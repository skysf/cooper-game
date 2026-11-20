"""Generate the shared elevation field and the render meshes for the west coast."""
import json
from pathlib import Path
import runpy

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "coop/coast"
LAYOUT = json.loads((ROOT / "coop/coast_layout.json").read_text())
LAKE = json.loads((ROOT / "coop/water_layout.json").read_text())
SEA = LAKE["waterY"]
STEP = LAYOUT["spacing"]
CELLS_X, CELLS_Z = LAYOUT["cells"]
X0, Z0 = LAYOUT["origin"]
X1, Z1 = X0 + STEP * CELLS_X, Z0 + STEP * CELLS_Z
TILE = 32


def smooth(lo, hi, value):
    t = np.clip((value - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def gaussian(x, width):
    return np.exp(-np.square(x / width))


def noise(x, z):
    """Broad damp-rock and growth patches, with a second irregular scale."""
    return (np.sin(x * .23 + 1.9 * np.sin(z * .16)) * np.cos(z * .28 - .2)
            + .44 * np.sin(x * .54 + z * .45 + 1.8)
            + .23 * np.cos(x * 1.07 - z * .85)) / 1.67


def around_lake(x, z):
    lx = (x - LAKE["center"][0]) / LAKE["radius"][0]
    lz = (z - LAKE["center"][1]) / LAKE["radius"][1]
    angle = np.arctan2(lz, lx)
    edge = 1 + .047 * np.sin(angle * 3 + .9) + .025 * np.cos(angle * 5 + .4) + .018 * np.sin(angle * 9 + .3)
    return np.hypot(lx, lz) / edge


def route_field(x, z, points):
    distance = np.full(x.shape, np.inf)
    height = np.zeros(x.shape)
    for start, end in zip(points, points[1:]):
        dx, dz = end[0] - start[0], end[1] - start[1]
        t = np.clip(((x - start[0]) * dx + (z - start[1]) * dz) / (dx * dx + dz * dz), 0, 1)
        length = np.square(x - start[0] - dx * t) + np.square(z - start[1] - dz * t)
        nearest = length < distance
        height = np.where(nearest, start[2] + t * (end[2] - start[2]), height)
        distance = np.minimum(distance, length)
    return np.sqrt(distance), height


def geography(x, z):
    u, v = -x, z + 52
    mottling = noise(u * .73, z * .78)
    shore = (84.7 + 17.7 * (1 - gaussian(v, 24))
             + 13.2 * gaussian(v + 27, 9.2) + 16.6 * gaussian(v - 28, 8.6)
             + 1.37 * np.sin(v * .21) + 1.3 * mottling
             + smooth(8.0, 23.0, np.abs(v)) * (1.19 * np.sin(v * .68) + .67 * np.cos(v * 1.30)))
    shore_distance = shore - u
    reefline = 125.0 + 4.1 * np.sin(v * .083 + .2) + 1.65 * np.cos(v * .231)
    reef_distance = u - reefline
    water_distance = np.maximum(-shore_distance, 0)
    shallow_slope = .144 + .055 * gaussian(v - 1.8, 16.0)
    basin = np.minimum(water_distance * shallow_slope, 5.7)
    channel = gaussian(u - 110.0 - 2.2 * np.sin(v * .22), 9) * gaussian(v - 2.2, 9)
    plate = noise(u * .73 + 8.1 * np.sin(v * .065), z * .65)
    grain = noise(u * 3.10 + v * .68, z * 3.27)
    coral = smooth(-.19, .57, plate + .34 * grain)
    coral *= smooth(3, 10, water_distance) * (1 - smooth(-4.0, 8.0, reef_distance))
    coral *= .75 + .25 * np.sin(v * .22 + u * .29)
    crest = gaussian(reef_distance, 4.5) * (.74 + .19 * noise(u * .67, z * .53))
    crest *= smooth(2.0, 8.0, water_distance)
    seabed = SEA - basin - channel * 1.08
    seabed -= 1.4 * smooth(2.0, 10.0, reef_distance) + 15.9 * smooth(6.0, 44.0, reef_distance)
    seabed += (basin - .78 + mottling * .25) * crest + coral * (.37 + .43 * (grain + 1.0))
    seabed += .33 * mottling * smooth(1.0, 4.8, water_distance)

    headland = smooth(11.0, 32.0, np.abs(v))
    schist = noise(u * .61, z * .79)
    # Use gently tilted plates and a second fault direction to break the lip of the bluff.
    shale = .5 * np.sin(z * .50 + u * .41) + .31 * np.sin(z * 1.26 - u * .36)
    fracture = np.sin(v * .64 + u * .37 + schist * 1.8) * (1.4 + headland * .6)
    lip = shore_distance + (schist * 1.84 + shale * .91 + fracture) * smooth(0, 5, shore_distance)
    cliff = smooth(4.4 - 3.5 * headland, 11.9 - 4.8 * headland, lip)
    rise = smooth(39.0, 71.0, u)
    ridge = 15.6 + headland * 4.8 + 2.5 * mottling + 2.1 * np.sin(v * .062 + u * .035)
    inland = (ridge * cliff + .13 * np.minimum(15.0, np.maximum(0.0, shore_distance))) * rise + SEA
    exposed = np.sqrt(np.maximum(0, cliff * (1 - cliff) * 4))
    shelves = np.sin(inland * 1.39 + v * .41 + np.sin(v * .36) * 1.45)
    inland += (.64 * schist + .79 * shale + shelves * .64) * exposed
    inland += .65 * mottling * smooth(35, 62, u) * smooth(0, 10, shore_distance)
    lake_distance = around_lake(x, z)
    lake_floor = np.where(lake_distance < 1, SEA - 2.35 * np.clip(1 - lake_distance, 0, 1),
                          SEA * (1 - smooth(1, 1.08, lake_distance)))
    joined_land = lake_floor * (1 - smooth(38, 47, u)) + inland * smooth(38, 47, u)
    ground = np.where(shore_distance >= 0, joined_land, seabed)

    # The island has a low sand spit on the bay-facing side and two higher ridges.
    iw = u - 187.1
    iv = z + 58.5
    skew_z = iv + .28 * iw
    angle = np.arctan2(skew_z / 13.3, iw / 20.9)
    rim = 1 + .09 * np.sin(angle * 3 - .2) + .067 * np.cos(angle * 5 + .8) + .043 * np.sin(angle * 8)
    radius = np.hypot(iw / 20.9, skew_z / 13.3) / rim
    island_gain = smooth(1.0, .46, radius)
    twin_ridge = 4.1 * gaussian(iw + 3.0, 8.9) * gaussian(iv - 1.45, 7.6)
    twin_ridge += 5.3 * gaussian(iw - 6.5, 7.5) * gaussian(iv + 1.8, 5.6)
    island = SEA + (4.8 + twin_ridge + 1.78 * mottling) * island_gain
    island += .51 * schist * island_gain * smooth(.0, 5.0, iw + 10)
    island_shelf = SEA - np.maximum(0, radius - 1) * 11.0 - 3.7 * smooth(1.2, 2.0, radius)
    island_shelf = island_shelf * (1 - smooth(1.85, 2.75, radius)) + ground * smooth(1.85, 2.75, radius)
    ground = np.maximum(ground, np.where(radius <= 1, island, island_shelf))

    trails = []
    ridge_distance, _ridge_grade = route_field(x, z, LAYOUT["ridgeTrail"])
    for name in ("ridgeTrail", "beachTrail", "islandTrail"):
        distance, grade = route_field(x, z, LAYOUT[name])
        width = 5.8 if name == "beachTrail" else 4.7
        mix = (1 - smooth(1.22, width, distance)) * smooth(30.0, 35.0, u)
        if name == "beachTrail":
            mix *= smooth(.69, 2.37, ridge_distance)
        ground = ground * (1 - mix) + grade * mix
        trails.append(1 - smooth(.63, 1.67, distance))
    path = np.maximum.reduce(trails)
    # The important sand is the pale shelf at the cliff's foot. Headland and
    # outer reef masks stay coarse so the scanned texture can vary at human scale.
    sand = (1 - smooth(.95, 4.7, ground)) * (1 - smooth(.24, .86, coral))
    sand *= 1 - .72 * headland * gaussian(shore_distance, 7.0)
    sand = np.maximum(sand, (1 - smooth(.3, 2.5, ground)) * gaussian(radius - 1.0, .23))
    sand *= 1 - smooth(13, 38, -ground)
    lichen = .23 + .57 * smooth(-.68, .59, mottling + .31 * schist)
    shrub = smooth(1.6, 10.0, ground) * smooth(-.53, .46, mottling + .27 * shale + .19 * grain)
    return ground, sand, shrub, lichen, path, coral, crest, lake_distance, radius


def bake_mesh(chunk, x, z, label, *, floor_field=None):
    ground, sand, shrub, lichen, path, coral, _crest, lake, _island = geography(x, z)
    if floor_field is not None:
        ground = floor_field
    step_x, step_z = x[0, 1] - x[0, 0], z[1, 0] - z[0, 0]
    dx = (geography(x + .19, z)[0] - geography(x - .19, z)[0]) / .38
    dz = (geography(x, z + .19)[0] - geography(x, z - .19)[0]) / .38
    slope = np.hypot(dx, dz)
    shrub *= 1 - smooth(.53, 1.45, slope)
    shrub = np.maximum(shrub, .24 * (1 - smooth(37, 65, -x)))
    sand *= 1 - .96 * smooth(.26, 1.06, slope)
    green = np.clip(shrub + lichen * (1 - smooth(.8, 2.3, slope)) * .27, 0, 1)
    green *= smooth(.32, 4.0, ground) * (1 - path)
    variation = .49 + .46 * noise(x * .56, z * .63) - .27 * coral
    weights = np.stack([sand, green, path, variation], axis=-1).reshape(-1, 4)
    normals = np.stack([-dx, np.ones_like(dx), -dz], axis=-1)
    normals /= np.linalg.norm(normals, axis=-1, keepdims=True)
    attrs = {
        "POSITION": np.stack([x, ground, z], axis=-1).reshape(-1, 3).astype(np.float32),
        "NORMAL": normals.reshape(-1, 3).astype(np.float32),
        "COLOR_0": (np.clip(weights, 0, 1) * 255).astype(np.uint8),
    }
    cells_z, cells_x = x.shape[0] - 1, x.shape[1] - 1
    for row in range(0, cells_z, TILE):
        for col in range(0, cells_x, TILE):
            j, i = np.mgrid[row:min(row+TILE,cells_z), col:min(col+TILE,cells_x)]
            base = (j * x.shape[1] + i).ravel()
            right, down = base + 1, base + x.shape[1]
            triangles = np.stack([base, down, right, right, down, down + 1], axis=1).reshape(-1, 3)
            visible = np.min(lake.ravel()[triangles], axis=1) >= .992
            chunk.mesh(f"{label}_{row//TILE}_{col//TILE}", attrs, triangles[visible])


def sandbar_texture(x, z, geo):
    ground, sand, _green, _lichen, _path, coral, reef, _lake, _island = geo
    depth = np.maximum(SEA - ground, 0)
    shore = gaussian(depth - .26, .28) * smooth(.008, .10, depth)
    in_sea = smooth(78, 83, -x)
    reef_surface = np.maximum(coral * 0.89, (1.0 - sand) * 0.62)
    fields = np.stack([np.clip(depth / 28.0, 0, 1), reef * in_sea, shore * in_sea, reef_surface], axis=-1)
    # Match grid texel centers to the physical sampling coordinates.
    Image.fromarray((np.clip(fields, 0, 1) * 255 + .5).astype(np.uint8)).save(OUT / "tide_field.png")


def shrubs_and_trees(x, z, geo):
    rng = np.random.default_rng(44931)
    ground, _sand, green, _lichen, path, _reef, _crest, lake, radius = geo
    slope_z, slope_x = np.gradient(ground, STEP)
    slope = np.hypot(slope_x, slope_z)
    route_distance = np.minimum.reduce([route_field(x, z, LAYOUT[name])[0]
                                        for name in ("ridgeTrail", "beachTrail", "islandTrail")])
    allowed = ((ground > .6) | ((ground >= -.03) & (-x < 49))) & (path < .26) & (slope < 1.18) & (lake > 1.09)
    trees, shrubs, stones, crags = [], [], [], []
    # Small patches of salt-pruned trees run down the sheltered portion of the
    # route. Bushes cling to sheltered ledges and break up the edge of the rock.
    for j in range(1, x.shape[0] - 1, 3):
        for i in range(1, x.shape[1] - 1, 3):
            if not allowed[j, i]:
                continue
            west = -x[j, i]
            if 33 < west < 72 and rng.random() < .105 + green[j, i] * .23:
                trees.append([x[j,i], z[j,i], rng.uniform(2.9, 7.8), rng.random()])
            elif radius[j, i] < .88 and ground[j, i] > 2.6 and rng.random() < .22:
                trees.append([x[j,i], z[j,i], rng.uniform(2.4, 4.5), rng.random()])
    for j in range(1, x.shape[0] - 1, 2):
        for i in range(1, x.shape[1] - 1, 2):
            if allowed[j, i] and (-x[j, i] > 49) and rng.random() < green[j, i] * .67:
                shrubs.append([x[j,i], z[j,i], rng.uniform(.37, 1.35), rng.random()])
    for j in range(1, x.shape[0] - 1, 4):
        for i in range(1, x.shape[1] - 1, 4):
            if -x[j,i] > 64 and -.08 < ground[j,i] < 5.0 and slope[j,i] > .26 and path[j,i] < .1:
                if rng.random() < .33:
                    stones.append([x[j,i],z[j,i],rng.uniform(.28, 1.12),rng.random()])
    for j in range(13, x.shape[0] - 12, 4):
        for i in range(3, x.shape[1] - 4, 4):
            if -123 < x[j, i] < -76 and 1.3 < ground[j, i] < 14.4 and slope[j, i] > 1.37 and route_distance[j, i] > 4.4:
                if rng.random() < .44:
                    crags.append([x[j,i], z[j,i], rng.uniform(1.8, 4.15), rng.random()])
    placement = {name: np.round(values, 3).tolist() for name, values in
                 (("trees", trees), ("shrubs", shrubs), ("stones", stones), ("crags", crags))}
    (OUT / "foliage.json").write_text(json.dumps(placement, separators=(",", ":")) + "\n")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    chunk_type = runpy.run_path(str(ROOT / "scripts/coop-zones.py"))["Chunk"]
    terrain = chunk_type()
    x, z = np.meshgrid(np.linspace(X0, X1, CELLS_X + 1), np.linspace(Z0, Z1, CELLS_Z + 1))
    geo = geography(x,z)
    height = geo[0].astype("<f4")
    height.tofile(OUT / "elevation.bin")
    sandbar_texture(x, z, geo)
    shrubs_and_trees(x, z, geo)
    bake_mesh(terrain, x, z, "Coast", floor_field=height)
    for name, lo, hi in [("North", -287, Z0), ("South", Z1, 181)]:
        side_x, side_z = np.meshgrid(np.linspace(X0, X1, 97), np.linspace(lo, hi, 56))
        bake_mesh(terrain, side_x, side_z, name)
    size = terrain.write("headlands", OUT)
    print(f"Coast, {CELLS_X} by {CELLS_Z} elevation cells, {size:,} bytes of spatially culled terrain.")


if __name__ == "__main__":
    main()
