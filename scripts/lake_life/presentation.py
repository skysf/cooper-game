"""Make inventory portraits and an editable rowing assembly from the exported meshes."""
import sys
from math import pi
from pathlib import Path
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
MODELS=ROOT/'coop/props/lake_life'
STUDY=ROOT/'art/characters/reed_marsh_study/lakefolk_1700'

def import_asset(asset):
    old=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(MODELS/(asset+'.glb')))
    objects=set(bpy.data.objects)-old
    group=bpy.data.objects.new(asset.title(),None)
    bpy.context.scene.collection.objects.link(group)
    for obj in objects:
        if not obj.parent:obj.parent=group
    return group,objects

def animation(objects,clip):
    rig=next((o for o in objects if o.type=='ARMATURE'),None)
    if not rig:return
    ad=rig.animation_data
    track=next(t for t in ad.nla_tracks if t.name.split('.')[0]==clip)
    for t in ad.nla_tracks:t.mute=True
    ad.action=track.strips[0].action

def studio(center,view,width):
    sc=bpy.context.scene
    world=bpy.data.worlds.new('Overcast skylight');sc.world=world;world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=(.69,.77,.84,1)
    world.node_tree.nodes['Background'].inputs[1].default_value=.45
    camera=bpy.data.cameras.new('Study lens');c=bpy.data.objects.new('Study camera',camera);sc.collection.objects.link(c)
    c.location=Vector(center)+Vector(view).normalized()*width*2.5;c.rotation_euler=(Vector(center)-c.location).to_track_quat('-Z','Y').to_euler()
    camera.type='ORTHO';camera.ortho_scale=width;camera.clip_start=.001;sc.camera=c
    for label,offset,power,size in [('Window',(-2.5,-3.5,5),480,3.2),('Bounce',(2,-1,2),125,2.6),('Rim',(1.4,3.2,3.5),330,2.5)]:
        d=bpy.data.lights.new(label,'AREA');d.energy=power;d.shape='DISK';d.size=size
        o=bpy.data.objects.new(label,d);sc.collection.objects.link(o);o.location=Vector(center)+Vector(offset)
        o.rotation_euler=(Vector(center)-o.location).to_track_quat('-Z','Y').to_euler()
    sc.render.engine='CYCLES';sc.cycles.samples=8;sc.cycles.use_denoising=True
    sc.render.film_transparent=True;sc.view_settings.view_transform='AgX'
    sc.render.resolution_percentage=100;sc.render.image_settings.color_mode='RGBA'
    return sc

for key,file,center,angle,scale in [
    ('lamb','inventory_lamb_raw',(.014,.01,.012),(-.50,-.85,1.7),.166),
    ('grilled','inventory_lamb_grilled',(.014,.01,.012),(-.50,-.85,1.7),.166),
    ('wool','inventory_wool',(0.,0.,.048),(-.7,-1,.62),.29),
    ('fleece','guide_meadow_sheep',(-.06,0,.57),(-.58,-1,.25),1.92)]:
    if '--assembly' in sys.argv or '--dock' in sys.argv or '--sheep' in sys.argv:break
    if '--grilled' in sys.argv and key!='grilled':continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    group,objects=import_asset(key)
    if key=='fleece':animation(objects,'Alert')
    sc=studio(center,angle,scale);sc.render.resolution_x=384 if key=='fleece' else 160;sc.render.resolution_y=288 if key=='fleece' else 160
    sc.render.filepath=str(ROOT/'coop/textures'/(file+'.png'));bpy.ops.render.render(write_still=True)

if '--grilled' in sys.argv:
    sys.exit(0)
def prepare_view(scene):
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                space = area.spaces.active
                space.region_3d.view_perspective = 'CAMERA'
                space.overlay.show_overlays = False
                space.shading.type = 'MATERIAL'
    bpy.context.preferences.filepaths.save_version = 0
    scene.render.fps = 30


def save_herd():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for key, x in [('fleece', -1.035), ('shorn', 1.035)]:
        model, objects = import_asset(key)
        model.location.x = x
        animation(objects, 'Graze')
    scene = studio((0,0,.58),(-.19,-1,.31),4.20)
    scene.name = '鹿鸣湖东岸 · 绵羊与剃毛外形'
    scene.frame_start, scene.frame_end = 1, 108
    scene.frame_set(20)
    scene.render.resolution_x, scene.render.resolution_y = 1120, 620
    prepare_view(scene)
    path = ROOT/'art/animals/sheep_study/sheep_motion.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)


if '--assembly' not in sys.argv and '--dock' not in sys.argv:
    save_herd()
if '--sheep' not in sys.argv:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import_asset('hull')
    for model, x in [('herbalist',-1.88), ('ferryman',1.68)]:
        group, objects = import_asset(model)
        group.location = (x,0,.446)
        group.rotation_euler.z = pi/2
        animation(objects,'Moored' if '--dock' in sys.argv else 'Row')
    for img in bpy.data.images:
        if img.has_data and not img.packed_file:
            img.pack()
    scene = studio((0,0,1.12),(.62,-1,.43),7.75)
    scene.name = '鹿鸣湖 · 双人操桨'
    scene.frame_start, scene.frame_end = 1, 279 if '--dock' in sys.argv else 78
    scene.frame_set(12)
    scene.render.resolution_x, scene.render.resolution_y = 1120, 700
    prepare_view(scene)
    dock = '--dock' in sys.argv
    if dock:
        scene.name='鹿鸣湖 · 盘缆与分拣药草'
        scene.frame_set(64)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(STUDY/('lakefolk_dockwork.blend' if dock else 'lakefolk_rowing.blend')), compress=True)
