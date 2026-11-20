#!/usr/bin/env python3
"""Index the model review and assemble two-view sheets from actual captures."""

import argparse
import json
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def group(file):
    folder = file.parent.name
    name = file.stem
    if folder in {"pines", "trees"}:
        return "trees"
    if folder in {"vegetation", "coast"} or name == "shore_boulder":
        return "waterfront-and-understory"
    if folder == "mines" or name == "iron_furnace":
        return "mines"
    if folder == "construction" or name in {"camp_table", "camp_lantern", "wood_chair", "wood_sign"}:
        return "cabin-and-furniture"
    if folder == "weapons" or name in {"club", "shield", "spear"}:
        return "held-equipment"
    if folder == "wild_people" or name in {"sky_character", "camp_crocodile", "camp_eagle", "camp_mastiff"}:
        return "characters-and-wildlife"
    if name in {"camp_backpack", "camp_boot", "camp_cap", "camp_helmet", "camp_jacket", "camp_pants", "camp_red_spaceship"}:
        return "player-gear-and-airship"
    if name.startswith(("food_", "crocodile_", "eagle_", "dog_meat")) or name in {"herb_bundle", "hide"}:
        return "food-and-harvests"
    return "camp-supplies"


def coverage(image):
    colors = np.asarray(image, dtype=np.int16)
    border = np.concatenate((colors[0], colors[-1], colors[:, 0], colors[:, -1]))
    background = np.median(border, axis=0)
    subject = np.max(np.abs(colors - background), axis=-1) > 16
    return round(float(subject.mean()), 4)


def draw_sheet(source, target, label, entries, tile_size, columns=2):
    view_width, height = tile_size
    panel_width = view_width * len(entries[0][1])
    gap, header, caption = 18, 52, 42
    rows = (len(entries) + columns - 1) // columns
    sheet = Image.new("RGB", (gap + columns * (panel_width + gap), header + rows * (height + caption + gap)), "#192225")
    draw = ImageDraw.Draw(sheet)
    title = ImageFont.load_default(size=22)
    text = ImageFont.load_default(size=14)
    draw.text((gap, 14), label.replace("-", " ").title(), font=title, fill="#f3ede0")
    for i, (name, photos, note) in enumerate(entries):
        left = gap + i % columns * (panel_width + gap)
        top = header + i // columns * (height + caption + gap)
        for j, photo in enumerate(photos):
            with Image.open(source / photo) as frame:
                tile = frame.convert("RGB").resize(tile_size, Image.Resampling.LANCZOS)
                sheet.paste(tile, (left + j * view_width, top))
        draw.text((left + 2, top + height + 3), name, font=text, fill="#f1e8d7")
        draw.text((left + 2, top + height + 22), note, font=text, fill="#a6b3b4")
    sheet.save(target / (label + ".jpg"), quality=91, subsampling=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ("inventory", "captures", "output"):
        parser.add_argument(argument, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    inventory = json.loads(args.inventory.read_text())
    capture = json.loads((args.captures / "capture.json").read_text())
    expected = {asset["file"]: asset for asset in inventory["models"] if asset["exists"]}
    actual = {asset["file"]: asset for asset in capture["assets"]}
    assert set(expected) == set(actual) and len(capture["failures"]) == 0
    assert len(capture["zones"]) == inventory["summary"]["streamed_glbs"]
    sheets = defaultdict(list)
    for file, details in actual.items():
        assert len(details["views"]) == 2 and details["glb_sha256"] == expected[file]["sha256"], file
        label = group(Path(file))
        details["sheet"] = label + ".jpg"
        details["visible_pixel_fraction"] = []
        for photo in details["views"]:
            with Image.open(args.captures / photo) as frame:
                details["visible_pixel_fraction"].append(coverage(frame.convert("RGB")))
        assert max(details["visible_pixel_fraction"]) > 0.002, file
        size = " x ".join(f"{extent:.3f}" for extent in details["bounds_size_m"])
        note = f"{size} m   |   {expected[file]['triangles']:,} triangles in file"
        sheets[label].append((Path(file).stem, details["views"], note))
    for label, entries in sheets.items():
        draw_sheet(args.captures, args.output, label, entries, (314, 235))
    zones = [(zone["id"], [zone["view"]], f"{zone['runtime_meshes']} meshes   |   {zone['runtime_batches']} batches")
             for zone in capture["zones"]]
    draw_sheet(args.captures, args.output, "streamed-zones", zones, (625, 352))
    (args.output / "capture-index.json").write_text(json.dumps(capture, ensure_ascii=False, indent=2) + "\n")
    print(f"Reviewed {len(actual)} imported models, {len(zones)} streamed scenes, {len(sheets) + 1} sheets")


if __name__ == "__main__":
    main()
