"""Build or re-export the trail pine in Blender. Units are meters."""
from dataclasses import dataclass
import hashlib
import json
from math import atan2, cos, exp, sin, tau
from pathlib import Path
import random
import struct
import sys
import tempfile
from urllib.request import urlopen

import bpy
from mathutils import Vector
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
PINES = ROOT / "coop" / "pines"
SOURCE = ROOT / "art" / "pine_tree_01_trail.blend"
GAME = PINES / "pine_mature_refined.glb"
SCENE = "Pine Tree 01 - Trail"
UP = Vector((0, 0, 1))
ROOTS = ((0.38, 0.67, 0.11), (1.65, 0.57, 0.095), (2.91, 0.81, 0.14),
         (3.96, 0.48, 0.084), (5.44, 0.74, 0.118))
MAPS = {
    "pine-bark.jpg": ("bark_diff", "7d3a558ed614c7e75594c7be3bf80311"),
    "pine-bark-nor.jpg": ("bark_nor_gl", "bb6e3a6eea777d992cef48fabfdc538c"),
    "pine-bark-rough.jpg": ("bark_rough", "1fb09885fde634d377e1d4f2a8960593"),
    "pine-bark-disp.jpg": ("bark_disp", "d7e015fc2042e8ced8697a72a959608a"),
}
WHITE = (1.0, 1.0, 1.0, 1.0)


def baseline():
    packed = (PINES / "pine_mature.glb").read_bytes()
    length = struct.unpack_from("<I", packed, 12)[0]
    model = json.loads(packed[20:20 + length])
    binary = memoryview(packed)[28 + length:]
    primitives = model["meshes"][0]["primitives"]

    def read(index):
        accessor = model["accessors"][index]
        view = model["bufferViews"][accessor["bufferView"]]
        start = view["byteOffset"]
        data = binary[start:start + view["byteLength"]]
        return np.frombuffer(data, {5126: "<f4", 5123: "<u2", 5121: "u1"}[accessor["componentType"]])

    def surface(primitive):
        attributes = primitive["attributes"]

        def xyz(name):
            points = read(attributes[name]).reshape(-1, 3)
            return np.column_stack((points[:, 0], -points[:, 2], points[:, 1]))

        uv = read(attributes["TEXCOORD_0"]).reshape(-1, 2).copy()
        uv[:, 1] = 1 - uv[:, 1]
        colors = read(attributes["COLOR_0"]).reshape(-1, 4) / 255
        return xyz("POSITION"), xyz("NORMAL"), uv, colors, read(primitive["indices"]).reshape(-1, 3)

    return surface(primitives[1]), surface(primitives[2])


@dataclass
class Level:
    collection: object
    parent: object
    index: int


class Geometry:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.uvs = []
        self.normals = []
        self.tints = []
        self.groups = {}

    def vertex(self, point, uv, normal=None, tint=WHITE):
        self.vertices.append(tuple(point))
        self.uvs.append(tuple(uv))
        self.normals.append(None if normal is None else tuple(normal))
        self.tints.append((tint, tint, tint, 1.0) if isinstance(tint, (float, np.floating)) else tint)

    def object(self, level, name, material):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        uv = mesh.uv_layers.new(name="UVMap")
        uv.data.foreach_set("uv", [value for loop in mesh.loops for value in self.uvs[loop.vertex_index]])
        for face in mesh.polygons:
            face.use_smooth = True
        if any(normal is not None for normal in self.normals):
            normals = [vertex.normal[:] if normal is None else normal
                       for vertex, normal in zip(mesh.vertices, self.normals)]
            mesh.normals_split_custom_set_from_vertices(normals)
        if any(tint != WHITE for tint in self.tints):
            colors = mesh.color_attributes.new(name="Surface color", type="FLOAT_COLOR", domain="POINT")
            colors.data.foreach_set("color", [value for tint in self.tints for value in tint])
        mesh.materials.append(material)
        obj = bpy.data.objects.new(name, mesh)
        level.collection.objects.link(obj)
        obj.parent = level.parent
        for name, indices in self.groups.items():
            obj.vertex_groups.new(name=name).add(list(indices), 1.0, "REPLACE")
        return obj

    def tube(self, path, radii, sides, seed, ground=False):
        """Emit a tapered bough or root with an editable ring topology."""
        start = len(self.vertices)
        length = 0.0
        for i, (point, radius) in enumerate(zip(path, radii)):
            axis = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
            helper = UP if abs(axis.z) < 0.94 else Vector((1, 0, 0))
            u = axis.cross(helper).normalized()
            v = axis.cross(u)
            if i:
                length += (point - path[i - 1]).length
            for side in range(sides + 1):
                angle = tau * side / sides
                wobble = 1 + 0.14 * cos(angle * 3 + seed + i * 0.38) + 0.08 * sin(angle * 5 + seed)
                offset = radius * wobble * (u * cos(angle) + v * sin(angle))
                offset.z *= 0.82 if ground else 1.0
                vertex = point + offset
                if ground:
                    vertex.z = max(0.0, vertex.z)
                uv = (0.11 + seed * 0.13 + side / sides, 0.15 + length * 1.26)
                self.vertex(vertex, uv, tint=wood_tint(vertex.z, angle, seed))
        for row in range(len(path) - 1):
            for side in range(sides):
                a = start + row * (sides + 1) + side
                b = a + sides + 1
                self.faces.append((a, a + 1, b + 1, b))
        end = start + (len(path) - 1) * (sides + 1)
        cap = len(self.vertices)
        end_tint = wood_tint(path[-1].z, seed, seed)
        self.vertex(path[-1], (0.52, 0.58), axis, end_tint)
        for side in range(sides):
            angle = tau * side / sides
            uv = (0.52 + 0.035 * cos(angle), 0.58 + 0.035 * sin(angle))
            self.vertex(self.vertices[end + side], uv, axis, end_tint)
        for side in range(sides):
            self.faces.append((cap, cap + 1 + side, cap + 1 + (side + 1) % sides))

    def card(self, points, uvs, tints, indices):
        start = len(self.vertices)
        rows = len(indices) // 2
        for index in indices:
            point = points[index]
            # A radial bias keeps neighboring sprays lit as a crown in the game.
            normal = Vector((point[0] * 0.46, point[1] * 0.46, 0.92)).normalized()
            self.vertex(point, uvs[index], normal, tints[index])
        for row in range(rows - 1):
            left = start + row * 2
            self.faces.append((left, left + 2, left + 3, left + 1))


def make_material(name, image, roughness, *, mask=False, normal=None, roughness_map=None):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = not mask
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    shader = nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = 0.0
    color = nodes.new("ShaderNodeTexImage")
    color.image = image
    color.label = "Poly Haven Pine Tree 01"
    color.location = (-480, 220)
    vertex_color = nodes.new("ShaderNodeVertexColor")
    vertex_color.layer_name = "Surface color"
    vertex_color.location = (-480, 470)
    tint = nodes.new("ShaderNodeMix")
    tint.data_type = "RGBA"
    tint.blend_type = "MULTIPLY"
    tint.inputs["Factor"].default_value = 1.0
    tint.location = (-220, 430)
    links.new(color.outputs["Color"], tint.inputs[6])
    links.new(vertex_color.outputs["Color"], tint.inputs[7])
    links.new(tint.outputs[2], shader.inputs["Base Color"])
    if mask:
        cutout = nodes.new("ShaderNodeMath")
        cutout.operation = "GREATER_THAN"
        cutout.inputs[1].default_value = 0.36
        cutout.location = (-220, 210)
        links.new(color.outputs["Alpha"], cutout.inputs[0])
        links.new(cutout.outputs[0], shader.inputs["Alpha"])
    if normal:
        relief = nodes.new("ShaderNodeTexImage")
        relief.image = normal
        relief.label = "Bark fissures"
        relief.location = (-480, -120)
        mapping = nodes.new("ShaderNodeNormalMap")
        mapping.inputs["Strength"].default_value = 0.87
        mapping.location = (-210, -130)
        links.new(relief.outputs["Color"], mapping.inputs["Color"])
        links.new(mapping.outputs["Normal"], shader.inputs["Normal"])
    if roughness_map:
        grain = nodes.new("ShaderNodeTexImage")
        grain.image = roughness_map
        grain.location = (-480, -420)
        channels = nodes.new("ShaderNodeSeparateColor")
        channels.location = (-215, -385)
        links.new(grain.outputs["Color"], channels.inputs["Color"])
        links.new(channels.outputs["Green"], shader.inputs["Roughness"])
    return material


def source_map(name):
    key, digest = MAPS[name]
    cache = ROOT / ".cache"
    cache.mkdir(exist_ok=True)
    path = cache / name
    if not path.exists():
        url = ("https://dl.polyhaven.org/file/ph-assets/Models/jpg/1k/pine_tree_01/"
               f"pine_tree_01_{key}_1k.jpg")
        with urlopen(url, timeout=30) as response:
            data = response.read()
        if hashlib.md5(data).hexdigest() != digest:
            raise ValueError(f"Unexpected Poly Haven image: {name}")
        path.write_bytes(data)
    if hashlib.md5(path.read_bytes()).hexdigest() != digest:
        raise ValueError(f"Unexpected Poly Haven image: {path}")
    return path


def packed_map(name, export_name, work, size, color_space):
    image = bpy.data.images.load(str(source_map(name)), check_existing=False)
    image.name = export_name
    image.colorspace_settings.name = color_space
    image.scale(size, size)
    image.filepath_raw = str(work / (export_name + ".jpg"))
    image.file_format = "JPEG"
    image.save(quality=88)
    image.pack()
    return image


def height_map():
    image = bpy.data.images.load(str(source_map("pine-bark-disp.jpg")), check_existing=False)
    image.colorspace_settings.name = "Non-Color"
    image.scale(128, 128)
    pixels = np.empty(128 * 128 * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return pixels.reshape(128, 128, 4)[..., 0]


def wood_tint(z, angle, seed):
    # The damp root collar picks up soil and lichen. Flecks follow broad grain.
    damp = max(0.0, 1.0 - z / 0.43)
    mottling = 0.94 + 0.048 * sin(angle * 3 + 2.2 * z + seed) + 0.018 * cos(angle * 7 + 4.2 * z)
    lichen = damp * max(0.0, sin(angle * 4 + z * 9 + seed)) ** 3
    return (mottling * (1 - 0.24 * damp - 0.09 * lichen),
            mottling * (1 - 0.19 * damp + 0.04 * lichen),
            mottling * (1 - 0.25 * damp - 0.07 * lichen), 1.0)


# Radius and root spread measured from the ground upward along the same stem.
STEM = (
    (0.0, .202, 1.00), (.023, .197, .92), (.050, .192, .80), (.084, .181, .65),
    (.138, .172, .52), (.204, .158, .37), (.301, .146, .24), (.430, .134, .13),
    (.595, .118, .06), (.795, .109, .015), (1.039, .103, 0.0), (1.290, .100, 0.0),
    (1.635, .091, 0.0), (2.010, .086, 0.0), (2.479, .073, 0.0), (2.890, .066, 0.0),
    (3.326, .055, 0.0), (3.822, .047, 0.0), (4.320, .041, 0.0), (4.774, .034, 0.0),
    (5.210, .028, 0.0), (5.71, .021, 0.0),
)
STEM_ROWS = (
    tuple(range(len(STEM))),
    (0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 21),
    (0, 4, 7, 10, 14, 18, 21),
)


def trunk_form(trunk, relief, material, level):
    stem = Geometry()
    sides = (44, 18, 9)[level.index]
    rows = STEM_ROWS[level.index]
    for index in rows:
        z, radius, spread = STEM[index]
        center = trunk_center(trunk, z)
        for side in range(sides + 1):
            angle = tau * side / sides
            basal = 0.0
            for i, (heading, length, width) in enumerate(ROOTS):
                axis = heading + 0.18 * spread * (-1) ** i
                difference = atan2(sin(angle - axis), cos(angle - axis))
                shoulder = 0.08 + width * 0.64 + (1 - spread) * 0.13
                basal += (length - STEM[0][1]) * spread * exp(-0.5 * (difference / shoulder) ** 2)
            u = 2 * side / sides + 0.04 * sin(z * 1.6)
            v = (z - 0.70 * basal) * 1.34
            rock = 1 + 0.075 * sin(angle * 3 - z * 1.47) + 0.039 * cos(angle * 7 + z * 2.26)
            displacement = 0.0
            if level.index == 0:
                sample = relief[int((v % 1.0) * 128), int((u % 1.0) * 128)]
                displacement = (float(sample) - 0.5) * 0.025 * max(0.36, 1 - z / 6.5)
            distance = radius * rock + basal + displacement
            point = (center.x + distance * cos(angle), center.y + distance * sin(angle), z)
            stem.vertex(point, (u, v), tint=wood_tint(z, angle, 1.3))
    for row in range(len(rows) - 1):
        for side in range(sides):
            a = row * (sides + 1) + side
            b = a + sides + 1
            stem.faces.append((a, a + 1, b + 1, b))
    obj = stem.object(level, "Stem and continuous root collar", material)
    normals = [vertex.normal.copy() for vertex in obj.data.vertices]
    for start in range(0, len(normals), sides + 1):
        end = start + sides
        normals[start] = normals[end] = (normals[start] + normals[end]).normalized()
    obj.data.normals_split_custom_set_from_vertices(normals)
    return obj


def trunk_center(positions, height):
    ring = positions[np.abs(positions[:, 2] - height) < 0.22]
    if len(ring) == 0:
        ring = positions[np.argsort(np.abs(positions[:, 2] - height))[:10]]
    return Vector((*np.median(ring[:, :2], axis=0), height))


def roots(geometry, trunk):
    center = trunk_center(trunk, 0.0)
    for i in (0, 2, 4):
        angle, length, width = ROOTS[i]
        outward = Vector((cos(angle), sin(angle), 0.0))
        sideways = UP.cross(outward) * (-1 if i == 2 else 1)
        points = [
            center + outward * (length * .34) + UP * .094,
            center + outward * (length * .56) + sideways * .063 + UP * .058,
            center + outward * (length * .74) + sideways * .168 + UP * .026,
            center + outward * (length * .83) + sideways * .25 + UP * .0035,
        ]
        geometry.tube(points, [width * .46, width * .36, width * .22, .0045], 8, i + .3, ground=True)


TIERS = (
    (2.43, (0.10, 1.68, 3.06, 4.77)),
    (2.96, (0.86, 2.28, 3.77, 5.68)),
    (3.62, (0.18, 1.61, 3.13, 4.94)),
    (4.29, (0.94, 2.45, 4.06, 5.54)),
    (5.05, (0.15, 2.06, 3.61, 5.19)),
    (5.60, (0.82, 2.68, 4.56)),
    (6.06, (0.16, 2.16, 4.35)),
)


def boughs(geometry, trunk, crown_centers, detail):
    rng = random.Random(1371)
    for tier, (height, angles) in enumerate(TIERS):
        for i, angle in enumerate(angles):
            direction = Vector((cos(angle), sin(angle), 0))
            sideways = UP.cross(direction)
            lift = rng.uniform(-0.12, 0.13)
            curl = rng.uniform(-0.24, 0.24)
            seed = rng.uniform(0.0, 3.0)
            center = trunk_center(trunk, height + lift) if height < 5.58 else Vector((0.0, 0.0, height + lift))
            aligned = crown_centers @ np.array(direction)
            off_axis = crown_centers @ np.array(sideways)
            score = aligned - 2.8 * np.abs(crown_centers[:, 2] - height) - 1.8 * np.abs(off_axis)
            tip = Vector(crown_centers[int(np.argmax(score))])
            spread = max(0.38, min(1.48, (tip - center).dot(direction)))
            base = center + direction * (0.016 if tier < 4 else 0.009)
            lower = center + direction * (spread * 0.42) - UP * (0.12 if tier < 3 else 0.065)
            upper = base.lerp(tip, 0.78) + sideways * curl * 0.6 - UP * 0.035
            end = base.lerp(tip, 0.97) + UP * 0.07
            radius = (0.061 - tier * 0.007) * (1.0 - i * 0.035)
            if detail < 2 and (detail == 0 or i != (tier + 1) % len(angles)):
                path = [base, lower, upper, end] if detail == 0 else [base, upper, end]
                radii = [radius, radius * 0.61, radius * 0.29, 0.008] if detail == 0 else [radius, radius * 0.32, 0.008]
                geometry.tube(path, radii, 6 if detail == 0 else 4, seed)
                if (detail == 0 and tier < 5) or (detail == 1 and tier < 3 and i % 2 == 0):
                    for side in ((-1, 1) if detail == 0 else (-1,)):
                        fork_end = upper + direction * 0.12 + sideways * (0.24 * side) + UP * 0.13
                        geometry.tube([lower, lower.lerp(fork_end, 0.55) - UP * 0.053, fork_end],
                                      [radius * 0.47, radius * 0.22, 0.005], 4, seed + side)
            elif detail == 2 and tier < 6 and i == tier % len(angles):
                geometry.tube([base, upper, end], [radius * .87, radius * .36, .007], 4, seed)

    leader = [trunk_center(trunk, 5.50), Vector((0.013, -0.013, 5.88)),
              Vector((-0.024, 0.012, 6.31)), Vector((0, 0, 6.80))]
    geometry.tube(leader, [0.034, 0.031, 0.023, 0.004], 6 if detail == 0 else 5,
                  0.3)


def trunk_knots(geometry, trunk):
    # Dead branch collars low enough to see along the path.
    for height, angle, size in ((1.16, 0.72, 0.056), (1.91, 3.22, 0.042), (0.79, 5.63, 0.045)):
        center = trunk_center(trunk, height)
        outward = Vector((cos(angle), sin(angle), 0))
        ring = trunk[np.abs(trunk[:, 2] - height) < 0.20]
        extent = float(np.quantile((ring - np.array(center)) @ np.array(outward), 0.85))
        collar = center + outward * extent
        geometry.tube([collar - outward * 0.037, collar + outward * 0.018,
                       collar + outward * (0.065 + size * 0.34) + UP * (size * 1.63),
                       collar + outward * (0.073 + size * 0.39) + UP * (size * 1.75)],
                      [size * 1.16, size, size * 0.57, size * 0.53], 9, height)


def cards_in_order(points):
    """Nest card selections by coverage, retaining the top and crown extremities."""
    centers = points.mean(axis=1)
    features = centers * [1.0, 1.0, 1.34]
    directions = np.array([(cos(x), sin(x)) for x in np.linspace(0.0, tau, 12, endpoint=False)])
    selected = [len(points) - 1, len(points) - 2, len(points) - 3]
    for heading in directions:
        selected.append(int(np.argmax((points[:, :, :2] @ heading).max(axis=1))))
    selected.extend([int(np.argmin(centers[:, 2])), int(np.argmax(centers[:, 2]))])
    selected = list(dict.fromkeys(selected))
    distance = ((features[:, None, :] - features[selected][None, :, :]) ** 2).sum(axis=2).min(axis=1)
    for _ in range(278 - len(selected)):
        farthest = int(distance.argmax())
        selected.append(farthest)
        distance = np.minimum(distance, ((features - features[farthest]) ** 2).sum(axis=1))
    return selected


def build_crown(level, source, selected, material):
    positions, _, uvs, colors, _ = source
    original = positions.reshape(-1, 6, 3)
    uvs = uvs.reshape(-1, 6, 2)
    colors = colors.reshape(-1, 6, 4)
    geometry = Geometry()
    for index in selected[:(278, 190, 102)[level.index]]:
        points = original[index].copy()
        rows = points.reshape(3, 2, 3)
        middle = rows.mean(axis=1, keepdims=True)
        # The least dense LOD broadens the individual sprays without growing the tree.
        width = (1.11, 1.27, 1.65)[level.index] if index < len(original) - 3 else 1.0
        rows[:] = middle + (rows - middle) * width
        tints = np.clip(colors[index, :, 1] * np.linspace(0.86, 1.04, 6), 0.0, 1.0)
        retain_bend = level.index == 0 or (level.index == 1 and middle[1, 0, 2] < 3.35)
        indices = (0, 1, 2, 3, 4, 5) if retain_bend else (0, 1, 4, 5)
        geometry.card(points, uvs[index], tints, indices)
    return geometry.object(level, ["Crown - bent needle sprays", "Crown - open whorls",
                                   "Crown - outer silhouette"][level.index], material)


def select_only(obj, others=()):
    bpy.ops.object.select_all(action="DESELECT")
    for selected in (obj, *others):
        selected.select_set(True)
    bpy.context.view_layer.objects.active = obj


def export(scene):
    level_collections = [scene.collection.children[f"LOD{index}"] for index in range(3)]
    layers = scene.view_layers[0].layer_collection.children
    excluded = [layers[collection.name].exclude for collection in level_collections]
    try:
        for collection in level_collections:
            layers[collection.name].exclude = False
        bpy.ops.export_scene.gltf(
            filepath=str(GAME), export_format="GLB", use_active_scene=True,
            export_animations=False, export_tangents=True, export_cameras=False,
            export_lights=False, export_all_vertex_colors=False,
            export_copyright="Pine Tree 01 by Rico Cilliers and Rob Tuytel, Poly Haven (CC0 1.0)",
        )
    finally:
        for collection, state in zip(level_collections, excluded):
            layers[collection.name].exclude = state


def build():
    original = bpy.context.window.scene
    scene = bpy.data.scenes.new(SCENE)
    bpy.context.window.scene = scene
    scene.unit_settings.system = "METRIC"
    scene["Source"] = "Pine Tree 01 | Rico Cilliers and Rob Tuytel | Poly Haven | CC0 1.0"
    scene["Editing"] = "LOD0 is visible by default. Toggle LOD collections in the View Layer."
    scene["Size"] = "7 m to leader tip. Base at Z=0 in Blender, Y=0 in Godot."
    try:
        source_trunk, source_foliage = baseline()
        positions = source_trunk[0]
        foliage = source_foliage[0].reshape(-1, 6, 3)
        centers = foliage.mean(axis=1)
        selected = cards_in_order(foliage)
        needle_image = bpy.data.images.load(str(PINES / "pine_needles.png"), check_existing=False)
        needle_image.pack()
        relief = height_map()
        with tempfile.TemporaryDirectory(prefix="cooper-pine-") as temp:
            work = Path(temp)
            bark = packed_map("pine-bark.jpg", "Pine bark color", work, 768, "sRGB")
            normal = packed_map("pine-bark-nor.jpg", "Pine bark normal", work, 512, "Non-Color")
            roughness = packed_map("pine-bark-rough.jpg", "Pine bark roughness", work, 256, "Non-Color")
        wood_near = make_material("Photographed pine bark", bark, 0.89, normal=normal, roughness_map=roughness)
        wood_distant = make_material("Pine bark", bark, 0.89)
        needles = make_material("Needle sprays", needle_image, 0.94, mask=True)

        levels = []
        for index in range(3):
            label = f"LOD{index}"
            collection = bpy.data.collections.new(label)
            scene.collection.children.link(collection)
            parent = bpy.data.objects.new(label, None)
            parent.empty_display_type = "PLAIN_AXES"
            parent.empty_display_size = 0.15
            collection.objects.link(parent)
            level = Level(collection, parent, index)
            levels.append(level)

            wood_material = wood_near if index == 0 else wood_distant
            trunk = trunk_form(positions, relief, wood_material, level)
            wood = Geometry()
            if index == 0:
                roots(wood, positions)
            root_end = len(wood.vertices)
            boughs(wood, positions, centers, index)
            if index == 0:
                bough_end = len(wood.vertices)
                trunk_knots(wood, positions)
                wood.groups = {"Surface roots": range(root_end), "Forked boughs": range(root_end, bough_end),
                               "Broken branch collars": range(bough_end, len(wood.vertices))}
            bough = wood.object(level, ["Root spurs, knots and forked boughs", "Primary boughs",
                                        "Leader"][index], wood_material)
            if index:
                select_only(trunk, [bough])
                bpy.ops.object.join()
                trunk.name = ["", "Wood - primary boughs", "Wood - stem and leader"][index]
            build_crown(level, source_foliage, selected, needles)

        export(scene)
        for level in levels[1:]:
            scene.view_layers[0].layer_collection.children[level.collection.name].exclude = True
        select_only(levels[0].parent)
        bpy.data.libraries.write(str(SOURCE), {scene}, compress=True)
    finally:
        bpy.context.window.scene = original
        for obj in list(scene.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        for collection in list(scene.collection.children):
            bpy.data.collections.remove(collection)
        bpy.data.scenes.remove(scene)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--export-only" in args:
        export(bpy.context.scene)
    else:
        build()
