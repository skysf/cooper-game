import {chromium} from 'playwright';
import {browserTestOptions,prepareOffscreenPage,enterCamp,stageOffscreenControls} from './coop-browser-controls.mjs';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {resolve} from 'node:path';
import {randomBytes} from 'node:crypto';
const folder=resolve(process.argv[2] || '.cache/eastern-playtest');
const mines=JSON.parse(await readFile(new URL('../coop/props/mines/mines_manifest.json',import.meta.url),'utf8')).mines;
await mkdir(folder,{recursive:true});
const browser=await chromium.launch(browserTestOptions({foreground:false}));
const room='east-qa-'+randomBytes(3).toString('hex');
const records={}, errors=[];
const page=await browser.newPage({viewport:{width:1280,height:720},deviceScaleFactor:1});
page.on('pageerror',e=>errors.push(String(e)));
page.on('console',e=>{if(/SCRIPT ERROR|SHADER ERROR|Parse Error|GLTF: |Failed to load|Compilation failed/i.test(e.text())){errors.push(e.text());console.log('BROWSER',e.text().slice(0,220));}});
const delay=ms=>page.waitForTimeout(ms);
const state=()=>page.evaluate(()=>window.CooperStatus);
async function aim(yaw,pitch){
 await page.evaluate(({yaw,pitch})=>{const c=document.querySelector('#canvas'),r=c.getBoundingClientRect(),s=CooperStatus;
 c.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,pointerType:'mouse',movementX:Math.round(Math.atan2(Math.sin(s.yaw-yaw),Math.cos(s.yaw-yaw))/.00215*r.width/c.width),movementY:Math.round((s.pitch-pitch)/.00215*r.height/c.height),clientX:r.x+r.width/2,clientY:r.y+r.height/2}));},{yaw,pitch}); await delay(500);
}
async function travel(site,expected){
 await page.keyboard.press('KeyM');
 await page.waitForFunction(()=>CooperStatus.atlas.open);
 let s=await state();let pt=s.atlas.sites[site]; if(!pt)throw Error(JSON.stringify(s.atlas));
 if(!records.atlas){await page.screenshot({path:folder+'/atlas.jpg',quality:92}); records.atlas=Object.keys(s.atlas.sites);}
 const r=await page.locator('#canvas').boundingBox();
 await page.mouse.click(r.x+pt[0]*r.width/s.viewport[0],r.y+pt[1]*r.height/s.viewport[1]);
 await page.waitForFunction(([x,z])=>!CooperStatus.atlas.open&&Math.hypot(CooperStatus.x-x,CooperStatus.z-z)<3,expected,{timeout:25000});
 await stageOffscreenControls(page);
}
async function shot(name){
 await delay(650);
 const s=await state();records[name]={x:s.x,z:s.z,y:s.players[s.selfId]?.y,yaw:s.yaw,pitch:s.pitch,packs:s.east?.packs,darkness:s.east?.darkness,plants:Object.values(s.east?.plants??{}).reduce((a,b)=>a+b,0),camps:s.wildPeople?.caves,people:Object.values(s.wildPeople?.people??{}).filter(p=>p.homeMine).map(p=>[p.homeMine,p.duty,p.clip])};
 await page.screenshot({path:folder+'/'+name+'.jpg',quality:92});console.log(name,JSON.stringify(records[name]).slice(0,330));
}
function point(id,z,offset=0){
 const entry=mines[id], f=entry.floor;
 let i=f.findIndex(r=>r[0]>=z);i=i<0?f.length-1:Math.max(1,i);
 const a=f[i-1],b=f[i],t=Math.max(0,Math.min(1,(z-a[0])/(b[0]-a[0])));
 const x=a[2]+(b[2]-a[2])*t+offset;
 const sign=id==='coal_mine'?1:-1;
 return [entry.origin[0]+sign*x,entry.origin[1]+a[1]+(b[1]-a[1])*t,entry.origin[2]+sign*z];
}
async function lookAt([x,y,z]){
 const s=await state(),feet=s.players[s.selfId].y;
 await aim(Math.atan2(s.x-x,s.z-z),Math.atan2(y-(feet+1.67),Math.hypot(x-s.x,z-s.z)));
}
async function walk([x,,z]){
 let s=await state();
 if(Math.hypot(s.x-x,s.z-z)<.35)return;
 await aim(Math.atan2(s.x-x,s.z-z),-.11);
 await page.keyboard.down('KeyW');
 try{await page.waitForFunction(([x,z])=>Math.hypot(CooperStatus.x-x,CooperStatus.z-z)<.48,[x,z],{timeout:17000});}
 finally{await page.keyboard.up('KeyW');}
}
async function descend(id){
 const sign=id==='coal_mine'?1:-1, entry=mines[id];
 for(const depth of [0,4.1,7,10.2,14,18.5,22.5,26]){
  await walk(point(id,depth));
  if(id==='coal_mine'&&depth===7){
   const fire=point(id,10.4,-1.43);fire[1]+=.3;
   await lookAt(fire);await shot('coal-hearth');
  }
 }
 const seam=entry.gather;
 await walk(point(id,seam[2],id==='coal_mine'?-.75:.75));
 await lookAt([entry.origin[0]+sign*seam[0],entry.origin[1]+seam[1],entry.origin[2]+sign*seam[2]]);
 await page.waitForFunction(id=>CooperStatus.mineTarget===id,id,{timeout:7500});
 let s=await state();const stock=s.mines[id].stock;
 await shot(id==='coal_mine'?'coal-depth':'iron-depth');
 await page.keyboard.press('KeyF');
 await page.waitForFunction(([id,stock])=>CooperStatus.mines[id].stock===stock-1,[id,stock]);
 records[id+'-mined']={before:stock,after:(await state()).mines[id].stock};
}
async function frameSample(name){
 const metrics=await page.evaluate(()=>new Promise(resolve=>{
  let start=performance.now(),prev=start;const gaps=[];
  const frame=t=>{if(t-prev>0)gaps.push(t-prev);prev=t;
   if(t-start<2700){requestAnimationFrame(frame);return;}
   gaps.sort((a,b)=>a-b);resolve({frames:gaps.length,fps:Math.round(gaps.length*10000/(t-start))/10,p95ms:Math.round(gaps[Math.floor(gaps.length*.95)]*10)/10});
  };requestAnimationFrame(frame);
 }));
 records[name+'-frame-sample']=metrics;console.log(name+' frames',metrics);
}
try{
 await prepareOffscreenPage(page);
 const url=new URL(process.env.COOP_URL||'http://127.0.0.1:5684/coop/');url.searchParams.set('room',room);
 await page.goto(url.toString(),{waitUntil:'domcontentloaded'});
 await page.waitForFunction(()=>window.CooperStatus?.ready,null,{timeout:150000});
 await enterCamp(page);
 await travel('root_trail',[58,-75.7]);
 await page.waitForFunction(()=>CooperStatus.east?.packs.includes('verdant'),null,{timeout:90000});
 await aim(-1.56,-.04);await shot('root-trail');await frameSample('root-trail');
 await lookAt([54.5,6.6,-81.13]);await shot('woodland-detail');
 await travel('flower_valley',[191,-52]);
 await page.waitForFunction(()=>CooperStatus.east?.packs.includes('namaqua'),null,{timeout:90000});
 await aim(-1.45,-.08);await shot('flower-valley');await frameSample('flower-valley');
 await lookAt([192.59,7.18,-49.22]);await shot('wildflowers');
 await travel('coal_mine',[90,-55]);await aim(Math.PI,-.07);await shot('coal-entrance');
 await descend('coal_mine');
 await travel('iron_mine',[265,-56]);await aim(0,-.04);await shot('iron-entrance');await descend('iron_mine');
 await travel('east_ridge',[322,-32.4]);await aim(-1.4,-.04);await shot('east-ridge');
 assert.equal(errors.length,0,errors.join('\n'));
 console.log('DONE',room,errors);
}finally{await writeFile(folder+'/playtest.json',JSON.stringify({room,records,errors},null,2));await browser.close();}
