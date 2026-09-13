// What a backup carries that a shared file does not — and the two shapes the
// two platforms write.
//
// Two separate claims are checked here.
//
// The first is the rule: sharing carries the original recordings and nothing
// else, because a shared file has to clear WhatsApp and the relay's ceiling and
// a clip can be made again at the other end. A BACKUP carries the kept clips
// too, because "the laptop is gone, is she still there?" is not answered by
// telling someone to write the words again.
//
// The second is the wire. The phone writes each recording flat — text,
// durationSeconds, fileExtension at the top level. This platform wrote them one
// level down inside `asset`, and read only that. So every recording that
// crossed from iOS arrived with no words, a zero duration and the wrong file
// extension, and nothing anywhere said so. Both shapes are read now, and both
// are written, which is the only way the two halves actually meet.
//
// Driven through the module rather than the UI: these are claims about the
// archive, and putting sixty clicks in front of them only buys flakiness.

import pw from 'playwright';

const URL = 'http://localhost:8899/index.html';
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
await page.goto(URL, { waitUntil: 'networkidle' });
await page.waitForTimeout(400);

// ── seed one person: one real recording, one clip she was made to say ──
const made = await page.evaluate(async () => {
  const m = await import('/core.js');
  const { store } = m;
  const personId = m.uuid();
  store.people.push({
    id: personId, name: 'Teta', fullName: 'Noura', relationship: 'Grandmother',
    voiceId: 'family_voice_1', createdAt: new Date().toISOString(),
    photoFilename: null, cloudKey: null,
  });
  const bytes = () => new Blob([new Uint8Array(2048).fill(7)], { type: 'audio/mp4' });
  const original = await store.storeAudio(bytes(), {
    personId, source: 'original', text: 'The kitchen, 2019', duration: 94,
  });
  const kept = await store.storeAudio(bytes(), {
    personId, source: 'generated', text: 'Take your time.', duration: 6,
    intent: 'comfort', content: 'wordsSuppliedByYou', isSaved: true,
  });
  // A book page: stored saved so a page is never paid for twice, which is
  // exactly why the export must not read `isSaved` directly.
  const page5 = await store.storeAudio(bytes(), {
    personId, source: 'generated', text: 'Page five.', duration: 4,
    bookId: m.uuid(), pageIndex: 5, isSaved: true,
  });
  return { personId, original: !!original, kept: !!kept, page5: !!page5 };
});
log(made.original && made.kept && made.page5, 'seeded a recording, a kept clip and a book page');

// ── what each of the two jobs carries ──────────────────────────────────
const carried = await page.evaluate(async personId => {
  const m = await import('/core.js');
  const shared = await m.Archive.export(personId);
  const backup = await m.Archive.export(personId, { includingKeptClips: true });
  const kinds = f => f.file.recordings.map(r => r.source);
  return {
    sharedCount: shared.file.recordings.length,
    sharedKinds: kinds(shared),
    backupCount: backup.file.recordings.length,
    backupKinds: kinds(backup),
    backupOriginals: backup.carriedOriginals,
    first: backup.file.recordings[0],
  };
}, made.personId);

log(carried.sharedCount === 1, 'a shared file still carries originals only', String(carried.sharedCount));
log(carried.backupCount === 2, 'a backup carries the kept clip too', String(carried.backupCount));
log(!carried.backupKinds.includes(undefined) && carried.backupKinds[0] === 'original'
    && carried.backupKinds[1] === 'generated',
  'originals first, and each one says which it is', carried.backupKinds.join(', '));
log(carried.backupOriginals === 1, 'originals are counted apart from the clips',
  String(carried.backupOriginals));
log(carried.backupCount === 2, 'the book page is left out — isSaved is not "chosen"');

// The fields the PHONE reads. Inside `asset` they are invisible to it.
const r = carried.first || {};
log(r.text === 'The kitchen, 2019', 'the words are written flat, where iOS looks', JSON.stringify(r.text));
log(r.durationSeconds === 94, 'and the duration', String(r.durationSeconds));
log(typeof r.fileExtension === 'string' && r.fileExtension.length > 0,
  'and a file extension, not only a MIME type', r.fileExtension);
log(!!r.asset, 'the old nested shape is still written, so archives in the wild keep opening');

// ── an archive written by the PHONE, opened here ───────────────────────
const fromPhone = await page.evaluate(async () => {
  const m = await import('/core.js');
  const b64 = btoa(String.fromCharCode(...new Uint8Array(512).fill(9)));
  // Exactly what Archive.swift writes: flat fields, no `asset`, no `type`,
  // and dates with no fractional seconds.
  const file = {
    jaddati: 1,
    exportedAt: '2026-09-13T10:00:00Z',
    person: { name: 'Teta', fullName: 'Noura', relationship: 'Grandmother',
              voiceId: 'family_voice_1', consentConfirmedAt: '2026-09-12T08:00:00Z' },
    notes: [], letters: [],
    recordings: [
      { text: 'The kitchen, 2019', durationSeconds: 94, fileExtension: 'm4a',
        source: 'original', createdAt: '2026-09-12T08:00:00Z', data: b64 },
      { text: 'Take your time.', durationSeconds: 6, fileExtension: 'm4a',
        source: 'generated', intent: 'comfort', contentKind: 'wordsSuppliedByYou',
        createdAt: '2026-09-12T09:00:00Z', data: b64 },
    ],
  };
  const result = await m.Archive.import(JSON.stringify(file));
  const landed = m.store.assets.filter(a => a.personId === result.person.id);
  return {
    restored: result.restored,
    texts: landed.map(a => a.text).sort(),
    durations: landed.map(a => a.durationSeconds).sort((x, y) => x - y),
    extensions: landed.map(a => (a.filename.split('.').pop())),
    sources: landed.map(a => a.source).sort(),
    intents: landed.map(a => a.intentRaw).filter(Boolean),
    dates: landed.map(a => a.createdAt).sort(),
  };
});

log(fromPhone.restored === 2, 'both recordings arrive from the phone', String(fromPhone.restored));
log(fromPhone.texts.includes('The kitchen, 2019'),
  'with the words intact — they used to arrive blank', JSON.stringify(fromPhone.texts));
log(fromPhone.durations.includes(94),
  'and the duration — it used to arrive as zero', JSON.stringify(fromPhone.durations));
log(fromPhone.extensions.every(e => e === 'm4a'),
  'and under the right name — everything used to land as .mp3', fromPhone.extensions.join(', '));
log(fromPhone.sources.join(',') === 'generated,original',
  'and the clip is still a clip, not a recording of her', fromPhone.sources.join(', '));
log(fromPhone.intents.includes('comfort'),
  'the clip remembers which screen made it', fromPhone.intents.join(', '));
log(fromPhone.dates.some(d => d.startsWith('2026-09-12')),
  'and the day it was made, not the day it arrived', fromPhone.dates.join(', '));

// ── an archive written by an OLDER version of this platform ────────────
const old = await page.evaluate(async () => {
  const m = await import('/core.js');
  const b64 = btoa(String.fromCharCode(...new Uint8Array(512).fill(9)));
  const file = {
    jaddati: 1,
    exportedAt: new Date().toISOString(),
    person: { name: 'Teta', relationship: 'Grandmother', voiceId: 'family_voice_1' },
    notes: [], letters: [],
    recordings: [{
      asset: { text: 'From before', durationSeconds: 11, source: 'original',
               createdAt: new Date().toISOString() },
      type: 'audio/mpeg',
      data: b64,
    }],
  };
  const result = await m.Archive.import(JSON.stringify(file));
  const landed = m.store.assets.filter(a => a.personId === result.person.id);
  return { restored: result.restored, text: landed[0]?.text, seconds: landed[0]?.durationSeconds };
});
log(old.restored === 1 && old.text === 'From before' && old.seconds === 11,
  'an archive from an older build of this platform still opens intact',
  `${old.text}, ${old.seconds}s`);

log(errs.length === 0, 'no console errors', errs.slice(0, 3).join(' | '));

await browser.close();
console.log(problems.length
  ? `\n${problems.length} failed:\n  ` + problems.join('\n  ')
  : '\nall clip and cross-platform checks passed');
process.exit(problems.length ? 1 : 0);
