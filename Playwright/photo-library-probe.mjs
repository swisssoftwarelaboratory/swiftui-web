// The photo library's own ask in the drawn iPhone (new-website#708), with Examples/PhotoLibrary:
// asking to add photos shows the short alert; once allowed, the full ask says "full access" and
// Keep Add Only refuses it; on a fresh phone the full ask shows the photo strip, Select Photos
// opens the photo sheet and limits the app to what was marked, and the app can open the sheet
// again; Allow Full Access also allows adding, and a reload remembers it without asking.
// Screenshots of each step go to --out.
//   node photo-library-probe.mjs http://127.0.0.1:8708/index.html [--browser webkit] [--out dir]
import { chromium, webkit } from 'playwright';
import { mkdirSync } from 'node:fs';
const args = process.argv.slice(2);
const base = args.find(a => !a.startsWith('--'));
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const out = opt('--out', null);
if (out) mkdirSync(out, { recursive: true });

const engine = { chromium, webkit }[opt('--browser', 'webkit')];
const browser = await engine.launch();
const problems = [];
let page;

const open = async (context) => {
  page = await context.newPage();
  page.on('pageerror', e => problems.push('pageerror: ' + e.message));
  await page.goto(base + '?platform=ios&device=iphone', { waitUntil: 'commit', timeout: 180000 });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  await page.waitForTimeout(800);
};
const fresh = async () => open(await browser.newContext({ deviceScaleFactor: 2, viewport: { width: 520, height: 1000 } }));

const texts = async () => (await page.evaluate(() => window.__swiftuiwebDebug.displayList()))
  .filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]);
const shot = async name => { if (out) await page.screenshot({ path: `${out}/${name}.png` }); };
const press = async label => {
  const button = page.locator(`#app button[aria-label="${label}"]`).first();
  const box = await button.boundingBox().catch(() => null);
  if (!box) { problems.push(`no button ${label}`); return; }
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
};
const expectText = async (wanted, budget = 4000) => {
  const deadline = Date.now() + budget;
  let seen = await texts();
  while (!seen.some(t => t.includes(wanted)) && Date.now() < deadline) { await page.waitForTimeout(50); seen = await texts(); }
  if (!seen.some(t => t.includes(wanted))) problems.push(`expected "${wanted}" in ${JSON.stringify(seen)}`);
};

// Adding first, then the full ask that follows it.
await fresh();
await shot('0-app');
await expectText('Full access: not asked');
await press('Ask to add photos');
await expectText('to add photos');
await page.waitForTimeout(700);
await shot('1-add');
await press('Allow');
await expectText('Adding: authorized');
await press('Ask for full access');
await expectText('full access to');
await page.waitForTimeout(700);
await shot('2-full-after-add');
await press('Keep Add Only');
await expectText('Full access: denied');
await expectText('Adding: authorized');

// A fresh phone: the full ask, Select Photos, and the sheet again.
await fresh();
await press('Ask for full access');
await expectText('to access your');
await expectText('Photos may contain data associated with');
await page.waitForTimeout(1500);
await shot('3-full');
await press('Select Photos');
await page.waitForTimeout(1200);
await shot('4-select-photos');
const photos = page.locator('#app button[aria-label="Photo"]');
if (await photos.count() < 2) problems.push(`the sheet shows ${await photos.count()} photos`);
for (const i of [0, 2]) {
  const box = await photos.nth(i).boundingBox();
  if (box) await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(150);
}
await shot('5-marked');
await press('Add');
await expectText('Full access: limited');
await page.waitForTimeout(700);
await press('Select more photos');
await page.waitForTimeout(1200);
await shot('6-select-more');
// The two photos picked before are marked again (7-one-more); one more makes one newly picked.
const again = page.locator('#app button[aria-label="Photo"]');
const box = await again.nth(4).boundingBox().catch(() => null);
if (box) await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2); else problems.push('no photos when reopened');
await page.waitForTimeout(200);
await shot('7-one-more');
await press('Add');
await expectText('Newly picked: 1');
await expectText('Adding: not asked');

// Another fresh phone: full access allows adding, and a reload remembers it.
await fresh();
await press('Ask for full access');
await expectText('to access your');
await page.waitForTimeout(500);
await press('Allow Full Access');
await expectText('Full access: authorized');
await expectText('Adding: authorized');
await page.reload({ waitUntil: 'commit' });
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
await page.waitForTimeout(800);
await expectText('Full access: authorized');
await press('Ask for full access');
await page.waitForTimeout(800);
if ((await texts()).some(t => t.includes('photo library?'))) problems.push('a reload asked again');

await browser.close();
console.log(JSON.stringify({ problems }, null, 2));
process.exit(problems.length ? 1 : 0);
