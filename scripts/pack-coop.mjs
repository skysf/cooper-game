import {readdirSync,readFileSync,writeFileSync,statSync,existsSync} from 'node:fs';
import {join} from 'node:path';
import {gzipSync} from 'node:zlib';

// Precompute once at build time so the first player does not pay the compression cost.
for(const dir of ['dist/coop','dist/coop/zones']){
  for(const name of readdirSync(dir)){
    if(!/\.(wasm|pck|glb|js)$/.test(name))continue;
    const file=join(dir,name);
    if(existsSync(file+'.gz') && statSync(file+'.gz').mtimeMs>=statSync(file).mtimeMs)continue;
    writeFileSync(file+'.gz',gzipSync(readFileSync(file),{level:6}));
  }
}
