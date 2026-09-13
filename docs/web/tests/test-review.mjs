// The rest of the review's findings, pinned.
import pw from 'playwright';
import { go } from './paths.mjs';
const problems = [];
const log = (ok,w,x='') => { console.log(`${ok?'PASS':'FAIL'}  ${w}${x?'  — '+x:''}`); if(!ok) problems.push(w); };
const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const ctx = await browser.newContext({ viewport:{width:390,height:844}, permissions:['microphone'] });
const page = await ctx.newPage();
const errs=[]; page.on('pageerror',e=>errs.push(e.message));
await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', r => {
  const u = r.request().url();
  if (u.includes('/chat/completions'))
    return r.fulfill({status:200,contentType:'application/json',body:JSON.stringify({choices:[{message:{content:'NOT IN NOTES'}}]})});
  return r.fulfill({status:200,contentType:'application/json',body:'{"voice_id":"v"}'});
});
await page.goto('http://localhost:8899/index.html',{waitUntil:'networkidle'});
await page.waitForTimeout(500);
await page.click('text=Allow these three things'); await page.waitForTimeout(400);
await page.click('text=Add someone'); await page.waitForTimeout(300);
await page.fill('.sheet input >> nth=0','Teta'); await page.fill('.sheet input >> nth=1','Grandmother');
await page.click('.sheet button:has-text("Add person")'); await page.waitForTimeout(400);
await page.click('.person-card'); await page.waitForTimeout(400);

// The experience list is gated on having a voice, and so is "Ask about them",
// so anyone who can see the refusal can also reach the screen it points at.
await page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.people[0];
  m.store.updatePerson({ ...p, voiceId: 'v', voiceCreatedAt: new Date().toISOString() });
});
await page.waitForTimeout(600);

// ── a memory can actually be written down ──────────────────────────────
await go.act(page); await go.way(page, 'Words & memories');
await page.fill('textarea','She made maqluba every Friday.'); await page.waitForTimeout(300);
log(await page.locator('button:has-text("Keep this as a memory")').isVisible(), 'the app offers a way to write a memory down');
await page.click('button:has-text("Keep this as a memory")'); await page.waitForTimeout(700);
const mem = await page.evaluate(async () => (await import('./core.js?v=' + document.documentElement.dataset.v)).store.memories((await import('./core.js?v=' + document.documentElement.dataset.v)).store.people[0].id).length);
log(mem === 1, 'and it is stored as a memory, not a comfort line', String(mem));
log(await page.locator('text=What your family has written down').isVisible(), 'the memories are listed where they are written');

// ── the refusal does not fail open on "NOT IN NOTES" ───────────────────
const said = await page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.people[0];
  try { return 'ANSWER: ' + await m.FamilyAnswer.answer('What did she cook?', m.store.memories(p.id)); }
  catch (e) { return e.name; }
});
log(said === 'NotInNotesError', 'a sentinel without underscores still refuses', said);

// ── the full question is asked ─────────────────────────────────────────
let asked = '';
await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/chat/completions', r => {
  asked = JSON.parse(r.request().postData()||'{}').messages?.[1]?.content || '';
  return r.fulfill({status:200,contentType:'application/json',body:JSON.stringify({choices:[{message:{content:'An answer.'}}]})});
});
const long = 'Q'.repeat(600);
await page.evaluate(async q => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  try { await m.FamilyAnswer.answer(q, m.store.memories(m.store.people[0].id)); } catch {}
}, long);
log(asked.length === 600, 'a 600-character question is asked in full, not cut to 300', String(asked.length));

// ── deleting a person takes their letters ──────────────────────────────
const after = await page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.people[0];
  m.store.addLetter({ personId: p.id, text: 'Sealed.', occasion: 'x',
                      deliverAt: new Date(Date.now()+9e8).toISOString() });
  await m.store.deletePerson(p);
  return m.store.letters.length;
});
log(after === 0, 'deleting a person takes their sealed letters with them', String(after));

// ── a shared voice is not deleted from the service ─────────────────────
const shared = await page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const file = { jaddati:1, person:{ name:'Jiddo', voiceId:'SHARED' }, notes:[], letters:[], recordings:[] };
  const r = await m.Archive.import(JSON.stringify(file));
  return { shared: r.person.voiceIsShared === true, voiceId: r.person.voiceId };
});
log(shared.shared, 'an imported person marks the voice as shared', JSON.stringify(shared));

// ── a malformed archive does not blank the app ─────────────────────────
const junk = await page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const file = { jaddati:1, person:{ name:'Broken', voiceId:{evil:1} },
                 notes:'not-an-array', letters:[{occasion:'no text'},{text:'ok',deliverAt:'nonsense'}],
                 recordings:'nope' };
  const r = await m.Archive.import(JSON.stringify(file));
  return { notes: r.notes, letters: r.letters, voiceId: m.store.people.slice(-1)[0].voiceId };
});
log(junk.notes === 0, 'a string where notes should be imports no junk notes', String(junk.notes));
log(junk.letters === 0, 'letters with no words or no date are dropped', String(junk.letters));
log(junk.voiceId === null, 'a non-string voice id is refused, not put in a URL', JSON.stringify(junk.voiceId));
await page.waitForTimeout(600);
const alive = await page.locator('.tabrail').isVisible().catch(()=>false);
log(alive, 'and the app is still on screen');

const real = errs.filter(e=>!/favicon|speechSynthesis|not-allowed/i.test(e));
log(real.length===0,'no page errors',real.slice(0,2).join(' | '));
await browser.close();
console.log('\n'+(problems.length?`${problems.length} PROBLEM(S)`:'all review-fix checks passed'));
process.exit(problems.length?1:0);
