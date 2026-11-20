import assert from "node:assert/strict";
import {createHash, randomBytes} from "node:crypto";
import {mkdir, readFile, writeFile} from "node:fs/promises";
import {resolve} from "node:path";
import {chromium} from "playwright";
import {browserTestOptions, prepareOffscreenPage, stageOffscreenControls} from "./coop-browser-controls.mjs";
import {installFrameCapture} from "./coop-frame-capture.mjs";

const output = resolve(process.env.COOP_RESCUE_EVIDENCE || ".cache/rescue-web-qa");
const saves = resolve(process.env.COOP_SAVE_DIR || ".local-rooms/recovery-preview");
const address = new URL(process.env.COOP_TEST_URL || "http://127.0.0.1:5284/coop/");
const socketAddress = process.env.COOP_TEST_SOCKET || "ws://127.0.0.1:5285";
const report = {checks: [], errors: []};
const peers = [];
const helperHome = {x: 3.15, y: 0, z: -84.9, yaw: Math.PI / 2};
const fallHome = {x: 1.8, y: 0, z: -84.9, yaw: Math.PI};
const camp = {x: 1.8, z: -84.9};

function identity(room) {
  const token = randomBytes(16).toString("hex");
  return {token, id: createHash("sha256").update(room + ":" + token).digest("hex").slice(0,16)};
}

async function saveFixture(room, homes, survival, elapsed = 40) {
  const fixture = {version: 1, elapsed, homes, survival, quest: {wood: false, tarp: false, repaired: false}};
  await writeFile(resolve(saves, room + ".json"), JSON.stringify(fixture), {flag: "wx"});
}

async function poll(get, timeout = 8000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    const value = get();
    if (value) return value;
    await new Promise(done => setTimeout(done, 30));
  }
  throw Error("Timed out waiting for a room snapshot");
}

async function connect(room, player) {
  const socket = new WebSocket(socketAddress);
  const peer = {socket, snapshot: null};
  peers.push(socket);
  socket.addEventListener("open", () => {
    socket.send(JSON.stringify({t:"join", room, token:player.token}));
  });
  socket.addEventListener("message", event => {
    const message = JSON.parse(event.data);
    if (message.t === "snapshot") peer.snapshot = message;
    if (message.t === "reject") peer.failure = message.text;
  });
  await poll(() => {
    if (peer.failure) throw Error(peer.failure);
    return peer.snapshot?.players[player.id];
  });
  return peer;
}

async function browserRescue() {
  const room = "rescue-" + randomBytes(4).toString("hex");
  const helper = identity(room);
  const injured = identity(room);
  await saveFixture(room, {[helper.id]:helperHome,[injured.id]:fallHome}, {
    [helper.id]:{health:100, bag:{}},
    [injured.id]:{health:0, bag:{coal:2}},
  }, 86);
  const browser = await chromium.launch(browserTestOptions());
  try {
    const page = await browser.newPage({viewport:{width:1280,height:720}});
    await prepareOffscreenPage(page);
    await page.addInitScript(installFrameCapture);
    await page.addInitScript(value => sessionStorage.setItem("cooper-identity",value), helper.token);
    page.on("pageerror", error => report.errors.push(error.message));
    page.on("console", message => {
      if (/SCRIPT ERROR|Parse Error|SHADER ERROR|Failed loading resource/.test(message.text())) report.errors.push(message.text());
    });
    address.searchParams.set("room",room);
    await page.goto(address.href, {waitUntil:"domcontentloaded"});
    await page.waitForFunction(() => window.CooperStatus?.ready, null, {timeout:120000});
    await stageOffscreenControls(page,20000);
    const casualty = await connect(room,injured);
    const initial = casualty.snapshot.players[injured.id];
    assert.equal(initial.health,0);
    assert(initial.downAt >= 40);
    const state = await page.evaluate(() => window.CooperStatus);
    const dx = initial.x-state.x;
    const dz = initial.z-state.z;
    const desiredYaw = Math.atan2(-dx,-dz);
    const desiredPitch = Math.atan2(initial.y+.36-state.y-1.67,Math.hypot(dx,dz));
    const yawOffset = Math.atan2(Math.sin(state.yaw-desiredYaw),Math.cos(state.yaw-desiredYaw))/.00215;
    await page.evaluate(([x,y]) => window.coopBenchMove(x,y),[yawOffset,(state.pitch-desiredPitch)/.00215]);
    await page.waitForFunction(id => window.CooperStatus?.rescueTarget === id &&
      CooperStatus.playerMotion[id]?.clip === "recovery/Knockout" && CooperStatus.playerMotion[id].time >= .88, injured.id);
    await page.screenshot({path:resolve(output,"down-and-rescue-prompt.jpg"),type:"jpeg",quality:91});
    await page.keyboard.press("KeyE");
    const alive = await poll(() => {
      const player = casualty.snapshot.players[injured.id];
      return player.health > 0 ? player : null;
    });
    assert.equal(alive.health,45);
    assert.equal(alive.downAt,-1);
    assert(alive.revivedAt < initial.downAt+15);
    assert.deepEqual([alive.x,alive.y,alive.z],[initial.x,initial.y,initial.z]);
    assert.equal(casualty.snapshot.survival.bag.coal,2);
    await page.waitForFunction(id => CooperStatus.playerMotion[id]?.clip === "recovery/Recover" &&
      CooperStatus.playerMotion[id].time >= .36, injured.id, {timeout:3500});
    await page.screenshot({path:resolve(output,"getting-up.jpg"),type:"jpeg",quality:91});
    const persisted = JSON.parse(await readFile(resolve(saves,room+".json"),"utf8"));
    assert.equal(persisted.survival[injured.id].health,45);
    assert.deepEqual([persisted.homes[injured.id].x,persisted.homes[injured.id].z],[initial.x,initial.z]);
    report.checks.push("Web E rescues the visible fallen teammate at the same position; rise and save confirmed");
    casualty.socket.close();
  } finally {
    await browser.close();
  }
}

async function automaticCases() {
  const soloRoom = "soloreturn-" + randomBytes(4).toString("hex");
  const solo = identity(soloRoom);
  const away = {x: 4,z:-79,yaw:0};
  await saveFixture(soloRoom,{[solo.id]:away},{[solo.id]:{health:0,bag:{coal:3}}});
  const single = await connect(soloRoom,solo);
  const returned = single.snapshot.players[solo.id];
  assert.equal(returned.health,45);
  assert(Math.hypot(returned.x-camp.x,returned.z-camp.z)<.02);
  assert.equal(single.snapshot.survival.bag.coal,3);
  single.socket.close();
  report.checks.push("solo knockout resolves before the first room snapshot");

  const timedRoom = "timedreturn-" + randomBytes(4).toString("hex");
  const helper = identity(timedRoom);
  const injured = identity(timedRoom);
  await saveFixture(timedRoom,{[helper.id]:{x:3.5,z:-83.5,yaw:0},[injured.id]:away},{
    [helper.id]:{health:100},[injured.id]:{health:0},
  });
  await connect(timedRoom,helper);
  const casualty = await connect(timedRoom,injured);
  const initial = casualty.snapshot.players[injured.id];
  assert.equal(initial.health,0);
  const final = await poll(() => casualty.snapshot.players[injured.id].health > 0 && casualty.snapshot,18000);
  const elapsed = final.elapsed-initial.downAt;
  assert(elapsed>=15 && elapsed<15.4);
  assert(Math.hypot(final.players[injured.id].x-camp.x,final.players[injured.id].z-camp.z)<.02);
  report.onlineTimeout = elapsed;
  report.checks.push("without help the player returns to camp at the 15-second room deadline");
}

await mkdir(output,{recursive:true});
try {
  await browserRescue();
  await automaticCases();
  assert.deepEqual(report.errors,[]);
  report.ok = true;
} catch(error) {
  report.failure = String(error.stack || error);
  process.exitCode = 1;
} finally {
  for (const peer of peers) peer.close();
  await writeFile(resolve(output,"report.json"),JSON.stringify(report,null,2)+"\n");
  console.log(JSON.stringify(report,null,2));
}
