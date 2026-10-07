import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

ARGS = argparse.ArgumentParser(description="Union scene: per-stripe RGB and luma inside the glass (a band clear of the glyphs), the shadow profile below each capsule, and the glyph ink extents, native against Flutter.")
ARGS.add_argument("--case", required=True, help="material.union/<case> folder")
ARGS.add_argument("--out", required=True)
OPTIONS = ARGS.parse_args()
case = Path(OPTIONS.case)
S = 3


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)


def luma(a):
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


apps = {app: {"ready": load(case / app / "ready.png"), "bare": load(case / app / "bare" / "ready.png")} for app in ("native", "flutter")}
stripes = [(59, 67), (72, 130), (139, 197), (206, 264), (273, 331), (336, 344)]
band = (426, 433)
found = {"band_y_pt": band, "stripes": []}
for x0, x1 in stripes:
    row = {"x_pt": [x0, x1]}
    for app, frames in apps.items():
        part = frames["ready"][band[0] * S : band[1] * S, x0 * S : x1 * S].reshape(-1, 3)
        bare = frames["bare"][band[0] * S : band[1] * S, x0 * S : x1 * S].reshape(-1, 3)
        row[app] = {"rgb": [round(float(v), 1) for v in part.mean(axis=0)], "luma": round(float(luma(part).mean()), 1), "bare_luma": round(float(luma(bare).mean()), 1)}
    row["flutter_minus_native_luma"] = round(row["flutter"]["luma"] - row["native"]["luma"], 1)
    found["stripes"].append(row)
shadow = {}
for name, cx in (("first", 121), ("second", 281)):
    shadow[name] = {}
    for app, frames in apps.items():
        column = luma(frames["ready"][:, cx * S - 3 : cx * S + 3]).mean(axis=1) - luma(frames["bare"][:, cx * S - 3 : cx * S + 3]).mean(axis=1)
        shadow[name][app] = {f"{y / S:.2f}": round(float(column[y]), 1) for y in range(480 * S, 500 * S)}
found["shadow_below_minus_bare"] = shadow
ink = {}
for name, cx in (("star", 81), ("heart", 161), ("bolt", 241), ("leaf", 321)):
    ink[name] = {}
    for app, frames in apps.items():
        crop = frames["ready"][430 * S : 472 * S, (cx - 21) * S : (cx + 21) * S]
        light = case.name.startswith("light")
        mask = (crop.max(axis=2) < 40) if light else (crop.min(axis=2) > 235)
        ys, xs = np.nonzero(mask)
        ink[name][app] = None if len(xs) == 0 else {"w_pt": round((xs.max() - xs.min() + 1) / S, 2), "h_pt": round((ys.max() - ys.min() + 1) / S, 2), "cx_pt": round(cx - 21 + (xs.max() + xs.min() + 1) / 2 / S, 2), "cy_pt": round(430 + (ys.max() + ys.min() + 1) / 2 / S, 2), "area_pt2": round(len(xs) / S / S, 1)}
found["glyph_ink"] = ink
region = (36 * S, 407 * S, 366 * S, 495 * S)
n, f = apps["native"]["ready"][region[1] : region[3], region[0] : region[2]], apps["flutter"]["ready"][region[1] : region[3], region[0] : region[2]]
diff = np.abs(n - f).mean(axis=2)
glyph = np.zeros(diff.shape, dtype=bool)
for cx in (81, 161, 241, 321):
    glyph[(437 - 407) * S : (466 - 407) * S, (cx - 16 - 36) * S : (cx + 16 - 36) * S] = True
found["mad_split"] = {"total": round(float(diff.mean()), 3), "glyph_boxes_share": round(float(diff[glyph].sum() / diff.sum()), 3), "glyph_boxes_area_share": round(float(glyph.mean()), 3), "mad_outside_glyph_boxes": round(float(diff[~glyph].mean()), 3)}
Path(OPTIONS.out).write_text(json.dumps(found, indent=1))
for row in found["stripes"]:
    print(row["x_pt"], "native", row["native"]["luma"], "flutter", row["flutter"]["luma"], "bare", row["native"]["bare_luma"], "f-n", row["flutter_minus_native_luma"])
print("ink", json.dumps(ink))
print("mad", found["mad_split"])
for name in shadow:
    for app in ("native", "flutter"):
        values = shadow[name][app]
        print(name, app, "shadow min", min(values.values()), "at", min(values, key=values.get), "rows y 483-490:", [values[f"{y:.2f}"] for y in np.arange(483, 491, 1.0)])
