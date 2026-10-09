import numpy as np

import align
import metrics
import springfit
import touch
import track

LEAD_SECONDS = 0.2
HOLD_SECONDS = 0.3
MAX_LAG_MS = 150
INNER_INSET = (16, 8)
EDGE_KEYS = ("xmin", "xmax", "ymin", "ymax")
MIN_TRAVEL = {"width": 4.0, "height": 4.0, "cx": 4.0, "cy": 4.0, "luma": 3.0, "progress": 0.2, **{key: 4.0 for key in EDGE_KEYS}}
MIN_EVENT_CHANGE = {"width": 4.0, "height": 4.0, "cx": 4.0, "cy": 4.0, "luma": 1.5, "progress": 0.1, **{key: 4.0 for key in EDGE_KEYS}}
SIGNIFICANT_KEYS = (*align.KEYS, "progress")
KEYS = (*SIGNIFICANT_KEYS, *EDGE_KEYS)
MOTION_MEASURES = (
    "delay_ms",
    "topology.count",
    "topology.join_ms",
    "topology.split_ms",
    "topology.neck_rms",
    "topology.gap_rms",
    *(f"{key}.{measure}" for key in (*align.KEYS, *EDGE_KEYS) for measure in ("peak_ms", "settle_ms", "overshoot_pct", "response_pct", "damping")),
    "progress.t10_90_ms",
    "progress.settle_ms",
    "progress.overshoot_pct",
    "progress.response_pct",
    "progress.damping",
    "progress.rms",
    "progress.sharpness",
)
LIMITS = {
    "delay_ms": "time_ms",
    "peak_ms": "time_ms",
    "settle_ms": "time_ms",
    "t10_90_ms": "time_ms",
    "overshoot_pct": "overshoot_pct",
    "response_pct": "response_pct",
    "damping": "damping",
    "rms": "progress_rms",
    "sharpness": "sharpness",
    "join_ms": "time_ms",
    "split_ms": "time_ms",
    "neck_rms": "neck_pt",
    "gap_rms": "gap_pt",
    "count": "count",
}
TRANSITION_SAMPLES = 2


def regions(scene):
    names = list(scene.track) + [name for name in scene.topology if name not in scene.track]
    return {name: tuple(scene.regions[name]) for name in names}


def inner_slices(rest_box, shape):
    height, width = shape[:2]
    if rest_box is None:
        return slice(0, height), slice(0, width)
    x, y, w, h = rest_box
    dx, dy = INNER_INSET
    top, bottom = int(round(y + dy)), int(round(y + h - dy))
    left, right = int(round(x + dx)), int(round(x + w - dx))
    if bottom - top < 3 or right - left < 3:
        return slice(0, height), slice(0, width)
    return slice(max(0, top), min(height, bottom)), slice(max(0, left), min(width, right))


def capture(scene, case_dir, found):
    if found is None:
        return {"events": [], "touches": [], "frames": 0}
    start, end = found
    shape_regions = regions(scene)
    union = metrics.union(list(shape_regions.values()))
    rect = track.pixel_rect(union)
    frames = track.extract(case_dir / "video.mp4", rect, case_dir / "shapes")
    frames = track.clip(frames, max(0.0, start - LEAD_SECONDS), end)
    frames = track.teardown_cut(frames, track.crop_px(metrics.load(case_dir / "settled.png"), rect))
    bare_full, ready_full = metrics.load(case_dir / "bare" / "ready.png"), metrics.load(case_dir / "ready.png")
    parts = {}
    for name, region in shape_regions.items():
        px = track.pixel_rect(region)
        local = (px[0] - rect[0], px[1] - rect[1], px[2], px[3])
        bare, full = track.crop_px(bare_full, px), track.crop_px(ready_full, px)
        edge_map = track.edges(bare)
        rest = track.box(full, bare, edge_map)
        bare_pt, full_pt = shrink(bare), shrink(full)
        parts[name] = {
            "local": local,
            "origin": (px[0] / metrics.SCALE, px[1] / metrics.SCALE),
            "bare": bare,
            "edges": edge_map,
            "bare_pt": bare_pt,
            "full_pt": full_pt,
            "inner": inner_slices(rest, bare_pt.shape),
            "rest": rest,
        }
    rows = {name: [] for name in parts}
    previous, diffs = None, []
    for frame in frames:
        point = shrink(frame)
        diffs.append(0.0 if previous is None else metrics.mad(point, previous))
        previous = point
        for name, part in parts.items():
            crop = track.crop_px(frame, part["local"])
            row = track.shape_row(crop, part["bare"], part["edges"], part["origin"])
            row.update(track.progress_row(shrink(crop), part["bare_pt"], part["full_pt"], part["inner"]))
            if name in scene.topology:
                row.update(track.topology_row(crop, part["bare"]))
            rows[name].append(row)
    windows = [w for w in touch.read(case_dir / "video.mp4", case_dir / "marker") if w[1] >= start - LEAD_SECONDS and w[0] <= end]
    events = []
    for first, last in align.events(diffs, frames.times):
        onset = frames.times[min(first + 1, last)]
        series = {name: event_series(frames.times, rows[name], first, last) for name in parts}
        if not any(significant(s) for s in series.values()):
            continue
        first_frame = {name: first_step(frames.times, rows[name], series[name], first, last) for name in parts}
        events.append({"onset": onset, "series": series, "step": touch.owner(onset, scene.steps, windows), "first_frame": first_frame})
    return {
        "events": events,
        "touches": windows,
        "stalls": align.stalls(diffs, frames.times),
        "frames": len(frames),
        "rest": {name: part["rest"] for name, part in parts.items()},
        "rows": {name: {"times": list(frames.times), "rows": rows[name]} for name in parts},
    }


def first_step(times, rows, series, first, last):
    after = min(first + 1, last)
    start, end = series["progress"][0], series["progress"][-1]
    travel = end - start
    value = rows[after]["progress"]
    return {
        "gap_ms": (times[after] - times[first]) * 1000,
        "progress": float((value - start) / travel) if np.isfinite(value) and abs(travel) >= MIN_TRAVEL["progress"] else None,
    }


def shrink(image):
    height, width = image.shape[0] // metrics.SCALE, image.shape[1] // metrics.SCALE
    trimmed = image[: height * metrics.SCALE, : width * metrics.SCALE]
    return trimmed.reshape(height, metrics.SCALE, width, metrics.SCALE, 3).mean(axis=(1, 3))


def event_series(times, rows, first, last):
    stop = times[last] + HOLD_SECONDS
    indices = [i for i in range(first, len(times)) if i <= last or times[i] <= stop]
    origin = max(times[first], times[first + 1] - 1.0 / align.GRID_HZ) if first + 1 < len(times) else times[first]
    stamps = [max(0.0, times[i] - origin) for i in indices] + [stop - origin]
    picked = [rows[i] for i in indices] + [rows[indices[-1]]]
    grid = np.arange(0.0, stamps[-1] + 1e-9, 1.0 / align.GRID_HZ)
    series = {}
    if "count" in picked[0]:
        counts = np.array([row["count"] for row in picked])
        series["count"] = counts[np.clip(np.searchsorted(stamps, grid, side="right") - 1, 0, len(counts) - 1)].tolist()
        necks = np.array([row["neck"] for row in picked], dtype=np.float64)
        series["neck"] = necks[np.clip(np.searchsorted(stamps, grid, side="right") - 1, 0, len(necks) - 1)].tolist()
        gaps = np.array([row["gap"] for row in picked], dtype=np.float64)
        series["gap"] = gaps[np.clip(np.searchsorted(stamps, grid, side="right") - 1, 0, len(gaps) - 1)].tolist()
    for key in (*KEYS, "sharpness", "residual"):
        values = np.array([row[key] for row in picked], dtype=np.float64)
        valid = np.isfinite(values)
        if valid.sum() < 2:
            series[key] = [float("nan")] * len(grid)
            continue
        series[key] = np.interp(grid, np.array(stamps)[valid], values[valid]).tolist()
    return series


def significant(series):
    if "count" in series and np.ptp(np.array(series["count"], dtype=np.float64)) >= 1:
        return True
    return any(np.isfinite(series[key]).all() and np.ptp(series[key]) >= MIN_EVENT_CHANGE[key] for key in SIGNIFICANT_KEYS)


def crossing(times, values, level):
    hits = np.nonzero(values >= level)[0]
    return float(times[hits[0]]) if len(hits) else None


def progress_features(series):
    values = np.array(series["progress"], dtype=np.float64)
    normalized = springfit.normalize(values)
    if normalized is None or abs(values[-1] - values[0]) < MIN_TRAVEL["progress"]:
        return None
    times = np.arange(len(values)) / align.GRID_HZ
    low, high = crossing(times, normalized, 0.1), crossing(times, normalized, 0.9)
    features = springfit.features(times, values)
    mid = int(np.argmin(np.abs(normalized - 0.5)))
    return {
        "t10_90_ms": (high - low) * 1000 if low is not None and high is not None else None,
        "settle_ms": features["settle_ms"],
        "overshoot_pct": features["overshoot_pct"],
        "sharpness_mid": float(series["sharpness"][mid]),
        "residual_peak": float(np.nanmax(series["residual"])),
        "normalized": normalized,
        "times": times,
        "spring": springfit.fit(times, values),
    }


def best_lag(a, b):
    limit = int(MAX_LAG_MS / 1000 * align.GRID_HZ)
    best, chosen = float("inf"), 0
    for lag in range(-limit, limit + 1):
        x, y = (a[lag:], b) if lag >= 0 else (a, b[-lag:])
        count = min(len(x), len(y))
        if count < 3:
            continue
        error = float(np.mean((x[:count] - y[:count]) ** 2))
        if error < best:
            best, chosen = error, lag
    return chosen


def compare_progress(a_series, b_series):
    a, b = progress_features(a_series), progress_features(b_series)
    if a is None or b is None:
        return None
    entry = {
        "native": {k: v for k, v in a.items() if k not in ("normalized", "times")},
        "flutter": {k: v for k, v in b.items() if k not in ("normalized", "times")},
        "curves": {"native": a["normalized"].tolist(), "flutter": b["normalized"].tolist()},
    }
    if a["t10_90_ms"] is not None and b["t10_90_ms"] is not None:
        entry["t10_90_ms"] = abs(a["t10_90_ms"] - b["t10_90_ms"])
    entry["settle_ms"] = abs(a["settle_ms"] - b["settle_ms"])
    entry["overshoot_pct"] = abs(a["overshoot_pct"] - b["overshoot_pct"])
    entry["sharpness"] = abs(a["sharpness_mid"] - b["sharpness_mid"])
    lag = best_lag(a["normalized"], b["normalized"])
    x, y = (a["normalized"][lag:], b["normalized"]) if lag >= 0 else (a["normalized"], b["normalized"][-lag:])
    count = min(len(x), len(y))
    entry["lag_ms"] = lag * 1000 / align.GRID_HZ
    entry["rms"] = float(np.sqrt(np.mean((x[:count] - y[:count]) ** 2)))
    apply_spring_fits(entry, a["spring"], b["spring"])
    return entry


def fit_problem(spring):
    if not spring:
        return "no travel"
    if spring["at_grid_edge"]:
        return "at the grid edge"
    if spring["rms"] >= 0.15:
        return f"rms {spring['rms']:.3f}"
    return None


def apply_spring_fits(entry, sa, sb):
    problems = {side: fit_problem(spring) for side, spring in (("native", sa), ("flutter", sb))}
    if any(problems.values()):
        entry["fit_invalid"] = {side: problem for side, problem in problems.items() if problem}
        entry["response_pct"] = float("inf")
        entry["damping"] = float("inf")
        return
    entry["response_pct"] = abs(sa["response"] - sb["response"]) / sa["response"] * 100
    entry["damping"] = abs(sa["damping"] - sb["damping"])


def compare_key(key, a_values, b_values):
    a, b = np.array(a_values, dtype=np.float64), np.array(b_values, dtype=np.float64)
    if not (np.isfinite(a).all() and np.isfinite(b).all()):
        return None
    if abs(a[-1] - a[0]) < MIN_TRAVEL[key] or abs(b[-1] - b[0]) < MIN_TRAVEL[key]:
        return None
    entry = {}
    ta, tb = np.arange(len(a)) / align.GRID_HZ, np.arange(len(b)) / align.GRID_HZ
    fa, fb = springfit.features(ta, a), springfit.features(tb, b)
    entry["peak_ms"] = abs(fa["peak_ms"] - fb["peak_ms"])
    entry["settle_ms"] = abs(fa["settle_ms"] - fb["settle_ms"])
    entry["overshoot_pct"] = abs(fa["overshoot_pct"] - fb["overshoot_pct"])
    sa, sb = springfit.fit(ta, a), springfit.fit(tb, b)
    entry["native_spring"], entry["flutter_spring"] = sa, sb
    apply_spring_fits(entry, sa, sb)
    return entry


def pairs(native, flutter):
    stepped = all(any(e["step"] is not None for e in side["events"]) for side in (native, flutter))
    if not stepped:
        return [(f"event{i}", a, b) for i, (a, b) in enumerate(zip(native["events"], flutter["events"]))]
    by_step = {}
    for side, found in (("native", native), ("flutter", flutter)):
        for event in found["events"]:
            if event["step"] is not None:
                by_step.setdefault(event["step"], {"native": [], "flutter": []})[side].append(event)
    return [
        (f"step{step}e{index}", a, b)
        for step, sides in sorted(by_step.items())
        for index, (a, b) in enumerate(zip(sides["native"], sides["flutter"]))
    ]


def unpaired(native, flutter):
    stepped = all(any(e["step"] is not None for e in side["events"]) for side in (native, flutter))
    if not stepped:
        count = min(len(native["events"]), len(flutter["events"]))
        return {"native": len(native["events"]) - count, "flutter": len(flutter["events"]) - count}
    found = {"native": 0, "flutter": 0}
    by_step = {}
    for side, capture in (("native", native), ("flutter", flutter)):
        for event in capture["events"]:
            if event["step"] is None:
                found[side] += 1
            else:
                by_step.setdefault(event["step"], {"native": 0, "flutter": 0})[side] += 1
    for sides in by_step.values():
        paired = min(sides.values())
        for side in found:
            found[side] += sides[side] - paired
    return found


def delay(event, steps, windows):
    times = touch.step_times(steps, windows)
    return None if event["step"] not in times else (event["onset"] - times[event["step"]]) * 1000


def transitions(counts):
    joins, splits = [], []
    for i in range(1, len(counts)):
        if counts[i - 1] >= 2 and counts[i] == 1:
            joins.append(i)
        if counts[i - 1] == 1 and counts[i] >= 2:
            splits.append(i)
    return joins, splits


def finite_difference(a, b):
    if np.isfinite(a) and np.isfinite(b):
        return float(abs(a - b))
    if not np.isfinite(a) and not np.isfinite(b):
        return 0.0
    return float("inf")


def neck_difference(a, b):
    return finite_difference(a["neck"], b["neck"])


def gap_difference(a, b):
    return finite_difference(a["gap"], b["gap"])


def transition_gap(a, b):
    if a and b:
        return abs(a[0] - b[0]) * 1000 / align.GRID_HZ
    return 0.0 if not a and not b else float("inf")


def series_rms(a_count, b_count, a_values, b_values):
    squares = []
    for ca, cb, va, vb in zip(a_count, b_count, a_values, b_values):
        difference = finite_difference(va, vb)
        if np.isinf(difference) and ca != cb:
            continue
        if np.isfinite(va) or np.isfinite(vb):
            squares.append(difference ** 2)
    return float(np.sqrt(np.mean(squares))) if squares else 0.0


def neck_rms(a_count, b_count, a_neck, b_neck):
    return series_rms(a_count, b_count, a_neck, b_neck)


def compare_topology(a_series, b_series):
    a_count, b_count = np.array(a_series["count"]), np.array(b_series["count"])
    entry = {}
    a_joins, a_splits = transitions(a_count)
    b_joins, b_splits = transitions(b_count)
    entry["join_ms"] = transition_gap(a_joins, b_joins)
    entry["split_ms"] = transition_gap(a_splits, b_splits)
    count = min(len(a_count), len(b_count))
    excluded = np.zeros(count, dtype=bool)
    for index in a_joins + a_splits + b_joins + b_splits:
        excluded[max(0, index - TRANSITION_SAMPLES) : index + TRANSITION_SAMPLES + 1] = True
    entry["count"] = float(((a_count[:count] != b_count[:count]) & ~excluded).sum())
    entry["neck_rms"] = neck_rms(a_count[:count], b_count[:count], a_series["neck"][:count], b_series["neck"][:count])
    if "gap" in a_series and "gap" in b_series:
        entry["gap_rms"] = series_rms(a_count[:count], b_count[:count], a_series["gap"][:count], b_series["gap"][:count])
    entry["native"] = {"joins_ms": [i * 1000 / align.GRID_HZ for i in a_joins], "splits_ms": [i * 1000 / align.GRID_HZ for i in a_splits]}
    entry["flutter"] = {"joins_ms": [i * 1000 / align.GRID_HZ for i in b_joins], "splits_ms": [i * 1000 / align.GRID_HZ for i in b_splits]}
    return entry


def compare(scene, native, flutter):
    result = {
        "event_count": [len(native["events"]), len(flutter["events"])],
        "unpaired": unpaired(native, flutter),
        "touches": [len(native["touches"]), len(flutter["touches"])],
        "expected_touches": touch.expected_touches(scene.steps),
        "stalls": {"native": native.get("stalls", []), "flutter": flutter.get("stalls", [])},
        "steps": [sorted({e["step"] for e in native["events"] if e["step"] is not None}), sorted({e["step"] for e in flutter["events"] if e["step"] is not None})],
        "pairs": {},
    }
    for label, a, b in pairs(native, flutter):
        pair = {"shapes": {}}
        da, db = delay(a, scene.steps, native["touches"]), delay(b, scene.steps, flutter["touches"])
        if da is not None and db is not None:
            pair["delay"] = {"native": da, "flutter": db}
            pair["delay_ms"] = abs(da - db)
        for name in regions(scene):
            sa, sb = a["series"][name], b["series"][name]
            shape = {}
            if name in scene.topology:
                shape["topology"] = compare_topology(sa, sb)
            for key in (*align.KEYS, *scene.edges.get(name, ())):
                entry = compare_key(key, sa[key], sb[key])
                if entry:
                    shape[key] = entry
            progress = compare_progress(sa, sb)
            if progress:
                shape["progress"] = progress
            shape["first_frame"] = {"native": a.get("first_frame", {}).get(name), "flutter": b.get("first_frame", {}).get(name)}
            pair["shapes"][name] = shape
        result["pairs"][label] = pair
    return result


def measures(result):
    found = {}
    for label, pair in result["pairs"].items():
        if "delay_ms" in pair:
            found[f"{label}.delay_ms"] = pair["delay_ms"]
        for name, shape in pair["shapes"].items():
            for key, entry in shape.items():
                for measure, value in entry.items():
                    if measure in LIMITS and isinstance(value, (int, float)):
                        found[f"{name}.{label}.{key}.{measure}"] = float(value)
    return found


def expected(result, scene):
    labels = list(result["pairs"])
    if scene.touches:
        labels += [label for label in (f"step{index}e0" for index in touch.touch_steps(scene.steps)) if label not in labels]
    names = []
    for label in labels:
        for measure in scene.motion:
            if measure == "delay_ms":
                names.append(f"{label}.delay_ms")
                continue
            if measure.startswith("topology."):
                owners = scene.topology
            elif measure.split(".")[0] in EDGE_KEYS:
                owners = [name for name, keys in scene.edges.items() if measure.split(".")[0] in keys]
            else:
                owners = scene.track
            names += [f"{name}.{label}.{measure}" for name in owners]
    return names


def limits(result, scene, noise=None, factor=1.5):
    noise = noise or {}
    native, flutter = result["event_count"]
    found = {"events.native_motion": (native, 1, "min")}
    steps_native, steps_flutter = result["steps"]
    if steps_native and steps_flutter:
        found["events.steps"] = (len(set(steps_native) ^ set(steps_flutter)), 0, "max")
    found["events.unpaired"] = (sum(result.get("unpaired", {}).values()), 0, "max")
    if scene.touches:
        for side, count in zip(("native", "flutter"), result["touches"]):
            found[f"touches.{side}"] = (abs(count - result.get("expected_touches", 0)), 0, "max")
    present = measures(result)
    for name in expected(result, scene):
        value = present.get(name, float("inf"))
        threshold = metrics.THRESHOLDS[LIMITS[name.split(".")[-1]]]
        found[name] = (value, max(threshold, factor * noise.get(name, 0.0)), "max")
    return found


def summary(capture):
    found = {"touches": [[round(a, 3), round(b, 3)] for a, b in capture.get("touches", [])], "frames": capture.get("frames", 0), "shapes": {}}
    for name, rows in capture.get("rows", {}).items():
        times, values = rows["times"], rows["rows"]
        first_touch = capture["touches"][0][0] if capture.get("touches") else None
        rest = max([i for i, t in enumerate(times) if first_touch is None or t < first_touch] or [0])
        widths = [row["width"] for row in values]
        heights = [row["height"] for row in values]
        widest = int(np.argmax(widths))
        found["shapes"][name] = {
            "rest": {key: round(values[rest][key], 2) for key in ("width", "height", "cx", "cy", "luma")},
            "max": {"width": round(max(widths), 2), "height": round(max(heights), 2)},
            "edge_in_band": {"rest": bool(values[rest].get("band")), "max": bool(values[widest].get("band"))},
            "min_visible": {"width": round(min([w for w in widths if w > 0] or [0]), 2), "height": round(min([h for h in heights if h > 0] or [0]), 2)},
        }
    found["events"] = []
    for event in capture.get("events", []):
        entry = {"onset": round(event["onset"], 3), "step": event["step"], "shapes": {}}
        for name, series in event["series"].items():
            features = progress_features(series)
            entry["shapes"][name] = None if features is None else {
                key: (round(value, 3) if isinstance(value, float) else value)
                for key, value in features.items()
                if key not in ("normalized", "times")
            }
        found["events"].append(entry)
    return found


def static_topology(scene, native_dir, flutter_dir):
    found = {}
    for name in scene.topology:
        px = track.pixel_rect(scene.regions[name])
        rows = {}
        for app, folder in (("native", native_dir), ("flutter", flutter_dir)):
            bare = track.crop_px(metrics.load(folder / "bare" / "ready.png"), px)
            mask = track.still_mask(track.crop_px(metrics.load(folder / "ready.png"), px), bare)
            rows[app] = dict(track.topology(mask), gap=track.gap(mask))
        found[name] = {
            "native": rows["native"],
            "flutter": rows["flutter"],
            "count": abs(rows["native"]["count"] - rows["flutter"]["count"]),
            "neck_pt": neck_difference(rows["native"], rows["flutter"]),
            "gap_pt": gap_difference(rows["native"], rows["flutter"]),
        }
    return found
