# Independent code review: 2B.1 branch `feat/ios-liquid-glass-2b1` at `abe33abbc`

Reviewer scope: code and its fidelity to `plan-2b1.md` (34 rulings) and `spec.md`; gates; the executor's 11 rulings; probes of the new motion code and the harness. Measurement numbers are the auditor's; I recomputed only where code drives a number. Nothing in `/Users/omaraly/development/AI/Operator-2b1` was edited. Probes ran in a detached scratch worktree at `abe33abbc` (`scratchpad/review2b1-exec/wt`, removed after the review); copies are in `scratchpad/review2b1-exec/probes/` (`review_probe_test.dart`, `harness_probe.py`, `rmgain.py` and their outputs `probe_run.txt`, `rmgain.out`, `gates.log`).

## 1. Verdict

**Mergeable after two small fixes (C1, C2); no blocker.** The branch's code is the reviewed prototype `bba17e92a` almost line for line: the only code differences are the re-fitted table (tool output, verified byte-identical to `fitvis.table_source(fit.json)`), one `Stack(alignment: Alignment.topLeft)` and four added tests, each covered by a ledger ruling. Every gate re-runs green with the claimed counts. The 32 first-review findings and R1–R10 are still fixed. Lifecycle is sound in every probe I could build: ghosts' snapshot images are disposed when the container, the overlay or the whole app goes mid-ghost, no ticker survives, and hot reload, kind and transition changes, `GlobalKey` moves, nested containers, rapid toggles, and a scrolled list hold up.

Probes found one real visible bug: a glass removed while its route is covered flashes back for one frame when the route is shown again (C1). They also found a hole in "nothing passes by being absent": a step that both apps miss is never expected (C2). The executor knew about C2 and recorded it in `todo-2b1.md`, but it is the same class as the plan review's blocker 1 and costs a few lines. The other findings are documentation drift, latent tool defects (the table writer, vacuous empty-run checks) and documented trade-offs that the probes confirm. Ruling 3 (recordings under load) is the weakest ruling. It does not invalidate the package code, but it makes Done item 4's 129 / 135 provisional (section 4).

Counts: **blocker 0, major 4 (C1–C4), minor 15 (C5–C19).**

## 2. Gates (re-run on the tip, scratch worktree at `abe33abbc`, `flutter pub get --offline`)

| Gate | Command | Result | Claim |
|---|---|---|---|
| app | `flutter analyze` / `flutter test` (`packages/mobile`) | `No issues found! (ran in 7.1s)` / `02:01 +2146: All tests passed!` | 2146 ✓ |
| package | same, `packages/ios_liquid_glass` | `No issues found! (ran in 5.0s)` / `00:04 +125: All tests passed!` | 125 ✓ |
| example | same, `…/example` | `No issues found! (ran in 1.5s)` / `00:01 +13: All tests passed!` | 13 ✓ |
| harness | `python3 -m unittest discover tool/glass_lab/harness/tests` | `Ran 175 tests in 41.463s` / `OK` | 175 ✓ |

Constraints, checked:
- No comments in any added Dart, Python, Swift, GLSL or shell line, including the committed research scripts. A regex over every `+` line matched only Python `//` integer division.
- All 31 commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (checked per commit).
- `frontend/package-lock.json`, every `pubspec.yaml` and `pubspec.lock` are untouched, so there are no new dependencies.
- `packages/mobile/lib/` and `packages/mobile/test/` are unchanged: Operator's app code is not touched. Its toolbars pick up the new behaviour only through the package.
- `scenes.json` and the native registry agree (`test_lab_ids_match_the_native_registry` passes).
- `noise.json`: `menu.bar` is kept, the `tabbar.drag` `event2.*` entries are removed (ruling 22), and the 15 new scenes are added. It is unchanged since `fd30f969d`.

## 3. Fidelity to the plan (branch against prototype `bba17e92a`)

`git diff --stat 06d406bae d35df87fa -- packages/mobile` is empty, so the two bases carry the same code. `git diff bba17e92a abe33abbc -- packages/mobile ':!noise.json'` touches 5 files:

| Difference | Ruling that covers it | Sound? |
|---|---|---|
| `lib/src/motion/ios27_motion.dart`: `.snappy` exponent 2.7 → 2.65, `.bouncy` exponent 2.75 → 2.8, `.bouncy` gain 0.34 → 0.36 | Task 20 Step 4 re-fit (ledger 20b), tool-written | Yes. The committed file is byte-identical to `fitvis.table_source(...)` of `fitvis/20261005-211745/fit.json` (I re-ran it: `identical`). `fit.json` has no `None` and no grid-edge value. |
| `api/glass_effect_container.dart:56`: `Stack(alignment: Alignment.topLeft)` | Final-review minor 1 (fix wave `8767603f3`) | Yes. The Stack has one non-positioned child and `StackFit.passthrough`, so alignment cannot move anything: no pixel effect, and the measured runs at `58ab57e0c` stay valid. |
| `test/motion/glass_motion_coordinator_test.dart`: +4 tests (identity insertion, container removed mid-ghost, overlay entry removed once unused, no `Directionality`) | Ledger Task 13 ruling; fix wave | Yes, with weak spots (executor ruling 11; my P1 and P2 cover what they miss). |
| `README.md` line 62: the new table values | Task 21 | Yes. |
| `tests/test_scenes_2b.py:34`: pins the six heights | Ledger F4 / Task 8 | Yes. |

There is no unexplained drift. The harness, the Swift lab, the example, the shaders, `scenes.json` and every other package file are byte-identical to the prototype.

## 4. Findings

### C1 · major: a glass removed while its route is covered flashes back for one frame when the route is shown again
- **Where:**
  - `lib/src/api/glass_effect.dart:125`: `animate` is true whenever the parent is still attached, whatever `TickerMode` says.
  - `lib/src/motion/glass_motion_coordinator.dart:473-492`: `takeGhosts` runs at the (offstage) layout and calls `_disappear(…, _now)`.
  - `:501-503`: the container's ticker is muted under `TickerMode(enabled: false)`.
- **Evidence:** probe P23 (`probes/review_probe_test.dart`).
  - Setup: `MaterialApp`, a container glass on the home route, a page pushed over it. The home glass is then removed by a `ValueNotifier` (a background state change), and the page is popped.
  - Output: `P23 while covered: ghosts taken 1, ghost member visibility [1.0]`, then `covered removal: hasGhosts while covered true, transient callbacks 0, ghosts after pop 1`.
  - Trace after `pop()`: `0ms:1/1.00 16ms:0/null …`.
  - So the ghost is built offstage and frozen at full visibility by the muted ticker, with its spring's start stamped seconds earlier. The first frame of the pop transition paints the long-removed glass at full visibility; the next tick finds the spring done and drops it.
- **Impact:** every route covered by another route, and every tab whose tickers are muted, does this. In Operator, a session-list toolbar glass that changes while a session page is open can flicker on back navigation. The snapshot is also kept while covered (bounded, one image per removed glass).
- **Fix:** treat a muted ticker as "no animation" (SwiftUI does not transition views that are not on screen). In `GlassMotionCoordinator.leave`, return `false` when `ghostOwner._ticker.muted`. In `takeGhosts`, drop entries whose owner is muted. Add P23 as a test.

### C2 · major: a step that both apps miss is never expected, so its seven measures pass by being absent
- **Where:** `tool/glass_lab/harness/shapes.py:395-423`. `expected()` iterates only the pairs that exist. `events.steps` (`:411-413`) compares the two apps' step sets with each other, not with the scene's touch steps. `done_table.py:24` takes "expected" from the same list.
- **Evidence:** `probes/harness_probe.py` H3 builds both captures with step 1's event and no step 3 event on `material.materialize`. It prints `judged names: 12 pairs: ['step1e0'] failing gates: []`: no gate fails, and `done_table` would print 7 / 7 / 7 for that case instead of 7 / 7 / 14. When Flutter alone misses step 3, `events.steps` and `events.unpaired` do fail (H3b).
- **Status:** the final review found this and `todo-2b1.md` ("An `events.pairs` gate is missing") records it. It did not happen in 2B.1: 24 of 24 pairs are present in all five Done runs, which I re-read. It is the plan review's blocker-1 class, and the lab's own README says nothing passes by being absent.
- **Fix:** about 6 lines before 2B.2 uses the harness. Add `events.steps_missing = len(touch.touch_steps(scene.steps) − (steps_native ∩ steps_flutter))` with limit 0 when the scene has touches, and make `expected()` emit names for every touch step's `e0`, so a missing pair is judged `inf`. Add a synthetic test like H3.

### C3 · major (latent, not fired): `fitvis --write` can commit an unfitted or grid-edge value into the shipped table
- **Where:**
  - `tool/glass_lab/harness/fitvis.py:333-335`: `exponent … else 1.0`, `gain … else 1.0`, the Reduce Motion gain falls back to the normal gain.
  - `:329-332`: a preset with no entry is skipped.
  - `:375-376`: `--write` never checks `at_grid_edge` or `at_floor`.
- **Evidence:** H7. With `exponent: None` the tool writes `ios27DefaultDisappearExponent = 1.0` and `…AppearGain = 1.0`. With `at_grid_edge: True` values it writes them (`edge values written: True`). A skipped preset breaks compilation, which is loud; a 1.0 does not.
- **Status:** executor ruling 4 used a manual guard. I confirmed the guard held this time (the committed file equals `table_source(fit.json)`, and `fit.json` has no `None` or edge value). `todo-2b1.md` records the fault. The plan's rule that fitted tables are written only by tools makes the tool the only guard, and 2B.2 and 2B.3 will re-run `--write`.
- **Fix:** before writing, raise on any `None` (except `INERT`), on `at_grid_edge`, on a non-`INERT` `at_floor` gain, and on a missing preset. Add a unit test.

### C4 · major (fit quality; needs a decision, no code change in 2B.1): the `.bouncy` Reduce Motion gain 0.62 averages two appearances that disagree; the renumbering (ruling 8) hid the signal
- **Where:** `fitvis.py:166-170`, `:186-206`. The pooled `fit_gain` pools every case. `by_take` groups only feed the `*_spread` stop checks.
- **Evidence:**
  - Before the renumbering, take 3 held only the light RM cases and fitted gain **0.0**; take 5 held only the dark replacements and fitted **1.24** (ledger 20b, `results-2b1.md` deviation 4). The pooled value is 0.62.
  - Per-case re-fit with `fitvis.fit_gain`, on scratch copies of the 24 native RM `.bouncy` recordings (Task 8 run `20261004-001040` plus noise takes 0–4; script `probes/rmgain.py`, output `probes/rmgain.out`):
    - pooled: **0.62**, the committed value exactly, so the copy reproduces the fit;
    - per case: `dark-photo` **0.44**, `dark-stripes` **1.50 (at the grid ceiling)**, `light-photo` **0.18**, `light-stripes` **0.0 (at the floor)**;
    - per appearance: light **0.0 (floor)**, dark **1.26**;
    - per take: 0.58–0.64, which is why the take-spread check is now quiet.
  - So the per-case gains run from floor to ceiling. The "never stuck at a grid edge unreported" lesson is checked only on the pooled value, which sits between them.
  - The renumbering is legitimate bookkeeping, because the pooled fit does not depend on take numbers. But the stop condition had fired on a real per-appearance difference, and `results-2b1.md` calls it "case mix, not a deviant take" without recording the split.
- **Impact:** the RM gain is a compromise that fits neither appearance, and one case's own fit is pinned at the grid ceiling (`dark-stripes`, where ruling 10's stripe shift also enters the progress). The normal `.bouncy` gain has the same per-appearance shape (todo class (a), "`.bouncy` appear settles late on `light`").
- **Fix:** record the per-appearance gains in `results-2b1.md` and `todo-2b1.md` next to the class (a) item. Make the spread check per case as well as per take, and report `at_grid_edge` per case, so a mix of appearances cannot hide behind a balanced take group. No code change to the package in 2B.1.

### C5 · minor: snapping on release after a drag lands at once
`glass_motion_coordinator.dart:106-126`. P4 drags 6 frames, then the next frame sets `x = 200` (a snap to a detent on release). The glass is drawn at `200.0` in its first frame: a jump. This is ruling 32's stated cost, but it hits the most common drag ending: release always lands within 50 ms of the last drag frame. Fix: in README line 59, name this case and its remedy (`withGlassAnimation` around the snap). Optionally test it.

### C6 · minor: README says standalone glass with no `Overlay` "appears and disappears at once"; it materializes on insertion
README line 60 against `glass_effect.dart:71-95`: the private coordinator joins with `inserted` regardless of the overlay. P3 reads `no Overlay, yet insertion visibility is 0.0 then 0.389`. P3b confirms removal is at once. Ruling 27 only says it disappears at once. Fix the README, or skip insertion animation when there is no overlay so the two sides match.

### C7 · minor: inside `withGlassAnimation`, a subtree switch ghosts standalone glass but not container glass
`glass_motion_coordinator.dart:398-440` adopts the leaving member into the container's coordinator, which is disposed in the same frame. P11 has one container glass and one standalone glass leaving with the same parent: `1 ghost(s)`. Ruling 16 says both dematerialize when a transaction is pending. Fix: when the container is leaving too (its parent detached), hand the ghost to the nearest overlay host. Otherwise document that container glass leaving with its container never ghosts.

### C8 · minor: ghost placement after an ancestor transform change relies on the renderer re-gathering geometry
`glass_motion_coordinator.dart:164-168` caches `_spaceOrigin`; `:452-457` places the ghost from it. P12 and P12b push a page, settle, then remove the glass: `ghost at Rect.fromLTRB(332.6, 256.0, 582.6, 344.0), glass was at Rect.fromLTRB(275.0, …)`, 57.6 pt off. That is on the `FakeGlass` path (flutter_test, ROADMAP gotcha 39; also Skia and web). On the shader path, `GeometryTransformTrackingLayer` reports each transform change and the blend group re-gathers the shapes (`drawnRect` → `_sync`), which should refresh the cache. That is unproven, because no test can run that path. Fix: make the refresh explicit. Read `_spaceOrigin` from `RenderGlassMemberBox` (or through the layer's transform-change callback) instead of depending on a gather, or record in ROADMAP that ghost placement depends on it.

### C9 · minor: `still_check.py` and `done_table.py` pass vacuously on empty or mistyped run folders
H1: `still_check` on two empty folders prints `0 … triples compared … missing: 0 | worse: 0`. H2: `done_table` prints `total: … 0 pass / 0 judged / 0 expected; events and touches 0/0`. Fix: exit non-zero when nothing was compared. In `done_table`, derive "expected" from the scenes' steps (with C2).

### C10 · minor: every member is notified on every tick while any member animates
`glass_motion_coordinator.dart:263-280, :505-511`. P15: a resting sibling was notified 20 times in 20 frames, so its glass repaints and the shared group re-gathers every frame. Known (perf todo, finding 22); confirmed here.

### C11 · minor: `results-2b1.md` "Gates" claims `+125` package tests "at `58ab57e0c`"
At `58ab57e0c` the coordinator test file has 28 tests; the package had 122. `+125` is the tip's count, after `8767603f3`. Fix: say "at `abe33abbc`", or give 122 for `58ab57e0c`.

### C12 · minor: lab README says `reproduce.py` refuses a stale native build
`tool/glass_lab/README.md:86`. R10 removed that check, and `grep require_fresh harness/*.py` shows no call in `reproduce.py`. Fix the sentence.

### C13 · minor: ROADMAP says the plan has "33 rulings"
`docs/liquid_glass/ROADMAP.md:396`. The plan has 34; ruling 34 is `atVisibility`.

### C14 · minor: two `todo-2b1.md` rows are stale
Line 53 says no test removes a container while a ghost is in flight. Line 55 lists "the overlay entry removed once unused" as untested. The fix wave added both tests. What is still untested: image disposal (my P1 and P2 pass) and "no `Overlay` disappears at once" (my P3b passes). Update the rows.

### C15 · minor: package consumers cannot reset the global `withGlassAnimation` value in their tests
`glass_animation.dart:84-88`: `debugResetGlassAnimation` is not exported (`lib/ios_liquid_glass.dart:28` exports only `GlassAnimation`, `GlassAnimationScope`, `withGlassAnimation`). A consumer test that calls `withGlassAnimation` and ends without a frame leaks the pending value into the next test's first frame. P14 confirms it is cleared one frame later. Under ruling 16, glass built in that first frame then materializes instead of appearing at once. Fix: export it (it is `@visibleForTesting`) and mention it in the README's motion section, next to the global-transaction sentence (line 55).

### C16 · minor: README describes `atVisibility` incompletely
README line 101 gives `atVisibility(v)` without its `blurRampExponent` parameter and does not say it is a lab-facing helper outside the SwiftUI surface (ruling 34). Add both.

### C17 · minor: the evidence and references live only in a worktree's ignored `build/`
`results-2b1.md` and `todo-2b1.md` cite run folders under `Operator-2b1/packages/mobile/build/glass_lab/` (`noise-2b1` is 44 GB; native references N1, N2, N5, N6, N7). The committed scan scripts hardcode that worktree (`research/execution-2b1/task9scan/scan.py:4,6`, `report.py:3,6`). If the worktree is removed after merge, 2B.2 and 2B.3 lose their references and noise takes. Fix: archive the native reference runs and noise takes outside the worktree before removing it, and say where in ROADMAP.

### C18 · minor: `requiresGeometryRebuild(null)` returns false, and `attach` nulls the baseline
`internal/render_liquid_glass_geometry.dart:95-98, :446-447`; `rendering/liquid_glass_render_object.dart:113-119`. A re-attach followed by one geometry-affecting change before the next paint keeps stale geometry until the next change. Known (todo); confirmed by reading. While glass animates, the very next tick repairs it.

### C19 · minor: lost-and-spurious touch pairs and `doubleTap` are not robust
H4: a touch whose `up` frame is lost is dropped, and an isolated blue frame counts as a touch, so the count can still match `expected_touches` with wrong timing. `doubleTap` misassigns steps. Known (todo). No 2B.1 scene is affected.

Probes that passed (no finding):
- P1, P2: ghost image disposed when the container, the overlay or the app goes mid-ghost; no transient callbacks left.
- P3b: no `Overlay`, removal at once.
- P5: a 70 ms jank frame mid-drag holds at most one frame's step, then sits on layout.
- P6: hot reload mid-appear and mid-ghost.
- P7: transition and glass kind changed mid-appear and back.
- P8: `GlobalKey` move from a container to standalone and back mid-animation.
- P9: a ghost never takes a tap.
- P10: nested containers.
- P13: same `ValueKey` removed and re-inserted under a new parent in one frame (ghost plus materialize, no exception).
- P14: pending cleared after one frame.
- P18: standalone glass ghost after a list scroll lands on screen.
- P21: 12 toggles 8 ms apart (up to 6 ghosts at once, all drained, ticker stopped).
- P22: removal 120 ms into an appear starts at the visible value and never rises.

Harness probes that passed:
- zero-travel progress is judged `inf` (7 of 7, H6);
- an instant step fits at the grid edge and fails as invalid (H8);
- zero-energy progress is NaN (H9);
- freshness guards: `run`, `repeat`, `fitvis`, `ghost_probe` and `cold_probe` call `require_fresh`; the example's stamp covers `PACKAGE_LIB` including the shaders.

## 5. The executor's 11 rulings

1. **Task text over header text (F1–F7):** justified. Each conflict was prose against replayed code; the cost was nil and is recorded.
2. **Keep the 2 pt marker tolerance:** justified.
   - `align.extent(ignore=MARKER)` (`align.py:113-114`) zeroes the marker's tiles plus one tile around them, so motion boxes never contain the marker.
   - Detected still boxes cannot see it, because `ready`, `settled` and `bare/ready` hold the same black square (ruling 7).
   - The still check reproduces 2A's `button.press` region (4 of 4 frames identical, measures unchanged).
   - Residual risk: a `settled.png` taken within 250 ms of a release. No scene does that.
3. **Accept recordings made under heavy load:** weakest ruling, acceptable for merging the package, not as a settled baseline.
   - What the numbers show:
     - Native references are 1–3 frames slower than the prototype's (results deviation 3).
     - Press holds run 2.1–2.9 s against 0.95–1.3 s.
     - Noise floors are wider than the prototype's three-take preview (median `response_pct` 8.2 → 13.6%, `damping` p90 0.072 → 0.15, `settle_ms` p90 17.5 → 35 ms).
   - Why: partly more pairs (a max over 10 pairs instead of 3), partly session drift. Within the noise run, pairs with a session-2 take add about one frame to `t10_90_ms` and `settle_ms` (median 0 → 8.3 ms and 4.2 → 8.3 ms) against session-1-only pairs.
   - Effect on Done item 4: 13 of the 129 normal passes and 21 of the 135 Reduce Motion passes hold only because noise lifts the limit above the fixed threshold. At fixed limits the counts are 116 and 114. Some floors are wide, for example default dark-photo-RM `step3e0` damping limit 0.435 and `response_pct` 52.9%.
   - Recommendation: before 2B.2 or 2B.3 build on these references, record one load-controlled native session (load average under about 10) of the materialize scenes and the press series. Re-baseline any reference that moves by more than a frame. Until then, read 129 / 135 as provisional.
4. **Leave a writer that can write 1.0:** the manual guard held (verified), but the tool should not stay this way: C3.
5. **Extra tests:** good additions, but the two parked weaknesses are real.
   - The ghost-in-flight test asserts neither that a ghost exists nor that its image is disposed.
   - The overlay test does not check the deferred entry dispose.
   - My P1 and P2 show the code is right. Strengthen the tests with `expect(coordinator.ghosts, hasLength(1))` before the removal and `image.debugDisposed` after.
6. **Move four noise takes aside and re-record:** justified and evenly applied within the materialize scenes.
   - The criterion is objective (first-frame gap over 30 ms followed by at least two sub-5 ms gaps) and was scanned over all 240 takes. Frame-level evidence is in `task-9-outliers.md`. The near-miss (36.7 ms, one burst frame) was kept by the rule.
   - Keeping the press and interactive takes is reasoned (no press measure is judged in 2B.1). It does carry capture holes into 2B.3's floors, which todo records.
   - Effect on limits: both tightened and loosened. 63 noise values went down and 48 went up. The judged floors that went up are:
     - `material.materialize light-stripes step1e0` `progress.damping` 0.08 → 0.25 and `response_pct` 13 → 26%;
     - `.bouncy dark-stripes-RM step1e0` `response_pct` 9 → 20% and `damping` 0.05 → 0.10;
     - `.bouncy dark-photo-RM step3e0` `settle_ms` 33 → 50 and `response_pct` 18 → 25%.
     The replacement takes were recorded at load 100–300.
   - I re-judged every progress measure of the five Done runs against both floors. No verdict changes because of a loosened floor. The one verdict that flips is a tightening (`.bouncy light-stripes-RM step1e0 response_pct`, limit 68.75 → 18.75, failing at 19.05 in the first RM run), and its repeat replaced that case.
   - Asymmetry: the judged runs' native captures were not scanned for the same signature (ledger 20c). The risk is false failures, not false passes.
7. **Split Task 20 into five parts:** justified; the step text was unchanged and each part was reviewed.
8. **Renumber three takes 5 → 3:** legitimate as bookkeeping. `fit_exponent` and `fit_gain` pool all curves regardless of take number, and `noise.json` uses every take. But the renumbering removed the only automatic signal that the `.bouncy` Reduce Motion gain differs by appearance. Per case it runs from 0.0 (light-stripes, floor) to 1.50 (dark-stripes, ceiling), light 0.0 against dark 1.26 (C4). The table's movement (2.7 → 2.65, 2.75 → 2.8, 0.34 → 0.36) comes from re-fitting on this branch's recordings rather than the prototype's, not from the renumbering itself.
9. **Do not fix the edge-scene 0.24 px rim snap:** the cause is proven well enough.
   - The device probe (`render()` skipped → byte-identical to 2A) isolates the image path.
   - `geometry = geometry!.render()` and `canvas.drawImage(image, Offset.zero, Paint())` exist on `d35df87fa` unchanged since the fork rename `e1acd006b`.
   - 2A's post-frame `_SizeReporter` `setState` is on `d35df87fa` (`glass_effect.dart:37,109`), which explains why 2A ended on the Picture path.
   - One qualification: the fault predates 2A, but 2B.1 makes the snapped path the steady state from the second frame for every glass at a fractional x, where 2A's late rebuild kept static glass exact. That is sub-pixel and moves no measure.
   - Deferring it is right. Gotcha 48 and `todo-2b1.md` carry it, and Done item 5 passes by its definition (frames changed, measures checked, none worse).
10. **Commit the evidence:** right, and small (1.7 MB). The runs it points to still need a permanent home (C17).
11. **Park two test-strength findings:** acceptable as minor (see 5). The probes show no leak behind them.

## 6. Docs

- **Package README:** documents the global `withGlassAnimation` value (line 55), ruling 32's follow mode and first-frame hold (line 59) and `atVisibility` (line 101). It has three drifts: C6 (no-`Overlay` insertion), C15 (test reset) and C16 (`atVisibility` signature and status). It is accurate on the presets, the fitted numbers and the material-from-drawn-size rule.
- **`FORK.md` and `CHANGELOG.md`:** accurate against the code.
- **ROADMAP:** accurate except C13.
- **Lab README:** accurate except C12.
- **Five `results-2b1.md` claims, checked:**
  1. The judged limit is max(fixed, 1.5 × noise): `shapes.py:422`, and every `result.json` limit equals the committed noise × 1.5. ✓
  2. 129 / 135 with the repeats substituted, 130 / 133 as first run: re-run with `done_table.py`. ✓
  3. 112 of 124 Flutter frames byte-identical: 4+8+0+20+12+20+20+16+12 from the nine still outputs. ✓
  4. `task-6-reproduce.txt` is byte-identical to the prototype's `reproduce.txt`: `diff -q`. ✓
  5. The committed table equals `fitvis.table_source(fit.json)` and differs from the seed in three lines. ✓
  6. Also checked: "Gates at `58ab57e0c` … +125" is wrong (C11).
