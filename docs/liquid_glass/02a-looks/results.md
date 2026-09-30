# 2A results

Date: 2026-09-30. Branch `feat/ios-liquid-glass-2a` at `567d0e7ac`. Simulator: iPhone 17 Pro (iOS 27), UDID 708879DD-8B2A-4547-863F-F49EE1474D8B.

Lab appearance defect (Task 12 rerun): `GlassLabScreen` picked its `DarkSkin`/`LightSkin` from platform brightness but never provided a matching `GlassTheme`, so the package's glass kept reading the app-root `GlassTheme` (light, from `SkinCubit`'s default) regardless of which appearance the lab was running — dark lab runs measured the wrong, light material rows. Fixed in `567d0e7ac` (`fix(mobile): Operator's glass lab gives the glass the lab's appearance`), which wraps the lab scene in its own `GlassTheme` matching the lab's chosen skin. The Operator component runs below supersede the earlier runs `20260930-100915`, `20260930-101816`, `20260930-102112`, which were taken before this fix and measured the light material in dark mode.

| Done item | Result | Evidence |
|---|---|---|
| 1 Package: rename, plugin live toggles, gates, no old imports | not evaluated in Task 12 (outside scope, items 3–6 only) | Task 8 `lab.py a11y` output; gates |
| 2 Example app | not evaluated in Task 12 (outside scope, items 3–6 only) | lab_test; README |
| 3 Material scenes, strict thresholds | 0 of 20 cases pass | `summary-material.md`, run `20260930-082046` |
| 4 Scroll edge MAD and luminance | 2 of 6 cases pass | run `20260930-082046` (edge scenes) |
| 5 Reduce Transparency and Increase Contrast | 0 of 20 cases pass | runs `20260930-094506` (RT), `20260930-095626` (IC) |
| 6 Operator components halve rim and luminance | 18 of 32 measures halved | comparison table below, runs `20260930-104535`/`20260930-105500`/`20260930-105756` (after the lab appearance fix; supersedes `20260930-100915`/`20260930-101816`/`20260930-102112`) |
| 7 Flip spike | not evaluated in Task 12 (outside scope) | flip-spike.md |
| 8 Frame cost within 20% | not evaluated in Task 12 (outside scope) | flip-spike.md |
| 9 Documents | not evaluated in Task 12 (outside scope) | Task 13 |

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
- **dark-photo, dark-stripes, dark-text, dark-white, light-photo, light-stripes, light-text, light-white**: all fail bbox_pt (7.00–12.00 pt, threshold 1.00) and centre_pt (5.00–6.00 pt, threshold 1.00). Checked `native_box`/`flutter_box` in `result.json`: on **black** the two boxes are pixel-identical (`[21,465,360,200]` both apps); on every other backdrop native's detected box is 3–12 px wider/taller than Flutter's. A side-by-side of `material.regular/dark-photo/{native,flutter}/ready.png` shows the two ~200 pt capsules in the same place, visually indistinguishable — the mismatch is the box detector picking up a few extra edge pixels of the busy/light backdrop around native's glass, not a real placement difference (matches the harness's known box-detection fragility on busy or light backdrops, gotchas 8/18 in ROADMAP §4).
  - **dark-text, dark-white, light-photo, light-stripes, light-text**: additionally fail rim_rms (6.63–15.63) or mad/luminance (light-photo: mad 11.17, luminance 9.54; light-text: mad 4.69, luminance 3.73; light-stripes: mad 4.98). `photo` and `text` were never included in the Group A/B tuning backdrops (`stripes,white,black` only, per `tuning-log.md`), so these residuals were never seen or fixed during tuning — light-photo in particular is a genuinely untested combination, not a known residual.

### material.clear (Done item 3) — 4 of 4 fail

- **dark-photo**: mad 9.91 > 4.00, rim_rms 22.31 > 6.00, bbox_pt 9.00, centre_pt 4.50. Matches the known residual: dark clear MAD on photo is rim/specular-shaped, inherited from dark regular.
- **dark-white**: mad 8.95 > 4.00, rim_rms 12.54 > 6.00, bbox_pt 9.00, centre_pt 4.50. Same inherited residual.
- **light-photo**: rim_rms 19.63 > 6.00, bbox_pt 6.00, centre_pt 3.00 (mad/luminance pass).
- **light-white**: mad 4.19 > 4.00 (narrowly), luminance 3.66 > 3.00, rim_rms 10.17 > 6.00, bbox_pt 6.00, centre_pt 2.50.

### material.tinted (Done item 3) — 6 of 6 fail

- **dark-black**: rim_rms 49.08 > 6.00 (largest rim residual in the run), mad 4.61 > 4.00, bbox_pt 2.00, centre_pt 2.00.
- **dark-white**: rim_rms 18.64 > 6.00, mad 5.66 > 4.00, bbox_pt 2.00, centre_pt 2.00.
- **dark-stripes**: rim_rms 9.99 > 6.00, bbox_pt 2.00, centre_pt 2.00 (mad/luminance pass).
- **light-black**: rim_rms 39.30 > 6.00, mad 5.01 > 4.00, bbox_pt 3.00, centre_pt 2.00.
- **light-white**: rim_rms 21.48 > 6.00, mad 5.14 > 4.00, bbox_pt 2.00, centre_pt 2.00.
- **light-stripes**: rim_rms 9.53 > 6.00, bbox_pt 2.00, centre_pt 2.00 (mad/luminance pass).

Every tinted case fails on rim_rms, by a wide margin on black and white. Matches the known residual: tinted's "Run" swatch lacks native's glossy highlight, so the rim measure never gets close to threshold regardless of backdrop.

### material.edge (Done item 4) — 4 of 6 fail

- **edge.soft dark-scroll**: mad 21.27 > 4.00 (luminance 1.64 passes). Matches the known residual: the soft scroll edge over-dims with a moiré texture in the blur band, producing a large MAD even though average luminance matches.
- **edge.soft light-scroll**: mad 5.67 > 4.00 (luminance 0.41 passes). Same moiré-texture cause, smaller in light appearance.
- **edge.hard dark-scroll**: mad 4.56 > 4.00, narrowly over threshold (luminance 0.45 passes). Consistent with the tuning log's accepted narrowed-rerun residual (mad 5.37 there vs 4.56 here, same order).
- **edge.automatic dark-scroll**: mad 4.56 > 4.00, identical values to `edge.hard dark-scroll` — `automatic` uses the hard-style search per the tuning log, so the same residual carries over.
- **edge.hard light-scroll** and **edge.automatic light-scroll** pass (mad 1.91, luminance 0.52 both).

### Accessibility — Reduce Transparency (Done item 5) — 10 of 10 fail

Run `20260930-094506`. Failures follow the same two patterns as the un-accessibility regular run: rim_rms fails on every backdrop including black (dark-black 6.12, light-black 25.14 — both worse than the plain-mode black rim, since RT layers its own tone shift on top of the same rim geometry), and the same bbox_pt/centre_pt detection-noise numbers reappear identically on photo/stripes/text/white (10.00/12.00/7.00/9.00/10.00 pt — confirming this is backdrop-dependent box detection, not an accessibility-mode effect). dark-photo, dark-stripes, dark-text additionally fail mad/luminance (up to mad 8.55, luminance 4.78).

### Accessibility — Increase Contrast (Done item 5) — 10 of 10 fail

Run `20260930-095626`. Same two patterns again, generally worse: dark-text (mad 10.70, luminance 8.42, rim 9.66), dark-white (mad 10.19, luminance 7.49, rim 10.16), light-photo (mad 13.25, luminance 13.20, rim 16.81) are the worst cases — all on backdrops (`photo`, `text`) that were never part of the IC tuning grid (`stripes,white,black` only, per the tuning log's IC redo section), so these are untested-backdrop residuals compounding the same detection-noise bbox/centre pattern.

## Operator components (Done item 6)

Runs (after the lab appearance fix, `567d0e7ac`): `tabbar.rest` → `20260930-104535`, `button.press` → `20260930-105500`, `navbar.inline` → `20260930-105756`, all `--app both --appearance both --flutter operator`. The comparison script (`task-12-brief.md` Step 4) now imports `LIMITS` from `tool/glass_lab/harness/metrics.THRESHOLDS` (`rim_rms` 6.0, `luminance` 3.0) instead of a hardcoded copy of the same numbers, so a future threshold change can't silently diverge between the two.

Superseded runs `20260930-100915`/`20260930-101816`/`20260930-102112` (Operator rebuilt, but the lab still measured the light material in dark mode) are kept below for the record but are not evidence for Done item 6.

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
- **tabbar.rest light-black** (rim): native's pill carries a soft, darker circular halo behind the selected "Agents" icon that flutter's pill lacks, leaving flutter's rim edge flatter.
- **tabbar.rest light-photo** (rim, luminance): the two capsules are visually indistinguishable over the busy photo backdrop at this resolution; both measures are numeric residuals, not a visible difference.
- **tabbar.rest light-stripes** (rim): same pattern as dark-stripes — flutter's pill edge is a shade less saturated than native's.
- **button.press dark-stripes** (rim): the "Glass button" label renders white in native but green (Operator's accent color) in flutter — the label's own tint, not the capsule's rim, drives the residual.
- **button.press light-stripes** (rim): same accent-tinted label difference as the dark case; the capsule edges themselves look close.
- **navbar.inline dark-black** (rim): native's back-chevron and bell/more pill stay a neutral dark grey with white icons; flutter's back circle renders a saturated red-pink and its bell icon renders green — both accent/system-color bleed onto the glass, not a shading difference.
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

The rim residual persists at the same magnitude as plain tinted (dark-black 48.84 vs 49.08 plain), consistent with the missing-glossy-highlight cause; Reduce Transparency's own tone/frost shift additionally pushes mad and luminance over threshold on most backdrops (worst: light-black, mad 12.31, luminance 13.03).

## Gates

`python3 -m unittest discover tool/glass_lab/harness/tests` (from `packages/mobile`): **80 tests, OK.** Harness code was not touched by the lab appearance fix.

The lab appearance fix (`567d0e7ac`) changed `packages/mobile/lib/core/widgets/glass/lab/glass_lab_screen.dart` and added a widget test. App gates for that commit: `flutter analyze` — "No issues found!"; `flutter test` — all tests passed, **2,146** (2,145 before Task 12 plus the one new regression test for this fix).
