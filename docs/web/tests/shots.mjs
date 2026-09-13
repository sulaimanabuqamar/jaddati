// Screenshots of the app as it is now, for the poster.
//
// Taken against the local build rather than the live site, because the live
// site is whatever was last pushed and the poster should show what is being
// demonstrated. Seeded straight into storage so no network is touched and
// nothing depends on a voice that may have been swept.

import pw from 'playwright';
import { go } from './paths.mjs';

const URL_ = 'http://localhost:8899/index.html';
const OUT = process.env.SHOTS_OUT || './shots';

const PERSON_ID = 'p-teta';
const seed = {
  people: [{
    id: PERSON_ID,
    name: 'جدّتي نورة',
    fullName: 'Noura Al Qubaisi',
    relationship: 'Grandmother',
    voiceId: '21m00Tcm4TlvDq8ikWAM',
    voiceCreatedAt: new Date(Date.now() - 86400000).toISOString(),
    consentConfirmedAt: new Date(Date.now() - 86400000).toISOString(),
    photoFilename: null,
    cloudKey: null,
  }],
  assets: [
    { id: 'a1', personId: PERSON_ID, source: 'original', filename: 'demo-1.mp3',
      text: 'A recording from the kitchen, 2019', durationSeconds: 94, isSaved: true,
      createdAt: new Date(Date.now() - 86400000).toISOString(), demo: true },
    { id: 'a2', personId: PERSON_ID, source: 'generated', filename: 'demo-2.mp3',
      text: 'Take your time. There is no right pace for any of this.',
      durationSeconds: 6, isSaved: true, intent: 'comfort', content: 'wordsSuppliedByYou',
      createdAt: new Date().toISOString(), demo: true },
  ],
  notes: [
    { id: 'n1', personId: PERSON_ID, text: 'She always said the bread had to rest before you cut it.',
      addedBy: 'Sulaiman', createdAt: new Date().toISOString() },
  ],
  books: [],
  letters: [
    { id: 'l1', personId: PERSON_ID, text: 'For the day you finish.', occasion: 'Graduation',
      deliverAt: new Date(Date.now() + 86400000 * 200).toISOString(),
      createdAt: new Date().toISOString() },
  ],
};

const shot = async (page, name) => {
  await page.waitForTimeout(700);
  await page.screenshot({ path: `${OUT}/${name}.png` });
  console.log('  ' + name + '.png');
};

const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });

for (const [mode, arabic] of [['light', false], ['dark', false], ['light', true]]) {
  const tag = arabic ? 'ar' : mode;
  console.log(`${mode}${arabic ? ' · arabic' : ''}`);

  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 3,            // the poster prints, so give it the pixels
  });
  const page = await ctx.newPage();
  // No network at all: anything not seeded simply is not drawn.
  await page.route('**/*', route =>
    route.request().url().startsWith('http://localhost:8899')
      ? route.continue()
      : route.abort());

  await page.addInitScript(([seed, mode, arabic]) => {
    localStorage.setItem('jaddati.library', JSON.stringify(seed));
    localStorage.setItem('jaddati.appearance', mode);
    if (arabic) localStorage.setItem('jaddati.language', 'ar');
  }, [seed, mode, arabic]);

  await page.goto(URL_, { waitUntil: 'networkidle' });
  await page.waitForTimeout(900);

  // The consent terms are derived from the live hostnames, so they cannot be
  // seeded — answer the gate the way a person does.
  if (await page.locator('.btn-primary').count()) {
    await page.click('.btn-primary >> nth=0');
    await page.waitForTimeout(800);
  }
  await page.waitForSelector('.tabrail', { timeout: 15000 });

  await go.people(page);
  await shot(page, `${tag}-1-home`);

  await page.click('.person-card, .bigcard, .feature-row').catch(() => {});
  await shot(page, `${tag}-2-person`);

  // the primary action: Say something
  await page.click('.primary-action .btn-primary').catch(() => {});
  await page.waitForTimeout(500);
  await page.fill('.screen textarea', arabic
    ? 'خذ وقتك. لا توجد سرعة صحيحة لأي من هذا.'
    : 'Take your time. There is no right pace for any of this.').catch(() => {});
  await shot(page, `${tag}-3-compose`);

  await ctx.close();
}

await browser.close();
console.log('\ndone');
