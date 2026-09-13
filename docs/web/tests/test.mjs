import pw from 'playwright';
import { go } from './paths.mjs';
const { chromium } = pw;

const URL = 'http://localhost:8899/index.html';
const problems = [];
const log = (ok, what, extra = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}${extra ? '  — ' + extra : ''}`);
  if (!ok) problems.push(what + (extra ? ': ' + extra : ''));
};

const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const ctx = await browser.newContext({
  viewport: { width: 390, height: 844 },
  permissions: ['microphone'],
});
const page = await ctx.newPage();

// This suite runs in rehearsal mode and reaches no service, but opening You
// asks the relay once whether Google sign-in is configured. Unstubbed that is
// a real network call which fails in here and logs. Answering "not
// configured" is both the truth for this suite and what keeps the section
// hidden.
await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/google/status', route =>
  route.fulfill({ status: 200, contentType: 'application/json',
                  body: '{"configured":false,"clientId":""}' }));

const consoleErrors = [];
page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text()); });
page.on('pageerror', e => consoleErrors.push('pageerror: ' + e.message));

await page.goto(URL, { waitUntil: 'networkidle' });
await page.waitForTimeout(600);

// ── the gate ───────────────────────────────────────────────────────────
log(await page.locator('text=Some of this').isVisible(), 'consent gate is the first screen');
log(await page.locator('text=ElevenLabs').isVisible(), 'gate names ElevenLabs');
log(await page.locator('text=Groq').isVisible(), 'gate names Groq');
log(!(await page.locator('.tabrail').isVisible().catch(() => false)), 'no tab rail behind the gate');

// the notice opens from the gate
await page.click('text=Read the full privacy notice');
await page.waitForTimeout(250);
log(await page.locator('.sheet').isVisible(), 'privacy notice opens from the gate');
await page.click('.sheet .appbar button[aria-label]');
await page.waitForTimeout(200);

// decline first, to prove the app still opens
await page.click('text=Not now');
await page.waitForTimeout(400);
log(await page.locator('.tabrail').isVisible(), 'declining still opens the app');
log(await page.locator('text=Jaddati').first().isVisible(), 'home screen renders');

// Declining used to leave the app in demo mode, because there was no key to
// decline the use of. Going through the relay it has one, so a refusal now
// really does switch voice creation off — which is the point of asking.
log(await page.locator('text=Kept on this phone').first().isVisible().catch(() => false),
    'declining switches the voice service off rather than falling back to demo');
log(!(await page.locator('text=DEMO MODE').isVisible().catch(() => false)),
    'and does not mislabel a refusal as demo mode');

// now allow, through the privacy sheet, and carry on as a real visitor would
await go.privacy(page);
await page.click('.sheet button:has-text("Allow the three things above")');
await page.waitForTimeout(400);
log(!(await page.locator('.sheet').isVisible().catch(() => false)), 'allowing from the privacy sheet closes it');

// Rehearsal mode: the whole flow on the browser's own voice, reaching nothing.
// This is what he will run in front of a room, and what the rest of this file
// exercises, so it is checked here rather than taken on trust.
await go.keys(page);
log(await page.locator('.sheet').isVisible(), 'voice service sheet opens');
log(await page.locator('text=Ready as it is').isVisible(), 'it no longer asks for a key up front');
log(!(await page.locator('.sheet input[type=password]').first().isVisible().catch(() => false)),
    'the key fields are folded away, not the first thing you see');
await page.click('.sheet .switch');
await page.click('.sheet button:has-text("Save")');
await page.waitForTimeout(500);
// Settings live on You now, so come back to the first screen of the app: the
// banner has to be where someone who never opened settings will meet it.
await go.people(page);
log(await page.locator('text=DEMO MODE').isVisible(), 'rehearsal mode announces itself on the home screen');
log(await page.locator('text=Switch rehearsal off').isVisible(),
    'and offers the way out, rather than telling you to add a key');

// ── people ─────────────────────────────────────────────────────────────
await page.click('text=Add someone');
await page.waitForTimeout(300);
await page.fill('.sheet input >> nth=0', 'Jaddati');
await page.fill('.sheet input >> nth=1', 'Grandmother');
await page.click('.sheet button:has-text("Add person")');
await page.waitForTimeout(400);
log(await page.locator('.person-card').count() === 1, 'person added and listed');

await page.click('.person-card');
await page.waitForTimeout(400);
log(await page.locator('text=No recreated voice yet').first().isVisible(), 'person screen shows no voice yet');

// ── a voice, in demo mode ──────────────────────────────────────────────
await page.click('button:has-text("Add their voice") >> nth=0');
await page.waitForTimeout(400);
log(await page.locator('.sheet').isVisible(), 'add-voice sheet opens');
log(await page.locator('.sheet button:has-text("Create voice")').isDisabled(), 'create is disabled with nothing chosen');

// a file, then both permissions
await page.setInputFiles('.sheet input[type=file]', {
  name: 'sample.wav', mimeType: 'audio/wav', buffer: wav(30),
});
await page.waitForTimeout(700);
await page.click('.sheet .switch >> nth=0');
await page.click('.sheet .switch >> nth=1');
await page.waitForTimeout(200);
log(!(await page.locator('.sheet button:has-text("Create voice")').isDisabled()), 'create enables with a file and both permissions');

await page.click('.sheet button:has-text("Create voice")');
await page.waitForTimeout(1800);
log(!(await page.locator('.sheet').isVisible().catch(() => false)), 'sheet closes after creating');
log(await page.locator('.primary-action .btn-primary').isVisible(),
    'the primary action unlocks once there is a voice');
log(await page.locator('.cardgrid').isVisible(), 'and the three doors appear with it');

// ── compose and play ───────────────────────────────────────────────────
await page.click('text=Say something');
await page.waitForTimeout(400);
log(await page.locator('textarea').isVisible(), 'compose screen has an editor');
await page.fill('textarea', 'Good morning, my love.');
await page.waitForTimeout(300);
log(!(await page.locator('button:has-text("Create audio")').isDisabled()), 'create audio enables with text');

await page.click('button:has-text("Create audio")');
await page.waitForTimeout(1500);
log(await page.locator('.player-art').isVisible(), 'player screen opens');
log(await page.locator('text=AI-RECREATED VOICE').isVisible(), 'clip is labelled AI-recreated');
log(await page.locator('text=Not kept yet').isVisible(), 'unkept clip says so');

await page.click('button:has-text("Keep this clip")');
await page.waitForTimeout(400);
log(await page.locator('button:has-text("Clip saved")').isVisible(), 'keeping a clip works');

await page.click('.appbar button >> nth=0');   // back
await page.waitForTimeout(400);

// ── books ──────────────────────────────────────────────────────────────
await page.click('.appbar button >> nth=0');   // back to person
await page.waitForTimeout(300);
await go.card(page, 'Books');
log(await page.locator('text=No books yet').isVisible(), 'empty shelf');

await page.setInputFiles('input[type=file]', {
  name: 'A Short Tale.txt', mimeType: 'text/plain',
  buffer: Buffer.from('The cat sat on the mat. '.repeat(90), 'utf8'),
});
await page.waitForTimeout(900);
log(await page.locator('.book-cover').count() >= 1, 'book imports and appears on the shelf');

await page.click('text=Open book');
await page.waitForTimeout(500);
log(await page.locator('text=Page 1 of').isVisible(), 'reader shows the page position');
log(await page.locator('button:has-text("Read this page")').isVisible(), 'reader offers to read the page');
await page.click('button:has-text("Next page")');
await page.waitForTimeout(400);
log(await page.locator('text=Page 2 of').isVisible(), 'page turning works');

// ── saved ──────────────────────────────────────────────────────────────
log(await page.locator('.tabrail').isVisible(), 'tab rail stays visible on a pushed screen');

// The People tab still holds the reader we left in it, which is the point of
// per-tab stacks. Leaving for another tab and coming back must not lose it.
await go.letters(page);
await page.click('.tabrail button >> nth=0');
await page.waitForTimeout(300);
log(await page.locator('text=Page 2 of').isVisible(), 'a tab remembers where you were in it');
await page.click('.tabrail button >> nth=0');
await page.waitForTimeout(300);
log(await page.locator('.person-card').count() === 1, 'tapping the same tab again returns to its root');

// Saved is a door on the person now rather than a tab of its own — a pile of
// clips with no name on it was never an archive, and as a tab it was dead
// until you had already tapped into someone.
await page.click('.person-card'); await page.waitForTimeout(500);
await go.card(page, 'Saved');
log(await page.locator('text=Carefully kept').isVisible(), 'Saved renders');
log(await page.locator('.audio-row').count() >= 2, 'saved list holds the original and the kept clip');
await go.back(page); await go.back(page);
await go.switchLanguage(page);
const dir = await page.evaluate(() => document.documentElement.dir);
log(dir === 'rtl', 'switching language sets RTL', dir);
log(await page.locator('.tabrail').getByText('الأشخاص').isVisible(), 'tab rail is in Arabic');
log(await page.locator('text=جدّتي').first().isVisible(), 'masthead reads جدّتي');

// back to English
await go.switchLanguage(page);
await page.waitForTimeout(500);
log(await page.evaluate(() => document.documentElement.dir) === 'ltr', 'switching back sets LTR');

// ── persistence ────────────────────────────────────────────────────────
await page.reload({ waitUntil: 'networkidle' });
await page.waitForTimeout(800);
log(await page.locator('.person-card').count() === 1, 'the person survives a reload');
log(!(await page.locator('text=Some of this').isVisible().catch(() => false)), 'the gate does not reappear after answering');

// ── layout ─────────────────────────────────────────────────────────────
const overflow = await page.evaluate(() =>
  document.documentElement.scrollWidth - document.documentElement.clientWidth);
log(overflow <= 0, 'no horizontal overflow at 390px', String(overflow));

const tiny = await ctx.newPage();
await tiny.setViewportSize({ width: 320, height: 640 });
await tiny.goto(URL, { waitUntil: 'networkidle' });
await tiny.waitForTimeout(600);
const overflow320 = await tiny.evaluate(() =>
  document.documentElement.scrollWidth - document.documentElement.clientWidth);
log(overflow320 <= 0, 'no horizontal overflow at 320px', String(overflow320));
await tiny.close();

// ── the relay wiring ───────────────────────────────────────────────────
// Everything above ran on the browser's own voice. This is the part that only
// shows up against a real service: the address it calls, the headers it sends,
// and whether the two refusals the relay can give arrive as sentences a person
// can act on. The relay itself is stubbed, so no allowance is spent proving it.

const seen = [];
// Its own context, not its own tab: sharing one would mean sharing the consent
// answer and the device id already written above, and this run needs to start
// where a first-time visitor starts.
const liveCtx = await browser.newContext({ viewport: { width: 390, height: 844 }, permissions: ['microphone'] });
const live = await liveCtx.newPage();
live.on('pageerror', e => consoleErrors.push('pageerror: ' + e.message));

await live.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', async route => {
  const req = route.request();
  seen.push({ url: req.url(), method: req.method(), headers: req.headers() });
  if (req.url().includes('/v1/voices/add'))
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ voice_id: 'stub_voice_1' }) });
  if (req.url().includes('/v1/text-to-speech/'))
    return route.fulfill({ status: 200, contentType: 'audio/mpeg', body: Buffer.alloc(4096, 7) });
  return route.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
});

await live.goto(URL, { waitUntil: 'networkidle' });
await live.waitForTimeout(500);
await live.click('text=Allow these three things');
await live.waitForTimeout(400);
await live.click('text=Add someone');
await live.waitForTimeout(300);
await live.fill('.sheet input >> nth=0', 'Teta');
await live.fill('.sheet input >> nth=1', 'Grandmother');
await live.click('.sheet button:has-text("Add person")');
await live.waitForTimeout(400);
await live.click('.person-card');
await live.waitForTimeout(400);
await live.click('button:has-text("Add their voice") >> nth=0');
await live.waitForTimeout(400);

// The sweep clears voices every ten minutes so everyone in the room gets a
// turn. Someone handing over a recording deserves to know that before they
// do it, not when their voice disappears.
log(await live.locator('text=removed automatically about every ten minutes').isVisible(),
    'the add-voice screen warns that voices are cleared every ten minutes');
log(await live.locator('text=Deleting this person removes it from there as well').isVisible(),
    'and no longer claims deleting a person leaves the voice behind');

await live.setInputFiles('.sheet input[type=file]', { name: 'sample.wav', mimeType: 'audio/wav', buffer: wav(30) });
await live.waitForTimeout(700);
await live.click('.sheet .switch >> nth=0');
await live.click('.sheet .switch >> nth=1');
await live.waitForTimeout(200);
await live.click('.sheet button:has-text("Create voice")');
await live.waitForTimeout(1500);

const add = seen.find(r => r.url.includes('/v1/voices/add'));
log(!!add, 'creating a voice calls the relay, not ElevenLabs directly');
log(!!add && add.headers['xi-api-key'] === 'jd_7cvjRdcDM88CWeY5tjUjuWwqf92u_wTWlCCvlD7ZdqI',
    'it sends the relay token, not a blank key', add && add.headers['xi-api-key']);
log(!!add && /^[A-Za-z0-9-]{8,64}$/.test(add.headers['x-jaddati-device'] || ''),
    'it sends a device id the relay will accept', add && add.headers['x-jaddati-device']);
log(!seen.some(r => /api\.elevenlabs\.io|api\.groq\.com/.test(r.url)),
    'nothing goes straight to ElevenLabs or Groq');

await live.click('text=Say something');
await live.waitForTimeout(400);
await live.fill('textarea', 'Good morning, my love.');
await live.waitForTimeout(300);
await live.click('button:has-text("Create audio")');
await live.waitForTimeout(1500);

const tts = seen.find(r => r.url.includes('/v1/text-to-speech/'));
log(!!tts, 'speaking calls the relay');
log(!!tts && tts.url.includes('stub_voice_1'), 'it speaks with the voice the relay handed back');
log(!!tts && tts.headers['x-jaddati-device'] === add.headers['x-jaddati-device'],
    'the same device id is used throughout, so the meter counts one visitor');
log(await live.locator('.player-art').isVisible(), 'the clip plays back through the relay path');

// The device id has to survive a reload, or every visit spends a fresh
// allowance and the metering means nothing.
const before = add.headers['x-jaddati-device'];
await live.reload({ waitUntil: 'networkidle' });
await live.waitForTimeout(500);
const after = await live.evaluate(() => localStorage.getItem('jaddati.device'));
log(after === before, 'the device id survives a reload', `${before} -> ${after}`);

// Both relay refusals, in the words a person actually reads.
const refusal = async (detail, expected, what) => {
  await live.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/v1/voices/add', route =>
    route.fulfill({ status: 429, contentType: 'application/json', body: JSON.stringify({ detail }) }), { times: 1 });
  const said = await live.evaluate(async () => {
    const mod = await import('./core.js?v=' + document.documentElement.dataset.v);
    try { await mod.Voice.createVoice('x', new Blob([new Uint8Array(2048)], { type: 'audio/wav' })); return 'no error'; }
    catch (e) { return e.message; }
  });
  log(said.includes(expected), what, said.slice(0, 80));
};
await refusal('voice limit reached for this device', 'no room for another voice',
              'a full voice list reads as "no room for another voice", not "busy, try again"');
await refusal('credit allowance used for this month (0 of 500 left)', "month's allowance",
              'an exhausted allowance says so, rather than blaming the network');

await liveCtx.close();

// ── console ────────────────────────────────────────────────────────────
const real = consoleErrors.filter(e => !/favicon|speechSynthesis|not-allowed/i.test(e));
log(real.length === 0, 'no console errors', real.slice(0, 4).join(' | '));

await page.screenshot({ path: 'shot-home.png' });
await browser.close();

console.log('\n' + (problems.length ? `${problems.length} PROBLEM(S)` : 'all checks passed'));
if (problems.length) process.exit(1);

/** A tiny valid WAV so the file picker has something with real duration. */
function wav(seconds) {
  const rate = 8000, n = rate * seconds;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(1, 22); buf.writeUInt32LE(rate, 24); buf.writeUInt32LE(rate * 2, 28);
  buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) buf.writeInt16LE(Math.round(Math.sin(i / 20) * 6000), 44 + i * 2);
  return buf;
}
