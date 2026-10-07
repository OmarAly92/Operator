import argparse
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

ARGS = argparse.ArgumentParser(description="Lay out the frames of a take's shapes/ cache (written by the harness's capture, one PNG per video frame) whose video timestamps fall in a window, labelled with their times, into one sheet.")
ARGS.add_argument("--take", required=True, help="app folder holding video.mp4 and shapes/")
ARGS.add_argument("--start", type=float, required=True)
ARGS.add_argument("--end", type=float, required=True)
ARGS.add_argument("--crop", default=None, help="x,y,w,h in px inside the cached crop")
ARGS.add_argument("--scale", type=float, default=0.5)
ARGS.add_argument("--columns", type=int, default=6)
ARGS.add_argument("--cache", default="shapes")
ARGS.add_argument("--out", required=True)
OPTIONS = ARGS.parse_args()

take = Path(OPTIONS.take)
probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time", "-of", "csv=p=0", str(take / "video.mp4")], capture_output=True, text=True, check=True)
times = [float(line.split(",")[0]) for line in probe.stdout.split() if line.strip()]
paths = sorted((take / OPTIONS.cache).glob("*.png"))
chosen = [(t, p) for t, p in zip(times, paths) if OPTIONS.start <= t <= OPTIONS.end]
tiles = []
for t, path in chosen:
    image = Image.open(path).convert("RGB")
    if OPTIONS.crop:
        x, y, w, h = (int(v) for v in OPTIONS.crop.split(","))
        image = image.crop((x, y, x + w, y + h))
    image = image.resize((int(image.width * OPTIONS.scale), int(image.height * OPTIONS.scale)))
    ImageDraw.Draw(image).text((3, 3), f"{t:.3f}", fill=(255, 0, 255))
    tiles.append(image)
if not tiles:
    raise SystemExit("no frames in the window")
w, h = tiles[0].width, tiles[0].height
rows = (len(tiles) + OPTIONS.columns - 1) // OPTIONS.columns
sheet = Image.new("RGB", (OPTIONS.columns * (w + 2), rows * (h + 2)), (255, 255, 255))
for i, tile in enumerate(tiles):
    sheet.paste(tile, ((i % OPTIONS.columns) * (w + 2), (i // OPTIONS.columns) * (h + 2)))
sheet.save(OPTIONS.out)
print(OPTIONS.out, len(tiles), "frames", len(times), "pts", len(paths), "cached")
