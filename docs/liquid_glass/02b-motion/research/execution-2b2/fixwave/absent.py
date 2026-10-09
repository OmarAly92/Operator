import json
import math
import sys
from collections import Counter
from pathlib import Path

RUNS = Path("/Users/omaraly/development/AI/Operator-2b2/packages/mobile/build/glass_lab/runs")
SETS = {
    "normal": [("20261008-044933", s, c) for s in ("material.morph", "material.morph.plain") for c in ("dark-photo", "dark-stripes", "light-photo", "light-stripes") if not (s == "material.morph.plain" and c == "dark-stripes")] + [("20261008-071523", "material.morph.plain", "dark-stripes")],
    "rm": [("20261008-050026", s, c + "-reduce-motion") for s in ("material.morph", "material.morph.plain") for c in ("dark-photo", "dark-stripes", "light-photo", "light-stripes") if not (s == "material.morph" and c == "dark-photo")] + [("20261008-071642", "material.morph", "dark-photo-reduce-motion")],
}

for mode, cases in SETS.items():
    why = Counter()
    fails = absent = 0
    shape_why = Counter()
    for run, scene, case in cases:
        r = json.loads((RUNS / run / scene / case / "result.json").read_text())
        for name, (v, l, b) in r["measures"].items():
            if r["checks"][name]:
                continue
            fails += 1
            if math.isfinite(v):
                continue
            absent += 1
            parts = name.split(".")
            if parts[0] != "motion" or len(parts) < 5:
                why["non-motion inf"] += 1
                continue
            shape, label, key, measure = parts[1], parts[2], parts[3], parts[4]
            pair = r["shapes"]["pairs"].get(label)
            if pair is None:
                why["label not paired (touch step event absent)"] += 1
                continue
            entry = pair["shapes"].get(shape, {}).get(key)
            if entry is None:
                why[f"key absent (travel under minimum on a side, or NaN series)"] += 1
                shape_why[(shape, key)] += 1
                continue
            if "fit_invalid" in entry:
                sides = tuple(sorted(entry["fit_invalid"]))
                kinds = tuple(sorted({p.split()[0] for p in entry["fit_invalid"].values()}))
                why[f"fit invalid {sides} {kinds}"] += 1
                continue
            if key == "topology":
                why[f"topology {measure} inf (join/split present in one app only)"] += 1
                continue
            why["other inf"] += 1
    print(f"== {mode}: failing {fails}, of which non-finite {absent}")
    for k, n in why.most_common():
        print(f"   {n:4d} {k}")
    print("   key-absent by shape/key:", dict(shape_why.most_common()))
