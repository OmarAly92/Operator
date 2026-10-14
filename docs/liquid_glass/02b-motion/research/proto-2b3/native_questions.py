import argparse
import json
import sys
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Print the L4 press features of native takes, step by step and shape by shape, and the drag frames' size and centre.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--out")
ARGS.add_argument("takes", nargs="+", help="scene=case_dir")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import analyze
import manifest
import press
import shapes
import takecheck

SCENES = {s.id: s for s in manifest.load()}
found = {}
for item in OPTIONS.takes:
    scene_id, folder = item.split("=", 1)
    scene = SCENES[scene_id]
    folder = Path(folder)
    window = analyze.window(folder)
    capture = shapes.capture(scene, folder, window[:2] if window else None)
    steps = press.step_features(scene, capture)
    entry = {"touches": capture["touches"], "steps": {}, "series": {}, "rest": capture.get("rest")}
    if takecheck.judged(scene):
        entry["takecheck"] = takecheck.check(scene, folder)
        if entry["takecheck"]["failures"]:
            print(f"{scene_id} {folder.parent.name} take check: {'; '.join(entry['takecheck']['failures'])}", flush=True)
    for label, step in steps.items():
        entry["steps"][label] = {name: {k: v for k, v in f.items()} for name, f in step.items()}
        for name, f in step.items():
            text = ("HOLE " if f["hole"] else "") + " ".join(f"{key} {'-' if f[key] is None else round(float(f[key]), 3)}" for key in press.MEASURES)
            print(f"{scene_id} {folder.parent.name} {label} {name}: {text}", flush=True)
    for name, rows in capture["rows"].items():
        entry["series"][name] = {"times": rows["times"], **{key: [r[key] for r in rows["rows"]] for key in ("glow", "width", "height", "cx", "cy")}}
    found[f"{scene_id}/{folder.parent.name}/{folder.parents[2].name}"] = entry
if OPTIONS.out:
    Path(OPTIONS.out).write_text(json.dumps(found, default=float))
