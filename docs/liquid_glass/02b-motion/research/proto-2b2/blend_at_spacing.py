import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Compare native N7 necks and bulges with each candidate smooth union at k equal to the container's spacing.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--native", required=True)
ARGS.add_argument("--out", required=True)
ARGS.add_argument("--pad", type=float, default=0.0)
OPTIONS = ARGS.parse_args()
sys.argv = [sys.argv[0], "--harness", OPTIONS.harness, "--native", OPTIONS.native, "--out", OPTIONS.out]
source = (Path(__file__).resolve().parent / "blend_model.py").read_text().split("native = json.loads")[0]
exec(source)

native = json.loads(Path(OPTIONS.native).read_text())
report = {}
for name, series in native.items():
    k = float(name[1:])
    report[name] = {}
    for model in ("quadratic", "angle"):
        rows, errors = [], []
        for gap, value in sorted(series.items(), key=lambda item: int(item[0])):
            found = measure(model, float(gap), k, OPTIONS.pad)
            key = "neck" if "neck" in value else "tip"
            predicted = found[key] if found[key] is not None else (0.0 if key == "neck" else float(gap) / 2)
            errors.append(predicted - value[key])
            rows.append({"gap": int(gap), "measure": key, "native": value[key], "model": round(predicted, 2)})
        report[name][model] = {"rms": round(float(np.sqrt(np.mean(np.square(errors)))), 3), "max_abs": round(float(np.max(np.abs(errors))), 3), "rows": rows}
        print(name, model, "rms", report[name][model]["rms"], "max", report[name][model]["max_abs"], " ".join(f"g{r['gap']}:{r['measure'][0]} {r['native']:.2f}/{r['model']:.2f}" for r in rows), flush=True)
Path(OPTIONS.out).write_text(json.dumps(report, indent=1))
