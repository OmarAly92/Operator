# Flutter "Liquid Glass" (iOS 26) landscape — survey for our glass package

Research date: 2026-09-26. Scope: pub.dev + GitHub packages, Flutter framework issues, and
articles about recreating Apple's iOS 26/27 Liquid Glass in Flutter. All star/date numbers
pulled live via `gh api` / `gh search repos` on the research date.

Context assumed: we vendor a fork of `liquid_glass_renderer` (whynotmake-it) and built
`GlassSurface`/`GlassButton`/a lens-shader tab bar/toolbar/frosted header/scroll-edge
effect/bottom sheet on top, using `BackdropFilterLayer` + `ImageFilter.shader` (Impeller).

---

## 1. The renderer we already fork — what upstream did since mid-2025

**whynotmake-it/flutter_liquid_glass** — https://github.com/whynotmake-it/flutter_liquid_glass
Monorepo for `liquid_glass_renderer` (444 stars, MIT, updated 2026-09-20, latest tag
`liquid_glass_renderer-v0.2.0-dev.4`). Author: Tim Lehmann (whynotmake.it). This is the
package almost every other library in this survey either vendors, forks, or credits as the
rendering foundation (`sdegenaar/liquid_glass_widgets` explicitly forks it into
`lib/src/engine/` with an `ATTRIBUTION.md`).

Notable commits/features since mid-2025 that we should diff against our fork
(newest first, from `gh api repos/whynotmake-it/flutter_liquid_glass/commits`):

- **`feat!: glass shadows now cut out the foreground shape to support offset shadows`** (Apr
  2026) — shadow rendering was rewritten so a `GlassShadow` can be offset without the shape's
  own silhouette double-counting in the shadow. Check if our `GlassSurface` shadow still has
  the old self-intersection bug.
- **`feat: change whether glow and stretch absorb pointer events or not`** + **fix for
  `FakeGlass` with zero blur and shadow visibility** (Apr 2026) — relevant to our press-glow.
- **`feat: add shadows to LiquidGlass and FakeGlass`**, **`feat: add
  LiquidGlassLayer.existsIn(context)`**, **`feat: add .auto constructor to LiquidGlass`** that
  automatically renders onto an ancestor layer if one exists (Feb 2026) — this is a real
  ergonomics win: callers no longer have to manually decide `LiquidGlass.inLayer` vs. a fresh
  layer. Worth adopting the pattern (`existsIn` + `.auto`) if our fork predates it.
- **`feat!: use a shader for fake glass saturation (Impeller only)`** and **`feat: optimize
  clip performance in FakeGlass`** (Feb 2026) — their low-cost fallback tier moved from
  CPU/ColorFilter saturation to a tiny dedicated shader; worth comparing against our "chrome"
  variant's cheap path if we have one.
- **`feat!: use normal blend mode for glass color`** and **`fix!: fake glass didn't render
  properly on skia and had bad specular highlights`** (Nov 2025) — a real correctness fix for
  the Skia/CanvasKit fallback path (blend-mode bug), worth checking our fork picked it up.
- **`feat!: rewrote rendering pass to use two passes`** (Oct 2025) — the single biggest
  architectural change: geometry (SDF + surface normal) is cached to an offscreen texture
  first; the lighting/refraction pass only re-runs the expensive shader when geometry actually
  changes. This is what every downstream fork (sdegenaar, liquido, etc.) inherited and is
  probably the most consequential upstream change to verify our fork has — it's the
  difference between "shader runs every frame" and "shader runs only while animating."
  Companion commits: `chore: cache geometry images as well to make sure we only run the
  geometry shader when absolutely necessary`, `fix: don't create intermediate images for
  geometry until it's settled` (memory).
- **`refactor!: LiquidGlassShapes now take a simple double as radius`**, **`refactor!: move
  blend setting from LiquidGlassSettings to LiquidGlassBlendGroup`** (Oct 2025) — API
  reshuffles; if our fork is pinned pre-these, merging will be a real API migration, not a
  drop-in bump.
- A **new sibling package, `apple_liquid_glass`**, was added to the monorepo
  (`packages/apple_liquid_glass`) — currently just a documented re-export of
  `liquid_glass_renderer` ("WIP", intent to layer Apple-guideline-conformant behavior on top
  later). Nothing functional yet, but it signals upstream's own roadmap direction — worth
  watching rather than acting on.

**Assessment:** high quality, the de facto shared foundation of the ecosystem, actively
maintained (commits as recent as Apr 2026), MIT. The two-pass geometry-cache rewrite (Oct
2025) is the change most likely to matter for our performance if our vendored fork predates
it — check our fork's pinned commit/tag against `v0.1.1-dev.11` ("performance gains... too
many changes to cover one by one") through `v0.2.0-dev.4`.

---

## 2. The most sophisticated widget kit found: `liquid_glass_widgets`

**sdegenaar/liquid_glass_widgets** — https://github.com/sdegenaar/liquid_glass_widgets
676 stars (highest of any Flutter glass repo), MIT, pushed 2026-09-19, pub.dev
`liquid_glass_widgets`, current version **1.7.2** (CHANGELOG shows an **"iOS 27 material"**
already in `Unreleased` — this project is tracking Apple's *next* glass revision, not just
26). Built on a fork of `liquid_glass_renderer` (kept isolated in `lib/src/engine/`, with a
full `ATTRIBUTION.md`/`THIRD_PARTY_NOTICES` provenance trail — a good citation-hygiene example
if we ever want to show ours) plus ~100% first-party widgets (`lib/widgets/`, 60+
components). Zero third-party runtime deps beyond the vendored engine.

This is the single richest source of borrowable, documented techniques in the survey. Its
`docs/` folder is effectively an engineering blog:

- **`docs/ARCHITECTURE.md`** — clean 5-layer diagram (shaders → engine → renderer scopes →
  theme/quality/a11y → widgets). Good structure reference regardless of whether we borrow code.
- **`docs/LIQUID_MORPH_ENGINE.md`** — a **two-blob physically-modeled morph** (anchor
  shrinking away + body travelling along a J-curve with overshoot), driven by a single
  underdamped spring at **ζ ≈ 0.73** (`GlassMorphController`), exposing `MorphPhase`
  (`idle → detaching → travelling → arriving → settled`) and `MorphSpeed` presets that all
  preserve the same damping ratio. SDF metaball blend strength (`blend`, 0–28 "blur units") is
  a *derived* field of the spring state, not animated separately. Automatically drops to a
  critically-damped/instant profile under `MediaQuery.disableAnimations`.
  `lib/utils/liquid_morph_physics.dart`, `lib/utils/glass_morph_controller.dart`.
- **`docs/PROGRESSIVE_BLUR.md`** — documents (and fixes) a real Impeller pitfall: a
  `BackdropFilter` + `ShaderMask` gradient-fade **does not work** because a `ShaderMask`
  ancestor cannot see a descendant `BackdropFilter`'s captured backdrop on Impeller. The
  working fix is binding the fragment shader **as the `BackdropFilter`'s own `ImageFilter`**
  (`ui.ImageFilter.shader(...)`), with the gradient baked into the shader itself, and
  composing two single-axis separable-gaussian passes (`ImageFilter.compose(outer, inner)`)
  instead of one full 2-D blur, for O(σ) instead of O(σ²) cost. Also documents a GLES
  backdrop-y-flip bug that only affects Flutter 3.44/3.45 and is compiled out on 3.46+
  (`shaders/gles_compat.glsl`, `LGR_GLES_FLIP_SAMPLE_Y`) — a good template for how to guard a
  shader against an engine-version-specific bug without runtime branching.
  `shaders/progressive_blur.frag`, `lib/widgets/effects/progressive_blur.dart`.
- **`docs/POPOVER_BLUR_RAMP.md`** — ramps a popover's backdrop blur sigma from 0 to full over
  260 ms (its own short monotonic `AnimationController`, deliberately *not* derived from the
  morph spring, because the spring overshoots/oscillates and would make the blur "breathe").
  Ships real before/after profiling numbers (Android emulator, Impeller/GLES, profile build,
  `integration_test` + `flutter drive --profile`): worst-case raster time 58.70 ms → 28.96 ms,
  over-budget raster frames 15 → 6, across 143 sampled frames. Notably honest about
  confounds (some of the win is app-side content trimming, not just the ramp) — a good model
  for how to report a perf claim credibly rather than just asserting "faster."
- **`docs/GLASS_NAVIGATION_TRANSITION.md`** + `GlassNavigationShell` — treats nav-bar chrome as
  belonging to the **Navigator**, not the screen (mirrors `UIBarButtonItem.identifier`
  cross-route morphing): a shell hoists back-button + actions above the `Navigator`, items
  sharing an `id` across two routes hold position while the capsule width animates and
  everything else cross-fades; unmatched items are matched positionally from the anchored
  edge. `GlassBarItemBackground` (`shared`/`separate`/`none`/`own`) cleanly models Apple's two
  `UIBarButtonItem` booleans (`sharesBackground`, `hidesSharedBackground`) as one enum, with
  `own` specifically handling "this item is itself a glass surface, so dissolve it via its own
  visibility rather than fading a layer over it." This is a sophisticated pattern we likely do
  **not** have (we don't have pinned-across-route toolbar chrome per the description of our
  package) and is a strong candidate if Operator ever wants a Warp-style persistent
  back-button/actions capsule during page transitions.
- **`docs/ADAPTIVE_QUALITY.md`** + **`docs/PLATFORM_SUPPORT.md`** — `GlassAdaptiveScope`
  benchmarks the device at startup (P75 frame time of a warm-up pass) and picks
  `premium`/`standard`/`minimal` automatically (`<20ms`/`20–28ms`/`>28ms`), caches the verdict
  for the session, allows `minQuality`/`maxQuality`/`allowStepUp`. Explicitly `@experimental`
  and crowdsourcing calibration data via GitHub Discussions — refreshingly honest about
  immaturity. The three-tier `GlassQuality` ladder itself (full shader → lightweight shader →
  `BackdropFilter`-only) is the actionable idea even if the auto-benchmark thresholds aren't
  trustworthy yet.
- **`lib/widgets/shared/glass_content_aware_scope.dart`** — content-aware bar
  brightness: captures the scrolling content region **once per sample** (heavily downscaled
  async `toImage`), grids it, and has each cell cast a **WCAG-contrast vote** ("would dark
  glyphs or light glyphs read better here") rather than thresholding raw luminance — plus
  sticky-tie and **dual-threshold hysteresis** (different thresholds for light→dark vs.
  dark→light) to stop flapping on mixed content. Directly relevant to the "adaptive tint from
  sampled backdrop luminance" ask — see also `liquid_glass_easy`'s alternative implementation
  below, which is arguably more rigorous perceptually.
- **`shaders/liquid_glass_render.frag`** — the deepest shader in the whole survey (487 lines,
  up from upstream's ~62). Adds on top of the whynotmake-it base: **chromatic aberration**
  (RGB channel split on the refraction vector), **Rec. 709 saturation control**,
  **luminosity-preserving tint** ("iOS 26-style"), **meniscus edge darkening** for physical
  glass thickness, a **manual bilinear-filter workaround** for Impeller's backdrop sampler
  (which is hardwired to nearest-neighbor with no Dart-exposed way to change it — cites Flutter
  engine issues **#139887** and **#188365** directly in the shader comment), and — already —
  an **iOS 27** material path (`uRimConfig` hairline outline + rim light, `uLensModel` paraxial
  vs. spherical refraction, `uFrost` — a "cloud" read from alternating pixel rows blended with
  a weighted ghost). Also documents a real engine-version-dependent bug they had to compile
  around: Flutter PR **#177551** (merged Dec 2025, Flutter 3.41+) started forwarding
  `ClipRRect` data to the iOS PlatformView compositor mutator stack, which is why their
  `LiquidOval` approximates ovals as `BorderRadius.circular(9999)` specifically to piggyback
  on that forwarding path.
- **`lib/widgets/shared/glass_isolation_scope.dart` /
  `interaction_notification.dart`** — a zero-cost `InheritedWidget` marker that tells
  descendants whether to force their own compositing layer (`useOwnLayer: true`) vs. join the
  ancestor's blend group, specifically to prevent "Z-order tearing" where a bar's *background*
  paints behind scrolling body content but its *foreground* paints on top. Plus a
  `Notification`-based "smart silence" (`InteractionNotification`) so a child being touched can
  tell an ancestor sheet to suppress its own scale/glow reaction. Both are small, cheap,
  reusable coordination primitives worth stealing verbatim regardless of the rest of the
  library.

**Overall assessment:** by far the most mature, most honestly-documented, most actively
maintained (676 stars, commits weeks old, real perf numbers, already iterating toward iOS 27)
Flutter glass implementation found. Same shader-based approach as ours (Impeller
`BackdropFilterLayer`/`ImageFilter.shader`), same upstream ancestor
(`liquid_glass_renderer`), which makes its `lib/src/engine/ATTRIBUTION.md` diff against
upstream and its `docs/` folder the single best diffing target for our own package. Quality:
genuinely high — this is not a toy.

---

## 3. Renan Araujo's `liquido` — small, clean, and from a Flutter insider

**renancaraujo/liquido** — https://github.com/renancaraujo/liquido — 200 stars, **MPL-2.0**
(note: copyleft-ish, different from everyone else's MIT — check before borrowing code
verbatim), pushed 2026-09-05. Renan Araujo is a Flutter DevRel/GDE, so this repo is a useful
read on how someone close to the Flutter team frames the problem, even though it isn't
official framework code.

Small, focused API: a single `Glass` widget family (`Glass`, `Glass.text`, `Glass.custom`)
built on `flutter_shaders` (`ShaderBuilder`) rather than a full scene-graph renderer like
whynotmake-it's. Parameters: `blurSigma`, `contrastBoost`, `saturationBoost`,
`grainIntensity`, `brightnessCompensation`, `centerScale`/`edgeScale` (a lens-style
magnification toward center vs. edge — conceptually close to our tab bar's "minify toward the
capsule axis" lens, worth comparing formulas), `glassTint`, `refractionBorder`, `boxShadow`.
`Glass.custom` takes an explicit `mask` widget (solid-alpha only, no soft edges allowed) so any
shape can host glass, not just the built-in `ShapeBorder` set. Single shader file:
`shaders/liquido_impeller.frag`.

**Assessment:** small and clean but far less deep than `liquid_glass_widgets` — no morph
engine, no adaptive quality, no navigation-chrome pinning, no metaball blending. `grainIntensity`
(deliberate film-grain-style dither on the glass) is a parameter we don't appear to have and is
worth a look — it's a legitimate technique for hiding banding in low-alpha blur gradients.
Good as a second reference implementation of the "lens" idea, not as a component-library
source.

---

## 4. `liquid_glass_easy` — the most rigorous *adaptivity* + *blending* + *motion* math found

**AhmeedGamil/liquid_glass_easy** — https://github.com/AhmeedGamil/liquid_glass_easy — 127
stars, MIT, pushed **2026-09-26** (updated the day of this research), pub.dev
`liquid_glass_easy`. Live docs/demo site linked from the README. Positions itself as a
"lens" abstraction (`LiquidGlassLens`) rather than a widget kit, with composable building
blocks (`LiquidGlassTouch`/`Flex`, `LiquidGlassLensMotionSpec`, `LiquidGlassBlender`,
`LiquidGlassMorph`, `LiquidGlassAdaptivity`, `LiquidGlassBatch`, `LiquidGlassLite`).

Three specific things worth borrowing, in detail:

1. **`docs/ADAPTIVITY.md`** — the best-argued implementation of "adaptive tint from sampled
   backdrop luminance" in the whole survey. Pipeline: sRGB→linear via **lookup table**, then
   Rec. 709 weights (explicitly calls out that applying the weights to raw sRGB bytes, the
   common shortcut, is wrong for saturated colors) → convert linear luminance to **normalized
   CIE L\*** (because perceived lightness is non-linear in luminance — their example: mid-grey
   `#808080` is luminance 0.216 but perceptual L\* 0.53, so thresholding raw luminance at 0.5
   misclassifies almost every photograph as dark) → area-weighted mean over the registered
   region → **exponential moving average** (weight 0.65 to the newest sample) → **two
   independent thresholds** (`darkBelow`/`lightAbove`, not a center+width) for a hysteresis
   band → a verdict change additionally requires **two consecutive agreeing samples**. Three
   independent anti-flicker layers (EMA, hysteresis band, 2-sample confirmation) is more
   rigorous than `liquid_glass_widgets`' WCAG-contrast-vote approach above, though both are
   solving the same problem and worth comparing side by side. Sampling cost is bounded
   explicitly: `pixelRatio: 0.05` (a 400px-wide backdrop becomes a ~20px sample),
   `frameLimit: 8` captures/sec, and **one sampler serves every registered client in a view**
   — ten adaptive surfaces cost one capture, not ten. This "N clients share one capture" idea
   is the most generally reusable part, independent of the luminance math.
2. **`lib/assets/shaders/metaball_glass.frag`** — smooth-union (polynomial smin) blending of
   up to 6 rounded-rect shapes into one merged silhouette with a genuine liquid "neck," reusing
   the same refraction/rim/tint code as the single-lens shader via `#include`. Handles the
   Impeller-vs-Skia gradient problem explicitly and instructively: on Impeller it takes the
   merged field's gradient from hardware derivatives (`dFdx`, 1 tap); on Skia it **cannot use
   `dFdx` at all** (SkSL rejects it at compile time, not at runtime — a uniform can't route
   around it) so the same file is `#include`d a second time from a `metaball_glass_skia.frag`
   entry point with a `METABALL_SKIA` define that switches to an **analytic h-weighted blend of
   the per-lens rounded-rect gradients** instead. If our fork ever needs to blend/merge glass
   shapes (explicitly called out in the task prompt as something worth borrowing), this
   dual-entry-point pattern is the concrete template, including the "uniform arrays deprdriven
   Dart/shader index desync" packing gotcha they document and reverted (they moved from
   `vec4[6]` arrays to packed `mat4` pairs because Impeller's `setFloat` index mapping for
   uniform arrays didn't match what they expected, silently corrupting `u_smoothness`).
3. **`lib/src/widgets/utils/liquid_glass_lens_motion.dart`** — an **acceleration-driven**
   (not velocity-driven) squash/stretch: it measures acceleration over a sliding
   `sampleWindow` (default 0.3s), maps it to a signed scale deviation via `sensitivity`
   (`scaleX = 1+d, scaleY = 1-d`), clamps to `maxDeformation`, and eases toward the new value
   over `responseTime` rather than snapping every frame. Explicit design point: "force, not
   speed, is what deforms it" — constant-speed motion produces zero deformation, only
   accelerating/braking does. This is worth comparing directly against our tab bar's existing
   spring-squash — if ours keys off velocity rather than acceleration, it will squash during
   any fast constant-speed drag rather than only at the start/end of motion, which is the
   physically wrong cue.

Also has `LiquidGlassBatch` (a subtree of non-overlapping lenses sharing one backdrop read,
distinct from `LiquidGlassBlender`'s metaball fusion — trades away visual fusion for pure
scale) and `LiquidGlassLite` (a shader-free frost+tint+rim fallback, togglable per-lens or
globally per render backend) which map onto the same "batching" and "cheap fallback tier"
ideas seen elsewhere, but are worth noting as a third independent implementation of both.

**Assessment:** actively maintained (commit the day of this research), MIT, genuinely novel
math in the adaptivity and motion pieces specifically — the docs read like they were written
by someone who actually derived the physics/color-science rather than copying a recipe. Good
second source (after `liquid_glass_widgets`) to mine for algorithms, weaker on breadth of
finished components.

---

## 5. Native-platform-view approaches (real UIKit/SwiftUI glass, not a shader)

These wrap real `UITabBar`/`UIGlassEffect`/SwiftUI `.glassEffect()` behind Flutter
`PlatformView`s, so **iOS 26+ renders genuine system glass for free** — no shader, no
refraction math to get right, but tied to iOS/macOS only, PlatformView compositing overhead,
and version-gating (`if #available(iOS 26.0, *)`) with a fallback.

- **serverpod/cupertino_native** — https://github.com/serverpod/cupertino_native — 171
  stars, BSD-3-Clause, **stale since 2026-02-05** (community forks have since overtaken it:
  **gunumdogdu/cupertino_native_better**, 44 stars, updated 2026-09-02, "reliable version
  detection"; **NarekManukyan/cupertino_native_plus**, 10 stars). Wraps real
  `UITabBar`/`UISegmentedControl`/`UISwitch`/`UISlider`/button/icon/popup-menu as iOS+macOS
  platform views (`ios/Classes/Views/CupertinoTabBarPlatformView.swift` etc.), with a
  **split tab bar** feature (two independent `UITabBar`s side-by-side with a spacing gap and
  fallback proportional-width layout when content doesn't fit) that none of the shader-based
  packages attempt, because it's trivial once you have two real `UITabBar` instances but hard
  to fake with one shader surface.
- **kiddo4/real_liquid_glass** — https://github.com/kiddo4/real_liquid_glass — 5 stars, MIT,
  small and honest: exposes a `getCapabilities` method channel call returning
  `{nativeGlass: <iOS 26+ bool>, reduceTransparency, osMajorVersion}` so Dart code can decide
  whether to use the real `UITabBar` (which gets native Liquid Glass "for free" on 26+, per
  its own comment: *"On iOS 26+ UIKit supplies the Liquid Glass surface, selection lens, touch
  response, and morphing transition"*) or fall back. Good minimal reference for a
  capability-probe pattern if we ever add a platform-view escape hatch.
- **tienanh306201z/native_liquid_glass** — https://github.com/tienanh306201z/native_liquid_glass
  — 9 stars, MIT, updated 2026-09-18. By far the widest native-platform-view surface of any
  repo surveyed: 16 separate `PlatformView` factories (button, button group, tab bar, toolbar,
  navigation bar, segmented control, slider, toggle, stepper, date/color picker, menu, search
  bar + scaffold, progress/activity indicator, alert, sheet, popover). Two things worth
  studying even for a shader-based renderer:
  - **`GlassEffectSuppressor.swift`** — real UIKit glass platform views sit *above* Flutter's
    Metal-rendered surface, so anything Flutter draws on top of them (a bottom sheet, a
    dialog, a page transition) gets bled through/over incorrectly. The fix is a singleton that
    broadcasts `NotificationCenter` events (`liquidGlassSuppress`/`unsuppress`) to fade every
    glass platform view's alpha to 0 during a Flutter-side overlay, exposed to Dart via a
    `liquid-glass-lifecycle` method channel, plus a **per-widget automatic path**
    (`lib/src/utils/liquid_glass_route_suppression.dart`) keyed off
    `ModalRoute.of(context).isCurrent`. This is the actual hard problem with any
    platform-view-based glass strategy and is not something a pure-shader renderer (ours) has
    to solve — but it's the concrete reason to stay shader-based if compositing correctness
    during overlays/transitions matters, which for us (bottom sheet with detents, page
    push/pop) it clearly does.
  - **`lib/src/utils/liquid_glass_spring.dart`** — reimplements Apple's `CupertinoMotion`-style
    presets (`bouncy`/`snappy`/`smooth`/`interactive`) directly on Flutter's own
    `SpringDescription.withDurationAndBounce` + `SpringSimulation`, with a redirect-preserving
    `SingleSpringController`. Same territory as `motor`'s `CupertinoMotion` (which
    `liquid_glass_widgets` also vendors, per its `THIRD_PARTY_NOTICES`) — a third independent
    implementation of the same physics, useful as a cross-check if we want Apple-matching
    spring constants without adding the `motor` package dependency.
- **TechSupportz/native_glass_navbar** — https://github.com/TechSupportz/native_glass_navbar
  — 66 stars, MIT, updated 2026-09-21 (actively maintained), narrowly scoped to just a
  `UITabBarController`-backed tab bar (`NativeTabBar.swift`) with a `hasActionButton` /
  floating action-button-in-the-tab-bar affordance mirroring Apple's own FAB-in-tab-bar
  pattern (see also `ryanashcraft/FabBar`, a pure-SwiftUI reference for the same look, found
  during the broader GitHub search).
- **berkaycatak/adaptive_platform_ui** — https://github.com/berkaycatak/adaptive_platform_ui
  — 256 stars (second-highest in the survey), MIT, pushed 2026-09-19. Broader scope than a
  tab bar: native iOS 26 `UIToolbar`/`UITabBar` via platform views
  (`iOS26ToolbarPlatformView.swift`, `iOS26TabBarPlatformView.swift`,
  `iOS26NativeTabBarManager.swift`, `iOS26SearchTabBarController.swift`) plus a large surface
  of adaptive Material-vs-Cupertino-vs-iOS26 widgets (dialogs, checkboxes, date/time pickers,
  context menus, segmented control, slider, switch — all namespaced `ios26_*.dart` for the
  native-glass variants vs. plain `adaptive_*.dart` for the cross-platform ones). Its own
  author wrote a Medium walkthrough (see §7). The `lib/src/toolbar/` subsystem
  (`adaptive_toolbar_host.dart`, `toolbar_chrome_scope.dart`, `hosted_top_toolbar.dart`,
  `duo_vertical_bar.dart`) is conceptually close to `liquid_glass_widgets`'
  `GlassNavigationShell` (pinned chrome across route changes) but implemented via real
  platform views instead of shader glass — a second, native, reference point for the same
  "toolbar chrome survives navigation" problem if we pursue it.

**Assessment of the whole native-platform-view family:** legitimate and pixel-perfect on
device (it's the literal OS control), but out of scope as *code* to borrow for a
shader-based renderer like ours — the value here is (a) the capability-probe pattern, (b) the
suppress/unsuppress-during-overlay problem statement, and (c) proof that Apple's own
`UITabBar`/`UIToolbar` do things (split bars, FAB-in-tab-bar, cross-route pinned chrome) that
are worth matching visually even though we'd implement them with our own shader.

---

## 6. Smaller / narrower / lower-quality repos (surveyed, mostly not worth borrowing from)

- **heyarny/oc_liquid_glass** — https://github.com/heyarny/oc_liquid_glass — 35 stars, MIT,
  updated 2026-06-25. Single-shader "droplet" package (`shaders/liquid_glass.frag`), modal
  route animation support, individually colorable droplets. Reasonable quality for its scope
  (one shader, one widget family) but far narrower than the two libraries above — worth a
  glance at the droplet shader if we ever want a non-rectilinear "blob" primitive, not a
  priority read otherwise.
- **colbymaloy/flutter_liquid_glass** — https://github.com/colbymaloy/flutter_liquid_glass —
  98 stars, **no license file**, **stale since 2025-06-13** (a one-off proof-of-concept from
  the week the flutter/flutter issue thread below was opened — the author is a participant in
  that thread). One shader (`assets/shaders/glass_shader.frag`), example app only, not
  published as a package. Historical interest only.
- **xhzq233/liquid_glass_example** — https://github.com/xhzq233/liquid_glass_example — 65
  stars, MIT, **stale since 2025-06-13**. Also a same-week proof-of-concept from a participant
  in the flutter/flutter thread (see §7 — this is the person who argued the effect "is
  relatively easy" and posted a video demo); example-only, no published package. Historical
  interest only.
- **sbis04/liquid_glass_demo** — https://github.com/sbis04/liquid_glass_demo — 176 stars, MIT,
  **stale since 2025-10-11**. A polished demo app (not a reusable package — no `lib/` API,
  just an example structure) most likely built to accompany a tutorial/talk. Fine as a visual
  reference, nothing to extract as code.
- **cupertino_native forks** (`gunumdogdu/cupertino_native_better`,
  `NarekManukyan/cupertino_native_plus`) — incremental forks of serverpod's package (see §5);
  not independently novel beyond "kept the version-detection code working after Apple shipped
  further iOS 26.x point releases."
- Everything else returned by the broad `"liquid glass" flutter` GitHub search below ~10
  stars (`subash1327/liquid_glass_flutter`, `Mehrozsheikh/flutter_apple_liquid_glass`,
  `teiseong/Liquid-Glass-Bar`, `rashidkhan-dev0101/Liquid_glass`,
  `CanArslanDev/flutter_liquid_glass`, `HadesPTIT/flutter_liquid_glass`,
  `fmonclus/liquid_glass_bottom_bar`, `dru/flutter_liquid_glass`,
  `TiagoDanin/Flutter-Liquid-Glass-Example`, `osmandemiroz/liquid_glacier`,
  `David1024Smith/liquid_glass_widgets`, `santhosh-ceo/liquid_glass_ui`,
  `gauravrajkagwaniya/native_adaptive_ui`, `nugaysamil/flutter_liquid_glass_plus`) — single-digit
  to low-teens stars, single-purpose demo/tutorial repos (mostly one bottom-nav-bar widget or
  one shader file each), several are unlicensed forks/clones of the above with cosmetic
  renames. None reviewed in depth; scanned titles/descriptions only. Flagging honestly: **the
  long tail of this ecosystem is low quality** — most single-digit-star repos are tutorial
  companions, not maintained packages, and duplicate ideas already covered better above.

---

## 7. Flutter framework position + community sentiment

**flutter/flutter#170310 — "Support for iOS 26 'Liquid Glass' Design in Cupertino Widgets"**
https://github.com/flutter/flutter/issues/170310 — open, `P3`, labeled `c: proposal`,
`team-design`, `triaged-design`. Filed 2025-06-10, most recent substantive team update
2025-07-29. **Official position, stated twice by @Piinks (Flutter team):**

> "We are not developing the new Apple '26 UI design features in the Cupertino library right
> now, and we will not be accepting contributions for these updates at this time."

> "The material and cupertino libraries are being decoupled into standalone packages... All
> new work for iOS26 updates in Cupertino will happen in the new packages once established in
> flutter/packages." (tracked in the mega-issue flutter/flutter#101479, Material/Cupertino
> decoupling from core)

Practical implication for us: **there is no official/first-party Liquid Glass Cupertino
support coming from Flutter core**, and none is planned even in the medium term — the
ecosystem packages surveyed above are not "stopgaps until the framework catches up," they are
the only path, indefinitely. This validates continuing to invest in our own
`liquid_glass_renderer`-based fork rather than waiting on upstream Flutter.

The comment thread itself is a genuinely useful read (quoted sparingly per policy, summarized
here): strong pushback from several long-time contributors (`n7trd`, `orestesgaolin`,
`sunflash`, `Kypsis`) arguing Flutter should not chase every OS design trend and that Liquid
Glass specifically has real accessibility concerns (contrast/reduced-transparency); a
countervailing "the community will just fragment into competing packages, better to have one
good first-party one" line from `Hari-07`/`LucasJosefiak`; and — most concretely for us — two
participants who went on to publish the shader demos indexed in §6: `xhzq233` (posted a video
demo and the claim that the effect "is relatively easy... no need to sample more than the
background content," which `timcreatedit` (a whynotmake-it/liquid_glass_renderer maintainer)
directly refuted with a counter-example showing edge highlights *do* pick up colors from
outside the shape's own bounds — i.e., real Liquid Glass reflects surrounding content, not
just what's directly behind the shape, which matches why `liquid_glass_widgets`' shader reads
a padded/oversized backdrop region rather than exactly the shape's bounding box) and
`colbymaloy` (asked for clarification, then shipped the one-shader demo in §6).
`InvisibleRunBot` also linked a relevant ShaderToy reference implementation:
https://www.shadertoy.com/view/WftXD2.

Related/adjacent framework issues referenced in the thread (not independently investigated
here, flagged for context only): #165502 (a "blank canvas" WidgetApp proposal),
#168813 (Material 3 Expressive — same "we're not chasing this right now" answer), #101479
(Material/Cupertino decoupling from `flutter/flutter` core — the actual mechanism through
which any future first-party glass package would ship), #97496, #53059.

**Engine-level issues cited by shader authors** (found via `liquid_glass_widgets`' shader
comments, not searched independently — worth a direct look if we hit the same symptoms):
**#139887** (Impeller's backdrop-filter sampler is nearest-neighbor with no Dart-exposed way
to request bilinear — original bug report), **#188365** (feature request to expose
`FilterQuality` on `BackdropFilterLayer`, filed by the `liquid_glass_widgets` author during
their own workaround), **#177551** (merged Dec 2025, Flutter 3.41+: `ClipRRect` clip data is
now forwarded to the iOS PlatformView compositor mutator stack, which is why some libraries
approximate ovals as `BorderRadius.circular(9999)` to get free correct clipping over
PlatformViews like `webview_flutter`/`google_maps_flutter`).

---

## 8. Articles / tutorials (Medium, dev.to, blogs — not independent implementations)

Surveyed for technique novelty, not depth — all describe the same core recipe
(`BackdropFilter` + blur + saturation + a `ShaderBuilder` highlight, or wrapping
`cupertino_native`) rather than adding anything beyond what the packages above already do
better and with real code:

- Berkay Çatak (author of `adaptive_platform_ui`) — "Recreating the iOS 26 Liquid Glass UI
  with Flutter: A Complete Guide" — https://berkaypng.medium.com/recreating-the-ios-26-liquid-glass-ui-with-flutter-a-complete-guide-f6b7c505529c
  — walkthrough matching his own package's native-platform-view approach.
- "iOS 27 Liquid Glass in Flutter: Three Ways to Fake It (and the Cheapest One)" by Anilcan
  Cakir — https://medium.com/@anilcan/ios-27-liquid-glass-in-flutter-three-ways-to-fake-it-and-the-cheapest-one-b020599c9958
  — frames the same three-tier tradeoff (`BackdropFilter`-only vs. shader vs. platform view)
  that `liquid_glass_widgets`' `GlassQuality` ladder already formalizes with real code.
- "iOS 26 Liquid Glass UI in Flutter: Issues & Solutions with MaterialApp and Cupertino
  Icons" — https://medium.com/easy-flutter/ios-26-liquid-glass-ui-in-flutter-issues-solutions-with-materialapp-and-cupertino-icons-61e3aacc65d0
  — practical gotcha list (icon families, `MaterialApp` vs `CupertinoApp` theming clashes),
  useful only if we hit the exact same symptom, not a technique source.
- Santhosh Adiga U — "Creating the iOS Liquid Glass Effect in Flutter" —
  https://medium.com/design-bootcamp/creating-the-ios-liquid-glass-effect-in-flutter-75c09b3d9f2a
  — basic `BackdropFilter`/blur/tint recipe, beginner-level.
- Dimash Yerimbetov and Pranav Dave Medium posts — same beginner `BackdropFilter` recipe,
  no novel technique.
- `theflutterk.it.com` blog and `leenspace.com`/`cropsly.com`/`blog.ni18.in` posts — general
  commentary on the Flutter-vs-iOS-26 gap, restate the flutter/flutter#170310 situation, no
  code of note.

No YouTube-repo companions with meaningfully different techniques surfaced beyond what's
already indexed above; the shader-demo repos in §6 (`xhzq233`, `colbymaloy`) are themselves the
"video demo" artifacts referenced from the framework issue thread.

---

## Top techniques to adopt (ranked)

1. **Bind the blur shader as the `BackdropFilter`'s own `ImageFilter`, not behind a
   `ShaderMask`** — the only way a gradient/progressive blur reliably sees the live backdrop
   on Impeller; a `ShaderMask` ancestor cannot see a descendant `BackdropFilter`'s capture. Use
   two composed single-axis separable-gaussian passes for O(σ) cost instead of one O(σ²)
   full 2-D blur.
   Source: `docs/PROGRESSIVE_BLUR.md`, `shaders/progressive_blur.frag` —
   https://github.com/sdegenaar/liquid_glass_widgets/blob/main/docs/PROGRESSIVE_BLUR.md

2. **Ramp a popover/sheet's backdrop blur sigma from 0→full over ~250ms on its own monotonic
   controller, decoupled from the opening spring** — pays the expensive raster cost only once
   the blob has grown, not during the cheapest-to-render early frames; measured 58.7ms→29ms
   worst-case raster time on a real device profile.
   Source: `docs/POPOVER_BLUR_RAMP.md` —
   https://github.com/sdegenaar/liquid_glass_widgets/blob/main/docs/POPOVER_BLUR_RAMP.md

3. **Adaptive glass tint/content-color from sampled backdrop luminance, done perceptually**
   (sRGB→linear→CIE L\*, not raw luminance) with dual-threshold hysteresis + N-consecutive-
   sample confirmation, and one shared downsampled capture serving every registered surface in
   a view (not one capture per surface).
   Sources: `docs/ADAPTIVITY.md` —
   https://github.com/AhmeedGamil/liquid_glass_easy/blob/main/ADAPTIVITY.md ;
   compare the WCAG-contrast-vote variant in
   `lib/widgets/shared/glass_content_aware_scope.dart` —
   https://github.com/sdegenaar/liquid_glass_widgets/blob/main/lib/widgets/shared/glass_content_aware_scope.dart

4. **Physically-modeled two-blob morph** (anchor shrinks away + body travels a J-curve with
   overshoot, one underdamped spring at ζ≈0.73 drives both position and SDF blend strength as
   one derived state) with an explicit `MorphPhase` state machine and a reduced-motion
   override to a critically-damped/instant profile.
   Source: `docs/LIQUID_MORPH_ENGINE.md` —
   https://github.com/sdegenaar/liquid_glass_widgets/blob/main/docs/LIQUID_MORPH_ENGINE.md

5. **Acceleration-driven (not velocity-driven) squash/stretch** for moving glass bodies —
   deforms only while a mover is speeding up or braking, not during constant-speed travel,
   via a sliding-window acceleration estimate, clamp, and an eased response time. Worth
   diffing against our tab bar's existing squash spring to check which cue it actually keys
   off of.
   Source: `lib/src/widgets/utils/liquid_glass_lens_motion.dart` —
   https://github.com/AhmeedGamil/liquid_glass_easy/blob/main/lib/src/widgets/utils/liquid_glass_lens_motion.dart

6. **SDF metaball smooth-union for merging multiple glass shapes**, with a documented
   backend split: hardware-derivative (`dFdx`) gradient on Impeller vs. an analytic h-weighted
   blend of per-shape gradients on Skia (because `dFdx` does not compile in SkSL at all, not
   just underperform) — plus the packing gotcha that uniform *arrays* desync Impeller's
   `setFloat` indexing, worth using packed `mat4`s instead.
   Source: `lib/assets/shaders/metaball_glass.frag` —
   https://github.com/AhmeedGamil/liquid_glass_easy/blob/main/lib/assets/shaders/metaball_glass.frag ;
   compare `LiquidGlassBlendGroup`'s two-pass geometry/render split at
   https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer/lib/src

7. **Verify our vendored `liquid_glass_renderer` fork against upstream's two-pass geometry-cache
   rewrite** (Oct 2025: cache SDF/normal geometry to a texture once, only re-run the expensive
   lighting/refraction shader while geometry is actually animating) — this is upstream's single
   biggest perf change since mid-2025 and the change every serious downstream fork inherited.
   Source: commit history —
   https://github.com/whynotmake-it/flutter_liquid_glass/commits/main/packages/liquid_glass_renderer

8. **Pinned cross-route navigation chrome**: bar back-button + actions belong to the
   `Navigator`, not the screen; items sharing an `id` across routes hold position while a
   shared capsule morphs width and unmatched items cross-fade, matched positionally from the
   anchored edge when no `id` is given — mirrors `UIBarButtonItem.identifier`/
   `sharesBackground`/`hidesSharedBackground` as one clean `GlassBarItemBackground` enum
   (`shared`/`separate`/`none`/`own`).
   Source: `docs/GLASS_NAVIGATION_TRANSITION.md` —
   https://github.com/sdegenaar/liquid_glass_widgets/blob/main/docs/GLASS_NAVIGATION_TRANSITION.md

9. **Device-tier adaptive quality ladder** (full shader → lightweight shader →
   `BackdropFilter`-only), auto-selected from an on-device P75 warm-up frame-time benchmark,
   cached per session, with explicit `minQuality`/`maxQuality` clamps — treat the auto-benchmark
   thresholds as unproven (the authors say so themselves) but the three-tier ladder and the
   isolation-scope mechanism that lets a bar force `premium` regardless of the app-wide default
   are worth adopting outright.
   Source: `docs/ADAPTIVE_QUALITY.md`, `docs/PLATFORM_SUPPORT.md`,
   `lib/widgets/shared/glass_isolation_scope.dart` —
   https://github.com/sdegenaar/liquid_glass_widgets/blob/main/docs/ADAPTIVE_QUALITY.md

10. **Manual bilinear-filter workaround for Impeller's backdrop sampler** — Impeller's
    implicit `BackdropFilterLayer` sampler is hardwired nearest-neighbor with no Dart-exposed
    way to request bilinear (Flutter engine issues #139887, #188365); if we see aliasing on
    continuous zoom/scale of a glass surface's backdrop sample, this shader-side workaround is
    a direct fix, not a Flutter-version wait.
    Source: `shaders/liquid_glass_render.frag` (search "Manual Bilinear Filtering") —
    https://github.com/sdegenaar/liquid_glass_widgets/blob/main/shaders/liquid_glass_render.frag

11. **Native-platform-view glass-suppression pattern**, for reference only (not directly
    applicable to a pure-shader renderer): a `NotificationCenter` broadcast that fades every
    UIKit glass `PlatformView` to alpha 0 during Flutter-side overlay presentation
    (dialogs/sheets/page transitions), plus an automatic per-widget path keyed off
    `ModalRoute.isCurrent`. Useful if we ever add a native-platform-view escape hatch alongside
    our shader surfaces and need the two to coexist correctly during transitions.
    Source: `GlassEffectSuppressor.swift`, `liquid_glass_route_suppression.dart` —
    https://github.com/tienanh306201z/native_liquid_glass/blob/main/ios/native_liquid_glass/Sources/native_liquid_glass/GlassEffectSuppressor.swift

12. **`grainIntensity` — deliberate dither on the glass surface** to hide banding in low-alpha
    blur gradients, as an explicit tunable parameter rather than an afterthought.
    Source: `lib/src/glass_options.dart` / `lib/src/glass.dart` —
    https://github.com/renancaraujo/liquido/blob/main/lib/src/glass.dart
