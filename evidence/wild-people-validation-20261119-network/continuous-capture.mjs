import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {intervals} from '../../scripts/coop-frame-capture.mjs';

const wait=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,ms,label){const end=Date.now()+ms;while(Date.now()<end){if(fn())return;await wait(30);}throw Error('Timed out '+label);}
function metrics(frames){assert.ok(frames.length>2,'enough submitted frames');const value=intervals(frames.map(f=>f.time));let streak=0,longest=0;for(const dt of value.intervalsMs){streak=dt>50?streak+1:0;longest=Math.max(longest,streak);}return {...value,intervalsMs:undefined,frames:frames.length,framesOver50Ms:value.intervalsMs.filter(dt=>dt>50).length,longestSlowStreak:longest};}
function phaseCounts(snapshot){const ns=Object.values(snapshot?.wildPeople?.people||{});return {players:Object.keys(snapshot?.players||{}).length,livingNPCs:ns.filter(n=>!['dead','gone','released'].includes(n.phase)).length,raiders:ns.filter(n=>n.phase==='raider').length,companions:ns.filter(n=>n.phase==='companion').length};}

// A single uninterrupted capture. Only the normal room WebSocket is observed
// during it; screenshots, state serialization, file writes and OS queries follow it.
export async function captureContinuous({page,report,out,stream,plannedWaveAt,controlZero=false,foreground,foregroundApp,enterCamp,beforeCapture=null,afterCapture=null,diagnosticOnly=false}){
 const prepared=await page.evaluate(()=>({elapsed:CooperStatus.elapsed,ready:CooperStatus.ready,warm:CooperStatus.peopleWarmupCount,locked:CooperStatus.locked}));
 assert.equal(prepared.ready,true);assert.equal(prepared.warm,8);
 const expectedStartWall=Date.now()+(plannedWaveAt-4-prepared.elapsed)*1000;
 console.log('CAPTURE_PLAN',JSON.stringify({now:new Date().toISOString(),expectedStart:new Date(expectedStartWall).toISOString(),expectedEnd:new Date(expectedStartWall+21000).toISOString(),secondsUntilStart:(expectedStartWall-Date.now())/1000,prepared,plannedWaveAt}));
 await until(()=>stream.latest?.elapsed>=plannedWaveAt-11,120000,'pre-wave foreground preparation');
 await page.evaluate(()=>{window.coopBenchFixedInput=false;});await foreground(page);if(!(await page.evaluate(()=>CooperStatus.locked)))await enterCamp(page);for(const key of ['w','a','s','d','Space','c','Shift'])await page.keyboard.up(key);await page.evaluate(()=>{window.coopBenchPinCamera=true;window.coopBenchFixedInput=true;});
 const beforeApp=foregroundApp();
 const cdp=await page.context().newCDPSession(page),{windowId}=await cdp.send('Browser.getWindowForTarget'),bounds=await cdp.send('Browser.getWindowBounds',{windowId});await cdp.detach();
 const origin=await page.evaluate(()=>performance.timeOrigin);
 if(beforeCapture)await beforeCapture();
 await until(()=>stream.latest?.elapsed>=plannedWaveAt-4,20000,'fixed pre-wave capture boundary');
 const before=await page.evaluate(()=>CooperStatus);
 assert.equal(phaseCounts({wildPeople:before.wildPeople,players:before.players}).raiders,0,'no new enemy may exist before transition capture');
 assert.equal(stream.birth,null,'first enemy birth was not missed during preparation');
 const startWall=Date.now();
 console.log('CONTINUOUS_CAPTURE_BEGIN',JSON.stringify({wall:new Date(startWall).toISOString(),elapsed:before.elapsed,poolHits:before.peoplePoolHits,coldCreates:before.peopleColdCreates}));
 const raw=await page.evaluate(async()=>{window.coopDiagMark?.('raw-capture-start');const value=await coopBenchSample(21000);window.coopDiagMark?.('raw-capture-end');return value;});
 const finishWall=Date.now();
 const afterApp=foregroundApp();
 const after=await page.evaluate(()=>CooperStatus);
 if(afterCapture)await afterCapture();
 const marker=controlZero?stream.controlBoundary:stream.birth;assert.ok(marker&&marker.wall>=startWall&&marker.wall<=finishWall,controlZero?'zero NPC reference time lies in capture':'four genuinely new enemies appeared during capture');if(controlZero)assert.equal(phaseCounts({wildPeople:after.wildPeople,players:after.players}).livingNPCs,0);
 const birthTime=marker.wall-origin;
 const submitted=raw.submitted;
 let birthIndex=submitted.findIndex(f=>f.time>=birthTime);assert.ok(birthIndex>1,'pre-birth submitted frames preserved');
 const firstStart=Math.max(0,birthIndex-1); // Preserve the interval spanning birth.
 const firstEnd=submitted.findIndex(f=>f.time>=birthTime+8000);
 assert.ok(firstEnd>firstStart,'eight seconds of first appearance preserved');
 const steadyStart=Math.max(firstStart,firstEnd-1);
 const slices={
  [controlZero?'zero-npc-before':'wave-before']:submitted.slice(0,birthIndex),
  [controlZero?'zero-npc-reference-window':'stress-first-appearance']:submitted.slice(firstStart,firstEnd+1),
  [controlZero?'zero-npc-steady':'stress-steady']:submitted.slice(steadyStart)
 };
 const sensors=await page.evaluate(()=>({poses:window.coopBenchPoseTrace,inputs:window.coopBenchInputTrace}));const poses=sensors.poses.filter(p=>p.time>=submitted[0].time&&p.time<=submitted.at(-1).time),anchor=poses[0];assert.ok(anchor,'small pose probes captured');const poseMotion={maxPosition:Math.max(...poses.map(p=>Math.hypot(p.x-anchor.x,p.z-anchor.z))),maxYaw:Math.max(...poses.map(p=>Math.abs(Math.atan2(Math.sin(p.yaw-anchor.yaw),Math.cos(p.yaw-anchor.yaw))))),maxPitch:Math.max(...poses.map(p=>Math.abs(p.pitch-anchor.pitch)))};const poseFixed=poseMotion.maxPosition<.05&&poseMotion.maxYaw<.004&&poseMotion.maxPitch<.004;
 const eligible=!diagnosticOnly&&poseFixed&&report.blank.blankRefreshEligible&&!report.screenLocked&&!raw.hidden&&!raw.lostFocus&&before.locked&&after.locked&&/Google Chrome/.test(beforeApp)&&/Google Chrome/.test(afterApp)&&bounds.bounds.windowState==='normal'&&!/SwiftShader|software|llvmpipe/i.test(raw.renderer);
 const trace=stream.trace.filter(t=>t.wall>=startWall-200&&t.wall<=finishWall+200);
 for(const [name,frames]of Object.entries(slices)){
  const m=metrics(frames),firstWall=origin+frames[0].time,lastWall=origin+frames.at(-1).time;
  const segmentTrace=trace.filter(t=>t.wall>=firstWall&&t.wall<=lastWall);
  const meets=m.fps>=30&&m.p95Ms<=34&&m.framesOver50Ms/Math.max(1,m.frames-1)<=.01&&m.longestSlowStreak<2&&m.maxMs<=100;
  report.samples[name]={...m,renderer:raw.renderer,buffer:raw.buffer,hidden:raw.hidden,lostFocus:raw.lostFocus,beforeApp,afterApp,window:bounds.bounds,lockedBefore:before.locked,lockedAfter:after.locked,peopleWarmupCount:before.peopleWarmupCount,peopleWarmupMs:before.peopleWarmupMs,poolHitsBefore:before.peoplePoolHits,poolHitsAfter:after.peoplePoolHits,coldCreatesBefore:before.peopleColdCreates,coldCreatesAfter:after.peopleColdCreates,poolByKeyBefore:before.peoplePoolByKey,poolByKeyAfter:after.peoplePoolByKey,coldByKeyBefore:before.peopleColdByKey,coldByKeyAfter:after.peopleColdByKey,poolMeasurementScope:'entire uninterrupted transition and steady window',birth:marker,poseFixed,poseMotion,phaseCountsStart:segmentTrace[0]?.counts,phaseCountsEnd:segmentTrace.at(-1)?.counts,diagnosticOnly,timingEnvironmentEligible:eligible,meets30FpsThresholds:eligible?meets:null};
  console.log('CONTINUOUS_SEGMENT',JSON.stringify({name,...report.samples[name]}));
 }
 report.continuousCapture={diagnosticOnly,startWall,finishWall,performanceTimeOrigin:origin,birthPerformanceTime:birthTime,birth:marker,controlZero,poseFixed,poseMotion,plannedWaveAt,beforeCounts:phaseCounts({wildPeople:before.wildPeople,players:before.players}),afterCounts:phaseCounts({wildPeople:after.wildPeople,players:after.players}),noScreenshotsOrQueriesInsideCapture:true};
 await writeFile(resolve(out,'continuous-raw-frames.json'),JSON.stringify(raw));
 await writeFile(resolve(out,'continuous-room-trace.json'),JSON.stringify({birth:marker,trace,before,after,sensors,poseMotion},null,2));
 await page.screenshot({path:resolve(out,'stress-after-continuous-capture.png')});
}
