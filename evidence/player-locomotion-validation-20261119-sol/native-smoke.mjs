import assert from 'node:assert/strict';
import {spawn,execFileSync} from 'node:child_process';
import {readFile,stat,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {nativeJoinArgs,resolveNativeJoin} from '../../scripts/native-camp-join.mjs';
import {out,root,tokens,startService,until,wait,save} from './qa-lib.mjs';
const report={started:new Date().toISOString(),mode:'final candidate Mac release headless join only; no GPU or repeated action suite'};let service,child,output='';
try{
 const app=resolve(root,'dist/coop-resource-fix-native/CooperCamp.app'),pckPath=resolve(app,'Contents/Resources/雨线营地.pck'),pck=await readFile(pckPath);report.package={app,mtime:(await stat(pckPath)).mtime.toISOString(),bytes:pck.length,sha256:createHash('sha256').update(pck).digest('hex')};
 assert.equal(report.package.sha256,'7fe68e3ccd9779161ed9e8144f75e9b25d4378f7957b34656696b31d92d6b457');service=await startService('mac');const join=await resolveNativeJoin(service.base+'/coop/?room=motion-water'),events=resolve(out,'mac-final-status.events'),exe=execFileSync('/usr/libexec/PlistBuddy',['-c','Print :CFBundleExecutable',resolve(app,'Contents/Info.plist')],{encoding:'utf8'}).trim();
 child=spawn(resolve(app,'Contents/MacOS',exe),['--headless','--max-fps','24','--log-file',resolve(out,'mac-final.log'),'--quit-after','3000','--',...nativeJoinArgs(join),'--qa-status-file='+events,'--token='+tokens[0]],{stdio:['ignore','pipe','pipe']});for(const stream of [child.stdout,child.stderr])stream.on('data',d=>output+=String(d));
 const s=await until(async()=>{if(child.exitCode!==null)throw Error('Native exited before ready: '+output);const text=await readFile(events,'utf8').catch(()=>'');return text.split('\n').filter(l=>l.startsWith('COOP_STATE ')).map(l=>{try{return JSON.parse(l.slice(11));}catch{return null;}}).find(s=>s?.ready&&s.room==='motion-water');},40000,'Mac candidate ready');
 assert.equal(s.websocketUrl,join.websocketUrl);assert.equal(s.swimming,false);assert.equal(s.localPhysics.grounded,true);assert.equal(s.survival.bag.club,3);assert.equal(s.survival.bag.shield,2);assert.equal(s.survival.weapon,'club');assert.equal(s.survival.shield,true);assert.ok(!Object.hasOwn(s.survival,'combatMode'));await save('mac-ready-state.json',s);report.ready=true;report.room=s.room;report.websocketUrl=s.websocketUrl;report.zoneBase=s.zoneBase;report.correctGroundedAndEquipment=true;report.ok=true;
}catch(e){report.ok=false;report.error=e.stack||String(e);console.error(report.error);process.exitCode=1;}
finally{if(child&&child.exitCode===null&&child.signalCode===null){const end=new Promise(r=>child.once('exit',r));child.kill('SIGTERM');await Promise.race([end,wait(4000)]);}if(service)await service.stop();await writeFile(resolve(out,'mac-output.txt'),output);report.finished=new Date().toISOString();await save('mac-report.json',report);console.log('MAC_MOTION_SMOKE',JSON.stringify(report));}
