"""Bake and export the two mineral pickups from the existing mine Blender source."""
from __future__ import annotations

import argparse
from math import radians
from pathlib import Path
import runpy
import sys

import numpy as np


PROJECT = Path(__file__).resolve().parents[1]
SIZE = 512
ITEMS = ("coal","iron_ore")
MATERIALS = {"coal":"Banding on fractured coal","iron_ore":"Hematite and weathered host"}


def mix(low, high, value):
    return np.asarray(low,dtype=np.float32)+value[:,None]*(np.asarray(high,dtype=np.float32)-low)


def smooth(lo,hi,x):
    a = np.clip((x-lo)/(hi-lo),0.,1.)
    return a*a*(3.-2.*a)


class Stone:
    def __init__(self, kind):
        self.kind = kind
        rng = np.random.default_rng(47512 if kind=="coal" else 15279)
        self.lattices = rng.uniform(-1.,1.,(5,32,32,32)).astype(np.float32)
        self.offsets = rng.uniform(0.,20.,(5,3)).astype(np.float32)
        self.layers = [(a,float(rng.uniform(.0006,.0022)),float(rng.uniform(.40,.95)))
                       for a in (-.01,.003,.016,.024,.036,.045,.062,.066,.079,.093,.111,.117,.129,.144,.154)]

    def noise(self,p,index,scale):
        lattice = self.lattices[index]
        pos = p*scale + self.offsets[index]
        q = np.floor(pos).astype(np.int32)
        f = (pos-q).astype(np.float32)
        a,b,c = (f*f*(3.-2.*f)).T
        x,y,z = (q%32).T
        i,j,k = ((q+1)%32).T

        low = (1-b)*((1-a)*lattice[z,y,x]+a*lattice[z,y,i])+b*((1-a)*lattice[z,j,x]+a*lattice[z,j,i])
        high = (1-b)*((1-a)*lattice[k,y,x]+a*lattice[k,y,i])+b*((1-a)*lattice[k,j,x]+a*lattice[k,j,i])
        return low*(1-c)+high*c

    def sample(self,p,full=False):
        x,y,z = p.T
        wide = self.noise(p,0,18.)
        patch = self.noise(p,1,48.)
        grain = self.noise(p,2,138.)
        grit = self.noise(p,3,306.)
        dust = self.noise(p,4,644.)
        if self.kind=="coal":
            plane = z+.22*x-.095*y+.0018*wide+.00055*patch
            sheen = np.zeros_like(wide)
            groove = np.zeros_like(wide)
            for i,(mark,width,weight) in enumerate(self.layers):
                continuity = (.66+.34*np.cos(44*x-36*y+.79*i))
                local = ((plane-mark)/width)**2
                sheen = np.maximum(sheen,weight*continuity*np.exp(-local))
                groove += .5*weight*continuity*np.exp(-((plane-mark+width*.35)/(width*.42))**2)
            rough_ash = smooth(.15,.77,.65*wide+.30*patch+.20*grain)
            trace = np.maximum(0.,np.cos(161*x+25*y+4.8*patch))**11
            fault = trace*smooth(.01,.64,.76*patch-.21*grain)*(1.-.73*sheen)
            exposed = .00046*patch+.00025*grain+.00012*grit+.00005*dust
            height = exposed*(1.-.66*sheen) + .00026*sheen-.00028*groove-.00066*fault
            if not full:
                return height
            color = mix((.167,.178,.187),(.214,.230,.245),sheen)
            tone = .012*wide+.018*patch+.011*grain+.010*grit+.005*dust-.024*fault
            color += tone[:,None]+rough_ash[:,None]*np.array((.054,.045,.032),np.float32)
            roughness = np.clip(.67+.081*rough_ash-.28*sheen+.046*grain,.31,.86)
            return color,roughness,height

        # The rusty surface follows continuous fracture and host-rock domains.
        angled = .66*z-.38*x+.21*y+.011*wide+.0045*patch
        rusty_spall = np.exp(-((angled-.041)/.008)**2)*smooth(-.36,.58,patch+.24*wide)
        oxides = smooth(.21,.78,.462+.32*wide+.30*patch+.12*grain+.19*rusty_spall)
        grey_grain = smooth(.28,.71,.68*grit+.28*dust)*smooth(-.33,.50,grain+.22*patch)
        relief = smooth(.20,.60,.63*grain+.28*grit)
        crevice = smooth(.31,.64,-(.73*grain+.34*grit))
        host = smooth(.21,.71,-.29*wide+.49*patch+.22*grain)*(1.-.70*oxides)
        height = (.00092*patch+.00062*grain+.00037*grit+.00012*dust
                  +.00039*relief-.00073*crevice+.00012*grey_grain)
        if not full:
            return height
        color = mix((.277,.287,.287),(.515,.342,.234),oxides)
        color += host[:,None]*np.array((.144,.112,.077),dtype=np.float32)
        brightness = .026*patch+.033*grain+.017*grit+.011*dust+.054*grey_grain-.051*crevice
        color += brightness[:,None]
        roughness = np.clip(.64+.17*oxides+.054*host+.056*crevice-.24*grey_grain,.40,.91)
        return color,roughness,height


def uv_atlas(scene, collection, kind):
    import bpy

    bpy.context.window.scene = scene
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection.objects:
        angle = 41.0 if kind=="coal" else 53.0
        for face in obj.data.polygons:
            face.use_smooth = True
        obj.data.set_sharp_from_angle(angle=radians(angle))
        obj.data.uv_layers.active.name = "Mineral UV"
        obj.select_set(True)
        obj.data.update()
    bpy.context.view_layer.objects.active=collection.objects[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=radians(61),island_margin=.019,
                             area_weight=.22,correct_aspect=True,scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()


def cover(collection):
    positions = np.zeros((SIZE,SIZE,3),np.float32)
    tangents = np.zeros_like(positions)
    bitangents = np.zeros_like(positions)
    occupied = np.zeros((SIZE,SIZE),bool)
    overlaps = 0
    for obj in collection.objects:
        mesh = obj.data
        uvs = mesh.uv_layers.active.data
        mesh.calc_loop_triangles()
        vertex = np.asarray([(obj.matrix_world @ vert.co)[:] for vert in mesh.vertices],np.float32)
        for triangle in mesh.loop_triangles:
            xy = np.asarray([uvs[loop].uv[:] for loop in triangle.loops],np.float32)
            xyz = vertex[list(triangle.vertices)]
            lo = np.maximum(0,np.floor(xy.min(axis=0)*SIZE-.5).astype(int))
            hi = np.minimum(SIZE-1,np.ceil(xy.max(axis=0)*SIZE-.5).astype(int))
            x,y = np.meshgrid(np.arange(lo[0],hi[0]+1),np.arange(lo[1],hi[1]+1))
            a,b = xy[1]-xy[0],xy[2]-xy[0]
            det = a[0]*b[1]-a[1]*b[0]
            assert abs(det)>1e-9
            ux,vy=(x+.5)/SIZE-xy[0,0],(y+.5)/SIZE-xy[0,1]
            beta = (ux*b[1]-vy*b[0])/det
            gamma = (vy*a[0]-ux*a[1])/det
            alpha = 1.-beta-gamma
            covered = (alpha>=0)&(beta>=0)&(gamma>=0)
            i,j = y[covered],x[covered]
            overlaps += int(np.count_nonzero(occupied[i,j]))
            weights = np.stack((alpha[covered],beta[covered],gamma[covered]),axis=1)
            positions[i,j] = weights@xyz
            normal_corners = np.asarray([mesh.corner_normals[loop].vector[:] for loop in triangle.loops],np.float32)
            n = weights@normal_corners
            n /= np.maximum(np.linalg.norm(n,axis=1)[:,None],1e-10)
            ds,dt = xyz[1]-xyz[0],xyz[2]-xyz[0]
            pu = (ds*b[1]-dt*a[1])/det
            pv = (dt*a[0]-ds*b[0])/det
            t = pu - np.sum(n*pu,axis=1)[:,None]*n
            t /= np.maximum(np.linalg.norm(t,axis=1)[:,None],1e-10)
            bitan = np.cross(n,t)
            sign = np.where(np.sum(bitan*pv,axis=1)>0.,1.,-1.)
            tangents[i,j] = t
            bitangents[i,j] = bitan*sign[:,None]
            occupied[i,j] = True
    texels = int(np.count_nonzero(occupied))
    assert texels>SIZE*SIZE*.24 and overlaps<=8, (texels,overlaps)
    return positions,tangents,bitangents,occupied


def material_pixels(collection,kind):
    points,tangent,bitangent,mask = cover(collection)
    stone = Stone(kind)
    pos = points[mask]
    color,rough,_ = stone.sample(pos,True)
    step = .00060
    du,dv = step*tangent[mask],step*bitangent[mask]
    dx = (stone.sample(pos+du)-stone.sample(pos-du))/(step*2)
    dy = (stone.sample(pos+dv)-stone.sample(pos-dv))/(step*2)
    length = np.sqrt(1.+dx*dx+dy*dy)
    normal = .5+.5*np.stack((-dx/length,-dy/length,1./length),axis=1)
    sheets = np.zeros((SIZE,SIZE,7),np.float32)
    rgb_mean = color.mean(axis=0)
    sheets[:,:,:3] = rgb_mean
    sheets[:,:,3:6] = (.5,.5,1.)
    sheets[:,:,6] = np.mean(rough)
    sheets[mask] = np.concatenate((np.clip(color,.085,.72),np.round(normal*127.)/127.,rough[:,None]),axis=1)
    vicinity = mask.copy()
    for _ in range(6):
        previous = vicinity.copy()
        for delta in ((1,0),(-1,0),(0,1),(0,-1)):
            shift = np.roll(previous,delta,axis=(0,1))
            fill = ~vicinity & shift
            sheets[fill] = np.roll(sheets,delta,axis=(0,1))[fill]
            vicinity[fill] = True
    finish = sheets[:,:,6:].reshape(SIZE//2,2,SIZE//2,2,1).mean(axis=(1,3),dtype=np.float32)
    return sheets[:,:,:3],sheets[:,:,3:6],finish


def mapped_material(kind, maps, stage):
    import bpy

    material = bpy.data.materials.new(MATERIALS[kind])
    material.use_nodes = True
    material.diffuse_color = (.045,.053,.060,1.) if kind=="coal" else (.143,.102,.078,1.)
    graph = material.node_tree
    shade = graph.nodes.get("Principled BSDF")
    shade.inputs["Metallic"].default_value=.025 if kind=="coal" else .11
    normal_map = graph.nodes.new("ShaderNodeNormalMap")
    normal_map.location=(-330,5)
    normal_map.inputs["Strength"].default_value=.73 if kind=="coal" else .86
    graph.links.new(normal_map.outputs["Normal"],shade.inputs["Normal"])
    targets=(shade.inputs["Base Color"],normal_map.inputs["Color"],shade.inputs["Roughness"])
    for index,(key,pixels,target) in enumerate(zip(("diff","nor_gl","rough"),maps,targets)):
        name = kind+"_chunk_"+key
        width = pixels.shape[0]
        image = bpy.data.images.new(name,width=width,height=width,alpha=False)
        image.colorspace_settings.name = "sRGB" if index==0 else "Non-Color"
        texel = np.ones((width,width,4),np.float32)
        texel[:,:,:3] = pixels
        image.pixels.foreach_set(texel.ravel())
        image.file_format = "JPEG" if index==0 else "PNG"
        filename = name+(".jpg" if index==0 else ".png")
        image.filepath_raw = str(stage/filename)
        image.save()
        image.pack()
        image.filepath = "//maps/"+filename
        node = graph.nodes.new("ShaderNodeTexImage")
        node.location=(-590,220-index*295)
        node.image = image
        graph.links.new(node.outputs["Color"],target)
    return material


def apply_material(scene, collection, kind, scratch):
    """Apply one continuous mineral material to the original geometry."""
    uv_atlas(scene,collection,kind)
    material = mapped_material(kind,material_pixels(collection,kind),Path(scratch))
    for part in collection.objects:
        part.data.materials.clear()
        part.data.materials.append(material)


def export_models(raw):
    import bpy

    assert bpy.app.background
    asset_path = PROJECT/"art/mines/rainline_mines.blend"
    if not bpy.data.filepath or Path(bpy.data.filepath).resolve()!=asset_path.resolve():
        raise RuntimeError(f"Open the editable mine source before exporting: {asset_path}")
    raw.mkdir(parents=True,exist_ok=True)
    export = runpy.run_path(str(PROJECT/"scripts/build-cabin-kit.py"))["export_part"]
    for kind in ITEMS:
        export(bpy.data.scenes[kind],bpy.data.collections[kind],raw)


def pack_models(raw, project):
    tools = runpy.run_path(str(PROJECT/"scripts/build-camp-weapons.py"))
    pack = tools["compress_model"]
    pack.__globals__["ROOT"] = project
    target = project/"coop/props/mines"
    target.mkdir(parents=True,exist_ok=True)
    for kind in ITEMS:
        pack(raw/(kind+".glb"),target/(kind+".glb"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command",required=True)
    export = commands.add_parser("export",help="Export only the two edited pickup scenes")
    export.add_argument("raw",type=Path)
    pack = commands.add_parser("pack",help="Pack runtime GLBs and Basis import settings")
    pack.add_argument("raw",type=Path)
    pack.add_argument("project",type=Path)
    argv = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else None
    args = parser.parse_args(argv)
    if args.command=="export":
        export_models(args.raw.resolve())
    else:
        pack_models(args.raw.resolve(),args.project.resolve())


if __name__=="__main__":
    main()
