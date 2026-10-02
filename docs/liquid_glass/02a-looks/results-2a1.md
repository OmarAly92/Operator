# 2A.1 results

Date: 2026-10-02. Branch `feat/ios-liquid-glass-2a`. Simulator: iPhone 17 Pro (iOS 27), UDID 708879DD-8B2A-4547-863F-F49EE1474D8B. Run folders are under `packages/mobile/build/glass_lab/runs/`, tune folders under `packages/mobile/build/glass_lab/tune/`.

This file records two measured states of the branch:
- **First 2A.1 run** (Task 9), at `46d4a4b3e`. `e0e119526` later changed `scroll_edge_effect.dart`, but only where a `ScrollEdge.bottom` band starts; no measured scene draws a bottom edge (`material.edge.*` and `perf.edge` are top edges, and Operator's lab scenes have no `ScrollEdgeEffect`), so those runs also describe `a4a534a59`.
- **After the review fix wave**, at `6be5e3ff1`: the shader fix `7c9793f9a`, the dark clear row copy `501ff476e`, the dark Reduce Transparency saturation retune `fd525eb3b`, and the soft scroll edge pass logged in `6be5e3ff1`, which wrote nothing. Both lab apps were rebuilt at that commit (`lab.py build example`, `lab.py build operator`), and `EnhancedBackgroundContrastEnabled` read `0` after the builds and after every run.

The rim measure changed in 2A.1 (Task 1): all four sides of every pinned glass, and never looser than 2A's. Every measure below is the `static.ready` block of the run's `result.json` (2A's convention); `lab.py report` also checks `settled`, and its pass and fail counts agree with the counts here for every run. Lumas are Rec.709 (`metrics.luma`, the measure's own convention) unless a line says otherwise.

| Done item | 2A | 2A.1 first run | 2A.1 after the review fixes | Evidence (after the review fixes) |
|---|---|---|---|---|
| 3 Material scenes, strict thresholds | 0 of 20 | 9 of 20: `material.regular` 8 of 10, `.clear` 1 of 4, `.tinted` 0 of 6 | **10 of 20**: `material.regular` 8 of 10, `.clear` 2 of 4, `.tinted` 0 of 6 | runs `20261002-200447` (regular), `20261002-201611` (clear); tinted not rerun, `20261002-151504` (below); `summary-material-2a1.md` holds `material.regular` only |
| 4 Scroll edge MAD and luminance | 2 of 6 | 5 of 6 (soft light MAD 4.07) | **5 of 6**: soft light MAD 4.07 > 4.00 | run `20261002-202042` |
| 5 Reduce Transparency and Increase Contrast | 0 of 20 | 16 of 20: Reduce Transparency 7 of 10, Increase Contrast 9 of 10 | **17 of 20**: Reduce Transparency 8 of 10, Increase Contrast 9 of 10 | runs `20261002-202731` (RT), `20261002-203837` (IC) |
| 6 Operator components halve rim and luminance | 18 of 32 | 22 of 32 | **22 of 32** (10 not halved) | runs `20261002-205000` (tabbar), `20261002-205855` (button), `20261002-210140` (navbar) |
| 8 Frame cost within 20% | +2.2% at default settings | **pass**: `perf.material` 12.659 ms against the old renderer's 12.10 ms (+4.6%, budget 14.52 ms); ratio method +2.6% | not re-measured (below) | `perf-2a1.json`, `perf-2a1-rt.json` |

Items 3, 4 and 5 did not reach their targets. Item 6 was never expected to reach 32. Item 8 passed in the first run.

`material.tinted` was not rerun in the fix wave: no tinted row changed, and the shader fix cannot change its pixels, because every tinted row is at least 1 pt (3 px) thick, more than its outline band plus a pixel (at most 0.55 × 3 + 1 = 2.65 px). The same holds for every row in the table, and the runs bear it out: every Flutter frame (`ready` and `settled`) of the fix wave is byte-identical to the first run's except the ones whose rows changed (dark `material.clear`, dark Reduce Transparency). That covers `material.regular`, light `material.clear`, the three edge styles, light Reduce Transparency, Increase Contrast and the three Operator scenes. Native frames differ by at most 2 levels where they differ at all.

Item 8 was not re-measured. The fix wave added one `max()` per pixel to each glass pass and changed table values only. `perf-2a1-rt.json` was taken in dark appearance with dark Reduce Transparency saturation 0.625, now 0.25 to 0.425; saturation is a uniform, so the per-pixel work is the same.

## Run folders

| State | Command | Run folder | Report counts |
|---|---|---|---|
| first | `run material.regular --appearance both` | `20261002-145817` | pass 8, fail 2 |
| first | `run material.clear --appearance both` | `20261002-151004` | pass 1, fail 3 |
| first | `run material.tinted --appearance both` | `20261002-151504` | pass 0, fail 6 |
| first | `run material.edge --appearance both` | `20261002-152214` | pass 5, fail 1 |
| first | `run material.regular --appearance both --a11y reduce-transparency` | `20261002-152923` | pass 7, fail 3 |
| first | `run material.regular --appearance both --a11y increase-contrast` | `20261002-154112` | pass 9, fail 1 |
| first | `run tabbar.rest --app both --appearance both --flutter operator` | `20261002-155246` | pass 0, fail 8 |
| first | `run button.press --app both --appearance both --flutter operator` | `20261002-160207` | pass 0, fail 2 |
| first | `run navbar.inline --app both --appearance both --flutter operator` | `20261002-160514` | pass 0, fail 6 |
| fix 1 check | `run material.regular --appearance dark --backdrop black` | `20261002-181826` | pass 1 |
| fix 1 check | `run material.regular --appearance dark --backdrop white` | `20261002-181958` | pass 1 |
| fix 2 check | `run material.clear --appearance both` | `20261002-183050` | pass 2, fail 2 |
| after | `run material.regular --appearance both` | `20261002-200447` | pass 8, fail 2 |
| after | `run material.clear --appearance both` | `20261002-201611` | pass 2, fail 2 |
| after | `run material.edge --appearance both` | `20261002-202042` | pass 5, fail 1 |
| after | `run material.regular --appearance both --a11y reduce-transparency` | `20261002-202731` | pass 8, fail 2 |
| after | `run material.regular --appearance both --a11y increase-contrast` | `20261002-203837` | pass 9, fail 1 |
| after | `run tabbar.rest --app both --appearance both --flutter operator` | `20261002-205000` | pass 0, fail 8 |
| after | `run button.press --app both --appearance both --flutter operator` | `20261002-205855` | pass 0, fail 2 |
| after | `run navbar.inline --app both --appearance both --flutter operator` | `20261002-210140` | pass 0, fail 6 |

The Operator scenes report 0 passes because `lab.py report` judges them against the strict thresholds, not the halving rule that Done item 6 uses (below).

## What the review fix wave changed

The wave came from two read-only reviews of `a4a534a59`: a code review (one latent shader bug, B1) and a measurement audit (the numbers were right, several diagnoses were not, and two failures had cheap fixes).

1. **Thin glass (B1, `7c9793f9a`).** The geometry pass stored the signed distance divided by the lens thickness, clamped to ±1. Glass thinner than its outline band plus a pixel therefore decoded every interior pixel at `sd = −thickness`: at 0.3 px, a 0.8-covered body with the outline drawn over it. Both passes now divide by `signedDistanceReach`, the larger of the thickness and the outline band plus one pixel. `test/final_render_coverage_test.dart` renders the final pass in a test: at 0.3 px the interior reads alpha 255 and grey 128, against alpha 233 before the fix, and a pixel one pixel outside reads black outline only, against grey 49 before. No committed row was thin enough to reach the bug: runs `20261002-181826` and `-181958` (dark `black` and `white`) are byte-identical to `20261002-145817`, and so is every other unchanged case listed above.
2. **Dark clear glass (`501ff476e`).** Native `material.clear` is byte-identical in dark and light (maximum difference 0 over the whole frame on `photo` and `white`, run `20261002-151004`), but Group C had tuned the dark rows on their own, to frost 25.56 against 2.8. The plan's `copy_row` copied `light.clear.44`, `.88` and `.200` whole into the dark rows. `dark-white` now passes (MAD 7.18 → 0.60, rim 9.78 → 5.19), and `dark-photo` keeps only `light-photo`'s rim 10.92 (MAD 8.72 → 2.02, rim 16.18 → 10.92). Flutter's dark and light clear frames are now identical below the status bar. The optional narrowed tune pass was not run: in the light clear C2, C2 narrowed and C3 steps (`tune/20261001-195519`, `-203559`, `-212206`), 190 candidates scored against the same native frames never brought `photo` rim below 10.80.
3. **Dark Reduce Transparency saturation (`fd525eb3b`).** E1 had stopped at its grid floor three times (1.125, 0.875, 0.625). One pass per anchor over 0.05 to 0.45 set 0.325 at 88 pt (`tune/20261002-184346`; `stripes` MAD 4.21 → 2.07), 0.25 at 200 pt (`tune/20261002-190636`; `stripes` 7.32 → 2.48) and 0.425 at 44 pt (`tune/20261002-192818`). A first 88 pt attempt crashed in the driver and wrote nothing (`tune/20261002-183733`). In the scene run, Reduce Transparency `dark-stripes` went from MAD 4.11 to 1.56 and `dark-photo` from 2.94 to 0.99.
4. **Soft light scroll edge (no change).** One narrowed pass (`tune/20261002-195020`) kept the committed row as its best (MAD 4.07, luminance 0.00, score 1.017). Five candidates were under MAD 4, the best of them dim 0.315 at MAD 3.999 and luminance 0.11, but each scored worse on the summed objective, which is the only thing `tune --write` can write. Nothing was written.

## Item 3: Material scenes, strict thresholds (10 of 20)

Thresholds: mad 4.0, luminance 3.0, rim_rms 6.0, bbox_pt 1.0, centre_pt 1.0 (`metrics.THRESHOLDS`). A case passes only if all five pass. Failing values are bold.

### material.regular (8 of 10), run `20261002-200447`

Every value is the same as in the first run (`20261002-145817`), and Flutter's frames are byte-identical.

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

### material.clear (2 of 4), run `20261002-201611`

First run (`20261002-151004`): `dark-photo` mad 8.72 and rim 16.18, `dark-white` mad 7.18 and rim 9.78, both failing; the light cases are unchanged.

| Case | mad | luminance | rim_rms | bbox_pt | centre_pt | Result |
|---|---|---|---|---|---|---|
| dark-photo | 2.02 | 0.27 | **10.92** | 0.00 | 0.00 | FAIL (rim_rms) |
| dark-white | 0.60 | 0.22 | 5.19 | 0.00 | 0.00 | pass |
| light-photo | 2.02 | 0.27 | **10.92** | 0.00 | 0.00 | FAIL (rim_rms) |
| light-white | 0.60 | 0.22 | 5.19 | 0.00 | 0.00 | pass |

### material.tinted (0 of 6), run `20261002-151504` (not rerun)

| Case | mad | luminance | rim_rms | bbox_pt | centre_pt | Result |
|---|---|---|---|---|---|---|
| dark-black | 1.36 | 0.63 | **24.35** | 0.00 | 0.00 | FAIL (rim_rms) |
| dark-stripes | 1.82 | 0.21 | **10.04** | 1.00 | 0.50 | FAIL (rim_rms) |
| dark-white | 2.17 | 0.97 | **9.51** | 1.00 | 0.00 | FAIL (rim_rms) |
| light-black | 2.80 | 0.04 | **14.34** | 1.00 | 0.00 | FAIL (rim_rms) |
| light-stripes | 1.79 | 0.18 | **9.04** | 0.00 | 0.00 | FAIL (rim_rms) |
| light-white | 1.72 | 0.44 | **10.73** | 0.00 | 0.00 | FAIL (rim_rms) |

## Item 4: Scroll edge (5 of 6), run `20261002-202042`

MAD and luminance only. Every value is the same as in the first run (`20261002-152214`).

| Style | Case | mad | luminance | rim_rms | bbox_pt | centre_pt | Result |
|---|---|---|---|---|---|---|---|
| soft | dark-scroll | 3.95 | 0.15 | 2.29 | 0.00 | 0.00 | pass |
| soft | light-scroll | **4.07** | 0.00 | 2.92 | 0.00 | 0.00 | FAIL (mad) |
| hard | dark-scroll | 3.47 | 0.00 | 4.26 | 0.00 | 0.00 | pass |
| hard | light-scroll | 2.07 | 0.00 | 0.67 | 0.00 | 0.00 | pass |
| automatic | dark-scroll | 3.47 | 0.00 | 4.26 | 0.00 | 0.00 | pass |
| automatic | light-scroll | 2.07 | 0.00 | 0.67 | 0.00 | 0.00 | pass |

## Item 5: Reduce Transparency and Increase Contrast (17 of 20)

### Reduce Transparency (8 of 10), run `20261002-202731`

First run (`20261002-152923`): `dark-stripes` mad 4.11 (failing), `dark-photo` mad 2.94; the light cases are unchanged.

| Case | mad | luminance | rim_rms | bbox_pt | centre_pt | Result |
|---|---|---|---|---|---|---|
| dark-black-reduce-transparency | 0.29 | 0.11 | 1.06 | 0.00 | 0.00 | pass |
| dark-photo-reduce-transparency | 0.99 | 0.16 | 1.79 | 1.00 | 0.50 | pass |
| dark-stripes-reduce-transparency | 1.56 | 0.31 | 1.67 | 0.00 | 0.00 | pass |
| dark-text-reduce-transparency | 0.70 | 0.48 | 2.26 | 0.00 | 0.00 | pass |
| dark-white-reduce-transparency | 0.76 | 0.58 | 2.46 | 0.00 | 0.00 | pass |
| light-black-reduce-transparency | 0.69 | 0.62 | 2.29 | 0.00 | 0.00 | pass |
| light-photo-reduce-transparency | 0.81 | 0.06 | 3.59 | **2.00** | 1.00 | FAIL (bbox_pt) |
| light-stripes-reduce-transparency | 0.70 | 0.01 | 2.93 | 1.00 | 0.00 | pass |
| light-text-reduce-transparency | 0.57 | 0.31 | **7.90** | 0.00 | 0.00 | FAIL (rim_rms) |
| light-white-reduce-transparency | 0.22 | 0.13 | 2.89 | 0.00 | 0.00 | pass |

### Increase Contrast (9 of 10), run `20261002-203837`

Every value is the same as in the first run (`20261002-154112`).

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

## Failing cases and their causes

Cause classes: **(a)** a tunable look difference; **(b)** a model limitation that needs a shader or material change; **(c)** a lab-scene difference; **(d)** a measurement artifact; **(e)** Operator component code, outside 2A. Each entry gives the failing measure, the worst `rim_elements` side, the class and the evidence. Pixel values marked "audit" come from the 2A.1 measurement audit of the first run's frames; where those frames did not change, the fix wave's runs have the same pixels.

| Done | Case | Failing measure | Class |
|---|---|---|---|
| 3 | `material.regular` dark-text | rim_rms 10.18 | b |
| 3 | `material.regular` light-photo | bbox_pt 2.00 | d |
| 3 | `material.clear` dark-photo, light-photo | rim_rms 10.92 each | a (b possible) |
| 3 | `material.tinted`, all six | rim_rms 9.04 to 24.35 | b, with a c part in four |
| 4 | `material.edge.soft` light-scroll | mad 4.07 | a, blocked by the tuner's objective |
| 5 | Reduce Transparency light-photo, Increase Contrast light-photo | bbox_pt 2.00 each | d |
| 5 | Reduce Transparency light-text | rim_rms 7.90 | d |

Fourteen failing cases: three in class a, seven in b, four in d. The ten Operator measures of item 6 are class e.

### material.regular (Done 3)

- **dark-text** (b): rim_rms 10.18 > 6.00. Worst side `s44` right, 16.89 (`s44` left 10.90; `s88` top 5.65; `s200` left 2.41). At 44 pt native shows the backdrop text in place, nearly sharp and dimmed; Flutter's pill is uniformly blurred. Audit: a sharp-plus-blur fit gives native a sharp gain of 0.150 and a blur gain of 0.025, and Flutter 0.001 and 0.299; the interior luma standard deviation is 13.0 against 3.0; on the right-end sample row native reads glyph strokes (147, 124, 127, 149) where Flutter is flat 171. The A4 tone step's 44 pt frost grid already reached 5.725 and chose 8.5876. It needs an unblurred, dimmed backdrop term whose weight depends on size (the "44 pt sharp-detail term"), then a retune of the 44 pt rows.
- **light-photo** (d): bbox_pt 2.00 > 1.00 (centre_pt 1.00 passes). Native `[15,461,372,223]`, Flutter `[15,461,372,225]`. This is not a longer shadow tail. Run `20261002-200447`: in rows 683 to 686 pt the two frames differ by at most 2 levels per channel and 0.13 in mean luma. The box detector thresholds each 3 × 3 block's maximum channel difference from the bare frame at `> 6`. At rows 684 and 685 pt, Flutter has 19 and 10 blocks over it (maxima 7.00 and 6.67) and native none (maxima 6.00 and 6.00), so the box flips by two rows on differences nobody can see.

### material.clear (Done 3)

- **dark-photo** and **light-photo** (a, b possible): rim_rms 10.92 > 6.00 each (`rim_legacy` 10.92; elements `plain` 8.17, `dimmed` 4.47; mad 2.02 passes). Worst side `plain` top, 11.02 (`plain` bottom 10.82). Since the copy, the two cases are the same Flutter frame against the same native frame. Audit: 98% of the rms sits in a 3 pt band at the top and bottom edges, and is 1.55 without it. The sample column runs 1.3 pt inside the photo's dark square. There native's top edge is a 2 px line (255, 224) over the interior, while Flutter's light is lower and wider (235, 202, 181, 160, 144, 121). Moving the column 6 pt left gives 5.37. The 190 C-group candidates never went below 10.80 (above), so it needs edge light below the C2 grid floors (`specularWidth` 0.5, `sheenWidth` 0.75). If an exponential falloff cannot draw a 2 px line with no halo, it is a model limitation (the "clear photo edge band").

### material.tinted (Done 3)

All six fail rim_rms only. The Run button (`run`) is over threshold in every case (element rms 24.35, 10.04, 9.51, 14.34, 9.04 and 9.39 in table order). The 88 pt `block` passes on the three dark cases (1.03, 1.93, 2.58) and on `light-stripes` (2.36), and fails on `light-black` (element rms 12.35; sides top 12.41, bottom 12.37, left and right 12.32) and `light-white` (element rms 8.69; top side 11.10). `light-white`'s reported 10.73 is `rim_legacy`, the centre-column measure on the main box.

The first version of this file blamed a Run capsule offset and native's capsule edge sitting one sample higher. The audit traced the residual to two outline features Flutter cannot draw (class b):
- **The prominent Run button:** native draws a dark ring about 2 px (0.67 pt) wide just inside the button's edge, reading 0 to 1 on black and 101 on white at the right end. Flutter's capsule is not offset: in light appearance native's body reaches row 538.0 exactly like Flutter's. It has no inner ring.
- **The tinted block:** native draws a 2 px tint-coloured outline ring just outside the block (53 and 90 on black, 189 and 151 on white in the top column). Flutter's outline is drawn only outside coverage and only in black (`fragColor = vec4(0, 0, 0, outlineAlpha)`), so it is invisible on black and too faint on white (241, 228).

A smaller class c part comes from the lab scene's label and glyph. The example's Run button uses `Icons.play_arrow_rounded` at size 20, a play triangle 10.0 pt tall and 8.0 pt wide. Native's `play.fill` is 13.67 pt tall and 12.33 pt wide. The label ends at x 228.33 against native's 226.33 and sits 0.67 pt lower.

Case by case (audit, run `20261002-151504`):
- **dark-black**: rim 24.35 (`run` bottom 30.17, right 28.21, left 25.66). The bottom's 30.17 is two pixels: native reads 0 and 0 where Flutter reads 177 and 182. It is 6.52 without the ring samples and 2.51 without the ring and the one label sample.
- **dark-stripes**: rim 10.04 (`run` right 15.44). Ring at the right end: native 83 and 120, Flutter 167 and 166. Label: Flutter's "n" reads 255 against native's 167. It is 5.62 without the ring, 8.63 without the label and 1.59 without both.
- **dark-white**: rim 9.51 (`run` right 13.59). The ring reads 101 native against 174 Flutter. It is 6.06 without the ring, 6.87 without the label and 3.15 without both.
- **light-black**: rim 14.34 (`run` 14.34, `block` 12.35). Native box `[75,364,252,90]`, Flutter `[76,365,250,88]`: native's is a point larger on every side, and its block carries the tint ring just outside its edge, which Flutter's black outline cannot draw on black. The Run ring reads 90 and 52 inside the edge against Flutter's 127 and 127. The Run element is 3.21 without the ring and the label.
- **light-stripes**: rim 9.04 (`run` right 14.25). It is 7.45 without the ring, 6.34 without the label and 3.18 without both.
- **light-white**: rim 10.73 (`rim_legacy`; `run` 9.39, `block` 8.69). The Run element is 3.27 without the ring and the label. The block's outline is native's green, darker ring (189, 151) against Flutter's black outline reading 241 and 228 on white. D1 tuned only the tint, and the light block's outline and edge light were copied from regular, so a retune of the `light.tinted.88` outline is a small class a part next to the shader change.

### material.edge.soft (Done 4)

- **light-scroll** (a, blocked by the objective): mad 4.07 > 4.00 (settled too). No `rim_elements`; the edge scene pins no glass. The whole difference sits at y 40 to 160 pt; from y 160 it is 0.00. Flutter is 5.7 luma lighter at y 40 to 60 (252.8 against 247.1) and darker at y 60 to 100 (234.8 against 238.2, 223.0 against 225.4). It keeps the third text line dark and smeared where native fades it lighter (audit). Candidates that pass exist: `tune/20261002-195020` n36, dim 0.315, MAD 3.999, luminance 0.11. They lose on `tune`'s summed objective to the committed row (score 1.017 against 1.035), and `--write` can write only the best score. It needs a spec ruling on the objective (ROADMAP §6).

### Reduce Transparency and Increase Contrast (Done 5)

- **Reduce Transparency light-photo** and **Increase Contrast light-photo** (d): bbox_pt 2.00 > 1.00 each. The same detector flip as plain `light-photo`: native `[15,461,372,223]`, Flutter `[15,461,372,225]`; worst sides `s200` right 4.32 and 4.51, and rim passes (3.59, 3.40).
- **Reduce Transparency light-text** (d, small a residual): rim_rms 7.90 > 6.00. Worst side `s44` right, 14.77 (`s88` left 7.35, `s200` left 4.68). Run `20261002-202731`: the `s44` element has 288 samples. One of them, at x 276 pt on the pill's right edge, lands on a black glyph pixel, which native shows dimmed through the glass (112) and Flutter as opaque black (0). Without that sample the rim is 4.35; without the two worst, 2.84. Separately, native's left-end edge pixel is darker at every size (118, 96, 114 against 159, 156, 150, audit), a small outline difference at the curved ends.

The first version of this file listed Reduce Transparency `dark-stripes` (mad 4.11) as "Flutter's glass is more saturated". That was right, and the cause was the tuner's grid floor (fix 3 above). It now passes at 1.56.

## Corrections to the first version of this file

- Tinted `light-black`: Flutter's box is `[76,365,250,88]`, not `[76,363,250,88]`. The block's residual is native's tint-coloured outer ring, not its capsule edge sitting one sample higher.
- Tinted `dark-black`: the residual is native's 2 px dark ring inside the button edge, not a Flutter capsule ending 0.67 pt lower.
- "The light block's top edge is 12.35 (`light-black`) and 8.69 (`light-white`)": those are the `block` element rms values. The top-side values are 12.41 and 11.10.
- `light-photo` `bbox_pt` 2.00 (plain, Reduce Transparency, Increase Contrast) is a detector flip on differences of at most 2 levels, not a longer shadow tail.
- Reduce Transparency `light-text` rim 7.90 comes from one sample of 288 (4.35 without it).
- Native `material.clear` is byte-identical in dark and light. The dark clear failures came from dark rows that had drifted, not from the edge model.
- Item 6: see the next section for the measures that got worse than 2A or than the baseline.
- Two luma conventions were mixed: "85.9 against 85.2" and "175.8 against 173.0" were Rec.601 means. The `luminance` measure is Rec.709: 84.3 against 83.8 and 177.4 against 174.3 (audit). Every luma in this version is Rec.709.
- Header: the first runs were taken at `46d4a4b3e`. The file then sat at `a4a534a59`, after `e0e119526`, which changes no measured scene.
- `summary-material-2a1.md` holds `material.regular` only; it now names run `20261002-200447`.

## Operator components (Done item 6)

Runs: `tabbar.rest` `20261002-205000`, `button.press` `20261002-205855`, `navbar.inline` `20261002-210140`, all `--app both --appearance both --flutter operator`. They are compared against the project 1 baseline `docs/liquid_glass/02a-looks/operator-baseline.json` (run `20260927-035111`). The comparison is 2A's Task 12 Step 4 script, unchanged except that it imports `THRESHOLDS` from `tool/glass_lab/harness/metrics.py`. A measure passes when it is at most half its baseline or already within its threshold (rim at most 6, luminance at most 3; 2A controller ruling C5).

Every value is the same as in the first run (`20261002-155246`, `-160207`, `-160514`), and Flutter's frames are byte-identical. Four measures counted "ok" under C5 got worse than the baseline but stay within the threshold:
- `tabbar.rest` `light-white` luminance, 0.68 to 1.74;
- `button.press` `light-stripes` luminance, 0.67 to 0.86;
- `navbar.inline` `light-stripes` luminance, 2.00 to 2.41;
- `navbar.inline` `light-white` luminance, 1.29 to 1.84.

`tabbar.rest`, `button.press` and `navbar.inline` have no pinned regions, so their `rim_rms` is the same centre-column measure 2A used.

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

**22 of 32 measures halved or within threshold; 10 not.**

Against 2A's Done runs (`20260930-104535` tabbar, `-105500` button, `-105756` navbar), 2A.1 moved these:
- **Better:** five tab bar measures now pass: `dark-stripes` rim, `light-black` rim, `light-photo` rim and luminance, and `light-stripes` rim.
- **Worse, now failing:** `tabbar.rest light-stripes` luminance, 1.43 in 2A and 3.08 now.
- **Worse, still failing:**
  - `navbar.inline dark-stripes` rim is 16.70, now worse than the project 1 baseline (16.37) as well as 2A (15.48);
  - the `button.press` rims rose from 9.33 to 10.69 (`dark-stripes`) and from 7.69 to 8.54 (`light-stripes`);
  - `navbar.inline light-black` luminance went from 3.99 to 4.05 (baseline 2.16).

All ten are Operator component code (class e), which projects 3 and 4 replace; 2A.1 does not touch it. Filmstrip notes (native | flutter, `ready.png`; audit values on the same, unchanged frames):
- **tabbar.rest light-stripes** (luminance 3.08): Flutter's bar reads lighter (177.4 against 174.3). With the glyph pixels masked, the bar material differs by 2.35, inside 3. The excess comes from Operator's icon and label colours (a dark green selected tab against native's light green) and its selected pill.
- **button.press dark-stripes** (rim 10.69) and **light-stripes** (rim 8.54): Operator's glass button is shorter than native's. Detected heights are 45 against 53 pt on `dark-stripes` (`bbox_pt` 4.00) and 45 against 54 pt on `light-stripes` (`bbox_pt` 5.00). Its label is Operator's green where native's is white or black, so the centre column crosses different content.
- **navbar.inline dark-black** (rim 22.20), **dark-stripes** (16.70), **dark-white** (26.60), **light-black** (rim 57.60, luminance 4.05) and **light-stripes** (35.56): native's trailing bell-and-dots group is one capsule (`[284,62,102,44]` on `dark-black`). Flutter's is a figure-8 with a waist (`[285,57,106,54]`), with Operator's green icons. On `light-black` the trailing-group columns are 12.45 luma lighter and the rest 0.46 lighter (audit); the figure-8's extra glass accounts for it.
- **navbar.inline light-white** (rim 44.80, identical to 2A and to the baseline): the detected box is the title "Agents" (native `[173,77,56,16]`, Flutter `[173,78,48,16]`, Operator's font, 8 pt narrower). The sampled column lands on that text, not on glass.

## Frame cost (Done item 8)

Measured in the first run only. Commands: `lab.py perf --takes 3 --out build/glass_lab/perf-2a1.json` and `lab.py perf --takes 3 --scenes perf.none,perf.glass,perf.material --a11y reduce-transparency --out build/glass_lab/perf-2a1-rt.json`, both in dark appearance (the `perf` default). Raster median in milliseconds over 3 takes (about 1,070 frames each).

| Scene | `perf-2a1.json` median | p90 | cost over `perf.none` | `perf-2a1-rt.json` (Reduce Transparency) median | p90 | cost over `perf.none` |
|---|---|---|---|---|---|---|
| perf.none | 0.840 | 1.308 | 0 | 0.877 | 1.383 | 0 |
| perf.glass (old renderer settings) | 12.607 | 13.528 | 11.767 | 12.525 | 13.822 | 11.648 |
| perf.material (tuned material) | 12.659 | 13.954 | 11.819 | 12.819 | 13.676 | 11.942 |
| perf.edge (scroll edge) | 5.816 | 6.749 | 4.976 | not run | not run | not run |

- Direct: `perf.material` 12.659 ms against the old renderer's 12.10 ms (2A `flip-spike.md`) is **+4.6%**, inside the 20% budget (14.52 ms).
- Ratio method: `perf.material` ÷ `perf.glass` × 1.022 = 12.659 ÷ 12.607 × 1.022 = **1.026** (+2.6%).
- The direct figure compares sessions four days apart: `perf.none` rose from 0.577 ms (2026-09-28) to 0.840 ms, and `perf-task6.json` measured `perf.glass` at 13.252 ms (audit). On a cost-over-`perf.none` basis the tuned material is +2.6% (11.819 against 11.519 ms). The pass is robust; the exact percentage is not.
- `perf.edge` has no budget: 5.816 ms raster median, 4.976 ms over `perf.none`.
- Reduce Transparency: `perf.material` 12.819 ms against `perf.glass` 12.525 ms in the same takes, ratio 1.046 (+4.6%), and +5.9% against 12.10 ms. Also inside the budget.

## Gates

At `6be5e3ff1`:
- app: `flutter analyze` "No issues found!", `flutter test` 2,146 passed;
- package: `flutter analyze` clean, `flutter test` 67 passed (64 at `a4a534a59`, plus the three final-render coverage tests);
- example: `flutter analyze` clean, `flutter test` 8 passed;
- harness: `python3 -m unittest discover tool/glass_lab/harness/tests`, 104 tests OK.
