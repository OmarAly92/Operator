# 2B.1 part 2: every noise limit that moved

`noise.json` recomputed at `86d1124f1` by `lab.case_noise` (canonical take order, A6) over every case of `noise-2b1/takes` (new session 1 from the 2026-10-06 08:52 boot, session 2 kept or replaced after the 11:31 boot), against `noise.json` at `fd30f969d`. A limit is max(fixed threshold, 1.5 × noise) (`shapes.limits`, `analyze.limit`); a row is listed when that limit changed. "Judged in item 4" marks the seven `block.step{1,3}e0.progress.*` measures of the three materialize scenes. Measures absent from one side read noise 0. Written by `disclosure.py` (main session scratch).

Counts: 1089 limits moved, 561 tighter and 415 looser among measures 2B.1 does not judge (press, interactive, width, height, centre, luma), and **59 tighter and 54 looser among the 168 × 2 judged item-4 limits** (some judged names moved in both runs' cases; each row is one scene, case and measure). Static and topology floors did not move (every take's static `mad` 0.00; the six spacing scenes' entries are byte-identical).

The largest judged loosenings and their cause, read from the pair results under `noise-2b1/<scene>/<case>/pair-*/result.json`:
- default `light-photo-reduce-motion` disappear (`step1e0`): `response_pct` 14.29 → 223.8, `settle_ms` 8.33 → 100, `damping` 0.11 → 0.38. Every pair with new take 2 reads 196–224 % and 100 ms; no other pair exceeds 8.7 %. Take 2's disappear onset is read 98 ms before its first moving frame: after a 378 ms idle gap the first changed frame and the next (53 ms later) still read progress 0.981, then the descent matches take 1's frame for frame (0.939, 0.79, 0.639, 0.522 …). The take passes the outlier rule (no burst) and the touch gate, so it stays; item 4 is also counted without it (`results-2b1.md`).
- `.bouncy` `dark-stripes` appear `settle_ms` 50 → 150: pairs with new take 2 read 108–150 ms, the others 0–42; take 2's appear differs from take 1's by 0.02–0.03 of progress at +17 to +132 ms, enough to move a 2 % settle band on a 5 % overshoot. A real native variation.
- `.snappy` `dark-photo-reduce-motion` appear `response_pct` 18.6 → 53.5: pair 3-2 (old session 2 take 3 against new take 2); the other pairs 0–29.4.
- default `light-stripes` disappear `response_pct` 26.1 → 41.2: pair 3-0 (the Task 9 replacement against new take 0).

| Scene | Case | Measure | Old noise | New noise | Old limit | New limit | Direction | Judged in item 4 |
|---|---|---|---|---|---|---|---|---|
| material.interactive | dark-photo | glass.step1e0.height.peak_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.interactive | dark-photo | glass.step1e0.height.response_pct | 10.87 | 9.524 | 16.3 | 14.29 | tighter |  |
| material.interactive | dark-photo | glass.step1e0.height.settle_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.interactive | dark-photo | glass.step1e0.luma.peak_ms | 91.67 | 50 | 137.5 | 75 | tighter |  |
| material.interactive | dark-photo | glass.step1e0.width.peak_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.interactive | dark-photo | glass.step1e0.width.response_pct | 10.87 | 11.9 | 16.3 | 17.86 | looser |  |
| material.interactive | dark-photo | glass.step1e0.width.settle_ms | 16.67 | 33.33 | 25 | 50 | looser |  |
| material.interactive | dark-photo | glass.step1e1.height.damping | 0.16 | 0.04 | 0.24 | 0.06 | tighter |  |
| material.interactive | dark-photo | glass.step1e1.height.overshoot_pct | 8.333 | 0 | 12.5 | 2 | tighter |  |
| material.interactive | dark-photo | glass.step1e1.height.peak_ms | 83.33 | 0 | 125 | 17 | tighter |  |
| material.interactive | dark-photo | glass.step1e1.height.response_pct | 203.8 | 9.375 | 305.8 | 14.06 | tighter |  |
| material.interactive | dark-photo | glass.step1e1.luma.damping | 1.07 | 1.19 | 1.605 | 1.785 | looser |  |
| material.interactive | dark-photo | glass.step1e1.luma.peak_ms | 58.33 | 191.7 | 87.5 | 287.5 | looser |  |
| material.interactive | dark-photo | glass.step1e1.luma.response_pct | 78.48 | 68.42 | 117.7 | 102.6 | tighter |  |
| material.interactive | dark-photo | glass.step1e1.luma.settle_ms | 66.67 | 16.67 | 100 | 25 | tighter |  |
| material.interactive | dark-photo | glass.step1e1.width.damping | 0.11 | 0.05 | 0.165 | 0.075 | tighter |  |
| material.interactive | dark-photo | glass.step1e1.width.overshoot_pct | 4.118 | 0 | 6.176 | 2 | tighter |  |
| material.interactive | dark-photo | glass.step1e1.width.peak_ms | 100 | 0 | 150 | 17 | tighter |  |
| material.interactive | dark-photo | glass.step1e1.width.response_pct | 263.6 | 12.9 | 395.5 | 19.35 | tighter |  |
| material.interactive | dark-photo | glass.step1e1.width.settle_ms | 25 | 8.333 | 37.5 | 17 | tighter |  |
| material.interactive | dark-photo | glass.step1e2.luma.peak_ms | 183.3 | 191.7 | 275 | 287.5 | looser |  |
| material.interactive | dark-photo | glass.step1e2.luma.settle_ms | 100 | 25 | 150 | 37.5 | tighter |  |
| material.interactive | dark-photo | glass.step3e0.height.damping | 0.05 | 0.03 | 0.075 | 0.05 | tighter |  |
| material.interactive | dark-photo | glass.step3e0.height.peak_ms | 8.333 | 33.33 | 17 | 50 | looser |  |
| material.interactive | dark-photo | glass.step3e0.height.response_pct | 25.53 | 26.32 | 38.3 | 39.47 | looser |  |
| material.interactive | dark-photo | glass.step3e0.height.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.interactive | dark-photo | glass.step3e0.luma.overshoot_pct | 1.587 | 0.5638 | 2.381 | 2 | tighter |  |
| material.interactive | dark-photo | glass.step3e0.luma.peak_ms | 66.67 | 41.67 | 100 | 62.5 | tighter |  |
| material.interactive | dark-photo | glass.step3e0.luma.settle_ms | 150 | 16.67 | 225 | 25 | tighter |  |
| material.interactive | dark-photo | glass.step3e0.width.damping | 0.11 | 0.07 | 0.165 | 0.105 | tighter |  |
| material.interactive | dark-photo | glass.step3e0.width.peak_ms | 8.333 | 33.33 | 17 | 50 | looser |  |
| material.interactive | dark-photo | glass.step3e0.width.response_pct | 34.37 | 20.51 | 51.56 | 30.77 | tighter |  |
| material.interactive | dark-photo | glass.step3e1.height.damping | 0.04 | 0.07 | 0.06 | 0.105 | looser |  |
| material.interactive | dark-photo | glass.step3e1.height.peak_ms | 8.333 | 33.33 | 17 | 50 | looser |  |
| material.interactive | dark-photo | glass.step3e1.height.response_pct | 13.33 | 15.62 | 20 | 23.44 | looser |  |
| material.interactive | dark-photo | glass.step3e1.height.settle_ms | 16.67 | 33.33 | 25 | 50 | looser |  |
| material.interactive | dark-photo | glass.step3e1.luma.damping | 0.01 | 0.39 | 0.05 | 0.585 | looser |  |
| material.interactive | dark-photo | glass.step3e1.luma.peak_ms | 191.7 | 58.33 | 287.5 | 87.5 | tighter |  |
| material.interactive | dark-photo | glass.step3e1.luma.response_pct | 12.12 | 37.5 | 18.18 | 56.25 | looser |  |
| material.interactive | dark-photo | glass.step3e1.luma.settle_ms | 191.7 | 33.33 | 287.5 | 50 | tighter |  |
| material.interactive | dark-photo | glass.step3e1.width.damping | 0.07 | 0.08 | 0.105 | 0.12 | looser |  |
| material.interactive | dark-photo | glass.step3e1.width.response_pct | 16.67 | 20 | 25 | 30 | looser |  |
| material.interactive | dark-photo | glass.step3e1.width.settle_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.interactive | dark-photo | glass.step3e2.luma.peak_ms | 200 | 291.7 | 300 | 437.5 | looser |  |
| material.interactive | dark-photo | glass.step3e2.luma.settle_ms | 125 | 291.7 | 187.5 | 437.5 | looser |  |
| material.interactive | dark-photo | step1e0.delay_ms | 11.67 | 20 | 17.5 | 30 | looser |  |
| material.interactive | dark-photo | step1e1.delay_ms | 2263 | 33.33 | 3395 | 50 | tighter |  |
| material.interactive | dark-photo | step1e2.delay_ms | 2318 | 21.67 | 3478 | 32.5 | tighter |  |
| material.interactive | dark-photo | step3e0.delay_ms | 11.67 | 25 | 17.5 | 37.5 | looser |  |
| material.interactive | dark-photo | step3e1.delay_ms | 3357 | 36.67 | 5035 | 55 | tighter |  |
| material.interactive | dark-photo | step3e2.delay_ms | 3432 | 350 | 5148 | 525 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.height.damping | 0.29 | 0.12 | 0.435 | 0.18 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.height.peak_ms | 108.3 | 33.33 | 162.5 | 50 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.height.response_pct | 414.3 | 30.56 | 621.4 | 45.83 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.height.settle_ms | 208.3 | 141.7 | 312.5 | 212.5 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.luma.overshoot_pct | 2.237 | 1.067 | 3.356 | 2 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.luma.peak_ms | 66.67 | 33.33 | 100 | 50 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.luma.settle_ms | 100 | 33.33 | 150 | 50 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.progress.rms | 0.06107 | 0.02748 | 0.0916 | 0.05 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.progress.settle_ms | 75 | 25 | 112.5 | 37.5 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.progress.t10_90_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.width.damping | 0.36 | 0.02 | 0.54 | 0.05 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.width.peak_ms | 108.3 | 33.33 | 162.5 | 50 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.width.response_pct | 428.6 | 27.03 | 642.9 | 40.54 | tighter |  |
| material.interactive | dark-stripes | glass.step1e0.width.settle_ms | 125 | 50 | 187.5 | 75 | tighter |  |
| material.interactive | dark-stripes | glass.step1e1.height.damping | 0.16 | 1.09 | 0.24 | 1.635 | looser |  |
| material.interactive | dark-stripes | glass.step1e1.height.peak_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.interactive | dark-stripes | glass.step1e1.height.response_pct | 61.11 | 68.97 | 91.67 | 103.4 | looser |  |
| material.interactive | dark-stripes | glass.step1e1.height.settle_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.interactive | dark-stripes | glass.step1e1.luma.peak_ms | 308.3 | 83.33 | 462.5 | 125 | tighter |  |
| material.interactive | dark-stripes | glass.step1e1.luma.settle_ms | 358.3 | 41.67 | 537.5 | 62.5 | tighter |  |
| material.interactive | dark-stripes | glass.step1e1.progress.rms | 0.6219 | 0.04938 | 0.9328 | 0.07408 | tighter |  |
| material.interactive | dark-stripes | glass.step1e1.progress.settle_ms | 341.7 | 41.67 | 512.5 | 62.5 | tighter |  |
| material.interactive | dark-stripes | glass.step1e1.progress.t10_90_ms | 300 | 25 | 450 | 37.5 | tighter |  |
| material.interactive | dark-stripes | glass.step1e1.width.damping | 0.06 | 0.05 | 0.09 | 0.075 | tighter |  |
| material.interactive | dark-stripes | glass.step1e1.width.response_pct | 29.17 | 24 | 43.75 | 36 | tighter |  |
| material.interactive | dark-stripes | glass.step1e1.width.settle_ms | 25 | 33.33 | 37.5 | 50 | looser |  |
| material.interactive | dark-stripes | glass.step1e2.luma.peak_ms | 91.67 | 175 | 137.5 | 262.5 | looser |  |
| material.interactive | dark-stripes | glass.step1e2.luma.settle_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.interactive | dark-stripes | glass.step1e2.progress.settle_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.interactive | dark-stripes | glass.step3e0.height.damping | 0.17 | 0.16 | 0.255 | 0.24 | tighter |  |
| material.interactive | dark-stripes | glass.step3e0.height.peak_ms | 41.67 | 25 | 62.5 | 37.5 | tighter |  |
| material.interactive | dark-stripes | glass.step3e0.height.response_pct | 33.33 | 20 | 50 | 30 | tighter |  |
| material.interactive | dark-stripes | glass.step3e0.height.settle_ms | 183.3 | 250 | 275 | 375 | looser |  |
| material.interactive | dark-stripes | glass.step3e0.luma.overshoot_pct | 2.055 | 2.386 | 3.082 | 3.578 | looser |  |
| material.interactive | dark-stripes | glass.step3e0.luma.peak_ms | 50 | 16.67 | 75 | 25 | tighter |  |
| material.interactive | dark-stripes | glass.step3e0.luma.settle_ms | 50 | 25 | 75 | 37.5 | tighter |  |
| material.interactive | dark-stripes | glass.step3e0.progress.rms | 0.04669 | 0.01905 | 0.07004 | 0.05 | tighter |  |
| material.interactive | dark-stripes | glass.step3e0.progress.settle_ms | 50 | 25 | 75 | 37.5 | tighter |  |
| material.interactive | dark-stripes | glass.step3e0.width.damping | 0.04 | 0.07 | 0.06 | 0.105 | looser |  |
| material.interactive | dark-stripes | glass.step3e0.width.overshoot_pct | 0 | 3.025 | 2 | 4.538 | looser |  |
| material.interactive | dark-stripes | glass.step3e0.width.peak_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.interactive | dark-stripes | glass.step3e0.width.response_pct | 28.89 | 27.5 | 43.33 | 41.25 | tighter |  |
| material.interactive | dark-stripes | glass.step3e0.width.settle_ms | 41.67 | 150 | 62.5 | 225 | looser |  |
| material.interactive | dark-stripes | glass.step3e1.height.damping | 1.2 | 1.09 | 1.8 | 1.635 | tighter |  |
| material.interactive | dark-stripes | glass.step3e1.height.peak_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.interactive | dark-stripes | glass.step3e1.height.response_pct | 262.5 | 233.3 | 393.7 | 350 | tighter |  |
| material.interactive | dark-stripes | glass.step3e1.height.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.interactive | dark-stripes | glass.step3e1.width.damping | 0.05 | 0.09 | 0.075 | 0.135 | looser |  |
| material.interactive | dark-stripes | glass.step3e1.width.overshoot_pct | 1.905 | 4.762 | 2.857 | 7.143 | looser |  |
| material.interactive | dark-stripes | glass.step3e1.width.response_pct | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.interactive | dark-stripes | glass.step3e1.width.settle_ms | 25 | 33.33 | 37.5 | 50 | looser |  |
| material.interactive | dark-stripes | glass.step3e2.luma.peak_ms | 233.3 | 91.67 | 350 | 137.5 | tighter |  |
| material.interactive | dark-stripes | step1e0.delay_ms | 13.33 | 15 | 20 | 22.5 | looser |  |
| material.interactive | dark-stripes | step1e1.delay_ms | 2487 | 20 | 3730 | 30 | tighter |  |
| material.interactive | dark-stripes | step1e2.delay_ms | 2392 | 28.33 | 3588 | 42.5 | tighter |  |
| material.interactive | dark-stripes | step3e0.delay_ms | 6.666 | 18.33 | 17 | 27.5 | looser |  |
| material.interactive | dark-stripes | step3e1.delay_ms | 3002 | 11.67 | 4503 | 17.5 | tighter |  |
| material.interactive | dark-stripes | step3e2.delay_ms | 2983 | 25 | 4475 | 37.5 | tighter |  |
| material.interactive | light-photo | glass.step1e0.height.damping | 0.04 | 0.01 | 0.06 | 0.05 | tighter |  |
| material.interactive | light-photo | glass.step1e0.height.peak_ms | 41.67 | 16.67 | 62.5 | 25 | tighter |  |
| material.interactive | light-photo | glass.step1e0.height.response_pct | 16.67 | 17.5 | 25 | 26.25 | looser |  |
| material.interactive | light-photo | glass.step1e0.height.settle_ms | 66.67 | 16.67 | 100 | 25 | tighter |  |
| material.interactive | light-photo | glass.step1e0.width.peak_ms | 41.67 | 16.67 | 62.5 | 25 | tighter |  |
| material.interactive | light-photo | glass.step1e0.width.response_pct | 16.22 | 17.07 | 24.32 | 25.61 | looser |  |
| material.interactive | light-photo | glass.step1e0.width.settle_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.interactive | light-photo | glass.step1e1.height.damping | 0.13 | 0.07 | 0.195 | 0.105 | tighter |  |
| material.interactive | light-photo | glass.step1e1.height.peak_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.interactive | light-photo | glass.step1e1.height.response_pct | 28.13 | 19.23 | 42.19 | 28.85 | tighter |  |
| material.interactive | light-photo | glass.step1e1.height.settle_ms | 33.33 | 8.333 | 50 | 17 | tighter |  |
| material.interactive | light-photo | glass.step1e1.luma.peak_ms | 225 | 233.3 | 337.5 | 350 | looser |  |
| material.interactive | light-photo | glass.step1e1.luma.response_pct | 56.25 | 52.75 | 84.38 | 79.12 | tighter |  |
| material.interactive | light-photo | glass.step1e1.luma.settle_ms | 0 | 33.33 | 17 | 50 | looser |  |
| material.interactive | light-photo | glass.step1e1.width.peak_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.interactive | light-photo | glass.step1e1.width.response_pct | 21.88 | 19.23 | 32.81 | 28.85 | tighter |  |
| material.interactive | light-photo | glass.step1e1.width.settle_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.interactive | light-photo | glass.step1e2.luma.peak_ms | 141.7 | 66.67 | 212.5 | 100 | tighter |  |
| material.interactive | light-photo | glass.step1e2.luma.settle_ms | 0 | 50 | 17 | 75 | looser |  |
| material.interactive | light-photo | glass.step3e0.height.peak_ms | 50 | 25 | 75 | 37.5 | tighter |  |
| material.interactive | light-photo | glass.step3e0.height.response_pct | 48.84 | 16.28 | 73.26 | 24.42 | tighter |  |
| material.interactive | light-photo | glass.step3e0.height.settle_ms | 166.7 | 175 | 250 | 262.5 | looser |  |
| material.interactive | light-photo | glass.step3e0.luma.peak_ms | 58.33 | 25 | 87.5 | 37.5 | tighter |  |
| material.interactive | light-photo | glass.step3e0.luma.settle_ms | 33.33 | 83.33 | 50 | 125 | looser |  |
| material.interactive | light-photo | glass.step3e0.width.damping | 0.16 | 0.02 | 0.24 | 0.05 | tighter |  |
| material.interactive | light-photo | glass.step3e0.width.overshoot_pct | 3.025 | 0.5912 | 4.538 | 2 | tighter |  |
| material.interactive | light-photo | glass.step3e0.width.peak_ms | 50 | 25 | 75 | 37.5 | tighter |  |
| material.interactive | light-photo | glass.step3e0.width.response_pct | 53.33 | 16.28 | 80 | 24.42 | tighter |  |
| material.interactive | light-photo | glass.step3e0.width.settle_ms | 116.7 | 25 | 175 | 37.5 | tighter |  |
| material.interactive | light-photo | glass.step3e1.height.damping | 0.39 | 0.47 | 0.585 | 0.705 | looser |  |
| material.interactive | light-photo | glass.step3e1.height.peak_ms | 116.7 | 100 | 175 | 150 | tighter |  |
| material.interactive | light-photo | glass.step3e1.height.response_pct | 192 | 74.58 | 288 | 111.9 | tighter |  |
| material.interactive | light-photo | glass.step3e1.height.settle_ms | 125 | 116.7 | 187.5 | 175 | tighter |  |
| material.interactive | light-photo | glass.step3e1.luma.damping | 0.52 | 0.23 | 0.78 | 0.345 | tighter |  |
| material.interactive | light-photo | glass.step3e1.luma.overshoot_pct | 5.261 | 4.91 | 7.891 | 7.366 | tighter |  |
| material.interactive | light-photo | glass.step3e1.luma.peak_ms | 308.3 | 316.7 | 462.5 | 475 | looser |  |
| material.interactive | light-photo | glass.step3e1.luma.response_pct | 175 | 62.9 | 262.5 | 94.35 | tighter |  |
| material.interactive | light-photo | glass.step3e1.luma.settle_ms | 200 | 241.7 | 300 | 362.5 | looser |  |
| material.interactive | light-photo | glass.step3e1.width.damping | 0.22 | 0.35 | 0.33 | 0.525 | looser |  |
| material.interactive | light-photo | glass.step3e1.width.peak_ms | 116.7 | 100 | 175 | 150 | tighter |  |
| material.interactive | light-photo | glass.step3e1.width.response_pct | 163 | 72.41 | 244.4 | 108.6 | tighter |  |
| material.interactive | light-photo | glass.step3e1.width.settle_ms | 125 | 91.67 | 187.5 | 137.5 | tighter |  |
| material.interactive | light-photo | glass.step3e2.luma.peak_ms | 58.33 | 200 | 87.5 | 300 | looser |  |
| material.interactive | light-photo | step1e0.delay_ms | 26.67 | 15 | 40 | 22.5 | tighter |  |
| material.interactive | light-photo | step1e1.delay_ms | 1872 | 6.666 | 2807 | 17 | tighter |  |
| material.interactive | light-photo | step1e2.delay_ms | 1875 | 56.67 | 2812 | 85 | tighter |  |
| material.interactive | light-photo | step3e0.delay_ms | 18.33 | 21.67 | 27.5 | 32.5 | looser |  |
| material.interactive | light-photo | step3e1.delay_ms | 3328 | 121.7 | 4992 | 182.5 | tighter |  |
| material.interactive | light-photo | step3e2.delay_ms | 3212 | 88.33 | 4817 | 132.5 | tighter |  |
| material.interactive | light-stripes | glass.step1e0.height.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.interactive | light-stripes | glass.step1e0.height.response_pct | 4.545 | 13.64 | 6.818 | 20.45 | looser |  |
| material.interactive | light-stripes | glass.step1e0.height.settle_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.interactive | light-stripes | glass.step1e0.luma.peak_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.interactive | light-stripes | glass.step1e0.luma.settle_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.interactive | light-stripes | glass.step1e0.width.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.interactive | light-stripes | glass.step1e0.width.response_pct | 6.522 | 13.64 | 9.783 | 20.45 | looser |  |
| material.interactive | light-stripes | glass.step1e0.width.settle_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.interactive | light-stripes | glass.step1e1.height.response_pct | 28.57 | 40 | 42.86 | 60 | looser |  |
| material.interactive | light-stripes | glass.step1e1.height.settle_ms | 50 | 16.67 | 75 | 25 | tighter |  |
| material.interactive | light-stripes | glass.step1e1.luma.peak_ms | 50 | 41.67 | 75 | 62.5 | tighter |  |
| material.interactive | light-stripes | glass.step1e1.luma.settle_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.interactive | light-stripes | glass.step1e1.width.response_pct | 34.37 | 52.38 | 51.56 | 78.57 | looser |  |
| material.interactive | light-stripes | glass.step1e2.luma.peak_ms | 291.7 | 66.67 | 437.5 | 100 | tighter |  |
| material.interactive | light-stripes | glass.step1e2.luma.settle_ms | 0 | 16.67 | 17 | 25 | looser |  |
| material.interactive | light-stripes | glass.step3e0.height.damping | 0.05 | 0.02 | 0.075 | 0.05 | tighter |  |
| material.interactive | light-stripes | glass.step3e0.height.peak_ms | 33.33 | 58.33 | 50 | 87.5 | looser |  |
| material.interactive | light-stripes | glass.step3e0.height.response_pct | 23.91 | 12.5 | 35.87 | 18.75 | tighter |  |
| material.interactive | light-stripes | glass.step3e0.height.settle_ms | 33.33 | 50 | 50 | 75 | looser |  |
| material.interactive | light-stripes | glass.step3e0.luma.peak_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.interactive | light-stripes | glass.step3e0.luma.settle_ms | 25 | 33.33 | 37.5 | 50 | looser |  |
| material.interactive | light-stripes | glass.step3e0.width.damping | 0.05 | 0.01 | 0.075 | 0.05 | tighter |  |
| material.interactive | light-stripes | glass.step3e0.width.peak_ms | 33.33 | 8.333 | 50 | 17 | tighter |  |
| material.interactive | light-stripes | glass.step3e0.width.response_pct | 23.4 | 8.163 | 35.11 | 12.24 | tighter |  |
| material.interactive | light-stripes | glass.step3e0.width.settle_ms | 41.67 | 16.67 | 62.5 | 25 | tighter |  |
| material.interactive | light-stripes | glass.step3e1.width.response_pct | 25 | 33.33 | 37.5 | 50 | looser |  |
| material.interactive | light-stripes | glass.step3e2.luma.peak_ms | 258.3 | 66.67 | 387.5 | 100 | tighter |  |
| material.interactive | light-stripes | step1e0.delay_ms | 0 | 18.33 | 17 | 27.5 | looser |  |
| material.interactive | light-stripes | step1e1.delay_ms | 1852 | 33.33 | 2777 | 50 | tighter |  |
| material.interactive | light-stripes | step1e2.delay_ms | 1852 | 38.33 | 2777 | 57.5 | tighter |  |
| material.interactive | light-stripes | step3e0.delay_ms | 21.67 | 20 | 32.5 | 30 | tighter |  |
| material.interactive | light-stripes | step3e1.delay_ms | 2947 | 21.67 | 4420 | 32.5 | tighter |  |
| material.interactive | light-stripes | step3e2.delay_ms | 2940 | 31.67 | 4410 | 47.5 | tighter |  |
| material.materialize | dark-photo | block.step1e0.progress.damping | 0.04 | 0.08 | 0.06 | 0.12 | looser | yes |
| material.materialize | dark-photo | block.step1e0.progress.response_pct | 4 | 11.11 | 6 | 16.67 | looser | yes |
| material.materialize | dark-photo | block.step3e0.cx.overshoot_pct | 4.167 | 0 | 6.25 | 2 | tighter |  |
| material.materialize | dark-photo | block.step3e0.cx.peak_ms | 33.33 | 0 | 50 | 17 | tighter |  |
| material.materialize | dark-photo | block.step3e0.cx.response_pct | 4.348 | 0 | 6.522 | 5 | tighter |  |
| material.materialize | dark-photo | block.step3e0.cx.settle_ms | 116.7 | 0 | 175 | 17 | tighter |  |
| material.materialize | dark-photo | block.step3e0.cy.damping | 0.2 | 0.18 | 0.3 | 0.27 | tighter |  |
| material.materialize | dark-photo | block.step3e0.cy.peak_ms | 91.67 | 8.333 | 137.5 | 17 | tighter |  |
| material.materialize | dark-photo | block.step3e0.cy.response_pct | 69.57 | 114.3 | 104.3 | 171.4 | looser |  |
| material.materialize | dark-photo | block.step3e0.cy.settle_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.materialize | dark-photo | block.step3e0.height.damping | 0.11 | 0.1 | 0.165 | 0.15 | tighter |  |
| material.materialize | dark-photo | block.step3e0.height.peak_ms | 33.33 | 8.333 | 50 | 17 | tighter |  |
| material.materialize | dark-photo | block.step3e0.height.response_pct | 68.18 | 100 | 102.3 | 150 | looser |  |
| material.materialize | dark-photo | block.step3e0.height.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.materialize | dark-photo | block.step3e0.progress.damping | 0.13 | 0.16 | 0.195 | 0.24 | looser | yes |
| material.materialize | dark-photo | block.step3e0.progress.response_pct | 23.19 | 20.41 | 34.78 | 30.61 | tighter | yes |
| material.materialize | dark-photo | block.step3e0.progress.settle_ms | 33.33 | 16.67 | 50 | 25 | tighter | yes |
| material.materialize | dark-photo | block.step3e0.progress.t10_90_ms | 25 | 16.67 | 37.5 | 25 | tighter | yes |
| material.materialize | dark-photo | block.step3e0.width.damping | 0.39 | 0.05 | 0.585 | 0.075 | tighter |  |
| material.materialize | dark-photo | block.step3e0.width.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize | dark-photo | block.step3e0.width.response_pct | 166.7 | 0 | 250 | 5 | tighter |  |
| material.materialize | dark-photo | block.step3e0.width.settle_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.materialize | dark-photo | step1e0.delay_ms | 20 | 16.67 | 30 | 25 | tighter |  |
| material.materialize | dark-photo | step3e0.delay_ms | 38.33 | 20 | 57.5 | 30 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step1e0.cx.overshoot_pct | 0 | 313.8 | 2 | 470.7 | looser |  |
| material.materialize | dark-photo-reduce-motion | block.step1e0.cx.peak_ms | 0 | 16.67 | 17 | 25 | looser |  |
| material.materialize | dark-photo-reduce-motion | block.step1e0.height.peak_ms | 25 | 8.333 | 37.5 | 17 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step1e0.luma.damping | 0.2 | 0.15 | 0.3 | 0.225 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step1e0.luma.peak_ms | 8.333 | 283.3 | 17 | 425 | looser |  |
| material.materialize | dark-photo-reduce-motion | block.step1e0.luma.response_pct | 21.43 | 12.5 | 32.14 | 18.75 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step1e0.luma.settle_ms | 25 | 66.67 | 37.5 | 100 | looser |  |
| material.materialize | dark-photo-reduce-motion | block.step1e0.width.peak_ms | 25 | 8.333 | 37.5 | 17 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step1e0.width.response_pct | 4.839 | 4.615 | 7.258 | 6.923 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step1e0.width.settle_ms | 16.67 | 0 | 25 | 17 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.cx.damping | 0.28 | 0.05 | 0.42 | 0.075 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.cx.peak_ms | 41.67 | 8.333 | 62.5 | 17 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.cx.response_pct | 41.67 | 6.667 | 62.5 | 10 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.cx.settle_ms | 50 | 33.33 | 75 | 50 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.cy.damping | 0.08 | 0.04 | 0.12 | 0.06 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.cy.overshoot_pct | 2.503 | 1.359 | 3.754 | 2.038 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.cy.peak_ms | 33.33 | 8.333 | 50 | 17 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.cy.response_pct | 51.85 | 17.65 | 77.78 | 26.47 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.cy.settle_ms | 41.67 | 16.67 | 62.5 | 25 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.height.damping | 0.22 | 0.1 | 0.33 | 0.15 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.height.peak_ms | 400 | 391.7 | 600 | 587.5 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.height.response_pct | 62.5 | 10 | 93.75 | 15 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.height.settle_ms | 50 | 16.67 | 75 | 25 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.progress.damping | 0.29 | 0.04 | 0.435 | 0.06 | tighter | yes |
| material.materialize | dark-photo-reduce-motion | block.step3e0.progress.response_pct | 35.29 | 4.167 | 52.94 | 6.25 | tighter | yes |
| material.materialize | dark-photo-reduce-motion | block.step3e0.progress.settle_ms | 50 | 25 | 75 | 37.5 | tighter | yes |
| material.materialize | dark-photo-reduce-motion | block.step3e0.progress.t10_90_ms | 25 | 16.67 | 37.5 | 25 | tighter | yes |
| material.materialize | dark-photo-reduce-motion | block.step3e0.width.damping | 0.83 | 0.26 | 1.245 | 0.39 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.width.peak_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.width.response_pct | 72.73 | 16.67 | 109.1 | 25 | tighter |  |
| material.materialize | dark-photo-reduce-motion | block.step3e0.width.settle_ms | 50 | 33.33 | 75 | 50 | tighter |  |
| material.materialize | dark-photo-reduce-motion | step1e0.delay_ms | 23.33 | 30 | 35 | 45 | looser |  |
| material.materialize | dark-photo-reduce-motion | step3e0.delay_ms | 53.33 | 30 | 80 | 45 | tighter |  |
| material.materialize | dark-stripes | block.step1e0.cx.overshoot_pct | 74.82 | 72.99 | 112.2 | 109.5 | tighter |  |
| material.materialize | dark-stripes | block.step1e0.cx.peak_ms | 41.67 | 33.33 | 62.5 | 50 | tighter |  |
| material.materialize | dark-stripes | block.step1e0.luma.damping | 0.13 | 0.15 | 0.195 | 0.225 | looser |  |
| material.materialize | dark-stripes | block.step1e0.luma.peak_ms | 33.33 | 50 | 50 | 75 | looser |  |
| material.materialize | dark-stripes | block.step1e0.luma.response_pct | 19.05 | 23.81 | 28.57 | 35.71 | looser |  |
| material.materialize | dark-stripes | block.step1e0.progress.t10_90_ms | 16.67 | 8.333 | 25 | 17 | tighter | yes |
| material.materialize | dark-stripes | block.step3e0.cx.response_pct | 66.67 | 50 | 100 | 75 | tighter |  |
| material.materialize | dark-stripes | block.step3e0.cx.settle_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.materialize | dark-stripes | block.step3e0.cy.damping | 0.05 | 0 | 0.075 | 0.05 | tighter |  |
| material.materialize | dark-stripes | block.step3e0.cy.peak_ms | 266.7 | 0 | 400 | 17 | tighter |  |
| material.materialize | dark-stripes | block.step3e0.cy.response_pct | 16.67 | 0 | 25 | 5 | tighter |  |
| material.materialize | dark-stripes | block.step3e0.height.damping | 0.04 | 0.05 | 0.06 | 0.075 | looser |  |
| material.materialize | dark-stripes | block.step3e0.luma.damping | 0.08 | 0.06 | 0.12 | 0.09 | tighter |  |
| material.materialize | dark-stripes | block.step3e0.luma.response_pct | 3.922 | 3.774 | 5.882 | 5.66 | tighter |  |
| material.materialize | dark-stripes | block.step3e0.luma.settle_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize | dark-stripes | block.step3e0.progress.damping | 0.08 | 0.04 | 0.12 | 0.06 | tighter | yes |
| material.materialize | dark-stripes | block.step3e0.progress.response_pct | 3.846 | 3.704 | 5.769 | 5.556 | tighter | yes |
| material.materialize | dark-stripes | block.step3e0.progress.settle_ms | 25 | 16.67 | 37.5 | 25 | tighter | yes |
| material.materialize | dark-stripes | block.step3e0.progress.t10_90_ms | 33.33 | 25 | 50 | 37.5 | tighter | yes |
| material.materialize | dark-stripes | block.step3e0.width.damping | 0.04 | 0.08 | 0.06 | 0.12 | looser |  |
| material.materialize | dark-stripes | block.step3e0.width.peak_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.materialize | dark-stripes | block.step3e0.width.response_pct | 60 | 54.55 | 90 | 81.82 | tighter |  |
| material.materialize | dark-stripes | step1e0.delay_ms | 6.666 | 18.33 | 17 | 27.5 | looser |  |
| material.materialize | dark-stripes-reduce-motion | block.step1e0.luma.damping | 0.11 | 0.12 | 0.165 | 0.18 | looser |  |
| material.materialize | dark-stripes-reduce-motion | block.step1e0.luma.peak_ms | 25 | 8.333 | 37.5 | 17 | tighter |  |
| material.materialize | dark-stripes-reduce-motion | block.step1e0.luma.response_pct | 15.79 | 16.67 | 23.68 | 25 | looser |  |
| material.materialize | dark-stripes-reduce-motion | block.step1e0.progress.damping | 0.09 | 0.1 | 0.135 | 0.15 | looser | yes |
| material.materialize | dark-stripes-reduce-motion | block.step1e0.progress.response_pct | 14.29 | 15 | 21.43 | 22.5 | looser | yes |
| material.materialize | dark-stripes-reduce-motion | block.step3e0.cx.response_pct | 10.53 | 5 | 15.79 | 7.5 | tighter |  |
| material.materialize | dark-stripes-reduce-motion | block.step3e0.height.damping | 0.09 | 0.06 | 0.135 | 0.09 | tighter |  |
| material.materialize | dark-stripes-reduce-motion | block.step3e0.height.peak_ms | 600 | 575 | 900 | 862.5 | tighter |  |
| material.materialize | dark-stripes-reduce-motion | block.step3e0.luma.damping | 0.05 | 0.03 | 0.075 | 0.05 | tighter |  |
| material.materialize | dark-stripes-reduce-motion | block.step3e0.luma.peak_ms | 41.67 | 25 | 62.5 | 37.5 | tighter |  |
| material.materialize | dark-stripes-reduce-motion | block.step3e0.luma.response_pct | 4.687 | 4.918 | 7.031 | 7.377 | looser |  |
| material.materialize | dark-stripes-reduce-motion | block.step3e0.luma.settle_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize | dark-stripes-reduce-motion | block.step3e0.progress.damping | 0.05 | 0.03 | 0.075 | 0.05 | tighter | yes |
| material.materialize | dark-stripes-reduce-motion | block.step3e0.progress.response_pct | 3.333 | 5.263 | 5 | 7.895 | looser | yes |
| material.materialize | dark-stripes-reduce-motion | block.step3e0.progress.settle_ms | 25 | 16.67 | 37.5 | 25 | tighter | yes |
| material.materialize | dark-stripes-reduce-motion | block.step3e0.progress.t10_90_ms | 16.67 | 25 | 25 | 37.5 | looser | yes |
| material.materialize | dark-stripes-reduce-motion | block.step3e0.width.response_pct | 6.25 | 0 | 9.375 | 5 | tighter |  |
| material.materialize | dark-stripes-reduce-motion | step1e0.delay_ms | 21.67 | 5.001 | 32.5 | 17 | tighter |  |
| material.materialize | dark-stripes-reduce-motion | step3e0.delay_ms | 20 | 18.33 | 30 | 27.5 | tighter |  |
| material.materialize | light-photo | block.step1e0.luma.damping | 0.13 | 0.11 | 0.195 | 0.165 | tighter |  |
| material.materialize | light-photo | block.step1e0.luma.peak_ms | 158.3 | 183.3 | 237.5 | 275 | looser |  |
| material.materialize | light-photo | block.step1e0.luma.response_pct | 23.81 | 15.38 | 35.71 | 23.08 | tighter |  |
| material.materialize | light-photo | block.step1e0.progress.damping | 0.15 | 0.08 | 0.225 | 0.12 | tighter | yes |
| material.materialize | light-photo | block.step1e0.progress.response_pct | 26.32 | 12.5 | 39.47 | 18.75 | tighter | yes |
| material.materialize | light-photo | block.step3e0.cx.peak_ms | 241.7 | 216.7 | 362.5 | 325 | tighter |  |
| material.materialize | light-photo | block.step3e0.cx.response_pct | 53.85 | 0 | 80.77 | 5 | tighter |  |
| material.materialize | light-photo | block.step3e0.cx.settle_ms | 25 | 0 | 37.5 | 17 | tighter |  |
| material.materialize | light-photo | block.step3e0.cy.damping | 0.04 | 0.02 | 0.06 | 0.05 | tighter |  |
| material.materialize | light-photo | block.step3e0.cy.response_pct | 43.75 | 6.25 | 65.62 | 9.375 | tighter |  |
| material.materialize | light-photo | block.step3e0.cy.settle_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.materialize | light-photo | block.step3e0.height.peak_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.materialize | light-photo | block.step3e0.height.response_pct | 43.75 | 6.667 | 65.62 | 10 | tighter |  |
| material.materialize | light-photo | block.step3e0.height.settle_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.materialize | light-photo | block.step3e0.luma.damping | 0.08 | 0.01 | 0.12 | 0.05 | tighter |  |
| material.materialize | light-photo | block.step3e0.luma.peak_ms | 58.33 | 50 | 87.5 | 75 | tighter |  |
| material.materialize | light-photo | block.step3e0.luma.response_pct | 14.67 | 3.125 | 22 | 5 | tighter |  |
| material.materialize | light-photo | block.step3e0.luma.settle_ms | 33.33 | 8.333 | 50 | 17 | tighter |  |
| material.materialize | light-photo | block.step3e0.progress.damping | 0.06 | 0.01 | 0.09 | 0.05 | tighter | yes |
| material.materialize | light-photo | block.step3e0.progress.response_pct | 14.1 | 2.985 | 21.15 | 5 | tighter | yes |
| material.materialize | light-photo | block.step3e0.progress.settle_ms | 33.33 | 8.333 | 50 | 17 | tighter | yes |
| material.materialize | light-photo | block.step3e0.progress.t10_90_ms | 16.67 | 8.333 | 25 | 17 | tighter | yes |
| material.materialize | light-photo | block.step3e0.width.damping | 0.11 | 0.02 | 0.165 | 0.05 | tighter |  |
| material.materialize | light-photo | block.step3e0.width.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize | light-photo | block.step3e0.width.response_pct | 57.14 | 0 | 85.71 | 5 | tighter |  |
| material.materialize | light-photo | block.step3e0.width.settle_ms | 25 | 8.333 | 37.5 | 17 | tighter |  |
| material.materialize | light-photo | step1e0.delay_ms | 25 | 26.67 | 37.5 | 40 | looser |  |
| material.materialize | light-photo | step3e0.delay_ms | 33.33 | 30 | 50 | 45 | tighter |  |
| material.materialize | light-photo-reduce-motion | block.step1e0.cy.peak_ms | 8.333 | 100 | 17 | 150 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step1e0.cy.response_pct | 3.509 | 1.818 | 5.263 | 5 | tighter |  |
| material.materialize | light-photo-reduce-motion | block.step1e0.cy.settle_ms | 16.67 | 100 | 25 | 150 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step1e0.height.peak_ms | 25 | 83.33 | 37.5 | 125 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step1e0.height.settle_ms | 25 | 100 | 37.5 | 150 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step1e0.luma.damping | 0.07 | 0.38 | 0.105 | 0.57 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step1e0.luma.peak_ms | 58.33 | 41.67 | 87.5 | 62.5 | tighter |  |
| material.materialize | light-photo-reduce-motion | block.step1e0.luma.response_pct | 9.524 | 223.8 | 14.29 | 335.7 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step1e0.luma.settle_ms | 0 | 100 | 17 | 150 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step1e0.progress.damping | 0.11 | 0.38 | 0.165 | 0.57 | looser | yes |
| material.materialize | light-photo-reduce-motion | block.step1e0.progress.response_pct | 14.29 | 223.8 | 21.43 | 335.7 | looser | yes |
| material.materialize | light-photo-reduce-motion | block.step1e0.progress.settle_ms | 8.333 | 100 | 17 | 150 | looser | yes |
| material.materialize | light-photo-reduce-motion | block.step1e0.width.peak_ms | 25 | 83.33 | 37.5 | 125 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step1e0.width.settle_ms | 16.67 | 100 | 25 | 150 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.cy.damping | 0.03 | 0.04 | 0.05 | 0.06 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.cy.peak_ms | 8.333 | 33.33 | 17 | 50 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.cy.response_pct | 17.39 | 60.87 | 26.09 | 91.3 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.cy.settle_ms | 8.333 | 25 | 17 | 37.5 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.height.damping | 0.04 | 0.09 | 0.06 | 0.135 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.height.peak_ms | 8.333 | 33.33 | 17 | 50 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.height.response_pct | 15.79 | 93.75 | 23.68 | 140.6 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.height.settle_ms | 8.333 | 33.33 | 17 | 50 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.luma.damping | 0.02 | 0.08 | 0.05 | 0.12 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.luma.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.luma.response_pct | 5.556 | 27.94 | 8.333 | 41.91 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.luma.settle_ms | 16.67 | 41.67 | 25 | 62.5 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.progress.damping | 0.04 | 0.1 | 0.06 | 0.15 | looser | yes |
| material.materialize | light-photo-reduce-motion | block.step3e0.progress.response_pct | 4.286 | 28.36 | 6.429 | 42.54 | looser | yes |
| material.materialize | light-photo-reduce-motion | block.step3e0.progress.settle_ms | 25 | 50 | 37.5 | 75 | looser | yes |
| material.materialize | light-photo-reduce-motion | block.step3e0.width.damping | 0.06 | 0.24 | 0.09 | 0.36 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.width.peak_ms | 41.67 | 66.67 | 62.5 | 100 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.width.response_pct | 13.33 | 130.8 | 20 | 196.2 | looser |  |
| material.materialize | light-photo-reduce-motion | block.step3e0.width.settle_ms | 8.333 | 41.67 | 17 | 62.5 | looser |  |
| material.materialize | light-photo-reduce-motion | step1e0.delay_ms | 26.67 | 100 | 40 | 150 | looser |  |
| material.materialize | light-photo-reduce-motion | step3e0.delay_ms | 18.33 | 50 | 27.5 | 75 | looser |  |
| material.materialize | light-stripes | block.step1e0.height.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize | light-stripes | block.step1e0.luma.peak_ms | 33.33 | 66.67 | 50 | 100 | looser |  |
| material.materialize | light-stripes | block.step1e0.luma.response_pct | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.materialize | light-stripes | block.step1e0.progress.damping | 0.25 | 0.28 | 0.375 | 0.42 | looser | yes |
| material.materialize | light-stripes | block.step1e0.progress.response_pct | 26.09 | 41.18 | 39.13 | 61.76 | looser | yes |
| material.materialize | light-stripes | block.step1e0.width.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize | light-stripes | block.step1e0.width.response_pct | 6.154 | 6.557 | 9.231 | 9.836 | looser |  |
| material.materialize | light-stripes | block.step1e0.width.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.materialize | light-stripes | block.step3e0.cx.damping | 0.07 | 0.03 | 0.105 | 0.05 | tighter |  |
| material.materialize | light-stripes | block.step3e0.cx.response_pct | 110 | 61.54 | 165 | 92.31 | tighter |  |
| material.materialize | light-stripes | block.step3e0.cy.peak_ms | 16.67 | 0 | 25 | 17 | tighter |  |
| material.materialize | light-stripes | block.step3e0.height.peak_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.materialize | light-stripes | block.step3e0.height.response_pct | 116.7 | 133.3 | 175 | 200 | looser |  |
| material.materialize | light-stripes | block.step3e0.height.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.materialize | light-stripes | block.step3e0.luma.damping | 0.16 | 0.1 | 0.24 | 0.15 | tighter |  |
| material.materialize | light-stripes | block.step3e0.luma.peak_ms | 41.67 | 25 | 62.5 | 37.5 | tighter |  |
| material.materialize | light-stripes | block.step3e0.luma.response_pct | 22.64 | 20.37 | 33.96 | 30.56 | tighter |  |
| material.materialize | light-stripes | block.step3e0.luma.settle_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.materialize | light-stripes | block.step3e0.progress.damping | 0.11 | 0.08 | 0.165 | 0.12 | tighter | yes |
| material.materialize | light-stripes | block.step3e0.progress.response_pct | 18.64 | 16.95 | 27.97 | 25.42 | tighter | yes |
| material.materialize | light-stripes | block.step3e0.progress.settle_ms | 25 | 16.67 | 37.5 | 25 | tighter | yes |
| material.materialize | light-stripes | block.step3e0.width.damping | 0.05 | 0.04 | 0.075 | 0.06 | tighter |  |
| material.materialize | light-stripes | block.step3e0.width.peak_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.materialize | light-stripes | step1e0.delay_ms | 20 | 21.67 | 30 | 32.5 | looser |  |
| material.materialize | light-stripes | step3e0.delay_ms | 21.67 | 20 | 32.5 | 30 | tighter |  |
| material.materialize | light-stripes-reduce-motion | block.step1e0.cx.overshoot_pct | 0 | 2.051 | 2 | 3.077 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step1e0.cx.settle_ms | 0 | 16.67 | 17 | 25 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step1e0.luma.damping | 0.1 | 0.11 | 0.15 | 0.165 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step1e0.luma.response_pct | 13.04 | 20 | 19.57 | 30 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step1e0.luma.settle_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step1e0.progress.damping | 0.1 | 0.11 | 0.15 | 0.165 | looser | yes |
| material.materialize | light-stripes-reduce-motion | block.step1e0.progress.response_pct | 13.04 | 20 | 19.57 | 30 | looser | yes |
| material.materialize | light-stripes-reduce-motion | block.step1e0.progress.t10_90_ms | 8.333 | 16.67 | 17 | 25 | looser | yes |
| material.materialize | light-stripes-reduce-motion | block.step3e0.cx.overshoot_pct | 86.71 | 70.58 | 130.1 | 105.9 | tighter |  |
| material.materialize | light-stripes-reduce-motion | block.step3e0.cx.response_pct | 25 | 40 | 37.5 | 60 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step3e0.cx.settle_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step3e0.height.damping | 0.03 | 0.07 | 0.05 | 0.105 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step3e0.height.peak_ms | 41.67 | 75 | 62.5 | 112.5 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step3e0.height.response_pct | 13.33 | 75 | 20 | 112.5 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step3e0.luma.damping | 0.02 | 0.04 | 0.05 | 0.06 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step3e0.luma.response_pct | 8.197 | 7.143 | 12.3 | 10.71 | tighter |  |
| material.materialize | light-stripes-reduce-motion | block.step3e0.luma.settle_ms | 8.333 | 25 | 17 | 37.5 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step3e0.progress.damping | 0.03 | 0.05 | 0.05 | 0.075 | looser | yes |
| material.materialize | light-stripes-reduce-motion | block.step3e0.progress.response_pct | 8.333 | 9.091 | 12.5 | 13.64 | looser | yes |
| material.materialize | light-stripes-reduce-motion | block.step3e0.progress.settle_ms | 16.67 | 25 | 25 | 37.5 | looser | yes |
| material.materialize | light-stripes-reduce-motion | block.step3e0.progress.t10_90_ms | 8.333 | 25 | 17 | 37.5 | looser | yes |
| material.materialize | light-stripes-reduce-motion | block.step3e0.width.damping | 0.02 | 0.05 | 0.05 | 0.075 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step3e0.width.peak_ms | 16.67 | 58.33 | 25 | 87.5 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step3e0.width.response_pct | 14.29 | 23.53 | 21.43 | 35.29 | looser |  |
| material.materialize | light-stripes-reduce-motion | block.step3e0.width.settle_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.materialize | light-stripes-reduce-motion | step1e0.delay_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize | light-stripes-reduce-motion | step3e0.delay_ms | 20 | 18.33 | 30 | 27.5 | tighter |  |
| material.materialize.bouncy | dark-photo | block.step1e0.progress.response_pct | 4 | 4.167 | 6 | 6.25 | looser | yes |
| material.materialize.bouncy | dark-photo | block.step3e0.cy.damping | 0.05 | 0.06 | 0.075 | 0.09 | looser |  |
| material.materialize.bouncy | dark-photo | block.step3e0.cy.overshoot_pct | 4.835 | 5.323 | 7.253 | 7.985 | looser |  |
| material.materialize.bouncy | dark-photo | block.step3e0.cy.peak_ms | 33.33 | 133.3 | 50 | 200 | looser |  |
| material.materialize.bouncy | dark-photo | block.step3e0.cy.response_pct | 85.71 | 185.7 | 128.6 | 278.6 | looser |  |
| material.materialize.bouncy | dark-photo | block.step3e0.cy.settle_ms | 425 | 383.3 | 637.5 | 575 | tighter |  |
| material.materialize.bouncy | dark-photo | block.step3e0.height.damping | 0.07 | 0.08 | 0.105 | 0.12 | looser |  |
| material.materialize.bouncy | dark-photo | block.step3e0.height.overshoot_pct | 0.3774 | 2.333 | 2 | 3.499 | looser |  |
| material.materialize.bouncy | dark-photo | block.step3e0.height.response_pct | 70 | 57.14 | 105 | 85.71 | tighter |  |
| material.materialize.bouncy | dark-photo | block.step3e0.height.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.materialize.bouncy | dark-photo | block.step3e0.progress.damping | 0.05 | 0.04 | 0.075 | 0.06 | tighter | yes |
| material.materialize.bouncy | dark-photo | block.step3e0.progress.response_pct | 28.57 | 22.86 | 42.86 | 34.29 | tighter | yes |
| material.materialize.bouncy | dark-photo | block.step3e0.progress.settle_ms | 50 | 25 | 75 | 37.5 | tighter | yes |
| material.materialize.bouncy | dark-photo | block.step3e0.width.damping | 0.17 | 0.05 | 0.255 | 0.075 | tighter |  |
| material.materialize.bouncy | dark-photo | block.step3e0.width.peak_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.materialize.bouncy | dark-photo | block.step3e0.width.response_pct | 87.5 | 14.29 | 131.3 | 21.43 | tighter |  |
| material.materialize.bouncy | dark-photo | block.step3e0.width.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.materialize.bouncy | dark-photo | step1e0.delay_ms | 21.67 | 33.33 | 32.5 | 50 | looser |  |
| material.materialize.bouncy | dark-photo | step3e0.delay_ms | 51.67 | 43.33 | 77.5 | 65 | tighter |  |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step1e0.cx.peak_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step1e0.height.response_pct | 7.843 | 0 | 11.76 | 5 | tighter |  |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step1e0.luma.damping | 0.25 | 0.26 | 0.375 | 0.39 | looser |  |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step1e0.luma.peak_ms | 208.3 | 200 | 312.5 | 300 | tighter |  |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step1e0.luma.settle_ms | 16.67 | 33.33 | 25 | 50 | looser |  |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step1e0.progress.damping | 0.13 | 0.12 | 0.195 | 0.18 | tighter | yes |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step3e0.cx.overshoot_pct | 2.429 | 2.023 | 3.643 | 3.034 | tighter |  |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step3e0.height.damping | 0.19 | 0.15 | 0.285 | 0.225 | tighter |  |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step3e0.height.peak_ms | 166.7 | 175 | 250 | 262.5 | looser |  |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step3e0.luma.peak_ms | 25 | 50 | 37.5 | 75 | looser |  |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step3e0.luma.response_pct | 15.25 | 4 | 22.88 | 6 | tighter |  |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step3e0.luma.settle_ms | 58.33 | 25 | 87.5 | 37.5 | tighter |  |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step3e0.progress.damping | 0.08 | 0.09 | 0.12 | 0.135 | looser | yes |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step3e0.progress.t10_90_ms | 25 | 8.333 | 37.5 | 17 | tighter | yes |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step3e0.width.damping | 0.41 | 0.19 | 0.615 | 0.285 | tighter |  |
| material.materialize.bouncy | dark-photo-reduce-motion | block.step3e0.width.response_pct | 41.67 | 14.29 | 62.5 | 21.43 | tighter |  |
| material.materialize.bouncy | dark-photo-reduce-motion | step1e0.delay_ms | 41.67 | 43.33 | 62.5 | 65 | looser |  |
| material.materialize.bouncy | dark-photo-reduce-motion | step3e0.delay_ms | 36.67 | 18.33 | 55 | 27.5 | tighter |  |
| material.materialize.bouncy | dark-stripes | block.step1e0.luma.damping | 0.03 | 0.06 | 0.05 | 0.09 | looser |  |
| material.materialize.bouncy | dark-stripes | block.step1e0.luma.response_pct | 4.348 | 8.333 | 6.522 | 12.5 | looser |  |
| material.materialize.bouncy | dark-stripes | block.step3e0.cx.damping | 0.04 | 0.02 | 0.06 | 0.05 | tighter |  |
| material.materialize.bouncy | dark-stripes | block.step3e0.cx.peak_ms | 8.333 | 25 | 17 | 37.5 | looser |  |
| material.materialize.bouncy | dark-stripes | block.step3e0.cx.response_pct | 0 | 85.71 | 5 | 128.6 | looser |  |
| material.materialize.bouncy | dark-stripes | block.step3e0.cx.settle_ms | 8.333 | 25 | 17 | 37.5 | looser |  |
| material.materialize.bouncy | dark-stripes | block.step3e0.height.peak_ms | 0 | 16.67 | 17 | 25 | looser |  |
| material.materialize.bouncy | dark-stripes | block.step3e0.height.settle_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.materialize.bouncy | dark-stripes | block.step3e0.luma.settle_ms | 25 | 100 | 37.5 | 150 | looser |  |
| material.materialize.bouncy | dark-stripes | block.step3e0.progress.settle_ms | 50 | 150 | 75 | 225 | looser | yes |
| material.materialize.bouncy | dark-stripes | block.step3e0.progress.t10_90_ms | 16.67 | 8.333 | 25 | 17 | tighter | yes |
| material.materialize.bouncy | dark-stripes | block.step3e0.width.damping | 0.04 | 0.09 | 0.06 | 0.135 | looser |  |
| material.materialize.bouncy | dark-stripes | block.step3e0.width.peak_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.materialize.bouncy | dark-stripes | block.step3e0.width.response_pct | 0 | 83.33 | 5 | 125 | looser |  |
| material.materialize.bouncy | dark-stripes | step1e0.delay_ms | 30 | 28.33 | 45 | 42.5 | tighter |  |
| material.materialize.bouncy | dark-stripes | step3e0.delay_ms | 31.67 | 30 | 47.5 | 45 | tighter |  |
| material.materialize.bouncy | dark-stripes-reduce-motion | block.step1e0.cx.response_pct | 0 | 8.108 | 5 | 12.16 | looser |  |
| material.materialize.bouncy | dark-stripes-reduce-motion | block.step1e0.width.response_pct | 10.42 | 6.977 | 15.62 | 10.47 | tighter |  |
| material.materialize.bouncy | dark-stripes-reduce-motion | block.step3e0.height.damping | 0.06 | 0 | 0.09 | 0.05 | tighter |  |
| material.materialize.bouncy | dark-stripes-reduce-motion | block.step3e0.height.peak_ms | 175 | 83.33 | 262.5 | 125 | tighter |  |
| material.materialize.bouncy | dark-stripes-reduce-motion | block.step3e0.luma.damping | 0.04 | 0.01 | 0.06 | 0.05 | tighter |  |
| material.materialize.bouncy | dark-stripes-reduce-motion | block.step3e0.luma.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize.bouncy | dark-stripes-reduce-motion | block.step3e0.luma.settle_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.materialize.bouncy | dark-stripes-reduce-motion | block.step3e0.progress.response_pct | 2.5 | 5 | 5 | 7.5 | looser | yes |
| material.materialize.bouncy | dark-stripes-reduce-motion | block.step3e0.progress.t10_90_ms | 16.67 | 0 | 25 | 17 | tighter | yes |
| material.materialize.bouncy | dark-stripes-reduce-motion | block.step3e0.width.damping | 0.08 | 0.06 | 0.12 | 0.09 | tighter |  |
| material.materialize.bouncy | dark-stripes-reduce-motion | step1e0.delay_ms | 11.67 | 21.67 | 17.5 | 32.5 | looser |  |
| material.materialize.bouncy | dark-stripes-reduce-motion | step3e0.delay_ms | 20 | 5 | 30 | 17 | tighter |  |
| material.materialize.bouncy | light-photo | block.step1e0.cx.settle_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.materialize.bouncy | light-photo | block.step1e0.cy.overshoot_pct | 3.125 | 2.734 | 4.687 | 4.101 | tighter |  |
| material.materialize.bouncy | light-photo | block.step1e0.cy.settle_ms | 8.333 | 25 | 17 | 37.5 | looser |  |
| material.materialize.bouncy | light-photo | block.step1e0.height.peak_ms | 0 | 25 | 17 | 37.5 | looser |  |
| material.materialize.bouncy | light-photo | block.step1e0.luma.damping | 0.08 | 0.12 | 0.12 | 0.18 | looser |  |
| material.materialize.bouncy | light-photo | block.step1e0.luma.peak_ms | 100 | 166.7 | 150 | 250 | looser |  |
| material.materialize.bouncy | light-photo | block.step1e0.luma.response_pct | 13.04 | 25 | 19.57 | 37.5 | looser |  |
| material.materialize.bouncy | light-photo | block.step1e0.progress.damping | 0.14 | 0.17 | 0.21 | 0.255 | looser | yes |
| material.materialize.bouncy | light-photo | block.step1e0.progress.response_pct | 18.18 | 33.33 | 27.27 | 50 | looser | yes |
| material.materialize.bouncy | light-photo | block.step1e0.width.peak_ms | 0 | 25 | 17 | 37.5 | looser |  |
| material.materialize.bouncy | light-photo | block.step3e0.cy.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize.bouncy | light-photo | block.step3e0.cy.response_pct | 61.54 | 53.85 | 92.31 | 80.77 | tighter |  |
| material.materialize.bouncy | light-photo | block.step3e0.cy.settle_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize.bouncy | light-photo | block.step3e0.height.damping | 0.05 | 0.03 | 0.075 | 0.05 | tighter |  |
| material.materialize.bouncy | light-photo | block.step3e0.height.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize.bouncy | light-photo | block.step3e0.height.response_pct | 77.78 | 90 | 116.7 | 135 | looser |  |
| material.materialize.bouncy | light-photo | block.step3e0.luma.peak_ms | 50 | 16.67 | 75 | 25 | tighter |  |
| material.materialize.bouncy | light-photo | block.step3e0.luma.response_pct | 15.22 | 12.77 | 22.83 | 19.15 | tighter |  |
| material.materialize.bouncy | light-photo | block.step3e0.progress.damping | 0.02 | 0.04 | 0.05 | 0.06 | looser | yes |
| material.materialize.bouncy | light-photo | block.step3e0.progress.response_pct | 14.89 | 12.5 | 22.34 | 18.75 | tighter | yes |
| material.materialize.bouncy | light-photo | block.step3e0.progress.t10_90_ms | 25 | 16.67 | 37.5 | 25 | tighter | yes |
| material.materialize.bouncy | light-photo | block.step3e0.width.damping | 0.28 | 0.17 | 0.42 | 0.255 | tighter |  |
| material.materialize.bouncy | light-photo | block.step3e0.width.peak_ms | 8.333 | 25 | 17 | 37.5 | looser |  |
| material.materialize.bouncy | light-photo | block.step3e0.width.response_pct | 150 | 100 | 225 | 150 | tighter |  |
| material.materialize.bouncy | light-photo | block.step3e0.width.settle_ms | 16.67 | 33.33 | 25 | 50 | looser |  |
| material.materialize.bouncy | light-photo | step1e0.delay_ms | 25 | 21.67 | 37.5 | 32.5 | tighter |  |
| material.materialize.bouncy | light-photo | step3e0.delay_ms | 35 | 18.33 | 52.5 | 27.5 | tighter |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step1e0.cy.peak_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step1e0.cy.settle_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step1e0.height.peak_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step1e0.luma.damping | 0.06 | 0.11 | 0.09 | 0.165 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step1e0.luma.response_pct | 8.696 | 17.39 | 13.04 | 26.09 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step1e0.progress.damping | 0.02 | 0.11 | 0.05 | 0.165 | looser | yes |
| material.materialize.bouncy | light-photo-reduce-motion | block.step1e0.progress.response_pct | 4.348 | 17.39 | 6.522 | 26.09 | looser | yes |
| material.materialize.bouncy | light-photo-reduce-motion | block.step1e0.width.peak_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step1e0.width.response_pct | 1.961 | 3.846 | 5 | 5.769 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.cx.damping | 0.04 | 0.03 | 0.06 | 0.05 | tighter |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.cx.overshoot_pct | 1.411 | 0.9785 | 2.116 | 2 | tighter |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.cx.response_pct | 7.692 | 61.54 | 11.54 | 92.31 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.cx.settle_ms | 66.67 | 75 | 100 | 112.5 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.cy.peak_ms | 75 | 91.67 | 112.5 | 137.5 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.cy.response_pct | 70 | 140 | 105 | 210 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.cy.settle_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.height.damping | 0.31 | 0.33 | 0.465 | 0.495 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.height.response_pct | 77.78 | 175 | 116.7 | 262.5 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.height.settle_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.luma.response_pct | 4.167 | 14.58 | 6.25 | 21.88 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.luma.settle_ms | 25 | 33.33 | 37.5 | 50 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.progress.response_pct | 4.255 | 17.02 | 6.383 | 25.53 | looser | yes |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.progress.settle_ms | 25 | 33.33 | 37.5 | 50 | looser | yes |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.progress.t10_90_ms | 8.333 | 25 | 17 | 37.5 | looser | yes |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.width.damping | 0.2 | 0.22 | 0.3 | 0.33 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.width.peak_ms | 8.333 | 25 | 17 | 37.5 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.width.response_pct | 45.45 | 100 | 68.18 | 150 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | block.step3e0.width.settle_ms | 0 | 16.67 | 17 | 25 | looser |  |
| material.materialize.bouncy | light-photo-reduce-motion | step1e0.delay_ms | 18.33 | 8.333 | 27.5 | 17 | tighter |  |
| material.materialize.bouncy | light-photo-reduce-motion | step3e0.delay_ms | 20 | 31.67 | 30 | 47.5 | looser |  |
| material.materialize.bouncy | light-stripes | block.step1e0.cx.settle_ms | 16.67 | 0 | 25 | 17 | tighter |  |
| material.materialize.bouncy | light-stripes | block.step1e0.luma.peak_ms | 50 | 8.333 | 75 | 17 | tighter |  |
| material.materialize.bouncy | light-stripes | block.step1e0.luma.response_pct | 9.091 | 8.333 | 13.64 | 12.5 | tighter |  |
| material.materialize.bouncy | light-stripes | block.step1e0.progress.damping | 0.03 | 0.06 | 0.05 | 0.09 | looser | yes |
| material.materialize.bouncy | light-stripes | block.step1e0.progress.response_pct | 4.762 | 9.091 | 7.143 | 13.64 | looser | yes |
| material.materialize.bouncy | light-stripes | block.step1e0.width.response_pct | 6.25 | 5.882 | 9.375 | 8.824 | tighter |  |
| material.materialize.bouncy | light-stripes | block.step1e0.width.settle_ms | 16.67 | 0 | 25 | 17 | tighter |  |
| material.materialize.bouncy | light-stripes | block.step3e0.cx.damping | 0.04 | 0.03 | 0.06 | 0.05 | tighter |  |
| material.materialize.bouncy | light-stripes | block.step3e0.cx.response_pct | 25 | 13.33 | 37.5 | 20 | tighter |  |
| material.materialize.bouncy | light-stripes | block.step3e0.height.damping | 0.05 | 0.04 | 0.075 | 0.06 | tighter |  |
| material.materialize.bouncy | light-stripes | block.step3e0.height.overshoot_pct | 0.1487 | 1.561 | 2 | 2.342 | looser |  |
| material.materialize.bouncy | light-stripes | block.step3e0.height.peak_ms | 0 | 25 | 17 | 37.5 | looser |  |
| material.materialize.bouncy | light-stripes | block.step3e0.height.response_pct | 16.67 | 100 | 25 | 150 | looser |  |
| material.materialize.bouncy | light-stripes | block.step3e0.luma.peak_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.materialize.bouncy | light-stripes | block.step3e0.luma.settle_ms | 58.33 | 33.33 | 87.5 | 50 | tighter |  |
| material.materialize.bouncy | light-stripes | block.step3e0.progress.settle_ms | 58.33 | 50 | 87.5 | 75 | tighter | yes |
| material.materialize.bouncy | light-stripes | block.step3e0.progress.t10_90_ms | 16.67 | 25 | 25 | 37.5 | looser | yes |
| material.materialize.bouncy | light-stripes | step1e0.delay_ms | 23.33 | 4.999 | 35 | 17 | tighter |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step1e0.luma.damping | 0.06 | 0.03 | 0.09 | 0.05 | tighter |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step1e0.luma.response_pct | 12.5 | 4.545 | 18.75 | 6.818 | tighter |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step1e0.progress.damping | 0.06 | 0.04 | 0.09 | 0.06 | tighter | yes |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step1e0.progress.response_pct | 12.5 | 4.545 | 18.75 | 6.818 | tighter | yes |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step1e0.width.response_pct | 6.122 | 2.128 | 9.184 | 5 | tighter |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.cx.overshoot_pct | 0 | 68.92 | 2 | 103.4 | looser |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.cx.peak_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.cx.settle_ms | 0 | 25 | 17 | 37.5 | looser |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.height.damping | 0.06 | 0.05 | 0.09 | 0.075 | tighter |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.height.peak_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.height.response_pct | 21.43 | 36.36 | 32.14 | 54.55 | looser |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.luma.peak_ms | 50 | 33.33 | 75 | 50 | tighter |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.luma.response_pct | 6.122 | 6.522 | 9.184 | 9.783 | looser |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.luma.settle_ms | 25 | 8.333 | 37.5 | 17 | tighter |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.progress.response_pct | 6.122 | 6.522 | 9.184 | 9.783 | looser | yes |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.progress.settle_ms | 25 | 8.333 | 37.5 | 17 | tighter | yes |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.progress.t10_90_ms | 16.67 | 2.842e-14 | 25 | 17 | tighter | yes |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.width.peak_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.width.response_pct | 11.76 | 23.53 | 17.65 | 35.29 | looser |  |
| material.materialize.bouncy | light-stripes-reduce-motion | block.step3e0.width.settle_ms | 0 | 25 | 17 | 37.5 | looser |  |
| material.materialize.bouncy | light-stripes-reduce-motion | step1e0.delay_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize.bouncy | light-stripes-reduce-motion | step3e0.delay_ms | 25 | 8.333 | 37.5 | 17 | tighter |  |
| material.materialize.snappy | dark-photo | block.step1e0.progress.damping | 0.07 | 0.03 | 0.105 | 0.05 | tighter | yes |
| material.materialize.snappy | dark-photo | block.step1e0.progress.response_pct | 12.5 | 4 | 18.75 | 6 | tighter | yes |
| material.materialize.snappy | dark-photo | block.step3e0.cy.damping | 0.06 | 0.04 | 0.09 | 0.06 | tighter |  |
| material.materialize.snappy | dark-photo | block.step3e0.cy.peak_ms | 83.33 | 75 | 125 | 112.5 | tighter |  |
| material.materialize.snappy | dark-photo | block.step3e0.cy.response_pct | 133.3 | 50 | 200 | 75 | tighter |  |
| material.materialize.snappy | dark-photo | block.step3e0.cy.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.materialize.snappy | dark-photo | block.step3e0.height.damping | 0.02 | 0.06 | 0.05 | 0.09 | looser |  |
| material.materialize.snappy | dark-photo | block.step3e0.height.overshoot_pct | 1.557 | 1.429 | 2.336 | 2.143 | tighter |  |
| material.materialize.snappy | dark-photo | block.step3e0.height.peak_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.materialize.snappy | dark-photo | block.step3e0.height.response_pct | 81.82 | 53.85 | 122.7 | 80.77 | tighter |  |
| material.materialize.snappy | dark-photo | block.step3e0.height.settle_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.materialize.snappy | dark-photo | block.step3e0.progress.damping | 0.15 | 0.07 | 0.225 | 0.105 | tighter | yes |
| material.materialize.snappy | dark-photo | block.step3e0.progress.response_pct | 34.88 | 13.73 | 52.33 | 20.59 | tighter | yes |
| material.materialize.snappy | dark-photo | block.step3e0.progress.settle_ms | 16.67 | 25 | 25 | 37.5 | looser | yes |
| material.materialize.snappy | dark-photo | block.step3e0.width.damping | 0.21 | 0.2 | 0.315 | 0.3 | tighter |  |
| material.materialize.snappy | dark-photo | block.step3e0.width.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize.snappy | dark-photo | block.step3e0.width.settle_ms | 33.33 | 8.333 | 50 | 17 | tighter |  |
| material.materialize.snappy | dark-photo | step1e0.delay_ms | 20 | 18.33 | 30 | 27.5 | tighter |  |
| material.materialize.snappy | dark-photo | step3e0.delay_ms | 16.67 | 33.33 | 25 | 50 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step1e0.height.response_pct | 3.571 | 3.448 | 5.357 | 5.172 | tighter |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step1e0.luma.damping | 0.16 | 0.18 | 0.24 | 0.27 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step1e0.luma.peak_ms | 16.67 | 50 | 25 | 75 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step1e0.luma.response_pct | 15.38 | 20 | 23.08 | 30 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step1e0.progress.response_pct | 8.333 | 4 | 12.5 | 6 | tighter | yes |
| material.materialize.snappy | dark-photo-reduce-motion | block.step1e0.width.response_pct | 3.704 | 5.556 | 5.556 | 8.333 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step3e0.height.peak_ms | 275 | 350 | 412.5 | 525 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step3e0.height.response_pct | 114.3 | 314.3 | 171.4 | 471.4 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step3e0.height.settle_ms | 16.67 | 50 | 25 | 75 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step3e0.luma.damping | 0.02 | 0.06 | 0.05 | 0.09 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step3e0.luma.peak_ms | 50 | 66.67 | 75 | 100 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step3e0.luma.response_pct | 16.46 | 36.36 | 24.68 | 54.55 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step3e0.progress.response_pct | 18.6 | 53.49 | 27.91 | 80.23 | looser | yes |
| material.materialize.snappy | dark-photo-reduce-motion | block.step3e0.progress.settle_ms | 33.33 | 50 | 50 | 75 | looser | yes |
| material.materialize.snappy | dark-photo-reduce-motion | block.step3e0.progress.t10_90_ms | 25 | 33.33 | 37.5 | 50 | looser | yes |
| material.materialize.snappy | dark-photo-reduce-motion | block.step3e0.width.damping | 0.49 | 0.48 | 0.735 | 0.72 | tighter |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step3e0.width.peak_ms | 50 | 75 | 75 | 112.5 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step3e0.width.response_pct | 133.3 | 383.3 | 200 | 575 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | block.step3e0.width.settle_ms | 8.333 | 33.33 | 17 | 50 | looser |  |
| material.materialize.snappy | dark-photo-reduce-motion | step1e0.delay_ms | 21.67 | 18.33 | 32.5 | 27.5 | tighter |  |
| material.materialize.snappy | dark-photo-reduce-motion | step3e0.delay_ms | 41.67 | 53.33 | 62.5 | 80 | looser |  |
| material.materialize.snappy | dark-stripes | block.step1e0.cx.peak_ms | 41.67 | 33.33 | 62.5 | 50 | tighter |  |
| material.materialize.snappy | dark-stripes | block.step1e0.height.peak_ms | 0 | 16.67 | 17 | 25 | looser |  |
| material.materialize.snappy | dark-stripes | block.step1e0.height.settle_ms | 0 | 16.67 | 17 | 25 | looser |  |
| material.materialize.snappy | dark-stripes | block.step1e0.luma.damping | 0.05 | 0.07 | 0.075 | 0.105 | looser |  |
| material.materialize.snappy | dark-stripes | block.step1e0.luma.response_pct | 8.333 | 9.091 | 12.5 | 13.64 | looser |  |
| material.materialize.snappy | dark-stripes | block.step1e0.progress.damping | 0.07 | 0.06 | 0.105 | 0.09 | tighter | yes |
| material.materialize.snappy | dark-stripes | block.step1e0.progress.response_pct | 9.091 | 8.333 | 13.64 | 12.5 | tighter | yes |
| material.materialize.snappy | dark-stripes | block.step1e0.width.peak_ms | 0 | 16.67 | 17 | 25 | looser |  |
| material.materialize.snappy | dark-stripes | block.step1e0.width.settle_ms | 0 | 16.67 | 17 | 25 | looser |  |
| material.materialize.snappy | dark-stripes | block.step3e0.cx.peak_ms | 33.33 | 41.67 | 50 | 62.5 | looser |  |
| material.materialize.snappy | dark-stripes | block.step3e0.cx.response_pct | 13.33 | 7.692 | 20 | 11.54 | tighter |  |
| material.materialize.snappy | dark-stripes | block.step3e0.cy.peak_ms | 0 | 91.67 | 17 | 137.5 | looser |  |
| material.materialize.snappy | dark-stripes | block.step3e0.height.settle_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.materialize.snappy | dark-stripes | block.step3e0.luma.damping | 0.07 | 0.05 | 0.105 | 0.075 | tighter |  |
| material.materialize.snappy | dark-stripes | block.step3e0.luma.peak_ms | 25 | 91.67 | 37.5 | 137.5 | looser |  |
| material.materialize.snappy | dark-stripes | block.step3e0.luma.response_pct | 4.545 | 9.091 | 6.818 | 13.64 | looser |  |
| material.materialize.snappy | dark-stripes | block.step3e0.luma.settle_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.materialize.snappy | dark-stripes | block.step3e0.progress.damping | 0.07 | 0.05 | 0.105 | 0.075 | tighter | yes |
| material.materialize.snappy | dark-stripes | block.step3e0.progress.response_pct | 4.444 | 8.889 | 6.667 | 13.33 | looser | yes |
| material.materialize.snappy | dark-stripes | block.step3e0.progress.settle_ms | 16.67 | 25 | 25 | 37.5 | looser | yes |
| material.materialize.snappy | dark-stripes | block.step3e0.width.response_pct | 8.333 | 9.091 | 12.5 | 13.64 | looser |  |
| material.materialize.snappy | dark-stripes | step1e0.delay_ms | 18.33 | 16.67 | 27.5 | 25 | tighter |  |
| material.materialize.snappy | dark-stripes | step3e0.delay_ms | 20 | 35 | 30 | 52.5 | looser |  |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step1e0.luma.damping | 0.08 | 0.09 | 0.12 | 0.135 | looser |  |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step1e0.luma.peak_ms | 50 | 16.67 | 75 | 25 | tighter |  |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step1e0.luma.response_pct | 15.79 | 13.64 | 23.68 | 20.45 | tighter |  |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step1e0.progress.damping | 0.08 | 0.04 | 0.12 | 0.06 | tighter | yes |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step1e0.progress.response_pct | 15 | 8.696 | 22.5 | 13.04 | tighter | yes |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step1e0.width.response_pct | 3.922 | 3.774 | 5.882 | 5.66 | tighter |  |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step3e0.cx.peak_ms | 25 | 41.67 | 37.5 | 62.5 | looser |  |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step3e0.cx.response_pct | 42.86 | 50 | 64.29 | 75 | looser |  |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step3e0.height.peak_ms | 250 | 16.67 | 375 | 25 | tighter |  |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step3e0.luma.peak_ms | 25 | 50 | 37.5 | 75 | looser |  |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step3e0.luma.response_pct | 3.704 | 5.556 | 5.556 | 8.333 | looser |  |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step3e0.luma.settle_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step3e0.progress.damping | 0.05 | 0.04 | 0.075 | 0.06 | tighter | yes |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step3e0.progress.response_pct | 3.922 | 5.769 | 5.882 | 8.654 | looser | yes |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step3e0.progress.settle_ms | 16.67 | 33.33 | 25 | 50 | looser | yes |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step3e0.progress.t10_90_ms | 16.67 | 25 | 25 | 37.5 | looser | yes |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step3e0.width.damping | 0.02 | 0.04 | 0.05 | 0.06 | looser |  |
| material.materialize.snappy | dark-stripes-reduce-motion | block.step3e0.width.peak_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.materialize.snappy | dark-stripes-reduce-motion | step1e0.delay_ms | 18.33 | 28.33 | 27.5 | 42.5 | looser |  |
| material.materialize.snappy | dark-stripes-reduce-motion | step3e0.delay_ms | 18.33 | 46.67 | 27.5 | 70 | looser |  |
| material.materialize.snappy | light-photo | block.step1e0.cy.overshoot_pct | 2.412 | 2.442 | 3.617 | 3.663 | looser |  |
| material.materialize.snappy | light-photo | block.step1e0.cy.settle_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.materialize.snappy | light-photo | block.step1e0.luma.damping | 0.07 | 0.08 | 0.105 | 0.12 | looser |  |
| material.materialize.snappy | light-photo | block.step1e0.luma.peak_ms | 133.3 | 141.7 | 200 | 212.5 | looser |  |
| material.materialize.snappy | light-photo | block.step1e0.luma.response_pct | 12.5 | 14.29 | 18.75 | 21.43 | looser |  |
| material.materialize.snappy | light-photo | block.step1e0.progress.damping | 0.07 | 0.05 | 0.105 | 0.075 | tighter | yes |
| material.materialize.snappy | light-photo | block.step1e0.progress.response_pct | 13.04 | 10 | 19.57 | 15 | tighter | yes |
| material.materialize.snappy | light-photo | block.step3e0.cy.response_pct | 42.86 | 53.85 | 64.29 | 80.77 | looser |  |
| material.materialize.snappy | light-photo | block.step3e0.height.response_pct | 53.85 | 66.67 | 80.77 | 100 | looser |  |
| material.materialize.snappy | light-photo | block.step3e0.height.settle_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.materialize.snappy | light-photo | block.step3e0.luma.peak_ms | 41.67 | 50 | 62.5 | 75 | looser |  |
| material.materialize.snappy | light-photo | block.step3e0.luma.response_pct | 15.62 | 18.52 | 23.44 | 27.78 | looser |  |
| material.materialize.snappy | light-photo | block.step3e0.luma.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.materialize.snappy | light-photo | block.step3e0.progress.damping | 0.04 | 0.03 | 0.06 | 0.05 | tighter | yes |
| material.materialize.snappy | light-photo | block.step3e0.progress.response_pct | 15.15 | 16.07 | 22.73 | 24.11 | looser | yes |
| material.materialize.snappy | light-photo | block.step3e0.progress.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter | yes |
| material.materialize.snappy | light-photo | block.step3e0.progress.t10_90_ms | 16.67 | 8.333 | 25 | 17 | tighter | yes |
| material.materialize.snappy | light-photo | block.step3e0.width.damping | 0.22 | 0.24 | 0.33 | 0.36 | looser |  |
| material.materialize.snappy | light-photo | block.step3e0.width.response_pct | 100 | 133.3 | 150 | 200 | looser |  |
| material.materialize.snappy | light-photo | step1e0.delay_ms | 20 | 1.667 | 30 | 17 | tighter |  |
| material.materialize.snappy | light-photo | step3e0.delay_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step1e0.cy.peak_ms | 16.67 | 0 | 25 | 17 | tighter |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step1e0.cy.settle_ms | 16.67 | 0 | 25 | 17 | tighter |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step1e0.height.peak_ms | 16.67 | 0 | 25 | 17 | tighter |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step1e0.luma.damping | 0.04 | 0.07 | 0.06 | 0.105 | looser |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step1e0.luma.peak_ms | 125 | 133.3 | 187.5 | 200 | looser |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step1e0.luma.response_pct | 4.762 | 9.091 | 7.143 | 13.64 | looser |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step1e0.progress.response_pct | 9.524 | 8.696 | 14.29 | 13.04 | tighter | yes |
| material.materialize.snappy | light-photo-reduce-motion | block.step1e0.width.peak_ms | 16.67 | 0 | 25 | 17 | tighter |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step3e0.height.damping | 0.02 | 0.04 | 0.05 | 0.06 | looser |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step3e0.height.response_pct | 11.76 | 13.33 | 17.65 | 20 | looser |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step3e0.luma.damping | 0.04 | 0.03 | 0.06 | 0.05 | tighter |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step3e0.luma.response_pct | 5 | 6.667 | 7.5 | 10 | looser |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step3e0.progress.damping | 0.04 | 0.03 | 0.06 | 0.05 | tighter | yes |
| material.materialize.snappy | light-photo-reduce-motion | block.step3e0.progress.response_pct | 5.085 | 6.78 | 7.627 | 10.17 | looser | yes |
| material.materialize.snappy | light-photo-reduce-motion | block.step3e0.progress.settle_ms | 16.67 | 25 | 25 | 37.5 | looser | yes |
| material.materialize.snappy | light-photo-reduce-motion | block.step3e0.width.damping | 0.07 | 0.08 | 0.105 | 0.12 | looser |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step3e0.width.peak_ms | 25 | 41.67 | 37.5 | 62.5 | looser |  |
| material.materialize.snappy | light-photo-reduce-motion | block.step3e0.width.response_pct | 15.38 | 14.29 | 23.08 | 21.43 | tighter |  |
| material.materialize.snappy | light-photo-reduce-motion | step1e0.delay_ms | 21.67 | 18.33 | 32.5 | 27.5 | tighter |  |
| material.materialize.snappy | light-photo-reduce-motion | step3e0.delay_ms | 26.67 | 20 | 40 | 30 | tighter |  |
| material.materialize.snappy | light-stripes | block.step1e0.cx.peak_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.materialize.snappy | light-stripes | block.step1e0.height.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize.snappy | light-stripes | block.step1e0.luma.peak_ms | 108.3 | 8.333 | 162.5 | 17 | tighter |  |
| material.materialize.snappy | light-stripes | block.step1e0.luma.response_pct | 19.05 | 14.29 | 28.57 | 21.43 | tighter |  |
| material.materialize.snappy | light-stripes | block.step1e0.progress.damping | 0.15 | 0.11 | 0.225 | 0.165 | tighter | yes |
| material.materialize.snappy | light-stripes | block.step1e0.progress.response_pct | 26.32 | 15.79 | 39.47 | 23.68 | tighter | yes |
| material.materialize.snappy | light-stripes | block.step1e0.width.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize.snappy | light-stripes | block.step1e0.width.response_pct | 7.273 | 0 | 10.91 | 5 | tighter |  |
| material.materialize.snappy | light-stripes | block.step3e0.cx.damping | 0.17 | 0.04 | 0.255 | 0.06 | tighter |  |
| material.materialize.snappy | light-stripes | block.step3e0.cx.overshoot_pct | 68.97 | 0.2439 | 103.5 | 2 | tighter |  |
| material.materialize.snappy | light-stripes | block.step3e0.cx.peak_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.materialize.snappy | light-stripes | block.step3e0.cx.response_pct | 18.75 | 23.53 | 28.12 | 35.29 | looser |  |
| material.materialize.snappy | light-stripes | block.step3e0.cx.settle_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.materialize.snappy | light-stripes | block.step3e0.cy.damping | 0.04 | 0.01 | 0.06 | 0.05 | tighter |  |
| material.materialize.snappy | light-stripes | block.step3e0.cy.peak_ms | 391.7 | 341.7 | 587.5 | 512.5 | tighter |  |
| material.materialize.snappy | light-stripes | block.step3e0.cy.response_pct | 7.692 | 0 | 11.54 | 5 | tighter |  |
| material.materialize.snappy | light-stripes | block.step3e0.height.response_pct | 7.692 | 7.143 | 11.54 | 10.71 | tighter |  |
| material.materialize.snappy | light-stripes | block.step3e0.luma.damping | 0.04 | 0.02 | 0.06 | 0.05 | tighter |  |
| material.materialize.snappy | light-stripes | block.step3e0.luma.peak_ms | 50 | 66.67 | 75 | 100 | looser |  |
| material.materialize.snappy | light-stripes | block.step3e0.luma.response_pct | 7.547 | 5.263 | 11.32 | 7.895 | tighter |  |
| material.materialize.snappy | light-stripes | block.step3e0.luma.settle_ms | 8.333 | 25 | 17 | 37.5 | looser |  |
| material.materialize.snappy | light-stripes | block.step3e0.progress.response_pct | 7.143 | 5 | 10.71 | 7.5 | tighter | yes |
| material.materialize.snappy | light-stripes | block.step3e0.progress.settle_ms | 16.67 | 25 | 25 | 37.5 | looser | yes |
| material.materialize.snappy | light-stripes | block.step3e0.progress.t10_90_ms | 8.333 | 25 | 17 | 37.5 | looser | yes |
| material.materialize.snappy | light-stripes | block.step3e0.width.damping | 0.07 | 0.03 | 0.105 | 0.05 | tighter |  |
| material.materialize.snappy | light-stripes | block.step3e0.width.response_pct | 37.5 | 18.18 | 56.25 | 27.27 | tighter |  |
| material.materialize.snappy | light-stripes | step1e0.delay_ms | 23.33 | 6.667 | 35 | 17 | tighter |  |
| material.materialize.snappy | light-stripes | step3e0.delay_ms | 3.334 | 18.33 | 17 | 27.5 | looser |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step1e0.cx.overshoot_pct | 2.041 | 2.296 | 3.061 | 3.444 | looser |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step1e0.cx.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step1e0.luma.damping | 0.11 | 0.08 | 0.165 | 0.12 | tighter |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step1e0.luma.peak_ms | 75 | 16.67 | 112.5 | 25 | tighter |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step1e0.luma.response_pct | 16.67 | 9.091 | 25 | 13.64 | tighter |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step1e0.progress.response_pct | 16.67 | 13.04 | 25 | 19.57 | tighter | yes |
| material.materialize.snappy | light-stripes-reduce-motion | block.step1e0.width.response_pct | 4 | 2 | 6 | 5 | tighter |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step3e0.cx.damping | 0.3 | 0.29 | 0.45 | 0.435 | tighter |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step3e0.cx.overshoot_pct | 86.71 | 87.18 | 130.1 | 130.8 | looser |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step3e0.cx.peak_ms | 16.67 | 41.67 | 25 | 62.5 | looser |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step3e0.cy.overshoot_pct | 1.786 | 0 | 2.679 | 2 | tighter |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step3e0.cy.response_pct | 7.692 | 0 | 11.54 | 5 | tighter |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step3e0.cy.settle_ms | 25 | 0 | 37.5 | 17 | tighter |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step3e0.height.damping | 0.07 | 0.08 | 0.105 | 0.12 | looser |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step3e0.height.peak_ms | 50 | 100 | 75 | 150 | looser |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step3e0.height.response_pct | 14.29 | 12.5 | 21.43 | 18.75 | tighter |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step3e0.luma.damping | 0.04 | 0.07 | 0.06 | 0.105 | looser |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step3e0.luma.response_pct | 1.923 | 5.769 | 5 | 8.654 | looser |  |
| material.materialize.snappy | light-stripes-reduce-motion | block.step3e0.progress.damping | 0.04 | 0.07 | 0.06 | 0.105 | looser | yes |
| material.materialize.snappy | light-stripes-reduce-motion | block.step3e0.progress.response_pct | 1.961 | 5.769 | 5 | 8.654 | looser | yes |
| material.materialize.snappy | light-stripes-reduce-motion | step1e0.delay_ms | 20 | 18.33 | 30 | 27.5 | tighter |  |
| material.materialize.snappy | light-stripes-reduce-motion | step3e0.delay_ms | 30 | 33.33 | 45 | 50 | looser |  |
| material.press.138x53 | dark-photo | glass.step1e0.height.overshoot_pct | 5.882 | 0.5882 | 8.823 | 2 | tighter |  |
| material.press.138x53 | dark-photo | glass.step1e0.luma.peak_ms | 25 | 50 | 37.5 | 75 | looser |  |
| material.press.138x53 | dark-photo | glass.step1e0.width.peak_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.press.138x53 | dark-photo | glass.step1e0.width.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.press.138x53 | dark-photo | glass.step1e1.height.damping | 0.01 | 0.12 | 0.05 | 0.18 | looser |  |
| material.press.138x53 | dark-photo | glass.step1e1.height.overshoot_pct | 0 | 7.353 | 2 | 11.03 | looser |  |
| material.press.138x53 | dark-photo | glass.step1e1.height.peak_ms | 25 | 8.333 | 37.5 | 17 | tighter |  |
| material.press.138x53 | dark-photo | glass.step1e1.height.response_pct | 11.43 | 17.14 | 17.14 | 25.71 | looser |  |
| material.press.138x53 | dark-photo | glass.step1e1.height.settle_ms | 16.67 | 150 | 25 | 225 | looser |  |
| material.press.138x53 | dark-photo | glass.step1e1.luma.peak_ms | 50 | 91.67 | 75 | 137.5 | looser |  |
| material.press.138x53 | dark-photo | glass.step1e1.luma.response_pct | 17.24 | 20 | 25.86 | 30 | looser |  |
| material.press.138x53 | dark-photo | glass.step1e1.luma.settle_ms | 8.333 | 150 | 17 | 225 | looser |  |
| material.press.138x53 | dark-photo | glass.step1e1.width.damping | 0.05 | 0.07 | 0.075 | 0.105 | looser |  |
| material.press.138x53 | dark-photo | glass.step1e1.width.overshoot_pct | 0.4445 | 2.512 | 2 | 3.768 | looser |  |
| material.press.138x53 | dark-photo | glass.step1e1.width.response_pct | 18.18 | 18.52 | 27.27 | 27.78 | looser |  |
| material.press.138x53 | dark-photo | glass.step1e1.width.settle_ms | 25 | 141.7 | 37.5 | 212.5 | looser |  |
| material.press.138x53 | dark-photo | step1e1.delay_ms | 2343 | 31.67 | 3515 | 47.5 | tighter |  |
| material.press.138x53 | dark-photo | step1e2.delay_ms | 2352 | 135 | 3527 | 202.5 | tighter |  |
| material.press.138x53 | dark-stripes | glass.step1e0.height.damping | 0.05 | 0.01 | 0.075 | 0.05 | tighter |  |
| material.press.138x53 | dark-stripes | glass.step1e0.height.overshoot_pct | 6.25 | 5.819 | 9.375 | 8.728 | tighter |  |
| material.press.138x53 | dark-stripes | glass.step1e0.height.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.press.138x53 | dark-stripes | glass.step1e0.height.response_pct | 11.11 | 12.5 | 16.67 | 18.75 | looser |  |
| material.press.138x53 | dark-stripes | glass.step1e0.height.settle_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.press.138x53 | dark-stripes | glass.step1e0.luma.settle_ms | 33.33 | 8.333 | 50 | 17 | tighter |  |
| material.press.138x53 | dark-stripes | glass.step1e0.progress.settle_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.press.138x53 | dark-stripes | glass.step1e0.width.damping | 0.04 | 0.02 | 0.06 | 0.05 | tighter |  |
| material.press.138x53 | dark-stripes | glass.step1e0.width.peak_ms | 25 | 50 | 37.5 | 75 | looser |  |
| material.press.138x53 | dark-stripes | glass.step1e1.height.damping | 0.02 | 0.04 | 0.05 | 0.06 | looser |  |
| material.press.138x53 | dark-stripes | glass.step1e1.height.response_pct | 6.452 | 13.89 | 9.677 | 20.83 | looser |  |
| material.press.138x53 | dark-stripes | glass.step1e1.progress.damping | 0.12 | 0.17 | 0.18 | 0.255 | looser |  |
| material.press.138x53 | dark-stripes | glass.step1e1.progress.response_pct | 21.31 | 22.97 | 31.97 | 34.46 | looser |  |
| material.press.138x53 | dark-stripes | glass.step1e1.progress.t10_90_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.press.138x53 | dark-stripes | glass.step1e1.width.response_pct | 10.71 | 15.15 | 16.07 | 22.73 | looser |  |
| material.press.138x53 | dark-stripes | glass.step1e1.width.settle_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.press.138x53 | dark-stripes | glass.step1e2.luma.peak_ms | 266.7 | 175 | 400 | 262.5 | tighter |  |
| material.press.138x53 | dark-stripes | step1e0.delay_ms | 10 | 21.67 | 17 | 32.5 | looser |  |
| material.press.138x53 | dark-stripes | step1e1.delay_ms | 2182 | 46.67 | 3273 | 70 | tighter |  |
| material.press.138x53 | dark-stripes | step1e2.delay_ms | 2182 | 41.67 | 3273 | 62.5 | tighter |  |
| material.press.138x53 | light-photo | glass.step1e0.height.peak_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.press.138x53 | light-photo | glass.step1e0.height.response_pct | 12.5 | 28.57 | 18.75 | 42.86 | looser |  |
| material.press.138x53 | light-photo | glass.step1e0.luma.settle_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.press.138x53 | light-photo | glass.step1e0.width.response_pct | 8.108 | 24.32 | 12.16 | 36.49 | looser |  |
| material.press.138x53 | light-photo | glass.step1e1.height.peak_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.press.138x53 | light-photo | glass.step1e1.height.response_pct | 14.81 | 18.52 | 22.22 | 27.78 | looser |  |
| material.press.138x53 | light-photo | glass.step1e1.height.settle_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.press.138x53 | light-photo | glass.step1e1.luma.damping | 0.09 | 0.11 | 0.135 | 0.165 | looser |  |
| material.press.138x53 | light-photo | glass.step1e1.luma.response_pct | 20 | 23.08 | 30 | 34.62 | looser |  |
| material.press.138x53 | light-photo | glass.step1e1.width.response_pct | 10.34 | 13.79 | 15.52 | 20.69 | looser |  |
| material.press.138x53 | light-photo | step1e0.delay_ms | 16.67 | 15 | 25 | 22.5 | tighter |  |
| material.press.138x53 | light-photo | step1e1.delay_ms | 2183 | 36.67 | 3275 | 55 | tighter |  |
| material.press.138x53 | light-photo | step1e2.delay_ms | 2313 | 211.7 | 3470 | 317.5 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e0.height.damping | 0.05 | 0.02 | 0.075 | 0.05 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e0.height.peak_ms | 58.33 | 16.67 | 87.5 | 25 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e0.height.response_pct | 34.29 | 23.08 | 51.43 | 34.62 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e0.height.settle_ms | 91.67 | 25 | 137.5 | 37.5 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e0.luma.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e0.luma.response_pct | 0 | 8.333 | 5 | 12.5 | looser |  |
| material.press.138x53 | light-stripes | glass.step1e0.luma.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e0.width.peak_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e0.width.response_pct | 27.03 | 22.5 | 40.54 | 33.75 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e0.width.settle_ms | 50 | 25 | 75 | 37.5 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e1.height.damping | 0.07 | 0.03 | 0.105 | 0.05 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e1.height.response_pct | 19.35 | 12.5 | 29.03 | 18.75 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e1.luma.damping | 0.17 | 0.09 | 0.255 | 0.135 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e1.luma.overshoot_pct | 0.768 | 1.789 | 2 | 2.683 | looser |  |
| material.press.138x53 | light-stripes | glass.step1e1.luma.response_pct | 29.03 | 19.23 | 43.55 | 28.85 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e1.width.damping | 0.06 | 0.02 | 0.09 | 0.05 | tighter |  |
| material.press.138x53 | light-stripes | glass.step1e1.width.response_pct | 21.88 | 10.34 | 32.81 | 15.52 | tighter |  |
| material.press.138x53 | light-stripes | step1e0.delay_ms | 20 | 21.67 | 30 | 32.5 | looser |  |
| material.press.138x53 | light-stripes | step1e1.delay_ms | 2275 | 33.33 | 3413 | 50 | tighter |  |
| material.press.138x53 | light-stripes | step1e2.delay_ms | 2280 | 38.33 | 3420 | 57.5 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e0.luma.peak_ms | 50 | 8.333 | 75 | 17 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e0.luma.settle_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e0.width.damping | 0.04 | 0.03 | 0.06 | 0.05 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e0.width.overshoot_pct | 2.064 | 2.025 | 3.096 | 3.037 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e0.width.peak_ms | 75 | 50 | 112.5 | 75 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e0.width.response_pct | 23.08 | 10.42 | 34.62 | 15.62 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e0.width.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e1.luma.damping | 0 | 0.21 | 0.05 | 0.315 | looser |  |
| material.press.250x44 | dark-photo | glass.step1e1.luma.peak_ms | 58.33 | 41.67 | 87.5 | 62.5 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e1.luma.response_pct | 0 | 14.02 | 5 | 21.03 | looser |  |
| material.press.250x44 | dark-photo | glass.step1e1.luma.settle_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e1.width.damping | 0.15 | 0.09 | 0.225 | 0.135 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e1.width.overshoot_pct | 3.6 | 2.041 | 5.4 | 3.061 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e1.width.peak_ms | 58.33 | 41.67 | 87.5 | 62.5 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e1.width.response_pct | 52.63 | 28 | 78.95 | 42 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e1.width.settle_ms | 41.67 | 58.33 | 62.5 | 87.5 | looser |  |
| material.press.250x44 | dark-photo | glass.step1e2.luma.damping | 0.07 | 0.02 | 0.105 | 0.05 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e2.luma.peak_ms | 166.7 | 241.7 | 250 | 362.5 | looser |  |
| material.press.250x44 | dark-photo | glass.step1e2.luma.response_pct | 216.7 | 108.3 | 325 | 162.5 | tighter |  |
| material.press.250x44 | dark-photo | glass.step1e2.luma.settle_ms | 41.67 | 66.67 | 62.5 | 100 | looser |  |
| material.press.250x44 | dark-photo | step1e1.delay_ms | 2710 | 30 | 4065 | 45 | tighter |  |
| material.press.250x44 | dark-photo | step1e2.delay_ms | 2692 | 81.67 | 4038 | 122.5 | tighter |  |
| material.press.250x44 | dark-stripes | glass.step1e0.luma.peak_ms | 66.67 | 75 | 100 | 112.5 | looser |  |
| material.press.250x44 | dark-stripes | glass.step1e0.progress.rms | 0.0411 | 0.03721 | 0.06166 | 0.05581 | tighter |  |
| material.press.250x44 | dark-stripes | glass.step1e0.progress.settle_ms | 25 | 41.67 | 37.5 | 62.5 | looser |  |
| material.press.250x44 | dark-stripes | glass.step1e0.width.peak_ms | 41.67 | 25 | 62.5 | 37.5 | tighter |  |
| material.press.250x44 | dark-stripes | glass.step1e0.width.response_pct | 20 | 33.33 | 30 | 50 | looser |  |
| material.press.250x44 | dark-stripes | glass.step1e0.width.settle_ms | 41.67 | 33.33 | 62.5 | 50 | tighter |  |
| material.press.250x44 | dark-stripes | glass.step1e1.width.response_pct | 34.78 | 29.03 | 52.17 | 43.55 | tighter |  |
| material.press.250x44 | dark-stripes | glass.step1e2.luma.peak_ms | 91.67 | 183.3 | 137.5 | 275 | looser |  |
| material.press.250x44 | dark-stripes | glass.step1e2.luma.settle_ms | 8.333 | 25 | 17 | 37.5 | looser |  |
| material.press.250x44 | dark-stripes | glass.step1e2.progress.settle_ms | 16.67 | 33.33 | 25 | 50 | looser |  |
| material.press.250x44 | dark-stripes | step1e0.delay_ms | 16.67 | 18.33 | 25 | 27.5 | looser |  |
| material.press.250x44 | dark-stripes | step1e1.delay_ms | 2715 | 400 | 4072 | 600 | tighter |  |
| material.press.250x44 | dark-stripes | step1e2.delay_ms | 2693 | 21.67 | 4040 | 32.5 | tighter |  |
| material.press.250x44 | light-photo | glass.step1e0.luma.peak_ms | 16.67 | 33.33 | 25 | 50 | looser |  |
| material.press.250x44 | light-photo | glass.step1e0.luma.settle_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.press.250x44 | light-photo | glass.step1e0.width.response_pct | 10.87 | 12.2 | 16.3 | 18.29 | looser |  |
| material.press.250x44 | light-photo | glass.step1e0.width.settle_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.press.250x44 | light-photo | glass.step1e1.luma.peak_ms | 50 | 8.333 | 75 | 17 | tighter |  |
| material.press.250x44 | light-photo | glass.step1e1.luma.settle_ms | 8.333 | 16.67 | 17 | 25 | looser |  |
| material.press.250x44 | light-photo | glass.step1e1.width.damping | 0.09 | 0.1 | 0.135 | 0.15 | looser |  |
| material.press.250x44 | light-photo | glass.step1e1.width.response_pct | 25.93 | 24 | 38.89 | 36 | tighter |  |
| material.press.250x44 | light-photo | glass.step1e1.width.settle_ms | 58.33 | 50 | 87.5 | 75 | tighter |  |
| material.press.250x44 | light-photo | glass.step1e2.luma.peak_ms | 150 | 241.7 | 225 | 362.5 | looser |  |
| material.press.250x44 | light-photo | step1e0.delay_ms | 13.33 | 15 | 20 | 22.5 | looser |  |
| material.press.250x44 | light-photo | step1e1.delay_ms | 2613 | 46.67 | 3920 | 70 | tighter |  |
| material.press.250x44 | light-photo | step1e2.delay_ms | 2718 | 136.7 | 4077 | 205 | tighter |  |
| material.press.250x44 | light-stripes | glass.step1e0.luma.peak_ms | 75 | 41.67 | 112.5 | 62.5 | tighter |  |
| material.press.250x44 | light-stripes | glass.step1e0.luma.settle_ms | 41.67 | 25 | 62.5 | 37.5 | tighter |  |
| material.press.250x44 | light-stripes | glass.step1e0.width.overshoot_pct | 2.215 | 0 | 3.322 | 2 | tighter |  |
| material.press.250x44 | light-stripes | glass.step1e0.width.peak_ms | 133.3 | 16.67 | 200 | 25 | tighter |  |
| material.press.250x44 | light-stripes | glass.step1e0.width.response_pct | 32.73 | 23.4 | 49.09 | 35.11 | tighter |  |
| material.press.250x44 | light-stripes | glass.step1e0.width.settle_ms | 141.7 | 25 | 212.5 | 37.5 | tighter |  |
| material.press.250x44 | light-stripes | glass.step1e1.luma.peak_ms | 25 | 8.333 | 37.5 | 17 | tighter |  |
| material.press.250x44 | light-stripes | glass.step1e1.width.damping | 0.08 | 0.02 | 0.12 | 0.05 | tighter |  |
| material.press.250x44 | light-stripes | glass.step1e1.width.overshoot_pct | 2.658 | 0 | 3.987 | 2 | tighter |  |
| material.press.250x44 | light-stripes | glass.step1e1.width.peak_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.press.250x44 | light-stripes | glass.step1e1.width.response_pct | 25 | 10 | 37.5 | 15 | tighter |  |
| material.press.250x44 | light-stripes | glass.step1e1.width.settle_ms | 41.67 | 16.67 | 62.5 | 25 | tighter |  |
| material.press.250x44 | light-stripes | step1e0.delay_ms | 18.33 | 21.67 | 27.5 | 32.5 | looser |  |
| material.press.250x44 | light-stripes | step1e1.delay_ms | 2395 | 36.67 | 3592 | 55 | tighter |  |
| material.press.250x44 | light-stripes | step1e2.delay_ms | 2395 | 36.67 | 3592 | 55 | tighter |  |
| material.press.300x120 | dark-photo | glass.step1e0.luma.settle_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.press.300x120 | dark-photo | glass.step1e0.width.response_pct | 29.41 | 8.696 | 44.12 | 13.04 | tighter |  |
| material.press.300x120 | dark-photo | glass.step1e0.width.settle_ms | 75 | 50 | 112.5 | 75 | tighter |  |
| material.press.300x120 | dark-photo | glass.step1e1.luma.peak_ms | 16.67 | 66.67 | 25 | 100 | looser |  |
| material.press.300x120 | dark-photo | glass.step1e1.luma.settle_ms | 41.67 | 25 | 62.5 | 37.5 | tighter |  |
| material.press.300x120 | dark-photo | glass.step1e1.width.damping | 0.23 | 0.27 | 0.345 | 0.405 | looser |  |
| material.press.300x120 | dark-photo | glass.step1e1.width.response_pct | 37.04 | 76.47 | 55.56 | 114.7 | looser |  |
| material.press.300x120 | dark-photo | glass.step1e1.width.settle_ms | 25 | 8.333 | 37.5 | 17 | tighter |  |
| material.press.300x120 | dark-photo | glass.step1e2.luma.peak_ms | 133.3 | 183.3 | 200 | 275 | looser |  |
| material.press.300x120 | dark-photo | glass.step1e2.luma.settle_ms | 25 | 8.333 | 37.5 | 17 | tighter |  |
| material.press.300x120 | dark-photo | step1e0.delay_ms | 13.33 | 21.67 | 20 | 32.5 | looser |  |
| material.press.300x120 | dark-photo | step1e1.delay_ms | 3487 | 30 | 5230 | 45 | tighter |  |
| material.press.300x120 | dark-photo | step1e2.delay_ms | 3492 | 33.33 | 5238 | 50 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e0.luma.peak_ms | 83.33 | 16.67 | 125 | 25 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e0.luma.settle_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e0.progress.rms | 0.05125 | 0.0165 | 0.07687 | 0.05 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e0.progress.settle_ms | 58.33 | 16.67 | 87.5 | 25 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e0.progress.t10_90_ms | 25 | 8.333 | 37.5 | 17 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e0.width.damping | 0.14 | 0.12 | 0.21 | 0.18 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e0.width.overshoot_pct | 12.5 | 8.333 | 18.75 | 12.5 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e0.width.peak_ms | 58.33 | 125 | 87.5 | 187.5 | looser |  |
| material.press.300x120 | dark-stripes | glass.step1e0.width.response_pct | 36.51 | 10.2 | 54.76 | 15.31 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e0.width.settle_ms | 125 | 58.33 | 187.5 | 87.5 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e1.luma.peak_ms | 141.7 | 100 | 212.5 | 150 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e1.luma.settle_ms | 91.67 | 83.33 | 137.5 | 125 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e1.progress.rms | 0.06995 | 0.05814 | 0.1049 | 0.08721 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e1.progress.settle_ms | 91.67 | 83.33 | 137.5 | 125 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e1.progress.t10_90_ms | 66.67 | 50 | 100 | 75 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e1.width.damping | 0.07 | 0.01 | 0.105 | 0.05 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e1.width.peak_ms | 16.67 | 41.67 | 25 | 62.5 | looser |  |
| material.press.300x120 | dark-stripes | glass.step1e1.width.response_pct | 20 | 6.897 | 30 | 10.34 | tighter |  |
| material.press.300x120 | dark-stripes | glass.step1e2.luma.peak_ms | 175 | 133.3 | 262.5 | 200 | tighter |  |
| material.press.300x120 | dark-stripes | step1e1.delay_ms | 2585 | 65 | 3878 | 97.5 | tighter |  |
| material.press.300x120 | dark-stripes | step1e2.delay_ms | 2678 | 48.33 | 4018 | 72.5 | tighter |  |
| material.press.300x120 | light-photo | glass.step1e0.luma.peak_ms | 58.33 | 50 | 87.5 | 75 | tighter |  |
| material.press.300x120 | light-photo | glass.step1e0.luma.settle_ms | 66.67 | 16.67 | 100 | 25 | tighter |  |
| material.press.300x120 | light-photo | glass.step1e0.width.damping | 0.04 | 0.02 | 0.06 | 0.05 | tighter |  |
| material.press.300x120 | light-photo | glass.step1e0.width.peak_ms | 50 | 25 | 75 | 37.5 | tighter |  |
| material.press.300x120 | light-photo | glass.step1e0.width.response_pct | 86.96 | 23.08 | 130.4 | 34.62 | tighter |  |
| material.press.300x120 | light-photo | glass.step1e0.width.settle_ms | 50 | 33.33 | 75 | 50 | tighter |  |
| material.press.300x120 | light-photo | glass.step1e1.luma.damping | 0.3 | 0.08 | 0.45 | 0.12 | tighter |  |
| material.press.300x120 | light-photo | glass.step1e1.luma.response_pct | 9.396 | 0.6849 | 14.09 | 5 | tighter |  |
| material.press.300x120 | light-photo | glass.step1e1.luma.settle_ms | 25 | 33.33 | 37.5 | 50 | looser |  |
| material.press.300x120 | light-photo | glass.step1e1.width.peak_ms | 8.333 | 41.67 | 17 | 62.5 | looser |  |
| material.press.300x120 | light-photo | glass.step1e1.width.response_pct | 13.33 | 40 | 20 | 60 | looser |  |
| material.press.300x120 | light-photo | glass.step1e1.width.settle_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.press.300x120 | light-photo | glass.step1e2.luma.peak_ms | 108.3 | 116.7 | 162.5 | 175 | looser |  |
| material.press.300x120 | light-photo | glass.step1e2.luma.settle_ms | 50 | 83.33 | 75 | 125 | looser |  |
| material.press.300x120 | light-photo | step1e0.delay_ms | 5 | 20 | 17 | 30 | looser |  |
| material.press.300x120 | light-photo | step1e1.delay_ms | 2430 | 30 | 3645 | 45 | tighter |  |
| material.press.300x120 | light-photo | step1e2.delay_ms | 2490 | 63.33 | 3735 | 95 | tighter |  |
| material.press.300x120 | light-stripes | glass.step1e0.luma.overshoot_pct | 0.3048 | 1.799 | 2 | 2.699 | looser |  |
| material.press.300x120 | light-stripes | glass.step1e0.luma.peak_ms | 33.33 | 66.67 | 50 | 100 | looser |  |
| material.press.300x120 | light-stripes | glass.step1e0.luma.settle_ms | 83.33 | 58.33 | 125 | 87.5 | tighter |  |
| material.press.300x120 | light-stripes | glass.step1e0.width.damping | 0.02 | 0.1 | 0.05 | 0.15 | looser |  |
| material.press.300x120 | light-stripes | glass.step1e0.width.overshoot_pct | 0 | 8.333 | 2 | 12.5 | looser |  |
| material.press.300x120 | light-stripes | glass.step1e0.width.peak_ms | 25 | 66.67 | 37.5 | 100 | looser |  |
| material.press.300x120 | light-stripes | glass.step1e0.width.response_pct | 21.28 | 59.46 | 31.91 | 89.19 | looser |  |
| material.press.300x120 | light-stripes | glass.step1e0.width.settle_ms | 33.33 | 66.67 | 50 | 100 | looser |  |
| material.press.300x120 | light-stripes | glass.step1e1.luma.damping | 1.32 | 1.34 | 1.98 | 2.01 | looser |  |
| material.press.300x120 | light-stripes | glass.step1e1.luma.peak_ms | 33.33 | 25 | 50 | 37.5 | tighter |  |
| material.press.300x120 | light-stripes | glass.step1e1.luma.response_pct | 114.6 | 126.5 | 171.9 | 189.8 | looser |  |
| material.press.300x120 | light-stripes | glass.step1e1.luma.settle_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.press.300x120 | light-stripes | glass.step1e1.width.damping | 0.04 | 0.11 | 0.06 | 0.165 | looser |  |
| material.press.300x120 | light-stripes | glass.step1e1.width.response_pct | 16.13 | 36.36 | 24.19 | 54.55 | looser |  |
| material.press.300x120 | light-stripes | glass.step1e1.width.settle_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.press.300x120 | light-stripes | glass.step1e2.luma.peak_ms | 100 | 250 | 150 | 375 | looser |  |
| material.press.300x120 | light-stripes | step1e0.delay_ms | 13.33 | 35 | 20 | 52.5 | looser |  |
| material.press.300x120 | light-stripes | step1e1.delay_ms | 2550 | 21.67 | 3825 | 32.5 | tighter |  |
| material.press.300x120 | light-stripes | step1e2.delay_ms | 2557 | 21.67 | 3835 | 32.5 | tighter |  |
| material.press.360x200 | dark-photo | glass.step1e0.luma.peak_ms | 100 | 33.33 | 150 | 50 | tighter |  |
| material.press.360x200 | dark-photo | glass.step1e0.luma.response_pct | 16.67 | 0 | 25 | 5 | tighter |  |
| material.press.360x200 | dark-photo | glass.step1e0.luma.settle_ms | 83.33 | 25 | 125 | 37.5 | tighter |  |
| material.press.360x200 | dark-photo | glass.step1e1.luma.damping | 0.09 | 0.12 | 0.135 | 0.18 | looser |  |
| material.press.360x200 | dark-photo | glass.step1e1.luma.peak_ms | 216.7 | 50 | 325 | 75 | tighter |  |
| material.press.360x200 | dark-photo | glass.step1e1.luma.response_pct | 8.451 | 23.68 | 12.68 | 35.53 | looser |  |
| material.press.360x200 | dark-photo | glass.step1e1.luma.settle_ms | 0 | 25 | 17 | 37.5 | looser |  |
| material.press.360x200 | dark-photo | step1e0.delay_ms | 11.67 | 21.67 | 17.5 | 32.5 | looser |  |
| material.press.360x200 | dark-photo | step1e1.delay_ms | 96.67 | 48.33 | 145 | 72.5 | tighter |  |
| material.press.360x200 | dark-stripes | glass.step1e0.luma.overshoot_pct | 0.7945 | 1.359 | 2 | 2.038 | looser |  |
| material.press.360x200 | dark-stripes | glass.step1e0.luma.settle_ms | 16.67 | 33.33 | 25 | 50 | looser |  |
| material.press.360x200 | dark-stripes | glass.step1e0.width.damping | 0.25 | 0.1 | 0.375 | 0.15 | tighter |  |
| material.press.360x200 | dark-stripes | glass.step1e0.width.peak_ms | 8.333 | 33.33 | 17 | 50 | looser |  |
| material.press.360x200 | dark-stripes | glass.step1e0.width.response_pct | 85.71 | 23.08 | 128.6 | 34.62 | tighter |  |
| material.press.360x200 | dark-stripes | glass.step1e0.width.settle_ms | 0 | 33.33 | 17 | 50 | looser |  |
| material.press.360x200 | dark-stripes | glass.step1e1.luma.damping | 0.17 | 0.18 | 0.255 | 0.27 | looser |  |
| material.press.360x200 | dark-stripes | glass.step1e1.luma.peak_ms | 91.67 | 41.67 | 137.5 | 62.5 | tighter |  |
| material.press.360x200 | dark-stripes | glass.step1e1.luma.response_pct | 26.83 | 23.08 | 40.24 | 34.62 | tighter |  |
| material.press.360x200 | dark-stripes | glass.step1e1.luma.settle_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.press.360x200 | dark-stripes | glass.step1e1.width.damping | 1.25 | 0.09 | 1.875 | 0.135 | tighter |  |
| material.press.360x200 | dark-stripes | glass.step1e1.width.peak_ms | 108.3 | 250 | 162.5 | 375 | looser |  |
| material.press.360x200 | dark-stripes | glass.step1e1.width.response_pct | 372.7 | 36.54 | 559.1 | 54.81 | tighter |  |
| material.press.360x200 | dark-stripes | glass.step1e1.width.settle_ms | 83.33 | 216.7 | 125 | 325 | looser |  |
| material.press.360x200 | dark-stripes | step1e0.delay_ms | 0 | 21.67 | 17 | 32.5 | looser |  |
| material.press.360x200 | dark-stripes | step1e1.delay_ms | 3523 | 46.67 | 5285 | 70 | tighter |  |
| material.press.360x200 | light-photo | glass.step1e0.width.damping | 0.12 | 0.02 | 0.18 | 0.05 | tighter |  |
| material.press.360x200 | light-photo | glass.step1e0.width.overshoot_pct | 15.83 | 7.778 | 23.75 | 11.67 | tighter |  |
| material.press.360x200 | light-photo | glass.step1e0.width.response_pct | 26.67 | 10.53 | 40 | 15.79 | tighter |  |
| material.press.360x200 | light-photo | glass.step1e0.width.settle_ms | 58.33 | 66.67 | 87.5 | 100 | looser |  |
| material.press.360x200 | light-photo | glass.step1e1.width.damping | 0.31 | 0.34 | 0.465 | 0.51 | looser |  |
| material.press.360x200 | light-photo | glass.step1e1.width.overshoot_pct | 7.692 | 25 | 11.54 | 37.5 | looser |  |
| material.press.360x200 | light-photo | glass.step1e1.width.response_pct | 20.69 | 47.83 | 31.03 | 71.74 | looser |  |
| material.press.360x200 | light-photo | step1e0.delay_ms | 23.33 | 25 | 35 | 37.5 | looser |  |
| material.press.360x200 | light-photo | step1e1.delay_ms | 3368 | 35 | 5053 | 52.5 | tighter |  |
| material.press.360x200 | light-stripes | glass.step1e0.width.peak_ms | 0 | 16.67 | 17 | 25 | looser |  |
| material.press.360x200 | light-stripes | glass.step1e0.width.response_pct | 0 | 10.17 | 5 | 15.25 | looser |  |
| material.press.360x200 | light-stripes | glass.step1e0.width.settle_ms | 0 | 16.67 | 17 | 25 | looser |  |
| material.press.360x200 | light-stripes | step1e0.delay_ms | 6.666 | 11.67 | 17 | 17.5 | looser |  |
| material.press.360x200 | light-stripes | step1e1.delay_ms | 3492 | 33.33 | 5237 | 50 | tighter |  |
| material.press.circle58 | dark-photo | glass.step1e0.height.response_pct | 29.41 | 20.45 | 44.12 | 30.68 | tighter |  |
| material.press.circle58 | dark-photo | glass.step1e0.height.settle_ms | 41.67 | 25 | 62.5 | 37.5 | tighter |  |
| material.press.circle58 | dark-photo | glass.step1e0.luma.peak_ms | 41.67 | 16.67 | 62.5 | 25 | tighter |  |
| material.press.circle58 | dark-photo | glass.step1e0.luma.settle_ms | 41.67 | 16.67 | 62.5 | 25 | tighter |  |
| material.press.circle58 | dark-photo | glass.step1e0.width.response_pct | 32.35 | 20 | 48.53 | 30 | tighter |  |
| material.press.circle58 | dark-photo | glass.step1e0.width.settle_ms | 41.67 | 25 | 62.5 | 37.5 | tighter |  |
| material.press.circle58 | dark-photo | glass.step1e1.height.peak_ms | 25 | 33.33 | 37.5 | 50 | looser |  |
| material.press.circle58 | dark-photo | glass.step1e1.height.response_pct | 8.108 | 17.65 | 12.16 | 26.47 | looser |  |
| material.press.circle58 | dark-photo | glass.step1e1.luma.damping | 0.04 | 0.5 | 0.06 | 0.75 | looser |  |
| material.press.circle58 | dark-photo | glass.step1e1.luma.peak_ms | 133.3 | 141.7 | 200 | 212.5 | looser |  |
| material.press.circle58 | dark-photo | glass.step1e1.luma.response_pct | 4 | 43.75 | 6 | 65.63 | looser |  |
| material.press.circle58 | dark-photo | glass.step1e1.luma.settle_ms | 208.3 | 241.7 | 312.5 | 362.5 | looser |  |
| material.press.circle58 | dark-photo | glass.step1e1.width.response_pct | 10.81 | 21.21 | 16.22 | 31.82 | looser |  |
| material.press.circle58 | dark-photo | glass.step1e1.width.settle_ms | 208.3 | 216.7 | 312.5 | 325 | looser |  |
| material.press.circle58 | dark-photo | step1e1.delay_ms | 2283 | 18.33 | 3425 | 27.5 | tighter |  |
| material.press.circle58 | dark-photo | step1e2.delay_ms | 2378 | 196.7 | 3567 | 295 | tighter |  |
| material.press.circle58 | dark-stripes | glass.step1e0.height.peak_ms | 16.67 | 33.33 | 25 | 50 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e0.height.response_pct | 21.43 | 24.24 | 32.14 | 36.36 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e0.luma.peak_ms | 33.33 | 16.67 | 50 | 25 | tighter |  |
| material.press.circle58 | dark-stripes | glass.step1e0.luma.settle_ms | 75 | 83.33 | 112.5 | 125 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e0.progress.rms | 0.05711 | 0.05421 | 0.08566 | 0.08132 | tighter |  |
| material.press.circle58 | dark-stripes | glass.step1e0.progress.t10_90_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.press.circle58 | dark-stripes | glass.step1e0.width.overshoot_pct | 1.864 | 1.949 | 2.796 | 2.923 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e0.width.response_pct | 21.43 | 24.24 | 32.14 | 36.36 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e0.width.settle_ms | 16.67 | 141.7 | 25 | 212.5 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e1.height.damping | 0.06 | 0.07 | 0.09 | 0.105 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e1.height.response_pct | 16.22 | 22.58 | 24.32 | 33.87 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e1.height.settle_ms | 183.3 | 191.7 | 275 | 287.5 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e1.luma.damping | 0.6 | 0.12 | 0.9 | 0.18 | tighter |  |
| material.press.circle58 | dark-stripes | glass.step1e1.luma.peak_ms | 133.3 | 141.7 | 200 | 212.5 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e1.luma.response_pct | 34.62 | 5.263 | 51.92 | 7.895 | tighter |  |
| material.press.circle58 | dark-stripes | glass.step1e1.luma.settle_ms | 191.7 | 216.7 | 287.5 | 325 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e1.progress.damping | 0.3 | 0.13 | 0.45 | 0.195 | tighter |  |
| material.press.circle58 | dark-stripes | glass.step1e1.progress.response_pct | 20.93 | 6.667 | 31.4 | 10 | tighter |  |
| material.press.circle58 | dark-stripes | glass.step1e1.progress.rms | 0.17 | 0.1732 | 0.2551 | 0.2598 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e1.progress.settle_ms | 183.3 | 233.3 | 275 | 350 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e1.progress.t10_90_ms | 283.3 | 266.7 | 425 | 400 | tighter |  |
| material.press.circle58 | dark-stripes | glass.step1e1.width.damping | 0.09 | 0.08 | 0.135 | 0.12 | tighter |  |
| material.press.circle58 | dark-stripes | glass.step1e1.width.overshoot_pct | 15.78 | 13.78 | 23.67 | 20.67 | tighter |  |
| material.press.circle58 | dark-stripes | glass.step1e1.width.peak_ms | 41.67 | 33.33 | 62.5 | 50 | tighter |  |
| material.press.circle58 | dark-stripes | glass.step1e1.width.response_pct | 18.42 | 19.35 | 27.63 | 29.03 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e2.progress.settle_ms | 66.67 | 50 | 100 | 75 | tighter |  |
| material.press.circle58 | dark-stripes | step1e0.delay_ms | 15 | 30 | 22.5 | 45 | looser |  |
| material.press.circle58 | dark-stripes | step1e1.delay_ms | 2473 | 261.7 | 3710 | 392.5 | tighter |  |
| material.press.circle58 | dark-stripes | step1e2.delay_ms | 2635 | 270 | 3953 | 405 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e0.height.overshoot_pct | 4.043 | 2.057 | 6.064 | 3.085 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e0.height.peak_ms | 33.33 | 66.67 | 50 | 100 | looser |  |
| material.press.circle58 | light-photo | glass.step1e0.height.response_pct | 18.6 | 22.86 | 27.91 | 34.29 | looser |  |
| material.press.circle58 | light-photo | glass.step1e0.luma.damping | 0.06 | 0.05 | 0.09 | 0.075 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e0.luma.response_pct | 23.53 | 30.77 | 35.29 | 46.15 | looser |  |
| material.press.circle58 | light-photo | glass.step1e0.progress.settle_ms | 25 | 16.67 | 37.5 | 25 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e0.width.response_pct | 18.6 | 22.86 | 27.91 | 34.29 | looser |  |
| material.press.circle58 | light-photo | glass.step1e1.height.overshoot_pct | 10.24 | 8.333 | 15.36 | 12.5 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.height.peak_ms | 33.33 | 8.333 | 50 | 17 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.height.response_pct | 10.81 | 8.824 | 16.22 | 13.24 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.height.settle_ms | 116.7 | 100 | 175 | 150 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.luma.damping | 1.4 | 0.01 | 2.1 | 0.05 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.luma.overshoot_pct | 13.17 | 11.99 | 19.75 | 17.99 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.luma.peak_ms | 416.7 | 408.3 | 625 | 612.5 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.luma.response_pct | 57.58 | 3.03 | 86.36 | 5 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.luma.settle_ms | 166.7 | 141.7 | 250 | 212.5 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.progress.overshoot_pct | 46.2 | 43.61 | 69.29 | 65.41 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.progress.response_pct | 4.651 | 2.273 | 6.977 | 5 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.progress.rms | 0.3522 | 0.3401 | 0.5283 | 0.5101 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.progress.sharpness | 0.6743 | 0.7782 | 1.011 | 1.167 | looser |  |
| material.press.circle58 | light-photo | glass.step1e1.progress.t10_90_ms | 433.3 | 416.7 | 650 | 625 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.width.damping | 0.06 | 0.05 | 0.09 | 0.075 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.width.overshoot_pct | 13.43 | 10.51 | 20.14 | 15.77 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.width.response_pct | 11.11 | 9.091 | 16.67 | 13.64 | tighter |  |
| material.press.circle58 | light-photo | glass.step1e1.width.settle_ms | 225 | 83.33 | 337.5 | 125 | tighter |  |
| material.press.circle58 | light-photo | step1e1.delay_ms | 2205 | 20 | 3308 | 30 | tighter |  |
| material.press.circle58 | light-photo | step1e2.delay_ms | 2392 | 233.3 | 3588 | 350 | tighter |  |
| material.press.circle58 | light-stripes | glass.step1e0.height.damping | 0.07 | 0.08 | 0.105 | 0.12 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e0.height.peak_ms | 41.67 | 33.33 | 62.5 | 50 | tighter |  |
| material.press.circle58 | light-stripes | glass.step1e0.height.response_pct | 18.18 | 25 | 27.27 | 37.5 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e0.height.settle_ms | 108.3 | 91.67 | 162.5 | 137.5 | tighter |  |
| material.press.circle58 | light-stripes | glass.step1e0.luma.damping | 0.11 | 0.09 | 0.165 | 0.135 | tighter |  |
| material.press.circle58 | light-stripes | glass.step1e0.luma.response_pct | 23.53 | 34.62 | 35.29 | 51.92 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e0.luma.settle_ms | 41.67 | 50 | 62.5 | 75 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e0.progress.rms | 0.03779 | 0.03752 | 0.05669 | 0.05629 | tighter |  |
| material.press.circle58 | light-stripes | glass.step1e0.progress.t10_90_ms | 16.67 | 8.333 | 25 | 17 | tighter |  |
| material.press.circle58 | light-stripes | glass.step1e0.width.overshoot_pct | 2.187 | 0.4167 | 3.281 | 2 | tighter |  |
| material.press.circle58 | light-stripes | glass.step1e0.width.peak_ms | 75 | 66.67 | 112.5 | 100 | tighter |  |
| material.press.circle58 | light-stripes | glass.step1e0.width.response_pct | 18.92 | 25 | 28.38 | 37.5 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e0.width.settle_ms | 141.7 | 125 | 212.5 | 187.5 | tighter |  |
| material.press.circle58 | light-stripes | glass.step1e1.height.damping | 0.04 | 0.03 | 0.06 | 0.05 | tighter |  |
| material.press.circle58 | light-stripes | glass.step1e1.height.overshoot_pct | 3.083 | 2.594 | 4.625 | 3.89 | tighter |  |
| material.press.circle58 | light-stripes | glass.step1e1.height.peak_ms | 0 | 25 | 17 | 37.5 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e1.height.response_pct | 10.81 | 9.091 | 16.22 | 13.64 | tighter |  |
| material.press.circle58 | light-stripes | glass.step1e1.height.settle_ms | 66.67 | 91.67 | 100 | 137.5 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e1.luma.overshoot_pct | 8.692 | 9.254 | 13.04 | 13.88 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e1.luma.response_pct | 0 | 6.667 | 5 | 10 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e1.luma.settle_ms | 75 | 100 | 112.5 | 150 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e1.progress.damping | 0.18 | 0.21 | 0.27 | 0.315 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e1.progress.overshoot_pct | 4.509 | 8.757 | 6.763 | 13.14 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e1.progress.response_pct | 9.524 | 15.79 | 14.29 | 23.68 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e1.progress.rms | 0.04856 | 0.05478 | 0.07284 | 0.08216 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e1.progress.settle_ms | 75 | 108.3 | 112.5 | 162.5 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e1.width.damping | 0.03 | 0.04 | 0.05 | 0.06 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e1.width.peak_ms | 33.33 | 41.67 | 50 | 62.5 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e1.width.response_pct | 11.11 | 12.5 | 16.67 | 18.75 | looser |  |
| material.press.circle58 | light-stripes | glass.step1e1.width.settle_ms | 58.33 | 50 | 87.5 | 75 | tighter |  |
| material.press.circle58 | light-stripes | step1e0.delay_ms | 16.67 | 20 | 25 | 30 | looser |  |
| material.press.circle58 | light-stripes | step1e1.delay_ms | 2118 | 15 | 3177 | 22.5 | tighter |  |
| material.press.circle58 | light-stripes | step1e2.delay_ms | 2288 | 193.3 | 3432 | 290 | tighter |  |

## Re-audit fix round (P2A-4): the press take replaced

`noise.json` after `material.press.circle58` dark-stripes take 1 (press 1.225 s, outside the touch gate) was replaced by a boot-C take (press 0.985 s), recomputed for that case only by `lab.case_noise`, against `noise.json` at `644972ba7`. 12 limits moved, 4 tighter and 8 looser, none judged in 2B.1; every other entry is byte-identical. The take's release delays (`step1e1`, `step1e2` `delay_ms`, 262 and 270 ms) no longer set the floors (68 and 78 ms).

|---|---|---|---|---|---|---|---|---|
| material.press.circle58 | dark-stripes | glass.step1e0.height.response_pct | 24.24 | 27.27 | 36.36 | 40.91 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e0.luma.peak_ms | 16.67 | 25 | 25 | 37.5 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e0.width.peak_ms | 58.33 | 66.67 | 87.5 | 100 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e0.width.response_pct | 24.24 | 27.27 | 36.36 | 40.91 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e1.height.response_pct | 22.58 | 19.35 | 33.87 | 29.03 | tighter |  |
| material.press.circle58 | dark-stripes | glass.step1e1.luma.damping | 0.12 | 0.32 | 0.18 | 0.48 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e1.luma.response_pct | 5.263 | 20 | 7.895 | 30 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e1.progress.damping | 0.13 | 0.52 | 0.195 | 0.78 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e1.progress.response_pct | 6.667 | 25 | 10 | 37.5 | looser |  |
| material.press.circle58 | dark-stripes | glass.step1e2.progress.settle_ms | 50 | 41.67 | 75 | 62.5 | tighter |  |
| material.press.circle58 | dark-stripes | step1e1.delay_ms | 261.7 | 68.33 | 392.5 | 102.5 | tighter |  |
| material.press.circle58 | dark-stripes | step1e2.delay_ms | 270 | 78.33 | 405 | 117.5 | tighter |  |
