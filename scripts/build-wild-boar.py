"""Open the approved boar study in Blender and build the animated set and game props."""
import sys, math
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'scripts/lake_life'),str(ROOT/'scripts/boar')]
from mesh import Model,runtime_material,browned_cut
from rigs import rig_model
from motion import Boar,CLIPS
from kit import Kit
DIR=ROOT/'art/animals/boar_study'
OUT=ROOT/'coop/props/wild_boar'
OUT.mkdir(parents=True,exist_ok=True)
sc=bpy.context.scene
source={c.name.split(' | ')[-1]:[o for o in c.objects if o.type=='MESH'] for c in bpy.data.collections if c.asset_data}
# The shoulder cut carries hand-painted muscle and fat laid out on its own UV island.
raw=next(n.image for n in source['Shoulder cut'][0].data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image.colorspace_settings.name=='sRGB')
cooked=browned_cut(raw);cooked.name='炙烤野猪肩肉'
# A repeating directional coat grain gives density between the silhouette bristles.
rng=np.random.default_rng(1708);sz=256
noise=rng.normal(0,1,(sz,sz));grain=sum(np.roll(noise,(k//5,k),axis=(0,1)) for k in range(13))/3.6
val=np.clip(.81+.125*grain,.47,1.);rgba=np.ones((sz,sz,4),'f');rgba[:,:,:3]=val[:,:,None]
coat=bpy.data.images.new('硬鬃 · 顺毛笔触',width=sz,height=sz);coat.pixels.foreach_set(rgba.ravel());coat.pack()
materials={k:runtime_material('Boar '+k,im,rough=r) for k,im,r in [('plain',None,.80),('coat',coat,.89),('eye',None,.23),('ivory',None,.49),('raw',raw,.66),('grilled',cooked,.81)]}
for m in materials.values():m.use_backface_culling=False
design=Boar()
def collect(model,objects,kind):
    for original in objects:
        name=original.name
        if kind=='boar_tusk' and '右' in name:continue
        copy=original.copy();copy.data=original.data.copy();sc.collection.objects.link(copy)
        matrix=original.parent.matrix_world.inverted()@original.matrix_world if original.parent else original.matrix_world.copy()
        hair=original.data.materials[0].name.startswith('鬃毛')
        if not hair:
            count=len(copy.data.polygons)
            ratio=.105 if name.startswith('体躯') else .12 if name.startswith('整张') else .20 if count>1200 else .47 if count>180 else 1.
            if kind in ('boar_raw','boar_grilled'):ratio=.58 if count>500 else 1.
            if ratio<1.:
                mod=copy.modifiers.new('Silhouette reduction','DECIMATE');mod.ratio=ratio
        dg=bpy.context.evaluated_depsgraph_get();ev=copy.evaluated_get(dg);me=ev.to_mesh();me.calc_loop_triangles()
        vertex=np.empty((len(me.vertices),3),'f');me.vertices.foreach_get('co',vertex.ravel())
        transform=np.asarray(matrix);vertex=vertex@transform[:3,:3].T+transform[:3,3]
        tri=np.empty((len(me.loop_triangles),3),'i');me.loop_triangles.foreach_get('vertices',tri.ravel())
        loops=np.empty_like(tri);me.loop_triangles.foreach_get('loops',loops.ravel())
        matid=np.empty(len(tri),'i');me.loop_triangles.foreach_get('material_index',matid)
        color=me.color_attributes.get('Pigment');cs=None
        if color is not None:
            cs=np.empty((len(color.data),4),'f');color.data.foreach_get('color',cs.ravel())
        uv=me.uv_layers.active;uvdata=None
        if uv:
            uvdata=np.empty((len(uv.data),2),'f');uv.data.foreach_get('uv',uvdata.ravel())
        for idx,material in enumerate(me.materials):
            mask=matid==idx
            if hair:
                stride=7 if '鬃线' in name or '深色脊' in name else 30 if '顺向' in name else 41
                mask &= (tri[:,0]//6)%stride==0
            if not mask.any():continue
            selected,new=np.unique(tri[mask],return_inverse=True);faces=new.reshape(-1,3);points=vertex[selected]
            if hair:
                # Thicken the retained strips, preserving their roots and direction.
                ids=selected%6;middle=np.where(ids<=1,selected-ids+(1-ids),np.where((ids==2)|(ids==3),selected+(5-2*ids),selected))
                offsets=(points-vertex[middle])*.57
                points=points+offsets
            mn=material.name
            key='coat' if ('被毛' in mn and not hair) else 'ivory' if '犬齿' in mn else 'eye' if any(k in name for k in ('眼球','瞳仁','虹膜')) else 'plain'
            if '肩胛肉' in mn:key='raw' if kind=='boar_raw' else 'grilled'
            colors=cs[selected,:3] if cs is not None else np.tile(material.diffuse_color[:3],(len(points),1))
            if key in ('raw','grilled'):colors=np.ones_like(colors)
            if kind=='boar_grilled' and '脂盖' in name:colors=colors*np.array([.58,.38,.22])
            tex=uvdata[loops[mask]] if uvdata is not None and key in ('raw','grilled') else np.stack((points[:,0]*2,points[:,2]*3+points[:,1]*1.4),axis=-1)[faces]
            weights=[design.weights(name,v) for v in points] if kind=='wild_boar' else [{}]*len(points)
            model.add(points,faces,tex,colors,key,weights)
        ev.to_mesh_clear();bpy.data.objects.remove(copy,do_unlink=True)
def export(name,o,rig=None):
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True)
    if rig:rig.select_set(True)
    bpy.context.view_layer.objects.active=rig or o
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),use_selection=True,use_active_scene=True,export_format='GLB',export_animations=bool(rig),export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_step=2,export_skins=True,export_vertex_color='ACTIVE',export_yup=True)
objects={}
for key,group in [('wild_boar','Wild boar'),('boar_raw','Shoulder cut'),('boar_grilled','Shoulder cut'),('boar_hide','Bristled hide'),('boar_tusk','Lower tusks'),('boar_cloak','cloak'),('tusk_whistle','whistle'),('boar_bedroll','roll'),('boar_bedding','bedding')]:
    model=Model(key,materials)
    if group in source:collect(model,source[group],key)
    else:getattr(Kit(model),group)()
    obj=model.finish()
    if key=='boar_tusk':
        center=(np.min(model.parts[0][0],axis=0)+np.max(model.parts[0][0],axis=0))/2
        for v in obj.data.vertices:v.co-=Vector((center[0],center[1],0))
    rig=rig_model(obj,model.weights,design,CLIPS.items()) if key=='wild_boar' else None
    export(key,obj,rig);objects[key]=(obj,rig)
# A clean, editable .blend containing the rig, clips and camp kit, without the high-poly studies.
output=bpy.data.scenes.new('林地野猪 · 动作与装备')
output.render.fps=30;output.frame_start=1;output.frame_end=126
for i,(name,(obj,rig)) in enumerate(objects.items()):
    group=bpy.data.collections.new(name+' · 模型');output.collection.children.link(group)
    group.objects.link(obj)
    if rig:
        group.objects.link(rig)
        rig.animation_data.action=rig.animation_data.nla_tracks['Forage'].strips[0].action
        rig.show_in_front=False;rig.display_type='WIRE'
    else: obj.location=(2.3+(i-1)%4*.92,1.65*((i-1)//4),0)
bpy.context.window.scene=output
for scene in list(bpy.data.scenes):
    if scene!=output:bpy.data.scenes.remove(scene)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            space=area.spaces.active;space.overlay.show_overlays=False;space.shading.color_type='VERTEX'
            space.region_3d.view_rotation=Vector((1.2,2.5,-.82)).to_track_quat('-Z','Y')
            space.region_3d.view_distance=3.6;space.region_3d.view_location=(0,0,.53)
# glTF multiplies COLOR_0 in the renderer. Make the same multiplication visible
# in the editable Blender file when switching from Solid to Material Preview.
for material in materials.values():
    tree=material.node_tree
    shader=tree.nodes.get('Principled BSDF')
    albedo=tree.nodes.new('ShaderNodeVertexColor');albedo.layer_name='Albedo'
    albedo.location=(-530,160)
    socket=shader.inputs['Base Color']
    if socket.links:
        painted=tree.nodes.new('ShaderNodeMixRGB');painted.blend_type='MULTIPLY'
        painted.inputs[0].default_value=1.0;painted.location=(-180,160)
        tree.links.new(socket.links[0].from_socket,painted.inputs[1])
        tree.links.new(albedo.outputs['Color'],painted.inputs[2])
        tree.links.new(painted.outputs[0],socket)
    else:
        tree.links.new(albedo.outputs['Color'],socket)
bpy.ops.object.select_all(action='DESELECT')
active_rig=objects['wild_boar'][1]
active_rig.select_set(True);bpy.context.view_layer.objects.active=active_rig
output.frame_set(20)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(DIR/'wild_boar_motion.blend'),compress=True)
