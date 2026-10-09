# Task 27 Step 6: analysis of the final package's runs against the prototype baseline

**Corrections of fix wave 1 (2026-10-09; the text below is as first written).** (1) Plain Reduce Motion light-stripes reads **73/101/148**, not 77, under the floors of the replaced noise take (`results-2b2.md`, "The second broken take"); the "morph + plain RM" row of section (2) reads newly passing 233 (not 237) and limits raised 404 (not 407; 406 on a recount). (2) The "old" and "new" manifest columns were judged under the prototype's own limits; the same recordings under today's floors are in the D3 table of `results-2b2.md`. (3) The extra 65 measures of the 213-measure cases are one more paired event label (`step1e1`), not a `collapsed` set, and no required measure drops out of a denominator. (4) The "absent" failures of section 3.2 are class (a) where the net-travel gate of `shapes.compare_key` drops a round-trip key (420 of 553 normal, 360 of 423 Reduce Motion), not class (b). (5) The toggle spring quoted for native comes from the `R/morph` tracker, not from the fits that decide pass or fail. (6) The hold-out of section (8) covers Flutter light-stripes frames only.

Measured package: the worktree at the Task 27a recording (commit 30a757902 holds the tables). Scripts: `R` = `docs/liquid_glass/02b-motion/research/proto-2b2`, `table.py`, `frames_at.py`, `crop.py`, `union_tone.py`, `still_masks.py`, `n7_table.py`, `R/onset/*`, `R/morph/{extract,morph_track,analyze_morph}.py` with `R/verify/{morph_compare_v,morph_table}.py`, all with `--harness tool/glass_lab/harness` from `packages/mobile`. Nothing recorded, no simulator command, no code edit.

Runs (`packages/mobile/build/glass_lab/runs/`): merge normal `20261008-043622`, merge Reduce Motion (RM) `-044149`, union `-044717`, morph + plain normal `-044933`, morph + plain RM `-050026`, spacing `-051131`, respace `20261008-041322`. Baselines: prototype `20261007-054755` / `-055356` / `-055926` / `-060205` / `-061306` / `-062403` (their `result.json` are the new-manifest re-analysis for merge and morph, so measure names, values and limits of the baseline are read from them; `table.py` on them reproduces `R/verify/logs/table-newmanifest-*.txt` line for line, checked on `-054755` and `-060205`).

**Case counts used (one recording per case, no mixing).** The 27a tables are used as they are, except for the two cases whose rerun is clean (`take_check` PASS on both apps): `material.morph.plain dark-stripes` normal (original 32/52/148 had "touch step 1 owns no event" in the native take) takes rerun C `20261008-071523` (46/92/148); `material.morph dark-photo-reduce-motion` (original 53/93/148, native "capture hole at step 1") takes rerun D `-071642` (50/89/148). The plain dark-photo RM case of rerun D is not used (its original take was not flagged). Reruns A (`-070956`, morph dark-photo normal), B (`-071241`, morph light-photo normal) and E (`-071925`, morph light-stripes RM) are still flagged after the one rerun, so their originals count (49/83/213, 43/80/148, 60/91/148); their reruns would read 46/80/148, 43/84/148, 58/93/148. Note for the flags: Task 25f (`noise-take-check.txt`) found `take_check`'s tap branch flags 28 of 40 `material.morph` takes of the noise recording too, on a pattern passing takes show, so a flag is "capture hole suspected", not a confirmed hole; the 133 ms native stall in the morph light-stripes normal take sits 770-900 ms after the touch, after the motion has settled (t90 385 ms), so it touches no motion measure.

## (1) Per scene and case: pass / judged / expected

Final = this run; old = prototype, old manifest; new = prototype recordings re-analysed with the D3 manifest (the last column of the D3 table of the plan is "final").

| Scene | Case | Old manifest | New manifest | Final |
|---|---|---|---|---|
| merge | dark-photo | 20/41/66 | 24/61/68 | **58/68/68** |
| merge | dark-stripes | 24/45/66 | 30/67/68 | **48/68/68** |
| merge | light-photo | 25/44/66 | 29/62/68 | **54/68/68** |
| merge | light-stripes | 25/46/66 | 33/68/68 | **44/68/68** |
| merge RM | dark-photo | 20/41/66 | 24/63/68 | **56/68/68** |
| merge RM | dark-stripes | 22/45/66 | 26/67/68 | **42/67/68** |
| merge RM | light-photo | 27/46/66 | 33/68/68 | **51/68/68** |
| merge RM | light-stripes | 26/46/66 | 32/68/68 | **45/68/68** |
| union | dark-stripes | 3/16/19 | 3/16/19 | **5/18/19** |
| union | light-stripes | 15/19/19 | 15/19/19 | **19/19/19** |
| morph | dark-photo | 19/59/126 | 25/73/148 | **49/83/213** (rerun A 46/80/148, flagged) |
| morph | dark-stripes | 24/55/126 | 28/69/148 | **35/80/148** |
| morph | light-photo | 29/55/126 | 33/69/148 | **43/80/148** (rerun B 43/84/148, flagged) |
| morph | light-stripes | 31/58/126 | 36/72/148 | **43/83/148** |
| morph.plain | dark-photo | 22/65/180 | 27/80/213 | **46/92/148** |
| morph.plain | dark-stripes | 17/61/126 | 21/75/148 | **46/92/148** (rerun C; original 32/52/148) |
| morph.plain | light-photo | 25/59/126 | 29/73/148 | **46/94/148** |
| morph.plain | light-stripes | 16/36/126 (Flutter hole, touches [2,1]) | 17/43/148 | **46/92/148** (touches [2,2]) |
| morph RM | dark-photo | 29/64/180 | 35/79/213 | **50/89/148** (rerun D; original 53/93/148) |
| morph RM | dark-stripes | 26/59/126 | 31/73/148 | **45/90/148** |
| morph RM | light-photo | 34/60/126 | 40/74/148 | **69/93/148** |
| morph RM | light-stripes | 39/62/126 | 47/76/148 | **60/91/148** (rerun E 58/93/148, flagged) |
| morph.plain RM | dark-photo | 21/62/126 | 28/76/148 | **54/95/148** |
| morph.plain RM | dark-stripes | 26/60/126 | 35/74/148 | **58/101/148** |
| morph.plain RM | light-photo | 31/60/126 | 37/74/148 | **84/101/148** |
| morph.plain RM | light-stripes | 29/60/126 | 36/74/148 | **77/101/148** |
| spacing | 46 cases | 6 of 46 pass | 6 of 46 | **7 of 46 pass** (item 5) |
| respace | dark-photo / light-photo | none | none | **11/17/27 / 13/17/27**; events [0,1] / [0,2], native `events.native_motion` 0 < 1 and every `topology.*` of `pair` absent (the tracker sees no native motion event); static: bbox 3 and centre 1.5 (dark), `rim_rms` 7.36 (light) |

Judged rises in every case (merge reaches 68 of 68 in 7 of 8 cases). Expected: merge 68, union 19, morph 148 except the two cases whose pairing yields the 213-measure set (morph dark-photo normal; baseline had it on plain dark-photo normal and morph dark-photo RM). No scene passes (every case has failing measures); counts are not totals-comparable, see (2).

## (2) By measure name against the baseline

"Newly passing" = failed (or absent) in the baseline, passes now; "under the baseline limit" = the new value would also pass the baseline's limit; the rest pass only because the case's limit rose (noise floor of Task 25; **no limit was lowered in any case of any scene**; "limits raised" counts measures present in both whose limit is above the baseline's).

| Run | Newly passing | of which under the baseline limit | only under a raised limit | Passed in baseline, fails now | Limits raised |
|---|---|---|---|---|---|
| merge normal (4 cases) | 92 | 42 | 50 | 4 | 114 |
| merge RM | 85 | 28 | 57 | 6 | 118 |
| union | 6 | 6 | 0 | 0 | 0 |
| morph + plain normal (8) | 166 | 99 | 67 | 28 | 378 |
| morph + plain RM (8) | 237 | 113 | 124 | 25 | 407 |
| spacing (46) | 1 | 1 | 0 | 1 | 0 |

Newly passing includes measures absent in the baseline now finite (merge 11 normal / 6 RM, morph 51 normal / 98 RM). `expected` differs between takes (213 or 148) so the morph dark-photo takes compare 65 measures of the `collapsed`/event set that exist in only one of the two recordings (`onlyb`/`onlyc`: morph dark-photo normal +65, plain dark-photo normal -65, morph dark-photo RM -65 against the baseline).

**Every measure that passed in the baseline and now fails (64).** Columns: baseline value, final value, limit baseline -> final (a value is the absolute difference of the two apps for timing measures; a limit that rose is a floor).

| Run | Case | Measure | Baseline | Now | Limit |
|---|---|---|---|---|---|
| merge |  light-stripes | left.s3.xmin.peak_ms | 8.33 | 58.3 | 17 -> 17 |
| merge |  light-stripes | right.s3.cx.peak_ms | 8.33 | 58.3 | 17 -> 17 |
| merge |  light-stripes | right.s3.xmax.peak_ms | 16.7 | 66.7 | 17 -> 17 |
| merge |  light-stripes | right.s3.xmax.settle_ms | 16.7 | 33.3 | 17 -> 17 |
| merge RM |  dark-stripes-reduce-motion | left.s3.cx.peak_ms | 0 | 167 | 17 -> 150 |
| merge RM |  dark-stripes-reduce-motion | pair.s1.topo.count | 0 | 7 | 0 -> 0 |
| merge RM |  dark-stripes-reduce-motion | pair.s1.topo.split_ms | 0 | absent | 17 -> 17 |
| merge RM |  light-photo-reduce-motion | right.s1.xmax.settle_ms | 8.33 | 41.7 | 17 -> 25 |
| merge RM |  light-stripes-reduce-motion | left.s3.xmin.peak_ms | 8.33 | 33.3 | 17 -> 17 |
| merge RM |  light-stripes-reduce-motion | right.s3.xmax.peak_ms | 16.7 | 25 | 17 -> 17 |
| morph | morph dark-photo | heart.s3.cy.damping | 0.05 | absent | 0.05 -> 0.05 |
| morph | morph dark-photo | stack.s3.ymin.peak_ms | 8.33 | 117 | 17 -> 37.5 |
| morph | morph dark-photo | star.s3.width.damping | 0.04 | absent | 0.05 -> 0.06 |
| morph | morph dark-photo | toggle.s1.cy.overshoot_pct | 0 | 11 | 2 -> 2 |
| morph | morph dark-photo | toggle.s1.width.peak_ms | 16.7 | 108 | 17 -> 25 |
| morph | morph dark-photo | toggle.s3.cy.overshoot_pct | 0 | 16.9 | 2 -> 2 |
| morph | morph dark-stripes | heart.s3.cy.settle_ms | 0 | 66.7 | 17 -> 25 |
| morph | morph dark-stripes | stack.s3.ymax.settle_ms | 0 | 41.7 | 17 -> 25 |
| morph | morph dark-stripes | toggle.s1.width.peak_ms | 16.7 | 108 | 17 -> 62.5 |
| morph | morph dark-stripes | toggle.s3.cy.peak_ms | 16.7 | 83.3 | 17 -> 17 |
| morph | morph dark-stripes | toggle.s3.cy.settle_ms | 8.33 | 83.3 | 17 -> 25 |
| morph | morph dark-stripes | toggle.s3.width.settle_ms | 8.33 | 91.7 | 17 -> 37.5 |
| morph | morph light-photo | stack.s3.ymax.settle_ms | 0 | 66.7 | 17 -> 25 |
| morph | morph light-photo | toggle.s1.width.peak_ms | 0 | 83.3 | 17 -> 62.5 |
| morph | morph light-photo | toggle.s3.cy.peak_ms | 16.7 | 100 | 17 -> 37.5 |
| morph | morph light-photo | toggle.s3.cy.settle_ms | 16.7 | 91.7 | 17 -> 37.5 |
| morph | morph light-photo | toggle.s3.width.settle_ms | 16.7 | 100 | 17 -> 37.5 |
| morph | morph light-stripes | heart.s3.cy.overshoot_pct | 1.67 | 9.92 | 2 -> 3.55 |
| morph | morph light-stripes | star.s1.width.overshoot_pct | 1.14 | 3.02 | 2 -> 2 |
| morph | morph light-stripes | toggle.s1.cy.peak_ms | 16.7 | 158 | 17 -> 37.5 |
| morph | morph light-stripes | toggle.s1.width.peak_ms | 16.7 | 108 | 17 -> 37.5 |
| morph | morph light-stripes | toggle.s3.cy.peak_ms | 8.33 | 91.7 | 17 -> 50 |
| morph | morph light-stripes | toggle.s3.cy.settle_ms | 0 | 83.3 | 17 -> 62.5 |
| morph | morph light-stripes | toggle.s3.width.settle_ms | 0 | 83.3 | 17 -> 50 |
| morph | morph.plain dark-photo | events.unpaired | 0 | 1 | 0 -> 0 |
| morph | morph.plain dark-photo | toggle.s3.cy.overshoot_pct | 0 | 18.6 | 2 -> 2 |
| morph | morph.plain light-photo | stack.s1.ymax.settle_ms | 16.7 | 33.3 | 17 -> 17 |
| morph | morph.plain light-photo | star.s1.width.overshoot_pct | 1.28 | 4.07 | 2 -> 2 |
| morph RM | morph dark-photo-reduce-motion | events.unpaired | 0 | 2 | 0 -> 0 |
| morph RM | morph dark-photo-reduce-motion | stack.s3.topo.gap_rms | 0 | 30 | 1 -> 12 |
| morph RM | morph dark-photo-reduce-motion | star.s3.width.damping | 0.05 | 0.08 | 0.05 -> 0.05 |
| morph RM | morph dark-photo-reduce-motion | toggle.s3.cy.overshoot_pct | 0 | 18.6 | 2 -> 2 |
| morph RM | morph dark-stripes-reduce-motion | star.s3.width.damping | 0.05 | absent | 0.05 -> 0.105 |
| morph RM | morph dark-stripes-reduce-motion | toggle.s3.cy.peak_ms | 0 | 125 | 17 -> 37.5 |
| morph RM | morph dark-stripes-reduce-motion | toggle.s3.cy.settle_ms | 0 | 125 | 17 -> 37.5 |
| morph RM | morph dark-stripes-reduce-motion | toggle.s3.width.settle_ms | 0 | 117 | 17 -> 50 |
| morph RM | morph light-photo-reduce-motion | stack.s3.topo.gap_rms | 0 | 19 | 1 -> 11.6 |
| morph RM | morph light-photo-reduce-motion | toggle.s3.cy.peak_ms | 0 | 117 | 17 -> 50 |
| morph RM | morph light-photo-reduce-motion | toggle.s3.cy.settle_ms | 8.33 | 117 | 17 -> 50 |
| morph RM | morph light-photo-reduce-motion | toggle.s3.width.settle_ms | 8.33 | 117 | 17 -> 50 |
| morph RM | morph light-stripes-reduce-motion | toggle.s1.cy.damping | 0.05 | 0.06 | 0.05 -> 0.05 |
| morph RM | morph light-stripes-reduce-motion | toggle.s1.cy.response_pct | 3.47 | 19.4 | 5 -> 12 |
| morph RM | morph light-stripes-reduce-motion | toggle.s1.width.peak_ms | 8.33 | 408 | 17 -> 125 |
| morph RM | morph light-stripes-reduce-motion | toggle.s3.cy.peak_ms | 8.33 | 100 | 17 -> 25 |
| morph RM | morph light-stripes-reduce-motion | toggle.s3.cy.settle_ms | 16.7 | 108 | 17 -> 25 |
| morph RM | morph light-stripes-reduce-motion | toggle.s3.width.settle_ms | 16.7 | 108 | 17 -> 25 |
| morph RM | morph.plain dark-photo-reduce-motion | bolt.s3.cy.peak_ms | 0 | 150 | 17 -> 37.5 |
| morph RM | morph.plain dark-photo-reduce-motion | stack.s3.ymax.peak_ms | 0 | 142 | 17 -> 37.5 |
| morph RM | morph.plain dark-photo-reduce-motion | toggle.s3.cy.overshoot_pct | 0 | 18.6 | 2 -> 2 |
| morph RM | morph.plain dark-stripes-reduce-motion | bolt.s3.cy.peak_ms | 16.7 | 150 | 17 -> 25 |
| morph RM | morph.plain dark-stripes-reduce-motion | heart.s3.cy.damping | 0.02 | 0.28 | 0.05 -> 0.255 |
| morph RM | morph.plain dark-stripes-reduce-motion | stack.s3.ymax.peak_ms | 16.7 | 150 | 17 -> 25 |
| morph RM | morph.plain dark-stripes-reduce-motion | stack.s3.ymax.settle_ms | 8.33 | 150 | 17 -> 25 |
| spacing |  6.a dark-photo | ready.topo.g4.gap_pt | 1 | 1.33 | 1 -> 1 |

Reading: of the 64, 10 are merge (normal: 4, all light-stripes step 3 `peak_ms`/`settle_ms`, 8.3-16.7 ms apart in the baseline and 33-67 ms now against an unchanged limit of 17; RM: 6, three of them dark-stripes RM, see 3.1), 1 is spacing, and 53 are morph: 31 on the toggle (`cy`/`width` `peak_ms`, `settle_ms`, `overshoot_pct`; the baseline passed them while the toggle started from the mirrored position 343 and crossed its region box at other times; now it springs from 451 on a slower-starting spring, fit 0.55-0.59 / 0.94-1.00 against native 0.28-0.33 / 1.70-1.98, so the apps differ by 83-158 ms in peak/settle and 11-19 in overshoot: class (a), with the clipped region box a (b) share), 11 on the badges (small: spring `damping` 0.05 -> 0.06-0.08 and overshoot 1.1-1.7 -> 3.0-9.9), 9 on the stack edges and `gap_rms` (the stack follows the toggle), 2 `events.unpaired` (plain dark-photo normal 0 -> 1, morph dark-photo RM 0 -> 2, see 6). In every one of the 64 the limit is unchanged or higher than the baseline's: **no regression is caused by a lowered limit** (none was lowered); in many a limit rose and the value still exceeds it (for example 8.3 -> 117 ms against 17 -> 37.5).

## (3) Failing measures, classed (a)-(d), grouped by family

Counts are measures failing in the grouped cases (4 cases per merge run, 8 per morph run: morph and morph.plain together). "Absent" = key absent or fit invalid (value infinite). Worst = largest value / limit among finite ones. Limits include the Task 25 floors. Classes: (a) the package draws or moves differently, (b) the measure or manifest is wrong for this scene, (c) a mask/tracker misreads one app, (d) capture problem.

### 3.1 `material.merge`, normal (68 failing measures; run `20261008-043622`) and Reduce Motion (78; `-044149`)

Normal:

| Family | n | absent | cases | Worst (measure value > limit, case) | Class |
|---|---|---|---|---|---|
| cx spring | 17 | 0 | 4 | right.s3.cx.response_pct 39 > 7.89 (merge dark-stripes) | (a) |
| cx timing | 15 | 0 | 3 | right.s1.cx.peak_ms 83.3 > 17 (merge light-photo) | (a) |
| edge/centre xmax spring | 6 | 0 | 3 | right.s3.xmax.response_pct 38.9 > 15 (merge dark-stripes) | (a) |
| edge/centre xmax timing | 8 | 0 | 3 | right.s1.xmax.peak_ms 83.3 > 17 (merge light-photo) | (a) |
| edge/centre xmin spring | 5 | 0 | 3 | left.s1.xmin.response_pct 14 > 5 (merge dark-stripes) | (a) |
| edge/centre xmin timing | 3 | 0 | 2 | left.s3.xmin.peak_ms 58.3 > 17 (merge light-stripes) | (a) |
| static bbox_pt | 6 | 0 | 3 | ready.bbox_pt 4 > 1 (merge dark-photo) | (a) |
| static centre_pt | 2 | 0 | 1 | ready.centre_pt 2 > 1 (merge dark-photo) | (a) |
| topology.gap_rms | 2 | 0 | 2 | pair.s1.topology.gap_rms 6.3 > 4.27 (merge dark-photo) | (a) |
| topology.neck_rms | 3 | 0 | 3 | pair.s1.topology.neck_rms 4.19 > 2.09 (merge light-stripes) | (a) |
| topology.split_ms | 1 | 0 | 1 | pair.s3.topology.split_ms 25 > 17 (merge dark-stripes) | (a) |

Reduce Motion:

| Family | n | absent | cases | Worst | Class |
|---|---|---|---|---|---|
| cx spring | 13 | 0 | 4 | right.s3.cx.response_pct 46.2 > 7.5 (merge dark-stripes-reduce-motion) | (a) |
| cx timing | 14 | 0 | 4 | right.s1.cx.peak_ms 75 > 17 (merge dark-stripes-reduce-motion) | (a) |
| edge/centre xmax spring | 6 | 0 | 4 | right.s3.xmax.response_pct 56.2 > 13.2 (merge dark-stripes-reduce-motion) | (a) |
| edge/centre xmax timing | 10 | 0 | 3 | right.s1.xmax.peak_ms 75 > 17 (merge dark-stripes-reduce-motion) | (a) |
| edge/centre xmin spring | 4 | 0 | 3 | left.s3.xmin.response_pct 51.5 > 13.2 (merge dark-stripes-reduce-motion) | (a) |
| edge/centre xmin timing | 7 | 0 | 3 | left.s3.xmin.peak_ms 75 > 25 (merge light-photo-reduce-motion) | (a) |
| static bbox_pt | 6 | 0 | 3 | ready.bbox_pt 4 > 1 (merge dark-photo-reduce-motion) | (a) |
| static centre_pt | 2 | 0 | 1 | ready.centre_pt 2 > 1 (merge dark-photo-reduce-motion) | (a) |
| topology.count | 1 | 0 | 1 | pair.s1.topology.count 7 > 0 (merge dark-stripes-reduce-motion) | (a) |
| topology.gap_rms | 7 | 0 | 4 | pair.s3.topology.gap_rms 5.73 > 3.78 (merge dark-stripes-reduce-motion) | (a) |
| topology.join_ms | 2 | 0 | 2 | pair.s1.topology.join_ms 41.7 > 25 (merge dark-stripes-reduce-motion) | (a) |
| topology.neck_rms | 3 | 0 | 2 | pair.s3.topology.neck_rms 13.1 > 8.36 (merge dark-stripes-reduce-motion) | (a) |
| topology.split_ms | 3 | 1 | 2 | pair.s3.topology.split_ms 33.3 > 17 (merge dark-stripes-reduce-motion) | (a) |

Evidence and exceptions:

- **Timing and spring of `cx`/`xmin`/`xmax` and the join/split times: (a)**, a smaller version of the baseline's. Native joins 208 ms after onset (dark-stripes RM 192), Flutter 225-233 (baseline 225-250); native splits 58-83 ms, Flutter 92-100 (baseline 108-117 against 58-75). Springs on the outer edges `xmin`/`xmax`, from `result.json`: join native 0.32-0.43 s / 1.09-1.35, Flutter 0.48-0.50 / 1.04-1.10; split native 0.32-0.45 / 1.08-1.36, Flutter 0.48-0.50 / 1.04-1.11 (baseline Flutter 0.49-0.50 / 1.04-1.08 clean, so the package's spring did not change here; the fix round moved the onset, not the response). The limits are Task 25 floors (114 raised in the four normal cases) and are still exceeded: the difference is above native's own take-to-take noise, so it is not a (b) plateau-jitter artefact as the baseline had to assume. The hysteresis remains: last neck before the split native 26.7 pt (95 ms), Flutter 14.3 pt (83 ms) in light-stripes normal (baseline 17.7-26.7 against 13.7-14.3): `neck_rms` 2.3-4.4 (join) and 2.6-13.1 (split), `gap_rms` 2.1-7.0 (baseline neck 3.1-5.7 and 8.9-24.5).
- **Static `bbox_pt`/`centre_pt` (dark-photo, dark-stripes, light-stripes): (a) the shadow**, unchanged: dark-photo native box [80, 411, 82, 80], Flutter [80, 411, 82, 84], only the bottom edge. Crop `crops/step6-merge-shadow-dark-photo-native-flutter-diff.png` (native, Flutter, |difference| x8: a crescent at the bottom rim).
- **dark-stripes RM, `pair.step1e0.topology.{count 7, join_ms 41.7, split_ms absent, neck_rms 6.56, gap_rms 11.49}`: (c)**. Flutter's pair is one joined glass (neck 49.7-51.3 pt) but the still-style mask reads 2 components (gap 3-4.3 pt) in 12 video frames, 17.507-17.590 and 17.808-17.893 (`R/onset/topology_series.py`), while every one of those frames shows the joined piece (`crops/step6-merge-dark-stripes-rm-mask-misread-flutter.png`, 17.49-17.62; the second window viewed by eye in the same way). Dark stripes carry no grain, the outline alone marks the glass (baseline 1i, 2a).
- Newly passing against the baseline: dark-stripes `ready.topology.pair.count` and `pair.gap_pt` (the baseline's class (c) failure of native's still mask; they pass now), `pair.step3e0.topology.count` in dark-photo, dark-stripes and dark-photo RM, dark-stripes RM (the one-frame 1 -> 2 -> 1, see 7), and `pair.step1e0.topology.count` in light-photo (the baseline's class (d) burst take, recorded cleanly now: join 225 ms, baseline 150).

### 3.2 `material.morph` and `.plain`, normal (run `20261008-044933`, reruns C as said) and Reduce Motion (`-050026`, rerun D)

Normal, 8 cases:

| Family | n | absent | cases | Worst | Class |
|---|---|---|---|---|---|
| collapsed cy spring | 34 | 34 | 8 |  | (b) |
| collapsed cy timing | 51 | 51 | 8 |  | (b) |
| collapsed width spring | 34 | 34 | 8 |  | (b) |
| collapsed width timing | 51 | 51 | 8 |  | (b) |
| gate events.unpaired | 4 | 0 | 4 | events.unpaired 2 > 0 (morph dark-stripes) | (a); plain dark-photo [2,3]: (c) probable |
| stack ymax spring | 26 | 4 | 8 | stack.s1.ymax.response_pct 122 > 5 (morph.plain light-photo) | (b) for 4 absent, (a) for 22 finite |
| stack ymax timing | 18 | 3 | 8 | stack.s1.ymax.peak_ms 117 > 25 (morph.plain light-photo) | (b) for 3 absent, (a) for 15 finite |
| stack ymin spring | 34 | 26 | 8 | stack.s1.ymin.response_pct 56.8 > 7.84 (morph.plain light-stripes) | (b) for 26 absent, (a) for 8 finite |
| stack ymin timing | 35 | 3 | 8 | stack.s1.ymin.peak_ms 200 > 25 (morph.plain light-stripes) | (b) for 3 absent, (a) for 32 finite |
| star/heart/bolt cy spring | 88 | 68 | 8 | heart.s1.cy.response_pct 57.5 > 8.82 (morph.plain light-photo) | (b) for 68 absent, (a) for 20 finite |
| star/heart/bolt cy timing | 107 | 33 | 8 | heart.s1.cy.peak_ms 400 > 17 (morph light-stripes) | (b) for 33 absent, (a) for 74 finite |
| star/heart/bolt width spring | 97 | 92 | 8 | star.s3.width.response_pct 26.5 > 5 (morph.plain dark-photo) | (b) for 92 absent, (a) for 5 finite |
| star/heart/bolt width timing | 142 | 105 | 8 | star.s1.width.settle_ms 525 > 25 (morph.plain light-stripes) | (b) for 105 absent, (a) for 37 finite |
| static bbox_pt | 8 | 0 | 4 | ready.bbox_pt 6 > 1 (morph dark-stripes) | (a) |
| static centre_pt | 8 | 0 | 4 | ready.centre_pt 3 > 1 (morph dark-stripes) | (a) |
| static topology neck_pt | 2 | 0 | 2 | ready.topology.stack.neck_pt 23.7 > 1 (morph dark-stripes) | (c) |
| toggle cy spring | 20 | 10 | 6 | toggle.s3.cy.response_pct 70.5 > 8 (morph dark-photo) | (b) for 10 absent, (a) for 10 finite |
| toggle cy timing | 24 | 3 | 8 | toggle.s3.cy.peak_ms 167 > 17 (morph dark-photo) | (b) for 3 absent, (a) for 21 finite |
| toggle width spring | 33 | 26 | 8 | toggle.s1.width.response_pct 53.5 > 6.98 (morph.plain light-stripes) | (b) for 26 absent, (a) for 7 finite |
| toggle width timing | 31 | 3 | 8 | toggle.s1.width.settle_ms 350 > 25 (morph.plain light-photo) | (b) for 3 absent, (a) for 28 finite |
| topology.count | 12 | 0 | 8 | stack.s3.topology.count 18 > 3 (morph.plain dark-photo) | (a) |
| topology.gap_rms | 5 | 0 | 5 | stack.s3.topology.gap_rms 25.7 > 6.18 (morph.plain dark-stripes) | (a) |
| topology.join_ms | 14 | 7 | 8 | stack.s3.topology.join_ms 133 > 17 (morph.plain light-stripes) | (a) |
| topology.neck_rms | 11 | 0 | 7 | stack.s3.topology.neck_rms 6.73 > 1.36 (morph.plain dark-stripes) | (a) |
| topology.split_ms | 6 | 0 | 6 | stack.s1.topology.split_ms 142 > 17 (morph.plain light-photo) | (a) |

Reduce Motion, 8 cases:

| Family | n | absent | cases | Worst | Class |
|---|---|---|---|---|---|
| collapsed cy spring | 32 | 32 | 8 |  | (b) |
| collapsed cy timing | 48 | 48 | 8 |  | (b) |
| collapsed width spring | 32 | 32 | 8 |  | (b) |
| collapsed width timing | 48 | 48 | 8 |  | (b) |
| gate events.unpaired | 5 | 0 | 5 | events.unpaired 2 > 0 (morph dark-photo-reduce-motion) | (a); plain dark-photo [2,3]: (c) probable |
| stack ymax spring | 17 | 0 | 5 | stack.s1.ymax.response_pct 42.9 > 7.32 (morph.plain light-stripes-reduce-motion) | (a) |
| stack ymax timing | 15 | 0 | 7 | stack.s3.ymax.settle_ms 142 > 17 (morph.plain dark-photo-reduce-motion) | (a) |
| stack ymin spring | 25 | 16 | 8 | stack.s1.ymin.response_pct 42.9 > 7.32 (morph.plain light-stripes-reduce-motion) | (b) for 16 absent, (a) for 9 finite |
| stack ymin timing | 10 | 0 | 7 | stack.s3.ymin.peak_ms 250 > 50 (morph dark-stripes-reduce-motion) | (a) |
| star/heart/bolt cy spring | 61 | 32 | 8 | heart.s3.cy.damping 0.96 > 0.05 (morph dark-photo-reduce-motion) | (b) for 32 absent, (a) for 29 finite |
| star/heart/bolt cy timing | 57 | 24 | 8 | bolt.s3.cy.settle_ms 200 > 25 (morph.plain dark-photo-reduce-motion) | (b) for 24 absent, (a) for 33 finite |
| star/heart/bolt width spring | 87 | 76 | 8 | star.s3.width.response_pct 48.8 > 7.23 (morph.plain dark-photo-reduce-motion) | (b) for 76 absent, (a) for 11 finite |
| star/heart/bolt width timing | 122 | 96 | 8 | star.s3.width.settle_ms 200 > 17 (morph.plain dark-photo-reduce-motion) | (b) for 96 absent, (a) for 26 finite |
| static bbox_pt | 8 | 0 | 4 | ready.bbox_pt 6 > 1 (morph dark-stripes-reduce-motion) | (a) |
| static centre_pt | 8 | 0 | 4 | ready.centre_pt 3 > 1 (morph dark-stripes-reduce-motion) | (a) |
| static topology neck_pt | 2 | 0 | 2 | ready.topology.stack.neck_pt 23.7 > 1 (morph dark-stripes-reduce-motion) | (c) |
| toggle cy spring | 20 | 0 | 7 | toggle.s3.cy.response_pct 73.8 > 16.2 (morph dark-photo-reduce-motion) | (a) |
| toggle cy timing | 16 | 0 | 8 | toggle.s1.cy.peak_ms 458 > 37.5 (morph.plain dark-photo-reduce-motion) | (a) |
| toggle width spring | 20 | 18 | 7 | toggle.s1.width.response_pct 26.9 > 5 (morph.plain light-stripes-reduce-motion) | (b) for 18 absent, (a) for 2 finite |
| toggle width timing | 17 | 0 | 7 | toggle.s3.width.settle_ms 142 > 25 (morph dark-photo-reduce-motion) | (a) |
| topology.count | 10 | 0 | 7 | stack.s3.topology.count 25 > 1.5 (morph.plain dark-photo-reduce-motion) | (a) |
| topology.gap_rms | 4 | 0 | 4 | stack.s3.topology.gap_rms 30 > 12 (morph dark-photo-reduce-motion) | (a) |
| topology.join_ms | 8 | 0 | 8 | stack.s3.topology.join_ms 333 > 17 (morph light-stripes-reduce-motion) | (a) |
| topology.neck_rms | 13 | 1 | 8 | stack.s3.topology.neck_rms 2.16 > 1.11 (morph.plain dark-photo-reduce-motion) | (a) |
| topology.split_ms | 2 | 0 | 2 | stack.s1.topology.split_ms 91.7 > 37.5 (morph.plain dark-photo-reduce-motion) | (a) |

What the frames say (light-stripes, light-photo, dark-stripes normal; `R/morph` pipeline on the final takes, native touch-up aligned with Flutter's; dark-photo silhouettes stay unreliable and were not run):

| | Native | Flutter baseline (prototype) | Flutter final |
|---|---|---|---|
| Toggle expand fit, t10 / t90 | 0.28-0.30 / 1.90-1.98, t10 19-28, t90 376-385 | 1.10-1.12 / 0.69-0.70, RMS 0.25, t10 158-160, t90 414 | 0.55-0.59 / 0.94-1.00, RMS 0.01-0.02, t10 49-83, t90 341-342 |
| Toggle collapse fit | 0.25-0.33 / 1.24-1.60, t90 240-275 | 1.07 / 0.72, RMS 0.2, t90 415 | 0.42-0.43 / 1.18-1.21, RMS 0.01, t90 320-324 |
| Toggle width, peak (swelling) | 71.0-71.7 at 138-183 ms | 57.7-58.7 | 58.0-58.7 (no swelling) |
| Toggle position in the first frames | holds 451 until its onset at 58 ms | 343-352 (mirrored) | holds 451.0-453.0 for 3-12 frames (`onset_cy`) |
| Heart, first seen | cy 440.6-445.2 at 53-88 ms, r 12.7-19.0 | 343.6-344.1 at 32-65 ms, r 29.0-29.4 | **432.4-450.1** at 0-65 ms, r 27.7-29.4 |
| Bolt, first seen | 479.2-487.4 at 120-170 ms | 460-463 at 265-282 ms | 462.4 at 83-100 ms, r 28.5-29.3 |
| Star, first seen | 378.7-394.0 at 352-368 ms, r 20.9-22.7 | 343.0-343.7 at 65-82 ms | 445.6-449.9 at 65-67 ms, r 28.5-29.3 |
| Stack count, expand | 1>2 at 310-360, a 2>1, 1>2 flicker in two, 4 components at 490-588 | 1>4 at 398 (light-photo 1>3 at 365) | 1>4 at 398-403 (light-photo 1>3 at 367, 3>4 at 385) |
| Stack count, collapse | 4>3 at 83-98, 3>2 at 92-112, a 2>4/4>2 flicker in two, 2>1 at 285-323 | 4>3 at 0, 3>2 at 33, 2>3 at 67, 3>2 at 183, 2>1 at 268 | 4>3 at 32, 3>2 at 132, 2>1 at 182 (light-photo: 2>3 at 167, 3>1 at 183) |

Classes by group:

- **Absent (key absent, fit invalid, native fit at the grid edge, travel under the minimum): (b)**, as ruling 26 said it stays: 553 of the 895 failing measures of the normal runs and 423 of 687 of the RM runs are absent or invalid; the `collapsed` region's cy/width (170 and 160 failures, every one absent) never has a glass of its own, the heart's and bolt's boxes are crossed by the toggle and the star, and the star's top edge `ymin` (the star appears 352-368 ms into the native expand) has an invalid native fit (grid edge 1.50 or RMS 0.16-0.26) in 29 of 69 normal and 16 of 35 RM failures. The per-glass tracker for the inner glasses is the carry-in of ruling 26.
- **Finite cy/width failures of the badges (star/heart/bolt): (a) with a (b) share.** The badges now start at the toggle (heart 432-450, star 446-450) but all three at once and at full size (r 27.7-29.4; native: heart 12.7-19.0 growing, bolt later, star at 352-368 ms from 379-394), one spring for every arrival (ruling 18/21: native heart 0.58-0.62 s, bolt 0.35-0.39 s) and no content-blur sharpening order (Flutter all sharp at 365 ms; native heart/bolt 288-312 ms, star 490-588 ms). Worst: heart `cy.peak_ms` 400 ms, star `width.peak_ms` 458 ms against 17-37.5. Which part is the box crossing (b) cannot be separated without the inner tracker.
- **Toggle `cy`/`width`: (a)**: no swelling (width peak 58.0-58.7 against 71.0-71.7, ruling 19/21; `width.overshoot_pct` 17.6 against 3.04 in dark-stripes normal), and the toggle spring (0.55-0.59 / 0.94-1.00 against native 0.28-0.33 / 1.70-1.98): `cy.peak_ms` 83-167, `settle_ms` 83-142, `overshoot_pct` 11-19 (a difference of overshoot between the apps at the box edge).
- **Stack `ymax` (the toggle's bottom edge) and `ymin` finite: (a)** (the same toggle spring and the star's much later arrival), worst `ymax.response_pct` 122 against 5 (plain light-photo normal), `ymin.peak_ms` 200-250 ms.
- **Stack topology: (a)**: Flutter's expand goes 1 -> 4 in one step at 398-403 ms (native 1 -> 2 at 310-373 ms, then 2 -> 4 at 482-588 ms with a 2 -> 1 -> 2 flicker); `topology.count` up to 39 (normal) and 52 (RM), `join_ms` 133-333 against 17-25, `split_ms` 58-142, `neck_rms` 2.2-6.7, `gap_rms` 12-38. Driven by the emergence and the one spring.
- **`gate events.unpaired` (4 normal and 5 RM of 16 cases each; baseline 5 and 4): (a)** for the cases with native 3-4 events against Flutter's 2 (native's event starts at touch-down, the press glow; Flutter has no press, ruling 26 / baseline 3a); plain dark-photo has Flutter 3 events against native 2 (normal and RM), **(c) probable** (baseline 3c: dark-photo silhouettes unreliable) and not checked frame by frame.
- **Static `bbox_pt` 4-6, `centre_pt` 2-3 (dark-photo, dark-stripes): (a)** shadow, as in merge; **`ready.topology.stack.neck_pt` 23.7 (dark-stripes): (c)**, native's still mask loses the orange-stripe half of the collapsed toggle (baseline 3f, unchanged).
- The plain control has no touch hold for press but fails the same families; its `light-stripes` case (baseline Flutter capture hole, 17/43/148) now records cleanly: 46/92/148, touches [2, 2].

### 3.3 Crops

`crops/step6-morph-emergence-swelling-light-stripes.png`: native (top) and Flutter (bottom) expand, light-stripes normal, 0-500 ms after touch-up. Native: toggle swells at +110-140, heart buds from the toggle, bolt later, star last at about +400. Flutter: the three glyph glasses are all present inside the toggle at +0 (position fixed, not the star slot), the stack unfolds by +200 and separates at +400, no swelling.

## (4) Done item 2: union, the baseline's glyph and material failures

Final: light-stripes **19/19/19**, dark-stripes **5/18/19** (baseline 15/19/19 and 3/16/19; run `20261008-044717`).

| Measure | light-stripes base -> now (limit) | dark-stripes base -> now (limit) |
|---|---|---|
| `ready.mad` / `settled.mad` | 5.653 -> **3.981** (4) pass | 11.128 -> 6.485 (4) fail |
| `ready.luminance` | 4.477 -> **0.982** (3) pass | 11.050 -> 4.991 (3) fail |
| `ready.rim_rms` | 3.344 -> 3.438 (6) pass | 12.137 -> 6.201 (6) fail |
| `bbox_pt` / `centre_pt` | 0 / 0 pass | 8 / 3.5 -> 8 / 3.5 (1) fail |
| topology `first.count`, `first.neck_pt`, `second.count`, `pair.count` | pass | 2, absent, 3 -> **1**, 5 -> **3**: fail |
| topology `second.neck_pt`, `pair.gap_pt` | pass | absent -> 0, absent -> 0: **newly pass** |

- **D2 fixed the glyphs (light-stripes passes both).** Ink area of Flutter's glyphs against native's: star 263.6 / 273.4 pt2 (baseline 60-239 against 271-355), heart 329.1 / 355.6, bolt 128.9 / 143.7, leaf 303.0 / 299.3 (SF `leaf.fill` against `Icons.eco` still differ in shape); `union_tone.py` puts 52 % of the mad in the glyph boxes (12.8 % of the area; baseline 3.69 of 5.65) and 2.23 outside them (baseline 1.96). The mad limit 4 is passed by 0.019: margin is thin.
- **D1 halved the dark material difference but did not remove it.** Flutter dark glass is darker than native's per stripe by 4.0, 6.1, 7.1, 6.0, 6.5, 3.5 luma (baseline 9.5-14.8); 29 % of the mad 6.485 sits in the glyph boxes (baseline 3.75 of 11.13) and 5.27 outside them (baseline 7.38). Class (a) (material, the container row of the median member; dark appearance only; light stripes differ by -6.4 to +4.2). `rim_rms` 6.201 against 6 is the same difference at the rim: (a).
- `bbox_pt` 8 and `centre_pt` 3.5, dark only: (a) shadow, Flutter's shadow tail 4.2-6.4 luma below the edge against native's 1.9 (`union_tone.py`), crosses the detector's 6-level threshold 8 pt lower (same as 3.2).
- **Topology (c).** Native's still mask breaks on dark stripes (3, 4 and 7 components for the first, second, pair), identically to the baseline (rim <= 30 along most of the capsule); Flutter's mask now breaks too (1, 3, 4 components, baseline 1, 1, 2) because the lighter D1 material moves its outline toward the same threshold, which is why `second.count` and `pair.count` approached native's from 3 and 5 to 1 and 3 and one neck and one gap now pass. Crop `crops/step6-union-dark-stripes-mask.png` (native top, Flutter bottom; frame, mask, |difference|).

## (5) Done item 3: the N7 spacing scenes (46 cases, run `20261008-051131`)

**7 of 46 pass** (baseline 6): light photo `.6.a`, `.10.a`, **`.16.a` (new)**, `.20.a`, `.40.a`, `.80.a`, `.80.b`. No dark-photo case passes. `.16.a` light passes because `g8` neck is 1.0 against 1.0 (baseline 1.67): at the limit. One new failure, `.6.a` dark `g4` gap 1.33 against 1.0 (baseline 1.0), in a case that fails anyway. Every other pass/fail result equals the baseline's (no limit raised in any of the 46 cases; values move by up to 2.3 pt, S20 g9 dark neck 14.0 -> 16.33).

Failing measures: dark photo `bbox_pt` 23 of 23 and `centre_pt` 20, topology `count` 4, `gap_pt` 15, `neck_pt` 15 (baseline 14 for gap); light photo `bbox_pt` 6, `centre_pt` 5, `rim_rms` 2, `count` 1, `gap_pt` 4, `neck_pt` 10 (baseline 11). Classes: `bbox_pt`/`centre_pt` (a) shadow; `rim_rms` light `default.b` and `20.c` (a) inner shading; necks and gaps at contact for small spacings and at the reach (a): native snaps at a point, Flutter keeps a soft smudge 5.3-7.0 pt thick (`crops/step6-spacing-20b-g10-pinch.png`: S20 g10, native dark, Flutter dark, native light, Flutter light); dark counts S20.b g10/g11, S40.b g20, S40.d g21 (native 1/2/1/2 against Flutter 2/1/2/1) are the same smudge read by the dark still mask: (a) with (c); S80.c light g40 (native 2, Flutter 1): (a).

Agreement against the baseline, over the 178 (spacing, gap, appearance) topology entries: counts agree 173 of 178 (baseline 173; the same five disagreements); necks of entries where both apps have one component within 1 pt: 50 of 70 (baseline 49); gaps of entries where both have two components within 1 pt: 89 of 103 (baseline 90). Outside 1 pt, necks: contact S4 g0 (18.0 / 18.33 native, 22.33 / 21.33 Flutter), S10 g0 dark, S12 g0, S20 g0 and g4 dark, default g2; the reach S8 g4 (native 1.0 / 1.33, Flutter none / 6.0), S16 g8 dark, S20 g9 and g10, S40 g19 and g20. Gaps: S12 g8 dark (7.67 against 4.67), S20 g11 light and g12 dark, S40 g21 light, g22 and g24 dark, S6 g4 dark, S80 g40 to g44 and g48 dark, default g5 and g6 dark. Flutter's gap past the reach is smaller than native's in 13 of the 14 entries listed, the sign the baseline had (S80 g40 dark the other way): the pinch (a). The container-material change (ruling 30) left the dark cases unchanged (the shadow still fails 23 of 23).

## (6) The events and touches gates, and class (d) holes

- **touches [2, 2] in 24 of 24 cases** (merge 8, morph 8, plain 8; `touches.native` and `touches.flutter` pass in all): the baseline's one exception (plain light-stripes Flutter [2, 1], a hole) is gone.
- **events: merge [2, 2] in 8 of 8, `events.unpaired` 0.** Morph and plain, events [native, Flutter] and unpaired: normal: morph dark-photo [4, 3] (1), dark-stripes [4, 2] (2), light-photo [4, 2] (2), light-stripes [2, 2] (0); plain dark-photo [2, 3] (1), dark-stripes, light-photo, light-stripes [2, 2] (0); RM: morph dark-photo [4, 2] (2, rerun D), dark-stripes [3, 2] (1), light-photo [3, 2] (1), light-stripes [3, 2] (1); plain dark-photo [2, 3] (1), the other three [2, 2] (0). So `events.unpaired` fails in 9 of 16 morph and plain cases (4 normal, 5 RM; baseline 5 and 4) and passes in 7; it is the native press event and, for plain dark-photo, a third Flutter event (3.2). `events.native_motion` passes in all 24.
- **Class (d) holes.** Task 27a's `take_check` over every merge and morph take flagged no Flutter take (not re-run here), no case has touches other than [2, 2], `stalls flutter` is empty everywhere except merge dark-stripes normal (27 ms, one frame). Native takes still flagged after their one rerun: morph dark-photo normal (A: capture hole at step 1, gaps 377/355/2313/17 ms), morph light-photo normal (B: step 1), morph light-stripes RM (E: step 1); their originals count. The flags are not confirmed holes (Task 25f: the rule flags takes that pass), no failing group depends on them (stalls of 130-133 ms come after the motion), so they are not classed as holes; if the user wants them settled, a third recording of those three cases is the next step, not a tuning of the rule.

## (7) Onset check (ruling 29)

- **Merge, Flutter: no frame at the mirror position at either onset, 0 of 16 onsets** (8 cases x join and split, `R/onset/onset_cx.py` series for the circles' `cx` from touch-down to onset + 120 ms: every frame's displacement from the start has the sign of the net displacement). The same test flags the baseline recording (`20261007-054755` light-stripes: right circle at +25.7 and -20.0 pt on the wrong side at join and split; dark-photo split: -20.3 pt). The numbers equal `flutter-merge-light-stripes-after.txt`: left circle 121.2, 121.7, 123.3, 125.5, 128.2, 130.8, 133.8, 136.5 against 121.17, 121.83, 123.33, 125.5, 128.17, 130.83, 133.83, 136.5; split 160.3, 160.3, 160.0, 159.2, 158.0, 156.7, 155.3 against 160.33, 160.33, 160.0, 159.17, 158.0, 156.67, 155.33.
- **Morph, Flutter: the toggle holds 451 and the badges leave it**: `R/onset/onset_cy.py` on light-stripes, light-photo and dark-stripes: first rows `toggle`/`collapsed` 451.2/57, 453.0/61, 452.2/62, then 451.0/65 for the rest; heart 435.0/25 -> 415.0/65 and bolt 467.2/25 -> 487.0/65 from the first frame, rows identical to `flutter-morph-light-stripes-after.txt` shifted by 0.708 s (light-stripes).
- **One-frame count change 1 -> 2 -> 1 (merge):** baseline Flutter split in dark-photo and dark-photo RM read join 33 ms and splits 8, 108/117 ms (count measure 2 and 1); final: no join in any step 3, one split at 92-100 ms in all 8 cases, `topology.count` 0 in all 16 events except dark-stripes RM step 1 (mask misread, 3.1). **Morph:** the first transition of Flutter's expand is 1 -> 4 at 398-403 ms in 7 of 7 normal takes (none earlier); the collapse starts with 4 > 3 at 32-33 ms (baseline 0 ms) and no 2 -> 3 bump at 67 ms; 5 of 7 collapses show a later 2 -> 3 or 2 -> 4 bump at 118-200 ms, which native shows too (2 > 4 at 162-245 ms).
- Toggle fit RMS 0.01-0.02 (baseline 0.11-0.25): the first-frame defect is gone from the spring fits too.

## (8) Hold-out of ruling 2 (eye against the topology mask; the threshold is not tuned)

Frames from the cached `shapes/` of the take (`frames_at.py`), judged by eye before the mask's `count` was read.

- **Merge, `material.merge light-stripes` normal, Flutter, join, 24 frames 17.403-17.788** (`crops/step6-holdout-merge-join-light-stripes-flutter.png`; zoom on 17.487, 17.503, 17.520 for the contact): eye: two pieces 17.403-17.487 (6 frames, gap 42.7 -> 13.0 pt), tips touching with no background between at 17.503 (called one piece, borderline), one piece 17.520-17.788 (17 frames, neck 21.7 -> 49.3). Mask `pair`: 2 in 6 frames (gap 42.7, 38.0, 32.7, 27.3, 20.7, 13.0), 1 from 17.503 (neck 10.0). **0 disagreements** (1 borderline frame, agreeing).
- **Morph, `material.morph light-stripes` normal, Flutter, expand, 24 frames 17.600-17.983** (`crops/step6-holdout-morph-expand-light-stripes-flutter.png`): eye: one piece (four glasses joined by thinning necks) 17.600-17.733 (9 frames), four separate glasses from 17.750 (15 frames); mask `stack`: 1 for 9 frames (neck 32.7 -> 4.7), 4 from 17.750. **0 disagreements.**
- **Same take, collapse, 24 frames 20.350-20.733** (`crops/step6-holdout-morph-collapse-light-stripes-flutter.png`): eye: four pieces 20.350-20.367, three (star, heart+bolt blob, toggle) 20.382-20.467, then the blob touches the toggle through a thin neck (one piece plus the fading star ghost) 20.483-20.500, one piece from 20.517 (the star has all but gone), one piece to the end. Mask: 4, 4, 3 x 6, 2, 2, **4 at 20.517, 3 at 20.532**, then 1 from 20.548. **Disagreements: 2 frames (20.517, 20.532), class (c)**: the fading star's ghost and the blob's outline split the mask for two frames, eye reads one piece. Native has the same flicker (2 > 4 at +225 ms).
- Also found by eye in the table's failures: the merge dark-stripes RM Flutter take, 12 frames of mask count 2 against a joined piece (3.1), class (c). 
- Total of the hold-out proper: 72 frame judgements, 2 disagreements (both morph collapse), 0 in merge.

## (9) Emergence (ruling 21c)

Yes. The heart's first-seen centre in Flutter is now **439.7 (light-stripes), 450.1 (light-photo), 432.4 (dark-stripes)**: the toggle's slot (native 442.9, 445.2, 440.6; baseline Flutter 343.6-344.1), and the star and bolt start there too (star 445.6-449.9, bolt 462.4; baseline star 343.0-343.7). It follows from the toggle's drawn rect no longer being mirrored. What remains different and is class (a): the three badges arrive together at full size within 0-100 ms (r 27.7-29.4) where native grows the heart from r 12.7-19.0 at 53-88 ms, the bolt at 113-170 ms and the star at 352-368 ms from 379-394, and Flutter's star is in the toggle at 65 ms where native's is last. `crops/step6-morph-emergence-swelling-light-stripes.png`.

## Per Done item

1 (merge, union, morph, normal and RM): **still failing**, every failure classed above: merge (a) timing, spring and hysteresis plus the shadow, one (c) group; morph (a) toggle spring, no swelling, one spring, emergence order, press event and the 1 -> 4 step, (b) absent per-glass measures, (c) dark masks; union see 4. 2 (union stills): **light-stripes passes (19/19/19), dark-stripes fails 14 of 19 measures: (a) material residual, shadow, rim; (c) mask**. 3 (spacing): **7 of 46** against 6, the same classes as the baseline. The onset frame (ruling 29) is fixed in both scenes.
