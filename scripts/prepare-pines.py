"""Prepare the Godot growth models from Poly Haven's Pine Tree 01.

Run with Python 3, NumPy, Pillow, and Godot 4.7.2. Pass --fetch if the
official source slices and maps are not already in the project cache.
"""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
from urllib.request import Request, urlopen

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache"
OUTPUT = ROOT / "coop" / "pines"
PH = "https://dl.polyhaven.org/file/ph-assets/Models"
MODEL = f"{PH}/gltf/1k/pine_tree_01"
MODEL_BUFFER = f"{PH}/gltf/8k/pine_tree_01/pine_tree_01.bin"
MAPS = f"{PH}/jpg/1k/pine_tree_01"
WOOD_RANGE = (383935936, 386644027)
WOOD_SHA256 = "342102498102270959613dbd48346bd9cf5b947cbe45aa9d77c33e19431ebbd0"
MAP_SOURCES = {
    "pine-bark.jpg": ("bark_diff", "7d3a558ed614c7e75594c7be3bf80311"),
    "pine-trunk-b.jpg": ("trunk_b_diff", "00ad0c0643a4e6b34914b8ac05cc28cb"),
    "pine-twig.jpg": ("twig_diff", "b6e5f4e8c228c275e5ff75cb165c2e1f"),
    "pine-twig-alpha.jpg": ("twig_alpha", "e9a69633f4c1d9b8a460c3f05fc8d75e"),
}
HEIGHTS = {"sapling": 0.65, "young": 2.4, "mature": 7.0}
UP = np.array([0.0, 1.0, 0.0])


def fetch_file(name, url, first=None, last=None):
    path = CACHE / name
    if path.exists():
        return
    headers = {"User-Agent": "CooperGame-PineAsset/1.0"}
    if first is not None:
        headers["Range"] = f"bytes={first}-{last}"
    with urlopen(Request(url, headers=headers), timeout=45) as response:
        if first is not None:
            reported = response.headers.get("Content-Range", "")
            if response.status != 206 or not reported.startswith(f"bytes {first}-{last}/"):
                raise ValueError(f"Unexpected Poly Haven range response: {reported}")
        data = response.read()
    path.write_bytes(data)


def make_source_wood():
    source = json.loads((CACHE / "pine-model-index.json").read_text())
    wood = source["meshes"][1]["primitives"][:2]
    assert source["nodes"][1]["name"] == "pine_tree_01_b_LOD0"
    first, last = WOOD_RANGE
    data = (CACHE / "pine-B-trunk.range").read_bytes()
    if len(data) != last - first + 1 or hashlib.sha256(data).hexdigest() != WOOD_SHA256:
        raise ValueError("Poly Haven wood slice checksum mismatch")
    original = source["bufferViews"][24:36]
    for view in original:
        view["byteOffset"] -= first
    accessors = source["accessors"][24:36]
    for accessor in accessors:
        accessor["bufferView"] -= 24
    primitives = [
        {
            "attributes": {
                semantic: index - 24
                for semantic, index in primitive["attributes"].items()
                if semantic in {"POSITION", "NORMAL", "TEXCOORD_0"}
            },
            "indices": primitive["indices"] - 24,
        }
        for primitive in wood
    ]
    model = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": primitives}],
        "bufferViews": original,
        "accessors": accessors,
        "buffers": [{"byteLength": len(data)}],
    }
    positions = np.frombuffer(data, "<f4", count=accessors[0]["count"] * 3).reshape(-1, 3)
    faces = np.frombuffer(data, "<u2", offset=original[5]["byteOffset"],
                          count=accessors[5]["count"]).reshape(-1, 3)
    return model, data, positions, faces


def reduced_wood(model, data, godot):
    with tempfile.TemporaryDirectory(prefix="cooper-pine-") as directory:
        work = Path(directory)
        (work / "project.godot").write_text(
            'config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        )
        (work / "source.glb").write_bytes(glb(model, data))
        shutil.copyfile(ROOT / "scripts" / "reduce-pine-wood.gd", work / "reduce.gd")
        result = subprocess.run(
            [godot, "--headless", "--path", str(work), "--log-file", str(work / "engine.log"),
             "--script", str(work / "reduce.gd")],
            capture_output=True, text=True, check=True, timeout=45,
        )
        path = work / "wood-lods.bin"
        if not path.is_file():
            raise RuntimeError(result.stdout + result.stderr)
        packed = path.read_bytes()

    offset = 0
    meshes = {"mature": [], "young": []}
    for i in range(2):
        count = struct.unpack_from("<I", packed, offset)[0]
        offset += 4
        positions = np.frombuffer(packed, "<f4", count * 3, offset).reshape(-1, 3)
        offset += count * 12
        normals = np.frombuffer(packed, "<f4", count * 3, offset).reshape(-1, 3)
        offset += count * 12
        uvs = np.frombuffer(packed, "<f4", count * 2, offset).reshape(-1, 2)
        offset += count * 8
        if i == 0:
            # Bake the source bark material's KHR_texture_transform.
            uvs = uvs * (1.2, 0.1) + (0.0, 0.9)
        for stage in meshes:
            index_count = struct.unpack_from("<I", packed, offset)[0]
            offset += 4
            indices = np.frombuffer(packed, "<u4", index_count, offset)
            offset += index_count * 4
            used, compact_faces = np.unique(indices, return_inverse=True)
            meshes[stage].append((positions[used], normals[used], uvs[used], compact_faces))
    assert offset == len(packed)
    return meshes


def branch_tips(positions, faces):
    # Weld UV seams before finding the original branch tubes.
    _, welded = np.unique(np.round(positions, 5), axis=0, return_inverse=True)
    parents = list(range(len(positions)))

    def root(i):
        while i != parents[i]:
            i, parents[i] = parents[i], parents[parents[i]]
        return i

    for a, b, c in welded[faces]:
        branch = root(a)
        parents[root(b)] = parents[root(c)] = branch
    labels = np.array([root(i) for i in welded])
    result = []
    for label in np.unique(labels):
        points = positions[labels == label]
        radial = np.linalg.norm(points[:, (0, 2)], axis=1)
        result.append((points[radial.argmin()], points[radial.argmax()]))
    return result


def foliage_atlas():
    source = Image.open(CACHE / "pine-twig.jpg").convert("RGB")
    alpha = Image.open(CACHE / "pine-twig-alpha.jpg").convert("L")
    # Isolate the two photographed needle sprays within the original UV sheet.
    crops = (
        ((24, 34, 229, 456), [(0, 38), (25, 2), (140, 0), (202, 65),
          (194, 215), (157, 302), (132, 344), (122, 422), (106, 422), (107, 344),
          (76, 315), (27, 263), (0, 205)], True, (8, 8, 496, 116)),
        ((650, 326, 988, 539), [(2, 162), (33, 114), (116, 44), (221, 12),
          (291, 2), (330, 98), (335, 158), (290, 207), (170, 210), (74, 179)],
         False, (8, 132, 496, 116)),
    )
    atlas = Image.new("RGBA", (512, 256), (49, 57, 36, 0))
    coordinates = []
    for box, polygon, rotate, (x, y, width, height) in crops:
        color = source.crop(box)
        color = ImageEnhance.Color(color).enhance(1.24)
        color = ImageEnhance.Brightness(color).enhance(1.16)
        tile = np.array(color)
        tile[:, :, 1] = np.minimum(tile[:, :, 1].astype("uint16") * 1.06, 255)
        color = Image.fromarray(tile)
        mask = Image.new("L", color.size)
        ImageDraw.Draw(mask).polygon(polygon, fill=255)
        cutout = alpha.crop(box)
        cutout.paste(0, mask=mask.point(lambda value: 255 - value))
        color.putalpha(cutout)
        if rotate:
            color = color.transpose(Image.Transpose.ROTATE_270)
        atlas.paste(color.resize((width, height), Image.Resampling.LANCZOS), (x, y))
        coordinates.append((x / 512, y / 256, width / 512, height / 256))
    atlas.save(OUTPUT / "pine_needles.png", optimize=True)
    return coordinates


def unit(vector):
    return vector / np.linalg.norm(vector)


class Surface:
    def __init__(self, material):
        self.material = material
        self.positions = []
        self.normals = []
        self.uv = []
        self.colors = []
        self.indices = []

    def vertex(self, position, normal, uv, tint=1.0):
        self.positions.append(position)
        self.normals.append(normal)
        self.uv.append(uv)
        color = round(tint * 255)
        self.colors.append((color, color, color, 255))

    def strip(self, start, rows):
        for row in range(rows - 1):
            left = start + row * 2
            self.indices.extend((left, left + 2, left + 1,
                                 left + 1, left + 2, left + 3))

    def add_imported(self, source, scale, lift=0.0):
        positions, normals, uv, indices = source
        self.positions.extend(positions * scale + [0.0, lift, 0.0])
        adjusted = normals / scale
        self.normals.extend(adjusted / np.linalg.norm(adjusted, axis=1)[:, None])
        self.uv.extend(uv)
        self.colors.extend([(255, 255, 255, 255)] * len(positions))
        self.indices.extend(indices)


def shoot(surface, point, direction, length, width, roll, texture, tint):
    forward = unit(direction)
    up = UP if abs(forward[1]) < 0.94 else np.array([0.0, 0.0, 1.0])
    sideways = unit(np.cross(up, forward))
    normal = np.cross(forward, sideways)
    sideways = sideways * math.cos(roll) + normal * math.sin(roll)
    normal = np.cross(forward, sideways)
    u, v, w, h = texture
    start = len(surface.positions)
    for t in (0.0, 0.44, 1.0):
        midpoint = point + forward * length * t - normal * (length * 0.10 * t * t)
        for side in (-0.5, 0.5):
            surface.vertex(midpoint + sideways * width * side, normal,
                           (u + w * t, v + h * (side + 0.5)), tint)
    surface.strip(start, 3)


def tube(surface, points, radii, sides):
    start = len(surface.positions)
    direction = unit(points[-1] - points[0])
    helper = UP if abs(direction[1]) < 0.94 else np.array([1.0, 0.0, 0.0])
    x = unit(np.cross(helper, direction))
    y = np.cross(x, direction)
    for row, (point, radius) in enumerate(zip(points, radii)):
        for j in range(sides + 1):
            angle = math.tau * j / sides
            normal = x * math.cos(angle) + y * math.sin(angle)
            surface.vertex(point + normal * radius, normal,
                           (0.21 + 0.28 * j / sides, 0.64 - 0.24 * row))
    for row in range(len(points) - 1):
        for j in range(sides):
            a = start + row * (sides + 1) + j
            b = a + sides + 1
            surface.indices.extend((a, b, a + 1, a + 1, b, b + 1))


def make_sapling(tiles):
    trunk, foliage = Surface(1), Surface(2)
    crown = np.array([0.023, 0.49, -0.023])
    tube(trunk, [np.zeros(3), np.array([0.008, 0.22, -0.01]), crown],
         [0.016, 0.01, 0.004], 7)
    rng = np.random.default_rng(813)
    tiers = [(0.13, 0.165, 4), (0.25, 0.15, 4), (0.37, 0.103, 4), (0.46, 0.083, 3)]
    for i, (y, length, branches) in enumerate(tiers):
        for j in range(branches):
            angle = 1.13 * i + math.tau * j / branches + rng.uniform(-0.14, 0.14)
            point = np.array([y * 0.045, y + rng.uniform(-0.027, 0.017), -y * 0.045])
            direction = np.array([math.cos(angle), rng.uniform(0.12, 0.41), math.sin(angle)])
            tip = point + direction * length
            tube(trunk, [point, tip], [0.0065, 0.001], 4)
            for k, turn in enumerate((-0.48, 0.0, 0.51)):
                aim = np.array([math.cos(angle + turn), direction[1] + 0.21 * k,
                                math.sin(angle + turn)])
                shoot(foliage, point + direction * length * (0.36 + 0.17 * k), aim,
                      length * 0.84, length * 0.47, (-0.57, 0.63, 0.1)[k], tiles[k % 2], 1.0)
    for angle in (0.3, 1.9, 3.8):
        shoot(foliage, crown, np.array([0.12 * math.cos(angle), 1.0, 0.12 * math.sin(angle)]),
              0.17, 0.093, angle, tiles[0], 1.0)
    return [trunk, foliage]


def make_tree(stage, wood, tips, tiles):
    boughs, trunk, foliage = Surface(0), Surface(1), Surface(2)
    mature = stage == "mature"
    if mature:
        bough_scale, bough_lift, trunk_scale = (0.45, 0.46, 0.45), 0.0, (0.45, 0.46, 0.45)
    else:
        bough_scale, bough_lift, trunk_scale = (0.22, 0.190, 0.22), -0.53, (0.18, 0.168, 0.18)
    boughs.add_imported(wood[0], bough_scale, bough_lift)
    trunk.add_imported(wood[1], trunk_scale)

    rng = np.random.default_rng(491 if mature else 381)
    for index, (a, b) in enumerate(tips):
        if not mature and index % 4 == 1:
            continue
        root = a * bough_scale + [0.0, bough_lift, 0.0]
        tip = b * bough_scale + [0.0, bough_lift, 0.0]
        axis = tip - root
        bearing = math.atan2(axis[2], axis[0])
        size = rng.uniform(0.31, 0.53) if mature else rng.uniform(0.21, 0.33)
        for j in range(2):
            angle = bearing + (-1 if j == 0 else 1) * rng.uniform(0.25, 0.74)
            upward = axis[1] / np.linalg.norm(axis)
            aim = np.array([math.cos(angle), upward * 0.68 + rng.uniform(-0.14, 0.28),
                            math.sin(angle)])
            point = root + axis * (0.45 + 0.25 * j)
            shoot(foliage, point, aim, size, size * rng.uniform(0.42, 0.63),
                  rng.uniform(-0.9, 0.9), tiles[(index + j) % 2],
                  rng.uniform(0.77, 1.0) if mature else rng.uniform(0.86, 1.0))

    # The source branch tubes end below the highest needle shoots.
    tip = np.array([0.0, 6.42 if mature else 2.12, 0.0])
    for angle in (0.1, 2.2, 4.3):
        aim = np.array([0.26 * math.cos(angle), 1.0, 0.26 * math.sin(angle)])
        shoot(foliage, tip, aim, 0.56 if mature else 0.28, 0.26 if mature else 0.135,
              angle, tiles[0], 0.93)
    return [boughs, trunk, foliage]


def glb(model, data):
    encoded = json.dumps(model, separators=(",", ":"), allow_nan=False).encode()
    encoded += b" " * (-len(encoded) % 4)
    data += b"\0" * (-len(data) % 4)
    header = struct.pack("<4sIII4s", b"glTF", 2, 28 + len(encoded) + len(data),
                         len(encoded), b"JSON")
    return header + encoded + struct.pack("<I4s", len(data), b"BIN\0") + data


def write_tree(stage, surfaces):
    names = ["Pine Boughs", "Pine Trunk", "Pine Needles"]
    image_names = ["pine_bark.jpg", "pine_trunk.jpg", "pine_needles.png"]
    mesh_name = "Pine " + stage.title()
    model = {
        "asset": {"version": "2.0", "generator": "Cooper Camp | Pine Tree 01",
                  "copyright": "Pine Tree 01 by Rico Cilliers and Rob Tuytel, Poly Haven (CC0 1.0)"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": mesh_name}],
        "meshes": [{"name": mesh_name, "primitives": []}],
        "materials": [],
        "images": [{"uri": name} for name in image_names],
        "textures": [{"source": i, "sampler": int(i == 2)} for i in range(3)],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": wrap, "wrapT": wrap}
                     for wrap in (10497, 33071)],
        "bufferViews": [], "accessors": [], "buffers": [],
    }
    for i, name in enumerate(names):
        material = {
            "name": name,
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": i}, "metallicFactor": 0, "roughnessFactor": 0.92,
            },
        }
        if i == 2:
            material.update(alphaMode="MASK", alphaCutoff=0.36, doubleSided=True)
        model["materials"].append(material)

    data = bytearray()

    def accessor(values, dtype, kind, component, target, bounds=False, normalized=False):
        values = np.asarray(values, dtype=dtype)
        index = len(model["bufferViews"])
        model["bufferViews"].append(
            {"buffer": 0, "byteOffset": len(data), "byteLength": values.nbytes, "target": target}
        )
        data.extend(values.tobytes())
        data.extend(b"\0" * (-len(data) % 4))
        entry = {"bufferView": index, "componentType": component, "count": len(values), "type": kind}
        if bounds:
            entry.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
        if normalized:
            entry["normalized"] = True
        model["accessors"].append(entry)
        return len(model["accessors"]) - 1

    points = np.concatenate([surface.positions for surface in surfaces])
    minimum = points.min(axis=0)
    maximum = points.max(axis=0)
    scale = HEIGHTS[stage] / (maximum[1] - minimum[1])
    triangles = 0
    for surface in surfaces:
        positions = (np.array(surface.positions) - [0.0, minimum[1], 0.0]) * scale
        assert len(positions) < 65536
        attributes = {
            "POSITION": accessor(positions, "<f4", "VEC3", 5126, 34962, bounds=True),
            "NORMAL": accessor(surface.normals, "<f4", "VEC3", 5126, 34962),
            "TEXCOORD_0": accessor(surface.uv, "<f4", "VEC2", 5126, 34962),
            "COLOR_0": accessor(surface.colors, "u1", "VEC4", 5121, 34962, normalized=True),
        }
        indices = accessor(surface.indices, "<u2", "SCALAR", 5123, 34963)
        model["meshes"][0]["primitives"].append(
            {"attributes": attributes, "indices": indices, "material": surface.material}
        )
        triangles += len(surface.indices) // 3
    model["buffers"].append({"byteLength": len(data)})
    path = OUTPUT / f"pine_{stage}.glb"
    path.write_bytes(glb(model, bytes(data)))
    dimensions = " × ".join(f"{size:.2f}" for size in (maximum - minimum) * scale)
    print(f"{path.name}: {dimensions} m | {triangles:,} triangles | {path.stat().st_size:,} bytes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="download missing official source files")
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot4")
                        or shutil.which("godot") or str(Path.home() / "Downloads/Godot.app/Contents/MacOS/Godot"))
    arguments = parser.parse_args()
    CACHE.mkdir(exist_ok=True)
    OUTPUT.mkdir(exist_ok=True)
    if arguments.fetch:
        fetch_file("pine-model-index.json", f"{MODEL}/pine_tree_01_1k.gltf")
        fetch_file("pine-B-trunk.range", MODEL_BUFFER, *WOOD_RANGE)
        for name, (source, _) in MAP_SOURCES.items():
            fetch_file(name, f"{MAPS}/pine_tree_01_{source}_1k.jpg")
    for name, (_, checksum) in MAP_SOURCES.items():
        if hashlib.md5((CACHE / name).read_bytes()).hexdigest() != checksum:
            raise ValueError(f"Poly Haven checksum mismatch for {name}")

    model, data, positions, faces = make_source_wood()
    wood = reduced_wood(model, data, arguments.godot)
    tips = branch_tips(positions, faces)
    tiles = foliage_atlas()
    for source, destination in [("pine-bark.jpg", "pine_bark.jpg"), ("pine-trunk-b.jpg", "pine_trunk.jpg")]:
        image = Image.open(CACHE / source).convert("RGB")
        image.resize((512, 512), Image.Resampling.LANCZOS).save(
            OUTPUT / destination, quality=87, optimize=True
        )
    write_tree("sapling", make_sapling(tiles))
    for stage in ("young", "mature"):
        write_tree(stage, make_tree(stage, wood[stage], tips, tiles))


if __name__ == "__main__":
    main()
