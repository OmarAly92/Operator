# Measurement audit: ios_liquid_glass 2B.2 results

Auditor: independent, read-only. Branch `feat/ios-liquid-glass-2b2`, worktree `/Users/omaraly/development/AI/Operator-2b2`, tip `78ffa9b51`. Date 2026-10-09.

**Verdict: Results are sound after corrections.** I reproduced every count in the Done table from `result.json`, using limits I rebuilt from `noise.json`. I found no stale build, no limit that differs from `noise.json`, no lowered limit, and no denominator that dropped a required measure. Five corrections are needed, none of which flips a Done item's verdict:
- The prototype-to-final comparison mixes yardsticks (A1).
- One broken native take feeds the morph.plain floors (A2).
- Single takes have a large leverage on the counts, and this is not disclosed (A3).
- Class (b) "absent" hides real class (a) differences, and that misdirects the todo item (A4).
- The tabbar.rest rerun is under-disclosed and its cause is misread (A5).

Findings: blocker 0, major 4, minor 4, note 6.

## What I ran and recomputed

All scripts are in `scratchpad/audit/`. They read run folders and write only to the scratchpad. The one exception is `still_check.py`, which is read-only.

- `recount.py`: passing / judged / expected from `result.json` for every case of the counted runs, the reruns A–E, the ruling-33 reruns and the prototype runs. Each limit is rebuilt as max(fixed, 1.5 × `noise.json`) and each check is redone from value, limit and bound.
- `flips.py` and `framematch.py`: for the four merge cases and morph Reduce Motion light-photo, the per-measure flips between Task 27 and the ruling-33 re-run, split into native and Flutter fits and topology times. I also matched video frames between the two recordings.
- `noise_loo.py` and `noise_effect.py`: I recomputed all 62 Task 25 floors from the ten pair `result.json` of each case in `runs/noise-2b2`. I ran a leave-one-take-out on every case and re-judged the counted runs under each leave-one-out floor. I recomputed the four gotcha-52 limits from `runs/noise-2b1`.
- `take_timeline.py`: touch windows (marker frames extracted to the scratchpad) against glass motion, using the cached frames and `ffprobe` times, for 6 noise takes and the respace native takes.
- `series_why.py`: I copied morph light-stripes (`-044933`) to the scratchpad and recomputed its shape series with the harness. The recomputed measures equal the stored ones. I then explained each absent key.
- `still_check.py`: the nine 2A still scenes against the 2B.1 archive, for both the Task 27 Step 9 runs and the ruling-33 runs, plus the two tabbar reruns and the navbar repeat.
- `navbar_measure.py`: glass columns and diameters in the 2B.1, seam, corrected (×2) and native `navbar.inline` dark-black frames.
- Frames I opened: the navbar crop, the tabbar first-run video (a 4 fps tab-bar contact sheet), the merge join and morph collapse hold-out crops, the merge dark-stripes Reduce Motion misread crop, and the union native and Flutter frames.
- `done_table.py` on the materialize runs `-074231` and `-075846`, with a per-measure comparison against the prototype runs `20261007-071931` and `-073538`.

Nothing was recorded. I did not touch the simulator or edit any recording, `noise.json` or archive data. Disk stayed at 50 GB free.

## Findings

**A1. Major. The D3 table and analysis (1) compare the prototype and the final package under different limits.**

Claim: the prototype counts (new manifest: merge 24/30/29/33, morph 25/28/33/36 …) are set against the final package (58/48/54/44, 49/35/43/43 …), and "nothing … was reached by loosening a limit".

What I recomputed: the prototype `result.json` were judged under the prototype floors. I rejudged the same prototype recordings under today's `noise.json` (`recount.py` on `Operator-2b2-proto/.../20261007-054755`, `-055356`, `-060205`, `-061306`). Prototype → final on the same yardstick:

| Scene | Same-yardstick prototype → final |
|---|---|
| merge | 32/38/29/34 → 58/48/54/44 |
| merge Reduce Motion | 39/41/38/33 → 56/42/51/45 |
| morph normal | 42/36/43/49 → 49/35/43/43 |
| plain | 32/23/31/19 → 46/46/46/46 |
| morph Reduce Motion | 43/40/57/58 → 50/45/69/60 |
| plain Reduce Motion | 29/37/45/46 → 54/58/84/77 |

On one yardstick, morph normal is flat (dark-stripes 36 → 35, light-photo 43 → 43) and light-stripes is lower (49 → 43). The merge gain is about half of what the table suggests.

Results line 36 gives the "under the baseline's own limit" counts, but no table shows the same-yardstick numbers. The limits themselves agree with the executor: 0 lowered and 114/118/378/406 raised (analysis says 407 for morph Reduce Motion with rerun D; I get 406). The 64 measures that passed before and fail now: 64 ✓.

Correction: add a same-yardstick column (the prototype recordings under the final `noise.json`) to the D3 table and to analysis (1). Say that the morph normal and plain-control gains are mostly floors and the recording, not package change.

**A2. Major. A broken native take feeds the floors: `noise-2b2/takes/material.morph.plain/light-stripes-reduce-motion/0`.**

Claim (E8): no take is excluded. Only the `take_check`-flagged morph and respace takes were examined; morph.plain takes were not opened.

Evidence:
- The take's video gives two timelines. The glass-region frames (`shapes/`, `ffprobe`) jump from 8.563 s to 15.923 s, and the glass moves at 16.04 s and 18.99 s. The marker crop of the same video has frames through 9.05 s and reads touch windows (9.053, 9.068) and (12.045, 12.065).
- Those windows are 15 and 20 ms long, against 88–94 ms in take 1, where touch and motion coincide at 16.10 / 16.22 s.
- In every pair with take 0: native events 5 against 2 (3 unpaired), `step1e0` delay 1213 ms (siblings 5–28), a 97 ms stall, and no stack split or join in either step.

This is gotcha 47's family: near-zero touch windows and motion owned by the wrong step.

The take alone sets 60 limits of the case. Examples, with the limit without it in brackets: `stack.step1e0.topology.count` 57 (0), `bolt.step3e0.cy.peak_ms` 437.5 (17), `star.step3e0.width.response_pct` 89 (5), `step1e0.delay_ms` 1812.5 (35). Excluding it moves plain light-stripes Reduce Motion from 77 to 70. Flutter's `stack.step1e0.topology.count` of 1 passes only under the 57 limit.

Correction: exclude the take and record a replacement after a fresh boot, as gotcha 52 did, then recompute that case's floors. Until then, report 70/101/148 beside 77, or flag the case.

**A3. Minor. Single takes carry most of the floor leverage, and the count effect is not stated.**

Recomputed:
- Pair maxima equal `noise.json` in all 62 cases (0 differences).
- Of 5924 measure-case limits, 935 are set by exactly one take: excluding that take alone lowers the limit. Another 1862 are set by a single pair.
- Re-judged under leave-one-out floors, single takes move the counted cases by up to 22 measures:
  - plain light-photo Reduce Motion without take 2: 84 → 62
  - plain dark-stripes Reduce Motion without take 0: 58 → 47
  - merge dark-stripes Reduce Motion without take 4: 42 → 32
  - morph light-photo Reduce Motion without take 2: 69 → 59
  - merge dark-photo Reduce Motion without take 0: 56 → 48
  - plain light-stripes Reduce Motion without take 0: 77 → 70 (A2)

E8 holds for the high-leverage takes I opened, apart from the A2 take. In morph light-photo Reduce Motion /2 and plain light-photo Reduce Motion /2, touch-down and glass motion coincide (17.397 / 17.400 s; 16.195 / 16.33 s) and the motion spans match their siblings. Their leverage is real spread, not a capture fault.

Correction: state the leave-one-out range per case next to the counts. The 754-of-841 outlier note does not convey that one take decides up to 22 measures of a case.

**A4. Major. The class (b) "absent" share contains real class (a) differences that the measure's net-travel gate hides.**

Claim: 553 of 895 normal and 423 of 687 Reduce Motion morph failures are absent or invalid, class (b), the "per-glass tracker" carry-in, and "until then these measures cannot pass".

Recomputed (`absent.py`, matching 553 and 423 exactly):

| Cause | Normal | Reduce Motion |
|---|---|---|
| Key absent | 420 | 360 |
| Native fit invalid (grid edge / RMS) | 104 | 58 |
| Both fits invalid | 20 | 4 |
| Flutter fit invalid | 2 | 0 |
| Topology non-finite | 7 | 1 |

`heart.width` and `bolt.width` are absent in all 17 counted cases of each mode, and `collapsed.cy` and `collapsed.width` likewise.

Why absent: `shapes.compare_key` drops a key when either app's net travel |end − start| is under 4 pt. The series exist and are finite in both apps. Morph light-stripes normal, recomputed in the scratchpad (excursion = peak-to-peak):

| Key | Native excursion | Flutter excursion |
|---|---|---|
| `heart.step1e0.width` | 37.3 pt | 2.0 pt |
| `bolt.step1e0.width` | 15.6 | 2.0 |
| `collapsed.step1e0.cy` | 9.3 | 2.0 |
| `collapsed.step1e0.width` | 11.7 | 1.7 |
| `heart.step3e0.width` | 57.2 | 38.7 |
| `bolt.step3e0.width` | 20.0 | 9.5 |

The net travel is under 4 pt in both apps, so each key is "absent". These are round-trip changes that native has and Flutter lacks, the same emergence and no-growth difference the analysis calls (a) in its section 9. The tracker sees them; the gate discards them.

The counts are unaffected (an absent key fails), but the class and the todo fix are wrong. A large part of the 553/423 is (a). The fix is a measure that scores excursions (peak-to-peak or peak against time) on round-trip keys, not only a new tracker.

Correction: reclassify the absent heart, bolt and collapsed keys as (a) where the native and Flutter excursions differ by more than the floor. Rewrite the `todo-2b2.md` row "Per-glass tracking …" to name the net-travel gate.

**A5. Minor. The tabbar.rest first run printed `worse: 6`, and its cause is visible.**

Claim: tabbar.rest's first run read 14 of 16; the light-white case was "a one-off capture accident, unexplained … no step in the scene", and it is not counted. The Done table shows "tabbar.rest 16 after one rerun", and line 14 says eight scenes `worse: 0`.

Recomputed: `still_check.py` on `-235737` prints `worse: 6` (light-white ready and settled: mad 9.41 → 14.90, bbox_pt 1 → 12, centre_pt 0 → 3.5/4.0). The results never state that `worse: 6`. The 16 of 16 is assembled from two runs: 14 from `-235737` plus 2 from the single-case rerun `-001054`.

The Flutter video of that take: from about 12 s to 17.25 s of video, the tab bar's drag lens moves PRs → Settings → Agents → PRs. The ready screenshot at 15.21 s caught it on PRs. `driver.log` has no tap. Something the driver did not send was touching the tab bar for about 5 s: input from outside the lab, consistent with a drag on the simulator window. It is not an encoder accident.

Correction: state `worse: 6` on the first run and the two-run assembly, and name the cause as an input the driver did not send. Find the input source before any further recording, since it can hit any take.

**A6. Minor. Gotcha 52: two of the four raised limits are not set by take 5.**

Recomputed from `noise-2b1/material.materialize/light-photo-reduce-motion/pair-*`. The values (50, 41.67, 33.33, 41.67 → limits 75, 62.5, 50, 62.5) match ✓.

`step1e0.luma.peak_ms` is set by take 5 (pairs 1-5 and 4-5) ✓. `step3e0.luma.peak_ms` comes from the single pair 1-5; without take 5 it is 8.33, so take 5 drives it ✓.

`step3e0.cy.peak_ms` and `cy.settle_ms` are different: without take 1 they are 8.33, without take 5 they are 33.33 / 25. Take 1 is the outlier there, against take 5 in the claim. None of the four is a judged materialize measure: materialize judges only `progress.*` and statics, so they do not touch 296/336.

Correction: attribute the step 3 `cy` limits to the pair (1, 5), with take 1 the driver. Say that the four raised limits are unjudged in materialize.

**A7. Minor. Materialize carry-in: 296/336/336 reproduces; the prototype comparison is "11 lost, 18 gained", not 8.**

`done_table.py` gives 147/168 and 149/168, with events and touches 120/120 ✓. Against the prototype (289/334), 11 measures that passed now fail:
- snappy dark-photo: 2
- snappy light-photo: 2
- default dark-photo Reduce Motion: 2
- default light-stripes Reduce Motion: 2
- bouncy dark-stripes Reduce Motion: 1
- snappy dark-photo Reduce Motion: 1
- snappy light-photo Reduce Motion: 1 (sharpness 0.993 → 1.075)

18 now pass that failed. Every one of the 11 has the same limit in both runs, so the cause is recording scatter (each run re-records native and Flutter with the exponents fixed), not a limit.

What 296 proves: with the H4 exponents, the appear stays within the gotcha-52 floors in 296 measures against fresh native takes. What it does not prove:
- Out-of-sample fit: the exponents and floors come from the same take set.
- Any comparison with 2B.1's 266, which used different floors.
- Precision better than about ±10 measures, given 11 lost and 18 gained between two recordings of the same code.

**A8. Minor. The toggle spring quoted for native is not the judged fit.**

Results and todo give native toggle 0.28–0.33 s / 1.70–1.98 against Flutter 0.55–0.59 / 0.94–1.00 (from the `R/morph` tracker). The harness fits that set pass/fail for `toggle.step1e0.cy` are:
- native 1.50 at the grid edge / 0.69–0.81 in all four normal cases, which makes them fit-invalid and absent;
- native 1.38–1.44 / 0.67–0.69 in Reduce Motion;
- Flutter 1.14–1.26 / 0.70–0.75.

The two trackers read the same native takes as overdamped and as underdamped. This is not explained, and it matters for the "fit the toggle spring to native" item in the todo.

**A9. Note. The native join at spacing/2 is exact from S4 to S40 and for the default 8, not at S80.**

Recomputed from `-051131` native counts:
- S8 g4 joined, g8 split; S16 g8 joined; S20 g10 joined, g11 split; S40 g20 joined, g21 split.
- default.a g4 joined, default.d g5 split ✓.
- At S80, native joins at g38 and splits at g40 in both appearances, so its threshold lies in (38, 40).

The executor classes S80.c light g40 as a Flutter class (a). It is equally a 1–2 pt departure of native from the copied rule at large spacing.

**A10. Note. The denominator depends on how many Flutter events pair.**

213 against 148 is an extra paired event label (`step1e1`: 50 track, 10 stack-edge and 5 topology measures), not "the 65-measure `collapsed` set". An unpaired native event costs one gate measure (`events.unpaired`); a paired one adds 65 mostly failing measures.

No required measure drops out:
- Touch-step labels are always expected.
- An absent key fails.
- respace [0,1] / [0,2] keeps its 10 motion measures as failures.

Correction: fix the wording at results line 36 and analysis (1).

**A11. Note. Native's trailing group is 304 px = 101.33 pt wide, not 102.**

Columns 854–1157 in both the 2B.1 and the corrected native frames. The "6 pt width difference (102 against 96)" is 5.33 pt.

**A12. Note. The hold-out covers only Flutter, light-stripes.**

The 48 merge-join and morph-expand frames and the 24 collapse frames are all Flutter, light-stripes. My reading of the crops agrees with the eye column: two pieces until 17.487 and touching at 17.503; at the collapse, one piece plus the fading star at 20.517–20.532 where the mask reads 4 and 3. The dark-stripes misread (12 frames) was found outside the hold-out.

Results line 86 should say "Flutter, light-stripes only"; the mask's reliability on dark backdrops is not established by it.

**A13. Note. Re-recording scatter, verified as recording rather than Flutter.**

The question was whether Flutter's behaviour changed between Task 27 and the ruling-33 re-run. I matched video frames between the two recordings:
- Merge dark-photo: the motion frames (126–148, 211–234) map one-to-one with a 2-frame shift, with mean absolute difference 0.12–0.21, the H.264 noise level.
- Merge light-stripes and morph Reduce Motion light-photo: the motion frames match at 0.05–0.16.
- The only mismatches are the launch and navigation frames before the first tap.

So Flutter rendered the same motion states, and the guard changed nothing in motion.

The flips come from three sources:
- Native refits, for example merge dark-photo `right.step3e0.cx`: native 0.43/1.10 → 0.23/2.00 at the grid edge, which is infinite.
- The 8.3 ms grid: Flutter's join reads 225 or 233 ms run to run.
- Touch sampling: Flutter's `step1e0` delay 0.0 → 18.3 ms in light-stripes.

The executor's verdict is confirmed. The Done table reports Task 27's sample. Both samples are valid, but a single case moves by up to 13 measures (morph Reduce Motion light-photo 69 / 56), so the counts carry that uncertainty. Report the pair, or a range.

**A14. Note. The navbar.inline diagnosis is proved, not only plausible.**

- Shapes: at `55f3d833a^` the scene passed two `GlassButton.icon` (a `GlassSurface` circle, size 44) into `GlobalAppbar.sub`, which wraps each trailing action in `GlassBarItem` (a `GlassSurface` capsule, extent 44, `global_appbar.dart:125`). With the back button that makes five glass shapes. The scene file is unchanged since `da4c9630e`, before 2B.1.
- 2B.1 frame: trailing circles 54.0 pt tall (top 57.0, bottom 110.67, against 62.0 / 105.67 now), that is 44 + 2 × 5 = k/4 at k = 20.
- Columns at x = 335: 36.0 (2B.1), 22.0 (seam), 16.0 (corrected, both runs), 44.0 (native). At the bisector the corrected frame reads 13.33 on both sides.
- Crop: the 2B.1 frame shows the inner 44 pt rim inside each bloated circle.

A corrected scene with two separate 44 pt circles 8 pt apart cannot reach 44 pt at x = 335 under any correct union. Native's one 101.3 × 44 capsule is reachable only by a different layout (one shared capsule), which is the carry-in already named.

The nine-scene still check reproduces:
- Task 27 Step 9: 112 of 124 triples byte-identical; navbar `worse: 12`.
- Ruling-33 runs: eight scenes `missing: 0`, `worse: 0`, all Flutter frames identical (tabbar after the rerun, see A5).
- navbar `-225125` and `-225900`: `worse: 12` each, and identical to each other (12 of 12).

## Recomputed numbers

| Item | Claimed | Recomputed | Source | Match |
|---|---|---|---|---|
| Merge normal | 58/68/68, 48/68/68, 54/68/68, 44/68/68 | same | `-043622` | yes |
| Merge Reduce Motion | 56/68/68, 42/67/68, 51/68/68, 45/68/68 | same | `-044149` | yes |
| Morph normal | 49/83/213, 35/80/148, 43/80/148, 43/83/148 | same | `-044933` | yes |
| Plain normal | 46/92/148 ×2, 46/94/148, 46/92/148 | same (dark-stripes from rerun C `-071523`) | | yes |
| Morph Reduce Motion | 50/89/148, 45/90/148, 69/93/148, 60/91/148 | same (dark-photo from rerun D `-071642`) | `-050026` | yes |
| Plain Reduce Motion | 54/95/148, 58/101/148, 84/101/148, 77/101/148 | same | `-050026` | yes |
| Reruns A, B, E | 46/80/148, 43/84/148, 58/93/148 | same | `-070956`, `-071241`, `-071925` | yes |
| Union | 5/18/19, 19/19/19 | same | `-044717`, `-003722` | yes |
| N7 spacing | 7 of 46 | 7 of 46 (the same seven) | `-051131`, `-012639` | yes |
| Respace | 11/17/27, 13/17/27; events [0,1] / [0,2] | same | `-041322` | yes |
| Limits against `noise.json` | max(fixed, 1.5 × noise) | 0 differences in all counted, rerun, ruling-33, N7 and materialize runs | `recount.py` | yes |
| Ruling-33 merge | 52/66, 44, 47, 50; Reduce Motion 54, 41/68, 48, 48 | same | `-001436`, `-002558` | yes |
| Ruling-33 morph | 48/87/213, 36, 45, 43; plain 47, 44/94, 46, 47 | same | `-003940` | yes |
| Ruling-33 morph Reduce Motion | 45, 41, 56, 63; plain 55, 53, 89, 79 | same | `-010310` | yes |
| D3 old manifest | 20/41/66 … | same as the logs; same recordings (identical events and stall lists) | `R/verify/logs` | yes |
| D3 new manifest | 24/61/68 … | same under the prototype's limits; under today's floors 32/38/29/34 (merge) … (A1) | proto runs | yes, but a different yardstick |
| Limits raised / lowered against prototype | 114/118/378/407 raised, 0 lowered | 114/118/378/406 raised, 0 lowered | | 406 against 407 |
| Passed in baseline, fail now | 64 | 64 | | yes |
| Class (b) absent, morph | 553 of 895 / 423 of 687 | same; 420 / 360 are net-travel gates, many hiding (a) (A4) | `absent.py` | count yes, class no |
| Noise floors, 62 cases | `noise.json` | 0 differences from pair maxima | `noise_loo.py` | yes |
| Single take sets limit | 754 of 841 outliers | 935 of 5924 limits set by one take (different definition) | `noise_loo.py` | not comparable |
| Gotcha-52 limits | 75 / 62.5 / 50 / 62.5, all from take 5 | values yes; step 3 `cy` driven by take 1 (A6) | `noise-2b1` pairs | partly |
| Materialize | 296/336/336 (147, 149), 120/120 | same | `-074231`, `-075846` | yes |
| Materialize, passed in prototype now failing | 8 (brief) | 11 (18 newly pass) | proto `-071931`, `-073538` | no |
| Still check, Task 27 | 112 of 124 identical; navbar `worse: 12` | same | Step 9 runs | yes |
| Still check, ruling 33 | eight scenes `worse: 0` | seven `worse: 0` on the first run; tabbar `worse: 6` until rerun (A5) | `-230550` … `-000641` | partly |
| Navbar columns at x = 335 | 36 / 22 / 16 / 44 | 36.0 / 22.0 / 16.0 / 44.0 | frames | yes |
| Navbar 2B.1 diameter | 54 pt | 54.0 pt | frame | yes |
| Native trailing width | 102 pt | 101.33 pt | frame | no (A11) |
| Merge join / split, native | 208 (Reduce Motion dark-stripes 192) / 58–83 ms | same | `result.json` | yes |
| Flutter join / split | 225–233 / 92–100 ms | same | `result.json` | yes |
| Respace native widen | first changed frame 98 ms, join 152 ms (light) | 16.373 s and 16.427 s against touch-down 16.275 s | series | yes |

## Items for the user

1. **Noise take `material.morph.plain/light-stripes-reduce-motion/0` (A2):** approve its exclusion. A replacement then has to be recorded on the iOS 27 simulator after a fresh boot, and that case's floors recomputed. I changed nothing.
2. **Simulator input during recording (A5):** something drove the tab bar for about 5 s during `-235737`, with no tap in the driver log. Check whether you or another process was using the simulator around 00:01 on 2026-10-09, and keep it exclusive while recording.
3. **D3 table (A1):** decide whether `results-2b2.md` should show the same-yardstick prototype numbers. Under one yardstick, morph normal shows no package gain.
4. **Morph carry-in (A4):** the follow-up for absent per-glass measures should be an excursion-aware measure; a new tracker is not the gap. A large share of those failures is (a).

## Not checked, and why

- The `R/morph` pipeline numbers: heart, bolt and star first-seen times and radii, the 1 → 2 and 2 → 4 stack times. Re-running that tracker is heavy and its relation to the judged fits is already in question (A8).
- Respace Flutter-against-native count-change times (−16, +5, +10, +110 ms) and `neck_rms` 16.0.
- `k = spacing` and the N7 neck RMS rows (S4 0.165 … S80 0.413). They need the model scripts, not recordings.
- The Task 25 press-gate values (0.932–0.990 s) and the 841 / 754 outlier counts under the executor's 3 × median rule. I used a leave-one-out definition instead.
- `take_check.py` itself: it calls `shapes.capture`, which deletes and rewrites `shapes/` inside the recordings (gotcha 51). I used scratchpad extractions instead.
- Gates, code and the guard's implementation: the other reviewer's scope.
