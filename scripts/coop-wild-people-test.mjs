import {spawnSync} from 'node:child_process';
import {existsSync} from 'node:fs';
import {mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {homedir, tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const root = fileURLToPath(new URL('..', import.meta.url));
const engine = [process.env.GODOT_BIN, '/Applications/Godot.app/Contents/MacOS/Godot',
  join(homedir(), 'Downloads/Godot.app/Contents/MacOS/Godot'), 'godot4', 'godot'].filter(Boolean).find(bin => {
  const r = spawnSync(bin, ['--headless', '--version'], {encoding: 'utf8'});
  return r.status === 0 && r.stdout.trim().startsWith('4.7.2.stable.');
});
if (!engine) throw Error('Godot 4.7.2 not found; set GODOT_BIN.');
const args = process.argv.slice(2);
const temp = await mkdtemp(join(tmpdir(), 'cooper-wild-people-'));
function run(script, userArgs = []) {
  const r = spawnSync(engine, ['--headless', '--log-file', join(temp, script+'.log'), '--path', join(root, 'coop'),
    '--script', join(root, 'scripts', script+'.gd'), '--', ...userArgs], {encoding: 'utf8', maxBuffer: 16*1024*1024});
  const log = (r.stdout || '') + (r.stderr || '');
  process.stdout.write(log);
  if (r.status !== 0 || /SCRIPT ERROR:|Parse Error:|Failed to load script/.test(log)) throw Error(script+' failed');
  return log;
}
try {
  if (args[0] === 'fixture') {
    if (!args[1]) throw Error('Usage: npm run coop:fixture:wild -- <new-save-directory> [combat|captive|companion|stress]');
    run('coop-wild-people-fixture', [resolve(args[1]), args[2] || 'combat']);
  } else {
    const log = run('test-coop-wild-people', [join(temp, 'rooms')]);
    const marker = log.match(/COOP_WILD_PEOPLE_OK (\{[^\n]+\})/);
    if (!marker) throw Error('Missing lifecycle completion result');
    const navigation = run('test-coop-wild-people-navigation');
    const navigationMarker = navigation.match(/COOP_WILD_NAVIGATION (\[[^\n]+\])/);
    if (!navigationMarker) throw Error('Missing navigation completion result');
    const scene = run('test-coop-wild-people-scene');
    const sceneMarker = scene.match(/COOP_WILD_PEOPLE_SCENE_OK (\{[^\n]+\})/);
    if (!sceneMarker) throw Error('Missing scene completion result');
    const report = {engine: 'Godot 4.7.2', lifecycle: JSON.parse(marker[1]), navigation: JSON.parse(navigationMarker[1]), scene: JSON.parse(sceneMarker[1])};
    if (args[0]) {
      await mkdir(resolve(args[0], '..'), {recursive: true});
      await writeFile(resolve(args[0]), JSON.stringify(report, null, 2)+'\n');
    }
  }
} finally {
  await rm(temp, {recursive: true, force: true});
}
