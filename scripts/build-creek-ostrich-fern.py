"""Create two native ostrich fern growth stages with editable Blender source.

Set RAINLINE_FERN_OUTPUT to a staging directory before running in Blender.
The resulting .blend and .glb may then be inspected and installed together.
"""

import math
import os
from pathlib import Path
import random

import bpy
import numpy as np
from mathutils import Vector


OUTPUT = Path(os.environ['RAINLINE_FERN_OUTPUT'])
SIZE = 512
UP = Vector((0.0, 0.0, 1.0))
EAST = Vector((1.0, 0.0, 0.0))
ATLAS = {'pinna': (8, 8, 504, 242), 'stipe': (8, 254, 122, 504),
         'rhizome': (132, 254, 248, 504), 'scale': (260, 254, 375, 504),
         'fertile': (385, 254, 504, 504)}


def leaf_atlas():
    pixels = np.ones((SIZE, SIZE, 4), dtype=np.float32)
    for kind, (x0, y0, x1, y1) in ATLAS.items():
        u, v = np.meshgrid(np.linspace(0., 1., x1 - x0), np.linspace(0., 1., y1 - y0))
        pattern = np.sin(u * 86 - v * 57) * np.sin(u * 241 + v * 101)
        noise = .014 * np.sin(u * 651 + v * 517) * np.sin(u * 479 - v * 991)
        if kind == 'pinna':
            cross = 2 * v - 1
            side = abs(cross)
            # Pectinate lobes remain connected to the costa, even at the deepest sinuses.
            flank = u - .025 * side - .012 * cross + .0027 * np.sin(u * 46)
            grooves = .5 + .5 * np.cos(math.tau * 21 * flank)
            rounded = np.sqrt(np.clip(1.0 - (1.0 - grooves) ** 2, 0, 1))
            heart = np.sin(math.pi * (.125 + .875 * u ** .71)) ** .78
            edge = heart * (.44 + .54 * rounded)
            alpha = np.clip((edge - side) * 113 + .52, 0., 1.)
            alpha *= np.clip(u * 160 + .03, 0., 1.) * np.clip((1 - u) * 130, 0., 1.)
            costa = np.exp(-(cross / (.045 * (1 - .58 * u) + .016)) ** 2)
            ribs = np.exp(-((np.sin(math.pi * 21 * flank) / .16) ** 2))
            ribs *= (1 - .73 * side) * (1 - .52 * u)
            secondary = .013 * np.exp(-((np.sin((flank + .006 * np.sin(side * 15)) * 42 * math.pi) / .30) ** 2)) * side
            margin = np.clip(side / np.maximum(edge, .12) - .76, 0., .24) * .13
            worn = u ** 4 * (.14 + .86 * (.5 + .5 * np.sin(v * 83 + u * 95)) ** 2)
            broad = .017 * np.sin(u * 14 + v * 12) + .018 * u - .025 * side
            base = np.array([.285, .441, .186]) + broad[:, :, None] * [1.0, 1.10, .69]
            base += worn[:, :, None] * [.122, .057, -.041]
            light = .134 * costa + .071 * ribs + secondary + margin + pattern * .014
            base += light[:, :, None] * [1.05, 1.0, .66]
            pixels[y0:y1, x0:x1, 3] = alpha
        elif kind == 'stipe':
            groove = -.077 * np.exp(-((u - .43) / .077) ** 2) + .044 * np.sin(u * 32 + .32 * np.sin(v * 6))
            blush = (1.0 - v) ** 7
            base = np.array([.303, .372, .169]) + blush[:, :, None] * [.043, -.112, .009]
            base += (groove + .023 * pattern)[:, :, None] * [1, 1, .75]
        elif kind == 'rhizome':
            furrow = .053 * np.sin(u * 73 + .74 * np.sin(v * 45)) * np.cos(v * 8)
            pits = -.071 * np.maximum(0., np.sin(u * 163 + v * 61) * np.cos(v * 241 - u * 73) - .44)
            base = np.array([.202, .145, .103]) + (furrow + pits + .055 * v)[:, :, None] * [1, .82, .60]
        elif kind == 'scale':
            central = .14 * np.exp(-((u - .52) / .075) ** 2) + .051 * np.sin(u * 65 + v * 9)
            base = np.array([.326, .222, .121]) + (central + .15 * v + .016 * pattern)[:, :, None] * [1, .80, .67]
        else:
            striate = .043 * np.sin(math.tau * u * 4 + .3 * np.sin(v * 32))
            bumps = .039 * np.cos(v * math.tau * 7 + .47 * np.sin(u * 24))
            base = np.array([.284, .192, .105]) + (striate + bumps + .073 * v)[:, :, None] * [1, .78, .59]
        pixels[y0:y1, x0:x1, :3] = np.clip(base + noise[:, :, None], .026, .87)

    # Fill gutters from the surrounding opaque tissues. Pinnae have their own transparent border.
    for kind, (x0, y0, x1, y1) in ATLAS.items():
        if kind == 'pinna':
            pixels[:y0, :x1 + 8, 3] = 0
            pixels[y1:y1 + 8, :x1 + 8, 3] = 0
            pixels[:y1 + 8, :x0, 3] = 0
            pixels[:y1 + 8, x1:, 3] = 0
            continue
        pixels[y0:y1, x0 - 5:x0, :3] = pixels[y0:y1, x0:x0 + 1, :3]
        pixels[y0:y1, x1:x1 + 5, :3] = pixels[y0:y1, x1 - 1:x1, :3]
        pixels[y0 - 5:y0, x0 - 5:x1 + 5, :3] = pixels[y0:y0 + 1, x0 - 5:x1 + 5, :3]
        pixels[y1:y1 + 5, x0 - 5:x1 + 5, :3] = pixels[y1 - 1:y1, x0 - 5:x1 + 5, :3]

    image = bpy.data.images.new('Ostrich fern · tissue atlas', SIZE, SIZE, alpha=True)
    image.pixels.foreach_set(pixels.ravel())
    image.update()
    image.alpha_mode = 'STRAIGHT'
    image.pack()
    return image


def material_for(atlas):
    surface = bpy.data.materials.new('Ostrich fern · fronds and crown')
    surface.use_nodes = True
    surface.use_backface_culling = False
    surface.diffuse_color = (.18, .31, .11, 1.)
    nodes = surface.node_tree.nodes
    links = surface.node_tree.links
    image = nodes.new('ShaderNodeTexImage')
    image.image = atlas
    image.extension = 'EXTEND'
    image.location = (-390, 90)
    clip = nodes.new('ShaderNodeMath')
    clip.operation = 'GREATER_THAN'
    clip.inputs[1].default_value = .43
    clip.location = (-170, -70)
    bsdf = nodes.get('Principled BSDF')
    bsdf.inputs['Roughness'].default_value = .86
    bsdf.inputs['Specular IOR Level'].default_value = .19
    links.new(image.outputs['Color'], bsdf.inputs['Base Color'])
    links.new(image.outputs['Alpha'], clip.inputs[0])
    links.new(clip.outputs[0], bsdf.inputs['Alpha'])
    return surface, image


class Tissue:
    def __init__(self, name):
        self.name = name
        self.points = []
        self.colors = []
        self.faces = []
        self.uvs = []

    def point(self, at, tone):
        self.points.append((at.x, at.y, max(0.0, at.z)))
        self.colors.append((*tone, 1.0))
        return len(self.points) - 1

    def face(self, indices, data, region):
        self.faces.append(tuple(indices))
        x0, y0, x1, y1 = ATLAS[region]
        self.uvs.append([((x0 + 2 + (x1 - x0 - 4) * u) / SIZE,
                          (y0 + 2 + (y1 - y0 - 4) * v) / SIZE) for u, v in data])

    def tube(self, axis, radii, sides, tone, region, phase):
        first = len(self.points)
        last = len(axis) - 1
        for i, center in enumerate(axis):
            direction = (axis[min(last, i + 1)] - axis[max(0, i - 1)]).normalized()
            across = direction.cross(UP if abs(direction.z) < .84 else EAST).normalized()
            normal = direction.cross(across).normalized()
            for j in range(sides):
                angle = phase + math.tau * j / sides
                radius = radii[i] * (1.0 + .085 * math.sin(angle * 3 + phase))
                at = center + radius * (across * math.cos(angle) + normal * math.sin(angle))
                self.point(at, tone)
        for i in range(last):
            offset = first + i * sides
            for j in range(sides):
                k = (j + 1) % sides
                self.face((offset + j, offset + k, offset + sides + k, offset + sides + j),
                          ((j / sides, i / last), ((j + 1) / sides, i / last),
                           ((j + 1) / sides, (i + 1) / last), (j / sides, (i + 1) / last)), region)

    def pinna(self, at, length, width, across, tangent, normal, side, tone, bend, twist, near):
        # Both LODs use the same root and tip. The detailed blade adds camber and a curled margin.
        forward = (across * side + tangent * .23 + normal * twist).normalized()
        cross = (tangent - forward * tangent.dot(forward)).normalized()
        along = (0., .54, 1.) if near else (0., 1.)
        across_leaf = (-1., 0., 1.) if near else (-1., 1.)
        first = len(self.points)
        for t in along:
            lift = normal * (bend * math.sin(math.pi * t) - .032 * length * t ** 3)
            axis = at + forward * (length * t) + tangent * (.12 * length * t ** 2) + lift
            for edge in across_leaf:
                curl = normal * (-(edge ** 2) * width * .18 + .09 * width * edge * t)
                self.point(axis + cross * (.5 * width * edge) + curl, tone)

        stride = len(across_leaf)
        for i in range(len(along) - 1):
            for j in range(stride - 1):
                left, right = (across_leaf[j] + 1) * .5, (across_leaf[j + 1] + 1) * .5
                indices = (first+i*stride+j, first+(i+1)*stride+j,
                           first+(i+1)*stride+j+1, first+i*stride+j+1)
                uv = ((along[i], left), (along[i + 1], left),
                      (along[i + 1], right), (along[i], right))
                if forward.cross(cross).dot(normal) < 0.:
                    indices, uv = indices[::-1], uv[::-1]
                self.face(indices, uv, 'pinna')

    def object(self, collection, material):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.points, [], self.faces)
        mesh.update()
        tex = mesh.uv_layers.new(name='Tissue UV')
        colors = mesh.color_attributes.new(name='Frond tint', type='BYTE_COLOR', domain='POINT')
        mesh.color_attributes.active_color = colors
        colors.data.foreach_set('color', [component for value in self.colors for component in value])
        for face, coords in zip(mesh.polygons, self.uvs):
            face.use_smooth = True
            for loop, uv in zip(face.loop_indices, coords):
                tex.data[loop].uv = uv
        mesh.materials.append(material)
        instance = bpy.data.objects.new(self.name, mesh)
        collection.objects.link(instance)
        return instance


def frond(number, azimuth, height, spread, width, pairs, rng, near):
    mesh = Tissue(f'Sterile frond {number + 1:02d}')
    outward = Vector((math.cos(azimuth), math.sin(azimuth), 0.))
    sideways = Vector((-outward.y, outward.x, 0.))
    base = outward * rng.uniform(.012, .031) + UP * rng.uniform(.019, .026)
    lean = rng.uniform(-.085, .093)
    top = rng.uniform(.70, .96)
    roll = rng.uniform(-.27, .27)
    tint = (rng.uniform(.76, 1.08), rng.uniform(.80, 1.01), rng.uniform(.70, .96))

    def arch(t):
        remain = 1. - t
        radial = spread * (3 * remain ** 2 * t * .023 + 3 * remain * t ** 2 * .48 + t ** 3)
        y = height * (3 * remain ** 2 * t * .62 + 3 * remain * t ** 2 * 1.23 + t ** 3 * top)
        return base + outward * radial + sideways * (lean * t ** 2) + UP * y

    span = 23 if near else 10
    stem = [arch(i / span) for i in range(span + 1)]
    stem_radius = [.0039 * (1. - i / span) ** 1.18 + .00048 for i in range(span + 1)]
    mesh.tube(stem, stem_radius, 5 if near else 3, (.84, .87, .72), 'stipe', azimuth)
    for i in range(pairs):
        leaf_tone = tuple(channel * rng.uniform(.87, 1.03) for channel in tint)
        for sign in (-1, 1):
            q = (i + .43 + sign * rng.uniform(.10, .25)) / pairs
            t = .077 + .904 * q
            axis = (arch(t + .001) - arch(t - .001)).normalized()
            plane = (sideways * math.cos(roll * t) + axis.cross(sideways) * math.sin(roll * t)).normalized()
            normal = axis.cross(plane).normalized()
            fullness = max(.049, math.sin(math.pi * (q ** 1.45))) ** .83
            blade = width * fullness * rng.uniform(.91, 1.06)
            margin = min(.018, (.0148 + .0029 * q) * fullness ** .36)
            margin *= rng.uniform(.89, 1.08)
            curvature = blade * rng.uniform(.017, .065)
            twist = rng.uniform(-.13, .14) - .04 * q
            mesh.pinna(arch(t) + plane * (sign * .00045), blade, margin, plane, axis, normal,
                       sign, leaf_tone, curvature, twist, near and blade > .029)

    at = arch(.973)
    axis = (arch(1.) - at).normalized()
    normal = axis.cross(sideways).normalized()
    mesh.pinna(at, (arch(1.) - at).length * 1.14, .00725, axis, sideways, normal,
               1, tint, .00062, 0., near)
    return mesh


def crown(mature, near, rng):
    mesh = Tissue('Rhizome, old stipe bases and scales')
    factor = 1. if mature else .78
    height = .039 * factor
    axis = [Vector((-.004, .001, 0.)), Vector((-.002, 0., .013 * factor)),
            Vector((0., .002, height)), Vector((.001, .0, height + .007))]
    radii = [.030 * factor, .035 * factor, .026 * factor, .007 * factor]
    mesh.tube(axis, radii, 12 if near else 7, (.83, .76, .66), 'rhizome', .1)
    count = 35 if near else 14
    for i in range(count):
        turn = i * 2.399963 + rng.uniform(-.38, .38)
        layer = i / count
        ray = Vector((math.cos(turn), math.sin(turn), 0.))
        across = ray.cross(UP)
        root = ray * ((.026 + .010 * math.sin(layer * math.pi)) * factor) + UP * (layer * height)
        length = rng.uniform(.010, .037) * factor
        tip = root + ray * (length * rng.uniform(.43, .97)) + UP * (length * rng.uniform(.31, .82))
        middle = root.lerp(tip, .44) + ray * (.0022 + .0012 * rng.random())
        side = across * rng.uniform(.0022, .0048)
        shade = rng.uniform(.64, 1.07)
        tint = (shade, shade * .96, shade * .87)
        points = [mesh.point(p, tint) for p in (root - side * .33, middle - side, tip, middle + side, root + side * .33, middle)]
        uv = ((.34, .01), (.04, .38), (.54, .99), (.96, .43), (.66, .01), (.51, .48))
        for j in range(5):
            k = (j + 1) % 5
            mesh.face((points[j], points[k], points[-1]), (uv[j], uv[k], uv[-1]), 'scale')
    for i in range(7 if mature else 4):
        turn = i * .96 + .2
        ray = Vector((math.cos(turn), math.sin(turn), 0.))
        bottom = ray * (.025 * factor) + UP * .012
        middle = bottom + ray * .005 + UP * .024
        top = middle + ray * .009 + UP * rng.uniform(.010, .037) * factor
        mesh.tube((bottom, middle, top), (.0047, .0034, .0019), 5 if near else 3,
                  (.75, .73, .66), 'rhizome', turn)
    return mesh


def fertile(number, near):
    mesh = Tissue(f'Fertile frond {number + 1:02d} · enclosed sori')
    rng = random.Random(4077 + number * 137)
    angle = 1.47 + number * 2.61
    ray = Vector((math.cos(angle), math.sin(angle), 0.))
    side = Vector((-ray.y, ray.x, 0.))
    height = .392 + number * .044

    def rachis(t):
        return ray * (.014 + .070 * t ** 2.1) + side * (.018 * t ** 1.5) + UP * (.024 + height * t)

    rings = 13 if near else 7
    mesh.tube([rachis(i / rings) for i in range(rings + 1)],
              [.0038 - .00335 * i / rings for i in range(rings + 1)], 5 if near else 3,
              (.82, .74, .68), 'fertile', .08)
    pairs = 20 if near else 13
    for i in range(pairs):
        t = (i + .45) / pairs
        for sign in (-1, 1):
            root = rachis(.34 + .64 * t + sign * .006)
            length = (.008 + .031 * math.sin(math.pi * t ** 1.42) ** .75) * rng.uniform(.89, 1.08)
            direction = (side * sign + ray * (.09 + .2 * t) + UP * (.20 + .21 * t)).normalized() * length
            if near and length > .024:
                progress = (0., .19, .35, .50, .65, .82, 1.)
                bulges = (.51, .98, .62, .94, .58, .81, .18)
            else:
                progress = (0., .22, .67, .97)
                bulges = (.58, .99, .81, .17)
            axis = [root + direction * u + UP * (.0024 * math.sin(math.pi * u)) for u in progress]
            mesh.tube(axis, [.00180 * bulge for bulge in bulges], 3,
                      (rng.uniform(.80, 1.02), .88, .81), 'fertile', angle)
    return mesh


def plant(mature, near):
    heights = (1.002, .876, .940, .827, .966, .902, .799) if mature else (.708, .625, .694, .644, .719)
    reaches = (.457, .478, .436, .513, .459, .533, .409) if mature else (.347, .385, .350, .385, .327)
    widths = (.111, .128, .105, .119, .115, .103, .111) if mature else (.080, .086, .079, .076, .083)
    rng = random.Random(44191 if mature else 88430)
    parts = [crown(mature, near, random.Random(7321 if mature else 13727))]
    for index, (height, reach, width) in enumerate(zip(heights, reaches, widths)):
        angle = index * math.tau / len(heights) + rng.uniform(-.21, .20) + (.34 if mature else 1.)
        pairs = rng.randrange(40, 46) if mature else rng.randrange(32, 39)
        parts.append(frond(index, angle, height, reach, width, pairs,
                           random.Random(540 + index * 901 + (0 if mature else 219)), near))
    if mature:
        parts.extend(fertile(i, near) for i in range(2))
    return parts


def collection(name):
    item = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(item)
    return item


def consolidated(name, parts, target, material):
    merged = Tissue(name)
    for part in parts:
        offset = len(merged.points)
        merged.points.extend(part.points)
        merged.colors.extend(part.colors)
        merged.faces.extend(tuple(index + offset for index in face) for face in part.faces)
        merged.uvs.extend(part.uvs)
    return merged.object(target, material)


def add_editable_shading(material, tex):
    nodes, links = material.node_tree.nodes, material.node_tree.links
    tint = nodes.new('ShaderNodeVertexColor')
    tint.layer_name = 'Frond tint'
    tint.location = (-396, 335)
    combine = nodes.new('ShaderNodeMixRGB')
    combine.blend_type = 'MULTIPLY'
    combine.inputs[0].default_value = 1.
    combine.location = (-132, 290)
    links.new(tex.outputs['Color'], combine.inputs[1])
    links.new(tint.outputs['Color'], combine.inputs[2])
    geometry = nodes.new('ShaderNodeNewGeometry')
    geometry.location = (-166, 620)
    reverse = nodes.new('ShaderNodeMixRGB')
    reverse.blend_type = 'MULTIPLY'
    reverse.inputs[2].default_value = (1.19, 1.10, 1.42, 1.)
    reverse.location = (91, 270)
    links.new(geometry.outputs['Backfacing'], reverse.inputs[0])
    links.new(combine.outputs[0], reverse.inputs[1])
    links.new(reverse.outputs[0], nodes.get('Principled BSDF').inputs['Base Color'])


def build():
    assert bpy.app.background, 'Run this mesh source using an isolated Blender CLI session.'
    OUTPUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.name = '鹿鸣溪岸 · Ostrich fern'
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.preferences.filepaths.save_version = 0
    material, texture = material_for(leaf_atlas())
    export = collection('Game mesh at soil origin')
    editable = []
    for growth, mature, x in (('Mature', True, -.68), ('Young', False, .68)):
        for dist, near in (('Near', True), ('Far', False)):
            name = f'Fern{growth}{dist}'
            parts = plant(mature, near)
            edited = collection(f'{growth} · {dist}')
            for part in parts:
                obj = part.object(edited, material)
                obj.location.x = x
                obj.location.y = 0. if near else 1.35
                editable.append(obj)
            consolidated(name, parts, export, material).select_set(True)
    bpy.context.view_layer.objects.active = export.objects[0]
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT / 'creek_ostrich_fern.glb'),
                             export_format='GLB', use_selection=True, export_yup=True,
                             export_animations=False, export_vertex_color='ACTIVE')
    for obj in list(export.objects):
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(data)
    bpy.data.collections.remove(export)
    add_editable_shading(material, texture)
    bpy.context.view_layer.objects.active = editable[1]
    editable[1].select_set(True)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                area.spaces.active.region_3d.view_location = (0., .55, .32)
                area.spaces.active.region_3d.view_distance = 3.4
                area.spaces.active.shading.color_type = 'MATERIAL'
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / 'creek_ostrich_fern.blend'), compress=True)


build()
