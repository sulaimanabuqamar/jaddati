// Signing in with Google, and what it is and is not for.
//
// Google is stubbed at the network edge: the point is that OUR flow is
// right — PKCE, state, the code spent once, tokens refreshed, the backup
// carrying the same archive the code handoff sends — not that Google works.

import pw from 'playwright';
import { go } from './paths.mjs';

const URL_ = 'http://localhost:8899/index.html';
const problems = [];
const log = (ok, what, extra = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}${extra ? '  — ' + extra : ''}`);
  if (!ok) problems.push(what);
};

const drive = new Map();          // stands in for appDataFolder
let exchanges = 0, refreshes = 0, lastAuthURL = null;
const idToken = 'x.' + Buffer.from(JSON.stringify({ email: 'rayan@example.com' })).toString('base64') + '.y';

const stub = async (page, { configured = true } = {}) => {
  await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', async route => {
    const u = route.request().url();
    const j = (o, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(o) });
    if (u.endsWith('/google/status'))
      return j({ configured, clientId: configured ? 'test-client-id.apps.googleusercontent.com' : '' });
    if (u.endsWith('/google/exchange')) {
      exchanges++;
      return j({ refresh_token: 'refresh-1', access_token: 'access-1', expires_in: 3600, id_token: idToken });
    }
    if (u.endsWith('/google/refresh')) {
      refreshes++;
      return j({ access_token: 'access-2', expires_in: 3600 });
    }
    if (u.includes('/v1/voices/add')) return j({ voice_id: 'v1' });
    return j({});
  });

  // Google's consent screen: never actually visited, just observed.
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
      const payload = body.split('\r\n\r\n')[2] || '';
      drive.set(name, payload.split('\r\n--')[0]);
      return j({ id: 'file-' + drive.size });
    }
    if (u.includes('alt=media')) {
      const id = u.match(/files\/([^?]+)/)[1];
      const name = [...drive.keys()][Number(id.replace('file-', '')) - 1];
      return route.fulfill({ status: 200, contentType: 'application/json', body: drive.get(name) || '{}' });
    }
    return j({ files: [...drive.keys()].map((n, i) => ({ id: 'file-' + (i + 1), name: n })) });
  });
  page.on('pageerror', e => problems.push('pageerror: ' + e.message));
};

const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });

// ── not configured: nothing is offered ─────────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  await stub(page, { configured: false });
  await page.goto(URL_, { waitUntil: 'networkidle' });
  await page.waitForTimeout(600);
  await page.click('text=Allow these three things'); await page.waitForTimeout(400);
  await go.you(page);
  const body = await page.locator('.screen').innerText();
  log(!/Sign in with Google/i.test(body), 'with no client id, sign-in is not offered at all');
  await ctx.close();
}

// ── configured: the flow ───────────────────────────────────────────────
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
const page = await ctx.newPage();
await stub(page);
await page.goto(URL_, { waitUntil: 'networkidle' });
await page.waitForTimeout(600);
await page.click('text=Allow these three things'); await page.waitForTimeout(400);
await go.you(page);

const body = await page.locator('.screen').innerText();
log(/Sign in with Google/i.test(body), 'configured, so it is offered');
log(/not how you give someone to the family/i.test(body),
  'and says plainly it is NOT family sharing');

await page.click('button:has-text("Sign in with Google")');
await page.waitForTimeout(900);
log(!!lastAuthURL, 'it goes to Google');
const auth = new URL(lastAuthURL || 'https://x/');
log(auth.searchParams.get('code_challenge_method') === 'S256', 'with PKCE, not a bare redirect');
log(!!auth.searchParams.get('state'), 'and a state to tie the answer back to the ask');
log(auth.searchParams.get('access_type') === 'offline' && auth.searchParams.get('prompt') === 'consent',
  'asking for offline access, or the backup dies in an hour');
log(auth.searchParams.get('scope').includes('drive.appdata'),
  'scoped to the private app folder', auth.searchParams.get('scope'));
log(!auth.searchParams.get('scope').includes('drive.file') &&
    !/auth\/drive($|\s)/.test(auth.searchParams.get('scope')),
  'and NOT to the rest of their Drive');

// come back the way Google sends you back
const state = auth.searchParams.get('state');
await page.goto(URL_ + '?code=auth-code-1&state=' + encodeURIComponent(state), { waitUntil: 'networkidle' });
await page.waitForTimeout(1200);
log(exchanges === 1, 'the code is exchanged once', String(exchanges));
log(!/[?&]code=/.test(page.url()), 'and cleared from the address bar', page.url());

await go.you(page);
const after = await page.locator('.screen').innerText();
log(/rayan@example.com/.test(after), 'the account is shown', after.split('\n').find(l => /@/.test(l)) || '');

// a person to back up
await go.people(page);
await page.click('text=Add someone'); await page.waitForTimeout(300);
await page.fill('.sheet input >> nth=0', 'Teta');
await page.click('.sheet button:has-text("Add person")'); await page.waitForTimeout(500);

await go.you(page);
await page.click('button:has-text("Back up now")');
await page.waitForTimeout(1800);
log(drive.size === 1, 'one file per person went up', String(drive.size));
const name = [...drive.keys()][0];
log(/^person-.*\.jaddati\.json$/.test(name), 'named so a restore can find it', name);
const stored = JSON.parse(drive.get(name) || '{}');
log(stored.jaddati === 1 && stored.person?.name === 'Teta',
  'and it is the SAME archive the code handoff sends, not a second format');

// a genuinely separate profile brings it back
const ctxB = await browser.newContext({ viewport: { width: 390, height: 844 } });
const b = await ctxB.newPage();
await stub(b);
await b.goto(URL_, { waitUntil: 'networkidle' });
await b.waitForTimeout(600);
await b.click('text=Allow these three things'); await b.waitForTimeout(400);
await b.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  m.Cloud.tokens = { refresh_token: 'r', access_token: '', expires_at: 0, email: 'rayan@example.com' };
});
await go.you(b);
await b.click('button:has-text("Bring everything back")');
await b.waitForTimeout(2000);
log(refreshes >= 1, 'an expired token is refreshed rather than failing', String(refreshes));
const restored = await b.evaluate(async () => (await import('./core.js?v=' + document.documentElement.dataset.v)).store.people.map(p => p.name));
log(restored.includes('Teta'), 'she comes back on the other phone', restored.join(','));

await browser.close();
console.log('\n' + (problems.length ? `${problems.length} PROBLEM(S)` : 'all cloud checks passed'));
process.exit(problems.length ? 1 : 0);
