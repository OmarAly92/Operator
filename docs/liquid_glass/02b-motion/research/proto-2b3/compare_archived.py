import argparse
import json
import math
import sys
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Judge Flutter press takes against native references recorded in another run: one pair folder per case, analysed with today's floors; prints passing / judged / expected and every failing measure.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--pairs", required=True, help="folder for the pair links and results")
ARGS.add_argument("--out", required=True)
ARGS.add_argument("cases", nargs="+", help="scene=native_take=flutter_take; the native take's folder name tells pairs of one case apart")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import analyze
import lab
import manifest

SCENES = {s.id: s for s in manifest.load()}
noise = lab.load_noise()
found = {}
for item in OPTIONS.cases:
    scene_id, native, flutter = item.split("=")
    scene = SCENES[scene_id]
    case = Path(native).resolve().parent.name
    pair = Path(OPTIONS.pairs) / scene_id / case / Path(native).name
    pair.mkdir(parents=True, exist_ok=True)
    for name, source in (("native", native), ("flutter", flutter)):
        link = pair / name
        if link.is_symlink():
            link.unlink()
        link.symlink_to(Path(source).resolve())
    result = analyze.analyze(scene, pair, noise.get(scene_id, {}).get(case, {}))
    measures = result["measures"]
    judged = {k: v for k, v in measures.items() if k.startswith("motion.") and not k.startswith(("motion.events", "motion.touches", "motion.capture"))}
    gates = {k: v for k, v in measures.items() if k.startswith(("motion.events", "motion.touches", "motion.capture"))}
    statics = {k: v for k, v in measures.items() if not k.startswith("motion.")}

    def ok(entry):
        value, limit, kind = entry
        return value <= limit if kind == "max" else value >= limit

    failing = {k: [round(v[0], 3) if math.isfinite(v[0]) else str(v[0]), round(v[1], 3)] for k, v in sorted(judged.items()) if not ok(v)}
    row = {
        "motion": [sum(ok(v) for v in judged.values()), sum(math.isfinite(v[0]) for v in judged.values()), len(judged)],
        "gates": {k: [v[0], v[1]] for k, v in gates.items()},
        "statics_failing": {k: [round(v[0], 3), v[1]] for k, v in statics.items() if not ok(v)},
        "failing": failing,
        "takecheck": result.get("takecheck"),
    }
    found[f"{scene_id}/{case}/{Path(native).name}"] = row
    print(scene_id, case, Path(native).name, "motion %d/%d/%d" % tuple(row["motion"]), "gates", {k.replace("motion.", ""): v[0] for k, v in gates.items() if not ok(v)}, "statics", list(row["statics_failing"]), flush=True)
    for name, entry in failing.items():
        print("   ", name.replace("motion.", ""), entry, flush=True)
Path(OPTIONS.out).write_text(json.dumps(found, indent=1, default=str))
