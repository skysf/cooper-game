import fs from 'node:fs';
import {makeGlb} from './glb.mjs';
import {clamp,lerp,random,smooth,trailX} from './scene-math.mjs';
import {woodlandFirWood} from './coop-fir-wood.mjs';

const forCoop=process.argv.includes('--coop');
const cfg=JSON.parse(fs.readFileSync('shared/layout.json','utf8'));
const water=forCoop?JSON.parse(fs.readFileSync('coop/water_layout.json','utf8')):null;
const scene={...cfg,objects:[],obstacles:[]};
const glb=makeGlb(), {material,vert}=glb, rng=random(cfg.seed);
const TAU=Math.PI*2, between=(a,b)=>lerp(a,b,rng()), gray=v=>[v,v,v];
const {cos,sin,abs,pow}=Math;
const length=v=>Math.hypot(...v), norm=v=>v.map(a=>a/(length(v)||1));
const add=(a,b)=>a.map((v,i)=>v+b[i]), sub=(a,b)=>a.map((v,i)=>v-b[i]);
const scale=(a,s)=>a.map(v=>v*s);
const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const at=z=>trailX(cfg.route,z);
const mud=material('mud','trail',{rough:.85}), floor=material('forest_floor','litter');
const bark=material('bark','bark_brown_01'), rock=material('rock','mossy_rock',{rough:.72});
const wood=material('wood','wood_planks'), leaf=material('needles',null,{card:'fir',twoSided:true});
const fern=material('fern',null,{card:'fern',twoSided:true});
const grass=material('sedge',null,{twoSided:true});
const lamp=material('lantern_glass',null,{tint:[1,.65,.24,1],glow:[1,.49,.10]});
const rounded=v=>Math.round(v*1000)/1000;
function lakeDistance(x,z) {
  const dx=(x-water.center[0])/water.radius[0], dz=(z-water.center[1])/water.radius[1];
  const angle=Math.atan2(dz,dx);
  return Math.hypot(dx,dz)/(1+.047*sin(angle*3+.9)+.025*cos(angle*5+.4)+.018*sin(angle*9+.3));
}
function creekDistance(x,z) {
  const {firstZ,spacing,steps}=water.creek, index=(z-firstZ)/spacing;
  if(index<0||index>steps)return Infinity;
  const offset=i=>-11.4+sin(i*.22)*2.1+cos(i*.47)*.38;
  const width=i=>.16+sin(Math.PI*i/steps)*1.13;
  const lo=Math.floor(index),hi=Math.ceil(index),t=index-lo;
  return abs(x-lerp(offset(lo),offset(hi),t))/lerp(width(lo),width(hi),t);
}
function shoreHeight(distance,depth,slope) {
  if(distance>=slope)return 0;
  if(distance<=1)return water.waterY-depth*(1-distance);
  const t=(distance-1)/(slope-1);
  return lerp(water.waterY,0,t*t*(3-2*t));
}
function groundHeight(x,z) {
  if(!water||x> -7||x< -46||z< -70||z> -29)return 0;
  return Math.min(shoreHeight(lakeDistance(x,z),2.35,1.08),shoreHeight(creekDistance(x,z),.33,1.24));
}
function lakeClearing(x,z,bankDistance) {
  return water&&(lakeDistance(x,z)<bankDistance||
    (x>water.dock.west-1.4&&x<water.dock.east+1.3&&abs(z-water.dock.z)<1.72));
}
function meshBookmark(...buffers) {
  return buffers.map(buffer=>[buffer,buffer.p.length,buffer.ix.length]);
}
function discardGeometry(bookmark) {
  for(const [buffer,points,indices] of bookmark){
    buffer.p.length=buffer.n.length=points;
    buffer.uv.length=points/3*2;
    buffer.c.length=points/3*4;
    buffer.ix.length=indices;
  }
}
function solid(type,x,z,r) {scene.obstacles.push({type,x:rounded(x),z:rounded(z),r:rounded(r)});}
function placed(type,x,z,meta={}) {scene.objects.push({type,x:rounded(x),z:rounded(z),...meta});}
function tube(b,a,end,r0,r1,sides=9,shade=1) {
  const axis=norm(sub(end,a)), e1=norm(cross(axis,abs(axis[2])<.86?[0,0,1]:[1,0,0])), e2=cross(e1,axis);
  let start=b.p.length/3;
  for(const [p,r,v] of [[a,r0,0],[end,r1,length(sub(end,a))]]){
    for(let j=0;j<=sides;j++){
      const ang=TAU*j/sides, n=add(scale(e1,cos(ang)),scale(e2,sin(ang)));
      vert(b,add(p,scale(n,r)),n,[j/sides*(Math.max(r0,.16)*TAU),-v*.85],gray(shade));
    }
  }
  for(let j=0;j<sides;j++){
    const i=start+j,k=i+sides+1;b.ix.push(i,k,i+1,i+1,k,k+1);
  }
}
function quad(b,points,uvs,c=gray(1)){
  const n=norm(cross(sub(points[1],points[0]),sub(points[2],points[0])));
  const i=b.p.length/3;
  points.forEach((p,j)=>vert(b,p,n,uvs[j],c));
  b.ix.push(i,i+1,i+2,i,i+2,i+3);
}
function beam(a,b,w,h,shade=.8,mat=wood) {
  const al=norm(sub(b,a)), e1=scale(norm(cross(al,abs(al[1])<.9?[0,1,0]:[0,0,1])),w/2),e2=scale(norm(cross(al,e1)),h/2);
  const ring=p=>[[1,1],[-1,1],[-1,-1],[1,-1]].map(([u,v])=>add(p,add(scale(e1,u),scale(e2,v))));
  const bottom=ring(a),top=ring(b),d=length(sub(a,b));
  for(let j=0;j<4;j++){const k=(j+1)%4;quad(mat,[bottom[j],bottom[k],top[k],top[j]],[[0,0],[w,0],[w,d*.7],[0,d*.7]],gray(shade));}
  quad(mat,top,[[0,0],[1,0],[1,1],[0,1]],gray(shade));
  quad(mat,bottom.reverse(),[[0,0],[1,0],[1,1],[0,1]],gray(shade));
}
function frond(b,base,theta,L,W,dy,dip,shade) {
  const start=b.p.length/3;
  for(let k=0;k<=2;k++){
    const t=k*.5, l=t*L, y=base[1]+t*dy-Math.sin(Math.PI*t)*dip;
    for(const s of [-1,1]) {
      const side=s*W*.5,x=base[0]+cos(theta)*l-sin(theta)*side,z=base[2]+sin(theta)*l+cos(theta)*side;
      vert(b,[x,y+side*.09,z],norm([-.18*cos(theta),1,-.18*sin(theta)]),[(s+1)/2,1-t],gray(shade));
    }
  }
  for(const k of [0,2]){const i=start+k;b.ix.push(i,i+1,i+2,i+2,i+1,i+3);}
}
const {x:sx,z:sz,width:sw,depth:sd}=cfg.shelter;
const trees=[];
function tree(x,z,h,r) {
  const orientation=rng()*TAU, leanX=between(-.5,.5),leanZ=between(-.5,.5);
  const hidden=lakeClearing(x,z,1.018);
  const bookmark=hidden?meshBookmark(leaf):null;
  if(!hidden){
    placed('fir',x,z,{height:rounded(h),radius:rounded(r),yaw:rounded(orientation)});
    solid('tree',x,z,r*1.15); trees.push({x,z,h,r});
  }
  const trunkPoint=t=>[x+leanX*t*t,h*t-.045,z+leanZ*t*t];
  const snags=[], crowns=[];
  if(!forCoop) legacyBole(x,z,h,r,orientation,trunkPoint);
  // Scots-pine understory: exposed trunk, snags and uneven, spreading crowns.
  for(let j=0;j<6;j++){
    const t=between(.14,.48),a=orientation+j*2.39,L=between(.32,1.5);
    const root=trunkPoint(t),dy=between(-.4,.2);
    if(forCoop) snags.push({t,angle:a,reach:L,dy});
    else tube(bark,root,add(root,[cos(a)*L,dy,sin(a)*L]),r*.16,.016,5,.56);
  }
  const skirt=between(.29,.49)+.16*sin(orientation*2), width=h*between(.16,.23)*(1+.22*cos(orientation));
  for(let tier=0;tier<9;tier++){
    const t=lerp(skirt,.987,tier/9), ring=trunkPoint(t), radius=width*pow(1-tier/10,.64);
    for(let j=0;j<7;j++){
      const a=orientation+tier*2.396+j*TAU/7+between(-.27,.27);
      const L=radius*between(.67,1.22), p=add(ring,[0,between(-.32,.32),0]), drop=between(-.23,.13)*L;
      if(tier<5){
        if(forCoop) crowns.push({p,angle:a,reach:L,drop});
        else tube(bark,p,add(p,[cos(a)*L*.64,drop-.13,sin(a)*L*.64]),r*.13,.014,5,.73);
      }
      frond(leaf,p,a,L,L*between(.87,1.2),drop,L*.16,between(.60,.96));
      // Drooping sprays give an eye-level viewer a volumetric crown silhouette.
      for(const s of [-1,1]){
        const base=add(p,[cos(a)*L*.42,drop*.4-.10,sin(a)*L*.42]);
        frond(leaf,base,a+s*.62,L*.57,L*.59,drop*.4-L*.30,L*.08,between(.62,1));
      }
    }
  }
  if(forCoop&&!hidden) woodlandFirWood(bark,vert,{x,z,h,radius:r,orientation,trunk:trunkPoint,snags,crowns});
  if(hidden)discardGeometry(bookmark);
}
function legacyBole(x,z,h,r,orientation,trunkPoint) {
  // Continuous grain through the taper; damp root flutes fade above breast height.
  const bole=bark.p.length/3, sides=14, profile=[[0,1.22],[.028,1.07],[.10,.93],[.38,.74],[.70,.42],[1,.025]];
  for(let k=0;k<profile.length;k++){
    const [t,rad]=profile[k], center=trunkPoint(t);
    for(let j=0;j<=sides;j++){
      const a=TAU*j/sides,flute=(.55+.45*sin(5*a+orientation))**3;
      const radius=r*(rad+.30*flute*Math.exp(-t*29));
      const p=add(center,[cos(a)*radius,0,sin(a)*radius]);
      const radial=norm([cos(a),t<.03?.17:.025,sin(a)]);
      const baseShade=.44+.46*(1-Math.exp(-t*13));
      vert(bark,p,radial,[j/sides*r*TAU,-t*h*.72],gray(baseShade));
      if(j<sides&&k<profile.length-1){const b=bole+k*(sides+1)+j,q=b+sides+1;bark.ix.push(b,q,b+1,b+1,q,q+1);}
    }
  }
  for(let j=0;j<5;j++){
    const a=orientation+j*TAU/5;
    tube(bark,[x,.30,z],[x+cos(a)*r*2.6,-.03,z+sin(a)*r*2.6],r*.52,.025,6,.68);
  }
}
const closeToCabin=(x,z)=>abs(x-sx)<sw/2+1.6&&abs(z-sz)<sd/2+1.5;
for(let z=10;z>=-116;z-=3.5){
  for(const side of [-1,1]){
    const zz=z+between(-1.5,1.5),x=at(zz)+side*between(3.0,7.5);
    if(!closeToCabin(x,zz))tree(x,zz,between(9,16),between(.18,.38));
  }
}
for(let iz=0;iz<27;iz++)for(const side of [-1,1])for(let layer=0;layer<2;layer++){
  const zz=12-iz*5+between(-2,2),x=at(zz)+side*(between(7,13)+layer*8);
  tree(x,zz,between(8,19),between(.16,.38));
}
function stone(x,z,r,h,a) {
  const sectors=17,rings=9,stretch=between(.76,.96),seed=between(0,TAU),start=rock.p.length/3;
  if(lakeClearing(x,z,.98))return;
  for(let j=0;j<=rings;j++)for(let i=0;i<=sectors;i++){
    const theta=i/sectors*TAU, angle=-.33*Math.PI+(j/rings)*.83*Math.PI;
    const noise=.89+.06*sin(theta*3+seed)*cos(angle*.7)+.04*cos(5*theta-angle*4)+.025*sin(2*theta+angle*7);
    const xx=r*noise*cos(theta)*cos(angle), zz=r*noise*sin(theta)*cos(angle)*stretch;
    const yy=h*sin(angle)*(.94+.08*cos(theta*2+seed)*cos(angle));
    const n=norm([cos(theta)*cos(angle)/r,sin(angle)/h,sin(theta)*cos(angle)/(r*stretch)]);
    const rotate=(u,v)=>[cos(a)*u-sin(a)*v,sin(a)*u+cos(a)*v];
    const [dx,dz]=rotate(xx,zz),[nx,nz]=rotate(n[0],n[2]);
    vert(rock,[x+dx,yy,z+dz],[nx,n[1],nz],[i/sectors*2*r,.45-j/rings*1.45*h],gray(.66+.24*clamp(j/rings,0,1)));
    if(i<sectors&&j<rings){const k=start+j*(sectors+1)+i,q=k+sectors+1;rock.ix.push(k,q,k+1,k+1,q,q+1);}
  }
  placed('rock',x,z,{radius:rounded(r),height:rounded(h),yaw:rounded(a)});
  solid('rock',x,z,r*.91);
}
for(const [z,side,r,h] of [[.8,1,1.05,.85],[-6.5,-1,1.25,.96],[-15,1,1.38,.94],[-29,-1,1.67,1.38],[-33,1,1.05,.83],[-59,1,1.4,.99],[-76,-1,1.30,.80]]) {
  stone(at(z)+side*(r+1.32),z,r,h,between(0,TAU));
}
for(let i=0;i<75;i++){
  const z=between(-111,11),r=between(.16,1.30),x=at(z)+(rng()>.5?1:-1)*(between(2.25,12)+r);
  if(!closeToCabin(x,z))stone(x,z,r,r*between(.38,.92),rng()*TAU);
}
// Shared baked ground modulation: contact darkening, broken canopy shadows and wheel ruts.
function illumination(x,z) {
  let light=.92;
  for(const t of trees){
    if(abs(x-t.x)>11||abs(z-t.z)>11)continue;
    const dx=x-t.x,dz=z-t.z,c=dx*dx+dz*dz;
    if(c<3)light-=.18*Math.exp(-c*1.6);
    const s=clamp(-(dx+dz)*.5,0,t.h*.61), q=(dx+s)**2+(dz+s)**2;
    if(q<.14&&s<t.h*.5)light-=.21;
    const d=(dx+t.h*.45)**2+(dz+t.h*.39)**2;
    if(d<8)light-=.30*Math.exp(-d*.3)*(.60+.4*sin(x*6+z*2)*cos(z*4));
  }
  return clamp(light,.40,.98);
}
function edge(z,side){return at(z)+side*(1.65+.20*sin(z*1.14+side)+.12*cos(z*2.64-side)+.19*cos(z*.32));}
function groundStrip(b,side,count,loZ,rows){
  const start=b.p.length/3;
  for(let j=0;j<=rows;j++){
    const z=loZ+j*.5,middle=at(z);
    const lo=side===-2?-51:side===-1?-30:middle+(side===1?4:-4);
    const hi=side===-2?-30:side===1?30:middle+(side===-1?-4:4);
    for(let k=0;k<=count;k++){
      const x=lerp(lo,hi,k/count),local=x-middle+4;
      const light=illumination(x,z), uv=side===0?[local/8,z/8]:[local*.5,z*.5];
      const height=groundHeight(x,z);
      const normal=height===0?[0,1,0]:norm([groundHeight(x-.12,z)-groundHeight(x+.12,z),.24,groundHeight(x,z-.12)-groundHeight(x,z+.12)]);
      vert(b,[x,height,z],normal,uv,gray(light*.88));
      if(j<rows&&k<count){const i=start+j*(count+1)+k,q=i+count+1;b.ix.push(i,q,i+1,i+1,q,q+1);}
    }
  }
}
for(const [b,side,count] of [[floor,-1,32],[mud,0,10],[floor,1,32]])groundStrip(b,side,count,-121,270);
if(water)groundStrip(floor,-2,31,-72,88);
for(let i=0;i<880;i++){
  const z=between(-115,12),side=rng()>.5?1:-1, x=edge(z,side)+side*between(.05,9);
  if(closeToCabin(x,z))continue;
  const hidden=lakeClearing(x,z,.985)||groundHeight(x,z)<-.085;
  const bookmark=hidden?meshBookmark(fern):null;
  const size=between(.22,.95), angle=between(0,TAU);
  for(let j=0;j<8;j++)frond(fern,[x,.08,z],angle+j*.785+between(-.25,.25),size*between(.6,1.23),size*.52,size*.44,-size*.24,between(.57,.98));
  if(hidden)discardGeometry(bookmark);
}
for(let i=0;i<6200;i++){
  const z=between(-112,12),side=rng()>.5?1:-1,x=edge(z,side)+side*between(-.20,5);
  if(closeToCabin(x,z))continue;
  const hidden=lakeClearing(x,z,.975)||groundHeight(x,z)<-.10;
  const H=between(.06,.29),angle=rng()*TAU;
  for(let j=0;j<4;j++){
    const a=angle+j*1.61,dx=cos(a),dz=sin(a),w=between(.008,.020),l=H*between(.42,1.05);
    if(forCoop||hidden)continue;
    const start=grass.p.length/3, n=[0,1,0];
    vert(grass,[x-w*dz,.009,z+w*dx],n,[0,0],[.079,.095,.039]);
    vert(grass,[x+w*dz,.009,z-w*dx],n,[1,0],[.085,.102,.047]);
    vert(grass,[x+dx*l,H,z+dz*l],n,[.5,1],[.18,.22,.085]);
    grass.ix.push(start,start+1,start+2);
  }
}
if(forCoop){
  const grassRng=random(cfg.seed+341), range=(a,b)=>lerp(a,b,grassRng());
  scene.grass=[];
  function densityAt(x,z){
    const ix=Math.floor(x), iz=Math.floor(z), tx=smooth(x-ix), tz=smooth(z-iz);
    function corner(a,b){
      let hash=Math.imul(a,0x1f123bb5)^Math.imul(b,0x05491333)^cfg.seed;
      hash=Math.imul(hash^(hash>>>16),0x045d9f3b);
      return ((hash^(hash>>>16))>>>0)/4294967296;
    }
    return lerp(lerp(corner(ix,iz),corner(ix+1,iz),tx),
                lerp(corner(ix,iz+1),corner(ix+1,iz+1),tx),tz);
  }
  function plant(x,z,meadow=false){
    const y=groundHeight(x,z);
    if(abs(x-at(z))<1.46||y<water.waterY+.012||lakeClearing(x,z,1.018))return;
    if(abs(x-sx)<sw/2+.27&&abs(z-sz)<sd/2+.27)return;
    if(water.boulders.some(rock=>Math.hypot(x-rock.x,z-rock.z)<rock.radius*.92))return;
    const density=densityAt(x*.24,z*.24)*.72+densityAt(x*.71+13,z*.71-5)*.28;
    const coverage=smooth((density-.34)/.34);
    if(grassRng()>=coverage)return;
    const shape=grassRng(), clumpThreshold=1-coverage*(meadow ? .33 : .20);
    const variant=shape<lerp(.46,.14,coverage)?0:shape<clumpThreshold?1:2;
    const width=variant===2?range(1.00,1.65):range(1.30,2.35);
    const height=variant===2?range(.82,1.38):range(1.05,1.86);
    const dry=grassRng()<.14?1:0;
    scene.grass.push([variant, ...[x,y-.006,z,range(0,TAU),width,height,dry,grassRng()].map(rounded)]);
  }
  // Keep the center of the path clear and vary the density across the forest edge.
  for(let i=0;i<7600;i++){
    const z=range(-117,12), side=grassRng()<.5?-1:1;
    plant(edge(z,side)+side*range(.02,5.2),z);
  }
  for(let i=0;i<1900;i++){
    plant(sx+range(-7.5,7.5),sz+range(-5.0,10.0),true);
  }
  for(let i=0;i<1480;i++){
    const angle=range(0,TAU), radius=range(1.015,1.28);
    plant(water.center[0]+water.radius[0]*cos(angle)*radius,
          water.center[1]+water.radius[1]*sin(angle)*radius,true);
  }
}
// Three-sided trail shelter. The open gable faces the approach.
placed('shelter',sx,sz,{width:sw,depth:sd});
const left=sx-sw/2,right=sx+sw/2,back=sz-sd/2,front=sz+sd/2;
for(const x of [left,right])for(const z of [back,front]){
  beam([x,0,z],[x,2.36,z],.20,.22);solid('post',x,z,.14);
}
for(const z of [front,back]){
  beam([left-.24,2.25,z],[right+.24,2.25,z],.15,.19,.68);
  for(const side of [-1,1])beam([sx+side*(sw/2+.40),2.08,z],[sx,3.58,z],.18,.18);
}
for(const side of [-1,1]){
  const x=side===-1?left:right;
  beam([x,2.22,back-.32],[x,2.22,front+.32],.22,.20);
  for(let j=0;j<6;j++)beam([x,j*.18+.12,back],[x,j*.18+.12,front-.65],.14,.154,.62+j*.025);
  for(let d=0;d<sd-.65;d+=.20)solid('wall',x,back+d,.115);
  for(let z=back-.43;z<front+.42;z+=.30)beam([x+side*.40,2.04,z],[sx,3.56,z],.31,.098,between(.43,.68));
}
for(let j=0;j<12;j++)beam([left,.10+j*.178,back],[right,.10+j*.178,back],.13,.16,.63+j*.013);
for(let x=left;x<=right;x+=.20)solid('wall',x,back,.11);
beam([left+.28,.48,back+.64],[right-.28,.48,back+.64],.56,.10,.82);
for(const x of [left+.48,right-.48])beam([x,0,back+.63],[x,.47,back+.63],.13,.31);
for(let x=left+.3;x<right-.18;x+=.23)solid('bench',x,back+.65,.24);
beam([sx+.92,2.47,front-.16],[sx+.92,2.05,front-.16],.025,.025,.4);
beam([sx+.92,1.92,front-.16],[sx+.92,2.08,front-.16],.11,.11,1,lamp);
beam([sx+.92,2.07,front-.16],[sx+.92,2.11,front-.16],.14,.14,.37);

const output=forCoop?'.cache/coop-world-source':'shared';
fs.mkdirSync(output,{recursive:true});
const model=output+'/woodland.glb';
scene.triangles=glb.write(model);
fs.writeFileSync(output+'/scene.json',JSON.stringify(scene));
if(!forCoop){
  for(const path of ['web/public/shared','godot/shared']){
    fs.mkdirSync(path,{recursive:true});
    for(const file of ['scene.json','woodland.glb'])fs.copyFileSync(output+'/'+file,path+'/'+file);
  }
}
console.log((forCoop?'Co-op':'Shared')+' woodland:',scene.objects.length,'placed objects,',scene.triangles,'triangles,',Math.round(fs.statSync(model).size/10485.76)/100,'MiB.');
