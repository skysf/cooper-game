"""Blender background authoring for the lakeside reeds and the ravine creepers."""
import json
import math
import random
import struct
import tempfile
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art/field_regions/photo_landscapes"
OUT = ROOT / "coop/vegetation/photo_landscapes"
TAU = math.tau
UP = Vector((0, 0, 1))


def radial(angle):
    return Vector((math.cos(angle), math.sin(angle), 0))


def texcoord(cell, u, v):
    # Atlas quadrants in Blender UV space, with a two-pixel gutter.
    if cell=="crown": return .604+u*.392, .002+v*.496
    if cell=="cane": return .502+u*.093, .002+v*.496
    left, bottom = {"silk":(0,.5), "leaf":(.5,.5), "blade":(0,0)}[cell]
    return left+.002+u*.496, bottom+.002+v*.496


class Plant:
    def __init__(self, name):
        self.name = name
        self.verts, self.faces, self.uvs, self.colors = [], [], [], []

    def rows(self, points, uv, cell, tint):
        start = len(self.verts)
        columns = len(points[0])
        for row, uv_row in zip(points, uv):
            self.verts.extend(tuple(p) for p in row)
            self.uvs.extend(texcoord(cell, *coord) for coord in uv_row)
            self.colors.extend([(*tint,1)]*columns)
        for i in range(len(points)-1):
            for j in range(columns-1):
                a=start+i*columns+j
                self.faces.append((a,a+1,a+1+columns,a+columns))

    def cane(self, path, radius, tint, sides=4):
        rows=[]; uvs=[]
        for i, point in enumerate(path):
            tangent=(path[min(i+1,len(path)-1)]-path[max(i-1,0)]).normalized()
            axis=tangent.cross(Vector((0,1,0)))
            if axis.length<.001: axis=tangent.cross(UP)
            axis.normalize()
            other=tangent.cross(axis).normalized()
            ring=[point+(math.cos(TAU*k/sides)*axis+math.sin(TAU*k/sides)*other)*radius[i] for k in range(sides+1)]
            rows.append(ring); uvs.append([(k/sides,i/(len(path)-1)) for k in range(sides+1)])
        self.rows(rows,uvs,'cane',tint)

    def blade(self, path, side, widths, cell, tint, fold=0):
        points=[]; uvs=[]
        for i,(p,w) in enumerate(zip(path,widths)):
            points.append([p-side*w,p+UP*(w*fold),p+side*w])
            uvs.append([(u,i/(len(path)-1)) for u in (0,.5,1)])
        self.rows(points,uvs,cell,tint)

    def finish(self, mat):
        mesh=bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.verts,[],self.faces)
        mesh.materials.append(mat); mesh.update()
        uv=mesh.uv_layers.new(name='Botanical atlas')
        col=mesh.color_attributes.new(name='FieldTint',type='BYTE_COLOR',domain='POINT')
        for i,c in enumerate(self.colors):
            col.data[i].color=c
        for poly in mesh.polygons:
            poly.use_smooth=True
            for loop in poly.loop_indices:
                uv.data[loop].uv=self.uvs[mesh.loops[loop].vertex_index]
        obj=bpy.data.objects.new(self.name,mesh)
        bpy.context.collection.objects.link(obj)
        return obj


def tuft(name,seed,number,cut=False):
    rng=random.Random(seed)
    m=Plant(name)
    for i in range(number):
        a=rng.uniform(-math.pi,math.pi)
        foot=radial(a)*rng.uniform(.06,.32)
        d=radial(a)*.42+Vector((.75,.12,0))
        height=rng.uniform(1.28,1.91)
        lean=rng.uniform(.14,.43)
        def pole(t):
            return foot+UP*(height*t-.045*t*t)+d*lean*(t**1.8)
        stop=rng.uniform(.065,.15) if cut else 1
        ts=[stop*k/5 for k in range(6)]
        m.cane([pole(t) for t in ts],[(.008-.004*t)*rng.uniform(.94,1.05) for t in ts],(.86,.84,.58))
        for j in range(2 if cut else 6):
            t=rng.uniform(.025,.10) if cut else .10+j*.135+rng.uniform(-.045,.045)
            a+=2.28+rng.uniform(-.45,.45)
            direction=radial(a)
            side=radial(a+math.pi/2)
            length=rng.uniform(.12,.29) if cut else rng.uniform(.38,.76)*(1.15-.34*t)
            width=rng.uniform(.012,.027)
            p=pole(t)
            times=[k/5 for k in range(6)]
            path=[p+direction*length*(s*.72+s*s*.28)+UP*length*(s*.95-s*s*1.28) for s in times]
            hue=rng.uniform(.56,1.0)
            m.blade(path,side,[width*(.12+math.sin(s*math.pi)**.68) if s<1 else .0009 for s in times],
                    'blade',(rng.uniform(.72,1),hue,rng.uniform(.50,.86)),.47)
        if cut: continue
        for t in (.32,.61,.81):
            m.cane([pole(t),pole(t+.009)],[.010,.008],(.69,.63,.4))
        # Multiple intersecting curved *branches* keep the panicle round in profile.
        plume_dir=(d+radial(rng.uniform(0,TAU))*.55).normalized()
        extent=rng.uniform(.38,.56)
        for branch in range(3):
            angle=branch*math.pi/3+a
            side=(radial(angle)+UP*math.sin(angle)*.34).normalized()
            times=[0,.23,.49,.74,1]
            origin=pole(1)
            path=[origin+plume_dir*extent*(.34*s+.66*s*s)+UP*extent*(1.08*s-1.08*s*s) for s in times]
            w=rng.uniform(.104,.151)
            m.blade(path,side,[w*.72,w,w*1.02,w*.94,w*.7],'silk',(1,.97,rng.uniform(.84,.96)))
    return m


def vine(name, seed, tall):
    rng=random.Random(seed); m=Plant(name)
    height=1.65 if tall else .82
    for j in range(13):
        a=j*TAU/13+rng.uniform(-.19,.19)
        d=radial(a); side=radial(a+math.pi/2)
        h=height*rng.uniform(.48,1.12); span=rng.uniform(.63,1.28)
        offset=radial(a+.7)*rng.uniform(.04,.27)
        def shoot(t):
            # Shoots first climb through the shrub, then trail down on the outside.
            return offset+d*span*(t**1.4)+side*(.091*math.sin(8*t+a)*t)+UP*(h*(math.sin(t*math.pi*.83)**.82))
        ts=[i/10 for i in range(11)]
        m.cane([shoot(t) for t in ts],[.014-.009*t for t in ts],(.51,.55,.34))
        for i in range(1,11):
            t=i/10
            angle=a+(.99 if i%2 else -.99)+rng.uniform(-.36,.36)
            direction=radial(angle); transverse=radial(angle+math.pi/2)
            joint=shoot(t)
            stalk=rng.uniform(.08,.19)
            leafbase=joint+direction*stalk+UP*.052
            m.cane([joint,leafbase],[.004,.0025],(.64,.64,.40),3)
            size=rng.uniform(.18,.32)*(1.16-.30*t)
            widths=[.19,.62,.62,.45,.12]
            times=[0,.20,.49,.77,1]
            path=[leafbase+direction*(size*s)+UP*size*(.24*math.sin(s*math.pi)-.62*s) for s in times]
            # Cutout supplies the notched heart silhouette; geometry folds at the midrib.
            light=rng.uniform(.61,1.0)
            m.blade(path,transverse,[size*w for w in widths],'leaf',(light,light,rng.uniform(.62,.91)),.25)
    return m


def canopy():
    rng=random.Random(7694); m=Plant('leaf_mantle')
    for layer,(radius,z,total) in enumerate([(1.13,-.37,12),(1.12,.04,13),(.70,.52,9),(.25,.81,5)]):
        for i in range(total):
            a=(i+rng.uniform(-.31,.31)+layer*.46)*TAU/total
            d=radial(a); side=radial(a+math.pi/2)
            origin=d*radius*rng.uniform(.54,.81)+UP*(z+rng.uniform(-.12,.12))
            reach=rng.uniform(.72,1.05)*(1.04-.07*layer)
            # Orient foliage around the volume: lower boughs hang, top boughs turn upward.
            rise=rng.uniform(.13,.49)+layer*.09
            times=[0,.33,.68,1]
            path=[origin+d*(reach*t)+UP*(rise*t+.29*math.sin(t*math.pi)-(.64-layer*.16)*t*t) for t in times]
            tint=.58+.09*layer+rng.uniform(-.09,.13)
            m.blade(path,side,[.48,.60,.62,.41],'crown',(tint,tint*.99,tint*.82),.48)
    return m


def bundle():
    rng=random.Random(842); m=Plant('reed_bundle')
    for i in range(17):
        a=rng.random()*TAU; d=radial(a); base=d*rng.uniform(.012,.045)
        start=base-UP*rng.uniform(.185,.26); end=base*1.4+UP*rng.uniform(.19,.29)
        m.cane([start,base*.72,end],[.006,.005,.003],(1,.90,.65))
        if i%2==0:
            times=[0,.4,.7,1]
            path=[end+d*.079*t+UP*.111*t for t in times]
            m.blade(path,radial(a+1.57),[.035]*4,'silk',(1,.97,.88))
    for z in (-.06,-.045,.05):
        loop=[radial(i*TAU/16)*.043+UP*z for i in range(17)]
        m.cane(loop,[.004]*17,(.43,.42,.28))
    return m


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    mat=bpy.data.materials.new('Field botany · leaf, silk and cane')
    mat.use_nodes=True; mat.use_backface_culling=False
    bs=mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Roughness'].default_value=.89
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(OUT/'field_botany.png')); tex.image.pack()
    mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    mat.node_tree.links.new(tex.outputs['Alpha'],bs.inputs['Alpha'])
    mat.surface_render_method='DITHERED'
    forms=[tuft('reed_silver',992,9),tuft('reed_ochre',71,7),tuft('reed_cut',992,9,True),
           vine('vine_drape',1332,True),vine('vine_scramble',1199,False),canopy(),bundle()]
    objs=[m.finish(mat) for m in forms]
    for i,obj in enumerate(objs):
        obj.location=((i%3)*3.8,(i//3)*3.8,0)
    bpy.ops.wm.save_as_mainfile(filepath=str(ART/'reed_and_vine_studies.blend'),compress=True)
    def export(objects,path):
        bpy.ops.object.select_all(action='DESELECT')
        for ob in objects:
            ob.location=(0,0,0); ob.select_set(True)
        # The two meshes use the very same atlas in Godot and in other glTF viewers.
        # Embed only the geometry into GLB and keep the adjacent PNG as the image URI.
        with tempfile.TemporaryDirectory() as folder:
            gltf=Path(folder)/"study.gltf"
            bpy.ops.export_scene.gltf(filepath=str(gltf),use_selection=True,export_format='GLTF_SEPARATE',
                                      export_yup=True,export_vertex_color='ACTIVE',export_materials='EXPORT')
            doc=json.loads(gltf.read_text())
            binary=(gltf.parent/doc["buffers"][0].pop("uri")).read_bytes()
        doc["images"]=[{"name":"Field botany","uri":"field_botany.png"}]
        doc["materials"][0].update(alphaMode="MASK",alphaCutoff=.28)
        meta=json.dumps(doc,separators=(",",":")).encode()
        meta+=b" "*(-len(meta)%4)
        binary+=bytes(-len(binary)%4)
        path.write_bytes(struct.pack("<4sII",b"glTF",2,28+len(meta)+len(binary))
                         +struct.pack("<I4s",len(meta),b"JSON")+meta
                         +struct.pack("<I4s",len(binary),b"BIN\0")+binary)
    export(objs[:-1],OUT/'field_plants.glb')
    export([objs[-1]],OUT/'reed_bundle.glb')
    for ob in objs[:-1]: ob.hide_render=True
    obj=objs[-1]; obj.rotation_euler=(.08,-.62,0)
    scene.render.engine='CYCLES'; scene.cycles.samples=10; scene.render.film_transparent=True
    scene.render.resolution_percentage=100; scene.render.resolution_x=192; scene.render.resolution_y=192
    world=bpy.data.worlds.new('Studio'); scene.world=world; world.use_nodes=True
    world.node_tree.nodes.get('Background').inputs[0].default_value=(.66,.74,.86,1)
    world.node_tree.nodes.get('Background').inputs[1].default_value=.65
    bpy.ops.object.light_add(type='AREA',location=(-2,-3,4))
    lamp=bpy.context.object; lamp.data.energy=330; lamp.data.shape='DISK'; lamp.data.size=3
    lamp.rotation_euler=(-lamp.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add(location=(.4,-2,.28)); cam=bpy.context.object; scene.camera=cam
    cam.rotation_euler=(Vector((0,0,.035))-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO'; cam.data.ortho_scale=.65
    scene.render.filepath=str(ROOT/'coop/textures/inventory_reed_bundle.png')
    bpy.ops.render.render(write_still=True)


main()
