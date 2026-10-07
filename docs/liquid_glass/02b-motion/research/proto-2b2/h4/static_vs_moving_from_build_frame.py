import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, "tool/glass_lab/harness")

import analyze
import fitvis
import manifest
import shapes
import springfit
import touch

run = Path(sys.argv[1])
fit = json.loads(Path(sys.argv[2]).read_text())
table, above = fit["visibility_for_progress"], fit["visibility_above_full"]
gains = {"material.materialize": 0.0, "material.materialize.snappy": 0.44, "material.materialize.bouncy": 0.5}
rm_gains = {"material.materialize": 0.0, "material.materialize.snappy": 0.6, "material.materialize.bouncy": 0.8}
scenes = {s.id: s for s in manifest.load()}
grid_t = np.arange(0, 1.2, 1 / 2000)
for scene_id in sys.argv[3].split(","):
    scene = scenes[scene_id]
    response, damping = fitvis.SCENES[scene_id]
    for case_dir in sorted((run / scene_id).glob("*")):
        case = case_dir.name
        base = case.removesuffix("-reduce-motion")
        gain = (rm_gains if case.endswith("reduce-motion") else gains)[scene_id]
        rows = {float(v): p for v, p in fit["flutter_progress"][base].items()}
        vs = sorted(rows)
        ps = np.maximum.accumulate([rows[v] for v in vs])
        s = springfit.step_response(grid_t, response, damping)
        alpha = fitvis.mapped(s, True, 1.0, gain)
        static = np.interp([fitvis.visibility(a, table, above) for a in alpha], vs, ps)
        folder = case_dir / "flutter"
        found = analyze.window(folder)
        cap = shapes.capture(scene, folder, found[:2] if found else None)
        name = scene.track[0]
        times = np.array(cap["rows"][name]["times"])
        prog = np.array([r["progress"] for r in cap["rows"][name]["rows"]])
        ups = [w[1] for w in cap["touches"]]
        for event in cap["events"]:
            if event["step"] != 3:
                continue
            onset = event["onset"]
            up = max(u for u in ups if u <= onset)
            i0 = int(np.searchsorted(times, onset))
            before = prog[i0 - 1]
            end_idx = [i for i in range(len(times)) if times[i] <= onset + 0.9][-1]
            end = prog[end_idx]
            norm = (prog - before) / (end - before)
            out = []
            for i in range(i0, min(i0 + 12, len(times))):
                dt = times[i] - up
                pred = float(np.interp(dt, grid_t, static))
                out.append((round(dt * 1000, 1), round(float(norm[i]), 3), round(pred, 3)))
            gap = (onset - up) * 1000
            res = np.array([o[1] - o[2] for o in out])
            print(f"{scene_id:28} {case:28} touch-up->onset {gap:5.1f} ms  moving-minus-static(from touch-up frame) mean {res.mean():+.3f} rms {np.sqrt((res**2).mean()):.3f}")
            print("    " + "  ".join(f"{a:.0f}:{b:.2f}/{c:.2f}" for a, b, c in out[:9]))
