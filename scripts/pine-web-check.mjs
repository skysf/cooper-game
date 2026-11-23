// Prepare and unpack a repeatable, foreground Chrome A/B against the regular
// local coop server. Pass an immutable copy of the original dist/coop folder.
import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { copyFile, mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises';
import { cpus, totalmem } from 'node:os';
import { resolve } from 'node:path';

const size = [1280, 720];
const target = { id: 'trail-mature', x: 2.18, z: -72.63, height: 6.16 };
const view = { yaw: -.08, pitch: .10, eyeHeight: 1.67 };
const stations = [['near', 3.5], ['middle', 13], ['far', 23]];
const climates = [['clear', 51], ['rain', 121]];
const sampleMs = 8000;
const evidenceDir = resolve('evidence/pine-refinement');
const qaRoot = resolve('dist/coop');
const [action, input] = process.argv.slice(2);

if (action === 'prepare') {
  assert.ok(input, 'Supply a saved, unmodified dist/coop directory.');
  const detailViews = process.argv.includes('--detail-views');
  const clearRoute = process.argv.includes('--clear-route');
  assert.ok(!detailViews || !clearRoute, 'Choose one route.');
  await prepare(input, process.argv.includes('--before-only'), detailViews, clearRoute);
} else if (action === 'extract') {
  assert.ok(input, 'Supply the JSON downloaded from the browser.');
  await extract(input);
} else {
  throw Error('Usage: node scripts/pine-web-check.mjs prepare BASELINE_DIR [--before-only] [--detail-views | --clear-route] | extract REPORT.json');
}

async function prepare(reference, beforeOnly, detailViews, clearRoute) {
  const seed = randomBytes(4).toString('hex');
  const fixture = clearRoute ? 'pine-clear-route-check' : detailViews ? 'pine-detail-check' : 'pine-web-check';
  const output = resolve(qaRoot, fixture);
  const yaw = detailViews || clearRoute ? 53 * Math.PI / 180 : view.yaw;
  const roots = ['roots', 2.2, 'LOD0', -.45, 0];
  const crown = ['lower-crown', 4.2, 'LOD0', .47, 0];
  const route = detailViews ? [roots, ['open-far', 23, 'LOD2', .10, 0]] :
    stations.map(([name, distance], i) => [name, distance, 'LOD' + i, view.pitch, sampleMs]);
  const weatherList = detailViews ? climates.slice(0, 1) : climates;
  const builds = {};
  for (const [label, source] of [['before', reference], ['after', 'dist/coop']]) {
    if (beforeOnly && label === 'after') break;
    const directory = resolve(output, label);
    await mkdir(directory, { recursive: true });
    const sourcePack = resolve(source, 'index.pck');
    builds[label] = {
      pckSha256: createHash('sha256').update(await readFile(sourcePack)).digest('hex'),
      pckBytes: (await stat(sourcePack)).size,
      pckGzipBytes: (await stat(sourcePack + '.gz')).size,
      wasmGzipBytes: (await stat(resolve(source, 'index.wasm.gz'))).size,
    };
    for (const name of await readdir(source)) {
      if (name.startsWith('index.') && name !== 'index.html') {
        await copyFile(resolve(source, name), resolve(directory, name));
      }
    }
    const html = await readFile(resolve(source, 'index.html'), 'utf8');
    assert.ok(html.includes('<script src="index.js">') && html.includes('</body>'));
    const initialize = "<script>sessionStorage.setItem('cooper-identity',new URLSearchParams(location.search).get('identity'))</script>";
    await writeFile(resolve(directory, 'index.html'), html
      .replace('<script src="index.js">', initialize + '<script src="index.js">')
      .replace('</body>', '<script>(' + captureTrial.toString() + ')()</script></body>'));
  }
  if (!beforeOnly) assert.notEqual(builds.before.pckSha256, builds.after.pckSha256, 'Build the latest Web release first.');
  const trials = [];
  const roomDir = resolve(process.env.COOP_SAVE_DIR || '.local-rooms');
  await mkdir(roomDir, { recursive: true });
  for (const [weatherIndex, [weather, elapsed]] of weatherList.entries()) {
    const views = clearRoute && weather === 'clear' ? [...route, roots, crown] : route;
    for (const [stationIndex, [station, distance, detail, pitch, duration]] of views.entries()) {
      const order = (weatherIndex + stationIndex) % 2 ? ['after', 'before'] : ['before', 'after'];
      for (const label of order.filter(label => builds[label])) {
        const room = 'pine-' + seed + '-' + trials.length;
        const identity = randomBytes(16).toString('hex');
        const actor = createHash('sha256').update(room + ':' + identity).digest('hex').slice(0, 16);
        // The input system takes mouse deltas in whole drawing pixels.
        const movementX = Math.round((view.yaw - yaw) / .00215);
        const movementY = Math.round((view.pitch - pitch) / .00215);
        const camera = {
          eyeHeight: view.eyeHeight, yaw: view.yaw - movementX * .00215, pitch: view.pitch - movementY * .00215,
          x: target.x + Math.sin(yaw) * distance, z: target.z + Math.cos(yaw) * distance,
        };
        await writeFile(resolve(roomDir, room + '.json'), JSON.stringify({
          version: 1, elapsed, groveStartedAt: elapsed - 51,
          quest: { wood: false, tarp: false, repaired: false },
          homes: { [actor]: { x: camera.x, z: camera.z, yaw: camera.yaw } },
        }), { flag: 'wx' });
        trials.push({
          label, weather, station, distance, camera, movementX, movementY,
          sampleMs: duration,
          detail: label === 'after' ? detail : null,
          url: label + '/index.html?' + new URLSearchParams({ room, identity }),
        });
      }
    }
  }
  const info = {
    chip: cpus()[0].model, memoryGiB: totalmem() / 2 ** 30, size, target, sampleMs: detailViews ? 0 : sampleMs, builds, detailViews, clearRoute,
    runs: [], date: null,
  };
  const reportName = 'pine-web-' + (clearRoute ? 'clear-route-' : detailViews ? 'detail-' : beforeOnly ? 'before-' : 'ab-') + seed + '.json';
  await writeFile(resolve(output, 'index.html'), `<!doctype html>
<meta charset="utf-8"><title>Cooper 松树 A/B</title>
<style>
  body {margin:0;background:#0c1412;color:#e2e6d4;font:15px system-ui;text-align:center}
  header {min-height:48px;display:flex;gap:18px;align-items:center;justify-content:center}
  iframe {display:block;width:1280px;height:720px;border:0;margin:0 auto}
  button,a {padding:7px 12px;color:#17241d;background:#dae3be;border:0;border-radius:4px}
</style>
<header><button id="start">开始测量</button><span id="status" role="status">保持 Chrome 在前台</span>
<a id="save" hidden>下载截图与帧耗时</a></header>
<main id="stage"></main>
<script>(${runTrials.toString()})(${JSON.stringify(trials)},${JSON.stringify(info)},${JSON.stringify(reportName)})</script>`);
  console.log('http://localhost:' + (process.env.COOP_PORT || '4184') + '/coop/' + fixture + '/index.html');
  console.log('Download name ' + reportName);
}

function runTrials(trials, report, reportName) {
  const start = document.querySelector('#start');
  const status = document.querySelector('#status');
  const save = document.querySelector('#save');
  const stage = document.querySelector('#stage');
  start.addEventListener('click', async () => {
    start.disabled = true;
    report.date = new Date().toISOString();
    try {
      for (const [index, trial] of trials.entries()) {
        status.textContent = (index + 1) + '/' + trials.length + ' ' + trial.label + ' · ' + trial.station + ' · ' + trial.weather;
        const frame = document.createElement('iframe');
        frame.title = 'Cooper · ' + trial.station;
        frame.src = trial.url;
        const captured = await new Promise((done, fail) => {
          function finish(error, data) {
            clearTimeout(timeout);
            window.removeEventListener('message', receive);
            if (error) fail(Error(error));
            else done(data);
          }
          function receive(event) {
            if (event.origin !== location.origin || event.source !== frame.contentWindow) return;
            if (event.data?.pineQA === 'ready') {
              frame.contentWindow.postMessage({ pineQA: 'capture', trial, sampleMs: trial.sampleMs, target: report.target, size: report.size }, location.origin);
            }
            if (event.data?.pineQA === 'result') finish(event.data.error, event.data.data);
          }
          const timeout = setTimeout(() => finish('Trial timed out: ' + trial.label + ' ' + trial.station), 30000);
          window.addEventListener('message', receive);
          stage.replaceChildren(frame);
        });
        const { url, ...settings } = trial;
        report.runs.push({ ...settings, ...captured });
        stage.replaceChildren();
      }
      status.textContent = '完成 ' + report.runs.length + ' 组采样';
    } catch (error) {
      status.textContent = error.message;
      report.error = error.message;
    }
    if (report.runs.length) {
      const blob = new Blob([JSON.stringify(report)], { type: 'application/json' });
      save.href = URL.createObjectURL(blob);
      save.download = reportName;
      save.hidden = false;
    }
  });
}

function captureTrial() {
  const nextFrame = () => new Promise(resolve => requestAnimationFrame(resolve));
  function sceneAt(trial, target, size) {
    const canvas = document.querySelector('canvas');
    const gl = canvas.getContext('webgl2');
    const extension = gl.getExtension('WEBGL_debug_renderer_info');
    const rect = canvas.getBoundingClientRect();
    const state = window.CooperStatus;
    const tree = state.grove.find(t => t.id === target.id);
    const scene = {
      x: state.x, z: state.z, yaw: state.yaw, pitch: state.pitch,
      elapsed: state.elapsed, groveElapsed: state.groveElapsed, rain: state.rain,
      grove: state.grove, resident: state.resident, viewport: state.viewport,
      drawingBuffer: [gl.drawingBufferWidth, gl.drawingBufferHeight], css: [rect.width, rect.height],
      dpr: devicePixelRatio, userAgent: navigator.userAgent,
      renderer: extension ? gl.getParameter(extension.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER),
      foreground: document.visibilityState === 'visible' && parent.document.hasFocus(),
    };
    const ensure = (test, reason) => { if (!test) throw Error(trial.label + ' ' + trial.station + ': ' + reason); };
    ensure(tree.stage === 'mature' && Math.abs(tree.height - target.height) < .002, 'Target not at full height');
    ensure((tree.detail ?? null) === trial.detail, 'Unexpected tree detail ' + tree.detail);
    const moved = ['x', 'z', 'yaw', 'pitch'].filter(key => Math.abs(scene[key] - trial.camera[key]) >= .001);
    ensure(!moved.length, 'Camera moved: ' + moved.map(key => key + '=' + scene[key] + ' (expected ' + trial.camera[key] + ')').join(', '));
    ensure(scene.rain === (trial.weather === 'rain' ? 1 : 0), 'Weather changed');
    ensure(['viewport', 'drawingBuffer', 'css'].every(k => scene[k].every((n, i) => Math.abs(n - size[i]) < .02)), 'Canvas is not 1280×720');
    ensure(/Apple.*M1/.test(scene.renderer), 'Unexpected WebGL renderer: ' + scene.renderer);
    ensure(scene.foreground, 'Chrome lost foreground focus');
    return scene;
  }

  window.addEventListener('message', async event => {
    if (event.origin !== location.origin || event.source !== parent || event.data?.pineQA !== 'capture') return;
    const { trial, sampleMs, target, size } = event.data;
    try {
      const until = performance.now() + 18000;
      while (true) {
        const s = window.CooperStatus;
        if (s?.ready && document.querySelector('#loader').hidden) {
          // Hide the introductory panel exactly as it is in play, while the
          // fixed benchmark camera remains independent of physical mouse input.
          CooperJoin.pointerLocked = true;
          document.querySelector('#fresh').hidden = true;
          if (s.locked && s.groveElapsed >= 54 && s.resident >= 2 &&
              Math.abs(s.x - trial.camera.x) < .001 && Math.abs(s.z - trial.camera.z) < .001) break;
        }
        if (performance.now() > until) throw Error('Fixed camera did not load: ' + JSON.stringify(s));
        await nextFrame();
      }
      const canvas = document.querySelector('canvas');
      if (trial.movementX || trial.movementY) {
        const rect = canvas.getBoundingClientRect();
        const movement = new PointerEvent('pointermove', {
          clientX: rect.left + rect.width / 2, clientY: rect.top + rect.height / 2,
          movementX: trial.movementX, movementY: trial.movementY, pointerType: 'mouse',
        });
        window.dispatchEvent(movement);
        await new Promise(resolve => setTimeout(resolve, 700));
      }
      const scene = sceneAt(trial, target, size);
      // Capture within the browser's paint cycle because WebGL releases its
      // drawing buffer after compositing.
      const png = await new Promise(resolve => requestAnimationFrame(() => resolve(canvas.toDataURL('image/png'))));
      if (png.length < 100000) throw Error('Empty or incomplete WebGL screenshot.');
      if (!sampleMs) {
        parent.postMessage({ pineQA: 'result', data: { scene, png } }, location.origin);
        return;
      }
      await new Promise(resolve => setTimeout(resolve, 400));
      const times = [await nextFrame()];
      while (times.at(-1) - times[0] < sampleMs) times.push(await nextFrame());
      const end = sceneAt(trial, target, size);
      const intervalsMs = times.slice(1).map((time, i) => time - times[i]);
      const sorted = [...intervalsMs].sort((a, b) => a - b);
      const durationMs = times.at(-1) - times[0];
      const frames = {
        count: intervalsMs.length, durationMs, fps: 1000 * intervalsMs.length / durationMs,
        p95Ms: sorted[Math.ceil(.95 * sorted.length) - 1], intervalsMs,
      };
      parent.postMessage({ pineQA: 'result', data: { scene, end, frames, png } }, location.origin);
    } catch (error) {
      parent.postMessage({ pineQA: 'result', error: error.message }, location.origin);
    }
  });
  parent.postMessage({ pineQA: 'ready' }, location.origin);
}

async function extract(file) {
  const report = JSON.parse(await readFile(file, 'utf8'));
  if (report.error) console.error('Partial run: ' + report.error);
  const isComparison = !!report.builds.after;
  const output = report.clearRoute ? resolve(evidenceDir, 'realism') : evidenceDir;
  await mkdir(output, { recursive: true });
  for (const run of report.runs) {
    const png = Buffer.from(run.png.split(',', 2)[1], 'base64');
    assert.deepEqual([png.readUInt32BE(16), png.readUInt32BE(20)], size);
    delete run.png;
    run.screenshot = [run.label, run.station, run.weather].join('-') + '.png';
    await writeFile(resolve(output, run.screenshot), png);
    if (run.frames) console.log(run.label, run.weather, run.station, run.frames.fps.toFixed(2) + ' FPS', run.frames.p95Ms.toFixed(2) + ' ms P95');
    else console.log(run.screenshot, '1280×720');
  }
  const reportFile = report.detailViews ? 'detail-views.json' : isComparison ? 'frame-times.json' : 'baseline-frame-times.json';
  await writeFile(resolve(output, reportFile), JSON.stringify(report, null, 2) + '\n');
  if (report.error) process.exitCode = 1;
}
