import argparse
import json
import sys
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Check native motion takes with the capture-hole rule and the touch gate (todo-2b1, task9scan), and print each event's first frames.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--scene", required=True)
ARGS.add_argument("takes", nargs="+")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import analyze
import manifest
import shapes
import touch

PRESS = (0.8, 1.2)
PRESS_DRAG = (1.0, 1.6)
scene = manifest.select(manifest.load(), OPTIONS.scene)[0]
steps = touch.touch_steps(scene.steps)
kinds = [next(iter(scene.steps[i])) for i in steps]
expected = touch.expected_touches(scene.steps)
report = []
for take in OPTIONS.takes:
    folder = Path(take)
    found = analyze.window(folder)
    capture = shapes.capture(scene, folder, found[:2])
    name = scene.track[0]
    times = capture["rows"][name]["times"]
    rows = capture["rows"][name]["rows"]
    windows = capture["touches"]
    failures = []
    if len(windows) != expected:
        failures.append(f"touch count {len(windows)} != {expected}")
    for index, (kind, window) in enumerate(zip(kinds, windows)):
        length = window[1] - window[0]
        if kind == "press" and not PRESS[0] <= length <= PRESS[1]:
            failures.append(f"press {length:.3f} s")
        if kind == "pressDrag" and not PRESS_DRAG[0] <= length <= PRESS_DRAG[1]:
            failures.append(f"press-drag {length:.3f} s")
    owned = {event["step"] for event in capture["events"]}
    failures += [f"touch step {step} owns no event" for step in steps if step not in owned]
    events = []
    for event in capture["events"]:
        first = times.index(event["onset"]) - 1
        gap1 = (times[first + 1] - times[first]) * 1000
        gap2 = (times[first + 2] - times[first + 1]) * 1000 if first + 2 < len(times) else 0.0
        burst = sum(1 for k in range(first + 1, min(first + 11, len(times) - 1)) if (times[k + 1] - times[k]) * 1000 < 5.0)
        kind = kinds[steps.index(event["step"])] if event["step"] in steps else None
        zero = event["step"] in steps and steps.index(event["step"]) < len(windows) and abs(windows[steps.index(event["step"])][1] - windows[steps.index(event["step"])][0]) < 1e-6
        hole = gap1 > 30 or gap2 > 30
        tap = kind in ("tap", "doubleTap")
        rule = (hole and zero) if tap else (hole or zero)
        flagged = (rule and hole and burst >= 2) or (tap and hole and burst >= 2)
        if flagged:
            failures.append(f"capture hole at step {event['step']}")
        progress = [round(rows[k]["progress"], 3) for k in range(first, min(first + 4, len(rows)))]
        events.append({"step": event["step"], "onset": round(event["onset"], 3), "gap1_ms": round(gap1, 1), "gap2_ms": round(gap2, 1), "burst": burst, "first_frame": event.get("first_frame", {}).get(name), "progress_first_frames": progress, "frame_gaps_ms": [round((times[k + 1] - times[k]) * 1000, 1) for k in range(first, min(first + 6, len(times) - 1))]})
    entry = {"take": take, "touches": [[round(a, 3), round(b, 3)] for a, b in windows], "events": events, "failures": failures, "verdict": "PASS" if not failures else "FAIL"}
    report.append(entry)
    print(json.dumps(entry))
