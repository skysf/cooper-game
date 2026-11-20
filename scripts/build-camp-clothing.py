"""Fit the supplied camp clothes to the hiker and export the game meshes."""

import math
from pathlib import Path
import runpy

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
PROPS = ROOT / "coop/props"
ITEMS = ("cap", "jacket", "pants")
TRIANGLE_BUDGETS = {"cap": 4500, "jacket": 14500, "pants": 7500}


def fit(point, item):
    x, y, z = point
    if item == "jacket":
        height = 0.85 + z * 1.13
        hood = max(0.0, height - 1.43)
        # Let the hood rest behind the neck when the face and glasses are visible.
        folded_height = height - hood + 0.10 * (1.0 - math.exp(-hood / 0.10))
        sleeve_end = smooth(0.18, 0.25, abs(x * 1.10)) * (1.0 - smooth(0.95, 1.15, height))
        return Vector((x * 1.10, y * 1.12 - 0.25 * hood, folded_height - 0.032 * sleeve_end))
    if item == "pants":
        return Vector((x * 1.09, y * 0.94, 0.89 + z * 0.83))
    return Vector((x * 1.30, y * 1.15 + 0.027, 1.65 + z))


def smooth(low, high, value):
    t = min(1.0, max(0.0, (value - low) / (high - low)))
    return t * t * (3.0 - 2.0 * t)


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


def export(item):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(ROOT / "art" / f"camp_{item}.blend")) as (source, target):
        target.objects = [f"Camp {item.title()}"]
    obj = next(obj for obj in target.objects if obj is not None)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.update()
    matrix = obj.matrix_world.copy()
    for vertex in obj.data.vertices:
        vertex.co = fit(matrix @ vertex.co, item)
    obj.matrix_world = Matrix.Identity(4)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if item == "jacket":
        obj.data.validate(clean_customdata=False)
        welded = bmesh.new()
        welded.from_mesh(obj.data)
        bmesh.ops.remove_doubles(welded, verts=list(welded.verts), dist=0.00020)
        welded.to_mesh(obj.data)
        welded.free()
        if obj.data.has_custom_normals:
            bpy.ops.mesh.customdata_custom_splitnormals_clear()
        for face in obj.data.polygons:
            face.use_smooth = True
    obj.data.calc_loop_triangles()
    triangles = len(obj.data.loop_triangles)
    if triangles > TRIANGLE_BUDGETS[item]:
        simplify = obj.modifiers.new(name="Game mesh", type="DECIMATE")
        simplify.ratio = TRIANGLE_BUDGETS[item] / triangles
        bpy.ops.object.modifier_apply(modifier=simplify.name)
    if item == "jacket":
        obj.data.validate(clean_customdata=False)
    for image in bpy.data.images:
        if image.packed_file is not None and max(image.size) > 512:
            image.scale(512, round(image.size[1] * 512 / image.size[0]))
    if item != "cap":
        skin(obj, item)
    bpy.ops.export_scene.gltf(filepath=str(PROPS / f"camp_{item}.glb"), export_format="GLB",
                              use_selection=True, export_animations=False)


if __name__ == "__main__":
    thumbnail = runpy.run_path(str(ROOT / "scripts/build-camp-backpack.py"))["thumbnail"]
    for item in ITEMS:
        export(item)
        thumbnail(PROPS / f"camp_{item}.glb", ROOT / "coop/textures" / f"inventory_{item}.png",
                  (0.75, 2.9, 0.75), f"Camp {item.title()}", 208)
