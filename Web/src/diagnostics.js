// Turns raw clang stderr / UB markers into short, human messages.
// A diagnostic: { line, col, severity: 'error'|'warning', message, kind }

const RULES = [
  // [regex on clang message, (match) => friendly text]
  [/use of undeclared identifier '(.+?)'(?:; did you mean '(.+?)'\?)?$/, (m) => m[2] ? `'${m[1]}' isn't declared. Did you mean '${m[2]}'?` : `'${m[1]}' isn't declared`],
  [/no member named '(.+?)' in '(.+?)'(?:; did you mean '(.+?)'\?)?$/, (m) => `'${short(m[2])}' has no '${m[1]}'` + (m[3] ? `. Did you mean '${m[3]}'?` : '')],
  [/no type named '(.+?)' in namespace '(.+?)'/, (m) => `'${m[2]}::${m[1]}' doesn't exist`],
  [/unknown type name '(.+?)'(?:; did you mean '(.+?)'\?)?$/, (m) => `Unknown type '${m[1]}'` + (m[2] ? `. Did you mean '${m[2]}'?` : '')],
  [/expected ';' (?:after|at end of) (.+)/, () => `Missing ';'`],
  [/expected '(.+?)'$/, (m) => `Missing '${m[1]}'`],
  [/expected expression/, () => `Something is missing here (expression expected)`],
  [/expected unqualified-id/, () => `Unexpected symbol here (check for an extra or missing '}' or ';')`],
  [/extraneous closing brace/, () => `Extra '}'`],
  [/non-void function '(.+?)' should return a value|non-void function does not return a value/, (m) => m[1] ? `'${m[1]}' must return a value` : `Function must return a value`],
  [/no matching function for call to '(.+?)'/, (m) => `No version of '${m[1]}' accepts these arguments`],
  [/no viable overloaded '(>>|<<)'/, (m) => m[1] === '>>' ? `Can't read this type with cin` : `Can't print this type with cout`],
  [/invalid operands to binary expression \('(.+?)' and '(.+?)'\)/, (m) => `Can't combine '${short(m[1])}' and '${short(m[2])}' with this operator`],
  [/no viable conversion from '(.+?)' to '(.+?)'/, (m) => `Can't convert '${short(m[1])}' to '${short(m[2])}'`],
  [/cannot initialize a variable of type '(.+?)' with an? (?:lvalue|rvalue) of type '(.+?)'/, (m) => `Can't store '${short(m[2])}' in a '${short(m[1])}'`],
  [/redefinition of '(.+?)'/, (m) => `'${m[1]}' is defined twice`],
  [/too (many|few) arguments to function call, expected (\d+), have (\d+)/, (m) => `Wrong argument count: needs ${m[2]}, got ${m[3]}`],
  [/expression is not assignable/, () => `Can't assign to this expression`],
  [/cannot assign to variable '(.+?)' with const-qualified type/, (m) => `'${m[1]}' is const and can't be changed`],
  [/use of undeclared label/, () => `Unknown label`],
  [/variable length array|variable-sized object/, () => `Array size must be a constant here`],
  [/'(.+?)' file not found/, (m) => `Header <${m[1]}> not found`],
  [/call to '(.+?)' is ambiguous/, (m) => `Call to '${m[1]}' is ambiguous (mixed argument types?)`],
  [/implicit conversion loses integer precision: '(.+?)' to '(.+?)'/, (m) => `Possible overflow: '${m[1]}' squeezed into '${m[2]}'`],
  [/implicit conversion from '(.+?)' to '(.+?)' (?:may )?(?:change|loses?)/, (m) => `'${m[1]}' → '${m[2]}' may lose precision`],
  [/comparison of integers of different signs/, () => `Comparing signed and unsigned (negative values break this)`],
  [/variable '(.+?)' is uninitialized|variable '(.+?)' is used uninitialized/, (m) => `'${m[1] || m[2]}' is used before it's set`],
  [/array index (-?\d+) is (?:past the end|before the beginning)/, (m) => `Index ${m[1]} is out of range`],
  [/array index (-?\d+) is past the end of the array \(which contains (\d+)/, (m) => `Index ${m[1]} is out of range (size ${m[2]})`],
  [/'(.+?)' may be used uninitialized|may be uninitialized/, (m) => `Value may be used before it's set`],
  [/format specifies type '(.+?)' but the argument has type '(.+?)'/, (m) => `printf/scanf format expects '${m[1]}' but got '${m[2]}'`],
  [/control reaches end of non-void function/, () => `Function may end without returning a value`],
  [/division by zero/, () => `Division by zero`],
];

// Warnings worth showing. Everything else (unused vars, shadowing...) is dropped as noise.
const KEEP_WARNINGS = /(shorten-64-to-32|implicit-int-conversion|sign-compare|uninitialized|array-bounds|return-type|division-by-zero|format|int-in-bool|tautological|parentheses|dangling|infinite-recursion|overflow)/;

function short(t) {
  return t.replace(/std::(__\d+::)?/g, '').replace(/basic_string<char[^>]*>/g, 'string').replace(/\s+/g, ' ').slice(0, 40);
}

export function parseDiagnostics(stderr) {
  const out = [];
  const seen = new Set();
  const re = /^(?:.*?):(\d+):(\d+): (error|warning|fatal error): (.*)$/gm;
  let m;
  while ((m = re.exec(stderr))) {
    const line = +m[1], col = +m[2];
    const severity = m[3] === 'warning' ? 'warning' : 'error';
    let raw = m[4];
    let flag = '';
    const f = raw.match(/\s\[-W([\w-]+)\]$/);
    if (f) { flag = f[1]; raw = raw.slice(0, f.index); }
    if (severity === 'warning' && !KEEP_WARNINGS.test(flag + ' ' + raw)) continue;
    if (/too many errors emitted/.test(raw)) continue;
    // wasm32 has a 32-bit size_t; Codeforces is 64-bit, so these warnings are false alarms here.
    if (/loses integer precision: '.+?' to '(?:std::)?(?:size_t|size_type|__size_type|unsigned long|difference_type|ptrdiff_t|long)'/.test(raw)) continue;
    let message = raw;
    for (const [rx, fn] of RULES) { const mm = raw.match(rx); if (mm) { message = fn(mm); break; } }
    const key = line + '|' + message;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ line, col, severity, message, raw, kind: 'compile' });
  }
  // A cascade of errors after the first is usually noise: keep the first 4.
  return out.slice(0, 4);
}

const UB_TEXT = {
  add: 'Integer overflow on +  (use long long)',
  sub: 'Integer overflow on −  (use long long)',
  mul: 'Integer overflow on ×  (use long long)',
  neg: 'Integer overflow on negation',
  div: 'Division by zero (or INT_MIN / -1)',
  shift: 'Shift amount out of range',
  index: 'Array index out of bounds',
};

// Look at a finished run's stderr and decide if it was a detected runtime bug.
export function parseRuntimeFault(run) {
  if (run.timedOut) return { kind: 'tle', message: 'Time limit exceeded' };
  const m = (run.stderr || '').match(/\x01UB\|(\d+)\|(\d+)\|(\w+)/);
  if (m) return { kind: 'ub', line: +m[1], col: +m[2], severity: 'error', message: UB_TEXT[m[3]] || 'Undefined behaviour' };
  if (run.crashed) {
    if (/unreachable/.test(run.crashed)) return { kind: 'crash', message: 'Crashed (assert failed, bad access or abort)' };
    if (/memory|out of bounds/i.test(run.crashed)) return { kind: 'crash', message: 'Crashed: memory access out of range' };
    return { kind: 'crash', message: 'Crashed: ' + run.crashed.slice(0, 80) };
  }
  if (run.exitCode && run.exitCode !== 0) return { kind: 'rte', message: `Non-zero exit code (${run.exitCode})` };
  return null;
}
