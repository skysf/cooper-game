import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { nativeJoinArgs, resolveNativeJoin } from './native-camp-join.mjs';

const join = await resolveNativeJoin(process.argv[2]);
const app = fileURLToPath(new URL('../dist/coop-native/Cooper.app', import.meta.url));
const launch = spawnSync('open', ['-n', app, '--args', '--', ...nativeJoinArgs(join)], { stdio: 'inherit' });
if (launch.error) throw launch.error;
process.exitCode = launch.status ?? 1;
