// Renders the README screenshots (demo data, user "john_pork") with headless Chromium.
// The editor and the problem reader are the app's real web pages; the native tabs are HTML recreations (shell.html).
// Usage (from repo root, after `cd Web && node build.mjs`):
//   NODE_PATH=$(npm root -g) node tools/screenshots/make.cjs docs/screenshots
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');

const out = path.resolve(process.argv[2] || 'docs/screenshots');
fs.mkdirSync(out, { recursive: true });
const dist = path.resolve(__dirname, '../../Web/dist');
const types = { '.js': 'text/javascript', '.html': 'text/html', '.css': 'text/css', '.woff2': 'font/woff2' };
const srv = http.createServer((q, r) => {
  const u = decodeURIComponent(q.url.split('?')[0]);
  const p = u === '/shell.html' ? path.join(__dirname, 'shell.html') : path.join(dist, u);
  fs.readFile(p, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': types[path.extname(p)] || 'application/octet-stream' }); r.end(d); });
}).listen(8790);

// Original demo problem (not copied from Codeforces).
const STATEMENT = `<div><p>Mira has an array $$$a$$$ of $$$n$$$ integers. She wants to choose exactly $$$k$$$ <b>disjoint pairs</b> of elements and maximise the total of $$$a_i \\cdot a_j$$$ over the chosen pairs $$$(i, j)$$$.</p>
<p>Help Mira find the largest possible total.</p></div>
<div class="input-specification"><div class="section-title">Input</div>
<p>The first line contains $$$t$$$ ($$$1 \\le t \\le 10^4$$$) — the number of test cases.</p>
<p>The first line of each test case contains two integers $$$n$$$ and $$$k$$$ ($$$2k \\le n \\le 2 \\cdot 10^5$$$). The second line contains $$$n$$$ integers $$$a_1, a_2, \\ldots, a_n$$$ ($$$1 \\le a_i \\le 10^9$$$).</p></div>
<div class="output-specification"><div class="section-title">Output</div><p>For each test case, print the largest possible total.</p></div>`;

const CODE = `#include <bits/stdc++.h>
using namespace std;

#define int long long

void solve() {
    int n, k;
    cin >> n >> k;
    vector<int> a(n);
    for (auto &x : a) cin >> x;
    sort(a.begin(), a.end());
    int ans = 0;
    for (int i = 0; i < k; i++)
        ans += a[n - 1 - 2 * i] * a[n - 2 - 2 * i];
    cout << anss << "\\n";
}

signed main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t = 1;
    cin >> t;
    while (t--) solve();
    return 0;
}
`;

(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  const names = ['problem', 'code', 'tests', 'detail', 'problemset', 'contests', 'subs', 'settings'];
  for (const n of names) {
    const pg = await ctx.newPage();
    pg.on('pageerror', (e) => console.log('[err]', n, e.message));
    await pg.goto('http://localhost:8790/shell.html?s=' + n);
    if (n === 'problem' || n === 'code') {
      const fr = await (async () => { for (let i = 0; i < 50; i++) { const f = pg.frames().find((x) => /(index|reader)\.html/.test(x.url())); if (f) return f; await pg.waitForTimeout(100); } })();
      await fr.waitForFunction(() => window.cfReader || window.cf);
      if (n === 'problem') {
        await fr.evaluate((html) => window.cfReader.render({
          title: 'B. Pair Sums', timeLimit: '2 seconds', memoryLimit: '256 megabytes', input: 'standard input', output: 'standard output',
          html, tags: ['greedy', 'sortings'], rating: 1200,
          samples: [{ input: '2\n4 2\n3 5 1 9\n3 1\n2 2 7\n', output: '48\n14\n' }],
        }), STATEMENT);
      } else {
        await fr.evaluate((code) => { window.cf.setCode(code); window.cf.setDiagnostics([{ line: 15, col: 13, severity: 'error', message: "'anss' isn't declared. Did you mean 'ans'?" }]); }, CODE);
      }
      await pg.waitForTimeout(700);
    }
    await pg.waitForTimeout(300);
    await pg.screenshot({ path: path.join(out, n + '.raw.png') });
    await pg.close();
  }
  await b.close(); srv.close();
  console.log('rendered', names.length);
})();
