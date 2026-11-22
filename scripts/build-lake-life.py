"""Blender background exporter for the lake household and the approved sheep study."""
from pathlib import Path
import sys
import bpy
import numpy as np
from mathutils import Matrix

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/lake_life'))
from mesh import Model,material_library
from dock_work import tools_mesh
from rigs import Crew,Sheep,rig_model

HOUSE=ROOT/'art/characters/reed_marsh_study/lakefolk_1700/lakefolk_houseboat.blend'
EWE=ROOT/'art/animals/sheep_study/sheep_study.blend'
OUT=ROOT/'coop/props/lake_life'
TARGETS={'hull':(HOUSE,'07','03  '),'ferryman':(HOUSE,'02','01  '),'herbalist':(HOUSE,'03','02  '),
         'fleece':(EWE,'02','01  '),'shorn':(EWE,'03','02  '),'lamb':(EWE,'04','03  '),'grilled':(EWE,'04','03  '),'wool':(EWE,'02','01  ')}
for key in (sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else TARGETS):
    path,scene_id,prefix=TARGETS[key]
    bpy.ops.wm.open_mainfile(filepath=str(path))
    sc=next(s for s in bpy.data.scenes if s.name.startswith(scene_id));bpy.context.window.scene=sc
    col=next(c for c in bpy.data.collections if c.name.startswith(prefix));root=next(o for o in col.objects if o.type=='EMPTY' and not o.parent)
    frame=root.matrix_world.inverted();lib=material_library(cooked=key == 'grilled');model=Model(key,lib);rig=None
    if key in ('ferryman','herbalist'):
        design=Crew(key=='herbalist');model.collect(list(col.all_objects),frame,key,design.weights,design.mirror)
        design.oar_mesh(model);tools_mesh(design,model);obj=model.finish();rig=rig_model(obj,model.weights,design,[('Moored',351 if design.female else 279),('CastOff',36),('Row',78),('Land',48)])
        print('IK stretch',key,design.max_stretch,flush=True)
    elif key in ('fleece','shorn'):
        design=Sheep();model.collect(list(col.objects),frame,key,design.weights);obj=model.finish()
        rig=rig_model(obj,model.weights,design,[('Graze',108),('Walk',36),('Alert',75),('Collapse',24),('Dead',15)])
    elif key=='wool':
        coat=next(o for o in col.objects if o.type=='MESH' and '连续羊毛被' in o.name)
        model.collect([coat],frame,key,lambda _,p:[{}]*len(p));obj=model.finish()
        coords=np.array([v.co[:] for v in obj.data.vertices]);lo=coords.min(axis=0);hi=coords.max(axis=0)
        coords=(coords-lo)/(hi-lo)*(.245,.160,.094)-(.1225,.080,0.)
        obj.data.vertices.foreach_set('co',coords.astype('f').ravel());obj.data.update()
    else:
        model.collect(list(col.all_objects),frame,key,lambda _,p:[{}]*len(p));obj=model.finish()
    # Export an isolated scene. Hidden objects in the original review scenes retain
    # their own selection in Blender and must never be included in a pickup or skin.
    clean=bpy.data.scenes.new('Lake asset '+key);clean.render.fps=30
    clean.collection.objects.link(obj)
    if rig:clean.collection.objects.link(rig)
    bpy.context.window.scene=clean
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
    if rig:rig.select_set(True);bpy.context.view_layer.objects.active=rig
    else:bpy.context.view_layer.objects.active=obj
    OUT.mkdir(exist_ok=True,parents=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'.glb')),export_format='GLB',use_active_scene=True,use_selection=True,export_animations=bool(rig),
        export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_step=2,export_skins=True,
        export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_yup=True,export_extras=False)
    print('EXPORTED',key,len(obj.data.polygons),(OUT/(key+'.glb')).stat().st_size,flush=True)
