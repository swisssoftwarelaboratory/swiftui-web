// Examples/Launches in headless Chromium (decision 0021): an app whose model imports Foundation
// and Combine. Three loads in one context: the launch count (UserDefaults) and the launches on
// file (FileManager + JSONEncoder) persist through localStorage, the Combine chain sets the
// status, the dispatched delay settles it, libm and Bundle answer.
// The network check (pf-urlsession): the page's URLSession over fetch against local fixtures —
// the same-origin JSON (200, decoded, its mime type), a missing path (404 as a response with a
// body), a request to a second local server that sends no CORS headers (URLError -1004, no
// status), a cancelled task (-999), and against the slow fixture server (fixture-server.mjs,
// `?slow=`): a timeout while the body is being read after the headers arrived (-1001), an
// in-flight cancellation after the headers (-999) with exactly one completion. The second
// server's address comes in `?cross=`.
//   node launches-probe.mjs "http://127.0.0.1:8765/index.html?cross=http://127.0.0.1:8776&slow=http://127.0.0.1:8777"
import { chromium } from 'playwright';
const url = process.argv[2];
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 400, height: 300 } });
const problems = [];
page.on('pageerror', e => problems.push('pageerror: ' + e.message));
// The network check provokes exactly two console errors on purpose: the 404 for the page's own
// `/fixtures/missing.json`, and the CORS refusal of `<cross>/fixtures/country.json`. Each is
// matched by its request URL (the console message's location, or the URL it names); any other
// console error, and any other 404 or CORS message, is a problem.
const pageOrigin = new URL(url).origin;
const crossOrigin = (() => { try { return new URL(new URL(url).searchParams.get('cross') || '').origin; } catch { return null; } })();
const deliberate = { missing: pageOrigin + '/fixtures/missing.json', cors: crossOrigin ? crossOrigin + '/fixtures/country.json' : null };
const expectedConsoleError = (m) => {
  const text = m.text();
  const at = (m.location() && m.location().url) || '';
  if (at === deliberate.missing && /status of 404/.test(text)) return true;
  if (deliberate.cors && at === deliberate.cors && /net::ERR_FAILED/.test(text)) return true;
  if (deliberate.cors && text.includes(`Access to fetch at '${deliberate.cors}' from origin '${pageOrigin}' has been blocked by CORS policy`)) return true;
  return false;
};
page.on('console', m => { if (m.type() === 'error' && !expectedConsoleError(m)) problems.push('console: ' + m.text() + ' @ ' + ((m.location() && m.location().url) || '')); });
const networkLine = (t) => { const start = t.findIndex(x => x.startsWith('network: ')); if (start < 0) return ''; const parts = []; for (let i = start; i < t.length && t[i] !== 'Record again'; i++) parts.push(t[i]); return parts.join(' '); };
const texts = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]));
for (let load = 1; load <= 3; load++) {
  await page.goto(url, { waitUntil: 'commit', timeout: 180000 });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  await page.waitForTimeout(400);
  const shown = await texts();
  const summary = shown.find(t => t.startsWith('launch ')) || '';
  const status = shown.find(t => t.startsWith('event: ')) || '';
  const expected = `launch ${load}.0, ${load} on file, log2(8) = 3.0, /`;
  if (summary !== expected) problems.push(`load ${load}: summary "${summary}", expected "${expected}"`);
  if (status !== `event: settled ${load}`) problems.push(`load ${load}: status "${status}", expected "event: settled ${load}"`);
  // UIKit, Foundation and SwiftUI imported together: one Selector ("copy:"), UIScreen's bounds, the bundle's languages (none recorded: the development one).
  const mixed = shown.find(t => t.startsWith('mixed: ')) || '';
  if (!/^mixed: copy: \d+ en$/.test(mixed)) problems.push(`load ${load}: mixed imports "${mixed}", expected "mixed: copy: <width> en"`);
  // SwiftData (pf-swiftdata): one Visit with its Note per launch, the table read back from localStorage, a second container of the name seeing the save.
  const data = shown.find(t => t.startsWith('data: ')) || '';
  const expectedData = `data: ${load} visits, ${load} notes linked, last ${load}, reopened ${load} launch ${load}`;
  if (data !== expectedData) problems.push(`load ${load}: data "${data}", expected "${expectedData}"`);
  // The network line wraps: join the lines from "network:" up to the button.
  const last = url.includes('slow=') ? 'completions' : 'cancel';
  const settledNetwork = async () => { for (let i = 0; i < 150; i++) { const t = await texts(); const line = networkLine(t); if (line.includes(last)) return line; await page.waitForTimeout(100); } return networkLine(await texts()); };
  const network = await settledNetwork();
  const expectedNetwork = 'network: ok 200 Chad/TCD application/json | missing 404 body' + (url.includes('cross=') ? ' | cors -1004' : '') + ' | cancel -999'
    + (url.includes('slow=') ? ' | timeout -1001 | inflight -999 | completions 1' : '');
  if (network !== expectedNetwork) problems.push(`load ${load}: network "${network}", expected "${expectedNetwork}"`);
}
// The keyboard notifications (uk-app-delegate-adaptor), read as the Countries handler reads
// them. Desktop Chromium has no on-screen keyboard, so this is the host→scene→notification
// path on SYNTHETIC viewport readings (what the phone's browser would report), not the
// phone's keyboard: a plain resize of the window stays 0; a reading with a focused input and
// the visual viewport 336 px short shows 336; the input blurred clears it.
const keyboardLine = async () => (await texts()).find(t => t.startsWith('keyboard: ')) || '';
await page.setViewportSize({ width: 375, height: 500 });
await page.waitForTimeout(300);
if (await keyboardLine() !== 'keyboard: 0') problems.push(`keyboard after a plain resize: "${await keyboardLine()}", expected "keyboard: 0"`);
const sceneFrame = () => page.evaluate(() => window.__swiftuiwebDebug.keyboardFrame());
await page.evaluate(() => window.__swiftuiwebDebug.syntheticKeyboardReading(500, 500 - 336, 0, 1, true));
await page.waitForTimeout(300);
if (await keyboardLine() !== 'keyboard: 336') problems.push(`keyboard on a synthetic reading: "${await keyboardLine()}", expected "keyboard: 336"`);
if (await sceneFrame() !== '164,336') problems.push(`scene keyboard frame: ${await sceneFrame()}, expected "164,336"`);
await page.evaluate(() => window.__swiftuiwebDebug.syntheticKeyboardReading(500, 250, 0, 2, true));   // pinch-zoomed: not a keyboard
await page.waitForTimeout(300);
if (await keyboardLine() !== 'keyboard: 0' || await sceneFrame() !== null) problems.push(`keyboard under zoom: "${await keyboardLine()}" frame ${await sceneFrame()}, expected none`);
await page.evaluate(() => window.__swiftuiwebDebug.syntheticKeyboardReading(500, 500 - 336, 0, 1, false));   // no focused input
await page.waitForTimeout(300);
if (await keyboardLine() !== 'keyboard: 0') problems.push(`keyboard without a focused input: "${await keyboardLine()}", expected "keyboard: 0"`);
// An app with a bundle identifier keeps its keys under `swiftuiweb.app[<id>].` (new-website#709).
const stored = await page.evaluate(() => Object.keys(localStorage).filter(k => k.startsWith('swiftuiweb.')).map(k => k.replace(/^swiftuiweb\.app\[[^\]]*\]\./, 'swiftuiweb.')).sort());
if (!stored.includes('swiftuiweb.defaults.standard') || !stored.includes('swiftuiweb.files/Documents/launches.json') || !stored.includes('swiftuiweb.swiftdata.launches')) problems.push('localStorage keys: ' + stored.join(', '));
console.log(problems.length ? problems.join('\n') : 'launches OK: three loads counted, on file and settled; keyboard notifications on synthetic viewport readings (no phone keyboard here)');
await browser.close();
process.exit(problems.length ? 1 : 0);
