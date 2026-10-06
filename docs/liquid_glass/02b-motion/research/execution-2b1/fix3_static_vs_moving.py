import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, "tool/glass_lab/harness")

import fitvis
import springfit

RUNS = Path("build/glass_lab/runs")
HERE = Path(__file__).resolve().parent
PAIRS = (("20261006-154138", "fix2-fit.json"), ("20261006-204707", "fix3-fit.json"))
for run, fit_name in PAIRS:
    fit = json.loads((HERE / fit_name).read_text())
    table, above = fit["visibility_for_progress"], fit["visibility_above_full"]
    print(f"run {run}, k = {fit['blur_ramp']['value']}, default appear, progress at 50 / 100 / 150 ms after onset")
    for case in ("dark-photo", "dark-stripes", "light-photo", "light-stripes"):
        rows = {float(v): p for v, p in fit["flutter_progress"][case].items()}
        visibilities = sorted(rows)
        progress = np.maximum.accumulate([rows[v] for v in visibilities])
        result = json.loads((RUNS / run / "material.materialize" / case / "result.json").read_text())
        curves = result["shapes"]["pairs"]["step3e0"]["shapes"]["block"]["progress"]["curves"]
        flutter, native = np.array(curves["flutter"]), np.array(curves["native"])
        t = np.arange(len(flutter)) / 120.0
        spring = springfit.step_response(t, 0.55, 1.0)
        still = np.interp([fitvis.visibility(s, table, above) for s in spring], visibilities, progress)
        still = (still - still[0]) / (still[-1] - still[0])
        n = min(len(flutter), len(still), 60)
        gap = float(np.sqrt(np.mean((flutter[:n] - still[:n]) ** 2)))
        at = (6, 12, 18)
        print(f"  {case:13} moving {' / '.join(f'{flutter[i]:.2f}' for i in at)}  still scan predicts {' / '.join(f'{still[i]:.2f}' for i in at)}  spring {' / '.join(f'{spring[i]:.2f}' for i in at)}  native {' / '.join(f'{native[i]:.2f}' for i in at)}  rms moving - still {gap:.3f}")
