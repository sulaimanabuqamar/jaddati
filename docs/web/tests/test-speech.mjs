// What happens to the words between typing them and hearing them.
//
// Two features that only exist in the gap: a blank line between paragraphs
// becomes a pause, and bare Arabic gets its harakat added first so the voice
// service is not guessing which word علم is. Both are invisible on screen and
// both change what a dead person is made to say, which is the reason they are
// checked here rather than taken on trust.
//
// The functions are exercised directly AND through Voice.synthesize, because
// the thing that actually matters is what ends up in the request body — a
// correct helper called in the wrong order, or not called at all, looks exactly
// like a working feature from the outside.

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

const m = await page.evaluateHandle(() => import('/core.js'));
const call = (fn, ...args) => page.evaluate(([mod, name, rest]) => mod[name](...rest), [m, fn, args]);

// ── the pauses ─────────────────────────────────────────────────────────
const TAG = await page.evaluate(mod => mod.PAUSE_TAG, m);
log(/^<break time="[\d.]+s" \/>$/.test(TAG), 'the pause is a break tag the v2 models read', TAG);
log(parseFloat(TAG.match(/([\d.]+)s/)[1]) <= 3, 'and is within the three seconds the service allows');

log(await call('withParagraphPauses', 'one\n\ntwo') === 'one\n' + TAG + '\ntwo',
    'a blank line between paragraphs becomes a pause');
log(await call('withParagraphPauses', 'one\ntwo') === 'one\ntwo',
    'a single newline does not — a line break is not a silence');
log(await call('withParagraphPauses', 'one\n \t \ntwo') === 'one\n' + TAG + '\ntwo',
    'a line with only spaces on it still counts as blank');
log(await call('withParagraphPauses', 'one\r\n\r\ntwo') === 'one\n' + TAG + '\ntwo',
    'and so does a Windows one, which is what a pasted document brings');
log(await call('withParagraphPauses', 'one\n\n\n\ntwo') === 'one\n' + TAG + '\ntwo',
    'four blank lines are one pause, not four');
log(await call('withParagraphPauses', 'no breaks here') === 'no breaks here',
    'text with no blank line is returned untouched');
log(await call('withParagraphPauses', '') === '', 'and so is nothing at all');

// The service's own warning: too many break tags in one generation and it
// starts speeding up or adding artefacts. Past the ceiling the app sends none
// rather than sending something that will be read badly.
const many = Array.from({ length: 9 }, (_, i) => 'p' + i).join('\n\n');
log(await call('withParagraphPauses', many) === many,
    'past the ceiling no tags are inserted at all, rather than too many');
const six = Array.from({ length: 7 }, (_, i) => 'p' + i).join('\n\n');
log((await call('withParagraphPauses', six)).split(TAG).length - 1 === 6,
    'six is still allowed, so the ceiling is a ceiling and not an off-by-one');

// ── deciding whether Arabic needs marks ────────────────────────────────
log(await call('needsHarakat', 'أريد أن أسمع صوتك مرة أخرى قبل أن أنام') === true,
    'a bare Arabic sentence is marked before it is spoken');
log(await call('needsHarakat', 'نعم') === false,
    'a short one is left alone — the call is not worth a word');
log(await call('needsHarakat', 'يُمْكِنُكَ التَّمَهُّلُ. لَا يَلْزَمُ أَنْ تَحْسِمَ شَيْئًا الْآنَ.') === false,
    'text that already carries harakat is not sent to have them added again');
log(await call('needsHarakat', 'Good morning, my love, I hope you slept well') === false,
    'and English is not Arabic with missing marks');

// ── the guard that makes the feature safe at all ───────────────────────
// A model asked to add harakat will sometimes answer the sentence, or tidy the
// grammar. Either would put words the family never wrote into her mouth.
const bare = 'أريد أن أسمع صوتك';
log(await call('marksOnly', 'أُرِيدُ أَنْ أَسْمَعَ صَوْتَكَ', bare) === true,
    'marks added and nothing else is accepted');
log(await call('marksOnly', 'أُرِيدُ أَنْ أَسْمَعَ صَوْتَكِ يا جدتي', bare) === false,
    'a model that added a word is refused');
log(await call('marksOnly', 'أريد أن أسمع صوتها', bare) === false,
    'a model that changed one letter is refused');
log(await call('marksOnly', 'Sure! Here is your text with harakat:', bare) === false,
    'and one that answered instead of marking is refused');
log(await call('marksOnly', '', bare) === false, 'an empty reply is refused');
log(await call('marksOnly', 'أريد أن  أسمع  صوتك', bare) === true,
    'but spacing alone is not a change worth losing the marks over');

// ── through the real path, which is what actually ships ────────────────
// Both features at once, in the order they have to happen: marks first, then
// pauses. The other order hands a break tag to a model that has just been told
// to put a vowel on every letter.
const body = await page.evaluate(async ([mod]) => {
  const sent = [];
  const realFetch = window.fetch;
  window.fetch = async (url, init) => {
    const href = String(url && url.url ? url.url : url);
    sent.push({ href, body: init && init.body });
    if (href.includes('/chat/completions')) {
      // Stand in for the harakat model, answering the way a good one does.
      return new Response(JSON.stringify({
        choices: [{ message: { content: 'أُرِيدُ أَنْ أَسْمَعَ صَوْتَكَ\n\nمَرَّةً أُخْرَى' } }],
      }), { status: 200, headers: { 'content-type': 'application/json' } });
    }
    if (href.includes('/v1/text-to-speech/')) {
      return new Response(new Blob([new Uint8Array(4096)]), { status: 200, headers: { 'content-type': 'audio/mpeg' } });
    }
    return realFetch(url, init);
  };
  // Signed in, because speaking through the relay needs an account now.
  const b64 = o => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  localStorage.setItem('jaddati.cloud.tokens', JSON.stringify({
    refresh_token: 'r', access_token: 'a', expires_at: Date.now() + 3600e3, email: 't@e.com',
    id_token: [b64({ alg: 'RS256' }), b64({ sub: 't', exp: Math.floor(Date.now() / 1000) + 3600 }), 'sig'].join('.'),
  }));
  try {
    await mod.Voice.synthesize('أريد أن أسمع صوتك\n\nمرة أخرى', 'voice-1', 'eleven_multilingual_v2',
      { stability: 0.5, similarity: 0.8, style: 0, speakerBoost: true, speed: 1 });
  } catch (e) { return { error: String(e && e.message || e) }; }
  finally { window.fetch = realFetch; }
  const speech = sent.find(s => s.href.includes('/v1/text-to-speech/'));
  return { asked: sent.map(s => s.href), text: speech && JSON.parse(speech.body).text };
}, [m]);

log(!body.error, 'a real generation goes through with both features on', body.error || '');
if (!body.error) {
  log(body.asked.some(h => h.includes('/chat/completions')),
      'bare Arabic was sent to have its marks added first');
  log(/[ً-ْ]/.test(body.text || ''), 'and what is spoken carries them', (body.text || '').slice(0, 30));
  log((body.text || '').includes(TAG), 'the blank line arrived as a pause');
  log(((body.text || '').indexOf(TAG) > 0) &&
      /[ً-ْ]/.test((body.text || '').slice(0, (body.text || '').indexOf(TAG))),
      'marks first and pauses second, so no break tag was ever handed to the model');
}

log(errs.length === 0, 'no console errors', errs.slice(0, 2).join(' | '));

await browser.close();
console.log(problems.length ? `\n${problems.length} failed:\n  ` + problems.join('\n  ')
                            : '\nall speech-shaping checks passed');
process.exit(problems.length ? 1 : 0);
