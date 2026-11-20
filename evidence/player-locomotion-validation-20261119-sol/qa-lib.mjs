import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import net from 'node:net';
import {findPath} from '../../scripts/coop-test-path.mjs';

export const root=fileURLToPath(new URL('../../',import.meta.url));
export const out=fileURLToPath(new URL('.',import.meta.url));
export const tokens=['12'.repeat(16),'34'.repeat(16)];
export const playerId=(room,index)=>createHash('sha256').update(room+':'+tokens[index]).digest('hex').slice(0,16);
export const wait=ms=>new Promise(r=>setTimeout(r,ms));
export async function until(fn,ms=10000,label='condition'){const end=Date.now()+ms;while(Date.now()<end){const result=await fn();if(result)return result;await wait(50);}throw Error('Timed out '+label);}
export async function save(name,data){await writeFile(resolve(out,name),JSON.stringify(data,null,2));}
export function personal(extra={}){return {health:100,hunger:80,water:40,mood:65,bag:{},worn:{cap:true,jacket:true,pants:true},...extra};}
export async function fixture(room,{homes=[[2.54,-87.95],[2.54,-87.95]],states=[{},{}],quest={wood:false,tarp:false,repaired:true},wild={},extra={}}={}){
 const data={version:1,elapsed:1000,groveStartedAt:0,quest,homes:{},survival:{},wildPeople:{version:1,settings:{firstRaid:7200,rest:3600,maxRaiders:1,maxCompanions:4,damageScale:.25},raid:{phase:'rest',nextAt:9000},people:{},...wild},...extra};
 for(let i=0;i<2;i++){data.homes[playerId(room,i)]={x:homes[i][0],z:homes[i][1],yaw:0};data.survival[playerId(room,i)]=personal(states[i]);}
 await writeFile(resolve(out,'saves',room+'.json'),JSON.stringify(data));return data;
}
async function freePort(){return new Promise((r,j)=>{const s=net.createServer();s.once('error',j);s.listen(0,'127.0.0.1',()=>{const p=s.address().port;s.close(()=>r(p));});});}
export async function startService(run='network'){
 await mkdir(resolve(out,'saves'),{recursive:true});
 let source=await readFile(resolve(root,'scripts/coop-serve.mjs'),'utf8');
 source=source.replace("const root=fileURLToPath(new URL('..',import.meta.url));",'const root='+JSON.stringify(root)+';').replace("mkdirSync(save,{recursive:true});mkdirSync(resolve(root,'.cache'),{recursive:true});","mkdirSync(save,{recursive:true});").replace("resolve(root,'.cache',port===4184?'coop-room.log':'coop-room-'+port+'.log')","resolve(save,'"+run+"-room-server.log')");
 await writeFile(resolve(out,'serve-owned.mjs'),source);
 const port=await freePort(),roomPort=await freePort();let output='';
 const child=spawn(process.execPath,[resolve(out,'serve-owned.mjs')],{env:{...process.env,COOP_PORT:String(port),COOP_ROOM_PORT:String(roomPort),COOP_SAVE_DIR:resolve(out,'saves'),COOP_SITE_DIR:process.env.LOCOMOTION_QA_SITE_DIR||resolve(root,'dist/coop')},stdio:['ignore','pipe','pipe']});
 for(const stream of [child.stdout,child.stderr])stream.on('data',d=>output+=String(d));
 const service={base:'http://127.0.0.1:'+port,port,roomPort,child,async stop(){if(child.exitCode===null&&child.signalCode===null){const exit=new Promise(r=>child.once('exit',r));child.kill('SIGTERM');await Promise.race([exit,wait(8000).then(()=>{throw Error('Owned service shutdown timeout');})]);}await writeFile(resolve(out,run+'-service-output.txt'),output);}};
 await until(async()=>{if(child.exitCode!==null)throw Error('Service exited: '+output);try{return(await(await fetch(service.base+'/health')).json()).ready;}catch{return false;}},20000,'own service ready');return service;
}
export async function connect(base,room,index){
 const ws=new WebSocket(base.replace(/^http/,'ws')+'/room');const p={ws,room,index,id:playerId(room,index),state:null,frames:0,notices:[],send:m=>ws.send(JSON.stringify(m))};
 ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.t==='snapshot'){p.state=m;p.frames++;}if(m.t==='notice')p.notices.push(m);if(m.t==='reject')p.rejected=m;};
 await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j;});p.send({t:'join',room,token:tokens[index],session:'inventory-single-stack-validation-'+index});
 p.keep=setInterval(()=>{if(ws.readyState===WebSocket.OPEN)p.send({t:'ping'});},4000);ws.onclose=()=>clearInterval(p.keep);
 await until(()=>{if(p.rejected)throw Error(JSON.stringify(p.rejected));return p.state;},10000,'join '+room+'/'+index);return p;
}
export async function close(p){if(!p)return;clearInterval(p.keep);if(p.ws.readyState===WebSocket.CLOSED)return;const end=new Promise(r=>p.ws.addEventListener('close',r,{once:true}));p.ws.close();await Promise.race([end,wait(3000)]);}
export async function command(p,type,fields){await wait(Math.max(0,180-(Date.now()-(p.lastAction||0))));const trace={type,fields,sent:Date.now(),elapsed:p.state?.elapsed};(p.actionTrace??=[]).push(trace);const count=p.notices.length,frame=p.frames;p.send({t:type,...fields});const notice=await until(()=>p.notices[count],5000,JSON.stringify(fields));p.lastAction=Date.now();trace.reply=p.lastAction;trace.notice=notice;if(notice.ok)await until(()=>p.frames>frame,3000,'authoritative action snapshot');return notice;}
export const person=(p,action,item='',id='',more={})=>command(p,'person',{action,item,id,...more});
export const provision=(p,action,item='',id='')=>command(p,'provision',{action,item,id});
export const act=(p,site)=>command(p,'act',{site});
export const point=p=>{const a=p.state.players[p.id];return [a.x,a.z];};
export async function walk(p,target,stop=.65){const world=JSON.parse(await readFile(resolve(root,'coop/world.json'),'utf8')),distance=(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1]);
 const route=findPath(world,point(p),target,{margin:.42,step:.5,stopDistance:stop,ship:p.state.ship,feet:p.state.players[p.id].y});
 for(const dest of route){const deadline=Date.now()+5000+distance(point(p),dest)*900;while(distance(point(p),dest)>.27){if(Date.now()>deadline)throw Error('Walk stuck '+JSON.stringify({here:point(p),dest,target}));const here=point(p),dx=dest[0]-here[0],dz=dest[1]-here[1],d=Math.hypot(dx,dz);p.send({t:'motion',x:dx/d,z:dz/d,yaw:Math.atan2(-dx,-dz)});await wait(65);}}
 p.send({t:'motion',x:0,z:0,yaw:0});await wait(200);assert.ok(distance(point(p),target)<stop+.6);return route;
}
