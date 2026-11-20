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
 const room='qa-lifecycle',original=JSON.parse(await readFile(resolve(out,'../run-3/saves/qa-lifecycle.json'),'utf8'));
 await writeFile(resolve(saves,room+'.json'),JSON.stringify(original));await boot();
 const a=await connect(room,0),b=await connect(room,1),id='person-1';const initial=structuredClone(people(a)[id]);mark('original-failure-seed-loaded',{elapsed:a.state.elapsed,x:initial.x,z:initial.z,player:point(a)});
 await until(()=>dist(point(a),[people(a)[id].x,people(a)[id].z])<2.1,15000,'original raider now reaches camp');
 const reached=structuredClone(people(a)[id]);
 for(let i=1;i<a.history.length;i++){const old=a.history[i-1],now=a.history[i];if(!old.people[id]||!now.people[id])continue;const n=now.people[id],o=old.people[id];assert.ok(dist([o.x,o.z],[n.x,n.z])<2.21*(now.elapsed-old.elapsed)+.035,'continuous bounded motion, no teleport');}
 mark('original-stall-now-cleared',{elapsed:a.state.elapsed,x:reached.x,z:reached.z,seconds:a.state.elapsed-original.elapsed});
 for(let i=0;i<7&&people(a)[id].phase!=='down';i++){await near(a,id,2);const me=a.state.players[a.id],n=people(a)[id],dx=n.x-me.x,dz=n.z-me.z,yaw=Math.atan2(-dx,-dz),pitch=Math.atan2(1.14-(me.y+1.67),Math.hypot(dx,dz));a.send({t:'motion',x:0,z:0,yaw});await wait(140);await action(a,'attack','',id,{yaw,pitch});await wait(740);}
 assert.equal(people(a)[id].phase,'down');assert.ok((await action(a,'capture','',id)).ok);await until(()=>people(b)[id].phase==='captive');
 report.cases.originalNavigationRegression={initial:[initial.x,initial.z],reached:[reached.x,reached.z],movementBoundVerified:true,capturedThroughOrdinaryAttackAndCapture:true,finalPhase:people(b)[id].phase};
 await Promise.all([close(a),close(b)]);await stop();assert.ok(!/SCRIPT ERROR:|Parse Error:|Invalid (access|call)/.test(logs));report.ok=true;
}catch(error){report.ok=false;report.errors.push(error.stack||String(error));console.error(error.stack||error);for(const p of allPeers.filter(p=>p.state))await writeFile(resolve(out,'last-'+p.room+'-'+p.index+'.json'),JSON.stringify({state:p.state,notices:p.notices.slice(-20),history:p.history},null,2));process.exitCode=1;}
finally{for(const p of allPeers)await close(p).catch(()=>{});await stop();await writeFile(resolve(out,'engine-output.txt'),logs);report.finished=new Date().toISOString();await writeFile(resolve(out,'report.json'),JSON.stringify(report,null,2));console.log('NAVIGATION_REGRESSION_RESULT',JSON.stringify({ok:report.ok,cases:report.cases,report:resolve(out,'report.json')}));}
