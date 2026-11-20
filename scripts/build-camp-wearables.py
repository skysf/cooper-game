"""Fit the supplied two-boot and plumed-helmet GLBs without changing their topology."""

from pathlib import Path
import runpy
import sys

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art/clothing/source/Character_Clothes"
SUFFIX = "_3D_fal-ai:hyper3d:rodin:v2.5:fast.glb"


def import_mesh(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    obj, = (obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def fit_boots(source):
    # There are two complete boots separated by the middle of the source scene.
    # Split on that gap so UVs, stitching, treads and both left/right shapes survive.
    bpy.context.tool_settings.mesh_select_mode = (True, False, False)
    for polygon in source.data.polygons:
        polygon.select = False
    for edge in source.data.edges:
        edge.select = False
    for vertex in source.data.vertices:
        vertex.select = vertex.co.x > 0.0
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    sizes = {}
    for obj in bpy.context.scene.objects:
        vertices = obj.data.vertices
        center_x = (min(v.co.x for v in vertices) + max(v.co.x for v in vertices)) / 2.0
        floor = min(v.co.z for v in vertices)
        name = "Left" if center_x > 0 else "Right"
        obj.name = "Boot" + name
        obj.data.name = name + " hiking boot"
        # Blender +Y will be Godot -Z. The local origin is below the ankle.
        pose = Matrix.Translation(Vector((center_x*.162, .055, -.15*floor))) @ Matrix.Diagonal((-.162,-.15,.15,1))
        obj.data.transform(pose)
        obj.location.x = -.14 if name == "Left" else .14
        obj.data.calc_loop_triangles()
        sizes[obj.name] = len(obj.data.loop_triangles)
        obj.select_set(True)
    assert set(sizes) == {"BootLeft", "BootRight"}
    return sizes


def fit_helmet(obj):
    obj.name = "CampHelmet"
    obj.data.name = "Plumed helmet"
    # Keep the closed visor centred around the eye line, and the gorget above the jacket.
    obj.data.transform(Matrix.Translation(Vector((0.0, -.003, .010))) @ Matrix.Diagonal((-.249,-.225,.231,1)))
    for material in obj.data.materials:
        for node in material.node_tree.nodes:
            if node.type != "TEX_IMAGE" or not node.image:
                continue
            image = node.image
            if max(image.size) > 2048:
                scale = 2048 / max(image.size)
                image.scale(round(image.size[0] * scale), round(image.size[1] * scale))
            image.pack()
    obj.data.calc_loop_triangles()
    return {obj.name: len(obj.data.loop_triangles)}


def fit_materials(item):
    # The supplied GLBs store the photographed surface as emission. Keep that
    # texture in the base color so the boots and helmet reflect camp lighting.
    materials = {material for obj in bpy.context.scene.objects for material in obj.data.materials}
    for material in materials:
        nodes = material.node_tree.nodes
        image_node = next(node for node in nodes if node.type == "TEX_IMAGE" and node.image)
        image = image_node.image
        nodes.clear()
        color = nodes.new("ShaderNodeTexImage")
        color.image = image
        color.location = (-310, 80)
        finish = nodes.new("ShaderNodeBsdfPrincipled")
        finish.inputs["Roughness"].default_value = 0.82 if item == "boot" else 0.55
        finish.inputs["Metallic"].default_value = 0.0 if item == "boot" else 0.20
        output = nodes.new("ShaderNodeOutputMaterial")
        output.location = (310, 80)
        material.node_tree.links.new(color.outputs["Color"], finish.inputs["Base Color"])
        material.node_tree.links.new(finish.outputs["BSDF"], output.inputs["Surface"])


def export(item, source_dir, blend, model):
    source = "boots" if item == "boot" else "helmets"
    mesh = import_mesh(source_dir / (source+SUFFIX))
    triangles = fit_boots(mesh) if item == "boot" else fit_helmet(mesh)
    fit_materials(item)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
    bpy.ops.export_scene.gltf(filepath=str(model), export_format="GLB", use_selection=True,
                             export_image_format="JPEG", export_jpeg_quality=94, export_animations=False)
    return triangles


if __name__ == "__main__":
    thumbnail = runpy.run_path(str(ROOT/"scripts/build-camp-backpack.py"))["thumbnail"]
    for item in ("boot", "helmet"):
        model = ROOT/"coop/props"/f"camp_{item}.glb"
        export(item, SOURCE, ROOT/"art"/f"camp_{item}.blend", model)
        if item == "helmet":
            thumbnail(model, ROOT/"coop/textures"/"inventory_helmet.png", (1.32,2.9,.53), size_px=384)
