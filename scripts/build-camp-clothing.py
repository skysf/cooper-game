"""Fit the supplied camp clothes to the hiker and export the game meshes."""

import math
from pathlib import Path
import runpy

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
PROPS = ROOT / "coop/props"
ITEMS = ("cap", "jacket", "pants")
TRIANGLE_BUDGETS = {"cap": 4500, "jacket": 52000, "pants": 7500}


def fit(point, item):
    x, y, z = point
    if item == "jacket":
        height = 0.85 + z * 1.13
        hood = max(0.0, height - 1.43)
        # Fold the crown behind the neck while keeping the throat opening rounded.
        fold = smooth(0.025, 0.23, hood)
        depth = y * 1.12
        forward = smooth(-0.058, 0.066, depth)
        folded_height = height - hood + 0.079 * (1.0 - math.exp(-hood / 0.079))
        folded_height += (0.023 - 0.033 * forward) * fold
        sleeve_end = smooth(0.18, 0.25, abs(x * 1.10)) * (1.0 - smooth(0.95, 1.15, height))
        return Vector((x * 1.10 * (1.0 - 0.13 * fold), depth * (1.0 - 0.27 * fold) - 0.033 * fold,
                       folded_height - 0.032 * sleeve_end))
    if item == "pants":
        return Vector((x * 1.09, y * 0.94, 0.89 + z * 0.83))
    return Vector((x * 1.30, y * 1.15 + 0.027, 1.65 + z))


def smooth(low, high, value):
    t = min(1.0, max(0.0, (value - low) / (high - low)))
    return t * t * (3.0 - 2.0 * t)


def jacket_detail_weight(point):
    x, depth, height = fit(point, "jacket")
    lateral = abs(x)
    shoulder = (smooth(0.114, 0.181, lateral) * smooth(1.175, 1.254, height)
                * (1.0 - smooth(1.414, 1.453, height)))
    elbow = (smooth(0.154, 0.213, lateral) * smooth(0.97, 1.027, height)
             * (1.0 - smooth(1.161, 1.232, height)))
    body = 0.28 * smooth(0.89, 0.96, height) * (1.0 - smooth(0.110, 0.17, lateral))
    zipper = 0.58 * (1.0 - smooth(0.018, 0.055, lateral)) * smooth(0.05, 0.09, depth)
    rim = 0.33 * smooth(1.46, 1.50, height)
    cuff = 0.34 * smooth(0.18, 0.245, lateral) * (1.0 - smooth(0.94, 1.00, height))
    return max(shoulder, elbow, body, zipper, rim, cuff)


def skin(obj, item):
    if item == "jacket":
        height, joint, tail, width, names = 1.35, 1.105, 0.90, 0.225, ("Arm", "Forearm")
    else:
        height, joint, tail, width, names = 0.87, 0.443, 0.13, 0.110, ("Leg", "Shin")
    armature = bpy.data.armatures.new("Camp " + item)
    rig = bpy.data.objects.new("Camp " + item + " rig", armature)
    bpy.context.collection.objects.link(rig)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    root = armature.edit_bones.new("Root")
    root.head, root.tail = (0, 0, 0), (0, 0, 0.2)
    for suffix, side in (("L", -1), ("R", 1)):
        upper = armature.edit_bones.new(names[0] + "_" + suffix)
        upper.head, upper.tail = (width * side, 0, height), (width * side, 0, joint)
        upper.parent = root
        lower = armature.edit_bones.new(names[1] + "_" + suffix)
        lower.head, lower.tail = upper.tail, (width * side, 0, tail)
        lower.parent = upper
        lower.use_connect = True
    bpy.ops.object.mode_set(mode="OBJECT")
    root_group = obj.vertex_groups.new(name="Root")
    limbs = [[obj.vertex_groups.new(name=name + "_" + suffix) for name in names] for suffix in ("L", "R")]
    if item == "jacket":
        weights_for = runpy.run_path(str(ROOT / "art/characters/locomotion/sleeve_weights.py"))["sleeve_weights"]
        weights = weights_for([(v.co.x, v.co.z, -v.co.y) for v in obj.data.vertices],
                              (edge.vertices for edge in obj.data.edges))
    for vertex in obj.data.vertices:
        x, _, z = vertex.co
        if item == "jacket":
            weight = weights[vertex.index]
        else:
            weight = 1.0 - smooth(0.64, 0.87, z)
        if weight > 0.0:
            upper, lower = limbs[int(x >= 0)]
            lower_weight = weight * (1.0 - smooth(joint - 0.06, joint + 0.055, z))
            if lower_weight < weight:
                upper.add([vertex.index], weight - lower_weight, "REPLACE")
            if lower_weight > 0.0:
                lower.add([vertex.index], lower_weight, "REPLACE")
        if weight < 1.0:
            root_group.add([vertex.index], 1.0 - weight, "REPLACE")
    obj.parent = rig
    modifier = obj.modifiers.new(name="Camp rig", type="ARMATURE")
    modifier.object = rig
    rig.select_set(True)


def ease_jacket_elbows(obj):
    # The midpoint matches the player's fitted forearm joint in the running rig.
    for vertex in obj.data.vertices:
        if not 0.995 < vertex.co.z < 1.22:
            continue
        side = "L" if vertex.co.x < 0 else "R"
        upper = obj.vertex_groups["Arm_" + side]
        lower = obj.vertex_groups["Forearm_" + side]
        weights = {group.group: group.weight for group in vertex.groups}
        arm = weights.get(upper.index, 0.0) + weights.get(lower.index, 0.0)
        if arm < 1e-6:
            continue
        lower_weight = arm * (1.0 - smooth(1.107 - 0.087, 1.107 + 0.087, vertex.co.z))
        if upper.index in weights:
            upper.remove([vertex.index])
        if lower.index in weights:
            lower.remove([vertex.index])
        if arm - lower_weight > 1e-6:
            upper.add([vertex.index], arm - lower_weight, "REPLACE")
        if lower_weight > 1e-6:
            lower.add([vertex.index], lower_weight, "REPLACE")


def reduce_mesh(obj, target, protect_jacket=False):
    obj.data.calc_loop_triangles()
    count = len(obj.data.loop_triangles)
    if count <= target:
        return
    simplify = obj.modifiers.new(name="Game mesh", type="DECIMATE")
    simplify.ratio = target / count
    group_name = "Temporary shoulder and elbow protection"
    if protect_jacket:
        protect = obj.vertex_groups.new(name=group_name)
        for vertex in obj.data.vertices:
            weight = 0.035 + 0.93 * jacket_detail_weight(obj.matrix_world @ vertex.co)
            protect.add([vertex.index], weight, "REPLACE")
        simplify.vertex_group = group_name
        simplify.invert_vertex_group = True
        simplify.vertex_group_factor = 3.0
    bpy.ops.object.modifier_apply(modifier=simplify.name)
    if protect_jacket:
        obj.vertex_groups.remove(obj.vertex_groups[group_name])


def export(item, directory=PROPS):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(ROOT / "art" / f"camp_{item}.blend")) as (source, target):
        target.objects = [f"Camp {item.title()}"]
    obj = next(obj for obj in target.objects if obj is not None)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.context.view_layer.update()
    if item == "jacket":
        # Reduce the authored surface before folding it. Welding the compressed
        # hood and sleeves merged close layers and damaged UVs and cloth folds.
        reduce_mesh(obj, TRIANGLE_BUDGETS[item], protect_jacket=True)
    matrix = obj.matrix_world.copy()
    for vertex in obj.data.vertices:
        vertex.co = fit(matrix @ vertex.co, item)
    obj.matrix_world = Matrix.Identity(4)
    obj.data.update()
    if item != "jacket":
        reduce_mesh(obj, TRIANGLE_BUDGETS[item])
    for image in bpy.data.images:
        edge = 1024 if item == "jacket" and image.colorspace_settings.name == "sRGB" else 512
        if image.packed_file is not None and max(image.size) > edge:
            scale = edge / max(image.size)
            image.scale(round(image.size[0] * scale), round(image.size[1] * scale))
    if item != "cap":
        skin(obj, item)
    if item == "jacket":
        ease_jacket_elbows(obj)
        bpy.context.scene.name = "Camp Jacket"
    bpy.ops.export_scene.gltf(filepath=str(directory / f"camp_{item}.glb"), export_format="GLB",
                              use_selection=True, export_animations=False)


if __name__ == "__main__":
    thumbnail = runpy.run_path(str(ROOT / "scripts/build-camp-backpack.py"))["thumbnail"]
    for item in ITEMS:
        export(item)
        thumbnail(PROPS / f"camp_{item}.glb", ROOT / "coop/textures" / f"inventory_{item}.png",
                  (0.75, 2.9, 0.75), f"Camp {item.title()}", 448 if item == "jacket" else 208)
