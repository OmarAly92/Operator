# Final re-review of the 2B.3 plan (after rounds 3 and 4)

**Scope.**
- Reviewed: `plan-2b3.md` at `12d300953`, code `87b88ab02`. The last review covered `fe8d7f97a`; this one is limited to what changed since.
- I did not touch the plan or the prototype. This file is the only addition and is not committed.
- No simulator was used: every claim could be settled from recordings already on disk.

**Where I worked.**
- `/Users/omaraly/development/AI/Operator-2b3-rereview3`: a fresh clone at `12d300953`.
- `/Users/omaraly/development/AI/Operator-2b3-rereview3-replay`: a worktree of that clone at `development` `c0e69d9a4`, with the evidence committed.
- Copies of the recordings under `Operator-2b3-review/packages/mobile/build/glass_lab/runs/`.
- Scratch outputs: `scratchpad/rev/` (`gates-rr3/`, `replay4-out/`, `patches4/`, `newrule3-out.txt`, `rowhole.py`).

## Verdict

**Ready to execute: yes**, once T1's text-only fix is made. T2, the disk, is the user's call before Task 13.

Everything I could recompute matches:
- the gates;
- the 18 byte-identical patches, and a replay that behaves as stated;
- the take-check counts;
- the law, its residuals and the held-out results;
- both forecasts.

The take-check changes do not let a hole into a floor or a fit. What is left is stale text (T1, T3), a disk precondition (T2) and one row-level softening (T4).

Counts: blocker 0, major 1 (T1), minor 4 (T2 to T5).

## 1. The take-check changes

**What changed.**
- `takecheck.py`: the onset window is now 90 ms (was 100), and during the hold a gap is lost only above 60 ms. After touch-up the lost-frame test runs to the end of the span, which was S1's fix.
- Gaps are rounded (`round(gap, 4) > 0.030`).
- `press.py`: the row-level motion thresholds rise from 0.1 to 0.5 luma and pt.

**Take-level results** (`takecheck.check` at `12d300953` on my copies; `newrule3-out.txt`):

| Takes | Result |
|---|---|
| N1 and N2 | **20 of 24 clean** (300 × 120 dark-photo and light-stripes, 360 × 200 dark-photo: squeezed first frames; circle58 dark-stripes: burst). Matches the writer |
| 2B.1 noise takes | **17 of 30 clean**: 12 squeezed first frames, plus `material.interactive` dark-photo take 3, now caught by the hold cap (118.3 ms lost in a press-drag's hold). Matches the writer |
| 2B.1's excluded `dark-stripes` | FAIL (burst at 24.360 s; 101.7 ms lost at 24.142 s) |
| 2B.1's excluded `dark-photo` | PASS (native's release cadence) |
| Every holed take from my earlier reviews | still FAIL, apart from the borderline `063817` Flutter (gaps 5.0 then 1.7 ms), as before |

**The 60 ms hold cap.**
- Sound. Native's own moving gaps during the press are 33.3–56.7 ms (`R/gap-phases.txt`), so 60 ms clears them by 3.3 ms, and the cap catches the one 118 ms loss.
- A single lost frame within the 20 Hz phase still cannot be seen. The plan now names this and says that `grow_ms` and the cut measures are protected only by the burst test and the leverage stop.

**The 90 ms onset window.** Sound. The earliest native slow gap seen is 96 ms (`drag.far`), and 103.3 ms in press takes. Task 12 reports the flag rate and stops above one take in ten.

**The 30.0 ms edge.** Sound. Timestamps are on a 1/600 s clock, so 30.0 ms is 18 ticks. One lost frame at 60 Hz gives 33.3 ms, and 33.3 ms is still flagged.

**The row thresholds of 0.5 luma / 0.5 pt** (T4).
- At the take level nothing changed: the region check (motion over 0.2) still decides `run`'s re-record, `repeat`'s exclusion, the `capture.<app>` gate, and `pressfit`'s `usable`.
- So no floor and no fit takes a holed take, and no judged limit moves.
- But the rows now miss step holes that the region check finds (`rowhole.py`):
  - the excluded `dark-stripes` take's step 1 is marked a hole at 0.1 but not at 0.5;
  - noise take dark-photo 3's step 3 (the 118 ms hold loss) is marked at 0.1 but not at 0.5.
- The writer's sentence "at 0.5, every rows hole found is also a region hole" is true. It is the other direction that fails: region holes are not all row holes.
- Effect: in a Done case whose kept take still fails the check after `run`'s retries, the step's time measures stay finite instead of NaN. They enter the passing counts while the `capture` gate fails beside them. This changes counts, not limits.

## 2. The law

**Recomputed.** `pressfit fit` on the three series files gives a summary identical to `R/pressfit.json`.
- The height form min(15.84, 9.73 · (100/h)^1.24) qualifies, with residuals within ±0.88 pt:

  | Size | Residual (pt) |
  |---|---|
  | 58 × 58 | −0.16 |
  | 138 × 53 | +0.51 |
  | 250 × 44 | −0.33 |
  | 250 × 88 | +0.07 |
  | 250 × 150 | +0.55 |
  | 300 × 120 | −0.41 |
  | 300 × 250 | −0.88 |
  | 360 × 200 | +0.45 |

  In-sample RMS 0.442; leave-one-size-out 0.698.
- The height-and-width form also qualifies (q −0.10, leave-one-size-out 0.789) and is not separated from it. The area form fails 250 × 150 by +1.66.

**The selection rule is right.** A form qualifies only if every size is within 1 pt (`bbox_pt`); leave-one-size-out then chooses among those. It is pinned by `test_a_form_that_misses_a_measured_size_by_more_than_the_size_threshold_is_not_chosen`.

**Held out** (`R/heldout.txt`; my recompute from `heldout-series.json`):

| Size | Native plateau | Law | Measures passing |
|---|---|---|---|
| 120 × 250 | 4.67 × 8.00 pt | 3.12 × 6.51 | 6 of 16; misses 1.55 / 1.49 pt; `grow_w` 1.67 and `grow_h` 1.67 fail |
| 44 × 44 | 16.0 / 15.67 | the cap, 15.84 | 10 of 15; growth within 0.33 pt; the light, the cut and `shrink_ms` fail |

**The stop rule is correct and tested.** `problems()` adds "no growth law form keeps every measured height within 1.0 pt", and `write_table` refuses on any problem. `test_a_refit_where_no_form_keeps_every_size_within_the_threshold_writes_nothing` passes in my replay. Task 14 Step 2 says to stop and report the residuals of every form.

**The misses are stated.**
- The README (line 90): "120 × 250 … 1.55 pt less …, 300 × 250 0.88 pt".
- The forecast's item 1 lists 120 × 250's growth as failing.
- But Task 14 Step 2 and Review Focus 5 still describe the old rule (T1).

## 3. Gates, patches and replay

| Gate | Plan | Mine |
|---|---|---|
| Harness | 315 | `Ran 315 tests`, OK |
| Package | 280 | `+280`, `No issues found!` |
| Example | 25 | `+25`, `No issues found!` |
| App | 2188 | `+2188: All tests passed!`, `No issues found!` |

**Patches.** All 18 are byte-identical to `git diff --full-index c0e69d9a4 87b88ab02 -- <files>`, covering the same 38 files.

**Replay.** I applied all 18 and ran the fail-first and pass steps below. Afterwards all 38 files are `cmp`-identical to `12d300953`.

| Task | Red | Green |
|---|---|---|
| 1 | `ModuleNotFoundError` | `Ran 18`, OK |
| 3 (take check, leverage) | `FAILED (errors=9)` | `Ran 40`, OK |
| 4 (pressfit, with the stop-rule test) | `ModuleNotFoundError` | `Ran 18`, OK; gate `Ran 315`, OK |
| 5 | compile error | `+53`; `table reproduced by pressfit` (with `native-press-300x250.json`) |
| 9 | – | `+10` |
| 10 (Operator tests) | fails | `+12` |

## 4. Forecasts

- **In-sample:** 318 of 469 pass, 417 finite, over 26 cases. The failure tally matches the plan (`shrink_ms` 22, `glow_rise_ms` 20, `grow_ms` 20, …).
- **Independent:** 246 of 347 over 17 pairs, matching the plan. The tally is `glow_half_ms` 18, `shrink_ms` 18, `delay_ms` 15, ….
- The independent set has 17 pairs (down from 18) because dark-photo take 3 now fails the check. It still covers three sizes on `photo`, and the plan says so.

## Findings

### T1 (major): Task 14 Step 2 and Review Focus 5 still describe the retired law rule

- **Task 14 Step 2** ends with "the power form replaces the inverse one only with a held-out gain over 1/3 pt", and asks the report to compare the law's "held-out gain". That is the rule `LAW_GAIN` implemented, and `pressfit.py` no longer contains it: `fit_growth_law` now chooses among height, area and height-and-width forms by the 1 pt rule and then leave-one-size-out, and writes no `held_out_gain`.
- **Review Focus 5** gives the old grid ("size at 100 pt 4–16 pt, power 1–2"; it is now 4–40 and 0.5–2). It names `LAW_GAIN` and says the form "changes from the inverse one only on a held-out gain over 1/3 pt". It omits the new "no form within 1 pt" refusal.
- Task 14 Step 2 is where the executor applies D13's stop rule, so the step must describe the rule the tool enforces.
- **Fix (text only):**
  - Replace the last sentence of Task 14 Step 2 with: the form is chosen by the 1 pt rule, then leave-one-size-out among qualifying forms; report `law.forms.*` and `separated`.
  - Correct Review Focus 5's grid, drop `LAW_GAIN`, and add the "no form within 1.0 pt" refusal and its test.

### T2 (minor; a precondition for the user): free disk is 56 GB, not the 180 GB the plan assumes

- **Evidence.** `df -h /Users/omaraly`: 56 GB available. The plan still says "About 180 GB were free on 2026-10-09".
- Task 13 copies 8.6 GB, and its analysis writes frame caches into the recordings (gotcha 51: 42 GB in 2B.1; this prototype's `runs/` is 43 GB). The plan's own "stop under 40 GB" will very likely halt Task 13.
- That stop is safe, not silent, but it ends the run partway through.
- My review clones use about 23 GB. `Operator-2b3-review` is 21 GB; the rest is `-review-replay`, `-review-a9`, `-rereview`, `-rereview-replay`, `-rereview2`, `-rereview2-replay`, `-rereview3` and `-rereview3-replay`. The user may delete them.
- **Fix.** Update the sentence. Ask the user to free space (or name a volume) before Task 13.

### T3 (minor): stale count in Task 13

- Task 13's Produces line says "Ruling 16 found 12 of 30 sampled 2B.1 press takes flagged". It is 13 of 30 (17 clean), as ruling 16 says.
- **Fix.** Correct the count and the replacement estimate.

### T4 (minor): the row-level thresholds no longer mark some step holes the take check finds

- **Evidence.** See section 1: the excluded `dark-stripes` step 1 and noise dark-photo take 3's step 3 are holes at the region level and at 0.1 on rows, but not at 0.5. Limits and floors are not affected. The counts can be: a Done case that keeps a failing take after retries counts finite step measures.
- **Fix.** Either mark a step NaN whenever `takecheck.json` lists a hole inside that step's span, so the rows follow the take-level verdict; or count every motion measure of a case that fails `capture.<app>` as failing in Task 15 Step 2. Add a test for the 118 ms hold loss at row level.

### T5 (minor): D9 names two Flutter runs for the 44 × 44 result

- D9 says "one Flutter take recorded with the refitted table (`20261009-124556`) … (`R/heldout.txt`, Flutter `20261014-165002`)". The numbers quoted (10 of 15; `shrink_ms` 250 against 335) are from `20261014-165002`.
- **Fix.** Drop the stale run id.

## Execution tasks

Checked and correct as written:
- reboot before references, every 2 h of recording, and after three failed take checks in a row;
- SIGINT only, including for an orphaned `recordVideo`;
- one lab command at a time, and nothing else running while recording or `perf` runs;
- the iOS 27 UDID named in every command;
- the accessibility reset after an interruption;
- the 40 GB stop;
- Task 14b marked NOT TO RUN (the user chose D6 A).

The task order is unchanged and consistent: the refit (14) comes after the floors (13) and before the Done runs (15).
