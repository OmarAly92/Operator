import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

ARGS = argparse.ArgumentParser(description="Union scene: the ink extents of each glyph in one app's ready.png, by the threshold union_tone.py uses for both apps.")
ARGS.add_argument("--ready", required=True)
OPTIONS = ARGS.parse_args()
S = 3
frame = np.asarray(Image.open(OPTIONS.ready).convert("RGB"), dtype=np.float32)
found = {}
for name, cx in (("star", 81), ("heart", 161), ("bolt", 241), ("leaf", 321)):
    crop = frame[430 * S : 472 * S, (cx - 21) * S : (cx + 21) * S]
    ys, xs = np.nonzero(crop.max(axis=2) < 40)
    found[name] = None if len(xs) == 0 else {"w_pt": round((xs.max() - xs.min() + 1) / S, 2), "h_pt": round((ys.max() - ys.min() + 1) / S, 2)}
print(json.dumps(found))
