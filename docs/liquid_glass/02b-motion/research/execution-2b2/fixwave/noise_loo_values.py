import json
import math
import sys
from pathlib import Path

H = Path("/Users/omaraly/development/AI/Operator-2b2/packages/mobile/tool/glass_lab/harness")
sys.path.insert(0, str(H))
import analyze
import shapes


def key_of(name):
    last = name.split(".")[-1]
    return shapes.LIMITS.get(last, last)


def pair_values(result):
    found = shapes.measures(result["shapes"]) if "shapes" in result else {
        n: v for n, (v, _) in analyze.motion_measures(result.get("motion", {"events": []})).items()
    }
    found.update({n: v for n, (v, _, _) in result.get("measures", {}).items() if not n.startswith("motion.")})
    return {n: v for n, v in found.items() if math.isfinite(v)}


def read_pairs(case_dir):
    pairs = {}
    for pd in sorted(Path(case_dir).glob("pair-*")):
        rp = pd / "result.json"
        if not rp.exists():
            continue
        _, a, b = pd.name.split("-", 2)
        pairs[(a, b)] = pair_values(json.loads(rp.read_text()))
    return pairs
