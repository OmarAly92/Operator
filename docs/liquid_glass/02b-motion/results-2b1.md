# 2B.1 results

Date: 2026-10-06, after the review fix wave (parts 1 and 2). Branch `feat/ios-liquid-glass-2b1`. Motion measured at `36039801b` (the re-fitted motion table); still glass at `01b59747d` (documents only since); gates at the tip (below). Simulator: iPhone 17 Pro (iOS 27), UDID 708879DD-8B2A-4547-863F-F49EE1474D8B, freshly booted at 2026-10-06 08:52:11 (boot A) and again at 11:31:23 (boot B). Run folders are under `packages/mobile/build/glass_lab/runs/`, fits under `packages/mobile/build/glass_lab/fitvis/`. `ReduceMotionEnabled` and `EnhancedBackgroundContrastEnabled` read `0` after every run and after the gates. Saved tool outputs are committed under `research/execution-2b1/` (paths below are relative to this folder); every ruling cited as P2-n, Task n or by a review finding is a line of `research/execution-2b1/ledger.md`. The fit is `research/execution-2b1/fix2-fit.json`.

This file replaces the first results (measured at `58ab57e0c` with the blur ramp k = 3). The review audit (`review-2b1-audit.md`, A1–A10) and the code review (`review-2b1-code.md`) found that the slow first noise session came from a simulator that had not been rebooted for nine days, that k had been chosen on sharpness alone, that the `.bouncy` gain was fitted on the whole curve, and that several facts were wrong. Part 2 re-recorded, re-fitted and re-measured. The first results' numbers are kept where they are still the record (Done item 4 before, the cold probe, the ghosts), each marked with its commit.

**How the numbers were read.** Every motion number is a `motion.*` measure of a run's `result.json`, judged against max(fixed threshold, 1.5 × noise) with the per-case noise of `tool/glass_lab/noise.json` (recomputed in part 2, `644972ba7`). `done_table.py` counts them per case: the seven `progress.*` measures per event pair are the Done item 4 measures; the event and touch gates (`events.*`, `touches.*`) are counted apart. Every still number is the `static.ready` block; `still_check.py` compares `ready` and `settled`, case by case, against the 2A runs of `results-2a1.md`, read in place. Commands run from `packages/mobile`.

## The Done table

| Done item (spec §8, 2B.1) | Result | Evidence |
|---|---|---|
| 1 L1–L3, L5–L8 tested and reproducing known numbers | **Pass.** Disappear 117–133 ms and appear 275–292 ms (ruling 6's 120 Hz estimator; the two 275 ms appears are 10 ms under the spec's 285, inside their `t10_90_ms` noise). Not an alpha fade on `photo`; v13 +12.00 / +4.66; short glass +17.00 (58 pt circle) and +16.00 (138 × 53); `button.press` +16.00 in all six runs; menu 0.26–0.30 s / 0.74–0.81. The spike's 250 × 44 (+17.67) **reproduces on `photo`**: +17.00 to +17.33 pt in all 12 recordings of N2 and its noise takes. On `stripes` it reads +14.33, L1's blind band (below). | harness `Ran 201 tests` OK; `reproduce.py materialize\|press\|menu` byte-identical to `research/execution-2b1/task-6-reproduce.txt` (`fix2-reproduce.txt`); `fix2-press-sizes.txt` |
| 2 Noise floors for every 2B.1 scene and case | **Pass**: 15 scenes, 60 cases, five native takes each from two simulator boots, static `mad` 0.00 in every case. The stale first session was replaced by a session recorded after a fresh boot; 18 takes failing the outlier rule or the touch gate were excluded and replaced (below). Every limit that moved is disclosed. | run `noise-2b1`; `noise.json` at `644972ba7`; `research/execution-2b1/fix2-noise-disclosure.md`, `fix2-noise-cases.json` |
| 3 N1, N2, N5, N7 and N6 (materialize) recorded | **Pass**, N1, N2, N5 and N6 re-recorded after the fresh boot: press holds read 0.98–1.00 s for the scripted 1.0 s | N1 `20261006-085522`, N2 `20261006-085825`, N5 `20261006-091133`, N6 `20261006-091925` (its dark-photo-reduce-motion case from `20261006-144758`, ruling P2-7); N7 Task 8's `20261004-003527` (still scenes) |
| 4 Materialize passes under default, `.snappy`, `.bouncy` and Reduce Motion, per shape | **Partly failing.** Progress measures (passing / judged / expected): normal **136 / 168 / 168** (135 as first run), Reduce Motion **133 / 168 / 168** (no repeat). Event and touch gates **120 / 120**, `unpaired` 0. Before the fix wave (k = 3, the old floors): 129 and 134 with repeats substituted per event (130 and 133 as first run). The 67 failures are classed below: **39 (b), 28 (a)**. | runs `20261006-154138` (normal), `20261006-155725` (Reduce Motion), repeat `20261006-162523`; `fix2-done-table-{normal,rm,repeat}.txt` |
| 5 Still glass no worse than 2A | **Pass**: `missing: 0` and `worse: 0` in all nine scenes, Operator's three included; **120 of 124** Flutter frames byte-identical to 2A's, `material.edge`'s 12 now among them (the A9 fix). The four `button.press` Flutter frames differ only at the two buttons' rims, moved 0.19–0.26 px by the same fix's phase-correct raster; no static measure changed pass or fail, and each that moved moved toward native (by at most 0.31). | nine runs `20261006-165449` … `20261006-175623`; `still_check.py`, `research/execution-2b1/fix2-still-<scene>.txt` |
| 6 Gates | **Pass**: app `+2146`, package `+155`, example `+13`, all three `flutter analyze` clean; harness 201 OK | below |

### Done item 4 per scene and appearance

Progress measures passing / judged / expected, with the one repeat substituted for its stalled event only (A5). Each line is two cases (`photo` and `stripes`) of two events each. Gates are 10 / 10 on every line.

| Scene | Appearance | Normal | Reduce Motion |
|---|---|---|---|
| `material.materialize` (default) | dark | 17 / 28 / 28 | 18 / 28 / 28 |
| `material.materialize` (default) | light | 26 / 28 / 28 | 28 / 28 / 28 |
| `material.materialize.snappy` | dark | 21 / 28 / 28 | 19 / 28 / 28 |
| `material.materialize.snappy` | light | 27 / 28 / 28 | 24 / 28 / 28 |
| `material.materialize.bouncy` | dark | 19 / 28 / 28 | 18 / 28 / 28 |
| `material.materialize.bouncy` | light | 26 / 28 / 28 | 26 / 28 / 28 |
| **Total** | | **136 / 168 / 168** | **133 / 168 / 168** |

Failing pairs by measure, out of 24 per run (normal / Reduce Motion): `t10_90_ms` 2 / 5, `settle_ms` 7 / 8, `overshoot_pct` 0 / 0, `response_pct` 11 / 7, `damping` 6 / 8, `rms` 0 / 0, `sharpness` 6 / 7.

**Repeats.** One Flutter gap over 25 ms sat inside an event: normal `.bouncy` dark-photo disappear, 40.0 ms right after a 403 ms idle gap, before the glass moved (`fix2-stall-events.txt`). That case was repeated alone (`run material.materialize.bouncy --appearance dark --backdrop photo`, `20261006-162523`, stall-free) and only its disappear substituted (A5's rule): 4 of 7 against 3 of 7; its appear was not stalled and is kept from the first run. Native had one 25.0 ms gap, Reduce Motion default light-stripes appear at +0.45 s, in the tail (progress 0.931 to 0.932); kept.

### Before and after

| | Normal | Reduce Motion |
|---|---|---|
| Before (`58ab57e0c`, k = 3, `noise.json` at `fd30f969d`), first run | 130 | 133 |
| Before, repeats substituted per event (A5) | **129** | **134** |
| After: the new runs judged on the old floors | 140 | 135 |
| After: the new runs on the new floors, first run | 135 | 133 |
| After, repeat substituted per event | **136** | **133** |

Two things moved the count, and they pull in opposite directions:
- **The new k and gains** (k = 3 to 0.5, peak-fitted gains): +10 normal and +2 Reduce Motion on the old floors. They move failures from the light backdrops to dark `photo`: light failures 31 → 11 (light-photo 15 → 6, light-stripes 16 → 5), dark-photo 27 → 39 (sharpness 12 → 12, the rest 15 → 27), dark-stripes 14 → 17 (the before list is the audit's section 2, the after list `fix2-failing-measures.json`).
- **The new floors**: −5 normal, −2 Reduce Motion. On these runs they fail 12 values that the old floors passed and pass 5 that they failed (ledger, step 7). The floors moved because the stale session's slow takes, the excluded press takes and three Task 9 replacements no longer set them, and the new session brought its own spread (disclosure below).

The runs themselves also differ from the old ones by the Flutter debug build's run-to-run spread, which no floor carries (A5).

## Run folders

| Step | Command | Run folder | Report counts |
|---|---|---|---|
| Task 5 touch check | `run material.materialize --appearance dark --backdrop photo` | `20261003-234148` | marker check only |
| Task 8 (native, superseded) | N5, N6, N1, N2, N7 | `20261004-000223`, `-001040`, `-001855`, `-002204`, `-003527` | recorded before the 2026-10-04 reboot; N7 is still the reference |
| Part 2 stage 1 | `run material.interactive --app native` (N1) | `20261006-085522` | 4 cases, native only |
| Part 2 stage 1 | `run material.press --app native` (N2) | `20261006-085825` | 20 cases, native only |
| Part 2 stage 1 | `run material.materialize --app native` (N5) | `20261006-091133` | 12 cases, native only |
| Part 2 stage 1 | the same, `--a11y reduce-motion` (N6) | `20261006-091925` | 12 cases; dark-photo-reduce-motion re-recorded in `20261006-144758` and copied in (`RERECORDED.txt`) |
| Task 9 + part 2 | noise takes: session 1 re-recorded in boot A (three per case), session 2 kept or replaced in boot B (two per case) | `noise-2b1` (`takes/`, `stale-session1/`, `excluded/`) | 60 cases, static `mad` 0.00 |
| Part 2 step 6 | `fitvis 20261006-091133 20261006-091925 noise-2b1 --ramps 0.25,0.5,1,1.5,2,3,4 --write` | `fitvis/fix2-20261006-115226` | `fix2-fit.json` |
| Step 5 | `run material.materialize` | `20261006-154138` | pass 1, fail 11 |
| Step 5 | `run material.materialize --a11y reduce-motion` | `20261006-155725` | pass 3, fail 9 |
| Step 5 repeat | `run material.materialize.bouncy --appearance dark --backdrop photo` | `20261006-162523` | pass 0, fail 1 |
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

`noise.json` holds `{scene: {case: {measure: noise}}}` for every 2B.1 scene. Values per scene: `material.materialize` 503, `.snappy` 496, `.bouncy` 497, `material.interactive` 318, `material.press.138x53` 187, `.250x44` 136, `.300x120` 147, `.360x200` 91, `.circle58` 209, the six `material.spacing.*` scenes 32–36 each (unchanged). `material.regular`, `tabbar.*` and `menu.bar` are byte-identical to before.

**The takes.** Five per case:
- **Session 1, three takes** (slots 0–2), recorded after the fresh boot A (2026-10-06 09:27–11:26, load 3.9–8.9 at the start of every motion scene). The stale session 1 (2026-10-04, a simulator boot from before the 04:02 reboot, on a Mac then up nine days) is moved, not deleted, to `noise-2b1/stale-session1/` with every pair folder that used it (A10).
- **Session 2, two takes** (slots 3–4): kept from the 2026-10-04 04:02 boot (and Task 9's four replacements of 2026-10-05), or replaced after boot B (2026-10-06 11:31) where a take was excluded.

**The outlier criteria**, applied to every take of both sessions (A10, brief step 3): `task9scan/report.py`'s rule (an event whose first or second frame gap is over 30 ms, followed by at least two gaps under 5 ms in the next ten), run with the branch harness (its rows for the 92 session-2 takes that did not change are identical to `task-9-scan.md`), and the touch gate the analysis judges (the touch count and a press as long as the script holds it), which `task-9-outliers.md` names next to the rule. 18 takes were excluded and replaced; the list with each take's numbers is in `noise-2b1/excluded/README.txt` and in the ledger:
- 12 old session-2 press and interactive takes that Task 9 had kept (the rule flags them; 2B.1 judges no press measure, but these floors feed 2B.3);
- 5 new session-1 takes: 3 by the rule (`press.138x53` dark-stripes 0, `press.circle58` dark-stripes 0 and 1), 2 by the touch gate (`press.300x120` dark-stripes 1, a 0.12 s press with no event owned by its step; `.bouncy` dark-stripes-reduce-motion 2, one touch of two and no event owned by a step);
- 1 replacement in boot B (`material.interactive` dark-photo 4, first attempt).

**The press-hold check** (A10): every press in the new takes (boots A and B) and in N1 and N2 reads 0.977–1.030 s for the scripted 1.0 s (median 0.990), except one 1.225 s window whose release frame came after a 0.61 s recorder gap; press-drags 1.30–1.36 s. The stale session read 3.26 s (median) and Task 8's N1 and N2 1.54–2.87 s. The fresh boot alone restored the scripted hold.

**Recomputed** by `lab.case_noise` in its canonical take order (A6), for all 60 cases.

**Every limit that moved** (A7): `research/execution-2b1/fix2-noise-disclosure.md` lists all 1089, each with its scene, case, measure, old and new noise and limit. Of the judged item-4 limits, **59 moved tighter and 54 looser**; of the others, 561 tighter and 415 looser. The largest judged loosenings, with their pairs:
- **default `light-photo-reduce-motion` disappear: `response_pct` 21.4 → 335.7 %, `settle_ms` 17 → 150 ms, `damping` 0.165 → 0.57.** One take sets all three: every pair with new session-1 take 2 reads 196–224 %, and no other pair passes 8.7 %. Its onset is read 98 ms before the glass moves (after a 378 ms idle gap, the first changed frame and the next still read progress 0.981; from there its descent matches take 1 frame for frame). It passes the outlier rule and the touch gate, so it stays (ruling P2-6): writing a new rule after seeing it is what the audit faulted. **That case passes 14 of 14 with or without the take**: judged on the floors of the other four takes, its limits for those measures read 13.0 %, 17 ms and 0.105, and the Reduce Motion run's values are 9.1 %, 16.7 ms and 0.04. The audit judges the ruling.
- `.bouncy` dark-stripes appear `settle_ms` 75 → 225 ms: pairs with new take 2 read 108–150 ms, the others 0–42; take 2's appear differs from take 1's by 0.02–0.03 of progress, enough to move a 2 % settle band on a 5 % overshoot. Native variation.
- `.snappy` dark-photo-reduce-motion appear `response_pct` 27.9 → 80.2 %: one cross-session pair (3-2); the rest 0–29.4.
- default light-stripes disappear `response_pct` 39.1 → 61.8 %: one cross-session pair (Task 9's replacement against new take 0).

## Done item 3: native references

N1, N2, N5 and N6 were re-recorded after the fresh boot (ruling P2-4: Task 8's came from the stale boot). N5 and N6 per case (10–90 % in ms; appear overshoot):

| Preset | Normal: disappear / appear | Reduce Motion: disappear / appear |
|---|---|---|
| default | 125–142 / 275–300 | 125–142 / 283–300 |
| `.snappy` | 117 / 200–225, overshoot 0.25–0.32 % | 117 / 200–208, 0.29–0.50 % |
| `.bouncy` | 100–108 / 133–158, overshoot 1.48–2.48 % | 100–108 / 133, 3.42–3.78 % |

- **N1** `material.interactive`: +12.00 pt width in all four cases, rest 251.33–252.0 × 88.67–89.67 pt; press 0.978–0.996 s, press-drag 1.317–1.335 s.
- **N2**: per size above (Done item 1, the size law).
- **N7** spacing (Task 8, `20261004-003527`): the default container joins at gaps 0 and 4 pt (necks 25.33 and 4.00 pt); `spacing: 40` joins at 0–20 pt (necks 50.67 … 2.00) (ruling 23).

## The fit (part 2, step 6)

`lab.py fitvis 20261006-091133 20261006-091925 noise-2b1 --ramps 0.25,0.5,1,1.5,2,3,4 --out <absolute> --write` (`fitvis/fix2-20261006-115226`). The write guard passed with no override (`write_problems` empty, `overrides.used` empty); `ios27_motion.dart` is byte-identical to `fitvis.table_source` of `fix2-fit.json`.

**The blur ramp k, on the joint objective (A1).** Sharpness RMS at matched progress / 1.0 plus per-backdrop progress deviation RMS / 0.05, over the four backdrops, against native's deviation from its own backdrop mean at the same point of the transition. Static scan values; "gap" is |Flutter − native| half-progress sharpness; a deviation is a backdrop's progress at the visibility where the backdrops' mean reaches 0.5, minus that mean:

| k | Sharpness RMS | Deviation RMS | Objective | Half-progress sharpness gap, dark-photo / light-photo (limit 1.0) | dark-photo deviation (native +0.038) | dark-stripes (native +0.092) | light-photo (native −0.063) | light-stripes (native −0.067) |
|---|---|---|---|---|---|---|---|---|
| 0.25 | 0.7852 | 0.0868 | 2.5217 | 0.82 / 1.21 | +0.197 | −0.031 | −0.094 | −0.073 |
| **0.5 (chosen)** | 0.9313 | 0.0688 | **2.3064** | 1.63 / 1.22 | +0.131 | −0.019 | −0.065 | −0.047 |
| 1.0 | 1.1387 | 0.0587 | 2.3122 | 1.62 / 1.22 | +0.048 | −0.005 | −0.029 | −0.013 |
| 1.5 | 1.0378 | 0.0679 | 2.3962 | 1.62 / 1.21 | −0.012 | +0.004 | −0.003 | +0.010 |
| 2.0 | 0.9173 | 0.0782 | 2.4819 | 1.57 / 1.14 | −0.044 | +0.010 | +0.012 | +0.022 |
| 3.0 | 0.8403 | 0.0969 | 2.7787 | 1.55 / 0.87 | −0.102 | +0.018 | +0.039 | +0.045 |
| 4.0 | 0.9688 | 0.1081 | 3.1298 | 1.47 / 0.38 | −0.133 | +0.023 | +0.053 | +0.056 |

The first scan (0.5–4) chose 0.5 on its edge and the guard refused it; the scan was extended to 0.25, which scored worse, so 0.5 is interior. The objective is flat between 0.5 and 1 (2.306 against 2.312). k = 0.5 matches native's per-backdrop progress on the light backdrops (within 0.02) and puts dark-photo 0.093 ahead of native; k = 1 matches dark-photo (within 0.01) and leaves the light backdrops 0.03–0.05 behind native. No k matches dark-stripes (native +0.092; Flutter −0.031 to +0.023 at every k). A k below 1 means the blur radius grows above its full value as glass fades (`atVisibility` scales blur by visibility^(k − 1)), so the visible blur ramps as visibility^0.5 and Flutter's half-way frame is blurrier than at rest; the crops below show it.

**Exponents and gains.**

| Preset | Disappear exponent (per take; per case) | Appear gain, normal (per case dark-photo, dark-stripes, light-photo, light-stripes; per appearance dark / light) | Appear gain, Reduce Motion (the same) |
|---|---|---|---|
| default | 3.1 (3.05–3.2; 2.45–3.65) | inert (the spring does not overshoot) | inert |
| `.snappy` | 2.75 (2.65–2.75; 2.2–3.1) | **0.42** (0.88, 0.44, 0.36, 0.40; 0.52 / 0.38) | **0.60** (1.42, 0.54, 0.50, 0.56; 0.72 / 0.52) |
| `.bouncy` | 2.7 (2.7–2.85; 2.3–3.05) | **0.50** (0.72, 0.48, 0.42, 0.54; 0.52 / 0.48) | **0.78** (1.46, 0.80, 0.66, 0.78; 0.92 / 0.70) |

24 disappear curves per preset, none excluded; no exponent or gain on a grid edge or the floor, per case included. The gains are fitted on the overshoot peak: native's mean appear overshoot per case against the overshoot Flutter's own static scan shows at the visibility the package draws, through the table extended above full visibility (`ios27VisibilityAboveFull` = 1.0698 … 1.4291 for progress 1.05 … 1.30) (A4, A8, C4). `.snappy`'s gain is now 0.42, not the floor: native's `.snappy` overshoots 0.28–0.48 % and the peak fit sees it (A8).

**Pooled, not per appearance** (ruling P2-8). The per-case fits show the spread follows the backdrop, not the appearance: dark-photo needs 0.72–1.46 in every preset and mode because Flutter's dark-photo progress above full rises about half as fast as the others' (at the pooled `.bouncy` gain it realises 1.24 % where the others realise 2.48–2.88 %), while dark-stripes sits with the light cases (0.48 against 0.42–0.54). A dark gain chases dark-photo and pushes dark-stripes past native (Reduce Motion `.bouncy`: 4.59 % predicted against native 3.96 %; pooled 3.87 %); the appearances differ by 0.04 in normal `.bouncy` against a within-appearance case spread of 0.24 (dark) and 0.12 (light). The package cannot see its backdrop.

**Predicted against realised overshoot** (re-review P1-7; `fix2-overshoot-predicted-vs-measured.md`): the fit's static prediction of Flutter's appear overshoot against what the Done runs measure, with the run's native in brackets, in %.

| Preset, mode | dark-photo | dark-stripes | light-photo | light-stripes |
|---|---|---|---|---|
| `.bouncy` normal: predicted / measured (native) | 1.24 / 1.03 (1.45) | 2.48 / 2.78 (2.15) | 2.88 / 2.75 (2.47) | 2.64 / 2.75 (2.79) |
| `.bouncy` Reduce Motion | 1.94 / 1.61 (3.44) | 3.87 / 3.96 (3.76) | 4.49 / 4.62 (3.55) | 4.11 / 3.99 (3.70) |
| `.snappy` normal | 0.14 / 0.01 (0.28) | 0.29 / 0.18 (0.29) | 0.33 / 0.21 (0.24) | 0.30 / 0.07 (0.50) |
| `.snappy` Reduce Motion | 0.20 / 0.10 (0.45) | 0.41 / 0.19 (0.26) | 0.47 / 0.31 (0.43) | 0.43 / 0.24 (0.46) |

`.bouncy` realises 0.83–1.12 of the prediction, within the 20 % the re-review set; the 0.83 on dark-photo is the case the backdrop dependence already separates. `.snappy` realises 0.07–0.65: at 0.1–0.5 % the overshoot is at the progress measure's resolution, and the gain is not identified there (a fit defect, in `todo-2b1.md`). `overshoot_pct` passes in every pair; its limit is 2 %.

**The default spring** (A3): pooled native default fits 0.58 s / 0.97 here (RMS 0.0277; per case 0.58 / 0.97 dark-photo, 0.71 / 0.79 dark-stripes, 0.51 / 1.09 light-photo, 0.45 / 1.24 light-stripes). Every recording group read 0.57–0.59 s / 0.94–1.01, consistent with SwiftUI's 0.55 / 1.0 within the fit's resolution: the error surface is flat (0.57 and 0.58 differ by 0.00002 RMS, A3), so `pass: false` at 0.58 says nothing about native. The per-case springs are stable across every recording group, so the lab's progress measure gives systematically different springs per backdrop. The presets stay SwiftUI's springs (ruling 10).

## Every failing materialize measure, classed by cause

Classes: **(a)** tunable (a fitted value), **(b)** model limitation, **(c)** lab scene, **(d)** measurement artifact, **(e)** the debug build. No limit was loosened. Each class below is decided by evidence: the per-k table of the fit (above), the per-case fits, the crops, and per pair the native and Flutter features in `research/execution-2b1/fix2-failing-measures.json` (repeated in the tables at the end of this section).

| Group | Class | Measures | Normal | Reduce Motion |
|---|---|---|---|---|
| G1 half-progress sharpness on dark `photo` | b | `sharpness` | 6 | 6 |
| G2 half-progress sharpness on light `photo` | a | `sharpness` | 0 | 1 |
| G3 dark `photo` timing and spring | a | `t10_90_ms`, `settle_ms`, `response_pct`, `damping` | 14 | 13 |
| G4 spring shape on dark `stripes` | b | `response_pct`, `damping` | 6 | 6 |
| G5 spring shape on the light backdrops | b | `response_pct`, `damping` | 3 | 3 |
| G6 timing by one to three frames off dark `photo` | b | `t10_90_ms`, `settle_ms` | 3 | 6 |
| **Total** | | | **32** | **35** |

No failure is (c), (d) or (e) once the one stalled event is repeated.

Crops are made from the runs' own video frames by `research/execution-2b1/crops/fix2_make_crops.py <out folder> <scratch folder>` (run from `packages/mobile`; it stages each case in a temporary folder, so the runs are not touched). Each tile is the tracked region with its time after the event's onset and its progress.

### G1: half-progress sharpness on dark `photo` (12), class (b)

Every dark-photo event fails `sharpness`, both events, every preset and mode: Flutter's half-way frame is blurrier than native's by 1.13–1.41 against a limit of 1.00. **This is an evaluated trade-off on one fitted value, k.** On the static scan, k = 0.25 would pass dark-photo (gap 0.82) but fails light-photo (1.21), and it puts Flutter's dark-photo progress 0.197 ahead of its backdrop mean against native's 0.038: a 0.159 miss, more than three times the 0.05 progress tolerance and 1.7 times the chosen k's 0.093. Light-photo passes only at k ≥ 3 (0.87, 0.38), where dark-photo fails (1.55, 1.47). **No scanned k passes the two photo backdrops' half-progress sharpness together, and the one k that passes dark-photo fails its progress deviation, so it is class (b).** The joint objective chose 0.5. One caution: the measured gaps read 0.2–0.5 below the static ones (1.13–1.41 measured against 1.63 static at k = 0.5), so the static scan decides the class, not the exact margin.

The model cause: at matched progress native's shapes are already crisp, with a strong rim and the lens pulling the shapes' edges at the capsule ends; Flutter's are blurred evenly (`crops/fix2-g1-half-progress-sharpness.png`: dark-photo native 0.48 at +65 ms against Flutter 0.55 at +68 ms; light-photo 0.52 / 0.46). On dark `photo` the progress projection is mostly the blur itself (the audit's k-sweep), so any ramp only moves where half progress lands; what keeps native's half-way frame sharp is the rim and lens terms of rulings 13 and 14, which the model lacks.

### G2: half-progress sharpness on light `photo` (1), class (a)

Reduce Motion `.snappy` light-photo disappear, 1.127 > 1.000 (native −1.52, Flutter −2.65). At k = 3 every light-photo event passed (0.70 measured in the first results); at k = 0.5 the static gap is 1.22 and one event of twelve fails. A fitted value (k) sets it; it is the cost of the trade-off in G1 and G3.

### G3: dark `photo` timing and spring (27), class (a)

Flutter's dark-photo disappear is now slower than native's in every preset and mode (default normal 175 against 133 ms; `.snappy` 142 against 125; Reduce Motion 175 against 142), and its appear stiffer (default normal spring 0.27 / 1.57 against native's 0.48 / 1.04). At k = 3 it ran the other way: the first results' dark-photo disappear ran ahead (108 against 133 ms). The sign follows k as the per-k table predicts: Flutter's dark-photo progress at a fixed visibility leads the backdrop mean by +0.131 at k = 0.5 and trails it by −0.102 at k = 3, against native's +0.038; at k = 1 it is +0.048. A glass whose progress reads higher at a given visibility holds on longer when disappearing and rises sooner when appearing, which is what the pairs show (`crops/fix2-g3-dark-photo-disappear.png`: native 0.61, 0.25, 0.08 at +48, +98, +148 ms against Flutter 0.66, 0.34, 0.16 at +50, +103, +152 ms). The `.bouncy` dark-photo appears also fall short of native's overshoot (1.03 against 1.45 %; 1.61 against 3.44 % under Reduce Motion): above full, Flutter's dark-photo progress rises about half as fast (the per-case gain fits 0.72 and 1.46 against the pooled 0.50 and 0.78).

This is a fitted value with a measured trade-off: at k = 3 the light backdrops carried 31 failures and dark-photo 15 non-sharpness ones; at k = 0.5 the light backdrops carry 11 and dark-photo 27. A k between 0.5 and 1 is the candidate (the objective cannot separate them, 2.306 against 2.312), with the light backdrops' deviation as its cost; the deciding run is a Done run at such a k, which `fitvis` writes only when its objective chooses it.

### G4: spring shape on dark `stripes` (12), class (b)

`response_pct` and `damping` on dark-stripes, both events, 1.05–2.6 times their limits. Native's dark-stripes progress leads its backdrop mean by +0.080 to +0.092 (`fix2-fit.json` `blur_ramp.native_deviation`); Flutter's sits at −0.031 to +0.023 at half progress for every one of the seven k scanned, so no fitted value reaches it. The crop shows why (`crops/fix2-g4-dark-stripes-appear.png`, default appear: native 0.43, 0.75, 0.93 against Flutter 0.47, 0.77, 0.93 at the same times): native's lens shifts the stripe boundaries inside the glass mid-transition, and that shift enters native's progress reading; Flutter's boundaries stay in place. The disappear failures on dark-stripes have the same root: native's dark-stripes disappear exponent is 2.2–2.45 per case against the pooled 2.7–3.1, and the package uses one exponent per preset for every backdrop. The lens displacement mid-transition is ruling 14's open item.

### G5: spring shape on the light backdrops (6), class (b)

Normal default light-photo appear `response_pct` 6.15 > 5.0; normal `.bouncy` light-stripes appear 6.38 > 5.0; normal `.snappy` light-photo disappear `damping` 0.080 > 0.075; Reduce Motion `.bouncy` light-stripes disappear `response_pct` 9.09 > 6.82; Reduce Motion `.snappy` light-photo appear `response_pct` 24.1 > 10.2 and `damping` 0.12 > 0.05. At k = 0.5 the light backdrops' progress deviation matches native's within 0.02, so what remains is the curve's shape, not its level, and no table value changes shape per backdrop: the gains move the overshoot the other way (Reduce Motion `.snappy` light-photo's own gain is 0.50 against the pooled 0.60, and Flutter already overshoots less, 0.31 against 0.43 %). Native's per-case springs differ systematically by backdrop and are stable across every recording group (A3: light-stripes 0.44–0.46 s, dark-stripes 0.69–0.73), while one SwiftUI spring per preset drives every backdrop (ruling 10). Four of the six are within 1.35 times their limits; the two Reduce Motion `.snappy` light-photo appear values are 2.4 times theirs.

### G6: timing by one to three frames off dark `photo` (9), class (b)

`t10_90_ms` and `settle_ms` 4–33 ms over their limits on dark-stripes, light-photo and light-stripes:
- three disappears settle one or two frames late on dark-stripes (default normal 25 > 17, default Reduce Motion 41.7 > 17, `.bouncy` Reduce Motion 33.3 > 17): the pooled exponent against native's per-backdrop one (dark-stripes 2.2–2.45 per case), as in G4;
- five `.bouncy` and `.snappy` appears settle or rise late (`.bouncy` normal light-photo `settle_ms` 50 > 25; Reduce Motion dark-stripes `t10_90_ms` 25 > 17 and `settle_ms` 33.3 > 17; Reduce Motion light-stripes `settle_ms` 50 > 17; `.snappy` Reduce Motion light-stripes `settle_ms` 41.7 > 37.5): Flutter's appear follows SwiftUI's spring (the `.bouncy` spring's own 10–90 % time is 169 ms; Flutter reads 167–175 ms, native 133–150 ms), and native's appears run faster than their spring (ruling 10);
- one default appear settles two frames late (normal light-stripes 33.3 > 25; native 10–90 % / settle 317 / 492 ms, Flutter 292 / 525 ms).

Where Flutter's `.bouncy` overshoot now meets or passes native's (2.75 against 2.47 % on normal light-photo), the 2 % settle band turns a 0.3-point difference into 50 ms (A4's band sensitivity).

### The failing values

<!-- G1 12 -->
| Group (class) | Mode | Preset | Case | Event | Measure | Value > limit | Native: 10–90 / settle, overshoot, spring, sharpness | Flutter: the same | Run |
|---|---|---|---|---|---|---|---|---|---|
| G1 (b) | normal | default | dark-photo | disappear | `sharpness` | 1.129 > 1.000 | 133 / 225 ms, 0.00 %, 0.26 / 0.98, -1.22 | 175 / 275 ms, 0.00 %, 0.31 / 0.99, -2.34 | `20261006-154138` |
| G1 (b) | normal | default | dark-photo | appear | `sharpness` | 1.209 > 1.000 | 275 / 458 ms, 0.00 %, 0.48 / 1.04, -1.07 | 267 / 425 ms, 0.00 %, 0.27 / 1.57, -2.28 | `20261006-154138` |
| G1 (b) | normal | .bouncy | dark-photo | disappear | `sharpness` | 1.247 > 1.000 | 100 / 167 ms, 0.00 %, 0.24 / 0.88, -1.24 | 125 / 192 ms, 0.00 %, 0.29 / 0.85, -2.48 | `20261006-162523` |
| G1 (b) | normal | .bouncy | dark-photo | appear | `sharpness` | 1.328 > 1.000 | 133 / 217 ms, 1.45 %, 0.43 / 0.73, -1.10 | 175 / 233 ms, 1.03 %, 0.31 / 0.97, -2.43 | `20261006-154138` |
| G1 (b) | normal | .snappy | dark-photo | disappear | `sharpness` | 1.273 > 1.000 | 125 / 192 ms, 0.00 %, 0.26 / 0.89, -1.09 | 142 / 225 ms, 0.01 %, 0.30 / 0.90, -2.36 | `20261006-154138` |
| G1 (b) | normal | .snappy | dark-photo | appear | `sharpness` | 1.127 > 1.000 | 217 / 317 ms, 0.28 %, 0.50 / 0.85, -1.19 | 200 / 300 ms, 0.01 %, 0.29 / 1.17, -2.32 | `20261006-154138` |
| G1 (b) | RM | default | dark-photo | disappear | `sharpness` | 1.295 > 1.000 | 142 / 242 ms, 0.00 %, 0.25 / 1.01, -1.16 | 175 / 275 ms, 0.00 %, 0.31 / 0.99, -2.45 | `20261006-155725` |
| G1 (b) | RM | default | dark-photo | appear | `sharpness` | 1.411 > 1.000 | 283 / 475 ms, 0.00 %, 0.49 / 1.07, -0.94 | 275 / 425 ms, 0.00 %, 0.28 / 1.53, -2.35 | `20261006-155725` |
| G1 (b) | RM | .bouncy | dark-photo | disappear | `sharpness` | 1.326 > 1.000 | 108 / 167 ms, 0.00 %, 0.25 / 0.86, -1.15 | 133 / 192 ms, 0.00 %, 0.30 / 0.83, -2.48 | `20261006-155725` |
| G1 (b) | RM | .bouncy | dark-photo | appear | `sharpness` | 1.325 > 1.000 | 133 / 425 ms, 3.44 %, 0.43 / 0.71, -1.09 | 175 / 242 ms, 1.61 %, 0.31 / 0.97, -2.42 | `20261006-155725` |
| G1 (b) | RM | .snappy | dark-photo | disappear | `sharpness` | 1.248 > 1.000 | 117 / 200 ms, 0.00 %, 0.26 / 0.91, -1.11 | 150 / 225 ms, 0.00 %, 0.30 / 0.91, -2.36 | `20261006-155725` |
| G1 (b) | RM | .snappy | dark-photo | appear | `sharpness` | 1.384 > 1.000 | 200 / 325 ms, 0.45 %, 0.57 / 0.78, -0.98 | 208 / 300 ms, 0.10 %, 0.29 / 1.18, -2.37 | `20261006-155725` |

<!-- G2 1 -->
| Group (class) | Mode | Preset | Case | Event | Measure | Value > limit | Native: 10–90 / settle, overshoot, spring, sharpness | Flutter: the same | Run |
|---|---|---|---|---|---|---|---|---|---|
| G2 (a) | RM | .snappy | light-photo | disappear | `sharpness` | 1.127 > 1.000 | 117 / 183 ms, 0.01 %, 0.21 / 0.99, -1.52 | 108 / 192 ms, 0.00 %, 0.19 / 1.04, -2.65 | `20261006-155725` |

<!-- G3 27 -->
| Group (class) | Mode | Preset | Case | Event | Measure | Value > limit | Native: 10–90 / settle, overshoot, spring, sharpness | Flutter: the same | Run |
|---|---|---|---|---|---|---|---|---|---|
| G3 (a) | normal | default | dark-photo | disappear | `t10_90_ms` | 41.667 > 17.000 | 133 / 225 ms, 0.00 %, 0.26 / 0.98, -1.22 | 175 / 275 ms, 0.00 %, 0.31 / 0.99, -2.34 | `20261006-154138` |
| G3 (a) | normal | default | dark-photo | disappear | `settle_ms` | 50.000 > 17.000 | 133 / 225 ms, 0.00 %, 0.26 / 0.98, -1.22 | 175 / 275 ms, 0.00 %, 0.31 / 0.99, -2.34 | `20261006-154138` |
| G3 (a) | normal | default | dark-photo | disappear | `response_pct` | 19.231 > 16.667 | 133 / 225 ms, 0.00 %, 0.26 / 0.98, -1.22 | 175 / 275 ms, 0.00 %, 0.31 / 0.99, -2.34 | `20261006-154138` |
| G3 (a) | normal | default | dark-photo | appear | `settle_ms` | 33.333 > 25.000 | 275 / 458 ms, 0.00 %, 0.48 / 1.04, -1.07 | 267 / 425 ms, 0.00 %, 0.27 / 1.57, -2.28 | `20261006-154138` |
| G3 (a) | normal | default | dark-photo | appear | `response_pct` | 43.750 > 30.612 | 275 / 458 ms, 0.00 %, 0.48 / 1.04, -1.07 | 267 / 425 ms, 0.00 %, 0.27 / 1.57, -2.28 | `20261006-154138` |
| G3 (a) | normal | default | dark-photo | appear | `damping` | 0.530 > 0.240 | 275 / 458 ms, 0.00 %, 0.48 / 1.04, -1.07 | 267 / 425 ms, 0.00 %, 0.27 / 1.57, -2.28 | `20261006-154138` |
| G3 (a) | normal | .bouncy | dark-photo | disappear | `settle_ms` | 25.000 > 17.000 | 100 / 167 ms, 0.00 %, 0.24 / 0.88, -1.24 | 125 / 192 ms, 0.00 %, 0.29 / 0.85, -2.48 | `20261006-162523` |
| G3 (a) | normal | .bouncy | dark-photo | disappear | `response_pct` | 20.833 > 6.250 | 100 / 167 ms, 0.00 %, 0.24 / 0.88, -1.24 | 125 / 192 ms, 0.00 %, 0.29 / 0.85, -2.48 | `20261006-162523` |
| G3 (a) | normal | .bouncy | dark-photo | appear | `t10_90_ms` | 41.667 > 17.000 | 133 / 217 ms, 1.45 %, 0.43 / 0.73, -1.10 | 175 / 233 ms, 1.03 %, 0.31 / 0.97, -2.43 | `20261006-154138` |
| G3 (a) | normal | .bouncy | dark-photo | appear | `damping` | 0.240 > 0.060 | 133 / 217 ms, 1.45 %, 0.43 / 0.73, -1.10 | 175 / 233 ms, 1.03 %, 0.31 / 0.97, -2.43 | `20261006-154138` |
| G3 (a) | normal | .snappy | dark-photo | disappear | `settle_ms` | 33.333 > 17.000 | 125 / 192 ms, 0.00 %, 0.26 / 0.89, -1.09 | 142 / 225 ms, 0.01 %, 0.30 / 0.90, -2.36 | `20261006-154138` |
| G3 (a) | normal | .snappy | dark-photo | disappear | `response_pct` | 15.385 > 6.000 | 125 / 192 ms, 0.00 %, 0.26 / 0.89, -1.09 | 142 / 225 ms, 0.01 %, 0.30 / 0.90, -2.36 | `20261006-154138` |
| G3 (a) | normal | .snappy | dark-photo | appear | `response_pct` | 42.000 > 20.588 | 217 / 317 ms, 0.28 %, 0.50 / 0.85, -1.19 | 200 / 300 ms, 0.01 %, 0.29 / 1.17, -2.32 | `20261006-154138` |
| G3 (a) | normal | .snappy | dark-photo | appear | `damping` | 0.320 > 0.105 | 217 / 317 ms, 0.28 %, 0.50 / 0.85, -1.19 | 200 / 300 ms, 0.01 %, 0.29 / 1.17, -2.32 | `20261006-154138` |
| G3 (a) | RM | default | dark-photo | disappear | `t10_90_ms` | 33.333 > 17.000 | 142 / 242 ms, 0.00 %, 0.25 / 1.01, -1.16 | 175 / 275 ms, 0.00 %, 0.31 / 0.99, -2.45 | `20261006-155725` |
| G3 (a) | RM | default | dark-photo | disappear | `response_pct` | 24.000 > 12.000 | 142 / 242 ms, 0.00 %, 0.25 / 1.01, -1.16 | 175 / 275 ms, 0.00 %, 0.31 / 0.99, -2.45 | `20261006-155725` |
| G3 (a) | RM | default | dark-photo | appear | `settle_ms` | 50.000 > 37.500 | 283 / 475 ms, 0.00 %, 0.49 / 1.07, -0.94 | 275 / 425 ms, 0.00 %, 0.28 / 1.53, -2.35 | `20261006-155725` |
| G3 (a) | RM | default | dark-photo | appear | `response_pct` | 42.857 > 6.250 | 283 / 475 ms, 0.00 %, 0.49 / 1.07, -0.94 | 275 / 425 ms, 0.00 %, 0.28 / 1.53, -2.35 | `20261006-155725` |
| G3 (a) | RM | default | dark-photo | appear | `damping` | 0.460 > 0.060 | 283 / 475 ms, 0.00 %, 0.49 / 1.07, -0.94 | 275 / 425 ms, 0.00 %, 0.28 / 1.53, -2.35 | `20261006-155725` |
| G3 (a) | RM | .bouncy | dark-photo | disappear | `t10_90_ms` | 25.000 > 17.000 | 108 / 167 ms, 0.00 %, 0.25 / 0.86, -1.15 | 133 / 192 ms, 0.00 %, 0.30 / 0.83, -2.48 | `20261006-155725` |
| G3 (a) | RM | .bouncy | dark-photo | appear | `t10_90_ms` | 41.667 > 17.000 | 133 / 425 ms, 3.44 %, 0.43 / 0.71, -1.09 | 175 / 242 ms, 1.61 %, 0.31 / 0.97, -2.42 | `20261006-155725` |
| G3 (a) | RM | .bouncy | dark-photo | appear | `settle_ms` | 183.333 > 75.000 | 133 / 425 ms, 3.44 %, 0.43 / 0.71, -1.09 | 175 / 242 ms, 1.61 %, 0.31 / 0.97, -2.42 | `20261006-155725` |
| G3 (a) | RM | .bouncy | dark-photo | appear | `damping` | 0.260 > 0.135 | 133 / 425 ms, 3.44 %, 0.43 / 0.71, -1.09 | 175 / 242 ms, 1.61 %, 0.31 / 0.97, -2.42 | `20261006-155725` |
| G3 (a) | RM | .snappy | dark-photo | disappear | `t10_90_ms` | 33.333 > 17.000 | 117 / 200 ms, 0.00 %, 0.26 / 0.91, -1.11 | 150 / 225 ms, 0.00 %, 0.30 / 0.91, -2.36 | `20261006-155725` |
| G3 (a) | RM | .snappy | dark-photo | disappear | `settle_ms` | 25.000 > 17.000 | 117 / 200 ms, 0.00 %, 0.26 / 0.91, -1.11 | 150 / 225 ms, 0.00 %, 0.30 / 0.91, -2.36 | `20261006-155725` |
| G3 (a) | RM | .snappy | dark-photo | disappear | `response_pct` | 15.385 > 6.000 | 117 / 200 ms, 0.00 %, 0.26 / 0.91, -1.11 | 150 / 225 ms, 0.00 %, 0.30 / 0.91, -2.36 | `20261006-155725` |
| G3 (a) | RM | .snappy | dark-photo | appear | `damping` | 0.400 > 0.180 | 200 / 325 ms, 0.45 %, 0.57 / 0.78, -0.98 | 208 / 300 ms, 0.10 %, 0.29 / 1.18, -2.37 | `20261006-155725` |

<!-- G4 12 -->
| Group (class) | Mode | Preset | Case | Event | Measure | Value > limit | Native: 10–90 / settle, overshoot, spring, sharpness | Flutter: the same | Run |
|---|---|---|---|---|---|---|---|---|---|
| G4 (b) | normal | default | dark-stripes | appear | `response_pct` | 14.545 > 5.556 | 292 / 467 ms, 0.00 %, 0.55 / 0.96, 0.07 | 292 / 492 ms, 0.01 %, 0.47 / 1.09, -0.11 | `20261006-154138` |
| G4 (b) | normal | default | dark-stripes | appear | `damping` | 0.130 > 0.060 | 292 / 467 ms, 0.00 %, 0.55 / 0.96, 0.07 | 292 / 492 ms, 0.01 %, 0.47 / 1.09, -0.11 | `20261006-154138` |
| G4 (b) | normal | .bouncy | dark-stripes | disappear | `response_pct` | 13.043 > 6.818 | 108 / 158 ms, 0.00 %, 0.23 / 0.87, 0.05 | 117 / 175 ms, 0.00 %, 0.20 / 1.00, -0.11 | `20261006-154138` |
| G4 (b) | normal | .bouncy | dark-stripes | disappear | `damping` | 0.130 > 0.050 | 108 / 158 ms, 0.00 %, 0.23 / 0.87, 0.05 | 117 / 175 ms, 0.00 %, 0.20 / 1.00, -0.11 | `20261006-154138` |
| G4 (b) | normal | .bouncy | dark-stripes | appear | `response_pct` | 5.263 > 5.000 | 150 / 342 ms, 2.15 %, 0.38 / 0.74, 0.03 | 167 / 400 ms, 2.78 %, 0.40 / 0.78, -0.14 | `20261006-154138` |
| G4 (b) | normal | .snappy | dark-stripes | appear | `response_pct` | 14.286 > 13.333 | 217 / 325 ms, 0.29 %, 0.49 / 0.86, -0.01 | 217 / 317 ms, 0.18 %, 0.42 / 0.92, -0.09 | `20261006-154138` |
| G4 (b) | RM | default | dark-stripes | appear | `response_pct` | 20.339 > 7.895 | 300 / 492 ms, 0.00 %, 0.59 / 0.97, 0.10 | 292 / 492 ms, 0.07 %, 0.47 / 1.09, -0.11 | `20261006-155725` |
| G4 (b) | RM | default | dark-stripes | appear | `damping` | 0.120 > 0.050 | 300 / 492 ms, 0.00 %, 0.59 / 0.97, 0.10 | 292 / 492 ms, 0.07 %, 0.47 / 1.09, -0.11 | `20261006-155725` |
| G4 (b) | RM | .bouncy | dark-stripes | appear | `damping` | 0.070 > 0.050 | 150 / 408 ms, 3.76 %, 0.41 / 0.70, 0.03 | 175 / 442 ms, 3.96 %, 0.40 / 0.77, -0.09 | `20261006-155725` |
| G4 (b) | RM | .snappy | dark-stripes | disappear | `damping` | 0.070 > 0.060 | 117 / 183 ms, 0.00 %, 0.21 / 0.98, 0.09 | 117 / 200 ms, 0.03 %, 0.20 / 1.05, -0.16 | `20261006-155725` |
| G4 (b) | RM | .snappy | dark-stripes | appear | `response_pct` | 16.000 > 8.654 | 217 / 317 ms, 0.26 %, 0.50 / 0.85, 0.14 | 217 / 317 ms, 0.19 %, 0.42 / 0.92, -0.13 | `20261006-155725` |
| G4 (b) | RM | .snappy | dark-stripes | appear | `damping` | 0.070 > 0.060 | 217 / 317 ms, 0.26 %, 0.50 / 0.85, 0.14 | 217 / 317 ms, 0.19 %, 0.42 / 0.92, -0.13 | `20261006-155725` |

<!-- G5 6 -->
| Group (class) | Mode | Preset | Case | Event | Measure | Value > limit | Native: 10–90 / settle, overshoot, spring, sharpness | Flutter: the same | Run |
|---|---|---|---|---|---|---|---|---|---|
| G5 (b) | normal | default | light-photo | appear | `response_pct` | 6.154 > 5.000 | 292 / 525 ms, 0.00 %, 0.65 / 0.90, -1.51 | 308 / 533 ms, 0.00 %, 0.61 / 0.94, -2.44 | `20261006-154138` |
| G5 (b) | normal | .bouncy | light-stripes | appear | `response_pct` | 6.383 > 5.000 | 133 / 383 ms, 2.79 %, 0.47 / 0.68, -0.06 | 167 / 433 ms, 2.75 %, 0.50 / 0.71, -0.11 | `20261006-154138` |
| G5 (b) | normal | .snappy | light-photo | disappear | `damping` | 0.080 > 0.075 | 117 / 183 ms, 0.01 %, 0.21 / 0.97, -1.56 | 100 / 192 ms, 0.00 %, 0.18 / 1.05, -2.37 | `20261006-154138` |
| G5 (b) | RM | .bouncy | light-stripes | disappear | `response_pct` | 9.091 > 6.818 | 100 / 158 ms, 0.00 %, 0.22 / 0.88, 0.04 | 100 / 167 ms, 0.00 %, 0.20 / 0.94, -0.10 | `20261006-155725` |
| G5 (b) | RM | .snappy | light-photo | appear | `response_pct` | 24.138 > 10.169 | 225 / 333 ms, 0.43 %, 0.58 / 0.79, -1.36 | 208 / 325 ms, 0.31 %, 0.44 / 0.91, -2.33 | `20261006-155725` |
| G5 (b) | RM | .snappy | light-photo | appear | `damping` | 0.120 > 0.050 | 225 / 333 ms, 0.43 %, 0.58 / 0.79, -1.36 | 208 / 325 ms, 0.31 %, 0.44 / 0.91, -2.33 | `20261006-155725` |

<!-- G6 9 -->
| Group (class) | Mode | Preset | Case | Event | Measure | Value > limit | Native: 10–90 / settle, overshoot, spring, sharpness | Flutter: the same | Run |
|---|---|---|---|---|---|---|---|---|---|
| G6 (b) | normal | default | dark-stripes | disappear | `settle_ms` | 25.000 > 17.000 | 133 / 217 ms, 0.00 %, 0.23 / 1.03, 0.02 | 133 / 242 ms, 0.00 %, 0.21 / 1.13, -0.12 | `20261006-154138` |
| G6 (b) | normal | default | light-stripes | appear | `settle_ms` | 33.333 > 25.000 | 317 / 492 ms, 0.00 %, 0.60 / 0.97, -0.03 | 292 / 525 ms, 0.00 %, 0.59 / 0.96, -0.15 | `20261006-154138` |
| G6 (b) | normal | .bouncy | light-photo | appear | `settle_ms` | 50.000 > 25.000 | 142 / 375 ms, 2.47 %, 0.53 / 0.67, -1.54 | 167 / 425 ms, 2.75 %, 0.50 / 0.71, -2.47 | `20261006-154138` |
| G6 (b) | RM | default | dark-stripes | disappear | `settle_ms` | 41.667 > 17.000 | 125 / 200 ms, 0.02 %, 0.20 / 1.09, 0.09 | 142 / 242 ms, 0.00 %, 0.21 / 1.13, -0.06 | `20261006-155725` |
| G6 (b) | RM | .bouncy | dark-stripes | disappear | `settle_ms` | 33.333 > 17.000 | 100 / 150 ms, 0.00 %, 0.21 / 0.91, 0.06 | 117 / 183 ms, 0.00 %, 0.21 / 0.98, -0.08 | `20261006-155725` |
| G6 (b) | RM | .bouncy | dark-stripes | appear | `t10_90_ms` | 25.000 > 17.000 | 150 / 408 ms, 3.76 %, 0.41 / 0.70, 0.03 | 175 / 442 ms, 3.96 %, 0.40 / 0.77, -0.09 | `20261006-155725` |
| G6 (b) | RM | .bouncy | dark-stripes | appear | `settle_ms` | 33.333 > 17.000 | 150 / 408 ms, 3.76 %, 0.41 / 0.70, 0.03 | 175 / 442 ms, 3.96 %, 0.40 / 0.77, -0.09 | `20261006-155725` |
| G6 (b) | RM | .bouncy | light-stripes | appear | `settle_ms` | 50.000 > 17.000 | 150 / 425 ms, 3.70 %, 0.48 / 0.68, 0.03 | 167 / 475 ms, 3.99 %, 0.51 / 0.69, -0.14 | `20261006-155725` |
| G6 (b) | RM | .snappy | light-stripes | appear | `settle_ms` | 41.667 > 37.500 | 200 / 308 ms, 0.46 %, 0.50 / 0.81, 0.07 | 208 / 350 ms, 0.24 %, 0.52 / 0.83, -0.14 | `20261006-155725` |

## Not judged, reported

### Touch-to-response delay

Onset minus touch-up, native / Flutter, ms (each pair's `shapes.pairs.<pair>.delay`; normal `.bouncy` dark-photo disappear from the repeat). Disappear is step 1, appear step 3.

| Preset | Case | Normal disappear | Normal appear | Reduce Motion disappear | Reduce Motion appear |
|---|---|---|---|---|---|
| default | dark-photo | 28 / 17 | 112 / 15 | 28 / 17 | 97 / 13 |
| default | dark-stripes | 45 / 17 | 112 / 33 | 30 / 17 | 97 / 30 |
| default | light-photo | 27 / 17 | 97 / 13 | 30 / 17 | 80 / 12 |
| default | light-stripes | 45 / 17 | 97 / 13 | 32 / 17 | 92 / 13 |
| `.snappy` | dark-photo | 47 / 17 | 80 / 12 | 28 / 17 | 78 / 15 |
| `.snappy` | dark-stripes | 47 / 15 | 77 / 30 | 47 / 17 | 95 / 30 |
| `.snappy` | light-photo | 28 / 17 | 82 / 13 | 47 / 17 | 80 / 30 |
| `.snappy` | light-stripes | 43 / 17 | 82 / 13 | 30 / 18 | 113 / 13 |
| `.bouncy` | dark-photo | 42 / 17 | 78 / 15 | 28 / 17 | 77 / 13 |
| `.bouncy` | dark-stripes | 28 / 17 | 95 / 32 | 28 / 17 | 97 / 30 |
| `.bouncy` | light-photo | 45 / 17 | 78 / 15 | 28 / 17 | 82 / 30 |
| `.bouncy` | light-stripes | 47 / 17 | 97 / 12 | 30 / 17 | 78 / 13 |

Native starts to disappear 27–47 ms (normal) and 28–47 ms (Reduce Motion) after the tap, and to appear 77–112 ms and 77–113 ms after it; the package within 12–33 ms in every pair. Class: native latency that the package does not copy (ruling 33); project 5 re-checks it on a device.

### Frame gaps and first frames

Inside events: Flutter's one 40.0 ms gap (repeated, above) and native's one 25.0 ms tail gap. No Flutter first changed frame is more than 0.06 of the travel ahead of native's (the largest: `.snappy` dark-photo-reduce-motion appear, and the repeat's `.bouncy` dark-photo appear). Flutter's first changed frame came after a gap over 25 ms in four pairs: normal `.bouncy` dark-photo disappear (403 ms, the stalled event above) and three Reduce Motion appears (30 ms each: `.bouncy` dark-stripes and light-photo, `.snappy` light-photo, at progress 0.06–0.09 against native's 0.01–0.05). These are the variable-rate recorder's idle gap before an event, since the first frame is not behind.

### Rim depth

`rim_check.py fitvis/fix2-20261006-115226/table/ramp0.5 <run>` (`research/execution-2b1/fix2-rim-normal.txt`, `fix2-rim-rm.txt`), depth of the lit band under the top edge in points: Flutter 0.67–1.0 pt at visibility 0.1–1.0 in every case, within one pixel (⅓ pt) of its depth at 1 from 0.3 up (dark-photo 0.67 at 0.1–0.5 against 1.0 at 1; light-photo 0.67 throughout; above full 1.0–1.33): `uFullThickness` reaches the geometry pass (finding 28). Native at rest 1.0–1.67 pt; mid-transition, normal: dark-photo 14.5 / 24 / 24 pt at progress 0.3 / 0.5 / 0.7, the other three 5.0–5.33; Reduce Motion 5.0–5.33 throughout. Ruling 14's open item.

### Not re-run in part 2

The cold first transition (`cold/20261006-002600`, at `58ab57e0c`, k = 3): the launch's first disappear started at progress 0.38 and read 83 against native's 133 ms, the appear 300 against 275 ms (ruling 24; the debug JIT's first frame). The ghosts (`ghost/20261006-014735`, `-014805`): the label in place and fading with the glass in every frame, no blink, in the container and in the `Overlay`. Neither depends on the materialize table; both are carried as measured.

## Done item 5: still glass against 2A

Built by `lab.py build example` and `lab.py build operator` at the tip, recorded 16:54–18:02 (load 43–128 from Spotlight indexing; still pixels do not depend on it). `still_check.py <2A run> <new run>` per scene; outputs in `research/execution-2b1/fix2-still-<scene>.txt`.

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

**`button.press`: the same fix, the other way.** Its four Flutter frames differ from 2A's only on the rims of the two buttons (maximum channel difference 133 dark, 110 light; label, interior and backdrop identical; `crops/fix2-still-button-press-dark-stripes-2A-new-diff.png`, 2A | new | difference × 4). The glass button's rim moved 0.19–0.26 px on both its left and right sides and 0.15–0.27 px vertically, a uniform sub-pixel translation (gradient centroids over 17 rows or columns per side). That is what part 1's fix does to glass that 2A also drew through the cached matte at a fractional pixel position; the button's exact position was not read. The first results' run (`20261006-013200`, before the fix) was byte-identical to 2A. Every measure moved toward native or stayed: dark-stripes `mad` 7.13 → 7.07, `rim_rms` 10.69 → 10.38; light-stripes `mad` 8.07 → 7.99, `rim_rms` 8.54 → 8.30, `luminance` 0.86 → 0.84; `bbox_pt` unchanged; every one failed or passed as before. Done item 5 passes on its definition, and the frame change is the A9 renderer fix, not a regression.

## Deviations from the plan and rulings

1. **The first noise session was stale, not loaded** (A10). The first results blamed machine load for the slow first noise session and the long native presses. The audit showed the drift tracks the session: that session ran on a simulator boot from before the 2026-10-04 reboot, on a Mac then up nine days, and read appear `t10_90` about 12 ms slower and presses of 3.26 s (median); the loaded second session agreed with 2A and with the low-load Step 5. Part 2 re-recorded it after a fresh boot, with N1, N2, N5 and N6: every press now reads 0.98–1.00 s. Load did produce capture holes, which the outlier rule excludes.
2. **Outlier exclusions** (Task 9, part 2). Task 9 excluded four materialize takes (capture holes, `task-9-outliers.md`) and kept 24 flagged press and interactive takes. Part 2 applied the rule to every take, with the touch gate, and excluded 18 (Done item 2). Ten cases now hold takes from three simulator boots (Task 9's four replaced cases, and six whose session 2 lost one take), and every case from at least two (ruling P2-3).
3. **`noise.json` is recomputed in canonical take order** (A6), and every moved limit is disclosed (A7). The audit found that Task 9's replacement takes had loosened eight item-4 limits in the four replaced cases, undisclosed; part 2's disclosure lists every moved limit, including the one take that sets three limits of one case (ruling P2-6).
4. **The fit** (A1, A4, A8, C3, C4, P1-6). k is chosen on the joint objective and written with its trade-off; the gains are fitted on the overshoot peak, per case and per appearance as well as pooled; the write guard refuses unfitted, dropped and edge values. The first fit attempt lost its output to a relative `--out` (the driver resolves it against `/`, as with `repeat --into`, ROADMAP gotcha 43); the second chose k = 0.5 on the edge of 0.5–4 and was refused; the third, with 0.25, wrote the table. One N6 case had a squeezed capture and was re-recorded before the third fit (ruling P2-7).
5. **Stall repeats** (A5). The first results substituted repeats per case: 129 normal and 135 Reduce Motion; per event, as the audit's rule requires, Reduce Motion reads 134. Part 2 substitutes per event only.
6. **`material.edge`** (A9). Part 1's fix (`f07236cff`) rasterizes the cached geometry matte at the sub-pixel phase it is drawn at, keeping the cache. All 12 `material.edge` Flutter frames are byte-identical to 2A's again (`20261006-171635`): the first results' rim snap (0.24 px there, 0.16 px by the audit's fit) is gone. It was a renderer defect, latent in the fork's geometry cache since before 2A and exposed by ruling 30, not a model limitation as the first results classed it. The same fix moves `button.press`'s rims, where 2A itself was snapped (Done item 5). Its per-frame cost while glass slides is not measured (re-review P1-4, `todo-2b1.md`).
7. **Disk and the lost still runs.** Part 2 stopped once at 36 GB free (the main session's 40 GB line) after Done item 4, and continued on the main session's 20 GB line; it ended at 33 GB. The noise analysis writes its frame caches into every take (`noise-2b1/takes` 42 GB, `stale-session1` 26 GB, `excluded` 3.6 GB). Stopping the first still attempt with `pkill` (SIGTERM) skipped the lab's cleanup and left `simctl io recordVideo` running, so the next five still runs failed in every case with `recordVideo did not start`; the recorder was stopped with SIGINT and all nine scenes recorded again (ROADMAP gotcha 50). A mistyped `lab.py report` on the runs folder itself wrote an empty `runs/report.html` and `runs/report_assets/`. Nothing was deleted; the failed runs are listed under Run folders.
8. **Tests beyond the plan.** Harness 175 → 201 (part 1: C2, C3, C9, C19, A1, A4, A6; part 2: P1-6); package 125 → 155 (part 1: C1, C5–C8, C10, C14, C15, C18, A4, A9; part 2: P1-3; P1-5 rewrote one assertion).

## Gates

At `01b59747d` plus this document change (no code since), with `--no-pub`:
- app (`packages/mobile`): `flutter analyze` "No issues found!", `flutter test` `+2146: All tests passed!`;
- package (`packages/ios_liquid_glass`): `flutter analyze` "No issues found!", `flutter test` `+155: All tests passed!`;
- example: `flutter analyze` "No issues found!", `flutter test` `+13: All tests passed!`;
- harness: `python3 -m unittest discover tool/glass_lab/harness/tests`, `Ran 201 tests`, OK.

`flutter test` prints the known SkSL error about `liquid_glass_geometry_blended` (ROADMAP gotcha 3). `xcrun simctl spawn 708879DD-8B2A-4547-863F-F49EE1474D8B defaults read com.apple.Accessibility ReduceMotionEnabled` prints `0`.
