import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ARGS = argparse.ArgumentParser(description="Measure native material.union stills: each union's silhouette (box, end radius, top straightness), the gap between the unions, the content glyph positions, and the difference from candidate shapes drawn at 3 px per point.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--out", required=True)
ARGS.add_argument("--crops", default=None)
ARGS.add_argument("--ring", type=float, default=8.0, help="silhouette barrier: max-channel difference from bare, lossless stills")
ARGS.add_argument("cases", nargs="+", help="label=native folder")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import metrics
import track
from silhouette import silhouette

SCALE = 3
MEMBER = 64.0
SPACING = 16.0
SCREEN_CX = 201.0
SUPERSAMPLE = 4
GLYPH_LUMA = 60.0
GLYPH_MIN_PX = 30

members_left = SCREEN_CX - (4 * MEMBER + 3 * SPACING) / 2
LAYOUT = [(members_left + i * (MEMBER + SPACING), members_left + i * (MEMBER + SPACING) + MEMBER) for i in range(4)]


def column_runs(mask):
    present = mask.any(axis=0)
    runs, start = [], None
    for i, v in enumerate(present):
        if v and start is None:
            start = i
        if not v and start is not None:
            runs.append((start, i - 1))
            start = None
    if start is not None:
        runs.append((start, len(present) - 1))
    return runs


def kasa(xs, ys):
    design = np.stack([xs, ys, np.ones_like(xs)], axis=1)
    (a, b, c), *_ = np.linalg.lstsq(design, xs * xs + ys * ys, rcond=None)
    cx, cy = a / 2, b / 2
    r = np.sqrt(c + cx * cx + cy * cy)
    residual = np.sqrt(np.mean((np.hypot(xs - cx, ys - cy) - r) ** 2))
    return {"cx": float(cx), "cy": float(cy), "r": float(r), "rms": float(residual)}


def capsule(shape, box):
    left, top, right, bottom = (v * SCALE * SUPERSAMPLE for v in box)
    height, width = shape
    image = Image.new("L", (width * SUPERSAMPLE, height * SUPERSAMPLE), 0)
    draw = ImageDraw.Draw(image)
    radius = (bottom - top) / 2
    draw.rounded_rectangle((left, top, right - 1, bottom - 1), radius=radius, fill=255)
    small = np.asarray(image, dtype=np.float32).reshape(height, SUPERSAMPLE, width, SUPERSAMPLE).mean(axis=(1, 3))
    return small >= 127.5


def circles(shape, centres, radius, cy):
    height, width = shape
    ys = (np.arange(height) + 0.5) / SCALE
    xs = (np.arange(width) + 0.5) / SCALE
    x, y = np.meshgrid(xs, ys)
    mask = np.zeros(shape, dtype=bool)
    for cx in centres:
        mask |= np.hypot(x - cx, y - cy) <= radius
    return mask


def edges(mask):
    top = np.array([np.nonzero(col)[0][0] if col.any() else -1 for col in mask.T])
    left = np.array([np.nonzero(row)[0][0] if row.any() else -1 for row in mask])
    right = np.array([np.nonzero(row)[0][-1] if row.any() else -1 for row in mask])
    return top, left, right


def compare(native, model):
    nt, nl, nr = edges(native)
    mt, ml, mr = edges(model)
    cols = (nt >= 0) & (mt >= 0)
    rows = (nl >= 0) & (ml >= 0)
    return {
        "xor_pt2": round(float((native ^ model).sum()) / SCALE**2, 2),
        "top_max_pt": round(float(np.abs(nt[cols] - mt[cols]).max()) / SCALE, 2) if cols.any() else None,
        "side_max_pt": round(float(max(np.abs(nl[rows] - ml[rows]).max(), np.abs(nr[rows] - mr[rows]).max())) / SCALE, 2) if rows.any() else None,
        "only_native_pt2": round(float((native & ~model).sum()) / SCALE**2, 2),
        "only_model_pt2": round(float((model & ~native).sum()) / SCALE**2, 2),
    }


def measure_union(mask, frame, a, b, index):
    part = np.zeros_like(mask)
    part[:, a : b + 1] = mask[:, a : b + 1]
    ys, xs = np.nonzero(part)
    left, right = xs.min() / SCALE, (xs.max() + 1) / SCALE
    top, bottom = ys.min() / SCALE, (ys.max() + 1) / SCALE
    height = bottom - top
    cy = (top + bottom) / 2
    rows = np.arange(ys.min(), ys.max() + 1)
    lefts = np.array([np.nonzero(part[r])[0][0] for r in rows])
    rights = np.array([np.nonzero(part[r])[0][-1] + 1 for r in rows])
    yy = (rows + 0.5) / SCALE
    end_left = kasa(lefts / SCALE, yy)
    end_right = kasa(rights / SCALE, yy)
    cols = np.arange(xs.min(), xs.max() + 1)
    tops = np.array([np.nonzero(part[:, c])[0][0] for c in cols]) / SCALE
    bottoms = np.array([np.nonzero(part[:, c])[0][-1] + 1 for c in cols]) / SCALE
    xx = (cols + 0.5) / SCALE
    middle = (xx > left + height / 2) & (xx < right - height / 2)
    flat_top = float(np.median(tops[middle]))
    on_flat = np.nonzero(np.abs(tops - flat_top) < 0.5 / SCALE)[0]
    pair = LAYOUT[2 * index : 2 * index + 2]
    lum = metrics.luma(frame)
    dark = part & (lum < GLYPH_LUMA)
    glyphs = []
    for area, (gx, gy, gw, gh) in metrics._components(dark):
        if area >= GLYPH_MIN_PX:
            glyphs.append({"cx": round((gx + gw / 2) / SCALE, 2), "cy": round((gy + gh / 2) / SCALE, 2), "w": round(gw / SCALE, 2), "h": round(gh / SCALE, 2)})
    glyphs.sort(key=lambda g: g["cx"])
    band = int(round((cy - 20) * SCALE))
    row = lum[band, :]
    probe = {f"x{x:.0f}": round(float(row[int(x * SCALE)]), 1) for x in [(pair[0][0] + pair[0][1]) / 2, (pair[0][1] + pair[1][0]) / 2, (pair[1][0] + pair[1][1]) / 2]}
    model_capsule = capsule(mask.shape, (left, top, right, bottom))
    model_circles = circles(mask.shape, [(p[0] + p[1]) / 2 for p in pair], MEMBER / 2, cy)
    return {
        "box": {"left": round(left, 2), "right": round(right, 2), "top": round(top, 2), "bottom": round(bottom, 2), "width": round(right - left, 2), "height": round(height, 2), "cy": round(cy, 2)},
        "layout": {"left": pair[0][0], "right": pair[1][1], "width": pair[1][1] - pair[0][0], "members": pair},
        "end_left": {k: round(v, 3) for k, v in kasa(lefts[lefts < lefts.min() + height / 2 * SCALE] / SCALE, yy[lefts < lefts.min() + height / 2 * SCALE]).items()},
        "end_right": {k: round(v, 3) for k, v in kasa(rights[rights > rights.max() - height / 2 * SCALE] / SCALE, yy[rights > rights.max() - height / 2 * SCALE]).items()},
        "top_flat": {"level": round(flat_top, 3), "range_middle_pt": round(float(tops[middle].max() - tops[middle].min()), 3), "first_flat_x": round(float(xx[on_flat[0]]), 2), "last_flat_x": round(float(xx[on_flat[-1]]), 2), "circle_flat_from": round(left + height / 2, 2), "circle_flat_to": round(right - height / 2, 2)},
        "bottom_range_middle_pt": round(float(bottoms[middle].max() - bottoms[middle].min()), 3),
        "glyphs": glyphs,
        "luma_row_cy_minus_20": probe,
        "vs_circle_capsule_of_box": compare(part, model_capsule & (np.arange(mask.shape[1])[None, :] >= a) & (np.arange(mask.shape[1])[None, :] <= b)),
        "vs_member_circles": compare(part, model_circles),
    }


report = {"layout_members": LAYOUT}
for spec in OPTIONS.cases:
    label, folder = spec.split("=", 1)
    folder = Path(folder)
    frame = metrics.load(folder / "ready.png")
    settled = metrics.load(folder / "settled.png")
    bare = metrics.load(folder / "bare" / "ready.png")
    top, bottom = 380 * SCALE, 520 * SCALE
    crop, bare_crop = frame[top:bottom], bare[top:bottom]
    mask = silhouette(crop, bare_crop, OPTIONS.ring)
    runs = [r for r in column_runs(mask) if r[1] - r[0] > 20 * SCALE]
    count = len([1 for area, _ in metrics._components(track.point_mask(mask)) if area >= track.TOPOLOGY_MIN_AREA])
    entry = {"ready_vs_settled_max": float(np.abs(frame - settled).max()), "components": count, "column_runs": len(runs), "unions": []}
    for index, (a, b) in enumerate(runs[:2]):
        found = measure_union(mask, crop, a, b, index)
        for key in ("box",):
            for k in ("top", "bottom", "cy"):
                found[key][k] = round(found[key][k] + top / SCALE, 2)
        for g in found["glyphs"]:
            g["cy"] = round(g["cy"] + top / SCALE, 2)
        for side in ("end_left", "end_right"):
            found[side]["cy"] = round(found[side]["cy"] + top / SCALE, 3)
        found["top_flat"]["level"] = round(found["top_flat"]["level"] + top / SCALE, 3)
        entry["unions"].append(found)
    if len(entry["unions"]) == 2:
        entry["gap_between_unions"] = round(entry["unions"][1]["box"]["left"] - entry["unions"][0]["box"]["right"], 2)
    report[label] = entry
    print(label, json.dumps(entry)[:1500], flush=True)
    if OPTIONS.crops:
        Path(OPTIONS.crops).mkdir(parents=True, exist_ok=True)
        Image.fromarray(np.clip(frame[400 * SCALE : 500 * SCALE, 40 * SCALE : 362 * SCALE], 0, 255).astype(np.uint8)).save(Path(OPTIONS.crops) / f"union-{label}.png")
Path(OPTIONS.out).write_text(json.dumps(report, indent=1))
