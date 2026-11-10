const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const root = path.resolve(__dirname, '..', 'dist');
const types = { '.js': 'text/javascript', '.html': 'text/html', '.css': 'text/css' };
const srv = http.createServer((q, r) => { const u = decodeURIComponent(q.url.split('?')[0]); fs.readFile(path.join(root, u), (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': types[path.extname(u)] || 'application/octet-stream' }); r.end(d); }); }).listen(8794);
(async () => {
  const b = await chromium.launch(); const pg = await (await b.newContext({ viewport: { width: 390, height: 600 } })).newPage();
  await pg.goto('http://localhost:8794/reader.html'); await pg.waitForFunction(() => window.cfReader);
  const text = () => pg.evaluate(() => document.querySelector('.tags')?.innerText || '');
  const render = (o) => pg.evaluate((o) => window.cfReader.render(Object.assign({ title: 'T', html: '<p>x</p>', tags: ['dp', 'math'], rating: 1500, samples: [] }, o)), o);
  await render({ hideTags: true, hideRating: true }); const a = await text();
  await pg.click('.tag.peek'); const a2 = await text();
  await render({ hideTags: true, hideRating: false }); const c = await text();
  await render({}); const d = await text();
  console.log(JSON.stringify({ hiddenBoth: a, afterTap: a2, tagsOnlyHidden: c, nothingHidden: d }));
  await b.close(); srv.close();
})();
