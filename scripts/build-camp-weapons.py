"""Export the assembled camp props and render their inventory thumbnails."""
from math import pi
from io import BytesIO
from hashlib import md5
import json
from pathlib import Path
import runpy
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "art/weapons/source"
MODELS = ROOT / "coop/weapons"
ICONS = ROOT / "coop/textures"
RIFLE = "bolt_action_rifle_7_62"
PISTOL = "service_pistol"


def export_weapon(path, key, source_name, objects, grip, orientation, sight=None):
    import bpy
    from mathutils import Matrix, Vector

    source = SOURCES / (source_name + "_4k.blend") / (source_name + "_4k.blend")
    bpy.ops.wm.open_mainfile(filepath=str(source))
    selected = [bpy.context.scene.objects[name] for name in objects]
    if key == "pistol":
        # The source lays out the filled magazine beside the first grip variant.
        bpy.context.scene.objects[PISTOL + "_magazine_loaded"].location.x = 0.0
    bpy.context.view_layer.update()

    root = bpy.data.objects.new(key.title(), None)
    bpy.context.collection.objects.link(root)
    transform = orientation @ Matrix.Translation(-Vector(grip))
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for item in selected:
        world = item.matrix_world.copy()
        item.parent = root
        item.matrix_world = transform @ world
        item.hide_set(False)
        item.select_set(True)

    if sight is not None:
        marker = bpy.data.objects.new("Sight", None)
        bpy.context.collection.objects.link(marker)
        marker.parent = root
        marker.location = transform @ Vector(sight)
        marker.select_set(True)

    materials = {slot.material for item in selected for slot in item.material_slots}
    for material in materials:
        for node in material.node_tree.nodes:
            if node.type != "TEX_IMAGE":
                continue
            image = node.image
            # Scalar maps carry broad surface variation. Keep the full 4K color and normals.
            if image.size[0] > 2048 and any(channel in image.name for channel in ("_rough", "_metal")):
                image.scale(2048, 2048)

    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True,
        export_apply=True, export_animations=False, export_tangents=True,
        export_copyright="Poly Haven / CC0 1.0",
    )


def texture_import(path, normal):
    """Use Godot's mipmapped Basis import with RDO for the 4K textures."""
    resource = "res://" + path.resolve().relative_to(ROOT / "coop").as_posix()
    imported = "res://.godot/imported/" + path.name + "-" + md5(resource.encode()).hexdigest() + ".ctex"
    settings = path.with_name(path.name + ".import")
    if settings.exists():
        return
    settings.write_text(f"""[remap]

importer="texture"
type="CompressedTexture2D"
path="{imported}"

[deps]

source_file="{resource}"
dest_files=["{imported}"]

[params]

compress/mode=4
compress/normal_map={1 if normal else 0}
compress/uastc_level=1
compress/rdo_quality_loss={0.65 if normal else 0.45}
mipmaps/generate=true
detect_3d/compress_to=0
""")


def compress_model(source, target):
    """Keep 4K color and normal data in textures Godot can compress separately."""
    from PIL import Image

    def align(data):
        data.extend(b"\0" * (-len(data) % 4))

    with source.open("rb") as stream:
        stream.seek(12)
        json_size, _ = struct.unpack("<II", stream.read(8))
        gltf = json.loads(stream.read(json_size))
        stream.read(8)
        bin_start = stream.tell()
        colors, normals = {}, set()
        for material in gltf["materials"]:
            index = material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
            colors[gltf["textures"][index]["source"]] = material.get("alphaMode") == "BLEND"
            normals.add(gltf["textures"][material["normalTexture"]["index"]]["source"])
        images = {info["bufferView"]: i for i, info in enumerate(gltf["images"])}
        maps = target.parent / "maps"
        maps.mkdir(exist_ok=True)
        webp = set()
        binary = bytearray()
        buffer_views = []
        view_indices = {}
        for i, view in enumerate(gltf["bufferViews"]):
            stream.seek(bin_start + view.get("byteOffset", 0))
            payload = stream.read(view["byteLength"])
            if i in images:
                index = images[i]
                info = gltf["images"][index]
                if index not in colors or colors[index] or len(payload) > 2 * 1024 * 1024:
                    with Image.open(BytesIO(payload)) as raw:
                        output = BytesIO()
                        if index in colors and not colors[index]:
                            raw.convert("RGB").save(output, "JPEG", quality=95, subsampling=0, optimize=True)
                            info["mimeType"] = "image/jpeg"
                        else:
                            image = raw.convert("RGBA" if colors.get(index) else "RGB")
                            if colors.get(index):
                                image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
                            image.save(output, "WEBP", lossless=True, method=4, exact=True)
                            info["mimeType"] = "image/webp"
                            webp.add(index)
                        payload = output.getvalue()
                suffix = ".webp" if index in webp else ".jpg"
                path = maps / (info["name"] + suffix)
                if path.suffix == ".jpg" and info["mimeType"] != "image/jpeg":
                    raise ValueError(f"Unexpected opaque texture format for {path.name}")
                path.write_bytes(payload)
                texture_import(path, index in normals)
                info["uri"] = path.relative_to(target.parent).as_posix()
                del info["bufferView"]
                continue
            align(binary)
            view["byteOffset"] = len(binary)
            view_indices[i] = len(buffer_views)
            buffer_views.append(view)
            binary.extend(payload)
        align(binary)

    for texture in gltf["textures"]:
        if texture["source"] in webp:
            texture.setdefault("extensions", {})["EXT_texture_webp"] = {"source": texture.pop("source")}
    for key in ("extensionsUsed", "extensionsRequired"):
        gltf.setdefault(key, []).append("EXT_texture_webp")
    gltf["bufferViews"] = buffer_views
    for accessor in gltf["accessors"]:
        accessor["bufferView"] = view_indices[accessor["bufferView"]]
    gltf["buffers"][0]["byteLength"] = len(binary)
    json_chunk = json.dumps(gltf, separators=(",", ":")).encode()
    json_chunk += b" " * (-len(json_chunk) % 4)
    with target.open("wb") as stream:
        stream.write(struct.pack("<4sII", b"glTF", 2, 28 + len(json_chunk) + len(binary)))
        stream.write(struct.pack("<I4s", len(json_chunk), b"JSON") + json_chunk)
        stream.write(struct.pack("<I4s", len(binary), b"BIN\0"))
        stream.write(binary)


def main():
    from mathutils import Matrix

    MODELS.mkdir(parents=True, exist_ok=True)
    upright = Matrix.Rotation(pi / 2, 4, "Z")
    models = {
        "katana": ("antique_katana_01", ["antique_katana_01"],
                   (0, 0, -0.16), Matrix.Rotation(-pi / 2, 4, "X")),
        "rifle": (RIFLE, [RIFLE] + [
            RIFLE + "_" + part for part in ("scope", "wrap", "bolt_a", "bolt_b", "trigger")
        ], (-0.34, 0, -0.034), upright, (-0.260, 0.007, 0.070)),
        "pistol": (PISTOL, [
            PISTOL + "_" + part for part in ("pistol_a", "slide_a", "hammer_a", "trigger_a", "magazine_loaded")
        ], (0.002, 0, 0.007), upright, (-0.030, 0, 0.081)),
    }
    render_icon = runpy.run_path(str(ROOT / "scripts/build-camp-backpack.py"))["thumbnail"]
    crop_icon = """
from PIL import Image
import sys
image = Image.open(sys.argv[1]).convert("RGBA")
image = image.rotate(float(sys.argv[3]), Image.Resampling.BICUBIC, expand=True)
image = image.crop(image.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox())
image.thumbnail((230, 230), Image.Resampling.LANCZOS)
icon = Image.new("RGBA", (256, 256))
icon.alpha_composite(image, ((256 - image.width) // 2, (256 - image.height) // 2))
icon.save(sys.argv[2], optimize=True)
"""
    with tempfile.TemporaryDirectory(prefix="camp-weapons-") as temp:
        for key, assembly in models.items():
            source = Path(temp) / (key + ".glb")
            export_weapon(source, key, *assembly)
            raw = Path(temp) / (key + ".png")
            render_icon(source, raw, (2.8, 0.4, 0.8), size_px=420)
            subprocess.run([
                "python3", "-c", crop_icon, str(raw),
                str(ICONS / ("inventory_" + key + ".png")), "26",
            ], check=True)
            subprocess.run([
                "python3", __file__, "--compress", str(source), str(MODELS / (key + ".glb"))
            ], check=True)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--compress":
        compress_model(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        main()
