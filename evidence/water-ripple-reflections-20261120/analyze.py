"""Compare fixed render pixels by distance to the real y=-0.075 water plane."""

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image


WATERLINE = -.075
WIDTH, HEIGHT = 1280, 720
FOCAL = math.tan(math.radians(78.0) * .5)
LUMA = np.array([.2126, .7152, .0722])


def image(where, shot, version):
    with Image.open(where / f'{shot}-{version}.png') as handle:
        return np.asarray(handle.convert('RGB'), dtype=np.int16)


def water_range(pose):
    yaw, pitch = pose['rotation']
    forward = np.array([-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)])
    right = np.array([math.cos(yaw), 0., -math.sin(yaw)])
    up = np.cross(right, forward)
    x = (2 * (np.arange(WIDTH) + .5) / WIDTH - 1) * FOCAL
    y = (1 - 2 * (np.arange(HEIGHT) + .5) / HEIGHT) * FOCAL * HEIGHT / WIDTH
    ray = forward + right * x[np.newaxis, :, np.newaxis] + up * y[:, np.newaxis, np.newaxis]
    with np.errstate(divide='ignore', invalid='ignore'):
        t = (WATERLINE - pose['eye'][1]) / ray[:, :, 1]
    return np.where(t >= 0, t * np.linalg.norm(ray, axis=2), np.inf)


def diff(reference, candidate, mask=None):
    residual = reference.astype('int32') - candidate.astype('int32')
    if mask is not None:
        residual = residual[mask]
    pixels = residual.reshape(-1, 3)
    peak = abs(pixels).max(axis=1)
    luma = pixels @ LUMA
    return {
        'pixels': int(peak.size),
        'rgb_counts_above_one': int((peak > 1).sum()),
        'peak_rgb_delta': int(peak.max()),
        'mae_rgb': round(float(abs(pixels).mean()), 5),
        'luma_rms': round(float(np.sqrt((luma ** 2).mean())), 5),
        'luma_percentiles_01_50_95_99': np.percentile(luma, [1, 50, 95, 99]).round(4).tolist(),
        'luma_brightening_ge_7': int((luma >= 7).sum()),
        'luma_darkening_le_minus_7': int((luma <= -7).sum()),
        'signed_luma_average': round(float(luma.mean()), 5),
    }


def measure(path):
    data = json.loads((path / 'native-rain-ripple-report.json').read_text())
    data['pixel_comparison'] = {}
    for name, shot in data['shots'].items():
        if 'before' not in shot['variants']:
            continue
        corrected = image(path, name, 'after')
        original = image(path, name, 'before')
        summary = {'current_minus_original': diff(corrected, original)}
        if 'before-repeat' in shot['variants']:
            repeat = image(path, name, 'before-repeat')
            summary['repeat_original_minus_original'] = diff(repeat, original)
        if 'rain-without-rings' in shot['variants']:
            distances = water_range(shot)
            crop = np.zeros((HEIGHT, WIDTH), dtype=bool)
            if name == 'lake-rain':
                crop[151:533, 86:1197] = True
            else:
                crop[143:630, 490:1260] = True
            plain = image(path, name, 'rain-without-rings')
            normal = image(path, name, 'slope-only')
            for region, bounds in [('near', (0, 8)), ('mid', (8, 17)), ('far', (22.1, 96))]:
                mask = crop & (distances >= bounds[0]) & (distances < bounds[1])
                summary[region] = {
                    'original_minus_unmarked_rain': diff(original, plain, mask),
                    'old_normal_minus_unmarked_rain': diff(normal, plain, mask),
                    'new_normal_minus_unmarked_rain': diff(corrected, plain, mask),
                    'direct_old_stamp_color': diff(original, normal, mask),
                }
        data['pixel_comparison'][name] = summary
    return data


if __name__ == '__main__':
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('frames', type=Path)
    args = cli.parse_args()
    print(json.dumps(measure(args.frames), ensure_ascii=False, indent=2))
