// The refusal has to be actionable where it is read.
import pw from 'playwright';
const URL_ = 'http://localhost:8899/index.html';
const problems = [];
const log = (ok, what, extra = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}${extra ? '  — ' + extra : ''}`);
  if (!ok) problems.push(what);
};
const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, permissions: ['microphone'] });
const page = await ctx.newPage();
const errs = [];
page.on('pageerror', e => errs.push('pageerror: ' + e.message));
let wentToGoogle = null;
await page.route('**/accounts.google.com/**', r => { wentToGoogle = r.request().url(); return r.abort(); });
await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', r => {
  const u = r.request().url();
  if (u.includes('/google/status'))
    return r.fulfill({ status: 200, contentType: 'application/json',
                       body: '{"configured":true,"clientId":"web.apps.googleusercontent.com"}' });
  return r.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
});
await page.goto(URL_, { waitUntil: 'networkidle' });
await page.waitForTimeout(500);
await page.click('text=Allow these three things'); await page.waitForTimeout(400);
await page.click('text=Add someone'); await page.waitForTimeout(300);
await page.fill('.sheet input >> nth=0', 'Teta');
await page.fill('.sheet input >> nth=1', 'Grandmother');
await page.click('.sheet button:has-text("Add person")'); await page.waitForTimeout(400);
await page.click('.person-card'); await page.waitForTimeout(400);
await page.click('button:has-text("Add their voice") >> nth=0'); await page.waitForTimeout(500);

const note = page.locator('.errornote:has-text("Sign in with Google to make new audio")');
log(await note.count() > 0, 'the sheet says so BEFORE a recording is chosen');
const btn = note.locator('button:has-text("Sign in with Google")');
log(await btn.count() > 0, 'and the sign-in is a button, not directions to another tab');
log(!(await page.locator('text=The button is in Backup').count()),
    'the old "go to the You tab" wording is gone from this screen');

await btn.first().click();
await page.waitForTimeout(900);
log(!!wentToGoogle, 'pressing it starts the sign-in from here', String(wentToGoogle).slice(0, 60));
log(/client_id=web\.apps/.test(wentToGoogle || ''), 'with the relay-supplied client id');

log(errs.length === 0, 'no console errors', errs.slice(0, 2).join(' | '));
await browser.close();
console.log(problems.length ? `\n${problems.length} failed:\n  ` + problems.join('\n  ') : '\nall gate checks passed');
process.exit(problems.length ? 1 : 0);
