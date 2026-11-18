// Generate original Y-up tree meshes in metres. Run from the project root.
import { mkdirSync } from 'node:fs';
import { makeGlb } from './glb.mjs';
import { random } from './scene-math.mjs';

const plus = (a,b) => a.map((v,i) => v+b[i]);
const times = (a,k) => a.map(v => v*k);
const between = (a,b,t) => plus(times(a,1-t),times(b,t));
const minus = (a,b) => plus(a,times(b,-1));
const cross = (a,b) => [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const unit = v => times(v,1/Math.hypot(...v));
const up = [0,1,0];
const radial = (a,r,y) => [Math.cos(a)*r,y,Math.sin(a)*r];
const stages = ['sapling','young','mature'];
mkdirSync('coop/trees',{recursive:true});

function build(species,stage) {
  const birch = species === 'birch';
  const height = [.65,2.4,7][stage];
  const rng = random((birch ? 14310 : 7560) + stage);
  const mesh = makeGlb();
  const wood = mesh.material(species+'_bark',null,{
    imageUri: birch ? 'birch_bark.jpg' : '../textures/bark_diff.jpg', rough:.93,
  });
  const leaves = mesh.material(species+'_foliage',null,{
    imageUri: birch ? 'birch_leaves.png' : '../textures/needles.png', cutoff:.36,twoSided:true, rough:.87,
  });
  // Each tube follows a centre line. Include an extra radial vertex for the UV seam.
  function tube(points,radii,sides,tint,repeat=2) {
    let prev;
    points.forEach((p,j) => {
      const tangent = unit(minus(points[Math.min(j+1,points.length-1)],points[Math.max(0,j-1)]));
      const side = unit(cross(tangent,Math.abs(tangent[0])<.88 ? [1,0,0] : [0,0,1]));
      const back = cross(tangent,side);
      const row = [];
      for(let i=0;i<=sides;i++) {
        const a = Math.PI*2*i/sides;
        const n = plus(times(side,Math.cos(a)),times(back,Math.sin(a)));
        row.push(mesh.vert(wood,plus(p,times(n,radii[j])),n,[i/sides,j/(points.length-1)*repeat],tint(j)));
        if(prev && i>0) wood.ix.push(prev[i-1],prev[i],row[i-1], prev[i],row[i],row[i-1]);
      }
      prev=row;
    });
  }
  // Bent sprays follow the actual branch direction. Tilt changes leaf orientation in each crown.
  function spray(start,tip,width,roll,sag,color) {
    const axis=unit(minus(tip,start));
    const lateral=unit(cross(axis,Math.abs(axis[1])<.96 ? up : [1,0,0]));
    const side=plus(times(lateral,Math.cos(roll)),times(cross(axis,lateral),Math.sin(roll)));
    const first=leaves.p.length/3;
    for(let k=0;k<=2;k++) {
      const t=k/2;
      const mid=plus(between(start,tip,t),[0,-sag*4*t*(1-t),0]);
      const tangent=plus(minus(tip,start),[0,-4*sag*(1-2*t),0]);
      const n=unit(cross(side,tangent));
      for(const sign of [-1,1]) mesh.vert(leaves,plus(mid,times(side,width*.5*sign)),n,[(sign+1)/2,1-t],color);
      if(k) {
        const j=first+(k-1)*2;
        leaves.ix.push(j,j+1,j+2, j+1,j+3,j+2);
      }
    }
  }
  const bend = birch ? .047 : .012;
  function trunk(t) {
    return [bend*Math.sin(3*t)*t,t,bend*Math.sin(4*t+.2)*t];
  }
  const rings = Array.from({length:9},(_,i) => i/8);
  const trunkRadius = (birch ? [.011,.015,.022] : [.016,.023,.028])[stage];
  tube(rings.map(trunk),rings.map(t => trunkRadius*(1.018-t)**.83*(t===0?1.34:1)),stage===2?10:7,
    j => birch ? between([.27,.23,.18],stage ? [.95,.94,.9] : [.49,.40,.32],Math.min(1,j/2)) : [.69,.66,.63],5);
  if(birch) {
    const count=[7,13,21][stage];
    for(let j=0;j<count;j++) {
      const t=.24+.74*(j+.16*rng())/count;
      const angle=j*2.39996+.55*rng();
      const length=(.09+.17*Math.sin(Math.PI*(t-.17)/.87))*(.84+.35*rng())*(stage===0?.78:1);
      const origin=trunk(t), knee=plus(origin,radial(angle,length*.58,length*.56));
      const end=plus(knee,radial(angle+.19,length*.43,length*.21));
      const woodTint=stage && j%3!==0 ? [.65,.61,.54] : [.39,.32,.25];
      tube([origin,knee,end],[trunkRadius*.42,trunkRadius*.17,.0008],5,() => woodTint);
      const splits=stage===0 ? 3 : 5;
      for(let k=0;k<splits;k++) {
        const q=.29+.63*k/(splits-1);
        const base=q<.58 ? between(origin,knee,q/.58) : between(knee,end,(q-.58)/.42);
        const a=angle+(k%2?1:-1)*(.3+.73*rng());
        const reach=length*(.28+.19*rng());
        const fork=plus(base,radial(a,reach*.65,reach*(.38+.25*rng())));
        const bud=plus(fork,radial(a+.2,reach*.55,-reach*(.18+.40*rng())));
        tube([base,fork,bud],[.0023,.0013,.0005],3,() => [.35,.29,.20]);
        for(let twig=0;twig<3;twig++) {
          const az=a+(twig-1)*(.6+.22*rng());
          const root=between(fork,bud,.13+twig*.25);
          const span=(stage===0?.13:.135)*(.76+.56*rng());
          const tip=plus(root,radial(az,span*.75,span*(.28-.78*rng())));
          const light=.69+.30*rng();
          spray(root,tip,span*.86,(rng()-.50)*2.4,span*.13,[light*.93,light,light*.81]);
        }
      }
    }
  } else {
    const levels=[6,9,13][stage];
    for(let j=0;j<levels;j++) {
      const t=.13+.83*j/(levels-1);
      const count=[5,7,8][stage]-(t>.78?2:0);
      for(let k=0;k<count;k++) {
        const a=j*2.39996+(k+.21*rng())*Math.PI*2/count;
        const length=(.018+.26*(1-t)**.8)*(.82+.30*rng());
        const base=trunk(t+.016*rng());
        const mid=plus(base,radial(a,length*.6,-length*.24));
        const tip=plus(mid,radial(a+.06,length*.4,length*.16));
        tube([base,mid,tip],[trunkRadius*(.34-.2*t),.0021,.00065],4,() => [.54,.50,.44]);
        const boughWidth=length*.65;
        spray(base,tip,boughWidth,(rng()-.5)*.67,length*.17,[.76,.86,.72]);
        const pairs=stage===0 ? 2 : 3;
        for(let p=0;p<pairs;p++) {
          const q=.22+.49*p/(pairs-1);
          const origin=plus(between(base,tip,q),[0,-length*.12*Math.sin(Math.PI*q),0]);
          for(const sign of [-1,1]) {
            const az=a+sign*(.62+.31*rng());
            const reach=length*(1-q*.69)*(.51+.20*rng());
            const end=plus(origin,radial(az,reach,-reach*(.18+.52*rng())));
            const light=.68+.26*rng();
            spray(origin,end,reach*.64,sign*(.36+.68*rng()),reach*.085,[light*.82,light,light*.84]);
          }
        }
      }
    }
  }
  let low=Infinity,high=-Infinity;
  for(const batch of [wood,leaves]) for(let i=1;i<batch.p.length;i+=3) {
    low=Math.min(low,batch.p[i]); high=Math.max(high,batch.p[i]);
  }
  const scale=height/(high-low);
  for(const batch of [wood,leaves]) for(let i=0;i<batch.p.length;i++) {
    batch.p[i]=(batch.p[i]-(i%3===1?low:0))*scale;
  }
  const path='coop/trees/'+species+'_'+stages[stage]+'.glb';
  console.log(path, mesh.write(path),'triangles');
}
for(const species of ['birch','spruce']) for(let stage=0;stage<3;stage++) build(species,stage);
