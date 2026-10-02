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

Native glass changes with its size: a 200 pt glass casts a long soft shadow (sigma about 17 pt) where a 44 pt one casts almost none, and its tone and frost differ too. `GlassEffect` measures itself and interpolates the tuned material between the 44, 88 and 200 pt anchors on its shorter side. Pass `sideHint` to avoid a one-frame default before the first layout.

Inside a `GlassEffectContainer`, every grouped child shares the container's single glass layer, so the layer's settings (tone, frost, edge light) are resolved once from the container's own `side` (default 88). Each child's shadow still comes from its own measured size.

### Clear glass has no tint

`Glass.clear.tint(color)` still renders untinted, with or without Reduce Transparency and Increase Contrast, and its foreground is the plain one. Use `Glass.regular.tint(color)` for tinted glass.

### Low level

The renderer underneath is still public: `LiquidGlass`, `LiquidGlassLayer`, `LiquidGlassSettings`, `LiquidGlassBlendGroup`, `FakeGlass`, `GlassGlow` and `LiquidStretch`. `GlassMaterial.resolve(...)` returns the tuned material for any glass, size, appearance and accessibility state, and `toSettings()` turns it into `LiquidGlassSettings`.

## How the look is made

- The geometry pass computes a signed-distance field of every shape in a layer, blends nearby shapes, and bakes a quarter-circle bevel with Snell refraction and the distance to the silhouette into a cached texture. It also covers a thin band just outside each shape.
- The final pass refracts the frosted backdrop through that texture, with dispersion at the rim only. It maps brightness through a three-point tone curve (black, mid, white) and tints with the accent across a brightness range. Then it draws the iOS 27 edge measured on the simulator: a crisp silhouette, a dark outline just outside it that is strongest at the curved ends, and a bright line and a soft sheen along the top and bottom, lit by two lobes of a vertical light.
- The shadow is one Gaussian per glass, offset downward, fitted to native's.
- The scroll edge effect stacks real Gaussian blurs, masked by a small shader, under a tinted gradient.

Frame cost, measured on the iOS 27 simulator with 13 glasses over a moving backdrop (debug build, raster median): 12.66 ms with the tuned material through `GlassEffect`, against 12.10 ms for this fork's renderer before 2A (the `liquid_glass_renderer` copy on Operator's `development` branch) at its defaults (+4.6%); a soft scroll edge adds 4.98 ms. Check your target devices.

## Credits and licence

This package is a fork of [`liquid_glass_renderer`](https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer) by Tim Lehmann ([whynotmake.it](https://whynotmake.it)), MIT licensed. The renderer's geometry pass, blend groups, caching, `FakeGlass`, `GlassGlow` and `LiquidStretch` are his work. `FORK.md` lists every change made since, and `LICENSE` is upstream's MIT licence.
