// Dev-only: checks the problem extraction script + reader rendering in headless Chromium.
// Usage: NODE_PATH=$(npm root -g) node test/reader-test.cjs <screenshot-dir>
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const root = path.resolve(__dirname, '..');
const shots = process.argv[2] || '.';
const types = { '.js': 'text/javascript', '.html': 'text/html', '.css': 'text/css', '.woff2': 'font/woff2' };
const srv = http.createServer((q, r) => {
  const u = decodeURIComponent(q.url.split('?')[0]);
  const p = u.startsWith('/fx/') ? path.join(root, 'test/fixtures', u.slice(4)) : path.join(root, 'dist', u);
  fs.readFile(p, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': types[path.extname(p)] || 'application/octet-stream' }); r.end(d); });
}).listen(8771);
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  const errs = [];
  const pg = await ctx.newPage(); pg.on('pageerror', (e) => errs.push(e.message));
  await pg.goto('http://localhost:8771/fx/problem.html');
  const body = fs.readFileSync(path.resolve(root, '../CFPhone/Scripts/extractProblem.js'), 'utf8');
  const res = await pg.evaluate(async (src) => { const AF = Object.getPrototypeOf(async function () {}).constructor; return await new AF(src)(); }, body);
  const j = JSON.parse(res);
  console.log(JSON.stringify({ ok: j.ok, title: j.title, tl: j.timeLimitMs, mem: j.memoryLimit, io: [j.input, j.output], ins: j.inputs, outs: j.outputs,
    hasTeX: j.statement.includes('$$$'), imgAbs: /https:\/\/codeforces\.com\/predownloaded/.test(j.statement),
    samplesRemoved: !j.statement.includes('sample-test'), headerRemoved: !j.statement.includes('time-limit') }));
  const rd = await ctx.newPage(); rd.on('pageerror', (e) => errs.push(e.message));
  await rd.goto('http://localhost:8771/reader.html');
  await rd.evaluate((j) => window.cfReader.render({ title: j.title, timeLimit: j.timeLimit, memoryLimit: j.memoryLimit, input: j.input, output: j.output, html: j.statement,
    tags: ['implementation', 'math'], rating: 1300, samples: [{ input: j.inputs[0], output: j.outputs[0] }] }), j);
  await rd.waitForTimeout(600);
  await rd.screenshot({ path: path.join(shots, 'reader.png') });
  const katexCount = await rd.evaluate(() => document.querySelectorAll('.katex').length);
  const aids = await rd.evaluate(() => ({ limits: [...document.querySelectorAll('.limit')].map((e) => e.innerText.replace(/\s+/g, ' ')), goal: [...document.querySelectorAll('.k-goal')].map((e) => e.innerText), cond: [...document.querySelectorAll('.k-cond')].map((e) => e.innerText), breaks: document.querySelectorAll('br.sbr').length }));
  console.log('aids on:', JSON.stringify(aids));
  await rd.screenshot({ path: path.join(shots, 'reader-aids.png') });
  await rd.evaluate(() => window.cfReader.setPrefs({ highlight: false, sentences: false, constraints: false }));
  const off = await rd.evaluate(() => ({ limits: document.querySelectorAll('.limit').length, marks: document.querySelectorAll('.k-goal,.k-cond').length, breaks: document.querySelectorAll('br.sbr').length }));
  console.log('aids off:', JSON.stringify(off));
  console.log('katex nodes:', katexCount, 'errors:', errs);
  await b.close(); srv.close();
})();
