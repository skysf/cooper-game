// Both web engines advance exactly one shared simulation step per rendered frame.
(() => {
'use strict';
const $ = id => document.getElementById(id);
const canvas = $('canvas'), params = new URLSearchParams(location.search);
const benchmark = params.has('bench'), view = params.get('view');
const edition = location.pathname.startsWith('/b') ? 'Godot' : 'Babylon';
const clamp = (x,a,b) => Math.min(b,Math.max(a,x));
const mix = (a,b,t) => a+(b-a)*t;
const keys = new Set(), samples = {clear:[], rain:[]};
const state = {x:0,y:1.67,z:5,yaw:0,pitch:-.07,time:0,wet:0};
let scene, preset, activated=false, once=false, completed=false, elapsed=0, prev, start, prior, lastHUD=-1;
let override=null, readyMs, invalid=false, previousPhase, gpu;
const lab = window.Wood = {step, frame, ready, fail, state, report:null};
lab.loaded = fetch('/shared/scene.json').then(r=>{if(!r.ok)throw Error('场景清单 HTTP '+r.status);return r.json()}).then(data=>{
  scene=lab.scene=data;
  preset=scene.weather[params.get('profile')==='storm'?'storm':'base'];
  Object.assign(state,preset);
  route(0);
});
function route(t){
 const points=scene.route;
 function locationAt(s) {
   let i=0;while(i<points.length-2 && s>points[i+1][0])i++;
   const a=points[i],b=points[i+1],u=clamp((s-a[0])/(b[0]-a[0]),0,1);
   return [mix(a[1],b[1],u*u*(3-2*u)),mix(a[2],b[2],u)];
 }
 const here=locationAt(t), ahead=locationAt(Math.min(t+.9,scene.weather.duration)), behind=locationAt(Math.max(0,t-.15));
 state.x=here[0];state.z=here[1];state.y=scene.player.eye;
 state.yaw=Math.atan2(ahead[0]-behind[0],behind[1]-ahead[1]);state.pitch=-.09;
}
function walk(dx,dz){
 const r=scene.player.radius,g=scene.ground;
 const free=(x,z)=>!scene.obstacles.some(o=>(x-o.x)**2+(z-o.z)**2 < (r+o.r)**2);
 const n=Math.max(1,Math.ceil(Math.hypot(dx,dz)/.12));
 for(let k=0;k<n;k++){
   const x=clamp(state.x+dx/n,g.x0+1,g.x0+g.step*(g.columns-1)-1);
   const z=clamp(state.z+dz/n,g.z0+1,g.z0+g.step*(g.rows-1)-1);
   if(free(x,state.z))state.x=x;
   if(free(state.x,z))state.z=z;
 }
 state.y=scene.player.eye;
}
function step(){
 if(!scene)return state;
 const now=performance.now(),dt=prev===undefined?0:(now-prev)/1000; prev=now;
 if(view){route(scene.weather.screenshotAt); elapsed=4;}
 else if(benchmark && once){elapsed=Math.min((now-start)/1000,scene.weather.duration);route(elapsed);}
 else if(activated){
   elapsed+=Math.min(dt,.1);
   const a=Number(keys.has('KeyD'))-Number(keys.has('KeyA')), f=Number(keys.has('KeyW'))-Number(keys.has('KeyS'));
   const distance=scene.player.speed*Math.min(dt,.1)/Math.max(1,Math.hypot(a,f));
   walk((f*Math.sin(state.yaw)+a*Math.cos(state.yaw))*distance,(-f*Math.cos(state.yaw)+a*Math.sin(state.yaw))*distance);
 }
 const rain=view?view==='rain':override===null?elapsed>=scene.weather.switchAt:override;
 state.time=elapsed;
 const target=rain?1:0;
 state.wet=view?target:state.wet+clamp(target-state.wet,-dt/scene.weather.transition,dt/scene.weather.transition);
 const tick=Math.floor(elapsed*4);
 if(tick!==lastHUD||!once){lastHUD=tick;$('condition').textContent=rain?'降雨　/　RAIN':'晴间多云　/　CLEAR';$('progress').textContent=benchmark?'固定路线　'+Math.floor(elapsed)+' / '+scene.weather.duration+' s':activated?(Math.hypot(state.x-scene.shelter.x,state.z-scene.shelter.z)<2.5?'已抵达庇护所':'庇护所　'+Math.round(Math.hypot(state.x-scene.shelter.x,state.z-scene.shelter.z))+' m'):'';}
 return state;
}
function ready(){
 if(once)return;
 const gl=canvas.getContext('webgl2');
 if(!gl){fail('此浏览器无法创建 WebGL 2 上下文');return;}
 const ext=gl.getExtension('WEBGL_debug_renderer_info');
 gpu={renderer:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER),webgl:gl.getParameter(gl.VERSION),width:gl.drawingBufferWidth,height:gl.drawingBufferHeight};
 if(gpu.width!==scene.render.width||gpu.height!==scene.render.height){fail('实际绘图缓冲区为 '+gpu.width+' × '+gpu.height+'，请重新载入');return;}
 readyMs=performance.now();once=true;start=readyMs;prev=start;
 $('enter').disabled=false;$('enter').textContent='进入林地　→';
 $('intro').hidden=benchmark||!!view;
 if(view)$('hud').hidden=true;
 lab.readyMs=readyMs;lab.gpu=gpu;
}
function stats(d){
 if(!d.length)return {frames:0,fps:null,p95Ms:null};
 const sorted=[...d].sort((a,b)=>a-b);
 return {frames:d.length,fps:1000*d.length/d.reduce((a,b)=>a+b,0),p95Ms:sorted[Math.ceil(.95*d.length)-1]};
}
function frame(){
 if(!once||!benchmark||completed)return;
 const now=performance.now(),phase=state.time<scene.weather.switchAt?'clear':'rain';
 if(prior!==undefined)samples[previousPhase].push(now-prior);prior=now;previousPhase=phase;
 if(state.time<scene.weather.duration)return;
 completed=true;
 lab.report={edition,profile:params.get('profile')==='storm'?'storm':'base',readyMs,gpu,userAgent:navigator.userAgent,devicePixelRatio,assets:performance.getEntriesByType('resource').filter(r=>r.name.startsWith(location.origin)).map(r=>({file:new URL(r.name).pathname,transferred:r.transferSize,decoded:r.decodedBodySize})),hiddenDuringTest:invalid||document.hidden,clear:stats(samples.clear),rain:stats(samples.rain),rawFrameMs:samples};
 $('result').hidden=false;
 const r=lab.report;
 $('details').innerHTML='<dl class="stats"><div><dt>首次可操作</dt><dd>'+(r.readyMs/1000).toFixed(2)+' s</dd></div><div><dt>绘图缓冲区</dt><dd>'+gpu.width+' × '+gpu.height+'</dd></div>'+['clear','rain'].map((k,i)=>'<div><dt>'+['晴天','雨天'][i]+'　FPS / P95</dt><dd>'+r[k].fps?.toFixed(1)+' / '+r[k].p95Ms?.toFixed(1)+' ms</dd></div>').join('')+'</dl>'+(r.hiddenDuringTest?'页面曾进入后台，请重测。':'');
}
function fail(err){$('intro').hidden=false;$('copy').textContent=String(err);$('enter').textContent='载入失败';lab.error=String(err);console.error(err);}
$('save').onclick=()=>{const link=document.createElement('a');link.href=URL.createObjectURL(new Blob([JSON.stringify(lab.report,null,2)],{type:'application/json'}));link.download=edition+'-woodland.json';link.click();setTimeout(()=>URL.revokeObjectURL(link.href),1000);};
const enter=()=>{if(once&&!benchmark&&!view){canvas.focus();const p=canvas.requestPointerLock();p?.catch(e=>{$('copy').textContent='鼠标未锁定，请再次点击进入。';});}};
$('enter').onclick=enter;canvas.onclick=enter;
document.addEventListener('pointerlockchange',()=>{activated=document.pointerLockElement===canvas;keys.clear();if(!benchmark&&!view){$('intro').hidden=activated;$('cross').hidden=!activated;if(!activated)$('enter').textContent='继续行走　→';}});
document.addEventListener('mousemove',event=>{if(activated){state.yaw+=event.movementX*scene.player.mouse;state.pitch=clamp(state.pitch-event.movementY*scene.player.mouse,-1.38,1.38);}});
window.addEventListener('keydown',e=>{if(activated){if(e.code==='Escape'){document.exitPointerLock();return;}keys.add(e.code);if(e.code==='KeyR'&&!e.repeat)override=!(override??(elapsed>=scene.weather.switchAt));}});
window.addEventListener('keyup',e=>keys.delete(e.code));window.addEventListener('blur',()=>keys.clear());
document.addEventListener('visibilitychange',()=>{if(document.hidden && once && !completed)invalid=true;});
if(params.get('profile')==='storm')$('test').href='?bench=1&profile=storm';
})();
