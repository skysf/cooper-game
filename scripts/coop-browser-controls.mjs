// Shared browser test launch, input and display handling.
import {execFileSync} from 'node:child_process';

export function hardwareForegroundRequested(headlessOverride) {
  if (headlessOverride === '1' || process.env.COOP_HARDWARE_FOREGROUND !== '1') return false;
  if (process.platform !== 'darwin' || process.env.GITHUB_ACTIONS !== 'true' ||
      process.env.RUNNER_ENVIRONMENT !== 'self-hosted') {
    throw Error('Foreground timing requires the dedicated self-hosted macOS GitHub Actions runner');
  }
  return true;
}

export function browserTestOptions({foreground = false, software = false, channel,
  metal = true, position = null} = {}) {
  const headless = !foreground;
  const args = headless ? ['--enable-unsafe-swiftshader'] : windowLaunchArgs(position);
  if (software) args.push('--use-gl=angle', '--use-angle=swiftshader');
  else if (headless && metal && process.platform === 'darwin') args.push('--use-angle=metal');
  return {headless, args, channel: channel || (!software && (process.platform === 'darwin' || foreground) ? 'chrome' : 'chromium')};
}

function installOffscreenInput() {
  let lockedElement = null;
  function setPointerLock(element) {
    if (lockedElement === element) return;
    lockedElement = element;
    queueMicrotask(() => document.dispatchEvent(new Event('pointerlockchange')));
  }
  Object.defineProperty(document, 'pointerLockElement', {get: () => lockedElement});
  Element.prototype.requestPointerLock = async function () { setPointerLock(this); };
  document.exitPointerLock = () => setPointerLock(null);
  window.coopOffscreenPointerLock = setPointerLock;

  // Invite QA uses an in-memory clipboard inside the test page.
  if (navigator.clipboard) {
    let clipboardText = '';
    navigator.clipboard.writeText = async text => { clipboardText = String(text); };
    navigator.clipboard.readText = async () => clipboardText;
  }
}

export async function prepareOffscreenPage(page) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Emulation.setFocusEmulationEnabled', {enabled: true});
  await page.addInitScript(installOffscreenInput);
  return cdp;
}

export function macScreenLocked() {
  if (process.platform !== 'darwin') return false;
  try {
    const registry = execFileSync('/usr/sbin/ioreg', ['-n', 'Root', '-l', '-d1'], {encoding: 'utf8', stdio: 'pipe'});
    return /"CGSSessionScreenIsLocked"\s*=\s*Yes\b/.test(registry);
  } catch {
    return false;
  }
}

export function benchmarkWindowPosition() {
  if (process.env.COOP_BENCH_WINDOW_X === undefined && process.env.COOP_BENCH_WINDOW_Y === undefined) return null;
  const position = {left: Number(process.env.COOP_BENCH_WINDOW_X || 0),
    top: Number(process.env.COOP_BENCH_WINDOW_Y || 0)};
  if (!Object.values(position).every(Number.isInteger)) throw Error('Invalid COOP_BENCH_WINDOW_X/Y');
  return position;
}

const windowSize = {width: 1320, height: 825};

export function windowLaunchArgs(position) {
  const args = [`--window-size=${windowSize.width},${windowSize.height}`];
  if (position) args.push(`--window-position=${position.left},${position.top}`);
  return args;
}

export async function focusWindow(page, position) {
  await page.bringToFront();
  if (!position) return;
  const cdp = await page.context().newCDPSession(page);
  try {
    const {windowId} = await cdp.send('Browser.getWindowForTarget');
    await cdp.send('Browser.setWindowBounds', {windowId, bounds: {...position, ...windowSize}});
  } finally {
    await cdp.detach();
  }
}

export async function clickCanvasPoint(page, point) {
  const bounds = await page.locator('#canvas').boundingBox();
  await page.mouse.click(bounds.x + point[0] * bounds.width, bounds.y + point[1] * bounds.height);
}

export async function stageOffscreenControls(page, timeout = 12000) {
  // The game handles browser keys and room messages with an in-page pointer lock.
  await page.evaluate(() => {
    const canvas = document.getElementById('canvas');
    canvas.focus();
    if (window.coopOffscreenPointerLock) window.coopOffscreenPointerLock(canvas);
    else window.CooperJoin.pointerLocked = true;
  });
  await page.waitForFunction(() => window.CooperStatus?.locked, null, {timeout});
}

export async function enterCamp(page) {
  // The ready snapshot arrives before the HUD's enter button settles into its final rect.
  for (let attempt = 0; attempt < 3; attempt++) {
    await page.bringToFront();
    await page.waitForTimeout(350);
    const point = await page.evaluate(useButton => {
      const [x, y, width, height] = CooperStatus.enterRect;
      return useButton && width > 0 ? [(x + width / 2) / CooperStatus.viewport[0],
        (y + height / 2) / CooperStatus.viewport[1]] : [0.64, 0.45];
    }, attempt === 0);
    if (attempt === 2) {
      // Some browser windows miss the canvas's normal click handler during focus handoff.
      // Request the same browser pointer lock on the next physical pointer gesture.
      await page.evaluate(() => {
        const canvas = document.getElementById('canvas');
        canvas.addEventListener('pointerdown', () => {
          if (!document.pointerLockElement) {
            canvas.focus();
            canvas.requestPointerLock()?.catch(error => { window.coopBenchPointerError = error.message; });
          }
        }, {once: true, capture: true});
      });
    }
    await clickCanvasPoint(page, point);
    const locked = await page.waitForFunction(() => document.pointerLockElement && CooperStatus.locked,
      null, {timeout: 2400}).catch(() => null);
    if (locked) return;
  }
  const detail = await page.evaluate(() => window.coopBenchPointerError || 'no browser detail');
  throw Error('Could not acquire pointer lock in the benchmark scene (' + detail + ')');
}
