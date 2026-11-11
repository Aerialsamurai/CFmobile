import { EditorView, keymap, lineNumbers, highlightActiveLine, highlightActiveLineGutter, Decoration, WidgetType, gutter, GutterMarker } from '@codemirror/view';
import { EditorState, StateField, StateEffect, RangeSetBuilder, Compartment } from '@codemirror/state';
import { cpp } from '@codemirror/lang-cpp';
import { syntaxHighlighting, HighlightStyle, indentOnInput, bracketMatching, indentUnit } from '@codemirror/language';
import { history, historyKeymap, defaultKeymap, undo, redo, toggleComment, copyLineDown, deleteLine, moveLineUp, moveLineDown, selectLine } from '@codemirror/commands';
import { closeBrackets, closeBracketsKeymap } from '@codemirror/autocomplete';
import { tags as t } from '@lezer/highlight';
import { applyTheme, DEFAULT_THEME, THEMES } from './themes.js';

// ---------- bridge to Swift (falls back to console in a normal browser) ----------
const post = (msg) => {
  try { window.webkit.messageHandlers.bridge.postMessage(msg); } catch { console.log('[bridge]', JSON.stringify(msg).slice(0, 200)); }
};

// ---------- diagnostics decorations ----------
const setDiags = StateEffect.define();
class Label extends WidgetType {
  constructor(text, sev) { super(); this.text = text; this.sev = sev; }
  eq(o) { return o.text === this.text && o.sev === this.sev; }
  toDOM() { const s = document.createElement('span'); s.className = 'cf-label cf-' + this.sev; s.textContent = this.text; return s; }
  ignoreEvent() { return true; }
}
class Dot extends GutterMarker {
  constructor(sev) { super(); this.sev = sev; }
  eq(o) { return o.sev === this.sev; }
  toDOM() { const s = document.createElement('span'); s.className = 'cf-dot cf-' + this.sev; s.textContent = '●'; return s; }
}
const diagField = StateField.define({
  create: () => ({ list: [], deco: Decoration.none }),
  update(v, tr) {
    for (const e of tr.effects) if (e.is(setDiags)) return build(tr.state, e.value);
    if (tr.docChanged && v.list.length) return { list: [], deco: Decoration.none }; // edits invalidate marks
    return v;
  },
  provide: (f) => EditorView.decorations.from(f, (v) => v.deco),
});
function build(state, list) {
  const doc = state.doc;
  const items = list.filter((d) => d.line >= 1 && d.line <= doc.lines)
    .sort((a, b) => a.line - b.line || (a.severity === 'error' ? -1 : 1));
  const byLine = new Map();
  for (const d of items) if (!byLine.has(d.line) || d.severity === 'error') byLine.set(d.line, d);
  const b = new RangeSetBuilder();
  for (const [ln, d] of [...byLine].sort((x, y) => x[0] - y[0])) {
    const line = doc.line(ln);
    b.add(line.from, line.from, Decoration.line({ class: 'cf-line-' + d.severity }));
    b.add(line.to, line.to, Decoration.widget({ widget: new Label(d.message, d.severity), side: 1 }));
  }
  return { list: items, deco: b.finish(), byLine };
}
const diagGutter = gutter({
  class: 'cf-gutter',
  lineMarker(view, line) {
    const v = view.state.field(diagField);
    if (!v.byLine) return null;
    const d = v.byLine.get(view.state.doc.lineAt(line.from).number);
    return d ? new Dot(d.severity) : null;
  },
  lineMarkerChange: (u) => u.docChanged || u.transactions.some((tr) => tr.effects.some((e) => e.is(setDiags))),
});

// ---------- highlight style (reads CSS vars, so themes swap instantly) ----------
const hl = HighlightStyle.define([
  { tag: t.keyword, color: 'var(--kw)' },
  { tag: [t.controlKeyword, t.moduleKeyword], color: 'var(--ctl)' },
  { tag: [t.typeName, t.className, t.namespace], color: 'var(--type)' },
  { tag: [t.string, t.character], color: 'var(--str)' },
  { tag: [t.number, t.bool, t.null, t.atom], color: 'var(--num)' },
  { tag: [t.lineComment, t.blockComment], color: 'var(--com)', fontStyle: 'italic' },
  { tag: [t.processingInstruction, t.meta, t.macroName], color: 'var(--pre)' },
  { tag: t.function(t.variableName), color: 'var(--fn)' },
  { tag: t.function(t.propertyName), color: 'var(--fn)' },
  { tag: [t.variableName, t.propertyName], color: 'var(--vr)' },
  { tag: t.definition(t.variableName), color: 'var(--vr)' },
  { tag: [t.operator, t.punctuation, t.bracket], color: 'var(--fg)' },
]);

const baseTheme = EditorView.theme({
  '&': { backgroundColor: 'var(--bg)', color: 'var(--fg)', height: '100%' },
  '.cm-scroller': { fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace', lineHeight: '1.55', overflow: 'auto' },
  '.cm-content': { caretColor: 'var(--cursor)', padding: '6px 0 160px 0' },
  '.cm-gutters': { backgroundColor: 'var(--bg)', color: 'var(--gutterFg)', border: 'none', paddingLeft: '2px' },
  '.cm-activeLine': { backgroundColor: 'var(--line)' },
  '.cm-activeLineGutter': { backgroundColor: 'transparent', color: 'var(--fg)' },
  '.cm-matchingBracket': { backgroundColor: 'transparent', outline: '1px solid var(--gutterFg)' },
  '.cm-line': { padding: '0 8px' },
  '.cm-lineNumbers .cm-gutterElement': { padding: '0 8px 0 4px', minWidth: '28px' },
  '.cf-gutter': { width: '14px' },
}, { dark: true });

// ---------- editor ----------
let view;
const opts = { indent: 4, autoClose: true, chips: true, haptics: true };
const indentC = new Compartment();
const closeC = new Compartment();
const indentStr = () => ' '.repeat(opts.indent);
let lastSent = '';
function makeState(doc) {
  return EditorState.create({
    doc,
    extensions: [
      lineNumbers(), diagGutter, highlightActiveLineGutter(), highlightActiveLine(),
      history(), indentOnInput(), bracketMatching(), closeC.of(opts.autoClose ? closeBrackets() : []), indentC.of(indentUnit.of(indentStr())),
      cpp(), syntaxHighlighting(hl), baseTheme, diagField,
      keymap.of([...closeBracketsKeymap, ...defaultKeymap, ...historyKeymap, { key: 'Tab', run: (v) => { v.dispatch(v.state.replaceSelection(indentStr())); return true; } }]),
      EditorView.contentAttributes.of({ autocorrect: 'off', autocapitalize: 'off', spellcheck: 'false', autocomplete: 'off' }),
      EditorView.updateListener.of((u) => {
        if (u.docChanged) {
          hideBar();
          scheduleSend();
        }
      }),
    ],
  });
}
let sendTimer;
function scheduleSend() {
  clearTimeout(sendTimer);
  sendTimer = setTimeout(() => { const c = view.state.doc.toString(); if (c !== lastSent) { lastSent = c; post({ t: 'code', code: c }); } }, 400);
}

// ---------- error bar ----------
const bar = () => document.getElementById('errbar');
function hideBar() { bar().classList.remove('show'); }
function showBar(list) {
  const el = bar();
  if (!list.length) { hideBar(); return; }
  el.innerHTML = '';
  for (const d of list.slice(0, 3)) {
    const row = document.createElement('div');
    row.className = 'row ' + d.severity;
    const ln = document.createElement('b'); ln.textContent = 'Line ' + d.line;
    const msg = document.createElement('span'); msg.textContent = d.message;
    row.append(ln, msg);
    row.onclick = () => jumpTo(d.line);
    el.append(row);
  }
  el.classList.add('show');
}
function jumpTo(line) {
  const l = view.state.doc.line(Math.min(Math.max(line, 1), view.state.doc.lines));
  view.dispatch({ selection: { anchor: l.from }, effects: EditorView.scrollIntoView(l.from, { y: 'center' }) });
}

// ---------- shortcut bar above the keyboard ----------
// Home row = the symbols that save the most taps on the iPhone keyboard (measured on 871 real solutions, see tools/research).
//   tap = main symbol · hold = popup with variants (slide, release) · flick up = first variant · ⋯ = everything else.
// A key never fires while the finger is dragging sideways, so scrolling/dragging can't type by accident.
// variant / item = [label, text, caretOffsetFromEnd?]
const Q = (l, t, b = 0) => [l, t, b];
const HOME = [
  { l: ';', t: ';', v: [Q(':', ':'), Q('::', '::'), Q('?', '?')] },
  { l: '(', t: '(', v: [Q('()', '()', -1)] },
  { l: ')', t: ')', over: true, v: [Q(');', ');'), Q(') {', ') {'), Q('))', '))')] },
  { l: '<', t: '<', v: [Q('<<', ' << '), Q('<=', ' <= '), Q('<>', '<>', -1)] },
  { l: '>', t: '>', v: [Q('>>', ' >> '), Q('>=', ' >= '), Q('->', '->')] },
  { l: '=', t: '=', v: [Q('==', ' == '), Q('!=', ' != '), Q('<=', ' <= '), Q('>=', ' >= ')] },
  { l: '+', t: '+', v: [Q('++', '++'), Q('+=', ' += '), Q('-', '-'), Q('--', '--'), Q('*', '*'), Q('/', '/'), Q('%', '%')] },
  { l: '{}', t: '{}', back: -1, v: [Q('{', '{'), Q('}', '}'), Q('{⏎}', '{\n\t\n}', -2)] },
  { l: '[]', t: '[]', back: -1, v: [Q('[', '['), Q(']', ']')] },
  { l: ',', t: ',', v: [Q('.', '.'), Q('_', '_'), Q('-', '-'), Q('"', '"'), Q("'", "'"), Q('#', '#')] },
];
const PAGES = {
  more: { label: '⋯', items: [
    Q('.', '.'), Q('_', '_'), Q('-', '-'), Q('"', '"'), Q("'", "'"), Q('#', '#'), Q('&', '&'), Q('|', '|'),
    Q('^', '^'), Q('~', '~'), Q('!', '!'), Q(':', ':'), Q('::', '::'), Q('->', '->'), Q('*', '*'), Q('/', '/'),
    Q('%', '%'), Q('\\', '\\'), Q('?', '?'), Q('&&', ' && '), Q('||', ' || '), Q('==', ' == '), Q('!=', ' != '),
    ['I/O', null, 0, null, 'io'], ['for', null, 0, null, 'code'], ['✎', null, 0, null, 'ed'],
  ] },
  io: { label: 'I/O', chip: true, items: [
    Q('cin >>', 'cin >> '), Q('cout <<', 'cout << '), Q('>>', ' >> '), Q('<<', ' << '),
    Q('"\\n"', '"\\n"'), Q("' '", "' '"), Q('endl', 'endl'), Q('cerr <<', 'cerr << '),
    Q('getline', 'getline(cin, )', -1), Q('printf', 'printf("")', -2), Q('scanf', 'scanf("")', -2), Q('setprecision', 'fixed << setprecision()', -1),
  ] },
  code: { label: 'for', chip: true, items: [
    Q('for', 'for (int i = 0; i < n; i++) {\n\t\n}', -2), Q('for auto', 'for (auto &x : ) {\n\t\n}', -9),
    Q('while', 'while () {\n\t\n}', -6), Q('if', 'if () {\n\t\n}', -6), Q('else', 'else {\n\t\n}', -2), Q('else if', 'else if () {\n\t\n}', -6),
    Q('return', 'return '), Q('break', 'break;'), Q('continue', 'continue;'),
    Q('vector<', 'vector<>', -1), Q('pair<', 'pair<>', -1), Q('map<', 'map<>', -1), Q('set<', 'set<>', -1),
    Q('sort', 'sort(.begin(), .end());', -17), Q('.size()', '.size()'), Q('.push_back', '.push_back()', -1),
    Q('.begin,.end', '.begin(), .end()'), Q('.first', '.first'), Q('.second', '.second'), Q('auto', 'auto '), Q('long long', 'long long '),
  ] },
  ed: { label: '✎', items: [
    ['⇥', null, 0, (v) => v.dispatch(v.state.replaceSelection(indentStr()))], ['↶', null, 0, (v) => undo(v)], ['↷', null, 0, (v) => redo(v)],
    ['//', null, 0, (v) => toggleComment(v)], ['⧉', null, 0, (v) => copyLineDown(v)], ['⌫ line', null, 0, (v) => deleteLine(v)],
    ['▢', null, 0, (v) => selectLine(v)], ['↑', null, 0, (v) => moveLineUp(v)], ['↓', null, 0, (v) => moveLineDown(v)],
  ] },
};
let keyPage = 'home';
let keyboardH = 0;

const buzz = () => { if (opts.haptics) post({ t: 'haptic' }); };
function insertText(text, back = 0) {
  const sel = view.state.selection.main;
  const line = view.state.doc.lineAt(sel.from);
  const lead = (line.text.match(/^\s*/) || [''])[0];
  const ins = text.replace(/\t/g, indentStr()).replace(/\n/g, '\n' + lead);
  view.dispatch({ changes: { from: sel.from, to: sel.to, insert: ins }, selection: { anchor: sel.from + ins.length + back } });
}
// ')' ']' '}' step over an identical character that is already there (e.g. after a pair was inserted)
function typeKey(def) {
  const sel = view.state.selection.main;
  if (def.over && sel.empty && view.state.doc.sliceString(sel.from, sel.from + 1) === def.t) {
    view.dispatch({ selection: { anchor: sel.from + 1 } });
  } else insertText(def.t, def.back || 0);
}

// ---- hold popup ----
let popup = null;
function showPopup(btn, variants) {
  closePopup();
  const pop = document.createElement('div');
  pop.className = 'kpop';
  variants.forEach(([l]) => { const d = document.createElement('div'); d.textContent = l; pop.append(d); });
  document.body.append(pop);
  const r = btn.getBoundingClientRect();
  const w = pop.offsetWidth;
  pop.style.left = Math.max(4, Math.min(window.innerWidth - w - 4, r.left + r.width / 2 - w / 2)) + 'px';
  pop.style.bottom = (window.innerHeight - r.top + 8) + 'px';
  popup = { el: pop, key: r, sel: -1 };
  return popup;
}
function popupSelect(x, y) {
  if (!popup) return -1;
  let hit = -1;
  [...popup.el.children].forEach((c, i) => {
    const r = c.getBoundingClientRect();
    const on = x >= r.left - 2 && x <= r.right + 2 && y < popup.key.bottom + 14;
    c.classList.toggle('on', on);
    if (on) hit = i;
  });
  popup.sel = hit;
  return hit;
}
function closePopup() { if (popup) { popup.el.remove(); popup = null; } }

// A home key: tap / hold-and-slide / flick up.
function bindKey(btn, def) {
  let st = null;
  const done = () => { if (st) clearTimeout(st.timer); st = null; btn.classList.remove('down'); closePopup(); };
  btn.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    done();
    try { btn.setPointerCapture(e.pointerId); } catch { /* keep receiving moves/up even after the finger leaves the key */ }
    st = { x: e.clientX, y: e.clientY, moved: false, held: false };
    btn.classList.add('down');
    if (def.v && def.v.length) st.timer = setTimeout(() => { if (st) { st.held = true; buzz(); showPopup(btn, def.v); } }, 260);
  });
  btn.addEventListener('pointermove', (e) => {
    if (!st) return;
    if (st.held) { popupSelect(e.clientX, e.clientY); return; }
    if (Math.hypot(e.clientX - st.x, e.clientY - st.y) > 10) { st.moved = true; clearTimeout(st.timer); }
  });
  btn.addEventListener('pointerup', (e) => {
    if (!st) return;
    const s = st, sel = popup ? popup.sel : -1;
    done();
    if (s.held) { if (sel >= 0) { buzz(); const [, t, b] = def.v[sel]; insertText(t, b || 0); } return; }
    const dx = e.clientX - s.x, dy = e.clientY - s.y;
    if (s.moved) {
      // an intentional upward flick = first variant; any other drag types nothing
      if (dy < -18 && Math.abs(dx) < Math.abs(dy) && def.v && def.v.length) { buzz(); const [, t, b] = def.v[0]; insertText(t, b || 0); }
      return;
    }
    buzz(); typeKey(def);
  });
  btn.addEventListener('pointercancel', done);
  btn.addEventListener('contextmenu', (e) => e.preventDefault());
}

// A page key: fires on release only if the finger didn't move.
function bindPress(btn, fn) {
  let down = false, sx = 0, sy = 0;
  btn.addEventListener('pointerdown', (e) => { e.preventDefault(); down = true; sx = e.clientX; sy = e.clientY; btn.classList.add('down'); });
  btn.addEventListener('pointermove', (e) => { if (down && Math.hypot(e.clientX - sx, e.clientY - sy) > 10) { down = false; btn.classList.remove('down'); } });
  btn.addEventListener('pointerup', () => { const fire = down; down = false; btn.classList.remove('down'); if (fire) fn(); });
  const cancel = () => { down = false; btn.classList.remove('down'); };
  btn.addEventListener('pointercancel', cancel);
  btn.addEventListener('pointerleave', cancel);
  btn.addEventListener('contextmenu', (e) => e.preventDefault());
}

function applyKeyLayout() {
  const row = document.getElementById('keys'), ed = document.getElementById('editor');
  const showing = keyboardH > 40;
  row.style.bottom = keyboardH + 'px';
  row.classList.toggle('up', showing);
  ed.style.bottom = showing ? (keyboardH + row.offsetHeight) + 'px' : '0px';
}

function renderKeys() {
  const row = document.getElementById('keys');
  closePopup();
  row.innerHTML = '';
  row.className = (keyboardH > 40 ? 'up ' : '') + (keyPage === 'home' ? 'home' : 'page');
  const add = (label, cls, fn) => { const b = document.createElement('button'); b.textContent = label; if (cls) b.className = cls; bindPress(b, fn); row.append(b); return b; };

  if (keyPage === 'home') {
    for (const def of HOME) {
      const b = document.createElement('button');
      b.textContent = def.l;
      if (def.v && def.v.length) b.classList.add('hasv');
      bindKey(b, def);
      row.append(b);
    }
    add('⋯', 'more', () => { buzz(); keyPage = 'more'; renderKeys(); });
  } else {
    const pg = PAGES[keyPage];
    add('‹', 'back', () => { buzz(); keyPage = keyPage === 'more' ? 'home' : 'more'; renderKeys(); });
    for (const [l, t, b, act, go] of pg.items) {
      if (go && PAGES[go].chip && !opts.chips) continue;
      const long = l.length > 3;
      add(l, go ? 'cat' : (long ? 'long' : ''), () => {
        buzz();
        if (go) { keyPage = go; renderKeys(); return; }
        if (act) act(view); else insertText(t, b);          // stay on this page until the user taps ‹
      });
    }
  }
  applyKeyLayout();
}
function buildKeyRow() { keyPage = 'home'; renderKeys(); }

// ---------- public API (called from Swift via evaluateJavaScript) ----------
window.cf = {
  setCode(code) { lastSent = code; view.setState(makeState(code)); hideBar(); },
  getCode: () => view.state.doc.toString(),
  setDiagnostics(list) { view.dispatch({ effects: setDiags.of(list) }); showBar(list); if (list[0]) jumpTo(list[0].line); },
  clearDiagnostics() { view.dispatch({ effects: setDiags.of([]) }); hideBar(); },
  setTheme(name) { return applyTheme(name); },
  setFontSize(px) { document.documentElement.style.setProperty('--fs', px + 'px'); },
  themes: () => Object.keys(THEMES),
  // Swift reports how many px of the web view the keyboard covers.
  setKeyboard(h) {
    keyboardH = h;
    if (h <= 40) keyPage = 'home';
    renderKeys();
    if (h > 40 && view) view.dispatch({ effects: EditorView.scrollIntoView(view.state.selection.main.head, { y: 'nearest', yMargin: 24 }) });
  },
  setOptions(o) {
    Object.assign(opts, o);
    if (view) view.dispatch({ effects: [
      indentC.reconfigure(indentUnit.of(indentStr())),
      closeC.reconfigure(opts.autoClose ? closeBrackets() : []),
    ] });
    buildKeyRow();
  },
  jumpTo,
};

function init() {
  applyTheme(DEFAULT_THEME);
  view = new EditorView({ state: makeState(''), parent: document.getElementById('editor') });
  buildKeyRow();
  post({ t: 'ready' });
}
init();
