// PROTOTYPE check (new-website#280): prints every scroll view on Home from the prototype build.
import { webkit } from 'playwright';
import fs from 'fs';
import path from 'path';
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../phone/public');
const secret = fs.readFileSync(path.join(root, '../secret.txt'), 'utf8').trim();
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' };
const browser = await webkit.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 860 }, deviceScaleFactor: 2 });
await context.route('https://proto.test/**', async route => {
  const u = new URL(route.request().url());
  if (u.pathname.endsWith('/b')) return route.fulfill({ status: 204 });
  let p = path.join(root, decodeURIComponent(u.pathname));
  if (p.endsWith('/')) p += 'index.html';
  if (!fs.existsSync(p)) return route.fulfill({ status: 404 });
  route.fulfill({ status: 200, body: fs.readFileSync(p), contentType: types[path.extname(p)] || 'application/octet-stream' });
});
const page = await context.newPage();
await page.goto(`https://proto.test/${secret}/scroller/?scroll=ours`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 120000 });
await page.waitForTimeout(2500);
console.log(JSON.stringify(await page.evaluate(() => window.__swiftuiwebDebug.scrollViews().map(v => v.map(x => Math.round(x))))));
const box = await page.evaluate(() => { const r = document.getElementById('app').getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; });
await page.mouse.move(box.x + box.w / 2, box.y + box.h * 0.45);
await page.mouse.wheel(0, 50);
await page.waitForTimeout(300);
console.log(JSON.stringify(await page.evaluate(() => window.__swiftuiwebDebug.scrollViews().map(v => v.map(x => Math.round(x))))));
await browser.close();
