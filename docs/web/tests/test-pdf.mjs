// Reading a PDF in the browser.
//
// The web build used to refuse PDFs outright, for a good reason: reading one
// meant fetching a library off a CDN at run time, and a page that does that
// stops working the day the CDN does. The library is vendored now, so this
// suite holds the capability to the thing that reasoning actually cared about
// — no network, and a PDF's own pages still being its pages.

import pw from 'playwright';
import { readFileSync } from 'node:fs';

const URL_ = 'http://localhost:8899/index.html';
const problems = [];
const log = (ok, what, extra = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}${extra ? '  — ' + extra : ''}`);
  if (!ok) problems.push(what);
};

const pdf = readFileSync('/home/claude/out/_lion-en.pdf');
const arabicPdf = readFileSync('/home/claude/out/_lion.pdf');

const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
const page = await ctx.newPage();

const offsite = [];
// Everything except this origin is refused, and anything attempted is recorded.
// A library that quietly reaches for a CDN would show up here rather than in a
// bug report three weeks later.
await page.route('**/*', route => {
  const url = route.request().url();
  if (url.startsWith('http://localhost:8899') || url.startsWith('data:') || url.startsWith('blob:')) {
    return route.continue();
  }
  offsite.push(url);
  return route.abort();
});

const errs = [];
page.on('pageerror', e => errs.push('pageerror: ' + e.message));
page.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });

// Seeded into storage before the app boots, the way the other suites do it: a
// second dynamic import of core.js is a second module instance with its own
// store, and pushing a person into that one does not reach this one.
const PERSON = 'p-noura';
await page.addInitScript(person => {
  localStorage.setItem('jaddati.library', JSON.stringify({
    people: [person], assets: [], notes: [], books: [], letters: [],
  }));
}, {
  id: PERSON, name: 'Noura', fullName: '', relationship: 'Grandmother',
  voiceId: 'demo-voice-1', voiceCreatedAt: new Date().toISOString(),
  consentConfirmedAt: new Date().toISOString(), createdAt: new Date().toISOString(),
  photoFilename: null, cloudKey: null,
});

await page.goto(URL_, { waitUntil: 'networkidle' });
await page.waitForTimeout(600);
if (await page.locator('.btn-primary').count()) {
  await page.click('.btn-primary >> nth=0');
  await page.waitForTimeout(600);
}

// ── the import, through the module rather than six clicks ───────────────
const result = await page.evaluate(async bytes => {
  const m = await import('/core.js');
  const file = new File([new Uint8Array(bytes)], 'The Lion and the Mouse.pdf',
                        { type: 'application/pdf' });
  try {
    const book = await m.makeBook(file, 'p-noura');
    return {
      ok: true,
      title: book.title,
      pages: book.pages.length,
      first: (book.pages[0] || '').slice(0, 60),
      joined: book.pages.join(' \n '),
    };
  } catch (e) {
    return { ok: false, message: String(e && e.message || e) };
  }
}, Array.from(pdf));

log(result.ok, 'a PDF imports at all', result.ok ? '' : result.message);
if (result.ok) {
  log(result.pages >= 3, "the PDF's own pages survive as pages", String(result.pages));
  log(/Lion/i.test(result.title), 'the title comes off the filename', result.title);
  log(/lion was asleep/i.test(result.joined), 'the English text came through');
  log(!/\.pdf/i.test(result.title), 'the extension is not read aloud as part of the title', result.title);
}

// ── Arabic: refused on purpose, not quietly scrambled ───────────────────
const arabic = await page.evaluate(async bytes => {
  const m = await import('/core.js');
  const file = new File([new Uint8Array(bytes)], 'arabic.pdf', { type: 'application/pdf' });
  try { const b = await m.makeBook(file, 'p-noura'); return { ok: true, pages: b.pages.length }; }
  catch (e) { return { ok: false, message: String(e && e.message || e) }; }
}, Array.from(arabicPdf));
log(!arabic.ok, 'an Arabic PDF is refused rather than imported backwards',
    arabic.ok ? 'imported ' + arabic.pages + ' pages' : arabic.message);
log(!arabic.ok && /txt/i.test(arabic.message), 'and the refusal says what to do instead');

// ── a scan: pages, no text layer ────────────────────────────────────────
const scanned = await page.evaluate(async () => {
  const m = await import('/core.js');
  // A one-page PDF with a rectangle and no text at all.
  const body = [
    '%PDF-1.4',
    '1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj',
    '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj',
    '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]/Contents 4 0 R>>endobj',
    '4 0 obj<</Length 44>>stream',
    '0 0 0 rg 20 20 160 160 re f',
    'endstream endobj',
    'trailer<</Root 1 0 R>>',
  ].join('\n');
  const file = new File([body], 'scan.pdf', { type: 'application/pdf' });
  try {
    const book = await m.makeBook(file, 'p-noura');
    return { ok: true, pages: book.pages.length };
  } catch (e) {
    return { ok: false, message: String(e && e.message || e) };
  }
});
log(!scanned.ok, 'a PDF with no text layer is refused rather than imported empty',
    scanned.ok ? 'imported ' + scanned.pages + ' pages' : scanned.message);

log(offsite.length === 0, 'nothing was fetched off this origin', offsite.slice(0, 3).join(', '));
log(errs.length === 0, 'no console errors', errs.slice(0, 2).join(' | '));

await browser.close();
console.log(problems.length
  ? `\n${problems.length} failed:\n  ` + problems.join('\n  ')
  : '\nall PDF checks passed');
process.exit(problems.length ? 1 : 0);
