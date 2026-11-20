"""Verify the installed fern positions against the generated creek surface."""

import json
import math
from pathlib import Path
import struct

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
WORLD = json.loads((ROOT / 'coop/world.json').read_text())
LAYOUT = json.loads((ROOT / 'coop/water_layout.json').read_text())
WATER = LAYOUT['waterY']
DOCK = LAYOUT['dock']
CREEK = LAYOUT['creek']
WOOD = WORLD['sites']['wood']
SHORE_BUFFER = 0.07
SIZE = {'mature': 0.57, 'young': 0.47}
MAX_WIND = 0.115
PLANTS = LAYOUT['lakesideVegetation']['ostrichFern']


def horizontal_section(z):
    index = (z - CREEK['firstZ']) / CREEK['spacing']
    low, high = math.floor(index), math.ceil(index)

    def center(i):
        return -11.4 + math.sin(i * .22) * 2.1 + math.cos(i * .47) * .38

    def halfwidth(i):
        return .16 + math.sin(math.pi * i / CREEK['steps']) * 1.13

    def interpolate(source):
        return source(low) + (source(high) - source(low)) * (index - low)

    return interpolate(center), interpolate(halfwidth)


def distance_lake(x, z):
    local = (np.array([x, z]) - LAYOUT['center']) / LAYOUT['radius']
    angle = math.atan2(local[1], local[0])
    shore = 1 + .047 * math.sin(angle * 3 + .9) + .025 * math.cos(angle * 5 + .4) + .018 * math.sin(angle * 9 + .3)
    return float(np.linalg.norm(local)) / shore


def segment_distance(xz, first, second):
    direction = second - first
    along = float(np.clip(np.dot(xz - first, direction) / np.dot(direction, direction), 0., 1.))
    return float(np.linalg.norm(xz - first - along * direction))


def read_terrain(filename):
    """Read the real world-space forest floor triangles in a produced creek chunk."""
    raw = filename.read_bytes()
    json_length = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20 + json_length])
    binary = 28 + json_length

    def accessor(index):
        access = document['accessors'][index]
        view = document['bufferViews'][access['bufferView']]
        offset = binary + view.get('byteOffset', 0) + access.get('byteOffset', 0)
        columns = {'SCALAR': 1, 'VEC3': 3}[access['type']]
        dtype = {5123: '<u2', 5125: '<u4', 5126: '<f4'}[access['componentType']]
        return np.frombuffer(raw, dtype=dtype, offset=offset, count=access['count'] * columns).reshape(-1, columns)

    triangles = []
    for node in document['nodes']:
        if not node['name'].startswith(('forest_floor', 'mud')):
            continue
        assert all(key not in node for key in ('matrix', 'translation', 'rotation', 'scale'))
        for surface in document['meshes'][node['mesh']]['primitives']:
            xyz = accessor(surface['attributes']['POSITION'])
            ids = accessor(surface['indices']).reshape(-1, 3)
            tri = xyz[ids]
            keep = (tri[:, :, 0].max(axis=1) >= -17.0) & (tri[:, :, 0].min(axis=1) <= -6.0)
            triangles.append(tri[keep])
    return np.concatenate(triangles).astype(np.float64)


TRIS = np.concatenate([read_terrain(ROOT / f'dist/coop-atlas/zones/{chunk}.glb') for chunk in ('creek', 'crossing')])
P0 = TRIS[:, 0]
D1 = TRIS[:, 1] - P0
D2 = TRIS[:, 2] - P0
DENOMINATOR = D1[:, 0] * D2[:, 2] - D1[:, 2] * D2[:, 0]
ROUTE = np.array([p[1:] for p in WORLD['route']])
OBSTACLES = [(np.array([o['x'], o['z']]), float(o['r']), o['type']) for o in WORLD['obstacles']]
HAZELS = [(np.array(p[:2]), p[2] * .66) for p in LAYOUT.get('lakesideVegetation', {}).get('hazel', [])]


def terrain_height(x, z):
    dx, dz = x - P0[:, 0], z - P0[:, 2]
    a = (dx * D2[:, 2] - dz * D2[:, 0]) / DENOMINATOR
    b = (dz * D1[:, 0] - dx * D1[:, 2]) / DENOMINATOR
    inside = (a >= -1e-6) & (b >= -1e-6) & (a + b <= 1 + 1e-6)
    if not inside.any():
        return None
    return float(np.max(P0[inside, 1] + a[inside] * D1[inside, 1] + b[inside] * D2[inside, 1]))


def measure(x, z, variant, scale):
    center, surface_halfwidth = horizontal_section(z)
    extent = SIZE[variant] * scale + MAX_WIND
    at = np.array([x, z])
    bank = abs(x - center) - surface_halfwidth
    lake = distance_lake(x, z)
    y = terrain_height(x, z)
    shore = min(distance_lake(*(at + np.array([math.cos(angle), math.sin(angle)]) * extent)) for angle in np.linspace(0., math.tau, 17))
    route = min(segment_distance(at, a, b) for a, b in zip(ROUTE[:-1], ROUTE[1:])) - extent
    dock_end = math.hypot(max(0., DOCK['west'] - x, x - DOCK['east']),
                          max(0., abs(z - DOCK['z']) - DOCK['halfWidth']))
    support_lane = segment_distance(at, np.array([DOCK['east'], DOCK['z']]), np.array([-6.7, DOCK['z']]))
    rock_or_tree, obstacle_type = min((float(np.linalg.norm(at - center)) - radius - extent, kind) for center, radius, kind in OBSTACLES)
    hazel = min(float(np.linalg.norm(at - center)) - radius - extent for center, radius in HAZELS)
    wood_gap = segment_distance(at, np.array(WOOD), np.array([-6.7, -53.0])) - extent
    east = terrain_height(x + .1, z) - terrain_height(x - .1, z)
    south = terrain_height(x, z + .1) - terrain_height(x, z - .1)
    first = max(z - .95, CREEK['firstZ'])
    last = min(z + .95, CREEK['firstZ'] + CREEK['spacing'] * CREEK['steps'])
    centerline = [np.array([horizontal_section(q)[0], q]) for q in np.linspace(first, last, 11)]
    from_channel = min(segment_distance(at, a, b) for a, b in zip(centerline[:-1], centerline[1:])) - extent
    return {
        'ground': y, 'above_water': y - WATER, 'from_creek_surface': bank, 'lake_distance': lake,
        'canopy_lake_distance': shore, 'clear_creek_center': from_channel,
        'slope': math.hypot(east, south) / .2, 'main_trail': route,
        'dock_and_approach': min(dock_end, support_lane) - extent,
        'wood_pile_access': wood_gap, 'tree_or_rock': rock_or_tree,
        'nearest_obstacle_type': obstacle_type, 'hazel': hazel, 'maximum_extent': extent
    }


def viable(site):
    return (site['above_water'] >= .031 and SHORE_BUFFER <= site['from_creek_surface'] <= .85
            and site['slope'] < .25 and site['lake_distance'] > 1.018
            and site['clear_creek_center'] > .30 and site['canopy_lake_distance'] >= 1.0
            and site['main_trail'] > 1.95 and site['dock_and_approach'] > .92
            and site['wood_pile_access'] > 1.22 and site['tree_or_rock'] > .08
            and site['hazel'] > 0.0)


def verify_planting():
    report = []
    for spec in PLANTS:
        x, z, scale, _, variant, ground = spec
        metrics = measure(x, z, variant, scale)
        assert viable(metrics), ((x, z), metrics)
        assert abs(ground - metrics['ground']) < .00001, (x, z, ground, metrics['ground'])
        report.append({'planting': spec, 'site': {k: round(v, 5) if isinstance(v, float) else v for k, v in metrics.items()}})
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    verify_planting()
