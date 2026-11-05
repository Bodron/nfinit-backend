import { fileURLToPath } from 'node:url';

function integer(env, key, fallback, min, max) {
  const value = Number(env[key] ?? fallback);
  if (!Number.isInteger(value) || value < min || value > max) throw new Error(`Invalid ${key}`);
  return value;
}
export function configFrom(env = process.env) {
  if (!env.MONGODB_URI || !/^mongodb(?:\+srv)?:\/\//.test(env.MONGODB_URI)) throw new Error('Set MONGODB_URI in .env or the hosting environment');
  const dbName = env.MONGODB_DB || 'nfinit_coop';
  if (!/^[a-zA-Z0-9_-]{1,64}$/.test(dbName)) throw new Error('Invalid MONGODB_DB');
  return {
    host: env.HOST || '0.0.0.0', port: integer(env, 'PORT', 8081, 0, 65535),
    mongoUri: env.MONGODB_URI, dbName,
    origins: new Set((env.ALLOWED_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean)),
    maxRooms: integer(env, 'MAX_ROOMS', 30, 1, 500),
    reconnectMs: integer(env, 'RECONNECT_GRACE_SECONDS', 30, 1, 180) * 1000,
    engineBin: env.ENGINE_BIN || fileURLToPath(new URL('../build/nfinit-engine', import.meta.url)),
  };
}
