// Benchmark-only input isolation and small read-only pose observations.
// Esc remains available to release pointer lock and interrupt the test.
export function installInputObserver(){
 window.coopBenchFixedInput=false;
 window.coopBenchInputTrace=[];
 window.coopBenchPoseTrace=[];
 const held=new Set();
 const record=value=>{window.coopBenchInputTrace.push(value);if(window.coopBenchInputTrace.length>256)window.coopBenchInputTrace.shift();};
 for(const type of ['keydown','keyup'])window.addEventListener(type,event=>{
  const blocked=window.coopBenchFixedInput&&type==='keydown'&&event.code!=='Escape';
  if(type==='keydown')held.add(event.code);else held.delete(event.code);
  record({time:performance.now(),type,code:event.code,trusted:event.isTrusted,blocked});
  if(blocked){event.preventDefault();event.stopImmediatePropagation();}
 },true);
 for(const type of ['pointerdown','mousedown'])window.addEventListener(type,event=>{
  if(!window.coopBenchFixedInput)return;
  record({time:performance.now(),type,button:event.button,trusted:event.isTrusted,blocked:true});
  event.preventDefault();event.stopImmediatePropagation();
 },true);
 let last=0;
 function observe(time){
  if(window.coopBenchFixedInput&&window.coopBenchSampling&&time-last>=250){
   last=time;const s=window.CooperStatus;
   if(s)window.coopBenchPoseTrace.push({time,x:s.x,z:s.z,yaw:s.yaw,pitch:s.pitch,locked:s.locked,held:[...held]});
  }
  requestAnimationFrame(observe);
 }
 requestAnimationFrame(observe);
}
