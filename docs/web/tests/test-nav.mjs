// The rebuild, checked the way a first-time user meets it.
//
// The complaint that started this was "I'm confused about what's happening",
// so these press what a stranger would press, in the order a stranger would
// press it, and assert that at no point are they shown a wall of choices.

import pw from 'playwright';
import { signedIn } from './paths.mjs';

const URL = 'http://localhost:8899/index.html';
const problems = [];
const log = (ok, what, extra = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}${extra ? '  — ' + extra : ''}`);
  if (!ok) problems.push(what);
};

const wav = n => {
  const d = 8000 * n, b = Buffer.alloc(44 + d);
  b.write('RIFF', 0); b.writeUInt32LE(36 + d, 4); b.write('WAVE', 8); b.write('fmt ', 12);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(8000, 24); b.writeUInt32LE(8000, 28); b.writeUInt16LE(1, 32);
  b.writeUInt16LE(8, 34); b.write('data', 36); b.writeUInt32LE(d, 40);
  return b;
};

const browser = await pw.chromium.launch({
  executablePath: '/opt/pw-browsers/chromium',
  args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream'],
});
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, permissions: ['microphone'] });
const page = await ctx.newPage();
const errs = [];
page.on('pageerror', e => errs.push('pageerror: ' + e.message));
page.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });

await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', route => {
  const u = route.request().url();
  if (u.includes('/v1/voices/add'))
    return route.fulfill({ status: 200, contentType: 'application/json', body: '{"voice_id":"v1"}' });
  if (u.includes('/v1/text-to-speech/'))
    return route.fulfill({ status: 200, contentType: 'audio/mpeg', body: Buffer.alloc(4096, 4) });
  return route.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
});

const shot = n => page.screenshot({ path: `/home/claude/web/nav-${n}.png` });

// Billed to an account now: without this the app refuses before it reaches
// the relay, and every assertion below would be testing the refusal.
await signedIn(page);
await page.goto(URL, { waitUntil: 'networkidle' });
await page.waitForTimeout(500);
await page.click('text=Allow these three things');
await page.waitForTimeout(500);

// ── 1. the rail, from a cold start ─────────────────────────────────────
const railLabels = await page.locator('.tabrail button').allTextContents();
log(railLabels.length === 3, 'three tabs', railLabels.join(' | '));
log(/People/.test(railLabels[0]) && /Letters/.test(railLabels[1]) && /You/.test(railLabels[2]),
  'People, Letters, You', railLabels.join(' | '));

// The whole point of the change: no tab is dead before you have a person.
for (const [i, name] of [[1, 'Letters'], [2, 'You']]) {
  await page.click(`.tabrail button >> nth=${i}`);
  await page.waitForTimeout(400);
  const body = await page.locator('.screen').innerText();
  log(!/Choose someone first/i.test(body), `${name} works with no person yet`,
    body.split('\n').slice(0, 2).join(' / '));
}
await shot('you-cold');
await page.click('.tabrail button >> nth=1'); await page.waitForTimeout(300);
await shot('letters-cold');

await page.click('.tabrail button >> nth=0'); await page.waitForTimeout(400);

// ── 2. a person with no voice sees ONE thing to do ─────────────────────
await page.click('text=Add someone'); await page.waitForTimeout(300);
await page.fill('.sheet input >> nth=0', 'Teta');
await page.fill('.sheet input >> nth=1', 'Grandmother');
await page.click('.sheet button:has-text("Add person")'); await page.waitForTimeout(500);
await page.click('.person-card'); await page.waitForTimeout(500);
await shot('person-novoice');

log(await page.locator('.person-hero').isVisible(), 'the person screen leads with their face');
const primary = await page.locator('.primary-action .btn-primary').allTextContents();
log(primary.length === 1, 'exactly ONE primary button', primary.join(' | '));
log(/Add their voice/.test(primary[0] || ''), 'and with no voice it says Add their voice', primary[0]);
log(await page.locator('.cardgrid').count() === 0, 'no cards yet — nothing to put in them');
const asides = await page.locator('.primary-action__aside').allTextContents();
log(asides.length === 1 && /still here/i.test(asides[0]), 'one aside: record them while you can', asides.join('|'));

// The old screen listed seven of these. None should survive on this screen.
const rows = await page.locator('.scroll .feature-row').count();
log(rows === 0, 'no feature rows on the person screen', String(rows));

// ── 3. setup is one tap away, and holds the rare things ────────────────
await page.click('.setup-btn');
await page.waitForTimeout(500);
await shot('setup');
const setupBody = await page.locator('.screen').innerText();
// Section labels are uppercased in CSS, so compare without case.
const setupText = setupBody.toLowerCase();
for (const t of ['Add their voice', 'Recorded before it is needed', 'Original recordings',
                 'Give this to the family', 'Remove this person']) {
  log(setupText.includes(t.toLowerCase()), `setup holds "${t}"`);
}
await page.click('.appbar button >> nth=0'); await page.waitForTimeout(500);

// ── 4. with a voice, the button changes and the doors appear ───────────
await page.click('.setup-btn'); await page.waitForTimeout(400);
await page.click('.feature-row:has-text("Add their voice")'); await page.waitForTimeout(500);
await page.setInputFiles('.sheet input[type=file]', { name: 's.wav', mimeType: 'audio/wav', buffer: wav(30) });
await page.waitForTimeout(700);
await page.click('.sheet .switch >> nth=0'); await page.click('.sheet .switch >> nth=1');
await page.waitForTimeout(200);
await page.click('.sheet button:has-text("Create voice")'); await page.waitForTimeout(1600);
await page.click('.appbar button >> nth=0').catch(() => {});
await page.waitForTimeout(600);
await shot('person-voice');

const primary2 = await page.locator('.primary-action .btn-primary').allTextContents();
log(primary2.length === 1, 'still exactly ONE primary button', primary2.join(' | '));
log(/Say something/.test(primary2[0] || ''), 'and now it says Say something', primary2[0]);
const cards = await page.locator('.bigcard__title').allTextContents();
log(cards.length === 3, 'three cards', cards.join(' | '));
log(/Saved/.test(cards[0]) && /Books/.test(cards[1]) && /Letters/.test(cards[2]),
  'Saved, Books, Letters', cards.join(' | '));

// ── 5. the cards go where they say they go ─────────────────────────────
for (const [i, expect] of [[0, /Everything saved|Saved/i], [1, /Book/i],
                           [2, /Words that arrive later/i]]) {
  await page.locator('.bigcard').nth(i).click();
  await page.waitForTimeout(600);
  const t = await page.locator('.screen').innerText();
  log(expect.test(t), `card ${i + 1} opens the right screen`, t.split('\n')[0]);
  await page.click('.appbar button >> nth=0'); await page.waitForTimeout(500);
}

// ── 6. the main action reaches the compose screen ──────────────────────
await page.click('.primary-action .btn-primary'); await page.waitForTimeout(700);
await shot('compose');
log(await page.locator('textarea').count() > 0, 'Say something opens a box to type in');

const real = errs.filter(e => !/favicon|speechSynthesis|not-allowed/i.test(e));
log(real.length === 0, 'no console errors', real.slice(0, 3).join(' | '));

await browser.close();
console.log('\n' + (problems.length ? `${problems.length} PROBLEM(S)` : 'all navigation checks passed'));
process.exit(problems.length ? 1 : 0);
