"""Measure and assemble the fixed-camera rain and shelter captures."""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


SCENES = (
    "open-outside", "camp", "built", "coal_mine", "iron_mine",
    "old-site", "tilted", "mine-open-slope",
)
FOCUS_SHIFT = [0.56, 0.29, -0.21]


def load_frame(directory, name):
    with Image.open(directory / f"{name}.png") as frame:
        return np.asarray(frame.convert("RGB"), dtype=np.int16)


def delta(first, second):
    return np.abs(first - second).max(axis=-1)


def visible_pixels(first, second, threshold=8):
    return int(np.count_nonzero(delta(first, second) > threshold))


def compare_shelter(directory):
    result = {}
    for scene in SCENES:
        reference = load_frame(directory, f"{scene}-dry-reference")
        exposed = load_frame(directory, f"{scene}-no-cover")
        covered = load_frame(directory, f"{scene}-covered")
        result[scene] = {
            "without_cover": visible_pixels(exposed, reference),
            "with_cover": visible_pixels(covered, reference),
            "changed_by_cover": visible_pixels(covered, exposed),
        }
    return result


def compare_focus(directory):
    reference = load_frame(directory, "open-outside-dry-reference")
    original = load_frame(directory, "open-outside-covered")
    shifted = load_frame(directory, "open-shifted-focus")
    next_frame = load_frame(directory, "open-next-frame")
    original_pixels = delta(original, reference) > 8
    return {
        "window_shift_m": FOCUS_SHIFT,
        "original_rain_pixels": int(original_pixels.sum()),
        "retained_rain_pixels": int(np.count_nonzero(original_pixels & (delta(shifted, reference) > 8))),
        "changed_by_window_shift": visible_pixels(original, shifted),
        "changed_after_one_sixtieth_room_second": visible_pixels(original, next_frame),
    }


def make_pair(output, panels):
    comparison = Image.new("RGB", (1280, 388), "#172226")
    labels = ImageDraw.Draw(comparison)
    for i, (source, label) in enumerate(panels):
        with Image.open(source) as frame:
            comparison.paste(frame.convert("RGB").resize((640, 360), Image.Resampling.LANCZOS), (i * 640, 0))
        labels.text((i * 640 + 14, 368), label, fill="#ecf0eb")
    comparison.save(output, quality=95, subsampling=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("baseline", "candidate", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    after = compare_shelter(args.candidate)
    anchor = compare_focus(args.candidate)
    assert anchor["original_rain_pixels"] > 0
    assert anchor["retained_rain_pixels"] >= anchor["original_rain_pixels"] * 0.99
    assert anchor["changed_by_window_shift"] < anchor["original_rain_pixels"] * 0.02
    assert anchor["changed_after_one_sixtieth_room_second"] > 100
    for scene in ("camp", "built", "coal_mine", "iron_mine", "tilted"):
        assert after[scene]["without_cover"] > after[scene]["with_cover"] > 0, scene
    for scene in ("old-site", "mine-open-slope"):
        assert after[scene]["changed_by_cover"] == 0, scene

    bright_rain = {}
    for label, directory in (("before", args.baseline), ("after", args.candidate)):
        bright_rain[label] = visible_pixels(load_frame(directory, "open-outside-covered"),
            load_frame(directory, "open-outside-dry-reference"), threshold=64)
    report = {
        "engine": "Godot 4.7.2 / OpenGL 4.1 Metal Compatibility / Apple M1",
        "viewport": [1280, 720],
        "room_seconds": 94.5,
        "rain_pixels_rgb_delta_over_8": {"before": compare_shelter(args.baseline), "after": after},
        "outdoor_rain_pixels_rgb_delta_over_64": bright_rain,
        "world_anchoring": anchor,
    }
    (args.output / "measurement.json").write_text(json.dumps(report, indent=2) + "\n")
    make_pair(args.output / "rain-before-after.jpg", [
        (args.baseline / "camp-unrepaired.png", "Previous precipitation"),
        (args.candidate / "camp-unrepaired.png", "World-anchored precipitation"),
    ])
    make_pair(args.output / "mine-cover.jpg", [
        (args.candidate / "coal_mine-no-cover.png", "Roof clipping disabled"),
        (args.candidate / "coal_mine-covered.png", "Rain stays outside the coal mine"),
    ])


if __name__ == "__main__":
    main()
