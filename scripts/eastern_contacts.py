"""Read contact geometry in Godot coordinates from the same streamed meshes the player sees."""
import json
import struct
from pathlib import Path

import numpy as np
from eastern_rock_mesh import read_attribute

TREES = ('grove_tree', 'crooked_tree', 'quiver_tree', 'fork_tree')
ROOT_MATS = ('bank_roots', 'tangled_roots', 'old_stump')
ROCKS = ('rock_shelf', 'granite_tor', 'weathered_rock', 'wood_rock')


def contact_meshes(path):
    raw = Path(path).read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20 + size])
    blob = memoryview(raw)[28 + size:]

    for node in doc['nodes']:
        name = node.get('name', '')
        if name.removesuffix('_far') not in (*TREES,*ROOT_MATS) and name not in ROCKS:
            continue
        # These exported prototypes have their transform baked into mesh space.
        assert not set(node).intersection(('matrix', 'translation', 'rotation', 'scale'))
        for prim in doc['meshes'][node['mesh']]['primitives']:
            mat = doc['materials'][prim['material']]
            if mat.get('alphaMode', 'OPAQUE') != 'OPAQUE':
                continue
            points = read_attribute(doc, blob, prim['attributes']['POSITION'])
            faces = read_attribute(doc, blob, prim['indices']).reshape(-1, 3)
            yield name, points, faces


def boundary_components(points, faces):
    # Weld only for measuring topology. UV seams in a glTF duplicate the same 3D point.
    _, unique, inverse = np.unique(points.round(4), axis=0, return_index=True, return_inverse=True)
    welded = inverse.reshape(-1)[faces]
    edges = np.concatenate([welded[:, [0, 1]], welded[:, [1, 2]], welded[:, [2, 0]]])
    edges, counts = np.unique(np.sort(edges, axis=1), axis=0, return_counts=True)
    neighbors = {}
    for a, b in edges[counts == 1]:
        neighbors.setdefault(a, []).append(b)
        neighbors.setdefault(b, []).append(a)
    while neighbors:
        stack = [next(iter(neighbors))]
        group = set()
        while stack:
            i = stack.pop()
            if i not in group:
                group.add(i)
                stack.extend(neighbors.pop(i, []))
        yield points[unique[list(group)]]


def build_contacts(asset_dir, output):
    roots = {key: [] for key in (*TREES,*ROOT_MATS)}
    triangles = {key: [] for key in ROCKS}
    for pack in ('verdant', 'namaqua'):
        for name, points, faces in contact_meshes(asset_dir / (pack + '.glb')):
            key = name.removesuffix('_far')
            if key in ROCKS:
                triangles[key].append(points[faces])
            elif points[:, 1].min() < .035:
                # The photographed trunk flares terminate in an oblique cut up to 73 cm
                # above the pivot. Both near and distant LOD rims must stay under soil.
                rims = [r for r in boundary_components(points, faces) if r[:, 1].min() < .04]
                roots[key].extend(rims or [points[points[:, 1] < .16]])
    profiles, footprints = {}, {}
    with (output / 'rock_faces.bin').open('wb') as file:
        for key, parts in triangles.items():
            tri = np.concatenate(parts)
            pts = tri.reshape(-1, 3)
            # A closed solid projects a connected silhouette for plant and trail clearance.
            footprint = np.unique(np.round(pts[:, [0, 2]] / .32).astype('i4'), axis=0) * .32
            footprints[key] = footprint
            normals = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
            tri = tri[np.abs(normals[:, 1]) > 1e-8]
            profiles[key] = {'first': file.tell() // 12, 'triangles': len(tri),
                             'min': pts.min(0).tolist(), 'max': pts.max(0).tolist()}
            tri.astype('<f4').tofile(file)
    (output / 'rock_profiles.json').write_text(json.dumps(profiles, separators=(',', ':')))
    roots = {key: np.unique(np.concatenate(parts).round(4),axis=0) for key,parts in roots.items()}
    (output/'root_contacts.json').write_text(json.dumps({key:np.round(rim.astype('f8'),4).tolist() for key,rim in roots.items()},separators=(',',':')))
    return roots, footprints
