import argparse
import sys
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Per video frame of one app's capture of a scene: the time, and for every topology region the component count, the neck thickness and the gap, from the harness's own capture.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--scene", required=True)
ARGS.add_argument("app_dir")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import analyze
import manifest
import shapes

scene = {s.id: s for s in manifest.load()}[OPTIONS.scene]
case = Path(OPTIONS.app_dir)
found = analyze.window(case)
capture = shapes.capture(scene, case, found[:2] if found else None)
print("touches", capture["touches"])
for name in scene.topology:
    rows = capture["rows"][name]
    print(name, "time count neck gap")
    for time, row in zip(rows["times"], rows["rows"]):
        print(f"{time:.3f} {row.get('count')} {row.get('neck'):.2f} {row.get('gap'):.2f}")
