import argparse
import json
from collections import defaultdict
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Collect N7 measures by spacing, case and gap, and write the per-series necks and bulges the blend fit reads.")
ARGS.add_argument("--measures", nargs="+", required=True)
ARGS.add_argument("--case", required=True)
ARGS.add_argument("--series-out")
OPTIONS = ARGS.parse_args()

rows = defaultdict(list)
for path in OPTIONS.measures:
    for take in json.loads(Path(path).read_text()):
        if take["case"] != OPTIONS.case:
            continue
        spacing = take["scene"].split(".")[2]
        spacing = "8" if spacing == "default" else spacing
        for name, value in take["regions"].items():
            rows[(int(spacing), int(name[1:]))].append(value)
series = defaultdict(dict)
for (spacing, gap), values in sorted(rows.items()):
    counts = sorted({v["count"] for v in values})
    necks = sorted({v["neck"] for v in values if v.get("neck") is not None})
    pads = sorted({round((v.get("pad_left", 0) + v.get("pad_right", 0)) / 2, 2) for v in values})
    bulges = sorted({round(min(v["tip_left"] - v["pad_left"], v["tip_right"] - v["pad_right"]), 2) for v in values if v.get("tip_left") is not None})
    print(f"S{spacing:>3} g{gap:>3} n={len(values)} count {counts} neck {necks} bulge {bulges} pad {pads}")
    entry = {}
    if counts == [1.0] and len(necks) == 1:
        entry["neck"] = necks[0]
    if counts == [2.0] and len(bulges) == 1:
        entry["tip"] = bulges[0]
    if entry:
        series[f"S{spacing}"][str(gap)] = entry
if OPTIONS.series_out:
    Path(OPTIONS.series_out).write_text(json.dumps(series, indent=1))
