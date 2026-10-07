import argparse
import json
import math
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Every failing motion measure of material.merge with the native value, the Flutter value (each app's own feature from series_dump.py) and the limit (from result.json).")
ARGS.add_argument("--run", required=True)
ARGS.add_argument("--series", required=True)
ARGS.add_argument("--out", required=True)
OPTIONS = ARGS.parse_args()
series = json.loads(Path(OPTIONS.series).read_text())
lines = []
for path in sorted(Path(OPTIONS.run).glob("material.merge/*/result.json")):
    result = json.loads(path.read_text())
    case = path.parent.name
    dump = series[case]
    lines.append(f"== {case}")
    for name, (value, limit, _) in result["measures"].items():
        if result["checks"][name] or not name.startswith("motion."):
            continue
        parts = name.split(".")
        if len(parts) < 5:
            lines.append(f"  {name}: {value} limit {limit}")
            continue
        shape, label, key, measure = parts[1], parts[2], parts[3], parts[4]
        shown = "absent" if not math.isfinite(value) else f"{value:.3g}"
        if key == "topology":
            topo = result["shapes"]["pairs"][label]["shapes"][shape]["topology"]
            lines.append(f"  {shape} {label} topology.{measure}: |diff| {shown} limit {limit}; native joins {topo['native']['joins_ms']} splits {topo['native']['splits_ms']}; flutter joins {topo['flutter']['joins_ms']} splits {topo['flutter']['splits_ms']}")
            continue
        own = dump["pairs"][label]["shapes"][shape][key]
        n, f = own["native"], own["flutter"]
        if measure in ("response_pct", "damping"):
            nv = f"{n['spring']['response']:.2f}/{n['spring']['damping']:.2f} rms {n['spring']['rms']:.3f}" if n and n.get("spring") else "-"
            fv = f"{f['spring']['response']:.2f}/{f['spring']['damping']:.2f} rms {f['spring']['rms']:.3f}" if f and f.get("spring") else "-"
        else:
            nv = f"{n.get(measure):.4g}" if n and n.get(measure) is not None else f"none (travel {n['travel']:.2f})" if n else "-"
            fv = f"{f.get(measure):.4g}" if f and f.get(measure) is not None else f"none (travel {f['travel']:.2f})" if f else "-"
        lines.append(f"  {shape} {label} {key}.{measure}: native {nv} | flutter {fv} | |diff| {shown} limit {limit}")
Path(OPTIONS.out).write_text("\n".join(lines) + "\n")
print(len(lines))
