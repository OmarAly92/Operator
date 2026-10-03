import json
from pathlib import Path

import numpy as np

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
RAMP_LEVELS = (0.0, 0.2, 0.35, 0.5, 0.65, 0.8, 1.0)
RAMPS = (1.0, 2.0, 3.0, 4.0)
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
            curves.append({"case": case, "take": take, "appearing": bool(a[-1] > a[0]), "t": t, "alpha": a, "sharpness": sharpness[chosen]})
    return curves


def mapped(s, appearing, exponent, gain):
    if appearing:
        return np.where(s <= 1, np.maximum(s, 0.0), 1 + gain * (s - 1))
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


def fit_gain(curves, response, damping):
    arriving = [c for c in curves if c["appearing"]]
    if not arriving or not overshoots(response, damping):
        return None
    found, excluded, used = fit_grid(arriving, GAINS, lambda c, g: best_lag(c, response, damping, 1.0, g)[1])
    if found is None:
        return None
    value, rms = found
    return {
        "value": round(value, 2),
        "rms": rms,
        "at_grid_edge": bool(np.isclose(value, GAINS[-1])),
        "at_floor": bool(np.isclose(value, GAINS[0])),
        "curves": used,
        "excluded": excluded,
    }


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


INERT = {"value": 0.0, "identifiable": False, "from": "the spring does not overshoot, so no gain can be measured and none is used"}


def gains_for(curves, reduce_motion, response, damping):
    if not overshoots(response, damping):
        return dict(INERT), dict(INERT)
    gain = fit_gain(curves, response, damping)
    reduce_gain = fit_gain(reduce_motion, response, damping)
    if reduce_gain is None and not reduce_motion and gain:
        reduce_gain = {**gain, "identifiable": False, "from": "the normal gain: no Reduce Motion recording"}
    return gain, reduce_gain


def fit_mapping(curves_by_scene, reduce_motion_by_scene=None):
    reduce_motion_by_scene = reduce_motion_by_scene or {}
    mapping = {}
    for scene_id, curves in curves_by_scene.items():
        response, damping = SCENES[scene_id]
        takes = by_take(curves)
        reduce_motion = reduce_motion_by_scene.get(scene_id, [])
        gain, reduce_gain = gains_for(curves, reduce_motion, response, damping)
        mapping[scene_id] = {
            "spring": [response, damping],
            "exponent": fit_exponent(curves, response, damping),
            "gain": gain,
            "reduce_motion_gain": reduce_gain,
            "exponent_spread": spread({take: fit_exponent(found, response, damping) for take, found in takes.items()}),
            "gain_spread": spread({take: fit_gain(found, response, damping) for take, found in takes.items()}),
            "reduce_motion_gain_spread": spread({take: fit_gain(found, response, damping) for take, found in by_take(reduce_motion).items()}),
            "cases": sorted({c["case"] for c in curves}),
            "reduce_motion_cases": sorted({c["case"] for c in reduce_motion}),
            "takes": sorted(takes),
        }
    return mapping


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
    gain = entry["gain"]["value"] if entry["gain"] else 1.0
    response, damping = SCENES[scene_id]

    def judged(fit):
        close = abs(fit["response"] - response) / response <= SPRING_TOLERANCE[0] + 1e-9 and abs(fit["damping"] - damping) <= SPRING_TOLERANCE[1] + 1e-9
        return {**fit, "pass": bool(close and not fit["at_grid_edge"])}

    result = {"swiftui": [response, damping], "all": judged(fit_spring(curves, exponent, gain))}
    result["cases"] = {case: judged(fit_spring([c for c in curves if c["case"] == case], exponent, gain)) for case in sorted({c["case"] for c in curves})}
    result["pass"] = result["all"]["pass"] and all(fit["pass"] for fit in result["cases"].values())
    return result


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


def flutter_sharpness(rows):
    found = {}
    for case, by_visibility in rows.items():
        visibilities = sorted(by_visibility)
        progress = np.maximum.accumulate(np.array([by_visibility[v][0] for v in visibilities]))
        sharpness = np.array([by_visibility[v][1] for v in visibilities])
        found[case] = {target: float(np.interp(target, progress, sharpness)) for target in SHARPNESS_AT}
    return found


def ramp_error(native, flutter):
    differences = [flutter[case][target] - value for case, targets in native.items() if case in flutter for target, value in targets.items()]
    return float(np.sqrt(np.mean(np.square(differences)))) if differences else float("inf")


def choose_ramp(native, rows_by_ramp):
    errors = {ramp: ramp_error(native, flutter_sharpness(rows)) for ramp, rows in rows_by_ramp.items()}
    best = min(errors, key=errors.get)
    ordered = sorted(errors)
    return {"value": best, "errors": errors, "at_grid_edge": len(ordered) > 1 and best in (ordered[0], ordered[-1])}


def invert(progress_by_case, grid=GRID):
    visibilities = sorted(next(iter(progress_by_case.values())))
    mean = np.mean([[curve[v] for v in visibilities] for curve in progress_by_case.values()], axis=0)
    monotone = np.maximum.accumulate(np.clip(mean, 0.0, 1.0))
    monotone[0], monotone[-1] = 0.0, 1.0
    targets = np.linspace(0.0, 1.0, grid)
    return [round(float(v), 4) for v in np.interp(targets, monotone, visibilities)], [round(float(a), 4) for a in mean]


def table_source(mapping, ramp, table):
    lines = [f"const double ios27BlurRampExponent = {float(ramp)};", ""]
    for scene_id, name in PRESETS.items():
        entry = mapping.get(scene_id)
        if not entry:
            continue
        exponent = entry["exponent"]["value"] if entry["exponent"] else 1.0
        gain = entry["gain"]["value"] if entry["gain"] else 1.0
        reduce_motion = entry["reduce_motion_gain"]["value"] if entry.get("reduce_motion_gain") else gain
        lines.append(f"const double ios27{name}DisappearExponent = {float(exponent)};")
        lines.append(f"const double ios27{name}AppearGain = {float(gain)};")
        lines.append(f"const double ios27{name}ReduceMotionAppearGain = {float(reduce_motion)};")
    rows = ", ".join(f"{v}" for v in table)
    lines += ["", f"const List<double> ios27VisibilityForProgress = [\n  {rows},\n];"]
    return "\n".join(lines) + "\n"


def run(udid, roots, out, count=LEVELS, write=False, ramps=RAMPS):
    build.require_fresh("example")
    scenes = {s.id: s for s in manifest.load()}
    default = scenes[DEFAULT_SCENE]
    region = default.regions[default.track[0]]
    every = {scene_id: native_curves(roots, scenes[scene_id]) for scene_id in SCENES}
    curves = {scene_id: [c for c in found if normal_case(c["case"])] for scene_id, found in every.items()}
    curves = {scene_id: found for scene_id, found in curves.items() if found}
    reduce_motion = {scene_id: [c for c in found if reduce_motion_case(c["case"])] for scene_id, found in every.items()}
    mapping = fit_mapping(curves, reduce_motion)
    check = spring_check(curves[DEFAULT_SCENE], mapping)
    cases = sorted({c["case"] for c in curves[DEFAULT_SCENE]})
    native = native_sharpness([c for found in curves.values() for c in found])
    rows_by_ramp = {ramp: static_rows(scan(udid, cases, out, RAMP_LEVELS, ramp), region) for ramp in ramps}
    ramp = choose_ramp(native, rows_by_ramp)
    final = static_rows(scan(udid, cases, Path(out) / "table", levels(count), ramp["value"]), region)
    table, mean = invert({case: {v: row[0] for v, row in rows.items()} for case, rows in final.items()})
    summary = {
        "roots": [str(root) for root in roots],
        "mapping": mapping,
        "default_spring_check": check,
        "blur_ramp": ramp,
        "native_sharpness": {case: {str(k): round(v, 3) for k, v in found.items()} for case, found in native.items()},
        "flutter_sharpness": {str(r): {case: {str(k): round(v, 3) for k, v in found.items()} for case, found in flutter_sharpness(rows).items()} for r, rows in rows_by_ramp.items()},
        "flutter_sharpness_table": {case: {str(k): round(v, 3) for k, v in found.items()} for case, found in flutter_sharpness(final).items()},
        "flutter_progress": {case: {str(v): round(row[0], 4) for v, row in rows.items()} for case, rows in final.items()},
        "flutter_progress_mean": mean,
        "visibility_for_progress": table,
    }
    Path(out).mkdir(parents=True, exist_ok=True)
    Path(out, "fit.json").write_text(json.dumps(summary, indent=2))
    if write:
        TABLE.write_text(table_source(mapping, ramp["value"], table))
    return summary
