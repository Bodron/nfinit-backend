import test from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryReplSet } from 'mongodb-memory-server';
import { MongoStore } from '../src/store.js';
import { startBackend } from '../src/server.js';
import { WebSocket } from 'ws';
import { fileURLToPath } from 'node:url';

async function until(check) {
  for (let i = 0; i < 200; i++) { if (await check()) return; await new Promise(r => setTimeout(r, 20)); }
  throw new Error('Mongo/WebSocket integration timed out');
}
async function peer(port) {
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`), messages = [];
  ws.on('message', raw => messages.push(JSON.parse(raw)));
  await new Promise((resolve, reject) => { ws.once('open', resolve); ws.once('error', reject); });
  return { ws, send: m => ws.send(JSON.stringify(m)), state: () => messages.findLast(m => m.type === 'state') };
}

test('Real MongoDB transactions persist profiles and apply a match exactly once', { timeout: 240000 }, async () => {
  const mongo = await MongoMemoryReplSet.create({ replSet: { count: 1 } });
  const store = new MongoStore(mongo.getUri(), 'nfinit_coop_test');
  try {
    await store.open();
    const a = await store.createGuest('Nyx'), b = await store.createGuest('Brum');
    const document = { schemaVersion: 1, values: { champions_v1: 'exact-save-999999999999999999999999', journey_v1: 'journey' } };
    const write = { baseRevision: 0, mutationId: 'a'.repeat(48), document };
    const copies = await Promise.all([store.saveProgress(a.player.id, write), store.saveProgress(a.player.id, write)]);
    assert.deepEqual(copies, [{ accepted: true, revision: 1 }, { accepted: true, revision: 1 }]);
    const contested = await Promise.all(['b', 'c'].map(id => store.saveProgress(a.player.id, {
      ...write, baseRevision: 1, mutationId: id.repeat(48), document: { ...document, values: { ...document.values, name: id } },
    })));
    assert.equal(contested.filter(r => r.accepted).length, 1);
    assert.equal((await store.getProgress(a.player.id)).revision, 2);
    assert.equal((await store.getProgress(b.player.id)).document, null);
    assert.equal((await store.authenticate(a.token)).id, a.player.id);
    assert.equal(await store.authenticate('invalid'), null);
    assert.equal((await store.getPlayer(a.player.id)).tokenHash, undefined);
    const id = 'mongo-transaction-test';
    const players = [a.player, b.player].map((p, i) => ({ id: p.id, skin: i, name: p.name }));
    await store.beginMatch(id, 'ABCDE', players);
    const result = { id, outcome: 'hunters', completedWaves: 128, wave: 129,
      players: players.map(p => ({ ...p, kills: 45, weaponXp: '9999999999999999999999999999999999999', essence: '125' })) };
    await Promise.all([store.finishMatch(result), store.finishMatch(result)]);
    assert.deepEqual((await store.getPlayer(a.player.id)).stats, { matches: 1, kills: 45, bestWave: 128, weaponXp: result.players[0].weaponXp, essence: '125' });
    await store.close();
    const reopened = new MongoStore(mongo.getUri(), 'nfinit_coop_test');
    try {
      await reopened.open(); assert.equal((await reopened.authenticate(a.token)).id, a.player.id);
      assert.equal((await reopened.getProgress(a.player.id)).revision, 2);
      assert.equal((await reopened.saveProgress(a.player.id, write)).revision, 1);
      assert.equal((await reopened.getProgress(a.player.id)).document.values.champions_v1, document.values.champions_v1);
      assert.equal((await reopened.history(a.player.id))[0].status, 'finished');
      await reopened.finishMatch(result); assert.equal((await reopened.getPlayer(b.player.id)).stats.matches, 1);
    } finally { await reopened.close(); }
    const online = new MongoStore(mongo.getUri(), 'nfinit_coop_test');
    const app = await startBackend({ config: { host: '127.0.0.1', port: 0,
      origins: new Set(), maxRooms: 2, reconnectMs: 1000,
      engineBin: fileURLToPath(new URL('../build/nfinit-engine', import.meta.url)) }, store: online });
    let host, friend;
    try {
      host = await peer(app.port); friend = await peer(app.port);
      host.send({ type: 'join', token: a.token, skin: 0 }); await until(() => host.state());
      friend.send({ type: 'join', token: b.token, skin: 2, code: host.state().code }); await until(() => friend.state());
      host.send({ type: 'start' }); friend.send({ type: 'start' }); await until(() => friend.state()?.running);
      assert.equal(friend.state().coop, true); assert.equal(friend.state().hunter, false);
      friend.send({ type: 'leave' });
      await until(async () => (await online.getPlayer(a.player.id)).stats.matches === 2);
      assert.equal((await online.getPlayer(b.player.id)).stats.matches, 2);
      const history = await online.history(a.player.id);
      assert.equal(history.length, 2); assert.equal(history[0].status, 'finished');
      const progressPlayers = [{ id: a.player.id, skin: 0 }, { id: b.player.id, skin: 2 }];
      await online.beginMatch('atomic-progress', 'PROGR', progressPlayers);
      const event = { id: 'atomic-progress', sequence: 1, states: progressPlayers.map(p => ({ id: p.id,
        state: { mode: 'survival', demo: true, startWave: 1, completedWaves: 25,
          combatXp: 100, damageUpgrades: 2, hasteUpgrades: 1, volleyUpgrades: 0,
          weaponXpEarned: 7, lootEssenceEarned: 3, self: { skin: p.skin } } })) };
      const beforeProgress = await Promise.all(progressPlayers.map(p => online.getProgress(p.id)));
      let calls = 0;
      await assert.rejects(online.saveCoopProgress(event, async (champions, state, runId) => {
        if (++calls === 2) throw new Error('Injected second champion failure');
        return app.engine.command('rewardProgress', { champions, state, runId });
      }));
      assert.deepEqual(await Promise.all(progressPlayers.map(p => online.getProgress(p.id))), beforeProgress);
      const apply = (champions, state, runId) => app.engine.command('rewardProgress', { champions, state, runId });
      await Promise.all([online.saveCoopProgress(event, apply), online.saveCoopProgress(event, apply)]);
      const afterProgress = await Promise.all(progressPlayers.map(p => online.getProgress(p.id)));
      for (const [i, value] of afterProgress.entries()) {
        assert.equal(value.revision, beforeProgress[i].revision + 1);
        assert.equal(JSON.parse(value.document.values.champions_v1).champions[progressPlayers[i].skin].dungeonCheckpoint.wave, 25);
      }
      await online.saveCoopProgress(event, apply);
      assert.deepEqual(await Promise.all(progressPlayers.map(p => online.getProgress(p.id))), afterProgress);
    } finally { host?.ws.terminate(); friend?.ws.terminate(); await app.close(); }
  } finally { await store.close(); await mongo.stop(); }
});
