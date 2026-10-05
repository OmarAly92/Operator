# 2B.1 results

Date: 2026-10-06. Branch `feat/ios-liquid-glass-2b1`, measured at `58ab57e0c` (the re-fitted motion table). Simulator: iPhone 17 Pro (iOS 27), UDID 708879DD-8B2A-4547-863F-F49EE1474D8B. Run folders are under `packages/mobile/build/glass_lab/runs/`; fit, cold-start and ghost folders under `packages/mobile/build/glass_lab/fitvis/`, `cold/` and `ghost/`. `ReduceMotionEnabled` read `0` after every run and after the gates. Saved tool outputs and task reports are committed under `research/execution-2b1/` (paths relative to this folder), with the execution ledger as `research/execution-2b1/ledger.md`; a ruling or review finding cited by task number is a line of that ledger. `fit.json` is the Step 4 fit, copied as `research/execution-2b1/task-20b-fit.json`.

**How the numbers were read.** Every motion number is a `motion.*` measure of a run's `result.json`, judged by `lab.py analyze` against max(fixed threshold, 1.5 × noise) with the per-case noise of `tool/glass_lab/noise.json` (Task 9). `done_table.py` counts them per case: the seven `progress.*` measures per event pair and shape are the Done item 4 measures; the event and touch gates (`events.*`, `touches.*`) are counted apart. Every still number is the `static.ready` block (2A's convention); `still_check.py` compares `ready` and `settled`, case by case, against the 2A runs of `results-2a1.md`, read in place. Each count below can be recomputed with the command next to it, run from `packages/mobile`.

## The Done table

| Done item (spec §8, 2B.1) | Result | Evidence |
|---|---|---|
| 1 L1–L3, L5–L8 tested and reproducing known numbers | **Pass**, with one number not reproduced, as ruling 2 expects. Disappear 117–133 ms and appear 275–292 ms (ruling 6's 120 Hz estimator); the two 275 ms appears are 10 ms under the spec's 285, inside their `t10_90_ms` noise (25 and 33.3 ms). Not an alpha fade on `photo`; v13 +12.00 / +4.66; short glass +17.00 (58 pt circle) and +16.00 (138 × 53); `button.press` 138.33 → 154.33 and 174.33 → 190.33 in all six runs; menu open 0.26–0.30 s / 0.74–0.81. 250 × 44 reads +14.33, **not reproduced** against the spike's +17.67 (ruling 2). Touches read back, two per app. | harness `Ran 175 tests` OK; `reproduce.py` output (`research/execution-2b1/task-6-reproduce.txt`, byte-identical to `research/proto-2b1/reproduce.txt`); touches in run `20261003-234148` |
| 2 Noise floors for every 2B.1 scene and case | **Pass**: 15 scenes, 60 cases, five native takes each over two sessions. Motion and static floors for the three materialize scenes (8 cases each), `material.interactive` and the five press sizes (4 cases each); static and topology floors for the six spacing scenes (2 cases each). Four capture-hole takes excluded and replaced (below). | run `noise-2b1`; `noise.json` at `fd30f969d` |
| 3 N1, N2, N5, N7 and N6 (materialize) recorded | **Pass** | runs `20261004-000223` (materialize, N5), `20261004-001040` (N6 materialize), `20261004-001855` (N1), `20261004-002204` (N2), `20261004-003527` (N7) |
| 4 Materialize passes under default, `.snappy`, `.bouncy` and Reduce Motion, per shape | **Partly failing**, as the plan expected. Progress measures (passing / judged / expected): normal **129 / 168 / 168**, Reduce Motion **135 / 168 / 168**, with the three stall repeats substituted (130 and 133 as first run). Event and touch gates **120 / 120**, `unpaired` 0 everywhere. All 72 remaining failures classed below: 69 class (b), 3 class (a). | runs `20261005-233131` (normal), `20261005-234750` (Reduce Motion), repeats `20261006-001644`, `-002044`, `-002206`; `done_table.py` |
| 5 Still glass no worse than 2A | **Pass**: `missing: 0` and `worse: 0` in all nine scenes, Operator's three included; 112 of 124 Flutter frames byte-identical to 2A's; no static measure changed pass or fail or moved by more than 0.0008. The 12 `material.edge` frames differ by a 0.24 px rim snap (finding below). | nine runs `20261006-003104` … `-013445`; `still_check.py` |
| 6 Gates | **Pass**: app `+2146`, package `+122`, example `+13`, all three `flutter analyze` clean; harness 175 OK | below |

### Done item 4 per scene and appearance

Progress measures passing / judged / expected, then the event and touch gates, with the repeats substituted. Each line is two cases (`photo` and `stripes`) of two events each.

| Scene | Appearance | Normal progress | Normal gates | Reduce Motion progress | Reduce Motion gates |
|---|---|---|---|---|---|
| `material.materialize` (default) | dark | 19 / 28 / 28 | 10 / 10 | 21 / 28 / 28 | 10 / 10 |
| `material.materialize` (default) | light | 24 / 28 / 28 | 10 / 10 | 23 / 28 / 28 | 10 / 10 |
| `material.materialize.snappy` | dark | 21 / 28 / 28 | 10 / 10 | 23 / 28 / 28 | 10 / 10 |
| `material.materialize.snappy` | light | 24 / 28 / 28 | 10 / 10 | 24 / 28 / 28 | 10 / 10 |
| `material.materialize.bouncy` | dark | 21 / 28 / 28 | 10 / 10 | 22 / 28 / 28 | 10 / 10 |
| `material.materialize.bouncy` | light | 20 / 28 / 28 | 10 / 10 | 22 / 28 / 28 | 10 / 10 |
| **Total** | | **129 / 168 / 168** | **60 / 60** | **135 / 168 / 168** | **60 / 60** |

As first run, normal `.snappy` dark read 22 and Reduce Motion `.bouncy` light 20 (totals 130 and 133). Per case, `done_table.py build/glass_lab/runs/20261005-233131 build/glass_lab/runs/20261005-234750` prints the first runs (`research/execution-2b1/task-20c-done-table.txt`) and `done_table.py build/glass_lab/runs/20261006-001644 build/glass_lab/runs/20261006-002044 build/glass_lab/runs/20261006-002206` the repeats (of `20261006-001644`, only the default `light-stripes` case is substituted; its `.snappy` and `.bouncy` cases were recorded by the same command and are not used).

Failing pairs by measure, out of 24 pairs per run (normal / Reduce Motion, with the repeats): `t10_90_ms` 4 / 3, `settle_ms` 7 / 3, `overshoot_pct` 0 / 0, `response_pct` 12 / 13, `damping` 10 / 8, `rms` 0 / 0, `sharpness` 6 / 6. The prototype's (fixed limits, one session): 4 / 7, 12 / 11, 0 / 0, 19 / 21, 15 / 15, 0 / 0, 6 / 6.

## Run folders

| Step | Command | Run folder | Report counts |
|---|---|---|---|
| Task 5 touch check | `run material.materialize --appearance dark --backdrop photo` | `20261003-234148` | marker check only |
| Task 8 (native) | `run material.materialize --app native` (N5) | `20261004-000223` | 12 cases, native only |
| Task 8 (native) | the same, `--a11y reduce-motion` (N6) | `20261004-001040` | 12 cases, native only |
| Task 8 (native) | `run material.interactive --app native` (N1) | `20261004-001855` | 4 cases, native only |
| Task 8 (native) | `run material.press --app native` (N2) | `20261004-002204` | 20 cases, native only |
| Task 8 (native) | `run material.spacing --app native` (N7) | `20261004-003527` | 12 cases, native only |
| Task 9 | `repeat <scene> --into noise-2b1` for the 15 scenes (materialize also `--a11y reduce-motion`): three takes in session 1, two in session 2 | `noise-2b1` | 60 cases, static `mad` 0.00 in every take |
| Task 20 Step 4 | `fitvis 20261004-000223 20261004-001040 noise-2b1 --write` | `fitvis/20261005-211745` | `fit.json` below |
| Step 5 | `run material.materialize` | `20261005-233131` | pass 0, fail 12 |
| Step 5 | `run material.materialize --a11y reduce-motion` | `20261005-234750` | pass 0, fail 12 |
| Step 5 repeat | `run material.materialize --appearance light --backdrop stripes` | `20261006-001644` | pass 0, fail 3 |
| Step 5 repeat | `run material.materialize.snappy --appearance dark --backdrop photo` | `20261006-002044` | pass 0, fail 1 |
| Step 5 repeat | `run material.materialize.bouncy --appearance light --backdrop stripes --a11y reduce-motion` | `20261006-002206` | pass 0, fail 1 |
| Step 6 | `cold_probe.py build/glass_lab/runs/20261005-233131/material.materialize/dark-photo` | `cold/20261006-002600` | below |
| Step 7 | `run material.regular` | `20261006-003104` | pass 8, fail 2 |
| Step 7 | `run material.clear` | `20261006-004222` | pass 2, fail 2 |
| Step 7 | `run material.tinted` | `20261006-004700` | pass 0, fail 6 |
| Step 7 | `run material.edge` | `20261006-005342` | pass 5, fail 1 |
| Step 7 | `run material.regular --a11y reduce-transparency` | `20261006-010032` | pass 8, fail 2 |
| Step 7 | `run material.regular --a11y increase-contrast` | `20261006-011154` | pass 9, fail 1 |
| Step 7 | `run tabbar.rest --flutter operator` | `20261006-012309` | pass 0, fail 8 |
| Step 7 | `run button.press --flutter operator` | `20261006-013200` | pass 0, fail 2 |
| Step 7 | `run navbar.inline --flutter operator` | `20261006-013445` | pass 0, fail 6 |
| Step 9 | `ghost_probe.py tool.ghost` | `ghost/20261006-014735` | below |
| Step 9 | `ghost_probe.py tool.ghost.standalone` | `ghost/20261006-014805` | below |
| edge diagnosis | throwaway probes, reverted | `20261006-020852`, `20261006-021029` | evidence only |

Every materialize case reports a failure, so `lab.py report` passes none; the counts that matter are `done_table.py`'s. The nine still runs report exactly the 2A runs' counts (`results-2a1.md`, "after"). Operator's scenes report 0 passes because `report` judges them on the strict thresholds, not 2A's halving rule.

## Done item 1: the lab reproduces the known numbers

`reproduce.py` reads recordings only (copied into `build/glass_lab/reference/` by Task 6). Its output is `research/execution-2b1/task-6-reproduce.txt`, byte-identical to the prototype's `research/proto-2b1/reproduce.txt`:

| Number (spec §8 item 1) | Read | Verdict |
|---|---|---|
| disappear 117–167 ms | 133, 117, 125, 117 ms (`LG-20260930-082046`: dark-photo, dark-stripes, light-photo, light-stripes) | pass |
| appear 285–320 ms | 275, 275, 292, 292 ms | pass within noise: the 275 ms cases are 10 ms under, against `step3e0.progress.t10_90_ms` noise of 25.0 ms (dark-photo) and 33.3 ms (dark-stripes) in `noise.json`; ruling 6 records that the spec's range came from a first-frame estimator that reads up to 28 ms longer |
| not an alpha fade | residual peak 5.12 / 5.37 against a floor of 2.67 / 2.13 on dark / light `photo`; half-progress sharpness −1.08 to −1.54 | pass (ruling 5) |
| v13 +12 / +4.67 pt at 250 × 88 | 252.0 × 88.67 → 264.0 × 93.33, +12.00 / +4.66 | pass (the 4.66 is 93.33 − 88.67 in thirds of a point) |
| about +17.5 pt on glass up to about 60 pt tall | +17.00 (58 pt circle, v16), +16.00 (138 × 53, v17), +14.33 (250 × 44, v18) | +17.00 and +16.00 pass; **+14.33 not reproduced** (spike +17.67): the spike's rest and peak boxes used different thresholds, and at v18's peak both capsule ends sit on the stripe boundaries at 67 and 335 pt, inside L1's blind band (ruling 2). Its true growth is about 15.0–15.5 pt; the 17.5 pt law does not hold at 250 × 44, and 2B.3 fits the size law on N2 on `photo` |
| `button.press` 138 → 154–155, 174 → 190–192 | 138.33 → 154.33 and 174.33 → 190.33 (+16.00) in all six runs (`LG-20260930-101816`, `LG-20260930-105500`, `LG-20261002-160207`, `LG-20261002-205855`, `GL-20260927-035111`, `GL-20260927-022300`) | pass |
| menu open 0.26–0.30 s / 0.74–0.81 | three pairs: 0.27/0.78, 0.26/0.81, 0.30/0.74 | pass (ruling 3) |
| touches (L5) | run `20261003-234148`: native (17.007, 17.122) and (19.722, 19.863) s, Flutter (17.542, 17.580) and (20.242, 20.350) s | two touches per app, as expected |

The native taps lasted 115 and 141 ms, longer than the prototype's 42 and 70 ms; no measure judges tap length, and taps are timed from touch-up.

## Done item 2: noise floors

`noise.json` holds `{scene: {case: {measure: noise}}}` for every 2B.1 scene. Values per scene: `material.materialize` 518, `.snappy` 501, `.bouncy` 498, `material.interactive` 318, `material.press.138x53` 187, `.250x44` 134, `.300x120` 147, `.360x200` 88, `.circle58` 207, and the six `material.spacing.*` scenes 32–36 each (static and topology). The 2A-era `menu.bar` and `tabbar.drag` entries are kept, except `tabbar.drag`'s `event2.*` teardown entries, which ruling 22 removes (commit `3e7a9e20f`, Task 6: 30 keys to 20). The widest materialize floors that remain: `material.materialize` dark-stripes `step3e0.progress.t10_90_ms` 33.3 ms, several at 25.0 ms.

Session 1 recorded three takes per case (load average 13–42), session 2 two more after a simulator reboot (load average 67–161). The four excluded takes and their replacements are under "Deviations" below.

## Done item 3: native references

- **N5 and N6, materialize** (dark-photo, from Task 8's report, `research/execution-2b1/task-8-report.md`; ms): default disappear 141.7 and appear 291.7; `.snappy` 116.7 and 216.7; `.bouncy` 108.3 and 141.7 (appear overshoot 1.42%); Reduce Motion default 141.7 and 283.3, `.snappy` 125.0 and 208.3, `.bouncy` 108.3 and 158.3 (overshoot 2.75%). Two touches and two events in each.
- **N1** `material.interactive` dark-stripes: rest 252.0 × 88.67, peak 264.0 × 93.0 (+12.00 / +4.33; the spike's v13 read +4.67, a pixel more).
- **N2** `material.press.250x44` dark-stripes: rest 252.0 × 44.67, peak 266.33 × 47.67 (+14.33, as the spike recording reads in L1).
- **N7** spacing, dark-photo (run `20261004-003527`, `track.still_mask` and `track.topology` over each region): the default container joins at gaps 0 and 4 pt (necks 25.33 and 4.00 pt) and keeps 8 pt and wider apart; `spacing: 40` joins at 0–20 pt (necks 50.67, 38.33, 40.67, 34.00, 24.67, 2.00) and keeps 24 pt and wider apart. This is ruling 23's reading exactly.

## Every failing materialize measure, classed by cause

Classes: **(a)** tunable (a fitted value); **(b)** model limitation; **(c)** lab scene; **(d)** measurement artifact (a stall the report lists, an invalid fit); **(e)** the debug build. No limit was loosened: each value below fails its own limit, max(fixed, 1.5 × noise), shown after the `>`.

| Group | Class | Measures | Normal | Reduce Motion |
|---|---|---|---|---|
| b1 half-progress sharpness on dark `photo` | b | `sharpness` | 6 | 6 |
| b2 dark `photo` disappear runs ahead | b | `response_pct`, `damping`, `t10_90_ms`, `settle_ms` | 7 | 4 |
| b3 spring shape on `light` and `stripes` | b | `response_pct`, `damping` | 17 | 19 |
| b4 timing by one to three frames | b | `t10_90_ms`, `settle_ms` | 7 | 3 |
| a1 `.bouncy` appear settles late where native overshoots more | a | `settle_ms` | 2 | 1 |
| **Total** | | | **39** | **33** |

Crops are made from the runs' own video frames by `research/execution-2b1/crops/make_crops.py <scratch folder> <out folder>` (run from `packages/mobile`; it copies the case folders and re-extracts frames there, so the run folders are not touched). Each tile is the tracked region, labelled with its time after the event's onset and its progress.

No failure is class (c), (d) or (e) once the repeats are substituted. No progress fit is marked invalid in either run. The listed stalls are native's (25–28 ms; below); the pairs they sit in fail in the same pattern as the stall-free cases of the other presets, so the stalls do not make the failures. The three Flutter stalls (class e, the debug JIT) were removed by repeating those cases (below).

### b1: half-progress sharpness on dark `photo` (12)

Every `sharpness` failure is on dark `photo`, both events, every preset and mode: Flutter's mid-transition frame is blurrier than native's, a sharpness difference of 1.12–1.52 against a limit of 1.00 (for example default normal disappear: native −1.11, Flutter −2.45). `fit.json` shows that no blur ramp closes it: at half progress Flutter reads −2.69 (k = 1), −2.63 (2), −2.61 (3) and −2.53 (4) on dark-photo against native's −1.07 (`flutter_sharpness`, `native_sharpness`). Ruling 25 expected exactly this; what softens the half-way frame other than the blur is in `todo-2b1.md`. Light `photo` passes (normal default disappear −1.55 against −2.25, a difference of 0.70).

Crop: `research/execution-2b1/crops/b1-half-progress-sharpness.png`, native | Flutter at the frame nearest progress 0.5 of the default disappear (run `20261005-233131`). On dark `photo` (native 0.48 at +62 ms, Flutter 0.44 at +47 ms) the red, blue and yellow shapes seen through Flutter's glass are blurred well past native's. Light `photo` shows the same in a milder form, under the limit.

| Group | Mode | Preset | Case | Event | Measure | Value > limit | Run |
|---|---|---|---|---|---|---|---|
| b1 | normal | default | dark-photo | disappear | `sharpness` | 1.341 > 1.000 | `20261005-233131` |
| b1 | normal | default | dark-photo | appear | `sharpness` | 1.334 > 1.000 | `20261005-233131` |
| b1 | normal | .bouncy | dark-photo | disappear | `sharpness` | 1.523 > 1.000 | `20261005-233131` |
| b1 | normal | .bouncy | dark-photo | appear | `sharpness` | 1.236 > 1.000 | `20261005-233131` |
| b1 | normal | .snappy | dark-photo | disappear | `sharpness` | 1.140 > 1.000 | `20261006-002044` |
| b1 | normal | .snappy | dark-photo | appear | `sharpness` | 1.289 > 1.000 | `20261006-002044` |
| b1 | RM | default | dark-photo | disappear | `sharpness` | 1.117 > 1.000 | `20261005-234750` |
| b1 | RM | default | dark-photo | appear | `sharpness` | 1.348 > 1.000 | `20261005-234750` |
| b1 | RM | .bouncy | dark-photo | disappear | `sharpness` | 1.366 > 1.000 | `20261005-234750` |
| b1 | RM | .bouncy | dark-photo | appear | `sharpness` | 1.428 > 1.000 | `20261005-234750` |
| b1 | RM | .snappy | dark-photo | disappear | `sharpness` | 1.202 > 1.000 | `20261005-234750` |
| b1 | RM | .snappy | dark-photo | appear | `sharpness` | 1.524 > 1.000 | `20261005-234750` |

### b2: dark `photo` disappear runs ahead of native (11)

Flutter's dark `photo` disappear is faster than native's in every preset: 10–90% 108 against 133 ms (default), 92 against 108 (`.bouncy`), 100 against 117 (`.snappy`); its fitted spring is 0.17 s / 1.13 against native's 0.25 / 0.99 (default normal). The cause is Flutter's own progress at a fixed visibility, which depends on the backdrop: at visibility 0.5 it is 0.312 on dark-photo, 0.441 on dark-stripes, 0.466 on light-photo and 0.470 on light-stripes (`fit.json` `flutter_progress`), while `ios27VisibilityForProgress` inverts their mean (0.422). Dark-photo progress therefore falls faster than the target on the way out, and rises slower on the way in (its appear reads 300 against 275 ms). The package cannot see its backdrop, so one table must serve all of them: class (b). It may share b1's cause (Flutter's partly visible frame on dark `photo` differs from native's beyond the blur); that is not established.

Crop: `research/execution-2b1/crops/b2-dark-photo-disappear.png`, native | Flutter at equal times after the default dark-photo disappear's onset (run `20261005-233131`): native 0.73 at +27 ms against Flutter 0.61 at +30 ms, 0.48 at +62 against 0.30 at +65, 0.25 at +95 against 0.13 at +98. Flutter's glass is visibly further gone at each time.

| Group | Mode | Preset | Case | Event | Measure | Value > limit | Run |
|---|---|---|---|---|---|---|---|
| b2 | normal | default | dark-photo | disappear | `damping` | 0.140 > 0.060 | `20261005-233131` |
| b2 | normal | default | dark-photo | disappear | `response_pct` | 32.0 > 6.0 | `20261005-233131` |
| b2 | normal | default | dark-photo | disappear | `settle_ms` | 25.0 > 17.0 | `20261005-233131` |
| b2 | normal | default | dark-photo | disappear | `t10_90_ms` | 25.0 > 17.0 | `20261005-233131` |
| b2 | normal | .bouncy | dark-photo | disappear | `damping` | 0.090 > 0.050 | `20261005-233131` |
| b2 | normal | .bouncy | dark-photo | disappear | `response_pct` | 26.1 > 6.0 | `20261005-233131` |
| b2 | normal | .snappy | dark-photo | disappear | `response_pct` | 24.0 > 18.8 | `20261006-002044` |
| b2 | RM | default | dark-photo | disappear | `response_pct` | 29.6 > 12.0 | `20261005-234750` |
| b2 | RM | default | dark-photo | disappear | `t10_90_ms` | 33.3 > 17.0 | `20261005-234750` |
| b2 | RM | .snappy | dark-photo | disappear | `response_pct` | 26.9 > 12.5 | `20261005-234750` |
| b2 | RM | .snappy | dark-photo | disappear | `settle_ms` | 25.0 > 17.0 | `20261005-234750` |

### b3: spring shape on `light` and `stripes` (36)

Mostly the appear event (33 of 36; three are disappears on `light-stripes` or `light-photo`). One SwiftUI spring per preset drives every backdrop, but what the pixels show is not the same curve on every backdrop. Native's own fitted spring on the default appear is 0.49 s / 1.02 on dark-photo, 0.55 / 0.97 on dark-stripes, 0.67 / 0.89 on light-photo and 0.67 / 0.89 on light-stripes (normal run `20261005-233131`; the light-stripes repeat reads 0.69 / 0.87), and Flutter's 0.56 / 0.98, 0.49 / 1.06, 0.42 / 1.20 and 0.43 / 1.16: the two move in opposite directions across backdrops. `fit.json`'s `default_spring_check` also finds native's spring depending on the backdrop: 0.59 / 0.98 (dark-photo), 0.71 / 0.80 (dark-stripes), 0.50 / 1.14 (light-photo) and 0.44 / 1.30 (light-stripes). Only that dependence is shared. Its values differ from the run fits above because it is a different estimator: one spring fitted through the fitted mapping to all of a case's appear and disappear curves over every take (`fitvis.py:231-246`), where the run fits a spring to one appear event's progress curve. The lens's stripe shift and the light backdrops' brightening enter the progress measure; neither is a state the package has. Class (b), the prototype's class 1. The deciding measure, a per-appearance fit on `photo` alone, is in `todo-2b1.md`.

Crop: `research/execution-2b1/crops/b3-light-stripes-appear.png`, native | Flutter at equal times after the default light-stripes appear's onset (repeat run `20261006-001644`): progress 0.23 against 0.40 at +100 ms, 0.59 against 0.70 at +200 ms, 0.81 against 0.85 at +300 ms. Native's frames show its lens shifting the stripe boundaries inside the glass and a soft, spreading edge, both of which enter native's progress reading; Flutter's glass has neither mid-transition.

| Group | Mode | Preset | Case | Event | Measure | Value > limit | Run |
|---|---|---|---|---|---|---|---|
| b3 | normal | default | dark-stripes | appear | `response_pct` | 10.9 > 5.8 | `20261005-233131` |
| b3 | normal | default | light-photo | appear | `damping` | 0.310 > 0.090 | `20261005-233131` |
| b3 | normal | default | light-photo | appear | `response_pct` | 37.3 > 21.2 | `20261005-233131` |
| b3 | normal | default | light-stripes | appear | `damping` | 0.300 > 0.165 | `20261006-001644` |
| b3 | normal | default | light-stripes | appear | `response_pct` | 37.7 > 28.0 | `20261006-001644` |
| b3 | normal | .bouncy | dark-stripes | appear | `damping` | 0.090 > 0.050 | `20261005-233131` |
| b3 | normal | .bouncy | light-photo | appear | `damping` | 0.140 > 0.050 | `20261005-233131` |
| b3 | normal | .bouncy | light-photo | appear | `response_pct` | 24.1 > 22.3 | `20261005-233131` |
| b3 | normal | .bouncy | light-stripes | disappear | `response_pct` | 14.3 > 7.1 | `20261005-233131` |
| b3 | normal | .bouncy | light-stripes | appear | `damping` | 0.140 > 0.050 | `20261005-233131` |
| b3 | normal | .bouncy | light-stripes | appear | `response_pct` | 14.6 > 5.0 | `20261005-233131` |
| b3 | normal | .snappy | dark-stripes | appear | `damping` | 0.260 > 0.105 | `20261005-233131` |
| b3 | normal | .snappy | dark-stripes | appear | `response_pct` | 29.8 > 6.7 | `20261005-233131` |
| b3 | normal | .snappy | light-photo | appear | `damping` | 0.160 > 0.060 | `20261005-233131` |
| b3 | normal | .snappy | light-photo | appear | `response_pct` | 29.3 > 22.7 | `20261005-233131` |
| b3 | normal | .snappy | light-stripes | appear | `damping` | 0.200 > 0.050 | `20261005-233131` |
| b3 | normal | .snappy | light-stripes | appear | `response_pct` | 29.8 > 10.7 | `20261005-233131` |
| b3 | RM | default | dark-stripes | appear | `damping` | 0.090 > 0.075 | `20261005-234750` |
| b3 | RM | default | dark-stripes | appear | `response_pct` | 16.9 > 5.0 | `20261005-234750` |
| b3 | RM | default | light-photo | appear | `damping` | 0.260 > 0.060 | `20261005-234750` |
| b3 | RM | default | light-photo | appear | `response_pct` | 32.8 > 6.4 | `20261005-234750` |
| b3 | RM | default | light-stripes | disappear | `response_pct` | 30.0 > 19.6 | `20261005-234750` |
| b3 | RM | default | light-stripes | appear | `damping` | 0.220 > 0.050 | `20261005-234750` |
| b3 | RM | default | light-stripes | appear | `response_pct` | 25.9 > 12.5 | `20261005-234750` |
| b3 | RM | .bouncy | dark-stripes | appear | `damping` | 0.180 > 0.050 | `20261005-234750` |
| b3 | RM | .bouncy | dark-stripes | appear | `response_pct` | 16.7 > 5.0 | `20261005-234750` |
| b3 | RM | .bouncy | light-photo | disappear | `response_pct` | 9.1 > 6.5 | `20261005-234750` |
| b3 | RM | .bouncy | light-photo | appear | `damping` | 0.100 > 0.050 | `20261005-234750` |
| b3 | RM | .bouncy | light-photo | appear | `response_pct` | 6.7 > 6.4 | `20261005-234750` |
| b3 | RM | .bouncy | light-stripes | appear | `damping` | 0.300 > 0.050 | `20261006-002206` |
| b3 | RM | .bouncy | light-stripes | appear | `response_pct` | 37.5 > 9.2 | `20261006-002206` |
| b3 | RM | .snappy | dark-stripes | appear | `response_pct` | 6.2 > 5.9 | `20261005-234750` |
| b3 | RM | .snappy | light-photo | appear | `damping` | 0.180 > 0.060 | `20261005-234750` |
| b3 | RM | .snappy | light-photo | appear | `response_pct` | 26.8 > 7.6 | `20261005-234750` |
| b3 | RM | .snappy | light-stripes | appear | `damping` | 0.110 > 0.060 | `20261005-234750` |
| b3 | RM | .snappy | light-stripes | appear | `response_pct` | 18.0 > 5.0 | `20261005-234750` |

### b4: timing by one to three frames (10)

`t10_90_ms` and `settle_ms` failures 4–25 ms over their limits (up to three 120 Hz frames; the largest are default dark-photo appear `settle_ms` 75.0 against 50.0 and `.bouncy` light-stripes appear `t10_90_ms` 41.7 against 25.0). The failing `.bouncy` appears are 25–42 ms longer in Flutter (for example 175 against 133 ms on normal light-stripes); the passing ones are 16.7 ms longer (normal light-photo, Reduce Motion dark-photo) and 25.0 ms at its limit of 25.0 (Reduce Motion light-stripes, repeat). One b4 row is a disappear: Reduce Motion default dark-stripes `settle_ms` 25.0 against 17.0, one frame past its limit. Below 1 the appear's progress is the SwiftUI spring itself, mapped to visibility through the tool-written table, so no fitted value shortens it without bending the spring, which ruling 10 forbids. The prototype classed the same failures (b) with the same cause as b3. No crop: these are timing differences of one to three frames, which a still frame cannot show.

| Group | Mode | Preset | Case | Event | Measure | Value > limit | Run |
|---|---|---|---|---|---|---|---|
| b4 | normal | default | dark-photo | appear | `settle_ms` | 75.0 > 50.0 | `20261005-233131` |
| b4 | normal | default | dark-stripes | appear | `settle_ms` | 41.7 > 37.5 | `20261005-233131` |
| b4 | normal | .bouncy | dark-photo | appear | `t10_90_ms` | 25.0 > 17.0 | `20261005-233131` |
| b4 | normal | .bouncy | dark-stripes | appear | `t10_90_ms` | 33.3 > 25.0 | `20261005-233131` |
| b4 | normal | .bouncy | light-stripes | appear | `t10_90_ms` | 41.7 > 25.0 | `20261005-233131` |
| b4 | normal | .snappy | dark-photo | appear | `settle_ms` | 33.3 > 25.0 | `20261006-002044` |
| b4 | normal | .snappy | dark-stripes | appear | `settle_ms` | 33.3 > 25.0 | `20261005-233131` |
| b4 | RM | default | dark-stripes | disappear | `settle_ms` | 25.0 > 17.0 | `20261005-234750` |
| b4 | RM | .bouncy | dark-stripes | appear | `t10_90_ms` | 33.3 > 25.0 | `20261005-234750` |
| b4 | RM | .bouncy | light-photo | appear | `t10_90_ms` | 25.0 > 17.0 | `20261005-234750` |

### a1: `.bouncy` appear settles late where native overshoots more (3)

Native's `.bouncy` appear overshoots more than the package's single gain gives, and decays more slowly: normal light-photo overshoot 2.5% against 1.5% and settle 400 against 242 ms; normal light-stripes 2.4% against 1.2%, 367 against 242 ms; Reduce Motion dark-photo 3.0% against 1.8%, 375 against 242 ms. `overshoot_pct` itself passes in all 48 pairs (its limit is wider). A per-appearance gain would close it: class (a), the prototype's class 3, carried to `todo-2b1.md`.

| Group | Mode | Preset | Case | Event | Measure | Value > limit | Run |
|---|---|---|---|---|---|---|---|
| a1 | normal | .bouncy | light-photo | appear | `settle_ms` | 158.3 > 25.0 | `20261005-233131` |
| a1 | normal | .bouncy | light-stripes | appear | `settle_ms` | 125.0 > 87.5 | `20261005-233131` |
| a1 | RM | .bouncy | dark-photo | appear | `settle_ms` | 133.3 > 75.0 | `20261005-234750` |

## Not judged, reported

### Touch-to-response delay

Onset minus touch-up, native / Flutter, ms, with the repeats substituted (from each pair's `shapes.pairs.<pair>.delay` in `result.json`). Disappear is step 1, appear step 3.

| Preset | Case | Normal disappear | Normal appear | Reduce Motion disappear | Reduce Motion appear |
|---|---|---|---|---|---|
| default | dark-photo | 33 / 18 | 112 / 33 | 33 / 17 | 112 / 33 |
| default | dark-stripes | 27 / 18 | 112 / 17 | 17 / 17 | 83 / 17 |
| default | light-photo | 48 / 17 | 93 / 15 | 47 / 15 | 95 / 15 |
| default | light-stripes | 40 / 13 | 95 / 17 | 43 / 17 | 112 / 15 |
| `.snappy` | dark-photo | 47 / 15 | 95 / 30 | 15 / 17 | 85 / 35 |
| `.snappy` | dark-stripes | 47 / 17 | 113 / 27 | 33 / 17 | 95 / 12 |
| `.snappy` | light-photo | 47 / 17 | 80 / 17 | 28 / 20 | 97 / 17 |
| `.snappy` | light-stripes | 45 / 17 | 98 / 17 | 32 / 17 | 97 / 0 |
| `.bouncy` | dark-photo | 50 / 17 | 95 / 28 | 27 / 17 | 112 / 33 |
| `.bouncy` | dark-stripes | 45 / 17 | 95 / 17 | 28 / 20 | 112 / 33 |
| `.bouncy` | light-photo | 47 / 15 | 63 / 13 | 47 / 17 | 83 / 17 |
| `.bouncy` | light-stripes | 28 / 13 | 93 / 17 | 47 / 17 | 90 / 28 |

Native starts to disappear 27–50 ms (normal) and 15–47 ms (Reduce Motion) after the tap, and to appear 63–113 ms and 83–112 ms after it. Flutter starts within 12–35 ms of the tap in every pair but one. The exception, Reduce Motion `.snappy` light-stripes appear (0 ms), is a same-frame start: Flutter's first changed frame shares its timestamp with the touch-up, after a 90 ms idle gap in the variable-rate video, and the event belongs to step 3's touch (the step pairing holds). Class: native latency that the package does not copy, by the user's ruling 33; project 5 re-checks it on a device, where touch delivery differs from the simulator's. The prototype read native 18–47 and 65–112 ms, Flutter 12–33 ms.

### Frame gaps over 25 ms inside events

| Run | Case | Native | Flutter | What was done |
|---|---|---|---|---|
| `20261005-233131` | default dark-photo | 28 | — | kept (native) |
| `20261005-233131` | default light-photo | 25, 25, 27 | — | kept (native) |
| `20261005-233131` | default light-stripes | — | 27 | repeated: `20261006-001644`, none |
| `20261005-233131` | `.snappy` dark-photo | — | 32, 25 | repeated: `20261006-002044`, none |
| `20261005-234750` | default dark-photo | 25 | — | kept (native) |
| `20261005-234750` | default light-photo | 25 | — | kept (native) |
| `20261005-234750` | default light-stripes | 25 | — | kept (native) |
| `20261005-234750` | `.bouncy` light-stripes | — | 30 | repeated: `20261006-002206`, none |
| `20261005-234750` | `.snappy` dark-stripes | 28 | — | kept (native) |
| `20261005-234750` | `.snappy` light-stripes | 28 | — | kept (native) |

The brief repeats only cases with a Flutter gap (the debug-build stall of spec §10). No Flutter first changed frame is more than 0.2 of the travel ahead of native's; the largest lead is 0.063. Flutter's first changed frame comes after a gap over 25 ms in five pairs of the substituted set: normal `.bouncy` dark-photo appear 28.3 ms, normal `.snappy` dark-stripes appear 26.7, Reduce Motion `.bouncy` dark-stripes appear 33.3 and Reduce Motion `.bouncy` light-stripes appear 28.3 (the repeat), at progress 0.04–0.08 against native's 0.02–0.05, and Reduce Motion `.snappy` light-stripes appear 90.0 ms at 0.02 (the same-frame start of the delay section above). Each is the variable-rate recorder's idle gap before an event, not a stall, since the first frame is not behind. Native first changed frames come after gaps of up to 50 ms before the disappear in many pairs of both runs; they were not checked for the capture-hole signature (a hole followed by sub-5 ms frames), which no harness check reads yet (`todo-2b1.md`).

### The cold first transition (Step 6)

`cold/20261006-002600`, `tool.materialize.cold` on dark `photo` with no warm-up, against native's case of `20261005-233131`:

| Event | Native first changed frame | Flutter first changed frame | 10–90% native / Flutter | Stalls |
|---|---|---|---|---|
| disappear (the launch's first transition) | after 33 ms, at progress 0.03 | after 35 ms, at progress **0.38** | 133 / **83** ms | native one, 28 ms; Flutter none |
| appear | after 13 ms, at 0.03 | after 15 ms, at 0.03 | 275 / 300 ms | none |

The first ghost of a launch in the debug JIT build drops its first frames, so its 10–90% reads 50 ms short. This is what the example's warm-up hides (ruling 24); recorded for project 5, not judged. The prototype read 38 ms at 0.38 and 83 against 133 ms for the disappear, 300 against 292 for the appear.

### The default spring against native (Step 4)

`fit.json`'s `default_spring_check`: over all four cases and takes native's default fits **0.58 s / 0.99** (RMS 0.028), against SwiftUI's 0.55 / 1.0: response 5.5% off, outside the 5% tolerance, so `pass` is false (the prototype read 0.57 / 0.98, `pass: true`). Per case all fail: dark-photo 0.59 / 0.98, dark-stripes 0.71 / 0.80, light-photo 0.50 / 1.14, light-stripes 0.44 / 1.30. This is a fact about native (ruling 10): one take's fitted spring varies by more than the tolerance between takes of one case, so no case decides SwiftUI's constant, and the presets stay SwiftUI's springs. No action.

### Rim depth (Step 8)

`rim_check.py build/glass_lab/fitvis/20261005-211745/table/ramp3.0 <run>` (`research/execution-2b1/task-20d-rim-normal.txt`, `research/execution-2b1/task-20d-rim-rm.txt`). Depth of the lit band under the top edge, in points:

| Case | Flutter at visibility 0.1–1.0 | Flutter at 1.0 | Native at rest | Native at progress 0.3 / 0.5 / 0.7, normal | the same, Reduce Motion |
|---|---|---|---|---|---|
| dark-photo | 0.67–1.0 (1.0 from 0.3) | 1.0 | 1.0 | 14.5 / 24 / 24 | 5.0 / 5.0 / 5.0 |
| dark-stripes | 0.67–1.0 (1.0 from 0.2) | 1.0 | 1.0 | 5.0 / 5.0 / 5.0 | 5.0 / 5.0 / 5.0 |
| light-photo | 0.67 throughout | 0.67 | 1.0 | 10.0 / 24 / 24 | 5.0 / 5.0 / 5.0 |
| light-stripes | 0.67–1.0 (1.0 from 0.6) | 1.0 | 1.67 | 5.5 / 5.33 / 5.33 | 5.33 / 5.33 / 5.33 |

Flutter's rim keeps its depth within one pixel (⅓ pt) of its depth at 1 from visibility 0.3 up in all four cases: `uFullThickness` reaches the geometry pass (finding 28). Native's rim is 5–24 pt deep mid-transition (5.0–5.33 pt under Reduce Motion, where there is no edge spread) against 1.0–1.67 pt at rest. That mismatch is ruling 14's open item, in `todo-2b1.md`. The prototype read the same ranges.

### Ghosts (Step 9)

Both `removal.png` sheets show the "Glass" label in place in every frame from release, fading with the glass, with no frame lacking glass or label (no blink). Mean difference of the region from `ready.png` after release:
- container, `ghost/20261006-014735`: 2.29, 2.93, 5.04, 7.80, 10.09, 11.90, 13.30, … 16.95 at +350 ms;
- `Overlay`, `ghost/20261006-014805`: 2.28, 2.89, 5.05, 7.76, 10.08, 11.87, 13.29, … 16.95.

Both rise with no jump, as the prototype's did (2.29, 2.93, 5.05, 7.77, 10.08 … 16.93).

## Done item 5: still glass against 2A

`still_check.py <2A run> <new run>` for each scene; outputs in `research/execution-2b1/task-20d-still-<scene>.txt`.

| Scene | 2A run | New run | Triples | Flutter frames byte-identical | missing | worse |
|---|---|---|---|---|---|---|
| `material.regular` | `20261002-200447` | `20261006-003104` | 20 | 20 | 0 | 0 |
| `material.clear` | `20261002-201611` | `20261006-004222` | 8 | 8 | 0 | 0 |
| `material.tinted` | `20261002-151504` | `20261006-004700` | 12 | 12 | 0 | 0 |
| `material.edge` | `20261002-202042` | `20261006-005342` | 12 | **0** | 0 | 0 |
| Reduce Transparency | `20261002-202731` | `20261006-010032` | 20 | 20 | 0 | 0 |
| Increase Contrast | `20261002-203837` | `20261006-011154` | 20 | 20 | 0 | 0 |
| `tabbar.rest` (Operator) | `20261002-205000` | `20261006-012309` | 16 | 16 | 0 | 0 |
| `button.press` (Operator) | `20261002-205855` | `20261006-013200` | 4 | 4 | 0 | 0 |
| `navbar.inline` (Operator) | `20261002-210140` | `20261006-013445` | 12 | 12 | 0 | 0 |

No static measure changed pass or fail in any scene. Recomputed with `still_check.compare`, the largest change of any measure is 0.0008: on byte-identical Flutter frames, `material.clear` dark-photo (`mad` 2.0206 → 2.0203, `luminance` 0.2727 → 0.2734), Increase Contrast light-white and `tabbar.rest` move by at most 0.0007, from native frames one or two levels off (ruling 28); `material.edge` moves by at most 0.0008 (`mad` 3.4663 → 3.4671 on automatic dark-scroll). Native frames differ from the 2A session's by 0 levels (102 of 124 frames), 1 level (8) or 2 levels (10), and by 229 on `button.press` (4), where native now draws the black touch marker that 2A did not and the region leaves out (ruling 7).

**`material.edge`: a 0.24 px rim snap, a renderer sampling defect classed (b) by the ledger's Task 20d ruling; no measure changed pass or fail.** All 12 Flutter frames differ from 2A's (maximum channel difference 16–32), in 1,334 pixels around the top-right "Edit" pill only (automatic dark-scroll `ready`); no measure changes pass or fail or moves by more than 0.0008 (the soft light-scroll `mad` fails at 4.07 before and after). 2A's edge runs are deterministic (`20261002-152214` and `-202042` are byte-identical). A least-squares fit of the rim profile shows the pill's left and right rims moved 0.235–0.249 px left and its top and bottom 0.000; its interior and label are identical (`research/execution-2b1/task-20d-edge-debug.md`). Cause: the pill sits at a fractional x (973.164 px). On a layer's first composite `GeometryTransformTrackingLayer` reports a transform change (`_lastTransform` starts null, `transform_tracking_repaint_boundary_mixin.dart:91-93`); the next paint turns the cached geometry into an image (`render_liquid_glass_geometry.dart:244`) that is drawn with nearest sampling at the fractional offset (`liquid_glass_render_object.dart:394`), so the rim snaps to the pixel grid. 2A escaped by sequence: its post-frame material change (side 88 to 44) forced a later exact rebuild. 2B.1 resolves the material at layout in the first frame (the member box's `performLayout`, `glass_motion_widgets.dart:92-95`, calls `GlassMember.sized`, which resizes the material at `glass_motion_coordinator.dart:284`; ruling 30), so nothing forces that rebuild. Probe run `20261006-020852`, with `render()` skipped, matches 2A byte for byte; `20261006-021029`, the committed code with traces, matches the Step 7 run. It is a latent fault of the fork's geometry cache, not a motion regression, and Done item 5 passes by the spec's definition. Both candidate fixes are in `todo-2b1.md`.

## Deviations from the plan and rulings

1. **Machine load during recordings.** Load averages: Task 8 native references about 45 (15-minute average at 00:54); Task 9 noise session 1 13–42, session 2 67–161; the Task 9 replacement takes 100–300 (Spotlight indexing, the Claude renderer and simulators; `research/execution-2b1/rerecord-uptime.txt`); Step 5 runs 11–20; Step 7 still runs about 43 at the start; ghost probes 10–13. Load plausibly affects XCUITest's touch timing (longer native holds and taps), the screen recorder's frame delivery (capture holes, native gaps of 25–28 ms) and the Flutter debug build's frame pacing. It does not reach still pixels: every noise take's static `mad` is 0.00, and 112 of 124 still Flutter frames are byte-identical to 2A's.
2. **Task 9: four native noise takes were screen-recorder capture holes.** In each, `simctl io recordVideo` delivered nothing for the first 68–407 ms of an event, then a burst of frames 1.7–6.7 ms apart, with the touch window zero-length; the native states equal the other takes' (`research/execution-2b1/task-9-outliers.md`, `research/execution-2b1/task-9-scan.md`). They were `material.materialize` light-stripes take 3, `.bouncy` dark-photo-reduce-motion take 3, `.bouncy` dark-stripes-reduce-motion take 3 and `.bouncy` light-stripes-reduce-motion take 4, all in session 2. They inflated the floors (light-stripes `step1e0.progress.t10_90_ms` 75 ms with them, 8.3 without). They were moved (not deleted) to `noise-2b1/excluded/` and replaced by narrowed `repeat --times 1 --into noise-2b1` takes (commit `fd30f969d`, only those four cases' 117 values changed; one bad replacement attempt also excluded). Then (Task 20b) the three replacements numbered 5 were renumbered 3, the slot their excluded takes left, because `fitvis` groups per-take spreads by take number across cases (`fitvis.py` `by_take`), and a take 5 present in three cases only made single-case groups. `noise.json` does not depend on take numbers. Press and interactive takes show the same burst-after-gap pattern in both sessions (24 takes flagged, 12 per session, `research/execution-2b1/task-9-scan.md`): the recorder writes nothing while the screen is still, and the press starts on the touch frame, so the pattern is endemic and re-recording would not remove it. They were kept, because 2B.1 judges no press measure; 2B.3 must re-examine them before judging press measures.
3. **Task 8 native references.** Native 10–90% times are one to three 120 Hz frames off the prototype's (`research/execution-2b1/task-8-report.md`): default disappear 141.7 against 125–133 ms (one frame), `.snappy` appear 216.7 against 200 (two), `.bouncy` appear 141.7 against 133 (one), Reduce Motion `.bouncy` appear 158.3 against about 133 (three), and native press holds are longer (interactive 2.13 and 2.87 s against 0.95 and 1.31; `press.250x44` 1.54 s against about 0.99), under heavy load. Sizes match (252.0 × 88.67 rest; 250 × 44 +14.33), and the spacing topology matches ruling 23 exactly. Accepted as references; Task 9's two-session floors absorb native's drift between sessions.
4. **Task 20 Step 4 fit.** The first fit (`fitvis/20261005-211745`) hit two stop conditions: the default's take 5 exponent 3.65 against the pooled 3.1, and `.bouncy`'s Reduce Motion gain 0.0 in take 3 and 1.24 in take 5 against the pooled 0.62. Both came from the case mix of item 2 (take 5 existed only in the three replaced cases), not from a deviant take. After the renumbering the second fit, reusing the scan shots in the same folder, was clean: default exponent 3.1 (takes 3.1–3.2), gain 0 (`identifiable: false`); `.snappy` 2.65 (2.65–2.75), gain 0 (`at_floor`), Reduce Motion gain 0 (`at_floor`); `.bouncy` 2.8 (2.7–2.95, one excluded curve, take 0 dark-stripes, RMS 0.467), gain 0.36 (0.32–0.42), Reduce Motion gain 0.62 (0.58–0.64); no value on a grid edge; blur ramp 3.0 (errors 1.14, 0.92, 0.84, 0.97 for k = 1–4); Flutter's mean progress at visibility 0.5 is 0.4223; the visibility table is unchanged. The `.bouncy` take 0 exponent (2.95) is 0.15 from the pooled value, outside the brief's ± 0.1 expectation and inside its ± 0.5 stop. The committed table (`58ab57e0c`) is byte-identical to `fitvis.table_source(fit.json)` and differs from the seed in three lines: `.snappy` exponent 2.7 → 2.65, `.bouncy` exponent 2.75 → 2.8, `.bouncy` appear gain 0.34 → 0.36. `default_spring_check` fails (above), a native fact (ruling 10), not a stop.
5. **Task 20 Step 5 repeats.** The three cases with a Flutter gap were repeated alone and the stall-free repeat kept in each: default light-stripes (27 ms; 12 of 14 before and after), Reduce Motion `.bouncy` light-stripes (30 ms; 10 → 12) and normal `.snappy` dark-photo (32 and 25 ms; 11 → **10**). The last was kept for being stall-free although it passes one measure fewer, so the normal total is 130 as run and 129 substituted. The four Flutter first-frame gaps over 25 ms and the 0 ms delay are explained above.
6. **`material.edge`'s changed frames** are the latent geometry-cache sampling fault above. Ruling: not fixed in 2B.1. The one-line fix (never turn the cache into an image) disables the geometry cache that the roadmap decided to keep (2026-09-27) and that M10 measures in 2B.3; the proper fix is model work. No measure moved, and Done item 5 passes by the spec's definition.
7. **Tests beyond the plan.** Task 8 strengthened one plan assertion: `test_press_scenes_hold_one_press_on_one_tracked_glass` now pins the six glass heights `[44, 54, 58, 88, 120, 200]` (the 138 × 53 region rounds to 54); the harness count is unchanged at 175. Task 13 added one package test: an identity glass inserted later appears at once. The package count is therefore 122, the plan's 121 plus one.
8. **Done item 1's 250 × 44 number** reads +14.33, not the spike's +17.67, for ruling 2's cause (above). Recorded as not reproduced.

## Gates

At `58ab57e0c`, with `--no-pub`:
- app (`packages/mobile`): `flutter analyze` "No issues found!", `flutter test` `+2146: All tests passed!`;
- package (`packages/ios_liquid_glass`): `flutter analyze` "No issues found!", `flutter test` `+122: All tests passed!`;
- example: `flutter analyze` "No issues found!", `flutter test` `+13: All tests passed!`;
- harness: `python3 -m unittest discover tool/glass_lab/harness/tests`, `Ran 175 tests`, OK.

`flutter test` prints the known SkSL error about `liquid_glass_geometry_blended` (ROADMAP gotcha 3). `xcrun simctl spawn 708879DD-8B2A-4547-863F-F49EE1474D8B defaults read com.apple.Accessibility ReduceMotionEnabled` prints `0`.
