import http from 'node:http';
import { readFileSync } from 'node:fs';
import { randomInt, randomUUID } from 'node:crypto';
import { WebSocketServer, WebSocket } from 'ws';
import { Engine } from './engine.js';
import { validProgressWrite } from './progress.js';
import { StateFrames } from './state-frames.js';
import { monitorEventLoopDelay } from 'node:perf_hooks';

const { version: backendVersion } = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const protocol = { backendVersion, coopProtocol: 2, pvpProtocol: 1, stateProtocol: 1,
  capabilities: ['shared-checkpoint', 'both-players-ready', 'shared-champion-progress', 'pvp-1v1', 'hidden-target-immunity', 'delta-state-frames', 'websocket-compression'] };

class Problem extends Error { constructor(code, status = 400) { super(code); this.code = code; this.status = status; } }
const nameOf = value => typeof value === 'string' && value.trim() ? value.trim().slice(0, 16) : 'Player';
const finite = value => typeof value === 'number' && Number.isFinite(value) && Math.abs(value) <= 10;
const actions = new Set(['dash', 'power', 'shoot', 'interact', 'decoy', 'listen', 'skill:0', 'skill:1', 'skill:2', 'upgrade:damage', 'upgrade:haste', 'upgrade:volley']);
function inputOf(m) {
  if (m.type === 'move' && finite(m.dx) && finite(m.dy)) return { type: 'move', dx: Math.max(-1, Math.min(1, m.dx)), dy: Math.max(-1, Math.min(1, m.dy)) };
  if (m.type === 'voice' && typeof m.running === 'boolean') return { type: 'voice', running: m.running };
  if (m.type === 'action' && actions.has(m.action)) {
    if ('targetX' in m || 'targetY' in m) {
      if (!finite(m.targetX) || !finite(m.targetY)) throw new Problem('invalid_target');
      return { type: 'action', action: m.action, targetX: m.targetX, targetY: m.targetY };
    }
    return { type: 'action', action: m.action };
  }
  throw new Problem('invalid_message');
}
function send(ws, message) {
  if (!ws || ws.readyState !== WebSocket.OPEN) return;
  if (ws.peer) ws.peer.maxBufferedBytes = Math.max(ws.peer.maxBufferedBytes, ws.bufferedAmount);
  if (ws.bufferedAmount > 1024 * 1024) { if (ws.peer) ws.peer.closeReason = 'send_backpressure'; ws.terminate(); return; }
  if (message.type === 'state' && ws.bufferedAmount > 128 * 1024) { if (ws.peer) ws.peer.skippedStates++; return; }
  const payload = JSON.stringify(message.type === 'state' && ws.peer?.frames ? ws.peer.frames.encode(message) : message);
  if (ws.peer) { ws.peer.bytesSent += Buffer.byteLength(payload); ws.peer.messagesSent++; }
  ws.send(payload, () => {});
}
async function jsonBody(req, limit = 8192) {
  let size = 0; const chunks = [];
  for await (const chunk of req) { size += chunk.length; if (size > limit) throw new Problem('payload_too_large', 413); chunks.push(chunk); }
  try { const value = JSON.parse(Buffer.concat(chunks).toString()); if (!value || Array.isArray(value) || typeof value !== 'object') throw 0; return value; }
  catch { throw new Problem('invalid_json'); }
}

export async function startBackend({ config, store, engine = new Engine(), logger = console }) {
  const rooms = new Map(), reservations = new Map(), pendingSaves = new Map(), pendingProgress = new Map(), limits = new Map();
  let shuttingDown = false, retrying = false, engineTiming = null;
  const log = (event, fields = {}) => logger.error(JSON.stringify({ event, ...fields })); // Deliberately excludes URIs and tokens.
  function rate(key, max, windowMs) {
    const now = Date.now(); let entry = limits.get(key);
    if (!entry || now >= entry.until) { if (limits.size > 10000) throw new Problem('server_busy', 503); entry = { count: 0, until: now + windowMs }; limits.set(key, entry); }
    if (++entry.count > max) throw new Problem('rate_limited', 429);
  }
  function codeOf() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; let code;
    do { code = Array.from({ length: 5 }, () => alphabet[randomInt(alphabet.length)]).join(''); } while (rooms.has(code));
    return code;
  }
  function decorate(room, state) {
    const connected = [...room.members.values()].filter(m => m.socket?.readyState === WebSocket.OPEN).length;
    return { ...state, coop: room.mode !== 'pvp', pvp: room.mode === 'pvp',
      ...(room.mode === 'pvp' ? { pvpRulesVersion: 1 } : {}),
      coopProtocol: protocol.coopProtocol, maxPlayers: 2, humanCount: room.members.size,
      connectedPlayers: connected, reconnecting: connected < room.members.size,
      readyCount: [...room.members.values()].filter(m => m.ready).length,
      ready: room.members.get(state.id)?.ready === true, starting: room.busy,
      ...(room.mode !== 'pvp' ? { coopStartWave: Math.min(...[...room.members.values()].map(m => checkpointOf(m) + 1)) } : {}),
      matchId: room.matchId || null, rewardsSaved: room.matchId ? room.saved.has(room.matchId) : false,
      party: state.party?.map(p => ({ ...p, ready: room.members.get(p.id)?.ready === true,
        checkpointWave: checkpointOf(room.members.get(p.id)),
        connected: !!room.members.get(p.id)?.socket && room.members.get(p.id).socket.readyState === WebSocket.OPEN })),
    };
  }
  function checkpointOf(member) {
    if (member?.checkpointProgress === member?.progress && member?.checkpointWave != null) return member.checkpointWave;
    let wave = 0;
    try {
      const raw = JSON.parse(member?.progress?.document?.values?.champions_v1 ?? '{}');
      const value = raw.champions?.[member.skin]?.dungeonCheckpoint?.wave;
      wave = Number.isSafeInteger(value) && value > 0 && value % 25 === 0 ? value : 0;
    } catch {}
    if (member) { member.checkpointProgress = member.progress; member.checkpointWave = wave; }
    return wave;
  }
  function publishLobby(room) {
    for (const [id, state] of room.last) send(room.members.get(id)?.socket, decorate(room, state));
  }
  function clearReady(room) { for (const member of room.members.values()) member.ready = false; }
  async function savePending() {
    if (retrying) return; retrying = true;
    try {
      for (const [id, item] of pendingProgress) {
        try {
          await store.saveCoopProgress(item.event, (champions, state, runId) =>
            engine.command('rewardProgress', { champions: champions ?? null, state, runId }));
          if (pendingProgress.get(id) === item) pendingProgress.delete(id);
          for (const member of item.room.members.values()) {
            member.progress = await store.getProgress(member.player.id);
            send(member.socket, { type: 'progressSaved', matchId: id, sequence: item.event.sequence });
          }
          publishLobby(item.room);
        } catch { log('champion_progress_save_pending'); }
      }
      for (const [id, item] of pendingSaves) {
        if (pendingProgress.has(id)) continue;
        try {
          await store.finishMatch(item.result); pendingSaves.delete(id); item.room.saved.add(id);
          for (const member of item.room.members.values()) send(member.socket, { type: 'matchSaved', matchId: id, rewardsSaved: true });
        } catch { log('match_save_pending'); }
      }
    } finally { retrying = false; }
  }
  function queueSave(room, result) {
    if (!room.saved.has(result.id)) pendingSaves.set(result.id, { room, result });
    void savePending();
  }
  function fallbackResult(room, reason, forfeitId) {
    const states = [...room.last.values()];
    return { id: room.matchId, roomCode: room.code, outcome: reason, mode: room.mode,
      ...(room.mode === 'pvp' ? { winnerId: states.find(s => s.ended)?.winner ?? (forfeitId ? [...room.members.keys()].find(id => id !== forfeitId) : 'abandoned') } : {}),
      wave: states[0]?.wave || 1, completedWaves: states[0]?.completedWaves || 0, startWave: states[0]?.startWave || 1,
      elapsed: states[0]?.elapsed || 0,
      players: [...room.members.values()].map(m => {
        const state = room.last.get(m.player.id);
        return { id: m.player.id, name: m.player.name, skin: m.skin, kills: state?.kills || 0,
          weaponXp: String(state?.weaponXpEarned || 0), essence: String(state?.lootEssenceEarned || 0) };
      }) };
  }
  async function closeRoom(room, reason, forfeitId) {
    if (room.closing) return; room.closing = true;
    if (room.mode === 'pvp' && ![...room.members.values()].some(m => m.player.id !== forfeitId && m.socket?.readyState === WebSocket.OPEN)) forfeitId = undefined;
    if (engine.ready) {
      try { await engine.command('finish', { code: room.code, reason, forfeitId }); } catch {}
    }
    if (room.matchId && !room.saved.has(room.matchId) && !pendingSaves.has(room.matchId)) queueSave(room, fallbackResult(room, reason, forfeitId));
    rooms.delete(room.code);
    for (const member of room.members.values()) {
      clearTimeout(member.expiry); reservations.delete(member.player.id);
      send(member.socket, { type: 'roomClosed', code: 'coop_room_closed', message: reason });
      member.socket?.close(1000, 'Room closed');
    }
    if (engine.ready) await engine.command('destroy', { code: room.code }).catch(() => {});
  }
  engine.on('message', ({ code, to, message }) => {
    const room = rooms.get(code); if (!room) return;
    if (message.type === 'state') room.last.set(to, message);
    send(room.members.get(to)?.socket, message.type === 'state' ? decorate(room, message) : message);
  });
  engine.on('result', ({ code, result }) => { const room = rooms.get(code); if (room && result.id === room.matchId) { clearReady(room); queueSave(room, result); } });
  engine.on('progress', event => {
    const room = rooms.get(event.code); if (!room || room.mode === 'pvp' || event.id !== room.matchId) return;
    if (event.sequence > (pendingProgress.get(event.id)?.event.sequence ?? 0)) {
      pendingProgress.set(event.id, { room, event }); void savePending();
    }
  });
  engine.on('metrics', value => { const { tickMeanMs, tickP95Ms, tickMaxMs, callbackMaxMs, roomCount } = value; engineTiming = { tickMeanMs, tickP95Ms, tickMaxMs, callbackMaxMs, roomCount }; });
  engine.on('engineError', ({ code }) => { const room = rooms.get(code); if (room) void closeRoom(room, 'Game engine stopped. Rejoin a new room.'); });
  engine.on('lost', () => { if (!shuttingDown) { log('engine_stopped'); for (const room of rooms.values()) void closeRoom(room, 'Game engine stopped. Start a new room.'); } });

  async function join(peer, message) {
    if (peer.member) throw new Problem('already_joined');
    rate(`join:${peer.ip}`, 30, 60000);
    const code = typeof message.code === 'string' ? message.code.trim().toUpperCase() : '';
    if (code && !/^[A-Z2-9]{5}$/.test(code)) throw new Problem('room_not_found');
    let room = code ? rooms.get(code) : null;
    if (code && !room) throw new Problem('room_not_found');
    const mode = message.mode ?? 'coop';
    peer.frames = message.stateProtocol === 1 ? new StateFrames() : null;
    if (!['coop', 'pvp'].includes(mode)) throw new Problem('invalid_mode');
    if (room && room.mode !== mode) throw new Problem('room_mode_mismatch');
    if (!Number.isInteger(message.skin ?? 0) || message.skin < 0 || message.skin > 3) throw new Problem('invalid_champion');
    let player, token;
    if (message.token) { player = await store.authenticate(message.token); if (!player) throw new Problem('invalid_token', 401); }
    else { const guest = await store.createGuest(nameOf(message.name)); player = guest.player; token = guest.token; }
    const progress = await store.getProgress(player.id);
    if (peer.socket.readyState !== WebSocket.OPEN) return;
    const reserved = reservations.get(player.id);
    if (reserved && reserved !== code) throw new Problem('already_in_room');
    if (!room) {
      if (rooms.size >= config.maxRooms) throw new Problem('server_full', 503);
      room = { code: codeOf(), mode, members: new Map(), last: new Map(), matchId: null, saved: new Set(), closing: false, busy: false };
      rooms.set(room.code, room);
    }
    if (room.closing) throw new Problem('room_unavailable');
    let member = room.members.get(player.id);
    const reconnect = !!member;
    if (member?.socket?.readyState === WebSocket.OPEN) throw new Problem('already_connected');
    if (!member && (room.members.size >= 2 || room.matchId)) throw new Problem('room_unavailable');
    if (!member) { member = { player, skin: message.skin ?? 0, socket: peer.socket, ready: false,
      progress }; room.members.set(player.id, member); clearReady(room); }
    else { clearTimeout(member.expiry); member.socket = peer.socket; }
    peer.member = member; peer.room = room; reservations.set(player.id, room.code);
    clearTimeout(peer.joinTimeout);
    send(peer.socket, { type: 'identity', protocol: protocol.coopProtocol, playerId: player.id, ...(token ? { token } : {}) });
    try {
      if (!reconnect) await engine.command('join', { code: room.code, playerId: player.id, name: player.name, skin: member.skin, mode: room.mode });
      const allHere = [...room.members.values()].every(m => m.socket?.readyState === WebSocket.OPEN);
      await engine.command('pause', { code: room.code, paused: !allHere });
    } catch { await closeRoom(room, 'Cannot open the game room. Please retry.'); throw new Problem('engine_unavailable', 503); }
  }
  async function handle(peer, m) {
    if (!m || Array.isArray(m) || typeof m !== 'object') throw new Problem('invalid_message');
    if (m.type === 'join') return join(peer, m);
    const room = peer.room, member = peer.member;
    if (!room || !member || room.closing || member.socket !== peer.socket) throw new Problem('not_joined');
    if (m.type === 'resync' && peer.frames) {
      if (Date.now() - (peer.lastResync ?? 0) < 1000) return;
      peer.lastResync = Date.now(); peer.frames = new StateFrames(); publishLobby(room); return;
    }
    if (m.type === 'leave') return closeRoom(room, room.mode === 'pvp' ? 'Opponent left the duel. Remaining player wins.' : 'A teammate left the room.', member.player.id);
    if (m.type === 'start' || m.type === 'ready') {
      if (m.type === 'ready' && typeof m.ready !== 'boolean') throw new Problem('invalid_message');
      if (room.busy) throw new Problem('start_pending');
      if (room.members.size !== 2 || [...room.members.values()].some(p => p.socket?.readyState !== WebSocket.OPEN)) throw new Problem('need_two_players');
      if ([...room.last.values()].some(s => s.running)) throw new Problem('already_running');
      if (room.matchId && !room.saved.has(room.matchId)) throw new Problem('save_pending');
      member.ready = m.type === 'start' || m.ready;
      publishLobby(room);
      if (![...room.members.values()].every(p => p.ready)) return;
      room.busy = true;
      publishLobby(room);
      try {
        await store.ping();
        const progress = {};
        for (const participant of room.members.values()) {
          participant.progress = await store.getProgress(participant.player.id);
          progress[participant.player.id] = participant.progress.document?.values?.champions_v1 ?? null;
        }
        if ([...room.members.values()].some(p => !p.ready || p.socket?.readyState !== WebSocket.OPEN)) return;
        const runId = randomUUID();
        await store.beginMatch(runId, room.code, [...room.members.values()].map(m => ({ id: m.player.id, name: m.player.name, skin: m.skin })), room.mode);
        room.matchId = runId;
        await engine.command('start', { code: room.code, playerId: [...room.members.keys()][0], runId, progress });
        await engine.command('pause', { code: room.code, paused: [...room.members.values()].some(p => p.socket?.readyState !== WebSocket.OPEN) });
      } catch (error) { clearReady(room); throw error; }
      finally { room.busy = false; publishLobby(room); }
      return;
    }
    await engine.command('input', { code: room.code, playerId: member.player.id, input: inputOf(m) });
  }
  function disconnected(peer) {
    clearTimeout(peer.joinTimeout);
    const room = peer.room, member = peer.member;
    if (!room || !member || room.closing || member.socket !== peer.socket) return;
    member.socket = null;
    clearReady(room);
    publishLobby(room);
    void engine.command('pause', { code: room.code, paused: true }).catch(() => closeRoom(room, 'Engine unavailable.'));
    member.expiry = setTimeout(() => void closeRoom(room, room.mode === 'pvp' ? 'Opponent did not reconnect. Remaining player wins.' : 'Reconnect time expired. The co-op run ended.', member.player.id), config.reconnectMs);
    member.expiry.unref();
  }

  // Bound zlib work/memory; negotiate compression with native clients, including build 20.
  const wss = new WebSocketServer({ noServer: true, maxPayload: 4096,
    perMessageDeflate: { threshold: 1024, serverNoContextTakeover: true,
      clientNoContextTakeover: true, concurrencyLimit: 4,
      zlibDeflateOptions: { level: 1, memLevel: 7 } } });
  const loopDelay = monitorEventLoopDelay({ resolution: 20 }); loopDelay.enable();
  const server = http.createServer(async (req, res) => {
    res.setHeader('Content-Type', 'application/json'); res.setHeader('Cache-Control', 'no-store'); res.setHeader('X-Content-Type-Options', 'nosniff');
    const reply = (status, body) => { res.writeHead(status); res.end(JSON.stringify(body)); };
    try {
      const origin = req.headers.origin;
      if (origin && !config.origins.has(origin)) throw new Problem('origin_not_allowed', 403);
      if (origin) { res.setHeader('Access-Control-Allow-Origin', origin); res.setHeader('Vary', 'Origin'); }
      res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type'); res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS');
      if (req.method === 'OPTIONS') return reply(204, {});
      rate(`http:${req.socket.remoteAddress}`, 120, 60000);
      const path = new URL(req.url, 'http://localhost').pathname;
      if (path === '/health' || path === '/healthz') return reply(200, { ok: true, service: 'nfinit-coop', rooms: rooms.size, maxPlayers: 2, ...protocol,
        runtime: { eventLoopDelayP95Ms: Math.round(loopDelay.percentile(95) / 1e6),
          enginePendingCommands: engine.pending?.size ?? 0,
          connectedPlayers: wss.clients.size, simulation: engineTiming } });
      if (path === '/readyz') { if (!engine.ready || shuttingDown) throw new Problem('not_ready', 503); await store.ping(); return reply(200, { ok: true, ...protocol }); }
      if (path === '/api/session' && req.method === 'POST') {
        rate(`guest:${req.socket.remoteAddress}`, 10, 60000);
        return reply(201, await store.createGuest(nameOf((await jsonBody(req)).name)));
      }
      const token = req.headers.authorization?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1];
      const player = await store.authenticate(token);
      if (!player) throw new Problem('unauthorized', 401);
      if (path === '/api/progress' && req.method === 'GET') return reply(200, { progress: await store.getProgress(player.id) });
      if (path === '/api/progress' && req.method === 'PUT') {
        const body = await jsonBody(req, 300 * 1024);
        if (!validProgressWrite(body)) throw new Problem('invalid_progress');
        const result = await store.saveProgress(player.id, body);
        return reply(result.accepted ? 200 : 409, result);
      }
      if (path === '/api/me' && req.method === 'GET') return reply(200, { player });
      if (path === '/api/matches' && req.method === 'GET') return reply(200, { matches: await store.history(player.id) });
      throw new Problem('not_found', 404);
    } catch (error) { reply(error instanceof Problem ? error.status : 503, { error: error instanceof Problem ? error.code : 'service_unavailable' }); }
  });
  server.requestTimeout = 10000; server.headersTimeout = 10000;
  server.on('upgrade', (req, socket, head) => {
    if (req.url !== '/ws' || shuttingDown || !engine.ready || wss.clients.size >= config.maxRooms * 2 + 20 || (req.headers.origin && !config.origins.has(req.headers.origin))) {
      socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n'); return;
    }
    wss.handleUpgrade(req, socket, head, ws => wss.emit('connection', ws, req));
  });
  wss.on('connection', (socket, req) => {
    const peer = { socket, ip: req.socket.remoteAddress, queue: Promise.resolve(), count: 0, window: Date.now(), alive: true, bytesSent: 0, messagesSent: 0, skippedStates: 0, maxBufferedBytes: 0 };
    peer.joinTimeout = setTimeout(() => { if (!peer.member) socket.close(1008, 'Join timeout'); }, 10000);
    socket.on('pong', () => { peer.alive = true; }); socket.peer = peer;
    socket.on('error', () => {});
    socket.on('close', (code) => {
      log('socket_closed', { code, bufferedBytes: socket.bufferedAmount, bytesSent: peer.bytesSent, messagesSent: peer.messagesSent, skippedStates: peer.skippedStates, maxBufferedBytes: peer.maxBufferedBytes, reason: peer.closeReason ?? 'transport_closed' });
      disconnected(peer);
    });
    socket.on('message', (raw, binary) => {
      peer.alive = true; // Real incoming input proves life even if a mobile pong is delayed.
      if (Date.now() - peer.window >= 1000) { peer.window = Date.now(); peer.count = 0; }
      if (binary || ++peer.count > 140) { peer.closeReason = 'input_rate_limit'; socket.close(1008, 'Message limit exceeded'); return; }
      let value;
      try { value = JSON.parse(raw.toString()); } catch { send(socket, { type: 'error', code: 'invalid_json', message: 'Invalid game message.' }); return; }
      peer.queue = peer.queue.then(() => handle(peer, value)).catch(error => send(socket, {
        type: 'error', code: error instanceof Problem ? error.code : 'service_unavailable', message: error instanceof Problem ? error.code.replaceAll('_', ' ') : 'Service temporarily unavailable.',
      }));
    });
  });
  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) { if (!ws.peer.alive) { ws.peer.closeReason = 'heartbeat_timeout'; ws.terminate(); } else { ws.peer.alive = false; ws.ping(); } }
    for (const [key, entry] of limits) if (Date.now() >= entry.until) limits.delete(key);
  }, 20000); heartbeat.unref();
  const retry = setInterval(() => void savePending(), 2000); retry.unref();
  try { await store.open(); await engine.open(config.engineBin); await new Promise((resolve, reject) => { server.once('error', reject); server.listen(config.port, config.host, resolve); }); }
  catch (error) { loopDelay.disable(); clearInterval(heartbeat); clearInterval(retry); await engine.close(); await store.close(); throw error; }
  return { server, rooms, engine, pendingSaves, pendingProgress, port: server.address().port,
    async close() {
      shuttingDown = true; loopDelay.disable(); clearInterval(heartbeat); clearInterval(retry);
      await Promise.all([...rooms.values()].map(room => closeRoom(room, 'Server restarting.')));
      for (let i = 0; i < 10 && (pendingSaves.size || pendingProgress.size || retrying); i++) { await savePending(); if (pendingSaves.size || pendingProgress.size || retrying) await new Promise(r => setTimeout(r, 200)); }
      if (pendingSaves.size) log('unsaved_results_at_shutdown');
      for (const ws of wss.clients) ws.terminate();
      await new Promise(resolve => wss.close(resolve)); await new Promise(resolve => server.close(resolve));
      await engine.close(); await store.close();
    },
  };
}
