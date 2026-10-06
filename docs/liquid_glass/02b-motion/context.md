# 2B context brief: how glass moves

Read-only research, 2026-10-02, at `development` 7e318a49f. Paths are relative to `packages/mobile/` unless they start with `docs/`.

Run roots used below:
- **GL** = `/Users/omaraly/development/AI/Operator-glass-lab/packages/mobile/build/glass_lab/runs/`. This is project 1: the baseline `20260927-035111`, the repeat takes `20260927-024701`, and the early runs `20260927-01*`/`-02*`.
- **LG** = `/Users/omaraly/development/AI/Operator-ios-liquid-glass/packages/mobile/build/glass_lab/runs/`. This is 2A: `20260930-082046` holds the motion scenes, and `20260930-101816`, `-105500`, `20261002-160207` and `-205855` hold `button.press`.

"Rerun" means I ran the harness's own `analyze.motion()` again on copies of the native captures. It was a pure Python re-analysis, with no simulator. The scripts and `native_motion.json` are in `docs/liquid_glass/02b-motion/research/`. The copied native captures they read were in that session's scratchpad and are not kept, but the original runs are under `packages/mobile/build/glass_lab/runs/` in the worktrees named below.

---

## 1. Native reference available

### Motion scenes (`tool/glass_lab/scenes.json`) and what the native catalog does

| Scene | Steps | Native code | Notes |
|---|---|---|---|
| `material.interactive` | press 1.0 s on `glass`, then pressDrag +60 pt (0.3 s press, 120 pt/s, hold 0.5 s) | `MaterialScenes.swift:65-74`: a `GlassBlock` 250×88, `.regular.interactive()`, on `Color.clear` | **0 native events** in all 4 cases, in both GL `20260927-035111` and LG `20260930-082046` (gotcha 10). It is still usable as a still image (2A `ready` MAD 2.85–14.6). |
| `material.materialize` | tap `toggle`, wait 1.2, tap, wait 1.2 | `:91-111`: `GlassEffectContainer { if shown { GlassBlock(250×88).glassEffectTransition(.materialize) } }`, toggled by **`withAnimation {}` with the default animation** | Native events exist (LG `20260930-082046`, 4 events per case). |
| `material.merge` | tap `merge`, wait 1.5, tap `split`, wait 1.5 | `:113-135`: `GlassEffectContainer(spacing: 40)`, two 80×80 circles in an `HStack`, spacing 80 ↔ 0 under `withAnimation` | 3–4 native events |
| `material.union` | none (rest) | `:137-157`: four 64×64 `.glassEffect()` (default capsule, so circles), spacing 16, `glassEffectUnion` ids "first"/"second", default container spacing | Native's main box is one 146×64 pair (LG union `native_box` [208,419,146,64]). The default spacing does **not** visibly join the 16-pt gap between the unions. |
| `material.morph` | tap `morph`, wait 1.5, tap, wait 1.5 | `:159-193`: `GlassEffectContainer(spacing: 20)`, three 56-pt badges with `glassEffectID`, plus a 56-pt toggle using `.buttonStyle(.plain)` and `.glassEffect(.regular.interactive())`, under `withAnimation` | 3–5 native events |
| `material.flip` | 4 × pressDrag scroll | `:76-89` | 2A spike: no native flip (gotcha 20) |
| `tabbar.press` / `tabbar.drag` | press 1.0 s on "PRs" / pressDrag Agents→Settings at 300 pt/s, hold 0.4 | `NavigationScenes.swift:28-70`: a real `TabView` | System lens (project 3 component) |
| `button.press` | press 0.8 s on `btn.glass`, wait 0.8, press 0.8 s on `btn.prominent` | `ControlScenes.swift:59-76`: `.buttonStyle(.glass)` and `.glassProminent` at `.controlSize(.large)` | **This is the only native press reaction we have.** Rest boxes: glass 138×53 at (132,368), prominent 174×53 at (114,481). |
| others with steps | `menu.bar`, `menu.pressdrag`, `toggle`, `slider`, `segmented`, `sheet.detents`, `popover.bar`, `tabbar.search`, … | | They belong to project 3, but `menu.bar` is the best-measured spring. |

Two catalog facts matter for 2B:
- Every 2B container scene animates with SwiftUI's **default** animation (`withAnimation {}`), not a glass-specific spring. Motor's doc comment states that `Animation.default` is a spring of duration 0.55 with bounce 0 (`~/.pub-cache/hosted/pub.dev/motor-1.1.0/lib/src/motion.dart:367-380`); I have not verified that against Apple.
- `Lab.bare` renders the backdrop only, without lab buttons or labels (`GlassLabApp.swift:24-28`). Box detection therefore also picks up the white lab buttons and the button labels.

### What the lab has measured natively (fits with RMS error under about 0.05 unless noted)

| Motion | Response (s) / damping | Source |
|---|---|---|
| Menu open, width | 0.26–0.27 / 0.78–0.81 (3 takes, light-stripes) | GL `20260927-024701/menu.bar/pair-*` `native_spring` |
| Menu open, width (baseline rerun) | light 0.30 / 0.74; **dark 0.43 / 0.70** | rerun of GL `20260927-035111/menu.bar` (the result.json is "missing", so it holds no fit) |
| Menu close, width | 0.34–0.35 / 0.39–0.41 (e≈0.066) | GL pairs |
| Menu open under Reduce Motion | width 0.53 / 0.74; luma 0.77 / 0.82, so it still animates and is slower | rerun of `menu.bar/dark-stripes-reduce-motion` |
| Tab lens drag start, width | 0.27–0.28 / 0.38–0.40 (e≈0.08) | GL pairs `tabbar.drag` ev0 (ROADMAP §8) |
| Tab lens press-down | width 361→376, peak 378, **overshoot about 13%**, 0.28 / 0.61 (dark) | rerun of `tabbar.press/dark-stripes` |
| Tab lens release | 0.31 / 0.76 (light, e 0.022); 0.31 / 0.70 (`tabbar.drag` light ev2, e 0.014); 0.32 / 0.67 (pair ev1) | reruns and GL pairs |
| Tab drag under Reduce Motion | **width constant at 362**: no lens growth, luma changes only | rerun of `tabbar.drag/dark-stripes-reduce-motion` |
| Button press-down, prominent, width | 174→190–192, **+16–17 pt (×1.09–1.10)**. Fits 0.22–0.47 / 0.55–0.68, but weak (e 0.06–0.083) | `button.press` results, all 6 runs |
| Button press-down, glass | 138→154–155, **+16–17 pt (×1.12)**. Both buttons grow by the same absolute amount, which looks like a fixed outset rather than one scale factor (inference). Rise to 90%: about 68 ms (glass), about 120 ms (prominent). | per-element rerun (`press_elements.py`) |
| Button release, prominent, width | dark 0.18–0.29 / 0.79–0.91; light 0.29–0.34 / 0.61–0.65 (e 0.019–0.049) | GL `035111`, `022300`; LG `101816`, `105500`, `160207`, `205855` |
| Button press, luma | element luma +4.6–5.2 (glass), +17 (prominent), in both appearances | per-element rerun |
| Materialize (appear), glass region | 10–90% **285–320 ms** (2–98% about 530 ms); luma fit 0.34–0.53 / about 1.0 | `materialize_summary.py` on LG `20260930-082046` (all 4 cases) |
| Dematerialize (disappear) | 10–90% **117–167 ms** (2–98% 217–265 ms); luma fit 0.18–0.23 / about 1.0 | same |
| Materialize is not an alpha fade | Mid-transition frames sit 5.2–5.5 MAD off the best alpha mix of bare and full glass, against a 2.4–2.9 rest (H.264) floor. On `photo` they are **less sharp than an alpha mix**: the Laplacian sits 1.1–1.6 below the alpha-mix value at α≈0.5, so this is a blur/lens ramp. | same; on stripes the Laplacian is uninformative |
| Merge / split (region progress) | merge: dark 0.28 / 0.75, light 0.43 / 0.80; split: 10–90% about 67 ms (dark) | `progress.py`, rough |
| Morph expand / collapse | expand 10–90% about 460–550 ms, settle 675–780 ms; collapse 10–90% about 210 ms, 0.77 / 0.73 (e 0.084). Fits are poor. | `progress.py` |

This disagrees with ROADMAP §6. Its "materialize ≈250 ms, dematerialize ≈350 ms" comes from a third-party nav-bar capture (3P-S42). The lab's own scene, under the default `withAnimation`, measures the reverse order: **appear is slower than disappear**. The spec must name which of the two is the target.

### Noise floor

`noise.json` covers only `menu.bar` (event0 width: peak 8 ms, settle 42 ms, response 15%, damping 0.07) and `tabbar.drag` (event0 width settle 133 ms; luma response 44%; event2 response 700%/540%). Event 2 is the **app-teardown frame** paired across takes (see §2), so its limits are meaningless. `material.regular` and `tabbar.rest` are `{}`.

There is **no noise data for `button.press`, `material.materialize`, `.merge`, `.morph` or `.interactive`**. Their limits fall back to the fixed thresholds, which native itself does not meet across runs: dark release response ranges 0.18–0.29. Across sessions, menu-open response goes from 0.27 to 0.30 in light and to 0.43 in dark, which exceeds the 15% noise in `noise.json`. Whether that dark difference is real or an artefact of the measurement is not known.

### Known gap: native interactive glass

Native `.glassEffect(.regular.interactive())` shows no press reaction to XCUITest touches on the iOS 27 simulator, while `.buttonStyle(.glass)` does react (gotcha 10, ROADMAP §1 pending). The "six variants" that were tried are not documented anywhere I could find. The inventory (§2.5, citing APPLY) says custom interactive glass "reacts to touch and pointer the same way" as `.glass` buttons. That supports using `button.press` as the press reference. Not tried: wrapping the block in a `Button` with `.buttonStyle(.glass)`, or `UIGlassEffect.isInteractive` through UIKit.

---

## 2. How the harness measures motion

- **Pipeline** (`analyze.py`, `align.py`):
  - It finds a window from content: the first overview frame (20 fps) that leaves `ready.png`, to the last that matches `settled.png` (`analyze.py:79-96`).
  - It extracts the region's frames at the real video timestamps (`-fps_mode passthrough`, `:46-63`).
  - It splits events on frame-to-frame MAD > 0.5 with a 150 ms quiet gap (`align.py:42-55`).
  - Per frame it records five series: **width, height, cx and cy of the largest connected component** differing from bare by more than 12, plus the **region's mean luma** (`align.py:68-77`). These are resampled to a 120 Hz grid (`:95-97`).
  - Events are paired **by order**, lag-aligned within ±150 ms (`analyze.py:155-190`), and compared on peak and settle time, overshoot, and a spring fit (`springfit.py`: a grid with response 0.05–1.5 s in 0.01 steps and damping 0.1–1.2, step response from rest, accepted at RMS < 0.15).
- **Limits** (`metrics.py:9-19`): time 17 ms, overshoot 2 points of percent, response 5%, damping 0.05. Each is raised to 1.5 × the noise in `noise.json` (`analyze.py:207-213`). Two more checks: `events.count` must match exactly, and `events.native_motion` must be ≥ 1. A spring fit needs travel of at least 4 pt or 3 luma.
- **What it cannot measure today:**
  - **Per-element motion.** It tracks only the largest blob. In the reruns this caused box switching:
    - materialize "width" jumps from the 254-pt glass to the 86-pt Toggle button;
    - merge goes from one 84-pt circle to the merged 164-pt blob, with an overshoot of 22% that is an artefact;
    - morph jumps to the top badge;
    - in `button.press`, the 138-pt glass button never shows up in "width".
  - **Height on stripes.** The blob spans the whole region, so height is stuck at the region height (`button.press` 192, `materialize` 337).
  - **Topology.** It cannot count components over time or measure a neck width, so merge and split timing, and whether a union holds, are unmeasured.
  - **Blur, lensing or highlight ramps** during materialize. Only mean luma is recorded; the alpha-vs-blur evidence in §1 came from ad-hoc scripts.
  - **Glow** (position, spread to neighbours) and **stretch anisotropy**.
  - **Touch-to-response latency.** There are no touch timestamps. `timing.json` records only `start` and `done`, and steps run about 2× their nominal length (button.press 3.7 s nominal → 7.96–8.17 s; materialize 2.9 → 6.0–6.3 s).
  - **Per-scene motion measures.** `manifest.py` allows only static measures in `measures`.
- **Known limits and artefacts:**
  - **Variable-rate video.** Frames are written only when the screen changes. Native `button.press` events contain gaps of 33–53 ms in every run, which is coarser than the 17 ms threshold.
  - **Teardown event.** Every native case ends with a one-frame "event" where luma falls sharply (to 35–146). Video frames up to 50 ms past the last settled match are included, so this event is counted in `event_count`. It inflates counts and `noise.json` event2.
  - **Order-only event pairing.** Native `button.press` yields 5–6 events against Flutter's 4 in every run, so later events compare the wrong pairs.
  - **Press fits.** A press-hold-release pulse is split into two step events, which works only if the hold exceeds 150 ms. Press-down fits are poor (e ≈ 0.07–0.08).
  - **Flutter runs as a debug JIT build on the simulator** (`build.py:17-20,55-60`; no profile or release build exists for the simulator), so a stall can look like spring error. The report lists Flutter gaps over 25 ms.
  - **No animated-geometry perf scene.** `perf_scenes.dart` animates only the backdrop under static glass.

---

## 3. What the package can animate today (`packages/ios_liquid_glass/lib/src/`)

- **`GlassGlow` / `GlassGlowLayer`** (`glass_glow.dart`):
  - A radial gradient (`BlendMode.plus`, `:288-309`) at the touch point.
  - Radius and alpha move on `Motion.interactiveSpring` on touch and `smoothSpring` on release (`:169-184`); offset uses `smoothSpring(1 s)` (`:124-132`).
  - Every `LiquidGlass` wraps its child in its own `GlassGlowLayer`, inside the shape clip and under `Opacity(visibility)` (`liquid_glass.dart:284-288`). **The glow therefore cannot spill onto neighbouring glass.**
  - It ignores Reduce Motion.
- **`LiquidStretch`** (`stretch.dart`):
  - `interactionScale` 1.05, `stretch` 0.5, `resistance` 0.08 (`:19-21`).
  - Scale moves on `smoothSpring(300 ms)` (`:83-85`); drag offset on `interactiveSpring`, then `bouncySpring` on release (`:93-95`).
  - `RawLiquidStretch` applies a volume-corrected anisotropic `Matrix4` (`:220-274`).
  - Used nowhere in Operator or the example. It ignores Reduce Motion.
- **`GlassDragBuilder`** (`internal/glass_drag_builder.dart`) is a Listener- or GestureDetector-driven drag offset with cancel handling.
- **Blend groups:**
  - `LiquidGlassBlendGroup(blend: 20)` (`liquid_glass_blend_group.dart:22`), at most **16 shapes** (`:35`).
  - Shapes merge through a polynomial smooth-min `smoothUnion(d1,d2,k)` with k = blend × DPR (`sdf.glsl:44-50`, `:75-104`).
  - **Semantics differ from SwiftUI `spacing`.** At the midpoint of a gap g, sd = g/2 − k/4, so shapes fuse only when g < k/2. `blend` 20 fuses gaps under 10 pt; SwiftUI starts merging at `spacing`.
  - Changing `blend` forces a geometry rebuild (`:189-193`).
  - There is no union-by-id and no identity morph.
- **`visibility`** (`liquid_glass_settings.dart:72-191`):
  - **Scales:** glass colour alpha, **thickness (lens)**, blur, chromatic aberration, light intensity, ambient, saturation (toward 1), toneBlack/Mid/White (toward identity), outline, outlineTop, specular, sheen. The shadow's blur and alpha also scale (`glass_shadow.dart:105,125,128`), and the child fades through `Opacity(visibility)` (`liquid_glass.dart:284`).
  - **Does not scale:** refractiveIndex, outlineWidth, specularWidth/Power/Fill, sheenWidth, tintBlack/White, lightAngle.
  - Thickness reaches 0 at visibility 0, so the geometry pass draws nothing (`liquid_glass_geometry_blended.frag:37`). This makes visibility a ready-made materialize knob.
  - The edge line and sheen fade over 0.7–1.0 × thickness (`liquid_glass_final_render.frag:60-61,84`), so ramping visibility also narrows the edge light (ROADMAP §6 "Edge light is coupled to lens thickness").
  - `copyWith(blend:)` is a dead parameter.
- **`Glass.interactive`** is stored and part of `==` (`api/glass.dart:16-29`), but **nothing reads `isInteractive`** (grep over lib, example and Operator).
- **`GlassEffectContainer`:**
  - `spacing = 20`, which maps directly to `blend` (`api/glass_effect_container.dart:9,26`).
  - One material is resolved at a fixed `side = 88` for every member.
  - A child with a different `Glass` gets its own layer and cannot merge (`api/glass_effect.dart:57-66`).
- **Identity glass:** `GlassEffect` returns the bare child for `Glass.identity` (`glass_effect.dart:47`). A `GlobalKey` on the child (`:31,42`) keeps its state across a switch to or from glass. The switch is instant, with no animation.
- **Size-dependent material** re-resolves after a post-frame size report when the shorter side changes by at least 0.5 pt (`glass_effect.dart:34-38,97-112`). That means one frame of lag and one rebuild per frame during a layout-size animation. A `Transform`-based press scale never re-resolves the material.
- **`motor` 1.1.0** (transitive, via the package pubspec) supplies `CupertinoMotion` presets: smooth 0.5 s / bounce 0, snappy 0.5 / 0.15, bouncy 0.5 / 0.3, interactive 0.15 / 0.14, and a default of 0.55 / 0 that motor says matches iOS `Animation.default`.
- **Geometry cost while animating:**
  - Any change to a shape's bounds or transform, to `effectiveThickness`, to `refractiveIndex`, `outlineWidth` or `blend` rebuilds the geometry (`render_liquid_glass_geometry.dart:69,204-214,414-420`).
  - A changing geometry is redrawn as a shader picture every frame. It is rasterised to a cached image only once a frame arrives with no change (`:211`).
  - Every 2B animation therefore pays the geometry shader each frame, and this has never been measured.
- **Operator's existing motion:**
  - `_PressLift` (`lib/core/widgets/glass/glass_surface.dart:56-95`): `AnimatedScale` 1.08 over 260 ms with `Cubic(0.34,1.4,0.64,1)` (`app_themes/app_motion.dart:20,122`), plus `GlassGlow` at white α 0.35. It is disabled under `disableAnimations`. Its fitted spring in `button.press` is 0.05–0.13 / 1.1–1.2 against native's 0.18–0.47 / 0.55–0.91.
  - Tab bar (`glass_tab_bar.dart:26-48,131-182`):
    - lens follows at ω 38 (critically damped) and travels at ω 18 / ζ 0.8;
    - **velocity-driven** squash (0.00028 per pt/s, max 0.12, ω 14 / ζ 0.2);
    - lift 300 ms on the overshoot cubic, lens ×1.115 / ×1.13, press ×1.053;
    - Reduce Motion means no lift and an instant snap. Hand-integrated spring at 1/240 s (`glass_tab_bar_logic.dart:38-58`).

## 4. Example app's motion scenes today

They render static images only (`example/lib/lab/scenes/material_scenes.dart`). `LabButton` has `onTap: null` (`lab_parts.dart:67-89`), so taps do nothing, and nothing in the example animates.
- `material.interactive` is a static 250×88 `Glass.regular.interactive()` (`:51-54`).
- `material.materialize` is a static block plus a dead Toggle (`:74-78`).
- `material.merge` is frozen in the split state with an 80-pt gap, `spacing: 40` (`:79-98`).
- `material.morph` shows only the 56-pt button, with no badges (`:118-130`).
- `material.union` has **4 `rect(20)` items in one container with no union groups**, where native uses circles in two unions (`:99-117`). That is a lab-scene mismatch: 2A `ready` MAD 12.2–13.9, rim 10.5–33.8.

In 2A all of them read Flutter event count 0 (LG `20260930-082046`). There is no `perf` scene with animated geometry. The Operator lab owns `tabbar.*` and `button.press`.

## 5. Research techniques worth borrowing

- **Materialize by ramping lensing, blur and highlight, fading only the content, never the glass alpha.** Sources: inventory §2.13 and §10 item 11, and UIKit's "prefer setting effect over alpha". The 3P-S42 numbers are about 250 ms in and 350 ms out, with "content blurs first, glass dissolves after". The lab measures the reverse in its own scene (§1).
- **Popover blur ramp:** sigma goes from 0 to full over about 260 ms on a separate monotonic controller, so an overshooting spring does not make the blur "breathe" (`flutter-repos.md:105-112`, ranked 2).
- **liquid_glass_widgets morph engine:**
  - two blobs (an anchor that shrinks while the body travels a J-curve), one underdamped spring at **ζ ≈ 0.73**;
  - the SDF blend strength is *derived* from the spring state;
  - a `MorphPhase` state machine;
  - critically damped or instant under `disableAnimations` (`flutter-repos.md:86-93`, ranked 4).
- **Acceleration-driven squash** (liquid_glass_easy): a 0.3 s window, a clamp, and an eased response, so nothing deforms at constant speed (`flutter-repos.md:244-253`). Operator's tab bar squash is velocity-driven.
- **Metaball merge** with a dFdx gradient on Impeller and analytic gradients on Skia; pack uniforms in `mat4`s, not arrays (`flutter-repos.md:230-243`; `non-flutter.md` ranked 8).
- **Press:**
  - scale *up* (not down), bounce, a glow starting under the finger that spreads to neighbouring glass in the same container, gel stretch while dragging, spring back with overshoot (inventory §2.5, §10 item 13);
  - measured by 3P-S42: brightening about +15 luma (light), lift 150 ms, collapse 60 ms;
  - the "1.1" scale in circulation comes from sample code;
  - a pressure-meniscus displacement term (`non-flutter.md` ranked 9) and rdev's gel squash and elastic translation (ranked 10).
- **Tab lens imitation values** (3P-S41, *imitation*): squash ±0.3 over a 0.3 s window, lift spring 0.4 s / 0.7, drop 0.5 s / 0.8 (inventory §3.2).
- **Interaction-coordination primitives** from liquid_glass_widgets: an `InteractionNotification` "smart silence" so a touched child suppresses its parent's scale and glow, and `glass_isolation_scope` (`flutter-repos.md:155-163`).
- **Reduce Motion** (inventory §7.3): "disables any elastic properties"; the HIG says avoid animating into and out of blurs, so use fades; no bounce, no stretch, morphs become cross-fades. Native evidence: under Reduce Motion the tab lens does not grow, and the menu still opens, more slowly (§1). "Reduce Bright Effects" (iOS 26.4) tones down the press flash; Flutter cannot read it.
- **Size-dependent material during a morph:** glass "thickens" as it grows (inventory §2.10, §10 item 7). Interpolate the material by the animated size.

## 6. Risks and open questions the spec must settle

1. **The press reference** (pending decision, ROADMAP §1). Options:
   - (a) adopt `button.press` (`.buttonStyle(.glass)` / `.glassProminent`) as the reference for `Glass.interactive()`, keeping `material.interactive` as a still image;
   - (b) first try a `Button`-wrapped or UIKit `isInteractive` native variant;
   - (c) defer to project 5.

   Native evidence is limited to width, luma and timing. There is no height (stripes), no glow image, and no drag stretch, because the `material.interactive` drag never moved natively.
2. **Measurement feasibility.** Before any Done criterion can be met, the harness needs:
   - per-element tracking (pinned regions or matched components);
   - a topology series (component count, neck width) for merge, split and union;
   - a materialize progress and blur measure (alpha-projection residual and Laplacian, as in §1);
   - teardown-event exclusion;
   - better event pairing than order alone;
   - `lab.py repeat` on every 2B scene for a noise floor.

   Decide whether thresholds stay at 17 ms / 5% / 0.05 when native runs differ by more than that across sessions (the dark-vs-light release damping split is unexplained).
3. **The target timing for materialize.** Either the lab's own `withAnimation` scene (appear ~300 ms 10–90%, disappear ~120–170 ms) or 3P-S42's 250/350 ms. Decide whether the package mirrors SwiftUI's `Animation.default` (motor 0.55/0) as the default glass animation.
4. **Visibility as materialize** couples edge-light width to lens thickness (ROADMAP §6, B3). Rule on a fixed reach before 2B tunes any ramp. Also decide which fields ramp, because refractiveIndex, outlineWidth and specularWidth do not.
5. **Blend semantics.** Calibrate `spacing` → `blend` (smooth-min fuses only gaps < k/2) against `material.merge` and native's no-merge at 16 pt in `material.union`. Union-by-id and identity morph need new mechanisms. The 16-shapes-per-group cap matters for morph stacks.
6. **Frame cost of animated geometry.**
   - Every animated frame of scale, stretch, merge, morph or materialize reruns the geometry shader with no cache (`render_liquid_glass_geometry.dart:204-214`).
   - It adds an `Opacity` save layer on the content, and a post-frame rebuild when the size changes.
   - A new perf scene with animated glass is needed, with a budget. The 2A item-8 method is to alternate A/B, as in gotcha 16.
   - Real 120 Hz smoothness belongs to project 5.
7. **Glow spreading to neighbours** needs a container-level glow layer. Today's glow is per shape and clipped (`liquid_glass.dart:284-288`).
8. **Reduce Motion measurement.** The harness can run `--a11y reduce-motion` live (gotcha 15). The package reads `reduceMotion` (`glass_accessibility.dart:12-28,75`), but `GlassGlow` and `LiquidStretch` ignore it. Native Reduce Motion references exist only for `tabbar.drag`, `menu.bar` and `sheet.detents`. Add `--a11y reduce-motion` runs of `button.press`, `material.materialize` and `material.merge`.
9. **Example scenes must become live.** Wire `LabButton.onTap`, use real state for materialize, merge and morph, and fix the union scene (circles, two union groups).
10. **Scope boundary with project 3.** The tab lens, menus and `button.press` are Operator or project-3 components. Decide what 2B owns: package primitives such as `Glass.interactive` behaviour, materialize transitions, the container morph and spring constants. Decide also whether Operator's `_PressLift` and the tab bar are retuned in 2B ("re-tuned springs for any glass the package owns", ROADMAP §6).
