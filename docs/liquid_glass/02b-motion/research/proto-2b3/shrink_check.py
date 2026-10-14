import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Where shrink_ms differs between the apps: per press size, native's and Flutter's release time (from touch-up until the width stays within max(10 % of grow_w, 2/3 pt)), their growth, and the release time read with a band of 10 % of grow_w alone, which tells a size-dependent release from the measure's fixed 2/3 pt band on small growth.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--out", required=True)
ARGS.add_argument("takes", nargs="+", help="scene=app=take")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import analyze
import manifest
import press
import shapes

SCENES = {s.id: s for s in manifest.load()}
found = []
for item in OPTIONS.takes:
    scene_id, app, folder = item.split("=", 2)
    folder = Path(folder)
    window = analyze.window(folder)
    capture = shapes.capture(SCENES[scene_id], folder, window[:2] if window else None)
    rows = capture["rows"]["glass"]
    down, up = capture["touches"][0]
    later = [w[0] for w in capture["touches"] if w[0] > up]
    end = later[0] if later else float("inf")
    f = press.features(rows["times"], rows["rows"], (down, up), end)
    times = list(rows["times"])
    rest = rows["rows"][press.rest_index(times, down)]
    dw = np.array([r["width"] - rest["width"] for r in rows["rows"]], dtype=np.float64)
    after = [i for i, t in enumerate(times) if up < t < end]
    share_only = press.settle(times, dw, after, press.SETTLE_SHARE * f["grow_w"], up) if f["grow_w"] >= press.MIN_GROWTH else None
    entry = {"scene": scene_id, "case": folder.parent.name, "app": app, "take": str(folder), "hole": f["hole"], "grow_w": f["grow_w"], "shrink_ms": f["shrink_ms"], "shrink_ms_share_only": share_only}
    found.append(entry)
    print(json.dumps(entry), flush=True)
Path(OPTIONS.out).write_text(json.dumps(found, indent=1))
