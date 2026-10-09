import itertools
import json
import math
import re
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import noise_loo_values
import metrics
import recount

ROOT = Path("/Users/omaraly/development/AI/Operator-2b2/packages/mobile/build/glass_lab/runs/noise-2b2")
CHECK = HERE.parent / "noise-take-check.txt"
RUNS = {
    "normal": Path("/Users/omaraly/development/AI/Operator-2b2/packages/mobile/build/glass_lab/runs/20261008-044933"),
    "reduce-motion": Path("/Users/omaraly/development/AI/Operator-2b2/packages/mobile/build/glass_lab/runs/20261008-050026"),
}
RERUN_D = Path("/Users/omaraly/development/AI/Operator-2b2/packages/mobile/build/glass_lab/runs/20261008-071642")
SCENE = "material.morph"

verdicts = {}
for line in CHECK.read_text().splitlines():
    match = re.match(r"\| ([\w-]+)/(\d) \| (PASS|FAIL) \|", line)
    if match:
        verdicts[(match.group(1), match.group(2))] = match.group(3)
touch_owner = {("light-stripes-reduce-motion", "1")}
variants = {
    "27 capture-hole takes out": {k for k, v in verdicts.items() if v == "FAIL" and k not in touch_owner},
    "all 28 failing takes out": {k for k, v in verdicts.items() if v == "FAIL"},
}


def limits(values):
    out = {}
    for name, value in values.items():
        try:
            fixed = metrics.THRESHOLDS[noise_loo_values.key_of(name)]
        except KeyError:
            continue
        out[name] = max(fixed, 1.5 * value)
    return out


report = {}
for label, flagged in variants.items():
    cases = {}
    for case_dir in sorted(p for p in (ROOT / SCENE).iterdir() if p.is_dir()):
        case = case_dir.name
        pairs = noise_loo_values.read_pairs(case_dir)
        takes = sorted({t for ab in pairs for t in ab})
        kept = [t for t in takes if (case, t) not in flagged]
        row = {"takes": takes, "flagged": [t for t in takes if (case, t) in flagged], "kept": kept}
        if len(kept) < 2:
            row["computable"] = False
            cases[case] = row
            continue
        names = sorted({n for v in pairs.values() for n in v})
        noise_all, noise_kept = {}, {}
        for n in names:
            vals = {ab: v[n] for ab, v in pairs.items() if n in v}
            noise_all[n] = max(vals.values())
            sub = [v for ab, v in vals.items() if ab[0] in kept and ab[1] in kept]
            if sub:
                noise_kept[n] = max(sub)
        la, lk = limits(noise_all), limits(noise_kept)
        moved = {n: (la[n], lk.get(n)) for n in la if lk.get(n) is not None and abs(lk[n] - la[n]) > 1e-9}
        missing = [n for n in la if n not in lk]
        halved = sum(1 for a, b in moved.values() if b < 0.5 * a)

        def lowered(subset):
            sub_noise = {}
            for n in names:
                sub = [v[n] for ab, v in pairs.items() if n in v and ab[0] in subset and ab[1] in subset]
                if sub:
                    sub_noise[n] = max(sub)
            lim = limits(sub_noise)
            return sum(1 for n in la if lim.get(n, metrics.THRESHOLDS.get(noise_loo_values.key_of(n), 0.0)) < la[n] - 1e-9)

        control = [lowered(set(c)) for c in itertools.combinations(takes, len(kept))]
        row.update(
            computable=True,
            measures=len(la),
            limits_moved=len(moved),
            no_value_without=len(missing),
            moved_by_more_than_half=halved,
            control_same_size_subsets=len(control),
            control_limits_lowered_min_median_max=[min(control), statistics.median(control), max(control)],
        )
        suffix = "reduce-motion" if case.endswith("reduce-motion") else "normal"
        run = RERUN_D if case == "dark-photo-reduce-motion" else RUNS[suffix]
        path = run / SCENE / case / "result.json"
        original = recount.recount(path)
        saved = recount.NOISE[SCENE][case]
        recount.NOISE[SCENE][case] = {**saved, **noise_kept}
        for n in missing:
            recount.NOISE[SCENE][case][n] = 0.0
        alt = recount.recount(path)
        recount.NOISE[SCENE][case] = saved
        row["counts_with_all_takes"] = [original["passed"], original["judged"], original["expected"]]
        row["counts_without_flagged"] = [alt["passed"], alt["judged"], alt["expected"]]
        cases[case] = row
    report[label] = cases
print(json.dumps(report, indent=1))
