import assert from 'node:assert/strict';
import {mkdir,readFile,stat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {chromium} from 'playwright';
import {prepareOffscreenPage,browserTestOptions,clickCanvasPoint} from '../../scripts/coop-browser-controls.mjs';
import {out,root,tokens,fixture,startService,save,wait,until,connect,close,walk} from './qa-lib.mjs';

const report={started:new Date().toISOString(),mode:'Unified inventory functional QA: headless Chrome Metal, ordinary F/Tab/mouse operations; no performance sampling',checks:[],states:{},errors:[]};
let service,browser;const pages=[];
const check=(name,value)=>{assert.ok(value,name);report.checks.push(name);};
const state=page=>page.evaluate(()=>CooperStatus);
const inventory=s=>s.inventoryPanel;
const slots=(s,item)=>inventory(s).slots.filter(slot=>slot.visible!==false&&slot.item===item);
const qty=slot=>slot.quantity;
async function snapshot(page,name){const s=await state(page);report.states[name]=s;await page.screenshot({path:resolve(out,name+'.png')});await save(name+'-state.json',s);return s;}
async function enter(page){await wait(350);const p=await page.evaluate(()=>{const [x,y,w,h]=CooperStatus.enterRect;return [(x+w/2)/CooperStatus.viewport[0],(y+h/2)/CooperStatus.viewport[1]];});await clickCanvasPoint(page,p);await page.waitForFunction(()=>document.pointerLockElement&&CooperStatus.locked,null,{timeout:8000});}
async function open(room,index=0){const context=await browser.newContext({viewport:{width:1280,height:720},deviceScaleFactor:1});await context.addInitScript(t=>sessionStorage.setItem('cooper-identity',t),tokens[index]);const page=await context.newPage();await prepareOffscreenPage(page);page.on('pageerror',e=>report.errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')report.errors.push(m.text());});await page.goto(service.base+'/coop/?room='+room,{waitUntil:'domcontentloaded'});await page.waitForFunction(()=>window.CooperStatus?.ready,null,{timeout:90000});await enter(page);pages.push({page,context,room,index});return page;}
async function clickRect(page,rect){const [x,y,w,h]=rect;assert.ok(w>0&&h>0);await page.mouse.click(x+w/2,y+h/2);await wait(350);}
async function select(page,item){if(!(await state(page)).backpackOpen){await page.keyboard.press('Tab');await page.waitForFunction(()=>CooperStatus.backpackOpen);}const s=await state(page),slot=inventory(s).slots.find(slot=>slot.visible!==false&&slot.item===item);assert.ok(slot,'visible slot '+item);await clickRect(page,slot.rect);}
async function button(page,key){const a=inventory(await state(page)).actions[key];assert.ok(a?.visible&&!a.disabled,'ordinary action available '+key);await clickRect(page,a.rect);}
async function closePanel(page){if((await state(page)).backpackOpen|| (await state(page)).peopleOpen)await page.keyboard.press('Escape');if(!(await state(page)).locked)await enter(page);}
async function aim(page,at){for(let i=0;i<5;i++){const s=await state(page),dx=at[0]-s.x,dz=at[2]-s.z,yaw=Math.atan2(-dx,-dz),pitch=Math.atan2(at[1]-(s.y+1.67),Math.hypot(dx,dz)),dy=Math.atan2(Math.sin(yaw-s.yaw),Math.cos(yaw-s.yaw)),dp=pitch-s.pitch;if(Math.abs(dy)<.004&&Math.abs(dp)<.004)return;await page.evaluate(([mx,my])=>{const c=document.getElementById('canvas'),b=c.getBoundingClientRect();c.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,pointerType:'mouse',movementX:Math.round(mx*b.width/c.width),movementY:Math.round(my*b.height/c.height),clientX:b.x+b.width/2,clientY:b.y+b.height/2}));},[-dy/.00215,-dp/.00215]);await wait(300);}}
async function targetProvision(page,id){await closePanel(page);const record=(await state(page)).provisions[id];assert.ok(record);await aim(page,[record.at[0],record.at[1]+.05,record.at[2]]);await page.waitForFunction(id=>CooperStatus.foodTarget===id,id,{timeout:4000});}
const waterOnTable=s=>Object.entries(s.provisions).filter(([,r])=>r.item==='water'&&r.surface==='table');
try{
 await mkdir(resolve(out,'saves'),{recursive:true});
 const fillers={bread:10,cap:10,club:10,water:10,wood:10};
 const cases=[{room:'stack-apple-ui',item:'apple',source:'fruit',at:[6,-81],initial:3,target:10},{room:'stack-herb-low-ui',item:'herb',source:'herbs',at:[6.4,-83.8],initial:3,target:7},{room:'stack-herb-high-ui',item:'herb',source:'herbs',at:[6.4,-83.8],initial:9,target:10}];
 report.authoredInitialFixtures=[];
 for(const c of cases){const data=await fixture(c.room,{homes:[c.at,c.at],states:[{bag:{...fillers,[c.item]:c.initial},worn:{cap:false,jacket:true,pants:true}},{}]});report.authoredInitialFixtures.push({room:c.room,item:c.item,initial:c.initial,target:c.target,path:'saves/'+c.room+'.json',initialState:data.survival});}
 const site=process.env.INVENTORY_QA_SITE_DIR||resolve(root,'dist/coop-resource-fix'),pck=await readFile(resolve(site,'index.pck'));report.package={site,bytes:pck.length,mtime:(await stat(resolve(site,'index.pck'))).mtime.toISOString(),sha256:createHash('sha256').update(pck).digest('hex')};
 service=await startService('browser');report.service=service.base;browser=await chromium.launch(browserTestOptions({metal:true}));
 const remaining={};
 for(const c of cases){const page=await open(c.room);await page.waitForFunction(key=>CooperStatus.sourceTarget===key,c.source);check(c.room+' initial total preserved', (await state(page)).survival.bag[c.item]===c.initial);
  for(let count=c.initial+1;count<=c.target;count++){await page.keyboard.press('f');await page.waitForFunction(([item,count])=>CooperStatus.survival.bag[item]===count,[c.item,count]);await wait(180);if([4,7,10].includes(count)){await select(page,c.item);const s=await snapshot(page,c.item+'-'+count);check(c.item+' '+count+' occupies one slot with full other five kinds',slots(s,c.item).length===1&&qty(slots(s,c.item)[0])===count&&s.inventoryPanel.slots.filter(s=>s.item).length===6);await closePanel(page);}}
  await page.reload({waitUntil:'domcontentloaded'});await page.waitForFunction(()=>window.CooperStatus?.ready,null,{timeout:90000});await enter(page);await select(page,c.item);let s=await snapshot(page,c.room+'-refresh');check(c.room+' refresh keeps one entry and total',slots(s,c.item).length===1&&qty(slots(s,c.item)[0])===c.target);
  if(c.item==='apple'){
   await button(page,'eat');await page.waitForFunction(()=>CooperStatus.survival.bag.apple===9);await button(page,'drop');await page.waitForFunction(()=>CooperStatus.survival.bag.apple===8);s=await state(page);const id=Object.keys(s.provisions).find(id=>s.provisions[id].item==='apple'&&s.provisions[id].surface==='ground');assert.ok(id);await targetProvision(page,id);await page.keyboard.press('e');await page.waitForFunction(()=>CooperStatus.survival.bag.apple===9);await select(page,'apple');s=await snapshot(page,'apple-eat-drop-pick-single-stack');check('eat and drop/pick use one apple at a time',slots(s,'apple').length===1&&qty(slots(s,'apple')[0])===9&&!s.provisions[id]);
   await select(page,'water');const before=(await state(page)).survival.water;await button(page,'drink');await page.waitForFunction(()=>CooperStatus.survival.bag.water===9);check('water still drinks exactly one', (await state(page)).survival.water>before+30);
   await select(page,'cap');await button(page,'wear');await page.waitForFunction(()=>CooperStatus.survival.worn.cap&&CooperStatus.survival.bag.cap===9);s=await state(page);await clickRect(page,s.equipmentTabRect);await wait(500);await snapshot(page,'cap-stack-equipped-current-model');check('stacked cap wears one without consuming other9', (await state(page)).survival.bag.cap===9);
  }
  remaining[c.room]=c.item==='apple'?9:c.target;await pages.find(p=>p.page===page).context.close();await wait(250);const peer=await connect(service.base,c.room,0);try{check(c.room+' reconnect preserves count',peer.state.survival.bag[c.item]===remaining[c.room]);}finally{await close(peer);}
 }
 await browser.close();browser=null;await service.stop();service=await startService('browser-restart');
 for(const c of cases){const peer=await connect(service.base,c.room,0);try{check(c.room+' process restart preserves quantity',peer.state.survival.bag[c.item]===remaining[c.room]);await save(c.room+'-restarted.json',peer.state);}finally{await close(peer);}}
 assert.deepEqual(report.errors,[]);report.ok=true;
}catch(e){report.ok=false;report.error=e.stack||String(e);console.error(report.error);process.exitCode=1;}
finally{if(browser)await browser.close();if(service)await service.stop();report.finished=new Date().toISOString();await save('browser-report.json',report);console.log('STACK_BROWSER',JSON.stringify({ok:report.ok,checks:report.checks.length,error:report.error}));}
