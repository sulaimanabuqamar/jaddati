// The new screens in Arabic, and at the narrowest phone width.
//
// Arabic is the interface, not a translation — that is a claim on the poster,
// so a new screen that only lays out in English breaks a promise the project
// makes about itself.
import pw from 'playwright';
import { go } from './paths.mjs';
const problems=[]; const log=(ok,w,x='')=>{console.log(`${ok?'PASS':'FAIL'}  ${w}${x?'  — '+x:''}`); if(!ok)problems.push(w);};
const wav = n => { const d=8000*n,b=Buffer.alloc(44+d); b.write('RIFF',0);b.writeUInt32LE(36+d,4);b.write('WAVE',8);b.write('fmt ',12);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(8000,24);b.writeUInt32LE(8000,28);b.writeUInt16LE(1,32);b.writeUInt16LE(8,34);b.write('data',36);b.writeUInt32LE(d,40); return b; };
const browser = await pw.chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });

async function run(width, arabic) {
  const ctx = await browser.newContext({ viewport:{width,height:844}, permissions:['microphone'] });
  const page = await ctx.newPage();
  const errs=[]; page.on('pageerror',e=>errs.push(e.message));
  await page.route('**/jaddati-proxy.sulaimanabuqamar.workers.dev/**', r => {
    const u=r.request().url();
    if (u.includes('/v1/text-to-speech/')) return r.fulfill({status:200,contentType:'audio/mpeg',body:Buffer.alloc(4096,2)});
    if (u.includes('/chat/completions')) return r.fulfill({status:200,contentType:'application/json',body:JSON.stringify({choices:[{message:{content:'إجابة.'},finish_reason:'stop'}]})});
    return r.fulfill({status:200,contentType:'application/json',body:'{"voice_id":"v1"}'});
  });
  await page.goto('http://localhost:8899/index.html',{waitUntil:'networkidle'});
  await page.waitForTimeout(500);
  if (arabic) { await go.switchLanguage(page); }
  await page.click(arabic ? 'text=اسمح بهذه الأمور الثلاثة' : 'text=Allow these three things').catch(async () => {
    await page.click('button.btn-primary'); });
  await page.waitForTimeout(500);

  await page.evaluate(async () => {
    const m = await import('./core.js?v=' + document.documentElement.dataset.v);
    const p = m.store.addPerson({ name:'تيتا', relationship:'جدتي' });
    m.store.updatePerson({ ...p, voiceId:'v1' });
    m.store.addNote({ personId:p.id, text:'كانت تطبخ المقلوبة كل جمعة.' });
    m.store.addLetter({ personId:p.id, text:'كل عام وأنت بخير يا حبيبتي.', occasion:'عيد ميلادها',
                        deliverAt:new Date(Date.now()+9e9).toISOString() });
  });
  await page.waitForTimeout(600);
  await page.click('.person-card'); await page.waitForTimeout(500);

  const tag = `${width}px ${arabic?'AR':'EN'}`;
  const dir = await page.evaluate(() => document.documentElement.dir);
  log(dir === (arabic?'rtl':'ltr'), `${tag}: direction is right`, dir);

  // Each screen is reached the way the rebuilt app reaches it, and the third
  // value is how deep it sits so the loop can walk back out to the person.
  const screens = [
    ['ask', async () => { await go.act(page); await go.way(page, arabic?'اسأل عنه':'Ask about them'); }, 1],
    ['language', async () => { await go.act(page); await go.way(page, arabic?'قلها بلغته':'Say it in their language'); }, 1],
    // By position, so the suite does not depend on the card's translation.
    ['letters', async () => { await page.click('.bigcard >> nth=2'); await page.waitForTimeout(550); }, 1],
    ['capture', async () => { await go.setup(page);
      await page.click(`.feature-row:has-text("${arabic?'سُجّل قبل الحاجة إليه':'Recorded before it is needed'}")`);
      await page.waitForTimeout(500); }, 2],
  ];
  for (const [name, open, depth] of screens) {
    await open();
    const overflow = await page.evaluate(() => {
      const el = document.scrollingElement || document.documentElement;
      let worst = el.scrollWidth - el.clientWidth;
      // Content inside a container that scrolls sideways ON PURPOSE is
      // reachable, not lost, so it is not overflow. The page-level measure
      // above still catches anything that actually breaks the layout.
      const inScroller = n => {
        for (let a = n.parentElement; a; a = a.parentElement) {
          if (a.classList.contains('screen')) return false;
          const ox = getComputedStyle(a).overflowX;
          if (ox === 'auto' || ox === 'scroll') return true;
        }
        return false;
      };
      for (const n of document.querySelectorAll('.screen *')) {
        if (inScroller(n)) continue;
        const r = n.getBoundingClientRect();
        if (r.width > 0) worst = Math.max(worst, Math.ceil(r.right - window.innerWidth), Math.ceil(-r.left));
      }
      return worst;
    });
    // A sideways strip only counts as reachable if it really does scroll.
    const stripOK = await page.evaluate(() => {
      const s = document.querySelector('.chiprow');
      if (!s) return true;
      const ox = getComputedStyle(s).overflowX;
      return (ox === 'auto' || ox === 'scroll') && s.scrollWidth >= s.clientWidth;
    });
    log(stripOK, `${tag}: ${name} sideways strip is scrollable, not clipped`);
    log(overflow <= 1, `${tag}: ${name} fits the screen`, String(overflow));
    const tiny = await page.evaluate(() =>
      [...document.querySelectorAll('.screen button')]
        .filter(b => { const r=b.getBoundingClientRect(); return r.height>0 && r.height<40; }).length);
    log(tiny === 0, `${tag}: ${name} has no button under 40px tall`, String(tiny));
    for (let i = 0; i < depth; i++) {
      await page.click('.appbar button >> nth=0').catch(()=>{});
      await page.waitForTimeout(400);
    }
  }
  log(errs.filter(e=>!/favicon|speechSynthesis|not-allowed/i.test(e)).length===0, `${tag}: no page errors`, errs.slice(0,2).join(' | '));
  await ctx.close();
}

await run(390, false);
await run(390, true);
await run(320, true);
await browser.close();
console.log('\n'+(problems.length?`${problems.length} PROBLEM(S)`:'all layout checks passed'));
process.exit(problems.length?1:0);
