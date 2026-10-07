### Task 25: Noise floors for every 2B.2 scene and case (L8), over two sessions

**Files:**
- Modify: `tool/glass_lab/noise.json` (written by `lab.py repeat` only)

**Interfaces:**
- Consumes: `lab.py repeat --into`, `lab.py reboot`, the scenes of Tasks 2, 6, 7, 8, 11, 19 and 23, `take_check.py` and `press_check.py` (`R/`).
- Produces: `noise.json` entries `{scene: {case: {measure: noise}}}` for `material.merge`, `material.union`, `material.morph`, `material.morph.plain` (normal and `-reduce-motion` cases where they have them), `material.respace` and the 17 `material.spacing.*` scenes that have no floor yet: motion measures where a scene moves, and the static and still-topology measures (`ready.mad`, `ready.topology.<region>.count`, `.neck_pt`, `.gap_pt`) everywhere. Every limit those scenes are judged on becomes max(fixed threshold, 1.5 × noise) (spec L8). **Every floor is computed from scratch from this task's takes**; none is carried from the prototype. The six spacing scenes that 2B.1 recorded (`material.spacing.40.{a,b,c}`, `material.spacing.default.{a,b,c}`) keep their 2B.1 floors, because `repeat` rewrites a scene's whole entry and recording them again would replace those floors with different ones; Gotcha 52's case keeps what Task 3 wrote.

Five native takes per scene and case: three in session 1, then a simulator reboot, then two in session 2 appended to the same run, so the noise of each case is the worst of its ten pairs, six of them across the reboot. Cases: `material.merge` 4 + 4 (Reduce Motion), `material.union` 2, `material.morph` 4 + 4, `material.morph.plain` 4 + 4, `material.respace` 2 and 17 spacing scenes 2 each (light and dark photo): 62 cases, 310 takes, about 50 s a take, so about 4.3 h of recording and about 3 h of analysis; session 1 is about 2.6 h and session 2 about 1.7 h. **Disk:** analysis writes `overview/`, `shapes/` and `marker/` frame caches into every take (gotcha 51; 2B.1's 60 cases made 42 GB), so this task needs about 50 GB beyond the 40 GB floor: begin with at least 90 GB free, or record and recompute in groups (A: merge, morph and morph.plain, normal and Reduce Motion; B: union, respace and the spacing scenes) and **stop to ask the user to approve clearing the finished group's caches** (`overview/`, `shapes/` and `marker/` under its takes) whenever free space falls under 45 GB; **Numbers (2026-10-07, about 83 GB free before Task 3's 8.6 GB copy, so about 74 GB after it):** group A (merge, morph, morph.plain: 24 of the 62 cases) writes about 17 GB at 2B.1's rate (42 GB for 60 cases), group B about 25 GB; so the first group fits above the 45 GB line and the second probably does not unless the finished group's caches are cleared. **Run `df -h /Users/omaraly` before every group and before every case batch inside one; stop under 40 GB free and report; ask the user for space under 45 GB. Never delete anything yourself to make room** (including caches, old runs and worktrees: the user clears them or names a volume).

```bash
cd /Users/omaraly/development/AI/Operator-2b2/packages/mobile
R=/Users/omaraly/development/AI/Operator-2b2/docs/liquid_glass/02b-motion/research/proto-2b2
RUN=$PWD/build/glass_lab/runs/noise-2b2
```

- [ ] **Step 1: Reboot, then check the press.** Boot fresh, record one native `material.interactive` take, and read its 1.0 s press:

```bash
python3 tool/glass_lab/harness/lab.py build all
python3 tool/glass_lab/harness/lab.py reboot
python3 tool/glass_lab/harness/lab.py run material.interactive --app native --appearance light --backdrop photo
python3 $R/press_check.py --harness tool/glass_lab/harness build/glass_lab/runs/<run>/material.interactive/light-photo/native
```

Expected: `press 0.9xx s PASS` (the prototype read 0.950 s, run `20261007-054559`). A press outside 0.8–1.2 s means a stale boot: reboot again (gotcha 49). Install the backdrops after the build (Execution setup).

- [ ] **Step 2: Session 1, group A.** One command at a time, `run_in_background`; every `repeat` stops the script when it exits non-zero (`repeat` writes `noise.json` first and exits non-zero on `static repeatability FAILED`; that stops the task, and the executor reports the scene and case instead of going on):

```bash
for a in "" "--a11y reduce-motion"; do
  for s in material.merge material.morph material.morph.plain; do python3 tool/glass_lab/harness/lab.py repeat $s --times 3 $a --into $RUN || { echo "STOP $s $a"; exit 1; }; done
done
```

`repeat` takes one scene at a time (`manifest.select` with a bare `material.morph` also matches `material.morph.plain`, but `repeat` uses only the first match). Then check the press again as in Step 1: a press outside 0.8–1.2 s throws away every take recorded since the last good check, which are re-recorded after a reboot (they are excluded as in Step 5).

- [ ] **Step 3: Session 1, group B.**

```bash
python3 tool/glass_lab/harness/lab.py repeat material.union --times 3 --into $RUN || exit 1
python3 tool/glass_lab/harness/lab.py repeat material.respace --times 3 --into $RUN || exit 1
for s in default.d 4.a 6.a 8.a 10.a 12.a 16.a 20.a 20.b 20.c 40.d 40.e 80.a 80.b 80.c 80.d 80.e; do python3 tool/glass_lab/harness/lab.py repeat material.spacing.$s --times 3 --into $RUN || { echo "STOP $s"; exit 1; }; done
```

(The six scenes `default.a`, `default.b`, `default.c`, `40.a`, `40.b` and `40.c` are not in the list: they keep 2B.1's floors.) Check the press again after about three hours of session 1.

- [ ] **Step 4: Reboot, check the press, session 2.**

```bash
python3 tool/glass_lab/harness/lab.py reboot
xcrun simctl spawn 708879DD-8B2A-4547-863F-F49EE1474D8B defaults read com.apple.Accessibility ReduceMotionEnabled
```

Expected: `rebooted 708879DD-8B2A-4547-863F-F49EE1474D8B`, then `0`. Check the press as in Step 1, then run Steps 2 and 3 again with `--times 2` and the same `--into $RUN`. Each case now has takes 0–4 and each `repeat` rewrites its scene's entry from all five takes.

- [ ] **Step 5: The capture-hole rule and the touch gate.** For every case:

```bash
python3 $R/take_check.py --harness tool/glass_lab/harness --scene <scene id> $RUN/takes/<scene>/<case>/*
```

A take with a first-frame gap of 68–407 ms followed by frames 1.7–6.7 ms apart (gotcha 47), a touch window of zero length, or a touch count other than the scene's, is moved to `$RUN/excluded/` with a README line saying why, replaced by one more take recorded after a fresh boot, and the case's entry recomputed. The replacement is `repeat` with `--times 1` **and the case's flags**, so that it records that case only:

```bash
python3 tool/glass_lab/harness/lab.py repeat <scene id> --times 1 --appearance <light|dark> --backdrop photo [--a11y reduce-motion] --into $RUN
```

(without the flags it records every case of the scene and adds a take to each). Never let one take set a floor alone: for each case list the measures whose noise is above 3 × the median of the others and say why they stay (gotcha 52).

- [ ] **Step 6: Check the file and list what moved.**

```bash
python3 - <<'EOF'
import json, subprocess
noise = json.load(open("tool/glass_lab/noise.json"))
before = json.loads(subprocess.run(["git", "show", "HEAD:packages/mobile/tool/glass_lab/noise.json"], capture_output=True, text=True).stdout)
for scene in ("material.merge", "material.union", "material.morph", "material.morph.plain", "material.respace"):
    print(scene, {case: len(values) for case, values in sorted(noise[scene].items())})
kept = [f"material.spacing.{s}" for s in "default.a default.b default.c 40.a 40.b 40.c".split()]
print("2B.1 spacing floors unchanged:", all(noise[k] == before[k] for k in kept))
print(sum(len(noise[f"material.spacing.{s}"]) for s in "default.a default.b default.c default.d 4.a 6.a 8.a 10.a 12.a 16.a 20.a 20.b 20.c 40.a 40.b 40.c 40.d 40.e 80.a 80.b 80.c 80.d 80.e".split()), "spacing cases")
print([(scene, case, name) for scene, entry in noise.items() if isinstance(entry, dict) for case, values in entry.items() if isinstance(values, dict) for name, value in values.items() if value != value or value == float("inf")])
EOF
```

Expected: merge and morph list 8 cases each (4 normal, 4 `-reduce-motion`), `material.union` 2, `material.morph.plain` 8, `material.respace` 2; `2B.1 spacing floors unchanged: True`; `46 spacing cases`; `[]` for non-finite noise. Every `static mad` ≤ 1.0 (2B.1 measured 0.00). No `FAILED` line.

- [ ] **Step 7: Commit.**

```bash
git add packages/mobile/tool/glass_lab/noise.json
git commit -m "test(glass-lab): native noise floors for every 2B.2 scene and case, five takes over two sessions

Co-Authored-By: <the session's attribution line>"
```

### Task 26: `material.respace`, the native reference for the spacing animation (ruling 12)

**Files:**
- Create: `docs/liquid_glass/02b-motion/research/execution-2b2/respace-*.txt` (evidence)

**Interfaces:**
- Consumes: the scenes of Task 23, the floors of Task 25, the package's animated `spacing` (Task 4), `R/onset/topology_series.py`.
- Produces: whether native animates a container's `spacing`, what it does, and the scene's count in the Done table. **No native evidence for this behaviour exists before this task** (ruling 12); the prototype never recorded the scene.

- [ ] **Step 1: Fresh boot, press check, build.** As Task 25 Step 1, with `lab.py build all`.
- [ ] **Step 2: Record both apps.** `python3 tool/glass_lab/harness/lab.py run material.respace` (native and Flutter, light and dark photo; the steps are `widen` at 0.5 s and `narrow` at 2.0 s). Then `python3 tool/glass_lab/harness/lab.py report build/glass_lab/runs/<run>` and `python3 $R/verify/table.py --harness tool/glass_lab/harness build/glass_lab/runs/<run>`.
- [ ] **Step 3: Read native's frames, not the table.**

```bash
python3 $R/onset/topology_series.py --harness tool/glass_lab/harness --scene material.respace build/glass_lab/runs/<run>/material.respace/light-photo/native > respace-native-light-photo.txt
python3 $R/onset/topology_series.py --harness tool/glass_lab/harness --scene material.respace build/glass_lab/runs/<run>/material.respace/light-photo/flutter > respace-flutter-light-photo.txt
```

Each prints, per video frame of the capture, the time, the pair's component count, its neck thickness and its gap, after each tap. Native **animates** the spacing if, after `widen`, its neck thickens over at least three video frames (about 50 ms) between the first frame in which the pair differs from rest and the frame in which the neck is within 1 pt of its final value; if the neck appears at its final value in one frame, or the join comes within one video frame of the first change, native does not animate it.
- [ ] **Step 4: The decision.** **If native does not animate `spacing`: stop Task 26 here and report to the main session** with the two txt files and the frames (`R/verify/frames_at.py`); do not keep ruling 12's behaviour, do not change the package: ruling 12, the README sentence and Task 4's `spacingTo` and `blendMotion` stay in the tree until the main session decides. **Task 27 may proceed while this stop is active,** with every scene except those Task 26 depends on (`material.respace`, which Task 27 does not run; the `material.spacing.*` scenes of Step 5 keep a constant spacing per scene and do not need the animation); its results record the open decision, and the Done table's spacing-animation row reads `stopped, undecided`. **If native animates it:** the Flutter capture is judged like any scene: record per case `pass / judged / expected`, class each failure (a)–(d) with its number, and say in the report how far Flutter's join and split times and neck series are from native's (`topology.join_ms`, `split_ms`, `neck_rms`, `gap_rms`). A failure is not tuned away: the spring is the package's, and a different native spring is a finding for the main session.
- [ ] **Step 5: Commit the evidence.**

```bash
git add docs/liquid_glass/02b-motion/research/execution-2b2
git commit -m "docs(mobile): native reference for the container spacing animation

Co-Authored-By: <the session's attribution line>"
```

### Task 27: Verification runs and `results-2b2.md` (spec §8, 2B.2)

**Files:**
- Create: `docs/liquid_glass/02b-motion/results-2b2.md`
- Modify: `packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart` (only through `lab.py fitvis --write`, and only if Step 7 re-fits)

**Interfaces:**
- Consumes: everything above; `R/verify/table.py` (per case pass / judged / expected from `result.json`), `done_table.py`, `still_check.py`.
- Produces: the Done table and the run folders, every number recomputable from `result.json` by those scripts.

All of this runs on the package **after** the fix-round tasks (13–24), so its numbers differ from the prototype's (`R/verify/`, the package before them); the prototype's tables are the baseline each measure is compared with by name.

- [ ] **Step 1: Fresh boot, press check, disk.** As Task 25 Step 1 (press check at the start and after about three hours), and `df -h /Users/omaraly` before every `run` of Steps 2 to 9 (stop under 40 GB free and report, ask under 45 GB, delete nothing). `lab.py build all`, then install the backdrops (Execution setup). **A press outside 0.8-1.2 s:** reboot (`lab.py reboot`), run the check again, and record nothing until it reads inside the range; a stale press spoils the native recordings only, but `run` records both apps, so the runs recorded since the last good check are set aside (`excluded/`, with a line saying why) and recorded again after the reboot; never count or class a case from a run recorded under a failed check.
- [ ] **Step 2: Merge, normal and Reduce Motion.**

```bash
python3 tool/glass_lab/harness/lab.py run material.merge
python3 tool/glass_lab/harness/lab.py run material.merge --a11y reduce-motion
```

- [ ] **Step 3: Union.** `python3 tool/glass_lab/harness/lab.py run material.union`
- [ ] **Step 4: Morph and its plain control, normal and Reduce Motion.**

```bash
python3 tool/glass_lab/harness/lab.py run material.morph
python3 tool/glass_lab/harness/lab.py run material.morph --a11y reduce-motion
```

(`material.morph` selects `material.morph.plain` too.)
- [ ] **Step 5: The N7 spacing scenes.** `python3 tool/glass_lab/harness/lab.py run material.spacing --backdrop photo` (all 23 scenes, light and dark; `material.respace` is not selected by this prefix).
- [ ] **Step 6: Report, count, and check the topology masks on Flutter frames.** For each run:

```bash
python3 tool/glass_lab/harness/lab.py report build/glass_lab/runs/<run>
python3 $R/verify/table.py --harness tool/glass_lab/harness build/glass_lab/runs/<run>
```

Per case this prints `pass / judged / expected`. The counts are compared **by measure name** with the baseline tables (`R/verify/logs/table-newmanifest-*.txt` for merge and morph: the same measures on the prototype's recordings, at the package before Tasks 13–24; `R/verify/logs/table-*.txt` for the rest), not by total: `expected` is not constant between takes (`material.morph dark-photo-reduce-motion` 29 / 64 / 180 and `material.morph.plain dark-photo` 22 / 65 / 180 against 126 for the other cases of the same scene). Expected: every measure that passed in the baseline still passes unless its case now has a floor that can only have raised its limit; `events` `[2, 2]` and `touches` `[2, 2]` except for captures that fall in a class (d) hole (repeat those cases alone with `--appearance` and `--backdrop`). Every failing measure is classed (a)–(d) with a number and a crop (`R/verify/crop.py`, `frames_at.py`). **Hold-out for the topology masks** (ruling 2): for one Flutter merge case and one Flutter morph case, write down from the frames (`frames_at.py` sheets) whether the pair, and the stack, is one piece or more at 24 frames each, and compare with the mask's `count` per frame; report every disagreement as class (c) and do not tune the threshold.
- [ ] **Step 7: Materialize with the H4 exponents.** The fitted exponents stay fixed. Before anything reads `noise-2b1`, check that Task 3's exclusion holds: `test ! -e $NOISE/takes/material.materialize/light-photo-reduce-motion/2 && test -d $NOISE/takes/material.materialize/light-photo-reduce-motion/5` (a re-fit that read the bad take 2 would reproduce 2B.1's `cy.peak_ms` 150). **Recompute check with the final harness:** Task 3 wrote its `noise.json` entry with the harness as it was before Tasks 5, 6, 9 and 12 changed `analyze`, `shapes` and `track`. Without recording anything, recompute the Task 3 case with the final `lab.py` and compare with Task 3's file: `git show <Task 3 commit>:packages/mobile/tool/glass_lab/noise.json > /tmp/noise-task3.json; python3 $R/noise_recompute.py --harness tool/glass_lab/harness --run $NOISE --before /tmp/noise-task3.json --out /tmp/noise-final-moved.json material.materialize/light-photo-reduce-motion`. Expected: no value and no limit moved; **if any did, list each moved limit in `results-2b2.md` (name, Task 3's value, the final harness's value) and do not edit `noise.json` by hand: the main session decides**. `lab.py run material.materialize` (default, `.snappy`, `.bouncy`), normal and `--a11y reduce-motion`, then `python3 tool/glass_lab/harness/done_table.py <both runs>`. Expected: about 289 / 334 / 336 (the prototype's 144 + 145; **this count is in-sample for the exponents, ruling 22, and was judged under the new gotcha 52 floors where 2B.1's 266 of 336 was judged under the old: say so**); a re-fit (`lab.py fitvis <runs> noise-2b1 --write`) is made only if a measure moved by more than its noise, is reported as a change of the fitted table with the measures that moved, and `ios27MorphContentBlur` survives it (Task 12).
- [ ] **Step 8: Reduce Motion, native merge.** Compare the native merge's Reduce Motion cases with ruling 14's spring ranges; they must agree.
- [ ] **Step 9: Still glass no worse than 2A.** Run every 2B.1 still scene and compare against 2B.1's runs in the archive (`/Users/omaraly/development/AI/glass-lab-runs/2b1/runs/`): `material.regular` (`20261006-165449`), `material.clear` (`-170542`), `material.tinted` (`-171006`), `material.edge` (`-171635`), `material.regular --a11y reduce-transparency` (`-172307`), `--a11y increase-contrast` (`-173358`), `tabbar.rest --flutter operator` (`-174454`), `button.press --flutter operator` (`-175336`), `navbar.inline --flutter operator` (`-175623`):

```bash
python3 tool/glass_lab/harness/still_check.py /Users/omaraly/development/AI/glass-lab-runs/2b1/runs/<2B.1 run> build/glass_lab/runs/<new run>
```

Expected: `missing: 0` and `worse: 0` in each. **This compares with 2B.1's runs, a ratchet (each plan may drift by the allowed noise); the spec's reference is 2A (`7e318a49f`), whose runs are not in the archive. It covers pinned groups only (D1, accepted by the user): no 2A still scene has an unpinned container of members of different sizes (the nine scenes are standalone glass or the app's `GlassScope`, which pins `side` and `spacing: 20`), so a pass here says the shader rewrite and the pinned path are no worse and says nothing about the median member's row for mixed sizes; per-glass materials in one layer are the carry-in to project 3.** The default spacing changed to 8 pt and the container material now follows its members (ruling 30), so a failure here is a scene that relied on 20 pt or on the 88 pt row: give it `spacing: 20` or `side: 88` (as the app's `GlassScope` does for spacing), not a loosened measure. **If a pixel difference remains with `spacing: 20` and `side: 88` pinned, stop and report to the main session: the shader rewrite (`angleSmoothUnion` and the generic loop in `sdf.glsl`) touches every container scene and is the cause to suspect; do not tune it.**
- [ ] **Step 10: Gates.** The four gate commands of Execution setup, at the final tree. Record the counts.
- [ ] **Step 11: Write `results-2b2.md`** from the template below, with the run folders, the counts and the classed failures, and commit it with the runs' `table-*.txt` outputs under `docs/liquid_glass/02b-motion/research/execution-2b2/`.

```bash
git add docs/liquid_glass/02b-motion/results-2b2.md docs/liquid_glass/02b-motion/research/execution-2b2
git commit -m "docs(mobile): 2B.2 results

Co-Authored-By: <the session's attribution line>"
```

**`results-2b2.md` template.**

```markdown
# 2B.2 results

Date: <date>. Branch `feat/ios-liquid-glass-2b2`. Measured at `<sha>`. Noise floors: Task 25's, five takes per case over two boots; the six 2B.1 spacing scenes keep 2B.1's. Decisions taken: D1 A (ruling 30; the median member's row accepted by the user; the still check covers pinned groups only; per-glass materials in one layer carried to project 3), D2 A (ruling 31), D3 A (user-approved manifest correction of 2026-10-07, ruling 26; morph tracked at the stack's outer edges only, the heart and the bolt not tracked individually, carried to 2B.3 or a fix wave), D4 hand-placed 1.5, not tool-written (ruling 23), D5 (onset frame fixed, the rest carried), D6 spacing animation kept (ruling 12): <native animates `spacing`: yes | no, stopped>.

## The Done table

| Done item (spec §8, 2B.2) | Result | Evidence |
|---|---|---|
| 1 `material.merge`, `material.union` and `material.morph` pass, normal and Reduce Motion: per-shape motion, join and split timing, neck width over time, component count | <Pass | Partly failing | Failing>. Merge normal <dark-photo p/j/e, dark-stripes, light-photo, light-stripes>; Reduce Motion <…>. Morph normal <…>; Reduce Motion <…>; plain <…>. Union <…>. | run folders; `table-<run>.txt` |
| 2 The rebuilt union scene passes its still-image measures | <…> light-stripes <p/j/e>, dark-stripes <p/j/e> | <run>, ruling 17 |
| 3 The N7 spacing scenes pass their still-image and topology measures | <n> of 46 cases pass; counts agree at <…>; necks within <…> | <run> |
| 4 Still glass is no worse than 2A; gates | still: `missing: 0`, `worse: 0` in <9> scenes, <n> of <m> Flutter frames byte-identical; gates: app `+<n>`, package `+<n>`, example `+<n>`, harness <n> OK, all three `flutter analyze` clean | <runs> |
| (carried) 2B.1 Done item 4 | materialize <pass> / <judged> / 336, **judged under the gotcha 52 floors of Task 3 and with exponents fitted on the same takes (in-sample, ruling 22); 2B.1's 266 of 336 was judged under the old floors: not the same yardstick** | <runs> |
| (new) Spacing animation, ruling 12 | native animates `spacing`: <yes | no>; `material.respace` <p/j/e> light photo, dark photo; join and split times native <…> Flutter <…> | Task 26 |

## Judged / expected counts (passing / judged / expected)

| Scene | Appearance | Normal | Reduce Motion |
|---|---|---|---|
| `material.merge` | dark photo | <…> | <…> |
| `material.merge` | dark stripes | <…> | <…> |
| `material.merge` | light photo | <…> | <…> |
| `material.merge` | light stripes | <…> | <…> |
| `material.morph` | (4 cases) | <…> | <…> |
| `material.morph.plain` | (4 cases) | <…> | <…> |
| `material.union` | dark stripes, light stripes | <…> | not applicable |
| `material.spacing.*` | 23 scenes, light and dark photo | <n> of 46 cases | not applicable |

## Merge and morph, the old and the new manifest on the same recordings (D3)

Prototype recordings at the package before Tasks 13–24; counts are passing / judged (finite) / expected. The manifest correction is the user's (2026-10-07), not a loosening: ruling 26.

| Run (prototype) | Case | Old manifest | New manifest | Final package, Task 27 |
|---|---|---|---|---|
| `20261007-054755` merge | dark photo, dark stripes, light photo, light stripes | 20/41/66, 24/45/66, 25/44/66, 25/46/66 | 24/61/68, 30/67/68, 29/62/68, 33/68/68 | <…> |
| `20261007-055356` merge, Reduce Motion | same four | 20/41/66, 22/45/66, 27/46/66, 26/46/66 | 24/63/68, 26/67/68, 33/68/68, 32/68/68 | <…> |
| `20261007-060205` morph and plain | same four each | normal 19/59/126, 24/55/126, 29/55/126, 31/58/126; plain 22/65/180, 17/61/126, 25/59/126, 16/36/126 | normal 25/73/148, 28/69/148, 33/69/148, 36/72/148; plain 27/80/213, 21/75/148, 29/73/148, 17/43/148 | <…> |
| `20261007-061306` morph and plain, Reduce Motion | same four each | 29/64/180, 26/59/126, 34/60/126, 39/62/126; plain 21/62/126, 26/60/126, 31/60/126, 29/60/126 | 35/79/213, 31/73/148, 40/74/148, 47/76/148; plain 28/76/148, 35/74/148, 37/74/148, 36/74/148 | <…> |

## Gotcha 52, the limits that moved

<the list from Task 3 Step 3, with the limits that rose named (the prototype's three: `block.step1e0.cx.peak_ms`, `block.step1e0.width.response_pct`, `block.step3e0.luma.peak_ms`) and the take that set each>

## Failures, classed

| Measure | Case | Class (a)–(d) | Value against limit | Evidence (run, crop) |
|---|---|---|---|---|

## Provisional limits

<none after Task 25, or the list of measures still judged on a fixed threshold because their case has no floor, and why>

## Open

Merging 2B.2 with failing Done items is the user's decision on the classed failures (spec §8), not a pass; <state which of items 1–3 fail>.

<the package defects of ruling 21 that remain (the toggle's swelling, merge and split timing and hysteresis, one spring for every arrival, content sharpening order); the open items: the native control that would separate the emergence and sink hypotheses (ruling 18), a tracker for the inner glasses of the morph (ruling 26), a native frame of a union member appearing (ruling 16), per-member material rows inside one layer (ruling 30), `fitvis` writing `ios27MorphContentBlur` (D4); what Task 26 decided about the spacing animation>
```

## Self-review

- **Spec coverage (2B.2, spec §4 and §8):** M4 merge and split (Tasks 4, 6; rulings 7–14), container spacing animation (Task 4, ruling 12; its native reference Tasks 23 and 26), M5 union (Task 8; D1, D2: Tasks 20–22), M6 morph (Task 11; Tasks 13 and 15 for the swap and the cap), the lab's topology, gap and manifest corrections (Tasks 1, 5, 6, 19), H4 (Task 10), gotcha 52 (Task 3), the first frame of a move (D5: Tasks 16–18), L8 for every 2B.2 scene (Task 25), N6 for merge and morph (native Reduce Motion references recorded in the prototype, rulings 14 and 18; re-recorded in Task 27), §9's 16-shape test (Task 15), Done items 1–4 (Task 27).
- **Placeholders:** none in the code steps; every code step is a patch that ran in the prototype or in the fix round, and the replay applied them all. Tasks 3, 25, 26 and 27 are recordings and verification with no prototype counterpart (the user's reduced scope, 2026-10-07; Task 3's `noise.json` is made by the executor); their expected numbers are the prototype's end-to-end numbers on the package before the fix round, said so, or, for `material.respace`, none.
- **Review Focus:** every line names the test or check that pins it; what is not pinned is said (Review Focus 12).
