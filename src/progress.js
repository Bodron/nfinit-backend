// Offline progress is a private backup, separate from authoritative co-op stats.
const keys = new Set(['champions_v1', 'journey_v1', 'name', 'class_skin_v2', 'skin', 'map',
  'sound', 'music_enabled', 'music_volume', 'haptics', 'runner', 'tutorial',
  'voice_sensitivity', 'best_score_v2_training', 'best_score_v2_online']);
const strings = new Set(['champions_v1', 'journey_v1', 'name', 'map']);
const booleans = new Set(['sound', 'music_enabled', 'haptics', 'runner', 'tutorial']);
export function validProgress(value) {
  if (!value || value.schemaVersion !== 1 || !value.values || Array.isArray(value.values) ||
      typeof value.values !== 'object' || Object.keys(value).some(k => !['schemaVersion', 'values'].includes(k))) return false;
  if (typeof value.values.champions_v1 !== 'string' || typeof value.values.journey_v1 !== 'string') return false;
  for (const [key, entry] of Object.entries(value.values)) {
    if (!keys.has(key)) return false;
    if (['best_score_v2_training', 'best_score_v2_online'].includes(key) && typeof entry === 'string') {
      if (!/^[0-9]{1,19}$/.test(entry)) return false;
      continue;
    }
    if (strings.has(key) ? typeof entry !== 'string' : booleans.has(key) ? typeof entry !== 'boolean' :
      typeof entry !== 'number' || !Number.isFinite(entry) || Math.abs(entry) > Number.MAX_SAFE_INTEGER) return false;
    if (key === 'music_volume' || key === 'voice_sensitivity') {
      if (entry < 0 || entry > 1) return false;
    } else if (!strings.has(key) && !booleans.has(key) && (!Number.isSafeInteger(entry) || entry < 0)) return false;
    if (key === 'champions_v1' || key === 'journey_v1') {
      try {
        const save = JSON.parse(entry);
        if (!save || Array.isArray(save) || typeof save !== 'object') return false;
        if (key === 'champions_v1' && (save.championProgressVersion !== 3 || save.heroRosterVersion !== 2 || !Array.isArray(save.champions) || save.champions.length !== 4)) return false;
        if (key === 'journey_v1' && save.heroRosterVersion !== 2) return false;
      } catch { return false; }
    }
  }
  return Buffer.byteLength(JSON.stringify(value)) <= 256 * 1024;
}
export function validProgressWrite(body) {
  return Number.isSafeInteger(body.baseRevision) && body.baseRevision >= 0 &&
    typeof body.mutationId === 'string' && /^[a-f0-9]{48}$/.test(body.mutationId) && validProgress(body.document);
}
export const publicProgress = row => row ? { revision: row.revision, document: row.document,
  updatedAt: row.updatedAt } : { revision: 0, document: null };
