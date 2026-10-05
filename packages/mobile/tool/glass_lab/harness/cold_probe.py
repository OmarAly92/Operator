import json
import sys
import time
from pathlib import Path

sys.path.insert(0, "tool/glass_lab/harness")

import analyze
import build
import manifest
import record
import shapes
import sim

SCENE = "material.materialize"
TOOL = "tool.materialize.cold"


def main(native_case, appearance="dark", backdrop="photo"):
    build.require_fresh("example")
    scene = {s.id: s for s in manifest.load()}[SCENE]
    udid = sim.device()
    sim.appearance(udid, appearance)
    out = build.OUT / "cold" / time.strftime("%Y%m%d-%H%M%S")
    record.drive(udid, build.EXAMPLE_BUNDLE, scene.id, [], backdrop, True, out / "bare", settle=1.0, marker=True)
    with record.Recording(udid, out / "video.mp4"):
        record.drive(udid, build.EXAMPLE_BUNDLE, TOOL, scene.steps, backdrop, False, out, marker=True)
    found = {}
    for app, folder in (("native", Path(native_case) / "native"), ("flutter", out)):
        window = analyze.window(folder)
        capture = shapes.capture(scene, folder, window[:2] if window else None)
        found[app] = {
            "stalls": capture.get("stalls", []),
            "events": [
                {"step": event["step"], "first_frame": event["first_frame"], "t10_90_ms": (shapes.progress_features(event["series"]["block"]) or {}).get("t10_90_ms")}
                for event in capture["events"]
            ],
        }
    print(json.dumps(found, indent=2))
    print(out)


if __name__ == "__main__":
    main(*sys.argv[1:])
