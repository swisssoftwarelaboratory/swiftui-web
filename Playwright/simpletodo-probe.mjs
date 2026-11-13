// SimpleToDo (Apps/upstream/simple-swiftui, unmodified; decision 0021) in headless Chromium on a
// phone-sized page: the title, Edit disabled with no items, two items added with the toolbar's +
// (each a "New Item" row), the first item's detail (its title field renamed, the segmented
// Priority picker set to High, Back to the list with the new title), the second item marked
// completed with its Toggle (the row's accessibility value then reads "completed"), the items
// back after a reload (the view model's JSON file, saved 5 seconds after a change), and Edit's
// selection mode deleting a selected item with the bottom bar's Delete selected. All data is what
// the probe types.
//   node simpletodo-probe.mjs http://127.0.0.1:8785/index.html?platform=ios [--out ../.build/apps/simpletodo]
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const url = process.argv[2];
const outIndex = process.argv.indexOf('--out');
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = outIndex > 0 ? process.argv[outIndex + 1] : join(root, '.build', 'apps', 'simpletodo');
mkdirSync(out, { recursive: true });
const git = (args) => { try { return execSync(`git ${args}`, { cwd: root, encoding: 'utf8' }).trim(); } catch { return 'unknown'; } };
const dirty = git('status --porcelain --untracked-files=normal').split('\n').filter(Boolean);
const report = {
  app: 'SimpleToDo', upstream: 'https://github.com/twostraws/simple-swiftui',
  tested_commit: git('rev-parse HEAD'), working_tree: dirty.length ? `dirty: ${dirty.length} path(s) differ from the commit` : 'clean',
  app_pinned_revision: git('ls-files --stage Apps/upstream/simple-swiftui').split(/\s+/)[1] || 'unknown',
  sdk: 'swift-6.4.2-RELEASE_wasm', browser: null, url, started: new Date().toISOString(),
  full_app_pass: false, flows: {}, problems: [], screenshots: [], trace: null, steps: [],
};
const NAME = 'Buy milk';
const FLOWS = ['launch', 'add-items', 'detail-edit', 'complete', 'persists-after-reload', 'select-delete'];
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
// Chrome asks for a favicon the server has not got; any other console error is a problem.
page.on('console', m => { if (m.type() === 'error' && !/\/favicon\.ico$/.test((m.location() && m.location().url) || '')) problems.push('console: ' + m.text().slice(0, 300)); });
const shot = async (name) => { const file = join(out, name + '.png'); try { await page.screenshot({ path: file }); report.screenshots.push(name + '.png'); } catch (e) { problems.push('screenshot ' + name + ': ' + e.message); } };
const list = () => page.evaluate(() => window.__swiftuiwebDebug.displayList());
const drawn = async () => (await list()).filter(c => c.startsWith('drawText')).map(c => {
  const m = c.match(/^drawText\("([^"]*)".*? at ([-\d.]+),([-\d.]+)/);
  return m ? { text: m[1], x: +m[2], y: +m[3] } : { text: c.match(/"([^"]*)"/)?.[1] ?? c, x: 0, y: 0 };
}).filter(d => d.y > 0 && d.y < 844);
const texts = async () => (await drawn()).map(d => d.text);
const settle = async (ready, tries = 60) => { let t = await texts(); for (let i = 0; i < tries && !ready(t); i++) { await page.waitForTimeout(250); t = await texts(); } return t; };
const count = (t, s) => t.filter(x => x === s).length;
// The overlay's controls (their labels and test ids).
const controls = () => page.evaluate(() => [...document.querySelectorAll('[aria-label], [data-testid]')].map(e => {
  const r = e.getBoundingClientRect();
  return { label: e.getAttribute('aria-label') || '', id: e.getAttribute('data-testid') || '', role: e.getAttribute('role') || e.tagName.toLowerCase(), x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) };
}).filter(b => b.width > 0 && b.height > 0 && b.label !== 'SwiftUI content'));
const record = async (step) => {
  report.steps.push({ step, texts: (await drawn()).map(t => `${t.text}@${Math.round(t.x)},${Math.round(t.y)}`), controls: (await controls()).map(c => `${c.role}:${c.label}${c.id ? '#' + c.id : ''}@${c.x},${c.y},${c.width}x${c.height}`) });
};
const tapAt = async (x, y) => { await page.touchscreen.tap(x, y); await page.waitForTimeout(250); };
const tapControl = async (match) => {
  const c = (await controls()).find(match);
  if (!c) return false;
  await tapAt(c.x + c.width / 2, c.y + c.height / 2);
  return true;
};
const tapText = async (text, dy = -6, dx = 8) => {
  const t = (await drawn()).find(d => d.text === text);
  if (!t) return false;
  await tapAt(t.x + dx, t.y + dy);
  return true;
};
const byLabel = (label) => (c) => c.label === label;
const loaded = async () => {
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  await page.waitForTimeout(500);
};
const tapLabel = async (label) => (await tapControl(byLabel(label))) || (await tapText(label));
const back = async () => (await tapLabel('Back')) || (await tapControl(c => /back/i.test(c.label))) || (await tapText('SimpleToDo'));
// The list's rows: the items' titles drawn below the navigation bar.
const titlesOf = (t) => t.filter(x => x === 'New Item' || x === NAME);
const rowControls = async () => (await controls()).filter(c => c.label === 'New Item' || c.label === NAME || c.label.startsWith('New Item,') || c.label.startsWith(NAME + ','));
const textInput = async () => (await controls()).find(c => c.role === 'input' || c.role === 'textbox' || c.role === 'textarea');
const focusedValue = () => page.evaluate(() => document.activeElement && 'value' in document.activeElement ? document.activeElement.value : null);

try {
  begin('launch');
  await page.goto(url, { waitUntil: 'load', timeout: 180000 });
  await loaded();
  let t = await settle(t => t.includes('SimpleToDo'));
  await record('launch');
  await shot('01-launch');
  const edit = (await controls()).find(c => c.label === 'Edit');
  const add = (await controls()).find(c => c.label === 'Add Item');
  if (expect(t.includes('SimpleToDo') && edit && add, 'the list did not show its title with Edit and Add Item: ' + JSON.stringify(t) + ' ' + JSON.stringify(await controls()))) {
    const disabled = await page.evaluate(() => { const e = [...document.querySelectorAll('[aria-label="Edit"]')][0]; return e ? (e.getAttribute('aria-disabled') === 'true' || e.disabled === true) : null; });
    if (expect(disabled === true, 'Edit was not disabled with no items: ' + disabled)) note('title SimpleToDo, Edit disabled, Add Item, no items');
  }

  begin('add-items');
  for (let i = 0; i < 2; i++) {
    await tapLabel('Add Item');
    t = await settle(t => count(t, 'New Item') >= i + 1, 20);
  }
  await page.waitForTimeout(500);
  t = await texts();
  await record('two items');
  await shot('02-two-items');
  if (expect(count(t, 'New Item') === 2, 'Add Item twice did not make two "New Item" rows: ' + JSON.stringify(t))) note('two "New Item" rows');

  begin('detail-edit');
  const firstRow = (await drawn()).filter(d => d.text === 'New Item').sort((a, b) => a.y - b.y)[0];
  if (expect(firstRow, 'no "New Item" row to open')) {
    await tapAt(firstRow.x + 20, firstRow.y - 6);
    t = await settle(t => t.includes('Mark completed') && t.includes('High'), 40);
    await record('detail');
    await shot('03-detail');
    if (expect(t.includes('Mark completed') && t.includes('Low') && t.includes('Medium') && t.includes('High'), 'the row did not open its detail (title field, Priority picker, Mark completed): ' + JSON.stringify(t))) {
      const field = await textInput();
      const titleText = (await drawn()).find(d => d.text === 'New Item' && d.y > 100);
      if (field) await tapAt(field.x + field.width / 2, field.y + field.height / 2);
      else if (titleText) await tapAt(titleText.x + 20, titleText.y - 6);
      await page.waitForTimeout(300);
      expect(await page.evaluate(() => ['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName)), 'pressing the title gave no text input: ' + JSON.stringify(await controls()));
      await page.keyboard.press('End');
      for (let i = 0; i < 'New Item'.length; i++) await page.keyboard.press('Backspace');
      await page.keyboard.type(NAME);
      await page.keyboard.press('Enter');
      t = await settle(t => count(t, NAME) >= 1, 20);
      await tapLabel('High');
      await page.waitForTimeout(500);
      await record('edited');
      await shot('04-edited');
      // The segmented picker is one radiogroup element whose value is the selected segment.
      const high = await page.evaluate(() => [...document.querySelectorAll('[role="radiogroup"]')].map(e => e.getAttribute('aria-valuetext')).find(v => v !== null) ?? null);
      expect(t.includes(NAME), `the detail's title did not become "${NAME}": ` + JSON.stringify(t));
      expect(high === 'High', 'the segmented picker did not select High: ' + high);
      await back();
      t = await settle(t => !t.includes('Mark completed') && t.includes(NAME), 40);
      const rowsNow = await rowControls();
      await record('back with the new title');
      await shot('05-list-renamed');
      if (expect(!t.includes('Mark completed') && t.includes(NAME) && count(t, 'New Item') === 1, `Back did not show the list with "${NAME}" and one "New Item": ` + JSON.stringify(t))) {
        const row = rowsNow.find(c => c.label.startsWith(NAME));
        if (expect(row && /high priority/.test(row.label + (await page.evaluate((l) => [...document.querySelectorAll('[aria-label]')].find(e => e.getAttribute('aria-label').startsWith(l))?.getAttribute('aria-valuetext') || '', NAME))), `the "${NAME}" row does not read high priority: ` + JSON.stringify(rowsNow))) note(`renamed "${NAME}", High, the row reads high priority`);
      }
    }
  }

  begin('complete');
  const second = (await drawn()).find(d => d.text === 'New Item');
  if (expect(second, 'no second "New Item" row')) {
    await tapAt(second.x + 20, second.y - 6);
    t = await settle(t => t.includes('Mark completed'), 40);
    const sw = (await controls()).find(c => c.label === 'Mark completed');
    if (expect(sw, 'no Mark completed switch: ' + JSON.stringify(await controls()))) {
      await tapAt(sw.x + sw.width - 30, sw.y + sw.height / 2);
      await page.waitForTimeout(500);
      const on = await page.evaluate(() => [...document.querySelectorAll('[aria-label="Mark completed"]')].map(e => e.getAttribute('aria-checked')).find(v => v !== null));
      await record('completed');
      await shot('06-completed');
      expect(on === 'true', 'the Mark completed switch did not turn on: ' + on);
      await back();
      t = await settle(t => !t.includes('Mark completed'), 40);
      const rowsNow = await rowControls();
      await record('back after completing');
      const row = rowsNow.find(c => c.label.startsWith('New Item'));
      const value = await page.evaluate(() => [...document.querySelectorAll('[aria-label]')].filter(e => e.getAttribute('aria-label').startsWith('New Item')).map(e => e.getAttribute('aria-label') + '|' + (e.getAttribute('aria-valuetext') || '') + '|' + (e.getAttribute('aria-description') || '')).join(';'));
      if (expect(row && /completed/.test(row.label + value), 'the "New Item" row does not read completed: ' + JSON.stringify(rowsNow) + ' ' + value)) note('Mark completed on, the row reads completed');
    }
  }

  begin('persists-after-reload');
  // The view model saves 5 seconds after the last change.
  await page.waitForTimeout(6500);
  await page.reload({ waitUntil: 'load' });
  await loaded();
  t = await settle(t => t.includes(NAME), 40);
  await record('reloaded');
  await shot('07-reloaded');
  if (expect(t.includes(NAME) && count(t, 'New Item') === 1, 'after a reload the items did not come back: ' + JSON.stringify(t))) note(`"${NAME}" and "New Item" back from the saved file`);

  begin('select-delete');
  await tapLabel('Edit');
  t = await settle(t => t.includes('Done'), 20);
  await record('editing');
  await shot('08-editing');
  if (expect(t.includes('Done'), 'Edit did not switch the list to editing (Done): ' + JSON.stringify(t))) {
    const target = (await drawn()).find(d => d.text === NAME);
    if (expect(target, `no "${NAME}" row to select`)) {
      await tapAt(target.x + 20, target.y - 6);
      await page.waitForTimeout(400);
      await record('selected');
      await shot('09-selected');
      const del = (await controls()).find(c => c.label === 'Delete selected');
      if (expect(del, 'no Delete selected button in the bottom bar: ' + JSON.stringify(await controls()))) {
        await tapAt(del.x + del.width / 2, del.y + del.height / 2);
        t = await settle(t => !t.includes(NAME), 20);
        await page.waitForTimeout(600);
        t = await texts();
        await record('deleted');
        await shot('10-deleted');
        if (expect(!t.includes(NAME) && count(t, 'New Item') === 1 && t.includes('Edit') && !t.includes('Done'), `Delete selected did not remove "${NAME}" and leave editing: ` + JSON.stringify(t))) note(`Edit, "${NAME}" selected, Delete selected removed it, editing ended`);
      }
    }
  }
} catch (e) {
  problems.push('probe: ' + e.message);
  if (current) report.flows[current] = { outcome: 'failed', detail: e.message };
} finally {
  try { await record('end'); } catch {}
  try { await context.tracing.stop({ path: join(out, 'trace.zip') }); report.trace = 'trace.zip'; } catch {}
  await browser.close();
  report.full_app_pass = FLOWS.every(f => report.flows[f].outcome === 'passed') && problems.length === 0;
  report.finished = new Date().toISOString();
  writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
}
process.exit(report.full_app_pass ? 0 : 1);
