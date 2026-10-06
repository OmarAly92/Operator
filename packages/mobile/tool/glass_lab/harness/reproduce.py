import sys
from dataclasses import replace
from pathlib import Path

sys.path.insert(0, "tool/glass_lab/harness")

import analyze
import manifest
import shapes

REFERENCE = Path("build/glass_lab/reference")
SCENES = {s.id: s for s in manifest.load()}


def capture(case, scene_id, regions):
    scene = replace(SCENES[scene_id], regions=regions, track=tuple(regions), motion=())
    folder = case / "native" if (case / "native").exists() else case
    found = analyze.window(folder)
    return shapes.capture(scene, folder, found[:2])


def materialize():
    for case in ("dark-photo", "dark-stripes", "light-photo", "light-stripes"):
        found = capture(REFERENCE / "LG-20260930-082046/material.materialize" / case, "material.materialize", {"block": [70, 400, 262, 104]})
        events = shapes.summary(found)["events"]
        rows = found["rows"]["block"]["rows"]
        floor = sorted(row["residual"] for row in rows if row["progress"] < 0.05)
        peak = max(row["residual"] for row in rows)
        timing = " ".join(f"{e['shapes']['block']['t10_90_ms']:.0f}ms/{e['shapes']['block']['sharpness_mid']:.2f}" for e in events)
        print(f"materialize {case}: {timing} residual peak {peak:.2f} floor {floor[len(floor) // 2] if floor else float('nan'):.2f}")


def press():
    cases = [
        ("P-20261003-012138/probe.interactive.v13/dark-stripes", "material.interactive", {"glass": [46, 377, 310, 148]}),
        ("P-20261003-012427/probe.interactive.v16/dark-stripes", "material.interactive", {"glass": [142, 392, 118, 118]}),
        ("P-20261003-012517/probe.interactive.v17/dark-stripes", "material.interactive", {"glass": [102, 394, 198, 114]}),
        ("P-20261003-012604/probe.interactive.v18/dark-stripes", "material.interactive", {"glass": [46, 399, 310, 104]}),
    ]
    for run in ("LG-20260930-101816", "LG-20260930-105500", "LG-20261002-160207", "LG-20261002-205855", "GL-20260927-035111", "GL-20260927-022300"):
        for case in ("dark-stripes", "light-stripes"):
            if (REFERENCE / run / "button.press" / case).exists():
                cases.append((f"{run}/button.press/{case}", "button.press", {"glass": [112, 348, 178, 93], "prominent": [94, 461, 214, 93]}))
    for case, scene_id, regions in cases:
        summary = shapes.summary(capture(REFERENCE / case, scene_id, regions))
        for name, shape in summary["shapes"].items():
            rest, peak = shape["rest"], shape["max"]
            print(f"press {case} {name}: {rest['width']} x {rest['height']} -> {peak['width']} x {peak['height']} ({peak['width'] - rest['width']:+.2f} / {peak['height'] - rest['height']:+.2f})")


def menu():
    scene = SCENES["menu.bar"]
    takes = (REFERENCE / "GL-20260927-024701/takes/menu.bar").resolve()
    for i, j in ((0, 1), (0, 2), (1, 2)):
        case = REFERENCE / "menu-pairs" / f"pair-{i}{j}"
        case.mkdir(parents=True, exist_ok=True)
        for name, take in (("native", i), ("flutter", j)):
            if not (case / name).exists():
                (case / name).symlink_to(takes / str(take))
        motion = analyze.analyze(scene, case)["motion"]
        width = motion["events"][0]["width"]
        springs = [width[side] for side in ("native_spring", "flutter_spring")]
        print(f"menu {case.name}: events {motion['event_count']} springs " + " ".join(f"{s['response']:.2f}/{s['damping']:.2f}" for s in springs))


if __name__ == "__main__":
    {"materialize": materialize, "press": press, "menu": menu}[sys.argv[1]]()
