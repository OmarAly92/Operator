import argparse
import sys
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Read the touch windows of a native material.interactive take: the 1.0 s press must read 0.8-1.2 s (gotcha 49).")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("take")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import analyze
import manifest
import shapes

scene = manifest.select(manifest.load(), "material.interactive")[0]
found = analyze.window(Path(OPTIONS.take))
capture = shapes.capture(scene, Path(OPTIONS.take), found[:2])
touches = capture["touches"]
print("touches", [[round(a, 3), round(b, 3)] for a, b in touches])
press = touches[0][1] - touches[0][0] if touches else float("nan")
print(f"press {press:.3f} s {'PASS' if 0.8 <= press <= 1.2 else 'FAIL'}")
