import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

ARGS = argparse.ArgumentParser(description="Sheet of frames from an extract.py cache in a window of milliseconds after a touch's up (or down), labelled with ms from that moment.")
ARGS.add_argument("--cache", required=True)
ARGS.add_argument("--touch", type=int, default=0)
ARGS.add_argument("--edge", choices=("down", "up"), default="up")
ARGS.add_argument("--start", type=float, required=True, help="ms")
ARGS.add_argument("--end", type=float, required=True, help="ms")
ARGS.add_argument("--every", type=int, default=1)
ARGS.add_argument("--scale", type=float, default=0.5)
ARGS.add_argument("--columns", type=int, default=8)
ARGS.add_argument("--out", required=True)
OPTIONS = ARGS.parse_args()
index = json.loads((Path(OPTIONS.cache) / "index.json").read_text())
zero = index["touches"][OPTIONS.touch][0 if OPTIONS.edge == "down" else 1]
chosen = [(t, p) for t, p in zip(index["times"], index["paths"]) if OPTIONS.start <= (t - zero) * 1000 <= OPTIONS.end][:: OPTIONS.every]
tiles = []
for t, path in chosen:
    image = Image.open(path).convert("RGB")
    image = image.resize((int(image.width * OPTIONS.scale), int(image.height * OPTIONS.scale)))
    ImageDraw.Draw(image).text((3, 3), f"{(t - zero) * 1000:.0f}", fill=(255, 0, 255))
    tiles.append(image)
w, h = tiles[0].size
rows = (len(tiles) + OPTIONS.columns - 1) // OPTIONS.columns
sheet = Image.new("RGB", (OPTIONS.columns * (w + 2), rows * (h + 2)), (255, 255, 255))
for i, tile in enumerate(tiles):
    sheet.paste(tile, ((i % OPTIONS.columns) * (w + 2), (i // OPTIONS.columns) * (h + 2)))
sheet.save(OPTIONS.out)
print(OPTIONS.out, len(tiles))
