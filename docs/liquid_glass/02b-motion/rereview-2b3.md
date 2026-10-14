# Re-review of the 2B.3 plan after the fix round

Reviewed: `plan-2b3.md` at `proto/2b3` `7abaeb22d` (code `c11d57268`; 5,154 lines; 18 patches). This is a scoped re-review of `plan-2b3-review.md` (F1 to F21). I left the plan and the prototype unchanged. This file is the only addition, and it is not committed.

**Where I worked.**
- `/Users/omaraly/development/AI/Operator-2b3-rereview`: a fresh clone at `7abaeb22d`.
- `/Users/omaraly/development/AI/Operator-2b3-rereview-replay`: a worktree of that clone at `development` `c0e69d9a4`, with `research/proto-2b3/` committed.
- Copies of the recordings, without their frame caches, in `Operator-2b3-review/packages/mobile/build/glass_lab/runs/`:
  - the two takes 2B.1 excluded from `runs/20261006-085522/excluded/`, copied from the archive, which I only read;
  - the 30 2B.1 press noise takes in `noise-copy/`;
  - the prototype's runs;
  - my light run `20261009-081334`.
- Scratch outputs: `scratchpad/rev/` (`newrule-out.txt`, `replay2-out/`, `gates-rr/`, `profile-mine.json`, `pressfit2.txt`).
- No simulator was used this round.

## Verdict

**Ready to execute: no.**

The fix round is real:
- Every code block equals the prototype.
- The gates and the replay match the plan.
- The settled law, the masked sigma, the cut per size, the Reduce Motion cut from six presses, the 44 × 44 numbers and the 304 of 440 forecast all recompute exactly.
- The squeezed-first-frame part of the new take rule is justified by the data (R-table below).

What still stops it:
- **R1.** The capture-hole rule looks only within 150 ms after a touch edge, and only for bursts. It therefore passes a take that 2B.1 excluded for a capture hole, so it is looser than 2B.1's rule. The plan still says no floor, fit or reference uses a holed take, and that is not true for this class of hole.
- **R2, R3 and R4 (major).** The forecast's passes are in-sample. The leverage stop writes the floor before it stops, and nothing says what to do next. The law's form is chosen on one clean take per size at the two sizes that decide it.

Counts: blocker 1 (R1), major 3 (R2 to R4), minor 6 (R5 to R10).

## Gates (fresh clone of `7abaeb22d`)

| Gate | Plan | Mine |
|---|---|---|
| Harness | `Ran 298 tests`, OK | `Ran 298 tests in 105.0s`, OK |
| Package | analyze clean, `+280` | `No issues found!`, `+280: All tests passed!` |
| Example | analyze clean, `+25` | `No issues found!`, `+25: All tests passed!` |
| App | analyze clean, `+2188` | `No issues found!`, `+2188: All tests passed!` |

## Code diff and replay

**Diff.** My extractor found 18 patch blocks, and each is byte-identical to `git diff --full-index c0e69d9a4 c11d57268 -- <its files>`. The union of their files is exactly the 38 files the prototype changes under `packages/`.

**Replay.** I applied all 18 patches in order with `git apply --3way` and ran the fail-first and pass steps of the patch tasks below (`replay2-out/summary.txt`). All 38 files are `cmp`-identical to `7abaeb22d` afterwards.

| Task | What I ran | Result |
|---|---|---|
| 0 | setup | `52 packages …` |
| 1 (take rule and press measures) | red, green | red `ModuleNotFoundError`; green `Ran 17 tests`, OK |
| 2 | green | `Ran 7`, OK |
| 3 (scripted check, leverage) | red, green | red `FAILED (errors=7)`; green OK |
| 4 (pressfit refit) | red, green, harness gate | red `ModuleNotFoundError: No module named 'pressfit'`; green `Ran 12`, OK; gate `Ran 298`, OK |
| 5 | red, green, table | red is a compile error; green `+53`; `table reproduced by pressfit` |
| 9 (D1 mirror) | test | `+10` |
| 10 (Operator tests) | red, green | red: the press, Reduce Motion and `GlassGlow` tests fail; green `+12` |

The replay is honest.

One detail (R9): `test_takecheck.py` / `test_lab.py` print a temporary run path (`lab.py:332 print(run_dir)`). With `2>&1` that path can be the last line, which is not the plan's "Expected output". The plan's `replay-5.txt` shows `OK` last only because of stream ordering.

## The F1 departure: the new take rule

**What was implemented.** A capture hole is either:
- two consecutive frame gaps under 4.5 ms within 150 ms after a touch-down or touch-up; or
- a first frame less than 4.5 ms after a touch-down (`takecheck.holes`).

Video timestamps come in 1.67 ms steps, so "under 4.5 ms" means a gap of 3.3 ms or less.

I ran it, with a copy of `takecheck.py` at `7abaeb22d` (`scratchpad/rev/newrule.py`), on every take I flagged in F1 and F2, on the 30 clean 2B.1 takes, on my light run, and on the 2B.1 takes that were excluded for capture holes.

| Takes | 2B.1 rule (`proto-2b2/take_check.py`) | New rule |
|---|---|---|
| The nine first-round question takes | 6 holed, 2 press-drag length (wrong window), 1 PASS (`055759`) | all 9 FAIL (`055759` and `055621` through the squeezed first frame, 3.3 ms) |
| The six comparison runs, 12 takes | 9 FAIL | 11 FAIL. **`063817` Flutter PASSES** (gaps 5.0 then 1.7: the 5.0 is not "under 4.5"; the old rule's float 4.99 counted it) |
| My light run `081334`, 2 takes | 2 FAIL | 2 FAIL |
| 30 clean 2B.1 noise takes | 30 PASS | 18 PASS, 12 FAIL (writer: 17 and 13). Every rejection is the squeezed first frame (1.7 or 3.3 ms after touch-down); none is a burst |
| **2B.1's excluded N1 `dark-stripes`** (`20261006-085522/excluded`, README: "a step-3 event after gaps of 80.0 and 101.7 ms, then 5 under 5 ms") | FAIL | **PASS** |
| 2B.1's excluded N1 `dark-photo` | FAIL | PASS |

**Is the squeezed first frame a real hole?** Yes. Where the first frame after touch-down is 1.7–3.3 ms late, the light's rise reads early by 5–25 ms, consistently:

| Takes | Squeezed rise (ms) | Clean rise (ms) |
|---|---|---|
| 250 × 44 dark-photo | 28.3 | 50–56.7 |
| 250 × 44 light-photo | 100.0 and 101.7 | 105–113.3 |
| circle58 dark | 100.0–111.7 | 118.3 |
| circle58 light | 98.3 and 103.3 | 115–120 |

So the 12 or 13 rejections of 2B.1 takes are justified, and that part of the rule is stricter than 2B.1's, not looser.

**Where it is looser than 2B.1's rule.**
1. **Frames dropped during the motion.**
   - In the excluded `dark-stripes` take the touch-up is at 23.955 s. The frames after it are 5.0, 80.0, 101.7 and 48.3 ms apart, so about 230 ms of the release spring is missing, and then a burst follows.
   - The new rule sees only bursts of two short gaps, and only within 150 ms, so it passes the take.
   - `shrink_ms` and the release's `delay_ms` read from such a take are wrong. 2B.1 excluded it for this reason.
2. **Anything more than 150 ms after a touch edge.** The cut comes 380–750 ms after touch-up, so a squeeze at the cut is never checked. `glow_drop_ms`, `glow_fade_ms`, `glow_half_ms` and `glow_level` all read those frames. The 2B.1 rule looked at every event's first frames, the cut included.
3. **A burst whose first gap is exactly 5.0 ms** (`063817` Flutter). This one is borderline and I do not count it as a defect.

The excluded `dark-photo` take is not a counter-example. Its release gaps (13.3, 15.0, 16.7, 3.3, 11.7, 5.0) are native's normal cadence, so the old rule probably flagged it wrongly. The excluded `dark-stripes` take is a true hole that the new rule passes.

## Findings

### R1 (blocker): the take rule passes dropped frames and holes beyond 150 ms, so holed takes can still set floors

- **Where.**
  - `takecheck.holes`, called from `press.features` ("hole") and from `run` and `repeat`.
  - Ruling 16.
  - Global Constraints: "No floor, fit or reference uses a holed take."
- **Evidence.** The table above: 2B.1's excluded N1 `dark-stripes` passes. Its 230 ms of missing release frames would enter a floor through the worst pair (`lab.case_noise`) in the same way F1 described. The cut is never examined.
- **Fix.**
  - Check the whole span each step is analysed over, from touch-down to the next touch (or to `settled`), not only 150 ms after an edge.
  - Flag two kinds of hole in that span:
    - a burst (two consecutive gaps of 3.3 ms or less);
    - a gap over 30 ms between two frames that both differ from their neighbours inside the tracked region (the glass was moving but frames were lost).
  - Keep the squeezed-first-frame test.
  - Add a test built from the archived `dark-stripes` gap list, plus a test with a burst at +450 ms (the cut).
  - Re-run `hole-rule-check.txt` and state the new pass counts. N1 and N2, and the 2B.1 noise takes, should lose only takes with a real gap.

### R2 (major): the forecast's 304 of 440 is measured in-sample

- **Where.** "What this plan expects to reach", item 1, and `R/flutter-compare.txt`. Global Constraints: "No fit result is reported as a pass on the takes it was fitted on."
- **Evidence.** `pressfit` fitted the shipped table on `R/native-press-all.json`, which is N1 and N2 from the archive (`R/pressfit.json`, `cases` 21 to 22). The Flutter takes were then judged against those same N1 and N2 references (`compare_archived.py`). I recomputed 304 passing, 399 judged, 440 expected from `flutter-compare.json`, with the failure tallies exactly as stated. But the size law, springs, cut and light per size were fitted on the native side of those very comparisons. The forecast does not say so.
- **Fix.** Either label the 304 of 440 as in-sample, or judge the same Flutter takes against independent clean native takes. The 18 2B.1 noise takes on `photo` that pass the new rule were not used by the prototype's fit, so they are independent.

### R3 (major): the leverage stop writes the floor before it stops, and the plan gives no procedure after a stop

- **Where.** `lab.cmd_repeat`: `NOISE.write_text` (line 34 of the function) runs before `raise SystemExit("one take sets a time limit …")`. Task 13 Steps 2 and 3 say nothing about what to do after a stop.
- **Consequence.** The leveraged limit is already in `noise.json` when `repeat` exits non-zero, and Task 13 Step 5 commits `noise.json`.
- **Also.** In session 1 the new cases have only three takes. The check then compares the worst pair with a single remaining pair, which gives spurious stops.
- **Fix.**
  - Write nothing for a case whose leverage check fires, or write it under a `pending` key.
  - Run the leverage check only once a case has five takes.
  - Add a Task 13 step for a stop: move the take that sets the limit to `excluded/` with the reason, record one replacement after a reboot, recompute, and report it.
- This is the user's D3 ruling ("STOPS"), so it must stop before anything is written.

### R4 (major): the power-law form is chosen by 0.05 pt, decided by one take each at the two sizes that matter, and the held-out 44 × 44 cannot test it

- **Where.** Ruling 8 and `pressfit.fit_growth_law`.
- **Evidence.** I recomputed it. Settled law min(15.84, 9.72 · (100/h)^1.22). Leave-one-size-out RMS 0.636 (power) against 0.685 (inverse, at_100 **9.82**, not the 9.72 that ruling 8 prints). In-sample RMS 0.288 against 0.403.
  - Per held-out size, the two forms tie on 44, 53 and 58 (the cap) and on 88 (±0.86–0.89).
  - **The inverse is better at 120** (residual 0.21 against 0.35).
  - The power form wins only at 200 (0.52 against 0.96).
  - The 120 and 200 rows are one light-photo take each, because the dark takes are skipped as holed. Their holes are at touch-down and do not touch a plateau read 0.3 s before touch-up.
  - The 44 × 44 circle sits on the cap, where both forms give 15.84 pt, so "the law extrapolates within 0.33 pt" confirms the cap only.
- **Fix.**
  - Use every take's plateau for the law, whether or not it is holed (the hole affects times, not the plateau).
  - Keep the inverse form unless the held-out gain is larger than the size measure's threshold (1/3 pt).
  - Add one held-out size between 88 and 200 pt tall (for example 250 × 150) to Task 12, so the choice of form is tested on a size outside the fit.

### R5 (minor): D10's per-channel evidence is weaker than stated; the luma part is solid

- **Evidence.** `R/light-blend.txt`.
  - The **luma** drop at the cut is 12.28–12.54 on `photo` and dark `stripes`, but 6.78 on light `stripes`. Native's light does not add a fixed amount over bright content; that conclusion is sound.
  - The per-channel changes (light-stripes R −2.68, G +10.41, B −1.28) come from H.264 video. H.264 subsamples colour at half resolution (4:2:0), and this is a region on 67 pt colour stripes, so chroma at the boundaries is blurred.
  - The "vivid" model wins with 3 coefficients against the additive model's 1, in-sample.
- **The plan's action is honest.** It forecasts light `stripes` failing `glow_peak` as class (b) and defers to a fix wave (D10 A).
- **Fix.** Word D10 as "luma halves over light stripes; the colour change is suggestive (H.264 chroma)". Pick between the models by held-out RMS across the four N1 cases, not in-sample.

### R6 (minor): native's lean toward the finger is now measured, and spec (a2) asks for it to be built

- **Evidence.** `R/native-questions-2.txt`:
  - `drag.far`, 256 pt below: `stretch` −0.035 and `centre` 1.67 pt, in one clean take; the holed take reads the same.
  - `drag.up`, 106 pt above: −0.015, 0.83 and 0.85 pt, in two clean takes.
  - `drag.out`, 40 pt to the right: +0.012 and 1.33, in one take, holed at touch-down.
  - The sign follows the drag's axis: taller when the finger is above or below, wider when it is to the side. It is a stretch-like deformation of 1.2 to 3.5 times the thresholds.
- **Assessment.** Spec (a2) is binding: "built only where native shows them, copied exactly". Deferring it is a departure from the spec. It is disclosed (D6, ruling 3, the forecast and the README), so it is not silent.
- **Fix.** The user must take D6 explicitly as a spec departure. The plan's recommendation (A, fit after Task 13's floors give a curve) is reasonable.

### R7 (minor): the Reduce Motion reference for `drag.out` was dropped without a word

- **Where.** Spec N6: "Reduce Motion runs of `material.interactive` … and the N3 drag scenes". The first plan recorded `drag.out` under Reduce Motion. Tasks 12, 13 and 15 now record only `material.interactive` and `drag.fast` under Reduce Motion, and no ruling says why.
- **Fix.** Restore it, or state why in ruling 19.

### R8 (minor): sigma rests on one take

- **Evidence.** `pressfit.py profile` on `20261009-085013` reproduces 126 rings, sigma 77, RMS 1.59 (`profile-mine.json` is identical to `R/glow-profile.json`). My masked profile of `20261009-060049` in round one gave sigma 86. Two Reduce Motion takes therefore give 77 and 86, and Task 14 again fits one take.
- **Fix.** Fit sigma on the median profile of the six clean Reduce Motion takes.

### R9 (minor): a test prints a temporary path that can become the run's last line

- **Where.** `lab.py` `print(run_dir)`, reached from `test_takecheck.py` / `test_lab.py` (Task 3).
- **Fix.** Silence it in the tests, or include it in the expected output.

### R10 (minor): a debug hook joins the public API and the README omits it

- `lib/ios_liquid_glass.dart` now exports `debugGlassPress` for Operator's tests, but the README does not list it. This follows the precedent of `debugResetGlassAnimation`.
- **Fix.** Name it in the README's API table, as tests-only.

## F1 to F21 status

| F | Status | Check |
|---|---|---|
| F1 take rule | **partly** | Built into `run` and `repeat` (D5 B); a holed step's times read NaN. The squeezed-first-frame part is sound. Holes beyond 150 ms and dropped frames pass (R1) |
| F2 forecast on clean takes | fixed, with R2 | Six holed cases counted as failing. Passes are in-sample |
| F3 settled law | fixed, with R4 | Fitted on the plateau. Form choice is narrow |
| F4 masked sigma | fixed, with R8 | 77, RMS 1.59, reproduced |
| F5 cut per size | fixed | 632.5, 525, 418.3, 400 and 380.8 ms, reproduced; 360 × 200 takes 300 × 120's (2 cases). The 44 × 44 cut is 750 against 632.5, disclosed |
| F6 guards | fixed | Grid widened to 0.01 s / damping 4; edge share 7 % under the 25 % limit; Reduce Motion cut 564.2 ms from six presses (median of 560.0–570.0), reproduced; per-size rows unguarded, disclosed |
| F7 forecast completeness | fixed, with R2 | Items 1, 2 and 3 and the event gate are forecast as failing. Tallies recomputed: `glow_rise_ms` 22, `glow_half_ms` 19 and the rest exactly as stated |
| F8 neighbour rect | fixed | Right region and 64 × 64 pinned rect start 32 pt past the facing edge (`scenes.json`); the pressed glass's bridge is forecast as a merge-model failure |
| F9 light cases | fixed (disclosed failure) | Light fitted over four backdrops; light `stripes` forecast to fail (D10, R5) |
| F10 far drag | fixed, with R6 | Far drag (256 pt, one clean take) and upward drag (106 pt, two clean takes) recorded; no release |
| F11 Operator | fixed | 44 × 44 and 36 pt references; tests restored (press lights and grows, release, cancel, disabled, Reduce Motion, mid-press disable); replay red and green as stated |
| F12 held-out size | partly | 44 × 44 held out, but on the cap (R4) |
| F13 fade judged | fixed | `glow_level` and `glow_half_ms` |
| F14 interactive still check | fixed | `R/still-check-interactive.txt`: `missing: 0`, `worse: 0` |
| F15 logs | fixed | `replay-4.txt`, `replay-5.txt` |
| F16 shared checkout | fixed | `git -C …/Operator-2b3 worktree add` |
| F17 missing cases | fixed | Expected-case set in Task 15 Step 2 |
| F18 counts | mostly | One new error: the inverse constant (R4) |
| F19 tests | fixed | Five lifecycle tests in the green run; README says interactive glass is opaque to hit testing |
| F20 D1 mirror | fixed | `angle_union_test.dart` row scan passes (`+10`) |
| F21 style | fixed | No whitespace warning on apply |

## The numbers I recomputed

| Claim | Mine | Verdict |
|---|---|---|
| Law min(15.84, 9.72 (100/h)^1.22); held-out 0.636 against 0.685 | 15.84, 9.72, 1.22; 0.636 against 0.685; inverse at_100 is 9.82 | reproduced; the choice is fragile (R4) |
| Masked sigma 77 | 77.0, RMS 1.588, 126 rings | reproduced; one take (R8) |
| Cut per size | 632.5, 525.0, 418.3, 400.0, 380.8 | reproduced |
| Reduce Motion cut 564 ms from 6 presses | 564.17 (560.0–570.0, 6 presses) | reproduced |
| 304 of 440 (399 finite); 3 cases with `events.unpaired`; 6 capture-holed cases | same | reproduced; in-sample (R2) |
| 44 × 44: growth within 0.33 pt; light 10.4 dimmer; cut 750 against 632.5 | native 16.67 × 17.33 against Flutter 17.0 × 17.33; peaks 53.51 against 43.07; cuts 750.0 against 636.7 | reproduced; one clean native take |
| No release at 40, 106 and 256 pt; lean −0.035 / 1.67 pt | from `native-questions-2.txt`: 256 pt one clean take (the second is holed and agrees); 106 pt two clean takes; 40 pt one holed take | reproduced; take counts as above |
| `pressfit` output equals `R/pressfit.json` | identical | reproduced |

## Anything new without a test

- The leverage stop's write-then-stop order (R3) has no test. `LeverageTests` exercise `leverage()` only.
- `run`'s `capture_checked` keeps the last failing take after two retries and the `capture.<app>` gate fails it, so this is visible, not silent.
- `repeat` moves failing takes out of `$NOISE` (a copy). This is correct; the plan says the archive is only copied.
