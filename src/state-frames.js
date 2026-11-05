import { isDeepStrictEqual } from 'node:util';

// Transport only: authoritative physics, health and rewards are never rounded.
const visualAges = new Set(['shotAge', 'empoweredAge', 'healthTrailAge', 'hurtAge', 'hitAge', 'ambushAge', 'dodgeAge']);
function compact(value) {
  if (typeof value === 'number' && !Number.isInteger(value)) {
    if (!Number.isFinite(value)) return value;
    return Math.round(value * 100000) / 100000;
  }
  if (Array.isArray(value)) return value.map(v => compact(v));
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) =>
    [k, visualAges.has(k) && typeof v === 'number' && v > 4 ? 4 : compact(v)]));
  return value;
}
function difference(previous, next) {
  const set = {}, unset = [];
  for (const [key, value] of Object.entries(next)) if (!isDeepStrictEqual(previous[key], value)) set[key] = value;
  for (const key of Object.keys(previous)) if (!Object.hasOwn(next, key)) unset.push(key);
  return { set, unset };
}

// One encoder per socket. Advance only for messages actually queued to that socket.
export class StateFrames {
  sequence = 0; previous = {}; actors = new Map(); keys = [];
  encode(state) {
    const next = compact(state), { self, players, ...root } = next;
    const reset = this.sequence === 0 || root.id !== this.previous.id || root.round !== this.previous.round || root.map !== this.previous.map;
    if (reset) { this.previous = {}; this.actors.clear(); this.keys = []; }
    const current = [self, ...players], changes = [], visible = current.map(p => p.id);
    const oldKeyCount = this.keys.length;
    for (const actor of current) {
      const { set, unset } = difference(this.actors.get(actor.id) ?? {}, actor);
      const pairs = [];
      for (const [key, value] of Object.entries(set)) {
        let index = this.keys.indexOf(key);
        if (index < 0) { index = this.keys.length; this.keys.push(key); }
        pairs.push(index, value);
      }
      if (pairs.length || unset.length) changes.push([actor.id, pairs, unset.map(k => this.keys.indexOf(k))]);
    }
    const patch = difference(this.previous, root);
    const frame = { type: 'stateFrame', protocol: 1, seq: ++this.sequence,
      base: reset ? 0 : this.sequence - 1, ...patch, visible, actors: changes };
    if (reset || this.keys.length !== oldKeyCount) frame.keys = [...this.keys];
    this.previous = root;
    // Drop vanished/hidden actors immediately, including all cached coordinates.
    this.actors = new Map(current.map(p => [p.id, p]));
    return frame;
  }
}
