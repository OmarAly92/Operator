import json
from pathlib import Path

import numpy as np

import align
import analyze
import build
import manifest
import metrics
import record
import shapes
import sim
import springfit
import track

SCENES = {
    "material.materialize": (0.55, 1.0),
    "material.materialize.snappy": (0.5, 0.85),
    "material.materialize.bouncy": (0.5, 0.7),
}
PRESETS = {"material.materialize": "Default", "material.materialize.snappy": "Snappy", "material.materialize.bouncy": "Bouncy"}
DEFAULT_SCENE = "material.materialize"
TOOL = "tool.visibility"
TABLE = build.PACKAGE_LIB / "src" / "motion" / "ios27_motion.dart"
GRID = 21
LEVELS = 11
RAMP_LEVELS = (0.0, 0.05, 0.1, 0.15, 0.2, 0.35, 0.5, 0.65, 0.8, 1.0)
OVER_LEVELS = (1.05, 1.1, 1.15, 1.2, 1.3, 1.4, 1.5)
RAMPS = (1.0, 2.0, 3.0, 4.0)
SHARPNESS_LIMIT = 1.0
PROGRESS_LIMIT = 0.05
LAGS = np.arange(-0.06, 0.0605, 0.002)
EXPONENTS = np.arange(1.0, 6.0001, 0.05)
GAINS = np.arange(0.0, 1.5001, 0.02)
RESPONSES = np.arange(0.3, 0.8001, 0.01)
DAMPINGS = np.arange(0.4, 1.4001, 0.01)
HORIZON = 0.9
OVERSHOOT = 1.001
SHARPNESS_AT = (0.25, 0.5, 0.75)
SHARPNESS_BIN = 0.1
SPRING_TOLERANCE = (0.05, 0.05)
OUTLIER_RMS = 0.1
FRAME_HZ = 60.0
FRAME_SECONDS = 2.0
APPEAR_EXPONENTS = np.arange(1.0, 3.0001, 0.05)
MOVING_MEASURES = ("t10_90_ms", "settle_ms", "overshoot_pct", "response_pct", "damping", "rms")
FIRST_FRAME_OUTCOMES = (True, False)
NOISE = manifest.LAB / "noise.json"


def levels(count=LEVELS):
    return [round(i / (count - 1), 4) for i in range(count)]


def case_parts(name):
    appearance, backdrop = name.split("-", 1)
    return appearance, backdrop


def normal_case(name):
    return len(name.split("-")) == 2


def reduce_motion_case(name):
    return name.endswith("-reduce-motion") and normal_case(name.removesuffix("-reduce-motion"))


def recordings(roots, scene_id):
    found = []
    for root in roots:
        root = Path(root)
        for case_dir in sorted((root / scene_id).glob("*")):
            if (case_dir / "native" / "video.mp4").exists():
                found.append((case_dir.name, root.name, case_dir / "native"))
        for take in sorted((root / "takes" / scene_id).glob("*/*")):
            if (take / "video.mp4").exists():
                found.append((take.parent.name, f"{root.name}/take{take.name}", take))
    return found


def native_curves(roots, scene):
    curves = []
    for case, take, folder in recordings(roots, scene.id):
        found = analyze.window(folder)
        capture = shapes.capture(scene, folder, found[:2] if found else None)
        rows = capture.get("rows", {}).get(scene.track[0])
        if not rows:
            continue
        times = np.array(rows["times"])
        values = np.array([row["progress"] for row in rows["rows"]])
        sharpness = np.array([row["sharpness"] for row in rows["rows"]])
        for event in capture["events"]:
            chosen = (times >= event["onset"] - 0.1) & (times <= event["onset"] + HORIZON)
            t, a = times[chosen] - event["onset"], values[chosen]
            if len(t) < 4:
                continue
            series = event.get("series", {}).get(scene.track[0], {}).get("progress")
            curves.append({"case": case, "take": take, "appearing": bool(a[-1] > a[0]), "t": t, "alpha": a, "sharpness": sharpness[chosen], "series": series})
    return curves


def mapped(s, appearing, exponent, gain, appear_exponent=1.0):
    if appearing:
        return np.where(s <= 1, np.maximum(s, 0.0) ** appear_exponent, 1 + gain * (s - 1))
    return np.clip(1 - s, 0.0, 1.0) ** exponent


def predicted(curve, response, damping, lag, exponent=1.0, gain=1.0):
    s = springfit.step_response(np.maximum(curve["t"] - lag, 0.0), response, damping)
    return mapped(s, curve["appearing"], exponent, gain)


def best_lag(curve, response, damping, exponent=1.0, gain=1.0):
    errors = [float(np.sqrt(np.mean((predicted(curve, response, damping, lag, exponent, gain) - curve["alpha"]) ** 2))) for lag in LAGS]
    index = int(np.argmin(errors))
    return float(LAGS[index]), errors[index]


def at_edge(value, grid):
    return bool(np.isclose(value, grid[0]) or np.isclose(value, grid[-1]))


def fit_grid(curves, grid, error_of):
    errors = np.array([[error_of(curve, value) for value in grid] for curve in curves])
    best = errors.min(axis=1)
    keep = best <= OUTLIER_RMS
    excluded = [{"take": c["take"], "case": c["case"], "rms": round(float(e), 4)} for c, e, k in zip(curves, best, keep) if not k]
    if not keep.any():
        return None, excluded, 0
    totals = (errors[keep] ** 2).sum(axis=0)
    index = int(np.argmin(totals))
    return (float(grid[index]), float(np.sqrt(totals[index] / keep.sum()))), excluded, int(keep.sum())


def fit_exponent(curves, response, damping):
    leaving = [c for c in curves if not c["appearing"]]
    if not leaving:
        return None
    found, excluded, used = fit_grid(leaving, EXPONENTS, lambda c, k: best_lag(c, response, damping, k)[1])
    if found is None:
        return None
    value, rms = found
    return {"value": round(value, 2), "rms": rms, "at_grid_edge": at_edge(value, EXPONENTS), "curves": used, "excluded": excluded}


def overshoots(response, damping):
    t = np.arange(0, HORIZON, 1 / 240)
    return float(springfit.step_response(t, response, damping).max()) > OVERSHOOT


def spring_overshoot(response, damping):
    t = np.arange(0, HORIZON, 1 / 240)
    return float(springfit.step_response(t, response, damping).max()) - 1


def overshoot_of(curve):
    features = springfit.features(curve["t"], curve["alpha"])
    return None if features is None else features["overshoot_pct"] / 100


def overshoot_targets(curves):
    found = {}
    for curve in curves:
        value = overshoot_of(curve) if curve["appearing"] else None
        if value is not None:
            found.setdefault(curve["case"], []).append(value)
    return {case: float(np.mean(values)) for case, values in found.items()}


def visibility(progress, table, above=()):
    last = len(table) - 1
    if progress <= 0:
        return table[0]
    if progress < 1:
        p = progress * last
        low = int(np.floor(p))
        return table[low] + (table[low + 1] - table[low]) * (p - low)
    points = [table[last], *above]
    if len(points) == 1:
        return table[last] + (table[last] - table[last - 1]) * last * (progress - 1)
    q = (progress - 1) * last
    top = len(points) - 1
    if q >= top:
        return points[top] + (points[top] - points[top - 1]) * (q - top)
    low = int(np.floor(q))
    return points[low] + (points[low + 1] - points[low]) * (q - low)


def realised_overshoot(rows, case, gain, overshoot, table, above):
    by_visibility = rows[case]
    visibilities = sorted(by_visibility)
    progress = np.maximum.accumulate(np.array([by_visibility[v][0] for v in visibilities]))
    return float(np.interp(visibility(1 + gain * overshoot, table, above), visibilities, progress)) - 1


def fit_peak_gain(targets, realised):
    cases = sorted(targets)
    if not cases:
        return None
    errors = np.array([[realised(case, g) - targets[case] for g in GAINS] for case in cases])
    totals = (errors ** 2).sum(axis=0)
    index = int(np.argmin(totals))
    value = float(GAINS[index])
    return {
        "value": round(value, 2),
        "rms": float(np.sqrt(totals[index] / len(cases))),
        "at_grid_edge": bool(np.isclose(value, GAINS[-1])),
        "at_floor": bool(np.isclose(value, GAINS[0])),
        "cases": cases,
        "native_overshoot": {case: round(targets[case], 5) for case in cases},
        "flutter_overshoot": {case: round(realised(case, value), 5) for case in cases},
    }


def appearance_of(case):
    return case.split("-", 1)[0]


def peak_gains(curves, response, damping, rows, table, above):
    overshoot = spring_overshoot(response, damping)
    targets = overshoot_targets(curves)
    known = {case: value for case, value in targets.items() if base_case(case) in rows}

    def realised(case, gain):
        return realised_overshoot(rows, base_case(case), gain, overshoot, table, above)

    cases = {case: fit_peak_gain({case: value}, realised) for case, value in sorted(known.items())}
    takes = {take: fit_peak_gain({c: v for c, v in overshoot_targets(found).items() if c in known}, realised) for take, found in sorted(by_take(curves).items())}
    dropped = {
        case: "no native overshoot measured" if case not in targets else f"no Flutter scan row for {base_case(case)}"
        for case in sorted({c["case"] for c in curves if c["appearing"]})
        if case not in known
    }
    return {
        "dropped": dropped,
        "pooled": fit_peak_gain(known, realised),
        "appearances": {
            appearance: fit_peak_gain({c: v for c, v in known.items() if appearance_of(c) == appearance}, realised)
            for appearance in sorted({appearance_of(c) for c in known})
        },
        "cases": cases,
        "case_spread": spread(cases),
        "take_spread": spread(takes),
        "spring_overshoot": round(overshoot, 5),
    }


def base_case(case):
    return case.removesuffix("-reduce-motion")


def spread(fits):
    values = [fit["value"] for fit in fits.values() if fit]
    if not values:
        return None
    return {"min": min(values), "max": max(values), "std": round(float(np.std(values)), 3), "per_take": {take: fit["value"] for take, fit in fits.items() if fit}}


def by_take(curves):
    grouped = {}
    for curve in curves:
        grouped.setdefault(curve["take"], []).append(curve)
    return grouped


INERT = {"value": 0.0, "identifiable": False, "inert": True, "from": "the spring does not overshoot, so no gain can be measured and none is used"}
GAIN_MODES = ("pooled", "per-appearance")


def inert_gains():
    return {"pooled": dict(INERT), "appearances": {"dark": dict(INERT), "light": dict(INERT)}, "cases": {}, "case_spread": None, "take_spread": None}


def fit_mapping(curves_by_scene, reduce_motion_by_scene=None):
    reduce_motion_by_scene = reduce_motion_by_scene or {}
    mapping = {}
    for scene_id, curves in curves_by_scene.items():
        response, damping = SCENES[scene_id]
        takes = by_take(curves)
        reduce_motion = reduce_motion_by_scene.get(scene_id, [])
        mapping[scene_id] = {
            "spring": [response, damping],
            "exponent": fit_exponent(curves, response, damping),
            "exponent_cases": {case: fit_exponent([c for c in curves if c["case"] == case], response, damping) for case in sorted({c["case"] for c in curves})},
            "exponent_spread": spread({take: fit_exponent(found, response, damping) for take, found in takes.items()}),
            "cases": sorted({c["case"] for c in curves}),
            "reduce_motion_cases": sorted({c["case"] for c in reduce_motion}),
            "takes": sorted(takes),
        }
    return mapping


def fit_gains(mapping, curves_by_scene, reduce_motion_by_scene, rows, table, above):
    for scene_id, entry in mapping.items():
        response, damping = SCENES[scene_id]
        if not overshoots(response, damping):
            entry["gains"], entry["reduce_motion_gains"] = inert_gains(), inert_gains()
            continue
        entry["gains"] = peak_gains(curves_by_scene.get(scene_id, []), response, damping, rows, table, above)
        reduce_motion = reduce_motion_by_scene.get(scene_id, [])
        entry["reduce_motion_gains"] = peak_gains(reduce_motion, response, damping, rows, table, above) if reduce_motion else None
    return mapping


def written_gains(entry, mode):
    found = {}
    for key, gains in (("normal", entry.get("gains")), ("reduce_motion", entry.get("reduce_motion_gains"))):
        for appearance in ("dark", "light"):
            if not gains:
                fit = None
            elif mode == "per-appearance":
                fit = (gains.get("appearances") or {}).get(appearance)
            else:
                fit = gains.get("pooled")
            found[(key, appearance)] = fit
    return found


def curve_error(curve, response, damping, exponent, gain):
    t = np.maximum(curve["t"][None, :] - LAGS[:, None], 0.0)
    model = mapped(springfit.step_response(t, response, damping), curve["appearing"], exponent, gain)
    return float(np.min(np.mean((model - curve["alpha"][None, :]) ** 2, axis=1)))


def fit_spring(curves, exponent, gain):
    best = None
    for response in RESPONSES:
        for damping in DAMPINGS:
            error = sum(curve_error(c, response, damping, exponent, gain) for c in curves)
            if best is None or error < best[0]:
                best = (error, float(response), float(damping))
    error, response, damping = best
    return {
        "response": round(response, 2),
        "damping": round(damping, 2),
        "rms": float(np.sqrt(error / max(1, len(curves)))),
        "at_grid_edge": at_edge(response, RESPONSES) or at_edge(damping, DAMPINGS),
    }


def spring_check(curves, mapping, scene_id=DEFAULT_SCENE):
    entry = mapping[scene_id]
    exponent = entry["exponent"]["value"] if entry["exponent"] else 1.0
    pooled = (entry.get("gains") or {}).get("pooled")
    gain = pooled["value"] if pooled else 0.0
    response, damping = SCENES[scene_id]

    def judged(fit):
        close = abs(fit["response"] - response) / response <= SPRING_TOLERANCE[0] + 1e-9 and abs(fit["damping"] - damping) <= SPRING_TOLERANCE[1] + 1e-9
        return {**fit, "pass": bool(close and not fit["at_grid_edge"])}

    result = {"swiftui": [response, damping], "all": judged(fit_spring(curves, exponent, gain))}
    result["cases"] = {case: judged(fit_spring([c for c in curves if c["case"] == case], exponent, gain)) for case in sorted({c["case"] for c in curves})}
    result["pass"] = result["all"]["pass"] and all(fit["pass"] for fit in result["cases"].values())
    return result


def flutter_frames(rows, table, above, response, damping, gain, appear_exponent, hz=FRAME_HZ, seconds=FRAME_SECONDS):
    visibilities = sorted(rows)
    progress = np.maximum.accumulate([rows[v] for v in visibilities])
    times = np.arange(int(round(seconds * hz))) / hz
    alpha = mapped(springfit.step_response(times, response, damping), True, 1.0, gain, appear_exponent)
    return times, np.interp([visibility(a, table, above) for a in alpha], visibilities, progress)


def recorded_series(times, progress, slope, keep_first):
    kept = [i for i in range(len(times)) if keep_first or i != 1]
    stamps, values = [float(times[i]) for i in kept], [float(progress[i]) for i in kept]
    diffs = [0.0] + [abs(b - a) * slope for a, b in zip(values, values[1:])]
    found = align.events(diffs, stamps)
    if not found:
        return None
    first, last = found[0]
    rows = [{**{key: 0.0 for key in shapes.KEYS}, "progress": value, "sharpness": 0.0, "residual": 0.0} for value in values]
    return shapes.event_series(stamps, rows, first, last)["progress"]


def moving_limits(noise, scene_id, case):
    found = noise.get(scene_id, {}).get(case, {})
    return {
        measure: max(metrics.THRESHOLDS[shapes.LIMITS[measure]], 1.5 * found.get(f"block.step3e0.progress.{measure}", 0.0))
        for measure in MOVING_MEASURES
    }


def progress_series(values):
    return {"progress": list(values), "sharpness": [0.0] * len(values), "residual": [0.0] * len(values)}


def moving_score(events, scene_id, rows, slopes, table, above, gain_of, appear_exponent, noise, outcomes=FIRST_FRAME_OUTCOMES):
    response, damping = SCENES[scene_id]
    failing, ratios, count = 0, [], 0
    simulated = {}
    for event in events:
        case = event["case"]
        base = base_case(case)
        if base not in rows or base not in slopes or event.get("series") is None:
            continue
        limits = moving_limits(noise, scene_id, case)
        for keep_first in outcomes:
            key = (base, gain_of(case), keep_first)
            if key not in simulated:
                times, progress = flutter_frames(rows[base], table, above, response, damping, gain_of(case), appear_exponent)
                simulated[key] = recorded_series(times, progress, slopes[base], keep_first)
            series = simulated[key]
            if series is None:
                continue
            found = shapes.compare_progress(progress_series(event["series"]), progress_series(series)) or {}
            count += 1
            for measure in MOVING_MEASURES:
                value = found.get(measure, float("inf"))
                failing += int(not value <= limits[measure])
                ratios.append(min(value / limits[measure], 10.0) if np.isfinite(value) else 10.0)
    if not count:
        return {"failing": float("inf"), "ratio": float("inf"), "pairs": 0}
    return {"failing": round(failing / count, 4), "ratio": round(float(np.mean(ratios)), 4), "pairs": count}


def fit_appear_exponent(events, scene_id, rows, slopes, table, above, gain_of, noise, outcomes=FIRST_FRAME_OUTCOMES):
    scores = {round(float(a), 2): moving_score(events, scene_id, rows, slopes, table, above, gain_of, float(a), noise, outcomes) for a in APPEAR_EXPONENTS}
    best = min(scores, key=lambda a: (scores[a]["failing"], scores[a]["ratio"]))
    return {
        "value": best,
        "at_grid_edge": at_edge(best, APPEAR_EXPONENTS),
        "events": len([e for e in events if e.get("series") is not None]),
        "objective": "mean failing Done measures per native appear and first-frame outcome, Flutter simulated from the scan at 60 Hz from its build frame; ties by mean value / limit",
        "table": {str(a): score for a, score in scores.items()},
    }


def fit_appear_exponents(mapping, curves_by_scene, reduce_motion_by_scene, rows, slopes, table, above, noise, mode="pooled"):
    for scene_id, entry in mapping.items():
        gains = written_gains(entry, mode)

        def gain_of(case, gains=gains):
            fit = gains.get(("reduce_motion" if case.endswith("-reduce-motion") else "normal", appearance_of(case)))
            return float(fit["value"]) if fit else 0.0

        events = [c for c in (*curves_by_scene.get(scene_id, []), *reduce_motion_by_scene.get(scene_id, [])) if c["appearing"]]
        entry["appear_exponent"] = fit_appear_exponent(events, scene_id, rows, slopes, table, above, gain_of, noise)
    return mapping


def appear_lines(mapping):
    lines = ["appear exponent (Done measures on simulated moving glass against every native appear, both first-frame outcomes):"]
    for scene_id, entry in mapping.items():
        fit = entry.get("appear_exponent")
        if not fit:
            continue
        table = fit["table"]
        one = table.get("1.0", {})
        chosen = table[str(fit["value"])]
        lines.append(f"  {scene_id:28} {fit['value']}  failing per appear {chosen['failing']} (at 1.0: {one.get('failing')}), mean value/limit {chosen['ratio']} (at 1.0: {one.get('ratio')}), {fit['events']} appears{', ON THE GRID EDGE' if fit['at_grid_edge'] else ''}")
    return lines


def scan_slopes(scan_dir, region):
    rect = track.pixel_rect(region)
    found = {}
    for case_dir in sorted(Path(scan_dir).glob("*")):
        bare, full = case_dir / "0.0" / "ready.png", case_dir / "1.0" / "ready.png"
        if bare.exists() and full.exists():
            found[case_dir.name] = metrics.mad(shapes.shrink(track.crop_px(metrics.load(full), rect)), shapes.shrink(track.crop_px(metrics.load(bare), rect)))
    return found


def scan(udid, cases, out, values, ramp):
    folder = Path(out) / f"ramp{ramp}"
    for name in cases:
        appearance, backdrop = case_parts(name)
        sim.appearance(udid, appearance)
        for visibility in values:
            shot = folder / name / f"{visibility}"
            if (shot / "ready.png").exists():
                continue
            record.drive(udid, build.EXAMPLE_BUNDLE, TOOL, [], backdrop, False, shot, settle=1.0, extra={"visibility": visibility, "blurRamp": ramp})
    return folder


def static_rows(scan_dir, region):
    rect = track.pixel_rect(region)
    found = {}
    for case_dir in sorted(Path(scan_dir).glob("*")):
        shots = {float(p.name): p / "ready.png" for p in case_dir.glob("*") if (p / "ready.png").exists()}
        if 0.0 not in shots or 1.0 not in shots:
            continue
        bare_px = track.crop_px(metrics.load(shots[0.0]), rect)
        full_px = track.crop_px(metrics.load(shots[1.0]), rect)
        bare, full = shapes.shrink(bare_px), shapes.shrink(full_px)
        inner = shapes.inner_slices(track.box(full_px, bare_px, track.edges(bare_px)), bare.shape)
        rows = {}
        for visibility, path in sorted(shots.items()):
            row = track.progress_row(shapes.shrink(track.crop_px(metrics.load(path), rect)), bare, full, inner)
            rows[visibility] = (row["progress"], row["sharpness"])
        found[case_dir.name] = rows
    return found


def native_sharpness(curves):
    samples = {}
    for curve in curves:
        for progress, sharpness in zip(curve["alpha"], curve["sharpness"]):
            if np.isfinite(progress) and np.isfinite(sharpness):
                samples.setdefault(curve["case"], []).append((float(progress), float(sharpness)))
    found = {}
    for case, pairs in samples.items():
        pairs = np.array(pairs)
        found[case] = {}
        for target in SHARPNESS_AT:
            near = pairs[np.abs(pairs[:, 0] - target) <= SHARPNESS_BIN]
            if len(near):
                found[case][target] = float(near[:, 1].mean())
    return found


def anchored(visibilities, progress, target):
    return len(visibilities) > 1 and visibilities[0] <= 0.0 and target < progress[1]


def flutter_sharpness(rows):
    found = {}
    for case, by_visibility in rows.items():
        visibilities = sorted(by_visibility)
        progress = np.maximum.accumulate(np.array([by_visibility[v][0] for v in visibilities]))
        sharpness = np.array([by_visibility[v][1] for v in visibilities])
        found[case] = {
            target: float("nan") if anchored(visibilities, progress, target) else float(np.interp(target, progress, sharpness))
            for target in SHARPNESS_AT
        }
    return found


def ramp_error(native, flutter, keep=None):
    differences = [
        flutter[case][target] - value
        for case, targets in native.items()
        if case in flutter
        for target, value in targets.items()
        if (keep is None or (case, target) in keep) and np.isfinite(flutter[case][target])
    ]
    return float(np.sqrt(np.mean(np.square(differences)))) if differences else float("inf")


def crossing_time(grid, values, target, rising):
    hits = np.nonzero(values >= target if rising else values <= target)[0]
    if not len(hits) or hits[0] == 0:
        return None
    i = hits[0]
    a, b = values[i - 1], values[i]
    return float(grid[i - 1] + (grid[i] - grid[i - 1]) * (target - a) / (b - a)) if b != a else float(grid[i])


def native_deviation(curves_by_scene):
    grid = np.arange(0, HORIZON, 1 / 120)
    found = {}
    for scene_id, curves in sorted(curves_by_scene.items()):
        for appearing in (True, False):
            group = [c for c in curves if c["appearing"] == appearing]
            cases = sorted({c["case"] for c in group})
            if len(cases) < 2:
                continue
            per_case = {case: np.mean([np.interp(grid, c["t"], c["alpha"]) for c in group if c["case"] == case], axis=0) for case in cases}
            mean = np.mean([per_case[case] for case in cases], axis=0)
            for target in SHARPNESS_AT:
                at = crossing_time(grid, mean, target, appearing)
                if at is None:
                    continue
                centre = float(np.interp(at, grid, mean))
                for case in cases:
                    found.setdefault(case, {}).setdefault(target, []).append(float(np.interp(at, grid, per_case[case])) - centre)
    return found


def flutter_deviation(rows):
    cases = sorted(rows)
    visibilities = sorted(v for v in rows[cases[0]] if v <= 1.0)
    progress = {case: np.array([rows[case][v][0] for v in visibilities]) for case in cases}
    mean = np.mean([progress[case] for case in cases], axis=0)
    monotone = np.maximum.accumulate(mean)
    found = {}
    for target in SHARPNESS_AT:
        at = float(np.interp(target, monotone, visibilities))
        centre = float(np.interp(at, visibilities, mean))
        for case in cases:
            found.setdefault(case, {})[target] = float(np.interp(at, visibilities, progress[case])) - centre
    return found


def deviation_error(native, flutter):
    differences = [flutter[case][target] - value for case, targets in native.items() if case in flutter for target, values in targets.items() for value in values]
    return float(np.sqrt(np.mean(np.square(differences)))) if differences else float("inf")


def finite(value, digits=3):
    return round(value, digits) if np.isfinite(value) else None


def unmeasured(flutter):
    return sorted(f"{case}@{target}" for case, found in flutter.items() for target, value in found.items() if not np.isfinite(value))


def ramp_objective(native_sharp, native_dev, rows, keep=None):
    flutter = flutter_sharpness(rows)
    sharpness = ramp_error(native_sharp, flutter, keep)
    deviation = deviation_error(native_dev, flutter_deviation(rows))
    return {
        "sharpness_rms": round(sharpness, 4),
        "progress_deviation_rms": round(deviation, 4),
        "objective": round(sharpness / SHARPNESS_LIMIT + deviation / PROGRESS_LIMIT, 4),
        "unmeasured": unmeasured(flutter),
        "flutter_deviation": {case: {str(t): round(v, 4) for t, v in found.items()} for case, found in flutter_deviation(rows).items()},
    }


def choose_ramp(native_sharp, native_dev, rows_by_ramp):
    flutter = {ramp: flutter_sharpness(rows) for ramp, rows in rows_by_ramp.items()}
    keep = {
        (case, target)
        for case, targets in native_sharp.items()
        for target in targets
        if all(case in found and np.isfinite(found[case][target]) for found in flutter.values())
    }
    dropped = sorted(f"{case}@{target}" for case, targets in native_sharp.items() for target in targets if (case, target) not in keep and any(case in found for found in flutter.values()))
    table = {ramp: ramp_objective(native_sharp, native_dev, rows, keep) for ramp, rows in rows_by_ramp.items()}
    best = min(table, key=lambda ramp: table[ramp]["objective"])
    ordered = sorted(table)
    return {
        "value": best,
        "objective": "sharpness RMS at matched progress, over the targets every k measures, / 1.0 + per-backdrop progress deviation RMS at fixed visibility / 0.05",
        "table": {str(ramp): table[ramp] for ramp in ordered},
        "dropped_targets": dropped,
        "native_deviation": {case: {str(t): round(float(np.mean(v)), 4) for t, v in found.items()} for case, found in native_dev.items()},
        "at_grid_edge": len(ordered) > 1 and best in (ordered[0], ordered[-1]),
    }


def ramp_lines(ramp):
    lines = [f"blur ramp trade-off ({ramp['objective']}):", "  k     sharpness_rms  deviation_rms  objective"]
    for k, row in ramp["table"].items():
        mark = "  <- chosen" if float(k) == float(ramp["value"]) else ""
        lines.append(f"  {float(k):<5} {row['sharpness_rms']:<14} {row['progress_deviation_rms']:<14} {row['objective']}{mark}")
    lines.append(f"  sharpness targets left out because a k reads them between the glass-absent shot and its first level: {', '.join(ramp.get('dropped_targets', [])) or 'none'}")
    return lines


def invert(progress_by_case, grid=GRID):
    progress_by_case = {case: {v: p for v, p in found.items() if v <= 1.0} for case, found in progress_by_case.items()}
    visibilities = sorted(next(iter(progress_by_case.values())))
    mean = np.mean([[curve[v] for v in visibilities] for curve in progress_by_case.values()], axis=0)
    monotone = np.maximum.accumulate(np.clip(mean, 0.0, 1.0))
    monotone[0], monotone[-1] = 0.0, 1.0
    targets = np.linspace(0.0, 1.0, grid)
    return [round(float(v), 4) for v in np.interp(targets, monotone, visibilities)], [round(float(a), 4) for a in mean]


def invert_above(progress_by_case, grid=GRID):
    above = {case: {v: p for v, p in found.items() if v >= 1.0} for case, found in progress_by_case.items()}
    visibilities = sorted(next(iter(above.values())))
    if len(visibilities) < 2 or visibilities[0] != 1.0:
        return [], []
    mean = np.mean([[curve[v] for v in visibilities] for curve in above.values()], axis=0)
    monotone = np.maximum.accumulate(mean)
    monotone[0] = 1.0
    step = 1 / (grid - 1)
    targets = [1 + k * step for k in range(1, grid) if 1 + k * step <= monotone[-1] + 1e-9]
    return [round(float(v), 4) for v in np.interp(targets, monotone, visibilities)], [round(float(a), 4) for a in mean]


def table_values(mapping, mode):
    values = {}
    for scene_id, name in PRESETS.items():
        entry = mapping.get(scene_id)
        if not entry:
            raise ValueError(f"{scene_id}: no fit")
        if not entry.get("exponent"):
            raise ValueError(f"{scene_id} disappear exponent: not fitted")
        values[f"ios27{name}DisappearExponent"] = float(entry["exponent"]["value"])
        if not entry.get("appear_exponent"):
            raise ValueError(f"{scene_id} appear exponent: not fitted")
        values[f"ios27{name}AppearExponent"] = float(entry["appear_exponent"]["value"])
        gains = written_gains(entry, mode) if "gains" in entry else legacy_gains(entry)
        for (key, appearance), fit in gains.items():
            label = f"ios27{name}{appearance.title()}{'ReduceMotion' if key == 'reduce_motion' else ''}AppearGain"
            if not fit:
                raise ValueError(f"{scene_id} {key.replace('_', ' ')} {appearance} appear gain: not fitted")
            values[label] = float(fit["value"])
    return values


def legacy_gains(entry):
    found = {}
    for key, fit in (("normal", entry.get("gain")), ("reduce_motion", entry.get("reduce_motion_gain"))):
        for appearance in ("dark", "light"):
            found[(key, appearance)] = fit
    return found


def table_source(mapping, ramp, table, above=(), mode="pooled"):
    values = table_values(mapping, mode)
    lines = [f"const double ios27BlurRampExponent = {float(ramp)};", ""]
    lines += [f"const double {name} = {value};" for name, value in values.items()]
    rows = ", ".join(f"{v}" for v in table)
    lines += ["", f"const List<double> ios27VisibilityForProgress = [\n  {rows},\n];"]
    lines += ["", f"const List<double> ios27VisibilityAboveFull = [{', '.join(f'{v}' for v in above)}];"]
    return "\n".join(lines) + "\n"


def edge_problems(label, fit, allowed=(), recorded=None):
    if not fit or fit.get("inert"):
        return []
    found = []
    if fit.get("at_grid_edge"):
        found.append(f"{label} = {fit['value']}: on the grid ceiling or edge")
    if fit.get("at_floor"):
        found.append(f"{label} = {fit['value']}: on the grid floor")
    return overridable(label, found, allowed, recorded)


def overridable(label, found, allowed=(), recorded=None):
    if found and label in allowed:
        if recorded is not None:
            recorded.append(label)
        return []
    return found


def case_problems(label, fit, allowed=(), recorded=None):
    if not fit:
        return overridable(label, [f"{label}: not fitted"], allowed, recorded)
    return edge_problems(label, fit, allowed, recorded)


def write_problems(summary, allowed=(), recorded=None):
    mapping, mode = summary["mapping"], summary.get("gain_mode", "pooled")
    found = []
    ramp = summary.get("blur_ramp") or {}
    if ramp.get("value") is None:
        found.append("ios27BlurRampExponent: not fitted")
    elif ramp.get("at_grid_edge"):
        found.append(f"ios27BlurRampExponent = {ramp['value']}: on the edge of the scanned ramps {sorted(float(k) for k in ramp.get('table', {}))}")
    table = summary.get("visibility_for_progress") or []
    if len(table) != GRID or table[0] != 0.0 or table[-1] != 1.0:
        found.append(f"ios27VisibilityForProgress: not a fitted {GRID}-entry table from 0 to 1")
    if not summary.get("visibility_above_full"):
        found.append("ios27VisibilityAboveFull: not fitted (no scan above visibility 1 reached progress 1.05)")
    for scene_id, name in PRESETS.items():
        entry = mapping.get(scene_id)
        if not entry:
            found.append(f"{scene_id}: no fit")
            continue
        exponent = entry.get("exponent")
        if not exponent:
            found.append(f"ios27{name}DisappearExponent: not fitted")
        elif exponent.get("at_grid_edge"):
            found.append(f"ios27{name}DisappearExponent = {exponent['value']}: on the grid edge")
        appear = entry.get("appear_exponent")
        if not appear:
            found.append(f"ios27{name}AppearExponent: not fitted")
        elif appear.get("at_grid_edge"):
            found.append(f"ios27{name}AppearExponent = {appear['value']}: on the grid edge")
        for (key, appearance), fit in written_gains(entry, mode).items():
            label = f"ios27{name}{appearance.title()}{'ReduceMotion' if key == 'reduce_motion' else ''}AppearGain"
            if not fit:
                found.append(f"{label}: not fitted")
                continue
            if not fit.get("inert") and fit.get("identifiable") is False:
                found.append(f"{label}: not fitted ({fit.get('from', 'not identifiable')})")
            found += edge_problems(label, fit)
        for case, fit in (entry.get("exponent_cases") or {}).items():
            found += case_problems(f"{scene_id}/exponent/{case}", fit, allowed, recorded)
        for key in ("gains", "reduce_motion_gains"):
            gains = entry.get(key) or {}
            for case, fit in (gains.get("cases") or {}).items():
                found += case_problems(f"{scene_id}/{key.removesuffix('s')}/{case}", fit, allowed, recorded)
            for case, reason in (gains.get("dropped") or {}).items():
                label = f"{scene_id}/{key.removesuffix('s')}/{case}"
                found += overridable(label, [f"{label}: dropped, {reason}"], allowed, recorded)
    return found


def run(udid, roots, out, count=LEVELS, write=False, ramps=RAMPS, mode="pooled", allowed=()):
    build.require_fresh("example")
    scenes = {s.id: s for s in manifest.load()}
    default = scenes[DEFAULT_SCENE]
    region = default.regions[default.track[0]]
    every = {scene_id: native_curves(roots, scenes[scene_id]) for scene_id in SCENES}
    curves = {scene_id: [c for c in found if normal_case(c["case"])] for scene_id, found in every.items()}
    curves = {scene_id: found for scene_id, found in curves.items() if found}
    reduce_motion = {scene_id: [c for c in found if reduce_motion_case(c["case"])] for scene_id, found in every.items()}
    mapping = fit_mapping(curves, reduce_motion)
    cases = sorted({c["case"] for c in curves[DEFAULT_SCENE]})
    native = native_sharpness([c for found in curves.values() for c in found])
    deviation = native_deviation(curves)
    rows_by_ramp = {ramp: static_rows(scan(udid, cases, out, RAMP_LEVELS, ramp), region) for ramp in ramps}
    ramp = choose_ramp(native, deviation, rows_by_ramp)
    for line in ramp_lines(ramp):
        print(line)
    final = static_rows(scan(udid, cases, Path(out) / "table", [*levels(count), *OVER_LEVELS], ramp["value"]), region)
    progress = {case: {v: row[0] for v, row in rows.items()} for case, rows in final.items()}
    table, mean = invert(progress)
    above, above_mean = invert_above(progress)
    fit_gains(mapping, curves, reduce_motion, final, table, above)
    slopes = scan_slopes(Path(out) / "table" / f"ramp{ramp['value']}", region)
    noise = json.loads(NOISE.read_text()) if NOISE.exists() else {}
    fit_appear_exponents(mapping, curves, reduce_motion, progress, slopes, table, above, noise, mode)
    for line in appear_lines(mapping):
        print(line)
    check = spring_check(curves[DEFAULT_SCENE], mapping)
    summary = {
        "roots": [str(root) for root in roots],
        "gain_mode": mode,
        "mapping": mapping,
        "default_spring_check": check,
        "blur_ramp": ramp,
        "native_sharpness": {case: {str(k): round(v, 3) for k, v in found.items()} for case, found in native.items()},
        "flutter_sharpness": {str(r): {case: {str(k): finite(v) for k, v in found.items()} for case, found in flutter_sharpness(rows).items()} for r, rows in rows_by_ramp.items()},
        "flutter_sharpness_table": {case: {str(k): finite(v) for k, v in found.items()} for case, found in flutter_sharpness(final).items()},
        "flutter_progress": {case: {str(v): round(row[0], 4) for v, row in rows.items()} for case, rows in final.items()},
        "flutter_progress_mean": mean,
        "flutter_progress_mean_above_full": above_mean,
        "visibility_for_progress": table,
        "visibility_above_full": above,
        "scan_slopes": {case: round(value, 4) for case, value in slopes.items()},
    }
    recorded = []
    problems = write_problems(summary, allowed, recorded)
    summary["overrides"] = {"allowed": sorted(allowed), "used": sorted(recorded)}
    summary["write"] = {"requested": bool(write), "refused": problems if write else [], "problems": problems}
    Path(out).mkdir(parents=True, exist_ok=True)
    Path(out, "fit.json").write_text(json.dumps(summary, indent=2))
    print(f"gain mode: {mode} (the table carries {'one gain per appearance' if mode == 'per-appearance' else 'the pooled gain for both appearances'})")
    if write:
        write_table(summary, problems)
    return summary


def write_table(summary, problems, target=None):
    target = Path(target or TABLE)
    if problems:
        raise SystemExit(f"fitvis --write refused, nothing written to {target}:\n" + "\n".join(f"  - {problem}" for problem in problems))
    target.write_text(table_source(summary["mapping"], summary["blur_ramp"]["value"], summary["visibility_for_progress"], summary["visibility_above_full"], summary["gain_mode"]))
