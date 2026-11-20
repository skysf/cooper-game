import {createServer} from 'node:http';
import {connect} from 'node:net';
import {spawn,spawnSync} from 'node:child_process';
import {createReadStream,statSync,existsSync,mkdirSync} from 'node:fs';
import {homedir,networkInterfaces} from 'node:os';
import {resolve,extname,sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const root="/Users/sky/Downloads/Sky_Studio_All/SkyStudio_APP_Master/Game/Cooper_Game/";
const site=resolve(root,process.env.COOP_SITE_DIR||'dist/coop');
const lan=process.argv.includes('--lan');
const port=Number(process.env.COOP_PORT||4184), roomPort=Number(process.env.COOP_ROOM_PORT||4185);
const save=resolve(root,process.env.COOP_SAVE_DIR||'.local-rooms');
const gamePath=resolve(root,'coop');
const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript','.wasm':'application/wasm','.pck':'application/octet-stream','.glb':'model/gltf-binary','.png':'image/png'};
const interfaces=Object.entries(networkInterfaces()).sort(([a],[b])=>Number(!/^en[01]$/.test(a))-Number(!/^en[01]$/.test(b)));
const ipv4=interfaces.flatMap(([,entries])=>entries||[]).filter(a=>a.family==='IPv4'&&!a.internal).map(a=>a.address);
const advertised=lan&&ipv4.length?'http://'+ipv4[0]+':'+port:null;
const binaries=[process.env.GODOT_BIN,'/Applications/Godot.app/Contents/MacOS/Godot',resolve(homedir(),'Downloads/Godot.app/Contents/MacOS/Godot'),'godot4','godot'].filter(Boolean);
const godot=binaries.find(bin=>spawnSync(bin,['--headless','--version'],{encoding:'utf8'}).stdout?.trim().startsWith('4.7.2.stable.'));
if(!godot)throw Error('需要 Godot 4.7.2 标准版，请设置 GODOT_BIN。');
if(!existsSync(resolve(site,'index.pck')))throw Error('缺少网页发行包，请先执行 npm run coop:build。');
mkdirSync(save,{recursive:true});
let child,ready=false,closing=false;
const server=createServer((req,res)=>{
  let path;
  try{path=decodeURIComponent(new URL(req.url,'http://localhost').pathname);}catch{res.writeHead(400).end();return;}
  if(path==='/health'){res.writeHead(ready?200:503,{'Content-Type':'application/json','Cache-Control':'no-store'}).end(JSON.stringify({game:'cooper-camp',ready,lan,advertised}));return;}
  if(!['GET','HEAD'].includes(req.method)){res.writeHead(405).end();return;}
  if(path==='/'||path==='/coop'){res.writeHead(302,{Location:'/coop/'+new URL(req.url,'http://localhost').search}).end();return;}
  if(!path.startsWith('/coop/')){res.writeHead(404).end();return;}
  const file=resolve(site,path.slice(6)||'index.html');
  if(!file.startsWith(site+sep)||!mime[extname(file)]){res.writeHead(404).end();return;}
  const gzip=/\bgzip\b/.test(req.headers['accept-encoding']||'') && existsSync(file+'.gz');
  const target=gzip?file+'.gz':file;
  const info=statSync(target,{throwIfNoEntry:false});
  if(!info?.isFile()){res.writeHead(404).end();return;}
  const etag='"'+info.size+'-'+Math.trunc(info.mtimeMs)+'"';
  res.setHeader('ETag',etag);res.setHeader('Vary','Accept-Encoding');
  res.setHeader('Cache-Control','no-cache');
  if(req.headers['if-none-match']===etag){res.writeHead(304).end();return;}
  if(gzip)res.setHeader('Content-Encoding','gzip');
  res.writeHead(200,{'Content-Type':mime[extname(file)],'Content-Length':info.size});
  if(req.method==='HEAD')res.end();else createReadStream(target).on('error',()=>res.destroy()).pipe(res);
});
server.on('upgrade',(req,socket,head)=>{
  if(!ready||req.url!=='/room'||req.headers.upgrade?.toLowerCase()!=='websocket'){socket.destroy();return;}
  if(req.headers.origin){
    try{if(new URL(req.headers.origin).host!==req.headers.host){socket.destroy();return;}}catch{socket.destroy();return;}
  }
  const upstream=connect(roomPort,'127.0.0.1');
  socket.on('error',()=>upstream.destroy());upstream.on('error',()=>socket.destroy());
  socket.on('close',()=>upstream.destroy());upstream.on('close',()=>socket.destroy());
  upstream.on('connect',()=>{
    const headers=['GET /room HTTP/1.1'];
    for(let i=0;i<req.rawHeaders.length;i+=2)headers.push(req.rawHeaders[i]+': '+req.rawHeaders[i+1]);
    upstream.write(headers.join('\r\n')+'\r\n\r\n');
    if(head.length)upstream.write(head);
    socket.pipe(upstream).pipe(socket);
  });
});
function shutdown(code){
  if(closing)return;closing=true;ready=false;process.exitCode=code;
  server.close();server.closeAllConnections();child?.kill('SIGTERM');
}
server.on('error',async err=>{
  if(err.code==='EADDRINUSE'){
    try{const h=await (await fetch('http://127.0.0.1:'+port+'/health')).json();
      if(h.game==='cooper-camp'&&h.ready&&(!lan||h.lan)){console.log('营地已运行 http://localhost:'+port+'/coop/');if(h.advertised)console.log('同网邀请 '+h.advertised+'/coop/?room=pine');return;}
      if(h.game==='cooper-camp'&&lan&&!h.lan)console.error('请先停止本机模式的营地服务，再开启 --lan。');
    }catch{}
  }
  console.error(err.message);shutdown(1);
});
server.listen(port,lan?'0.0.0.0':'127.0.0.1',()=>{
  child=spawn(godot,['--headless','--path',gamePath,'--log-file',resolve(save,'mac-room-server.log'),'--script','res://server.gd','--','--port='+roomPort,'--save='+save],{stdio:['ignore','pipe','inherit']});
  child.stdout.on('data',chunk=>{
    if(!ready&&chunk.toString().includes('ROOM_SERVER_READY')){
      ready=true;console.log('雨线营地 http://localhost:'+port+'/coop/　房间存档 '+save);
      if(advertised)console.log('同网邀请 '+advertised+'/coop/?room=pine');
    }
  });
  child.on('error',err=>{console.error(err.message);shutdown(1);});
  child.on('exit',()=>{if(!closing){console.error('Godot 房间服务已退出。');shutdown(1);}});
});
process.once('SIGINT',()=>shutdown(0));process.once('SIGTERM',()=>shutdown(0));
