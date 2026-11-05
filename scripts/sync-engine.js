import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { dirname, extname, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const backend = fileURLToPath(new URL('../', import.meta.url));
const appLib = resolve(backend, '../lib'), destination = resolve(backend, 'engine/lib');
const manifestPath = resolve(backend, 'engine/sources.json');
const hash = data => createHash('sha256').update(data).digest('hex');
const safe = name => /^(game|content)\/[a-z0-9_/]+\.dart$/.test(name);

try {
  if (existsSync(resolve(appLib, 'game/engine.dart')) && existsSync(resolve(backend, '../pubspec.yaml'))) {
    const pending = [resolve(appLib, 'game/engine.dart')], files = new Map();
    while (pending.length) {
      const path = pending.pop(), name = relative(appLib, path).split(sep).join('/');
      if (files.has(name)) continue;
      if (!safe(name) || extname(path) !== '.dart') throw new Error('Engine source outside allowed directories');
      const source = readFileSync(path, 'utf8');
      files.set(name, source);
      for (const directive of source.matchAll(/^(?:import|export|part)\s+((?!of\b)[^;]+);/gm)) {
        for (const match of directive[1].matchAll(/['"]([^'"]+)['"]/g)) {
          const uri = match[1];
          if (uri === 'dart:ui' || uri.startsWith('package:') || uri.includes(':') && !uri.startsWith('dart:')) {
            throw new Error('Only pure Dart server engine dependencies can be exported');
          }
          if (!uri.startsWith('dart:')) pending.push(resolve(dirname(path), uri));
        }
      }
    }
    const previous = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, 'utf8')).files : [];
    for (const [name, source] of files) {
      const target = resolve(destination, name); mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, source);
    }
    for (const { path } of previous) {
      if (safe(path) && !files.has(path) && existsSync(resolve(destination, path))) unlinkSync(resolve(destination, path));
    }
    writeFileSync(manifestPath, `${JSON.stringify({ schemaVersion: 1, entrypoint: 'game/engine.dart',
      files: [...files].sort(([a], [b]) => a.localeCompare(b)).map(([path, source]) => ({ path, sha256: hash(source) })) }, null, 2)}\n`);
  }
  // A standalone clone has no Flutter project; its vendored sources are complete.
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  if (manifest.schemaVersion !== 1 || !manifest.files?.length) throw new Error('Missing engine sources');
  for (const file of manifest.files) {
    if (!safe(file.path) || hash(readFileSync(resolve(destination, file.path))) !== file.sha256) {
      throw new Error('Engine source manifest does not match; run sync:engine from the game checkout');
    }
  }
  console.log(`Verified ${manifest.files.length} pure Dart engine sources. No Flutter or image assets required.`);
} catch (error) {
  console.error(`Cannot prepare standalone engine: ${error.message}`); process.exitCode = 1;
}
