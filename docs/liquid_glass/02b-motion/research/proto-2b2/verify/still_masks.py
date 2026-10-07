import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ARGS = argparse.ArgumentParser(description="Render the harness still mask (rim, grain, filled) of each topology region of a still scene for both apps, with the component count, neck and gap, and the rim's strength along the outline.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--case", required=True)
ARGS.add_argument("--scene", required=True)
ARGS.add_argument("--out", required=True)
ARGS.add_argument("--json")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import manifest
import metrics
import track

scene = {s.id: s for s in manifest.load()}[OPTIONS.scene]
case = Path(OPTIONS.case)
rows, found = [], {}
for app in ("native", "flutter"):
    frame_full = metrics.load(case / app / "ready.png")
    bare_full = metrics.load(case / app / "bare" / "ready.png")
    tiles = []
    for name in scene.topology:
        px = track.pixel_rect(scene.regions[name])
        frame, bare = track.crop_px(frame_full, px), track.crop_px(bare_full, px)
        difference = np.abs(frame - bare).max(axis=2)
        rim = difference > track.STILL_RIM
        grain = track.grain_removed(frame, bare)
        mask = track.still_mask(frame, bare)
        parts = track.components(track.point_mask(mask))
        topo = track.topology(mask)
        found[f"{app}.{name}"] = {"count": topo["count"], "neck": topo["neck"], "gap": track.gap(mask), "component_boxes_pt": [list(b) for b in parts], "rim_px": int(rim.sum()), "grain_px": int(grain.sum()), "mask_px": int(mask.sum())}
        image = np.zeros(frame.shape, dtype=np.uint8)
        image[mask] = (90, 90, 90)
        image[grain] = (0, 160, 255)
        image[rim] = (255, 255, 255)
        tiles.append(np.concatenate([frame.astype(np.uint8), image, np.clip(difference * 4, 0, 255).astype(np.uint8)[..., None].repeat(3, axis=2)], axis=0))
        print(app, name, json.dumps(found[f"{app}.{name}"]))
    rows.append(np.concatenate([np.pad(t, ((0, 0), (0, 6), (0, 0)), constant_values=255) for t in tiles], axis=1))
width = max(r.shape[1] for r in rows)
rows = [np.pad(r, ((0, 6), (0, width - r.shape[1]), (0, 0)), constant_values=255) for r in rows]
Image.fromarray(np.concatenate(rows, axis=0)).save(OPTIONS.out)
if OPTIONS.json:
    Path(OPTIONS.json).write_text(json.dumps(found, indent=1, default=lambda v: None))
print(OPTIONS.out)
