import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';
import {benchmarkWindowPosition, browserTestOptions, enterCamp, focusWindow, macScreenLocked} from './coop-browser-controls.mjs';
import {captureBlankRaf, installFrameCapture, intervals} from './coop-frame-capture.mjs';
import {findPath} from './coop-test-path.mjs';

const entry = new URL(process.env.COOP_URL || 'http://127.0.0.1:4494/coop/');
const output = process.argv[2] || '.cache/coast/foreground';
const design = JSON.parse(await readFile('coop/coast_layout.json', 'utf8'));
const world = JSON.parse(await readFile('coop/world.json', 'utf8'));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
assert.ok(!macScreenLocked(), 'Unlock the desktop before measuring foreground play');
await mkdir(output, {recursive: true});

const position = benchmarkWindowPosition() || (process.platform === 'darwin' ? {left: 40, top: 55} : null);
const browser = await chromium.launch(browserTestOptions({foreground: true, position}));
const context = await browser.newContext({viewport: {width: 1280, height: 720}, deviceScaleFactor: 1});
const page = await context.newPage();
const report = {ok: false, browser: browser.version(), measurements: {}, checks: {}, errors: []};
const requests = [];
let phase = 'entry';
let peer;
let peerTimer;
let snapshot;

await page.addInitScript(installFrameCapture);
await page.addInitScript(() => {
  window.coastLongTasks = [];
  new PerformanceObserver(list => {
    for (const task of list.getEntries()) window.coastLongTasks.push([task.startTime, task.duration]);
  }).observe({type: 'longtask', buffered: true});
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
  await page.screenshot({path: `${output}/${name}.png`, timeout: 10000});
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
  await enterCamp(page);
  assert.ok(await locked(), 'Chrome did not acquire real pointer lock');
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
    console.log(name, `${frames.fps.toFixed(1)} fps,`, `P95 ${frames.p95Ms.toFixed(1)} ms,`,
      `max ${frames.maxMs.toFixed(1)} ms,`, `${frames.over50Ms} over 50 ms`);
    assert.ok(!surface.hidden && !surface.lostFocus && await locked(), name + ' lost foreground');
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
  await measure('campToLake', () => route(findPath(world, [start.x,start.z], design.entry,
    {margin: .80, stopDistance: .55, ship: start.ship}), {tolerance: .28}));
  await measure('lakeToClifftop', () => route(design.ridgeTrail));
  let current = await status();
  assert.ok(current.x < -71.15 && current.y >= 15.2 && current.zone === 'headland');
  await lookAt(design.reef, -.30);
  await shot('clifftop');
  await measure('clifftopToBeach', () => route(design.beachTrail, {pitch: -.16}));
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
  report.checks.realPointerLock = await locked();
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
  assert.deepEqual(report.below30FpsTarget.concat(report.longFrameFailures), [], 'Missed the frame pacing target');
  report.ok = true;
} catch (error) {
  report.failure = {phase, error: String(error)};
  await shot('failure').catch(() => {});
  throw error;
} finally {
  clearInterval(peerTimer);
  if (peer) peer.close();
  await writeFile(`${output}/report.json`, JSON.stringify(report, null, 2) + '\n');
  await browser.close();
}
