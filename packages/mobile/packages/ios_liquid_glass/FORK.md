# Why this package is vendored

Vendored from `liquid_glass_renderer` at upstream commit `ad3bcff` (2026-04-24), not the
last pub.dev release `0.2.0-dev.4` (2025-11-13). `main` carries five months of unreleased
work the app needs: `shadows` on `LiquidGlass`/`FakeGlass`, `LiquidGlass.auto`,
`LiquidGlassLayer.existsIn`, the Impeller saturation shader for `FakeGlass`, and fixes to
`FakeGlass` rendering on Skia.

It is the renderer behind the iOS-style glass chrome (tab bar, navigation bars, composer,
sheets). It is vendored rather than depended on so the app can tune the shaders and the
fallback path to its own design, and so an experimental pre-release cannot change under it.

`lib/`, `test/`, `LICENSE`, `README.md` and `CHANGELOG.md` are kept. Upstream's `example/`,
`doc/` GIFs and `coverage/` are dropped; README image links therefore do not resolve.

Changes from upstream:

- `pubspec.yaml`: workspace resolution, `publish_to: none`, a `flutter_test` dev
  dependency kept for `test/`.
- Thickness is uploaded × devicePixelRatio to both the geometry and the final render pass,
  so `LiquidGlassSettings.thickness` is in logical points. Upstream left it in physical
  pixels, making the lens band a third as wide on a 3x screen. A DPR change re-uploads it.
  Blend was already uploaded × devicePixelRatio upstream (`liquid_glass_blend_group.dart`,
  `updateShaderWithSettings`); no change needed there.

- `sdfSquircle` in `sdf.glsl` is a p-norm continuous corner (`SQUIRCLE_EXPONENT`,
  `SQUIRCLE_EXTENT`) fitted to Flutter's `RoundedSuperellipseBorder`. Upstream used the
  rounded-rectangle formula, so the lens and the clip disagreed at the corners.

- `LiquidGlassSettings.fillRatio` (default 0.8, upstream's hard-coded value) sets how
  strongly the side facing away from the light is lit. The rim brightness is clamped to
  [0, 1]. The app sets 0.7 after measuring a near-uniform native rim.

- `GlassDragBuilder` handles `onPointerCancel` in listener mode; upstream left a cancelled
  touch stuck pressed.
- `GlassGlow` fades out where the finger lifted; upstream slid the glow to the top-left
  corner on release.
- Removed `Glassify` (`experimental.dart`), the unused `LiquidGlassFilter`, and their
  shaders `liquid_glass_filter.frag` and `liquid_glass_arbitrary.frag`. The app uses
  neither, and both failed SkSL compilation on every build.
- Removed `lib/assets/shaders/shared.glsl`, unused once `Glassify` was removed.
- Removed the public `ShaderKeys` fields `legacyLiquidGlass`, `liquidGlassFilterShader`
  and `glassify`, which only `Glassify` referenced.

Record every later change to `lib/` in this file.

Upstream: https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer
