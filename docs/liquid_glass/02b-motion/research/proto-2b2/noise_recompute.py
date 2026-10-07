import argparse
import json
import math
import sys
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Recompute noise.json entries from a noise run's takes with lab.case_noise, and list every noise and limit that moved against a previous noise.json.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--run", required=True, help="the noise run folder holding takes/<scene>/<case>/<n>")
ARGS.add_argument("--before", required=True, help="the noise.json to compare against")
ARGS.add_argument("--write", help="the noise.json to write the merged result to")
ARGS.add_argument("--out", required=True, help="json file listing every moved value")
ARGS.add_argument("cases", nargs="*", help="scene/case to recompute; all cases in the run when empty")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import lab
import manifest
import metrics
import shapes

STATIC = {"ready.mad": "mad", "ready.luminance": "luminance", "ready.rim_rms": "rim_rms", "ready.bbox_pt": "bbox_pt", "ready.centre_pt": "centre_pt"}


def threshold(name):
    last = name.split(".")[-1]
    if name in STATIC:
        return metrics.THRESHOLDS[STATIC[name]]
    if name.startswith("ready.topology."):
        return metrics.THRESHOLDS[last]
    if last in shapes.LIMITS:
        return metrics.THRESHOLDS[shapes.LIMITS[last]]
    return None


def limit(name, noise):
    base = threshold(name)
    if base is None:
        return None
    return max(base, lab.analyze.NOISE_FACTOR * noise)


run = Path(OPTIONS.run)
scenes = {scene.id: scene for scene in manifest.load()}
before = json.loads(Path(OPTIONS.before).read_text())
after = json.loads(json.dumps(before))
if OPTIONS.cases:
    jobs = [tuple(case.split("/")) for case in OPTIONS.cases]
else:
    jobs = [(scene.name, case.name) for scene in sorted((run / "takes").iterdir()) for case in sorted(scene.iterdir())]
moved = []
for scene_id, case in jobs:
    folder = run / "takes" / scene_id / case
    takes = [folder / str(n) for n in lab.take_numbers(folder)]
    worst, static_worst = lab.case_noise(scenes[scene_id], takes, run / scene_id / case)
    old = (before.get(scene_id) or {}).get(case, {})
    for name in sorted(set(old) | set(worst)):
        a, b = old.get(name), worst.get(name)
        if a is None or b is None or not math.isclose(a, b, rel_tol=0, abs_tol=1e-9):
            la = limit(name, a) if a is not None else (threshold(name) if threshold(name) is not None else None)
            lb = limit(name, b) if b is not None else (threshold(name) if threshold(name) is not None else None)
            moved.append({"scene": scene_id, "case": case, "measure": name, "noise_before": a, "noise_after": b, "limit_before": la, "limit_after": lb, "limit_moved": la != lb})
    after.setdefault(scene_id, {})[case] = worst
    print(f"{scene_id} {case}: {len(takes)} takes, static mad {static_worst:.2f}, {sum(1 for m in moved if m['scene'] == scene_id and m['case'] == case)} values moved", flush=True)
Path(OPTIONS.out).write_text(json.dumps(moved, indent=1))
if OPTIONS.write:
    Path(OPTIONS.write).write_text(json.dumps(after, indent=2, sort_keys=True) + "\n")
print(len(moved), "values moved,", sum(m["limit_moved"] for m in moved), "limits moved")
