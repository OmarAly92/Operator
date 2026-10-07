import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, "tool/glass_lab/harness")

import fitvis
import springfit

GAIN = {"material.materialize": (0.0, 0.0), "material.materialize.snappy": (0.44, 0.6), "material.materialize.bouncy": (0.5, 0.8)}
LAGS = np.arange(-0.06, 0.0605, 0.002)
EXPS = np.arange(1.0, 3.0001, 0.05)
per_scene = {}
for run in sys.argv[1:]:
    for result in sorted(Path(run).glob("material.materialize*/*/result.json")):
        scene_id, case = result.parent.parent.name, result.parent.name
        r = json.loads(result.read_text())
        y = np.array(r["shapes"]["pairs"]["step3e0"]["shapes"]["block"]["progress"]["curves"]["native"][:72])
        t = np.arange(len(y)) / 120
        response, damping = fitvis.SCENES[scene_id]
        gain = GAIN[scene_id][1 if case.endswith("motion") else 0]
        errs = np.array([[np.mean((fitvis.mapped(springfit.step_response(np.maximum(t - lag, 0), response, damping), True, 1, gain, a) - y) ** 2) for lag in LAGS] for a in EXPS])
        per_scene.setdefault(scene_id, []).append(errs)
        i, j = np.unravel_index(np.argmin(errs), errs.shape)
        print(f"{scene_id:28} {case:28} best a {EXPS[i]:.2f} lag {LAGS[j]*1000:+.0f} ms rms {np.sqrt(errs[i, j]):.4f}; a=1 best rms {np.sqrt(errs[0].min()):.4f}")
for scene_id, errs in per_scene.items():
    total = sum(e.min(axis=1) for e in errs)
    print(scene_id, "pooled best a", round(float(EXPS[int(np.argmin(total))]), 2))
