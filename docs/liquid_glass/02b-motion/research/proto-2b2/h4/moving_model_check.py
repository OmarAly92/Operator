import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, "tool/glass_lab/harness")

import fitvis
import manifest
import shapes

fit_dir = Path(sys.argv[1])
fit = json.loads((fit_dir / "fit.json").read_text())
runs = [Path(r) for r in sys.argv[2:]]
table, above = fit["visibility_for_progress"], fit["visibility_above_full"]
k = fit["blur_ramp"]["value"]
scene = {s.id: s for s in manifest.load()}["material.materialize"]
slopes = fitvis.scan_slopes(fit_dir / "table" / f"ramp{k}", scene.regions[scene.track[0]])
print("slopes", {c: round(v, 2) for c, v in slopes.items()})
gains = {"material.materialize": (0.0, 0.0), "material.materialize.snappy": (0.44, 0.6), "material.materialize.bouncy": (0.5, 0.8)}
rows = {case: {float(v): p for v, p in found.items()} for case, found in fit["flutter_progress"].items()}
noise = json.loads(fitvis.NOISE.read_text())
totals = {"recorded": 0, "matched_outcome": 0, "pred_true": 0, "pred_false": 0}
for run in runs:
    for result in sorted(run.glob("material.materialize*/*/result.json")):
        scene_id, case = result.parent.parent.name, result.parent.name
        r = json.loads(result.read_text())
        pair = r["shapes"]["pairs"]["step3e0"]
        prog = pair["shapes"]["block"]["progress"]
        delay = pair["delay"]["flutter"]
        recorded_first = delay < 22
        gain = gains[scene_id][1 if case.endswith("motion") else 0]
        response, damping = fitvis.SCENES[scene_id]
        base = case.removesuffix("-reduce-motion")
        times, progress = fitvis.flutter_frames(rows[base], table, above, response, damping, gain, 1.0)
        limits = fitvis.moving_limits(noise, scene_id, case)
        rec_fail = sum(1 for m in fitvis.MOVING_MEASURES if (r["measures"].get(f"motion.block.step3e0.progress.{m}") or [0, 0])[0] > (r["measures"].get(f"motion.block.step3e0.progress.{m}") or [0, 0])[1])
        line = []
        preds = {}
        for keep in (True, False):
            series = fitvis.recorded_series(times, progress, slopes[base], keep)
            found = shapes.compare_progress(fitvis.progress_series(prog["curves"]["native"]), fitvis.progress_series(series))
            fails = sum(1 for m in fitvis.MOVING_MEASURES if not found.get(m, float("inf")) <= limits[m])
            fl = found["flutter"]["spring"]
            preds[keep] = fails
            line.append(f"{'kept' if keep else 'dropped'} {fl['response']:.2f}/{fl['damping']:.2f} t1090 {found['flutter']['t10_90_ms']:.0f} fail {fails}")
        rf = prog["flutter"]["spring"]
        totals["recorded"] += rec_fail
        totals["matched_outcome"] += preds[recorded_first]
        totals["pred_true"] += preds[True]
        totals["pred_false"] += preds[False]
        print(f"{scene_id:28} {case:28} onset {'first' if recorded_first else 'second'} ({delay:.0f} ms) recorded {rf['response']:.2f}/{rf['damping']:.2f} t1090 {prog['flutter']['t10_90_ms']:.0f} fail {rec_fail} | " + " | ".join(line))
print(totals)
