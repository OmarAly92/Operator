### Task 1: L4: press measures per touch step, and the capture-hole rule that keeps squeezed frames out of them

**Files:**
- Create: `tool/glass_lab/harness/press.py`, `tool/glass_lab/harness/takecheck.py` (the take rule: touch count, scripted durations, capture holes)
- Modify: `tool/glass_lab/harness/shapes.py` (a `glow` row over the rest box or a pinned rect, `press.*` in `MOTION_MEASURES`, `compare`, `measures`, `expected`, `limits`), `track.py` (`glow`), `metrics.py` (threshold `ratio` 0.01), `manifest.py` (`press.*`, `pinned`), `reproduce.py` (`glow`)
- Test: `tool/glass_lab/harness/tests/test_press.py`

**Why.** Rulings 1, 2 and 16. Spec L4 is built first so the lab measures glow and stretch before any package press work. A step with a capture hole anywhere from its touch-down to the next touch (a squeezed first frame, a burst of two short gaps, or frames lost while the glass moves, ruling 16) reads its time measures as NaN: they fail when judged and drop out of every floor (F1, R1).

- [ ] **Step 1: Add the failing tests.**

<<PATCH t01-tests from=c0e69d9a4 to=87b88ab02 files=packages/mobile/tool/glass_lab/harness/tests/test_press.py>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t01-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_press.py` => FAIL

<<OUT t01-harness-red>>

Expected: `ModuleNotFoundError: No module named 'press'` (the test imports the module the implementation adds).

- [ ] **Step 3: Apply the implementation.**

<<PATCH t01-impl from=c0e69d9a4 to=87b88ab02 files=packages/mobile/tool/glass_lab/harness/press.py,packages/mobile/tool/glass_lab/harness/takecheck.py,packages/mobile/tool/glass_lab/harness/shapes.py,packages/mobile/tool/glass_lab/harness/track.py,packages/mobile/tool/glass_lab/harness/metrics.py,packages/mobile/tool/glass_lab/harness/manifest.py,packages/mobile/tool/glass_lab/harness/reproduce.py>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t01-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_press.py` => PASS

<<OUT t01-harness-green>>

- [ ] **Step 5: Gate: harness.**

RUN[t01-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t01-gate-harness>>

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): L4 press measures per touch step and the capture-hole rule

Co-Authored-By: <the session's attribution line>"
```

### Task 2: N3, N4 and held-out size scenes, judged on the press measures

**Files:**
- Modify: `tool/glass_lab/native/GlassLab/MaterialScenes.swift` (`NeighboursScene`, twelve registry lines)
- Modify: `tool/glass_lab/scenes.json` (`material.drag.{fast,out,far,up}`, `material.neighbours.{0,10,40}` with their pinned light rects, `material.press.{circle44,250x150,300x250,120x250,capsule36}`, and the press measures on every press scene)
- Test: `tool/glass_lab/harness/tests/test_scenes_2b.py`

**Why.** Rulings 3, 4, 8, 17 and 19. The drags reuse `InteractiveScene` (v13's 250 × 88 block); the neighbours are v15's two 120 × 88 glasses in `GlassEffectContainer(spacing: 20)` with v13's content, the left one pressed. The neighbour's region and light rect start 32 pt past its facing edge (law growth plus `spacing`), so the pressed glass and the merge bridge never enter them (F8). The 44 × 44 circle and the 120 × 36 capsule are Operator's sizes; the circle is held out of the fit (F11, F12), and so is the 120 × 250 portrait capsule, which separates width from height (ruling 8); the 250 × 150 and 300 × 250 rects are fitted. The new scenes run on `photo` only (ruling 19).

- [ ] **Step 1: Add the failing tests.**

<<PATCH t02-tests from=c0e69d9a4 to=87b88ab02 files=packages/mobile/tool/glass_lab/harness/tests/test_scenes_2b.py>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t02-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_scenes_2b.py` => FAIL

<<OUT t02-harness-red>>

Expected: the press scene tests fail (`KeyError` for the new scenes, `Tuples differ` for the motion lists).

- [ ] **Step 3: Apply the implementation.**

<<PATCH t02-impl from=c0e69d9a4 to=87b88ab02 files=packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift,packages/mobile/tool/glass_lab/scenes.json>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t02-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_scenes_2b.py` => PASS

<<OUT t02-harness-green>>

- [ ] **Step 5: Check the manifest loads, validates and matches the native registry.**

RUN[t02-manifest]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_manifest.py` => PASS

<<OUT t02-manifest>>

- [ ] **Step 6: Build the native lab app.**

RUN[t02-native]: `cd packages/mobile && python3 tool/glass_lab/harness/lab.py build native` => PASS

<<OUT t02-native>>

- [ ] **Step 7: Gate: harness.**

RUN[t02-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t02-gate-harness>>

- [ ] **Step 8: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): N3 drags, N4 neighbours and Operator sizes, judged on the press measures

Co-Authored-By: <the session's attribution line>"
```

### Task 3: D5 B: `run` and `repeat` check every press take, re-record a holed one, and stop on a floor one take sets

**Files:**
- Modify: `tool/glass_lab/harness/lab.py` (`capture_checked`, `record_checked`, `leverage`, `noise-sources.json`), `analyze.py` (the `capture.<app>` gate)
- Test: `tool/glass_lab/harness/tests/test_takecheck.py`, `test_lab.py` (the pair-naming test counts folders and reads the sources file)

**Why.** Rulings 16 and 18, decisions D3 and D5 (taken). `run` re-records a press take that fails the take check up to twice and keeps the failed ones under `excluded/`; the report gates every press case on its kept takes' checks. `repeat` checks takes already on disk, moves failing ones to `excluded/`, records until enough pass, writes which pair of takes sets every limit, and, on a case with five or more takes, exits non-zero when one take sets a time limit above 3 × the median of the pairs without it, after writing every other case's floor and nothing for that case (R3).

- [ ] **Step 1: Add the failing tests.**

<<PATCH t03-tests from=c0e69d9a4 to=87b88ab02 files=packages/mobile/tool/glass_lab/harness/tests/test_takecheck.py,packages/mobile/tool/glass_lab/harness/tests/test_lab.py>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t03-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_takecheck.py tool/glass_lab/harness/tests/test_lab.py` => FAIL

<<OUT t03-harness-red>>

Expected: the `lab` tests of `test_takecheck.py` fail (`AttributeError: module 'lab' has no attribute 'capture_checked'`, `record_checked`, `leverage`, `LEVERAGE_TAKES`) and `test_lab.py`'s pair-naming test fails on the missing `noise-sources.json`; the take-rule tests pass, because `takecheck` came with Task 1.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t03-impl from=c0e69d9a4 to=87b88ab02 files=packages/mobile/tool/glass_lab/harness/lab.py,packages/mobile/tool/glass_lab/harness/analyze.py>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t03-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_takecheck.py tool/glass_lab/harness/tests/test_lab.py` => PASS

<<OUT t03-harness-green>>

- [ ] **Step 5: Gate: harness.**

RUN[t03-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t03-gate-harness>>

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): run and repeat check every press take and stop on a floor one take sets

Co-Authored-By: <the session's attribution line>"
```

### Task 4: `pressfit`: fit the press model on clean native series and write `ios27_press.dart`

**Files:**
- Create: `tool/glass_lab/harness/pressfit.py` (`profile` and `fit` commands)
- Test: `tool/glass_lab/harness/tests/test_pressfit.py`

**Why.** Rulings 5 to 9. Every press number the package ships comes from this tool. It skips takes that fail the take check or hole their first press for every timing fit, holds the 44 × 44 circle and the 120 × 250 capsule out, fits the size law on the settled growth of every take, holed or not, as a function of height and width, keeps only a form within 1 pt of native at every measured size and chooses among those by leave-one-size-out error, fits the light on every backdrop with the glow width from rings inside the glass, reads the cut per size, and refuses a law or sigma on its grid edge, more than 25 % of per-take spring fits on their grid edge, a Reduce Motion cut from fewer than five presses, or a missing fit.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t04-tests from=c0e69d9a4 to=87b88ab02 files=packages/mobile/tool/glass_lab/harness/tests/test_pressfit.py>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t04-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_pressfit.py` => FAIL

<<OUT t04-harness-red>>

Expected: `ModuleNotFoundError: No module named 'pressfit'`.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t04-impl from=c0e69d9a4 to=87b88ab02 files=packages/mobile/tool/glass_lab/harness/pressfit.py>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t04-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_pressfit.py` => PASS

<<OUT t04-harness-green>>

- [ ] **Step 5: Gate: harness.**

RUN[t04-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t04-gate-harness>>

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): pressfit fits the press model and writes ios27_press.dart

Co-Authored-By: <the session's attribution line>"
```

### Task 5: M7: interactive glass presses like native (scale, light, cut per size, release, Reduce Motion, touches)

**Files:**
- Create: `packages/ios_liquid_glass/lib/src/motion/glass_press.dart`, `glass_press_widgets.dart` (with `debugGlassPress`, exported for tests), `ios27_press.dart` (written by `pressfit.py fit --write`)
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart`, `glass_shape_motion.dart` (`contentScale`), `lib/src/liquid_glass.dart` (content scaled about its centre), `lib/src/api/glass_effect.dart` (the press target and light on interactive glass), `lib/ios_liquid_glass.dart` (export)
- Test: `packages/ios_liquid_glass/test/motion/glass_press_test.dart`; `glass_group_test.dart`, `glass_union_test.dart`, `render_hooks_test.dart` (their fake motions gain `contentScale`)

**Why.** Rulings 3 to 13. The press is the member's own state, sampled on the coordinator's ticker, so no widget rebuilds while glass is pressed. The drawn rect and the content scale together about the centre. The target listens to raw pointer events and hit-tests the glass's shape, so it never enters the gesture arena; the first target to see a pointer down claims it and a hit-test path is dispatched innermost first, so only the innermost interactive glass reacts.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t05-tests from=c0e69d9a4 to=87b88ab02 files=packages/mobile/packages/ios_liquid_glass/test/motion/glass_press_test.dart,packages/mobile/packages/ios_liquid_glass/test/motion/glass_group_test.dart,packages/mobile/packages/ios_liquid_glass/test/motion/glass_union_test.dart,packages/mobile/packages/ios_liquid_glass/test/motion/render_hooks_test.dart>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t05-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_press_test.dart test/motion/glass_group_test.dart test/motion/glass_union_test.dart test/motion/render_hooks_test.dart` => FAIL

<<OUT t05-pkg-red>>

Expected: a compile failure: the tests import `glass_press.dart`, `glass_press_widgets.dart` and `ios27_press.dart`, which do not exist yet, and the three fakes override a `contentScale` that `GlassShapeMotion` does not declare yet.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t05-impl from=c0e69d9a4 to=87b88ab02 files=packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_press.dart,packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_press_widgets.dart,packages/mobile/packages/ios_liquid_glass/lib/src/motion/ios27_press.dart,packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart,packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart,packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass.dart,packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart,packages/mobile/packages/ios_liquid_glass/lib/ios_liquid_glass.dart>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t05-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_press_test.dart test/motion/glass_group_test.dart test/motion/glass_union_test.dart test/motion/render_hooks_test.dart` => PASS

<<OUT t05-pkg-green>>

- [ ] **Step 5: Check that `pressfit` writes exactly the table the patch added (the table is tool-written, never typed).**

RUN[t05-table]: `cd packages/mobile && python3 tool/glass_lab/harness/pressfit.py fit ../../docs/liquid_glass/02b-motion/research/proto-2b3/native-press-all.json ../../docs/liquid_glass/02b-motion/research/proto-2b3/native-questions-2.json ../../docs/liquid_glass/02b-motion/research/proto-2b3/native-press-300x250.json --profile ../../docs/liquid_glass/02b-motion/research/proto-2b3/glow-profile.json --write > /dev/null && git diff --exit-code -- packages/ios_liquid_glass/lib/src/motion/ios27_press.dart && echo table reproduced by pressfit` => PASS

<<OUT t05-table>>

Expected: `table reproduced by pressfit`. A difference means the table in the patch is not the tool's output: stop and report.

- [ ] **Step 6: Gate: package.**

RUN[t05-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t05-gate-pkg-analyze>>

RUN[t05-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t05-gate-pkg-test>>

- [ ] **Step 7: Commit.**

```bash
git add -A packages
git commit -m "feat(ios_liquid_glass): interactive glass presses like native

Co-Authored-By: <the session's attribution line>"
```

### Task 6: M8: `LiquidStretch` does nothing under Reduce Motion

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/stretch.dart`
- Test: `packages/ios_liquid_glass/test/motion/glass_stretch_reduce_motion_test.dart`

**Why.** Ruling 10. Spec M8: `GlassGlow` and `LiquidStretch` stop ignoring Reduce Motion. The package's press never uses `LiquidStretch`; the public widget turns itself off under Reduce Motion. `GlassGlow` keeps its glow (native's press light is the same under Reduce Motion).

- [ ] **Step 1: Add the failing tests.**

<<PATCH t06-tests from=c0e69d9a4 to=87b88ab02 files=packages/mobile/packages/ios_liquid_glass/test/motion/glass_stretch_reduce_motion_test.dart>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t06-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_stretch_reduce_motion_test.dart` => FAIL

<<OUT t06-pkg-red>>

Expected: the test finds a `RawLiquidStretch` under Reduce Motion.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t06-impl from=c0e69d9a4 to=87b88ab02 files=packages/mobile/packages/ios_liquid_glass/lib/src/stretch.dart>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t06-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_stretch_reduce_motion_test.dart` => PASS

<<OUT t06-pkg-green>>

- [ ] **Step 5: Gate: package.**

RUN[t06-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t06-gate-pkg-analyze>>

RUN[t06-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t06-gate-pkg-test>>

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "feat(ios_liquid_glass): LiquidStretch does nothing under Reduce Motion

Co-Authored-By: <the session's attribution line>"
```

### Task 7: M11: the example's press size, drag and neighbour scenes

**Files:**
- Modify: `packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart` (`_press`, `_neighbours`, seventeen registry lines)

**Why.** Spec M11. Each Flutter scene is its native twin's layout with native's tap ids (`glass`, `left`, `right`). The 360 × 200 glass is `GlassShape.rect(32)` where native's is `.rect(cornerRadius: 32)`.

- [ ] **Step 1: Add the scenes.**

<<PATCH t07-impl from=c0e69d9a4 to=87b88ab02 files=packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart>>

- [ ] **Step 2: Gate: example.**

RUN[t07-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t07-gate-example-analyze>>

RUN[t07-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t07-gate-example-test>>

- [ ] **Step 3: Commit.**

```bash
git add -A packages
git commit -m "feat(example): press size, drag and neighbour scenes with native's tap ids

Co-Authored-By: <the session's attribution line>"
```

### Task 8: M10: `perf.motion` and `perf.slide`

**Files:**
- Modify: `packages/ios_liquid_glass/example/lib/lab/scenes/perf_scenes.dart`

**Why.** Ruling 14. `perf.motion` keeps glass animating every frame: press pulses on four interactive glasses (synthetic pointer events every 400 ms), three glasses that materialize and dematerialize, a container whose three glasses merge and split, and a row that slides by a sub-pixel amount every frame (the A9 re-raster). `perf.slide` slides `perf.material`'s whole layout. `perf.material`'s widget tree is unchanged.

- [ ] **Step 1: Add the scenes.**

<<PATCH t08-impl from=c0e69d9a4 to=87b88ab02 files=packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/perf_scenes.dart>>

- [ ] **Step 2: Gate: example.**

RUN[t08-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t08-gate-example-analyze>>

RUN[t08-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t08-gate-example-test>>

- [ ] **Step 3: Commit.**

```bash
git add -A packages
git commit -m "feat(example): perf.motion and perf.slide

Co-Authored-By: <the session's attribution line>"
```

### Task 9: F20, for D1: a pressed glass in a row does not reach the fold's step

**Files:**
- Test: `packages/ios_liquid_glass/test/geometry/angle_union_test.dart` (a group of two tests)

**Why.** Ruling 18. A pressed 44 pt glass grows ×1.38 into its neighbours, so the Dart mirror of the union is scanned across a row of three 44 pt circles with the middle one at ×1.38, at the app's `spacing` of 20 and the default 8, gaps 8 and 16. The scan is first shown to find the known step of the three-shape cluster. The row is continuous, so D1 stays A. This task adds tests only; they pass on arrival by design.

- [ ] **Step 1: Add the tests.**

<<PATCH t09-impl from=c0e69d9a4 to=87b88ab02 files=packages/mobile/packages/ios_liquid_glass/test/geometry/angle_union_test.dart>>

- [ ] **Step 2: Run them.**

RUN[t09-mirror]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/geometry/angle_union_test.dart` => PASS

<<OUT t09-mirror>>

- [ ] **Step 3: Gate: package.**

RUN[t09-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t09-gate-pkg-analyze>>

RUN[t09-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t09-gate-pkg-test>>

- [ ] **Step 4: Commit.**

```bash
git add -A packages
git commit -m "test(ios_liquid_glass): a pressed glass in a row keeps the union field continuous

Co-Authored-By: <the session's attribution line>"
```

### Task 10: D9 (the user's decision, separable): Operator's pressable glass uses the package press

**Files:**
- Modify (app): `lib/core/widgets/glass/glass_surface.dart` (`Glass.interactive` when pressable and enabled; `_PressLift`, `pressedScale` and `glowAlpha` removed), `glass_button.dart`
- Test (app): `test/core/widgets/glass/glass_button_test.dart` (the behavioural press tests, kept and strengthened)

**Why.** Ruling 15 and D9. The user decided on 2026-10-09 to keep the swap in 2B.3, conditional on the 44 × 44 native reference and these tests, and shown to them before merge. **No other task depends on this one**: dropping it leaves every other patch and run unchanged.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t10-tests from=c0e69d9a4 to=87b88ab02 files=packages/mobile/test/core/widgets/glass/glass_button_test.dart>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t10-app-red]: `cd packages/mobile && flutter test --no-pub test/core/widgets/glass/glass_button_test.dart 2>&1 | grep -v impellerc_verbose_error; exit ${PIPESTATUS[0]}` => FAIL

<<OUT t10-app-red>>

Expected: the press tests fail: the glass is not interactive yet, so no press is read.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t10-impl from=c0e69d9a4 to=87b88ab02 files=packages/mobile/lib/core/widgets/glass/glass_surface.dart,packages/mobile/lib/core/widgets/glass/glass_button.dart>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t10-app-green]: `cd packages/mobile && flutter test --no-pub test/core/widgets/glass/glass_button_test.dart 2>&1 | grep -v impellerc_verbose_error; exit ${PIPESTATUS[0]}` => PASS

<<OUT t10-app-green>>

- [ ] **Step 5: Gate: app.**

RUN[t10-gate-app-analyze]: `cd packages/mobile && flutter analyze --no-pub` => PASS

<<OUT t10-gate-app-analyze>>

RUN[t10-gate-app-test]: `cd packages/mobile && flutter test --no-pub` => PASS

<<OUT t10-gate-app-test>>

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "feat(mobile): pressable glass uses the package press

Co-Authored-By: <the session's attribution line>"
```

### Task 11: M9: the README documents the press and Reduce Motion everywhere

**Files:**
- Modify: `packages/ios_liquid_glass/README.md`

**Why.** Spec M9. The SwiftUI table's `interactive()` row, a Press section (what was measured, the hit-test behaviour) and the Reduce Motion paragraph. Task 14 corrects its numbers from the refit.

- [ ] **Step 1: Apply the README.**

<<PATCH t11-impl from=c0e69d9a4 to=87b88ab02 files=packages/mobile/packages/ios_liquid_glass/README.md>>

- [ ] **Step 2: Check the section is there.**

RUN[t11-readme]: `cd packages/mobile/packages/ios_liquid_glass && grep -c '^### Press' README.md` => PASS

<<OUT t11-readme>>

- [ ] **Step 3: Commit.**

```bash
git add -A packages
git commit -m "docs(ios_liquid_glass): README documents the press and Reduce Motion everywhere

Co-Authored-By: <the session's attribution line>"
```
