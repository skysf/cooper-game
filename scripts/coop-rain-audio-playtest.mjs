// Measure the rendered stereo mix at the audio clock while the player looks around.
import assert from 'node:assert/strict';
import {createHash, randomBytes} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {chromium} from 'playwright';
import {browserTestOptions, enterCamp, prepareOffscreenPage} from './coop-browser-controls.mjs';

const [backend = 'engine', reportPath] = process.argv.slice(2);
assert.ok(['engine', 'lan'].includes(backend) && reportPath, 'Pass engine|lan and an output JSON path');
const base = process.env.COOP_URL || 'http://127.0.0.1:5784/coop/';
const saves = process.env.COOP_QA_SAVE_DIR || '.cache/rain-continuity/rooms';
const room = 'rain-' + randomBytes(6).toString('hex');
const token = randomBytes(16).toString('hex');
const player = createHash('sha256').update(room + ':' + token).digest('hex').slice(0, 16);
await writeFile(join(saves, room + '.json'), JSON.stringify({version: 1, elapsed: 56,
  quest: {wood: false, tarp: false, repaired: false}, homes: {[player]: {x: 2, z: -75, yaw: 0}}}), {flag: 'wx'});

// The meter runs on the browser audio thread, including during a slow graphics frame.
const meterCode = `registerProcessor('rain-meter', class extends AudioWorkletProcessor {
  constructor() { super(); this.frames = 0; this.left = 0; this.right = 0; this.batch = []; }
  process(inputs, outputs) {
    const [left, right = left] = inputs[0];
    for (let i = 0; i < outputs[0][0].length; i++) {
      this.left += (left?.[i] || 0) ** 2; this.right += (right?.[i] || 0) ** 2;
      if (++this.frames < Math.round(sampleRate / 100)) continue;
      this.batch.push([(currentFrame + i) / sampleRate, this.left / this.frames, this.right / this.frames]);
      this.frames = 0; this.left = 0; this.right = 0;
      if (this.batch.length === 10) { this.port.postMessage(this.batch); this.batch = []; }
    }
    return true;
  }
});`;

function installProbe({token, backend}) {
  sessionStorage.setItem('cooper-identity', token);
  let proto = AudioContext.prototype;
  while (!Object.hasOwn(proto, 'audioWorklet')) proto = Object.getPrototypeOf(proto);
  const worklet = Object.getOwnPropertyDescriptor(proto, 'audioWorklet').get;
  if (backend === 'lan') delete proto.audioWorklet;
  const outputs = new Set(), loopingContexts = new Set(), sources = [], rows = [];
  const connect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function(dest, ...args) {
    if (dest === this.context.destination) outputs.add(this);
    return connect.call(this, dest, ...args);
  };
  const start = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function(...args) {
    if (this.loop) {
      loopingContexts.add(this.context);
      sources.push({duration: this.buffer.duration, channels: this.buffer.numberOfChannels, time: this.context.currentTime});
    }
    return start.apply(this, args);
  };
  window.rainProbe = {rows, sources, async attach(code) {
    const running = Array.from(outputs).filter(node => node.context.state === 'running');
    const context = (running.find(node => loopingContexts.has(node.context)) || running[0]).context;
    const url = URL.createObjectURL(new Blob([code], {type: 'text/javascript'}));
    try { await worklet.call(context).addModule(url); } finally { URL.revokeObjectURL(url); }
    const meter = new AudioWorkletNode(context, 'rain-meter', {channelCount: 2, channelCountMode: 'explicit'});
    for (const node of outputs) if (node.context === context) connect.call(node, meter);
    // The meter produces silence; leave the actual game signal path intact.
    connect.call(meter, context.destination);
    meter.port.onmessage = event => rows.push(...event.data);
    this.time = () => context.currentTime;
  }};
}

function stats(rows) {
  assert.ok(rows.length >= 100, 'Captured at least one second of stereo output');
  const db = power => 10 * Math.log10(Math.max(power, 1e-12));
  const sorted = rows.map(([, l, r]) => db((l + r) / 2)).sort((a, b) => a - b);
  const median = sorted[Math.floor(sorted.length / 2)];
  let quiet = 0, longest = 0, imbalanced = 0;
  for (const [, l, r] of rows) {
    quiet = db((l + r) / 2) < median - 12 ? quiet + 10 : 0;
    longest = Math.max(longest, quiet);
    if (Math.abs(db(l) - db(r)) > 9) imbalanced++;
  }
  const round = n => Number(n.toFixed(2));
  return {seconds: round(rows.length / 100), medianDb: round(median), minDb: round(sorted[0]),
    longestDipMs: longest, unevenStereoPct: round(100 * imbalanced / rows.length)};
}

const browser = await chromium.launch(browserTestOptions());
try {
  const page = await browser.newPage({viewport: {width: 1280, height: 720}});
  const errors = [];
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', msg => { if (/SCRIPT ERROR:|Parse Error:/.test(msg.text())) errors.push(msg.text()); });
  await page.addInitScript(installProbe, {token, backend});
  await prepareOffscreenPage(page);
  await page.goto(base + '?room=' + room);
  await page.waitForFunction(() => window.CooperStatus?.ready, null, {timeout: 150000});
  await enterCamp(page);
  await page.waitForFunction(() => CooperStatus.rain > 0.98);
  await page.waitForTimeout(800);
  await page.evaluate(code => rainProbe.attach(code), meterCode);
  const sections = {};
  for (const [name, seconds] of [['still', 2], ['firstPersonTurn', 9], ['thirdPersonTurn', 10]]) {
    if (name === 'thirdPersonTurn') {
      await page.keyboard.press('KeyV');
      await page.waitForFunction(() => !CooperStatus.weaponView.firstPerson);
    }
    sections[name] = await page.evaluate(async ({name, seconds}) => {
      const canvas = document.getElementById('canvas'), start = rainProbe.time();
      let previous = performance.now(), lastYaw = CooperStatus.yaw, turn = 0, longestFrameMs = 0;
      while (rainProbe.time() - start < seconds) {
        await new Promise(requestAnimationFrame);
        const now = performance.now(), s = CooperStatus;
        longestFrameMs = Math.max(longestFrameMs, now - previous);
        if (name !== 'still') {
          canvas.dispatchEvent(new PointerEvent('pointermove', {bubbles: true, pointerType: 'mouse',
            movementX: Math.round(Math.min(now - previous, 60) * 1.4)}));
          turn += Math.atan2(Math.sin(s.yaw - lastYaw), Math.cos(s.yaw - lastYaw));
        }
        previous = now; lastYaw = s.yaw;
      }
      return {start, end: rainProbe.time(), rain: CooperStatus.rain, turns: Math.abs(turn / (2 * Math.PI)),
        longestAnimationFrameMs: Math.round(longestFrameMs)};
    }, {name, seconds});
  }
  await page.waitForTimeout(200);
  const data = await page.evaluate(() => ({rows: rainProbe.rows, loops: rainProbe.sources}));
  for (const part of Object.values(sections)) {
    Object.assign(part, stats(data.rows.filter(([t]) => t >= part.start && t < part.end)));
  }
  const report = {backend, sections, loops: data.loops, errors};
  await writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report));
  assert.deepEqual(errors, []);
  assert.equal(data.loops.filter(loop => loop.channels === 2 && loop.duration > 6).length, 1,
    'One stereo rain buffer runs across the entire turn and both camera modes');
  for (const [name, part] of Object.entries(sections)) {
    assert.ok(part.rain > 0.7 && part.medianDb > -57, name + ' has steady audible rain');
    assert.ok(name === 'still' || part.turns > 1.5, name + ' turns the in-game camera');
    assert.ok(part.longestDipMs < 20 && part.unevenStereoPct < 2, name + ' keeps a continuous stereo bed');
    assert.ok(Math.abs(part.medianDb - sections.still.medianDb) < 3, name + ' keeps the outdoor rain level');
  }
} finally { await browser.close(); }
