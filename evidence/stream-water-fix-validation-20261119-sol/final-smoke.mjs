import assert from 'node:assert/strict';
import {spawn,execFileSync} from 'node:child_process';
import {readFile,stat,mkdir,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {chromium} from 'playwright';
import {prepareOffscreenPage,browserTestOptions,clickCanvasPoint} from '../../scripts/coop-browser-controls.mjs';
import {nativeJoinArgs,resolveNativeJoin} from '../../scripts/native-camp-join.mjs';
import {out,root,tokens,fixture,startService,save,wait,until} from './qa-lib.mjs';
const report={started:new Date().toISOString(),scope:'Final incremental font screenshot and Mac release headless join only; earlier functional tests are not repeated',errors:[]};
let service,browser,native,nativeOutput='';
try{
 await mkdir(resolve(out,'saves'),{recursive:true});
 await fixture('stream-final',{states:[{bag:{water:10,wood:1,tarp:1}},{}]});
 const site=process.env.WATER_QA_SITE_DIR||resolve(root,'dist/coop'),app=process.env.WATER_QA_NATIVE_APP||resolve(root,'.cache/resource-fix-release/native/CooperCamp.app');
 const webPck=await readFile(resolve(site,'index.pck')),nativePckPath=resolve(app,'Contents/Resources/雨线营地.pck'),nativePck=await readFile(nativePckPath);
 report.web={site,mtime:(await stat(resolve(site,'index.pck'))).mtime.toISOString(),bytes:webPck.length,sha256:createHash('sha256').update(webPck).digest('hex')};
 report.mac={app,mtime:(await stat(nativePckPath)).mtime.toISOString(),bytes:nativePck.length,sha256:createHash('sha256').update(nativePck).digest('hex')};
 service=await startService('final');report.service=service.base;
 browser=await chromium.launch(browserTestOptions({metal:true}));const context=await browser.newContext({viewport:{width:1280,height:720},deviceScaleFactor:1});await context.addInitScript(t=>sessionStorage.setItem('cooper-identity',t),tokens[0]);const page=await context.newPage();await prepareOffscreenPage(page);page.on('pageerror',e=>report.errors.push(String(e)));await page.goto(service.base+'/coop/?room=stream-final',{waitUntil:'domcontentloaded'});await page.waitForFunction(()=>window.CooperStatus?.ready,null,{timeout:90000});
 await wait(350);const point=await page.evaluate(()=>{const [x,y,w,h]=CooperStatus.enterRect;return [(x+w/2)/CooperStatus.viewport[0],(y+h/2)/CooperStatus.viewport[1]];});await clickCanvasPoint(page,point);await page.waitForFunction(()=>CooperStatus.locked);await page.keyboard.press('Tab');await page.waitForFunction(()=>CooperStatus.backpackOpen);
 const status=await page.evaluate(()=>CooperStatus);assert.equal(status.survival.bag.water,10);assert.equal(status.inventoryPanel.slots.filter(s=>s.visible&&s.item==='water').length,1);assert.equal(status.inventoryPanel.slots.find(s=>s.item==='water').quantity,10);await page.screenshot({path:resolve(out,'final-inventory-readable.png')});await save('final-web-state.json',status);report.web.singleWaterStack=true;
 await browser.close();browser=null;await wait(400);
 const join=await resolveNativeJoin(service.base+'/coop/?room=stream-final'),events=resolve(out,'final-native-status.events');const exe=execFileSync('/usr/libexec/PlistBuddy',['-c','Print :CFBundleExecutable',resolve(app,'Contents/Info.plist')],{encoding:'utf8'}).trim();
 native=spawn(resolve(app,'Contents/MacOS',exe),['--headless','--max-fps','24','--log-file',resolve(out,'final-native.log'),'--quit-after','3000','--',...nativeJoinArgs(join),'--qa-status-file='+events,'--token='+tokens[0]],{stdio:['ignore','pipe','pipe']});for(const stream of [native.stdout,native.stderr])stream.on('data',d=>nativeOutput+=String(d));
 const nativeState=await until(async()=>{if(native.exitCode!==null)throw Error('Native exited before ready: '+nativeOutput);const text=await readFile(events,'utf8').catch(()=>'');return text.split('\n').filter(l=>l.startsWith('COOP_STATE ')).map(l=>{try{return JSON.parse(l.slice(11));}catch{return null;}}).find(s=>s?.ready&&s.room==='stream-final'&&s.survival?.bag?.water===10);},40000,'native final ready');
 assert.equal(nativeState.survival.bag.wood,1);assert.equal(nativeState.survival.bag.tarp,1);assert.ok(!Object.hasOwn(nativeState.survival,'combatMode'));assert.equal(nativeState.websocketUrl,join.websocketUrl);report.mac.ready=true;report.mac.correctRoomAndWaterAndPrivateMaterials=true;report.mac.noCombatMode=true;report.mac.websocketUrl=nativeState.websocketUrl;report.mac.zoneBase=nativeState.zoneBase;await save('final-native-state.json',nativeState);assert.deepEqual(report.errors,[]);report.ok=true;
}catch(e){report.ok=false;report.error=e.stack||String(e);console.error(report.error);process.exitCode=1;}
finally{if(browser)await browser.close();if(native&&native.exitCode===null&&native.signalCode===null){const exit=new Promise(r=>native.once('exit',r));native.kill('SIGTERM');await Promise.race([exit,wait(4000)]);}if(service)await service.stop();await writeFile(resolve(out,'final-native-output.txt'),nativeOutput);report.finished=new Date().toISOString();await save('final-smoke-report.json',report);console.log('FINAL_SMOKE',JSON.stringify({ok:report.ok,web:report.web,mac:report.mac,error:report.error}));}
