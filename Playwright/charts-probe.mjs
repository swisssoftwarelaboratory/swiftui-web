// Swift Charts Examples (Apps/upstream/Swift-Charts-Examples, unmodified; decision 0021) in
// headless Chromium on a phone-sized page: the split view collapses to its "Charts" list of
// sections with a preview per chart (ImageRenderer's recording, replayed), the list scrolls, a row
// pushes its chart (bars painted), the chart's slider changes the bar width, Back returns, and
// the toolbar's Filter menu narrows the list to one category. All data is the app's own.
//   node charts-probe.mjs http://127.0.0.1:8781/index.html?platform=ios [--out ../.build/apps/charts]
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const url = process.argv[2];
const outIndex = process.argv.indexOf('--out');
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = outIndex > 0 ? process.argv[outIndex + 1] : join(root, '.build', 'apps', 'charts');
mkdirSync(out, { recursive: true });
const git = (args) => { try { return execSync(`git ${args}`, { cwd: root, encoding: 'utf8' }).trim(); } catch { return 'unknown'; } };
const dirty = git('status --porcelain --untracked-files=normal').split('\n').filter(Boolean);
const report = {
  app: 'Swift Charts Examples', upstream: 'https://github.com/jordibruin/Swift-Charts-Examples',
  tested_commit: git('rev-parse HEAD'), working_tree: dirty.length ? `dirty: ${dirty.length} path(s) differ from the commit` : 'clean',
  app_pinned_revision: git('ls-files --stage Apps/upstream/Swift-Charts-Examples').split(/\s+/)[1] || 'unknown',
  sdk: 'swift-6.4.2-RELEASE_wasm', browser: null, url, started: new Date().toISOString(),
  full_app_pass: false, flows: {}, problems: [], screenshots: [], trace: null,
};
const FLOWS = ['launch', 'previews', 'scroll', 'detail', 'slider', 'back', 'filter'];
for (const f of FLOWS) report.flows[f] = { outcome: 'not-run' };
let current = null;
const begin = (name) => { current = name; report.flows[name] = { outcome: 'passed' }; };
const problems = report.problems;
const expect = (ok, message) => { if (!ok) { problems.push(message); if (current) report.flows[current] = { outcome: 'failed', detail: message }; } return ok; };
const note = (detail) => { if (current && report.flows[current].outcome === 'passed') report.flows[current].detail = detail; };

const browser = await chromium.launch();
report.browser = browser.version();
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
await context.tracing.start({ screenshots: true, snapshots: false });
const page = await context.newPage();
page.on('pageerror', e => problems.push('pageerror: ' + e.message + ' ' + (e.stack || '').split('\n').slice(1, 6).join(' <- ')));
page.on('console', m => { if (m.type() === 'error') problems.push('console: ' + m.text().slice(0, 300)); });
const shot = async (name) => { const file = join(out, name + '.png'); try { await page.screenshot({ path: file }); report.screenshots.push(name + '.png'); } catch (e) { problems.push('screenshot ' + name + ': ' + e.message); } };
const list = () => page.evaluate(() => window.__swiftuiwebDebug.displayList());
// The painted texts with their positions (drawText("…" font size wN at x,y …)).
const drawn = async () => (await list()).filter(c => c.startsWith('drawText')).map(c => {
  const m = c.match(/^drawText\("([^"]*)" (\S+) [\d.]+ w\d+ at ([-\d.]+),([-\d.]+)/);
  return m ? { text: m[1], x: +m[3], y: +m[4] } : { text: c.match(/"([^"]*)"/)?.[1] ?? c, x: 0, y: 0 };
});
const texts = async () => (await drawn()).map(d => d.text);
const settle = async (ready, tries = 60) => { let t = await texts(); for (let i = 0; i < tries && !ready(t); i++) { await page.waitForTimeout(250); t = await texts(); } return t; };
const onScreen = async (text) => (await drawn()).find(d => d.text === text && d.y > 0 && d.y < 844);
// Waits for a text to stop moving (a fling's momentum): a tap during it only stops the scroll.
const still = async (text) => {
  let previous = await onScreen(text);
  for (let i = 0; i < 30; i++) {
    await page.waitForTimeout(150);
    const current = await onScreen(text);
    if (previous && current && previous.x === current.x && previous.y === current.y) return current;
    previous = current;
  }
  return previous;
};
const tapText = async (text) => {
  const hit = await onScreen(text);
  if (!hit) return false;
  await page.touchscreen.tap(hit.x + 10, hit.y - 6);
  return true;
};
const tapLabel = async (label) => {
  const box = await page.locator(`[aria-label="${label}"]`).first().boundingBox().catch(() => null);
  if (!box) return false;
  await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
  return true;
};
// A finger drag up the list (CDP touches: the host's touch scrolling, with its momentum).
const cdp = await context.newCDPSession(page);
const swipeUp = async (distance = 400) => {
  const x = 195, y0 = 700;
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y: y0 }] });
  for (let i = 1; i <= 10; i++) await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y0 - distance * i / 10 }] });
  // Held still before the lift, so the list moves the drag's distance and does not fling: a
  // fling's length depends on the runner's speed and could carry a row past between looks.
  await page.waitForTimeout(200);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y0 - distance }] });
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await page.waitForTimeout(300);
};
const count = (commands, prefix) => commands.filter(c => c.startsWith(prefix)).length;

try {
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });

  begin('launch');
  let t = await settle(t => t.includes('Charts') && t.includes('Electrocardiograms (ECG)'));
  await shot('01-launch');
  expect(t.includes('Charts'), `no "Charts" title; painted: ${t.slice(0, 30).join(' | ')}`);
  expect(t.includes('Electrocardiograms (ECG)') && t.includes('iPhone Storage'), `the first section's charts are not listed; painted: ${t.slice(0, 30).join(' | ')}`);
  note(`${t.length} texts painted, the apple section first`);

  // Each row shows its chart drawn by ImageRenderer at launch: the recording replays as drawing
  // commands, so the previews' own texts (the ECG's average, the storage total) are painted.
  begin('previews');
  t = await texts();
  const ecg = t.find(s => s.includes('BPM Average')), storage = t.find(s => s.includes('GB of 128 GB Used'));
  const fills = count(await list(), 'fill');
  expect(!!ecg && !!storage, `the first previews' texts are not painted; painted: ${t.slice(0, 30).join(' | ')}`);
  expect(fills >= 20, `${fills} filled shapes on the first screen`);
  note(`"${ecg}" and "${storage}" painted, ${fills} filled shapes`);

  begin('scroll');
  for (let i = 0; i < 20 && !(await onScreen('Single Bar')); i++) await swipeUp();
  await shot('02-scrolled');
  expect(!!(await onScreen('Single Bar')), `"Single Bar" never scrolled into view; painted: ${(await texts()).slice(0, 30).join(' | ')}`);

  begin('detail');
  await still('Single Bar');
  expect(await tapText('Single Bar'), 'no "Single Bar" row to tap');
  t = await settle(t => t.some(s => s.startsWith('Bar Width: ')), 20);
  if (!t.some(s => s.startsWith('Bar Width: '))) {
    // A tap that landed while the list still moved only stopped it (as on iOS): tap again.
    await still('Single Bar');
    await tapText('Single Bar');
    t = await settle(t => t.some(s => s.startsWith('Bar Width: ')));
  }
  await page.waitForTimeout(1200);   // the bars rise into place, one after another
  await shot('03-single-bar');
  const aria = await page.evaluate(() => [...document.querySelectorAll('[aria-label]')].map(e => `${e.getAttribute('role') || e.tagName.toLowerCase()}:${e.getAttribute('aria-label')}`).slice(0, 40).join(' | '));
  expect(t.includes('Bar Width: 7.0'), `the Single Bar chart did not open; painted: ${t.slice(0, 30).join(' | ')}; accessibility: ${aria}`);
  const bars = (await list()).filter(c => /^fill(Rect|Path|RRect|Gradient)/.test(c)).length;   // the bars are gradient fills
  expect(bars >= 30, `${bars} filled shapes in the chart (30 days of bars)`);
  note(`the chart and its controls, ${bars} filled shapes`);

  // The slider (an <input type=range> in the accessibility overlay, which the runtime follows).
  begin('slider');
  const slider = page.locator('[aria-label="Bar Width"]').first();
  if (expect(await slider.count() > 0, 'no slider labelled "Bar Width"')) {
    await slider.focus();
    for (let i = 0; i < 5; i++) await page.keyboard.press('ArrowRight');
    t = await settle(t => t.some(s => s.startsWith('Bar Width: ') && s !== 'Bar Width: 7.0'), 20);
    const label = t.find(s => s.startsWith('Bar Width: '));
    await shot('04-slider');
    expect(label && label !== 'Bar Width: 7.0', `the bar width label stayed "${label}" after five arrow presses`);
    note(`the label reads "${label}"`);
  }

  begin('back');
  const backed = (await tapLabel('Back')) || (await tapText('Charts'));
  expect(backed, 'no Back button');
  t = await settle(t => !t.some(s => s.startsWith('Bar Width: ')) && t.includes('Single Bar'));
  await shot('05-back');
  expect(!t.some(s => s.startsWith('Bar Width: ')) && t.includes('Single Bar'), `the list did not come back; painted: ${t.slice(0, 30).join(' | ')}`);

  // The toolbar's Filter menu holds a picker of the categories: Bar leaves only bar charts.
  begin('filter');
  const opened = (await tapLabel('Filter')) || (await tapText('Filter'));
  expect(opened, 'no Filter button');
  t = await settle(t => t.includes('Bar') && t.includes('Show all'), 20);
  await shot('06-filter-menu');
  expect(t.includes('Show all'), `the Filter menu did not open; painted: ${t.slice(0, 30).join(' | ')}`);
  const picked = (await tapLabel('Bar')) || (await tapText('Bar'));
  expect(picked, 'no "Bar" row in the menu');
  // The list keeps its scroll position, so the bar section may show from any of its rows.
  const barRow = t => ['Single Bar', 'Two Bars', 'Pyramid', 'Time Sheet Bar'].some(r => t.includes(r));
  t = await settle(t => !t.includes('Show all') && barRow(t) && !t.includes('line') && !t.includes('apple'));
  await shot('07-filtered');
  expect(barRow(t) && t.includes('bar') && !t.includes('line') && !t.includes('apple') && !t.includes('Electrocardiograms (ECG)'), `the list was not narrowed to bar charts; painted: ${t.slice(0, 30).join(' | ')}`);

  report.full_app_pass = Object.values(report.flows).every(f => f.outcome === 'passed') && problems.length === 0;
} catch (e) {
  problems.push('probe: ' + e.message);
} finally {
  try { await context.tracing.stop({ path: join(out, 'trace.zip') }); report.trace = 'trace.zip'; } catch {}
  await browser.close();
  report.finished = new Date().toISOString();
  writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ full_app_pass: report.full_app_pass, flows: report.flows, problems: report.problems }, null, 2));
}
process.exit(report.full_app_pass ? 0 : 1);
