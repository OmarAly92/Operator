import argparse
import hashlib
import json
import math
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import analyze
import build
import fitvis
import flip
import manifest
import metrics
import probe
import record
import report
import shapes
import sim
import tonefit
import tune

RUNS = build.OUT / "runs"
RUN_NAME = re.compile(r"\d{8}-\d{6}")
NOISE = manifest.LAB / "noise.json"
REPEAT_SCENES = ("material.regular", "tabbar.rest", "tabbar.drag", "menu.bar")
BASELINE_A11Y_SCENES = ("material.regular", "tabbar.rest", "tabbar.drag", "menu.bar", "sheet.detents")


def cmd_build(args):
    udid = sim.device()
    if args.target in ("native", "all"):
        build.native(udid)
    if args.target in ("example", "all"):
        build.example(udid)
    if args.target in ("operator", "all"):
        build.flutter(udid)
    print(f"built for {udid}")


def cmd_prepare(args):
    udid = sim.device()
    sim.status_bar(udid)
    source = build.backdrops()
    for bundle in (build.NATIVE_BUNDLE, *build.FLUTTER_TARGETS.values()):
        sim.install_backdrops(udid, bundle, source)
    for scene in manifest.load():
        if scene.native_only:
            sim.revoke_location(udid, scene.app)
            if scene.prepare:
                record.prepare_apple(udid, scene, build.OUT / "prepare" / scene.id)
    print(f"prepared {udid}")


def case_name(appearance, backdrop, a11y):
    return f"{appearance}-{backdrop}" + ("" if a11y == "none" else f"-{a11y}")


def run_cases(udid, scenes, apps, appearances, backdrop, a11y, run_dir, flutter_target="example"):
    try:
        sim.accessibility(udid, a11y)
        for scene in scenes:
            backdrops = [backdrop] if backdrop else list(scene.backdrops)
            for appearance in [a for a in scene.appearances if a in appearances]:
                sim.appearance(udid, appearance)
                for chosen in backdrops:
                    case_dir = run_dir / scene.id / case_name(appearance, chosen, a11y)
                    for app in ["native"] if scene.native_only else apps:
                        print(f"{scene.id} {case_dir.name} {app}", flush=True)
                        try:
                            record.capture(udid, scene, app, chosen, case_dir / app, flutter_target)
                        except Exception as error:
                            (case_dir / app).mkdir(parents=True, exist_ok=True)
                            (case_dir / app / "error.txt").write_text(str(error))
                            print(f"  failed: {error}", flush=True)
    finally:
        sim.accessibility(udid, "none")


def new_run_dir():
    run_dir = RUNS / time.strftime("%Y%m%d-%H%M%S")
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir


def apps_for(value):
    return ["native", "flutter"] if value == "both" else [value]


def appearances_for(value):
    return ["light", "dark"] if value == "both" else [value]


def cmd_run(args):
    scenes = manifest.select(manifest.load(), args.scene)
    if "flutter" in apps_for(args.app) and any(not scene.native_only for scene in scenes):
        build.require_fresh(args.flutter)
    if "native" in apps_for(args.app) or any(scene.native_only for scene in scenes):
        build.require_fresh("native")
    udid = sim.device()
    run_dir = new_run_dir()
    (run_dir / "run.json").write_text(json.dumps({"flutter": args.flutter, "a11y": args.a11y}))
    run_cases(udid, scenes, apps_for(args.app), appearances_for(args.appearance), args.backdrop, args.a11y, run_dir, args.flutter)
    print(run_dir)


def load_noise():
    return json.loads(NOISE.read_text()) if NOISE.exists() else {}


def noise_for(noise, scene_id, case):
    entry = noise.get(scene_id) or {}
    if entry and all(isinstance(value, dict) for value in entry.values()):
        return entry.get(case, {})
    return entry


def analyze_run(run_dir):
    scenes = {s.id: s for s in manifest.load()}
    noise = load_noise()
    for case_dir in sorted(Path(run_dir).glob("*/*")):
        scene = scenes.get(case_dir.parent.name)
        if scene is None or not case_dir.is_dir():
            continue
        if any((case_dir / app / "error.txt").exists() for app in ("native", "flutter")):
            (case_dir / "result.json").write_text(json.dumps({"scene": scene.id, "case": case_dir.name, "kind": "error"}))
            continue
        result = analyze.analyze(scene, case_dir, noise_for(noise, scene.id, case_dir.name))
        (case_dir / "result.json").write_text(json.dumps(result))


def latest_run():
    runs = sorted(p for p in RUNS.glob("*") if p.is_dir() and RUN_NAME.fullmatch(p.name))
    if not runs:
        raise SystemExit("no runs yet")
    return runs[-1]


def cmd_report(args):
    run_dir = Path(args.run_dir) if args.run_dir else latest_run()
    analyze_run(run_dir)
    page, counts, _ = report.build(run_dir, manifest.load())
    print(page)
    print(json.dumps(counts))


def cmd_summary(args):
    run_dir = Path(args.run_dir) if args.run_dir else latest_run()
    _, counts, results = report.build(run_dir, manifest.load())
    Path(args.out).write_text(report.markdown(run_dir, counts, results, manifest.load()))
    print(args.out)


def cmd_baseline(args):
    cmd_prepare(args)
    udid = sim.device()
    run_dir = new_run_dir()
    scenes = manifest.load()
    run_cases(udid, scenes, ["native", "flutter"], ["light", "dark"], None, "none", run_dir, args.flutter)
    chosen = [s for s in scenes if s.id in BASELINE_A11Y_SCENES]
    for mode in ("reduce-transparency", "increase-contrast", "reduce-motion"):
        run_cases(udid, chosen, ["native", "flutter"], ["dark"], None, mode, run_dir, args.flutter)
    analyze_run(run_dir)
    page, counts, _ = report.build(run_dir, scenes)
    print(page)
    print(json.dumps(counts))


def repeat_cases(scene, appearance=None, backdrop=None):
    appearances = [a for a in scene.appearances if appearance in (None, "both", a)]
    backdrops = [b for b in scene.backdrops if backdrop in (None, b)]
    return [(a, b) for a in appearances for b in backdrops]


def take_numbers(folder):
    return sorted(int(p.name) for p in Path(folder).glob("*") if p.is_dir() and p.name.isdigit())


def canonical_takes(takes):
    def key(take):
        timing = Path(take) / "timing.json"
        start = json.loads(timing.read_text()).get("start") if timing.exists() else None
        video = Path(take) / "video.mp4"
        content = hashlib.sha256(video.read_bytes()).hexdigest() if video.exists() else ""
        return (start is None, start or 0.0, content)
    return sorted(takes, key=key)


def case_noise(scene, takes, case_root):
    worst, static_worst, cache = {}, 0.0, {}
    takes = canonical_takes(takes)
    for i in range(len(takes)):
        for j in range(i + 1, len(takes)):
            case = case_root / f"pair-{takes[i].name}-{takes[j].name}"
            case.mkdir(parents=True, exist_ok=True)
            for name, source in (("native", takes[i]), ("flutter", takes[j])):
                link = case / name
                if link.is_symlink() and (not link.exists() or link.resolve() != source.resolve()):
                    link.unlink()
                if not link.exists():
                    link.symlink_to(source.resolve())
            result = analyze.analyze(scene, case, cache=cache)
            (case / "result.json").write_text(json.dumps(result))
            for stat in result.get("static", {}).values():
                static_worst = max(static_worst, stat["mad"])
            found = shapes.measures(result["shapes"]) if "shapes" in result else {
                name: value for name, (value, _) in analyze.motion_measures(result.get("motion", {"events": []})).items()
            }
            found.update({name: value for name, (value, _, _) in result.get("measures", {}).items() if not name.startswith("motion.")})
            for name, value in found.items():
                if math.isfinite(value):
                    worst[name] = max(worst.get(name, 0.0), value)
    return worst, static_worst


def cmd_repeat(args):
    build.require_fresh("native")
    udid = sim.device()
    names = REPEAT_SCENES if args.scene == "default" else [args.scene]
    scenes = [manifest.select(manifest.load(), name)[0] for name in names]
    run_dir = Path(args.into) if args.into else new_run_dir()
    noise = load_noise()
    failed = []
    try:
        sim.accessibility(udid, args.a11y)
        for scene in scenes:
            entry = noise.get(scene.id, {})
            if entry and not all(isinstance(value, dict) for value in entry.values()):
                entry = {}
            for appearance, backdrop in repeat_cases(scene, args.appearance, args.backdrop):
                sim.appearance(udid, appearance)
                name = case_name(appearance, backdrop, args.a11y)
                folder = run_dir / "takes" / scene.id / name
                start = (take_numbers(folder) or [-1])[-1] + 1
                for number in range(start, start + args.times):
                    print(f"{scene.id} {name} take {number}", flush=True)
                    record.capture(udid, scene, "native", backdrop, folder / str(number))
                takes = [folder / str(n) for n in take_numbers(folder)]
                worst, static_worst = case_noise(scene, takes, run_dir / scene.id / name)
                entry[name] = worst
                print(f"{scene.id} {name}: {len(takes)} takes, static mad {static_worst:.2f}, motion noise {json.dumps({k: round(v, 1) for k, v in worst.items()})}")
                if static_worst > 1.0:
                    print(f"{scene.id} {name}: static repeatability FAILED (mad {static_worst:.2f} > 1.0)")
                    failed.append(f"{scene.id} {name}")
            noise[scene.id] = entry
    finally:
        sim.accessibility(udid, "none")
    NOISE.write_text(json.dumps(noise, indent=2, sort_keys=True) + "\n")
    print(NOISE)
    print(run_dir)
    if failed:
        raise SystemExit(f"static repeatability failed for {', '.join(failed)}")


def cmd_reboot(args):
    udid = sim.reboot()
    sim.status_bar(udid)
    print(f"rebooted {udid}")


def cmd_measure(args):
    scene = manifest.select(manifest.load(), args.scene)[0]
    case = Path(args.case_dir)
    apps = [case / name for name in ("native", "flutter") if (case / name / "video.mp4").exists()] or [case]
    summary = {}
    for app_dir in apps:
        found = analyze.window(app_dir)
        capture = shapes.capture(scene, app_dir, found[:2] if found else None)
        summary[app_dir.name] = shapes.summary(capture)
    print(json.dumps(summary, indent=2))


def cmd_fitvis(args):
    udid = sim.device()
    out = Path(args.out) if args.out else build.OUT / "fitvis" / time.strftime("%Y%m%d-%H%M%S")
    ramps = tuple(float(r) for r in args.ramps.split(","))
    summary = fitvis.run(udid, [Path(r) for r in args.runs], out, args.levels, args.write, ramps, args.gain_mode, tuple(args.allow_case_edge))
    print(json.dumps({k: v for k, v in summary.items() if k in ("gain_mode", "mapping", "default_spring_check", "blur_ramp", "visibility_for_progress", "visibility_above_full", "overrides", "write")}, indent=2))
    print(out)


A11Y_ROWS = {"reduce-transparency": "reduceTransparency", "increase-contrast": "increaseContrast"}


def tune_row(a11y, row):
    expected = A11Y_ROWS.get(a11y)
    if row is None:
        return expected or "regular"
    if expected != row and (expected or row in A11Y_ROWS.values()):
        raise SystemExit(f"--a11y {a11y} renders the {expected or 'plain'} row, not --row {row}")
    return row


def cmd_tune(args):
    row = tune_row(args.a11y, args.row)
    udid = sim.device()
    scene = manifest.select(manifest.load(), args.scene)[0]
    out = build.OUT / "tune" / time.strftime("%Y%m%d-%H%M%S")
    try:
        sim.accessibility(udid, args.a11y)
        summary = tune.run(
            udid, scene, args.appearance, args.backdrops.split(","), tune.parse_params(args.params),
            row, args.size, args.flutter, out, write=args.write, max_passes=args.passes,
            regions=args.region.split(",") if args.region else (), pad=args.pad,
        )
    finally:
        sim.accessibility(udid, "none")
    print(json.dumps(summary, indent=2))
    print(out)


def cmd_tonefit(args):
    scene = manifest.select(manifest.load(), args.scene)[0]
    print(json.dumps(tonefit.run_fit(args.run_dir, scene, args.a11y), indent=2))


def cmd_flip(args):
    run_dir = Path(args.run_dir) if args.run_dir else latest_run()
    text = flip.report(run_dir, args.regular)
    print(text)
    if args.out:
        Path(args.out).write_text(text)


def cmd_perf(args):
    build.require_fresh(args.flutter)
    udid = sim.device()
    sim.appearance(udid, args.appearance)
    try:
        sim.accessibility(udid, args.a11y)
        summary = probe.perf(udid, build.FLUTTER_TARGETS[args.flutter], args.takes, tuple(args.scenes.split(",")))
    finally:
        sim.accessibility(udid, "none")
    text = json.dumps(summary, indent=2)
    print(text)
    if args.out:
        Path(args.out).write_text(text + "\n")


def cmd_a11y(args):
    udid = sim.device()
    results = probe.accessibility_check(udid, build.FLUTTER_TARGETS[args.flutter])
    print(json.dumps(results, indent=2))
    failed = [mode for mode, result in results.items() if not result["live"]]
    if failed:
        raise SystemExit(f"not delivered live: {', '.join(failed)}")


def cmd_geometry(args):
    udid = sim.device()
    scene = manifest.select(manifest.load(), args.scene)[0]
    out = build.OUT / "geometry" / scene.id
    sim.appearance(udid, args.appearance)
    backdrop = args.backdrop or scene.backdrops[0]
    record.drive(udid, build.NATIVE_BUNDLE, scene.id, [], backdrop, True, out / "bare", settle=1.0)
    record.drive(udid, build.NATIVE_BUNDLE, scene.id, [], backdrop, False, out / "scene", settle=1.5)
    boxes = metrics.glass_boxes(metrics.load(out / "scene" / "ready.png"), metrics.load(out / "bare" / "ready.png"))
    for box in boxes:
        print(json.dumps({"x": box[0], "y": box[1], "width": box[2], "height": box[3]}))


def parser():
    root = argparse.ArgumentParser(prog="lab.py")
    commands = root.add_subparsers(dest="command", required=True)
    b = commands.add_parser("build")
    b.add_argument("target", nargs="?", default="all", choices=("native", "example", "operator", "all"))
    b.set_defaults(func=cmd_build)
    commands.add_parser("prepare").set_defaults(func=cmd_prepare)
    r = commands.add_parser("run")
    r.add_argument("scene")
    r.add_argument("--app", default="both", choices=("native", "flutter", "both"))
    r.add_argument("--appearance", default="both", choices=("light", "dark", "both"))
    r.add_argument("--backdrop", choices=manifest.BACKDROPS)
    r.add_argument("--a11y", default="none", choices=sim.A11Y_MODES)
    r.add_argument("--flutter", default="example", choices=tuple(build.FLUTTER_TARGETS))
    r.set_defaults(func=cmd_run)
    p = commands.add_parser("report")
    p.add_argument("run_dir", nargs="?")
    p.set_defaults(func=cmd_report)
    bl = commands.add_parser("baseline")
    bl.add_argument("--flutter", default="example", choices=tuple(build.FLUTTER_TARGETS))
    bl.set_defaults(func=cmd_baseline)
    m = commands.add_parser("summary")
    m.add_argument("out")
    m.add_argument("run_dir", nargs="?")
    m.set_defaults(func=cmd_summary)
    t = commands.add_parser("repeat")
    t.add_argument("scene", nargs="?", default="default")
    t.add_argument("--times", type=int, default=3)
    t.add_argument("--appearance", choices=("light", "dark", "both"))
    t.add_argument("--backdrop", choices=manifest.BACKDROPS)
    t.add_argument("--a11y", default="none", choices=sim.A11Y_MODES)
    t.add_argument("--into")
    t.set_defaults(func=cmd_repeat)
    commands.add_parser("reboot").set_defaults(func=cmd_reboot)
    e = commands.add_parser("measure")
    e.add_argument("case_dir")
    e.add_argument("--scene", required=True)
    e.set_defaults(func=cmd_measure)
    v = commands.add_parser("fitvis")
    v.add_argument("runs", nargs="+")
    v.add_argument("--levels", type=int, default=fitvis.LEVELS)
    v.add_argument("--ramps", default=",".join(str(r) for r in fitvis.RAMPS))
    v.add_argument("--out")
    v.add_argument("--write", action="store_true")
    v.add_argument("--gain-mode", default="pooled", choices=fitvis.GAIN_MODES)
    v.add_argument("--allow-case-edge", action="append", default=[], metavar="SCENE/KIND/CASE")
    v.set_defaults(func=cmd_fitvis)
    u = commands.add_parser("tune")
    u.add_argument("--scene", required=True)
    u.add_argument("--appearance", required=True, choices=("light", "dark"))
    u.add_argument("--backdrops", required=True)
    u.add_argument("--params", required=True)
    u.add_argument("--row", choices=("regular", "clear", "tinted", "reduceTransparency", "increaseContrast"))
    u.add_argument("--size", type=int, default=88, choices=(44, 88, 200))
    u.add_argument("--region")
    u.add_argument("--pad", type=int, default=tune.PAD)
    u.add_argument("--a11y", default="none", choices=sim.A11Y_MODES)
    u.add_argument("--flutter", default="example", choices=("example",))
    u.add_argument("--passes", type=int, default=4)
    u.add_argument("--write", action="store_true")
    u.set_defaults(func=cmd_tune)
    o = commands.add_parser("tonefit")
    o.add_argument("run_dir")
    o.add_argument("--scene", default="material.regular")
    o.add_argument("--a11y", default="none", choices=sim.A11Y_MODES)
    o.set_defaults(func=cmd_tonefit)
    l = commands.add_parser("flip")
    l.add_argument("run_dir", nargs="?")
    l.add_argument("--regular")
    l.add_argument("--out")
    l.set_defaults(func=cmd_flip)
    f = commands.add_parser("perf")
    f.add_argument("--flutter", default="example", choices=tuple(build.FLUTTER_TARGETS))
    f.add_argument("--appearance", default="dark", choices=("light", "dark"))
    f.add_argument("--takes", type=int, default=3)
    f.add_argument("--scenes", default=",".join(probe.PERF_SCENES))
    f.add_argument("--a11y", default="none", choices=sim.A11Y_MODES)
    f.add_argument("--out")
    f.set_defaults(func=cmd_perf)
    y = commands.add_parser("a11y")
    y.add_argument("--flutter", default="example", choices=tuple(build.FLUTTER_TARGETS))
    y.set_defaults(func=cmd_a11y)
    g = commands.add_parser("geometry")
    g.add_argument("scene")
    g.add_argument("--appearance", default="dark", choices=("light", "dark"))
    g.add_argument("--backdrop", choices=manifest.BACKDROPS)
    g.set_defaults(func=cmd_geometry)
    return root


def main(argv=None):
    args = parser().parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
