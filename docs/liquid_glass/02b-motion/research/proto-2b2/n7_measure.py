import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Measure native N7 spacing stills: count, neck and each circle's inner tip against its outer edge.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--out", required=True)
ARGS.add_argument("--mask", choices=("still", "silhouette"), default="still")
ARGS.add_argument("takes", nargs="+", help="folders holding ready.png and bare/ready.png, as scene/case/take=path")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import manifest
import metrics
import track

sys.path.insert(0, str(Path(__file__).resolve().parent))
from silhouette import silhouette

SCENES = {scene.id: scene for scene in manifest.load()}
SCREEN_CENTRE = metrics.SCREEN[0] / 2
RADIUS = 40.0


def runs(row):
    found, start = [], None
    for index, value in enumerate(row):
        if value and start is None:
            start = index
        if not value and start is not None:
            found.append((start, index))
            start = None
    if start is not None:
        found.append((start, len(row)))
    return found


def tips(mask, origin_x, gap):
    scale = metrics.SCALE
    rows = mask.shape[0]
    centre_rows = range(rows // 2 - scale, rows // 2 + scale + 1)
    best = None
    for r in centre_rows:
        found = [segment for segment in runs(mask[r]) if segment[1] - segment[0] >= scale * 4]
        if not found:
            continue
        left, right = found[0][0], found[-1][1]
        entry = {"outer_left": origin_x + left / scale, "outer_right": origin_x + right / scale}
        if len(found) >= 2:
            entry["inner_left"] = origin_x + found[0][1] / scale
            entry["inner_right"] = origin_x + found[-1][0] / scale
        if best is None or entry["outer_right"] - entry["outer_left"] > best["outer_right"] - best["outer_left"]:
            best = entry
    if best is None:
        return None
    left_centre = SCREEN_CENTRE - gap / 2 - RADIUS
    right_centre = SCREEN_CENTRE + gap / 2 + RADIUS
    best["pad_left"] = left_centre - RADIUS - best["outer_left"]
    best["pad_right"] = best["outer_right"] - (right_centre + RADIUS)
    if "inner_left" in best:
        best["tip_left"] = best["inner_left"] - (left_centre + RADIUS)
        best["tip_right"] = (right_centre - RADIUS) - best["inner_right"]
        best["gap_seen"] = best["inner_right"] - best["inner_left"]
    return best


def measure(scene_id, folder):
    scene = SCENES[scene_id]
    frame = metrics.load(Path(folder) / "ready.png")
    bare_full = metrics.load(Path(folder) / "bare" / "ready.png")
    found = {}
    for name in scene.topology:
        px = track.pixel_rect(scene.regions[name])
        crop = track.crop_px(frame, px)
        bare = track.crop_px(bare_full, px)
        mask = track.still_mask(crop, bare) if OPTIONS.mask == "still" else silhouette(crop, bare)
        gap = float(name[1:])
        row = track.topology(mask)
        row.update(tips(mask, px[0] / metrics.SCALE, gap) or {})
        found[name] = {key: (round(value, 3) if isinstance(value, float) and np.isfinite(value) else (None if isinstance(value, float) else value)) for key, value in row.items()}
    return found


results = []
for spec in OPTIONS.takes:
    label, folder = spec.split("=", 1)
    scene_id, case, take = label.split("/")
    results.append({"scene": scene_id, "case": case, "take": take, "folder": folder, "regions": measure(scene_id, folder)})
Path(OPTIONS.out).write_text(json.dumps(results, indent=1))
print(len(results), "takes measured")
