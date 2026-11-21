// Scrolling probe: opens a scroll fixture in the gallery, sends wheel events over the canvas,
// checks the content moved (via the debug bridge) and reports frames per wheel event plus the
// mean frame interval while scrolling; saves a screenshot mid-scroll (indicator visible).
//   node scroll-probe.mjs http://127.0.0.1:8090/index.html [--fixture scroll/long] [--browser chromium] [--out ../.build/scroll-probe]
import { chromium, webkit, firefox } from 'playwright';
import { mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const url = args.find(a => !a.startsWith('--'));
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const fixture = opt('--fixture', 'scroll/long');
const out = opt('--out', join(here, '..', '.build', 'scroll-probe'));
mkdirSync(out, { recursive: true });

const browser = await { chromium, webkit, firefox }[opt('--browser', 'chromium')].launch();
const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 1280, height: 900 } });
const errors = [];
page.on('pageerror', e => errors.push(e.message));
await page.goto(`${url}?fixture=${encodeURIComponent(fixture)}`, { timeout: 120000 });
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 120000 });
await page.waitForTimeout(100);

const canvas = page.locator('#app canvas');
const box = await canvas.boundingBox();
const frames = () => page.evaluate(() => window.__galleryFrames);
const frameCount = () => page.evaluate(() => window.__swiftuiwebDebug.frameCount());
const before = await frames();
await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);

// One real wheel event through the browser (checks the listener and preventDefault), then 60
// synthetic 40 px ticks dispatched in the page, one per animation frame, collecting the host's
// own layout + paint time per frame from the debug bridge.
// Seen on the window in the capture phase: a real vertical wheel goes to the browser's own scroll
// box over the canvas (new-website#404), which stops it there, so a listener on the canvas never
// hears it. The box scrolls with the browser's own animation and the next frame copies it to the
// content, so the probe waits for the content to move (up to 2 s) rather than a fixed 50 ms, which a
// slow runner missed (new-website#706).
await page.evaluate(() => { window.__wheelDeltas = []; window.addEventListener('wheel', e => window.__wheelDeltas.push([e.deltaY, e.deltaMode]), { capture: true }); });
await page.mouse.wheel(0, 40);
await page.waitForFunction(y => window.__galleryFrames.content.y < y, before.content.y, { timeout: 2000 }).catch(() => {});
const afterOne = await frames();
console.log(`real wheel event(s) seen by the page: ${JSON.stringify(await page.evaluate(() => window.__wheelDeltas))}`);
const startFrames = await frameCount();
const millis = await page.evaluate(async () => {
  const canvas = document.querySelector('#app canvas');
  const rect = canvas.getBoundingClientRect();
  const samples = [];
  for (let i = 0; i < 60; i++) {
    canvas.dispatchEvent(new WheelEvent('wheel', { deltaY: 40, deltaMode: 0, bubbles: true, cancelable: true,
                                                   clientX: rect.left + rect.width / 2, clientY: rect.top + rect.height / 2 }));
    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
    samples.push(window.__swiftuiwebDebug.frameMillis());
  }
  return samples;
});
await canvas.screenshot({ path: join(out, 'mid-scroll.png') });
const painted = (await frameCount()) - startFrames;
const after = await frames();
const sorted = [...millis].sort((a, b) => a - b);
console.log(`${fixture}: content.y ${before.content.y} -> ${afterOne.content.y} after one real wheel event, -> ${after.content.y} after 60 synthetic 40 px ticks (${painted} frames painted)`);
console.log(`layout + paint per frame: median ${sorted[30].toFixed(2)} ms, p90 ${sorted[54].toFixed(2)} ms, max ${sorted[59].toFixed(2)} ms`);

// Single real ticks from rest (new-website#706): CI lost the first real tick of a scroll about
// half the time since the browser's own scroll box took vertical wheels (new-website#404). Each
// trial waits at the top until the box is at rest, sends one real 40 px tick and logs what the
// page saw: the box (scrollTop, scrollHeight, clientHeight), the scene's driven view, whether
// the tick was cancelled, the box's scroll events, and where the content stood after up to 1 s.
const trials = [];
async function singleTick(label) {
  const state = await page.evaluate(() => {
    const box = document.querySelector('[data-swiftuiweb-scroller]');
    window.__tick = { wheels: [], scrolls: 0 };
    window.addEventListener('wheel', e => setTimeout(() => window.__tick.wheels.push({ dy: e.deltaY, prevented: e.defaultPrevented, target: e.target.tagName + (e.target.hasAttribute && e.target.hasAttribute('data-swiftuiweb-scroller') ? '[box]' : '') })), { capture: true, once: true });
    box && box.addEventListener('scroll', () => window.__tick.scrolls++);
    const hit = document.elementFromPoint(innerWidth / 2, innerHeight / 2);
    return { box: box ? [box.scrollTop, box.scrollHeight, box.clientHeight] : null, native: window.__swiftuiwebDebug.nativeScroller?.(), hit: hit && hit.tagName };
  });
  const y0 = (await frames()).content.y;
  const t0 = Date.now();
  await page.mouse.wheel(0, 40);
  const moved = await page.waitForFunction(y => window.__galleryFrames.content.y < y, y0, { timeout: 1000 }).then(() => true, () => false);
  const ms = Date.now() - t0;
  const y1 = (await frames()).content.y;
  const seen = await page.evaluate(() => { const box = document.querySelector('[data-swiftuiweb-scroller]'); return { ...window.__tick, boxTop: box && box.scrollTop, native: window.__swiftuiwebDebug.nativeScroller?.() }; });
  console.log(`${label}: ${moved ? 'moved' : 'LOST'} ${y0} -> ${y1} in ${ms} ms; before ${JSON.stringify(state)}; after ${JSON.stringify(seen)}`);
  trials.push(moved);
}
// Scroll back up past the top: must clamp at 0.
let ticks = 0;
while ((await frames()).content.y < 0 && ticks < 400) { await page.mouse.wheel(0, -40); ticks++; }
await page.mouse.wheel(0, -40);
await page.waitForTimeout(100);
const top = await frames();
console.log(`after scrolling back with ${ticks + 1} real wheel ticks: content.y ${top.content.y} (expected 0)`);
// The indicator fades: no fillRRect once the fade is over.
await page.waitForTimeout(1200);
const list = await page.evaluate(() => window.__swiftuiwebDebug.displayList());
console.log(`display list after the fade: ${list.length} commands, indicator ${list.some(c => c.startsWith('fillRRect')) ? 'still visible' : 'gone'}`);
await canvas.screenshot({ path: join(out, 'after-fade.png') });
for (let i = 0; i < 8; i++) {
  let n = 0;
  while ((await frames()).content.y < 0 && n < 400) { await page.mouse.wheel(0, -200); n++; }
  await page.waitForTimeout(i % 2 ? 1200 : 300);
  await singleTick(`single tick ${i + 1} (rest ${i % 2 ? 1200 : 300} ms)`);
}
console.log(`single real ticks that moved the content: ${trials.filter(Boolean).length}/${trials.length}`);
if (errors.length) console.log('page errors:\n' + errors.join('\n'));
await browser.close();
process.exit(errors.length || trials.some(m => !m) || afterOne.content.y >= before.content.y || after.content.y >= afterOne.content.y || top.content.y !== 0 || list.some(c => c.startsWith('fillRRect')) ? 1 : 0);
