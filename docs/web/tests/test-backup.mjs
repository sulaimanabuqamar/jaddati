// Does a clip someone generated and KEPT actually reach the backup?
//
// test-clips.mjs already asserts this, but it seeds the store directly, and
// that is exactly the shape of test that has missed real bugs in this codebase
// before. This one presses the buttons: add a person, add a voice, type the
// words, Create audio, Keep this clip — then asks the archive what it carries.
//
// It exists because the backup was reported as still broken after the fix, and
// the only way to answer that honestly was to drive it the way a person does.

import pw from 'playwright';
const URL_ = 'http://localhost:8899/index.html';
const b = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const ctx = await b.newContext({ viewport: { width: 390, height: 844 } });
const p = await ctx.newPage();
const uploads = [];
await p.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', r => {
  const u = r.request().url();
  if (u.includes('/google/status')) return r.fulfill({ status: 200, contentType: 'application/json', body: '{"configured":false,"clientId":""}' });
  if (u.includes('/v1/voices/add')) return r.fulfill({ status: 200, contentType: 'application/json', body: '{"voice_id":"family_voice_1"}' });
  if (u.includes('/v1/text-to-speech/')) return r.fulfill({ status: 200, contentType: 'audio/mpeg', body: Buffer.alloc(4096, 7) });
  return r.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
});
// With a personal key the app talks to ElevenLabs directly, not the relay.
await p.route('**/api.elevenlabs.io/**', r => {
  const u = r.request().url();
  if (u.includes('/v1/voices/add')) return r.fulfill({ status: 200, contentType: 'application/json', body: '{"voice_id":"family_voice_1"}' });
  if (u.includes('/v1/text-to-speech/')) return r.fulfill({ status: 200, contentType: 'audio/mpeg', body: Buffer.alloc(4096, 7) });
  return r.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
});
await p.route('**/googleapis.com/**', r => {
  uploads.push({ url: r.request().url(), body: (r.request().postData() || '').slice(0, 4000) });
  return r.fulfill({ status: 200, contentType: 'application/json', body: '{"id":"f1","files":[]}' });
});
p.on('pageerror', e => console.log('PAGEERROR', e.message));
await p.goto(URL_, { waitUntil: 'networkidle' });
await p.waitForTimeout(600);
if (await p.locator('.btn-primary').count()) { await p.click('.btn-primary >> nth=0'); await p.waitForTimeout(600); }

// a real generation against a stubbed service, so a real blob lands
await p.evaluate(() => localStorage.setItem('jaddati.key.elevenlabs', 'sk_probe_only'));
await p.reload({ waitUntil: 'networkidle' }); await p.waitForTimeout(700);
// Adding a personal key moves voice off the relay, and the stored consent
// records which hosts it was given for — so the gate correctly asks again.
if (await p.locator('.btn-primary').count()) { await p.click('.btn-primary >> nth=0'); await p.waitForTimeout(700); }

await p.click('text=Add someone'); await p.waitForTimeout(300);
await p.fill('.sheet input >> nth=0', 'Noura');
await p.fill('.sheet input >> nth=1', 'Grandmother');
await p.click('.sheet button:has-text("Add person")'); await p.waitForTimeout(500);
await p.click('.person-card'); await p.waitForTimeout(500);

// a voice
await p.click('button:has-text("Add their voice") >> nth=0'); await p.waitForTimeout(400);
await p.setInputFiles('.sheet input[type=file]', { name: 's.wav', mimeType: 'audio/wav', buffer: Buffer.alloc(9000, 1) });
await p.waitForTimeout(700);
const sw = await p.locator('.sheet .switch').count();
for (let i = 0; i < sw; i++) await p.click('.sheet .switch >> nth=' + i);
await p.waitForTimeout(200);
await p.click('.sheet button:has-text("Create voice")'); await p.waitForTimeout(1800);

// generate and KEEP a clip
await p.click('text=Say something'); await p.waitForTimeout(500);
await p.fill('textarea', 'Good morning, my love.');
await p.waitForTimeout(300);
await p.click('button:has-text("Create audio")'); await p.waitForTimeout(1600);
const problems = [];
const log = (ok, what, extra = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}${extra ? '  — ' + extra : ''}`);
  if (!ok) problems.push(what);
};

log(await p.locator('text=AI-RECREATED VOICE').count() > 0, 'the clip is labelled AI-recreated');
const keep = await p.locator('button:has-text("Keep this clip")').count();
log(keep === 1, 'and offers to be kept');
if (keep) { await p.click('button:has-text("Keep this clip")'); await p.waitForTimeout(700); }

const state = await p.evaluate(async () => {
  // The app loads core.js with a cache-busting stamp; importing it unstamped
  // gives a SECOND module instance with its own store. Use the app's own.
  const v = document.documentElement.getAttribute('data-v');
  const m = await import('/core.js?v=' + v);
  const person = m.store.people[0];
  const assets = m.store.assets.map(a => ({ source: a.source, isSaved: a.isSaved, bookId: a.bookId, demo: a.demo, exists: m.store.fileExists(a) }));
  const kept = m.store.keptClips(person.id).length;
  const out = await m.Archive.export(person.id, { includingKeptClips: true });
  return { assets, kept, carried: out.carried, carriedOriginals: out.carriedOriginals,
           kinds: out.file.recordings.map(r => r.source) };
});
log(state.kept === 1, 'the kept clip is counted as kept', String(state.kept));
log(state.carried === 2, 'and the backup carries BOTH the recording and the clip',
    state.kinds.join(', '));
log(state.carriedOriginals === 1, 'with the originals still counted apart',
    String(state.carriedOriginals));
log(state.kinds.includes('generated'), 'the clip travels labelled as a clip, not as a recording');

await b.close();
console.log(problems.length
  ? `\n${problems.length} failed:\n  ` + problems.join('\n  ')
  : '\nall backup checks passed');
process.exit(problems.length ? 1 : 0);
