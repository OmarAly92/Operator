# Project 2B: how glass moves. Brainstorm state (no spec written yet)

Updated: 2026-10-03. Status: **brainstorming, architectural path.** The research is done (`context.md`). All seven questions are answered (2026-10-03: 1 C, 2–7 A). The question 1 spike is done (`spike-interactive.md`): plain interactive glass reacts once it holds rendered content; the reference is v13. Approach 1 chosen (2026-10-03). Next: the design in sections. Nothing about 2B is approved yet.

A fresh session continues from here. Read `docs/liquid_glass/ROADMAP.md` first, all of it, especially §5 (working rules), §6 Project 2B and §8. Then read `context.md` in this folder: the evidence brief, cited by file:line and run folder. Then this file.

## What the user wants (said, not assumed)

- The goal of the whole effort: `ios_liquid_glass` should be a Flutter package identical to native iOS 27 Liquid Glass, usable in any Flutter app. Operator is only its first consumer (ROADMAP §1). In the user's words: "I want everything, I want perfection".
- On 2026-10-02 the user said "merge it and push, then start 2B". 2A is merged and pushed (`development` at `7e318a49f`). The static-look residuals are deferred to the 2A.2 to-do list (`docs/liquid_glass/02a-looks/todo-2a2.md`).
- 2B's scope as the ROADMAP (§6 Project 2B) has it:
  - interactive press response (scale up, bounce, glow spreading to neighbouring glass in the same container, drag stretch);
  - materialize and dematerialize, done by ramping lens, blur and highlight rather than alpha;
  - shape merging with container spacing, union, and identity morph (the `glassEffectID` equivalent);
  - re-tuned springs for any glass the package owns;
  - Reduce Motion (no elasticity, fades instead of blur ramps).

## Process (the user's standing workflow, ROADMAP §5)

1. **Brainstorm, here:** ask clarifying questions one at a time (multiple choice, with my recommendation first), then propose 2–3 approaches, then present the design in sections with the user approving each.
2. **Spec:** write `docs/liquid_glass/02b-motion/spec.md` in the style of `docs/liquid_glass/02a-looks/spec.md`. Self-review it. The user approves the written spec.
3. **Plan, here, prototype-first:**
   - prove every risky piece on the iOS 27 simulator in a throwaway worktree;
   - write `docs/liquid_glass/02b-motion/plan.md` with the tested code embedded, as `plan.md` and `plan-2a1.md` did;
   - the user approves the plan.
4. **Execution:** a fresh **local** Claude Code session on the Mac, never a cloud session (one was started in the cloud once and could not reach the Mac). It runs subagent-driven, in a new worktree and branch, from a handoff prompt written here.
5. **Review, here:**
   - rerun every gate;
   - run an independent code review against the plan, using a subagent;
   - run an independent measurement audit that recomputes the Done table from `result.json` and looks at full-resolution crops, using a subagent. In 2A both audits found real errors the executing session had missed: stale-build tuning, tuning stuck at grid floors, wrong diagnoses;
   - then a fix wave, re-measure, and merge and push only when the user says.
6. **Subagents for heavy reading.** Use subagents for heavy reading and long work so the main context stays small. The user asked for this explicitly.

## Questions, asked one at a time

| # | Question | Status | My recommendation and why |
|---|---|---|---|
| 1 | **What is the native reference for press response?** (A) match `.buttonStyle(.glass)` buttons on the simulator now; (B) leave press response for a real device (project 5); (C) try harder to make plain `.glassEffect(.regular.interactive())` react on the simulator first, then fall back to A. | **Answered 2026-10-03: C.** A time-boxed native spike runs first (`spike-interactive.md` in this folder records it); if no plain `.interactive()` variant reacts, fall back to A. | **A.** Native `material.interactive` has 0 motion events in every recorded case (ROADMAP gotcha 10; `context.md` §1). `button.press` is the only measured press reference: width grows about +16–17 pt (×1.12 and ×1.09, so a fixed outset rather than a scale), and the release spring has response 0.18–0.34 s and damping 0.61–0.91. Press-down fits are weak. This also settles the old pending `material.interactive` decision: it stays a still image, and a real device checks it in project 5. |
| 2 | **What is the target timing for materialize and dematerialize?** The lab's own `withAnimation` scene measures appear about 285–320 ms and disappear about 117–167 ms (10–90%). A third-party capture said 250 / 350 ms. | **Answered 2026-10-03: A.** The package default is SwiftUI's default spring; the lab's native `withAnimation` numbers are the target; add native materialize scenes driven by `.snappy` and `.bouncy` so the progress mapping is checked under app-supplied animations too. | **The lab's measurement**: it is the instrument, and the third-party numbers run the other way. Also ask whether the package's default glass animation should mirror SwiftUI's `Animation.default`. |
| 3 | **Where is 2B's boundary with project 3?** | **Answered 2026-10-03: A.** 2B builds the package motion primitives only; components (tab bar lens, menus, a ready-made glass button) stay in project 3; Operator moves onto them in 2B only if trivial. | 2B owns the package primitives: what `Glass.interactive()` does (press outset and spring, glow, glow spreading to neighbours inside a container, drag stretch), the transitions (materialize, identity, matched geometry), container merge and split with SwiftUI `spacing` semantics, union by id, identity morph by id, the spring constants and Reduce Motion. Components stay in project 3: the tab bar lens, menus and the `button.press` component. Operator's `_PressLift` and tab bar move onto the package's interactive glass only if trivial; otherwise project 3. |
| 4 | **Are the lab's motion upgrades part of 2B?** | **Answered 2026-10-03: A.** The lab motion upgrades are 2B's first tasks; glass work starts only after them. | **Yes, as the first tasks**, because nothing can be measured without them (`context.md` §2 and §6.2): per-element tracking through pinned regions, a topology series (component count, neck width) for merge, split and union, a materialize progress and blur measure, excluding the app-teardown event, event pairing better than order alone, `lab.py repeat` noise floors for every 2B scene, and a threshold policy of max(fixed, 1.5 × noise). Native runs differ across sessions by more than `noise.json` allows. |
| 5 | **API shape**, mirroring SwiftUI. | **Answered 2026-10-03: A.** SwiftUI names with implicit animation (default spring, app override like `withAnimation`); names fixed once. | `Glass.interactive()` (exists, stored but unused); `GlassEffectContainer(spacing:)` with SwiftUI semantics (today `blend` fuses only gaps under half its value); an id plus namespace for morph, like `glassEffectID`; union by id, like `glassEffectUnion`; transitions like `glassEffectTransition(.materialize / .identity / .matchedGeometry)`. **Implicit animation**: a widget change animates with a package default spring, like SwiftUI `withAnimation`, with an override. Names are decided once and never renamed. |
| 6 | **Reduce Motion behaviour and how to measure it.** | **Answered 2026-10-03: A.** Record native Reduce Motion references for press, materialize, merge and morph and match them; Apple's guidance is only the starting guess. | No bounce or stretch, and fades instead of blur and lens ramps. Measured with `--a11y reduce-motion` runs of `button.press`, `material.materialize` and `material.merge`; native Reduce Motion references exist today only for `tabbar.drag`, `menu.bar` and `sheet.detents`. `GlassGlow` and `LiquidStretch` ignore `reduceMotion` today. |
| 7 | **Frame-cost budget for animated glass.** | **Answered 2026-10-03: A.** An animated-glass perf scene (press, materialize, merge) within 20% of the static glass scene, A/B alternating; device smoothness stays in project 5. | A new perf scene with glass animating every frame. Every animated frame reruns the geometry shader with no cache (`render_liquid_glass_geometry.dart:204-214`) plus an `Opacity` save layer. Budget: within 20% of the static glass scene on the simulator, measured A/B alternating (gotcha 16). Real 120 Hz smoothness is project 5. |

Other points the spec must settle (from `context.md` §6):
- **Edge light and lens thickness.** "Visibility as materialize" couples edge-light width to lens thickness (2A.1 open item B3). Rule on a fixed reach before tuning any ramp, and decide which fields ramp: `refractiveIndex`, `outlineWidth` and `specularWidth` do not today.
- **Blend calibration.** Calibrate `spacing` against `blend` on `material.merge`, and match native's no-merge at 16 pt in `material.union`. Groups are capped at 16 shapes, which matters for morph stacks.
- **Glow spreading.** It needs a container-level glow layer; today the glow is per shape and clipped (`liquid_glass.dart:284-288`).
- **Live example scenes.** They are static today: wire `LabButton.onTap`, use real state for materialize, merge and morph, and fix the union scene (circles, two union groups).

## Approaches (proposed 2026-10-03; the user chose 1)

1. **Recommended: a glass motion layer inside the package.**
   - A container-level coordinator animates three things with `motor` springs (motor is already a dependency):
     - glass visibility (materialize, using the existing ramp that already scales lens, blur, tone, outline, specular and shadow);
     - geometry: size, outset and position;
     - blend, for merge and split.
   - An id registry gives identity morph and union.
   - A press controller drives a fixed outset, the spring and a container-level glow.
   - Everything is implicit, SwiftUI-style, and Reduce Motion aware.
2. **Port the liquid_glass_widgets morph engine** (`research/flutter-repos.md`): a faster start, but less control and a foreign design.
3. **Explicit `AnimationController` API, no implicit animation:** simpler to build, but further from SwiftUI and more work for every app.

## Done criteria I intend to propose

- Every 2B scene's motion measures (peak time, settle time, overshoot, fitted spring response and damping, per element) are within max(fixed threshold, 1.5 × noise floor) of native.
- Rest frames still meet 2A's static results.
- Reduce Motion variants pass.
- The animated-glass frame cost is within budget.
- The example scenes are live.
- The API is documented in the package README.

## Facts to carry (details and citations in `context.md`)

- **Measured native springs:**
  - menu open: response about 0.26–0.30 s, damping 0.74–0.81;
  - tab bar drag width: response about 0.27–0.34 s, damping about 0.37–0.40;
  - glass button release: response 0.18–0.34 s, damping 0.61–0.91.
- **Harness limits today:**
  - it tracks only the largest blob, so merge, morph and materialize switch boxes mid-event;
  - it cannot measure height on stripes, topology, blur, glow or touch timing;
  - every case ends with a counted teardown event;
  - events pair by order only;
  - no 2B scene has a noise floor.
- **Package today:**
  - `isInteractive` is stored but never read;
  - the press glow is per shape and clipped;
  - `LiquidStretch` is unused;
  - `blend` is a smooth-min that fuses only gaps under k/2;
  - there is no union or identity morph;
  - animated geometry cost has never been measured.
- **Example motion scenes are static:** taps do nothing, and the union scene does not match native.

## Design sections (presented one at a time, 2026-10-03)

1. **Order of work: approved.** One spec, three plans, each executed by a fresh local session, reviewed and merged before the next plan is written.
   - 2B.1: lab upgrades (per-element tracking in pinned regions, topology, materialize progress and blur, teardown exclusion, time-based pairing, noise floors), each proven by reproducing known native numbers; new native references (materialize under `.snappy` and `.bouncy`; Reduce Motion press, materialize, merge, morph); repeat runs for noise; the coordinator with materialize as its first feature.
   - 2B.2: merge and split with SwiftUI `spacing` calibrated against native, union by id, morph by id, live example scenes, union scene fixed.
   - 2B.3: press (outset, spring, container glow spreading, drag stretch) on the spike's reference, Reduce Motion everywhere, animated perf scene within 20%, README API docs.
   - Spring constants start from native fits, then are verified in the lab.
2. **Lab upgrades and new native references: approved.** Each upgrade has synthetic-frame tests and must reproduce known native numbers first.
   - Per-shape tracking: a scene names several shapes, each in its own pinned region (today `track` is one region); width, height (working on stripes), centre and luma per shape.
   - Topology: component count and narrowest neck per frame.
   - Materialize progress (between bare and full glass) and blur against a plain alpha mix.
   - Glow spread (luma in neighbour regions) and stretch (aspect change): specified now, built at the start of 2B.3.
   - Touch-down and touch-up timestamps logged by both drivers; events paired by causing step; touch-to-response latency.
   - Teardown cut: nothing after the last settled frame.
   - Per-scene motion measures in `scenes.json`.
   - Noise floors: 5 native takes per 2B scene and case over 2 separate sessions; limit = max(fixed, 1.5 × noise).
   - New native references: materialize under `.snappy` and `.bouncy`; `--a11y reduce-motion` runs of press, materialize, merge, morph; the spike's reacting variant, if any, replaces native `material.interactive`.
3. **The coordinator: approved.**
   - Every `GlassEffectContainer` owns one; a `GlassEffect` outside any container gets a private one.
   - Members register layout rect, shape, glass id, union id, transition, interactive flag; each rebuild diffs and animates the difference.
   - Animated per member: drawn rect (springs from old to new layout, FLIP style), visibility, press outset, glow; per container: spacing.
   - Content is painted shifted to follow its glass; hit testing uses final layout (as SwiftUI).
   - Removal animates: the coordinator keeps drawing removed glass (dematerialize or morph into its id) plus a fading content snapshot; prototyped first; fallback is glass animates out and content vanishes at once; the spec records what the prototype proves.
   - Interruptible: retargets keep velocity.
   - One ticker per coordinator writes into render objects; no widget rebuild per frame; geometry is redrawn per animated frame (cost measured in 2B.3).
   - Standalone glass resolves material from its animated size every frame; container members share one material as today.
   - Springs: motor spring physics parameterised by response and damping, the same units as the lab's native fits.
4. **Press, glow and drag stretch: approved, with (a).**
   - Reference from the spike (plain interactive if any variant reacts, else `.buttonStyle(.glass)`).
   - Press down: fixed outset per side (native +16–17 pt width at 138 and 174 pt; spike's 44/250 pt controls and the new height tracker confirm); brightening (+4.6–5.2 luma glass, +17 prominent); rise, overshoot and release spring from native fits (release 0.18–0.34 s / 0.61–0.91, glass rise to 90% about 68 ms); label behaviour measured and copied.
   - Glow: starts under the finger (today's `GlassGlow` physics), drawn by the container so it spills onto neighbours in the same container, clipped to the glass shapes; new native scene: two glass buttons close together in a container.
   - Drag stretch: volume-preserving `LiquidStretch` maths moved into the coordinator; new native scene: press-and-drag on a glass button.
   - Touch: raw pointer listening that never competes in the gesture arena (inner buttons keep their taps); nested interactive glass: innermost reacts; leaving the glass or turning into a scroll releases with the release spring.
   - **(a):** anything native does not show on the simulator (glow spreading, stretch) is built from Apple's description, its constants kept in one place and marked "unverified" in spec and README, with a device check listed in project 5.
5. **Appear, merge, union and morph: approved.**
   - Materialize uses `visibility`; the asymmetric progress-to-visibility mapping is fitted on native default-animation frames, checked on `.snappy` and `.bouncy`; visibility clamps to [0, 1] unless native frames show otherwise.
   - Edge light: width follows the material's full thickness, brightness follows visibility (still glass unchanged bit for bit); native mid-appear frames check it.
   - Transitions: materialize (default; glass ramps, content fades), identity (none), matched geometry (morph by id).
   - Merge/split: SwiftUI `spacing` semantics; spacing-to-blend mapping calibrated on native `material.merge` with the topology measures; the blend formula is replaced if it cannot match native's neck; merging emerges from drawn positions.
   - Union: shared union id draws as one shape at any distance; native's union shape measured and copied; Flutter union scene rebuilt (four 64 pt circles in two pairs).
   - Morph: id plus app-created namespace; an unpartnered appearing glass emerges from existing glass in the same container (source read off native morph frames; guess: nearest); targets expand about 460–550 ms, collapse about 210 ms.
   - Live example scenes with native's tap ids (`toggle`, `merge`, `split`, `morph`).
6. **API, Reduce Motion and frame cost: approved.**
   - API: `Glass.regular.interactive()`; `GlassEffectContainer(spacing:)` with SwiftUI meaning and native's measured default; `GlassNamespace()`; `GlassEffect(id: GlassEffectID(id, ns), union: GlassEffectUnion(id, ns), transition: GlassEffectTransition.materialize | .identity | .matchedGeometry)`; `GlassAnimation` (`.defaultSpring`-style default, `.snappy`, `.bouncy`, `.smooth`, `.spring(duration:bounce:)`, `.spring(response:dampingFraction:)`, `.none`); `withGlassAnimation(animation, () => setState(...))`; `GlassAnimationScope(animation:)`.
   - Precedence: `withGlassAnimation` > `GlassAnimationScope` > package default (SwiftUI default spring, verified against the lab). The press always uses its own native-fitted springs.
   - Reduce Motion read as today (plugin or `disableAnimations`). Starting guess: press brightens only (no growth, overshoot or stretch); materialize and morph cross-fade without blur ramp; merge springs without bounce. Native Reduce Motion recordings decide and every Reduce Motion run is checked. A mid-animation switch applies from the next change.
   - Frame cost: perf scene with continuous press pulses, materialize and merge; within 20% of the still-glass scene; alternating A/B pairs; over budget means 2B.3 fixes the cost (likely the per-frame geometry redraw).

### Spike result (2026-10-03, `spike-interactive.md`, probe code `proto/2b` 5999b4412)

- Native `.glassEffect(.regular.interactive())` reacts on the simulator once the glass holds rendered, hit content (`Text`, a `Button` label, or `Color.white.opacity(0.001)`); `material.interactive` never reacted because its content is `Color.clear`. The reaction coincides with UIKit's `_UIFlexInteractionPanGestureRecognizer` joining the touch (58 launches). Verified here: v13's `ready.png` is byte-identical to v0's (max difference 0).
- Reference for `Glass.interactive()`: v13, `Color.white.opacity(0.001).frame(250×88).glassEffect(.regular.interactive())`. No fallback to `button.press`.
- **Section 4 correction:** the press is a uniform scale whose factor falls with size, not a fixed outset. Glass up to about 60 pt tall grows about 17.5 pt in width; taller glass grows about 1100/h pt (inference from six sizes). `.buttonStyle(.glass)` and interactive `.glassEffect` press identically at the same size.
- Glow first (luma to 90% in 0–120 ms), growth second (128–220 ms); release: size back in 123–183 ms, glow 270–615 ms; SwiftUI glow decays from about +17 to +11.5 over about 400 ms, then drops in one frame.
- A slow pressDrag (+60 pt at 120 pt/s) neither moves nor stretches the glass; the glow dims during the drag. Two interactive shapes 10 pt apart in a `spacing: 20` container: only the pressed one scales, and the neighbour shows no glow (MAD 0.18–0.82).
