import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Summarize morph_track.py outputs: event onsets (the toggle's bottom-cap centre moving by more than 0.5 pt), the toggle's motion and size, per-badge series named by position windows and order in the stack (rules in expand_names and collapse_names, checked against crops), with spring fits from the event onset or a fitted later onset, topology transitions, and the necks against the angle blend at k = spacing.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--out", required=True)
ARGS.add_argument("--spacing", type=float, default=20.0)
ARGS.add_argument("--unreliable", default="", help="comma-separated labels whose silhouettes break (recorded in the output, not excluded)")
ARGS.add_argument("cases", nargs="+", help="label=morph_track.py json")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import measure
import springfit
import tracking

REST = {"star": 343.0, "heart": 415.0, "bolt": 487.0}
COLLAPSED = 451.0
EXPANDED_TOGGLE = 559.0
REST_RADIUS = 28.4
ONSET_PT = 0.5
TOGGLE_MATCH = 3.0
NAME_REACH = 6.0
LINK_GATE = 14.0
LINK_GAP = 0.3
ONSET_SEARCH = np.arange(0.0, 0.45, 1 / 120)
STAR_ABOVE = 20.0
BOLT_FROM = 460.0
BRIDGE_FROM = 440.0
MIN_ROWS = 10.0
FRAGMENT_ABOVE = 400.0
MERGED_FROM = 440.0
MERGED_TO = 462.0
STAR_STAYS = 8.0
MIN_BADGE_RADIUS = 8.0


def onset(rows):
    first = rows[0]["caps"]["bottom"]
    for row in rows[1:]:
        cap = row["caps"]["bottom"]
        if first and cap and abs(cap["cy"] - first["cy"]) > ONSET_PT:
            return row
    return None


def crossing_ms(times, values, fraction):
    start, end = values[0], values[-1]
    level = start + fraction * (end - start)
    for (t0, v0), (t1, v1) in zip(zip(times, values), zip(times[1:], values[1:])):
        if (v0 - level) * (v1 - level) <= 0 and v1 != v0:
            return (t0 + (level - v0) / (v1 - v0) * (t1 - t0)) * 1000
    return None


def max_width(row):
    return max([l["width"] for l in row["lobes"]] or [0.0])


def toggle_rows(rows):
    found = []
    for row in rows:
        cap = row["caps"]["bottom"]
        if cap:
            found.append((row["t"], cap["cy"], cap["r"]))
    return found


def badge_frames(rows):
    frames = []
    for row in rows:
        cap = row["caps"]["bottom"]
        lowest = max(row["glass"], key=lambda g: g["cy"]) if row["glass"] else None
        values = [g for g in row["glass"] if g is not lowest and not (cap and abs(g["cy"] - cap["cy"]) < TOGGLE_MATCH)]
        frames.append((row["t"], values))
    return frames


def angle_blend_neck(c1, r1, c2, r2, k):
    top = min(c1 - r1, c2 - r2) - 4
    bottom = max(c1 + r1, c2 + r2) + 4
    width = 2 * max(r1, r2) + 8
    s = measure.SCALE
    ys = (np.arange(int((bottom - top) * s)) + 0.5) / s + top
    xs = (np.arange(int(width * s)) + 0.5) / s - width / 2
    x, y = np.meshgrid(xs, ys)
    d1, d2 = np.hypot(x, y - c1), np.hypot(x, y - c2)
    a, b = d1 - r1, d2 - r2
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    dot = (x * x + (y - c1) * (y - c2)) / np.maximum(d1 * d2, 1e-9)
    field = np.minimum(a, b) - h * h * k / 4 * (1 - dot) / 2
    found = measure.stack_topology(field < 0)
    if found["count"] != 1:
        return {"count": found["count"], "neck": None}
    necks = found["necks"]
    return {"count": 1, "neck": round(min(n["width"] for n in necks), 2) if necks else None}


def neck_rows(rows, k):
    out = []
    for row in rows:
        fits = sorted(row["glass"], key=lambda g: g["cy"])
        for a, b in zip(fits, fits[1:]):
            gap = b["cy"] - a["cy"] - a["r"] - b["r"]
            between = [n for n in row["necks"] if a["cy"] < n["y"] < b["cy"]]
            joined = any(e[0] < a["cy"] and e[1] > b["cy"] for e in row["extent"])
            model = angle_blend_neck(a["cy"], a["r"], b["cy"], b["r"], k)
            out.append({"t": row["t"], "ms": row["ms"], "pair": [a["cy"], b["cy"]], "radii": [a["r"], b["r"]], "gap": round(gap, 2), "native_joined": joined, "native_neck": between[0]["width"] if between else None, "model_joined": model["count"] == 1, "model_neck": model["neck"]})
    return out


def transitions(rows):
    found = []
    for a, b in zip(rows, rows[1:]):
        if a["count"] != b["count"]:
            found.append({"ms": b["ms"], "from": a["count"], "to": b["count"]})
    return found


def toggle_summary(rows, zero_row):
    series = toggle_rows(rows)
    t0 = zero_row["t"] if zero_row else series[0][0]
    after = [(t, y, r) for t, y, r in series if t >= t0]
    previous = [s for s in series if s[0] < t0]
    start = previous[-1] if previous else series[0]
    times = [start[0] - t0 + 0.0] + [t - t0 for t, _, _ in after]
    times[0] = 0.0
    ys = [start[1]] + [y for _, y, _ in after]
    widths = [(row["t"], max_width(row)) for row in rows]
    rest_width = widths[0][1]
    peak = max(widths, key=lambda w: w[1])
    after_peak = [w for w in widths if w[0] > peak[0]]
    low = min(after_peak, key=lambda w: w[1]) if after_peak else None
    fit = springfit.fit(times, ys)
    features = springfit.features(times, ys)
    t10, t90 = crossing_ms(times, ys, 0.1), crossing_ms(times, ys, 0.9)
    return {
        "t10_ms": round(t10, 1) if t10 is not None else None,
        "t90_ms": round(t90, 1) if t90 is not None else None,
        "start_cy": round(ys[0], 2),
        "end_cy": round(ys[-1], 2),
        "position_fit": fit,
        "position_features": features,
        "width_rest": rest_width,
        "width_peak": peak[1],
        "width_peak_ms_from_onset": round((peak[0] - t0) * 1000, 1),
        "width_low_after_peak": low[1] if low else None,
        "width_low_ms_from_onset": round((low[0] - t0) * 1000, 1) if low else None,
        "width_end": widths[-1][1],
    }


def expand_names(lobes, state, reduce_motion):
    n = len(lobes)
    if reduce_motion:
        return ["star", "heart", "bolt"] if n == 3 else ["merged"] * n
    names = [None] * n
    lower = [i for i, g in enumerate(lobes) if g["cy"] >= BOLT_FROM]
    upper = [i for i, g in enumerate(lobes) if g["cy"] < BOLT_FROM]
    if lower:
        names[lower[-1]] = "bolt"
        for i in lower[:-1]:
            names[i] = "unknown"
    if len(upper) == 1:
        names[upper[0]] = "heart"
    elif len(upper) == 2:
        top, bottom = upper
        if lobes[bottom]["cy"] >= BRIDGE_FROM:
            names[top], names[bottom] = "heart", "star"
        else:
            names[top], names[bottom] = "star", "heart"
    else:
        for i in upper:
            names[i] = "unknown"
    return names


def collapse_names(lobes):
    names = []
    rest = []
    for g in lobes:
        if abs(g["cy"] - REST["star"]) <= STAR_STAYS:
            names.append("star")
        elif g["cy"] < FRAGMENT_ABOVE:
            names.append("unknown")
        else:
            names.append(None)
            rest.append(len(names) - 1)
    if len(rest) == 2:
        names[rest[0]], names[rest[1]] = "heart", "bolt"
    elif len(rest) == 1:
        y = lobes[rest[0]]["cy"]
        names[rest[0]] = "heart" if y < MERGED_FROM else ("bolt" if y > MERGED_TO else "heart+bolt")
    else:
        for i in rest:
            names[i] = "unknown"
    return names


def badge_summary(rows, zero_row, expand, reduce_motion):
    t0 = zero_row["t"] if zero_row else rows[0]["t"]
    state, named = {}, {}
    for t, values in badge_frames(rows):
        lobes = sorted([g for g in values if g["r"] >= MIN_BADGE_RADIUS and g["rows_pt"] >= MIN_ROWS], key=lambda g: g["cy"])
        names = expand_names(lobes, state, reduce_motion) if expand else collapse_names(lobes)
        for name, g in zip(names, lobes):
            named.setdefault(name, []).append({"t": t, "ms": round((t - t0) * 1000, 1), "cy": g["cy"], "r": g["r"], "luma": g.get("luma"), "sharp": g.get("sharp"), "rms": g["rms"], "lobes": len(lobes)})
            state[name] = g["cy"]
    out = {}
    for name, series in named.items():
        times = [s["t"] for s in series]
        cys = [s["cy"] for s in series]
        rs = [s["r"] for s in series]
        entry = {"first_ms": series[0]["ms"], "last_ms": series[-1]["ms"], "first": {"cy": cys[0], "r": rs[0]}, "last": {"cy": cys[-1], "r": rs[-1]}, "series": series}
        if expand and name in REST:
            entry["extreme_cy"] = min(cys) if REST[name] < COLLAPSED else max(cys)
            entry["max_r"] = max(rs)
            entry["position_fixed_onset"] = tracking.spring_from(times, cys, REST[name], t0)
            free = tracking.spring_from(times, cys, REST[name], t0 + ONSET_SEARCH)
            free["onset_ms_from_event"] = round((free["onset"] - t0) * 1000, 1)
            entry["position_free_onset"] = free
            entry["radius_from_free_onset"] = tracking.spring_from(times, rs, REST_RADIUS, free["onset"])
        if not expand and name in ("heart", "bolt", "heart+bolt"):
            entry["toward_collapsed"] = tracking.spring_from(times, cys, COLLAPSED, t0)
            entry["min_r"] = min(rs)
        out[name] = entry
    return out


report = {}
for spec in OPTIONS.cases:
    label, path = spec.split("=", 1)
    data = json.loads(Path(path).read_text())
    report[label] = {"source": data["folder"], "touches": data["touches"], "silhouette_unreliable": label in OPTIONS.unreliable.split(",")}
    for k, event in enumerate(("expand", "collapse")):
        rows = data[event]["rows"]
        down, up = data["touches"][k]
        zero = onset(rows)
        summary = {
            "hold_ms": round((up - down) * 1000, 1),
            "onset_ms_from_up": round((zero["t"] - up) * 1000, 1) if zero else None,
            "onset_ms_from_down": round((zero["t"] - down) * 1000, 1) if zero else None,
            "toggle": toggle_summary(rows, zero),
            "badges": badge_summary(rows, zero, event == "expand", label.endswith("-rm")),
            "count_transitions": transitions(rows),
            "necks": neck_rows(rows, OPTIONS.spacing),
        }
        summary["frames"] = rows
        report[label][event] = summary
        t = summary["toggle"]
        print(label, event, "onset", summary["onset_ms_from_up"], "toggle", t["start_cy"], "->", t["end_cy"], t["position_fit"], "width", t["width_rest"], t["width_peak"], t["width_peak_ms_from_onset"], t["width_low_after_peak"], flush=True)
        for name, b in summary["badges"].items():
            print("   ", name, b["first_ms"], b["first"], b["last_ms"], b["last"], b.get("position_fixed_onset") or b.get("toward_collapsed"), flush=True)
            if "position_free_onset" in b:
                print("      free", b["position_free_onset"], "radius", b["radius_from_free_onset"], "extreme", b["extreme_cy"], "max_r", b["max_r"], flush=True)
        print("    counts", summary["count_transitions"], flush=True)
Path(OPTIONS.out).write_text(json.dumps(report, separators=(",", ":")))
