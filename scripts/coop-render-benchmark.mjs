// A/B the actual static releases and keep the individual frame timings and screenshots.
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {spawn} from 'node:child_process';
import {createHash, randomBytes} from 'node:crypto';
import {createReadStream} from 'node:fs';
import {mkdir, mkdtemp, stat, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';
import {benchmarkWindowPosition, browserTestOptions, clickCanvasPoint, enterCamp, focusWindow,
  hardwareForegroundRequested, macScreenLocked, prepareOffscreenPage, stageOffscreenControls} from './coop-browser-controls.mjs';
import {captureBlankRaf, installFrameCapture, intervals} from './coop-frame-capture.mjs';
import {divePose, installSoftwareRoomReplay, prepareSoftwareSite, recordSoftwareRoom} from './coop-render-fixtures.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const output = resolve(process.env.COOP_BENCH_OUT || '.cache/coop-render-benchmark');
const [firstBuild, secondBuild] = process.argv.slice(2);
const reference = process.env.COOP_BENCH_REFERENCE || (secondBuild ? firstBuild : '');
const candidate = process.env.COOP_BENCH_CANDIDATE || secondBuild || firstBuild || 'dist/coop';
const builds = reference ? [['before', reference], ['after', candidate]] : [['current', candidate]];
const seconds = Number(process.env.COOP_BENCH_SECONDS || 8);
const warmup = Number(process.env.COOP_BENCH_WARMUP || 5);
const basePort = Number(process.env.COOP_BENCH_PORT || 4270);
const software = process.env.COOP_BENCH_SOFTWARE === '1';
const foreground = !software && hardwareForegroundRequested(process.env.COOP_BENCH_HEADLESS);
// The client publishes its pose every quarter-second of game time. A single
// SwiftShader frame can take several real seconds on a hosted CPU.
const interactionTimeout = software ? 120000 : 6500;
const unthrottled = process.env.COOP_BENCH_UNTHROTTLED === '1';
const windowPosition = foreground ? benchmarkWindowPosition() : null;
const browserOptions = browserTestOptions({foreground, software, position: windowPosition,
  channel: process.env.COOP_BENCH_BROWSER, metal: process.env.COOP_BENCH_HEADLESS_METAL !== '0'});
const {headless, channel} = browserOptions;
const headlessMetal = browserOptions.args.includes('--use-angle=metal');
const viewport = {width: 1280, height: 720};
const dawnStart = 315.0;
const declination = Math.asin(Math.sin(2.87341195) * Math.sin(0.4090928));
const sunsetAngle = Math.acos(-Math.tan(0.75049158) * Math.tan(declination));
const sunrise = 122 + (Math.PI - sunsetAngle) * 420 / Math.PI;
const lakeWaterCamera = {at: [-10.82, -49.1], yaw: 1.53, pitch: -0.35};
const coastWaterCamera = {at: [-85.1, -51.0], yaw: 1.48, pitch: -0.34, coast: true};
const scenes = {
  forest: {at: [2.0, -71.5], yaw: -0.08, pitch: 0.10, clock: 0},
  lake: {at: [-10.82, -49.1], yaw: 1.53, pitch: -0.12, clock: 24},
  'lake-water-clear': {...lakeWaterCamera, clock: 24},
  'lake-water-rain': {...lakeWaterCamera, clock: 86, rain: 1},
  'coast-water-clear': {...coastWaterCamera, clock: 24},
  'coast-water-rain': {...coastWaterCamera, clock: 86, rain: 1},
  'shelter-rain': {at: [1.42, -90.88], yaw: 3.119, pitch: -0.054, clock: 89, rain: 1, repaired: true},
  'mine-rain': {at: [-74.045, -29.55], ground: 20.56, yaw: 0.029, pitch: -0.415, clock: 89, rain: 1, coast: true},
  'creek-ferns': {at: [-6.55, -60.05], yaw: 2.234, pitch: -0.303, clock: 86, rain: 1},
  'creek-spruce': {at: [-7.70, -63.50], yaw: 0.543, pitch: 0.557, clock: 24},
  'camp-glazed-jug': {at: [3.36, -88.07], yaw: -0.322, pitch: -0.808, clock: 24, repaired: true},
  'campfire-rain': {at: [5.16, -83.85], yaw: 2.752, pitch: -0.870, clock: 86, rain: 1, fire: true},
  lamp: {at: [2.15, -87.26], yaw: -1.75, pitch: 0.24, clock: 190, transition: 'repair'},
  dawn: {at: [2.0, -71.5], yaw: -1.47, pitch: 0.13, clock: dawnStart - warmup, transition: 'sunrise'},
  inventory: {at: [1.9, -85.0], yaw: -0.08, pitch: 0.10, clock: 30, inventory: true},
  equipment: {at: [1.9, -85.0], yaw: -0.08, pitch: 0.10, clock: 30, inventory: true, equipment: true},
  underwater: {at: [-23.5, -50.0], yaw: 1.52, pitch: -0.20, clock: 27, diving: true},
  storm: {at: [2.0, -71.5], yaw: -0.08, pitch: 0.10, clock: 86},
};
const names = (process.env.COOP_BENCH_SCENES || 'forest,lake,lamp,dawn,inventory,equipment,underwater,storm').split(',');
assert.ok(names.every(name => scenes[name]), 'COOP_BENCH_SCENES contains an unknown scene');
const combinedInventory = software && names.includes('inventory') && names.includes('equipment');
const sceneLoads = combinedInventory ? names.filter(name => name !== 'equipment') : names;
assert.ok(seconds >= 2 && seconds <= 45, 'COOP_BENCH_SECONDS must be between 2 and 45');
assert.ok(warmup >= 2 && warmup <= 20, 'COOP_BENCH_WARMUP must be between 2 and 20');
assert.ok(Number.isInteger(basePort) && basePort > 1024 && basePort <= 65530, 'Invalid COOP_BENCH_PORT');

async function startService(directory, saves, port, services) {
  await stat(resolve(directory, 'index.pck'));
  const child = spawn(process.execPath, ['scripts/coop-serve.mjs'], {
    cwd: root, stdio: ['ignore', 'pipe', 'pipe'],
    env: {...process.env, COOP_SITE_DIR: resolve(directory), COOP_PORT: String(port),
      COOP_ROOM_PORT: String(port + 1), COOP_SAVE_DIR: saves},
  });
  services.push(child);
  const origin = 'http://127.0.0.1:' + port;
  let diagnostics = '';
  for (const stream of [child.stderr, child.stdout]) stream.on('data', text => { diagnostics += text; });
  const limit = Date.now() + (software ? 30000 : 16000);
  while (Date.now() < limit && child.exitCode === null) {
    const status = await fetch(origin + '/health').then(response => response.json()).catch(() => null);
    if (status?.game === 'cooper-camp' && status.ready && diagnostics.includes(saves)) return origin;
    await new Promise(done => setTimeout(done, 120));
  }
  throw Error('Co-op benchmark service did not start on ' + origin + '\n' + diagnostics);
}

async function aim(page, scene) {
  for (let attempt = 0; attempt < 4; attempt++) {
    const actual = await page.evaluate(() => ({yaw: CooperStatus.yaw, pitch: CooperStatus.pitch}));
    const yawError = Math.atan2(Math.sin(scene.yaw - actual.yaw), Math.cos(scene.yaw - actual.yaw));
    const pitchError = scene.pitch - actual.pitch;
    if (Math.abs(yawError) < 0.004 && Math.abs(pitchError) < 0.004) return;
    await page.evaluate(([x, y]) => {
      window.coopBenchPreviousAimStatus = window.CooperStatus;
      window.coopBenchMove(x, y);
    }, [-yawError / 0.00215, -pitchError / 0.00215]);
    await page.waitForFunction(() => window.CooperStatus !== window.coopBenchPreviousAimStatus,
      null, {timeout: interactionTimeout});
  }
  throw Error('Could not set the benchmark camera using mouse input');
}

async function canvasScreenshot(page, file) {
  const clip = await page.evaluate(() => {
    const {x, y, width, height} = document.getElementById('canvas').getBoundingClientRect();
    return {x, y, width, height};
  });
  assert.ok(clip.width > 0 && clip.height > 0, 'Missing game canvas');
  await page.screenshot({path: resolve(output, file), clip, timeout: software ? interactionTimeout : 30000});
}

async function gamePackageSha(directory) {
  const hash = createHash('sha256');
  for await (const bytes of createReadStream(resolve(directory, 'index.pck'))) hash.update(bytes);
  return hash.digest('hex');
}

async function openInventory(page) {
  await page.keyboard.press('Tab');
  await page.waitForFunction(() => window.CooperStatus?.backpackOpen, null, {timeout: interactionTimeout});
  const bag = await page.evaluate(() => CooperStatus.survival?.bag);
  assert.ok(bag?.apple > 0 && bag?.jacket > 0, 'The fixture must contain one food and one spare garment');
}

async function selectEquipment(page, allowLegacy) {
  const point = await page.evaluate(() => {
    if (!CooperStatus.equipmentTabRect) return null;
    const [x, y, width, height] = CooperStatus.equipmentTabRect;
    return [(x + width / 2) / CooperStatus.viewport[0], (y + height / 2) / CooperStatus.viewport[1]];
  });
  if (!point && allowLegacy) return false;
  assert.ok(point, 'Candidate must expose the equipment tab rectangle for this scene');
  await clickCanvasPoint(page, point);
  await page.waitForFunction(() => CooperStatus.equipmentOpen, null, {timeout: interactionTimeout});
  return true;
}

await mkdir(output, {recursive: true});
const scratch = await mkdtemp(resolve(output, 'rooms-'));
const services = [];
const runs = [];
const softwareFixtures = new Map();
const report = {viewport, seconds, warmup, channel, headless, software, headlessMetal, unthrottled, windowPosition,
  date: new Date().toISOString(), runs};
let browser;
let page;
let activeRun;
let errors = [];
try {
  if (!headless && macScreenLocked()) {
    report.environment = {timingEligible: false, screenLocked: true};
    throw Error('The macOS user session is locked');
  }
  const servers = await Promise.all(builds.map(async ([label, directory], index) => {
    const saves = resolve(scratch, label);
    await mkdir(saves);
    const site = software ? await prepareSoftwareSite(directory, resolve(scratch, 'site-' + label)) : directory;
    const origin = await startService(site, saves, basePort + index * 2, services);
    return {label, directory: resolve(directory), saves, origin};
  }));
  if (unthrottled) browserOptions.args.push('--disable-frame-rate-limit', '--disable-gpu-vsync');
  browser = await chromium.launch(browserOptions);
  report.browser = browser.version();
  report.builds = await Promise.all(servers.map(async ({label, directory}) =>
    ({label, directory, pckSha256: await gamePackageSha(directory)})));
  const context = await browser.newContext({viewport, deviceScaleFactor: 1});
  if (software) {
    context.setDefaultTimeout(interactionTimeout);
    await installSoftwareRoomReplay(context, softwareFixtures);
    report.softwareFixture = 'Production room replies and a frame-stepped Godot clock. Browser frame intervals remain real wall time.';
  }
  const token = randomBytes(16).toString('hex');
  await context.addInitScript(identity => sessionStorage.setItem('cooper-identity', identity), token);
  await context.addInitScript(installFrameCapture);
  const blankPage = await context.newPage();
  if (headless) await prepareOffscreenPage(blankPage);
  else await focusWindow(blankPage, windowPosition);
  await blankPage.waitForTimeout(300);
  report.environment = await captureBlankRaf(blankPage);
  report.environment.timingEligible = report.environment.blankRefreshEligible && !headless && !software && !unthrottled;
  const blankRaf = report.environment.blankRaf;
  console.log(`Blank tab ${blankRaf.fps.toFixed(2)} FPS, P95 ${blankRaf.p95Ms.toFixed(2)} ms`);
  await blankPage.close();
  for (const name of sceneLoads) {
    const scene = scenes[name];
    for (const {label, saves, origin} of servers) {
      activeRun = {label, scene: name};
      console.log(`Loading ${label} ${name}`);
      errors = [];
      page = await context.newPage();
      if (headless) await prepareOffscreenPage(page);
      page.on('pageerror', error => errors.push(error.message));
      page.on('console', message => {
        if (message.type() === 'error') errors.push(message.text());
      });
      page.on('response', response => {
        if (response.status() >= 400 && new URL(response.url()).pathname.startsWith('/coop/')) {
          errors.push(response.status() + ' ' + response.url());
        }
      });
      const room = 'render-' + name;
      const id = createHash('sha256').update(room + ':' + token).digest('hex').slice(0, 16);
      const [x, z] = scene.at;
      await writeFile(resolve(saves, room + '.json'), JSON.stringify({
        version: 1, elapsed: scene.clock, groveStartedAt: 0,
        quest: {wood: !!scene.repaired || scene.transition === 'repair',
          tarp: !!scene.repaired || scene.transition === 'repair', repaired: !!scene.repaired},
        homes: {[id]: {x, y: scene.ground, z, yaw: scene.yaw}},
        ...(scene.fire ? {storage: {'camp-storage-6': {kind: 'campfire', at: [4.75, 0, -82.85], fuelUntil: 122}}} : {}),
        ...(scene.inventory ? {survival: {[id]: {bag: {apple: 2, bread: 1, jacket: 1}}}} : {}),
      }));
      let recordedDiveY = null;
      if (software) {
        activeRun.step = 'record-room';
        const fixture = await recordSoftwareRoom(origin, room, token, scene, warmup);
        fixture.sunrise = scene.transition === 'sunrise';
        softwareFixtures.set(new URL(origin).host + '/' + room, fixture);
        if (scene.diving) recordedDiveY = fixture.submerged.players[fixture.welcome.id].y;
      }
      activeRun.step = 'load-room';
      await page.goto(`${origin}/coop/?room=${room}`, {waitUntil: 'domcontentloaded'});
      if (software) {
        // The opaque loading screen covers the main canvas while Godot warms its subviewports.
        // Limit its pixel load on a CPU rasterizer until the real room is ready.
        await page.locator('#canvas').evaluate(canvas => { canvas.width = 320; canvas.height = 180; });
      }
      if (!headless) await focusWindow(page, windowPosition);
      await page.waitForFunction(coast => window.CooperStatus?.ready &&
        (coast ? CooperStatus.focusReady : CooperStatus.resident >= 3) &&
        document.getElementById('loader').hidden, !!scene.coast, {timeout: software ? 420000 : 50000});
      if (software) {
        await page.locator('#canvas').evaluate((canvas, size) => {
          window.coopFixtureSetStep(1 / 15);
          canvas.width = size.width;
          canvas.height = size.height;
        }, viewport);
        await page.waitForFunction(size => {
          const gl = document.getElementById('canvas').getContext('webgl2');
          return gl?.drawingBufferWidth === size.width && gl.drawingBufferHeight === size.height &&
            CooperStatus.viewport[0] === size.width && CooperStatus.viewport[1] === size.height;
        }, viewport, {timeout: interactionTimeout});
      }
      const initial = await page.evaluate(() => window.CooperStatus);
      assert.ok(Math.hypot(initial.x - x, initial.z - z) < 0.05, 'Room spawn moved for ' + name);
      if (scene.ground !== undefined) {
        assert.ok(Math.abs(initial.y - scene.ground) < 0.1,
          `Room did not restore the expected floor for ${name}: ${initial.y} vs ${scene.ground}`);
      }
      assert.equal(initial.quest.repaired, !!scene.repaired);
      if (scene.transition === 'repair') {
        assert.equal(initial.quest.wood && initial.quest.tarp, true, 'Lamp fixture lacks materials');
        await page.waitForFunction(() => CooperStatus.nearby === 'repair', null, {timeout: interactionTimeout});
      }
      activeRun.step = 'position-camera';
      if (headless) await stageOffscreenControls(page, interactionTimeout);
      else await enterCamp(page);
      await page.evaluate(() => { window.coopBenchPinCamera = true; });
      await aim(page, scene);
      if (scene.inventory && (software || scene.equipment)) await openInventory(page);
      let diveY;
      if (scene.diving) {
        activeRun.step = 'settle-dive';
        assert.ok(initial.swimming, 'The dive fixture must spawn at the water surface');
        // Hold the actual dive input until movement clamps at the lakebed. Stopping
        // at the first submerged sample leaves the depth dependent on polling speed.
        await page.keyboard.down('c');
        try {
          await page.waitForFunction(({maxY, tolerance, recordedY}) => {
            const status = window.CooperStatus;
            if (!status?.swimming || status.y >= maxY) return false;
            const player = status.players?.[status.selfId];
            if (!player?.swimming || Math.abs(status.y - player.y) > tolerance) return false;
            if (recordedY !== null) return Math.abs(status.y - recordedY) <= tolerance;
            const prior = window.coopBenchDive;
            if (status === prior?.status) return false;
            const settled = prior && Math.abs(status.y - prior.status.y) <= tolerance ? prior.settled + 1 : 0;
            window.coopBenchDive = {status, settled};
            return settled >= 2;
          }, {...divePose, recordedY: recordedDiveY}, {timeout: interactionTimeout});
          diveY = await page.evaluate(() => CooperStatus.y);
        } finally {
          await page.keyboard.up('c');
        }
      }
      const views = combinedInventory && name === 'inventory' ? ['inventory', 'equipment'] : [name];
      for (const view of views) {
        activeRun.scene = view;
        activeRun.step = 'select-view';
        const equipment = !!scenes[view].equipment;
        if (software && equipment) await page.evaluate(() => window.coopFixtureSetStep(1 / 15));
        let legacyInventory = software && equipment && !await selectEquipment(page, label === 'before');
        const timeInventoryAction = !software && scene.inventory;
        const screenshotClock = scene.clock + warmup;
        activeRun.step = 'before-screenshot';
        await page.waitForFunction(clock => CooperStatus.elapsed >= clock, screenshotClock, {timeout: interactionTimeout});
        if (software) await page.evaluate(() => window.coopFixtureSetStep(1 / 60));
        const screenshot = label + '-' + view + '.png';
        const beforeScreenshot = scene.transition ? label + '-' + view + '-before.png' : screenshot;
        const still = await page.evaluate(() => window.CooperStatus);
        assert.equal(still.rain, scene.rain ?? (name === 'storm' ? 1 : 0));
        assert.equal(still.dayPart, name === 'dawn' ? 'dawn' : name === 'lamp' ? 'night' : 'day');
        if (!timeInventoryAction && (!software || scene.transition)) await canvasScreenshot(page, beforeScreenshot);
        await page.waitForTimeout(400);
        const start = await page.evaluate(() => window.CooperStatus);
        const sampleSeconds = scene.transition === 'sunrise' ? Math.max(seconds, 7.5)
          : software && scene.transition === 'repair' ? 2 * interactionTimeout / 1000 : seconds;
        const collecting = page.evaluate(([ms, minimumFrames]) => window.coopBenchSample(ms, minimumFrames),
          [sampleSeconds * 1000, software ? 3 : 0]);
        let transition;
        let inventoryAction;
        activeRun.step = 'capture-frames';
        if (scene.transition === 'repair') {
          activeRun.step = 'confirm-repair';
          await page.waitForFunction(() => window.coopBenchSampling, null, {timeout: interactionTimeout});
          if (software) await page.evaluate(() => window.coopFixtureSetStep(1 / 15));
          const requested = await page.evaluate(() => performance.now());
          await page.keyboard.press('e');
          await page.waitForFunction(() => CooperStatus.quest.repaired, null, {timeout: interactionTimeout});
          transition = await page.evaluate(time => ({type: 'repair', requestBrowserTime: time,
            confirmedBrowserTime: performance.now(), confirmedRoomTime: CooperStatus.elapsed}), requested);
          if (software) {
            // Let the regular fade reach full brightness in simulated time,
            // even if each SwiftShader frame takes several wall-clock seconds.
            const settled = await page.evaluate(() => window.coopFixtureClock() + 640);
            await page.waitForFunction(target => window.coopFixtureClock() >= target, settled, {timeout: interactionTimeout});
            await page.evaluate(() => {
              window.coopFixtureSetStep(1 / 60);
              window.coopBenchFinish = true;
            });
          }
        } else if (timeInventoryAction) {
          activeRun.step = 'open-inventory-view';
          await page.waitForFunction(() => window.coopBenchSampling, null, {timeout: interactionTimeout});
          const requested = await page.evaluate(() => performance.now());
          if (equipment) legacyInventory = !await selectEquipment(page, label === 'before');
          else await openInventory(page);
          if (!legacyInventory) {
            inventoryAction = {type: equipment ? 'open-equipment' : 'open-inventory', requestBrowserTime: requested,
              confirmedBrowserTime: await page.evaluate(() => performance.now())};
          }
        }
        const capture = await collecting;
        activeRun.step = 'verify-scene';
        const end = await page.evaluate(() => window.CooperStatus);
        if (scene.diving) {
          assert.ok(still.swimming && end.swimming && Math.abs(still.y - diveY) <= divePose.tolerance &&
            Math.abs(end.y - diveY) <= divePose.tolerance, 'The camera depth changed during the submerged sample');
        }
        if (scene.transition === 'sunrise') {
          assert.ok(start.elapsed < sunrise && end.elapsed > sunrise, 'The timing sample missed sunrise');
          transition = {type: 'sunrise', roomTime: sunrise};
        }
        if (transition) {
          if (transition.type === 'repair') {
            assert.ok(capture.submitted[0]?.time <= transition.requestBrowserTime &&
              capture.submitted.at(-1)?.time >= transition.confirmedBrowserTime, 'The timing sample missed the repair');
          }
          await canvasScreenshot(page, screenshot);
        }
        if (timeInventoryAction || (software && !scene.transition)) {
          if (inventoryAction) {
            assert.ok(capture.submitted[0]?.time <= inventoryAction.requestBrowserTime &&
              capture.submitted.at(-1)?.time >= inventoryAction.confirmedBrowserTime, 'The timing sample missed the inventory action');
          }
          await canvasScreenshot(page, screenshot);
        }
        const observedWindow = await page.evaluate(() => ({x: screenX, y: screenY,
          availWidth: screen.availWidth, availHeight: screen.availHeight}));
        assert.ok(!capture.hidden && !capture.lostFocus && capture.submitted.length >= 2, 'Lost active canvas frame submissions');
        assert.deepEqual(capture.buffer, [viewport.width, viewport.height]);
        assert.ok(Math.hypot(end.x - x, end.z - z) < 0.05 && Math.abs(end.yaw - scene.yaw) < 0.006 &&
          Math.abs(end.pitch - scene.pitch) < 0.006, 'Camera moved during ' + view);
        assert.equal(end.terrainError, '');
        const frames = intervals(capture.submitted.map(entry => entry.time));
        const knownGpu = !!capture.renderer && !/swiftshader|llvmpipe|software|swrast|lavapipe/i.test(capture.renderer);
        const run = {label, scene: view, screenshot, viewport: capture.buffer, window: observedWindow, renderer: capture.renderer,
          vendor: capture.vendor, targetM1: knownGpu && /Apple M1[,)]/i.test(capture.renderer),
          hardwareRenderer: knownGpu, errors: [...errors], fixedPose: {x, y: end.y, z, yaw: end.yaw, pitch: end.pitch},
          roomClock: {seed: scene.clock, requestedScreenshot: screenshotClock,
            screenshot: timeInventoryAction || (software && !scene.transition) ? end.elapsed : still.elapsed,
            start: start.elapsed, end: end.elapsed, rain: still.rain, dayPart: still.dayPart, repaired: end.quest.repaired},
          raf: intervals(capture.raf), frames,
          drawCalls: capture.submitted.map(entry => entry.drawCalls),
          submittedTriangles: capture.submitted.map(entry => entry.triangles),
        };
        if (scene.inventory) {
          run.inventory = {open: end.backpackOpen, equipment: !!end.equipmentOpen, bag: end.survival.bag,
            legacyInventory, action: inventoryAction};
        }
        if (transition) run.transition = {...transition, beforeScreenshot, afterScreenshot: screenshot};
        runs.push(run);
        await writeFile(resolve(output, 'render-benchmark.json'), JSON.stringify(report, null, 2) + '\n');
        console.log(`${label} ${view} ${frames.fps.toFixed(2)} FPS, P95 ${frames.p95Ms.toFixed(2)} ms, ${capture.renderer}`);
        assert.deepEqual(run.errors, [], `${label} ${view} browser errors`);
      }
      await page.keyboard.press('Escape');
      await page.close();
      page = null;
    }
  }
} catch (error) {
  const state = page && await page.evaluate(() => ({
    status: window.CooperStatus, focused: document.hasFocus(), locked: !!document.pointerLockElement,
  })).catch(() => null);
  report.failure = {...activeRun, message: error.message, errors, browserState: state};
  if (report.environment?.screenLocked) {
    console.error(error.message);
    process.exitCode = 2;
  } else throw error;
} finally {
  try {
    await writeFile(resolve(output, 'render-benchmark.json'), JSON.stringify(report, null, 2) + '\n');
  } finally {
    if (browser) await browser.close();
    await Promise.all(services.map(async child => {
      if (child.exitCode === null && child.signalCode === null) {
        const exited = once(child, 'exit');
        child.kill('SIGTERM');
        await exited;
      }
    }));
  }
}
