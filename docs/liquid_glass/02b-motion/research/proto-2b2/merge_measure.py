import argparse
import dataclasses
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Per-frame topology of native material.merge: the gap between the circles from the outer span, the component count and the neck, and the gap at each join and split.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--out", required=True)
ARGS.add_argument("--region", default="61,399,280,104")
ARGS.add_argument("cases", nargs="+", help="label=native folder")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import analyze
import manifest
import shapes

DIAMETER = 80.0
base = manifest.select(manifest.load(), "material.merge")[0]
region = [float(v) for v in OPTIONS.region.split(",")]
scene = dataclasses.replace(base, regions={"pair": region}, track=("pair",), topology=("pair",))
results = {}
for spec in OPTIONS.cases:
    label, folder = spec.split("=", 1)
    folder = Path(folder)
    found = analyze.window(folder)
    capture = shapes.capture(scene, folder, found[:2])
    rows = capture["rows"]["pair"]
    times, values = rows["times"], rows["rows"]
    rest = values[0]
    pad = (rest["width"] - (2 * DIAMETER + 80.0)) / 2
    frames = []
    for t, row in zip(times, values):
        gap = row["width"] - 2 * DIAMETER - 2 * pad if row["width"] > 0 else float("nan")
        frames.append({"t": round(t, 4), "width": round(row["width"], 2), "gap": round(gap, 2), "count": row["count"], "neck": None if not np.isfinite(row["neck"]) else round(row["neck"], 2), "band": bool(row.get("band"))})
    transitions = []
    for i in range(1, len(frames)):
        a, b = frames[i - 1], frames[i]
        if a["count"] >= 2 and b["count"] == 1:
            transitions.append({"kind": "join", "t": b["t"], "gap_before": a["gap"], "gap_at": b["gap"], "neck_at": b["neck"], "dt_ms": round((b["t"] - a["t"]) * 1000, 1)})
        if a["count"] == 1 and b["count"] >= 2:
            transitions.append({"kind": "split", "t": b["t"], "gap_before": a["gap"], "gap_at": b["gap"], "neck_before": a["neck"], "dt_ms": round((b["t"] - a["t"]) * 1000, 1)})
    results[label] = {"pad": round(pad, 2), "rest": {k: rest[k] for k in ("width", "height", "count")}, "transitions": transitions, "touches": capture["touches"], "frames": frames}
    print(label, "pad", round(pad, 2), json.dumps(transitions))
Path(OPTIONS.out).write_text(json.dumps(results, indent=0))
