// Dark is a switch, and the app opens light.
//
// Three things worth pinning: a first visit is light with no stored
// preference at all; the switch actually changes the document; and the
// choice survives a reload. The fourth is the one that bit on the phone —
// that nothing is left behind carrying a light surface into dark.

import pw from 'playwright';

const URL = 'http://localhost:8899/index.html';
const problems = [];
const log = (ok, what, extra = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}${extra ? '  — ' + extra : ''}`);
  if (!ok) problems.push(what);
};

const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });

// A phone set to DARK. The app should still open light, because this is a
// choice the user makes rather than one the system makes for them.
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, colorScheme: 'dark' });
const page = await ctx.newPage();
const errs = [];
page.on('pageerror', e => errs.push(e.message));

await page.goto(URL, { waitUntil: 'networkidle' });
await page.waitForTimeout(500);

const attr = () => page.evaluate(() => document.documentElement.getAttribute('data-theme'));
const ground = () => page.evaluate(() =>
  getComputedStyle(document.documentElement).getPropertyValue('--paper').trim());

log(await attr() === null, 'a first visit carries no theme attribute', String(await attr()));
log((await ground()).toUpperCase() === '#F9F5EF', 'and opens LIGHT even on a dark phone', await ground());
log(await page.evaluate(() => localStorage.getItem('jaddati.appearance')) === null,
  'nothing stored until the user chooses');

await page.click('text=Allow these three things'); await page.waitForTimeout(400);
await page.click('.tabrail button >> nth=2'); await page.waitForTimeout(400);
log(await page.locator('.switch:has-text("Dark mode")').isVisible(), 'You offers a Dark mode switch');

await page.click('.switch:has-text("Dark mode") input'); await page.waitForTimeout(500);
log(await attr() === 'dark', 'switching it on marks the document', String(await attr()));
log((await ground()).toUpperCase() === '#14100E', 'and the ground goes dark', await ground());
await page.screenshot({ path: '/home/claude/web/th-dark.png' });

// The phone bug: a surface that stayed light while the text on it went pale.
const offenders = await page.evaluate(() => {
  const lum = c => { const m = c.match(/\d+/g); if (!m) return null;
    const [r,g,b] = m.map(Number).map(v => { v/=255; return v<=.03928 ? v/12.92 : ((v+.055)/1.055)**2.4; });
    return .2126*r + .7152*g + .0722*b; };
  const out = [];
  for (const el of document.querySelectorAll('.screen *, .tabrail *')) {
    const bg = getComputedStyle(el).backgroundColor;
    if (!bg || bg === 'rgba(0, 0, 0, 0)') continue;
    const L = lum(bg);
    // A near-white surface in dark mode is the shape of the bug: the card
    // stayed cream while the name on it went near-white and vanished.
    if (L !== null && L > 0.6 && !el.closest('.hero')) {
      out.push((el.className || el.tagName) + ' ' + bg);
    }
  }
  return out.slice(0, 6);
});
log(offenders.length === 0, 'no near-white surface survives into dark', offenders.join(' | '));

await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(600);
log(await attr() === 'dark', 'the choice survives a reload', String(await attr()));

await page.click('.tabrail button >> nth=2'); await page.waitForTimeout(400);
await page.click('.switch:has-text("Dark mode") input'); await page.waitForTimeout(500);
log(await attr() === null, 'switching it off returns to light', String(await attr()));

log(errs.filter(e => !/favicon|speechSynthesis/i.test(e)).length === 0, 'no page errors', errs.slice(0,2).join(' | '));

await browser.close();
console.log('\n' + (problems.length ? `${problems.length} PROBLEM(S)` : 'all theme checks passed'));
process.exit(problems.length ? 1 : 0);
