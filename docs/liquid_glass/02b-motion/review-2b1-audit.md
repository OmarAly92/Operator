# 2B.1 measurement audit (branch `feat/ios-liquid-glass-2b1`, tip `abe33abbc`)

Auditor: independent measurement audit, 2026-10-06. Nothing in `/Users/omaraly/development/AI/Operator-2b1` was edited or written; every analysis ran on scratch copies (`scratchpad/review2b1-audit/`), with the branch harness copied to `scratchpad/review2b1-audit/mobile/tool/glass_lab/`. No simulator was used (see point 4 and point 6 for why no recording was decisive).

## 1. Verdict

**The numbers hold; several diagnoses and two recorded "native facts" do not.**

- Every Done-table count recomputes exactly from `result.json` with my own script: progress measures 129 / 168 / 168 (normal) and 135 / 168 / 168 (Reduce Motion) with the repeats, 130 and 133 as first run, event and touch gates 120 / 120, `unpaired` 0. Every recorded limit equals max(fixed, 1.5 × noise) with the `noise.json` the runs loaded (`fd30f969d`): 0 mismatches over 336 judged values. No measure is absent. The 72 failing values and limits match the results tables one for one.
- `noise.json` recomputes from the take videos (6 cases re-analysed, both appearances, materialize, press and spacing). `reproduce.py` re-run in scratch is byte-identical to the executor's and the prototype's output. Still glass: 112 / 124 Flutter frames byte-identical, `missing` 0, `worse` 0 in all nine scenes, largest measure move 0.0008; re-analysing both the 2A and the new runs with the branch harness gives the stored values.
- No blocker. Three **major** findings should be fixed in the documents before merge:
  - **A1:** the class (b) label on the dark-`photo` disappear failures is not proven, because a fitted value (the blur ramp) demonstrably sets their cause.
  - **A2:** the "250 × 44 grows only 15.0–15.5 pt, the 17.5 pt law does not hold" fact, now in the ROADMAP, is contradicted by the branch's own N2 recordings on `photo` (+16.67 to +17.33 pt).
  - **A4:** a1's candidate fix (a per-appearance gain fitted by `fitvis`) would fit `light` at the grid floor 0.0 and make the failure worse.

  The rest are minor.
- Load did not bias the native references or the fits. Session 1 (the lowest load, before the simulator reboot) is the outlier, not the loaded sessions. No re-recording is needed before merge. N1 and N2 were recorded with 1.5–2.9 s presses for a scripted 1.0 s, so they should be re-recorded after a fresh simulator boot before 2B.3 judges press (A10).

## 2. Recomputed Done table against the claims

Script: `scratchpad/review2b1-audit/recompute.py` (reads each pair's `shapes.pairs.*.shapes.block.progress` values, not `measures`, applies max(fixed, 1.5 × noise) from `noise.json` at `fd30f969d`, and compares with the stored `measures`/`checks`). Output: `recompute-fd30.txt`.

| Done item | Claim | Recomputed | Agrees |
|---|---|---|---|
| 1 | pass; 250 × 44 +14.33 not reproduced | `reproduce.py` output byte-identical to `task-6-reproduce.txt` and `proto-2b1/reproduce.txt` (`reproduce-audit.txt`); reference copies byte-identical to the original recordings (266 files, md5) | yes, but the 250 × 44 explanation is wrong (A2) |
| 2 | 15 scenes, 60 cases | 15 scenes, 60 cases; value counts 518 / 501 / 498 / 318 / 187 / 134 / 147 / 88 / 207, spacing 32–36; `noise.json` = max over stored pair results in all 60 cases; 6 cases re-analysed from video reproduce it, except 3 replaced cases' asymmetric `response_pct` (A6) | yes |
| 3 | recorded | runs present | yes (A10 on N1/N2 usability) |
| 4 normal | 129 / 168 / 168 (130 first run) | **129 / 168 / 168** (130 first run) | yes |
| 4 Reduce Motion | 135 / 168 / 168 (133 first run) | **135 / 168 / 168** (133 first run); 134 if substituted per event, not per case (A5) | yes |
| 4 gates | 120 / 120, `unpaired` 0 | 120 / 120, `unpaired` 0 in all 24 cases; every case has pairs `step1e0`, `step3e0`, 2 touches per app | yes |
| 4 per scene × appearance | table in results | identical (default dark 19 / 21, light 24 / 23; snappy 21 / 23, 24 / 24; bouncy 21 / 22, 20 / 22) | yes |
| 4 failing pairs by measure | `t10_90` 4 / 3, `settle` 7 / 3, `overshoot` 0 / 0, `response` 12 / 13, `damping` 10 / 8, `rms` 0 / 0, `sharpness` 6 / 6 | identical | yes |
| 4 classes | 69 (b), 3 (a) | counts per group match (b1 12, b2 11, b3 36, b4 10, a1 3). (b) is supported for b1 (12) and the four `.bouncy` `t10_90` rows of b4. It is not proven for b2 (11) and two b4 rows (A1). b3 (36) is plausible but its argument is k-dependent (A1). a1 is (a), but its fix is wrong (A4). | counts yes, classes partly |
| 5 | 112 / 124 byte-identical, missing 0, worse 0, max move 0.0008 | identical (`still-audit.txt`); native frames differ by 0 (102), 1 (8), 2 (10), 229 (4) levels | yes; edge wording A9 |

Every failing measure (substituted set, 39 normal + 33 Reduce Motion), value > limit, with the noise used:

| Mode | Scene | Case | Event | Measure | Value | Limit | Noise | Run |
|---|---|---|---|---|---|---|---|---|
| N | mm | dark-photo | disappear | t10_90_ms | 25.000 | 17.000 | 8.333 | 20261005-233131 |
| N | mm | dark-photo | disappear | settle_ms | 25.000 | 17.000 | 0.000 | 20261005-233131 |
| N | mm | dark-photo | disappear | response_pct | 32.000 | 6.000 | 4.000 | 20261005-233131 |
| N | mm | dark-photo | disappear | damping | 0.140 | 0.060 | 0.040 | 20261005-233131 |
| N | mm | dark-photo | disappear | sharpness | 1.341 | 1.000 | 0.057 | 20261005-233131 |
| N | mm | dark-photo | appear | settle_ms | 75.000 | 50.000 | 33.333 | 20261005-233131 |
| N | mm | dark-photo | appear | sharpness | 1.334 | 1.000 | 0.196 | 20261005-233131 |
| N | mm | dark-stripes | appear | settle_ms | 41.667 | 37.500 | 25.000 | 20261005-233131 |
| N | mm | dark-stripes | appear | response_pct | 10.909 | 5.769 | 3.846 | 20261005-233131 |
| N | mm | light-photo | appear | response_pct | 37.313 | 21.154 | 14.103 | 20261005-233131 |
| N | mm | light-photo | appear | damping | 0.310 | 0.090 | 0.060 | 20261005-233131 |
| N | mm | light-stripes | appear | response_pct | 37.681 | 27.966 | 18.644 | 20261006-001644 |
| N | mm | light-stripes | appear | damping | 0.300 | 0.165 | 0.110 | 20261006-001644 |
| N | mm.bouncy | dark-photo | disappear | response_pct | 26.087 | 6.000 | 4.000 | 20261005-233131 |
| N | mm.bouncy | dark-photo | disappear | damping | 0.090 | 0.050 | 0.020 | 20261005-233131 |
| N | mm.bouncy | dark-photo | disappear | sharpness | 1.523 | 1.000 | 0.238 | 20261005-233131 |
| N | mm.bouncy | dark-photo | appear | t10_90_ms | 25.000 | 17.000 | 8.333 | 20261005-233131 |
| N | mm.bouncy | dark-photo | appear | sharpness | 1.236 | 1.000 | 0.082 | 20261005-233131 |
| N | mm.bouncy | dark-stripes | appear | t10_90_ms | 33.333 | 25.000 | 16.667 | 20261005-233131 |
| N | mm.bouncy | dark-stripes | appear | damping | 0.090 | 0.050 | 0.030 | 20261005-233131 |
| N | mm.bouncy | light-photo | appear | settle_ms | 158.333 | 25.000 | 16.667 | 20261005-233131 |
| N | mm.bouncy | light-photo | appear | response_pct | 24.074 | 22.340 | 14.894 | 20261005-233131 |
| N | mm.bouncy | light-photo | appear | damping | 0.140 | 0.050 | 0.020 | 20261005-233131 |
| N | mm.bouncy | light-stripes | disappear | response_pct | 14.286 | 7.143 | 4.762 | 20261005-233131 |
| N | mm.bouncy | light-stripes | appear | t10_90_ms | 41.667 | 25.000 | 16.667 | 20261005-233131 |
| N | mm.bouncy | light-stripes | appear | settle_ms | 125.000 | 87.500 | 58.333 | 20261005-233131 |
| N | mm.bouncy | light-stripes | appear | response_pct | 14.583 | 5.000 | 2.083 | 20261005-233131 |
| N | mm.bouncy | light-stripes | appear | damping | 0.140 | 0.050 | 0.010 | 20261005-233131 |
| N | mm.snappy | dark-photo | disappear | response_pct | 24.000 | 18.750 | 12.500 | 20261006-002044 |
| N | mm.snappy | dark-photo | disappear | sharpness | 1.140 | 1.000 | 0.101 | 20261006-002044 |
| N | mm.snappy | dark-photo | appear | settle_ms | 33.333 | 25.000 | 16.667 | 20261006-002044 |
| N | mm.snappy | dark-photo | appear | sharpness | 1.289 | 1.000 | 0.243 | 20261006-002044 |
| N | mm.snappy | dark-stripes | appear | settle_ms | 33.333 | 25.000 | 16.667 | 20261005-233131 |
| N | mm.snappy | dark-stripes | appear | response_pct | 29.787 | 6.667 | 4.444 | 20261005-233131 |
| N | mm.snappy | dark-stripes | appear | damping | 0.260 | 0.105 | 0.070 | 20261005-233131 |
| N | mm.snappy | light-photo | appear | response_pct | 29.310 | 22.727 | 15.152 | 20261005-233131 |
| N | mm.snappy | light-photo | appear | damping | 0.160 | 0.060 | 0.040 | 20261005-233131 |
| N | mm.snappy | light-stripes | appear | response_pct | 29.825 | 10.714 | 7.143 | 20261005-233131 |
| N | mm.snappy | light-stripes | appear | damping | 0.200 | 0.050 | 0.030 | 20261005-233131 |
| RM | mm | dark-photo | disappear | t10_90_ms | 33.333 | 17.000 | 0.000 | 20261005-234750 |
| RM | mm | dark-photo | disappear | response_pct | 29.630 | 12.000 | 8.000 | 20261005-234750 |
| RM | mm | dark-photo | disappear | sharpness | 1.117 | 1.000 | 0.129 | 20261005-234750 |
| RM | mm | dark-photo | appear | sharpness | 1.348 | 1.000 | 0.151 | 20261005-234750 |
| RM | mm | dark-stripes | disappear | settle_ms | 25.000 | 17.000 | 8.333 | 20261005-234750 |
| RM | mm | dark-stripes | appear | response_pct | 16.949 | 5.000 | 3.333 | 20261005-234750 |
| RM | mm | dark-stripes | appear | damping | 0.090 | 0.075 | 0.050 | 20261005-234750 |
| RM | mm | light-photo | appear | response_pct | 32.836 | 6.429 | 4.286 | 20261005-234750 |
| RM | mm | light-photo | appear | damping | 0.260 | 0.060 | 0.040 | 20261005-234750 |
| RM | mm | light-stripes | disappear | response_pct | 30.000 | 19.565 | 13.043 | 20261005-234750 |
| RM | mm | light-stripes | appear | response_pct | 25.862 | 12.500 | 8.333 | 20261005-234750 |
| RM | mm | light-stripes | appear | damping | 0.220 | 0.050 | 0.030 | 20261005-234750 |
| RM | mm.bouncy | dark-photo | disappear | sharpness | 1.366 | 1.000 | 0.197 | 20261005-234750 |
| RM | mm.bouncy | dark-photo | appear | settle_ms | 133.333 | 75.000 | 50.000 | 20261005-234750 |
| RM | mm.bouncy | dark-photo | appear | sharpness | 1.428 | 1.000 | 0.258 | 20261005-234750 |
| RM | mm.bouncy | dark-stripes | appear | t10_90_ms | 33.333 | 25.000 | 16.667 | 20261005-234750 |
| RM | mm.bouncy | dark-stripes | appear | response_pct | 16.667 | 5.000 | 2.500 | 20261005-234750 |
| RM | mm.bouncy | dark-stripes | appear | damping | 0.180 | 0.050 | 0.030 | 20261005-234750 |
| RM | mm.bouncy | light-photo | disappear | response_pct | 9.091 | 6.522 | 4.348 | 20261005-234750 |
| RM | mm.bouncy | light-photo | appear | t10_90_ms | 25.000 | 17.000 | 8.333 | 20261005-234750 |
| RM | mm.bouncy | light-photo | appear | response_pct | 6.667 | 6.383 | 4.255 | 20261005-234750 |
| RM | mm.bouncy | light-photo | appear | damping | 0.100 | 0.050 | 0.020 | 20261005-234750 |
| RM | mm.bouncy | light-stripes | appear | response_pct | 37.500 | 9.184 | 6.122 | 20261006-002206 |
| RM | mm.bouncy | light-stripes | appear | damping | 0.300 | 0.050 | 0.020 | 20261006-002206 |
| RM | mm.snappy | dark-photo | disappear | settle_ms | 25.000 | 17.000 | 8.333 | 20261005-234750 |
| RM | mm.snappy | dark-photo | disappear | response_pct | 26.923 | 12.500 | 8.333 | 20261005-234750 |
| RM | mm.snappy | dark-photo | disappear | sharpness | 1.202 | 1.000 | 0.190 | 20261005-234750 |
| RM | mm.snappy | dark-photo | appear | sharpness | 1.524 | 1.000 | 0.264 | 20261005-234750 |
| RM | mm.snappy | dark-stripes | appear | response_pct | 6.250 | 5.882 | 3.922 | 20261005-234750 |
| RM | mm.snappy | light-photo | appear | response_pct | 26.786 | 7.627 | 5.085 | 20261005-234750 |
| RM | mm.snappy | light-photo | appear | damping | 0.180 | 0.060 | 0.040 | 20261005-234750 |
| RM | mm.snappy | light-stripes | appear | response_pct | 18.000 | 5.000 | 1.961 | 20261005-234750 |
| RM | mm.snappy | light-stripes | appear | damping | 0.110 | 0.060 | 0.040 | 20261005-234750 |

Re-analysis check: three Step 5 cases re-analysed from video in scratch (`reanalyze.py`, normal `.snappy` dark-photo, normal default light-stripes, Reduce Motion `.bouncy` light-stripes) reproduce every stored `motion.*` value exactly.

## 3. Findings

### A1 — major: the class (b) label on b2 (11) and two b4 rows is not proven; a fitted value sets their cause

**Evidence.** Results b2 names the cause as Flutter's progress at fixed visibility depending on the backdrop (dark-photo 0.312 at visibility 0.5 against the table's mean 0.422) and concludes "one table must serve all of them: class (b)". The size and even the sign of that dependence are set by the blur-ramp exponent k, a fitted value. From the Step 4 scan shots themselves (`fitvis.static_rows` on `build/glass_lab/fitvis/20261005-211745/ramp{1..4}.0`, dark-photo progress at v = 0.5 minus the four-backdrop mean):

| k | dark-photo p(0.5) | mean | dark-photo − mean | light-photo − mean | Flutter sharpness at p = 0.5, dark-photo / light-photo (native −1.07 / −1.48) |
|---|---|---|---|---|---|
| 1 | 0.59 | 0.54 | **+0.05** | −0.03 | −2.69 / −2.71 |
| 2 | 0.42 | 0.455 | **−0.05** | +0.02 | −2.63 / −2.62 |
| 3 (chosen) | 0.31 | 0.42 | **−0.11** | +0.045 | −2.61 / −2.36 |
| 4 | 0.26 | 0.40 | −0.14 | +0.06 | −2.53 / −1.86 |

k was chosen by `fitvis.choose_ramp` on sharpness alone. On dark-photo the sharpness at half progress barely moves with k (−2.69 → −2.53), because there the progress projection is mostly the blur itself, so any ramp just moves where p = 0.5 lands. Meanwhile k = 3 doubles dark-photo's progress deviation against k = 1–2. The b2 symptom follows from that deviation: disappear runs ahead, Flutter 0.17 s / 1.13 against native 0.25 / 0.99, and appear lags, 300 against 275 ms. The two b4 rows "default dark-photo appear `settle_ms` 75 > 50" and "`.snappy` dark-photo appear `settle_ms` 33 > 25" are the mirrored appear side of the same deviation. Native's own disappear on dark-photo is not unusual (0.25 / 0.99 against 0.21–0.25 on the other backdrops), so the lead is Flutter's alone.

The same knob also undercuts b3's supporting argument that "the two move in opposite directions across backdrops". At k = 3, Flutter's per-backdrop spread runs opposite to native's (dark-photo behind and light ahead on appear). At k = 1, it has native's sign (dark-photo ahead and light behind, like native's 0.49 s against 0.67 s).

The cost of a lower k is light-photo sharpness, which passes at k = 3 (diff 0.70 measured) and would read about 1.1–1.2 at k = 1–2. So this is a trade-off on one fitted value that nobody has evaluated. A static what-if (`whatif.py`) points the same way: normal-mode timing and spring passes are 75 / 96 at k = 1 against 63 / 96 at k = 3. Its validation against the real k = 3 run is off by 0.05–0.1 s in fitted response, though, so I do not rely on its counts.

Frames: `review2b1-audit/crops/fitvis-blur-ramp-dark-photo.png` (k × visibility sheet, the ramp works as coded), `crops/b1b2-dark-photo-disappear-matched-progress.png`, `crops/b2-dark-photo-disappear-curves.png`.

**Fix.** Reclass b2 (11) and the two dark-photo appear `settle_ms` rows of b4 as "(a) candidate, trade-off with light-photo sharpness, not evaluated". Add a todo item with the deciding measure: re-fit k jointly on sharpness and per-backdrop progress agreement (or run Step 5 with a k = 2 table and count). Drop or qualify b3's "opposite directions" sentence (it is k-dependent).

### A2 — major: the 250 × 44 "native fact" is contradicted by the branch's own N2 recordings on `photo`

**Evidence.** Results Done item 1 row, ROADMAP "Measured native facts" (`git diff d35df87fa abe33abbc -- docs/liquid_glass/ROADMAP.md`) and the todo's "Facts, no action" all record that 250 × 44 grows "about +15.0–15.5 pt" and that "the 17.5 pt law does not hold at 250 × 44". `shapes.summary` on the branch's own `material.press.250x44` noise takes (`press_photo.py`, output `press-photo.txt`) reads:

| Case | Take 0 rest → peak | Take 3 rest → peak |
|---|---|---|
| dark-photo | 251.33 → 268.33 (**+17.00**) | 251.33 → 268.00 (**+16.67**) |
| light-photo | 251.00 → 268.33 (**+17.33**) | 251.00 → 268.33 (**+17.33**) |
| dark-stripes (control) | 252.00 → 266.33 (+14.33) | 252.00 → 266.33 (+14.33) |

On `photo` the peak is 268.0–268.33 pt. On `stripes` it is 266.33 pt, about 2 pt short, which is more than the ±0.67 pt per edge that ruling 1 and gotcha 35 give the blind band. Even taking the `stripes` rest (252.0, not in band) against the `photo` peak, growth is about 16.0–16.3 pt, not 15.0–15.5. The `photo` rest boxes are flagged in band, so they may read up to 0.67 pt short.

**Fix.** Replace the fact with: "On `photo`, L1 reads +16.7 to +17.3 pt at 250 × 44 (N2 noise takes), within about 1 pt of the spike's law. The `stripes` reading of +14.33 is L1's blind band, which cost about 2 pt at the capsule ends." Correct gotcha 35's ±0.67 pt bound. Done item 1 can cite N2 `photo` as this number's reproduction. Fix it in results, todo, ROADMAP and the plan's ruling 2 cross-references.

### A3 — minor: the default-spring "native fact" overstates a fit the data cannot resolve

**Evidence.** `springcheck.py` reproduces `fit.json` exactly (pooled 0.58 / 0.99; per case 0.59 / 0.98, 0.71 / 0.80, 0.50 / 1.14, 0.44 / 1.30). The grid runs 0.30–0.80 s and 0.40–1.40, so this is not a grid-edge fit.

The error surface is flat. Pooled RMS with the best damping at each response:

| Response | 0.55 | 0.56 | 0.57 | 0.58 | 0.59 |
|---|---|---|---|---|---|
| RMS | 0.02858 | 0.02852 | 0.02848 | 0.02846 | 0.02847 |

The "5.5 % off, `pass: false`" verdict therefore rests on an RMS difference of 0.00002 between 0.57 (passes) and 0.58 (fails). The 5.5 % is 0.58 / 0.55 − 1 = 5.45 %, rounded; the arithmetic is honest.

Per recording group, with no load dependence:

| Group | Load | Pooled spring |
|---|---|---|
| Session 1 | 13–42 | 0.58 / 1.00 |
| Session 2 | 67–161 | 0.59 / 0.94 |
| Task 8 | about 45 | 0.58 / 1.01 |
| Step 5 native | 11–20 | **0.57 / 0.98, `pass: true`** |
| 2A `LG-20260930-082046` | — | 0.58 / 0.96 |
| Prototype | — | 0.59 / 0.97 |

The per-case fits are stable across all of these groups (dark-stripes 0.69–0.73, light-stripes 0.44–0.46), so the backdrop dependence is systematic. That contradicts the results' reason, that "one take's fitted spring varies by more than the tolerance between takes of one case".

**Fix.** Restate it as: "Pooled native default fits 0.57–0.59 s / 0.94–1.01 in every recording group, consistent with SwiftUI's 0.55 / 1.0 within the fit's resolution (flat error surface). The lab's progress measure gives systematically different springs per backdrop." No action changes.

### A4 — major: a1's class (a) is right, but its mechanism is wrong and its candidate fix would make it worse

**Evidence (1): the fitted gain does not track overshoot.** `gaincheck.py` runs `fitvis.fit_gain` per case on the same `.bouncy` curves that produced the pooled gains, from the Step 4 inputs:

| Case | Normal gain | Reduce Motion gain |
|---|---|---|
| dark-photo | 0.14 | 0.44 |
| dark-stripes | **1.5 (grid ceiling)** | **1.5 (ceiling)** |
| light-photo | **0.0 (floor)** | 0.18 |
| light-stripes | **0.0 (floor)** | **0.0 (floor)** |

Native's overshoot is largest on `light` (2.45–2.54 %), yet `light` fits gain 0. The gain absorbs the curve-shape mismatch of b3, not the overshoot. The pooled 0.36 and 0.62 are not on a grid edge, and they are stable across sessions (normal: session 1 0.38, session 2 0.32, Task 8 0.36, Step 5 0.34). They are, however, compromises between per-case fits pinned at both edges.

The todo's candidate, "a per-appearance appear gain fitted by `fitvis`", would therefore fit `light` at 0.0. That removes Flutter's overshoot on `light`, the opposite of what a1 needs (native 2.5 %, outside the 2 % settle band).

**Evidence (2): Flutter realises only part of the targeted overshoot.** Bouncy appear overshoot, native against Flutter, from the Step 5 `result.json` files:

| Case | Normal | Reduce Motion |
|---|---|---|
| dark-photo | 1.48 / 1.02 | 3.00 / 1.81 |
| dark-stripes | 2.10 / 1.35 | 3.61 / 2.27 |
| light-photo | 2.54 / 1.54 | 3.52 / 2.41 |
| light-stripes | 2.45 / 1.25 | 3.80 / 2.29 |

Flutter shows 0.51–0.69 × native's overshoot in all eight pairs, so the shortfall is uniform, not appearance-dependent. The SwiftUI `.bouncy` spring overshoots 4.6 %. The fitted gains therefore target 0.36 × 4.6 = 1.66 % (normal) and 0.62 × 4.6 = 2.85 % (Reduce Motion). Flutter realises 1.02–1.54 % and 1.81–2.41 %, so about 40 % is lost between the target and the pixels, through the table extrapolation above 1 and Flutter's progress above visibility 1.

Reduce Motion dark-photo, one of a1's three rows, already has a target matching native (2.85 against 3.0 %). A per-appearance gain fitted on native curves would not fix it.

The settle failures occur exactly where native's overshoot is above the 2 % settle band and Flutter's is below it. Where both are above (Reduce Motion dark-stripes, light-*), settle passes. That is why `settle_ms` jumps by 100–160 ms.

**Fix.** Keep class (a). Replace the todo candidate with: "fit the gain on the overshoot peak, not on the whole curve; fit it against Flutter's realised overshoot (or scan visibility above 1 and extend the table); then decide per appearance for normal `light` (native 2.5 % against 1.5–2.1 % on `dark`)". Record the per-case edge fits as a fit defect next to the `table_source` item. Note the 2 % band sensitivity.

### A5 — minor: the stall repeats are legitimate per case, but one repeat swapped out a failure in an event that had no stall

**Evidence.** Gap locations from re-analysing the original cases from video (`reanalyze.py`):

- Normal default light-stripes: one Flutter gap of 26.7 ms at +427 ms in the appear, at travel 0.958 → 0.961. It is in the tail. The count is unchanged (12 → 12).
- Normal `.snappy` dark-photo: 31.7 ms at travel 0.991 → 0.996 in the disappear, and 25.0 ms at 0.828 → 0.876 in the appear. The repeat is worse (11 → 10) and was kept.
- Reduce Motion `.bouncy` light-stripes: 30.0 ms at +97 ms in the disappear, at travel 0.63 → 0.755, a genuine mid-event stall. The appear had none.

The repeat (12 / 14) turned two failures into passes:

- the disappear's `response_pct` 19.05 > 18.75, in the stalled event (legitimate);
- the appear's `t10_90_ms` 41.7 > 25.0, in an event with no stall.

Counts:

| | Normal | Reduce Motion |
|---|---|---|
| As first run | 130 | 133 |
| Repeats substituted per case (claimed) | 129 | 135 |
| Repeats substituted per stalled event | 129 | **134** |

The unused cases of repeat `20261006-001644` show the Flutter side's run-to-run variance that no floor carries. `.bouncy` light-stripes appear `t10_90` is 41.7 (fail) in one run and passes in the other; its disappear `damping` passes, then fails. Both runs total 9 / 14.

**Fix.** Report 134 as the per-event figure, or state that substitution is per case. Say that two of the three "stalls" sit at 96–99 % of travel.

### A6 — minor: `noise.json` depends on take numbering, so the claim "noise.json does not depend on take numbers" is false

**Evidence.** `response_pct` is |n − f| / n with "native" = the lower take number (`lab.py` `case_noise`), so it is asymmetric. After ruling 8 renumbered 5 → 3, re-analysing the takes in their current order gives values that differ from the stored `noise.json` (`nr-*.txt`):

| Case | Measure | Recomputed | `noise.json` |
|---|---|---|---|
| `.bouncy` dark-photo-RM | step1 `progress.response_pct` | 23.08 | 25.0 |
| `.bouncy` dark-photo-RM | step3 `progress.response_pct` | 21.62 | 25.0 |
| `.bouncy` dark-stripes-RM | step1 `progress.response_pct` | 16.67 | 20.0 |
| default light-stripes | step3 width / height `response_pct` | 46.7 / 85.7 | 57.1 / 116.7 |

No item 4 verdict changes: 30.77 < 34.6, 24.32 < 32.4, 4.55 < 25.0.

**Fix.** Take the noise of the asymmetric measures over both orientations (or the symmetric |n − f| / mean), recompute `noise.json`, and correct the sentence in results "Deviations 2".

### A7 — minor: the replacement takes loosened item-4 limits; this is not disclosed

**Evidence.** I recomputed the limits from the pair results with only the four retained original takes, and with the replacements (`noise_variants.py`, `noise-four_takes.json`). In those four cases the replacements, recorded in a third session at load 100–300, loosen limits:

| Case | Event | Measure | Four retained takes | With the replacement |
|---|---|---|---|---|
| default light-stripes | disappear | `damping` | 0.12 | 0.375 |
| default light-stripes | disappear | `response_pct` | 19.6 | 39.1 |
| `.bouncy` dark-photo-RM | appear | `settle_ms` | 50 | 75 |
| `.bouncy` dark-photo-RM | appear | `response_pct` | 27.3 | 37.5 |
| `.bouncy` dark-photo-RM | appear | `damping` | 0.075 | 0.12 |
| `.bouncy` dark-stripes-RM | disappear | `response_pct` | 13.6 | 30 |
| `.bouncy` dark-stripes-RM | disappear | `damping` | 0.075 | 0.15 |
| `.bouncy` light-stripes-RM | appear | `settle_ms` | 25 | 37.5 |

The exclusions themselves tightened `t10_90`, `settle` and `rms` (for example light-stripes `t10_90` 112.5 → 17).

Item 4 with these alternatives (`rc-noise-*.txt`):

| Noise | Normal substituted | Reduce Motion substituted |
|---|---|---|
| Four retained takes | 129 | 135 |
| All five original takes, excluded ones included (`7c67ed4f1`) | 129 | 135 |
| All six takes | 129 | 135 |

Only the Reduce Motion first run gains one pass with the excluded takes in (134): the `.bouncy` light-stripes disappear `response_pct`, a case the repeat replaced anyway.

**Fix.** Disclose this in Deviations 2. Note that these four cases' takes span three sessions.

### A8 — minor: the `.snappy` gain sits on the grid floor although native overshoots

**Evidence.** `fit.json` gives `.snappy` gain 0.0 with `at_floor` in both modes, and every per-take value is 0.0. The plan exempts `at_floor` only when native does not overshoot. Native `.snappy` appear overshoots in every noise take, while the default (no overshoot) reads 0.00–0.05 %:

| | Native `.snappy` appear overshoot |
|---|---|
| Normal | 0.23–0.42 % (20 takes) |
| Reduce Motion | 0.28–0.54 % |

The SwiftUI `.snappy` spring overshoots 0.63 %. No measure fails, since the `overshoot_pct` limit is 2.

**Fix.** List it in the todo as a floor fit (gain unidentifiable at this overshoot), not as "native not overshooting".

### A9 — minor: `material.edge`'s mechanism is proven; "pre-existing" is not, and the class and size are wrong

**Evidence.**
- I re-verified byte for byte:
  - 2A `20261002-152214` = `20261002-202042`;
  - probe `20261006-020852` (no `render()`) = 2A;
  - probe `20261006-021029` = the Step 7 run `20261006-005342`;
  - every difference lies in x 976–1159, y 183–319 px (the "Edit" pill).
- `git diff 7e318a49f d35df87fa` and `6be5e3ff1 d35df87fa` over the package lib, example lib and app lib are empty. The 2A runs are therefore `development`'s code, and `development` at `d35df87fa` produces 2A's unsnapped frames. A new simulator run of `d35df87fa` would only repeat that, so it was not decisive and I did not make one.
- The `render()` path at `render_liquid_glass_geometry.dart:244` and the nearest `drawImage` are unchanged since `d35df87fa`, so the fault is latent there. No run shows it on pre-2B.1 code, though. The frame change is introduced by 2B.1 (ruling 30).
- My sub-pixel fit of the rim profiles (linear interpolation, rows 215–290) gives a left shift of 0.155–0.160 px on both side rims, 0.000 on top and bottom. That matches the pill's fractional offset of 0.164 px (x = 973.164), where nearest sampling should land. The results' 0.235–0.249 px is the less consistent estimate.
- Crop: `review2b1-audit/crops/edge-automatic-dark-ready-2A-new-diffx8.png` (2A | new | difference × 8, 3× nearest).

**Fix.** Reword in results and todo: "2B.1 changes all 12 `material.edge` Flutter frames by a 0.16 px rim shift (a renderer defect, latent in the fork's geometry cache since before 2A, exposed by ruling 30); Done item 5 passes on its measure definition." Change the class from (b) to "defect".

### A10 — minor for 2B.1, must-do before 2B.3: the drift tracks the pre-reboot session, not load, and N1/N2 presses are not the scripted 1.0 s

**Evidence.** Per-take native features from the noise pair results (`take_features.py`; 24 scene × case groups):

| Comparison | Appear `t10_90` | Appear `settle` | Disappear `t10_90` | Disappear first-frame gap |
|---|---|---|---|---|
| Session 2 (load 67–161) − session 1 (13–42) | **−12.3 ms** (sd 6.1) | −15.2 ms | −1.1 ms | +14 ms |
| Step 5 (load 11–20) − session 2 | −0.5 ms | — | +1.2 ms | — |

2A's `LG-20260930-082046` (275 / 275 / 292 / 292 appear) agrees with session 2 and Step 5. Session 1 (300–308 ms on most cases), the lowest-load session, is the outlier. It ran before the simulator reboot, on a Mac then up nine days.

Press touch windows (`task-9-scan.md`, scripted 1.0 s), and native fits by group:

| | Session 1 | Session 2 | Task 8, same pre-reboot boot |
|---|---|---|---|
| Press hold median | **3.26 s** (0.88–4.59) | 0.97 s (0.85–1.31) | N1 2.13 and 2.87 s, N2 1.54 s |
| Default exponent per take | 3.1–3.15 | 3.1–3.2 | — |
| Pooled default spring | 0.58 | 0.59 | 0.58 (Step 5 0.57) |

Mid-event native stalls are 8 % (session 1) and 9 % (session 2) of takes, so they do not track load either. Load does correlate with capture holes: 4 of 48 session-2 materialize takes against 0 of 72 in session 1; those takes were excluded.

**Fix.** No re-recording is needed before merge. Correct results "Deviations 1/3": the long holds and the slow session-1 appear come from the pre-reboot simulator, not from load. Add a todo item for 2B.3: re-record N1, N2 and the press/interactive noise takes after a fresh simulator boot, and check that the holds read about 1.0 s.

## 4. The nine points

**1. Done item 4 table.**
- My own script reproduces every count: 129 / 168 / 168 and 135 / 168 / 168 with the repeats, 130 / 133 as first run, gates 120 / 120.
- Judged = expected = 168 per run, and every pair and measure is present (no `inf`).
- Every limit is max(fixed, 1.5 × noise) with `noise.json` at `fd30f969d`, which the runs loaded (`result.json` written 2026-10-06 00:04, after `fd30f969d`): 0 mismatches.
- The full failing list is in section 2.

**2. Stall repeats.**
- Three cases were repeated, all for Flutter gaps over 25 ms flagged by `align.stalls`: normal default light-stripes, normal `.snappy` dark-photo, Reduce Motion `.bouncy` light-stripes.
- Gap locations are in A5. Each original had a Flutter gap inside an event, two of them in the last 1–4 % of travel.
- Only the Reduce Motion `.bouncy` repeat turned failures into passes: two, one of them in an unstalled event.
- Counts: 130 / 133 before, 129 / 135 with per-case substitution, 129 / 134 with per-event substitution.

**3. Noise floors.**
- Recomputed from video, `noise.json` matches exactly in five cases: default dark-photo (dark), `.snappy` light-stripes (light), `.bouncy` dark-photo-RM (except A6), `press.250x44` dark-stripes and `spacing.40.b` light-photo. It also matches the stored pair results in all 60 cases (`noise_variants.py`).
- The exclusion rule (gap > 30 ms in either of an event's first two gaps, and ≥ 2 sub-5 ms gaps in the next 10, `task9scan/report.py`) is objective. It was applied to all 120 materialize takes and all press and interactive takes, and flags exactly the four excluded materialize takes. The 24 press and interactive takes it flags were kept with a stated reason, since no press measure is judged in 2B.1. The rule was written after the outliers were seen.
- The renumbering changed no stored value but makes `noise.json` irreproducible for asymmetric measures (A6).
- The exclusions tightened, and the replacements loosened, several item-4 limits (A7). No item-4 verdict changes with the excluded takes put back.

**4. Recording under load.** Load did not bias the native references, the fitted values or the floors' level; what varies is the session. The pre-reboot session 1 reads appear about 12 ms slower and presses about 3 × longer; Step 5, at low load, agrees with loaded session 2 and with 2A. Load did produce capture holes, which were excluded. No re-recording is needed before merge; N1 and N2 should be re-recorded after a fresh boot before 2B.3 (A10).

**5. Item 1.**
- `reproduce.py` re-run in scratch on byte-verified copies is byte-identical to `task-6-reproduce.txt` and `proto-2b1/reproduce.txt`. Against the plan's known numbers:
  - disappear 117–133 ms passes;
  - appear 275 / 275 / 292 / 292 ms: two are 10 ms under 285, inside the 25 / 33.3 ms noise;
  - v13 +12.00 / +4.66 passes;
  - `button.press` +16.00 in all six runs passes;
  - menu 0.26–0.30 / 0.74–0.81 passes.
- Ruling 2: +14.33 is reproduced on `stripes`, but its explanation and the "law does not hold" conclusion are wrong (A2).

**6. Still glass.**
- `still_audit.py` recomputes all nine scenes, re-analysing both 2A and new runs with the branch harness; the stored values are confirmed. 112 / 124 Flutter frames are byte-identical, `missing` 0, `worse` 0 under still_check's definition.
- With no flutter-change gate and no noise allowance, only `tabbar.rest` light-stripes moves, by 0.0001 on an already-failing measure, with an identical Flutter frame (a native change, ruling 28).
- No static measure got worse by more than its noise.
- Edge cause proven for the branch; "pre-existing" is not shown; the shift is 0.16 px, not 0.24 (A9).

**7. Class (b) diagnoses.** Each was checked against my own crops at matched progress (`crops/b1b2-*`, `crops/b3-*`) and the curves (`crops/*-curves.png`).
- **b1, half-progress sharpness on dark `photo`: (b) supported.** At matched travel, native's shapes are already crisp by 26 % of the disappear, while its rim and lens bands stay strong. Flutter stays blurred. The k-sweep shows dark-photo sharpness at p = 0.5 is insensitive to k (−2.69 → −2.53), because on dark-photo the progress projection is mostly blur. The missing mid-transition rim and edge terms (rulings 13 and 14) are the plausible model cause.
- **b2, the dark `photo` disappear: not proven (A1).** A fitted value (k) sets the dark-photo progress deviation that the results name as the cause.
- **b3, spring shape on `light-stripes`: plausible, not proven.** At matched progress, native shows the lens shift and soft edge that Flutter lacks (`crops/b3-light-stripes-appear-matched-progress.png`). The curves (`crops/b3-light-stripes-appear-curves.png`) show Flutter ahead by about 35–50 ms through the middle, with the same shape. Native has a slow first 30–40 ms, which a spring fit with no lag term turns into response and damping error. The "opposite directions" argument is k-dependent (A1).
- **b4:** the four `.bouncy` appear `t10_90` rows are (b) by ruling 10. The SwiftUI `.bouncy` spring's own 10–90 time is 169 ms; Flutter reads 158–175 ms and native 133–150 ms. The two dark-photo appear `settle` rows belong with b2.
- **a1:** class (a) is right; the mechanism is wrong and the candidate fix would worsen it (A4).

**8. Native spring fact.**
- Pooled 0.58 / 0.99 and the per-case values recompute exactly.
- It is not a grid-edge fit (grid 0.30–0.80 s / 0.40–1.40).
- The 5.5 % is 5.45 % rounded, so the arithmetic is honest, but it is below the fit's resolution: a flat surface, with 0.57 within 0.00002 RMS. Step 5's native alone passes.
- Restate it (A3).

**9. Fitted table.**
- `ios27_motion.dart` at `abe33abbc` is byte-identical to `fitvis.table_source(fit.json)`.
- `fit.json` is byte-identical to `build/glass_lab/fitvis/20261005-211745/fit.json` (the post-renumbering fit: takes 0–4, no take 5), committed as `58ab57e0c`, and unchanged since.
- No value is the writer's 1.0 default: every exponent and gain is a fitted or INERT value, and the default gain is 0.0 from INERT.
- No exponent, gain or ramp is at a grid edge: exponents 2.65–3.1 on 1–6; gains 0.36 and 0.62 on 0–1.5; k = 3 is interior, with errors 1.14 / 0.92 / 0.84 / 0.97.
- The one floor value, `.snappy` gain 0.0 `at_floor`, is flagged but mis-justified (A8).
- The `.bouncy` pooled gains (0.36, 0.62) are off the edges, but the same fit per case is pinned at the ceiling (1.5, dark-stripes) and the floor (0.0, `light`) in both modes. The 2A "fit stuck at a grid edge" lesson recurs one level down (A4).

## Files

Everything is under `scratchpad/review2b1-audit/`:
- scripts: `recompute.py`, `reanalyze.py`, `noise_variants.py`, `noise_recheck.py`, `still_audit.py`, `fitcurves.py`, `springcheck.py`, `whatif.py`, `diag_crops.py`, `press_photo.py`, `take_features.py`, `gaincheck.py`;
- outputs: `recompute-fd30.txt`, `rc-noise-*.txt`, `nr-*.txt`, `still-audit.txt`, `reproduce-audit.txt`, `press-photo.txt`, `springcheck.txt`, `gaincheck.txt`, `whatif.txt`, `take_features.json`, `failing-table.md`;
- crops: `crops/`.

The bulky copied videos and frames were deleted after use. No simulator recording was made. The load average during this audit reached 100–270 from the audit's own analysis jobs, which is a further reason no recording was attempted.
