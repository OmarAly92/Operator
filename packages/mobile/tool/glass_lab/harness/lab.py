import argparse
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import analyze
import build
import manifest
import metrics
import record
import report
import sim

RUNS = build.OUT / "runs"
RUN_NAME = re.compile(r"\d{8}-\d{6}")
NOISE = manifest.LAB / "noise.json"
REPEAT_SCENES = ("material.regular", "tabbar.rest", "tabbar.drag", "menu.bar")
BASELINE_A11Y_SCENES = ("material.regular", "tabbar.rest", "tabbar.drag", "menu.bar", "sheet.detents")


def cmd_build(args):
    udid = sim.device()
    if args.target in ("native", "both"):
        build.native(udid)
    if args.target in ("flutter", "both"):
        build.flutter(udid)
    print(f"built for {udid}")


def cmd_prepare(args):
    udid = sim.device()
    sim.status_bar(udid)
    source = build.backdrops()
    for bundle in (build.NATIVE_BUNDLE, build.FLUTTER_BUNDLE):
        sim.install_backdrops(udid, bundle, source)
    for scene in manifest.load():
        if scene.native_only:
            sim.revoke_location(udid, scene.app)
            if scene.prepare:
                record.prepare_apple(udid, scene, build.OUT / "prepare" / scene.id)
    print(f"prepared {udid}")


def case_name(appearance, backdrop, a11y):
    return f"{appearance}-{backdrop}" + ("" if a11y == "none" else f"-{a11y}")


def run_cases(udid, scenes, apps, appearances, backdrop, a11y, run_dir):
    sim.accessibility(udid, a11y)
    try:
        for scene in scenes:
            backdrops = [backdrop] if backdrop else list(scene.backdrops)
            for appearance in [a for a in scene.appearances if a in appearances]:
                sim.appearance(udid, appearance)
                for chosen in backdrops:
                    case_dir = run_dir / scene.id / case_name(appearance, chosen, a11y)
                    for app in ["native"] if scene.native_only else apps:
                        print(f"{scene.id} {case_dir.name} {app}", flush=True)
                        try:
                            record.capture(udid, scene, app, chosen, case_dir / app)
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
    udid = sim.device()
    scenes = manifest.select(manifest.load(), args.scene)
    run_dir = new_run_dir()
    run_cases(udid, scenes, apps_for(args.app), appearances_for(args.appearance), args.backdrop, args.a11y, run_dir)
    print(run_dir)


def load_noise():
    return json.loads(NOISE.read_text()) if NOISE.exists() else {}


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
        result = analyze.analyze(scene, case_dir, noise.get(scene.id))
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
    run_cases(udid, scenes, ["native", "flutter"], ["light", "dark"], None, "none", run_dir)
    chosen = [s for s in scenes if s.id in BASELINE_A11Y_SCENES]
    for mode in ("reduce-transparency", "increase-contrast", "reduce-motion"):
        run_cases(udid, chosen, ["native", "flutter"], ["dark"], None, mode, run_dir)
    analyze_run(run_dir)
    page, counts, _ = report.build(run_dir, scenes)
    print(page)
    print(json.dumps(counts))


def cmd_repeat(args):
    udid = sim.device()
    names = REPEAT_SCENES if args.scene == "default" else [args.scene]
    scenes = [manifest.select(manifest.load(), name)[0] for name in names]
    run_dir = new_run_dir()
    noise = load_noise()
    failed = []
    for scene in scenes:
        appearance, backdrop = scene.appearances[0], scene.backdrops[0]
        sim.appearance(udid, appearance)
        takes = []
        for number in range(args.times):
            take = run_dir / "takes" / scene.id / str(number)
            print(f"{scene.id} take {number}", flush=True)
            record.capture(udid, scene, "native", backdrop, take)
            takes.append(take)
        worst, static_worst = {}, 0.0
        for i in range(len(takes)):
            for j in range(i + 1, len(takes)):
                case = run_dir / scene.id / f"pair-{i}{j}"
                case.mkdir(parents=True, exist_ok=True)
                for name, source in (("native", takes[i]), ("flutter", takes[j])):
                    link = case / name
                    if not link.exists():
                        link.symlink_to(source)
                result = analyze.analyze(scene, case)
                (case / "result.json").write_text(json.dumps(result))
                for stat in result.get("static", {}).values():
                    static_worst = max(static_worst, stat["mad"])
                if "motion" in result:
                    for name, (value, _) in analyze.motion_measures(result["motion"]).items():
                        worst[name] = max(worst.get(name, 0.0), value)
        noise[scene.id] = worst
        print(f"{scene.id}: static mad {static_worst:.2f}, motion noise {json.dumps({k: round(v, 1) for k, v in worst.items()})}")
        if static_worst > 1.0:
            print(f"{scene.id}: static repeatability FAILED (mad {static_worst:.2f} > 1.0)")
            failed.append(scene.id)
    NOISE.write_text(json.dumps(noise, indent=2, sort_keys=True) + "\n")
    print(NOISE)
    if failed:
        raise SystemExit(f"static repeatability failed for {', '.join(failed)}")


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
    b.add_argument("target", nargs="?", default="both", choices=("native", "flutter", "both"))
    b.set_defaults(func=cmd_build)
    commands.add_parser("prepare").set_defaults(func=cmd_prepare)
    r = commands.add_parser("run")
    r.add_argument("scene")
    r.add_argument("--app", default="both", choices=("native", "flutter", "both"))
    r.add_argument("--appearance", default="both", choices=("light", "dark", "both"))
    r.add_argument("--backdrop", choices=manifest.BACKDROPS)
    r.add_argument("--a11y", default="none", choices=sim.A11Y_MODES)
    r.set_defaults(func=cmd_run)
    p = commands.add_parser("report")
    p.add_argument("run_dir", nargs="?")
    p.set_defaults(func=cmd_report)
    commands.add_parser("baseline").set_defaults(func=cmd_baseline)
    m = commands.add_parser("summary")
    m.add_argument("out")
    m.add_argument("run_dir", nargs="?")
    m.set_defaults(func=cmd_summary)
    t = commands.add_parser("repeat")
    t.add_argument("scene", nargs="?", default="default")
    t.add_argument("--times", type=int, default=3)
    t.set_defaults(func=cmd_repeat)
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
