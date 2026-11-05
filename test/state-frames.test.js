import test from 'node:test';
import assert from 'node:assert/strict';
import { StateFrames } from '../src/state-frames.js';
import { states, expand } from './state-frames.fixture.js';

test('Delta frames reconstruct exact visible state, remove optional fields, hide actors and reset on rematch/map change', () => {
  const encoder=new StateFrames(),source=states();
  const frames=source.map(s=>JSON.parse(JSON.stringify(encoder.encode(s))));
  assert.deepEqual(expand(frames),source);
  assert.equal(frames[0].base,0);assert.equal(frames[1].base,frames[0].seq);
  assert.equal(frames[4].base,0);assert.equal(frames[5].base,0);
  assert.equal(frames[1].set.walls,undefined);
  assert.deepEqual(frames[2].visible,['a']);assert.equal(encoder.actors.size,2);
});
test('Hidden coordinates are not retained in a socket baseline or sent after concealment', () => {
  const encoder=new StateFrames(),source=states(),initial=encoder.encode(source[0]),second=encoder.encode(source[1]);
  const hidden=encoder.encode(source[2]);assert.equal(encoder.actors.has('b'),false);
  assert.equal(JSON.stringify(hidden).includes('.59999'),false);
  const returned=encoder.encode(source[3]);assert.deepEqual(expand([initial,second,hidden,returned])[3],source[3]);
});
test('Transport normalization bounds coordinate error, stabilizes expired effects and preserves exact growing HP', () => {
  const encoder=new StateFrames(),state=states()[0];
  state.self.x=.123456789;state.self.shotAge=444;
  const first=encoder.encode(state),decoded=expand([first])[0];
  assert.ok(Math.abs(decoded.self.x-state.self.x)<.0000051);
  assert.equal(decoded.self.health,'9999999999999999999999999');assert.equal(decoded.self.shotAge,4);
  state.self.shotAge=445;
  assert.deepEqual(encoder.encode(state).actors,[]);
});
test('New connections send complete keyframes regardless of another socket baseline', () => {
  const first=new StateFrames(),state=states()[1];first.encode(states()[0]);
  const reconnect=new StateFrames().encode(state);assert.equal(reconnect.base,0);
  assert.deepEqual(expand([reconnect])[0],state);
});
