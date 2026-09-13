// Language should never change by accident, and You should read in the order
// it was asked for.

import pw from 'playwright';
import { go } from './paths.mjs';

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
page.on('pageerror', e => errs.push(e.message));

const dir = () => page.evaluate(() => document.documentElement.dir);

await page.goto(URL, { waitUntil: 'networkidle' });
await page.waitForTimeout(500);

// ── 1. the globe asks ──────────────────────────────────────────────────
log(await dir() === 'ltr', 'starts in English', await dir());
await page.click('.iconbtn:has(.globe)');
await page.waitForTimeout(400);
log(await page.locator('.dialog').isVisible(), 'the globe opens a dialog rather than switching');
log(await dir() === 'ltr', 'and nothing has changed yet', await dir());
log(await page.locator('.dialog').innerText().then(t => /العربية/.test(t)),
  'the dialog names the language you would get');

await page.click('.dialog button:has-text("Cancel")');
await page.waitForTimeout(400);
log(await dir() === 'ltr', 'cancelling leaves the language alone', await dir());

await page.click('.iconbtn:has(.globe)'); await page.waitForTimeout(350);
await page.click('.dialog button:has-text("العربية")');
await page.waitForTimeout(600);
log(await dir() === 'rtl', 'confirming switches it', await dir());

// back to English the same way
await page.click('.iconbtn:has(.globe)'); await page.waitForTimeout(350);
await page.click('.dialog button:has-text("English")');
await page.waitForTimeout(600);
log(await dir() === 'ltr', 'and back again', await dir());

// ── 2. You: order, and Language as a screen ────────────────────────────
await page.click('text=Allow these three things'); await page.waitForTimeout(400);
await go.you(page);

const order = await page.evaluate(() =>
  [...document.querySelectorAll('.scroll .feature-row__title')].map(e => e.textContent));
log(order[0] === 'Language', 'Language is first', order.join(' | '));
log(order[1] === 'Privacy and data', 'then Privacy and data', order.join(' | '));
log(order[2] === 'Dark mode', 'then Dark mode, below Privacy', order.join(' | '));

await page.click('.feature-row:has-text("Language")');
await page.waitForTimeout(500);
const body = await page.locator('.screen').innerText();
log(/English/.test(body) && /العربية/.test(body), 'the Language screen lists both');
log(await page.locator('[aria-current="true"]').count() === 1, 'and marks the one in use');
log(await page.locator('.appbar .globe').count() === 0, 'no globe on the screen that IS the globe');
await page.screenshot({ path: '/home/claude/web/st-language.png' });

// picking from the list does not ask again — being here is the deliberate act
await page.click('.feature-row:has-text("العربية")');
await page.waitForTimeout(600);
log(await page.locator('.dialog').count() === 0, 'choosing from the list does not ask again');
log(await dir() === 'rtl', 'and it switches', await dir());
log(await page.locator('[aria-current="true"]').count() === 1, 'the mark moves to the new one');

await page.click('.feature-row:has-text("English")'); await page.waitForTimeout(600);
log(await dir() === 'ltr', 'and back');

await go.back(page);
log(await page.locator('.scroll .feature-row__title').first().isVisible(), 'back returns to You');

log(errs.filter(e => !/favicon|speechSynthesis/i.test(e)).length === 0, 'no page errors', errs.slice(0,2).join(' | '));

await browser.close();
console.log('\n' + (problems.length ? `${problems.length} PROBLEM(S)` : 'all settings checks passed'));
process.exit(problems.length ? 1 : 0);
