import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { MongoClient } from 'mongodb';
import { publicProgress } from './progress.js';

const hash = token => createHash('sha256').update(token).digest('hex');
const publicProfile = profile => profile && ({ id: profile._id, name: profile.name, stats: profile.stats });
function guest(name) {
  const token = randomBytes(32).toString('base64url');
  return { token, profile: { _id: randomUUID(), tokenHash: hash(token), name, createdAt: new Date(),
    stats: { matches: 0, kills: 0, bestWave: 0, weaponXp: '0', essence: '0' } } };
}
function rewards(profile, player, result) {
  return { matches: profile.stats.matches + 1, kills: profile.stats.kills + player.kills,
    bestWave: Math.max(profile.stats.bestWave, result.completedWaves > 0 ? (result.startWave || 1) + result.completedWaves - 1 : 0),
    weaponXp: (BigInt(profile.stats.weaponXp) + BigInt(player.weaponXp)).toString(),
    essence: (BigInt(profile.stats.essence) + BigInt(player.essence)).toString() };
}
function progressed(previous, applied) {
  return { schemaVersion: 1, values: { ...(previous?.document?.values ?? {}),
    journey_v1: previous?.document?.values?.journey_v1 ?? applied.journey,
    champions_v1: applied.champions } };
}
export class MongoStore {
  constructor(uri, dbName) { this.client = new MongoClient(uri, { serverSelectionTimeoutMS: 5000, maxPoolSize: 10 }); this.db = this.client.db(dbName); }
  async open() {
    await this.client.connect();
    this.players = this.db.collection('players'); this.matches = this.db.collection('coop_matches');
    this.progress = this.db.collection('player_progress');
    await this.players.createIndex({ tokenHash: 1 }, { unique: true });
    await this.matches.createIndex({ 'players.id': 1, startedAt: -1 });
  }
  async ping() { await this.db.command({ ping: 1 }); }
  async createGuest(name) {
    const { token, profile } = guest(name); await this.players.insertOne(profile);
    return { token, player: publicProfile(profile) };
  }
  async authenticate(token) {
    if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(token)) return null;
    return publicProfile(await this.players.findOne({ tokenHash: hash(token) }));
  }
  async getPlayer(id) { return publicProfile(await this.players.findOne({ _id: id })); }
  async getProgress(id) { return publicProgress(await this.progress.findOne({ _id: id })); }
  async saveProgress(id, { baseRevision, mutationId, document }) {
    const fingerprint = hash(JSON.stringify({ baseRevision, document }));
    const previous = await this.progress.findOne({ _id: id });
    const receipt = previous?.receipts?.find(r => r.id === mutationId);
    if (receipt) return receipt.fingerprint === fingerprint
      ? { accepted: true, revision: receipt.revision }
      : { accepted: false, progress: publicProgress(previous) };
    if ((previous?.revision ?? 0) !== baseRevision) return { accepted: false, progress: publicProgress(previous) };
    const revision = baseRevision + 1, updatedAt = new Date();
    try {
      const saved = await this.progress.findOneAndUpdate({ _id: id, revision: baseRevision }, {
        $set: { revision, document, updatedAt },
        $push: {
          receipts: { $each: [{ id: mutationId, fingerprint, revision }], $slice: -32 },
          history: { $each: previous ? [publicProgress(previous)] : [], $slice: -3 },
        },
      }, { upsert: !previous, returnDocument: 'after', writeConcern: { w: 'majority' } });
      if (saved) return { accepted: true, revision };
    } catch (error) { if (error.code !== 11000) throw error; }
    // Includes simultaneous first writes and duplicate requests after a lost ACK.
    const current = await this.progress.findOne({ _id: id });
    const duplicate = current?.receipts?.find(r => r.id === mutationId && r.fingerprint === fingerprint);
    return duplicate ? { accepted: true, revision: duplicate.revision }
      : { accepted: false, progress: publicProgress(current) };
  }
  async beginMatch(id, code, players) {
    await this.matches.insertOne({ _id: id, roomCode: code, players, status: 'running', startedAt: new Date() });
  }
  async saveCoopProgress(event, apply) {
    const session = this.client.startSession();
    try {
      await session.withTransaction(async () => {
        const match = await this.matches.findOne({ _id: event.id }, { session });
        if (!match || event.states.length !== 2 || new Set(event.states.map(p => p.id)).size !== 2 ||
            !event.states.every(p => match.players.some(q => q.id === p.id && q.skin === p.state.self.skin))) throw new Error('Invalid progress participants');
        if ((match.progressSequence ?? 0) >= event.sequence) return;
        for (const player of event.states) {
          const previous = await this.progress.findOne({ _id: player.id }, { session });
          const applied = await apply(previous?.document?.values?.champions_v1, player.state, event.id);
          await this.progress.replaceOne({ _id: player.id }, { _id: player.id,
            revision: (previous?.revision ?? 0) + 1, updatedAt: new Date(),
            document: progressed(previous, applied), receipts: previous?.receipts ?? [],
            history: [...(previous?.history ?? []), ...(previous ? [publicProgress(previous)] : [])].slice(-3),
          }, { upsert: true, session });
        }
        await this.matches.updateOne({ _id: event.id }, { $set: { progressSequence: event.sequence } }, { session });
      }, { writeConcern: { w: 'majority' } });
    } finally { await session.endSession(); }
  }
  async finishMatch(result) {
    const session = this.client.startSession();
    try {
      await session.withTransaction(async () => {
        const match = await this.matches.findOne({ _id: result.id }, { session });
        if (!match) throw new Error('Unknown match');
        if (match.status === 'finished') return;
        if (result.players.length !== 2 || new Set(result.players.map(p => p.id)).size !== 2 || !result.players.every(p => match.players.some(q => q.id === p.id))) throw new Error('Invalid result participants');
        for (const player of result.players) {
          const profile = await this.players.findOne({ _id: player.id }, { session });
          if (!profile) throw new Error('Unknown player');
          await this.players.updateOne({ _id: player.id }, { $set: { stats: rewards(profile, player, result) } }, { session });
        }
        await this.matches.updateOne({ _id: result.id }, { $set: { status: 'finished', result, finishedAt: new Date() } }, { session });
      }, { writeConcern: { w: 'majority' } });
    } finally { await session.endSession(); }
  }
  async history(id, limit = 20) {
    const rows = await this.matches.find({ 'players.id': id }).sort({ startedAt: -1 }).limit(limit).toArray();
    return rows.map(({ _id, ...row }) => ({ id: _id, ...row }));
  }
  async close() { await this.client.close(); }
}

// Explicit test injection only. Production startup always constructs MongoStore.
export class MemoryStore {
  players = new Map(); matches = new Map(); progress = new Map();
  async open() {} async ping() {} async close() {}
  async createGuest(name) { const { token, profile } = guest(name); this.players.set(profile._id, profile); return { token, player: publicProfile(profile) }; }
  async authenticate(token) { if (typeof token !== 'string') return null; return publicProfile([...this.players.values()].find(p => p.tokenHash === hash(token))); }
  async getPlayer(id) { return publicProfile(this.players.get(id)); }
  async getProgress(id) { return publicProgress(this.progress.get(id)); }
  async saveProgress(id, { baseRevision, mutationId, document }) {
    const row = this.progress.get(id), fingerprint = hash(JSON.stringify({ baseRevision, document }));
    const duplicate = row?.receipts?.find(r => r.id === mutationId);
    if (duplicate?.fingerprint === fingerprint) return { accepted: true, revision: duplicate.revision };
    if (duplicate || (row?.revision ?? 0) !== baseRevision) return { accepted: false, progress: publicProgress(row) };
    const revision = baseRevision + 1;
    this.progress.set(id, { revision, document: structuredClone(document), updatedAt: new Date(),
      receipts: [...(row?.receipts ?? []), { id: mutationId, fingerprint, revision }].slice(-32) });
    return { accepted: true, revision };
  }
  async beginMatch(id, code, players) { if (this.matches.has(id)) throw new Error('Duplicate match'); this.matches.set(id, { id, roomCode: code, players, status: 'running', startedAt: new Date() }); }
  async saveCoopProgress(event, apply) {
    const match = this.matches.get(event.id);
    if (!match || event.states.length !== 2 || new Set(event.states.map(p => p.id)).size !== 2 ||
        !event.states.every(p => match.players.some(q => q.id === p.id && q.skin === p.state.self.skin))) throw new Error('Invalid progress participants');
    if ((match.progressSequence ?? 0) >= event.sequence) return;
    const updates = [];
    for (const player of event.states) {
      const previous = this.progress.get(player.id);
      const applied = await apply(previous?.document?.values?.champions_v1, player.state, event.id);
      updates.push([player.id, { revision: (previous?.revision ?? 0) + 1, updatedAt: new Date(),
        document: progressed(previous, applied), receipts: previous?.receipts ?? [] }]);
    }
    for (const [id, value] of updates) this.progress.set(id, value);
    match.progressSequence = event.sequence;
  }
  async finishMatch(result) {
    const match = this.matches.get(result.id); if (!match) throw new Error('Unknown match'); if (match.status === 'finished') return;
    for (const player of result.players) { const p = this.players.get(player.id); p.stats = rewards(p, player, result); }
    Object.assign(match, { result, status: 'finished' });
  }
  async history(id, limit = 20) { return [...this.matches.values()].filter(m => m.players.some(p => p.id === id)).reverse().slice(0, limit); }
}
