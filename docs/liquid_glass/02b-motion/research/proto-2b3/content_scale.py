import argparse
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Measure whether a press scales the label inside native interactive glass: the extent of the label's bright pixels at rest and at the press peak.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--region", required=True, help="x,y,w,h in pt around the label")
ARGS.add_argument("--level", type=float, default=200.0)
ARGS.add_argument("take")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import metrics
import touch
import track

folder = Path(OPTIONS.take)
region = [float(v) for v in OPTIONS.region.split(",")]
px = track.pixel_rect(region)
frames = track.extract(folder / "video.mp4", px, folder / "label")
windows = touch.read(folder / "video.mp4", folder / "marker")
down, up = windows[0]


def extent(image):
    mask = metrics.luma(image) > OPTIONS.level
    columns = np.nonzero(mask.sum(axis=0) >= 2)[0]
    rows = np.nonzero(mask.sum(axis=1) >= 2)[0]
    if not len(columns) or not len(rows):
        return None
    return ((columns[-1] - columns[0] + 1) / metrics.SCALE, (rows[-1] - rows[0] + 1) / metrics.SCALE, (columns[0] + columns[-1] + 1) / 2 / metrics.SCALE)


rest = [i for i, t in enumerate(frames.times) if t < down][-1]
held = [i for i, t in enumerate(frames.times) if down + 0.4 <= t <= up]
print("rest", frames.times[rest], extent(frames[rest]))
for i in held[:: max(1, len(held) // 4)]:
    print("held", round(frames.times[i], 3), extent(frames[i]))
