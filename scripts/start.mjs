import { createServer } from 'node:http';
import { createReadStream,existsSync,statSync } from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('..',import.meta.url));process.chdir(root);
if(!existsSync('dist/a/index.html')){
  const result=spawnSync('npm',['run','build:a'],{stdio:'inherit'});
  if(result.status!==0)process.exit(result.status??1);
}
if(!['index.html','index.wasm','index.pck','index.js'].every(f=>existsSync('dist/b/'+f))){
  const result=spawnSync('npm',['run','build:b'],{stdio:'inherit'});
  if(result.status!==0)console.error('B 导出失败，A 仍可试玩。');
}
const paths={'/a':'dist/a','/b':'dist/b','/lab':'web/public/lab','/shared':'shared'};
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript','.css':'text/css','.mjs':'text/javascript','.wasm':'application/wasm','.json':'application/json','.glb':'model/gltf-binary','.png':'image/png'};
const server=createServer((req,res)=>{
 let pathname;try{pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname);}catch{res.writeHead(400).end();return;}
 if(pathname==='/'){res.writeHead(302,{Location:'/a/'}).end();return;}
 const key='/'+pathname.split('/')[1];
 if(!paths[key]){res.writeHead(404).end();return;}
 if(pathname===key){res.writeHead(302,{Location:key+'/'}).end();return;}
 const folder=path.resolve(paths[key]),file=path.resolve(folder,'.'+pathname.slice(key.length)+(pathname.endsWith('/')?'index.html':''));
 if(!file.startsWith(folder+path.sep)||!existsSync(file)||!statSync(file).isFile()){res.writeHead(404).end('File unavailable');return;}
 const st=statSync(file),etag='"'+st.size+'-'+Math.trunc(st.mtimeMs)+'"';
 res.setHeader('ETag',etag);res.setHeader('Cache-Control','no-cache');
 if(req.headers['if-none-match']===etag){res.writeHead(304).end();return;}
 res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Content-Length':st.size});
 if(req.method==='HEAD'){res.end();return;}createReadStream(file).pipe(res);
});
const port=Number(process.env.PORT||4173);
const addresses='A http://localhost:'+port+'/a/\nB http://localhost:'+port+'/b/';
server.on('error',async error=>{
 if(error.code==='EADDRINUSE'){
  try{
   const endpoint=await fetch('http://127.0.0.1:'+port+'/a/',{signal:AbortSignal.timeout(1500)});
   if(endpoint.ok && (await endpoint.text()).includes('林径观察站')){console.log('试玩服务已在运行。\n'+addresses);return;}
  }catch{}
 }
 console.error('本地服务启动失败',error.message);process.exitCode=1;
});
server.listen(port,'127.0.0.1',()=>console.log(addresses));
