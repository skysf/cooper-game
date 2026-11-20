"""Finish the existing camp table and chair from read-only Blender source copies."""
from __future__ import annotations

import json
from math import pi, radians
from pathlib import Path
import random
import shutil
import struct


WOOD_ATLAS_ROWS = ((0,69),(70,128),(129,190),(191,240),(241,292),
                   (293,356),(357,407),(408,460),(461,511))
USE = {
    "wood_diff": "textures/wood_diff.jpg",
    "wood_nor_gl": "textures/wood_nor_gl.jpg",
    "furniture_endgrain_diff": "props/furniture/furniture_endgrain_diff.jpg",
    "furniture_endgrain_nor_gl": "props/furniture/furniture_endgrain_nor_gl.png",
}
ASSEMBLIES = {
    "camp_table": ("camp_table.blend","props/camp_table.glb"),
    "wood_chair": ("wood_chair.blend","props/storage/wood_chair.glb"),
}
PITCHER = ("Water jug","Hand-shaped jug handle","Quiet waterline")


def end_grain(output):
    import bpy
    import numpy as np

    old=bpy.data.materials.get("Pine end grain • individual boards")
    if old is not None:
        return old
    target=Path(output)/"coop/props/furniture"
    target.mkdir(parents=True,exist_ok=True)
    size=512
    rng=np.random.default_rng(1603)
    u,v=np.meshgrid(np.linspace(0.,1.,size,dtype=np.float32),np.linspace(0.,1.,size,dtype=np.float32))
    flecks=rng.random((size,size),dtype=np.float32)-.5
    oval=np.hypot((u-.22)*1.05, (v-.30)*1.13)
    band=oval+.012*np.sin(u*18.+v*9.)+.005*np.sin(u*39.-v*24.)
    phase=band*2*pi*30+.49*np.sin(v*12+u*7)+.155*np.sin(u*319+v*61)
    rings=np.maximum(0.,np.cos(phase))**3
    early=np.maximum(0.,np.sin(phase-.36))**6
    blade=np.maximum(0.,np.cos(v*pi*455.+np.sin(u*24.)))**11
    tone=.011*np.cos(u*10+v*4)-.063*rings+.037*early-.018*blade+.035*flecks
    background=np.array((.572,.439,.322),dtype=np.float32)
    color=np.clip(background[None,None,:]+tone[:,:,None],.15,.85)
    height=.085*early-.116*rings-.065*blade+.071*flecks
    dy,dx=np.gradient(height)
    normal=np.stack((-dx*3.3,-dy*3.3,np.ones_like(height)),axis=-1)
    normal/=np.linalg.norm(normal,axis=-1,keepdims=True)

    def bitmap(name,pixels,format_name,raw):
        image=bpy.data.images.new(name,width=size,height=size,alpha=False)
        image.colorspace_settings.name="Non-Color" if raw else "sRGB"
        rgba=np.ones((size,size,4),dtype=np.float32)
        rgba[:,:,:3]=pixels
        image.pixels.foreach_set(rgba.ravel())
        image.file_format=format_name
        image.filepath_raw=str(Path(output)/"coop"/USE[name])
        image.save()
        image.pack()
        image.filepath="//furniture/"+Path(USE[name]).name
        return image

    material=bpy.data.materials.new("Pine end grain • individual boards")
    material.use_nodes=True
    material.diffuse_color=(.36,.23,.14,1)
    nodes,links=material.node_tree.nodes,material.node_tree.links
    shader=nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value=.82
    color_node=nodes.new("ShaderNodeTexImage")
    color_node.image=bitmap("furniture_endgrain_diff",color,"JPEG",False)
    color_node.location=(-560,180)
    normal_node=nodes.new("ShaderNodeTexImage")
    normal_node.image=bitmap("furniture_endgrain_nor_gl",normal*.5+.5,"PNG",True)
    normal_node.location=(-560,-90)
    bump=nodes.new("ShaderNodeNormalMap")
    bump.location=(-310,-90)
    bump.inputs["Strength"].default_value=.58
    links.new(color_node.outputs["Color"],shader.inputs["Base Color"])
    links.new(normal_node.outputs["Color"],bump.inputs["Color"])
    links.new(bump.outputs["Normal"],shader.inputs["Normal"])
    return material


def source_parts(kind):
    import bpy

    if kind=="camp_table":
        return [o for o in bpy.context.scene.objects if o.type=="MESH" and o.name not in PITCHER]
    coll = next(c for c in bpy.data.collections if c.get("asset_id")=="wood_chair")
    scene = bpy.context.scene
    for previous in list(scene.collection.children):
        scene.collection.children.unlink(previous)
    scene.collection.children.link(coll)
    for unused in list(bpy.data.collections):
        if unused != coll:
            bpy.data.collections.remove(unused)
    bpy.data.orphans_purge(do_recursive=True)
    scene.unit_settings.system="METRIC"
    return list(coll.objects)


def activate(obj):
    import bpy

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active=obj


def lightly_round(obj):
    import bpy

    if obj.get("furniture_edge_finish") or not obj.name.startswith(("Seat plank","Back shoulder slat","Back rail")):
        return
    activate(obj)
    bevel=obj.modifiers.new("Worn chair edge, approximately one millimetre","BEVEL")
    bevel.width=.00105
    bevel.segments=2
    bevel.limit_method="ANGLE"
    bevel.angle_limit=radians(23)
    bevel.harden_normals=True
    bevel.use_clamp_overlap=True
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    for face in obj.data.polygons:
        face.use_smooth=True
    obj.data.set_sharp_from_angle(angle=radians(47))
    weighted=obj.modifiers.new("Planar timber faces","WEIGHTED_NORMAL")
    weighted.keep_sharp=True
    weighted.weight=32
    bpy.ops.object.modifier_apply(modifier=weighted.name)
    obj["furniture_edge_finish"]=True


def frame_for_board(obj):
    from mathutils import Vector

    verts=[v.co.copy() for v in obj.data.vertices]
    spans=[max(p[i] for p in verts)-min(p[i] for p in verts) for i in range(3)]
    name=obj.name
    length=max(range(3),key=lambda n:spans[n])
    if name.startswith("Worn foot"):
        length=2
    if "peg" in name:
        length=1 if name.startswith("Wooden") else 2
    axis=Vector(tuple(float(i==length) for i in range(3)))
    if name.startswith(("Chair front leg","Chair back upright")):
        # The source posts lean. Align the grain to their actual cut direction.
        z_max=max(p.z for p in verts)
        z_min=min(p.z for p in verts)
        bases=[p for p in verts if abs(p.z-z_min)<.00001]
        peaks=[p for p in verts if abs(p.z-z_max)<.00001]
        axis=(sum(peaks,Vector())/len(peaks)-sum(bases,Vector())/len(bases)).normalized()
    across=Vector(tuple(float(i==(length+1)%3) for i in range(3)))
    across=(across-axis*across.dot(axis)).normalized()
    depth=axis.cross(across).normalized()
    return verts,(axis,across,depth)


def remap(obj, end_material, index):
    mesh=obj.data
    verts,axes=frame_for_board(obj)
    coordinates=[[p.dot(axis) for axis in axes] for p in verts]
    ranges=[(min(row[i] for row in coordinates),max(row[i] for row in coordinates)) for i in range(3)]
    center=[(a+b)*.5 for a,b in ranges]
    dims=[b-a for a,b in ranges]
    rng=random.Random(557+index*127)
    chosen=(index*3 + 1) % len(WOOD_ATLAS_ROWS)
    top,bottom=WOOD_ATLAS_ROWS[chosen]
    uv_mid=1.-(top+bottom)/1024.
    max_across=(bottom-top-12)/512.
    rise=min(.61,max_across/max(.0001,max(dims[1:])))
    long_scale=min(.585,.928/max(.0001,dims[0]))
    length_used=dims[0]*long_scale
    start_u=.036 + rng.uniform(.1,.9)*max(.0,.928-length_used)
    end_span=max(dims[1:]) * 1.21
    slices=(.48+rng.uniform(-.045,.054),.54+rng.uniform(-.06,.066))
    old_names=[m.name for m in mesh.materials]
    peg = "peg" in obj.name
    if end_material.name in old_names:
        end_slot=old_names.index(end_material.name)
    else:
        mesh.materials.append(end_material)
        end_slot=len(mesh.materials)-1
    uv=mesh.uv_layers.active
    count=0
    volumes=[]
    for poly in mesh.polygons:
        grain=poly.normal.dot(axes[0])
        slot=poly.material_index
        if slot < len(old_names) and old_names[slot]=="Fresh fibers in knife cuts":
            continue
        is_end=peg or abs(grain)>.75
        cross_idx=1 if abs(poly.normal.dot(axes[2]))>=abs(poly.normal.dot(axes[1])) else 2
        points=[]
        for index_loop,vert in zip(poly.loop_indices,poly.vertices):
            x,y,z=coordinates[vert]
            if is_end:
                sign=1. if grain>=0. else -1.
                value=(slices[0]+sign*(y-center[1])/end_span,slices[1]+(z-center[2])/end_span)
                if peg and abs(grain)<.61:
                    # The exposed circular end uses rings. Wrap the narrow dowel wall.
                    sign=1. if poly.normal.dot(axes[2])>=0 else -1.
                    value=(.46+(x-center[0])/max(.007,dims[0]),
                           .45+sign*(coordinates[vert][cross_idx]-center[cross_idx])/end_span)
            else:
                across_value=coordinates[vert][cross_idx]-center[cross_idx]
                value=(start_u+(x-ranges[0][0])*long_scale,uv_mid+across_value*rise)
            uv.data[index_loop].uv=value
            points.append(value)
        if is_end:
            poly.material_index=end_slot
            count+=1
            area=abs(sum(a[0]*b[1]-a[1]*b[0] for a,b in zip(points,points[1:]+points[:1])))*.5
            volumes.append(area)
        elif slot<len(old_names) and old_names[slot].startswith("Pine ends and"):
            poly.material_index=0
    mesh.update()
    return {"atlasRow":chosen,"endFaces":count,"smallestEndUv":min(volumes,default=0.)}


def save_export(parts, id, output):
    import bpy

    root=Path(output)
    src,relative=ASSEMBLIES[id]
    source=root/"art"/src
    source.parent.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True,relative_remap=False)
    meshes=[p for p in parts if p.type=="MESH"]
    marker=[p for p in parts if p.type=="EMPTY"]
    bpy.ops.object.select_all(action="DESELECT")
    collection=bpy.data.collections.new("Temporary baked geometry")
    bpy.context.scene.collection.children.link(collection)
    batch=[]
    for part in meshes:
        clone=part.copy()
        clone.data=part.data.copy()
        collection.objects.link(clone)
        clone.select_set(True)
        batch.append(clone)
    bpy.context.view_layer.objects.active=batch[0]
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bpy.ops.object.join()
    baked=bpy.context.object
    baked.name=baked.data.name=id
    for item in marker:
        item.select_set(True)
    raw=root/(id+"-embedded.glb")
    bpy.ops.export_scene.gltf(filepath=str(raw),export_format="GLB",use_selection=True,
        export_tangents=True,export_materials="EXPORT",export_animations=False,
        export_cameras=False,export_lights=False,export_extras=True)
    target=root/"coop"/relative
    target.parent.mkdir(parents=True,exist_ok=True)
    externalize(raw,target,root/"coop")
    raw.unlink()
    return target


def externalize(raw, target, coop):
    """Point both exports at the same project wood texture images."""
    from os.path import relpath

    contents=raw.read_bytes()
    length,chunk=struct.unpack_from("<I4s",contents,12)
    assert chunk == b"JSON"
    data=json.loads(contents[20:20+length])
    old=memoryview(contents)[28+length:]
    image_views=set()
    for img in data["images"]:
        uri=coop/USE[img["name"]]
        assert uri.is_file()
        img["uri"]=Path(relpath(uri,target.parent)).as_posix()
        image_views.add(img.pop("bufferView"))
        img.pop("mimeType",None)
    output=bytearray()
    mapping={}
    kept=[]
    for i,view in enumerate(data["bufferViews"]):
        if i in image_views:
            continue
        output += b"\0" * (-len(output)%4)
        first=view.get("byteOffset",0)
        view["byteOffset"]=len(output)
        output += old[first:first+view["byteLength"]]
        mapping[i]=len(kept)
        kept.append(view)
    output += b"\0" * (-len(output)%4)
    for access in data["accessors"]:
        access["bufferView"]=mapping[access["bufferView"]]
    data["bufferViews"]=kept
    data["buffers"][0]["byteLength"]=len(output)
    meta=json.dumps(data,separators=(",",":")).encode()
    meta+=b" "*(-len(meta)%4)
    with target.open("wb") as file:
        file.write(struct.pack("<4sII",b"glTF",2,28+len(meta)+len(output)))
        file.write(struct.pack("<I4s",len(meta),b"JSON")+meta)
        file.write(struct.pack("<I4s",len(output),b"BIN\0"))
        file.write(output)


def refine(kind, output, wood_inputs):
    import bpy

    assert bpy.app.background
    output=Path(output).resolve()
    assert bpy.data.filepath and output not in Path(bpy.data.filepath).resolve().parents
    output.mkdir(parents=True,exist_ok=True)
    inputs=Path(wood_inputs)
    for name in ("wood_diff","wood_nor_gl"):
        path=output/"coop"/USE[name]
        path.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(inputs/path.name,path)
    parts=source_parts(kind)
    cap=end_grain(output)
    report={}
    for i,obj in enumerate(parts):
        if obj.type!="MESH":
            continue
        lightly_round(obj)
        report[obj.name]=remap(obj,cap,i)
    target=save_export(parts,kind,output)
    (output/(kind+"-mapped.json")).write_text(json.dumps(report,indent=2)+"\n")
    return {"runtime":str(target),"bytes":target.stat().st_size,"woodParts":len(report)}
