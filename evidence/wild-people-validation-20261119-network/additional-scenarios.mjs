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
 const romance='qa-romance-accept', aid=pid(romance,0),bid=pid(romance,1);
 await fixture(romance,{homes:[[1.8,-84.9],[1.8,-84.9]],wild:{people:{'consenting-adult':{phase:'companion',sex:'male',age:31,tier:0,x:1.8,z:-86,yaw:-2.4,health:84,hunger:86,water:82,mood:65,order:'guard',joinedAt:400,romanceOpen:false,relations:{[aid]:{trust:95,affection:90},[bid]:{trust:12,affection:2}}}}}});
 await fixture('qa-forager',{homes:[[-9.6,-62.5],[1.8,-84.9]],wild:{settings:{firstRaid:20,warning:8,rest:3600,maxRaiders:1,maxCompanions:4,damageScale:.25},raid:{phase:'rest',nextAt:1035,warningAt:0,startedAt:0,wave:0},resources:{fruit:{stock:1,progress:0},water:{stock:1,progress:0}},people:{'free-forager':{phase:'companion',sex:'female',age:29,tier:0,x:waterAt[0],z:waterAt[1],health:84,hunger:40,water:30,mood:65,weapon:'club',shield:false,order:'guard',joinedAt:400,romanceOpen:false}}}});
 await boot();
 let a=await connect(romance,0),b=await connect(romance,1);const sid='consenting-adult';
 assert.equal(people(a)[sid].relationship,'尚未恋爱');assert.equal(people(b)[sid].relationship,'尚未恋爱');
 assert.equal(people(a)[sid].relation.trust,95);assert.equal(people(a)[sid].relation.affection,90);
 await near(a,sid);const accepted=await action(a,'romance','',sid);assert.ok(accepted.ok&&accepted.text.includes('自愿接受'));
 await until(()=>people(a)[sid].relationship==='你的伴侣'&&people(b)[sid].relationship==='已有伴侣');
 assert.equal(people(b)[sid].relation.trust,12);assert.ok(!('partner' in people(b)[sid]));
 const savedRelation={a:people(a)[sid].relation,b:people(b)[sid].relation};
 await Promise.all([close(a),close(b)]);await stop();await boot();a=await connect(romance,0);b=await connect(romance,1);
 assert.equal(people(a)[sid].relationship,'你的伴侣');assert.equal(people(b)[sid].relationship,'已有伴侣');assert.equal(people(b)[sid].relation.trust,12);
 report.cases.romanceSuccess={result:accepted.text,prerequisites:{age:31,phase:'companion',joinedFor:600,trust:95,affection:90,mood:65},storedPersonalRelations:savedRelation,sharedPartnerPersists:true};mark('romance-success-and-restart-passed',report.cases.romanceSuccess);
 await Promise.all([close(a),close(b)]);
 a=await connect('qa-forager',0);b=await connect('qa-forager',1);const fid='free-forager';
 await until(()=>people(a)[fid].water>60&&a.state.wildPeople.resources.water.stock===0,5000,'autonomous actual water consumption');
 const afterWater=structuredClone(people(a)[fid]);mark('forager-drank-actual-water',{elapsed:a.state.elapsed,water:afterWater.water,stock:a.state.wildPeople.resources.water.stock,position:[afterWater.x,afterWater.z]});
 await until(()=>a.state.wildPeople.resources.fruit.stock===0&&people(a)[fid].hunger>55,40000,'forager walks to fruit and consumes one');
 const afterFood=structuredClone(people(a)[fid]);assert.ok(dist([afterFood.x,afterFood.z],[6,-81])<1.1);assert.equal(a.state.survival.bag.apple||0,0);assert.equal(b.state.survival.bag.apple||0,0);
 mark('forager-ate-actual-fruit',{elapsed:a.state.elapsed,hunger:afterFood.hunger,stock:a.state.wildPeople.resources.fruit.stock,position:[afterFood.x,afterFood.z]});
 const enemy=await until(()=>Object.keys(people(a)).find(id=>id!==fid&&people(a)[id].phase==='raider'),20000,'new raid for autonomous defense');
 await until(()=>people(a)[fid].help.includes('回防')||people(a)[enemy].health<people(a)[enemy].maxHealth,20000,'autonomous returns to defense');
 await until(()=>people(a)[enemy].health<people(a)[enemy].maxHealth&&people(a)[fid].health<84,20000,'actual companion combat damage on both sides');
 await until(()=>Math.abs(people(a)[fid].health-people(b)[fid].health)<.1,3000,'shared companion health');
 report.cases.foragingAndDefense={waterSourceConsumed:true,waterAfterDrink:afterWater.water,fruitSourceConsumed:true,foodPosition:[afterFood.x,afterFood.z],hungerAfterFood:afterFood.hunger,ordinaryPlayersDidNotFeed:true,raidPhase:a.state.wildPeople.raid.phase,enemy:people(a)[enemy],companion:people(a)[fid]};mark('autonomous-foraging-and-defense-passed',{elapsed:a.state.elapsed,enemyHealth:people(a)[enemy].health,companionHealth:people(a)[fid].health,companionMode:people(a)[fid].help});
 await Promise.all([close(a),close(b)]);await stop();assert.ok(!/SCRIPT ERROR:|Parse Error:|Invalid (access|call)/.test(logs),'no engine script errors');report.ok=true;
}catch(error){report.ok=false;report.errors.push(error.stack||String(error));console.error(error.stack||error);for(const p of allPeers.filter(p=>p.state))await writeFile(resolve(out,'last-'+p.room+'-'+p.index+'.json'),JSON.stringify({state:p.state,notices:p.notices.slice(-20),history:p.history},null,2));process.exitCode=1;}
finally{for(const p of allPeers)await close(p).catch(()=>{});await stop();await writeFile(resolve(out,'engine-output.txt'),logs);report.finished=new Date().toISOString();await writeFile(resolve(out,'report.json'),JSON.stringify(report,null,2));console.log('ADDITIONAL_VALIDATION_RESULT',JSON.stringify({ok:report.ok,cases:Object.keys(report.cases),report:resolve(out,'report.json')}));}
