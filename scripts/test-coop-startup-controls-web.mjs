import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { chromium } from 'playwright';
import { browserTestOptions, clickCanvasPoint, enterCamp, prepareOffscreenPage } from './coop-browser-controls.mjs';

const address = new URL(process.env.COOP_TEST_URL || 'http://127.0.0.1:5684/coop/');
address.searchParams.set('room', 'startup-' + randomBytes(4).toString('hex'));
const foreground = process.env.COOP_TEST_FOREGROUND === '1';
const browser = await chromium.launch(browserTestOptions({ foreground }));
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
if (!foreground) await prepareOffscreenPage(page);
const errors = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {
  if (/SCRIPT ERROR|Parse Error/.test(message.text())) errors.push(message.text());
});
await page.addInitScript(() => {
  const samples = [];
  window.startupProgressSamples = samples;
  const observe = new MutationObserver(() => {
    const bar = document.querySelector('#bar');
    const loader = document.querySelector('#loader');
    if (!bar || !loader) return;
    const sample = {
      percent: bar.position < 0 ? null : 100 * bar.position,
      ready: Boolean(window.CooperStatus?.ready),
      hidden: loader.hidden,
    };
    if (JSON.stringify(sample) !== JSON.stringify(samples.at(-1))) samples.push(sample);
    if (sample.hidden) observe.disconnect();
  });
  observe.observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: ['value', 'hidden'] });
});
let releaseChunk;
const pending = new Promise(resolve => { releaseChunk = resolve; });
await page.route(/\/coop\/zones\/camp\.glb$/, async route => {
  await pending;
  await route.continue();
});

try {
  await page.goto(address.href, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => window.CooperStatus?.connected && !CooperStatus.previewWarming &&
    !CooperStatus.focusReady, null, { timeout: 120000 });
  await page.waitForFunction(() => document.querySelector('#phase').textContent.includes('脚下的林区'));
  assert.deepEqual(await page.evaluate(() => ({
    hidden: document.querySelector('#loader').hidden,
    incomplete: document.querySelector('#bar').position < 1,
    ready: CooperStatus.ready,
  })), { hidden: false, incomplete: true, ready: false });
  releaseChunk();
  await page.waitForFunction(() => window.CooperStatus?.ready && document.querySelector('#loader').hidden);
  const progress = await page.evaluate(() => window.startupProgressSamples);
  assert.ok(progress.length > 1 && progress.every((sample, index) =>
    sample.percent !== null && (!index || sample.percent >= progress[index - 1].percent) &&
    (sample.percent < 100 || sample.ready) && (sample.ready || !sample.hidden)), JSON.stringify(progress));
  assert.deepEqual(progress.at(-1), { percent: 100, ready: true, hidden: true });
  console.log('Startup kept the loader visible below 100% until the starting area was ready');

  const panel = id => page.waitForFunction(id =>
    Boolean(id === 'atlas' ? CooperStatus.atlas.open : CooperStatus[id]) &&
    !CooperStatus.locked && CooperStatus.menuVisible === false && document.pointerLockElement === null,
  id, { timeout: 4500 });
  const resumed = () => page.waitForFunction(() =>
    !CooperStatus.backpackOpen && !CooperStatus.peopleOpen && !CooperStatus.atlas.open &&
    !CooperStatus.storageOpen && CooperStatus.locked && CooperStatus.menuVisible === false &&
    document.pointerLockElement === document.getElementById('canvas'),
  null, { timeout: 4500 });
  const menu = () => page.waitForFunction(() =>
    !CooperStatus.backpackOpen && !CooperStatus.peopleOpen && !CooperStatus.atlas.open &&
    !CooperStatus.storageOpen && !CooperStatus.locked && CooperStatus.menuVisible === true &&
    document.pointerLockElement === null && !document.getElementById('fresh').hidden,
  null, { timeout: 4500 });
  const unlockedInWorld = () => page.waitForFunction(() =>
    !CooperStatus.locked && CooperStatus.menuVisible === false && !CooperStatus.backpackOpen &&
    document.pointerLockElement === null && document.getElementById('fresh').hidden,
  null, { timeout: 4500 });

  await menu();
  await enterCamp(page);
  await page.keyboard.press('Escape');
  // CDP sends the key to the page without invoking Chrome's own unlock shortcut.
  await page.evaluate(() => {
    if (document.pointerLockElement) document.exitPointerLock();
  });
  await unlockedInWorld();
  await clickCanvasPoint(page, [0.5, 0.5]);
  await resumed();
  await page.keyboard.press('Tab');
  await panel('backpackOpen');
  await delay(5500);
  await page.keyboard.press('Escape');
  await resumed();
  await page.keyboard.press('Tab');
  await panel('backpackOpen');
  await page.evaluate(() => {
    const canvas = document.getElementById('canvas');
    canvas.requestPointerLock = () => {
      delete canvas.requestPointerLock;
      return Promise.reject(new DOMException('Test declined pointer lock', 'NotAllowedError'));
    };
  });
  await page.keyboard.press('Escape');
  await unlockedInWorld();
  await clickCanvasPoint(page, [0.5, 0.5]);
  await resumed();
  await page.keyboard.press('Tab');
  await panel('backpackOpen');
  await page.keyboard.press('KeyB');
  await panel('peopleOpen');
  await page.keyboard.press('Escape');
  await resumed();
  for (const [key, id] of [['KeyM', 'atlas'], ['KeyK', 'storageOpen']]) {
    await page.keyboard.press(key);
    await panel(id);
    await page.keyboard.press('Escape');
    await resumed();
  }
  await page.keyboard.press('Tab');
  await panel('backpackOpen');
  await page.keyboard.press('Shift+Escape');
  await menu();
  await enterCamp(page);
  await page.keyboard.press('Shift+Escape');
  await menu();
  await page.keyboard.press('Tab');
  await panel('backpackOpen');
  await page.keyboard.press('Escape');
  await menu();
  assert.deepEqual(errors, []);
  console.log(`Esc and a declined relock kept the world open, and Shift+Esc showed the menu (${foreground ? 'browser' : 'simulated'} pointer lock)`);
} catch (error) {
  console.error(await page.evaluate(() => ({
    phase: document.querySelector('#phase')?.textContent,
    browserLocked: Boolean(document.pointerLockElement),
    focused: document.hasFocus(),
    locked: window.CooperStatus?.locked,
    menuVisible: window.CooperStatus?.menuVisible,
    backpack: window.CooperStatus?.backpackOpen,
    people: window.CooperStatus?.peopleOpen,
    atlas: window.CooperStatus?.atlas.open,
    storage: window.CooperStatus?.storageOpen,
  })).catch(() => null), errors);
  throw error;
} finally {
  releaseChunk();
  await browser.close();
}
