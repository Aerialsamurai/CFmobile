// Headless page driven by Swift: compile + run + verdict, all inside this web view.
import { Engine } from './engine.js';
import { parseDiagnostics, parseRuntimeFault } from './diagnostics.js';

const engine = new Engine('');
let lastWasm = null;

const norm = (s) => s.replace(/\r/g, '').split('\n').map((l) => l.replace(/\s+$/, '')).join('\n').replace(/\n+$/, '');

// Token-wise comparison like Codeforces' default checker (whitespace-insensitive, floats compared exactly unless eps given).
function sameOutput(got, want, eps) {
  const a = got.split(/\s+/).filter(Boolean), b = want.split(/\s+/).filter(Boolean);
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] === b[i]) continue;
    if (eps) { const x = Number(a[i]), y = Number(b[i]); if (!isNaN(x) && !isNaN(y) && Math.abs(x - y) <= eps * Math.max(1, Math.abs(y))) continue; }
    return false;
  }
  return true;
}

window.cfEngine = {
  async compile(code, opts = {}) {
    lastWasm = null;
    let r = await engine.compile(code, { std: opts.std || 'c++23', checks: opts.checks !== false });
    // The compiler can fail to start on the very first call (cold load); one retry fixes it.
    if (!r.ok && r.internal) {
      engine.compiler?.terminate(); engine.compiler = null;
      r = await engine.compile(code, { std: opts.std || 'c++23', checks: opts.checks !== false });
    }
    const diagnostics = parseDiagnostics(r.stderr || '');
    if (r.ok) lastWasm = r.wasm;
    return { ok: !!r.ok, ms: r.ms, diagnostics, raw: r.stderr || '' };
  },
  // Runs the last compiled program on one input and judges it.
  async runOne(input, expected, opts = {}) {
    if (!lastWasm) return { verdict: 'NC', message: 'Not compiled' };
    const r = await engine.run(lastWasm, input, opts.timeLimitMs || 4000);
    const fault = parseRuntimeFault(r);
    let verdict;
    if (fault?.kind === 'tle') verdict = 'TLE';
    else if (fault) verdict = 'RE';
    else if (expected == null) verdict = 'RAN';
    else verdict = sameOutput(r.stdout, expected, opts.eps) ? 'AC' : 'WA';
    return { verdict, stdout: r.stdout.slice(0, 20000), ms: r.ms, fault: fault || null };
  },
};
window.webkit?.messageHandlers?.bridge?.postMessage({ t: 'engineReady' });
