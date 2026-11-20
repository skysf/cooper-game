// Ordinary browser input against an offline-authored stress room; no gameplay mutation API.
import assert from 'node:assert/strict';
import {chromium} from 'playwright';
import {mkdir, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {randomBytes} from 'node:crypto';
import {browserTestOptions, prepareOffscreenPage, stageOffscreenControls} from './coop-browser-controls.mjs';
import {installFrameCapture, intervals} from './coop-frame-capture.mjs';
const base = process.env.COOP_BASE || 'http://127.0.0.1:4294';
const out = resolve(process.env.COOP_EVIDENCE_DIR || 'evidence/wild-people-web-stress');
const room = process.env.COOP_WILD_ROOM || 'wild-qa-stress';
const token = 'cafe00112233445566778899aabbccdd';
await mkdir(out, {recursive:true});
const browser = await chromium.launch(browserTestOptions());
const peers = [];
const errors = [];
let page;
let heartbeat;
let patrol;
const hold = ms => new Promise(r=>setTimeout(r,ms));
try {
  for (let i=0;i<3;i++) {
    const ws = new WebSocket(base.replace(/^http/,'ws')+'/room');
    const peer = {ws, id:'', state:null, positions:[], motions:0};
    peers.push(peer);
    ws.onmessage = event => {
      const message = JSON.parse(event.data);
      if (message.t === 'welcome') peer.id = message.id;
      if (message.t === 'snapshot') peer.state = message.players[peer.id];
    };
    await new Promise((done,fail)=>{ws.onopen=done;ws.onerror=fail;});
    ws.send(JSON.stringify({t:'join',room,token:randomBytes(16).toString('hex')}));
  }
  heartbeat = setInterval(()=>{for(const {ws} of peers)if(ws.readyState===WebSocket.OPEN)ws.send(JSON.stringify({t:'ping'}));},3000);
  const context = await browser.newContext({viewport:{width:1280,height:720},deviceScaleFactor:1});
  page = await context.newPage();
  page.on('pageerror',e=>errors.push(String(e)));
  page.on('console',m=>{if(m.type()==='error' && /SCRIPT ERROR|Parse Error|Invalid/.test(m.text()))errors.push(m.text());});
  await prepareOffscreenPage(page);
  await page.addInitScript(installFrameCapture);
  await page.addInitScript(token=>sessionStorage.setItem('cooper-identity',token),token);
  await page.goto(base+'/coop/?room='+room);
  await page.waitForFunction(()=>window.CooperStatus?.ready, null, {timeout:120000});
  await stageOffscreenControls(page);
  await page.waitForFunction(()=>CooperStatus.elapsed >= 186, null, {timeout:65000});
  const arrivalStart = await page.evaluate(()=>({elapsed:CooperStatus.elapsed,
    raiders:Object.values(CooperStatus.wildPeople?.people||{}).filter(p=>p.phase==='raider').length}));
  const raidTiming = page.evaluate(()=>window.coopBenchSample(13000));
  const lanes = peers.map(peer=>[peer.state.x,peer.state.z]);
  const started = performance.now();
  patrol = setInterval(()=>{
    for (let i=0;i<peers.length;i++) {
      const peer = peers[i];
      if (peer.ws.readyState !== WebSocket.OPEN || !peer.state) continue;
      const {x,z,vx,vz} = peer.state;
      const waypoint = lanes[i][1] + 1.4 + Math.sin((performance.now() - started) / 1050 + i) * 1.1;
      const dx = lanes[i][0] - x;
      const dz = waypoint - z;
      const gap = Math.max(.50,Math.hypot(dx,dz));
      peer.ws.send(JSON.stringify({t:'motion',x:dx/gap,z:dz/gap,yaw:Math.atan2(-dx,-dz)}));
      peer.positions.push([x,z,vx,vz]);
      peer.motions++;
    }
  },80);
  await page.waitForFunction(()=>Object.values(CooperStatus.wildPeople?.people||{}).filter(p=>p.phase==='raider').length===4, null, {timeout:120000});
  const arrival = await raidTiming;
  assert.ok(!arrival.hidden && !arrival.lostFocus && arrival.submitted.length > 2);
  assert.deepEqual(arrival.buffer,[1280,720]);
  await writeFile(resolve(out,'raid-arrival-frames.json'),JSON.stringify(arrival)+'\n');
  const arrivalTiming = intervals(arrival.submitted.map(frame=>frame.time));
  await page.screenshot({path:resolve(out,'four-player-camp-combat.png')});
  const timingPromise = page.evaluate(()=>window.coopBenchSample(10000,300));
  const frames = [];
  for(let i=0;i<20;i++) {
    frames.push(await page.evaluate(()=>{
      const s=window.CooperStatus;
      const people=Object.values(s.wildPeople?.people||{});
      return {fps:s.fps,members:s.members,avatars:s.remoteAvatars,health:s.survival.health,
        living:people.filter(p=>!['dead','gone','released'].includes(p.phase)).length,
        raiders:people.filter(p=>p.phase==='raider').length,companions:people.filter(p=>p.phase==='companion').length};
    }));
    await hold(500);
  }
  const timingRaw = await timingPromise;
  clearInterval(patrol);
  assert.deepEqual(timingRaw.buffer,[1280,720]);
  assert.ok(!timingRaw.hidden && !timingRaw.lostFocus && timingRaw.renderer && !/swiftshader|software/i.test(timingRaw.renderer));
  const submittedTiming = intervals(timingRaw.submitted.map(f=>f.time));
  await writeFile(resolve(out,'submitted-frames.json'),JSON.stringify(timingRaw)+'\n');
  await page.keyboard.press('KeyB');
  await page.waitForFunction(()=>window.CooperStatus?.peopleOpen);
  const before = await page.evaluate(()=>({x:CooperStatus.x,z:CooperStatus.z,attack:CooperStatus.survival.attackAt}));
  await page.keyboard.down('KeyW');
  await page.mouse.click(1180,660);
  await hold(500);
  await page.keyboard.up('KeyW');
  const after = await page.evaluate(()=>({x:CooperStatus.x,z:CooperStatus.z,attack:CooperStatus.survival.attackAt,locked:CooperStatus.locked,modal:CooperStatus.peopleOpen}));
  assert.equal(after.locked,false);assert.equal(after.modal,true);
  assert.ok(Math.hypot(after.x-before.x,after.z-before.z)<0.12);
  assert.equal(after.attack,before.attack);
  await page.screenshot({path:resolve(out,'four-player-people-panel.png')});
  await page.keyboard.press('Escape');
  await page.waitForFunction(()=>!CooperStatus.peopleOpen);
  assert.ok(frames.every(f=>f.members===4 && f.avatars===3));
  assert.ok(frames.some(f=>f.living>=8));
  const activePeers = peers.map(({id,motions,positions})=>{
    const [startX,startZ] = positions[0];
    const distance = Math.max(...positions.map(([x,z])=>Math.hypot(x-startX,z-startZ)));
    const movingSamples = positions.filter(([, ,vx,vz])=>Math.hypot(vx,vz) > .25).length;
    assert.ok(distance > .65 && movingSamples > 10, 'each remote player must move through the live server');
    return {id,motions,distance,movingSamples};
  });
  assert.deepEqual(errors,[]);
  const fps=frames.map(f=>f.fps).sort((a,b)=>a-b);
  await writeFile(resolve(out,'report.json'),JSON.stringify({ok:true,mode:'headless Chrome ANGLE Metal; 4 real room players, up to 8 real NPCs',formalHardwareTimingEligible:false,
    modalNoAttack:true,modalNoMovement:true,arrivalStart,arrivalTiming,activePeers,submittedTiming,renderer:timingRaw.renderer,frames,
    observedFps:{min:fps[0],median:fps[Math.floor(fps.length/2)],max:fps.at(-1)},errors},null,2)+'\n');
  clearInterval(heartbeat);
  console.log(JSON.stringify({ok:true,samples:frames.length,minFps:fps[0],medianFps:fps[Math.floor(fps.length/2)],out}));
} catch(e) {
  if(page)await page.screenshot({path:resolve(out,'failure.png')}).catch(()=>{});
  await writeFile(resolve(out,'failure.json'),JSON.stringify({error:String(e),errors},null,2)+'\n');
  throw e;
} finally {
  clearInterval(heartbeat);
  clearInterval(patrol);
  for(const {ws} of peers)ws.close();
  await browser.close();
}
