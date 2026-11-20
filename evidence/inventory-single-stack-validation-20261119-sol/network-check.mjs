import assert from 'node:assert/strict';
import {mkdir,readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {out,root,playerId,fixture,startService,connect,close,person,provision,save,wait} from './qa-lib.mjs';
const report={started:new Date().toISOString(),mode:'Production Godot server and real WebSockets; disposable old-version fixtures; no runtime state modification',checks:[],events:[]};
const peers=[];let service;
const check=(name,value,data)=>{if(data)report.events.push({name,...data});assert.ok(value,name);report.checks.push(name);};
const bag=p=>p.state.survival.bag;
const open=async(room,index=0)=>{const p=await connect(service.base,room,index);peers.push(p);return p;};
const record=item=>({item,at:[2.54,.04,-87.95],surface:'ground'});
const max=2147483647;
try{
 await mkdir(resolve(out,'saves'),{recursive:true});
 const source=await readFile(resolve(root,'coop/survival.gd'),'utf8'),items=Object.keys(JSON.parse(source.match(/const ITEM_NAMES := (\{[^\n]+\})/)[1]));report.registry=items;
 const groups=[];for(let i=0;i<items.length;i+=6)groups.push(items.slice(i,i+6));
 for(let i=0;i<groups.length;i++){const group=groups[i],contents=Object.fromEntries(group.map(item=>[item,10])),provisions=Object.fromEntries(group.map(item=>['same-'+item,record(item)]));if(i===0)provisions.newWater=record('water');await fixture('stack-registry-'+i,{states:[{bag:contents},{}],extra:{provisions}});}
 const twelve=items.slice(0,12),room12='stack-twelve';await fixture(room12,{states:[{bag:Object.fromEntries(twelve.map(item=>[item,10]))},{}],extra:{backpackOwner:playerId(room12,0),provisions:{sameApple:record('apple'),newTarp:record('tarp')}}});
 await fixture('stack-upper',{states:[{bag:{apple:max}},{}],extra:{provisions:{extraApple:record('apple')}}});
 const npc={id:'care',name:'堆叠验收',sex:'female',age:30,tier:0,phase:'captive',x:4.6,z:-83,yaw:0,health:52,clip:'Captive',clipAt:1000,water:40,hunger:40,mood:50,disease:10,legL:20};
 await fixture('stack-use',{homes:[[4.6,-81.4],[4.6,-81.4]],states:[{bag:{apple:10,herb:10,cap:10,club:10,water:10,wood:10},worn:{cap:false,jacket:true,pants:true}},{}],wild:{people:{care:npc}}});
 service=await startService();report.service=service.base;
 for(let i=0;i<groups.length;i++){let a=await open('stack-registry-'+i);for(const item of groups[i]){check(item+' old quantity10 retained',bag(a)[item]===10);assert.equal((await provision(a,'take','', 'same-'+item)).ok,true);check(item+' repeated pickup merges to11',bag(a)[item]===11);}
  if(i===0){const rejected=await provision(a,'take','','newWater');check('six distinct types reject seventh without erasing object',!rejected.ok&&a.state.provisions.newWater?.item==='water'&&!(bag(a).water>0));const b=await open('stack-registry-0',1);assert.equal((await provision(b,'take','','newWater')).ok,true);check('rejected seventh type remains claimable by teammate',bag(b).water===1);await close(b);}
  await close(a);a=await open('stack-registry-'+i);check('registry group '+i+' reconnect keeps every total',groups[i].every(item=>bag(a)[item]===11));await close(a);
 }
 let a=await open(room12),b=await open(room12,1);check('twelve types all quantities survive load',twelve.every(item=>bag(a)[item]===10));assert.equal((await provision(a,'take','','sameApple')).ok,true);const full12=await provision(a,'take','','newTarp');check('full12 allows existing type but retains rejected13th object',bag(a).apple===11&&!full12.ok&&a.state.provisions.newTarp?.item==='tarp');assert.equal((await provision(b,'take','','newTarp')).ok,true);check('13th object not lost after refusal',bag(b).tarp===1);await close(a);await close(b);
 a=await open('stack-upper');b=await open('stack-upper',1);const over=await provision(a,'take','','extraApple');check('legal upper bound preserved and overflow cannot consume world item',bag(a).apple===max&&!over.ok&&Boolean(a.state.provisions.extraApple));assert.equal((await provision(b,'take','','extraApple')).ok,true);assert.equal((await provision(a,'eat','apple')).ok,true);check('eat at upper limit consumes exactly one',bag(a).apple===max-1);await close(a);await close(b);
 a=await open('stack-use');b=await open('stack-use',1);assert.equal((await provision(a,'eat','apple')).ok,true);check('eat consumes one from10',bag(a).apple===9);assert.equal((await person(a,'feed','apple','care')).ok,true);check('NPC feed consumes only one',bag(a).apple===8);assert.equal((await person(a,'treat','','care')).ok,true);check('NPC herb treatment consumes only one',bag(a).herb===9);
 assert.equal((await provision(a,'wear','cap')).ok,true);check('wear consumes one cap and keeps other9',bag(a).cap===9&&a.state.survival.worn.cap);assert.equal((await provision(a,'remove_worn','cap')).ok,true);check('remove worn merges cap at full type capacity',bag(a).cap===10&&!a.state.survival.worn.cap);
 assert.equal((await person(a,'equip','club')).ok,true);check('equip weapon does not consume its stack',bag(a).club===10&&a.state.survival.weapon==='club');assert.equal((await provision(a,'drop','club')).ok,true);const club=Object.keys(a.state.provisions).find(id=>a.state.provisions[id].item==='club');check('drop emits one and keeps9 equipped',bag(a).club===9&&a.state.survival.weapon==='club'&&Boolean(club));assert.equal((await provision(b,'take','',club)).ok,true);check('dropped stack transfers a single weapon',bag(a).club===9&&bag(b).club===1);
 assert.equal((await person(a,'water','','care')).ok,true);check('water NPC supply still consumes one',bag(a).water===9);check('material stack and no-mode state retained',bag(a).wood===10&&!Object.hasOwn(a.state.survival,'combatMode'));await save('single-use-states.json',{a:a.state,b:b.state});await close(a);await close(b);
 await service.stop();service=await startService();
 for(let i=0;i<groups.length;i++){a=await open('stack-registry-'+i);check('process restart registry group '+i+' preserves all quantities',groups[i].every(item=>bag(a)[item]===11));await close(a);}
 a=await open(room12);check('process restart preserves full12 inventory',twelve.every(item=>bag(a)[item]===(item==='apple'?11:10)));await close(a);report.ok=true;
}catch(e){report.ok=false;report.error=e.stack||String(e);report.failureContext=peers.filter(p=>p.ws.readyState!==WebSocket.CLOSED).map(p=>({room:p.room,notices:p.notices,state:p.state,actionTrace:p.actionTrace}));console.error(report.error);process.exitCode=1;}
finally{for(const p of peers)await close(p);if(service)await service.stop();report.finished=new Date().toISOString();await save('network-report.json',report);console.log('STACK_NETWORK',JSON.stringify({ok:report.ok,checks:report.checks.length,error:report.error}));}
