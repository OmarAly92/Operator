import json
import math
import sys
from pathlib import Path

H = Path("/Users/omaraly/development/AI/Operator-2b2/packages/mobile/tool/glass_lab/harness")
sys.path.insert(0, str(H))
sys.path.insert(0, str(Path(__file__).parent))
import metrics
import shapes
import analyze


def key_of(name):
    last = name.split(".")[-1]
    return shapes.LIMITS.get(last, last)


def pair_values(result):
    found = shapes.measures(result["shapes"]) if "shapes" in result else {
        n: v for n, (v, _) in analyze.motion_measures(result.get("motion", {"events": []})).items()
    }
    found.update({n: v for n, (v, _, _) in result.get("measures", {}).items() if not n.startswith("motion.")})
    return {n: v for n, v in found.items() if math.isfinite(v)}

RUNS = Path("/Users/omaraly/development/AI/Operator-2b2/packages/mobile/build/glass_lab/runs")
NOISE_ROOT = RUNS / "noise-2b2"
COUNTED = {
    "material.merge": {"": "20261008-043622", "rm": "20261008-044149"},
    "material.morph": {"": "20261008-044933", "rm": "20261008-050026"},
    "material.morph.plain": {"": "20261008-044933", "rm": "20261008-050026"},
    "material.respace": {"": "20261008-041322"},
}
OVERRIDE = {("material.morph.plain", "dark-stripes"): "20261008-071523", ("material.morph", "dark-photo-reduce-motion"): "20261008-071642"}


def judged_path(scene, case):
    if (scene, case) in OVERRIDE:
        return RUNS / OVERRIDE[(scene, case)] / scene / case / "result.json"
    run = COUNTED[scene]["rm" if case.endswith("reduce-motion") else ""]
    return RUNS / run / scene / case / "result.json"


def count(result, noise):
    p = 0
    flips = []
    for name, (v, l, b) in result["measures"].items():
        bare = name[len("motion."):] if name.startswith("motion.") else name
        if bare.startswith(("events.", "touches.")):
            lim = l
        else:
            lim = max(metrics.THRESHOLDS[key_of(bare)], 1.5 * noise.get(bare, 0.0))
        ok = math.isfinite(v) and (v >= lim - 1e-9 if b == "min" else v <= lim + 1e-9)
        p += ok
        if ok != result["checks"][name]:
            flips.append((name, round(v, 3), round(l, 3), round(lim, 3)))
    return p, flips


for scene in sys.argv[1:]:
    for case_dir in sorted((NOISE_ROOT / scene).iterdir()):
        jp = judged_path(scene, case_dir.name)
        if not jp.exists():
            continue
        result = json.loads(jp.read_text())
        pairs = {}
        for pd in sorted(case_dir.glob("pair-*")):
            _, a, b = pd.name.split("-", 2)
            pairs[(a, b)] = pair_values(json.loads((pd / "result.json").read_text()))
        takes = sorted({t for ab in pairs for t in ab})
        base, _ = count(result, {n: max(v[n] for v in pairs.values() if n in v) for n in {n for v in pairs.values() for n in v}})
        line = []
        for t in takes:
            keep = [v for ab, v in pairs.items() if t not in ab]
            noise = {}
            for v in keep:
                for n, x in v.items():
                    noise[n] = max(noise.get(n, 0.0), x)
            p, flips = count(result, noise)
            line.append(f"t{t}:{p}")
            if base - p >= 3:
                print(f"   {scene} {case_dir.name} without take {t}: {base} -> {p}; {flips[:6]}")
        print(f"{scene} {case_dir.name} ({jp.parent.parent.parent.name}) pass {base}/{len(result['measures'])}: leave-one-out {' '.join(line)}")
