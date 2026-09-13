// The two new experiences, exercised the way a judge would meet them.
//
// Both put a model between what you type and what gets spoken, so the thing
// worth proving is not that a button lights up — it is that the transform runs,
// that the clip is labelled with the words that were actually said, and that
// the refusal path works. The refusal is the feature: an app that invents a
// grandmother's favourite dish and says it warmly is the failure this guards.

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

// Stub the relay: the voice returns audio, and the model echoes back whatever
// the prompt asked for so the grounding can be inspected.
let lastChat = null;
await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', async route => {
  const req = route.request();
  const url = req.url();
  if (url.includes('/v1/voices/add'))
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ voice_id: 'stub_v' }) });
  if (url.includes('/v1/text-to-speech/'))
    return route.fulfill({ status: 200, contentType: 'audio/mpeg', body: Buffer.alloc(4096, 9) });
  if (url.includes('/chat/completions')) {
    lastChat = JSON.parse(req.postData() || '{}');
    const system = lastChat.messages?.[0]?.content || '';
    const reply = system.includes('Translate the text into')
      ? 'THE TRANSLATION'
      : (system.includes('NOT_IN_NOTES') && /NOTES_EMPTY_TRIGGER/.test(lastChat.messages?.[1]?.content || '')
          ? 'NOT_IN_NOTES'
          : 'SHE LOVED MAQLUBA.');
    return route.fulfill({ status: 200, contentType: 'application/json',
      body: JSON.stringify({ choices: [{ message: { content: reply } }] }) });
  }
  return route.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
});

// Billed to an account now: without this the app refuses before it reaches
// the relay, and every assertion below would be testing the refusal.
await signedIn(page);
await page.goto(URL, { waitUntil: 'networkidle' });
await page.waitForTimeout(500);
await page.click('text=Allow these three things');
await page.waitForTimeout(400);

// a person with a voice
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

// The six ways of asking are chips inside the compose screen now, not six
// full-width rows on the person screen with a sentence under each.
await go.act(page);
log(await page.locator('.chip:has-text("Ask about them")').isVisible(), 'compose offers "Ask about them"');
log(await page.locator('.chip:has-text("Say it in their language")').isVisible(), 'and "Say it in their language"');

// ── asking with no notes at all ────────────────────────────────────────
await go.way(page, 'Ask about them');
log(await page.locator('text=What the family').isVisible(), 'the ask screen opens');
await page.fill('textarea', 'What was her favourite food?');
await page.waitForTimeout(300);
await page.click('.btn-primary:has-text("Ask")');
await page.waitForTimeout(900);
log(await page.locator('text=not in the memories your family has written down').isVisible(),
    'with no notes it refuses instead of inventing an answer');
log(lastChat === null, 'and it never even asked the model', lastChat ? 'a call was made' : '');

// ── now with notes ─────────────────────────────────────────────────────
await page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.people[0];
  m.store.addNote({ personId: p.id, text: 'She made maqluba every Friday for the whole family.' });
  m.store.addNote({ personId: p.id, text: 'She grew up in Nablus and moved to Abu Dhabi in 1974.' });
});
await page.waitForTimeout(400);
// Adding a note re-renders the screen, which empties the box — so ask again
// the way a person would, by typing it.
await page.fill('textarea', 'What was her favourite food?');
await page.waitForTimeout(250);
await page.click('.btn-primary:has-text("Ask")');
await page.waitForTimeout(1600);

log(!!lastChat, 'with notes present it does call the model');
const sys = lastChat?.messages?.[0]?.content || '';
log(sys.includes('maqluba'), 'the family notes are handed to it as the source material');
log(sys.includes('ONLY'), 'told to use only those notes');
log(/Do not speak as the person|Do not say 'I'/.test(sys), 'and forbidden from speaking as her');
log(!/Teta|Grandmother/.test(sys), 'the model is still never told whose voice it is', sys.match(/Teta|Grandmother/)?.[0] || '');
log(await page.locator('.player-art').isVisible(), 'the answer plays back');
const spoken = await page.evaluate(async () => (await import('./core.js?v=' + document.documentElement.dataset.v)).store.assets.slice(-1)[0]?.text);
log(spoken === 'SHE LOVED MAQLUBA.', 'the clip carries the words that were SPOKEN, not the question', spoken);
const prov = await page.evaluate(async () => (await import('./core.js?v=' + document.documentElement.dataset.v)).store.assets.slice(-1)[0]?.provenance);
log((prov || '').includes('favourite food'), 'and keeps the question it answered', prov);
const kind = await page.evaluate(async () => (await import('./core.js?v=' + document.documentElement.dataset.v)).store.assets.slice(-1)[0]?.contentKind);
log(kind === 'answerFromNotes', 'labelled as coming from the family notes', kind);

// ── the language bridge ────────────────────────────────────────────────
await page.click('.appbar button >> nth=0'); await page.waitForTimeout(300);
await page.click('.appbar button >> nth=0'); await page.waitForTimeout(400);
await go.act(page); await go.way(page, 'Say it in their language');
log(await page.locator('text=Across the').isVisible(), 'the language screen opens');
await page.fill('textarea', 'Good morning, my love.');
await page.waitForTimeout(300);
await page.click('.btn-primary:has-text("Say it across")');
await page.waitForTimeout(1600);
const sys2 = lastChat?.messages?.[0]?.content || '';
log(sys2.includes('Translate the text into Arabic'), 'English input is translated to Arabic');
log(sys2.includes('Gulf'), 'and asked for spoken Gulf wording, not newspaper Arabic');
const spoken2 = await page.evaluate(async () => (await import('./core.js?v=' + document.documentElement.dataset.v)).store.assets.slice(-1)[0]?.text);
log(spoken2 === 'THE TRANSLATION', 'the translation is what gets spoken', spoken2);
const kind2 = await page.evaluate(async () => (await import('./core.js?v=' + document.documentElement.dataset.v)).store.assets.slice(-1)[0]?.contentKind);
log(kind2 === 'translatedWords', 'and the clip says it is a translation', kind2);

// Arabic in, English out.
const dir = await page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  return m.Translator.targetFor('صباح الخير يا حبيبي');
});
log(dir === 'en', 'Arabic input goes the other way', dir);

const real = errs.filter(e => !/favicon|speechSynthesis|not-allowed/i.test(e));
log(real.length === 0, 'no console errors', real.slice(0, 3).join(' | '));

await browser.close();
console.log('\n' + (problems.length ? `${problems.length} PROBLEM(S)` : 'all new-feature checks passed'));
process.exit(problems.length ? 1 : 0);
