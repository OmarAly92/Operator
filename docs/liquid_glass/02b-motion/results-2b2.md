# 2B.2 results

Date: 2026-10-09. Branch `feat/ios-liquid-glass-2b2`. The Task 27 recordings (merge, union, morph, N7 spacing, respace, materialize, the first nine still runs) were measured at the package of `5d34a69fc` plus the plan's tasks; no `lib/` code changed between them and ruling 33 (`55f3d833a`). The ruling-33 re-runs (the nine still scenes, `navbar.inline`, and the merge, union, morph and spacing checks below) were measured at `55f3d833a` (the later `50b5ed28c` changes no pixel). Noise floors: Task 25's, five takes per case over two boots; the six 2B.1 spacing scenes keep 2B.1's. Decisions taken: D1 A (ruling 30; the median member's row accepted by the user; the still check covers pinned groups only; per-glass materials in one layer carried to project 3), D2 A (ruling 31), D3 A (user-approved manifest correction of 2026-10-07, ruling 26; morph tracked at the stack's outer edges only, the heart and the bolt not tracked individually, carried to 2B.3 or a fix wave), D4 hand-placed 1.5, not tool-written (ruling 23), D5 (onset frame fixed, the rest carried), D6 spacing animation kept (ruling 12): **native animates `spacing`: yes** (Task 26). Ruling 33 and the `navbar.inline` decision are the user's of 2026-10-08.

**What this document does not claim.** Done items 1 to 3 still fail in part, as the plan forecast. **Spec §8's "still glass no worse than 2A" is broken on one scene, `navbar.inline`**, and that is the user's decision of 2026-10-08 (ruling 33 below), not a pass. Nothing in this table was reached by loosening a limit or a measure: no limit was lowered or raised by hand, 4 limits rose through Task 3's recompute (gotcha 52, below), and the Task 25 floors raised 114 to 407 limits per run.

## The Done table

| Done item (spec §8, 2B.2) | Result | Evidence |
|---|---|---|
| 1 `material.merge`, `material.union` and `material.morph` pass, normal and Reduce Motion: per-shape motion, join and split timing, neck width over time, component count | **Failing in part** (every case has failing measures). Merge normal dark-photo 58/68/68, dark-stripes 48/68/68, light-photo 54/68/68, light-stripes 44/68/68; Reduce Motion 56/68/68, 42/67/68, 51/68/68, 45/68/68. Morph normal 49/83/213, 35/80/148, 43/80/148, 43/83/148; plain 46/92/148, 46/92/148, 46/94/148, 46/92/148; Reduce Motion 50/89/148, 45/90/148, 69/93/148, 60/91/148; plain Reduce Motion 54/95/148, 58/101/148, 84/101/148, 77/101/148. Union: item 2. The one-frame mirror at the onset is gone (0 of 16 merge onsets, the toggle holds 451); the heart now emerges from the toggle (432-450, baseline 344) | merge `20261008-043622` / `-044149`; morph `-044933` (rerun C `-071523` used; reruns A `-070956`, B `-071241` not used) and `-050026` (rerun D `-071642` used; rerun E `-071925` not used); `table-*.txt`, `analysis-step6.md` |
| 2 The rebuilt union scene passes its still-image measures | **Light-stripes passes 19/19/19** (`mad` 3.981 against 4); **dark-stripes fails 14 of 19** (5/18/19): (a) material residual, shadow, rim; (c) mask | `20261008-044717`, `table-union-normal.txt`, `analysis-step6.md` 4, ruling 17 |
| 3 The N7 spacing scenes pass their still-image and topology measures | **7 of 46 cases pass** (baseline 6); counts agree at 173 of 178 topology entries (baseline 173); necks within 1 pt in 50 of 70 (49), gaps in 89 of 103 (90); no dark-photo case passes | `20261008-051131`, `table-spacing-normal.txt`, `analysis-step6.md` 5 |
| 4 Still glass is no worse than 2A; gates | **Eight of nine scenes: `missing: 0`, `worse: 0`, all Flutter frames byte-identical to 2B.1's** (regular 20, clear 8, tinted 12, edge 12, reduce-transparency 20, increase-contrast 20, button.press 4, tabbar.rest 16 after one rerun: see below); **`navbar.inline`: `worse: 12` against 2B.1, accepted by the user (2026-10-08, ruling 33), class (a); the scene's ratchet baseline is now `20261008-225125`** (repeat `-225900`, `worse: 0`, 12 of 12 byte-identical). Gates: below | `final-checks/`, `still-check-navbar-inline-ruling33.txt`, `navbar-ruling33-columns.txt`, `crops/navbar-inline-ruling33-dark-black.png` |
| (carried) 2B.1 Done item 4 | materialize **296 / 336 / 336** progress measures (normal 147 of 168, Reduce Motion 149 of 168; events and touches 120 of 120), **judged under the gotcha 52 floors of Task 3 and with exponents fitted on the same takes (in-sample, ruling 22); 2B.1's 266 of 336 was judged under the old floors: not the same yardstick** | `20261008-074231`, `-075846`, `done-table-materialize.txt`, Task 27 Step 7 |
| (new) Spacing animation, ruling 12 | **native animates `spacing`: yes.** Widen: first differing frame 98 ms (light) / 81 ms (dark) after the touch, join at 152 / 161 ms, neck within 1 pt of its final value after 23 / 24 frames; narrow: split at 236 / 145 ms. `material.respace` light 13/17/27, dark 11/17/27; the motion events are absent (class (b): the tracker never tests neck or gap). Flutter against native count-change time: light widen -16 ms, narrow +5; dark widen +10, narrow +110 ms (`neck_rms` 16.0, 6 frames disagree) | `20261008-041322`, `respace-*.txt`, `table-respace.txt`, Task 26 |

Classification of every item: item 1 **expected** failures in part (the plan forecast them); item 2 light-stripes **passing**, dark-stripes **expected**; item 3 **expected**; item 4 **passing on eight scenes, `navbar.inline` a classed failure accepted by the user**; carried item 4 **judged** (in-sample); spacing animation **judged**.

## Judged / expected counts (passing / judged / expected)

Counts are one recording per case, no mixing; reruns C and D replace their originals (clean `take_check`), A, B and E are still flagged so the originals count (Task 27 Step 6).

| Scene | Appearance | Normal | Reduce Motion |
|---|---|---|---|
| `material.merge` | dark photo | 58/68/68 | 56/68/68 |
| `material.merge` | dark stripes | 48/68/68 | 42/67/68 |
| `material.merge` | light photo | 54/68/68 | 51/68/68 |
| `material.merge` | light stripes | 44/68/68 | 45/68/68 |
| `material.morph` | dark photo, dark stripes, light photo, light stripes | 49/83/213, 35/80/148, 43/80/148, 43/83/148 | 50/89/148, 45/90/148, 69/93/148, 60/91/148 |
| `material.morph.plain` | same four | 46/92/148, 46/92/148, 46/94/148, 46/92/148 | 54/95/148, 58/101/148, 84/101/148, 77/101/148 |
| `material.union` | dark stripes, light stripes | 5/18/19, 19/19/19 | not applicable |
| `material.spacing.*` | 23 scenes, light and dark photo | 7 of 46 cases pass | not applicable |
| `material.respace` | dark photo, light photo | 11/17/27, 13/17/27 | not run |

`expected` is not constant between takes (morph dark-photo normal 213, the others 148): the 65-measure `collapsed` set exists in only one of two recordings. Measures that passed in the baseline and fail now: 64 (merge 10, spacing 1, morph 53), listed in `analysis-step6.md` (2); in every one the limit is unchanged or higher than the baseline's, none was lowered. Newly passing: merge 92 and 85, union 6, morph 166 and 237, spacing 1; of those under the baseline's own limit: 42, 28, 6, 99, 113, 1.

## Merge and morph, the old and the new manifest on the same recordings (D3)

Prototype recordings at the package before Tasks 13-24; counts are passing / judged (finite) / expected. The manifest correction is the user's (2026-10-07), not a loosening: ruling 26.

| Run (prototype) | Case | Old manifest | New manifest | Final package, Task 27 |
|---|---|---|---|---|
| `20261007-054755` merge | dark photo, dark stripes, light photo, light stripes | 20/41/66, 24/45/66, 25/44/66, 25/46/66 | 24/61/68, 30/67/68, 29/62/68, 33/68/68 | 58/68/68, 48/68/68, 54/68/68, 44/68/68 |
| `20261007-055356` merge, Reduce Motion | same four | 20/41/66, 22/45/66, 27/46/66, 26/46/66 | 24/63/68, 26/67/68, 33/68/68, 32/68/68 | 56/68/68, 42/67/68, 51/68/68, 45/68/68 |
| `20261007-060205` morph and plain | same four each | normal 19/59/126, 24/55/126, 29/55/126, 31/58/126; plain 22/65/180, 17/61/126, 25/59/126, 16/36/126 | normal 25/73/148, 28/69/148, 33/69/148, 36/72/148; plain 27/80/213, 21/75/148, 29/73/148, 17/43/148 | normal 49/83/213, 35/80/148, 43/80/148, 43/83/148; plain 46/92/148, 46/92/148, 46/94/148, 46/92/148 |
| `20261007-061306` morph and plain, Reduce Motion | same four each | 29/64/180, 26/59/126, 34/60/126, 39/62/126; plain 21/62/126, 26/60/126, 31/60/126, 29/60/126 | 35/79/213, 31/73/148, 40/74/148, 47/76/148; plain 28/76/148, 35/74/148, 37/74/148, 36/74/148 | 50/89/148, 45/90/148, 69/93/148, 60/91/148; plain 54/95/148, 58/101/148, 84/101/148, 77/101/148 |

## Gotcha 52, the limits that moved

Task 3 excluded take 2 of `material.materialize/light-photo-reduce-motion` (its onset read 98 ms before the glass moved), recorded take 5 on a fresh boot (press 0.958 s, `take_check` PASS, first-frame gap 18.3 ms, no hole) and recomputed that case's noise: **25 values and 19 limits moved: 15 lower and 4 higher** (the prototype had 27, 18 and 3 with a different replacement take). The four limits that rose, and the take that set each (take 5 of that case):

| Measure | Limit before -> after | Noise before -> after |
|---|---|---|
| `block.step1e0.luma.peak_ms` | 62.5 -> 75.0 | 41.67 -> 50.0 |
| `block.step3e0.cy.peak_ms` | 50.0 -> 62.5 | 33.33 -> 41.67 |
| `block.step3e0.cy.settle_ms` | 37.5 -> 50.0 | 25.0 -> 33.33 |
| `block.step3e0.luma.peak_ms` | 25.0 -> 62.5 | 16.67 -> 41.67 |

The fifteen that fell: `step1e0` `cy.peak_ms` 150 -> 37.5, `cy.settle_ms` 150 -> 25, `height.peak_ms` 125 -> 17, `height.settle_ms` 150 -> 25, `luma.damping` 0.57 -> 0.105, `luma.response_pct` 335.71 -> 13.04, `luma.settle_ms` 150 -> 17, `progress.damping` 0.57 -> 0.105, `progress.response_pct` 335.71 -> 13.04, `progress.settle_ms` 150 -> 17, `width.peak_ms` 125 -> 17, `width.settle_ms` 150 -> 25, `delay_ms` 150 -> 42.5; `step3e0` `progress.damping` 0.15 -> 0.12, `progress.t10_90_ms` 37.5 -> 25. Each limit follows max(fixed, 1.5 x noise). **The Task 3 recompute check at the final harness (Task 27 Step 7): 0 values and 0 limits moved**; `noise-recompute-final.txt`. 2B.1's 266 of 336 was judged under the old floors, so it is not comparable with 296 of 336 now. The plan's dangling-link count of 0 printed 14: all 14 are inside `excluded/`, which `relink_noise.py` skips by design and nothing reads (ruling E3 below).

Task 25 then recorded 62 cases at five takes each over two boots (presses 0.932 to 0.990 s, none outside 0.8-1.2 s): 841 outliers over 62 cases, 754 of them set a limit (`noise-outliers.txt`); static repeatability max 0.0022 (a failure would have stopped the task). The six 2B.1 spacing scenes keep their 2B.1 floors.

## Failures, classed

The per-measure lists (every failing measure of every case, with its value, limit and class) are in `research/execution-2b2/analysis-step6.md` (3.1 merge, 3.2 morph and plain, 4 union, 5 spacing, 6 events and touches) and the `table-*.txt` files; the classes by family:

| Group | Case | Class | Value against limit | Evidence |
|---|---|---|---|---|
| Merge `cx`, `xmin`, `xmax` spring and timing, join and split time, `neck_rms`, `gap_rms` (68 normal, 78 Reduce Motion) | all 8 | (a) | join native 208 ms (dark-stripes Reduce Motion 192), Flutter 225-233; split native 58-83, Flutter 92-100; spring native 0.32-0.45 s / 1.08-1.36, Flutter 0.48-0.50 / 1.04-1.11; worst `right.s3.cx.response_pct` 39 > 7.89 | `analysis-step6.md` 3.1; the fix round moved the onset, not the response |
| Merge dark-stripes Reduce Motion: pair read as two components in 12 frames of a joined piece (`count` 7, `join_ms` 41.7, `split_ms` absent) | dark-stripes RM | (c) | mask | `crops/step6-merge-dark-stripes-rm-mask-misread-flutter.png` |
| Static `bbox_pt` 4-8, `centre_pt` 2-4 on dark backgrounds (merge, morph, union, N7 spacing 23 of 23 dark-photo) | dark cases | (a) the shadow tail | Flutter's tail sits 4.2-6.4 luma below the edge against native's 1.9, crossing the detector's 6-level threshold 8 pt lower | `crops/step6-merge-shadow-dark-photo-native-flutter-diff.png`, `union_tone.py` |
| Morph toggle `cy` and `width` timing, spring, overshoot; stack `ymax`, `ymin` finite | all 16 | (a) | width peak 58.0-58.7 against native 71.0-71.7 (no swelling); spring 0.55-0.59 / 0.94-1.00 against 0.28-0.33 / 1.70-1.98; `cy.peak_ms` 83-167 > 17-37.5, `overshoot_pct` 11-19 > 2 | `analysis-step6.md` 3.2 "what the frames say" |
| Morph badges `cy` and `width` finite, stack topology (`count` up to 39 normal and 52 Reduce Motion, `join_ms`, `split_ms`, `neck_rms`, `gap_rms`) | all 16 | (a), with a (b) share | all three badges arrive together at full size (r 27.7-29.4) where native grows heart, bolt and star in turn; the stack goes 1 -> 4 at 398-403 ms where native goes 1 -> 2 at 310-373 | `analysis-step6.md` 3.2 and 9; ruling 18 and 21 |
| Morph and plain: absent or invalid measures (collapsed region, inner glasses, the star's top edge): 553 of 895 failing (normal), 423 of 687 (Reduce Motion) | all 16 | (b) | key absent, fit invalid, native fit at the grid edge | ruling 26 and D3; the per-glass tracker is a carry-in |
| `events.unpaired` fails in 9 of 16 morph and plain cases | 4 normal, 5 Reduce Motion | (a); plain dark-photo [2, 3] (c) probable | native's event starts at touch-down (the press glow), Flutter has none | `analysis-step6.md` 6 |
| `ready.topology.stack.neck_pt` 23.7 > 1 | morph dark-stripes | (c) | native's still mask loses the orange-stripe half of the collapsed toggle | baseline 3f, unchanged |
| Union dark-stripes: `mad` 6.485 > 4, `luminance` 4.991 > 3, `rim_rms` 6.201 > 6, `bbox_pt` 8, `centre_pt` 3.5; topology counts 1, 3, 4 against native's 3, 4, 7 | dark-stripes | (a) material residual, shadow, rim; (c) the mask | Flutter dark glass is 3.5-7.1 luma darker than native's per stripe (baseline 9.5-14.8); native's own mask breaks into 3, 4 and 7 components | `analysis-step6.md` 4, `crops/step6-union-dark-stripes-mask.png` |
| N7 spacing: 39 of 46 cases fail | dark photo 23, light photo 16 | (a) shadow, the pinch; (c) the dark mask | native snaps a neck at a point, Flutter keeps a 5.3-7.0 pt smudge; counts differ at S20 g10/g11, S40 g20/g21, S80 g40 | `analysis-step6.md` 5, `crops/step6-spacing-20b-g10-pinch.png` |
| `material.respace`: no motion event, `events.native_motion` 0 < 1, every `topology.*` of `pair` absent | both | (b) | the tracker's event test (bbox, centre, mean difference, luma) never tests neck or gap | `table-respace.txt`, Task 25 Step 5 |
| Materialize: 40 of 336 progress measures fail (sharpness, settle, response, damping) | normal and Reduce Motion | (a) / (b) as 2B.1's H1 to H6; in-sample fit | e.g. snappy dark-photo step1e0 damping 0.130 > 0.050 | `done-table-materialize.txt` |
| **`navbar.inline`: `rim_rms` (dark-black, dark-white, light-black, light-stripes) and `bbox_pt` 5 -> 6 (dark-black, light-black), ready and settled: 12 worse** | six cases | **(a), accepted by the user** | dark-black rim_rms 22.20 -> 27.50, dark-white 26.60 -> 48.16, light-black 57.60 -> 96.06, light-stripes 35.56 -> 53.51 | ruling 33 below |
| `tabbar.rest` light-white, first run only: two triples differ (selection on PRs, mid-transition) | light-white | (d) a one-off capture, no step in the scene | Flutter frame max difference 241 | two single-case reruns are byte-identical to 2B.1's; not counted (below) |
| Three native morph takes still flagged by `take_check` after one rerun (dark-photo normal, light-photo normal, light-stripes Reduce Motion) | 3 | not classed (d): no take excluded | gaps 377/355/2313/17 ms at step 1 | ledger Task 25 Step 5 and Step 6; the flag is "capture hole suspected" on a pattern that passing takes show |

Hold-out of the topology masks (ruling 2, not tuned): 72 frame judgements by eye against the mask, 0 disagreements in merge, 2 in the morph collapse (20.517 and 20.532, class (c): the fading star ghost splits the mask; native flickers the same way). `analysis-step6.md` 8.

## Provisional limits

None after Task 25: every 2B.2 scene has noise floors (the six 2B.1 spacing scenes keep theirs). The still-image measures of the nine 2A scenes keep their 2B.1 limits.

## Ruling 33: coincident glass joins the union once (navbar.inline)

**Why `navbar.inline` was regressing.** The lab scene passed two `GlassButton.icon` actions to `GlobalAppbar.sub`; the bar wraps every trailing action in `GlassBarItem`, itself glass, so each action put two 44 pt shapes on one rect into the container's blend group (five shapes with the back button). 2B.1's quadratic union returns `d - k/4` for two coincident shapes, 5 pt at k = 20 pt: it drew each action as a 54 pt circle (162 px; native and the back button are 44 pt) and the bloated circles overlapped into a 36 pt neck. The angle weight of 2B.2 is 0 for parallel normals, so coincident copies no longer bloat the circles (now 44 pt), the neck is a real one, and a seam appeared: the fold's normal output is discontinuous at the bisector between the two buttons, so the second copy re-blends on one side only (field step 7.69 px across the bisector, neck 20.7 pt left against 16.0 pt right, frame run `20261008-093137`). The app's own screens pass non-glass actions, so the double glass was a lab-scene artefact; the real app's bar has one glass per action. The diagnosis, with the model against both frames to about 1 pt, is `research/execution-2b2/navbar-diagnosis.md`; its two key claims were re-checked first (two identical 44 pt shapes per action; `smin(d, d) = d - k/4` = 5 pt at k = 20 pt).

**Fix (user decision of 2026-10-08, option A; commit `55f3d833a`).** (a) The lab scene passes non-glass `IconButton` actions as the app's screens do. (b) `RenderLiquidGlassBlendGroup.gatherShapeData` skips a candidate with the same rect (1e-3 pt) and the same outline as an earlier one: a rounded rectangle whose radius is at least half the side of a square is an oval, other outlines compare by shape and effective radius; the skipped member still paints. The model of rulings 7 to 10 is untouched (join at spacing / 2, k = spacing, default 8, the angle weighting; no shader edited). Tests, red first: `glass_group_test` +9 (the render-object guard; the geometry shader cannot compile in `flutter test`), `coincident_union_test` +6 (continuity across the bisector, necks 12.41 pt at the bisector and 15.82 pt at x = 335, the doubled geometry as a recorded hazard: step above 7 px and a neck thinner by more than 2 pt), `lab_navigation_scenes_test` +1 (two bar items, no glass nested in glass, 44 x 44 each).

**Before and after** (dark-black frame columns, `navbar-ruling33-columns.txt`; crop `crops/navbar-inline-ruling33-dark-black.png`):

| | 2B.1 | seam run `20261008-093137` | corrected `-225125` and `-225900` | native |
|---|---|---|---|---|
| column at x = 335 pt | 36.0 | 22.0 | 16.0 | 44.0 |
| column just left / right of the bisector | 36.00 / 36.67 | 20.67 / 16.00 | 13.33 / 13.33 | 44 / 44 |
| button diameter | 54 pt | 44 pt | 44 pt | one 102 x 44 capsule |
| `rim_rms` dark-black / dark-stripes / dark-white | 22.20 / 16.70 / 26.60 | 27.81 / 16.52 / 44.98 | 27.50 / 13.17 / 48.16 | |
| `rim_rms` light-black / light-stripes / light-white | 57.60 / 35.56 / 44.80 | 92.26 / 54.58 / 44.80 | 96.06 / 53.51 / 44.80 | |
| `bbox_pt` dark-black / dark-stripes / dark-white | 5 / 6 / 6 | 6 / 5 / 5 | 6 / 5 / 5 | |
| `bbox_pt` light-black / light-stripes / light-white | 5 / 5 / 8 | 6 / 5 / 8 | 6 / 5 / 8 | |

The corrected render is repeatable: the second run is byte-identical to the first in 12 of 12 frames. **N7 and merge numbers did not change**: the two-circle blend of `blend-at-spacing` is two distinct circles, nothing is dropped; the model's rows are as measured (S4 0.165, S6 0.47, S8 0.374, S10 0.502, S12 0.502, S16 0.334, S20 0.421, S40 0.427, S80 0.413). The ruling-33 re-run check is below.

**What is broken, plainly.** Spec §8's "still glass no worse than 2A" is broken on `navbar.inline`: its 2B.1 pass depended on a 5 pt bloat of the doubled glass that native does not have (class (a)), and no correct union can restore it: every correct model draws a thinner neck at x = 335 (quadratic deduplicated 17.2 pt, angle deduplicated 15.8 pt) against 2B.1's 36 pt and native's 44 pt, and getting 36 pt from two 44 pt circles 8 pt apart under the angle model needs a spacing of 52.3 pt, or restoring w = 1 for parallel normals, which ruling 9 rejects. **This is the user's decision of 2026-10-08**, option A. The ratchet baseline for `navbar.inline` moved to the corrected render by recording it with `lab.py run` (run `20261008-225125`, repeated by `-225900`) and checking it with `still_check.py`; the repository holds no baseline file (the baseline is a run folder named in the plan), which is itself a carry-in (`todo-2b2.md`). **Native draws the trailing items as one 102 x 44 capsule; that is a project 3/4 carry-in, not done here.** Operator's nav bar is unchanged.

## Ruling 33 re-run check: the guard changes no N7, union, morph or merge frame

Rebuilt (`lab.py build all`), fresh boot (press 0.950 s PASS), then the nine still scenes, `navbar.inline`, and merge (normal and Reduce Motion), union, morph and plain (normal and Reduce Motion) and the N7 spacing scenes, recorded again at `55f3d833a`, one lab command at a time (press 0.977 s PASS before the motion batch; disk 65 GB down to 50 GB, never under 45). Files: `research/execution-2b2/final-checks/` (`guard-effect-summary.txt`, `still-check-*.txt`, `table-rerun-*.txt`, the run indexes).

- **The nine 2A still scenes, against 2B.1's archive runs (`still_check.py`): `missing: 0`, `worse: 0`, every Flutter frame byte-identical** in material.regular (20 of 20), clear (8), tinted (12), edge (12), reduce-transparency (20), increase-contrast (20), button.press (4) and tabbar.rest (16). tabbar.rest's first run read 14 of 16: light-white `ready` and `settled` had the selection on PRs, mid-transition (Flutter frame difference up to 241), in a scene with no step; two single-case reruns (`20261009-001054`, `-001205`) are byte-identical to 2B.1's in both frames, so the first run's light-white case is a one-off capture accident, unexplained, and is not counted. **`navbar.inline`: worse 12 against 2B.1, and byte-identical to its own repeat (12 of 12): the classed failure above.**
- **N7 spacing (23 scenes, 46 cases): 92 of 92 Flutter frames byte-identical** to the Task 27 run `20261008-051131`, and all 46 cases equal in pass / judged / expected and in the set of failing measures. **Union: 4 of 4 frames identical, 5/18/19 and 19/19/19 again, the same failing measures.** Merge, merge Reduce Motion, morph and morph Reduce Motion: every `ready.png` and `settled.png` of the Flutter app is byte-identical (8, 8, 16 and 16 frames). The two-circle blend numbers of N7 are as measured: S4 0.165 ... S80 0.413 (the guard drops nothing from two distinct circles).
- **The moving counts of a re-recorded case scatter, in both directions, and Flutter's own fits do not move.** Merge normal 52/66/68, 44/68/68, 47/68/68, 50/68/68 against the counted 58, 48, 54, 44; Reduce Motion 54, 41/68, 48, 48 against 56, 42/67, 51, 45; morph 48/87/213, 36, 45, 43 and plain 47, 44/94 (the counted rerun C read 46/92), 46, 47 against 49, 35, 43, 43 and 46, 46, 46, 46; morph Reduce Motion 45, 41, 56, 63 against 50 (rerun D), 45, 69, 60 and plain 55, 53, 89, 79 against 54, 58, 84, 77. Each re-run re-records native too: Flutter's spring fits (response, damping ratio) of the measures failing in both recordings agree to at most 0.01 / 0.02 (merge, 26 measures), 0.02 / 0.04 (merge Reduce Motion, 21), 0.06 / 0.08 (morph, 182) and 0.08 / 0.11 (morph Reduce Motion, 139), median 0.00, where native's own fits differ by up to 0.05 / 0.25, 0.24 / 0.41 and 0.17 / 0.13 between the two recordings. **The counted numbers in the Done table stay Task 27's (as recorded and analysed in `analysis-step6.md`); the re-run is a second sample and shows the recording scatter of one case, up to 13 measures (morph Reduce Motion light-photo 69 against 56).** Not shown by bytes: the video frames of the moving cases. The argument that the guard cannot be what moved them: it fires only for two members on one rect and outline, a nested pair would also show at rest, and every rest frame is byte-identical (`guard-effect-summary.txt`).
- After the review below the guard also lets a member take the place of a ghost on its rect (`50b5ed28c`); that changes which render object stands for the shape, not a pixel, and only in a container at its sixteen-shape cap.


## Gates at the final tree

Run at `50b5ed28c` (the final code; docs commits only after it), from `packages/mobile`:

- `flutter analyze --no-pub` in the app, `packages/ios_liquid_glass` and `packages/ios_liquid_glass/example`: "No issues found!" in all three.
- `flutter test --no-pub`: app **+2189**, package **+239**, example **+25**: "All tests passed!" in all three (before ruling 33: +2188, +222, +25; ruling 33 added +1 app, +17 package: `glass_group_test` +11 including the two ghost tests of the review, `coincident_union_test` +6).
- `python3 -m unittest discover tool/glass_lab/harness/tests`: **Ran 253 tests ... OK**.


## Disclosure: the previous executor's rulings, and how this branch was executed

Rulings of the first executor (the ledger, `research/execution-2b2/ledger.md`), numbered E1 to E10 so they do not collide with the plan's 32 rulings and ruling 33:

- **E1. Per-task reviewers were skipped for the patch-replay tasks 1 to 24b.** The plan's patches came from a reviewed prototype (41 patches, 113 runs, 0 problems in the replay), the implementer ran every fail-first and gate step, and the whole-branch review at the end covers the branch; the user watches usage. Cost if wrong: a defect found at the end review instead of per task. The final review (below) is that review.
- **E2. Implementers and mechanical helpers ran on model sonnet.**
- **E3. Task 3 Step 3's dangling-link count printed 14, not 0.** `relink_noise.py` skips `excluded/` by design; the 14 are the links inside the folders Step 2 moved there; nothing reads `excluded/`; the count outside it is 0.
- **E4. Take 5's first-frame gap is 18.3 ms, not the plan's 68-407 ms**: that range is the capture-hole signature (gotcha 47); `take_check` PASS says no hole.
- **E5. Three patches were regenerated from the prototype, not applied from the brief's text**: `t05-tests` and `t05-impl` (Task 5) and `t06-impl` (Task 6) were regenerated with `git diff` between the prototype commits the brief names, restricted to the task's files, with index hashes equal to the brief's. The end check, a file-for-file comparison of the final tree against `proto/2b2`, is below.
- **E6. Task 9 was done before Task 8**, a mistake of order; harmless (Task 9 touches only `lab.py` and `test_lab.py`, which Task 8 does not).
- **E7. Task 10's red run's first error line** was `glass_materialize_test.dart:21:83`, not `:30:43`: the same missing symbol, compiler ordering.
- **E8. No take was excluded at Task 25 Step 5.** `take_check` flagged 28 of 40 `material.morph` takes (the tap branch, capture hole), 9 of 10 `material.respace` takes (the touch step owns no event) and crashed on the union and the 23 spacing scenes (no touch steps). Judgement: the flags are a tracker problem, not captures with a hole: none of the 40 morph takes has a zero-length touch window or a touch count other than 2; the 380-420 ms and 2.3-3.0 s first-frame stalls are the still screen before the tap, present in passing takes with the same values; 10-90 % times of the stack height agree between passing and failing takes (no squeezed take); gotcha 47's actual signature is absent. Respace's missing events are the tracker's event test never testing neck or gap (class (b)). Cost if wrong: floors for morph include takes with a stall that is not a fault; reversible by recomputing from the takes on disk. **The plan names none of this**; it is a deviation for the main session (`noise-take-check.txt`).
- **E9. The Step 6 rerun cases C and D replaced their originals; A, B and E did not.** Clean reruns (`take_check` PASS on both apps) of morph.plain dark-stripes normal and morph dark-photo Reduce Motion count; the reruns of the other three are still flagged, so their originals count. Cost if wrong: counts for those cases (46/80/148, 43/84/148 and 58/93/148 would be the rerun values).
- **E10. Task 27 Step 9 stopped on `navbar.inline`** (shader not tuned, as the plan says) and reported; the user's decision of 2026-10-08 followed (ruling 33).

Other deviations: Task 25 stopped once on disk (44 GB free) and resumed after the main session answered; the disk fell from 107 to 98 GB across group A session 2 (the ledger); the group B recording wrote about 4.5 GB, not the 25 GB the plan projected.

**Execution of ruling 33 (this session).** Press 0.950 s after a fresh boot, 0.977 s before the motion re-runs; disk 65 GB at the start and 62 GB at the end (never under 62); only the iOS 27 simulator `708879DD-8B2A-4547-863F-F49EE1474D8B`; no lab run was stopped (I killed only two shell wrappers that were waiting to start the next batch); no limit or measure changed; nothing pushed or merged.

## Final whole-branch review

Done by the executor of ruling 33 (the first executor skipped the per-task reviewers, E1), at `50b5ed28c`. What it covered and found:

- **File for file against `proto/2b2`** (the reviewed prototype the plan was generated from): over `packages/mobile/packages`, `tool`, `lib/core/widgets` and `test/core/widgets` the only differences are `noise.json` (the plan expects it), the three ruling-33 files and tests, and two files that come from `development` having moved since the prototype (`settings_group.dart`, `ROADMAP.md`). Tasks 5 and 6's regenerated patches (E5) are therefore covered by this comparison.
- **No comment lines were added** to any Dart, Python, GLSL or Swift file of the branch against `development` (`git diff` of added lines, searched for `//` and `#` comments). No `package-lock.json`, `.g.dart` or `frontend/` file is in the diff; the branch touches only `packages/mobile` and `docs/liquid_glass`.
- **Gates** at the final tree: above. The counts equal the ledger's after Task 24b (+222, +25, +2188, 253) plus ruling 33's additions.
- **The new guard** was read against its callers: `getPath(shapes)` (`render_liquid_glass_geometry.dart:221`) draws each shape's path, and a dropped member's path equals the kept one's by construction; `paintShapeContents` walks `link.shapeEntries`, not the shape list, so a dropped member still paints. **One defect found and fixed** (`50b5ed28c`): when a ghost registered before a member on the same rect, the guard kept the ghost and dropped the member, and the sixteen-shape cap then removes ghosts first, so a container at the cap could lose both; a member now takes a ghost's place (two tests, red against the first version by construction). The guard compares against earlier candidates in registration order (O(n squared) over at most sixteen shapes per paint); a union's non-leading members are skipped before it, as before.
- **What this review did not do:** it did not re-read the 41 replayed patches line by line (the replay and the two plan reviews did, and the file-for-file comparison says they match), did not re-run the real-app checks of the earlier tasks, and did not check the moving frames of the cases above by bytes. The main session's independent code review and measurement audit are still to come.

