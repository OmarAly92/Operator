import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

import metrics

MEASURES = ("mad", "luminance", "rim_rms", "bbox_pt", "centre_pt")


def frames_equal(a, b):
    if not (a.exists() and b.exists()):
        return None
    return float(np.abs(metrics.load(a) - metrics.load(b)).max())


def worse(old, new, passed_before, passed_after, allowance, flutter_changed):
    if not flutter_changed:
        return False
    return (passed_before and not passed_after) or (not passed_before and new > old + allowance)


def compare(before_run, after_run, noise=None):
    noise = noise or {}
    rows, missing = [], []
    for before_path in sorted(Path(before_run).glob("*/*/result.json")):
        before = json.loads(before_path.read_text())
        if before.get("kind") != "compared":
            continue
        scene, case = before_path.parent.parent.name, before_path.parent.name
        result_path = Path(after_run) / scene / case / "result.json"
        after = json.loads(result_path.read_text()) if result_path.exists() else {}
        if after.get("kind") != "compared":
            missing.append((scene, case))
            continue
        for frame in ("ready", "settled"):
            flutter = frames_equal(before_path.parent / "flutter" / f"{frame}.png", result_path.parent / "flutter" / f"{frame}.png")
            native = frames_equal(before_path.parent / "native" / f"{frame}.png", result_path.parent / "native" / f"{frame}.png")
            for measure in MEASURES:
                old, new = before["static"][frame][measure], after["static"][frame][measure]
                passed_before, passed_after = before["static"][frame]["pass"][measure], after["static"][frame]["pass"][measure]
                changed = flutter is None or flutter > 0
                bad = worse(old, new, passed_before, passed_after, noise.get(measure, 0.0), changed)
                rows.append((scene, case, frame, measure, old, new, passed_before, passed_after, bad, flutter, native))
    return rows, missing


def results(run):
    folder = Path(run)
    if not folder.is_dir():
        raise SystemExit(f"{run}: no such run folder")
    found = sorted(folder.glob("*/*/result.json"))
    if not found:
        raise SystemExit(f"{run}: no scene/case/result.json in this run folder")
    return found


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 2:
        raise SystemExit("usage: still_check.py <2A run> <new run>")
    before_run, after_run = args
    results(before_run)
    results(after_run)
    rows, missing = compare(before_run, after_run)
    bad = [row for row in rows if row[8]]
    triples = {(r[0], r[1], r[2]): (r[9], r[10]) for r in rows}
    if not triples:
        raise SystemExit(f"nothing compared: no case of {before_run} was compared in {after_run} (missing {len(missing)})")
    identical = {key: value for key, value in triples.items() if value[0] == 0.0}
    print(f"{len(triples)} scene, case and frame triples compared; {len(identical)} Flutter frames byte-identical to the 2A run")
    for (scene, case, frame), (_, native) in sorted(identical.items()):
        print(f"identical flutter {scene} {case} {frame}: native frame max difference {native}")
    for scene, case, frame, measure, old, new, passed_before, passed_after, _, flutter, native in rows:
        if old != new or not passed_after:
            print(f"{scene} {case} {frame} {measure}: {old:.2f} -> {new:.2f} ({'pass' if passed_before else 'fail'} -> {'pass' if passed_after else 'fail'}), flutter frame max difference {flutter}, native {native}")
    print(f"missing: {len(missing)}")
    for scene, case in missing:
        print(f"MISSING {scene} {case}")
    print(f"worse: {len(bad)}")
    for row in bad:
        print("WORSE", row[:6])


if __name__ == "__main__":
    main()
