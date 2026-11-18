// Run both static releases in the same foreground Chrome tab. Each trial loads
// a fresh, isolated local save at the same camera pose and room-clock time.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash, randomBytes} from 'node:crypto';
import {mkdtemp, mkdir, writeFile, stat} from 'node:fs/promises';
import {resolve} from 'node:path';
import {chromium} from 'playwright';

const reference=process.argv[2];
if(!reference)throw Error('Pass the saved pre-grove dist/coop directory as the reference.');
const scratch=await mkdtemp(resolve('.cache/grove-check-'));
const servers=[];
const result={date:new Date().toISOString(),pose:[-0.8,-70.5],runs:[]};
let browser;
try{
  for(const [label,dir,port] of [['before',reference,4240],['after','dist/coop',4242]]){
    await stat(resolve(dir,'index.wasm'));
    const saves=resolve(scratch,label);
    await mkdir(saves);
    const processHandle=spawn(process.execPath,['scripts/coop-serve.mjs'],{env:{...process.env,COOP_SITE_DIR:dir,COOP_PORT:String(port),COOP_ROOM_PORT:String(port+1),COOP_SAVE_DIR:saves},stdio:['ignore','pipe','pipe']});
    servers.push(processHandle);
    await new Promise((ok,fail)=>{
      const t=setTimeout(()=>fail(Error('QA room service timed out')),15000);
      processHandle.stdout.on('data',chunk=>{if(String(chunk).includes(saves)){clearTimeout(t);ok();}});
      processHandle.once('exit',code=>{clearTimeout(t);fail(Error('QA room service stopped '+code));});
      processHandle.stderr.on('data',chunk=>process.stderr.write(chunk));
    });
  }
  browser=await chromium.launch({channel:'chrome',headless:false,args:['--window-size=1320,840']});
  result.chrome=browser.version();
  const context=await browser.newContext({viewport:{width:1280,height:720},deviceScaleFactor:1});
  const token=randomBytes(16).toString('hex');
  await context.addInitScript(t=>sessionStorage.setItem('cooper-identity',t),token);
  const page=await context.newPage();
  const cdp=await context.newCDPSession(page);
  for(const [weather,clock] of [['clear',0],['rain',90]]){
    for(const [label,port] of [['before',4240],['after',4242]]){
      const room='trial-'+weather;
      const id=createHash('sha256').update(room+':'+token).digest('hex').slice(0,16);
      const save={version:1,elapsed:clock,groveStartedAt:0,quest:{wood:false,tarp:false,repaired:false},homes:{[id]:{x:-0.8,z:-70.5,yaw:-.08}}};
      await writeFile(resolve(scratch,label,room+'.json'),JSON.stringify(save));
      await cdp.send('Network.clearBrowserCache');
      await page.goto('http://localhost:'+port+'/coop/?room='+room,{waitUntil:'domcontentloaded'});
      await page.bringToFront();
      await page.waitForFunction(()=>window.CooperStatus?.ready && document.getElementById('loader').hidden);
      await page.waitForFunction(()=>CooperStatus.resident>=2);
      const pose=await page.evaluate(()=>({x:CooperStatus.x,z:CooperStatus.z,yaw:CooperStatus.yaw}));
      assert.ok(Math.abs(pose.x+.8)<.03 && Math.abs(pose.z+70.5)<.03);
      await page.waitForTimeout(500);
      // Lock using a click in the scenery, outside all interactive HUD panels.
      await page.mouse.click(815,325);
      await page.waitForFunction(()=>!!document.pointerLockElement,null,{timeout:5000});
      await page.waitForTimeout(800);
      const metrics=await page.evaluate(()=>new Promise(resolve=>{
        const start=performance.now(),intervals=[];
        let prev;
        function frame(t){
          if(prev!==undefined)intervals.push(t-prev);
          prev=t;
          if(t-start<8000){requestAnimationFrame(frame);return;}
          const sorted=[...intervals].sort((a,b)=>a-b);
          const gl=document.querySelector('canvas').getContext('webgl2'), ext=gl.getExtension('WEBGL_debug_renderer_info');
          resolve({frames:intervals.length,fps:1000*intervals.length/intervals.reduce((a,b)=>a+b,0),p95Ms:sorted[Math.ceil(sorted.length*.95)-1],buffer:[gl.drawingBufferWidth,gl.drawingBufferHeight],renderer:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER),yaw:CooperStatus.yaw,pitch:CooperStatus.pitch,rain:CooperStatus.rain,elapsed:CooperStatus.elapsed,grove:CooperStatus.grove,groveElapsed:CooperStatus.groveElapsed});
        }
        requestAnimationFrame(frame);
      }));
      assert.equal(metrics.rain,weather==='clear'?0:1);
      assert.ok(Math.abs(metrics.yaw+.08)<.01 && Math.abs(metrics.pitch-.10)<.01,'camera changed');
      if(label==='after')assert.ok(metrics.grove?.length,'Rendered grove telemetry missing');
      await page.screenshot({path:'evidence/grove-'+label+'-'+weather+'.png'});
      result.runs.push({label,weather,...metrics});
      console.log(label,weather,metrics.fps.toFixed(1),metrics.p95Ms.toFixed(2),metrics.groveElapsed);
      await page.keyboard.press('Escape');
    }
  }
  const room='trial-cycle', url='http://localhost:4242/coop/?room='+room;
  const actor=createHash('sha256').update(room+':'+token).digest('hex').slice(0,16);
  await writeFile(resolve(scratch,'after',room+'.json'),JSON.stringify({
    version:1,elapsed:0,groveStartedAt:0,quest:{wood:false,tarp:false,repaired:false},
    homes:{[actor]:{x:4.45,z:-75.7,yaw:-.08}}
  }));
  await page.goto(url,{waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>window.CooperStatus?.ready && document.querySelector('#loader').hidden &&
    Math.abs(CooperStatus.x-4.45)<.03 && Math.abs(CooperStatus.z+75.7)<.03);
  // Leave the mouse free for unattended growth photos. Desktop focus changes
  // must not rotate this camera or change the HUD between captures.
  await page.waitForTimeout(600);
  result.cycle=[];
  for(const [stage,seconds] of [['sapling',0],['young',19],['mature',48]]){
    await page.waitForFunction(([stage,seconds])=>CooperStatus.groveElapsed>=seconds &&
      CooperStatus.grove.some(t=>t.id==='camp-sapling' && t.stage===stage),[stage,seconds],{timeout:50000});
    const photo=await page.evaluate(()=>({time:CooperStatus.groveElapsed,tree:CooperStatus.grove.find(t=>t.id==='camp-sapling'),
      pose:[CooperStatus.x,CooperStatus.z,CooperStatus.yaw,CooperStatus.pitch],locked:CooperStatus.locked}));
    assert.ok(!photo.locked && Math.abs(photo.pose[2]+.08)<.001 && Math.abs(photo.pose[3]-.1)<.001);
    result.cycle.push(photo);
    await page.screenshot({path:'evidence/grove-cycle-'+stage+'.png'});
  }
  const guest=await browser.newContext({viewport:{width:1280,height:720}});
  const friend=await guest.newPage();
  await friend.goto(url);
  await friend.waitForFunction(()=>window.CooperStatus?.members===2 && CooperStatus.grove.some(t=>t.id==='camp-sapling'&&t.stage==='mature'));
  result.lateJoin=await friend.evaluate(()=>({members:CooperStatus.members,time:CooperStatus.groveElapsed,tree:CooperStatus.grove.find(t=>t.id==='camp-sapling')}));
  await writeFile('evidence/grove-comparison.json',JSON.stringify(result,null,2)+'\n');
}finally{
  if(browser)await browser.close();
  for(const child of servers)child.kill('SIGTERM');
}
