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
| `.glassEffect(.regular.interactive())` | `Glass.regular.interactive()` (the press arrives in a later version) |
| `.glassEffect(in: .circle)`, `.rect(cornerRadius:)`, capsule | `GlassShape.circle()`, `GlassShape.rect(r)`, `GlassShape.superellipse(r)`, `GlassShape.capsule()` |
| `GlassEffectContainer(spacing:)` | `GlassEffectContainer(spacing: 20, child: ...)` |
| `.glassEffectTransition(.materialize)`, `.identity` | `GlassEffect(transition: GlassEffectTransition.materialize)`, `GlassEffectTransition.identity` |
| `Animation.default`, `.snappy`, `.bouncy`, `.smooth` | `GlassAnimation.defaultSpring`, `.snappy`, `.bouncy`, `.smooth` |
| `.spring(duration:bounce:)`, `.spring(response:dampingFraction:)` | `GlassAnimation.spring(duration:, bounce:)`, `GlassAnimation.dampedSpring(response:, dampingFraction:)` |
| `withAnimation(.bouncy) { ... }` | `withGlassAnimation(GlassAnimation.bouncy, () => setState(...))` |
| (no equivalent) | `GlassAnimationScope(animation: ..., child: ...)`, a default for a subtree; `GlassAnimation.none` turns animation off |
| `.scrollEdgeEffectStyle(.soft / .hard / .automatic)` | `ScrollUnderBars(style: ScrollEdgeStyle.soft, child: ...)` or `ScrollEdgeEffect(...)` |
| the 35% dimming layer under clear glass | `GlassDimming(child: ...)` |

### Motion

Glass materializes when it appears and dematerializes when it is removed, as native glass does: the lens, frost, tone and edge light ramp in and out while the content fades, rather than the whole glass fading. A removed glass keeps drawing, with a snapshot of its content, until it has gone. Glass that moves or changes size springs from where it was drawn to where it is laid out; its content follows it, and taps go to the new layout at once.

```dart
GlassEffectContainer(
  child: shown ? GlassEffect(child: label) : const SizedBox.shrink(),
)

withGlassAnimation(GlassAnimation.snappy, () => setState(() => shown = !shown));
```

Changes animate by default with `GlassAnimation.defaultSpring`. `withGlassAnimation` applies its animation to every glass change built in the next frame, including one an unrelated `setState` causes in that frame, as a SwiftUI transaction does; otherwise the nearest `GlassAnimationScope` applies; otherwise the default. `GlassAnimation.none` and `GlassEffectTransition.identity` change at once. The presets are SwiftUI's springs: `defaultSpring` 0.55 s, `smooth` 0.5 s, `snappy` 0.5 s with bounce 0.15, `bouncy` 0.5 s with bounce 0.3.

What animates:
- **Insertion and removal.** A glass materializes when it is built into a layout that already existed (`if (shown) GlassEffect(...)` inside a container, a `Row` or a `SizedBox`), or inside `withGlassAnimation`. Glass built together with its parent (a page, a tab, a new subtree, a list item scrolled into view) appears at once, as does `if (shown) Padding(child: GlassEffect(...))` outside `withGlassAnimation`. Removal mirrors it: a glass removed on its own dematerializes; one that leaves with its parent or its page goes at once.
- **Moves and resizes.** A single layout change animates when the glass widget was rebuilt, when its container gained or lost a glass, or inside `withGlassAnimation`. A glass whose layout changes on consecutive frames (frames drawn one after the other, at most 50 ms apart) is moved by the app, by a drag, its own animation or the keyboard, and follows its layout exactly: its first changed frame is taken as a single change and holds the glass where it was, and from the second it sits on its layout, covering both frames' movement in one step. It animates again after a frame without a change. Inside `withGlassAnimation` changes animate even on consecutive frames. The cost: two separate changes on back-to-back frames are taken as motion, so the second lands at once and drops the first one's spring. Scrolling never animates: glass in a scroll view moves with the content in the same frame. A `const` glass whose parent changed jumps unless the change is inside `withGlassAnimation`. A container that re-centres in its parent (a centred `Row` that gains an item) animates its glass; anything that moves the container's parent moves the glass at once.
- **Glass outside a container** transitions too. Its ghost is drawn in the nearest `Overlay`, above that overlay's routes; without an `Overlay` (no `MaterialApp`, `CupertinoApp` or `WidgetsApp` above it) it appears and disappears at once.

The timing is native's, measured on the iOS 27 simulator. Appearing glass follows the animation's spring and overshoots where the spring does, scaled by a fitted gain (0 for `snappy`, 0.36 for `bouncy`; the default spring does not overshoot, so it needs none); disappearing glass follows the spring's remainder to a fitted power (3.1 for the default, 2.65 for `snappy`, 2.8 for `bouncy`), which is why removal is about twice as fast as insertion. An app's own spring uses the preset nearest its damping. The backdrop blur ramps as visibility to the power 3. The numbers ship as a table, `ios27_motion.dart`, written by the lab. Under Reduce Motion native keeps materialize's timing and blur and overshoots more, so glass that begins to appear under Reduce Motion takes a second fitted gain (0.62 for `bouncy`).

Each glass resolves its material (tone, frost, edge light and shadow) from its drawn size at layout and on every animated frame, so a glass growing from 44 to 200 pt changes its shadow as it grows. Container spacing does not animate yet.

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

Native glass changes with its size: a 200 pt glass casts a long soft shadow (sigma about 17 pt) where a 44 pt one casts almost none, and its tone and frost differ too. `GlassEffect` resolves the tuned material from its drawn size, interpolated between the 44, 88 and 200 pt anchors on its shorter side, at its first layout and whenever it changes size; no frame is painted with a guess. `sideHint` is the size its first build uses before that layout.

Inside a `GlassEffectContainer`, every grouped child shares the container's single glass layer, so the layer's settings (tone, frost, edge light) are resolved once from the container's own `side` (default 88). Each child's shadow still comes from its own measured size.

### Clear glass has no tint

`Glass.clear.tint(color)` still renders untinted, with or without Reduce Transparency and Increase Contrast, and its foreground is the plain one. Use `Glass.regular.tint(color)` for tinted glass.

### Low level

The renderer underneath is still public: `LiquidGlass`, `LiquidGlassLayer`, `LiquidGlassSettings`, `LiquidGlassBlendGroup`, `FakeGlass`, `GlassGlow` and `LiquidStretch`. `LiquidGlassSettings.atVisibility(v)` gives the settings glass draws with at materialize visibility `v`. `GlassMaterial.resolve(...)` returns the tuned material for any glass, size, appearance and accessibility state, and `toSettings()` turns it into `LiquidGlassSettings`.

## How the look is made

- The geometry pass computes a signed-distance field of every shape in a layer, blends nearby shapes, and bakes a quarter-circle bevel with Snell refraction and the distance to the silhouette into a cached texture. It also covers a thin band just outside each shape.
- The final pass refracts the frosted backdrop through that texture, with dispersion at the rim only. It maps brightness through a three-point tone curve (black, mid, white) and tints with the accent across a brightness range. Then it draws the iOS 27 edge measured on the simulator: a crisp silhouette, a dark outline just outside it that is strongest at the curved ends, and a bright line and a soft sheen along the top and bottom, lit by two lobes of a vertical light.
- The shadow is one Gaussian per glass, offset downward, fitted to native's.
- The scroll edge effect stacks real Gaussian blurs, masked by a small shader, under a tinted gradient.

Frame cost, measured on the iOS 27 simulator with 13 glasses over a moving backdrop (debug build, raster median): 12.66 ms with the tuned material through `GlassEffect`, against 12.10 ms for this fork's renderer before 2A (the `liquid_glass_renderer` copy on Operator's `development` branch) at its defaults (+4.6%); a soft scroll edge adds 4.98 ms. Check your target devices.

## Credits and licence

This package is a fork of [`liquid_glass_renderer`](https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer) by Tim Lehmann ([whynotmake.it](https://whynotmake.it)), MIT licensed. The renderer's geometry pass, blend groups, caching, `FakeGlass`, `GlassGlow` and `LiquidStretch` are his work. `FORK.md` lists every change made since, and `LICENSE` is upstream's MIT licence.
