import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';
import {browserTestOptions, enterCamp, focusWindow, macScreenLocked, prepareOffscreenPage, stageOffscreenControls} from './coop-browser-controls.mjs';
import {installFrameCapture, intervals} from './coop-frame-capture.mjs';

const base = new URL(process.env.COOP_URL || 'http://127.0.0.1:4794/coop/');
const output = process.argv[2] || '.cache/field-atlas/playtest';
const foreground = process.env.COOP_ATLAS_FOREGROUND === '1';
const windowPosition = foreground && process.platform === 'darwin' ? {left: 40, top: 55} : null;
assert.ok(!foreground || !macScreenLocked(), 'The foreground test needs an unlocked display');
base.searchParams.set('room', 'atlas-qa-' + randomBytes(5).toString('hex'));
await mkdir(output, {recursive: true});
const browser = await chromium.launch(browserTestOptions({foreground, position: windowPosition}));
const report = {ok: false, foreground, checks: {}, errors: []};
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

async function start(viewport) {
  const context = await browser.newContext({viewport, deviceScaleFactor: 1});
  const page = await context.newPage();
  if (foreground) await focusWindow(page, windowPosition);
  else await prepareOffscreenPage(page);
  await page.addInitScript(installFrameCapture);
  page.on('pageerror', error => report.errors.push(String(error)));
  page.on('console', event => {
    if (/SCRIPT ERROR|SHADER ERROR|Parse Error/i.test(event.text())) report.errors.push(event.text());
  });
  await page.goto(base.toString());
  await wait(page, () => window.CooperStatus?.ready, null, 100000);
  return page;
}

const state = page => page.evaluate(() => window.CooperStatus);
async function wait(page, predicate, arg = null, timeout = 10000) {
  await page.waitForFunction(predicate, arg, {timeout});
  return state(page);
}

async function openMap(page) {
  await page.keyboard.press('KeyM');
  return wait(page, expected => CooperStatus.atlas.open && expected.every(site => site in CooperStatus.atlas.sites), Object.keys(travel));
}

function middle([x, y, width, height]) {
  return [x + width * .5, y + height * .5];
}

async function canvasPoint(page, point, status) {
  const bounds = await page.locator('#canvas').boundingBox();
  return [bounds.x + point[0] * bounds.width / status.viewport[0], bounds.y + point[1] * bounds.height / status.viewport[1]];
}

async function click(page, point, status, options) {
  const [x, y] = await canvasPoint(page, point, status);
  await page.mouse.click(x, y, options);
}

async function focus(page) {
  if (foreground) await focusWindow(page, windowPosition);
}

const travel = {
  root_trail: [58,-75.7], flower_valley: [191,-52], coal_mine: [90,-55], iron_mine: [265,-56], east_ridge: [322,-32.4],
  island: [-187.55, -57.1], ridge: [-69.9, -53.15], beach: [-84.8, -50.7],
  buddha: [-113.84, -78.57],
  lake: [-8.55, -49.1], tower: [6.7, -16.9], camp: [1.9, -85.0],
};

try {
  const a = await start({width: 1280, height: 720});
  const first = await state(a);
  const b = await start({width: 960, height: 540});
  const second = await wait(b, () => CooperStatus.members === 2);
  assert.notEqual(first.selfId, second.selfId);
  // Move the second player through ordinary game inputs while the first stays in the same room.
  if (foreground) await enterCamp(b);
  else await stageOffscreenControls(b);
  await b.keyboard.down('KeyW');
  await delay(690);
  await b.keyboard.up('KeyW');
  const moved = await wait(b, ([x,z]) => Math.hypot(CooperStatus.x-x, CooperStatus.z-z) > .75, [second.x,second.z]);
  await focus(a);
  if (foreground) await enterCamp(a);
  else await stageOffscreenControls(a);
  let atlas = await openMap(a);
  atlas = await wait(a, ([id,x,z]) => {
    const peer = CooperStatus.atlas.team[id];
    return peer && Math.hypot(peer[0] - x, peer[1] - z) < .7;
  },
    [second.selfId, moved.x, moved.z]);
  assert.ok(!atlas.locked);
  await a.keyboard.down('KeyW');
  await delay(460);
  await a.keyboard.up('KeyW');
  assert.ok(Math.hypot((await state(a)).x - atlas.x, (await state(a)).z - atlas.z) < .16);
  report.checks.liveTeammateAndModalControls = true;
  await a.screenshot({path: `${output}/atlas.png`});

  const island = atlas.atlas.sites.island;
  const [px, py] = await canvasPoint(a, island, atlas);
  await a.mouse.move(px, py);
  const sample = a.evaluate(() => window.coopBenchSample(4100));
  await a.waitForFunction(() => window.coopBenchSampling);
  await a.mouse.wheel(0, -240);
  let closer = await wait(a, () => CooperStatus.atlas.zoom > 1.2 && CooperStatus.atlas.cues > 0);
  assert.ok(Math.hypot(closer.atlas.sites.island[0]-island[0],closer.atlas.sites.island[1]-island[1]) < 5);
  const cueStart = closer.atlas.cues;
  await click(a, middle(closer.atlas.zoomInRect), closer);
  closer = await wait(a, cue => CooperStatus.atlas.cues > cue && CooperStatus.atlas.zoom > 1.42, cueStart);
  const [vx,vy,width,height] = closer.atlas.viewRect;
  const dragStart = await canvasPoint(a, [vx+width*.37,vy+height*.63], closer);
  await a.mouse.move(...dragStart);
  await a.mouse.down();
  await a.mouse.move(dragStart[0]+86, dragStart[1]+31, {steps: 9});
  await a.mouse.up();
  const dragged = await wait(a, x => Math.abs(CooperStatus.atlas.sites.island[0]-x) > 30, closer.atlas.sites.island[0]);
  assert.ok(dragged.atlas.open && !dragged.atlas.travelPending);
  const captured = await sample;
  const measured = intervals(captured.submitted.map(frame => frame.time));
  assert.ok(measured.fps >= 29.8 && measured.p95Ms <= 35.5);
  if (foreground) assert.ok(!captured.hidden && !captured.lostFocus && !/swiftshader/i.test(captured.renderer));
  report.zoomFrames = {...measured, renderer: captured.renderer, buffer: captured.buffer};
  await a.screenshot({path: `${output}/zoomed.png`});
  await click(a, middle(dragged.atlas.zoomOutRect), dragged);
  await wait(a, z => CooperStatus.atlas.targetZoom < z, dragged.atlas.targetZoom);
  await a.mouse.move(...dragStart);
  for (let i=0;i<11;i++) await a.mouse.wheel(0, 280);
  atlas = await wait(a, () => CooperStatus.atlas.zoom === 1);
  report.checks.cursorZoomButtonsPanAndCues = true;

  const [x,y,w,h] = atlas.atlas.viewRect;
  await click(a, [x+w*.37,y+h*.58], atlas, {button:'right'});
  atlas = await wait(a, () => Object.keys(CooperStatus.atlas.pins).length === 1);
  const pin = Object.keys(atlas.atlas.pins)[0];
  await focus(b);
  const peerMap = await openMap(b);
  assert.deepEqual(peerMap.atlas.pins, {});
  await focus(a);
  await a.reload();
  await wait(a, () => window.CooperStatus?.ready, null, 100000);
  if (foreground) await enterCamp(a);
  else await stageOffscreenControls(a);
  atlas = await openMap(a);
  assert.equal(atlas.selfId, first.selfId);
  assert.ok(atlas.atlas.pins[pin]);
  await a.screenshot({path: `${output}/personal-pin.png`});
  await click(a, atlas.atlas.pins[pin], atlas);
  atlas = await wait(a, id => CooperStatus.atlas.selectedPin === id && CooperStatus.atlas.eraseRect.length === 4, pin);
  await click(a, middle(atlas.atlas.eraseRect), atlas);
  await wait(a, () => Object.keys(CooperStatus.atlas.pins).length === 0);
  report.checks.privatePinsPersistAndDelete = true;

  const visited = {};
  for (const [site, destination] of Object.entries(travel)) {
    atlas = (await state(a)).atlas.open ? await state(a) : await openMap(a);
    await click(a, atlas.atlas.sites[site], atlas);
    const arrived = await wait(a, ([x,z]) => !CooperStatus.atlas.open && !CooperStatus.swimming
      && Math.hypot(CooperStatus.x-x,CooperStatus.z-z) < 3.3, destination);
    visited[site] = [arrived.x, arrived.y, arrived.z];
    if (site === 'island') {
      await focus(b);
      const seen = await wait(b, id => CooperStatus.atlas.team[id]?.[0] < -185, first.selfId);
      assert.equal(seen.members, 2);
      await b.screenshot({path: `${output}/teammate-on-island.png`});
      await focus(a);
    }
  }
  report.checks.groundedTravelAndTeammateUpdate = visited;
  await openMap(a);
  await a.keyboard.press('Escape');
  await wait(a, () => !CooperStatus.atlas.open);
  report.checks.escReturnsToGame = true;
  assert.deepEqual(report.errors, []);
  report.ok = true;
  console.log('Field atlas passed', {foreground, fps: measured.fps, p95: measured.p95Ms, landmarks: Object.keys(visited)});
} catch (error) {
  report.failure = String(error);
  throw error;
} finally {
  await writeFile(`${output}/report.json`, JSON.stringify(report, null, 2) + '\n');
  await browser.close();
}
