import sys
from pathlib import Path
sys.path.insert(0, "tool/glass_lab/harness")
import analyze, manifest, shapes
scene = {s.id: s for s in manifest.load()}[sys.argv[1]]
case = Path(sys.argv[2])
lo, hi = float(sys.argv[3]), float(sys.argv[4])
found = analyze.window(case)
cap = shapes.capture(scene, case, found[:2] if found else None)
names = list(cap["rows"])
times = cap["rows"][names[0]]["times"]
print("time", *names)
for i, t in enumerate(times):
    if lo <= t <= hi:
        print(f"{t:.3f}", *[f"{cap['rows'][n]['rows'][i].get('cy', float('nan')):.1f}/{cap['rows'][n]['rows'][i].get('height', 0):.0f}" for n in names])
