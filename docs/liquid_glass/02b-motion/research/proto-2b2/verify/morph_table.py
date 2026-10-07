import argparse
import json
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Compact native-against-Flutter table from morph_compare.py's json: per case and event, the toggle's onset, 10/90 % times, fit and width swing, the topology transitions, and per badge its first frame, extreme, size, fit and content sharp time.")
ARGS.add_argument("compare")
ARGS.add_argument("--cases", default="")
OPTIONS = ARGS.parse_args()
data = json.loads(Path(OPTIONS.compare).read_text())
wanted = [c for c in OPTIONS.cases.split(",") if c] or list(data)


def f(entry):
    if not entry:
        return "-"
    return f"{entry['response']:.2f}/{entry['damping']:.2f}" + (f" s{entry['start']}" if entry.get("start") is not None else "") + f" rms{entry['rms']}"


for case in wanted:
    for event, sides in data[case].items():
        print(f"== {case} {event}")
        for side in ("native", "flutter"):
            s = sides[side]
            t = s["toggle"]
            w = t["width"]
            counts = " ".join(f"{ms:.0f}:{a}>{b}" for ms, a, b in s["counts"][:8]) + (" ..." if len(s["counts"]) > 8 else "")
            print(f"  {side[:3]} onset {s['onset_ms_from_up']} toggle {t['start_cy']}->{t['end_cy']} t10 {t['t10_ms']} t90 {t['t90_ms']} fit {f(t['fit'])} width rest {w[0]} peak {w[1]}@{w[2]} low {w[3]}@{w[4]} sharp {t['sharp_ms_from_up']}")
            print(f"      counts {counts}")
            for name, b in sorted(s["badges"].items()):
                if name in ("unknown", "merged"):
                    continue
                fit = b.get("position_fixed_onset") or b.get("toward_collapsed")
                print(f"      {name:10s} first {b['first_ms']} cy {b['first']['cy']:.1f} r {b['first']['r']:.1f}; last {b['last_ms']} cy {b['last']['cy']:.1f} r {b['last']['r']:.1f}; extreme {b.get('extreme_cy')} max_r {b.get('max_r')} min_r {b.get('min_r')} fit {f(fit)} sharp {b['sharp_ms_from_up']}")
