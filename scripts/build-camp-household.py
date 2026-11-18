"""Bake the four original Artaley3D household scans to grounded runtime GLBs."""

import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "art/household"
PROPS = ROOT / "coop/props"
HEADER = struct.Struct("<4sIQQQ")
ASSETS = {
    "table_gnome": ("StrawberryGardenGnomeFigurine_BLEND", "StrawberryGardenGnomeFigurine_LOD3", 1, 0.195),
    "table_babushka": ("Babushka_BLEND", "Babushka", 1, 0.155),
    "food_bread": ("BreadRoll_001_Blend", "BreadRoll_LOD1", 0, 0.102),
    "food_apple": ("GalaApple_01_BLEND", "GalaApple_01", 1, 0.078),
}

# Reuse the repository's SDNA field reader, corner normals, and binary accessor writer.
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("camp_stones", Path(__file__).with_name("build-camp-stones.py"))
rock_export = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rock_export)


class Blend5(rock_export.Blend):
    """Read the Blender 5 file and keep data pointer IDs scoped to each datablock."""

    def __init__(self, path):
        data = subprocess.check_output(["zstd", "-q", "-dc", str(path)])
        if not data.startswith(b"BLENDER17-01v05"):
            raise ValueError(f"Expected a little-endian Blender 5 file: {path}")
        self.blocks, self.kinds, self.group = {}, {}, {}
        cursor, owner = 17, None
        while cursor < len(data):
            code, type_id, address, size, count = HEADER.unpack_from(data, cursor)
            cursor += HEADER.size
            block = (code, type_id, count, memoryview(data)[cursor:cursor + size])
            if code != b"DATA":
                owner = address
            self.group.setdefault(owner, {})[address] = block
            self.blocks[address] = block
            self.kinds.setdefault(code, []).append(block)
            cursor += size
        if cursor != len(data):
            raise ValueError(f"Incomplete Blender datablock in {path}")
        self._read_schema(self.kinds[b"DNA1"][0][3].tobytes())

    def _float_array(self, data, kind, name):
        offset, _, _, count = self.schemas[kind][1][name]
        return struct.unpack_from(f"<{count}f", data, offset)

    def mesh(self, object_name):
        for _, _, _, obj in self.kinds[b"OB\0\0"]:
            if self.identifier("Object", obj) == object_name:
                break
        else:
            raise ValueError(f"Missing source object: {object_name}")

        mesh_address = self.field(obj, "Object", "data")
        datablocks = self.group[mesh_address]
        mesh = datablocks[mesh_address][3]
        storage = self.field(mesh, "Mesh", "attribute_storage")
        entries = datablocks[self.field(storage, "AttributeStorage", "dna_attributes")][3]
        entry_count = self.field(storage, "AttributeStorage", "dna_attributes_num")
        entry_size = self.schemas["Attribute"][0]
        attributes = {}
        for i in range(entry_count):
            entry = entries[i * entry_size:(i + 1) * entry_size]
            name_ptr = self.field(entry, "Attribute", "name")
            label = bytes(datablocks[name_ptr][3]).split(b"\0", 1)[0].decode()
            if label not in ("position", ".corner_vert", "UVMap"):
                continue
            array = datablocks[self.field(entry, "Attribute", "data")][3]
            attributes[label] = datablocks[self.field(array, "AttributeArray", "data")][3]

        points = np.frombuffer(attributes["position"], "<f4").reshape(-1, 3).astype(np.float64)
        offsets = datablocks[self.field(mesh, "Mesh", "poly_offset_indices")][3]
        widths = np.diff(np.frombuffer(offsets, "<i4"))
        if not np.all(widths == 3):
            raise ValueError(f"Expected triangular polygons in {object_name}")
        faces = np.frombuffer(attributes[".corner_vert"], "<i4").reshape(-1, 3)
        uv = np.frombuffer(attributes["UVMap"], "<f4").reshape(-1, 2).astype(np.float64)

        # The bread roll stores its up orientation as a Blender object rotation.
        if self.field(obj, "Object", "parent"):
            raise ValueError(f"Expected a single unparented object in {object_name}")
        x, y, z = self._float_array(obj, "Object", "rot")
        sx, sy, sz = np.sin((x, y, z))
        cx, cy, cz = np.cos((x, y, z))
        rx = np.array(((1, 0, 0), (0, cx, -sx), (0, sx, cx)))
        ry = np.array(((cy, 0, sy), (0, 1, 0), (-sy, 0, cy)))
        rz = np.array(((cz, -sz, 0), (sz, cz, 0), (0, 0, 1)))
        points = (points * self._float_array(obj, "Object", "size")) @ (rz @ ry @ rx).T
        # Blender to glTF basis, then bottom-origin Blender UV to top-origin textures.
        return points[:, [0, 2, 1]] * (1, 1, -1), faces, uv * (1, -1) + (0, 1)


def texture(folder, names, mode="RGB"):
    for entry in folder.iterdir():
        if any(fragment in entry.stem for fragment in names):
            with Image.open(entry) as source:
                return source.convert(mode).resize((512, 512), Image.Resampling.LANCZOS)
    raise ValueError(f"Missing {' or '.join(names)} in {folder}")


def texture_payload(folder):
    base = texture(folder, ("_BaseColor",))
    normal = texture(folder, ("_Normal",))
    occlusion = texture(folder, ("_AmbientOcclusion", "_AmbientOcculsion"), "L")
    roughness = texture(folder, ("_Roughness",), "L")
    # glTF uses R for AO, G for roughness and B for metalness. The source masks are all black.
    arm = Image.merge("RGB", (occlusion, roughness, Image.new("L", roughness.size, 0)))
    return [rock_export.jpeg(base, 91), rock_export.jpeg(normal, 94), rock_export.jpeg(arm, 94)]


def export(name, points, faces, uv, maps):
    output = rock_export.PropFile()
    corners = rock_export.corner_data(points, faces, uv)
    primitive = output.primitive([tuple(corners[i:i + 3]) for i in range(0, len(corners), 3)], 0)
    images = [{"bufferView": output.append(raw), "mimeType": "image/jpeg"} for raw in maps]
    gltf = {
        "asset": {"version": "2.0", "generator": "Rainline Camp", "copyright": "Artaley3D | CC0 | https://artaley3d.com/models"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": [primitive]}],
        "materials": [{
            "name": "Scanned Surface",
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": 0},
                "metallicRoughnessTexture": {"index": 2},
                "metallicFactor": 0.0,
                "roughnessFactor": 1.0,
            },
            "normalTexture": {"index": 1},
            "occlusionTexture": {"index": 2},
        }],
        "textures": [{"source": i, "sampler": 0} for i in range(len(images))],
        "samplers": [{"magFilter": 9729, "minFilter": 9987}],
        "images": images,
        "accessors": output.accessors,
        "bufferViews": output.view,
        "buffers": [{"byteLength": len(output.payload)}],
    }
    document = json.dumps(gltf, separators=(",", ":")).encode()
    document += b" " * (-len(document) % 4)
    output.payload.extend(b"\0" * (-len(output.payload) % 4))
    destination = PROPS / f"{name}.glb"
    destination.write_bytes(
        struct.pack("<4sIII4s", b"glTF", 2, 28 + len(document) + len(output.payload), len(document), b"JSON")
        + document + struct.pack("<I4s", len(output.payload), b"BIN\0") + output.payload
    )
    print(f"{name}: {len(faces):,} triangles, {np.ptp(points, axis=0).round(4)} m, {destination.stat().st_size:,} bytes")


def add_import_settings(name):
    path = PROPS / f"{name}.glb.import"
    if path.exists():
        return
    reference = (PROPS / "stone_round.glb.import").read_text()
    old = "res://props/stone_round.glb"
    new = f"res://props/{name}.glb"
    text = reference.replace(hashlib.md5(old.encode()).hexdigest(), hashlib.md5(new.encode()).hexdigest())
    text = text.replace("stone_round.glb", f"{name}.glb")
    # Let Godot allocate a fresh resource UID when it imports the asset.
    path.write_text("\n".join(line for line in text.splitlines() if not line.startswith("uid=")) + "\n")


def main():
    for name, (folder, object_name, fit_axis, size) in ASSETS.items():
        source = SOURCES / folder
        points, faces, uv = Blend5(next(source.glob("*.blend"))).mesh(object_name)
        low, high = points.min(axis=0), points.max(axis=0)
        base = np.array(((low[0] + high[0]) * 0.5, low[1], (low[2] + high[2]) * 0.5))
        points = (points - base) * (size / (high[fit_axis] - low[fit_axis]))
        export(name, points, faces, uv, texture_payload(source / "Textures"))
        add_import_settings(name)


if __name__ == "__main__":
    main()
