import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Compare the morph toggle's size curve on each tap with the 58 pt interactive circle's 1.0 s press (N2, material.press.circle58, same centre): the widest row of the silhouette (every glass is centred on x = 201 pt, so this is the widest glass) against time, with the bottom-cap circle fit kept beside it from touch-down and from touch-up.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--press", nargs="+", required=True, help="label=extract.py cache folder of a circle58 press")
ARGS.add_argument("--morph", nargs="+", required=True, help="label=morph_track.py json")
ARGS.add_argument("--out", required=True)
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import measure
import metrics
import track


def press_series(cache):
    index = json.loads((Path(cache) / "index.json").read_text())
    rect = index["rect_px"]
    origin = (rect[0] / metrics.SCALE, rect[1] / metrics.SCALE)
    bare = track.crop_px(metrics.load(Path(index["folder"]) / "bare" / "ready.png"), rect)
    edge_map = track.edges(bare)
    down, up = index["touches"][0]
    rows = []
    for i, t in enumerate(index["times"]):
        if t < down - 1.0 or t > up + 1.0 or i > index["teardown_last"]:
            continue
        image = metrics.load(index["paths"][i])
        mask = track.glass_mask(image, bare, edge_map)
        fit = measure.cap_fit(mask, "bottom")
        shape = measure.profile(mask)
        rows.append({"i": i, "t": t, "from_down_ms": round((t - down) * 1000, 1), "from_up_ms": round((t - up) * 1000, 1), "diameter": round(2 * float(shape["half"].max()), 2), "cap_diameter": round(2 * fit["r"], 2) if fit else None, "cy": round(fit["cy"] + origin[1], 2) if fit else None})
    return {"touch": [down, up], "rows": rows}


def toggle_series(path, event):
    report = json.loads(Path(path).read_text())
    rows = []
    touches = report["touches"][0 if event == "expand" else 1]
    for row in report[event]["rows"]:
        toggle = row["caps"]["bottom"]
        widest = max([l["width"] for l in row["lobes"]] or [0.0])
        if toggle is None or widest <= 0:
            continue
        rows.append({"i": row["i"], "t": row["t"], "from_down_ms": round((row["t"] - touches[0]) * 1000, 1), "from_up_ms": round((row["t"] - touches[1]) * 1000, 1), "diameter": widest, "cap_diameter": round(2 * toggle["r"], 2), "cy": toggle["cy"]})
    return {"touch": touches, "rows": rows}


def summary(series):
    rows = [r for r in series["rows"] if r["diameter"] is not None]
    rest = float(np.median([r["diameter"] for r in rows if r["from_down_ms"] <= 0]))
    peak = max(rows, key=lambda r: r["diameter"])
    onset = next((r for r in rows if r["from_down_ms"] >= 0 and r["diameter"] - rest > 1.0), None)
    level = rest + 0.9 * (peak["diameter"] - rest)
    reach90 = next((r for r in rows if r["from_down_ms"] >= 0 and r["diameter"] >= level), None)
    return {
        "rest_diameter": round(rest, 2),
        "peak_diameter": peak["diameter"],
        "growth": round(peak["diameter"] - rest, 2),
        "peak_from_down_ms": peak["from_down_ms"],
        "peak_from_up_ms": peak["from_up_ms"],
        "onset_from_down_ms": onset["from_down_ms"] if onset else None,
        "onset_from_up_ms": onset["from_up_ms"] if onset else None,
        "reach90_from_down_ms": reach90["from_down_ms"] if reach90 else None,
        "hold_ms": round((series["touch"][1] - series["touch"][0]) * 1000, 1),
    }


report = {"law": "growth = min(16.82, 1014 / h) pt (results-2b1.md, fix2-press-size-law.json)", "press": {}, "toggle": {}}
for spec in OPTIONS.press:
    label, cache = spec.split("=", 1)
    series = press_series(cache)
    report["press"][label] = {"summary": summary(series), "rows": series["rows"]}
    print("press", label, report["press"][label]["summary"], flush=True)
for spec in OPTIONS.morph:
    label, path = spec.split("=", 1)
    for event in ("expand", "collapse"):
        series = toggle_series(path, event)
        report["toggle"][f"{label}.{event}"] = {"summary": summary(series), "rows": series["rows"]}
        print("toggle", label, event, report["toggle"][f"{label}.{event}"]["summary"], flush=True)
Path(OPTIONS.out).write_text(json.dumps(report, indent=0))
