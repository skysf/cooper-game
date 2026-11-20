import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';

// Profiling changes execution cost. These observations identify synchronous
// driver stalls and main-thread tasks; they are never scored as FPS evidence.
export function installGLDiagnostics(){
 window.__CooperWildTrace=true;
 const log=window.coopDiag={gl:[],longTasks:[],marks:[],limit:20000,dropped:0};
 const put=(kind,value)=>{if(log[kind].length<log.limit)log[kind].push(value);else log.dropped++;};
 const objects=new WeakMap();let nextId=1;
 const objectId=x=>{if(!x||typeof x!=='object')return x;let id=objects.get(x);if(!id){id=nextId++;objects.set(x,id);}return {id,type:x.constructor?.name};};
 const compact=(value,index)=>{
  if(value===null||value===undefined||typeof value==='number'||typeof value==='boolean')return value;
  if(typeof value==='string')return value.slice(0,64);
  if(ArrayBuffer.isView(value))return {type:value.constructor.name,bytes:value.byteLength};
  if(value instanceof ArrayBuffer)return {type:'ArrayBuffer',bytes:value.byteLength};
  if(value.width!==undefined||value.height!==undefined)return {type:value.constructor?.name,width:value.width,height:value.height};
  return objectId(value);
 };
 const proto=WebGL2RenderingContext.prototype;
 const all=new Set(['compileShader','linkProgram','createProgram','createShader','shaderSource','attachShader']);
 const methods=[...all,'getProgramParameter','getShaderParameter','getProgramInfoLog','getShaderInfoLog','useProgram','texImage2D','texImage3D','texSubImage2D','texSubImage3D','compressedTexImage2D','compressedTexImage3D','bufferData','bufferSubData','drawArrays','drawElements','drawRangeElements','drawArraysInstanced','drawElementsInstanced','blitFramebuffer','flush','finish','readPixels','clientWaitSync','getSyncParameter','getParameter'];
 for(const name of methods){const original=proto[name];if(typeof original!=='function')continue;
  proto[name]=function(...args){const start=performance.now();let result;try{return result=Reflect.apply(original,this,args);}finally{const end=performance.now(),duration=end-start;if(all.has(name)||duration>=.75)put('gl',{name,start,end,duration,args:args.map(compact),source:name==='shaderSource'?args[1]:undefined,result:all.has(name)?objectId(result):undefined,sampling:Boolean(window.coopBenchSampling)});}};
 }
 try{new PerformanceObserver(list=>{for(const entry of list.getEntries())put('longTasks',{start:entry.startTime,duration:entry.duration,name:entry.name,attribution:Array.from(entry.attribution||[],a=>({name:a.name,containerType:a.containerType,containerName:a.containerName,containerSrc:a.containerSrc}))});}).observe({type:'longtask',buffered:true});}catch(e){log.observerError=String(e);}
 window.coopDiagMark=name=>{const time=performance.now();performance.mark(name);put('marks',{name,time,wall:Date.now()});};
}

export async function startDiagnostics(page,out){
 const cdp=await page.context().newCDPSession(page);
 await cdp.send('Profiler.enable');
 await cdp.send('Profiler.setSamplingInterval',{interval:1000});
 const completed=new Promise(resolve=>cdp.once('Tracing.tracingComplete',resolve));
 await cdp.send('Tracing.start',{categories:'devtools.timeline,v8,v8.execute,gpu,blink.user_timing,disabled-by-default-devtools.timeline,disabled-by-default-devtools.timeline.frame',transferMode:'ReturnAsStream'});
 await cdp.send('Profiler.start');
 await page.evaluate(()=>coopDiagMark('wild-diagnostic-start'));
 return async()=>{
  await page.evaluate(()=>coopDiagMark('wild-diagnostic-end'));
  const {profile}=await cdp.send('Profiler.stop');
  await cdp.send('Tracing.end');
  const {stream}=await completed;let trace='';
  for(;;){const r=await cdp.send('IO.read',{handle:stream,size:1024*1024});trace+=r.base64Encoded?Buffer.from(r.data,'base64').toString('utf8'):r.data;if(r.eof)break;}
  await cdp.send('IO.close',{handle:stream});
  const observations=await page.evaluate(()=>({performanceTimeOrigin:performance.timeOrigin,diagnostics:window.coopDiag,cpu:window.__CooperWildCpu,events:window.__CooperWildEvents,availableTraceKeys:Object.keys(window).filter(k=>/wild.*trace|trace.*wild/i.test(k))}));
  await Promise.all([writeFile(resolve(out,'chrome-trace.json'),trace),writeFile(resolve(out,'chrome-cpu-profile.json'),JSON.stringify(profile)),writeFile(resolve(out,'diagnostic-observations.json'),JSON.stringify(observations,null,2))]);
  await cdp.detach();
  return {diagnosticOnly:true,files:['chrome-trace.json','chrome-cpu-profile.json','diagnostic-observations.json'],glCalls:observations.diagnostics.gl.length,longTasks:observations.diagnostics.longTasks.length,dropped:observations.diagnostics.dropped};
 };
}
