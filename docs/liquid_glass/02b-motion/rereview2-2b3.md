# Third re-review of the 2B.3 plan (after fix round 2)

**Scope.**
- Reviewed: `plan-2b3.md` at `proto/2b3` `fe8d7f97a` (code `9adddc6b5`, `69d6a1421`, `65dbeba40`; evidence `30edcd386`; 18 patches).
- Scope: the fixes to `rereview-2b3.md` R1 to R10, plus D11.
- I did not touch the plan or the prototype. This file is the only addition and is not committed.
- No simulator was used: every disputed claim could be settled from recordings already on disk.

**Where I worked.**
- `/Users/omaraly/development/AI/Operator-2b3-rereview2`: a fresh clone at `fe8d7f97a`.
- `/Users/omaraly/development/AI/Operator-2b3-rereview2-replay`: a worktree of that clone at `development` `c0e69d9a4`, with the evidence committed.
- Copies of the recordings, without frame caches, under `Operator-2b3-review/packages/mobile/build/glass_lab/runs/`:
  - N1 and N2;
  - the 30 2B.1 noise takes;
  - the two takes 2B.1 excluded, read from the archive and never written to it;
  - the prototype's runs;
  - my light run `081334`.
- Scratch outputs: `scratchpad/rev/` (`gates-rr2/`, `replay3-out/`, `patches3/`, `newrule2-out.txt`, `variant.py`, `variant-out.txt`).

## Verdict

**Ready to execute: no.**

Only S1 blocks, and it is a small change: extend native's lost-frame test from 200 ms after touch-up to the end of the span. It flags none of the 54 clean native takes, and it covers the measures that are read after 200 ms.

S2 (D11) is the user's decision. I would change the plan's recommendation. With the 250 × 150 plateau included, a power form keeps every measured height within 0.54 pt. The plan's selection rule instead keeps the inverse law, which fails two heights. Everything else checks out.

Counts: blocker 0, major 2 (S1, S2), minor 4 (S3 to S6).

## Gates, code and replay

| Gate | Plan | Mine (fresh clone `fe8d7f97a`) |
|---|---|---|
| Harness | `Ran 310 tests`, OK | `Ran 310 tests`, OK |
| Package | `+280`, analyze clean | `+280: All tests passed!`, `No issues found!` |
| Example | `+25`, analyze clean | `+25`, `No issues found!` |
| App | `+2188`, analyze clean | `+2188: All tests passed!`, `No issues found!` |

**Code.** All 18 patch blocks are byte-identical to `git diff --full-index c0e69d9a4 65dbeba40 -- <files>`. Their files are exactly the 38 that the prototype changes.

**Replay.** I applied all 18 patches in order with `git apply --3way` and ran the fail-first and pass steps of the tasks below (`replay3-out/summary.txt`). Afterwards, all 38 files are `cmp`-identical to `fe8d7f97a`.

| Task | What it covers | Red | Green |
|---|---|---|---|
| 1 | span take rule | `ModuleNotFoundError` | `Ran 18`, OK |
| 3 | leverage stop, 5-take rule, kept floor | `FAILED (errors=9)` | `Ran 37`, OK, with `OK` as the last line (R9 fixed) |
| 4 | pressfit refit | `ModuleNotFoundError` | `Ran 16`, OK; harness gate `Ran 310`, OK |
| 5 | press | compile error | `+53`; `table reproduced by pressfit` |
| 9 | mirror | – | `+10` |
| 10 | Operator tests | press tests fail | `+12` |

- **Task 13 Step 2b** is prose, and its behaviour is pinned by `test_a_stopped_case_keeps_its_old_floor_and_repeat_exits_after_writing_the_others`, which passes.
- **Task 14b** (D6 B) is a written block with no patch. It was never prototyped (S4).

## R1: the take rule

I ran `takecheck.check` at `fe8d7f97a` on the takes the coordinator named (`newrule2-out.txt`).

| Takes | Result |
|---|---|
| 2B.1's excluded N1 `dark-stripes` | **FAIL**: a burst at 24.360 s (405 ms after touch-up at 23.955 s) and "101.7 ms lost while the glass moved" at 24.142 s (187 ms after touch-up, inside native's 200 ms window). The 80.0 ms gap 5 ms after touch-up is not flagged on its own, because the frame before it does not differ from the one before that; the 101.7 ms gap that follows is flagged. Pinned by `test_the_archived_dark_stripes_release_is_a_hole_with_its_lost_frames_and_its_burst`. |
| 2B.1's excluded N1 `dark-photo` | PASS (its release gaps are native's normal cadence, as before) |
| 30 2B.1 noise takes | **18 PASS**, 12 FAIL, every failure a squeezed first frame (writer: 18; matches) |
| First-round comparison takes | 7 of 8 FAIL. `063817` Flutter passes (gaps 5.0 then 1.7 ms), a borderline case |
| My light run `081334` (Flutter) | both FAIL (burst; squeezed first frame plus burst) |

**Is the native-window departure sound?**
- **After touch-down: yes.** `R/gap-phases.txt` shows native's own frames slowing to 33–57 ms gaps 103–265 ms after touch-down while the glass grows, in 43 of 56 takes. A loss there cannot be told apart from cadence.
- **After touch-up: no.** The same file lists no native gap over 30 ms with the glass moving on both sides after a touch-up: every "moving gap" it lists starts before touch-up. Native's first gap over 30 ms after touch-up comes at 238 ms or later, and only with the glass nearly still (the light holding before the cut).
- **My check.** I re-ran the take check with the lost-frame test extended to the whole span after touch-up, from touch-up to the next touch or touch-up + 1.2 s (`variant.py`). It flags **0 of 54** clean native takes (the 24 N1 and N2 references and the 30 noise takes).
- **Conclusion.** The 200 ms limit after touch-up is not justified by native's cadence. It leaves a native hole there unchecked: S1.

**What the unchecked part reads, and what protects it.**

| Measure | When it is read | Protected by |
|---|---|---|
| `shrink_ms` | 130–392 ms after touch-up (the release spring and its undershoot) | burst test and leverage stop only, beyond 200 ms |
| `glow_half_ms` | 80–207 ms after touch-up (Reduce Motion step 1 at 187–207) | partly the window; the rest as above |
| `glow_drop_ms`, `glow_fade_ms`, `glow_level` | the cut, 380–750 ms after touch-up | burst test and leverage stop only |
| `grow_ms` | native's 20 Hz phase after touch-down | burst test and leverage stop only |

- **The cut.** A delayed cut frame after native's still hold cannot be detected by frame times, because the glass is still before it. Its only protections are the span-wide burst test and the leverage stop, which needs the outlier to exceed 3× the median of its siblings' pairs and 11.3 ms.
- **`grow_ms`.** It sits in native's 20 Hz phase, which is unavoidable. The same two protections apply.

The plan says "a native gap later in the span is native's own cadence as often as a loss" but does not list which measures are affected; S1 asks it to.

## S1 (major): native's lost-frame test stops 200 ms after touch-up, though native draws at full rate while moving to the end of the span

- **Where.** `takecheck.span_holes` (`near = … or up <= t < up + RELEASE`), the rows' copy in `press.features`, and ruling 16.
- **Evidence.**
  - Extending the test after touch-up flags 0 of 54 clean native takes (`variant-out.txt`).
  - `R/gap-phases.txt` has no moving gap after any touch-up.
  - The measures read beyond 200 ms after touch-up are the `shrink_ms` tail, `glow_half_ms` under Reduce Motion, and the three cut measures.
- **Fix.**
  - For native, apply the lost-frame test from touch-down to touch-down + 100 ms **and from touch-up to the end of the span**.
  - Add a test: a native gap of 80 ms with the glass moving on both sides 300 ms after touch-up is a hole.
  - Re-run `hole-rule-check.txt`; I expect no change in the counts.
  - In ruling 16, name the measures that only the burst test and the leverage stop protect (`grow_ms`, the cut measures).

## S2 (major), and D11: the selection rule keeps a law that fails two heights when a fitted form passes all of them

**Recomputed.**
- On the 13 plateaus, `pressfit` gives the inverse law min(15.84, 9.70·100/h). Its leave-one-size-out RMS is 0.781, against 1.149 for the power form min(15.84, 9.73·(100/h)^1.28); in-sample RMS is 0.569 against 0.374. `R/pressfit.json` is identical to my run.
- Held out:
  - 250 × 150: native settles at 5.33 × 3.33 pt; Flutter at 6.33 × 4.33 (peak 7.0 × 5.33).
  - 44 × 44: 11 of 15 measures pass. The failures are `glow_peak` 10.27, the cut 83 ms early and `shrink_ms` 167 ms faster. Its growth passes, at the cap.

**Adding the 250 × 150 plateau (5.33 pt) to the fit.**

| Form | Constants | Residual at h 150 | Residual at h 200 | Other heights | Leave-one-size-out RMS |
|---|---|---|---|---|---|
| Inverse | at_100 9.58 | **+1.06** | **+1.12** | – | 0.807 |
| Power | 9.69·(100/h)^1.31 | +0.37 | +0.24 | 44–120 all within −0.54…+0.51 | 1.075 |

- So the power form keeps **every** measured height inside the 1 pt `grow_w` threshold. The inverse law fails two of them.
- Leave-one-size-out still prefers the inverse, because dropping the three 88 pt takes leaves the power form's exponent to two tall points. With so few sizes and a cap, it does not measure what Done item 1 asks: native's law at every size.

**Options.**
- **(a) Refit with 250 × 150 in, and record a new tall held-out size** (for example 300 × 170). Choose the form by "every fitted height within the `grow_w` threshold, then the lower held-out error".
  - Cost: a `pressfit` selection change with its tests (about 1 h in the prototype), one native and example scene, Task 12 references and Task 13 floors for it (about 45 min of recording with re-records), and a replay.
- **(b) Two-parameter forms** such as a/h^p above the cap, or a/h − b.
  - Same cost as (a). With four tall heights the extra parameter is barely identified.
- **(c) A table:** the median plateau per measured height, interpolated in log height and held flat beyond the ends, as the cut and the light already are.
  - Copies native exactly at every recorded size.
  - Same cost as (a), and it still needs a new held-out size to say anything between the rows.

**I would take (a)**, keeping the power form only if it passes every height. "Inverse law, fails at 250 × 150 and 360 × 200" is honestly disclosed (D11, the forecast), but the evidence on disk already supports a form that does not fail. Under spec M7 and Done item 1, shipping a known failure is the weaker choice.

## S3 (minor): `shrink_ms` is the largest independent failure and has no class

- **Evidence.** It accounts for 20 of the 104 independent failures (`R/flutter-compare-independent.txt`). The 44 × 44 releases 167 ms faster than native.
- Native's `shrink_ms` spans 136–392 ms across sizes and backdrops (`R/reproduce-glow.txt`). The press uses one release spring.
- **Fix.** Before Task 16 classes it, check whether the failures are size-dependent, as the cut was, or come from the measure's 2/3 pt band on small growths. Name the candidate (a release per size) in the forecast.

## S4 (minor): Task 14b is unprototyped and should not be run

- The user decided D6 A, so Task 14b will not run.
- **Fix.** Mark it "not run (user chose D6 A)" or move it to `todo-2b3.md`. An unprototyped code block in the plan invites an executor to run it.

## S5 (minor): native's onset window has only 3 ms of margin

- The window ends 100 ms after touch-down. Native's earliest slow gap starts at 103.3 ms (`gap-phases.txt`). A take whose 20 Hz phase begins at 98 ms would be re-recorded for no reason. That makes the rule stricter, not looser.
- **Fix.** Report the rate in Task 12. Lower the window to 90 ms if the rate is high.

## S6 (minor): the independent forecast is narrow

- **Recomputed.** In-sample 305 of 441 (414 finite) over 24 cases. Independent 276 of 380 over 18 pairs. The failure tallies match the plan.
- **Independence.** The 18 native takes are 2B.1 noise takes that no fit read: `pressfit` read `native-press-all.json` (N1 and N2) and `native-questions-2.json`. So they are independent of the table.
  - They pair with only six Flutter takes.
  - They cover only three sizes (250 × 88, 250 × 44, 58 pt circle), all on `photo`.
- So 138 × 53, 300 × 120, 360 × 200 and every `stripes` case have only in-sample numbers. The 360 × 200 `grow_w` failure is in-sample.
- **Fix.** Say so in one sentence under the table.

## Forecast honesty, Done items 1 to 4

- **Item 1.** Failing in part, with the tall-glass growth, the press-drag cut, light on light `stripes`, the small circles' light, `events.unpaired` and `delay_ms` named. Honest, apart from S2's framing and S3.
- **Item 2.** Neighbours "pass on absence" is a forecast: Flutter has not run them. The drags fail by D6 A. Honest.
- **Item 3.** Carries 2B.1's and 2B.2's Reduce Motion failures. Honest.
- **Item 4.** Passes on the median, with the dropped frames reported. Honest.

## R1 to R10 status

| R | Status | Check |
|---|---|---|
| R1 take rule | **fixed, with S1** | Span-wide burst and squeezed first frame; lost frames span-wide for Flutter. The excluded `dark-stripes` fails; noise takes 18 of 30. The native window after touch-up is narrower than its evidence (S1) |
| R2 in-sample forecast | fixed | Two columns; both recomputed; S6 |
| R3 leverage stop | fixed | No floor written for a stopped case; waits for 5 takes; Task 13 Step 2b procedure; tests pass |
| R4 law form | changed, with S2 | Inverse kept on 13 plateaus with a 1/3 pt gain rule; the held-out 250 × 150 fails growth; D11 |
| R5 D10 wording | fixed | "luma halves (solid)… colour suggestive only: 4:2:0 chroma"; model chosen by held-out RMS (6.14 against 9.51) |
| R6 D6 | fixed | Explicit departure from (a2); the user chose A; Task 14b remains in the plan (S4) |
| R7 `drag.out` under Reduce Motion | fixed | In Tasks 12, 13 and 15 |
| R8 sigma | fixed | Median of six takes' profiles: sigma 77, RMS 1.591, recomputed (the single-take fit gave 77 too) |
| R9 temp path | fixed | `OK` is the last line in my replay |
| R10 `debugGlassPress` | fixed | Named tests-only in the README (`65dbeba40`) |

## Decisions

| Decision | Plan | Mine |
|---|---|---|
| D1 | A (project 3) | agree |
| D2 | A | agree |
| D4 | A | agree |
| D6 | user chose A | remove or mark Task 14b (S4) |
| D7 | A | agree |
| D8 | A | agree |
| D9 | user chose A | the 44 × 44 reference holds for growth; the light is 10.3 luma dim and the cut 83 ms early, both disclosed |
| D10 | A | agree |
| D11 | A (keep the tool's rule) | **B-like, option (a) above** |

**New without a test.** None found beyond S1's missing case. Every new path in `takecheck`, `lab.repeat` and `pressfit` has a test, and they pass.
