import json
import math
import sys
from collections import defaultdict
from pathlib import Path

H = Path("/Users/omaraly/development/AI/Operator-2b2/packages/mobile/tool/glass_lab/harness")
sys.path.insert(0, str(H))
import analyze
import metrics
import shapes

NOISE = json.loads((H.parent / "noise.json").read_text())
ROOT = Path(sys.argv[1])
SCENES = sys.argv[2:] if len(sys.argv) > 2 else None


def key_of(name):
    last = name.split(".")[-1]
    return shapes.LIMITS.get(last, last)


def pair_values(result):
    found = shapes.measures(result["shapes"]) if "shapes" in result else {
        n: v for n, (v, _) in analyze.motion_measures(result.get("motion", {"events": []})).items()
    }
    found.update({n: v for n, (v, _, _) in result.get("measures", {}).items() if not n.startswith("motion.")})
    return {n: v for n, v in found.items() if math.isfinite(v)}


totals = defaultdict(int)
per_take = defaultdict(lambda: defaultdict(list))
mismatch = 0
for scene_dir in sorted(p for p in ROOT.iterdir() if p.is_dir() and p.name != "takes"):
    if SCENES and scene_dir.name not in SCENES:
        continue
    for case_dir in sorted(p for p in scene_dir.iterdir() if p.is_dir()):
        pairs = {}
        for pd in sorted(case_dir.glob("pair-*")):
            rp = pd / "result.json"
            if not rp.exists():
                continue
            _, a, b = pd.name.split("-", 2)
            pairs[(a, b)] = pair_values(json.loads(rp.read_text()))
        takes = sorted({t for ab in pairs for t in ab})
        names = sorted({n for v in pairs.values() for n in v})
        stored = NOISE.get(scene_dir.name, {}).get(case_dir.name, {})
        for n in names:
            vals = {ab: v[n] for ab, v in pairs.items() if n in v}
            worst = max(vals.values())
            if abs(worst - stored.get(n, float("nan"))) > 1e-6:
                mismatch += 1
            try:
                fixed = metrics.THRESHOLDS[key_of(n)]
            except KeyError:
                continue
            lim = max(fixed, 1.5 * worst)
            totals["measure_cases"] += 1
            for t in takes:
                rest = [v for ab, v in vals.items() if t not in ab]
                lo = max(fixed, 1.5 * max(rest)) if rest else fixed
                if lo < lim - 1e-9:
                    per_take[(scene_dir.name, case_dir.name)][t].append((n, round(worst, 3), round(lim, 3), round(lo, 3)))
            single = [t for t in takes if any(x[0] == n for x in per_take[(scene_dir.name, case_dir.name)][t])]
            if len(single) == 1:
                totals["single_take_sets_limit"] += 1
            elif len(single) == 2:
                totals["pair_sets_limit"] += 1

print("noise.json mismatches", mismatch)
print(dict(totals))
for (s, c), d in sorted(per_take.items()):
    for t, rows in sorted(d.items(), key=lambda kv: -len(kv[1])):
        big = sorted(rows, key=lambda r: -(r[2] / max(r[3], 1e-9)))[:4]
        print(f"{s} {c} take {t}: lowers {len(rows)} limits if excluded; e.g. {big}")
