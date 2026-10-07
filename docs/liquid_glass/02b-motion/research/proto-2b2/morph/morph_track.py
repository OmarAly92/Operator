import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Per-frame silhouette tracks of native material.morph from frames cached by extract.py: the stack's extent, components, lobes and necks, and a circle fitted to each lobe, with the median luma of a ring inside each fitted circle (outside the other circles) and the content sharpness at its centre.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--cache", required=True, help="case folder written by extract.py")
ARGS.add_argument("--out", required=True)
ARGS.add_argument("--before", type=float, default=0.12)
ARGS.add_argument("--after", type=float, default=1.3)
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import measure
import metrics
import track

CONTENT_HALF = 10.0
RING = (0.55, 0.85)

cache = Path(OPTIONS.cache)
index = json.loads((cache / "index.json").read_text())
folder = Path(index["folder"])
rect = index["rect_px"]
origin = (rect[0] / metrics.SCALE, rect[1] / metrics.SCALE)
times = index["times"]
last = index["teardown_last"]
bare = track.crop_px(metrics.load(folder / "bare" / "ready.png"), rect)
edge_map = track.edges(bare)
down1, up1 = index["touches"][0]
down2, up2 = index["touches"][1]


def content(gray, fit, others):
    s = metrics.SCALE
    cy, cx = (fit["cy"] - origin[1]) * s, (fit["cx"] - origin[0]) * s
    half = CONTENT_HALF * s
    top, left = int(round(cy - half)), int(round(cx - half))
    box = gray[max(0, top) : top + int(2 * half), max(0, left) : left + int(2 * half)]
    sharp = track.laplacian(np.repeat(box[..., None], 3, axis=2)) if box.shape[0] > 2 and box.shape[1] > 2 else float("nan")
    ys, xs = np.mgrid[0 : gray.shape[0], 0 : gray.shape[1]]
    distance = np.hypot(ys - cy, xs - cx)
    inside = (distance >= RING[0] * fit["r"] * s) & (distance <= RING[1] * fit["r"] * s)
    for other in others:
        oy, ox = (other["cy"] - origin[1]) * s, (other["cx"] - origin[0]) * s
        inside &= np.hypot(ys - oy, xs - ox) > other["r"] * s
    values = gray[inside]
    return {"sharp": round(sharp, 3), "luma": round(float(np.median(values)), 2) if values.size else None, "luma_px": int(values.size)}


def measure_frame(i):
    image = metrics.load(index["paths"][i])
    mask = track.glass_mask(image, bare, edge_map)
    topology = measure.stack_topology(mask)
    fits = measure.fit_circles(mask, [l["y"] for l in topology["lobes"]], [l["width"] / 2 for l in topology["lobes"]])
    glass = []
    for lobe, fit in zip(topology["lobes"], fits):
        if fit is None:
            continue
        glass.append({"lobe_y": round(lobe["y"] + origin[1], 2), "lobe_width": round(lobe["width"], 2), "cy": round(fit["cy"] + origin[1], 3), "cx": round(fit["cx"] + origin[0], 3), "r": round(fit["r"], 3), "rows_pt": round(fit["rows_pt"], 2), "rms": round(fit["rms"], 3)})
    gray = metrics.luma(image)
    for n, g in enumerate(glass):
        g.update(content(gray, g, [o for m, o in enumerate(glass) if m != n]))
    caps = {}
    for side in ("top", "bottom"):
        cap = measure.cap_fit(mask, side)
        caps[side] = None if cap is None else {"cy": round(cap["cy"] + origin[1], 3), "r": round(cap["r"], 3), "edge": round(cap["edge"] + origin[1], 2), "rows_pt": round(cap["rows_pt"], 2)}
    return {
        "caps": caps,
        "count": topology["count"],
        "extent": [[round(a + origin[1], 2), round(b + origin[1], 2)] for a, b in topology["extent"]],
        "lobes": [{"y": round(l["y"] + origin[1], 2), "width": round(l["width"], 2)} for l in topology["lobes"]],
        "necks": [{"y": round(n["y"] + origin[1], 2), "width": round(n["width"], 2)} for n in topology["necks"]],
        "glass": glass,
    }


def event(start, end, zero):
    rows = []
    for i in [i for i, t in enumerate(times) if start <= t <= end and i <= last]:
        row = {"i": i, "t": round(times[i], 6), "ms": round((times[i] - zero) * 1000, 1), **measure_frame(i)}
        rows.append(row)
        print(i, row["ms"], row["count"], row["extent"], [(g["cy"], g["r"]) for g in row["glass"]], flush=True)
    return rows


report = {
    "case": cache.name,
    "folder": str(folder),
    "origin_pt": origin,
    "touches": index["touches"],
    "expand": {"zero": up1, "rows": event(down1 - OPTIONS.before, up1 + OPTIONS.after, up1)},
    "collapse": {"zero": up2, "rows": event(down2 - OPTIONS.before, up2 + OPTIONS.after, up2)},
}
Path(OPTIONS.out).write_text(json.dumps(report, indent=0))
