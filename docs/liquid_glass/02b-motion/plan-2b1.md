# ios_liquid_glass 2B.1: the instrument and the first motion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal.** Make the lab able to measure how glass moves, record the native references 2B needs first, and give the package its motion coordinator with materialize and dematerialize as the first feature:
- lab: per-shape tracking (L1), topology (L2), materialize progress and blur (L3), touch timestamps from an on-screen marker in both apps (L5), the teardown cut (L6), per-scene motion measures that fail when absent (L7), per-case noise floors over two sessions for motion and still measures (L8);
- native references: v13's content in `material.interactive` (N1), a press size series (N2), materialize under `.snappy` and `.bouncy` (N5), container spacing still scenes (N7), Reduce Motion runs of the three materialize scenes (N6);
- package: `GlassAnimation` with SwiftUI's presets, `withGlassAnimation`, `GlassAnimationScope`, `GlassEffectTransition` (M2, M9 part); one coordinator per container and one per standalone glass (M1) that animates insertion and removal with native's asymmetric, per-animation progress (M3), keeps removed glass as a ghost with a fading snapshot of its content (in the container, or in the nearest `Overlay` for standalone glass), springs drawn rects with no widget rebuild, follows the app's own motion and every scroll exactly, and resolves each glass's material from its drawn size;
- example: live materialize scenes with native's tap id `toggle` (M11 part) and the lab's tool scenes;
- verification in `docs/liquid_glass/02b-motion/results-2b1.md` against spec §8 "2B.1 is done when".

**Architecture.**
- The harness gains three modules: `track.py` (Task 1), `touch.py` (Task 2) and `shapes.py` (Task 4, on Task 3's manifest and spring-fit groundwork). `track.py` finds each tracked shape's box against the bare frame inside its pinned region at full resolution, with a threshold raised by the backdrop's own edge strength so H.264 ringing at backdrop edges is ignored (and flags box edges inside that blind band), projects each frame onto the bare-to-full line at point resolution for progress, residual and sharpness, and counts glass components and their neck for topology. `touch.py` reads the marker's colour from the video. `shapes.py` cuts the capture after its last settled frame, splits events, gives each event to the step whose touch came last, compares native and Flutter per shape and per step, and judges every measure a scene lists for every pair and shape, an absent one as `inf`, with unpaired events and missing touches failing too. Scenes without a track keep today's whole-region series, now with the teardown cut.
- The package keeps its renderer. Three render-level hooks are added: an `Animation<double>` visibility that the layer, geometry, shadow and content read without a rebuild (blur ramped by a fitted power), a `GlassShapeMotion` drawn rect that the blend group gathers instead of the layout rect, and a `GlassMaterialSource` that feeds a glass's settings and shadow from its drawn size. Above them, `GlassEffectContainer` owns a `GlassMotionCoordinator` (one ticker) whose space is the render object above the container; each `GlassEffect` is a member with a presence spring and four offset springs added to its live layout, so a scroll can never leave it behind; a single layout change animates only after a rebuild, a structure change or a transaction, and a glass the app moves on consecutive frames follows its layout exactly (ruling 32). Appearing and disappearing glass draws in its own layer with the container's material; a removed glass becomes a ghost built in the same frame through a `LayoutBuilder`, at its last on-screen rect, with a snapshot of its content's last painted layer; standalone glass's ghost lives in an `OverlayEntry`.
- Fitted numbers (each preset's disappear exponent and appear overshoot gains, normal and Reduce Motion, the blur ramp, Flutter's visibility-to-progress table) come from `lab.py fitvis`, never by hand; the springs themselves are SwiftUI's.

**Tech stack.** Flutter 3.44.5 / Dart, Impeller runtime-effect shaders (GLSL 460), `motor` 1.1.0 springs; Python 3 (stdlib, Pillow, numpy) for the harness; Xcode 27, SwiftUI and XCUITest; the iOS 27 simulator.

**Spec.** `docs/liquid_glass/02b-motion/spec.md` (approved 2026-10-03): §4 (2B.1's scope), §5–§7, §8 "2B.1 is done when", §9, §12. Read `docs/liquid_glass/ROADMAP.md` §3–§5 first, then the spec, then `02b-motion/brainstorm.md`, `spike-interactive.md` and `context.md`.

**Where the code comes from.** Every code block and patch below ran in a throwaway prototype: worktree `/Users/omaraly/development/AI/Operator-2b1-proto`, branch `proto/2b1` from `development` `06d406bae`, committed there as `bba17e92a` (after two review rounds: the first prototype was `d6c716728` with plan `93c021d1c`, the second `9e1ec21eb` with plan `509ce7be2`), with this plan in the commit after it. Its own lab outputs are under that worktree's `packages/mobile/build/glass_lab/` (`runs/`, `fitvis/`, `reference/`, `ghost/`, `cold/`); the outputs and crops the rulings quote are committed on `proto/2b1` in `docs/liquid_glass/02b-motion/research/proto-2b1/` (`reproduce.txt`, the native fit checks, the Flutter materialize tables before and after the warm-up, the fit outputs and the scan's pixel check, the still-check, rim-check and cold-probe outputs, the v18 left-end crop, the ghost frames and the N7 screenshot). The patches are generated from that tree against `development`, each names the blobs it applies to, and they were applied in order with `git apply --3way` to a fresh export of `development` in a scratch repository, committed task by task, with the gates run after each task (the "Expected" lines of each task are those runs). Gates on the prototype commit, run with `--no-pub` (exact last lines):
- app (`packages/mobile`): `flutter analyze` → `No issues found! (ran in 20.1s)`; `flutter test` → `01:10 +2146: All tests passed!`;
- package (`packages/ios_liquid_glass`): `flutter analyze` → `No issues found! (ran in 1.9s)`; `flutter test` → `00:03 +121: All tests passed!`;
- example (`packages/ios_liquid_glass/example`): `flutter analyze` → `No issues found! (ran in 0.9s)`; `flutter test` → `00:01 +13: All tests passed!`;
- harness (`packages/mobile`): `python3 -m unittest discover tool/glass_lab/harness/tests` → `Ran 175 tests in 31.193s` / `OK`.

In that replay, onto the current `development` tip `6f42bb8c4`, every patch applied cleanly and every task's new tests failed before its implementation, with four exceptions that each step names: Task 18's first test (it pins the 2A bytes, so it passes on the 2A shader by design); Task 14's two tests that removal without a ghost already satisfies; and Task 16's app-animation test, which a glass that reports no rebuilds already satisfies. Every task's tests then passed with the counts this plan gives, and the final tree matched the prototype's sources file for file. The one difference is `brainstorm.md`, which `development` changed after the prototype branched.

Transcribe the code exactly. If a step fails, find the cause, fix it and say what changed in the task report.

**Rulings the prototype forced, with evidence.** Each refines or departs from the spec; where they differ, these win. Run folders are under the prototype's `packages/mobile/build/glass_lab/runs/`; `LG`, `P` and `GL` are copies of the 2A worktree's (`Operator-ios-liquid-glass`), the interactive spike's (`Operator-2b-proto`) and project 1's (`Operator-glass-lab`) runs in the prototype's `build/glass_lab/reference/`. An independent review of the first version of this plan (`proto/2b1` `93c021d1c`) found 1 blocker, 11 major and 20 minor problems; every one is fixed in the prototype and here, and the rulings it changed say so. Its re-review of the second version (`509ce7be2`) found ten more (R1–R10), fixed the same way; R1 and finding 12 took the user's rulings (32 and 33).

*Lab*

1. **The glass box is found against the bare frame with an edge-aware threshold** (spec L1). A pixel is glass when its 3 × 3-smoothed max-channel difference from `bare/ready.png` exceeds 15 + 1.0 × the backdrop's own edge strength (the larger neighbour difference, dilated over 5 × 5 px); rows and columns need at least 6 px. Why: H.264 rings in every video frame at every backdrop edge (1–3 px lines up to 87 levels at the stripe boundaries x = 67, 201 and 335 pt), so a fixed threshold reads the region's full height on `stripes` (the bug `context.md` §2 names), and a 9 px morphological opening, tried first, erased thin rims on short glass (the 58 pt circle read 40 pt wide). The spike's change box is relative to a rest frame and cannot see glass that is absent, which materialize needs. Evidence: v13 dark-stripes reads 252.00 × 88.67 → 264.00 × 93.33, **+12.00 / +4.67** exactly (`P-20261003-012138`); `button.press` 138.33 → 154.33 and 174.33 → 190.33 in all six runs (targets 138 → 154–155, 174 → 190–192). The cost is a blind band: within ±2 px (±0.67 pt) of a backdrop edge stronger than about 20 levels the raised threshold can hide a dim rim (v18's left rim at 67.67 pt sits under a threshold of 92), so the tracker flags a box edge inside that band (`band`, `edge_in_band`) and a reader treats that edge as up to 0.67 pt short (finding 18). An edge counts as inside the band when more than half of it lies on a backdrop edge, so a box whose top and bottom merely cross a stripe boundary is not flagged: v13, an exact reading, is not; v18 is, at its peak (R4).
2. **"About +17.5 pt width on glass up to about 60 pt tall" reproduces for two sizes of three; the third was a spike artifact, and L1 under-reads it.** L1 reads +17.0 (58 pt circle, v16), +16.0 (138 × 53, v17) and +14.33 (250 × 44, v18) against the spike's +17.67, +16.67 and +17.67. The spike took its rest box from the lossless PNG at threshold 20 and its peak from a change box at threshold 12, which gains up to a third of a point per edge; and at v18's peak both capsule ends sit on the stripe boundaries at 67 and 335 pt, where the change box caught the boundary itself: a 3× crop of the left end (`P-20261003-012604`, frame 300) shows the rim at 67.9 pt and no glass over the red stripe left of 67.1 pt, where the spike's box began at 66.67. Both of v18's ends are inside L1's blind band at the peak (ruling 1), so its true growth is about 15.0–15.5 pt (the review's column profile), and the lab's own `material.press.250x44` on `stripes` (+14.33, run `20261003-044602`) is not independent confirmation. Either way the "17.5 pt for short glass" law does not hold at 250 × 44. Done item 1 records this as not reproduced, with this cause; 2B.3 fits the size law on N2 on `photo`.
3. **`menu.bar` keeps the whole-region series; the teardown cut reproduces its spring.** The menu grows out of its toolbar button and over the nav title, so a box pinned over the menu's area measures the nav title and the menu together (width 232–265 pt; fitted springs 0.56–1.05 s / 0.38–0.57 over the three `GL-20260927-024701` takes and four baseline cases), and a region below the bar still gives 0.15–0.65 s / 0.66–1.20. On the old largest-blob series with the teardown cut, the three repeat takes pair to 0.27/0.78, 0.26/0.81 and 0.30/0.74, **inside 0.26–0.30 / 0.74–0.81**, with 2 events per take instead of 3.
4. **Teardown cut (L6).** Every extracted frame after the last one within 6 levels of the best match to `settled.png` (region MAD) is dropped; the overview window's end was `(last + 1) / 20` s and let the teardown frame in. v13 light-photo's capture ended with a full-region "glass" at 28.49 s (mean difference 59) that is now cut; on the real captures the review checked, the cut removed only the teardown frames (49 levels off, `.bouncy` light-photo native: 3 frames at 22.68 s) and nothing inside an event.
5. **Progress, residual and sharpness (L3) are read at point resolution (3 × 3 mean) over the tracked region; sharpness inside the rest box inset 16 × 8 pt.** Reproduces the "not an alpha fade" result on `LG-20260930-082046` `photo`: peak residual 5.12–5.37 against a glass-absent floor of 2.13–2.67 (context: 5.2–5.5 against 2.4–2.9), and half-progress sharpness 1.08–1.54 below the alpha mix (context: 1.1–1.6). On `stripes` there is no alpha-fade signal (peak 2.85 against an unreadable floor on `dark-stripes`, 3.60 against 1.72 on `light-stripes`) and the sharpness is uninformative (−0.03 to 0.04), as the context brief found.
6. **The 10–90% time is read on the 120 Hz grid.** `LG-20260930-082046` gives appear 275–292 ms and disappear 117–133 ms; the context brief's 285–320 / 117–167 ms were first-frame crossings, and the review reproduced them with the brief's own method on the same frames. The two estimators differ by up to 28 ms per case, so Done item 1's timing is judged against Task 9's `progress.t10_90_ms` noise, and native and Flutter are always read by the same estimator, so no Done measure is loosened.
7. **The touch marker returns to black 250 ms after release, and both apps paint it in the bare launch too.** So `ready.png`, `settled.png` and `bare/ready.png` hold the same black square, and still measures never see it; `region_for` drops any box that fits within one 8 pt motion tile of the marker, because the motion extent's tiles see the marker change colour during a touch (ruling 28 found the 2 pt tolerance of the first plan too small). Operator's app paints no marker, so for its scenes only the native video shows one, and the same rule keeps it out of the region. Touches are read from the video only; the spike's per-touch log file is not kept. A tap shorter than one video frame shows only its blue release frame (the prototype's `tool.ghost` probe `ghost/20261003-045928`: black, then blue at 17.578 s, then black); it counts as a touch at that frame.
8. **Events pair by step, and nothing passes by being absent.** An event belongs to the last touch that began before its onset; a step's events pair in order (`step<k>e<i>`); when either video has no marker (old runs, Operator's lab), events pair by order as before. Any event left out of a pair fails `events.unpaired` (limit 0), a scene with touch steps fails `touches.native`/`touches.flutter` unless each app's video shows the expected touches, and a measure the scene lists that is absent for a pair and shape is judged as `inf` (finding 1; the first prototype's `.bouncy light-photo` Flutter capture had three events and the third, the clamp dip of ruling 11's old form, was never judged). Touch-to-response delay is onset minus touch-up for `tap` and `doubleTap`, minus touch-down for `press` and `pressDrag`; it is computed and reported for every pair, but the materialize scenes do not list `delay_ms`: native starts to appear 65–112 ms after the tap and to disappear 18–47 ms after it, where the package starts within 12–33 ms (all 48 pairs of `20261003-113033` and `-120351`), and the user ruled that it is reported and classed, not copied (ruling 33). `results-2b1.md` reports it per pair.

*Materialize, measured natively in the prototype (runs `20261003-032332`; Reduce Motion `20261003-033143`; repeat takes `repeat-2b1`)*

9. **Native progress is the animation's spring on appear, scaled above 1 by a fitted gain, and the spring's remainder to a fitted power on disappear, per preset.** With `s(t)` the spring's step response: appear progress = s up to 1, then 1 + g·(s − 1); disappear progress = max(0, 1 − s)^e. `fitvis` fits `e` and `g` for each of the three native animations at its SwiftUI spring, over every backdrop and take: the default animation's disappear exponent is 3.1 (3.05–3.15 over the four takes); its critically damped spring never overshoots, so no gain can be measured and none is used: the table carries 0, marked `identifiable: false` (the measured trend is 0 at damping 0.85 and 0.34 at 0.7, and `GlassMaterializeMapping.of` gives the default mapping only to springs with damping above 0.925, which overshoot by at most 0.05%; R5); `.snappy` disappears with exponent 2.7 (2.7–2.75) and does not overshoot on appear (gain 0 in every take, the grid's floor: SwiftUI's 0.85 damping overshoots 0.6%, native's progress does not); `.bouncy` disappears with exponent 2.75 (2.7–2.8) and overshoots on appear by 0.34 of its spring's overshoot (0.32–0.38); one `.bouncy` curve (take 2, `dark-stripes`) fits no exponent better than RMS 0.24 and is left out (`fit.json` `excluded`). Per-curve RMS 0.029–0.037 over all backdrops (fit `build/glass_lab/fitvis/fixwave`, `research/proto-2b1/fitvis-fixwave.json`); none on a grid edge. The first plan's single exponent 3.2 for all three came from the default scene alone; per preset, `.snappy` and `.bouncy` disappear faster in shape (2.7, 2.75), as the review measured (2.70, 2.65). This is the spec's "asymmetric mapping". The package runs a presence spring (0 → 1 in, 1 → 0 out), turns it into progress that way, and turns progress into visibility through Flutter's own measured progress at fixed visibilities (`ios27VisibilityForProgress`). An app's own spring takes the mapping of the preset nearest its damping fraction (default and `smooth` for ~1.0, `.snappy` 0.85, `.bouncy` 0.7).
10. **The presets are SwiftUI's springs; what the lab fits is the mapping** (finding 3, the main session's ruling). `GlassAnimation.defaultSpring` is 0.55 s / 1.0, `.smooth` 0.5 / 1.0, `.snappy` 0.5 / 0.85, `.bouncy` 0.5 / 0.7, `motor`'s `CupertinoMotion` values; they are the springs every 2B motion runs on, so they are not bent to fit materialize. The first plan's `.snappy` 0.57 / 0.74 and `.bouncy` 0.55 / 0.50 were artifacts of fitting one exponent for all three under a clamp: with its own exponent, `.snappy` at 0.5 / 0.85 fits native as well (RMS 0.0123 against 0.0121), and `.bouncy`'s 0.50 damping existed only under the clamp. The default spring is checked against native on every case: over all four cases and takes native's default fits 0.57 s / 0.98, within 5% and 0.05 of SwiftUI's 0.55 / 1.0; no single case does (`dark-photo` 0.58 / 0.95, `light-photo` 0.49 / 1.12, `light-stripes` 0.45 / 1.24, `dark-stripes` 0.74 / 0.77, the stripes cases carrying the lens's stripe shift in their progress), so `default_spring_check.pass` is false and `results-2b1.md` reports it as failing. One native take's own fitted spring varies by more than the tolerance (`progress.response_pct` up to 21% and `progress.damping` up to 0.10 between takes of one case, Task 9), so no single case can decide SwiftUI's constant; the pooled fit is the evidence that the constant is SwiftUI's.
11. **Appearing glass overshoots as native does; visibility is clamped at 0 only** (finding 4). Native `.bouncy` appear progress overshoots 1.4–2.5% normally and 2.8–3.8% under Reduce Motion; the first plan's clamp at 1 guaranteed overshoot failures and made a 0.50-damped spring dip after it (an unjudged third event and a 158 ms settle failure, `045312`). Now the overshoot is the spring's times the fitted gain, visibility follows the table's last slope above 1, the shadow and the content stay capped at full, and a disappearing spring that undershoots 0 is held at 0. Native overshoots more under Reduce Motion, so each preset has a second gain fitted on the Reduce Motion recordings (`ios27{Preset}ReduceMotionAppearGain`): `.bouncy` 0.62 (four Reduce Motion curves of run `20261003-033143`, RMS 0.038, not on the grid edge: 0.62 × the 0.7-damped spring's 4.6% is 2.9%, inside native's 2.8–3.8%, where the normal 0.34 gives 1.6%), `.snappy` 0 (`at_floor`, as in normal mode), and the default 0, as in normal mode (R5). A glass takes the gain of the mode it began to appear in.
12. **Reduce Motion does not change materialize's timing or blur.** Under Reduce Motion native keeps the same timing (10–90% within a frame of normal in every scene and case) and still blurs (half-progress sharpness −0.89 to −1.56 on `photo`), so the spec's starting guess, a cross-fade without the blur ramp, is wrong. What it changes: it removes the edge spread of ruling 13 (box height ≤ 88.67 pt throughout, residual 3.25–3.56 against 5.06–5.41) and `.bouncy` overshoots more (2.8–3.8% against 1.4–2.5%). The package draws no edge spread, so its Reduce Motion materialize is its normal one with the Reduce Motion overshoot gain of ruling 11, and a Reduce Motion switch mid-animation leaves the animation alone (Review Focus 4).
13. **Native materialize spreads the glass edge; the package does not, in 2B.1.** Mid-appear the native glass box measures 218–254 × 85–96 pt at progress 0.09–0.6 (+7.3 pt tall at 0.19, `032332` `dark-photo`) while the package's measures 216–223 × 78–85 and jumps to 249.67 wide at about 0.54, where its faint ends cross L1's threshold (`045312`): a mismatch of up to about 15 pt in height and 15–30 pt in width, a soft, spreading edge against a crisp one. No Done measure is a box size, so it fails nothing judged; it is visible. Building it needs a soft-coverage term in both shaders; it is in `todo-2b1.md`, not built.
14. **`refractiveIndex`, `outlineWidth` and `specularWidth` do not ramp, as today; native's softer mid-transition rim and the lens displacement are open items with their deciding measures** (finding 26). The rim check (Task 20 Step 8, `rim_check.py`) measures the depth of the lit band under the top edge: Flutter's lit band is 0.67–1.0 pt deep at every visibility from 0.1 to 1 in all four cases, and from 0.3 up within one pixel (⅓ pt) of its depth at 1. Native's is 1.0–1.67 pt at rest, 5–24 pt at progress 0.3–0.7 in the normal run (`20261003-113033`, where ruling 13's edge spread moves the top edge through the band) and still 5.0–5.33 pt under Reduce Motion (`20261003-120351`), where there is no spread. So native's rim mid-transition is softer or wider than at rest and Flutter's is not: a visible mismatch that no Done item 4 measure judges. The depth cannot say which of a wider outline, a softer specular or the materialize blur over the edge makes it, so the three keep 2A's values (no ramp), and the band's profile across the edge is an open item in `todo-2b1.md` with its measure: native's profile at progress 0.3–0.7 under Reduce Motion against Flutter's at the same visibility with `outlineWidth` and `specularWidth` swept. The lens displacement (how far the backdrop shifts inside the rim mid-transition against native) is not measured: it is in `todo-2b1.md` with its measure, the cross-correlation shift of a row just inside each end against the bare row, native at progress 0.5 against Flutter at the visibility the table gives for 0.5.

*Package*

15. **The content snapshot works, so removal keeps the content (no fallback).** `GlassEffect`'s content sits in a `RepaintBoundary` subclass; `State.deactivate` runs after the render tree is detached but before `finalizeTree` disposes layers, so it can keep the boundary's last painted `OffsetLayer` alive with a `LayerHandle` at no cost; the coordinator calls `toImageSync` on it only when it builds the ghost, in the ghost host's layout callback, so a glass moved with a `GlobalKey` within the frame keeps its state and takes no snapshot (finding 21). A `LayoutBuilder` is the one element that may be marked dirty during build (its `markNeedsBuild` schedules a layout callback), so the ghost is built and painted **in the removal frame**: no blink. Ghosts are placed at paint time from global coordinates, because a container that wraps only the removed glass shrinks to nothing in that frame (native's `GlassEffectContainer { if shown { … } }` does exactly that). Evidence: package tests (ghost in the same frame with a non-null image; stays at the glass's on-screen rect when the container shrinks to zero; a `GlobalKey` move between containers leaves no ghost and stays visible) and the simulator: `build/glass_lab/ghost/20261003-210622` (`tool.ghost`, dark `photo`, on the final prototype): in every frame after release the "Glass" label stays where it was and fades with the glass, and the region's mean difference from `ready.png` rises 2.29, 2.93, 5.05, 7.77, 10.08 … 16.93 with no jump and no frame without glass.
16. **Insertion and removal follow one rule for container and standalone glass** (the first plan's "standalone glass never transitions" is withdrawn, finding 9). A glass materializes when a `withGlassAnimation` is pending, or when it is first built into a parent render object that has already been laid out; it dematerializes when a `withGlassAnimation` is pending, or when its parent render object is still attached as it leaves (it was removed alone). Reason: Flutter cannot tell an insertion from a first build by the element alone, but a page push, a tab's first build, a newly built subtree and a lazily built list item all create their parents in the same frame as the glass, while `if (shown) GlassEffect(…)` toggled inside an existing layout has a parent that was laid out before; the removal side mirrors it, so a glass that leaves with its page or its parent does not leave a ghost behind. Tests: `glass present at the first frame does not animate in`, `inserted glass materializes in its own layer, then joins the container`, `glass removed together with its parent disappears at once`, `standalone glass inserted later materializes, and glass built with its page appears at once`, `removed standalone glass dematerializes in the nearest Overlay, with its content snapshot`. A glass wrapped in a new parent of its own (`if (shown) Padding(child: GlassEffect(…))`) appears at once unless the change is inside `withGlassAnimation`, the transaction SwiftUI itself needs.
17. **The coordinator's space is the render object above the container** (finding 29). A container that re-centres in its parent (`Center > GlassEffectContainer > Row` with an inserted item) animates its glass from where it was on screen; anything that moves the parent itself (an outer scroll, a route transition, the keyboard) moves the glass at once. Standalone glass's space is its own parent. `material.merge` re-centres its container, which this covers.
18. **Appearing and disappearing glass draws in its own layer with the container's material**, then rejoins the shared group with one rebuild when it settles. Per-shape visibility in a shared layer cannot ramp the backdrop blur, which is one `BackdropFilter` per layer. Consequences: ghosts and appearing glass never count toward the container's 16-shape uniform cap (Review Focus 5), and an appearing glass does not merge with its neighbours until it settles; 2B.2 decides from native morph frames whether that matters. The cost of an extra layer per transitioning glass is in `todo-2b1.md` for M10 (finding 22).
19. **2B.1's API is `GlassAnimation`, `withGlassAnimation`, `GlassAnimationScope` and `GlassEffectTransition.materialize`/`.identity`.** `.matchedGeometry`, `GlassNamespace`, `GlassEffectID` and `GlassEffectUnion` arrive with ids in 2B.2; the coordinator's registry needs none of them now. `withGlassAnimation`'s pending animation is one global value, as SwiftUI's transaction is per update: every glass change built in that frame takes it (README), and tests clear it with `debugResetGlassAnimation` (finding 32).
20. **The edge light reads the full thickness through new uniforms** (`uOptics.w` in the final pass, `uFullThickness` at float 103 in the geometry pass), and the signed distance is encoded with the full-thickness reach. At visibility 1 the bytes are 2A's: the final pass is checked against bytes recorded from the 2A shader; the geometry pass cannot run under `flutter test` (SkSL), is the identity by construction at visibility 1 (simulator check: the final prototype's `material.regular` Flutter frames (run `20261003-210710`) are byte-identical to the 2A.1 run `20261002-200447` in all ten cases, `ready` and `settled`), and below 1 the rim check shows the rim keeps its full depth (finding 28; ruling 14).
21. **Content keeps its layout-size clip while the drawn rect moves**; it is translated by the drawn rect's centre offset, as spec M1 asks, and not clipped to the drawn size.
22. **Noise floors are per case, and stills have them too**: `noise.json` is `{scene: {case: {measure: noise}}}` for the new scenes, with motion, static (`ready.mad`, …) and still-topology (`ready.topology.<region>.count`, `.neck_pt`) entries; `analyze` applies max(fixed, 1.5 × noise) to all of them (finding 10). A non-finite value (an invalid fit) never becomes a noise. The old scene-wide `menu.bar` and `tabbar.drag` entries stay readable; the `tabbar.drag` `event2.*` teardown entries are removed.
23. **Topology (L2).** Components are counted on a point-resolution mask (a point is glass when half its pixels are; components of at least 20 pt²). The neck is measured at pixel resolution: the mask is split on its principal axis into two lobes, and the neck is the shortest cross-section perpendicular to the segment between their centroids. Two discs with a 20 pt bridge read 20.67 pt; two overlapping discs with a 38.7 pt chord read 40.33 (the 3 × 3 smoothing fills the cusps by about a point; native and Flutter share the bias). One component whose centroid segment crosses no glass reads neck NaN, not 0, so it fails a comparison (finding 30: native `spacing: 40` g20 on `stripes` read count 1, neck 0.00). Video frames use L1's edge-aware mask; still screenshots, which are lossless, use a plain threshold of 6 levels, because on `photo` the glass interior differs from the bare frame by less than L1's 15 and the edge-aware mask breaks each glass into pieces. Counts in motion are compared outside ±2 samples (±17 ms) of any join or split. Native N7 stills (`20261003-050837` `dark-photo`, `20261003-044920` `dark-stripes`): the default container merges at gaps 0 and 4 pt (necks 25.33 and 4.00 pt) and keeps 8 pt and wider apart; `spacing: 40` merges up to 20 pt (necks 50.67, 38.33, 40.67, 34.00, 24.67 and 2.00 pt at 0, 4, 8, 12, 16 and 20) and keeps 24 pt and wider apart. So native's merge reach is about half its `spacing`, like the package's smooth-min (which fuses gaps under blend / 2), not spec M4's "closer than `spacing`": nothing in 2B.1 depends on it, and it is carried to 2B.2's M4 with these numbers (`todo-2b1.md`).
24. **The example's materialize scenes run their transition once, quickly, before they are measured, and the cold first transition is still recorded.** In the prototype's first Flutter run (`20261003-042321`) the first ghost or appearing-glass frame of each launch stalled in the debug JIT build: one dropped frame (a 28–33 ms gap at the event's start, against 17 ms after the warm-up), after which Flutter's first changed frame sat at progress 0.735 against native's 0.963 on `dark-photo`. After a 0.08 s hide-and-show at launch (before `ready.png`), the same cases read disappear within 0–17 ms of native. This is lab hygiene for a debug build, not package behaviour, so `align.stalls` (which skips each event's first gap) is joined by a first-frame check (Flutter's first changed frame against native's, `done_table.py`), stalls are stored in `result.json` again (finding 6), and Task 20 records `tool.materialize.cold` for project 5: the prototype's probe (`build/glass_lab/cold/20261003-121941`, `dark-photo`, no warm-up) renders the scene from the first frame and records both events; the launch's first transition, a disappear, has one 38 ms gap at its start and its first changed frame at progress 0.38 against native's 0.03, so its 10–90% reads 83 ms against native's 133, while the appear after it starts at 0.03 within 17 ms and reads 300 ms against 292. That is what the warm-up hides, recorded, not judged.
25. **The backdrop blur ramps as visibility to a fitted power** (finding 11). The first plan expected the half-progress sharpness gap (Flutter −2.29 to −2.52 against native −1.01 to −1.27 on dark `photo`) to stay as a model limitation; it is tunable. The geometry, lens, light and tone ramp linearly with visibility as before; the blur is blur × v^k, and `fitvis` picks `k` by scanning `tool.visibility` at fixed visibilities under several `k` (the scene draws through `LiquidGlassSettings.atVisibility(v, blurRampExponent: k)`, the function the renderer applies with the fitted `k`, so the scan cannot drift from the package; R8) and matching Flutter's sharpness at quarter, half and three-quarter progress to native's at the same progress: `k` = 3 (sharpness RMS difference against native over the four cases and the three progress points: 1.14 at k = 1, 0.91 at 2, 0.84 at 3, 0.97 at 4; not on the grid edge). It closes the gap at quarter progress on `light-photo` (Flutter −4.0 at k = 1, −0.3 at k = 3, native −2.0) and halves it on `dark-photo` (−3.9 → −3.0, native −1.5), but not at half progress, where Flutter stays at −2.6 / −2.4 against native's −1.1 / −1.5 whatever the ramp (−2.69 at k = 1, −2.61 at k = 3 on `dark-photo`): what softens Flutter's half-way frame is not the blur. The half-progress sharpness measure is therefore expected to keep failing on `photo`, classed (b) with this evidence, and what else softens it is in `todo-2b1.md`. On `stripes` both apps read near 0, as before.
26. **A single layout change animates only when the glass was rebuilt, its container gained or lost a glass, or a `withGlassAnimation` is pending; a glass the app moves on consecutive frames follows its layout (ruling 32); scrolling never animates** (finding 2). The first plan compared layouts in the member box's `paint`, which a re-composited scroll never calls, so glass in a `ListView` inside a container drew at a stale place. Now the drawn rect is the live layout plus four offset springs that rest at 0, read from the render tree whenever the drawn rect is asked for, so a scroll or a re-composite moves the glass with its layout in the same frame; a size change is compared at the member box's layout, a position change at the first read of the drawn rect in a frame, both against the frame flags above (the glass widget's build in that frame or the one before, because the renderer can draw a moved glass a frame late), and the scroll offsets of every `Scrollable` between the glass and the coordinator's space are taken out of the position first. Flutter has no hook between layout and paint, and the coordinator's tick runs before layout, so these reads are where a change is first seen. A glass that is not rebuilt (a `const` widget whose parent changed) jumps unless the change is inside `withGlassAnimation`, which is SwiftUI's own rule for animating a layout change.
27. **Standalone glass's ghost is drawn in the nearest `Overlay`** (finding 9). A private coordinator dies with its glass; the ghost needs a host that outlives it. Each `OverlayState` gets one `OverlayEntry` with its own ticker and ghost host, inserted after the frame in which the first standalone glass under it is built (an `Overlay` cannot take a new entry during build) and removed once no standalone glass uses it and no ghost is left. The `Navigator` keeps entries it does not own above its routes, so ghosts draw above every route of that overlay: a glass removed under a modal route draws its ghost over the modal for 0.13–0.3 s. Without an `Overlay` standalone glass disappears at once. Simulator evidence: `build/glass_lab/ghost/20261003-210646` (`tool.ghost.standalone`, the same glass on dark `photo` with no container): the label stays where it was and fades with the glass, and the mean difference from `ready.png` rises 2.28, 2.89, 5.04, 7.76, 10.08 … 16.94, the container's values one frame later.
28. **"Still glass no worse than 2A" counts a measure as worse only when the Flutter frame changed, and lists any 2A case it cannot find** (finding 7). An unchanged Flutter frame means the change came from the native side: native frames differ by a level or two between sessions. Evidence: on the final prototype all 52 Flutter frames of the four still scenes are byte-identical to their 2A runs (`material.regular` 20, Operator's `tabbar.rest` 16, `button.press` 4, `navbar.inline` 12; runs `20261003-210710`, `-212057`, `-213008`, `-213813`), native frames differ from 2A's session by 0–2 levels (229 at the touch marker on `button.press`, which 2A did not draw and the region leaves out), and no measure moved: `missing: 0`, `worse: 0` in all four. The exemption was not needed in this run; it is there for a session whose native frames move a measure. Operator's three 2A component scenes (`tabbar.rest`, `button.press`, `navbar.inline`, `--flutter operator`) are in the check, because Operator builds every toolbar on `GlassEffectContainer` and 2B.1 makes those toolbars coordinator members.
29. **Animated container spacing moves to 2B.2, with M4** (finding 8, the main session's ruling). Spec M1 lists "Animated per container: spacing", but 2B.2 changes what `spacing` means (ruling 23: native's merge reach is about half its `spacing`), so animating today's meaning would be thrown away. A spacing change jumps in 2B.1.
30. **Material follows the drawn size with no post-frame lag** (spec M1, finding 8). Each glass resolves its material from its drawn size at its member box's layout (so the first painted frame already has the measured material) and on every animated frame; the first build, before any layout, uses `sideHint` or 88, as 2A's did, but no frame is painted with it. The resolver is a pure function of the side built from the theme, accessibility and debug overrides of the last build, so a tick needs no `BuildContext`.
31. **A removal reads no transform.** `State.deactivate` runs in the build phase, where an ancestor can be a fresh render object that has not been laid out (a route's `FractionalTranslation` in the first frame). The first prototype's ghost placement asked the coordinator's space for its transform to the screen there, which asserts (`RenderBox was not laid out`) and replaced the scene with Flutter's error screen until the next rebuild; the materialize scenes' warm-up hid it, and `cold_probe.py` (`tool.materialize.cold`, no warm-up) found it: a red error screen for the 8 s before the first tap (prototype probe `cold/20261003-105036`). Now every transform is read at paint, where all ancestors are laid out: each member caches its space's screen origin at the first read of its drawn rect in a frame, and a ghost is placed from that cache. The cache is as old as the last read, and nothing reads a list item's glass that a scroll only re-composited (and `FakeGlass` never does), so the ghost's rect also adds how far every `Scrollable` above the glass has scrolled since that read; scroll positions are safe to read during build (R6). Test: `a glass removed after its list scrolled leaves its ghost where the glass was on screen` (Task 16). Test: `leaving reads no transform, so a removal during build never touches an ancestor that is not laid out yet` (Task 12), with a render object that throws if its transform is read.
32. **A glass moved on consecutive frames follows its layout exactly; a single change animates** (R1, the user's ruling). A glass whose layout changes on consecutive frames is moved by the app (a drag, the app's own animation, the keyboard), and the coordinator follows it with no spring lag; a single change (a toggle, an insertion or removal, a one-off rebuild that moves the glass) animates with the default spring or the transaction's. Exactly: a member is *following* in a frame when its layout (its size at layout, its position at the first read in the frame) changed in that frame and in the frame drawn just before it, at most 50 ms earlier (`GlassMember.followGap`; Flutter draws no frame while nothing changes, so an idle gap shows as a longer interval). The first changed frame of a motion cannot be told from a single change, so it is taken as one: the change goes into the offset springs and the glass holds where it was (the spring's first sample). In the second frame the member is following: the offset springs are put back to their state before that frame's change (`GlassSpring.copy`/`restoreFrom`), so an animation already in flight carries on, and the glass sits on its layout, covering both frames' movement in one step, never past it or back. From then on each change applies at once. The member drops back to animating after one drawn frame without a change, or an idle gap over 50 ms. Inside `withGlassAnimation` every change animates, consecutive or not, and is never put back. The cost: two separate changes on back-to-back frames are taken as motion, so the second lands at once and the first one's spring, one frame old, is dropped with it; a drag that skips a frame holds for that frame. The reviewer's probes (a `setState` drag of 15 pt a frame, an `AnimatedBuilder` move) lagged their layout by up to 130 pt; they now sit on it within 0.5 pt from their second moving frame. Tests (Task 16): `a glass dragged by setState holds still in its first frame, then sits on its layout within 0.5 pt in every frame`, `a glass moved by an app animation every frame sits on its layout within 0.5 pt from the animation's second moving frame`, `a single change springs, and so do changes inside withGlassAnimation on back-to-back frames`, `a drag is followed, and a toggle after its release springs again`.
33. **The touch-to-response delay is reported and classed, not copied and not judged** (finding 12, the user's ruling). `results-2b1.md` reports each pair's delay, native and Flutter, and classes it; the package adds no delay to match native's, and `delay_ms` is not a judged materialize measure. Native starts to appear 65–112 ms and to disappear 18–47 ms after the tap, the package within 12–33 ms (ruling 8). Project 5 re-checks it on a device, where touch delivery differs from the simulator's.
34. **`LiquidGlassSettings.atVisibility(v, blurRampExponent:)` is public API** (final check). The example's `tool.visibility` scene, which `lab.py fitvis` scans, must draw through the exact function the renderer applies (R8), and the example reaches the package only through its public exports. The README lists it under the renderer settings as a lab-facing helper; it is not part of the SwiftUI-mirroring surface (spec M9).
## Global Constraints

- No code comments in any new or changed code (Dart, Swift, Python, GLSL, shell); keep the upstream comments that already exist.
- Every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never stage `frontend/package-lock.json`.
- Never `git stash`.
- Never run `dart format` on whole files; match the surrounding style.
- Build the lab apps only with `python3 tool/glass_lab/harness/lab.py build <native|example|operator|all>` (plain `flutter build ios` fails under Xcode 27).
- Use only the simulator "iPhone 17 Pro (iOS 27)", UDID `708879DD-8B2A-4547-863F-F49EE1474D8B`; never touch the iOS 26.5 simulator (`94D0C207-A90B-4806-BBAB-8AF9B3F16329`) or its Operator data.
- Simulator or system prompts get only "Don't Allow" or "Not Now"; never pair Operator; never enter a password.
- No downloads, no `pip install`, no new third-party dependencies; run `flutter test` and `flutter analyze` with `--no-pub` (the workspace resolves offline).
- Never push.
- Limits and measures are never loosened: the fixed thresholds in `metrics.py` stay, every limit is max(fixed, 1.5 × noise).
- Material and fitted tables are written only by tools: `ios27.dart`, `ios27_scroll_edge.dart` by `lab.py tune --write`; `ios27_motion.dart` by `lab.py fitvis --write` (Task 8 commits the prototype's tool output as the seed).
- Flutter 3.44.5.
- One lab command at a time (`build`, `run`, `repeat`, `fitvis`, `tune`, `perf`, `a11y`, `reboot` share the simulator); run long ones with the Bash tool's `run_in_background`, never a trailing `&`, and never poll with short sleeps.
- Every `simctl` command names the simulator by its UDID, never `booted` (two booted simulators make `booted` ambiguous). After any interrupted lab command, `xcrun simctl spawn 708879DD-8B2A-4547-863F-F49EE1474D8B defaults read com.apple.Accessibility ReduceMotionEnabled` and `… EnhancedBackgroundContrastEnabled` must print `0`; if not, run `python3 -c "import sys; sys.path.insert(0, 'tool/glass_lab/harness'); import sim; sim.accessibility(sim.device(), 'none')"`.
- A case whose `driver.log` holds only the `xcodebuild` invocation line is a known driver crash (ROADMAP §6, "Lab driver crashes"): rerun that case alone with `--appearance` and `--backdrop`, and say so in the task report.
- Judge glass only by lab measurements; when a number looks wrong, open the frames. Record every number with its run folder.
- Paths are relative to `packages/mobile/` unless they start with `docs/` or `packages/mobile/` (then relative to the repository root). Run every patch from the worktree root as `git apply --3way` (each patch names the blobs it applies to, so a line changed on `development` since `06d406bae` merges instead of failing; resolve a conflict keeping both sides' intent and say so in the task report).

## Execution setup

- First, the main session commits this plan and `docs/liquid_glass/02b-motion/research/proto-2b1/` to `development` (they live only on `proto/2b1` until then), so the feature branch carries the plan its rulings cite.
- Then work in a new worktree `/Users/omaraly/development/AI/Operator-2b1` on a new branch `feat/ios-liquid-glass-2b1` from `development`:
  `git -C /Users/omaraly/development/AI/Operator worktree add /Users/omaraly/development/AI/Operator-2b1 -b feat/ios-liquid-glass-2b1 development`
  then `cd /Users/omaraly/development/AI/Operator-2b1/packages/mobile && flutter pub get --offline`.
- This runs only on this Mac: a cloud session cannot reach the simulator.
- Never touch `/Users/omaraly/development/AI/Operator` (the shared checkout) after the `worktree add`, and read other worktrees only (Task 6 copies runs from them, after checking they still exist).
- Run the lab from `packages/mobile`. Pass run folders to `--into` as absolute paths. `lab.py prepare` drives Apple's apps and is not needed: install the backdrops into the two lab apps after their first build with
  `python3 -c "import sys; sys.path.insert(0, 'tool/glass_lab/harness'); import sim, build; u = sim.device(); sim.status_bar(u); [sim.install_backdrops(u, b, build.backdrops()) for b in (build.NATIVE_BUNDLE, build.EXAMPLE_BUNDLE)]"`.
- Gates for every task that touches their code (the "Expected" line of each task gives the count at that point):
  - app, from `packages/mobile`: `flutter analyze --no-pub` prints "No issues found!", `flutter test --no-pub` is green;
  - package, from `packages/mobile/packages/ios_liquid_glass`: `flutter analyze --no-pub`, `flutter test --no-pub`;
  - example, from `packages/mobile/packages/ios_liquid_glass/example`: `flutter analyze --no-pub`, `flutter test --no-pub`;
  - harness, from `packages/mobile`: `python3 -m unittest discover tool/glass_lab/harness/tests` prints OK;
  - `flutter test` prints a long SkSL error about `liquid_glass_geometry_blended` ("initializers are not permitted on arrays"); it is known and harmless (ROADMAP gotcha 3).

## Review Focus

1. **A list scrolled inside a container** (`GlassEffectContainer > ListView > GlassEffect`, Operator's sheets and toolbars). Expected: the glass moves with the list in the same frame, never springs after it, and lazily built items appear without materializing. Pinned by `a list scrolled inside a container moves its glass with the list at once, with no spring` (Task 13).
2. **A sibling inserted into a centred container** (`Center > GlassEffectContainer > Row`), which re-centres the container. Expected: the glass already there stays where it is on screen in the insertion frame and then springs to its new place; it never jumps. Pinned by `glass keeps its place on screen when a sibling is inserted and the centred container re-centres, then springs to its new place` (Task 13).
3. **A glass removed while its spring is in flight, or its whole container removed mid-animation.** Expected: the ghost starts from the visible progress it had (no jump, and no rise after the removal), and a disposed container stops its ticker and frees its snapshots without an exception. Pinned by `removing glass while it appears continues from its current visibility`, `visibility never rises after a removal, even right after insertion` and `a container removed while its glass animates disposes cleanly` (Tasks 13 and 14).
4. **The app rebuilds during an animation, or Reduce Motion switches during one.** Expected: the springs keep running from where they are; nothing restarts or stops (ruling 12; spec M8: a switch applies from the next change). Pinned by `rebuilding during an animation does not restart it` and `switching Reduce Motion during an animation neither restarts nor stops it` (Task 13).
5. **Sixteen glasses in a container while one leaves and another arrives.** Expected: the ghost and the arriving glass draw in their own layers, so the container's group never holds a seventeenth shape and the `UnsupportedError` cap is never hit, in any frame of the transition. Pinned by `a ghost draws in its own layer, so sixteen glasses, one leaving and one arriving never share one group` (Task 14).
6. **A glass the app moves every frame** (a slider thumb or sheet handle dragged with `setState`, glass inside an `AnimatedBuilder`, a toolbar riding the keyboard). Expected: the glass holds where it was in its first moving frame, then sits on its layout within 0.5 pt in every frame, its content with it and taps on its layout; a toggle after the motion springs again; changes inside `withGlassAnimation` spring even on consecutive frames (ruling 32). Pinned by the four tests ruling 32 names (Task 16).

## 2A's review lessons, and where this plan holds them

- **The measures compare the right regions on every side and backdrop:** every motion measure is read inside a pinned region per shape (Tasks 1 and 4), on both appearances and both backdrops of each scene, and the still check compares every 2A scene, accessibility mode and Operator scene case by case, and lists any case it cannot find (Task 20 Step 7).
- **Nothing passes by being absent:** an expected measure that is missing is judged as `inf`, an unpaired event and a missing touch fail (Task 4).
- **Fits are never stuck at a grid floor or ceiling without being reported:** `fitvis` writes `at_grid_edge` for every exponent, gain and the blur ramp, and the lab's own spring fit (`springfit.fit`) does too; a pair whose fit is on an edge fails as invalid (Tasks 3 and 4), and Task 20 Step 4 stops on a fitted value at an edge.
- **Tuning, fits and recordings refuse stale builds:** `fitvis`, `ghost_probe.py` and `cold_probe.py` call `build.require_fresh("example")`; `run` and `repeat` refuse a stale native build (Task 6); `reproduce.py` only reads recordings and needs no build (R10).
- **Diagnoses are backed by crops or numbers:** every ruling cites a run folder and a number, and `results-2b1.md` classes each failure with one (Task 20 Step 10).
- **Every Done number is recomputable from `result.json`:** `done_table.py` and `still_check.py` print the Done table's numbers from the runs' `result.json` files, and their counting is unit-tested (Task 20).
## What this plan expects to reach

Measured in the prototype after both review rounds. Noise floors are Task 9's and do not exist in the prototype, so the prototype column uses the fixed thresholds; the prototype's one-session, three-take native noise (`repeat-2b1`, not committed to `noise.json`) gives the expected column, applied pair by pair as `limits()` applies it (max(fixed, 1.5 × noise)). **Done item 4 is expected to stay partly failing**, for the classed causes below. Run folders are the prototype's. Progress measures (the seven `progress.*` measures per pair, the Done item 4 measures) are counted apart from the event and touch gates (`events.*`, `touches.*`).

| Done item (spec §8, 2B.1) | Prototype | Expected after Task 20 |
|---|---|---|
| 1 L1–L3, L5–L8 tested; known numbers reproduced | 175 harness tests. Reproduced: appear and disappear (ruling 6), not-an-alpha-fade on `photo` (ruling 5), v13 +12.00 / +4.67, `button.press` 138.33 → 154.33 and 174.33 → 190.33, menu open 0.26–0.30 / 0.74–0.81 (ruling 3). Short glass: +17.0 and +16.0 reproduce, 250 × 44's +17.67 does not (+14.33, both ends in L1's blind band; ruling 2). | Pass, with the 250 × 44 number recorded as not reproduced and why, and the 10–90% times judged against Task 9's noise. |
| 2 Noise floors for every 2B.1 scene and case | one session of three takes for the three materialize scenes only (`repeat-2b1`) | Pass (Task 9), motion, static and topology. |
| 3 N1, N2, N5, N7 and N6 (materialize) recorded | all recorded: materialize `20261003-032332`, Reduce Motion `20261003-033143`, interactive `20261003-044516`, press `20261003-044602`, spacing `20261003-044920` and `20261003-050837` (one appearance and backdrop each for the last three) | Pass. |
| 4 Materialize passes per shape under default, `.snappy`, `.bouncy` and Reduce Motion | **Partly failing.** Progress measures at the fixed limits 112 of 168 (normal) and 108 of 168 (Reduce Motion), 113 and 111 once R3's float slack counts the four `damping` values that equal their limit; every one judged. The event and touch gates 60 of 60 in each run. | **Partly failing: 120 of 168 (normal) and 119 of 168 (Reduce Motion) at 1.5 × the prototype's noise (the reviewer's 119 and 116, before R3), every remaining failure classed below** |
| 5 Still glass no worse than 2A | Pass on the final prototype: all 52 Flutter frames byte-identical to 2A's (`material.regular` 20, `tabbar.rest` 16, `button.press` 4, `navbar.inline` 12), no measure moved, `missing: 0` and `worse: 0` in each (4 of the 9 scenes Task 20 runs). | Pass for every 2A scene, accessibility mode and Operator scene, `missing: 0`. |
| 6 Gates | app 2,146, package 121, example 13, harness 175; `flutter analyze` clean in all three | Pass. |

**Why Done item 4 fails in part, and how each failure is classed** (normal run `20261003-113033`, Reduce Motion `20261003-120351`; counts out of 24 pairs per measure, at 1.5 × the three-take noise with R3's float slack):
1. **Spring shape, class (b), model limitation.** `response_pct` passes 7 and 7, `damping` 13 and 15. The gaps are a curve-shape mismatch, not noise: on one SwiftUI spring native's progress fits springs from 0.45 to 0.74 s and damping from 0.77 to 1.24 across the four backdrops (ruling 10's default-spring check), while the package draws every backdrop from that spring through one mapping per preset. The largest gaps are the `light` and `stripes` appears, 41–61% in response and up to 0.77 in damping, against noise of 15–21% and 0.05–0.10 at those pairs. The per-backdrop difference comes from what the pixels show (the lens's stripe shift and the light backdrops' brightening enter the progress measure), so it is not a mapping the package can take from its own state; `todo-2b1.md` carries the deciding measure, a per-appearance fit on `photo` alone, where no stripe shift enters.
2. **Timing by one to three frames, class (b), the same cause.** `t10_90_ms` passes 20 and 17: every failure is 25 ms (one 42 ms), and the noise at exactly those pairs is 0–8 ms, so no noise floor absorbs them. `settle_ms` passes 14 and 14.
3. **`.bouncy` appear settle on `light`, class (a), tunable.** 141–150 ms late in both `light` cases (normal) and on `dark-photo` under Reduce Motion: native overshoots 2.5–2.6% there and decays more slowly than its spring, where the package's single `.bouncy` gain gives 1.1–1.3%. A per-appearance gain would close it; it is in `todo-2b1.md` with that measure.
4. **Half-progress sharpness on dark `photo`, class (b)** (ruling 25): 6 of 24 pairs in each run; no blur ramp changes it.

Overshoot and RMS pass in all 48 pairs, the event and touch gates in all, and neither app stalls inside an event.
---

## File map

| Path (under `packages/mobile/` unless it starts with `docs/`) | Responsibility | Task |
|---|---|---|
| `tool/glass_lab/harness/track.py` (new), `tests/{synthetic,test_track}.py` (new) | Per-shape boxes and their blind band, progress and blur, topology, teardown cut | 1 |
| `tool/glass_lab/harness/touch.py` (new), `align.py`, `tests/test_touch.py` (new) | Marker reading, touches and steps; the marker kept out of the changed extent | 2 |
| `tool/glass_lab/harness/{springfit,manifest,metrics,analyze,tune,tonefit}.py`, `tests/{test_manifest,test_metrics}.py` | Tracks, motion and topology in the manifest; spring fits that report their grid edge; the new thresholds | 3 |
| `tool/glass_lab/harness/shapes.py` (new), `{analyze,report}.py`, `tests/test_shapes.py` (new) | Events by step, per-shape comparison, motion measures judged even when absent, stalls and first frames, still noise | 4 |
| `tool/glass_lab/native/GlassLab/{TouchMarker.swift (new),Lab.swift,GlassLabApp.swift}`, `native/GlassLabDriver/DriverTests.swift`, `harness/record.py`, `packages/ios_liquid_glass/example/lib/lab/{glass_lab_launch,glass_lab_marker,glass_lab_screen}.dart` | The touch marker in both apps; the fit tool's launch values | 5 |
| `tool/glass_lab/harness/reproduce.py` (new), `{lab,sim,build}.py`, `tool/glass_lab/noise.json`, `tests/test_lab.py` | `measure`, per-case `repeat` over sessions, `reboot`, the native stamp; reproduction of known numbers | 6 |
| `tool/glass_lab/harness/fitvis.py` (new), `lab.py`, `tests/test_fitvis.py` (new) | The fit tool: the materialize mapping, the blur ramp, Flutter's visibility table | 7 |
| `tool/glass_lab/native/GlassLab/MaterialScenes.swift`, `tool/glass_lab/scenes.json`, `tests/test_scenes_2b.py` (new) | N1, N2, N5, N7 scenes; materialize tracking and measures | 8 |
| `tool/glass_lab/noise.json` (by `repeat`) | Noise floors | 9 |
| `packages/ios_liquid_glass/lib/src/motion/{glass_animation,glass_spring,ios27_motion}.dart` (new) | Animation API with SwiftUI's presets, springs, fitted table seed | 10 |
| `packages/ios_liquid_glass/lib/src/motion/{glass_shape_motion,glass_material_source}.dart` (new), `lib/src/{liquid_glass_settings,liquid_glass_render_scope,liquid_glass,liquid_glass_blend_group,glass_shadow}.dart`, `lib/src/rendering/{liquid_glass_layer,liquid_glass_render_object}.dart`, `lib/src/internal/render_liquid_glass_geometry.dart` | Visibility, drawn-rect and material-source hooks; the blur ramp (`LiquidGlassSettings.atVisibility`) | 11 |
| `packages/ios_liquid_glass/lib/src/motion/{glass_frame,glass_materialize,glass_motion_coordinator}.dart` (new), `test/motion/glass_member_test.dart` (new) | The materialize mapping; the coordinator: members, live drawn rects, offset springs and their rule, following, pending ghosts | 12 |
| `packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart` (new), `lib/src/api/{glass_effect_transition (new),glass_effect,glass_effect_container}.dart`, `lib/ios_liquid_glass.dart` | Container glass joins the coordinator and materializes; the container's space; the API | 13 |
| `packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart`, `lib/src/api/{glass_effect,glass_effect_container}.dart` | Removal ghosts with content snapshots | 14 |
| `packages/ios_liquid_glass/lib/src/api/{glass_effect,glass_material_context}.dart`, `lib/src/material/glass_material_override.dart`, `test/glass_effect_test.dart` | Material from the drawn size, with no post-frame rebuild | 15 |
| `packages/ios_liquid_glass/lib/src/api/glass_effect.dart` | Moves and resizes after a rebuild; app-driven motion and scrolls followed exactly | 16 |
| `packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart`, `lib/src/api/glass_effect.dart` | Standalone transitions; ghosts in the nearest `Overlay` | 17 |
| `packages/ios_liquid_glass/lib/assets/shaders/{liquid_glass_final_render,liquid_glass_geometry_blended}.frag`, `lib/src/rendering/liquid_glass_render_object.dart`, `lib/src/liquid_glass_blend_group.dart` | Edge light from the full thickness | 18 |
| `packages/ios_liquid_glass/example/lib/lab/scenes/motion_scenes.dart` (new), `glass_lab_registry.dart`, `scenes/material_scenes.dart` | Live materialize scenes (warmed), fit, ghost and cold-start tools | 19 |
| `tool/glass_lab/harness/{still_check,done_table,rim,rim_check,ghost_probe,cold_probe}.py` (new), `tests/test_done_numbers.py` (new), `docs/liquid_glass/02b-motion/{results-2b1,todo-2b1}.md` (new) | Verification | 20 |
| `docs/liquid_glass/ROADMAP.md`, `packages/ios_liquid_glass/{README,FORK,CHANGELOG}.md`, `tool/glass_lab/README.md` | Documents | 21 |

**Task order and why** (the brief's order: lab, native references and noise, coordinator and springs, materialize, example scenes, verification, documents).
1–7. The lab first, so every later number is measured the new way, and the known numbers are reproduced before anything is judged (spec decision 4). The tracker, the marker reader, the manifest and spring-fit groundwork, the per-scene measures, the marker in the apps, the lab commands and the fit tool are separate tasks so each can be reviewed on its own.
8–9. Native references, then their noise floors, which need the scenes.
10–17. Springs and the API, the render hooks, the coordinator and the mapping, container glass in three steps (joining and materializing, removal ghosts, material from the drawn size), then the move rule and standalone glass's transitions, each a task a reviewer can accept or reject on its own.
18. Materialize's edge light, the one shader change.
19. The example's live scenes, which need the API.
20. Verification, which needs everything, and re-fits the table from this branch's native runs.
21. Documents.

---
### Task 1: The tracker: per-shape boxes, progress and blur, topology and the teardown cut (L1, L2, L3, L6)

**Files:**
- Create: `tool/glass_lab/harness/track.py`, `tool/glass_lab/harness/tests/synthetic.py`
- Test: `tool/glass_lab/harness/tests/test_track.py`

**Interfaces:**
- Produces:
  - `track.pixel_rect(region) -> (x, y, w, h)` in pixels, every value even (ffmpeg crops of yuv420 video need even origins and sizes);
  - `track.edges(bare)`, `track.glass_mask(frame, bare, edge_map)`, `track.box_pixels(frame, bare, edge_map) -> (left, top, right, bottom) | None` in pixels, and `track.box(...) -> (x, y, w, h) | None` in points relative to the crop; the detector is ruling 1's;
  - `track.shape_row(frame, bare, edge_map, origin) -> {"width", "height", "cx", "cy", "luma", "band"}`: centres absolute, in points; an empty box gives width 0 and NaN centres; `band` is 1.0 when any box edge lies within the 5 px edge dilation of a backdrop edge stronger than 20 levels (`track.in_band`), where the raised threshold can hide up to two pixels of rim (finding 18, ruling 1);
  - `track.progress_row(frame_pt, bare_pt, full_pt, inner) -> {"progress", "residual", "sharpness"}` at point resolution (L3);
  - `track.topology(mask) -> {"count", "neck"}` and `track.topology_row(frame, bare, edge_map)` (L2): separate glass components (point-resolution mask, at least 20 pt² each) and, when they are one, the narrowest cross-section in points along the segment between the two lobes' centroids (ruling 23); one component whose segment crosses no glass reads `neck` NaN, never 0, so it fails any neck comparison instead of passing as a join (finding 30); `track.still_mask(frame, bare)` for lossless stills;
  - `track.extract(video, rect, dest) -> align.Frames` (every frame of the video, full resolution, cropped), `track.clip(frames, start, end)` (keeps the last frame before `start`, retimed to `start`, as the rest frame), `track.teardown_cut(frames, settled_crop)` (L6: nothing after the last frame within 6 levels of the best match to `settled.png` is analysed).
- `tests/synthetic.py` holds the synthetic frames and series every harness test of Tasks 1–4 builds on (`stripes`, `with_codec_lines`, `draw`, `frames`, `disks`, `spring_series`, `capture_of`).

- [ ] **Step 1: Write the failing tests.** Create `tool/glass_lab/harness/tests/synthetic.py`:

```python
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import align
import springfit


def stripes(width=120, height=60, period=40):
    image = np.zeros((height * 3, width * 3, 3), dtype=np.float32)
    colours = [(230, 70, 80), (240, 180, 90), (30, 200, 100)]
    for x in range(width * 3):
        image[:, x] = colours[(x // (period * 3)) % len(colours)]
    return image


def with_codec_lines(image, period=40, amplitude=90.0):
    noisy = image.copy()
    for x in range(period * 3, image.shape[1], period * 3):
        noisy[:, x - 1 : x + 1] += amplitude
    return np.clip(noisy, 0, 255)


def draw(image, box, value=(250, 250, 250)):
    x, y, w, h = (int(round(v * 3)) for v in box)
    out = image.copy()
    out[y : y + h, x : x + w] = value
    return out


def frames(paths, times):
    return align.Frames(paths, times)


def disks(gap, bridge=0, height=120, width=240):
    image = np.full((height * 3, width * 3, 3), 40, dtype=np.float32)
    yy, xx = np.mgrid[0 : height * 3, 0 : width * 3]
    for cx in (60, 140 + gap):
        image[(xx - cx * 3) ** 2 + (yy - 60 * 3) ** 2 <= (40 * 3) ** 2] = 250
    if bridge:
        image[(60 - bridge // 2) * 3 : (60 + bridge // 2) * 3, 95 * 3 : 105 * 3] = 250
    return image


def spring_series(response, damping, appearing=True, exponent=1.0, seconds=0.9):
    t = np.arange(0, seconds, 1 / align.GRID_HZ)
    s = springfit.step_response(t, response, damping)
    progress = s if appearing else (1 - np.clip(s, 0, 1)) ** exponent
    flat = np.zeros_like(t)
    return {"width": flat + 250, "height": flat + 88, "cx": flat + 201, "cy": flat + 451, "luma": flat + 100, "progress": progress, "sharpness": flat, "residual": flat}


def capture_of(*series, steps=None):
    return {"events": [{"onset": 1.0 + i, "series": {"block": s}, "step": None if steps is None else steps[i]} for i, s in enumerate(series)], "touches": []}
```

and `tool/glass_lab/harness/tests/test_track.py`:

```python
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import track
from synthetic import disks, draw, frames, stripes, with_codec_lines


class PixelRectTests(unittest.TestCase):
    def test_rects_are_even_and_cover_the_region(self):
        x, y, w, h = track.pixel_rect((46.5, 377.33, 310, 148))
        self.assertEqual((x % 2, y % 2, w % 2, h % 2), (0, 0, 0, 0))
        self.assertLessEqual(x, 46.5 * 3)
        self.assertLessEqual(y, 377.33 * 3)
        self.assertGreaterEqual(x + w, (46.5 + 310) * 3)
        self.assertGreaterEqual(y + h, (377.33 + 148) * 3)


class BoxTests(unittest.TestCase):
    def test_finds_a_drawn_box_to_a_third_of_a_point_per_edge(self):
        bare = stripes()
        frame = draw(bare, (30, 20, 50, 20))
        x, y, w, h = track.box(frame, bare, track.edges(bare))
        self.assertAlmostEqual(x, 30, delta=0.34)
        self.assertAlmostEqual(y, 20, delta=0.34)
        self.assertAlmostEqual(w, 50, delta=0.67)
        self.assertAlmostEqual(h, 20, delta=0.67)

    def test_codec_lines_at_backdrop_edges_do_not_widen_the_box(self):
        bare = stripes()
        frame = with_codec_lines(draw(bare, (50, 20, 20, 20)))
        x, y, w, h = track.box(frame, bare, track.edges(bare))
        self.assertAlmostEqual(x, 50, delta=0.34)
        self.assertAlmostEqual(w, 20, delta=0.67)
        self.assertAlmostEqual(h, 20, delta=0.67)

    def test_a_box_edge_on_a_backdrop_edge_is_flagged_as_inside_the_blind_band(self):
        bare = stripes()
        on_edge = track.shape_row(draw(bare, (40, 20, 30, 20)), bare, track.edges(bare), (0, 0))
        clear = track.shape_row(draw(bare, (50, 20, 20, 20)), bare, track.edges(bare), (0, 0))
        self.assertEqual(on_edge["band"], 1.0)
        self.assertEqual(clear["band"], 0.0)

    def test_a_box_whose_top_and_bottom_cross_a_backdrop_edge_is_not_flagged(self):
        bare = stripes()
        crossing = track.shape_row(draw(bare, (30, 20, 30, 20)), bare, track.edges(bare), (0, 0))
        self.assertEqual(crossing["band"], 0.0)

    def test_nothing_drawn_has_no_box(self):
        bare = stripes()
        self.assertIsNone(track.box(with_codec_lines(bare), bare, track.edges(bare)))

    def test_shape_rows_report_absolute_centres(self):
        bare = stripes()
        row = track.shape_row(draw(bare, (30, 20, 50, 20)), bare, track.edges(bare), (100, 200))
        self.assertAlmostEqual(row["cx"], 155, delta=0.5)
        self.assertAlmostEqual(row["cy"], 230, delta=0.5)
        empty = track.shape_row(bare, bare, track.edges(bare), (100, 200))
        self.assertEqual(empty["width"], 0.0)
        self.assertTrue(np.isnan(empty["cx"]))


class ProgressTests(unittest.TestCase):
    def setUp(self):
        rng = np.random.default_rng(3)
        self.bare = rng.uniform(0, 255, (40, 60, 3)).astype(np.float32)
        self.full = self.blur(self.bare, 6) + 30
        self.inner = (slice(5, 35), slice(5, 55))

    @staticmethod
    def blur(image, passes):
        for _ in range(passes):
            image = (image + np.roll(image, 1, 0) + np.roll(image, -1, 0) + np.roll(image, 1, 1) + np.roll(image, -1, 1)) / 5
        return image

    def test_an_alpha_mix_reads_its_alpha_with_no_residual(self):
        frame = self.bare + 0.3 * (self.full - self.bare)
        row = track.progress_row(frame, self.bare, self.full, self.inner)
        self.assertAlmostEqual(row["progress"], 0.3, places=4)
        self.assertAlmostEqual(row["residual"], 0.0, places=3)
        self.assertAlmostEqual(row["sharpness"], 0.0, places=3)

    def test_a_blurred_mix_is_not_an_alpha_fade_and_is_softer(self):
        blurred = self.blur(self.bare + 0.5 * (self.full - self.bare), 2)
        row = track.progress_row(blurred, self.bare, self.full, self.inner)
        self.assertGreater(row["residual"], 5)
        self.assertLess(row["sharpness"], -1)


class TopologyTests(unittest.TestCase):
    def setUp(self):
        self.bare = np.full((360, 720, 3), 40, dtype=np.float32)
        self.edges = track.edges(self.bare)

    def test_separate_glass_counts_two_with_no_neck(self):
        self.assertEqual(track.topology_row(disks(20), self.bare, self.edges), {"count": 2.0, "neck": 0.0})

    def test_merged_glass_counts_one_and_measures_its_narrowest_neck(self):
        row = track.topology_row(disks(0, bridge=20), self.bare, self.edges)
        self.assertEqual(row["count"], 1.0)
        self.assertAlmostEqual(row["neck"], 20, delta=1)
        overlapping = track.topology_row(disks(-10), self.bare, self.edges)
        self.assertAlmostEqual(overlapping["neck"], 2 * (40**2 - 35**2) ** 0.5, delta=2)

    def test_still_screenshots_use_the_low_lossless_threshold(self):
        faint = self.bare.copy()
        yy, xx = np.mgrid[0:360, 0:720]
        faint[(xx - 180) ** 2 + (yy - 180) ** 2 <= 120**2] += 10
        self.assertEqual(track.topology(track.still_mask(faint, self.bare))["count"], 1.0)
        self.assertEqual(track.topology_row(faint, self.bare, self.edges)["count"], 0.0)

    def test_one_component_with_no_neck_is_not_a_join(self):
        mask = np.zeros((90, 300), dtype=bool)
        mask[30:60, 30:120] = True
        mask[30:60, 180:270] = True
        mask[30:33, 30:270] = True
        found = track.topology(mask)
        self.assertEqual(found["count"], 1.0)
        self.assertTrue(np.isnan(found["neck"]))


class TeardownTests(unittest.TestCase):
    def test_frames_after_the_last_settled_match_are_dropped(self):
        import tempfile
        from PIL import Image
        settled = np.full((30, 30, 3), 100, dtype=np.float32)
        with tempfile.TemporaryDirectory() as temp:
            paths = []
            for i, value in enumerate((100, 140, 102, 101, 30)):
                path = Path(temp) / f"{i}.png"
                Image.fromarray(np.full((30, 30, 3), value, dtype=np.uint8)).save(path)
                paths.append(path)
            kept = track.teardown_cut(frames(paths, [0.0, 0.1, 0.2, 0.3, 0.4]), settled)
            self.assertEqual(kept.times, [0.0, 0.1, 0.2, 0.3])

    def test_the_rest_frame_before_the_window_is_kept_and_retimed(self):
        clipped = track.clip(frames(["a", "b", "c", "d"], [1.0, 5.0, 5.5, 9.0]), 4.8, 6.0)
        self.assertEqual(clipped.paths, ["a", "b", "c"])
        self.assertEqual(clipped.times, [4.8, 5.0, 5.5])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and see them fail.**

Run (from `packages/mobile`): `python3 -m unittest tool/glass_lab/harness/tests/test_track.py`
Expected: `ModuleNotFoundError: No module named 'track'`.

- [ ] **Step 3: Write the tracker.** Create `tool/glass_lab/harness/track.py`:

```python
import re
import subprocess
from pathlib import Path

import numpy as np

import align
import metrics

BOX_THRESHOLD = 15.0
EDGE_GAIN = 1.0
EDGE_REACH = 5
MIN_RUN = 6
SETTLED_MARGIN = 6.0
PTS = re.compile(r"pts_time:([0-9.]+)")


def pixel_rect(region, scale=metrics.SCALE):
    x, y, w, h = region
    left, top = int(np.floor(x * scale / 2)) * 2, int(np.floor(y * scale / 2)) * 2
    right, bottom = int(np.ceil((x + w) * scale / 2)) * 2, int(np.ceil((y + h) * scale / 2)) * 2
    return left, top, right - left, bottom - top


def crop_px(image, rect):
    x, y, w, h = rect
    return image[y : y + h, x : x + w]


def _box_filter(values, size, reduce):
    pad = size // 2
    padded = np.pad(values, pad, mode="edge")
    height, width = values.shape
    out = None
    for dy in range(size):
        for dx in range(size):
            window = padded[dy : dy + height, dx : dx + width]
            out = window.copy() if out is None else reduce(out, window)
    return out


def smooth(values):
    return _box_filter(values, 3, np.add) / 9.0


def edges(bare):
    gradient = np.zeros(bare.shape[:2], dtype=np.float32)
    gradient[:, 1:] = np.abs(bare[:, 1:] - bare[:, :-1]).max(axis=2)
    gradient[1:, :] = np.maximum(gradient[1:, :], np.abs(bare[1:] - bare[:-1]).max(axis=2))
    return _box_filter(gradient, EDGE_REACH, np.maximum)


def glass_mask(frame, bare, edge_map):
    difference = smooth(np.abs(frame - bare).max(axis=2))
    return difference > BOX_THRESHOLD + EDGE_GAIN * edge_map


BAND_EDGE = 20.0


def box_pixels(frame, bare, edge_map):
    mask = glass_mask(frame, bare, edge_map)
    columns = np.nonzero(mask.sum(axis=0) >= MIN_RUN)[0]
    rows = np.nonzero(mask.sum(axis=1) >= MIN_RUN)[0]
    if len(columns) == 0 or len(rows) == 0:
        return None
    return int(columns[0]), int(rows[0]), int(columns[-1]), int(rows[-1])


def box(frame, bare, edge_map, scale=metrics.SCALE):
    found = box_pixels(frame, bare, edge_map)
    if found is None:
        return None
    left, top, right, bottom = found
    return (left / scale, top / scale, (right - left + 1) / scale, (bottom - top + 1) / scale)


def in_band(edge_map, found):
    left, top, right, bottom = found
    reach = EDGE_REACH // 2
    columns = [edge_map[top : bottom + 1, max(0, c - reach) : c + reach + 1] for c in (left, right)]
    rows = [edge_map[max(0, r - reach) : r + reach + 1, left : right + 1].T for r in (top, bottom)]
    return any(part.size and float((part.max(axis=1) > BAND_EDGE).mean()) > 0.5 for part in columns + rows)


def shape_row(frame, bare, edge_map, origin, scale=metrics.SCALE):
    found = box_pixels(frame, bare, edge_map)
    luma = float(metrics.luma(frame).mean())
    if found is None:
        return {"width": 0.0, "height": 0.0, "cx": float("nan"), "cy": float("nan"), "luma": luma, "band": 0.0}
    left, top, right, bottom = found
    x, y, w, h = left / scale, top / scale, (right - left + 1) / scale, (bottom - top + 1) / scale
    return {"width": float(w), "height": float(h), "cx": float(origin[0] + x + w / 2), "cy": float(origin[1] + y + h / 2), "luma": luma, "band": float(in_band(edge_map, found))}


def laplacian(image):
    gray = metrics.luma(image)
    centre = gray[1:-1, 1:-1] * 4 - gray[:-2, 1:-1] - gray[2:, 1:-1] - gray[1:-1, :-2] - gray[1:-1, 2:]
    return float(np.abs(centre).mean())


def progress_row(frame, bare, full, inner):
    travel = full - bare
    energy = float((travel**2).sum())
    if energy <= 0:
        return {"progress": float("nan"), "residual": float("nan"), "sharpness": float("nan")}
    alpha = float(((frame - bare) * travel).sum() / energy)
    mix = bare + alpha * travel
    rows, columns = inner
    return {
        "progress": alpha,
        "residual": float(np.abs(frame - mix).mean()),
        "sharpness": laplacian(frame[rows, columns]) - laplacian(mix[rows, columns]),
    }


def extract(video, rect, dest):
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    for old in dest.glob("*.png"):
        old.unlink()
    x, y, w, h = rect
    process = subprocess.run(
        [
            "ffmpeg", "-loglevel", "info", "-y", "-i", str(video),
            "-fps_mode", "passthrough",
            "-vf", f"crop={w}:{h}:{x}:{y},showinfo",
            str(dest / "%06d.png"),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    times = [float(t) for t in PTS.findall(process.stderr)]
    paths = sorted(dest.glob("*.png"))
    count = min(len(paths), len(times))
    return align.Frames(paths[:count], times[:count])


def clip(frames, start, end):
    before = [i for i, t in enumerate(frames.times) if t < start]
    inside = [i for i, t in enumerate(frames.times) if start <= t <= end]
    chosen = ([before[-1]] if before else []) + inside
    times = [max(frames.times[i], start) for i in chosen]
    return align.Frames([frames.paths[i] for i in chosen], times)


def teardown_cut(frames, settled):
    if len(frames) == 0:
        return frames
    distances = [metrics.mad(frame, settled) for frame in frames]
    limit = min(distances) + SETTLED_MARGIN
    last = max(i for i, d in enumerate(distances) if d <= limit)
    return align.Frames(frames.paths[: last + 1], frames.times[: last + 1])


TOPOLOGY_MIN_AREA = 20


def point_mask(mask, scale=metrics.SCALE):
    height, width = mask.shape[0] // scale, mask.shape[1] // scale
    return mask[: height * scale, : width * scale].reshape(height, scale, width, scale).mean(axis=(1, 3)) >= 0.5


def components(mask):
    found = []
    for area, box in metrics._components(mask):
        if area >= TOPOLOGY_MIN_AREA:
            found.append(box)
    return found


def lobes(mask):
    ys, xs = np.nonzero(mask)
    if len(xs) < 2:
        return None
    points = np.stack([xs, ys], axis=1).astype(np.float64) + 0.5
    centre = points.mean(axis=0)
    spread = np.cov((points - centre).T)
    values, vectors = np.linalg.eigh(spread)
    axis = vectors[:, int(np.argmax(values))]
    side = (points - centre) @ axis
    if (side < 0).sum() == 0 or (side >= 0).sum() == 0:
        return None
    return points[side < 0].mean(axis=0), points[side >= 0].mean(axis=0)


def cross_section(mask, point, normal):
    height, width = mask.shape
    length = 0
    for direction in (1, -1):
        step = 0 if direction == 1 else 1
        while True:
            x, y = point + normal * direction * step
            ix, iy = int(np.floor(x)), int(np.floor(y))
            if not (0 <= ix < width and 0 <= iy < height and mask[iy, ix]):
                break
            length += 1
            step += 1
    return length


def neck(mask, scale=metrics.SCALE):
    found = lobes(mask)
    if found is None:
        return 0.0
    a, b = found
    span = float(np.linalg.norm(b - a))
    if span < 1:
        return 0.0
    along = (b - a) / span
    normal = np.array([-along[1], along[0]])
    widths = [cross_section(mask, a + along * t, normal) for t in np.arange(0, span + 1e-9, 1.0)]
    return float(min(widths)) / scale if widths else 0.0


STILL_THRESHOLD = 6.0


def still_mask(frame, bare):
    return smooth(np.abs(frame - bare).max(axis=2)) > STILL_THRESHOLD


def topology(mask):
    parts = components(point_mask(mask))
    if len(parts) != 1:
        return {"count": float(len(parts)), "neck": 0.0}
    width = neck(mask)
    return {"count": 1.0, "neck": width if width > 0 else float("nan")}


def topology_row(frame, bare, edge_map):
    return topology(glass_mask(frame, bare, edge_map))
```

- [ ] **Step 4: Run the new tests, then every harness test.**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_track.py`
Expected: `Ran 15 tests` … `OK`.
Run: `python3 -m unittest discover tool/glass_lab/harness/tests`
Expected: `Ran 119 tests` … `OK`.

- [ ] **Step 5: Commit.**

```bash
git add packages/mobile/tool/glass_lab/harness/track.py packages/mobile/tool/glass_lab/harness/tests/synthetic.py packages/mobile/tool/glass_lab/harness/tests/test_track.py
git commit -m "feat(glass-lab): per-shape boxes, progress and blur, topology and the teardown cut

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Touch phases read from the on-screen marker (L5, the reader)

**Files:**
- Create: `tool/glass_lab/harness/touch.py`
- Modify: `tool/glass_lab/harness/align.py`
- Test: `tool/glass_lab/harness/tests/test_touch.py`

**Interfaces:**
- Consumes: `track.extract`, `track.pixel_rect` (Task 1); `align.extent` (2A).
- Produces: `touch.MARKER = (16, 662, 18, 18)` (points); `touch.classify(pixels) -> "down" | "move" | "up" | "idle" | "unknown"`; `touch.read(video, dest) -> [(down, up), ...]` in video seconds (a tap shorter than one video frame shows only its blue release frame and counts as a touch at that frame, ruling 7); `touch.touch_steps(steps)`, `touch.expected_touches(steps)` (a `doubleTap` step counts two touches), `touch.owner(onset, steps, windows)` (the step whose touch began last before the onset), `touch.step_times(steps, windows)` (release for `tap` and `doubleTap`, touch-down for `press` and `pressDrag`); `touch.without_marker(boxes)`, `touch.marker_free(rect)`; `align.extent(frames, ..., ignore=())` leaves out the 8 pt tiles over each ignored rect and one tile around it, and the analysis passes `touch.MARKER` (Task 3): `extent` returns one box around every changed tile, so the marker's colour changes would otherwise stretch a still scene's region from the glass to the marker (the prototype's `button.press` region grew from 2A's 92, 356, 216 × 192 to 4, 356, 304 × 336 and its `mad` moved 7.13 → 3.29 on an unchanged Flutter frame until this was fixed).

- [ ] **Step 1: Write the failing tests.** Create `tool/glass_lab/harness/tests/test_touch.py`:

```python
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import align
import touch


class TouchTests(unittest.TestCase):
    def test_colours_classify(self):
        self.assertEqual(touch.classify(np.full((4, 4, 3), (255, 0, 0))), "down")
        self.assertEqual(touch.classify(np.full((4, 4, 3), (0, 255, 0))), "move")
        self.assertEqual(touch.classify(np.full((4, 4, 3), (0, 0, 255))), "up")
        self.assertEqual(touch.classify(np.full((4, 4, 3), (5, 5, 5))), "idle")
        self.assertEqual(touch.classify(np.full((4, 4, 3), (128, 128, 128))), "unknown")

    def test_touches_pair_each_down_with_its_release(self):
        states = [(0.0, "idle"), (1.0, "down"), (1.5, "move"), (2.0, "up"), (2.3, "idle"), (3.0, "down"), (3.05, "up"), (3.1, "down"), (3.2, "up")]
        self.assertEqual(touch.touches(states), [(1.0, 2.0), (3.0, 3.05), (3.1, 3.2)])

    def test_a_tap_shorter_than_a_frame_shows_only_its_release(self):
        self.assertEqual(touch.touches([(0.0, "idle"), (17.578, "up"), (17.797, "idle")]), [(17.578, 17.578)])

    def test_events_belong_to_the_step_whose_touch_came_last(self):
        steps = [{"wait": 0.5}, {"tap": "toggle"}, {"wait": 1.2}, {"press": {"at": "glass", "duration": 1.0}}]
        windows = [(1.0, 1.1), (3.0, 4.0)]
        self.assertIsNone(touch.owner(0.5, steps, windows))
        self.assertEqual(touch.owner(1.2, steps, windows), 1)
        self.assertEqual(touch.owner(3.05, steps, windows), 3)
        self.assertEqual(touch.step_times(steps, windows), {1: 1.1, 3: 3.0})

    def test_the_marker_is_never_a_glass_box(self):
        self.assertEqual(touch.without_marker([(16, 662, 18, 18), (76, 400, 250, 88)]), [(76, 400, 250, 88)])

    def test_the_marker_never_joins_the_changed_extent(self):
        first = np.zeros((800, 400, 3), dtype=np.float32)
        changed = first.copy()
        changed[400:480, 96:200] = 255
        changed[662:680, 16:34] = 255
        self.assertEqual(align.extent([first, changed]), [(16, 400, 184, 280)])
        self.assertEqual(align.extent([first, changed], ignore=(touch.MARKER,)), [(96, 400, 104, 80)])
        marker_only = first.copy()
        marker_only[662:680, 16:34] = 255
        self.assertEqual(align.extent([first, marker_only], ignore=(touch.MARKER,)), [])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and see them fail.**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_touch.py`
Expected: `ModuleNotFoundError: No module named 'touch'`.

- [ ] **Step 3: Write the reader.** Create `tool/glass_lab/harness/touch.py`:

```python
import numpy as np

import metrics
import track

MARKER = (16, 662, 18, 18)
MARKER_INSET = 6
COLOUR_MARGIN = 80.0
DARK = 60.0
TOUCH_KINDS = ("tap", "doubleTap", "press", "pressDrag")


def marker_rect():
    x, y, w, h = MARKER
    return track.pixel_rect((x + MARKER_INSET, y + MARKER_INSET, w - 2 * MARKER_INSET, h - 2 * MARKER_INSET))


def classify(pixels):
    r, g, b = (float(v) for v in np.asarray(pixels, dtype=np.float32).reshape(-1, 3).mean(axis=0))
    if r - max(g, b) > COLOUR_MARGIN:
        return "down"
    if g - max(r, b) > COLOUR_MARGIN:
        return "move"
    if b - max(r, g) > COLOUR_MARGIN:
        return "up"
    if max(r, g, b) < DARK:
        return "idle"
    return "unknown"


def phases(frames):
    return [(time, classify(frame)) for time, frame in zip(frames.times, frames)]


def touches(states):
    found, start, previous = [], None, "idle"
    for time, state in states:
        if state in ("down", "move") and previous not in ("down", "move"):
            start = time
        if state == "up" and previous in ("down", "move") and start is not None:
            found.append((start, time))
            start = None
        elif state == "up" and previous == "idle":
            found.append((time, time))
        if state != "unknown":
            previous = state
    return found


def touch_steps(steps):
    return [index for index, step in enumerate(steps) if next(iter(step)) in TOUCH_KINDS]


def expected_touches(steps):
    return sum(2 if next(iter(steps[index])) == "doubleTap" else 1 for index in touch_steps(steps))


def step_times(steps, windows):
    times = {}
    for index, window in zip(touch_steps(steps), windows):
        kind = next(iter(steps[index]))
        times[index] = window[1] if kind in ("tap", "doubleTap") else window[0]
    return times


def owner(onset, steps, windows):
    owned = None
    for index, window in zip(touch_steps(steps), windows):
        if window[0] <= onset + 1e-6:
            owned = index
    return owned


def read(video, dest):
    return touches(phases(track.extract(video, marker_rect(), dest)))


def is_marker(box):
    x, y, w, h = box
    mx, my, mw, mh = MARKER
    return x >= mx - 2 and y >= my - 2 and x + w <= mx + mw + 2 and y + h <= my + mh + 2


def without_marker(boxes):
    return [box for box in boxes if not is_marker(box)]


def marker_free(rect):
    return not metrics.overlaps(rect, MARKER, slack=0)
```

- [ ] **Step 4: Leave the marker out of the changed extent.** Apply to `tool/glass_lab/harness/align.py`:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/align.py b/packages/mobile/tool/glass_lab/harness/align.py
index ea5b7222f977bf7340cf1a005d62d616c405cca9..b923787cc9be4272bd31b4a74699e45bddba28b4 100644
--- a/packages/mobile/tool/glass_lab/harness/align.py
+++ b/packages/mobile/tool/glass_lab/harness/align.py
@@ -97,7 +97,7 @@
     return {key: np.interp(grid, times, [r[key] for r in rows]).tolist() for key in KEYS}
 
 
-def extent(frames, threshold=EXTENT_THRESHOLD, tile=EXTENT_TILE):
+def extent(frames, threshold=EXTENT_THRESHOLD, tile=EXTENT_TILE, ignore=()):
     first, peak = None, None
     for frame in frames:
         if first is None:
@@ -110,6 +110,8 @@
     if peak is None:
         return []
     peak[: SKIP_TOP_POINTS // tile] = 0
+    for x, y, w, h in ignore:
+        peak[max(0, y // tile - 1) : (y + h) // tile + 2, max(0, x // tile - 1) : (x + w) // tile + 2] = 0
     ys, xs = np.nonzero(peak > threshold)
     if len(xs) == 0:
         return []
PATCH
```

- [ ] **Step 5: Run the tests.**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_touch.py` → `Ran 6 tests` … `OK`.
Run: `python3 -m unittest discover tool/glass_lab/harness/tests` → `Ran 125 tests` … `OK`.

- [ ] **Step 6: Commit.**

```bash
git add packages/mobile/tool/glass_lab/harness/touch.py packages/mobile/tool/glass_lab/harness/align.py packages/mobile/tool/glass_lab/harness/tests/test_touch.py
git commit -m "feat(glass-lab): read touch phases from the on-screen marker in the video

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Tracks, motion and topology in the manifest, spring fits that report their grid edge, and the new thresholds (groundwork for L1–L3, L7)

**Files:**
- Modify: `tool/glass_lab/harness/manifest.py`, `springfit.py`, `metrics.py`, `analyze.py`, `tune.py`, `tonefit.py`
- Test: `tool/glass_lab/harness/tests/test_manifest.py`, `tests/test_metrics.py`

**Interfaces:**
- Consumes: `touch.MARKER`, `touch.without_marker` and `align.extent(..., ignore=)` (Task 2).
- Produces:
  - `manifest.Scene.track` is a tuple of region names (a single string still means a list of one), `Scene.topology` likewise, `Scene.motion` a tuple of measure names, `Scene.touches` is true when a step is a tap, double tap, press or press-drag; `manifest.MOTION_MEASURES`; `manifest.tracks(value)`;
  - `springfit.fit` returns `at_grid_edge`, and its damping grid now reaches 2.0 (finding 5);
  - `metrics.THRESHOLDS`: `progress_rms` 0.05, `sharpness` 1.0, `neck_pt` 1.0, `count` 0 (spec L2, L3);
  - `analyze.region_for` is the union of a scene's tracked regions, and leaves the touch marker out of a still scene's region (Task 2); `analyze.elements_for` leaves every tracked region out of the rim elements; the tuner and the tone fit read the tracks as a tuple.
- Nothing judges motion per shape yet; Task 4 builds that on these.

- [ ] **Step 1: Write the failing tests.** Extend `test_manifest.py` and `test_metrics.py`:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py b/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py
index 631a71fe6bec3f8f39ae13f6b0a3e22002cdf18d..ec7af215eb2706b5c8b7ecf5c299e42f95a6a2f0 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py
@@ -6,6 +6,7 @@
 
 sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
 
+import analyze
 import manifest
 
 REGISTERED = re.compile(r'^\s*"([a-z0-9.]+)": \{ AnyView', re.M)
@@ -85,5 +86,38 @@
         self.assertEqual(lab, registered)
 
 
+class TrackTests(unittest.TestCase):
+    def base(self, **changes):
+        entry = {"id": "x", "group": "material", "title": "t", "inventory": "2.13", "app": "lab", "backdrops": ["stripes"], "appearances": ["dark"], "steps": [], "regions": {"a": [0, 0, 1, 1], "b": [1, 1, 1, 1]}}
+        entry.update(changes)
+        return entry
+
+    def test_a_single_track_name_means_a_list_of_one(self):
+        self.assertEqual(manifest.parse([self.base(track="a")])[0].track, ("a",))
+        self.assertEqual(manifest.parse([self.base(track=["a", "b"])])[0].track, ("a", "b"))
+        self.assertEqual(manifest.parse([self.base()])[0].track, ())
+
+    def test_topology_regions_are_validated(self):
+        self.assertEqual(manifest.parse([self.base(topology="a")])[0].topology, ("a",))
+        self.assertTrue(any("topology names an unknown region" in e for e in manifest.validate([self.base(topology=["z"])])))
+        self.assertEqual(manifest.validate([self.base(topology=["a", "b"])]), [])
+
+    def test_tracks_and_motion_measures_are_validated(self):
+        self.assertTrue(any("unknown region" in e for e in manifest.validate([self.base(track=["a", "c"])])))
+        self.assertTrue(any("non-empty list" in e for e in manifest.validate([self.base(track=[])])))
+        self.assertTrue(any("unknown motion measure progress.wobble" in e for e in manifest.validate([self.base(track="a", motion=["progress.wobble"])])))
+        self.assertTrue(any("need a track" in e for e in manifest.validate([self.base(motion=["progress.rms"])])))
+        self.assertEqual(manifest.validate([self.base(track="a", motion=list(manifest.MOTION_MEASURES))]), [])
+
+    def test_tracked_regions_are_not_rim_elements_and_the_union_is_the_region(self):
+        scene = manifest.parse([self.base(track=["a"])])[0]
+        self.assertEqual(analyze.elements_for(scene), {"b": (1, 1, 1, 1)})
+        self.assertEqual(analyze.region_for(scene, Path("/nonexistent")), (0, 0, 1, 1))
+
+    def test_touch_scenes_are_the_ones_with_touch_steps(self):
+        self.assertTrue(manifest.parse([self.base(steps=[{"wait": 1}, {"tap": "x"}])])[0].touches)
+        self.assertFalse(manifest.parse([self.base(steps=[{"wait": 1}])])[0].touches)
+
+
 if __name__ == "__main__":
     unittest.main()
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_metrics.py b/packages/mobile/tool/glass_lab/harness/tests/test_metrics.py
index d2d6dbee4eb8e6df27a08d0b46a18f1396eb157c..7220d8322b7e2337e174a2790d25de71b190aea3 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_metrics.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_metrics.py
@@ -215,6 +215,12 @@
 
     def test_flat_series_has_no_fit(self):
         self.assertIsNone(springfit.fit([0, 1, 2], [5, 5, 5]))
+
+    def test_a_fit_on_its_grid_edge_says_so_and_the_damping_grid_reaches_2(self):
+        times = np.arange(0, 0.9, 1 / 120)
+        self.assertTrue(springfit.fit(times, springfit.step_response(times, 0.04, 1.0))["at_grid_edge"])
+        self.assertFalse(springfit.fit(times, springfit.step_response(times, 0.4, 1.6))["at_grid_edge"])
+        self.assertEqual(springfit.DAMPINGS[-1], 2.0)
 
 
 class ThresholdTests(unittest.TestCase):
PATCH
```

- [ ] **Step 2: Run them and see them fail.**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_manifest.py tool/glass_lab/harness/tests/test_metrics.py`
Expected: 6 of the 50 fail: `AttributeError: 'Scene' object has no attribute 'topology'` (and `'touches'`), `TypeError: cannot use 'list' as a dict key` (a track given as a list), `AssertionError: 'a' != ('a',)`, and `KeyError: 'at_grid_edge'`.

- [ ] **Step 3: Report spring fits on a grid edge, and widen the damping grid.** From the worktree root (`/Users/omaraly/development/AI/Operator-2b1`):

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/springfit.py b/packages/mobile/tool/glass_lab/harness/springfit.py
index ede9e4c81a1f149ed7a23021f1d2d5dc1a828f88..13257646604478f9bc3b1f683fd458eb1f9bbb04 100644
--- a/packages/mobile/tool/glass_lab/harness/springfit.py
+++ b/packages/mobile/tool/glass_lab/harness/springfit.py
@@ -1,7 +1,7 @@
 import numpy as np
 
 RESPONSES = np.linspace(0.05, 1.5, 146)
-DAMPINGS = np.linspace(0.1, 1.2, 111)
+DAMPINGS = np.linspace(0.1, 2.0, 191)
 
 
 def step_response(t, response, damping):
@@ -38,7 +38,8 @@
     curves = step_response(t, RESPONSES[:, None, None], DAMPINGS[None, :, None])
     errors = np.sqrt(np.mean((curves - normalized[None, None, :]) ** 2, axis=2))
     i, j = np.unravel_index(np.argmin(errors), errors.shape)
-    return {"response": float(RESPONSES[i]), "damping": float(DAMPINGS[j]), "rms": float(errors[i, j])}
+    edge = i in (0, len(RESPONSES) - 1) or j in (0, len(DAMPINGS) - 1)
+    return {"response": float(RESPONSES[i]), "damping": float(DAMPINGS[j]), "rms": float(errors[i, j]), "at_grid_edge": bool(edge)}
 
 
 def features(times, values):
PATCH
```

- [ ] **Step 4: Tracks as tuples in the manifest, the thresholds, the region, the tuner and the tone fit.**

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/manifest.py b/packages/mobile/tool/glass_lab/harness/manifest.py
index 303380d328aebeaa0546676254073a41045596b7..62ec2dda07689780869b28302e8b499e9d38fe05 100644
--- a/packages/mobile/tool/glass_lab/harness/manifest.py
+++ b/packages/mobile/tool/glass_lab/harness/manifest.py
@@ -8,8 +8,24 @@
 BACKDROPS = ("stripes", "photo", "white", "black", "text", "scroll", "none")
 APPEARANCES = ("light", "dark")
 STEP_KINDS = ("wait", "tap", "doubleTap", "press", "pressDrag")
+TOUCH_STEPS = ("tap", "doubleTap", "press", "pressDrag")
 FIELDS = ("id", "group", "title", "inventory", "app", "backdrops", "appearances", "steps")
 STATIC_MEASURES = ("mad", "luminance", "rim_rms", "bbox_pt", "centre_pt")
+MOTION_MEASURES = (
+    "delay_ms",
+    "topology.count",
+    "topology.join_ms",
+    "topology.split_ms",
+    "topology.neck_rms",
+    *(f"{key}.{measure}" for key in ("width", "height", "cx", "cy", "luma") for measure in ("peak_ms", "settle_ms", "overshoot_pct", "response_pct", "damping")),
+    "progress.t10_90_ms",
+    "progress.settle_ms",
+    "progress.overshoot_pct",
+    "progress.response_pct",
+    "progress.damping",
+    "progress.rms",
+    "progress.sharpness",
+)
 
 
 @dataclass(frozen=True)
@@ -23,9 +39,11 @@
     appearances: tuple
     steps: tuple
     regions: dict = field(default_factory=dict)
-    track: str | None = None
+    track: tuple = ()
     prepare: tuple = ()
     measures: tuple = STATIC_MEASURES
+    motion: tuple = ()
+    topology: tuple = ()
 
     @property
     def native_only(self):
@@ -34,6 +52,10 @@
     @property
     def rest(self):
         return all("wait" in step for step in self.steps)
+
+    @property
+    def touches(self):
+        return any(next(iter(step)) in TOUCH_STEPS for step in self.steps)
 
 
 def _target_errors(where, value):
@@ -97,8 +119,25 @@
         for name, rect in regions.items():
             if not (isinstance(rect, list) and len(rect) == 4 and all(isinstance(v, (int, float)) for v in rect)):
                 errors.append(f"{where}: region {name} must be [x, y, w, h]")
-        if entry.get("track") is not None and entry["track"] not in regions:
+        track = entry.get("track")
+        names = [track] if isinstance(track, str) else track
+        if track is not None and not (isinstance(names, list) and names and all(isinstance(n, str) for n in names)):
+            errors.append(f"{where}: track must be a region name or a non-empty list of them")
+        elif track is not None and any(name not in regions for name in names):
             errors.append(f"{where}: track names an unknown region")
+        topology = entry.get("topology")
+        names = [topology] if isinstance(topology, str) else topology
+        if topology is not None and not (isinstance(names, list) and names and all(isinstance(n, str) for n in names)):
+            errors.append(f"{where}: topology must be a region name or a non-empty list of them")
+        elif topology is not None and any(name not in regions for name in names):
+            errors.append(f"{where}: topology names an unknown region")
+        motion = entry.get("motion", [])
+        if not isinstance(motion, list):
+            errors.append(f"{where}: motion must be a list")
+        else:
+            errors += [f"{where}: unknown motion measure {m}" for m in motion if m not in MOTION_MEASURES]
+            if motion and track is None:
+                errors.append(f"{where}: motion measures need a track")
         measures = entry.get("measures", list(STATIC_MEASURES))
         if not isinstance(measures, list) or not measures:
             errors.append(f"{where}: measures must be a non-empty list")
@@ -107,6 +146,12 @@
         if entry.get("app") != "lab" and entry.get("group") != "apple":
             errors.append(f"{where}: only apple scenes may target another app")
     return errors
+
+
+def tracks(value):
+    if value is None:
+        return ()
+    return (value,) if isinstance(value, str) else tuple(value)
 
 
 def parse(raw):
@@ -124,9 +169,11 @@
             appearances=tuple(entry["appearances"]),
             steps=tuple(entry["steps"]),
             regions=dict(entry.get("regions", {})),
-            track=entry.get("track"),
+            track=tracks(entry.get("track")),
             prepare=tuple(entry.get("prepare", [])),
             measures=tuple(entry.get("measures", STATIC_MEASURES)),
+            motion=tuple(entry.get("motion", [])),
+            topology=tracks(entry.get("topology")),
         )
         for entry in raw
     ]
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/metrics.py b/packages/mobile/tool/glass_lab/harness/metrics.py
index d35ed8d66ff1e0e744c3f40048e41d0e81f859cc..dd03d25bca4cdccc67305aaf95ca0bb714e831c0 100644
--- a/packages/mobile/tool/glass_lab/harness/metrics.py
+++ b/packages/mobile/tool/glass_lab/harness/metrics.py
@@ -16,6 +16,10 @@
     "overshoot_pct": 2.0,
     "response_pct": 5.0,
     "damping": 0.05,
+    "progress_rms": 0.05,
+    "sharpness": 1.0,
+    "neck_pt": 1.0,
+    "count": 0.0,
 }
 
 
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/analyze.py b/packages/mobile/tool/glass_lab/harness/analyze.py
index 8b81ac765d5aca62eb2a944a56371398725e84dd..5476a4286e60f497a9648733687787cdfb8639bf 100644
--- a/packages/mobile/tool/glass_lab/harness/analyze.py
+++ b/packages/mobile/tool/glass_lab/harness/analyze.py
@@ -8,6 +8,7 @@
 import align
 import metrics
 import springfit
+import touch
 
 OVERVIEW_FPS = 20
 MATCH_MARGIN = 6.0
@@ -98,20 +99,20 @@
 
 def region_for(scene, case_dir):
     if scene.track:
-        return tuple(scene.regions[scene.track])
+        return metrics.union([tuple(scene.regions[name]) for name in scene.track])
     bare = metrics.load(case_dir / "bare" / "ready.png")
     boxes = metrics.glass_boxes(metrics.load(case_dir / "ready.png"), bare)
     boxes += metrics.glass_boxes(metrics.load(case_dir / "settled.png"), bare)
     if not scene.rest and (case_dir / "video.mp4").exists():
         found = window(case_dir)
         if found:
-            boxes += align.extent(found[2])
-    boxes = [box for box in boxes if box[1] + box[3] > align.SKIP_TOP_POINTS]
+            boxes += align.extent(found[2], ignore=(touch.MARKER,))
+    boxes = [box for box in touch.without_marker(boxes) if box[1] + box[3] > align.SKIP_TOP_POINTS]
     return metrics.union(boxes, pad=12) or (0, 0, *metrics.SCREEN)
 
 
 def elements_for(scene):
-    return {name: tuple(rect) for name, rect in scene.regions.items() if name != scene.track}
+    return {name: tuple(rect) for name, rect in scene.regions.items() if name not in scene.track}
 
 
 def motion(case_dir, region):
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/tune.py b/packages/mobile/tool/glass_lab/harness/tune.py
index 7c7a497219770dfb6b5e7f181118b53bf74ee3d5..1fa765de86012e02ba418eacbceb6b7d95249a18 100644
--- a/packages/mobile/tool/glass_lab/harness/tune.py
+++ b/packages/mobile/tool/glass_lab/harness/tune.py
@@ -162,7 +162,7 @@
 
     def region(self, native, native_bare):
         if self.scene.track:
-            return tuple(self.scene.regions[self.scene.track])
+            return metrics.union([tuple(self.scene.regions[name]) for name in self.scene.track])
         if self.regions:
             return named_region(self.scene, self.regions, self.pad)
         box = element_box(metrics.glass_boxes(native, native_bare), self.size)
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/tonefit.py b/packages/mobile/tool/glass_lab/harness/tonefit.py
index be9b22734100d6687956c2415338b96241f00706..c4fc32718ba2290054a838b9a6aac9cd2bad0678 100644
--- a/packages/mobile/tool/glass_lab/harness/tonefit.py
+++ b/packages/mobile/tool/glass_lab/harness/tonefit.py
@@ -35,7 +35,7 @@
     fits = {}
     for appearance in scene.appearances:
         for name, box in scene.regions.items():
-            if name == scene.track:
+            if name in scene.track:
                 continue
             points = []
             for backdrop in BACKDROPS:
PATCH
```

- [ ] **Step 5: Run the new tests, then every harness test.**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_manifest.py tool/glass_lab/harness/tests/test_metrics.py`
Expected: `Ran 50 tests` … `OK`.
Run: `python3 -m unittest discover tool/glass_lab/harness/tests`
Expected: `Ran 131 tests` … `OK`.

- [ ] **Step 6: Commit.**

```bash
git add packages/mobile/tool/glass_lab/harness
git commit -m "feat(glass-lab): tracks, motion and topology lists in the manifest; spring fits report their grid edge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
### Task 4: Per-scene motion measures per shape, judged so that nothing passes by being absent (L1–L3, L6, L7)

**Files:**
- Create: `tool/glass_lab/harness/shapes.py`
- Modify: `tool/glass_lab/harness/analyze.py`, `report.py`
- Test: `tool/glass_lab/harness/tests/test_shapes.py`

**Interfaces:**
- Consumes: `track` (Task 1), `touch` (Task 2), the manifest's tracks, motion and topology, `springfit.fit`'s `at_grid_edge` and the thresholds (Task 3).
- Produces:
  - `shapes.capture(scene, case_dir, (start, end)) -> {"events", "touches", "stalls", "frames", "rest", "rows"}`: every event carries its `onset`, its owning `step`, its per-shape 120 Hz series and `first_frame` (per shape: the gap from the rest frame to the first changed frame, in ms, and that frame's progress as a fraction of the event's travel); `stalls` are the frame gaps over 25 ms inside events (`align.stalls`, spec §10);
  - `shapes.compare(scene, native, flutter)` → `event_count`, `unpaired` (`{"native": n, "flutter": n}`, the events of either app in no pair), `touches`, `expected_touches`, `stalls` (`{"native": [...], "flutter": [...]}`), `steps`, and `pairs` (per pair: `delay` in ms for both apps, per shape the key, progress and topology comparisons and `first_frame` for both apps);
  - `shapes.measures(result) -> {name: value}` (present values only) and `shapes.expected(result, scene) -> [name]` (every measure the scene lists, for every pair and every shape that owns it: `topology.*` for the scene's topology regions, the rest for its tracks);
  - `shapes.limits(result, scene, noise) -> {name: (value, limit, "max"|"min")}`: `events.native_motion` (at least 1), `events.steps` when both apps have stepped events, `events.unpaired` (limit 0), `touches.native` and `touches.flutter` for scenes with touch steps (touches read against `touch.expected_touches`, limit 0), and every expected measure with its value, or `inf` when it is absent (finding 1); each limit is max(fixed threshold, 1.5 × noise);
  - a spring fit that sits on its grid edge or fits worse than RMS 0.15 is reported under `fit_invalid` and its `response_pct` and `damping` are `inf` (finding 5);
  - `shapes.compare_topology(native_series, flutter_series)` gives `join_ms`, `split_ms`, `count` (samples where the counts differ, outside ±2 samples of any transition) and `neck_rms`; `shapes.static_topology(scene, native_dir, flutter_dir)` and the still measures `ready.topology.<region>.count` (limit 0) and `.neck_pt` (limit 1 pt);
  - `shapes.summary(capture)`: per shape the rest box, the largest and smallest visible box and whether the rest and the widest box had an edge inside L1's blind band (`edge_in_band`);
  - motion measure names: `<shape>.<pair>.<key>.<measure>` and `<pair>.delay_ms`, where `<pair>` is `step<k>e<i>` (the i-th event caused by step k) or `event<i>` when either video has no marker;
  - `analyze.analyze(scene, case_dir, noise=None, cache=None)`: static and still-topology measures now also take max(fixed, 1.5 × noise) when `noise` names them (finding 10; 2A's scene-wide noise names none, so 2A's judgements do not move); per-shape scenes store `native_stalls` and `flutter_stalls` again for the report (finding 6); `cache` (a dict) lets one capture per recording serve every pair (Task 6's `repeat`). `analyze.within` counts a value equal to its limit up to float rounding (1e-9) as within it (R3: `abs(1.06 − 1.01)` is 0.050000000000000044);
  - the report shows each pair's progress curves and features.
- Why a separate path: scenes that declare `motion` measures are analysed per shape; every other scene keeps the whole-region series it has today (ruling 3), now with the teardown cut.

- [ ] **Step 1: Write the failing tests.** Create `tool/glass_lab/harness/tests/test_shapes.py`:

```python
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import analyze
import manifest
import shapes
import springfit
from synthetic import capture_of, spring_series


class ShapeTopologyTests(unittest.TestCase):
    def test_join_and_split_times_count_mismatches_and_neck_are_compared(self):
        def series(join, split):
            count = [2.0] * join + [1.0] * (split - join) + [2.0] * (80 - split)
            neck = [0.0] * join + [10.0] * (split - join) + [0.0] * (80 - split)
            return {"count": count, "neck": neck}
        late = shapes.compare_topology(series(20, 60), series(23, 60))
        self.assertAlmostEqual(late["join_ms"], 25, places=6)
        self.assertEqual(late["split_ms"], 0)
        self.assertEqual(late["count"], 0.0)
        self.assertAlmostEqual(late["neck_rms"], (3 * 100 / 80) ** 0.5, places=6)
        stuck = shapes.compare_topology(series(20, 60), series(23, 80))
        self.assertNotIn("split_ms", stuck)
        self.assertEqual(stuck["count"], 17.0)
        self.assertIsNone(shapes.compare_topology({"count": [1.0] * 5, "neck": [5.0] * 5}, {"count": [1.0] * 5, "neck": [5.0] * 5}))


class ProgressMeasureTests(unittest.TestCase):
    def test_ten_to_ninety_matches_the_spring(self):
        features = shapes.progress_features(spring_series(0.55, 1.0))
        self.assertAlmostEqual(features["t10_90_ms"], 294, delta=9)
        leaving = shapes.progress_features(spring_series(0.55, 1.0, appearing=False, exponent=3.2))
        self.assertLess(leaving["t10_90_ms"], 170)

    def test_a_variable_rate_capture_reads_the_same_ten_to_ninety_time_within_a_frame(self):
        rng = np.random.default_rng(7)
        times = np.cumsum(np.concatenate([[0.0], rng.choice([1 / 120, 1 / 60, 0.033, 0.053], 40)]))
        rows = [{"width": 250.0, "height": 88.0, "cx": 201.0, "cy": 451.0, "luma": 100.0, "progress": float(p), "sharpness": 0.0, "residual": 0.0}
                for p in springfit.step_response(times, 0.55, 1.0)]
        series = shapes.event_series(list(times), rows, 0, len(times) - 1)
        exact = shapes.progress_features(spring_series(0.55, 1.0))["t10_90_ms"]
        self.assertAlmostEqual(shapes.progress_features(series)["t10_90_ms"], exact, delta=1000 / 120)

    def test_overshoot_is_read_in_points_of_percent(self):
        self.assertGreater(shapes.progress_features(spring_series(0.5, 0.7))["overshoot_pct"], 3)
        self.assertEqual(shapes.progress_features(spring_series(0.55, 1.0))["overshoot_pct"], 0.0)

    def test_identical_captures_measure_zero(self):
        scene = manifest.parse([{
            "id": "material.materialize", "group": "material", "title": "t", "inventory": "2.13", "app": "lab",
            "backdrops": ["stripes"], "appearances": ["dark"], "steps": [{"wait": 0.5}, {"tap": "toggle"}],
            "regions": {"block": [70, 400, 262, 104]}, "track": ["block"], "motion": ["progress.t10_90_ms", "progress.rms"],
        }])[0]
        a = capture_of(spring_series(0.55, 1.0, False, 3.2), spring_series(0.55, 1.0))
        result = shapes.compare(scene, a, a)
        found = shapes.measures(result)
        self.assertEqual(found["block.event0.progress.t10_90_ms"], 0.0)
        self.assertEqual(found["block.event1.progress.rms"], 0.0)
        limits = shapes.limits(result, scene)
        self.assertEqual(set(limits), {"events.native_motion", "events.unpaired", "touches.native", "touches.flutter", "block.event0.progress.t10_90_ms", "block.event0.progress.rms", "block.event1.progress.t10_90_ms", "block.event1.progress.rms"})
        self.assertEqual(limits["block.event0.progress.rms"], (0.0, 0.05, "max"))

    def test_a_slower_flutter_appear_fails_and_noise_raises_the_limit(self):
        scene = manifest.parse([{
            "id": "x", "group": "material", "title": "t", "inventory": "2.13", "app": "lab",
            "backdrops": ["stripes"], "appearances": ["dark"], "steps": [{"tap": "toggle"}],
            "regions": {"block": [0, 0, 10, 10]}, "track": "block", "motion": ["progress.t10_90_ms"],
        }])[0]
        result = shapes.compare(scene, capture_of(spring_series(0.55, 1.0)), capture_of(spring_series(0.7, 1.0)))
        value, limit, _ = shapes.limits(result, scene)["block.event0.progress.t10_90_ms"]
        self.assertGreater(value, 17)
        self.assertEqual(limit, 17)
        _, raised, _ = shapes.limits(result, scene, {"block.event0.progress.t10_90_ms": 100})["block.event0.progress.t10_90_ms"]
        self.assertEqual(raised, 150)

    def test_events_pair_by_the_step_that_caused_them(self):
        scene = manifest.parse([{
            "id": "x", "group": "material", "title": "t", "inventory": "2.13", "app": "lab",
            "backdrops": ["stripes"], "appearances": ["dark"], "steps": [{"tap": "a"}, {"tap": "b"}],
            "regions": {"block": [0, 0, 10, 10]}, "track": ["block"], "motion": ["progress.rms"],
        }])[0]
        native = capture_of(spring_series(0.55, 1.0, False, 3.2), spring_series(0.55, 1.0), steps=[0, 1])
        flutter = capture_of(spring_series(0.55, 1.0), steps=[1])
        result = shapes.compare(scene, native, flutter)
        self.assertEqual(list(result["pairs"]), ["step1e0"])
        self.assertEqual(shapes.measures(result)["block.step1e0.progress.rms"], 0.0)
        self.assertEqual(shapes.limits(result, scene)["events.steps"], (1, 0, "max"))


class NothingPassesByBeingAbsentTests(unittest.TestCase):
    def scene(self, motion=("progress.t10_90_ms", "progress.rms", "progress.response_pct", "progress.damping"), steps=None):
        return manifest.parse([{
            "id": "x", "group": "material", "title": "t", "inventory": "2.13", "app": "lab",
            "backdrops": ["stripes"], "appearances": ["dark"], "steps": steps or [{"tap": "a"}, {"tap": "b"}],
            "regions": {"block": [0, 0, 10, 10]}, "track": ["block"], "motion": list(motion),
        }])[0]

    def test_an_extra_flutter_event_is_unpaired_and_fails(self):
        scene = self.scene()
        native = capture_of(spring_series(0.55, 1.0, False, 3.2), spring_series(0.55, 1.0), steps=[0, 1])
        flutter = capture_of(spring_series(0.55, 1.0, False, 3.2), spring_series(0.55, 1.0), spring_series(0.5, 0.5), steps=[0, 1, 1])
        result = shapes.compare(scene, native, flutter)
        self.assertEqual(result["unpaired"], {"native": 0, "flutter": 1})
        self.assertEqual(shapes.limits(result, scene)["events.unpaired"], (1, 0, "max"))
        self.assertFalse(analyze.within(*shapes.limits(result, scene)["events.unpaired"]))

    def test_a_missing_progress_entry_fails_as_infinite(self):
        scene = self.scene()
        flat = spring_series(0.55, 1.0)
        flat["progress"] = np.full_like(flat["progress"], 0.5)
        native = capture_of(spring_series(0.55, 1.0), steps=[0])
        flutter = capture_of(flat, steps=[0])
        result = shapes.compare(scene, native, flutter)
        self.assertNotIn("progress", result["pairs"]["step0e0"]["shapes"]["block"])
        limits = shapes.limits(result, scene)
        for measure in ("t10_90_ms", "rms", "response_pct", "damping"):
            value, _, _ = limits[f"block.step0e0.progress.{measure}"]
            self.assertEqual(value, float("inf"))
            self.assertFalse(analyze.within(*limits[f"block.step0e0.progress.{measure}"]))

    def test_a_spring_fit_on_its_grid_edge_is_reported_and_fails(self):
        entry = {}
        shapes.apply_spring_fits(entry, {"response": 0.38, "damping": 2.0, "rms": 0.01, "at_grid_edge": True}, {"response": 0.4, "damping": 1.0, "rms": 0.01, "at_grid_edge": False})
        self.assertEqual(entry["fit_invalid"], {"native": "at the grid edge"})
        self.assertEqual((entry["response_pct"], entry["damping"]), (float("inf"), float("inf")))

    def test_a_value_on_its_limit_passes_whatever_the_float_rounding(self):
        self.assertTrue(analyze.within(abs(1.06 - 1.01), 0.05, "max"))
        self.assertTrue(analyze.within(0.7 - 0.6, 0.1, "min"))
        self.assertFalse(analyze.within(0.0501, 0.05, "max"))
        self.assertFalse(analyze.within(float("inf"), 0.05, "max"))

    def test_touches_are_counted_against_the_touch_steps(self):
        scene = self.scene(steps=[{"wait": 0.5}, {"tap": "a"}, {"doubleTap": "b"}])
        native, flutter = capture_of(spring_series(0.55, 1.0), steps=[1]), capture_of(spring_series(0.55, 1.0), steps=[1])
        native["touches"] = [(1.0, 1.1), (2.0, 2.05), (2.1, 2.15)]
        flutter["touches"] = [(1.0, 1.1)]
        limits = shapes.limits(shapes.compare(scene, native, flutter), scene)
        self.assertEqual(limits["touches.native"], (0, 0, "max"))
        self.assertEqual(limits["touches.flutter"], (2, 0, "max"))

    def test_stalls_and_the_first_changed_frame_are_kept_for_the_report(self):
        rows = [{"progress": p} for p in (0.0, 0.0, 0.7, 0.9, 1.0)]
        series = {"progress": [0.0, 0.5, 1.0]}
        step = shapes.first_step([0.0, 0.1, 0.15, 0.2, 0.3], rows, series, 1, 4)
        self.assertAlmostEqual(step["gap_ms"], 50, places=6)
        self.assertAlmostEqual(step["progress"], 0.7, places=6)
        scene = self.scene()
        native, flutter = capture_of(spring_series(0.55, 1.0), steps=[0]), capture_of(spring_series(0.55, 1.0), steps=[0])
        native["stalls"], flutter["stalls"] = [], [41.0]
        flutter["events"][0]["first_frame"] = {"block": {"gap_ms": 33.0, "progress": 0.73}}
        result = shapes.compare(scene, native, flutter)
        self.assertEqual(result["stalls"], {"native": [], "flutter": [41.0]})
        self.assertEqual(result["pairs"]["step0e0"]["shapes"]["block"]["first_frame"]["flutter"], {"gap_ms": 33.0, "progress": 0.73})


class MotionMeasureNameTests(unittest.TestCase):
    def test_the_harness_and_the_manifest_agree_on_motion_measures(self):
        self.assertEqual(manifest.MOTION_MEASURES, shapes.MOTION_MEASURES)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and see them fail.**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py`
Expected: `ModuleNotFoundError: No module named 'shapes'`.

- [ ] **Step 3: Write the per-shape analysis.** Create `tool/glass_lab/harness/shapes.py`:

```python
import numpy as np

import align
import metrics
import springfit
import touch
import track

LEAD_SECONDS = 0.2
HOLD_SECONDS = 0.3
MAX_LAG_MS = 150
INNER_INSET = (16, 8)
MIN_TRAVEL = {"width": 4.0, "height": 4.0, "cx": 4.0, "cy": 4.0, "luma": 3.0, "progress": 0.2}
MIN_EVENT_CHANGE = {"width": 4.0, "height": 4.0, "cx": 4.0, "cy": 4.0, "luma": 1.5, "progress": 0.1}
KEYS = (*align.KEYS, "progress")
MOTION_MEASURES = (
    "delay_ms",
    "topology.count",
    "topology.join_ms",
    "topology.split_ms",
    "topology.neck_rms",
    *(f"{key}.{measure}" for key in align.KEYS for measure in ("peak_ms", "settle_ms", "overshoot_pct", "response_pct", "damping")),
    "progress.t10_90_ms",
    "progress.settle_ms",
    "progress.overshoot_pct",
    "progress.response_pct",
    "progress.damping",
    "progress.rms",
    "progress.sharpness",
)
LIMITS = {
    "delay_ms": "time_ms",
    "peak_ms": "time_ms",
    "settle_ms": "time_ms",
    "t10_90_ms": "time_ms",
    "overshoot_pct": "overshoot_pct",
    "response_pct": "response_pct",
    "damping": "damping",
    "rms": "progress_rms",
    "sharpness": "sharpness",
    "join_ms": "time_ms",
    "split_ms": "time_ms",
    "neck_rms": "neck_pt",
    "count": "count",
}
TRANSITION_SAMPLES = 2


def regions(scene):
    names = list(scene.track) + [name for name in scene.topology if name not in scene.track]
    return {name: tuple(scene.regions[name]) for name in names}


def inner_slices(rest_box, shape):
    height, width = shape[:2]
    if rest_box is None:
        return slice(0, height), slice(0, width)
    x, y, w, h = rest_box
    dx, dy = INNER_INSET
    top, bottom = int(round(y + dy)), int(round(y + h - dy))
    left, right = int(round(x + dx)), int(round(x + w - dx))
    if bottom - top < 3 or right - left < 3:
        return slice(0, height), slice(0, width)
    return slice(max(0, top), min(height, bottom)), slice(max(0, left), min(width, right))


def capture(scene, case_dir, found):
    if found is None:
        return {"events": [], "touches": [], "frames": 0}
    start, end = found
    shape_regions = regions(scene)
    union = metrics.union(list(shape_regions.values()))
    rect = track.pixel_rect(union)
    frames = track.extract(case_dir / "video.mp4", rect, case_dir / "shapes")
    frames = track.clip(frames, max(0.0, start - LEAD_SECONDS), end)
    frames = track.teardown_cut(frames, track.crop_px(metrics.load(case_dir / "settled.png"), rect))
    bare_full, ready_full = metrics.load(case_dir / "bare" / "ready.png"), metrics.load(case_dir / "ready.png")
    parts = {}
    for name, region in shape_regions.items():
        px = track.pixel_rect(region)
        local = (px[0] - rect[0], px[1] - rect[1], px[2], px[3])
        bare, full = track.crop_px(bare_full, px), track.crop_px(ready_full, px)
        edge_map = track.edges(bare)
        rest = track.box(full, bare, edge_map)
        bare_pt, full_pt = shrink(bare), shrink(full)
        parts[name] = {
            "local": local,
            "origin": (px[0] / metrics.SCALE, px[1] / metrics.SCALE),
            "bare": bare,
            "edges": edge_map,
            "bare_pt": bare_pt,
            "full_pt": full_pt,
            "inner": inner_slices(rest, bare_pt.shape),
            "rest": rest,
        }
    rows = {name: [] for name in parts}
    previous, diffs = None, []
    for frame in frames:
        point = shrink(frame)
        diffs.append(0.0 if previous is None else metrics.mad(point, previous))
        previous = point
        for name, part in parts.items():
            crop = track.crop_px(frame, part["local"])
            row = track.shape_row(crop, part["bare"], part["edges"], part["origin"])
            row.update(track.progress_row(shrink(crop), part["bare_pt"], part["full_pt"], part["inner"]))
            if name in scene.topology:
                row.update(track.topology_row(crop, part["bare"], part["edges"]))
            rows[name].append(row)
    windows = [w for w in touch.read(case_dir / "video.mp4", case_dir / "marker") if w[1] >= start - LEAD_SECONDS and w[0] <= end]
    events = []
    for first, last in align.events(diffs, frames.times):
        onset = frames.times[min(first + 1, last)]
        series = {name: event_series(frames.times, rows[name], first, last) for name in parts}
        if not any(significant(s) for s in series.values()):
            continue
        first_frame = {name: first_step(frames.times, rows[name], series[name], first, last) for name in parts}
        events.append({"onset": onset, "series": series, "step": touch.owner(onset, scene.steps, windows), "first_frame": first_frame})
    return {
        "events": events,
        "touches": windows,
        "stalls": align.stalls(diffs, frames.times),
        "frames": len(frames),
        "rest": {name: part["rest"] for name, part in parts.items()},
        "rows": {name: {"times": list(frames.times), "rows": rows[name]} for name in parts},
    }


def first_step(times, rows, series, first, last):
    after = min(first + 1, last)
    start, end = series["progress"][0], series["progress"][-1]
    travel = end - start
    value = rows[after]["progress"]
    return {
        "gap_ms": (times[after] - times[first]) * 1000,
        "progress": float((value - start) / travel) if np.isfinite(value) and abs(travel) >= MIN_TRAVEL["progress"] else None,
    }


def shrink(image):
    height, width = image.shape[0] // metrics.SCALE, image.shape[1] // metrics.SCALE
    trimmed = image[: height * metrics.SCALE, : width * metrics.SCALE]
    return trimmed.reshape(height, metrics.SCALE, width, metrics.SCALE, 3).mean(axis=(1, 3))


def event_series(times, rows, first, last):
    stop = times[last] + HOLD_SECONDS
    indices = [i for i in range(first, len(times)) if i <= last or times[i] <= stop]
    origin = max(times[first], times[first + 1] - 1.0 / align.GRID_HZ) if first + 1 < len(times) else times[first]
    stamps = [max(0.0, times[i] - origin) for i in indices] + [stop - origin]
    picked = [rows[i] for i in indices] + [rows[indices[-1]]]
    grid = np.arange(0.0, stamps[-1] + 1e-9, 1.0 / align.GRID_HZ)
    series = {}
    if "count" in picked[0]:
        counts = np.array([row["count"] for row in picked])
        series["count"] = counts[np.clip(np.searchsorted(stamps, grid, side="right") - 1, 0, len(counts) - 1)].tolist()
        series["neck"] = np.interp(grid, stamps, [row["neck"] for row in picked]).tolist()
    for key in (*KEYS, "sharpness", "residual"):
        values = np.array([row[key] for row in picked], dtype=np.float64)
        valid = np.isfinite(values)
        if valid.sum() < 2:
            series[key] = [float("nan")] * len(grid)
            continue
        series[key] = np.interp(grid, np.array(stamps)[valid], values[valid]).tolist()
    return series


def significant(series):
    return any(np.isfinite(series[key]).all() and np.ptp(series[key]) >= MIN_EVENT_CHANGE[key] for key in KEYS)


def crossing(times, values, level):
    hits = np.nonzero(values >= level)[0]
    return float(times[hits[0]]) if len(hits) else None


def progress_features(series):
    values = np.array(series["progress"], dtype=np.float64)
    normalized = springfit.normalize(values)
    if normalized is None or abs(values[-1] - values[0]) < MIN_TRAVEL["progress"]:
        return None
    times = np.arange(len(values)) / align.GRID_HZ
    low, high = crossing(times, normalized, 0.1), crossing(times, normalized, 0.9)
    features = springfit.features(times, values)
    mid = int(np.argmin(np.abs(normalized - 0.5)))
    return {
        "t10_90_ms": (high - low) * 1000 if low is not None and high is not None else None,
        "settle_ms": features["settle_ms"],
        "overshoot_pct": features["overshoot_pct"],
        "sharpness_mid": float(series["sharpness"][mid]),
        "residual_peak": float(np.nanmax(series["residual"])),
        "normalized": normalized,
        "times": times,
        "spring": springfit.fit(times, values),
    }


def best_lag(a, b):
    limit = int(MAX_LAG_MS / 1000 * align.GRID_HZ)
    best, chosen = float("inf"), 0
    for lag in range(-limit, limit + 1):
        x, y = (a[lag:], b) if lag >= 0 else (a, b[-lag:])
        count = min(len(x), len(y))
        if count < 3:
            continue
        error = float(np.mean((x[:count] - y[:count]) ** 2))
        if error < best:
            best, chosen = error, lag
    return chosen


def compare_progress(a_series, b_series):
    a, b = progress_features(a_series), progress_features(b_series)
    if a is None or b is None:
        return None
    entry = {
        "native": {k: v for k, v in a.items() if k not in ("normalized", "times")},
        "flutter": {k: v for k, v in b.items() if k not in ("normalized", "times")},
        "curves": {"native": a["normalized"].tolist(), "flutter": b["normalized"].tolist()},
    }
    if a["t10_90_ms"] is not None and b["t10_90_ms"] is not None:
        entry["t10_90_ms"] = abs(a["t10_90_ms"] - b["t10_90_ms"])
    entry["settle_ms"] = abs(a["settle_ms"] - b["settle_ms"])
    entry["overshoot_pct"] = abs(a["overshoot_pct"] - b["overshoot_pct"])
    entry["sharpness"] = abs(a["sharpness_mid"] - b["sharpness_mid"])
    lag = best_lag(a["normalized"], b["normalized"])
    x, y = (a["normalized"][lag:], b["normalized"]) if lag >= 0 else (a["normalized"], b["normalized"][-lag:])
    count = min(len(x), len(y))
    entry["lag_ms"] = lag * 1000 / align.GRID_HZ
    entry["rms"] = float(np.sqrt(np.mean((x[:count] - y[:count]) ** 2)))
    apply_spring_fits(entry, a["spring"], b["spring"])
    return entry


def fit_problem(spring):
    if not spring:
        return "no travel"
    if spring["at_grid_edge"]:
        return "at the grid edge"
    if spring["rms"] >= 0.15:
        return f"rms {spring['rms']:.3f}"
    return None


def apply_spring_fits(entry, sa, sb):
    problems = {side: fit_problem(spring) for side, spring in (("native", sa), ("flutter", sb))}
    if any(problems.values()):
        entry["fit_invalid"] = {side: problem for side, problem in problems.items() if problem}
        entry["response_pct"] = float("inf")
        entry["damping"] = float("inf")
        return
    entry["response_pct"] = abs(sa["response"] - sb["response"]) / sa["response"] * 100
    entry["damping"] = abs(sa["damping"] - sb["damping"])


def compare_key(key, a_values, b_values):
    a, b = np.array(a_values, dtype=np.float64), np.array(b_values, dtype=np.float64)
    if not (np.isfinite(a).all() and np.isfinite(b).all()):
        return None
    if abs(a[-1] - a[0]) < MIN_TRAVEL[key] or abs(b[-1] - b[0]) < MIN_TRAVEL[key]:
        return None
    entry = {}
    ta, tb = np.arange(len(a)) / align.GRID_HZ, np.arange(len(b)) / align.GRID_HZ
    fa, fb = springfit.features(ta, a), springfit.features(tb, b)
    entry["peak_ms"] = abs(fa["peak_ms"] - fb["peak_ms"])
    entry["settle_ms"] = abs(fa["settle_ms"] - fb["settle_ms"])
    entry["overshoot_pct"] = abs(fa["overshoot_pct"] - fb["overshoot_pct"])
    sa, sb = springfit.fit(ta, a), springfit.fit(tb, b)
    entry["native_spring"], entry["flutter_spring"] = sa, sb
    apply_spring_fits(entry, sa, sb)
    return entry


def pairs(native, flutter):
    stepped = all(any(e["step"] is not None for e in side["events"]) for side in (native, flutter))
    if not stepped:
        return [(f"event{i}", a, b) for i, (a, b) in enumerate(zip(native["events"], flutter["events"]))]
    by_step = {}
    for side, found in (("native", native), ("flutter", flutter)):
        for event in found["events"]:
            if event["step"] is not None:
                by_step.setdefault(event["step"], {"native": [], "flutter": []})[side].append(event)
    return [
        (f"step{step}e{index}", a, b)
        for step, sides in sorted(by_step.items())
        for index, (a, b) in enumerate(zip(sides["native"], sides["flutter"]))
    ]


def unpaired(native, flutter):
    stepped = all(any(e["step"] is not None for e in side["events"]) for side in (native, flutter))
    if not stepped:
        count = min(len(native["events"]), len(flutter["events"]))
        return {"native": len(native["events"]) - count, "flutter": len(flutter["events"]) - count}
    found = {"native": 0, "flutter": 0}
    by_step = {}
    for side, capture in (("native", native), ("flutter", flutter)):
        for event in capture["events"]:
            if event["step"] is None:
                found[side] += 1
            else:
                by_step.setdefault(event["step"], {"native": 0, "flutter": 0})[side] += 1
    for sides in by_step.values():
        paired = min(sides.values())
        for side in found:
            found[side] += sides[side] - paired
    return found


def delay(event, steps, windows):
    times = touch.step_times(steps, windows)
    return None if event["step"] not in times else (event["onset"] - times[event["step"]]) * 1000


def transitions(counts):
    joins, splits = [], []
    for i in range(1, len(counts)):
        if counts[i - 1] >= 2 and counts[i] == 1:
            joins.append(i)
        if counts[i - 1] == 1 and counts[i] >= 2:
            splits.append(i)
    return joins, splits


def compare_topology(a_series, b_series):
    a_count, b_count = np.array(a_series["count"]), np.array(b_series["count"])
    if a_count.max() < 2 and b_count.max() < 2:
        return None
    entry = {}
    a_joins, a_splits = transitions(a_count)
    b_joins, b_splits = transitions(b_count)
    for key, a, b in (("join_ms", a_joins, b_joins), ("split_ms", a_splits, b_splits)):
        if a and b:
            entry[key] = abs(a[0] - b[0]) * 1000 / align.GRID_HZ
    count = min(len(a_count), len(b_count))
    excluded = np.zeros(count, dtype=bool)
    for index in a_joins + a_splits + b_joins + b_splits:
        excluded[max(0, index - TRANSITION_SAMPLES) : index + TRANSITION_SAMPLES + 1] = True
    entry["count"] = float(((a_count[:count] != b_count[:count]) & ~excluded).sum())
    a_neck, b_neck = np.array(a_series["neck"][:count]), np.array(b_series["neck"][:count])
    entry["neck_rms"] = float(np.sqrt(np.mean((a_neck - b_neck) ** 2)))
    entry["native"] = {"joins_ms": [i * 1000 / align.GRID_HZ for i in a_joins], "splits_ms": [i * 1000 / align.GRID_HZ for i in a_splits]}
    entry["flutter"] = {"joins_ms": [i * 1000 / align.GRID_HZ for i in b_joins], "splits_ms": [i * 1000 / align.GRID_HZ for i in b_splits]}
    return entry


def compare(scene, native, flutter):
    result = {
        "event_count": [len(native["events"]), len(flutter["events"])],
        "unpaired": unpaired(native, flutter),
        "touches": [len(native["touches"]), len(flutter["touches"])],
        "expected_touches": touch.expected_touches(scene.steps),
        "stalls": {"native": native.get("stalls", []), "flutter": flutter.get("stalls", [])},
        "steps": [sorted({e["step"] for e in native["events"] if e["step"] is not None}), sorted({e["step"] for e in flutter["events"] if e["step"] is not None})],
        "pairs": {},
    }
    for label, a, b in pairs(native, flutter):
        pair = {"shapes": {}}
        da, db = delay(a, scene.steps, native["touches"]), delay(b, scene.steps, flutter["touches"])
        if da is not None and db is not None:
            pair["delay"] = {"native": da, "flutter": db}
            pair["delay_ms"] = abs(da - db)
        for name in regions(scene):
            sa, sb = a["series"][name], b["series"][name]
            shape = {}
            if name in scene.topology:
                topology = compare_topology(sa, sb)
                if topology:
                    shape["topology"] = topology
            for key in align.KEYS:
                entry = compare_key(key, sa[key], sb[key])
                if entry:
                    shape[key] = entry
            progress = compare_progress(sa, sb)
            if progress:
                shape["progress"] = progress
            shape["first_frame"] = {"native": a.get("first_frame", {}).get(name), "flutter": b.get("first_frame", {}).get(name)}
            pair["shapes"][name] = shape
        result["pairs"][label] = pair
    return result


def measures(result):
    found = {}
    for label, pair in result["pairs"].items():
        if "delay_ms" in pair:
            found[f"{label}.delay_ms"] = pair["delay_ms"]
        for name, shape in pair["shapes"].items():
            for key, entry in shape.items():
                for measure, value in entry.items():
                    if measure in LIMITS and isinstance(value, (int, float)):
                        found[f"{name}.{label}.{key}.{measure}"] = float(value)
    return found


def expected(result, scene):
    names = []
    for label in result["pairs"]:
        for measure in scene.motion:
            if measure == "delay_ms":
                names.append(f"{label}.delay_ms")
                continue
            owners = scene.topology if measure.startswith("topology.") else scene.track
            names += [f"{name}.{label}.{measure}" for name in owners]
    return names


def limits(result, scene, noise=None, factor=1.5):
    noise = noise or {}
    native, flutter = result["event_count"]
    found = {"events.native_motion": (native, 1, "min")}
    steps_native, steps_flutter = result["steps"]
    if steps_native and steps_flutter:
        found["events.steps"] = (len(set(steps_native) ^ set(steps_flutter)), 0, "max")
    found["events.unpaired"] = (sum(result.get("unpaired", {}).values()), 0, "max")
    if scene.touches:
        for side, count in zip(("native", "flutter"), result["touches"]):
            found[f"touches.{side}"] = (abs(count - result.get("expected_touches", 0)), 0, "max")
    present = measures(result)
    for name in expected(result, scene):
        value = present.get(name, float("inf"))
        threshold = metrics.THRESHOLDS[LIMITS[name.split(".")[-1]]]
        found[name] = (value, max(threshold, factor * noise.get(name, 0.0)), "max")
    return found


def summary(capture):
    found = {"touches": [[round(a, 3), round(b, 3)] for a, b in capture.get("touches", [])], "frames": capture.get("frames", 0), "shapes": {}}
    for name, rows in capture.get("rows", {}).items():
        times, values = rows["times"], rows["rows"]
        first_touch = capture["touches"][0][0] if capture.get("touches") else None
        rest = max([i for i, t in enumerate(times) if first_touch is None or t < first_touch] or [0])
        widths = [row["width"] for row in values]
        heights = [row["height"] for row in values]
        widest = int(np.argmax(widths))
        found["shapes"][name] = {
            "rest": {key: round(values[rest][key], 2) for key in ("width", "height", "cx", "cy", "luma")},
            "max": {"width": round(max(widths), 2), "height": round(max(heights), 2)},
            "edge_in_band": {"rest": bool(values[rest].get("band")), "max": bool(values[widest].get("band"))},
            "min_visible": {"width": round(min([w for w in widths if w > 0] or [0]), 2), "height": round(min([h for h in heights if h > 0] or [0]), 2)},
        }
    found["events"] = []
    for event in capture.get("events", []):
        entry = {"onset": round(event["onset"], 3), "step": event["step"], "shapes": {}}
        for name, series in event["series"].items():
            features = progress_features(series)
            entry["shapes"][name] = None if features is None else {
                key: (round(value, 3) if isinstance(value, float) else value)
                for key, value in features.items()
                if key not in ("normalized", "times")
            }
        found["events"].append(entry)
    return found


def static_topology(scene, native_dir, flutter_dir):
    found = {}
    for name in scene.topology:
        px = track.pixel_rect(scene.regions[name])
        rows = {}
        for app, folder in (("native", native_dir), ("flutter", flutter_dir)):
            bare = track.crop_px(metrics.load(folder / "bare" / "ready.png"), px)
            rows[app] = track.topology(track.still_mask(track.crop_px(metrics.load(folder / "ready.png"), px), bare))
        found[name] = {
            "native": rows["native"],
            "flutter": rows["flutter"],
            "count": abs(rows["native"]["count"] - rows["flutter"]["count"]),
            "neck_pt": abs(rows["native"]["neck"] - rows["flutter"]["neck"]),
        }
    return found
```

- [ ] **Step 4: The analysis and the report use it.** From the worktree root:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/analyze.py b/packages/mobile/tool/glass_lab/harness/analyze.py
index 5476a4286e60f497a9648733687787cdfb8639bf..aa2d7583557453fd8e6ee5287935dbabcee51f97 100644
--- a/packages/mobile/tool/glass_lab/harness/analyze.py
+++ b/packages/mobile/tool/glass_lab/harness/analyze.py
@@ -7,8 +7,10 @@
 
 import align
 import metrics
+import shapes
 import springfit
 import touch
+import track
 
 OVERVIEW_FPS = 20
 MATCH_MARGIN = 6.0
@@ -121,6 +123,9 @@
         return {"events": [], "stalls": []}
     start, end, _ = found
     crops = frames(case_dir / "video.mp4", max(0.0, start - LEAD_SECONDS), end, region, case_dir / "frames")
+    settled_path = case_dir / "settled.png"
+    if settled_path.exists():
+        crops = track.teardown_cut(crops, shrink(metrics.crop(metrics.load(settled_path), region)))
     if len(crops) < 2:
         return {"events": [], "stalls": []}
     bare_path = case_dir / "bare" / "ready.png"
@@ -132,6 +137,27 @@
         if align.significant(series):
             found_events.append({"start": crops.times[first], "series": series})
     return {"events": found_events, "stalls": align.stalls(diffs, crops.times), "first_time": crops.times[0]}
+
+
+def shape_capture(scene, case_dir, cache=None):
+    key = (scene.id, str(Path(case_dir).resolve()))
+    if cache is not None and key in cache:
+        return cache[key]
+    found = window(case_dir)
+    captured = shapes.capture(scene, case_dir, found[:2] if found else None)
+    if cache is not None:
+        cache[key] = captured
+    return captured
+
+
+def cached_motion(case_dir, region, cache=None):
+    key = ("motion", str(Path(case_dir).resolve()), tuple(region))
+    if cache is not None and key in cache:
+        return cache[key]
+    found = motion(case_dir, region)
+    if cache is not None:
+        cache[key] = found
+    return found
 
 
 def compare_series(key, a, b, a_full, b_full):
@@ -214,15 +240,23 @@
     return limits
 
 
+FLOAT_SLACK = 1e-9
+
+
 def within(value, limit, bound):
-    return value >= limit if bound == "min" else value <= limit
+    return value >= limit - FLOAT_SLACK if bound == "min" else value <= limit + FLOAT_SLACK
 
 
 def motion_checks(result, noise=None):
     return {name: within(*entry) for name, entry in motion_limits(result, noise).items()}
 
 
-def analyze(scene, case_dir, noise=None):
+def limit(key, name, noise, value):
+    return (value, max(metrics.THRESHOLDS[key], NOISE_FACTOR * noise.get(name, 0.0)), "max")
+
+
+def analyze(scene, case_dir, noise=None, cache=None):
+    noise = noise or {}
     case_dir = Path(case_dir)
     native_dir, flutter_dir = case_dir / "native", case_dir / "flutter"
     result = {"scene": scene.id, "case": case_dir.name}
@@ -247,10 +281,29 @@
             region,
             elements_for(scene),
         )
-    checks = {f"{name}.{key}": value for name, stat in result["static"].items() for key, value in stat["pass"].items() if key in scene.measures}
-    measures = {f"{name}.{key}": (stat[key], metrics.THRESHOLDS[key], "max") for name, stat in result["static"].items() for key in stat["pass"] if key in scene.measures}
-    if not scene.rest:
-        native, flutter = motion(native_dir, region), motion(flutter_dir, region)
+    measures = {
+        f"{name}.{key}": limit(key, f"{name}.{key}", noise, stat[key])
+        for name, stat in result["static"].items()
+        for key in stat["pass"]
+        if key in scene.measures
+    }
+    if scene.topology:
+        result["topology"] = shapes.static_topology(scene, native_dir, flutter_dir)
+        for name, entry in result["topology"].items():
+            for key, threshold in (("count", "count"), ("neck_pt", "neck_pt")):
+                measures[f"ready.topology.{name}.{key}"] = limit(threshold, f"ready.topology.{name}.{key}", noise, entry[key])
+    checks = {name: within(*entry) for name, entry in measures.items()}
+    if not scene.rest and (scene.track or scene.topology):
+        native, flutter = shape_capture(scene, native_dir, cache), shape_capture(scene, flutter_dir, cache)
+        result["shapes"] = shapes.compare(scene, native, flutter)
+        result["shape_rest"] = {"native": native.get("rest"), "flutter": flutter.get("rest")}
+        result["native_stalls"] = native.get("stalls", [])
+        result["flutter_stalls"] = flutter.get("stalls", [])
+        limits = shapes.limits(result["shapes"], scene, noise)
+        measures.update({f"motion.{k}": v for k, v in limits.items()})
+        checks.update({f"motion.{k}": within(*v) for k, v in limits.items()})
+    elif not scene.rest:
+        native, flutter = cached_motion(native_dir, region, cache), cached_motion(flutter_dir, region, cache)
         result["motion"] = compare_motion(native, flutter)
         result["native_stalls"] = native["stalls"]
         result["flutter_stalls"] = flutter["stalls"]
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/report.py b/packages/mobile/tool/glass_lab/harness/report.py
index a2a5f59e661a544e8917607d604d819ae80873e7..e326c18a6718fc9d7dd5e6ffcb554c9c4efbb749 100644
--- a/packages/mobile/tool/glass_lab/harness/report.py
+++ b/packages/mobile/tool/glass_lab/harness/report.py
@@ -98,6 +98,21 @@
             if "native_spring" in entry:
                 springs = f' · spring native {fmt(entry["native_spring"]["response"])}s/{fmt(entry["native_spring"]["damping"])}, flutter {fmt(entry["flutter_spring"]["response"])}s/{fmt(entry["flutter_spring"]["damping"])}'
             parts.append(f'<div class="small">rms {fmt(entry["rms"])}{springs}</div>')
+    shapes_result = result.get("shapes") or {}
+    if shapes_result:
+        parts.append(f'<div class="small">shape events native/flutter: {shapes_result["event_count"][0]}/{shapes_result["event_count"][1]}, touches {shapes_result["touches"][0]}/{shapes_result["touches"][1]}</div>')
+    for label, pair in shapes_result.get("pairs", {}).items():
+        for name, shape in pair["shapes"].items():
+            progress = shape.get("progress")
+            if not progress:
+                continue
+            native, flutter = progress["native"], progress["flutter"]
+            parts.append(f'<div class="label">{html.escape(name)} · {html.escape(label)} · progress</div>' + svg_lines(progress["curves"]))
+            parts.append(
+                f'<div class="small">10–90% {fmt(native.get("t10_90_ms"))}/{fmt(flutter.get("t10_90_ms"))} ms · settle {fmt(native["settle_ms"])}/{fmt(flutter["settle_ms"])} ms'
+                f' · overshoot {fmt(native["overshoot_pct"])}/{fmt(flutter["overshoot_pct"])} · sharpness at half {fmt(native["sharpness_mid"])}/{fmt(flutter["sharpness_mid"])}'
+                f' · curve rms {fmt(progress["rms"])}</div>'
+            )
     for name, stat in (result.get("static") or {}).items():
         if "rim_native" in stat:
             parts.append(f'<div class="label">rim profile ({name})</div>' + svg_lines({"native": stat["rim_native"], "flutter": stat["rim_flutter"]}))
PATCH
```

- [ ] **Step 5: Run the new tests, then every harness test.**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py`
Expected: `Ran 14 tests` … `OK`.
Run: `python3 -m unittest discover tool/glass_lab/harness/tests`
Expected: `Ran 145 tests` … `OK`.

- [ ] **Step 6: Commit.**

```bash
git add packages/mobile/tool/glass_lab/harness
git commit -m "feat(glass-lab): per-scene motion measures per shape; an absent measure or an unpaired event fails

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
### Task 5: The touch marker in both apps (L5)

**Files:**
- Create: `tool/glass_lab/native/GlassLab/TouchMarker.swift`
- Modify: `tool/glass_lab/native/GlassLab/Lab.swift`, `tool/glass_lab/native/GlassLab/GlassLabApp.swift`, `tool/glass_lab/native/GlassLabDriver/DriverTests.swift`, `tool/glass_lab/harness/record.py`, `packages/ios_liquid_glass/example/lib/lab/glass_lab_launch.dart`, `glass_lab_marker.dart`, `glass_lab_screen.dart`
- Test: `tool/glass_lab/harness/tests/test_record.py`, `packages/ios_liquid_glass/example/test/lab_test.dart`

**Interfaces:**
- Consumes: `manifest.Scene.touches` (Task 3), `touch.MARKER` (Task 2, the same rect).
- Produces:
  - native: launch variable `GLASS_LAB_MARKER=1` shows an 18 pt square at (16, 662) pt, black at rest, red on touch-down and while held, green on move, blue on release, black again 250 ms after release (ruling 7). The driver forwards `TEST_RUNNER_GLASS_MARKER`;
  - example: `GlassLabLaunch.marker` (`"marker": true` in `launch.json`), `GlassLabLaunch.visibility` and `GlassLabLaunch.blurRamp` (`"visibility"`, `"blurRamp"`: doubles, read by Task 19's `tool.visibility`, which `fitvis` scans); `GlassLabTouchMarker` paints the same square from raw pointer events through a translucent `Listener`, so it never takes part in the gesture arena;
  - harness: `record.write_launch_file(folder, scene, backdrop, bare, material=None, material_side=None, marker=False, extra=None)`, `record.drive(..., marker=False, extra=None)`; `record.capture` shows the marker in both the bare and the scene launch of every scene with touch steps, so `ready.png`, `settled.png` and `bare/ready.png` all hold the same black square and no still measure sees it.
- The native marker hooks `UIWindow.sendEvent(_:)` and calls the original first. The spike's version (`proto/2b` 5999b4412, `TouchProbe.swift`) also logged every touch to a file; the lab reads touches from the video only (spec L5), so the log is gone.

- [ ] **Step 1: Write the failing tests.** Harness:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_record.py b/packages/mobile/tool/glass_lab/harness/tests/test_record.py
index 0f78e9924c802461a4bc46ebb674f57318f7103b..ea9892126b42b819dd61bc49269b3779045ee988 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_record.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_record.py
@@ -39,6 +39,24 @@
             self.assertNotIn("materialSide", json.loads((Path(temp) / record.LAUNCH_FILE).read_text()))
 
 
+class MarkerTests(unittest.TestCase):
+    def test_the_marker_and_extra_fields_travel_in_the_launch_file(self):
+        with tempfile.TemporaryDirectory() as temp:
+            record.write_launch_file(temp, "tool.visibility", "photo", False, marker=True, extra={"visibility": 0.4})
+            written = json.loads((Path(temp) / record.LAUNCH_FILE).read_text())
+            self.assertEqual(written, {"scene": "tool.visibility", "backdrop": "photo", "bare": False, "marker": True, "visibility": 0.4})
+
+    def test_touch_scenes_show_the_marker_in_both_launches_and_still_scenes_do_not(self):
+        scenes = {s.id: s for s in manifest.load()}
+        for scene_id, expected in (("material.materialize", True), ("material.regular", False)):
+            with mock.patch.object(record, "drive", return_value={}) as drive, \
+                 mock.patch.object(record, "Recording") as recording:
+                recording.return_value.__enter__.return_value.started = 0
+                with tempfile.TemporaryDirectory() as temp:
+                    record.capture("udid", scenes[scene_id], "native", "stripes", Path(temp))
+            self.assertEqual([call.kwargs["marker"] for call in drive.call_args_list], [expected, expected])
+
+
 class OtherAppsTests(unittest.TestCase):
     def test_every_other_lab_app_is_closed_so_no_back_link_shows_in_the_status_bar(self):
         with mock.patch.object(record.subprocess, "run") as run:
PATCH
```

Example (adds two tests at the end of `main()`):

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/example/test/lab_test.dart b/packages/mobile/packages/ios_liquid_glass/example/test/lab_test.dart
index 4f4a138e9091f0f70bc7625ffeeff549faaee972..3611be7a249fc4ce11aa9fbf6216ff4b06f21ed9 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/test/lab_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/test/lab_test.dart
@@ -4,6 +4,7 @@
 import 'package:flutter/material.dart';
 import 'package:flutter_test/flutter_test.dart';
 import 'package:ios_liquid_glass_example/lab/glass_lab_launch.dart';
+import 'package:ios_liquid_glass_example/lab/glass_lab_marker.dart';
 import 'package:ios_liquid_glass_example/lab/glass_lab_registry.dart';
 import 'package:ios_liquid_glass_example/lab/glass_lab_screen.dart';
 import 'package:ios_liquid_glass_example/lab/scenes/lab_parts.dart';
@@ -81,4 +82,30 @@
     }
     semantics.dispose();
   });
+
+  test('reads the touch marker and a fixed visibility from the launch file', () {
+    final launch = GlassLabLaunch.fromJson({'scene': 'tool.visibility', 'marker': true, 'visibility': 0.35, 'blurRamp': 2});
+    expect(launch?.marker, isTrue);
+    expect(launch?.visibility, 0.35);
+    expect(launch?.blurRamp, 2);
+    expect(GlassLabLaunch.fromJson({'scene': 'material.regular'})?.marker, isFalse);
+  });
+
+  testWidgets('the touch marker is red while down, blue after release and black again', (tester) async {
+    tester.view.physicalSize = const Size(1206, 2622);
+    tester.view.devicePixelRatio = 3;
+    addTearDown(tester.view.reset);
+    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.regular', marker: true))));
+    Color colour() => tester.widget<ColoredBox>(find.byKey(const ValueKey('touch.marker'))).color;
+    expect(tester.getRect(find.byKey(const ValueKey('touch.marker'))), GlassLabTouchMarker.rect);
+    expect(colour(), GlassLabTouchMarker.idle);
+    final gesture = await tester.startGesture(const Offset(201, 300));
+    await tester.pump();
+    expect(colour(), GlassLabTouchMarker.down);
+    await gesture.up();
+    await tester.pump();
+    expect(colour(), GlassLabTouchMarker.up);
+    await tester.pump(const Duration(milliseconds: 300));
+    expect(colour(), GlassLabTouchMarker.idle);
+  });
 }
PATCH
```

- [ ] **Step 2: Run them and see them fail.**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_record.py`
Expected: `TypeError: write_launch_file() got an unexpected keyword argument 'marker'` and a failure on the `marker` keyword in `capture`.
Run (from `packages/mobile/packages/ios_liquid_glass/example`): `flutter test --no-pub test/lab_test.dart`
Expected: compile errors, `No named parameter with the name 'marker'` and `Undefined name 'GlassLabTouchMarker'`.

- [ ] **Step 3: The native marker.** Create `tool/glass_lab/native/GlassLab/TouchMarker.swift`:

```swift
import ObjectiveC
import SwiftUI
import UIKit

extension Notification.Name {
    static let labTouch = Notification.Name("lab.touch")
}

enum TouchRelay {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        guard
            let original = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.sendEvent(_:))),
            let replacement = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.labSendEvent(_:)))
        else { return }
        method_exchangeImplementations(original, replacement)
    }

    static func relay(_ event: UIEvent) {
        guard event.type == .touches, let touch = event.allTouches?.first else { return }
        NotificationCenter.default.post(name: .labTouch, object: touch.phase.rawValue)
    }
}

extension UIWindow {
    @objc func labSendEvent(_ event: UIEvent) {
        labSendEvent(event)
        TouchRelay.relay(event)
    }
}

struct TouchMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> TouchMarkerView {
        TouchRelay.install()
        return TouchMarkerView()
    }

    func updateUIView(_ uiView: TouchMarkerView, context: Context) {}
}

final class TouchMarkerView: UIView {
    static let restDelay: TimeInterval = 0.25
    private var observer: NSObjectProtocol?
    private var generation = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        observer = NotificationCenter.default.addObserver(forName: .labTouch, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.object as? Int, let phase = UITouch.Phase(rawValue: raw) else { return }
            self?.show(phase)
        }
    }

    required init?(coder: NSCoder) { nil }

    private func show(_ phase: UITouch.Phase) {
        generation += 1
        switch phase {
        case .began, .stationary:
            backgroundColor = .red
        case .moved:
            backgroundColor = .green
        case .ended, .cancelled:
            backgroundColor = .blue
            let current = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.restDelay) { [weak self] in
                guard let self, self.generation == current else { return }
                self.backgroundColor = .black
            }
        default:
            break
        }
    }
}
```

Then:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/native/GlassLab/Lab.swift b/packages/mobile/tool/glass_lab/native/GlassLab/Lab.swift
index fa12118681fc1a6cc4dfd413f0b1e926c95ec2d7..3c7c766f2429daf5d208ac75f3b1ad19f9a67cb8 100644
--- a/packages/mobile/tool/glass_lab/native/GlassLab/Lab.swift
+++ b/packages/mobile/tool/glass_lab/native/GlassLab/Lab.swift
@@ -6,6 +6,7 @@
     static let sceneID = environment["GLASS_LAB_SCENE"]
     static let bare = environment["GLASS_LAB_BARE"] == "1"
     static let backdropID = environment["GLASS_LAB_BACKDROP"] ?? "stripes"
+    static let marker = environment["GLASS_LAB_MARKER"] == "1"
     static let accent = Color(red: 0x1A / 255, green: 0xCB / 255, blue: 0x64 / 255)
 
     static func image(_ id: String) -> UIImage? {
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/native/GlassLab/GlassLabApp.swift b/packages/mobile/tool/glass_lab/native/GlassLab/GlassLabApp.swift
index 79364100c46d29ec198a72bf8287997320956d1e..b23337469cb306445f6fb8ae06754e7f0f2d5cd2 100644
--- a/packages/mobile/tool/glass_lab/native/GlassLab/GlassLabApp.swift
+++ b/packages/mobile/tool/glass_lab/native/GlassLab/GlassLabApp.swift
@@ -36,6 +36,11 @@
             }
         }
         .overlay(alignment: .topLeading) { ReadyMarker() }
+        .overlay(alignment: .bottomLeading) {
+            if Lab.marker {
+                TouchMarker().frame(width: 18, height: 18).padding(.leading, 16).padding(.bottom, 160)
+            }
+        }
     }
 }
 
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/native/GlassLabDriver/DriverTests.swift b/packages/mobile/tool/glass_lab/native/GlassLabDriver/DriverTests.swift
index 63d634f2856e7fac380a6f22142210a3e7f34ae5..4aed2be00200e9f17f40a5d8d9fca4f42fac7946 100644
--- a/packages/mobile/tool/glass_lab/native/GlassLabDriver/DriverTests.swift
+++ b/packages/mobile/tool/glass_lab/native/GlassLabDriver/DriverTests.swift
@@ -13,6 +13,7 @@
             app.launchEnvironment["GLASS_LAB_SCENE"] = scene
             app.launchEnvironment["GLASS_LAB_BACKDROP"] = environment["GLASS_BACKDROP"] ?? "stripes"
             app.launchEnvironment["GLASS_LAB_BARE"] = environment["GLASS_BARE"] ?? "0"
+            app.launchEnvironment["GLASS_LAB_MARKER"] = environment["GLASS_MARKER"] ?? "0"
         }
         app.launch()
         dismissSystemPrompts()
PATCH
```

- [ ] **Step 4: The harness passes the marker to both apps.**

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/record.py b/packages/mobile/tool/glass_lab/harness/record.py
index fae5cb938bbf3566a8361e85c860db8c66456dfb..f47298b815aebc95095545901fdf58056805391f 100644
--- a/packages/mobile/tool/glass_lab/harness/record.py
+++ b/packages/mobile/tool/glass_lab/harness/record.py
@@ -47,10 +47,14 @@
     return sim.container(udid, target) / "Documents" / "glass_lab"
 
 
-def write_launch_file(folder, scene_id, backdrop, bare, material=None, material_side=None):
+def write_launch_file(folder, scene_id, backdrop, bare, material=None, material_side=None, marker=False, extra=None):
     folder = Path(folder)
     folder.mkdir(parents=True, exist_ok=True)
     payload = {"scene": scene_id, "backdrop": backdrop, "bare": bare}
+    if marker:
+        payload["marker"] = True
+    if extra:
+        payload.update(extra)
     if material:
         payload["material"] = material
     if material and material_side:
@@ -68,13 +72,13 @@
             subprocess.run(["xcrun", "simctl", "terminate", udid, bundle], capture_output=True)
 
 
-def drive(udid, target, scene_id, steps, backdrop, bare, out_dir, settle=1.5, material=None, material_side=None):
+def drive(udid, target, scene_id, steps, backdrop, bare, out_dir, settle=1.5, material=None, material_side=None, marker=False, extra=None):
     out_dir = Path(out_dir)
     out_dir.mkdir(parents=True, exist_ok=True)
     close_other_apps(udid, target)
     folder = launch_folder(udid, target) if target in build.FLUTTER_TARGETS.values() and scene_id else None
     if folder:
-        write_launch_file(folder, scene_id, backdrop, bare, material, material_side)
+        write_launch_file(folder, scene_id, backdrop, bare, material, material_side, marker, extra)
     env = dict(
         os.environ,
         TEST_RUNNER_GLASS_TARGET=target,
@@ -82,6 +86,7 @@
         TEST_RUNNER_GLASS_STEPS=json.dumps(list(steps)),
         TEST_RUNNER_GLASS_BACKDROP=backdrop,
         TEST_RUNNER_GLASS_BARE="1" if bare else "0",
+        TEST_RUNNER_GLASS_MARKER="1" if marker else "0",
         TEST_RUNNER_GLASS_SETTLE=str(settle),
         TEST_RUNNER_GLASS_OUT=str(out_dir),
     )
@@ -123,10 +128,11 @@
     out_dir = Path(out_dir)
     target = target_for(scene, app, flutter_target)
     scene_id = "" if scene.native_only else scene.id
+    marker = not scene.native_only and scene.touches
     if not scene.native_only:
-        drive(udid, target, scene_id, [], backdrop, True, out_dir / "bare", settle=1.0)
+        drive(udid, target, scene_id, [], backdrop, True, out_dir / "bare", settle=1.0, marker=marker)
     with Recording(udid, out_dir / "video.mp4") as recording:
-        timing = drive(udid, target, scene_id, scene.steps, backdrop, False, out_dir)
+        timing = drive(udid, target, scene_id, scene.steps, backdrop, False, out_dir, marker=marker)
     timing["video_start"] = recording.started
     (out_dir / "timing.json").write_text(json.dumps(timing))
     return timing
PATCH
```

- [ ] **Step 5: The example's marker.**

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_launch.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_launch.dart
index d4fdef9207b82fc8cb684dcc55eed6c31508d284..3d923746b1f66d157271f42705ee22f31ddd7af7 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_launch.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_launch.dart
@@ -4,7 +4,16 @@
 import 'package:path_provider/path_provider.dart';
 
 class GlassLabLaunch {
-  const GlassLabLaunch({required this.scene, this.backdrop = defaultBackdrop, this.bare = false, this.material = const {}, this.materialSide});
+  const GlassLabLaunch({
+    required this.scene,
+    this.backdrop = defaultBackdrop,
+    this.bare = false,
+    this.material = const {},
+    this.materialSide,
+    this.marker = false,
+    this.visibility,
+    this.blurRamp,
+  });
 
   static const String defaultBackdrop = 'stripes';
   static const String launchFile = 'launch.json';
@@ -15,6 +24,9 @@
   final bool bare;
   final Map<String, double> material;
   final double? materialSide;
+  final bool marker;
+  final double? visibility;
+  final double? blurRamp;
 
   static GlassLabLaunch? fromJson(Object? json) {
     if (json is! Map<String, dynamic>) return null;
@@ -23,6 +35,8 @@
     final backdrop = json['backdrop'];
     final material = json['material'];
     final materialSide = json['materialSide'];
+    final visibility = json['visibility'];
+    final blurRamp = json['blurRamp'];
     return GlassLabLaunch(
       scene: scene,
       backdrop: backdrop is String && backdrop.isNotEmpty ? backdrop : defaultBackdrop,
@@ -31,6 +45,9 @@
           ? {for (final entry in material.entries) if (entry.value is num) entry.key: (entry.value as num).toDouble()}
           : const {},
       materialSide: materialSide is num ? materialSide.toDouble() : null,
+      marker: json['marker'] == true,
+      visibility: visibility is num ? visibility.toDouble() : null,
+      blurRamp: blurRamp is num ? blurRamp.toDouble() : null,
     );
   }
 
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_marker.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_marker.dart
index 753add2e01036a54d13c3c41d53826500770de6f..bdc9cadb3b4c5b9ff0ce6c36ef7fe36023c4792f 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_marker.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_marker.dart
@@ -16,3 +16,53 @@
   @override
   Widget build(BuildContext context) => const GlassLabMarker('scene.ready', child: SizedBox(width: 1, height: 1));
 }
+
+class GlassLabTouchMarker extends StatefulWidget {
+  const GlassLabTouchMarker({super.key, required this.child});
+
+  static const Rect rect = Rect.fromLTWH(16, 662, 18, 18);
+  static const Duration restDelay = Duration(milliseconds: 250);
+  static const Color idle = Color(0xFF000000);
+  static const Color down = Color(0xFFFF0000);
+  static const Color moved = Color(0xFF00FF00);
+  static const Color up = Color(0xFF0000FF);
+
+  final Widget child;
+
+  @override
+  State<GlassLabTouchMarker> createState() => _GlassLabTouchMarkerState();
+}
+
+class _GlassLabTouchMarkerState extends State<GlassLabTouchMarker> {
+  Color _color = GlassLabTouchMarker.idle;
+  int _generation = 0;
+
+  void _show(Color color) {
+    final generation = ++_generation;
+    setState(() => _color = color);
+    if (color != GlassLabTouchMarker.up) return;
+    Future<void>.delayed(GlassLabTouchMarker.restDelay, () {
+      if (mounted && _generation == generation) setState(() => _color = GlassLabTouchMarker.idle);
+    });
+  }
+
+  @override
+  Widget build(BuildContext context) {
+    return Listener(
+      behavior: HitTestBehavior.translucent,
+      onPointerDown: (_) => _show(GlassLabTouchMarker.down),
+      onPointerMove: (_) => _show(GlassLabTouchMarker.moved),
+      onPointerUp: (_) => _show(GlassLabTouchMarker.up),
+      onPointerCancel: (_) => _show(GlassLabTouchMarker.up),
+      child: Stack(
+        children: [
+          Positioned.fill(child: widget.child),
+          Positioned.fromRect(
+            rect: GlassLabTouchMarker.rect,
+            child: IgnorePointer(child: ColoredBox(key: const ValueKey('touch.marker'), color: _color)),
+          ),
+        ],
+      ),
+    );
+  }
+}
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_screen.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_screen.dart
index 52358f45ab846fa0caab6e54217c2343b4cdbf4d..6fdd46139e53f58028202735fb07f79b42d702d1 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_screen.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_screen.dart
@@ -12,6 +12,8 @@
 
   final GlassLabLaunch launch;
 
+  Widget _marked(Widget child) => launch.marker ? GlassLabTouchMarker(child: child) : child;
+
   @override
   Widget build(BuildContext context) {
     final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
@@ -23,11 +25,13 @@
         child: GlassLabAccessibilityProbe(
           child: Material(
             type: MaterialType.transparency,
-            child: Stack(
-              children: [
-                Positioned.fill(child: GlassLabRegistry.build(launch)),
-                const Positioned(left: 0, top: 0, child: GlassLabReady()),
-              ],
+            child: _marked(
+              Stack(
+                children: [
+                  Positioned.fill(child: GlassLabRegistry.build(launch)),
+                  const Positioned(left: 0, top: 0, child: GlassLabReady()),
+                ],
+              ),
             ),
           ),
         ),
PATCH
```

- [ ] **Step 6: Run the tests and the gates.**

Run (from `packages/mobile`): `python3 -m unittest discover tool/glass_lab/harness/tests`
Expected: `Ran 147 tests` … `OK`. `test_generated.py` still passes: the Xcode project uses synchronised folders, so `TouchMarker.swift` needs no project change.
Run (from the example): `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+10: All tests passed!`.

- [ ] **Step 7: Prove the marker on the simulator.** Build both apps and record one materialize case in each:

```bash
python3 tool/glass_lab/harness/lab.py build native
python3 tool/glass_lab/harness/lab.py build example
python3 tool/glass_lab/harness/lab.py run material.materialize --appearance dark --backdrop photo
```

Then read the touches back (replace `<run>` with the folder the run printed):

```bash
python3 - <<'EOF'
import sys
sys.path.insert(0, "tool/glass_lab/harness")
import touch
from pathlib import Path
case = Path("build/glass_lab/runs/<run>/material.materialize/dark-photo")
for app in ("native", "flutter"):
    print(app, [(round(a, 3), round(b, 3)) for a, b in touch.read(case / app / "video.mp4", case / app / "marker")])
EOF
```

Expected: two touches per app (the two `toggle` taps), each 30–110 ms long. The prototype read native `(16.233, 16.275)`, `(18.907, 18.977)` (run `20261003-032332`) and two touches in the example's video (run `20261003-042321`). If either list is empty, open a frame of `video.mp4` at a touch: the square must sit at (16, 662) pt, which is (48, 1986) px.

- [ ] **Step 8: Commit.**

```bash
git add packages/mobile/tool/glass_lab/native packages/mobile/tool/glass_lab/harness packages/mobile/packages/ios_liquid_glass/example
git commit -m "feat(glass-lab): touch marker in the native and example apps, read from the video

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Lab commands — `measure`, per-case `repeat` over two sessions, `reboot`, a native freshness stamp — and the reproduction of known native numbers (L8 machinery, Done item 1)

**Files:**
- Create: `tool/glass_lab/harness/reproduce.py`
- Modify: `tool/glass_lab/harness/lab.py`, `tool/glass_lab/harness/sim.py`, `tool/glass_lab/harness/build.py`, `tool/glass_lab/noise.json`
- Test: `tool/glass_lab/harness/tests/test_lab.py`

**Interfaces:**
- Consumes: `shapes.capture`, `shapes.measures`, `shapes.summary`, `analyze.analyze(..., cache=)` (Task 4), `record.drive(..., extra=)` (Task 5).
- Produces:
  - `lab.py measure <case_dir> --scene <id>`: prints, per app found in the case (or the folder itself when it holds `video.mp4`), the touches, the rest box of each tracked shape at the last frame before the first touch, its largest and smallest visible box (with `edge_in_band`), and each event's onset, step and progress features;
  - `lab.py repeat <scene> [--times N] [--appearance light|dark|both] [--backdrop B] [--a11y MODE] [--into RUN]`: records N native takes of **every case** of the scene (narrowed by the flags), appends to the takes already in `RUN` when `--into` names one, recomputes the noise of each case from **all** its takes (every pair, named `pair-<i>-<j>`, each take captured once), and writes it to `noise.json` as `{scene: {case: {measure: value}}}`: the motion measures, and the static and still-topology measures (`ready.mad`, `ready.topology.g8.neck_pt`, …) so stills get noise floors too (finding 10). Non-finite values (an invalid fit) never become a noise. The static repeatability check (MAD ≤ 1.0) stays. `--into` takes an absolute path (the driver resolves a relative one against `/`);
  - `lab.py reboot`: shuts the iOS 27 simulator down, boots it, re-applies the status bar;
  - `lab.noise_for(noise, scene, case)`: reads a per-case entry, or an old scene-wide entry (`menu.bar`, `tabbar.drag`) as before;
  - `build.native` stamps `build/glass_lab/native/sources.sha256` from `native/GlassLab` and `native/GlassLabDriver`; `lab.py run` (any native recording) and `lab.py repeat` refuse a stale native build, as `run` already refuses a stale Flutter one (finding 17); `reproduce.py` only reads recordings made elsewhere, so it needs no build (R10);
- `noise.json` loses the `tabbar.drag` `event2.*` entries: that event was the teardown frame, which Task 1 no longer analyses (spec L8).

- [ ] **Step 1: Write the failing tests.** Extend `test_lab.py`:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_lab.py b/packages/mobile/tool/glass_lab/harness/tests/test_lab.py
index e090c5005b42615fd690b9b3378b724ab70eb507..8ad7c99915453885d1207e9cf17f57fe0e610070 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_lab.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_lab.py
@@ -70,7 +70,20 @@
              mock.patch.object(lab, "new_run_dir", return_value=Path(temp)):
             lab.cmd_run(args)
             self.assertEqual(json.loads((Path(temp) / "run.json").read_text()), {"flutter": "example", "a11y": "none"})
-        fresh.assert_not_called()
+        fresh.assert_called_once_with("native")
+
+    def test_repeat_refuses_a_stale_native_build_before_touching_the_simulator(self):
+        args = lab.parser().parse_args(["repeat", "material.materialize"])
+        with mock.patch.object(lab.build, "require_fresh", side_effect=SystemExit("stale")) as fresh, \
+             mock.patch.object(lab.sim, "device") as device:
+            with self.assertRaises(SystemExit):
+                lab.cmd_repeat(args)
+        fresh.assert_called_once_with("native")
+        device.assert_not_called()
+
+    def test_the_native_build_is_stamped_from_its_swift_sources(self):
+        self.assertEqual(lab.build.SOURCES["native"], (lab.build.NATIVE / "GlassLab", lab.build.NATIVE / "GlassLabDriver"))
+        self.assertEqual(lab.build.STAMPS["native"].parent, lab.build.NATIVE_DATA)
 
 
 class AccessibilityRestoredOnFailureTests(unittest.TestCase):
@@ -112,5 +125,58 @@
         self.assertEqual(calls, ["increaseContrast", "none"])
 
 
+class NoiseTests(unittest.TestCase):
+    def test_per_case_noise_is_read_per_case_and_old_entries_stay_scene_wide(self):
+        noise = {"material.materialize": {"dark-photo": {"block.step1e0.progress.rms": 0.02}}, "menu.bar": {"event0.width.peak_ms": 8.0}}
+        self.assertEqual(lab.noise_for(noise, "material.materialize", "dark-photo"), {"block.step1e0.progress.rms": 0.02})
+        self.assertEqual(lab.noise_for(noise, "material.materialize", "light-photo"), {})
+        self.assertEqual(lab.noise_for(noise, "menu.bar", "dark-photo"), {"event0.width.peak_ms": 8.0})
+        self.assertEqual(lab.noise_for(noise, "material.regular", "dark-photo"), {})
+
+    def test_the_teardown_entries_are_gone_from_the_committed_noise(self):
+        noise = json.loads(lab.NOISE.read_text())
+        self.assertFalse([name for name in noise["tabbar.drag"] if name.startswith("event2.")])
+
+    def test_repeat_covers_every_case_unless_narrowed(self):
+        import manifest
+        scene = {s.id: s for s in manifest.load()}["material.materialize"]
+        self.assertEqual(lab.repeat_cases(scene), [("light", "stripes"), ("light", "photo"), ("dark", "stripes"), ("dark", "photo")])
+        self.assertEqual(lab.repeat_cases(scene, "dark", "photo"), [("dark", "photo")])
+
+    def test_pairs_of_takes_have_distinct_names_past_ten_takes_and_each_take_is_captured_once(self):
+        import manifest
+        scene = {s.id: s for s in manifest.load()}["material.materialize"]
+        calls = []
+
+        def analyze_pair(scene, case, cache=None):
+            for side in ("native", "flutter"):
+                key = (scene.id, str((case / side).resolve()))
+                if key not in cache:
+                    calls.append(key)
+                    cache[key] = {}
+            return {"static": {}, "measures": {"ready.mad": (1.5, 4.0, "max"), "ready.topology.g4.neck_pt": (float("nan"), 1.0, "max")}, "shapes": {"pairs": {"step1e0": {"shapes": {"block": {"progress": {"rms": 0.01, "response_pct": float("inf")}}}}}}}
+
+        with tempfile.TemporaryDirectory() as temp:
+            takes = []
+            for number in range(12):
+                (Path(temp) / "takes" / str(number)).mkdir(parents=True)
+                takes.append(Path(temp) / "takes" / str(number))
+            with mock.patch.object(lab.analyze, "analyze", side_effect=analyze_pair):
+                worst, _ = lab.case_noise(scene, takes, Path(temp) / "pairs")
+            names = [p.name for p in (Path(temp) / "pairs").iterdir()]
+        self.assertEqual(len(names), 66)
+        self.assertEqual(len(set(names)), 66)
+        self.assertIn("pair-1-11", names)
+        self.assertIn("pair-11-1", [f"pair-{b}-{a}" for a, b in (n.split("-")[1:] for n in names)])
+        self.assertEqual(len(calls), 12)
+        self.assertEqual(worst, {"ready.mad": 1.5, "block.step1e0.progress.rms": 0.01})
+
+    def test_takes_are_numbered_after_the_ones_already_there(self):
+        with tempfile.TemporaryDirectory() as temp:
+            for name in ("0", "1", "2", "pair-01"):
+                (Path(temp) / name).mkdir()
+            self.assertEqual(lab.take_numbers(temp), [0, 1, 2])
+
+
 if __name__ == "__main__":
     unittest.main()
PATCH
```

- [ ] **Step 2: Run them and see them fail.**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_lab.py`
Expected: 15 tests, 2 failures and 6 errors: `AttributeError: module 'lab' has no attribute 'case_noise'` (then `noise_for`, `repeat_cases`, `take_numbers`), `KeyError: 'native'`, the `noise.json` test listing the `tabbar.drag` `event2.*` entries, `Expected 'require_fresh' to be called once`, and a `CalledProcessError` from `xcrun simctl ui <MagicMock …> appearance light`: the old `repeat` still sets the appearance itself, with the test's fake device id, which `simctl` rejects without touching a simulator.

- [ ] **Step 3: The commands, the reboot, the native stamp and the noise file.** From the worktree root:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/lab.py b/packages/mobile/tool/glass_lab/harness/lab.py
index d6af493536081f144ee15f3ede7bcbce9dc565db..8b45133c38fb242690b10300e3d593d9927a89a4 100644
--- a/packages/mobile/tool/glass_lab/harness/lab.py
+++ b/packages/mobile/tool/glass_lab/harness/lab.py
@@ -1,5 +1,6 @@
 import argparse
 import json
+import math
 import re
 import sys
 import time
@@ -15,6 +16,7 @@
 import probe
 import record
 import report
+import shapes
 import sim
 import tonefit
 import tune
@@ -94,6 +96,8 @@
     scenes = manifest.select(manifest.load(), args.scene)
     if "flutter" in apps_for(args.app) and any(not scene.native_only for scene in scenes):
         build.require_fresh(args.flutter)
+    if "native" in apps_for(args.app) or any(scene.native_only for scene in scenes):
+        build.require_fresh("native")
     udid = sim.device()
     run_dir = new_run_dir()
     (run_dir / "run.json").write_text(json.dumps({"flutter": args.flutter, "a11y": args.a11y}))
@@ -103,6 +107,13 @@
 
 def load_noise():
     return json.loads(NOISE.read_text()) if NOISE.exists() else {}
+
+
+def noise_for(noise, scene_id, case):
+    entry = noise.get(scene_id) or {}
+    if entry and all(isinstance(value, dict) for value in entry.values()):
+        return entry.get(case, {})
+    return entry
 
 
 def analyze_run(run_dir):
@@ -115,7 +126,7 @@
         if any((case_dir / app / "error.txt").exists() for app in ("native", "flutter")):
             (case_dir / "result.json").write_text(json.dumps({"scene": scene.id, "case": case_dir.name, "kind": "error"}))
             continue
-        result = analyze.analyze(scene, case_dir, noise.get(scene.id))
+        result = analyze.analyze(scene, case_dir, noise_for(noise, scene.id, case_dir.name))
         (case_dir / "result.json").write_text(json.dumps(result))
 
 
@@ -156,47 +167,95 @@
     print(json.dumps(counts))
 
 
+def repeat_cases(scene, appearance=None, backdrop=None):
+    appearances = [a for a in scene.appearances if appearance in (None, "both", a)]
+    backdrops = [b for b in scene.backdrops if backdrop in (None, b)]
+    return [(a, b) for a in appearances for b in backdrops]
+
+
+def take_numbers(folder):
+    return sorted(int(p.name) for p in Path(folder).glob("*") if p.is_dir() and p.name.isdigit())
+
+
+def case_noise(scene, takes, case_root):
+    worst, static_worst, cache = {}, 0.0, {}
+    for i in range(len(takes)):
+        for j in range(i + 1, len(takes)):
+            case = case_root / f"pair-{takes[i].name}-{takes[j].name}"
+            case.mkdir(parents=True, exist_ok=True)
+            for name, source in (("native", takes[i]), ("flutter", takes[j])):
+                link = case / name
+                if not link.exists():
+                    link.symlink_to(source.resolve())
+            result = analyze.analyze(scene, case, cache=cache)
+            (case / "result.json").write_text(json.dumps(result))
+            for stat in result.get("static", {}).values():
+                static_worst = max(static_worst, stat["mad"])
+            found = shapes.measures(result["shapes"]) if "shapes" in result else {
+                name: value for name, (value, _) in analyze.motion_measures(result.get("motion", {"events": []})).items()
+            }
+            found.update({name: value for name, (value, _, _) in result.get("measures", {}).items() if not name.startswith("motion.")})
+            for name, value in found.items():
+                if math.isfinite(value):
+                    worst[name] = max(worst.get(name, 0.0), value)
+    return worst, static_worst
+
+
 def cmd_repeat(args):
+    build.require_fresh("native")
     udid = sim.device()
     names = REPEAT_SCENES if args.scene == "default" else [args.scene]
     scenes = [manifest.select(manifest.load(), name)[0] for name in names]
-    run_dir = new_run_dir()
+    run_dir = Path(args.into) if args.into else new_run_dir()
     noise = load_noise()
     failed = []
-    for scene in scenes:
-        appearance, backdrop = scene.appearances[0], scene.backdrops[0]
-        sim.appearance(udid, appearance)
-        takes = []
-        for number in range(args.times):
-            take = run_dir / "takes" / scene.id / str(number)
-            print(f"{scene.id} take {number}", flush=True)
-            record.capture(udid, scene, "native", backdrop, take)
-            takes.append(take)
-        worst, static_worst = {}, 0.0
-        for i in range(len(takes)):
-            for j in range(i + 1, len(takes)):
-                case = run_dir / scene.id / f"pair-{i}{j}"
-                case.mkdir(parents=True, exist_ok=True)
-                for name, source in (("native", takes[i]), ("flutter", takes[j])):
-                    link = case / name
-                    if not link.exists():
-                        link.symlink_to(source)
-                result = analyze.analyze(scene, case)
-                (case / "result.json").write_text(json.dumps(result))
-                for stat in result.get("static", {}).values():
-                    static_worst = max(static_worst, stat["mad"])
-                if "motion" in result:
-                    for name, (value, _) in analyze.motion_measures(result["motion"]).items():
-                        worst[name] = max(worst.get(name, 0.0), value)
-        noise[scene.id] = worst
-        print(f"{scene.id}: static mad {static_worst:.2f}, motion noise {json.dumps({k: round(v, 1) for k, v in worst.items()})}")
-        if static_worst > 1.0:
-            print(f"{scene.id}: static repeatability FAILED (mad {static_worst:.2f} > 1.0)")
-            failed.append(scene.id)
+    try:
+        sim.accessibility(udid, args.a11y)
+        for scene in scenes:
+            entry = noise.get(scene.id, {})
+            if entry and not all(isinstance(value, dict) for value in entry.values()):
+                entry = {}
+            for appearance, backdrop in repeat_cases(scene, args.appearance, args.backdrop):
+                sim.appearance(udid, appearance)
+                name = case_name(appearance, backdrop, args.a11y)
+                folder = run_dir / "takes" / scene.id / name
+                start = (take_numbers(folder) or [-1])[-1] + 1
+                for number in range(start, start + args.times):
+                    print(f"{scene.id} {name} take {number}", flush=True)
+                    record.capture(udid, scene, "native", backdrop, folder / str(number))
+                takes = [folder / str(n) for n in take_numbers(folder)]
+                worst, static_worst = case_noise(scene, takes, run_dir / scene.id / name)
+                entry[name] = worst
+                print(f"{scene.id} {name}: {len(takes)} takes, static mad {static_worst:.2f}, motion noise {json.dumps({k: round(v, 1) for k, v in worst.items()})}")
+                if static_worst > 1.0:
+                    print(f"{scene.id} {name}: static repeatability FAILED (mad {static_worst:.2f} > 1.0)")
+                    failed.append(f"{scene.id} {name}")
+            noise[scene.id] = entry
+    finally:
+        sim.accessibility(udid, "none")
     NOISE.write_text(json.dumps(noise, indent=2, sort_keys=True) + "\n")
     print(NOISE)
+    print(run_dir)
     if failed:
         raise SystemExit(f"static repeatability failed for {', '.join(failed)}")
+
+
+def cmd_reboot(args):
+    udid = sim.reboot()
+    sim.status_bar(udid)
+    print(f"rebooted {udid}")
+
+
+def cmd_measure(args):
+    scene = manifest.select(manifest.load(), args.scene)[0]
+    case = Path(args.case_dir)
+    apps = [case / name for name in ("native", "flutter") if (case / name / "video.mp4").exists()] or [case]
+    summary = {}
+    for app_dir in apps:
+        found = analyze.window(app_dir)
+        capture = shapes.capture(scene, app_dir, found[:2] if found else None)
+        summary[app_dir.name] = shapes.summary(capture)
+    print(json.dumps(summary, indent=2))
 
 
 A11Y_ROWS = {"reduce-transparency": "reduceTransparency", "increase-contrast": "increaseContrast"}
@@ -307,7 +366,16 @@
     t = commands.add_parser("repeat")
     t.add_argument("scene", nargs="?", default="default")
     t.add_argument("--times", type=int, default=3)
+    t.add_argument("--appearance", choices=("light", "dark", "both"))
+    t.add_argument("--backdrop", choices=manifest.BACKDROPS)
+    t.add_argument("--a11y", default="none", choices=sim.A11Y_MODES)
+    t.add_argument("--into")
     t.set_defaults(func=cmd_repeat)
+    commands.add_parser("reboot").set_defaults(func=cmd_reboot)
+    e = commands.add_parser("measure")
+    e.add_argument("case_dir")
+    e.add_argument("--scene", required=True)
+    e.set_defaults(func=cmd_measure)
     u = commands.add_parser("tune")
     u.add_argument("--scene", required=True)
     u.add_argument("--appearance", required=True, choices=("light", "dark"))
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/sim.py b/packages/mobile/tool/glass_lab/harness/sim.py
index c3bd93320bc336298e933888e8f97f0c0f325b74..4515280af3563895a94111d303931d9b420f1687 100644
--- a/packages/mobile/tool/glass_lab/harness/sim.py
+++ b/packages/mobile/tool/glass_lab/harness/sim.py
@@ -22,6 +22,14 @@
     udid = next((d["udid"] for d in devices if d["name"] == DEVICE_NAME), None)
     if udid is None:
         udid = simctl("create", DEVICE_NAME, DEVICE_TYPE, RUNTIME).strip()
+    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
+    simctl("bootstatus", udid, "-b")
+    return udid
+
+
+def reboot():
+    udid = device()
+    subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True)
     subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
     simctl("bootstatus", udid, "-b")
     return udid
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/build.py b/packages/mobile/tool/glass_lab/harness/build.py
index 86d1ee7bff10b73708fd8ef34a3ac1523e23a133..3edc64efa9236d5d84188c59f32fc97fe4af3db4 100644
--- a/packages/mobile/tool/glass_lab/harness/build.py
+++ b/packages/mobile/tool/glass_lab/harness/build.py
@@ -23,8 +23,16 @@
 EXAMPLE_BUNDLE = "dev.operator.iosliquidglass.example"
 FLUTTER_TARGETS = {"example": EXAMPLE_BUNDLE, "operator": FLUTTER_BUNDLE}
 PACKAGE_LIB = MOBILE / "packages" / "ios_liquid_glass" / "lib"
-SOURCES = {"example": (PACKAGE_LIB, EXAMPLE / "lib"), "operator": (PACKAGE_LIB, MOBILE / "lib")}
-STAMPS = {"example": EXAMPLE_DATA / "sources.sha256", "operator": FLUTTER_DATA / "sources.sha256"}
+SOURCES = {
+    "example": (PACKAGE_LIB, EXAMPLE / "lib"),
+    "operator": (PACKAGE_LIB, MOBILE / "lib"),
+    "native": (NATIVE / "GlassLab", NATIVE / "GlassLabDriver"),
+}
+STAMPS = {
+    "example": EXAMPLE_DATA / "sources.sha256",
+    "operator": FLUTTER_DATA / "sources.sha256",
+    "native": NATIVE_DATA / "sources.sha256",
+}
 
 
 def stream(args, cwd=None):
@@ -40,6 +48,7 @@
 
 
 def native(udid):
+    digest = sources_hash(SOURCES["native"])
     stream([sys.executable, str(NATIVE / "gen_project.py")])
     stream([
         "xcodebuild", "build-for-testing",
@@ -49,6 +58,7 @@
         "-derivedDataPath", str(NATIVE_DATA),
     ])
     sim.install(udid, NATIVE_APP)
+    stamp("native", digest)
 
 
 def flutter_app(udid, root, data_path, app_path):
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/noise.json b/packages/mobile/tool/glass_lab/noise.json
index 88ffd8c943764139ca340dc535e4f57869f73eb2..c96885af5c84bfa8eefec9f3ab6725cc88abce03 100644
--- a/packages/mobile/tool/glass_lab/noise.json
+++ b/packages/mobile/tool/glass_lab/noise.json
@@ -75,17 +75,7 @@
     "event1.width.overshoot_pct": 6.25,
     "event1.width.peak_ms": 116.66666666666669,
     "event1.width.response_pct": 6.250000000000005,
-    "event1.width.settle_ms": 50.0,
-    "event2.luma.damping": 0.49,
-    "event2.luma.overshoot_pct": 0.0018722728124975774,
-    "event2.luma.peak_ms": 466.66666666666663,
-    "event2.luma.response_pct": 700.0,
-    "event2.luma.settle_ms": 391.6666666666667,
-    "event2.width.damping": 0.18999999999999995,
-    "event2.width.overshoot_pct": 6.25,
-    "event2.width.peak_ms": 191.66666666666666,
-    "event2.width.response_pct": 540.0,
-    "event2.width.settle_ms": 233.33333333333331
+    "event1.width.settle_ms": 50.0
   },
   "tabbar.rest": {}
 }
PATCH
```

- [ ] **Step 4: Run the harness tests.**

Run: `python3 -m unittest discover tool/glass_lab/harness/tests`
Expected: `Ran 154 tests` … `OK`.

- [ ] **Step 5: Copy the existing native recordings this task reproduces.** They live in other worktrees, which are throwaway; check that every source exists first, and stop if one is gone (report which; do not substitute another run):

```bash
cd /Users/omaraly/development/AI/Operator-2b1/packages/mobile
LG=/Users/omaraly/development/AI/Operator-ios-liquid-glass/packages/mobile/build/glass_lab/runs
P=/Users/omaraly/development/AI/Operator-2b-proto/packages/mobile/build/glass_lab/runs
GL=/Users/omaraly/development/AI/Operator-glass-lab/packages/mobile/build/glass_lab/runs
for d in $LG/20260930-082046/material.materialize $LG/20260930-101816 $LG/20260930-105500 $LG/20261002-160207 $LG/20261002-205855 \
         $P/20261003-012138 $P/20261003-012914 $P/20261003-012427 $P/20261003-012517 $P/20261003-012604 \
         $GL/20260927-024701/takes/menu.bar $GL/20260927-035111/button.press $GL/20260927-022300; do
  [ -d "$d" ] || { echo "MISSING $d"; exit 1; }
done
R=build/glass_lab/reference
copy() { rsync -a --exclude 'frames/' --exclude 'overview/' --exclude 'probe_frames/' --exclude 'probe_marker/' --exclude report_assets --exclude report.html "$1/" "$2/"; }
copy $LG/20260930-082046/material.materialize $R/LG-20260930-082046/material.materialize
for r in 20260930-101816 20260930-105500 20261002-160207 20261002-205855; do copy $LG/$r $R/LG-$r; done
for r in 20261003-012138 20261003-012914 20261003-012427 20261003-012517 20261003-012604; do copy $P/$r $R/P-$r; done
copy $GL/20260927-024701/takes/menu.bar $R/GL-20260927-024701/takes/menu.bar
copy $GL/20260927-035111/button.press $R/GL-20260927-035111/button.press
copy $GL/20260927-022300 $R/GL-20260927-022300
```

Expected: no `MISSING` line. If one appears, stop the task and report it: the plan's reproduction targets come from those recordings.

- [ ] **Step 6: Reproduce the known native numbers (Done item 1).** Create `tool/glass_lab/harness/reproduce.py`, which measures the copied recordings with this task's code and the regions given inline (the scenes are not tracked in `scenes.json` until Task 8):

```python
import sys
from dataclasses import replace
from pathlib import Path

sys.path.insert(0, "tool/glass_lab/harness")

import analyze
import manifest
import shapes

REFERENCE = Path("build/glass_lab/reference")
SCENES = {s.id: s for s in manifest.load()}


def capture(case, scene_id, regions):
    scene = replace(SCENES[scene_id], regions=regions, track=tuple(regions), motion=())
    folder = case / "native" if (case / "native").exists() else case
    found = analyze.window(folder)
    return shapes.capture(scene, folder, found[:2])


def materialize():
    for case in ("dark-photo", "dark-stripes", "light-photo", "light-stripes"):
        found = capture(REFERENCE / "LG-20260930-082046/material.materialize" / case, "material.materialize", {"block": [70, 400, 262, 104]})
        events = shapes.summary(found)["events"]
        rows = found["rows"]["block"]["rows"]
        floor = sorted(row["residual"] for row in rows if row["progress"] < 0.05)
        peak = max(row["residual"] for row in rows)
        timing = " ".join(f"{e['shapes']['block']['t10_90_ms']:.0f}ms/{e['shapes']['block']['sharpness_mid']:.2f}" for e in events)
        print(f"materialize {case}: {timing} residual peak {peak:.2f} floor {floor[len(floor) // 2] if floor else float('nan'):.2f}")


def press():
    cases = [
        ("P-20261003-012138/probe.interactive.v13/dark-stripes", "material.interactive", {"glass": [46, 377, 310, 148]}),
        ("P-20261003-012427/probe.interactive.v16/dark-stripes", "material.interactive", {"glass": [142, 392, 118, 118]}),
        ("P-20261003-012517/probe.interactive.v17/dark-stripes", "material.interactive", {"glass": [102, 394, 198, 114]}),
        ("P-20261003-012604/probe.interactive.v18/dark-stripes", "material.interactive", {"glass": [46, 399, 310, 104]}),
    ]
    for run in ("LG-20260930-101816", "LG-20260930-105500", "LG-20261002-160207", "LG-20261002-205855", "GL-20260927-035111", "GL-20260927-022300"):
        for case in ("dark-stripes", "light-stripes"):
            if (REFERENCE / run / "button.press" / case).exists():
                cases.append((f"{run}/button.press/{case}", "button.press", {"glass": [112, 348, 178, 93], "prominent": [94, 461, 214, 93]}))
    for case, scene_id, regions in cases:
        summary = shapes.summary(capture(REFERENCE / case, scene_id, regions))
        for name, shape in summary["shapes"].items():
            rest, peak = shape["rest"], shape["max"]
            print(f"press {case} {name}: {rest['width']} x {rest['height']} -> {peak['width']} x {peak['height']} ({peak['width'] - rest['width']:+.2f} / {peak['height'] - rest['height']:+.2f})")


def menu():
    scene = SCENES["menu.bar"]
    takes = (REFERENCE / "GL-20260927-024701/takes/menu.bar").resolve()
    for i, j in ((0, 1), (0, 2), (1, 2)):
        case = REFERENCE / "menu-pairs" / f"pair-{i}{j}"
        case.mkdir(parents=True, exist_ok=True)
        for name, take in (("native", i), ("flutter", j)):
            if not (case / name).exists():
                (case / name).symlink_to(takes / str(take))
        motion = analyze.analyze(scene, case)["motion"]
        width = motion["events"][0]["width"]
        springs = [width[side] for side in ("native_spring", "flutter_spring")]
        print(f"menu {case.name}: events {motion['event_count']} springs " + " ".join(f"{s['response']:.2f}/{s['damping']:.2f}" for s in springs))


if __name__ == "__main__":
    {"materialize": materialize, "press": press, "menu": menu}[sys.argv[1]]()
```

Run each part (each takes a few minutes; it extracts every video frame):

```bash
python3 tool/glass_lab/harness/reproduce.py materialize
python3 tool/glass_lab/harness/reproduce.py press
python3 tool/glass_lab/harness/reproduce.py menu
```

Expected, exactly as the prototype printed it (`research/proto-2b1/reproduce.txt`; disappear first, then appear, as `10–90 time / sharpness at half progress`):

```text
materialize dark-photo: 133ms/-1.29 275ms/-1.08 residual peak 5.12 floor 2.67
materialize dark-stripes: 117ms/0.04 275ms/0.00 residual peak 2.85 floor nan
materialize light-photo: 125ms/-1.54 292ms/-1.54 residual peak 5.37 floor 2.13
materialize light-stripes: 117ms/-0.03 292ms/-0.02 residual peak 3.60 floor 1.72
press P-20261003-012138/probe.interactive.v13/dark-stripes glass: 252.0 x 88.67 -> 264.0 x 93.33 (+12.00 / +4.66)
press P-20261003-012427/probe.interactive.v16/dark-stripes glass: 60.0 x 58.67 -> 77.0 x 75.67 (+17.00 / +17.00)
press P-20261003-012517/probe.interactive.v17/dark-stripes glass: 140.0 x 54.0 -> 156.0 x 60.0 (+16.00 / +6.00)
press P-20261003-012604/probe.interactive.v18/dark-stripes glass: 252.0 x 44.67 -> 266.33 x 47.67 (+14.33 / +3.00)
press LG-20260930-101816/button.press/dark-stripes glass: 138.33 x 53.33 -> 154.33 x 59.33 (+16.00 / +6.00)
press LG-20260930-101816/button.press/dark-stripes prominent: 174.33 x 52.67 -> 190.33 x 58.0 (+16.00 / +5.33)
… (the same two lines for light-stripes, and for every other button.press run)
menu pair-01: events [2, 2] springs 0.27/0.78 0.26/0.81
menu pair-02: events [2, 2] springs 0.27/0.78 0.30/0.74
menu pair-12: events [2, 2] springs 0.26/0.81 0.30/0.74
```

How they compare with the spec's targets:
- **Appear 285–320 ms, disappear 117–167 ms**: the 120 Hz-grid times are 275–292 and 117–133 ms. The context brief's numbers were first-frame crossings; on these same frames the raw crossings are 268–320 and 117–150 ms (ruling 6). The two estimators differ by up to 28 ms per case, so Task 9's noise floor for `progress.t10_90_ms` is what Done item 1 is judged against. The "not an alpha fade" result holds on `photo`: peak residual 5.12–5.37 against a glass-absent floor of 2.13–2.67 (context: 5.2–5.5 against 2.4–2.9), and the half-progress sharpness is 1.08–1.54 below the alpha mix (context: 1.1–1.6). On `stripes` there is no alpha-fade signal (2.85 against an unreadable floor, 3.60 against 1.72; ruling 5).
- **v13 +12 / +4.67 pt**: reproduced (+4.66 is 93.33 − 88.67 in floating point).
- **About +17.5 pt on glass up to about 60 pt tall**: +17.0 (58 pt circle) and +16.0 (138×53) reproduce within 2/3 pt; 250×44 reads +14.33, not +17.67. Ruling 2 explains it; its true growth is about 15.0–15.5 pt, because both capsule ends sit inside L1's blind band (`edge_in_band` true at the peak). This number is recorded as not reproduced, with its cause, in `results-2b1.md`. 2B.3's size law is fitted on N2 on `photo`, where no stripe edge hides a rim.
- **`button.press` 138 → 154–155, 174 → 190–192**: 138.33 → 154.33 and 174.33 → 190.33 in all six runs.
- **Menu open 0.26–0.30 s / 0.74–0.81**: three pairs inside it, on the whole-region series (ruling 3), now with 2 events instead of the baseline's 3.

A value that differs from these by more than a third of a point, 17 ms, 0.3 sharpness or 0.01 of a spring constant is a bug to find before Task 8.

- [ ] **Step 7: Commit.**

```bash
git add packages/mobile/tool/glass_lab/harness packages/mobile/tool/glass_lab/noise.json
git commit -m "feat(glass-lab): measure, per-case repeat over sessions, reboot and a native build stamp; reproduce the known native motion numbers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
### Task 7: The `fitvis` tool: the materialize mapping, the blur ramp and Flutter's visibility table, fitted to native (rulings 9–11, 25)

**Files:**
- Create: `tool/glass_lab/harness/fitvis.py`
- Modify: `tool/glass_lab/harness/lab.py`
- Test: `tool/glass_lab/harness/tests/test_fitvis.py`

**Interfaces:**
- Consumes: `shapes.capture`, `shapes.shrink`, `shapes.inner_slices` (Task 4), `record.drive(..., extra=)` (Task 5), `build.require_fresh`, `build.PACKAGE_LIB` (Task 6), `track.pixel_rect`, `track.crop_px` (Task 1).
- Produces:
  - `lab.py fitvis <run> [<run> ...] [--levels 11] [--ramps 1.0,2.0,3.0,4.0] [--out DIR] [--write]` and `fitvis.run(...)`, the only writer of `ios27_motion.dart` (rulings 9–11, 25):
    - reads every native recording of the three materialize scenes in the given runs: a run's `<scene>/<case>/native` and a `repeat` run's `takes/<scene>/<case>/<n>`; the Reduce Motion cases (`<appearance>-<backdrop>-reduce-motion`) fit only each preset's Reduce Motion appear gain, and every other accessibility case is left out;
    - keeps each preset's spring at SwiftUI's constants (`motor`'s `CupertinoMotion`: default 0.55 s / 1.0, `.snappy` 0.5 / 0.85, `.bouncy` 0.5 / 0.7) and fits the **materialize mapping** per preset over every backdrop and take: the disappear exponent `e` (progress = (1 − s)^e) and the appear overshoot gain `g` (progress = s up to 1, then 1 + g·(s − 1)); a preset whose spring does not overshoot (the default, damping 1.0) gets gain 0, marked `identifiable: false`, normal and Reduce Motion alike: no gain can be measured there and none is used (R5); the Reduce Motion gain is fitted the same way on the Reduce Motion curves (`reduce_motion_gain`, with its spread), and is the normal gain, marked `identifiable: false`, when the runs hold no Reduce Motion recording; a gain of 0 (native does not overshoot) is the grid's physical floor and is reported as `at_floor`, not as a grid edge; a curve that no value on the grid fits better than RMS 0.1 (a broken capture) is left out of the fit and listed under `excluded`; it records each fit's spread over the takes;
    - checks the default: a free spring fitted to the default scene's curves, over all cases and per case, must be within 5% and 0.05 of SwiftUI's 0.55 / 1.0 and off its grid edge; the result is `default_spring_check` in `fit.json`, pass or fail, never hidden;
    - fits the blur ramp: scans the example's `tool.visibility` at visibilities 0, 0.2, 0.35, 0.5, 0.65, 0.8 and 1 under each ramp exponent `k` (the backdrop blur at visibility v is blur × v^k), compares Flutter's half-, quarter- and three-quarter-progress sharpness with native's at the same progress, and keeps the `k` with the least RMS difference (`blur_ramp`, with `at_grid_edge`);
    - scans `tool.visibility` at `levels` visibilities under the chosen `k`, inverts Flutter's progress into `ios27VisibilityForProgress`, writes `build/glass_lab/fitvis/<time>/fit.json`, and with `--write` rewrites `packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart` through `fitvis.table_source`. It refuses a stale example build, and reuses any scan shot already in `--out`.
- The example's `tool.visibility` scene it scans is Task 19's; the table it writes is first committed in Task 10 and re-fitted in Task 20.

- [ ] **Step 1: Write the failing tests.** Create `tool/glass_lab/harness/tests/test_fitvis.py`:

```python
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import fitvis
import springfit


def curve(case, appearing, response, damping, exponent=1.0, gain=1.0, lag=0.01, take="t0"):
    t = np.arange(-0.05, 0.9, 1 / 120)
    s = springfit.step_response(np.maximum(t - lag, 0), response, damping)
    alpha = fitvis.mapped(s, appearing, exponent, gain)
    return {"case": case, "take": take, "appearing": appearing, "t": t, "alpha": alpha, "sharpness": -2 * alpha * (1 - alpha)}


class InvertTests(unittest.TestCase):
    def test_the_table_maps_measured_progress_back_to_visibility(self):
        progress = {"dark-photo": {0.0: 0.0, 0.5: 0.8, 1.0: 1.0}, "light-photo": {0.0: 0.0, 0.5: 0.6, 1.0: 1.0}}
        table, mean = fitvis.invert(progress, grid=5)
        self.assertEqual(mean, [0.0, 0.7, 1.0])
        self.assertEqual(table[0], 0.0)
        self.assertEqual(table[-1], 1.0)
        self.assertAlmostEqual(table[2], 0.5 * 0.5 / 0.7, places=3)

    def test_a_non_monotone_measurement_is_made_monotone(self):
        table, _ = fitvis.invert({"x": {0.0: 0.0, 0.25: 0.4, 0.5: 0.35, 0.75: 0.7, 1.0: 1.0}}, grid=11)
        self.assertEqual(table, sorted(table))


class MappingTests(unittest.TestCase):
    def test_each_preset_keeps_its_swiftui_spring_and_gets_its_own_exponent_and_overshoot_gain(self):
        curves = {
            "material.materialize": [curve("dark-photo", True, 0.55, 1.0), curve("dark-photo", False, 0.55, 1.0, 3.2), curve("light-stripes", False, 0.55, 1.0, 3.2)],
            "material.materialize.bouncy": [curve("light-photo", True, 0.5, 0.7, gain=0.5), curve("dark-stripes", False, 0.5, 0.7, 2.7)],
        }
        mapping = fitvis.fit_mapping(curves)
        self.assertEqual(mapping["material.materialize"]["spring"], [0.55, 1.0])
        self.assertAlmostEqual(mapping["material.materialize"]["exponent"]["value"], 3.2, delta=0.06)
        self.assertAlmostEqual(mapping["material.materialize.bouncy"]["exponent"]["value"], 2.7, delta=0.06)
        self.assertAlmostEqual(mapping["material.materialize.bouncy"]["gain"]["value"], 0.5, delta=0.03)
        self.assertFalse(mapping["material.materialize.bouncy"]["gain"]["at_grid_edge"])
        self.assertFalse(mapping["material.materialize"]["gain"]["identifiable"])
        self.assertEqual(mapping["material.materialize"]["gain"]["value"], 0.0)
        self.assertEqual(mapping["material.materialize"]["reduce_motion_gain"]["value"], 0.0)
        self.assertEqual(mapping["material.materialize"]["cases"], ["dark-photo", "light-stripes"])

    def test_a_curve_no_exponent_can_fit_is_left_out_and_reported(self):
        good = [curve("dark-photo", False, 0.5, 0.7, 2.7, take=t) for t in ("a", "b", "c")]
        broken = curve("dark-stripes", False, 0.5, 0.7, 2.7, take="d")
        broken["alpha"] = np.clip(broken["alpha"] + 0.6 * np.sin(np.arange(len(broken["alpha"]))), -1, 2)
        found = fitvis.fit_mapping({"material.materialize.bouncy": good + [broken]})["material.materialize.bouncy"]["exponent"]
        self.assertAlmostEqual(found["value"], 2.7, delta=0.06)
        self.assertEqual([e["take"] for e in found["excluded"]], ["d"])
        self.assertEqual(found["curves"], 3)

    def test_a_gain_of_zero_is_the_floor_not_a_failed_fit(self):
        found = fitvis.fit_mapping({"material.materialize.snappy": [curve("dark-photo", True, 0.5, 0.85, gain=0.0)]})["material.materialize.snappy"]["gain"]
        self.assertEqual(found["value"], 0.0)
        self.assertTrue(found["at_floor"])
        self.assertFalse(found["at_grid_edge"])

    def test_the_spread_across_takes_is_recorded(self):
        curves = {"material.materialize": [curve("dark-photo", False, 0.55, 1.0, 3.0, take="a"), curve("dark-photo", False, 0.55, 1.0, 3.4, take="b")]}
        found = fitvis.fit_mapping(curves)["material.materialize"]["exponent_spread"]
        self.assertAlmostEqual(found["min"], 3.0, delta=0.06)
        self.assertAlmostEqual(found["max"], 3.4, delta=0.06)
        self.assertEqual(sorted(found["per_take"]), ["a", "b"])

    def test_accessibility_cases_are_left_out_of_the_fit_and_every_backdrop_stays_in(self):
        self.assertTrue(fitvis.normal_case("light-stripes"))
        self.assertTrue(fitvis.normal_case("dark-photo"))
        self.assertFalse(fitvis.normal_case("dark-photo-reduce-motion"))
        self.assertTrue(fitvis.reduce_motion_case("dark-photo-reduce-motion"))
        self.assertFalse(fitvis.reduce_motion_case("dark-photo-increase-contrast"))

    def test_reduce_motion_gets_its_own_appear_gain_and_falls_back_to_the_normal_one(self):
        curves = {
            "material.materialize.bouncy": [curve("light-photo", True, 0.5, 0.7, gain=0.3)],
            "material.materialize.snappy": [curve("light-photo", True, 0.5, 0.85, gain=0.2)],
        }
        reduce_motion = {"material.materialize.bouncy": [curve("light-photo-reduce-motion", True, 0.5, 0.7, gain=0.7)]}
        mapping = fitvis.fit_mapping(curves, reduce_motion)
        bouncy, snappy = mapping["material.materialize.bouncy"], mapping["material.materialize.snappy"]
        self.assertAlmostEqual(bouncy["gain"]["value"], 0.3, delta=0.03)
        self.assertAlmostEqual(bouncy["reduce_motion_gain"]["value"], 0.7, delta=0.03)
        self.assertEqual(bouncy["reduce_motion_cases"], ["light-photo-reduce-motion"])
        self.assertEqual(snappy["reduce_motion_gain"]["value"], snappy["gain"]["value"])
        self.assertFalse(snappy["reduce_motion_gain"]["identifiable"])
        alone = fitvis.fit_mapping({"material.materialize.bouncy": curves["material.materialize.bouncy"]})["material.materialize.bouncy"]
        self.assertEqual(alone["reduce_motion_gain"]["value"], alone["gain"]["value"])
        self.assertFalse(alone["reduce_motion_gain"]["identifiable"])


class SpringCheckTests(unittest.TestCase):
    def test_native_at_swiftuis_default_passes_and_a_slower_case_fails_on_its_own(self):
        mapping = {"material.materialize": {"exponent": {"value": 3.2}, "gain": {"value": 1.0}}}
        good = [curve("dark-photo", True, 0.55, 1.0), curve("dark-photo", False, 0.55, 1.0, 3.2)]
        self.assertTrue(fitvis.spring_check(good, mapping)["pass"])
        slow = good + [curve("light-stripes", True, 0.64, 1.0), curve("light-stripes", False, 0.64, 1.0, 3.2)]
        check = fitvis.spring_check(slow, mapping)
        self.assertFalse(check["pass"])
        self.assertTrue(check["cases"]["dark-photo"]["pass"])
        self.assertFalse(check["cases"]["light-stripes"]["pass"])


class RampTests(unittest.TestCase):
    def test_native_sharpness_is_read_at_matched_progress(self):
        found = fitvis.native_sharpness([curve("dark-photo", True, 0.55, 1.0)])
        self.assertAlmostEqual(found["dark-photo"][0.5], -0.5, delta=0.05)

    def test_the_ramp_whose_flutter_sharpness_matches_native_is_chosen(self):
        native = {"dark-photo": {0.25: -0.4, 0.5: -0.5, 0.75: -0.4}}

        def rows(depth):
            return {"dark-photo": {v: (v, -depth * v * (1 - v) * 4) for v in (0.0, 0.25, 0.5, 0.75, 1.0)}}

        chosen = fitvis.choose_ramp(native, {1.0: rows(2.4), 2.0: rows(0.5), 3.0: rows(0.2)})
        self.assertEqual(chosen["value"], 2.0)
        self.assertFalse(chosen["at_grid_edge"])
        self.assertTrue(fitvis.choose_ramp(native, {1.0: rows(2.4), 2.0: rows(1.0)})["at_grid_edge"])


class TableTests(unittest.TestCase):
    def test_the_table_file_is_dart_the_package_reads(self):
        mapping = {
            "material.materialize": {"exponent": {"value": 3.2}, "gain": {"value": 0.55, "identifiable": False}},
            "material.materialize.bouncy": {"exponent": {"value": 2.65}, "gain": {"value": 0.6}},
        }
        source = fitvis.table_source(mapping, 2, [0.0, 0.5, 1.0])
        mapping["material.materialize"]["reduce_motion_gain"] = {"value": 0.8}
        self.assertIn("const double ios27DefaultReduceMotionAppearGain = 0.8;", fitvis.table_source(mapping, 2, [0.0, 0.5, 1.0]))
        self.assertIn("const double ios27BlurRampExponent = 2.0;", source)
        self.assertIn("const double ios27DefaultDisappearExponent = 3.2;", source)
        self.assertIn("const double ios27BouncyAppearGain = 0.6;", source)
        self.assertIn("const double ios27BouncyReduceMotionAppearGain = 0.6;", source)
        self.assertNotIn("Snappy", source)
        self.assertIn("const List<double> ios27VisibilityForProgress = [\n  0.0, 0.5, 1.0,\n];", source)

    def test_levels_span_zero_to_one(self):
        self.assertEqual(fitvis.levels(5), [0.0, 0.25, 0.5, 0.75, 1.0])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and see them fail.**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py`
Expected: `ModuleNotFoundError: No module named 'fitvis'`.

- [ ] **Step 3: Write the fit tool.** Create `tool/glass_lab/harness/fitvis.py`:

```python
import json
from pathlib import Path

import numpy as np

import analyze
import build
import manifest
import metrics
import record
import shapes
import sim
import springfit
import track

SCENES = {
    "material.materialize": (0.55, 1.0),
    "material.materialize.snappy": (0.5, 0.85),
    "material.materialize.bouncy": (0.5, 0.7),
}
PRESETS = {"material.materialize": "Default", "material.materialize.snappy": "Snappy", "material.materialize.bouncy": "Bouncy"}
DEFAULT_SCENE = "material.materialize"
TOOL = "tool.visibility"
TABLE = build.PACKAGE_LIB / "src" / "motion" / "ios27_motion.dart"
GRID = 21
LEVELS = 11
RAMP_LEVELS = (0.0, 0.2, 0.35, 0.5, 0.65, 0.8, 1.0)
RAMPS = (1.0, 2.0, 3.0, 4.0)
LAGS = np.arange(-0.06, 0.0605, 0.002)
EXPONENTS = np.arange(1.0, 6.0001, 0.05)
GAINS = np.arange(0.0, 1.5001, 0.02)
RESPONSES = np.arange(0.3, 0.8001, 0.01)
DAMPINGS = np.arange(0.4, 1.4001, 0.01)
HORIZON = 0.9
OVERSHOOT = 1.001
SHARPNESS_AT = (0.25, 0.5, 0.75)
SHARPNESS_BIN = 0.1
SPRING_TOLERANCE = (0.05, 0.05)
OUTLIER_RMS = 0.1


def levels(count=LEVELS):
    return [round(i / (count - 1), 4) for i in range(count)]


def case_parts(name):
    appearance, backdrop = name.split("-", 1)
    return appearance, backdrop


def normal_case(name):
    return len(name.split("-")) == 2


def reduce_motion_case(name):
    return name.endswith("-reduce-motion") and normal_case(name.removesuffix("-reduce-motion"))


def recordings(roots, scene_id):
    found = []
    for root in roots:
        root = Path(root)
        for case_dir in sorted((root / scene_id).glob("*")):
            if (case_dir / "native" / "video.mp4").exists():
                found.append((case_dir.name, root.name, case_dir / "native"))
        for take in sorted((root / "takes" / scene_id).glob("*/*")):
            if (take / "video.mp4").exists():
                found.append((take.parent.name, f"{root.name}/take{take.name}", take))
    return found


def native_curves(roots, scene):
    curves = []
    for case, take, folder in recordings(roots, scene.id):
        found = analyze.window(folder)
        capture = shapes.capture(scene, folder, found[:2] if found else None)
        rows = capture.get("rows", {}).get(scene.track[0])
        if not rows:
            continue
        times = np.array(rows["times"])
        values = np.array([row["progress"] for row in rows["rows"]])
        sharpness = np.array([row["sharpness"] for row in rows["rows"]])
        for event in capture["events"]:
            chosen = (times >= event["onset"] - 0.1) & (times <= event["onset"] + HORIZON)
            t, a = times[chosen] - event["onset"], values[chosen]
            if len(t) < 4:
                continue
            curves.append({"case": case, "take": take, "appearing": bool(a[-1] > a[0]), "t": t, "alpha": a, "sharpness": sharpness[chosen]})
    return curves


def mapped(s, appearing, exponent, gain):
    if appearing:
        return np.where(s <= 1, np.maximum(s, 0.0), 1 + gain * (s - 1))
    return np.clip(1 - s, 0.0, 1.0) ** exponent


def predicted(curve, response, damping, lag, exponent=1.0, gain=1.0):
    s = springfit.step_response(np.maximum(curve["t"] - lag, 0.0), response, damping)
    return mapped(s, curve["appearing"], exponent, gain)


def best_lag(curve, response, damping, exponent=1.0, gain=1.0):
    errors = [float(np.sqrt(np.mean((predicted(curve, response, damping, lag, exponent, gain) - curve["alpha"]) ** 2))) for lag in LAGS]
    index = int(np.argmin(errors))
    return float(LAGS[index]), errors[index]


def at_edge(value, grid):
    return bool(np.isclose(value, grid[0]) or np.isclose(value, grid[-1]))


def fit_grid(curves, grid, error_of):
    errors = np.array([[error_of(curve, value) for value in grid] for curve in curves])
    best = errors.min(axis=1)
    keep = best <= OUTLIER_RMS
    excluded = [{"take": c["take"], "case": c["case"], "rms": round(float(e), 4)} for c, e, k in zip(curves, best, keep) if not k]
    if not keep.any():
        return None, excluded, 0
    totals = (errors[keep] ** 2).sum(axis=0)
    index = int(np.argmin(totals))
    return (float(grid[index]), float(np.sqrt(totals[index] / keep.sum()))), excluded, int(keep.sum())


def fit_exponent(curves, response, damping):
    leaving = [c for c in curves if not c["appearing"]]
    if not leaving:
        return None
    found, excluded, used = fit_grid(leaving, EXPONENTS, lambda c, k: best_lag(c, response, damping, k)[1])
    if found is None:
        return None
    value, rms = found
    return {"value": round(value, 2), "rms": rms, "at_grid_edge": at_edge(value, EXPONENTS), "curves": used, "excluded": excluded}


def overshoots(response, damping):
    t = np.arange(0, HORIZON, 1 / 240)
    return float(springfit.step_response(t, response, damping).max()) > OVERSHOOT


def fit_gain(curves, response, damping):
    arriving = [c for c in curves if c["appearing"]]
    if not arriving or not overshoots(response, damping):
        return None
    found, excluded, used = fit_grid(arriving, GAINS, lambda c, g: best_lag(c, response, damping, 1.0, g)[1])
    if found is None:
        return None
    value, rms = found
    return {
        "value": round(value, 2),
        "rms": rms,
        "at_grid_edge": bool(np.isclose(value, GAINS[-1])),
        "at_floor": bool(np.isclose(value, GAINS[0])),
        "curves": used,
        "excluded": excluded,
    }


def spread(fits):
    values = [fit["value"] for fit in fits.values() if fit]
    if not values:
        return None
    return {"min": min(values), "max": max(values), "std": round(float(np.std(values)), 3), "per_take": {take: fit["value"] for take, fit in fits.items() if fit}}


def by_take(curves):
    grouped = {}
    for curve in curves:
        grouped.setdefault(curve["take"], []).append(curve)
    return grouped


INERT = {"value": 0.0, "identifiable": False, "from": "the spring does not overshoot, so no gain can be measured and none is used"}


def gains_for(curves, reduce_motion, response, damping):
    if not overshoots(response, damping):
        return dict(INERT), dict(INERT)
    gain = fit_gain(curves, response, damping)
    reduce_gain = fit_gain(reduce_motion, response, damping)
    if reduce_gain is None and not reduce_motion and gain:
        reduce_gain = {**gain, "identifiable": False, "from": "the normal gain: no Reduce Motion recording"}
    return gain, reduce_gain


def fit_mapping(curves_by_scene, reduce_motion_by_scene=None):
    reduce_motion_by_scene = reduce_motion_by_scene or {}
    mapping = {}
    for scene_id, curves in curves_by_scene.items():
        response, damping = SCENES[scene_id]
        takes = by_take(curves)
        reduce_motion = reduce_motion_by_scene.get(scene_id, [])
        gain, reduce_gain = gains_for(curves, reduce_motion, response, damping)
        mapping[scene_id] = {
            "spring": [response, damping],
            "exponent": fit_exponent(curves, response, damping),
            "gain": gain,
            "reduce_motion_gain": reduce_gain,
            "exponent_spread": spread({take: fit_exponent(found, response, damping) for take, found in takes.items()}),
            "gain_spread": spread({take: fit_gain(found, response, damping) for take, found in takes.items()}),
            "reduce_motion_gain_spread": spread({take: fit_gain(found, response, damping) for take, found in by_take(reduce_motion).items()}),
            "cases": sorted({c["case"] for c in curves}),
            "reduce_motion_cases": sorted({c["case"] for c in reduce_motion}),
            "takes": sorted(takes),
        }
    return mapping


def curve_error(curve, response, damping, exponent, gain):
    t = np.maximum(curve["t"][None, :] - LAGS[:, None], 0.0)
    model = mapped(springfit.step_response(t, response, damping), curve["appearing"], exponent, gain)
    return float(np.min(np.mean((model - curve["alpha"][None, :]) ** 2, axis=1)))


def fit_spring(curves, exponent, gain):
    best = None
    for response in RESPONSES:
        for damping in DAMPINGS:
            error = sum(curve_error(c, response, damping, exponent, gain) for c in curves)
            if best is None or error < best[0]:
                best = (error, float(response), float(damping))
    error, response, damping = best
    return {
        "response": round(response, 2),
        "damping": round(damping, 2),
        "rms": float(np.sqrt(error / max(1, len(curves)))),
        "at_grid_edge": at_edge(response, RESPONSES) or at_edge(damping, DAMPINGS),
    }


def spring_check(curves, mapping, scene_id=DEFAULT_SCENE):
    entry = mapping[scene_id]
    exponent = entry["exponent"]["value"] if entry["exponent"] else 1.0
    gain = entry["gain"]["value"] if entry["gain"] else 1.0
    response, damping = SCENES[scene_id]

    def judged(fit):
        close = abs(fit["response"] - response) / response <= SPRING_TOLERANCE[0] + 1e-9 and abs(fit["damping"] - damping) <= SPRING_TOLERANCE[1] + 1e-9
        return {**fit, "pass": bool(close and not fit["at_grid_edge"])}

    result = {"swiftui": [response, damping], "all": judged(fit_spring(curves, exponent, gain))}
    result["cases"] = {case: judged(fit_spring([c for c in curves if c["case"] == case], exponent, gain)) for case in sorted({c["case"] for c in curves})}
    result["pass"] = result["all"]["pass"] and all(fit["pass"] for fit in result["cases"].values())
    return result


def scan(udid, cases, out, values, ramp):
    folder = Path(out) / f"ramp{ramp}"
    for name in cases:
        appearance, backdrop = case_parts(name)
        sim.appearance(udid, appearance)
        for visibility in values:
            shot = folder / name / f"{visibility}"
            if (shot / "ready.png").exists():
                continue
            record.drive(udid, build.EXAMPLE_BUNDLE, TOOL, [], backdrop, False, shot, settle=1.0, extra={"visibility": visibility, "blurRamp": ramp})
    return folder


def static_rows(scan_dir, region):
    rect = track.pixel_rect(region)
    found = {}
    for case_dir in sorted(Path(scan_dir).glob("*")):
        shots = {float(p.name): p / "ready.png" for p in case_dir.glob("*") if (p / "ready.png").exists()}
        if 0.0 not in shots or 1.0 not in shots:
            continue
        bare_px = track.crop_px(metrics.load(shots[0.0]), rect)
        full_px = track.crop_px(metrics.load(shots[1.0]), rect)
        bare, full = shapes.shrink(bare_px), shapes.shrink(full_px)
        inner = shapes.inner_slices(track.box(full_px, bare_px, track.edges(bare_px)), bare.shape)
        rows = {}
        for visibility, path in sorted(shots.items()):
            row = track.progress_row(shapes.shrink(track.crop_px(metrics.load(path), rect)), bare, full, inner)
            rows[visibility] = (row["progress"], row["sharpness"])
        found[case_dir.name] = rows
    return found


def native_sharpness(curves):
    samples = {}
    for curve in curves:
        for progress, sharpness in zip(curve["alpha"], curve["sharpness"]):
            if np.isfinite(progress) and np.isfinite(sharpness):
                samples.setdefault(curve["case"], []).append((float(progress), float(sharpness)))
    found = {}
    for case, pairs in samples.items():
        pairs = np.array(pairs)
        found[case] = {}
        for target in SHARPNESS_AT:
            near = pairs[np.abs(pairs[:, 0] - target) <= SHARPNESS_BIN]
            if len(near):
                found[case][target] = float(near[:, 1].mean())
    return found


def flutter_sharpness(rows):
    found = {}
    for case, by_visibility in rows.items():
        visibilities = sorted(by_visibility)
        progress = np.maximum.accumulate(np.array([by_visibility[v][0] for v in visibilities]))
        sharpness = np.array([by_visibility[v][1] for v in visibilities])
        found[case] = {target: float(np.interp(target, progress, sharpness)) for target in SHARPNESS_AT}
    return found


def ramp_error(native, flutter):
    differences = [flutter[case][target] - value for case, targets in native.items() if case in flutter for target, value in targets.items()]
    return float(np.sqrt(np.mean(np.square(differences)))) if differences else float("inf")


def choose_ramp(native, rows_by_ramp):
    errors = {ramp: ramp_error(native, flutter_sharpness(rows)) for ramp, rows in rows_by_ramp.items()}
    best = min(errors, key=errors.get)
    ordered = sorted(errors)
    return {"value": best, "errors": errors, "at_grid_edge": len(ordered) > 1 and best in (ordered[0], ordered[-1])}


def invert(progress_by_case, grid=GRID):
    visibilities = sorted(next(iter(progress_by_case.values())))
    mean = np.mean([[curve[v] for v in visibilities] for curve in progress_by_case.values()], axis=0)
    monotone = np.maximum.accumulate(np.clip(mean, 0.0, 1.0))
    monotone[0], monotone[-1] = 0.0, 1.0
    targets = np.linspace(0.0, 1.0, grid)
    return [round(float(v), 4) for v in np.interp(targets, monotone, visibilities)], [round(float(a), 4) for a in mean]


def table_source(mapping, ramp, table):
    lines = [f"const double ios27BlurRampExponent = {float(ramp)};", ""]
    for scene_id, name in PRESETS.items():
        entry = mapping.get(scene_id)
        if not entry:
            continue
        exponent = entry["exponent"]["value"] if entry["exponent"] else 1.0
        gain = entry["gain"]["value"] if entry["gain"] else 1.0
        reduce_motion = entry["reduce_motion_gain"]["value"] if entry.get("reduce_motion_gain") else gain
        lines.append(f"const double ios27{name}DisappearExponent = {float(exponent)};")
        lines.append(f"const double ios27{name}AppearGain = {float(gain)};")
        lines.append(f"const double ios27{name}ReduceMotionAppearGain = {float(reduce_motion)};")
    rows = ", ".join(f"{v}" for v in table)
    lines += ["", f"const List<double> ios27VisibilityForProgress = [\n  {rows},\n];"]
    return "\n".join(lines) + "\n"


def run(udid, roots, out, count=LEVELS, write=False, ramps=RAMPS):
    build.require_fresh("example")
    scenes = {s.id: s for s in manifest.load()}
    default = scenes[DEFAULT_SCENE]
    region = default.regions[default.track[0]]
    every = {scene_id: native_curves(roots, scenes[scene_id]) for scene_id in SCENES}
    curves = {scene_id: [c for c in found if normal_case(c["case"])] for scene_id, found in every.items()}
    curves = {scene_id: found for scene_id, found in curves.items() if found}
    reduce_motion = {scene_id: [c for c in found if reduce_motion_case(c["case"])] for scene_id, found in every.items()}
    mapping = fit_mapping(curves, reduce_motion)
    check = spring_check(curves[DEFAULT_SCENE], mapping)
    cases = sorted({c["case"] for c in curves[DEFAULT_SCENE]})
    native = native_sharpness([c for found in curves.values() for c in found])
    rows_by_ramp = {ramp: static_rows(scan(udid, cases, out, RAMP_LEVELS, ramp), region) for ramp in ramps}
    ramp = choose_ramp(native, rows_by_ramp)
    final = static_rows(scan(udid, cases, Path(out) / "table", levels(count), ramp["value"]), region)
    table, mean = invert({case: {v: row[0] for v, row in rows.items()} for case, rows in final.items()})
    summary = {
        "roots": [str(root) for root in roots],
        "mapping": mapping,
        "default_spring_check": check,
        "blur_ramp": ramp,
        "native_sharpness": {case: {str(k): round(v, 3) for k, v in found.items()} for case, found in native.items()},
        "flutter_sharpness": {str(r): {case: {str(k): round(v, 3) for k, v in found.items()} for case, found in flutter_sharpness(rows).items()} for r, rows in rows_by_ramp.items()},
        "flutter_sharpness_table": {case: {str(k): round(v, 3) for k, v in found.items()} for case, found in flutter_sharpness(final).items()},
        "flutter_progress": {case: {str(v): round(row[0], 4) for v, row in rows.items()} for case, rows in final.items()},
        "flutter_progress_mean": mean,
        "visibility_for_progress": table,
    }
    Path(out).mkdir(parents=True, exist_ok=True)
    Path(out, "fit.json").write_text(json.dumps(summary, indent=2))
    if write:
        TABLE.write_text(table_source(mapping, ramp["value"], table))
    return summary
```

- [ ] **Step 4: The command.** From the worktree root:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/harness/lab.py b/packages/mobile/tool/glass_lab/harness/lab.py
index 8b45133c38fb242690b10300e3d593d9927a89a4..4052a1b4c891b922653b94c01a0b1a8dd25f6581 100644
--- a/packages/mobile/tool/glass_lab/harness/lab.py
+++ b/packages/mobile/tool/glass_lab/harness/lab.py
@@ -10,6 +10,7 @@
 
 import analyze
 import build
+import fitvis
 import flip
 import manifest
 import metrics
@@ -256,6 +257,15 @@
         capture = shapes.capture(scene, app_dir, found[:2] if found else None)
         summary[app_dir.name] = shapes.summary(capture)
     print(json.dumps(summary, indent=2))
+
+
+def cmd_fitvis(args):
+    udid = sim.device()
+    out = Path(args.out) if args.out else build.OUT / "fitvis" / time.strftime("%Y%m%d-%H%M%S")
+    ramps = tuple(float(r) for r in args.ramps.split(","))
+    summary = fitvis.run(udid, [Path(r) for r in args.runs], out, args.levels, args.write, ramps)
+    print(json.dumps({k: v for k, v in summary.items() if k in ("mapping", "default_spring_check", "blur_ramp", "visibility_for_progress")}, indent=2))
+    print(out)
 
 
 A11Y_ROWS = {"reduce-transparency": "reduceTransparency", "increase-contrast": "increaseContrast"}
@@ -376,6 +386,13 @@
     e.add_argument("case_dir")
     e.add_argument("--scene", required=True)
     e.set_defaults(func=cmd_measure)
+    v = commands.add_parser("fitvis")
+    v.add_argument("runs", nargs="+")
+    v.add_argument("--levels", type=int, default=fitvis.LEVELS)
+    v.add_argument("--ramps", default=",".join(str(r) for r in fitvis.RAMPS))
+    v.add_argument("--out")
+    v.add_argument("--write", action="store_true")
+    v.set_defaults(func=cmd_fitvis)
     u = commands.add_parser("tune")
     u.add_argument("--scene", required=True)
     u.add_argument("--appearance", required=True, choices=("light", "dark"))
PATCH
```

- [ ] **Step 5: Run the new tests, then every harness test.**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py`
Expected: `Ran 13 tests` … `OK`.
Run: `python3 -m unittest discover tool/glass_lab/harness/tests`
Expected: `Ran 167 tests` … `OK`.

- [ ] **Step 6: Commit.**

```bash
git add packages/mobile/tool/glass_lab/harness
git commit -m "feat(glass-lab): fitvis fits the materialize mapping, the blur ramp and the visibility table to native

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
### Task 8: Native references N1, N2, N5, N7 and the Reduce Motion materialize runs (N6), recorded

**Files:**
- Modify: `tool/glass_lab/native/GlassLab/MaterialScenes.swift`, `tool/glass_lab/scenes.json`
- Test: `tool/glass_lab/harness/tests/test_scenes_2b.py`

**Interfaces:**
- Consumes: the marker (Task 5), `track`/`motion` in the manifest (Task 3), the native stamp (Task 6).
- Produces these scene ids (each registered literally in `MaterialScenes.swift`, so `test_lab_ids_match_the_native_registry` holds):
  - **N1** `material.interactive`: v13's content, `Color.white.opacity(0.001).frame(250×88).glassEffect(.regular.interactive())`, tracked as `glass` = `[46, 377, 310, 148]`; steps unchanged;
  - **N2** `material.press.circle58` (58 pt circle), `.138x53`, `.250x44`, `.300x120` (capsules) and `.360x200` (rect, corner 32), with `material.interactive` the six sizes 44 to 200 pt tall; one 1.0 s press on `glass` each, tracked `glass` = rest box ± 30 pt; no `motion` list (the press is judged in 2B.3);
  - **N5** `material.materialize.snappy` and `.bouncy`: `MaterializeScene(animation: .snappy/.bouncy)`, the same toggle steps;
  - the three materialize scenes track `block` = `[70, 400, 262, 104]` and are judged on the seven `progress.*` measures (spec §8 Done item 4);
  - **N7** `material.spacing.default.{a,b,c}` and `material.spacing.40.{a,b,c}`: two 80 pt circles per row, each pair in its own `GlassEffectContainer()` or `GlassEffectContainer(spacing: 40)`, rows 100 pt apart, gaps 0, 4, 8, 12 / 16, 20, 24, 32 / 40, 48, 60; still scenes on `photo`, one region `g<gap>` per pair (pair box ± 12 pt), each also a `topology` region, so a run measures native's component count and neck width per gap. On `photo` because every pair's neck sits on x = 201 pt, a stripe boundary: still screenshots are measured with the lossless detector of ruling 23 and read the same on both backdrops, but a video-frame detector cannot see through that edge if 2B.2 ever animates these scenes. Each pair has its own container so no two pairs can merge, whatever the default spacing turns out to be.

- [ ] **Step 1: Write the failing test.** Create `tool/glass_lab/harness/tests/test_scenes_2b.py`:

```python
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import manifest
import touch

MATERIALIZE = ("material.materialize", "material.materialize.snappy", "material.materialize.bouncy")
PRESS = ("material.interactive", "material.press.circle58", "material.press.138x53", "material.press.250x44", "material.press.300x120", "material.press.360x200")
SPACING = tuple(f"material.spacing.{c}.{p}" for c in ("default", "40") for p in ("a", "b", "c"))


class SceneTests(unittest.TestCase):
    def setUp(self):
        self.scenes = {s.id: s for s in manifest.load()}

    def test_materialize_scenes_track_the_block_on_progress_measures(self):
        for scene_id in MATERIALIZE:
            scene = self.scenes[scene_id]
            self.assertEqual(scene.track, ("block",))
            self.assertEqual(scene.regions["block"], [70, 400, 262, 104])
            self.assertEqual(set(scene.motion), {m for m in manifest.MOTION_MEASURES if m.startswith("progress.")})
            self.assertTrue(scene.touches)

    def test_press_scenes_hold_one_press_on_one_tracked_glass(self):
        for scene_id in PRESS:
            scene = self.scenes[scene_id]
            self.assertEqual(scene.track, ("glass",))
            self.assertTrue(any("press" in step for step in scene.steps))
            self.assertEqual(scene.motion, ())
        heights = sorted(self.scenes[s].regions["glass"][3] - 60 for s in PRESS)
        self.assertEqual(len(heights), 6)

    def test_spacing_scenes_are_still_with_one_region_per_gap(self):
        gaps = []
        for scene_id in SPACING:
            scene = self.scenes[scene_id]
            self.assertTrue(scene.rest)
            self.assertEqual(scene.backdrops, ("photo",))
            self.assertEqual(set(scene.topology), set(scene.regions))
            gaps += [int(name[1:]) for name in scene.regions]
        self.assertEqual(sorted(gaps), sorted([0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 60] * 2))

    def test_no_region_of_a_touch_scene_overlaps_the_touch_marker(self):
        for scene in manifest.load():
            if scene.touches:
                for name, rect in scene.regions.items():
                    self.assertTrue(touch.marker_free(rect), f"{scene.id} {name}")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and see it fail.**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_scenes_2b.py`
Expected: `KeyError: 'material.spacing.default.a'` and two `Tuples differ` failures (`()` against `('block',)` and `('glass',)`: the materialize and interactive scenes are not tracked yet).

- [ ] **Step 3: The native scenes.**

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift b/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift
index b209b381dc2ca02195450ffcc5a6c647009076bd..b638301a1db008b0b9d27f10bcca216043961bc5 100644
--- a/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift
+++ b/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift
@@ -8,6 +8,19 @@
         "material.interactive": { AnyView(InteractiveScene()) },
         "material.flip": { AnyView(FlipScene()) },
         "material.materialize": { AnyView(MaterializeScene()) },
+        "material.materialize.snappy": { AnyView(MaterializeScene(animation: .snappy)) },
+        "material.materialize.bouncy": { AnyView(MaterializeScene(animation: .bouncy)) },
+        "material.press.circle58": { AnyView(PressScene(width: 58, height: 58, circle: true)) },
+        "material.press.138x53": { AnyView(PressScene(width: 138, height: 53)) },
+        "material.press.250x44": { AnyView(PressScene(width: 250, height: 44)) },
+        "material.press.300x120": { AnyView(PressScene(width: 300, height: 120)) },
+        "material.press.360x200": { AnyView(PressScene(width: 360, height: 200, cornerRadius: 32)) },
+        "material.spacing.default.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: nil)) },
+        "material.spacing.default.b": { AnyView(SpacingScene(gaps: [16, 20, 24, 32], spacing: nil)) },
+        "material.spacing.default.c": { AnyView(SpacingScene(gaps: [40, 48, 60], spacing: nil)) },
+        "material.spacing.40.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 40)) },
+        "material.spacing.40.b": { AnyView(SpacingScene(gaps: [16, 20, 24, 32], spacing: 40)) },
+        "material.spacing.40.c": { AnyView(SpacingScene(gaps: [40, 48, 60], spacing: 40)) },
         "material.merge": { AnyView(MergeScene()) },
         "material.union": { AnyView(UnionScene()) },
         "material.morph": { AnyView(MorphScene()) },
@@ -66,9 +79,64 @@
     var body: some View {
         ZStack {
             Backdrop()
-            GlassBlock(width: 250, height: 88, glass: .regular.interactive())
+            Color.white.opacity(0.001)
+                .frame(width: 250, height: 88)
+                .glassEffect(.regular.interactive())
                 .accessibilityElement()
                 .accessibilityIdentifier("glass")
+        }
+    }
+}
+
+struct PressScene: View {
+    let width: CGFloat
+    let height: CGFloat
+    var circle = false
+    var cornerRadius: CGFloat?
+
+    var body: some View {
+        ZStack {
+            Backdrop()
+            Group {
+                if circle {
+                    Color.white.opacity(0.001).frame(width: width, height: height).glassEffect(.regular.interactive(), in: .circle)
+                } else if let cornerRadius {
+                    Color.white.opacity(0.001).frame(width: width, height: height).glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
+                } else {
+                    Color.white.opacity(0.001).frame(width: width, height: height).glassEffect(.regular.interactive())
+                }
+            }
+            .accessibilityElement()
+            .accessibilityIdentifier("glass")
+        }
+    }
+}
+
+struct SpacingScene: View {
+    let gaps: [CGFloat]
+    let spacing: CGFloat?
+
+    var body: some View {
+        ZStack {
+            Backdrop()
+            VStack(spacing: 100) {
+                ForEach(gaps, id: \.self) { gap in
+                    pair(gap)
+                }
+            }
+        }
+    }
+
+    @ViewBuilder
+    private func pair(_ gap: CGFloat) -> some View {
+        let circles = HStack(spacing: gap) {
+            Color.clear.frame(width: 80, height: 80).glassEffect(.regular, in: .circle)
+            Color.clear.frame(width: 80, height: 80).glassEffect(.regular, in: .circle)
+        }
+        if let spacing {
+            GlassEffectContainer(spacing: spacing) { circles }
+        } else {
+            GlassEffectContainer { circles }
         }
     }
 }
@@ -89,6 +157,7 @@
 }
 
 struct MaterializeScene: View {
+    var animation: Animation?
     @State private var shown = true
 
     var body: some View {
@@ -102,7 +171,11 @@
             VStack {
                 Spacer()
                 LabButton(title: "Toggle", id: "toggle") {
-                    withAnimation { shown.toggle() }
+                    if let animation {
+                        withAnimation(animation) { shown.toggle() }
+                    } else {
+                        withAnimation { shown.toggle() }
+                    }
                 }
                 .padding(.bottom, 120)
             }
PATCH
```

- [ ] **Step 4: The manifest.** Apply the `scenes.json` change (13 new scenes, 79 in all; `material.materialize` and `material.interactive` gain regions, tracks and the materialize motion list):

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/scenes.json b/packages/mobile/tool/glass_lab/scenes.json
index 5a815fb46d5b561177eabcf255f851e04fdfa4d0..024c209b6bf819a62ca3126d891e283a5dea56d9 100644
--- a/packages/mobile/tool/glass_lab/scenes.json
+++ b/packages/mobile/tool/glass_lab/scenes.json
@@ -141,6 +141,217 @@
       {
         "wait": 1.0
       }
+    ],
+    "regions": {
+      "glass": [
+        46,
+        377,
+        310,
+        148
+      ]
+    },
+    "track": [
+      "glass"
+    ]
+  },
+  {
+    "id": "material.press.circle58",
+    "group": "material",
+    "title": "Interactive glass press, 58 pt circle",
+    "inventory": "2.5",
+    "app": "lab",
+    "backdrops": [
+      "stripes",
+      "photo"
+    ],
+    "appearances": [
+      "light",
+      "dark"
+    ],
+    "steps": [
+      {
+        "wait": 0.5
+      },
+      {
+        "press": {
+          "at": "glass",
+          "duration": 1.0
+        }
+      },
+      {
+        "wait": 1.0
+      }
+    ],
+    "regions": {
+      "glass": [
+        142,
+        392,
+        118,
+        118
+      ]
+    },
+    "track": [
+      "glass"
+    ]
+  },
+  {
+    "id": "material.press.138x53",
+    "group": "material",
+    "title": "Interactive glass press, 138 by 53 capsule",
+    "inventory": "2.5",
+    "app": "lab",
+    "backdrops": [
+      "stripes",
+      "photo"
+    ],
+    "appearances": [
+      "light",
+      "dark"
+    ],
+    "steps": [
+      {
+        "wait": 0.5
+      },
+      {
+        "press": {
+          "at": "glass",
+          "duration": 1.0
+        }
+      },
+      {
+        "wait": 1.0
+      }
+    ],
+    "regions": {
+      "glass": [
+        102,
+        394,
+        198,
+        114
+      ]
+    },
+    "track": [
+      "glass"
+    ]
+  },
+  {
+    "id": "material.press.250x44",
+    "group": "material",
+    "title": "Interactive glass press, 250 by 44 capsule",
+    "inventory": "2.5",
+    "app": "lab",
+    "backdrops": [
+      "stripes",
+      "photo"
+    ],
+    "appearances": [
+      "light",
+      "dark"
+    ],
+    "steps": [
+      {
+        "wait": 0.5
+      },
+      {
+        "press": {
+          "at": "glass",
+          "duration": 1.0
+        }
+      },
+      {
+        "wait": 1.0
+      }
+    ],
+    "regions": {
+      "glass": [
+        46,
+        399,
+        310,
+        104
+      ]
+    },
+    "track": [
+      "glass"
+    ]
+  },
+  {
+    "id": "material.press.300x120",
+    "group": "material",
+    "title": "Interactive glass press, 300 by 120 capsule",
+    "inventory": "2.5",
+    "app": "lab",
+    "backdrops": [
+      "stripes",
+      "photo"
+    ],
+    "appearances": [
+      "light",
+      "dark"
+    ],
+    "steps": [
+      {
+        "wait": 0.5
+      },
+      {
+        "press": {
+          "at": "glass",
+          "duration": 1.0
+        }
+      },
+      {
+        "wait": 1.0
+      }
+    ],
+    "regions": {
+      "glass": [
+        21,
+        361,
+        360,
+        180
+      ]
+    },
+    "track": [
+      "glass"
+    ]
+  },
+  {
+    "id": "material.press.360x200",
+    "group": "material",
+    "title": "Interactive glass press, 360 by 200 rounded rectangle",
+    "inventory": "2.5",
+    "app": "lab",
+    "backdrops": [
+      "stripes",
+      "photo"
+    ],
+    "appearances": [
+      "light",
+      "dark"
+    ],
+    "steps": [
+      {
+        "wait": 0.5
+      },
+      {
+        "press": {
+          "at": "glass",
+          "duration": 1.0
+        }
+      },
+      {
+        "wait": 1.0
+      }
+    ],
+    "regions": {
+      "glass": [
+        1,
+        321,
+        400,
+        260
+      ]
+    },
+    "track": [
+      "glass"
     ]
   },
   {
@@ -264,6 +475,130 @@
       {
         "wait": 1.2
       }
+    ],
+    "regions": {
+      "block": [
+        70,
+        400,
+        262,
+        104
+      ]
+    },
+    "track": [
+      "block"
+    ],
+    "motion": [
+      "progress.t10_90_ms",
+      "progress.settle_ms",
+      "progress.overshoot_pct",
+      "progress.response_pct",
+      "progress.damping",
+      "progress.rms",
+      "progress.sharpness"
+    ]
+  },
+  {
+    "id": "material.materialize.snappy",
+    "group": "material",
+    "title": "Glass materializes in and out under withAnimation(.snappy)",
+    "inventory": "2.13",
+    "app": "lab",
+    "backdrops": [
+      "stripes",
+      "photo"
+    ],
+    "appearances": [
+      "light",
+      "dark"
+    ],
+    "steps": [
+      {
+        "wait": 0.5
+      },
+      {
+        "tap": "toggle"
+      },
+      {
+        "wait": 1.2
+      },
+      {
+        "tap": "toggle"
+      },
+      {
+        "wait": 1.2
+      }
+    ],
+    "regions": {
+      "block": [
+        70,
+        400,
+        262,
+        104
+      ]
+    },
+    "track": [
+      "block"
+    ],
+    "motion": [
+      "progress.t10_90_ms",
+      "progress.settle_ms",
+      "progress.overshoot_pct",
+      "progress.response_pct",
+      "progress.damping",
+      "progress.rms",
+      "progress.sharpness"
+    ]
+  },
+  {
+    "id": "material.materialize.bouncy",
+    "group": "material",
+    "title": "Glass materializes in and out under withAnimation(.bouncy)",
+    "inventory": "2.13",
+    "app": "lab",
+    "backdrops": [
+      "stripes",
+      "photo"
+    ],
+    "appearances": [
+      "light",
+      "dark"
+    ],
+    "steps": [
+      {
+        "wait": 0.5
+      },
+      {
+        "tap": "toggle"
+      },
+      {
+        "wait": 1.2
+      },
+      {
+        "tap": "toggle"
+      },
+      {
+        "wait": 1.2
+      }
+    ],
+    "regions": {
+      "block": [
+        70,
+        400,
+        262,
+        104
+      ]
+    },
+    "track": [
+      "block"
+    ],
+    "motion": [
+      "progress.t10_90_ms",
+      "progress.settle_ms",
+      "progress.overshoot_pct",
+      "progress.response_pct",
+      "progress.damping",
+      "progress.rms",
+      "progress.sharpness"
     ]
   },
   {
@@ -342,6 +677,274 @@
       {
         "wait": 1.5
       }
+    ]
+  },
+  {
+    "id": "material.spacing.default.a",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 0, 4, 8, 12 pt in the default GlassEffectContainer()",
+    "inventory": "2.14",
+    "app": "lab",
+    "backdrops": [
+      "photo"
+    ],
+    "appearances": [
+      "light",
+      "dark"
+    ],
+    "steps": [],
+    "regions": {
+      "g0": [
+        109,
+        129,
+        184,
+        104
+      ],
+      "g4": [
+        107,
+        309,
+        188,
+        104
+      ],
+      "g8": [
+        105,
+        489,
+        192,
+        104
+      ],
+      "g12": [
+        103,
+        669,
+        196,
+        104
+      ]
+    },
+    "topology": [
+      "g0",
+      "g4",
+      "g8",
+      "g12"
+    ]
+  },
+  {
+    "id": "material.spacing.default.b",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 16, 20, 24, 32 pt in the default GlassEffectContainer()",
+    "inventory": "2.14",
+    "app": "lab",
+    "backdrops": [
+      "photo"
+    ],
+    "appearances": [
+      "light",
+      "dark"
+    ],
+    "steps": [],
+    "regions": {
+      "g16": [
+        101,
+        129,
+        200,
+        104
+      ],
+      "g20": [
+        99,
+        309,
+        204,
+        104
+      ],
+      "g24": [
+        97,
+        489,
+        208,
+        104
+      ],
+      "g32": [
+        93,
+        669,
+        216,
+        104
+      ]
+    },
+    "topology": [
+      "g16",
+      "g20",
+      "g24",
+      "g32"
+    ]
+  },
+  {
+    "id": "material.spacing.default.c",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 40, 48, 60 pt in the default GlassEffectContainer()",
+    "inventory": "2.14",
+    "app": "lab",
+    "backdrops": [
+      "photo"
+    ],
+    "appearances": [
+      "light",
+      "dark"
+    ],
+    "steps": [],
+    "regions": {
+      "g40": [
+        89,
+        219,
+        224,
+        104
+      ],
+      "g48": [
+        85,
+        399,
+        232,
+        104
+      ],
+      "g60": [
+        79,
+        579,
+        244,
+        104
+      ]
+    },
+    "topology": [
+      "g40",
+      "g48",
+      "g60"
+    ]
+  },
+  {
+    "id": "material.spacing.40.a",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 0, 4, 8, 12 pt in GlassEffectContainer(spacing: 40)",
+    "inventory": "2.14",
+    "app": "lab",
+    "backdrops": [
+      "photo"
+    ],
+    "appearances": [
+      "light",
+      "dark"
+    ],
+    "steps": [],
+    "regions": {
+      "g0": [
+        109,
+        129,
+        184,
+        104
+      ],
+      "g4": [
+        107,
+        309,
+        188,
+        104
+      ],
+      "g8": [
+        105,
+        489,
+        192,
+        104
+      ],
+      "g12": [
+        103,
+        669,
+        196,
+        104
+      ]
+    },
+    "topology": [
+      "g0",
+      "g4",
+      "g8",
+      "g12"
+    ]
+  },
+  {
+    "id": "material.spacing.40.b",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 16, 20, 24, 32 pt in GlassEffectContainer(spacing: 40)",
+    "inventory": "2.14",
+    "app": "lab",
+    "backdrops": [
+      "photo"
+    ],
+    "appearances": [
+      "light",
+      "dark"
+    ],
+    "steps": [],
+    "regions": {
+      "g16": [
+        101,
+        129,
+        200,
+        104
+      ],
+      "g20": [
+        99,
+        309,
+        204,
+        104
+      ],
+      "g24": [
+        97,
+        489,
+        208,
+        104
+      ],
+      "g32": [
+        93,
+        669,
+        216,
+        104
+      ]
+    },
+    "topology": [
+      "g16",
+      "g20",
+      "g24",
+      "g32"
+    ]
+  },
+  {
+    "id": "material.spacing.40.c",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 40, 48, 60 pt in GlassEffectContainer(spacing: 40)",
+    "inventory": "2.14",
+    "app": "lab",
+    "backdrops": [
+      "photo"
+    ],
+    "appearances": [
+      "light",
+      "dark"
+    ],
+    "steps": [],
+    "regions": {
+      "g40": [
+        89,
+        219,
+        224,
+        104
+      ],
+      "g48": [
+        85,
+        399,
+        232,
+        104
+      ],
+      "g60": [
+        79,
+        579,
+        244,
+        104
+      ]
+    },
+    "topology": [
+      "g40",
+      "g48",
+      "g60"
     ]
   },
   {
PATCH
```

- [ ] **Step 5: Run the tests and the gates.**

Run: `python3 -m unittest discover tool/glass_lab/harness/tests` → `Ran 171 tests` … `OK`.
Run (example): `flutter test --no-pub` → `+10: All tests passed!` (the new ids render the missing placeholder in the example until Task 19).

- [ ] **Step 6: Build and record the native references.** One lab command at a time, each with `run_in_background`:

```bash
python3 tool/glass_lab/harness/lab.py build native
python3 tool/glass_lab/harness/lab.py run material.materialize --app native
python3 tool/glass_lab/harness/lab.py run material.materialize --app native --a11y reduce-motion
python3 tool/glass_lab/harness/lab.py run material.interactive --app native
python3 tool/glass_lab/harness/lab.py run material.press --app native
python3 tool/glass_lab/harness/lab.py run material.spacing --app native
```

`material.materialize` as a selector runs the three materialize scenes (it matches the id and every id that starts with `material.materialize.`). Write each printed run folder into the task report; Task 20 cites them.

- [ ] **Step 7: Check what was recorded.** For one case of each:

```bash
python3 tool/glass_lab/harness/lab.py measure build/glass_lab/runs/<materialize run>/material.materialize.bouncy/dark-photo --scene material.materialize.bouncy
python3 tool/glass_lab/harness/lab.py measure build/glass_lab/runs/<interactive run>/material.interactive/dark-stripes --scene material.interactive
python3 tool/glass_lab/harness/lab.py measure build/glass_lab/runs/<press run>/material.press.250x44/dark-stripes --scene material.press.250x44
```

Expected, from the prototype (runs `20261003-032332` normal, `20261003-033143` Reduce Motion, `20261003-044516` interactive, `20261003-044602` press, `20261003-044920` spacing):
- materialize, every scene and case: two touches and two events, owned by steps 1 and 3. 10–90% on `photo`: default 125–133 ms out / 275–292 ms in; `.snappy` 117–125 / 200; `.bouncy` 100–108 / 133. Reduce Motion: the same times within one frame (rulings 9, 12), but `.bouncy` overshoots more (2.8–3.8% against 1.4–2.5%);
- `material.interactive dark-stripes`: two touches (the 1.0 s press, held 0.95 s, and the press-drag, 1.31 s), six events owned by steps 1 and 3; rest 252.0 × 88.67 pt, largest 264.0 × 93.33 pt (+12.00 / +4.67, v13's numbers);
- `material.press.250x44 dark-stripes`: one touch of about 0.99 s; rest 252.0 × 44.67 pt, largest 266.33 × 47.67 pt (+14.33, ruling 2's number from the lab's own scene). The other sizes (prototype, `dark-stripes`): 58 pt circle 60.0 → 76.67, 138 × 53 140.0 → 156.0, 300 × 120 302.33 × 129.33 → 311.0 × 132.67, 360 × 200 375.33 × 218.67 → 378.0 × 222.33 (the rest boxes of the taller glass include part of their shadow);
- every spacing case: a still `ready.png` with 4 (or 3) pairs. Native topology on `dark-photo` (prototype run `20261003-050837`): the default container joins the pair at gaps 0 and 4 pt (one component, necks 25.33 and 4.00 pt) and keeps it apart from 8 pt; `spacing: 40` joins it up to 20 pt (necks 50.67, 38.33, 40.67, 34.00, 24.67, 2.00) and keeps it apart from 24 pt (ruling 23).

If `material.interactive` shows no press (max width equal to rest), its content is not v13's: open `ready.png` and check the scene source.

- [ ] **Step 8: Commit.**

```bash
git add packages/mobile/tool/glass_lab/native packages/mobile/tool/glass_lab/scenes.json packages/mobile/tool/glass_lab/harness/tests/test_scenes_2b.py
git commit -m "feat(glass-lab): native references for the press sizes, materialize under snappy and bouncy, and container spacing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: Noise floors for every 2B.1 scene and case (L8), over two sessions

**Files:**
- Modify: `tool/glass_lab/noise.json` (written by `lab.py repeat` only)

**Interfaces:**
- Consumes: `lab.py repeat --into`, `lab.py reboot` (Task 6), the scenes of Task 8.
- Produces: `noise.json` entries `{scene: {case: {measure: noise}}}` for `material.materialize`, `.snappy`, `.bouncy` (normal and `-reduce-motion` cases), `material.interactive`, the five `material.press.*` scenes and the six `material.spacing.*` scenes: motion measures where a scene moves, and the static and still-topology measures (`ready.mad`, `ready.topology.g<gap>.count`, `.neck_pt`) everywhere. Every limit those scenes are judged on becomes max(fixed threshold, 1.5 × noise) through `analyze`, stills included (spec L8, finding 10). The static repeatability check (MAD ≤ 1.0) still runs.

Five native takes per scene and case: three in session 1, then a simulator reboot, then two in session 2 appended to the same run, so the noise of each case is the worst of its ten pairs, six of them across the reboot. Time: about 40 s to record a take, and each case's analysis captures each take once (`analyze`'s cache) and then compares the ten pairs; budget about 3.5 h of recording and 2 h of analysis over the 21 scenes. Use one absolute run folder for every command:

```bash
RUN=/Users/omaraly/development/AI/Operator-2b1/packages/mobile/build/glass_lab/runs/noise-2b1
```

- [ ] **Step 1: Session 1.** One command at a time, `run_in_background`, about 40 s per take:

```bash
python3 tool/glass_lab/harness/lab.py repeat material.materialize --times 3 --into $RUN
python3 tool/glass_lab/harness/lab.py repeat material.materialize.snappy --times 3 --into $RUN
python3 tool/glass_lab/harness/lab.py repeat material.materialize.bouncy --times 3 --into $RUN
python3 tool/glass_lab/harness/lab.py repeat material.materialize --times 3 --a11y reduce-motion --into $RUN
python3 tool/glass_lab/harness/lab.py repeat material.materialize.snappy --times 3 --a11y reduce-motion --into $RUN
python3 tool/glass_lab/harness/lab.py repeat material.materialize.bouncy --times 3 --a11y reduce-motion --into $RUN
python3 tool/glass_lab/harness/lab.py repeat material.interactive --times 3 --into $RUN
for s in circle58 138x53 250x44 300x120 360x200; do python3 tool/glass_lab/harness/lab.py repeat material.press.$s --times 3 --into $RUN; done
for s in default.a default.b default.c 40.a 40.b 40.c; do python3 tool/glass_lab/harness/lab.py repeat material.spacing.$s --times 3 --into $RUN; done
```

`repeat` takes one scene at a time: `manifest.select` with a bare `material.materialize` would also match `.snappy` and `.bouncy`, but `repeat` uses only the first match.

- [ ] **Step 2: Reboot.**

```bash
python3 tool/glass_lab/harness/lab.py reboot
xcrun simctl spawn 708879DD-8B2A-4547-863F-F49EE1474D8B defaults read com.apple.Accessibility ReduceMotionEnabled
```

Expected: `rebooted 708879DD-8B2A-4547-863F-F49EE1474D8B`, then `0`.

- [ ] **Step 3: Session 2.** The same commands with `--times 2` (and the same `--into $RUN`). Each case now has takes 0–4; each `repeat` prints `<scene> <case>: 5 takes, static mad …, motion noise {…}` and rewrites that scene's entry from all five takes.

Expected: every `static mad` ≤ 1.0 (a still frame is identical between native takes; 2A measured 0.00). No `FAILED` line. The prototype recorded one session of three takes of the materialize scenes (`repeat-2b1`, not committed; ten of the twelve cases, the two `.bouncy` light cases' analysis having been cut short) and read, per case, `progress.t10_90_ms` noise 8–25 ms, `progress.settle_ms` 17–25 ms, `progress.rms` 0.007–0.019, `progress.sharpness` 0.02–0.17, `progress.response_pct` 2–21% and `progress.damping` 0.02–0.10: a native take's own fitted spring varies by more than the 5% and 0.05 limits, which is why those two measures are judged against this noise (`research/proto-2b1/noise-preview-3takes.json`). Values well outside these ranges are not wrong, but say so in the task report.

- [ ] **Step 4: Check the file.**

```bash
python3 - <<'EOF'
import json
noise = json.load(open("tool/glass_lab/noise.json"))
for scene in ("material.materialize", "material.materialize.snappy", "material.materialize.bouncy", "material.interactive",
              "material.press.circle58", "material.press.138x53", "material.press.250x44", "material.press.300x120", "material.press.360x200"):
    print(scene, sorted(noise[scene]))
for scene in ("material.spacing.default.a", "material.spacing.default.b", "material.spacing.default.c", "material.spacing.40.a", "material.spacing.40.b", "material.spacing.40.c"):
    print(scene, {case: sorted(k for k in entry if k.startswith("ready.topology.")) for case, entry in noise[scene].items()})
print([k for k in noise["tabbar.drag"] if k.startswith("event2.")])
print([(scene, case, name) for scene, entry in noise.items() if isinstance(entry, dict) for case, values in entry.items() if isinstance(values, dict) for name, value in values.items() if value != value or value == float("inf")])
EOF
```

Expected: the materialize scenes list 8 cases each (4 normal, 4 `-reduce-motion`), the press scenes 4 each; every spacing scene lists its cases with a `ready.topology.g<gap>.count` and `.neck_pt` entry for each of its pairs; `[]` for the teardown entries; `[]` for non-finite noise.

- [ ] **Step 5: Commit.**

```bash
git add packages/mobile/tool/glass_lab/noise.json
git commit -m "test(glass-lab): native noise floors for every 2B.1 scene and case, five takes over two sessions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 10: Springs and the animation API (M2, part of M9)

**Files:**
- Create: `packages/ios_liquid_glass/lib/src/motion/glass_animation.dart`, `glass_spring.dart`, `ios27_motion.dart`
- Test: `packages/ios_liquid_glass/test/motion/glass_animation_test.dart`

**Interfaces:**
- Produces (public from Task 13's export): `GlassAnimation` with `.spring({Duration duration = 500 ms, double bounce = 0})`, `.dampedSpring({required double response, required double dampingFraction})`, presets `defaultSpring` (0.55 s, damping 1), `smooth` (0.5 s, bounce 0), `snappy` (0.5 s, bounce 0.15), `bouncy` (0.5 s, bounce 0.3), `none`: SwiftUI's springs, the values `motor`'s `CupertinoMotion` uses (ruling 10); getters `response`, `dampingFraction`, `description` (a `SpringDescription` with mass 1, stiffness 4π²/response², damping ratio = damping fraction: the model `springfit.py` fits), `isNone`, and `simulate(from, to, velocity)` (`motor`'s `SpringMotion(description).createSimulation`); `withGlassAnimation(GlassAnimation, VoidCallback)`; `GlassAnimationScope(animation:, child:)`.
- Produces (internal): `resolveGlassAnimation(GlassAnimation? scope)` = pending `withGlassAnimation` → scope → `defaultSpring`; `pendingGlassAnimation`; `debugResetGlassAnimation()` (`@visibleForTesting`: the pending animation is one global value, so tests clear it in `tearDown`, finding 32); `GlassSpring` (1-D spring with `value`, `velocity`, `target`, `isMoving`, `jumpTo`, `animateTo(target, animation, now)` which samples first so a retarget keeps value and velocity, `offsetBy(delta, animation, now)` which moves a spring that rests at 0 by `delta` and springs it back keeping its velocity, `restart(value, velocity, target, animation, now)`, `sample(now)`, `copy()` and `restoreFrom(spring, now)`, which put a spring back to an earlier state); `GlassMotionValue` (an `Animation<double>` the coordinator sets each frame, so `FadeTransition` and render objects listen without a rebuild).
- `ios27_motion.dart` is a fitted table: `ios27BlurRampExponent`, `ios27{Default,Snappy,Bouncy}DisappearExponent`, `ios27{Default,Snappy,Bouncy}AppearGain`, `ios27{Default,Snappy,Bouncy}ReduceMotionAppearGain`, `ios27VisibilityForProgress`. It is written only by `lab.py fitvis --write` (Task 7). This task commits the prototype's tool output byte for byte as the seed (fit folder `build/glass_lab/fitvis/fixwave` in the prototype, from the native runs `20261003-032332`, `20261003-033143` (Reduce Motion) and `repeat-2b1`); Task 20 re-fits it from this branch's own native runs. Task 12 reads the mapping, Task 11 the blur ramp.
- `withGlassAnimation`'s animation applies to the glass changes built in the next frame and is cleared by a post-frame callback; a later call wins (spec M2 precedence). Every glass change built in that frame takes it, including one from an unrelated `setState` in the same frame, as SwiftUI's transaction does; the package README says so.

- [ ] **Step 1: Write the failing tests.** Create `packages/ios_liquid_glass/test/motion/glass_animation_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_spring.dart';
import 'package:motor/motor.dart';

void main() {
  tearDown(debugResetGlassAnimation);

  test("presets are SwiftUI's springs, the values motor's CupertinoMotion uses", () {
    double response(CupertinoMotion motion) => motion.duration.inMicroseconds / Duration.microsecondsPerSecond;
    double damping(CupertinoMotion motion) => motion.bounce > 0 ? 1 - motion.bounce : 1 / (1 + motion.bounce);
    for (final (animation, motion) in [
      (GlassAnimation.defaultSpring, const CupertinoMotion()),
      (GlassAnimation.smooth, const CupertinoMotion.smooth()),
      (GlassAnimation.snappy, const CupertinoMotion.snappy()),
      (GlassAnimation.bouncy, const CupertinoMotion.bouncy()),
    ]) {
      expect(animation.response, response(motion));
      expect(animation.dampingFraction, damping(motion));
    }
    expect((GlassAnimation.defaultSpring.response, GlassAnimation.defaultSpring.dampingFraction), (0.55, 1.0));
    expect(GlassAnimation.snappy.response, 0.5);
    expect(GlassAnimation.snappy.dampingFraction, closeTo(0.85, 1e-12));
    expect(GlassAnimation.bouncy.response, 0.5);
    expect(GlassAnimation.bouncy.dampingFraction, closeTo(0.7, 1e-12));
    const custom = GlassAnimation.dampedSpring(response: 0.3, dampingFraction: 0.75);
    expect((custom.response, custom.dampingFraction), (0.3, 0.75));
    expect(const GlassAnimation.spring(duration: Duration(milliseconds: 400), bounce: -0.5).dampingFraction, 2.0);
    expect(GlassAnimation.none.isNone, isTrue);
  });

  test('the spring is the one the lab fits: stiffness 4π²/response², damping 2ζ√k', () {
    final spring = const GlassAnimation.dampedSpring(response: 0.55, dampingFraction: 1).description;
    expect(spring.mass, 1);
    expect(spring.stiffness, closeTo(130.5, 0.1));
    expect(spring.damping, closeTo(2 * 1.0 * 11.424, 0.01));
  });

  test('a retargeted spring keeps its value and velocity', () {
    final spring = GlassSpring(0)..animateTo(100, GlassAnimation.defaultSpring, Duration.zero);
    spring.sample(const Duration(milliseconds: 80));
    final value = spring.value, velocity = spring.velocity;
    expect(velocity, greaterThan(0));
    spring.animateTo(-50, GlassAnimation.bouncy, const Duration(milliseconds: 80));
    expect(spring.value, value);
    expect(spring.velocity, velocity);
    spring.sample(const Duration(milliseconds: 88));
    expect(spring.value, greaterThan(value));
    spring.sample(const Duration(seconds: 5));
    expect(spring.value, -50);
    expect(spring.isMoving, isFalse);
  });

  test('GlassAnimation.none jumps', () {
    final spring = GlassSpring(0)..animateTo(10, GlassAnimation.none, Duration.zero);
    expect(spring.value, 10);
    expect(spring.isMoving, isFalse);
  });

  testWidgets('withGlassAnimation applies to the next frame, then the scope, then the default', (tester) async {
    GlassAnimation? seen;
    late StateSetter rebuild;
    await tester.pumpWidget(GlassAnimationScope(
      animation: GlassAnimation.snappy,
      child: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        seen = resolveGlassAnimation(GlassAnimationScope.maybeOf(context));
        return const SizedBox();
      }),
    ));
    expect(seen, GlassAnimation.snappy);
    withGlassAnimation(GlassAnimation.bouncy, () => rebuild(() {}));
    await tester.pump();
    expect(seen, GlassAnimation.bouncy);
    rebuild(() {});
    await tester.pump();
    expect(seen, GlassAnimation.snappy);
    await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
      seen = resolveGlassAnimation(GlassAnimationScope.maybeOf(context));
      return const SizedBox();
    }));
    expect(seen, GlassAnimation.defaultSpring);
  });
}
```

- [ ] **Step 2: Run them and see them fail.**

Run (from `packages/mobile/packages/ios_liquid_glass`): `flutter test --no-pub test/motion/glass_animation_test.dart`
Expected: compile error, `Error when reading 'lib/src/motion/glass_animation.dart'`.

- [ ] **Step 3: The seed table** (the prototype's `fitvis --write` output; do not edit it by hand). Create `packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart`:

```dart
const double ios27BlurRampExponent = 3.0;

const double ios27DefaultDisappearExponent = 3.1;
const double ios27DefaultAppearGain = 0.0;
const double ios27DefaultReduceMotionAppearGain = 0.0;
const double ios27SnappyDisappearExponent = 2.7;
const double ios27SnappyAppearGain = 0.0;
const double ios27SnappyReduceMotionAppearGain = 0.0;
const double ios27BouncyDisappearExponent = 2.75;
const double ios27BouncyAppearGain = 0.34;
const double ios27BouncyReduceMotionAppearGain = 0.62;

const List<double> ios27VisibilityForProgress = [
  0.0, 0.0651, 0.1297, 0.1939, 0.2549, 0.3147, 0.3716, 0.4257, 0.477, 0.5251, 0.5706, 0.6157, 0.6602, 0.7045, 0.7472, 0.7899, 0.8311, 0.8718, 0.9134, 0.9567, 1.0,
];
```

- [ ] **Step 4: The animation API.** Create `packages/ios_liquid_glass/lib/src/motion/glass_animation.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

@immutable
class GlassAnimation {
  const GlassAnimation.spring({Duration duration = const Duration(milliseconds: 500), double bounce = 0})
    : _duration = duration,
      _bounce = bounce,
      _response = null,
      _dampingFraction = null,
      isNone = false;

  const GlassAnimation.dampedSpring({required double response, required double dampingFraction})
    : _response = response,
      _dampingFraction = dampingFraction,
      _duration = null,
      _bounce = 0,
      isNone = false;

  const GlassAnimation._none() : _duration = null, _bounce = 0, _response = null, _dampingFraction = null, isNone = true;

  static const GlassAnimation defaultSpring = GlassAnimation.spring(duration: Duration(milliseconds: 550));
  static const GlassAnimation smooth = GlassAnimation.spring();
  static const GlassAnimation snappy = GlassAnimation.spring(bounce: 0.15);
  static const GlassAnimation bouncy = GlassAnimation.spring(bounce: 0.3);
  static const GlassAnimation none = GlassAnimation._none();

  final Duration? _duration;
  final double _bounce;
  final double? _response;
  final double? _dampingFraction;
  final bool isNone;

  double get response => _response ?? _duration!.inMicroseconds / Duration.microsecondsPerSecond;

  double get dampingFraction => _dampingFraction ?? (_bounce >= 0 ? 1 - _bounce : 1 / (1 + _bounce));

  SpringDescription get description => SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 4 * math.pi * math.pi / (response * response),
    ratio: dampingFraction,
  );

  Simulation simulate(double from, double to, double velocity) =>
      SpringMotion(description).createSimulation(start: from, end: to, velocity: velocity);

  @override
  bool operator ==(Object other) =>
      other is GlassAnimation &&
      other.isNone == isNone &&
      (isNone || (other.response == response && other.dampingFraction == dampingFraction));

  @override
  int get hashCode => isNone ? 0 : Object.hash(response, dampingFraction);

  @override
  String toString() => isNone ? 'GlassAnimation.none' : 'GlassAnimation(response: $response, dampingFraction: $dampingFraction)';
}

GlassAnimation? _pending;
int _generation = 0;

void withGlassAnimation(GlassAnimation animation, VoidCallback body) {
  final generation = ++_generation;
  _pending = animation;
  try {
    body();
  } finally {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (_generation == generation) _pending = null;
      })
      ..ensureVisualUpdate();
  }
}

@internal
GlassAnimation? get pendingGlassAnimation => _pending;

@visibleForTesting
void debugResetGlassAnimation() {
  _generation++;
  _pending = null;
}

@internal
GlassAnimation resolveGlassAnimation(GlassAnimation? scope) => _pending ?? scope ?? GlassAnimation.defaultSpring;

class GlassAnimationScope extends InheritedWidget {
  const GlassAnimationScope({super.key, required this.animation, required super.child});

  final GlassAnimation animation;

  static GlassAnimation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassAnimationScope>()?.animation;

  @override
  bool updateShouldNotify(GlassAnimationScope oldWidget) => oldWidget.animation != animation;
}
```

- [ ] **Step 5: The spring and the motion value.** Create `packages/ios_liquid_glass/lib/src/motion/glass_spring.dart`:

```dart
import 'package:flutter/animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:meta/meta.dart';

@internal
class GlassSpring {
  GlassSpring(double value) : _value = value, _target = value;

  double _value;
  double _velocity = 0;
  double _target;
  Simulation? _simulation;
  Duration? _start;

  double get value => _value;

  double get velocity => _velocity;

  double get target => _target;

  bool get isMoving => _simulation != null;

  void jumpTo(double value, {double velocity = 0}) {
    _value = value;
    _target = value;
    _velocity = velocity;
    _simulation = null;
  }

  void animateTo(double target, GlassAnimation animation, Duration? now) {
    if (now != null) sample(now);
    _target = target;
    if (animation.isNone) {
      jumpTo(target);
      return;
    }
    if (_value == target && _velocity == 0) {
      _simulation = null;
      return;
    }
    _simulation = animation.simulate(_value, target, _velocity);
    _start = now;
  }

  void offsetBy(double delta, GlassAnimation animation, Duration? now) {
    if (now != null) sample(now);
    restart(_value + delta, _velocity, 0, animation, now);
  }

  void restart(double value, double velocity, double target, GlassAnimation animation, Duration? now) {
    _value = value;
    _velocity = velocity;
    _simulation = null;
    animateTo(target, animation, now);
  }

  GlassSpring copy() => GlassSpring(_value)
    .._velocity = _velocity
    .._target = _target
    .._simulation = _simulation
    .._start = _start;

  void restoreFrom(GlassSpring other, Duration? now) {
    _value = other._value;
    _velocity = other._velocity;
    _target = other._target;
    _simulation = other._simulation;
    _start = other._start;
    if (now != null) sample(now);
  }

  bool sample(Duration now) {
    final simulation = _simulation;
    if (simulation == null) return false;
    final start = _start ??= now;
    final t = (now - start).inMicroseconds / Duration.microsecondsPerSecond;
    if (simulation.isDone(t)) {
      _value = _target;
      _velocity = 0;
      _simulation = null;
      return false;
    }
    _value = simulation.x(t);
    _velocity = simulation.dx(t);
    return true;
  }
}

@internal
class GlassMotionValue extends Animation<double> with AnimationEagerListenerMixin, AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  GlassMotionValue([this._value = 1]);

  double _value;

  @override
  double get value => _value;

  set value(double next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  AnimationStatus get status => AnimationStatus.forward;
}
```

- [ ] **Step 6: Run the tests and the package gates.**

Run: `flutter test --no-pub test/motion/glass_animation_test.dart` → `+5: All tests passed!`
Run: `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+72: All tests passed!`

- [ ] **Step 7: Commit.**

```bash
git add packages/mobile/packages/ios_liquid_glass/lib/src/motion packages/mobile/packages/ios_liquid_glass/test/motion
git commit -m "feat(ios_liquid_glass): GlassAnimation, withGlassAnimation, GlassAnimationScope and retargetable springs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 11: Render hooks for moving glass: an animated visibility, a drawn rect and a material source, written into render objects with no widget rebuild (M1, M3)

**Files:**
- Create: `packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart`, `lib/src/motion/glass_material_source.dart`
- Modify: `packages/ios_liquid_glass/lib/src/liquid_glass_render_scope.dart`, `lib/src/rendering/liquid_glass_layer.dart`, `lib/src/rendering/liquid_glass_render_object.dart`, `lib/src/internal/render_liquid_glass_geometry.dart`, `lib/src/liquid_glass_blend_group.dart`, `lib/src/liquid_glass.dart`, `lib/src/glass_shadow.dart`
- Test: `packages/ios_liquid_glass/test/motion/render_hooks_test.dart`

**Interfaces:**
- Consumes: `GlassMotionValue`, `ios27BlurRampExponent` (Task 10).
- Produces:
  - `GlassShapeMotion` (internal): a `Listenable` with `Rect resolve(RenderBox shape)`, the shape's drawn rect in its own local coordinates;
  - `GlassMaterialSource` (internal `ChangeNotifier`): `GlassMaterialSource({resolve, tint, side})`, `settings`, `shadows`, `side`, `configure({resolve, tint})`, `resize(side, {exact = false})` (ignores changes under half a point unless `exact`), notifying only when the material changes;
  - `LiquidGlassLayer(visibility:, settingsSource:)` (both `@internal`), carried by `LiquidGlassRenderScope`; `RenderLiquidGlassLayer`, `RenderLiquidGlassBlendGroup` and the geometry listen to both, and draw `settingsSource.settings` (when given) with the visibility applied: `visibility × max(0, v)` and blur × v^k (`ios27BlurRampExponent`, ruling 25), so an appearing spring that overshoots over-materializes by as much as it overshoots (ruling 11); the glass shadow listens to the visibility (capped at 1: a shadow cannot be more than opaque) and to `shadowSource`; the content fades through a `FadeTransition` on the same visibility. With no animation and no source the widget tree draws exactly what it drew before;
  - `LiquidGlass.grouped(motion:, shadowSource:)`, `LiquidGlass.withOwnLayer(motion:, visibility:, settingsSource:, shadowSource:)` (all `@internal`); `RenderLiquidGlass.motion`, `RenderLiquidGlass.drawnRect`: the blend group gathers the drawn rect, not the layout rect; `getPath()` follows it; content is painted translated by the drawn rect's centre offset (spec M1: content follows the glass), and hit testing stays on the layout (spec M1);
  - `resolveVisibility(settings, animation)` (internal, `liquid_glass_render_object.dart`).
- The renderer's tests run on the fake-glass path (flutter_test has no shader filter), so this task's tests drive the render objects directly; Tasks 12–17's tests and Task 20's simulator runs drive the real path.

- [ ] **Step 1: Write the failing tests.** Create `packages/ios_liquid_glass/test/motion/render_hooks_test.dart`:

```dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
import 'package:ios_liquid_glass/src/motion/glass_spring.dart';
import 'package:ios_liquid_glass/src/motion/ios27_motion.dart';
import 'package:ios_liquid_glass/src/rendering/liquid_glass_layer.dart';
import 'package:ios_liquid_glass/src/rendering/liquid_glass_render_object.dart';

class _Motion extends ChangeNotifier implements GlassShapeMotion {
  Rect drawn = const Rect.fromLTWH(-10, -5, 120, 50);

  @override
  Rect resolve(RenderBox shape) => drawn;

  void move(Rect rect) {
    drawn = rect;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a layer reads an animated visibility without being rebuilt', () async {
    final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
    final visibility = GlassMotionValue(1);
    const settings = LiquidGlassSettings(thickness: 20, blur: 6, specular: 0.4);
    final layer = RenderLiquidGlassLayer(
      renderShader: program.fragmentShader(),
      backdropKey: null,
      devicePixelRatio: 3,
      settings: settings,
      link: GeometryRenderLink(),
    )
      ..visibility = visibility
      ..attach(PipelineOwner());
    expect(layer.settings, settings);
    visibility.value = 0.25;
    expect(layer.settings.effectiveThickness, 5);
    expect(layer.settings.effectiveBlur, closeTo(6 * math.pow(0.25, ios27BlurRampExponent), 1e-9));
    expect(layer.settings.thickness, 20);
    layer.settings = settings.copyWith(blur: 8);
    expect(layer.settings.effectiveBlur, closeTo(8 * math.pow(0.25, ios27BlurRampExponent), 1e-9));
    visibility.value = 1.04;
    expect(layer.settings.effectiveThickness, closeTo(20.8, 1e-9));
    visibility.value = -0.1;
    expect(layer.settings.effectiveThickness, 0);
    expect(layer.settings.effectiveBlur, 0);
    layer.visibility = null;
    expect(layer.settings.effectiveBlur, 8);
  });

  test('settings at a visibility scale it and ramp the blur, the one formula the lab scans with', () {
    const settings = LiquidGlassSettings(thickness: 20, blur: 8);
    final half = settings.atVisibility(0.5, blurRampExponent: 3);
    expect(half.visibility, 0.5);
    expect(half.blur, closeTo(2, 1e-12));
    expect(half.effectiveBlur, closeTo(1, 1e-12));
    expect(settings.atVisibility(0.5).blur, closeTo(8 * math.pow(0.5, ios27BlurRampExponent - 1), 1e-12));
    expect(settings.atVisibility(0).blur, 0);
    expect(settings.atVisibility(-0.2).visibility, 0);
    expect(settings.atVisibility(1), settings);
  });

  test('a layer follows a material source without being rebuilt, and visibility still applies on top', () async {
    final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
    final source = GlassMaterialSource(resolve: (side) => GlassMaterial({'thickness': side / 4, 'frost': 2}), side: 44);
    final visibility = GlassMotionValue(1);
    final layer = RenderLiquidGlassLayer(
      renderShader: program.fragmentShader(),
      backdropKey: null,
      devicePixelRatio: 3,
      settings: const LiquidGlassSettings(thickness: 99),
      link: GeometryRenderLink(),
    )
      ..settingsSource = source
      ..visibility = visibility
      ..attach(PipelineOwner());
    expect(layer.settings.thickness, 11);
    source.resize(88);
    expect(layer.settings.thickness, 22);
    source.resize(88.3);
    expect(layer.settings.thickness, 22);
    source.resize(88.3, exact: true);
    expect(layer.settings.thickness, closeTo(22.075, 1e-9));
    visibility.value = 0.5;
    expect(layer.settings.effectiveThickness, closeTo(11.0375, 1e-9));
    layer.settingsSource = null;
    expect(layer.settings.thickness, 99);
  });

  test('glass paints its geometry and its path at the drawn rect, and follows it', () {
    final motion = _Motion();
    final glass = RenderLiquidGlass(shape: const LiquidRoundedRectangle(borderRadius: 10), glassContainsChild: false, blendGroupLink: null)
      ..motion = motion
      ..layout(BoxConstraints.tight(const Size(100, 40)));
    expect(glass.drawnRect, const Rect.fromLTWH(-10, -5, 120, 50));
    expect(glass.getPath().getBounds(), const Rect.fromLTWH(-10, -5, 120, 50));
    motion.move(const Rect.fromLTWH(0, 0, 60, 40));
    expect(glass.getPath().getBounds(), const Rect.fromLTWH(0, 0, 60, 40));
    glass.motion = null;
    expect(glass.drawnRect, const Rect.fromLTWH(0, 0, 100, 40));
  });
}
```

- [ ] **Step 2: Run them and see them fail.**

Run: `flutter test --no-pub test/motion/render_hooks_test.dart`
Expected: compile errors (`glass_shape_motion.dart` and `glass_material_source.dart` missing; `The setter 'visibility' isn't defined`; `The setter 'motion' isn't defined`).

- [ ] **Step 3: The motion interface and the material source.** Create `packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

@internal
abstract interface class GlassShapeMotion implements Listenable {
  Rect resolve(RenderBox shape);
}
```

and `packages/ios_liquid_glass/lib/src/motion/glass_material_source.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:ios_liquid_glass/src/liquid_glass_settings.dart';
import 'package:ios_liquid_glass/src/material/glass_material.dart';

@internal
class GlassMaterialSource extends ChangeNotifier {
  GlassMaterialSource({required GlassMaterial Function(double side) resolve, Color? tint, required double side})
    : _resolve = resolve,
      _tint = tint,
      _side = side {
    _apply(resolve(side), notify: false);
  }

  GlassMaterial Function(double side) _resolve;
  Color? _tint;
  double _side;
  late LiquidGlassSettings _settings;
  late List<BoxShadow> _shadows;

  double get side => _side;

  LiquidGlassSettings get settings => _settings;

  List<BoxShadow> get shadows => _shadows;

  void configure({required GlassMaterial Function(double side) resolve, Color? tint}) {
    _resolve = resolve;
    _tint = tint;
    _apply(resolve(_side));
  }

  void resize(double side, {bool exact = false}) {
    if (side == _side || (!exact && (side - _side).abs() < 0.5)) return;
    _side = side;
    _apply(_resolve(side));
  }

  void _apply(GlassMaterial material, {bool notify = true}) {
    final settings = material.toSettings(tint: _tint);
    final shadows = material.shadows;
    if (notify && settings == _settings && listEquals(shadows, _shadows)) return;
    _settings = settings;
    _shadows = shadows;
    if (notify) notifyListeners();
  }
}
```

- [ ] **Step 4: Visibility, drawn-rect and material plumbing.** From the worktree root:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_settings.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_settings.dart
index 969b102138962cef0fa0e1d4fab3ea261cf411ed..ff17bf68eceb537b3e5cca323df89205a884cd3f 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_settings.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_settings.dart
@@ -4,6 +4,7 @@
 import 'package:flutter/widgets.dart';
 import 'package:ios_liquid_glass/ios_liquid_glass.dart';
 import 'package:ios_liquid_glass/src/liquid_glass_render_scope.dart';
+import 'package:ios_liquid_glass/src/motion/ios27_motion.dart';
 
 /// Represents the settings for a liquid glass effect.
 class LiquidGlassSettings with Equatable {
@@ -191,6 +192,14 @@
   double get effectiveSheen => sheen * visibility;
 
   final double sheenWidth;
+
+  LiquidGlassSettings atVisibility(double visibility, {double blurRampExponent = ios27BlurRampExponent}) {
+    final value = max(0, visibility).toDouble();
+    return copyWith(
+      visibility: this.visibility * value,
+      blur: value > 0 ? blur * pow(value, blurRampExponent - 1) : 0,
+    );
+  }
 
   /// Creates a new [LiquidGlassSettings] with the given settings.
   LiquidGlassSettings copyWith({
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_render_scope.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_render_scope.dart
index 6e348931457d1d787f92ca6da09185f17bce0534..1ee254c7731219a5f13dad5cef28565847f1eddd 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_render_scope.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_render_scope.dart
@@ -1,5 +1,6 @@
 import 'package:flutter/widgets.dart';
 import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
 import 'package:meta/meta.dart';
 
 @internal
@@ -9,10 +10,16 @@
     required this.settings,
     required super.child,
     this.useFake = false,
+    this.visibility,
+    this.settingsSource,
     super.key,
   });
 
   final LiquidGlassSettings settings;
+
+  final Animation<double>? visibility;
+
+  final GlassMaterialSource? settingsSource;
 
   final bool useFake;
 
@@ -45,6 +52,8 @@
   bool updateShouldNotify(covariant InheritedWidget oldWidget) {
     return oldWidget is! LiquidGlassRenderScope ||
         oldWidget.settings != settings ||
-        oldWidget.useFake != useFake;
+        oldWidget.useFake != useFake ||
+        oldWidget.visibility != visibility ||
+        oldWidget.settingsSource != settingsSource;
   }
 }
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/rendering/liquid_glass_layer.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/rendering/liquid_glass_layer.dart
index 5f8a4aa56580e33c9e0d075cfa270c58df87d5c5..03da1dfc20345a379f9360f9e6a09c5fcac32f72 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/rendering/liquid_glass_layer.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/rendering/liquid_glass_layer.dart
@@ -10,6 +10,7 @@
 import 'package:ios_liquid_glass/src/internal/transform_tracking_repaint_boundary_mixin.dart';
 import 'package:ios_liquid_glass/src/liquid_glass_render_scope.dart';
 import 'package:ios_liquid_glass/src/logging.dart';
+import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
 import 'package:ios_liquid_glass/src/rendering/liquid_glass_render_object.dart';
 import 'package:ios_liquid_glass/src/shaders.dart';
 import 'package:meta/meta.dart';
@@ -74,8 +75,16 @@
     this.settings = const LiquidGlassSettings(),
     this.fake = false,
     this.useBackdropGroup = false,
+    @internal this.visibility,
+    @internal this.settingsSource,
     super.key,
   });
+
+  @internal
+  final Animation<double>? visibility;
+
+  @internal
+  final GlassMaterialSource? settingsSource;
 
   /// The subtree in which you should include at least one [LiquidGlass] widget.
   ///
@@ -139,6 +148,8 @@
 
       return LiquidGlassRenderScope(
         settings: widget.settings,
+        visibility: widget.visibility,
+        settingsSource: widget.settingsSource,
         useFake: true,
         child: InheritedGeometryRenderLink(
           link: _link,
@@ -150,6 +161,8 @@
     return RepaintBoundary(
       child: LiquidGlassRenderScope(
         settings: widget.settings,
+        visibility: widget.visibility,
+        settingsSource: widget.settingsSource,
         child: InheritedGeometryRenderLink(
           link: _link,
           child: ShaderBuilder(
@@ -160,6 +173,8 @@
                   ? BackdropGroup.of(context)?.backdropKey
                   : null,
               settings: widget.settings,
+              visibility: widget.visibility,
+              settingsSource: widget.settingsSource,
               link: _link,
               child: child!,
             ),
@@ -178,12 +193,16 @@
     required this.settings,
     required Widget super.child,
     required this.link,
+    this.visibility,
+    this.settingsSource,
   });
 
   final FragmentShader renderShader;
   final BackdropKey? backdropKey;
   final LiquidGlassSettings settings;
   final GeometryRenderLink link;
+  final Animation<double>? visibility;
+  final GlassMaterialSource? settingsSource;
 
   @override
   RenderObject createRenderObject(BuildContext context) {
@@ -193,7 +212,9 @@
       backdropKey: backdropKey,
       settings: settings,
       link: link,
-    );
+    )
+      ..visibility = visibility
+      ..settingsSource = settingsSource;
   }
 
   @override
@@ -205,6 +226,8 @@
       ..link = link
       ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
       ..settings = settings
+      ..visibility = visibility
+      ..settingsSource = settingsSource
       ..backdropKey = backdropKey;
   }
 }
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart
index d98ec03842d1747dad8fa918415aed211e094e16..114a23ec258c4722f84441ef78e2d68c2fc03331 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart
@@ -11,6 +11,7 @@
 import 'package:ios_liquid_glass/src/internal/render_liquid_glass_geometry.dart';
 import 'package:ios_liquid_glass/src/internal/snap_rect_to_pixels.dart';
 import 'package:ios_liquid_glass/src/logging.dart';
+import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
 import 'package:meta/meta.dart';
 
 /// A render object that can assemble [RenderLiquidGlassGeometry] shapes and
@@ -48,10 +49,35 @@
   }
 
   LiquidGlassSettings? _settings;
-  LiquidGlassSettings get settings => _settings!;
+  LiquidGlassSettings? _effective;
+  LiquidGlassSettings get settings => _effective ??= _resolveVisibility(_settingsSource?.settings ?? _settings!, _visibility);
   set settings(LiquidGlassSettings value) {
     if (_settings == value) return;
     _settings = value;
+    _visibilityChanged();
+  }
+
+  Animation<double>? _visibility;
+  Animation<double>? get visibility => _visibility;
+  set visibility(Animation<double>? value) {
+    if (_visibility == value) return;
+    if (attached) _visibility?.removeListener(_visibilityChanged);
+    _visibility = value;
+    if (attached) _visibility?.addListener(_visibilityChanged);
+    _visibilityChanged();
+  }
+
+  GlassMaterialSource? _settingsSource;
+  set settingsSource(GlassMaterialSource? value) {
+    if (_settingsSource == value) return;
+    if (attached) _settingsSource?.removeListener(_visibilityChanged);
+    _settingsSource = value;
+    if (attached) _settingsSource?.addListener(_visibilityChanged);
+    _visibilityChanged();
+  }
+
+  void _visibilityChanged() {
+    _effective = null;
     _updateShaderSettings();
     markNeedsPaint();
   }
@@ -87,11 +113,16 @@
   @mustCallSuper
   void attach(PipelineOwner owner) {
     super.attach(owner);
+    _visibility?.addListener(_visibilityChanged);
+    _settingsSource?.addListener(_visibilityChanged);
+    _effective = null;
   }
 
   @override
   @mustCallSuper
   void detach() {
+    _visibility?.removeListener(_visibilityChanged);
+    _settingsSource?.removeListener(_visibilityChanged);
     super.detach();
   }
 
@@ -378,6 +409,13 @@
   }
 }
 
+LiquidGlassSettings _resolveVisibility(LiquidGlassSettings settings, Animation<double>? visibility) =>
+    visibility == null ? settings : settings.atVisibility(visibility.value);
+
+@internal
+LiquidGlassSettings resolveVisibility(LiquidGlassSettings settings, Animation<double>? visibility) =>
+    _resolveVisibility(settings, visibility);
+
 @internal
 class GeometryRenderLink {
   final List<RenderLiquidGlassGeometry> _shapeGeometries = [];
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/internal/render_liquid_glass_geometry.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/internal/render_liquid_glass_geometry.dart
index fb0818c2300050bc70a15ec036aa8a315595be97..d21f7cb2ff14e15443323c8a6117f18cb443b518 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/internal/render_liquid_glass_geometry.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/internal/render_liquid_glass_geometry.dart
@@ -1,6 +1,7 @@
 import 'dart:ui';
 
 import 'package:equatable/equatable.dart';
+import 'package:flutter/animation.dart';
 import 'package:flutter/rendering.dart';
 import 'package:flutter_shaders/flutter_shaders.dart';
 import 'package:ios_liquid_glass/ios_liquid_glass.dart';
@@ -8,6 +9,7 @@
 import 'package:ios_liquid_glass/src/liquid_glass.dart';
 import 'package:ios_liquid_glass/src/liquid_glass_blend_group.dart';
 import 'package:ios_liquid_glass/src/logging.dart';
+import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
 import 'package:ios_liquid_glass/src/rendering/liquid_glass_render_object.dart';
 import 'package:meta/meta.dart';
 
@@ -57,21 +59,46 @@
   final FragmentShader geometryShader;
 
   LiquidGlassSettings? _settings;
+  LiquidGlassSettings? _effective;
 
   /// The settings used for liquid glass rendering.
   ///
   /// If these settings change in a way that affects geometry, the geometry
   /// will be marked as needing an update.
-  LiquidGlassSettings get settings => _settings!;
+  LiquidGlassSettings get settings => _effective ??= resolveVisibility(_settingsSource?.settings ?? _settings!, _visibility);
   set settings(LiquidGlassSettings value) {
     if (_settings == value) return;
-
-    if (value.requiresGeometryRebuild(_settings)) {
+    _settings = value;
+    _applySettings();
+  }
+
+  Animation<double>? _visibility;
+  Animation<double>? get visibility => _visibility;
+  set visibility(Animation<double>? value) {
+    if (_visibility == value) return;
+    if (attached) _visibility?.removeListener(_applySettings);
+    _visibility = value;
+    if (attached) _visibility?.addListener(_applySettings);
+    _applySettings();
+  }
+
+  GlassMaterialSource? _settingsSource;
+  set settingsSource(GlassMaterialSource? value) {
+    if (_settingsSource == value) return;
+    if (attached) _settingsSource?.removeListener(_applySettings);
+    _settingsSource = value;
+    if (attached) _settingsSource?.addListener(_applySettings);
+    _applySettings();
+  }
+
+  void _applySettings() {
+    final previous = _effective;
+    _effective = null;
+    final value = settings;
+    if (value.requiresGeometryRebuild(previous)) {
       logger.finer('$hashCode rebuild ');
       markGeometryNeedsUpdate(force: true);
     }
-
-    _settings = value;
     updateShaderWithSettings(value, _devicePixelRatio);
     markNeedsPaint();
   }
@@ -134,11 +161,16 @@
   void attach(PipelineOwner owner) {
     _renderLink?.registerGeometry(this);
     super.attach(owner);
+    _visibility?.addListener(_applySettings);
+    _settingsSource?.addListener(_applySettings);
+    _effective = null;
   }
 
   @override
   @mustCallSuper
   void detach() {
+    _visibility?.removeListener(_applySettings);
+    _settingsSource?.removeListener(_applySettings);
     _renderLink?.unregisterGeometry(this);
     super.detach();
   }
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
index d4631e640802c3e364f3f91c656c4e0a69d13fc0..0f2c886b199938a5b74a2e3b6f61b3c03be10e9d 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
@@ -5,6 +5,7 @@
 import 'package:ios_liquid_glass/src/internal/transform_tracking_repaint_boundary_mixin.dart';
 import 'package:ios_liquid_glass/src/liquid_glass.dart';
 import 'package:ios_liquid_glass/src/liquid_glass_render_scope.dart';
+import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
 import 'package:ios_liquid_glass/src/rendering/liquid_glass_render_object.dart';
 import 'package:ios_liquid_glass/src/shaders.dart';
 import 'package:meta/meta.dart';
@@ -85,6 +86,8 @@
           link: _geometryLink,
           renderLink: InheritedGeometryRenderLink.of(context)!,
           settings: LiquidGlassRenderScope.of(context).settings,
+          visibility: LiquidGlassRenderScope.of(context).visibility,
+          settingsSource: LiquidGlassRenderScope.of(context).settingsSource,
           child: child,
         ),
         assetKey: ShaderKeys.blendedGeometry,
@@ -121,6 +124,8 @@
     required this.renderLink,
     required this.link,
     required this.settings,
+    this.visibility,
+    this.settingsSource,
     super.child,
   });
 
@@ -129,6 +134,8 @@
   final GeometryRenderLink renderLink;
   final GlassGroupLink link;
   final LiquidGlassSettings settings;
+  final Animation<double>? visibility;
+  final GlassMaterialSource? settingsSource;
 
   @override
   RenderObject createRenderObject(BuildContext context) {
@@ -139,7 +146,9 @@
       settings: settings,
       link: link,
       blend: blend,
-    );
+    )
+      ..visibility = visibility
+      ..settingsSource = settingsSource;
   }
 
   @override
@@ -151,6 +160,8 @@
       ..blend = blend
       ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
       ..settings = settings
+      ..visibility = visibility
+      ..settingsSource = settingsSource
       ..link = link;
   }
 }
@@ -345,7 +356,7 @@
 
     final blendGroupRect = MatrixUtils.transformRect(
       transformToGeometry,
-      Offset.zero & renderObject.size,
+      renderObject.drawnRect,
     );
 
     return ShapeGeometry(
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass.dart
index 7d8395d2278a53337e064b3103628c245c262bff..cfbbf1d3794b88b751710888a18d156a115123be 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass.dart
@@ -9,6 +9,8 @@
 import 'package:ios_liquid_glass/src/internal/transform_tracking_repaint_boundary_mixin.dart';
 import 'package:ios_liquid_glass/src/liquid_glass_blend_group.dart';
 import 'package:ios_liquid_glass/src/liquid_glass_render_scope.dart';
+import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
+import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
 import 'package:meta/meta.dart';
 
 /// A liquid glass shape.
@@ -45,6 +47,10 @@
   })  : grouped = false,
         blendGroupLink = null,
         ownLayerConfig = null,
+        motion = null,
+        visibility = null,
+        settingsSource = null,
+        shadowSource = null,
         _auto = false;
 
   /// Creates a new [LiquidGlass] that automatically renders on a parent
@@ -69,6 +75,10 @@
   })  : grouped = true,
         blendGroupLink = null,
         ownLayerConfig = (settings, fake),
+        motion = null,
+        visibility = null,
+        settingsSource = null,
+        shadowSource = null,
         _auto = true;
 
   /// Creates a new [LiquidGlass] that is part of a [LiquidGlassBlendGroup].
@@ -84,8 +94,12 @@
     this.clipBehavior = Clip.hardEdge,
     this.blendGroupLink,
     this.shadows = const [],
+    @internal this.motion,
+    @internal this.shadowSource,
   })  : ownLayerConfig = null,
         grouped = true,
+        visibility = null,
+        settingsSource = null,
         _auto = false;
 
   /// Creates a new [LiquidGlass] that creates its own [LiquidGlassLayer].
@@ -105,6 +119,10 @@
     this.clipBehavior = Clip.hardEdge,
     this.blendGroupLink,
     this.shadows = const [],
+    @internal this.motion,
+    @internal this.visibility,
+    @internal this.settingsSource,
+    @internal this.shadowSource,
   })  : ownLayerConfig = (settings, fake),
         grouped = false,
         _auto = false;
@@ -151,6 +169,18 @@
   /// shape is cut out of the composed shadow stack so the shadow does not
   /// bleed through the translucent glass body.
   final List<BoxShadow> shadows;
+
+  @internal
+  final GlassShapeMotion? motion;
+
+  @internal
+  final Animation<double>? visibility;
+
+  @internal
+  final GlassMaterialSource? settingsSource;
+
+  @internal
+  final GlassMaterialSource? shadowSource;
 
   /// Whether this glass should automatically detect a parent layer.
   final bool _auto;
@@ -177,6 +207,8 @@
 
       return LiquidGlassLayer(
         settings: settings,
+        visibility: visibility,
+        settingsSource: settingsSource,
         child: LiquidGlassBlendGroup(
           blend: 0,
           child: Builder(
@@ -260,7 +292,8 @@
   }
 
   Widget _buildContent(BuildContext context, [GlassGroupLink? blendGroupLink]) {
-    final settings = LiquidGlassSettings.of(context);
+    final scope = LiquidGlassRenderScope.of(context);
+    final settings = scope.settings;
 
     if (!ImageFilter.isShaderFilterSupported) {
       return FakeGlass(
@@ -270,23 +303,29 @@
       );
     }
 
+    final content = Opacity(
+      opacity: settings.visibility.clamp(0, 1),
+      child: GlassGlowLayer(
+        child: child,
+      ),
+    );
+    final animated = scope.visibility;
     return GlassShadow(
       settings: settings,
       shape: shape,
       shadows: shadows,
+      visibility: animated,
+      motion: motion,
+      shadowSource: shadowSource,
       child: _RawLiquidGlass(
         blendGroupLink: blendGroupLink ?? LiquidGlassBlendGroup.of(context),
         shape: shape,
         glassContainsChild: glassContainsChild,
+        motion: motion,
         child: ClipPath(
           clipper: ShapeBorderClipper(shape: shape),
           clipBehavior: clipBehavior,
-          child: Opacity(
-            opacity: settings.visibility.clamp(0, 1),
-            child: GlassGlowLayer(
-              child: child,
-            ),
-          ),
+          child: animated == null ? content : FadeTransition(opacity: animated, child: content),
         ),
       ),
     );
@@ -299,6 +338,7 @@
     required this.shape,
     required this.glassContainsChild,
     required this.blendGroupLink,
+    this.motion,
   });
 
   final LiquidShape shape;
@@ -306,6 +346,8 @@
   final bool glassContainsChild;
 
   final GlassGroupLink? blendGroupLink;
+
+  final GlassShapeMotion? motion;
 
   @override
   RenderObject createRenderObject(BuildContext context) {
@@ -313,7 +355,7 @@
       shape: shape,
       glassContainsChild: glassContainsChild,
       blendGroupLink: blendGroupLink,
-    );
+    )..motion = motion;
   }
 
   @override
@@ -324,7 +366,8 @@
     renderObject
       ..shape = shape
       ..glassContainsChild = glassContainsChild
-      ..blendGroupLink = blendGroupLink;
+      ..blendGroupLink = blendGroupLink
+      ..motion = motion;
   }
 }
 
@@ -366,14 +409,33 @@
 
   final transformLayerHandle = LayerHandle<TransformLayer>();
 
+  GlassShapeMotion? _motion;
+  GlassShapeMotion? get motion => _motion;
+  set motion(GlassShapeMotion? value) {
+    if (_motion == value) return;
+    if (attached) _motion?.removeListener(_motionChanged);
+    _motion = value;
+    if (attached) _motion?.addListener(_motionChanged);
+    _motionChanged();
+  }
+
+  void _motionChanged() {
+    _blendGroupLink?.notifyShapeLayoutChanged(this);
+    markNeedsPaint();
+  }
+
+  Rect get drawnRect => _motion?.resolve(this) ?? Offset.zero & size;
+
   @override
   void attach(PipelineOwner owner) {
     super.attach(owner);
+    _motion?.addListener(_motionChanged);
     _registerWithLink();
   }
 
   @override
   void detach() {
+    _motion?.removeListener(_motionChanged);
     _unregisterFromParentLayer();
     transformLayerHandle.layer = null;
     super.detach();
@@ -428,10 +490,12 @@
     Offset offset,
   ) {
     if (attached) {
+      final layout = Offset.zero & size;
+      final shift = _motion == null ? Offset.zero : drawnRect.center - layout.center;
       transformLayerHandle.layer = context.pushTransform(
         needsCompositing,
         offset,
-        transform,
+        shift == Offset.zero ? transform : (Matrix4.copy(transform)..translateByDouble(shift.dx, shift.dy, 0, 1)),
         super.paint,
         oldLayer: transformLayerHandle.layer,
       );
@@ -439,6 +503,7 @@
   }
 
   Path getPath() {
-    return _lastPath;
+    if (_motion == null) return _lastPath;
+    return shape.getOuterPath(drawnRect);
   }
 }
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/glass_shadow.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/glass_shadow.dart
index f5d1e81541af72608bba3e4ec8aa8a98aaeb5a41..874cf4ccd530eb5b3aadc8e738a817b32e148aaa 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/glass_shadow.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/glass_shadow.dart
@@ -1,6 +1,8 @@
 import 'package:flutter/rendering.dart';
 import 'package:flutter/widgets.dart';
 import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
+import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
 import 'package:meta/meta.dart';
 
 /// Paints [BoxShadow]s for a [LiquidShape] using canvas primitives
@@ -17,9 +19,18 @@
     required this.shape,
     required this.shadows,
     required this.settings,
+    this.visibility,
+    this.motion,
+    this.shadowSource,
     super.child,
     super.key,
   });
+
+  final Animation<double>? visibility;
+
+  final GlassShapeMotion? motion;
+
+  final GlassMaterialSource? shadowSource;
 
   /// The shape to paint shadows for.
   final LiquidShape shape;
@@ -40,7 +51,10 @@
       shape: shape,
       shadows: shadows,
       visibility: settings.visibility,
-    );
+    )
+      ..animatedVisibility = visibility
+      ..motion = motion
+      ..shadowSource = shadowSource;
   }
 
   @override
@@ -52,7 +66,10 @@
     renderObject
       ..shape = shape
       ..shadows = shadows
-      ..visibility = settings.visibility;
+      ..visibility = settings.visibility
+      ..animatedVisibility = visibility
+      ..motion = motion
+      ..shadowSource = shadowSource;
   }
 }
 
@@ -73,7 +90,7 @@
     markNeedsPaint();
   }
 
-  List<BoxShadow> get shadows => _shadows;
+  List<BoxShadow> get shadows => _shadowSource?.shadows ?? _shadows;
   List<BoxShadow> _shadows;
   set shadows(List<BoxShadow> value) {
     if (_shadows == value) return;
@@ -81,7 +98,7 @@
     markNeedsPaint();
   }
 
-  double get visibility => _visibility;
+  double get visibility => _visibility * (_animatedVisibility?.value.clamp(0.0, 1.0) ?? 1);
   double _visibility = 1;
   set visibility(double value) {
     if (_visibility == value) return;
@@ -89,10 +106,53 @@
     markNeedsPaint();
   }
 
+  Animation<double>? _animatedVisibility;
+  set animatedVisibility(Animation<double>? value) {
+    if (_animatedVisibility == value) return;
+    if (attached) _animatedVisibility?.removeListener(markNeedsPaint);
+    _animatedVisibility = value;
+    if (attached) _animatedVisibility?.addListener(markNeedsPaint);
+    markNeedsPaint();
+  }
+
+  GlassMaterialSource? _shadowSource;
+  set shadowSource(GlassMaterialSource? value) {
+    if (_shadowSource == value) return;
+    if (attached) _shadowSource?.removeListener(markNeedsPaint);
+    _shadowSource = value;
+    if (attached) _shadowSource?.addListener(markNeedsPaint);
+    markNeedsPaint();
+  }
+
+  GlassShapeMotion? _motion;
+  set motion(GlassShapeMotion? value) {
+    if (_motion == value) return;
+    if (attached) _motion?.removeListener(markNeedsPaint);
+    _motion = value;
+    if (attached) _motion?.addListener(markNeedsPaint);
+    markNeedsPaint();
+  }
+
+  @override
+  void attach(PipelineOwner owner) {
+    super.attach(owner);
+    _animatedVisibility?.addListener(markNeedsPaint);
+    _motion?.addListener(markNeedsPaint);
+    _shadowSource?.addListener(markNeedsPaint);
+  }
+
+  @override
+  void detach() {
+    _animatedVisibility?.removeListener(markNeedsPaint);
+    _motion?.removeListener(markNeedsPaint);
+    _shadowSource?.removeListener(markNeedsPaint);
+    super.detach();
+  }
+
   @override
   void paint(PaintingContext context, Offset offset) {
-    if (shadows.isNotEmpty) {
-      final rect = offset & size;
+    if (shadows.isNotEmpty && visibility > 0) {
+      final rect = (_motion?.resolve(this) ?? Offset.zero & size).shift(offset);
       final canvas = context.canvas;
 
       final needsCutout = shadows.any((s) => s.offset != Offset.zero);
PATCH
```

- [ ] **Step 5: Run the tests and the gates.**

Run: `flutter test --no-pub test/motion/render_hooks_test.dart` → `+4: All tests passed!`
Run: `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+76: All tests passed!`
Run (from `packages/mobile`): `flutter analyze --no-pub` → `No issues found!` (Operator compiles against the changed renderer).

- [ ] **Step 6: Commit.**

```bash
git add packages/mobile/packages/ios_liquid_glass
git commit -m "feat(ios_liquid_glass): animated visibility, drawn rects and a material source reach the render objects without a rebuild

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 12: The materialize mapping and the motion coordinator (M1, M3)

**Files:**
- Create: `packages/ios_liquid_glass/lib/src/motion/glass_frame.dart`, `glass_materialize.dart`, `glass_motion_coordinator.dart`
- Test: `packages/ios_liquid_glass/test/motion/glass_materialize_test.dart`, `test/motion/glass_member_test.dart`

**Interfaces:**
- Consumes: `GlassAnimation`, `resolveGlassAnimation`, `pendingGlassAnimation`, `GlassSpring`, `GlassMotionValue`, the table (Task 10); `GlassShapeMotion`, `GlassMaterialSource` (Task 11).
- Produces (all internal):
  - the mapping: `GlassMaterialize.progress(presence, appearing:, mapping:, reduceMotion:)` = presence while appearing up to 1, then 1 + gain × (presence − 1), and min(presence, 1)^exponent while disappearing, 0 below 0; the gain is the preset's Reduce Motion gain when the glass began to appear under Reduce Motion (`GlassMaterializeMapping.reduceMotionAppearGain`, ruling 11); `GlassMaterializeMapping.of(animation)` takes the preset whose damping is nearest the animation's (ruling 9); `GlassMaterialize.visibility(progress)` interpolates `ios27VisibilityForProgress` and extends its last slope above 1 (ruling 11); `GlassMaterialize.reverse` keeps the visible progress continuous and never turns a removal into a rise or an insertion into a fall (finding 15);
  - `GlassFrame.current`: a frame counter, advanced after every frame;
  - `GlassMember` (one per glass): `visibility` (`GlassMotionValue`), the presence spring, four offset springs (`left`, `top`, `width`, `height`) that rest at 0, `presence`, `progress`, `isMoving`, `ownsLayer` (true while appearing or disappearing); `attachBox(box)`/`detachBox(box)`; `drawn` = the live layout rect of the attached box in the coordinator's space plus the offsets, read from the render tree whenever it is asked for, so a scroll or a re-composite can never leave it stale (finding 2); `drawnSize`; `resolve(box)` (the drawn rect in a shape's local coordinates); `sized(size)` (called at the box's layout) and `sync()` (called at its paint); `rebuilt()` (called by the glass widget's build); `material` (a `GlassMaterialSource` resized from the drawn size at layout and on every animated frame, spec M1); `scrollables` (the `ScrollableState`s above the glass); `reduceMotion` (set by the glass widget's build; an appear takes the value it starts with, so a switch mid-animation leaves it alone);
  - when a glass's layout changes (its size at `sized`, its position at the first read of `drawn` in a frame), the offsets absorb the change and spring back to 0 **only** if `rebuilt()` was called in that frame or the one before, the coordinator gained or lost a glass in that window, or a `withGlassAnimation` is pending; any other change is applied at once; the scroll offsets of every `Scrollable` between the glass and the space are taken out of the comparison first, so a scroll never animates (ruling 26); a member whose layout also changed in the frame drawn just before, at most `GlassMember.followGap` (50 ms) earlier, is following (`isFollowing`): its change applies at once and the previous frame's change is taken back out of the offset springs (`GlassSpring.copy`/`restoreFrom`), unless a `withGlassAnimation` is pending (ruling 32);
  - `GlassMotionCoordinator({vsync, onIdle})`: one ticker; `marker` (the render object whose parent is the space); `join({scope, animate, inserted, from, reduceMotion})` (an inserted member with `animate` appears from 0; `from` copies a member moving from another coordinator); `leave(member, {animate, owner, content, contentSize, pixelRatio}) -> bool` (with an animation, the member is left as a pending ghost at its last on-screen rect, moved by however far the `Scrollable`s above it scrolled since that rect was read (R6), with its settings, shape and shadow captured, owned by `owner` or this coordinator; it starts to disappear only when `takeGhosts` builds it); `rejoin(member)` (cancels a pending ghost, keeps every value); `reattach(member)`; `drop(member)`; `takeGhosts()` (snapshots each pending ghost's retained content layer with `toImageSync`, then releases it); `ghosts`, `hasGhosts`, `members`, `dispose()`.
- The coordinator touches the render tree only through `RenderBox`es its members are given; Task 13 gives them through widgets. Its timestamps come from the frame being drawn; a change made between frames starts at the next frame.

- [ ] **Step 1: Write the failing tests.** Create `packages/ios_liquid_glass/test/motion/glass_materialize_test.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_materialize.dart';
import 'package:ios_liquid_glass/src/motion/ios27_motion.dart';

void main() {
  const mapping = GlassMaterializeMapping(disappearExponent: 3, appearGain: 0.5);

  test('appearing glass follows its spring and overshoots by the fitted gain; disappearing glass follows the remainder to the fitted power', () {
    expect(GlassMaterialize.progress(0.4, appearing: true, mapping: mapping), 0.4);
    expect(GlassMaterialize.progress(1.08, appearing: true, mapping: mapping), closeTo(1.04, 1e-12));
    expect(GlassMaterialize.progress(-0.05, appearing: true, mapping: mapping), 0);
    expect(GlassMaterialize.progress(0.4, appearing: false, mapping: mapping), closeTo(math.pow(0.4, 3), 1e-12));
    expect(GlassMaterialize.progress(-0.05, appearing: false, mapping: mapping), 0);
    expect(GlassMaterialize.progress(1.2, appearing: false, mapping: mapping), 1);
  });

  test('under Reduce Motion an appearing glass overshoots by its own fitted gain', () {
    const both = GlassMaterializeMapping(disappearExponent: 3, appearGain: 0.3, reduceMotionAppearGain: 0.8);
    expect(GlassMaterialize.progress(1.1, appearing: true, mapping: both), closeTo(1.03, 1e-12));
    expect(GlassMaterialize.progress(1.1, appearing: true, mapping: both, reduceMotion: true), closeTo(1.08, 1e-12));
    expect(const GlassMaterializeMapping(disappearExponent: 3, appearGain: 0.3).reduceMotionAppearGain, 0.3);
    expect(GlassMaterializeMapping.bouncy.reduceMotionAppearGain, ios27BouncyReduceMotionAppearGain);
  });

  test('each preset uses its own fitted mapping, and a custom spring the preset nearest its damping', () {
    expect(GlassMaterializeMapping.of(GlassAnimation.defaultSpring), GlassMaterializeMapping.defaultSpring);
    expect(GlassMaterializeMapping.of(GlassAnimation.smooth), GlassMaterializeMapping.defaultSpring);
    expect(GlassMaterializeMapping.of(GlassAnimation.snappy), GlassMaterializeMapping.snappy);
    expect(GlassMaterializeMapping.of(GlassAnimation.bouncy), GlassMaterializeMapping.bouncy);
    expect(GlassMaterializeMapping.of(const GlassAnimation.dampedSpring(response: 0.3, dampingFraction: 0.5)), GlassMaterializeMapping.bouncy);
    expect(GlassMaterializeMapping.of(const GlassAnimation.dampedSpring(response: 0.3, dampingFraction: 0.9)), GlassMaterializeMapping.snappy);
    expect(GlassMaterializeMapping.of(const GlassAnimation.dampedSpring(response: 0.3, dampingFraction: 1.4)), GlassMaterializeMapping.defaultSpring);
    expect(GlassMaterializeMapping.defaultSpring.disappearExponent, ios27DefaultDisappearExponent);
    expect(GlassMaterializeMapping.snappy.appearGain, ios27SnappyAppearGain);
    expect(GlassMaterializeMapping.bouncy.disappearExponent, ios27BouncyDisappearExponent);
  });

  test('visibility interpolates the fitted table, stays at 0 below it and extends its last slope above 1', () {
    const table = [0.0, 0.2, 1.0];
    expect(GlassMaterialize.visibility(0, table: table), 0);
    expect(GlassMaterialize.visibility(0.25, table: table), closeTo(0.1, 1e-12));
    expect(GlassMaterialize.visibility(0.75, table: table), closeTo(0.6, 1e-12));
    expect(GlassMaterialize.visibility(1, table: table), 1);
    expect(GlassMaterialize.visibility(1.05, table: table), closeTo(1.08, 1e-12));
    expect(GlassMaterialize.visibility(-1, table: table), 0);
    expect(ios27VisibilityForProgress.first, 0);
    expect(ios27VisibilityForProgress.last, 1);
    for (var i = 1; i < ios27VisibilityForProgress.length; i++) {
      expect(ios27VisibilityForProgress[i], greaterThanOrEqualTo(ios27VisibilityForProgress[i - 1]));
    }
  });

  test('reversing keeps the visible progress, and a falling rate stays continuous', () {
    for (final (presence, velocity) in [(0.6, -2.0), (0.3, -1.5), (0.9, -0.4)]) {
      final before = GlassMaterialize.progress(presence, appearing: true, mapping: mapping);
      final (next, nextVelocity) = GlassMaterialize.reverse(presence, velocity, toAppearing: false, from: mapping, to: mapping);
      expect(GlassMaterialize.progress(next, appearing: false, mapping: mapping), closeTo(before, 1e-9));
      final rate = 3 * math.pow(next, 2) * nextVelocity;
      expect(rate, closeTo(velocity, 1e-9));
    }
    for (final (presence, velocity) in [(0.6, 2.0), (0.3, 1.5)]) {
      final before = GlassMaterialize.progress(presence, appearing: false, mapping: mapping);
      final (next, nextVelocity) = GlassMaterialize.reverse(presence, velocity, toAppearing: true, from: mapping, to: mapping);
      expect(GlassMaterialize.progress(next, appearing: true, mapping: mapping), closeTo(before, 1e-9));
      expect(nextVelocity, closeTo(3 * math.pow(presence, 2) * velocity, 1e-9));
    }
  });

  test('a removal never reverses into a rise, and an insertion never into a fall, however early', () {
    for (final presence in [0.0035, 0.05, 0.4, 1.03]) {
      final (_, removed) = GlassMaterialize.reverse(presence, 6, toAppearing: false, from: mapping, to: mapping);
      expect(removed, lessThanOrEqualTo(0));
      final (_, inserted) = GlassMaterialize.reverse(presence, -6, toAppearing: true, from: mapping, to: mapping);
      expect(inserted, greaterThanOrEqualTo(0));
    }
  });
}
```

and `packages/ios_liquid_glass/test/motion/glass_member_test.dart` (render boxes laid out by hand, no widgets):

```dart
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_materialize.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/ios27_motion.dart';

class _Tripwire extends RenderProxyBox {
  _Tripwire({RenderBox? child}) : super(child);

  bool armed = false;

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    if (armed) throw StateError('a transform was read');
    super.applyPaintTransform(child, transform);
  }
}

class _Space {
  _Space(GlassMotionCoordinator coordinator) {
    box = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(const Size(100, 40)));
    holder = RenderPositionedBox(alignment: Alignment.topLeft, child: box);
    tripwire = _Tripwire(child: holder);
    root = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(const Size(400, 400)), child: tripwire);
    owner.rootNode = root;
    root.layout(const BoxConstraints());
    coordinator.marker = holder;
    lay();
  }

  late final RenderConstrainedBox box;
  late final RenderPositionedBox holder;
  late final _Tripwire tripwire;
  late final RenderConstrainedBox root;
  final PipelineOwner owner = PipelineOwner();

  void lay({Size size = const Size(100, 40), Alignment alignment = Alignment.topLeft}) {
    box.additionalConstraints = BoxConstraints.tight(size);
    holder.alignment = alignment;
    owner.flushLayout();
  }
}

void main() {
  tearDown(debugResetGlassAnimation);

  testWidgets('an inserted member appears from 0 along its spring and settles at full visibility', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final member = coordinator.join(inserted: true);
    expect(member.presence, GlassPresence.appearing);
    expect(member.visibility.value, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(member.visibility.value, inExclusiveRange(0, 1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 16));
    expect(member.presence, GlassPresence.present);
    expect(member.visibility.value, 1);
    expect(member.isMoving, isFalse);
  });

  testWidgets('a member inserted under Reduce Motion overshoots by the Reduce Motion gain of its preset', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final normal = coordinator.join(inserted: true, scope: GlassAnimation.bouncy);
    final reduced = coordinator.join(inserted: true, scope: GlassAnimation.bouncy, reduceMotion: true);
    await tester.pump();
    var peak = (normal: 0.0, reduced: 0.0);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      peak = (normal: math.max(peak.normal, normal.progress), reduced: math.max(peak.reduced, reduced.progress));
    }
    final overshoot = peak.normal - 1;
    expect(overshoot, greaterThan(0));
    expect(peak.reduced - 1, closeTo(overshoot * ios27BouncyReduceMotionAppearGain / ios27BouncyAppearGain, 1e-3));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 16));
  });

  testWidgets('a member that was not inserted, or joins under GlassAnimation.none, is present at once', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    expect(coordinator.join().presence, GlassPresence.present);
    expect(coordinator.join(inserted: true, scope: GlassAnimation.none).presence, GlassPresence.present);
    expect(coordinator.join(inserted: true, animate: false).presence, GlassPresence.present);
  });

  testWidgets('a leaving member becomes a ghost at its last on-screen rect, fades to the mapped power and is dropped', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final space = _Space(coordinator);
    final member = coordinator.join()
      ..attachBox(space.box)
      ..shape = const LiquidRoundedRectangle(borderRadius: 20)
      ..sharedSettings = const LiquidGlassSettings();
    member.sized(space.box.size);
    expect(member.drawn, const Rect.fromLTWH(0, 0, 100, 40));
    expect(coordinator.leave(member, animate: true), isTrue);
    expect(coordinator.ghosts, isEmpty);
    final ghost = coordinator.takeGhosts().single;
    expect(ghost.rect, const Rect.fromLTWH(0, 0, 100, 40));
    expect(ghost.snapshot, isNull);
    expect(member.presence, GlassPresence.disappearing);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final presence = member.progress;
    expect(presence, inExclusiveRange(0, 1));
    expect(member.visibility.value, closeTo(GlassMaterialize.visibility(presence), 1e-12));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 16));
    expect(coordinator.ghosts, isEmpty);
  });

  testWidgets('leaving reads no transform, so a removal during build never touches an ancestor that is not laid out yet', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final space = _Space(coordinator);
    space.lay(alignment: Alignment.center);
    final member = coordinator.join()
      ..attachBox(space.box)
      ..shape = const LiquidRoundedRectangle(borderRadius: 20)
      ..sharedSettings = const LiquidGlassSettings();
    member.sized(space.box.size);
    expect(member.drawn, const Rect.fromLTWH(150, 180, 100, 40));
    space.tripwire.armed = true;
    expect(coordinator.leave(member, animate: true), isTrue);
    expect(coordinator.takeGhosts().single.rect, const Rect.fromLTWH(150, 180, 100, 40));
    space.tripwire.armed = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 16));
  });

  testWidgets('a member that leaves and rejoins in the same frame keeps its state and leaves no ghost', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final space = _Space(coordinator);
    final member = coordinator.join()
      ..attachBox(space.box)
      ..shape = const LiquidRoundedRectangle(borderRadius: 20)
      ..sharedSettings = const LiquidGlassSettings();
    member.sized(space.box.size);
    member.drawn;
    expect(coordinator.leave(member, animate: true), isTrue);
    coordinator.rejoin(member);
    expect(coordinator.takeGhosts(), isEmpty);
    expect(member.presence, GlassPresence.present);
    expect(coordinator.members, contains(member));
  });

  testWidgets('a member that was never drawn, or leaves without an animation, leaves no ghost', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final undrawn = coordinator.join()..shape = const LiquidRoundedRectangle(borderRadius: 20);
    expect(coordinator.leave(undrawn, animate: true), isFalse);
    final space = _Space(coordinator);
    final member = coordinator.join()
      ..attachBox(space.box)
      ..shape = const LiquidRoundedRectangle(borderRadius: 20)
      ..sharedSettings = const LiquidGlassSettings();
    member.sized(space.box.size);
    expect(coordinator.leave(member, animate: false), isFalse);
    expect(coordinator.takeGhosts(), isEmpty);
    expect(coordinator.leave(member, animate: true), isFalse);
  });

  testWidgets('a layout change after a rebuild springs the drawn rect from where it was; without one it jumps', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final space = _Space(coordinator);
    final member = coordinator.join()..attachBox(space.box);
    member.sized(space.box.size);
    expect(member.drawn, const Rect.fromLTWH(0, 0, 100, 40));
    member.rebuilt();
    space.lay(size: const Size(200, 40), alignment: Alignment.center);
    member.sized(space.box.size);
    expect(member.drawn, const Rect.fromLTWH(0, 0, 100, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = member.drawn!;
    expect(mid.width, inExclusiveRange(100, 200));
    expect(mid.left, inExclusiveRange(0, 100));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 16));
    expect(member.drawn, const Rect.fromLTWH(100, 180, 200, 40));
    space.lay(size: const Size(200, 40));
    member.sized(space.box.size);
    expect(member.drawn, const Rect.fromLTWH(0, 0, 200, 40));
    expect(member.isMoving, isFalse);
  });

  testWidgets('reversing a removal mid-appear keeps the visible progress and never rises', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final space = _Space(coordinator);
    final member = coordinator.join(inserted: true)
      ..attachBox(space.box)
      ..shape = const LiquidRoundedRectangle(borderRadius: 20)
      ..sharedSettings = const LiquidGlassSettings();
    member.sized(space.box.size);
    expect(member.drawn, const Rect.fromLTWH(0, 0, 100, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final before = member.progress;
    coordinator.leave(member, animate: true);
    coordinator.takeGhosts();
    expect(member.progress, closeTo(before, 1e-9));
    var last = member.progress;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      if (coordinator.ghosts.isEmpty) break;
      expect(member.progress, lessThanOrEqualTo(last + 1e-12));
      last = member.progress;
    }
    expect(math.min(last, 1), lessThan(before));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 16));
    expect(coordinator.ghosts, isEmpty);
  });
}
```

- [ ] **Step 2: Run them and see them fail.**

Run: `flutter test --no-pub test/motion/glass_materialize_test.dart test/motion/glass_member_test.dart`
Expected: compile errors (`glass_materialize.dart` and `glass_motion_coordinator.dart` missing).

- [ ] **Step 3: The frame counter and the mapping.** Create `packages/ios_liquid_glass/lib/src/motion/glass_frame.dart`:

```dart
import 'package:flutter/scheduler.dart';
import 'package:meta/meta.dart';

@internal
sealed class GlassFrame {
  static int _count = 0;
  static SchedulerBinding? _binding;

  static int get current {
    final binding = SchedulerBinding.instance;
    if (!identical(binding, _binding)) {
      _binding = binding;
      binding.addPersistentFrameCallback((_) => _count++);
    }
    return _count;
  }
}
```

and `packages/ios_liquid_glass/lib/src/motion/glass_materialize.dart`:

```dart
import 'dart:math' as math;

import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/ios27_motion.dart';
import 'package:meta/meta.dart';

@internal
@immutable
class GlassMaterializeMapping {
  const GlassMaterializeMapping({required this.disappearExponent, required this.appearGain, double? reduceMotionAppearGain})
    : reduceMotionAppearGain = reduceMotionAppearGain ?? appearGain;

  static const GlassMaterializeMapping defaultSpring = GlassMaterializeMapping(
    disappearExponent: ios27DefaultDisappearExponent,
    appearGain: ios27DefaultAppearGain,
    reduceMotionAppearGain: ios27DefaultReduceMotionAppearGain,
  );
  static const GlassMaterializeMapping snappy = GlassMaterializeMapping(
    disappearExponent: ios27SnappyDisappearExponent,
    appearGain: ios27SnappyAppearGain,
    reduceMotionAppearGain: ios27SnappyReduceMotionAppearGain,
  );
  static const GlassMaterializeMapping bouncy = GlassMaterializeMapping(
    disappearExponent: ios27BouncyDisappearExponent,
    appearGain: ios27BouncyAppearGain,
    reduceMotionAppearGain: ios27BouncyReduceMotionAppearGain,
  );

  final double disappearExponent;
  final double appearGain;
  final double reduceMotionAppearGain;

  double gain({required bool reduceMotion}) => reduceMotion ? reduceMotionAppearGain : appearGain;

  static GlassMaterializeMapping of(GlassAnimation animation) {
    final presets = [
      (GlassAnimation.defaultSpring.dampingFraction, defaultSpring),
      (GlassAnimation.snappy.dampingFraction, snappy),
      (GlassAnimation.bouncy.dampingFraction, bouncy),
    ];
    var chosen = presets.first;
    for (final preset in presets.skip(1)) {
      if ((animation.dampingFraction - preset.$1).abs() < (animation.dampingFraction - chosen.$1).abs()) chosen = preset;
    }
    return chosen.$2;
  }
}

@internal
sealed class GlassMaterialize {
  static double progress(
    double presence, {
    required bool appearing,
    GlassMaterializeMapping mapping = GlassMaterializeMapping.defaultSpring,
    bool reduceMotion = false,
  }) {
    if (presence <= 0) return 0;
    if (!appearing) return math.pow(math.min(presence, 1.0), mapping.disappearExponent).toDouble();
    return presence <= 1 ? presence : 1 + mapping.gain(reduceMotion: reduceMotion) * (presence - 1);
  }

  static double visibility(double progress, {List<double> table = ios27VisibilityForProgress}) {
    final last = table.length - 1;
    if (progress <= 0) return table.first;
    if (progress >= 1) return table[last] + (table[last] - table[last - 1]) * last * (progress - 1);
    final p = progress * last;
    final low = p.floor();
    return table[low] + (table[low + 1] - table[low]) * (p - low);
  }

  static (double, double) reverse(
    double presence,
    double velocity, {
    required bool toAppearing,
    GlassMaterializeMapping from = GlassMaterializeMapping.defaultSpring,
    GlassMaterializeMapping to = GlassMaterializeMapping.defaultSpring,
    bool reduceMotion = false,
  }) {
    if (toAppearing) {
      final p = presence.clamp(0.0, 1.0);
      final alpha = math.pow(p, from.disappearExponent).toDouble();
      final rate = from.disappearExponent * math.pow(p, from.disappearExponent - 1).toDouble() * velocity;
      return (alpha, math.max(0, rate));
    }
    final alpha = progress(presence, appearing: true, mapping: from, reduceMotion: reduceMotion).clamp(0.0, 1.0);
    if (alpha <= 0) return (0, 0);
    final rate = velocity * (presence > 1 ? from.gain(reduceMotion: reduceMotion) : 1);
    final root = math.pow(alpha, 1 / to.disappearExponent).toDouble();
    return (root, math.min(0, rate / (to.disappearExponent * math.pow(root, to.disappearExponent - 1).toDouble())));
  }
}
```

- [ ] **Step 4: The coordinator.** Create `packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart`:

```dart
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/liquid_glass_settings.dart';
import 'package:ios_liquid_glass/src/liquid_shape.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_frame.dart';
import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
import 'package:ios_liquid_glass/src/motion/glass_materialize.dart';
import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
import 'package:ios_liquid_glass/src/motion/glass_spring.dart';
import 'package:meta/meta.dart';

@internal
enum GlassPresence { appearing, present, disappearing }

@internal
class GlassMember extends ChangeNotifier implements GlassShapeMotion {
  GlassMember(this.coordinator);

  final GlassMotionCoordinator coordinator;
  final GlassMotionValue visibility = GlassMotionValue();
  final GlassSpring _presence = GlassSpring(1);
  final List<GlassSpring> _offset = [for (var i = 0; i < 4; i++) GlassSpring(0)];
  GlassPresence presence = GlassPresence.present;
  GlassMaterializeMapping _mapping = GlassMaterializeMapping.defaultSpring;
  bool reduceMotion = false;
  bool _reduceMotionAtStart = false;
  GlassAnimation? scopeAnimation;
  bool animatesTransitions = true;
  LiquidShape? shape;
  LiquidGlassSettings? sharedSettings;
  GlassMaterialSource? material;
  List<ScrollableState> scrollables = const [];
  VoidCallback? onSettled;
  RenderBox? _box;
  Size? _size;
  Offset? _anchor;
  Offset? _live;
  Offset? _spaceOrigin;
  Offset _shiftAtRead = Offset.zero;
  int _originFrame = -1;
  int _animateUntil = -1;
  int _changeFrame = -2;
  Duration? _changeTime;
  bool _following = false;
  List<GlassSpring>? _held;
  int _heldFrame = -2;
  GlassAnimation? _requested;
  GlassMotionCoordinator? _ghostOwner;

  LiquidGlassSettings? get settings => sharedSettings ?? material?.settings;

  bool get isMoving => _presence.isMoving || _offset.any((spring) => spring.isMoving);

  bool get ownsLayer => presence != GlassPresence.present;

  double get progress => GlassMaterialize.progress(
    _presence.value,
    appearing: presence != GlassPresence.disappearing,
    mapping: _mapping,
    reduceMotion: _reduceMotionAtStart,
  );

  Size? get drawnSize {
    final size = _size;
    return size == null ? null : Size(size.width + _offset[2].value, size.height + _offset[3].value);
  }

  Rect? get drawn {
    _sync();
    return _lastDrawn;
  }

  Rect? get _lastDrawn {
    final live = _live, size = drawnSize;
    if (live == null || size == null) return null;
    return Rect.fromLTWH(live.dx + _offset[0].value, live.dy + _offset[1].value, size.width, size.height);
  }

  void attachBox(RenderBox box) => _box = box;

  void detachBox(RenderBox box) {
    if (identical(_box, box)) _box = null;
  }

  void rebuilt() {
    _animateUntil = GlassFrame.current + 1;
    _requested = resolveGlassAnimation(scopeAnimation);
  }

  bool get isFollowing => _following && _changeFrame >= GlassFrame.current - 1;

  GlassAnimation? _animationNow() {
    final frame = GlassFrame.current;
    var chosen = pendingGlassAnimation;
    if (chosen == null && frame <= _animateUntil) chosen = _requested;
    if (chosen == null && frame <= coordinator._structureUntil) chosen = coordinator._structureAnimation;
    return chosen == null || chosen.isNone ? null : chosen;
  }

  static const Duration followGap = Duration(milliseconds: 50);

  GlassAnimation? _changed() {
    final frame = GlassFrame.current;
    if (_changeFrame != frame) {
      final now = coordinator._now, last = _changeTime;
      _following = _changeFrame == frame - 1 && now != null && last != null && now - last <= followGap;
      _changeFrame = frame;
      _changeTime = now;
    }
    final pending = pendingGlassAnimation;
    if (pending != null) return pending.isNone ? null : pending;
    if (_following) {
      _letGo(frame);
      return null;
    }
    final animation = _animationNow();
    if (animation != null && _heldFrame != frame) {
      _held = [for (final spring in _offset) spring.copy()];
      _heldFrame = frame;
    }
    return animation;
  }

  void _letGo(int frame) {
    final held = _held;
    _held = null;
    if (held == null || _heldFrame != frame - 1) return;
    final now = coordinator._now;
    for (var i = 0; i < _offset.length; i++) {
      _offset[i].restoreFrom(held[i], now);
    }
    coordinator._start();
  }

  void sized(Size size) {
    final previous = _size;
    _size = size;
    if (previous != null && previous != size) {
      final animation = _changed();
      if (animation != null) {
        final now = coordinator._now;
        _offset[2].offsetBy(previous.width - size.width, animation, now);
        _offset[3].offsetBy(previous.height - size.height, animation, now);
        coordinator._start();
      }
    }
    _resizeMaterial();
  }

  void sync() => _sync();

  void _sync() {
    final box = _box;
    final space = coordinator.space;
    if (box == null || space == null || !box.attached || !space.attached || !box.hasSize) return;
    final live = MatrixUtils.transformPoint(box.getTransformTo(space), Offset.zero);
    final anchor = live - _scrollShift(space);
    _live = live;
    final frame = GlassFrame.current;
    if (_originFrame != frame) {
      _originFrame = frame;
      _spaceOrigin = MatrixUtils.transformPoint(space.getTransformTo(null), Offset.zero);
      _shiftAtRead = _scrollShift(null);
    }
    final previous = _anchor;
    _anchor = anchor;
    if (previous == null || previous == anchor) return;
    final animation = _changed();
    if (animation == null) return;
    final now = coordinator._now;
    _offset[0].offsetBy(previous.dx - anchor.dx, animation, now);
    _offset[1].offsetBy(previous.dy - anchor.dy, animation, now);
    coordinator._start();
  }

  Offset _scrollShift(RenderObject? space) {
    var shift = Offset.zero;
    for (final scrollable in scrollables) {
      if (!scrollable.mounted) break;
      if (space != null) {
        final render = scrollable.context.findRenderObject();
        if (render == null || !_inside(render, space)) break;
      }
      final position = scrollable.position;
      if (!position.hasPixels) continue;
      final pixels = position.pixels;
      shift += switch (scrollable.axisDirection) {
        AxisDirection.down => Offset(0, -pixels),
        AxisDirection.up => Offset(0, pixels),
        AxisDirection.right => Offset(-pixels, 0),
        AxisDirection.left => Offset(pixels, 0),
      };
    }
    return shift;
  }

  static bool _inside(RenderObject render, RenderObject space) {
    for (var node = render.parent; node != null; node = node.parent) {
      if (identical(node, space)) return true;
    }
    return false;
  }

  @override
  Rect resolve(RenderBox shape) {
    final local = Offset.zero & shape.size;
    final current = drawn;
    final space = coordinator.space;
    if (current == null || space == null || !shape.attached || !space.attached) return local;
    return current.shift(-MatrixUtils.transformPoint(shape.getTransformTo(space), Offset.zero));
  }

  void _adopt(GlassMember other) {
    presence = other.presence;
    _mapping = other._mapping;
    _reduceMotionAtStart = other._reduceMotionAtStart;
    _presence.jumpTo(other._presence.value, velocity: other._presence.velocity);
    if (other._presence.isMoving) {
      _presence.restart(other._presence.value, other._presence.velocity, other._presence.target, resolveGlassAnimation(scopeAnimation), coordinator._now);
      coordinator._start();
    }
    _publish();
  }

  void _appear(GlassAnimation animation, Duration? now) {
    final mapping = GlassMaterializeMapping.of(animation);
    if (presence == GlassPresence.disappearing) {
      final (value, velocity) = GlassMaterialize.reverse(_presence.value, _presence.velocity, toAppearing: true, from: _mapping, to: mapping);
      _presence.restart(value, velocity, 1, animation, now);
    } else {
      _presence.restart(0, 0, 1, animation, now);
    }
    _mapping = mapping;
    _reduceMotionAtStart = reduceMotion;
    presence = GlassPresence.appearing;
    _publish();
  }

  void _disappear(GlassAnimation animation, Duration? now) {
    final mapping = GlassMaterializeMapping.of(animation);
    if (presence == GlassPresence.appearing) {
      final (value, velocity) = GlassMaterialize.reverse(
        _presence.value,
        _presence.velocity,
        toAppearing: false,
        from: _mapping,
        to: mapping,
        reduceMotion: _reduceMotionAtStart,
      );
      _presence.restart(value, velocity, 0, animation, now);
    } else {
      _presence.restart(1, 0, 0, animation, now);
    }
    _mapping = mapping;
    presence = GlassPresence.disappearing;
    _publish();
  }

  bool _sample(Duration now) {
    var moving = _presence.sample(now);
    for (final spring in _offset) {
      moving = spring.sample(now) || moving;
    }
    _publish();
    if (!_presence.isMoving && presence == GlassPresence.appearing) {
      presence = GlassPresence.present;
      onSettled?.call();
    }
    return moving;
  }

  void _publish() {
    visibility.value = GlassMaterialize.visibility(progress);
    _resizeMaterial();
    notifyListeners();
  }

  void _resizeMaterial() {
    final size = drawnSize;
    if (size != null) material?.resize(size.shortestSide, exact: !_offset.any((spring) => spring.isMoving));
  }

  @override
  void dispose() {
    visibility.dispose();
    super.dispose();
  }
}

@internal
class GlassGhost {
  GlassGhost({
    required this.member,
    required this.rect,
    required this.snapshot,
    required this.pixelRatio,
    required this.settings,
    required this.shape,
    required this.shadows,
  });

  final GlassMember member;
  final Rect rect;
  final ui.Image? snapshot;
  final double pixelRatio;
  final LiquidGlassSettings settings;
  final LiquidShape shape;
  final List<BoxShadow> shadows;

  void dispose() {
    snapshot?.dispose();
    member.dispose();
  }
}

class _Leaving {
  _Leaving({
    required this.animation,
    required this.rect,
    required this.settings,
    required this.shape,
    required this.shadows,
    required this.content,
    required this.contentSize,
    required this.pixelRatio,
  });

  final GlassAnimation animation;
  final Rect rect;
  final LiquidGlassSettings settings;
  final LiquidShape shape;
  final List<BoxShadow> shadows;
  final LayerHandle<OffsetLayer>? content;
  final Size? contentSize;
  final double pixelRatio;

  ui.Image? snapshot() {
    final layer = content?.layer;
    final size = contentSize;
    if (layer == null || size == null || size.isEmpty) return null;
    return layer.toImageSync(Offset.zero & size, pixelRatio: pixelRatio);
  }

  void release() => content?.layer = null;
}

@internal
class GlassMotionCoordinator {
  GlassMotionCoordinator({required TickerProvider vsync, this.onIdle}) {
    _ticker = vsync.createTicker(_tick);
  }

  final VoidCallback? onIdle;
  late final Ticker _ticker;
  final Set<GlassMember> _members = {};
  final List<GlassGhost> ghosts = [];
  final Map<GlassMember, _Leaving> _leaving = {};
  RenderObject? marker;
  Element? _ghostHost;
  bool _disposed = false;
  int _structureUntil = -1;
  GlassAnimation? _structureAnimation;

  Iterable<GlassMember> get members => _members;

  bool get hasGhosts => ghosts.isNotEmpty || _leaving.isNotEmpty;

  RenderObject? get space => marker?.parent ?? marker;

  Duration? get _now {
    final binding = SchedulerBinding.instance;
    return binding.schedulerPhase == SchedulerPhase.idle ? null : binding.currentFrameTimeStamp;
  }

  GlassMember join({GlassAnimation? scope, bool animate = true, bool inserted = false, GlassMember? from, bool reduceMotion = false}) {
    final member = GlassMember(this)
      ..scopeAnimation = scope
      ..animatesTransitions = animate
      ..reduceMotion = reduceMotion;
    _members.add(member);
    if (from != null) {
      member._adopt(from);
      return member;
    }
    final animation = resolveGlassAnimation(scope);
    if (inserted && animate && !animation.isNone) {
      member._appear(animation, _now);
      _structureChanged(animation);
      _start();
    }
    return member;
  }

  bool leave(
    GlassMember member, {
    required bool animate,
    GlassMotionCoordinator? owner,
    LayerHandle<OffsetLayer>? content,
    Size? contentSize,
    double pixelRatio = 1,
  }) {
    if (!_members.contains(member)) {
      content?.layer = null;
      return false;
    }
    final rect = _globalRect(member);
    _members.remove(member);
    final ghostOwner = owner ?? this;
    final animation = resolveGlassAnimation(member.scopeAnimation);
    final settings = member.settings, shape = member.shape;
    if (_disposed ||
        ghostOwner._disposed ||
        !animate ||
        !member.animatesTransitions ||
        animation.isNone ||
        rect == null ||
        settings == null ||
        shape == null) {
      content?.layer = null;
      return false;
    }
    final leaving = _Leaving(
      animation: animation,
      rect: rect,
      settings: settings,
      shape: shape,
      shadows: member.material?.shadows ?? const [],
      content: content,
      contentSize: contentSize,
      pixelRatio: pixelRatio,
    );
    _structureChanged(animation);
    member._ghostOwner = ghostOwner;
    ghostOwner._adopt(member, leaving);
    return true;
  }

  void reattach(GlassMember member) {
    if (member._ghostOwner == null) _members.add(member);
  }

  void _adopt(GlassMember member, _Leaving leaving) {
    _leaving[member] = leaving;
    _ghostHost?.markNeedsBuild();
    _start();
  }

  Rect? _globalRect(GlassMember member) {
    final drawn = member._lastDrawn;
    final origin = member._spaceOrigin;
    if (drawn == null || origin == null) return null;
    return drawn.shift(origin + member._scrollShift(null) - member._shiftAtRead);
  }

  void drop(GlassMember member) {
    final leaving = member._ghostOwner?._leaving.remove(member);
    leaving?.release();
    if (_members.remove(member) || leaving != null) member.dispose();
  }

  void rejoin(GlassMember member) {
    final leaving = member._ghostOwner?._leaving.remove(member);
    if (leaving == null) return;
    leaving.release();
    member._ghostOwner = null;
    _members.add(member);
  }

  List<GlassGhost> takeGhosts() {
    for (final MapEntry(key: member, value: leaving) in _leaving.entries) {
      final snapshot = leaving.snapshot();
      leaving.release();
      member
        ..material = null
        .._disappear(leaving.animation, _now);
      ghosts.add(GlassGhost(
        member: member,
        rect: leaving.rect,
        snapshot: snapshot,
        pixelRatio: leaving.pixelRatio,
        settings: leaving.settings,
        shape: leaving.shape,
        shadows: leaving.shadows,
      ));
    }
    _leaving.clear();
    return ghosts;
  }

  set ghostHost(Element? element) => _ghostHost = element;

  void _structureChanged(GlassAnimation animation) {
    _structureUntil = GlassFrame.current + 1;
    _structureAnimation = animation;
  }

  void _start() {
    if (!_disposed && !_ticker.isActive) _ticker.start();
  }

  void _tick(Duration _) {
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    var moving = false;
    for (final member in _members.toList()) {
      moving = member._sample(now) || moving;
    }
    var finished = false;
    for (final ghost in ghosts.toList()) {
      if (ghost.member._sample(now)) {
        moving = true;
      } else {
        ghosts.remove(ghost);
        ghost.dispose();
        finished = true;
      }
    }
    if (finished) _ghostHost?.markNeedsBuild();
    if (!moving && _leaving.isEmpty) {
      _ticker.stop();
      if (ghosts.isEmpty) onIdle?.call();
    }
  }

  void dispose() {
    _disposed = true;
    _ticker.dispose();
    for (final ghost in ghosts) {
      ghost.dispose();
    }
    ghosts.clear();
    for (final MapEntry(key: member, value: leaving) in _leaving.entries) {
      leaving.release();
      member.dispose();
    }
    _leaving.clear();
    for (final member in _members) {
      member.dispose();
    }
    _members.clear();
  }
}
```

- [ ] **Step 5: Run the tests and the gates.**

Run: `flutter test --no-pub test/motion/glass_materialize_test.dart test/motion/glass_member_test.dart` → `+15: All tests passed!`
Run: `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+91: All tests passed!`

- [ ] **Step 6: Commit.**

```bash
git add packages/mobile/packages/ios_liquid_glass/lib/src/motion packages/mobile/packages/ios_liquid_glass/test/motion
git commit -m "feat(ios_liquid_glass): the materialize mapping and the motion coordinator

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 13: Glass in a container joins the coordinator and materializes (M1, M3, part of M9)

**Files:**
- Create: `packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart`, `lib/src/api/glass_effect_transition.dart`
- Modify: `packages/ios_liquid_glass/lib/src/api/glass_effect.dart`, `lib/src/api/glass_effect_container.dart`, `lib/ios_liquid_glass.dart`
- Test: `packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart`

**Interfaces:**
- Consumes: the coordinator and the mapping (Task 12); `LiquidGlass.grouped(motion:, shadowSource:)`, `LiquidGlass.withOwnLayer(motion:, visibility:, settingsSource:, shadowSource:)` (Task 11).
- Produces:
  - public: `GlassEffect(transition: GlassEffectTransition.materialize | .identity)` (default `materialize`); `GlassEffectTransition`; exports of `GlassAnimation`, `GlassAnimationScope`, `withGlassAnimation`;
  - `GlassCoordinatorSpace` (its render object is the coordinator's `marker`, so the space is the render object above it) and `GlassMemberBox` (attaches its render box to the member, calls `sized` at layout and `sync` at paint);
  - `GlassEffectContainer` is stateful and owns one `GlassMotionCoordinator`; its build is a `GlassCoordinatorSpace` around the layer. The space is the render object **above** the container, so a container that re-centres in its parent animates its glass, and anything that moves the container's parent (an outer scroll, a route transition) moves the glass at once (ruling 17, finding 29);
  - every `GlassEffect` joins a coordinator: its container's, or a private one around itself (standalone glass has no insert or remove transition until Task 17); it passes `GlassAccessibility.of(context).reduceMotion` to `join` and to its member on every build (ruling 11);
  - insertion (container glass): a glass materializes when a `withGlassAnimation` is pending, or when it is first built into a parent render object that was already laid out (a glass toggled into an existing layout); glass built together with its parent (a page, a tab, a new subtree, a lazily built list item) appears at once (ruling 16). Appearing glass draws in its own layer with the container's material until it settles, then is rebuilt once into the shared group (ruling 18);
  - removal is at once in this task: `State.deactivate` leaves the member without an animation, and `activate` puts it back (Task 14 adds the ghost);
  - the material is still resolved the way `development` resolves it (a post-frame size report); Task 15 replaces that.
- Moves and resizes do not animate yet (the glass widget does not report its rebuilds); a container that gains or loses a glass animates its other glass's moves through the coordinator's structure flag (Review Focus 2). Task 16 adds the rest.

- [ ] **Step 1: Write the failing tests.** Create `packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart` (the Review Focus tests here: `a list scrolled inside a container moves its glass with the list at once, with no spring`; `glass keeps its place on screen when a sibling is inserted and the centred container re-centres, then springs to its new place`; `a container removed while its glass animates disposes cleanly`; `rebuilding during an animation does not restart it` and `switching Reduce Motion during an animation neither restarts nor stops it`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
import 'package:ios_liquid_glass/src/shaders.dart';

class _Toggle extends StatefulWidget {
  const _Toggle({required this.children, this.animation, this.row = false});

  final List<Widget> Function(bool shown) children;
  final GlassAnimation? animation;
  final bool row;

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool shown = true;

  void toggle() => setState(() => shown = !shown);

  @override
  Widget build(BuildContext context) {
    final children = widget.children(shown);
    final Widget flex = widget.row ? Row(mainAxisSize: MainAxisSize.min, children: children) : Column(mainAxisSize: MainAxisSize.min, children: children);
    final container = GlassEffectContainer(child: flex);
    final animation = widget.animation;
    return MaterialApp(
      home: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Center(child: animation == null ? container : GlassAnimationScope(animation: animation, child: container)),
      ),
    );
  }
}

Widget _block({Key? key, double width = 250, double height = 88, Widget? child}) =>
    GlassEffect(key: key, child: SizedBox(width: width, height: height, child: child));

Iterable<LiquidGlassLayer> _layers(WidgetTester tester) => tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer));

double? _visibility(WidgetTester tester) => _layers(tester).map((layer) => layer.visibility?.value).whereType<double>().firstOrNull;

GlassMember _member(WidgetTester tester, [Finder? glass]) =>
    tester.renderObject<RenderGlassMemberBox>(find.descendant(of: glass ?? find.byType(GlassEffect), matching: find.byType(GlassMemberBox)).first).member;

Rect _onScreen(GlassMember member) => MatrixUtils.transformRect(member.coordinator.space!.getTransformTo(null), member.drawn!);

void main() {
  isLocalTest = true;
  tearDown(debugResetGlassAnimation);

  testWidgets('glass present at the first frame does not animate in', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) _block()]));
    expect(_layers(tester).length, 1);
    expect(find.byType(LiquidGlass), findsOneWidget);
  });

  testWidgets('inserted glass materializes in its own layer, then joins the container', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (!shown) _block()]));
    await tester.pump();
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(_layers(tester).length, 2);
    expect(_visibility(tester), 0);
    await tester.pump(const Duration(milliseconds: 100));
    final early = _visibility(tester)!;
    await tester.pump(const Duration(milliseconds: 150));
    final later = _visibility(tester)!;
    expect(early, inExclusiveRange(0, later));
    expect(later, lessThan(1));
    await tester.pumpAndSettle();
    expect(_layers(tester).length, 1);
  });

  testWidgets('GlassAnimation.none and the identity transition change at once', (tester) async {
    await tester.pumpWidget(_Toggle(animation: GlassAnimation.none, children: (shown) => [if (shown) _block()]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(find.byType(LiquidGlass), findsNothing);
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(_layers(tester).length, 1);
    await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) const GlassEffect(transition: GlassEffectTransition.identity, child: SizedBox(width: 10, height: 10))]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    expect(find.byType(LiquidGlass), findsNothing);
  });

  testWidgets('a container removed while its glass animates disposes cleanly', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (!shown) _block()]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rebuilding during an animation does not restart it', (tester) async {
    await tester.pumpWidget(_Toggle(children: (shown) => [if (!shown) _block()]));
    await tester.pump(const Duration(seconds: 1));
    final state = tester.state<_ToggleState>(find.byType(_Toggle));
    state.toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final before = _visibility(tester)!;
    state.toggle();
    state.toggle();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_visibility(tester), greaterThan(before));
  });

  testWidgets('switching Reduce Motion during an animation neither restarts nor stops it', (tester) async {
    addTearDown(GlassAccessibility.debugReset);
    await tester.pumpWidget(_Toggle(children: (shown) => [if (!shown) _block()]));
    await tester.pump(const Duration(seconds: 1));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final before = _visibility(tester)!;
    GlassAccessibility.platform.value = const GlassAccessibilityData(reduceMotion: true);
    await tester.pump(const Duration(milliseconds: 16));
    final after = _visibility(tester)!;
    expect(after, greaterThan(before));
    expect(after, lessThan(1));
    await tester.pumpAndSettle();
    expect(_layers(tester).length, 1);
  });

  testWidgets('a list scrolled inside a container moves its glass with the list at once, with no spring', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: GlassEffectContainer(
          child: SizedBox(
            height: 300,
            width: 200,
            child: ListView(controller: controller, children: [for (var i = 0; i < 12; i++) _block(key: ValueKey(i), width: 200, height: 60)]),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    final member = _member(tester, find.byKey(const ValueKey(2)));
    final before = _onScreen(member);
    expect(before.top, closeTo(tester.getRect(find.byKey(const ValueKey(2))).top, 1e-6));
    controller.jumpTo(50);
    await tester.pump();
    expect(_onScreen(member).top, closeTo(before.top - 50, 1e-6));
    expect(_onScreen(member).top, closeTo(tester.getRect(find.byKey(const ValueKey(2))).top, 1e-6));
    expect(member.isMoving, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_onScreen(member).top, closeTo(before.top - 50, 1e-6));
    expect(_visibility(tester), isNull);
  });

  testWidgets('glass keeps its place on screen when a sibling is inserted and the centred container re-centres, then springs to its new place', (tester) async {
    await tester.pumpWidget(_Toggle(row: true, children: (shown) => [
      _block(key: const ValueKey('a'), width: 100, height: 60),
      if (!shown) _block(key: const ValueKey('b'), width: 100, height: 60),
    ]));
    await tester.pump(const Duration(seconds: 1));
    final member = _member(tester, find.byKey(const ValueKey('a')));
    final before = _onScreen(member);
    expect(before, tester.getRect(find.byKey(const ValueKey('a'))));
    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
    await tester.pump();
    final after = tester.getRect(find.byKey(const ValueKey('a')));
    expect(after.left, closeTo(before.left - 50, 1e-6));
    expect(_onScreen(member).left, closeTo(before.left, 1e-6));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_onScreen(member).left, inExclusiveRange(after.left, before.left));
    await tester.pumpAndSettle();
    expect(_onScreen(member).left, closeTo(after.left, 1e-6));
  });
}
```

- [ ] **Step 2: Run them and see them fail.**

Run: `flutter test --no-pub test/motion/glass_motion_coordinator_test.dart`
Expected: compile errors (`glass_motion_widgets.dart` missing; `GlassEffectTransition` undefined).

- [ ] **Step 3: The widgets: the space and the member box.** Create `packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart`:

```dart
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:meta/meta.dart';

@internal
class GlassCoordinatorSpace extends SingleChildRenderObjectWidget {
  const GlassCoordinatorSpace({super.key, required this.coordinator, super.child});

  final GlassMotionCoordinator coordinator;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGlassCoordinatorSpace(coordinator);

  @override
  void updateRenderObject(BuildContext context, RenderGlassCoordinatorSpace renderObject) {
    renderObject.coordinator = coordinator;
  }
}

@internal
class RenderGlassCoordinatorSpace extends RenderProxyBox {
  RenderGlassCoordinatorSpace(this._coordinator);

  GlassMotionCoordinator _coordinator;
  set coordinator(GlassMotionCoordinator value) {
    if (_coordinator == value) return;
    if (_coordinator.marker == this) _coordinator.marker = null;
    _coordinator = value;
    if (attached) _coordinator.marker = this;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _coordinator.marker = this;
  }

  @override
  void detach() {
    if (_coordinator.marker == this) _coordinator.marker = null;
    super.detach();
  }
}

@internal
class GlassMemberBox extends SingleChildRenderObjectWidget {
  const GlassMemberBox({super.key, required this.member, super.child});

  final GlassMember member;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGlassMemberBox(member);

  @override
  void updateRenderObject(BuildContext context, RenderGlassMemberBox renderObject) {
    renderObject.member = member;
  }
}

@internal
class RenderGlassMemberBox extends RenderProxyBox {
  RenderGlassMemberBox(this._member);

  GlassMember _member;
  GlassMember get member => _member;
  set member(GlassMember value) {
    if (identical(_member, value)) return;
    if (attached) {
      _member.detachBox(this);
      value.attachBox(this);
    }
    _member = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _member.attachBox(this);
  }

  @override
  void detach() {
    _member.detachBox(this);
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    _member.sized(size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _member.sync();
    super.paint(context, offset);
  }
}
```

- [ ] **Step 4: The transition and the API.** Create `packages/ios_liquid_glass/lib/src/api/glass_effect_transition.dart`:

```dart
enum GlassEffectTransition { materialize, identity }
```

Then, from the worktree root:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
index 846871b319867e59a5af6dd6f6dba1c5d5c1f738..39eb262539b3b5dd5463147acf245d1452d340fb 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
@@ -3,15 +3,20 @@
 import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
 import 'package:ios_liquid_glass/src/api/glass.dart';
 import 'package:ios_liquid_glass/src/api/glass_effect_container.dart';
+import 'package:ios_liquid_glass/src/api/glass_effect_transition.dart';
 import 'package:ios_liquid_glass/src/api/glass_material_context.dart';
 import 'package:ios_liquid_glass/src/api/glass_shape.dart';
 import 'package:ios_liquid_glass/src/liquid_glass.dart';
+import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
+import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
+import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
 
 class GlassEffect extends StatefulWidget {
   const GlassEffect({
     super.key,
     this.glass = Glass.regular,
     this.shape = const GlassShape.capsule(),
+    this.transition = GlassEffectTransition.materialize,
     this.sideHint,
     required this.child,
   });
@@ -20,6 +25,7 @@
 
   final Glass glass;
   final GlassShape shape;
+  final GlassEffectTransition transition;
   final double? sideHint;
   final Widget child;
 
@@ -27,9 +33,16 @@
   State<GlassEffect> createState() => _GlassEffectState();
 }
 
-class _GlassEffectState extends State<GlassEffect> {
+class _GlassEffectState extends State<GlassEffect> with SingleTickerProviderStateMixin {
   final _childKey = GlobalKey();
   double? _shorterSide;
+  GlassMotionCoordinator? _private;
+  GlassMotionCoordinator? _coordinator;
+  GlassMember? _member;
+  bool _joined = false;
+  bool _left = false;
+
+  bool get _identity => widget.glass.kind == GlassKind.identity;
 
   void _measured(Size size) {
     final side = size.shortestSide;
@@ -38,32 +51,116 @@
   }
 
   @override
+  void didChangeDependencies() {
+    super.didChangeDependencies();
+    _join();
+  }
+
+  @override
+  void didUpdateWidget(GlassEffect oldWidget) {
+    super.didUpdateWidget(oldWidget);
+    if (oldWidget.glass.kind != widget.glass.kind || oldWidget.transition != widget.transition) _join();
+  }
+
+  static bool _laidOut(RenderObject? parent) => switch (parent) {
+    RenderBox() => parent.hasSize,
+    RenderSliver() => parent.geometry != null,
+    _ => false,
+  };
+
+  void _join() {
+    final container = GlassEffectContainer.scopeOf(context)?.coordinator;
+    final coordinator = _identity ? null : container ?? (_private ??= GlassMotionCoordinator(vsync: this));
+    final scope = GlassAnimationScope.maybeOf(context);
+    final animate = widget.transition == GlassEffectTransition.materialize;
+    final current = _member;
+    if (coordinator == _coordinator && current != null) {
+      current
+        ..scopeAnimation = scope
+        ..animatesTransitions = animate;
+      return;
+    }
+    final inserted = container != null && !_joined && (pendingGlassAnimation != null || _laidOut(context.findAncestorRenderObjectOfType<RenderObject>()));
+    _joined = true;
+    _coordinator = coordinator;
+    _member = coordinator?.join(
+      scope: scope,
+      animate: animate,
+      inserted: inserted,
+      from: current,
+      reduceMotion: GlassAccessibility.of(context).reduceMotion,
+    )?..onSettled = _settled;
+    if (current != null) current.coordinator.drop(current);
+  }
+
+  void _settled() {
+    if (mounted) setState(() {});
+  }
+
+  @override
+  void deactivate() {
+    final member = _member, coordinator = _coordinator;
+    if (member != null && coordinator != null) {
+      coordinator.leave(member, animate: false);
+      _left = true;
+    }
+    super.deactivate();
+  }
+
+  @override
+  void activate() {
+    super.activate();
+    final member = _member;
+    if (_left && member != null) member.coordinator.reattach(member);
+    _left = false;
+  }
+
+  @override
+  void dispose() {
+    final member = _member;
+    if (member != null) {
+      if (!_left) {
+        member.coordinator.drop(member);
+      } else {
+        member.dispose();
+      }
+    }
+    _private?.dispose();
+    super.dispose();
+  }
+
+  @override
   Widget build(BuildContext context) {
-    final child = _SizeReporter(
-      key: _childKey,
-      onSize: _measured,
-      child: GlassEffectScope(glass: widget.glass, child: widget.child),
-    );
-    if (widget.glass.kind == GlassKind.identity) return child;
+    final content = _SizeReporter(key: _childKey, onSize: _measured, child: GlassEffectScope(glass: widget.glass, child: widget.child));
+    final member = _member;
+    if (_identity || member == null) return content;
     return ListenableBuilder(
       listenable: GlassAccessibility.platform,
       builder: (context, _) {
-        final material = resolveGlassMaterial(
-          context,
-          glass: widget.glass,
-          shorterSide: _shorterSide ?? widget.sideHint ?? GlassEffect.fallbackSide,
-        );
-        final tint = widget.glass.tintColor;
-        final container = GlassEffectContainer.glassOf(context);
-        if (container != null && container.sameMaterial(widget.glass)) {
-          return LiquidGlass.grouped(shape: widget.shape.liquidShape, shadows: material.shadows, child: child);
+        final material = resolveGlassMaterial(context, glass: widget.glass, shorterSide: _shorterSide ?? widget.sideHint ?? GlassEffect.fallbackSide);
+        final shape = widget.shape.liquidShape;
+        final container = GlassEffectContainer.scopeOf(context);
+        final grouped = container != null && container.glass.sameMaterial(widget.glass);
+        member
+          ..shape = shape
+          ..sharedSettings = grouped ? container.settings : null
+          ..reduceMotion = GlassAccessibility.of(context).reduceMotion;
+        final Widget glass;
+        if (grouped && !member.ownsLayer) {
+          glass = LiquidGlass.grouped(shape: shape, shadows: material.shadows, motion: member, child: content);
+        } else {
+          glass = LiquidGlass.withOwnLayer(
+            settings: grouped ? container.settings : material.toSettings(tint: widget.glass.tintColor),
+            shape: shape,
+            shadows: material.shadows,
+            motion: member,
+            visibility: member.visibility,
+            child: content,
+          );
         }
-        return LiquidGlass.withOwnLayer(
-          settings: material.toSettings(tint: tint),
-          shape: widget.shape.liquidShape,
-          shadows: material.shadows,
-          child: child,
-        );
+        final box = GlassMemberBox(member: member, child: glass);
+        final private = _private;
+        return container == null && private != null ? GlassCoordinatorSpace(coordinator: private, child: box) : box;
       },
     );
   }
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart
index e02699c3a254f1d7202fc98b18f78f22049282c9..e8adf04bd658268b140a2d964a655acfb24c04e6 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart
@@ -3,9 +3,13 @@
 import 'package:ios_liquid_glass/src/api/glass.dart';
 import 'package:ios_liquid_glass/src/api/glass_material_context.dart';
 import 'package:ios_liquid_glass/src/liquid_glass_blend_group.dart';
+import 'package:ios_liquid_glass/src/liquid_glass_settings.dart';
+import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
+import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
 import 'package:ios_liquid_glass/src/rendering/liquid_glass_layer.dart';
+import 'package:meta/meta.dart';
 
-class GlassEffectContainer extends StatelessWidget {
+class GlassEffectContainer extends StatefulWidget {
   const GlassEffectContainer({super.key, this.spacing = 20, this.glass = Glass.regular, this.side = 88, required this.child});
 
   final double spacing;
@@ -13,28 +17,60 @@
   final double side;
   final Widget child;
 
-  static Glass? glassOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ContainerScope>()?.glass;
+  static Glass? glassOf(BuildContext context) => scopeOf(context)?.glass;
+
+  @internal
+  static GlassContainerScope? scopeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassContainerScope>();
+
+  @override
+  State<GlassEffectContainer> createState() => _GlassEffectContainerState();
+}
+
+class _GlassEffectContainerState extends State<GlassEffectContainer> with SingleTickerProviderStateMixin {
+  late final GlassMotionCoordinator _coordinator = GlassMotionCoordinator(vsync: this);
+
+  @override
+  void dispose() {
+    _coordinator.dispose();
+    super.dispose();
+  }
 
   @override
   Widget build(BuildContext context) {
     return ListenableBuilder(
       listenable: GlassAccessibility.platform,
       builder: (context, _) {
-        final material = resolveGlassMaterial(context, glass: glass, shorterSide: side);
-        return LiquidGlassLayer(
-          settings: material.toSettings(tint: glass.tintColor),
-          child: LiquidGlassBlendGroup(blend: spacing, child: _ContainerScope(glass: glass, child: child)),
+        final material = resolveGlassMaterial(context, glass: widget.glass, shorterSide: widget.side);
+        final settings = material.toSettings(tint: widget.glass.tintColor);
+        return GlassCoordinatorSpace(
+          coordinator: _coordinator,
+          child: LiquidGlassLayer(
+            settings: settings,
+            child: LiquidGlassBlendGroup(
+              blend: widget.spacing,
+              child: GlassContainerScope(
+                glass: widget.glass,
+                settings: settings,
+                coordinator: _coordinator,
+                child: widget.child,
+              ),
+            ),
+          ),
         );
       },
     );
   }
 }
 
-class _ContainerScope extends InheritedWidget {
-  const _ContainerScope({required this.glass, required super.child});
+@internal
+class GlassContainerScope extends InheritedWidget {
+  const GlassContainerScope({super.key, required this.glass, required this.settings, required this.coordinator, required super.child});
 
   final Glass glass;
+  final LiquidGlassSettings settings;
+  final GlassMotionCoordinator coordinator;
 
   @override
-  bool updateShouldNotify(_ContainerScope oldWidget) => oldWidget.glass != glass;
+  bool updateShouldNotify(GlassContainerScope oldWidget) =>
+      oldWidget.glass != glass || oldWidget.settings != settings || oldWidget.coordinator != coordinator;
 }
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/ios_liquid_glass.dart b/packages/mobile/packages/ios_liquid_glass/lib/ios_liquid_glass.dart
index d9abb56bff6ad7819a8cff901276d1a3ebadd972..272eb249379d6758a13effab0bb0655de9794aa0 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/ios_liquid_glass.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/ios_liquid_glass.dart
@@ -8,6 +8,7 @@
 export 'src/api/glass_dimming.dart' show GlassDimming;
 export 'src/api/glass_effect.dart' show GlassEffect, GlassEffectScope;
 export 'src/api/glass_effect_container.dart' show GlassEffectContainer;
+export 'src/api/glass_effect_transition.dart' show GlassEffectTransition;
 export 'src/api/glass_foreground.dart' show GlassForeground;
 export 'src/api/glass_shape.dart';
 export 'src/api/glass_theme.dart' show GlassTheme, GlassThemeData;
@@ -24,6 +25,7 @@
 export 'src/material/ios27.dart' show ios27Table;
 export 'src/material/ios27_scroll_edge.dart' show ios27ScrollEdgeTable;
 export 'src/material/scroll_edge_material.dart' show ScrollEdgeMaterial, ScrollEdgeStyle;
+export 'src/motion/glass_animation.dart' show GlassAnimation, GlassAnimationScope, withGlassAnimation;
 export 'src/rendering/liquid_glass_layer.dart' show LiquidGlassLayer;
 export 'src/scroll_edge/scroll_edge_effect.dart' show ScrollEdge, ScrollEdgeEffect;
 export 'src/scroll_edge/scroll_under_bars.dart' show ScrollUnderBars;
PATCH
```

- [ ] **Step 5: Run the tests and the gates.**

Run (package): `flutter test --no-pub test/motion/glass_motion_coordinator_test.dart` → `+8: All tests passed!`. Then `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+99: All tests passed!`
Run (app, from `packages/mobile`): `flutter analyze --no-pub` → `No issues found!` (Operator's `GlassSurface` and `GlassScope` sit on `GlassEffect` and `GlassEffectContainer`).

- [ ] **Step 6: Commit.**

```bash
git add packages/mobile/packages/ios_liquid_glass
git commit -m "feat(ios_liquid_glass): glass in a container joins a motion coordinator and materializes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
### Task 14: Removed glass leaves a ghost with a snapshot of its content (M1, M3)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart`, `lib/src/api/glass_effect.dart`, `lib/src/api/glass_effect_container.dart`
- Test: `packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart`

**Interfaces:**
- Consumes: `GlassMotionCoordinator.leave/rejoin/reattach/takeGhosts` (Task 12); the widgets and the container's coordinator (Task 13).
- Produces:
  - `GlassSnapshotBoundary` (`retain()` keeps the last painted layer alive with a `LayerHandle`) and `GlassGhostHost` (a `LayoutBuilder` that takes the coordinator's ghosts in the same frame and draws each at its global rect in its own layer);
  - the container's child sits in a `Stack(fit: passthrough)` with a `GlassGhostHost` above it;
  - removal: `State.deactivate` retains the content's layer and leaves the member; the coordinator keeps it as a ghost when a `withGlassAnimation` is pending or the glass's parent render object is still attached (it was removed alone); the snapshot is taken only when the ghost is built, so a glass moved with a `GlobalKey` in the same frame keeps its state and pays no snapshot (finding 21); `GlobalKey` moves between containers carry the glass's presence across (`join(from:)`);
- Ghosts carry the glass's settings and shape; their shadow comes with Task 15's material source.

- [ ] **Step 1: Write the failing tests.** Add the removal tests to `glass_motion_coordinator_test.dart` (the Review Focus tests here: `removing glass while it appears continues from its current visibility` and `visibility never rises after a removal, even right after insertion`; `a ghost draws in its own layer, so sixteen glasses, one leaving and one arriving never share one group`):

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart
index 632e11d996add19892f46ae008781812ce560c41..cbaa559279c5bb342da78f61a40644350f1a4cff 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart
@@ -76,6 +76,46 @@
     expect(_layers(tester).length, 1);
   });
 
+  testWidgets('removed glass leaves a ghost in the same frame, with its content snapshot, and it is dropped after', (tester) async {
+    await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) _block(child: const ColoredBox(color: Color(0xFFFF0000)))]));
+    await tester.pump(const Duration(seconds: 1));
+    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
+    await tester.pump();
+    expect(find.byType(RawImage), findsOneWidget);
+    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
+    expect(_visibility(tester), 1);
+    await tester.pump(const Duration(milliseconds: 60));
+    expect(_visibility(tester), inExclusiveRange(0, 1));
+    await tester.pumpAndSettle();
+    expect(find.byType(RawImage), findsNothing);
+    expect(_layers(tester).length, 1);
+  });
+
+  testWidgets('a ghost stays where its glass was on screen when the container shrinks around the removal', (tester) async {
+    await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) _block(child: const ColoredBox(color: Color(0xFFFF0000)))]));
+    await tester.pump(const Duration(seconds: 1));
+    final before = tester.getRect(find.byType(GlassEffect));
+    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
+    await tester.pump();
+    expect(tester.getSize(find.byType(GlassEffectContainer)), Size.zero);
+    expect(tester.getRect(find.byType(RawImage)).center, before.center);
+  });
+
+  testWidgets('disappearing is faster than appearing under the same spring', (tester) async {
+    await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) _block()]));
+    await tester.pump(const Duration(seconds: 1));
+    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 120));
+    final out = _visibility(tester)!;
+    await tester.pumpAndSettle();
+    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 120));
+    final into = _visibility(tester)!;
+    expect(1 - out, greaterThan(into));
+  });
+
   testWidgets('GlassAnimation.none and the identity transition change at once', (tester) async {
     await tester.pumpWidget(_Toggle(animation: GlassAnimation.none, children: (shown) => [if (shown) _block()]));
     await tester.pump(const Duration(seconds: 1));
@@ -89,6 +129,20 @@
     await tester.pump(const Duration(seconds: 1));
     tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
     await tester.pump();
+    expect(find.byType(LiquidGlass), findsNothing);
+  });
+
+  testWidgets('removing glass while it appears continues from its current visibility', (tester) async {
+    await tester.pumpWidget(_Toggle(children: (shown) => [if (!shown) _block()]));
+    await tester.pump(const Duration(seconds: 1));
+    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 150));
+    final before = _visibility(tester)!;
+    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
+    await tester.pump();
+    expect(_visibility(tester), closeTo(before, 1e-9));
+    await tester.pumpAndSettle();
     expect(find.byType(LiquidGlass), findsNothing);
   });
 
@@ -131,6 +185,28 @@
     expect(after, lessThan(1));
     await tester.pumpAndSettle();
     expect(_layers(tester).length, 1);
+  });
+
+  testWidgets('a ghost draws in its own layer, so sixteen glasses, one leaving and one arriving never share one group', (tester) async {
+    await tester.pumpWidget(_Toggle(children: (shown) => [
+      for (var i = 0; i < 15; i++) _block(key: ValueKey(i), width: 20, height: 10),
+      if (shown) _block(key: const ValueKey('leaving'), width: 20, height: 10),
+      if (!shown) _block(key: const ValueKey('arriving'), width: 20, height: 10),
+    ]));
+    await tester.pump(const Duration(seconds: 1));
+    expect(tester.takeException(), isNull);
+    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
+    await tester.pump();
+    for (var i = 0; i < 6; i++) {
+      await tester.pump(const Duration(milliseconds: 16));
+      expect(tester.takeException(), isNull);
+    }
+    final ghost = find.ancestor(of: find.byType(RawImage), matching: find.byType(LiquidGlassLayer)).first;
+    expect(ghost, findsOneWidget);
+    expect(find.descendant(of: ghost, matching: find.byType(GlassEffect)), findsNothing);
+    expect(find.byType(GlassEffect), findsNWidgets(16));
+    await tester.pumpAndSettle();
+    expect(tester.takeException(), isNull);
   });
 
   testWidgets('a list scrolled inside a container moves its glass with the list at once, with no spring', (tester) async {
@@ -181,4 +257,55 @@
     await tester.pumpAndSettle();
     expect(_onScreen(member).left, closeTo(after.left, 1e-6));
   });
+
+  testWidgets('glass removed together with its parent disappears at once', (tester) async {
+    await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) Padding(padding: const EdgeInsets.all(1), child: _block())]));
+    await tester.pump(const Duration(seconds: 1));
+    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
+    await tester.pump();
+    expect(find.byType(RawImage), findsNothing);
+    expect(find.byType(LiquidGlass), findsNothing);
+  });
+
+  testWidgets('visibility never rises after a removal, even right after insertion', (tester) async {
+    await tester.pumpWidget(_Toggle(children: (shown) => [if (!shown) _block()]));
+    await tester.pump(const Duration(seconds: 1));
+    final state = tester.state<_ToggleState>(find.byType(_Toggle));
+    state.toggle();
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 8));
+    state.toggle();
+    await tester.pump();
+    var last = _visibility(tester)!;
+    while (find.byType(LiquidGlassLayer).evaluate().length > 1) {
+      await tester.pump(const Duration(milliseconds: 8));
+      final now = _visibility(tester);
+      if (now == null) break;
+      expect(now, lessThanOrEqualTo(last + 1e-12));
+      last = now;
+    }
+  });
+
+  testWidgets('glass moved to another container with a GlobalKey stays visible and leaves no ghost', (tester) async {
+    final key = GlobalKey();
+    var left = true;
+    late StateSetter rebuild;
+    await tester.pumpWidget(MaterialApp(
+      home: StatefulBuilder(builder: (context, setState) {
+        rebuild = setState;
+        final glass = GlassEffect(key: key, child: const SizedBox(width: 80, height: 40));
+        return Row(children: [
+          GlassEffectContainer(child: SizedBox(width: 100, height: 60, child: left ? glass : null)),
+          GlassEffectContainer(child: SizedBox(width: 100, height: 60, child: left ? null : glass)),
+        ]);
+      }),
+    ));
+    await tester.pump(const Duration(seconds: 1));
+    rebuild(() => left = false);
+    await tester.pump();
+    expect(find.byType(RawImage), findsNothing);
+    expect(_member(tester).presence, GlassPresence.present);
+    expect(_visibility(tester), isNull);
+    expect(tester.takeException(), isNull);
+  });
 }
PATCH
```

- [ ] **Step 2: Run them and see them fail.**

Run: `flutter test --no-pub test/motion/glass_motion_coordinator_test.dart`
Expected: `+10 -6`: the six tests that need a ghost fail (`Found 0 widgets with type "RawImage"`; the visibility reads `null` because the glass is gone). `glass removed together with its parent disappears at once` and `glass moved to another container with a GlobalKey stays visible and leaves no ghost` pass already, because removal is still at once.

- [ ] **Step 3: The snapshot boundary, the ghost host and the removal.** From the worktree root:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart
index 29defbcf3d149b442358bc7efabf4a26512a78b2..39c83318a57584e42609f3f1abeae95af20019ae 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart
@@ -1,5 +1,6 @@
 import 'package:flutter/rendering.dart';
 import 'package:flutter/widgets.dart';
+import 'package:ios_liquid_glass/src/liquid_glass.dart';
 import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
 import 'package:meta/meta.dart';
 
@@ -98,3 +99,138 @@
     super.paint(context, offset);
   }
 }
+
+@internal
+class GlassSnapshotBoundary extends SingleChildRenderObjectWidget {
+  const GlassSnapshotBoundary({super.key, super.child});
+
+  @override
+  RenderObject createRenderObject(BuildContext context) => RenderGlassSnapshotBoundary();
+}
+
+@internal
+class RenderGlassSnapshotBoundary extends RenderRepaintBoundary {
+  LayerHandle<OffsetLayer>? retain() {
+    final painted = layer;
+    if (painted is! OffsetLayer || !hasSize || size.isEmpty) return null;
+    return LayerHandle<OffsetLayer>()..layer = painted;
+  }
+}
+
+@internal
+class GlassGhostHost extends StatelessWidget {
+  const GlassGhostHost({super.key, required this.coordinator});
+
+  final GlassMotionCoordinator coordinator;
+
+  @override
+  Widget build(BuildContext context) {
+    return LayoutBuilder(
+      builder: (context, constraints) {
+        coordinator.ghostHost = context as Element;
+        final ghosts = coordinator.takeGhosts();
+        return IgnorePointer(
+          child: ExcludeSemantics(
+            child: _GhostStack(
+              children: [for (final ghost in ghosts) _GhostSlot(key: ObjectKey(ghost), global: ghost.rect, child: _Ghost(ghost: ghost))],
+            ),
+          ),
+        );
+      },
+    );
+  }
+}
+
+class _GhostParentData extends ContainerBoxParentData<RenderBox> {
+  Rect global = Rect.zero;
+}
+
+class _GhostSlot extends ParentDataWidget<_GhostParentData> {
+  const _GhostSlot({super.key, required this.global, required super.child});
+
+  final Rect global;
+
+  @override
+  void applyParentData(RenderObject renderObject) {
+    final data = renderObject.parentData! as _GhostParentData;
+    if (data.global == global) return;
+    data.global = global;
+    renderObject.parent?.markNeedsLayout();
+  }
+
+  @override
+  Type get debugTypicalAncestorWidgetClass => _GhostStack;
+}
+
+class _GhostStack extends MultiChildRenderObjectWidget {
+  const _GhostStack({super.children});
+
+  @override
+  RenderObject createRenderObject(BuildContext context) => _RenderGhostStack();
+}
+
+class _RenderGhostStack extends RenderBox
+    with ContainerRenderObjectMixin<RenderBox, _GhostParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _GhostParentData> {
+  @override
+  void setupParentData(RenderBox child) {
+    if (child.parentData is! _GhostParentData) child.parentData = _GhostParentData();
+  }
+
+  @override
+  void performLayout() {
+    size = constraints.biggest.isFinite ? constraints.biggest : constraints.smallest;
+    var child = firstChild;
+    while (child != null) {
+      final data = child.parentData! as _GhostParentData;
+      child.layout(BoxConstraints.tight(data.global.size));
+      child = data.nextSibling;
+    }
+  }
+
+  Offset _placement(RenderBox child) => globalToLocal((child.parentData! as _GhostParentData).global.topLeft);
+
+  @override
+  void paint(PaintingContext context, Offset offset) {
+    var child = firstChild;
+    while (child != null) {
+      context.paintChild(child, offset + _placement(child));
+      child = childAfter(child);
+    }
+  }
+
+  @override
+  void applyPaintTransform(RenderBox child, Matrix4 transform) {
+    final placement = _placement(child);
+    transform.translateByDouble(placement.dx, placement.dy, 0, 1);
+  }
+
+  @override
+  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => false;
+}
+
+class _Ghost extends StatelessWidget {
+  const _Ghost({required this.ghost});
+
+  final GlassGhost ghost;
+
+  @override
+  Widget build(BuildContext context) {
+    final snapshot = ghost.snapshot;
+    return LiquidGlass.withOwnLayer(
+      settings: ghost.settings,
+      shape: ghost.shape,
+      shadows: ghost.shadows,
+      visibility: ghost.member.visibility,
+      child: SizedBox.fromSize(
+        size: ghost.rect.size,
+        child: snapshot == null
+            ? null
+            : OverflowBox(
+                maxWidth: double.infinity,
+                maxHeight: double.infinity,
+                child: RawImage(image: snapshot, scale: ghost.pixelRatio),
+              ),
+      ),
+    );
+  }
+}
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
index 39eb262539b3b5dd5463147acf245d1452d340fb..59b308946ee5ae055dc7fcc382c6e6875a09df35 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
@@ -34,13 +34,17 @@
 }
 
 class _GlassEffectState extends State<GlassEffect> with SingleTickerProviderStateMixin {
+  final _snapshotKey = GlobalKey();
   final _childKey = GlobalKey();
   double? _shorterSide;
+  double _pixelRatio = 1;
   GlassMotionCoordinator? _private;
   GlassMotionCoordinator? _coordinator;
   GlassMember? _member;
+  RenderObject? _parent;
   bool _joined = false;
   bool _left = false;
+  bool _ghosted = false;
 
   bool get _identity => widget.glass.kind == GlassKind.identity;
 
@@ -53,6 +57,7 @@
   @override
   void didChangeDependencies() {
     super.didChangeDependencies();
+    _pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
     _join();
   }
 
@@ -101,7 +106,19 @@
   void deactivate() {
     final member = _member, coordinator = _coordinator;
     if (member != null && coordinator != null) {
-      coordinator.leave(member, animate: false);
+      final owner = coordinator == _private ? null : coordinator;
+      final parent = _parent;
+      final animate = owner != null && (pendingGlassAnimation != null || (parent != null && parent.attached));
+      final boundary = _snapshotKey.currentContext?.findRenderObject();
+      final keep = animate && member.animatesTransitions && boundary is RenderGlassSnapshotBoundary;
+      _ghosted = coordinator.leave(
+        member,
+        animate: animate,
+        owner: owner,
+        content: keep ? boundary.retain() : null,
+        contentSize: keep && boundary.hasSize ? boundary.size : null,
+        pixelRatio: _pixelRatio,
+      );
       _left = true;
     }
     super.deactivate();
@@ -111,8 +128,15 @@
   void activate() {
     super.activate();
     final member = _member;
-    if (_left && member != null) member.coordinator.reattach(member);
+    if (_left && member != null) {
+      if (_ghosted) {
+        member.coordinator.rejoin(member);
+      } else {
+        member.coordinator.reattach(member);
+      }
+    }
     _left = false;
+    _ghosted = false;
   }
 
   @override
@@ -121,7 +145,7 @@
     if (member != null) {
       if (!_left) {
         member.coordinator.drop(member);
-      } else {
+      } else if (!_ghosted) {
         member.dispose();
       }
     }
@@ -131,7 +155,11 @@
 
   @override
   Widget build(BuildContext context) {
-    final content = _SizeReporter(key: _childKey, onSize: _measured, child: GlassEffectScope(glass: widget.glass, child: widget.child));
+    _parent = context.findAncestorRenderObjectOfType<RenderObject>();
+    final content = GlassSnapshotBoundary(
+      key: _snapshotKey,
+      child: _SizeReporter(key: _childKey, onSize: _measured, child: GlassEffectScope(glass: widget.glass, child: widget.child)),
+    );
     final member = _member;
     if (_identity || member == null) return content;
     return ListenableBuilder(
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart
index e8adf04bd658268b140a2d964a655acfb24c04e6..dded169d3f67fe38dcfeebcdf0804b1a85fab7a3 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart
@@ -52,7 +52,11 @@
                 glass: widget.glass,
                 settings: settings,
                 coordinator: _coordinator,
-                child: widget.child,
+                child: Stack(
+                  fit: StackFit.passthrough,
+                  clipBehavior: Clip.none,
+                  children: [widget.child, Positioned.fill(child: GlassGhostHost(coordinator: _coordinator))],
+                ),
               ),
             ),
           ),
PATCH
```

- [ ] **Step 4: Run the tests and the gates.**

Run (package): `flutter test --no-pub test/motion/glass_motion_coordinator_test.dart` → `+16: All tests passed!`. Then `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+107: All tests passed!`

- [ ] **Step 5: Commit.**

```bash
git add packages/mobile/packages/ios_liquid_glass
git commit -m "feat(ios_liquid_glass): removed glass leaves a ghost with a snapshot of its content

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
### Task 15: Glass takes its material from its drawn size, with no post-frame rebuild (M1)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/api/glass_effect.dart`, `lib/src/api/glass_material_context.dart`, `lib/src/material/glass_material_override.dart`
- Test: `packages/ios_liquid_glass/test/glass_effect_test.dart`

**Interfaces:**
- Consumes: `GlassMaterialSource` and the render objects' `settingsSource`/`shadowSource` (Task 11); `GlassMember.material` (Task 12).
- Produces:
  - material follows size (spec M1): each glass owns a `GlassMaterialSource` built from `glassMaterialResolver(context, glass:)` (a pure function of the side, from the theme, accessibility and debug overrides of the last build; `GlassMaterialOverride.scopeOf`/`valuesFor`); standalone glass draws its settings and shadow from it, container glass its shadow (its settings stay the container's). `GlassEffect`'s post-frame size `setState` is gone; `sideHint` is the side of the first build, before any layout.

- [ ] **Step 1: Write the failing tests.** Make the material tests read what the glass draws, which now comes from the source, and add `has the material of its own size in its first frame`:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/test/glass_effect_test.dart b/packages/mobile/packages/ios_liquid_glass/test/glass_effect_test.dart
index d81d32d46317a06f74d9c2cc9e49e831f1479336..ac8ca787a4607d3341f49f40cc604c7a34640930 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/glass_effect_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/glass_effect_test.dart
@@ -2,6 +2,8 @@
 import 'package:flutter_test/flutter_test.dart';
 import 'package:ios_liquid_glass/ios_liquid_glass.dart';
 import 'package:ios_liquid_glass/src/shaders.dart';
+
+LiquidGlassSettings _drawn(LiquidGlassLayer layer) => layer.settingsSource?.settings ?? layer.settings;
 
 const _accent = Color(0xFF1ACB64);
 
@@ -32,20 +34,26 @@
   testWidgets('draws its own layer with the material resolved for its measured size', (tester) async {
     await tester.pumpWidget(_host(const GlassEffect(child: SizedBox(width: 250, height: 60))));
     await tester.pump();
-    final layer = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer));
+    final layer = _drawn(tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)));
     final expected = GlassMaterial.resolve(glass: Glass.regular, shorterSide: 60, brightness: Brightness.dark);
     final unmeasured = GlassMaterial.resolve(glass: Glass.regular, shorterSide: 88, brightness: Brightness.dark);
-    expect(layer.settings, expected.toSettings());
-    expect(layer.settings, isNot(unmeasured.toSettings()));
+    expect(layer, expected.toSettings());
+    expect(layer, isNot(unmeasured.toSettings()));
+  });
+
+  testWidgets('has the material of its own size in its first frame', (tester) async {
+    await tester.pumpWidget(_host(const GlassEffect(child: SizedBox(width: 250, height: 60))));
+    final layer = _drawn(tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)));
+    expect(layer, GlassMaterial.resolve(glass: Glass.regular, shorterSide: 60, brightness: Brightness.dark).toSettings());
   });
 
   testWidgets('re-resolves when the appearance flips', (tester) async {
     await tester.pumpWidget(_host(const GlassEffect(child: SizedBox(width: 250, height: 88))));
     await tester.pump();
-    final dark = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings;
+    final dark = _drawn(tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)));
     await tester.pumpWidget(_host(const GlassEffect(child: SizedBox(width: 250, height: 88)), brightness: Brightness.light));
     await tester.pump();
-    expect(tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings, isNot(dark));
+    expect(_drawn(tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))), isNot(dark));
   });
 
   testWidgets('joins a container that holds the same glass', (tester) async {
@@ -80,7 +88,7 @@
     )));
     expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
     final inner = tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).last;
-    expect(inner.settings.glassColor.withValues(alpha: 1), _accent);
+    expect(_drawn(inner).glassColor.withValues(alpha: 1), _accent);
   });
 
   testWidgets('identity glass draws no glass', (tester) async {
@@ -100,7 +108,7 @@
   testWidgets('debug overrides reach the renderer', (tester) async {
     await tester.pumpWidget(_host(const GlassEffect(child: SizedBox(width: 250, height: 88)), overrides: const {'frost': 17}));
     await tester.pump();
-    expect(tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings.blur, 17);
+    expect(_drawn(tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))).blur, 17);
   });
 
   testWidgets('side-scoped overrides reach only the glass at that anchor', (tester) async {
@@ -120,7 +128,7 @@
       ),
     ));
     await tester.pump();
-    final blurs = tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).map((layer) => layer.settings.blur).toList();
+    final blurs = tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).map((layer) => _drawn(layer).blur).toList();
     expect(blurs.first, 17);
     expect(blurs.last, isNot(17));
   });
PATCH
```

- [ ] **Step 2: Run them and see them fail.**

Run: `flutter test --no-pub test/glass_effect_test.dart`
Expected: `+12 -1`: `has the material of its own size in its first frame` fails, because the first frame still draws the 88 pt fallback material and the measured one arrives a frame later.

- [ ] **Step 3: The material resolver and the source.** From the worktree root:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/material/glass_material_override.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/material/glass_material_override.dart
index f0fc8058f893b9298f45450e08ca2f7d1e6929d4..5c3bcb4881c0dc9f76bcda1d671dbd7098290645 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/material/glass_material_override.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/material/glass_material_override.dart
@@ -12,10 +12,13 @@
     return context.dependOnInheritedWidgetOfExactType<GlassMaterialOverride>()?.values ?? const {};
   }
 
-  static Map<String, double> forSide(BuildContext context, double shorterSide) {
-    if (!kDebugMode) return const {};
-    final scope = context.dependOnInheritedWidgetOfExactType<GlassMaterialOverride>();
-    if (scope == null) return const {};
+  static Map<String, double> forSide(BuildContext context, double shorterSide) => valuesFor(scopeOf(context), shorterSide);
+
+  static GlassMaterialOverride? scopeOf(BuildContext context) =>
+      kDebugMode ? context.dependOnInheritedWidgetOfExactType<GlassMaterialOverride>() : null;
+
+  static Map<String, double> valuesFor(GlassMaterialOverride? scope, double shorterSide) {
+    if (!kDebugMode || scope == null) return const {};
     final side = scope.side;
     if (side != null && (shorterSide.clamp(44.0, 200.0) - side).abs() >= 1) return const {};
     return scope.values;
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_material_context.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_material_context.dart
index f4b12f5b34418f341a58977e5df95746fe2dbfff..80d3e5dee8e45e482daff0496640744f04c87bdc 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_material_context.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_material_context.dart
@@ -6,9 +6,16 @@
 import 'package:ios_liquid_glass/src/material/glass_material_override.dart';
 
 GlassMaterial resolveGlassMaterial(BuildContext context, {required Glass glass, required double shorterSide}) =>
-    GlassMaterial.resolve(
-      glass: glass,
-      shorterSide: shorterSide,
-      brightness: GlassTheme.brightnessOf(context),
-      accessibility: GlassAccessibility.of(context),
-    ).withOverrides(GlassMaterialOverride.forSide(context, shorterSide));
+    glassMaterialResolver(context, glass: glass)(shorterSide);
+
+GlassMaterial Function(double shorterSide) glassMaterialResolver(BuildContext context, {required Glass glass}) {
+  final brightness = GlassTheme.brightnessOf(context);
+  final accessibility = GlassAccessibility.of(context);
+  final override = GlassMaterialOverride.scopeOf(context);
+  return (side) => GlassMaterial.resolve(
+    glass: glass,
+    shorterSide: side,
+    brightness: brightness,
+    accessibility: accessibility,
+  ).withOverrides(GlassMaterialOverride.valuesFor(override, side));
+}
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
index 59b308946ee5ae055dc7fcc382c6e6875a09df35..e75cce70b0f69c49a5c65f9726d22a365c966008 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
@@ -8,6 +8,7 @@
 import 'package:ios_liquid_glass/src/api/glass_shape.dart';
 import 'package:ios_liquid_glass/src/liquid_glass.dart';
 import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
+import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
 import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
 import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
 
@@ -35,24 +36,17 @@
 
 class _GlassEffectState extends State<GlassEffect> with SingleTickerProviderStateMixin {
   final _snapshotKey = GlobalKey();
-  final _childKey = GlobalKey();
-  double? _shorterSide;
   double _pixelRatio = 1;
   GlassMotionCoordinator? _private;
   GlassMotionCoordinator? _coordinator;
   GlassMember? _member;
+  GlassMaterialSource? _material;
   RenderObject? _parent;
   bool _joined = false;
   bool _left = false;
   bool _ghosted = false;
 
   bool get _identity => widget.glass.kind == GlassKind.identity;
-
-  void _measured(Size size) {
-    final side = size.shortestSide;
-    if (_shorterSide != null && (side - _shorterSide!).abs() < 0.5) return;
-    setState(() => _shorterSide = side);
-  }
 
   @override
   void didChangeDependencies() {
@@ -150,37 +144,41 @@
       }
     }
     _private?.dispose();
+    _material?.dispose();
     super.dispose();
   }
 
   @override
   Widget build(BuildContext context) {
     _parent = context.findAncestorRenderObjectOfType<RenderObject>();
-    final content = GlassSnapshotBoundary(
-      key: _snapshotKey,
-      child: _SizeReporter(key: _childKey, onSize: _measured, child: GlassEffectScope(glass: widget.glass, child: widget.child)),
-    );
+    final content = GlassSnapshotBoundary(key: _snapshotKey, child: GlassEffectScope(glass: widget.glass, child: widget.child));
     final member = _member;
     if (_identity || member == null) return content;
     return ListenableBuilder(
       listenable: GlassAccessibility.platform,
       builder: (context, _) {
-        final material = resolveGlassMaterial(context, glass: widget.glass, shorterSide: _shorterSide ?? widget.sideHint ?? GlassEffect.fallbackSide);
+        final resolve = glassMaterialResolver(context, glass: widget.glass);
+        final tint = widget.glass.tintColor;
+        final material = _material ??= GlassMaterialSource(resolve: resolve, tint: tint, side: widget.sideHint ?? GlassEffect.fallbackSide);
+        material.configure(resolve: resolve, tint: tint);
         final shape = widget.shape.liquidShape;
         final container = GlassEffectContainer.scopeOf(context);
         final grouped = container != null && container.glass.sameMaterial(widget.glass);
         member
           ..shape = shape
+          ..material = material
           ..sharedSettings = grouped ? container.settings : null
           ..reduceMotion = GlassAccessibility.of(context).reduceMotion;
         final Widget glass;
         if (grouped && !member.ownsLayer) {
-          glass = LiquidGlass.grouped(shape: shape, shadows: material.shadows, motion: member, child: content);
+          glass = LiquidGlass.grouped(shape: shape, shadows: material.shadows, shadowSource: material, motion: member, child: content);
         } else {
           glass = LiquidGlass.withOwnLayer(
-            settings: grouped ? container.settings : material.toSettings(tint: widget.glass.tintColor),
+            settings: grouped ? container.settings : material.settings,
+            settingsSource: grouped ? null : material,
             shape: shape,
             shadows: material.shadows,
+            shadowSource: material,
             motion: member,
             visibility: member.visibility,
             child: content,
@@ -204,35 +202,3 @@
   @override
   bool updateShouldNotify(GlassEffectScope oldWidget) => oldWidget.glass != glass;
 }
-
-class _SizeReporter extends SingleChildRenderObjectWidget {
-  const _SizeReporter({super.key, required this.onSize, required super.child});
-
-  final ValueChanged<Size> onSize;
-
-  @override
-  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);
-
-  @override
-  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) {
-    renderObject.onSize = onSize;
-  }
-}
-
-class _RenderSizeReporter extends RenderProxyBox {
-  _RenderSizeReporter(this.onSize);
-
-  ValueChanged<Size> onSize;
-  Size? _reported;
-
-  @override
-  void performLayout() {
-    super.performLayout();
-    if (_reported == size) return;
-    _reported = size;
-    final measured = size;
-    WidgetsBinding.instance.addPostFrameCallback((_) {
-      if (attached) onSize(measured);
-    });
-  }
-}
PATCH
```

- [ ] **Step 4: Run the tests and every gate.**

Run (package): `flutter test --no-pub test/glass_effect_test.dart` → `+13: All tests passed!`. Then `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+108: All tests passed!`
Run (example): `flutter analyze --no-pub`; `flutter test --no-pub` → `+10: All tests passed!`
Run (app, from `packages/mobile`): `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+2146: All tests passed!` (`GlassSurface` passes its size as `sideHint`, so its first build already has the right material).

- [ ] **Step 5: Commit.**

```bash
git add packages/mobile/packages/ios_liquid_glass
git commit -m "feat(ios_liquid_glass): glass takes its material from its drawn size at layout and on every animated frame

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
### Task 16: Moves and resizes animate after a rebuild, follow the app's own motion, and never lag a scroll (M1)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/api/glass_effect.dart`
- Test: `packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart`

**Interfaces:**
- Consumes: `GlassMember.rebuilt()`, `GlassMember.scrollables` (Task 12).
- Produces: `GlassEffect`'s build reports each rebuild to its member and hands it the `ScrollableState`s above it, so a single layout change that follows a rebuild springs from where the glass was drawn (ruling 26), the drawn size, and with it the material, springs through every frame (spec M1), and a scroll in the same frame is still followed exactly. A glass the app moves on consecutive frames follows its layout from the second (ruling 32). A `const` glass whose parent changed jumps unless the change is inside `withGlassAnimation`.

- [ ] **Step 1: Write the failing tests** (`a resized glass springs its drawn rect with no widget rebuilds while it moves`; `hit testing uses the final layout while the glass is still moving`; `standalone glass takes its material from its drawn size on every frame of a resize, with no rebuild`; `a glass resized by a rebuild while its list scrolls follows the scroll exactly and springs only its size`; Review Focus 6, the four tests ruling 32 names; and `a glass removed after its list scrolled leaves its ghost where the glass was on screen`, R6):

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart
index cbaa559279c5bb342da78f61a40644350f1a4cff..1e3669972fade1d76e6bf496fcd95eae164d73a3 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart
@@ -209,6 +209,76 @@
     expect(tester.takeException(), isNull);
   });
 
+  testWidgets('a resized glass springs its drawn rect with no widget rebuilds while it moves', (tester) async {
+    var builds = 0;
+    var wide = false;
+    late StateSetter rebuild;
+    await tester.pumpWidget(MaterialApp(
+      home: Center(
+        child: StatefulBuilder(builder: (context, setState) {
+          rebuild = setState;
+          return GlassEffectContainer(
+            child: GlassEffect(
+              child: Builder(builder: (context) {
+                builds++;
+                return SizedBox(width: wide ? 300 : 100, height: 60);
+              }),
+            ),
+          );
+        }),
+      ),
+    ));
+    await tester.pump(const Duration(seconds: 1));
+    final box = tester.renderObject<RenderGlassMemberBox>(find.byType(GlassMemberBox));
+    expect(box.member.drawn!.width, 100);
+    final centre = _onScreen(box.member).center;
+    rebuild(() => wide = true);
+    await tester.pump();
+    final buildsAfterChange = builds;
+    expect(box.member.drawn!.width, closeTo(100, 0.5));
+    await tester.pump(const Duration(milliseconds: 100));
+    final mid = box.member.drawn!.width;
+    expect(mid, inExclusiveRange(100, 300));
+    expect(_onScreen(box.member).center.dx, closeTo(centre.dx, 1e-6));
+    expect(box.member.resolve(box).width, mid);
+    await tester.pump(const Duration(milliseconds: 100));
+    expect(box.member.drawn!.width, greaterThan(mid));
+    expect(builds, buildsAfterChange);
+    await tester.pumpAndSettle();
+    expect(box.member.drawn!.width, 300);
+  });
+
+  testWidgets('hit testing uses the final layout while the glass is still moving', (tester) async {
+    var taps = 0;
+    var right = false;
+    late StateSetter rebuild;
+    await tester.pumpWidget(MaterialApp(
+      home: Align(
+        alignment: Alignment.topLeft,
+        child: StatefulBuilder(builder: (context, setState) {
+          rebuild = setState;
+          return GlassEffectContainer(
+            child: Padding(
+              padding: EdgeInsets.only(left: right ? 200 : 0),
+              child: GlassEffect(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => taps++, child: const SizedBox(width: 80, height: 80))),
+            ),
+          );
+        }),
+      ),
+    ));
+    await tester.pump(const Duration(seconds: 1));
+    rebuild(() => right = true);
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 50));
+    final box = tester.renderObject<RenderGlassMemberBox>(find.byType(GlassMemberBox));
+    expect(box.member.drawn!.left, inExclusiveRange(0, 200));
+    await tester.tapAt(const Offset(240, 40));
+    await tester.pump();
+    await tester.tapAt(const Offset(40, 40));
+    await tester.pump();
+    expect(taps, 1);
+  });
+
   testWidgets('a list scrolled inside a container moves its glass with the list at once, with no spring', (tester) async {
     final controller = ScrollController();
     addTearDown(controller.dispose);
@@ -238,6 +308,223 @@
     expect(_visibility(tester), isNull);
   });
 
+  testWidgets('a glass resized by a rebuild while its list scrolls follows the scroll exactly and springs only its size', (tester) async {
+    final controller = ScrollController();
+    addTearDown(controller.dispose);
+    var wide = false;
+    late StateSetter rebuild;
+    await tester.pumpWidget(MaterialApp(
+      home: Align(
+        alignment: Alignment.topLeft,
+        child: GlassEffectContainer(
+          child: SizedBox(
+            height: 300,
+            width: 300,
+            child: StatefulBuilder(builder: (context, setState) {
+              rebuild = setState;
+              return ListView(controller: controller, children: [
+                for (var i = 0; i < 12; i++)
+                  Align(
+                    alignment: Alignment.centerLeft,
+                    child: _block(key: ValueKey(i), width: i == 2 && wide ? 200 : 100, height: 60),
+                  ),
+              ]);
+            }),
+          ),
+        ),
+      ),
+    ));
+    await tester.pump(const Duration(seconds: 1));
+    final member = _member(tester, find.byKey(const ValueKey(2)));
+    final before = _onScreen(member);
+    rebuild(() => wide = true);
+    controller.jumpTo(50);
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 100));
+    final layout = tester.getRect(find.byKey(const ValueKey(2)));
+    final drawn = _onScreen(member);
+    expect(layout.top, closeTo(before.top - 50, 1e-6));
+    expect(drawn.top, closeTo(layout.top, 1e-6));
+    expect(drawn.width, inExclusiveRange(100, 200));
+    await tester.pumpAndSettle();
+    expect(_onScreen(member), tester.getRect(find.byKey(const ValueKey(2))));
+  });
+
+  testWidgets('a glass dragged by setState holds still in its first frame, then sits on its layout within 0.5 pt in every frame', (tester) async {
+    var x = 0.0;
+    late StateSetter drag;
+    await tester.pumpWidget(MaterialApp(
+      home: StatefulBuilder(builder: (context, setState) {
+        drag = setState;
+        return Stack(children: [
+          Positioned(left: x, top: 100, child: _block(key: const ValueKey('thumb'), width: 60, height: 40, child: Text('${x.round()}'))),
+        ]);
+      }),
+    ));
+    await tester.pump(const Duration(seconds: 1));
+    final member = _member(tester);
+    var previous = tester.getRect(find.byKey(const ValueKey('thumb')));
+    for (var i = 0; i < 12; i++) {
+      drag(() => x += 15);
+      await tester.pump(const Duration(milliseconds: 16));
+      final layout = tester.getRect(find.byKey(const ValueKey('thumb')));
+      final drawn = _onScreen(member);
+      if (i == 0) {
+        expect(drawn.left, closeTo(previous.left, 0.5));
+        expect(member.isFollowing, isFalse);
+      } else {
+        expect(drawn.left, closeTo(layout.left, 0.5));
+        expect(drawn.top, closeTo(layout.top, 0.5));
+        expect(member.isFollowing, isTrue);
+      }
+      previous = layout;
+    }
+    await tester.pump(const Duration(milliseconds: 200));
+    expect(member.isMoving, isFalse);
+    expect(_onScreen(member), tester.getRect(find.byKey(const ValueKey('thumb'))));
+  });
+
+  testWidgets('a glass moved by an app animation every frame sits on its layout within 0.5 pt from the animation\'s second moving frame', (tester) async {
+    final controller = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 300));
+    addTearDown(controller.dispose);
+    await tester.pumpWidget(MaterialApp(
+      home: Align(
+        alignment: Alignment.topLeft,
+        child: GlassEffectContainer(
+          child: SizedBox(
+            width: 400,
+            height: 100,
+            child: AnimatedBuilder(
+              animation: controller,
+              builder: (context, _) => Padding(
+                padding: EdgeInsets.only(left: controller.value * 200),
+                child: Align(alignment: Alignment.topLeft, child: _block(key: const ValueKey('moved'), width: 80, height: 60)),
+              ),
+            ),
+          ),
+        ),
+      ),
+    ));
+    await tester.pump(const Duration(seconds: 1));
+    final member = _member(tester);
+    controller.forward();
+    var moved = 0;
+    var last = tester.getRect(find.byKey(const ValueKey('moved')));
+    for (var i = 0; i < 30; i++) {
+      await tester.pump(const Duration(milliseconds: 16));
+      final layout = tester.getRect(find.byKey(const ValueKey('moved')));
+      if (layout != last) moved++;
+      if (moved >= 2 && layout != last) expect(_onScreen(member).left, closeTo(layout.left, 0.5));
+      last = layout;
+    }
+    expect(moved, greaterThan(10));
+    expect(_onScreen(member).left, closeTo(200, 0.5));
+  });
+
+  testWidgets('a single change springs, and so do changes inside withGlassAnimation on back-to-back frames', (tester) async {
+    var left = 0.0;
+    late StateSetter move;
+    await tester.pumpWidget(MaterialApp(
+      home: Align(
+        alignment: Alignment.topLeft,
+        child: GlassEffectContainer(
+          child: SizedBox(
+            width: 400,
+            height: 100,
+            child: StatefulBuilder(builder: (context, setState) {
+              move = setState;
+              return Padding(padding: EdgeInsets.only(left: left), child: Align(alignment: Alignment.topLeft, child: _block(key: const ValueKey('glass'), width: 80, height: 60)));
+            }),
+          ),
+        ),
+      ),
+    ));
+    await tester.pump(const Duration(seconds: 1));
+    final member = _member(tester);
+    move(() => left = 100);
+    await tester.pump();
+    expect(_onScreen(member).left, closeTo(0, 1e-6));
+    await tester.pump(const Duration(milliseconds: 100));
+    expect(_onScreen(member).left, inExclusiveRange(0, 100));
+    expect(member.isFollowing, isFalse);
+    await tester.pumpAndSettle();
+    expect(_onScreen(member).left, closeTo(100, 1e-6));
+    withGlassAnimation(GlassAnimation.defaultSpring, () => move(() => left = 150));
+    await tester.pump(const Duration(milliseconds: 16));
+    withGlassAnimation(GlassAnimation.defaultSpring, () => move(() => left = 200));
+    await tester.pump(const Duration(milliseconds: 16));
+    expect(_onScreen(member).left, lessThan(150));
+    await tester.pump(const Duration(milliseconds: 100));
+    expect(_onScreen(member).left, inExclusiveRange(100, 200));
+    await tester.pumpAndSettle();
+    expect(_onScreen(member).left, closeTo(200, 1e-6));
+  });
+
+  testWidgets('a drag is followed, and a toggle after its release springs again', (tester) async {
+    var x = 0.0;
+    late StateSetter drag;
+    await tester.pumpWidget(MaterialApp(
+      home: StatefulBuilder(builder: (context, setState) {
+        drag = setState;
+        return Stack(children: [
+          Positioned(left: x, top: 100, child: _block(key: const ValueKey('thumb'), width: 60, height: 40)),
+        ]);
+      }),
+    ));
+    await tester.pump(const Duration(seconds: 1));
+    final member = _member(tester);
+    for (var i = 0; i < 6; i++) {
+      drag(() => x += 15);
+      await tester.pump(const Duration(milliseconds: 16));
+    }
+    expect(_onScreen(member).left, closeTo(90, 0.5));
+    await tester.pump(const Duration(milliseconds: 200));
+    drag(() => x = 200);
+    await tester.pump(const Duration(milliseconds: 16));
+    expect(_onScreen(member).left, closeTo(90, 0.5));
+    await tester.pump(const Duration(milliseconds: 100));
+    expect(_onScreen(member).left, inExclusiveRange(90, 200));
+    await tester.pumpAndSettle();
+    expect(_onScreen(member).left, closeTo(200, 1e-6));
+  });
+
+  testWidgets('a glass removed after its list scrolled leaves its ghost where the glass was on screen', (tester) async {
+    final controller = ScrollController();
+    addTearDown(controller.dispose);
+    var shown = true;
+    late StateSetter remove;
+    await tester.pumpWidget(MaterialApp(
+      home: Align(
+        alignment: Alignment.topLeft,
+        child: GlassEffectContainer(
+          child: SizedBox(
+            width: 300,
+            height: 400,
+            child: StatefulBuilder(builder: (context, setState) {
+              remove = setState;
+              return ListView(controller: controller, children: [
+                for (var i = 0; i < 8; i++)
+                  Padding(
+                    padding: const EdgeInsets.all(8),
+                    child: Row(children: [if (i != 2 || shown) _block(key: ValueKey(i), width: 100, height: 60)]),
+                  ),
+              ]);
+            }),
+          ),
+        ),
+      ),
+    ));
+    await tester.pump(const Duration(seconds: 1));
+    controller.jumpTo(60);
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 500));
+    final onScreen = tester.getRect(find.byKey(const ValueKey(2)));
+    remove(() => shown = false);
+    await tester.pump();
+    expect(find.byType(RawImage), findsOneWidget);
+    expect(tester.getRect(find.byType(RawImage)).top, closeTo(onScreen.top, 0.5));
+  });
+
   testWidgets('glass keeps its place on screen when a sibling is inserted and the centred container re-centres, then springs to its new place', (tester) async {
     await tester.pumpWidget(_Toggle(row: true, children: (shown) => [
       _block(key: const ValueKey('a'), width: 100, height: 60),
@@ -265,6 +552,45 @@
     await tester.pump();
     expect(find.byType(RawImage), findsNothing);
     expect(find.byType(LiquidGlass), findsNothing);
+  });
+
+  testWidgets('standalone glass takes its material from its drawn size on every frame of a resize, with no rebuild', (tester) async {
+    var tall = false;
+    var builds = 0;
+    late StateSetter rebuild;
+    await tester.pumpWidget(MaterialApp(
+      home: Center(
+        child: StatefulBuilder(builder: (context, setState) {
+          rebuild = setState;
+          return GlassEffect(
+            child: Builder(builder: (context) {
+              builds++;
+              return SizedBox(width: 300, height: tall ? 200 : 44);
+            }),
+          );
+        }),
+      ),
+    ));
+    await tester.pump(const Duration(seconds: 1));
+    final member = _member(tester);
+    expect(member.material!.side, 44);
+    rebuild(() => tall = true);
+    await tester.pump();
+    final buildsAfterChange = builds;
+    final sides = <double>[];
+    final settings = <LiquidGlassSettings>[];
+    for (var i = 0; i < 3; i++) {
+      await tester.pump(const Duration(milliseconds: 40));
+      sides.add(member.material!.side);
+      settings.add(member.material!.settings);
+      expect(member.material!.side, closeTo(member.drawnSize!.shortestSide, 0.5));
+    }
+    expect(sides.first, inExclusiveRange(44, 200));
+    expect(sides.last, greaterThan(sides.first));
+    expect(settings.first, isNot(settings.last));
+    expect(builds, buildsAfterChange);
+    await tester.pumpAndSettle();
+    expect(member.material!.side, 200);
   });
 
   testWidgets('visibility never rises after a removal, even right after insertion', (tester) async {
PATCH
```

- [ ] **Step 2: Run them and see them fail.**

Run: `flutter test --no-pub test/motion/glass_motion_coordinator_test.dart`
Expected: `+17 -8`: eight of the nine new tests fail. The glass jumps to its new size or place at once (`Expected: a numeric value within <0.5> of <100>`, `Actual: <300.0>`; `Expected: be in range from 100 (exclusive) to 200 (exclusive)`, `Actual: <200.0>`), the drag's first frame does not hold (`Actual: <15.0>`), a single change does not spring, and the ghost after a scroll lands where the glass was before it, because the glass reports no `Scrollable`s yet. `a glass moved by an app animation every frame sits on its layout within 0.5 pt from the animation's second moving frame` passes already: a glass that reports no rebuilds never springs. It pins that reporting them does not make app-driven motion lag.

- [ ] **Step 3: Report rebuilds and scrollables.**

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
index e75cce70b0f69c49a5c65f9726d22a365c966008..dd067076f5b809d4329f29e6c839071354dc6542 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
@@ -94,6 +94,16 @@
 
   void _settled() {
     if (mounted) setState(() {});
+  }
+
+  List<ScrollableState> _scrollables() {
+    final found = <ScrollableState>[];
+    for (var scrollable = context.findAncestorStateOfType<ScrollableState>();
+        scrollable != null;
+        scrollable = scrollable.context.findAncestorStateOfType<ScrollableState>()) {
+      found.add(scrollable);
+    }
+    return found;
   }
 
   @override
@@ -154,6 +164,9 @@
     final content = GlassSnapshotBoundary(key: _snapshotKey, child: GlassEffectScope(glass: widget.glass, child: widget.child));
     final member = _member;
     if (_identity || member == null) return content;
+    member
+      ..scrollables = _scrollables()
+      ..rebuilt();
     return ListenableBuilder(
       listenable: GlassAccessibility.platform,
       builder: (context, _) {
PATCH
```

- [ ] **Step 4: Run the tests and the gates.**

Run (package): `flutter test --no-pub test/motion/glass_motion_coordinator_test.dart` → `+25: All tests passed!`; `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+117: All tests passed!`
Run (app, from `packages/mobile`): `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+2146: All tests passed!`

- [ ] **Step 5: Commit.**

```bash
git add packages/mobile/packages/ios_liquid_glass
git commit -m "feat(ios_liquid_glass): moves and resizes spring after a rebuild; app-driven motion and scrolls are followed exactly

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 17: Standalone glass materializes and dematerializes too, its ghost drawn in the nearest `Overlay` (M1)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart`, `lib/src/api/glass_effect.dart`
- Test: `packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart`

**Interfaces:**
- Consumes: the coordinator (Task 12), `GlassGhostHost` and the insertion and removal rules (Tasks 13 and 14).
- Produces:
  - standalone glass follows the same insertion and removal rules as container glass (spec M1; ruling 16): it materializes when it is built into a parent that was already laid out or inside `withGlassAnimation`, and dematerializes when it is removed alone or inside `withGlassAnimation`;
  - `GlassOverlayGhosts.of(context)` (internal): one ghost host per `OverlayState`, an `OverlayEntry` inserted after the frame in which the first standalone glass under that overlay is built, holding its own coordinator (ticker) and `GlassGhostHost`; it is removed, after a frame, once no standalone glass uses it and no ghost is left. Its ghosts are drawn at their global rects above the overlay's routes (the `Navigator` keeps entries it does not own on top), so a ghost of glass under a modal route draws over that route for its 0.13–0.3 s (ruling 27). Without an `Overlay` (no `MaterialApp`, `CupertinoApp` or `WidgetsApp` above it), standalone glass disappears at once.

- [ ] **Step 1: Write the failing tests** (`standalone glass inserted later materializes, and glass built with its page appears at once`; `removed standalone glass dematerializes in the nearest Overlay, with its content snapshot`):

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart
index 1e3669972fade1d76e6bf496fcd95eae164d73a3..14a6045409984fef33c6e7d19d836a8285bd755f 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_motion_coordinator_test.dart
@@ -7,11 +7,12 @@
 import 'package:ios_liquid_glass/src/shaders.dart';
 
 class _Toggle extends StatefulWidget {
-  const _Toggle({required this.children, this.animation, this.row = false});
+  const _Toggle({required this.children, this.animation, this.row = false, this.container = true});
 
   final List<Widget> Function(bool shown) children;
   final GlassAnimation? animation;
   final bool row;
+  final bool container;
 
   @override
   State<_Toggle> createState() => _ToggleState();
@@ -26,7 +27,7 @@
   Widget build(BuildContext context) {
     final children = widget.children(shown);
     final Widget flex = widget.row ? Row(mainAxisSize: MainAxisSize.min, children: children) : Column(mainAxisSize: MainAxisSize.min, children: children);
-    final container = GlassEffectContainer(child: flex);
+    final container = widget.container ? GlassEffectContainer(child: flex) : flex;
     final animation = widget.animation;
     return MaterialApp(
       home: GlassTheme(
@@ -545,6 +546,42 @@
     expect(_onScreen(member).left, closeTo(after.left, 1e-6));
   });
 
+  testWidgets('standalone glass inserted later materializes, and glass built with its page appears at once', (tester) async {
+    await tester.pumpWidget(_Toggle(container: false, children: (shown) => [if (!shown) _block()]));
+    await tester.pump(const Duration(seconds: 1));
+    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
+    await tester.pump();
+    expect(_visibility(tester), 0);
+    await tester.pump(const Duration(milliseconds: 120));
+    expect(_visibility(tester), inExclusiveRange(0, 1));
+    await tester.pumpAndSettle();
+    expect(_visibility(tester), 1);
+    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
+    navigator.push(MaterialPageRoute<void>(builder: (context) => Center(child: _block(key: const ValueKey('page')))));
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 16));
+    final page = find.descendant(of: find.byKey(const ValueKey('page')), matching: find.byType(LiquidGlassLayer));
+    expect(tester.widget<LiquidGlassLayer>(page).visibility!.value, 1);
+  });
+
+  testWidgets('removed standalone glass dematerializes in the nearest Overlay, with its content snapshot', (tester) async {
+    await tester.pumpWidget(_Toggle(container: false, children: (shown) => [if (shown) _block(child: const ColoredBox(color: Color(0xFFFF0000)))]));
+    await tester.pump(const Duration(seconds: 1));
+    final before = tester.getRect(find.byType(GlassEffect));
+    tester.state<_ToggleState>(find.byType(_Toggle)).toggle();
+    await tester.pump();
+    expect(find.byType(GlassEffect), findsNothing);
+    expect(find.byType(RawImage), findsOneWidget);
+    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
+    expect(tester.getRect(find.byType(RawImage)).center, before.center);
+    expect(find.ancestor(of: find.byType(RawImage), matching: find.byType(Overlay)), findsWidgets);
+    await tester.pump(const Duration(milliseconds: 60));
+    expect(_visibility(tester), inExclusiveRange(0, 1));
+    await tester.pumpAndSettle();
+    expect(find.byType(RawImage), findsNothing);
+    expect(tester.takeException(), isNull);
+  });
+
   testWidgets('glass removed together with its parent disappears at once', (tester) async {
     await tester.pumpWidget(_Toggle(children: (shown) => [if (shown) Padding(padding: const EdgeInsets.all(1), child: _block())]));
     await tester.pump(const Duration(seconds: 1));
PATCH
```

- [ ] **Step 2: Run them and see them fail.**

Run: `flutter test --no-pub test/motion/glass_motion_coordinator_test.dart`
Expected: the two new tests fail: `Expected: <0>` (the inserted standalone glass is fully visible at once) and `Expected: exactly one matching candidate` for the ghost's `RawImage`.

- [ ] **Step 3: The overlay ghost host and the standalone rules.**

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart
index 39c83318a57584e42609f3f1abeae95af20019ae..ec59778c7ab14dbb40d7ac003ae580edfb18277e 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart
@@ -1,4 +1,5 @@
 import 'package:flutter/rendering.dart';
+import 'package:flutter/scheduler.dart';
 import 'package:flutter/widgets.dart';
 import 'package:ios_liquid_glass/src/liquid_glass.dart';
 import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
@@ -139,6 +140,81 @@
       },
     );
   }
+}
+
+@internal
+class GlassOverlayGhosts {
+  GlassOverlayGhosts._(this._overlay);
+
+  static final Expando<GlassOverlayGhosts> _hosts = Expando();
+
+  final OverlayState _overlay;
+  OverlayEntry? _entry;
+  bool _inserted = false;
+  GlassMotionCoordinator? _coordinator;
+  int _users = 0;
+
+  static GlassOverlayGhosts? of(BuildContext context) {
+    final overlay = Overlay.maybeOf(context);
+    if (overlay == null) return null;
+    return _hosts[overlay] ??= GlassOverlayGhosts._(overlay);
+  }
+
+  GlassMotionCoordinator? get coordinator => _coordinator;
+
+  void retain() {
+    _users++;
+    if (_entry != null) return;
+    final entry = _entry = OverlayEntry(builder: (context) => _OverlayGhostLayer(host: this));
+    SchedulerBinding.instance.addPostFrameCallback((_) {
+      if (!identical(_entry, entry) || !_overlay.mounted) return;
+      _overlay.insert(entry);
+      _inserted = true;
+    });
+  }
+
+  void release() {
+    _users--;
+    _removeIfIdle();
+  }
+
+  void _removeIfIdle() {
+    final entry = _entry;
+    if (_users > 0 || entry == null || (_coordinator?.hasGhosts ?? false)) return;
+    _entry = null;
+    if (_inserted) entry.remove();
+    _inserted = false;
+    SchedulerBinding.instance.addPostFrameCallback((_) => entry.dispose());
+  }
+}
+
+class _OverlayGhostLayer extends StatefulWidget {
+  const _OverlayGhostLayer({required this.host});
+
+  final GlassOverlayGhosts host;
+
+  @override
+  State<_OverlayGhostLayer> createState() => _OverlayGhostLayerState();
+}
+
+class _OverlayGhostLayerState extends State<_OverlayGhostLayer> with SingleTickerProviderStateMixin {
+  late final GlassMotionCoordinator _coordinator = GlassMotionCoordinator(vsync: this, onIdle: widget.host._removeIfIdle);
+
+  @override
+  void initState() {
+    super.initState();
+    widget.host._coordinator = _coordinator;
+  }
+
+  @override
+  void dispose() {
+    if (identical(widget.host._coordinator, _coordinator)) widget.host._coordinator = null;
+    _coordinator.dispose();
+    super.dispose();
+  }
+
+  @override
+  Widget build(BuildContext context) => GlassGhostHost(coordinator: _coordinator);
 }
 
 class _GhostParentData extends ContainerBoxParentData<RenderBox> {
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
index dd067076f5b809d4329f29e6c839071354dc6542..c308beafb631e51599d75ab7f40b8fd47f7d6636 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
@@ -41,6 +41,7 @@
   GlassMotionCoordinator? _coordinator;
   GlassMember? _member;
   GlassMaterialSource? _material;
+  GlassOverlayGhosts? _overlay;
   RenderObject? _parent;
   bool _joined = false;
   bool _left = false;
@@ -70,6 +71,7 @@
   void _join() {
     final container = GlassEffectContainer.scopeOf(context)?.coordinator;
     final coordinator = _identity ? null : container ?? (_private ??= GlassMotionCoordinator(vsync: this));
+    _useOverlay(coordinator != null && container == null);
     final scope = GlassAnimationScope.maybeOf(context);
     final animate = widget.transition == GlassEffectTransition.materialize;
     final current = _member;
@@ -79,7 +81,7 @@
         ..animatesTransitions = animate;
       return;
     }
-    final inserted = container != null && !_joined && (pendingGlassAnimation != null || _laidOut(context.findAncestorRenderObjectOfType<RenderObject>()));
+    final inserted = !_joined && (pendingGlassAnimation != null || _laidOut(context.findAncestorRenderObjectOfType<RenderObject>()));
     _joined = true;
     _coordinator = coordinator;
     _member = coordinator?.join(
@@ -92,6 +94,13 @@
     if (current != null) current.coordinator.drop(current);
   }
 
+  void _useOverlay(bool standalone) {
+    final overlay = standalone ? GlassOverlayGhosts.of(context) : null;
+    if (identical(overlay, _overlay)) return;
+    _overlay?.release();
+    _overlay = overlay?..retain();
+  }
+
   void _settled() {
     if (mounted) setState(() {});
   }
@@ -110,7 +119,8 @@
   void deactivate() {
     final member = _member, coordinator = _coordinator;
     if (member != null && coordinator != null) {
-      final owner = coordinator == _private ? null : coordinator;
+      final standalone = coordinator == _private;
+      final owner = standalone ? _overlay?.coordinator : coordinator;
       final parent = _parent;
       final animate = owner != null && (pendingGlassAnimation != null || (parent != null && parent.attached));
       final boundary = _snapshotKey.currentContext?.findRenderObject();
@@ -154,6 +164,8 @@
       }
     }
     _private?.dispose();
+    _overlay?.release();
+    _overlay = null;
     _material?.dispose();
     super.dispose();
   }
PATCH
```

- [ ] **Step 4: Run the tests and the gates.**

Run (package): `flutter test --no-pub test/motion/glass_motion_coordinator_test.dart` → `+27: All tests passed!`; `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+119: All tests passed!`
Run (app, from `packages/mobile`): `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+2146: All tests passed!`

- [ ] **Step 5: Commit.**

```bash
git add packages/mobile/packages/ios_liquid_glass
git commit -m "feat(ios_liquid_glass): standalone glass materializes and leaves a ghost in the nearest Overlay

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 18: Materialize's edge light: width from the full thickness, brightness from visibility, still glass unchanged pixel for pixel (M3)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_final_render.frag`, `lib/assets/shaders/liquid_glass_geometry_blended.frag`, `lib/src/rendering/liquid_glass_render_object.dart`, `lib/src/liquid_glass_blend_group.dart`
- Test: `packages/ios_liquid_glass/test/motion/edge_light_test.dart`

**Interfaces:**
- Consumes: Task 11's render objects.
- Produces:
  - final pass: `uOptics.w` = the material's full thickness in pixels (`settings.thickness × dpr`, which visibility does not scale); the signed distance is decoded with `signedDistanceReach(fullThickness, outlineWidth)`; the bevel (dispersion spread) still uses the ramped thickness; the edge line and sheen use `edgeDistance = clamp(−sd, 0, fullThickness)` and fade over 0.7–1.0 × the full thickness;
  - geometry pass: a new `uFullThickness` (float index 103, after the 96 shape floats), so it encodes the signed distance with the same reach;
  - at visibility 1 the full and ramped thicknesses are equal and every expression is the 2A one, so still glass draws the same bytes (spec M3).
- `fullThickness = max(uOptics.w, thickness)` in the final pass and `max(uFullThickness, uThickness)` in the geometry pass, so a caller that leaves the new uniform at 0 gets the 2A behaviour.
- Why: with visibility below 1 the old code clamped the decoded distance to the ramped thickness, so appearing glass drew its edge light over a band that grew with the lens; worse, the signed distance saturates at a reach of about a pixel at low visibility, which would light the whole interior once the width comes from the full thickness. Both shaders therefore move to the full-thickness reach together.
- Only the final pass can be pinned by bytes in a test: `flutter test`'s SkSL backend cannot compile the geometry shader (the known "initializers are not permitted on arrays" error). The geometry change is the identity at visibility 1 by construction; Task 20's still-glass runs check it at visibility 1, and its rim check (`rim_check.py`) checks it below 1, where a mis-wired `uFullThickness` would narrow the rim (finding 28).

- [ ] **Step 1: Write the failing test.** The expected bytes were recorded from the 2A shader (`development` `06d406bae`) with the same uniforms and `uOptics.w = 0`. Create `packages/ios_liquid_glass/test/motion/edge_light_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _glass2a = [
  (3.0, [0, 0, 0, 13, 0, 0, 0, 77, 0, 0, 0, 96, 191, 191, 191, 217, 255, 253, 255, 255, 255, 192, 248, 255, 252, 116, 150, 255, 234, 56, 198, 255, 234, 56, 198, 255, 234, 56, 198, 255, 234, 56, 198, 255, 234, 56, 198, 255, 200, 93, 203, 255, 234, 69, 157, 255, 234, 56, 198, 255, 234, 56, 198, 255]),
  (9.0, [0, 0, 0, 11, 0, 0, 0, 79, 0, 0, 0, 96, 191, 182, 191, 217, 255, 177, 255, 255, 255, 142, 255, 255, 255, 114, 255, 255, 255, 95, 237, 255, 255, 82, 224, 255, 252, 73, 215, 255, 246, 67, 209, 255, 242, 63, 205, 255, 214, 107, 217, 255, 241, 62, 204, 255, 235, 56, 198, 255, 234, 56, 198, 255]),
  (24.0, [0, 0, 0, 13, 0, 0, 0, 80, 8, 7, 8, 101, 200, 178, 200, 223, 255, 177, 255, 255, 255, 140, 255, 255, 255, 114, 255, 255, 255, 95, 237, 255, 255, 82, 224, 255, 252, 73, 215, 255, 246, 67, 209, 255, 242, 63, 205, 255, 235, 99, 133, 255, 248, 69, 211, 255, 244, 65, 207, 255, 241, 62, 204, 255]),
];

Future<ui.Image> _pixels(List<int> rgba, int width) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(Uint8List.fromList(rgba), width, 1, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

int _encoded(double signedDistancePx, double reachPx) => ((0.5 - 0.5 * signedDistancePx / reachPx) * 255).round().clamp(0, 255);

Future<List<int>> _strip({required double thicknessPx, required double fullThicknessPx, required double reachPx, bool flat = false}) async {
  const width = 16;
  final geometry = <int>[];
  for (var i = 0; i < width; i++) {
    geometry.addAll([128 + (i * 5) % 60, 200 - i * 3, _encoded(2.0 - i * 0.75, reachPx), 255]);
  }
  final backdrop = <int>[for (var i = 0; i < width; i++) ...(flat ? [90, 120, 150, 255] : [20 + i * 14, 240 - i * 13, 90 + (i * 37) % 120, 255])];
  final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
  final shader = program.fragmentShader();
  final uniforms = [
    16.0, 1.0, 0.0, 0.0, 16.0, 1.0,
    0.2, 0.4, 0.9, 0.1,
    thicknessPx, 0.02, 1.2, fullThicknessPx,
    0.05, 0.55, 0.95, 0.0,
    0.9, 1.1, 0.3, 4.0,
    0.8, 0.3, 1.65, 0.0,
    0.5, 2.0, 2.0, 0.6,
    0.0, 1.0,
  ];
  for (var i = 0; i < uniforms.length; i++) {
    shader.setFloat(i, uniforms[i]);
  }
  shader
    ..setImageSampler(0, await _pixels(backdrop, width))
    ..setImageSampler(1, await _pixels(geometry, width));
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 16, 1), ui.Paint()..shader = shader);
  final image = await recorder.endRecording().toImage(16, 1);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return bytes.buffer.asUint8List().toList();
}

double _reach(double thicknessPx) => thicknessPx > 2.65 ? thicknessPx : 2.65;

void main() {
  test('still glass at full visibility draws the 2A bytes pixel for pixel', () async {
    for (final (thickness, bytes) in _glass2a) {
      final strip = await _strip(thicknessPx: thickness, fullThicknessPx: thickness, reachPx: _reach(thickness));
      expect(strip, bytes, reason: 'thickness $thickness');
    }
  });

  test('over a flat backdrop a ramped lens lights its edge exactly as the full lens does, wider than its own thickness', () async {
    final full = await _strip(thicknessPx: 24, fullThicknessPx: 24, reachPx: 24, flat: true);
    final ramped = await _strip(thicknessPx: 3, fullThicknessPx: 24, reachPx: 24, flat: true);
    final coupled = await _strip(thicknessPx: 3, fullThicknessPx: 3, reachPx: _reach(3), flat: true);
    expect(ramped, full);
    expect(ramped[9 * 4], greaterThan(coupled[9 * 4]));
  });
}
```

- [ ] **Step 2: Run it and see it fail.**

Run: `flutter test --no-pub test/motion/edge_light_test.dart`
Expected: the first test passes (the 2A shader ignores `uOptics.w`) and the second fails at `expect(ramped, full)`: `Expected: [0, 0, 0, 13, 0, 0, 0, 80, …]`, `Actual: [65, 65, 65, 122, 89, 89, 89, 145, …]`. The 2A shader decodes a signed distance encoded with the full-thickness reach using the ramped one, so it lights the whole strip; over a flat backdrop the lens's refraction has nothing to shift, so only the edge light separates the two strips.

- [ ] **Step 3: The shaders and their uniforms.**

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_final_render.frag b/packages/mobile/packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_final_render.frag
index 1db0ce013cfe40ec3c19473326736a0471754cca..a5d03e0019294b029973b667bc1e4d4ee7fbe1c2 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_final_render.frag
+++ b/packages/mobile/packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_final_render.frag
@@ -44,7 +44,8 @@
     }
 
     float thickness = max(uOptics.x, 0.001);
-    float signedDistance = decodeSignedDistance(geometryData, signedDistanceReach(thickness, uOutline.z));
+    float fullThickness = max(uOptics.w, thickness);
+    float signedDistance = decodeSignedDistance(geometryData, signedDistanceReach(fullThickness, uOutline.z));
     vec2 displacement = decodeDisplacement(geometryData, thickness * 10.0);
     vec2 normal = length(displacement) > 0.0001 ? normalize(displacement) : vec2(0.0);
 
@@ -57,8 +58,8 @@
         return;
     }
 
-    float edgeDistance = clamp(-signedDistance, 0.0, thickness);
-    float rise = 1.0 - edgeDistance / thickness;
+    float bevelDistance = clamp(-signedDistance, 0.0, thickness);
+    float rise = 1.0 - bevelDistance / thickness;
     float heightNorm = sqrt(max(0.0, 1.0 - rise * rise));
     float bevel = 1.0 - heightNorm;
 
@@ -81,7 +82,8 @@
 
     float power = max(uLight.z, 0.001);
     float lobes = pow(max(0.0, dot(normal, uLightDirection)), power) + uLight.w * pow(max(0.0, dot(normal, -uLightDirection)), power);
-    float fade = 1.0 - smoothstep(0.7 * thickness, thickness, edgeDistance);
+    float edgeDistance = clamp(-signedDistance, 0.0, fullThickness);
+    float fade = 1.0 - smoothstep(0.7 * fullThickness, fullThickness, edgeDistance);
     float line = uLight.x * exp(-edgeDistance / max(uLight.y, 0.001));
     float sheen = uTintSheen.z * exp(-edgeDistance / max(uTintSheen.w, 0.001));
     color = clamp(color + vec3(lobes * fade * (line + sheen)), 0.0, 1.0);
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_geometry_blended.frag b/packages/mobile/packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_geometry_blended.frag
index dc060e219f4e37c8a8999a44b8ec9f2d4c4e98f5..248c1f645cc11f16f7216577c75d647cd4bc1b1c 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_geometry_blended.frag
+++ b/packages/mobile/packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_geometry_blended.frag
@@ -15,6 +15,7 @@
 layout(location = 1) uniform vec4 uOpticalProps;
 layout(location = 2) uniform float uNumShapes;
 layout(location = 3) uniform float uShapeData[MAX_SHAPES * 6];
+layout(location = 99) uniform float uFullThickness;
 
 float uThickness = uOpticalProps.z;
 float uRefractiveIndex = uOpticalProps.x;
@@ -42,7 +43,7 @@
     float dx = dFdx(sd);
     float dy = dFdy(sd);
     float maxDisplacement = uThickness * 10.0;
-    float reach = signedDistanceReach(uThickness, uOutlineBand);
+    float reach = signedDistanceReach(max(uFullThickness, uThickness), uOutlineBand);
     
     if (sd >= 0.0) {
         vec2 gradient = vec2(dx, dy);
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart
index 114a23ec258c4722f84441ef78e2d68c2fc03331..ba1ae84627cea9f32b3adaca6fa453561f1589a3 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart
@@ -140,7 +140,7 @@
           settings.effectiveThickness * devicePixelRatio,
           settings.effectiveChromaticAberration,
           settings.effectiveSaturation,
-          0,
+          settings.thickness * devicePixelRatio,
           settings.effectiveToneBlack,
           settings.effectiveToneMid,
           settings.effectiveToneWhite,
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
index 0f2c886b199938a5b74a2e3b6f61b3c03be10e9d..1859c178c9b4d30d553281651b9784633cbe0f17 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
@@ -230,6 +230,9 @@
         blend * devicePixelRatio,
       ]);
     });
+    geometryShader.setFloatUniforms(initialIndex: 7 + LiquidGlassBlendGroup.maxShapesPerLayer * 6, (value) {
+      value.setFloat(settings.thickness * devicePixelRatio);
+    });
   }
 
   @override
PATCH
```

- [ ] **Step 4: Run the tests and the gates.**

Run: `flutter test --no-pub test/motion/edge_light_test.dart` → `+2: All tests passed!`
Run: `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+121: All tests passed!` (the long SkSL error about `liquid_glass_geometry_blended` is printed as always; ROADMAP gotcha 3).

- [ ] **Step 5: Commit.**

```bash
git add packages/mobile/packages/ios_liquid_glass
git commit -m "feat(ios_liquid_glass): edge light keeps the full thickness while glass materializes; still glass unchanged

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 19: Live example scenes: the three materialize scenes and the lab's tool scenes (M11 for 2B.1)

**Files:**
- Create: `packages/ios_liquid_glass/example/lib/lab/scenes/motion_scenes.dart`
- Modify: `packages/ios_liquid_glass/example/lib/lab/glass_lab_registry.dart`, `example/lib/lab/scenes/material_scenes.dart`
- Test: `packages/ios_liquid_glass/example/test/lab_test.dart`

**Interfaces:**
- Consumes: `GlassEffectContainer`, `GlassEffect`, `withGlassAnimation`, `GlassAnimation` (Tasks 13–17); `LabButton(onTap:)`, `LabCentered`, `LabBlock` (existing); `GlassLabLaunch.visibility` and `.blurRamp` (Task 5).
- Produces:
  - `material.materialize`: `GlassEffectContainer(child: shown ? LabBlock(250×88) : SizedBox.shrink())`, like native's `GlassEffectContainer { if shown { GlassBlock } }`; the toggle is a plain `setState`, so the change uses the package default (native uses `withAnimation {}`); the glass is toggled inside the container's laid-out `Stack`, so it materializes under Task 13's insertion rule;
  - `material.materialize.snappy` / `.bouncy`: the same with `withGlassAnimation(GlassAnimation.snappy / .bouncy, …)`;
  - each materialize scene runs one quick hide-and-show (a 0.08 s critically damped spring, 150 ms per step) right after its first frame, before the driver's 1.5 s settle and `ready.png` (ruling 24): the example is a debug JIT build, and the first transition of a launch otherwise stalls on compiling the code it runs;
  - tools (outside the manifest): `tool.visibility`, the materialize block drawn with its own layer at the fixed `launch.json` `visibility`, its blur ramped by `blurRamp` exactly as the package ramps it (what `fitvis` scans); `tool.ghost` and `tool.ghost.standalone`, the materialize scene with a "Glass" label, in a container and with no container (Task 20 looks at both ghosts); `tool.materialize.cold`, the materialize scene without the warm-up (Task 20 records the first transition of a launch for project 5).
- Native's container shrinks to nothing when the glass is removed, and so does this one; the ghost stays where the glass was because ghosts are placed in global coordinates (ruling 15).

- [ ] **Step 1: Write the failing tests** (appended to `main()`):

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/example/test/lab_test.dart b/packages/mobile/packages/ios_liquid_glass/example/test/lab_test.dart
index 3611be7a249fc4ce11aa9fbf6216ff4b06f21ed9..87417eee0b4d88bf7edf1be3e9930903d82319d4 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/test/lab_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/test/lab_test.dart
@@ -3,6 +3,7 @@
 
 import 'package:flutter/material.dart';
 import 'package:flutter_test/flutter_test.dart';
+import 'package:ios_liquid_glass/ios_liquid_glass.dart';
 import 'package:ios_liquid_glass_example/lab/glass_lab_launch.dart';
 import 'package:ios_liquid_glass_example/lab/glass_lab_marker.dart';
 import 'package:ios_liquid_glass_example/lab/glass_lab_registry.dart';
@@ -108,4 +109,50 @@
     await tester.pump(const Duration(milliseconds: 300));
     expect(colour(), GlassLabTouchMarker.idle);
   });
+
+  testWidgets('the materialize scene removes and restores its glass on the toggle', (tester) async {
+    tester.view.physicalSize = const Size(1206, 2622);
+    tester.view.devicePixelRatio = 3;
+    addTearDown(tester.view.reset);
+    final semantics = tester.ensureSemantics();
+    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.materialize.snappy'))));
+    await tester.pump(const Duration(seconds: 1));
+    expect(find.byType(GlassEffect), findsOneWidget);
+    await tester.tap(find.bySemanticsIdentifier('toggle'));
+    await tester.pump();
+    expect(find.byType(GlassEffect), findsNothing);
+    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
+    await tester.pumpAndSettle();
+    expect(find.byType(LiquidGlassLayer), findsOneWidget);
+    await tester.tap(find.bySemanticsIdentifier('toggle'));
+    await tester.pumpAndSettle();
+    expect(find.byType(GlassEffect), findsOneWidget);
+    semantics.dispose();
+  });
+
+  testWidgets('the visibility tool ramps blur by the launch exponent, as the package ramps it', (tester) async {
+    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'tool.visibility', visibility: 0.5, blurRamp: 3))));
+    final settings = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings;
+    final full = GlassMaterial.resolve(glass: Glass.regular, shorterSide: 88, brightness: GlassTheme.brightnessOf(tester.element(find.byType(LiquidGlassLayer)))).toSettings();
+    expect(settings.visibility, 0.5);
+    expect(settings.effectiveBlur, closeTo(full.blur * 0.125, 1e-9));
+  });
+
+  testWidgets('the standalone ghost tool removes glass that is in no container', (tester) async {
+    tester.view.physicalSize = const Size(1206, 2622);
+    tester.view.devicePixelRatio = 3;
+    addTearDown(tester.view.reset);
+    final semantics = tester.ensureSemantics();
+    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'tool.ghost.standalone'))));
+    await tester.pump(const Duration(seconds: 1));
+    expect(find.byType(GlassEffectContainer), findsNothing);
+    final images = find.byType(RawImage).evaluate().length;
+    await tester.tap(find.bySemanticsIdentifier('toggle'));
+    await tester.pump();
+    expect(find.byType(GlassEffect), findsNothing);
+    expect(find.byType(RawImage).evaluate().length, images + 1);
+    await tester.pumpAndSettle();
+    expect(find.byType(RawImage).evaluate().length, images);
+    semantics.dispose();
+  });
 }
PATCH
```

- [ ] **Step 2: Run them and see them fail.**

Run (example): `flutter test --no-pub test/lab_test.dart`
Expected: the new tests fail: `material.materialize.snappy` and the tools are not registered yet, so the screen shows the missing placeholder (`Expected: exactly one matching candidate`, found 0).

- [ ] **Step 3: The scenes.** Create `packages/ios_liquid_glass/example/lib/lab/scenes/motion_scenes.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import '../glass_lab_launch.dart';
import 'lab_parts.dart';

sealed class MotionScenes {
  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
    'material.materialize': (launch) => MaterializeScene(backdrop: launch.backdrop),
    'material.materialize.snappy': (launch) => MaterializeScene(backdrop: launch.backdrop, animation: GlassAnimation.snappy),
    'material.materialize.bouncy': (launch) => MaterializeScene(backdrop: launch.backdrop, animation: GlassAnimation.bouncy),
  };

  static final Map<String, Widget Function(GlassLabLaunch launch)> tools = {
    'tool.visibility': (launch) => VisibilityScene(backdrop: launch.backdrop, visibility: launch.visibility ?? 1, blurRamp: launch.blurRamp ?? 1),
    'tool.ghost': (launch) => MaterializeScene(backdrop: launch.backdrop, label: 'Glass'),
    'tool.ghost.standalone': (launch) => MaterializeScene(backdrop: launch.backdrop, label: 'Glass', standalone: true),
    'tool.materialize.cold': (launch) => MaterializeScene(backdrop: launch.backdrop, warmUp: false),
  };
}

class MaterializeScene extends StatefulWidget {
  const MaterializeScene({super.key, required this.backdrop, this.animation, this.label, this.standalone = false, this.warmUp = true});

  final String backdrop;
  final GlassAnimation? animation;
  final String? label;
  final bool standalone;
  final bool warmUp;

  @override
  State<MaterializeScene> createState() => _MaterializeSceneState();
}

class _MaterializeSceneState extends State<MaterializeScene> {
  static const GlassAnimation warmUp = GlassAnimation.dampedSpring(response: 0.08, dampingFraction: 1);
  static const Duration warmUpStep = Duration(milliseconds: 150);

  bool _shown = true;

  @override
  void initState() {
    super.initState();
    if (widget.warmUp) WidgetsBinding.instance.addPostFrameCallback((_) => _warmUp());
  }

  Future<void> _warmUp() async {
    for (final shown in [false, true]) {
      if (!mounted) return;
      withGlassAnimation(warmUp, () => setState(() => _shown = shown));
      await Future<void>.delayed(warmUpStep);
    }
  }

  void _toggle() {
    final animation = widget.animation;
    if (animation == null) {
      setState(() => _shown = !_shown);
    } else {
      withGlassAnimation(animation, () => setState(() => _shown = !_shown));
    }
  }

  Widget _block() {
    final label = widget.label;
    if (label == null) return const LabBlock(width: 250, height: 88);
    return GlassEffect(
      child: SizedBox(
        width: 250,
        height: 88,
        child: GlassForeground(child: Center(child: Text(label, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LabCentered(
      backdrop: widget.backdrop,
      bottom: LabButton(title: 'Toggle', id: 'toggle', onTap: _toggle),
      children: [
        if (widget.standalone)
          SizedBox(width: 250, height: 88, child: _shown ? _block() : null)
        else
          GlassEffectContainer(child: _shown ? _block() : const SizedBox.shrink()),
      ],
    );
  }
}

class VisibilityScene extends StatelessWidget {
  const VisibilityScene({super.key, required this.backdrop, required this.visibility, this.blurRamp = 1});

  final String backdrop;
  final double visibility;
  final double blurRamp;

  @override
  Widget build(BuildContext context) {
    final material = GlassMaterial.resolve(
      glass: Glass.regular,
      shorterSide: 88,
      brightness: GlassTheme.brightnessOf(context),
      accessibility: GlassAccessibility.of(context),
    );
    final settings = material.toSettings().atVisibility(visibility, blurRampExponent: blurRamp);
    return LabCentered(
      backdrop: backdrop,
      children: [
        LiquidGlass.withOwnLayer(
          settings: settings,
          shape: const LiquidRoundedRectangle(borderRadius: 999),
          shadows: material.shadows,
          child: const SizedBox(width: 250, height: 88),
        ),
      ],
    );
  }
}
```

Then:

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_registry.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_registry.dart
index f8e4a2f10e094e892464d9df47cc6c1a84a75152..9cb3ea814f1a46dca6ba0ceb2a883dc104fc898d 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_registry.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_registry.dart
@@ -4,11 +4,12 @@
 import 'glass_lab_launch.dart';
 import 'glass_lab_marker.dart';
 import 'scenes/material_scenes.dart';
+import 'scenes/motion_scenes.dart';
 import 'scenes/perf_scenes.dart';
 
 sealed class GlassLabRegistry {
-  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {...MaterialScenes.scenes};
-  static final Map<String, Widget Function(GlassLabLaunch launch)> tools = {...PerfScenes.scenes};
+  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {...MaterialScenes.scenes, ...MotionScenes.scenes};
+  static final Map<String, Widget Function(GlassLabLaunch launch)> tools = {...PerfScenes.scenes, ...MotionScenes.tools};
 
   static Widget build(GlassLabLaunch launch) {
     if (launch.bare) return GlassLabBackdrop(id: launch.backdrop);
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
index 237bb210b774e537471b477835eda01c2dac2ede..a1aa9ea8fce99483fa0ddbaa64bada3466c15e18 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
@@ -70,11 +70,6 @@
           ),
         ),
       ],
-    ),
-    'material.materialize': (launch) => LabCentered(
-      backdrop: launch.backdrop,
-      bottom: const LabButton(title: 'Toggle', id: 'toggle'),
-      children: const [LabBlock(width: 250, height: 88)],
     ),
     'material.merge': (launch) => LabCentered(
       backdrop: launch.backdrop,
PATCH
```

- [ ] **Step 4: Run the tests and the gates.**

Run (example): `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → `+13: All tests passed!`

- [ ] **Step 5: Commit.**

```bash
git add packages/mobile/packages/ios_liquid_glass/example
git commit -m "feat(ios_liquid_glass example): live materialize scenes, warmed before they are measured, and the lab's tool scenes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 20: Verification runs and `results-2b1.md` (spec §8, 2B.1)

**Files:**
- Create: `tool/glass_lab/harness/still_check.py`, `done_table.py`, `ghost_probe.py`, `rim.py`, `rim_check.py`, `cold_probe.py`, `docs/liquid_glass/02b-motion/results-2b1.md`
- Modify: `packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart` (only through `lab.py fitvis --write`)
- Test: `tool/glass_lab/harness/tests/test_done_numbers.py`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `still_check.py <2A run> <new run>` compares two runs case by case: per frame and static measure, the old and new value and pass, the Flutter frame's and the native frame's largest pixel difference; `still_check.worse(old, new, passed_before, passed_after, allowance, flutter_changed)` is spec §8 item 5's "worse" (a pass lost, or a failure grown by more than its noise) on a frame whose Flutter side changed (ruling 28); a case of the 2A run that the new run lacks is printed as `MISSING` and counted;
  - `done_table.py <run>…` prints, per materialize case, the progress measures as passing / judged (finite) / expected, apart from the event and touch gates (`events.*`, `touches.*`), the events, unpaired events and touches, both apps' frame gaps over 25 ms inside events, and per pair and shape the touch-to-response delay, the first changed frame (`progress@gap`), the progress features, invalid fits and every failing measure; then the totals;
  - `rim.rim_width(frame, bare, box_px)`: the depth in points of the lit band under the glass's top edge (half the band's peak over the interior), whatever its brightness; `rim_check.py <fitvis scan> <native run>` prints it for Flutter's fixed-visibility stills and for native materialize frames at progress 0.3, 0.5 and 0.7 against 1;
  - `ghost_probe.py [tool.ghost | tool.ghost.standalone]` records a removal and saves a sheet of the frames after release;
  - `cold_probe.py <native case>` records `tool.materialize.cold` (no warm-up) and prints both apps' first changed frame, 10–90% times and frame gaps.

- [ ] **Step 1: Write the failing tests.** Create `tool/glass_lab/harness/tests/test_done_numbers.py`:

```python
import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import done_table
import rim
import still_check


def static(value, passed):
    return {measure: value for measure in still_check.MEASURES} | {"pass": {measure: passed for measure in still_check.MEASURES}}


def write_case(root, scene, case, value, passed, flutter_pixel):
    folder = Path(root) / scene / case
    for app in ("native", "flutter"):
        (folder / app).mkdir(parents=True, exist_ok=True)
        for frame in ("ready", "settled"):
            pixel = flutter_pixel if app == "flutter" else 10
            Image.fromarray(np.full((4, 4, 3), pixel, dtype=np.uint8)).save(folder / app / f"{frame}.png")
    (folder / "result.json").write_text(json.dumps({"kind": "compared", "static": {"ready": static(value, passed), "settled": static(value, passed)}}))


class StillCheckTests(unittest.TestCase):
    def test_worse_means_a_pass_lost_or_a_failure_grown_past_noise_on_a_changed_flutter_frame(self):
        self.assertTrue(still_check.worse(3.0, 5.0, True, False, 0.0, True))
        self.assertTrue(still_check.worse(5.0, 5.6, False, False, 0.5, True))
        self.assertFalse(still_check.worse(5.0, 5.4, False, False, 0.5, True))
        self.assertFalse(still_check.worse(3.0, 2.0, True, True, 0.0, True))
        self.assertFalse(still_check.worse(3.0, 5.0, True, False, 0.0, False))

    def test_cases_in_the_2a_run_missing_from_the_new_one_are_reported(self):
        with tempfile.TemporaryDirectory() as before, tempfile.TemporaryDirectory() as after:
            write_case(before, "tabbar.rest", "dark-photo", 3.0, True, 50)
            write_case(before, "navbar.inline", "dark-photo", 3.0, True, 50)
            write_case(after, "tabbar.rest", "dark-photo", 6.0, False, 51)
            rows, missing = still_check.compare(before, after)
        self.assertEqual(missing, [("navbar.inline", "dark-photo")])
        self.assertTrue(all(row[8] for row in rows))
        self.assertEqual({row[9] for row in rows}, {1.0})


class RimTests(unittest.TestCase):
    def test_the_lit_band_under_the_top_edge_is_measured_in_points_whatever_its_brightness(self):
        bare = np.full((90, 300, 3), 60, dtype=np.float32)
        for brightness in (90.0, 27.0):
            frame = bare.copy()
            frame[10:80, 30:270] += 10
            frame[10:22, 30:270] += brightness
            self.assertAlmostEqual(rim.rim_width(frame, bare, (30, 10, 269, 79)), 4.0, places=6)
        self.assertTrue(np.isnan(rim.rim_width(bare + 1, bare, (30, 10, 269, 79))))


class DoneTableTests(unittest.TestCase):
    def test_progress_measures_are_counted_apart_from_the_event_gates_and_absent_ones_are_not_judged(self):
        result = {
            "measures": {
                "motion.events.native_motion": (2, 1, "min"),
                "motion.events.unpaired": (1, 0, "max"),
                "motion.block.step1e0.progress.rms": (0.01, 0.05, "max"),
                "motion.block.step1e0.progress.t10_90_ms": (float("inf"), 17, "max"),
                "ready.mad": (2.0, 4.0, "max"),
            },
            "checks": {
                "motion.events.native_motion": True,
                "motion.events.unpaired": False,
                "motion.block.step1e0.progress.rms": True,
                "motion.block.step1e0.progress.t10_90_ms": False,
                "ready.mad": True,
            },
        }
        found = done_table.summary(result)
        self.assertEqual(found["gates"], (1, 2))
        self.assertEqual(found["progress"], (1, 1, 2))
        self.assertEqual(found["failing"], ["block.step1e0.progress.t10_90_ms", "events.unpaired"])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and see them fail.**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_done_numbers.py`
Expected: `ModuleNotFoundError: No module named 'done_table'`.

- [ ] **Step 3: The helpers.** Create `tool/glass_lab/harness/still_check.py`:

```python
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

import metrics

MEASURES = ("mad", "luminance", "rim_rms", "bbox_pt", "centre_pt")


def frames_equal(a, b):
    if not (a.exists() and b.exists()):
        return None
    return float(np.abs(metrics.load(a) - metrics.load(b)).max())


def worse(old, new, passed_before, passed_after, allowance, flutter_changed):
    if not flutter_changed:
        return False
    return (passed_before and not passed_after) or (not passed_before and new > old + allowance)


def compare(before_run, after_run, noise=None):
    noise = noise or {}
    rows, missing = [], []
    for before_path in sorted(Path(before_run).glob("*/*/result.json")):
        before = json.loads(before_path.read_text())
        if before.get("kind") != "compared":
            continue
        scene, case = before_path.parent.parent.name, before_path.parent.name
        result_path = Path(after_run) / scene / case / "result.json"
        after = json.loads(result_path.read_text()) if result_path.exists() else {}
        if after.get("kind") != "compared":
            missing.append((scene, case))
            continue
        for frame in ("ready", "settled"):
            flutter = frames_equal(before_path.parent / "flutter" / f"{frame}.png", result_path.parent / "flutter" / f"{frame}.png")
            native = frames_equal(before_path.parent / "native" / f"{frame}.png", result_path.parent / "native" / f"{frame}.png")
            for measure in MEASURES:
                old, new = before["static"][frame][measure], after["static"][frame][measure]
                passed_before, passed_after = before["static"][frame]["pass"][measure], after["static"][frame]["pass"][measure]
                changed = flutter is None or flutter > 0
                bad = worse(old, new, passed_before, passed_after, noise.get(measure, 0.0), changed)
                rows.append((scene, case, frame, measure, old, new, passed_before, passed_after, bad, flutter, native))
    return rows, missing


def main():
    before_run, after_run = sys.argv[1], sys.argv[2]
    rows, missing = compare(before_run, after_run)
    bad = [row for row in rows if row[8]]
    triples = {(r[0], r[1], r[2]): (r[9], r[10]) for r in rows}
    identical = {key: value for key, value in triples.items() if value[0] == 0.0}
    print(f"{len(triples)} scene, case and frame triples compared; {len(identical)} Flutter frames byte-identical to the 2A run")
    for (scene, case, frame), (_, native) in sorted(identical.items()):
        print(f"identical flutter {scene} {case} {frame}: native frame max difference {native}")
    for scene, case, frame, measure, old, new, passed_before, passed_after, _, flutter, native in rows:
        if old != new or not passed_after:
            print(f"{scene} {case} {frame} {measure}: {old:.2f} -> {new:.2f} ({'pass' if passed_before else 'fail'} -> {'pass' if passed_after else 'fail'}), flutter frame max difference {flutter}, native {native}")
    print(f"missing: {len(missing)}")
    for scene, case in missing:
        print(f"MISSING {scene} {case}")
    print(f"worse: {len(bad)}")
    for row in bad:
        print("WORSE", row[:6])


if __name__ == "__main__":
    main()
```

Create `tool/glass_lab/harness/done_table.py`:

```python
import json
import math
import sys
from pathlib import Path

GATE = ("events.", "touches.")


def fmt(value, digits=0):
    if value is None:
        return "-"
    if isinstance(value, float) and not math.isfinite(value):
        return "absent"
    return f"{value:.{digits}f}"


def summary(result):
    motion = {name[len("motion."):]: entry for name, entry in result["measures"].items() if name.startswith("motion.")}
    checks = {name: result["checks"][f"motion.{name}"] for name in motion}
    gates = [name for name in motion if name.startswith(GATE)]
    progress = [name for name in motion if not name.startswith(GATE)]
    return {
        "gates": (sum(checks[n] for n in gates), len(gates)),
        "progress": (sum(checks[n] for n in progress), sum(math.isfinite(motion[n][0]) for n in progress), len(progress)),
        "failing": sorted(name for name in motion if not checks[name]),
    }


def main():
    totals = {"gates": [0, 0], "progress": [0, 0, 0]}
    for run in sys.argv[1:]:
        for path in sorted(Path(run).glob("material.materialize*/*/result.json")):
            result = json.loads(path.read_text())
            name = f"{path.parent.parent.name} {path.parent.name}"
            if result.get("kind") != "compared":
                print(f"{name}: {result.get('kind')}")
                continue
            found = summary(result)
            shapes = result.get("shapes", {})
            passed, judged, expected = found["progress"]
            gate_pass, gate_count = found["gates"]
            for key, values in (("gates", found["gates"]), ("progress", found["progress"])):
                totals[key] = [a + b for a, b in zip(totals[key], values)]
            print(f"{name}: progress measures {passed} pass / {judged} judged / {expected} expected; events and touches {gate_pass}/{gate_count}; "
                  f"events {shapes.get('event_count')} unpaired {shapes.get('unpaired')} touches {shapes.get('touches')} of {shapes.get('expected_touches')}; "
                  f"stalls native {fmt_list(result.get('native_stalls'))} flutter {fmt_list(result.get('flutter_stalls'))}")
            for label, pair in shapes.get("pairs", {}).items():
                delay = pair.get("delay", {})
                for shape, entry in pair["shapes"].items():
                    first = entry.get("first_frame", {})
                    progress = entry.get("progress")
                    head = f"   {label} {shape}: delay {fmt(delay.get('native'))}/{fmt(delay.get('flutter'))} ms, first frame {first_frame(first.get('native'))}/{first_frame(first.get('flutter'))}"
                    if not progress:
                        print(f"{head}; no progress travel")
                        continue
                    n, f = progress["native"], progress["flutter"]
                    print(f"{head}; t10_90 {fmt(n['t10_90_ms'])}/{fmt(f['t10_90_ms'])} settle {fmt(n['settle_ms'])}/{fmt(f['settle_ms'])} "
                          f"overshoot {fmt(n['overshoot_pct'], 1)}/{fmt(f['overshoot_pct'], 1)} spring {spring(n['spring'])} vs {spring(f['spring'])} "
                          f"rms {fmt(progress['rms'], 3)} sharp {fmt(n['sharpness_mid'], 2)}/{fmt(f['sharpness_mid'], 2)}"
                          + (f" fit invalid {progress['fit_invalid']}" if "fit_invalid" in progress else ""))
            for failing in found["failing"]:
                value, limit, bound = result["measures"][f"motion.{failing}"]
                print(f"   FAIL {failing} {fmt(value, 3)} {'>' if bound == 'max' else '<'} {fmt(limit, 3)}")
    print(f"total: progress measures {totals['progress'][0]} pass / {totals['progress'][1]} judged / {totals['progress'][2]} expected; "
          f"events and touches {totals['gates'][0]}/{totals['gates'][1]}")


def fmt_list(values):
    return "[" + ", ".join(fmt(v) for v in values or []) + "]"


def first_frame(entry):
    if not entry:
        return "-"
    return f"{fmt(entry.get('progress'), 2)}@{fmt(entry.get('gap_ms'))}ms"


def spring(fit):
    if not fit:
        return "-"
    return f"{fit['response']:.2f}/{fit['damping']:.2f}" + ("(edge)" if fit.get("at_grid_edge") else "")


if __name__ == "__main__":
    main()
```

Create `tool/glass_lab/harness/rim.py`:

```python
import numpy as np

import metrics

COLUMN_HALF = 10
MIN_PEAK = 2.0


def rim_width(frame, bare, box_px, scale=metrics.SCALE):
    left, top, right, bottom = box_px
    centre = (left + right) // 2
    columns = slice(max(0, centre - COLUMN_HALF), centre + COLUMN_HALF + 1)
    column = metrics.luma(frame)[top : bottom + 1, columns].mean(axis=1) - metrics.luma(bare)[top : bottom + 1, columns].mean(axis=1)
    third = len(column) // 3
    if third < 2:
        return float("nan")
    interior = float(np.median(column[third : 2 * third]))
    band = column[:third] - interior
    peak = float(band.max())
    if peak < MIN_PEAK:
        return float("nan")
    lit = np.nonzero(band >= peak / 2)[0]
    return float(lit[-1] + 1) / scale
```

Create `tool/glass_lab/harness/rim_check.py`:

```python
import json
import sys
from dataclasses import replace
from pathlib import Path

import numpy as np

sys.path.insert(0, "tool/glass_lab/harness")

import analyze
import manifest
import metrics
import rim
import shapes
import track

SCENE = "material.materialize"
REGION = "block"
BINS = (0.3, 0.5, 0.7)
TOLERANCE = 0.08


def flutter(scan_dir, region):
    rect = track.pixel_rect(region)
    found = {}
    for case_dir in sorted(Path(scan_dir).glob("*")):
        shots = {float(p.name): p / "ready.png" for p in case_dir.glob("*") if (p / "ready.png").exists()}
        if 0.0 not in shots or 1.0 not in shots:
            continue
        bare = track.crop_px(metrics.load(shots[0.0]), rect)
        box = track.box_pixels(track.crop_px(metrics.load(shots[1.0]), rect), bare, track.edges(bare))
        found[case_dir.name] = {str(v): rim.rim_width(track.crop_px(metrics.load(path), rect), bare, box) for v, path in sorted(shots.items()) if v > 0}
    return found


def native(run_dir, region):
    scene = replace({s.id: s for s in manifest.load()}[SCENE], regions={REGION: region}, track=(REGION,), motion=())
    found = {}
    for case_dir in sorted((Path(run_dir) / SCENE).glob("*")):
        folder = case_dir / "native"
        if not (folder / "video.mp4").exists():
            continue
        window = analyze.window(folder)
        capture = shapes.capture(scene, folder, window[:2] if window else None)
        rect = track.pixel_rect(region)
        bare = track.crop_px(metrics.load(folder / "bare" / "ready.png"), rect)
        box = track.box_pixels(track.crop_px(metrics.load(folder / "ready.png"), rect), bare, track.edges(bare))
        rows = capture["rows"][REGION]["rows"]
        paths = sorted((folder / "shapes").glob("*.png"))
        progress = np.array([row["progress"] for row in rows])
        widths = {"1.0": rim.rim_width(track.crop_px(metrics.load(folder / "ready.png"), rect), bare, box)}
        for target in BINS:
            near = [i for i in np.nonzero(np.abs(progress - target) <= TOLERANCE)[0] if i < len(paths)]
            values = [rim.rim_width(metrics.load(paths[i]), bare, box) for i in near]
            values = [v for v in values if np.isfinite(v)]
            widths[str(target)] = round(float(np.median(values)), 2) if values else None
        found[case_dir.name] = widths
    return found


def main():
    region = tuple({s.id: s for s in manifest.load()}[SCENE].regions[REGION])
    print(json.dumps({"flutter": flutter(sys.argv[1], region), "native": native(sys.argv[2], region)}, indent=2))


if __name__ == "__main__":
    main()
```

Create `tool/glass_lab/harness/ghost_probe.py`:

```python
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, "tool/glass_lab/harness")

import build
import metrics
import record
import shapes
import sim
import touch
import track

STEPS = [{"wait": 0.5}, {"tap": "toggle"}, {"wait": 1.2}]
REGION = (60, 390, 282, 122)


def main(scene="tool.ghost"):
    build.require_fresh("example")
    udid = sim.device()
    sim.appearance(udid, "dark")
    out = build.OUT / "ghost" / time.strftime("%Y%m%d-%H%M%S")
    with record.Recording(udid, out / "video.mp4"):
        record.drive(udid, build.EXAMPLE_BUNDLE, scene, STEPS, "photo", False, out, marker=True)
    rect = track.pixel_rect(REGION)
    frames = track.extract(out / "video.mp4", rect, out / "frames")
    windows = touch.read(out / "video.mp4", out / "marker")
    release = windows[0][1]
    chosen = [i for i, t in enumerate(frames.times) if release - 0.05 <= t <= release + 0.35]
    ready = shapes.shrink(track.crop_px(metrics.load(out / "ready.png"), rect))
    print(f"touch {windows[0]}, {len(chosen)} frames from release - 50 ms to + 350 ms")
    tiles = []
    for i in chosen:
        frame = metrics.load(frames.paths[i])
        print(f"{frames.times[i] - release:+.3f} s  mean difference from ready {metrics.mad(shapes.shrink(frame), ready):6.2f}")
        tiles.append(frame[::2, ::2])
    sheet = np.concatenate(tiles[:10], axis=0)
    Image.fromarray(sheet.astype(np.uint8)).save(out / "removal.png")
    print(out / "removal.png")


if __name__ == "__main__":
    main(*sys.argv[1:])
```

Create `tool/glass_lab/harness/cold_probe.py`:

```python
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, "tool/glass_lab/harness")

import analyze
import build
import manifest
import record
import shapes
import sim

SCENE = "material.materialize"
TOOL = "tool.materialize.cold"


def main(native_case, appearance="dark", backdrop="photo"):
    build.require_fresh("example")
    scene = {s.id: s for s in manifest.load()}[SCENE]
    udid = sim.device()
    sim.appearance(udid, appearance)
    out = build.OUT / "cold" / time.strftime("%Y%m%d-%H%M%S")
    record.drive(udid, build.EXAMPLE_BUNDLE, scene.id, [], backdrop, True, out / "bare", settle=1.0, marker=True)
    with record.Recording(udid, out / "video.mp4"):
        record.drive(udid, build.EXAMPLE_BUNDLE, TOOL, scene.steps, backdrop, False, out, marker=True)
    found = {}
    for app, folder in (("native", Path(native_case) / "native"), ("flutter", out)):
        window = analyze.window(folder)
        capture = shapes.capture(scene, folder, window[:2] if window else None)
        found[app] = {
            "stalls": capture.get("stalls", []),
            "events": [
                {"step": event["step"], "first_frame": event["first_frame"], "t10_90_ms": (shapes.progress_features(event["series"]["block"]) or {}).get("t10_90_ms")}
                for event in capture["events"]
            ],
        }
    print(json.dumps(found, indent=2))
    print(out)


if __name__ == "__main__":
    main(*sys.argv[1:])
```

Run: `python3 -m unittest discover tool/glass_lab/harness/tests` → `Ran 175 tests` … `OK`. Commit:

```bash
git add packages/mobile/tool/glass_lab/harness
git commit -m "feat(glass-lab): still check, Done table, rim check, ghost and cold-start probes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Re-fit the motion table from this branch's native runs.** Use Task 8's normal-mode and Reduce Motion materialize runs and Task 9's repeat run (five takes per case):

```bash
python3 tool/glass_lab/harness/lab.py build example
python3 tool/glass_lab/harness/lab.py fitvis build/glass_lab/runs/<Task 8 materialize run> build/glass_lab/runs/<Task 8 Reduce Motion run> build/glass_lab/runs/noise-2b1 --write
git diff packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart
python3 tool/glass_lab/harness/lab.py build example
```

It records about 160 shots (four ramps × seven visibilities × four cases, then eleven visibilities × four cases), about an hour. Check `fit.json` against the seed (prototype `build/glass_lab/fitvis/fixwave`):
- `mapping`: default exponent 3.1 ± 0.15; `.snappy` 2.7 ± 0.15 with gain 0 (`at_floor`); `.bouncy` 2.75 ± 0.15 with gain 0.34 ± 0.1; each take's exponent within ± 0.1 of the pooled one and its gain within ± 0.06 (the prototype's spreads were 3.05–3.15, 2.7–2.75, 2.7–2.8 and 0.32–0.38); at most one `excluded` curve per scene (the prototype excluded one `.bouncy` `dark-stripes` take);
- `reduce_motion_gain`: `.bouncy` 0.62 ± 0.1, `.snappy` 0 (`at_floor`), the default 0 (`identifiable: false`);
- `default_spring_check`: pooled 0.57 / 0.98, `pass: true` for `all`, per case 0.45–0.74 s / 0.77–1.24 (`pass: false`);
- `blur_ramp`: 3.0, errors about 1.1, 0.9, 0.8 and 1.0 for k = 1–4, not on the edge;
- `visibility_for_progress` about the seed's; Flutter's mean progress at visibility 0.5 about 0.42 (the ramp makes mid visibilities less blurred and so less progressed).

Stop, report `fit.json`, and do not commit a table built on it, if any of these holds: an exponent, a gain or the blur ramp on its grid edge (`at_grid_edge: true`; a gain `at_floor`, native not overshooting, is not an edge); a take's exponent outside the seed's ± 0.5, or its gain outside ± 0.3; more than one curve per scene `excluded`. `default_spring_check.pass` false is not a stop: it is a fact about native that `results-2b1.md` reports, with the failing cases (ruling 10). Otherwise run the package tests (`+121`) and commit the table as written:

```bash
git add packages/mobile/packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart
git commit -m "chore(ios_liquid_glass): re-fit the materialize table from this branch's native runs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(If `git diff` shows no change, there is nothing to commit.)

- [ ] **Step 5: The materialize runs, both apps, fresh.**

```bash
python3 tool/glass_lab/harness/lab.py run material.materialize
python3 tool/glass_lab/harness/lab.py run material.materialize --a11y reduce-motion
python3 tool/glass_lab/harness/lab.py report build/glass_lab/runs/<normal run>
python3 tool/glass_lab/harness/lab.py report build/glass_lab/runs/<reduce motion run>
python3 tool/glass_lab/harness/done_table.py build/glass_lab/runs/<normal run> build/glass_lab/runs/<reduce motion run>
```

Retry a crashed case alone (Global Constraints) and copy its case folder into the run before `report`. Then repeat, alone, every case whose `done_table` line shows a Flutter frame gap over 25 ms inside an event, or a Flutter first changed frame more than 0.2 of the travel ahead of native's (a first-frame stall, which `align.stalls` cannot see because it skips each event's first gap); keep the better run and say which cases were repeated and why (spec §10, finding 6).

What the prototype measured (`normal `20261003-113033`, Reduce Motion `20261003-120351``, after the fit of Step 4; not a target, the targets are the limits):
- progress measures (the seven `progress.*` measures per pair, Done item 4): normal 112 passing / 168 judged / 168 expected, Reduce Motion 108 / 168 / 168 (113 and 111 with R3's float slack; 120 and 119 at 1.5 × the three-take noise, as "What this plan expects to reach" classes them). By measure, normal then Reduce Motion, out of 24 each: `t10_90_ms` 20 and 17 (failures 25 ms, one 42 ms on the Reduce Motion `.bouncy` `light-photo` appear), `settle_ms` 12 and 13 (the normal `.bouncy` `light` appears settle 141–150 ms early: native overshoots 2.5–2.6% there and decays more slowly than its spring), `overshoot_pct` 24 and 24 (`.bouncy` under Reduce Motion included, with its own gain), `response_pct` 5 and 3, `damping` 9 and 9 (native's spring fitted per pair varies past 5% and 0.05; ruling 10), `rms` 24 and 24 (0.008–0.033 and 0.010–0.042), `sharpness` 18 and 18 (all six failures in each run on dark `photo`, at half progress; ruling 25);
- event and touch gates (`events.*`, `touches.*`): 60 of 60 in each run, `unpaired` 0 everywhere;
- stalls: none in either app in either run; Flutter's first changed frame within 0.07 of native's progress in every pair;
- touch-to-response delay (reported, not judged): native starts to disappear 18–47 ms and to appear 65–112 ms after the touch-up, Flutter 12–33 ms for both.

- [ ] **Step 6: The first transition of a launch, without the warm-up (project 5).**

```bash
python3 tool/glass_lab/harness/cold_probe.py build/glass_lab/runs/<normal run>/material.materialize/dark-photo
```

Record its two events in `results-2b1.md` as the cold start the warm-up hides (ruling 24). The prototype read: (`cold/20261003-121941`): the disappear's first frame came after a 38 ms gap at progress 0.38 (native 0.03 after 45 ms), 10–90% 83 ms against native's 133; the appear's first frame after 17 ms at 0.03 (native 0.01 after 18 ms), 300 ms against 292; no stall inside either event.

- [ ] **Step 7: Still glass is no worse than 2A, Operator's scenes included.** Run the 2A scenes in both apps, report them, and compare with the 2A runs of `results-2a1.md` (read in place; `still_check.py` only reads). Those runs were made at `6be5e3ff1`; `git diff 6be5e3ff1 7e318a49f -- packages/mobile/packages/ios_liquid_glass/lib packages/mobile/packages/ios_liquid_glass/example/lib` is empty, so they are the package as merged at `7e318a49f`:

```bash
python3 tool/glass_lab/harness/lab.py build operator
for s in material.regular material.clear material.tinted material.edge; do python3 tool/glass_lab/harness/lab.py run $s; done
python3 tool/glass_lab/harness/lab.py run material.regular --a11y reduce-transparency
python3 tool/glass_lab/harness/lab.py run material.regular --a11y increase-contrast
for s in tabbar.rest button.press navbar.inline; do python3 tool/glass_lab/harness/lab.py run $s --flutter operator; done
for r in <the nine runs>; do python3 tool/glass_lab/harness/lab.py report build/glass_lab/runs/$r; done
LG=/Users/omaraly/development/AI/Operator-ios-liquid-glass/packages/mobile/build/glass_lab/runs
python3 tool/glass_lab/harness/still_check.py $LG/20261002-200447 build/glass_lab/runs/<regular run>
python3 tool/glass_lab/harness/still_check.py $LG/20261002-201611 build/glass_lab/runs/<clear run>
python3 tool/glass_lab/harness/still_check.py $LG/20261002-151504 build/glass_lab/runs/<tinted run>
python3 tool/glass_lab/harness/still_check.py $LG/20261002-202042 build/glass_lab/runs/<edge run>
python3 tool/glass_lab/harness/still_check.py $LG/20261002-202731 build/glass_lab/runs/<reduce transparency run>
python3 tool/glass_lab/harness/still_check.py $LG/20261002-203837 build/glass_lab/runs/<increase contrast run>
python3 tool/glass_lab/harness/still_check.py $LG/20261002-205000 build/glass_lab/runs/<tabbar.rest run>
python3 tool/glass_lab/harness/still_check.py $LG/20261002-205855 build/glass_lab/runs/<button.press run>
python3 tool/glass_lab/harness/still_check.py $LG/20261002-210140 build/glass_lab/runs/<navbar.inline run>
```

Expected: `missing: 0` and `worse: 0` for each. The prototype measured: `missing: 0` and `worse: 0` in all four, on the final prototype (runs `20261003-210710`, `-212057`, `-213008`, `-213813`); all 52 Flutter frames byte-identical to 2A's and no measure moved, with Task 2 keeping the marker out of the extent (before that, `button.press`'s region stretched to the marker and its `mad` read 7.13 → 3.29 on an unchanged frame). A changed Flutter frame in a 2A material scene is a regression to find (the package changed only motion paths and two uniforms that equal 2A's at visibility 1): open the two frames and their difference before anything else. A measure that moved on an unchanged Flutter frame moved on the native side (ruling 28); print the native frame difference `still_check` lists next to it in `results-2b1.md`.

- [ ] **Step 8: The edge light below visibility 1, and the rim against native mid-transition.**

```bash
python3 tool/glass_lab/harness/rim_check.py build/glass_lab/fitvis/<Step 4 fit>/table/ramp<k> build/glass_lab/runs/<normal run>
python3 tool/glass_lab/harness/rim_check.py build/glass_lab/fitvis/<Step 4 fit>/table/ramp<k> build/glass_lab/runs/<reduce motion run>
```

Expected: in every Flutter case, the rim depth at visibility 0.3 and above equals the depth at 1 within one pixel (⅓ pt): the geometry pass's `uFullThickness` reaches the shader (finding 28; a mis-wired uniform narrows it with the ramped thickness). The native lines are ruling 14's evidence on `outlineWidth` and `specularWidth`: native's rim depth at progress 0.3–0.7 against 1. The prototype read: Flutter 0.67–1.0 pt at every visibility, within ⅓ pt of its depth at 1 from 0.3 up in all four cases; native 1.0–1.67 pt at rest, 5–24 pt at progress 0.3–0.7 in the normal run and 5.0–5.33 pt under Reduce Motion (ruling 14).

- [ ] **Step 9: Look at both ghosts.**

```bash
python3 tool/glass_lab/harness/ghost_probe.py tool.ghost
python3 tool/glass_lab/harness/ghost_probe.py tool.ghost.standalone
```

Open each printed `removal.png` (one row per frame from 50 ms before release to 350 ms after). Expected: the "Glass" label stays where it was in every frame and fades with the glass; no frame without both the glass and the label before it fades (no blink), in the container and in the `Overlay`. The prototype's probes showed the label in place and fading with the glass in each of the ten frames, in the container (`20261003-210622`) and in the `Overlay` (`20261003-210646`), and the region's mean difference from `ready.png` rising 2.29, 2.93, 5.05, 7.77, 10.08, 11.86, 13.29 … 16.93 over 250 ms with no jump; the `Overlay` probe follows the same values one frame later.

- [ ] **Step 10: Write `docs/liquid_glass/02b-motion/results-2b1.md`.** Use `results-2a1.md`'s layout: date, branch, simulator; how the numbers were read (`result.json`, `static.ready` and the `motion.*` measures); then:

1. **The Done table**, one row per spec §8 "2B.1 is done when" item:

   | Done item | Result | Evidence |
   |---|---|---|
   | 1 L1–L3, L5–L8 tested and reproducing known numbers | pass/fail per number, from Task 6 Step 6's output and Task 5 Step 7's touches; v18 (+14.33) recorded as not reproduced with ruling 2's cause; 10–90% times judged against Task 9's `t10_90_ms` noise (ruling 6) | harness test count; `reproduce.py` output |
   | 2 Noise floors for every 2B.1 scene and case | the scenes and cases in `noise.json`, motion, static and topology | the repeat run folder (Task 9) |
   | 3 N1, N2, N5, N7 and N6 (materialize) recorded | the run folders | Task 8 runs |
   | 4 Materialize passes under default, `.snappy`, `.bouncy` and Reduce Motion, per shape | progress measures passing / judged / expected, and the event and touch gates passing / expected, per scene and appearance, normal and Reduce Motion | the two Step 5 runs; `done_table.py` output |
   | 5 Still glass no worse than 2A | `missing` and `worse` per scene, Operator's three scenes included; byte-identical Flutter frame counts | Step 7 runs and `still_check.py` output |
   | 6 Gates | the four gate lines | — |

2. **Run folders**, a table like `results-2a1.md`'s: command, run folder, report counts.
3. **Every failing materialize measure, classed by cause** ("What this plan expects to reach" gives the prototype's classes and why), with evidence (a number from `result.json` and, for a model cause, a crop): (a) tunable (a fitted value), (b) model limitation (the edge spread of ruling 13), (c) lab scene, (d) measurement artifact (a stall the report lists, a fit marked invalid), (e) the debug build. No limit is loosened; a case passes only on the limits as written.
4. **Not judged, reported:** the touch-to-response delay per pair, native and Flutter, classed (rulings 8 and 33: native starts to appear 65–112 ms after the tap and to disappear 18–47 ms after it, the package 12–33 ms; reported and classed, not copied, and re-checked on a device in project 5); the frame gaps over 25 ms per app; the cold first transition of Step 6; the default-spring check of Step 4; the rim depths of Step 8.
5. **Carried to a to-do list** (`docs/liquid_glass/02b-motion/todo-2b1.md`, created here), one line per item with its class and the evidence, as `todo-2a2.md` does. It always carries: the native edge spread (ruling 13); the rim's mid-transition depth and the lens displacement against native (ruling 14's open items); the M10 performance traps (finding 22: every member notified on every animated frame, a `RepaintBoundary` per `GlassEffect`, a full extra layer per ghost or appearing glass, so removing sixteen glasses at once adds sixteen layers); container spacing animation, moved to 2B.2 with M4 (ruling 29); native's merge reach of about half its `spacing` (ruling 23), for 2B.2's M4; the curve-shape mismatch on `light` and `stripes` with its deciding measure (a per-appearance fit on `photo` alone), and the `.bouncy` settle on `light` with a per-appearance gain as its candidate fix ("What this plan expects to reach").

Every number in the file must be recomputable from a `result.json` or a command in this plan.

- [ ] **Step 11: Run every gate and record the lines.**

From `packages/mobile`: `flutter analyze --no-pub`, `flutter test --no-pub` (expect `+2146: All tests passed!`), `python3 -m unittest discover tool/glass_lab/harness/tests` (expect `Ran 175 tests` … `OK`); from the package: `flutter analyze --no-pub`, `flutter test --no-pub` (`+121`); from the example: the same (`+13`). Check `xcrun simctl spawn 708879DD-8B2A-4547-863F-F49EE1474D8B defaults read com.apple.Accessibility ReduceMotionEnabled` prints `0`.

- [ ] **Step 12: Commit.**

```bash
git add docs/liquid_glass/02b-motion/results-2b1.md docs/liquid_glass/02b-motion/todo-2b1.md
git commit -m "docs(mobile): 2B.1 results: the Done table, still glass against 2A, failures by cause

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 21: Documents

**Files:**
- Modify: `docs/liquid_glass/ROADMAP.md`, `packages/ios_liquid_glass/README.md`, `packages/ios_liquid_glass/FORK.md`, `packages/ios_liquid_glass/CHANGELOG.md`, `tool/glass_lab/README.md`

**Interfaces:**
- Consumes: `results-2b1.md` (Task 20).
- Produces: the ROADMAP's status row, §4 gotchas 10 and 13 corrected from the spike and gotchas 35–46 added, §6 2B's 2B.1 subsection, §9's next step; the package README's motion section (insertion and removal rules, the `Overlay` ghost, scrolling, material from the drawn size, the global `withGlassAnimation` transaction) and SwiftUI table rows; `FORK.md`'s 2B.1 changes; `CHANGELOG.md`'s 2B.1 entries; the lab README's new commands, fields, marker, native stamp and per-shape measures.

- [ ] **Step 1: Apply the documents as the prototype wrote them.** These patches carry `development`'s text as context; if the main session changed a line they touch (the ROADMAP's status row is the likely one), `git apply --3way` merges it (Execution setup):

```bash
git apply --3way <<'PATCH'
diff --git a/docs/liquid_glass/ROADMAP.md b/docs/liquid_glass/ROADMAP.md
index d69b55685a0cf9927ab1c6b81ca09be200504629..f5d5b4237292139c029c206ee32177007b6a0a59 100644
--- a/docs/liquid_glass/ROADMAP.md
+++ b/docs/liquid_glass/ROADMAP.md
@@ -1,6 +1,6 @@
 # ios_liquid_glass: master roadmap
 
-Last updated: 2026-10-02. Owner: Omar Aly (the user). This is the single source of truth for the whole Liquid Glass effort. Every other document in `docs/liquid_glass/` hangs off it.
+Last updated: 2026-10-03. Owner: Omar Aly (the user). This is the single source of truth for the whole Liquid Glass effort. Every other document in `docs/liquid_glass/` hangs off it.
 
 **Status at a glance**
 
@@ -9,7 +9,7 @@
 | 1 | Reference lab (measuring instrument) | **DONE**, merged to `development` (`7f74f5a0b`), not pushed |
 | 2A | Package foundation + how glass looks | **DONE**, merged to `development` on 2026-10-02 (2A, 2A.1 and the review fix wave). Done item 3 passes 10 of 20 cases, item 4 5 of 6, item 5 17 of 20, item 6 22 of 32 measures, item 8 passes. Results: `docs/liquid_glass/02a-looks/results-2a1.md`. |
 | 2A.2 | Static-look polish (shader residuals) | TODO, not planned: `docs/liquid_glass/02a-looks/todo-2a2.md` |
-| 2B | How glass moves | **SPEC APPROVED** (2026-10-03); the 2B.1 plan is being written (`02b-motion/plan-2b1.md`). Spec `02b-motion/spec.md`; every decision is in `02b-motion/brainstorm.md`; native interactive spike in `02b-motion/spike-interactive.md`; research brief `02b-motion/context.md`. Three plans (2B.1–2B.3) follow, one at a time. |
+| 2B | How glass moves | **2B.1 EXECUTED** on `feat/ios-liquid-glass-2b1`, awaiting review: the lab measures motion per shape, the native references N1, N2, N5, N7 and the materialize Reduce Motion runs are recorded with noise floors, and the package has its coordinator with materialize. Results: `02b-motion/results-2b1.md`. Plan `02b-motion/plan-2b1.md`; spec `02b-motion/spec.md`. 2B.2 (merge, union, morph) is planned after 2B.1 merges. |
 | 3 | Every iOS component inside the package | NOT STARTED |
 | 4 | Operator adopts the package | NOT STARTED |
 | 5 | Real-device verification pass | NOT STARTED |
@@ -158,10 +158,10 @@
 7. **XCUITest touch timing jitters.** Motion limits are max(fixed threshold, 1.5 × native-vs-native noise). Still images are exact (0.00 between native takes).
 8. **Glass box matching.** Faint glass (dark glass on black, white on white) shows only its contents. The harness therefore matches Flutter's shapes to the native element they overlap, and widens native to its parts, never to a full-screen dim layer. This fix is commit `caf1991ab`. Before it, the baseline reported fake 130–300 pt placement errors.
 9. **Spring fits must use each app's full event.** Fits on lag-trimmed curves moved with the alignment (fixed in `caf1991ab`).
-10. **Native `.glassEffect(.regular.interactive())` shows no visible press reaction** to XCUITest touches on the iOS 27 simulator. Six variants were tried and the touches do arrive. `.buttonStyle(.glass)` does react.
+10. **Native `.glassEffect(.regular.interactive())` reacts to presses on the iOS 27 simulator only when the glass holds rendered content that the touch hits** (a `Text`, a `Button` label, or `Color.white.opacity(0.001)`). With only `Color.clear` inside, the touch hits nothing in the effect and UIKit's `_UIFlexInteractionPanGestureRecognizer` never joins it, so nothing reacts; that was the old `material.interactive` (`02b-motion/spike-interactive.md`, 58 launches, XCUITest and HID touches alike). Since 2B.1 `material.interactive` holds v13's `Color.white.opacity(0.001)` and reacts: 252.0 × 88.67 → 264.0 × 93.33 pt on `dark-stripes`. `.buttonStyle(.glass)` and interactive `.glassEffect` press identically at the same size.
 11. **On iOS 27 the search tab sits inside the tab bar capsule** as a fourth item; on 26.5 it was a separate circle. The native tab bar measures x 20, y 791, 362 × 62 pt.
 12. **Flutter's `find.bySemanticsIdentifier` needs `tester.ensureSemantics()`.** Flutter semantics identifiers and labels do reach XCUITest.
-13. **Color.clear in SwiftUI is not hit-testable** unless it has a content shape. This did not explain gotcha 10.
+13. **Color.clear in SwiftUI is not hit-testable** unless it has a content shape, but a content shape (or a SwiftUI gesture) does not make interactive glass react: only rendered content does (spike v12, v14, v2, v9; gotcha 10).
 14. **A scroll view whose content is an `Image.file` has no height at first layout**, so `ScrollController(initialScrollOffset:)` clamps to 0. Jump to the offset after the image's first frame (2A prototype, edge scenes).
 15. **Accessibility changes reach a running app live on the simulator:**
     - `defaults write com.apple.Accessibility EnhancedBackgroundContrastEnabled` (Reduce Transparency) and `ReduceMotionEnabled`;
@@ -186,6 +186,18 @@
 32. **Never `ceil()` a pixel-snapped extent.** Floating point makes 760 px into 760.0000000000001 and the geometry image one pixel too big, which drops the last lit column and row of glass at fractional positions (2A.1, `toPixelCount`).
 33. **A `saveLayer` per shadow is expensive under Impeller.** Thirteen offset shadows cut out with `saveLayer` + `dstOut` measured 14.72 ms raster median on the simulator against 12.62 ms with shadows off (2.1 ms); a difference clip measured 13.04 ms (0.4 ms) (2A.1 prototype: 14.72 ms is the prototype's own `Operator-2a1-proto/packages/mobile/build/glass_lab/perf-2a1.json` and 13.04 ms its `perf-2a1b.json`, neither the same file as this branch's `perf-2a1.json`; 12.62 ms is from the prototype's shadows-off probe, recorded in `PROTOTYPE-2A1.md` and `plan-2a1.md` header ruling 16, because its `perf_variants.py` is not on disk).
 34. **Native tone points can be read off native captures alone** (`lab.py tonefit`). Tune tone on all five backdrops, never on three: 2A's light rows missed `photo` by 20–35 luma (2A.1).
+35. **H.264 rings at every backdrop edge in every video frame** (1–3 px lines of up to 87 levels at the stripe boundaries x = 67, 201 and 335 pt). A glass box found against the bare screenshot with a fixed threshold therefore spans the whole region on `stripes`; `track.py` raises the threshold by the backdrop's own edge strength (2B.1 ruling 1). The cost is a blind band: within ±2 px (±0.67 pt) of a backdrop edge stronger than about 20 levels a dim rim can be hidden (v18's left rim sat under a threshold of 92), so the tracker flags box edges in that band (`edge_in_band`); fit size laws on `photo`.
+36. **The overview window let the app's teardown frame into every capture**, as a final one-frame "event" (the old `tabbar.drag` `event2` noise). Nothing after the last frame that matches `settled.png` is analysed now (2B.1).
+37. **A removed widget's render objects are detached before `State.deactivate`, but a `RepaintBoundary`'s layer lives until `finalizeTree`**, so `deactivate` can still snapshot the content's last painted frame with `toImageSync`. A `LayoutBuilder` is the one element that may be marked dirty during build (it rebuilds in layout), which is how the removal ghost appears in the removal frame (2B.1 ruling 15).
+38. **The debug JIT stalls the first frame that runs new code.** The first ghost or appearing-glass frame of a launch dropped a frame (a 28–33 ms gap), after which Flutter's first changed frame sat at progress 0.735 against native's 0.963 (prototype run `20261003-042321`). `align.stalls` skips each event's first gap, so it cannot see this; `done_table.py` compares each app's first changed frame instead. The example's materialize scenes run their transition once, quickly, before they are measured, and `cold_probe.py` records the cold first transition for project 5.
+39. **`flutter test` has no shader image filter**, so every `LiquidGlassLayer` in a widget test draws `FakeGlass` and no `RenderLiquidGlass` exists. Test render-level glass code by constructing its render objects; the geometry shader cannot be compiled by `flutter test`'s SkSL backend at all (gotcha 3).
+40. **Native materialize under Reduce Motion keeps its timing and its blur**; it drops the edge spread that makes the native glass box grow up to 7 pt taller mid-transition, and `.bouncy` overshoots more (2.8–3.8% against 1.4–2.5%), so the package fits a Reduce Motion appear gain per preset (2B.1 rulings 11, 12 and 13).
+41. **Flutter has no hook between layout and paint, and a ticker runs before layout.** A drawn rect kept as absolute springs and compared in a paint method goes stale when its glass is only re-composited (a `ListView` item's `RepaintBoundary` on scroll). 2B.1 anchors each drawn rect to the live layout and adds offset springs, compares a size at layout and a position at the first read in a frame, and animates only after a rebuild, a structure change or a transaction (ruling 26).
+42. **An `Overlay` cannot take a new entry during build** (it is an ancestor; `setState` would assert), so standalone glass's ghost host is an `OverlayEntry` inserted after the frame in which the first standalone glass is built, not when one is removed (ruling 27).
+43. **`lab.py repeat --into` needs an absolute path.** The driver resolves a relative output path against `/` (`The file “ready.png” doesn't exist` in `bare/driver.log`).
+44. **`State.deactivate` runs in the build phase; read no render transform there.** An ancestor can be a fresh render object not yet laid out (a route's `FractionalTranslation` in the first frame), and `getTransformTo` through it asserts, replacing the screen with Flutter's error until the next rebuild. A warm-up transition hides it; `cold_probe.py` found it (2B.1 ruling 31).
+45. **`align.extent` returns one box around every changed tile, so anything else that changes on screen joins it.** The touch marker's colour changes stretched `button.press`'s still region from the glass to the bottom-left corner and moved its measures on an unchanged Flutter frame; `extent` now takes `ignore=` and the analysis passes the marker.
+46. **A move rule keyed on rebuilds makes app-driven motion lag.** Most `GlassEffect`s are rebuilt on every frame of a `setState` drag or an `AnimatedBuilder`, so "animate a change that follows a rebuild" sprang every frame's step and the glass trailed its layout by up to 130 pt. 2B.1 follows a glass whose layout changes on consecutive frames and animates only a single change (ruling 32); the first frame of a motion still holds, because it cannot be told from a single change.
 
 ---
 
@@ -376,22 +388,23 @@
   - Operator's stamped sources omit its path-dependency packages `packages/xterm` and `speech_to_text` (`tool/glass_lab/harness/build.py`, `SOURCES`).
 
 
-### Project 2B: How glass moves (SPEC APPROVED 2026-10-03: `02b-motion/spec.md`; 2B.1 plan in progress)
-- **Read first:** `docs/liquid_glass/02b-motion/brainstorm.md`. It holds where the brainstorm stands, the question queue with my recommendation for each, the approaches and Done criteria I intend to propose, and the process. Then `02b-motion/context.md`, the research brief cited by file:line and run folder. The analysis scripts are in `02b-motion/research/`.
-- **Pending:** question 1, the press-response reference: A, B or C (recommendation A).
-- **Scope:**
-  - interactive press response: scale up, bounce, glow spreading to neighbouring glass in the same container, drag stretch;
-  - materialize and dematerialize, by ramping lensing, blur and highlight rather than alpha;
-  - shape merging with container spacing, union, identity morph (`glassEffectID` equivalent);
-  - re-tuned springs for any glass the package owns;
-  - Reduce Motion (no elasticity; fades instead of blur ramps).
-- **Measured native data to start from** (`noise.json`, baseline):
-  - menu open width spring response about 0.26–0.30 s, damping 0.74–0.81 (fit error about 0.03);
-  - tab bar drag width response about 0.27–0.34 s, damping about 0.37–0.40.
-  - Native materialize and dematerialize are about 250 ms and 350 ms in a third-party 120 fps capture (research/apple-inventory §2.13). **The lab's own native scene measures the reverse**: appear about 285–320 ms, disappear about 117–167 ms (10–90%), per `02b-motion/context.md` §1.
-  - Native glass button press (`button.press`, `.buttonStyle(.glass)`): width grows about +16–17 pt, a fixed outset; the release spring has response 0.18–0.34 s and damping 0.61–0.91. Native `material.interactive` has 0 events in every case.
-- **Lab scenes:** `material.interactive` (see the pending decision), `material.materialize`, `material.merge`, `material.union`, `material.morph`, `tabbar.press`, `tabbar.drag`, `button.press`.
-- **Next:** continue the brainstorm in `02b-motion/brainstorm.md` (question 1 is pending), then write `02b-motion/spec.md`.
+### Project 2B: How glass moves (2B.1 executed, awaiting review; spec `02b-motion/spec.md`)
+
+#### 2B.1: the instrument and the first motion
+- **Plan:** `02b-motion/plan-2b1.md` (21 tasks; 33 rulings in its header, each with prototype evidence; written, reviewed and fixed twice before execution). Prototype: worktree `/Users/omaraly/development/AI/Operator-2b1-proto`, branch `proto/2b1` (throwaway, never merged).
+- **Branch:** `feat/ios-liquid-glass-2b1`. **Results:** `02b-motion/results-2b1.md` (the spec §8 2B.1 Done table, with run folders; still glass against 2A, Operator's scenes included; failures classed by cause; delays, stalls and the cold first transition reported). **To do:** `02b-motion/todo-2b1.md`.
+- **Lab:** `track.py` (per-shape boxes against the bare frame with an edge-aware threshold and a flagged blind band; progress, residual and sharpness; topology), `touch.py` (marker), `shapes.py` (teardown cut, events by step, per-shape comparison; an absent measure, an unpaired event or a missing touch fails), `fitvis.py` (per-preset materialize mapping, blur ramp, visibility table, default-spring check), `lab.py measure | reboot | fitvis`, per-case `repeat` over two sessions with static and topology noise, a native build stamp, `reproduce.py`, `still_check.py`, `done_table.py`, `rim_check.py`, `ghost_probe.py`, `cold_probe.py`.
+- **Native references:** `material.interactive` (v13), `material.press.*` (N2), `material.materialize.snappy|bouncy` (N5), `material.spacing.*` (N7), Reduce Motion materialize runs (N6).
+- **Package:** `GlassAnimation` (SwiftUI's presets), `withGlassAnimation`, `GlassAnimationScope`, `GlassEffectTransition.materialize|identity`; a coordinator per container and per standalone glass (insertion and removal by one rule, removal ghosts with a content snapshot, in the container or the nearest `Overlay`; drawn rects anchored to the live layout, a single change animated after a rebuild or a transaction, app-driven motion followed exactly, never behind a scroll); each glass's material from its drawn size; the fitted `ios27_motion.dart`; the edge light keeps the full thickness while glass materializes.
+- **Measured native facts:** appear progress is the animation's spring, overshooting by a fitted share of the spring's overshoot (`snappy` 0, `bouncy` 0.34, and 0.62 for `bouncy` under Reduce Motion); disappear is the spring's remainder to a fitted power (default 3.1, `snappy` 2.7, `bouncy` 2.75); the backdrop blur ramps as visibility^3; Reduce Motion keeps materialize's timing and blur; native starts to appear 65–112 ms after a tap and to disappear 18–47 ms after it; the 250 × 44 press grows about +15 pt, not +17.67; native's merge reach is about half its `spacing`.
+- **User rulings:** the touch-to-response delay is reported and classed, not copied and not judged; project 5 re-checks it on a device (2B.1 ruling 33). A glass the app moves on consecutive frames follows its layout exactly, and a single change animates (2B.1 ruling 32).
+- **Open for 2B.2:** animated container spacing with M4 (2B.1 ruling 29), calibrated on the merge reach above; `.matchedGeometry`, ids, union; whether appearing glass merges with neighbours.
+- **Open model items:** native's mid-materialize edge spread (rulings 12, 13); the lens displacement mid-transition (ruling 14); whatever `results-2b1.md` classes as (b).
+
+#### What 2B as a whole covers (spec §2, §4)
+- **Plans:** 2B.1 (above); 2B.2 merge, split, union and morph; 2B.3 press, Reduce Motion everywhere, frame cost. Each is written prototype-first after the previous one merges.
+- **Native facts carried from before 2B.1:** menu open width spring 0.26–0.30 s / 0.74–0.81 (reproduced by the 2B.1 lab); tab bar drag width 0.27–0.34 s / 0.37–0.40; a third-party capture's materialize 250 / 350 ms runs the other way from the lab's 275–292 / 117–133 ms; the glass button press grows +16 pt at 53 pt tall, and plain interactive glass presses like it once it holds rendered content (gotcha 10).
+- **Lab scenes for 2B:** `material.interactive`, `material.press.*`, `material.materialize*`, `material.spacing.*`, `material.merge`, `material.union`, `material.morph`; `tabbar.press`, `tabbar.drag` and `button.press` stay project 3 component references.
 
 ### Project 3: Every iOS component inside the package (NOT STARTED)
 - **Scope:** everything in §7 marked project 3.
@@ -553,13 +566,7 @@
 
 ## 9. Exact next steps
 
-1. **Project 2B (how glass moves) is being brainstormed.** Read `docs/liquid_glass/02b-motion/brainstorm.md` and do exactly what it says next:
-   - get the user's answer to question 1 (the press-response reference: A, B or C; recommendation A);
-   - then ask questions 2–7 one at a time, each multiple choice with the recommendation first;
-   - then propose the approaches;
-   - then present the design in sections;
-   - then write `docs/liquid_glass/02b-motion/spec.md`, which the user approves;
-   - then the plan, prototype-first.
+1. **2B.1 is executed and awaits review** (§5 step 4): rerun every gate, run an independent code review against `02b-motion/plan-2b1.md` and an independent measurement audit that recomputes `results-2b1.md` from `result.json` and looks at full-resolution crops; fix, re-measure, and merge only when the user says. Then write the 2B.2 plan (merge, split, union, morph), prototype-first, from the merged baseline.
 2. **2A.2 (static-look polish)** is a to-do list, not yet planned: `docs/liquid_glass/02a-looks/todo-2a2.md`. The user decides when, likely alongside project 3, since the tinted rings are a prominent-button detail.
 3. **Pending user decisions:**
    - native `material.interactive` (§1), which 2B question 1 settles;
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/README.md b/packages/mobile/packages/ios_liquid_glass/README.md
index 011df95e984ad0de9a4c6440f06778458b049d4e..4797a53ae36f84902cc7b6961929f523b968f1b9 100644
--- a/packages/mobile/packages/ios_liquid_glass/README.md
+++ b/packages/mobile/packages/ios_liquid_glass/README.md
@@ -29,11 +29,39 @@
 | `.glassEffect(.clear)` | `GlassEffect(glass: Glass.clear, ...)` |
 | `.glassEffect(.regular.tint(.green))` | `GlassEffect(glass: Glass.regular.tint(green), ...)` |
 | `.glassEffect(.identity)` | `GlassEffect(glass: Glass.identity, ...)` |
-| `.glassEffect(.regular.interactive())` | `Glass.regular.interactive()` (motion arrives in a later version) |
+| `.glassEffect(.regular.interactive())` | `Glass.regular.interactive()` (the press arrives in a later version) |
 | `.glassEffect(in: .circle)`, `.rect(cornerRadius:)`, capsule | `GlassShape.circle()`, `GlassShape.rect(r)`, `GlassShape.superellipse(r)`, `GlassShape.capsule()` |
 | `GlassEffectContainer(spacing:)` | `GlassEffectContainer(spacing: 20, child: ...)` |
+| `.glassEffectTransition(.materialize)`, `.identity` | `GlassEffect(transition: GlassEffectTransition.materialize)`, `GlassEffectTransition.identity` |
+| `Animation.default`, `.snappy`, `.bouncy`, `.smooth` | `GlassAnimation.defaultSpring`, `.snappy`, `.bouncy`, `.smooth` |
+| `.spring(duration:bounce:)`, `.spring(response:dampingFraction:)` | `GlassAnimation.spring(duration:, bounce:)`, `GlassAnimation.dampedSpring(response:, dampingFraction:)` |
+| `withAnimation(.bouncy) { ... }` | `withGlassAnimation(GlassAnimation.bouncy, () => setState(...))` |
+| (no equivalent) | `GlassAnimationScope(animation: ..., child: ...)`, a default for a subtree; `GlassAnimation.none` turns animation off |
 | `.scrollEdgeEffectStyle(.soft / .hard / .automatic)` | `ScrollUnderBars(style: ScrollEdgeStyle.soft, child: ...)` or `ScrollEdgeEffect(...)` |
 | the 35% dimming layer under clear glass | `GlassDimming(child: ...)` |
+
+### Motion
+
+Glass materializes when it appears and dematerializes when it is removed, as native glass does: the lens, frost, tone and edge light ramp in and out while the content fades, rather than the whole glass fading. A removed glass keeps drawing, with a snapshot of its content, until it has gone. Glass that moves or changes size springs from where it was drawn to where it is laid out; its content follows it, and taps go to the new layout at once.
+
+```dart
+GlassEffectContainer(
+  child: shown ? GlassEffect(child: label) : const SizedBox.shrink(),
+)
+
+withGlassAnimation(GlassAnimation.snappy, () => setState(() => shown = !shown));
+```
+
+Changes animate by default with `GlassAnimation.defaultSpring`. `withGlassAnimation` applies its animation to every glass change built in the next frame, including one an unrelated `setState` causes in that frame, as a SwiftUI transaction does; otherwise the nearest `GlassAnimationScope` applies; otherwise the default. `GlassAnimation.none` and `GlassEffectTransition.identity` change at once. The presets are SwiftUI's springs: `defaultSpring` 0.55 s, `smooth` 0.5 s, `snappy` 0.5 s with bounce 0.15, `bouncy` 0.5 s with bounce 0.3.
+
+What animates:
+- **Insertion and removal.** A glass materializes when it is built into a layout that already existed (`if (shown) GlassEffect(...)` inside a container, a `Row` or a `SizedBox`), or inside `withGlassAnimation`. Glass built together with its parent (a page, a tab, a new subtree, a list item scrolled into view) appears at once, as does `if (shown) Padding(child: GlassEffect(...))` outside `withGlassAnimation`. Removal mirrors it: a glass removed on its own dematerializes; one that leaves with its parent or its page goes at once.
+- **Moves and resizes.** A single layout change animates when the glass widget was rebuilt, when its container gained or lost a glass, or inside `withGlassAnimation`. A glass whose layout changes on consecutive frames (frames drawn one after the other, at most 50 ms apart) is moved by the app, by a drag, its own animation or the keyboard, and follows its layout exactly: its first changed frame is taken as a single change and holds the glass where it was, and from the second it sits on its layout, covering both frames' movement in one step. It animates again after a frame without a change. Inside `withGlassAnimation` changes animate even on consecutive frames. The cost: two separate changes on back-to-back frames are taken as motion, so the second lands at once and drops the first one's spring. Scrolling never animates: glass in a scroll view moves with the content in the same frame. A `const` glass whose parent changed jumps unless the change is inside `withGlassAnimation`. A container that re-centres in its parent (a centred `Row` that gains an item) animates its glass; anything that moves the container's parent moves the glass at once.
+- **Glass outside a container** transitions too. Its ghost is drawn in the nearest `Overlay`, above that overlay's routes; without an `Overlay` (no `MaterialApp`, `CupertinoApp` or `WidgetsApp` above it) it appears and disappears at once.
+
+The timing is native's, measured on the iOS 27 simulator. Appearing glass follows the animation's spring and overshoots where the spring does, scaled by a fitted gain (0 for `snappy`, 0.34 for `bouncy`; the default spring does not overshoot, so it needs none); disappearing glass follows the spring's remainder to a fitted power (3.1 for the default, 2.7 for `snappy`, 2.75 for `bouncy`), which is why removal is about twice as fast as insertion. An app's own spring uses the preset nearest its damping. The backdrop blur ramps as visibility to the power 3. The numbers ship as a table, `ios27_motion.dart`, written by the lab. Under Reduce Motion native keeps materialize's timing and blur and overshoots more, so glass that begins to appear under Reduce Motion takes a second fitted gain (0.62 for `bouncy`).
+
+Each glass resolves its material (tone, frost, edge light and shadow) from its drawn size at layout and on every animated frame, so a glass growing from 44 to 200 pt changes its shadow as it grows. Container spacing does not animate yet.
 
 ### Theme
 
@@ -60,7 +88,7 @@
 
 ### Size
 
-Native glass changes with its size: a 200 pt glass casts a long soft shadow (sigma about 17 pt) where a 44 pt one casts almost none, and its tone and frost differ too. `GlassEffect` measures itself and interpolates the tuned material between the 44, 88 and 200 pt anchors on its shorter side. Pass `sideHint` to avoid a one-frame default before the first layout.
+Native glass changes with its size: a 200 pt glass casts a long soft shadow (sigma about 17 pt) where a 44 pt one casts almost none, and its tone and frost differ too. `GlassEffect` resolves the tuned material from its drawn size, interpolated between the 44, 88 and 200 pt anchors on its shorter side, at its first layout and whenever it changes size; no frame is painted with a guess. `sideHint` is the size its first build uses before that layout.
 
 Inside a `GlassEffectContainer`, every grouped child shares the container's single glass layer, so the layer's settings (tone, frost, edge light) are resolved once from the container's own `side` (default 88). Each child's shadow still comes from its own measured size.
 
@@ -70,7 +98,7 @@
 
 ### Low level
 
-The renderer underneath is still public: `LiquidGlass`, `LiquidGlassLayer`, `LiquidGlassSettings`, `LiquidGlassBlendGroup`, `FakeGlass`, `GlassGlow` and `LiquidStretch`. `GlassMaterial.resolve(...)` returns the tuned material for any glass, size, appearance and accessibility state, and `toSettings()` turns it into `LiquidGlassSettings`.
+The renderer underneath is still public: `LiquidGlass`, `LiquidGlassLayer`, `LiquidGlassSettings`, `LiquidGlassBlendGroup`, `FakeGlass`, `GlassGlow` and `LiquidStretch`. `LiquidGlassSettings.atVisibility(v)` gives the settings glass draws with at materialize visibility `v`. `GlassMaterial.resolve(...)` returns the tuned material for any glass, size, appearance and accessibility state, and `toSettings()` turns it into `LiquidGlassSettings`.
 
 ## How the look is made
 
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/FORK.md b/packages/mobile/packages/ios_liquid_glass/FORK.md
index c97b62ae16209a98b5b1255f3094ec1a697bde66..cf2ac2b9aa8e8257076e2a2e5b8c5dd55ac29161 100644
--- a/packages/mobile/packages/ios_liquid_glass/FORK.md
+++ b/packages/mobile/packages/ios_liquid_glass/FORK.md
@@ -79,6 +79,14 @@
 - `scroll_edge_blur.frag` is replaced by `scroll_edge_mask.frag`. `ScrollEdgeEffect` stacks real Gaussians (`ImageFilter.compose` of a blur and the mask shader) and paints the dim, cap and divider line itself.
 - `GlassMaterialOverride` takes an optional `side`; `resolveGlassMaterial` applies overrides only to glass at that size anchor.
 
+## ios_liquid_glass 0.1.0, project 2B.1 (motion)
+
+- `LiquidGlassLayer` takes optional internal `visibility` (an animation) and `settingsSource` (a `GlassMaterialSource`) parameters, carried by `LiquidGlassRenderScope`. `RenderLiquidGlassLayer`, `RenderLiquidGlassBlendGroup` (through `RenderLiquidGlassGeometry`) and the glass shadow listen to them: the source replaces the layer's settings, and the visibility is multiplied into `LiquidGlassSettings.visibility` (held at 0 below, not capped above) with the blur ramped as visibility to `ios27BlurRampExponent` (`LiquidGlassSettings.atVisibility`, new public API, which the lab's `tool.visibility` scene uses too); the content fades through a `FadeTransition` on it. Without them the layer draws exactly what it drew before.
+- `RenderLiquidGlass` takes an optional internal `GlassShapeMotion`. The blend group gathers the shape's drawn rect from it instead of its layout rect, `getPath()` follows it, and the content is painted translated by the drawn rect's centre offset; layout and hit testing are unchanged. `LiquidGlass.grouped` and `LiquidGlass.withOwnLayer` gain internal `motion`, `visibility`, `settingsSource` and `shadowSource` parameters; the glass shadow reads its shadows from `shadowSource` when given.
+- `liquid_glass_final_render.frag` reads the material's full thickness from `uOptics.w`: the signed distance is decoded with the full-thickness reach, the dispersion bevel keeps the ramped thickness, and the edge line and sheen take their width from the full thickness. `liquid_glass_geometry_blended.frag` gains `uFullThickness` (float 103) and encodes the signed distance with the same reach. At visibility 1 both are the ramped thickness, so still glass is unchanged byte for byte.
+- `GlassMaterialOverride` gains `scopeOf` and `valuesFor`, and `glassMaterialResolver` builds a pure function of the side from a context, so a glass can re-resolve its material without one.
+- New, not from upstream: `lib/src/motion/` (`GlassAnimation`, `withGlassAnimation`, `GlassAnimationScope`, the springs, the frame counter, the material source, the motion coordinator, members, ghosts, the `Overlay` ghost host and their widgets, the materialize mapping, the fitted `ios27_motion.dart` table), `lib/src/api/glass_effect_transition.dart`; `GlassEffectContainer` becomes stateful and owns the coordinator; `GlassEffect` joins it (or a private one), keeps its content in a snapshot boundary, takes a `transition`, and no longer measures itself with a post-frame `setState`.
+
 Record every later change to `lib/` in this file.
 
 Upstream: https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/packages/ios_liquid_glass/CHANGELOG.md b/packages/mobile/packages/ios_liquid_glass/CHANGELOG.md
index 915ae25d26e367f68d80059b68c8afbbbbd5781b..08cbb1f51d829df4b8e952093aae135c13d7758b 100644
--- a/packages/mobile/packages/ios_liquid_glass/CHANGELOG.md
+++ b/packages/mobile/packages/ios_liquid_glass/CHANGELOG.md
@@ -14,6 +14,13 @@
  - (2A.1) **FIX**: `Glass.clear.tint(c)` stays untinted under Reduce Transparency and Increase Contrast, and its foreground is not the tinted one.
  - (2A.1) **FEAT**: `GlassMaterialOverride.side` limits debug overrides to one size anchor.
  - (2A.1) **FIX**: glass thinner than its outline band (thickness below `outlineWidth` + 1 px, as at the start of a visibility ramp) covers its interior fully and draws its outline only outside it, instead of a half-covered, darkened body.
+ - (2B.1) **FEAT**: glass materializes and dematerializes with native's timing, in a `GlassEffectContainer` and on its own; a removed glass keeps drawing with a snapshot of its content until it has gone (glass outside a container in the nearest `Overlay`).
+ - (2B.1) **FEAT**: `GlassAnimation` (`defaultSpring`, `snappy`, `bouncy`, `smooth`, `spring`, `dampedSpring`, `none`, SwiftUI's springs), `withGlassAnimation` and `GlassAnimationScope`; how far glass has materialized follows a per-animation mapping fitted to native on the iOS 27 simulator.
+ - (2B.1) **FEAT**: `GlassEffect(transition: GlassEffectTransition.materialize | .identity)`.
+ - (2B.1) **FEAT**: glass that moves or resizes after a rebuild springs its drawn rect; content follows, taps go to the new layout, and scrolling never lags. Glass the app moves on consecutive frames (a drag, its own animation) follows its layout exactly.
+ - (2B.1) **FEAT**: `LiquidGlassSettings.atVisibility(v)`, the settings glass draws with at materialize visibility `v`.
+ - (2B.1) **FEAT**: `GlassEffect` resolves its material from its drawn size at layout and on every animated frame, instead of one frame after layout.
+ - (2B.1) **FIX**: the edge line and sheen keep their full width while the lens ramps with `visibility`; still glass is unchanged.
 
 ## 0.2.0-dev.4
 
PATCH
```

```bash
git apply --3way <<'PATCH'
diff --git a/packages/mobile/tool/glass_lab/README.md b/packages/mobile/tool/glass_lab/README.md
index 3bfd23f64bcfcc036fb755aaaf340ae0f77147cd..3f1f805a690dc9e7356d707618743da3ee50c0cd 100644
--- a/packages/mobile/tool/glass_lab/README.md
+++ b/packages/mobile/tool/glass_lab/README.md
@@ -44,7 +44,10 @@
   - `--flutter example|operator`, where `flutter` means the example app unless you pass `--flutter operator`.
 - **`report [<run dir>]`** analyses a run and writes `report.html` beside it. With no argument it uses the latest run.
 - **`summary <out.md> [<run dir>]`** writes a Markdown summary of a run.
-- **`repeat [<scene>] [--times 3]`** records native takes and compares them to each other, then updates `noise.json`. With no scene it covers `material.regular`, `tabbar.rest`, `tabbar.drag` and `menu.bar`. Rerun it after an Xcode or simulator update.
+- **`repeat [<scene>] [--times 3] [--appearance A] [--backdrop B] [--a11y MODE] [--into RUN]`** records native takes of every case of a scene and compares every pair of takes of a case (`pair-<i>-<j>`, each take captured once), then writes that case's noise into `noise.json` as `{scene: {case: {measure: noise}}}`: the motion measures, and the static and still-topology measures (`ready.mad`, `ready.topology.<region>.neck_pt`, …), so still scenes get noise floors too. A non-finite value never becomes a noise. `--into` appends takes to an earlier run (give it an absolute path: the driver resolves a relative one against `/`), so a case's noise covers takes from two sessions (record three, `reboot`, record two more `--into` the same run). With no scene it covers `material.regular`, `tabbar.rest`, `tabbar.drag` and `menu.bar`. Rerun it after an Xcode or simulator update.
+- **`reboot`** shuts the iOS 27 simulator down, boots it again and resets the status bar.
+- **`measure <case dir> --scene <id>`** prints, for each app in a case folder, the touches read from the marker, each tracked shape's rest box (the last frame before the first touch), its largest and smallest box and whether an edge of either sat inside the tracker's blind band at a backdrop edge (`edge_in_band`), and each event's onset, owning step and progress features.
+- **`fitvis <run> [<run> ...] [--levels 11] [--ramps 1.0,2.0,3.0,4.0] [--out DIR] [--write]`** fits the materialize motion table from native recordings (a run's `<scene>/<case>/native` and a `repeat` run's takes). The springs stay SwiftUI's; it fits, per preset and over every backdrop and take, the disappear exponent and the appear overshoot gain, with their spread over the takes, and from the Reduce Motion cases a second appear gain (the other accessibility cases are left out), and checks that native's default fits SwiftUI's 0.55 s / 1.0 in every case (`default_spring_check`, pass or fail). It photographs the example's `tool.visibility` scene at fixed visibilities under several blur ramps, keeps the ramp whose sharpness at quarter, half and three-quarter progress best matches native's at the same progress, then inverts Flutter's progress under that ramp into `ios27VisibilityForProgress`. It writes `build/glass_lab/fitvis/<time>/fit.json` (every fit with `at_grid_edge`); `--write` rewrites `packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart`; never edit that table by hand. It refuses a stale example build and reuses scan shots already in `--out`.
 - **`geometry <scene>`** prints the native glass boxes of a scene in points, for positioning Flutter scenes.
 - **`baseline [--flutter example|operator]`** runs every scene in both apps and both appearances, plus the accessibility runs, then `report`. It takes about four hours.
 - **`tune`** searches material parameters against native (see below).
@@ -63,8 +66,10 @@
 
 Optional fields:
 - `regions`: named rectangles in points;
-- `track`: a region that pins where the scene is compared;
-- `measures`: the still-image measures that count, from `mad`, `luminance`, `rim_rms`, `bbox_pt` and `centre_pt`; all of them by default.
+- `track`: a region name, or a list of them, that pins where the scene is compared. In a scene with steps, each tracked region is a shape measured on its own (below);
+- `measures`: the still-image measures that count, from `mad`, `luminance`, `rim_rms`, `bbox_pt` and `centre_pt`; all of them by default;
+- `topology`: region names whose glass is counted and necked (spec L2): the number of separate glass components and, when they are one, the narrowest neck between its two lobes. In a still scene each topology region is compared on `ready.png` (`ready.topology.<region>.count`, limit 0, and `.neck_pt`, limit 1 pt); in a scene with steps, on join and split times and the neck over time (`topology.*` motion measures);
+- `motion`: the motion measures that count for each tracked shape, from `delay_ms`, `topology.count`, `topology.join_ms`, `topology.split_ms`, `topology.neck_rms`, `<key>.<measure>` (`width`, `height`, `cx`, `cy` or `luma`, with `peak_ms`, `settle_ms`, `overshoot_pct`, `response_pct` or `damping`) and `progress.t10_90_ms`, `.settle_ms`, `.overshoot_pct`, `.response_pct`, `.damping`, `.rms` and `.sharpness`. With none, a tracked scene is checked only for its events.
 
 For example, the edge scenes pin the top 240 pt and count only `mad` and `luminance`.
 
@@ -78,7 +83,11 @@
 - `material` is an optional map of material overrides by field name. Scroll edge fields are prefixed `edge.`;
 - `materialSide` limits the overrides to glass at that size anchor (44, 88 or 200 pt, after clamping the glass's shorter side), so a 200 pt candidate does not repaint the 44 and 88 pt glass in the same scene.
 
+`build native` stamps the native sources (`build/glass_lab/native/sources.sha256`, from `native/GlassLab` and `native/GlassLabDriver`), and `run`, `repeat` and `reproduce.py` refuse a native build older than its sources, as `run` refuses a stale Flutter build.
+
 Before each capture the harness closes every other lab app, so the captured app is launched from the home screen and no "◀ app" back link appears in its status bar.
+
+Scenes with touch steps show a touch marker in both apps, in the bare launch as well: an 18 pt square at (16, 662) pt, black at rest, red while a finger is down, green while it moves, blue on release and black again 250 ms later. The native app takes `GLASS_LAB_MARKER=1`; the example takes `"marker": true` in `launch.json`. The harness reads touch-down and touch-up from the marker's colour in the video, so touch times share the video's clock.
 
 Backgrounds live in each app's `Documents/glass_lab/`.
 
@@ -118,3 +127,15 @@
 - Each event is checked for peak time, settle time, overshoot and a fitted spring (response and damping).
 
 Motion limits are max(fixed threshold, 1.5 × `noise.json`), because touch timing on the simulator varies a little between runs. The report also lists any Flutter frame gaps over 25 ms, so a debug-build stall is not mistaken for a wrong spring.
+
+Nothing after the last frame that matches `settled.png` is analysed, so the app's teardown frame is never an event.
+
+Scenes with a `track` and steps are measured per shape:
+- each tracked region is cropped at full resolution from every video frame; the shape's box is found against the bare screenshot, with the threshold raised at the backdrop's own edges, where H.264 rings in every frame; a box edge within the 5 px of a strong backdrop edge is flagged, because the raised threshold can hide up to two pixels of rim there;
+- each frame is also projected onto the line from the bare screenshot to `ready.png` at point resolution: `progress` is the alpha of the closest alpha mix, `residual` how far the frame is from that mix, and `sharpness` its Laplacian minus the mix's, inside the rest box; a materialize that blurs reads a residual over the H.264 floor and a negative sharpness;
+- events belong to the step whose touch began last before them and pair with the other app's events of that step (`step<k>e<i>`); without a marker they pair by order (`event<i>`);
+- each pair is compared on the scene's `motion` measures; progress is compared on its 10–90% time, settle time, overshoot, a fitted spring, the RMS of the normalised curves after lag alignment, and the sharpness at half progress; `delay_ms` compares touch-to-response delays;
+- nothing passes by being absent: every measure the scene lists is judged for every pair and shape, an absent one as `inf`; an event left out of every pair fails `events.unpaired`, and a scene with touch steps fails `touches.native` or `touches.flutter` unless each video shows the expected touches; a spring fit on its grid edge or with RMS 0.15 or worse is reported as `fit_invalid` and fails;
+- `result.json` keeps both apps' frame gaps over 25 ms inside events (`native_stalls`, `flutter_stalls`) and, per pair and shape, each app's first changed frame (`first_frame`: its gap from the rest frame and its share of the travel), so a first-frame stall, which the gap list skips, shows too.
+
+Scripts beside `lab.py`: `reproduce.py materialize|press|menu` measures the 2A, spike and project 1 recordings the 2B.1 plan reproduces; `still_check.py <2A run> <new run>` compares still measures case by case and lists missing cases; `done_table.py <run>…` prints the materialize Done numbers; `rim_check.py <fitvis scan> <native run>` measures the edge light's depth below full visibility; `ghost_probe.py [tool.ghost|tool.ghost.standalone]` records a removal; `cold_probe.py <native case>` records the first transition of a launch without the warm-up.
PATCH
```

- [ ] **Step 2: Bring the numbers in line with this branch's measurements.** The prototype's text quotes its own fit (default exponent 3.1; `.snappy` 2.7, gain 0; `.bouncy` 2.75, gain 0.34 (0.62 under Reduce Motion); blur ramp 3). If Task 20 Step 4 re-fitted different values, replace them in the package README's "Motion" section and the ROADMAP's 2B.1 "Measured native facts" line with the committed `ios27_motion.dart` values. In the ROADMAP's status row and 2B.1 subsection, add one sentence with the Done counts of `results-2b1.md` (item 4 as progress measures passing out of judged and expected, normal and Reduce Motion, and the gates; item 5's `worse` and `missing`), and name `todo-2b1.md`. Also update §3's gate counts: harness **175**, package **121**, example **13**, app **2,146**.

- [ ] **Step 3: Check the documents against the code.**

```bash
grep -n "const double" packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart
grep -n "lab.py measure\|lab.py fitvis\|reboot\|sources.sha256" tool/glass_lab/README.md | head
```

Expected: the README's mapping and ramp numbers equal the table's; the lab README names every new command and the native stamp.

- [ ] **Step 4: Commit.**

```bash
git add docs/liquid_glass/ROADMAP.md packages/mobile/packages/ios_liquid_glass/README.md packages/mobile/packages/ios_liquid_glass/FORK.md packages/mobile/packages/ios_liquid_glass/CHANGELOG.md packages/mobile/tool/glass_lab/README.md
git commit -m "docs(mobile): 2B.1 in the ROADMAP, the package README, FORK, CHANGELOG and the lab README

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Self-review

- **Spec coverage (2B.1, spec §4 and §8):** L1, L2, L3 and L6 Task 1 (L1 proved on known numbers in Task 6; L2 on synthetic frames and native N7 stills); L5 Tasks 2 and 5; L7 Tasks 3, 4 and 8; L8 Tasks 6 and 9 (motion, static and topology noise); N1, N2, N5, N7, N6 (materialize) Task 8; M1 Tasks 11–17 (a coordinator per container and a private one per standalone glass, drawn rects that follow the live layout, removal with a snapshot, interruptible springs, per-frame writes with no rebuild, material following the drawn size, the 16-shape cap with ghosts outside it); M2 Task 10; M3 Tasks 12, 13 and 18 (mapping, overshoot, edge light), with the blur ramp in Tasks 7 and 11; M9 (2B.1 part) Tasks 10 and 13; M11 (materialize) Task 19; verification Task 20; documents Task 21. Not in 2B.1, as the spec orders or as ruled: L4, N3, N4, N6 beyond materialize, M4–M8, M10, and M1's per-container spacing animation (ruling 29).
- **Placeholders:** none; every code step is a file or a patch that ran in the prototype.
- **Names across tasks:** `GlassShapeMotion.resolve`, `GlassMaterialSource.resize/configure`, `GlassMember.drawn/sized/sync/rebuilt/scrollables`, `GlassMotionCoordinator.join/leave/rejoin/reattach/drop/takeGhosts`, `GlassOverlayGhosts.of`, `GlassMaterialize.progress/visibility/reverse`, `GlassMaterializeMapping.of`, `shapes.capture/compare/expected/limits/measures/summary`, `touch.read/owner/step_times/expected_touches`, `track.box/box_pixels/progress_row/topology/teardown_cut`, `fitvis.fit_mapping/spring_check/choose_ramp/table_source` are defined once and used with the same signatures.
- **Review Focus:** each of the six lines has its test in Tasks 13, 14 and 16.
