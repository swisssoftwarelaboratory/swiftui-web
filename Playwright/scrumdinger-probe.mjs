// Scrumdinger (Apps/upstream/Scrumdinger, unmodified; decision 0021) in headless Chrome, the
// flow a user takes: the add sheet from the bar's "+" (a NavigationStack in a sheet with its
// own Dismiss and Add), a title typed into the form, an attendee added with the icon-only "Add
// Attendee" button, the scrum on the list after Add and still there after a reload (its
// FileService through localStorage), the detail screen opened from the card, a meeting run by
// the real SpeechService: speech authorisation (the host's on-device recogniser, decision 0022,
// the locale's pack installed into the profile), the microphone (Chrome's fake device playing a
// committed recording — "one two three four five", on a loop — as the input the app's
// AVAudioEngine taps), the timer counting, the transcript the app accumulates from its appended
// buffers, the meeting left and its history row opened to the saved transcript.
//   node scrumdinger-probe.mjs http://127.0.0.1:8773/index.html?platform=ios [--out ../.build/apps/scrumdinger] [--profile dir]
// The browser is the installed Google Chrome with its sandbox ON (Playwright's --no-sandbox
// silences the on-device recogniser; the bundled Chromium has none) in a persistent profile
// (default Playwright/.speech-profile, shared with speech-probe.mjs) that keeps the pack.
// Evidence goes to --out whatever happens: report.json (the tested commit, the app's pinned
// revision, every flow's outcome — passed / failed / not-run — the problems, and
// `full_app_pass` true only when every flow passed), the screenshots the flows take, a
// Playwright trace. CI uploads the folder.
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const url = process.argv[2];
const outIndex = process.argv.indexOf('--out');
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = outIndex > 0 ? process.argv[outIndex + 1] : join(root, '.build', 'apps', 'scrumdinger');
mkdirSync(out, { recursive: true });
const profileIndex = process.argv.indexOf('--profile');
const profile = profileIndex > 0 ? process.argv[profileIndex + 1] : join(root, 'Playwright', '.speech-profile');
mkdirSync(profile, { recursive: true });
// The microphone: Chrome's fake audio device plays this file (16 kHz, macOS `say`: "one two three four five"), looping.
const microphone = join(root, 'Examples', 'Launches', 'fixtures', 'speech-one.wav');
if (!existsSync(microphone)) { console.log('no microphone fixture at ' + microphone); process.exit(1); }
const git = (args) => { try { return execSync(`git ${args}`, { cwd: root, encoding: 'utf8' }).trim(); } catch { return 'unknown'; } };
// The tested commit is only what ran when the tree is clean; a dirty tree is said so.
const dirty = git('status --porcelain --untracked-files=normal').split('\n').filter(Boolean);
const report = {
  app: 'Scrumdinger', upstream: 'https://github.com/Sedlacek-Solutions/Scrumdinger',
  tested_commit: git('rev-parse HEAD'), working_tree: dirty.length ? `dirty: ${dirty.length} path(s) differ from the commit` : 'clean', app_pinned_revision: git('ls-files --stage Apps/upstream/Scrumdinger').split(/\s+/)[1] || 'unknown',
  browser: null, url, started: new Date().toISOString(),
  full_app_pass: false,
  flows: {}, problems: [], screenshots: [], trace: null,
  notes: ['The meeting runs against the real SpeechService: the host\'s on-device recogniser (decision 0022) transcribes the buffers the app appends from its AVAudioEngine tap; the microphone is Chrome\'s fake device playing a committed recording.'],
};
let currentFlow = null;
const flow = (name, outcome, detail) => { report.flows[name] = { outcome, ...(detail ? { detail } : {}) }; };
const shot = async (name) => { const file = join(out, name + '.png'); try { await page.screenshot({ path: file }); report.screenshots.push(name + '.png'); } catch (e) { report.problems.push('screenshot ' + name + ': ' + e.message); } };
const context = await chromium.launchPersistentContext(profile, {
  channel: 'chrome', chromiumSandbox: true, headless: true,
  // The audio service's own sandbox cannot open the fixture (the fake device then delivers
  // silence): that one feature is off, the browser sandbox the recogniser needs stays on.
  args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', '--use-file-for-fake-audio-capture=' + microphone, '--disable-features=AudioServiceSandbox', '--autoplay-policy=no-user-gesture-required'],
  viewport: { width: 375, height: 667 }, hasTouch: true, isMobile: true,
});
const browser = context.browser();
report.browser = browser ? browser.version() : 'chrome';
await context.tracing.start({ screenshots: true, snapshots: false });
const page = context.pages()[0] || await context.newPage();
const problems = report.problems;
const logs = [];
page.on('pageerror', e => problems.push('pageerror: ' + e.message + ' ' + (e.stack || '').split('\n').slice(1, 6).join(' <- ')));
// Chrome asks for a favicon the server has not got; any other console error is a problem.
page.on('console', m => { logs.push(m.text()); if (m.type() === 'error' && !/\/favicon\.ico$/.test((m.location() && m.location().url) || '')) problems.push('console: ' + m.text() + ' @ ' + ((m.location() && m.location().url) || '')); });
const texts = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]));
const settle = async (ready, tries = 50) => { let t = await texts(); for (let i = 0; i < tries && !ready(t); i++) { await page.waitForTimeout(100); t = await texts(); } return t; };
const tap = async (label, which = 'first') => {
  const box = await page.locator(`[aria-label="${label}"]`)[which]().boundingBox();
  if (!box) { problems.push(`no element labelled "${label}"`); return; }
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
};
const expect = (condition, message) => { if (!condition) { problems.push(message); if (currentFlow) report.flows[currentFlow] = { outcome: 'failed', detail: message }; } };
// Flows are declared not-run up front, so an early crash still reports every one.
const FLOWS = ['launch', 'add-sheet', 'title-and-attendee', 'scrum-listed', 'persists-after-reload', 'detail-screen', 'meeting-screen', 'meeting-timer', 'meeting-transcription', 'history-transcript'];
for (const f of FLOWS) flow(f, 'not-run');
const begin = (name) => { currentFlow = name; flow(name, 'passed'); };
// Taps a painted text (a row with a tap gesture has no control element).
const tapText = async (text, dx = 20, dy = -8) => {
  const at = await page.evaluate((text) => { const op = window.__swiftuiwebDebug.displayList().find(c => c.startsWith(`drawText("${text}"`)); const m = op && op.match(/at ([\d.]+),([\d.]+)/); return m ? { x: +m[1], y: +m[2] } : null; }, text);
  if (!at) { problems.push(`no painted text "${text}"`); return; }
  await page.mouse.click(at.x + dx, at.y + dy);
};
const loaded = async () => {
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  await page.waitForTimeout(300);
};

const finish = async (code) => {
  report.finished = new Date().toISOString();
  report.speech_log = logs.filter(l => /Recognition|transcription|authoriz|Audio engine|Recording format|Speech/i.test(l)).slice(-40);
  try { await context.tracing.stop({ path: join(out, 'trace.zip') }); report.trace = 'trace.zip'; } catch (e) { problems.push('trace: ' + e.message); }
  report.full_app_pass = FLOWS.every(f => report.flows[f] && report.flows[f].outcome === 'passed') && problems.length === 0;
  writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  await context.close();
  process.exit(code);
};
process.on('uncaughtException', async (e) => { problems.push('uncaught: ' + e.message); if (currentFlow) flow(currentFlow, 'failed', e.message); await finish(1); });
process.on('unhandledRejection', async (e) => { problems.push('unhandled: ' + (e && e.message || e)); if (currentFlow) flow(currentFlow, 'failed', String(e && e.message || e)); await finish(1); });

begin('launch');
await page.goto(url, { waitUntil: 'commit', timeout: 180000 });
await loaded();
expect((await texts()).includes('Daily Scrums'), 'the list screen did not show "Daily Scrums"');
await shot('1-launch');
expect(logs.some(l => l.includes('SpeechRecognizer created')), 'the real SpeechService did not find a recogniser (RuntimeEnvironment should be the physical device on wasm)');

// The add sheet: a NavigationStack inside a sheet with Dismiss and Add in its bar.
begin('add-sheet');
await tap('Add');
let shown = await settle(t => t.includes('Dismiss') && t.includes('Meeting Info'));
expect(shown.includes('Dismiss') && shown.includes('Add') && shown.includes('Title'), 'the add sheet did not show its bar and form: ' + JSON.stringify(shown));

await shot('2-add-sheet');
begin('title-and-attendee');
await tap('Title');
await page.waitForTimeout(200);
await page.keyboard.type('Design review');
shown = await settle(t => t.includes('Design review'));
expect(shown.includes('Design review'), 'the title was not typed: ' + JSON.stringify(shown));

await tap('New Attendee');
await page.waitForTimeout(200);
await page.keyboard.type('Ada');
await settle(t => t.includes('Ada'));
await tap('Add Attendee');
shown = await settle(t => t.includes('Ada') && t.includes('New Attendee'));
expect(shown.includes('Ada') && shown.includes('New Attendee'), 'the attendee row did not appear with the field cleared: ' + JSON.stringify(shown));

await shot('3-filled');
begin('scrum-listed');
await tap('Add', 'last');
shown = await settle(t => !t.includes('Dismiss') && t.includes('Design review'));
expect(shown.includes('Design review') && shown.includes('1') && shown.includes('5'), 'the card did not show the scrum with 1 attendee and 5 minutes: ' + JSON.stringify(shown));

await shot('4-listed');
// On file: a reload shows it again.
begin('persists-after-reload');
await page.reload({ waitUntil: 'commit' });
await loaded();
shown = await settle(t => t.includes('Design review'));
expect(shown.includes('Design review'), 'the scrum did not survive a reload: ' + JSON.stringify(shown));
// An app with a bundle identifier keeps its keys under `swiftuiweb.app[<id>].` (new-website#709).
const stored = await page.evaluate(() => Object.keys(localStorage).map(k => k.replace(/^swiftuiweb\.app\[[^\]]*\]\./, 'swiftuiweb.')));
expect(stored.includes('swiftuiweb.files/Documents/dailyScrumsKey'), 'the scrums file is not in localStorage: ' + JSON.stringify(stored));

// The detail screen from the card, then the meeting.
begin('detail-screen');
await tapText('Design review', 40);
shown = await settle(t => t.includes('Start Meeting'));
expect(shown.includes('Start Meeting') && shown.includes('Ada'), 'the detail screen did not open: ' + JSON.stringify(shown));

await shot('5-detail');
begin('meeting-screen');
await tapText('Start Meeting');
shown = await settle(t => t.includes('Seconds Elapsed'));
expect(shown.includes('Seconds Elapsed') && shown.includes('Seconds Remaining'), 'the meeting screen did not open: ' + JSON.stringify(shown));
await shot('6-meeting');
// Speech authorisation is the first thing the app's `.task` asks for; the first run on a
// profile installs the locale's pack here (minutes), so the timer gets a long wait.
begin('meeting-timer');
const elapsedAt = (t) => { const i = t.indexOf('Seconds Elapsed'); return i >= 0 ? t[i + 1] : null; };
shown = await settle(t => t.includes('Not authorized to recognize speech') || t.includes('Speech recognizer unavailable') || (elapsedAt(t) !== null && elapsedAt(t) !== '0'), 15 * 60 * 10);
expect(!shown.includes('Not authorized to recognize speech') && !shown.includes('Speech recognizer unavailable'), 'the app was refused speech: ' + JSON.stringify(shown.filter(t => /authorized|unavailable|permitted/i.test(t))));
expect(elapsedAt(shown) !== null && elapsedAt(shown) !== '0', 'the meeting timer did not start: ' + JSON.stringify(shown));
expect(logs.some(l => l.includes('Audio engine started successfully')), 'the SpeechService did not start its audio engine');
// The transcript: the app accumulates each partial result (MeetingScreen.startSpeechRecording); the
// recording loops, so the words recur. The service logs each result it gets.
begin('meeting-transcription');
const transcription = () => logs.filter(l => l.includes('New transcription: ')).map(l => l.slice(l.indexOf('New transcription: ') + 'New transcription: '.length).trim());
// The recording says one, two, three: as words, as digits, or (when the app joins results
// that are single digits) as one run of digits such as "12345".
const saysOne = (t) => { const w = t.toLowerCase().replace(/[^a-z0-9 ]/g, '').split(/\s+/); return w.some(x => /^\d*123\d*$/.test(x)) || ((w.includes('1') || w.includes('one')) && (w.includes('2') || w.includes('two')) && (w.includes('3') || w.includes('three'))); };
for (let i = 0; i < 300 && !transcription().some(saysOne); i++) await page.waitForTimeout(100);
const heard = transcription();
expect(heard.some(saysOne), 'no transcription of the recording reached the app within 30 s; results: ' + JSON.stringify(heard.slice(-3)));
expect(logs.some(l => l.includes('Processing audio buffer')), 'the app\'s tap delivered no buffers');
await shot('7-meeting-running');
// Leaving the meeting saves its history with the transcript (onDisappear), then the detail's
// History section lists it and the history screen shows the words.
begin('history-transcript');
const backBox = await page.locator('[aria-label="Back"]').first().boundingBox().catch(() => null);
if (backBox) await page.mouse.click(backBox.x + backBox.width / 2, backBox.y + backBox.height / 2); else await tapText('Design review', 0, 0);
shown = await settle(t => t.includes('Start Meeting') && !t.includes('No meetings yet'), 100);
expect(shown.includes('Start Meeting') && !shown.includes('No meetings yet'), 'the detail screen did not list the meeting: ' + JSON.stringify(shown));
expect(logs.some(l => l.includes('Stopping speech recording')), 'the SpeechService did not stop on leaving');
await shot('8-detail-with-history');
const dateRow = shown.find(t => /\b20\d\d\b/.test(t) && !t.includes('Start Meeting'));
expect(dateRow, 'no dated history row on the detail screen: ' + JSON.stringify(shown));
if (dateRow) await tapText(dateRow, 10, -6);
shown = await settle(t => t.includes('Transcript'), 100);
const transcriptIndex = shown.indexOf('Transcript');
const saved = transcriptIndex >= 0 ? shown.slice(transcriptIndex + 1).join(' ') : '';
expect(transcriptIndex >= 0 && saysOne(saved), 'the history screen did not show the saved transcript: ' + JSON.stringify(shown));
await shot('9-history-transcript');
currentFlow = null;

console.log(problems.length ? problems.join('\n') : 'scrumdinger: sheet, attendee, on file after reload, detail, the meeting with its timer and on-device transcription, the history with the transcript — full_app_pass=true');
console.log('evidence: ' + join(out, 'report.json'));
await finish(problems.length ? 1 : 0);
