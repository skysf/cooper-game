"""Build two isolated elite trouser and boot fits from the editable source scenes."""
import hashlib
import json
from math import cos, sin
from pathlib import Path
import runpy
import sys

import bmesh
import bpy

ROOT = Path(__file__).resolve().parents[2]
GEN = runpy.run_path(str(ROOT/'scripts/build-wild-people.py'))
LOFT = GEN['loft']
MIX = GEN['mix_weights']

LEG_ROWS = [
    (0.106,0.100,-0.007,0.040,0.044),
    (0.132,0.100,-0.009,0.043,0.045),
    (0.148,0.100,-0.010,0.047,0.050),
    (0.164,0.100,-0.012,0.050,0.054),
    (0.171,0.100,-0.013,0.050,0.055),
    (0.191,0.100,-0.014,0.052,0.058),
    (0.207,0.099,-0.014,0.052,0.058),
    (0.235,0.099,-0.015,0.053,0.059),
    (0.285,0.099,-0.016,0.058,0.062),
    (0.338,0.097,-0.013,0.064,0.065),
    (0.383,0.095,-0.008,0.065,0.067),
    (0.438,0.092, 0.001,0.061,0.064),
    (0.481,0.091, 0.010,0.060,0.065),
    (0.511,0.090, 0.009,0.064,0.067),
    (0.565,0.088, 0.003,0.071,0.077),
    (0.642,0.086, 0.001,0.079,0.086),
    (0.716,0.085, 0.000,0.084,0.093),
    (0.790,0.085, 0.000,0.088,0.096),
    (0.848,0.086,-0.002,0.080,0.086),
    (0.892,0.086,-0.003,0.073,0.081),
]


def components(obj):
    mesh=obj.data
    peers=[[] for _ in mesh.vertices]
    for e in mesh.edges:
        a,b=e.vertices
        peers[a].append(b)
        peers[b].append(a)
    visited=set()
    result=[]
    components_of={}
    for start in range(len(peers)):
        if start in visited:
            continue
        visited.add(start)
        remaining=[start]
        part=[]
        while remaining:
            x=remaining.pop()
            part.append(x)
            for y in peers[x]:
                if y not in visited:
                    visited.add(y)
                    remaining.append(y)
        for v in part:
            components_of[v]=len(result)
        result.append({'ids':sorted(part),'faces':[]})
    for f in mesh.polygons:
        result[components_of[f.vertices[0]]]['faces'].append(f.index)
    return result

def leg_surface(mats, female, wool, straps):
    garment = GEN['Surface']('Trousers and boot binding',mats)
    for side,label in [(1,'L'),(-1,'R')]:
        start = len(garment.faces)
        rows = [(z, side*x, y, rx*(0.92 if female else 1.0), ry*(0.97 if female else 1.0))
                for z,x,y,rx,ry in LEG_ROWS]
        shin, thigh = 'shin_'+label, 'thigh_'+label
        weights = lambda p,i,a: MIX(p[2],[(.448,shin),(.538,thigh),(.80,thigh),(.90,'hips')])
        wraps = {2,5} if female else {4,5}
        raised_rows = wraps | {i+1 for i in wraps}
        def contour(p, row, angle):
            z,x,y,rx,ry = rows[row]
            radius = (0.0025 if row in raised_rows else 0.0)
            fold = 0.002 * sin(3.0*angle + 1.4*row)
            depth = radius + fold
            c = cos(angle)
            s = sin(angle)
            slant = (0.006 if female else 0.0035) * s * side if row in range(2,7) else 0.0
            return p[0]+s*depth, p[1]+c*depth, z+slant
        # Samples from the same atlas as the fur. These bands stay inside the
        # deep woven fabric of the full-size and rear figures in the reference.
        cx = 837 if female else 711
        lo, hi = ((550,592) if female else (562,580))
        def weave(row,s,c,front):
            percent = min(1.0,max(0.0,(rows[row][0]-.12)/.71))
            return cx+s*(4.8 if female else 3.4), hi+(lo-hi)*percent
        LOFT(garment,rows,18,wool,weights,weave,contour)
        for row in wraps:
            for i in range(18):
                garment.indices[start+row*18+i]=straps
    return garment


def recolor_binding(material, female):
    material.name = 'Olive wool binding' if female else 'Weathered umber binding'
    color = (.092,.105,.057) if female else (.105,.060,.030)
    material.diffuse_color = (*color,1)
    surface = material.node_tree.nodes.get('Principled BSDF')
    surface.inputs['Base Color'].default_value = (*color,1)
    surface.inputs['Roughness'].default_value = .88


def build(name, output):
    female = name == 'female_elite'
    src = ROOT/'art/wild_man'/(name+'.blend')
    bpy.ops.wm.open_mainfile(filepath=str(src))
    assert bpy.app.background and Path(bpy.data.filepath)==src
    obj = next(o for o in bpy.context.scene.objects if o.type=='MESH')
    rig = next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    mesh = obj.data
    mesh.calc_loop_triangles()
    original_faces = len(mesh.loop_triangles)
    mats = list(mesh.materials)
    wool = next(i for i,m in enumerate(mats) if m.name=='Mask and fleece')
    straps = next(i for i,m in enumerate(mats) if m.name=='Palm green')
    boot = next(i for i,m in enumerate(mats) if m.name=='Horn ridges')
    groups = {g.name:g.index for g in obj.vertex_groups}
    discard, boots = [], []
    for part in components(obj):
        idxs = part['ids']
        leg = sum(any(obj.vertex_groups[g.group].name.startswith(('thigh_','shin_','foot_','toes_'))
                       and g.weight>1e-5 for g in mesh.vertices[idx].groups) for idx in idxs)
        if not leg or max(mesh.vertices[i].co.z for i in idxs)>.9245:
            continue
        materials = {mesh.polygons[i].material_index for i in part['faces']}
        if materials=={boot} and 0.143 < max(mesh.vertices[i].co.z for i in idxs) < 0.147:
            boots.append(idxs)
            continue
        # The bare leg and wraps are the repeated lower-body components.
        # The one obsolete trouser shell per leg is replaced alongside them.
        discard.extend(idxs)
    assert len(boots)==2 and len(discard) in (1806,1918), (name,len(discard),len(boots))

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    indices = list(bm.verts)
    layer = bm.verts.layers.deform.verify()
    uv = bm.loops.layers.uv.verify()
    adjusted = 0
    for shell in boots:
        side = 'L' if sum(indices[i].co.x for i in shell)<0 else 'R'
        for i in shell:
            vertex = indices[i]
            if vertex.co.z < .089:
                continue
            weights = MIX(vertex.co.z,[(.089,'foot_'+side),(.147,'shin_'+side)])
            if isinstance(weights,str):
                weights = {weights:1.0}
            values=vertex[layer]
            del values[groups['foot_'+side]]
            for joint,weight in weights.items():
                values[groups[joint]]=weight
            adjusted += 1
    bmesh.ops.delete(bm, geom=[indices[i] for i in discard], context='VERTS')
    assert all(f.material_index!=straps for f in bm.faces), 'Binding slot must be free in the remaining outfit'
    recolor_binding(mats[straps],female)
    new = leg_surface(mats,female,wool,straps)
    verts = [bm.verts.new(p) for p in new.verts]
    for v,weights in zip(verts,new.weights):
        for joint,weight in weights.items():
            v[layer][groups[joint]]=weight
    for choice,mat,uvs in zip(new.faces,new.indices,new.uvs):
        face = bm.faces.new([verts[i] for i in choice])
        face.material_index=mat
        face.smooth=True
        face_uvs = dict(zip((verts[i] for i in choice),uvs))
        for loop in face.loops:
            u,v=face_uvs[loop.vert]
            loop[uv].uv=(u/1376,1.0-v/768)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    mesh.calc_loop_triangles()
    bpy.context.scene['lower_leg_fit'] = 'Outer wool, fitted leather and leg-bound bindings'
    bpy.context.preferences.filepaths.save_version=0
    output.mkdir(exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.wm.save_as_mainfile(filepath=str(output/(name+'.blend')),compress=True)
    rig.animation_data.action=None
    for track in rig.animation_data.nla_tracks:
        track.mute=False
    bpy.ops.export_scene.gltf(filepath=str(output/(name+'.glb')),export_format='GLB',use_selection=True,
        export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,
        export_cameras=False,export_lights=False,export_texcoords=True,export_materials='EXPORT',
        export_anim_slide_to_zero=True)
    return {'asset':name,'originalTriangles':original_faces,'triangles':len(mesh.loop_triangles),
            'removedVertices':len(discard),'fittedBootUpperVertices':adjusted,
            'sourceSha256':hashlib.sha256(src.read_bytes()).hexdigest(),
            'exportSha256':hashlib.sha256((output/(name+'.glb')).read_bytes()).hexdigest()}


def candidates(output):
    output=Path(output).resolve()
    keys=("male_elite","female_elite")
    if any((output/(key+suffix)).exists() for key in keys for suffix in (".blend",".glb")):
        raise ValueError("Use a fresh output directory")
    output.mkdir(parents=True,exist_ok=True)
    info=[build(key,output) for key in keys]
    (output/"build.json").write_text(json.dumps(info,indent=2)+"\n")
    return info


if __name__ == "__main__":
    candidates(sys.argv[sys.argv.index("--")+1])
