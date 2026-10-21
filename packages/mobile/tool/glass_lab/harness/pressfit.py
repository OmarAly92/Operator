import json
import math
from pathlib import Path

import numpy as np

import metrics
import press
import springfit

LAB = Path(__file__).resolve().parents[1]
TABLE = LAB.parents[1] / "packages" / "ios_liquid_glass" / "lib" / "src" / "motion" / "ios27_press.dart"
STEP_PT = 1.0 / 3.0
SIGMAS = np.arange(20.0, 300.0 + 1e-9, 1.0)
FOLLOWS = np.round(np.arange(0.05, 2.0 + 1e-9, 0.01), 2)
PLATEAU_SECONDS = 0.3
HELD_OUT = ("material.press.circle44", "material.press.120x250")
EDGE_SHARE = 0.25
SIZE_LIMIT = metrics.THRESHOLDS["bbox_pt"]
REDUCE_MOTION_PRESSES = 5
FIT_RESPONSES = np.round(np.arange(0.01, 1.5 + 1e-9, 0.005), 3)
FIT_DAMPINGS = np.round(np.arange(0.1, 4.0 + 1e-9, 0.01), 2)
HOLD_DROP = 0.5


def load(paths):
    found = {}
    for path in paths:
        found.update(json.loads(Path(path).read_text()))
    return found


def mode(key):
    return "reduce-motion" if "reduce-motion" in key else "normal"


def size_of(scene_id):
    if scene_id == "material.interactive" or scene_id.startswith("material.drag."):
        return 250.0, 88.0, "capsule"
    tail = scene_id.split(".")[-1]
    if tail.startswith("capsule"):
        return 120.0, float(tail[len("capsule") :]), "capsule"
    if tail.startswith("circle"):
        side = float(tail[len("circle") :])
        return side, side, "circle"
    width, height = (float(v) for v in tail.split("x"))
    return width, height, "rect32" if (width, height) in RECT32 else "capsule"


RECT32 = ((360.0, 200.0), (300.0, 250.0))


def usable(entry, name):
    if entry.get("takecheck", {}).get("failures"):
        return False
    return not entry["steps"].get("step1", {}).get(name, {}).get("hole", False)


def skipped(series):
    return sorted(key for key, entry in series.items() if any(not usable(entry, name) for name in entry["series"]))


def plateaus(series):
    for key, entry in series.items():
        scene_id = key.split("/")[0]
        if not (scene_id == "material.interactive" or scene_id.startswith("material.press.")) or scene_id in HELD_OUT:
            continue
        if mode(key) != "normal" or key.split("/")[1].split("-")[1] != "photo" or not entry.get("touches"):
            continue
        down, up = entry["touches"][0]
        for name, rows in entry["series"].items():
            case = {"key": key, "size": size_of(scene_id), "times": np.array(rows["times"], dtype=np.float64), "rows": rows, "down": down, "up": up}
            case["plateau"] = plateau(case)
            if case["plateau"] is not None:
                yield case


def presses(series):
    for key, entry in series.items():
        scene_id = key.split("/")[0]
        if not (scene_id == "material.interactive" or scene_id.startswith("material.press.")) or scene_id in HELD_OUT:
            continue
        for name, rows in entry["series"].items():
            if not usable(entry, name) or "step1" not in entry["steps"]:
                continue
            times = np.array(rows["times"], dtype=np.float64)
            down, up = entry["touches"][0]
            later = [w[0] for w in entry["touches"] if w[0] > up]
            case = {
                "key": key,
                "scene": scene_id,
                "mode": mode(key),
                "backdrop": key.split("/")[1].split("-")[1],
                "size": size_of(scene_id),
                "times": times,
                "rows": rows,
                "down": down,
                "up": up,
                "end": later[0] if later else math.inf,
                "features": entry["steps"]["step1"][name],
            }
            case["plateau"] = plateau(case)
            yield case


def plateau(case):
    times, rows = case["times"], case["rows"]
    first = rest_index(times, case["down"])
    width = np.array(rows["width"]) - rows["width"][first]
    held = width[(times > case["up"] - PLATEAU_SECONDS) & (times <= case["up"])]
    return float(held.mean()) if len(held) else None


def rest_index(times, down):
    return press.rest_index(list(times), down)


LAW_CAPS = np.round(np.arange(14.0, 20.0 + 1e-9, 0.02), 2)
LAW_AT_100 = np.round(np.arange(4.0, 40.0 + 1e-9, 0.01), 2)
LAW_POWERS = np.round(np.arange(0.5, 2.0 + 1e-9, 0.01), 2)
LAW_WIDTH_POWERS = np.round(np.arange(-1.0, 1.0 + 1e-9, 0.05), 2)
LAW_FORMS = ("height", "area", "height_width")


def law_errors(caps, scales, values, grown):
    model = np.minimum(caps[:, None, None], scales[None, :, None] * values[None, None, :])
    return np.sqrt(np.mean((model - grown[None, None, :]) ** 2, axis=2))


def law_point(values, grown):
    coarse_caps, coarse_scales = LAW_CAPS[::5], LAW_AT_100[::10]
    errors = law_errors(coarse_caps, coarse_scales, values, grown)
    i, j = np.unravel_index(np.argmin(errors), errors.shape)
    caps = LAW_CAPS[np.abs(LAW_CAPS - coarse_caps[i]) <= 0.1 + 1e-9]
    scales = LAW_AT_100[np.abs(LAW_AT_100 - coarse_scales[j]) <= 0.1 + 1e-9]
    errors = law_errors(caps, scales, values, grown)
    k, m = np.unravel_index(np.argmin(errors), errors.shape)
    return float(errors[k, m]), float(caps[k]), float(scales[m])


def law_grid(base, grown, powers, factor=None):
    factor = np.ones_like(base) if factor is None else factor
    best = None
    for power in powers:
        error, cap, at_100 = law_point(factor * base ** power, grown)
        if best is None or error < best[0]:
            best = (error, cap, at_100, float(power))
    error, cap, at_100, power = best
    return {
        "cap": cap,
        "at_100": at_100,
        "power": power,
        "rms": error,
        "on_edge": bool(cap in (LAW_CAPS[0], LAW_CAPS[-1]) or at_100 in (LAW_AT_100[0], LAW_AT_100[-1]) or (len(powers) > 1 and power in (powers[0], powers[-1]))),
    }


def law_fit(form, widths, heights, grown):
    if form == "height":
        return dict(law_grid(100.0 / heights, grown, LAW_POWERS), width_power=0.0, form=form)
    if form == "area":
        law = law_grid(1e4 / (widths * heights), grown, LAW_POWERS)
        return dict(law, width_power=law["power"], form=form)
    best = None
    for width_power in LAW_WIDTH_POWERS:
        law = law_grid(100.0 / heights, grown, LAW_POWERS, (100.0 / widths) ** width_power)
        if best is None or law["rms"] < best["rms"]:
            best = dict(law, width_power=float(width_power), form=form)
    best["on_edge"] = bool(best["on_edge"] or best["width_power"] in (LAW_WIDTH_POWERS[0], LAW_WIDTH_POWERS[-1]))
    return best


def law_value(law, width, height):
    return min(law["cap"], law["at_100"] * (100.0 / height) ** law["power"] * (100.0 / width) ** law.get("width_power", 0.0))


def held_out(form, widths, heights, grown, sizes):
    squares = []
    for size in sorted(set(sizes)):
        keep = np.array([s != size for s in sizes])
        law = law_fit(form, widths[keep], heights[keep], grown[keep])
        squares += [(law_value(law, w, h) - g) ** 2 for w, h, g, s in zip(widths, heights, grown, sizes) if s == size]
    return float(np.sqrt(np.mean(squares)))


def size_residuals(law, widths, heights, grown, sizes):
    found = {}
    for size in sorted(set(sizes)):
        mask = np.array([s == size for s in sizes])
        found[f"{size[0]:g}x{size[1]:g}"] = law_value(law, size[0], size[1]) - float(np.median(grown[mask]))
    return found


def fit_growth_law(cases, forms=LAW_FORMS):
    widths = np.array([c["size"][0] for c in cases], dtype=np.float64)
    heights = np.array([c["size"][1] for c in cases], dtype=np.float64)
    grown = np.array([c["plateau"] for c in cases], dtype=np.float64)
    sizes = [tuple(c["size"][:2]) for c in cases]
    found = {}
    for form in forms:
        law = law_fit(form, widths, heights, grown)
        residuals = size_residuals(law, widths, heights, grown, sizes)
        found[form] = dict(law, held_out_rms=held_out(form, widths, heights, grown, sizes), residuals=residuals, within=all(abs(r) <= SIZE_LIMIT for r in residuals.values()))
    eligible = [form for form in forms if found[form]["within"]]
    if eligible:
        chosen = min(eligible, key=lambda form: found[form]["held_out_rms"])
    else:
        chosen = min(found, key=lambda form: max(abs(r) for r in found[form]["residuals"].values()))
    ranked = sorted(eligible, key=lambda form: found[form]["held_out_rms"])
    separated = len(ranked) < 2 or found[ranked[1]]["held_out_rms"] - found[ranked[0]]["held_out_rms"] > SIZE_LIMIT / 3
    return dict(found[chosen], chosen=chosen, forms=found, separated=separated, cases=len(cases))


def fit_raw(times, values):
    t = np.asarray(times, dtype=np.float64)[None, None, :]
    curves = springfit.step_response(t, FIT_RESPONSES[:, None, None], FIT_DAMPINGS[None, :, None])
    errors = np.sqrt(np.mean((curves - np.asarray(values, dtype=np.float64)[None, None, :]) ** 2, axis=2))
    i, j = np.unravel_index(np.argmin(errors), errors.shape)
    edge = i in (0, len(FIT_RESPONSES) - 1) or j in (0, len(FIT_DAMPINGS) - 1)
    return {"response": float(FIT_RESPONSES[i]), "damping": float(FIT_DAMPINGS[j]), "rms": float(errors[i, j]), "at_grid_edge": bool(edge)}


def reach(spring, share):
    t = np.arange(0.0, 1.0, 0.0005)
    curve = springfit.step_response(t, spring["response"], spring["damping"])
    hits = np.nonzero(curve >= share)[0]
    return float(t[hits[0]]) if len(hits) else 0.0


JUMPS = np.round(np.arange(0.0, 1.0 + 1e-9, 0.05), 2)


def fit_jump(times, values):
    t = np.asarray(times, dtype=np.float64)[1:]
    v = np.asarray(values, dtype=np.float64)[1:]
    if len(t) < 2:
        return None
    curves = springfit.step_response(t[None, None, :], FIT_RESPONSES[:, None, None], FIT_DAMPINGS[None, :, None])
    best = None
    for jump in JUMPS:
        errors = np.sqrt(np.mean((jump + (1 - jump) * curves - v[None, None, :]) ** 2, axis=2))
        i, j = np.unravel_index(np.argmin(errors), errors.shape)
        if best is None or errors[i, j] < best["rms"]:
            edge = i in (0, len(FIT_RESPONSES) - 1) or j in (0, len(FIT_DAMPINGS) - 1)
            best = {"jump": float(jump), "response": float(FIT_RESPONSES[i]), "damping": float(FIT_DAMPINGS[j]), "rms": float(errors[i, j]), "at_grid_edge": bool(edge)}
    return best


def first_change(times, values, start, reference, threshold):
    for t, v in zip(times, values):
        if t > start and abs(v - reference) >= threshold:
            return t
    return None


def shares(times, values, origin, stop, start_value, end_value, zero=None):
    before = times[times < origin]
    keep = (times >= origin) & (times <= stop)
    if zero is None:
        zero = before[-1] if len(before) else origin
    t = np.concatenate([[0.0], times[keep] - zero])
    v = np.concatenate([[start_value], values[keep]])
    return t, (v - start_value) / (end_value - start_value)


def growth_fit(case):
    times, rows = case["times"], case["rows"]
    first = rest_index(times, case["down"])
    width = np.array(rows["width"]) - rows["width"][first]
    plateau = width[(times > case["up"] - PLATEAU_SECONDS) & (times <= case["up"])]
    if not len(plateau) or plateau.mean() < press.MIN_GROWTH:
        return None
    began = first_change(times, width, case["down"], 0.0, STEP_PT + 1e-6)
    if began is None:
        return None
    level = float(plateau.mean())
    t, v = shares(times, width, began, case["up"], 0.0, level)
    spring = fit_raw(t, v)
    return {"delay": float(began - case["down"] - reach(spring, STEP_PT / level)), "seen_ms": float((began - case["down"]) * 1000), **spring}


def release_fit(case):
    times, rows = case["times"], case["rows"]
    first = rest_index(times, case["down"])
    width = np.array(rows["width"]) - rows["width"][first]
    at_up = float(width[times <= case["up"]][-1])
    if at_up < press.MIN_GROWTH:
        return None
    began = first_change(times, width, case["up"], at_up, STEP_PT + 1e-6)
    if began is None:
        return None
    t, v = shares(times, width, began, min(case["end"], case["up"] + 1.0), at_up, 0.0)
    spring = fit_raw(t, v)
    return {"delay": float(began - case["up"] - reach(spring, STEP_PT / at_up)), "seen_ms": float((began - case["up"]) * 1000), **spring}


def glow_fit(case):
    times, rows = case["times"], case["rows"]
    first = rest_index(times, case["down"])
    glow = np.array(rows["glow"]) - rows["glow"][first]
    f = case["features"]
    peak, cut = f["glow_peak"], f["glow_drop_ms"]
    if peak < press.MIN_GLOW:
        return None
    hold_level = f["glow_drop"] if cut is not None else 0.0
    swell = peak - hold_level
    during = (times >= case["down"]) & (times <= case["up"])
    t, v = shares(times, glow, case["down"], case["up"], 0.0, peak, zero=case["down"])
    rise = fit_jump(t, v)
    if cut is None:
        return {"peak": float(peak), "hold_level": 0.0, "swell": float(peak), "first_share": None, "rise": rise, "hold_ms": None, "fade": None, "cut_ms": None}
    after = (times > case["up"]) & (times < case["up"] + cut / 1000.0)
    held = None
    for t_, g in zip(times[after], glow[after]):
        if g < peak - HOLD_DROP:
            held = t_ - case["up"]
            break
    fade = None
    if held is not None and swell > press.MIN_GLOW / 2:
        t, v = shares(times, glow, case["up"] + held, case["up"] + cut / 1000.0 - 1e-6, peak, hold_level)
        fade = fit_raw(t, v)
    return {
        "peak": float(peak),
        "hold_level": float(hold_level),
        "swell": float(swell),
        "first_share": float(glow[during][0] / peak) if during.any() else 0.0,
        "rise": rise,
        "hold_ms": None if held is None else float(held * 1000),
        "fade": fade,
        "cut_ms": float(cut),
    }


def median(values):
    values = [v for v in values if v is not None and np.isfinite(v)]
    return float(np.median(values)) if values else None


def gaussian_mean(width, height, sigma, focus=(0.0, 0.0), shape="capsule"):
    xs = np.linspace(-width / 2, width / 2, 121)
    ys = np.linspace(-height / 2, height / 2, 61)
    x, y = np.meshgrid(xs, ys)
    inside = inside_shape(x, y, width, height, shape)
    values = np.exp(-((x - focus[0]) ** 2 + (y - focus[1]) ** 2) / (2 * sigma * sigma))
    return float(values[inside].mean())


def inside_shape(x, y, width, height, shape):
    if shape == "circle":
        return x * x + y * y <= (width / 2) ** 2
    radius = min(width, height) / 2 if shape == "capsule" else 32.0
    cx = np.clip(np.abs(x), 0, width / 2 - radius)
    cy = np.clip(np.abs(y), 0, height / 2 - radius)
    return (np.abs(x) - cx) ** 2 + (np.abs(y) - cy) ** 2 <= radius * radius


def fit_sigma(profile, hold_level):
    distances = np.array([p[0] for p in profile])
    values = np.array([p[1] for p in profile]) - hold_level
    best = (math.inf, None, None)
    for sigma in SIGMAS:
        shape = np.exp(-(distances**2) / (2 * sigma * sigma))
        scale = float((shape * values).sum() / (shape * shape).sum())
        error = float(np.sqrt(np.mean((scale * shape - values) ** 2)))
        if error < best[0]:
            best = (error, float(sigma), scale)
    return {"sigma": best[1], "peak": best[2], "rms": best[0], "on_edge": best[1] in (SIGMAS[0], SIGMAS[-1])}


def size_table(fits, sigma):
    by_size = {}
    for case, fit in fits:
        width, height, shape = case["size"]
        by_size.setdefault((width, height, shape), []).append(fit)
    table = []
    for (width, height, shape), found in sorted(by_size.items(), key=lambda item: item[0][0] * item[0][1]):
        hold = median([f["hold_level"] for f in found])
        swell = median([f["swell"] for f in found])
        mean = gaussian_mean(width, height, sigma, shape=shape)
        table.append({"width": width, "height": height, "shape": shape, "area": width * height, "hold": hold, "swell": swell, "swell_peak": swell / mean, "cut_ms": median([f["cut_ms"] for f in found]), "cases": len(found)})
    measured = [row for row in table if row["cut_ms"] is not None]
    for row in table:
        if row["cut_ms"] is None and measured:
            nearest = min(measured, key=lambda other: abs(math.log(other["area"]) - math.log(row["area"])))
            row["cut_ms"] = nearest["cut_ms"]
            row["cut_from"] = [nearest["width"], nearest["height"]]
    return table


def edge_share(fits):
    flags = [bool(fit.get("at_grid_edge")) for fit in fits if fit]
    return (sum(flags) / len(flags)) if flags else 0.0


def fit(series, profile=None):
    cases = list(presses(series))
    normal = [c for c in cases if c["mode"] == "normal"]
    photo = [c for c in normal if c["backdrop"] == "photo"]
    growth = [g for g in (growth_fit(c) for c in normal) if g]
    release = [r for r in (release_fit(c) for c in normal) if r]
    glows = [(c, g) for c, g in ((c, glow_fit(c)) for c in cases) if g]
    normal_glows = [g for c, g in glows if c["mode"] == "normal"]
    reduce_glows = [g for c, g in glows if c["mode"] == "reduce-motion"]
    sigma = fit_sigma(profile["profile"], profile["hold_level"]) if profile else {"sigma": None}
    per_take = [g for g in growth] + [r for r in release] + [g["rise"] for g in normal_glows if g["rise"]] + [g["fade"] for g in normal_glows if g["fade"]]
    summary = {
        "skipped": skipped(series),
        "held_out": list(HELD_OUT),
        "edge_share": edge_share(per_take),
        "law": fit_growth_law(list(plateaus(series))),
        "growth": {"delay": median([g["delay"] for g in growth]), "response": median([g["response"] for g in growth]), "damping": median([g["damping"] for g in growth]), "cases": len(growth)},
        "release": {"delay": median([r["delay"] for r in release]), "response": median([r["response"] for r in release]), "damping": median([r["damping"] for r in release]), "cases": len(release)},
        "glow": {
            "rise_jump": median([g["rise"]["jump"] for g in normal_glows if g["rise"]]),
            "rise_response": median([g["rise"]["response"] for g in normal_glows if g["rise"]]),
            "rise_damping": median([g["rise"]["damping"] for g in normal_glows if g["rise"]]),
            "hold_ms": median([g["hold_ms"] for g in normal_glows]),
            "fade_response": median([g["fade"]["response"] for g in normal_glows if g["fade"]]),
            "fade_damping": median([g["fade"]["damping"] for g in normal_glows if g["fade"]]),
            "cut_ms": median([g["cut_ms"] for g in normal_glows]),
            "reduce_motion_cut_ms": median([g["cut_ms"] for g in reduce_glows]),
            "reduce_motion_presses": sum(1 for g in reduce_glows if g["cut_ms"] is not None),
            "cut_ms_range": [min(g["cut_ms"] for g in normal_glows if g["cut_ms"]), max(g["cut_ms"] for g in normal_glows if g["cut_ms"])] if normal_glows else None,
            "cases": len(normal_glows),
            "reduce_motion_cases": len(reduce_glows),
        },
        "sigma": sigma,
    }
    if sigma["sigma"]:
        summary["sizes"] = size_table([(c, g) for c, g in glows if c["mode"] == "normal"], sigma["sigma"])
    return summary


def problems(summary):
    found = []
    if summary["law"]["on_edge"]:
        found.append("growth law on its grid edge")
    if not summary["law"].get("within", True):
        found.append(f"no growth law form keeps every measured height within {SIZE_LIMIT} pt")
    for part in ("growth", "release"):
        if summary[part]["response"] is None:
            found.append(f"{part}: no fit")
    glow = summary["glow"]
    for key in ("rise_response", "hold_ms", "fade_response", "cut_ms", "reduce_motion_cut_ms"):
        if glow[key] is None:
            found.append(f"glow {key}: no fit")
    if not summary.get("sizes"):
        found.append("no glow size table")
    if summary.get("edge_share", 0.0) > EDGE_SHARE:
        found.append(f"{summary['edge_share']:.0%} of the per-take spring fits sit on the grid edge (limit {EDGE_SHARE:.0%})")
    if summary["glow"].get("reduce_motion_presses", 0) < REDUCE_MOTION_PRESSES:
        found.append(f"the Reduce Motion cut rests on {summary['glow'].get('reduce_motion_presses', 0)} presses (need {REDUCE_MOTION_PRESSES})")
    if summary["sigma"].get("on_edge"):
        found.append("glow sigma on its grid edge")
    return found


def number(value):
    return f"{float(value)}"


def table_source(summary):
    law, growth, release, glow = summary["law"], summary["growth"], summary["release"], summary["glow"]
    sizes = summary["sizes"]
    lines = [
        f"const double ios27PressGrowthCap = {number(law['cap'])};",
        f"const double ios27PressGrowthAt100 = {number(law['at_100'])};",
        f"const double ios27PressGrowthPower = {number(law['power'])};",
        f"const double ios27PressGrowthWidthPower = {number(law.get('width_power', 0.0))};",
        f"const double ios27PressGrowthDelay = {number(round(growth['delay'], 4))};",
        f"const double ios27PressGrowthResponse = {number(round(growth['response'], 3))};",
        f"const double ios27PressGrowthDamping = {number(round(growth['damping'], 3))};",
        f"const double ios27PressReleaseDelay = {number(round(release['delay'], 4))};",
        f"const double ios27PressReleaseResponse = {number(round(release['response'], 3))};",
        f"const double ios27PressReleaseDamping = {number(round(release['damping'], 3))};",
        f"const double ios27PressGlowRiseJump = {number(round(glow['rise_jump'], 3))};",
        f"const double ios27PressGlowRiseResponse = {number(round(glow['rise_response'], 3))};",
        f"const double ios27PressGlowRiseDamping = {number(round(glow['rise_damping'], 3))};",
        f"const double ios27PressGlowHold = {number(round(glow['hold_ms'] / 1000, 4))};",
        f"const double ios27PressGlowFadeResponse = {number(round(glow['fade_response'], 3))};",
        f"const double ios27PressGlowFadeDamping = {number(round(glow['fade_damping'], 3))};",
        f"const double ios27PressReduceMotionGlowCut = {number(round(glow['reduce_motion_cut_ms'] / 1000, 4))};",
        f"const double ios27PressGlowSigma = {number(summary['sigma']['sigma'])};",
        "",
        "const List<double> ios27PressGlowAreas = [" + ", ".join(number(round(s["area"], 2)) for s in sizes) + "];",
        "const List<double> ios27PressGlowHoldLuma = [" + ", ".join(number(round(s["hold"], 3)) for s in sizes) + "];",
        "const List<double> ios27PressGlowSwellLuma = [" + ", ".join(number(round(s["swell_peak"], 3)) for s in sizes) + "];",
        "const List<double> ios27PressGlowCutSeconds = [" + ", ".join(number(round(s["cut_ms"] / 1000, 4)) for s in sizes) + "];",
    ]
    return "\n".join(lines) + "\n"


def write_table(summary, target=None):
    found = problems(summary)
    target = Path(target or TABLE)
    if found:
        raise SystemExit(f"pressfit --write refused, nothing written to {target}:\n" + "\n".join(f"  - {p}" for p in found))
    target.write_text(table_source(summary))
    return target


def rings(change, width_pt, height_pt, shape, scale):
    height, width = change.shape
    ys, xs = np.mgrid[0:height, 0:width]
    x = (xs + 0.5) / scale - width / scale / 2
    y = (ys + 0.5) / scale - height / scale / 2
    inside = inside_shape(x, y, width_pt, height_pt, shape)
    distance = np.hypot(x, y)
    bins = np.floor(distance).astype(int)
    return [(float(b) + 0.5, float(change[(bins == b) & inside].mean())) for b in range(int(bins.max()) + 1) if ((bins == b) & inside).sum() >= 9]


def median_profile(profiles):
    rings = {}
    for profile in profiles:
        for distance, value in profile["profile"]:
            rings.setdefault(distance, []).append(value)
    count = len(profiles)
    return {
        "takes": [p["take"] for p in profiles],
        "box_pt": profiles[0]["box_pt"],
        "shape": profiles[0]["shape"],
        "profile": [(distance, float(np.median(values))) for distance, values in sorted(rings.items()) if len(values) == count],
        "hold_level": float(np.median([p["hold_level"] for p in profiles])),
    }


def profile_take(runs, key):
    scene, case, run = key.split("/")
    return Path(runs) / run / scene / case / "native"


def glow_profile(take, region, hold_level, shape="capsule"):
    import metrics
    import touch
    import track

    take = Path(take)
    px = track.pixel_rect(region)
    bare = track.crop_px(metrics.load(take / "bare" / "ready.png"), px)
    full = track.crop_px(metrics.load(take / "ready.png"), px)
    left, top, right, bottom = track.box_pixels(full, bare, track.edges(bare))
    frames = track.extract(take / "video.mp4", px, take / "profile")
    down, up = touch.read(take / "video.mp4", take / "marker")[0]
    rest = rest_index(frames.times, down)
    held = min(range(len(frames.times)), key=lambda i: abs(frames.times[i] - (down + up) / 2))
    change = (metrics.luma(frames[held]) - metrics.luma(frames[rest]))[top : bottom + 1, left : right + 1]
    width_pt, height_pt = (right - left + 1) / metrics.SCALE, (bottom - top + 1) / metrics.SCALE
    return {"take": str(take), "box_pt": [width_pt, height_pt], "shape": shape, "profile": rings(change, width_pt, height_pt, shape, metrics.SCALE), "hold_level": float(hold_level)}


def main(argv=None):
    import argparse

    parser = argparse.ArgumentParser(description="Fit the press model (size law, growth and release springs, glow) on native press series.")
    commands = parser.add_subparsers(dest="command", required=True)
    profile = commands.add_parser("profile", help="read the glow's spatial profile from a native Reduce Motion material.interactive take")
    profile.add_argument("keys", nargs="+", help="scene/case/run keys of native Reduce Motion takes in the series")
    profile.add_argument("--series", required=True)
    profile.add_argument("--runs", required=True)
    profile.add_argument("--out", required=True)
    fitting = commands.add_parser("fit", help="fit the model on series written by native_questions.py and a saved profile")
    fitting.add_argument("series", nargs="+")
    fitting.add_argument("--profile", required=True)
    fitting.add_argument("--out")
    fitting.add_argument("--write", action="store_true")
    options = parser.parse_args(argv)
    if options.command == "profile":
        series = json.loads(Path(options.series).read_text())
        found = median_profile([glow_profile(profile_take(options.runs, key), (46, 377, 310, 148), series[key]["steps"]["step1"]["glass"]["glow_drop"]) for key in options.keys])
        Path(options.out).write_text(json.dumps(found, indent=1))
        print(f"median profile of {len(found['takes'])} takes, {len(found['profile'])} rings, written to {options.out}")
        return
    summary = fit(load(options.series), json.loads(Path(options.profile).read_text()))
    text = json.dumps(summary, indent=1)
    if options.out:
        Path(options.out).write_text(text + "\n")
    print(text)
    for problem in problems(summary):
        print("PROBLEM", problem)
    if options.write:
        print(f"written {write_table(summary)}")


if __name__ == "__main__":
    main()
