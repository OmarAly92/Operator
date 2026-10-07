import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Merge scene: each circle's true position from the outer edge of its region box (left box's left edge, right box's right edge, which no bridge crosses) per event and app, its spring fit and features, and the pair's join/split times and neck from the harness series dumped by series_dump.py.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--series", required=True)
ARGS.add_argument("--out", required=True)
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import align
import shapes
import springfit

data = json.loads(Path(OPTIONS.series).read_text())
report = {}
for case, entry in data.items():
    report[case] = {}
    for index, name in ((0, "merge"), (1, "split")):
        row = {}
        for app in ("native", "flutter"):
            series = entry["events"][app][index]["series"]
            found = {}
            for shape, sign in (("left", -1), ("right", 1)):
                cx, width = np.array(series[shape]["cx"], dtype=float), np.array(series[shape]["width"], dtype=float)
                outer = cx + sign * width / 2
                times = np.arange(len(outer)) / align.GRID_HZ
                fit = springfit.fit(times, outer)
                feats = springfit.features(times, outer)
                norm = springfit.normalize(outer)
                t10 = float(times[np.nonzero(norm >= 0.1)[0][0]] * 1000) if norm is not None else None
                t90 = float(times[np.nonzero(norm >= 0.9)[0][0]] * 1000) if norm is not None else None
                found[shape] = {"start": round(float(outer[0]), 2), "end": round(float(outer[-1]), 2), "t10_ms": t10, "t90_ms": t90, "spring": fit, "features": feats, "curve_33ms": [round(float(v), 1) for v in outer[: 96 : 4]]}
            counts = series["pair"]["count"]
            joins, splits = shapes.transitions(np.array(counts))
            found["pair"] = {"joins_ms": [i * 1000 / align.GRID_HZ for i in joins], "splits_ms": [i * 1000 / align.GRID_HZ for i in splits], "neck_33ms": [None if v is None else round(v, 1) for v in series["pair"]["neck"][: 96 : 4]]}
            row[app] = found
        report[case][name] = row
        for app in ("native", "flutter"):
            f = row[app]
            print(f"{case:13s} {name:5s} {app:7s} left {f['left']['spring']['response']:.2f}/{f['left']['spring']['damping']:.2f} rms {f['left']['spring']['rms']:.3f} t10 {f['left']['t10_ms']:.0f} t90 {f['left']['t90_ms']:.0f} | right {f['right']['spring']['response']:.2f}/{f['right']['spring']['damping']:.2f} rms {f['right']['spring']['rms']:.3f} t10 {f['right']['t10_ms']:.0f} t90 {f['right']['t90_ms']:.0f} | joins {f['pair']['joins_ms']} splits {f['pair']['splits_ms']}")
            print(f"{'':27s} left outer {f['left']['curve_33ms'][:14]}")
Path(OPTIONS.out).write_text(json.dumps(report, indent=1))
