import assert from 'node:assert/strict';
import {mkdir,readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {out,root,fixture,startService,connect,close,person,provision,act,save,wait,until,playerId} from './qa-lib.mjs';

const report={started:new Date().toISOString(),mode:'Independent real WebSockets against production server; authored disposable fixtures; no runtime state setters',checks:[],events:[]};
const peers=[];let service;
const note=(name,data)=>{report.events.push({name,...data});console.log(name,JSON.stringify(data));};
const check=(name,value)=>{assert.ok(value,name);report.checks.push(name);};
const open=async(room,index)=>{const p=await connect(service.base,room,index);peers.push(p);return p;};
const bag=p=>p.state.survival.bag;
const tableWater=p=>Object.entries(p.state.provisions).filter(([,v])=>v.item==='water');
async function persisted(room){return JSON.parse(await readFile(resolve(out,'saves',room+'.json'),'utf8'));}
function materialTotals(data){const totals={wood:0,tarp:0};for(const state of Object.values(data.survival||{}))for(const k of Object.keys(totals))totals[k]+=state.bag?.[k]||0;for(const v of Object.values(data.provisions||{}))if(v.item in totals)totals[v.item]++;return totals;}

try{
 await mkdir(resolve(out,'saves'),{recursive:true});
 const water=[-10.4,-62.5],nearNPC=[4.6,-81.4];
 await fixture('water-gather',{homes:[water,water],wild:{resources:{water:{stock:16,progress:0}}}});
 await fixture('water-race',{homes:[water,water],wild:{resources:{water:{stock:1,progress:0}}}});
 const world=JSON.parse(await readFile(resolve(root,'coop/world.json'),'utf8'));
 for(const item of ['wood','tarp'])await fixture('material-pick-'+item,{homes:[[world.sites[item][0]+1,world.sites[item][1]],[world.sites[item][0]+1,world.sites[item][1]]],quest:{wood:false,tarp:false,repaired:false}});
 await fixture('material-use',{quest:{wood:false,tarp:false,repaired:false},states:[{bag:{wood:2,tarp:2}},{bag:{wood:3,tarp:3}}]});
 await fixture('material-facility',{homes:[[1.8,-84.9],[1.8,-84.9]],states:[{bag:{wood:2,tarp:2}},{bag:{wood:3,tarp:3}}],wild:{facility:50}});
 await fixture('material-transfer',{quest:{wood:false,tarp:false,repaired:false},states:[{bag:{wood:1,tarp:1}},{}]});
 await fixture('material-legacy',{quest:{wood:true,tarp:true,repaired:false}});
 await fixture('material-old-repaired',{quest:{wood:true,tarp:true,repaired:true}});
 const npc={id:'person-1',name:'验收住民',sex:'female',age:30,tier:0,phase:'down',x:4.6,z:-83,yaw:0,health:84,stun:0,stunUntil:1100,clip:'Down',clipAt:1000,legL:0,legR:0,water:42,hunger:80,mood:70,weapon:'',shield:false};
 for(const mode of ['subdue','lethal'])await fixture('weapon-old-'+mode,{homes:[nearNPC,nearNPC],states:[{bag:{spear:1,club:1},weapon:'spear',combatMode:mode},{}],wild:{people:{'person-1':npc}}});
 await fixture('npc-water-care',{homes:[nearNPC,nearNPC],states:[{bag:{water:10}},{}],wild:{people:{'person-1':{...npc,phase:'captive',stunUntil:0,clip:'Captive',water:42}}}});
 await fixture('npc-real-source',{wild:{people:{'person-1':{...npc,phase:'companion',clip:'Guard',x:water[0],z:water[1],water:30,hunger:80,health:84,stunUntil:0,joinedAt:900}},resources:{water:{stock:1,progress:0}}}});
 service=await startService();report.ownService=service.base;

 let a=await open('water-gather',0),b=await open('water-gather',1);
 for(let i=1;i<=10;i++){assert.equal((await person(a,'gather','water')).ok,true);if([4,7,10].includes(i)){check('actual gathered '+i+' waters retained',bag(a).water===i);note('gather-stage',{count:i,bag:bag(a),source:a.state.wildPeople.resources.water});}}
 check('water source actually decremented',a.state.wildPeople.resources.water.stock===6);
 await close(a);a=await open('water-gather',0);check('same identity reconnect keeps all 10 water',bag(a).water===10);
 await save('gather-before-restart.json',{a:a.state,b:b.state});await close(a);await close(b);

 a=await open('water-race',0);b=await open('water-race',1);
 const race=await Promise.all([person(a,'gather','water'),person(b,'gather','water')]);await wait(200);
 check('last real water source issued once',race.filter(r=>r.ok).length===1&&(bag(a).water||0)+(bag(b).water||0)===1&&a.state.wildPeople.resources.water.stock===0);
 note('source-race',{race,a:a.state.survival,b:b.state.survival});await close(a);await close(b);

 for(const item of ['wood','tarp']){a=await open('material-pick-'+item,0);b=await open('material-pick-'+item,1);const picked=await act(a,item),second=await act(b,item);note('material-pick-'+item,{picked,second,a:bag(a),b:bag(b),players:a.state.players});check('pickup '+item+' belongs only to A',picked.ok&&!second.ok&&bag(a)[item]===1&&!(bag(b)[item]>0));await close(a);await close(b);}
 a=await open('material-use',0);b=await open('material-use',1);const built=await act(a,'repair');await wait(150);
 check('repair consumes only action owner material',built.ok&&bag(a).wood===1&&bag(a).tarp===1&&bag(b).wood===3&&bag(b).tarp===3&&a.state.quest.repaired);
 note('material-use',{built,a:a.state.survival,b:b.state.survival,quest:a.state.quest});await close(a);await close(b);

 a=await open('material-facility',0);b=await open('material-facility',1);const facilityFixed=await person(a,'repair_facility');await wait(150);check('facility repair consumes only owner wood and tarp',facilityFixed.ok&&a.state.wildPeople.facility===75&&bag(a).wood===1&&bag(a).tarp===1&&bag(b).wood===3&&bag(b).tarp===3);note('material-facility',{facilityFixed,a:a.state.survival,b:b.state.survival,facility:a.state.wildPeople.facility});await close(a);await close(b);

 a=await open('material-transfer',0);b=await open('material-transfer',1);check('B cannot spend A material',!(await act(b,'repair')).ok);
 for(const item of ['wood','tarp']){assert.equal((await provision(a,'drop',item)).ok,true);const id=Object.keys(a.state.provisions).find(id=>a.state.provisions[id].item===item);assert.ok(id);assert.equal((await provision(b,'take','',id)).ok,true);}
 check('drop and pickup transfer actual materials',!(bag(a).wood>0)&&!(bag(a).tarp>0)&&bag(b).wood===1&&bag(b).tarp===1);
 const rebuilt=await act(b,'repair');check('receiver can repair from transferred material',rebuilt.ok&&bag(b).wood===0&&bag(b).tarp===0);await close(a);await close(b);

 a=await open('material-legacy',0);b=await open('material-legacy',1);await close(a);await close(b);const legacyBefore=await persisted('material-legacy');
 check('old unspent material migrated to one real copy',JSON.stringify(materialTotals(legacyBefore))===JSON.stringify({wood:1,tarp:1}));note('legacy-before-restart',{totals:materialTotals(legacyBefore),quest:legacyBefore.quest,keys:Object.keys(legacyBefore)});
 a=await open('material-old-repaired',0);b=await open('material-old-repaired',1);await close(a);await close(b);check('already repaired old room does not duplicate spent material',JSON.stringify(materialTotals(await persisted('material-old-repaired')))===JSON.stringify({wood:0,tarp:0}));

 for(const mode of ['subdue','lethal']){
  a=await open('weapon-old-'+mode,0);b=await open('weapon-old-'+mode,1);
  check('old '+mode+' mode omitted from public personal state',!Object.hasOwn(a.state.survival,'combatMode'));
  const stance=await person(a,'stance');check('old stance command cannot toggle hidden mode ('+mode+')',!stance.ok);
  check('cannot equip missing weapon ('+mode+')',!(await person(b,'equip','spear')).ok&&b.state.survival.weapon==='');
  const n=a.state.wildPeople.people['person-1'],p=a.state.players[a.id],target=[n.x-.14,.23,n.z-.50],dx=target[0]-p.x,dz=target[2]-p.z,yaw=Math.atan2(-dx,-dz),pitch=Math.atan2(target[1]-(p.y+1.67),Math.hypot(dx,dz));
  a.send({t:'motion',x:0,z:0,yaw});await wait(150);const hit=await person(a,'attack','','',{yaw,pitch});await wait(150);const injured=a.state.wildPeople.people['person-1'];
  check('equipped spear is sharp regardless old '+mode+' field',hit.ok&&injured.health<84&&injured.legL+injured.legR>0&&injured.stun===0);
  note('weapon-'+mode,{hit,before:n,after:injured,personal:a.state.survival});await close(a);await close(b);
 }
 a=await open('npc-water-care',0);const npcBefore=a.state.wildPeople.people['person-1'].water;assert.equal((await person(a,'water','','person-1')).ok,true);check('NPC supply still consumes real carried water',bag(a).water===9&&a.state.wildPeople.people['person-1'].water>npcBefore+30);await close(a);
 a=await open('npc-real-source',0);await until(()=>a.state.wildPeople.resources.water.stock===0,5000,'companion actual source water');check('companion still consumes real creek stock',a.state.wildPeople.people['person-1'].water>60);note('npc-real-source',{resources:a.state.wildPeople.resources,person:a.state.wildPeople.people['person-1']});await close(a);

 await service.stop();service=await startService();
 a=await open('water-gather',0);check('process restart restores 10 water',bag(a).water===10);await close(a);
 a=await open('material-use',0);b=await open('material-use',1);check('material repair and private remainder survive restart',a.state.quest.repaired&&bag(a).wood===1&&bag(a).tarp===1&&bag(b).wood===3&&bag(b).tarp===3);await close(a);await close(b);
 a=await open('material-legacy',1);b=await open('material-legacy',0);await close(a);await close(b);const legacyAfter=await persisted('material-legacy');check('legacy migration is once across reverse join and restart',JSON.stringify(materialTotals(legacyAfter))===JSON.stringify({wood:1,tarp:1}));await save('legacy-migration-states.json',{before:legacyBefore,after:legacyAfter});
 report.ok=true;
}catch(e){report.ok=false;report.failureContext=peers.filter(p=>p.ws.readyState!==WebSocket.CLOSED).map(p=>({room:p.room,index:p.index,actionTrace:p.actionTrace,state:p.state}));report.error=e.stack||String(e);console.error(report.error);process.exitCode=1;}
finally{for(const p of peers)await close(p);if(service)await service.stop();report.finished=new Date().toISOString();await save('network-report.json',report);console.log('NETWORK_RESULT',JSON.stringify({ok:report.ok,checks:report.checks.length,error:report.error}));}
