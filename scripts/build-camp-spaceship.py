"""Reduce the supplied single-mesh GLB while keeping its PBR textures and UVs."""

import argparse
import ctypes
import io
import json
from pathlib import Path
import struct

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art/vehicles/source/红色科幻飞船.glb"
OUTPUT = ROOT / "coop/props/camp_red_spaceship.glb"


def simplify(library, indices, positions, normals, uv):
    meshopt = ctypes.CDLL(str(library.resolve()))
    pointer = ctypes.c_void_p
    size = ctypes.c_size_t
    fn = meshopt.meshopt_simplifyWithAttributes
    fn.argtypes = [pointer, pointer, size, pointer, size, size, pointer, size,
                   pointer, size, pointer, size, ctypes.c_float, ctypes.c_uint, pointer]
    fn.restype = size
    attributes = np.ascontiguousarray(np.column_stack((normals, uv)), dtype="<f4")
    weights = np.array([0.16, 0.16, 0.16, 0.45, 0.45], dtype="<f4")
    reduced = np.empty_like(indices)
    error = ctypes.c_float()
    # Permit small UV/normal discontinuities to collapse within the attribute error budget.
    count = fn(reduced.ctypes.data, indices.ctypes.data, indices.size, positions.ctypes.data,
               len(positions), 12, attributes.ctypes.data, 20, weights.ctypes.data, 5,
               None, 90_000 * 3, 0.015, 1 << 5, ctypes.byref(error))
    if not count or count > 140_000 * 3:
        raise RuntimeError(f"Simplification returned {count // 3:,} triangles")
    print(f"{indices.size // 3:,} → {count // 3:,} triangles (relative error {error.value:.5f})")
    used, remapped = np.unique(reduced[:count], return_inverse=True)
    return used, remapped.astype("<u2" if len(used) <= 65536 else "<u4")


def main(library):
    file = SOURCE.read_bytes()
    magic, version, file_size, json_size, json_kind = struct.unpack_from("<4sIIII", file)
    if (magic, version, file_size, json_kind) != (b"glTF", 2, len(file), 0x4E4F534A):
        raise ValueError("Expected the original GLB v2 model")
    document = json.loads(file[20:20 + json_size])
    binary = memoryview(file)[28 + json_size:]
    views = document["bufferViews"]
    accessors = document["accessors"]
    primitive, = document["meshes"][0]["primitives"]

    def view(index):
        record = views[index]
        start = record.get("byteOffset", 0)
        return binary[start:start + record["byteLength"]]

    def accessor(index, dtype, components):
        record = accessors[index]
        return np.frombuffer(view(record["bufferView"]), dtype=dtype,
                             offset=record.get("byteOffset", 0),
                             count=record["count"] * components).reshape(-1, components)

    attributes = primitive["attributes"]
    positions = accessor(attributes["POSITION"], "<f4", 3)
    normals = accessor(attributes["NORMAL"], "<f4", 3)
    uv = accessor(attributes["TEXCOORD_0"], "<f4", 2)
    indices = accessor(primitive["indices"], "<u4", 1).ravel()
    used, reduced = simplify(library, indices, positions, normals, uv)

    # Face the Godot forward axis (-Z), with the lowest hull point on the ground.
    oriented_positions = positions[used][:, [2, 1, 0]] * [-2.4, 2.4, 2.4]
    oriented_positions[:, 1] -= oriented_positions[:, 1].min()
    oriented_normals = normals[used][:, [2, 1, 0]] * [-1.0, 1.0, 1.0]
    payload = bytearray()
    new_views = []

    def append(data, target=None):
        payload.extend(b"\0" * (-len(payload) % 4))
        record = {"buffer": 0, "byteOffset": len(payload), "byteLength": len(data)}
        if target is not None:
            record["target"] = target
        new_views.append(record)
        payload.extend(data)
        return len(new_views) - 1

    for index, array, target in [
        (attributes["POSITION"], oriented_positions.astype("<f4"), 34962),
        (attributes["NORMAL"], oriented_normals.astype("<f4"), 34962),
        (attributes["TEXCOORD_0"], uv[used], 34962),
        (primitive["indices"], reduced, 34963),
    ]:
        record = accessors[index]
        record.update(bufferView=append(array.tobytes(), target), byteOffset=0, count=len(array))
        if "min" in record:
            record.update(min=array.min(axis=0).tolist(), max=array.max(axis=0).tolist())
        if target == 34963:
            record["componentType"] = 5123 if array.dtype.itemsize == 2 else 5125

    for record in document["images"]:
        with Image.open(io.BytesIO(view(record["bufferView"]))) as image:
            texture = image.convert("RGB")
            texture.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
            buffer = io.BytesIO()
            texture.save(buffer, format="JPEG", quality=89, subsampling=0, optimize=True)
        record["bufferView"] = append(buffer.getvalue())

    document["bufferViews"] = new_views
    document["buffers"] = [{"byteLength": len(payload)}]
    document["nodes"][0]["name"] = "RedSpaceship"
    document["asset"]["generator"] = "Cooper Game / meshoptimizer"
    encoded = json.dumps(document, separators=(",", ":")).encode()
    encoded += b" " * (-len(encoded) % 4)
    payload.extend(b"\0" * (-len(payload) % 4))
    result = (struct.pack("<4sIIII", b"glTF", 2, 28 + len(encoded) + len(payload), len(encoded), 0x4E4F534A)
              + encoded + struct.pack("<II", len(payload), 0x004E4942) + payload)
    OUTPUT.write_bytes(result)
    print(f"{OUTPUT.name}: {len(result) / 1_000_000:.2f} MB")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("meshoptimizer_library", type=Path)
    main(parser.parse_args().meshoptimizer_library)
