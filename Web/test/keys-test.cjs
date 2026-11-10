// Dev-only: checks the shortcut bar (fire-on-release, drag doesn't type, category pages) in headless Chromium.
// Usage: NODE_PATH=$(npm root -g) node test/keys-test.cjs <screenshot-dir>
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const root = path.resolve(__dirname, '..', 'dist');
const shots = process.argv[2] || '.';
const types = { '.js': 'text/javascript', '.html': 'text/html', '.css': 'text/css' };
const srv = http.createServer((q, r) => {
  const u = decodeURIComponent(q.url.split('?')[0]);
  fs.readFile(path.join(root, u), (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': types[path.extname(u)] || 'application/octet-stream' }); r.end(d); });
}).listen(8793);

(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 390, height: 664 }, deviceScaleFactor: 2, hasTouch: false });
  const pg = await ctx.newPage();
  const errs = []; pg.on('pageerror', (e) => errs.push(e.message));
  await pg.goto('http://localhost:8793/index.html');
  await pg.waitForFunction(() => window.cf);
  await pg.evaluate(() => { window.cf.setCode('int main() {\n    \n}\n'); window.cf.setKeyboard(300); });
  // keyboard 300px covers the bottom of a 664px view, so the bar sits at y = 664-300-height
  const code = () => pg.evaluate(() => window.cf.getCode());
  const btn = (label) => pg.locator('#keys button', { hasText: new RegExp('^' + label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '$') }).first();
  const center = async (loc) => { const bb = await loc.boundingBox(); return { x: bb.x + bb.width / 2, y: bb.y + bb.height / 2 }; };
  const log = [];

  // 1. a clean tap types the key
  const semi = await center(btn(';'));
  await pg.mouse.move(semi.x, semi.y); await pg.mouse.down(); await pg.mouse.up();
  log.push(['tap ;', (await code()).includes(';')]);

  // 2. press, drag far away, release: must NOT type
  const before = await code();
  const sq = await center(btn('<<'));
  await pg.mouse.move(sq.x, sq.y); await pg.mouse.down(); await pg.mouse.move(sq.x + 60, sq.y + 2, { steps: 6 }); await pg.mouse.up();
  log.push(['drag does not type <<', (await code()) === before]);

  // 3. press, slide sideways and release over another key: must NOT type either
  const pa = await center(btn('()'));
  await pg.mouse.move(pa.x, pa.y); await pg.mouse.down(); await pg.mouse.move(semi.x, semi.y, { steps: 8 }); await pg.mouse.up();
  log.push(['slide to another key does not type', (await code()) === before]);

  await pg.screenshot({ path: path.join(shots, 'keys-home.png') });

  // 4. category page opens, shows items, picking one returns home
  await btn('I/O').click();
  const onPage = await pg.evaluate(() => document.getElementById('keys').className);
  await pg.screenshot({ path: path.join(shots, 'keys-io.png') });
  await btn('cout <<').click();
  await btn('endl').click();
  const afterPick = await pg.evaluate(() => document.getElementById('keys').className);
  log.push(['page opens', onPage.includes('page')]);
  log.push(['picks insert and the page stays open', (await code()).includes('cout << ') && (await code()).includes('endl') && afterPick.includes('page')]);
  await btn('‹').click();
  log.push(['back returns to the home row', (await pg.evaluate(() => document.getElementById('keys').className)).includes('home')]);

  // 5. editor shrinks to make room for the bar (no overlap)
  const geo = await pg.evaluate(() => ({ ed: parseFloat(document.getElementById('editor').style.bottom), keys: document.getElementById('keys').offsetHeight }));
  log.push(['editor leaves room for bar', geo.ed >= 300 + geo.keys - 1]);

  // 6. Edit page is sticky and its actions work (undo)
  await btn('✎').click();
  await btn('↶').click();
  const stillPage = await pg.evaluate(() => document.getElementById('keys').className.includes('page'));
  log.push(['edit page stays open', stillPage]);
  await pg.screenshot({ path: path.join(shots, 'keys-edit.png') });

  // 7. Code page: 'for' inserts a loop with the caret inside
  await btn('‹').click(); await btn('for').click(); await btn('for').click();
  await pg.screenshot({ path: path.join(shots, 'keys-code.png') });
  log.push(['for loop inserted', /for \(int i = 0; i < n; i\+\+\) \{/.test(await code())]);

  for (const [n, ok] of log) console.log(ok ? 'PASS' : 'FAIL', n);
  console.log('errors:', errs);
  await b.close(); srv.close();
})();
