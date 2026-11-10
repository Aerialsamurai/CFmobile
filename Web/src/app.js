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
// Two levels: a home row (quick keys + category buttons) and one page per category.
// Keys fire on RELEASE and only if the finger hasn't moved, so scrolling/dragging never types anything.
// item = [label, text, caretOffsetFromEnd?] inserts text; item = [label, null, 0, action] runs an editor command.
const Q = (l, t, b = 0) => [l, t, b];
const PAGES = {
  br: { label: '[ <', items: [
    Q('{', '{'), Q('}', '}'), Q('(', '('), Q(')', ')'), Q('[', '['), Q(']', ']'), Q('<', '<'), Q('>', '>'),
    Q('{}', '{}', -1), Q('()', '()', -1), Q('[]', '[]', -1), Q('<>', '<>', -1), Q('""', '""', -1), Q("''", "''", -1),
  ] },
  op: { label: '+ =', items: [
    Q('+', '+'), Q('-', '-'), Q('*', '*'), Q('/', '/'), Q('%', '%'), Q('=', '='), Q('++', '++'), Q('--', '--'),
    Q('==', ' == '), Q('!=', ' != '), Q('<=', ' <= '), Q('>=', ' >= '), Q('+=', ' += '), Q('-=', ' -= '), Q('*=', ' *= '), Q('/=', ' /= '),
  ] },
  sy: { label: '& ?', items: [
    Q('&&', ' && '), Q('||', ' || '), Q('!', '!'), Q('&', '&'), Q('|', '|'), Q('^', '^'), Q('~', '~'), Q('?', '?'),
    Q(':', ':'), Q('::', '::'), Q('->', '->'), Q('.', '.'), Q(',', ','), Q('#', '#'), Q('_', '_'), Q('\\', '\\'),
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
  ed: { label: '✎', sticky: true, items: [
    ['⇥', null, 0, (v) => v.dispatch(v.state.replaceSelection(indentStr()))], ['↶', null, 0, (v) => undo(v)], ['↷', null, 0, (v) => redo(v)],
    ['//', null, 0, (v) => toggleComment(v)], ['⧉', null, 0, (v) => copyLineDown(v)], ['⌫ line', null, 0, (v) => deleteLine(v)],
    ['▢', null, 0, (v) => selectLine(v)], ['↑', null, 0, (v) => moveLineUp(v)], ['↓', null, 0, (v) => moveLineDown(v)],
  ] },
};
const QUICK = [Q(';', ';'), Q('{}', '{}', -1), Q('()', '()', -1), Q('<<', ' << ')];
let keyPage = 'home';
let keyboardH = 0;

const buzz = () => { if (opts.haptics) post({ t: 'haptic' }); };
function insertText(text, back = 0) {
  const sel = view.state.selection.main;
  const line = view.state.doc.lineAt(sel.from);
  const lead = (line.text.match(/^\s*/) || [''])[0];
  const ins = text.replace(/\t/g, indentStr()).replace(/\n/g, '\n' + lead);
  // caret offsets were written for 4-space indents; adjust if the user picked 2
  const fix = back < 0 && text.includes('\t') ? 0 : 0;
  view.dispatch({ changes: { from: sel.from, to: sel.to, insert: ins }, selection: { anchor: sel.from + ins.length + back + fix } });
}

// A press counts only if it is released on the same key without the finger moving (> 10px = a scroll/drag).
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
  row.innerHTML = '';
  row.className = (keyboardH > 40 ? 'up ' : '') + (keyPage === 'home' ? 'home' : 'page');
  const add = (label, cls, fn) => { const b = document.createElement('button'); b.textContent = label; if (cls) b.className = cls; bindPress(b, fn); row.append(b); return b; };

  if (keyPage === 'home') {
    for (const [l, t, b] of QUICK) add(l, '', () => { buzz(); insertText(t, b); });
    for (const [id, pg] of Object.entries(PAGES)) {
      if (pg.chip && !opts.chips) continue;
      add(pg.label, 'cat', () => { buzz(); keyPage = id; renderKeys(); });
    }
  } else {
    const pg = PAGES[keyPage];
    add('‹', 'back', () => { buzz(); keyPage = 'home'; renderKeys(); });
    for (const [l, t, b, act] of pg.items) {
      const long = l.length > 3;
      add(l, long ? 'long' : '', () => {
        buzz();
        if (act) act(view); else insertText(t, b);   // stay on this page until the user taps ‹
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
