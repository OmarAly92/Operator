import argparse
import json
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Compare analyze_morph.py summaries of native and Flutter material.morph takes, case by case and event by event: onsets, the toggle's motion and width, each badge's position and size, the topology transitions, and when each glass's content turns sharp (its glyph Laplacian first reaching half of its own rest value after the event onset, and staying there for two samples).")
ARGS.add_argument("--native", required=True)
ARGS.add_argument("--flutter", required=True)
ARGS.add_argument("--out", required=True)
OPTIONS = ARGS.parse_args()

SHARP_FRACTION = 0.5
SHARP_HOLD = 2
TOGGLE_MATCH = 6.0


def fit(entry):
    if not entry:
        return None
    return {"response": entry["response"], "damping": round(entry["damping"], 2), "start": round(entry["start"], 1), "rms": round(entry["rms"], 2)}


def sharp_ms(series, zero_ms):
    values = [(s["ms"], s["sharp"]) for s in series if s.get("sharp") is not None]
    if len(values) < SHARP_HOLD + 1:
        return None
    rest = float(np.median([v for _, v in values[-5:]]))
    level = SHARP_FRACTION * rest
    for n in range(len(values) - SHARP_HOLD + 1):
        if values[n][0] < zero_ms:
            continue
        if all(v >= level for _, v in values[n : n + SHARP_HOLD]):
            return values[n][0]
    return None


def toggle_sharp(event):
    frames = event["frames"]
    series = []
    for row in frames:
        cap = row["caps"]["bottom"]
        if not cap or not row["glass"]:
            continue
        lowest = max(row["glass"], key=lambda g: g["cy"])
        if abs(lowest["cy"] - cap["cy"]) <= TOGGLE_MATCH:
            series.append({"ms": row["ms"], "sharp": lowest.get("sharp")})
    blurred = [s for s in series if s["ms"] >= event["onset_ms_from_up"]] if event.get("onset_ms_from_up") is not None else series
    return sharp_ms(series, (event.get("onset_ms_from_up") or 0) + 30) if blurred else None


def summary(event):
    toggle = event["toggle"]
    found = {
        "onset_ms_from_up": event["onset_ms_from_up"],
        "toggle": {
            "start_cy": toggle["start_cy"],
            "end_cy": toggle["end_cy"],
            "t10_ms": toggle["t10_ms"],
            "t90_ms": toggle["t90_ms"],
            "fit": fit(toggle["position_fit"]),
            "overshoot_pct": round(toggle["position_features"]["overshoot_pct"], 2) if toggle.get("position_features") else None,
            "width": [toggle["width_rest"], toggle["width_peak"], toggle["width_peak_ms_from_onset"], toggle["width_low_after_peak"], toggle["width_low_ms_from_onset"]],
            "sharp_ms_from_up": toggle_sharp(event),
        },
        "counts": [(t["ms"], t["from"], t["to"]) for t in event["count_transitions"]],
        "badges": {},
    }
    onset = event["onset_ms_from_up"] or 0
    for name, badge in event["badges"].items():
        entry = {"first_ms": badge["first_ms"], "last_ms": badge["last_ms"], "first": badge["first"], "last": badge["last"]}
        for key in ("extreme_cy", "max_r", "min_r"):
            if key in badge:
                entry[key] = round(badge[key], 2)
        for key in ("position_fixed_onset", "position_free_onset", "radius_from_free_onset", "toward_collapsed"):
            if key in badge:
                entry[key] = fit(badge[key])
        series = [{"ms": s["ms"] + onset, "sharp": s.get("sharp")} for s in badge["series"]]
        entry["sharp_ms_from_up"] = sharp_ms(series, onset + 30)
        found["badges"][name] = entry
    return found


native = json.loads(Path(OPTIONS.native).read_text())
flutter = json.loads(Path(OPTIONS.flutter).read_text())
report = {}
for case in sorted(set(native) & set(flutter)):
    report[case] = {}
    for event in ("expand", "collapse"):
        report[case][event] = {"native": summary(native[case][event]), "flutter": summary(flutter[case][event])}
Path(OPTIONS.out).write_text(json.dumps(report, indent=1))
for case, events in report.items():
    for event, sides in events.items():
        print(f"== {case} {event}")
        for side in ("native", "flutter"):
            s = sides[side]
            t = s["toggle"]
            print(f"  {side:7s} onset {s['onset_ms_from_up']} toggle {t['start_cy']}->{t['end_cy']} t10 {t['t10_ms']} t90 {t['t90_ms']} fit {t['fit']} width {t['width']} sharp {t['sharp_ms_from_up']}")
            print(f"          counts {s['counts']}")
            for name, b in sorted(s["badges"].items()):
                extra = {k: b[k] for k in ("extreme_cy", "max_r", "min_r", "position_fixed_onset", "toward_collapsed") if k in b}
                print(f"          {name:10s} first {b['first_ms']} {b['first']} last {b['last_ms']} sharp {b['sharp_ms_from_up']} {extra}")
