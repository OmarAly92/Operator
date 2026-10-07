import argparse
from pathlib import Path

import numpy as np
from PIL import Image

ARGS = argparse.ArgumentParser(description="Crop a region in points from PNG frames at 3 px per point, stack them side by side with labels, optionally scaled, into one PNG.")
ARGS.add_argument("--region", required=True, help="x,y,w,h in points")
ARGS.add_argument("--scale", type=float, default=1.0)
ARGS.add_argument("--out", required=True)
ARGS.add_argument("--vertical", action="store_true")
ARGS.add_argument("--gain", type=float, default=0.0, help="when set, also show |a-b| difference images amplified by this gain, against the first image")
ARGS.add_argument("images", nargs="+", help="label=path")
OPTIONS = ARGS.parse_args()

x, y, w, h = (float(v) for v in OPTIONS.region.split(","))
box = (int(round(x * 3)), int(round(y * 3)), int(round((x + w) * 3)), int(round((y + h) * 3)))
tiles, labels = [], []
first = None
for spec in OPTIONS.images:
    label, path = spec.split("=", 1)
    image = Image.open(path).convert("RGB").crop(box)
    tiles.append(image)
    labels.append(label)
    if OPTIONS.gain:
        array = np.asarray(image, dtype=np.float32)
        if first is None:
            first = array
        else:
            difference = np.clip(np.abs(array - first).max(axis=2) * OPTIONS.gain, 0, 255).astype(np.uint8)
            tiles.append(Image.fromarray(difference).convert("RGB"))
            labels.append(f"|{label}-{labels[0]}|x{OPTIONS.gain:g}")
if OPTIONS.scale != 1.0:
    tiles = [t.resize((int(t.width * OPTIONS.scale), int(t.height * OPTIONS.scale)), Image.NEAREST) for t in tiles]
from PIL import ImageDraw
band = 14
if OPTIONS.vertical:
    canvas = Image.new("RGB", (max(t.width for t in tiles), sum(t.height + band for t in tiles)), (255, 0, 255))
    offset = 0
    for tile, label in zip(tiles, labels):
        ImageDraw.Draw(canvas).text((2, offset), label, fill=(255, 255, 0))
        canvas.paste(tile, (0, offset + band))
        offset += tile.height + band
else:
    canvas = Image.new("RGB", (sum(t.width + 4 for t in tiles), max(t.height for t in tiles) + band), (255, 0, 255))
    offset = 0
    for tile, label in zip(tiles, labels):
        ImageDraw.Draw(canvas).text((offset + 2, 0), label, fill=(255, 255, 0))
        canvas.paste(tile, (offset, band))
        offset += tile.width + 4
Path(OPTIONS.out).parent.mkdir(parents=True, exist_ok=True)
canvas.save(OPTIONS.out)
print(OPTIONS.out, canvas.size)
