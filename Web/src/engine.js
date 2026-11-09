// Main-thread API over the workers.
export class Engine {
  constructor(base = '') {
    this.base = base;
    this.compiler = null;
    this.nextId = 1;
  }
  _compiler() {
    this.compiler ??= new Worker(this.base + 'compile.worker.js', { type: 'module' });
    return this.compiler;
  }
  compile(code, { std = 'c++23', checks = true, onStatus } = {}) {
    const id = this.nextId++;
    const w = this._compiler();
    return new Promise((resolve, reject) => {
      const h = (e) => {
        if (e.data.id !== id) return;
        if (e.data.type === 'status') return onStatus?.(e.data.text);
        w.removeEventListener('message', h);
        if (e.data.type === 'error') reject(new Error(e.data.message)); else resolve(e.data);
      };
      w.addEventListener('message', h);
      w.postMessage({ id, type: 'compile', code, std, checks });
    });
  }
  run(wasm, input, timeLimitMs = 4000) {
    return new Promise((resolve) => {
      const w = new Worker(this.base + 'run.worker.js', { type: 'module' });
      const timer = setTimeout(() => { w.terminate(); resolve({ timedOut: true, stdout: '', stderr: '', ms: timeLimitMs }); }, timeLimitMs);
      w.onmessage = (e) => { clearTimeout(timer); w.terminate(); resolve(e.data); };
      w.onerror = (e) => { clearTimeout(timer); w.terminate(); resolve({ crashed: String(e.message), stdout: '', stderr: '', ms: 0 }); };
      w.postMessage({ id: 1, wasm: wasm.slice(), input });
    });
  }
}
