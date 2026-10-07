# Why this package is vendored

Vendored from `liquid_glass_renderer` at upstream commit `ad3bcff` (2026-04-24), not the
last pub.dev release `0.2.0-dev.4` (2025-11-13). `main` carries five months of unreleased
work the app needs: `shadows` on `LiquidGlass`/`FakeGlass`, `LiquidGlass.auto`,
`LiquidGlassLayer.existsIn`, the Impeller saturation shader for `FakeGlass`, and fixes to
`FakeGlass` rendering on Skia.

It is the renderer behind the iOS-style glass chrome (tab bar, navigation bars, composer,
sheets). It is vendored rather than depended on so the app can tune the shaders and the
fallback path to its own design, and so an experimental pre-release cannot change under it.

`lib/`, `test/`, `LICENSE` and `CHANGELOG.md` are kept. Upstream's `doc/` GIFs and `coverage/`
are dropped. Upstream's `README.md` and `example/` were replaced in 2A by this package's own
README and example app.

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

- `LiquidGlassSettings.fillRatio` is kept as upstream's public API (default 0.8), but the
  iOS 27 final pass does not read it; `GlassStyle`, which used to set it, was deleted with
  the rest of Operator's old glass API.

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


## ios_liquid_glass 0.1.0 (project 2A)

The package was renamed from `liquid_glass_renderer` to `ios_liquid_glass`, with library `package:ios_liquid_glass/ios_liquid_glass.dart` and shader root `packages/ios_liquid_glass/`. Its goal changed from a vendored renderer to an iOS 27 Liquid Glass package for any Flutter app. Changes to upstream's code:

- `liquid_glass_final_render.frag` is rewritten as the iOS 27 model:
  - rim-only dispersion;
  - a three-point tone curve on luminance with chroma saturation;
  - a tint brightness range;
  - an adaptive hairline;
  - a two-lobe specular in the rim band.
- Upstream's rim lighting (`render.glsl`, `lightIntensity`, `ambientStrength`, `fillRatio` in the shader) is gone. `render.glsl` is deleted. The geometry pass is unchanged.
- `LiquidGlassSettings` gains `toneBlack`, `toneMid`, `toneWhite`, `tintBlack`, `tintWhite`, `hairline`, `hairlineWidth`, `hairlineDark`, `hairlineLight`, `specular`, `specularWidth`, `specularPower` and `specularFill`, with `effective*` getters where visibility applies. The old fields stay for `FakeGlass`.
- `LiquidGlassRenderObject._updateShaderSettings` packs the new uniforms into `vec4`s from index 6.
- `LiquidGlassSettings` and `LiquidShape` use `with Equatable` instead of the deprecated `EquatableMixin`. The library file declares `library;`.
- `GlassMaterial.resolve` keeps a tinted glass's `tintAmount`, `tintBlack` and `tintWhite` from the tinted row, at the same appearance and anchors, when Reduce Transparency or Increase Contrast picks the accessibility row for the rest of the material. The accessibility rows are tuned on their own for tone, frost and edge light, share only the lens and shadow fields with the regular rows, and carry a `tintAmount` of 0. Since 2A.1 this applies only to regular glass: `Glass.clear.tint(c)` stays untinted.
- `GlassEffect` and `GlassEffectContainer` share one internal resolve helper, `resolveGlassMaterial` in `lib/src/api/glass_material_context.dart`, instead of each repeating the same `GlassMaterial.resolve` call; each widget still calls `toSettings()` itself.
- New, not from upstream:
  - `lib/src/api/` (`Glass`, `GlassShape`, `GlassTheme`, `GlassEffect`, `GlassEffectScope`, `GlassEffectContainer`, `GlassDimming`, `GlassForeground`, `glass_material_context.dart`);
  - `lib/src/material/` (`GlassMaterial`, `ios27Table`, `ScrollEdgeMaterial`, `ios27ScrollEdgeTable`, `GlassMaterialOverride`);
  - `lib/src/accessibility/`;
  - `lib/src/scroll_edge/` and `scroll_edge_blur.frag`, moved from Operator;
  - the iOS plugin in `ios/`;
  - the `example/` app.

## ios_liquid_glass 0.1.0, project 2A.1 fix round

- The geometry pass (`liquid_glass_geometry_blended.frag`) writes the signed distance to the silhouette, normalised by the larger of the thickness and the outline band plus one pixel (`signedDistanceReach`, used by both passes, so glass thinner than its band still decodes a fully covered interior and an outline only outside it), into the blue channel instead of the bevel height, uses alpha as an inside-the-shape-or-outline-band flag, and covers a band `outlineWidth` + 1 px outside every shape. Its second uniform float carries that band in physical pixels. `encodeGeometry`, `signedDistanceReach` and `decodeSignedDistance` in `displacement_encoding.glsl` replace the old encoding.
- The geometry bounds grow by `outlineWidth` + 1 pt so the band is inside the texture and the shader layer's clip; a change of `outlineWidth` rebuilds the geometry.
- Geometry pictures and images are sized with `toPixelCount()` (rounding) instead of `ceil()`. The extents are already snapped to pixels, and `ceil` turned a floating-point 760.0000000000001 into 761, which sampled the geometry one pixel off at the right and bottom of glass at fractional positions.
- `liquid_glass_final_render.frag`: coverage is a one-pixel ramp at the silhouette (upstream faded the last two pixels); a dark outline is drawn outside the silhouette with a strength that follows the normal (`outline` at the ends, `outlineTop` at the top and bottom); inside, an exponential line (`specular`, `specularWidth`) and sheen (`sheen`, `sheenWidth`) are weighted by the two light lobes and fade out over the last 30% of the bevel. The adaptive inner hairline is gone.
- `LiquidGlassSettings` loses `hairline`, `hairlineWidth`, `hairlineDark`, `hairlineLight` and `effectiveHairline`, and gains `outline`, `outlineTop`, `outlineWidth`, `sheen` and `sheenWidth` with their `effective*` getters.
- `GlassShadow` cuts an offset shadow out of the glass with a difference clip instead of a `saveLayer` and a `dstOut` shape, and sizes the clip to three sigma of the blur (upstream's layer bounds stopped the tail at one blur radius).
- `scroll_edge_blur.frag` is replaced by `scroll_edge_mask.frag`. `ScrollEdgeEffect` stacks real Gaussians (`ImageFilter.compose` of a blur and the mask shader) and paints the dim, cap and divider line itself.
- `GlassMaterialOverride` takes an optional `side`; `resolveGlassMaterial` applies overrides only to glass at that size anchor.

## ios_liquid_glass 0.1.0, project 2B.1 (motion)

- `LiquidGlassLayer` takes optional internal `visibility` (an animation) and `settingsSource` (a `GlassMaterialSource`) parameters, carried by `LiquidGlassRenderScope`. `RenderLiquidGlassLayer`, `RenderLiquidGlassBlendGroup` (through `RenderLiquidGlassGeometry`) and the glass shadow listen to them: the source replaces the layer's settings, and the visibility is multiplied into `LiquidGlassSettings.visibility` (held at 0 below, not capped above) with the blur ramped as visibility to `ios27BlurRampExponent` (`LiquidGlassSettings.atVisibility`, new public API, which the lab's `tool.visibility` scene uses too); the content fades through a `FadeTransition` on it. Without them the layer draws exactly what it drew before.
- `RenderLiquidGlass` takes an optional internal `GlassShapeMotion`. The blend group gathers the shape's drawn rect from it instead of its layout rect, `getPath()` follows it, and the content is painted translated by the drawn rect's centre offset; layout and hit testing are unchanged. `LiquidGlass.grouped` and `LiquidGlass.withOwnLayer` gain internal `motion`, `visibility`, `settingsSource` and `shadowSource` parameters; the glass shadow reads its shadows from `shadowSource` when given.
- `liquid_glass_final_render.frag` reads the material's full thickness from `uOptics.w`: the signed distance is decoded with the full-thickness reach, the dispersion bevel keeps the ramped thickness, and the edge line and sheen take their width from the full thickness. `liquid_glass_geometry_blended.frag` gains `uFullThickness` (float 103) and encodes the signed distance with the same reach. At visibility 1 both are the ramped thickness, so still glass is unchanged byte for byte.
- `GlassMaterialOverride` gains `scopeOf` and `valuesFor`, and `glassMaterialResolver` builds a pure function of the side from a context, so a glass can re-resolve its material without one.
- New, not from upstream: `lib/src/motion/` (`GlassAnimation`, `withGlassAnimation`, `GlassAnimationScope`, the springs, the frame counter, the material source, the motion coordinator, members, ghosts, the `Overlay` ghost host and their widgets, the materialize mapping, the fitted `ios27_motion.dart` table), `lib/src/api/glass_effect_transition.dart`; `GlassEffectContainer` becomes stateful and owns the coordinator; `GlassEffect` joins it (or a private one), keeps its content in a snapshot boundary, takes a `transition`, and no longer measures itself with a post-frame `setState`.
- A rendered geometry cache (`RenderedGeometryCache`) keeps its picture and rasterizes its image at the sub-pixel phase it is drawn at (`matteAt`); `LiquidGlassRenderObject` draws a cached matte under a pure translation on the pixel grid at that phase (`drawMatteAt`), so glass at a fractional position draws its rim where the uncached picture does. Upstream drew the image rasterized on its own grid with nearest sampling at the fractional offset, up to half a pixel off. Other transforms draw the phase-zero image as before.
- `requiresGeometryRebuild(null)` is true, and `RenderLiquidGlassGeometry.attach` and `LiquidGlassRenderObject.attach` re-apply the settings against the kept baseline (refreshing the uniforms) instead of clearing it.

## ios_liquid_glass 0.1.0, project 2B.2 (merge and split)

- `sdf.glsl` replaces upstream's quadratic `smoothUnion` with `angleSmoothUnion`, a quadratic smooth-min with k = blend whose correction is weighted by (1 − n_a · n_b) / 2, the angle between the two shapes' unit gradients. Each shape's gradient is analytic (`getShapeSDFGrad`); the fold carries the blended field's gradient, neglecting the change of the angle weight itself. A blend of 0 is still the plain minimum. `sceneSDF`'s unrolled path for one to four shapes is gone; every count runs the same loop.
- `LiquidGlassBlendGroup` takes an optional internal `blendMotion` (a `ValueListenable<double>`); `RenderLiquidGlassBlendGroup` listens to it and takes its value as `blend`, so a container's spacing animates with no rebuild. Its own `blend` default stays 20.
- `GlassEffectContainer.spacing` defaults to 8 pt, native's default, and animates through the container's coordinator.

Record every later change to `lib/` in this file.

Upstream: https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer
