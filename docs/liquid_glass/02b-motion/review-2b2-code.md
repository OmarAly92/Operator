# Independent code review: ios_liquid_glass 2B.2 (`feat/ios-liquid-glass-2b2`, tip 78ffa9b51, code 50b5ed28c)

Reviewer did not write the plan or the code. Nothing changed in the branch or the shared checkout. Scratch worktree `/Users/omaraly/development/AI/Operator-2b2-codereview` (detached at the tip) was used for every gate and mutation and has been removed (`git worktree remove --force`, that path only).

## What I ran

- `cmp` of every `packages/` file in `development..branch` against `proto/2b2` (worktree `Operator-2b2-proto`).
- All gates in the scratch worktree. No lab record, simulator or build command.
- Read: blend group, motion coordinator, motion widgets, `GlassEffect`, `GlassEffectContainer`, namespace/morph geometry, `sdf.glsl` diff, harness diffs (`shapes.py`, `track.py`, `manifest.py`, `analyze.py`, `fitvis.py`, `lab.py`, `metrics.py`), `MaterialScenes.swift` diff, `noise.json` against base, the E1-E10 rulings, `noise-take-check.txt`.
- 12 mutation runs and 3 numerical probes of the shader (a Dart run on the repo's own `scene_sdf_mirror.dart`, and a Python port).

## Gate lines (all match the claims)

| Gate | Result |
|---|---|
| `flutter analyze --no-pub` app / package / example | No issues found, in all three |
| `flutter test --no-pub` app | +2189, All tests passed |
| `flutter test --no-pub` package | +239, All tests passed |
| `flutter test --no-pub` example | +25, All tests passed |
| `python3 -m unittest discover tool/glass_lab/harness/tests` | Ran 253 tests, OK |

## Verdict

**Ready to merge: yes**, with one major finding (C1) that the user should decide on (carry-in or fix with a re-measure) and three minor ones. No blocker. Nothing I found breaks a current call site.

Counts: blocker 0, major 1 (C1), minor 4 (C2-C5), note 4 (C6-C9).

## 1. Branch vs plan

59 `packages/` files in the diff (the executor says 56). Against `proto/2b2`:

- 52 byte-identical.
- 2 new in the branch: `test/geometry/coincident_union_test.dart`, `test/core/widgets/glass/lab/lab_navigation_scenes_test.dart` (ruling 33).
- 5 differ, all explained:
  - `liquid_glass_blend_group.dart` (`+math` import, `_coincident`, `_canonicalOutline`, the `twin` branch), `glass_group_test.dart` (+11 tests) and `FORK.md` (one added line, 108): ruling 33 and the review fix `50b5ed28c`.
  - `lab_navigation_scenes.dart`: `GlassButton.icon` replaced by `IconButton`, ruling 33(a).
  - `noise.json`: the prototype's is partial (2865 leaf values) against the branch's 8789. Against `development` it moved exactly 25 values, all in `material.materialize/light-photo-reduce-motion`, as the ledger says; 5 of the 25 rose (`luma.peak_ms` 41.7 to 50.0, `step3e0.cy.peak_ms` 33.3 to 41.7, `cy.settle_ms` 25 to 33.3, `step3e0.luma.peak_ms` 16.7 to 41.7, `progress.sharpness` +0.0007). Those are the replaced take's own noise, not a loosened limit elsewhere.
- The regenerated patches (`t05-tests`, `t05-impl`, `t06-impl`) therefore match: the final tree equals the prototype file for file, so E5 holds.

## Findings

### C1. major: the fold's carried gradient flips at the first pair's bisector, so the field steps for non-identical triples

`packages/mobile/packages/ios_liquid_glass/lib/assets/shaders/sdf.glsl:81-89` (`angleSmoothUnion`), mirrored at `test/geometry/scene_sdf_mirror.dart:78-86`.

The returned gradient is `mix(near.yz, far.yz, h * w * 0.5)`. At the bisector `a.x == b.x` the roles of near and far swap, `h` is 1, and the result is `mix(a, b, w/2)` on one side and `mix(b, a, w/2)` on the other. They are equal only when `w == 0` (parallel normals, the coincident case) or the normals are identical. The next fold step uses that gradient to compute its own `w`, so the output distance jumps across the first pair's bisector whenever a third shape is within `k`.

Ruling 33 diagnosed exactly this ("the fold's normal output is discontinuous at the bisector") but fixed only the trigger (two copies of one rect). The guard is a real fix for coincident shapes and for near-identical ones: `w` scales as the square of the angle, so a 0.5 pt offset gives a step far below a pixel. It does not fix the shader.

Evidence (the repo's own mirror, step measured at x = bisector -/+ 1e-5, scanned over y):

- Three 44 pt circles, centres (0,0), (52,0), (-7.68,17.77): **0.87 px** at k = 8, **2.14 px** at k = 20.
- A row of three 44 pt circles with k = 40: 0.34 px (gap 0), 0.16 px (gap 8), 0.08 px (gap 12). The same row at k = 8 and k = 20, and a symmetric triangle at k = 8/20/40: 0.0000.
- A Python port gave the same numbers (best of 4000 random third circles: 0.86 px at k = 8, 2.10 px at k = 20).

Exposure today: low. The shipped call sites are rows at spacing 8 (container default) and 20 (`GlassScope`); rows at k <= 20 are clean, and the union scene folds only two union outlines. It is reachable by an asymmetric cluster of three or more shapes, or a row at a large spacing. A morph with a ghost, a member and a partner is a candidate and I did not test it on screen.

Suggested fix: make the carried gradient symmetric, `mix(near.yz, far.yz, h * 0.5)` (equal weights at the bisector, so no jump). In both ports this took the step to below 4e-4 (numerical noise) at k = 8 and 20. The value of a two-shape union is unchanged (the gradient is only consumed by later folds), but three-or-more-shape values change, so Task 27's tables for scenes with three or more shapes would need a re-measure. Reasonable alternatives: carry it to project 3 with a FORK.md line, or fix it now. It is not a merge blocker.

### C2. minor: no test ties the shader to its Dart mirror, and nothing pins the fold step

`test/geometry/angle_union_test.dart`, `scene_sdf_mirror.dart`.

`flutter test` cannot compile the geometry shader (gotcha 39), so the "blend continuity" and "angle union" tests exercise a Dart copy of the formulas. Mutations that passed all 239 package tests:

- `sdf.glsl`: `w = (1 - dot) * 0.7` instead of `* 0.5`.
- `sdf.glsl`: `near` chosen as the larger distance.
- mirror: `t = h * w * 0.5` changed to `t = h * 0.5` (which is the C1 fix), in `test/geometry`.

So the angle weight, the near/far choice and the fold step have no test that can fail on the real shader, and no test covers a three-shape fold at all (C1 would have been caught by one). Suggested: a parity test that parses the numeric constants and formula text out of `sdf.glsl`, plus a continuity test of the mirror on a three-shape cluster.

### C3. minor: arrival-first pairing in `leave()` and the double-partner guard are unpinned

`glass_motion_coordinator.dart:908-915` (`leave`), `:741-746` (`join`).

With the whole `leave()` pairing replaced by `false`, `glass_morph_test` still passes (the tests all take the `join`-side path; removing the `join` pairing fails 3). Removing only `&& !_leaving.values.any((other) => identical(other.partner, arrival))` also passes. So the order "arrival joins, then the leaver leaves" and the "one arrival, two leavers" guard have no test. Add a swap test where the new widget mounts before the old one deactivates, and one with two leavers sharing an id.

### C4. minor: `fitvis` fits the appear exponent on the measure that later judges it

`fitvis.py:405-440` (`moving_score`, `fit_appear_exponent`).

The exponent is chosen to minimise failing Done measures against every native appear, and the materialize table (296/336 normal, 147/168 Reduce Motion) is then counted on the same appears. It is in-sample. Disclosed in the objective string, but the headline count reads as a held-out pass. State it in the results next to the counts.

### C5. minor: `RenderGlassContentBlur._changed` skips the repaint during `persistentCallbacks`

`glass_motion_widgets.dart:431-433`.

`resolveGhosts()` runs from `_RenderGhostStack.paint` and calls `_blur(best)`, which sets `contentBlurred.value` during the persistent-callbacks phase; the listener then declines to `markNeedsPaint`. If that glass was painted earlier in the same pass its blur applies one frame late. The coordinator ticker is still running (`_blurred.isNotEmpty` keeps `moving` true) and `_publish()` notifies each frame, so the lag is at most one frame; I did not reproduce a visible frame. Note for the real-app pass.

### C6. note: the coincident guard compares geometry only

`liquid_glass_blend_group.dart:446-476`.

Verified, not defects:

- Tolerance 1e-3 pt on all four edges, then a canonical outline: ellipse is `(ellipse, 0)`; a rounded rectangle on a square with radius >= half the side canonicalises to an ellipse; other rounded rectangles compare `min(r, halfShort)`; squircle `min(1.65 r, halfShort)`.
- The 1.65 duplicates `SQUIRCLE_EXTENT` (`sdf.glsl:18`) as a literal; if one changes the other drifts.
- Ghost-then-member on one rect: the member takes the ghost's slot (`:341-346`). Member-then-ghost: the ghost is dropped. The cap then removes transient candidates from the end only, and counts after de-duplication.
- Seventeen members still exceed the cap with nothing to drop. That is as before 2B.2.
- Dropped members still paint (`paintShapeContents` walks `link.shapeEntries`).
- The guard also drops a second glass with a different tint on the same rect. Within a container glasses must be `sameMaterial` to be grouped, so this cannot happen via `GlassEffect`.

### C7. note: lifecycle paths read clean

- `_GlassEffectState.deactivate` (`glass_effect.dart:158-178`) reads no transform: `leave()` uses `_globalRect` (stored `_lastDrawn` and `_spaceOrigin`), `_scrollShift(null)` reads only `ScrollPosition.pixels`, and the snapshot is a retained layer (gotchas 37, 44).
- The overlay entry is inserted post-frame (gotcha 42) and removed through `onIdle`/`release`; `retain` after removal creates a new entry.
- Tickers: `_start` is guarded by `_disposed`; `spacingTo` goes to `AnimationNone` when disposed or muted.
- A leave that is ghosted and then disposed before `takeGhosts` leaves the member in `_leaving` until the coordinator disposes (`_dropLeaving`); a bounded delay, not a leak.
- Chained swaps: the removed-partner branch (`_step`, `:517-519`) samples the partner's own spring; mutation M3 confirms the chained-swap tests guard it.
- Median member side (ruling 30): `_followSides` (`:640-648`) takes the upper median `sides[n ~/ 2]`, excludes disappearing members, and an explicit `side` sets `followMaterial = null`. Re-run on join, leave, rejoin, drop and resize. Mixed sizes use one row, a stated and accepted limit.
- Spacing: `GlassEffectContainer.spacing` default 8; the only non-lab call site is `GlassScope`, which now passes `spacing: 20` and `side`, so nothing changed in the app. Example lab `GlassEffectContainer(child: ...)` sites (`material_scenes.dart:218`, `motion_scenes.dart:85`) take 8; the union scene gap is 16, so no behaviour change.

### C8. note: harness changes read for measures that cannot fail

- `finite_difference` and `topology()` now return NaN for "no neck / no gap" and treat NaN against NaN as agreement (0). A measurement that fails identically in both apps reads as agreement. `count` still guards it. Stricter elsewhere: a transition present in one app and absent in the other is `inf` (it used to be skipped), and `compare_topology` no longer returns `None` when neither app has two shapes.
- `series_rms` skips samples where one app has a neck, the other none, and the counts differ (the `count` measure owns them). With equal counts and one NaN it yields `inf`, so it fails.
- `significant()` now also counts a topology change; this only adds events (stricter).
- `fitvis --write`: `MORPH_BLUR_LINE` keeps the hand-placed line; if the file's value were formatted in a way the regex misses, the constant would vanish and the build would fail loudly, not silently. The tests named in ruling 23 cover the keep and the add-none case.
- `lab.py case_noise` re-points a broken or wrong-take symlink; `noise.json` differences against base are limited to the one case the ledger names.
- `ios27MorphContentBlur = 1.5` is the one disclosed hand-placed value; `ios27_motion.dart` otherwise has the plan's exponents (1.85 / 1.95 / 2.45). `ios27.dart` and `ios27_scroll_edge.dart` are untouched.
- `gap_pt` threshold 1.0 equals `neck_pt`'s; limits still take `max(threshold, NOISE_FACTOR * noise)`. Nothing loosens a limit.
- `fill_holes` in `track.py` closes any ring of glass, so a loop of three or more shapes with an enclosed gap would read as one filled component. Not in any scene.

### C9. note: rule compliance

- No added comment lines in Dart, Python, GLSL, Swift or shell (searched the added lines of `lib`, `test`, harness and Swift). The old `// Optimized` comments in `sdf.glsl` were removed with the code they annotated.
- All 38 commits carry `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- No `package-lock.json`, `.g.dart`, `pubspec.lock`, build or `.DS_Store` files; the diff touches only `packages/mobile` and `docs/liquid_glass`.
- No whole-file format noise: the largest changed lib files are net additions (`glass_motion_coordinator.dart` +478/-20, `material_scenes.dart` +44/-52 is the union scene rebuild).
- Fitted tables: only `ios27_motion.dart` changed, as above.

## Mutation results (all reverted; `git status` clean before the worktree was removed)

| # | Mutation | Tests run | Result |
|---|---|---|---|
| M1 | `_coincident` always false | `glass_group_test`, `coincident_union_test` | killed: 7 fail |
| M1b | ghost-vs-member precedence removed (`candidates[twin].$2 && !transient` to `false`) | `glass_group_test` | killed: 1 fails ("a ghost on the same rect as a member never stands in for the member") |
| M1c | tolerance 1e-3 to 2 | `glass_group_test` | killed: 1 fails (pixel shift) |
| M1d | oval rule: drop the `isSquare` condition | `glass_group_test` | killed: 1 fails ("on a wide rect a capsule is not an oval") |
| M2 | cap removes members before ghosts | `test/motion` | killed: 3 fail |
| M2b | cap never removes | `test/motion` | killed: 3 fail |
| M3 | content ghost never samples a removed partner (`live = true`) | `glass_morph_test` | killed: both chained-swap tests fail |
| M3d | both swap pairings off | `glass_morph_test` | killed: 3 fail |
| M3e | `join` pairing off | `glass_morph_test` | killed: 3 fail |
| M3b | `leave()` pairing off | `glass_morph_test` | **survived** (C3) |
| M3f | drop the double-partner guard | `glass_morph_test` | **survived** (C3) |
| M4a | anchor: drop the space-origin term in the shift | `test/motion` | killed: 2 fail |
| M4b | anchor: origin = zero | `test/motion` | killed: 2 fail |
| M4c | animate on origin change alone | `test/motion` | killed: 1 fails ("glass whose container only moves with its parent follows at once") |
| M5a | `sdf.glsl` weight 0.5 to 0.7 | whole package | **survived** (C2) |
| M5b | `sdf.glsl` near/far inverted | whole package | **survived** (C2) |
| M5c | mirror `t = h * 0.5` | `test/geometry` | **survived** (C2) |

## Executor rulings E1-E10

- **E1** (per-task reviews skipped for replayed patches): accept. The patches are a reviewed prototype, I confirmed the tree equals it file for file, and this review is the whole-branch read. The cost named (a defect found late) is real but I found none in the replayed code except C1/C2, which are in the prototype's design, not the replay.
- **E2** (sonnet helpers): accept.
- **E3** (dangling-link count 14): accept. The 14 are inside `excluded/`, which `relink_noise.py` skips by design.
- **E4** (take 5 first-frame gap 18.3 ms): accept; `take_check` passes on it.
- **E5** (three regenerated patches): accept, verified by `cmp`.
- **E6, E7**: accept (order and compiler-ordering details).
- **E8** (no take excluded at Task 25 Step 5): accept with a caveat, and it is the one the user should see. `take_check`'s own rule flags 27 of 40 morph takes as a capture hole; the executor's counter-evidence is 2 touches in all 40, no zero-length window, stack 10-90 % times of 252-373 ms agreeing between passing and flagged takes, and the long first gap being the still screen before the tap. That reads as sound. Two things weaken it: the flagged pattern (gap of about 400 ms followed by frames 1.7-3.3 ms apart, `burst >= 2`) is the same shape as gotcha 47's squeeze, and `dark-photo/4` has a 535 ms step-1 time against 367 for the rest. A squeezed take widens a noise floor, which loosens the morph limits. I did not recompute the floors (it writes caches into the recordings that another auditor reads), so I cannot say whether excluding the 27 changes any limit. Recommended: recompute morph floors with and without the flagged takes and put the delta in the results; if no limit moves by more than one step the ruling stands.
- **E9** (reruns C and D replace originals, A, B, E do not): accept; one consistent rule (a rerun replaces only if `take_check` is clean) and the counts for the alternative are stated.
- **E10** and ruling 33: accept; the user decided on 2026-10-08. The navbar.inline still regression (12 worse rows, a classed failure of spec §8) is disclosed in `results-2b2.md` and needs no new decision.

## Items for the user

1. C1: fix the carried gradient now (one line, `h * 0.5`, then re-measure the scenes with three or more shapes) or record it as a project 3 carry-in with a FORK.md line. Not reachable by current call sites.
2. E8: whether to accept the morph noise floors without a with/without comparison, or ask for the recompute first.
3. C2: whether to add a shader/mirror parity test before merge (cheap) or leave the shader guarded only by lab runs.
4. Already decided and still standing: the navbar.inline break of "still glass no worse than 2A", and the median-member material row.

## Not checked

- Any lab recording, simulator, native build or on-screen frame; the byte-identity claims for moving frames (ruling 33 re-run) and every number in the results tables.
- A `noise_recompute.py` or `take_check.py` run (they write into the recordings); I read their saved output only.
- Line-by-line audit of the 41 replayed patches' test files beyond the mutation sample; `glass_materialize.dart`, `glass_shape_motion.dart` consumers and the Swift scenes were skimmed, not traced.
- Shader performance with 16 shapes and gradients per pixel (the unrolled loop was replaced by a single loop).
- `dart format` conformance of the touched files.
- Whether the ghost host and overlay behave correctly under route transitions on a device (only the code and tests were read).
