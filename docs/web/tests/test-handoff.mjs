// One voice, the whole family.
//
// The claim on the poster is that her archive moves to another phone. The thing
// that makes that real rather than a file copy is the voice identifier: the
// voice lives at the service, not on the phone, so the second device must be
// able to speak in it immediately — without cloning her again and without
// taking a second voice slot for the same person.
//
// The second context here is a genuinely separate browser profile: different
// localStorage, different IndexedDB. That is the only honest way to test that
// something survived the move rather than simply still being there.

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
const errs = [];

const stub = async page => {
  await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', route => {
    const u = route.request().url();
    if (u.includes('/v1/voices/add'))
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ voice_id: 'family_voice_1' }) });
    if (u.includes('/v1/text-to-speech/'))
      return route.fulfill({ status: 200, contentType: 'audio/mpeg', body: Buffer.alloc(4096, 3) });
    return route.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
  });
  page.on('pageerror', e => errs.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errs.push(m.text() + ' @ ' + (m.location()?.url || '?')); });
};

// ── the first phone ────────────────────────────────────────────────────
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
await a.click('button:has-text("Add their voice") >> nth=0'); await a.waitForTimeout(400);
await a.setInputFiles('.sheet input[type=file]', { name: 's.wav', mimeType: 'audio/wav', buffer: wav(30) });
await a.waitForTimeout(700);
await a.click('.sheet .switch >> nth=0'); await a.click('.sheet .switch >> nth=1');
await a.waitForTimeout(200);
await a.click('.sheet button:has-text("Create voice")'); await a.waitForTimeout(1400);

// notes and a sealed letter, so the export has something to carry
await a.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.people[0];
  m.store.addNote({ personId: p.id, text: 'She made maqluba every Friday.' });
  m.store.addLetter({
    personId: p.id, text: 'Happy birthday, my love.', occasion: 'Her 21st',
    deliverAt: new Date(Date.now() + 90 * 86400000).toISOString(),
  });
});
await a.waitForTimeout(400);

await go.setup(a);
log(await a.locator('text=Give this to the family').isVisible(), 'setup offers the handoff');
await go.back(a);

const exported = await a.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const out = await m.Archive.export(m.store.people[0].id);
  return { json: JSON.stringify(out.file), carried: out.carried, leftBehind: out.leftBehind };
});
const file = JSON.parse(exported.json);
log(file.jaddati === 1, 'the file declares its version');
log(file.person?.name === 'Teta', 'it carries the person', file.person?.name);
log(file.person?.voiceId === 'family_voice_1', 'and the voice identifier — the part that matters', file.person?.voiceId);
log(file.notes?.length === 1, 'the family notes travel', String(file.notes?.length));
log(file.letters?.length === 1, 'sealed letters travel', String(file.letters?.length));
log(exported.carried === 1, 'the original recording is carried', String(exported.carried));
log(!file.person?.id, 'no local id is carried — two phones must not share one');

// ── the second phone: a genuinely separate profile ─────────────────────
const ctxB = await browser.newContext({ viewport: { width: 390, height: 844 }, permissions: ['microphone'] });
const b = await ctxB.newPage();
await stub(b);
await signedIn(b, 'receives@example.com');
await b.goto(URL, { waitUntil: 'networkidle' });
await b.waitForTimeout(500);
await b.click('text=Allow these three things'); await b.waitForTimeout(400);

log(await b.locator('text=No people yet').isVisible(), 'the second phone starts empty');
log(await b.locator('text=Bring someone from another phone').isVisible(), 'and offers to bring someone in');

const brought = await b.evaluate(async json => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const r = await m.Archive.import(json);
  return { name: r.person.name, voiceId: r.person.voiceId, id: r.person.id,
           notes: m.store.memories(r.person.id).length,
           sealed: m.store.sealedLetters(r.person.id).length,
           restored: r.restored };
}, exported.json);

log(brought.name === 'Teta', 'she arrives on the second phone', brought.name);
log(brought.voiceId === 'family_voice_1', 'speaking in the SAME voice, not a new clone', brought.voiceId);
log(brought.id !== file.person?.id, 'with a fresh local id');
log(brought.notes === 1, 'her notes came with her', String(brought.notes));
log(brought.sealed === 1, 'and the sealed letter is still sealed', String(brought.sealed));
log(brought.restored === 1, 'the original recording was restored', String(brought.restored));

await b.waitForTimeout(600);
log(await b.locator('text=Teta').first().isVisible(), 'and she is on the home screen');

// The whole point: the second phone can speak without creating a voice.
let addCalls = 0;
await b.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/v1/voices/add', route => {
  addCalls++;
  return route.fulfill({ status: 200, contentType: 'application/json', body: '{"voice_id":"SHOULD_NOT_HAPPEN"}' });
});
const spoke = await b.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.people[0];
  const r = await m.Voice.synthesize('Good morning.', p.voiceId, m.Config.defaultModelId, m.TUNING.natural);
  return !!r.blob;
});
log(spoke, 'the second phone speaks straight away');
log(addCalls === 0, 'without cloning her a second time', String(addCalls));

// ── a file that is not one of ours ─────────────────────────────────────
const refused = await b.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const out = [];
  for (const bad of ['not json at all', '{"hello":true}', '{"jaddati":99,"person":{"name":"x"}}']) {
    try { await m.Archive.import(bad); out.push('ACCEPTED'); }
    catch (e) { out.push(e.name); }
  }
  return out;
});
log(refused.every(r => r === 'ArchiveError'), 'rubbish files are refused with a real message', refused.join(', '));

const real = errs.filter(e => !/favicon|speechSynthesis|not-allowed/i.test(e));
log(real.length === 0, 'no console errors', real.slice(0, 3).join(' | '));

await browser.close();
console.log('\n' + (problems.length ? `${problems.length} PROBLEM(S)` : 'all handoff checks passed'));
process.exit(problems.length ? 1 : 0);
