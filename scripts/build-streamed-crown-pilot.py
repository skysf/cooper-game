"""Build editable needle groups around the original streamed tree's boughs.

RAINLINE_CROWN_STAGE contains the extracted source geometry and its attribution.
Outputs stay in that staging folder until the Blender source and game mesh pass review.
"""

import json
import math
import os
from pathlib import Path
import random

import bpy
import numpy as np
from mathutils import Vector


STAGE = Path(os.environ['RAINLINE_CROWN_STAGE'])
ROOT = Path(__file__).resolve().parents[1]
DATA = np.load(STAGE/'input/tree.npz')
META = json.loads((STAGE/'qa/attribution.json').read_text())['pilot']
UP = Vector((0, 0, 1))
WHITE = (1., 1., 1., 1.)


def xyz(points):
    return np.column_stack((points[:, 0], -points[:, 2], points[:, 1]))


def make_material(name, asset, *, cutoff=None, bark=False):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = cutoff is None
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get('Principled BSDF')
    bsdf.inputs['Roughness'].default_value = .89 if bark else .94
    bsdf.inputs['Specular IOR Level'].default_value = .20 if bark else .13
    texture = nodes.new('ShaderNodeTexImage')
    texture.image = bpy.data.images.load(str(ROOT/asset), check_existing=True)
    texture.image.pack()
    texture.location = (-350, 130)
    links.new(texture.outputs['Color'], bsdf.inputs['Base Color'])
    if cutoff is not None:
        clip = nodes.new('ShaderNodeMath')
        clip.operation = 'GREATER_THAN'
        clip.inputs[1].default_value = cutoff
        clip.location = (-124, -45)
        links.new(texture.outputs['Alpha'], clip.inputs[0])
        links.new(clip.outputs[0], bsdf.inputs['Alpha'])
    if bark:
        body = nodes.new('ShaderNodeTexImage')
        body.image = bpy.data.images.load(str(ROOT/'coop/textures/bark_nor_gl.jpg'), check_existing=True)
        body.image.colorspace_settings.name = 'Non-Color'
        body.image.pack()
        body.location = (-600, -215)
        mapping = nodes.new('ShaderNodeNormalMap')
        mapping.inputs['Strength'].default_value = .76
        mapping.location = (-320, -133)
        links.new(body.outputs['Color'], mapping.inputs['Color'])
        links.new(mapping.outputs['Normal'], bsdf.inputs['Normal'])
    return material, texture


class Geometry:
    def __init__(self, name):
        self.name = name
        self.points = []
        self.normals = []
        self.uv = []
        self.colors = []
        self.faces = []

    @classmethod
    def existing(cls, name, field):
        result = cls(name)
        result.points = [tuple(p) for p in xyz(DATA[field+'_positions'])]
        result.normals = [tuple(p) for p in xyz(DATA[field+'_normals'])]
        result.uv = [(u, 1. - v) for u, v in DATA[field+'_uv']]
        result.colors = [tuple(p) for p in DATA[field+'_colors']]
        result.faces = [tuple(p) for p in DATA[field+'_faces']]
        return result

    def vertex(self, point, uv, tint, normal=None):
        self.points.append(tuple(point))
        self.uv.append(uv)
        self.colors.append(tint)
        self.normals.append(normal)
        return len(self.points) - 1

    def include(self, other):
        offset = len(self.points)
        self.points.extend(other.points)
        self.uv.extend(other.uv)
        self.colors.extend(other.colors)
        self.normals.extend(other.normals)
        self.faces.extend(tuple(i + offset for i in face) for face in other.faces)

    def make_object(self, collection, material, parent=None):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.points, [], self.faces)
        mesh.update()
        uv = mesh.uv_layers.new(name='Tissue')
        uv.data.foreach_set('uv',[coordinate for corner in mesh.loops for coordinate in self.uv[corner.vertex_index]])
        colors = mesh.color_attributes.new(name='Canopy shade', type='BYTE_COLOR', domain='POINT')
        colors.data.foreach_set('color', [v for rgba in self.colors for v in rgba])
        mesh.color_attributes.active_color = colors
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        if any(value is not None for value in self.normals):
            normal = [vertex.normal[:] if v is None else v for vertex, v in zip(mesh.vertices, self.normals)]
            mesh.normals_split_custom_set_from_vertices(normal)
        mesh.materials.append(material)
        obj = bpy.data.objects.new(self.name, mesh)
        collection.objects.link(obj)
        obj.parent = parent
        return obj

    def spray(self, start, end, width, roll, droop, tone, tile, near, rank):
        axis = (end-start).normalized()
        sweep = UP.cross(axis).normalized()
        upright = axis.cross(sweep).normalized()
        side = sweep * math.cos(roll) + upright * math.sin(roll)
        normal = axis.cross(side).normalized()
        # A small normal bias keeps a cluster coherent as its narrow blades tilt independently.
        outward = Vector((end.x, end.y, 0.)).normalized()
        tint = (tone * .69, tone * .99, tone * 1.02, rank)
        tangent_normal = (normal * .81 + UP * .17 + outward * .12).normalized()
        rows = (0., .49, 1.) if near else (0., 1.)
        root = len(self.points)
        for t in rows:
            curve = start.lerp(end,t) + normal * droop * (1 - (2*t - 1) ** 2)
            scale = .81 + .19 * math.sin(math.pi * t)
            for edge in (-1, 1):
                at = curve + side * (width * .5 * edge * scale) + UP * (edge * width * .028 * t)
                x = (9.5 + 493.0*t) / 512.
                y = 1. - ((10.5 if tile == 0 else 134.5) + (111.0 if edge == 1 else 0.)) / 256.
                self.vertex(at, (x, y), tint, tuple(tangent_normal))
        for i in range(len(rows)-1):
            first = root+i*2
            self.faces.append((first, first+2, first+3, first+1))

    def twig(self, path, width, phase, rank):
        root = len(self.points)
        progress = 0.0
        radii = (width, width*.58, width*.23)
        for i, point in enumerate(path):
            axis = (path[min(2,i+1)]-path[max(0,i-1)]).normalized()
            a = UP.cross(axis).normalized()
            b = axis.cross(a).normalized()
            if i:
                progress += (point-path[i-1]).length
            for j in range(5):
                angle = phase + math.tau*j/4.
                radial = a*math.cos(angle) + b*math.sin(angle)
                self.vertex(point + radial*radii[i], (.1+phase*.21+j*.25,.38+progress*1.1),
                            (.66,.60,.49,rank), tuple(radial))
        for i in range(2):
            for j in range(4):
                first = root + i*5+j
                self.faces.append((first,first+1,first+6,first+5))


def branch_groups(near):
    old = xyz(DATA['leaf_positions']).reshape(-1,3,2,3)
    old_colors = DATA['leaf_colors'].reshape(-1,6,4).mean(axis=1)
    foliage = [Geometry(f'Whorl {i+1:02d} · needle sprays') for i in range(9)]
    twigs = [Geometry(f'Whorl {i+1:02d} · forks') for i in range(9)]
    order = list(range(len(old)))
    random.Random(23153).shuffle(order)
    for k, slab in enumerate(old):
        rank = (order[k] + .5) / len(order)
        centers = [Vector(a.mean(axis=0)) for a in slab]
        width = Vector(slab[1,1]-slab[1,0]).length
        axis = Vector(slab[1,1]-slab[1,0]).normalized()
        length = (centers[-1]-centers[0]).length
        rng = random.Random(78919+k*1987)
        i = k//21
        def stem(t):
            return centers[0].lerp(centers[1], 2*t) if t <= .5 else centers[1].lerp(centers[2], 2*t-1)

        def leaflet(a,b,side,reach,branch,tilt,hidden=False):
            base = stem(a)
            tip = stem(b) + axis*(side*width*reach) + UP*branch
            sprig = (tip-base).length
            texture = rng.randrange(2)
            color = min(.98,max(.53,old_colors[k,1] + rng.uniform(-.07,.10)))
            frill = .406 + rng.uniform(-.070,.059)
            span = min(width*.49,max(.042,sprig*frill)) * (1. if near else 1.135)
            camber = rng.uniform(-.053,.061)*sprig
            if not hidden:
                foliage[i].spray(base,tip,span,tilt,camber,color,texture,near,rank)

        leaflet(.08,.63,0,0., .033*length,rng.uniform(-.42,.45),hidden=not near)
        leaflet(.46,1.,0,0., 0.,rng.uniform(-.55,.58))
        for sign in (-1,1):
            leaflet(.22+rng.uniform(-.045,.062), .52+rng.uniform(-.068,.069), sign, rng.uniform(.33,.44),
                    rng.uniform(-.15,-.037)*length, sign*rng.uniform(.43,1.05))
            leaflet(.45+rng.uniform(-.041,.057), .76+rng.uniform(-.059,.061), sign, rng.uniform(.22,.33),
                    rng.uniform(-.038,.085)*length, sign*rng.uniform(.28,.89))
        if near and k % 3 == 0 and length > .55:
            twigs[i].twig([stem(.04),stem(.41)-UP*(length*.023),stem(.864)],
                          min(.021,.009+length*.0038),rng.uniform(.11,1.0),rank)
    return foliage, [group for group in twigs if group.faces]


def collection(name, parent=None):
    group = bpy.data.collections.new(name)
    (parent if parent else bpy.context.scene.collection).children.link(group)
    return group


def pivot(name, group, parent=None):
    obj = bpy.data.objects.new(name,None)
    group.objects.link(obj)
    obj.parent = parent
    return obj


def merge(parts, name, group, material, parent):
    geometry = Geometry(name)
    for part in parts:
        geometry.include(part)
    return geometry.make_object(group,material,parent)


def preview_tint(material, texture):
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    colors = nodes.new('ShaderNodeVertexColor')
    colors.layer_name = 'Canopy shade'
    colors.location = (-400,315)
    tint = nodes.new('ShaderNodeMixRGB')
    tint.blend_type = 'MULTIPLY'
    tint.inputs[0].default_value = 1.
    tint.location = (-150,310)
    links.new(texture.outputs['Color'],tint.inputs[1])
    links.new(colors.outputs['Color'],tint.inputs[2])
    links.new(tint.outputs[0],nodes.get('Principled BSDF').inputs['Base Color'])


def build():
    assert bpy.app.background, 'Use an isolated Blender session.'
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.name = 'Luming trail · streamed crown study'
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.preferences.filepaths.save_version = 0
    wood = make_material('Original streamed bark', 'coop/textures/bark_diff.jpg', bark=True)
    needles = make_material('Photographed Pine Tree 01 sprays', 'coop/pines/pine_needles.png', cutoff=.34)
    reference_needles = make_material('Original broad card needles', 'coop/textures/needles.png', cutoff=.35)
    trunk = Geometry.existing('Unchanged trunk and primary supports', 'wood')
    old_leaves = Geometry.existing('Original panels', 'leaf')
    near, near_twigs = branch_groups(True)
    far, _ = branch_groups(False)
    editable = collection('Editable candidate')
    editable_root = pivot('Original streamed tree pivot',editable)
    editable_root['source_world_root'] = META['origin']
    editable_root['collision_radius_m'] = META['collision']['r']
    editable_root['wind_source_height'] = META['tree']['height']
    trunk.make_object(editable,wood[0],editable_root)
    for label,branch,detail in (('LOD0 · Near',near,near_twigs),('LOD1 · Far',far,[])):
        split = collection(label,editable)
        for mesh in branch:
            mesh.make_object(split,needles[0],editable_root)
        for mesh in detail:
            mesh.make_object(split,wood[0],editable_root)
        if not detail:
            split.hide_render = True
            split.hide_viewport = True
    reference = collection('Original canopy · same pivot and scale')
    base = pivot('Before',reference)
    trunk.make_object(reference,wood[0],base)
    old_leaves.make_object(reference,reference_needles[0],base)
    reference.hide_render = True
    reference.hide_viewport = True

    export = collection('Game export')
    tree = pivot('StreamedCrownPilot',export)
    tree['source_world_root'] = META['origin']
    tree['collision_radius_m'] = META['collision']['r']
    tree['wind_source_height'] = META['tree']['height']
    core = trunk.make_object(export,wood[0],tree)
    core.name = 'StreamedWood'
    detailed = pivot('LOD0',export,tree)
    reduced = pivot('LOD1',export,tree)
    merge(near,'NeedleGroupsNear',export,needles[0],detailed)
    merge(near_twigs,'TwigWoodNear',export,wood[0],detailed)
    merge(far,'NeedleGroupsFar',export,needles[0],reduced)
    for obj in export.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = tree
    bpy.ops.export_scene.gltf(filepath=str(STAGE/'production-assets/luming_streamed_crown.glb'),export_format='GLB',
        use_selection=True,export_yup=True,export_materials='NONE',export_animations=False,
        export_vertex_color='ACTIVE',export_extras=True)
    for obj in reversed(list(export.objects)):
        mesh = obj.data
        bpy.data.objects.remove(obj,do_unlink=True)
        if isinstance(mesh,bpy.types.Mesh) and mesh.users==0:
            bpy.data.meshes.remove(mesh)
    bpy.data.collections.remove(export)
    for material, texture in (wood,needles,reference_needles):
        preview_tint(material,texture)
    bpy.context.view_layer.objects.active = editable_root
    editable_root.select_set(True)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                area.spaces.active.region_3d.view_location = (0.,0.,META['tree']['height']*.45)
                area.spaces.active.region_3d.view_distance = 21.0
                area.spaces.active.shading.color_type = 'MATERIAL'
    bpy.ops.wm.save_as_mainfile(filepath=str(STAGE/'production-assets/luming_streamed_crown.blend'),compress=True)


build()
