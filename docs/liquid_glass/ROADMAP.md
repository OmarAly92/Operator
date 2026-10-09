# ios_liquid_glass: master roadmap

Last updated: 2026-10-07. Owner: Omar Aly (the user). This is the single source of truth for the whole Liquid Glass effort. Every other document in `docs/liquid_glass/` hangs off it.

**Status at a glance**

| # | Project | Status |
|---|---|---|
| 1 | Reference lab (measuring instrument) | **DONE**, merged to `development` (`7f74f5a0b`), not pushed |
| 2A | Package foundation + how glass looks | **DONE**, merged to `development` on 2026-10-02 (2A, 2A.1 and the review fix wave). Done item 3 passes 10 of 20 cases, item 4 5 of 6, item 5 17 of 20, item 6 22 of 32 measures, item 8 passes. Results: `docs/liquid_glass/02a-looks/results-2a1.md`. |
| 2A.2 | Static-look polish (shader residuals) | TODO, not planned: `docs/liquid_glass/02a-looks/todo-2a2.md` |
| 2B | How glass moves | **2B.1 DONE**, merged to `development` and pushed on 2026-10-06 (`c4de9358a`): the lab measures motion per shape, the native references and noise floors are recorded over fresh simulator boots, and the package has its motion coordinator with materialize and dematerialize. Done items 1, 2, 3, 5 and 6 pass; item 4 passes 133 of 168 progress measures in normal and Reduce Motion (gates 120 of 120), and its 70 classed failures are in `02b-motion/todo-2b1.md`. Results `02b-motion/results-2b1.md`; reviews `review-2b1-code.md`, `review-2b1-audit.md`. Recordings archived at `/Users/omaraly/development/AI/glass-lab-runs/2b1/`. **2B.2 DONE**, merged to `development` on 2026-10-09 (`9d2b95ca0`), not pushed: native merge semantics (glass deforms below `spacing`, joins below `spacing / 2`, default 8 pt, an angle-weighted union), container spacing animation, `GlassNamespace`/`GlassEffectUnion`, `GlassEffectID` morph, topology masks on stripes and photo, the H4 moving-glass appear fit, noise floors for the 2B.2 scenes. Done items 1 to 3 pass in part (merge 44–58 of 68 per case, morph no case fully, N7 spacing 7 of 46); every failure is classed in `02b-motion/todo-2b2.md`. `navbar.inline` is worse than 2A by the user's decision of 2026-10-08. Results `02b-motion/results-2b2.md`; reviews `review-2b2-code.md`, `review-2b2-audit.md`, `rereview-2b2-fixwave1.md`. **Next: the 2B.3 plan** (press, Reduce Motion everywhere, frame cost). |
| 3 | Every iOS component inside the package | NOT STARTED |
| 4 | Operator adopts the package | NOT STARTED |
| 5 | Real-device verification pass | NOT STARTED |

---

## 0. How to use this document (fresh session, read first)

1. Read this whole file, then the spec of the project you are about to work on. Specs are under `docs/liquid_glass/<nn>-<name>/spec.md`.
2. Section 9 says exactly what to do next. Do that, nothing else.
3. Follow section 5 (working rules) exactly, including how a plan is written (prototype first) and who reviews.
4. When a project changes state, update the status table above and that project's section in §6. Commit this file with the change.
5. Never trust memory over this file and `git log`. If they disagree, check the code and fix this file.

---

## 1. The goal

**In the user's words (2026-09-27):** "my goal is to improve this package `packages/mobile/packages/liquid_glass_renderer` so it be identical to original iOS liquid glass, so I can use this package in any other Flutter project if I needed liquid glass." Earlier (2026-09-26): "I want everything, I want perfection."

So:
- **The product is the package.** It will be renamed from `liquid_glass_renderer` to **`ios_liquid_glass`**; the user decided the name on 2026-09-27. It must be:
  - complete: every iPhone Liquid Glass material, motion and component;
  - identical to native iOS 27, measured and not eyeballed;
  - usable in any Flutter app, with no Operator code or theme inside.
- **Operator (`packages/mobile`) is only its first consumer.** Operator's own glass code in `lib/core/widgets/glass/` moves into the package over projects 2A and 3. Operator ends up using the package's widgets with its own tint colour and fonts.

### Decision log

| Date | Decision | By |
|---|---|---|
| 2026-09-23 | Mobile goes full iOS Liquid Glass, iOS only. Android must still compile. The Pencil design prototype no longer governs mobile. The AppSkin palette and fonts are kept. | user |
| 2026-09-26 | Target look is **iOS 27**, not 26.5. iOS 27 glass differs: a darker edge hairline, brighter specular, more diffusion, and a new automatic scroll edge. | user |
| 2026-09-26 | Order: reference lab → engine → components → Operator rollout, each with its own spec. | user |
| 2026-09-26 | Lab touch approach A: an XCUITest driver plays identical touches on native, the Flutter lab and Apple's apps. | user |
| 2026-09-27 | Split project 2 into 2A (looks) then 2B (motion). | user |
| 2026-09-27 | The package is the product, reusable in any Flutter app. Rename it to `ios_liquid_glass`. | user |
| 2026-09-27 | Keep the renderer's geometry and blend pass and its caching; replace the final lighting and colour step with an iOS 27 model. | agreed |
| pending | Native `material.interactive` shows no press reaction on the simulator. Recommendation: keep it as a still-image reference and check `.interactive()` on a real iPhone in project 5. | user to decide |

---

## 2. Where everything is

Repository: `/Users/omaraly/development/AI/Operator`. Default branch `development`; release branch `master`, which is never used for this work. All mobile paths below are relative to `packages/mobile/` unless they start with `docs/`.

### The package (the product)
| Path | What |
|---|---|
| `packages/ios_liquid_glass/` | The package, renamed from `liquid_glass_renderer` in 2A. It is a pub workspace member (listed under `workspace:` in `pubspec.yaml`, depended on by name `ios_liquid_glass`). |
| `packages/ios_liquid_glass/lib/ios_liquid_glass.dart` | Public exports: `LiquidGlass`, `LiquidGlassLayer`, `LiquidGlassSettings`, `LiquidGlassBlendGroup`, `FakeGlass`, `GlassGlow`, `LiquidStretch`, shapes, plus the 2A API and material exports below. |
| `packages/ios_liquid_glass/lib/src/` | `liquid_glass.dart`, `liquid_glass_blend_group.dart`, `rendering/liquid_glass_layer.dart`, `rendering/liquid_glass_render_object.dart`, `liquid_glass_settings.dart`, `glass_glow.dart`, `glass_shadow.dart`, `fake_glass.dart`, `stretch.dart`, `internal/*` |
| `packages/ios_liquid_glass/lib/src/api/` | `Glass`, `GlassShape`, `GlassTheme`, `GlassEffect`, `GlassEffectScope`, `GlassEffectContainer`, `GlassDimming`, `GlassForeground`, and the shared `resolveGlassMaterial` helper in `glass_material_context.dart` |
| `packages/ios_liquid_glass/lib/src/material/` | `GlassMaterial`, the tuned `ios27Table` (`ios27.dart`), `ScrollEdgeMaterial`, the tuned `ios27ScrollEdgeTable` (`ios27_scroll_edge.dart`), `GlassMaterialOverride`. Tables are written only by `lab.py tune --write`, never by hand. |
| `packages/ios_liquid_glass/lib/src/accessibility/` | `GlassAccessibility`, the static `ValueNotifier` bridge to the iOS plugin |
| `packages/ios_liquid_glass/lib/src/scroll_edge/` | `ScrollEdgeEffect`, `ScrollUnderBars`, moved from Operator in 2A |
| `packages/ios_liquid_glass/lib/assets/shaders/` | `liquid_glass_geometry_blended.frag` (SDF geometry and blending, cached; since 2A.1 it encodes the signed distance to the silhouette, normalised by `signedDistanceReach` (the larger of the lens thickness and the outline band plus a pixel), and an outline band outside it), `liquid_glass_final_render.frag` (the iOS 27 model: rim-only dispersion, three-point tone curve, tint range, crisp silhouette, outer outline, line and sheen), `sdf.glsl`, `displacement_encoding.glsl`, `fake_glass_color.frag`, `scroll_edge_mask.frag` (replaced `scroll_edge_blur.frag` in 2A.1). `render.glsl` is deleted (2A). |
| `packages/ios_liquid_glass/ios/` | The iOS plugin, reports Reduce Transparency live |
| `packages/ios_liquid_glass/example/` | A plain Flutter app that uses only the package; the lab's Flutter target |
| `packages/ios_liquid_glass/FORK.md` | Every change made to upstream. Upstream is `whynotmake-it/flutter_liquid_glass`, vendored at `ad3bcff` (2026-04-24), MIT, by Tim Lehmann. Keep `LICENSE` and credit forever. |

### Operator's glass layer (moves into the package over 2A and 3)
| Path | What | Moves in |
|---|---|---|
| `lib/core/widgets/glass/glass_surface.dart` | `GlassSurface` (kind, size, variant, pressable), now an adapter over the package's `GlassEffect` | 2A done; a thin adapter until project 3 replaces call sites directly |
| `lib/core/widgets/glass/glass_scope.dart` | `GlassScope`, now an adapter over the package's `GlassEffectContainer` | 2A done; a thin adapter until project 3 |
| `lib/core/widgets/glass/glass_metrics.dart` | Layout constants (tab bar 62, insets and so on) | 3 |
| `lib/core/widgets/glass/glass_tab_bar.dart`, `glass_tab_bar_logic.dart`, `glass_lens.dart` + `shaders/tab_lens.frag` | Tab bar with the minifying lens (tuned on iOS 26.5 in commit `947f03e8e`) | 3 |
| `lib/core/widgets/glass/glass_button.dart`, `glass_bar_item.dart`, `glass_toolbar.dart`, `frosted_header.dart`, `glass_sheet.dart` | Buttons, bar items, toolbar, frosted header, simple sheet | 3 |
| `lib/core/widgets/sheet/app_sheet.dart` | Multi-page sheet (`showAppSheet`, detents fit/medium/large) | 3 |
| `lib/core/widgets/main_widgets/global_appbar.dart` | Operator's nav bar built on the glass layer | stays in Operator, rebuilt on package parts in 4 |
| `lib/core/widgets/glass/lab/**` | Operator's debug glass lab (route `/glass-lab`, reads `Documents/glass_lab/launch.json`). 2A moved the reusable lab scenes into the package's `example/` app; this lab now keeps only the Operator-component scenes (`tabbar.*`, `button.*`, `navbar.*`) that measure Operator's own glass, not the package's | component scenes stay here through project 3/4 |

### The lab (measuring instrument, project 1)
| Path | What |
|---|---|
| `tool/glass_lab/README.md` | How to use the lab (commands below) |
| `tool/glass_lab/scenes.json` | 66 scenes: 60 lab scenes plus 6 Apple app references. The manifest is the source of truth. |
| `tool/glass_lab/noise.json` | Native-vs-native motion noise floor (committed) |
| `tool/glass_lab/native/` | `gen_project.py` → `GlassLab.xcodeproj`. `GlassLab/` is the SwiftUI iOS 27 catalog (bundle `dev.operator.glasslab`). `GlassLabDriver/` is the XCUITest driver. |
| `tool/glass_lab/backdrops/generate.py` | Deterministic backdrops (stripes, photo, white, black, text, scroll), generated into `build/glass_lab/backdrops/` and never committed |
| `tool/glass_lab/harness/` | `lab.py` CLI; `manifest, sim, build, record, analyze, align, metrics, springfit, report, tune, tonefit, probe, flip, material_table` modules; `tests/` (104 unittest tests) |
| `build/glass_lab/` | Build output and runs (git-ignored). The project 1 baseline run lives **in the worktree** `/Users/omaraly/development/AI/Operator-glass-lab/packages/mobile/build/glass_lab/runs/20260927-035111/` (report.html inside); the repeat takes are in `.../runs/20260927-024701/`. |

### Documents
| Path | What |
|---|---|
| `docs/liquid_glass/ROADMAP.md` | This file |
| `docs/liquid_glass/research/apple-inventory.md` | **The definition of "complete"**: 80 Apple Liquid Glass components and behaviours, iOS 27 deltas, numbers ledger, and "behaviours most implementations miss" |
| `docs/liquid_glass/research/flutter-repos.md` | Flutter implementations surveyed, with techniques worth borrowing (liquid_glass_widgets morph engine and blur ramp, liquid_glass_easy adaptivity and metaballs) |
| `docs/liquid_glass/research/non-flutter.md` | Non-Flutter implementations: Kyant0/AndroidLiquidGlass shader, kube.io optics, SDF smooth-union, dual-lobe rim; ranked techniques |
| `docs/liquid_glass/research/operator-audit.md` | Every Operator screen and the component each uses (the input to project 4) |
| `docs/liquid_glass/01-reference-lab/spec.md`, `plan.md`, `baseline.md` | Project 1 |
| `docs/liquid_glass/02a-looks/spec.md`, `plan.md` | Project 2A spec and plan. The plan's header lists 15 rulings that refine the spec, each with its evidence. |
| `docs/liquid_glass/02a-looks/plan-2a1.md`, `results-2a1.md`, `tuning-log-2a1.md` | The 2A.1 fix round: its plan (18 rulings), the measured results against iOS 27, and the tuning log of every `tune` step with its folder. |
| `docs/superpowers/specs/2026-09-23-mobile-liquid-glass-engine-design.md`, `2026-09-24-mobile-glass-chrome-design.md`, `2026-09-24-mobile-sheets-design.md` (+ plans and reports in `docs/superpowers/`) | History: the first engine and chrome work on iOS 26.5, before this roadmap |

### Worktrees
- `/Users/omaraly/development/AI/Operator-glass-lab`: branch `feat/mobile-glass-lab`, project 1. Merged; it can be removed when the baseline run in its `build/` is no longer needed.
- The shared checkout `/Users/omaraly/development/AI/Operator` is used by several sessions at once. Work in a worktree; touch the shared checkout only to merge or push when the user asks.

---

## 3. Environment and tools

- **Machine:** macOS (Darwin 27). Xcode 27.0 (27A266a). Flutter 3.44.5 (CI pins it). Python 3.14 with Pillow and numpy; pytest is not installed, so use unittest. `ffmpeg` is at `/opt/homebrew/bin`. `timeout` exists (Homebrew) but sends SIGTERM; use `kill -INT` for Python cleanup.
- **Simulators:**
  - **"iPhone 17 Pro (iOS 27)"**: UDID `708879DD-8B2A-4547-863F-F49EE1474D8B`, runtime `com.apple.CoreSimulator.SimRuntime.iOS-27-0`. All lab work runs here. The harness finds it by name and runtime.
  - "iPhone 17 Pro" on iOS 26.5: UDID `94D0C207-A90B-4806-BBAB-8AF9B3F16329`. It holds the user's **paired, real Operator**. Do not touch its data; use it only for 26.5 comparisons.
  - The iOS 27 simulator's languages are `en-EG`, `ar-EG`, inherited from the Mac. The keyboard is English with a globe key, and calendars start on Saturday. This is harmless because both apps share it.
- **Building Operator for the simulator:** `flutter build ios` alone **fails under Xcode 27**. Use:
  ```bash
  flutter build ios --simulator --debug --config-only
  xcodebuild build -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath build/glass_lab/flutter IPHONEOS_DEPLOYMENT_TARGET=15.0
  ```
  `tool/glass_lab/harness/build.py` does exactly this.
- **Lab commands** (from `packages/mobile`; see `tool/glass_lab/README.md`):
  - `lab.py build [native|example|operator|all]`, then `lab.py prepare`;
  - `lab.py run <scene|group|prefix|all> [--app native|flutter|both] [--appearance light|dark|both] [--backdrop id] [--a11y none|reduce-transparency|increase-contrast|reduce-motion] [--flutter example|operator]`;
  - `lab.py report [run]`, `lab.py summary <out.md> [run]`, `lab.py repeat [scene]`, `lab.py geometry <scene>`;
  - `lab.py tonefit <run> [--a11y MODE]` (fits the three tone points from native captures alone);
  - `lab.py tune [--pad N]` (searches material parameters against native, `--write` updates the package's tables; `--pad` is the region padding in points, 12 by default, 60 for shadow steps);
  - `lab.py perf [--takes 3] [--scenes a,b] [--a11y MODE] [--out file]` (raster time of `perf.none`, `perf.glass`, `perf.material` and `perf.edge` in the example app);
  - `tune`, `run` and `perf` refuse a stale build: run `lab.py build example` first;
  - `lab.py a11y` (drives all three accessibility modes live against a running app);
  - `lab.py flip [run] --regular run` (checks whether native glass flips light/dark with its backdrop);
  - `lab.py baseline [--flutter example|operator]`, which takes about 4 h, so run it in the background.

  Each case takes about 36 s. A driver failure no longer stalls for 600 s, because the harness passes `-collect-test-diagnostics never`.
- **Gates:**
  - App, from `packages/mobile`: `flutter analyze` must print "No issues found!", and `flutter test` must be green (**2,146** tests after 2B.1);
  - Package, from `packages/mobile/packages/ios_liquid_glass`: `flutter analyze`, `flutter test` (**125** tests after 2B.1);
  - Example, from `packages/mobile/packages/ios_liquid_glass/example`: `flutter analyze`, `flutter test` (**13** tests after 2B.1);
  - `python3 -m unittest discover tool/glass_lab/harness/tests` must print OK (**175** tests after 2B.1).

---

## 4. Gotchas already learned (with evidence)

1. **Dart's `Platform.environment` is empty on iOS** (it logged 0 entries). Launch variables cannot reach Flutter. The lab passes the scene through `Documents/glass_lab/launch.json`, which the harness writes before each launch and the app deletes on start.
2. **Operator's first launch on a fresh simulator shows a notification permission prompt.** The driver dismisses springboard alerts with "Don't Allow" or "Not Now", and only those.
3. **`flutter test` prints a long SkSL error** for `liquid_glass_geometry_blended` ("initializers are not permitted on arrays"). It comes from the renderer shader, is known and harmless, and tests pass.
4. **The simulator records variable-rate video at up to 120 Hz.** Analyse at the real frame timestamps, never at a fixed 60 fps: resampling faked one-frame timing errors.
5. **Test-runner clock times do not map onto video time.** Windows are found from content, by matching the lossless `ready.png` and `settled.png` screenshots.
6. **The Dynamic Island area (top 72 pt) differs** between XCUIScreen screenshots and video, so it is excluded from matching.
7. **XCUITest touch timing jitters.** Motion limits are max(fixed threshold, 1.5 × native-vs-native noise). Still images are exact (0.00 between native takes).
8. **Glass box matching.** Faint glass (dark glass on black, white on white) shows only its contents. The harness therefore matches Flutter's shapes to the native element they overlap, and widens native to its parts, never to a full-screen dim layer. This fix is commit `caf1991ab`. Before it, the baseline reported fake 130–300 pt placement errors.
9. **Spring fits must use each app's full event.** Fits on lag-trimmed curves moved with the alignment (fixed in `caf1991ab`).
10. **Native `.glassEffect(.regular.interactive())` reacts to presses on the iOS 27 simulator only when the glass holds rendered content that the touch hits** (a `Text`, a `Button` label, or `Color.white.opacity(0.001)`). With only `Color.clear` inside, the touch hits nothing in the effect and UIKit's `_UIFlexInteractionPanGestureRecognizer` never joins it, so nothing reacts; that was the old `material.interactive` (`02b-motion/spike-interactive.md`, 58 launches, XCUITest and HID touches alike). Since 2B.1 `material.interactive` holds v13's `Color.white.opacity(0.001)` and reacts: 252.0 × 88.67 → 264.0 × 93.33 pt on `dark-stripes`. `.buttonStyle(.glass)` and interactive `.glassEffect` press identically at the same size.
11. **On iOS 27 the search tab sits inside the tab bar capsule** as a fourth item; on 26.5 it was a separate circle. The native tab bar measures x 20, y 791, 362 × 62 pt.
12. **Flutter's `find.bySemanticsIdentifier` needs `tester.ensureSemantics()`.** Flutter semantics identifiers and labels do reach XCUITest.
13. **Color.clear in SwiftUI is not hit-testable** unless it has a content shape, but a content shape (or a SwiftUI gesture) does not make interactive glass react: only rendered content does (spike v12, v14, v2, v9; gotcha 10).
14. **A scroll view whose content is an `Image.file` has no height at first layout**, so `ScrollController(initialScrollOffset:)` clamps to 0. Jump to the offset after the image's first frame (2A prototype, edge scenes).
15. **Accessibility changes reach a running app live on the simulator:**
    - `defaults write com.apple.Accessibility EnhancedBackgroundContrastEnabled` (Reduce Transparency) and `ReduceMotionEnabled`;
    - `simctl ui <udid> increase_contrast`.
    No `notifyutil` is needed (2A prototype, `lab.py a11y`).
16. **`FrameTiming` raster durations work in simulator debug builds.** Always alternate A/B order.
17. **A linear `lift + gain·L` tone curve cannot fit native glass over both mid-tones and white.** Use three points: black, mid, white.
18. **Detected glass boxes miss light glass on white.** Only the end caps show. Score pinned manifest regions instead.
19. **Name clash:** Operator has a `GlassScope`, so the package's inherited widget is `GlassEffectScope`.
20. **Native `.glassEffect()` glass does not flip light/dark with the content behind it** on the iOS 27 simulator, at 44 or 200 pt (2A flip spike).
21. **The material tables are Dart compiled into the apps.** `tune` must send the whole current table row (edge rows with the `edge.` prefix) merged with each candidate, not just the candidate, or later steps score against the stale compiled seed instead of earlier steps' writes (commit `4b096dd`; Task 11 Group A redo). `tune`, `run` and `perf` refuse a stale build, so rebuild with `lab.py build example` before every step, including after the previous `tune --write` (2A.1).
22. **`tune`'s grid and refinement values can escape a parameter's physical range.** Before commit `380e328` clamped them to a per-field range, an unclamped narrowed rerun wrote values like `toneBlack -0.0688` and `dark.tinted.44`'s `specular -0.1` to the committed tables. Since 2A.1 the start value is sent exactly as committed and only grid and refinement candidates are clamped (`tool/glass_lab/harness/tune.py`, `coordinate_descent`).
23. **Operator's debug lab must give the glass the lab's own appearance, not the app's.** `GlassLabScreen` picked its `DarkSkin`/`LightSkin` from platform brightness but never provided a matching `GlassTheme`, so the glass kept reading the app-root `GlassTheme` (light, from `SkinCubit`'s default) regardless of which appearance the lab was running — dark lab runs measured the wrong, light material rows. Fixed by wrapping the lab scene in its own `GlassTheme` matching the lab's chosen skin (commit `567d0e7`).
24. **Native `.scrollEdgeEffectStyle(.hard)` and `.automatic` are pixel-identical** in the edge scenes on the iOS 27 simulator — own captures, byte-identical (Task 11 Group F review). `automatic` resolves to `hard` here.
25. **`material.regular`'s report `bbox_pt`/`centre_pt` measure the 200 pt glass's shadow extent, not a placement error**, on every backdrop except black. The scene has no `track`, so `analyze.region_for` pads the union of detected boxes and the box detector finds native's soft shadow tail as part of the glass; Task 11's pinned tuning regions (`s88`, `s200` padded by 12) clipped both shadow halos and never saw this residual during tuning (`results.md`, Done item 3). 2A.1's shadow fit and `--pad 60` fixed it on white and text; `material.regular light-photo` still reads `bbox_pt` 2.00 (plain, Reduce Transparency and Increase Contrast runs), and that is a detector flip, not a longer tail: the detector thresholds 3 × 3 block maxima of the difference from bare at `> 6`, Flutter's tail crosses it at rows 684 and 685 pt (maxima 7.00 and 6.67) where native's peaks at exactly 6.00, and the two frames differ there by at most 2 levels per channel (run `20261002-200447`, `results-2a1.md`).
26. **`lab.py run` only records; `lab.py report <run>` analyses.** A run folder with no `report.html` has not been analysed yet — run `report` on it explicitly before reading pass/fail counts.
27. **`ShaderMask` (and any save layer) over a `BackdropFilter` renders no blur under Impeller.** Mask a backdrop blur with `ImageFilter.compose(outer: ImageFilter.shader(mask), inner: ImageFilter.blur(...))`, which the backdrop filter draws source-over (2A.1 prototype `20260930-181321`).
28. **A lab app launched while another lab app is still running can show iOS's "◀ App" back link under the clock.** The harness closes the other lab apps before every capture (2A.1).
29. **Native iOS 27 glass edges:** a crisp silhouette pixel, a dark outline just outside the silhouette that is strongest where the normal is horizontal (none at the top in dark appearance), a bright line and a sheen inside at the top and bottom only, and no inner hairline. The 2A anti-aliasing faded the silhouette pixel to 26 where native reads 95 (2A.1).
30. **Native shadows are one Gaussian:** sigma 17 pt and offset 8 pt at 200 pt (opacity 0.16–0.18 dark, 0.12 light), sigma 6–7 pt at 88, about 2.5 pt at 44. Clear glass casts none (2A.1).
31. **Native capsules have continuous corners.** At 200 pt the flat top starts about 19 pt later than a circle-ended capsule, and the edge sits up to 1.3 pt lower near the arc start; the package's capsule is circle-ended. Not fixed (see §6).
32. **Never `ceil()` a pixel-snapped extent.** Floating point makes 760 px into 760.0000000000001 and the geometry image one pixel too big, which drops the last lit column and row of glass at fractional positions (2A.1, `toPixelCount`).
33. **A `saveLayer` per shadow is expensive under Impeller.** Thirteen offset shadows cut out with `saveLayer` + `dstOut` measured 14.72 ms raster median on the simulator against 12.62 ms with shadows off (2.1 ms); a difference clip measured 13.04 ms (0.4 ms) (2A.1 prototype: 14.72 ms is the prototype's own `Operator-2a1-proto/packages/mobile/build/glass_lab/perf-2a1.json` and 13.04 ms its `perf-2a1b.json`, neither the same file as this branch's `perf-2a1.json`; 12.62 ms is from the prototype's shadows-off probe, recorded in `PROTOTYPE-2A1.md` and `plan-2a1.md` header ruling 16, because its `perf_variants.py` is not on disk).
34. **Native tone points can be read off native captures alone** (`lab.py tonefit`). Tune tone on all five backdrops, never on three: 2A's light rows missed `photo` by 20–35 luma (2A.1).
35. **H.264 rings at every backdrop edge in every video frame** (1–3 px lines of up to 87 levels at the stripe boundaries x = 67, 201 and 335 pt). A glass box found against the bare screenshot with a fixed threshold therefore spans the whole region on `stripes`; `track.py` raises the threshold by the backdrop's own edge strength (2B.1 ruling 1). The cost is a blind band: within ±2 px of a backdrop edge stronger than about 20 levels a dim rim can be hidden (v18's left rim sat under a threshold of 92), so the tracker flags box edges in that band (`edge_in_band`). The cost is larger than the band's width: at the 250 × 44 press's peak both capsule ends sit on stripe boundaries and the box reads 1.7–2.0 pt narrow, so the growth reads +14.33 on `stripes` against +17.00 to +17.33 on `photo` (2B.1 review A2). Fit size laws on `photo`.
36. **The overview window let the app's teardown frame into every capture**, as a final one-frame "event" (the old `tabbar.drag` `event2` noise). Nothing after the last frame that matches `settled.png` is analysed now (2B.1).
37. **A removed widget's render objects are detached before `State.deactivate`, but a `RepaintBoundary`'s layer lives until `finalizeTree`**, so `deactivate` can still snapshot the content's last painted frame with `toImageSync`. A `LayoutBuilder` is the one element that may be marked dirty during build (it rebuilds in layout), which is how the removal ghost appears in the removal frame (2B.1 ruling 15).
38. **The debug JIT stalls the first frame that runs new code.** The first ghost or appearing-glass frame of a launch dropped a frame (a 28–33 ms gap), after which Flutter's first changed frame sat at progress 0.735 against native's 0.963 (prototype run `20261003-042321`). `align.stalls` skips each event's first gap, so it cannot see this; `done_table.py` compares each app's first changed frame instead. The example's materialize scenes run their transition once, quickly, before they are measured, and `cold_probe.py` records the cold first transition for project 5.
39. **`flutter test` has no shader image filter**, so every `LiquidGlassLayer` in a widget test draws `FakeGlass` and no `RenderLiquidGlass` exists. Test render-level glass code by constructing its render objects; the geometry shader cannot be compiled by `flutter test`'s SkSL backend at all (gotcha 3).
40. **Native materialize under Reduce Motion keeps its timing and its blur**; it drops the edge spread that makes the native glass box grow up to 7 pt taller mid-transition, and `.bouncy` overshoots more (2.75% against 1.42% on dark `photo` in this branch's runs `20261004-001040` and `20261004-000223`; the prototype read 2.8–3.8% against 1.4–2.5%), so the package fits a Reduce Motion appear gain per preset (2B.1 rulings 11, 12 and 13).
41. **Flutter has no hook between layout and paint, and a ticker runs before layout.** A drawn rect kept as absolute springs and compared in a paint method goes stale when its glass is only re-composited (a `ListView` item's `RepaintBoundary` on scroll). 2B.1 anchors each drawn rect to the live layout and adds offset springs, compares a size at layout and a position at the first read in a frame, and animates only after a rebuild, a structure change or a transaction (ruling 26).
42. **An `Overlay` cannot take a new entry during build** (it is an ancestor; `setState` would assert), so standalone glass's ghost host is an `OverlayEntry` inserted after the frame in which the first standalone glass is built, not when one is removed (ruling 27).
43. **`lab.py repeat --into` and `lab.py fitvis --out` need absolute paths.** The native driver resolves a relative output path against `/` (`The file “ready.png” doesn't exist` in `driver.log`); a fit lost its first shot to it in the 2B.1 fix wave.
44. **`State.deactivate` runs in the build phase; read no render transform there.** An ancestor can be a fresh render object not yet laid out (a route's `FractionalTranslation` in the first frame), and `getTransformTo` through it asserts, replacing the screen with Flutter's error until the next rebuild. A warm-up transition hides it; `cold_probe.py` found it (2B.1 ruling 31).
45. **`align.extent` returns one box around every changed tile, so anything else that changes on screen joins it.** The touch marker's colour changes stretched `button.press`'s still region from the glass to the bottom-left corner and moved its measures on an unchanged Flutter frame; `extent` now takes `ignore=` and the analysis passes the marker.
46. **A move rule keyed on rebuilds makes app-driven motion lag.** Most `GlassEffect`s are rebuilt on every frame of a `setState` drag or an `AnimatedBuilder`, so "animate a change that follows a rebuild" sprang every frame's step and the glass trailed its layout by up to 130 pt. 2B.1 follows a glass whose layout changes on consecutive frames and animates only a single change (ruling 32); the first frame of a motion still holds, because it cannot be told from a single change.
47. **`simctl io recordVideo` can drop the frames at the start of an animation and flush the rest in a burst.** Three of the 60 noise takes (all take 3, session 2) showed a first-frame gap of 68–407 ms and then frames 1.7–6.7 ms apart; the animation's states matched the other takes' exactly, only their timestamps were squeezed, so a 125 ms 10–90% time read 50, 8.3 and 66.7 ms. `align.stalls` does not see it (it starts counting at the event's second frame) and the touch window comes out zero-length. Such takes were excluded and replaced (`02b-motion/research/execution-2b1/task-9-outliers.md`). Press recordings show the same burst after the still screen before a press, and the recorder can squeeze a whole press into a burst (a 1.0 s press read 0.12 s, its event owned by no step): check every take with the rule and the touch gate before it feeds a floor (2B.1 fix wave: 18 takes excluded).
48. **(Fixed in the 2B.1 fix wave, A9: the cache now rasterises at the phase it is drawn at.) The geometry cache rasterised the matte on the glass's local pixel grid and drew it with nearest sampling, so glass at a fractional x showed its rim up to 0.5 px off.** Which path a frame ends on depends on whether a rebuild follows the first composite's transform event: `material.edge`'s pill (x = 973.164 px) moved left 0.24 px (`-0.245`/`-0.235` least-squares shift, 12 frames) when 2B.1 resolved material during layout and dropped 2A's later forced rebuild. Whole-point scenes are unchanged. Keeping the geometry as a Picture (`render_liquid_glass_geometry.dart:244`) restored 2A byte for byte in a probe (not shipped, perf unmeasured); `02b-motion/research/execution-2b1/task-20d-edge-debug.md`. The snap was 0.24 px by the first results' fit and 0.16 px by the audit's. **A 2A baseline can carry it:** 2A's own `button.press` frames were snapped (rims 0.17–0.50 px off their layout positions, duplicated rows at the top and bottom rims), so after the fix those frames change while the new ones sit on the layout positions within 0.11 px (2B.1 re-audit P2A-3). Read a changed frame against the layout before calling it a regression.
49. **Reboot the simulator before recording native references, and again every few hours.** A simulator that had not been rebooted for nine days held every scripted 1.0 s XCUITest press for 3.26 s (median) and read appear 10–90 % times about 12 ms slower; after a fresh boot every press read 0.98–1.03 s and the timing agreed with 2A. Machine load did not cause it (2B.1 review A10). A boot goes stale within hours of lab use: one read 0.98–1.00 s four hours after it started and 2.0–2.4 s at seven and a half (XCUITest synthesized the 1.0 s press over 2.44 s, `driver.log`). Before a native recording, check that a 1.0 s press reads 0.8–1.2 s; when it does not, `xcrun simctl shutdown` and `boot` the iOS 27 UDID and record again (ruling P2-11).
50. **A killed lab run can leave `simctl io recordVideo` running, and then every later recording fails with `recordVideo did not start`.** Stopping a run mid-take orphans the recorder (parent PID 1). Find it with `ps -axo pid,ppid,command | grep recordVideo` and stop it with SIGINT, which finalizes its file. Stop a lab run only with SIGINT (Ctrl-C), which runs its cleanup and resets the accessibility settings; SIGTERM, `pkill`'s default, skips both (2B.1 fix wave: five still runs lost).
51. **Analysis writes its frame caches into the recordings.** `overview/`, `shapes/` and `marker/` under every take made the 2B.1 noise run 42 GB (and 26 GB for the stale session kept beside it). Check `df -h` before a noise recompute or a fit, and keep 20 GB free.
52. **One 2B.1 noise take must not feed a later plan's floors.** `noise-2b1/takes/material.materialize/light-photo-reduce-motion/2` has its disappear onset read 98 ms before the glass moves (the first changed frame and the next, 53 ms later, both at progress 0.981), so it alone sets that case's disappear `response_pct` (21.4 → 335.7 %), `settle_ms` and `damping` limits. It passes the outlier rule and the touch gate and stays for 2B.1's count, where the case passes 14 / 14 either way (ruling P2-6, re-audit P2A-6). Before 2B.2 or 2B.3 reuses `noise.json`: define an event's onset as its first frame that moves by more than the progress noise and recompute every floor, or move the take to `noise-2b1/excluded/` and record a replacement in that slot after a fresh boot.

---

## 5. Working rules

### Process for every project (the user's standing workflow)
1. **Spec** here: brainstorming, then the user approves the written spec.
2. **Plan** here, **prototype first**. Build a throwaway prototype in the session scratchpad, make it compile and run on the iOS 27 simulator, and run its tests. Then generate the plan with the tested code embedded. That is how project 1's plan reached "every task passed review". The user then approves the plan.
3. **Execution** in a **fresh session**, with `superpowers:subagent-driven-development`, in a new worktree and branch. The user starts it from a handoff prompt that you write, in the style of project 1's.
4. **Review** back here, and never trust green gates alone:
   - diff the branch against the plan's code;
   - rerun every gate;
   - open the actual measurements and screenshots;
   - fix what is wrong, commit, and re-measure.
5. **Merge** into `development` when the user says; push only when asked.

### Hard rules
- **No code comments** in any new or changed code (Swift, Dart, Python, shell, GLSL). Keep existing upstream comments.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `frontend/package-lock.json`. **Never `git stash` in the shared checkout.**
- Work in a worktree. The shared checkout is for merges and pushes only.
- Never pair Operator with a desktop, never enter a password, never touch the user's real sessions or desktops, and never use the iOS 26.5 simulator's Operator data.
- System prompts on the simulator get only "Don't Allow" or "Not Now".
- No downloads and no `pip install`. Python uses the standard library, Pillow and numpy.
- Judge glass against native measurements, never from memory. When a number looks wrong, open the screenshots.
- Keep `docs/liquid_glass/ROADMAP.md` current.

---

## 6. Projects in detail

### Project 1: Reference lab (DONE)
- **Spec, plan, baseline:** `docs/liquid_glass/01-reference-lab/`.
- **Branch:** `feat/mobile-glass-lab`, merged into `development` as `7f74f5a0b` on 2026-09-27. **Not pushed yet.**
- **Delivered:**
  - native iOS 27 catalog (60 scenes);
  - XCUITest driver;
  - harness (still-image measures from lossless screenshots; motion from real frame timestamps, split into events, aligned jointly, springs fitted on full events);
  - Operator debug lab route;
  - `noise.json`;
  - a committed baseline summary (`baseline.md`, 228 cases: 96 fail, 120 missing, 12 references, 0 errors).
- **Review fixes** (`caf1991ab`): element matching, full-event spring fits and joint alignment, count-mismatch ranking, run robustness, `repeat` exit code, no diagnostics stall, native stepper legible in dark mode, Operator lab status bar icons.
- **Open items carried forward:**
  - `material.interactive` has no native motion (decision pending, §1).
  - Flutter scenes exist only for the components Operator already has: tab bar rest/press/drag, `button.press` and `button.styles`, `sheet.detents`, `navbar.inline`, regular/tinted/clear/interactive material, and edge effects. Everything else reads "missing" until the package builds it.
  - Apple prepare taps are not idempotent.
  - `events.count` compares by order only.

### Project 2A: Package foundation + how glass looks (DONE, merged 2026-10-02)
- **Spec:** `docs/liquid_glass/02a-looks/spec.md`. Read it for every detail.
- **Branch:** `feat/ios-liquid-glass-2a`, merged into `development` and pushed on 2026-10-02.
- **What is left:** `docs/liquid_glass/02a-looks/todo-2a2.md` lists every residual by cause (shader work for a 2A.2 round, measurement noise, lab scene, a spec decision, and Operator component items for projects 3 and 4).
- **Plan:** `docs/liquid_glass/02a-looks/plan.md`; the 2A.1 fix round has its own, `docs/liquid_glass/02a-looks/plan-2a1.md`. Plan.md's 13 tasks, in order:
  1. rename;
  2. plugin;
  3. final render model;
  4. API and material;
  5. Operator adapters;
  6. scroll edge into the package;
  7. example app as the lab target;
  8. probes (`perf`, `a11y`);
  9. flip spike and frame cost;
  10. `tune`;
  11. tuning campaign;
  12. verification runs;
  13. documents.

  Its header lists **15 rulings that refine the spec**, each with prototype evidence: a three-point tone curve, a tint brightness range, no geometry change, no flip to build, static pre-scrolled edge scenes, measured foreground colours, and others.
- **Summary:**
  - Rename to `ios_liquid_glass` and make it a plugin with an iOS part for Reduce Transparency.
  - A SwiftUI-mirroring public API (`Glass`, `GlassEffect`, `GlassEffectContainer`).
  - iOS 27 material defaults inside the package.
  - An `example/` app that becomes the lab's Flutter target.
  - A new final-render lighting and colour model: dark hairline plus dual specular, a brightness transfer curve, frosting, quarter-circle bevel, rim-only dispersion, size-dependent material, adaptive shadow.
  - Clear and tinted variants, the scroll edge effect, the accessibility modes, and a spike on light/dark flipping.
  - A `lab.py tune` automatic parameter search.
  - Operator's `GlassStyle`, `GlassSurface` and `GlassScope` replaced by the package API.
- **Prototype (2026-09-27):** worktree `/Users/omaraly/development/AI/Operator-2a-proto` (branch `proto/2a`, uncommitted, throwaway, never merged). `PROTOTYPE-2A.md` at its root has the final gate counts and evidence:
  - package 46 tests, example 6, harness 75, Operator 2,145;
  - builds under Xcode 27;
  - a11y toggles live;
  - perf: new 12.54 ms against old 12.63 ms;
  - no native flip;
  - edge content aligned to 0 px;
  - tone-curve tune: dark regular 88 pt from 17.85 to 7.18 in one pass.
- **Delivered** (Done table from `docs/liquid_glass/02a-looks/results.md`; full evidence there):
  1. Package renamed, plugin live toggles, gates green, no old imports — pass.
  2. Example app — pass.
  3. Material scenes, strict thresholds — 0 of 20 cases pass.
  4. Scroll edge MAD and luminance — 2 of 6 cases pass.
  5. Reduce Transparency and Increase Contrast — 0 of 20 cases pass.
  6. Operator components halve rim and luminance — 18 of 32 measures halved.
  7. Flip spike — no native flip; nothing to build; needs no 2A implementation.
  8. Frame cost within 20% — pass, new 12.36 ms vs old 12.10 ms (+2.2%), measured at `const LiquidGlassSettings()`, not the tuned material.
  9. Documents — done in Task 13.
- **Open items from 2A** (2A's per-scene failure lists in `results.md` are superseded by 2A.1's results below; what still fails is in the 2A.1 subsection):
  - **Operator components** (10 of 32 measures not halved after 2A.1, all `rim_rms` except `navbar.inline light-black` and `tabbar.rest light-stripes` luminance): Flutter's glass icons and button labels pick up Operator's green accent colour where native's stay neutral white or black, Flutter's trailing nav group is a figure-8 where native's is one capsule, and the button is shorter than native's. Operator component code, which project 3 replaces.
  - Native `material.interactive` shows no press reaction on the simulator (pending decision, §1).
  - Swift Package Manager support (plan ruling 13): a follow-up, not enabled globally.
  - Adaptive shadow (plan ruling 15): the shadow is static, since 2A.1 fitted to native's whole tail on `white`, `text` and `photo`; the flip spike built no backdrop readback, so adapting it moves to project 3.
  - `FakeGlass` tone (plan ruling 14): `FakeGlass` keeps upstream's look; it gets the tone curve when a project 3 component needs a non-shader fallback.
- **Rulings:** the plan's 15 header rulings are in `docs/liquid_glass/02a-looks/plan.md`'s header; every controller ruling made during execution is tracked in `docs/liquid_glass/02a-looks/rulings.md`.
- **2A review (2026-09-30):** the code was sound, but the look failed the spec's thresholds, mostly for tuning-setup reasons. 2A.1 (below) is the fix round. Its plan is `docs/liquid_glass/02a-looks/plan-2a1.md` (10 tasks, 18 rulings), its prototype `/Users/omaraly/development/AI/Operator-2a1-proto` (`PROTOTYPE-2A1.md`, uncommitted, throwaway), its results `docs/liquid_glass/02a-looks/results-2a1.md` and its tuning log `docs/liquid_glass/02a-looks/tuning-log-2a1.md`.
- **Next:** the user reviews 2A.1 and its review fix wave and decides the merge (§9).

#### 2A.1: the 2A review's fix round (done; merged with 2A on 2026-10-02)

Same branch, `feat/ios-liquid-glass-2a`. The review's findings, one line each:
1. The rim measure sampled only the centre column; it now scores all four sides of every pinned glass at its exact edge, never looser than 2A's.
2. The edge model could not draw native's edge; it is now a crisp silhouette, a dark outline outside it that is strongest at the curved ends, and a line and sheen at the top and bottom.
3. The tuner never saw native's long shadow tail; the shadow is fitted to it and tuned with `--pad 60`.
4. Tone was tuned on three backdrops and `photo` and `text` were never seen; tone points come from `lab.py tonefit` and every row is tuned on five backdrops.
5. The tinted scene was offset from native (the Run button was 86 × 40 pt, native's is 78 × 37) and lab scenes did not centre on whole points; both are fixed.
6. Clear glass cast a shadow; it casts none. (The dark clear rows kept `shadowOpacity` 0.005 from step C1, a flat-score pick, until the review fix wave copied the light clear rows into them; since then every clear row has `shadowOpacity` 0.)
7. The scroll edge used a sparse 7 × 7 kernel; it stacks real Gaussians behind a small mask shader.
8. The independent code review's bugs and stale document facts: stale builds scored as current, `Glass.clear.tint(c)` tinted under Reduce Transparency and Increase Contrast, `tune` clamped its start into the field's range, so its start score did not describe the committed row and `--write` could rewrite a value nobody had searched, `--a11y` and `--row` mismatches, Operator's bottom edges used the top-tuned row, and stale facts in the package documents (all fixed).
9. Frame cost was measured only at `const LiquidGlassSettings()`; `perf.material` now measures the tuned material, and the shadow cut-out is a clip instead of a `saveLayer`.

**Review fix wave** (2026-10-02, on the same branch). Two read-only reviews of `a4a534a59` drove it: a code review (one latent shader bug, B1, two low findings, B2 and B3, and six document errors) and a measurement audit (every number right, several diagnoses wrong, two cheap fixes).
1. B1 fixed (`7c9793f9a`): both glass passes normalise the signed distance by `signedDistanceReach`, the larger of the lens thickness and the outline band plus a pixel. Glass thinner than its band no longer draws a 0.8-covered, outlined body. No committed row reached the bug: every Flutter frame whose row did not change is byte-identical to the first run.
2. Dark clear glass takes the light clear rows (`501ff476e`, the plan's `copy_row`): native `material.clear` is byte-identical in dark and light.
3. Dark Reduce Transparency saturation retuned below the old grid floor (`fd525eb3b`): 0.325 at 88 pt, 0.25 at 200 pt, 0.425 at 44 pt (was 0.625).
4. Soft light scroll edge: one narrowed pass (`tune/20261002-195020`) kept the committed row; nothing written.
5. Records corrected (`results-2a1.md`, this file, `flip-spike.md`, the package README).

**Results** (`results-2a1.md`; the strict thresholds are unchanged, the rim measure is the new one):

| Done item | 2A | 2A.1 first run | 2A.1 after the review fixes |
|---|---|---|---|
| 3 Material scenes, strict thresholds | 0 of 20 | 9 of 20 | **10 of 20** (`material.regular` 8 of 10, `.clear` 2 of 4, `.tinted` 0 of 6) |
| 4 Scroll edge MAD and luminance | 2 of 6 | 5 of 6 | **5 of 6** (soft light MAD 4.07 > 4.00) |
| 5 Reduce Transparency and Increase Contrast | 0 of 20 | 16 of 20 | **17 of 20** (Reduce Transparency 8 of 10, Increase Contrast 9 of 10) |
| 6 Operator components halve rim and luminance | 18 of 32 | 22 of 32 | **22 of 32** (10 not halved) |
| 8 Frame cost within 20% | +2.2% at default settings | **pass**: `perf.material` 12.659 ms against 12.10 ms, +4.6% (budget 14.52 ms); ratio method +2.6% | not re-measured |

Items 3, 4 and 5 did not reach their targets. Item 6 was never expected to reach 32. Item 8 passes. `perf.edge` (a soft scroll edge) costs 4.976 ms over `perf.none` (5.816 ms raster median); the spec sets no budget for it, so project 5's device check records it.

Done cases still failing, with their cause class from `results-2a1.md`. Classes: (a) tunable, (b) model limitation, (c) lab scene, (d) measurement artifact, (e) Operator component code.
- `material.regular` `dark-text` rim 10.18 (b) and `light-photo` bbox_pt 2.00 (d).
- `material.clear` `dark-photo` and `light-photo` rim 10.92 (a, b possible).
- All six `material.tinted` cases, rim 9.04 to 24.35 (b, with a c part in four).
- Soft light scroll edge MAD 4.07 (a, blocked by the tuner's objective).
- Reduce Transparency `light-photo` bbox_pt 2.00 (d) and `light-text` rim 7.90 (d).
- Increase Contrast `light-photo` bbox_pt 2.00 (d).

**Open items that remain** after the review fix wave, by cause class:

*Model work (shader or material, in the package):*
- **Tinted outline colour and inset** (b). Native's prominent button draws a dark ring about 2 px wide just inside its edge. The tinted block draws a 2 px tint-coloured ring just outside it. Ours is black only and only outside coverage (`liquid_glass_final_render.frag`). It accounts for all six `material.tinted` failures: without the ring and label samples, the Run element is 1.59 to 3.27. Then retune the tinted 44 pt rows and the `light.tinted.88` outline, which D1 never tuned.
- **44 pt sharp-detail term** (b). Under small glass native keeps a sharp, dimmed copy of the backdrop (sharp gain 0.150 against our 0.001 at 44 pt on `dark-text`, audit), and ours is one Gaussian. This fails `material.regular dark-text` (rim 10.18, `s44` right 16.89). It is also visible, but passing, at 44 pt on every backdrop and at 88 pt on `text`, `photo` and `stripes`. Needs an unblurred, dimmed backdrop term with a size-dependent weight, then a retune of the 44 pt rows.
- **Clear photo edge band** (a, b possible). `material.clear` dark and light `photo` rim 10.92, 98% of it in a 3 pt band at the top and bottom edges. Native's line there is 2 px with no halo; ours is lower and wider. The 190 C-group candidates never went below 10.80 (`tune/20261001-195519`, `-203559`, `-212206`). Next: edge light below the C2 grid floors (`specularWidth` 0.5, `sheenWidth` 0.75). If an exponential falloff cannot draw it, the line needs a new shape.
- **Flutter's hairline wraps further round the curved ends** (b, unmeasured). At 40° from horizontal on the 200 pt right end, our darkest edge pixel is 91 against native's 120 on `dark-white`, 50 against 85 on `dark-photo` and 44 against 77 on `dark-stripes` (audit). The rim measure samples only 0° and 90°, so nothing scores it. Candidate: an angular falloff exponent on `mix(outlineTop, outline, |n.x|)`.
- **Hard scroll edge: soft bottom and light divider** (b, passes at MAD 2.07 and 3.47). Native's band ends in a crisp cut followed by a mid-grey divider (145, 130, 119, the same in both appearances). Ours brightens over its last 3.5 pt, and its divider is near-white in dark (219, 223, 227) and lighter in light (184, 181, 177) (audit).
- **Continuous-corner capsule** (b, gotcha 31): needs a new SDF; not built.
- **Edge light is coupled to lens thickness** (b). `edgeDistance` saturates at `thickness`, and line and sheen fade over 0.7 to 1.0 of it (`liquid_glass_final_render.frag` lines 60 and 84). So several light rows' `sheenWidth` exceed their `thickness` (`ios27.dart`: `light.regular.44` 3.5 against 1.0 pt, `light.increaseContrast.44` and `light.reduceTransparency.44` 2.75 against 1.0, `light.clear.44` and now `dark.clear.44` 1.4167 against 1.0). A later lens step silently changes an edge already tuned, and 2B's visibility ramp would scale edge width with lens depth. B1's coverage and outline breakage on thin glass is fixed (`signedDistanceReach`); the lighting coupling is not. The plan mandated this model; it needs a design ruling before 2B/3 (candidate: normalise by a fixed reach, which also answers B3).
- **The scroll edge's first frame or two shows tint without blur** (b). Until the mask program loads and the origin is measured, the fallback is a `ShaderMask` over a `BackdropFilter`, which renders no blur under Impeller (gotcha 27; `scroll_edge_effect.dart`, `_level` fallback).

*Deferred shader findings (code review, low severity, not fixed):*
- **B2.** The outer half of the silhouette pixel (`0 <= sd < 0.5`, still drawn at `coverage = 0.5 − sd`) takes the outline band's encoding, which points 5 × thickness px inward, instead of the edge's refraction (`liquid_glass_geometry_blended.frag`, the `sd >= 0.0` branch). Over `stripes` and `photo` that puts a half-weighted ghost colour on the silhouette pixel. Fix: branch on `sd >= 0.5`. Re-measure before committing, because it changes anti-aliased pixels.
- **B3.** The signed distance sits in the 8-bit blue channel with steps of 2 × reach / 255 px. On thick glass that quantises the one-pixel ramp, the outline and the line: `light.clear.88` at 18 pt (54 px) gets 0.42 px steps. A fixed reach of 8 to 16 px would fix it but changes thick glass and needs a retune. Decide it with the coupling item above.

*Lab scene:*
- **Run glyph** (c). The example's tinted Run button uses `Icons.play_arrow_rounded` at size 20, a play triangle about 10 pt tall, against native's 13.67 pt SF Symbol `play.fill`. Its label ends 2 pt further right and 0.67 pt lower. This drives the Run MAD and one rim sample per tinted case. Fix it in `example/lib/lab/scenes/material_scenes.dart` (a custom triangle or a larger icon, native's gap), not in the package.
- **No measured bottom scroll edge.** No native bottom edge is measured and the lab has no bottom-edge scene, so Operator's bottom edges use `soft` until project 3 measures one.

*Measurement artifacts (harness):*
- **`light-photo` `bbox_pt` 2.00** (d), in plain, Reduce Transparency and Increase Contrast. The box detector thresholds 3 × 3 block maxima at `> 6`. Flutter's shadow tail crosses it at two rows where native's peaks at exactly 6.00, on differences of at most 2 levels (run `20261002-200447`). Fix the detector (luma-based, or hysteresis around the threshold), not the glass.
- **Reduce Transparency `light-text` rim 7.90** (d). One sample of 288 lands on a glyph pixel at the 44 pt pill's right edge; the rim is 4.35 without it (run `20261002-202731`). The same kind of sample crosses Flutter's Run label in the tinted scene. Candidate: mask text out of the rim measure.

*Tuning objective (needs a spec ruling before 2B/3):*
- **Soft light scroll edge MAD 4.07.** `tune`'s summed objective (spec §6) prefers the committed row, at MAD 4.07, luminance 0.00 and score 1.017, over nearby candidates that pass both measures, for example dim 0.315 at MAD 3.999 and luminance 0.11 (score 1.035). Two narrowed passes agree (`tune/20261002-141622`, `tune/20261002-195020`). Candidates for the ruling: rank by failed-measure count first, or add a hinge penalty above the threshold.

*Operator component work (e, projects 3 and 4):*
- **10 of 32 item 6 measures not halved.** All are `rim_rms` except `navbar.inline light-black` and `tabbar.rest light-stripes` luminance. The causes are Operator's own components:
  - its glass icons and labels take the green accent where native's stay white or black;
  - its tab bar's selected pill;
  - its glass button is 45 pt tall against native's 53 to 54;
  - the nav bar's trailing group is a figure-8 where native's is one capsule;
  - its title font is 8 pt narrower.

  `navbar.inline dark-stripes` rim (16.70) is now worse than the baseline (16.37) and 2A (15.48). The `button.press` rims rose from 2A's 9.33 and 7.69 to 10.69 and 8.54.

*Decisions and lab tooling:*
- `material.interactive`: pending decision (§1).
- **Lab driver crashes.** Three `xcodebuild` crashes left a `driver.log` holding only the invocation line, each retried by hand with the identical command: two on `photo` (`tune/20261002-035550`, `tune/20261002-072028`) and one on `stripes` (`tune/20261002-183733`).
- **Freshness guard gaps.**
  - `baseline`, `repeat` and `a11y` lack the guard that `tune`, `run` and `perf` have (`a11y` drives the example app, `lab.py` `cmd_a11y`).
  - The guard proves the build folder is fresh, not the installed app; the prototype installs the same bundle id.
  - Operator's stamped sources omit its path-dependency packages `packages/xterm` and `speech_to_text` (`tool/glass_lab/harness/build.py`, `SOURCES`).


### Project 2B: How glass moves (2B.1 done and merged 2026-10-06; 2B.2 next; spec `02b-motion/spec.md`)

#### 2B.1: the instrument and the first motion
- **Plan:** `02b-motion/plan-2b1.md` (21 tasks; 34 rulings in its header, each with prototype evidence; written, reviewed and fixed twice before execution). Prototype: worktree `/Users/omaraly/development/AI/Operator-2b1-proto`, branch `proto/2b1` (throwaway, never merged).
- **Branch:** `feat/ios-liquid-glass-2b1`. **Results:** `02b-motion/results-2b1.md` (the spec §8 2B.1 Done table, with run folders; still glass against 2A, Operator's scenes included; failures classed by cause; delays, stalls and the cold first transition reported). **To do:** `02b-motion/todo-2b1.md`.
- **Lab:** `track.py` (per-shape boxes against the bare frame with an edge-aware threshold and a flagged blind band; progress, residual and sharpness; topology), `touch.py` (marker), `shapes.py` (teardown cut, events by step, per-shape comparison; an absent measure, an unpaired event or a missing touch fails), `fitvis.py` (per-preset materialize mapping, blur ramp, visibility table, default-spring check), `lab.py measure | reboot | fitvis`, per-case `repeat` over two sessions with static and topology noise, a native build stamp, `reproduce.py`, `still_check.py`, `done_table.py`, `rim_check.py`, `ghost_probe.py`, `cold_probe.py`.
- **Native references:** `material.interactive` (v13), `material.press.*` (N2), `material.materialize.snappy|bouncy` (N5), `material.spacing.*` (N7), Reduce Motion materialize runs (N6).
- **Package:** `GlassAnimation` (SwiftUI's presets), `withGlassAnimation`, `GlassAnimationScope`, `GlassEffectTransition.materialize|identity`; a coordinator per container and per standalone glass (insertion and removal by one rule, removal ghosts with a content snapshot, in the container or the nearest `Overlay`; drawn rects anchored to the live layout, a single change animated after a rebuild or a transaction, app-driven motion followed exactly, never behind a scroll); each glass's material from its drawn size; the fitted `ios27_motion.dart`; the edge light keeps the full thickness while glass materializes.
- **Measured native facts (after the fix wave):** appear progress is the animation's spring, with the spring's overshoot showing at 0.28–0.48 % for `snappy` and 1.80–2.80 % for `bouncy` (3.53–4.09 % under Reduce Motion), lowest on dark `photo`; disappear is the spring's remainder to a power that depends on the backdrop (default 2.45–3.65, `snappy` 2.2–3.1, `bouncy` 2.3–3.05 per case); Reduce Motion keeps materialize's timing and blur; native starts to disappear 27–48 ms and to appear 63–113 ms after a tap, the package within 13–33 ms; the native default spring fits 0.57–0.59 s / 0.94–1.01 in every recording group, SwiftUI's 0.55 / 1.0 within the fit's flat error surface; press growth on `photo` is min(16.82, 1014 / height) pt (RMS 0.67 pt over 72 recordings), the 250 × 44 press +17.00 to +17.33 pt (L1 reads +14.33 on `stripes`, its blind band); native's merge reach is about half its `spacing`.
- **Fitted package values (`ios27_motion.dart`, `fix3-fit.json`):** the backdrop blur ramps as visibility^k with k = 1, chosen on sharpness and per-backdrop progress together over a ramp scan with levels below visibility 0.2 (it wins by 0.11; part 2's k = 0.5 was the old scan grid's artefact); disappear exponents pooled over the backdrops (default 3.1, `snappy` 2.75, `bouncy` 2.7); appear gains fitted on the overshoot peak and pooled over both appearances, because the spread follows the backdrop, not the appearance (`snappy` 0.44, `bouncy` 0.5; under Reduce Motion 0.6 and 0.8).
- **User rulings:** the touch-to-response delay is reported and classed, not copied and not judged; project 5 re-checks it on a device (2B.1 ruling 33). A glass the app moves on consecutive frames follows its layout exactly, and a single change animates (2B.1 ruling 32).
- **Done counts (`results-2b1.md`, after the fix round):** item 4 passes 133 / 168 progress measures normal and 133 / 168 under Reduce Motion at k = 1 (judged and expected 168 each; event and touch gates 120 / 120; 136 / 133 at part 2's k = 0.5 and 129 / 134 at the first results' k = 3, with the failures moving between backdrops with k); item 5 has `missing` 0 and `worse` 0 in all nine scenes, 120 of 124 Flutter frames byte-identical to 2A's (`material.edge`'s 12 again, after the A9 fix; `button.press`'s 4 now on their layout positions, where 2A's were snapped). Gates app 2,146, package 155, example 13, harness 204. What is left is `02b-motion/todo-2b1.md`.
- **Open for 2B.2:** animated container spacing with M4 (2B.1 ruling 29), calibrated on the merge reach above; `.matchedGeometry`, ids, union; whether appearing glass merges with neighbours.
- **Open model items:** native's mid-materialize edge spread (rulings 12, 13); the rim and lens mid-transition (ruling 14) and whatever keeps native's half-way frame sharp on dark `photo` (H1, a hypothesis to test); dark `stripes`' progress lead (H5); moving glass reading more progressed than the static scan at the same visibility (H4, which the static objective cannot see).
- **Review fix wave (2026-10-06):** part 1 fixed the code review's C1–C19 and the audit's tool findings (A1, A4, A6, A8, A9); part 2 re-recorded noise session 1, N1, N2, N5 and N6 after a fresh boot, excluded 18 noise takes by the outlier rule and the touch gate, recomputed `noise.json` (1089 limits moved, all disclosed), re-fitted k, the exponents and the peak gains, and re-ran Done items 1–6. The re-audit of part 2 (P2A-1 to P2A-9) found k = 0.5 to be the ramp scan's grid artefact; the fix round added visibility levels below 0.2, re-fitted (k = 1), re-ran Done item 4, replaced one press noise take outside the touch gate, re-recorded two N1 cases that failed the capture-hole rule, and corrected the documents. Rulings P2-1 to P2-12 in the ledger (P2-9 overturned).

#### What 2B as a whole covers (spec §2, §4)
- **Plans:** 2B.1 (above); 2B.2 merge, split, union and morph; 2B.3 press, Reduce Motion everywhere, frame cost. Each is written prototype-first after the previous one merges.
- **Native facts carried from before 2B.1:** menu open width spring 0.26–0.30 s / 0.74–0.81 (reproduced by the 2B.1 lab); tab bar drag width 0.27–0.34 s / 0.37–0.40; a third-party capture's materialize 250 / 350 ms runs the other way from the lab's 275–292 / 117–133 ms; the glass button press grows +16 pt at 53 pt tall, and plain interactive glass presses like it once it holds rendered content (gotcha 10).
- **Lab scenes for 2B:** `material.interactive`, `material.press.*`, `material.materialize*`, `material.spacing.*`, `material.merge`, `material.union`, `material.morph`; `tabbar.press`, `tabbar.drag` and `button.press` stay project 3 component references.

### Project 3: Every iOS component inside the package (NOT STARTED)
- **Scope:** everything in §7 marked project 3.
  - Move Operator's tab bar (with lens), toolbar, bar items, buttons, frosted header, simple and multi-page sheets into the package as generic components.
  - Build the missing ones: menus that grow from their button, context menu, popover, alert, action sheet or confirmation dialog, switch, slider, segmented control, stepper, pickers, page control, search field and search tab, nav bar with large title and minimization, bottom toolbar, tab bar accessory and minimize, badges, swipe actions, push zoom and sheet zoom transitions, lists and forms styling, progress.
  - Each gets its lab scene implemented in the package's `example/` app and must pass against native.
- **Next:** spec after 2B.

### Project 4: Operator adopts the package (NOT STARTED)
- **Scope:** replace Operator's widgets with the package's on every screen listed in `research/operator-audit.md`. Its biggest gaps:
  - Material dialogs;
  - four plain Material bottom sheets;
  - no menus;
  - Material switches;
  - Material pull-to-refresh and snackbars;
  - `MaterialPageRoute` transitions;
  - opaque settings rows (content stays solid per Apple's rule, but gets iOS 27 list styling).

  Delete Operator's `lib/core/widgets/glass/` leftovers.
- **Next:** spec after 3.

### Project 5: Real-device verification (NOT STARTED)
- **Scope:**
  - run the key scenes on the user's real iPhone (iOS 27);
  - check `.interactive()` (§1 pending);
  - tilt-driven highlights;
  - 120 Hz smoothness and frame cost of the package's shaders.

---

## 7. Component checklist (the definition of complete)

Source: `research/apple-inventory.md` §1, which has 80 rows. The table lists the iPhone-relevant ones. A lab scene id means the native reference already exists in the catalog.

"Package" means the thing exists in the package and matches native, measured.

| Item (inventory §) | Lab scene | Project | Package |
|---|---|---|---|
| Regular glass (2.1) | material.regular | 2A | partly (8 of 10 cases pass — results-2a1.md) |
| Clear glass + 35% dimming (2.2) | material.clear | 2A | partly (2 of 4 cases pass; `photo` rim 10.92 in both appearances — results-2a1.md) |
| Identity glass (2.3) | none | 2A | partly (`Glass.identity` implemented; no native lab scene to measure) |
| Tinted glass (2.4) | material.tinted | 2A | no (0 of 6 cases pass, rim only: native's tinted outline ring and inset that our outline cannot draw — results-2a1.md) |
| Interactive press (2.5) | material.interactive, button.press | 2B | no |
| Lensing / edge refraction (2.6) | material.* | 2A | partly (thickness/refractive index tuned on five backdrops; residuals in results-2a1.md) |
| Specular rim, dark iOS 27 outline, line and sheen (2.7) | material.* | 2A | partly (the iOS 27 edge model; rim passes on regular 9 of 10 cases, clear and tinted residuals — results-2a1.md) |
| Adaptive shadow (2.8) | material.* on white and text | 2A | partly (static shadow fitted to native's whole tail in 2A.1; adapting it is project 3 — plan ruling 15) |
| Light/dark flip of small glass (2.9) | material.flip | 2A (spike) | no native flip on iOS 27 simulator (flip-spike.md) |
| Size-dependent thickness (2.10) | material.regular (3 sizes) | 2A | partly (tuned at 44/88/200 pt; 44 pt glass lacks native's sharp detail, `dark-text` rim 10.18 — results-2a1.md) |
| Vibrant foreground (2.11) | material.* | 2A | partly (`GlassForeground` implemented per plan ruling 7; not separately measured) |
| Materialize / dematerialize (2.13) | material.materialize | 2B | no |
| Container shared sampling and merging (2.14) | material.merge | 2B | partly (renderer blend groups) |
| Union (2.15) | material.union | 2B | no |
| Identity morph (2.16) | material.morph | 2B | no |
| Capsule, fixed, concentric shapes (2.17) | material.shapes | 2A shapes / 3 concentric | partly |
| Scroll edge effect soft, hard, automatic (2.19) | material.edge.* | 2A | partly (5 of 6 cases pass, soft light MAD 4.07 — results-2a1.md) |
| Content-layer materials (2.22) | material.content | 3 | no |
| Floating tab bar + search tab (3.1, 3.5) | tabbar.rest, tabbar.search | 3 | no (Operator GlassTabBar) |
| Tab selection lens (3.2) | tabbar.press, tabbar.drag | 3 | no (Operator lens, 26.5-tuned) |
| Tab bar minimize (3.3) | tabbar.minimize | 3 | no |
| Tab bar bottom accessory (3.4) | tabbar.accessory | 3 | no |
| Prominent tab (3.6) | tabbar.prominent | 3 | no |
| Tab badge (3.7) | tabbar.badge | 3 | no |
| Nav bar, back button, groups (3.10–3.13) | navbar.inline, navbar.groups | 3 | no |
| Large title + subtitle (3.12) | navbar.large | 3 | no |
| Prominent toolbar action (3.14) | navbar.groups | 3 | no |
| Bottom toolbar (3.15) | toolbar.bottom | 3 | no |
| Toolbar morph across push/pop (3.16) | navbar.push | 3 | no |
| Bar button badge (3.17) | navbar.badge | 3 | no |
| Nav bar minimization, iOS 27 (3.18) | navbar.minimize | 3 | no |
| Bottom search field, minimized search (3.20) | search.bottom, search.minimized | 3 | no |
| Search scopes (3.21) | search.scopes | 3 | no |
| Sheets: inset partial, opaque full (4.1–4.2) | sheet.detents, sheet.scroll | 3 | no (Operator AppSheet, opaque, one detent) |
| Sheet zoom from source (4.3) | sheet.zoom | 3 | no |
| Cross-fade sheet, iOS 27 (4.4) | sheet.crossfade | 3 | no |
| Popover from bar button (4.5) | popover.bar | 3 | no |
| Menus growing from their button (4.6) | menu.bar, menu.submenu, menu.pressdrag | 3 | no |
| Context menu (4.7) | contextmenu.card | 3 | no |
| Alerts (4.9) | alert.two, alert.three | 3 | no |
| Confirmation dialog from source (4.10) | confirm.source | 3 | no |
| Push zoom transition (4.11) | push.zoom | 3 | no |
| Glass / prominent / clear buttons, sizes, shapes (5.1–5.4) | button.styles, button.press | 3 | no (Operator GlassButton) |
| Switch (5.5) | toggle | 3 | no |
| Slider (5.6) | slider | 3 | no |
| Segmented control (5.7) | segmented | 3 | no |
| Stepper (5.8) | stepper | 3 | no |
| Pickers (5.9) | picker.menu, datepicker.* | 3 | no |
| Page control (5.10) | pagecontrol | 3 | no |
| Text and search fields (5.11) | textfield | 3 | no |
| Lists and forms (5.12) | list.form | 3 | no |
| Progress (5.13) | progress | 3 | no |
| Swipe actions (5.14) | swipe.row | 3 | no |
| Reduce Transparency (7.1) | a11y runs | 2A | partly (plugin live; 8 of 10 cases pass, both failures measurement artifacts — results-2a1.md) |
| Increase Contrast (7.2) | a11y runs | 2A | partly (9 of 10 cases pass, the failure a measurement artifact — results-2a1.md) |
| Reduce Motion (7.3) | a11y runs | 2B | no |

Out of scope: iPad and Mac items (sidebar, pointer, iPad tab bar), app icons, widgets, system-owned UI (keyboard, share sheet).

---

## 8. Baseline facts to carry forward (project 1, re-analysed after `caf1991ab`)

- **Still-image difference, Operator vs native** (region MAD, target ≤ 4; luminance ≤ 3; rim-profile RMS ≤ 6):

  | Where | MAD | Rim RMS |
  |---|---|---|
  | Typical | ~14 | ~19 |
  | Dark mode | 18 | 18 |
  | Light mode | 12 | 20 |
  | Reduce Transparency | 56 | 31 |
  | Increase Contrast | 22 | 22 |
  | Edge effects | ~50 | >100 |
  | Sheet | 35 | 28 |

- **Placement is right.** On black, where shadows are invisible, glass box centres match native (0.0 pt). Elsewhere Operator's even shadow shifts the box centre by 4–8 pt.
- **What is visibly wrong:**
  - Operator's glass is nearly invisible over black, where native shows a visible grey capsule.
  - The rim picks up background colour; native uses a dark hairline with a bright top highlight.
  - The tint is flat; native reshapes backdrop brightness per mode and size.
  - Shadows are even; native's are offset downward and adaptive.
  - Operator's tab bar footprint is 377 × 82 against native's 362 × 62.
  - Operator's sheet is opaque and doesn't move to the small detent.
  - The nav bar has two circles where native has one grouped capsule.
- **Native springs measured:**
  - menu open: response ≈ 0.28 s, damping ≈ 0.78;
  - tab bar drag width: response ≈ 0.30 s, damping ≈ 0.38.
- **Noise floor (`noise.json`):**

  | Scene | Measure | Value |
  |---|---|---|
  | menu.bar event0 | width peak | 8 ms |
  | menu.bar event0 | width settle | 42 ms |
  | menu.bar event0 | width response | 15% |
  | tabbar.drag event0 | width settle | 133 ms |
  | tabbar.drag event0 | luma response | 44% |

### 2A results (`docs/liquid_glass/02a-looks/results.md`, at the head of branch `feat/ios-liquid-glass-2a`)

- Material scenes (`material.regular`, `.clear`, `.tinted`), strict thresholds: **0 of 20 cases pass**.
- Scroll edge (`material.edge.soft/.hard/.automatic`), MAD and luminance: **2 of 6 cases pass** (`edge.hard` and `edge.automatic`, light appearance only).
- Reduce Transparency: **0 of 10 cases pass**. Increase Contrast: **0 of 10 cases pass**.
- Operator components (`tabbar.rest`, `button.press`, `navbar.inline`), halved-rim-and-luminance criterion: **18 of 32 measures halved** (up from 7 of 32 before the lab appearance fix, commit `567d0e7`).
- Flip spike: no native flip at 44 pt or 200 pt, either appearance — nothing to build.
- Frame cost: new renderer 12.36 ms vs old 12.10 ms raster mean, **+2.2%**, inside the 20% budget — measured at `const LiquidGlassSettings()`, not the tuned iOS 27 material.
- Gates: harness **84** tests OK; package **51**, example **6**, app **2,146** tests; `flutter analyze` "No issues found!" in app, package and example; `grep -rn liquid_glass_renderer` in `packages/mobile` (excluding `build/`, `.dart_tool`) matches only the package pubspec's fork-attribution description line.

### 2A.1 results (`docs/liquid_glass/02a-looks/results-2a1.md`, at the head of branch `feat/ios-liquid-glass-2a`)

After the review fix wave (runs `20261002-200447` to `20261002-210140`; the first 2A.1 run's counts in brackets):
- Material scenes, strict thresholds: **10 of 20 cases pass** (`material.regular` 8 of 10, `material.clear` 2 of 4, `material.tinted` 0 of 6) [9 of 20, clear 1 of 4].
- Scroll edge, MAD and luminance: **5 of 6 cases pass** (soft light-scroll MAD 4.07 > 4.00) [5 of 6].
- Reduce Transparency: **8 of 10 cases pass** [7 of 10]. Increase Contrast: **9 of 10 cases pass** [9 of 10].
- Operator components, halved-rim-and-luminance criterion: **22 of 32 measures halved or within threshold** [22 of 32].
- Frame cost (first run, not re-measured): `perf.material` (tuned material) 12.659 ms raster median against the old renderer's 12.10 ms, **+4.6%**, inside the 20% budget (14.52 ms); ratio method +2.6%; under Reduce Transparency 12.819 ms (+5.9%). `perf.edge` costs 4.976 ms over `perf.none`.
- The rim measure changed (all four sides of every pinned glass), so 2A's numbers are not directly comparable with these.
- Of the 14 failing Done cases, 3 are tunable (class a), 7 need model work (b) and 4 are measurement artifacts (d); the 10 Operator measures are Operator component code (e).
- Gates at the head: harness **104** tests OK; package **67**, example **8**, app **2,146** tests; `flutter analyze` "No issues found!" in app, package and example.

---

## 9. Exact next steps

1. **Write the 2B.3 plan** (spec §4: press M7, Reduce Motion M8 everywhere, frame cost M10, README API docs, Operator press swap if trivial; L4 glow and stretch measures first), prototype-first, from `development` at `9d2b95ca0` or later, and have it independently reviewed before execution (§5). Carry in `02b-motion/todo-2b2.md` and `todo-2b1.md`:
   - the shader seam in `angleSmoothUnion` for three or more different overlapping shapes (fix `h * 0.5` in `sdf.glsl` and the Dart mirror; re-measure merge, morph, union and navbar);
   - per-glass materials in one layer for mixed-size containers (project 3);
   - morph's round-trip motion measure: the net-travel gate in `shapes.compare_key` hides real heart and bolt differences;
   - the morph toggle's swelling, one spring for all arrivals, and the other class (a) causes in `todo-2b2.md`;
   - the A9 re-raster cost while glass slides (the animated perf scene, M10);
   - the flagged morph takes behind the noise floors (E8): third recordings of the four cases that cannot be recomputed without them, if the floors matter;
   - keep the simulator exclusive while recording, and stop a stale boot (gotcha 49).
   - 2B.2's recordings are in `Operator-2b2/packages/mobile/build/glass_lab/` and the prototype worktrees (`Operator-2b2-proto`, `-h4`, `-morph`); archive them as 2B.1's were before deleting anything, with the user's approval.
   - Free disk was about 50 GB on 2026-10-09.

2. **2A.2 (static-look polish)** is a to-do list, not yet planned: `docs/liquid_glass/02a-looks/todo-2a2.md`. The user decides when, likely alongside project 3, since the tinted rings are a prominent-button detail.
3. **Pending user decisions:**
   - native `material.interactive` (§1), which 2B question 1 settles;
   - Swift Package Manager support for the plugin (a follow-up).
