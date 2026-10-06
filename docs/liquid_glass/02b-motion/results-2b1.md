# 2B.1 results

Date: 2026-10-06, after the review fix wave (parts 1 and 2) and the re-audit's fix round. Branch `feat/ios-liquid-glass-2b1`. Motion measured at `1a340d4bb` (the materialize table re-fitted with k = 1); still glass at `01b59747d` (the k = 1 table changes only partly visible glass, so the still runs were not repeated); gates at the tip (below). Simulator: iPhone 17 Pro (iOS 27), UDID 708879DD-8B2A-4547-863F-F49EE1474D8B, freshly booted at 2026-10-06 08:52:11 (boot A), 11:31:23 (boot B) and 19:08:43 (boot C). Run folders are under `packages/mobile/build/glass_lab/runs/`, fits under `packages/mobile/build/glass_lab/fitvis/`. `ReduceMotionEnabled` and `EnhancedBackgroundContrastEnabled` read `0` after every run and after the gates. Saved tool outputs are committed under `research/execution-2b1/` (paths below are relative to this folder); every ruling cited as P2-n, Task n or by a review finding is a line of `research/execution-2b1/ledger.md`. The fit is `research/execution-2b1/fix3-fit.json`.

This file replaces the first results (measured at `58ab57e0c`, k = 3) and part 2's results (measured at `36039801b`, k = 0.5). The review audit (`review-2b1-audit.md`, A1–A10) and the code review (`review-2b1-code.md`) led to part 2: a fresh-boot noise session, a joint objective for the blur ramp k, peak-fitted gains and the corrections A2–A10. The re-audit of part 2 (P2A-1 to P2A-9, in the main session's scratch) found that part 2's k = 0.5 was an artefact of the ramp scan's visibility grid. The fix round added visibility levels below 0.2, re-fitted (k = 1), re-ran Done item 4, replaced one press noise take, re-recorded two N1 cases and corrected the documents. Numbers from the earlier rounds stay where they are still the record, each marked with its commit.

**How the numbers were read.** Every motion number is a `motion.*` measure of a run's `result.json`, judged against max(fixed threshold, 1.5 × noise) with the per-case noise of `tool/glass_lab/noise.json` (recomputed in part 2, `644972ba7`; one press case again in the fix round, `c546e42d6`, no materialize floor changed). `done_table.py` counts them per case: the seven `progress.*` measures per event pair are the Done item 4 measures; the event and touch gates (`events.*`, `touches.*`) are counted apart. Every still number is the `static.ready` block; `still_check.py` compares `ready` and `settled`, case by case, against the 2A runs of `results-2a1.md`, read in place. Commands run from `packages/mobile`.

## The Done table

| Done item (spec §8, 2B.1) | Result | Evidence |
|---|---|---|
| 1 L1–L3, L5–L8 tested and reproducing known numbers | **Pass.** Disappear 117–133 ms and appear 275–292 ms (ruling 6's 120 Hz estimator; the two 275 ms appears are 10 ms under the spec's 285, inside their `t10_90_ms` noise). Not an alpha fade on `photo`; v13 +12.00 / +4.66; short glass +17.00 (58 pt circle) and +16.00 (138 × 53); `button.press` +16.00 in all six runs; menu 0.26–0.30 s / 0.74–0.81. The spike's 250 × 44 (+17.67) **reproduces on `photo`**: +17.00 to +17.33 pt in all 12 recordings of N2 and its noise takes. On `stripes` it reads +14.33, L1's blind band (below). | harness `Ran 204 tests` OK; `reproduce.py materialize\|press\|menu` byte-identical to `research/execution-2b1/task-6-reproduce.txt` (`fix2-reproduce.txt`); `fix2-press-sizes.txt` |
| 2 Noise floors for every 2B.1 scene and case | **Pass**: 15 scenes, 60 cases, five native takes each from at least two simulator boots, static `mad` 0.00 in every case. The stale first session was replaced after a fresh boot; 20 takes failing the outlier rule or the touch gate were excluded and replaced (below). Every limit that moved is disclosed. | run `noise-2b1`; `noise.json` at `c546e42d6`; `research/execution-2b1/fix2-noise-disclosure.md`, `fix2-noise-cases.json` |
| 3 N1, N2, N5, N7 and N6 (materialize) recorded | **Pass**, N1, N2, N5 and N6 re-recorded after fresh boots; every reference case passes the outlier rule and the touch gate (two N1 cases re-recorded for it); press holds read 0.98–1.00 s for the scripted 1.0 s | N1 `20261006-085522` (dark cases from `20261006-191235`), N2 `20261006-085825`, N5 `20261006-091133`, N6 `20261006-091925` (its dark-photo-reduce-motion case from `20261006-144758`); N7 Task 8's `20261004-003527` (still scenes) |
| 4 Materialize passes under default, `.snappy`, `.bouncy` and Reduce Motion, per shape | **Partly failing.** Progress measures (passing / judged / expected), at k = 1: normal **133 / 168 / 168** (132 as first run), Reduce Motion **133 / 168 / 168**. Event and touch gates **120 / 120**, `unpaired` 0. Before: 129 and 134 at k = 3 (the first results), 136 and 133 at k = 0.5 (part 2), each with repeats per event. The 70 failures are classed below: **35 (b), 33 (a), 2 (d)**. | runs `20261006-204707` (normal), `20261006-210255` (Reduce Motion), repeat `20261006-211934`; `fix3-done-table-{normal,rm,repeat}.txt` |
| 5 Still glass no worse than 2A | **Pass**: `missing: 0` and `worse: 0` in all nine scenes, Operator's three included; **120 of 124** Flutter frames byte-identical to 2A's, `material.edge`'s 12 now among them (the A9 fix). The four `button.press` Flutter frames differ only at the two buttons' rims, which now sit on their layout positions where 2A's were snapped (below); no static measure changed pass or fail. | nine runs `20261006-165449` … `20261006-175623`; `still_check.py`, `research/execution-2b1/fix2-still-<scene>.txt` |
| 6 Gates | **Pass**: app `+2146`, package `+155`, example `+13`, all three `flutter analyze` clean; harness 204 OK | below |

### Done item 4 per scene and appearance

Progress measures passing / judged / expected at k = 1, with the one repeat substituted for its stalled event only (A5). Each line is two cases (`photo` and `stripes`) of two events each. Gates are 10 / 10 on every line.

| Scene | Appearance | Normal | Reduce Motion |
|---|---|---|---|
| `material.materialize` (default) | dark | 20 / 28 / 28 | 22 / 28 / 28 |
| `material.materialize` (default) | light | 21 / 28 / 28 | 28 / 28 / 28 |
| `material.materialize.snappy` | dark | 23 / 28 / 28 | 20 / 28 / 28 |
| `material.materialize.snappy` | light | 24 / 28 / 28 | 23 / 28 / 28 |
| `material.materialize.bouncy` | dark | 22 / 28 / 28 | 20 / 28 / 28 |
| `material.materialize.bouncy` | light | 23 / 28 / 28 | 20 / 28 / 28 |
| **Total** | | **133 / 168 / 168** | **133 / 168 / 168** |

Failing pairs by measure, out of 24 per run (normal / Reduce Motion): `t10_90_ms` 2 / 4, `settle_ms` 5 / 5, `overshoot_pct` 0 / 0, `response_pct` 7 / 8, `damping` 12 / 9, `rms` 0 / 0, `sharpness` 9 / 9.

**Repeats.** One Flutter gap over 25 ms sat inside an event: normal `.snappy` dark-photo disappear, 26.7 ms at +67 ms, between progress 0.40 and 0.27 (`fix3-stall-events.txt`). That case was repeated alone (`run material.materialize.snappy --appearance dark --backdrop photo`, `20261006-211934`, stall-free) and only its disappear substituted (A5's rule): 6 of 7 against 5 of 7; its appear was not stalled and is kept from the first run. Native had no gap over 25 ms inside an event in either run. Every native recording of the three runs passes the capture-hole rule and the touch gate (25 recordings).

### Before and after

Every row is a full Done item 4 run pair: normal / Reduce Motion progress measures passing, of 168 each.

| Round | k | Floors | First run | Repeats substituted per event |
|---|---|---|---|---|
| First results (`58ab57e0c`) | 3 | `fd30f969d` | 130 / 133 | **129 / 134** |
| Part 2, judged on the old floors | 0.5 | `fd30f969d` | 140 / 135 | 141 / 135 |
| Part 2 (`36039801b`) | 0.5 | `644972ba7` | 135 / 133 | **136 / 133** |
| Fix round (`1a340d4bb`) | 1 | `644972ba7` (materialize unchanged in `c546e42d6`) | 132 / 133 | **133 / 133** |

From k = 3 to k = 0.5 two things moved the count (re-audit P2A-2, on both bases):
- **the new k and gains**: +10 / +2 on the first runs (130 → 140, 133 → 135), +12 / +1 per event (129 → 141, 134 → 135);
- **the new floors**: −5 / −2 on both bases (140 → 135, 135 → 133; 141 → 136, 135 → 133). On those runs they fail 12 values that the old floors passed and pass 5 that they failed.

From k = 0.5 to k = 1 the floors are the same, so the change is the new k (with the gains and table fitted at it) and the runs' own spread: −3 / 0 on both bases. The failures move between backdrops with k:

| Failures by backdrop | k = 3 | k = 0.5 | k = 1 |
|---|---|---|---|
| dark-photo, sharpness | 12 | 12 | 12 |
| dark-photo, the rest | 15 | 27 | 17 |
| dark-stripes | 14 | 17 | 12 |
| light-photo (sharpness) | 15 (0) | 6 (1) | 16 (6) |
| light-stripes | 16 | 5 | 13 |
| **Total** | **72** | **67** | **70** |

(The k = 3 list is the audit's section 2; k = 0.5 `fix2-failing-measures.json`; k = 1 `fix3-failing-measures.json`.) The runs also differ by the Flutter debug build's run-to-run spread, which no floor carries (A5); the re-audit's leave-one-take-out pass over the noise takes moves ±20 verdicts.

## Run folders

| Step | Command | Run folder | Report counts |
|---|---|---|---|
| Task 5 touch check | `run material.materialize --appearance dark --backdrop photo` | `20261003-234148` | marker check only |
| Task 8 (native, superseded) | N5, N6, N1, N2, N7 | `20261004-000223`, `-001040`, `-001855`, `-002204`, `-003527` | recorded before the 2026-10-04 reboot; N7 is still the reference |
| Part 2 stage 1 | `run material.interactive --app native` (N1) | `20261006-085522` | 4 cases; dark-photo and dark-stripes replaced from `20261006-191235` (`RERECORDED.txt`) |
| Part 2 stage 1 | `run material.press --app native` (N2) | `20261006-085825` | 20 cases, native only |
| Part 2 stage 1 | `run material.materialize --app native` (N5) | `20261006-091133` | 12 cases, native only |
| Part 2 stage 1 | the same, `--a11y reduce-motion` (N6) | `20261006-091925` | 12 cases; dark-photo-reduce-motion from `20261006-144758` (`RERECORDED.txt`) |
| Fix round | `run material.interactive --app native --appearance dark` (N1, boot C) | `20261006-191235` | 2 cases, copied into N1; a boot-B attempt `20261006-190046` held its presses 1.9–2.1 s and is not used |
| Task 9 + part 2 + fix round | noise takes: session 1 in boot A (three per case), session 2 kept or replaced in boots B and C (two per case) | `noise-2b1` (`takes/`, `stale-session1/`, `excluded/`) | 60 cases, static `mad` 0.00 |
| Fix round | `fitvis 20261006-091133 20261006-091925 noise-2b1 --ramps 0.25,0.5,1,1.5,2,3,4 --write` | `fitvis/fix3-20261006-192018` | `fix3-fit.json` |
| Fix round | `run material.materialize` | `20261006-204707` | pass 0, fail 12 |
| Fix round | `run material.materialize --a11y reduce-motion` | `20261006-210255` | pass 2, fail 10 |
| Fix round repeat | `run material.materialize.snappy --appearance dark --backdrop photo` | `20261006-211934` | pass 0, fail 1 |
| Part 2 (k = 0.5, superseded) | fit, Step 5 runs and repeat | `fitvis/fix2-20261006-115226`, `20261006-154138`, `-155725`, `-162523` | part 2's numbers above |
| Step 7 | `run material.regular` | `20261006-165449` | pass 8, fail 2 |
| Step 7 | `run material.clear` | `20261006-170542` | pass 2, fail 2 |
| Step 7 | `run material.tinted` | `20261006-171006` | pass 0, fail 6 |
| Step 7 | `run material.edge` | `20261006-171635` | pass 5, fail 1 |
| Step 7 | `run material.regular --a11y reduce-transparency` | `20261006-172307` | pass 8, fail 2 |
| Step 7 | `run material.regular --a11y increase-contrast` | `20261006-173358` | pass 9, fail 1 |
| Step 7 | `run tabbar.rest --flutter operator` | `20261006-174454` | pass 0, fail 8 |
| Step 7 | `run button.press --flutter operator` | `20261006-175336` | pass 0, fail 2 |
| Step 7 | `run navbar.inline --flutter operator` | `20261006-175623` | pass 0, fail 6 |
| Step 7, lost | the first still attempts: one stopped at 36 GB free, five whose every case failed `recordVideo did not start` behind an orphaned recorder (Deviations 7) | `20261006-162805`, `-163622`, `-164138`, `-164345`, `-164655`, `-165005` | not used |
| Before the fix wave | Step 5, repeats, cold probe, still runs, ghosts | `20261005-233131`, `-234750`, `20261006-001644`, `-002044`, `-002206`, `cold/20261006-002600`, `20261006-003104` … `-013445`, `ghost/20261006-014735`, `-014805` | the first results |

`lab.py report` passes a materialize case only when all its measures pass, so its counts are not Done item 4's; `done_table.py`'s are.

## Done item 1: the lab reproduces the known numbers

`reproduce.py` reads recordings only (copied into `build/glass_lab/reference/` by Task 6). Run at the tip for its three parts, its output is byte-identical to `research/execution-2b1/task-6-reproduce.txt` and to the prototype's `research/proto-2b1/reproduce.txt`.

| Number (spec §8 item 1) | Read | Verdict |
|---|---|---|
| disappear 117–167 ms | 133, 117, 125, 117 ms (`LG-20260930-082046`: dark-photo, dark-stripes, light-photo, light-stripes) | pass |
| appear 285–320 ms | 275, 275, 292, 292 ms | pass within noise: ruling 6 records that the spec's range came from a first-frame estimator that reads up to 28 ms longer |
| not an alpha fade | residual peak 5.12 / 5.37 against a floor of 2.67 / 2.13 on dark / light `photo`; half-progress sharpness −1.08 to −1.54 | pass (ruling 5) |
| v13 +12 / +4.67 pt at 250 × 88 | 252.0 × 88.67 → 264.0 × 93.33, +12.00 / +4.66 | pass |
| about +17.5 pt on glass up to about 60 pt tall | v16 +17.00, v17 +16.00 (both `stripes`, `reproduce.py`); 250 × 44 on `photo` +17.00 to +17.33 in both appearances (12 recordings), N2 `20261006-085825` and the `noise-2b1` takes (`fix2-press-sizes.txt`) | **pass.** The `stripes` reading of v18 and of N2 is +14.33: at the peak both capsule ends sit on the stripe boundaries at 67 and 335 pt, inside L1's blind band, and the box reads 266.33 pt wide against 268.0–268.33 on `photo` (1.7–2.0 pt short), from a rest of 252.0 against 251.0–251.33. The blind band cost about 2.7–3.0 pt of growth here, not the ±0.67 pt per edge the first results assumed (A2). |
| `button.press` 138 → 154–155, 174 → 190–192 | 138.33 → 154.33 and 174.33 → 190.33 (+16.00) in all six runs | pass |
| menu open 0.26–0.30 s / 0.74–0.81 | three pairs: 0.27/0.78, 0.26/0.81, 0.30/0.74 | pass (ruling 3) |
| touches (L5) | run `20261003-234148`: two touches per app; in part 2 every noise take and reference kept passes the touch gate | pass |

**The size law, fitted on `photo`** (A2; `fix2-press-size-law.json`): over 72 recordings on `photo` (N1, N2 and the noise takes of all six sizes), width growth is Δw = min(16.82, 1014 / h) pt, RMS 0.67 pt, neither parameter on its grid edge. Per size on `photo`: 44 pt +17.00 to +17.33, 53 pt +16.67, 58 pt +16.67, 88 pt +12.00, 120 pt +8.67, 200 pt +3.0 to +4.33. Every `photo` box has an edge flagged in the blind band (`edge_in_band`: the photo's own edges are strong), so no recording avoids it; the law agrees with the spec's inference (min(17.5, 1100 / h)) within 0.7 pt. 2B.3 judges press against it.

## Done item 2: noise floors

`noise.json` holds `{scene: {case: {measure: noise}}}` for every 2B.1 scene. Values per scene: `material.materialize` 503, `.snappy` 496, `.bouncy` 497, `material.interactive` 318, `material.press.138x53` 187, `.250x44` 136, `.300x120` 147, `.360x200` 91, `.circle58` 209, the six `material.spacing.*` scenes 32–36 each. `material.regular`, `tabbar.*`, `menu.bar` and the spacing scenes are byte-identical to before part 2.

**The takes.** Five per case:
- **Session 1, three takes** (slots 0–2), recorded after the fresh boot A (2026-10-06 09:27–11:30, load 3.9–8.9 at the start of every motion scene). The stale session 1 (2026-10-04, a simulator boot from before the 04:02 reboot, on a Mac then up nine days) is moved, not deleted, to `noise-2b1/stale-session1/` with every pair folder that used it (A10).
- **Session 2, two takes** (slots 3–4): kept from the 2026-10-04 04:02 boot (and Task 9's four replacements of 2026-10-05), or replaced after boot B (2026-10-06 11:31) where a take was excluded.
- One slot (`press.circle58` dark-stripes 1) was recorded in boot C in the fix round. Ten cases hold takes from three boots (Task 9's four replaced cases and six whose session 2 lost one take); every case holds takes from at least two.

**The outlier criteria**, applied to every take, uniformly (A10, re-audit P2A-4): `task9scan/report.py`'s rule (an event whose first or second frame gap is over 30 ms, followed by at least two gaps under 5 ms in the next ten), run with the branch harness (its rows for the 92 session-2 takes that did not change are identical to `task-9-scan.md`), and the touch gate the analysis judges, as stated: the touch count, a press of 0.8–1.2 s, a press-drag of 1.0–1.6 s, every touch step owning an event (`task-9-outliers.md` names the zero-length touch window next to the rule). **20 takes were excluded and replaced**; the list with each take's numbers is in `noise-2b1/excluded/README.txt` and in the ledger:
- 12 old session-2 press and interactive takes that Task 9 had kept (the rule flags them);
- 6 boot-A takes: 3 by the rule (`press.138x53` dark-stripes 0, `press.circle58` dark-stripes 0 and 1), 3 by the touch gate (`press.300x120` dark-stripes 1, a 0.12 s press; `.bouncy` dark-stripes-reduce-motion 2, one touch of two; and, in the fix round, the replacement `press.circle58` dark-stripes 1, a 1.225 s press, which part 2 had explained away and should have excluded);
- 2 failed replacements in boot B: `material.interactive` dark-photo 4 (the rule) and `press.circle58` dark-stripes 1 (a 2.373 s press, below).

**The press-hold check** (A10): every press in the takes in use and in N1 and N2 reads 0.977–1.030 s for the scripted 1.0 s (median 0.990); press-drags 1.30–1.36 s. The stale session read 3.26 s (median) and Task 8's N1 and N2 1.54–2.87 s. A fresh boot restores the scripted hold, but not for long: boot B read 0.98–1.00 s four hours after it started and 1.9–2.4 s at seven and a half (XCUITest synthesized the 1.0 s press over 2.44 s), so the fix round rebooted again (boot C, ruling P2-11, ROADMAP gotcha 49).

**Recomputed** by `lab.case_noise` in its canonical take order (A6), for all 60 cases (`644972ba7`), and for the one replaced press case in the fix round (`c546e42d6`).

**Every limit that moved** (A7): `research/execution-2b1/fix2-noise-disclosure.md` lists all 1089 of part 2, each with its scene, case, measure, old and new noise and limit (of the judged item-4 limits, **59 moved tighter and 54 looser**; of the others, 561 tighter and 415 looser), and in a second section the fix round's 12 (`press.circle58` dark-stripes, 4 tighter and 8 looser, none judged). The largest judged loosenings, with their pairs:
- **default `light-photo-reduce-motion` disappear: `response_pct` 21.4 → 335.7 %, `settle_ms` 17 → 150 ms, `damping` 0.165 → 0.57.** One take sets all three: new session-1 take 2 (`takes/material.materialize/light-photo-reduce-motion/2`). Every pair with it reads 196–224 %, 100 ms and 0.31–0.38; no other pair passes 8.7 %, 0 ms and 0.07. Its onset is read 98 ms before the glass moves: after a 378 ms idle gap the first changed frame and the next, 53 ms later, still read progress 0.981. It passes the outlier rule and the touch gate, so it stays for 2B.1 (ruling P2-6). **That case passes 14 of 14 with or without the take**: judged on the floors of the other four takes its limits for those measures read 13.0 %, 17 ms and 0.105, against the Reduce Motion run's values 9.1 %, 16.7 ms and 0.04 at k = 0.5 (re-audit P2A-6, verified); the k = 1 run passes the case 14 of 14 too. The cause is the onset definition (the first changed frame), an analysis defect (d), not native variation. **This take must not feed a later plan's floors**: before 2B.2 or 2B.3 reuses `noise.json`, either the onset is defined as the first frame that moves by more than the progress noise and the floors are recomputed, or the slot is re-recorded (`todo-2b1.md`, ROADMAP gotcha 52).
- `.bouncy` dark-stripes appear `settle_ms` 75 → 225 ms: pairs with new take 2 read 108–150 ms, the others 0–42; take 2's appear differs from take 1's by 0.02–0.03 of progress, enough to move a 2 % settle band on a 5 % overshoot. Native variation.
- `.snappy` dark-photo-reduce-motion appear `response_pct` 27.9 → 80.2 %: one cross-session pair (3-2); the rest 0–29.4.
- default light-stripes disappear `response_pct` 39.1 → 61.8 %: one cross-session pair (Task 9's replacement against new take 0).

## Done item 3: native references

N1, N2, N5 and N6 were re-recorded after a fresh boot (ruling P2-4: Task 8's came from the stale boot). Every case was then checked with the outlier rule and the touch gate (re-audit P2A-5): N2's 20, N5's 12 and N6's 12 pass; N1 dark-photo (a step-1 event after a 616.7 ms gap, then 2 gaps under 5 ms) and dark-stripes (a step-3 event after gaps of 80.0 and 101.7 ms, then 5 under 5 ms) were capture holes. Both were re-recorded in boot C (`20261006-191235`; presses 0.987 and 0.985 s, press-drags 1.312 and 1.323 s, the rule and the gate pass) and copied into N1; the old cases are under `20261006-085522/excluded/`. N6's dark-photo-reduce-motion case had already been replaced (ruling P2-7).

N5 and N6 per case (10–90 % in ms; appear overshoot):

| Preset | Normal: disappear / appear | Reduce Motion: disappear / appear |
|---|---|---|
| default | 125–142 / 275–300 | 125–142 / 283–300 |
| `.snappy` | 117 / 200–225, overshoot 0.25–0.32 % | 117 / 200–208, 0.29–0.50 % |
| `.bouncy` | 100–108 / 133–158, overshoot 1.48–2.48 % | 100–108 / 133, 3.42–3.78 % |

- **N1** `material.interactive`: +12.00 pt width in all four cases (dark-stripes +12.00 / +4.66, v13's numbers), rest 251.33–252.0 × 88.67–89.67 pt; presses 0.978–0.997 s, press-drags 1.312–1.335 s.
- **N2**: per size above (Done item 1, the size law).
- **N7** spacing (Task 8, `20261004-003527`): the default container joins at gaps 0 and 4 pt (necks 25.33 and 4.00 pt); `spacing: 40` joins at 0–20 pt (necks 50.67 … 2.00) (ruling 23).

## The fit (fix round)

`lab.py fitvis 20261006-091133 20261006-091925 noise-2b1 --ramps 0.25,0.5,1,1.5,2,3,4 --out <absolute> --write` (`fitvis/fix3-20261006-192018`). The write guard passed with no override (`write_problems` empty, `overrides.used` empty); `ios27_motion.dart` is byte-identical to `fitvis.table_source` of `fix3-fit.json`. The folder links part 2's shots at the levels part 2 scanned; three of them were shot again and are byte-identical to the old ones, so the renderer and the new boot did not change them.

**Why part 2's k = 0.5 was wrong** (re-audit P2A-1, ruling P2-9 overturned). Part 2's ramp scan had no visibility level between 0 and 0.2. At k ≤ 0.5 dark-photo passes progress 0.25 before visibility 0.2, so its sharpness at p = 0.25 was interpolated toward the visibility-0 shot, where the glass is absent and the sharpness is 0 by construction. That understated the blur exactly at the k it favoured, and made 0.5 look best by 0.006. The fix (`f57618dd3`): the ramp scan adds levels 0.05, 0.1 and 0.15, and the objective scores no sharpness target whose bracket includes the glass-absent shot, leaving such a target out at every k so that every k is scored on the same targets. Even with the level at 0.05, dark-photo at p = 0.25 is read against the glass-absent shot at k = 0.25, so that one target is left out.

**The blur ramp k, on the joint objective (A1).** Sharpness RMS at matched progress over the targets every k measures / 1.0, plus per-backdrop progress deviation RMS / 0.05, against native's deviation from its own backdrop mean at the same point of the transition. Static scan values; "gap" is |Flutter − native| half-progress sharpness; a deviation is a backdrop's progress at the visibility where the backdrops' mean reaches 0.5, minus that mean (`fix3-fitvis.txt`, `fix3-fit.json`):

| k | Sharpness RMS | Deviation RMS | Objective | Half-progress sharpness gap, dark-photo / light-photo (limit 1.0) | dark-photo deviation (native +0.038) | dark-stripes (native +0.092) | light-photo (native −0.063) | light-stripes (native −0.067) |
|---|---|---|---|---|---|---|---|---|
| 0.25 | 0.9727 | 0.0971 | 2.915 | 1.64 / 1.21 | +0.197 | −0.031 | −0.094 | −0.073 |
| 0.5 | 0.9726 | 0.0704 | 2.3812 | 1.63 / 1.22 | +0.131 | −0.019 | −0.065 | −0.047 |
| **1.0 (chosen)** | 0.941 | 0.0587 | **2.1144** | 1.62 / 1.22 | +0.048 | −0.005 | −0.029 | −0.013 |
| 1.5 | 0.8657 | 0.0679 | 2.2241 | 1.62 / 1.21 | −0.012 | +0.004 | −0.003 | +0.010 |
| 2.0 | 0.7127 | 0.0782 | 2.2774 | 1.57 / 1.14 | −0.044 | +0.010 | +0.012 | +0.022 |
| 3.0 | 0.7846 | 0.0969 | 2.7229 | 1.55 / 0.87 | −0.102 | +0.018 | +0.039 | +0.045 |
| 4.0 | 0.9823 | 0.1081 | 3.1433 | 1.47 / 0.38 | −0.133 | +0.023 | +0.053 | +0.056 |

k = 1 is interior and wins by 0.11 over k = 1.5. At k = 1 Flutter's static per-backdrop progress matches native's on dark-photo within 0.01 at half progress (and within 0.02 at 0.25 and 0.75) and leaves the light backdrops 0.03–0.05 behind native; at k = 0.5 it was the other way round. No k matches dark-stripes (native +0.092; Flutter −0.031 to +0.023 at every k). No k passes dark-photo's half-progress sharpness (1.47–1.64); part 2's "k = 0.25 passes dark-photo (0.82)" was the same artefact (re-audit P2A-1). Light-photo passes from k = 3 (0.87).

**Exponents and gains.**

| Preset | Disappear exponent (per take; per case) | Appear gain, normal (per case dark-photo, dark-stripes, light-photo, light-stripes; per appearance dark / light) | Appear gain, Reduce Motion (the same) |
|---|---|---|---|
| default | 3.1 (3.05–3.2; 2.45–3.65) | inert (the spring does not overshoot) | inert |
| `.snappy` | 2.75 (2.65–2.75; 2.2–3.1) | **0.44** (0.76, 0.44, 0.38, 0.42; 0.52 / 0.40) | **0.60** (1.24, 0.54, 0.52, 0.58; 0.72 / 0.54) |
| `.bouncy` | 2.7 (2.7–2.85; 2.3–3.05) | **0.50** (0.64, 0.48, 0.44, 0.54; 0.52 / 0.50) | **0.80** (1.28, 0.80, 0.68, 0.80; 0.90 / 0.72) |

24 disappear curves per preset, none excluded; no exponent or gain on a grid edge or the floor, per case included. The exponents are part 2's; the gains moved by 0–0.02 with the table above full (`ios27VisibilityAboveFull` = 1.0664 … 1.4658 for progress 1.05 … 1.35). The gains are fitted on the overshoot peak: native's mean appear overshoot per case against the overshoot Flutter's own static scan shows at the visibility the package draws (A4, A8, C4). `.snappy`'s gain is no longer the floor: native's `.snappy` overshoots 0.28–0.48 % and the peak fit sees it (A8).

**Pooled, not per appearance** (ruling P2-8, its full cost per re-audit P2A-7). The dark and light per-appearance gains differ by 0.12 (`.snappy` normal), 0.18 (`.snappy` Reduce Motion), 0.02 (`.bouncy` normal) and 0.18 (`.bouncy` Reduce Motion). In every preset and mode the dark split is dark-photo's alone (its per-case gain 0.64–1.28), while dark-stripes sits with the light cases (0.44–0.80 against 0.38–0.80): Flutter's dark-photo progress above full rises more slowly than the others'. The package cannot see its backdrop, so a dark gain chases dark-photo and pushes dark-stripes past native (Reduce Motion `.bouncy`, predicted: dark-stripes 4.47 % per appearance against native 3.96 %, pooled 3.98 %). The cost of pooling: dark-photo's predicted appear overshoot stays 1.26 points under native in Reduce Motion `.bouncy` (2.27 against 3.53 %; 2.54 per appearance), and the light cases take 0–0.08 more gain than their own appearance fit (0.44 against 0.40, 0.60 against 0.54, 0.50 against 0.50, 0.80 against 0.72). Per appearance lowers the squared error over the four cases by construction, but only by moving dark-photo.

**Predicted against realised overshoot** (re-review P1-7; `fix3-overshoot-predicted-vs-measured.md`): the fit's static prediction of Flutter's appear overshoot against what the k = 1 Done runs measure, with the run's native in brackets, in %.

| Preset, mode | dark-photo | dark-stripes | light-photo | light-stripes |
|---|---|---|---|---|
| `.bouncy` normal: predicted / measured (native) | 1.42 / 1.31 (1.44) | 2.48 / 2.52 (1.99) | 2.79 / 2.75 (2.41) | 2.56 / 2.81 (2.53) |
| `.bouncy` Reduce Motion | 2.27 / 1.95 (2.83) | 3.98 / 4.11 (3.57) | 4.47 / 4.56 (3.67) | 4.10 / 3.98 (3.67) |
| `.snappy` normal | 0.17 / 0.07 (0.30) | 0.30 / 0.13 (0.28) | 0.34 / 0.19 (0.24) | 0.31 / 0.22 (0.31) |
| `.snappy` Reduce Motion | 0.23 / 0.11 (0.48) | 0.41 / 0.20 (0.34) | 0.46 / 0.39 (0.37) | 0.42 / 0.30 (0.43) |

`.bouncy` realises 0.86–1.10 of the prediction, within the 20 % the re-review set. `.snappy` realises 0.39–0.85: at 0.1–0.5 % the overshoot is at the progress measure's resolution, and the gain is not identified there (a fit defect, in `todo-2b1.md`). `overshoot_pct` passes in every pair; its limit is 2 %. In these runs native's `.bouncy` overshoot came out 0.06–0.70 points under the noise-take means the gains were fitted to (Reduce Motion 2.83–3.67 against 3.53–4.09 %).

**The default spring** (A3): pooled native default fits 0.58 s / 0.97 (RMS 0.0277; per case 0.58 / 0.97 dark-photo, 0.71 / 0.79 dark-stripes, 0.51 / 1.09 light-photo, 0.45 / 1.24 light-stripes). Every recording group read 0.57–0.59 s / 0.94–1.01, consistent with SwiftUI's 0.55 / 1.0 within the fit's resolution: the error surface is flat (0.57 and 0.58 differ by 0.00002 RMS, A3), so `pass: false` at 0.58 says nothing about native. The per-case springs are stable across every recording group, so the lab's progress measure gives systematically different springs per backdrop. The presets stay SwiftUI's springs (ruling 10).

**The static scan does not describe moving glass** (`fix3-static-vs-moving.txt`, by `fix3_static_vs_moving.py`). For the default appear, the progress Flutter's moving glass shows at 50 / 100 / 150 ms after onset against what its own static scan predicts at the visibility the package draws at those times (the SwiftUI spring through the fitted table):

| Backdrop | k = 0.5 run: moving / still scan | k = 1 run: moving / still scan | native, k = 1 run |
|---|---|---|---|
| dark-photo | 0.26, 0.47, 0.66 / 0.18, 0.45, 0.65 | 0.21, 0.45, 0.63 / 0.12, 0.35, 0.56 | 0.11, 0.30, 0.50 |
| dark-stripes | 0.17, 0.37, 0.55 / 0.11, 0.30, 0.49 | 0.18, 0.39, 0.57 / 0.12, 0.32, 0.51 | 0.12, 0.33, 0.52 |
| light-photo | 0.10, 0.27, 0.47 / 0.08, 0.25, 0.44 | 0.19, 0.39, 0.57 / 0.10, 0.29, 0.48 | 0.05, 0.19, 0.38 |
| light-stripes | 0.11, 0.29, 0.49 / 0.09, 0.27, 0.46 | 0.21, 0.41, 0.59 / 0.11, 0.31, 0.50 | 0.12, 0.31, 0.49 |

At k = 1 the moving glass runs 0.06–0.10 of progress ahead of its static prediction on every backdrop, and the static prediction itself tracks the spring and native; at k = 0.5 the lead was 0.02–0.08, largest on dark-photo. The objective that chooses k reads only the static scan, so it cannot see this lead; why moving glass reads more progressed than still glass at the same visibility is not established (H4 below).

## Every failing materialize measure, classed by cause

Classes: **(a)** tunable (a fitted value), **(b)** model limitation, **(c)** lab scene, **(d)** measurement artifact, **(e)** the debug build. No limit was loosened. Each class is decided by evidence: the per-k table of the fit, the per-case fits, the moving-against-still table, the crops, and per pair the native and Flutter features in `research/execution-2b1/fix3-failing-measures.json` (repeated in the tables at the end of this section). The groups are those of the k = 1 runs; part 2's groups G1–G6 at k = 0.5 are in its commit (`84e7b92f9`).

| Group | Class | Measures | Normal | Reduce Motion |
|---|---|---|---|---|
| H1 half-progress sharpness on dark `photo` | b | `sharpness` | 6 | 6 |
| H2 half-progress sharpness on light `photo` | a | `sharpness` | 3 | 3 |
| H3 a native capture that misses the disappear's start | d | `response_pct`, `damping` | 2 | 0 |
| H4 default and `.snappy` appears stiffer than native, every backdrop | a | `response_pct`, `damping`, `settle_ms` | 16 | 11 |
| H5 dark `photo` disappears faster than native | b | `settle_ms`, `response_pct`, `damping` | 1 | 3 |
| H6 `.bouncy` appears at SwiftUI's spring, where native runs faster | b | `t10_90_ms`, `settle_ms`, `response_pct`, `damping` | 7 | 12 |
| **Total** | | | **35** | **35** |

No failure is (c) or (e) once the one stalled event is repeated.

Crops are made from the runs' own video frames by `research/execution-2b1/crops/fix3_make_crops.py <out folder> <scratch folder>` (run from `packages/mobile`; it stages each case in a temporary folder, so the runs are not touched). Each tile is the tracked region with its time after the event's onset and its progress.

### H1: half-progress sharpness on dark `photo` (12), class (b)

Every dark-photo event fails `sharpness`, both events, every preset and mode: Flutter's half-way frame is blurrier than native's by 1.06–1.51 against a limit of 1.00. **No scanned k passes it**: on the dense scan the static gap is 1.47–1.64 at every k from 0.25 to 4. Part 2 wrote that k = 0.25 would pass it (0.82); that reading was the scan-grid artefact (re-audit P2A-1), and at k = 0.25 the dark-photo progress also misses native's per-backdrop lead by 0.159. The crop (`crops/fix3-h1-half-progress-sharpness.png`: dark-photo native 0.45 at +65 ms against Flutter 0.45 at +65 ms; light-photo 0.52 / 0.50) shows native's shapes unblurred at half progress and Flutter's blurred evenly. What keeps native sharp is not shown by the crop: native's blur may lag its tone and rim, or the rim and lens terms of rulings 13 and 14 may carry its half-way look. Both are hypotheses; the ramp sweep in `todo-2b1.md` tests them.

### H2: half-progress sharpness on light `photo` (6), class (a)

Normal `.snappy` disappear 1.005, `.bouncy` disappear 1.035 and appear 1.047; Reduce Motion `.snappy` disappear 1.096, `.bouncy` disappear 1.190 and appear 1.242, all against 1.000. The static gap is 1.21–1.22 for k up to 1.5, 1.14 at 2, 0.87 at 3 and 0.38 at 4, and at k = 3 every light-photo event passed (the first results, 0.70 measured). A fitted value (k) sets it: the cost of k = 1 (one failure at k = 0.5, which shares the static gap of 1.22; the run-to-run spread of a value this close to its limit decides the rest).

### H3: a native capture that misses the disappear's start (2), class (d)

Normal default light-stripes disappear `response_pct` 130.0 > 61.8 and `damping` 0.95 > 0.42. Native's first changed frame came after a 30.0 ms gap already at progress 0.19 (the rule's threshold is over 30 ms), and its fitted spring is 0.10 s / 1.96, against 0.20–0.26 s for every other native disappear in both runs; Flutter's is 0.23 / 1.01. The response and damping deltas measure the capture, not the motion. The rule allows no repeat for a native artifact.

### H4: default and `.snappy` appears stiffer than native, every backdrop (27), class (a)

`response_pct` 15.8–45.3 % (limits 5.0–30.6), `damping` 0.10–0.40 (limits 0.05–0.24) and three `settle_ms` one or two frames over, on all four backdrops: Flutter's appear fits 0.32–0.49 s / 0.87–1.30 against native's 0.43–0.75 / 0.77–1.06. The moving-against-still table above shows why: at k = 1 Flutter's moving glass runs 0.06–0.10 of progress ahead of what its own static scan predicts at the same visibility, on every backdrop, while the static prediction tracks the spring and native (`crops/fix3-h4-light-stripes-appear.png`: native 0.10, 0.31, 0.49 at +48, +100, +152 ms against Flutter 0.20, 0.40, 0.58 at +48, +98, +148 ms). At k = 0.5 the lead was 0.02–0.08, largest on dark-photo, and the timing and spring failures sat on dark-photo (part 2's G3, 27); from k = 0.5 to k = 1 dark-photo's failures fell from 39 to 29 and the other backdrops' rose from 28 to 41. A fitted value, k, therefore decides where they fall: class (a). Whether any k removes them is not established, because the objective that fits k reads only the static scan and cannot see the moving lead; its deciding measure is a Done run per candidate k, or an objective scored on moving glass (`todo-2b1.md`). Why moving glass reads more progressed than still glass at the same visibility is not established either.

### H5: dark `photo` disappears faster than native (4), class (b)

Normal default dark-photo disappear `settle_ms` 25 > 17 (native 133 / 225 ms, Flutter 125 / 200); Reduce Motion `.snappy` dark-photo disappear `settle_ms` 25 > 17, `response_pct` 8.3 > 6.0 and `damping` 0.13 > 0.06 (native 125 / 200 ms and 0.24 / 0.97, Flutter 108 / 175 and 0.26 / 0.84). Dark-photo's own disappear exponent is 2.9 (default) and 2.55 (`.snappy`) against the pooled 3.1 and 2.75 (`fix3-fit.json` `exponent_cases`); a higher power takes the visibility down faster. One exponent per preset serves every backdrop, and the package cannot see its backdrop.

### H6: `.bouncy` appears at SwiftUI's spring, where native runs faster (19), class (b)

`.bouncy` appears in both modes: 10–90 % times 17–42 ms longer than native's (`t10_90_ms` failing in six), with `settle_ms`, `response_pct` and `damping` of the same events. Flutter's 10–90 % reads 158–175 ms, the SwiftUI `.bouncy` spring's own is 169 ms, and native's 133–158 ms: Flutter follows the spring, native runs faster than its spring (ruling 10). In these runs native's `.bouncy` overshoot also came out 0.06–0.70 points under the noise-take means the gains were fitted to, while Flutter realised its prediction (0.86–1.10), so Flutter overshoots native in 6 of the 8 pairs and settles later (the 2 % settle band amplifies it, A4).

### The failing values

| Group (class) | Mode | Preset | Case | Event | Measure | Value > limit | Native: 10–90 / settle, overshoot, spring, sharpness | Flutter: the same | Run |
|---|---|---|---|---|---|---|---|---|---|
| H1 (b) | normal | default | dark-photo | disappear | `sharpness` | 1.195 > 1.000 | 133 / 225 ms, 0.00 %, 0.26 / 0.97, -1.14 | 125 / 200 ms, 0.00 %, 0.27 / 0.90, -2.33 | `20261006-204707` |
| H1 (b) | normal | default | dark-photo | appear | `sharpness` | 1.376 > 1.000 | 292 / 492 ms, 0.00 %, 0.59 / 0.95, -1.00 | 267 / 458 ms, 0.00 %, 0.36 / 1.24, -2.37 | `20261006-204707` |
| H1 (b) | normal | .bouncy | dark-photo | disappear | `sharpness` | 1.454 > 1.000 | 117 / 167 ms, 0.00 %, 0.25 / 0.85, -1.18 | 100 / 158 ms, 0.00 %, 0.25 / 0.82, -2.63 | `20261006-204707` |
| H1 (b) | normal | .bouncy | dark-photo | appear | `sharpness` | 1.331 > 1.000 | 133 / 217 ms, 1.44 %, 0.43 / 0.73, -1.02 | 158 / 225 ms, 1.31 %, 0.32 / 0.90, -2.35 | `20261006-204707` |
| H1 (b) | normal | .snappy | dark-photo | disappear | `sharpness` | 1.512 > 1.000 | 117 / 192 ms, 0.00 %, 0.26 / 0.91, -1.08 | 117 / 175 ms, 0.01 %, 0.25 / 0.87, -2.59 | `20261006-211934` |
| H1 (b) | normal | .snappy | dark-photo | appear | `sharpness` | 1.181 > 1.000 | 200 / 325 ms, 0.30 %, 0.58 / 0.77, -1.10 | 192 / 308 ms, 0.07 %, 0.32 / 1.07, -2.28 | `20261006-204707` |
| H1 (b) | RM | default | dark-photo | disappear | `sharpness` | 1.062 > 1.000 | 133 / 225 ms, 0.00 %, 0.26 / 0.98, -1.24 | 125 / 200 ms, 0.00 %, 0.27 / 0.90, -2.31 | `20261006-210255` |
| H1 (b) | RM | default | dark-photo | appear | `sharpness` | 1.408 > 1.000 | 292 / 475 ms, 0.00 %, 0.50 / 1.06, -1.08 | 267 / 458 ms, 0.00 %, 0.34 / 1.30, -2.49 | `20261006-210255` |
| H1 (b) | RM | .bouncy | dark-photo | disappear | `sharpness` | 1.360 > 1.000 | 117 / 167 ms, 0.00 %, 0.25 / 0.85, -1.27 | 108 / 158 ms, 0.00 %, 0.25 / 0.82, -2.63 | `20261006-210255` |
| H1 (b) | RM | .bouncy | dark-photo | appear | `sharpness` | 1.460 > 1.000 | 133 / 350 ms, 2.83 %, 0.37 / 0.73, -0.97 | 167 / 225 ms, 1.95 %, 0.33 / 0.88, -2.43 | `20261006-210255` |
| H1 (b) | RM | .snappy | dark-photo | disappear | `sharpness` | 1.388 > 1.000 | 125 / 200 ms, 0.00 %, 0.24 / 0.97, -1.15 | 108 / 175 ms, 0.00 %, 0.26 / 0.84, -2.54 | `20261006-210255` |
| H1 (b) | RM | .snappy | dark-photo | appear | `sharpness` | 1.404 > 1.000 | 192 / 292 ms, 0.48 %, 0.43 / 0.87, -1.00 | 192 / 308 ms, 0.11 %, 0.32 / 1.08, -2.40 | `20261006-210255` |

| Group (class) | Mode | Preset | Case | Event | Measure | Value > limit | Native: 10–90 / settle, overshoot, spring, sharpness | Flutter: the same | Run |
|---|---|---|---|---|---|---|---|---|---|
| H2 (a) | normal | .bouncy | light-photo | disappear | `sharpness` | 1.035 > 1.000 | 100 / 158 ms, 0.01 %, 0.21 / 0.91, -1.58 | 108 / 167 ms, 0.02 %, 0.21 / 0.93, -2.61 | `20261006-204707` |
| H2 (a) | normal | .bouncy | light-photo | appear | `sharpness` | 1.047 > 1.000 | 158 / 392 ms, 2.41 %, 0.54 / 0.67, -1.51 | 175 / 425 ms, 2.75 %, 0.47 / 0.74, -2.56 | `20261006-204707` |
| H2 (a) | normal | .snappy | light-photo | disappear | `sharpness` | 1.005 > 1.000 | 117 / 183 ms, 0.00 %, 0.21 / 0.98, -1.61 | 117 / 183 ms, 0.00 %, 0.21 / 0.98, -2.61 | `20261006-204707` |
| H2 (a) | RM | .bouncy | light-photo | disappear | `sharpness` | 1.190 > 1.000 | 100 / 158 ms, 0.00 %, 0.21 / 0.92, -1.52 | 108 / 167 ms, 0.02 %, 0.21 / 0.92, -2.71 | `20261006-210255` |
| H2 (a) | RM | .bouncy | light-photo | appear | `sharpness` | 1.242 > 1.000 | 133 / 400 ms, 3.67 %, 0.48 / 0.66, -1.32 | 175 / 483 ms, 4.56 %, 0.48 / 0.71, -2.56 | `20261006-210255` |
| H2 (a) | RM | .snappy | light-photo | disappear | `sharpness` | 1.096 > 1.000 | 117 / 183 ms, 0.00 %, 0.22 / 0.95, -1.50 | 117 / 183 ms, 0.01 %, 0.21 / 0.98, -2.59 | `20261006-210255` |

| Group (class) | Mode | Preset | Case | Event | Measure | Value > limit | Native: 10–90 / settle, overshoot, spring, sharpness | Flutter: the same | Run |
|---|---|---|---|---|---|---|---|---|---|
| H3 (d) | normal | default | light-stripes | disappear | `response_pct` | 130.000 > 61.765 | 125 / 200 ms, 0.00 %, 0.10 / 1.96, -0.01 | 133 / 217 ms, 0.01 %, 0.23 / 1.01, -0.22 | `20261006-204707` |
| H3 (d) | normal | default | light-stripes | disappear | `damping` | 0.950 > 0.420 | 125 / 200 ms, 0.00 %, 0.10 / 1.96, -0.01 | 133 / 217 ms, 0.01 %, 0.23 / 1.01, -0.22 | `20261006-204707` |

| Group (class) | Mode | Preset | Case | Event | Measure | Value > limit | Native: 10–90 / settle, overshoot, spring, sharpness | Flutter: the same | Run |
|---|---|---|---|---|---|---|---|---|---|
| H4 (a) | normal | default | dark-photo | appear | `settle_ms` | 33.333 > 25.000 | 292 / 492 ms, 0.00 %, 0.59 / 0.95, -1.00 | 267 / 458 ms, 0.00 %, 0.36 / 1.24, -2.37 | `20261006-204707` |
| H4 (a) | normal | default | dark-photo | appear | `response_pct` | 38.983 > 30.612 | 292 / 492 ms, 0.00 %, 0.59 / 0.95, -1.00 | 267 / 458 ms, 0.00 %, 0.36 / 1.24, -2.37 | `20261006-204707` |
| H4 (a) | normal | default | dark-photo | appear | `damping` | 0.290 > 0.240 | 292 / 492 ms, 0.00 %, 0.59 / 0.95, -1.00 | 267 / 458 ms, 0.00 %, 0.36 / 1.24, -2.37 | `20261006-204707` |
| H4 (a) | normal | default | dark-stripes | appear | `response_pct` | 23.214 > 5.556 | 300 / 483 ms, 0.00 %, 0.56 / 1.00, 0.05 | 292 / 492 ms, 0.05 %, 0.43 / 1.17, -0.15 | `20261006-204707` |
| H4 (a) | normal | default | dark-stripes | appear | `damping` | 0.170 > 0.060 | 300 / 483 ms, 0.00 %, 0.56 / 1.00, 0.05 | 292 / 492 ms, 0.05 %, 0.43 / 1.17, -0.15 | `20261006-204707` |
| H4 (a) | normal | default | light-photo | appear | `settle_ms` | 33.333 > 17.000 | 292 / 542 ms, 0.00 %, 0.75 / 0.84, -1.54 | 300 / 508 ms, 0.00 %, 0.41 / 1.24, -2.41 | `20261006-204707` |
| H4 (a) | normal | default | light-photo | appear | `response_pct` | 45.333 > 5.000 | 292 / 542 ms, 0.00 %, 0.75 / 0.84, -1.54 | 300 / 508 ms, 0.00 %, 0.41 / 1.24, -2.41 | `20261006-204707` |
| H4 (a) | normal | default | light-photo | appear | `damping` | 0.400 > 0.050 | 292 / 542 ms, 0.00 %, 0.75 / 0.84, -1.54 | 300 / 508 ms, 0.00 %, 0.41 / 1.24, -2.41 | `20261006-204707` |
| H4 (a) | normal | default | light-stripes | appear | `response_pct` | 35.593 > 25.424 | 308 / 492 ms, 0.02 %, 0.59 / 0.99, -0.04 | 300 / 500 ms, 0.04 %, 0.38 / 1.30, -0.23 | `20261006-204707` |
| H4 (a) | normal | default | light-stripes | appear | `damping` | 0.310 > 0.120 | 308 / 492 ms, 0.02 %, 0.59 / 0.99, -0.04 | 300 / 500 ms, 0.04 %, 0.38 / 1.30, -0.23 | `20261006-204707` |
| H4 (a) | normal | .snappy | dark-photo | appear | `response_pct` | 44.828 > 20.588 | 200 / 325 ms, 0.30 %, 0.58 / 0.77, -1.10 | 192 / 308 ms, 0.07 %, 0.32 / 1.07, -2.28 | `20261006-204707` |
| H4 (a) | normal | .snappy | dark-photo | appear | `damping` | 0.300 > 0.105 | 200 / 325 ms, 0.30 %, 0.58 / 0.77, -1.10 | 192 / 308 ms, 0.07 %, 0.32 / 1.07, -2.28 | `20261006-204707` |
| H4 (a) | normal | .snappy | dark-stripes | appear | `settle_ms` | 41.667 > 37.500 | 192 / 292 ms, 0.28 %, 0.47 / 0.82, -0.02 | 217 / 333 ms, 0.13 %, 0.47 / 0.88, -0.16 | `20261006-204707` |
| H4 (a) | normal | .snappy | light-photo | appear | `damping` | 0.100 > 0.050 | 200 / 325 ms, 0.24 %, 0.58 / 0.77, -1.55 | 217 / 342 ms, 0.19 %, 0.49 / 0.87, -2.37 | `20261006-204707` |
| H4 (a) | normal | .snappy | light-stripes | appear | `response_pct` | 16.071 > 7.500 | 208 / 317 ms, 0.31 %, 0.56 / 0.78, -0.03 | 217 / 342 ms, 0.22 %, 0.47 / 0.89, -0.20 | `20261006-204707` |
| H4 (a) | normal | .snappy | light-stripes | appear | `damping` | 0.110 > 0.050 | 208 / 317 ms, 0.31 %, 0.56 / 0.78, -0.03 | 217 / 342 ms, 0.22 %, 0.47 / 0.89, -0.20 | `20261006-204707` |
| H4 (a) | RM | default | dark-photo | appear | `response_pct` | 32.000 > 6.250 | 292 / 475 ms, 0.00 %, 0.50 / 1.06, -1.08 | 267 / 458 ms, 0.00 %, 0.34 / 1.30, -2.49 | `20261006-210255` |
| H4 (a) | RM | default | dark-photo | appear | `damping` | 0.240 > 0.060 | 292 / 475 ms, 0.00 %, 0.50 / 1.06, -1.08 | 267 / 458 ms, 0.00 %, 0.34 / 1.30, -2.49 | `20261006-210255` |
| H4 (a) | RM | default | dark-stripes | appear | `response_pct` | 26.316 > 7.895 | 283 / 475 ms, 0.00 %, 0.57 / 0.95, 0.12 | 292 / 492 ms, 0.04 %, 0.42 / 1.20, -0.16 | `20261006-210255` |
| H4 (a) | RM | default | dark-stripes | appear | `damping` | 0.250 > 0.050 | 283 / 475 ms, 0.00 %, 0.57 / 0.95, 0.12 | 292 / 492 ms, 0.04 %, 0.42 / 1.20, -0.16 | `20261006-210255` |
| H4 (a) | RM | .snappy | dark-photo | appear | `damping` | 0.210 > 0.180 | 192 / 292 ms, 0.48 %, 0.43 / 0.87, -1.00 | 192 / 308 ms, 0.11 %, 0.32 / 1.08, -2.40 | `20261006-210255` |
| H4 (a) | RM | .snappy | dark-stripes | appear | `response_pct` | 25.000 > 8.654 | 200 / 292 ms, 0.34 %, 0.48 / 0.83, 0.08 | 208 / 317 ms, 0.20 %, 0.36 / 1.04, -0.17 | `20261006-210255` |
| H4 (a) | RM | .snappy | dark-stripes | appear | `damping` | 0.210 > 0.060 | 200 / 292 ms, 0.34 %, 0.48 / 0.83, 0.08 | 208 / 317 ms, 0.20 %, 0.36 / 1.04, -0.17 | `20261006-210255` |
| H4 (a) | RM | .snappy | light-photo | appear | `response_pct` | 15.789 > 10.169 | 208 / 317 ms, 0.37 %, 0.57 / 0.77, -1.46 | 217 / 342 ms, 0.39 %, 0.48 / 0.88, -2.37 | `20261006-210255` |
| H4 (a) | RM | .snappy | light-photo | appear | `damping` | 0.110 > 0.050 | 208 / 317 ms, 0.37 %, 0.57 / 0.77, -1.46 | 217 / 342 ms, 0.39 %, 0.48 / 0.88, -2.37 | `20261006-210255` |
| H4 (a) | RM | .snappy | light-stripes | appear | `response_pct` | 31.373 > 8.654 | 200 / 300 ms, 0.43 %, 0.51 / 0.80, 0.04 | 208 / 317 ms, 0.30 %, 0.35 / 1.07, -0.19 | `20261006-210255` |
| H4 (a) | RM | .snappy | light-stripes | appear | `damping` | 0.270 > 0.105 | 200 / 300 ms, 0.43 %, 0.51 / 0.80, 0.04 | 208 / 317 ms, 0.30 %, 0.35 / 1.07, -0.19 | `20261006-210255` |

| Group (class) | Mode | Preset | Case | Event | Measure | Value > limit | Native: 10–90 / settle, overshoot, spring, sharpness | Flutter: the same | Run |
|---|---|---|---|---|---|---|---|---|---|
| H5 (b) | normal | default | dark-photo | disappear | `settle_ms` | 25.000 > 17.000 | 133 / 225 ms, 0.00 %, 0.26 / 0.97, -1.14 | 125 / 200 ms, 0.00 %, 0.27 / 0.90, -2.33 | `20261006-204707` |
| H5 (b) | RM | .snappy | dark-photo | disappear | `settle_ms` | 25.000 > 17.000 | 125 / 200 ms, 0.00 %, 0.24 / 0.97, -1.15 | 108 / 175 ms, 0.00 %, 0.26 / 0.84, -2.54 | `20261006-210255` |
| H5 (b) | RM | .snappy | dark-photo | disappear | `response_pct` | 8.333 > 6.000 | 125 / 200 ms, 0.00 %, 0.24 / 0.97, -1.15 | 108 / 175 ms, 0.00 %, 0.26 / 0.84, -2.54 | `20261006-210255` |
| H5 (b) | RM | .snappy | dark-photo | disappear | `damping` | 0.130 > 0.060 | 125 / 200 ms, 0.00 %, 0.24 / 0.97, -1.15 | 108 / 175 ms, 0.00 %, 0.26 / 0.84, -2.54 | `20261006-210255` |

| Group (class) | Mode | Preset | Case | Event | Measure | Value > limit | Native: 10–90 / settle, overshoot, spring, sharpness | Flutter: the same | Run |
|---|---|---|---|---|---|---|---|---|---|
| H6 (b) | normal | .bouncy | dark-photo | appear | `t10_90_ms` | 25.000 > 17.000 | 133 / 217 ms, 1.44 %, 0.43 / 0.73, -1.02 | 158 / 225 ms, 1.31 %, 0.32 / 0.90, -2.35 | `20261006-204707` |
| H6 (b) | normal | .bouncy | dark-photo | appear | `damping` | 0.170 > 0.060 | 133 / 217 ms, 1.44 %, 0.43 / 0.73, -1.02 | 158 / 225 ms, 1.31 %, 0.32 / 0.90, -2.35 | `20261006-204707` |
| H6 (b) | normal | .bouncy | dark-stripes | appear | `t10_90_ms` | 25.000 > 17.000 | 142 / 183 ms, 1.99 %, 0.38 / 0.73, 0.04 | 167 / 375 ms, 2.52 %, 0.38 / 0.82, -0.19 | `20261006-204707` |
| H6 (b) | normal | .bouncy | dark-stripes | appear | `damping` | 0.090 > 0.050 | 142 / 183 ms, 1.99 %, 0.38 / 0.73, 0.04 | 167 / 375 ms, 2.52 %, 0.38 / 0.82, -0.19 | `20261006-204707` |
| H6 (b) | normal | .bouncy | light-photo | appear | `settle_ms` | 33.333 > 25.000 | 158 / 392 ms, 2.41 %, 0.54 / 0.67, -1.51 | 175 / 425 ms, 2.75 %, 0.47 / 0.74, -2.56 | `20261006-204707` |
| H6 (b) | normal | .bouncy | light-photo | appear | `damping` | 0.070 > 0.060 | 158 / 392 ms, 2.41 %, 0.54 / 0.67, -1.51 | 175 / 425 ms, 2.75 %, 0.47 / 0.74, -2.56 | `20261006-204707` |
| H6 (b) | normal | .bouncy | light-stripes | appear | `damping` | 0.060 > 0.050 | 133 / 358 ms, 2.53 %, 0.47 / 0.68, -0.05 | 167 / 425 ms, 2.81 %, 0.47 / 0.74, -0.20 | `20261006-204707` |
| H6 (b) | RM | .bouncy | dark-photo | appear | `t10_90_ms` | 33.333 > 17.000 | 133 / 350 ms, 2.83 %, 0.37 / 0.73, -0.97 | 167 / 225 ms, 1.95 %, 0.33 / 0.88, -2.43 | `20261006-210255` |
| H6 (b) | RM | .bouncy | dark-photo | appear | `settle_ms` | 125.000 > 75.000 | 133 / 350 ms, 2.83 %, 0.37 / 0.73, -0.97 | 167 / 225 ms, 1.95 %, 0.33 / 0.88, -2.43 | `20261006-210255` |
| H6 (b) | RM | .bouncy | dark-photo | appear | `damping` | 0.150 > 0.135 | 133 / 350 ms, 2.83 %, 0.37 / 0.73, -0.97 | 167 / 225 ms, 1.95 %, 0.33 / 0.88, -2.43 | `20261006-210255` |
| H6 (b) | RM | .bouncy | dark-stripes | appear | `t10_90_ms` | 33.333 > 17.000 | 133 / 392 ms, 3.57 %, 0.41 / 0.68, 0.11 | 167 / 458 ms, 4.11 %, 0.47 / 0.72, -0.18 | `20261006-210255` |
| H6 (b) | RM | .bouncy | dark-stripes | appear | `settle_ms` | 66.667 > 17.000 | 133 / 392 ms, 3.57 %, 0.41 / 0.68, 0.11 | 167 / 458 ms, 4.11 %, 0.47 / 0.72, -0.18 | `20261006-210255` |
| H6 (b) | RM | .bouncy | dark-stripes | appear | `response_pct` | 14.634 > 7.500 | 133 / 392 ms, 3.57 %, 0.41 / 0.68, 0.11 | 167 / 458 ms, 4.11 %, 0.47 / 0.72, -0.18 | `20261006-210255` |
| H6 (b) | RM | .bouncy | light-photo | appear | `t10_90_ms` | 41.667 > 37.500 | 133 / 400 ms, 3.67 %, 0.48 / 0.66, -1.32 | 175 / 483 ms, 4.56 %, 0.48 / 0.71, -2.56 | `20261006-210255` |
| H6 (b) | RM | .bouncy | light-photo | appear | `settle_ms` | 83.333 > 50.000 | 133 / 400 ms, 3.67 %, 0.48 / 0.66, -1.32 | 175 / 483 ms, 4.56 %, 0.48 / 0.71, -2.56 | `20261006-210255` |
| H6 (b) | RM | .bouncy | light-stripes | appear | `t10_90_ms` | 33.333 > 17.000 | 133 / 400 ms, 3.67 %, 0.47 / 0.67, 0.04 | 167 / 458 ms, 3.98 %, 0.39 / 0.79, -0.22 | `20261006-210255` |
| H6 (b) | RM | .bouncy | light-stripes | appear | `settle_ms` | 58.333 > 17.000 | 133 / 400 ms, 3.67 %, 0.47 / 0.67, 0.04 | 167 / 458 ms, 3.98 %, 0.39 / 0.79, -0.22 | `20261006-210255` |
| H6 (b) | RM | .bouncy | light-stripes | appear | `response_pct` | 17.021 > 9.783 | 133 / 400 ms, 3.67 %, 0.47 / 0.67, 0.04 | 167 / 458 ms, 3.98 %, 0.39 / 0.79, -0.22 | `20261006-210255` |
| H6 (b) | RM | .bouncy | light-stripes | appear | `damping` | 0.120 > 0.050 | 133 / 400 ms, 3.67 %, 0.47 / 0.67, 0.04 | 167 / 458 ms, 3.98 %, 0.39 / 0.79, -0.22 | `20261006-210255` |

## Not judged, reported

### Touch-to-response delay

Onset minus touch-up, native / Flutter, ms (each pair's `shapes.pairs.<pair>.delay`, k = 1 runs; normal `.snappy` dark-photo disappear from the repeat). Disappear is step 1, appear step 3.

| Preset | Case | Normal disappear | Normal appear | Reduce Motion disappear | Reduce Motion appear |
|---|---|---|---|---|---|
| default | dark-photo | 47 / 17 | 80 / 32 | 45 / 17 | 97 / 32 |
| default | dark-stripes | 45 / 17 | 97 / 28 | 45 / 17 | 112 / 30 |
| default | light-photo | 45 / 18 | 78 / 32 | 47 / 17 | 95 / 15 |
| default | light-stripes | 30 / 17 | 98 / 32 | 27 / 17 | 97 / 17 |
| `.snappy` | dark-photo | 43 / 17 | 77 / 32 | 47 / 17 | 110 / 33 |
| `.snappy` | dark-stripes | 45 / 17 | 113 / 18 | 42 / 17 | 112 / 30 |
| `.snappy` | light-photo | 47 / 17 | 88 / 13 | 45 / 17 | 95 / 17 |
| `.snappy` | light-stripes | 45 / 17 | 95 / 17 | 45 / 17 | 110 / 32 |
| `.bouncy` | dark-photo | 45 / 17 | 80 / 28 | 43 / 17 | 112 / 28 |
| `.bouncy` | dark-stripes | 30 / 17 | 113 / 28 | 45 / 17 | 113 / 17 |
| `.bouncy` | light-photo | 47 / 17 | 63 / 17 | 28 / 17 | 95 / 17 |
| `.bouncy` | light-stripes | 48 / 17 | 95 / 13 | 45 / 17 | 98 / 30 |

Native starts to disappear 30–48 ms (normal) and 27–47 ms (Reduce Motion) after the tap, and to appear 63–113 ms and 95–113 ms after it; the package within 13–33 ms in every pair. Class: native latency that the package does not copy (ruling 33); project 5 re-checks it on a device.

### Frame gaps and first frames

Inside events: Flutter's one 26.7 ms gap (repeated, above); none in native. No Flutter first changed frame is more than 0.05 of the travel ahead of native's (default light-photo appear, and Reduce Motion `.snappy` light-stripes appear). Flutter's first changed frame came after a gap over 25 ms in eight appears (28–32 ms, at progress 0.05–0.06 against native's 0.00–0.04): the variable-rate recorder's idle gap before an event, since the first frame is not behind.

### Rim depth

`rim_check.py fitvis/fix3-20261006-192018/table/ramp1.0 <run>` (`research/execution-2b1/fix3-rim-normal.txt`, `fix3-rim-rm.txt`), depth of the lit band under the top edge in points: Flutter 0.67–1.0 pt at visibility 0.1–1.0 in every case, within one pixel (⅓ pt) of its depth at 1 from 0.3 up (dark-photo and light-stripes 0.67 at 0.3 against 1.0 at 1; light-photo 0.67 throughout; above full 1.0–1.33): `uFullThickness` reaches the geometry pass (finding 28). Native at rest 1.0–1.67 pt; mid-transition, normal: dark-photo and light-photo 14.5 / 24 / 24 pt at progress 0.3 / 0.5 / 0.7, the stripes cases 5.0–5.33 (in part 2's normal run light-photo read 5.0); Reduce Motion 5.0–5.33 throughout. Ruling 14's open item.

### Not re-run after the first results

The cold first transition (`cold/20261006-002600`, at `58ab57e0c`, k = 3): the launch's first disappear started at progress 0.38 and read 83 against native's 133 ms, the appear 300 against 275 ms (ruling 24; the debug JIT's first frame). The ghosts (`ghost/20261006-014735`, `-014805`): the label in place and fading with the glass in every frame, no blink, in the container and in the `Overlay`. Neither depends on the materialize table; both are carried as measured.

## Done item 5: still glass against 2A

Built by `lab.py build example` and `lab.py build operator` at `01b59747d`, recorded 16:54–18:02 (load 43–128 from Spotlight indexing; still pixels do not depend on it). `still_check.py <2A run> <new run>` per scene; outputs in `research/execution-2b1/fix2-still-<scene>.txt`.

| Scene | 2A run | New run | Triples | Flutter frames byte-identical | missing | worse |
|---|---|---|---|---|---|---|
| `material.regular` | `20261002-200447` | `20261006-165449` | 20 | 20 | 0 | 0 |
| `material.clear` | `20261002-201611` | `20261006-170542` | 8 | 8 | 0 | 0 |
| `material.tinted` | `20261002-151504` | `20261006-171006` | 12 | 12 | 0 | 0 |
| `material.edge` | `20261002-202042` | `20261006-171635` | 12 | **12** | 0 | 0 |
| Reduce Transparency | `20261002-202731` | `20261006-172307` | 20 | 20 | 0 | 0 |
| Increase Contrast | `20261002-203837` | `20261006-173358` | 20 | 20 | 0 | 0 |
| `tabbar.rest` (Operator) | `20261002-205000` | `20261006-174454` | 16 | 16 | 0 | 0 |
| `button.press` (Operator) | `20261002-205855` | `20261006-175336` | 4 | **0** | 0 | 0 |
| `navbar.inline` (Operator) | `20261002-210140` | `20261006-175623` | 12 | 12 | 0 | 0 |

Every report count equals the 2A run's (`results-2a1.md`, "after"). Native frames differ from the 2A session's by 0 levels (102 of 124 frames), 1 (8) or 2 (10), and by 229 on `button.press` (4), where native draws the black touch marker that 2A did not and the region leaves out (ruling 7).

**`material.edge`: fixed.** All 12 Flutter frames are byte-identical to 2A's again; the first results' rim snap is gone (A9, Deviations 6).

**`button.press`: the same fix, the other way: now geometrically correct, where 2A was snapped** (ruling P2-10, its evidence from the re-audit, P2A-3). Its four Flutter frames differ from 2A's only on the rims of the two buttons (maximum channel difference 133 dark, 110 light; label, interior and backdrop identical; `crops/fix2-still-button-press-dark-stripes-2A-new-diff.png`, 2A | new | difference × 4, and `reaudit2-button/button-press-{dark,light}-stripes-rims-2A-new-diff.png` at 10×). The scene is `LabCentered`: a centred column of two 44 pt `GlassButton.label`s 69 pt apart, so every rim is mirror-symmetric about x = 201 pt = 603.0 px, and the vertical centres are 1183.5 and 1522.5 px. Rim centres by gradient centroids over 13 rows for the sides and 80 columns for the top and bottom (`reaudit2-button/centre.py`, re-run here, `centre.txt`):

| Frame | Glass button x / y (px) | Prominent button x / y (px) |
|---|---|---|
| 2A dark-stripes | 603.32 / 1184.00 | 602.67 / 1522.89 |
| new dark-stripes | 603.11 / 1183.49 | 603.00 / 1522.50 |
| 2A light-stripes | 603.17 / 1183.69 | 602.61 / 1522.58 |
| new light-stripes | 602.98 / 1183.51 | 603.00 / 1522.52 |

The new rims sit on their layout positions within 0.11 px in x and 0.02 px in y; 2A's were off by 0.17–0.39 px in x and up to 0.50 px in y, and 2A's top and bottom rims carry duplicated rows (rows 1118 and 1119, and 1248 and 1249, identical at x = 500), the signature of nearest sampling at a half-pixel phase that part 1's A9 fix removes. The first results' run (`20261006-013200`, before the fix) is byte-identical to 2A, so 2A's own reference frames carried the snap (ROADMAP gotcha 48). The change is not a uniform translation: per edge it runs from −0.05 to 0.84 px, because of 2A's duplicated rows, and the prominent button moved 0.32–0.46 px in x, the other way. Which commit made it was not bisected; A9 is the cause the duplicated-row signature points to, and the verdict holds either way. The static measures: dark-stripes `mad` 7.13 → 7.07, `rim_rms` 10.69 → 10.38, `luminance` 0.0164 → 0.0201 (0.004 further from native, against a limit of 3.0); light-stripes `mad` 8.07 → 7.99, `rim_rms` 8.54 → 8.30, `luminance` 0.86 → 0.84; `bbox_pt` unchanged; none changed pass or fail. Done item 5 passes on its definition, and the new frames are an improvement, not a regression.

## Deviations from the plan and rulings

1. **The first noise session was stale, not loaded** (A10). The first results blamed machine load for the slow first noise session and the long native presses. The audit showed the drift tracks the session: that session ran on a simulator boot from before the 2026-10-04 reboot, on a Mac then up nine days, and read appear `t10_90` about 12 ms slower and presses of 3.26 s (median); the loaded second session agreed with 2A and with the low-load Step 5. Part 2 re-recorded it after a fresh boot, with N1, N2, N5 and N6. A boot goes stale within hours too: boot B held a 1.0 s press for 2.0–2.4 s after seven and a half hours of lab use, so the fix round rebooted before recording (ruling P2-11). Load did produce capture holes, which the outlier rule excludes.
2. **Outlier exclusions** (Task 9, part 2, the fix round). Task 9 excluded four materialize takes (capture holes, `task-9-outliers.md`) and kept 24 flagged press and interactive takes. Part 2 and the fix round applied the rule and the touch gate to every take, uniformly, and to the native references, and excluded 20 takes and two N1 cases (Done items 2 and 3). Ten cases now hold takes from three simulator boots (Task 9's four replaced cases, and six whose session 2 lost one take), and every case from at least two (ruling P2-3).
3. **`noise.json` is recomputed in canonical take order** (A6), and every moved limit is disclosed (A7). The audit found that Task 9's replacement takes had loosened eight item-4 limits in the four replaced cases, undisclosed; the disclosure now lists every moved limit of part 2 and of the fix round, and names the one take that sets three limits of one case (ruling P2-6: kept for 2B.1, never for a later plan's floors).
4. **The fit** (A1, A4, A8, C3, C4, P1-6, P2A-1). k is chosen on the joint objective over a ramp scan with levels below visibility 0.2, and written with its trade-off; the gains are fitted on the overshoot peak, per case and per appearance as well as pooled; the write guard refuses unfitted, dropped and edge values, and the objective reads no sharpness against the glass-absent shot. Part 2's k = 0.5 (ruling P2-9) was the scan-grid artefact and is overturned; k = 1 is written. Part 2's first fit attempt lost its output to a relative `--out` (the driver resolves it against `/`, as with `repeat --into`, ROADMAP gotcha 43). One N6 case had a squeezed capture and was re-recorded before part 2's last fit (ruling P2-7).
5. **Stall repeats** (A5). The first results substituted repeats per case: 129 normal and 135 Reduce Motion; per event, as the audit's rule requires, Reduce Motion reads 134. Part 2 and the fix round substitute per event only (part 2: `.bouncy` dark-photo disappear; the fix round: `.snappy` dark-photo disappear).
6. **`material.edge`** (A9). Part 1's fix (`f07236cff`) rasterizes the cached geometry matte at the sub-pixel phase it is drawn at, keeping the cache. All 12 `material.edge` Flutter frames are byte-identical to 2A's again (`20261006-171635`): the first results' rim snap (0.24 px by the first results' fit, 0.16 px by the audit's) is gone. It was a renderer defect, latent in the fork's geometry cache since before 2A and exposed by ruling 30, not a model limitation as the first results classed it. The same fix moves `button.press`'s rims onto their layout positions, where 2A itself was snapped (Done item 5). Its per-frame cost while glass slides is not measured (re-review P1-4, `todo-2b1.md`).
7. **Disk and the lost runs.** Part 2 stopped once at 36 GB free (the main session's 40 GB line) after Done item 4, and continued on the main session's 20 GB line; the fix round started at 28 GB and ended at 19 GB, under the 20 GB line once the last Done item 4 runs had been analysed (each run pair is about 7 GB); no recording or run followed. The noise analysis writes its frame caches into every take (`noise-2b1/takes` 42 GB, `stale-session1` 26 GB, `excluded` 3.6 GB). Stopping the first still attempt with `pkill` (SIGTERM) skipped the lab's cleanup and left `simctl io recordVideo` running, so the next five still runs failed in every case with `recordVideo did not start`; the recorder was stopped with SIGINT and all nine scenes recorded again (ROADMAP gotcha 50). A mistyped `lab.py report` on the runs folder itself wrote an empty `runs/report.html` and `runs/report_assets/`. Nothing was deleted; the failed runs are listed under Run folders.
8. **Tests beyond the plan.** Harness 175 → 204 (part 1: C2, C3, C9, C19, A1, A4, A6; part 2: P1-6; the fix round: P2A-1); package 125 → 155 (part 1: C1, C5–C8, C10, C14, C15, C18, A4, A9; part 2: P1-3; P1-5 rewrote one assertion).

## Gates

At `1a340d4bb` plus this document change (no code since), with `--no-pub`:
- app (`packages/mobile`): `flutter analyze` "No issues found!", `flutter test` `+2146: All tests passed!`;
- package (`packages/ios_liquid_glass`): `flutter analyze` "No issues found!", `flutter test` `+155: All tests passed!`;
- example: `flutter analyze` "No issues found!", `flutter test` `+13: All tests passed!`;
- harness: `python3 -m unittest discover tool/glass_lab/harness/tests`, `Ran 204 tests`, OK.

`flutter test` prints the known SkSL error about `liquid_glass_geometry_blended` (ROADMAP gotcha 3). `xcrun simctl spawn 708879DD-8B2A-4547-863F-F49EE1474D8B defaults read com.apple.Accessibility ReduceMotionEnabled` prints `0`.

