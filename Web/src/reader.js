import katex from 'katex';
import renderMathInElement from 'katex/contrib/auto-render';
import { applyTheme, DEFAULT_THEME } from './themes.js';

const post = (m) => { try { window.webkit.messageHandlers.bridge.postMessage(m); } catch { /* browser */ } };
const $ = (id) => document.getElementById(id);

// Statement HTML comes from codeforces.com; strip anything executable before inserting it.
function clean(html) {
  const doc = new DOMParser().parseFromString('<div id="r">' + html + '</div>', 'text/html');
  doc.querySelectorAll('script, iframe, object, embed, style, link, form').forEach((n) => n.remove());
  doc.querySelectorAll('*').forEach((n) => {
    for (const a of [...n.attributes]) if (/^on/i.test(a.name) || (/^(href|src)$/i.test(a.name) && /^\s*javascript:/i.test(a.value))) n.removeAttribute(a.name);
  });
  return doc.getElementById('r').innerHTML;
}

function el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }

function sampleBlock(title, text) {
  const wrap = el('div', 'sample-part');
  const head = el('div', 'sample-head');
  head.append(el('span', '', title));
  const copy = el('button', 'copy', 'Copy');
  copy.onclick = () => { navigator.clipboard?.writeText(text).then(() => { copy.textContent = 'Copied'; setTimeout(() => (copy.textContent = 'Copy'), 1200); }).catch(() => {}); };
  head.append(copy);
  wrap.append(head, el('pre', 'sample-pre', text.replace(/\n$/, '')));
  return wrap;
}

let prefs = { highlight: true, sentences: true, serif: false };
let last = null;

// ---- reading aids -------------------------------------------------------------------------------------------
// Words worth catching the eye on a small screen. goal = what to compute; cond = condition that changes the answer.
const GOAL = '(?:print|output|find|determine|calculate|count|construct|minimi[sz]e|maximi[sz]e|minimum|maximum|smallest|largest|lexicographically|shortest|longest|number of ways)';
const COND = '(?:exactly|at least|at most|distinct|different|pairwise|modulo|it is guaranteed|guaranteed|does not exceed|over all test cases|multiple answers|any of them|any valid|otherwise|if there (?:is|are) no|-1)';
const KEY_RE = new RegExp('\\b(' + GOAL + ')\\b|\\b(' + COND + ')(?![\\w])', 'gi');

function walkText(root, skip, fn) {
  const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode(n) {
      if (!n.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
      for (let e = n.parentElement; e && e !== root; e = e.parentElement) if (skip(e)) return NodeFilter.FILTER_REJECT;
      return NodeFilter.FILTER_ACCEPT;
    },
  });
  const nodes = []; while (w.nextNode()) nodes.push(w.currentNode);
  nodes.forEach(fn);
}
const isMathy = (e) => e.matches('.katex, .katex-display, pre, code, .tex-span, .tex-formula, script, style, button, .sample-pre');

// Never highlight inside our own UI (header chips, headings, example blocks).
const isChrome = (e) => isMathy(e) || e.matches('header, h1, .limits, .samples, .sample, .section-title, .chip, .tags, .meta');
function highlightKeywords(root) {
  walkText(root, isChrome, (n) => {
    const text = n.nodeValue;
    KEY_RE.lastIndex = 0;
    if (!KEY_RE.test(text)) return;
    KEY_RE.lastIndex = 0;
    const frag = document.createDocumentFragment();
    let at = 0, m;
    while ((m = KEY_RE.exec(text))) {
      if (m.index > at) frag.append(text.slice(at, m.index));
      frag.append(el('b', m[1] ? 'k-goal' : 'k-cond', m[0]));
      at = m.index + m[0].length;
    }
    frag.append(text.slice(at));
    n.replaceWith(frag);
  });
}

// One sentence per line in the Input / Output sections (they are dense paragraphs on a phone).
const ABBR = /(?:e\.g|i\.e|etc|vs|cf|no|fig)$/i;
function breakSentences(root) {
  root.querySelectorAll('.input-specification, .output-specification').forEach((sec) => {
    walkText(sec, isMathy, (n) => {
      const text = n.nodeValue;
      const re = /([.!?])\s+(?=[A-Z])/g;
      let m, at = 0, any = false;
      const frag = document.createDocumentFragment();
      while ((m = re.exec(text))) {
        if (ABBR.test(text.slice(Math.max(0, m.index - 4), m.index))) continue;
        frag.append(text.slice(at, m.index + 1), el('br', 'sbr'));
        at = m.index + m[0].length; any = true;
      }
      if (!any) return;
      frag.append(text.slice(at));
      n.replaceWith(frag);
    });
  });
}

function render(p, keepScroll = 0) {
  last = p;
  const root = $('doc');
  document.documentElement.classList.toggle('serif', !!prefs.serif);
  root.innerHTML = '';
  if (!p || !p.html) {
    const e = el('div', 'empty');
    e.append(el('div', 'big', '📄'), el('div', '', 'No problem statement here.'), el('div', 'sub', 'Import a Codeforces problem (list icon → paste a link, or browse the problemset) and it will show up here.'));
    root.append(e);
    return;
  }
  const head = el('header');
  head.append(el('h1', '', p.title || 'Problem'));
  const meta = el('div', 'meta');
  for (const [k, v] of [['time', p.timeLimit], ['memory', p.memoryLimit], ['input', p.input], ['output', p.output]]) {
    if (v) { const c = el('span', 'chip'); c.append(el('b', '', k), document.createTextNode(' ' + v)); meta.append(c); }
  }
  head.append(meta);
  // Tags / rating can spoil a problem. When hidden, show a chip the reader can tap to peek on purpose.
  const hasTags = !!(p.tags && p.tags.length), hasRating = !!p.rating;
  if (hasTags || hasRating) {
    const t = el('div', 'tags');
    const anyHidden = (hasTags && p.hideTags) || (hasRating && p.hideRating);
    const what = hasTags && p.hideTags && hasRating && p.hideRating ? 'Tags & rating' : (hasTags && p.hideTags ? 'Tags' : 'Rating');
    let revealed = false;
    const draw = () => {
      t.innerHTML = '';
      if (hasRating && (!p.hideRating || revealed)) t.append(el('span', 'tag rating', '★ ' + p.rating));
      if (hasTags && (!p.hideTags || revealed)) (p.tags || []).forEach((x) => t.append(el('span', 'tag', x)));
      if (anyHidden && !revealed) {
        const b = el('button', 'tag peek', what + ' hidden · tap to reveal');
        b.onclick = () => { revealed = true; draw(); };
        t.append(b);
      }
    };
    draw();
    head.append(t);
  }
  const body = el('article', 'statement');
  body.innerHTML = clean(p.html);
  root.append(head);
  root.append(body);

  if (p.samples && p.samples.length) {
    const sec = el('section', 'samples');
    sec.append(el('div', 'section-title', p.samples.length > 1 ? 'Examples' : 'Example'));
    p.samples.forEach((s, i) => {
      const card = el('div', 'sample');
      if (p.samples.length > 1) card.append(el('div', 'sample-n', 'Example ' + (i + 1)));
      card.append(sampleBlock('Input', s.input), sampleBlock('Output', s.output));
      sec.append(card);
    });
    root.append(sec);
    // move the Note section (if any) after the examples, as on the real site
    const note = body.querySelector('.note');
    if (note) root.append(note);
  }
  try {
    renderMathInElement(root, {
      delimiters: [{ left: '$$$$$$', right: '$$$$$$', display: true }, { left: '$$$', right: '$$$', display: false }],
      throwOnError: false, ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'],
    });
  } catch (e) { /* leave raw TeX visible */ }
  if (prefs.sentences) breakSentences(root);
  if (prefs.highlight) highlightKeywords(root);
  window.scrollTo(0, keepScroll);
}

window.cfReader = {
  render: (p) => render(p, 0),
  setPrefs(o) { prefs = Object.assign(prefs, o); if (last) render(last, window.scrollY); },
  setTheme: (n) => applyTheme(n),
  setFontSize: (px) => document.documentElement.style.setProperty('--rfs', px + 'px'),
};
applyTheme(DEFAULT_THEME);
post({ t: 'readerReady' });
