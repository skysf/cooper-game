// Plan a path for test clients. The game still drives ordinary input packets and
// resolves all movement against the authoritative server's collision checks.
export function shipClearance([x,z], ship, feet=0) {
  if(!Number.isFinite(ship?.y) || ship.y > feet+1.67 || ship.y+1.64 < feet)return Infinity;
  const dx=x-ship.x,dz=z-ship.z,cos=Math.cos(ship.yaw),sin=Math.sin(ship.yaw);
  return Math.max(Math.abs(dx*cos-dz*sin)-1.0,Math.abs(dx*sin+dz*cos)-2.28);
}

export function findPath(manifest, start, target, {margin=.37, step=.5, stopDistance=1.6, ship, feet=0}={}) {
  const distance=(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1]);
  function isClear([x,z], clearance) {
    return x>=-28.8 && x<=28.8 && z>=-118.8 && z<=11.8 &&
      shipClearance([x,z],ship,feet)>=clearance &&
      manifest.obstacles.every(o=>Math.hypot(o.x-x,o.z-z)>=o.r+clearance);
  }
  function clearSegment(a,b,clearance=margin) {
    const samples=Math.max(1,Math.ceil(distance(a,b)/.15));
    for(let i=0;i<=samples;i++) {
      const t=i/samples;
      if(!isClear([a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t],clearance))return false;
    }
    return true;
  }
  const toWorld=([x,z])=>[x*step,z*step];
  const key=cell=>cell.join(',');
  const nearest=start.map(coord=>Math.round(coord/step));
  const origins=[];
  for(let dx=-2;dx<=2;dx++) {
    for(let dz=-2;dz<=2;dz++) {
      const cell=[nearest[0]+dx,nearest[1]+dz], point=toWorld(cell);
      if(isClear(point,margin) && clearSegment(start,point,.285))origins.push(cell);
    }
  }
  origins.sort((a,b)=>distance(start,toWorld(a))-distance(start,toWorld(b)));
  if(!origins.length)throw Error('No walkable cell near '+start);
  const origin=origins[0];
  const records=new Map([[key(origin),{cell:origin,parent:null,cost:0}]]);
  const open=new Map([[key(origin),distance(toWorld(origin),target)]]);
  const offsets=[[1,0],[-1,0],[0,1],[0,-1],[1,1],[-1,1],[1,-1],[-1,-1]];
  while(open.size) {
    let current=null, best=Infinity;
    for(const [id,score] of open) {
      if(score<best) { best=score; current=id; }
    }
    open.delete(current);
    const node=records.get(current), point=toWorld(node.cell);
    if(distance(point,target)<stopDistance) {
      const reversed=[];
      for(let n=node;n;n=records.get(n.parent))reversed.push(toWorld(n.cell));
      const chain=[start,...reversed.reverse()], compact=[start];
      for(let i=1;i<chain.length;i++) {
        if(i===chain.length-1 || !clearSegment(compact.at(-1),chain[i+1]))compact.push(chain[i]);
      }
      return compact.slice(1);
    }
    for(const [dx,dz] of offsets) {
      const cell=[node.cell[0]+dx,node.cell[1]+dz], id=key(cell);
      const next=toWorld(cell), cost=node.cost+Math.hypot(dx,dz)*step;
      if((records.get(id)?.cost??Infinity)<=cost || !clearSegment(point,next))continue;
      records.set(id,{cell,parent:current,cost});
      open.set(id,cost+distance(next,target));
    }
  }
  throw Error('No walkable route to '+target);
}
