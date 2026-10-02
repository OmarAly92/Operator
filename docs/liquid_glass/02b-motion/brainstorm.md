# Project 2B: how glass moves. Brainstorm state (no spec written yet)

Updated: 2026-10-03. Status: **brainstorming, architectural path.** The research is done (`context.md`). Question 1 is answered (C, 2026-10-03) and its native spike is running; questions 2–7 follow the spike. Nothing about 2B is approved yet.

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
| 2 | **What is the target timing for materialize and dematerialize?** The lab's own `withAnimation` scene measures appear about 285–320 ms and disappear about 117–167 ms (10–90%). A third-party capture said 250 / 350 ms. | Not asked yet. | **The lab's measurement**: it is the instrument, and the third-party numbers run the other way. Also ask whether the package's default glass animation should mirror SwiftUI's `Animation.default`. |
| 3 | **Where is 2B's boundary with project 3?** | Not asked yet. | 2B owns the package primitives: what `Glass.interactive()` does (press outset and spring, glow, glow spreading to neighbours inside a container, drag stretch), the transitions (materialize, identity, matched geometry), container merge and split with SwiftUI `spacing` semantics, union by id, identity morph by id, the spring constants and Reduce Motion. Components stay in project 3: the tab bar lens, menus and the `button.press` component. Operator's `_PressLift` and tab bar move onto the package's interactive glass only if trivial; otherwise project 3. |
| 4 | **Are the lab's motion upgrades part of 2B?** | Not asked yet. | **Yes, as the first tasks**, because nothing can be measured without them (`context.md` §2 and §6.2): per-element tracking through pinned regions, a topology series (component count, neck width) for merge, split and union, a materialize progress and blur measure, excluding the app-teardown event, event pairing better than order alone, `lab.py repeat` noise floors for every 2B scene, and a threshold policy of max(fixed, 1.5 × noise). Native runs differ across sessions by more than `noise.json` allows. |
| 5 | **API shape**, mirroring SwiftUI. | Not asked yet. | `Glass.interactive()` (exists, stored but unused); `GlassEffectContainer(spacing:)` with SwiftUI semantics (today `blend` fuses only gaps under half its value); an id plus namespace for morph, like `glassEffectID`; union by id, like `glassEffectUnion`; transitions like `glassEffectTransition(.materialize / .identity / .matchedGeometry)`. **Implicit animation**: a widget change animates with a package default spring, like SwiftUI `withAnimation`, with an override. Names are decided once and never renamed. |
| 6 | **Reduce Motion behaviour and how to measure it.** | Not asked yet. | No bounce or stretch, and fades instead of blur and lens ramps. Measured with `--a11y reduce-motion` runs of `button.press`, `material.materialize` and `material.merge`; native Reduce Motion references exist today only for `tabbar.drag`, `menu.bar` and `sheet.detents`. `GlassGlow` and `LiquidStretch` ignore `reduceMotion` today. |
| 7 | **Frame-cost budget for animated glass.** | Not asked yet. | A new perf scene with glass animating every frame. Every animated frame reruns the geometry shader with no cache (`render_liquid_glass_geometry.dart:204-214`) plus an `Opacity` save layer. Budget: within 20% of the static glass scene on the simulator, measured A/B alternating (gotcha 16). Real 120 Hz smoothness is project 5. |

Other points the spec must settle (from `context.md` §6):
- **Edge light and lens thickness.** "Visibility as materialize" couples edge-light width to lens thickness (2A.1 open item B3). Rule on a fixed reach before tuning any ramp, and decide which fields ramp: `refractiveIndex`, `outlineWidth` and `specularWidth` do not today.
- **Blend calibration.** Calibrate `spacing` against `blend` on `material.merge`, and match native's no-merge at 16 pt in `material.union`. Groups are capped at 16 shapes, which matters for morph stacks.
- **Glow spreading.** It needs a container-level glow layer; today the glow is per shape and clipped (`liquid_glass.dart:284-288`).
- **Live example scenes.** They are static today: wire `LabButton.onTap`, use real state for materialize, merge and morph, and fix the union scene (circles, two union groups).

## Approaches I intend to propose after the questions

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
