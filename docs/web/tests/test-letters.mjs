// Words that arrive later.
//
// The promise is that words are sealed now and heard on a chosen day. Two
// things make that true rather than decorative: a sealed letter must not be
// readable early, and no audio may be generated until it is opened — spending
// the allowance in advance on something nobody may ever hear, in a voice that
// might still be improved before the day.

import pw from 'playwright';
import { go, signedIn } from './paths.mjs';

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

const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, permissions: ['microphone'] });
const page = await ctx.newPage();
const errs = [];
page.on('pageerror', e => errs.push('pageerror: ' + e.message));
page.on('console', m => { if (m.type() === 'error') errs.push(m.text() + ' @ ' + (m.location()?.url || '?')); });

let ttsCalls = 0;
await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', route => {
  const u = route.request().url();
  if (u.includes('/v1/voices/add'))
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ voice_id: 'stub_v' }) });
  if (u.includes('/v1/text-to-speech/')) {
    ttsCalls++;
    return route.fulfill({ status: 200, contentType: 'audio/mpeg', body: Buffer.alloc(4096, 5) });
  }
  return route.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
});

// Billed to an account now: without this the app refuses before it reaches
// the relay, and every assertion below would be testing the refusal.
await signedIn(page);
await page.goto(URL, { waitUntil: 'networkidle' });
await page.waitForTimeout(500);
await page.click('text=Allow these three things'); await page.waitForTimeout(400);
await page.click('text=Add someone'); await page.waitForTimeout(300);
await page.fill('.sheet input >> nth=0', 'Teta');
await page.fill('.sheet input >> nth=1', 'Grandmother');
await page.click('.sheet button:has-text("Add person")'); await page.waitForTimeout(400);
await page.click('.person-card'); await page.waitForTimeout(400);
await page.click('button:has-text("Add their voice") >> nth=0'); await page.waitForTimeout(400);
await page.setInputFiles('.sheet input[type=file]', { name: 's.wav', mimeType: 'audio/wav', buffer: wav(30) });
await page.waitForTimeout(700);
await page.click('.sheet .switch >> nth=0'); await page.click('.sheet .switch >> nth=1');
await page.waitForTimeout(200);
await page.click('.sheet button:has-text("Create voice")'); await page.waitForTimeout(1400);
const ttsAfterVoice = ttsCalls;

log(await page.locator('.bigcard:has-text("Letters")').isVisible(), 'the person screen offers a door to letters');
await go.card(page, 'Letters');
log(await page.locator('text=Sealed now.').isVisible(), 'the letters screen opens');
log(await page.locator('text=Nothing sealed yet').isVisible(), 'and starts empty');

// ── seal one for a day that has not come ───────────────────────────────
await page.fill('.sheet input, input[type=text] >> nth=0', 'Her 21st birthday');
const future = new Date(Date.now() + 90 * 86400000).toISOString().slice(0, 10);
await page.fill('input[type=date]', future);
await page.fill('textarea', 'You are twenty-one today, and I am so proud of you.');
await page.waitForTimeout(300);
await page.click('button:has-text("Seal it")');
await page.waitForTimeout(700);

log(await page.locator('text=Her 21st birthday').isVisible(), 'the sealed letter is listed');
log(ttsCalls === ttsAfterVoice, 'sealing generates NO audio', `${ttsCalls - ttsAfterVoice} call(s)`);

const body = await page.locator('.screen').innerText();
log(!body.includes('twenty-one today'), 'and the words are NOT shown while it is sealed');
log(!(await page.locator('button:has-text("Open it")').isVisible().catch(() => false)),
    'a letter whose day has not come cannot be opened');

// ── one whose day has come ─────────────────────────────────────────────
await page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.people[0];
  m.store.addLetter({
    personId: p.id, text: 'Happy birthday, my love.', occasion: 'Today',
    deliverAt: new Date(Date.now() - 3600000).toISOString(),
  });
});
await page.waitForTimeout(500);
log(await page.locator('text=Waiting for you').first().isVisible(), 'a letter whose day has passed is ready');
log(await page.locator('button:has-text("Open it")').isVisible(), 'and offers to be opened');

await page.click('button:has-text("Open it")');
await page.waitForTimeout(1600);
log(ttsCalls === ttsAfterVoice + 1, 'opening generates the audio, once', String(ttsCalls - ttsAfterVoice));
log(await page.locator('.player-art').isVisible(), 'and plays it');

const spoken = await page.evaluate(async () => (await import('./core.js?v=' + document.documentElement.dataset.v)).store.assets.slice(-1)[0]?.text);
log(spoken === 'Happy birthday, my love.', 'the clip carries the sealed words', spoken);

const opened = await page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  return m.store.letters.filter(l => l.openedAt).length;
});
log(opened === 1, 'the letter is marked opened so it cannot be charged for twice', String(opened));

// ── it survives a reload, which is the whole point of sealing ──────────
await page.reload({ waitUntil: 'networkidle' });
await page.waitForTimeout(700);
const kept = await page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  return { total: m.store.letters.length, sealed: m.store.sealedLetters(m.store.people[0].id).length };
});
log(kept.total === 2 && kept.sealed === 1, 'letters survive a reload', JSON.stringify(kept));

const real = errs.filter(e => !/favicon|speechSynthesis|not-allowed/i.test(e));
log(real.length === 0, 'no console errors', real.slice(0, 3).join(' | '));

await browser.close();
console.log('\n' + (problems.length ? `${problems.length} PROBLEM(S)` : 'all letter checks passed'));
process.exit(problems.length ? 1 : 0);
