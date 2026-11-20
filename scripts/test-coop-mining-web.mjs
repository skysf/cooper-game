import assert from "node:assert/strict";
import {createHash, randomBytes} from "node:crypto";
import {mkdir, readFile, writeFile} from "node:fs/promises";
import {resolve} from "node:path";
import {chromium} from "playwright";
import {browserTestOptions, prepareOffscreenPage, stageOffscreenControls} from "./coop-browser-controls.mjs";
import {installFrameCapture} from "./coop-frame-capture.mjs";

const output = resolve(process.env.COOP_MINING_EVIDENCE || ".cache/mining-web-qa");
const saves = resolve(process.env.COOP_SAVE_DIR || ".local-rooms/mining-preview");
const address = new URL(process.env.COOP_TEST_URL || "http://127.0.0.1:5184/coop/");
const manifest = JSON.parse(await readFile("coop/props/mines/mines_manifest.json", "utf8"));
const identity = randomBytes(16).toString("hex");
const browser = await chromium.launch(browserTestOptions());
const page = await browser.newPage({viewport: {width: 1280, height: 720}});
const report = {checks: [], pickups: [], errors: []};
const read = () => page.evaluate(() => window.CooperStatus);
const wait = (predicate, arg, timeout = 10000) => page.waitForFunction(predicate, arg, {timeout});
await mkdir(output, {recursive: true});

async function openRoom(label, home, bag, elapsed = 14) {
  const room = label + "-" + randomBytes(4).toString("hex");
  const player = createHash("sha256").update(room + ":" + identity).digest("hex").slice(0, 16);
  const fixture = {version: 1, elapsed, homes: {[player]: home}, survival: {[player]: {bag}},
    quest: {wood: false, tarp: false, repaired: false}};
  await writeFile(resolve(saves, room + ".json"), JSON.stringify(fixture), {flag: "wx"});
  address.searchParams.set("room", room);
  await page.goto(address.href, {waitUntil: "domcontentloaded"});
  await wait(() => window.CooperStatus?.ready || window.CooperStatus?.status === "无法读取房间存档", null, 120000);
  assert.equal((await read()).ready, true, (await read()).status);
  await stageOffscreenControls(page, 20000);
}

function mineWorldPoint(mine, [x, y, z]) {
  const sin = Math.sin(mine.yaw);
  const cos = Math.cos(mine.yaw);
  return [mine.origin[0] + x * cos + z * sin, mine.origin[1] + y, mine.origin[2] - x * sin + z * cos];
}

async function aim([x, y, z]) {
  const state = await read();
  const dx = x - state.x;
  const dz = z - state.z;
  const direction = Math.atan2(-dx, -dz);
  const vertical = Math.atan2(y - state.y - 1.67, Math.hypot(dx, dz));
  const angle = state.yaw - direction;
  await page.evaluate(([x, y]) => window.coopBenchMove(x, y),
    [Math.atan2(Math.sin(angle), Math.cos(angle)) / .00215, (state.pitch - vertical) / .00215]);
}

async function clickAction(action) {
  await wait(action => {
    const item = CooperStatus.storagePanel.recipes[action];
    return item?.visible && !item.disabled;
  }, action, action === "take_ingot" ? 54000 : 9000);
  await clickRect((await read()).storagePanel.recipes[action].rect);
}

async function clickRect([x, y, width, height]) {
  await page.mouse.click(x + width / 2, y + height / 2);
}

async function screenshot(name) {
  await page.screenshot({path: resolve(output, name + ".jpg"), type: "jpeg", quality: 90});
}

async function dropAndRecover(item) {
  const before = await read();
  assert.equal(before.survival.bag[item],1);
  const known = Object.keys(before.provisions);
  await page.keyboard.press("Tab");
  await wait(item => CooperStatus.inventoryPanel.open &&
    CooperStatus.inventoryPanel.slots.some(slot => slot.visible && slot.item === item),item);
  await clickRect((await read()).inventoryPanel.slots.find(slot => slot.visible && slot.item === item).rect);
  await wait(item => CooperStatus.inventoryPanel.selectedItem === item &&
    CooperStatus.inventoryPanel.actions.drop.visible && !CooperStatus.inventoryPanel.actions.drop.disabled,item);
  await clickRect((await read()).inventoryPanel.actions.drop.rect);
  const dropped = await wait(({item,known}) => {
    const state = CooperStatus;
    const match = Object.entries(state.provisions).find(([id,entry]) =>
      !known.includes(id) && entry.item === item && entry.surface === "ground");
    if (!match || state.survival.bag[item]) return false;
    const mesh = state.provisionScene.find(node => node.id === match[0] && node.visible);
    return mesh && {id:match[0],at:match[1].at,mesh:mesh.at};
  },{item,known}).then(handle => handle.jsonValue());
  assert.ok(dropped.mesh.every((value,index) => Math.abs(value-dropped.at[index]) < .0001));
  await page.keyboard.press("Tab");
  await wait(() => !CooperStatus.backpackOpen);
  await stageOffscreenControls(page);
  const [x,y,z] = dropped.at;
  await aim([x,y+.05,z]);
  await wait(id => CooperStatus.foodTarget === id,dropped.id);
  await screenshot(item + "-floor");
  await page.keyboard.press("KeyE");
  await wait(({id,item}) => !CooperStatus.provisions[id] &&
    !CooperStatus.provisionScene.some(node => node.id === id) && CooperStatus.survival.bag[item] === 1,{id:dropped.id,item});
  report.pickups.push({item,placement:dropped.at,visibleMesh:dropped.mesh,recovered:true});
}

try {
  await prepareOffscreenPage(page);
  await page.addInitScript(installFrameCapture);
  await page.addInitScript(value => sessionStorage.setItem("cooper-identity", value), identity);
  page.on("pageerror", error => report.errors.push(error.message));
  page.on("console", message => {
    if (/SCRIPT ERROR|Parse Error|SHADER ERROR|Failed loading resource/.test(message.text())) report.errors.push(message.text());
  });
  for (const [id, mine] of Object.entries(manifest.mines)) {
    const nearest = mine.floor.reduce((a, b) => Math.abs(a[0] - mine.gather[2]) < Math.abs(b[0] - mine.gather[2]) ? a : b);
    const [x, y, z] = mineWorldPoint(mine, [0, nearest[1], mine.gather[2]]);
    const target = mineWorldPoint(mine, mine.gather);
    const yaw = Math.atan2(x - target[0], z - target[2]);
    await openRoom(id.replace("_", "-"), {x, y, z, yaw}, {});
    await aim(target);
    await wait(id => CooperStatus.mineTarget === id, id);
    const before = (await read()).mines[id].stock;
    await screenshot(id);
    await page.keyboard.press("KeyF");
    await wait(({id, item, before}) => CooperStatus.survival.bag[item] === 1 &&
      CooperStatus.mines[id].stock === before - 1, {id, item: mine.item, before});
    report.checks.push("F at " + id + " adds one modeled item and reduces the shared seam stock");
    await dropAndRecover(mine.item);
  }

  await openRoom("forge", {x: 5.16, z: -83.85, yaw: 0}, {coal: 2, iron_ore: 2}, 98);
  await aim([4.75,.18,-82.85]);
  await wait(() => CooperStatus.storageTarget === "camp-storage-6");
  await screenshot("campfire-out");
  await page.keyboard.press("KeyE");
  await wait(() => CooperStatus.storagePanel.mode === "fire");
  await clickAction("fuel_coal");
  await wait(() => CooperStatus.survival.bag.coal === 1);
  report.checks.push("the campfire accepts coal through the same E panel as wood");
  await page.keyboard.press("Escape");
  await stageOffscreenControls(page);
  await screenshot("campfire-lit");
  await aim([5.98,.53,-84.55]);
  await wait(() => CooperStatus.storageTarget === "camp-iron-furnace");
  await screenshot("camp-furnace");
  await page.keyboard.press("KeyE");
  await wait(() => CooperStatus.storagePanel.mode === "furnace");
  await clickAction("smelt");
  await wait(() => !CooperStatus.survival.bag.coal && !CooperStatus.survival.bag.iron_ore);
  await screenshot("furnace-batch");
  const pending = (await read()).storagePanel.recipes.take_ingot;
  assert.equal(pending.disabled, true);
  await clickAction("take_ingot");
  await wait(() => CooperStatus.survival.bag.iron_ingot === 1);
  report.checks.push("the furnace spends two ores and one coal, waits and returns one ingot");
  assert.deepEqual(report.errors, []);
  report.ok = true;
} catch (error) {
  report.failure = error.message;
  const state = await read().catch(() => null);
  if (state) report.state = {at: [state.x, state.y, state.z], room: state.room, status: state.status, mineTarget: state.mineTarget,
    storageTarget: state.storageTarget, storagePanel: state.storagePanel, bag: state.survival?.bag, notice: state.notice};
  await screenshot("failure").catch(() => {});
  process.exitCode = 1;
} finally {
  await writeFile(resolve(output, "report.json"), JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify(report));
  await browser.close();
}
