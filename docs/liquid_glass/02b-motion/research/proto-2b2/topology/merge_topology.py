import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Per-frame topology of native material.merge with the harness's video topology mask, its join and split gaps, and the tracker against hand labels.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--labels", required=True)
ARGS.add_argument("--frames", required=True, help="scratch folder for the extracted full-resolution crops")
ARGS.add_argument("--out", required=True)
ARGS.add_argument("--region", default="61,399,280,104")
ARGS.add_argument("cases", nargs="+", help="label=native folder")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import analyze
import metrics
import shapes
import track

DIAMETER = 80.0
REST_SPAN = 2 * DIAMETER + 80.0
region = [float(v) for v in OPTIONS.region.split(",")]
px = track.pixel_rect(region)
labels = json.loads(Path(OPTIONS.labels).read_text())["cases"]


def value(number):
    return round(float(number), 2) if np.isfinite(number) else None


results = {}
for spec in OPTIONS.cases:
    name, folder = spec.split("=", 1)
    folder = Path(folder)
    frames = track.extract(folder / "video.mp4", px, Path(OPTIONS.frames) / name)
    bare = track.crop_px(metrics.load(folder / "bare" / "ready.png"), px)
    edge_map = track.edges(bare)
    start, end = analyze.window(folder)[:2]
    clipped = track.clip(frames, max(0.0, start - shapes.LEAD_SECONDS), end)
    clipped = track.teardown_cut(clipped, track.crop_px(metrics.load(folder / "settled.png"), px))
    order = {str(path): i for i, path in enumerate(frames.paths)}
    window = [order[str(path)] for path in clipped.paths]
    wanted = sorted(set(window) | {f["index"] for f in labels.get(name, {}).get("frames", [])})
    rows = {}
    for i in wanted:
        frame = metrics.load(frames.paths[i])
        box = track.shape_row(frame, bare, edge_map, (0, 0))
        new = track.topology_row(frame, bare)
        old = track.topology(track.glass_mask(frame, bare, edge_map))
        rows[i] = {"index": i, "t": round(frames.times[i], 6), "width": round(box["width"], 2), "count": new["count"], "neck": value(new["neck"]), "count_l1_mask": old["count"]}
    pad = (rows[window[0]]["width"] - REST_SPAN) / 2
    for row in rows.values():
        row["gap_pt"] = round(row["width"] - 2 * DIAMETER - 2 * pad, 2)
    transitions = []
    for a, b in zip(window, window[1:]):
        before, after = rows[a], rows[b]
        if before["count"] >= 2 and after["count"] == 1:
            transitions.append({"kind": "join", "index": b, "t": after["t"], "gap_before": before["gap_pt"], "gap_at": after["gap_pt"], "neck_at": after["neck"], "dt_ms": round((after["t"] - before["t"]) * 1000, 1)})
        if before["count"] == 1 and after["count"] >= 2:
            transitions.append({"kind": "split", "index": b, "t": after["t"], "gap_before": before["gap_pt"], "gap_at": after["gap_pt"], "neck_before": before["neck"], "dt_ms": round((after["t"] - before["t"]) * 1000, 1)})
    compared = []
    for labelled in labels.get(name, {}).get("frames", []):
        row = rows[labelled["index"]]
        compared.append({"index": labelled["index"], "group": labelled["group"], "label": labelled["label"], "tracker": row["count"], "l1_mask": row["count_l1_mask"], "gap_pt": row["gap_pt"], "neck": row["neck"]})
    window_counts = [rows[i]["count"] for i in window]
    results[name] = {
        "folder": str(folder),
        "pad": round(pad, 2),
        "window": [window[0], window[-1]],
        "window_counts": sorted(set(window_counts)),
        "window_l1_counts": sorted(set(rows[i]["count_l1_mask"] for i in window)),
        "transitions": transitions,
        "labels_compared": len(compared),
        "labels_disagreeing": [c for c in compared if c["tracker"] != c["label"]],
        "labels_l1_mask_disagreeing": sum(1 for c in compared if c["l1_mask"] != c["label"]),
        "compared": compared,
        "frames": [rows[i] for i in window],
    }
    print(name, "pad", round(pad, 2), "counts", sorted(set(window_counts)), "label disagreements", len(results[name]["labels_disagreeing"]), "of", len(compared), json.dumps(transitions))
Path(OPTIONS.out).write_text(json.dumps(results, indent=1))
