import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { WebSocket } from 'ws';
import { MemoryStore } from '../src/store.js';
import { startBackend } from '../src/server.js';
import { configFrom } from '../src/config.js';

const engineBin = fileURLToPath(new URL('../build/nfinit-engine', import.meta.url));
const config = { host: '127.0.0.1', port: 0, origins: new Set(), maxRooms: 5, reconnectMs: 1000, engineBin };
async function until(fn, ms = 5000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const value = await fn(); if (value) return value; await new Promise(r => setTimeout(r, 20)); }
  throw new Error('Timed out waiting for server state');
}
async function client(port) {
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`), messages = [];
  ws.on('message', raw => messages.push(JSON.parse(raw)));
  await new Promise((resolve, reject) => { ws.once('open', resolve); ws.once('error', reject); });
  return { ws, messages, send: m => ws.send(JSON.stringify(m)), state: () => messages.findLast(m => m.type === 'state'),
    identity: () => messages.find(m => m.type === 'identity'), error: code => messages.find(m => m.type === 'error' && m.code === code) };
}
test('Configuration requires MongoDB and rejects invalid capacity/port without exposing credentials', () => {
  assert.throws(() => configFrom({}), /MONGODB_URI/);
  assert.throws(() => configFrom({ MONGODB_URI: 'mongodb://localhost', PORT: '-1' }), /PORT/);
  assert.equal(configFrom({ MONGODB_URI: 'mongodb://localhost' }).maxRooms, 30);
});
test('Two real clients play co-op, reject a third, reconnect and persist one result', async t => {
  const store = new MemoryStore(), app = await startBackend({ config, store });
  t.after(() => app.close());
  const a = await client(app.port); t.after(() => a.ws.terminate());
  a.send({ type: 'join', name: 'Nyx', skin: 0 });
  await until(() => a.state());
  const code = a.state().code, identity = a.identity();
  assert.equal(a.state().maxPlayers, 2); assert.equal(a.state().coop, true);
  a.send({ type: 'start' }); await until(() => a.error('need_two_players'));
  const b = await client(app.port); t.after(() => b.ws.terminate());
  b.send({ type: 'join', code, name: 'Brum', skin: 2 });
  await until(() => b.state()?.humanCount === 2 && a.state()?.humanCount === 2);
  b.send({ type: 'start' }); await until(() => b.state()?.readyCount === 1);
  assert.equal(b.state().running, false);
  b.send({ type: 'ready', ready: false }); await until(() => b.state()?.readyCount === 0);
  const c = await client(app.port); t.after(() => c.ws.terminate());
  c.send({ type: 'join', code, name: 'Third', skin: 1 }); await until(() => c.error('room_unavailable'));
  a.send({ type: 'start', wave: 9999, health: 1e30 });
  await until(() => a.state()?.readyCount === 1);
  assert.equal(a.state().running, false);
  b.send({ type: 'start' });
  await until(() => a.state()?.running && b.state()?.running);
  assert.equal(a.state().wave, 1); assert.equal(a.state().hunter, false); assert.equal(b.state().hunter, false);
  assert.equal(a.state().combat, true); assert.equal(a.state().party.length, 2);
  const ax = a.state().self.x, by = b.state().self.y;
  a.send({ type: 'move', dx: -1, dy: 0 }); b.send({ type: 'move', dx: 0, dy: 1 });
  await until(() => a.state().self.x < ax - .003 && b.state().self.y > by + .003);
  a.send({ type: 'action', action: 'skill:0' });
  await until(() => a.state().minorSkillSerial > 0);
  b.send({ type: 'setHealth', health: 1e30 }); await until(() => b.error('invalid_message'));
  a.send({ type: 'move', dx: 0, dy: 0 }); b.send({ type: 'move', dx: 0, dy: 0 });
  a.ws.terminate();
  await until(() => b.state()?.paused && b.state()?.reconnecting);
  const elapsed = b.state().elapsed;
  await new Promise(r => setTimeout(r, 120)); assert.equal(b.state().elapsed, elapsed);
  const resumed = await client(app.port); t.after(() => resumed.ws.terminate());
  resumed.send({ type: 'join', code, token: identity.token, name: 'Forged name', skin: 3 });
  await until(() => resumed.state()?.running && !resumed.state()?.paused);
  assert.equal(resumed.state().id, identity.playerId); assert.equal(resumed.state().self.skin, 0);
  assert.equal(resumed.state().matchId, b.state().matchId);
  b.send({ type: 'leave' });
  await until(() => resumed.messages.some(m => m.type === 'roomClosed'));
  await until(() => store.matches.values().next().value?.status === 'finished');
  const me = await fetch(`http://127.0.0.1:${app.port}/api/me`, { headers: { authorization: `Bearer ${identity.token}` } }).then(r => r.json());
  assert.equal(me.player.stats.matches, 1);
  const match = [...store.matches.values()][0];
  await store.finishMatch(match.result); assert.equal((await store.getPlayer(identity.playerId)).stats.matches, 1);
  assert.equal((await store.history(identity.playerId)).length, 1);
});
test('Disconnect expiry closes the room and saves server-earned progress', async t => {
  const app = await startBackend({ config: { ...config, reconnectMs: 80 }, store: new MemoryStore() });
  t.after(() => app.close());
  const a = await client(app.port), b = await client(app.port);
  t.after(() => { a.ws.terminate(); b.ws.terminate(); });
  a.send({ type: 'join', name: 'A', skin: 1 }); await until(() => a.state());
  b.send({ type: 'join', name: 'B', skin: 3, code: a.state().code }); await until(() => b.state());
  a.send({ type: 'start' }); b.send({ type: 'start' }); await until(() => b.state()?.running);
  a.ws.terminate();
  await until(() => b.messages.some(m => m.type === 'roomClosed'));
  await until(() => app.pendingSaves.size === 0);
  assert.equal(app.rooms.size, 0);
});
test('HTTP profiles require bearer auth and WebSocket origins are checked', async t => {
  const app = await startBackend({ config, store: new MemoryStore() }); t.after(() => app.close());
  const base = `http://127.0.0.1:${app.port}`;
  assert.equal((await fetch(`${base}/api/me`)).status, 401);
  assert.equal((await fetch(`${base}/readyz`)).status, 200);
  const health = await fetch(`${base}/healthz`).then(r => r.json());
  assert.equal(health.backendVersion, '1.2.0');
  assert.equal(health.coopProtocol, 2);
  assert.equal(health.pvpProtocol, 1);
  assert.ok(health.capabilities.includes('hidden-target-immunity'));
  assert.ok(health.capabilities.includes('shared-checkpoint'));
  assert.ok(health.capabilities.includes('both-players-ready'));
  const guest = await fetch(`${base}/api/session`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: 'Friend' }) }).then(r => r.json());
  assert.ok(guest.token); assert.equal(guest.player.name, 'Friend'); assert.equal(guest.player.tokenHash, undefined);
  assert.equal((await fetch(`${base}/api/me`, { headers: { authorization: `Bearer ${guest.token}` } })).status, 200);
  assert.equal((await fetch(`${base}/healthz`, { headers: { origin: 'https://untrusted.invalid' } })).status, 403);
  const ws = new WebSocket(`ws://127.0.0.1:${app.port}/ws`, { origin: 'https://untrusted.invalid' });
  const error = await new Promise(resolve => ws.once('error', resolve)); assert.match(error.message, /403/);
});

test('50 and 75 start together at 51 with individual gear and both advance without losing higher progress', async t => {
  const store = new MemoryStore(), app = await startBackend({ config, store }); t.after(() => app.close());
  const profiles = await Promise.all([store.createGuest('Lower'), store.createGuest('Higher')]);
  for (const [i, profile] of profiles.entries()) {
    const champions = JSON.stringify({ championProgressVersion: 3, heroRosterVersion: 2,
      essence: 60, champions: Array.from({ length: 4 }, (_, skin) => ({ xp: skin === i ? 10000 * (i + 1) : 0,
        weapon: { xp: skin === i ? 500 * (i + 1) : 0 },
        ...(skin === i ? { dungeonCheckpoint: { wave: i ? 75 : 50, xp: 100, damage: 2, haste: 1, volley: 0 } } : {}),
      })) });
    await store.saveProgress(profile.player.id, { baseRevision: 0, mutationId: String(i).repeat(48),
      document: { schemaVersion: 1, values: { champions_v1: champions, name: profile.player.name } } });
  }
  const a = await client(app.port), b = await client(app.port); t.after(() => { a.ws.terminate(); b.ws.terminate(); });
  a.send({ type: 'join', token: profiles[0].token, skin: 0 }); await until(() => a.state());
  b.send({ type: 'join', token: profiles[1].token, skin: 1, code: a.state().code }); await until(() => b.state()?.humanCount === 2);
  assert.equal(b.state().coopStartWave, 51);
  a.send({ type: 'start', wave: 999 }); await until(() => a.state()?.readyCount === 1);
  assert.equal(a.state().running, false);
  b.send({ type: 'start' }); await until(() => a.state()?.running && b.state()?.running);
  assert.equal(a.state().startWave, 51); assert.equal(b.state().startWave, 51);
  assert.ok(a.state().championLevel > 1); assert.ok(b.state().championLevel > a.state().championLevel);
  assert.equal(a.state().damageUpgrades, 2); assert.equal(b.state().damageUpgrades, 2);
  const room = app.rooms.get(a.state().code), id = room.matchId;
  const event = { code: room.code, id, sequence: 100, states: profiles.map((p, skin) => ({ id: p.player.id,
    state: { mode: 'survival', demo: true, startWave: 51, completedWaves: 25,
      combatXp: 130, damageUpgrades: 3, hasteUpgrades: 1, volleyUpgrades: 0,
      weaponXpEarned: 5, lootEssenceEarned: 3, self: { skin } } })) };
  // Trusted worker event, never accepted from a WebSocket client.
  app.engine.emit('progress', event);
  await until(async () => (await store.getProgress(profiles[0].player.id)).revision > 1 && !app.pendingProgress.size);
  const saved = await Promise.all(profiles.map(p => store.getProgress(p.player.id)));
  for (const [skin, value] of saved.entries()) {
    const progress = JSON.parse(value.document.values.champions_v1);
    assert.equal(progress.champions[skin].dungeonCheckpoint.wave, 75);
    assert.equal(progress.bestWave, 75); assert.ok(progress.essence > 60);
    assert.equal(value.document.values.name, profiles[skin].player.name);
  }
  app.engine.emit('progress', event);
  await until(() => !app.pendingProgress.size);
  assert.deepEqual(await Promise.all(profiles.map(p => store.getProgress(p.player.id))), saved);
  const next = { ...event, sequence: 101, states: event.states.map(p => ({ ...p,
    state: { ...p.state, completedWaves: 50, weaponXpEarned: 9, lootEssenceEarned: 6 } })) };
  app.engine.emit('progress', next);
  await until(async () => JSON.parse((await store.getProgress(profiles[1].player.id)).document.values.champions_v1).champions[1].dungeonCheckpoint.wave === 100);
  for (const [skin, profile] of profiles.entries()) {
    assert.equal(JSON.parse((await store.getProgress(profile.player.id)).document.values.champions_v1).champions[skin].dungeonCheckpoint.wave, 100);
  }
});

test('PvP rooms require matching mode, two ready players, reconnect and persist a separate forfeit result', async t => {
  const store = new MemoryStore(), app = await startBackend({ config, store });
  t.after(() => app.close());
  const a = await client(app.port), b = await client(app.port), c = await client(app.port);
  t.after(() => { a.ws.terminate(); b.ws.terminate(); c.ws.terminate(); });
  a.send({ type: 'join', mode: 'pvp', name: 'Nyx', skin: 0 });
  await until(() => a.state());
  const code = a.state().code, identity = a.identity();
  assert.equal(a.state().mode, 'pvp'); assert.equal(a.state().pvp, true);
  assert.equal(a.state().coop, false); assert.equal(a.state().pvpRulesVersion, 1);
  assert.equal(a.state().coopStartWave, undefined);
  c.send({ type: 'join', mode: 'coop', code, name: 'Wrong mode', skin: 1 });
  await until(() => c.error('room_mode_mismatch'));
  b.send({ type: 'join', mode: 'pvp', code, name: 'Brum', skin: 2 });
  await until(() => b.state()?.humanCount === 2);
  c.send({ type: 'join', mode: 'pvp', code, name: 'Third', skin: 1 });
  await until(() => c.error('room_unavailable'));
  a.send({ type: 'ready', ready: true });
  await until(() => a.state()?.readyCount === 1);
  assert.equal(a.state().running, false);
  a.send({ type: 'ready', ready: false });
  await until(() => a.state()?.readyCount === 0);
  a.send({ type: 'start', wave: 999, health: 999999 });
  b.send({ type: 'start' });
  await until(() => a.state()?.running && b.state()?.running);
  assert.equal(a.state().duration, 120); assert.equal(a.state().self.health, 100);
  assert.equal(b.state().self.health, 100); assert.equal(a.state().party.length, 2);
  assert.equal(a.state().hunters, 0);
  const before = await Promise.all([identity.playerId, b.identity().playerId].map(id => store.getProgress(id)));
  const firstMatch = a.state().matchId;
  // Exercise the ordinary result/rematch path without waiting for the 120s timer.
  await app.engine.command('finish', { code, forfeitId: b.state().id, reason: 'Test completed duel' });
  await until(() => a.state()?.ended && a.state()?.rewardsSaved);
  a.send({ type: 'ready', ready: true }); b.send({ type: 'ready', ready: true });
  await until(() => a.state()?.running && a.state()?.matchId !== firstMatch);
  assert.equal(a.state().pvp, true); assert.equal(a.state().self.health, 100);
  assert.equal(b.state().self.health, 100);
  const matchId = a.state().matchId;
  a.ws.terminate();
  await until(() => b.state()?.paused && b.state()?.reconnecting);
  const resumed = await client(app.port); t.after(() => resumed.ws.terminate());
  resumed.send({ type: 'join', mode: 'pvp', code, token: identity.token, skin: 3 });
  await until(() => resumed.state()?.running && !resumed.state()?.paused);
  assert.equal(resumed.state().pvp, true); assert.equal(resumed.state().matchId, matchId);
  assert.equal(resumed.state().self.skin, 0);
  b.send({ type: 'leave' });
  await until(() => store.matches.get(matchId)?.status === 'finished');
  const result = store.matches.get(matchId).result;
  assert.equal(result.mode, 'pvp'); assert.equal(result.winnerId, identity.playerId);
  const winner = (await store.getPlayer(identity.playerId)).stats;
  assert.equal(winner.pvpWins, 2); assert.equal(winner.pvpMatches, 2);
  assert.equal((await store.getPlayer(b.identity().playerId)).stats.pvpWins, 0);
  assert.equal(winner.matches, 0); assert.equal(winner.weaponXp, '0');
  assert.deepEqual(await Promise.all([identity.playerId, b.identity().playerId].map(id => store.getProgress(id))), before);
  await store.finishMatch(result);
  assert.equal((await store.getPlayer(identity.playerId)).stats.pvpMatches, 2);
  await assert.rejects(store.saveCoopProgress({ id: matchId, states: [] }, () => { throw new Error('must not run'); }));
});

test('PvP disconnect expiry awards the connected opponent after grace period', async t => {
  const store = new MemoryStore(), app = await startBackend({ config: { ...config, reconnectMs: 100 }, store });
  t.after(() => app.close());
  const a = await client(app.port), b = await client(app.port);
  t.after(() => { a.ws.terminate(); b.ws.terminate(); });
  a.send({ type: 'join', mode: 'pvp', name: 'A', skin: 1 }); await until(() => a.state());
  b.send({ type: 'join', mode: 'pvp', name: 'B', skin: 3, code: a.state().code }); await until(() => b.state());
  a.send({ type: 'start' }); b.send({ type: 'start' }); await until(() => b.state()?.running);
  const id = b.state().matchId, survivor = b.state().id;
  a.ws.terminate();
  await until(() => store.matches.get(id)?.status === 'finished');
  assert.equal(store.matches.get(id).result.winnerId, survivor);
});
