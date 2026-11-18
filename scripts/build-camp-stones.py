"""Export the local Poly Haven Blender rock packages for the co-op game."""

import ctypes
import gzip
import io
import json
import math
from pathlib import Path
import re
import struct
import subprocess

import numpy as np
from PIL import Image, ImageEnhance, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art/rocks"
PROPS = ROOT / "coop/props"
HEADER = struct.Struct("<4sIQII")


class Blend:
    def __init__(self, path):
        if path.name.startswith('rock_moss_set'):
            with gzip.open(path, 'rb') as source:
                self.data = source.read()
        else:
            self.data = subprocess.check_output(['zstd', '-q', '-dc', str(path)])
        assert self.data.startswith(b'BLENDER-v'), self.data[:12]
        self.blocks = {}
        self.kinds = {}
        cursor = 12
        while cursor < len(self.data):
            code, size, address, dna_type, count = HEADER.unpack_from(self.data, cursor)
            cursor += HEADER.size
            chunk = memoryview(self.data)[cursor:cursor+size]
            block = (code, dna_type, count, chunk)
            self.blocks[address] = block
            self.kinds.setdefault(code, []).append(block)
            cursor += size
        self._read_schema(self.kinds[b'DNA1'][0][3].tobytes())

    def _read_schema(self, data):
        def fields(at, header):
            assert data[at:at+4] == header
            count, = struct.unpack_from('<I', data, at + 4)
            strings, at = [], at + 8
            for i in range(count):
                end = data.index(b'\0', at)
                strings.append(data[at:end].decode())
                at = end + 1
            return strings, (at+3)//4*4
        names, at = fields(4, b'NAME')
        types, at = fields(at, b'TYPE')
        assert data[at:at+4] == b'TLEN'
        sizes = struct.unpack_from('<' + 'H'*len(types), data, at+4)
        at = (at+4+2*len(types)+3)//4*4
        assert data[at:at+4] == b'STRC'
        count, = struct.unpack_from('<I',data,at+4)
        at += 8
        self.schemas = {}
        for i in range(count):
            type_id, size = struct.unpack_from('<HH', data, at)
            at += 4
            fields, offset = {}, 0
            for j in range(size):
                t, n = struct.unpack_from('<HH', data, at)
                at += 4
                label = names[n].split('[')[0].lstrip('(*')
                pointer = names[n].startswith(('*', '(*'))
                length = math.prod(map(int, re.findall(r'\[(\d+)\]', names[n])))
                fields[label] = (offset, types[t], pointer, length)
                offset += (8 if pointer else sizes[t]) * length
            if offset != sizes[type_id]:
                raise ValueError((types[type_id], offset, sizes[type_id]))
            self.schemas[types[type_id]] = (sizes[type_id], fields)

    def field(self, data, kind, name):
        offset, typ, pointer, count = self.schemas[kind][1][name]
        if pointer:
            return struct.unpack_from('<Q', data, offset)[0]
        if typ == 'int':
            return struct.unpack_from('<i', data, offset)[0]
        if typ == 'char':
            return bytes(data[offset:offset+count]).partition(b'\0')[0].decode('utf-8','replace')
        return data[offset:offset+self.schemas[typ][0]]

    def identifier(self, kind, data):
        return self.field(self.field(data,kind,'id'),'ID','name')[2:]

    def layers(self, kind):
        count = self.field(kind,'CustomData','totlayer')
        pointer = self.field(kind,'CustomData','layers')
        data = self.blocks[pointer][3] if count else b''
        size = self.schemas['CustomDataLayer'][0]
        return [data[i*size:(i+1)*size] for i in range(count)]

    def mesh(self, object_name):
        for _, _, _, obj in self.kinds[b"OB\0\0"]:
            if self.identifier("Object", obj) == object_name:
                break
        else:
            raise ValueError(f"Missing source object {object_name}")
        mesh = self.blocks[self.field(obj, "Object", "data")][3]
        vertex_count = self.field(mesh, "Mesh", "totvert")
        corner_count = self.field(mesh, "Mesh", "totloop")
        legacy_vertices = self.field(mesh, "Mesh", "mvert")

        def data_layer(group, label):
            for layer in self.layers(self.field(mesh, "Mesh", group)):
                if self.field(layer, "CustomDataLayer", "name") == label:
                    return self.blocks[self.field(layer, "CustomDataLayer", "data")][3]
            raise ValueError(f"Missing {label} on {object_name}")

        uv_map = data_layer("ldata", "UVMap")
        if legacy_vertices:
            points = np.ndarray((vertex_count, 3), "<f4", self.blocks[legacy_vertices][3], strides=(20, 4))
            corners = np.ndarray((corner_count,), "<i4", self.blocks[self.field(mesh, "Mesh", "mloop")][3], strides=(8,))
            polygons = self.blocks[self.field(mesh, "Mesh", "mpoly")][3]
            widths = np.ndarray((corner_count // 3,), "<i4", polygons, offset=4, strides=(12,))
            uv = np.ndarray((corner_count, 2), "<f4", uv_map, strides=(12, 4))
        else:
            points = np.frombuffer(data_layer("vdata", "position"), "<f4").reshape(-1, 3)
            corners = np.frombuffer(data_layer("ldata", ".corner_vert"), "<i4")
            offsets = self.blocks[self.field(mesh, "Mesh", "poly_offset_indices")][3]
            widths = np.diff(np.frombuffer(offsets, "<i4"))
            uv = np.frombuffer(uv_map, "<f4").reshape(-1, 2)
        if len(widths) * 3 != corner_count or not np.all(widths == 3):
            raise ValueError(f"Source mesh {object_name} must be triangulated")
        # Convert Blender Z-up and bottom-origin UVs to glTF Y-up and top-origin UVs.
        return points[:, [0, 2, 1]].astype(float) * [1, 1, -1], corners.reshape(-1, 3), uv.astype(float) * [1, -1] + [0, 1]


def unit(vector):
    return vector / np.linalg.norm(vector)


def corner_data(points, faces, uv):
    normals = np.zeros_like(points)
    triangles = points[faces]
    face_normals = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    for i in range(3):
        np.add.at(normals, faces[:, i], face_normals)
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-12)
    return list(zip(points[faces.ravel()], normals[faces.ravel()], uv))


def ground_edge(vertices, faces):
    """Clip an oblique strip off the flat stone and cap the exposed stone."""
    normal = unit(np.array((0.12, 0.48, 1.0)))
    boundary_level = np.quantile([position @ normal for position, _, _ in vertices], 0.87)

    def offset(point):
        variation = 0.0004 * math.sin(130 * point[0])
        return point @ normal - boundary_level - variation

    retained, cap_points, links = [], {}, {}
    for face in faces:
        polygon, crossings = [], []
        for first, second in zip(face, face[1:] + face[:1]):
            a, b = vertices[first], vertices[second]
            before, after = offset(a[0]), offset(b[0])
            if before <= 0:
                polygon.append(a)
            if (before < 0 < after) or (after < 0 < before):
                fraction = before/(before-after)
                intersection = tuple(x + (y-x)*fraction for x, y in zip(a, b))
                key = tuple(intersection[0].round(7))
                cap_points[key] = intersection[0]
                crossings.append(key)
                polygon.append(intersection)
        if len(crossings) == 2 and crossings[0] != crossings[1]:
            first, second = crossings
            links.setdefault(first, set()).add(second)
            links.setdefault(second, set()).add(first)
        for i in range(1, len(polygon) - 1):
            retained.append((polygon[0], polygon[i], polygon[i+1]))

    if not links or any(len(neighbors) != 2 for neighbors in links.values()):
        raise ValueError("The stone bevel must form closed rims on the source shell")
    axis = unit(np.cross(np.array((0.0, 1.0, 0.0)), normal))
    cross_axis = np.cross(normal, axis)
    exposed = []
    while links:
        start = min(links)
        current, previous = start, None
        boundary = []
        while True:
            boundary.append(cap_points[current])
            upcoming = min(links.pop(current) - {previous})
            if upcoming == start:
                break
            previous, current = current, upcoming
        center = np.mean(boundary, axis=0)
        signed_area = sum(np.cross(a-center, b-center) @ normal for a, b in zip(boundary, boundary[1:] + boundary[:1]))
        if signed_area < 0:
            boundary.reverse()
        # A slight crown breaks up the fresh surface while keeping the original rim.
        crown = center + normal * 0.0007
        for a, b in zip(boundary, boundary[1:] + boundary[:1]):
            facet = unit(np.cross(a-crown, b-crown))
            face_normal = unit(0.60*normal + 0.40*facet)
            exposed.append(tuple((p, face_normal, np.array((0.5+(p-center)@axis*8, 0.5+(p-center)@cross_axis*15)))
                                 for p in (crown, a, b)))
    return retained, exposed


class PropFile:
    def __init__(self):
        self.payload = bytearray()
        self.view, self.accessors = [], []

    def append(self, raw, target=None):
        self.payload.extend(b"\0" * (-len(self.payload) % 4))
        view = {"buffer": 0, "byteOffset": len(self.payload), "byteLength": len(raw)}
        if target is not None:
            view["target"] = target
        self.view.append(view)
        self.payload.extend(raw)
        return len(self.view) - 1

    def accessor(self, array, kind, component, target, bounds=False):
        view = self.append(array.tobytes(), target)
        data = {"bufferView": view, "componentType": component, "count": len(array), "type": kind}
        if bounds:
            data.update(min=array.min(axis=0).tolist(), max=array.max(axis=0).tolist())
        self.accessors.append(data)
        return len(self.accessors) - 1

    def primitive(self, faces, material):
        unique, rows, indices = {}, [], []
        for face in faces:
            for position, normal, uv in face:
                values = tuple(np.concatenate((position, unit(normal), uv)).round(7))
                if values not in unique:
                    unique[values] = len(rows)
                    rows.append(values)
                indices.append(unique[values])
        data = np.array(rows, dtype="<f4")
        return {
            "attributes": {
                "POSITION": self.accessor(data[:, :3], "VEC3", 5126, 34962, bounds=True),
                "NORMAL": self.accessor(data[:, 3:6], "VEC3", 5126, 34962),
                "TEXCOORD_0": self.accessor(data[:, 6:8], "VEC2", 5126, 34962),
            },
            "indices": self.accessor(np.array(indices, dtype="<u2"), "SCALAR", 5123, 34963),
            "material": material,
        }

    def write(self, name, surfaces, images, credit):
        primitives = [self.primitive(faces, material) for material, faces in enumerate(surfaces)]
        materials = [{
            "name": "Scanned Rock",
            "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 2},
                                     "metallicFactor": 0, "roughnessFactor": 1.0},
            "normalTexture": {"index": 1, "scale": 0.92},
        }]
        if len(surfaces) == 2:
            materials.append({
                "name": "Fresh Stone",
                "pbrMetallicRoughness": {"baseColorTexture": {"index": 3}, "metallicFactor": 0,
                                         "roughnessFactor": 0.78},
            })
        image_views = [{"bufferView": self.append(raw), "mimeType": "image/jpeg"} for raw in images]
        payload = {
            "asset": {"version": "2.0", "generator": "Cooper Camp", "copyright": credit},
            "scene": 0,
            "scenes": [{"nodes": [0]}],
            "nodes": [{"mesh": 0, "name": name}],
            "meshes": [{"primitives": primitives, "name": name}],
            "materials": materials,
            "textures": [{"source": i, "sampler": 0} for i in range(len(images))],
            "samplers": [{"magFilter": 9729, "minFilter": 9987}],
            "images": image_views,
            "accessors": self.accessors,
            "bufferViews": self.view,
            "buffers": [{"byteLength": len(self.payload)}],
        }
        document = json.dumps(payload, separators=(",", ":")).encode()
        document += b" " * (-len(document) % 4)
        self.payload.extend(b"\0" * (-len(self.payload) % 4))
        path = PROPS / f"{name}.glb"
        path.write_bytes(struct.pack("<4sIII4s", b"glTF", 2, 28+len(document)+len(self.payload), len(document), b"JSON")
                         + document + struct.pack("<I4s", len(self.payload), b"BIN\0") + self.payload)
        print(f"{path.relative_to(ROOT)}: {sum(map(len, surfaces))} triangles, {path.stat().st_size:,} bytes")


def load_map(path):
    if path.suffix == ".exr":
        return load_exr(path)
    with Image.open(path) as image:
        return image.convert("RGB")


def load_exr(path):
    library = ROOT / ".cache/blender-lab/Blender/Blender.app/Contents/Resources/lib/libOpenEXR.dylib"
    exr = ctypes.CDLL(str(library))
    pointer = ctypes.c_void_p
    integer = ctypes.c_int
    signatures = {
        "ImfOpenInputFile": (pointer, ctypes.c_char_p),
        "ImfInputHeader": (pointer, pointer),
        "ImfHeaderDataWindow": (None, pointer, *([ctypes.POINTER(integer)] * 4)),
        "ImfInputSetFrameBuffer": (integer, pointer, pointer, ctypes.c_size_t, ctypes.c_size_t),
        "ImfInputReadPixels": (integer, pointer, integer, integer),
        "ImfCloseInputFile": (integer, pointer),
        "ImfErrorMessage": (ctypes.c_char_p,),
    }
    for name, (result, *arguments) in signatures.items():
        function = getattr(exr, name)
        function.restype = result
        function.argtypes = arguments
    handle = exr.ImfOpenInputFile(str(path).encode())
    if not handle:
        raise ValueError(exr.ImfErrorMessage().decode())
    try:
        bounds = [integer() for _ in range(4)]
        exr.ImfHeaderDataWindow(exr.ImfInputHeader(handle), *(ctypes.byref(value) for value in bounds))
        x_min, y_min, x_max, y_max = (value.value for value in bounds)
        if (x_min, y_min) != (0, 0):
            raise ValueError(f"Unexpected EXR raster offset for {path.name}")
        width, height = x_max + 1, y_max + 1
        pixels = np.empty((height, width, 4), dtype=np.float16)
        if not exr.ImfInputSetFrameBuffer(handle, pixels.ctypes.data, 1, width) or not exr.ImfInputReadPixels(handle, 0, y_max):
            raise ValueError(exr.ImfErrorMessage().decode())
        rgb = np.clip(pixels[:, :, :3].astype(np.float32), 0.0, 1.0)
        return Image.fromarray(np.rint(rgb * 255).astype(np.uint8))
    finally:
        exr.ImfCloseInputFile(handle)


def jpeg(image, quality=91):
    with io.BytesIO() as output:
        image.save(output, format="JPEG", quality=quality, optimize=True, subsampling=0)
        return output.getvalue()


def rock_maps(folder, prefix):
    return [load_map(next((folder / "textures").glob(f"{prefix}_{label}_4k.*")))
            for label in ("diff", "nor_gl", "rough")]


def mapped_crops(maps, uv, limit):
    dimensions = np.array(maps[0].size)
    low = np.maximum(0, np.floor(uv.min(axis=0) * dimensions).astype(int) - 12)
    high = np.minimum(dimensions, np.ceil(uv.max(axis=0) * dimensions).astype(int) + 12)
    cropped = []
    for image in maps:
        if image.size != tuple(dimensions):
            raise ValueError("Rock maps must share their UV raster dimensions")
        tile = image.crop((*low, *high))
        tile.thumbnail((limit, limit), Image.Resampling.LANCZOS)
        cropped.append(tile)
    roughness = cropped[2].getchannel("R")
    cropped[2] = Image.merge("RGB", (Image.new("L", roughness.size, 255), roughness, Image.new("L", roughness.size, 0)))
    return (uv * dimensions - low) / (high - low), [jpeg(cropped[0]), jpeg(cropped[1], 93), jpeg(cropped[2], 91)]


def fitted_mesh(source, object_name, size=None):
    points, faces, uv = source.mesh(object_name)
    if size is not None and np.ptp(points[:, 2]) > np.ptp(points[:, 0]):
        points = points[:, [2, 1, 0]] * [-1, 1, 1]
    low, high = points.min(axis=0), points.max(axis=0)
    points -= (low + high) * 0.5
    if size is not None:
        points *= np.array(size) / (high - low)
    else:
        points[:, 1] += (high[1] - low[1]) * 0.5
    return points, faces, uv


def main():
    moss_name = "rock_moss_set_01"
    moss = SOURCE / f"{moss_name}_4k"
    moss_blend = Blend(moss / f"{moss_name}_4k.blend")
    maps = rock_maps(moss, moss_name)
    credit = "CC0 Rock Moss Set 01 by Kless Gyzen, Poly Haven"
    for name, suffix, size in (
        ("stone_round", "rock03", (0.135, 0.077, 0.099)),
        ("stone_flat", "rock02", (0.115, 0.036, 0.079)),
    ):
        points, faces, uv = fitted_mesh(moss_blend, f"{moss_name}_{suffix}", size)
        uv, images = mapped_crops(maps, uv, 512)
        vertices = corner_data(points, faces, uv)
        corners = [tuple(range(i, i + 3)) for i in range(0, len(vertices), 3)]
        PropFile().write(name, [[tuple(vertices[i] for i in face) for face in corners]], images, credit)
        if name == "stone_flat":
            with Image.open(ROOT / "coop/textures/rock_diff.jpg") as texture:
                gray = ImageEnhance.Contrast(ImageOps.grayscale(texture.resize((256, 256)))).enhance(0.75)
            fresh = ImageOps.colorize(gray, black="#504e4b", white="#c8c3b4")
            PropFile().write("stone_sharp", ground_edge(vertices, corners), [*images, jpeg(fresh)],
                             credit + "; CC0 Mossy Rock texture by Rob Tuytel, Poly Haven")

    boulder_name = "boulder_01"
    boulder = SOURCE / f"{boulder_name}_4k"
    points, faces, uv = fitted_mesh(Blend(boulder / f"{boulder_name}_4k.blend"), "boulder_01_LOD3")
    uv, images = mapped_crops(rock_maps(boulder, boulder_name), uv, 1024)
    vertices = corner_data(points, faces, uv)
    triangles = [tuple(vertices[i:i + 3]) for i in range(0, len(vertices), 3)]
    PropFile().write("shore_boulder", [triangles], images, "CC0 Boulder 01 by Rico Cilliers, Poly Haven")


if __name__ == "__main__":
    main()
