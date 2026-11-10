// Function body for callAsyncJavaScript, run on a codeforces.com problem page. Returns a JSON string.
// Re-fetches the page source so we get the raw statement ($$$ TeX intact), not MathJax-rewritten DOM.
var doc = document;
try {
  var resp = await fetch(location.href, { credentials: 'include' });
  var text = await resp.text();
  var parsed = new DOMParser().parseFromString(text, 'text/html');
  if (parsed.querySelector('.problem-statement')) doc = parsed;
} catch (e) {}
var ps = doc.querySelector('.problem-statement');
if (!ps) { return JSON.stringify({ ok: false, reason: document.title || 'no problem found' }); }

function pre(el) {
  var lines = el.querySelectorAll('.test-example-line');
  if (lines.length) { return Array.from(lines).map(function (l) { return l.textContent; }).join('\n') + '\n'; }
  var clone = el.cloneNode(true);
  clone.querySelectorAll('br').forEach(function (b) { b.replaceWith('\n'); });
  var t = clone.textContent.replace(/^\n+/, '');
  return t.endsWith('\n') ? t : t + '\n';
}
function prop(sel) {
  var n = ps.querySelector(sel);
  if (!n) return '';
  var c = n.cloneNode(true);
  var t = c.querySelector('.property-title'); if (t) t.remove();
  return c.textContent.trim();
}
function abs(u) { try { return new URL(u, 'https://codeforces.com/').href; } catch (e) { return u; } }

var title = ((ps.querySelector('.header .title') || {}).textContent || 'Problem').replace(/^[A-Z0-9]+\.\s*/, '').trim();
var tlText = prop('.time-limit');
var m = tlText.match(/([0-9.]+)\s*second/);
var tl = m ? Math.round(parseFloat(m[1]) * 1000) : 2000;
var ins = Array.from(ps.querySelectorAll('.sample-test .input pre')).map(pre);
var outs = Array.from(ps.querySelectorAll('.sample-test .output pre')).map(pre);

var body = ps.cloneNode(true);
body.querySelectorAll('.header, .sample-tests, .input-output-copier').forEach(function (n) { n.remove(); });
body.querySelectorAll('img[src]').forEach(function (i) { i.setAttribute('src', abs(i.getAttribute('src'))); });
body.querySelectorAll('a[href]').forEach(function (a) { a.setAttribute('href', abs(a.getAttribute('href'))); });

return JSON.stringify({
  ok: true, title: title, timeLimitMs: tl,
  timeLimit: tlText, memoryLimit: prop('.memory-limit'), input: prop('.input-file'), output: prop('.output-file'),
  inputs: ins, outputs: outs, statement: body.innerHTML
});
