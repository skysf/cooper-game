"""Rebuild the lake's wave slopes, refracted sunlight and scanned bed textures.

The two photographic source JPEGs are verified against Poly Haven's 1K
River Small Rocks release. All three runtime textures are included in the game.
"""
from pathlib import Path
import hashlib
import subprocess

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'coop/textures'
CACHE = ROOT / '.cache'
SOURCE = 'https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/river_small_rocks/'


def gravel():
    for channel, digest, size in [('diff', '723ee7172c9d0e98d286473ef443033c', 768),
                                  ('nor_gl', 'e12850ba2aa71fe93a45ddd8ad03b6f4', 512)]:
        path = CACHE / f'lake-small-rocks-{channel}.jpg'
        if not path.exists() or hashlib.md5(path.read_bytes()).hexdigest() != digest:
            subprocess.run(['curl', '-fLsS', '--retry', '2', '-o', str(path),
                            SOURCE + f'river_small_rocks_{channel}_1k.jpg'], check=True)
        if hashlib.md5(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f'Unexpected source data in {path.name}')
        with Image.open(path) as photo:
            photo.convert('RGB').resize((size, size), Image.Resampling.LANCZOS).save(
                OUTPUT / f'lake_gravel_{channel}.jpg', quality=83, subsampling=0, optimize=True)


def wave_field():
    # Integration uses four samples per output texel in both dimensions.
    size, output_size = 1024, 256
    rng = np.random.default_rng(93172)
    y, x = np.indices((size, size), dtype=np.float32) / size
    slope = np.zeros((2, size, size), dtype=np.float32)
    for _ in range(56):
        angle = rng.normal(0.26, 0.59) if rng.random() < 0.73 else rng.uniform(0.0, np.pi)
        frequency = np.exp(rng.uniform(np.log(3.0), np.log(23.0)))
        kx, ky = np.rint(frequency * np.array([np.cos(angle), np.sin(angle)])).astype(int)
        magnitude = np.hypot(kx, ky)
        phase = np.cos(2.0 * np.pi * (kx * x + ky * y) + rng.uniform(0, 2.0 * np.pi))
        slope[0] += phase * (kx / magnitude)
        slope[1] += phase * (ky / magnitude)
    slope *= 0.105 / np.sqrt(np.mean(np.sum(slope * slope, axis=0)))

    # Refract parallel rays across the wave normals into freshwater (IOR 1.333).
    # Their hit density on a bed 1.75 metres below gives focusing and shadow bands.
    travel = (1.0 - 1.0 / 1.333) * 1.75 / 3.4
    hit_x = ((x + slope[0] * travel) * output_size).astype(int) % output_size
    hit_y = ((y + slope[1] * travel) * output_size).astype(int) % output_size
    count = np.bincount((hit_y * output_size + hit_x).ravel(), minlength=output_size**2)
    intensity = count.reshape(output_size, output_size) / (size / output_size) ** 2
    caustic = Image.fromarray((np.clip((intensity - 0.45) / 2.6, 0, 1) * 255).astype('uint8'))
    caustic = caustic.filter(ImageFilter.GaussianBlur(0.55))
    normal = np.clip(slope.reshape(2, output_size, 4, output_size, 4).mean(axis=(2, 4)) / 0.70 + 0.5, 0, 1)
    channels = [Image.fromarray((s * 255).astype('uint8')) for s in normal]
    Image.merge('RGB', (*channels, caustic)).save(OUTPUT / 'lake_ripples.png', optimize=True)


if __name__ == '__main__':
    CACHE.mkdir(exist_ok=True)
    gravel()
    wave_field()
