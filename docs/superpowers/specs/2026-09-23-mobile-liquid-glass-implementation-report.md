# Mobile Liquid Glass engine — implementation report

Date: 2026-09-24. Branch: `feat/mobile-ios-polish`, from `d78b792a0`.
Plan: `docs/superpowers/plans/2026-09-23-mobile-liquid-glass-engine.md`.
Spec: `docs/superpowers/specs/2026-09-23-mobile-liquid-glass-engine-design.md`.
Sign-off note: `docs/superpowers/specs/2026-09-23-mobile-liquid-glass-signoff.md`.

**Status:** Tasks 1–13 are complete and reviewed. Task 14 steps 1–4 are done. **Step 5, the
user's sign-off on the comparison images, is pending.** The project is not done until that
sign-off.

**Gates at HEAD:**

- `flutter analyze` prints `No issues found!`.
- `flutter test` in `packages/mobile`: `+1405: All tests passed!`
- `flutter test` in `packages/liquid_glass_renderer`: `+4: All tests passed!`

**How it was run:** superpowers:subagent-driven-development. Each task had a fresh
implementer, a task review, and fix rounds with scoped re-reviews. Task 14's
capture → compare → adjust loop was run by the controller, and subagents made only bounded
edits. A final whole-branch review on Opus followed, then one fix wave and a scoped
re-review.

## Commits per task

| Task | Commits |
|---|---|
| 1 Native reference and capture tooling | `f91ab51dd` |
| 2 Glass lab route | `ed524b8d9`, `77a38ee15` (capture builds once per scene) |
| 3 Density-correct thickness | `f0e8a42ba` |
| 4 Continuous-corner SDF | `177fb7282`, `f4f359084` (re-fit by measurement) |
| 5 fillRatio and clamped rim | `758d5e6ed` |
| 6 Interaction fixes and dead shader removal | `ce4a85d67` |
| 7 GlassStyle and GlassMetrics | `213fcd984` |
| 8 GlassScope and GlassSurface | `d90196405`, `70dc917cc` |
| 9 GlassButton | `cda1a7b7b`, `464ca08ae` |
| 10 GlassToolbar | `7d315bd54`, `98b333841` |
| 11 GlassTabBar | `649e1c2f7`, `c9849fe45` |
| 12 ScrollEdgeEffect | `b83162e2b`, `44f8db34b`, `58cd13da9`, `85e2ad52b`, `a22fb9e68` |
| 13 GlassSheetChrome | `fde46254e`, `73b7ac7b1` |
| 14 Tuning and sign-off note | `2f64ab56c`, `166485459`, `17fad127e`, `117bc2035`, `103708fa3`, `7ba84fc84`, `fd15d7a4b`, `f24a8eb20`, `af584a6ae`, `e49b36f65`, `487887fb3` |
| Final review fix wave | `b2fa61be2`, `d8f3d07bd`, `13c2d9de2`, `6c2c2e1d9`, `02f8ebd4c` |

**Commit trailers:** the messages of `ed524b8d9`…`f4f359084` were rewritten in place
(`git filter-branch --msg-filter`, tree hash verified identical). Subagents had committed with
their harness's "Claude Sonnet 5" trailer instead of the required
`Co-Authored-By: Claude Opus 5.5`. Every commit on the branch now carries the required trailer.

## Deviations from the plan, and why

### Task 1

- None in code.
- The first dispatch told the implementer to skip `flutter test` because no Dart had changed.
  That was wrong, and the test was run in a fix round.

### Task 2

- **Scene selection:** the lab picks its scene with `--dart-define=GLASS_LAB_SCENE`, not
  `Platform.environment`. `Platform.environment` is empty in an iOS Flutter app even when
  launched with `SIMCTL_CHILD_*`, which was confirmed empirically. `run_lab.sh` builds once per
  scene.
- **Loop order:** `capture.sh` loops scene-outer so each scene builds once. The plan's order
  built four times.
- **Test wrapper:** the lab test needed a `ScreenUtilInit` wrapper, because `AppTextStyle` uses
  `flutter_screenutil`. That is the codebase's test convention, and no assertion changed.

### Task 3

- **Blend was already scaled:** it is × devicePixelRatio at `liquid_glass_blend_group.dart:219`,
  not at the cited 242–246, so only thickness changed.
- **The plan's before/after check could not see the change:** stripes are vertical and 201px
  wide, the capsule's end caps sit inside single stripes, and vertical displacement along
  vertical stripes is invisible.
- **Verification used a temporary probe:** a capsule placed over a horizontal edge. Before the
  fix the colour reached 88px into the capsule; after it, 0px.
- The durable lens-visible check is Task 4's `corners` scene.

### Task 4

- **The plan's crop coordinates missed the corner.** They were corrected to the real geometry.
- **The first fit (4.0 / 1.40) was rejected by the controller.** The lens bulged 7–19px past
  the outline at 45°.
- **Re-fit by ray measurement to `SQUIRCLE_EXPONENT` 3.5 and `SQUIRCLE_EXTENT` 1.65.** Every ray
  is within 1px of the straight-edge baseline, on two corners.

### Task 5

- The plan's `///` doc comment on the new field was omitted, per the user's no-comments rule.
- The package default stays 0.8 (plan), not 0.25 (spec). The app sets its own value through
  GlassStyle.

### Task 6

- `shared.glsl` was also deleted, because only the removed shaders used it.
- A dangling `legacyLiquidGlass` key was removed.

### Task 8

- **Every non-regular variant (clear and prominent) now gets its own layer**, not only
  prominent.
- The reason: `LiquidGlass.auto` ignores its `settings` under an ancestor layer, so a clear
  surface inside a regular scope rendered as regular.

### Task 9

- **A disabled GlassButton renders no `GlassGlow`.** The plan's code let a disabled button glow
  on touch, which breaks the "disabled must not animate" rule.
- **The final review added two more fixes:** the button no longer sticks at the pressed scale if
  it is disabled while pressed, and prominent text uses the new `AppSkin.onGlassProminent` token.

### Task 10

- **The toolbar clamps text scale to 1.8.**
- **The large-text test now measures `RenderParagraph.textSize`.** `tester.takeException()`
  cannot see vertical clipping in a fixed 44pt row: the title measured 46pt at 2.0 before the
  clamp.

### Task 11

Changes beyond the plan:

- **Pointer tracking:** `_activePointer` stops a second finger from double-selecting.
- **Droplet lift:** the lifted droplet overflows the bar vertically (`liftScale` 1.3). The
  plan's droplet merged into the bar's smooth union and was invisible when lifted.
- **Stretch:** stretch follows a `VelocityTracker` and springs back to 1. The plan's per-event
  delta depended on the sample rate and never settled.
- **Reduce Motion:** a non-overshooting curve is used. The spring still bounced.
- **Semantics:** `onTap` is handled, with `excludeSemantics`.
- **Lab scene:** a lab-only `lifted` scene injects a held synthetic touch, to capture the lifted
  droplet.

### Task 12

- **Variant A failed.** A `ShaderMask` cannot mask a `BackdropFilter`, so the band had no blur.
- **The native reference was changed.** It was a `VStack`, and it is now a `ScrollView` with
  `.scrollEdgeEffectStyle(.soft)`. The spec says "a scrolling list", and without a scroll view
  iOS draws no edge effect, so the native side had nothing to match.
- **The effect was refitted from native pixels.** It now uses a black overlay by theme and a
  smoothstep falloff, and a band-height uniform fixes a hard line.
- **Resource handling after review:**
  - the shader is created once and disposed
  - it checks `isShaderFilterSupported`
  - it passes a band-origin uniform, so it works away from the screen edge

### Task 13

- **The sheet height in the lab is 430, not 380.** The first measurement had hit the stripe
  boundary (row 546); the real rim rows are 1245 native and 1395 lab.
- **The barrier dims to match native.** It is black α 0.20 light and 0.48 dark, fitted from
  pixels. The plan had a transparent barrier.
- **After the final review, the sheet body keeps its state across the floating/anchored switch.**
  A `GlobalKey` stops the subtree from remounting.

### Task 14

**Geometry:**

- The native 3-tab bar is 274pt wide, so `tabBarSideInset` is 64.
- A compact 36pt label-button variant was added, with the 44pt hit area kept.
- Other metrics: `primaryButtonInset` 16 plus a new `primaryButtonBottomGap` of 12,
  `toolbarTopGap` 0, `displayCornerRadius` 64, and label padding 14 / 11.

**Type:** 17pt regular labels and a 17pt semibold title.

**Colour:**

- Regular buttons are accent-tinted and prominent text is white, matching the reference's
  `.tint(accent)`.
- Contrast is flagged under "Unfinished and partly verified".

**fillRatio:** 0.7, not the spec's 0.25. Native crops show a thin, near-uniform rim, so the spec's
"dim fill" assumption did not hold.

**Scaling with size:**

- Tint and saturation scale with glass size. Dark regular tints toward `bgElevated`.
- Shadows scale with size, as the spec requires (deferred from Task 7).

**Resolved in the final review fix wave:** the lab route is gated behind `kDebugMode`,
`tabGlyph` is wired to 24, and FORK.md gaps are filled.

## Final capture metrics

`tool/glass_reference/capture.sh` at HEAD, iPhone 17 Pro, iOS 26.5:

| Scene | top_mad | bottom_mad |
|---|---|---|
| light/rest | 5.75 | 7.10 |
| dark/rest | 7.47 | 10.92 |
| light/sheet | 5.11 | 8.76 |
| dark/sheet | 5.52 | 7.70 |

At the start of Task 14 these were:

| Scene | top_mad | bottom_mad |
|---|---|---|
| light/rest | 16.19 | 25.21 |
| dark/rest | 35.31 | 25.42 |
| light/sheet | 12.89 | 48.08 |
| dark/sheet | 20.17 | 10.61 |

## Final GlassMetrics

```
hitTarget 44          toolbarSideInset 16     toolbarTopGap 0        toolbarItemGap 8
tabBarHeight 62       tabBarSideInset 64      tabBarBottomInset 21   tabGlyph 24
dropletInset 4        compactButtonHeight 36  primaryButtonInset 16  primaryButtonBottomGap 12
sheetInset 8          displayCornerRadius 64  floatingSheetMaxFraction 0.9
labelButtonPadding 14 compactLabelButtonPadding 11
```

## Final GlassStyle

`t = sizeProgress(size)`, which runs from 20pt to 600pt.

- **regular, light:** white tint α 0.58→0.76, saturation 2.0→1.24.
- **regular, dark:** `bgElevated` tint α 0.1→0.9, saturation 1.2→1.1.
- **clear:** light: white tint α 0.08; dark: `bgSurface` tint α 0.05. Saturation 1.2, blur
  halved.
- **prominent:** `accent` tint α 0.85, saturation 1.0.
- **All variants:**
  - blur 4.2→5
  - thickness `lerp(10, 30, √t)`
  - lightIntensity 0.55→0.8
  - ambientStrength 0.1
  - refractiveIndex 1.2
  - lightAngle π/2
  - chromaticAberration 0.005
  - fillRatio 0.7
- **Increase Contrast:** tint α + 0.3, capped at 0.92, and a 1px `borderStrong` outline.
- **Shadows:** black, `BlurStyle.outer`.
  - contact: α 0.05 light / 0.06 dark, radius 1→3
  - ambient: α 0.12 light / 0.10 dark, radius 24→40

## SQUIRCLE constants

`SQUIRCLE_EXPONENT 3.5`, `SQUIRCLE_EXTENT 1.65` (`liquid_glass_renderer/lib/assets/shaders/sdf.glsl`).

## ScrollEdgeEffect variant kept

**Variant B:** an `ImageFilter.shader` vertical variable blur (`packages/mobile/shaders/scroll_edge_blur.frag`).

- **Overlay:** black overlay by theme.
- **Max alpha:** light 0.26 at both edges; dark 0.6 top and 0.49 bottom.
- **Falloff and blur:** smoothstep knee 0.45 at the top and 0.8 at the bottom, blur radius 4pt.
- **Lab bands:** 140pt at the top and 120pt at the bottom.
- **Fallback:** the widget falls back to variant A's tree where shader filters are unsupported
  (the Skia test host).
- **Why:** variant A did not blur at all on device.

## Unfinished, or verified only partly

- **User sign-off (Task 14 step 5) is pending.**
- **Not built:**
  - The spec's `clear`-variant 35% dim layer.
  - Reduce Transparency, which is out of scope by spec decision 2.
- **Not captured against native:**
  - Press and mid-drag states. The lab's `lifted` scene shows only the lifted droplet.
  - The tab-bar stretch dynamics. `stretchVelocityDivisor` 400 is untuned.
- **Lens width and refraction strength:** thickness and refractiveIndex are the plan's starting
  values. The comparison scenes cannot show the lens band. The `corners` scene can, and it was
  used for the SDF fit.
- **Remaining visible differences:** these are listed in the sign-off note.
  - Native's title adapts to luminance.
  - Dark toolbar glass reads darker than native. This is structural: the lab's glass samples
    content after the scroll-edge darkening.
  - Native has brighter rims.
  - Glyphs differ: SF Symbols against Material icons.
  - Native tab labels use vibrancy.
  - Native shows no sheet grabber.
- **Design decision for the user:**
  - Accent-tinted regular glass buttons (#1ACB64 on white glass) have about 2.1:1 contrast,
    below WCAG AA.
  - They match the native reference, but whether regular buttons default to accent should be
    decided before project 2 adopts them.
- **Preconditions for project 2:**
  - A pointer-up far off the tab bar still selects a tab. The `Listener` is outside the gesture
    arena, so a scroll takeover never cancels it.
  - `ScrollEdgeEffect` re-measures its band origin only when it rebuilds, which is wrong inside a
    sliding sheet.
- **Other deferred minors:** `GlassSurface`'s grouped branch computes unused settings; the
  circle, rect and grouped kinds have no direct tests; glow alphas and the toolbar's 1.8 text
  cap are local constants; the droplet jumps to the finger on press; there is no GLES y-flip,
  since Android is out of scope; `_MeasuredSheet` schedules a redundant post-frame measure.
- **Physical-device performance is not measured.** This covers the 49-tap blur and the glass
  backdrop passes; the simulator does not measure GPU cost faithfully.

## Rulings made during execution

Each ruling is listed with what it costs if wrong. The full ledger lived in the git-ignored
workspace; these are all of its rulings.

1. **fillRatio package default 0.8, not the spec's 0.25.**
   - Why: the app sets its own value through GlassStyle.
   - Cost if wrong: raw LiquidGlass users get the upstream rim.
2. **The `///` doc comment on fillRatio was omitted.**
   - Why: the no-comments rule.
   - Cost if wrong: one undocumented field.
3. **Blend is scaled by DPR only if it wasn't already.** It already was.
4. **The clear dim layer and mid-press captures were not built.**
   - Why: they are not in the plan. They are listed above.
5. **Literal black/white glass-light constants are accepted.**
6. **iPhone 17 Pro, not the spec's iPhone 16 Pro.**
   - Why: the user's instruction.
7. **Lab scene via `--dart-define`.**
   - Cost if wrong: one build per scene.
8. **`ScreenUtilInit` in lab tests.**
   - Cost if wrong: none; it is the codebase convention.
9. **The corners scene serves as the durable lens check.**
   - Cost if wrong: thickness regressions are visible only in the corners captures.
10. **The commit trailers were rewritten by the controller.**
    - Cost if wrong: none to the tree; the old SHAs in reports are stale.
11. **Shadow size scaling was deferred to Task 14,** where it was done.
12. **Every non-regular variant gets its own layer.**
    - Cost if wrong: an extra nested layer for clear glass.
13. **All four Task 11 review findings were fixed in round 1, over the plan's code.**
    - Cost if wrong: a more complex tab bar.
14. **The native reference became a ScrollView.**
    - Cost if wrong: earlier metrics are not comparable across that change.
15. **The sheet barrier dims to match native.**
    - Cost if wrong: sheets dim the app behind them.
16. **fillRatio 0.7, against the spec's "dim fill".**
    - Cost if wrong: the rim is less directional than the spec imagined.
17. **Accent-tinted regular buttons and white prominent text.**
    - Cost if wrong: the contrast issue above.
    - The final review moved the white into `AppSkin.onGlassProminent`.
18. **Blur 4.2–5 kept despite a +0.17 bottom_mad.**
    - Cost if wrong: within noise.
19. **Size-scaled tint kept although dark/rest rose 0.3 in total.**
    - Why: the sheets fell by about 7.7.
    - Cost if wrong: the dark tab bar is a shade off its best.
20. **Dark large glass tints toward bgElevated.**
    - Cost if wrong: the dark tab bar is a shade lighter than its best.
