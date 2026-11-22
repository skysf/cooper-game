"""Bake the room's collision columns from the same metric GLB used by the coast scene."""
import filecmp
import json
import shutil
import struct

import numpy as np
from eastern_rock_mesh import read_attribute


def vertical_limits(triangles, origin, shape, step):
    """Intersect vertical rays at grid vertices with each projected triangle."""
    depth, width = shape
    bottom = np.full(depth * width, np.inf, dtype="f4")
    top = -bottom.copy()
    for first in range(0, len(triangles), 256):
        tri = triangles[first:first + 256].astype("f8")
        grid = (tri[:, :, [0, 2]] - origin) / step
        low = np.ceil(grid.min(axis=1) - 1e-7).astype(int)
        high = np.floor(grid.max(axis=1) + 1e-7).astype(int)
        sizes = np.maximum(0, high - low + 1)
        counts = sizes[:, 0] * sizes[:, 1]
        ids = np.repeat(np.arange(len(tri)), counts)
        offsets = np.arange(len(ids)) - np.repeat(np.cumsum(counts) - counts, counts)
        x = low[ids, 0] + offsets % sizes[ids, 0]
        z = low[ids, 1] + offsets // sizes[ids, 0]
        b, c = grid[:, 1] - grid[:, 0], grid[:, 2] - grid[:, 0]
        dx, dz = x - grid[ids, 0, 0], z - grid[ids, 0, 1]
        det = (b[:, 0] * c[:, 1] - b[:, 1] * c[:, 0])[ids]
        with np.errstate(invalid="ignore", divide="ignore"):
            u = (dx * c[ids, 1] - dz * c[ids, 0]) / det
            v = (b[ids, 0] * dz - b[ids, 1] * dx) / det
        hit = (abs(det) > 1e-9) & (u >= -1e-7) & (v >= -1e-7) & (u + v <= 1.0000001)
        faces = tri[ids[hit], :, 1]
        y = faces[:, 0] + u[hit] * (faces[:, 1] - faces[:, 0]) + v[hit] * (faces[:, 2] - faces[:, 0])
        pixels = z[hit] * width + x[hit]
        np.minimum.at(bottom, pixels, y)
        np.maximum.at(top, pixels, y)
    return bottom, top


def bake(root, out):
    source = root / "art/landmarks/leshan_buddha/leshan_buddha.glb"
    model = out / source.name
    if not model.exists() or not filecmp.cmp(source, model, shallow=False):
        shutil.copyfile(source, model)
    raw = model.read_bytes()
    size = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + size])
    blob = memoryview(raw)[28 + size:]
    solids = []
    for node in doc["nodes"]:
        if set(node).intersection(("matrix", "scale", "rotation", "translation")):
            raise ValueError("Bake object transforms into the metric landmark before export")
        if "mesh" in node:
            parts = []
            for prim in doc["meshes"][node["mesh"]]["primitives"]:
                vertices = read_attribute(doc, blob, prim["attributes"]["POSITION"])
                indices = read_attribute(doc, blob, prim["indices"])
                parts.append(vertices[indices.reshape(-1, 3)])
            solids.append(np.concatenate(parts))

    step = .125
    vertices = np.concatenate(solids).reshape(-1, 3)[:, [0, 2]]
    origin = np.floor(vertices.min(axis=0)) - 1
    width, depth = (np.ceil((vertices.max(axis=0) - origin) / step).astype(int) + 2)
    limits = [vertical_limits(tri, origin, (depth, width), step) for tri in solids]
    bottoms, tops = np.asarray(limits).transpose(1, 0, 2)
    order = np.argsort(bottoms, axis=0)
    bottoms, tops = (np.take_along_axis(values, order, axis=0) for values in (bottoms, tops))
    pixel_count = width * depth
    layer = np.full(pixel_count, -1)
    last = np.full(pixel_count, -np.inf)
    layers = []
    for low, high in zip(bottoms, tops):
        hits = np.isfinite(low)
        new = hits & (low > last + .025)
        layer[new] += 1
        while len(layers) <= layer.max():
            layers.append(np.full((pixel_count, 2), 32767, dtype="<i2"))
        last = np.where(new, high, np.maximum(last, high))
        for i, spans in enumerate(layers):
            starts, updates = new & (layer == i), hits & (layer == i)
            spans[starts, 0] = np.rint(low[starts] * 100)
            spans[updates, 1] = np.rint(last[updates] * 100)
    with (out / "buddha_contact.bin").open("wb") as f:
        f.write(struct.pack("<6i", width, depth, len(layers), round(step * 1000), *np.rint(origin * 1000).astype(int)))
        np.stack(layers, axis=1).tofile(f)
