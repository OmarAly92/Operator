# ios_liquid_glass

iOS 27 Liquid Glass for Flutter, measured against native.

Every look parameter in this package comes from an automatic search against screenshots of native SwiftUI glass on the iOS 27 simulator. The numbers ship as a table, `ios27Table`. The measuring instrument, a native catalog, a touch driver and a comparison harness, lives in the repository that develops this package (`tool/glass_lab/`).

Requires Impeller (iOS, or Android with Impeller). The accessibility bridge is iOS only; on other platforms the package falls back to `MediaQuery`.

## Use

```dart
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

GlassEffect(
  child: Padding(
    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: GlassForeground(child: Text('Glass')),
  ),
)
```

The glass is drawn behind the child, in the shape you choose, sized by the child. Put it over content: glass shows what is behind it.

### SwiftUI names

| SwiftUI | ios_liquid_glass |
|---|---|
| `.glassEffect()` | `GlassEffect(child: ...)` |
| `.glassEffect(.clear)` | `GlassEffect(glass: Glass.clear, ...)` |
| `.glassEffect(.regular.tint(.green))` | `GlassEffect(glass: Glass.regular.tint(green), ...)` |
| `.glassEffect(.identity)` | `GlassEffect(glass: Glass.identity, ...)` |
| `.glassEffect(.regular.interactive())` | `Glass.regular.interactive()` (motion arrives in a later version) |
| `.glassEffect(in: .circle)`, `.rect(cornerRadius:)`, capsule | `GlassShape.circle()`, `GlassShape.rect(r)`, `GlassShape.superellipse(r)`, `GlassShape.capsule()` |
| `GlassEffectContainer(spacing:)` | `GlassEffectContainer(spacing: 20, child: ...)` |
| `.scrollEdgeEffectStyle(.soft / .hard / .automatic)` | `ScrollUnderBars(style: ScrollEdgeStyle.soft, child: ...)` or `ScrollEdgeEffect(...)` |
| the 35% dimming layer under clear glass | `GlassDimming(child: ...)` |

### Theme

`GlassTheme` is optional. Without it, glass follows the platform brightness.

```dart
GlassTheme(
  data: GlassThemeData(
    brightness: Brightness.dark,
    accent: Color(0xFF1ACB64),
    scrollEdgeTint: Color(0xFF000000),
  ),
  child: app,
)
```

- `accent` is what `Glass.regular.tint(GlassTheme.of(context).accent)` uses.
- `scrollEdgeTint` colours the scroll edge effect. By default it is black in dark mode and white in light mode.
- `GlassForeground` gives labels and symbols on glass their native colour: white in dark mode, black in light mode, and white on tinted glass.

### Accessibility

Reduce Transparency, Increase Contrast and Reduce Motion are read live. On iOS a small plugin reports Reduce Transparency, which Flutter's `MediaQuery` does not expose. Glass switches to its tuned `reduceTransparency` or `increaseContrast` material without a restart. `GlassAccessibility.of(context)` returns the current values.

### Size

Native glass gets thicker and deeper as it grows. `GlassEffect` measures itself and interpolates the material between the 44, 88 and 200 pt anchors on its shorter side. Pass `sideHint` to avoid a one-frame default before the first layout.

Inside a `GlassEffectContainer`, every grouped child shares the container's single glass layer, so the material is resolved once from the container's own `side` (default 88) — not from each child's measured size.

### Clear glass has no tint

`Glass.clear.tint(color)` still renders untinted: the tuned `clear` row's `tintAmount` is 0, and picking the `clear` row does not depend on `tintColor`. Use `Glass.regular.tint(color)` for tinted glass.

### Low level

The renderer underneath is still public: `LiquidGlass`, `LiquidGlassLayer`, `LiquidGlassSettings`, `LiquidGlassBlendGroup`, `FakeGlass`, `GlassGlow` and `LiquidStretch`. `GlassMaterial.resolve(...)` returns the tuned material for any glass, size, appearance and accessibility state, and `toSettings()` turns it into `LiquidGlassSettings`.

## How the look is made

- The geometry pass computes a signed-distance field of every shape in a layer, blends nearby shapes, and bakes a quarter-circle bevel with Snell refraction into a cached texture.
- The final pass refracts the frosted backdrop through that texture, with dispersion at the rim only. It then maps brightness through a three-point tone curve (black, mid, white), tints with the accent across a brightness range, and draws an adaptive hairline and a two-lobe specular rim.

The new final pass costs the same as upstream's, at upstream's default settings (`const LiquidGlassSettings()`: default blur, identity tone curve, no hairline or specular). Measured on the iOS 27 simulator, 13 own-layer glasses over a moving backdrop: 12.10 ms median raster time per frame for the old renderer against 12.48 ms and 12.24 ms for the new one, in two separate takes. The cost of the tuned iOS 27 materials — frost as high as 72 under Reduce Transparency — is not yet measured. Check your target devices.

## Credits and licence

This package is a fork of [`liquid_glass_renderer`](https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer) by Tim Lehmann ([whynotmake.it](https://whynotmake.it)), MIT licensed. The renderer's geometry pass, blend groups, caching, `FakeGlass`, `GlassGlow` and `LiquidStretch` are his work. `FORK.md` lists every change made since, and `LICENSE` is upstream's MIT licence.
