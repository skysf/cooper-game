import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const mode = process.argv[2] || 'web';
const coop = mode.startsWith('coop-');
const project = resolve(root, coop ? 'coop' : 'godot');
if (!['web', 'native', 'build-native', 'coop-web', 'coop-native'].includes(mode)) throw Error('Unsupported build target '+mode);
const candidates = [
  process.env.GODOT_BIN,
  '/Applications/Godot.app/Contents/MacOS/Godot',
  resolve(homedir(), 'Downloads/Godot.app/Contents/MacOS/Godot'),
  'godot4', 'godot',
].filter(Boolean);
const engine = candidates.find(binary => {
  const out = spawnSync(binary, ['--headless', '--version'], { encoding: 'utf8' });
  return out.status === 0 && out.stdout.trim().startsWith('4.7.2.stable.');
});
if (!engine) throw Error('未找到 Godot 4.7.2 标准版，可设置 GODOT_BIN 指向可执行文件。');

function run(command, args, capture = false) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: capture ? 'pipe' : 'inherit',
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
  });
  if (capture) {
    process.stdout.write(result.stdout || '');
    process.stderr.write(result.stderr || '');
  }
  if (result.error) throw result.error;
  if (result.status !== 0 || (capture && /SCRIPT ERROR:|Parse Error:|Failed to (load script|export project)/i.test(result.stdout + result.stderr))) {
    throw Error(`Godot 构建失败，退出状态 ${result.status ?? result.signal}。`);
  }
}

const web = mode === 'web' || mode === 'coop-web';
const workspaceOutput = resolve(root, coop ? (web ? 'dist/coop' : 'dist/coop-native') : (web ? 'dist/b' : 'dist/native'));
mkdirSync(workspaceOutput, { recursive: true });
const cache = resolve(root, '.cache');
mkdirSync(cache, { recursive: true });
run('python3', [resolve(root, 'scripts/godot-templates.py'), web ? 'web' : 'mac']);
if (web && !coop) run(process.execPath, [resolve(root, 'scripts/shell.mjs')]);
const args = ['--headless', '--path', project, '--log-file', resolve(cache, 'godot-export.log')];
run(engine, [...args, '--import'], true);
const output = resolve(workspaceOutput, web ? 'index.html' : (coop ? 'CooperCamp.app' : 'Woodland.app'));
run(engine, [...args, '--export-release', web ? 'Web' : 'macOS', output], true);
if (web) {
  for (const name of ['index.html', 'index.js', 'index.wasm', 'index.pck']) {
    if (!existsSync(resolve(workspaceOutput, name))) throw Error(`缺少导出文件 ${name}`);
  }
  if (readFileSync(resolve(workspaceOutput, 'index.wasm')).subarray(0, 4).toString() !== '\0asm') {
    throw Error('输出缺少 WebAssembly 标头');
  }
  console.log('Godot Web release →', output);
} else {
  for (const entry of ['Contents/Info.plist', 'Contents/MacOS', 'Contents/Resources']) {
    if (!existsSync(resolve(output, entry))) throw Error(`缺少 macOS 应用文件 ${entry}`);
  }
  run('codesign', ['--verify', '--strict', output]);
  console.log('Godot macOS release →', output);
  if (mode === 'native') run('open', [output]);
}
