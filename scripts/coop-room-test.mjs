import {findPath} from './coop-test-path.mjs';
// Real loopback WebSockets + the production Godot server and collision manifest.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import net from 'node:net';
import { tmpdir, homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const project = process.env.COOP_PROJECT || join(root, 'coop');
const manifest = JSON.parse(await readFile(join(project, 'world.json'), 'utf8'));
const godot = process.env.GODOT_BIN || [
  '/Applications/Godot.app/Contents/MacOS/Godot',
  join(homedir(), 'Downloads/Godot.app/Contents/MacOS/Godot'),
].find(existsSync) || 'godot';
const hold = ms => new Promise(done => setTimeout(done, ms));
const tmp = await mkdtemp(join(tmpdir(), 'woodland-room-'));
let server;
let adapter;
const allPeers = [];
const logs = [];
const info = { transport: 'Godot headless server + Node WebSocket clients over loopback', checks: {} };
const port = await new Promise((done, fail) => {
  const probe = net.createServer();
  probe.once('error', fail);
  probe.listen(0, '127.0.0.1', () => { const p = probe.address().port; probe.close(() => done(p)); });
});

async function until(predicate, deadline = 6000) {
  const limit = Date.now() + deadline;
  while (Date.now() < limit) {
    const result = predicate();
    if (result) return result;
    await hold(20);
  }
  throw Error('Timed out: ' + predicate.toString().slice(0, 200));
}
async function boot() {
  server = spawn(godot, ['--headless', '--log-file', join(tmp,'engine.log'), '--path', project, '--script', 'res://server.gd', '--', '--save='+tmp, '--port='+port], {stdio:['ignore','pipe','pipe']});
  let ready=false;
  for(const stream of [server.stdout,server.stderr]) stream.on('data',data=>{
    const line=String(data);logs.push(line);
    if(line.includes('ROOM_SERVER_READY'))ready=true;
  });
  await until(()=>{if(server.exitCode !== null) throw Error(logs.slice(-12).join(''));return ready;});
}
async function stop() {
  if(!server || server.exitCode!==null || server.signalCode!==null)return;
  const exit = new Promise(resolve => server.once('exit',resolve));
  if(process.platform!=='win32')server.kill('SIGCONT');
  server.kill('SIGTERM');await exit;
}
async function connect(room='test', token=randomBytes(16).toString('hex'), expectReject=false,
    session=randomBytes(12).toString('hex'), snapshotFlow=false) {
  const ws=new WebSocket('ws://127.0.0.1:'+port);
  const p={ws,token,session,id:'',state:null,snapshots:0,notices:[],reject:null,send:m=>ws.send(JSON.stringify(m))};
  allPeers.push(p);
  ws.onopen=()=>{
    p.send({t:'join',room,token,session,...(snapshotFlow?{snapshotFlow:true}:{})});
    const keepAlive=setInterval(()=>{if(ws.readyState===WebSocket.OPEN)p.send({t:'ping'});},5000);
    ws.addEventListener('close',()=>clearInterval(keepAlive),{once:true});
  };
  ws.onmessage=e=>{
    const m=JSON.parse(e.data);
    if(m.t==='welcome')p.id=m.id;
    if(m.t==='snapshot'){p.state=m;p.snapshots++;}
    if(m.t==='notice')p.notices.push(m);
    if(m.t==='reject')p.reject=m;
  };
  await until(()=>expectReject?p.reject:(p.state && p.id));
  return p;
}
function here(p){const {x,z}=p.state.players[p.id];return [x,z];}
const dist=(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1]);
async function walk(p,site) {
  const target=manifest.sites[site];
  const points=findPath(manifest,here(p),target,{ship:p.state.ship,feet:p.state.players[p.id].y});
  for(const dest of points){
    const limit=Date.now()+3500+dist(here(p),dest)*650;
    while(dist(here(p),dest)>.32){
      if(Date.now()>limit)throw Error('walk stuck '+JSON.stringify({site,at:here(p),dest}));
      const [x,z]=here(p),dx=dest[0]-x,dz=dest[1]-z,d=Math.hypot(dx,dz);
      const speed=Math.min(1,d/0.75);p.send({t:'motion',x:dx/d*speed,z:dz/d*speed,yaw:Math.atan2(-dx,-dz)});
      await hold(58);
    }
  }
  p.send({t:'motion',x:0,z:0,yaw:0});
  assert.ok(dist(here(p),target)<2.5);
}
async function act(p,site) {
  const n=p.notices.length;
  p.send({t:'act',site});return until(()=>p.notices[n]);
}
async function close(p){
  if(p.ws.readyState===WebSocket.CLOSED)return;
  const ended=new Promise(done=>p.ws.addEventListener('close',done,{once:true}));
  p.ws.close();await ended;
}
const playerId = (room, token) => createHash('sha256').update(`${room}:${token}`).digest('hex').slice(0,16);

async function checkSnapshotCoalescing() {
  const room = 'snapshot-flow';
  const token = randomBytes(16).toString('hex');
  const id = playerId(room, token);
  await writeFile(join(tmp, room+'.json'), JSON.stringify({
    version:1, elapsed:12, quest:{wood:true,tarp:true,repaired:false}, homes:{[id]:{x:1.9,z:-87.55,yaw:0}},
  }));
  const stalled = await connect(room, token, false, undefined, true);
  const oldClient = await connect(room);
  const first = stalled.state;
  assert.equal(first.snapshotSeq, 1);
  assert.equal(oldClient.state.snapshotSeq, undefined);
  stalled.send({t:'motion',x:0,z:0,yaw:0,snapshotAck:2});
  const repaired = await act(stalled, 'repair');
  assert.ok(repaired.ok, 'a notice is delivered even while a snapshot is pending');
  await until(()=>oldClient.state.quest.repaired);
  await hold(650);
  assert.equal(stalled.snapshots, 1, 'a slow renderer can have at most one unconsumed snapshot');
  stalled.send({t:'motion',x:0,z:0,yaw:0,snapshotAck:first.snapshotSeq});
  await until(()=>stalled.state.snapshotSeq===2);
  assert.ok(stalled.state.quest.repaired && stalled.state.elapsed > first.elapsed + 0.5,
    'the next snapshot contains the current room state rather than a backlog');
  info.checks.snapshotFlow = {singlePending:true, freshestAfterAck:true, noticesDelivered:true, legacyCompatible:true};
  await Promise.all([close(stalled),close(oldClient)]);
}

async function checkStones() {
  const room = 'camp-stones';
  const tokens = Array.from({length:3}, () => randomBytes(16).toString('hex'));
  const positions = [[1.43,-85], [1.2,-84.9], [-10.45,-49.1]];
  const homes = Object.fromEntries(tokens.map((token,index) => {
    const [x,z] = positions[index];
    return [playerId(room,token), {x,z,yaw:0}];
  }));
  await writeFile(join(tmp,room+'.json'),JSON.stringify({
    version:1,elapsed:115,quest:{wood:false,tarp:false,repaired:false},homes,
  }));
  const [a,b,dock] = await Promise.all(tokens.map(token=>connect(room,token)));
  const send = (peer,action,rest={})=>peer.send({t:'stone',action,...rest});
  const agrees = (key,accept)=>until(()=>[a,b,dock].every(peer=>accept(peer.state.stones[key])));
  send(a,'pick',{id:'camp-round'});send(b,'pick',{id:'camp-round'});
  await agrees('camp-round',s=>s?.mode==='held');
  const holder = a.state.stones['camp-round'].holder;
  assert.ok([a.id,b.id].includes(holder));
  const winner = holder===a.id?a:b, other = holder===a.id?b:a;
  send(other,'drop');
  send(winner,'context');
  await agrees('camp-round',s=>s?.mode==='placed');
  send(other,'pick',{id:'camp-flat'});
  await agrees('camp-flat',s=>s?.holder===other.id);
  send(other,'context');
  await agrees('camp-flat',s=>s?.edge===3);
  send(other,'context');
  await agrees('camp-flat',s=>s?.edge===2);
  await until(()=>[a,b,dock].every(peer=>peer.state.lineCut));
  send(other,'drop');
  await agrees('camp-flat',s=>s?.mode==='ground');
  const drop = await until(() => a.state.stoneSounds?.find(sound=>sound.cue==='stone_earth'));
  assert.ok(drop.strength<1 && drop.point[1]>=0);
  send(a,'pick',{id:'shore-round'});
  send(dock,'pick',{id:'shore-round'});
  await agrees('shore-round',s=>s?.holder===dock.id);
  send(dock,'throw',{yaw:Math.PI/2,pitch:.09});
  await agrees('shore-round',s=>s?.mode==='air');
  const launch = await until(() => dock.state.stoneSounds?.find(sound=>sound.cue==='stone_throw'));
  for(const peer of [a,b]){
    assert.deepEqual(await until(()=>peer.state.stoneSounds?.find(sound=>sound.id===launch.id)),launch);
  }
  await agrees('shore-round',s=>s?.mode==='submerged');
  await until(()=>[a,b,dock].every(peer=>peer.state.waterImpacts?.length===1));
  assert.deepEqual(a.state.waterImpacts,dock.state.waterImpacts);
  const splash=await until(()=>dock.state.stoneSounds?.find(sound=>sound.cue==='stone_water'));
  assert.ok(splash.id>launch.id);
  assert.deepEqual(splash.point,dock.state.waterImpacts[0].point);
  assert.deepEqual(await until(()=>b.state.stoneSounds?.find(sound=>sound.id===splash.id)),splash);
  assert.ok(dock.state.waterImpacts[0].point[0]<positions[2][0]-2);
  const saved = JSON.parse(await readFile(join(tmp,room+'.json'),'utf8'));
  assert.equal(saved.stones['camp-flat'].edge,2);
  assert.equal(saved.lineCut,true);
  assert.equal(saved.stoneSounds,undefined);
  info.checks.stoneInteractions = {exclusivePickup:true, placedCanvas:true, sharpenedAndCut:true, thrownAndSharedSplash:true};
  info.checks.stoneAudioEvents = {localDrop:true, sharedLaunch:true, sharedSplash:true, transient:true};
  await Promise.all([close(a),close(b),close(dock)]);
}
try{
  const legacyToken=randomBytes(16).toString('hex');
  const legacyId=createHash('sha256').update('legacy-grove:'+legacyToken).digest('hex').slice(0,16);
  const planted=manifest.grove.trees[0];
  await writeFile(join(tmp,'legacy-grove.json'),JSON.stringify({
    version:1,elapsed:142,quest:{wood:true,tarp:false,repaired:false},
    homes:{[legacyId]:{x:planted.x,z:planted.z,yaw:0}},
  }));
  await boot();
  await checkSnapshotCoalescing();
  await checkStones();
  const legacy=await connect('legacy-grove',legacyToken);
  const legacyFriend=await connect('legacy-grove');
  assert.ok(legacy.state.elapsed>=142 && legacy.state.groveElapsed<1);
  assert.equal(legacy.state.quest.wood,true);
  const displaced=dist(here(legacy),[planted.x,planted.z]);
  assert.ok(displaced>=planted.radius+.29 && displaced<.6);
  assert.ok(Math.abs(legacyFriend.state.elapsed-legacyFriend.state.groveElapsed-142)<1e-6);
  await until(()=>legacy.state.groveElapsed>=.3 && legacyFriend.state.groveElapsed>=.3);
  assert.ok(Math.abs(legacy.state.groveElapsed-legacyFriend.state.groveElapsed)<.3);
  const savedGroveAge=legacy.state.groveElapsed;
  await Promise.all([close(legacy),close(legacyFriend)]);
  await until(()=>[legacy,legacyFriend].every(peer=>logs.some(line=>line.includes('ROOM_LEAVE legacy-grove '+peer.id))));
  const migrated=JSON.parse(await readFile(join(tmp,'legacy-grove.json'),'utf8'));
  assert.equal(migrated.groveStartedAt,142);
  // The snapshot and save serialize elapsed and grove age separately as JSON floats.
  const clockTolerance=1e-6;
  const persistedGroveAge=migrated.elapsed-migrated.groveStartedAt;
  assert.ok(persistedGroveAge+clockTolerance>=savedGroveAge,
    `Checkpoint regressed the grove clock from ${savedGroveAge} to ${persistedGroveAge}`);
  const interrupted=await connect('handover');
  const continued=await connect('handover',interrupted.token,false,interrupted.session);
  assert.equal(continued.id,interrupted.id);
  assert.equal(Object.keys(continued.state.players).length,1);
  await until(()=>interrupted.ws.readyState===WebSocket.CLOSED);
  await close(continued);info.checks.staleSocketTakeover=true;
  const a=await connect(),b=await connect(),other=await connect('separate');
  const c=await connect(),d=await connect(),full=await connect('test',undefined,true);
  assert.equal(full.reject.code,'full');await close(full);await close(c);await close(d);
  await until(()=>Object.keys(a.state.players).length===2);
  info.checks.roomLimit=4;
  assert.equal((await act(a,'tarp')).ok,false);
  assert.equal((await act(a,'repair')).ok,false);
  info.checks.rangeAndPrerequisites=true;
  const position=here(a),t=performance.now();
  a.send({t:'motion',x:500,z:500,yaw:0,position:[28,10]});await hold(550);
  a.send({t:'motion',x:0,z:0,yaw:0});await hold(250);
  assert.ok(dist(position,here(a)) < 3.6*(performance.now()-t)/1000+.15);
  info.checks.serverSpeedBound=true;
  console.log('Walking both players to wood');
  await Promise.all([walk(a,'wood'),walk(b,'wood')]);
  const attempts=await Promise.all([act(a,'wood'),act(b,'wood')]);
  assert.equal(attempts.filter(r=>r.ok).length,1);
  await until(()=>a.state.quest.wood && b.state.quest.wood);
  info.checks.simultaneousPickupAwards=1;
  // The single physical award belongs to its collector. Share it explicitly before splitting up.
  async function provision(p,action,rest={}){
    const n=p.notices.length;p.send({t:'provision',action,...rest});return until(()=>p.notices[n]);
  }
  if(!a.state.survival.bag.wood){
    assert.equal((await provision(b,'drop',{item:'wood'})).ok,true);
    await until(()=>Object.values(a.state.provisions).some(r=>r.item==='wood'));
    const woodId=Object.keys(a.state.provisions).find(id=>a.state.provisions[id].item==='wood');
    assert.equal((await provision(a,'take',{id:woodId})).ok,true);
  }
  await until(()=>a.state.survival.bag.wood===1);
  const old=here(b),id=b.id;await close(b);
  await until(()=>Object.keys(a.state.players).length===1);
  const back=await connect('test',b.token);
  assert.equal(back.id,id);assert.ok(dist(here(back),old)<.5);
  info.checks.reconnectIdentityAndPose=true;
  console.log('Players splitting across sectors');
  await Promise.all([walk(a,'tarp'),walk(back,'repair')]);
  assert.equal((await act(a,'tarp')).ok,true);
  assert.equal((await act(back,'repair')).ok,false, 'a teammate cannot spend the collector inventory');
  await walk(a,'repair');
  assert.equal((await act(a,'repair')).ok,true);
  await until(()=>a.state.survival.bag.wood===0 && a.state.survival.bag.tarp===0);
  info.checks.personalMaterialSpending=true;
  await until(()=>a.state.quest.repaired && back.state.quest.repaired);
  assert.equal(other.state.quest.wood,false);
  info.checks.independentRooms=true;
  info.checks.sharedRoof=true;
  await until(()=>a.state.elapsed>=66 && back.state.elapsed>=66, 70000);
  info.checks.stormReachedByBoth=true;
  const before=a.state.elapsed;
  assert.equal(a.state.groveElapsed,a.state.elapsed);
  assert.equal(back.state.groveElapsed,back.state.elapsed);
  for(const p of [a,back,other])await close(p);
  await until(()=>existsSync(join(tmp,'test.json')));
  await stop();await boot();
  const legacyRestored=await connect('legacy-grove',legacy.token);
  const restoredGroveAge=legacyRestored.state.groveElapsed;
  assert.ok(restoredGroveAge+clockTolerance>=persistedGroveAge && restoredGroveAge-persistedGroveAge<.4,
    `Restart read grove age ${restoredGroveAge} from persisted age ${persistedGroveAge}`);
  assert.ok(Math.abs(legacyRestored.state.elapsed-restoredGroveAge-migrated.groveStartedAt)<clockTolerance);
  await close(legacyRestored);
  info.checks.groveClock={legacyAnchor:142,before:savedGroveAge,after:legacyRestored.state.groveElapsed,legacyPositionCorrection:displaced};
  const restored=await connect('test',a.token);
  assert.deepEqual(restored.state.quest,{wood:true,tarp:true,repaired:true});
  assert.ok(restored.state.elapsed>=before-.5);
  assert.equal(restored.id,a.id);
  assert.ok(dist(here(restored),manifest.sites.repair)<2.5);
  info.checks.restartStateAndClock={before,after:restored.state.elapsed};
  await close(restored);
  // Sever the real transport under two running Godot adapters, then restore it.
  adapter=spawn(godot,['--headless','--log-file',join(tmp,'client.log'),'--path',project,
    '--script',join(root,'scripts','coop-room-test.gd'),'--',String(port)],{stdio:['ignore','pipe','pipe']});
  let trace='';
  for(const stream of [adapter.stdout,adapter.stderr])stream.on('data',data=>{trace+=String(data);});
  const adapterExit=new Promise(done=>adapter.on('exit',(code)=>done(code)));
  const reached=marker=>{if(adapter.exitCode!==null && adapter.exitCode!==0)throw Error(trace);return trace.includes(marker);};
  await until(()=>reached('ROOM_ADAPTER_CHECKPOINT'),15000);
  assert.ok(trace.includes('ROOM_ADAPTER_RENDER_RESUMED'));
  info.checks.firstSnapshotSurvivesRenderPause=true;
  const expectedHome=JSON.parse(trace.match(/ROOM_ADAPTER_CHECKPOINT (\{[^\n]+\})/)[1]);
  const checkpointPath=join(tmp,'adapter.json');
  await until(()=>{
    if(!existsSync(checkpointPath))return false;
    const home=JSON.parse(readFileSync(checkpointPath,'utf8')).homes[expectedHome.id];
    return home && dist([home.x,home.z],[expectedHome.x,expectedHome.z])<.45;
  });
  if(process.platform!=='win32'){
    // Leave TCP open while simulating an access point that drops all game traffic.
    server.kill('SIGSTOP');
    await until(()=>reached('ROOM_ADAPTER_OFFLINE'),9000);
    info.checks.halfOpenSnapshotTimeout=true;
  }
  await stop();
  await until(()=>reached('ROOM_ADAPTER_OFFLINE'),9000);
  await boot();
  await until(()=>reached('ROOM_ADAPTER_RESTORED'),9000);
  assert.equal(await adapterExit,0);
  info.checks.godotClientReconnectAndPrediction=true;
  if(process.argv[2])await writeFile(resolve(process.argv[2]),JSON.stringify(info,null,2)+'\n');
  console.log(JSON.stringify(info,null,2));
}catch(e){console.error(logs.join('').slice(-4000));throw e;}
finally{
  if(adapter && adapter.exitCode===null)adapter.kill();
  for(const p of allPeers)p.ws.close();
  await stop();await rm(tmp,{recursive:true,force:true});
}
