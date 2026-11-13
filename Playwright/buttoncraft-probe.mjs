// buttoncraft (Apps/upstream/buttoncraft, unmodified; decision 0021) in headless Chromium on a
// phone-sized page: the title and the effect cards with their values, a held press on a styled
// button (its ButtonStyle's pressed look, then back at rest), the Scale Effect slider moved by the
// keyboard (its label follows), the reset button (the value comes back), the Animation switch (the
// spring cards go and come back), and the code panel (the generated snippet, Copied). All data is
// the app's own.
//   node buttoncraft-probe.mjs http://127.0.0.1:8782/index.html?platform=ios [--out ../.build/apps/buttoncraft]
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const url = process.argv[2];
const outIndex = process.argv.indexOf('--out');
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = outIndex > 0 ? process.argv[outIndex + 1] : join(root, '.build', 'apps', 'buttoncraft');
mkdirSync(out, { recursive: true });
const git = (args) => { try { return execSync(`git ${args}`, { cwd: root, encoding: 'utf8' }).trim(); } catch { return 'unknown'; } };
const dirty = git('status --porcelain --untracked-files=normal').split('\n').filter(Boolean);
const report = {
  app: 'buttoncraft', upstream: 'https://github.com/atrinh0/buttoncraft',
  tested_commit: git('rev-parse HEAD'), working_tree: dirty.length ? `dirty: ${dirty.length} path(s) differ from the commit` : 'clean',
  app_pinned_revision: git('ls-files --stage Apps/upstream/buttoncraft').split(/\s+/)[1] || 'unknown',
  sdk: 'swift-6.4.2-RELEASE_wasm', browser: null, url, started: new Date().toISOString(),
  full_app_pass: false, flows: {}, problems: [], screenshots: [], trace: null,
};
const FLOWS = ['launch', 'press', 'slider', 'reset', 'toggle', 'code'];
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
const drawn = async () => (await list()).filter(c => c.startsWith('drawText')).map(c => {
  const m = c.match(/^drawText\("([^"]*)" (\S+) [\d.]+ w\d+ at ([-\d.]+),([-\d.]+)/);
  return m ? { text: m[1], x: +m[3], y: +m[4] } : { text: c.match(/"([^"]*)"/)?.[1] ?? c, x: 0, y: 0 };
});
const texts = async () => (await drawn()).map(d => d.text);
const settle = async (ready, tries = 60) => { let t = await texts(); for (let i = 0; i < tries && !ready(t); i++) { await page.waitForTimeout(250); t = await texts(); } return t; };
const onScreen = async (text) => (await drawn()).find(d => d.text === text && d.y > 0 && d.y < 844);
const box = (selector) => page.locator(selector).first().boundingBox().catch(() => null);
const tapBox = async (b) => { if (!b) return false; await page.touchscreen.tap(b.x + b.width / 2, b.y + b.height / 2); return true; };
const cdp = await context.newCDPSession(page);
// A finger drag up the scroll view, held still before the lift so it does not fling.
const swipeUp = async (distance = 300) => {
  const x = 195, y0 = 700;
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y: y0 }] });
  for (let i = 1; i <= 10; i++) await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y0 - distance * i / 10 }] });
  await page.waitForTimeout(200);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y0 - distance }] });
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await page.waitForTimeout(300);
};
const scale = t => t.find(s => /^\d+%$/.test(s));
// The accessibility overlay's buttons with their labels and boxes (a symbol button reads as its
// symbol's name when the runtime gives it one; else its place on screen picks it out).
const buttons = () => page.evaluate(() => [...document.querySelectorAll('button, [role="button"]')].map(e => {
  const r = e.getBoundingClientRect();
  return { label: e.getAttribute('aria-label') || e.textContent || '', x: r.x, y: r.y, width: r.width, height: r.height };
}).filter(b => b.width > 0 && b.height > 0));
const button = async (name, where) => {
  const all = await buttons();
  return all.find(b => b.label.includes(name)) || all.filter(where).sort((a, b) => a.y - b.y)[0] || null;
};
const centre = b => ({ x: b.x + b.width / 2, y: b.y + b.height / 2 });
const animationSwitch = '[aria-label="Animation"][role="switch"], [aria-label="Animation"][role="checkbox"]';

try {
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });

  begin('launch');
  let t = await settle(t => t.includes('buttoncraft') && t.includes('Scale Effect'));
  await shot('01-launch');
  expect(t.includes('buttoncraft'), `no "buttoncraft" title; painted: ${t.slice(0, 30).join(' | ')}`);
  expect(['Scale Effect', 'Rotation Effect', 'Blur Radius', 'tap here', 'or here'].every(s => t.includes(s)), `the cards and buttons are not all painted; painted: ${t.slice(0, 30).join(' | ')}`);
  expect(t.includes('85%') && t.includes('0 degrees') && t.includes('0.0'), `the default values (85%, 0 degrees, 0.0) are not painted; painted: ${t.slice(0, 30).join(' | ')}`);
  report.buttons = (await buttons()).map(b => `${b.label}@${Math.round(b.x)},${Math.round(b.y)}`);
  note(`${t.length} texts painted, Scale Effect ${scale(t)}`);

  // A held touch on "tap here": its ButtonStyle scales the label and fills the capsule with the
  // pressed colour (isPressed), and the spring takes it back at rest after the lift.
  begin('press');
  const tap = await onScreen('tap here');
  if (expect(!!tap, 'no "tap here" button on screen')) {
    const rest = JSON.stringify(await list());
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: tap.x + 20, y: tap.y - 6 }] });
    await page.waitForTimeout(800);
    const pressed = JSON.stringify(await list());
    const moved = (await drawn()).find(d => d.text === 'tap here');
    await shot('02-pressed');
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    let back = JSON.stringify(await list());
    for (let i = 0; i < 40 && back !== rest; i++) { await page.waitForTimeout(100); back = JSON.stringify(await list()); }
    expect(pressed !== rest, 'the held press changed nothing on screen');
    expect(back === rest, 'the button did not come back to rest after the lift');
    note(`the label moved from ${tap.x},${tap.y} to ${moved?.x},${moved?.y} while held`);
  }

  // The Scale Effect slider (an <input type=range> in the accessibility overlay): three steps of
  // 0.05 up from 0.85.
  begin('slider');
  const slider = page.locator('input[type=range]').first();
  if (expect(await slider.count() > 0, 'no slider')) {
    await slider.focus();
    for (let i = 0; i < 3; i++) await page.keyboard.press('ArrowRight');
    t = await settle(t => scale(t) === '100%', 20);
    await shot('03-slider');
    expect(scale(t) === '100%', `the Scale Effect label reads "${scale(t)}" after three arrow presses, not 100%`);
    note(`the label reads "${scale(t)}"`);
  }

  begin('reset');
  // The top bar's trailing button.
  const reset = await button('Arrow Counterclockwise', b => centre(b).x > 260 && centre(b).y < 200);
  if (expect(!!reset, `no reset button; buttons: ${(await buttons()).map(b => `${b.label}@${Math.round(b.x)},${Math.round(b.y)}`).join(' | ')}`)) {
    await tapBox(reset);
    t = await settle(t => scale(t) === '85%', 20);
    await shot('04-reset');
    expect(scale(t) === '85%', `the Scale Effect label reads "${scale(t)}" after reset, not 85%`);
  }

  // The Animation switch shows and hides the two spring cards.
  begin('toggle');
  for (let i = 0; i < 6 && !(await box(animationSwitch)); i++) await swipeUp();
  let toggle = await box(animationSwitch);
  for (let i = 0; i < 6 && toggle && toggle.y + toggle.height > 800; i++) { await swipeUp(); toggle = await box(animationSwitch); }
  if (expect(!!toggle, 'no Animation switch')) {
    const before = await page.locator(animationSwitch).first().getAttribute('aria-checked');
    expect(before === 'true', `the Animation switch starts ${before}, not on`);
    expect((await texts()).includes('Spring Stiffness'), 'no Spring Stiffness card while animation is on');
    await tapBox(toggle);
    t = await settle(t => !t.includes('Spring Stiffness'), 20);
    await shot('05-animation-off');
    expect(!t.includes('Spring Stiffness') && !t.includes('Spring Damping'), 'the spring cards stayed after the switch went off');
    expect(await page.locator(animationSwitch).first().getAttribute('aria-checked') === 'false', 'the switch did not read off');
    await tapBox(await box(animationSwitch));
    t = await settle(t => t.includes('Spring Stiffness') && t.includes('Spring Damping'), 20);
    expect(t.includes('Spring Stiffness') && t.includes('Spring Damping'), 'the spring cards did not come back');
  }

  // The curly braces button opens the code panel with the snippet for the current style; its
  // copy button shows "Copied" for a second.
  begin('code');
  // The centred button under the last card (the damping card's footnote).
  const bracesButton = async () => {
    const footnote = (await drawn()).find(d => d.text.startsWith('(low for bouncier'));
    return button('Curlybraces', b => footnote && centre(b).y > footnote.y && Math.abs(centre(b).x - 195) < 60);
  };
  let braces = await bracesButton();
  for (let i = 0; i < 8 && (!braces || braces.y + braces.height > 800); i++) { await swipeUp(); braces = await bracesButton(); }
  if (expect(!!braces, `no code button; buttons: ${(await buttons()).map(b => `${b.label}@${Math.round(b.x)},${Math.round(b.y)}`).join(' | ')}`)) {
    await tapBox(braces);
    const snippet = t => t.some(s => s.includes('struct MyButtonStyle: ButtonStyle'));
    t = await settle(snippet, 20);
    await page.waitForTimeout(600);
    await shot('06-code');
    expect(snippet(t), `the code panel did not open; painted: ${t.slice(-30).join(' | ')}`);
    // The snippet's lines may wrap at the panel's width: the scale is looked for in all of it.
    const code = (await texts()).join(' ');
    expect(code.includes('CGFloat(0.85)'), `the snippet does not carry the scale 0.85; its scale line: ${(await texts()).filter(s => s.includes('scaleEffect') || s.includes('CGFloat')).join(' | ')}`);
    // The copy button sits at the code panel's bottom trailing corner: below the snippet's
    // first line and above "just like that" (the reset button is trailing too, at the top).
    // The app scrolls the panel's end into view (ScrollViewReader.scrollTo); where it has not,
    // the probe scrolls to the copy button itself and says so.
    const copyButton = async () => {
      const top = (await drawn()).find(d => d.text.includes('struct MyButtonStyle'));
      return button('Copy', b => centre(b).x > 250 && centre(b).y > 200 && (!top || centre(b).y > top.y));
    };
    let copy = await copyButton();
    const scrolledByApp = !!copy && copy.y + copy.height < 800;
    for (let i = 0; i < 10 && copy && copy.y + copy.height > 800; i++) { await swipeUp(); copy = await copyButton(); }
    if (expect(!!copy, `no copy button; buttons: ${(await buttons()).map(b => `${b.label}@${Math.round(b.x)},${Math.round(b.y)}`).join(' | ')}`)) {
      note(scrolledByApp ? 'the app scrolled the panel into view' : 'the app did not scroll the panel into view (scrollTo after the panel appears); the probe scrolled');
      await tapBox(copy);
      let copied = false;
      for (let i = 0; i < 20 && !copied; i++) { copied = (await texts()).includes('Copied'); if (!copied) await page.waitForTimeout(50); }
      await shot('07-copied');
      expect(copied, 'no "Copied" after the copy button');
    }
  }

  report.full_app_pass = Object.values(report.flows).every(f => f.outcome === 'passed') && problems.length === 0;
} catch (e) {
  problems.push('probe: ' + e.message);
} finally {
  try { await context.tracing.stop({ path: join(out, 'trace.zip') }); report.trace = 'trace.zip'; } catch {}
  await browser.close();
  report.finished = new Date().toISOString();
  writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ full_app_pass: report.full_app_pass, flows: report.flows, problems: report.problems }, null, 2));
  process.exit(report.full_app_pass ? 0 : 1);
}
