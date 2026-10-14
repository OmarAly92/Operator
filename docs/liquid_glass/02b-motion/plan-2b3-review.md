# Independent review of the ios_liquid_glass 2B.3 plan

Reviewed: `docs/liquid_glass/02b-motion/plan-2b3.md` at `proto/2b3` `721468412` (4,003 lines, 16 patches, 30 RUN lines, rulings 1 to 17, decisions D1 to D9). Nothing in the prototype worktree was edited; this file is the only new file there and is not committed.

Where I worked:
- `/Users/omaraly/development/AI/Operator-2b3-review`: a fresh `git clone` of the prototype at `721468412` (gates, recomputes, my copies of the recordings under its `packages/mobile/build/glass_lab/`, frame caches excluded, so nothing was written into the prototype's runs or the archives).
- `/Users/omaraly/development/AI/Operator-2b3-review-replay`: a worktree of that clone at `development` `c0e69d9a4` with `research/proto-2b3/` committed into it, as Execution setup does (replay).
- `/Users/omaraly/development/AI/Operator-2b3-review-a9`: a worktree of that clone at `abe33abbc` (Task 14 Step 4 precondition).
- Scratch outputs: `/private/tmp/claude-501/-Users-omaraly-development-AI-Operator/3cb31e11-a739-49c0-9569-54a30de0cbb4/scratchpad/rev/` (`gates-proto/`, `replay-out/`, `patches/`, `reproduce-glow.txt`, `nq-mine.txt`, `pressfit-mine.json`).
- One simulator check (F9): reboot of `708879DD-8B2A-4547-863F-F49EE1474D8B`, then `lab.py run material.interactive --app flutter --appearance light` from the review clone (run `Operator-2b3-review/packages/mobile/build/glass_lab/runs/20261009-081334`; a first attempt `-081301` failed because the clone had no native driver build). Nothing else ran during it; accessibility settings read `0` afterwards; no `recordVideo` left running. The iOS 26.5 simulator was not touched.

## Verdict

**Ready to execute: no.**

The code is honest: every patch is byte-identical to the prototype's commits, the replay reproduces every red and green, and the gates match the stated counts. Most numbers I recomputed match too. The problems are in the measurement and the model:
- The plan lets capture-hole takes into the references and the noise floors, and those takes corrupt the press timing measures. That would raise limits without anyone noticing (F1).
- The forecast rests on prototype comparisons whose takes mostly fail `take_check` (F2).
- Three fitted parts of the press model are built wrong: overshoot is counted twice in the size law (F3), the glow width is fitted on pixels outside the glass (F4), and the cut time ignores a clear size dependence (F5).
- The forecast leaves out failures the prototype already showed (F7), and two of the departures from the spec go further than their evidence (F8, F10).

F3, F4 and F5 change `pressfit.py` and so the tool-written `ios27_press.dart`. The prototype has to be re-run and the plan regenerated, because the plan's table check (Task 4 Step 5) pins the current output byte for byte.

Counts: blocker 1 (F1), major 11 (F2 to F12), minor 9 (F13 to F21).

## Gate results (fresh clone of `721468412`)

| Gate | Plan | Mine |
|---|---|---|
| Harness `python3 -m unittest discover tool/glass_lab/harness/tests` | `Ran 274 tests`, OK | `Ran 274 tests in 96.4s`, `OK` |
| Package `flutter analyze` / `flutter test` | clean, `+273` | `No issues found!`, `+273: All tests passed!` |
| Example | clean, `+25` | `No issues found!`, `+25: All tests passed!` |
| App (`packages/mobile`) | clean, `+2187` | `No issues found!`, `+2187: All tests passed!` |

(`scratchpad/rev/gates-proto/*.txt`.) The SkSL `impellerc` error appears once in the app log, as gotcha 3 says it will.

## Code diff result

- I wrote my own extractor for the plan's 16 `Patch` blocks (`scratchpad/rev/extract.py`). Each block is **byte-identical** to `git diff --full-index <base> <head> -- <files>` over the range and files the plan names (16 of 16).
- The union of the patch files is exactly the 31 files under `packages/` that `c0e69d9a4..721468412` changes. No code file is missing and none is extra.
- The prototype worktree has no uncommitted changes (`git status --short` is empty).
- One small point. Two patches start from the final test file rather than the commit the implementation came from: `t01-tests` (from `a3026d856`) is applied against `t01-impl` (from `d65ef3a94`). This is deliberate, and it passes (11 tests).
- `t08-impl` adds a blank line at the end of the file (`git apply` prints "1 line adds whitespace errors") and a blank line between two imports (minor, F21).

## Replay spot-check

On `Operator-2b3-review-replay` (`development` `c0e69d9a4`, evidence committed) I applied **all 16 patches** in order with `git apply --3way`. I ran the fail-first and pass steps of Tasks 1, 3, 4 (including the table check), 5, 7, 9 and 10, plus Task 1's harness gate and Task 2's manifest check (`scratchpad/rev/replay-out/summary.txt`):
- Task 0: `52 packages have newer versions …` (matches).
- Task 1 red: `ModuleNotFoundError: No module named 'press'`. Green: `Ran 11 tests`, OK. Gate: `Ran 264 tests`, OK.
- Task 2 manifest: `Ran 22 tests`, OK.
- Task 3 red: `ModuleNotFoundError: No module named 'pressfit'`. Green: `Ran 8 tests`, OK.
- Task 4 red: compile failure (`Error when reading 'lib/src/motion/glass_press.dart'`, so it fails for the stated reason). Green: `+48: All tests passed!`. Table check: `table reproduced by pressfit`.
- Task 5 red: `Expected: no matching candidates … Found 1 widget with type "RawLiquidStretch"`. Green: `+1`.
- Task 7 red: `FAILED (failures=3)`. Green: `Ran 6 tests`, OK.
- Task 9 red: the three named tests fail. Green: `+11`.
- Task 10: `1`.
- After the last patch, all 31 package files are `cmp`-identical to `a3026d856`.

The writer's replay claim is honest. Two small remarks:
- The `replay-1.log`, `replay-2.log` and `replay-3.log` that the plan cites are ignored by git (`.gitignore:6 *.log`), and `plan/replay-result.txt` is empty (F15).
- Task 14 Step 4's precondition holds: HEAD's `perf_scenes.dart` copied into `abe33abbc` analyzes clean (`No issues found!`).

## Recomputed numbers

| Claim (plan) | Source I used | Mine | Verdict |
|---|---|---|---|
| L4 on v13 dark-stripes: rise 35 ms, fade 403 ms, +12 / +4.67 pt, growth to 90 % in 210 ms, drop 11.23 at 403.3 ms | `reproduce.py glow` on copies of `P-20261003-012138` and the others | 35.0, 403.334, 12.0 / 4.667, 210.0, 11.231 at 403.334 | reproduced |
| light-photo +19.00 / +19.05; N1 dark-photo +20.61, drop 11.39 at 400.0; N2 drops at 380–423 ms | same run | 19.004 / 19.052; 20.612, 11.391 at 400.0; 380.0–423.3 | reproduced |
| Size law min(16.78, 1015/h), in-sample RMS 0.64 against 0.35, held-out 0.81 against 1.29 | `pressfit.fit_growth_law` on `R/native-press.json` | 16.78 / 10.15; 0.636 / 0.355; 0.812 / 1.287 | reproduced, but the law is fitted on the **peak** (F3) |
| Springs and delays: growth 51.5 ms, 0.26 / 0.615; release 19.9 ms, 0.33 / 0.615; light 0.06 / 1.945, jump 0.025, hold 56.7 ms, fade 0.385 / 1.055 | `pressfit.py fit` on the same inputs | identical to `R/pressfit.json` (whole JSON equal) | reproduced. 7 of 12 per-take rise fits sit on the spring grid edge (F6) |
| Hold about 11 luma (10.97–11.41, 0 at 360 × 200); swell centre 14.8–15.7, 11.1 (250 × 44), 39.4 (58 circle) | `pressfit.json` sizes | same | reproduced |
| Sigma 61 pt, RMS 3.96 over 133 rings | `fit_sigma` on `R/glow-profile.json` | 61.0, 3.957, 133 rings | reproduced, but it is an artefact: masked to the capsule, **86 pt, RMS 0.32** (F4) |
| Cut 380–665 ms, median 422.5 ms, "12 takes" | `glow_drop_ms` of the 12 first presses | 10 cuts (360 × 200 has none), 380.0–665.0, median 422.5 | number reproduced, count wrong (F18). The cut follows area, r = −0.88 (F5) |
| Press-drag cut 526–650 ms | N1 step 3 | 526.7–650.0 | reproduced |
| Reduce Motion cut 558–570 ms, "two takes, three touches" | `060049` steps 1 and 3, `060150` | 570.0, 568.3, 558.3. The fit uses one press (`reduce_motion_cases: 1`) | reproduced; the shipped 0.57 s comes from one press (F6) |
| Rulings 3, 4, 10 (drag, neighbour and Reduce Motion features) | `native_questions.py` on my copies of the 8 takes | every value identical to `R/native-questions.txt` (only the key prefix `glow_` differs, so the committed text came from an earlier printer) | reproduced, but see F8 and F10 |
| Content scale v18 × 1.067 / × 1.066, v17 × 1.113 / × 1.131 | not re-run (needs the spike's label folders; frames read by eye in the crops only) | – | not recomputed |
| Perf: material 13.41, motion 14.50 (+8.1 %), slide 15.16 (+13.0 %); frames 1440 / 979 / 808 | `R/perf-1.json` | 14.501 / 13.4115 = 1.081; 15.1595 / 13.4115 = 1.130; 360 / 245 / 202 frames per take | reproduced from the JSON; no pairs to recompute (the plan says so) |
| Press floor probe (250 × 44 dark-photo): `glow_rise_ms` 28.33, fade and drop 23.33, `grow_ms` 15.0, `shrink_ms` 33.33, `grow_w` 0.33, `glow_drop` 0.55, `centre` 0.15 | `native_questions.py` on copies of archive `noise-2b1` takes 0–4; noise is the worst pair, which is max − min (`lab.case_noise`) | 28.33, 23.33, 15.0, 33.33, 0.33, 0.55, 0.15 | reproduced. The 28.33 comes from the one take with a 380 ms gap (take 4, rise 28.3 against 50–56.7), which is F1 in miniature |
| Still check `material.tinted`: 12 frames byte-identical, `missing: 0`, `worse: 0` | `still_check.py` archive `20261008-232144` against prototype `20261009-071450` | same | reproduced |
| Forecast row, 250 × 88: fails `glow_rise_ms` 33.3 and `grow_ms` 78.3; press-drag fails `glow_drop_ms` 101.7, `grow_ms` 20, `shrink_ms` 100 | `20261009-063647/.../result.json` | same numbers. Also fails `events.unpaired` 2, `step1e2.delay_ms` 81.7 > 32.5, `step3e1.delay_ms` 200 > 55, `ready/settled.bbox_pt` 2.0 > 1.0 | contradicted as complete (F7). Both takes fail `take_check` (F2) |
| Forecast row, 360 × 200: fails `grow_w` 2.0, `grow_ms` 75, `shrink_ms` 180 | `R/flutter-press-2.txt` | same, plus `glow_fade_ms` 66.7. The Flutter take is squeezed (`press 0.678 s`) | contradicted (F2, F7) |

## Findings

### F1 (blocker): the plan admits takes whose capture holes corrupt the press timing measures, into the references and the noise floors

- **Where.** Task 11 Step 3 and Task 12 Step 5 (which uses Step 3's rule). Ruling 16 says "their touch windows and features agree with the unflagged takes'". Task 14 Step 1 checks the native takes with the same rule.
- **What the rule says.** A burst "after the still screen that ends at touch-down" is accepted, because "its frames sit before the first changed frame".
- **Evidence that it is wrong.** The burst frames are the first frames after touch-down. The event onset is the touch-down frame, and the squeezed frames follow it (`R/take-check.txt`: `060244` onset 17.453 = touch-down, gap 403.3 ms, then frames 3.3, 1.7, 3.3 and 1.7 ms apart). The timing they give is wrong:
  - `material.interactive` dark-photo `060244`: rise 0.0 ms and `grow_ms` 90, against 55 and 215 in the clean N1 take `20261006-085522`;
  - `material.neighbours.10` left: rise 0.0 and `grow_ms` 20.0, against 85 and 155 at gap 40;
  - `material.drag.out`: rise 0.0.
- **2B.1's takes are clean.** I ran `take_check.py` on 30 copied 2B.1 press noise takes (250 × 44, `material.interactive` and circle58, dark and light `photo`). All 30 PASS and none has more than a one-frame burst. Even that one burst moves the rise: take 4 of 250 × 44 reads 28.3 ms against 50–56.7, and that single take sets the case's `glow_rise_ms` noise to 28.33.
- **The new takes are not.** The pattern hits 6 of the 9 prototype question takes. It also hits both of my Flutter light takes (`20261009-081334`, `capture hole at step 1` in both). Under today's recording conditions it is the common case, not an outlier.
- **Consequence.** Noise is the worst pair (`lab.case_noise`), so one burst take in a case lifts `glow_rise_ms` and `grow_ms` limits by 50–200 ms. Flutter's timing differences then pass vacuously. The limit has been loosened without being declared, and 2B.1's own exclusion rule (gotcha 47, "18 takes excluded") has been relaxed without saying so.
- **Fix.**
  - Treat any burst of two or more frames under 5 ms apart, within 150 ms after touch-down or touch-up, as a capture hole. Re-record the take, or make `press.features` return `None` (absent) for the time measures of the affected step on that take and keep it out of the floors.
  - Pin the rule with a synthetic-burst test in `test_press.py`.
  - Write the rule into Tasks 11, 12 and 14, and budget for re-recording: the prototype's hit rate suggests most takes.
  - Report, in the noise file, which takes set each time limit (the gotcha 52 rule).

### F2 (major): the forecast's Flutter-against-native comparisons are built on takes that fail `take_check`

- **Where.** "What this plan expects to reach", item 1, and ruling 12 (`20261009-062606`).
- **Evidence.** I ran `take_check.py` on every take of the six comparison runs:

  | Run | Scene | Native | Flutter |
  |---|---|---|---|
  | `062606` | `material.interactive` | hole at step 3 | hole at step 1 |
  | `062805` | 250 × 44 | PASS | hole at step 1 |
  | `062924` | 360 × 200 | PASS | PASS |
  | `063647` | `material.interactive` | hole at step 3 | hole at step 1 |
  | `063817` | 250 × 44 | hole at step 1 | hole at step 1 |
  | `063941` | 360 × 200 | hole at step 1 | **press 0.678 s** and a hole |

- So the 360 × 200 row of the forecast compares a squeezed Flutter recording (Flutter rise 0.0, `grow_ms` 25) with a holed native one. Ruling 12's evidence (`062606`: Flutter `grow_ms` 0) is also a holed Flutter step 1.
- The "native spread is wide" argument (`grow_ms` 90, 143, 210, 215) includes the holed 90 from `060244`.
- **Fix.** Re-run the three comparisons on clean takes, or drop the per-measure pass/fail lines from the forecast and say they are not evidence.

### F3 (major): the size law is fitted on the peak growth and then used as the target of a spring that overshoots, so the overshoot is counted twice

- **Where.** `pressfit.fit_growth_law` reads `features["grow_w"]`, the largest growth during the touch (`press.py`). `GlassPress.scaleFor` multiplies `widthGrowth(size)` by the growth spring's value. That spring (0.26 s, damping 0.615) peaks at 1.0863 of its target (springfit, my run).
- **Evidence.**
  - Native's peak growth exceeds its 0.3 s plateau by 4–9 %: 12.00 against 11.33 (250 × 88), 17.00 against 16.33 or 16.00 (250 × 44), 16.67 against 15.33 (138 × 53), 8.67 against 8.33 or 8.00 (300 × 120); from `R/native-press.json`.
  - So Flutter's peak is about 1.086 × law: 12.53 at h 88 and 18.23 at h 44.
  - Measured: Flutter `grow_w` 12.667 against native 12.0 (`063647`), 18.333 against 17.0 (`062805`, `063817`), and 12.667 against 12.0 on light-photo (my run `081334`).
  - The plan classes 250 × 44's 1.33 pt as an expected class (a) failure, and the 360 × 200 miss as the law's fault.
- **Refit on the plateau.** min(15.84, 962/h); held-out RMS 0.771 (inverse) against 1.053 (power). This predicts Flutter peaks of 17.21 at h 44 and 11.88 at h 88, both within 0.25 pt of native.
- **Fix.** Fit the law on the plateau, which `growth_fit` already computes. Add a test in which a spring-driven synthetic series is not double counted. Correct the README's numbers ("grows by min(16.78, 1015 / height)") to say settled growth.

### F4 (major): the glow's width (sigma 61 pt) comes from rings that include pixels outside the glass

- **Where.** `pressfit.glow_profile` bins the change over the whole bounding box. It does not mask to the shape, although the same file has `inside_shape`. Task 13 Step 2 re-uses it.
- **Evidence.** Same take (`20261009-060049`) and same hold (11.581):
  - unmasked: sigma 61, RMS 3.957 luma (reproduced);
  - masked to the capsule: **sigma 86 pt, RMS 0.324 luma**, over 125 rings.
  - The unmasked profile falls from 16.5 to 0.02 luma between 104 and 128 pt only because the box corners outside the capsule carry no change. Inside the capsule the light is 24.8 at the centre and still 16.4 at 120 pt.
- The per-size swell strengths in `ios27_press.dart` depend on sigma through `gaussian_mean`, so they move too.
- **Fix.** Mask the profile with `inside_shape`, refit, and add a test with corner pixels.

### F5 (major): the one-frame cut depends on glass size, and the single median misses the small sizes by 100–240 ms

- **Where.** Ruling 7 ("cause not known"), `ios27PressGlowCut = 0.4225`, and the forecast table, which names only the press-drag cut.
- **Evidence.** The 10 native cuts against log area, dark / light:

  | Size | Cut (ms) |
  |---|---|
  | circle58 | 613 / 652 |
  | 138 × 53 | 530 / 665 |
  | 250 × 44 | 422 / 423 |
  | 250 × 88 | 400 / 410 |
  | 300 × 120 | 383 / 380 |

  The correlation is r = −0.88. A line in log area leaves RMS 53 ms; the median leaves 128 ms.
- The median misses circle58 by 191–229 ms, 138 × 53 by 108–243 ms and 300 × 120 by 39–43 ms. Native's own floor for `glow_drop_ms` is 21.7–26.7 ms (limits 32.5–40), so those cases fail, and so does `glow_fade_ms`, which equals `glow_drop_ms` whenever there is a cut (F13).
- **Fix.** Put the cut in `pressfit`'s size table and interpolate it in log area, as the hold and swell already are. Fit it on Task 13's 72 takes. Otherwise list these failures in the forecast. Ruling 7's "nor the hold level, nor the swell's decay" never tested size.

### F6 (major): `pressfit` refuses grid-edge values only for the law and sigma; most light fits sit on the spring grid's edge, and the Reduce Motion cut is one press

- **Where.** `pressfit.problems()`. Review Focus 5 says `pressfit` "refuses a summary with a missing fit or a grid-edge value".
- **Evidence.** The springfit grid is response 0.05–1.5 and damping 0.1–2.0 (`springfit.py:3-4`). Per-take rise fits:
  - response 0.05 (the floor) in 4 of 12;
  - damping 2.0 (the ceiling) in 4 of 12, 7 takes in all;
  - fade damping 2.0 in 2 takes.
  - The shipped medians, 0.06 / 1.945, sit one step from the edges.
  - `reduce_motion_cases: 1` (`R/pressfit.json`): `ios27PressReduceMotionGlowCut = 0.57` is one press of one take.
- **Fix.**
  - Count per-take grid-edge fits in `problems()`, and refuse when more than a fixed share of them sit on an edge, or widen the grid below 0.05 s.
  - Refuse a Reduce Motion cut from fewer than five presses.
  - Say in Review Focus 5 exactly which values are guarded.

### F7 (major): the forecast leaves out failures the prototype already showed, and Done item 3 is forecast as passing although "Reduce Motion everywhere" carries 2B.1's and 2B.2's failures

- **Evidence.**
  - `20261009-063647/material.interactive/dark-photo/result.json` (the only prototype Flutter run that was analysed) also fails `motion.events.unpaired` 2 (native 7 events, Flutter 5) and `step1e2.delay_ms` 81.7 > 32.5. The 2B.1 and 2B.2 practice is that the event gate passes (120 of 120).
  - The same run fails `step3e1.delay_ms` 200 > 55, and `ready.bbox_pt` and `settled.bbox_pt` 2.0 > 1.0.
  - 360 × 200 also fails `glow_fade_ms` (66.7).
  - My Flutter light run (`081334`) fails `glow_peak` on light-stripes: 15.35 against native 11.87 (N1), 3.48 > 3. Light-photo reads 21.94 against 19.02 (2.92, at the line). Flutter's additive light does not dim over white the way native's does, and the prototype never ran a light case.
  - Done item 3, "Reduce Motion runs pass", under spec §4's "Reduce Motion everywhere": materialize under Reduce Motion is 133 of 168 (`results-2b1.md`), and merge and morph under Reduce Motion fail (`todo-2b2.md`). The plan keeps those results unchanged and still forecasts only items 1 and 2 as failing.
- **Fix.** State that items 1, 2 and 3 fail in part, and the event gate as well, with these numbers. Run one light and one stripes case of each press size in the prototype before the forecast is written.

### F8 (major): the neighbour scenes do not judge "absence" at gaps 0 and 10, and the neighbour's rest box covers only part of the glass

- **Where.** Ruling 4; Task 2's "Why" ("neither region holds the other glass"); the forecast ("passing on absence for the neighbours").
- **Evidence.**
  - Native's `right` measures at gap 0 read `grow_h` 3.0 pt, `centre` 1.5, `stretch` −0.042. At gap 10 they read `grow_w` 5.667, `stretch` 0.047, `centre` 2.833, `grow_ms` 20 and `shrink_ms` 135 (`R/native-questions.txt`, which I reproduced). This is the pressed glass's growth crossing the midline and the merge bridge, not the neighbour.
  - Flutter is therefore judged on its merge bridge. 2B.2 left that failing (todo-2b2 merge rows: neck 13.7–14.3 against 17.7–26.7 pt, joins and splits late). Failures there will look like "the neighbour scales".
  - The `right` rest box on dark `photo` is 121 × 67.67 pt (gaps 0 and 10) and 121.33 × 56.67 pt (gap 40), against the 120 × 88 glass. In the crop of `20261009-055951` `ready.png`, the lower part of the right glass over the green gradient barely differs from the bare frame, so the neighbour's glow is measured over its top 64–77 % only.
- **Fix.**
  - Judge the neighbour on `glow_peak` and the time measures inside a pinned layout rect, and leave out the band within (law growth + `spacing`) of the facing edge.
  - Or forecast the gap 0 and gap 10 size measures as merge-model failures (todo-2b2), not press.
  - Check the box on light backdrops in Task 11.

### F9 (major): the light model is untested on light backdrops and on stripes, and on light stripes it already fails

- **Evidence.** My simulator check (`20261009-081334`, Flutter only, after a reboot) against N1 native `20261006-085522`:

  | Case | Flutter `glow_peak` | Native `glow_peak` | Difference |
  |---|---|---|---|
  | light-stripes | 15.35 | 11.87 | **3.48 (fail)** |
  | light-photo | 21.94 | 19.02 | 2.92 |

  Over light-stripes the drop is 7.86 against 6.24. Native's light is weaker over bright content than a plain additive light. The plan's "luma rises by 255 × alpha where it does not clip" (ruling 6) was only tested on dark `photo`.
- **Fix.** Fit the light's strength on all four N1 cases and the N2 light cases, not on `photo` alone. Check whether native's rise depends on the content's luma, for example by applying alpha to (255 − L). Add the light cases to the prototype's comparison before the forecast is written.

### F10 (major): "leaving the glass does not release it" is generalised to any distance from one take that ends 40 pt outside

- **Where.** Ruling 3, the README ("Leaving the glass does not release it"), and `RenderGlassPressTarget`, which never releases on distance.
- **Evidence.** `material.drag.out` (`20261009-055711`, one take, holed at step 1) stays grown while the finger is up to 40 pt outside. Nothing shows what native does at 100 or 300 pt, or off the top. The package keeps the press at any distance.
- A skeptic would expect a release distance. UIKit controls keep tracking within a margin around their bounds, not at any distance. That is not known for glass, which is exactly why it should be recorded.
- **Fix.** Add a far drag to Task 11, for example +300 pt, plus one vertical exit. Keep the README to what was measured ("within 40 pt") until it exists.

### F11 (major): the Operator swap is small in code but not in effect, and its tests lost their behavioural assertions

- **Where.** Task 9 and D9.
- **Evidence.**
  - `GlassButton.icon` and `GlassBarItem` default to 44 × 44, which is outside every measured size: the smallest native press is the 58 pt circle (area 3364), and 44 × 44 is 1936. The law gives +16.78 pt, a ×1.381 scale of glass and content. `_PressLift` was ×1.08.
  - The light holds the circle58 end values: 39.4 luma swell plus about 11 luma hold.
  - Compact 36 pt capsules sit inside a 44 pt hit area. A tap at the margin fires `onTap`, but the glass does not light, because the target hit-tests the shape.
  - The terminal chat header (`terminal_chat_header.dart:208`) is one interactive capsule around several controls, so pressing any of them grows the whole capsule.
  - Bar items that sit in a container can merge with their neighbour during a press (+8.4 pt per side).
  - `glass_button_test.dart` went from 13 to 11 tests:
    - no test now checks that a press happens (`member.press.isPressed`) or is released after up, cancel or disable;
    - "reduce motion keeps scale at rest" was deleted;
    - "cancel returns to rest" lost its rest assertion.
  - Operator's own gates pass (+2187).
- **Fix.** Restore behavioural tests: pressed after down, released after up, cancel and disable, and no growth under Reduce Motion. Add a 44 × 44 circle and a 36 pt capsule to N2's references before Operator ships on extrapolated numbers. Put the numbers above into D9.

### F12 (major): the size law and the light are judged only on the six sizes they were fitted on

- **Where.** Global Constraints ("passes are on new recordings of the same scenes, not on new scenes").
- The plan discloses this but does nothing about it. Operator's main sizes and every portrait shape are outside the fit (ruling 8).
- **Fix.** Hold one size out of Task 13's fit (for example a 44 × 44 circle or 88 × 200 portrait), record it in Tasks 11 and 14, and judge it. This costs one scene.

### F13 (minor): `glow_fade_ms` duplicates `glow_drop_ms` whenever there is a cut, so the swell's decay is never judged

- **Evidence.** Every native step with a cut shows `glow_fade_ms == glow_drop_ms` (all 22 lines in `R/native-press.txt` and `R/reproduce-glow.txt`).
- **Fix.** Add a pre-cut level measure (the light one frame before the cut) or the decay's half time, so the fitted fade 0.385 / 1.055 is measured.

### F14 (minor): `material.interactive` and the N2 scenes are not in the still check

- **Evidence.** These are the scenes whose content the press target and the glow painter now wrap. The only analysed prototype Flutter run fails `ready.bbox_pt` 2.0 > 1.0. No pre-2B.3 Flutter recording of it exists in either archive, so "a press changes no still frame" is unproven there.
- **Fix.** Record `material.interactive` at `development` once, and include it in Task 14 Step 5.

### F15 (minor): evidence the plan cites will not be committed

- `research/proto-2b3/plan/replay/replay-{1,2,3}.log` match `.gitignore:6 *.log`, so Execution setup's commit drops them. `plan/replay-result.txt` is empty.
- **Fix.** Rename them `.txt`, or say they live only in the prototype worktree.

### F16 (minor): Task 14 Step 4 touches the shared checkout

- **Where.** `git -C /Users/omaraly/development/AI/Operator worktree add …` contradicts Execution setup's "never touch the shared checkout after the worktree add".
- **Fix.** Use `git -C /Users/omaraly/development/AI/Operator-2b3 worktree add …`.

### F17 (minor): Task 14 Step 2's count skips a case that has no `result.json`

- A case left un-analysed (gotcha 26) or errored is simply not printed.
- **Fix.** Compare the printed cases with the expected list (11 scenes × 4 cases + 3 × 4 under Reduce Motion), and treat a missing one as failing.

### F18 (minor): counts in the text

- Ruling 7 says "12 takes" for the cut; there are 10 cuts.
- Ruling 16 says "6 of the 8 new native takes" are flagged; it is 5 of 8 kept takes, or 6 of 9 counting `055519`.
- Ruling 7 gives the Reduce Motion cut as "two takes, three touches", but the shipped value is one press (F6).
- The app's net test change is −2 (13 → 11 in `glass_button_test.dart`), which matches +2187; it is described as "three removed, one added".

### F19 (minor): untested press paths

- A standalone glass removed or disabled mid-press, which goes through the private coordinator's ticker.
- A Reduce Motion switch mid-press (spec M8: "applies from the next change"; the press captures the setting at touch-down).
- A glass removed while grown: `GlassGhost.contentScale` is 1, so its ghost snaps to rest size.
- A second finger, which is ignored.
- "The press uses its own springs inside `withGlassAnimation`" (M2).
- Interactive glass is now `HitTestBehavior.opaque`, so it absorbs touches meant for widgets behind it inside its shape. The README does not say so.

### F20 (minor): D1's "no call site reaches it" gets weaker once glass presses

- A pressed glass grows by up to 16.78 pt into its container neighbours. That makes a row of unequal overlapping shapes reachable: `perf.motion`'s three-glass container, and Operator bar groups.
- 2B.2 pinned "rows of equal circles" and "any two shapes" as clean, not unequal rows.
- **Fix.** Before accepting D1 A, add a Dart-mirror test: three 44 pt circles at Operator's spacing with the middle one scaled ×1.38.

### F21 (minor): style in `t08-impl`

- A blank line at the end of `perf_scenes.dart` and a blank line between `gestures.dart` and `material.dart` imports.

## Departures

### Disclosed

| Departure | Native evidence | Enough? |
|---|---|---|
| No stretch on any drag (ruling 3) | Fast drag `stretch` 0.007, `centre` 0.24, one take (dark-photo `055621`). Slow drag ≤ 0.007 on every N1 take. The plain-press range 0.002–0.017 is mostly 1/3 pt quantisation (0.004–0.006 of ratio per step) | Absence of a large stretch, yes: an Apple-style stretch would be several points. Absence at the 0.01 threshold, one take is not enough; Task 11's four cases are needed, and the ruling should wait for them |
| No glow spreading, no container glow layer (ruling 4) | Neighbour peak 0.39, 0.02 and 0.004 luma against 23.5–23.9, one take per gap | Yes for the light: a 60× margin. Not for size (F8) |
| Leaving the glass does not release (ruling 3, against M7) | One take, 40 pt outside | No (F10) |
| Content scales with the glass (ruling 5) | v17 and v18 labels scale with the glass, from a luma > 200 extent (the glow can move edge pixels by at most about 0.67 pt, small against +4.33 and +7.33 pt) | Yes |
| Reduce Motion: lights, never grows; `GlassGlow` keeps its glow (ruling 10) | `grow_w` 0 against 12; peak 19.6 against 20.6 | Yes. Whether the light's focus still follows the finger under Reduce Motion is not measured |
| Follow spring not re-timed (ruling 13) | none | Disclosed as a carried value; acceptable |

### Not disclosed

- **The take rule (F1).** It relaxes 2B.1's capture-hole exclusion (gotcha 47) for the new takes. In effect that loosens limits.
- **Size law target (F3).** Spec M7 says "native's size law fitted on N2". The package overshoots it by about 8.6 %, so it does not follow the law it fitted.
- **Done item 3 (F7).** Spec §4's "Reduce Motion everywhere" is forecast as passing on the press alone.
- **Spec §9 tests.** "Reduce Motion paths" and "hit testing at the final layout while glass is still moving" have no press test for a mid-press switch or for a press while scaled (F19).
- **Spec M7, "re-timed to native".** The follow motion is not re-timed. It is disclosed as ruling 13, but the self-review's departures list names only four of the departures.
- **Item by item.**
  - Every other §8 2B.3 item maps to a task: items 1 and 2 to Tasks 11, 12 and 14; item 4 to Task 14 Steps 3 and 4; item 5 to Tasks 10 and 15; item 6 to Task 9; item 7 to Task 14 Step 5; item 8 to Task 15.
  - M9: the README table covers every name (checked).
  - M10: `perf.motion` covers press pulses, materialize and dematerialize, and merge and split.

## Decisions D1 to D9

| Decision | Plan's recommendation | Mine |
|---|---|---|
| D1 seam | A (project 3) | A, after F20's mirror test. If a row of unequal shapes shows the step, B |
| D2 morph round trip | A (defer) | Agree |
| D3 single takes | A (report leave-one-out) | A is not enough once F1 is fixed: also refuse a floor where one take sets a time limit above 3× its siblings' median. Task 12 Step 6 already detects that; make it stop the task instead of only naming it |
| D4 `FakeGlass` | A | Agree |
| D5 checks inside `repeat` and `run` | A (by hand) | B. The by-hand rule is the problem in F1, and recording will be about 4.5 h; a scripted check with the corrected burst rule is cheaper than reading `take_check` by hand for about 200 takes |
| D6 drag-out pull | A | Agree, plus F10's far drag |
| D7 2B.2 class (a) items | A | Agree |
| D8 2B.1 package defects | A | Agree |
| D9 Operator feel | Keep Task 9 | The user should decide after seeing F11's numbers (×1.38 at 44 pt against ×1.08, extrapolated sizes). I would keep Task 9 only with F11's tests and a 44 × 44 reference; otherwise move it to project 3 with that reason |

**Forecast honesty.** "Items 1 and 2 fail in part" is understated. Item 3 also fails, the event gate fails, the light cases fail on `glow_peak`, and the small sizes fail on the cut. The positive part (item 4 perf passing) is supported by the JSON. Perf could only be read from the JSON: no pairs exist, and 32 % (`perf.motion`) and 44 % (`perf.slide`) fewer frames with p90 over 16.7 ms deserve a sentence in Done item 4, even if they are not judged.

## The Operator `_PressLift` swap

- **The code.** Trivial and correct. `GlassSurface.build` becomes `GlassEffect(glass: glassForVariant(...).interactive(pressable && enabled), ...)`. `_PressLift`, `pressedScale`, `glowAlpha` and the app's `GlassGlow` go. `glass_button.dart` drops `glowAlpha`.
- **Call sites.** Three: `GlassButton`, `GlassBarItem`, and `terminal_chat_header.dart:212`.
- **Gates.** App analyze is clean and `+2187` passes. The still frames should not change, and Task 14 Step 5's `button.press`, `tabbar.rest` and `navbar.inline` will confirm it.
- **What changes for the user.**
  - 44 pt icon buttons and bar items grow to about 60.8 pt and their glyphs scale ×1.38 (was ×1.08). Labelled buttons grow by about 16.8 pt in width whatever their width.
  - A white flash appears: an even 11 luma plus a 39 luma spot on 44 pt circles. This replaces the 0.35 or 0.25 white `GlassGlow`.
  - After release, the light holds for about 0.42 s and goes in one frame.
  - Under Reduce Motion the glass now lights; before, nothing happened.
  - The terminal header grows as one capsule.
  - Corners of the hit area outside the glass shape tap without lighting.
- **The user decides:**
  1. Whether Operator adopts these extrapolated small-size numbers now, or after a 44 × 44 native reference.
  2. Whether the terminal header's multi-control capsule should press as a whole.
  3. Whether to restore the behavioural tests (recommended, F11).

## What would make it ready

1. Fix the take rule and the floors (F1), and re-run the prototype's comparison on clean takes, including light and stripes cases (F2, F9).
2. Change `pressfit`: fit the law on the plateau (F3), mask the profile (F4), fit the cut per size (F5), and add the grid-edge and Reduce Motion count checks (F6). Re-run `pressfit`, regenerate the plan with `build_plan.py`, and replay.
3. Rewrite the forecast (F7, F8) and Ruling 3's scope (F10). Add the held-out and Operator sizes (F11, F12).
4. Apply the minor fixes as text or tests.
