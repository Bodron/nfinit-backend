// Test-only in-memory storage; never imported by the production entry point.
import { createInterface } from 'node:readline';
import { startBackend } from '../src/server.js';
import { MemoryStore } from '../src/store.js';
import { fileURLToPath } from 'node:url';

const app = await startBackend({ config: { host: '127.0.0.1', port: 0, origins: new Set(), maxRooms: 4,
  reconnectMs: 5000, engineBin: fileURLToPath(new URL('../build/nfinit-engine', import.meta.url)) }, store: new MemoryStore() });
console.log(JSON.stringify({ port: app.port }));
createInterface({ input: process.stdin }).on('line', line => {
  const command = JSON.parse(line);
  for (const room of app.rooms.values()) room.members.get(command.disconnect)?.socket?.terminate();
});
for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, async () => { await app.close(); process.exit(0); });
