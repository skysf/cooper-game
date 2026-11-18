"""Bake the d3-celestial XHIP stars.6.json catalog into the camp's galactic sky atlas."""

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image


WIDTH, HEIGHT = 4096, 2048
GALACTIC_AXES = ((266.4051, -28.936175), (318.0044, 48.32964), (192.85948, 27.12825))


def celestial_vector(ra, dec):
    ra, dec = math.radians(ra), math.radians(dec)
    return np.array((math.cos(ra) * math.cos(dec), math.sin(ra) * math.cos(dec), math.sin(dec)))


def star_color(bv):
    try:
        index = float(bv or 0.0)
    except (ValueError, TypeError):
        index = 0.55
    index = index if math.isfinite(index) else 0.55
    return np.array((
        np.interp(index, (-0.35, 0.4, 1.7), (0.72, 0.98, 1.0)),
        np.interp(index, (-0.35, 0.4, 1.7), (0.84, 0.97, 0.77)),
        np.interp(index, (-0.35, 0.4, 1.7), (1.0, 0.94, 0.56)),
    ))


def bake(catalog):
    atlas = np.zeros((HEIGHT, WIDTH, 3), dtype=np.float32)
    basis = np.array([celestial_vector(*axis) for axis in GALACTIC_AXES])
    for record in catalog["features"]:
        x, y, z = basis @ celestial_vector(*record["geometry"]["coordinates"])
        latitude = math.asin(float(np.clip(z, -1, 1)))
        u = (0.5 - math.atan2(y, x) / math.tau) * WIDTH - 0.5
        v = (0.5 - latitude / math.pi) * HEIGHT - 0.5
        mag = float(record["properties"]["mag"])
        strength = min(1.0, 10.0 ** (-0.175 * (mag + 1.44)))
        sigma_y = 0.53 + 0.56 * math.sqrt(strength)
        sigma_x = sigma_y / max(0.10, math.cos(latitude))
        xs = np.arange(math.floor(u - 3 * sigma_x), math.ceil(u + 3 * sigma_x) + 1)
        ys = np.arange(max(0, math.floor(v - 3 * sigma_y)), min(HEIGHT, math.ceil(v + 3 * sigma_y) + 1))
        profile = np.exp(-0.5 * (((xs - u) / sigma_x) ** 2 + ((ys[:, None] - v) / sigma_y) ** 2))
        color = strength * star_color(record["properties"].get("bv"))
        atlas[ys[:, None], xs % WIDTH] += profile[..., None] * color
    return Image.fromarray(np.rint(np.clip(atlas, 0.0, 1.0) * 255).astype(np.uint8))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("catalog", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "coop/textures/milky_way_stars.png")
    args = parser.parse_args()
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    bake(catalog).save(args.output, optimize=True)
    print(f"Baked {len(catalog['features'])} stars to {args.output}")


if __name__ == "__main__":
    main()
