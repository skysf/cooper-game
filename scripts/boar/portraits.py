"""Render inventory cutouts and a review of six poses from the exported game meshes."""
from pathlib import Path
from shutil import copyfile
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
cache=ROOT/'.cache/boar-integration';cache.mkdir(parents=True,exist_ok=True)
def portrait(asset,clip='',frame=1):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'coop/props/wild_boar'/(asset+'.glb')))
    if clip:
        rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');ad=rig.animation_data
        tr=next(t for t in ad.nla_tracks if t.name.split('.')[0]==clip)
        for other in ad.nla_tracks:other.mute=True
        ad.action=tr.strips[0].action; bpy.context.scene.frame_set(frame)
    sc=bpy.context.scene;dg=bpy.context.evaluated_depsgraph_get();pts=[]
    for obj in sc.objects:
        if obj.type!='MESH':continue
        ev=obj.evaluated_get(dg);pts.extend(ev.matrix_world@v.co for v in ev.data.vertices)
    half=Vector([(max(p[i] for p in pts)-min(p[i] for p in pts))/2 for i in range(3)])
    center=Vector([min(p[i] for p in pts)+half[i] for i in range(3)])
    direction=Vector((-.53,-1,.24) if clip else (-.48,-.85,1.3) if asset in ('boar_raw','boar_grilled','boar_hide','boar_tusk') else (-.54,-1,.38)).normalized()
    data=bpy.data.cameras.new('Orthographic');cam=bpy.data.objects.new('Viewer',data);sc.collection.objects.link(cam);cam.location=center+direction*4
    cam.rotation_euler=(-direction).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.clip_start=.001;sc.camera=cam
    inv=cam.rotation_euler.to_matrix().inverted();v=[inv@(p-center) for p in pts];aspect=1.48 if clip else 1.
    data.ortho_scale=(2.20 if clip else 1.17*max(max(q.x for q in v)-min(q.x for q in v),(max(q.y for q in v)-min(q.y for q in v))*aspect))
    if clip:cam.location=Vector((-.08,0,.52))+direction*4
    for offset,energy,size in [((-2,-3,4),470,3),((2,-1,1.5),140,2),((1,3,3),470,2.4)]:
        light=bpy.data.lights.new('Softbox','AREA');light.energy=energy;light.size=size
        ob=bpy.data.objects.new('Softbox',light);sc.collection.objects.link(ob);ob.location=center+Vector(offset)
        ob.rotation_euler=(center-ob.location).to_track_quat('-Z','Y').to_euler()
    world=bpy.data.worlds.new('Overcast');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.77,.81,.87,1);world.node_tree.nodes['Background'].inputs[1].default_value=.55;sc.world=world
    sc.render.engine='CYCLES';sc.cycles.samples=8;sc.cycles.use_denoising=True;sc.render.film_transparent=True
    sc.render.resolution_percentage=100;sc.render.resolution_x=480 if clip else 152;sc.render.resolution_y=324 if clip else 152
    sc.render.filepath=str(cache/(clip+'.png') if clip else ROOT/'coop/textures'/('inventory_'+asset+'.png'))
    bpy.ops.render.render(write_still=True)
for a in ['boar_raw','boar_grilled','boar_tusk','boar_hide','boar_cloak','tusk_whistle','boar_bedroll']:
    portrait(a)
for c,f in [('Forage',18),('Warn',14),('Charge',8),('Run',5),('LieDown',22),('Rest',42)]:portrait('wild_boar',c,f)

copyfile(cache/'Warn.png',ROOT/'coop/textures/guide_woodland_boar.png')
