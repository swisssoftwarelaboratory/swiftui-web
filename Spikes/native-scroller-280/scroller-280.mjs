// PROTOTYPE check (new-website#280): opens the scroll prototype page from disk in Playwright's
// WebKit at laptop size, wheels Home down and back in each mode, and prints how the native box
// and the app's scroll view moved, frame by frame. Usage: node scroller-280.mjs <out dir>
import { webkit } from 'playwright';
import fs from 'fs';
import path from 'path';
const out = process.argv[2] || '/tmp/scroller-280';
fs.mkdirSync(out, { recursive: true });
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../phone/public');
const secret = fs.readFileSync(path.join(root, '../secret.txt'), 'utf8').trim();
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png' };
const browser = await webkit.launch();
const results = {};
for (const mode of (process.env.MODES || 'ours,native,nobounce').split(',')) {
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
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto(`https://proto.test/${secret}/scroller/?scroll=${mode}`);
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 120000 });
  await page.waitForTimeout(2500);
  const box = await page.evaluate(() => { const r = document.getElementById('app').getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; });
  await page.mouse.move(box.x + box.w / 2, box.y + box.h * 0.45);
  await page.waitForTimeout(400);
  await page.evaluate(() => {
    window.__trace = [];
    const d = window.__swiftuiwebDebug;
    const tick = () => {
      const s = document.getElementById('native-scroller');
      const v = d.scrollViews().filter(v => v[7] > 0 && v[8] === 1);
      window.__trace.push([Math.round(performance.now()), d.frameCount(), s ? s.scrollTop : null, v.length ? v[0][5] : null]);
      if (window.__trace.length < 600) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  });
  // A trackpad-like swipe down: 30 events, 8 ms apart, falling deltas; then back up.
  for (let i = 0; i < 30; i++) { await page.mouse.wheel(0, Math.max(2, 40 - i * 1.3)); await page.waitForTimeout(8); }
  await page.waitForTimeout(500);
  await page.screenshot({ path: `${out}/${mode}-down.png`, clip: { x: box.x - 20, y: box.y - 10, width: box.w + 40, height: Math.min(box.h + 20, 860 - box.y + 10) } });
  for (let i = 0; i < 60; i++) { await page.mouse.wheel(0, -40); await page.waitForTimeout(8); }
  await page.waitForTimeout(600);
  const trace = await page.evaluate(() => window.__trace);
  const state = await page.evaluate(() => window.__scrollProto && window.__scrollProto.state ? window.__scrollProto.state() : null);
  await page.screenshot({ path: `${out}/${mode}-top.png` });
  // Taps still work: the tab bar's second item.
  await page.mouse.click(box.x + box.w * 0.375, box.y + box.h - 45);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: `${out}/${mode}-tab2.png`, clip: { x: box.x - 20, y: box.y - 10, width: box.w + 40, height: Math.min(box.h + 20, 860 - box.y + 10) } });
  // And the new tab's own list scrolls through the box.
  await page.mouse.move(box.x + box.w / 2, box.y + box.h * 0.45);
  await page.waitForTimeout(400);
  for (let i = 0; i < 20; i++) { await page.mouse.wheel(0, 30); await page.waitForTimeout(8); }
  await page.waitForTimeout(500);
  const tab2 = await page.evaluate(() => window.__swiftuiwebDebug.scrollViews().filter(v => v[8] === 1 && v[7] > 0).map(v => [Math.round(v[5]), Math.round(v[7])]));
  await page.screenshot({ path: `${out}/${mode}-tab2-scrolled.png`, clip: { x: box.x - 20, y: box.y - 10, width: box.w + 40, height: Math.min(box.h + 20, 860 - box.y + 10) } });
  results[mode] = { errors, state, tab2, trace: trace.filter((r, i) => i === 0 || r[2] !== trace[i - 1][2] || r[3] !== trace[i - 1][3]).slice(0, 80) };
  await context.close();
}
fs.writeFileSync(`${out}/results.json`, JSON.stringify(results, null, 1));
for (const [m, r] of Object.entries(results)) {
  const ends = r.trace.map(x => x[3]).filter(x => x != null);
  console.log(m, 'errors', r.errors.length, r.errors.slice(0, 3), 'max app offset', Math.max(...ends, 0), 'state', JSON.stringify(r.state), 'tab2', JSON.stringify(r.tab2));
}
await browser.close();
