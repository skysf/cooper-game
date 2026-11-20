import assert from "node:assert/strict";
import {createHash, randomBytes} from "node:crypto";
import {mkdir, writeFile} from "node:fs/promises";
import {resolve} from "node:path";
import {chromium} from "playwright";
import {browserTestOptions, prepareOffscreenPage, stageOffscreenControls} from "./coop-browser-controls.mjs";
import {installFrameCapture} from "./coop-frame-capture.mjs";

const output = resolve(process.env.COOP_CONSTRUCTION_EVIDENCE || ".cache/construction-web-qa");
const saves = resolve(process.env.COOP_SAVE_DIR || ".local-rooms/construction-preview");
const address = new URL(process.env.COOP_TEST_URL || "http://127.0.0.1:5084/coop/");
const room = "cabin-" + randomBytes(4).toString("hex");
const identity = randomBytes(16).toString("hex");
const player = createHash("sha256").update(room + ":" + identity).digest("hex").slice(0, 16);
address.searchParams.set("room", room);
const center = [9.8, 0, -74.5];
const start = {x: 9.8, z: -71.96, yaw: 0};
await mkdir(output, {recursive: true});
await writeFile(resolve(saves, room + ".json"), JSON.stringify({
  version: 1, elapsed: 4, homes: {[player]: start}, survival: {[player]: {bag: {wood_plank: 60}}},
  quest: {wood: false, tarp: false, repaired: false},
}), {flag: "wx"});

const browser = await chromium.launch(browserTestOptions());
const page = await browser.newPage({viewport: {width: 1280, height: 720}});
const report = {room, worldCenter: center, checks: [], errors: []};
const read = () => page.evaluate(() => window.CooperStatus);
const wait = (predicate, arg, timeout = 7000) => page.waitForFunction(predicate, arg, {timeout});

async function aim([x, y, z]) {
  const state = await read();
  const dx = x - state.x;
  const dz = z - state.z;
  const yaw = Math.atan2(-dx, -dz);
  const pitch = Math.atan2(y - (state.y + 1.67), Math.hypot(dx, dz));
  const turn = state.yaw - yaw;
  await page.evaluate(([horizontal, vertical]) => window.coopBenchMove(horizontal, vertical),
    [Math.atan2(Math.sin(turn), Math.cos(turn)) / .00215, (state.pitch - pitch) / .00215]);
  await wait(({yaw, pitch}) => {
    const turn = CooperStatus.yaw - yaw;
    return Math.abs(Math.atan2(Math.sin(turn), Math.cos(turn))) < .018 && Math.abs(CooperStatus.pitch - pitch) < .018;
  }, {yaw, pitch});
}

async function walk(x, z) {
  let pose = await read();
  for (let attempt = 0; attempt < 3; attempt++) {
    const distance = Math.hypot(x - pose.x, z - pose.z);
    if (distance < .28) return;
    await aim([x, pose.y + 1.67, z]);
    await page.keyboard.down("KeyW");
    try {
      await wait(({x, z, ux, uz}) => (x - CooperStatus.x) * ux + (z - CooperStatus.z) * uz < .34,
        {x, z, ux: (x - pose.x) / distance, uz: (z - pose.z) / distance}, 11000);
    } finally {
      await page.keyboard.up("KeyW");
    }
    await wait(() => Math.hypot(CooperStatus.localPhysics.vx, CooperStatus.localPhysics.vz) < .2);
    pose = await read();
    if (Math.hypot(pose.x - x, pose.z - z) < .68) return;
  }
  throw new Error(`Avatar did not reach the walking waypoint ${x}, ${z}; stopped at ${pose.x}, ${pose.z}`);
}

async function select(recipe) {
  await page.keyboard.press("KeyK");
  await wait(() => CooperStatus.storagePanel.mode === "craft");
  for (let i = 0; i < 4; i++) {
    const button = (await read()).storagePanel.recipes[recipe];
    assert.ok(button && !button.disabled, "the required materials enable the recipe");
    if (button.visible && button.rect[3] > 18) {
      const [x, y, width, height] = button.rect;
      await page.mouse.click(x + width / 2, y + height / 2);
      break;
    }
    await page.mouse.move(800, 580);
    await page.mouse.wheel(0, 350);
    await page.waitForTimeout(220);
  }
  await wait(recipe => !CooperStatus.storageOpen && CooperStatus.placementPreview.recipe === recipe, recipe);
  if (!(await read()).locked) {
    await page.locator("#canvas").click({position: {x: 1150, y: 580}});
    await wait(() => CooperStatus.locked);
  }
}

async function preview(target, snap, valid, expected = null) {
  await aim(target);
  if (snap) {
    await page.keyboard.down("ShiftLeft");
    await page.waitForTimeout(220);
  }
  return wait(({valid, expected}) => {
    const pose = CooperStatus.placementPreview;
    return pose.visible && pose.ok === valid && (!expected || expected.every((value, i) => Math.abs(pose.at[i] - value) < .035));
  }, {valid, expected});
}

async function build(target, snap, cost, {image, mouse = false, expected = null} = {}) {
  const boards = (await read()).survival.bag.wood_plank;
  try {
    await preview(target, snap, true, expected);
    if (image) await page.screenshot({path: resolve(output, image), type: "jpeg", quality: 90});
    if (mouse) {
      await page.mouse.down();
      await page.mouse.up();
    } else {
      await page.keyboard.press("KeyG");
    }
    await wait(count => CooperStatus.survival.bag.wood_plank === count, boards - cost);
  } finally {
    if (snap) await page.keyboard.up("ShiftLeft");
  }
}

try {
  await prepareOffscreenPage(page);
  await page.addInitScript(installFrameCapture);
  await page.addInitScript(value => sessionStorage.setItem("cooper-identity", value), identity);
  page.on("pageerror", error => report.errors.push(error.message));
  page.on("console", message => {
    if (/SCRIPT ERROR|Parse Error|SHADER ERROR/.test(message.text())) report.errors.push(message.text());
  });
  await page.goto(address.href, {waitUntil: "domcontentloaded"});
  await wait(() => window.CooperStatus?.ready || window.CooperStatus?.status === "无法读取房间存档", null, 150000);
  assert.equal((await read()).ready, true, (await read()).status);
  await stageOffscreenControls(page, 20000);
  assert.equal((await read()).survival.bag.wood_plank, 60);
  await select("cabin_floor");
  await build(center, false, 7, {image: "green-floor.jpg"});
  report.checks.push("K recipe, green floor preview and G consume seven boards");

  await select("cabin_doorway");
  await build([9.8, .18, -73.27], true, 6, {mouse: true, expected: [9.8,.18,-73.18]});
  report.checks.push("Shift snaps the doorway to its floor and a left click confirms");

  await select("cabin_roof");
  try {
    await preview([9.8, 2.33, -73.07], true, false);
    await page.screenshot({path: resolve(output, "red-roof.jpg"), type: "jpeg", quality: 90});
    await page.keyboard.press("KeyG");
    assert.equal((await read()).survival.bag.wood_plank, 47);
  } finally {
    await page.keyboard.up("ShiftLeft");
  }
  report.checks.push("unsupported roof is red and confirming leaves the bag unchanged");

  await select("cabin_wall");
  await walk(7.96, -72.30);
  await walk(7.96, -74.51);
  await build([8.57, .18, -74.50], true, 6, {expected: [8.48,.18,-74.5]});
  await walk(7.96, -76.64);
  await walk(9.83, -76.71);
  await build([9.80, .18, -75.73], true, 6, {expected: [9.8,.18,-75.82]});
  await walk(12.04, -76.62);
  await walk(12.00, -74.55);
  await build([11.03, .18, -74.50], true, 6, {expected: [11.12,.18,-74.5]});
  await walk(12.05, -72.14);
  await walk(start.x, start.z);
  await select("cabin_roof");
  await build([9.8, 2.33, -73.07], true, 8, {expected: [9.8,2.48,-74.5]});
  report.checks.push("W navigation, three snapped walls and both sides supporting the same roof");
  await page.keyboard.press("Escape");
  await stageOffscreenControls(page);
  await aim([9.80, 1.43, -74.58]);
  await page.screenshot({path: resolve(output, "finished-cabin.jpg"), type: "jpeg", quality: 90});
  await walk(9.8, -74.47);
  assert.ok(Math.abs((await read()).y - .18) < .022);
  report.checks.push("walk through the finished doorway onto the raised floor");
  await walk(9.8, -71.15);
  await walk(12.70, -70.72);
  await aim([9.8, 1.47, -74.50]);
  await page.screenshot({path: resolve(output, "cabin-exterior.jpg"), type: "jpeg", quality: 90});
  assert.deepEqual(report.errors, []);
  report.ok = true;
} catch (error) {
  report.failure = error.message;
  report.state = await page.evaluate(() => {
    const s = window.CooperStatus;
    return s && {x: s.x, y: s.y, z: s.z, yaw: s.yaw, pitch: s.pitch, bag: s.survival?.bag,
      status: s.status, locked: s.locked, target: s.storageTarget, panel: s.storagePanel, preview: s.placementPreview};
  }).catch(() => null);
  await page.screenshot({path: resolve(output, "failure.jpg"), type: "jpeg", quality: 85}).catch(() => {});
  process.exitCode = 1;
} finally {
  await writeFile(resolve(output, "report.json"), JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify(report));
  await browser.close();
}
