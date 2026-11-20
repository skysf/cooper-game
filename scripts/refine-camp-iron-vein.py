"""Fit the exposed iron mineral layer to the existing Rainline rock face."""
from __future__ import annotations

from math import cos, pi, sin, tau
from pathlib import Path
import json
import random
import runpy


TILE_METRES = 1.44
MATERIAL_NAME = "Iron oxide in fractured host rock"
MAP_NAMES = ("iron_vein_contact_diff", "iron_vein_contact_nor_gl", "iron_vein_contact_rough")


def periodic_noise(u, v, size, rng):
    import numpy as np

    field = rng.uniform(-1.,1.,(size,size)).astype(np.float32)
    x,y = u*size,v*size
    ix,iy = x.astype(np.int32),y.astype(np.int32)
    a,b = x-ix,y-iy
    a,b = a*a*(3-2*a),b*b*(3-2*b)
    ix,iy = ix%size,iy%size
    j,k = (ix+1)%size,(iy+1)%size
    return ((1-b)*((1-a)*field[iy,ix]+a*field[iy,j])+b*((1-a)*field[k,ix]+a*field[k,j])).astype(np.float32)


def mineral_cells(size, rng):
    """Return irregular mineral domains and the distance from their fractured edges."""
    import numpy as np

    count = 112
    jitter = rng.uniform(.06,.94,(count,count,2)).astype(np.float32)
    tags = rng.uniform(-1.,1.,(count,count)).astype(np.float32)
    minerals = np.empty((size,size),np.float32)
    spacing = np.empty_like(minerals)
    for start in range(0,size,192):
        end=min(size,start+192)
        x,y=np.meshgrid(np.arange(size,dtype=np.float32)*count/size,
                        np.arange(start,end,dtype=np.float32)*count/size)
        ix,iy=x.astype(np.int32),y.astype(np.int32)
        fx,fy=x-ix,y-iy
        first=np.full(x.shape,8.,np.float32)
        second=np.full_like(first,8.)
        value=np.zeros_like(first)
        for j in (-1,0,1):
            for i in (-1,0,1):
                cx,cy=(ix+i)%count,(iy+j)%count
                dx,dy=i+jitter[cy,cx,0]-fx,j+jitter[cy,cx,1]-fy
                distance=dx*dx+dy*dy
                closer=distance<first
                value=np.where(closer,tags[cy,cx],value)
                second=np.minimum(second,np.maximum(distance,first))
                first=np.minimum(first,distance)
        minerals[start:end]=value
        spacing[start:end]=np.sqrt(second)-np.sqrt(first)
    return minerals,spacing


def smooth_band(low, high, value):
    import numpy as np

    t=np.clip((value-low)/(high-low),0.,1.)
    return t*t*(3.-2.*t)


def coastal_map(name, size):
    import bpy
    import numpy as np

    image=bpy.data.images[name]
    width,height=image.size[:]
    pixels=np.empty(width*height*4,dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels=pixels.reshape((height,width,4))
    x=(np.arange(size)*width//size+211)%width
    y=(np.arange(size)*height//size+387)%height
    return pixels[y[:,None],x[None,:],:3]


def map_pixels(size):
    import numpy as np

    rng=np.random.default_rng(732017)
    grid=np.arange(size,dtype=np.float32)/size
    u,v=np.meshgrid(grid,grid)
    weather=periodic_noise(u,v,7,rng)
    crust=periodic_noise(u,v,23,rng)
    rubble=periodic_noise(u,v,57,rng)
    grit=periodic_noise(u,v,177,rng)
    dust=periodic_noise(u,v,517,rng)
    mineral,cleavage=mineral_cells(size,rng)
    host=coastal_map("cliff_color",size)
    luma=host[:,:,0]*.30+host[:,:,1]*.52+host[:,:,2]*.18
    scan=np.clip((luma-luma.mean())/max(.015,luma.std()),-2.7,2.7)
    del host,luma

    # Broken bedding is a low-amplitude colour change across the grain. The
    # mineral domains and scanned fracture are independent of that direction.
    layer=2*u+6*v+.29*weather+.076*crust
    along=np.cos(layer*2*pi)
    patches=smooth_band(-.18,.52,crust+.42*rubble)
    bedding=along*patches
    oxide=smooth_band(.30,.79,.456+.35*weather+.26*crust+.09*rubble+.12*bedding)
    iron=np.asarray((.337,.327,.312),dtype=np.float32)
    stained=np.asarray((.513,.335,.207),dtype=np.float32)
    color=iron[None,None,:]+oxide[:,:,None]*(stained-iron)
    core=smooth_band(.029,.15,cleavage)
    fleck=smooth_band(.30,.86,mineral)*core
    graphite=smooth_band(.35,.77,-mineral)*core
    faults=(1.-smooth_band(.004,.06,cleavage))*smooth_band(-.23,.55,rubble)
    intensity=.037*scan+.023*crust+.024*rubble+.018*grit+.012*dust+.061*fleck-.044*graphite-.024*faults
    color=np.clip(color+intensity[:,:,None],.11,.71).astype(np.float32)

    # Derive tangent slopes from depths in metres, instead of changing grain
    # strength as the dimensions of individual UV charts change.
    depth=.0054*rubble+.0021*grit+.00061*dust+.00116*fleck-.00056*faults
    metres=TILE_METRES/size
    dx=(np.roll(depth,-1,axis=1)-np.roll(depth,1,axis=1))*(.50/metres)
    dy=(np.roll(depth,-1,axis=0)-np.roll(depth,1,axis=0))*(.50/metres)
    coast_normal=coastal_map("cliff_normal",size)
    nx=-dx+(coast_normal[:,:,0]-.5)*1.21
    ny=-dy+(coast_normal[:,:,1]-.5)*1.21
    denominator=np.sqrt(1.+nx*nx+ny*ny)
    normal=np.stack((nx/denominator,ny/denominator,1./denominator),axis=-1)
    # Fewer levels in the two signed channels avoid full-resolution colour
    # noise in lossless storage without erasing the underlying mineral facets.
    encoded=np.clip(np.round((normal*.5+.5)*127)/127,0,1).astype(np.float32)
    rough=np.clip(.73+.12*oxide+.046*rubble-.23*fleck+.071*graphite,.45,.92)
    rough=rough.reshape(size//2,2,size//2,2).mean(axis=(1,3),dtype=np.float32)
    return color,encoded,rough[:,:,None]


def material(scratch):
    import bpy
    import numpy as np

    mat=bpy.data.materials.get(MATERIAL_NAME)
    if mat is None:
        mat=bpy.data.materials.new(MATERIAL_NAME)
    mat.use_nodes=True
    nodes,links=mat.node_tree.nodes,mat.node_tree.links
    nodes.clear()
    for name in MAP_NAMES:
        old=bpy.data.images.get(name)
        if old is not None:
            assert old.users == 0, f"Image {name} belongs to another asset too"
            bpy.data.images.remove(old)

    def packed_map(name, pixels, filename, data):
        size=pixels.shape[0]
        img=bpy.data.images.new(name,width=size,height=size,alpha=False)
        img.colorspace_settings.name="Non-Color" if data else "sRGB"
        rgba=np.ones((size,size,4),dtype=np.float32)
        rgba[:,:,:3]=pixels
        img.pixels.foreach_set(rgba.ravel())
        img.filepath_raw=str(Path(scratch)/filename)
        img.file_format="PNG" if data else "JPEG"
        img.save()
        img.pack()
        img.filepath="//maps/"+filename
        return img

    color,normal,roughness=map_pixels(2048)
    shade=nodes.new("ShaderNodeBsdfPrincipled")
    output=nodes.new("ShaderNodeOutputMaterial")
    output.location=(270,100)
    links.new(shade.outputs["BSDF"],output.inputs["Surface"])
    shade.inputs["Metallic"].default_value=.12
    shade.inputs["Roughness"].default_value=.76
    mat.diffuse_color=(.354,.289,.234,1)
    colors=nodes.new("ShaderNodeTexImage")
    colors.image=packed_map(MAP_NAMES[0],color,MAP_NAMES[0]+".jpg",False)
    colors.location=(-640,200)
    normal_map=nodes.new("ShaderNodeTexImage")
    normal_map.image=packed_map(MAP_NAMES[1],normal,MAP_NAMES[1]+".png",True)
    normal_map.location=(-640,-85)
    normal_node=nodes.new("ShaderNodeNormalMap")
    normal_node.inputs["Strength"].default_value=.82
    normal_node.location=(-322,-85)
    rough=nodes.new("ShaderNodeTexImage")
    rough.image=packed_map(MAP_NAMES[2],roughness,MAP_NAMES[2]+".png",True)
    rough.location=(-640,-365)
    links.new(colors.outputs["Color"],shade.inputs["Base Color"])
    links.new(normal_map.outputs["Color"],normal_node.inputs["Color"])
    links.new(normal_node.outputs["Normal"],shade.inputs["Normal"])
    links.new(rough.outputs["Color"],shade.inputs["Roughness"])
    return mat


def metric_uv(obj):
    """Map each visible face at the same metre-based texel density."""
    mesh=obj.data
    layer=mesh.uv_layers.active
    for face in mesh.polygons:
        n=face.normal
        axis=max(range(3),key=lambda i:abs(n[i]))
        side=1. if n[axis]>0. else -1.
        for loop in face.loop_indices:
            x,y,z=mesh.vertices[mesh.loops[loop].vertex_index].co
            if axis==0:
                u,v=side*y,z
            elif axis==1:
                u,v=-side*x,z
            else:
                u,v=x,side*y
            layer.data[loop].uv=(u/TILE_METRES+.231,v/TILE_METRES+.417)
    mesh.update()


def model_signature(collection):
    from hashlib import sha256
    import struct

    signature=sha256()
    for obj in sorted(collection.objects,key=lambda o:o.name):
        mesh=obj.data
        signature.update(obj.name.encode())
        coordinates=[v for point in mesh.vertices for v in point.co]
        signature.update(struct.pack(f"<{len(coordinates)}f",*coordinates))
        for face in mesh.polygons:
            signature.update(struct.pack(f"<{len(face.vertices)+1}I",len(face.vertices),*face.vertices))
    return signature.hexdigest()

def deposit(collection, wall, entry, scratch, mesh_object):
    """Project the ore ribbon onto the actual interior mesh, then recess its perimeter."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree

    start=entry["seam"]["at"]
    assert abs(entry["seam"]["yaw"])<.00001
    triangles = BVHTree.FromPolygons(
        [v.co for v in wall.data.vertices], [p.vertices for p in wall.data.polygons])
    target=Vector((1,0,0))

    def rock(y,z):
        ray=Vector((start[0]-1.70,-(start[2]+z),start[1]+y))
        touch,normal,_,_ = triangles.ray_cast(ray,target,3.3)
        if touch is None or abs(normal.x)<.35:
            raise ValueError(f"Rock surface missing at local vein y/z ({y:.3f},{z:.3f})")
        return touch.x-start[0]

    def section(u):
        center = -.012 + .119*(u-.48)+ .058*sin(u*5.3*pi+.71)+.021*sin(u*10.4*pi+.44)
        width = (.284 + .041*sin(u*6.0*pi+.51)+.013*sin(u*96))*(.30+.70*sin(pi*u)**.51)
        return center,width

    count,across=71,13
    positions,faces=[],[]
    for i in range(count):
        u=i/(count-1)
        z=-1.102+2.165*u
        center,width=section(u)
        feather=min(1.0,15*u,15*(1-u))
        for j in range(across):
            v=j/(across-1)
            delta=2*v-1
            y=center+width*delta
            regular=(.048+.010*sin(u*39+delta*6)+.004*cos(u*109+delta*8))
            offset=.010 - feather*max(0,1-delta**2)**1.2*regular
            positions.append((rock(y,z)+offset,y,z))
        if i>0:
            a,b=(i-1)*across,i*across
            for j in range(across-1):
                faces.append((a+j,b+j,b+j+1,a+j+1))
    mat=material(Path(scratch))
    mesh_object(collection,"Iron ore exposed bed and buried perimeter",positions,faces,[mat],
                lambda i,_:(0.,0.),[0]*len(faces),smooth=True)

    rng=random.Random(849)
    for i in range(29):
        u=rng.uniform(.040,.967)
        z=-1.102+2.165*u
        center,width=section(u)
        y=center+rng.uniform(-.61,.61)*width
        zz=rng.uniform(.029,.108)
        yy=zz*rng.uniform(.39,.76)
        phase=rng.uniform(0,tau)
        angle=rng.uniform(-.67,.52)
        count=rng.randrange(7,11)
        shape=[rng.uniform(.85,1.13) for _ in range(count)]
        protrusion=rng.uniform(.048,.084)
        verts=[]
        for taper,depth in ((1.08,-.014),(1.0,protrusion*.57),(.68,protrusion)):
            for j in range(count):
                theta=phase+tau*j/count
                dy=shape[j]*sin(theta)*yy*taper
                dz=shape[j]*cos(theta)*zz*taper
                py=y+dy*cos(angle)-dz*sin(angle)
                pz=z+dy*sin(angle)+dz*cos(angle)
                verts.append((rock(py,pz)-depth+rng.uniform(-.004,.004),py,pz))
        cap=3*count
        top_y=y+rng.uniform(-.012,.012)
        top_z=z+rng.uniform(-.018,.018)
        verts.append((rock(top_y,top_z)-protrusion-rng.uniform(.002,.008),top_y,top_z))
        faces=[]
        for ring in range(2):
            a,b=ring*count,(ring+1)*count
            for j in range(count):
                k=(j+1)%count
                faces.append((a+j,a+k,b+k,b+j))
        faces += [(cap,2*count+j,2*count+(j+1)%count) for j in range(count)]
        obj=mesh_object(collection,f"Iron nodule with chipped bevel {i+1:02}",verts,faces,[mat],
                        lambda j,_:(0.,0.),[0]*len(faces),smooth=True)
        obj.data.set_sharp_from_angle(angle=.81)

    for part in collection.objects:
        metric_uv(part)
    edge=[v[0]-rock(v[1],v[2]) for i,v in enumerate(positions) if i<across or i>=len(positions)-across
          or i%across in (0,across-1)]
    core=[rock(v[1],v[2])-v[0] for i,v in enumerate(positions) if .23<i/len(positions)<.77 and i%across==6]
    return {"measuredWallVertices":len(positions),"perimeterBuriedM":[min(edge),max(edge)],
            "centralReliefM":[min(core),max(core)],"sourcePolygons":sum(len(o.data.polygons) for o in collection.objects)}


def closeups(stage, crew, entry, path, suffix, view=""):
    import bpy
    from mathutils import Vector

    x,y,z=entry["gather"]
    target=Vector(crew["ASSET"]["to_blender"]((x-.022,y+.01,z+.016)))
    if bpy.data.objects.get("Close-up oil lantern") is None:
        lamp=bpy.data.lights.new("Close-up oil lantern","AREA")
        lamp.energy=48.0
        lamp.color=(1.0,.79,.58)
        lamp.size=.65
        fill=bpy.data.objects.new("Close-up oil lantern",lamp)
        stage.collection.objects.link(fill)
        fill.location=crew["ASSET"]["to_blender"]((x-.66,y+.64,z+.28))
        fill.rotation_euler=(target-fill.location).to_track_quat("-Z","Y").to_euler()
    for name,at,aim,lens in (
        ("face",(x-1.10,y+.19,z-.18),(x-.02,y+.017,z+.047),29),
        ("edge",(x-1.25,y+.23,z-1.10),(x-.02,y+.027,z-.13),38),
    ):
        if view and view != name:
            continue
        crew["setup_view"](stage,at,aim,1120,696,lens)
        stage.cycles.samples=18
        stage.render.filepath=str(path/f"{name}-{suffix}.jpg")
        bpy.ops.render.render(write_still=True)


def refine(output, manifest_file, helper_file, baseline_renders=True, render_after=True):
    import bpy

    assert bpy.app.background
    path=Path(output).resolve()
    path.mkdir(parents=True,exist_ok=True)
    assert Path(bpy.data.filepath).resolve().parent != path
    helper=runpy.run_path(str(helper_file))
    asset=helper["ASSET"]
    data=json.loads(Path(manifest_file).read_text())["mines"]["iron_mine"]
    stage=bpy.data.scenes["iron_mine"]
    seam=bpy.data.scenes["iron_seam"]
    collection=bpy.data.collections["iron_seam"]
    bpy.context.window.scene=stage
    camera_pose=stage.camera.matrix_world.copy()
    lens=stage.camera.data.lens
    render_state=(stage.render.resolution_x,stage.render.resolution_y,stage.render.filepath,stage.cycles.samples)
    if baseline_renders:
        closeups(stage,helper,data,path,"before")
        lighting=bpy.data.objects.get("Close-up oil lantern")
        bpy.data.objects.remove(lighting,do_unlink=True)
    geometry=model_signature(collection)
    mat=material(path)
    for part in collection.objects:
        assert list(part.data.materials)==[mat]
        metric_uv(part)
    assert model_signature(collection)==geometry
    metrics={"sourceGeometrySHA256":geometry,"modelPieces":len(collection.objects),
             "tileMetres":TILE_METRES,"baseAndNormalPixels":2048,"roughnessPixels":1024}
    asset["export_part"](seam,collection,path)
    raw=path/"iron_seam.glb"
    normalized=path/"runtime"
    normalized.mkdir(exist_ok=True)
    helper["normalize_shared_images"](raw,normalized/"iron_seam.glb")
    raw.unlink()
    bpy.context.window.scene=stage
    stage.camera.matrix_world=camera_pose
    stage.camera.data.lens=lens
    stage.render.resolution_x,stage.render.resolution_y,stage.render.filepath,stage.cycles.samples=render_state
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(path/"rainline_mines.blend"),compress=True,relative_remap=False)
    (path/"metric-texture.json").write_text(json.dumps(metrics,indent=2)+"\n")
    if render_after:
        closeups(stage,helper,data,path,"after")
    return metrics
