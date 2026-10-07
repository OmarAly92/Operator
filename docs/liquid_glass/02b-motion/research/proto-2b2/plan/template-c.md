### Task 1: Topology that agrees at zero, necks only on one component, a manifest that rejects topology without regions

**Files:**
- Modify: `tool/glass_lab/harness/shapes.py`, `track.py`, `manifest.py`
- Test: `tool/glass_lab/harness/tests/test_shapes.py`, `test_track.py`, `test_manifest.py`

**Why.** Ruling 1. 2B.2's join, split and neck measures read these functions; fixed first so nothing later is judged on a defect.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t01-tests from=4db49edc3 to=fb0207573 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t01-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_manifest.py` => FAIL

<<OUT t01-harness-red>>

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t01-impl from=4db49edc3 to=fb0207573 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t01-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_manifest.py` => PASS

<<OUT t01-harness-green>>

- [ ] **Step 5: Gate: harness.**

RUN[t01-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t01-gate-harness>>

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "fix(glass_lab): topology reads agreeing apps as zero, no neck without one joined component, manifest rejects topology measures without regions

Co-Authored-By: <the session's attribution line>"
```

### Task 2: N7 finer gap series and spacing probes (scenes and native controls)

**Files:**
- Modify: `tool/glass_lab/scenes.json` (the `material.spacing.*` scenes 4, 6, 8, 10, 12, 16, 20 and the finer series `default.d`, `20.b`, `20.c`, `40.d`, `40.e`, `80.a`–`80.e`)
- Modify: `tool/glass_lab/native/GlassLab/MaterialScenes.swift` (the matching native scenes)

**Why.** Ruling 7. Native merge reach is read from these scenes; the 2B.1 N7 set (`default.a`–`c`, `40.a`–`c`) could not pin it. The Swift is compiled in Task 7's gate.

- [ ] **Step 1: Apply the implementation.**

<<PATCH t02-impl from=fb0207573 to=54cfd52d5 files=@impl>>

- [ ] **Step 2: Check the manifest still loads and validates every scene.**

RUN[t02-manifest]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_manifest.py` => PASS

<<OUT t02-manifest>>

- [ ] **Step 3: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): N7 finer gap series and spacing probes for native merge reach

Co-Authored-By: <the session's attribution line>"
```

### Task 3: Gotcha 52: the 2B.1 floors without the take that set a limit, recorded again in this checkout

**Files:**
- Modify: `tool/glass_lab/noise.json` (written by `lab.py repeat`; no patch: execution makes it from its own takes)

**Why.** Ruling 5. 2B.1's `noise.json` holds `cy.peak_ms` 150 for `material.materialize` light-photo-reduce-motion because one of its five takes (take 2) reads its disappear onset 98 ms early. The prototype fixed that in its own, untracked copy of `noise-2b1`; that copy does not travel. This task does the same in the executor's copy by the same moves, records the replacement take after a fresh boot, and lets `repeat` write `noise.json` from the executor's own takes. The prototype's result (`R/gotcha52-moved.json`) is the expectation, not a patch. **The archive's pair-folder links are all dangling:** every one of its 1206 `pair-*/native|flutter` links names `/Users/omaraly/development/AI/Operator-2b1/packages/mobile/build/glass_lab/runs/noise-2b1/...`, a worktree that no longer exists, and this task runs with `development`'s `lab.py`, whose `case_noise` raises `FileExistsError` on a link that exists but points nowhere (Task 9 repairs that later). So the copy is relinked by script before `repeat` runs; the prototype did the same by hand (`excluded/relinks-2b2.json` records old and new targets). Task 9 stays where it is.

- [ ] **Step 1: Copy the archive's `noise-2b1` (never move or write the archive), after checking the disk.** The archive (`/Users/omaraly/development/AI/glass-lab-runs/2b1/runs/noise-2b1`) is only ever read and copied: nothing in this plan moves, deletes or records into it, and every later step in this task works on the copy. The copy is about 8.6 GB on disk (13 GB with caches counted differently by Finder); `repeat` adds one take's frame caches and the analysis of the case's pairs, under 1 GB.

```bash
cd /Users/omaraly/development/AI/Operator-2b2/packages/mobile
R=/Users/omaraly/development/AI/Operator-2b2/docs/liquid_glass/02b-motion/research/proto-2b2
NOISE=$PWD/build/glass_lab/runs/noise-2b1
CASE=material.materialize/light-photo-reduce-motion
df -h /Users/omaraly
test ! -e $NOISE && mkdir -p build/glass_lab/runs && cp -R /Users/omaraly/development/AI/glass-lab-runs/2b1/runs/noise-2b1 build/glass_lab/runs/
test -d $NOISE && test ! -L $NOISE && echo "copy, not a link"
find $NOISE -type l ! -exec test -e {} \; -print | wc -l
df -h /Users/omaraly
```

Expected: `copy, not a link`, then `1206` (every pair link in the copy is dangling; they name the removed `Operator-2b1` worktree), and about 8.6 GB less free space. **Stop under 40 GB free before the copy and report** (the user decides what to clear; do not delete anything to make room). If `$NOISE` exists already, check `test ! -L $NOISE` and use it only if it is a real directory.

- [ ] **Step 2: Take 2 out of the floors, by these moves.** `$NOISE` is the executor's copy of the archive's `noise-2b1` (Step 1); the moves are exactly the prototype's.

```bash
cd /Users/omaraly/development/AI/Operator-2b2/packages/mobile
R=/Users/omaraly/development/AI/Operator-2b2/docs/liquid_glass/02b-motion/research/proto-2b2
NOISE=$PWD/build/glass_lab/runs/noise-2b1
CASE=material.materialize/light-photo-reduce-motion
mkdir -p $NOISE/excluded/takes/$CASE $NOISE/excluded/$CASE
mv $NOISE/takes/$CASE/2 $NOISE/excluded/takes/$CASE/2
for pair in pair-0-2 pair-1-2 pair-3-2 pair-4-2; do mv $NOISE/$CASE/$pair $NOISE/excluded/$CASE/$pair; done
mkdir -p $NOISE/excluded/stale-pairs/material.materialize/light-stripes $NOISE/excluded/stale-pairs/material.materialize.bouncy/dark-stripes-reduce-motion $NOISE/excluded/stale-pairs/material.materialize.bouncy/dark-photo-reduce-motion
mv $NOISE/material.materialize/light-stripes/pair-4-5 $NOISE/excluded/stale-pairs/material.materialize/light-stripes/pair-4-5
mv $NOISE/material.materialize.bouncy/dark-stripes-reduce-motion/pair-4-5 $NOISE/excluded/stale-pairs/material.materialize.bouncy/dark-stripes-reduce-motion/pair-4-5
mv $NOISE/material.materialize.bouncy/dark-photo-reduce-motion/pair-4-5 $NOISE/excluded/stale-pairs/material.materialize.bouncy/dark-photo-reduce-motion/pair-4-5
printf '%s\n' "takes/$CASE/2 (session 2): its disappear onset is read 98 ms before the glass moves (its first changed frame and the next, 53 ms later, both at progress 0.981), so it alone set the case's disappear response_pct, settle_ms and damping limits (ROADMAP gotcha 52). Moved here with the four pair folders that used it; replaced by a take recorded after a fresh boot." "The three pair-4-5 folders under stale-pairs named a take 5 that 2B.1 deleted with its excluded takes; their links point nowhere." > $NOISE/excluded/README.txt
test ! -e $NOISE/takes/$CASE/2 && ls $NOISE/takes/$CASE
```

Expected: `ls` lists `0 1 3 4`. (Take 2 is absent; the next take number `repeat` appends is 5.)

- [ ] **Step 3: Point the copy's pair links at the copy.** The links that remain in the copy all name the removed `Operator-2b1` worktree (Step 1); the three stale `pair-4-5` folders and the four `pair-*-2` folders of the case, whose links named takes that no longer exist, were moved out by Step 2, so every remaining link has a take of the same number in the copy. `relink_noise.py` rewrites each of them to the same take inside `$NOISE`, refuses the archive and a link-not-copy, stops if any target is missing from the copy, and records old and new targets in `$NOISE/excluded/relinks-2b2.json`:

```bash
python3 $R/relink_noise.py $NOISE
find $NOISE -type l ! -exec test -e {} \; -print | wc -l
```

Expected: `relinked 1192 links` (1206 less the 14 in the seven folders Step 2 moved) and then `0` dangling links. A `MISSING` line stops the task: report it. Without this step `repeat` would record take 5 and then raise `FileExistsError` in `case_noise` on the first pair folder (`pair-0-1`) before it writes `noise.json`, and the rerun would record take 6.

- [ ] **Step 4: Build, reboot, check the press, record the replacement take.** The replacement is recorded in this task; nothing is copied from the prototype's `build/` folder (it is untracked and goes with the prototype worktree). One case only, so the flags name it:

```bash
python3 tool/glass_lab/harness/lab.py build native
python3 -c "import sys; sys.path.insert(0, 'tool/glass_lab/harness'); import sim, build; u = sim.device(); sim.status_bar(u); [sim.install_backdrops(u, b, build.backdrops()) for b in (build.NATIVE_BUNDLE, build.EXAMPLE_BUNDLE)]"
python3 tool/glass_lab/harness/lab.py reboot
python3 tool/glass_lab/harness/lab.py run material.interactive --app native --appearance light --backdrop photo
python3 $R/press_check.py --harness tool/glass_lab/harness build/glass_lab/runs/<that run>/material.interactive/light-photo/native
python3 tool/glass_lab/harness/lab.py repeat material.materialize --times 1 --appearance light --backdrop photo --a11y reduce-motion --into $NOISE
```

Expected: `press 0.9xx s PASS` (0.8-1.2 s; else reboot again, gotcha 49), then `repeat` prints that it recorded take 5 of `light-photo-reduce-motion` and rewrites that case's entry in `tool/glass_lab/noise.json` from takes 0, 1, 3, 4, 5. **Run `repeat` once.** If it ends in an error after printing `take 5` (the take is on disk), do not run it again: that would record take 6. Fix the cause and rerun it with `--times 0`, which records nothing and recomputes the case's floors and `noise.json` from the takes on disk. A `static repeatability FAILED` line stops the task: report it, do not commit. `repeat` refuses with `the native app build is older than its sources` when a package or Swift file changed since the last native build: run `python3 tool/glass_lab/harness/lab.py build native` and repeat the command.

- [ ] **Step 5: Check the new take and the file.**

```bash
python3 $R/take_check.py --harness tool/glass_lab/harness --scene material.materialize $NOISE/takes/$CASE/5
test -d $NOISE/excluded/takes/$CASE/2 && ! test -e $NOISE/takes/$CASE/2 && test -d $NOISE/takes/$CASE/5 && echo "take 2 excluded, take 5 present"
git show HEAD:packages/mobile/tool/glass_lab/noise.json > /tmp/noise-before.json
python3 $R/noise_recompute.py --harness tool/glass_lab/harness --run $NOISE --before /tmp/noise-before.json --out /tmp/gotcha52-moved.json $CASE
```

Expected: `take_check.py` reports no capture hole (a first-frame gap of 68-407 ms followed by frames 1.7-6.7 ms apart, gotcha 47), a touch window of the scene's length and the scene's touch count, and a disappear onset whose first changed frames are not both at progress 0.98 (that was take 2's fault); a take that fails any of these goes to `excluded/` with a README line and is replaced by another take after another fresh boot. Then `take 2 excluded, take 5 present`, and `noise_recompute.py` lists every value and limit that moved against 2B.1's file. The prototype's list (`R/gotcha52-moved.json`) has 27 values and 18 limits moved, 15 of them lower (for example `block.step1e0.cy.peak_ms` 150.0 to 25.0) and 3 higher (`block.step1e0.cx.peak_ms` 17 to 25, `block.step1e0.width.response_pct` 5 to 9.23, `block.step3e0.luma.peak_ms` 25 to 62.5), each equal to 1.5 times the recomputed noise, so they follow max(fixed, 1.5 x noise); the executor's take 5 is another recording, so its numbers differ, and **the list of what moved, with the three that rise named, goes into `results-2b2.md`**. Whatever moved, 2B.1's Done item 4 (266 of 336) was judged under the old floors and later counts under the new ones are not the same yardstick: the Done table says so.

- [ ] **Step 6: Commit.**

```bash
git add packages/mobile/tool/glass_lab/noise.json
git commit -m "fix(glass_lab): gotcha 52 take excluded and replaced after a fresh boot; noise.json recomputed for that case

Co-Authored-By: <the session's attribution line>"
```

### Task 4: Angle-weighted smooth union, native default spacing, animated spacing, the N7 and merge live scenes (M4)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/assets/shaders/sdf.glsl`, `lib/src/liquid_glass_blend_group.dart`, `lib/src/api/glass_effect_container.dart`, `lib/src/motion/glass_motion_coordinator.dart`, `FORK.md`, `README.md`
- Modify (app): `lib/core/widgets/glass/glass_scope.dart`
- Create (example): `lib/lab/scenes/spacing_scenes.dart`; modify `lib/lab/glass_lab_registry.dart`, `lib/lab/scenes/material_scenes.dart`
- Test: `test/geometry/{angle_union_test,pair_topology,scene_sdf_mirror}`, `test/motion/glass_spacing_test.dart`, example `test/spacing_scenes_test.dart`, app `test/core/widgets/glass/glass_scope_test.dart`

**Why.** Rulings 7–12. `scene_sdf_mirror.dart` and `pair_topology.dart` are the Dart mirror of the shader and its pair measures, so the geometry tests run without the GPU (`flutter test` cannot run the runtime effect). The app's `GlassScope` passes `spacing: 20` so its toolbars keep their look when the default becomes 8.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t04-tests from=4e32718e4 to=3269b9580 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t04-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/geometry/angle_union_test.dart test/motion/glass_spacing_test.dart` => FAIL

<<OUT t04-pkg-red>>

RUN[t04-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/spacing_scenes_test.dart` => FAIL

<<OUT t04-example-red>>

RUN[t04-app-red]: `cd packages/mobile && flutter test --no-pub test/core/widgets/glass/glass_scope_test.dart` => PASS

<<OUT t04-app-red>>

Expected: the package and example tests fail (missing symbols and values); the app's `glass_scope_test` **passes** before the implementation, by design: it pins that `GlassScope` keeps 20 pt, which was the package default until this task changes it, and it must still pass after.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t04-impl from=4e32718e4 to=3269b9580 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t04-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/geometry/angle_union_test.dart test/motion/glass_spacing_test.dart` => PASS

<<OUT t04-pkg-green>>

RUN[t04-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/spacing_scenes_test.dart` => PASS

<<OUT t04-example-green>>

RUN[t04-app-green]: `cd packages/mobile && flutter test --no-pub test/core/widgets/glass/glass_scope_test.dart` => PASS

<<OUT t04-app-green>>

- [ ] **Step 5: Gate: package.**

RUN[t04-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t04-gate-pkg-analyze>>

RUN[t04-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t04-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t04-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t04-gate-example-analyze>>

RUN[t04-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t04-gate-example-test>>

- [ ] **Step 7: Gate: app.**

RUN[t04-gate-app-analyze]: `cd packages/mobile && flutter analyze --no-pub` => PASS

<<OUT t04-gate-app-analyze>>

RUN[t04-gate-app-test]: `cd packages/mobile && flutter test --no-pub` => PASS

<<OUT t04-gate-app-test>>

- [ ] **Step 8: Commit.**

```bash
git add -A packages
git commit -m "feat(ios_liquid_glass): angle-weighted smooth union, native default spacing 8, animated spacing, N7 and live merge scenes

Co-Authored-By: <the session's attribution line>"
```

### Task 5: Topology masks that count native glass on stripes and photo, a still mask without the outline, `gap_pt`

**Files:**
- Modify: `tool/glass_lab/harness/track.py` (`topology_mask`, `still_mask`, `gap`), `shapes.py`, `analyze.py`, `metrics.py`
- Test: `tool/glass_lab/harness/tests/{synthetic,test_track,test_shapes}.py`

**Why.** Rulings 2–4. The merge, union and N7 judgements read these masks; the prototype checked them against 120 hand-labelled frames and 141 native N7 takes (`R/topology/`).

- [ ] **Step 1: Add the failing tests.**

<<PATCH t05-tests from=3269b9580 to=6006902f6 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t05-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_shapes.py` => FAIL

<<OUT t05-harness-red>>

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t05-impl from=3269b9580 to=6006902f6 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t05-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_shapes.py` => PASS

<<OUT t05-harness-green>>

- [ ] **Step 5: Gate: harness.**

RUN[t05-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t05-gate-harness>>

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): topology masks that count native glass on stripes and photo, still mask without the outline, gap_pt

Co-Authored-By: <the session's attribution line>"
```

### Task 6: `material.merge` tracks each circle, judges the pair's topology, and runs on photo too

**Files:**
- Modify: `tool/glass_lab/scenes.json` (`material.merge`: tracked circles, `topology` regions, photo backdrop, the motion list)

**Why.** Rulings 2 and 26. The scene is the spec's merge Done item; its manifest keeps `width.*` (ruling 26, D3).

- [ ] **Step 1: Apply the implementation.**

<<PATCH t06-impl from=6006902f6 to=96d7d5d03 files=@impl>>

- [ ] **Step 2: Check the manifest still loads and validates every scene.**

RUN[t06-manifest]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_manifest.py` => PASS

<<OUT t06-manifest>>

- [ ] **Step 3: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): material.merge tracks each circle, judges the pair's topology, and runs on photo too

Co-Authored-By: <the session's attribution line>"
```

### Task 7: Native controls for the morph toggle's swelling

**Files:**
- Modify: `tool/glass_lab/scenes.json` (`material.tap`, `material.morph.plain`)
- Modify: `tool/glass_lab/native/GlassLab/MaterialScenes.swift`

**Why.** Ruling 19. A tap that changes nothing and a plain morph show that the toggle's swelling is the morph. This task also compiles the Swift of Tasks 2 and 7.

- [ ] **Step 1: Apply the implementation.**

<<PATCH t07-impl from=d0cfaf7ae to=599853e52 files=@impl>>

- [ ] **Step 2: Check the manifest still loads and validates every scene.**

RUN[t07-manifest]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_manifest.py` => PASS

<<OUT t07-manifest>>

- [ ] **Step 3: Build the native lab app (Xcode 27, a few minutes); this is the only check the Swift of Tasks 2 and 7 gets.**

RUN[t07-native-build]: `cd packages/mobile && python3 tool/glass_lab/harness/lab.py build native` => PASS

<<OUT t07-native-build>>

- [ ] **Step 4: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): native controls for the morph toggle's swelling

Co-Authored-By: <the session's attribution line>"
```

### Task 8: `GlassNamespace` and `GlassEffectUnion`: a union draws as one capsule on its members' drawn rects; the union scene rebuilt (M5)

**Files:**
- Create: `packages/ios_liquid_glass/lib/src/api/glass_namespace.dart`
- Modify: `lib/ios_liquid_glass.dart`, `lib/src/api/glass_effect.dart`, `lib/src/glass_shadow.dart`, `lib/src/liquid_glass.dart`, `lib/src/liquid_glass_blend_group.dart`, `lib/src/motion/glass_motion_coordinator.dart`, `lib/src/motion/glass_shape_motion.dart`, `CHANGELOG.md`, `FORK.md`, `README.md`
- Modify (example): `lib/lab/scenes/material_scenes.dart` (the union scene), `tool/glass_lab/scenes.json`
- Test: `test/motion/glass_union_test.dart`, `test/motion/render_hooks_test.dart`, example `test/union_scene_test.dart`

**Why.** Rulings 15–17.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t08-tests from=599853e52 to=3a1e5a7f1 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t08-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_union_test.dart test/motion/render_hooks_test.dart` => FAIL

<<OUT t08-pkg-red>>

RUN[t08-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/union_scene_test.dart` => FAIL

<<OUT t08-example-red>>

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t08-impl from=599853e52 to=3a1e5a7f1 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t08-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_union_test.dart test/motion/render_hooks_test.dart` => PASS

<<OUT t08-pkg-green>>

RUN[t08-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/union_scene_test.dart` => PASS

<<OUT t08-example-green>>

- [ ] **Step 5: Gate: package.**

RUN[t08-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t08-gate-pkg-analyze>>

RUN[t08-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t08-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t08-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t08-gate-example-analyze>>

RUN[t08-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t08-gate-example-test>>

- [ ] **Step 7: Gate: app.**

RUN[t08-gate-app-analyze]: `cd packages/mobile && flutter analyze --no-pub` => PASS

<<OUT t08-gate-app-analyze>>

RUN[t08-gate-app-test]: `cd packages/mobile && flutter test --no-pub` => PASS

<<OUT t08-gate-app-test>>

- [ ] **Step 8: Commit.**

```bash
git add -A packages
git commit -m "feat(ios_liquid_glass): GlassNamespace and GlassEffectUnion; a union draws as one capsule on its members' drawn rects; union scene rebuilt

Co-Authored-By: <the session's attribution line>"
```

### Task 9: A noise pair folder whose link is broken or names another take is pointed at the take it pairs

**Files:**
- Modify: `tool/glass_lab/harness/lab.py`
- Test: `tool/glass_lab/harness/tests/test_lab.py`

**Why.** Ruling 6.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t09-tests from=3a1e5a7f1 to=359eb8e31 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t09-lab-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_lab.py` => FAIL

<<OUT t09-lab-red>>

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t09-impl from=3a1e5a7f1 to=359eb8e31 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t09-lab-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_lab.py` => PASS

<<OUT t09-lab-green>>

- [ ] **Step 5: Gate: harness.**

RUN[t09-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t09-gate-harness>>

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "fix(glass_lab): a noise pair folder whose link is broken or names another take is pointed at the take it pairs now

Co-Authored-By: <the session's attribution line>"
```

### Task 10: Appear progress is the spring to a fitted per-preset exponent, fitted on simulated moving glass (H4)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_materialize.dart`, `lib/src/motion/ios27_motion.dart` (the three `ios27*AppearExponent` constants, as `fitvis --write` writes them)
- Modify: `tool/glass_lab/harness/fitvis.py` (`mapped`, `flutter_frames`, `recorded_series`, `moving_score`, `fit_appear_exponent(s)`)
- Test: `test/motion/glass_materialize_test.dart`, `tool/glass_lab/harness/tests/test_fitvis.py`

**Why.** Ruling 22. The exponents are `lab.py fitvis` output (`R/h4/fit-h4.json`, `fitvis-h4.txt`), and the check below compares the committed constants with that file.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t10-tests from=6873314df to=22df6e970 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t10-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_materialize_test.dart` => FAIL

<<OUT t10-pkg-red>>

RUN[t10-fitvis-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py` => FAIL

<<OUT t10-fitvis-red>>

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t10-impl from=6873314df to=22df6e970 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t10-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_materialize_test.dart` => PASS

<<OUT t10-pkg-green>>

RUN[t10-fitvis-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py` => PASS

<<OUT t10-fitvis-green>>

- [ ] **Step 5: Check the committed exponents are `fitvis`'s fitted values (`h4/fit-h4.json`).**

RUN[t10-table]: `python3 -c "import json,re; m=json.load(open('docs/liquid_glass/02b-motion/research/proto-2b2/h4/fit-h4.json'))['mapping']; t=open('packages/mobile/packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart').read(); w={'material.materialize':'Default','material.materialize.snappy':'Snappy','material.materialize.bouncy':'Bouncy'}; print([(n, m[k]['appear_exponent']['value'], float(re.search('ios27'+n+'AppearExponent = ([0-9.]+)',t).group(1))) for k,n in w.items()])"` => PASS

<<OUT t10-table>>

- [ ] **Step 6: Gate: package.**

RUN[t10-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t10-gate-pkg-analyze>>

RUN[t10-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t10-gate-pkg-test>>

- [ ] **Step 7: Gate: harness.**

RUN[t10-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t10-gate-harness>>

- [ ] **Step 8: Commit.**

```bash
git add -A packages
git commit -m "feat(materialize): appear progress is the spring to a fitted per-preset exponent, fitted on simulated moving glass (H4)

Co-Authored-By: <the session's attribution line>"
```

### Task 11: `GlassEffectID` and matched-geometry morph: partner morph, emergence from the nearest glass, sink or dematerialize, content blur, the morph scenes (M6)

**Files:**
- Create: `packages/ios_liquid_glass/lib/src/motion/glass_morph_geometry.dart`; `example/lib/lab/scenes/morph_scenes.dart`
- Modify: `lib/ios_liquid_glass.dart`, `lib/src/api/{glass_effect,glass_effect_transition,glass_namespace}.dart`, `lib/src/motion/{glass_motion_coordinator,glass_motion_widgets,ios27_motion}.dart`, `FORK.md`, `README.md`; example `lib/lab/scenes/material_scenes.dart`; `tool/glass_lab/scenes.json` (`material.morph`, `.plain`)
- Test: `test/motion/glass_morph_test.dart`, example `test/morph_scene_test.dart`

**Why.** Rulings 18–21.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t11-tests from=c8121c7aa to=f4039bea6 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t11-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_morph_test.dart` => FAIL

<<OUT t11-pkg-red>>

RUN[t11-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/morph_scene_test.dart` => FAIL

<<OUT t11-example-red>>

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t11-impl from=c8121c7aa to=f4039bea6 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t11-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_morph_test.dart` => PASS

<<OUT t11-pkg-green>>

RUN[t11-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/morph_scene_test.dart` => PASS

<<OUT t11-example-green>>

- [ ] **Step 5: Gate: package.**

RUN[t11-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t11-gate-pkg-analyze>>

RUN[t11-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t11-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t11-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t11-gate-example-analyze>>

RUN[t11-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t11-gate-example-test>>

- [ ] **Step 7: Gate: app.**

RUN[t11-gate-app-analyze]: `cd packages/mobile && flutter analyze --no-pub` => PASS

<<OUT t11-gate-app-analyze>>

RUN[t11-gate-app-test]: `cd packages/mobile && flutter test --no-pub` => PASS

<<OUT t11-gate-app-test>>

- [ ] **Step 8: Commit.**

```bash
git add -A packages
git commit -m "feat(ios_liquid_glass): GlassEffectID and matchedGeometry morph: partner morph, emergence from the nearest glass, sink or dematerialize, content blur, morph scenes

Co-Authored-By: <the session's attribution line>"
```

### Task 12: `fitvis --write` keeps the morph content blur line the table already holds

**Files:**
- Modify: `tool/glass_lab/harness/fitvis.py` (`table_source`, `write_table`)
- Test: `tool/glass_lab/harness/tests/test_fitvis.py`

**Why.** Ruling 23.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t12-tests from=f4039bea6 to=1d2ddc57a files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t12-fitvis-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py` => FAIL

<<OUT t12-fitvis-red>>

Expected: `FAILED (failures=1)`. Task 12 adds two tests; only `test_a_write_keeps_the_morph_content_blur_line_the_target_already_holds` fails before the implementation (the old `table_source` deletes the line). `test_a_write_to_a_target_without_the_morph_content_blur_line_adds_none` **passes** before it, by design: it pins the other half of the rule (a target that has no such line must not gain one), which the old code also satisfied and a careless fix could break, so it is a guard and not a red test.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t12-impl from=f4039bea6 to=1d2ddc57a files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t12-fitvis-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py` => PASS

<<OUT t12-fitvis-green>>

- [ ] **Step 5: Gate: harness.**

RUN[t12-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t12-gate-harness>>

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "fix(glass_lab): fitvis --write keeps the morph content blur line the table already holds

Co-Authored-By: <the session's attribution line>"
```

### Task 13: A second morph swap inside the first settles: the content ghost samples a partner that was removed

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart` (`GlassGhost._step`, content kind)
- Test: `test/motion/glass_morph_test.dart` (`_Chain`, two tests)

**Why.** Ruling 27. A content ghost reported `partner._morph.isMoving`, and a partner's spring is advanced only by its own member; when the partner was itself swapped away inside the morph, its ghost is a content ghost too and never advanced it, so the first ghost, its snapshot and the container's ticker ran for ever. A double tap on the toggle did it.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t13-tests from=4db370855 to=3f5f59cbf files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t13-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_morph_test.dart` => FAIL

<<OUT t13-pkg-red>>

Expected: the two new tests fail on `Expected: empty / Actual: [Instance of 'GlassGhost']` (the ghost is still there 5 s after the second swap, at a 60 ms and at a 300 ms gap); the other morph tests pass.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t13-impl from=4db370855 to=3f5f59cbf files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t13-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_morph_test.dart` => PASS

<<OUT t13-pkg-green>>

- [ ] **Step 5: Gate: package.**

RUN[t13-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t13-gate-pkg-analyze>>

RUN[t13-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t13-gate-pkg-test>>

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "fix(ios_liquid_glass): a second morph swap inside the first settles: the content ghost samples a removed partner

Co-Authored-By: <the session's attribution line>"
```

### Task 14: A shape motion says whether it is transient (a ghost is, a member is not)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart`, `lib/src/motion/glass_motion_coordinator.dart`
- Test: `test/motion/render_hooks_test.dart`, `test/motion/glass_union_test.dart` (their fake motions implement the new member)

**Why.** Ruling 28. A refactor that adds `isTransient` to the `GlassShapeMotion` interface and changes no behaviour, so that Task 15's test can fail on an assertion and not on a missing symbol.

- [ ] **Step 1: Apply the implementation.**

<<PATCH t14-impl from=3f5f59cbf to=42f09d87f files=@all>>

- [ ] **Step 2: Gate: package.**

RUN[t14-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t14-gate-pkg-analyze>>

RUN[t14-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t14-gate-pkg-test>>

- [ ] **Step 3: Commit.**

```bash
git add -A packages
git commit -m "refactor(ios_liquid_glass): a shape motion says whether it is transient; a ghost is, a member is not

Co-Authored-By: <the session's attribution line>"
```

### Task 15: Ghosts count toward a container's sixteen shapes and are left out before a member is; paint never throws for them

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart` (`gatherShapeData`)
- Test: `test/motion/glass_group_test.dart` (new; builds the blend group and its glass render objects, as spec §9 and gotcha 39 require)

**Why.** Ruling 28. A sinking or pending ghost registers in the container's blend group, which 2B.1's ghosts did not: they drew in their own layers because they only fade in place (`dematerialize`) and need no blend; a sink has to blend with the glass it sinks into. 15 glasses, an arrival with an id and two sinking ghosts made 18 shapes and `updateGeometryShaderShapes` threw `UnsupportedError` in paint. The shader cannot be compiled by `flutter test` (gotcha 3), so the test constructs `RenderLiquidGlassBlendGroup` and `RenderLiquidGlass` objects with the shader upload stubbed and reads `gatherShapeData`.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t15-tests from=42f09d87f to=19e53ff72 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t15-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_group_test.dart` => FAIL

<<OUT t15-pkg-red>>

Expected: three of the four tests fail on `Expected: an object with length of <16>` or on the ghost that should have been left out (18, 17 and 16 shapes drawn); `ghosts under the cap all stay in the geometry` passes before and after, by design.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t15-impl from=42f09d87f to=19e53ff72 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t15-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_group_test.dart` => PASS

<<OUT t15-pkg-green>>

- [ ] **Step 5: Gate: package.**

RUN[t15-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t15-gate-pkg-analyze>>

RUN[t15-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t15-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t15-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t15-gate-example-analyze>>

RUN[t15-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t15-gate-example-test>>

- [ ] **Step 7: Commit.**

```bash
git add -A packages
git commit -m "fix(ios_liquid_glass): ghosts count toward a container's sixteen shapes and are left out before a member, so paint never throws for them

Co-Authored-By: <the session's attribution line>"
```

### Task 16: A shape motion syncs itself and says whether it moved; a geometry asks before it trusts its cache (nothing answers yes yet)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart`, `lib/src/motion/glass_motion_coordinator.dart`, `lib/src/internal/render_liquid_glass_geometry.dart` (`shapesMoved`, `revalidateGeometry`)
- Test: `test/motion/render_hooks_test.dart`, `glass_union_test.dart`, `glass_group_test.dart` (fakes implement `syncMoved`)

**Why.** Ruling 29. Two refactors with no behaviour change (the member answers `false`, `shapesMoved` answers `false`), so that Task 17's tests fail on assertions.

- [ ] **Step 1: Apply the implementation.**

<<PATCH t16-impl from=19e53ff72 to=7bf674822 files=@all>>

- [ ] **Step 2: Gate: package.**

RUN[t16-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t16-gate-pkg-analyze>>

RUN[t16-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t16-gate-pkg-test>>

- [ ] **Step 3: Commit.**

```bash
git add -A packages
git commit -m "refactor(ios_liquid_glass): a shape motion syncs itself and says whether it moved; a geometry asks whether its shapes moved before it trusts its cache

Co-Authored-By: <the session's attribution line>"
```

### Task 17: Glass whose anchor changes has its container's geometry rebuilt in that frame (the first frame of a move)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart` (`GlassMember._moved`, `syncMoved`), `lib/src/liquid_glass_blend_group.dart` (`shapesMoved`)
- Test: `test/motion/glass_space_shift_test.dart` (new), `test/motion/glass_group_test.dart`

**Why.** Ruling 29 (D5). In the frame of a tap Flutter drew a glass at the container's shift: the blend group decides in `paint` whether to rebuild its geometry matte, before its members' `sync` has found that their anchors changed, so it reused last frame's matte (group-local) at the group's new position, and the next frame, when the members' springs notify, drew it right (`R/verify/summary.txt` 1c: 8 of 8 split onsets, 5 of 8 merge onsets). Shadows were right because they read `drawn` after `sync`. The group now asks each glass to sync, and a glass that moved marks the geometry as possibly stale, before the decision. Verified in the real app, `R/onset/flutter-merge-light-stripes-after.txt` (run `20261007-114536`): no frame at the mirror at either onset.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t17-tests from=7bf674822 to=ab9ee28c6 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t17-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart test/motion/glass_group_test.dart` => FAIL

<<OUT t17-pkg-red>>

Expected: `both circles report that they moved...`, `a move without an animation is reported...` and `a settled geometry is marked for an update...` fail (the member and the group answer `false` before the implementation); the others pass.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t17-impl from=7bf674822 to=ab9ee28c6 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t17-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart test/motion/glass_group_test.dart` => PASS

<<OUT t17-pkg-green>>

- [ ] **Step 5: Gate: package.**

RUN[t17-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t17-gate-pkg-analyze>>

RUN[t17-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t17-gate-pkg-test>>

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "fix(ios_liquid_glass): glass whose anchor changes has the container's geometry rebuilt in that frame, so the first frame of a move is not drawn at the container's shift

Co-Authored-By: <the session's attribution line>"
```

### Task 18: A space that moves on screen as its container resizes is part of the glass's anchor (a morph does not start from the mirror of its start)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart` (`GlassMember._sync`)
- Test: `test/motion/glass_space_shift_test.dart` (two tests)

**Why.** Ruling 29 (D5). The anchor was the glass's place in its space; when the space itself moves on screen at the same time (the morph scene's column re-centres as the stack grows, so the toggle's space moves 108 pt up while the toggle's place in it moves 216 down), the offset the glass springs from was computed without the space's move and the toggle started at 2 x old - new (343 for 451 to 559), for the whole spring. The anchor now adds the space's on-screen origin (outer scrolling excluded), and Task 24b limits that to the frames in which the glass's own place in the space changed. Verified in the real app (`R/onset/flutter-morph-light-stripes-after.txt`, run `20261007-115120`): the toggle's first frames stay at 451 and the badges leave it. This also removes the cause of ruling 21 (c) as the prototype described it (the heart first seen at the star's slot); whether emergence now equals native's is for Task 27 to measure.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t18-tests from=ab9ee28c6 to=6569e47e2 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t18-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart` => FAIL

<<OUT t18-pkg-red>>

Expected: the two `glass in a space that re-centres...` tests fail on `Actual: <222.0>` against 272.0 (grow) and `Actual: <372.0>` against 322.0 (shrink): the glass is drawn 50 pt from where it was.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t18-impl from=ab9ee28c6 to=6569e47e2 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t18-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart` => PASS

<<OUT t18-pkg-green>>

- [ ] **Step 5: Gate: package.**

RUN[t18-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t18-gate-pkg-analyze>>

RUN[t18-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t18-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t18-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t18-gate-example-analyze>>

RUN[t18-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t18-gate-example-test>>

**The app gate is not run in this task or in Task 20:** the app's `floating_working_control_test` (`reduce motion changes instantly and runs no shimmer ticker`) fails from here until Task 24b, which fixes the over-broad anchor this task introduced (the first replay found it). The app gate runs again, whole, at Task 24b.

- [ ] **Step 7: Commit.**

```bash
git add -A packages
git commit -m "fix(ios_liquid_glass): a space that moves on screen as its container resizes is part of the glass's anchor, so a morph does not start from the mirror of its start

Co-Authored-By: <the session's attribution line>"
```

### Task 19: Merge is judged by each circle's outer edge and the pair's gap, morph by the stack's outer edges (D3, a user-approved manifest correction)

**Files:**
- Modify: `tool/glass_lab/harness/track.py` (`shape_row` edges, `topology_row` gap), `shapes.py` (`EDGE_KEYS`, `gap_rms`, `significant`), `manifest.py` (`EDGE_KEYS`, `edges`)
- Modify: `tool/glass_lab/scenes.json` (`material.merge`, `material.morph`, `material.morph.plain`)
- Test: `tool/glass_lab/harness/tests/{test_track,test_shapes,test_manifest}.py`

**Why.** Ruling 26 (D3). Approved by the user on 2026-10-07 as a manifest correction, not a loosening. `material.merge` listed `width.*` for circles that never change width (20 absent measures per case, class (b)); its replacement is each circle's outer edge (the left circle's left edge `xmin`, the right circle's right edge `xmax`, which no bridge crosses) and the pair's `gap_rms` beside the join, split, neck and count it already had. `material.morph` keeps every measure it had and gains the stack's top and bottom edges (`ymin`, `ymax`: the star's top and the toggle's bottom). New keys are `MOTION_MEASURES` entries with tests; the old and new counts on the same recordings are in the Done table template.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t19-tests from=6569e47e2 to=5ed43ab6e files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t19-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_manifest.py` => FAIL

<<OUT t19-harness-red>>

Expected: the new tests fail on a missing key (`xmin`, `gap`, `topology.gap_rms`, `edges`) or on the manifest entries; nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t19-impl from=6569e47e2 to=5ed43ab6e files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t19-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_manifest.py` => PASS

<<OUT t19-harness-green>>

- [ ] **Step 5: Gate: harness.**

RUN[t19-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t19-gate-harness>>

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): merge is judged by each circle's outer edge and the pair's gap, morph by the stack's outer edges (D3, user-approved manifest correction)

Co-Authored-By: <the session's attribution line>"
```

### Task 20: A container draws with the material row of its members' size (the median member), unless it is given a side (D1)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart` (`side` is nullable; a `GlassMaterialSource`), `lib/src/api/glass_effect.dart`, `lib/src/motion/glass_motion_coordinator.dart` (`followMaterial`, `_followSides`, `sharedMaterial`)
- Test: `test/glass_container_material_test.dart` (new), `test/motion/glass_member_test.dart`

**Why.** Ruling 30 (D1, a main-session ruling). Native draws each glass with its own size's material (64 pt union glass is 9-12 luma lighter than 80 pt glass in dark); the container resolved one row for a fixed `side` of 88. The container's layer now follows a material source whose side is the median of its members' laid-out shorter sides (the upper median for an even count), so a container of equal members, as in the union scene, draws with the row of that size; an explicit `side` pins it as before. **A limit, stated:** one layer has one material, so a container of members of different sizes draws all of them with the median member's row; a row per member inside one layer needs per-shape material parameters in the final-render shader and is not built. This changes the material of every container whose members are not 88 pt: Task 27 Step 9's still check against 2A is the risk check.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t20-tests from=5ed43ab6e to=4d42f3642 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t20-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/glass_container_material_test.dart` => FAIL

<<OUT t20-pkg-red>>

Expected: five of the six tests fail on `Expected: LiquidGlassSettings` (the row of 88 is drawn); `a container with an explicit side keeps that row` passes before and after, by design.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t20-impl from=5ed43ab6e to=4d42f3642 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t20-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/glass_container_material_test.dart` => PASS

<<OUT t20-pkg-green>>

- [ ] **Step 5: Gate: package.**

RUN[t20-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t20-gate-pkg-analyze>>

RUN[t20-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t20-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t20-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t20-gate-example-analyze>>

RUN[t20-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t20-gate-example-test>>

The app gate is not run here (see Task 18); it runs at Task 24b.

- [ ] **Step 7: Commit.**

```bash
git add -A packages
git commit -m "feat(ios_liquid_glass): a container draws with the material row of its members' size (the median member), unless it is given a side (D1)

Co-Authored-By: <the session's attribution line>"
```

### Task 21: The union scene's glyph sizes are a constant of the scene

**Files:**
- Modify: `packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart`
- Test: `example/test/union_scene_test.dart`

**Why.** Ruling 31 (D2). A refactor (all four sizes 24, as before) so that Task 22's test fails on an assertion.

- [ ] **Step 1: Apply the implementation.**

<<PATCH t21-impl from=4d42f3642 to=8d61ee26c files=@all>>

- [ ] **Step 2: Gate: example.**

RUN[t21-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t21-gate-example-analyze>>

RUN[t21-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t21-gate-example-test>>

- [ ] **Step 3: Commit.**

```bash
git add -A packages
git commit -m "refactor(example): the union scene's glyph sizes are a constant of the scene

Co-Authored-By: <the session's attribution line>"
```

### Task 22: The union scene's glyphs are sized to native's ink height (D2)

**Files:**
- Modify: `packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart` (`UnionScene.glyphSizes`)
- Test: `example/test/union_scene_test.dart`
- Evidence: `R/union/glyph-ink.txt`, `R/union/ink_flutter.py`

**Why.** Ruling 31 (D2, a main-session ruling: match native's glyph ink in the example's union scene; never shrink the measured regions). Native's SF Symbols at size 24 are taller than Material Icons at 24; each size is 24 x native ink height / Flutter ink height at 24, rounded to 0.5 (star 33, heart 28, bolt 34.5, leaf 32.5), and the test derives them from the saved ink measurements. This is a change of the test content (the example), not of the package. Measured in the app (`R/union/glyph-ink.txt`, run `20261007-120641`): heights within 0.33 pt of native, star and heart widths within 1.0 pt; bolt and leaf stay 2.3 and 4.0 pt narrower because `Icons.bolt` and `Icons.eco` are other shapes than `bolt.fill` and `leaf.fill` (class (b), content).

- [ ] **Step 1: Add the failing tests.**

<<PATCH t22-tests from=8d61ee26c to=d4243f87f files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t22-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/union_scene_test.dart` => FAIL

<<OUT t22-example-red>>

Expected: `each glyph is sized so its ink is as tall as native's...` fails (`Expected: [33.0, 28.0, 34.5, 32.5] Actual: [24.0, 24.0, 24.0, 24.0]`); the other two pass.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t22-impl from=8d61ee26c to=d4243f87f files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t22-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/union_scene_test.dart` => PASS

<<OUT t22-example-green>>

- [ ] **Step 5: Gate: example.**

RUN[t22-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t22-gate-example-analyze>>

RUN[t22-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t22-gate-example-test>>

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "feat(example): the union scene's glyphs are sized to native's ink height (D2)

Co-Authored-By: <the session's attribution line>"
```

### Task 23: `material.respace`: a native and a Flutter scene whose container spacing animates, judged on the pair's topology

**Files:**
- Modify: `tool/glass_lab/native/GlassLab/MaterialScenes.swift` (`RespaceScene`), `tool/glass_lab/scenes.json` (`material.respace`), `tool/glass_lab/harness/shapes.py` (`significant`)
- Modify (example): `lib/lab/scenes/spacing_scenes.dart` (`RespaceScene`)
- Test: `tool/glass_lab/harness/tests/{test_shapes,test_manifest}.py`, example `test/spacing_scenes_test.dart`

**Why.** Ruling 12 (a user decision of 2026-10-07: keep the spacing animation, with a native reference). **No native evidence for the animation exists yet:** nothing recorded in 2B.1 or the prototype changes a container's `spacing` while it is on screen, so ruling 12 is the package's own design until Task 26 records and judges this scene. The scene is two 80 pt circles 12 pt apart (a gap that is apart at spacing 8, whose reach is 4 pt, and joined at spacing 40, whose reach is 20 pt) in a native `GlassEffectContainer(spacing:)` that `withAnimation` changes between 8 and 40 on the buttons `widen` and `narrow`; the Flutter scene does the same under `withGlassAnimation`. The circles never move, so the whole judgement is the pair's topology (count, join and split times, neck and gap over time). A topology change alone now makes an event significant (a scene whose only change is a neck forming has no shape that moves). The id is `material.respace`, not `material.spacing.*`, so the N7 selector and the 23-scene counts do not change.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t23-tests from=d4243f87f to=7f868ffe1 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t23-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_manifest.py` => FAIL

<<OUT t23-harness-red>>

RUN[t23-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/spacing_scenes_test.dart` => FAIL

<<OUT t23-example-red>>

Expected: the harness tests fail (`a topology change alone makes an event significant`, and the manifest has no `material.respace`) and `material.respace is two 80 pt circles...` fails on the registry.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t23-impl from=d4243f87f to=7f868ffe1 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t23-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_manifest.py` => PASS

<<OUT t23-harness-green>>

RUN[t23-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/spacing_scenes_test.dart` => PASS

<<OUT t23-example-green>>

- [ ] **Step 5: Build the native lab app (Xcode 27); this is the only check the Swift of `RespaceScene` gets. `lab_ids_match_the_native_registry` (harness test) pins that the Swift registry and the manifest agree.**

RUN[t23-native-build]: `cd packages/mobile && python3 tool/glass_lab/harness/lab.py build native` => PASS

<<OUT t23-native-build>>

- [ ] **Step 6: Gate: harness.**

RUN[t23-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t23-gate-harness>>

- [ ] **Step 7: Gate: example.**

RUN[t23-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t23-gate-example-analyze>>

RUN[t23-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t23-gate-example-test>>

- [ ] **Step 8: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): material.respace, a native and a Flutter scene whose container spacing animates, judged on the pair's topology; a topology change alone makes an event significant

Co-Authored-By: <the session's attribution line>"
```

### Task 24: README and FORK say what the stills measure, that the spacing animation has no native reference yet, and what the new behaviours are

**Files:**
- Modify: `packages/ios_liquid_glass/README.md`, `FORK.md`

**Why.** Rulings 9, 12, 28-30. README claimed that the blend "matches native's necks and bulges ... from 4 to 80 pt" while 6 of the 46 recorded N7 cases pass end to end and none on dark; it now says what was measured (at most 0.5 pt RMS on the light photo silhouette, 9 spacings) and what was not. The container's material, the 16-shape guard, the anchor and the ghost fix are recorded in FORK as `FORK.md` requires.

- [ ] **Step 1: Apply the implementation.**

<<PATCH t24-impl from=7f868ffe1 to=e320d0cbd files=@all>>

- [ ] **Step 2: Commit.**

```bash
git add -A packages
git commit -m "docs(ios_liquid_glass): README states what the stills measure and that the spacing animation has no native reference yet; the container material, the cap, the anchor and the ghost fix are recorded in FORK

Co-Authored-By: <the session's attribution line>"
```

### Task 24b: A space's own move counts in a glass's anchor only when the glass's place in it changed too

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart` (`GlassMember._sync`, `_anchorOrigin`), `FORK.md`
- Test: `test/motion/glass_space_shift_test.dart` (one test, and `_Grow` gains `inside`)

**Why.** Ruling 29. Task 18 counted every move of the space; the app's own `floating_working_control_test` (`reduce motion changes instantly and runs no shimmer ticker`) failed in the first replay at Task 18's app gate, because glass that only moves with its parent (README: "anything that moves the container's parent moves the glass at once") started to spring. The origin shift is now added only when the glass's place in the space changed in the same frame, which is the morph's case (the toggle's place changes by 216 and its space moves by 108) and not the floating control's. The real-app morph check was repeated at this commit (`R/onset/flutter-morph-light-stripes-after.txt`, run `20261007-124647`).

- [ ] **Step 1: Add the failing tests.**

<<PATCH t24b-tests from=e320d0cbd to=4fe05e630 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t24b-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart` => FAIL

<<OUT t24b-pkg-red>>

Expected: `glass whose container only moves with its parent follows at once and springs nothing` fails (`Expected: a numeric value within <0.000001> of <322.0> Actual: <272.0>`); the five others pass.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t24b-impl from=e320d0cbd to=4fe05e630 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t24b-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart` => PASS

<<OUT t24b-pkg-green>>

- [ ] **Step 5: Gate: package.**

RUN[t24b-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t24b-gate-pkg-analyze>>

RUN[t24b-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t24b-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t24b-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t24b-gate-example-analyze>>

RUN[t24b-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t24b-gate-example-test>>

- [ ] **Step 7: Gate: app.**

RUN[t24b-gate-app-analyze]: `cd packages/mobile && flutter analyze --no-pub` => PASS

<<OUT t24b-gate-app-analyze>>

RUN[t24b-gate-app-test]: `cd packages/mobile && flutter test --no-pub` => PASS

<<OUT t24b-gate-app-test>>

- [ ] **Step 8: Gate: harness.**

RUN[t24b-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t24b-gate-harness>>

- [ ] **Step 9: Commit.**

```bash
git add -A packages
git commit -m "fix(ios_liquid_glass): a space's own move counts in a glass's anchor only when the glass's place in it changed too, so glass that moves with its parent still follows at once

Co-Authored-By: <the session's attribution line>"
```
