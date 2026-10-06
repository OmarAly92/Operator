# Mobile Liquid Glass engine — design

Date: 2026-09-23. Branch: `feat/mobile-ios-polish`. Package: `packages/mobile`.

## Why

The mobile app is being redesigned toward a native iOS 26 feel. The user's bar is
explicit: "perfect, not a cheap copy". A frosted `BackdropFilter` is the cheap copy.
The real material is Apple's Liquid Glass: lensing at the rim, a nearly clear centre,
a directional specular rim, and gel-like interaction.

This spec covers **project 1 of 2: the glass engine**. It delivers a tuned renderer
plus the core glass widgets, and proves them against Apple's own glass in the same
simulator. **Project 2** comes after this ships, with its own spec. It applies the
engine to every screen and adds the rest of the iOS pass: Cupertino routes with
swipe-back, large titles, action sheets and context menus, iOS controls, SF-style
icons, and haptics.

## Decisions already made (user, 2026-09-23)

| Decision | Choice |
|---|---|
| Direction | Full iOS polish. The Pencil prototype in `docs/design/` no longer constrains layout, chrome or components. |
| Colours and type | Keep the current `AppSkin` palette (light and dark), Anthropic Sans and JetBrains Mono. |
| Platform | **iOS only.** Android is out of scope: it is not verified, tuned or tested. It must still build, because CI runs `flutter analyze` and `flutter test`. |
| Renderer | `liquid_glass_renderer`, vendored as a workspace package at `packages/liquid_glass_renderer` from upstream `ad3bcff`, committed as `61c90e668`. It is ours to customise, and every change is logged in its `FORK.md`. |

## Decisions made in this spec (override on review)

1. **Glass adapts to the app theme, not to the luminance of what's behind it.**
   - Apple flips small bars light or dark based on the backdrop.
   - Doing that here needs a GPU readback per bar, plus a matching foreground colour
     flip in Dart that the shader cannot tell us about.
   - Operator's content is its own themed surfaces, so the theme already predicts the
     backdrop in almost every case.
   - Revisit only if the side-by-side comparison shows a visible gap over mixed content.
2. **Accessibility:**
   - **Reduce Motion** (`MediaQuery.disableAnimationsOf`) disables stretch, bounce and
     the droplet's squash.
   - **Increase Contrast** (`MediaQuery.highContrastOf`) adds a solid 1px border and
     raises tint opacity.
   - **Reduce Transparency** is not exposed by Flutter, so reading it needs a small
     iOS method channel. It is out of scope for this project and logged as a follow-up.
3. **No SkSL port of the geometry shader.** Skia only matters for Android. Instead,
   the two unused shaders (`liquid_glass_filter.frag`, and `liquid_glass_arbitrary.frag`
   for `Glassify`) are dropped from the package `pubspec.yaml`. That removes most of the
   build-log noise.

## Scope

### A. Renderer changes (`packages/liquid_glass_renderer`)

Each change is logged in `FORK.md` with its reason. Line references are to the
vendored source at `61c90e668`.

1. **Density-correct thickness.**
   - Shapes are uploaded in physical pixels (`liquid_glass_blend_group.dart:242-246`),
     but `thickness` is not scaled (`:218`).
   - The lens band is therefore about 3× too thin on a 3x iPhone.
   - Fix: scale thickness, and the smooth-union `blend` it pairs with, by the device
     pixel ratio.
2. **True continuous corners.**
   - `LiquidRoundedSuperellipse`'s SDF (`sdf.glsl:17-25`) is the same formula as the
     rounded rect.
   - The clip and shadow use a real `RoundedSuperellipse` (`liquid_shape.dart:53`,
     `glass_shadow.dart:144`), so the lens and the silhouette disagree at the corners.
   - Fix: replace it with a superellipse SDF that matches Flutter's `RoundedSuperellipse`.
3. **Directional specular.**
   - Today the opposite side gets 0.8 of the key light (`liquid_glass_final_render.frag:104-114`).
     The rim is nearly symmetric and the sum is unclamped.
   - Apple's rim is bright on the lit side with a dim fill opposite.
   - Fix: add a `fillRatio` setting (default 0.25) and clamp the result.
   - Fix: scale specular and bevel width with shape size, so bigger glass reads as thicker.
4. **Interaction fixes.**
   - `GlassGlow` springs its offset back to `Offset.zero` on release
     (`glass_glow.dart:183`), so the glow slides to the top-left corner. Fix: fade it in
     place.
   - `GlassDragBuilder` in listener mode has no `onPointerCancel`
     (`internal/glass_drag_builder.dart:61-83`), so a cancelled touch sticks pressed.
     Fix: handle cancel.
5. **Materialise, don't fade.** Appear and disappear animate `LiquidGlassSettings.visibility`,
   which scales lensing, blur and light together. Opacity is never animated. This is a
   convention in the core widgets; it needs no renderer change.

### B. Core glass widgets (`lib/core/widgets/glass/`)

These follow the package conventions: `context.skin` for colour, `AppMotion` for
timing, `Haptics` for feedback, and raw-int spacing.

| Widget | Behaviour |
|---|---|
| `GlassStyle` | Resolves `LiquidGlassSettings` from the skin and a variant. **`regular`**: default, blurred, light theme-tint. **`clear`**: more transparent, with a 35% dim layer when content behind is bright. **`prominent`**: accent-tinted, for the single primary action. Thickness, specular and shadow scale with shape size. Pure function, unit-tested. |
| `GlassScope` | One `LiquidGlassLayer` per chrome region. It never wraps top and bottom bars in one layer, because the backdrop pass covers the layer's bounding box. Rule: glass never samples glass. |
| `GlassSurface` | A shape (capsule, circle or continuous rect) rendered as `LiquidGlass.auto` with a style and a soft two-layer shadow. |
| `GlassButton` | Circle (icon) or capsule (icon plus label), 44pt minimum hit target. On press it scales **up** with a spring bounce, a glow spreads from the touch point, and a light haptic fires. Honours Reduce Motion. |
| `GlassTabBar` | Floating capsule, 62pt tall, 21pt side inset, about 22pt above the home indicator. The selection is a **droplet**: a grouped shape in the bar's blend group. At rest it is a quiet pill. On touch it lifts into lensing glass, stretches with drag velocity, and settles on a spring. Haptic select on change. |
| `GlassToolbar` | A top bar of floating circle and capsule buttons with a centred title. It replaces the flat `AppBar` look where adopted. |
| `ScrollEdgeEffect` | The soft blur-and-fade of content where it passes under a top or bottom bar. Soft style only. |
| `GlassSheetChrome` | Replaces `AppSheetChrome` for glass sheets. At partial height the sheet is inset with concentric corners and floats as glass. It becomes opaque and edge-anchored as it nears full height (about 0.9 of the screen). |

`ScrollEdgeEffect` has no ready-made primitive: Flutter has no variable-radius blur.
The first implementation task is a spike comparing two approaches on the simulator:
- a gradient-masked backdrop blur
- a small `ImageFilter.shader` vertical variable blur

The spike picks one against the native reference. The acceptance criterion is fixed
here, not the technique.

### C. Proof: native reference and glass lab

"Perfect" is judged against Apple's real glass, never from memory.

- **Native reference app.** Tiny SwiftUI app at `packages/mobile/tool/glass_reference/`,
  iOS 26. It renders a fixed scene with real `glassEffect`, `GlassEffectContainer`,
  `.buttonStyle(.glass/.glassProminent)` and a `TabView`:
  - a scrolling list of Operator-like cards in the app palette
  - a colourful image band
  - a floating tab bar
  - a top toolbar with a back circle and trailing capsule
  - a primary glass button
  - a partial-height sheet
- **Flutter glass lab.** A debug-only route in the app that renders the same scene with
  the engine.
- **Comparison loop.**
  - Both run in the same iOS 26 simulator (iPhone 16 Pro, Xcode 26.6). Screenshots are
    taken at matched scroll offsets, in light and dark, at rest and mid-press.
  - They are composed side by side into a report image.
  - Tuning iterates on `GlassStyle` and the shader until differences are not visible at
    normal viewing size.
- **Sign-off.** The user signs off on the side-by-side images. That is this project's
  acceptance gate.

### D. Tests

- Unit tests:
  - `GlassStyle` resolution (variant × theme × size → settings)
  - the size-scaling functions
  - droplet position and selection logic
  - Reduce Motion and Increase Contrast branching
- Widget tests for `GlassButton` (hit target, haptic, press state and cancel) and
  `GlassTabBar` (selection callbacks).
- Shader output is **not** covered by `flutter test`, because the test host does not run
  Impeller shaders. The simulator side-by-side is the check, and this spec says so rather
  than claiming a golden test.
- The gate is unchanged: `flutter analyze` reports no issues, and `flutter test` passes
  the full suite.

## Out of scope

- Project 2: applying glass to the real screens and the wider iOS pass (routes, titles,
  sheets, menus, controls, icons, haptics map).
- Android verification and tuning, and a Skia fallback beyond what upstream `FakeGlass`
  already does.
- Backdrop-luminance adaptivity (decision 1).
- Reduce Transparency (decision 2).
- Device-motion specular.
- Tab bar minimize-on-scroll: it belongs with the real tab screens in project 2.

## Risks

- **Performance.** Content scrolling behind static glass re-runs two backdrop passes per
  frame over each layer's bounding box. Keeping one layer per chrome region bounds this.
  The simulator does not measure GPU cost faithfully, so frame timing on a physical
  iPhone is needed before project 2 ships glass app-wide. Whether the user has a device
  for this is not known.
- **Texture memory spikes while glass animates** (flutter#138627). This hits the droplet
  and sheets. Keep animated shapes small and settle quickly.
- **Uncommitted work on `development`.** The main checkout has uncommitted edits to
  `block_card`, `session_card` and `terminal_chat_header`. This project does not touch
  those files. Project 2 will, and must rebase onto them once they land.
