"""Check the shipped silhouettes, plant rims, portal surfaces and clipped spring edges."""
import json
import math
import struct
import sys
from pathlib import Path

import numpy as np
from eastern_contacts import TREES, ROCKS, ROOT_MATS
from eastern_rock_mesh import read_attribute
from eastern_springs import height_at

ROOT = Path(__file__).resolve().parents[1]
EAST = ROOT/'coop/east'

def load_meshes(path):
    raw=path.read_bytes(); size=struct.unpack_from('<I',raw,12)[0]; doc=json.loads(raw[20:20+size]); blob=memoryview(raw)[28+size:]
    meshes={}
    for node in doc['nodes']:
        if 'mesh' not in node: continue
        pieces=[]
        for p in doc['meshes'][node['mesh']]['primitives']:
            pts=read_attribute(doc,blob,p['attributes']['POSITION']); f=read_attribute(doc,blob,p['indices']).reshape(-1,3)
            if 'TEXCOORD_0' in p['attributes']:
                uv=read_attribute(doc,blob,p['attributes']['TEXCOORD_0']); assert np.all(np.isfinite(uv))
            assert np.all(np.isfinite(pts))
            pieces.append(pts[f])
        meshes[node['name']]=np.concatenate(pieces)
    return meshes

def surface(tri,x,z):
    a=tri[:,0]; b=tri[:,1]-a; c=tri[:,2]-a
    det=b[:,0]*c[:,2]-b[:,2]*c[:,0]
    use=abs(det)>1e-8
    dx=x-a[use,0]; dz=z-a[use,2]; b,c,det,a=b[use],c[use],det[use],a[use]
    u=(dx*c[:,2]-dz*c[:,0])/det; v=(b[:,0]*dz-b[:,2]*dx)/det
    ok=(u>=-1e-5)&(v>=-1e-5)&(u+v<=1.00001)
    return np.max((a[:,1]+u*b[:,1]+v*c[:,1])[ok],initial=-np.inf)

def boundary(tri):
    _,_,inverse=np.unique(tri.reshape(-1,3).round(4),axis=0,return_inverse=True,return_index=True)
    f=inverse.reshape(-1,3); edges=np.sort(np.concatenate([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]),axis=1)
    _,c=np.unique(edges,axis=0,return_counts=True)
    return int(sum(c==1))

def check_patch_edges(soil):
    patches={k:v for k,v in soil.items() if k.startswith(('spring_bank_','portal_ground_'))}
    triangles=np.concatenate([soil['ground_patch_joins'],*patches.values()])
    points,ids=np.unique(triangles.reshape(-1,3).round(5),axis=0,return_inverse=True)
    f=ids.reshape(-1,3)
    edges,counts=np.unique(np.sort(np.concatenate([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]),axis=1),axis=0,return_counts=True)
    a,b=points[edges[:,0]],points[edges[:,1]]
    result={}
    for name,tris in patches.items():
        lo,hi=tris.reshape(-1,3).min(0),tris.reshape(-1,3).max(0)
        rim=np.zeros(len(edges),bool)
        for axis,along in [(0,2),(2,0)]:
            on_edge=(a[:,axis]==b[:,axis])&((a[:,axis]==lo[axis])|(a[:,axis]==hi[axis]))
            rim|=on_edge&(np.minimum(a[:,along],b[:,along])>=lo[along])&(np.maximum(a[:,along],b[:,along])<=hi[along])
        count=int(rim.sum())
        assert count==round(8*(hi[0]-lo[0]+hi[2]-lo[2])) and np.all(counts[rim]==2),(name,count)
        result[name]=count
    return result

def ledge_fixture(groups, models, ground):
    # Transform the visible rocks once; a valid test face cannot be inside a
    # neighbouring rock. March along cardinal axes so a diagonal wall slide
    # does not count as moving through it.
    bodies=[]
    for kind in ROCKS:
        for pose in groups[kind]:
            px,py,pz,yaw,scale=pose
            tri=models[kind].copy()*scale
            ox,oz=tri[:,:,0].copy(),tri[:,:,2].copy()
            c,s=math.cos(yaw),math.sin(yaw)
            tri[:,:,0]=px+c*ox+s*oz
            tri[:,:,1]+=py
            tri[:,:,2]=pz-s*ox+c*oz
            bounds=tri.reshape(-1,3)[:,[0,2]]
            bodies.append((kind,pose,tri,bounds.min(axis=0),bounds.max(axis=0)))

    nearby=sorted((body for body in bodies if body[0]=='rock_shelf' and 250<body[1][0]<352 and -100<body[1][2]<-10),
                  key=lambda body:math.hypot(body[1][0]-300,body[1][2]+34))
    for _,pose,tri,lo,hi in nearby:
        px,py,pz,yaw,scale=pose
        neighbors=[(rock,low,high) for _,_,rock,low,high in bodies if rock is not tri
                   and np.all(high>lo-2) and np.all(low<hi+2)]
        def floor_at(p):
            result=float(ground(*p))
            for rock,low,high in neighbors:
                if np.all(p>=low) and np.all(p<=high):result=max(result,surface(rock,*p))
            return result
        c,s=math.cos(yaw),math.sin(yaw)
        for lateral,depth in [(1.6,-2.5),(-1.2,-2.25),(1.,-1.)]:
            target=np.array([px,pz])+scale*np.array([c*lateral+s*depth,-s*lateral+c*depth])
            roof_y=surface(tri,*target)
            if not np.isfinite(roof_y) or roof_y<floor_at(target)+.3:continue
            for axis in (np.array([0.,1.]),np.array([1.,0.])):
                probes=[]
                for side in [-1,1]:
                    for d in np.arange(15*scale,0,-.10):
                        point=target+axis*side*d
                        top=surface(tri,*point)
                        bed=float(ground(*point))
                        if top-bed<1.44 or floor_at(point)>top:continue
                        run=point[None,:]+axis*side*np.linspace(.36,1.28,5)[:,None]
                        floor=max(max(floor_at(q),surface(tri,*q)) for q in run)
                        if top-floor>1.25:
                            probes.append({'start':run[-1].tolist(),'aim':point.tolist(),'top':float(top),'ground':bed})
                            break
                if len(probes)==2:
                    return {'pose':pose,'roof':[target[0],float(roof_y),target[1]],
                            'oldFeet':float(ground(*target)),'approaches':probes}
    raise AssertionError("No exposed ledge with two impassable approaches")


def main():
    report={}; models={}
    for pack in ('verdant','namaqua'):models.update(load_meshes(ROOT/'art/field_regions'/(pack+'.glb')))
    closure={}
    for key in ROCKS:
        for lod in (key,key+'_far'):
            if lod not in models:continue
            tri=models[lod]; closure[lod]={'openEdges':boundary(tri),'volumeM3':round(float(np.einsum('ij,ij->i',tri[:,0],np.cross(tri[:,1],tri[:,2])).sum()/6),2)}
            assert closure[lod]['openEdges']==0 and abs(closure[lod]['volumeM3'])>.05,(lod,closure[lod])
    report['rocks']=closure
    h=np.fromfile(EAST/'elevation.bin','<f4').reshape(208,372); reg=json.loads((EAST/'region.json').read_text())
    springs=json.loads((EAST/'springs.json').read_text()); raw=np.fromfile(EAST/'spring_beds.bin','<f4'); rims=json.loads((EAST/'root_contacts.json').read_text()); groups=json.loads((EAST/'plants.json').read_text())
    def ground(x,z):
        x,z=np.broadcast_arrays(np.asarray(x),np.asarray(z)); y=height_at(h,x,z,reg['origin'])
        for s in springs.values():
            n=s['cells']+1; o=s['origin']; span=s['cells']*s['spacing']; keep=(x>=o[0])&(x<=o[0]+span)&(z>=o[1])&(z<=o[1]+span)
            if np.any(keep): y=np.where(keep,height_at(raw[s['first']:s['first']+n*n].reshape(n,n),x,z,o,s['spacing']),y)
        return y
    soil=load_meshes(EAST/'terrain.glb'); mine_data=json.loads((ROOT/'coop/props/mines/mines_manifest.json').read_text())['mines']; mouths={}
    report['sharedPatchEdges']=check_patch_edges(soil)
    for key in springs:
        mine=next(iter(load_meshes(ROOT/'coop/props/mines'/(key+'.glb')).values())).copy(); cx,cy,cz=reg['camps'][key]['origin'];sign=1 if key=='coal_mine' else -1
        mine[:,:,0]=cx+sign*mine[:,:,0];mine[:,:,1]+=cy;mine[:,:,2]=cz+sign*mine[:,:,2]
        surrounding=soil['portal_ground_'+key]; t=np.concatenate([mine,surrounding]); gap=[]
        for z in np.arange(-3.81,8.94,.23):
            for x in np.arange(-4.94,4.94,.23):
                wx=cx+x;wz=cz+sign*z
                if not math.isfinite(surface(t,wx,wz)):gap.append([wx,wz])
        mouths[key]={'verticalRays':len(np.arange(-3.81,8.94,.23))*len(np.arange(-4.94,4.94,.23)),'uncovered':len(gap)}
        assert not gap,(key,len(gap),gap[:5])
        # The floor on the far side of a gap can satisfy a downward ray. Check the
        # outward-facing earth skin itself and its independently loaded walk height.
        floor=np.asarray(mine_data[key]['floor']); patch=json.loads((EAST/'portal_ground.json').read_text())[key]
        field=np.asarray(patch['heights']).reshape(patch['cells'][1]+1,patch['cells'][0]+1)
        up=np.cross(surrounding[:,1]-surrounding[:,0],surrounding[:,2]-surrounding[:,0])[:,1]>0
        crown=surrounding[up]; probes=0
        for depth in np.arange(.83,8.8,.22):
            center=np.interp(depth,floor[:,0],floor[:,2])
            tread=cy+np.interp(depth,floor[:,0],floor[:,1])
            for offset in np.arange(-.62,.63,.16):
                wx,wz=cx+sign*(center+offset),cz+sign*depth
                top=surface(crown,wx,wz)
                feet=height_at(field,np.array(wx),np.array(wz),patch['origin'],patch['spacing'])
                assert top>tread+2.4 and abs(top-feet)<.001,(key,depth,offset,top,feet)
                probes+=1
        mouths[key]['outerRoofContacts']=probes
    report['portals']=mouths
    contacts={}
    for key in TREES:
        worst=-math.inf; rim=np.asarray(rims[key]); n=0
        for px,py,pz,yaw,scale in groups[key]:
            c,s=math.cos(yaw)*scale,math.sin(yaw)*scale; x=px+c*rim[:,0]+s*rim[:,2];z=pz-s*rim[:,0]+c*rim[:,2]
            delta=py+scale*rim[:,1]-ground(x,z)
            worst=max(worst,float(delta.max()));n+=len(rim)
        contacts[key]={'trees':len(groups[key]),'probes':n,'smallestBurialM':round(-worst,4)};assert worst<=-.027,(key,worst)
    report['treeRims']=contacts
    for k,s in springs.items():
        water=soil['spring_water_'+k]; y=float(s['level']); assert abs(water[:,:,1]-y).max()<2e-5
        points=water.reshape(-1,3); depth=y-ground(points[:,0],points[:,2]);assert depth.min()>-.00002 and .30<depth.max()<.48
        # Every open edge must lie at the independently measured height of the shore.
        rounded,inv=np.unique(points.round(5),axis=0,return_inverse=True); f=inv.reshape(-1,3);edges,c=np.unique(np.sort(np.concatenate([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]),1),axis=0,return_counts=True); shore=rounded[np.unique(edges[c==1])];error=float(np.max(abs(ground(shore[:,0],shore[:,2])-y)));assert error<.0001,(k,error)
        report[k+'Spring']={'shoreVertices':len(shore),'maxShoreErrorM':round(error,6),'depthM':round(float(depth.max()),4)}
    # Pick a ledge with an unjumpable face on both sides. A half-height lip on
    # sloping ground can legally be stepped onto at the top of the jump.
    report['collisionFixture']=ledge_fixture(groups,models,ground)
    target=Path(sys.argv[1]) if len(sys.argv)>1 else None
    if target:target.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False))

if __name__=='__main__':main()
