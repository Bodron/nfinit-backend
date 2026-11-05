import { EventEmitter } from 'node:events';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';

export class Engine extends EventEmitter {
  pending = new Map(); serial = 0; ready = false;
  async open(binary) {
    this.child = spawn(binary, [], { stdio: ['pipe', 'pipe', 'pipe'], env: { LANG: 'C.UTF-8' } });
    this.child.stderr.on('data', () => {}); // Never relay process internals to clients.
    createInterface({ input: this.child.stdout }).on('line', line => {
      try {
        const event = JSON.parse(line);
        if (event.rid) {
          const p = this.pending.get(event.rid); if (!p) return;
          clearTimeout(p.timer); this.pending.delete(event.rid);
          if (event.ok) p.resolve(event); else p.reject(new Error('Engine command failed'));
        } else this.emit(event.event, event);
      } catch { this.child.kill(); }
    });
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.child.kill(); reject(new Error('Engine startup timed out')); }, 10000);
      this.once('ready', () => { clearTimeout(timer); this.ready = true; resolve(); });
      this.child.once('error', () => { clearTimeout(timer); reject(new Error('Cannot start game engine. Run npm run build:engine first.')); });
      this.child.once('exit', () => { clearTimeout(timer); if (!this.ready) reject(new Error('Engine exited during startup')); });
    });
    this.child.on('exit', () => {
      this.ready = false;
      for (const p of this.pending.values()) { clearTimeout(p.timer); p.reject(new Error('Engine unavailable')); }
      this.pending.clear(); this.emit('lost');
    });
  }
  command(op, data = {}) {
    if (!this.ready || this.child.stdin.writableLength > 1024 * 1024) return Promise.reject(new Error('Engine unavailable'));
    const rid = ++this.serial;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(rid); reject(new Error('Engine command timeout')); }, 5000);
      this.pending.set(rid, { resolve, reject, timer });
      this.child.stdin.write(`${JSON.stringify({ rid, op, ...data })}\n`);
    });
  }
  async close() {
    if (!this.child || this.child.exitCode !== null) return;
    const exited = new Promise(resolve => this.child.once('exit', resolve));
    this.child.stdin.end();
    const timer = setTimeout(() => this.child.kill('SIGKILL'), 2000);
    await exited; clearTimeout(timer);
  }
}
