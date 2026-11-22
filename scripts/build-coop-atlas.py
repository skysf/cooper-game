"""Draw the field atlas from the room's terrain, water, forest, and trail data."""

from pathlib import Path
import json
import runpy

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
COOP = ROOT / "coop"
COAST = json.loads((COOP / "coast_layout.json").read_text())
WORLD = json.loads((COOP / "world.json").read_text())
WATER = json.loads((COOP / "water_layout.json").read_text())
FOLIAGE = json.loads((COOP / "coast/foliage.json").read_text())
GEOGRAPHY = runpy.run_path(str(ROOT / "scripts/build-coast.py"))
REGION = json.loads((COOP/"east/region.json").read_text())
WEST, EAST = COAST["westLimit"], REGION["eastLimit"]
NORTH, SOUTH = -119, 12
WIDTH = 3072
HEIGHT = round(WIDTH * (SOUTH - NORTH) / (EAST - WEST))
RNG = np.random.default_rng(78421)


def elevation(x, z, lake):
    columns, rows = COAST["cells"]
    origin_x, origin_z = COAST["origin"]
    spacing = COAST["spacing"]
    gx = np.clip((x - origin_x) / spacing, 0, columns)
    gz = np.clip((z - origin_z) / spacing, 0, rows)
    ix = np.minimum(gx.astype(int), columns - 1)
    iz = np.minimum(gz.astype(int), rows - 1)
    fx, fz = gx - ix, gz - iz
    field = np.fromfile(COOP / "coast/elevation.bin", dtype="<f4").reshape(rows + 1, columns + 1)
    a, b, c, d = field[iz, ix], field[iz, ix + 1], field[iz + 1, ix], field[iz + 1, ix + 1]
    terrain = np.where(fx + fz <= 1, a + (b - a) * fx + (c - a) * fz,
                       d + (c - d) * (1 - fx) + (b - d) * (1 - fz))
    lake_bed = np.where(lake < 1, WATER["waterY"] - 2.35 * np.clip(1 - lake, 0, 1), 0)
    columns, rows = REGION["cells"]
    ox, oz = REGION["origin"]
    eastern = np.fromfile(COOP/"east/elevation.bin",dtype="<f4").reshape(rows+1,columns+1)
    east_y = eastern[np.clip(np.rint(z-oz).astype(int),0,rows),np.clip(np.rint(x-ox).astype(int),0,columns)]
    return np.where(x >= ox,east_y,np.where(x < -30, terrain, lake_bed))


def creek_mask(x, z):
    creek = WATER["creek"]
    indices = np.arange(creek["steps"] + 1)
    at = (z - creek["firstZ"]) / creek["spacing"]
    center = np.interp(at, indices, -11.4 + np.sin(indices * .22) * 2.1 + np.cos(indices * .47) * .38)
    radius = np.interp(at, indices, .16 + np.sin(np.pi * indices / creek["steps"]) * 1.13)
    return (np.abs(x - center) <= radius) & (at >= 0) & (at <= creek["steps"])


def texture(scale):
    noise = RNG.integers(0, 256, (HEIGHT // scale + 2, WIDTH // scale + 2), dtype=np.uint8)
    return np.asarray(Image.fromarray(noise).resize((WIDTH, HEIGHT), Image.Resampling.BICUBIC)) / 127.5 - 1.0


def mix(a, b, factor):
    amount = factor[..., None]
    return np.asarray(a) * (1 - amount) + np.asarray(b) * amount


def project(x, z):
    return (x - WEST) * WIDTH / (EAST - WEST), (z - NORTH) * HEIGHT / (SOUTH - NORTH)


def paint_terrain():
    x, z = np.meshgrid(np.linspace(WEST, EAST, WIDTH), np.linspace(NORTH, SOUTH, HEIGHT))
    lake = GEOGRAPHY["around_lake"](x, z)
    y = elevation(x, z, lake)
    sea = WATER["waterY"]
    wet = ((x <= COAST["seaEast"]) & (y < sea)) | (lake < 1) | creek_mask(x, z)
    sea_depth = np.maximum(0, sea - y)
    dz, dx = np.gradient(y, (SOUTH - NORTH) / HEIGHT, (EAST - WEST) / WIDTH)
    slope = np.hypot(dx, dz)
    light = np.clip((.32 * dx + .28 * dz) / np.sqrt(1 + slope * slope), -.40, .40)
    mottling = texture(46)
    dry = mix([170, 175, 121], [209, 195, 151], np.clip(y / 39 + .24 + mottling * .11, 0, 1))
    dry = mix(dry, [147, 121, 96], np.clip((slope - .30) / 1.45, 0, .61))
    dry += (light * 27)[..., None]
    shallows = np.clip(sea_depth / 21, 0, 1)
    water = mix([131, 167, 159], [189, 204, 184], shallows ** .62)
    water = np.where((lake < 1)[..., None], mix([132, 166, 155], [103, 143, 143], np.clip((1 - lake) * .9, 0, 1)), water)
    ink = np.minimum(.9, 1 - np.abs(np.mod(y + 1.25, 2.5) - 1.25) / np.maximum(.05, slope * .15))
    contour = np.clip(ink, 0, 1) * np.clip(slope / .24, 0, 1)
    shoreline = np.clip(1 - np.abs(y - sea) / .55, 0, 1) * (x < COAST["seaEast"])
    atlas = mix(np.where(wet[..., None], water, dry), [67, 86, 74], contour * .15 + shoreline * .23)
    atlas += (3.8 * texture(12) + 2.6 * mottling + RNG.normal(0, 1.3, y.shape))[..., None]
    return Image.fromarray(np.uint8(np.clip(atlas, 0, 255)))


def draw_features(image):
    trees = [(p["x"], p["z"], p["r"] * 4 + .5) for p in WORLD["obstacles"] if p["type"] == "tree"]
    trees += [(p[0], p[1], p[2] * .26) for p in FOLIAGE["trees"]]
    eastern_plants = json.loads((COOP/"east/plants.json").read_text())
    trees += [(p[0],p[2],p[4]*1.2) for key in ("grove_tree","crooked_tree","quiver_tree","fork_tree") for p in eastern_plants[key]]
    forest = Image.new("RGBA", image.size)
    ink = ImageDraw.Draw(forest)
    for x, z, radius in trees:
        u, v = project(x, z)
        height = 3 + radius * 2.1
        ink.line([(u, v-height), (u-height*.65, v+1), (u-height*.28, v+1),
                  (u-height*.72, v+height*.45), (u+height*.72, v+height*.45),
                  (u+height*.28, v+1), (u+height*.65, v+1), (u, v-height)], fill=(63, 84, 63, 114), width=1)
    image = Image.alpha_composite(image.convert("RGBA"), forest).convert("RGB")
    drawn = ImageDraw.Draw(image)
    trails = [[(p[1], p[2]) for p in WORLD["route"]]]
    trails.extend([[(p[0], p[1]) for p in COAST[key]] for key in ("ridgeTrail", "beachTrail", "islandTrail")])
    trails.append([(1.9, -85), (-3.5, -80.5), (-8, -80.5), (-9.5, -78), (-11.5, -75), (-13.5, -73.5), COAST["entry"]])
    trails.extend(REGION["trails"])
    for trail in trails:
        track = [project(x, z) for x, z in trail]
        drawn.line(track, fill="#a7a27a", width=7, joint="curve")
        drawn.line(track, fill="#795f44", width=3, joint="curve")
    for a, b in zip([COAST["beach"], COAST["reef"]], [COAST["reef"], COAST["landing"]]):
        start, end = np.array(project(*a)), np.array(project(*b))
        length = float(np.linalg.norm(end - start))
        along = (end - start) / length
        for offset in range(0, int(length), 15):
            drawn.line([tuple(start + offset * along), tuple(start + min(length, offset + 7) * along)], fill="#476b69", width=3)
    camp = WORLD["shelter"]
    drawn.rectangle((*project(camp["x"] - camp["width"] / 2, camp["z"] - camp["depth"] / 2),
                     *project(camp["x"] + camp["width"] / 2, camp["z"] + camp["depth"] / 2)), fill="#886d4f")
    dock = WATER["dock"]
    drawn.rectangle((*project(dock["west"], dock["z"] - dock["halfWidth"]),
                     *project(dock["east"], dock["z"] + dock["halfWidth"])), fill="#947957")
    return image


if __name__ == "__main__":
    draw_features(paint_terrain()).save(COOP / "coast/field_atlas.webp", quality=90, method=6)
