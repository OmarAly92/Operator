import argparse
import json
import sys
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Extract full-resolution frames of a region of a native recording, with real timestamps, and the touch windows read from the touch marker, into a cache outside the recording.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--cache", required=True)
ARGS.add_argument("--region", required=True, help="x,y,w,h in points")
ARGS.add_argument("cases", nargs="+", help="label=native folder")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import metrics
import touch
import track

region = [float(v) for v in OPTIONS.region.split(",")]
rect = track.pixel_rect(region)
for spec in OPTIONS.cases:
    label, folder = spec.split("=", 1)
    folder = Path(folder)
    dest = Path(OPTIONS.cache) / label
    frames = track.extract(folder / "video.mp4", rect, dest / "frames")
    cut = track.teardown_cut(frames, track.crop_px(metrics.load(folder / "settled.png"), rect))
    windows = touch.touches(touch.phases(track.extract(folder / "video.mp4", touch.marker_rect(), dest / "marker")))
    index = {
        "folder": str(folder.resolve()),
        "region_pt": region,
        "rect_px": list(rect),
        "times": list(frames.times),
        "paths": [str(p) for p in frames.paths],
        "teardown_last": len(cut) - 1,
        "touches": [list(w) for w in windows],
    }
    (dest / "index.json").write_text(json.dumps(index, indent=0))
    print(label, len(frames), "frames, teardown_last", len(cut) - 1, "touches", windows, flush=True)
