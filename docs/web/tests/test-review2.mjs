// The second review's findings that apply to the web.
import pw from 'playwright';
const problems=[]; const log=(ok,w,x='')=>{console.log(`${ok?'PASS':'FAIL'}  ${w}${x?'  — '+x:''}`); if(!ok)problems.push(w);};
const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const page = await (await browser.newContext({viewport:{width:390,height:844}})).newPage();
const errs=[]; page.on('pageerror',e=>errs.push(e.message));
let reply='', finish='stop';
await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', r => {
  const u=r.request().url();
  if (u.includes('/chat/completions'))
    return r.fulfill({status:200,contentType:'application/json',
      body:JSON.stringify({choices:[{message:{content:reply},finish_reason:finish}]})});
  if (u.includes('/v1/text-to-speech/')) return r.fulfill({status:200,contentType:'audio/mpeg',body:Buffer.alloc(4096,1)});
  return r.fulfill({status:200,contentType:'application/json',body:'{"voice_id":"v"}'});
});
await page.goto('http://localhost:8899/index.html',{waitUntil:'networkidle'});
await page.waitForTimeout(500);
await page.click('text=Allow these three things'); await page.waitForTimeout(400);
await page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.addPerson({ name:'Teta', relationship:'Grandmother' });
  m.store.updatePerson({ ...p, voiceId:'v1' });
  m.store.addNote({ personId: p.id, text: 'She made maqluba on Fridays.' });
});
await page.waitForTimeout(500);

const ask = async () => page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.people[0];
  try { return 'ANSWER:' + await m.FamilyAnswer.answer('ما هو طبقها المفضل؟', m.store.memories(p.id)); }
  catch (e) { return e.name; }
});

reply = 'لا أعرف، هذا غير مذكور في الملاحظات.';
log(await ask() === 'NotInNotesError', 'a refusal written in Arabic is caught, not spoken as an answer', await ask());

reply = 'NOT IN NOTES';
log(await ask() === 'NotInNotesError', 'and one without underscores');

reply = 'كانت تطبخ المقلوبة كل جمعة، وكان البيت كله يجتمع حولها في ذلك اليوم.';
const real = await ask();
log(real.startsWith('ANSWER:'), 'a genuine Arabic answer still gets through', real.slice(0,40));

reply = 'نصف جملة مقطوعة'; finish = 'length';
const cut = await ask();
log(cut === 'CompanionError', 'a reply cut off at the ceiling is refused, not billed', cut);
finish = 'stop';

// a letter whose clip was discarded can be opened again
const again = await page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.people[0];
  const l = m.store.addLetter({ personId:p.id, text:'Happy birthday.', occasion:'Today',
                                deliverAt:new Date(Date.now()-3600000).toISOString() });
  const a = await m.store.storeAudio(new Blob([new Uint8Array(4096)],{type:'audio/mpeg'}),
    { personId:p.id, source:'generated', text:l.text, isSaved:true, fileExtension:'mp3' });
  m.store.updateLetter({ ...l, openedAt:new Date().toISOString(), assetId:a.id });
  const beforeDiscard = m.store.dueLetters(p.id).length;
  await m.store.deleteAsset(a);
  return { beforeDiscard, afterDiscard: m.store.dueLetters(p.id).length,
           opened: m.store.openedLetters(p.id).length };
});
log(again.beforeDiscard === 0, 'an opened letter with its clip intact is not offered again', JSON.stringify(again));
log(again.afterDiscard === 1, 'but a discarded clip makes it openable again — the words are not lost');
log(again.opened === 0, 'and it leaves the opened list while its clip is gone');

log(errs.filter(e=>!/favicon|speechSynthesis/i.test(e)).length===0,'no page errors',errs.slice(0,2).join(' | '));
await browser.close();
console.log('\n'+(problems.length?`${problems.length} PROBLEM(S)`:'all second-review checks passed'));
process.exit(problems.length?1:0);
