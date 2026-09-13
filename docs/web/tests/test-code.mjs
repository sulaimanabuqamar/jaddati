// Handing someone over by code instead of by file.
//
// The second context is a genuinely separate browser profile — different
// localStorage, different IndexedDB — because that is the only honest way to
// show something travelled rather than simply still being there.

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

// Stands in for the relay's KV. The point is that phone B gets back exactly
// the bytes phone A sent, and nothing else.
const held = new Map();
let lastPut = null;

const stub = async page => {
  await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', async route => {
    const req = route.request(), u = req.url();
    if (u.endsWith('/archive')) {
      lastPut = { body: req.postData(), headers: req.headers() };
      const code = 'K7M2Q4';
      held.set(code, req.postData());
      return route.fulfill({ status: 200, contentType: 'application/json',
                             body: JSON.stringify({ code, hours: 24 }) });
    }
    if (u.endsWith('/archive/fetch')) {
      const asked = JSON.parse(req.postData() || '{}').code;
      const stored = held.get(asked);
      return stored
        ? route.fulfill({ status: 200, contentType: 'application/json', body: stored })
        : route.fulfill({ status: 404, contentType: 'application/json',
                          body: '{"detail":"no archive for that code"}' });
    }
    if (u.includes('/v1/voices/add'))
      return route.fulfill({ status: 200, contentType: 'application/json', body: '{"voice_id":"family_voice_1"}' });
    if (u.includes('/v1/text-to-speech/'))
      return route.fulfill({ status: 200, contentType: 'audio/mpeg', body: Buffer.alloc(4096, 3) });
    return route.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
  });
  page.on('pageerror', e => problems.push('pageerror: ' + e.message));
};

const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });

// ── phone A ────────────────────────────────────────────────────────────
const ctxA = await browser.newContext({ viewport: { width: 390, height: 844 }, permissions: ['microphone'] });
const a = await ctxA.newPage();
await stub(a);
// Billed to an account now, so the browser that makes the voice has to be
// signed in — otherwise this suite is only testing the refusal.
await signedIn(a, 'gives@example.com');
await a.goto(URL, { waitUntil: 'networkidle' });
await a.waitForTimeout(500);
await a.click('text=Allow these three things'); await a.waitForTimeout(400);
await a.click('text=Add someone'); await a.waitForTimeout(300);
await a.fill('.sheet input >> nth=0', 'Teta');
await a.fill('.sheet input >> nth=1', 'Grandmother');
await a.click('.sheet button:has-text("Add person")'); await a.waitForTimeout(400);
await a.click('.person-card'); await a.waitForTimeout(400);
await a.click('.setup-btn'); await a.waitForTimeout(400);
await a.click('.feature-row:has-text("Add their voice")'); await a.waitForTimeout(400);
await a.setInputFiles('.sheet input[type=file]', { name: 's.wav', mimeType: 'audio/wav', buffer: wav(30) });
await a.waitForTimeout(700);
await a.click('.sheet .switch >> nth=0'); await a.click('.sheet .switch >> nth=1');
await a.waitForTimeout(200);
await a.click('.sheet button:has-text("Create voice")'); await a.waitForTimeout(1500);

await a.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.people[0];
  m.store.addNote({ personId: p.id, text: 'She made maqluba every Friday.' });
  m.store.addLetter({ personId: p.id, text: 'Happy birthday.', occasion: 'Her 21st',
                      deliverAt: new Date(Date.now() + 9e9).toISOString() });
});
await a.waitForTimeout(400);

// ── the code ───────────────────────────────────────────────────────────
await a.click('.setup-btn').catch(() => {});
await a.waitForTimeout(500);
log(await a.locator('button:has-text("Give this to the family")').isVisible(), 'setup offers the handoff');
await a.click('button:has-text("Give this to the family")');
await a.waitForTimeout(1400);

const code = (await a.locator('.code').textContent().catch(() => '')) || '';
log(/^[A-Z0-9]{6}$/.test(code), 'a six-character code is shown', code);
log(await a.locator('text=works for a day').isVisible().catch(() => false), 'and says how long it lasts');
log(await a.locator('button:has-text("Save it as a file instead")').isVisible(),
  'the file is still offered, not buried');
log(!!lastPut && lastPut.headers['x-jaddati-device'], 'the upload identifies the device');
log(!!lastPut && JSON.parse(lastPut.body).person?.voiceId === 'family_voice_1',
  'and carries the voice id — the part that matters');
await a.screenshot({ path: '/home/claude/web/cd-code.png' });

// ── phone B: a separate profile ────────────────────────────────────────
const ctxB = await browser.newContext({ viewport: { width: 390, height: 844 }, permissions: ['microphone'] });
const b = await ctxB.newPage();
await stub(b);
await signedIn(b, 'receives@example.com');
await b.goto(URL, { waitUntil: 'networkidle' });
await b.waitForTimeout(500);
await b.click('text=Allow these three things'); await b.waitForTimeout(400);
log(await b.locator('text=No people yet').isVisible(), 'the second phone starts empty');

await b.click('button:has-text("Bring someone from another phone")');
await b.waitForTimeout(500);
log(await b.locator('.sheet input[type=text]').isVisible(), 'it asks for a code, not a file');
log(await b.locator('.sheet input[type=file]').count() === 0, 'no file picker in the way');
log(await b.locator('button:has-text("Bring them in from a file instead")').isVisible(),
  'the file is still reachable from here');
await b.screenshot({ path: '/home/claude/web/cd-enter.png' });

// a wrong code says so, and does not hint at which kind of wrong
await b.fill('.sheet input[type=text]', 'ZZZZZZ');
await b.click('.sheet button:has-text("Bring them in")');
await b.waitForTimeout(900);
const wrong = await b.locator('.sheet').innerText();
log(/no archive for that code|codes last a day/i.test(wrong), 'a wrong code is refused clearly',
  wrong.split('\n').find(l => /code/i.test(l)) || '');
log(await b.locator('.sheet').isVisible(), 'and the sheet stays open to try again');

// typed the way someone would actually type it
await b.fill('.sheet input[type=text]', code.toLowerCase());
await b.click('.sheet button:has-text("Bring them in")');
await b.waitForTimeout(1600);

const got = await b.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.people[0];
  return p ? { name: p.name, voiceId: p.voiceId,
               notes: m.store.memories(p.id).length,
               sealed: m.store.sealedLetters(p.id).length,
               originals: m.store.assetsFor(p.id, 'original').length } : null;
});
log(!!got && got.name === 'Teta', 'she arrives on the second phone', got && got.name);
log(!!got && got.voiceId === 'family_voice_1', 'in the SAME voice, not a new clone', got && got.voiceId);
log(!!got && got.notes === 1, 'her notes came with her');
log(!!got && got.sealed === 1, 'and the sealed letter is still sealed');
log(!!got && got.originals === 1, 'the original recording travelled too');
log(await b.locator('.person-card').count() === 1, 'and she is on the home screen');

await browser.close();
console.log('\n' + (problems.length ? `${problems.length} PROBLEM(S)` : 'all code-handoff checks passed'));
process.exit(problems.length ? 1 : 0);
