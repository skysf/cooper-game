import assert from 'node:assert/strict';
import {once} from 'node:events';
import {mkdir,open,writeFile} from 'node:fs/promises';
import {dirname,extname,resolve} from 'node:path';
import {chromium} from 'playwright';
import {benchmarkWindowPosition, browserTestOptions, enterCamp, focusWindow, hardwareForegroundRequested,
  macScreenLocked, prepareOffscreenPage, stageOffscreenControls} from './coop-browser-controls.mjs';
import {captureBlankRaf, installFrameCapture, intervals} from './coop-frame-capture.mjs';

const base = new URL(process.env.COOP_BASE || 'http://127.0.0.1:4184').origin;
const destination = resolve(process.env.COOP_BENCH_OUT || process.env.COOP_EVIDENCE_DIR || '.cache/flight-qa');
const output = extname(destination)==='.json' ? destination : resolve(destination,'flight-web.json');
const dir = dirname(output);
const room = 'flight-' + Date.now().toString(36);
const sensitivity = .00215;
const foreground = hardwareForegroundRequested(process.env.COOP_CHROME_HEADLESS);
const windowPosition = foreground ? benchmarkWindowPosition() : null;
const browserOptions = browserTestOptions({foreground, position: windowPosition,
  channel: process.env.COOP_CHROME_CHANNEL, metal: process.env.COOP_FLIGHT_HEADLESS_METAL !== '0'});
const {headless} = browserOptions;
const tracing = process.env.COOP_FLIGHT_TRACE === '1';
const turnDelayMs = Number(process.env.COOP_FLIGHT_TURN_DELAY_MS ?? 620);
const reverseFirstTurn = process.env.COOP_FLIGHT_REVERSE_TURN === '1';
assert.ok(Number.isFinite(turnDelayMs) && turnDelayMs >= 0 && turnDelayMs <= 20000, 'Invalid COOP_FLIGHT_TURN_DELAY_MS');
const sleep = ms => new Promise(done => setTimeout(done, ms));
const shortAngle = angle => Math.atan2(Math.sin(angle), Math.cos(angle));
const report = {room, base, headless, tracing, turnDelayMs, reverseFirstTurn, errors: [], phases: {}, checkpoints: {}};
await mkdir(dir, {recursive:true});

let browser, page, flightSnapshot;
const state = () => page.evaluate(() => window.CooperStatus || {});
async function waitFor(description, condition, timeout=14000, read=state) {
  const deadline = Date.now()+timeout;
  while(Date.now()<deadline) {
    const s = await read();
    if(condition(s))return s;
    await sleep(70);
  }
  throw new Error('Timed out waiting for '+description);
}

async function moveMouse(dx, dy) {
  await page.evaluate(({dx,dy}) => window.coopBenchMove(dx, dy), {dx,dy});
}

async function aim(yaw, pitch) {
  const s = await state();
  await moveMouse(shortAngle(s.yaw - yaw)/sensitivity, (s.pitch - pitch)/sensitivity);
  return waitFor('relative mouse aim', now => Math.abs(shortAngle(now.yaw-yaw)) < .028
    && Math.abs(now.pitch-pitch)<.025, 4000);
}

async function hold(key, duration) {
  await page.keyboard.down(key);
  await sleep(duration);
  await page.keyboard.up(key);
}

function submittedFrames(sample) {
  assert.ok(!sample.hidden && !sample.lostFocus && sample.submitted.length >= 2,
    'Flight lost active canvas submissions');
  return intervals(sample.submitted.map(frame => frame.time));
}

async function phase(name, duration, turn) {
  const collecting = page.evaluate(ms => window.coopBenchSample(ms), duration);
  await page.waitForFunction(() => window.coopBenchSampling);
  const samples = await page.evaluate(({duration,turn}) => new Promise(done => {
    const intervals = [], status = [];
    const started = performance.now();
    let latest, previous, batch = 0;
    const dispatch = () => {
      // Feed the pointer-lock movement event through the same browser input handler as a mouse.
      window.coopBenchMove(turn, 0);
      batch++;
    };
    const input = turn ? setInterval(dispatch, 22) : null;
    function sample(now) {
      if(previous !== undefined)intervals.push(now-previous);
      previous = now;
      const s = window.CooperStatus;
      if(s && s !== latest) {
        latest = s;
        status.push({ms:now-started,roomTime:s.elapsed,yaw:s.yaw,view:s.shipCameraYaw,fps:s.fps,ship:s.ship?.yaw,y:s.ship?.y});
      }
      if(now-started < duration)requestAnimationFrame(sample);
      else {
        if(input !== null)clearInterval(input);
        done({intervals,status,mouseEvents:batch});
      }
    }
    requestAnimationFrame(sample);
  }), {duration,turn});
  const sorted = samples.intervals.slice().sort((a,b)=>a-b);
  const avgMs = samples.intervals.reduce((a,b)=>a+b,0)/samples.intervals.length;
  const changes = samples.status.slice(1).map((x,i)=>shortAngle(x.view-samples.status[i].view));
  const direction = -Math.sign(turn);
  let turning = false;
  const reversals = [];
  for (const [index, change] of changes.entries()) {
    turning ||= change * direction > 0.004;
    if (turning && change * direction < -0.02) {
      reversals.push({ms: samples.status[index + 1].ms, radians: change});
    }
  }
  const lastFps = samples.status.map(x=>x.fps).filter(Number.isFinite);
  report.phases[name] = {
    frames:sorted.length, avgFps:+(1000/avgMs).toFixed(2), p95Ms:+sorted[Math.ceil(sorted.length*.95)-1].toFixed(2),
    worstMs:+sorted.at(-1).toFixed(2), framesOver35ms:sorted.filter(ms=>ms>35).length,
    framesOver50ms:sorted.filter(ms=>ms>50).length, engineFpsRange:lastFps.length?[Math.min(...lastFps),Math.max(...lastFps)]:[],
    turnRadians:+changes.reduce((a,b)=>a+b,0).toFixed(3), mouseEvents:samples.mouseEvents, ...samples,
    submitted:submittedFrames(await collecting), cameraReverseJumps:reversals,
  };
  const p=report.phases[name];
  console.log(name, JSON.stringify({avgFps:p.avgFps,p95Ms:p.p95Ms,worstMs:p.worstMs,framesOver35ms:p.framesOver35ms,
    engineFpsRange:p.engineFpsRange,turnRadians:p.turnRadians}));
  if(turn){
    assert.ok(p.turnRadians * direction > 1, name+' camera responds to the turn');
    assert.deepEqual(p.cameraReverseJumps, [], name+' visibly reversed despite same-direction input');
  }
}

async function firstChaseTurn() {
  const direction = reverseFirstTurn ? -10 : 10;
  if (!tracing) return phase('chase turn', 5800, direction);
  const cdp = await page.context().newCDPSession(page);
  const filename = resolve(dir, 'flight-chase-turn-trace.json');
  const mark = name => page.evaluate(label => {
    const {startTime} = performance.mark(label);
    return {browserMs: startTime, epochMs: performance.timeOrigin + startTime};
  }, name);
  await cdp.send('Tracing.start', {transferMode: 'ReturnAsStream', traceConfig: {
    includedCategories: ['devtools.timeline', 'gpu', 'v8', 'blink.user_timing',
      'disabled-by-default-devtools.timeline', 'disabled-by-default-gpu.service'],
  }});
  report.trace = {file: filename, start: await mark('cooper-first-chase-turn-start')};
  try {
    await phase('chase turn', 5800, direction);
  } finally {
    report.trace.end = await mark('cooper-first-chase-turn-end');
    const complete = once(cdp, 'Tracing.tracingComplete');
    await cdp.send('Tracing.end');
    const [{stream}] = await complete;
    const file = await open(filename, 'w');
    try {
      while (true) {
        const chunk = await cdp.send('IO.read', {handle: stream, size: 1024 * 1024});
        await file.write(chunk.base64Encoded ? Buffer.from(chunk.data, 'base64') : chunk.data);
        if (chunk.eof) break;
      }
    } finally {
      await file.close();
      await cdp.send('IO.close', {handle: stream});
      await cdp.detach();
    }
  }
}

try {
  if (!headless && macScreenLocked()) {
    report.environment = {timingEligible: false, screenLocked: true};
    throw Error('The macOS user session is locked');
  }
  browser = await chromium.launch(browserOptions);
  report.browserVersion = browser.version();
  page = await browser.newPage({viewport:{width:1280,height:720},deviceScaleFactor:1});
  if (headless) await prepareOffscreenPage(page);
  else await focusWindow(page, windowPosition);
  report.environment = await captureBlankRaf(page);
  report.environment.timingEligible = report.environment.blankRefreshEligible && !headless && !tracing &&
    !reverseFirstTurn && turnDelayMs === 620;
  await page.addInitScript(installFrameCapture);
  page.on('pageerror', error => report.errors.push(error.message));
  page.on('console', msg => {
    if(msg.type()==='error' && report.errors.length<20)report.errors.push(msg.text().slice(0,1500));
  });
  if (tracing) {
    report.requests = [];
    page.on('requestfinished', request => {
      const {pathname} = new URL(request.url());
      if (!pathname.startsWith('/coop/')) return;
      const {startTime, responseEnd} = request.timing();
      report.requests.push({pathname, startEpochMs: startTime, finishedEpochMs: startTime + responseEnd});
    });
  }
  page.on('websocket', socket => {
    socket.on('framereceived', ({payload}) => {
      if(typeof payload === 'string' && payload.includes('"ship"')) {
        const message = JSON.parse(payload);
        if(message.t === 'snapshot')flightSnapshot = message.ship;
      }
    });
  });
  await page.goto(base+'/coop/?room='+room,{waitUntil:'domcontentloaded'});
  if (!headless) await focusWindow(page, windowPosition);
  const ready = await waitFor('game assets and room', s=>s.ready, 48000);
  await page.waitForFunction(()=>document.getElementById('loader').hidden);
  report.startup = {firstPlayableMs: await page.evaluate(() => performance.now()),
    lanternWarmupMs: ready.lanternWarmupMs ?? null};
  if (headless) await stageOffscreenControls(page);
  else await enterCamp(page);
  // Keep OS pointer-lock recentering and stray movements outside the fixed replay.
  await page.evaluate(() => { window.coopBenchPinCamera = true; });
  report.gpu = await page.evaluate(()=>{
    const gl=document.querySelector('canvas').getContext('webgl2');
    const ext=gl.getExtension('WEBGL_debug_renderer_info');
    return {buffer:[gl.drawingBufferWidth,gl.drawingBufferHeight],renderer:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER),
      window:{x:screenX,y:screenY,availWidth:screen.availWidth,availHeight:screen.availHeight}};
  });
  await phase('camp baseline',4800,0);
  let boarding = await state();
  const aimAtShip = async () => {
    const dx = boarding.ship.x-boarding.x,dz = boarding.ship.z-boarding.z;
    await aim(Math.atan2(-dx,-dz),Math.atan2(boarding.ship.y+.85-(boarding.y+1.67),Math.hypot(dx,dz)));
  };
  await aimAtShip();
  await hold('w',800);
  await sleep(320);
  boarding = await state();
  await aimAtShip();
  await waitFor('ship boarding prompt', s=>s.shipTarget);
  await page.keyboard.press('e');
  let s = await waitFor('boarded in chase view', s=>s.shipPiloting && s.thirdPerson);
  report.checkpoints.board = {x:s.ship.x,y:s.ship.y,z:s.ship.z,thirdPerson:s.thirdPerson};
  await page.screenshot({path:resolve(dir,'flight-parked.png')});

  const takeoffCapture = page.evaluate(() => window.coopBenchSample(6000));
  await page.waitForFunction(() => window.coopBenchSampling);
  await page.keyboard.down('Space');
  await waitFor('belly-only takeoff power', s=>s.ship.y > 1.7 && s.ship.thrust > .70
    && s.ship.rearThrust === 0 && !s.ship.landed);
  await waitFor('low-altitude rotation height', s=>s.ship.y > 4.45);
  await page.keyboard.up('Space');
  await page.evaluate(() => { window.coopBenchFinish = true; });
  report.phases.takeoff = {submitted: submittedFrames(await takeoffCapture)};
  await page.screenshot({path:resolve(dir,'flight-takeoff.png')});
  await sleep(turnDelayMs);
  await firstChaseTurn();

  await page.keyboard.press('v');
  await waitFor('cockpit view',s=>s.shipPiloting && !s.thirdPerson);
  await page.screenshot({path:resolve(dir,'flight-cockpit.png')});
  await phase('cockpit turn',5800,10);
  await page.keyboard.press('v');
  await waitFor('return to chase view',s=>s.thirdPerson);

  await page.keyboard.down('Space');
  await waitFor('altitude clear of the trees',s=>s.ship.y>18.5);
  await page.keyboard.up('Space');
  const t = await state();
  const target = [-25.2,-49.7];
  const flyDx = target[0]-t.ship.x, flyDz = target[1]-t.ship.z;
  await aim(Math.atan2(-flyDx,-flyDz),-.27);
  await sleep(740);
  const travel = (Math.hypot(flyDx,flyDz)+3.3)/.011;
  const forwardStarted = Date.now();
  await page.keyboard.down('w');
  const mainPower = await waitFor('forward acceleration with hover lift',s=>s.ship.rearThrust>.70 && s.ship.thrust<.5);
  report.checkpoints.forward = {lift:mainPower.ship.thrust,rear:mainPower.ship.rearThrust};
  await page.screenshot({path:resolve(dir,'flight-rear-thrust.png')});
  await page.keyboard.down('Space');
  const diagonal = await waitFor('forward climb using both sets of nozzles',s=>s.ship.rearThrust>.35 && s.ship.thrust>.9);
  report.checkpoints.diagonal = {lift:diagonal.ship.thrust,rear:diagonal.ship.rearThrust};
  await page.screenshot({path:resolve(dir,'flight-diagonal-thrust.png')});
  await page.keyboard.up('Space');
  await sleep(Math.max(0,travel-(Date.now()-forwardStarted)));
  await page.keyboard.up('w');
  await sleep(850);
  s = await state();
  report.checkpoints.overLake = [s.ship.x,s.ship.y,s.ship.z];
  assert.ok(Math.hypot(s.ship.x-target[0],s.ship.z-target[1])<5.3,'the pilot can fly to the center of the lake');
  await aim(s.yaw,.03);
  await page.keyboard.down('Space');
  const vertical = await waitFor('full vertical thrust with the tail engines off',s=>s.ship.thrust>.9 && s.ship.rearThrust===0);
  report.checkpoints.vertical = {lift:vertical.ship.thrust,rear:vertical.ship.rearThrust};
  await page.screenshot({path:resolve(dir,'flight-exhaust.png')});
  await page.keyboard.up('Space');
  await page.keyboard.down('c');
  const readFlightSnapshot = () => flightSnapshot || {};
  const descent = await waitFor('lower belly thrust while descending',s=>s.thrust<.2 && s.v[1]<-3.1,5000,readFlightSnapshot);
  await page.keyboard.up('c');
  const braking = await waitFor('higher belly thrust to brake the descent',s=>s.thrust>.65 && s.rearThrust===0,3000,readFlightSnapshot);
  report.checkpoints.verticalBrake = {descend:descent.thrust,brake:braking.thrust,rear:braking.rearThrust};
  await page.keyboard.down('c');
  s = await waitFor('water parking',s=>s.ship.landed && s.ship.onWater,20000);
  await page.keyboard.up('c');
  report.checkpoints.water = {x:s.ship.x,y:s.ship.y,z:s.ship.z,surface:s.ship.surface};
  await page.screenshot({path:resolve(dir,'flight-water.png')});
  await page.keyboard.press('e');
  await waitFor('safe disembark into water',s=>!s.shipPiloting && s.swimming);
  report.checkpoints.swimming = true;
  assert.deepEqual(report.errors,[]);
  report.ok = true;
} catch (error) {
  report.ok = false;
  report.error = error.message;
  if(page) {
    report.last = await state().catch(()=>null);
    await page.screenshot({path:resolve(dir,'flight-check-failed.png')}).catch(()=>{});
  }
  if (report.environment?.screenLocked) {
    console.error(error.message);
    process.exitCode = 2;
  } else throw error;
} finally {
  if(browser)await browser.close();
  await writeFile(output,JSON.stringify(report,null,2));
}
