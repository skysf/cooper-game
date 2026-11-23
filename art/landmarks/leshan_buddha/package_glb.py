"""Export the editable sculpt with its colour and normal relief baked for game import."""
from math import radians
from pathlib import Path
import tempfile

import bpy

OUT = Path(__file__).resolve().parent
sculpture = bpy.data.collections["Leshan • carved sandstone"]
objects = [ob for ob in sculpture.objects if ob.type == 'MESH']
root = next(ob for ob in sculpture.objects if ob.type == 'EMPTY')
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 1
scene.render.bake.use_selected_to_active = False


def select(items):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in items:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = items[0]


def optimize():
    for ob in objects:
        if len(ob.data.polygons) < 1400 or ob.name.startswith(('HalluxNail','Toenail','Toe_')):
            continue
        bpy.context.view_layer.objects.active = ob
        mod = ob.modifiers.new('Game silhouette', 'DECIMATE')
        if ob.name.startswith('Face'):
            mod.ratio = .45
        elif ob.name.startswith('Long earlobe'):
            mod.ratio = .48
        elif ob.name.startswith('Rows of spiral'):
            mod.ratio = .21
        else:
            mod.ratio = .42
        bpy.ops.object.modifier_apply(modifier=mod.name)


def unwrap(items):
    select(items)
    for ob in items:
        uv = ob.data.uv_layers.new(name='Atlas', do_init=False)
        ob.data.uv_layers.active = uv
        uv.active_render = True
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=radians(62), area_weight=.45, island_margin=.001)
    bpy.ops.uv.select_all(action='SELECT')
    bpy.ops.uv.pack_islands(rotate=True, margin_method='FRACTION', margin=.0017, shape_method='AABB')
    bpy.ops.object.mode_set(mode='OBJECT')


def bake_group(name, items, size):
    print('UNWRAP', name, len(items), flush=True)
    unwrap(items)
    source = bpy.data.materials['Weathered sandstone'].copy()
    for ob in items:
        ob.data.materials[0] = source
    nodes, links = source.node_tree.nodes, source.node_tree.links
    src_uv = nodes.new('ShaderNodeUVMap')
    src_uv.uv_map = 'Stone grain metres'
    for tex in [n for n in nodes if n.type == 'TEX_IMAGE']:
        links.new(src_uv.outputs['UV'], tex.inputs['Vector'])
    source_normal = next(n for n in nodes if n.type == 'NORMAL_MAP')
    source_normal.uv_map = src_uv.uv_map
    shader = nodes.get('Principled BSDF')
    out = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL')
    color = shader.inputs['Base Color'].links[0].from_socket
    emission = nodes.new('ShaderNodeEmission')
    links.new(color, emission.inputs['Color'])
    target = nodes.new('ShaderNodeTexImage')
    maps = []
    for mode, title in [('EMIT','colour'),('NORMAL','normal')]:
        output = bpy.data.images.new(name+' '+title, width=size, height=size, alpha=False,
                                     is_data=(mode=='NORMAL'))
        output.generated_color = ((.5,.5,1,1) if mode=='NORMAL' else (.24,.16,.12,1))
        target.image = output
        for node in nodes:
            node.select = False
        target.select = True
        nodes.active = target
        links.new(emission.outputs[0] if mode=='EMIT' else shader.outputs[0], out.inputs['Surface'])
        print('BAKE',name,mode,flush=True)
        bpy.ops.object.bake(type=mode, uv_layer='Atlas', normal_space='TANGENT', margin=7,
                            margin_type='EXTEND', use_clear=False)
        with tempfile.TemporaryDirectory() as temp:
            ext = '.png' if mode=='NORMAL' else '.jpg'
            path = Path(temp)/(output.name+ext)
            output.filepath_raw = str(path)
            output.file_format = 'PNG' if mode=='NORMAL' else 'JPEG'
            output.save()
            img = bpy.data.images.load(str(path),check_existing=False)
            img.name = name+' '+title+' baked'
            if mode=='NORMAL':
                img.colorspace_settings.name='Non-Color'
            img.pack()
        maps.append(img)
    mat = bpy.data.materials.new(name+' • baked sandstone')
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes.get('Principled BSDF')
    shader.inputs['Metallic'].default_value = 0
    shader.inputs['Roughness'].default_value = .91
    shader.inputs['Specular IOR Level'].default_value = .22
    for i,img in enumerate(maps):
        node = nodes.new('ShaderNodeTexImage')
        node.image = img
        if i == 0:
            links.new(node.outputs['Color'],shader.inputs['Base Color'])
        else:
            normal = nodes.new('ShaderNodeNormalMap')
            links.new(node.outputs['Color'],normal.inputs['Color'])
            links.new(normal.outputs['Normal'],shader.inputs['Normal'])
    for ob in items:
        ob.data.materials[0] = mat
        ob.data.uv_layers.remove(ob.data.uv_layers['Stone grain metres'])
        ob.data.color_attributes.remove(ob.data.color_attributes['Stone'])


optimize()
feet = [ob for ob in objects if ob.name.startswith(('Instep','Toe_','Toenail','HalluxNail'))]
bake_group('Feet and toenails', feet, 2048)
bake_group('Monument', [ob for ob in objects if ob not in feet], 2048)
select([root,*objects])
result=bpy.ops.export_scene.gltf(filepath=str(OUT/'leshan_buddha.glb'),use_selection=True,
                          export_format='GLB',export_animations=False,export_vertex_color='NONE',
                          export_attributes=False,export_extras=True,export_cameras=False,export_lights=False)
if result != {'FINISHED'}:
    raise RuntimeError('GLB export failed: '+str(result))
