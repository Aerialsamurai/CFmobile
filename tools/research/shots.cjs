const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const out = process.argv[2];
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  for (const c of ['speed', 'swipe', 'smart', 'grid', 'keyboard', 'current']) {
    const pg = await ctx.newPage();
    await pg.goto('file://' + path.resolve(__dirname, 'concepts.html') + '?c=' + c);
    await pg.waitForTimeout(150);
    await pg.screenshot({ path: path.join(out, 'concept-' + c + '.raw.png') });
    await pg.close();
  }
  await b.close();
})();
