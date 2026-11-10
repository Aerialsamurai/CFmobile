// Function body for callAsyncJavaScript, run on https://codeforces.com/contests while logged in.
// Returns which listed contests the logged-in user is registered for.
var rows = Array.from(document.querySelectorAll('tr[data-contestid]'));
var loggedIn = !!document.querySelector('a[href^="/profile/"]');
var contests = rows.map(function (r) {
  var id = parseInt(r.getAttribute('data-contestid'), 10);
  return { id: id, registered: /registered/i.test(r.innerText) };
}).filter(function (c) { return !isNaN(c.id); });
return JSON.stringify({ ok: contests.length > 0, loggedIn: loggedIn, contests: contests });
