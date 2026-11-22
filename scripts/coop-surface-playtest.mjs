import { chromium } from 'playwright';
import { browserTestOptions, prepareOffscreenPage, enterCamp } from './coop-browser-controls.mjs';
import { mkdir,readFile,writeFile } from 'node:fs/promises';
import { resolve,join } from 'node:path';
import { createHash,randomBytes } from 'node:crypto';
import assert from 'node:assert/strict';
const folder=resolve(process.argv[2]||'evidence/eastern-ground-repair-20261121');
const saveDir=resolve(process.env.COOP_QA_SAVE_DIR||'.cache/world-expansion/repairs/rooms');
const url=process.env.COOP_URL||'http://127.0.0.1:5784/coop/';
const {collisionFixture:fixture}=JSON.parse(await readFile(join(folder,'contacts.json'),'utf8'));
const springs=JSON.parse(await readFile(resolve('coop/east/springs.json'),'utf8'));
const browser=await chromium.launch(browserTestOptions({foreground:false}));
const cases=(process.env.COOP_SURFACE_CASES||"").split(",").filter(Boolean);
const results=cases.length?JSON.parse(await readFile(join(folder,"browser.json"),"utf8")).results:{},errors=[];
await mkdir(saveDir,{recursive:true});
async function play(name,start,target,action){
 if(cases.length&&!cases.includes(name))return;
 const room='surf-'+randomBytes(5).toString('hex'),token=randomBytes(16).toString('hex'),id=createHash('sha256').update(room+':'+token).digest('hex').slice(0,16);
 const state={version:1,elapsed:12,homes:{[id]:{x:start[0],z:start[1],y:start[2]??0,yaw:0}},quest:{wood:false,tarp:false,repaired:false}};
 await writeFile(join(saveDir,room+'.json'),JSON.stringify(state),{flag:'wx'});
 const context=await browser.newContext({viewport:{width:1200,height:710},deviceScaleFactor:1});const page=await context.newPage();
 await page.addInitScript(token=>sessionStorage.setItem('cooper-identity',token),token);
 page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(/SCRIPT ERROR|SHADER ERROR|Parse Error|Compilation failed|Failed to load/i.test(m.text())){errors.push(m.text());console.log('BROWSER',m.text().slice(0,180));}});
 const status=()=>page.evaluate(()=>CooperStatus);
 async function aim(x,y,z){const s=await status(),feet=s.players[s.selfId].y;const yaw=Math.atan2(s.x-x,s.z-z),pitch=Math.atan2(y-feet-1.67,Math.hypot(x-s.x,z-s.z));
  await page.evaluate(({yaw,pitch})=>{const c=document.querySelector('#canvas'),r=c.getBoundingClientRect(),s=CooperStatus;c.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,pointerType:'mouse',movementX:Math.round(Math.atan2(Math.sin(s.yaw-yaw),Math.cos(s.yaw-yaw))/.00215*r.width/c.width),movementY:Math.round((s.pitch-pitch)/.00215*r.height/c.height),clientX:r.x+r.width/2,clientY:r.y+r.height/2}));},{yaw,pitch});await page.waitForTimeout(380);}
 try{await prepareOffscreenPage(page);await page.goto(url+'?room='+room);await page.waitForFunction(()=>window.CooperStatus?.ready,null,{timeout:150000});await enterCamp(page);const pack=start[0]>144?'namaqua':'verdant';await page.waitForFunction(pack=>CooperStatus.east?.packs?.includes(pack),pack,{timeout:90000});await page.waitForTimeout(550);let s=await status();assert.equal(s.selfId,id);let startFeet=s.players[id].y;assert.ok(Math.hypot(s.x-start[0],s.z-start[1])<1.6,name+' load');await aim(...target);
  if(action==='restore'){assert.ok(Math.abs(startFeet-fixture.roof[1])<.02);await page.keyboard.press('KeyV');}
  if(action==='cross'){await page.keyboard.down('KeyW');try{await page.waitForFunction(()=>CooperStatus.x>34,null,{timeout:7000});}finally{await page.keyboard.up('KeyW');}await aim(31,.12,-62);}
  if(action==='collision'){await page.keyboard.press('KeyV');await page.keyboard.down('KeyW');await page.waitForTimeout(1250);await page.keyboard.up('KeyW');s=await status();let d=Math.hypot(s.x-start[0],s.z-start[1]);assert.ok(d>0.1&&d<2.0,name+' displacement '+d);}
  await page.waitForTimeout(280);s=await status();results[name]={start,position:[s.x,s.players[id].y,s.z],startFeet,thirdPerson:s.thirdPerson};await page.screenshot({path:join(folder,name+'.jpg'),quality:93});console.log(name,JSON.stringify(results[name]));
 }finally{await context.close();}}
try{
 await play('forest-crossing',[26,-53.5],[50,1.2,-53.5],'cross');
 await play('coal-threshold',[90,-48.15,4.27],[89.7,4.45,-57.8]);
 await play('root-contact',[89.0,-54.8],[89.6,5.05,-57.6]);
 await play('iron-threshold',[265,-62.95,7.45],[265.2,7.82,-53.5]);
 await play('woodland-spring',[103.8,-62.3],[102,springs.coal_mine.level,-59]);
 await play('dryland-spring',[257.4,-55.6],[254,springs.iron_mine.level,-54]);
 for(let i=0;i<fixture.approaches.length;i++){const p=fixture.approaches[i];await play('rock-stop-'+(i+1),p.start,[p.aim[0],p.ground+1.4,p.aim[1]],'collision');}
 const r=fixture.roof;await play('rock-standing',[r[0],r[2],fixture.oldFeet],[r[0]+1,r[1]-.3,r[2]+2.5],'restore');
 const p=fixture.approaches[0],d=[p.start[0]-p.aim[0],p.start[1]-p.aim[1]];await play('closed-rock-back',[p.start[0]+d[0]*3.3,p.start[1]+d[1]*3.3],[r[0],r[1]-.4,r[2]]);
 assert.deepEqual(errors,[]);console.log('SURFACE_WEB_OK');
}finally{await writeFile(join(folder,'browser.json'),JSON.stringify({results,errors},null,2)+'\n');await browser.close();}
