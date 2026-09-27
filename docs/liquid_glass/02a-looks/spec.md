# Project 2A: ios_liquid_glass package foundation and how glass looks

Date: 2026-09-27. Status: **written, awaiting the user's review.** The plan is not written yet.
Master roadmap: `docs/liquid_glass/ROADMAP.md`; read it first, especially §3–§5.
Measuring instrument: project 1 (`docs/liquid_glass/01-reference-lab/`) and `packages/mobile/tool/glass_lab/`.

Paths are relative to `packages/mobile/` unless they start with `docs/`.

---

## 1. Why

The user's goal is one Flutter package, `ios_liquid_glass`, that is identical to native iOS 27 Liquid Glass and usable in any Flutter app (ROADMAP §1). Today the package is a lightly modified fork of `liquid_glass_renderer`. The parts that make it look like iOS live in Operator (`lib/core/widgets/glass/glass_style.dart` and friends), and they look like iOS 26.5, not 27.

Project 1's baseline measured the gap (ROADMAP §8):

| Measure | Operator | Target |
|---|---|---|
| Region colour difference (MAD) | ~14 | ≤ 4 |
| Rim-profile error | ~19 | ≤ 6 |
| Reduce Transparency difference | 56 | not handled at all today |
| Scroll edge effect difference | ~50 | ≤ 4 |

The causes are in the final render step:
- the rim takes on the backdrop's colour instead of iOS 27's dark hairline plus bright specular;
- a flat alpha tint instead of a brightness transfer curve;
- too little frosting;
- an even shadow;
- no light/dark adaptation.

2A makes the package stand on its own and makes its glass **look** identical to native. How glass **moves** is project 2B. Components are project 3.

## 2. Scope

**In:**
- **A. Package foundation:**
  - A1: rename to `ios_liquid_glass`;
  - A2: turn it into a plugin with an iOS accessibility bridge;
  - A3: a SwiftUI-mirroring public API;
  - A4: an iOS 27 material system inside the package;
  - A5: an `example/` app as the lab's Flutter target;
  - A6: Operator migrated onto the new API.
- **B. The iOS 27 look:**
  - B1: new final render model (refraction profile, rim-only dispersion, frosting, brightness curve, tint, hairline, dual specular);
  - B2: size dependence;
  - B3: shadow;
  - B4: variants (regular, clear with dimming, tinted, identity);
  - B5: scroll edge effect;
  - B6: Reduce Transparency and Increase Contrast;
  - B7: foreground colour on glass;
  - B8: light/dark flip spike.
- **C. Tuning tool:** `lab.py tune`, an automatic parameter search against native.

**Out:**
- Motion of any kind: press response, materialize, merge, morph, springs, Reduce Motion behaviour. That is 2B.
- Components: tab bar, toolbar, buttons, sheets, menus and so on. That is project 3. 2A may change how Operator's existing components look, because they draw through the material, but it does not move them into the package or change their layout.
- Device tilt highlights, and real-device checks. That is project 5.
- Android visuals. Android must compile, and the plugin is a no-op there.

## 3. Decisions (settled)

- Package name **`ios_liquid_glass`**, directory `packages/ios_liquid_glass/`. Keep upstream's MIT `LICENSE` and credit Tim Lehmann / whynotmake.it in the README and in `FORK.md`, which is kept as the change log against upstream.
- Keep the renderer's **geometry pass, blend groups and caching** (`liquid_glass_geometry_blended.frag`, `LiquidGlassLayer`, `LiquidGlassBlendGroup`). **Replace the final render step** (`liquid_glass_final_render.frag` and its helpers in `render.glsl`) with the iOS 27 model in §5.
- Material numbers come from **measurement**, found by `lab.py tune` (§6), and never from eyeballing.
- The target is the iOS 27 simulator "iPhone 17 Pro (iOS 27)" (ROADMAP §3).

---

## 4. Part A: package foundation

### A1. Rename
- `git mv packages/liquid_glass_renderer packages/ios_liquid_glass`.
- `packages/ios_liquid_glass/pubspec.yaml`:
  - `name: ios_liquid_glass`;
  - `description:` "iOS 27 Liquid Glass for Flutter, measured against native.";
  - `version: 0.1.0`;
  - keep `resolution: workspace` and `publish_to: none`.
- The library file becomes `lib/ios_liquid_glass.dart` (library `ios_liquid_glass`), and shader asset paths become `packages/ios_liquid_glass/...`. Check `lib/src/shaders.dart`, which builds asset keys.
- App `pubspec.yaml`: in the workspace entry and in the dependency, replace `liquid_glass_renderer` with `ios_liquid_glass`.
- Replace every import `package:liquid_glass_renderer/liquid_glass_renderer.dart` with `package:ios_liquid_glass/ios_liquid_glass.dart`. Today that is 7 files: 3 in `lib/core/widgets/glass/` and 4 in `test/`.
- `grep -rn liquid_glass_renderer` must afterwards hit only `FORK.md`, `CHANGELOG.md` and the README credit.
- Run `flutter pub get` from `packages/mobile`. `pubspec.lock` changes only the package name.

### A2. Plugin with an iOS accessibility bridge
Flutter's `MediaQuery` exposes Increase Contrast (`highContrast`) and Reduce Motion (`disableAnimations`), but **not Reduce Transparency**. The package becomes a Flutter plugin:
- `pubspec.yaml` gets `flutter: plugin: platforms: ios: pluginClass: IosLiquidGlassPlugin`.
- `ios/Classes/IosLiquidGlassPlugin.swift`: a Swift Package or podspec, whichever builds under Xcode 27 with the app's CocoaPods setup. The prototype decides.
- An `EventChannel` named `ios_liquid_glass/accessibility` emits `{reduceTransparency, increaseContrast, reduceMotion}`, read from `UIAccessibility.isReduceTransparencyEnabled`, `isDarkerSystemColorsEnabled` and `isReduceMotionEnabled`. It emits once on listen and again on `UIAccessibility.reduceTransparencyStatusDidChangeNotification`, `darkerSystemColorsStatusDidChangeNotification` and `reduceMotionStatusDidChangeNotification`.
- On other platforms nothing is registered, and Dart falls back to `MediaQuery` values with Reduce Transparency false.
- Dart side: `GlassAccessibility` (`lib/src/accessibility/glass_accessibility.dart`):
  - an `InheritedWidget` fed by the channel stream, merged with `MediaQuery`;
  - `GlassAccessibility.of(context)` returns `{reduceTransparency, increaseContrast, reduceMotion}`;
  - `GlassAccessibilityScope` is inserted automatically by the package's root widgets, so apps do not have to add it;
  - tests override the values with `GlassAccessibility.debugOverride`.
- Verify with the lab: `lab.py run material.regular --a11y reduce-transparency` flips the flag inside the example app. The harness already sets the simulator defaults (`sim.accessibility`).

### A3. Public API, mirroring SwiftUI
New public classes, in `lib/src/api/`, all exported from `lib/ios_liquid_glass.dart`:

| Dart | SwiftUI | Meaning |
|---|---|---|
| `Glass` (immutable value, `==`) with `Glass.regular`, `Glass.clear`, `Glass.identity`, `.tint(Color?)`, `.interactive([bool])` | `Glass` | What material to draw. `interactive` is stored now and behaves in 2B. |
| `GlassEffect({required Glass glass, GlassShape shape = const GlassShape.capsule(), required Widget child})` | `.glassEffect(_:in:)` | Draws glass behind the child, in the shape, sized by the child. |
| `GlassShape.capsule()`, `.circle()`, `.rect(cornerRadius)`, `.superellipse(cornerRadius)` | `DefaultGlassEffectShape`, `.circle`, `.rect(cornerRadius:)` | Maps to the renderer's `LiquidRoundedSuperellipse`, `LiquidOval` and `LiquidRoundedRectangle`. Concentric shapes come in project 3. |
| `GlassEffectContainer({double? spacing, required Widget child})` | `GlassEffectContainer(spacing:)` | Shares sampling and blending for nearby glass (the renderer's `LiquidGlassLayer` plus blend group). Merge behaviour is tuned in 2B. |
| `GlassDimming({double opacity = 0.35, required GlassShape shape})` | HIG dimming layer | The dark layer under clear glass over bright media. |
| `GlassTheme` (`InheritedWidget`), with `GlassTheme.of(context)` returning `GlassThemeData { Brightness? brightness, Color? accent }` | environment | Optional. By default the brightness comes from `MediaQuery.platformBrightnessOf` and there is no accent. Operator sets its accent here. |

- The existing low-level renderer API (`LiquidGlass`, `LiquidGlassLayer`, `LiquidGlassSettings` and so on) stays exported. `GlassEffect` is built on it, and advanced users keep full control.
- The API is a stable surface for projects 2B and 3. Name it once, here, and do not rename it later.

### A4. iOS 27 material system inside the package
- `lib/src/material/glass_material.dart`: `GlassMaterial`, the full parameter set of the new render model (§5 B1–B3, one field per parameter), with `lerp`.
- `lib/src/material/ios27.dart`: the **tuned table**.
  - It is keyed by appearance (light, dark) × variant (regular, clear, tintedBase) × size anchor, where the anchor is the glass's shorter side: **44, 88 and 200 pt**, the three sizes of `material.regular`.
  - It also holds Reduce Transparency and Increase Contrast overrides per appearance.
  - It is written by `lab.py tune --write` in one fixed, sorted format, plain Dart `const` maps with no comments, so diffs are readable.
- `GlassMaterial.resolve({required Glass glass, required Size size, required Brightness brightness, required GlassAccessibilityData a11y, Color? accent})`:
  - picks the variant row;
  - interpolates between size anchors on log(shorter side), clamping outside 44–200;
  - applies the tint and the accessibility override;
  - returns the `GlassMaterial` that `GlassEffect` hands to the renderer.
- **Debug overrides:** `GlassMaterialOverride` (`InheritedWidget`, honoured only when `kDebugMode`) replaces any subset of fields by name. The example app fills it from `launch.json` for tuning (§6).

### A5. `example/` app = the lab's Flutter target
The package gets `packages/ios_liquid_glass/example/`: a Flutter app created with `flutter create --platforms ios,android --org dev.operator.iosliquidglass example`. Its iOS bundle id is `dev.operator.iosliquidglass.example`, and it is a workspace member if pub requires that.
- It runs **only package code**. That proves the package works in a fresh app, which is the user's goal.
- The lab plumbing moves from Operator into the example app:
  - `GlassLabLaunch`: launch file `Documents/glass_lab/launch.json`, now with an optional `material` overrides map;
  - `GlassLabMarker` and `GlassLabReady`;
  - `GlassLabBackdrop`;
  - the registry and the missing-scene placeholder.

  They live in `example/lib/lab/`, with the same ids and semantics identifiers as today.
- Scenes implemented in the example app in 2A, all built with the new API:
  - `material.regular`, `material.clear`, `material.tinted`, `material.shapes`, `material.content` (content materials: plain frosted cards);
  - `material.edge.soft`, `material.edge.hard`, `material.edge.automatic`;
  - `material.flip`, only if the B8 spike lands.

  Motion scenes (`material.interactive`, `material.materialize`, `material.merge`, `material.union`, `material.morph`) render their glass statically for still images. Their motion is 2B.
- Harness changes (`tool/glass_lab/harness/`):
  - `build.py` gains `flutter_example(udid)`, which builds `packages/ios_liquid_glass/example/ios/Runner.xcworkspace` with the same Xcode 27 recipe.
  - `lab.py build` gains the target `example`, and `both` means native plus example plus Operator.
  - `record.target_for` and the `run`, `baseline` and `tune` commands take `--flutter example|operator`, defaulting to `example`. The bundle ids live in `build.py`.
  - `prepare` copies backdrops into all three apps.
  - Operator's debug lab keeps only the component scenes (tab bar, buttons, sheet, nav bar) until project 3 moves them. Its material scenes are deleted in favour of the example app's.
  - Tests are updated accordingly.
- The example app's `README.md` shows how to use the package in a new project. It is the user-facing proof of reuse.

### A6. Operator migrated onto the package API
- `lib/core/widgets/glass/glass_style.dart` is **deleted**. Its role (variant × size × appearance → settings) is now `GlassMaterial.resolve` in the package.
- `GlassSurface` stays as a thin Operator adapter over `GlassEffect`, so the ~30 call sites do not churn before project 3 replaces them:
  - `regular` → `Glass.regular`;
  - `clear` → `Glass.clear`;
  - `prominent` → `Glass.regular.tint(accent)`;
  - `chrome` → `Glass.regular`. Chrome was an iOS 26.5 tab bar special; the tab bar is re-tuned against iOS 27 in project 3, so until then it uses regular glass. That is accepted.
- `GlassScope` becomes an adapter over `GlassEffectContainer`.
- Operator sets `GlassTheme(accent: skin.accent)` at its app root.
- `scroll_edge_effect.dart`, `scroll_under_bars.dart` and `shaders/scroll_edge_blur.frag` **move into the package** (`lib/src/scroll_edge/`), re-exported as `ScrollEdgeEffect`, `ScrollEdgeStyle {soft, hard, automatic}` and `ScrollUnderBars`. Operator imports them from the package.
- `tab_lens.frag` and `glass_lens.dart` stay in Operator until project 3.
- Tests that pinned old `GlassStyle` numbers are rewritten to pin the package's resolution (`GlassMaterial.resolve`), not tuned values.
- Operator's look changes by design (iOS 27). Nothing else in Operator changes.

---

## 5. Part B: the iOS 27 look

### B1. The final render model
This replaces `liquid_glass_final_render.frag`, keeping the name so the renderer wiring is untouched, and the lighting part of `render.glsl`. Per pixel, in order:

1. **Refraction.**
   - The displacement comes from the geometry texture, with a **quarter-circle bevel height profile**, `h(t) = sqrt(1 - (1 - t)^2)` for t in [0, 1] across the bevel width (research/non-flutter.md §6, ranked 1).
   - Samples are pulled **inward**, as a convex lens does (ranked 2).
   - `getHeight` in `render.glsl` and the geometry shader's displacement encoding change so the profile is exact.
   - Parameters: `refraction` (maximum displacement at the rim, in pt) and `bevel` (bevel width, in pt).
2. **Dispersion.**
   - Per-channel displacement scales: red × (1 + k), blue × (1 − k).
   - It is weighted by the bevel factor, so the flat centre has none (ranked 6).
   - Parameter: `dispersion` (k).
3. **Frosting.**
   - The backdrop blur already exists as a `BackdropFilterLayer` with `ImageFilter.blur` under the shader (`rendering/liquid_glass_layer.dart` ~line 252).
   - Its sigma becomes a material parameter.
   - Parameter: `frost` (sigma in pt).
4. **Brightness transfer.**
   - The refracted, frosted colour splits into luminance L (Rec. 709) and chroma C = rgb − L.
   - Then L′ = clamp(`lift` + `gain` · L, 0, 1) and C′ = C · `saturation`.
   - This is what native does instead of a flat tint: dark glass lifts black backdrops to grey, and light glass compresses whites. The current flat `glassColor` alpha blend is removed.
   - Parameters: `lift`, `gain`, `saturation`.
5. **Tint** (tinted glass only).
   - colour = mix(colour, tintTone(L′), `tintAmount`).
   - `tintTone` maps the tint colour across brightness, keeping its hue and moving its lightness with L′, so the tint "adapts to the content behind it" (research/apple-inventory §2.4).
   - Parameter: `tintAmount`. The tint colour comes from `Glass.tint` or `GlassTheme.accent`.
6. **Edge hairline.**
   - A thin line at the silhouette: colour = mix(colour, hairlineColour, `hairline` · falloff(distance, `hairlineWidth`)).
   - `hairlineColour` is dark over bright local content and light over dark content (research/non-flutter.md ranked 4). It is found from the frosted sample's luminance just inside the edge, with a smoothstep between `hairlineDark` and `hairlineLight`.
   - Parameters: `hairline`, `hairlineWidth`, `hairlineDark`, `hairlineLight`.
7. **Specular.**
   - Two lobes, computed from the same geometry normal:
     - key = max(0, n · l)^`specularPower`;
     - fill = `specularFill` · max(0, −n · l)^`specularPower`.
   - They are masked to a rim band of `specularWidth` and added as white × `specular`.
   - `l` comes from `lightAngle`. The iOS 27 key light is upper-left; tuning confirms the angle.
   - Parameters: `specular`, `specularWidth`, `specularPower`, `specularFill`, `lightAngle`.
8. **Alpha.** Geometry alpha, antialiased as today.

Uniform packing:
- Impeller desyncs `setFloat` indices with uniform arrays (research/flutter-repos.md ranked 6), so pack into `vec4`s.
- Keep the SkSL fallback path compiling. The existing `FakeGlass` path stays as the non-shader fallback, and gets the same brightness transfer where it can.

### B2. Size dependence
- Every B1 parameter is defined at the anchors 44, 88 and 200 pt (shorter side) and interpolated (A4). Native makes larger glass "more opaque, thicker, deeper shadow, stronger lensing" (research/apple-inventory §2.10).
- The three anchors are fitted from `material.regular`, whose sizes are 150×44, 250×88 and 360×200.

### B3. Shadow
- `GlassShadow` (`lib/src/glass_shadow.dart`) is driven by `shadowOffsetY`, `shadowBlur` and `shadowOpacity` per appearance and size.
- Native's shadow sits lower. Operator's is even today, which is why box centres are off by 4–8 pt on light backdrops.
- Fitted by the box and centre measures on `white` and `text` backdrops. On `black` the shadow is invisible and the centre is already 0.0.
- **Adaptive shadow** (deeper over text, lighter over flat light) needs the backdrop's luminance under the glass. It is in scope only if the B8 spike provides that cheaply. Otherwise the static shadow is fitted to the average of `text` and `white`, and adaptivity moves to 2B or 3 with a note in the ROADMAP.

### B4. Variants
- **Regular:** as above.
- **Clear:**
  - its own table rows: much lower `lift`, less `frost`, "no adaptive behaviours" (research/apple-inventory §2.2);
  - `GlassDimming` supplies the 35% dark layer;
  - measured by `material.clear` on `photo` and `white`, with and without dimming.
- **Tinted:** regular plus `tintAmount`. Measured by `material.tinted`, where native uses `Glass.regular.tint(accent)` and the accent is Operator's green `#1ACB64`.
- **Identity:** no glass at all, just the child. It exists so animations in 2B can switch glass on and off without changing the widget tree.

### B5. Scroll edge effect (iOS 27)
- Move it into the package (A6).
- Measure `material.edge.soft`, `.hard` and `.automatic` over the `scroll` backdrop. Today's MAD is ~50.
- iOS 27's automatic style draws "a uniform toolbar across the top" when content scrolls under floating bars (research/apple-inventory §2.19 and §8).
- Parameters (tuned per style and appearance):
  - blur ramp start and end, in pt from the top;
  - maximum blur sigma;
  - dim or scrim colour and opacity;
  - for automatic: the uniform bar's opacity and height.
- `ScrollEdgeStyle.automatic` becomes the default.

### B6. Accessibility looks
- **Reduce Transparency:** glass becomes an almost opaque frosted fill with the same shape and shadow. The table holds a per-appearance `reduceTransparency` row. It is fitted with `--a11y reduce-transparency` on `material.regular` and `material.tinted`; today's MAD is 56.
- **Increase Contrast:** a visible border (colour and width) plus a more opaque fill. The table holds an `increaseContrast` row, fitted with `--a11y increase-contrast`; today's MAD is 22.
- **Reduce Motion:** only the flag plumbing (A2) in 2A. The behaviour is 2B.

### B7. Foreground on glass
- `Glass.foregroundColor(context)` and `GlassForeground` (a `DefaultTextStyle` plus `IconTheme` wrapper) give labels and symbols on glass their native colour: primary label colour per appearance, or per flip state if B8 lands.
- Operator's components keep their own colours until project 3.
- Measured on `material.tinted` (the "Run" label) and on native button labels in `button.styles`.

### B8. Light/dark flip: spike first
Native small glass (bars, tab bars) flips light or dark with the content behind it; large glass never does (research/apple-inventory §2.9). Flutter cannot cheaply read what lies behind a widget. The spike answers whether the package can match this without hurting frame time. It compares three options on `material.flip`:
1. **In-shader:** tone chosen per element from a few samples of the frosted backdrop across the element. It is cheap, but it has no hysteresis and cannot flip glyphs, which live in Dart.
2. **Low-rate readback:** a `RenderRepaintBoundary.toImage` of the content behind the glass, downsampled and sampled every N frames. It has hysteresis and flips glyphs, but costs frame time. Measure it.
3. **Hybrid:** option 1 for the glass, and option 2 at a low rate for glyphs.

- The output is `docs/liquid_glass/02a-looks/flip-spike.md`, with measured frame cost and a native-vs-Flutter filmstrip of `material.flip`, plus a decision.
- Implement it in 2A only if the cost stays below 1 ms per frame on the simulator. Otherwise record the decision in the ROADMAP and move it to 2B.

---

## 6. Part C: tuning tool (`lab.py tune`)

Hand tuning took many rounds for the tab bar. Here it becomes a search.

- **Command:**

  ```bash
  lab.py tune --scene material.regular --size 44 --appearance dark \
    --backdrops white,black,photo,stripes,text \
    --params lift=0:0.4:9,gain=0.5:1.0:6,saturation=1:2:6,frost=2:12:6 \
    [--variant regular] [--a11y none] [--write]
  ```
- **How it runs:**
  - For each candidate it writes `launch.json` with `{"scene": ..., "backdrop": ..., "material": {"lift": .., ...}}` and runs the driver with no steps and no recording.
  - It captures `ready.png` only. The bare frames and the native `ready.png` are captured once and reused, which makes each candidate case about 12 s.
  - The example app applies the overrides through `GlassMaterialOverride` (A4).
- **Objective:** the sum over the chosen cases of MAD/4 + luminance/3 + rim/6 + centre/1 + bbox/1, each capped at 10× its threshold so one bad case cannot dominate. The region is the native element's region, exactly as in `analyze.py`.
- **Search:**
  - coordinate descent: sweep one parameter's grid holding the others, keep the best, move to the next, and repeat until a full pass does not improve by at least 1%;
  - then a local refinement with half the grid step around the best.
- **Output:** everything goes to `build/glass_lab/tune/<timestamp>/`:
  - `log.jsonl` (every candidate with its measures);
  - `best.json`;
  - a filmstrip of native against the best candidate.
- **`--write`:** rewrites the matching rows of `packages/ios_liquid_glass/lib/src/material/ios27.dart` in its fixed format.
- **Tests (harness):**
  - the objective on synthetic results;
  - coordinate descent on a fake evaluator with a known optimum;
  - the table writer round-tripping `ios27.dart`.
- **Order of tuning** (each step starts from the previous best):
  1. Dark regular at 88 pt: frost, lift, gain, saturation.
  2. Then refraction, bevel and dispersion.
  3. Then hairline and specular.
  4. Then shadow.
  5. Repeat at 44 and 200 pt.
  6. Light appearance.
  7. Clear.
  8. Tinted.
  9. Reduce Transparency and Increase Contrast.
  10. Scroll edge styles.

---

## 7. Done means

Every measure is read from a fresh `lab.py run` on the iOS 27 simulator, with the report reviewed.

1. **Package:**
   - renamed;
   - the plugin reads all three accessibility settings on iOS 27, and each toggle reaches the example app live, without a relaunch;
   - `flutter analyze` is clean and `flutter test` is green in both `packages/mobile` and the package (package tests plus example tests);
   - no `liquid_glass_renderer` import remains.
2. **Example app:** builds and runs every scene it registers. Unregistered ids show the missing placeholder. The README shows use in a fresh project.
3. **Material scenes pass strict still-image thresholds** on the example target (MAD ≤ 4, luminance ≤ 3, rim ≤ 6, centre ≤ 1 pt, box ≤ 1 pt), in light and dark:
   - `material.regular` on all 5 backdrops;
   - `material.clear` on `photo` and `white`;
   - `material.tinted` on `stripes`, `white` and `black`.
4. **Scroll edge:** `material.edge.soft`, `.hard` and `.automatic` pass MAD ≤ 4 and luminance ≤ 3 on `scroll`. The box and centre measures are exempt.
5. **Accessibility:** `material.regular` passes the same thresholds under `--a11y reduce-transparency` and under `--a11y increase-contrast`.
6. **Operator's component scenes improve.** On the Operator target, `tabbar.rest`, `button.press` and `navbar.inline`, in both appearances on their listed backdrops, must at least halve their rim RMS and luminance difference against the project 1 baseline. They keep Operator's fonts and icons, so MAD cannot reach zero.
7. **B8 spike:** written up, with a decision, and implemented only if accepted.
8. **Performance:**
   - measured in the example app on the simulator (raster frame time with and without a screen of glass);
   - recorded in the spike doc and the ROADMAP;
   - no worse than the current renderer by more than 20%.

   The real-device check is project 5.
9. **Documents:** the ROADMAP is updated (status, §7 checklist rows for 2A, §8 numbers), and `packages/ios_liquid_glass/README.md` documents the API with attributions.

## 8. Testing

**Package, Dart:**
- `Glass` value semantics;
- `GlassMaterial.resolve` (variant rows, size interpolation and clamping, the tint path, accessibility overrides);
- `GlassMaterialOverride` parsing, applied only in debug;
- `GlassAccessibility` with a mocked channel, plus the fallback when no channel exists;
- `GlassEffect` builds the renderer widgets with the resolved settings;
- `ScrollEdgeEffect` tests moved from Operator.

**Other:**
- **Plugin:** the Swift code is compiled by the example app's iOS build. Behaviour is checked by the lab's accessibility runs (Done item 5).
- **Harness:** tune objective, search, table writer, the `--flutter` target switch.
- **Operator:** existing glass tests updated to the adapter. Full `flutter test` green.

## 9. Risks

- **The brightness transfer might not be linear enough.** If `lift` and `gain` cannot reach MAD ≤ 4 on both `white` and `black`, extend the curve to a 3-point spline (L at 0, 0.5 and 1), a documented fallback.
- **Plugin build under Xcode 27 with CocoaPods.** The prototype must prove the example app and Operator both build with the plugin before the plan is written.
- **Shader cost.** Dual specular, adaptive hairline and dispersion add backdrop taps. Keep dispersion to three taps, and measure (Done item 8).
- **The iOS 27 key light direction and hairline adaptivity** are inferred from research, not published. Tuning decides, and the rim-profile measure guards it.
- **Scroll edge automatic** is new in iOS 27 and its visuals are undocumented. The lab's `material.edge.automatic` native recording is the only truth.

## 10. Files

**Created:**
- `packages/ios_liquid_glass/`: renamed from `packages/liquid_glass_renderer/`;
- `lib/ios_liquid_glass.dart`;
- `lib/src/api/{glass.dart, glass_effect.dart, glass_shape.dart, glass_effect_container.dart, glass_dimming.dart, glass_theme.dart, glass_foreground.dart}`;
- `lib/src/material/{glass_material.dart, ios27.dart, glass_material_override.dart}`;
- `lib/src/accessibility/glass_accessibility.dart`;
- `lib/src/scroll_edge/{scroll_edge_effect.dart, scroll_under_bars.dart}`;
- `lib/assets/shaders/scroll_edge_blur.frag`;
- `ios/Classes/IosLiquidGlassPlugin.swift` (+ podspec or `Package.swift`);
- `example/` (app, lab plumbing, scenes, README);
- `README.md`;
- `test/**`;
- `docs/liquid_glass/02a-looks/plan.md` (next);
- `docs/liquid_glass/02a-looks/flip-spike.md`.

**Modified:**
- `lib/assets/shaders/liquid_glass_final_render.frag`, `render.glsl`, `liquid_glass_geometry_blended.frag` (height profile);
- `lib/src/liquid_glass_settings.dart` (new fields, or superseded by `GlassMaterial` passed through);
- `lib/src/rendering/liquid_glass_layer.dart` (uniform packing, frost sigma);
- `lib/src/glass_shadow.dart`;
- `FORK.md`, `CHANGELOG.md`;
- in Operator: `pubspec.yaml`, `pubspec.lock`, `lib/core/widgets/glass/{glass_surface.dart, glass_scope.dart}`, the app root (`GlassTheme`), imports of the scroll edge effect;
- `tool/glass_lab/harness/{build.py, record.py, lab.py, tests/*}` and `tool/glass_lab/README.md`;
- `docs/liquid_glass/ROADMAP.md`.

**Deleted:**
- `lib/core/widgets/glass/glass_style.dart` and its test;
- `lib/core/widgets/glass/scroll_edge_effect.dart`, `scroll_under_bars.dart`, `shaders/scroll_edge_blur.frag` (moved into the package);
- Operator lab material scenes (moved to the example app).

## 11. How the plan must be written (for the next step)

Follow ROADMAP §5 and §9:
1. Prototype in the scratchpad first. Prove each of these on the iOS 27 simulator:
   - the rename;
   - the plugin build;
   - the example app build with the launch file;
   - the new shader compiling and rendering;
   - one `tune` loop improving one parameter.
2. Then write `docs/liquid_glass/02a-looks/plan.md` with the tested code embedded, tasks of reviewable size, and the Review Focus section.
3. The user approves it.
4. It is then executed in a fresh session, subagent-driven, in the worktree `../Operator-ios-liquid-glass` on branch `feat/ios-liquid-glass-2a`.
