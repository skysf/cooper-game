"""Model the camp's plank table, knife inscription, and water jug in Blender."""

import math
from pathlib import Path
import random

import bmesh
import bpy
import numpy as np
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
TOP = 0.79
PROPS = ROOT / "coop/props"


def surface(name, rgb, roughness=0.6, metallic=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = (*rgb, 1)
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*rgb, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return material


def timber():
    material = surface("Weathered plank", (0.3, 0.19, 0.09), 0.78)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes.get("Principled BSDF")
    for name, file, colour in (
        ("Grain", "wood_diff.jpg", "sRGB"), ("Pores", "wood_nor_gl.jpg", "Non-Color"),
    ):
        image = bpy.data.images.load(str(ROOT / "coop/textures" / file), check_existing=True)
        image.colorspace_settings.name = colour
        image.pack()
        texture = nodes.new("ShaderNodeTexImage")
        texture.label = name
        texture.image = image
        if name == "Grain":
            links.new(texture.outputs["Color"], shader.inputs["Base Color"])
        else:
            normal = nodes.new("ShaderNodeNormalMap")
            normal.inputs["Strength"].default_value = 0.75
            links.new(texture.outputs["Color"], normal.inputs["Color"])
            links.new(normal.outputs["Normal"], shader.inputs["Normal"])
    return material


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def bevel(obj, width, segments=2):
    activate(obj)
    modifier = obj.modifiers.new("Worn edges", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def beam(name, center, dimensions, material, edge=0.004, offset=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    long_axis = max(range(3), key=lambda axis: dimensions[axis])
    uv = obj.data.uv_layers.active.data
    for face in obj.data.polygons:
        axis = max(range(3), key=lambda i: abs(face.normal[i]))
        cross = next(i for i in range(3) if i not in (axis, long_axis)) if axis != long_axis else (axis + 1) % 3
        grain = long_axis if axis != long_axis else (axis + 2) % 3
        for index in face.loop_indices:
            point = obj.data.vertices[obj.data.loops[index].vertex_index].co
            uv[index].uv = (point[grain] / 0.90 + offset, point[cross] / 0.81 + 0.51)
    if edge > 0:
        bevel(obj, edge)
    return obj


def rail(name, start, end, width, depth, material):
    a, b = Vector(start), Vector(end)
    part = beam(name, (a + b) * 0.5, (width, depth, (b-a).length), material)
    part.rotation_mode = "QUATERNION"
    part.rotation_quaternion = (b-a).to_track_quat("Z", "Y")
    return part


def cylinder(name, center, radius, depth, material, vertices=10):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    return obj


def mesh(name, vertices, faces, material):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    data.materials.append(material)
    return obj


# Draw each glyph by hand as distinct strokes. Small asymmetries are intentional.
GLYPHS = {
    "S": [[(.95,.91),(.67,1.0),(.24,.94),(.11,.76),(.20,.61),(.73,.46),(.87,.31),(.77,.12),(.53,.025),(.19,.07),(.035,.18)]],
    "K": [[(.14,.99),(.12,.55),(.1,.03)],[(.93,.98),(.63,.76),(.15,.48),(.53,.37),(.98,.04)]],
    "Y": [[(.09,.97),(.31,.72),(.53,.49),(.86,.99)],[(.53,.49),(.54,.27),(.49,.015)]],
    "1": [[(.14,.75),(.50,.98),(.54,.63),(.50,.04)],[(.22,.05),(.56,.04),(.83,.025)]],
    "2": [[(.095,.81),(.27,.97),(.59,1.0),(.82,.86),(.83,.67),(.64,.51),(.37,.35),(.17,.17),(.09,.02),(.46,.045),(.9,.02)]],
    "0": [[(.55,.99),(.31,.92),(.15,.72),(.105,.39),(.17,.13),(.39,.025),(.66,.055),(.83,.24),(.87,.58),(.77,.88),(.55,.995)]],
}


def carved_depth(xx, yy):
    rng = random.Random(1120)
    depths = np.zeros_like(xx)
    x = 0.015
    for glyph in "SKY 1120":
        if glyph == " ":
            x += 0.016
            continue
        width = rng.uniform(0.029, 0.033)
        height = rng.uniform(0.049, 0.056)
        baseline = -0.292 + rng.uniform(-0.0038, 0.0038)
        slope = rng.uniform(-0.004, 0.005)
        for stroke in GLYPHS[glyph]:
            control = [Vector((x + u * width + slope * v, baseline + v * height)) for u, v in stroke]
            points = [control[0]]
            for a, b in zip(control, control[1:]):
                side = Vector((a.y - b.y, b.x - a.x)).normalized()
                points.extend((a.lerp(b, .54) + side * rng.uniform(-.00075, .00075), b))
            shapes = []
            for index in range(len(points)):
                taper = 0.40 if index in (0, len(points) - 1) else 1.0
                shapes.append((rng.uniform(.00165, .00260) * taper, rng.uniform(.00195, .00420) * taper))
            for index, (a, b) in enumerate(zip(points, points[1:])):
                dx, dy = b - a
                t = np.clip(((xx - a.x) * dx + (yy - a.y) * dy) / (dx * dx + dy * dy), 0.0, 1.0)
                d = np.hypot(xx - a.x - t * dx, yy - a.y - t * dy)
                w0, z0 = shapes[index]
                w1, z1 = shapes[index + 1]
                radius = w0 + t * (w1 - w0)
                groove = np.maximum(1.0 - d / radius, 0.0) * (z0 + t * (z1 - z0))
                np.maximum(depths, groove, out=depths)
        x += width + rng.uniform(0.007, 0.009)
    return depths


def engraved_board(wood, carved):
    # The carved area is tightly sampled. The flat rim spans the rest of the plank.
    x0, x1, y0, y1 = -.7875, .7775, -.3585, -.1815
    inset = .004
    xs = np.r_[x0 + inset, np.linspace(.002, .325, 300), x1 - inset]
    ys = np.r_[y0 + inset, np.linspace(-.305, -.221, 82), y1 - inset]
    xx, yy = np.meshgrid(xs, ys)
    depths = carved_depth(xx, yy)
    vertices = list(zip(xx.ravel(), yy.ravel(), (TOP - depths).ravel()))
    faces, materials = [], []
    columns, rows = len(xs), len(ys)
    for row in range(rows - 1):
        for col in range(columns - 1):
            a = row * columns + col
            b, c, d = a + 1, a + columns, a + columns + 1
            faces.append((a, b, d, c))
            materials.append(1 if depths[row:row+2, col:col+2].mean() > .00037 else 0)
    boundary = list(range(columns))
    boundary += [(r + 1) * columns - 1 for r in range(1, rows)]
    boundary += [(rows - 1) * columns + c for c in range(columns - 2, -1, -1)]
    boundary += [r * columns for r in range(rows - 2, 0, -1)]
    outer_index = len(vertices)
    for offset in (TOP - inset, TOP - .038):
        for i in boundary:
            x, y, _ = vertices[i]
            x = x0 if x == xs[0] else x1 if x == xs[-1] else x
            y = y0 if y == ys[0] else y1 if y == ys[-1] else y
            vertices.append((x, y, offset))
    count = len(boundary)
    bottom_index = outer_index + count
    for i in range(count):
        j = (i + 1) % count
        faces.append((boundary[i], outer_index + i, outer_index + j, boundary[j]))
        faces.append((outer_index + i, bottom_index + i, bottom_index + j, outer_index + j))
        materials.extend((0, 0))
    faces.append(tuple(reversed(range(bottom_index, bottom_index + count))))
    materials.append(0)

    obj = mesh("Top plank 1", vertices, faces, wood)
    obj.data.materials.append(carved)
    uv = obj.data.uv_layers.new(name="UVMap").data
    for face, material in zip(obj.data.polygons, materials):
        face.material_index = material
        for index in face.loop_indices:
            x, y, z = obj.data.vertices[obj.data.loops[index].vertex_index].co
            across = y + .27 if abs(face.normal.z) > .2 else y + .27 + z - TOP
            uv[index].uv = (x / .90 + .24, across / .81 + .51)

    editable = bmesh.new()
    editable.from_mesh(obj.data)
    editable.normal_update()
    bmesh.ops.dissolve_limit(editable, angle_limit=.00005, use_dissolve_boundaries=False,
                            verts=list(editable.verts), edges=list(editable.edges), delimit={"MATERIAL", "UV"})
    editable.to_mesh(obj.data)
    editable.free()
    obj.data.update()
    assert sum(face.material_index == 1 for face in obj.data.polygons) >= 50
    return obj


def table():
    wood = timber()
    carved = surface("Fresh fibers in knife cuts", (0.13, 0.070, 0.036), .88)
    peg = surface("Oak end grain pegs", (0.22, 0.115, 0.049), .85)
    parts = [engraved_board(wood, carved)]
    for i, (length, center) in enumerate(((1.578,.006), (1.563,-.006), (1.571,.004)), start=1):
        plank = beam(f"Top plank {i+1}", (center, -0.27 + i * .18, TOP - .019),
                     (length, .177, .038), wood, edge=.0044, offset=.24+i*.267)
        parts.append(plank)
    for side in (-1, 1):
        parts.append(beam("Long apron", (0, side*.251, .686), (1.32, .038, .117), wood, offset=.61+side*.21))
        parts.append(beam("End apron", (side*.661, 0, .686), (.039, .45, .112), wood, offset=.46+side*.15))
        for front in (-1, 1):
            parts.append(rail("Splayed leg", (side*.698, front*.283, .028),
                              (side*.648, front*.234, .745), .068, .067, wood))
            parts.append(beam("Worn foot", (side*.697, front*.282, .019), (.066,.066,.038), wood))
        parts.append(beam("End stretcher", (side*.68, 0, .238), (.071, .53, .059), wood, offset=.29))
    parts.append(beam("Long stretcher", (0, 0, .238), (1.42, .062, .069), wood, offset=.16))
    for i, x in enumerate((-.66, .66)):
        for y in (-.27, -.089, .09, .27):
            parts.append(cylinder("Hand-cut oak peg", (x, y, TOP-.0012), .0059 + i*.0003, .0031, peg))
    return parts


def jug():
    clay = surface("Hand thrown stoneware", (.09, .14, .13), .57)
    glaze = surface("Glaze on the lip", (.071, .116, .106), .31)
    water = surface("Water inside jug", (.055, .092, .085), .17)
    count = 36
    profile = [(0,.056),(.006,.072),(.028,.087),(.082,.092),(.151,.087),(.181,.068),
               (.199,.043),(.231,.038),(.240,.044),(.248,.042),(.248,.034),(.231,.030),
               (.207,.031),(.19,.039),(.153,.065),(.072,.067),(.015,.045)]
    points = [(r*math.cos(j*math.tau/count), r*math.sin(j*math.tau/count), z)
              for z, r in profile for j in range(count)]
    faces = [(i*count+j,i*count+(j+1)%count,(i+1)*count+(j+1)%count,(i+1)*count+j)
             for i in range(len(profile)-1) for j in range(count)]
    faces += [tuple(reversed(range(count))), tuple(range(len(points)-count,len(points)))]
    body = mesh("Water jug", points, faces, clay)
    body.data.materials.append(glaze)
    for face in body.data.polygons:
        index = face.index // count
        face.use_smooth = face.index < len(faces)-2
        if 7 <= index <= 11:
            face.material_index = 1
    curve = bpy.data.curves.new("Rounded jug handle", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 5
    curve.bevel_depth = .012
    curve.bevel_resolution = 3
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(4)
    for knot, coord in zip(spline.bezier_points, [
        (.050,0,.206),(.103,0,.204),(.131,0,.167),(.115,0,.109),(.083,0,.102),
    ]):
        knot.co = coord
        knot.handle_left_type = knot.handle_right_type = "AUTO"
    handle = bpy.data.objects.new("Hand-shaped jug handle", curve)
    bpy.context.collection.objects.link(handle)
    curve.materials.append(clay)
    activate(handle)
    bpy.ops.object.convert(target="MESH")
    handle = bpy.context.object
    fill = cylinder("Quiet waterline", (0,0,.173), .052, .002, water, vertices=32)
    return [body, handle, fill]


def export(name, parts):
    activate(parts[0])
    for part in parts:
        part.select_set(True)
    # Keep the editable assembly in the .blend; the game gets one batched mesh.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    parts[0].name = parts[0].data.name = name
    bpy.ops.export_scene.gltf(filepath=str(PROPS / (name + ".glb")), export_format="GLB",
                              use_selection=True, export_materials="EXPORT",
                              export_cameras=False, export_lights=False, export_animations=False)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bench = table()
    pitcher = jug()
    for part in pitcher:
        part.location.x += 1.09
    activate(bench[0])
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "art/camp_table.blend"), compress=True)
    for part in pitcher:
        part.location.x -= 1.09
    export("camp_table", bench)
    export("camp_water_jug", pitcher)


if __name__ == "__main__":
    main()
