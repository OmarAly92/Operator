import sys
from pathlib import Path
sys.path.insert(0, "tool/glass_lab/harness")
import analyze, manifest, shapes
scene = {s.id: s for s in manifest.load()}[sys.argv[1]]
case = Path(sys.argv[2])
found = analyze.window(case)
cap = shapes.capture(scene, case, found[:2] if found else None)
print("touches", cap["touches"], "events", [(e["onset"], e["step"]) for e in cap["events"]])
for name, rows in cap["rows"].items():
    print(name)
    t = rows["times"]
    for i, (ti, r) in enumerate(zip(t, rows["rows"])):
        print(f"  {ti:.3f} cx={r.get('cx')} width={r.get('width')} count={r.get('count')}")
