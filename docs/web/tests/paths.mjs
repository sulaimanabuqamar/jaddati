// Where things live after the navigation rebuild.
//
// The suites below were written against a shape where everything hung off the
// person screen. Keeping those paths in one file means the next change to the
// app's shape is one edit here rather than nine across the tests — and it
// keeps each suite's ASSERTIONS about behaviour untouched, which is the part
// that was worth having.

export const go = {
  async people(page) { await page.click('.tabrail button >> nth=0'); await page.waitForTimeout(400); },
  async letters(page) { await page.click('.tabrail button >> nth=1'); await page.waitForTimeout(400); },
  async you(page) { await page.click('.tabrail button >> nth=2'); await page.waitForTimeout(400); },

  async privacy(page) {
    await go.you(page);
    await page.click('.feature-row:has-text("Privacy and data")');
    await page.waitForTimeout(450);
  },
  async keys(page) {
    await go.you(page);
    await page.click('.feature-row:has-text("Voice service")');
    await page.waitForTimeout(450);
  },

  /** The gear on the person screen: everything you do once. */
  async setup(page) { await page.click('.setup-btn'); await page.waitForTimeout(450); },

  /** One of the three doors under the primary button. */
  async card(page, name) { await page.click(`.bigcard:has-text("${name}")`); await page.waitForTimeout(550); },

  /** The primary button, whatever it currently says. */
  async act(page) { await page.click('.primary-action .btn-primary'); await page.waitForTimeout(550); },

  /** A different way of asking, from inside the compose screen. */
  async way(page, label) { await page.click(`.chip:has-text("${label}")`); await page.waitForTimeout(550); },

  /// The globe asks before it switches, so this is two taps now.
  async switchLanguage(page) {
    await page.click('.iconbtn:has(.globe)');
    await page.waitForTimeout(350);
    await page.click('.dialog .btn-primary');
    await page.waitForTimeout(650);
  },

  async back(page) { await page.click('.appbar button >> nth=0'); await page.waitForTimeout(450); },
};
