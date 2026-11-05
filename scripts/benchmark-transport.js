// node scripts/benchmark-transport.js /absolute/path/to/snapshots.jsonl
import { createReadStream } from 'node:fs';
import { createInterface } from 'node:readline';
import { deflateRawSync } from 'node:zlib';
import { performance } from 'node:perf_hooks';
import { StateFrames } from '../src/state-frames.js';
if (!process.argv[2]) throw new Error('Supply a synthetic snapshot JSONL file');
const frames = new StateFrames();
let count = 0, rawBytes = 0, frameBytes = 0, deflateBytes = 0, oldDeflateBytes = 0, maxFrameBytes = 0;
const timings=[];
for await (const line of createInterface({ input: createReadStream(process.argv[2]) })) {
  const state=JSON.parse(line),now=performance.now(),frame=JSON.stringify(frames.encode(state));
  timings.push(performance.now()-now);
  const compressed=deflateRawSync(frame,{level:1,memLevel:7}),legacy=deflateRawSync(line,{level:1,memLevel:7});
  const size=Buffer.byteLength(frame);count++;rawBytes+=Buffer.byteLength(line);frameBytes+=size;
  deflateBytes+=compressed.length;oldDeflateBytes+=legacy.length;maxFrameBytes=Math.max(maxFrameBytes,size);
}
timings.sort((a,b)=>a-b);
console.log(JSON.stringify({snapshots:count,rawBytes,frameBytes,deflateBytes,legacyDeflateBytes:oldDeflateBytes,
  frameReductionPercent:Math.round((1-frameBytes/rawBytes)*1000)/10,
  compressedReductionPercent:Math.round((1-deflateBytes/rawBytes)*1000)/10,
  rawBytesPerSecondPerPhone:Math.round(rawBytes/count*20),
  frameBytesPerSecondPerPhone:Math.round(frameBytes/count*20),
  compressedBytesPerSecondPerPhone:Math.round(deflateBytes/count*20),
  legacyCompressedBytesPerSecondPerPhone:Math.round(oldDeflateBytes/count*20),
  maxFrameBytes,encodeP95Ms:timings[Math.floor(timings.length*.95)],
  scope:'Identical synthetic states; compressed sizes exclude TLS/WebSocket headers. Not a VPS or device FPS measurement.'},null,2));
