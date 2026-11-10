// Long-lived worker: loads Clang once, compiles on request.
import { STDCPP_SHIM } from './shim.js';
import { UB_HANDLERS } from './ubhandlers.js';

let clangPromise = null;
function loadClang() {
  // ./clang/bundle.js is copied from @yowasp/clang/gen at build time.
  clangPromise ??= import('./clang/bundle.js');
  return clangPromise;
}

const FLAGS = ['-O2', '-fno-exceptions', '-fno-color-diagnostics', '-fno-caret-diagnostics',
  '-fdiagnostics-show-option', '-Wall', '-Wextra', '-Wshadow', '-Wconversion', '-Wno-sign-conversion'];

const SAN = ['-fsanitize=signed-integer-overflow,shift,bounds,integer-divide-by-zero'];

self.onmessage = async (e) => {
  const { id, type, code, std = 'c++23', defines = [], checks = true } = e.data;
  if (type !== 'compile') return;
  try {
    self.postMessage({ id, type: 'status', text: 'Loading compiler…' });
    const { runClang } = await loadClang();
    self.postMessage({ id, type: 'status', text: 'Compiling…' });
    let stderr = '';
    let internal = false;
    const dec = new TextDecoder();
    const t0 = performance.now();
    let files;
    try {
      files = await runClang(
        ['clang++', `-std=${std}`, ...FLAGS, ...(checks ? SAN : []), ...defines.map(d => '-D' + d), '-I./inc', 'main.cpp', ...(checks ? ['ub.cpp'] : []), '-o', 'main.wasm'],
        { 'main.cpp': code, 'ub.cpp': UB_HANDLERS, inc: { bits: { 'stdc++.h': STDCPP_SHIM } } },
        { stderr: (b) => { if (b) stderr += typeof b === 'string' ? b : dec.decode(b); } }
      );
    } catch (err) {
      files = null; // non-zero exit: diagnostics are in stderr
      if (!stderr.trim()) { stderr = 'INTERNAL: ' + String((err && err.message) || err); internal = true; }
    }
    const ms = Math.round(performance.now() - t0);
    const wasm = files && files['main.wasm'];
    if (wasm) self.postMessage({ id, type: 'done', ok: true, stderr, ms, wasm }, [wasm.buffer]);
    else self.postMessage({ id, type: 'done', ok: false, stderr, ms, internal });
  } catch (err) {
    self.postMessage({ id, type: 'error', message: String(err && err.stack || err) });
  }
};
