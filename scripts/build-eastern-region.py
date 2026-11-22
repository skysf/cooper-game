"""Bake matching terrain, walk heights and clustered plant placements for the east."""
import json
import math
import random
import runpy
from pathlib import Path

import numpy as np

from eastern_contacts import build_contacts, ROCKS, TREES
from eastern_springs import height_at, radius as spring_radius, water_mesh
from eastern_horizon import bake_horizon
import eastern_photo_landscapes as photo

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "coop/east"
REGION = json.loads((OUT/"region.json").read_text())
CATALOG = json.loads((OUT/"model_catalog.json").read_text())
Chunk = runpy.run_path(str(ROOT/"scripts/coop-zones.py"))["Chunk"]


def ease(v):
    u = np.clip(v,0,1)
    return u*u*(3-2*u)


def distance(x,z,segments):
    d = np.full(np.broadcast(x,z).shape,np.inf)
    for path in segments:
        for (ax,az),(bx,bz) in zip(path,path[1:]):
            dx,dz = bx-ax,bz-az
            t = np.clip(((x-ax)*dx+(z-az)*dz)/(dx*dx+dz*dz),0,1)
            d = np.minimum(d,np.hypot(x-ax-dx*t,z-az-dz*t))
    return d


def ground_material_weights(x, z):
    dry = ease((x - 110 + 8 * np.sin(z * .065)) / 57)
    dry *= 1 - .90 * photo.wooded_cover(x,z)
    path = 1 - ease((distance(x, z, REGION["trails"]) - 1.0) / 1.5)
    return dry, path


def bake_footing():
    ox, oz = REGION["origin"]
    nx, nz = REGION["cells"]
    x, z = np.meshgrid(ox + np.arange(nx) + .5, oz + np.arange(nz) + .5)
    dry, path = ground_material_weights(x, z)
    # The verge shader blends the eastern materials into the original forest.
    blend = ease((x + (3*np.sin(z*.24) + 2.4*np.sin(z*.63+.4))*ease((x-30)/10) - 30.25) / 23.75)
    np.uint8(np.maximum(dry, path) * blend >= .5).tofile(OUT / "soil_footing.bin")


def natural_ground(x,z):
    h = 3.7+2.35*np.sin(x*.044+z*.026)+1.55*np.cos(z*.086-x*.017)
    for cx,cz,rx,rz,amplitude in [(60,-113,23,14,8),(108,-11,17,33,11),(146,-116,31,19,15),
            (194,-10,37,23,10),(234,-92,23,24,12),(275,-104,36,18,17),(326,-64,24,21,14),
            (355,9,36,17,18),(368,-138,45,31,28)]:
        h += amplitude*np.exp(-((x-cx)/rx)**2-((z-cz)/rz)**2)
    h += (.38*np.sin(x*.24+np.sin(z*.13))+.23*np.sin(z*.37+x*.11))*ease((x-32)/12)
    h += photo.relief(x,z)
    for camp in REGION["camps"].values():
        cx,y,cz=camp["origin"]
        sign=1 if camp["yaw"]==0 else -1
        u,v=(x-cx)*sign,(z-cz)*sign
        blend=(1-ease((np.abs(u)-3)/13))*(1-ease((np.abs(v-10)-15)/12))
        hill=y+.034*np.minimum(v,0)+5.1*ease(v/8.5)+1.45*ease((v-8)/20)+.55*ease(np.abs(u)/5)
        h=h*(1-blend)+hill*blend
    return h*ease((x-30)/17)


def spring_level(camp):
    x,z=camp["water"]
    angles=np.linspace(0,2*np.pi,48,endpoint=False)
    banks=natural_ground(x+3*np.cos(angles),z+2.25*np.sin(angles))
    # Use the low side of the existing site so a spring cuts into the hillside.
    return float(min(natural_ground(x,z)-.26,np.quantile(banks,.18)-.14))


SPRING_LEVELS={key:spring_level(camp) for key,camp in REGION["camps"].items()}


def ground(x,z):
    h=natural_ground(x,z)
    for key,camp in REGION["camps"].items():
        r=spring_radius(x,z,camp)
        level=SPRING_LEVELS[key]
        bed=level-.40+.69*ease((r-.08)/1.20)
        bank=ease((r-1.20)/.84)
        h=bed*(1-bank)+h*bank
    return h


def stitch_ground_edges(mesh, data, triangles, keep, patches, origin):
    """Give both sides of each fine/coarse join the same ordered edge vertices."""
    ox,oz = origin
    nz,nx = keep.shape
    edge_points, cells = {}, set()
    for patch in patches:
        for side in [patch[0],patch[-1],patch[:,0],patch[:,-1]]:
            per_metre = round(1./np.linalg.norm((side[1]-side[0])[[0,2]]))
            for k in range(0,len(side)-1,per_metre):
                span = side[k:k+per_metre+1]
                a,b = span[0],span[-1]
                ia = round(a[2]-oz)*(nx+1)+round(a[0]-ox)
                ib = round(b[2]-oz)*(nx+1)+round(b[0]-ox)
                edge_points[ia,ib] = span[1:-1]
                edge_points[ib,ia] = span[-2:0:-1]
                i,j = round(min(a[0],b[0])-ox),round(min(a[2],b[2])-oz)
                cells.update([(j,i),(j-1,i) if a[2]==b[2] else (j,i-1)])

    attrs = {key:[] for key in data}
    faces = []
    def vertex(indices, weights, position=None):
        for name,field in data.items():
            attrs[name].append(position if name=='POSITION' and position is not None else weights @ field[indices])
        return len(attrs['POSITION'])-1

    corners = np.eye(3)
    for j,i in sorted(cells):
        if not (0<=j<nz and 0<=i<nx and keep[j,i]):
            continue
        keep[j,i] = False
        for tri in triangles[j,i]:
            ring = []
            for a in range(3):
                b = (a+1)%3
                ring.append(vertex(tri,corners[a]))
                points = edge_points.get((tri[a],tri[b]),())
                for n,point in enumerate(points):
                    t = (n+1)/(len(points)+1)
                    ring.append(vertex(tri,(1-t)*corners[a]+t*corners[b],point))
            if len(ring)==3:
                faces.append(ring)
            else:
                mid = vertex(tri,np.full(3,1./3))
                faces.extend((mid,v,ring[(n+1)%len(ring)]) for n,v in enumerate(ring))
    attrs = {key:np.asarray(values,dtype=data[key].dtype) for key,values in attrs.items()}
    attrs['NORMAL'] /= np.linalg.norm(attrs['NORMAL'],axis=1)[:,None]
    mesh.mesh('ground_patch_joins',attrs,np.asarray(faces))


def bake():
    bake_footing()
    ox,oz=REGION["origin"]
    nx,nz=REGION["cells"]
    x,z=np.meshgrid(np.arange(nx+1)+ox,np.arange(nz+1)+oz)
    h=ground(x,z)
    h.astype("<f4").tofile(OUT/"elevation.bin")
    dz_grid,dx_grid=np.gradient(h)
    dz,dx=dz_grid,dx_grid
    world=json.loads((ROOT/"coop/world.json").read_text())
    mesh=Chunk()
    mesh.doc["asset"]["generator"]="Rainline eastern terrain"

    def terrain_data(x,z,h,step,moisture,threshold=0.0):
        dz,dx=np.gradient(h,step)
        norm=np.stack([-dx,np.ones_like(h),-dz],axis=-1)
        norm/=np.linalg.norm(norm,axis=2)[:,:,None]
        dry,path=ground_material_weights(x,z)
        stone=ease((np.hypot(dx,dz)-.18)/.8)*dry
        colors=np.stack([dry,path,stone,moisture],axis=-1)
        # Keep the original forest-floor UV phase right through the last streamed column.
        route=world["route"]
        middle=np.full_like(h,route[0][1])
        for (_,ax,az),(_,bx,bz) in zip(route,route[1:]):
            middle=np.where(z<=az,ax+(bx-ax)*ease((z-az)/(bz-az)),middle)
        data={"POSITION":np.stack([x,h,z],axis=-1).astype("f4").reshape(-1,3),
              "NORMAL":norm.astype("f4").reshape(-1,3),"COLOR_0":np.uint8(colors.reshape(-1,4)*255),
              "TEXCOORD_0":(np.stack([x,z],axis=-1)/3.4).astype("f4").reshape(-1,2),
              "TEXCOORD_1":(np.stack([(x-middle+4)*.5,np.broadcast_to(threshold,h.shape)],axis=-1)).astype("f4").reshape(-1,2)}
        ids=np.arange(h.size).reshape(h.shape)
        a,b,c,e=ids[:-1,:-1],ids[:-1,1:],ids[1:,:-1],ids[1:,1:]
        return data,np.stack((a,c,b,b,c,e),axis=-1).reshape(*a.shape,2,3)

    data,tris=terrain_data(x,z,h,1,np.zeros_like(h))
    ok=np.ones((nz,nx),bool)
    ok[:,0]=False  # The production camp floor ends exactly at x=30.
    # Bake a quarter-metre surround up to the actual curving gallery walls. The centre stays
    # open until the existing hillside is safely above the roof; both jambs overlap solid rock.
    mine_rows = json.loads((ROOT/'coop/props/mines/mines_manifest.json').read_text())['mines']
    springs={}
    portal_surfaces={}
    patch_edges=[]
    fine_fields=[]
    wet_cells=[]
    for key,camp in REGION['camps'].items():
        cx,_,cz=camp['origin']
        v=(z[:-1,:-1]+.5-cz)*(1 if camp['yaw']==0 else -1)
        sign=1 if camp['yaw']==0 else -1
        ok &= ~((np.abs(x[:-1,:-1]+.5-cx)<5)&(v>=-4)&(v<9))
        px,pz=np.meshgrid(np.arange(cx-5,cx+5.01,.25),np.arange(min(cz-4*sign,cz+9*sign),max(cz-4*sign,cz+9*sign)+.01,.25))
        depths=(pz-cz)*sign; side=(px-cx)*sign
        floor=np.array(mine_rows[key]['floor'])
        lane=np.interp(depths,floor[:,0],floor[:,2]); width=np.interp(depths,floor[:,0],floor[:,3]); floor_y=np.interp(depths,floor[:,0],floor[:,1])+camp['origin'][1]
        ground_y=height_at(h,px,pz,(ox,oz))
        # Outside the rock lip the ground itself becomes the gravel tread; its inner edge
        # sits just below the Blender floor. This continues under the jambs from either side.
        shoulder=(1-ease((abs(side-lane)-width+.08)/.68))*ease((depths+3.5)/1.0)*(1-ease(depths/.60))
        portal_y=ground_y*(1-shoulder)+np.minimum(ground_y,floor_y-.065)*shoulder
        # The approach is open in front of the arch. Behind the first timber the
        # surface wraps over the gallery crown, then rejoins the natural slope.
        crown=1+.053*np.sin(np.maximum(depths,0)*.76+(0 if key=='coal_mine' else .73))
        cross=abs(side-lane)/width
        arch=np.interp(cross,[0,.34,.66,.89,1.,1.22,1.70],[2.79,2.68,2.34,1.69,.78,.18,-.65])
        cover=(1-ease((cross-1.12)/.58))*ease((depths-.20)/.55)
        portal_y+=cover*np.maximum(0,floor_y+arch*crown+.23-portal_y)
        approach=ease((depths+3.4)/2.1)*(1-ease((abs(side-lane)-width+.18)/.72))*(1-ease((depths-2.8)/2.4))
        approach*=1-ease((depths-.15)/.6)
        data_portal,faces_portal=terrain_data(px,pz,portal_y,.25,np.zeros_like(px),approach)
        wall_depth=depths[:-1,:-1]+sign*.125
        wall_side=side[:-1,:-1]+sign*.125
        lane=np.interp(wall_depth,floor[:,0],floor[:,2]); width=np.interp(wall_depth,floor[:,0],floor[:,3]);
        bore=(wall_depth>=.12)&(wall_depth<.75)&(abs(wall_side-lane)<width+.12)
        mesh.mesh('portal_ground_'+key,data_portal,faces_portal[~bore].reshape(-1,3))
        patch_edges.append(data_portal['POSITION'].reshape(*px.shape,3))
        # Publish the same triangles to character, camera and ship ground queries.
        portal_surfaces[key]={'origin':[float(px.min()),float(pz.min())],'spacing':.25,
            'cells':[px.shape[1]-1,px.shape[0]-1],'heights':portal_y.round(5).ravel().tolist(),
            'openCells':np.flatnonzero(bore).tolist()}
        wx,wz=camp['water']
        half=6; step=.25
        gx,gz=np.meshgrid(np.arange(-half,half+step,step)+wx,np.arange(-half,half+step,step)+wz)
        rim=ease((np.maximum(abs(gx-wx),abs(gz-wz))-(half-1.25))/1.25)
        bed=ground(gx,gz)*(1-rim)+height_at(h,gx,gz,(ox,oz))*rim
        level=SPRING_LEVELS[key]
        wet=(1-ease((bed-level+.015)/.37))*(1-ease((spring_radius(gx,gz,camp)-1.10)/.5))
        fine,faces=terrain_data(gx,gz,bed,step,wet)
        mesh.mesh('spring_bank_'+key,fine,faces.reshape(-1,3))
        patch_edges.append(fine['POSITION'].reshape(*gx.shape,3))
        mask=water_mesh(mesh,key,gx,gz,bed,level,camp,faces.reshape(-1,3))
        ok &= ~((abs(x[:-1,:-1]+.5-wx)<half)&(abs(z[:-1,:-1]+.5-wz)<half))
        springs[key]={'origin':[wx-half,wz-half],'cells':len(gx)-1,'spacing':step,'level':level,'first':sum(a.size for a in fine_fields),'waterFirst':sum(a.size for a in wet_cells)}
        fine_fields.append(bed.astype('<f4'))
        wet_cells.append(mask)
    np.concatenate(wet_cells).tofile(OUT/'spring_water_cells.bin')
    (OUT/'portal_ground.json').write_text(json.dumps(portal_surfaces,separators=(',',':')))
    (OUT/'springs.json').write_text(json.dumps(springs))
    np.concatenate([a.ravel() for a in fine_fields]).tofile(OUT/'spring_beds.bin')
    stitch_ground_edges(mesh,data,tris,ok,patch_edges,(ox,oz))
    for j in range(0,nz,32):
        for i in range(0,nx,32):
            cells=tris[j:j+32,i:i+32][ok[j:j+32,i:i+32]]
            mesh.mesh(f"slope_{i}_{j}",data,cells.reshape(-1,3))
    bake_horizon(mesh,ROOT,h,REGION)
    mesh.write("terrain",OUT)
    root_rims,rock_feet=build_contacts(ROOT/'art/field_regions',OUT)
    rock_mask=np.zeros((2*nz+1,2*nx+1),bool)

    def surface_height(px,pz):
        px,pz=np.broadcast_arrays(np.asarray(px),np.asarray(pz))
        result=height_at(h,px,pz,(ox,oz))
        for spring,bed in zip(springs.values(),fine_fields):
            sx,sz=spring['origin']; length=spring['spacing']*spring['cells']
            inside=(px>=sx)&(px<=sx+length)&(pz>=sz)&(pz<=sz+length)
            if np.any(inside):
                result=np.where(inside,height_at(bed,px,pz,(sx,sz),spring['spacing']),result)
        return result

    rng=random.Random(83122)
    covers=json.loads((OUT/"cover.json").read_text())
    groups={name:[] for name in [*CATALOG,*covers]}
    solids=[]
    routes=list(REGION["trails"])
    for camp in REGION["camps"].values():
        cx,_,cz=camp["origin"]
        sg=1 if camp["yaw"]==0 else -1
        gate=[cx,cz-4*sg]
        routes += [[gate,camp[k]] for k in ("food","wood","water")]
    route_dist=distance(x,z,routes)

    def place(key,px,pz,scale,clearance=0,force=False):
        if not (ox+.5<=px<ox+nx-1 and oz+.5<=pz<oz+nz-1):return
        i,j=int(px-ox),int(pz-oz)
        if not force and route_dist[j,i] < (2.45+clearance if clearance else 1.60):return
        for camp in REGION["camps"].values():
            cx,_,cz=camp["origin"]
            v=(pz-cz)*(1 if camp["yaw"]==0 else -1)
            if -5<v<34 and abs(px-cx)<4.8:return
            if not force and math.dist((px,pz),camp["water"])<3.35:return
        px,pz,scale=round(px,2),round(pz,2),round(scale,3)
        y=float(surface_height(px,pz))
        yaw=round(rng.uniform(-math.pi,math.pi),3)
        sink=.025
        if key in ROCKS:
            footprint=CATALOG[key]["width"]*scale*.5
            slope=math.hypot(dx_grid[j,i],dz_grid[j,i])
            sink=scale*.21+min(footprint*slope,scale*1.15)
            if key=="rock_shelf":
                yaw=round(math.atan2(float(dx_grid[j,i]),float(dz_grid[j,i]))+rng.uniform(-.28,.28),3)
                sink+=.64*scale
            # Consume the authored orientation before excluding this local face so
            # every subsequent seeded placement outside the study keeps its pose.
            if 282<px<332 and -1.5<photo.scarp_depth(px,pz)<12:
                return
            c,s=math.cos(yaw)*scale,math.sin(yaw)*scale
            x0,z0=rock_feet[key].T
            rx,rz=px+c*x0+s*z0,pz-s*x0+c*z0
            ri,rj=np.clip(np.rint(rx-ox).astype(int),0,nx),np.clip(np.rint(rz-oz).astype(int),0,nz)
            if np.any(route_dist[rj,ri]<2.15) or any(np.any(spring_radius(rx,rz,camp)<1.48) for camp in REGION['camps'].values()):return
            for camp in REGION['camps'].values():
                cx,_,cz=camp['origin']; depth=(rz-cz)*(1 if camp['yaw']==0 else -1)
                if np.any((abs(rx-cx)<4.2)&(depth<34)&(depth>-4.5)):return
            # Reserve space around actual rock, including the reconstructed back, for exposed ground.
            mi=np.clip(np.rint((rx-ox)*2).astype(int),1,2*nx-1); mj=np.clip(np.rint((rz-oz)*2).astype(int),1,2*nz-1)
            for di in (-1,0,1):
                for dj in (-1,0,1): rock_mask[mj+dj,mi+di]=True
        if key in TREES:
            rim=root_rims[key]; c,s=math.cos(yaw)*scale,math.sin(yaw)*scale
            gx,gz=px+c*rim[:,0]+s*rim[:,2],pz-s*rim[:,0]+c*rim[:,2]
            sink=y-float(np.min(surface_height(gx,gz)-rim[:,1]*scale))+.085
        groups[key].append([px,round(y-sink,3),pz,yaw,scale])
        if key in ROCKS:
            solids.append({'type':'rock','profile':key,'x':px,'z':pz,'base':round(y-sink,3),'r':round(clearance*scale,2),
                           'height':round(CATALOG[key]['height']*scale,2),'yaw':yaw,'scale':scale})
            return
        if clearance:
            solids.append({"x":round(px,2),"z":round(pz,2),"r":round(clearance*scale,2),"type":"tree" if "tree" in key else "rock",("treeHeight" if "tree" in key else "height"):round(CATALOG[key]["height"]*scale,2)})

    # Widely separated canopy crowns leave pools of daylight on the trail.
    for ix in range(32,179,7):
        for jz in range(-135,27,7):
            px,pz=ix+rng.uniform(-2.7,2.7),jz+rng.uniform(-3,3)
            if rng.random()<(.62 if px<119 else .62*max(0,(176-px)/57)):
                place(rng.choice(["grove_tree","grove_tree","crooked_tree"]),px,pz,rng.uniform(.78,1.48),.37)
    for ix in range(144,384,10):
        for jz in range(-134,26,10):
            px,pz=ix+rng.uniform(-3.6,3.6),jz+rng.uniform(-4,4)
            if rng.random()<.35:
                place(rng.choice(["fork_tree","quiver_tree"]),px,pz,rng.uniform(.72,1.38),.43)
    wet=["underbrush","fern_bush","broadleaf","trail_grass","trail_grass","litter","bank_roots"]
    dryplants=["gazania","gazania_low","ursinia","blue_flower","iceplant","silver_bush","wax_shrub"]
    for k in range(1260):
        px,pz=rng.uniform(31,377),rng.uniform(-133,25)
        humid=px<rng.uniform(126,159)
        kind=rng.choice(wet if humid else dryplants)
        for _ in range(rng.randint(3,9)):
            place(kind,px+rng.gauss(0,1.15),pz+rng.gauss(0,.98),rng.uniform(.70,1.45))
    for k in range(670):
        px,pz=rng.uniform(32,385),rng.uniform(-139,38)
        if px<139:
            kind=rng.choice(["fallen_trunk","old_stump","tangled_roots","wood_rock"])
        else:
            kind=rng.choice(["weathered_rock","rock_shelf","dry_branch","granite_tor"])
        r={"wood_rock":.62,"weathered_rock":.65,"granite_tor":1.05,"rock_shelf":.8,"old_stump":.38}.get(kind,0)
        place(kind,px,pz,rng.uniform(.64,1.64),r)
    for camp in REGION["camps"].values():
        for k,key in (("food","broadleaf" if camp["yaw"]==0 else "wax_shrub"),("wood","fallen_trunk" if camp["yaw"]==0 else "dry_branch")):
            px,pz=camp[k]
            for j in range(3):place(key,px+1.15+j*.3,pz+.7*j,1.2,force=True)
    # Denser ribbons follow lit clearings and the edges of the two main walking routes.
    for (a,b) in zip(REGION["trails"][0],REGION["trails"][0][1:]):
        dx,dz=b[0]-a[0],b[1]-a[1]
        length=math.hypot(dx,dz)
        for _ in range(max(1,int(length*1.75))):
            t=rng.random()
            offset=rng.choice([-1,1])*rng.uniform(2.5,10.5)
            px,pz=a[0]+dx*t-dz/length*offset,a[1]+dz*t+dx/length*offset
            kind=rng.choice(wet if px<140 else dryplants)
            for _ in range(rng.randint(4,9)):
                place(kind,px+rng.gauss(0,.82),pz+rng.gauss(0,.63),rng.uniform(.74,1.43))
    # A second, inexpensive layer joins isolated specimens into swathes. Noise leaves
    # exposed soil between meadows and creates denser ribbons of growth along the trail.
    for pz in np.arange(-131,26,1.82):
        for px in np.arange(31,377,1.82):
            u,v=px+rng.uniform(-.82,.82),pz+rng.uniform(-.82,.82)
            woodland=u<144+7*math.sin(v*.059)
            patch=.5+.24*math.sin(u*.13+v*.16)+.19*math.sin(u*.26-v*.071)+.06*math.cos(v*.41)
            verge=2.1<route_dist[int(v-oz),int(u-ox)]<10
            density=(.24+.65*patch if woodland else .05+.81*max(0,(patch-.32)/.68)) + (.17 if verge else 0)
            if rng.random()>=density:continue
            key=("sedge_bed" if rng.random()<.74 else "fern_bed") if woodland else ("gold_drift" if math.sin(u*.069-v*.102) > -.27 else "blue_drift")
            place(key,u,v,rng.uniform(.70,1.35))
    # Attach understory to the original camp, stream bank, coastal terraces and island.
    # Keep the established paths, player spawns, construction footprint and waterline clear.
    world=json.loads((ROOT/"coop/world.json").read_text())
    coast=json.loads((ROOT/"coop/coast_layout.json").read_text())
    coast_h=np.fromfile(ROOT/"coop/coast/elevation.bin",dtype="<f4").reshape(coast["cells"][1]+1,coast["cells"][0]+1)
    shelters=world["shelter"]
    forest_beds=[(10,-85,3.5,2.0),(15,-78,4,2),(21,-85,4,3),(-6,-92,2,2),
                 (8,-65,5,5),(-6.5,-75,2.0,1.8),(5,-42,3.4,3),(12,-26,3.2,4),
                 (17,-14,4,3),(-8,-15,4,3),(-36,-77,6,5),(-45,-69,6,4)]
    coastal_beds=[(-63,-58,7,7),(-77,-37,6,6),(-78,-69,6,5),(-187,-56,9,9),(-191,-69,6,5)]
    trails=[[(pt[1],pt[2]) for pt in world["route"]]]+[[(pt[0],pt[1]) for pt in coast[k]] for k in ("ridgeTrail","beachTrail","islandTrail")]
    features=[(p["x"],p["z"],p["r"]) for p in world["obstacles"]]
    for biome,beds in [(wet,forest_beds),(dryplants,coastal_beds)]:
        for cx,cz,rx,rz in beds:
            for _ in range(18):
                px,pz=cx+rng.gauss(0,rx*.55),cz+rng.gauss(0,rz*.55)
                kind=rng.choice(["sedge_bed","fern_bed"] if biome is wet else ["gold_drift","blue_drift"]) if rng.random()<.42 else rng.choice(biome)
                for _ in range(5):
                    fx,fz=px+rng.gauss(0,.55),pz+rng.gauss(0,.5)
                    if abs(fx-shelters["x"])<shelters["width"]*.5+.7 and abs(fz-shelters["z"])<shelters["depth"]*.5+.7:continue
                    if any((fx-u)**2+(fz-v)**2<(r+.28)**2 for u,v,r in features):continue
                    if distance(fx,fz,trails)<1.06:continue
                    y=0.0
                    if fx>=-30 and (-35<fx<-7 and -75<fz<-28):continue
                    if fx< -30:
                        gx=(fx-coast["origin"][0])/coast["spacing"]
                        gz=(fz-coast["origin"][1])/coast["spacing"]
                        i,j=int(gx),int(gz)
                        if not (0<=j<coast_h.shape[0]-1 and 0<=i<coast_h.shape[1]-1):continue
                        u,v=gx-i,gz-j
                        tl,tr,bl,br=coast_h[j,i],coast_h[j,i+1],coast_h[j+1,i],coast_h[j+1,i+1]
                        y=tl+(tr-tl)*u+(bl-tl)*v if u+v<=1 else br+(bl-br)*(1-u)+(tr-br)*(1-v)
                        if y<.12 or max(tl,tr,bl,br)-min(tl,tr,bl,br)>.67:continue
                    groups[kind].append([round(fx,2),round(float(y)-.014,3),round(fz,2),round(rng.uniform(-math.pi,math.pi),3),round(rng.uniform(.74,1.27),3)])
    # Carry small stands and the same understory across the old straight forest boundary.
    fringe=random.Random(4301)
    for j in range(-119,13,4):
        for i in range(15,34,4):
            px,pz=i+fringe.uniform(-2,2),j+fringe.uniform(-2,2)
            if distance(px,pz,routes)<2.8 or any(math.hypot(px-u,pz-v)<r+1.15 for u,v,r in features):continue
            key=fringe.choice(['fern_bush','broadleaf','sedge_bed','fern_bed','trail_grass'])
            yaw=fringe.uniform(-math.pi,math.pi); scale=fringe.uniform(.8,1.26)
            base=float(surface_height(px,pz))-.02
            if i<30 and fringe.random()<.075 and distance(px,pz,routes)>3.6:
                key=fringe.choice(['grove_tree','crooked_tree']); rim=root_rims[key];c,s=math.cos(yaw)*scale,math.sin(yaw)*scale
                base=float(np.min(surface_height(px+c*rim[:,0]+s*rim[:,2],pz-s*rim[:,0]+c*rim[:,2])-rim[:,1]*scale))-.16
                solids.append({'type':'tree','x':round(px,2),'z':round(pz,2),'r':round(.37*scale,2),'treeHeight':round(CATALOG[key]['height']*scale,2)})
            groups[key].append([round(px,2),round(base,3),round(pz,2),round(yaw,3),round(scale,3)])
    groups.update(vine_drape=[], vine_scramble=[], leaf_mantle=[])
    photo.plant(place,groups,surface_height,random.Random(71091))

    def keep_plant(p):
        px,_,pz,*_=p
        if px<ox:return True
        i,j=round((px-ox)*2),round((pz-oz)*2)
        if rock_mask[j,i]:return False
        return all((px-camp['water'][0])**2+(pz-camp['water'][1])**2>4.15**2 for camp in REGION['camps'].values())
    for key in groups:
        if key not in ROCKS:groups[key]=[p for p in groups[key] if keep_plant(p)]
    photo.add_canopies(groups,random.Random(51148))
    trunks={(p[0],p[2]) for key in TREES for p in groups[key]}
    solids=[o for o in solids if o['type']!='tree' or (o['x'],o['z']) in trunks]
    (OUT/"plants.json").write_text(json.dumps(groups,separators=(",",":")))
    (OUT/"obstacles.json").write_text(json.dumps(solids,separators=(",",":")))
    print(sum(map(len,groups.values())),"instances;",len(solids),"obstacles")


if __name__=="__main__":
    bake()
