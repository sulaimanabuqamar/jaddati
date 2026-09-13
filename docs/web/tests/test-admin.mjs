// The admin page, driven the way he will drive it on demo day.
//
// The relay is stubbed: this proves the page asks the right question, survives
// a wrong token, draws what comes back, and — the part that matters most on a
// public page — never writes the token anywhere that outlives the tab.

import pw from 'playwright';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, normalize } from 'node:path';

// Its own server, rooted at docs/ rather than at docs/web/ like the other
// suites: the page under test lives one level up from them and loads the
// shared stylesheet from there. Starting one here keeps `node test-admin.mjs`
// a complete instruction rather than one that only works if you remember to
// serve the right directory first.
const DOCS = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const TYPES = { '.html': 'text/html', '.css': 'text/css', '.svg': 'image/svg+xml', '.js': 'text/javascript' };
const server = createServer(async (req, res) => {
  let path = normalize(decodeURIComponent(req.url.split('?')[0]));
  if (path.endsWith('/')) path += 'index.html';
  try {
    const body = await readFile(join(DOCS, path));
    const dot = path.lastIndexOf('.');
    res.writeHead(200, { 'content-type': TYPES[path.slice(dot)] || 'application/octet-stream' });
    res.end(body);
  } catch { res.writeHead(404).end('no'); }
});
await new Promise(r => server.listen(0, r));
const URL_ = `http://localhost:${server.address().port}/admin/`;
const problems = [];
const log = (ok, what, extra = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}${extra ? '  — ' + extra : ''}`);
  if (!ok) problems.push(what);
};

const now = Date.now();
const ROLL = {
  accounts: [
    { sub: 'amal', email: 'amal@example.com', firstSeen: now - 86400000 * 2, lastSeen: now - 20000,
      generations: 7, characters: 910, usedThisMonth: 910, leftThisMonth: 90 },
    { sub: 'bilal', email: 'bilal@example.com', firstSeen: now - 3600000, lastSeen: now - 3600000,
      generations: 22, characters: 1000, usedThisMonth: 1000, leftThisMonth: 0 },
  ],
  voices: { held: 4, cap: 6, slots: [] },
  creditsPerAccount: 1000,
  month: '2026-09',
};

const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
const page = await ctx.newPage();

const errs = [];
page.on('pageerror', e => errs.push('pageerror: ' + e.message));
page.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });

let asked = [];
await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', route => {
  const token = route.request().headers()['x-jaddati-admin'] || '';
  asked.push({ url: route.request().url(), method: route.request().method(), token });
  if (token !== 'the-real-one')
    return route.fulfill({ status: 401, contentType: 'application/json', body: '{"detail":"unauthorised"}' });
  return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(ROLL) });
});

await page.goto(URL_, { waitUntil: 'networkidle' });
await page.waitForTimeout(300);

log(await page.locator('#gate').isVisible(), 'the page asks for a token before anything else');
log(!(await page.locator('#roll').isVisible().catch(() => false)), 'and shows nothing until it has one');
const html = await page.content();
log(!/the-real-one/.test(html), 'the page itself carries no token');

// ── a wrong token ──────────────────────────────────────────────────────
await page.fill('#token', 'wrong');
await page.click('#gate button[type=submit]');
await page.waitForTimeout(400);
log((await page.locator('#problem').textContent()).includes('refused'),
    'a refused token says so, rather than failing silently');
log(!(await page.locator('#roll').isVisible().catch(() => false)), 'and the roll stays shut');
log(!(await page.evaluate(() => sessionStorage.getItem('jaddati.admin.token'))),
    'a token that did not work is not remembered');

// ── the right one ──────────────────────────────────────────────────────
await page.fill('#token', 'the-real-one');
await page.click('#gate button[type=submit]');
await page.waitForTimeout(500);
log(await page.locator('#roll').isVisible(), 'the right token opens the roll');
log((await page.locator('#rows tr').count()) === 2, 'both accounts are drawn',
    String(await page.locator('#rows tr').count()));
log((await page.locator('#t-people').textContent()) === '2', 'the count agrees with the table');
log((await page.locator('#t-voices').textContent()) === '4 / 6', 'voices held are shown against the cap',
    await page.locator('#t-voices').textContent());
log((await page.locator('#t-made').textContent()) === '29', 'the clips are totalled',
    await page.locator('#t-made').textContent());

const firstRow = await page.locator('#rows tr >> nth=0').innerText();
log(/amal@example\.com/.test(firstRow), 'the address is shown');
log(/just now|seconds ago|minute/.test(firstRow), 'and when they were last seen, in words',
    firstRow.replace(/\s+/g, ' ').slice(0, 70));
const secondRow = await page.locator('#rows tr >> nth=1').innerText();
log(/none left/i.test(secondRow), 'an account with nothing left says so plainly');
log((await page.locator('.low').count()) === 1, 'and is the only one marked');

// ── the request itself ─────────────────────────────────────────────────
const good = asked.find(a => a.token === 'the-real-one');
log(!!good && good.method === 'GET', 'the roll is read with GET', good && good.method);
log(!!good && /\/admin\/accounts$/.test(good.url), 'at /admin/accounts', good && good.url);

// ── the token's life ───────────────────────────────────────────────────
log(await page.evaluate(() => sessionStorage.getItem('jaddati.admin.token')) === 'the-real-one',
    'a working token is kept for this tab');
log(!(await page.evaluate(() => localStorage.getItem('jaddati.admin.token'))),
    'and never written to storage that outlives the tab');

await page.reload({ waitUntil: 'networkidle' });
await page.waitForTimeout(500);
log(await page.locator('#roll').isVisible(), 'a reload in the same tab does not ask again');

await page.click('#forget');
await page.waitForTimeout(200);
log(await page.locator('#gate').isVisible() && !(await page.evaluate(() => sessionStorage.getItem('jaddati.admin.token'))),
    'and forgetting it really forgets it');

// An address is somebody else's text. If it were ever written as markup this
// is where it would show.
ROLL.accounts[0].email = '<img src=x onerror="window.__pwned=1">@example.com';
await page.fill('#token', 'the-real-one');
await page.click('#gate button[type=submit]');
await page.waitForTimeout(500);
log(!(await page.evaluate(() => window.__pwned)), 'an address from the relay is drawn as text, not as markup');
log((await page.locator('#rows tr >> nth=0').innerText()).includes('onerror'),
    'and is shown exactly as it arrived');

// ── nothing left this origin ───────────────────────────────────────────
// The two refusals above are deliberate, and Chromium logs every 401 it sees
// whether or not the page handled it. What is being watched for here is a
// script that threw.
const real = errs.filter(e => !/401 \(Unauthorized\)|favicon/i.test(e));
log(real.length === 0, 'no console errors', real.slice(0, 2).join(' | '));

await browser.close();
server.close();
console.log(problems.length ? `\n${problems.length} failed:\n  ` + problems.join('\n  ')
                            : '\nall admin page checks passed');
process.exit(problems.length ? 1 : 0);
