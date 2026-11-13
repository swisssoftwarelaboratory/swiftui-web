// SimpleScores (Apps/upstream/simple-swiftui, unmodified; decision 0021) in headless Chromium on
// a phone-sized page: the title and the Add Player button, two players added (each a "New
// Player" row at 0 in its own colour), the + and − buttons changing a score, a player renamed
// in the row's text field, the names and scores back after a reload (the view model's JSON
// file, saved 5 seconds after a change, through the host's store), Reset Scores to 0, and Remove
// All through its alert. All data is what the probe types.
//   node simplescores-probe.mjs http://127.0.0.1:8784/index.html?platform=ios [--out ../.build/apps/simplescores]
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const url = process.argv[2];
const outIndex = process.argv.indexOf('--out');
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = outIndex > 0 ? process.argv[outIndex + 1] : join(root, '.build', 'apps', 'simplescores');
mkdirSync(out, { recursive: true });
const git = (args) => { try { return execSync(`git ${args}`, { cwd: root, encoding: 'utf8' }).trim(); } catch { return 'unknown'; } };
const dirty = git('status --porcelain --untracked-files=normal').split('\n').filter(Boolean);
const report = {
  app: 'SimpleScores', upstream: 'https://github.com/twostraws/simple-swiftui',
  tested_commit: git('rev-parse HEAD'), working_tree: dirty.length ? `dirty: ${dirty.length} path(s) differ from the commit` : 'clean',
  app_pinned_revision: git('ls-files --stage Apps/upstream/simple-swiftui').split(/\s+/)[1] || 'unknown',
  sdk: 'swift-6.4.2-RELEASE_wasm', browser: null, url, started: new Date().toISOString(),
  full_app_pass: false, flows: {}, problems: [], screenshots: [], trace: null, steps: [],
};
const NAME = 'Ada';
const FLOWS = ['launch', 'add-players', 'score-buttons', 'rename', 'persists-after-reload', 'reset', 'remove-all'];
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
// A row is the score's text with its player's name on the same line; − sits at the row's left
// edge (a 44-point frame inside 10 points of inset and 10 of padding) and + at its right.
const rows = async () => {
  const d = await drawn();
  const scores = d.filter(s => /^-?\d+$/.test(s.text));
  return scores.map(s => ({ score: +s.text, x: s.x, y: s.y, name: d.find(n => n !== s && Math.abs(n.y - s.y) < 12 && n.x < s.x && !/^-?\d+$/.test(n.text))?.text })).filter(r => r.name !== undefined).sort((a, b) => a.y - b.y);
};
const minusOf = (r) => tapAt(10 + 10 + 22, r.y - 6);
const plusOf = (r) => tapAt(390 - 10 - 10 - 22, r.y - 6);

try {
  begin('launch');
  await page.goto(url, { waitUntil: 'load', timeout: 180000 });
  await loaded();
  let t = await settle(t => t.includes('SimpleScores') && t.includes('Add Player'));
  await record('launch');
  await shot('01-launch');
  if (expect(t.includes('SimpleScores') && t.includes('Add Player'), 'the list did not show its title and Add Player: ' + JSON.stringify(t))) note('title SimpleScores, Add Player, no players');

  begin('add-players');
  for (let i = 0; i < 2; i++) {
    if (!(await tapControl(byLabel('Add Player')))) await tapText('Add Player');
    t = await settle(t => count(t, 'New Player') >= i + 1, 20);
  }
  await record('two players');
  await shot('02-two-players');
  let r = await rows();
  if (expect(r.length === 2 && r.every(x => x.name === 'New Player' && x.score === 0), 'Add Player twice did not make two "New Player" rows at 0: ' + JSON.stringify(r) + ' ' + JSON.stringify(t))) note('two "New Player" rows at 0');

  begin('score-buttons');
  for (let i = 0; i < 3; i++) await plusOf((await rows())[0]);
  await minusOf((await rows())[0]);
  await page.waitForTimeout(800);
  r = await rows();
  await record('scored');
  await shot('03-scored');
  if (expect(r[0]?.score === 2 && r[1]?.score === 0, 'three + and one − on the first row did not make it 2: ' + JSON.stringify(r))) note('first row 0 → 3 → 2, second row still 0');

  begin('rename');
  const first = (await drawn()).find(d => d.text === 'New Player');
  if (expect(first, 'no "New Player" name to rename')) {
    await tapAt(first.x + 20, first.y - 8);
    await page.waitForTimeout(300);
    await record('name pressed');
    // The row is one accessibility element; the field being edited gets an input of its own.
    const field = (await controls()).find(c => (c.role === 'input' || c.role === 'textbox' || c.role === 'textarea') && Math.abs(c.y + c.height / 2 - (first.y - 8)) < 30);
    expect(field, 'pressing the name gave no text input: ' + JSON.stringify(await controls()));
    if (field && !(await page.evaluate(() => ['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName)))) await tapAt(field.x + field.width / 2, field.y + field.height / 2);
    await page.keyboard.press('End');
    for (let i = 0; i < 'New Player'.length; i++) await page.keyboard.press('Backspace');
    await page.keyboard.type(NAME);
    await page.keyboard.press('Enter');
    t = await settle(t => t.includes(NAME), 20);
    r = await rows();
    await record('renamed');
    await shot('04-renamed');
    if (expect(t.includes(NAME) && r.some(x => x.name === NAME && x.score === 2), `the first row was not renamed "${NAME}": ` + JSON.stringify(r) + ' ' + JSON.stringify(t))) note(`"New Player" → "${NAME}", still 2`);
  }

  begin('persists-after-reload');
  // The view model saves 5 seconds after the last change.
  await page.waitForTimeout(6500);
  await page.reload({ waitUntil: 'load' });
  await loaded();
  t = await settle(t => t.includes(NAME), 40);
  r = await rows();
  await record('reloaded');
  await shot('05-reloaded');
  if (expect(r.length === 2 && r.some(x => x.name === NAME && x.score === 2) && r.some(x => x.name === 'New Player' && x.score === 0), 'after a reload the players did not come back: ' + JSON.stringify(r) + ' ' + JSON.stringify(t))) note(`${NAME} 2 and New Player 0 back from the saved file`);

  begin('reset');
  if (!(await tapControl(byLabel('Reset Scores to 0')))) await tapText('Reset Scores to 0');
  await page.waitForTimeout(500);
  r = await rows();
  await record('reset');
  await shot('06-reset');
  if (expect(r.length === 2 && r.every(x => x.score === 0) && r.some(x => x.name === NAME), 'Reset Scores to 0 did not zero the scores and keep the names: ' + JSON.stringify(r))) note('both scores 0, names kept');

  begin('remove-all');
  if (!(await tapControl(byLabel('Remove All')))) await tapText('Remove All');
  t = await settle(t => t.includes('Delete all players?'), 20);
  await record('alert');
  await shot('07-alert');
  if (expect(t.includes('Delete all players?') && t.includes('Delete') && t.includes('Cancel'), 'Remove All did not ask "Delete all players?": ' + JSON.stringify(t))) {
    if (!(await tapControl(c => c.label === 'Delete' && c.role === 'button'))) await tapText('Delete');
    t = await settle(t => !t.includes('Delete all players?') && !t.includes(NAME), 20);
    r = await rows();
    await record('removed');
    await shot('08-removed');
    if (expect(r.length === 0 && !t.includes(NAME) && t.includes('Add Player'), 'Delete did not remove every player: ' + JSON.stringify(r) + ' ' + JSON.stringify(t))) note('the alert asked, Delete removed both players');
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
