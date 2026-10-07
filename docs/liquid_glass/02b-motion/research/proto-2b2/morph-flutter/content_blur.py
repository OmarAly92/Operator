import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Fit the Gaussian blur (in points) of a morphing glass's glyph with measure.find_glyph: the template is the glyph cropped from a sharp rest frame of the same take, matched over a window in each frame of a time span. Prints and writes the per-frame blur, scale and NCC, and the median blur over the frames whose NCC passes.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--out", required=True)
ARGS.add_argument("--glyph", type=float, default=14.0, help="template half size in points")
ARGS.add_argument("--reach", type=float, default=14.0, help="search reach around the expected centre in points")
ARGS.add_argument("--min-ncc", type=float, default=0.8)
ARGS.add_argument("specs", nargs="+", help="label=cache_dir:touch:rest_ms:rest_cy:from_ms:to_ms:cx:cy[:cy_end] (touch 0 or 1, times from that touch's up; the template is cut at (cx, rest_cy) from the frame nearest rest_ms; the glyph centre moves linearly from cy to cy_end over the span)")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "morph"))

import measure
import metrics


def frame_at(index, ms, up):
    times = index["times"]
    return int(np.argmin([abs(t - (up + ms / 1000)) for t in times]))


def crop(gray, origin, cx, cy, half):
    s = metrics.SCALE
    top, left = int(round((cy - origin[1] - half) * s)), int(round((cx - origin[0] - half) * s))
    return gray[max(0, top) : top + int(2 * half * s), max(0, left) : left + int(2 * half * s)]


report = {}
for spec in OPTIONS.specs:
    label, rest = spec.split("=", 1)
    parts = rest.split(":")
    cache, touch, rest_ms, rest_cy, start_ms, end_ms, cx, cy = parts[0], int(parts[1]), *map(float, parts[2:8])
    cy_end = float(parts[8]) if len(parts) > 8 else cy
    index = json.loads((Path(cache) / "index.json").read_text())
    origin = (index["rect_px"][0] / metrics.SCALE, index["rect_px"][1] / metrics.SCALE)
    up = index["touches"][touch][1]
    rest_index = frame_at(index, rest_ms, up)
    template = crop(metrics.luma(metrics.load(index["paths"][rest_index])), origin, cx, rest_cy, OPTIONS.glyph)
    rows = []
    for i, t in enumerate(index["times"]):
        ms = (t - up) * 1000
        if not (start_ms <= ms <= end_ms) or i > index["teardown_last"]:
            continue
        fraction = 0.0 if end_ms == start_ms else (ms - start_ms) / (end_ms - start_ms)
        expected = cy + (cy_end - cy) * fraction
        window = crop(metrics.luma(metrics.load(index["paths"][i])), origin, cx, expected, OPTIONS.glyph + OPTIONS.reach)
        found = measure.find_glyph(window, template)
        if found is None:
            continue
        rows.append({"i": i, "ms": round(ms, 1), "blur": found["blur"], "scale": found["scale"], "ncc": round(found["ncc"], 3)})
        print(label, i, round(ms, 1), found["blur"], found["scale"], round(found["ncc"], 3), flush=True)
    good = [r["blur"] for r in rows if r["ncc"] >= OPTIONS.min_ncc]
    report[label] = {"spec": spec, "rest_frame": rest_index, "rows": rows, "median_blur": float(np.median(good)) if good else None, "frames": len(good)}
    print(label, "median blur", report[label]["median_blur"], "over", len(good), "frames", flush=True)
pooled = [r["blur"] for entry in report.values() for r in entry["rows"] if r["ncc"] >= OPTIONS.min_ncc and 0 < r["blur"] < measure.FINE_BLURS[-1]]
report["pooled"] = {"median_blur": float(np.median(pooled)) if pooled else None, "frames": len(pooled), "rule": "frames of every span with ncc >= min_ncc and a blur inside the search grid, excluding 0 (sharp)"}
print("pooled median blur", report["pooled"]["median_blur"], "over", len(pooled), "frames", flush=True)
Path(OPTIONS.out).write_text(json.dumps(report, indent=1))
