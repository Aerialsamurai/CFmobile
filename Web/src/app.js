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

// ---------- key row above the keyboard ----------
const KEYS = ['{', '}', '(', ')', '[', ']', ';', '<', '>', '&', '|', '!', '=', '+', '-', '*', '/', '%', '"', "'", ',', '#', ':', '~', '^', '_'];
// [label, text, caret offset from the end of the inserted text]
const CHIPS = [
  ['for', 'for (int i = 0; i < n; i++) {\n\t\n}', -2],
  ['cin>>', 'cin >> ', 0], ['cout<<', 'cout << ', 0], ['<<', ' << ', 0], ['>>', ' >> ', 0],
  ['&&', ' && ', 0], ['||', ' || ', 0], ['::', '::', 0], ['->', '->', 0],
  ['vector<', 'vector<>', -1], ['pair<', 'pair<>', -1], ['.size()', '.size()', 0],
  ['.begin(),.end()', '.begin(), .end()', 0], ['sort(', 'sort()', -1], ['"\\n"', '"\\n"', 0],
  ['.first', '.first', 0], ['.second', '.second', 0],
];
const buzz = () => { if (opts.haptics) post({ t: 'haptic' }); };
function insertText(text, back = 0) {
  const sel = view.state.selection.main;
  const line = view.state.doc.lineAt(sel.from);
  const lead = (line.text.match(/^\s*/) || [''])[0];
  const ins = text.replace(/\t/g, indentStr()).replace(/\n/g, '\n' + lead);
  view.dispatch({ changes: { from: sel.from, to: sel.to, insert: ins }, selection: { anchor: sel.from + ins.length + back } });
}
function buildKeyRow() {
  const row = document.getElementById('keys');
  row.innerHTML = '';
  const mk = (label, fn, cls = '') => {
    const b = document.createElement('button'); b.textContent = label; b.className = cls;
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); buzz(); fn(); });
    row.append(b);
  };
  const sep = () => { const d = document.createElement('i'); row.append(d); };
  mk('⇥', () => view.dispatch(view.state.replaceSelection(indentStr())), 'wide');
  mk('↶', () => undo(view), 'wide'); mk('↷', () => redo(view), 'wide');
  for (const k of KEYS) mk(k, () => {
    const pair = { '{': '{}', '(': '()', '[': '[]', '"': '""', "'": "''" }[k];
    if (pair && opts.autoClose) insertText(pair, -1); else insertText(k);
  });
  sep();
  mk('//', () => toggleComment(view), 'wide act');
  mk('⧉', () => copyLineDown(view), 'wide act');
  mk('⌫ line', () => deleteLine(view), 'wide act');
  mk('▢', () => selectLine(view), 'wide act');
  mk('↑', () => moveLineUp(view), 'wide act');
  mk('↓', () => moveLineDown(view), 'wide act');
  if (opts.chips) { sep(); for (const [l, t, b] of CHIPS) mk(l, () => insertText(t, b), 'chip'); }
}

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
    const keys = document.getElementById('keys'), ed = document.getElementById('editor');
    keys.style.bottom = h + 'px'; keys.classList.toggle('up', h > 40);
    ed.style.bottom = (h > 40 ? h + 50 : 0) + 'px';
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
