import json
import math
import sys
from pathlib import Path

H = Path("/Users/omaraly/development/AI/Operator-2b2/packages/mobile/tool/glass_lab/harness")
sys.path.insert(0, str(H))
sys.path.insert(0, "/Users/omaraly/development/AI/Operator-2b2/docs/liquid_glass/02b-motion/research/execution-2b2/fixwave")
import metrics
import recount


def limit_of(name, stored, rejudge):
    bare = name[len("motion."):] if name.startswith("motion.") else name
    if not rejudge or bare.startswith(("events.", "touches.")):
        return stored
    noise = recount.noise_for(CURRENT["scene"], CURRENT["case"])
    return max(metrics.THRESHOLDS[recount.key_of(bare)], 1.5 * noise.get(bare, 0.0))


CURRENT = {}


def compare(final_path, base_path, rejudge):
    f = json.loads(Path(final_path).read_text())
    b = json.loads(Path(base_path).read_text())
    CURRENT["scene"], CURRENT["case"] = f["scene"], f["case"]
    out = dict(new=0, under=0, only=0, lost=0, raised=0, passed=0, judged=0)
    for name, (v, l, bound) in f["measures"].items():
        lim = limit_of(name, l, rejudge)
        ok = recount.within(v, lim, bound)
        out["passed"] += ok
        out["judged"] += math.isfinite(v)
        base = b["measures"].get(name)
        base_ok = bool(b["checks"].get(name)) if base is not None else False
        if ok and not base_ok:
            out["new"] += 1
            if base is not None and recount.within(v, base[1], base[2]):
                out["under"] += 1
            elif base is None:
                out["under"] += 0
            else:
                out["only"] += 1
        if base_ok and not ok:
            out["lost"] += 1
        if base is not None and lim > base[1] + 1e-9:
            out["raised"] += 1
    return out


def total(pairs, rejudge):
    sums = {}
    for f, b in pairs:
        for k, v in compare(f, b, rejudge).items():
            sums[k] = sums.get(k, 0) + v
    return sums
