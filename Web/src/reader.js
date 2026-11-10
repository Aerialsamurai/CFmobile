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

function render(p) {
  const root = $('doc');
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
  if ((p.tags && p.tags.length) || p.rating) {
    const t = el('div', 'tags');
    if (p.rating) t.append(el('span', 'tag rating', '★ ' + p.rating));
    (p.tags || []).forEach((x) => t.append(el('span', 'tag', x)));
    head.append(t);
  }
  const body = el('article', 'statement');
  body.innerHTML = clean(p.html);
  root.append(head, body);

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
  window.scrollTo(0, 0);
}

window.cfReader = {
  render,
  setTheme: (n) => applyTheme(n),
  setFontSize: (px) => document.documentElement.style.setProperty('--rfs', px + 'px'),
};
applyTheme(DEFAULT_THEME);
post({ t: 'readerReady' });
