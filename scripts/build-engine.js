import { mkdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const dart = process.env.DART_BIN || 'dart';
const sources = spawnSync(process.execPath, [`${root}scripts/sync-engine.js`], { stdio: 'inherit' });
if (sources.error || sources.status !== 0) process.exit(sources.status || 1);
mkdirSync(`${root}build`, { recursive: true });
for (const args of [['pub', 'get'], ['compile', 'exe', 'worker.dart', '-o', `${root}build/nfinit-engine`]]) {
  const result = spawnSync(dart, args, { cwd: `${root}engine`, stdio: 'inherit' });
  if (result.error) { console.error('Dart SDK not found. Set DART_BIN in your shell or use Docker.'); process.exit(1); }
  if (result.status !== 0) process.exit(result.status || 1);
}
