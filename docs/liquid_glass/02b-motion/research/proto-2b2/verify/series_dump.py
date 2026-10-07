import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Re-run the harness's per-shape capture on a case's two apps and dump what result.json drops: every frame's per-region rows, the touches, each event's series, and per pair, shape and key each app's own features and spring fit, beside the judged differences from result.json.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--scene", required=True)
ARGS.add_argument("--out", required=True)
ARGS.add_argument("cases", nargs="+")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import align
import analyze
import manifest
import shapes
import springfit

scene = {s.id: s for s in manifest.load()}[OPTIONS.scene]


def clean(value):
    if isinstance(value, float):
        return round(value, 3) if np.isfinite(value) else None
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [clean(v) for v in value]
    if isinstance(value, np.floating):
        return clean(float(value))
    return value


def own(series_key):
    values = np.array(series_key, dtype=np.float64)
    if not np.isfinite(values).all():
        return None
    times = np.arange(len(values)) / align.GRID_HZ
    found = {"start": values[0], "end": values[-1], "min": values.min(), "max": values.max(), "travel": values[-1] - values[0]}
    feats = springfit.features(times, values)
    if feats:
        found.update(feats)
    fit = springfit.fit(times, values)
    if fit:
        found["spring"] = fit
    return found


report = {}
for case in OPTIONS.cases:
    case = Path(case)
    captured = {}
    for app in ("native", "flutter"):
        found = analyze.window(case / app)
        captured[app] = shapes.capture(scene, case / app, found[:2] if found else None)
    entry = {"touches": {app: captured[app]["touches"] for app in captured}, "rows": {}, "events": {}, "pairs": {}}
    for app in captured:
        entry["rows"][app] = {name: {"times": rows["times"], "rows": [{k: r.get(k) for k in ("width", "height", "cx", "cy", "luma", "count", "neck", "progress")} for r in rows["rows"]]} for name, rows in captured[app].get("rows", {}).items()}
        entry["events"][app] = [{"onset": e["onset"], "step": e["step"], "series": e["series"]} for e in captured[app]["events"]]
    for label, a, b in shapes.pairs(captured["native"], captured["flutter"]):
        pair = {"onset": {"native": a["onset"], "flutter": b["onset"]}, "shapes": {}}
        for name in shapes.regions(scene):
            sa, sb = a["series"][name], b["series"][name]
            pair["shapes"][name] = {key: {"native": own(sa[key]), "flutter": own(sb[key])} for key in align.KEYS}
            if "count" in sa:
                pair["shapes"][name]["topology"] = shapes.compare_topology(sa, sb)
        entry["pairs"][label] = pair
    report[case.name] = clean(entry)
    print(case, "events", [len(captured[a]["events"]) for a in captured], "touches", [captured[a]["touches"] for a in captured], flush=True)
Path(OPTIONS.out).write_text(json.dumps(report))
