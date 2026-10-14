import math

import numpy as np

import takecheck
import touch

PEAK_SHARE = 0.9
SETTLE_SHARE = 0.1
MIN_GLOW = 3.0
MIN_GROWTH = 1.0
SIZE_BAND = 2.0 / 3.0
MEASURES = (
    "glow_peak",
    "glow_rise_ms",
    "glow_fade_ms",
    "glow_drop",
    "glow_drop_ms",
    "glow_level",
    "glow_half_ms",
    "grow_w",
    "grow_h",
    "grow_ms",
    "shrink_ms",
    "stretch",
    "centre",
)
TIMES = ("glow_rise_ms", "glow_fade_ms", "glow_drop_ms", "glow_half_ms", "grow_ms", "shrink_ms")
LIMITS = {
    "glow_peak": "luminance",
    "glow_rise_ms": "time_ms",
    "glow_fade_ms": "time_ms",
    "glow_drop": "luminance",
    "glow_drop_ms": "time_ms",
    "glow_level": "luminance",
    "glow_half_ms": "time_ms",
    "grow_w": "bbox_pt",
    "grow_h": "bbox_pt",
    "grow_ms": "time_ms",
    "shrink_ms": "time_ms",
    "stretch": "ratio",
    "centre": "centre_pt",
}


def rest_index(times, down):
    before = [i for i, t in enumerate(times) if t < down]
    return before[-1] if before else 0


def rise(times, values, indices, peak, down):
    if peak is None or not indices:
        return None
    for i in indices:
        if values[i] >= PEAK_SHARE * peak:
            return (times[i] - down) * 1000
    return None


def settle(times, values, indices, band, up):
    if not indices:
        return None
    outside = [i for i in indices if abs(values[i]) > band]
    if not outside:
        return (times[indices[0]] - up) * 1000
    last = outside[-1]
    later = [i for i in indices if i > last]
    return (times[later[0]] - up) * 1000 if later else None


def drop(times, values, during, after, up):
    if not after:
        return None, None, None
    chain = ([during[-1]] if during else []) + after
    best, when, level = 0.0, None, None
    for previous, current in zip(chain, chain[1:]):
        fall = values[previous] - values[current]
        if fall > best:
            best, when, level = fall, (times[current] - up) * 1000, values[previous]
    return best, when, level


def half(times, values, after, peak, floor, up):
    target = (peak + floor) / 2
    for i in after:
        if values[i] <= target:
            return (times[i] - up) * 1000
    return None


def features(times, rows, window, end=math.inf):
    down, up = window
    times = list(times)
    first = rest_index(times, down)
    rest = rows[first]
    during = [i for i, t in enumerate(times) if down <= t <= up]
    after = [i for i, t in enumerate(times) if up < t < end]
    glow = np.array([row["glow"] - rest["glow"] for row in rows], dtype=np.float64)
    dw = np.array([row["width"] - rest["width"] for row in rows], dtype=np.float64)
    dh = np.array([row["height"] - rest["height"] for row in rows], dtype=np.float64)
    peak = float(glow[during].max()) if during else 0.0
    lit = peak >= MIN_GLOW
    grow_w = float(dw[during].max()) if during else 0.0
    grow_h = float(dh[during].max()) if during else 0.0
    grown = grow_w >= MIN_GROWTH
    fall, fall_ms, level = drop(times, glow, during, after, up)
    cut = lit and fall is not None and fall >= MIN_GLOW
    ratio0 = rest["width"] / rest["height"] if rest["height"] > 0 else float("nan")
    moving = during + after
    stretch = [row["width"] / row["height"] / ratio0 - 1 for row in (rows[i] for i in moving) if row["height"] > 0 and row["width"] > 0]
    offsets = [math.hypot(rows[i]["cx"] - rest["cx"], rows[i]["cy"] - rest["cy"]) for i in moving if np.isfinite(rows[i]["cx"]) and np.isfinite(rows[i]["cy"])]
    return {
        "hole": bool(takecheck.span_holes(times, row_changes(rows), [(down, up)], tail=min(takecheck.TAIL, end - up))),
        "rest": {key: rest[key] for key in ("glow", "width", "height", "cx", "cy")},
        "glow_peak": peak,
        "glow_rise_ms": rise(times, glow, during, peak, down) if lit else None,
        "glow_fade_ms": settle(times, glow, after, SETTLE_SHARE * peak, up) if lit else None,
        "glow_drop": fall if lit else 0.0,
        "glow_drop_ms": fall_ms if cut else None,
        "glow_level": float(level) if cut else None,
        "glow_half_ms": half(times, glow, after, peak, level if cut else 0.0, up) if lit else None,
        "grow_w": grow_w,
        "grow_h": grow_h,
        "grow_ms": rise(times, dw, during, grow_w, down) if grown else None,
        "shrink_ms": settle(times, dw, after, max(SETTLE_SHARE * grow_w, SIZE_BAND), up) if grown else None,
        "stretch": max(stretch, key=abs) if stretch else 0.0,
        "centre": max(offsets) if offsets else 0.0,
    }


GLOW_CHANGE = 0.5
SIZE_CHANGE = 0.5


def row_changes(rows):
    found = [False]
    for previous, current in zip(rows, rows[1:]):
        moved = abs(current["glow"] - previous["glow"]) > GLOW_CHANGE
        for key in ("width", "height", "cx", "cy"):
            a, b = previous[key], current[key]
            if np.isfinite(a) and np.isfinite(b) and abs(b - a) > SIZE_CHANGE:
                moved = True
        found.append(moved)
    return found


def difference(a, b):
    if a is None and b is None:
        return 0.0
    if a is None or b is None:
        return float("inf")
    return float(abs(a - b))


def compare(a, b):
    holed = a.get("hole") or b.get("hole")
    entry = {measure: float("nan") if holed and measure in TIMES else difference(a[measure], b[measure]) for measure in MEASURES}
    entry["native"] = a
    entry["flutter"] = b
    return entry


def step_features(scene, capture):
    windows = touch.step_windows(scene.steps, capture.get("touches", []))
    found = {}
    ordered = sorted(windows.items())
    for position, (index, group) in enumerate(ordered):
        window = (group[0][0], group[-1][1])
        end = ordered[position + 1][1][0][0] if position + 1 < len(ordered) else math.inf
        found[f"step{index}"] = {
            name: features(rows["times"], rows["rows"], window, end)
            for name, rows in capture.get("rows", {}).items()
            if rows["rows"] and "glow" in rows["rows"][0]
        }
    return found


def compare_steps(scene, native, flutter):
    a, b = step_features(scene, native), step_features(scene, flutter)
    found = {}
    for label in sorted(set(a) & set(b)):
        found[label] = {name: compare(a[label][name], b[label][name]) for name in sorted(set(a[label]) & set(b[label]))}
    return found
