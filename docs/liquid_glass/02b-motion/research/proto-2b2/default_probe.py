import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Compare each pair region of material.spacing.<S>.a with the same region of material.spacing.default.a, pixel for pixel, to find the spacing the default container uses.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--run", required=True)
ARGS.add_argument("--out", required=True)
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import manifest
import metrics
import track

scenes = {scene.id: scene for scene in manifest.load()}
run = Path(OPTIONS.run)
reference = scenes["material.spacing.default.a"]
found = {}
for case in sorted(p.name for p in (run / "material.spacing.default.a").iterdir()):
    default = metrics.load(run / "material.spacing.default.a" / case / "native" / "ready.png")
    found[case] = {}
    for folder in sorted(run.glob("material.spacing.*.a")):
        spacing = folder.name.split(".")[2]
        if spacing == "default" or not (folder / case / "native" / "ready.png").exists():
            continue
        frame = metrics.load(folder / case / "native" / "ready.png")
        row = {}
        for name, region in reference.regions.items():
            px = track.pixel_rect(region)
            difference = np.abs(track.crop_px(frame, px) - track.crop_px(default, px))
            row[name] = {"max": float(difference.max()), "mean": round(float(difference.mean()), 4)}
        found[case][spacing] = row
        print(case, spacing, " ".join(f"{n}: max {v['max']:.0f} mean {v['mean']:.3f}" for n, v in row.items()), flush=True)
Path(OPTIONS.out).write_text(json.dumps(found, indent=1))
