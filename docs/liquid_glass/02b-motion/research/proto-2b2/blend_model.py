import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Draw two 80 pt circles joined by a candidate smooth union at 3 px per point, measure them with the harness's neck and the N7 tip measure, and fit each candidate's blend k to native's necks and tips.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--native", required=True, help="json of native measures: {series: {gap: {neck, tip}}}")
ARGS.add_argument("--out", required=True)
ARGS.add_argument("--pad", type=float, default=0.0, help="points the native mask reaches past the silhouette")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import track

SCALE = 3
RADIUS = 40.0


def field(model, gap, k, width=None):
    width = width or (2 * RADIUS + gap + 24)
    height = 2 * RADIUS + 24
    xs = (np.arange(int(width * SCALE)) + 0.5) / SCALE - width / 2
    ys = (np.arange(int(height * SCALE)) + 0.5) / SCALE - height / 2
    x, y = np.meshgrid(xs, ys)
    cx = RADIUS + gap / 2
    r1 = np.hypot(x + cx, y)
    r2 = np.hypot(x - cx, y)
    a, b = r1 - RADIUS, r2 - RADIUS
    if k <= 0:
        return np.minimum(a, b), x
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    if model == "quadratic":
        return np.minimum(a, b) - h * h * k / 4, x
    if model == "angle":
        dot = ((x + cx) * (x - cx) + y * y) / np.maximum(r1 * r2, 1e-9)
        return np.minimum(a, b) - h * h * k / 4 * (1 - dot) / 2, x
    if model == "cubic":
        return np.minimum(a, b) - h ** 3 * k / 6, x
    raise ValueError(model)


def measure(model, gap, k, pad):
    f, x = field(model, gap, k)
    mask = f < pad
    found = track.topology(mask)
    row = mask[mask.shape[0] // 2]
    inside = np.nonzero(row)[0]
    xs = x[0]
    tip = None
    if found["count"] == 2:
        left = inside[inside < len(row) // 2]
        tip = float(xs[left.max()] + 0.5 / SCALE) - (-gap / 2)
    return {"count": found["count"], "neck": None if not np.isfinite(found["neck"]) else found["neck"], "tip": tip}


def score(model, k, series, pad):
    errors = []
    for gap, native in series.items():
        found = measure(model, float(gap), k, pad)
        if native.get("neck") is not None:
            errors.append((found["neck"] if found["neck"] is not None else 0.0) - native["neck"])
        if native.get("tip") is not None:
            errors.append((found["tip"] if found["tip"] is not None else float(gap) / 2) - native["tip"])
    return float(np.sqrt(np.mean(np.square(errors)))) if errors else float("nan")


native = json.loads(Path(OPTIONS.native).read_text())
report = {}
for name, series in native.items():
    report[name] = {}
    for model in ("quadratic", "angle", "cubic"):
        grid = np.arange(2.0, 101.0, 2.0)
        scores = [score(model, k, series, OPTIONS.pad) for k in grid]
        coarse = float(grid[int(np.nanargmin(scores))])
        grid = np.arange(max(0.5, coarse - 2.0), coarse + 2.01, 0.1)
        scores = [score(model, k, series, OPTIONS.pad) for k in grid]
        best = round(float(grid[int(np.nanargmin(scores))]), 2)
        detail = {gap: measure(model, float(gap), best, OPTIONS.pad) for gap in series}
        report[name][model] = {"k": best, "rms": round(float(np.nanmin(scores)), 3), "predicted": detail}
        print(name, model, "k", best, "rms", round(float(np.nanmin(scores)), 3), flush=True)
Path(OPTIONS.out).write_text(json.dumps(report, indent=1))
