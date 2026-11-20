import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';
import {benchmarkWindowPosition, browserTestOptions, enterCamp, focusWindow, macScreenLocked,
  prepareOffscreenPage, stageOffscreenControls} from './coop-browser-controls.mjs';
import {captureBlankRaf, installFrameCapture, intervals} from './coop-frame-capture.mjs';
import {findPath} from './coop-test-path.mjs';

const entry = new URL(process.env.COOP_URL || 'http://127.0.0.1:4494/coop/');
const output = process.argv[2] || '.cache/coast/foreground';
const design = JSON.parse(await readFile('coop/coast_layout.json', 'utf8'));
const world = JSON.parse(await readFile('coop/world.json', 'utf8'));
const foreground = process.env.COOP_COAST_HEADLESS !== '1';
const traceGL = process.env.COOP_COAST_GL_TRACE === '1';
const mineStops = process.env.COOP_COAST_MINES === '1'
  ? JSON.parse(await readFile('coop/props/mines/mines_manifest.json', 'utf8')).mines : null;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const screenLockedAtLaunch = macScreenLocked();
assert.ok(!foreground || !screenLockedAtLaunch, 'Unlock the desktop before measuring foreground play');
await mkdir(output, {recursive: true});

const position = foreground && (benchmarkWindowPosition() || (process.platform === 'darwin' ? {left: 40, top: 55} : null));
const browser = await chromium.launch(browserTestOptions({foreground, position}));
const context = await browser.newContext({viewport: {width: 1280, height: 720}, deviceScaleFactor: 1});
const page = await context.newPage();
const report = {ok: false, browser: browser.version(), foreground, screenLockedAtLaunch, traceGL, measurements: {}, checks: {}, errors: []};
const requests = [];
report.zoneRequests = requests;
report.startup = {};
let phase = 'entry';
let peer;
let peerTimer;
let snapshot;

if (!foreground) await prepareOffscreenPage(page);
await page.addInitScript(installFrameCapture);
await page.addInitScript(() => {
  window.coastLongTasks = [];
  new PerformanceObserver(list => {
    for (const task of list.getEntries()) window.coastLongTasks.push([task.startTime, task.duration]);
  }).observe({type: 'longtask', buffered: true});
});
if (traceGL) await page.addInitScript(() => {
  const gl = WebGL2RenderingContext.prototype;
  const labels = new WeakMap();
  const programs = new WeakMap();
  const source = gl.shaderSource;
  const attach = gl.attachShader;
  gl.shaderSource = function (shader, code) {
    const custom = [...new Set(code.match(/\bm_[a-z][a-z_0-9]+/gi) || [])].slice(0,16);
    const variants = (code.match(/^#define (?:MODE|USE|ENABLE|DISABLE)_[A-Z_0-9]+/gm) || [])
      .map(line => line.slice(8));
    labels.set(shader,{custom,variants});
    return source.call(this,shader,code);
  };
  gl.attachShader = function (program, shader) {
    if (!programs.has(program)) programs.set(program,[]);
    programs.get(program).push(labels.get(shader) || null);
    return attach.call(this,program,shader);
  };
  window.coastGLCalls = [];
  for (const name of ['compileShader', 'linkProgram', 'getProgramParameter', 'texImage2D', 'compressedTexImage2D', 'bufferData']) {
    const original = gl[name];
    gl[name] = function (...args) {
      const start = performance.now();
      const result = original.apply(this, args);
      const elapsed = performance.now() - start;
      if (elapsed >= 2 || name === 'linkProgram') {
        const status = window.CooperStatus;
        window.coastGLCalls.push({name,start,elapsed,
          pose: status && [status.x,status.y,status.z,status.yaw,status.pitch,status.elapsed,status.rain],
          program: name === 'linkProgram' || name === 'getProgramParameter' ? programs.get(args[0]) : null});
      }
      return result;
    };
  }
});
page.on('pageerror', error => report.errors.push(String(error)));
page.on('console', message => {
  if (/SHADER ERROR|SCRIPT ERROR|Parse Error|Chunk load/i.test(message.text())) report.errors.push(message.text());
});
page.on('request', request => {
  if (request.url().includes('/zones/')) requests.push(new URL(request.url()).pathname);
});

const status = () => page.evaluate(() => window.CooperStatus);
const locked = () => page.evaluate(() => document.pointerLockElement === document.getElementById('canvas'));
async function shot(name) {
  const format = foreground ? 'png' : 'jpg';
  await page.screenshot({path: `${output}/${name}.${format}`, timeout: 10000});
  // Let Chrome finish screenshot capture before measuring the next input phase.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
}
async function wait(predicate, options = {}) {
  await page.waitForFunction(predicate, options.arg, {timeout: options.timeout || 11000});
  return status();
}

async function enter(name) {
  const room = `coast-${name}-${randomBytes(5).toString('hex')}`;
  entry.searchParams.set('room', room);
  await page.goto(entry.toString());
  const start = await wait(() => window.CooperStatus?.ready, {timeout: 100000});
  report.startup[name] = await page.evaluate(() => performance.now());
  if (foreground) await enterCamp(page);
  else await stageOffscreenControls(page);
  assert.ok(await locked(), 'The game did not acquire input lock');
  await page.evaluate(() => { window.coopBenchPinCamera = true; });
  assert.ok(Math.hypot(start.x - world.spawn[0], start.z - world.spawn[1]) < .4);
  return {...start, room};
}

async function joinWitness(room) {
  const endpoint = new URL('/room', entry);
  endpoint.protocol = entry.protocol === 'https:' ? 'wss:' : 'ws:';
  peer = new WebSocket(endpoint);
  await new Promise((resolve, reject) => { peer.onopen = resolve; peer.onerror = reject; });
  peer.onmessage = event => {
    const packet = JSON.parse(event.data);
    if (packet.t === 'snapshot') snapshot = packet;
  };
  peer.send(JSON.stringify({t: 'join', room, token: randomBytes(16).toString('hex')}));
  peerTimer = setInterval(() => {
    if (peer.readyState === WebSocket.OPEN) peer.send(JSON.stringify({t: 'ping'}));
  }, 3000);
}

const angle = value => Math.atan2(Math.sin(value), Math.cos(value));
async function aim(yaw, pitch) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const current = await status();
    await page.evaluate(([x,y]) => window.coopBenchMove(x, y),
      [angle(current.yaw - yaw) / .00215, (current.pitch - pitch) / .00215]);
    const aligned = await page.waitForFunction(([y,p]) => Math.abs(Math.atan2(Math.sin(CooperStatus.yaw-y),
      Math.cos(CooperStatus.yaw-y))) < .033 && Math.abs(CooperStatus.pitch-p) < .029, [yaw,pitch], {timeout: 850}).catch(() => null);
    if (aligned) return;
  }
  throw Error(`${phase} could not look toward ${yaw}, ${pitch}`);
}

async function lookAt([x,z], pitch) {
  const current = await status();
  await aim(Math.atan2(current.x - x, current.z - z), pitch);
}

async function pan(radians, duration) {
  const before = await status();
  await page.evaluate(({radians, duration}) => new Promise(done => {
    const pixels = -radians / .00215;
    const start = performance.now();
    let sent = 0;
    function turn(now) {
      const progress = Math.min(1, (now - start) / duration);
      const offset = Math.round(pixels * progress);
      if (offset !== sent) window.coopBenchMove(offset - sent, 0);
      sent = offset;
      if (progress < 1) requestAnimationFrame(turn);
      else done();
    }
    requestAnimationFrame(turn);
  }), {radians, duration});
  await wait(([start, expected]) => Math.abs(Math.atan2(Math.sin(CooperStatus.yaw - start - expected),
    Math.cos(CooperStatus.yaw - start - expected))) < .08, {arg: [before.yaw,radians]});
}

async function hold(key, action) {
  await page.keyboard.down(key);
  try { return await action(); }
  finally { await page.keyboard.up(key); }
}

async function steer([x,z], {pitch = .03, tolerance = .63, speed = 2.1} = {}) {
  const start = await status();
  const dx = x - start.x, dz = z - start.z;
  const distance = Math.hypot(dx, dz);
  if (distance <= tolerance) return;
  await aim(Math.atan2(-dx,-dz), pitch);
  const deadline = Date.now() + 4350 + distance * 1500 / speed;
  await hold('KeyW', async () => {
    let current;
    while (Date.now() < deadline) {
      current = await status();
      assert.ok(current.ready && current.connected && current.locked, `${phase} lost game input`);
      const ex = x - current.x, ez = z - current.z;
      const forward = (ex * dx + ez * dz) / distance;
      const lateral = Math.abs(ex * dz - ez * dx) / distance;
      if (Math.hypot(ex, ez) <= tolerance || forward < tolerance * .75 && lateral < tolerance * 1.7) return;
      await sleep(85);
    }
    throw Error(`${phase} stopped on the way to ${x}, ${z} at ${current?.x}, ${current?.z}`);
  });
}

async function route(points, options) {
  for (const point of points) await steer(point, options);
}

async function stopAt([x,z], tolerance, pitch = -.16) {
  let current = await status();
  for (let attempt = 0; attempt < 7; attempt++) {
    const dx = x - current.x, dz = z - current.z;
    const distance = Math.hypot(dx,dz);
    if (distance <= tolerance) return current;
    await aim(Math.atan2(-dx,-dz), pitch);
    await hold('KeyW', () => sleep(Math.min(830,Math.max(70,(distance - .10) * 265))));
    await sleep(285);
    current = await wait(() => Math.hypot(CooperStatus.localPhysics.vx,CooperStatus.localPhysics.vz) < .23,
      {timeout: 4500});
  }
  if (Math.hypot(current.x-x,current.z-z) <= tolerance) return current;
  throw Error(`${phase} could not stop at ${x}, ${z}; stopped at ${current.x}, ${current.z}`);
}

function inMine(mine, [x, y, z]) {
  const sin = Math.sin(mine.yaw);
  const cos = Math.cos(mine.yaw);
  return [mine.origin[0] + x * cos + z * sin, mine.origin[1] + y, mine.origin[2] - x * sin + z * cos];
}

async function visitMine(id, mine) {
  const approach = [];
  for (let i = 0; i < mine.route.length; i++) {
    const [x,,z] = mine.route[i];
    const [ax,,az] = mine.route[Math.max(0,i-1)];
    const [bx,,bz] = mine.route[Math.min(i+1,mine.route.length-1)];
    const legs = Math.hypot(x-ax,z-az) * Math.hypot(bx-x,bz-z);
    const bend = legs > 0 && ((x-ax)*(bx-x) + (z-az)*(bz-z))/legs < .90;
    if (bend || i % 5 === 0 || i === mine.route.length - 1) approach.push({point:[x,z],tolerance:bend ? .18 : .37});
  }
  // The mine's cross sections give the walkable center as the passage bends.
  const chamber = mine.floor.filter(section => section[0] >= 0 && section[0] < mine.gather[2])
    .filter((_, index) => index % 3 === 0)
    .map(([z,y,x]) => inMine(mine,[x,y,z])).map(([x,,z]) => ({point:[x,z],tolerance:.40}));
  const [gx,gy,gz] = inMine(mine, mine.gather);
  const nearest = mine.floor.reduce((a,b) => Math.abs(a[0] - mine.gather[2]) < Math.abs(b[0] - mine.gather[2]) ? a : b);
  const [x,,z] = inMine(mine, [nearest[2],nearest[1],mine.gather[2]]);
  await measure(`${id}WalkIn`, async () => {
    for (const {point,tolerance} of [...approach,...chamber]) await stopAt(point,tolerance);
    const current = await stopAt([x,z],.32);
    await aim(Math.atan2(current.x - gx, current.z - gz),
      Math.atan2(gy - current.y - 1.67, Math.hypot(gx - current.x,gz - current.z)));
    await wait(target => CooperStatus.mineTarget === target, {arg: id, timeout: 3500});
    const before = (await status()).mines[id].stock;
    await page.keyboard.press('KeyF');
    await wait(({id,item,before}) => CooperStatus.mines[id].stock === before - 1 && CooperStatus.survival.bag[item] > 0,
      {arg: {id, item: mine.item, before}, timeout: 3500});
  });
  await shot(id);
  await measure(`${id}WalkOut`, async () => {
    for (const {point,tolerance} of [...approach,...chamber].reverse()) await stopAt(point,tolerance);
  });
  report.checks[id] = true;
}

function timing(times) {
  const {intervalsMs, ...summary} = intervals(times);
  return {...summary, frames: times.length, over35Ms: intervalsMs.filter(ms => ms > 35).length,
    over50Ms: intervalsMs.filter(ms => ms > 50).length,
    adjacentOver50Ms: intervalsMs.some((ms, index) => ms > 50 && intervalsMs[index - 1] > 50), intervalsMs};
}

async function measure(name, play) {
  phase = name;
  const before = requests.length;
  const start = await status();
  const sampling = page.evaluate(() => window.coopBenchSample(75000));
  await page.waitForFunction(() => window.coopBenchSampling === true);
  try { await play(); }
  finally {
    await page.evaluate(() => { window.coopBenchFinish = true; });
    const {raf, submitted, ...surface} = await sampling;
    const end = await status();
    const frames = timing(submitted.map(frame => frame.time));
    const longTasks = await page.evaluate(([first,last]) => window.coastLongTasks.filter(([start,duration]) =>
      start < last && start + duration >= first), [frames.firstTimestampMs, frames.lastTimestampMs]);
    report.measurements[name] = {...surface, ...frames, animationFrames: timing(raf),
      start: [start.x,start.y,start.z], end: [end.x,end.y,end.z], rain: end.rain,
      zoneRequests: requests.slice(before), longTasks};
    if (traceGL) report.measurements[name].glCalls = await page.evaluate(([first,last]) =>
      window.coastGLCalls.filter(({start,elapsed}) => start < last && start + elapsed >= first),
      [frames.firstTimestampMs, frames.lastTimestampMs]);
    console.log(name, `${frames.fps.toFixed(1)} fps,`, `P95 ${frames.p95Ms.toFixed(1)} ms,`,
      `max ${frames.maxMs.toFixed(1)} ms,`, `${frames.over50Ms} over 50 ms`);
    assert.ok(!surface.hidden && !surface.lostFocus && await locked(), name + ' lost visibility, focus or input lock');
    assert.deepEqual(surface.buffer, [1280,720]);
    assert.ok(surface.renderer && !/swiftshader|software/i.test(surface.renderer), surface.renderer);
  }
}

try {
  await focusWindow(page, position);
  report.display = await captureBlankRaf(page);
  assert.ok(report.display.blankRefreshEligible, 'The test window cannot display 30 FPS on this screen');
  const start = await enter('walk');
  await joinWitness(start.room);
  const toLake = findPath(world,[start.x,start.z],design.entry,{margin:.80,stopDistance:.55,ship:start.ship});
  await measure('campToLake', async () => {
    if (!mineStops) return route(toLake,{tolerance:.28});
    for (const point of toLake) await stopAt(point,.32,.03);
  });
  await measure('lakeToClifftop', () => route(design.ridgeTrail));
  let current = await status();
  assert.ok(current.x < -71.15 && current.y >= 15.2 && current.zone === 'headland');
  await lookAt(design.reef, -.30);
  await shot('clifftop');
  if (mineStops) {
    for (const [id,mine] of Object.entries(mineStops)) {
      await visitMine(id,mine);
      await stopAt(design.lookout,.39);
    }
  }
  await measure('clifftopToBeach', async () => {
    if (!mineStops) return route(design.beachTrail, {pitch: -.16});
    for (const [x,z] of design.beachTrail) await stopAt([x,z],.43);
  });
  assert.ok((await status()).y < 1.75);
  await lookAt(design.reef, -.09);
  await shot('beach');
  const offshore = requests.length;
  await measure('reefSwimAndDive', async () => {
    await steer(design.reef, {pitch: -.02});
    await wait(() => CooperStatus.swimming && CooperStatus.x < -124.5);
    await steer([-144.0,-53.7], {pitch: -.02});
    await hold('KeyC', () => wait(() => CooperStatus.y < -.83, {timeout: 4000}));
  });
  await aim(Math.PI * .50, -.26);
  await shot('underwater');
  await measure('swimToIslandSummit', async () => {
    await hold('Space', () => wait(() => CooperStatus.y > -.24, {timeout: 4000}));
    await steer(design.landing);
    await route(design.islandTrail);
  });
  current = await status();
  assert.ok(current.zone === 'island' && current.y > 7.1 && !current.swimming);
  assert.ok(snapshot?.players[start.selfId]?.x < -184 && current.members === 2);
  assert.equal(requests.length, offshore);
  report.checks.sameRoomAcrossCampAndIsland = true;
  report.checks.walkSwimDiveAndLand = true;
  report.checks.offshoreZoneRequests = requests.length - offshore;
  await measure('distantCoastFromIsland', async () => {
    await lookAt(design.lookout, -.07);
    await pan(.73, 8000);
  });
  assert.deepEqual(report.measurements.distantCoastFromIsland.zoneRequests, []);
  await lookAt(design.lookout, -.07);
  await shot('island');
  clearInterval(peerTimer);
  peer.close();

  phase = 'flightEntry';
  current = await enter('flight');
  await steer([1.9,-82.1], {tolerance: .24});
  await lookAt([current.ship.x,current.ship.z], -.27);
  await wait(() => CooperStatus.shipTarget);
  await page.keyboard.press('KeyE');
  await wait(() => CooperStatus.shipPiloting);
  await measure('takeoffAndFlyToClifftop', () => hold('Space', async () => {
    await wait(() => CooperStatus.ship.y > 29, {timeout: 12000});
    await steer([-66.8,-52.3], {pitch: -.52, tolerance: 2.3, speed: 10});
    await wait(() => CooperStatus.ship.y > 46, {timeout: 8000});
  }));
  await aim(Math.PI * .50, -.64);
  await shot('airship-bay');
  await measure('fullSpeedFlightAcrossReef', () => steer([-172.0,-55.0], {pitch: -.26, tolerance: 3, speed: 10}));
  current = await status();
  assert.ok(current.ship.x < -166);
  assert.deepEqual(report.measurements.fullSpeedFlightAcrossReef.zoneRequests, []);
  report.checks.flightAcrossReef = true;
  report.checks.realPointerLock = foreground && await locked();
  await shot('airship-island');
  await measure('distantCoastFromShip', async () => {
    await steer([-226.0,-70.0], {pitch: -.22, tolerance: 2.8, speed: 10});
    await lookAt(design.lookout, -.25);
    await pan(-.73, 8000);
  });
  assert.deepEqual(report.measurements.distantCoastFromShip.zoneRequests, []);
  await lookAt(design.lookout, -.25);
  await shot('distant-coast');
  assert.deepEqual(report.errors, []);
  report.below30FpsTarget = Object.entries(report.measurements)
    .filter(([, frames]) => frames.fps < 29.8 || frames.p95Ms > 34.0).map(([name]) => name);
  report.longFrameFailures = Object.entries(report.measurements)
    .filter(([, frames]) => frames.maxMs > 100 || frames.adjacentOver50Ms
      || frames.over50Ms > (frames.frames - 1) * .01).map(([name]) => name);
  if (foreground) assert.deepEqual(report.below30FpsTarget.concat(report.longFrameFailures), [], 'Missed the frame pacing target');
  report.ok = true;
} catch (error) {
  report.failure = {phase, error: String(error)};
  const state = await status().catch(() => null);
  if (state) report.failure.state = {at: [state.x,state.y,state.z], rain: state.rain, notice: state.notice,
    mineTarget: state.mineTarget, localPhysics: state.localPhysics};
  await shot('failure').catch(() => {});
  throw error;
} finally {
  clearInterval(peerTimer);
  if (peer) peer.close();
  await writeFile(`${output}/report.json`, JSON.stringify(report, null, 2) + '\n');
  await browser.close();
}
