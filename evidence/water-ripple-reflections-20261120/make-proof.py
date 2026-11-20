"""Create compact water evidence while retaining the original exposure."""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


FONT = ImageFont.truetype('/System/Library/Fonts/Hiragino Sans GB.ttc', 22)
RULE = '#182322'
LABEL = '#e2e9e2'
TILE_GAP = 14


def sheet(frames, out, name, rows):
    tiles = []
    for row in rows:
        images = []
        for shot, title, width, crop in row:
            with Image.open(frames / (shot + '.png')) as original:
                panel = original.convert('RGB')
            if crop:
                panel = panel.crop(crop)
            panel = panel.resize((width, round(width * panel.height / panel.width)), Image.Resampling.LANCZOS)
            images.append((panel, title))
        tiles.append(images)
    row_heights = [max(panel.height for panel, _ in row) + 36 for row in tiles]
    width = max(sum(panel.width for panel, _ in row) + TILE_GAP * (len(row) - 1) for row in tiles)
    canvas = Image.new('RGB', (width, sum(row_heights) + TILE_GAP * (len(tiles) - 1)), RULE)
    draw = ImageDraw.Draw(canvas)
    y = 0
    for row, height in zip(tiles, row_heights):
        x = 0
        for panel, title in row:
            draw.text((x + 9, y + 5), title, font=FONT, fill=LABEL)
            canvas.paste(panel, (x, y + 36))
            x += panel.width + TILE_GAP
        y += height + TILE_GAP
    canvas.save(out / name, quality=92, optimize=True, subsampling=0)


def produce(frames, out):
    out.mkdir(parents=True, exist_ok=True)
    sheet(frames, out, 'lake-and-sea-fixed.jpg', [
        [('lake-weather-before', '鹿鸣湖 · 原雨纹', 850, None), ('lake-weather-after', '鹿鸣湖 · 改进后', 850, None)],
        [('coast-weather-before', '近海 · 原雨纹', 850, None), ('coast-weather-after', '近海 · 改进后', 850, None)],
    ])
    lake = (340, 244, 1040, 512)
    ocean = (490, 315, 1190, 583)
    sheet(frames, out, 'near-water-profile-controls.jpg', [
        [('lake-rain-before', '湖 · 原着色', 590, lake), ('lake-rain-slope-only', '湖 · 去掉原有亮边', 590, lake),
         ('lake-rain-after', '湖 · 改进后', 590, lake)],
        [('coast-rain-before', '海 · 原着色', 590, ocean), ('coast-rain-slope-only', '海 · 去掉原有亮边', 590, ocean),
         ('coast-rain-after', '海 · 改进后', 590, ocean)],
    ])
    sheet(frames, out, 'distance-and-waterline.jpg', [
        [('lake-distant-before', '远湖 · 原雨纹', 780, None), ('lake-distant-after', '远湖 · 改进后', 780, None)],
        [('coast-offshore-before', '外海 · 原雨纹', 780, None), ('coast-offshore-after', '外海 · 改进后', 780, None)],
        [('lake-creek-join-after', '溪水汇入湖面', 780, None), ('coast-wash-after', '海岸浅水交接', 780, None)],
    ])
    sheet(frames, out, 'clear-and-submerged.jpg', [
        [('lake-clear-after', '晴天湖面', 780, None), ('coast-clear-after', '晴天海面', 780, None)],
        [('lake-submerged-before', '从水下看雨湖 · 原水面', 780, None),
         ('lake-submerged-after', '从水下看雨湖 · 改进后', 780, None)],
    ])


if __name__ == '__main__':
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('frames', type=Path)
    cli.add_argument('out', type=Path)
    args = cli.parse_args()
    produce(args.frames, args.out)
