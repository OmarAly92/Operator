import argparse
import json
import math
from collections import defaultdict
from pathlib import Path

ARGS = argparse.ArgumentParser(description="N7 spacing run: per spacing, gap and case the native and Flutter component count, neck and gap from result.json with each topology check, and each app's dark-against-light gap agreement.")
ARGS.add_argument("run")
ARGS.add_argument("--out", required=True)
OPTIONS = ARGS.parse_args()


def num(v):
    return None if v is None or (isinstance(v, float) and not math.isfinite(v)) else round(v, 2)


rows = defaultdict(dict)
fails = []
for path in sorted(Path(OPTIONS.run).glob("material.spacing.*/*/result.json")):
    result = json.loads(path.read_text())
    scene, case = path.parent.parent.name, path.parent.name
    spacing = scene.split(".")[2]
    spacing = "8 (default)" if spacing == "default" else spacing
    if result.get("kind") != "compared":
        fails.append(f"{scene} {case}: {result.get('kind')}")
        continue
    for name, entry in result["topology"].items():
        key = (spacing, int(name[1:]))
        checks = {m: result["checks"][f"ready.topology.{name}.{m}"] for m in ("count", "neck_pt", "gap_pt")}
        rows[key][case] = {app: {k: num(entry[app][k]) for k in ("count", "neck", "gap")} for app in ("native", "flutter")}
        rows[key][case]["checks"] = checks
        rows[key][case]["scene"] = scene
    for name, ok in result["checks"].items():
        if not ok:
            value, limit, _ = result["measures"][name]
            fails.append(f"{scene} {case} FAIL {name} {num(value) if num(value) is not None else 'absent'} > {limit}")


def order(key):
    s = key[0].split(" ")[0]
    return (int(s), key[1])


lines = ["spacing gap | dark-photo native count/neck/gap ; flutter count/neck/gap ; checks c/n/g | light-photo same | dark-light gap: native, flutter"]
for key in sorted(rows, key=order):
    parts = [f"S{key[0]:>11s} g{key[1]:>3d}"]
    gaps = {}
    for case in ("dark-photo", "light-photo"):
        e = rows[key].get(case)
        if not e:
            parts.append(f"{case}: missing")
            continue
        n, f, c = e["native"], e["flutter"], e["checks"]
        parts.append(f"{case[:1]}: N {n['count']}/{n['neck']}/{n['gap']} F {f['count']}/{f['neck']}/{f['gap']} {''.join('.' if c[m] else 'X' for m in ('count', 'neck_pt', 'gap_pt'))}")
        gaps[case] = (n["gap"], f["gap"])
    if len(gaps) == 2:
        d = [None if gaps["dark-photo"][i] is None or gaps["light-photo"][i] is None else round(gaps["dark-photo"][i] - gaps["light-photo"][i], 2) for i in (0, 1)]
        parts.append(f"d-l gap N {d[0]} F {d[1]}")
    lines.append(" | ".join(parts))
lines.append("")
lines += fails
Path(OPTIONS.out).write_text("\n".join(lines) + "\n")
print("\n".join(lines))
