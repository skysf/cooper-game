import {chromium} from 'playwright';
import {mkdir,writeFile} from 'node:fs/promises';
import {strict as assert} from 'node:assert';
import {browserTestOptions, prepareOffscreenPage} from './coop-browser-controls.mjs';
const out=process.env.WOOD_TEST_OUT||'evidence', base='http://localhost:'+(process.env.PORT||4173);
const mode=process.argv[2]||process.env.WOOD_TEST||'bench';
const editions=(process.env.EDITIONS||'a,b').split(',');
await mkdir(out,{recursive:true});
const browser=await chromium.launch(browserTestOptions());
try{
  const context=await browser.newContext({viewport:{width:1280,height:720},deviceScaleFactor:1});
  const page=await context.newPage();page.setDefaultTimeout(45000);
  const devtools=await prepareOffscreenPage(page);
  let edition;
  page.on('pageerror',e=>console.error(edition,'page error',e.message));
  page.on('console',m=>{if(m.type()==='error'||m.type()==='warning')console.error(edition,m.type(),m.text().slice(0,500));});
  for(edition of editions){
  async function go(query=''){
   await page.goto(base+'/'+edition+'/'+query,{waitUntil:'domcontentloaded'});
   await page.waitForFunction(()=>window.Wood?.readyMs||window.Wood?.error);
   const d=await page.evaluate(()=>({ready:Wood.readyMs,gpu:Wood.gpu,error:Wood.error}));
   if(d.error)throw Error(d.error);
   assert.equal(d.gpu.width,1280);assert.equal(d.gpu.height,720);
   console.log(edition,query,d);
  }
  if(mode==='bench'){
   // Reuse the same offscreen browser process and page for both engines.
   await page.goto('about:blank');
   await devtools.send('Network.clearBrowserCache');
   await devtools.send('Storage.clearDataForOrigin',{origin:base,storageTypes:'all'});
   const idleHz=await page.evaluate(()=>new Promise(resolve=>{
    let count=0;const t=performance.now();function sample(){count++;const d=performance.now()-t;if(d<2000)requestAnimationFrame(sample);else resolve(1000*count/d);}requestAnimationFrame(sample);
   }));
   for(const cache of ['cold','warm']){
    await go('?bench=1');
    await page.evaluate(()=>{window.woodRafCount=0;window.woodRafStart=performance.now();function tick(){window.woodRafCount++;if(!Wood.report)requestAnimationFrame(tick);else window.woodRafEnd=performance.now();}requestAnimationFrame(tick);});
    await page.waitForFunction(()=>!!Wood.report,null,{timeout:80000,polling:500});
    const result=await page.evaluate(()=>({...Wood.report,measuredRafHz:1000*window.woodRafCount/((window.woodRafEnd||performance.now())-window.woodRafStart),finalPose:{...Wood.state}}));
    result.blankTabRafHz=idleHz;
    assert.equal(result.hiddenDuringTest,false,'tab was backgrounded');
    assert.ok(result.rain.frames>0 && result.clear.frames>0);
    await writeFile(out+'/'+edition+'-'+cache+'.json',JSON.stringify({...result,cache,headed:false,timingEligible:false,
      browserVersion:browser.version(),recordedAt:new Date().toISOString()},null,2));
    console.log(edition,cache,result.clear,result.rain);
   }
  } else {
   for(const condition of ['clear','rain','storm']){
    await go('?view='+(condition==='clear'?'clear':'rain')+(condition==='storm'?'&profile=storm':''));
    await page.waitForTimeout(600);
    await page.locator('canvas').screenshot({path:out+'/'+edition+'-'+condition+'.png'});
   }
   await go();
   await page.locator('#enter').click();
   await page.waitForFunction(()=>document.pointerLockElement===document.querySelector('canvas'));
   const state=()=>page.evaluate(()=>({...Wood.state}));
   const initial=await state();await page.keyboard.down('w');await page.waitForTimeout(500);await page.keyboard.up('w');
   const walked=await state();assert.ok(Math.hypot(initial.x-walked.x,initial.z-walked.z)>.2);
   await page.evaluate(()=>document.dispatchEvent(new MouseEvent('mousemove',{movementX:70,movementY:5,bubbles:true})));
   const looked=await state();assert.ok(looked.yaw!==walked.yaw||looked.pitch!==walked.pitch);
   await page.keyboard.press('r');await page.waitForFunction(()=>Wood.state.wet>.99);
   await page.keyboard.press('r');await page.waitForFunction(()=>Wood.state.wet<.01);
   // Stage just outside one rock, then drive through the normal WASD handler.
   const rock=await page.evaluate(()=>{
     const r=Wood.scene.obstacles.filter(o=>o.type==='rock').find(o=>Wood.scene.obstacles.every(n=>n===o||Math.hypot(o.x-n.x,o.z+o.r+1-n.z)>n.r+.6));if(!r)throw Error('missing isolated rock');
     Object.assign(Wood.state,{x:r.x,z:r.z+r.r+1,yaw:0,pitch:0});return r;
   });
   await page.keyboard.down('w');await page.waitForTimeout(1500);await page.keyboard.up('w');const blocked=await state();
   assert.ok(Math.abs(Math.hypot(blocked.x-rock.x,blocked.z-rock.z)-rock.r-.29)<.13);
   assert.equal(blocked.y,1.67);assert.equal(walked.y,1.67);
   await page.keyboard.press('Escape');await page.waitForTimeout(200);
   const esc=await page.evaluate(()=>!document.pointerLockElement);
   assert.ok(esc,'Esc did not release the pointer');
   const info={edition,headless:true,renderer:await page.evaluate(()=>Wood.gpu),initial,walked,looked,blocked,rock,esc,weatherCycle:true,profiles:['base','storm']};
   await writeFile(out+'/'+edition+'-controls.json',JSON.stringify(info,null,2));
   console.log(edition,'controls',esc?'Esc passed':'Esc needs physical keyboard');
  }
  }
  await context.close();
}finally{await browser.close();}
