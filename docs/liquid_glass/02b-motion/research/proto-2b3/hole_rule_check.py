import argparse
import sys
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Apply the take check to a list of takes (scene=take), with every frame cache in a scratch folder, so archived takes are only read.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--cache", required=True)
ARGS.add_argument("takes", nargs="+")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import manifest
import takecheck

scenes = {s.id: s for s in manifest.load()}
for index, item in enumerate(OPTIONS.takes):
    scene_id, take = item.split("=", 1)
    result = takecheck.check(scenes[scene_id], Path(take), cache=Path(OPTIONS.cache) / str(index))
    print("PASS" if not result["failures"] else "FAIL", scene_id, "/".join(Path(take).parts[-4:]), "; ".join(result["failures"]), flush=True)
