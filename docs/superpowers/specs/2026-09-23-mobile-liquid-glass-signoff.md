# Mobile Liquid Glass engine — sign-off note

Date: 2026-09-24. Branch: `feat/mobile-ios-polish`. Status: **awaiting user sign-off.**

Device: iPhone 17 Pro simulator, iOS 26.5 runtime (Xcode 26.6), UDID
`94D0C207-A90B-4806-BBAB-8AF9B3F16329`.

The native reference (`packages/mobile/tool/glass_reference/GlassReference.swift`) and the
Flutter glass lab render the same fixed scene. `tool/glass_reference/capture.sh` screenshots
both and writes `build/captures/compare_*.png` (native | lab | diff ×4) and `compare_*_zoom.png`
(the top and bottom 150pt of each, native left, lab right).

## Final capture metrics

`top_mad` / `bottom_mad` are the mean absolute RGB difference over the top and bottom 450px
strips (0–255 scale).

| Scene | top_mad | bottom_mad | Before tuning (start of Task 14) |
|---|---|---|---|
| light/rest | 5.75 | 7.10 | 16.19 / 25.21 |
| dark/rest | 7.47 | 10.92 | 35.31 / 25.42 |
| light/sheet | 5.11 | 8.76 | 12.89 / 48.08 |
| dark/sheet | 5.52 | 7.70 | 20.17 / 10.61 |

For scale, the first lab baseline (Task 2, before any chrome existed in the lab) was
light/rest 6.89 / 26.92 and dark/rest 6.26 / 23.42.

## Final values

### GlassMetrics

| Constant | Value | Source |
|---|---|---|
| hitTarget | 44 | plan |
| toolbarSideInset | 16 | measured, matches |
| toolbarTopGap | 0 | measured (was 4; lab sat 4pt low) |
| toolbarItemGap | 8 | plan |
| tabBarHeight | 62 | measured, matches |
| tabBarSideInset | 64 | measured (native 3-tab bar is 274pt wide) |
| tabBarBottomInset | 21 | measured, matches |
| tabGlyph | 24 | measured (native tab icon glyph) |
| dropletInset | 4 | plan |
| compactButtonHeight | 36 | measured (native `.glassProminent` capsule) |
| primaryButtonInset | 16 | measured (right inset) |
| primaryButtonBottomGap | 12 | measured (gap above the tab bar) |
| labelButtonPadding / compactLabelButtonPadding | 14 / 11 | measured widths |
| sheetInset | 8 | measured |
| displayCornerRadius | 64 | measured (sheet corner extent 179px vs native 178px) |
| floatingSheetMaxFraction | 0.9 | plan |

### GlassStyle.resolve (t = sizeProgress(size), 20→600pt)

| Setting | regular light | regular dark | clear | prominent |
|---|---|---|---|---|
| tint | white, α 0.58→0.76 | bgElevated, α 0.1→0.9 | white 0.08 / bgSurface 0.05 | accent 0.85 |
| saturation | 2.0→1.24 | 1.2→1.1 | 1.2 | 1.0 |
| blur | 4.2→5 | 4.2→5 | half | 4.2→5 |
| thickness | 10→30 (√t) | same | same | same |
| lightIntensity | 0.55→0.8 | same | same | same |
| fillRatio | 0.7 | 0.7 | 0.7 | 0.7 |
| chromaticAberration | 0.005 | | | |
| ambientStrength / refractiveIndex / lightAngle | 0.1 / 1.2 / π/2 | | | |

Shadows (black, `BlurStyle.outer`): contact α 0.05 light / 0.06 dark, radius 1→3; ambient
α 0.12 light / 0.10 dark, radius 24→40.

### Other tuned values

- `SQUIRCLE_EXPONENT` 3.5, `SQUIRCLE_EXTENT` 1.65 (`sdf.glsl`, fitted by ray measurement to
  `RoundedSuperellipseBorder`, within 1px on every ray).
- ScrollEdgeEffect (variant B, variable-blur shader): black overlay, max alpha light 0.26 top /
  0.26 bottom, dark 0.6 top / 0.49 bottom; knee 0.45 top / 0.8 bottom; blur radius 4pt; lab bands
  140pt top / 120pt bottom.
- Sheet barrier: black α 0.20 light (`0x33000000`), 0.48 dark (`0x79000000`).
- Tab bar droplet: liftScale 1.3, stretchVelocityDivisor 400 (not verified against native).

## Remaining visible differences

- **Title colour, both themes, rest scene.** Native renders "Agents" white over the colourful band
  (iOS luminance adaptation). The lab keeps `textPrimary`. Out of scope by spec decision 1.
- **Toolbar back circle and Edit capsule, dark (and slightly light).** Native glass interiors
  read lighter. The lab's glass samples content after the ScrollEdgeEffect has darkened it; native
  glass appears to sample the undarkened content. This is structural, not a constant.
- **Glass rims, both themes.** Native has a thin, bright, near-uniform white ring on every glass
  shape. The lab's rim is fainter. Raising lightIntensity and ambientStrength did not move it
  measurably.
- **Glyphs, both themes.** SF Symbols (native) vs Material icons (lab): the tab icons, back chevron
  and play glyph differ in shape and weight. Icons are project 2.
- **Tab labels, dark.** Native labels take a vibrancy tint from the backdrop; the lab's are
  plain white or accent.
- **Sheet grabber, both themes.** Native shows no grabber with a single `.medium` detent;
  GlassSheetChrome always draws one.
- **Sheet label position.** The lab's "Sheet" text sits about 28pt lower than native's (lab
  content only).

## Deviations from the spec and unfinished items

- The `clear` variant's 35% dim layer (spec B) was not built.
- Native mid-press captures (spec C) were not taken; the lab `lifted` scene is lab-only.
- Reduce Transparency is out of scope (spec decision 2) and remains a follow-up.
- `fillRatio` is 0.7, not the spec's 0.25, because native crops show a near-uniform rim.
- The package default `fillRatio` stays 0.8 (plan) against the spec's 0.25.
- Regular glass buttons are accent-tinted and prominent text is white, matching the native
  reference's `.tint(accent)`. Accent #1ACB64 against white glass is about 2.1:1 contrast,
  below WCAG AA for 17pt text; this is a design decision for the user before project 2.
- The native reference was changed from a `VStack` to a `ScrollView` (spec: "a scrolling
  list") so iOS draws its scroll-edge effect.
- The sheet dims its barrier (black 0.20 light / 0.48 dark), fitted to native, where the
  plan had a transparent barrier.
- `tabBarSideInset` is 64 (the measured native 3-tab width), not the spec's 21pt; project 2
  must size the bar by tab count.
- `GlassTabBar`: a pointer-up far off the bar still selects, since the `Listener` is outside
  the gesture arena. Fix before project 2 uses it on scrolling screens.
- `ScrollEdgeEffect` re-measures its band origin only on rebuild. Fix before any sheet uses it.

## Not verified by these captures

- Lens-band width and refraction strength (thickness, refractiveIndex). The rest scene cannot
  show the lens (Task 3), so they keep the plan's starting values. The lab's `corners` scene
  shows the lens and was used for the SDF fit.
- Press and mid-drag states against native: there is no native mid-press capture. The lab's
  `lifted` scene shows the tab-bar droplet lifted.
- The `clear` variant (no native element uses it in the reference scene).
