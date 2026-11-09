// One-shot worker: runs a compiled WASI program with given stdin. Terminated by the host on timeout.
import { WASI, File, OpenFile, ConsoleStdout } from '@bjorn3/browser_wasi_shim';

self.onmessage = async (e) => {
  const { id, wasm, input } = e.data;
  const enc = new TextEncoder();
  const out = [], err = [];
  const stdin = new OpenFile(new File(enc.encode(input)));
  const stdout = new ConsoleStdout((b) => out.push(b.slice()));
  const stderr = new ConsoleStdout((b) => err.push(b.slice()));
  const wasi = new WASI(['main'], [], [stdin, stdout, stderr]);
  const t0 = performance.now();
  let exitCode = 0, crashed = null;
  try {
    const mod = await WebAssembly.compile(wasm);
    const inst = await WebAssembly.instantiate(mod, { wasi_snapshot_preview1: wasi.wasiImport });
    exitCode = wasi.start(inst);
  } catch (ex) {
    crashed = String(ex && ex.message || ex);
  }
  const ms = Math.round(performance.now() - t0);
  const join = (chunks) => new TextDecoder().decode(new Blob(chunks).size ? concat(chunks) : new Uint8Array());
  function concat(chunks) {
    const n = chunks.reduce((a, c) => a + c.length, 0), r = new Uint8Array(n); let o = 0;
    for (const c of chunks) { r.set(c, o); o += c.length; } return r;
  }
  self.postMessage({ id, stdout: join(out), stderr: join(err), exitCode, crashed, ms });
};
