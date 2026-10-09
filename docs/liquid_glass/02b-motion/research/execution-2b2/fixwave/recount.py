import json
import math
import sys
from pathlib import Path

H = Path("/Users/omaraly/development/AI/Operator-2b2/packages/mobile/tool/glass_lab/harness")
sys.path.insert(0, str(H))
import manifest
import shapes
import metrics

NOISE = json.loads((H.parent / "noise.json").read_text())
SCENES = {s.id: s for s in manifest.load()}
STATIC = {"mad", "luminance", "rim_rms", "bbox_pt", "centre_pt", "count", "neck_pt", "gap_pt"}


def noise_for(scene_id, case):
    entry = NOISE.get(scene_id) or {}
    if entry and all(isinstance(v, dict) for v in entry.values()):
        return entry.get(case, {})
    return entry


def key_of(name):
    last = name.split(".")[-1]
    if last in shapes.LIMITS:
        return shapes.LIMITS[last]
    return last


def within(v, l, b):
    if not math.isfinite(v):
        return False
    return v >= l - 1e-9 if b == "min" else v <= l + 1e-9


def recount(path, verbose=False):
    r = json.loads(Path(path).read_text())
    scene_id, case = r["scene"], r["case"]
    scene = SCENES[scene_id]
    noise = noise_for(scene_id, case)
    m, c = r["measures"], r["checks"]
    out = {"limit_diff": [], "check_diff": [], "missing_declared": []}
    declared = []
    if "shapes" in r:
        labels = list(r["shapes"].get("pairs", {}))
        declared = shapes.expected({"pairs": {lab: None for lab in labels}}, scene)
        for name in declared:
            if f"motion.{name}" not in m:
                out["missing_declared"].append(name)
    passed = judged = 0
    for name, (v, l, b) in m.items():
        bare = name[len("motion."):] if name.startswith("motion.") else name
        if bare.startswith(("events.", "touches.")):
            exp_l = l
        else:
            k = key_of(bare)
            exp_l = max(metrics.THRESHOLDS[k], 1.5 * noise.get(bare, 0.0))
        if abs(exp_l - l) > 1e-6:
            out["limit_diff"].append((name, l, exp_l))
        ok = within(v, exp_l, b)
        if ok != c[name]:
            out["check_diff"].append((name, v, l, c[name]))
        passed += ok
        judged += math.isfinite(v)
    expected = len(m) + len(out["missing_declared"])
    out.update(passed=passed, judged=judged, expected=expected, stored_pass=sum(c.values()))
    ev = r.get("shapes", {})
    out["events"] = ev.get("event_count")
    out["touches"] = ev.get("touches")
    out["pairs"] = list(ev.get("pairs", {}).keys())
    return out


if __name__ == "__main__":
    for run in sys.argv[1:]:
        for p in sorted(Path(run).glob("*/*/result.json")):
            r = json.loads(p.read_text())
            if r.get("kind") != "compared":
                print(p.parent.parent.name, p.parent.name, r.get("kind"))
                continue
            o = recount(p)
            print(f"{Path(run).name} {p.parent.parent.name} {p.parent.name}: {o['passed']}/{o['judged']}/{o['expected']} stored_pass {o['stored_pass']} events {o['events']} touches {o['touches']} pairs {o['pairs']} limdiff {len(o['limit_diff'])} chkdiff {len(o['check_diff'])} missing {len(o['missing_declared'])}")
            for d in o["limit_diff"][:5]:
                print("   LIMIT", d)
            for d in o["check_diff"][:5]:
                print("   CHECK", d)
