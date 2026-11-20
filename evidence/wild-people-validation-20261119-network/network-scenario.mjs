import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import net from 'node:net';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {findPath} from '../../scripts/coop-test-path.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url));
const out=resolve(fileURLToPath(new URL('.',import.meta.url)),process.argv[2]||'run-2');
const saves=resolve(out,'saves');
const engine='/Users/sky/Downloads/Godot.app/Contents/MacOS/Godot';
const manifest=JSON.parse(await readFile(resolve(root,'coop/world.json'),'utf8'));
const implementation=await readFile(resolve(root,'coop/wild_people.gd'),'utf8');
const location=name=>implementation.match(new RegExp('const '+name+' := Vector2\\(([-0-9.]+), ([-0-9.]+)\\)')).slice(1).map(Number);
const herbsAt=location('HERBS'),waterAt=location('WATER');
const tokens=['a'.repeat(32),'b'.repeat(32)];
const pid=(room,index)=>createHash('sha256').update(room+':'+tokens[index]).digest('hex').slice(0,16);
const wait=ms=>new Promise(done=>setTimeout(done,ms));
const dist=(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1]);
const point=p=>{const a=p.state.players[p.id];return [a.x,a.z];};
const people=p=>p.state.wildPeople.people;
const report={started:new Date().toISOString(),transport:'Production Godot server and real loopback WebSocket clients',cases:{},events:[],errors:[]};
let server,port,bootNumber=0,logs='',allPeers=[];
function mark(name,detail={}){report.events.push({name,at:new Date().toISOString(),...detail});console.log(name,JSON.stringify(detail));}
async function until(fn,ms=10000,label='condition'){
 const end=Date.now()+ms;
 while(Date.now()<end){const v=await fn();if(v)return v;await wait(40);}
 throw Error('Timed out: '+label);
}
async function fixture(room,{elapsed=1000,homes=[[6,-81],[6,-81]],wild={},survival={}}={}){
 const data={version:1,elapsed,groveStartedAt:0,quest:{wood:true,tarp:true,repaired:true},homes:{},survival:{},wildPeople:{version:1,settings:{firstRaid:7200,warning:8,rest:3600,maxRaiders:1,maxCompanions:4,damageScale:.25},people:{},...wild}};
 tokens.forEach((_,i)=>{data.homes[pid(room,i)]={x:homes[i][0],z:homes[i][1],yaw:0};data.survival[pid(room,i)]={health:100,hunger:86,water:82,mood:65,bag:{},worn:{cap:true,jacket:true,pants:true},...(survival[i]||{})};});
 await writeFile(resolve(saves,room+'.json'),JSON.stringify(data));
}
async function boot(){
 bootNumber++;let ready=false;
 server=spawn(engine,['--headless','--path',resolve(root,'coop'),'--log-file',resolve(out,'godot-'+bootNumber+'.log'),'--script','res://server.gd','--','--port='+port,'--save='+saves],{stdio:['ignore','pipe','pipe']});
 for(const stream of [server.stdout,server.stderr])stream.on('data',d=>{logs+=String(d);if(String(d).includes('ROOM_SERVER_READY'))ready=true;});
 await until(()=>{if(server.exitCode!==null)throw Error('server exited '+logs.slice(-3000));return ready;},15000,'room server ready');
}
async function stop(){if(!server||server.exitCode!==null||server.signalCode!==null)return;const done=new Promise(r=>server.once('exit',r));server.kill('SIGTERM');await done;}
async function connect(room,index,session='validation-'+index){
 const ws=new WebSocket('ws://127.0.0.1:'+port);
 const p={ws,room,index,id:'',state:null,notices:[],frames:0,phases:[],history:[],send:m=>ws.send(JSON.stringify(m))};allPeers.push(p);
 ws.onopen=()=>{p.send({t:'join',room,token:tokens[index],session});p.keep=setInterval(()=>{if(ws.readyState===WebSocket.OPEN)p.send({t:'ping'});},4000);};
 ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.t==='welcome')p.id=m.id;if(m.t==='snapshot'){p.state=m;p.frames++;const phase=m.wildPeople?.raid?.phase;if(phase&&p.phases.at(-1)!==phase){p.phases.push(phase);mark('phase',{room,index,phase,elapsed:m.elapsed});}p.history.push({elapsed:m.elapsed,people:m.wildPeople?.people,resources:m.wildPeople?.resources});if(p.history.length>30)p.history.shift();}if(m.t==='notice')p.notices.push(m);if(m.t==='reject')throw Error(JSON.stringify(m));};
 ws.onclose=()=>clearInterval(p.keep);
 await until(()=>p.id&&p.state,10000,'peer join '+room+'/'+index);return p;
}
async function close(p){if(p.ws.readyState===WebSocket.CLOSED)return;const ended=new Promise(r=>p.ws.addEventListener('close',r,{once:true}));p.ws.close();await ended;}
async function action(p,action,item='',id='',more={}){
 await wait(Math.max(0,170-(Date.now()-(p.lastAction||0))));p.lastAction=Date.now();
 const n=p.notices.length,f=p.frames;
 p.send({t:'person',action,item,id,...more});
 if(action==='attack'){
  await until(()=>p.frames>f,3000,'attack snapshot');await wait(80);return p.notices[n]||{ok:true,text:''};
 }
 const notice=await until(()=>p.notices[n],5000,action+' notice');
 await until(()=>p.frames>f,3000,action+' snapshot').catch(()=>{});
 return notice;
}
async function walk(p,target,stop=.8){
 let route=findPath(manifest,point(p),target,{margin:.42,step:.5,stopDistance:stop,ship:p.state.ship,feet:p.state.players[p.id].y});
 for(const dest of route){const end=Date.now()+4500+dist(point(p),dest)*900;while(dist(point(p),dest)>.27){if(Date.now()>end)throw Error('walk stuck '+JSON.stringify({room:p.room,here:point(p),dest,target}));const here=point(p),dx=dest[0]-here[0],dz=dest[1]-here[1],d=Math.hypot(dx,dz);p.send({t:'motion',x:dx/d,z:dz/d,yaw:Math.atan2(-dx,-dz)});await wait(65);}}
 p.send({t:'motion',x:0,z:0,yaw:0});await wait(170);assert.ok(dist(point(p),target)<Math.max(2.2,stop+.6),'walk reached '+target);
}
async function near(p,id,range=1.8){const n=people(p)[id];if(dist(point(p),[n.x,n.z])>range)await walk(p,[n.x,n.z],Math.min(1.3,range-.3));}

try{
 await mkdir(saves,{recursive:true});
 port=await new Promise(r=>{const probe=net.createServer();probe.listen(0,'127.0.0.1',()=>{const p=probe.address().port;probe.close(()=>r(p));});});report.port=port;
 await fixture('qa-resource-race',{wild:{resources:{fruit:{stock:1,progress:0}}}});
 await fixture('qa-lifecycle',{elapsed:0,homes:[[6,-81],[1.8,-84.9]],wild:{settings:{firstRaid:20,warning:8,rest:3600,maxRaiders:1,maxCompanions:4,damageScale:.25},raid:{phase:'rest',nextAt:20,warningAt:0,startedAt:0,wave:0}}});
 const social='qa-social', aid=pid(social,0),bid=pid(social,1);
 await fixture(social,{homes:[[1.8,-84.9],[1.8,-84.9]],wild:{people:{'known-adult':{phase:'companion',sex:'female',age:28,tier:0,x:1.8,z:-86.0,yaw:-2.4,health:84,hunger:86,water:82,mood:65,weapon:'spear',shield:true,order:'guard',joinedAt:400,romanceOpen:false,relations:{[aid]:{trust:70,affection:45},[bid]:{trust:12,affection:2}}}}}});
 await boot();
 // Shared resource is consumed once by concurrent, independent players.
 let a=await connect('qa-resource-race',0),b=await connect('qa-resource-race',1);
 const grabs=await Promise.all([action(a,'gather','fruit'),action(b,'gather','fruit')]);
 assert.equal(grabs.filter(x=>x.ok).length,1);
 await until(()=>a.state.wildPeople.resources.fruit.stock===0&&b.state.wildPeople.resources.fruit.stock===0);
 assert.equal((a.state.survival.bag.apple||0)+(b.state.survival.bag.apple||0),1);
 report.cases.resourceRace={awards:grabs.filter(x=>x.ok).length,stock:0,bags:[a.state.survival.bag,b.state.survival.bag]};mark('resource-race-passed',report.cases.resourceRace);
 await Promise.all([close(a),close(b)]);
 // A real warning and first raid, followed by ordinary movement, combat and care.
 a=await connect('qa-lifecycle',0);b=await connect('qa-lifecycle',1);
 for(let i=0;i<2;i++)assert.ok((await action(a,'gather','fruit')).ok);
 await walk(a,herbsAt);for(let i=0;i<2;i++)assert.ok((await action(a,'gather','herbs')).ok);
 await walk(a,waterAt);for(let i=0;i<2;i++)assert.ok((await action(a,'gather','water')).ok);
 mark('real-sources-collected',{elapsed:a.state.elapsed,at:point(a),bag:a.state.survival.bag});
 const id=await until(()=>Object.keys(people(a))[0],20000,'first actual raid');
 await walk(a,[1.8,-84.9]);await until(()=>dist(point(a),[people(a)[id].x,people(a)[id].z])<2.1,25000,'raider approaches camp');
 const initialHealth=a.state.survival.health;
 const refused=await action(a,'capture','',id);assert.equal(refused.ok,false);assert.ok(a.state.survival.health<initialHealth);
 const captureFailedAt=a.state.elapsed;
 for(let i=0;i<7&&people(a)[id].phase!=='down';i++){
  await near(a,id,2.0);const me=a.state.players[a.id],n=people(a)[id],dx=n.x-me.x,dz=n.z-me.z;const yaw=Math.atan2(-dx,-dz),pitch=Math.atan2(1.14-(me.y+1.67),Math.hypot(dx,dz));
  a.send({t:'motion',x:0,z:0,yaw});await wait(140);await action(a,'attack','',id,{yaw,pitch});await wait(740);
 }
 assert.equal(people(a)[id].phase,'down');
 await until(()=>a.state.elapsed>captureFailedAt+5.1,8000,'capture retry cool-down');
 assert.ok((await action(a,'capture','',id)).ok);assert.equal(people(a)[id].phase,'captive');
 await until(()=>people(b)[id]?.phase==='captive');
 assert.ok(a.phases.includes('warning')&&a.phases.includes('active'),'real warning is observed before first raid');
 const beforeBag={...a.state.survival.bag};
 for(let i=0;i<2;i++)assert.ok((await action(a,'feed','apple',id)).ok);
 for(let i=0;i<2;i++)assert.ok((await action(a,'water','',id)).ok);
 assert.ok((await action(a,'treat','',id)).ok);
 assert.equal(a.state.survival.bag.apple,0);assert.equal(a.state.survival.bag.water,0);assert.equal(a.state.survival.bag.herb,1);
 await until(()=>people(a)[id].relation.food===2&&people(b)[id].relation.food===0);
 assert.ok(!('relations' in people(a)[id])&&!('relations' in people(b)[id]));
 assert.ok(!('romanceOpen' in people(a)[id])&&!('partner' in people(a)[id]));
 const early=await action(a,'invite','',id);assert.equal(early.ok,false);
 const treatedAt=a.state.elapsed;
 mark('capture-and-care-passed',{id,beforeBag,afterBag:a.state.survival.bag,aRelation:people(a)[id].relation,bRelation:people(b)[id].relation,careNeed:people(a)[id].careNeed,careDuration:people(a)[id].careDuration});
 // Refresh one player while the other remains online.
 const stableId=a.id;await close(a);a=await connect('qa-lifecycle',0);
 assert.equal(a.id,stableId);assert.equal(people(a)[id].relation.food,2);assert.equal(people(b)[id].relation.food,0);
 // Run the actual randomized care duration; do not mutate the live server clock/state.
 let lastProgress=0;
 while(!people(a)[id].readyToJoin){
  if(a.state.elapsed-treatedAt>50.5&&(a.state.survival.bag.herb||0)>0){assert.ok((await action(a,'treat','',id)).ok);mark('follow-up-treatment',{elapsed:a.state.elapsed});}
  if(Date.now()-lastProgress>15000){lastProgress=Date.now();mark('care-progress',{elapsed:a.state.elapsed,careSeconds:people(a)[id].careSeconds,needed:people(a)[id].careDuration,health:people(a)[id].health});}
  if(a.state.elapsed-treatedAt>145)throw Error('care never becomes ready '+JSON.stringify(people(a)[id]));
  await wait(500);
 }
 const ready=structuredClone(people(a)[id]);
 // Empty-room shutdown and restart preserve the same captive, care draw and relations.
 await Promise.all([close(a),close(b)]);await stop();
 const persisted=JSON.parse(await readFile(resolve(saves,'qa-lifecycle.json'),'utf8'));
 await writeFile(resolve(out,'lifecycle-before-restart.json'),JSON.stringify(persisted,null,2));
 await boot();a=await connect('qa-lifecycle',0);b=await connect('qa-lifecycle',1);
 const restored=people(a)[id], saved=persisted.wildPeople.people[id];
 assert.equal(restored.phase,'captive');assert.ok(Math.abs(restored.z-saved.z)<.01&&Math.abs(restored.x-saved.x)<.01,'negative world coordinates restore');
 assert.equal(restored.careDuration,saved.careDuration);assert.equal(restored.careNeed,saved.careNeed);assert.equal(restored.relation.food,2);assert.equal(people(b)[id].relation.food,0);
 assert.ok(restored.readyToJoin);assert.ok(a.state.elapsed-persisted.elapsed<.6,'empty room clock pauses');
 assert.ok((await action(a,'invite','',id)).ok);await until(()=>people(b)[id].phase==='companion');
 const forcedRomance=await action(a,'romance','',id);assert.equal(forcedRomance.ok,false,'new companion still requires free time and affection');
 report.cases.lifecycle={id,actualWarning:true,actualMeleeKnockout:true,weakCaptureRejected:true,consumedFromRealSources:beforeBag,careNeed:ready.careNeed,careDuration:ready.careDuration,careSecondsAtReady:ready.careSeconds,reconnectedIdentity:stableId,restoredPosition:[restored.x,restored.z],sharedPhase:people(b)[id].phase,aRelation:people(a)[id].relation,bRelation:people(b)[id].relation};mark('full-lifecycle-passed',report.cases.lifecycle);
 await Promise.all([close(a),close(b)]);
 // Distinct personal relationships, refusal cooldown and exclusive equipment transfers.
 a=await connect(social,0);b=await connect(social,1);const sid='known-adult';
 assert.equal(people(a)[sid].relation.trust,70);assert.equal(people(b)[sid].relation.trust,12);
 await near(a,sid);const refusal=await action(a,'romance','',sid);assert.ok(refusal.ok&&refusal.text.includes('婉拒'));
 await until(()=>people(a)[sid].relation.refusedUntil>a.state.elapsed&&people(b)[sid].relation.refusedUntil===0);
 const repeated=await action(a,'romance','',sid);assert.equal(repeated.ok,false);
 await near(b,sid);const take=await Promise.all([action(a,'take_equipment','',sid),action(b,'take_equipment','',sid)]);
 assert.equal(take.filter(x=>x.ok).length,1);await until(()=>!people(a)[sid].weapon&&!people(b)[sid].weapon);
 const winner=(a.state.survival.bag.spear||0)>0?a:b;
 assert.equal((a.state.survival.bag.spear||0)+(b.state.survival.bag.spear||0),1);
 assert.ok((await action(winner,'equip','spear')).ok);assert.equal(winner.state.survival.weapon,'spear');
 assert.ok((await action(winner,'give_equipment','spear',sid)).ok);assert.equal(winner.state.survival.weapon,'');assert.equal(winner.state.survival.bag.spear,0);assert.equal(people(winner)[sid].weapon,'spear');
 report.cases.social={aTrust:people(a)[sid].relation.trust,bTrust:people(b)[sid].relation.trust,aRefusedUntil:people(a)[sid].relation.refusedUntil,bRefusedUntil:people(b)[sid].relation.refusedUntil,exclusiveTransfer:true,equippedTransferClearsPlayer:true};mark('social-and-equipment-passed',report.cases.social);
 await Promise.all([close(a),close(b)]);await stop();
 assert.ok(!/SCRIPT ERROR:|Parse Error:|Invalid (access|call)/.test(logs),'no engine script errors');
 report.ok=true;
}catch(error){report.ok=false;report.errors.push(error.stack||String(error));console.error(error.stack||error);for(const p of allPeers.filter(p=>p.state))await writeFile(resolve(out,'last-'+p.room+'-'+p.index+'.json'),JSON.stringify({state:p.state,notices:p.notices.slice(-20),history:p.history},null,2));process.exitCode=1;}
finally{for(const p of allPeers)await close(p).catch(()=>{});await stop();await writeFile(resolve(out,'engine-output.txt'),logs);report.finished=new Date().toISOString();await writeFile(resolve(out,'report.json'),JSON.stringify(report,null,2));console.log('NETWORK_VALIDATION_RESULT',JSON.stringify({ok:report.ok,cases:Object.keys(report.cases),report:resolve(out,'report.json')}));}
