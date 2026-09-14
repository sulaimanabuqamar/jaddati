// Restoring onto someone who is already here.
//
// The restore used to bring back only people who were MISSING. Once she was on
// the device her backup was skipped whole — so a clip made on a phone and
// backed up could never reach a laptop that already had her, however many
// times the button was pressed. The only way through was to delete her first,
// which is not a thing to ask of somebody restoring a dead relative.
//
// The risk in fixing it is the opposite failure: a merge that cannot tell what
// it has already seen turns the same button into a duplicating machine. So
// every check here presses it TWICE.

import pw from 'playwright';

const URL_ = 'http://localhost:8899/index.html';
const problems = [];
const log = (ok, what, extra = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}${extra ? '  — ' + extra : ''}`);
  if (!ok) problems.push(what);
};

const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
const page = await ctx.newPage();
const errs = [];
page.on('pageerror', e => errs.push('pageerror: ' + e.message));
page.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });

await page.goto(URL_, { waitUntil: 'networkidle' });
await page.waitForTimeout(500);
if (await page.locator('.btn-primary').count()) {
  await page.click('.btn-primary >> nth=0');
  await page.waitForTimeout(400);
}

// An archive written the way the PHONE writes one: flat fields, second
// precision on the dates (Swift's .iso8601 strategy drops the milliseconds,
// and identity is read off those dates).
const b64 = Buffer.alloc(3000, 3).toString('base64');
const archive = (recordings, notes = [], letters = []) => JSON.stringify({
  jaddati: 1,
  exportedAt: '2026-09-13T20:00:00Z',
  person: { name: 'Noura', fullName: 'Noura Al Qubaisi', relationship: 'Grandmother',
            voiceId: 'voice-from-the-phone', voiceCreatedAt: '2026-09-10T09:00:00Z',
            consentConfirmedAt: '2026-09-10T09:00:00Z', cloudKey: 'key-noura' },
  notes, letters, recordings,
});

const ORIGINAL = { text: 'The kitchen, 2019', durationSeconds: 94, fileExtension: 'm4a',
                   source: 'original', createdAt: '2026-09-10T09:05:00Z', data: b64 };
const CLIP = { text: 'Take your time.', durationSeconds: 6, fileExtension: 'm4a',
               source: 'generated', intent: 'comfort', contentKind: 'wordsSuppliedByYou',
               createdAt: '2026-09-13T19:00:00Z', data: b64 };
const NOTE = { text: 'The bread had to rest before you cut it.', addedBy: 'Sulaiman',
               createdAt: '2026-09-11T10:00:00Z' };
const LETTER = { text: 'For the day you finish.', occasion: 'Graduation',
                 deliverAt: '2027-06-01T09:00:00Z', createdAt: '2026-09-11T10:00:00Z' };

const run = (file, into) => page.evaluate(async ([text, key]) => {
  const m = await import('/core.js?v=' + document.documentElement.dataset.v);
  const mine = key ? m.store.people.find(p => (p.cloudKey || p.id) === key) || null : null;
  const out = await m.Archive.import(text, { into: mine });
  const person = out.person;
  const assets = m.store.archive(person.id);
  return {
    restored: out.restored, addedNotes: out.addedNotes, addedLetters: out.addedLetters,
    merged: out.merged,
    people: m.store.people.length,
    clips: assets.filter(a => a.source === 'generated').length,
    originals: assets.filter(a => a.source === 'original').length,
    words: assets.filter(a => a.source === 'generated').map(a => a.text),
    notes: m.store.memories(person.id).length,
    letters: m.store.lettersFor(person.id).length,
    name: person.name, voiceId: person.voiceId, shared: person.voiceIsShared === true,
    madeOn: (assets.find(a => a.source === 'generated') || {}).createdAt,
  };
}, [file, into]);

// ── the phone's first backup: a recording, no clip yet ──────────────────
let r = await run(archive([ORIGINAL], [NOTE]), null);
log(r.people === 1 && !r.merged, 'the first restore stands her up', `${r.people} person`);
log(r.originals === 1 && r.clips === 0, 'with the recording and no clip yet');

// ── the same file again: nothing new ────────────────────────────────────
r = await run(archive([ORIGINAL], [NOTE]), 'key-noura');
log(r.merged, 'the second restore goes INTO her rather than beside her');
log(r.people === 1, 'so there is still one of her', `${r.people}`);
log(r.restored === 0 && r.addedNotes === 0, 'and nothing was added twice',
    `${r.restored} clips, ${r.addedNotes} notes`);
log(r.originals === 1 && r.notes === 1, 'the counts did not double',
    `${r.originals} recording, ${r.notes} note`);

// ── the phone backs up again, now with a clip ───────────────────────────
// This is the case he hit: she is already on the laptop, and the thing he
// wants is in the file.
r = await run(archive([ORIGINAL, CLIP], [NOTE], [LETTER]), 'key-noura');
log(r.restored === 1, 'a clip made after the first restore arrives', `${r.restored}`);
log(r.addedLetters === 1, 'and so does a letter written after it', `${r.addedLetters}`);
log(r.clips === 1 && r.originals === 1, 'without a second copy of the recording',
    `${r.clips} clip, ${r.originals} recording`);
log(r.words[0] === 'Take your time.', 'the clip keeps its words', r.words[0]);
log(String(r.madeOn).startsWith('2026-09-13T19:00'),
    'and the day it was made, not the day it arrived', r.madeOn);

// ── and again, to prove the clip is now recognised as hers ──────────────
r = await run(archive([ORIGINAL, CLIP], [NOTE], [LETTER]), 'key-noura');
log(r.restored === 0 && r.addedLetters === 0, 'pressing it once more adds nothing',
    `${r.restored} clips, ${r.addedLetters} letters`);
log(r.clips === 1 && r.notes === 1 && r.letters === 1,
    'so the button is not a duplicating machine', `${r.clips}/${r.notes}/${r.letters}`);

// ── what a merge must NOT do to her ─────────────────────────────────────
const renamed = await page.evaluate(async () => {
  const m = await import('/core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.people.find(x => x.cloudKey === 'key-noura');
  p.name = 'Teta'; p.voiceId = 'voice-made-on-this-laptop'; p.voiceIsShared = false;
  m.store.save();
  return p.name;
});
log(renamed === 'Teta', 'renamed locally, with her own voice');
r = await run(archive([ORIGINAL, CLIP]), 'key-noura');
log(r.name === 'Teta', 'a merge does not rename her back', r.name);
log(r.voiceId === 'voice-made-on-this-laptop',
    'and does not repoint her at a voice this device does not own', r.voiceId);
log(r.shared === false, 'so deleting her here still cannot destroy anyone else’s voice');

log(errs.length === 0, 'no console errors', errs.slice(0, 2).join(' | '));

await browser.close();
console.log(problems.length ? `\n${problems.length} failed:\n  ` + problems.join('\n  ')
                            : '\nall merge checks passed');
process.exit(problems.length ? 1 : 0);
