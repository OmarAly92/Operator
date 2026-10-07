import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

ARGS = argparse.ArgumentParser(description="Tile cached frames into a labelled contact sheet: each tile is a frame index, labelled with its index and its time in ms from --zero.")
ARGS.add_argument("--cache", required=True, help="a case folder written by extract.py")
ARGS.add_argument("--frames", required=True, help="comma-separated frame indices, or a:b for a range")
ARGS.add_argument("--zero", type=float, default=0.0, help="video time in s that labels count from")
ARGS.add_argument("--crop", default=None, help="x,y,w,h in points inside the cached region")
ARGS.add_argument("--scale", type=float, default=0.5)
ARGS.add_argument("--columns", type=int, default=12)
ARGS.add_argument("--out", required=True)
OPTIONS = ARGS.parse_args()

index = json.loads((Path(OPTIONS.cache) / "index.json").read_text())
chosen = []
for part in OPTIONS.frames.split(","):
    if ":" in part:
        a, b = part.split(":")
        chosen.extend(range(int(a), int(b) + 1))
    else:
        chosen.append(int(part))
tiles = []
for i in chosen:
    image = Image.open(index["paths"][i]).convert("RGB")
    if OPTIONS.crop:
        x, y, w, h = (float(v) * 3 for v in OPTIONS.crop.split(","))
        image = image.crop((int(x), int(y), int(x + w), int(y + h)))
    image = image.resize((max(1, int(image.width * OPTIONS.scale)), max(1, int(image.height * OPTIONS.scale))), Image.LANCZOS)
    label = f"#{i} {round((index['times'][i] - OPTIONS.zero) * 1000)}"
    tiles.append((image, label))
width, height = tiles[0][0].size
columns = min(OPTIONS.columns, len(tiles))
rows = (len(tiles) + columns - 1) // columns
sheet = Image.new("RGB", (columns * width, rows * (height + 14)), "white")
draw = ImageDraw.Draw(sheet)
for n, (image, label) in enumerate(tiles):
    x, y = (n % columns) * width, (n // columns) * (height + 14)
    sheet.paste(image, (x, y + 14))
    draw.text((x + 2, y + 1), label, fill="black")
Path(OPTIONS.out).parent.mkdir(parents=True, exist_ok=True)
sheet.save(OPTIONS.out)
print(OPTIONS.out, sheet.size)
