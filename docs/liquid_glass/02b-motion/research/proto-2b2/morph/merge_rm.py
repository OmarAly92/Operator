import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Per-frame gap, component count and neck of native material.merge (two 80 pt circles) from frames cached by extract.py, the spring of the gap on each tap, and the gaps at which the circles join and split; normal and Reduce Motion side by side.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--out", required=True)
ARGS.add_argument("cases", nargs="+", help="label=extract.py cache folder")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import measure
import metrics
import springfit
import track

DIAMETER = 80.0
REST_GAP = 80.0
ONSET_PT = 0.5


def crossing_ms(times, values, fraction):
    start, end = values[0], values[-1]
    level = start + fraction * (end - start)
    for (t0, v0), (t1, v1) in zip(zip(times, values), zip(times[1:], values[1:])):
        if (v0 - level) * (v1 - level) <= 0 and v1 != v0:
            return (t0 + (level - v0) / (v1 - v0) * (t1 - t0)) * 1000
    return None


def frame_rows(index, bare, edge_map):
    rows = []
    for i, t in enumerate(index["times"]):
        if i > index["teardown_last"]:
            break
        image = metrics.load(index["paths"][i])
        mask = track.glass_mask(image, bare, edge_map)
        found = measure.stack_topology(mask.T)
        if not found["extent"]:
            continue
        left, right = found["extent"][0][0], found["extent"][-1][1]
        rows.append({"i": i, "t": t, "left": left, "right": right, "width": right - left, "count": found["count"], "necks": [n["width"] for n in found["necks"]]})
    return rows


def event(rows, down, up, pad, until):
    before = [r for r in rows if r["t"] < down - 0.05]
    chosen = before[-1:] + [r for r in rows if down - 0.05 <= r["t"] <= until]
    for r in chosen:
        r["gap"] = round(r["width"] - 2 * DIAMETER - 2 * pad, 2)
    first = chosen[0]
    start = next((r for r in chosen if abs(r["gap"] - first["gap"]) > ONSET_PT), None)
    if start is None:
        return {"onset_ms_from_up": None}
    previous = chosen[chosen.index(start) - 1]
    moving = [previous] + chosen[chosen.index(start) :]
    times = [0.0] + [r["t"] - previous["t"] for r in moving[1:]]
    gaps = [r["gap"] for r in moving]
    transitions = []
    for a, b in zip(chosen, chosen[1:]):
        if a["count"] != b["count"]:
            transitions.append({"ms_from_up": round((b["t"] - up) * 1000, 1), "from": a["count"], "to": b["count"], "gap_before": a["gap"], "gap_after": b["gap"], "neck_before": min(a["necks"]) if a["necks"] else None, "neck_after": min(b["necks"]) if b["necks"] else None})
    t10, t90 = crossing_ms(times, gaps, 0.1), crossing_ms(times, gaps, 0.9)
    return {
        "onset_ms_from_up": round((previous["t"] - up) * 1000, 1),
        "gap_start": gaps[0],
        "gap_end": gaps[-1],
        "gap_extreme": min(gaps) if gaps[-1] < gaps[0] else max(gaps),
        "fit": springfit.fit(times, gaps),
        "features": springfit.features(times, gaps),
        "t10_ms": round(t10, 1) if t10 is not None else None,
        "t90_ms": round(t90, 1) if t90 is not None else None,
        "transitions": transitions,
        "series": [{"ms_from_up": round((r["t"] - up) * 1000, 1), "gap": r["gap"], "count": r["count"], "neck": min(r["necks"]) if r["necks"] else None} for r in chosen],
    }


report = {}
for spec in OPTIONS.cases:
    label, cache = spec.split("=", 1)
    index = json.loads((Path(cache) / "index.json").read_text())
    rect = index["rect_px"]
    bare = track.crop_px(metrics.load(Path(index["folder"]) / "bare" / "ready.png"), rect)
    edge_map = track.edges(bare)
    rows = frame_rows(index, bare, edge_map)
    (down1, up1), (down2, up2) = index["touches"][:2]
    rest = [r for r in rows if r["t"] < down1 - 0.05][-1]
    pad = (rest["width"] - 2 * DIAMETER - REST_GAP) / 2
    entry = {"pad": round(pad, 3), "rest_width": rest["width"], "touches": index["touches"], "merge": event(rows, down1, up1, pad, down2 - 0.05), "split": event(rows, down2, up2, pad, index["times"][index["teardown_last"]])}
    report[label] = entry
    for name in ("merge", "split"):
        e = entry[name]
        print(label, name, "onset", e.get("onset_ms_from_up"), "gap", e.get("gap_start"), "->", e.get("gap_end"), "extreme", e.get("gap_extreme"), "fit", e.get("fit"), "t10/90", e.get("t10_ms"), e.get("t90_ms"), "ovs", (e.get("features") or {}).get("overshoot_pct"), "transitions", e.get("transitions"), flush=True)
Path(OPTIONS.out).write_text(json.dumps(report, indent=0))
