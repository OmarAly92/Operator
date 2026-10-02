# Project 2B: how glass moves

Date: 2026-10-03. Status: **written for the user's review; not approved yet.**
Master roadmap: `docs/liquid_glass/ROADMAP.md`; read it first, especially §5 (working rules) and the gotchas.
Evidence: `context.md` (research brief, cited by file:line and run folder) and `spike-interactive.md` (the native interactive glass spike), both in this folder. Every decision below was taken one question at a time with the user; `brainstorm.md` records each answer.
Measuring instrument: `packages/mobile/tool/glass_lab/` (project 1, extended by 2A).

Paths are relative to `packages/mobile/` unless they start with `docs/`.

---

## 1. Why

The goal is one Flutter package, `ios_liquid_glass`, identical to native iOS 27 Liquid Glass and usable in any Flutter app (ROADMAP §1). 2A made still glass look like native. Nothing in the package moves like native yet:
- `Glass.interactive()` is stored but nothing reads it (`lib/src/api/glass.dart:16-29`);
- glass appears and disappears instantly; there is no transition;
- `GlassEffectContainer(spacing:)` maps to a smooth-min `blend` that fuses only gaps under half its value (`lib/src/liquid_glass_blend_group.dart`, `lib/assets/shaders/sdf.glsl:44-50`), where SwiftUI starts merging at `spacing`;
- there is no union and no identity morph;
- the press glow is drawn inside each shape and clipped to it (`lib/src/liquid_glass.dart:284-288`);
- the example app's motion scenes are still images: taps do nothing (`example/lib/lab/lab_parts.dart:67-89`).

The lab cannot yet measure most of 2B either (`context.md` §2): it follows only the largest blob, cannot see topology or blur, counts the app-teardown frame as an event, pairs events by order, and has no noise floor for any 2B scene.

What native does, as measured so far:

| Motion | Native | Source |
|---|---|---|
| Plain interactive glass press, 250×88 | uniform scale, +12.0 / +4.67 pt (dark), +12.67 / +5.33 pt (light); luma +17.7 / +19.0; glow to 90% in 27–55 ms, size to 90% in 188–210 ms; release: size settles in 123–157 ms, glow in 387–413 ms with a one-frame drop about 400 ms after release | `spike-interactive.md`, v13 |
| Press scale against size | glass up to about 60 pt tall grows about 17.5 pt in width whatever its width; taller glass grows about 1100 / height pt (inference from six sizes) | `spike-interactive.md`, size table |
| Slow press-drag (+60 pt at 120 pt/s) | no movement, no stretch; the glow dims | same |
| Neighbour 10 pt away in a `spacing: 20` container | only the pressed shape scales; no glow on the neighbour | same, v15 |
| Materialize (appear), default `withAnimation` | 10–90% in 285–320 ms; not an alpha fade, a blur and lens ramp | `context.md` §1 |
| Dematerialize (disappear) | 10–90% in 117–167 ms | same |
| Merge, region progress | dark 0.28 s / 0.75, light 0.43 s / 0.80 (rough) | same |
| Morph | expand 10–90% about 460–550 ms; collapse about 210 ms (poor fits) | same |
| Menu open (a spring the lab measures well) | response 0.26–0.30 s, damping 0.74–0.81 | same |

## 2. Scope

**In:**
- **L. Lab upgrades:** per-shape tracking, topology, materialize progress and blur, glow and stretch measures, touch timestamps, teardown cut, per-scene motion measures, noise floors.
- **N. Native references:** the fixed interactive scene, a press size series, drags, neighbours, materialize under other animations, container spacing calibration, Reduce Motion runs.
- **M. Package motion:** the coordinator, animations and springs, materialize, merge and split, union, morph, press, Reduce Motion, the public API, frame cost, live example scenes.

**Out:**
- Components: the tab bar lens, menus and a ready-made glass button belong to project 3. `button.press` stays a component reference for project 3.
- Operator rollout. Operator's `_PressLift` (`lib/core/widgets/glass/glass_surface.dart:56-95`) moves onto the package press in 2B only if the swap is trivial; otherwise project 3 or 4. The tab bar stays as it is.
- Real-device smoothness at 120 Hz and anything only a device can show: project 5.
- The static-look residuals in `docs/liquid_glass/02a-looks/todo-2a2.md` (2A.2).
- Android visuals. Android must still compile.

## 3. Decisions (settled with the user, 2026-10-03)

1. **Press reference:** native plain interactive glass, made measurable by the spike. `material.interactive` gets v13's content, `Color.white.opacity(0.001)`, in place of `Color.clear`; its still image is byte-identical (verified on dark-stripes: max difference 0). No fallback to `.buttonStyle(.glass)` is needed.
2. **Materialize timing:** the package default is SwiftUI's default spring. The lab's native `withAnimation` measurements are the target. Native materialize is also recorded under `.snappy` and `.bouncy`, so the progress mapping is checked under app-supplied animations.
3. **Boundary with project 3:** 2B builds package motion primitives only (§2).
4. **Lab first:** the lab upgrades are 2B's first tasks; glass work starts only after them.
5. **API:** SwiftUI names with implicit animation (§7.9). Names are fixed once and never renamed.
6. **Reduce Motion:** measure native under Reduce Motion and copy it. Apple's guidance is only the starting guess.
7. **Frame cost:** an animated-glass perf scene within 20% of the still-glass scene.
8. **Architecture:** a motion coordinator inside each glass container (approach 1 of three proposed).
9. **Stretch and glow spreading (a2):** built only where native shows them, and copied exactly. Nothing is built from Apple's description alone.
10. **Work is split into three plans** (§4).

## 4. Order of work

One spec, three plans. Each plan is written prototype-first, executed by a fresh **local** Claude Code session on the Mac (subagent-driven, in its own worktree and branch), reviewed here with an independent code review and an independent measurement audit, fixed, and merged only when the user says. The next plan is written only after the previous one is merged, because its measurements are the next plan's baseline.

- **2B.1, the instrument and the first motion:** L1–L3 and L5–L8; native references N1, N2, N5, N7, and N6 for the materialize scenes; the coordinator (M1, M2) with materialize (M3) as its first feature; live materialize scene.
- **2B.2, merge, split, union and morph:** N6 for `material.merge` and `material.morph`; M4–M6; live merge, union and morph scenes; the rebuilt union scene.
- **2B.3, press and the finish:** L4 and native references N3, N4, and N6 for `material.interactive` and the drags, first; press (M7); Reduce Motion everywhere (M8); frame cost (M10); README API docs; Operator press swap if trivial.

Spring constants always start from native's fitted numbers, then are verified in the lab.

---

## 5. Part L: lab upgrades

Every upgrade lands with unit tests on synthetic frames and must reproduce known native numbers from existing recordings, within noise, before it judges anything (§8, 2B.1). The fixed thresholds in `tool/glass_lab/harness/metrics.py:9-19` stay as they are; new measures get the fixed thresholds below.

### L1. Per-shape tracking

- A scene's `track` becomes a list of named regions (a single string stays valid and means a list of one). Each tracked shape is measured inside its own pinned region, never as the largest blob of the frame.
- Per shape and frame: width, height, centre x and centre y of the glass box, and mean luma.
- The box is found against the bare frame inside the region, and must work on `stripes`, where today's height is stuck at the region height (`context.md` §2). The spike's method (3 × 3 smoothed max-channel difference, a minimum run of pixels per row and column, `docs/liquid_glass/02b-motion/research/spike-interactive/probe_analyze.py`) is the starting point.
- Proof: reproduces v13's +12 / +4.67 pt (dark-stripes) and the short-glass +17.5 pt width growth, and today's `button.press` widths (138 → 154–155, 174 → 190–192), from existing runs.

### L2. Topology

- Per frame, inside a named region: the number of separate glass components, and the narrowest neck between them (the smallest cross-section of the glass mask on the segment joining their centres), in pt.
- Events: join time (count goes 2 → 1) and split time (1 → 2).
- Fixed thresholds: component count must match native on every compared frame except within one frame of a join or split; join and split times 17 ms; neck width RMS over the event 1 pt.

### L3. Materialize progress and blur

- Per frame, inside the shape's region: progress p, the α that makes `α · full + (1 − α) · bare` closest to the frame; the residual MAD off that alpha mix; and the Laplacian sharpness of the frame minus that of the alpha mix at the same p.
- Measures: progress 10–90% time and settle time (17 ms), overshoot (2 points of percent), the progress curve's RMS against native after lag alignment (0.05), and the sharpness difference at p ≈ 0.5 (1.0).
- Proof: reproduces appear 285–320 ms and disappear 117–167 ms, and the "not an alpha fade" result (mid-transition residual 5.2–5.5 MAD against a 2.4–2.9 rest floor), from LG `20260930-082046`.

### L4. Glow and stretch (built at the start of 2B.3)

- Glow: luma rise in the pressed shape's region and in each neighbour's region; glow rise time and fade time.
- Stretch: width-to-height ratio against rest, and centre offset, during drags.
- Fixed thresholds: luma 3; ratio 0.01; centre 1 pt; times 17 ms.

### L5. Touch timestamps

- Both apps paint a touch marker in scenes that declare touch steps: an 18 pt square at (16, 662) pt, black at rest, red on touch-down, green on move, blue on touch-up, as the spike's `TouchProbe.swift` does (`proto/2b` 5999b4412). It never overlaps a measured region, and scenes without touch steps do not show it.
- The harness reads touch phases from the video, so touch times share the video's clock.
- Events are paired by the step that caused them, not by order. Touch-to-response delay is a measure (17 ms).

### L6. Teardown cut

Nothing after the last frame that matches `settled.png` is analysed. The app-teardown frame is never an event.

### L7. Per-scene motion measures

A scene declares the motion measures it is judged on in `scenes.json`, validated by `manifest.py` like the static `measures` list.

### L8. Noise floors

- Five native takes of every 2B scene and case, in two separate sessions with a simulator reboot between them, through `lab.py repeat`.
- `noise.json` gains a per-measure noise for each. Every limit is max(fixed threshold, 1.5 × noise).
- The existing `tabbar.drag` event-2 entry, which is the teardown frame (`context.md` §1), is removed.

## 6. Part N: native references

All native scenes live in `tool/glass_lab/native/GlassLab/`; the spike's probe scenes on `proto/2b` (`ProbeScenes.swift`) may be ported.

- **N1. `material.interactive`:** v13's content in `InteractiveScene` (`MaterialScenes.swift:65-74`). Still reference unchanged; press measurable.
- **N2. Press size series:** at least six interactive shapes from 44 to 200 pt tall, including the spike's 58 pt circle, 138×53, 250×44, 250×88 and 360×200. They pin the scale law.
- **N3. Drags:** press-drag at 120 pt/s, at 600 pt/s or faster, and a drag that ends 40 pt outside the glass.
- **N4. Neighbours:** two interactive shapes touching (gap 0), merged (gap 10 in `spacing: 20`, as v15) and apart (gap 40 in `spacing: 20`); press one.
- **N5. Materialize under other animations:** `material.materialize` driven by `withAnimation(.snappy)` and by `withAnimation(.bouncy)`, as two new scenes.
- **N6. Reduce Motion:** `--a11y reduce-motion` runs of `material.interactive`, the three materialize scenes, `material.merge`, `material.morph`, and the N3 drag scenes.
- **N7. Container spacing calibration (still images):** pairs of 80 pt circles at gaps 0, 4, 8, 12, 16, 20, 24, 32, 40, 48 and 60 pt, one scene in a default `GlassEffectContainer()` and one in `spacing: 40`. They give native's default spacing and the neck width against gap.

Every scene gets noise floors (L8).

## 7. Part M: package motion

### M1. The coordinator

- Every `GlassEffectContainer` owns one coordinator. A `GlassEffect` outside any container gets a private one, so standalone glass animates too.
- Each glass widget registers its layout rect (where Flutter laid it out, in container coordinates), shape, glass id, union id, transition and interactive flag. On every rebuild the coordinator compares the new layout with what is drawn and animates the difference.
- Animated per glass widget: the drawn rect (springs from the old layout rect to the new one), visibility, press scale and glow. Animated per container: spacing.
- Content follows the glass: each widget's content is painted translated to follow its drawn rect. Hit testing uses the final layout, as SwiftUI's does.
- **Removal animates:** when an app removes a glass widget, the coordinator keeps drawing that glass while it dematerializes or morphs into its matching id, with a fading snapshot of its content. This is the riskiest piece and is prototyped first. If the content snapshot cannot be made reliable, the fallback is: the glass animates out and its content disappears at once. The plan records which one the prototype proved.
- **Interruptible:** a change during an animation retargets every spring from its current value and velocity.
- **Per frame:** one ticker per coordinator writes animated values straight into the render objects. No widget rebuilds while glass moves. The geometry is still redrawn on each animated frame (M10 measures it).
- **Material follows size:** standalone glass resolves its material from its drawn size every frame (no post-frame lag). Container members keep sharing one material, as today.
- The 16-shape cap per container stays (`LiquidGlassBlendGroup.maxShapesPerLayer`), including removed glass that is still animating out.

### M2. Animations and springs

- Springs use `motor`'s spring physics, set by response and damping, the same two numbers the lab fits from native.
- `GlassAnimation` presets mirror SwiftUI: `defaultSpring`, `snappy`, `bouncy`, `smooth`, `GlassAnimation.spring(duration:, bounce:)`, `GlassAnimation.dampedSpring(response:, dampingFraction:)`, and `GlassAnimation.none`. `motor`'s `CupertinoMotion` values are the starting point (default 0.55 s / bounce 0; smooth 0.5 / 0; snappy 0.5 / 0.15; bouncy 0.5 / 0.3); the lab's native measurements override them where they differ.
- **Precedence:** a change made inside `withGlassAnimation(animation, () => setState(...))` uses that animation. Otherwise the nearest `GlassAnimationScope(animation:)` applies. Otherwise the package default applies. `withGlassAnimation`'s animation applies to glass changes built in the next frame and is then cleared.
- Changes animate by default; `GlassAnimation.none` turns animation off.
- The press always uses its own native-fitted springs, whatever animation is in force, as in SwiftUI.

### M3. Materialize and dematerialize

- Driven by `visibility` (`lib/src/liquid_glass_settings.dart:72-191`), which already scales lens thickness, blur, chromatic aberration, light, ambient, saturation, tone, outline, specular, sheen and shadow, and fades the content.
- The mapping from spring progress to visibility is asymmetric: it is fitted on native's default-animation frames (appear about twice as slow as disappear), then checked on the `.snappy` and `.bouncy` references (N5).
- Visibility is clamped to [0, 1], so an overshooting spring never over-blurs, unless native's frames show otherwise.
- **Edge light:** the edge line and sheen take their width from the material's full thickness and their brightness from visibility. Today they fade over 0.7–1.0 × the ramped thickness (`liquid_glass_final_render.frag:60-61,84`), so appearing glass narrows its edge light. At visibility 1 the two are equal, so still glass renders identically to 2A; a test proves it pixel for pixel. Native mid-appear frames check the choice.
- Whether `refractiveIndex`, `outlineWidth` and `specularWidth` ramp (they do not today) is decided by native's mid-transition frames.
- Transitions: `GlassEffectTransition.materialize` (default: glass ramps, content fades), `.identity` (no animation), `.matchedGeometry` (morph with the glass that has the same id).

### M4. Merge and split

- `GlassEffectContainer(spacing:)` takes SwiftUI's meaning: glass closer than `spacing` begins to merge. Its default is native's default spacing, measured by N7.
- The mapping from `spacing` to `blend` is calibrated on N7's neck widths and `material.merge`'s topology. If the current smooth-min cannot match native's neck shape, it is replaced.
- Merging needs no separate animation: shapes blend by their drawn rects, so they join and split as the coordinator moves them.

### M5. Union

- Glass with the same union id draws as one shape at any distance.
- What native draws for a union is measured (component count, outline, neck) and copied.
- The Flutter `material.union` scene is rebuilt to match native: four 64 pt circles in two union pairs (`MaterialScenes.swift`, `UnionScene`).

### M6. Morph

- Glass with an id, in a namespace the app creates once, morphs into or out of the glass with the same id.
- An appearing glass with no partner emerges from existing glass in the same container, and a removed one sinks back into it. Which glass it emerges from is read off native's morph frames; the working guess is the nearest.
- Targets: native `material.morph` (expand about 460–550 ms, collapse about 210 ms, re-measured with L1 and L2).

### M7. Press

- Reference: N1 and N2 (`spike-interactive.md`).
- **Scale:** uniform, never a fixed outset, with native's size law fitted on N2 (today's inference: width growth about min(17.5, 1100 / height) pt, the same factor on both axes).
- **Order:** glow first, growth second, with native's timings; on release, the size spring and the glow fade, including the one-frame drop about 400 ms after release.
- **Content:** whatever native does to the content inside (moves, scales or stays) is measured and copied.
- **Glow:** starts under the finger with today's `GlassGlow` physics, re-timed to native. It is drawn by the container rather than inside each shape, clipped to the glass shapes, so it can reach neighbouring glass where native shows it does (N4).
- **Stretch and glow spreading:** only where native shows them (N3, N4), copied exactly. Where native shows nothing, the package does nothing.
- **Touches:**
  - interactive glass listens to raw pointer events without entering the gesture arena, so a button inside it keeps its tap;
  - it reacts to any touch inside its shape, whatever its content (native needs rendered content, a SwiftUI hit-testing detail the spike documented);
  - with nested interactive glass, only the innermost reacts;
  - a drag that leaves the glass, or a scroll that takes over, releases with the release spring.

### M8. Reduce Motion

- Read as today: the iOS setting through the plugin, or Flutter's `disableAnimations` (`lib/src/accessibility/glass_accessibility.dart:75`).
- Starting guess, until native's Reduce Motion references (N6) decide:
  - press: brightens only, with no growth, overshoot or stretch;
  - materialize and morph: cross-fades without the blur ramp;
  - merge: springs without bounce.
- `GlassGlow` and `LiquidStretch` stop ignoring Reduce Motion.
- A switch during an animation applies from the next change.

### M9. Public API

Names mirror SwiftUI and are fixed once:

| SwiftUI | Package |
|---|---|
| `.glassEffect(.regular.interactive())` | `Glass.regular.interactive()` (exists) |
| `GlassEffectContainer(spacing:)` | `GlassEffectContainer(spacing:)`, SwiftUI meaning, native default |
| `@Namespace` | `GlassNamespace()`, created once in the app's `State` |
| `.glassEffectID(id, in: ns)` | `GlassEffect(id: GlassEffectID(id, ns))` |
| `.glassEffectUnion(id:namespace:)` | `GlassEffect(union: GlassEffectUnion(id, ns))` |
| `.glassEffectTransition(...)` | `GlassEffect(transition: GlassEffectTransition.materialize / .identity / .matchedGeometry)` |
| `Animation.default`, `.snappy`, `.bouncy`, `.smooth`, `.spring(duration:bounce:)`, `.spring(response:dampingFraction:)` | `GlassAnimation.defaultSpring`, `.snappy`, `.bouncy`, `.smooth`, `GlassAnimation.spring(duration:, bounce:)`, `GlassAnimation.dampedSpring(response:, dampingFraction:)`, plus `GlassAnimation.none` |
| `withAnimation(.bouncy) { ... }` | `withGlassAnimation(GlassAnimation.bouncy, () => setState(...))` |
| (no equivalent) | `GlassAnimationScope(animation:, child:)`, a subtree default |

`Glass.interactive` stays part of `Glass`'s equality. The README documents every name with a SwiftUI-to-Flutter table.

### M10. Frame cost

- A new example perf scene keeps glass animating every frame: repeated press pulses, materialize and dematerialize, and merge and split.
- Its frame time must stay within 20% of the still-glass perf scene, measured in alternating A/B pairs (gotcha 16).
- Over budget means 2B.3 fixes the cost before finishing; the likely target is the per-frame geometry redraw (`internal/render_liquid_glass_geometry.dart:204-214`).

### M11. Live example scenes

`material.interactive`, the materialize scenes, `material.merge`, `material.union`, `material.morph`, the N2–N4 scenes and the N7 spacing scenes are real, stateful Flutter scenes with the same tap ids as native (`toggle`, `merge`, `split`, `morph`, `glass`). `LabButton.onTap` is wired.

---

## 8. Done means

**The rule.** Every measure is read from a fresh `lab.py run` on the iOS 27 simulator. The target is every measure passing in every case (dark and light, each listed backdrop, normal and Reduce Motion), with each limit max(fixed threshold, 1.5 × noise). A measure that still fails at the end of a plan is classed by cause, with evidence, in that plan's results and carried to a to-do list, as 2A.2 was. **No limit or measure is ever loosened.** The user decides each merge.

**"Still glass no worse than 2A"** means: every static measure, on every 2A scene and case that passed at `7e318a49f`, still passes, and no failing static measure gets worse by more than its noise.

**2B.1 is done when:**
1. L1–L3 and L5–L8 have passing synthetic-frame tests and reproduce, within noise: appear 285–320 ms, disappear 117–167 ms, v13's +12 / +4.67 pt at 250×88, about +17.5 pt width on glass up to about 60 pt tall, and menu open 0.26–0.30 s / 0.74–0.81.
2. Noise floors exist for every 2B.1 scene and case.
3. N1, N2, N5, N7 and the N6 runs for materialize are recorded.
4. Materialize and dematerialize pass under the default animation, `.snappy`, `.bouncy` and Reduce Motion, per shape: 10–90% time, settle time, overshoot, spring fit, progress curve and the sharpness difference.
5. Still glass is no worse than 2A.
6. Gates: `flutter analyze` clean and `flutter test` green in the app, the package and the example; harness tests green.

**2B.2 is done when:**
1. `material.merge`, `material.union` and `material.morph` pass, normal and Reduce Motion: per-shape motion, join and split timing, neck width over time and component count.
2. The rebuilt union scene passes its still-image measures.
3. The N7 spacing scenes pass their still-image and topology measures.
4. Still glass is no worse than 2A. Gates as in 2B.1.

**2B.3 is done when:**
1. `material.interactive` and the N2 sizes pass: uniform scale on native's size law at every size, glow first and growth second with native's timings, release (size spring and glow fade with its one-frame drop), and touch-to-response delay.
2. N3 and N4 pass: stretch and glow spreading where native shows them, and their absence where it does not.
3. Reduce Motion runs pass.
4. The animated perf scene is within 20% of the still-glass scene.
5. The package README documents the whole API.
6. Operator's `_PressLift` is on the package press if the swap was trivial; otherwise the reason is recorded and it moves to project 3.
7. Still glass is no worse than 2A. Gates as in 2B.1.
8. The ROADMAP is updated: status, §7 checklist rows for 2B, §8 numbers, and gotchas 10 and 13 corrected from the spike.

## 9. Testing

**Package, Dart, on a fake clock:**
- the coordinator's comparison when glass is added, removed, moved, resized or re-ided;
- a spring retargeted mid-flight keeps its value and velocity;
- removed glass keeps animating out, then is dropped;
- animation precedence: `withGlassAnimation`, then `GlassAnimationScope`, then the default; `GlassAnimation.none`;
- Reduce Motion paths;
- hit testing at the final layout while glass is still moving;
- only the innermost nested interactive glass reacts;
- a button inside interactive glass keeps its tap;
- the 16-shape cap, counting glass still animating out;
- still glass at visibility 1 renders identically before and after the edge-light change.

**Harness:** synthetic-frame tests for every new measure, manifest validation for the new fields, noise-floor limits, step-based event pairing and the teardown cut.

**Gates on every task:** `flutter analyze` and `flutter test` in `packages/mobile`, the package and the example; the harness tests.

**Review after each plan, here:** an independent code review against the plan, and an independent measurement audit that recomputes the Done table from `result.json` and looks at full-resolution crops; then a fix wave.

## 10. Risks

- **Content snapshot on removal.** Capturing a removed widget's last frame may be unreliable in Flutter. Prototyped first, with a documented fallback (M1).
- **Per-frame geometry cost.** Every animated frame redraws the geometry shader with no cache. The perf scene measures it; 2B.3 fixes it if over budget.
- **The blend formula may not match native's neck.** Calibration (N7) decides; replacement is allowed (M4).
- **The size law is an inference** from six sizes. N2 pins it.
- **Timing resolution.** The video is variable-rate, with gaps of 33–53 ms in native press events, coarser than the 17 ms threshold; native also drifts between sessions. Noise floors from two sessions carry this into the limits.
- **Flutter runs as a debug JIT build on the simulator,** so a stall can look like spring error. The report lists Flutter frame gaps over 25 ms, and a run with stalls during an event is repeated.
- **`motor`'s default spring** is claimed to match SwiftUI's `Animation.default` but has not been verified against Apple; the lab's materialize measurements decide.

## 11. Files

The plans name exact files. Expected:

**Created:**
- in the package: `lib/src/motion/` (coordinator, animation and spring types, transaction and scope, press controller, container glow layer, id and union registry, removal ghosts), `lib/src/api/glass_namespace.dart`, `lib/src/api/glass_animation.dart`, tests under `test/motion/`;
- in the example: live motion scenes, the touch marker, the animated perf scene;
- native: the N2–N7 scenes and the touch marker;
- harness: the L1–L8 modules and their tests;
- `docs/liquid_glass/02b-motion/plan-2b1.md`, `plan-2b2.md`, `plan-2b3.md`, each plan's results file, and its tuning log if any.

**Modified:**
- package: `api/glass_effect.dart`, `api/glass_effect_container.dart`, `liquid_glass.dart`, `liquid_glass_blend_group.dart`, `glass_glow.dart`, `stretch.dart`, `internal/render_liquid_glass_geometry.dart`, `assets/shaders/liquid_glass_final_render.frag` (edge light), possibly `assets/shaders/sdf.glsl` (blend), `lib/ios_liquid_glass.dart` (exports), `README.md`, `FORK.md`, `CHANGELOG.md`;
- example: `lib/lab/lab_parts.dart`, `lib/lab/scenes/material_scenes.dart`, perf scenes;
- native: `MaterialScenes.swift`, `SceneRegistry.swift`, `GlassLabApp.swift`, the driver;
- harness: `align.py`, `analyze.py`, `manifest.py`, `metrics.py`, `lab.py`, `scenes.json`, `noise.json`, `tool/glass_lab/README.md`;
- `docs/liquid_glass/ROADMAP.md`.

## 12. How the plans must be written

Follow ROADMAP §5:
1. Before each plan, prototype its risky pieces on the iOS 27 simulator in a throwaway worktree. For 2B.1 that is: per-shape tracking and progress measures reproducing the known native numbers; the touch marker in both apps; the coordinator with a removal ghost and the content snapshot; one materialize run measured end to end against native.
2. Write the plan (`plan-2b1.md`, then `plan-2b2.md`, then `plan-2b3.md`) with the tested code embedded, tasks of reviewable size, and the Review Focus section.
3. The user approves each plan.
4. A fresh local session executes it, subagent-driven, in a new worktree and branch.
5. Review here, fix, and merge only when the user says. The next plan is written after the merge.
