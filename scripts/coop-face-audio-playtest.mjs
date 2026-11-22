// Two clients in a fresh QA room. The observer uses the normal Godot UI, while a
// nearby peer exercises the public inventory protocol. Record actual WebAudio starts.
import assert from 'node:assert/strict';
import {createHash, randomBytes} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {chromium} from 'playwright';
import {browserTestOptions, prepareOffscreenPage, enterCamp, clickCanvasPoint} from './coop-browser-controls.mjs';
const base=process.env.COOP_URL||'http://127.0.0.1:5784/coop/';
const engineAudio=process.env.COOP_QA_ENGINE_AUDIO==='1';
const out=resolve('evidence/eastern-ground-repair-20261121');
const saves=resolve(process.env.COOP_QA_SAVE_DIR||'.cache/world-expansion/repairs/rooms');
const room='voice-'+randomBytes(5).toString('hex'), token=()=>randomBytes(16).toString('hex');
const localToken=token(), remoteToken=token(), id=t=>createHash('sha256').update(room+':'+t).digest('hex').slice(0,16);
const local=id(localToken), remote=id(remoteToken), speaker='coal_mine-dweller-0', now=84;
const home=(x,z)=>({x,z,y:4.3,yaw:Math.PI});
const npc={id:speaker,sex:'female',name:'槐枝',phase:'resident',tier:1,x:90,z:-51.0,y:4.33,yaw:0,clip:'Idle',homeMine:'coal_mine',duty:'fire',berth:0,workUntil:now+18};
const state={version:1,quest:{wood:false,tarp:false,repaired:false},elapsed:now,homes:{[local]:home(90,-52.25),[remote]:home(91.45,-51.4)},survival:{[remote]:{health:100,hunger:36,water:35,bag:{apple:1,bread:1,water:1}}},wildPeople:{version:1,caves:{coal_mine:{settled:true,fireUntil:now+100}},people:{[speaker]:npc}}};
await mkdir(saves,{recursive:true});await mkdir(out,{recursive:true});
await writeFile(join(saves,room+'.json'),JSON.stringify(state),{flag:'wx'});
const browser=await chromium.launch(browserTestOptions()), errors=[];
const page=await browser.newPage({viewport:{width:1200,height:710}});let peer;
const status=()=>page.evaluate(()=>CooperStatus);
try{
 await page.addInitScript(({token:t,engineAudio})=>{
  sessionStorage.setItem('cooper-identity',t);window.__CooperWildTrace=true;
  // Exercise the same WebAudio fallback as an HTTP LAN client on loopback.
  if(!engineAudio)for(let proto=AudioContext.prototype;proto;proto=Object.getPrototypeOf(proto)){
   if(Object.hasOwn(proto,'audioWorklet')){delete proto.audioWorklet;break;}
  }
  window.starts=[];window.mixPeaks=[];let current, audio;
  if(engineAudio){
   const connect=AudioNode.prototype.connect;
   AudioNode.prototype.connect=function(dest,...args){
    if(dest===this.context.destination){
     const meter=this.context.createAnalyser();meter.fftSize=512;connect.call(this,meter);
     const data=new Float32Array(meter.fftSize);
     setInterval(()=>{meter.getFloatTimeDomainData(data);let peak=0;for(const v of data)peak=Math.max(peak,Math.abs(v));window.mixPeaks.push({at:performance.now(),peak});},24);
    }
    return connect.call(this,dest,...args);
   };
  }
  const original=AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start=function(...args){if(current)window.starts.push({name:current,loop:this.loop,offset:args[1]||0});return original.apply(this,args);};
  Object.defineProperty(window,'CooperAudio',{configurable:true,get:()=>audio,set:obj=>{
   audio=obj;for(const key of ['ambient','engine','play']){const orig=obj[key];obj[key]=function(name,...rest){current=name;try{return orig.call(this,name,...rest);}finally{current=null;}};}
  }});
 },{token:localToken,engineAudio});
 await prepareOffscreenPage(page);
 page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(/SCRIPT ERROR|Parse Error|Compilation failed|SHADER ERROR/.test(m.text()))errors.push(m.text());});
 await page.goto(base+'?room='+room);console.log('loading',room);await page.waitForFunction(()=>window.CooperStatus?.ready,null,{timeout:150000});await enterCamp(page);
 peer=new WebSocket(new URL('/room',base.replace('http','ws')));let snap;
 peer.onmessage=e=>{const m=JSON.parse(e.data);if(m.t==='snapshot')snap=m;};
 await new Promise((res,rej)=>{peer.onopen=res;peer.onerror=rej;});
 peer.send(JSON.stringify({t:'join',room,token:remoteToken}));
 const wait=ms=>new Promise(r=>setTimeout(r,ms));
 for(let i=0;i<100&&!snap;i++)await wait(60);
 assert.ok(snap?.players?.[remote]);await page.waitForFunction(w=>w in (CooperStatus.faces||{}),speaker);
 async function aim(height){
  const s=await status(),p=s.wildPeople.people[speaker],feet=s.players[local].y;
  const yaw=Math.atan2(s.x-p.x,s.z-p.z),pitch=Math.atan2(p.y+height-feet-1.67,Math.hypot(p.x-s.x,p.z-s.z));
  await page.evaluate(({yaw,pitch})=>{const c=document.querySelector('#canvas'),r=c.getBoundingClientRect(),s=CooperStatus;c.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,pointerType:'mouse',movementX:Math.round(Math.atan2(Math.sin(s.yaw-yaw),Math.cos(s.yaw-yaw))/.00215*r.width/c.width),movementY:Math.round((s.pitch-pitch)/.00215*r.height/c.height),clientX:r.x+r.width/2,clientY:r.y+r.height/2}));},{yaw,pitch});
  await wait(320);
 }
 await aim(1.5);await page.screenshot({path:join(out,'resident-rest.jpg'),quality:95});
 await aim(1.12);await page.keyboard.press('KeyB');
 await page.waitForFunction(s=>CooperStatus.peoplePanel?.selected===s&&CooperStatus.peoplePanel?.actions?.['chat/']?.visible,speaker,{timeout:7000});
 let s=await status();let button=s.peoplePanel.actions['chat/'];assert.equal(button.disabled,false);
 const [x,y,w,h]=button.rect;await clickCanvasPoint(page,[(x+w/2)/s.viewport[0],(y+h/2)/s.viewport[1]]);
 await page.waitForFunction(s=>CooperStatus.wildPeople.people[s].speechAt>=84,speaker,{timeout:6000});
 const samples=[];await aim(1.51);
 const end=Date.now()+3400;let photographed=false, stamp=-1;
 while(Date.now()<end){s=await status();const face=s.faces?.[speaker];
  if(face&&s.elapsed!==stamp){samples.push({time:s.elapsed-s.wildPeople.people[speaker].speechAt,face});stamp=s.elapsed;if(face[0]>.55&&!photographed){await page.screenshot({path:join(out,'resident-speaking.jpg'),quality:95});photographed=true;}}
  await wait(28);
 }
 assert.ok(photographed,'mouth opens');assert.equal(samples.at(-1).face[0],0,'lips close at the end');
 assert.ok(samples.some(o=>o.time<2.8&&o.face[0]<.13),'real pause during greeting');
 for(const [action,item,cue] of [['eat','apple','eat_apple'],['eat','bread','eat_bread'],['drink','water','drink_water']]){
  const mark=await page.evaluate(()=>performance.now());
  peer.send(JSON.stringify({t:'provision',action,item}));
  if(engineAudio){
   for(let i=0;i<50&&!snap?.stoneSounds?.some(e=>e.cue===cue);i++)await wait(30);
   assert.ok(snap.stoneSounds.some(e=>e.cue===cue),'server emitted '+cue);
   await page.waitForFunction(t=>window.mixPeaks.some(e=>e.at>t&&e.peak>0.008),mark,{timeout:3000});
   await wait(700);
  }else await page.waitForFunction(c=>window.starts.some(e=>e.name===c+'.wav'),cue,{timeout:5000});
  assert.equal(snap.players[remote].slot,2);
 }
 peer.send(JSON.stringify({t:'provision',action:'eat',item:'apple'}));await wait(700);
 const played=await page.evaluate(()=>window.starts);if(!engineAudio)for(const name of ['eat_apple','eat_bread','drink_water','resident_female'])assert.equal(played.filter(e=>e.name===name+'.wav').length,1,name+' plays once');
 if(!engineAudio)assert.ok(played.some(e=>e.name==='forest_rain.wav'&&e.loop),'rain mixer running');assert.deepEqual(errors,[]);
 await writeFile(join(out,engineAudio?'voice-and-food-worklet.json':'voice-and-food.json'),JSON.stringify({played,samples,errors,backend:engineAudio?'Godot AudioWorklet':'LAN Web Audio',outputPeak:engineAudio?await page.evaluate(()=>window.mixPeaks.reduce((x,v)=>Math.max(x,v.peak),0)):undefined},null,2)+'\n');console.log('FACE_AUDIO_WEB_OK',played.map(s=>s.name).join(' '),samples.length);
} catch(e){console.error(e);console.error('last state',await page.evaluate(s=>({clock:window.CooperStatus?.elapsed,person:window.CooperStatus?.wildPeople?.people?.[s],panel:window.CooperStatus?.peoplePanel?.actions?.['chat/'],starts:window.starts,faces:window.CooperStatus?.faces}),speaker).catch(()=>null));process.exitCode=1;}
finally{peer?.close();await browser.close();}
