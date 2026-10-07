import argparse
import json
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Per-frame merge and split curves of both apps on the harness's 120 Hz event grid (every second sample): left circle outer edge, harness left cx, pair component count and neck, from series_dump.py output.")
ARGS.add_argument("--out", required=True)
ARGS.add_argument("series", nargs="+")
OPTIONS = ARGS.parse_args()
lines = []
for source in OPTIONS.series:
    data = json.loads(Path(source).read_text())
    for case, entry in data.items():
        for index, name in ((0, "merge"), (1, "split")):
            lines.append(f"== {case} {name}: ms from each app's event onset | native: left outer edge, left box cx, count, neck | flutter: same")
            sides = {app: entry["events"][app][index]["series"] for app in ("native", "flutter")}
            length = min(len(sides[a]["left"]["cx"]) for a in sides)
            for i in range(0, min(length, 72), 2):
                cells = []
                for app in ("native", "flutter"):
                    s = sides[app]
                    outer = s["left"]["cx"][i] - s["left"]["width"][i] / 2
                    neck = s["pair"]["neck"][i]
                    cells.append(f"{outer:7.2f} {s['left']['cx'][i]:7.2f} {int(s['pair']['count'][i])} {'' if neck is None else f'{neck:5.1f}':>5s}")
                lines.append(f"{i * 1000 / 120:6.1f} | " + " | ".join(cells))
Path(OPTIONS.out).write_text("\n".join(lines) + "\n")
print(len(lines), "lines")
