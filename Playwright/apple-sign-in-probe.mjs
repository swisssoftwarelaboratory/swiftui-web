// Sign in with Apple in the drawn iPhone (new-website#707), with Examples/AppleSignIn: the
// button's first sign-in shows iOS's sheet with the name and the email choice, Continue runs
// Face ID and hands the app the name and the Hide My Email address; a second sign-in shows the
// shorter sheet and hands over no name or email; the close button cancels; the account's state
// is authorized. Screenshots of each step go to --out.
//   node apple-sign-in-probe.mjs http://127.0.0.1:8707/index.html [--browser webkit] [--out dir]
import { chromium, webkit } from 'playwright';
import { mkdirSync } from 'node:fs';
const args = process.argv.slice(2);
const base = args.find(a => !a.startsWith('--'));
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const out = opt('--out', null);
if (out) mkdirSync(out, { recursive: true });

const engine = { chromium, webkit }[opt('--browser', 'webkit')];
const browser = await engine.launch();
const context = await browser.newContext({ deviceScaleFactor: 2, viewport: { width: 520, height: 1000 } });
const page = await context.newPage();
const problems = [];
page.on('pageerror', e => problems.push('pageerror: ' + e.message));
await page.goto(base + '?platform=ios&device=iphone', { waitUntil: 'commit', timeout: 180000 });
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
await page.waitForTimeout(800);

const texts = async () => (await page.evaluate(() => window.__swiftuiwebDebug.displayList()))
  .filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]);
const shot = async name => { if (out) await page.screenshot({ path: `${out}/${name}.png` }); };
const press = async label => {
  const button = page.locator(`#app button[aria-label="${label}"]`).first();
  const box = await button.boundingBox();
  if (!box) { problems.push(`no button ${label}`); return; }
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
};
const expectText = async (wanted, budget = 4000) => {
  const deadline = Date.now() + budget;
  let seen = await texts();
  while (!seen.some(t => t.includes(wanted)) && Date.now() < deadline) { await page.waitForTimeout(50); seen = await texts(); }
  if (!seen.some(t => t.includes(wanted))) problems.push(`expected "${wanted}" in ${JSON.stringify(seen)}`);
};

await shot('0-app');
// A first sign-in: the full sheet.
await press('Sign in with Apple');
await expectText('Create an account for');
await page.waitForTimeout(900);
await shot('1-sheet');
for (const word of ['Name', 'Share My Email', 'Hide My Email', 'mara.keller@icloud.com', 'Continue']) await expectText(word);
await press('Continue');
await page.waitForTimeout(400);
await shot('2-face-id');
await expectText('signed in', 5000);
await page.waitForTimeout(900);
await shot('3-signed-in');
await expectText('Mara Keller');
await expectText('@privaterelay.appleid');
await expectText('full_name, email');

// A second sign-in: the short sheet, no name or email handed over.
await press('Sign in with a controller');
await expectText('Do you want to sign in to');
await page.waitForTimeout(900);
await shot('4-returning');
const returning = await texts();
if (returning.includes('Share My Email')) problems.push('the returning sheet asks for the email again');
await press('Continue');
await page.waitForTimeout(2200);
await shot('5-returned');
const after = await texts();
if (after.includes('Mara Keller')) problems.push('a second sign-in handed over the name');

// The close button cancels.
await press('Sign in with Apple');
await expectText('Do you want to sign in to');
await page.waitForTimeout(900);
await press("Close");
await expectText('cancelled');

await press('Check the account');
await expectText('authorized');
await page.waitForTimeout(500);
await shot('6-state');

await browser.close();
if (problems.length) { console.log('FAIL\n' + problems.join('\n')); process.exit(1); }
console.log('OK');
