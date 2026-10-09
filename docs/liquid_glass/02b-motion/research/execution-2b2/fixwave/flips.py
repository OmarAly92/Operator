import json
import math
import sys
from pathlib import Path

RUNS = Path("/Users/omaraly/development/AI/Operator-2b2/packages/mobile/build/glass_lab/runs")


def entry(r, name):
    parts = name.split(".")
    if parts[0] != "motion" or len(parts) < 5:
        return None
    shape, label, key = parts[1], parts[2], parts[3]
    return r["shapes"]["pairs"].get(label, {}).get("shapes", {}).get(shape, {}).get(key)


def side(e, measure):
    if e is None:
        return "absent"
    if "native_spring" in e or "flutter_spring" in e:
        n, f = e.get("native_spring"), e.get("flutter_spring")
        fn = lambda s: f"{s['response']:.2f}/{s['damping']:.2f}" if s else "-"
        return f"N {fn(n)} F {fn(f)}"
    if "native" in e and isinstance(e["native"], dict) and "joins_ms" in e["native"]:
        return f"N j{[round(x) for x in e['native']['joins_ms']]} s{[round(x) for x in e['native']['splits_ms']]} F j{[round(x) for x in e['flutter']['joins_ms']]} s{[round(x) for x in e['flutter']['splits_ms']]}"
    return ""


def main(a_run, b_run, scene, cases):
    fs = {"flutter_same": 0, "flutter_moved": 0, "other": 0}
    for case in cases:
        a = json.loads((RUNS / a_run / scene / case / "result.json").read_text())
        b = json.loads((RUNS / b_run / scene / case / "result.json").read_text())
        names = sorted(set(a["measures"]) | set(b["measures"]))
        flips = [n for n in names if a["checks"].get(n) != b["checks"].get(n)]
        print(f"== {scene} {case}: pass {sum(a['checks'].values())} -> {sum(b['checks'].values())}, flips {len(flips)} (A->fail {sum(1 for n in flips if a['checks'].get(n))}, A->pass {sum(1 for n in flips if b['checks'].get(n))})")
        for n in flips:
            va, vb = a["measures"].get(n, [None] * 3), b["measures"].get(n, [None] * 3)
            sa, sb = side(entry(a, n), n), side(entry(b, n), n)
            print(f"   {n}: {va[0] if va[0] is None else round(va[0],3)}<={round(va[1],3) if va[1] else va[1]} {a['checks'].get(n)} -> {vb[0] if vb[0] is None else round(vb[0],3)}<={round(vb[1],3) if vb[1] else vb[1]} {b['checks'].get(n)} | {sa} || {sb}")
        for lab in a["shapes"]["pairs"]:
            da = a["shapes"]["pairs"][lab].get("delay", {})
            db = b["shapes"]["pairs"].get(lab, {}).get("delay", {})
            print(f"   delay {lab}: N {da.get('native')} -> {db.get('native')}; F {da.get('flutter')} -> {db.get('flutter')}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:])
