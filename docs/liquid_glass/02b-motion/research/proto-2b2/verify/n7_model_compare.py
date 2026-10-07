import argparse
import json
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="N7 light-photo silhouettes: per spacing and gap the neck (joined) or bulge tip (apart) of the stored native series, the angle model at k = spacing (blend-at-spacing-light-photo.json), this run's native and this run's Flutter; per spacing the RMS of Flutter against the model and against this run's native.")
ARGS.add_argument("--model", required=True)
ARGS.add_argument("--native", required=True)
ARGS.add_argument("--flutter", required=True)
ARGS.add_argument("--out", required=True)
OPTIONS = ARGS.parse_args()
model = json.loads(Path(OPTIONS.model).read_text())
native = json.loads(Path(OPTIONS.native).read_text())
flutter = json.loads(Path(OPTIONS.flutter).read_text())


def value(series, s, gap, key):
    entry = series.get(s, {}).get(str(gap))
    if entry is None:
        return None
    if key in entry:
        return entry[key]
    return 0.0 if key == "neck" and "tip" in entry else ("joined" if key == "tip" else None)


lines, report = [], {}
for s in sorted(model, key=lambda k: float(k[1:])):
    rows = model[s]["angle"]["rows"]
    errs_model, errs_native = [], []
    lines.append(f"== {s} (angle model rms against stored native {model[s]['angle']['rms']})")
    lines.append("gap measure | stored native | model | native now | flutter now")
    for row in rows:
        gap, key = row["gap"], row["measure"]
        now_n, now_f = value(native, s, gap, key), value(flutter, s, gap, key)
        if isinstance(now_f, (int, float)):
            errs_model.append(now_f - row["model"])
        if isinstance(now_f, (int, float)) and isinstance(now_n, (int, float)):
            errs_native.append(now_f - now_n)
        lines.append(f"g{gap:>3d} {key:4s} | {row['native']:>7} | {row['model']:>6} | {now_n!s:>7} | {now_f!s:>7}")
    report[s] = {
        "flutter_vs_model_rms": round(float(np.sqrt(np.mean(np.square(errs_model)))), 3) if errs_model else None,
        "flutter_vs_model_max": round(float(np.max(np.abs(errs_model))), 3) if errs_model else None,
        "flutter_vs_native_now_rms": round(float(np.sqrt(np.mean(np.square(errs_native)))), 3) if errs_native else None,
        "flutter_vs_native_now_max": round(float(np.max(np.abs(errs_native))), 3) if errs_native else None,
    }
    lines.append(f"   Flutter against model: rms {report[s]['flutter_vs_model_rms']} max {report[s]['flutter_vs_model_max']}; against native now: rms {report[s]['flutter_vs_native_now_rms']} max {report[s]['flutter_vs_native_now_max']}")
Path(OPTIONS.out).write_text("\n".join(lines) + "\n" + json.dumps(report, indent=1) + "\n")
print("\n".join(lines))
