// Measure submitted canvas frames alongside browser animation callbacks.
export function installFrameCapture() {
  const prototype = WebGL2RenderingContext.prototype;
  const drawTarget = new WeakMap();
  let timestamp = null;
  let frames = null;
  let frame = null;
  let gameContext = null;
  // A real click acquires pointer lock. Camera fixtures supply only one identified movement event.
  let stagedMove = null;
  for (const type of ['pointermove', 'mousemove']) {
    window.addEventListener(type, event => {
      if (window.coopBenchPinCamera && event !== stagedMove) event.stopImmediatePropagation();
    }, true);
  }
  window.coopBenchMove = (x, y) => {
    const canvas = document.getElementById('canvas');
    const bounds = canvas.getBoundingClientRect();
    stagedMove = new PointerEvent('pointermove', {
      bubbles: true, pointerType: 'mouse', movementX: Math.round(x * bounds.width / canvas.width),
      movementY: Math.round(y * bounds.height / canvas.height),
      clientX: bounds.x + bounds.width / 2, clientY: bounds.y + bounds.height / 2,
    });
    canvas.dispatchEvent(stagedMove);
    stagedMove = null;
  };
  const nativeAnimationFrame = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = callback => nativeAnimationFrame(time => {
    timestamp = time;
    try { callback(time); }
    finally { timestamp = null; }
  });
  const nativeBindFramebuffer = prototype.bindFramebuffer;
  prototype.bindFramebuffer = function(target, buffer) {
    if (target === this.FRAMEBUFFER || target === this.DRAW_FRAMEBUFFER) drawTarget.set(this, buffer);
    return nativeBindFramebuffer.call(this, target, buffer);
  };
  function record(context, mode, count, copies, blit = false) {
    if (!frames || timestamp === null || context !== gameContext) return;
    if (!frame || frame.time !== timestamp) {
      frame = {time: timestamp, drawCalls: 0, triangles: 0, presented: false};
      frames.push(frame);
    }
    if (!drawTarget.get(context)) frame.presented = true;
    if (blit) return;
    frame.drawCalls++;
    if (mode === context.TRIANGLES) frame.triangles += count * copies / 3;
    if (mode === context.TRIANGLE_STRIP || mode === context.TRIANGLE_FAN) frame.triangles += Math.max(count - 2, 0) * copies;
  }
  // Fixed signatures avoid a temporary argument array on every submitted draw.
  const drawArrays = prototype.drawArrays;
  prototype.drawArrays = function(mode, first, count) {
    if (count > 0) record(this, mode, count, 1);
    return drawArrays.call(this, mode, first, count);
  };
  const drawElements = prototype.drawElements;
  prototype.drawElements = function(mode, count, type, offset) {
    if (count > 0) record(this, mode, count, 1);
    return drawElements.call(this, mode, count, type, offset);
  };
  const drawRangeElements = prototype.drawRangeElements;
  prototype.drawRangeElements = function(mode, start, end, count, type, offset) {
    if (count > 0) record(this, mode, count, 1);
    return drawRangeElements.call(this, mode, start, end, count, type, offset);
  };
  const drawArraysInstanced = prototype.drawArraysInstanced;
  prototype.drawArraysInstanced = function(mode, first, count, instances) {
    if (count > 0 && instances > 0) record(this, mode, count, instances);
    return drawArraysInstanced.call(this, mode, first, count, instances);
  };
  const drawElementsInstanced = prototype.drawElementsInstanced;
  prototype.drawElementsInstanced = function(mode, count, type, offset, instances) {
    if (count > 0 && instances > 0) record(this, mode, count, instances);
    return drawElementsInstanced.call(this, mode, count, type, offset, instances);
  };
  const nativeBlit = prototype.blitFramebuffer;
  prototype.blitFramebuffer = function(sx0, sy0, sx1, sy1, dx0, dy0, dx1, dy1, mask, filter) {
    if (mask & this.COLOR_BUFFER_BIT) record(this, 0, 0, 0, true);
    return nativeBlit.call(this, sx0, sy0, sx1, sy1, dx0, dy0, dx1, dy1, mask, filter);
  };
  window.coopBenchSample = (duration, minimumFrames = 0) => new Promise(done => {
    const visibility = document.visibilityState;
    const raf = [];
    const start = performance.now();
    let hidden = visibility !== 'visible';
    let lostFocus = !document.hasFocus();
    gameContext = document.getElementById('canvas').getContext('webgl2');
    frames = [];
    frame = null;
    window.coopBenchSampling = false;
    window.coopBenchFinish = false;
    function sample(time) {
      raf.push(time);
      window.coopBenchSampling = true;
      hidden ||= document.visibilityState !== 'visible';
      lostFocus ||= !document.hasFocus();
      const frameCountReady = !minimumFrames || frames.filter(entry => entry.presented).length >= minimumFrames;
      const stillSampling = time - start < duration && !window.coopBenchFinish;
      const waitingForFrames = !frameCountReady && time - start < duration + 30000;
      if (stillSampling || waitingForFrames) {
        nativeAnimationFrame(sample);
        return;
      }
      const gl = gameContext;
      const renderer = gl.getExtension('WEBGL_debug_renderer_info');
      const submitted = frames.filter(entry => entry.presented && entry.time >= raf[0] && entry.time <= time);
      frames = null;
      gameContext = null;
      window.coopBenchSampling = false;
      done({
        raf, submitted, hidden, lostFocus, buffer: [gl.drawingBufferWidth, gl.drawingBufferHeight],
        renderer: renderer && gl.getParameter(renderer.UNMASKED_RENDERER_WEBGL),
        vendor: renderer && gl.getParameter(renderer.UNMASKED_VENDOR_WEBGL),
      });
    }
    nativeAnimationFrame(sample);
  });
}

export function intervals(times) {
  const intervalsMs = times.slice(1).map((time, index) => time - times[index]);
  const sorted = [...intervalsMs].sort((a, b) => a - b);
  const durationMs = times.at(-1) - times[0];
  return {
    fps: 1000 * intervalsMs.length / durationMs,
    p95Ms: sorted[Math.ceil(sorted.length * 0.95) - 1],
    p99Ms: sorted[Math.ceil(sorted.length * 0.99) - 1],
    maxMs: sorted.at(-1), durationMs, firstTimestampMs: times[0], lastTimestampMs: times.at(-1), intervalsMs,
  };
}

export async function captureBlankRaf(page) {
  const blank = await page.evaluate(() => new Promise(done => {
    const times = [];
    let foreground = true;
    function sample(time) {
      times.push(time);
      foreground &&= document.visibilityState === 'visible' && document.hasFocus();
      if (time - times[0] < 2500) requestAnimationFrame(sample);
      else done({times, foreground, window: {x: screenX, y: screenY, width: outerWidth, height: outerHeight},
        display: {width: screen.width, height: screen.height, availWidth: screen.availWidth,
          availHeight: screen.availHeight, availLeft: screen.availLeft, availTop: screen.availTop}, scaleFactor: devicePixelRatio});
    }
    requestAnimationFrame(sample);
  }));
  const blankRaf = intervals(blank.times);
  return {blankRaf, foreground: blank.foreground, display: blank.display, window: blank.window,
    scaleFactor: blank.scaleFactor,
    blankRefreshEligible: blank.foreground && blankRaf.fps >= 29.8 && blankRaf.p95Ms <= 35.5};
}
