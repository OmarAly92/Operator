# Final whole-branch review: ios_liquid_glass 2B.1

Branch `feat/ios-liquid-glass-2b1`, base `d35df87fa`, head `7e363e226` (29 commits). Reviewer: final whole-branch seat (read-only, no subagents, no simulator).

## Method

- Read the plan header (rulings 1-34, Global Constraints, Review Focus 1-6), spec §8, the ledger (`progress.md`), `results-2b1.md` and `todo-2b1.md`.
- Read the package diff in full: `glass_motion_coordinator.dart`, `glass_motion_widgets.dart`, `glass_effect.dart`, `glass_effect_container.dart`, `glass_spring.dart`, `glass_animation.dart`, `glass_frame.dart`, `glass_materialize.dart`, `glass_material_source.dart`, `ios27_motion.dart`, the render-hook changes (`liquid_glass.dart`, `liquid_glass_render_object.dart`, `render_liquid_glass_geometry.dart`, `liquid_glass_layer.dart`, `liquid_glass_blend_group.dart`, `glass_shadow.dart`, `liquid_glass_settings.dart`) and both shaders. For the harness: `shapes.py`, `touch.py`, the `analyze.py`, `align.py`, `manifest.py`, `metrics.py` and `springfit.py` diffs, `done_table.py`, `still_check.py`, `fitvis.table_source`, and the `scenes.json` motion entries. This was done in passes; I skimmed the rest of the harness (`track.py`, `rim*.py`, probes) and the Swift lab code.
- Re-ran every gate on head: package analyze clean, `+122`; example analyze clean, `+13`; app analyze clean, `+2146`; harness `Ran 175 tests` OK.
- Wrote throwaway lifecycle probes in my scratchpad and ran them against the package. Nothing was written to the repo. All 12 probes passed:
  - a container removed while a ghost is in flight: no exception, no transient callbacks left;
  - a standalone ghost in flight when the whole app is removed;
  - a standalone glass removed and settled, after which the overlay entry count returns to its baseline;
  - a `GlobalKey` move from standalone to a container and back: no ghost, no exception;
  - standalone glass switched regular → identity → regular, then removed;
  - six fast toggles in a container;
  - page push and pop with standalone glass;
  - a container inside `IntrinsicHeight`;
  - a drag followed by a removal: the ghost sits at the drawn rect;
  - lazily built standalone list items appear at once;
  - two page pops under `withGlassAnimation`;
  - a container with no `Directionality`. This probe failed, which is Minor 1 below.

## Strengths

- **The coordinator's ownership model is sound end to end.**
  - Each `GlassMember` has exactly one owner at a time: the `GlassEffect` state, a coordinator's `_leaving` map, or a `GlassGhost`.
  - Disposal follows that owner: `drop` and `dispose` run when the state is not ghosted; `GlassGhost.dispose` handles ghosts; `GlassMotionCoordinator.dispose` covers `_leaving` (`glass_effect.dart:156-171`, `glass_motion_coordinator.dart:459-471, 528-544`).
  - Deactivate runs parent-first and unmount runs child-first, so a whole-container removal detaches the glass's parent before `deactivate` reads `parent.attached`. Nothing is disposed twice, and nothing leaks.
- **Removal reads no transform (ruling 31).** `_globalRect` uses the last drawn rect, the cached space origin and the scroll delta (`glass_motion_coordinator.dart:452-457`). A removal during build therefore cannot touch an ancestor that has not been laid out.
- **Drawn-rect continuity is designed well.** A change folds `previous − new` into the offset springs, so the drawn rect is the same before and after `_sync` within a frame. Readers that gathered earlier in the paint stay consistent. Following restores the pre-change springs and lands on the layout in one step (`:106-137, 156-178`). `_changed()` is idempotent per frame across `sized` (layout) and `_sync` (paint).
- **Render-hook listeners are symmetric.** Every new listener (visibility, settings source, motion, shadow source) is added in `attach` or the setter only while attached, and removed in `detach`.
- **The shader change is the identity at visibility 1.** `uOptics.w` and `uFullThickness` are both checked: `max(full, thickness)`, uniform 103 = 7 + 16·6.
- **The harness meets "nothing passes by being absent".** A listed measure that is missing is `inf` (`shapes.py:419-422`). An unpaired or unowned event fails `events.unpaired`. Touch counts are gated. An invalid or grid-edge spring fit sets `response_pct`/`damping` to `inf`. Limits stay max(fixed, 1.5 × noise); no fixed threshold was loosened, and the new keys only add (`metrics.py`). `FLOAT_SLACK` is 1e-9, which is not a loosening.
- **The `results-2b1.md` claims I checked hold up.** The code citations are right (`glass_motion_widgets.dart:92-95`, `glass_motion_coordinator.dart:284`, `fitvis.py:231-246`, the `transform_tracking…:91-93` mixin, `render_liquid_glass_geometry.dart:244`, `liquid_glass_render_object.dart:394` in `_buildGeometryImage`). The gate counts match my reruns. The committed table has no non-fitted 1.0.
- **The constraints are met.**
  - No comments in new or changed code; I grepped every added non-doc line.
  - `simctl` always takes a UDID (`sim.reboot`).
  - No pubspec changes: `motor` and `meta` were already dependencies.
  - The material and motion tables are tool output.
- **`todo-2b1.md` is unusually complete**, with a deciding measure for each item.

## Issues

### Critical

None.

### Important

1. **Review Focus 3's ghost half is unpinned.**
   - File: `test/motion/glass_motion_coordinator_test.dart:160-168`.
   - What's wrong: "a container removed while its glass animates disposes cleanly" removes the container while an *inserted* glass appears. The dispose path for a ghost in flight is never exercised: `ghosts` and `_leaving`, the snapshot dispose, and the ticker stop (`glass_motion_coordinator.dart:528-544`). Review Focus 3 names this case ("or its whole container removed mid-animation … frees its snapshots"). Task 14 deferred it, and `todo-2b1.md` lists it as a defect.
   - Why it matters: my probe shows the code works today. Nothing guards it against regression, and it is the riskiest lifecycle path.
   - Fix: add the test. Toggle off, pump 30 ms with a `RawImage` present, `pumpWidget(SizedBox())`, then assert no exception and `transientCallbackCount == 0`.
2. **The leak guard for the standalone overlay entry is untested.**
   - File: `lib/src/motion/glass_motion_widgets.dart:165-188`.
   - What's wrong: `GlassOverlayGhosts` inserts an `OverlayEntry` into the app's `Navigator` overlay for any standalone glass. It removes the entry only through `release`/`onIdle` → `_removeIfIdle`, and nothing tests that removal (Task 17 deferred minor).
   - Why it matters: every standalone `GlassEffect` in Operator retains this entry. A regression would leave a permanent full-screen entry above every route.
   - Fix: add the test. Count `_OverlayEntryWidget`s before, with and after a standalone glass removal, and expect `[n, n+1, n]`. My probe does exactly this and passes.

### Minor

1. **`GlassEffectContainer` now needs a `Directionality` ancestor.**
   - File: `lib/src/api/glass_effect_container.dart:55-58`.
   - What's wrong: the new `Stack` resolves `AlignmentDirectional.topStart`. Without a `WidgetsApp` above it, the container throws "No Directionality widget found". My probe confirms this. Real apps are unaffected; package users mounting a bare container (tests, previews) are.
   - Fix: pass `alignment: Alignment.topLeft` to the `Stack`.
2. **Harness defects that 2B.2 will hit are missing from `todo-2b1.md`.**
   - What's wrong: `compare_topology` returns `None` when neither side reaches two components, and it omits `join_ms`/`split_ms` when only one side transitions (`shapes.py:324-333`). A listed `topology.*` measure then reads `inf`, a false fail (Task 4 deferred). The manifest accepts `topology.*` motion measures on a scene with no `topology` regions, and requires a `track` even for topology-only motion (`manifest.py` validate; Task 3 deferred). A count-0 frame reads neck 0.0, not NaN (`track.py:466`; Task 1 deferred).
   - Why it matters: 2B.2's Done item 1 judges join and split timing, neck and count.
   - Fix: add these lines to `todo-2b1.md` "Harness and lab".
3. **`fitvis.table_source` silently writes 1.0 for an unfitted exponent or gain, and drops a preset with no curves.**
   - File: `fitvis.py:331-334`.
   - What's wrong: the Task 7 ruling guarded this by controller process only. The tool itself remains unsafe for the next `--write`, and it is not in the todo, though the Reduce Motion gain fallback next to it is.
   - Fix: add it to `todo-2b1.md`. Better, make `table_source` raise on `None`.
4. **"Nothing passes by being absent" is only relative to native.**
   - File: `shapes.py:395-404`.
   - What's wrong: `expected()` iterates the pairs that exist. If both apps miss the same step's event, that step's measures are never expected, while `events.native_motion` (≥1), `events.steps` (symmetric difference) and `events.unpaired` still pass. `done_table`'s 168 / 168 shows this did not happen in the 2B.1 runs.
   - Fix (later): add an `events.pairs` gate, the number of pairs ≥ the number of touch steps.
5. **Stale uniforms on reattach.**
   - Files: `liquid_glass_render_object.dart:113-119`, `render_liquid_glass_geometry.dart:160-167` (Task 11 deferred, in todo).
   - What's wrong: `attach` nulls `_effective` without re-uploading uniforms.
   - Fix: call `_visibilityChanged()` / `_applySettings()` at the end of `attach`. It is a one-liner, but there is no realistic trigger in 2B.1: the new visibility objects on a re-join go through the setter, which refreshes.
6. **`_RenderGhostStack.performLayout` falls back to `constraints.smallest` under unbounded constraints** (`glass_motion_widgets.dart:257`). This is harmless today: both hosts get tight constraints from `Positioned.fill` or the theater.
7. **`MOTION_MEASURES` exists twice** (`shapes.py:16-30`, `manifest.py:14-28`). They must be kept in step by hand.

## Ledger triage

### Rulings

Every `Ruling:` line looks right. Notes:

- **F1-F7, Task 2, Task 5, Task 8 (load), Task 13, Task 20 planning, Task 20e: agree.**
- **Task 7 ruling (`table_source` 1.0): agree for this branch.** I re-checked the committed `ios27_motion.dart`: the only 0 gains are INERT or `at_floor`, and there is no 1.0. The underlying tool fault should go to the todo (Minor 3).
- **Task 9 exclusions and Task 20b renumbering: agree.**
  - These are the only places where data selection touched a limit.
  - The selection tightened limits; it never loosened one.
  - Each exclusion is backed by frame-gap evidence (`task-9-outliers.md`, `task-9-scan.md`). Excluded takes were moved, not deleted.
  - The renumbering is justified by `by_take` grouping on take number, not by the result.
  - Results report both.
- **Task 20d (edge snap, no code change): agree.**
  - Spec Done item 5 judges measures, and none moved (≤ 0.0008).
  - The cause is a latent geometry-cache sampling fault, proven by the `render()`-skip probe. It is in the todo with both fixes.
  - The user should still know that 12 `material.edge` Flutter frames are not byte-identical to 2A.

### Deferred minors

**Fix before merge** (test or doc only, no production change):

- Task 14: a test for removing a container with a ghost in flight (Important 1).
- Task 17: a test that the overlay entry is removed once unused (Important 2). The other three overlay paths can carry.
- Task 4 (`compare_topology` `None` / missing `join_ms`), Task 3 (topology measures without topology regions) and Task 1 (count 0 → neck 0.0): add to `todo-2b1.md` for 2B.2 (Minor 2).
- Task 7 ruling item: the `table_source` 1.0 writer goes to the todo (Minor 3).

**Fine to carry** (already in the todo, resolved, or harmless):

- **Task 1:** `BAND_EDGE` placement; lobes and neck on the full mask.
- **Task 2:** a touch with no up frame (caught by `touches.*`).
- **Task 3:** threshold keys not cross-checked.
- **Task 4:**
  - `doubleTap` (in the todo; no scene uses it);
  - touches before start − 0.2 s;
  - has-marker inference;
  - duplication;
  - `event_series` hold vs split.
- **Task 5:** `TouchRelay` first touch and its observer.
- **Task 6:** all four (two in the todo).
- **Task 7:**
  - Reduce Motion gain fallback (in the todo);
  - INERT keys;
  - `invert` on partial scans;
  - `best_lag` duplication;
  - `recordings()` untested.
- **Task 8:** spacing geometry test.
- **Task 9:** the take-4 36.7 ms gap.
- **Task 10:** all three (`bounce ≥ 1` is in the todo).
- **Task 11:**
  - the pass-through duplication;
  - the null baseline and stale uniforms (in the todo; Minor 5);
  - FakeGlass (in the todo; iOS 27 Impeller only);
  - content slot type switch (harmless: the content carries `_snapshotKey`, a `GlobalKey`, so it is reparented with its state);
  - thin paint coverage.
- **Task 12:**
  - notify every tick (in the todo, M10);
  - overshoot reversal step;
  - pending ghost with no host keeps the ticker running (in the todo);
  - position compared on every read.
- **Task 13:**
  - siblings jump: **resolved**, because `leave` calls `_structureChanged` when it ghosts (`glass_motion_coordinator.dart:436`);
  - scrollables: **resolved** (`glass_effect.dart:180`);
  - lazy list without repaint boundaries: README caveat optional.
- **Task 14:**
  - `_childKey`: **resolved**, removed;
  - `GlobalKey` in a `LayoutBuilder`: speculative.
- **Task 15:** material disposed while a ghost holds it. It is never touched after dispose: `takeGhosts` nulls `material` before `_disappear`, and `_leaving` members are neither sampled nor laid out.
- **Task 16:** all four.
- **Task 17:** the other three paths; no ghost before the first build; later entries draw above ghosts.
- **Task 18:** offset 7.
- **Task 19:** warm-up tap (in the todo).
- **Task 20a:** all four. `still_check` without noise is stricter, not looser.
- **Task 20e:** `scan.py` and `make_crops.py` paths (evidence copies).

## Plan alignment

- The three known departures are justified and ledgered:
  - the two extra tests;
  - the replaced and renumbered Task 9 takes;
  - the fitvis re-fit, byte-identical to `table_source(fit.json)`.
- No other departure from the plan's code was found.
- **Done item 4 is not met as the spec words it** ("pass … per shape"): normal 129 / 168 and Reduce Motion 135 / 168. Every failure is classed: 69 (b), 3 (a). The plan's header table expected "partly failing" and the plan was approved with that expectation, so this is not an execution defect. It is the one spec item the user must accept explicitly at merge.

## Declined to judge

- Whether native-parity numbers (spring shape, sharpness, 10–90% times) could be closed: these are model work, which the plan scopes to the todo.
- Renderer frame cost: per-tick notify of every member, one `RepaintBoundary` per glass, an extra layer per transition. That is M10 / 2B.3 by plan.
- Lab-app Swift and example scene correctness beyond the lifecycle that the results depend on: covered by per-task reviews and the simulator runs, and I was told not to run the simulator.
- Whether a ghost drawn above a modal route is acceptable UX: ruling 27 decides it.
- Whether glass inside a `LayoutBuilder`-swapped subtree should materialize: ruling 16's rule applies, and SwiftUI does the same.

## Assessment

**Ready to merge: with fixes.**

Reasoning: I found no correctness defect in the coordinator, ghost, overlay or render-hook lifecycle, and all gates are green on head. The fixes are two lifecycle tests for paths Review Focus 3 and Task 17 name (both pass in my probes today), plus four todo lines for harness faults that 2B.2 will meet. Separately, the user must explicitly accept Done item 4 as partly failing.
