import os

HARNESS = "cd packages/mobile && python3 -m unittest "
PKG = "cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub "
EXAMPLE = "cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub "
APP = "cd packages/mobile && flutter test --no-pub "
H = "tool/glass_lab/harness/tests/"
M = "packages/mobile/"
P = M + "packages/ios_liquid_glass/"
R = "docs/liquid_glass/02b-motion/research/proto-2b3"
BASE = "c0e69d9a4"
HEAD = os.environ["PROTO_HEAD"]
NO_IMPELLERC = " 2>&1 | grep -v impellerc_verbose_error; exit ${PIPESTATUS[0]}"


def files(*names, root=M):
    return ",".join(root + name for name in names)


TASKS = [
    {
        "n": 1,
        "title": "L4: press measures per touch step, and the capture-hole rule that keeps squeezed frames out of them",
        "files": [
            "Create: `tool/glass_lab/harness/press.py`, `tool/glass_lab/harness/takecheck.py` (the take rule: touch count, scripted durations, capture holes)",
            "Modify: `tool/glass_lab/harness/shapes.py` (a `glow` row over the rest box or a pinned rect, `press.*` in `MOTION_MEASURES`, `compare`, `measures`, `expected`, `limits`), `track.py` (`glow`), `metrics.py` (threshold `ratio` 0.01), `manifest.py` (`press.*`, `pinned`), `reproduce.py` (`glow`)",
            "Test: `tool/glass_lab/harness/tests/test_press.py`",
        ],
        "why": "Rulings 1, 2 and 16. Spec L4 is built first so the lab measures glow and stretch before any package press work. A step with a capture hole anywhere from its touch-down to the next touch (a squeezed first frame, a burst of two short gaps, or frames lost while the glass moves, ruling 16) reads its time measures as NaN: they fail when judged and drop out of every floor (F1, R1).",
        "tests": {"base": BASE, "head": HEAD, "files": files("tool/glass_lab/harness/tests/test_press.py")},
        "impl": {"base": BASE, "head": HEAD, "files": files(*(f"tool/glass_lab/harness/{n}.py" for n in ("press", "takecheck", "shapes", "track", "metrics", "manifest", "reproduce")))},
        "runs": [("harness", HARNESS + f"{H}test_press.py", "FAIL")],
        "red_note": "Expected: `ModuleNotFoundError: No module named 'press'` (the test imports the module the implementation adds).",
        "gates": ["harness"],
        "commit": "feat(glass_lab): L4 press measures per touch step and the capture-hole rule",
    },
    {
        "n": 2,
        "title": "N3, N4 and held-out size scenes, judged on the press measures",
        "files": [
            "Modify: `tool/glass_lab/native/GlassLab/MaterialScenes.swift` (`NeighboursScene`, twelve registry lines)",
            "Modify: `tool/glass_lab/scenes.json` (`material.drag.{fast,out,far,up}`, `material.neighbours.{0,10,40}` with their pinned light rects, `material.press.{circle44,250x150,300x250,120x250,capsule36}`, and the press measures on every press scene)",
            "Test: `tool/glass_lab/harness/tests/test_scenes_2b.py`",
        ],
        "why": "Rulings 3, 4, 8, 17 and 19. The drags reuse `InteractiveScene` (v13's 250 × 88 block); the neighbours are v15's two 120 × 88 glasses in `GlassEffectContainer(spacing: 20)` with v13's content, the left one pressed. The neighbour's region and light rect start 32 pt past its facing edge (law growth plus `spacing`), so the pressed glass and the merge bridge never enter them (F8). The 44 × 44 circle and the 120 × 36 capsule are Operator's sizes; the circle is held out of the fit (F11, F12), and so is the 120 × 250 portrait capsule, which separates width from height (ruling 8); the 250 × 150 and 300 × 250 rects are fitted. The new scenes run on `photo` only (ruling 19).",
        "tests": {"base": BASE, "head": HEAD, "files": files("tool/glass_lab/harness/tests/test_scenes_2b.py")},
        "impl": {"base": BASE, "head": HEAD, "files": files("tool/glass_lab/native/GlassLab/MaterialScenes.swift", "tool/glass_lab/scenes.json")},
        "runs": [("harness", HARNESS + f"{H}test_scenes_2b.py", "FAIL")],
        "red_note": "Expected: the press scene tests fail (`KeyError` for the new scenes, `Tuples differ` for the motion lists).",
        "checks": [
            ("manifest", HARNESS + f"{H}test_manifest.py"),
            ("native", "cd packages/mobile && python3 tool/glass_lab/harness/lab.py build native"),
        ],
        "check_titles": {"manifest": "Check the manifest loads, validates and matches the native registry.", "native": "Build the native lab app."},
        "gates": ["harness"],
        "commit": "feat(glass_lab): N3 drags, N4 neighbours and Operator sizes, judged on the press measures",
    },
    {
        "n": 3,
        "title": "D5 B: `run` and `repeat` check every press take, re-record a holed one, and stop on a floor one take sets",
        "files": [
            "Modify: `tool/glass_lab/harness/lab.py` (`capture_checked`, `record_checked`, `leverage`, `noise-sources.json`), `analyze.py` (the `capture.<app>` gate)",
            "Test: `tool/glass_lab/harness/tests/test_takecheck.py`, `test_lab.py` (the pair-naming test counts folders and reads the sources file)",
        ],
        "why": "Rulings 16 and 18, decisions D3 and D5 (taken). `run` re-records a press take that fails the take check up to twice and keeps the failed ones under `excluded/`; the report gates every press case on its kept takes' checks. `repeat` checks takes already on disk, moves failing ones to `excluded/`, records until enough pass, writes which pair of takes sets every limit, and, on a case with five or more takes, exits non-zero when one take sets a time limit above 3 × the median of the pairs without it, after writing every other case's floor and nothing for that case (R3).",
        "tests": {"base": BASE, "head": HEAD, "files": files("tool/glass_lab/harness/tests/test_takecheck.py", "tool/glass_lab/harness/tests/test_lab.py")},
        "impl": {"base": BASE, "head": HEAD, "files": files("tool/glass_lab/harness/lab.py", "tool/glass_lab/harness/analyze.py")},
        "runs": [("harness", HARNESS + f"{H}test_takecheck.py {H}test_lab.py", "FAIL")],
        "red_note": "Expected: the `lab` tests of `test_takecheck.py` fail (`AttributeError: module 'lab' has no attribute 'capture_checked'`, `record_checked`, `leverage`, `LEVERAGE_TAKES`) and `test_lab.py`'s pair-naming test fails on the missing `noise-sources.json`; the take-rule tests pass, because `takecheck` came with Task 1.",
        "gates": ["harness"],
        "commit": "feat(glass_lab): run and repeat check every press take and stop on a floor one take sets",
    },
    {
        "n": 4,
        "title": "`pressfit`: fit the press model on clean native series and write `ios27_press.dart`",
        "files": [
            "Create: `tool/glass_lab/harness/pressfit.py` (`profile` and `fit` commands)",
            "Test: `tool/glass_lab/harness/tests/test_pressfit.py`",
        ],
        "why": "Rulings 5 to 9. Every press number the package ships comes from this tool. It skips takes that fail the take check or hole their first press for every timing fit, holds the 44 × 44 circle and the 120 × 250 capsule out, fits the size law on the settled growth of every take, holed or not, as a function of height and width, keeps only a form within 1 pt of native at every measured size and chooses among those by leave-one-size-out error, fits the light on every backdrop with the glow width from rings inside the glass, reads the cut per size, and refuses a law or sigma on its grid edge, more than 25 % of per-take spring fits on their grid edge, a Reduce Motion cut from fewer than five presses, or a missing fit.",
        "tests": {"base": BASE, "head": HEAD, "files": files("tool/glass_lab/harness/tests/test_pressfit.py")},
        "impl": {"base": BASE, "head": HEAD, "files": files("tool/glass_lab/harness/pressfit.py")},
        "runs": [("harness", HARNESS + f"{H}test_pressfit.py", "FAIL")],
        "red_note": "Expected: `ModuleNotFoundError: No module named 'pressfit'`.",
        "gates": ["harness"],
        "commit": "feat(glass_lab): pressfit fits the press model and writes ios27_press.dart",
    },
    {
        "n": 5,
        "title": "M7: interactive glass presses like native (scale, light, cut per size, release, Reduce Motion, touches)",
        "files": [
            "Create: `packages/ios_liquid_glass/lib/src/motion/glass_press.dart`, `glass_press_widgets.dart` (with `debugGlassPress`, exported for tests), `ios27_press.dart` (written by `pressfit.py fit --write`)",
            "Modify: `packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart`, `glass_shape_motion.dart` (`contentScale`), `lib/src/liquid_glass.dart` (content scaled about its centre), `lib/src/api/glass_effect.dart` (the press target and light on interactive glass), `lib/ios_liquid_glass.dart` (export)",
            "Test: `packages/ios_liquid_glass/test/motion/glass_press_test.dart`; `glass_group_test.dart`, `glass_union_test.dart`, `render_hooks_test.dart` (their fake motions gain `contentScale`)",
        ],
        "why": "Rulings 3 to 13. The press is the member's own state, sampled on the coordinator's ticker, so no widget rebuilds while glass is pressed. The drawn rect and the content scale together about the centre. The target listens to raw pointer events and hit-tests the glass's shape, so it never enters the gesture arena; the first target to see a pointer down claims it and a hit-test path is dispatched innermost first, so only the innermost interactive glass reacts.",
        "tests": {"base": BASE, "head": HEAD, "files": files("test/motion/glass_press_test.dart", "test/motion/glass_group_test.dart", "test/motion/glass_union_test.dart", "test/motion/render_hooks_test.dart", root=P)},
        "impl": {"base": BASE, "head": HEAD, "files": files("lib/src/motion/glass_press.dart", "lib/src/motion/glass_press_widgets.dart", "lib/src/motion/ios27_press.dart", "lib/src/motion/glass_motion_coordinator.dart", "lib/src/motion/glass_shape_motion.dart", "lib/src/liquid_glass.dart", "lib/src/api/glass_effect.dart", "lib/ios_liquid_glass.dart", root=P)},
        "runs": [("pkg", PKG + "test/motion/glass_press_test.dart test/motion/glass_group_test.dart test/motion/glass_union_test.dart test/motion/render_hooks_test.dart", "FAIL")],
        "red_note": "Expected: a compile failure: the tests import `glass_press.dart`, `glass_press_widgets.dart` and `ios27_press.dart`, which do not exist yet, and the three fakes override a `contentScale` that `GlassShapeMotion` does not declare yet.",
        "checks": [("table", f"cd packages/mobile && python3 tool/glass_lab/harness/pressfit.py fit ../../{R}/native-press-all.json ../../{R}/native-questions-2.json ../../{R}/native-press-300x250.json --profile ../../{R}/glow-profile.json --write > /dev/null && git diff --exit-code -- packages/ios_liquid_glass/lib/src/motion/ios27_press.dart && echo table reproduced by pressfit")],
        "check_titles": {"table": "Check that `pressfit` writes exactly the table the patch added (the table is tool-written, never typed)."},
        "check_notes": {"table": "Expected: `table reproduced by pressfit`. A difference means the table in the patch is not the tool's output: stop and report."},
        "gates": ["package"],
        "commit": "feat(ios_liquid_glass): interactive glass presses like native",
    },
    {
        "n": 6,
        "title": "M8: `LiquidStretch` does nothing under Reduce Motion",
        "files": ["Modify: `packages/ios_liquid_glass/lib/src/stretch.dart`", "Test: `packages/ios_liquid_glass/test/motion/glass_stretch_reduce_motion_test.dart`"],
        "why": "Ruling 10. Spec M8: `GlassGlow` and `LiquidStretch` stop ignoring Reduce Motion. The package's press never uses `LiquidStretch`; the public widget turns itself off under Reduce Motion. `GlassGlow` keeps its glow (native's press light is the same under Reduce Motion).",
        "tests": {"base": BASE, "head": HEAD, "files": files("test/motion/glass_stretch_reduce_motion_test.dart", root=P)},
        "impl": {"base": BASE, "head": HEAD, "files": files("lib/src/stretch.dart", root=P)},
        "runs": [("pkg", PKG + "test/motion/glass_stretch_reduce_motion_test.dart", "FAIL")],
        "red_note": "Expected: the test finds a `RawLiquidStretch` under Reduce Motion.",
        "gates": ["package"],
        "commit": "feat(ios_liquid_glass): LiquidStretch does nothing under Reduce Motion",
    },
    {
        "n": 7,
        "title": "M11: the example's press size, drag and neighbour scenes",
        "files": ["Modify: `packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart` (`_press`, `_neighbours`, seventeen registry lines)"],
        "why": "Spec M11. Each Flutter scene is its native twin's layout with native's tap ids (`glass`, `left`, `right`). The 360 × 200 glass is `GlassShape.rect(32)` where native's is `.rect(cornerRadius: 32)`.",
        "impl": {"base": BASE, "head": HEAD, "files": files("example/lib/lab/scenes/material_scenes.dart", root=P)},
        "impl_title": "Add the scenes.",
        "gates": ["example"],
        "commit": "feat(example): press size, drag and neighbour scenes with native's tap ids",
    },
    {
        "n": 8,
        "title": "M10: `perf.motion` and `perf.slide`",
        "files": ["Modify: `packages/ios_liquid_glass/example/lib/lab/scenes/perf_scenes.dart`"],
        "why": "Ruling 14. `perf.motion` keeps glass animating every frame: press pulses on four interactive glasses (synthetic pointer events every 400 ms), three glasses that materialize and dematerialize, a container whose three glasses merge and split, and a row that slides by a sub-pixel amount every frame (the A9 re-raster). `perf.slide` slides `perf.material`'s whole layout. `perf.material`'s widget tree is unchanged.",
        "impl": {"base": BASE, "head": HEAD, "files": files("example/lib/lab/scenes/perf_scenes.dart", root=P)},
        "impl_title": "Add the scenes.",
        "gates": ["example"],
        "commit": "feat(example): perf.motion and perf.slide",
    },
    {
        "n": 9,
        "title": "F20, for D1: a pressed glass in a row does not reach the fold's step",
        "files": ["Test: `packages/ios_liquid_glass/test/geometry/angle_union_test.dart` (a group of two tests)"],
        "why": "Ruling 18. A pressed 44 pt glass grows ×1.38 into its neighbours, so the Dart mirror of the union is scanned across a row of three 44 pt circles with the middle one at ×1.38, at the app's `spacing` of 20 and the default 8, gaps 8 and 16. The scan is first shown to find the known step of the three-shape cluster. The row is continuous, so D1 stays A. This task adds tests only; they pass on arrival by design.",
        "impl": {"base": BASE, "head": HEAD, "files": files("test/geometry/angle_union_test.dart", root=P)},
        "impl_title": "Add the tests.",
        "checks": [("mirror", PKG + "test/geometry/angle_union_test.dart")],
        "check_titles": {"mirror": "Run them."},
        "gates": ["package"],
        "commit": "test(ios_liquid_glass): a pressed glass in a row keeps the union field continuous",
    },
    {
        "n": 10,
        "title": "D9 (the user's decision, separable): Operator's pressable glass uses the package press",
        "files": [
            "Modify (app): `lib/core/widgets/glass/glass_surface.dart` (`Glass.interactive` when pressable and enabled; `_PressLift`, `pressedScale` and `glowAlpha` removed), `glass_button.dart`",
            "Test (app): `test/core/widgets/glass/glass_button_test.dart` (the behavioural press tests, kept and strengthened)",
        ],
        "why": "Ruling 15 and D9. The user decided on 2026-10-09 to keep the swap in 2B.3, conditional on the 44 × 44 native reference and these tests, and shown to them before merge. **No other task depends on this one**: dropping it leaves every other patch and run unchanged.",
        "tests": {"base": BASE, "head": HEAD, "files": files("test/core/widgets/glass/glass_button_test.dart")},
        "impl": {"base": BASE, "head": HEAD, "files": files("lib/core/widgets/glass/glass_surface.dart", "lib/core/widgets/glass/glass_button.dart")},
        "runs": [("app", APP + "test/core/widgets/glass/glass_button_test.dart" + NO_IMPELLERC, "FAIL")],
        "red_note": "Expected: the press tests fail: the glass is not interactive yet, so no press is read.",
        "gates": ["app"],
        "commit": "feat(mobile): pressable glass uses the package press",
    },
    {
        "n": 11,
        "title": "M9: the README documents the press and Reduce Motion everywhere",
        "files": ["Modify: `packages/ios_liquid_glass/README.md`"],
        "why": "Spec M9. The SwiftUI table's `interactive()` row, a Press section (what was measured, the hit-test behaviour) and the Reduce Motion paragraph. Task 14 corrects its numbers from the refit.",
        "impl": {"base": BASE, "head": HEAD, "files": files("README.md", root=P)},
        "impl_title": "Apply the README.",
        "checks": [("readme", "cd packages/mobile/packages/ios_liquid_glass && grep -c '^### Press' README.md")],
        "check_titles": {"readme": "Check the section is there."},
        "commit": "docs(ios_liquid_glass): README documents the press and Reduce Motion everywhere",
    },
]
