import pw from 'playwright';
import { go } from './paths.mjs';
const problems = [];
const log = (ok, w, x='') => { console.log(`${ok?'PASS':'FAIL'}  ${w}${x?'  — '+x:''}`); if(!ok) problems.push(w); };
const wav = n => { const d=8000*n,b=Buffer.alloc(44+d); b.write('RIFF',0);b.writeUInt32LE(36+d,4);b.write('WAVE',8);b.write('fmt ',12);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(8000,24);b.writeUInt32LE(8000,28);b.writeUInt16LE(1,32);b.writeUInt16LE(8,34);b.write('data',36);b.writeUInt32LE(d,40); return b; };
const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const ctx = await browser.newContext({ viewport:{width:390,height:844}, permissions:['microphone'] });
const page = await ctx.newPage();
const errs=[]; page.on('pageerror',e=>errs.push(e.message));
page.on('console',m=>{if(m.type()==='error')errs.push(m.text()+' @ '+(m.location()?.url||'?'));});
await page.route('**/workers.dev/**', r => r.fulfill({status:200,contentType:'application/json',body:'{"voice_id":"v"}'}));
await page.goto('http://localhost:8899/index.html',{waitUntil:'networkidle'});
await page.waitForTimeout(500);
await page.click('text=Allow these three things'); await page.waitForTimeout(400);
await page.click('text=Add someone'); await page.waitForTimeout(300);
await page.fill('.sheet input >> nth=0','Teta'); await page.fill('.sheet input >> nth=1','Grandmother');
await page.click('.sheet button:has-text("Add person")'); await page.waitForTimeout(400);
await page.click('.person-card'); await page.waitForTimeout(400);

// With no voice yet, capture is the one alternative offered beside the
// primary button — which is exactly when it matters most.
log(await page.locator('.primary-action__aside').isVisible(), 'the person screen offers capture');
await page.click('.primary-action__aside'); await page.waitForTimeout(500);
log(await page.locator('text=While they are').isVisible(), 'the capture screen opens');
log(await page.locator('text=Say the name of everyone').isVisible(), 'it asks for specific things, not "a voice sample"');
const prompts = await page.locator('button:has-text("Record this")').count();
log(prompts === 6, 'six prompts, each recordable', String(prompts));
log(await page.locator('text=Nothing here is sent anywhere').isVisible(), 'and says plainly that nothing leaves the phone');

// It works with no voice at all — which is the point: this is for before.
const noVoice = await page.evaluate(async () => (await import('./core.js?v=' + document.documentElement.dataset.v)).store.people[0].voiceId);
log(!noVoice, 'available before any voice exists', String(noVoice));

// Saving one marks it as answered.
await page.evaluate(async () => {
  const m = await import('./core.js?v=' + document.documentElement.dataset.v);
  const p = m.store.people[0];
  await m.store.storeAudio(new Blob([new Uint8Array(2048)],{type:'audio/webm'}), {
    personId: p.id, source:'original', text:'x', duration: 30, isSaved:true,
    promptId:'names', fileExtension:'webm' });
});
await page.waitForTimeout(500);
const kept = await page.evaluate(async () => (await import('./core.js?v=' + document.documentElement.dataset.v)).store.assets.filter(a=>a.promptId==='names').length);
log(kept === 1, 'the prompt it answered is remembered', String(kept));
await page.reload({waitUntil:'networkidle'}); await page.waitForTimeout(700);
const after = await page.evaluate(async () => (await import('./core.js?v=' + document.documentElement.dataset.v)).store.assets.filter(a=>a.promptId==='names').length);
log(after === 1, 'and survives a reload', String(after));

const real = errs.filter(e=>!/favicon|speechSynthesis|not-allowed/i.test(e));
log(real.length===0,'no console errors',real.slice(0,2).join(' | '));
await browser.close();
console.log('\n'+(problems.length?`${problems.length} PROBLEM(S)`:'all capture checks passed'));
process.exit(problems.length?1:0);
