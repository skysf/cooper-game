import {spawn} from 'node:child_process';
import {readFile,writeFile} from 'node:fs/promises';
import net from 'node:net';
import {createInterface} from 'node:readline';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {chromium} from 'playwright';
import {prepareOffscreenPage,browserTestOptions,enterCamp} from '../../../scripts/coop-browser-controls.mjs';
import {installFrameCapture} from '../../../scripts/coop-frame-capture.mjs';
const out=fileURLToPath(new URL('.',import.meta.url));
const root=fileURLToPath(new URL('../../../',import.meta.url));
const token='cafe00112233445566778899aabbccdd';
const report={started:new Date().toISOString(),mode:'headless Chrome ANGLE Metal; ordinary keyboard, mouse and UI button inputs',formalHardwareTimingEligible:false,commands:[],errors:[]};
const wait=ms=>new Promise(r=>setTimeout(r,ms));
async function freePort(){return new Promise((resolve,reject)=>{const s=net.createServer();s.once('error',reject);s.listen(0,'127.0.0.1',()=>{const p=s.address().port;s.close(()=>resolve(p));});});}
const port=await freePort(),roomPort=await freePort();report.port=port;report.roomPort=roomPort;
const service=spawn(process.execPath,[resolve(out,'serve-owned.mjs')],{env:{...process.env,COOP_PORT:String(port),COOP_ROOM_PORT:String(roomPort),COOP_SAVE_DIR:resolve(out,'saves'),COOP_SITE_DIR:resolve(root,'dist/coop')},stdio:['ignore','pipe','pipe']});
let serverOutput='';for(const stream of [service.stdout,service.stderr])stream.on('data',x=>serverOutput+=String(x));
let ready=false;for(let i=0;i<120;i++){try{ready=(await(await fetch('http://127.0.0.1:'+port+'/health')).json()).ready;if(ready)break;}catch{}await wait(100);}if(!ready)throw Error('Service not ready '+serverOutput);
const browser=await chromium.launch(browserTestOptions({metal:true}));
const pages=[];
async function open(mode){
 const context=await browser.newContext({viewport:{width:1280,height:720},deviceScaleFactor:1});
 await context.addInitScript(t=>sessionStorage.setItem('cooper-identity',t),token);
 const page=await context.newPage();await prepareOffscreenPage(page);await page.addInitScript(installFrameCapture);
 page.on('pageerror',e=>report.errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')report.errors.push(m.text());});
 await page.goto('http://127.0.0.1:'+port+'/coop/?room=wild-qa-'+mode,{waitUntil:'domcontentloaded'});
 await page.waitForFunction(()=>window.CooperStatus?.ready&&window.CooperStatus?.wildPeople?.people,null,{timeout:90000});
 await enterCamp(page);pages.push({page,context,mode});return pages.length-1;
}
async function state(page){return page.evaluate(()=>window.CooperStatus);}
async function snapshot(page,name){const path=resolve(out,name+'.png');await page.screenshot({path});return path;}
async function aim(page,id,up=1.12){
 const s=await state(page),n=s.wildPeople.people[id];if(!n)throw Error('NPC missing '+id);
 const targetYaw=Math.atan2(s.x-n.x,s.z-n.z),targetPitch=Math.atan2((n.y||0)+up-(s.y+1.67),Math.hypot(n.x-s.x,n.z-s.z));
 for(let i=0;i<5;i++){const a=await state(page);const ye=Math.atan2(Math.sin(targetYaw-a.yaw),Math.cos(targetYaw-a.yaw)),pe=targetPitch-a.pitch;if(Math.abs(ye)<.004&&Math.abs(pe)<.004)return;await page.evaluate(([dx,dy])=>window.coopBenchMove(dx,dy),[-ye/.00215,-pe/.00215]);await wait(300);}
}
async function save(){await writeFile(resolve(out,'report.json'),JSON.stringify(report,null,2));await writeFile(resolve(out,'service-output.txt'),serverOutput);}
process.once('uncaughtException',async e=>{report.errors.push(e.stack||String(e));await browser.close().catch(()=>{});service.kill('SIGTERM');await save();process.exit(1);});
const index=await open('captive');await snapshot(pages[index].page,'captive-entry');console.log('BROWSER_READY',JSON.stringify({index,port,state:await state(pages[index].page)}));
const rl=createInterface({input:process.stdin,crlfDelay:Infinity});
for await(const line of rl){if(!line.trim())continue;let command;try{
 command=JSON.parse(line);const i=command.page??0;const page=pages[i]?.page;
 let result;
 if(command.op==='open'){result={index:await open(command.mode)};}
 else if(command.op==='press'){await page.keyboard.press(command.key);await wait(command.wait??350);}
 else if(command.op==='click'){await page.mouse.click(command.x,command.y);await wait(command.wait??400);}
 else if(command.op==='wheel'){await page.mouse.move(command.x??900,command.y??450);await page.mouse.wheel(0,command.dy);await wait(400);}
 else if(command.op==='hold'){await page.keyboard.down(command.key);await wait(command.ms);await page.keyboard.up(command.key);await wait(300);}
 else if(command.op==='modal_hold'){await page.keyboard.down('w');await wait(100);await page.keyboard.press('b');await wait(350);await page.keyboard.up('w');await wait(350);}
 else if(command.op==='capture'){result={screenshot:await snapshot(page,command.name)};}
 else if(command.op==='aim'){await aim(page,command.id||'person-1',command.up??1.12);}
 else if(command.op==='resize'){await page.setViewportSize({width:command.width,height:command.height});await wait(500);}
 else if(command.op==='sample'){result=await page.evaluate(ms=>window.coopBenchSample(ms),command.ms||6000);}
 else if(command.op==='wait'){await wait(Math.min(command.ms,30000));}
 else if(command.op==='close'){await save();break;}
 else if(command.op!=='state')throw Error('Unknown command');
 if(page)result={...result,state:await state(page)};
 report.commands.push({at:new Date().toISOString(),command,result});await save();console.log('RESULT',JSON.stringify({command,result}));
 }catch(e){report.errors.push(String(e));report.commands.push({command,error:String(e)});await save();console.log('COMMAND_ERROR',JSON.stringify({command,error:String(e)}));}}
await browser.close();const stopped=new Promise(r=>service.once('exit',r));service.kill('SIGTERM');await stopped;report.finished=new Date().toISOString();await save();console.log('BROWSER_SESSION_FINISHED',JSON.stringify({errors:report.errors,report:resolve(out,'report.json')}));
