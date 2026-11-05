import { configFrom } from './config.js';
import { MongoStore } from './store.js';
import { startBackend } from './server.js';

try {
  const config = configFrom();
  const app = await startBackend({ config, store: new MongoStore(config.mongoUri, config.dbName) });
  console.log(JSON.stringify({ event: 'listening', host: config.host, port: app.port, mode: 'coop', maxPlayers: 2 }));
  let closing = false;
  async function stop(code = 0) {
    if (closing) return; closing = true;
    process.exitCode = code;
    const timeout = setTimeout(() => process.exit(1), 15000); timeout.unref();
    try { await app.close(); } finally { clearTimeout(timeout); }
  }
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => void stop());
  app.engine.on('lost', () => void stop(1));
} catch (error) {
  console.error(JSON.stringify({ event: 'startup_failed', error: error.name,
    code: error.code ?? null,
    help: error.code === 8000 || error.code === 18
      ? 'MongoDB rejected authentication. Check the database user, password and URI encoding in .env.'
      : 'Check MONGODB_URI, Atlas network access and ENGINE_BIN. Run npm run build:engine first.' }));
  process.exitCode = 1;
}
