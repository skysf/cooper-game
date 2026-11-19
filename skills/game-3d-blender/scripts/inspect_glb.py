#!/usr/bin/env python3
"""Report the geometry, embedded textures, skinning, and clips declared in GLB files."""

import argparse
import io
import json
import struct
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    Image = None


HEADER = struct.Struct("<4sII")
CHUNK_HEADER = struct.Struct("<I4s")


def read_exact(stream, count):
    data = stream.read(count)
    if len(data) != count:
        raise ValueError("unexpected end of GLB")
    return data


def read_layout(stream, file_size):
    magic, version, declared_size = HEADER.unpack(read_exact(stream, HEADER.size))
    if magic != b"glTF" or version != 2:
        raise ValueError("expected a GLB version 2 file")
    if declared_size != file_size:
        raise ValueError("GLB header length does not match the file")
    json_length, kind = CHUNK_HEADER.unpack(read_exact(stream, CHUNK_HEADER.size))
    if kind != b"JSON" or json_length > file_size - stream.tell():
        raise ValueError("invalid first GLB chunk")
    document = json.loads(read_exact(stream, json_length))
    if not isinstance(document, dict):
        raise ValueError("GLB JSON must be an object")
    binary = None
    while stream.tell() < file_size:
        length, kind = CHUNK_HEADER.unpack(read_exact(stream, CHUNK_HEADER.size))
        offset = stream.tell()
        if offset + length > file_size:
            raise ValueError("GLB chunk extends past the file")
        if kind == b"BIN\x00":
            binary = (offset, length)
        stream.seek(offset + length)
    return document, binary


def triangle_count(mode, count):
    if mode == 4:
        return count // 3
    if mode in (5, 6):
        return max(0, count - 2)
    return 0


def inspect_primitive(primitive, accessors):
    attributes = primitive["attributes"]
    vertices = accessors[attributes["POSITION"]]["count"]
    elements = accessors[primitive["indices"]]["count"] if "indices" in primitive else vertices
    skins = sum(name.startswith("JOINTS_") for name in attributes)
    return {
        "vertices": vertices,
        "triangles": triangle_count(primitive.get("mode", 4), elements),
        "material": primitive.get("material"),
        "joint_attribute_sets": skins,
        "morph_targets": len(primitive.get("targets", [])),
    }


def inspect_image(image, document, stream, binary):
    report = {"name": image.get("name"), "mime_type": image.get("mimeType")}
    if "bufferView" not in image or binary is None:
        return report
    view = document["bufferViews"][image["bufferView"]]
    if view["buffer"] != 0:
        return report
    start, size = binary
    offset, length = view.get("byteOffset", 0), view["byteLength"]
    if offset < 0 or length < 0 or offset + length > size:
        raise ValueError("embedded image is outside the BIN chunk")
    report["embedded_bytes"] = length
    if Image is not None:
        stream.seek(start + offset)
        try:
            with Image.open(io.BytesIO(read_exact(stream, length))) as texture:
                report["dimensions"] = list(texture.size)
        except (OSError, Image.DecompressionBombError):
            pass
    return report


def inspect_animation(animation, accessors):
    times = [accessors[sampler["input"]] for sampler in animation["samplers"]]
    duration = None
    if times and all(accessor.get("min") and accessor.get("max") for accessor in times):
        duration = max(accessor["max"][0] for accessor in times)
        duration -= min(accessor["min"][0] for accessor in times)
    paths = sorted({
        channel["target"]["path"]
        for channel in animation["channels"]
    })
    return {"name": animation.get("name"), "duration_seconds": duration, "target_paths": paths}


def inspect_glb(path):
    size = path.stat().st_size
    with path.open("rb") as stream:
        document, binary = read_layout(stream, size)
        accessors = document.get("accessors", [])
        meshes = [
            {
                "name": mesh.get("name"),
                "primitives": [
                    inspect_primitive(primitive, accessors)
                    for primitive in mesh["primitives"]
                ],
            }
            for mesh in document.get("meshes", [])
        ]
        images = [
            inspect_image(image, document, stream, binary)
            for image in document.get("images", [])
        ]
        return {
            "file": str(path),
            "bytes": size,
            "triangles": sum(
                primitive["triangles"] for mesh in meshes for primitive in mesh["primitives"]
            ),
            "materials": len(document.get("materials", [])),
            "meshes": meshes,
            "images": images,
            "skins": [
                {"name": skin.get("name"), "joints": len(skin["joints"])}
                for skin in document.get("skins", [])
            ],
            "animations": [
                inspect_animation(animation, accessors)
                for animation in document.get("animations", [])
            ],
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", type=Path, metavar="FILE")
    args = parser.parse_args()
    reports = []
    for path in args.files:
        try:
            reports.append(inspect_glb(path))
        except (OSError, ValueError, KeyError, IndexError, TypeError) as exc:
            parser.error(f"{path}: {exc}")
    print(json.dumps(reports, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
