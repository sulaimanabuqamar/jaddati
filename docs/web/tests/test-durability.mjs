// The things that only go wrong the SECOND time.
//
// Every case here passed a first run and broke on a repeat, or broke only once
// something had been discarded. They are the expensive kind: a duplicate
// grandmother, a letter nothing can reach, a listener that is never let go.
// None of them announce themselves, so each one gets a test that presses the
// button twice.

import pw from 'playwright';
import { go } from './paths.mjs';

const URL_ = 'http://localhost:8899/index.html';
const problems = [];
const log = (ok, what, extra = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}${extra ? '  — ' + extra : ''}`);
  if (!ok) problems.push(what);
};

const drive = new Map();
const idToken = 'x.' + Buffer.from(JSON.stringify({ email: 'rayan@example.com' })).toString('base64') + '.y';
let refreshStatus = 200;
let lastAuthURL = null;

const stub = async page => {
  await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', async route => {
    const u = route.request().url();
    const j = (o, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(o) });
    if (u.endsWith('/google/status')) return j({ configured: true, clientId: 'test.apps.googleusercontent.com' });
    if (u.endsWith('/google/exchange'))
      return j({ refresh_token: 'refresh-1', access_token: 'access-1', expires_in: 3600, id_token: idToken });
    if (u.endsWith('/google/refresh')) {
      if (refreshStatus !== 200) return j({ error: 'backend_error' }, refreshStatus);
      return j({ access_token: 'access-2', expires_in: 3600 });
    }
    if (u.includes('/v1/voices/add')) return j({ voice_id: 'v1' });
    return j({});
  });
  await page.route('https://accounts.google.com/**', route => {
    lastAuthURL = route.request().url();
    return route.fulfill({ status: 200, contentType: 'text/html', body: '<html>consent</html>' });
  });
  await page.route('https://www.googleapis.com/**', async route => {
    const req = route.request(), u = req.url();
    const j = o => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(o) });
    if (!(req.headers()['authorization'] || '').startsWith('Bearer '))
      return route.fulfill({ status: 401, contentType: 'application/json', body: '{}' });
    if (u.includes('/upload/drive/')) {
      const body = req.postData() || '';
      const name = (body.match(/"name":"([^"]+)"/) || [])[1] || 'unnamed';
      drive.set(name, (body.split('\r\n\r\n')[2] || '').split('\r\n--')[0]);
      return j({ id: 'file-' + [...drive.keys()].indexOf(name) });
    }
    if (u.includes('alt=media')) {
      const i = Number(u.match(/files\/file-(\d+)/)[1]);
      return route.fulfill({ status: 200, contentType: 'application/json',
                             body: drive.get([...drive.keys()][i]) || '{}' });
    }
    return j({ files: [...drive.keys()].map((n, i) => ({ id: 'file-' + i, name: n })) });
  });
  page.on('pageerror', e => problems.push('pageerror: ' + e.message));
};

const start = async ctx => {
  const page = await ctx.newPage();
  await stub(page);
  await page.goto(URL_, { waitUntil: 'networkidle' });
  await page.waitForTimeout(500);
  await page.click('text=Allow these three things');
  await page.waitForTimeout(400);
  return page;
};

const signIn = async page => {
  await go.you(page);
  lastAuthURL = null;
  await page.click('button:has-text("Sign in with Google")');
  await page.waitForTimeout(900);
  // The state has to come out of the URL we were sent to: by now the page is
  // on Google's origin, where the app's own storage is not readable.
  const state = new URL(lastAuthURL).searchParams.get('state');
  await page.goto(URL_ + '?code=c1&state=' + encodeURIComponent(state), { waitUntil: 'networkidle' });
  await page.waitForTimeout(1000);
};

const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });

// ── restore, twice ──────────────────────────────────────────────────────
// The one that quietly ruins an archive. Import mints a fresh local id every
// time, so without a key tying a Drive file to someone already here, the
// second press stood a second grandmother beside the first — and the backup
// after THAT wrote a second Drive file for her.
{
  const ctxA = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const a = await start(ctxA);
  await signIn(a);

  await go.people(a);
  await a.click('text=Add someone'); await a.waitForTimeout(300);
  await a.fill('.sheet input >> nth=0', 'Teta');
  await a.click('.sheet button:has-text("Add person")'); await a.waitForTimeout(500);

  await go.you(a);
  await a.click('button:has-text("Back up now")'); await a.waitForTimeout(1500);
  log(drive.size === 1, 'one person, one file in Drive', String(drive.size));
  await ctxA.close();

  // a genuinely separate browser profile
  const ctxB = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const b = await start(ctxB);
  await signIn(b);

  await go.you(b);
  await b.click('button:has-text("Bring everything back")'); await b.waitForTimeout(1800);
  let people = await b.evaluate(() => JSON.parse(localStorage.getItem('jaddati.library') || '{}').people?.length || 0);
  log(people === 1, 'restore brings her back once', String(people));

  await b.click('button:has-text("Bring everything back")'); await b.waitForTimeout(1800);
  people = await b.evaluate(() => JSON.parse(localStorage.getItem('jaddati.library') || '{}').people?.length || 0);
  log(people === 1, 'and pressing it again does NOT stand a second copy beside her', String(people));

  const said = await b.locator('.toast').innerText().catch(() => '');
  log(/already here/i.test(said), 'and says so rather than claiming it brought her again', said);

  // and backing up from the restoring browser writes over the same file
  const before = drive.size;
  await b.click('button:has-text("Back up now")'); await b.waitForTimeout(1800);
  log(drive.size === before,
      'backing up after a restore writes over the same file, not beside it',
      `${before} → ${drive.size}`);
  await ctxB.close();
}

// ── a refresh that merely failed must not sign you out ──────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await start(ctx);
  await signIn(page);

  // expire the access token so the next call has to refresh
  await page.evaluate(() => {
    const raw = JSON.parse(localStorage.getItem('jaddati.cloud.tokens') || 'null');
    if (raw) { raw.expires_at = Date.now() - 1000; localStorage.setItem('jaddati.cloud.tokens', JSON.stringify(raw)); }
  });
  refreshStatus = 500;
  await go.you(page);
  await page.click('button:has-text("Back up now")');
  await page.waitForTimeout(1600);
  const body = await page.locator('.screen').innerText();
  log(/Sign out of Google/i.test(body),
      'a 500 on refresh leaves you signed in — it is the network, not the grant');
  log(!/Google access has ended/i.test(body),
      'and does not claim Google revoked anything');
  refreshStatus = 200;
  await ctx.close();
}

// ── a refused consent is still an answer ────────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await start(ctx);
  await page.goto(URL_ + '?error=access_denied', { waitUntil: 'networkidle' });
  await page.waitForTimeout(900);
  log(!/[?&]error=/.test(page.url()), 'a refusal is cleared from the address bar', page.url());
  const body = await page.locator('.screen, .gate').first().innerText();
  log(body.length > 0, 'and the app still comes up');
  await ctx.close();
}

// ── a letter you can no longer open, you can still remove ───────────────
// Discarding the clip puts the letter back in "waiting for you". If the button
// there is disabled — no voice, nothing configured — that card used to be the
// end of the road, and the words sat where nothing in the app could reach them.
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await start(ctx);
  await go.people(page);
  await page.click('text=Add someone'); await page.waitForTimeout(300);
  await page.fill('.sheet input >> nth=0', 'Teta');
  await page.click('.sheet button:has-text("Add person")'); await page.waitForTimeout(600);

  // a letter whose day has already come, on a person with no voice at all
  await page.evaluate(() => {
    const key = 'jaddati.library';
    const db = JSON.parse(localStorage.getItem(key) || '{}');
    const person = db.people[0];
    db.letters = db.letters || [];
    db.letters.push({
      id: 'letter-stuck', personId: person.id, text: 'Happy birthday, my love.',
      occasion: 'Her birthday',
      deliverAt: new Date(Date.now() - 86400000).toISOString(),
      createdAt: new Date(Date.now() - 172800000).toISOString(),
    });
    localStorage.setItem(key, JSON.stringify(db));
  });
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForTimeout(700);
  await go.letters(page);
  await page.waitForTimeout(500);
  // The Letters tab is a list across everyone; the card itself lives on the
  // person's own letters screen, which is where a letter can be acted on.
  await page.click('.feature-row'); await page.waitForTimeout(700);

  const card = page.locator('.screen');
  const text = await card.innerText();
  log(/Happy birthday/i.test(text) === false, 'a waiting letter never shows its words early');
  log(/Remove/i.test(text), 'a letter waiting to be opened offers a way out');
  log(/needs their recreated voice/i.test(text),
      'and says why the open button is grey rather than looking broken');

  await page.click('.screen button:has-text("Remove")'); await page.waitForTimeout(400);
  await page.click('.dialog button:has-text("Remove")'); await page.waitForTimeout(600);
  const left = await page.evaluate(() =>
    (JSON.parse(localStorage.getItem('jaddati.library') || '{}').letters || []).length);
  log(left === 0, 'and removing it actually removes it', String(left));
  await ctx.close();
}

// ── the player lets go of the player ────────────────────────────────────
// Each visit registered a "change" listener and relied on unmount to drop it.
// The screen was never tracked, so unmount never ran and the listeners piled
// up for the rest of the session.
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await start(ctx);

  // Installed before anything loads AND re-installed on every navigation, so a
  // reload does not quietly take the counter away and leave the test measuring
  // an undefined — which it silently did, and passed.
  await page.addInitScript(() => {
    // Count every "change" listener the app adds and drops, without guessing
    // at a class name — a filter that matches nothing makes this test pass by
    // measuring nothing at all, which is worse than not having it.
    window.__net = 0;
    const proto = EventTarget.prototype;
    const add = proto.addEventListener, rm = proto.removeEventListener;
    proto.addEventListener = function (t, f, o) {
      // Only the app's own EventTargets — the player and the store. A change
      // listener on a DOM input dies with the element and is not a leak; the
      // ones that outlive their screen are the ones on these.
      if (t === 'change' && !(this instanceof Element) && !(this instanceof Document)) window.__net++;
      return add.call(this, t, f, o);
    };
    proto.removeEventListener = function (t, f, o) {
      if (t === 'change' && !(this instanceof Element) && !(this instanceof Document)) window.__net--;
      return rm.call(this, t, f, o);
    };
  });

  await go.people(page);
  await page.click('text=Add someone'); await page.waitForTimeout(300);
  await page.fill('.sheet input >> nth=0', 'Teta');
  await page.click('.sheet button:has-text("Add person")'); await page.waitForTimeout(600);

  // Open a clip, come back, repeat. The player screen is the one that used to
  // register a listener and never let it go.
  // A recording to render rows for. The file itself is absent, which is fine:
  // the row still renders, and the row is what subscribes to the player.
  await page.evaluate(() => {
    const key = 'jaddati.library';
    const db = JSON.parse(localStorage.getItem(key) || '{}');
    const person = db.people[0];
    db.assets = db.assets || [];
    for (let i = 0; i < 3; i++) {
      db.assets.push({
        id: 'asset-' + i, personId: person.id, source: 'original',
        filename: 'missing-' + i + '.m4a', text: 'A recording', durationSeconds: 4,
        createdAt: new Date().toISOString(), isSaved: true,
      });
    }
    localStorage.setItem(key, JSON.stringify(db));
  });
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForTimeout(700);

  const readings = [];
  for (let i = 0; i < 3; i++) {
    await go.people(page); await page.waitForTimeout(300);
    await page.click('.bigcard, .person-card, .feature-row').catch(() => {});
    await page.waitForTimeout(500);
    await go.you(page); await page.waitForTimeout(300);
    readings.push(await page.evaluate(() => window.__net));
  }
  log(readings.some(n => n > 0), 'the counter is actually seeing listeners', readings.join(' → '));
  // Not "zero" — the app legitimately holds some while a screen is up. What
  // matters is that the number stops growing lap after lap.
  log(readings[2] <= readings[0],
      'moving between tabs does not leave listeners behind', readings.join(' → '));
  await ctx.close();
}

await browser.close();
console.log(problems.length ? `\n${problems.length} PROBLEM(S)` : '\nall OK');
process.exit(problems.length ? 1 : 0);
