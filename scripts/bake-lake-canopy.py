"""Bake the four far-bank views from the same GLBs planted along the forest trail.

Run with python3 scripts/bake-lake-canopy.py. Blender renders each silhouette on
the CPU in an isolated background process. Pillow packs the views in reading order.
"""
from pathlib import Path
import math
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
# Orthographic width / height is restored on each card in lake.gd.
VIEWS = (
    ("pines/pine_mature.glb", 32, 0.55),
    ("trees/spruce_mature.glb", 117, 0.61),
    ("trees/birch_mature.glb", 68, 0.88),
    ("pines/pine_mature.glb", 164, 0.55),
)


def render(directory):
    import bpy
    from mathutils import Vector

    assert bpy.app.background
    scene = bpy.context.scene
    for obj in list(scene.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 12
    scene.cycles.transparent_max_bounces = 12
    scene.cycles.use_denoising = False
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 2
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'Standard'
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get('Background')
    background.inputs['Color'].default_value = (0.85, 0.93, 1.0, 1.0)
    background.inputs['Strength'].default_value = 1.05
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 7.38
    scene.camera = camera
    bpy.ops.object.light_add(type='SUN')
    key = bpy.context.object
    key.data.energy = 2.5
    key.data.angle = math.radians(13)
    key.data.color = (1.0, 0.92, 0.79)
    for i, (asset, angle, width) in enumerate(VIEWS):
        keep = set(scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(ROOT / 'coop' / asset))
        azimuth = math.radians(angle)
        facing = Vector((math.cos(azimuth), math.sin(azimuth), 0.0))
        right = Vector((-facing.y, facing.x, 0.0))
        focus = Vector((0.0, 0.0, 3.54))
        camera.location = focus + facing * 17.0 + Vector((0, 0, 0.48))
        camera.rotation_euler = (focus - camera.location).to_track_quat('-Z', 'Y').to_euler()
        light_direction = facing * 0.55 + right * 0.70 + Vector((0, 0, 0.95))
        key.rotation_euler = (-light_direction).to_track_quat('-Z', 'Y').to_euler()
        scene.render.resolution_x = round(448 * width)
        scene.render.resolution_y = 448
        scene.render.filepath = str(directory / (str(i) + '.png'))
        bpy.ops.render.render(write_still=True)
        for obj in set(scene.objects) - keep:
            bpy.data.objects.remove(obj, do_unlink=True)


def bake():
    from PIL import Image

    with tempfile.TemporaryDirectory(prefix='cooper-lake-canopy-') as tmp:
        directory = Path(tmp)
        subprocess.run([str(ROOT / 'scripts/start-blender.sh'), '--background', '--factory-startup',
                        '--python-exit-code', '1', '--python', str(Path(__file__).resolve()),
                        '--', str(directory)], check=True)
        atlas = Image.new('RGBA', (512, 512))
        for i in range(len(VIEWS)):
            with Image.open(directory / (str(i) + '.png')) as view:
                tile = view.convert('RGBA').resize((256, 256), Image.Resampling.LANCZOS)
                atlas.paste(tile, ((i % 2) * 256, (i // 2) * 256))
        atlas.save(ROOT / 'coop/textures/lake_canopy.png', optimize=True)


if __name__ == '__main__':
    if '--' in sys.argv:
        render(Path(sys.argv[sys.argv.index('--') + 1]))
    else:
        bake()
