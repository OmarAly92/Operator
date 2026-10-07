import json
import re
import subprocess
from pathlib import Path

import numpy as np

import align
import metrics
import shapes
import springfit
import touch
import track

OVERVIEW_FPS = 20
MATCH_MARGIN = 6.0
TILE = 24
SKIP_TOP_TILES = 3
LEAD_SECONDS = 0.2
MAX_LAG_MS = 150
MIN_TRAVEL = {"width": 4.0, "height": 4.0, "cx": 4.0, "cy": 4.0, "luma": 3.0}
PTS = re.compile(r"pts_time:([0-9.]+)")


def _crop_filter(region, downscale):
    x, y, w, h = (int(round(v * metrics.SCALE)) for v in region)
    size = f",scale={max(1, w // metrics.SCALE)}:{max(1, h // metrics.SCALE)}" if downscale else ""
    return f"crop={w}:{h}:{x}:{y}{size}"


def _clean(dest):
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    for old in dest.glob("*.png"):
        old.unlink()
    return dest


def overview(video, dest):
    dest = _clean(dest)
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-i", str(video), "-vf", f"fps={OVERVIEW_FPS},{_crop_filter((0, 0, *metrics.SCREEN), True)}", str(dest / "%06d.png")],
        check=True,
    )
    paths = sorted(dest.glob("*.png"))
    return align.Frames(paths, [i / OVERVIEW_FPS for i in range(len(paths))])


def frames(video, start, end, region, dest):
    dest = _clean(dest)
    process = subprocess.run(
        [
            "ffmpeg", "-loglevel", "info", "-y", "-copyts",
            "-ss", f"{start:.3f}", "-to", f"{end:.3f}", "-i", str(video),
            "-fps_mode", "passthrough",
            "-vf", f"{_crop_filter(region, True)},showinfo",
            str(dest / "%06d.png"),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    times = [float(t) for t in PTS.findall(process.stderr)]
    paths = sorted(dest.glob("*.png"))
    count = min(len(paths), len(times))
    return align.Frames(paths[:count], times[:count])


def shrink(image):
    height, width = image.shape[0] // metrics.SCALE, image.shape[1] // metrics.SCALE
    trimmed = image[: height * metrics.SCALE, : width * metrics.SCALE]
    return trimmed.reshape(height, metrics.SCALE, width, metrics.SCALE, 3).mean(axis=(1, 3))


def tile_difference(a, b):
    difference = np.abs(a - b).mean(axis=2)
    height, width = difference.shape[0] // TILE * TILE, difference.shape[1] // TILE * TILE
    tiles = difference[:height, :width].reshape(height // TILE, TILE, width // TILE, TILE).mean(axis=(1, 3))
    return float(tiles[SKIP_TOP_TILES:].max())


def window(case_dir):
    view = overview(case_dir / "video.mp4", case_dir / "overview")
    ready = shrink(metrics.load(case_dir / "ready.png"))
    settled = shrink(metrics.load(case_dir / "settled.png"))
    to_ready = [tile_difference(frame, ready) for frame in view]
    to_settled = [tile_difference(frame, settled) for frame in view]
    if not to_ready:
        return None
    ready_limit = min(to_ready) + MATCH_MARGIN
    settled_limit = min(to_settled) + MATCH_MARGIN
    first = next((i for i, d in enumerate(to_ready) if d <= ready_limit), 0)
    leave = next((i for i in range(first, len(to_ready)) if to_ready[i] > ready_limit), None)
    last = max((i for i, d in enumerate(to_settled) if d <= settled_limit), default=len(view) - 1)
    if leave is None or last <= leave:
        return None
    start = max(0, leave - 4)
    chosen = align.Frames(view.paths[start : last + 1], view.times[start : last + 1])
    return start / OVERVIEW_FPS, (last + 1) / OVERVIEW_FPS, chosen


def region_for(scene, case_dir):
    if scene.track:
        return metrics.union([tuple(scene.regions[name]) for name in scene.track])
    bare = metrics.load(case_dir / "bare" / "ready.png")
    boxes = metrics.glass_boxes(metrics.load(case_dir / "ready.png"), bare)
    boxes += metrics.glass_boxes(metrics.load(case_dir / "settled.png"), bare)
    if not scene.rest and (case_dir / "video.mp4").exists():
        found = window(case_dir)
        if found:
            boxes += align.extent(found[2], ignore=(touch.MARKER,))
    boxes = [box for box in touch.without_marker(boxes) if box[1] + box[3] > align.SKIP_TOP_POINTS]
    return metrics.union(boxes, pad=12) or (0, 0, *metrics.SCREEN)


def elements_for(scene):
    return {name: tuple(rect) for name, rect in scene.regions.items() if name not in scene.track}


def motion(case_dir, region):
    found = window(case_dir)
    if found is None:
        return {"events": [], "stalls": []}
    start, end, _ = found
    crops = frames(case_dir / "video.mp4", max(0.0, start - LEAD_SECONDS), end, region, case_dir / "frames")
    settled_path = case_dir / "settled.png"
    if settled_path.exists():
        crops = track.teardown_cut(crops, shrink(metrics.crop(metrics.load(settled_path), region)))
    if len(crops) < 2:
        return {"events": [], "stalls": []}
    bare_path = case_dir / "bare" / "ready.png"
    bare = shrink(metrics.crop(metrics.load(bare_path), region)) if bare_path.exists() else crops[0]
    diffs = align.differences(crops)
    found_events = []
    for first, last in align.events(diffs, crops.times):
        series = align.event_series(crops, first, last, bare)
        if align.significant(series):
            found_events.append({"start": crops.times[first], "series": series})
    return {"events": found_events, "stalls": align.stalls(diffs, crops.times), "first_time": crops.times[0]}


def shape_capture(scene, case_dir, cache=None):
    key = (scene.id, str(Path(case_dir).resolve()))
    if cache is not None and key in cache:
        return cache[key]
    found = window(case_dir)
    captured = shapes.capture(scene, case_dir, found[:2] if found else None)
    if cache is not None:
        cache[key] = captured
    return captured


def cached_motion(case_dir, region, cache=None):
    key = ("motion", str(Path(case_dir).resolve()), tuple(region))
    if cache is not None and key in cache:
        return cache[key]
    found = motion(case_dir, region)
    if cache is not None:
        cache[key] = found
    return found


def compare_series(key, a, b, a_full, b_full):
    entry = {"rms": float(np.sqrt(np.mean((a - b) ** 2))), "native": a.tolist(), "flutter": b.tolist()}
    if abs(a_full[-1] - a_full[0]) < MIN_TRAVEL[key] or abs(b_full[-1] - b_full[0]) < MIN_TRAVEL[key]:
        return entry
    a_times = np.arange(len(a_full)) / align.GRID_HZ
    b_times = np.arange(len(b_full)) / align.GRID_HZ
    fa, fb = springfit.features(a_times, a_full), springfit.features(b_times, b_full)
    if fa and fb:
        entry["peak_ms"] = abs(fa["peak_ms"] - fb["peak_ms"])
        entry["settle_ms"] = abs(fa["settle_ms"] - fb["settle_ms"])
        entry["overshoot_pct"] = abs(fa["overshoot_pct"] - fb["overshoot_pct"])
    sa, sb = springfit.fit(a_times, a_full), springfit.fit(b_times, b_full)
    if sa and sb and sa["rms"] < 0.15 and sb["rms"] < 0.15:
        entry["native_spring"], entry["flutter_spring"] = sa, sb
        entry["response_pct"] = abs(sa["response"] - sb["response"]) / sa["response"] * 100
        entry["damping"] = abs(sa["damping"] - sb["damping"])
    return entry


def best_lag(a_series, b_series):
    limit = int(MAX_LAG_MS / 1000 * align.GRID_HZ)
    moving = [key for key in align.KEYS if np.ptp(np.array(a_series[key])) >= MIN_TRAVEL[key]]
    if not moving:
        return 0
    series = [(np.array(a_series[key]) / np.ptp(a_series[key]), np.array(b_series[key]) / np.ptp(a_series[key])) for key in moving]
    best, chosen = float("inf"), 0
    for lag in range(-limit, limit + 1):
        error = 0.0
        for a, b in series:
            x, y = (a[lag:], b) if lag >= 0 else (a, b[-lag:])
            count = min(len(x), len(y))
            if count < 3:
                break
            error += float(np.mean((x[:count] - y[:count]) ** 2))
        else:
            if error < best:
                best, chosen = error, lag
    return chosen


def compare_motion(native, flutter):
    result = {"event_count": [len(native["events"]), len(flutter["events"])], "events": []}
    for native_event, flutter_event in zip(native["events"], flutter["events"]):
        a_series, b_series = native_event["series"], flutter_event["series"]
        lag = best_lag(a_series, b_series)
        event = {"lag_ms": lag * 1000 / align.GRID_HZ}
        for key in align.KEYS:
            a_full, b_full = np.array(a_series[key]), np.array(b_series[key])
            a, b = (a_full[lag:], b_full) if lag >= 0 else (a_full, b_full[-lag:])
            count = min(len(a), len(b))
            if count < 3:
                continue
            event[key] = compare_series(key, a[:count], b[:count], a_full, b_full)
        result["events"].append(event)
    return result


NOISE_FACTOR = 1.5
LIMITS = (("peak_ms", "time_ms"), ("settle_ms", "time_ms"), ("overshoot_pct", "overshoot_pct"), ("response_pct", "response_pct"), ("damping", "damping"))


def motion_measures(result):
    measures = {}
    for number, event in enumerate(result["events"]):
        for key in align.KEYS:
            for measure, limit in LIMITS:
                if key in event and measure in event[key]:
                    measures[f"event{number}.{key}.{measure}"] = (event[key][measure], limit)
    return measures


def motion_limits(result, noise=None):
    noise = noise or {}
    native, flutter = result["event_count"]
    limits = {"events.count": (abs(native - flutter), 0, "max"), "events.native_motion": (native, 1, "min")}
    for name, (value, limit) in motion_measures(result).items():
        limits[name] = (value, max(metrics.THRESHOLDS[limit], NOISE_FACTOR * noise.get(name, 0.0)), "max")
    return limits


FLOAT_SLACK = 1e-9


def within(value, limit, bound):
    return value >= limit - FLOAT_SLACK if bound == "min" else value <= limit + FLOAT_SLACK


def motion_checks(result, noise=None):
    return {name: within(*entry) for name, entry in motion_limits(result, noise).items()}


def limit(key, name, noise, value):
    return (value, max(metrics.THRESHOLDS[key], NOISE_FACTOR * noise.get(name, 0.0)), "max")


TOPOLOGY_MEASURES = ("count", "neck_pt", "gap_pt")


def topology_measures(topology, noise):
    return {
        f"ready.topology.{name}.{key}": limit(key, f"ready.topology.{name}.{key}", noise, entry[key])
        for name, entry in topology.items()
        for key in TOPOLOGY_MEASURES
    }


def analyze(scene, case_dir, noise=None, cache=None):
    noise = noise or {}
    case_dir = Path(case_dir)
    native_dir, flutter_dir = case_dir / "native", case_dir / "flutter"
    result = {"scene": scene.id, "case": case_dir.name}
    if scene.native_only:
        native = motion(native_dir, (0, 0, *metrics.SCREEN)) if not scene.rest else {"events": []}
        result.update(kind="reference", native_events=[{"start": e["start"], "series": e["series"]} for e in native["events"]])
        return result
    region = region_for(scene, native_dir)
    result["region"] = region
    flutter_timing = json.loads((flutter_dir / "timing.json").read_text()) if (flutter_dir / "timing.json").exists() else None
    if flutter_timing is None or flutter_timing.get("missing"):
        result["kind"] = "missing"
        return result
    result["kind"] = "compared"
    result["static"] = {}
    for name in ("ready", "settled"):
        result["static"][name] = metrics.static_compare(
            metrics.load(native_dir / f"{name}.png"),
            metrics.load(flutter_dir / f"{name}.png"),
            metrics.load(native_dir / "bare" / "ready.png"),
            metrics.load(flutter_dir / "bare" / "ready.png"),
            region,
            elements_for(scene),
        )
    measures = {
        f"{name}.{key}": limit(key, f"{name}.{key}", noise, stat[key])
        for name, stat in result["static"].items()
        for key in stat["pass"]
        if key in scene.measures
    }
    if scene.topology:
        result["topology"] = shapes.static_topology(scene, native_dir, flutter_dir)
        measures.update(topology_measures(result["topology"], noise))
    checks = {name: within(*entry) for name, entry in measures.items()}
    if not scene.rest and (scene.track or scene.topology):
        native, flutter = shape_capture(scene, native_dir, cache), shape_capture(scene, flutter_dir, cache)
        result["shapes"] = shapes.compare(scene, native, flutter)
        result["shape_rest"] = {"native": native.get("rest"), "flutter": flutter.get("rest")}
        result["native_stalls"] = native.get("stalls", [])
        result["flutter_stalls"] = flutter.get("stalls", [])
        limits = shapes.limits(result["shapes"], scene, noise)
        measures.update({f"motion.{k}": v for k, v in limits.items()})
        checks.update({f"motion.{k}": within(*v) for k, v in limits.items()})
    elif not scene.rest:
        native, flutter = cached_motion(native_dir, region, cache), cached_motion(flutter_dir, region, cache)
        result["motion"] = compare_motion(native, flutter)
        result["native_stalls"] = native["stalls"]
        result["flutter_stalls"] = flutter["stalls"]
        limits = motion_limits(result["motion"], noise)
        measures.update({f"motion.{k}": v for k, v in limits.items()})
        checks.update({f"motion.{k}": within(*v) for k, v in limits.items()})
    result["checks"] = checks
    result["measures"] = measures
    result["pass"] = bool(checks) and all(checks.values())
    return result
