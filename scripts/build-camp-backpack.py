"""Export the supplied backpack and render inventory thumbnails from the game props."""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
PROPS = ROOT / "coop/props"
ICONS = ROOT / "coop/textures"


def export_backpack():
    backpack = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    for image in bpy.data.images:
        if image.packed_file is not None and max(image.size) > 512:
            image.scale(512, 512)
    bpy.ops.object.select_all(action="DESELECT")
    backpack.select_set(True)
    bpy.context.view_layer.objects.active = backpack
    bpy.ops.export_scene.gltf(
        filepath=str(PROPS / "camp_backpack.glb"),
        export_format="GLB",
        use_selection=True,
        export_animations=False,
    )


def thumbnail(source, output, angle, model_name=None, size_px=144):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=str(source))
    corners = [obj.matrix_world @ Vector(point)
               for obj in scene.objects if obj.type == "MESH" and not obj.hide_render
               and (model_name is None or obj.name == model_name)
               for point in obj.bound_box]
    lo = Vector([min(p[axis] for p in corners) for axis in range(3)])
    hi = Vector([max(p[axis] for p in corners) for axis in range(3)])
    center = (lo + hi) * 0.5
    span = max(hi - lo)
    bpy.ops.object.camera_add(location=center + Vector(angle) * span)
    camera = bpy.context.object
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = span * 1.43
    camera.data.clip_start = 0.001
    scene.camera = camera
    for location, strength, size in [((-.9, -1.3, 2.0), 24, 2), ((1.5, -0.2, 1.1), 9, 2), ((0, 1.3, .9), 12, 1.4)]:
        bpy.ops.object.light_add(type="AREA", location=center + Vector(location) * span)
        light = bpy.context.object
        light.rotation_euler = (center - light.location).to_track_quat("-Z", "Y").to_euler()
        light.data.energy = strength * span ** 2
        light.data.shape = "DISK"
        light.data.size = size * span
    scene.world = bpy.data.worlds.new("Inventory ambient")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (.28, .28, .28, 1)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 20
    scene.cycles.use_denoising = True
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 2
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = size_px
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    export_backpack()
    thumbnail(PROPS / "food_apple.glb", ICONS / "inventory_apple.png", (1.3, -2.7, 1.6))
    thumbnail(PROPS / "food_bread.glb", ICONS / "inventory_bread.png", (1.4, -2.9, 1.7))
    thumbnail(PROPS / "camp_backpack.glb", ICONS / "inventory_backpack.png", (0.9, -3.0, 0.8))
