// Drives production clients through ordinary input. Telemetry is read-only.
import { strict as assert } from 'node:assert';
import { execFileSync, spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { browserTestOptions, clickCanvasPoint, prepareOffscreenPage, stageOffscreenControls } from './coop-browser-controls.mjs';
import { installFrameCapture } from './coop-frame-capture.mjs';
import { nativeJoinArgs, resolveNativeJoin } from './native-camp-join.mjs';
import { findPath, shipClearance } from './coop-test-path.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const base = new URL(process.env.COOP_BASE || 'http://localhost:' + (process.env.COOP_PORT || 4184)).origin;
const room = 'walk-' + Date.now().toString(36);
const pageURL = base + '/coop/?room=' + room;
const native = process.platform === 'darwin' && process.env.COOP_WEB_ONLY !== '1';
const app = resolve(root, 'dist/coop-native/CooperCamp.app');
const log = resolve(root, '.cache',room+'-mac.log');
const manifest = JSON.parse(await readFile(resolve(root,'coop/world.json'),'utf8'));
const evidenceDir = resolve(root,process.env.COOP_EVIDENCE_DIR||'evidence');
const wait = ms => new Promise(done => setTimeout(done,ms));
const length = (a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1]);
const report = {room, native, headless: true, client: 'offscreen Chromium', pointerLock: 'in-page',
  webUrl: pageURL, route: [], members: {}, picked: [], zonesRequested: [], errors: []};
await mkdir(evidenceDir,{recursive:true});
await mkdir(resolve(root,'.cache'),{recursive:true});

let nativeLaunch;
let nativeClosed;
let browser;
let page;
const held = new Set();
report.pointerChanges=[];
const state = ()=>page.evaluate(()=>window.CooperStatus || {});
async function nativeStates() {
  const txt = await readFile(log+'.events','utf8').catch(()=> '');
  return txt.split('\n').filter(l=>l.startsWith('COOP_STATE ')).flatMap(l=>{
    try{return [JSON.parse(l.slice(11))];}catch{return [];}
  });
}
async function until(read, timeout=15000, what='condition'){
  const limit=Date.now()+timeout;
  while(Date.now()<limit){
    const result=await read();
    if(result)return result;
    await wait(100);
  }
  throw Error('Timed out waiting for '+what);
}
async function keyChord(keys) {
  for(const k of [...held])if(!keys.includes(k)){await page.keyboard.up(k);held.delete(k);}
  for(const k of keys)if(!held.has(k)){await page.keyboard.down(k);held.add(k);}
}
async function release(){
  await keyChord([]);
  // Observe the last authoritative snapshot after the key-up event.
  await wait(410);
}
async function walk(site) {
  const goal=manifest.sites[site];
  const deadline=Date.now()+130000;
  let stuck=0,last=[Infinity,Infinity];
  let lastPlan;
  while(Date.now()<deadline){
    let s=await state();
    if(!s.ready) s=await until(async()=>{const now=await state();return now.ready&&now;},10000,'terrain loaded');
    if(!s.locked) {
      await stageOffscreenControls(page);
      s=await state();
    }
    const here=[s.x,s.z];
    if(s.nearby===site && length(here,goal)<2.12)return s;
    if(length(here,last)<.07)stuck++;else stuck=0;
    last=here;
    if(stuck>5)throw Error('blocked at '+JSON.stringify({here,site,lastPlan}));
    const waypoints=findPath(manifest,here,goal,{margin:.62,stopDistance:.9,step:.5,ship:s.ship,feet:s.y});
    // A corner smaller than one grid cell can be the escape from contact.
    const dest=waypoints.find(p=>length(here,p)>.13)||goal;
    const clearance=Math.min(shipClearance(here,s.ship,s.y),...manifest.obstacles.map(o=>Math.hypot(here[0]-o.x,here[1]-o.z)-o.r));
    const d=length(here,dest),reach=Math.min(clearance<.8 ? .65 : 3.1,d);
    const dx=(dest[0]-here[0])*reach/d,dz=(dest[1]-here[1])*reach/d;
    // Express the world-space direction as the player's actual strafe/forward keys.
    const side=dx*Math.cos(s.yaw)-dz*Math.sin(s.yaw);
    const forward=-dx*Math.sin(s.yaw)-dz*Math.cos(s.yaw);
    const sideKey=side>=0?'d':'a', fwdKey=forward>=0?'w':'s';
    const diagonal=Math.min(Math.abs(side),Math.abs(forward));
    lastPlan={dest,here,reach,side,forward,clearance,waypoints};
    if(diagonal>.12){
      await keyChord([sideKey,fwdKey]);
      await wait(diagonal*Math.SQRT2/3.6*1000);
    }
    const straight=Math.abs(Math.abs(side)-Math.abs(forward));
    if(straight>.10 || diagonal<=.12){
      await keyChord([Math.abs(side)>Math.abs(forward)?sideKey:fwdKey]);
      await wait(Math.max(.12,straight)/3.6*1000);
    }
    await release();
  }
  throw Error('Route timeout '+site);
}
async function nearAndUse(site,key){
  const s=await walk(site);
  console.log('At',site,s.x.toFixed(2),s.z.toFixed(2),s.zone);
  report.route.push({site,zone:s.zone,x:s.x,z:s.z,resident:s.resident,elapsed:s.elapsed});
  await page.keyboard.press('e');
  await until(async()=> (await state()).quest?.[key],8000,'E '+site);
  report.picked.push(key);
  if(native)await until(async()=>(await nativeStates()).some(n=>n.quest[key]),8000,'native replicated '+key);
  await page.screenshot({path: resolve(evidenceDir,'coop-'+site+'.png')});
}

try{
  assert.ok((await fetch(base+'/coop/')).ok,'web client is unavailable');
  browser=await chromium.launch(browserTestOptions());
  const ctx=await browser.newContext({viewport:{width:1280,height:720},deviceScaleFactor:1});
  page=await ctx.newPage();
  await prepareOffscreenPage(page);
  await page.addInitScript(installFrameCapture);
  page.on('pageerror',e=>report.errors.push(e.message));
  const warnings=[];
  report.consoleWarnings=warnings;
  page.on('console',msg=>{if(msg.text().startsWith('POINTER '))report.pointerChanges.push(msg.text());if(['warning','error'].includes(msg.type())&&warnings.length<15)warnings.push(msg.text().slice(0,600));});
  await page.addInitScript(()=>{
    document.addEventListener('pointerlockerror',()=>console.warn('document pointerlockerror'));
    document.addEventListener('pointerlockchange',()=>console.log('POINTER '+Boolean(document.pointerLockElement)+' focus='+document.hasFocus()+' t='+Math.round(performance.now())));
  });

  page.on('request',r=>{if(r.url().includes('/zones/'))report.zonesRequested.push(new URL(r.url()).pathname);});
  await page.goto(pageURL,{waitUntil:'domcontentloaded'});
  let s=await until(async()=>{const x=await state();return x.ready&&x;},45000,'web first playable');
  const id=s.selfId;
  assert.equal(s.room,room);
  report.gpu=await page.evaluate(()=>{
    const gl=document.querySelector('canvas').getContext('webgl2'),ext=gl.getExtension('WEBGL_debug_renderer_info');
    return {buffer:[gl.drawingBufferWidth,gl.drawingBufferHeight],renderer:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER)};
  });
  await page.screenshot({path:resolve(evidenceDir,'coop-camp.png')});
  await page.waitForFunction(()=>document.getElementById('loader').hidden);
  await stageOffscreenControls(page);
  s=await state();
  const initialYaw=s.yaw;
  await page.evaluate(()=>window.coopBenchMove(70,5));
  const moved=await until(async()=>{const x=await state();return Math.abs(x.yaw-initialYaw)>.02&&x;},3000,'mouse look');
  report.lookDelta=moved.yaw-initialYaw;
  await page.evaluate(()=>window.coopBenchMove(-70,-5));
  if(native){
    assert.ok(existsSync(app),'missing '+app);
    const join=await resolveNativeJoin(pageURL);
    const {websocketUrl,zoneBase,inviteUrl}=join;
    report.nativeConnection={websocketUrl,zoneBase,inviteUrl};
    const executable=execFileSync('/usr/libexec/PlistBuddy',['-c','Print :CFBundleExecutable',resolve(app,'Contents/Info.plist')],{encoding:'utf8'}).trim();
    assert.ok(executable && basename(executable)===executable,'invalid Mac release executable name');
    const binary=resolve(app,'Contents/MacOS',executable);
    report.nativeLaunch='headless release executable';
    nativeLaunch=spawn(binary,['--headless','--max-fps','24','--log-file',log,'--quit-after','30000','--',
      ...nativeJoinArgs(join),'--qa-status-file='+log+'.events','--token='+randomBytes(16).toString('hex')],{stdio:'ignore'});
    nativeClosed=new Promise(done=>nativeLaunch.once('close',done));
    nativeLaunch.on('error',error=>report.errors.push(error.message));
    const ready=await until(async()=>(await nativeStates()).find(s=>s.ready),30000,'native first playable');
    assert.equal(ready.room,room);
    for(const [field,address] of Object.entries(report.nativeConnection))assert.equal(ready[field],address,field);
  }
  if(native){
    s=await until(async()=>{const x=await state();return x.members===2&&x;},10000,'two clients');
    assert.equal(s.remoteAvatars,1);report.members.web=s.members;
    const n=await until(async()=>(await nativeStates()).find(x=>x.members===2&&x.remoteAvatars===1),10000,'native avatar list');
    report.members.native=n.members;
  }
  await page.screenshot({path:resolve(evidenceDir,'coop-camp.png')});
  await nearAndUse('wood','wood');
  await nearAndUse('tarp','tarp');
  await nearAndUse('repair','repaired');
  const repaired=await state();
  report.completed={rain:repaired.rain,elapsed:repaired.elapsed,quest:repaired.quest,sheltered:repaired.sheltered};
  await page.keyboard.press('Shift+Escape');
  await until(async()=>!(await state()).locked,5000,'Shift+Esc release');
  s=await state();
  const [inviteX,inviteY,inviteWidth,inviteHeight]=s.inviteRect;
  await clickCanvasPoint(page,[(inviteX+inviteWidth/2)/s.viewport[0],(inviteY+inviteHeight/2)/s.viewport[1]]);
  await until(async()=>(await state()).inviteShown,5000,'invite link visible');
  report.inviteKeptPointerFree=await page.evaluate(()=>!document.pointerLockElement && !CooperStatus.locked);
  assert.ok(report.inviteKeptPointerFree);
  report.inviteUrl=await page.evaluate(()=>CooperJoin.inviteUrl);
  assert.equal(new URL(report.inviteUrl).searchParams.get('room'),room);
  await page.reload({waitUntil:'domcontentloaded'});
  const rejoined=await until(async()=>{const x=await state();return x.ready&&x;},45000,'refresh reconnect');
  assert.equal(rejoined.selfId,id);assert.ok(rejoined.quest.repaired);
  report.reconnect={samePlayerId:true,sameQuest:true,distanceFromLast:length([rejoined.x,rejoined.z],[repaired.x,repaired.z])};
  assert.ok(report.reconnect.distanceFromLast<.5);
  if(native){
    const n=(await nativeStates()).findLast(x=>x.members===2&&x.quest.repaired);
    assert.ok(n);report.nativeObserved={quest:n.quest,zone:n.zone,members:n.members,remoteAvatars:n.remoteAvatars,rain:n.rain,elapsed:n.elapsed};
  }
  assert.ok(new Set(report.zonesRequested).size>=5);
  assert.equal(report.errors.length,0,JSON.stringify(report.errors));
  report.ok=true;
} catch(error){
  report.ok=false;report.error=String(error);
  if(page){report.last=await state().catch(()=>null);report.dom=await page.evaluate(()=>({pointer:!!document.pointerLockElement,focus:document.hasFocus(),loader:document.querySelector('#loader')?.hidden,active:document.activeElement?.tagName})).catch(()=>null);await page.screenshot({path:resolve(root,'.cache/coop-playtest-failed.png')}).catch(()=>{});}
  throw error;
} finally {
  if(browser)await browser.close();
  if(nativeLaunch && nativeLaunch.exitCode===null && nativeLaunch.signalCode===null)nativeLaunch.kill('SIGTERM');
  if(nativeClosed)await nativeClosed;
  report.zonesRequested=[...new Set(report.zonesRequested)];
  await writeFile(resolve(evidenceDir,native?'coop-playtest.json':'coop-playtest-web.json'),JSON.stringify(report,null,2));
  console.log('Playable test',report.ok,report.picked.join(', '));
}
