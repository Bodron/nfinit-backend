import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { startBackend } from '../src/server.js';
import { MemoryStore } from '../src/store.js';

const config = { host: '127.0.0.1', port: 0, origins: new Set(['https://game.example']), maxRooms: 2,
  reconnectMs: 1000, engineBin: fileURLToPath(new URL('../build/nfinit-engine', import.meta.url)) };
const document = { schemaVersion: 1, values: {
  champions_v1: JSON.stringify({ championProgressVersion: 3, heroRosterVersion: 2,
    essence: '999999999999999999999999999999999999999', champions: [{}, {}, {}, {}] }),
  journey_v1: JSON.stringify({ heroRosterVersion: 2, rounds: 100 }), name: 'Nyx', music_volume: 0,
} };

test('Private progress API persists full snapshots, rejects conflicts, retries idempotently and isolates identities', async t => {
  const store = new MemoryStore(), app = await startBackend({ config, store }); t.after(() => app.close());
  const base = `http://127.0.0.1:${app.port}`;
  const guest = await store.createGuest('Nyx'), other = await store.createGuest('Brum');
  const request = (method, body, token = guest.token) => fetch(`${base}/api/progress`, {
    method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  assert.equal((await fetch(`${base}/api/progress`)).status, 401);
  assert.deepEqual((await request('GET').then(r => r.json())).progress, { revision: 0, document: null });
  const write = { baseRevision: 0, mutationId: 'a'.repeat(48), document };
  const duplicates = await Promise.all([request('PUT', write), request('PUT', write)]);
  assert.deepEqual(duplicates.map(r => r.status), [200, 200]);
  assert.equal((await request('GET').then(r => r.json())).progress.revision, 1);
  assert.deepEqual((await request('GET').then(r => r.json())).progress.document, document);
  assert.equal((await request('GET', null, other.token).then(r => r.json())).progress.document, null);
  const edited = { ...write, document: { ...document, values: { ...document.values, name: 'Different' } } };
  assert.equal((await request('PUT', edited)).status, 409); // Same receipt, different contents.
  const races = await Promise.all(['b', 'c'].map(id => request('PUT', { ...write, baseRevision: 1, mutationId: id.repeat(48) })));
  assert.deepEqual(races.map(r => r.status).sort(), [200, 409]);
  assert.equal((await request('GET').then(r => r.json())).progress.revision, 2);
  // Retrying an older ACK still returns that revision, never applies it again.
  assert.equal((await request('PUT', write).then(r => r.json())).revision, 1);
  assert.equal((await store.getPlayer(guest.player.id)).stats.matches, 0);
  const preflight = await fetch(`${base}/api/progress`, { method: 'OPTIONS', headers: { origin: 'https://game.example' } });
  assert.match(preflight.headers.get('access-control-allow-methods'), /PUT/);
});

test('Progress writes validate schemas and bound payloads without leaking credentials', async t => {
  const store = new MemoryStore(), app = await startBackend({ config, store }); t.after(() => app.close());
  const { token } = await store.createGuest('Tester');
  const send = body => fetch(`http://127.0.0.1:${app.port}/api/progress`, { method: 'PUT',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const base = { baseRevision: 0, mutationId: 'd'.repeat(48), document };
  for (const bad of [
    { ...base, baseRevision: -1 }, { ...base, mutationId: 'invalid' },
    { ...base, document: { schemaVersion: 999, values: {} } },
    { ...base, document: { schemaVersion: 1, values: { ...document.values, token: 'secret' } } },
    { ...base, document: { schemaVersion: 1, values: { ...document.values, champions_v1: '{' } } },
    { ...base, document: { schemaVersion: 1, values: { ...document.values, music_volume: 2 } } },
  ]) assert.equal((await send(bad)).status, 400);
  assert.equal((await send({ ...base, padding: 'x'.repeat(310 * 1024) })).status, 413);
  assert.equal((await send(base)).status, 200);
});
