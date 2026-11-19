"""Export Poly Haven's Grass Medium 01 LOD2 meshes and a compact color atlas."""

from pathlib import Path

import bpy
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "coop/vegetation"
SOURCE = Path(bpy.data.filepath).parent
TEXTURE_SIZE = 1024
VARIANTS = {
    "GrassShort": "tiny_e",
    "GrassTuft": "tiny_a",
    "GrassClump": "mid_b",
}


def pixels(filename, colorspace):
    image = bpy.data.images.load(str(SOURCE / "textures" / filename), check_existing=False)
    image.colorspace_settings.name = colorspace
    image.scale(TEXTURE_SIZE, TEXTURE_SIZE)
    rgba = np.empty((TEXTURE_SIZE, TEXTURE_SIZE, 4), dtype=np.float32)
    image.pixels.foreach_get(rgba.ravel())
    return rgba


def write_atlas():
    alpha = pixels("grass_medium_01_alpha_4k.png", "Non-Color")[:, :, 0]
    fresh = pixels("grass_medium_01_diff_4k.jpg", "sRGB")
    dry = pixels("grass_medium_01_dry_diff_4k.png", "sRGB")
    dry[:, :, :3] = fresh[:, :, :3] * 0.42 + dry[:, :, :3] * 0.58
    fresh[:, :, 3] = dry[:, :, 3] = alpha
    atlas = bpy.data.images.new("Grass color and alpha", TEXTURE_SIZE * 2, TEXTURE_SIZE, alpha=True)
    atlas.pixels.foreach_set(np.concatenate((fresh, dry), axis=1).ravel())
    atlas.file_format = "PNG"
    atlas.save(filepath=str(OUT / "grass_medium_01.png"))


def export_meshes():
    bpy.ops.object.select_all(action="DESELECT")
    for name, variant in VARIANTS.items():
        source = bpy.data.objects[f"grass_medium_01_{variant}_LOD2"]
        mesh = source.data.copy()
        mesh.materials.clear()
        lowest = min(vertex.co.z for vertex in mesh.vertices)
        for vertex in mesh.vertices:
            vertex.co.z -= lowest
        tuft = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(tuft)
        tuft.select_set(True)
        if name == "GrassClump":
            bpy.context.view_layer.objects.active = tuft
            simplify = tuft.modifiers.new(name="Runtime triangle budget", type="DECIMATE")
            simplify.ratio = 0.64
            bpy.ops.object.modifier_apply(modifier=simplify.name)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / "grass_medium_01.glb"),
        export_format="GLB",
        use_selection=True,
        export_materials="NONE",
        export_animations=False,
    )


OUT.mkdir(parents=True, exist_ok=True)
write_atlas()
export_meshes()
