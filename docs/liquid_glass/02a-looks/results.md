# 2A results

Date: 2026-09-30. Branch `feat/ios-liquid-glass-2a` at `567d0e7ac`. Simulator: iPhone 17 Pro (iOS 27), UDID 708879DD-8B2A-4547-863F-F49EE1474D8B. The material and accessibility runs below (`20260930-082046`, `094506`, `095626`) were built and run at `7fef0baae`, the commit immediately before the lab appearance fix; the Operator component runs (`104535`/`105500`/`105756`) were rebuilt afterward at `567d0e7ac`.

Lab appearance defect (Task 12 rerun): `GlassLabScreen` picked its `DarkSkin`/`LightSkin` from platform brightness but never provided a matching `GlassTheme`, so the package's glass kept reading the app-root `GlassTheme` (light, from `SkinCubit`'s default) regardless of which appearance the lab was running — dark lab runs measured the wrong, light material rows. Fixed in `567d0e7ac` (`fix(mobile): Operator's glass lab gives the glass the lab's appearance`), which wraps the lab scene in its own `GlassTheme` matching the lab's chosen skin. The Operator component runs below supersede the earlier runs `20260930-100915`, `20260930-101816`, `20260930-102112`, which were taken before this fix and measured the light material in dark mode.

| Done item | Result | Evidence |
|---|---|---|
| 1 Package: rename, plugin live toggles, gates, no old imports | pass | Task 8 `lab.py a11y`: all 3 modes (reduce-transparency, increase-contrast, reduce-motion) live, no cross-talk; gates green: harness 80 tests OK, package 47 tests, example 6 tests, app 2,146 tests, `flutter analyze` "No issues found!" in app/package/example; `grep -rn liquid_glass_renderer` in `packages/mobile` (excluding build/.dart_tool) matches only `pubspec.yaml`'s fork-attribution description line, no code imports |
| 2 Example app | pass | run `20260930-082046` builds and runs every scene registered in the manifest; `example/test/lab_test.dart`'s "every manifest scene renders its scene or the missing placeholder" covers the one missing scene (`material.content`); README still pending, due Task 13 |
| 3 Material scenes, strict thresholds | 0 of 20 cases pass | `summary-material.md`, run `20260930-082046` |
| 4 Scroll edge MAD and luminance | 2 of 6 cases pass | run `20260930-082046` (edge scenes) |
| 5 Reduce Transparency and Increase Contrast | 0 of 20 cases pass | runs `20260930-094506` (RT), `20260930-095626` (IC) |
| 6 Operator components halve rim and luminance | 18 of 32 measures halved | comparison table below, runs `20260930-104535`/`20260930-105500`/`20260930-105756` (after the lab appearance fix; supersedes `20260930-100915`/`20260930-101816`/`20260930-102112`) |
| 7 Flip spike | no flip; nothing to build | native small and large glass does not flip between light/dark content in either appearance, at 44 pt or 200 pt (flip-spike.md); the package already draws only the same-appearance material, so B8 needs no 2A implementation |
| 8 Frame cost within 20% | pass — new 12.36 ms vs old 12.10 ms (+2.2%) | flip-spike.md, `perf.glass` raster mean, well inside the 20% budget |
| 9 Documents | done in Task 13 | — |

## Step 1: Rebuild

`lab.py build example` and `lab.py build operator` both completed with exit code 0, targeting UDID 708879DD-8B2A-4547-863F-F49EE1474D8B.

## Step 2/3: Material scenes and accessibility — Done items 3 and 5

Run: `lab.py run material --appearance both` → run folder `20260930-082046`.
Report: `packages/mobile/build/glass_lab/runs/20260930-082046/report.html`. Overall counts across every scene in the manifest: `{"pass": 2, "fail": 44, "missing": 2}` (most of those 44 are motion scenes, out of scope for items 3–4 per the brief).

Restricted to the Done-item-3 cases (`material.regular` on 5 backdrops, `material.clear` on photo/white, `material.tinted` on stripes/white/black, both appearances): **0 of 20 pass.**

Restricted to Done-item-4 cases (`material.edge.soft/.hard/.automatic` on `scroll`, both appearances, MAD and luminance only): **2 of 6 pass** (`edge.hard` and `edge.automatic`, light appearance only).

Accessibility (Done item 5), `material.regular` on 5 backdrops, both appearances:
- Reduce Transparency: `lab.py run material.regular --appearance both --a11y reduce-transparency` → run `20260930-094506`. Report: `{"pass": 0, "fail": 10}`.
- Increase Contrast: `lab.py run material.regular --appearance both --a11y increase-contrast` → run `20260930-095626`. Report: `{"pass": 0, "fail": 10}`.
- After each run, `xcrun simctl spawn booted defaults read com.apple.Accessibility EnhancedBackgroundContrastEnabled` printed `0`.

**0 of 20 accessibility cases pass.**

## Failing cases

Every measure below is read from `result.json`'s `static.ready` block in the cited run folder. "Filmstrip" observations are from the `ready.png` screenshots (native vs flutter) unless noted.

### material.regular (Done item 3) — 10 of 10 fail

- **dark-black**: rim_rms 8.26 > 6.00 (mad/luminance/bbox/centre all pass, bbox exactly 0). Known residual: Flutter draws a crisp bright rim where native shows a soft diagonal highlight.
- **light-black**: rim_rms 17.70 > 6.00, same cause, worse in light appearance.
- **dark-photo, dark-stripes, dark-text, dark-white, light-photo, light-stripes, light-text, light-white**: all fail bbox_pt (7.00–12.00 pt, threshold 1.00) and centre_pt (5.00–6.00 pt, threshold 1.00). The glass itself is placed identically in both apps: `material.regular` has no `track`, so `analyze.region_for` pads the union of detected boxes by 12 pt, and `static_compare`'s box detector (`|frame − bare| > 6`) only finds one component in that region — the 200 pt glass. On **black**, where there is no shadow to catch, `native_box`/`flutter_box` are pixel-identical (`[21,465,360,200]`) and bbox/centre are exactly 0. On every other backdrop the measured box is native's *shadow extent*, not a placement difference: on dark-white/dark-text native reads `[3,455,396,236]` against Flutter's `[9,455,384,224]` (the same pair reappears identically in the RT and IC a11y runs, since those rows copy the same shadow parameters). Sampling the pixels directly below the glass on `dark-white` (native vs its own bare backdrop, in luma): native's darkening tapers from about −6 to 0 over roughly 19 pt; Flutter's shadow, copying the same parameters, tapers from about −5 to 0 within about 1 pt — native's shadow is a long, soft halo, Flutter's is tight and short. That is a real shadow-extent residual for 2B/tuning, not a placement error and not backdrop-detection noise. (On `light-photo` specifically, native is not simply "wider": native's box `[15,461,372,223]` is 4 pt taller but 2 pt narrower than Flutter's `[14,458,374,219]`.) Task 11 saw bbox 1.0/centre 0.0 on this same element because its A4 pinned region scored the smaller 88 pt block (`s88`); this run's A7 pinned region (`s200`, padded by 12) clips both shadow halos and could not see this residual during tuning.
  - **dark-text, dark-white, light-photo, light-stripes, light-text**: additionally fail rim_rms (6.63–15.63) or mad/luminance (light-photo: mad 11.17, luminance 9.54; light-text: mad 4.69, luminance 3.73; light-stripes: mad 4.98). `photo` and `text` were never included in the Group A/B tuning backdrops (`stripes,white,black` only, per `tuning-log.md`), so these residuals were never seen or fixed during tuning — light-photo in particular is a genuinely untested combination, not a known residual.

### material.clear (Done item 3) — 4 of 4 fail

- **dark-photo**: mad 9.91 > 4.00, rim_rms 22.31 > 6.00, bbox_pt 9.00, centre_pt 4.50. Matches the known residual: dark clear MAD on photo is rim/specular-shaped, inherited from dark regular. Native's box is exactly the 88 pt glass (`[75,331,252,88]`); Flutter's is 9 pt taller (`[75,331,251,97]`) — Flutter's clear glass casts a visible drop shadow (copied from `material.regular`, offsetY 6.5) where native's clear glass casts none the box detector can see, the same shadow-extent mechanism as `material.regular`'s bbox/centre failures.
- **dark-white**: mad 8.95 > 4.00, rim_rms 12.54 > 6.00, bbox_pt 9.00, centre_pt 4.50. Same inherited rim residual, and the same shadow-extent mechanism: native `[75,483,252,88]` vs Flutter's `[74,483,254,97]`.
- **light-photo**: rim_rms 19.63 > 6.00, bbox_pt 6.00, centre_pt 3.00 (mad/luminance pass). Native `[75,331,252,88]` vs Flutter `[74,331,253,94]` — again Flutter's shadow extends the box. The filmstrip (`ready.png`) shows Flutter's refraction blurring the shapes behind the glass — a pink triangle and a blue oval near the top-right lose their sharp edges — where native's refraction keeps the same shapes crisp.
- **light-white**: mad 4.19 > 4.00 (narrowly), luminance 3.66 > 3.00, rim_rms 10.17 > 6.00, bbox_pt 6.00, centre_pt 2.50. On white the two pills read as nearly the same flat grey fill; Flutter's is fractionally darker/cooler and its box is 7 pt taller (`[73,482,256,95]` vs native's `[75,483,252,88]`) from the same shadow Flutter draws under clear glass that native's crisp-edged pill does not show.

### material.tinted (Done item 3) — 6 of 6 fail

- **dark-black**: rim_rms 49.08 > 6.00 (largest rim residual in the run), mad 4.61 > 4.00, bbox_pt 2.00, centre_pt 2.00. `rim_profile` samples the centre column of the *scored* box, here the 88 pt block `native_box [76,365,250,88]`; Flutter's matching block is `[76,363,250,88]` — 2 pt higher, exactly matching bbox/centre (both 2.0). That 2 pt vertical offset in the example app's tinted scene shifts Flutter's sample window off native's top edge, where native has a brighter glint (rim peak ≈197) than Flutter reads at the same sample point (≈185 at native's peak index) — the dominant cause of the large rim_rms is this vertical offset, not a missing highlight on the "Run" swatch (which sits at y 501+, well outside the scored 88 pt block).
- **dark-white**: rim_rms 18.64 > 6.00, mad 5.66 > 4.00, bbox_pt 2.00, centre_pt 2.00. Same 2 pt vertical offset (`native_box [75,365,252,97]` vs `[74,363,254,97]`).
- **dark-stripes**: rim_rms 9.99 > 6.00, bbox_pt 2.00, centre_pt 2.00 (mad/luminance pass). Same offset, smaller effect against the striped backdrop.
- **light-black**: rim_rms 39.30 > 6.00, mad 5.01 > 4.00, bbox_pt 3.00, centre_pt 2.00. Same offset (`native_box [75,364,252,90]` vs `[76,363,250,88]`, 3 pt at the bottom edge in light appearance).
- **light-white**: rim_rms 21.48 > 6.00, mad 5.14 > 4.00, bbox_pt 2.00, centre_pt 2.00. Same offset (`[75,364,252,95]` vs `[73,362,256,95]`).
- **light-stripes**: rim_rms 9.53 > 6.00, bbox_pt 2.00, centre_pt 2.00 (mad/luminance pass). Same offset.

Every tinted case fails on rim_rms, by a wide margin on black and white. The dominant cause is a 2–3 pt placement offset (mostly vertical) in the example app's tinted scene between native and Flutter, which shifts `rim_profile`'s sample column off native's brighter top-edge glint — not a missing gloss highlight on the "Run" swatch, which sits below the scored block and is outside `rim_profile`'s sample window.

### material.edge (Done item 4) — 4 of 6 fail

- **edge.soft dark-scroll**: mad 21.27 > 4.00 (luminance 1.64 passes). Matches the known residual: the soft scroll edge over-dims with a moiré texture in the blur band, producing a large MAD even though average luminance matches.
- **edge.soft light-scroll**: mad 5.67 > 4.00 (luminance 0.41 passes). Same moiré-texture cause, smaller in light appearance.
- **edge.hard dark-scroll**: mad 4.56 > 4.00, narrowly over threshold (luminance 0.45 passes). Consistent with the tuning log's accepted narrowed-rerun residual (mad 5.37 there vs 4.56 here, same order).
- **edge.automatic dark-scroll**: mad 4.56 > 4.00, identical values to `edge.hard dark-scroll` — `automatic` uses the hard-style search per the tuning log, so the same residual carries over.
- **edge.hard light-scroll** and **edge.automatic light-scroll** pass (mad 1.91, luminance 0.52 both).

### Accessibility — Reduce Transparency (Done item 5) — 10 of 10 fail

Run `20260930-094506`. rim_rms fails on 9 of 10 backdrops; **light-white passes** (5.60 ≤ 6.00). dark-black's rim (6.12) is actually *better* than the plain-mode black rim (8.26) — RT's tone shift does not compound the rim residual on black; light-black (25.14) is far worse. The same bbox_pt/centre_pt numbers as plain `material.regular` reappear identically on photo/stripes/text/white (10.00/12.00/7.00/9.00/10.00 pt) because the a11y rows reuse the same shadow parameters as plain mode — this is the same shadow-extent residual documented under Done item 3 (material.regular), not a fresh accessibility-mode effect. dark-photo, dark-stripes, dark-text additionally fail mad/luminance (up to mad 8.55, luminance 4.78).

Per-case filmstrips (`ready.png`, native vs flutter):
- **dark-black**: rim-only failure (6.12); the same crisp-vs-soft rim highlight difference as plain dark-black, slightly reduced by RT's own tone shift.
- **dark-photo**: fails mad/luminance/rim/bbox/centre; native's photo backdrop dims more evenly under RT than Flutter's, on top of the usual shadow-extent box delta.
- **dark-stripes**: mad (8.55) fails while luminance (0.06) passes; the striped backdrop under Flutter's glass reads patchier than native's evenly dimmed stripes.
- **dark-text**: mad 5.14/luminance 2.63 near threshold, rim 10.11 fails; native's text glyphs dim more uniformly under RT than Flutter's.
- **dark-white**: mad/luminance pass but rim (11.10) and box (12.0/6.0) fail; the same shadow-extent box delta as plain dark-white.
- **light-black**: rim-only failure, and the worst RT case (25.14); the light-appearance rim residual is markedly larger than dark's (6.12), consistent with material.regular's light-black rim (17.70) already exceeding dark-black's (8.26) before RT.
- **light-photo**: mad/luminance pass, rim (10.51) and box fail; the same shadow-extent box delta as plain light-photo, RT's frost narrows but does not close the rim gap.
- **light-stripes**: mad/luminance pass, rim (7.63) and box fail; same pattern as light-photo, a smaller rim residual.
- **light-text**: mad/luminance pass, rim (6.28, narrowly over) and box fail; same shadow-extent box delta as plain light-text.
- **light-white**: only box fails (rim 5.60 and mad/luminance all pass); the capsule and its RT frost read the same in both apps here — the remaining bbox_pt/centre_pt (10.0/6.0) come entirely from the shadow-extent mechanism, not a visible RT difference.

### Accessibility — Increase Contrast (Done item 5) — 10 of 10 fail

Run `20260930-095626`. dark-text (mad 10.70, luminance 8.42, rim 9.66) and light-photo (mad 13.25, luminance 13.20, rim 16.81) are the worst cases in the run, both on `photo`/`text`, which were never part of the IC tuning grid (`stripes,white,black` only, per the tuning log's IC redo section) — untested-backdrop residuals. But `dark-white` (mad 10.19, luminance 7.49) and `dark-stripes` (mad 8.20, luminance 4.42) also fail mad/luminance despite `white` and `stripes` being tuned IC backdrops, so IC's regression is not confined to untested backdrops. The same shadow-extent bbox_pt/centre_pt pattern documented under Done item 3 reappears here too.

Per-case filmstrips:
- **dark-black**: rim-only failure (8.08), about the same as plain dark-black (8.26); IC's contrast boost does not meaningfully change the rim residual on black.
- **dark-photo**: fails mad/luminance/rim/bbox/centre; IC's contrast boost widens the gap on the photo backdrop beyond even RT's (mad 9.47 vs RT's 6.94).
- **dark-stripes**: rim passes (5.80) but mad (8.20) and luminance (4.42) fail — the one case where IC's contrast boost creates a visible tonal difference on a tuned backdrop despite the rim itself matching.
- **dark-text**: worst dark-mode case (mad 10.70, luminance 8.42, rim 9.66); IC's contrast boost most visibly separates native's and Flutter's text-backdrop dimming here.
- **dark-white**: mad 10.19/luminance 7.49 fail despite white being a tuned IC backdrop; Flutter's glass reads visibly lighter and less contrasty than native's under IC on white.
- **light-black**: the only IC case where mad (4.48) and luminance (3.77) also fail alongside rim (23.70); light-mode IC's contrast boost creates a genuine tonal gap on black, not just a rim residual.
- **light-photo**: worst case in the entire run (mad 13.25, luminance 13.20, rim 16.81) — the filmstrip shows Flutter's top rim as a distinct bright pink/magenta outline that native's softer, yellow-tinted highlight does not show, and Flutter's fill leans more uniformly green/pink than native's warmer, patchier tint.
- **light-stripes**: rim passes (7.85, narrowly) but mad (8.08) fails while luminance (0.10) passes; a patchy, not systematically brighter or darker, difference across the stripes.
- **light-text**: mad/luminance/rim all pass; only the shadow-extent box delta (10.0/6.0) keeps this case failing overall.
- **light-white**: closest to passing entirely — only box fails (rim 5.64, mad 1.26, luminance 0.54 all pass), the same shadow-extent mechanism as light-white RT.

## Operator components (Done item 6)

Runs (after the lab appearance fix, `567d0e7ac`): `tabbar.rest` → `20260930-104535`, `button.press` → `20260930-105500`, `navbar.inline` → `20260930-105756`, all `--app both --appearance both --flutter operator`. The comparison script (`task-12-brief.md` Step 4) now imports `LIMITS` from `tool/glass_lab/harness/metrics.THRESHOLDS` (`rim_rms` 6.0, `luminance` 3.0) instead of a hardcoded copy of the same numbers, so a future threshold change can't silently diverge between the two.

Superseded runs `20260930-100915`/`20260930-101816`/`20260930-102112` (Operator rebuilt, but the lab still measured the light material in dark mode) are summarised below for the record but are not evidence for Done item 6.

| Case | Measure | Baseline | Now | Verdict |
|---|---|---|---|---|
| tabbar.rest dark-black | rim_rms | 25.57 | 7.29 | ok |
| tabbar.rest dark-black | luminance | 13.59 | 5.54 | ok |
| tabbar.rest dark-photo | rim_rms | 19.43 | 6.71 | ok |
| tabbar.rest dark-photo | luminance | 9.13 | 2.51 | ok |
| tabbar.rest dark-stripes | rim_rms | 9.54 | 7.90 | NOT HALVED |
| tabbar.rest dark-stripes | luminance | 7.05 | 0.10 | ok |
| tabbar.rest dark-white | rim_rms | 44.09 | 14.20 | ok |
| tabbar.rest dark-white | luminance | 40.67 | 6.65 | ok |
| tabbar.rest light-black | rim_rms | 22.69 | 16.17 | NOT HALVED |
| tabbar.rest light-black | luminance | 13.93 | 4.57 | ok |
| tabbar.rest light-photo | rim_rms | 12.49 | 14.79 | NOT HALVED |
| tabbar.rest light-photo | luminance | 3.88 | 6.75 | NOT HALVED |
| tabbar.rest light-stripes | rim_rms | 9.74 | 8.71 | NOT HALVED |
| tabbar.rest light-stripes | luminance | 5.16 | 1.43 | ok |
| tabbar.rest light-white | rim_rms | 5.22 | 4.36 | ok |
| tabbar.rest light-white | luminance | 0.68 | 1.68 | ok |
| button.press dark-stripes | rim_rms | 13.37 | 9.33 | NOT HALVED |
| button.press dark-stripes | luminance | 2.95 | 0.08 | ok |
| button.press light-stripes | rim_rms | 13.47 | 7.69 | NOT HALVED |
| button.press light-stripes | luminance | 0.67 | 1.13 | ok |
| navbar.inline dark-black | rim_rms | 27.50 | 22.36 | NOT HALVED |
| navbar.inline dark-black | luminance | 6.71 | 0.15 | ok |
| navbar.inline dark-stripes | rim_rms | 16.37 | 15.48 | NOT HALVED |
| navbar.inline dark-stripes | luminance | 3.79 | 0.69 | ok |
| navbar.inline dark-white | rim_rms | 41.15 | 28.53 | NOT HALVED |
| navbar.inline dark-white | luminance | 7.38 | 1.80 | ok |
| navbar.inline light-black | rim_rms | 96.06 | 60.80 | NOT HALVED |
| navbar.inline light-black | luminance | 2.16 | 3.99 | NOT HALVED |
| navbar.inline light-stripes | rim_rms | 58.81 | 37.17 | NOT HALVED |
| navbar.inline light-stripes | luminance | 2.00 | 1.11 | ok |
| navbar.inline light-white | rim_rms | 44.80 | 44.80 | NOT HALVED |
| navbar.inline light-white | luminance | 1.29 | 1.76 | ok |

**14 of 32 measures not halved** (18 of 32 halved), all of it a large improvement over the pre-fix run's 25 of 32 not halved. Every `luminance` measure now passes except `tabbar.rest light-photo` and `navbar.inline light-black`; the remaining failures are concentrated in `rim_rms`, still over threshold on 10 of 12 cases.

Filmstrips for the still-failing cases (`ready.png`, native vs flutter, from the runs above):

- **tabbar.rest dark-stripes** (rim): flutter's selected-tab pill reads slightly less saturated and warm than native's over the same stripe backdrop — a smaller version of the same rim residual, not a gross mismatch.
- **tabbar.rest light-black** (rim): the rim column sits mid-bar, between the PRs and Settings tabs, not behind the selected icon; there, native shows a bright top-edge glint (rim value 175 at the sample position where flutter's antialiased edge reads only 39) — a real edge-highlight difference, not a halo behind Agents.
- **tabbar.rest light-photo** (rim, luminance): native's bar is visibly brighter and pinker than flutter's over the busy photo backdrop (mean fill RGB native ≈219/147/194 vs flutter ≈199/138/178; luminance 6.75) — native's selected pill carries a more saturated pink glow where flutter's reads duller.
- **tabbar.rest light-stripes** (rim): same pattern as dark-stripes — flutter's pill edge is a shade less saturated than native's.
- **button.press dark-stripes** (rim): the "Glass button" label renders white in native but green (Operator's accent color) in flutter — the label's own tint, not the capsule's rim, drives the residual.
- **button.press light-stripes** (rim): same accent-tinted label difference as the dark case; the capsule edges themselves look close.
- **navbar.inline dark-black** (rim): both back circles are neutral dark grey on black; the real cause of the rim residual is shape, not tint — native's scored box is a clean 102×44 capsule (`native_box [284,62,102,44]`) while flutter's trailing bell/more group renders as two fused circles, a 106×54 "peanut" (`flutter_box [285,57,106,54]`), and `rim_profile`'s sample column falls on the peanut's waist, so flutter's edges sit a few points inside native's at that column.
- **navbar.inline dark-stripes** (rim): flutter's back-button circle is a solid, opaque red-pink where native's stays a translucent red-tinted circle that shows the stripe underneath; flutter's bell icon is green where native's is white.
- **navbar.inline dark-white** (rim): same accent-tint pattern — flutter's bell/more icons render green, native's stay white.
- **navbar.inline light-black** (rim, luminance): flutter's bell/more pill shows a bright radial glow along its top edge that native's pill does not have, and its icons pick up a green tint where native's stay black.
- **navbar.inline light-stripes** (rim): flutter's back-button circle is again a more saturated red-pink than native's softer translucent one, and its bell icon is green versus native's black.
- **navbar.inline light-white** (rim): the capsules read close at this resolution; the persistent icon-color difference (green bell/dots in flutter vs black in native) is the visible residual.

A consistent pattern runs through the still-failing `navbar.inline` and `button.press` cases: flutter's glass icons and button labels pick up Operator's green accent color where native's stay neutral white or black, and flutter's opaque circular buttons (the nav back button) read more saturated than native's translucent ones. `tabbar.rest`'s remaining failures are smaller and mostly within the same rim-residual family documented for `material.regular` in Done item 3 (a crisper rim than native's soft highlight).

### Superseded pre-fix runs (measured the light material in dark mode)

Runs: `tabbar.rest` → `20260930-100915`, `button.press` → `20260930-101816`, `navbar.inline` → `20260930-102112`.

**25 of 32 measures not halved.** Only 7 passed, all in the light appearance — every dark-appearance measure failed, and most were *worse* than the project 1 baseline (e.g. `tabbar.rest dark-black` rim_rms 25.57 → 70.19, `navbar.inline dark-black` rim_rms 27.50 → 62.68). A side-by-side of `tabbar.rest/dark-black/{native,flutter}/ready.png` from that run showed native's tab bar over black as an almost-invisible dark capsule with a thin bright rim, while flutter's capsule rendered as a solidly lit, opaque light-grey pill — consistent with the lab measuring the light material regardless of the requested dark appearance.

## Informational: Tinted under Reduce Transparency

Not a Done criterion (controller ruling C3). Run: `lab.py run material.tinted --appearance both --a11y reduce-transparency` → run `20260930-103050`. Accessibility confirmed back to `0` afterward.

| Case | mad | luminance | rim_rms | bbox_pt | centre_pt |
|---|---|---|---|---|---|
| dark-black | 5.09 | 0.55 | 48.84 | 2.00 | 2.00 |
| dark-stripes | 5.32 | 3.84 | 9.77 | 2.00 | 2.00 |
| dark-white | 8.42 | 5.73 | 21.22 | 2.00 | 2.00 |
| light-black | 12.31 | 13.03 | 49.24 | 3.00 | 2.00 |
| light-stripes | 5.54 | 4.07 | 12.14 | 2.00 | 2.00 |
| light-white | 4.93 | 0.50 | 21.32 | 2.00 | 2.00 |

The rim residual persists at the same magnitude as plain tinted (dark-black 48.84 vs 49.08 plain; `native_box [76,365,250,88]` vs `flutter_box [76,363,250,88]`, the same 2 pt placement offset), consistent with the placement-offset cause documented under Done item 3; Reduce Transparency's own tone/frost shift additionally pushes mad and luminance over threshold on most backdrops (worst: light-black, mad 12.31, luminance 13.03).

## Gates

`python3 -m unittest discover tool/glass_lab/harness/tests` (from `packages/mobile`): **80 tests, OK.** Harness code was not touched by the lab appearance fix.

The lab appearance fix (`567d0e7ac`) changed `packages/mobile/lib/core/widgets/glass/lab/glass_lab_screen.dart` and added a widget test. App gates for that commit: `flutter analyze` — "No issues found!"; `flutter test` — all tests passed, **2,146** (2,145 before Task 12 plus the one new regression test for this fix).
