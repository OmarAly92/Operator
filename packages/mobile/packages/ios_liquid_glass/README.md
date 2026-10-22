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
| `.glassEffect(.regular.interactive())` | `GlassEffect(glass: Glass.regular.interactive(), ...)` |
| `.glassEffect(in: .circle)`, `.rect(cornerRadius:)`, capsule | `GlassShape.circle()`, `GlassShape.rect(r)`, `GlassShape.superellipse(r)`, `GlassShape.capsule()` |
| `GlassEffectContainer(spacing:)`, `GlassEffectContainer()` | `GlassEffectContainer(spacing: 40, child: ...)`, `GlassEffectContainer(child: ...)` (native default, 8 pt) |
| `@Namespace` | `GlassNamespace()`, created once in a `State` |
| `.glassEffectUnion(id:namespace:)` | `GlassEffect(union: GlassEffectUnion(id, namespace), ...)` |
| `.glassEffectID(id, in: namespace)` | `GlassEffect(id: GlassEffectID(id, namespace), ...)` |
| `.glassEffectTransition(.materialize)`, `.identity`, `.matchedGeometry` | `GlassEffect(transition: GlassEffectTransition.materialize)`, `GlassEffectTransition.identity`, `GlassEffectTransition.matchedGeometry` |
| `Animation.default`, `.snappy`, `.bouncy`, `.smooth` | `GlassAnimation.defaultSpring`, `.snappy`, `.bouncy`, `.smooth` |
| `.spring(duration:bounce:)`, `.spring(response:dampingFraction:)` | `GlassAnimation.spring(duration:, bounce:)`, `GlassAnimation.dampedSpring(response:, dampingFraction:)` |
| `withAnimation(.bouncy) { ... }` | `withGlassAnimation(GlassAnimation.bouncy, () => setState(...))` |
| (no equivalent) | `GlassAnimationScope(animation: ..., child: ...)`, a default for a subtree; `GlassAnimation.none` turns animation off |
| `.scrollEdgeEffectStyle(.soft / .hard / .automatic)` | `ScrollUnderBars(style: ScrollEdgeStyle.soft, child: ...)` or `ScrollEdgeEffect(...)` |
| the 35% dimming layer under clear glass | `GlassDimming(child: ...)` |
| (no equivalent; for widget tests only) | `debugGlassPress(element)`: whether the glass under `element` is pressed, its press scale and its light. Exported for tests that check a press, as `debugResetGlassAnimation` is; not an API for app code |

### Motion

Glass materializes when it appears and dematerializes when it is removed, as native glass does: the lens, frost, tone and edge light ramp in and out while the content fades, rather than the whole glass fading. A removed glass keeps drawing, with a snapshot of its content, until it has gone. Glass that moves or changes size springs from where it was drawn to where it is laid out; its content follows it, and taps go to the new layout at once.

```dart
GlassEffectContainer(
  child: shown ? GlassEffect(child: label) : const SizedBox.shrink(),
)

withGlassAnimation(GlassAnimation.snappy, () => setState(() => shown = !shown));
```

Changes animate by default with `GlassAnimation.defaultSpring`. `withGlassAnimation` applies its animation to every glass change built in the next frame, including one an unrelated `setState` causes in that frame, as a SwiftUI transaction does; otherwise the nearest `GlassAnimationScope` applies; otherwise the default. Because that pending animation is one global value, a test that calls `withGlassAnimation` and ends without a frame would hand it to the next test's first frame: call `debugResetGlassAnimation()` in `tearDown` (it is exported for tests only). `GlassAnimation.none` and `GlassEffectTransition.identity` change at once. The presets are SwiftUI's springs: `defaultSpring` 0.55 s, `smooth` 0.5 s, `snappy` 0.5 s with bounce 0.15, `bouncy` 0.5 s with bounce 0.3.

What animates:
- **Insertion and removal.** A glass materializes when it is built into a layout that already existed (`if (shown) GlassEffect(...)` inside a container, a `Row` or a `SizedBox`), or inside `withGlassAnimation`. Glass built together with its parent (a page, a tab, a new subtree, a list item scrolled into view) appears at once, as does `if (shown) Padding(child: GlassEffect(...))` outside `withGlassAnimation`. Removal mirrors it: a glass removed on its own dematerializes; one that leaves with its parent or its page goes at once. Inside `withGlassAnimation`, container glass that leaves together with its container dematerializes in the nearest `Overlay`, as glass outside a container does. A glass inserted or removed while it is off screen, its tickers muted by `TickerMode` (a route covered by another, an offstage tab), changes at once and leaves no ghost: nothing transitions where it cannot be seen.
- **Moves and resizes.** A single layout change animates when the glass widget was rebuilt, when its container gained or lost a glass, or inside `withGlassAnimation`. A glass whose layout changes on consecutive frames (frames drawn one after the other, at most 50 ms apart) is moved by the app, by a drag, its own animation or the keyboard, and follows its layout exactly: its first changed frame is taken as a single change and holds the glass where it was, and from the second it sits on its layout, covering both frames' movement in one step. It animates again after a frame without a change. Inside `withGlassAnimation` changes animate even on consecutive frames. The cost: two separate changes on back-to-back frames are taken as motion, so the second lands at once and drops the first one's spring. The common case is a snap to a detent on release: it comes within one frame of the last drag frame, so it lands at once; wrap the release in `withGlassAnimation(GlassAnimation.defaultSpring, () => setState(...))` and it springs. Scrolling never animates: glass in a scroll view moves with the content in the same frame. A `const` glass whose parent changed jumps unless the change is inside `withGlassAnimation`. A container that re-centres in its parent (a centred `Row` that gains an item) animates its glass; anything that moves the container's parent moves the glass at once.
- **Glass outside a container** transitions too. Its ghost is drawn in the nearest `Overlay`, above that overlay's routes; without an `Overlay` (no `MaterialApp`, `CupertinoApp` or `WidgetsApp` above it) it has nowhere to draw a ghost, so it both appears and disappears at once.

The timing is native's, measured on the iOS 27 simulator. Appearing glass follows the animation's spring and overshoots where the spring does, scaled by a fitted gain (0.44 for `snappy`, 0.5 for `bouncy`; the default spring does not overshoot, so it needs none); `lab.py fitvis` fits the gain on native's overshoot peak against the overshoot Flutter's own frames show, read through a visibility table that extends above full visibility, and the table has room for a gain per appearance, used only when the fit shows a consistent difference between light and dark (the shipped table uses one gain for both). Disappearing glass follows the spring's remainder to a fitted power (3.1 for the default, 2.75 for `snappy`, 2.7 for `bouncy`), which is why removal is about twice as fast as insertion. An app's own spring uses the preset nearest its damping. The backdrop blur ramps linearly with visibility (the fitted power is 1), the exponent that best matches native's half-way sharpness and its per-backdrop progress together. The numbers ship as a table, `ios27_motion.dart`, written by the lab. Under Reduce Motion native keeps materialize's timing and blur and overshoots more, so glass that begins to appear under Reduce Motion takes a second fitted gain (0.6 for `snappy`, 0.8 for `bouncy`).

Each glass resolves its material (tone, frost, edge light and shadow) from its drawn size at layout and on every animated frame, so a glass growing from 44 to 200 pt changes its shadow as it grows.

A container's glass blends with its neighbours as native's does: glass closer than `spacing` deforms toward its neighbour, and joins it into one shape when closer than about half of `spacing`. The shape is a smooth union weighted by the angle between the two shapes' edges; against native's stills its necks and bulges differ by at most 0.5 pt RMS (light photo, 9 spacings from 4 to 80 pt), but the whole still comparison passes in 6 of the 46 recorded cases (all light photo, none dark): the shadow and the pinch at the reach still differ. Shapes blend by their drawn rects, so glass that springs toward or away from its neighbour joins and splits as it moves. A `spacing` change animates like a move: with `withGlassAnimation`'s animation, the nearest `GlassAnimationScope` or the default spring, and a spacing the app changes on consecutive frames follows its value. That animation is this package's own design: no native recording of a container changing its `spacing` has been judged yet.

A glass with a `GlassEffectID` and no `transition` morphs (`GlassEffectTransition.matchedGeometry`), as native glass with a `.glassEffectID` does; a glass without one materializes. Morphing glass stays at full brightness and blends with its container's other glass by `spacing` while it moves:
- **With a partner.** A glass removed and another inserted with the same id in the same container in the same frame draw as one glass: it springs from the removed glass's drawn rect to the inserted one's layout with the animation in force, while the old content fades out over it and the new content fades in.
- **Appearing without a partner.** The glass emerges from the nearest glass already in the container (the one whose drawn rect is closest to the new glass's layout): it starts on that glass's drawn rect and springs to its own layout. Under Reduce Motion it starts at that glass's centre at its own size, and its content fades in.
- **Removed without a partner.** A glass whose last rect is within `spacing` of a remaining glass's laid-out rect sinks into it: it moves to that glass's centre at full brightness while it shrinks and its content fades, then is dropped; under Reduce Motion it slides there at full size. A glass farther away dematerializes in place.
- **Content.** The content of every glass in a morph is blurred from the change until its glass no longer touches another glass of the morph (gap at least half of `spacing`); the glass a removed one sinks into stays blurred until it has sunk. Under Reduce Motion nothing is blurred.
- Glass without a container, or alone in one, has nothing to morph with: an appearing glass grows from its own centre and a removed one dematerializes.

Glass in one container that shares a `GlassEffectUnion` (the same id in the same `GlassNamespace`), the same shape and the same `Glass` draws as one shape at any distance, as native's `.glassEffectUnion` does: a shape on the bounding rect of the members' drawn rects, so it follows a member that moves. Circles and capsules become a capsule of that rect, as native draws two 64 pt circles 16 pt apart as one 144 × 64 pt capsule; rounded rectangles and superellipses keep their corner radius. Each member's content stays where that member is laid out. A union counts as one shape against a container's 16 shapes, and blends with the container's other glass by `spacing` like any shape. Glass with the same union id but a different shape or `Glass` forms its own union. A member that is materializing draws on its own and joins its union when it settles; a removed member leaves its union at once and dematerializes on its own. A union needs a container: glass outside one draws on its own whatever its union. The fallback renderer without shader support (`FakeGlass`) draws each member on its own.

### Press

Interactive glass (`Glass.regular.interactive()`, or `.interactive()` on any `Glass`) reacts to a touch as native interactive glass does on the iOS 27 simulator:
- **It lights at once and grows second.** On touch-down the glass brightens in the frame of the touch: an even light over the whole glass and a brighter spot under the finger that follows it. About 50 ms later the glass and its content scale up together about their centre, on a spring that overshoots a little and settles. The scale is uniform, the same factor on both axes, and falls with size: the **settled** growth in width is min(15.88, 9.7 × (100 / height)^1.24) pt (15.88 pt for glass up to about 67 pt tall, 11.4 pt at 88 pt, 4.1 pt at 200 pt), within 0.89 pt of native's at every landscape size measured, from 58 × 58 to 360 × 200 and 300 × 250, and the height grows by the same factor. A width term was fitted too and adds nothing measurable at those sizes.
- **Release.** On touch-up the glass springs back to its size, slightly under it and back. The spot fades while the even light stays, and then all the light goes in one frame, later for small glass than for large: about 720 ms after release for a 58 pt circle, 410 ms for a 250 × 88 capsule.
- **Drags.** A finger that moves keeps the press, the spot following it, and the glass does not stretch while the finger is inside it. Leaving the glass does not release it: native glass stays pressed until the finger lifts, measured with the finger 40 pt beside it, 106 pt above it and 256 pt below it. Native glass also leans a little toward a finger outside it (up to about 1.7 pt and 3.9 % of its aspect at 256 pt); this package does not.
- **Neighbours.** Pressing one glass in a container does not light or scale its neighbours. A pressed glass that grows toward a neighbour within `spacing` blends with it as any glass does.
- **Touches.** The glass listens to raw pointer events and never enters the gesture arena, so a button inside interactive glass keeps its tap and the glass presses too. Any touch inside the glass's shape counts, whatever its content, and the glass takes that touch: inside its shape, interactive glass is opaque to hit testing, so a widget behind it does not get the touch. With interactive glass nested in interactive glass only the innermost presses, and a second finger is ignored. A scroll view that scrolls while the finger is down releases the press; no native recording of that exists, it is the design.
- **Reduce Motion.** The glass lights as usual and never grows; the light goes about 570 ms after release.
- **What differs from native, measured.** Native's light changes the glass's colour on saturated backdrops (it brightens and saturates it); this package adds white. Native's light lasts longer after a press-drag than after a press. The light's strength follows the backdrop in native and not here: on the 58 and 44 pt circles the peak is 10 to 13 luma below native's on dark photo and about 9 above it on light photo, and about 3 below on dark photo at 250 × 88 and larger. Native's release is slower than this package's for small glass and faster for large: a 58 pt circle settles in about 320 ms in native against 170 to 250 ms here, a 300 × 250 rectangle in about 137 ms against about 230 ms here. Measured limits of the size law: a 120 × 250 portrait capsule, which the law was not fitted on, grows 1.67 pt less in width and in height here than in native on dark photo, and a 300 × 250 rectangle 0.89 pt less; every other measured size is within 0.78 pt. The details are in the repository's `docs/liquid_glass/02b-motion/results-2b3.md`.

The numbers come from the lab: `pressfit.py` fits the size law, the growth and release springs, the light's timing, its strength and its cut per glass size on native recordings that pass the lab's take check, and writes `ios27_press.dart`.

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

Under Reduce Motion glass does what native glass does under it, measured, not guessed: materialize keeps its timing and blur and overshoots more (above); merge and morph change nothing but morphing glass, which slides at full size with its content fading in sharp; a press lights the glass without growing it. `LiquidStretch` does nothing under Reduce Motion. A change of the setting applies from the next change.

### Size

Native glass changes with its size: a 200 pt glass casts a long soft shadow (sigma about 17 pt) where a 44 pt one casts almost none, and its tone and frost differ too. `GlassEffect` resolves the tuned material from its drawn size, interpolated between the 44, 88 and 200 pt anchors on its shorter side, at its first layout and whenever it changes size; no frame is painted with a guess. `sideHint` is the size its first build uses before that layout.

Inside a `GlassEffectContainer`, every grouped child shares the container's single glass layer, so the layer's settings (tone, frost, edge light) are resolved once for the whole container: from its `side` when one is given, and otherwise from the median of its members' measured shorter sides, following them as they resize, join and leave. A container of equal members (a union of 64 pt circles, a row of 44 pt buttons) therefore draws with the row of that size; a container of members of different sizes draws all of them with the median member's row, because one layer has one material. Each child's shadow still comes from its own measured size.

### Clear glass has no tint

`Glass.clear.tint(color)` still renders untinted, with or without Reduce Transparency and Increase Contrast, and its foreground is the plain one. Use `Glass.regular.tint(color)` for tinted glass.

### Low level

The renderer underneath is still public: `LiquidGlass`, `LiquidGlassLayer`, `LiquidGlassSettings`, `LiquidGlassBlendGroup`, `FakeGlass`, `GlassGlow` and `LiquidStretch`. `LiquidGlassSettings.atVisibility(v, blurRampExponent: k)` gives the settings glass draws with at materialize visibility `v`, the backdrop blur ramped as `v` to the power `k` (by default the fitted `ios27BlurRampExponent`). It is a lab-facing helper, public so the lab's `tool.visibility` scene draws through the renderer's own function, and not part of the SwiftUI-mirroring API. `GlassMaterial.resolve(...)` returns the tuned material for any glass, size, appearance and accessibility state, and `toSettings()` turns it into `LiquidGlassSettings`.

### Other exports

- `GlassKind`: the enum behind `Glass` (`regular`, `clear`, `identity`).
- `GlassEffectScope`: an inherited widget that gives a `GlassEffect`'s subtree its `Glass`; `GlassEffectScope.maybeOf(context)` reads it.
- `GlassAccessibilityData`: the Reduce Transparency, Increase Contrast and Reduce Motion flags that `GlassAccessibility` carries.
- `GlassGlowLayer`: the layer a `GlassGlow` sends its touch updates to, like `Material` for an `InkWell`.
- `GestureMode`: whether a drag-driven effect reads raw pointer events (`listener`) or takes part in the gesture arena (`gestureDetector`).
- `RawLiquidStretch`: stretches its child by a given `Offset` in pixels; `LiquidStretch` is this plus drag handling.
- `OffsetResistanceExtension`: `Offset.withResistance(r)`, a damping that holds an offset back the further it is from zero.
- `ScrollEdge`: which edge (`top` or `bottom`) a `ScrollEdgeEffect` sits on.
- `ScrollEdgeMaterial` and `ios27ScrollEdgeTable`: the scroll edge's tuned values per appearance and style, resolved by `ScrollEdgeMaterial.resolve`. Written only by the lab's tuning.
- `GlassMaterialOverride`: debug builds only; overrides the resolved material values for a subtree, for the lab.
- `LgrLogs`: switches on the package's loggers.
- `debugPaintLiquidGlassGeometry`: draws the geometry textures instead of the glass; false in release builds.
- `GlassCapsule`, `GlassCircle`, `GlassRect`, `GlassSuperellipse` (the `GlassShape` subclasses) and `LiquidShape`, `LiquidOval`, `LiquidRoundedRectangle`, `LiquidRoundedSuperellipse` (the renderer's shapes).

## How the look is made

- The geometry pass computes a signed-distance field of every shape in a layer, blends nearby shapes, and bakes a quarter-circle bevel with Snell refraction and the distance to the silhouette into a cached texture. It also covers a thin band just outside each shape.
- The final pass refracts the frosted backdrop through that texture, with dispersion at the rim only. It maps brightness through a three-point tone curve (black, mid, white) and tints with the accent across a brightness range. Then it draws the iOS 27 edge measured on the simulator: a crisp silhouette, a dark outline just outside it that is strongest at the curved ends, and a bright line and a soft sheen along the top and bottom, lit by two lobes of a vertical light.
- The shadow is one Gaussian per glass, offset downward, fitted to native's.
- The scroll edge effect stacks real Gaussian blurs, masked by a small shader, under a tinted gradient.

Frame cost, measured on the iOS 27 simulator with 13 glasses over a moving backdrop (debug build, raster median): 12.66 ms with the tuned material through `GlassEffect`, against 12.10 ms for this fork's renderer before 2A (the `liquid_glass_renderer` copy on Operator's `development` branch) at its defaults (+4.6%); a soft scroll edge adds 4.98 ms. Check your target devices.

## Credits and licence

This package is a fork of [`liquid_glass_renderer`](https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer) by Tim Lehmann ([whynotmake.it](https://whynotmake.it)), MIT licensed. The renderer's geometry pass, blend groups, caching, `FakeGlass`, `GlassGlow` and `LiquidStretch` are his work. `FORK.md` lists every change made since, and `LICENSE` is upstream's MIT licence.
