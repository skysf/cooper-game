// Measure first playable in a cold, bandwidth-limited browser context.
// A second independent browser context verifies the invite and both peer views.
import {chromium} from 'playwright';
import {writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {browserTestOptions, prepareOffscreenPage} from './coop-browser-controls.mjs';
const base=(process.env.COOP_BASE||'http://localhost:4184').replace(/\/$/,'');
const room='stream-'+Date.now().toString(36);
const browser=await chromium.launch(browserTestOptions());
try{
  const options={viewport:{width:1280,height:720},deviceScaleFactor:1};
  const ctx=await browser.newContext(options), page=await ctx.newPage();
  page.on('pageerror',error=>console.error(error.message));
  page.on('requestfailed',r=>console.error(r.url(),r.failure()?.errorText));
  const cdp=await prepareOffscreenPage(page);
  const wire=[], requests=[];
  let navClock;
  cdp.on('Network.requestWillBeSent',event=>{
    if(event.type==='Document' && event.request.url.startsWith(base))navClock=event.wallTime-event.timestamp;
    if(event.request.url.startsWith(base+'/coop/zones/'))requests.push({time:event.timestamp,path:new URL(event.request.url).pathname});
  });
  cdp.on('Network.dataReceived',event=>wire.push({id:event.requestId,time:event.timestamp,bytes:event.encodedDataLength,done:false}));
  cdp.on('Network.loadingFinished',event=>wire.push({id:event.requestId,time:event.timestamp,bytes:event.encodedDataLength,done:true}));
  await cdp.send('Network.enable');await cdp.send('Network.clearBrowserCache');
  await cdp.send('Network.emulateNetworkConditions',{offline:false,latency:70,downloadThroughput:10_000_000/8,uploadThroughput:2_000_000/8});
  await page.addInitScript(()=>{
    const timer=setInterval(()=>{
      if(!window.CooperStatus?.ready || !document.querySelector('#loader')?.hidden)return;
      clearInterval(timer);
      const c=document.querySelector('canvas'),gl=c.getContext('webgl2'),ext=gl.getExtension('WEBGL_debug_renderer_info');
      const resources=performance.getEntriesByType('resource').map(r=>({path:new URL(r.name).pathname,bytes:r.transferSize,encoded:r.encodedBodySize,completedAtMs:r.responseEnd}));
      window.campMeasurement={readyMs:performance.now(),timeOrigin:performance.timeOrigin,resources,buffer:[gl.drawingBufferWidth,gl.drawingBufferHeight],gpu:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER),resident:window.CooperStatus.resident};
    },25);
  });
  const url=base+'/coop/?room='+room;
  await page.goto(url,{waitUntil:'domcontentloaded'});
  try {
    await page.waitForFunction(()=>window.campMeasurement,null,{timeout:95000});
  } catch (error) {
    console.error(await page.evaluate(()=>({phase:document.querySelector('#phase')?.textContent,status:window.CooperStatus?.status,terrain:window.CooperStatus?.terrainError})));
    throw error;
  }
  const report=await page.evaluate(()=>campMeasurement);
  const readyAt=(report.timeOrigin+report.readyMs)/1000-navClock;
  report.zonesRequestedAtReady=requests.filter(r=>r.time<=readyAt).map(r=>r.path);
  const received=new Map();
  for(const e of wire){
    if(e.time>readyAt)continue;
    received.set(e.id,e.done?e.bytes:(received.get(e.id)||0)+e.bytes);
  }
  report.encodedBytesAtReady=[...received.values()].reduce((n,v)=>n+v,0);
  assert.ok(report.resources.some(r=>r.path.endsWith('/camp.glb')));
  assert.ok(!report.zonesRequestedAtReady.some(path=>path.endsWith('/tower.glb')));
  report.downloadMbps=10;report.uploadMbps=2;report.simulatedLatencyMs=70;
  report.transferredMiB=report.resources.reduce((sum,r)=>sum+r.bytes,0)/1048576;
  report.chrome=browser.version();report.date=new Date().toISOString();report.headless=true;
  const inviteButton=await page.evaluate(()=>{
    const r=document.querySelector('canvas').getBoundingClientRect();
    const [x,y,w,h]=CooperStatus.inviteRect;
    return {x:r.left+(x+w/2)*r.width/CooperStatus.viewport[0],y:r.top+(y+h/2)*r.height/CooperStatus.viewport[1]};
  });
  await page.mouse.click(inviteButton.x,inviteButton.y);
  const field=page.getByRole('textbox',{name:/房间邀请链接/});
  await field.waitFor({state:'visible'});
  const invite=await field.inputValue();
  assert.equal(new URL(invite).searchParams.get('room'),room);
  assert.ok(await field.evaluate(el=>el.selectionStart===0 && el.selectionEnd===el.value.length));
  report.invite={url:invite,selectable:true};
  const ctx2=await browser.newContext(options),p2=await ctx2.newPage();
  await prepareOffscreenPage(p2);
  await p2.goto(invite);await p2.waitForFunction(()=>window.CooperStatus?.ready&&CooperStatus.members===2&&CooperStatus.remoteAvatars===1,null,{polling:100,timeout:45000});
  await page.waitForFunction(()=>window.CooperStatus?.members===2&&CooperStatus.remoteAvatars===1,null,{polling:100,timeout:18000});
  const players=await Promise.all([page,p2].map(p=>p.evaluate(()=>({id:CooperStatus.selfId,peers:CooperStatus.members,avatars:CooperStatus.remoteAvatars}))));
  assert.notEqual(players[0].id,players[1].id);assert.ok(players.every(x=>x.avatars===1));
  report.twoBrowsers=players;report.base=base;
  await writeFile(process.env.COOP_START_REPORT||'evidence/coop-web-start.json',JSON.stringify(report,null,2));
  console.log(JSON.stringify({readyMs:report.readyMs,MiB:report.transferredMiB,players,buffer:report.buffer,zones:report.resources.filter(r=>r.path.includes('zones')).map(r=>r.path)}));
}finally{await browser.close();}
