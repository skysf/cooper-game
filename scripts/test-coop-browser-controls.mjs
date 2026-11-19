import assert from 'node:assert/strict';
import {test} from 'node:test';
import {browserTestOptions, hardwareForegroundRequested} from './coop-browser-controls.mjs';

test('normal test launches are offscreen, including with an old headful override', () => {
  delete process.env.COOP_HARDWARE_FOREGROUND;
  assert.equal(hardwareForegroundRequested('0'), false);
  const options = browserTestOptions();
  assert.equal(options.headless, true);
  assert.ok(options.args.every(argument => !argument.startsWith('--window-')));
  if (process.platform === 'darwin') assert.ok(options.args.includes('--use-angle=metal'));
  assert.ok(browserTestOptions({software: true}).args.includes('--use-angle=swiftshader'));
});

test('foreground timing requires an explicit opt-in on the dedicated runner', () => {
  process.env.COOP_HARDWARE_FOREGROUND = '1';
  delete process.env.GITHUB_ACTIONS;
  delete process.env.RUNNER_ENVIRONMENT;
  assert.throws(() => hardwareForegroundRequested('0'), /dedicated self-hosted/);
  assert.equal(hardwareForegroundRequested('1'), false);

  process.env.GITHUB_ACTIONS = 'true';
  process.env.RUNNER_ENVIRONMENT = 'self-hosted';
  if (process.platform === 'darwin') assert.equal(hardwareForegroundRequested('0'), true);
  else assert.throws(() => hardwareForegroundRequested('0'), /dedicated self-hosted/);
});
