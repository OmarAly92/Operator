import argparse
import json
import math
import sys
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Per scene and case of a run: pass / judged / expected counts from result.json, and every failing measure with its value and limit; for motion measures also each app's own value where result.json keeps it (delays, joins, splits, springs).")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("runs", nargs="+")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import manifest
import shapes

SCENES = {s.id: s for s in manifest.load()}


def fmt(v):
    if isinstance(v, float):
        if not math.isfinite(v):
            return "absent" if v > 0 else "-inf"
        return f"{v:.3f}".rstrip("0").rstrip(".") if abs(v) < 1e6 else str(v)
    return str(v)


def sides(result, name):
    parts = name.split(".")
    if parts[0] != "motion" or len(parts) < 4:
        return ""
    if parts[-1] == "delay_ms":
        pair = result["shapes"]["pairs"].get(parts[1], {})
        d = pair.get("delay", {})
        return f" [native {fmt(d.get('native'))} flutter {fmt(d.get('flutter'))}]"
    shape, label, key, measure = parts[1], parts[2], parts[3], parts[-1]
    entry = result["shapes"]["pairs"].get(label, {}).get("shapes", {}).get(shape, {}).get(key)
    if entry is None:
        return " [key absent: an app's travel under the minimum or no pair]"
    if key == "topology":
        n, f = entry["native"], entry["flutter"]
        return f" [native joins {n['joins_ms']} splits {n['splits_ms']}; flutter joins {f['joins_ms']} splits {f['splits_ms']}]"
    if measure in ("response_pct", "damping"):
        ns, fs = entry.get("native_spring"), entry.get("flutter_spring")
        extra = f" fit_invalid {entry['fit_invalid']}" if "fit_invalid" in entry else ""
        if ns and fs:
            return f" [native {ns['response']:.2f}/{ns['damping']:.2f} rms {ns['rms']:.3f}; flutter {fs['response']:.2f}/{fs['damping']:.2f} rms {fs['rms']:.3f}{extra}]"
        return f" [{extra}]"
    return ""


for run in OPTIONS.runs:
    print(f"#### run {run}")
    for path in sorted(Path(run).glob("*/*/result.json")):
        result = json.loads(path.read_text())
        scene = SCENES.get(path.parent.parent.name)
        if result.get("kind") != "compared":
            print(f"{path.parent.parent.name} {path.parent.name}: {result.get('kind')}")
            continue
        measures, checks = result["measures"], result["checks"]
        expected = len(measures)
        if scene is not None and "shapes" in result:
            for name in shapes.expected({"pairs": {}}, scene):
                full = f"motion.{name}"
                if full not in measures:
                    expected += 1
                    print(f"   NOTE {full} not in result.json")
        judged = sum(1 for v in measures.values() if math.isfinite(v[0]))
        passed = sum(1 for k in measures if checks[k])
        static = [k for k in measures if not k.startswith("motion.")]
        motion = [k for k in measures if k.startswith("motion.")]
        sp, mp = sum(checks[k] for k in static), sum(checks[k] for k in motion)
        print(f"{path.parent.parent.name} {path.parent.name}: pass {passed} / judged {judged} / expected {expected} (static+topology {sp}/{len(static)}, motion {mp}/{len(motion)}); "
              f"events {result.get('shapes', {}).get('event_count')} touches {result.get('shapes', {}).get('touches')} stalls flutter {[round(s) for s in result.get('flutter_stalls', [])]} native {[round(s) for s in result.get('native_stalls', [])]}")
        for name in measures:
            if not checks[name]:
                value, limit, bound = measures[name]
                print(f"   FAIL {name} {fmt(value)} {'>' if bound == 'max' else '<'} {fmt(limit)}{sides(result, name)}")
