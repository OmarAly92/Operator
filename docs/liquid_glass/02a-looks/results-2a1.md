# 2A.1 results

Date: 2026-10-02. Branch `feat/ios-liquid-glass-2a` at `46d4a4b3e`. Simulator: iPhone 17 Pro (iOS 27), UDID 708879DD-8B2A-4547-863F-F49EE1474D8B. Both lab apps were rebuilt at that commit (`lab.py build example`, `lab.py build operator`, exit 0) and `EnhancedBackgroundContrastEnabled` read `0` after the build and after each accessibility run.

The rim measure changed in 2A.1 (Task 1): all four sides of every pinned glass, and never looser than 2A's. 2A's numbers are re-analysed with it where a comparison is quoted. Every measure below is the `static.ready` block of the run's `result.json` (2A's convention); `lab.py report` also checks `settled`, and its pass and fail counts agree with the counts here for every run.

| Done item | 2A | Prototype (no campaign) | 2A.1 | Evidence |
|---|---|---|---|---|
| 3 Material scenes, strict thresholds | 0 of 20 | 5 of 20 | **9 of 20**: `material.regular` 8 of 10, `material.clear` 1 of 4, `material.tinted` 0 of 6 | runs `20261002-145817` (regular), `20261002-151004` (clear), `20261002-151504` (tinted); `summary-material-2a1.md` |
| 4 Scroll edge MAD and luminance | 2 of 6 | 5 of 6 (soft light MAD 4.12) | **5 of 6**: soft light MAD 4.07 > 4.00 | run `20261002-152214` |
| 5 Reduce Transparency and Increase Contrast | 0 of 20 | not measured | **16 of 20**: Reduce Transparency 7 of 10, Increase Contrast 9 of 10 | runs `20261002-152923` (RT), `20261002-154112` (IC) |
| 6 Operator components halve rim and luminance | 18 of 32 | 20 of 32 | **22 of 32** (10 not halved) | runs `20261002-155246` (tabbar), `20261002-160207` (button), `20261002-160514` (navbar) |
| 8 Frame cost within 20% | +2.2% at default settings | +7.8% with the tuned material (13.04 ms) | **pass**: `perf.material` 12.659 ms against the old renderer's 12.10 ms (+4.6%, budget 14.52 ms); ratio method +2.6% | `perf-2a1.json`, `perf-2a1-rt.json` |

Items 3, 4 and 5 did not reach their targets. Item 6 was never expected to reach 32. Item 8 passes.

Run folders (all under `packages/mobile/build/glass_lab/runs/`):

| Step | Command | Run folder | Report counts |
|---|---|---|---|
| 2 | `run material.regular --appearance both` | `20261002-145817` | pass 8, fail 2 |
| 2 | `run material.clear --appearance both` | `20261002-151004` | pass 1, fail 3 |
| 2 | `run material.tinted --appearance both` | `20261002-151504` | pass 0, fail 6 |
| 2 | `run material.edge --appearance both` (`.soft`, `.hard`, `.automatic`) | `20261002-152214` | pass 5, fail 1 |
| 3 | `run material.regular --appearance both --a11y reduce-transparency` | `20261002-152923` | pass 7, fail 3 |
| 3 | `run material.regular --appearance both --a11y increase-contrast` | `20261002-154112` | pass 9, fail 1 |
| 4 | `run tabbar.rest --app both --appearance both --flutter operator` | `20261002-155246` | pass 0, fail 8 |
| 4 | `run button.press --app both --appearance both --flutter operator` | `20261002-160207` | pass 0, fail 2 |
| 4 | `run navbar.inline --app both --appearance both --flutter operator` | `20261002-160514` | pass 0, fail 6 |

The Operator scenes report 0 passes because `lab.py report` judges them against the strict thresholds, not the halving rule that Done item 6 uses (below).

## What the campaign expected, and what the fresh runs show

| Expected residual (tuning log) | Fresh run |
|---|---|
| Dark 88 pt photo MAD about 4.3 | Reproduced inside the 88 pt pinned region: MAD 4.33 over the `s88` rect padded 12 pt (`dark-photo`, run `20261002-145817`), with `s88` rim top 7.20. The Done measure is the whole-scene MAD, 1.80, which passes, and `dark-photo` passes all five measures. |
| Dark 44 pt curved-end rim on text and photo | Confirmed. `dark-text`: `s44` right 16.89, `s44` rim_rms 10.18 > 6.00, the only reason that case fails. `dark-photo`: `s44` left 9.85, `s44` rim_rms 5.05, which passes. |
| Clear glass: dark rim, dark photo MAD, light photo rim | Confirmed, and wider than expected: `dark-photo` MAD 8.72 and rim 16.18, `dark-white` MAD 7.18 and rim 9.78 (a new MAD miss), `light-photo` rim 10.92. Only `light-white` passes. |
| Tinted: the Run button's rim and the light block's edge rim | Confirmed. The Run button's rim is 9.04 to 24.35 on all six cases; the light block's top edge is 12.35 (`light-black`) and 8.69 (`light-white`). Tinted MAD, luminance and box pass everywhere (MAD 1.36 to 2.80), so the glyph-dominated MAD residual is not over threshold in this scene. |
| Dark Reduce Transparency stripes MAD, worse at 200 pt | Confirmed: whole-scene MAD 4.11 > 4.00; over the `s200` rect padded 60 pt it is 5.08, against 2.24 at 88 pt and 0.96 at 44 pt. |
| Soft light scroll edge MAD 4.07 | Confirmed to the digit: 4.07 > 4.00 (run `20261002-152214`). |

New in the fresh runs, not on the campaign's list: `light-photo` fails `bbox_pt` 2.00 in plain, Reduce Transparency and Increase Contrast; Reduce Transparency `light-text` fails rim 7.90 (`s44` right 14.77); `material.clear` `dark-white` fails MAD.

## Item 3: Material scenes, strict thresholds (9 of 20)

Thresholds: mad 4.0, luminance 3.0, rim_rms 6.0, bbox_pt 1.0, centre_pt 1.0 (`metrics.THRESHOLDS`). A case passes only if all five pass. Failing values are bold.

### material.regular (8 of 10), run `20261002-145817`

| Case | mad | luminance | rim_rms | bbox_pt | centre_pt | Result |
|---|---|---|---|---|---|---|
| dark-black | 0.39 | 0.09 | 1.72 | 0.00 | 0.00 | pass |
| dark-photo | 1.80 | 0.48 | 5.05 | 1.00 | 0.50 | pass |
| dark-stripes | 2.30 | 0.02 | 3.31 | 0.00 | 0.00 | pass |
| dark-text | 1.02 | 0.12 | **10.18** | 0.00 | 0.00 | FAIL (rim_rms) |
| dark-white | 0.82 | 0.06 | 2.75 | 0.00 | 0.00 | pass |
| light-black | 0.69 | 0.42 | 1.95 | 0.00 | 0.00 | pass |
| light-photo | 1.57 | 0.34 | 3.74 | **2.00** | 1.00 | FAIL (bbox_pt) |
| light-stripes | 1.44 | 0.08 | 3.36 | 1.00 | 0.00 | pass |
| light-text | 1.47 | 0.57 | 5.18 | 0.00 | 0.00 | pass |
| light-white | 0.55 | 0.30 | 3.44 | 0.00 | 0.00 | pass |

### material.clear (1 of 4), run `20261002-151004`

| Case | mad | luminance | rim_rms | bbox_pt | centre_pt | Result |
|---|---|---|---|---|---|---|
| dark-photo | **8.72** | 0.03 | **16.18** | 0.00 | 0.00 | FAIL (mad, rim_rms) |
| dark-white | **7.18** | 1.46 | **9.78** | 0.00 | 0.00 | FAIL (mad, rim_rms) |
| light-photo | 2.02 | 0.27 | **10.92** | 0.00 | 0.00 | FAIL (rim_rms) |
| light-white | 0.60 | 0.22 | 5.19 | 0.00 | 0.00 | pass |

### material.tinted (0 of 6), run `20261002-151504`

| Case | mad | luminance | rim_rms | bbox_pt | centre_pt | Result |
|---|---|---|---|---|---|---|
| dark-black | 1.36 | 0.63 | **24.35** | 0.00 | 0.00 | FAIL (rim_rms) |
| dark-stripes | 1.82 | 0.21 | **10.04** | 1.00 | 0.50 | FAIL (rim_rms) |
| dark-white | 2.17 | 0.97 | **9.51** | 1.00 | 0.00 | FAIL (rim_rms) |
| light-black | 2.80 | 0.04 | **14.34** | 1.00 | 0.00 | FAIL (rim_rms) |
| light-stripes | 1.79 | 0.18 | **9.04** | 0.00 | 0.00 | FAIL (rim_rms) |
| light-white | 1.72 | 0.44 | **10.73** | 0.00 | 0.00 | FAIL (rim_rms) |

## Item 4: Scroll edge (5 of 6), run `20261002-152214`

MAD and luminance only.

`material.edge.soft`:

| Case | mad | luminance | rim_rms | bbox_pt | centre_pt | Result |
|---|---|---|---|---|---|---|
| dark-scroll | 3.95 | 0.15 | 2.29 | 0.00 | 0.00 | pass |
| light-scroll | **4.07** | 0.00 | 2.92 | 0.00 | 0.00 | FAIL (mad) |

`material.edge.hard`:

| Case | mad | luminance | rim_rms | bbox_pt | centre_pt | Result |
|---|---|---|---|---|---|---|
| dark-scroll | 3.47 | 0.00 | 4.26 | 0.00 | 0.00 | pass |
| light-scroll | 2.07 | 0.00 | 0.67 | 0.00 | 0.00 | pass |

`material.edge.automatic`:

| Case | mad | luminance | rim_rms | bbox_pt | centre_pt | Result |
|---|---|---|---|---|---|---|
| dark-scroll | 3.47 | 0.00 | 4.26 | 0.00 | 0.00 | pass |
| light-scroll | 2.07 | 0.00 | 0.67 | 0.00 | 0.00 | pass |

## Item 5: Reduce Transparency and Increase Contrast (16 of 20)

### Reduce Transparency (7 of 10), run `20261002-152923`

| Case | mad | luminance | rim_rms | bbox_pt | centre_pt | Result |
|---|---|---|---|---|---|---|
| dark-black-reduce-transparency | 0.29 | 0.11 | 1.05 | 0.00 | 0.00 | pass |
| dark-photo-reduce-transparency | 2.94 | 0.14 | 1.79 | 1.00 | 0.50 | pass |
| dark-stripes-reduce-transparency | **4.11** | 0.58 | 2.17 | 0.00 | 0.00 | FAIL (mad) |
| dark-text-reduce-transparency | 0.70 | 0.48 | 2.26 | 0.00 | 0.00 | pass |
| dark-white-reduce-transparency | 0.76 | 0.58 | 2.46 | 0.00 | 0.00 | pass |
| light-black-reduce-transparency | 0.69 | 0.62 | 2.29 | 0.00 | 0.00 | pass |
| light-photo-reduce-transparency | 0.81 | 0.06 | 3.59 | **2.00** | 1.00 | FAIL (bbox_pt) |
| light-stripes-reduce-transparency | 0.70 | 0.01 | 2.93 | 1.00 | 0.00 | pass |
| light-text-reduce-transparency | 0.57 | 0.31 | **7.90** | 0.00 | 0.00 | FAIL (rim_rms) |
| light-white-reduce-transparency | 0.22 | 0.13 | 2.89 | 0.00 | 0.00 | pass |

### Increase Contrast (9 of 10), run `20261002-154112`

| Case | mad | luminance | rim_rms | bbox_pt | centre_pt | Result |
|---|---|---|---|---|---|---|
| dark-black-increase-contrast | 0.34 | 0.16 | 1.40 | 0.00 | 0.00 | pass |
| dark-photo-increase-contrast | 1.90 | 0.07 | 3.33 | 1.00 | 0.50 | pass |
| dark-stripes-increase-contrast | 2.51 | 0.33 | 3.23 | 0.00 | 0.00 | pass |
| dark-text-increase-contrast | 1.23 | 0.39 | 4.76 | 0.00 | 0.00 | pass |
| dark-white-increase-contrast | 1.07 | 0.34 | 4.64 | 0.00 | 0.00 | pass |
| light-black-increase-contrast | 0.96 | 0.41 | 2.01 | 0.00 | 0.00 | pass |
| light-photo-increase-contrast | 1.63 | 0.37 | 3.40 | **2.00** | 1.00 | FAIL (bbox_pt) |
| light-stripes-increase-contrast | 1.74 | 0.29 | 3.12 | 1.00 | 0.00 | pass |
| light-text-increase-contrast | 1.03 | 0.16 | 4.83 | 0.00 | 0.00 | pass |
| light-white-increase-contrast | 0.57 | 0.20 | 3.65 | 0.00 | 0.00 | pass |

## Failing cases

Each entry gives the scene, case, failing measure with value and threshold, the worst `rim_elements` side (element and side, with the side's rms), and one sentence from the `native | flutter` filmstrip (`ready.png`). Direction claims carry a pixel number from the same `ready.png`.

### material.regular (Done 3)

- **dark-text**: rim_rms 10.18 > 6.00 (settled too). Worst side `s44` right, 16.89 (`s44` rms 10.18; `s88` top 5.65; `s200` left 2.41). Native shows the backdrop text through the 44 pt pill (interior luma standard deviation 15.6) and Flutter's pill is blurred flat (2.0), so at the right-end sample native reads 124 where Flutter reads 171.
- **light-photo**: bbox_pt 2.00 > 1.00 (centre_pt 1.00 passes; settled bbox_pt 2.00 too). Worst side `s200` right, 4.93 (rim passes at 3.74). Flutter's detected box is 2 pt taller at the bottom (native `[15,461,372,223]`, Flutter `[15,461,372,225]`), a longer shadow tail, while the fill luma matches (153.3 native, 153.6 Flutter).

### material.clear (Done 3)

- **dark-photo**: mad 8.72 > 4.00 and rim_rms 16.18 > 6.00 (`rim_legacy` 16.18; elements `plain` 15.25, `dimmed` 10.54). Worst side `plain` top, 20.10 (`dimmed` top 14.88). Flutter's clear glass blurs what native shows crisp: inside the top pill the luma gradient is 0.27 against native's 0.71 and the luma standard deviation 9.5 against 26.2, and at the top-rim peak sample native reads 224 against Flutter's 166.
- **dark-white**: mad 7.18 > 4.00 and rim_rms 9.78 > 6.00 (`dimmed` element 9.78, `plain` 9.35, `rim_legacy` 5.93). Worst side `plain` left, 13.21 (`dimmed` right 12.66). On white, native's clear pill is a flat grey (luma 190 at the centre, 14 pt in from the left edge and 14 pt in from the top), while Flutter's fill is a dark vignette: 172 at the centre (18 darker) and 198 at the left edge (8 lighter).
- **light-photo**: rim_rms 10.92 > 6.00 (`rim_legacy` 10.92; elements `plain` 8.17, `dimmed` 4.47; mad 2.02 passes). Worst side `plain` top, 11.02 (`dimmed` top 5.47). The top rim of Flutter's pill is brighter than native's at the peak sample (native 103, Flutter 160), and Flutter's refraction softens the small blue and pink ovals a little (gradient 0.61 against 0.71).

### material.tinted (Done 3)

All six fail rim_rms only. The Run button (`run`) is over threshold on every case (element rms 24.35, 10.04, 9.51, 14.34, 9.04 and 9.39 in table order); the 88 pt `block` passes on the three dark cases (1.03, 1.93, 2.58) and on `light-stripes` (2.36) and fails on `light-black` (12.35) and `light-white` (8.69). `light-white`'s reported 10.73 is `rim_legacy`, the centre-column measure on the main box, not an element. The Run label and play glyph are Flutter's own text, not glass. Measured on `dark-black`: Flutter's Run capsule ends 0.67 pt lower (last lit row 537.67 against native's 537.00) and its white label spans x 179.0 to 228.0 against native's 176.7 to 226.0, about 2 pt further right.

- **dark-black**: rim_rms 24.35 > 6.00. Worst side `run` bottom, 30.17 (`block` top 1.54). At the bottom-edge sample native is black (0) and Flutter still reads 182, because Flutter's Run capsule ends 0.67 pt lower.
- **dark-stripes**: rim_rms 10.04 > 6.00. Worst side `run` right, 15.44 (`block` left 2.42). The row crosses Flutter's "Run" label, which sits about 2 pt further right than native's, so at the first right-edge sample Flutter reads 255 (white glyph) where native reads 167.
- **dark-white**: rim_rms 9.51 > 6.00. Worst side `run` right, 13.59 (`block` left 2.62). Same offset label: Flutter reads 255 where native reads 171 at the first right-edge sample.
- **light-black**: rim_rms 14.34 > 6.00. Worst side `run` right, 18.54 (`run` rms 14.34); the block also misses at `block` top 12.41 (native 90 against Flutter 0 at the top-edge sample, native's capsule edge sitting one sample higher, `native_box [75,364,252,90]` against Flutter `[76,363,250,88]`). Run: Flutter 255 against native 125 at the first right-edge sample.
- **light-stripes**: rim_rms 9.04 > 6.00. Worst side `run` right, 14.25 (`block` top 3.07). Flutter's label glyph again reaches 255 where native reads 145.
- **light-white**: rim_rms 10.73 > 6.00 (this is `rim_legacy`; elements `run` 9.39 and `block` 8.69 also exceed 6.00). Worst side `run` right, 12.60; the block misses at `block` top 11.10 (native 151, Flutter 228 at the top-edge sample, Flutter's glint one sample off native's). Run: Flutter 255 against native 157.

### material.edge.soft (Done 4)

- **light-scroll**: mad 4.07 > 4.00 (settled too). No `rim_elements` (the edge scene pins no glass). The difference is confined to the fade band: mean absolute difference per 20 pt band is 5.70 at y 40 to 60, 10.49 at y 60 to 80, 11.41 at y 80 to 100, 7.32 at y 100 to 120, 6.75 at y 120 to 140 and 0.00 from y 160, with Flutter 5.7 luma lighter at y 40 to 60 (252.8 against 247.1) and 3.4 and 2.4 darker at y 60 to 80 and 80 to 100 (234.8 against 238.2, 223.0 against 225.4), so native's text fades out earlier and more smoothly than ours.

### Reduce Transparency (Done 5)

- **dark-stripes**: mad 4.11 > 4.00 (settled too). Worst side `s44` right, 2.80 (rim passes at 2.17). Flutter's glass is more saturated than native's over the stripes (mean channel spread 105.0 against 96.8 across the scene region) at an almost equal luma (85.9 against 85.2), and over the 200 pt glass the MAD rises to 5.08.
- **light-photo**: bbox_pt 2.00 > 1.00. Worst side `s200` right, 4.32. The same box as plain light-photo: Flutter's box is 2 pt taller at the bottom (`[15,461,372,225]` against native `[15,461,372,223]`).
- **light-text**: rim_rms 7.90 > 6.00. Worst side `s44` right, 14.77 (`s88` left 7.35, `s200` left 4.68). At the 44 pt pill's right-end sample native reads 112 (dimmed glyph through the glass) where Flutter reads 0 (opaque black glyph pixel); the scene luma matches (241.6 native, 241.3 Flutter).

### Increase Contrast (Done 5)

- **light-photo**: bbox_pt 2.00 > 1.00. Worst side `s200` right, 4.51. The same 2 pt taller Flutter box as plain and Reduce Transparency `light-photo` (`[15,461,372,225]` against `[15,461,372,223]`); every other measure passes (rim 3.40, mad 1.63).

## Operator components (Done item 6)

Runs: `tabbar.rest` `20261002-155246`, `button.press` `20261002-160207`, `navbar.inline` `20261002-160514`, all `--app both --appearance both --flutter operator`, against the project 1 baseline `docs/liquid_glass/02a-looks/operator-baseline.json` (run `20260927-035111`). The comparison is 2A's Task 12 Step 4 script unchanged except that it imports `THRESHOLDS` from `tool/glass_lab/harness/metrics.py` instead of hardcoding the limits. A measure passes when it is at most half its baseline or already within its threshold (rim at most 6, luminance at most 3; 2A controller ruling C5). `tabbar.rest`, `button.press` and `navbar.inline` have no pinned regions, so their `rim_rms` is the same centre-column measure 2A used and the comparison stays like for like.

| Case | Measure | Baseline | Now | Verdict |
|---|---|---|---|---|
| tabbar.rest dark-black | rim_rms | 25.57 | 1.52 | ok |
| tabbar.rest dark-black | luminance | 13.59 | 5.95 | ok |
| tabbar.rest dark-photo | rim_rms | 19.43 | 3.05 | ok |
| tabbar.rest dark-photo | luminance | 9.13 | 3.47 | ok |
| tabbar.rest dark-stripes | rim_rms | 9.54 | 5.82 | ok |
| tabbar.rest dark-stripes | luminance | 7.05 | 1.03 | ok |
| tabbar.rest dark-white | rim_rms | 44.09 | 12.47 | ok |
| tabbar.rest dark-white | luminance | 40.67 | 6.28 | ok |
| tabbar.rest light-black | rim_rms | 22.69 | 1.80 | ok |
| tabbar.rest light-black | luminance | 13.93 | 4.37 | ok |
| tabbar.rest light-photo | rim_rms | 12.49 | 2.25 | ok |
| tabbar.rest light-photo | luminance | 3.88 | 2.83 | ok |
| tabbar.rest light-stripes | rim_rms | 9.74 | 2.52 | ok |
| tabbar.rest light-stripes | luminance | 5.16 | 3.08 | NOT HALVED |
| tabbar.rest light-white | rim_rms | 5.22 | 2.89 | ok |
| tabbar.rest light-white | luminance | 0.68 | 1.74 | ok |
| button.press dark-stripes | rim_rms | 13.37 | 10.69 | NOT HALVED |
| button.press dark-stripes | luminance | 2.95 | 0.02 | ok |
| button.press light-stripes | rim_rms | 13.47 | 8.54 | NOT HALVED |
| button.press light-stripes | luminance | 0.67 | 0.86 | ok |
| navbar.inline dark-black | rim_rms | 27.50 | 22.20 | NOT HALVED |
| navbar.inline dark-black | luminance | 6.71 | 0.09 | ok |
| navbar.inline dark-stripes | rim_rms | 16.37 | 16.70 | NOT HALVED |
| navbar.inline dark-stripes | luminance | 3.79 | 0.69 | ok |
| navbar.inline dark-white | rim_rms | 41.15 | 26.60 | NOT HALVED |
| navbar.inline dark-white | luminance | 7.38 | 2.52 | ok |
| navbar.inline light-black | rim_rms | 96.06 | 57.60 | NOT HALVED |
| navbar.inline light-black | luminance | 2.16 | 4.05 | NOT HALVED |
| navbar.inline light-stripes | rim_rms | 58.81 | 35.56 | NOT HALVED |
| navbar.inline light-stripes | luminance | 2.00 | 2.41 | ok |
| navbar.inline light-white | rim_rms | 44.80 | 44.80 | NOT HALVED |
| navbar.inline light-white | luminance | 1.29 | 1.84 | ok |

**22 of 32 measures halved or within threshold; 10 not.** The tab bar now passes 15 of its 16 measures (every rim; luminance only `light-stripes` 3.08, which is 0.08 over 3.00 and above half of its 5.16 baseline); `button.press` keeps both rims (10.69 and 8.54, against baselines 13.37 and 13.47); `navbar.inline` keeps all six rims and `light-black` luminance (4.05).

Against 2A's 14 measures not halved (runs `20260930-104535`, `105500`, `105756`), five tab bar measures now pass (`dark-stripes` rim, `light-black` rim, `light-photo` rim and luminance, `light-stripes` rim) and one regressed: `tabbar.rest light-stripes` luminance, 1.43 in 2A and 3.08 now (0.08 over 3.00). The button and navbar measures that missed in 2A still miss.

Filmstrip notes for the 10 measures that did not halve (native | flutter, `ready.png`):

- **tabbar.rest light-stripes** (luminance 3.08): Flutter's bar reads 2.8 luma lighter (175.8 against 173.0) and less saturated (channel spread 133.4 against 138.5), the selected pill's pink glow being weaker.
- **button.press dark-stripes** (rim 10.69) and **light-stripes** (rim 8.54): Flutter's "Glass button" label is Operator's green where native's is white, the glass button is 4 pt shorter (`bbox_pt` 4.00) and the prominent button sits 4 pt lower, so the centre column crosses different content.
- **navbar.inline dark-black** (rim 22.20): native's trailing group is two separate circles; Flutter's fuses into one peanut shape (`bbox_pt` 5.00, `centre_pt` 3.00), and the sample column falls on the waist.
- **navbar.inline dark-stripes** (rim 16.70), **dark-white** (rim 26.60), **light-black** (rim 57.60 and luminance 4.05), **light-stripes** (rim 35.56): the same fused trailing group, with Flutter's bell and dots in Operator's green where native's are white or black; on `light-black` the scene is 4.0 luma lighter in Flutter (30.5 against 26.5).
- **navbar.inline light-white** (rim 44.80): identical to 2A's 44.80 and to the project 1 baseline value; the trailing group is fused in Flutter (`bbox_pt` 8.00, `centre_pt` 4.00) with green glyphs against black, and the measured column lands on that shape difference, not on glass material.

All ten are Operator component code, which project 3 replaces; 2A.1 does not touch it.

## Frame cost (Done item 8)

Commands: `lab.py perf --takes 3 --out build/glass_lab/perf-2a1.json` and `lab.py perf --takes 3 --scenes perf.none,perf.glass,perf.material --a11y reduce-transparency --out build/glass_lab/perf-2a1-rt.json`. Raster median in milliseconds over 3 takes (about 1,070 frames each).

| Scene | `perf-2a1.json` median | p90 | cost over `perf.none` | `perf-2a1-rt.json` (Reduce Transparency) median | p90 | cost over `perf.none` |
|---|---|---|---|---|---|---|
| perf.none | 0.840 | 1.308 | 0 | 0.877 | 1.383 | 0 |
| perf.glass (old renderer settings) | 12.607 | 13.528 | 11.767 | 12.525 | 13.822 | 11.648 |
| perf.material (tuned material) | 12.659 | 13.954 | 11.819 | 12.819 | 13.676 | 11.942 |
| perf.edge (scroll edge) | 5.816 | 6.749 | 4.976 | not run | not run | not run |

- Direct: `perf.material` 12.659 ms against the old renderer's 12.10 ms (2A `flip-spike.md`) is **+4.6%**, inside the 20% budget (14.52 ms). The prototype measured 13.04 ms (+7.8%).
- Ratio method: `perf.material` ÷ `perf.glass` × 1.022 = 12.659 ÷ 12.607 × 1.022 = **1.026** (+2.6%). The tuned material costs 0.052 ms more than default settings in the same takes.
- `perf.glass` here is 12.607 ms against 2A's 12.36 ms for the new renderer at the same settings, and Task 6's `perf-task6.json` read 13.252 ms for it, about 0.6 ms above the prototype on this machine. Machine drift between sessions is of that order, which is why the ratio is reported beside the direct figure.
- `perf.edge` has no budget. Its raster median is 5.816 ms (4.976 ms over `perf.none`); Task 6's `perf-task6.json` read 5.786 ms.
- Reduce Transparency: `perf.material` 12.819 ms against `perf.glass` 12.525 ms in the same takes, ratio 12.819 ÷ 12.525 × 1.022 = 1.046 (+4.6%), and +5.9% against 12.10 ms. Also inside the budget.

## Gates

None of Task 9's work touches code, so the gates were not re-run; the counts at the end of Task 8 stand (harness 104 tests, package 63, example 8, app 2,146).
