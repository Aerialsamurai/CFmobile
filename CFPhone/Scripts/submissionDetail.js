// Function body (async). Args: sid. Run on a codeforces.com submission page while logged in.
// Uses the same endpoint the site's own "Click to see test details" uses.
var meta = document.querySelector('meta[name="X-Csrf-Token"]');
var token = meta ? meta.getAttribute('content') : '';
if (!token) { var inp = document.querySelector('input[name="csrf_token"]'); token = inp ? inp.value : ''; }
if (!token) { return JSON.stringify({ ok: false, reason: 'not-ready: ' + (document.title || '') }); }
var resp = await fetch('/data/submitSource', {
  method: 'POST', credentials: 'include',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'X-Csrf-Token': token },
  body: 'submissionId=' + encodeURIComponent(sid) + '&csrf_token=' + encodeURIComponent(token)
});
var j;
try { j = await resp.json(); } catch (e) { return JSON.stringify({ ok: false, reason: 'bad-response' }); }
var n = parseInt(j.testCount || '0', 10);
if (!n) { return JSON.stringify({ ok: true, testCount: 0, verdict: j.verdict || '' }); }
return JSON.stringify({
  ok: true, testCount: n, verdict: j.verdict || '',
  input: j['input#' + n] || '', output: j['output#' + n] || '', answer: j['answer#' + n] || '',
  checker: j['checkerStdoutAndStderr#' + n] || ''
});
