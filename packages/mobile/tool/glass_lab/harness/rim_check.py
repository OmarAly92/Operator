import json
import sys
from dataclasses import replace
from pathlib import Path

import numpy as np

sys.path.insert(0, "tool/glass_lab/harness")

import analyze
import manifest
import metrics
import rim
import shapes
import track

SCENE = "material.materialize"
REGION = "block"
BINS = (0.3, 0.5, 0.7)
TOLERANCE = 0.08


def flutter(scan_dir, region):
    rect = track.pixel_rect(region)
    found = {}
    for case_dir in sorted(Path(scan_dir).glob("*")):
        shots = {float(p.name): p / "ready.png" for p in case_dir.glob("*") if (p / "ready.png").exists()}
        if 0.0 not in shots or 1.0 not in shots:
            continue
        bare = track.crop_px(metrics.load(shots[0.0]), rect)
        box = track.box_pixels(track.crop_px(metrics.load(shots[1.0]), rect), bare, track.edges(bare))
        found[case_dir.name] = {str(v): rim.rim_width(track.crop_px(metrics.load(path), rect), bare, box) for v, path in sorted(shots.items()) if v > 0}
    return found


def native(run_dir, region):
    scene = replace({s.id: s for s in manifest.load()}[SCENE], regions={REGION: region}, track=(REGION,), motion=())
    found = {}
    for case_dir in sorted((Path(run_dir) / SCENE).glob("*")):
        folder = case_dir / "native"
        if not (folder / "video.mp4").exists():
            continue
        window = analyze.window(folder)
        capture = shapes.capture(scene, folder, window[:2] if window else None)
        rect = track.pixel_rect(region)
        bare = track.crop_px(metrics.load(folder / "bare" / "ready.png"), rect)
        box = track.box_pixels(track.crop_px(metrics.load(folder / "ready.png"), rect), bare, track.edges(bare))
        rows = capture["rows"][REGION]["rows"]
        paths = sorted((folder / "shapes").glob("*.png"))
        progress = np.array([row["progress"] for row in rows])
        widths = {"1.0": rim.rim_width(track.crop_px(metrics.load(folder / "ready.png"), rect), bare, box)}
        for target in BINS:
            near = [i for i in np.nonzero(np.abs(progress - target) <= TOLERANCE)[0] if i < len(paths)]
            values = [rim.rim_width(metrics.load(paths[i]), bare, box) for i in near]
            values = [v for v in values if np.isfinite(v)]
            widths[str(target)] = round(float(np.median(values)), 2) if values else None
        found[case_dir.name] = widths
    return found


def main():
    region = tuple({s.id: s for s in manifest.load()}[SCENE].regions[REGION])
    print(json.dumps({"flutter": flutter(sys.argv[1], region), "native": native(sys.argv[2], region)}, indent=2))


if __name__ == "__main__":
    main()
