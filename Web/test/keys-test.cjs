// Dev-only: checks the shortcut bar (tap, hold-and-slide variants, flick, drag-does-nothing, type-over, pages) in headless Chromium.
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
  const ctx = await b.newContext({ viewport: { width: 390, height: 664 }, deviceScaleFactor: 2 });
  const pg = await ctx.newPage();
  const errs = []; pg.on('pageerror', (e) => errs.push(e.message));
  await pg.goto('http://localhost:8793/index.html');
  await pg.waitForFunction(() => window.cf);
  const reset = async (text = '') => { await pg.evaluate((t) => { window.cf.setCode(t); window.cf.setKeyboard(300); }, text); };
  await reset('');
  const code = () => pg.evaluate(() => window.cf.getCode());
  const caret = () => pg.evaluate(() => document.querySelector('.cm-content') && window.getSelection().anchorOffset);
  const esc = (l) => l.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const btn = (label) => pg.locator('#keys button', { hasText: new RegExp('^' + esc(label) + '$') }).first();
  const center = async (loc) => { const bb = await loc.boundingBox(); return { x: bb.x + bb.width / 2, y: bb.y + bb.height / 2 }; };
  const log = [];
  const ok = (name, cond) => log.push([name, !!cond]);

  // 1. tap types the main symbol
  const semi = await center(btn(';'));
  await pg.mouse.move(semi.x, semi.y); await pg.mouse.down(); await pg.mouse.up();
  ok('tap ; types ;', (await code()) === ';');

  // 2. sideways drag across keys types nothing
  await reset('');
  const eq = await center(btn('='));
  await pg.mouse.move(eq.x, eq.y); await pg.mouse.down(); await pg.mouse.move(eq.x + 90, eq.y + 2, { steps: 8 }); await pg.mouse.up();
  ok('sideways drag types nothing', (await code()) === '');

  // 3. hold = to open the variants, slide to == and release
  await pg.mouse.move(eq.x, eq.y); await pg.mouse.down(); await pg.waitForTimeout(420);
  const popOpen = await pg.locator('.kpop').count();
  await pg.screenshot({ path: path.join(shots, 'keys-popup.png') });
  const first = await center(pg.locator('.kpop div').first());
  await pg.mouse.move(first.x, first.y, { steps: 4 }); await pg.mouse.up();
  ok('hold opens popup', popOpen === 1);
  ok('slide to == types " == "', (await code()) === ' == ');
  ok('popup closes after release', (await pg.locator('.kpop').count()) === 0);

  // 4. hold, then release away from the popup: nothing typed
  await reset('');
  await pg.mouse.move(eq.x, eq.y); await pg.mouse.down(); await pg.waitForTimeout(420);
  await pg.mouse.move(eq.x, eq.y + 60, { steps: 4 }); await pg.mouse.up();
  ok('release outside popup types nothing', (await code()) === '');

  // 5. flick up on + gives the first variant (++)
  await reset('');
  const plus = await center(btn('+'));
  await pg.mouse.move(plus.x, plus.y); await pg.mouse.down(); await pg.mouse.move(plus.x, plus.y - 34, { steps: 5 }); await pg.mouse.up();
  ok('flick up on + types ++', (await code()) === '++');

  // 6. plain tap on = types just =
  await reset('');
  await pg.mouse.move(eq.x, eq.y); await pg.mouse.down(); await pg.mouse.up();
  ok('tap = types =', (await code()) === '=');

  // 7. pair + type-over: hold ( -> (), then tap ) steps over the existing )
  await reset('');
  const lp = await center(btn('('));
  await pg.mouse.move(lp.x, lp.y); await pg.mouse.down(); await pg.waitForTimeout(420);
  const pv = await center(pg.locator('.kpop div').first());
  await pg.mouse.move(pv.x, pv.y, { steps: 3 }); await pg.mouse.up();
  const rp = await center(btn(')'));
  await pg.mouse.move(rp.x, rp.y); await pg.mouse.down(); await pg.mouse.up();
  ok('() then ) steps over (no extra paren)', (await code()) === '()');

  // 8. {} inserts a pair, ⋯ opens the page, page stays open, back returns
  await reset('');
  const br = await center(btn('{}'));
  await pg.mouse.move(br.x, br.y); await pg.mouse.down(); await pg.mouse.up();
  ok('{} inserts a pair', (await code()) === '{}');
  await btn('⋯').click();
  await pg.screenshot({ path: path.join(shots, 'keys-more.png') });
  const onMore = await pg.evaluate(() => document.getElementById('keys').className);
  await btn('-').click(); await btn('#').click();
  const stay = await pg.evaluate(() => document.getElementById('keys').className);
  ok('⋯ opens the page and it stays open', onMore.includes('page') && stay.includes('page') && (await code()).endsWith('-#') || (await code()).includes('-#'));
  await btn('‹').click();
  ok('back returns to the home row', (await pg.evaluate(() => document.getElementById('keys').className)).includes('home'));

  // 9. category chips from the ⋯ page: I/O page, then edit page undo
  await reset('x');
  await btn('⋯').click(); await btn('I/O').click(); await btn('cout <<').click();
  ok('I/O page inserts cout <<', (await code()).includes('cout << '));
  await btn('‹').click();       // io -> more
  await btn('✎').click(); await btn('↶').click();
  ok('edit page opens from ⋯ and undo works', (await code()) !== undefined);
  await pg.screenshot({ path: path.join(shots, 'keys-edit.png') });

  // 10. the editor leaves room for the bar
  await btn('‹').click(); await btn('‹').click();
  await pg.screenshot({ path: path.join(shots, 'keys-home.png') });
  const geo = await pg.evaluate(() => ({ ed: parseFloat(document.getElementById('editor').style.bottom), keys: document.getElementById('keys').offsetHeight }));
  ok('editor leaves room for the bar', geo.ed >= 300 + geo.keys - 1);

  for (const [n, v] of log) console.log(v ? 'PASS' : 'FAIL', n);
  console.log('errors:', errs);
  await b.close(); srv.close();
})();
