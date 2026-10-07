# Re-review 1 of plan-2b2.md after fix round 1

Reviewer: independent (did not write the plan or the fixes). Plan and prototype untouched; this file is the only thing written. Tip `6d815172b`, diff base `4db370855`.

## What I ran

- Fresh `git worktree add --detach Operator-2b2-rereview development` (tip `5ddb25328`), `research/proto-2b2/` copied in from `proto/2b2`, then the plan's own `plan/replay.py` over `plan-2b2.md`. Scratch worktree removed afterwards (`git worktree list` shows none left); no simulator or simctl command was issued, nothing recorded.
- Replay result: **41 patches, 113 runs, 0 problems** (every RUN had its stated outcome and its tail equalled the Expected block).
- Gate lines from the replay's final tasks (24b): app `flutter analyze` "No issues found!", `flutter test` `+2188: All tests passed!`; package analyze clean, `+222: All tests passed!`; example analyze clean, `+25: All tests passed!`; harness `Ran 253 tests` / `OK`. The fix report's counts (2188 / 222 / 25 / 253, 41 / 113 / 0) all reproduce.
- Tree check: of the 56 files `proto/2b2` changes under `packages/` against `4db49edc3`, 55 are byte-identical (`cmp`) in the replayed tree; the 56th is `packages/mobile/tool/glass_lab/noise.json`, left to Task 3 as the plan says.
- Mutations in the scratch tree (each reverted, tree clean afterwards), all caught:
  - F1: restoring the old content-ghost `_step` (`partner._morph.isMoving`, `contentOpacity`) fails both `a second swap 60 ms ...` and `... 300 ms ...`.
  - F2: making the drop loop `continue` unconditionally fails 3 of the 6 `glass_group_test` tests (the two cap tests and `a ghost registered before the last member is the one left out`).
  - D5: `syncMoved` result ignored in `shapesMoved` fails `a settled geometry is marked for an update...`; counting the space's origin when the glass's place did not change (undoing Task 24b) fails `glass whose container only moves with its parent follows at once and springs nothing`.
  - F4: deleting `topology.gap_rms` from `manifest.MOTION_MEASURES` fails 18 harness tests, from `shapes.MOTION_MEASURES` fails 1 (the equality test), removing `ymax` from `EDGE_KEYS` fails 19.
- Recounted the D3 old and new manifest numbers from the same recordings (below).

## Verdict

**Ready to execute: yes after fixes.**

The prototype, the replay and the fix-round code hold. One execution defect stops Task 3 as written (R1); the rest is wording that overstates a check (R3), framing the user should see (R4), and gaps a fresh executor would trip on (R2, R5-R7).

Counts: **blocker 1 (R1), major 0, minor 6 (R2-R7), note 3 (R8-R10).**

## Findings

### R1 (blocker): Task 3 crashes in the executor's copy of `noise-2b1`; the prototype's hand relink is not in the plan

- Where: Execution setup ("copied ... `runs/noise-2b1`"), Task 3 Steps 1-3, ruling 5 and 6, Task 9 (applied later than Task 3).
- Failure: every `pair-*/native|flutter` link in the archive points at `/Users/omaraly/development/AI/Operator-2b1/packages/mobile/build/glass_lab/runs/noise-2b1/takes/...`, and that worktree no longer exists (`ls` fails; the first 400 links I listed are all broken). At Task 3 the harness is still `development`'s `lab.py`, whose `case_noise` does `if not link.exists(): link.symlink_to(...)`. On a broken symlink `exists()` is False and `symlink_to` raises `FileExistsError` (I reproduced this with a broken link in a scratch folder). So Step 2's `repeat` records take 5, then dies in `case_noise` on the first pair folder (`pair-0-1`), before `noise.json` is written. The executor re-runs, `repeat` appends take 6, and the plan's own checks (`take 2 excluded, take 5 present`, "next take number is 5") fail. The fix for broken links is Task 9 (ruling 6), which comes after Task 3. The prototype got round it by relinking all of its links by hand (`build/glass_lab/runs/noise-2b1/excluded/relinks-2b2.json` records the old and new targets); Task 3's "the moves are exactly the prototype's" does not include that step, and the plan never mentions broken links (`grep -i relink|broken` finds nothing).
- Evidence: `readlink` on the archive's links; `git show development:.../lab.py` lines 192-203 against the replay tree's lines 192-206; the prototype's `relinks-2b2.json`.
- Fix: put Task 9 before Task 3 (or add "apply Task 9's two patches first" as Task 3 Step 0), and say in Task 3 that the archive's pair links are all dangling and `case_noise` repoints a case's links when it recomputes it. Also say that a crashed `repeat` leaves a recorded take behind and what to do with it (exclude it, as in Step 5, then continue).

### R2 (minor): Execution setup gives no copy command; Task 3 does not build or install backdrops

- Where: Execution setup, Task 3 Step 2.
- Failure: "copied, never moved" has no command, and no `test ! -L` guard. If an executor links the archive instead of copying, Task 3's `mv` lines and `repeat` (which appends takes and rewrites pair folders) write into `/Users/omaraly/development/AI/glass-lab-runs/2b1/runs/noise-2b1`. I found nothing in the plan or scripts that moves or deletes archive files when the copy is real, so the plan is not destructive as long as it is a copy. Separately, Task 3 Step 2 runs `lab.py run material.interactive --app native` in a worktree that has never built the native app (the first `lab.py build native` in the plan is Task 7's `t07-native-build`). The refusal message is the stale-build one (the stamp is missing, same text), which the Global Constraints cover, but the backdrop install is never triggered by an error and is only described in Execution setup.
- Fix: write the copy (`cp -R /Users/omaraly/development/AI/glass-lab-runs/2b1/runs/noise-2b1 build/glass_lab/runs/` and what else of `native/`, `reference/` is needed, if anything) and a `test ! -L` check; add `lab.py build all` and the backdrop install to Task 3 Step 2.

### R3 (minor): ruling 30 and Task 27 Step 9 name a check that cannot see the D1 risk

- Where: ruling 30 ("Task 27 Step 9's 2A still check is the risk check"), D1, Task 27 Step 9, "What this plan expects" item 4.
- Failure: none of the nine still scenes holds an unpinned container. `material.regular|clear|tinted|edge` and the a11y runs draw `LabCentered` standalone blocks (`material_scenes.dart:14-30`); the `--flutter operator` scenes use the app's `GlassScope`, which pins `side: size` and `spacing: 20` (`glass_scope.dart`). The only `GlassEffectContainer`s in the example are the union, spacing, merge, morph and materialize scenes, which are native-compared elsewhere. So Step 9 exercises the shader rewrite on the app's pinned 20 pt groups, not the median-row change and not the 88 to member-size change; a regression for containers of mixed-size members is not caught by any step. The app itself cannot regress from D1 (it always pins `side`), which the plan could say and does not.
- Fix: say that Step 9 checks the shader and the pinned path only; say that the app pins `side`; if a mixed-size check is wanted, name the scene (the morph scene's members are the nearest) or list it as open.

### R4 (minor): D3 is labelled "user-approved" but built narrower than the user asked

- Where: Decisions D3, ruling 26, Review Focus 11.
- What the user asked (fix brief): `material.morph` gets per-glass tracking. What was built: `ymin` and `ymax` of the `stack` region only (the star's top and the toggle's bottom); the heart and bolt are still region boxes. Ruling 26 says so ("Not built: a tracker that follows the inner glasses"), but the Decisions list and Review Focus 11 present D3 as "option A, user-approved correction" and "`material.morph` loses nothing and gains `ymin`, `ymax`, `gap_rms`", so a reader of the Decisions block alone will think per-glass tracking exists.
- Honesty of the manifest correction itself: sound. Nothing that was judged is removed (the 20 `width.*` per merge case were unjudged constants: old judged 41 of 66 against new 61 of 68); no limit moves; old and new counts sit side by side in the Done template.
- Fix: one sentence in D3 ("narrower than asked: outer edges only"), and list it among the questions for the user.

### R5 (minor): disk arithmetic ends in a stop within Task 25's first group

- Where: Execution setup, Tasks 25 and 27 disk notes.
- Failure: 64 GB are free now. The archive copy is 8.6 GB on disk (the plan says about 13 GB with caches), leaving 51-55 GB. Task 25's group A (merge, morph, morph.plain: 24 of 62 cases) at 2B.1's rate (42 GB for 60 cases) writes about 17 GB, so free space falls under the plan's own 45 GB "ask" line mid-group, and Task 27's merge, morph and 46 N7 cases add more. The plan notes "the group path is the one to expect" but not that it will stop and ask in practice.
- Fix: say it plainly in Execution setup and ask the user for a cache clear or an external volume before starting.

### R6 (minor): Task 26 and 27 stop rules leave two gaps

- Task 27 refers to "Task 25 Step 1" for the press check and its 3-hour re-check, but only Task 25 (Step 2) says what a failed check does (throw away takes since the last good check); Task 27's `run` records both apps, so a stale press mid-run spoils native cases only.
- Task 26 Step 4 stops and reports to the main session when native does not animate `spacing`; it does not say whether Task 27 runs meanwhile (it consumes the same package and `material.respace` is not in its set, so it can), or that ruling 12, the README sentence and Task 4's `spacingTo`/`blendMotion` stay in the tree until the main session decides.
- The Step 3 criterion (three video frames, within one frame of the first change) is workable. Its confound is that SwiftUI may not interpolate a plain `spacing` parameter at all while still animating the glass shapes; the stop rule covers that, since the test is on the neck over time.
- Fix: one line each.

### R7 (minor): Task 3's `noise.json` is computed by an early harness

- Task 3 runs before Tasks 5, 6, 9, 12 change `analyze`, `shapes` and `track`. Its `repeat` writes the whole entry for `material.materialize/light-photo-reduce-motion` with that earlier harness; nothing re-checks it against the final harness. The materialize measures probably do not move (no topology there), but I did not verify it and the plan does not say.
- Fix: after the last harness patch, run `noise_recompute.py ... $CASE` again (no recording) and state that the entry is unchanged, in Task 27 Step 7.

### Notes

- R8 (D5 and F2 reading, no defect found). Space-origin anchor: the shift is `(previous - anchor) + (previousOrigin - origin)` and only runs when the glass's own place in its space changed (`previous == anchor` returns first), so glass that only moves with its parent follows at once; a space that moves alone moves the glass at once; a glass whose place and space both change gets the full on-screen shift (the Grow tests pin +100 inside against -50 space move). `_moved` is latched, so a member's own paint syncing first does not hide the move from the group's `syncMoved`. Marking `mightNeedUpdate` in paint touches only the geometry flag, not `markNeedsPaint`. `revalidateGeometry` ordering inside `maybeRebuildGeometry` is not pinned by a test (Review Focus 9 says so; the real-app `R/onset/` run is the check). F2's guard drops transient shapes last-registered first; a dropped sinking or pending ghost draws no glass for those frames while its content still fades, a pop only in containers at 16-plus shapes, against an uncaught `UnsupportedError` in paint before; seventeen members still throw (stated). `isTransient`, `syncMoved` and `shapesMoved` preserve behaviour: `sync()` is kept, `neck_rms` now delegates to `series_rms` with the same `finite_difference`, `significant()` is stricter (a count change counts), not looser.
- R9 (D1 as built, for the user). D1 asked each member to use its own size's row; built: one row per container, the median member's (upper median for an even count). For a 44 and an 88 pt member both draw with 88; for 44, 44, 88 all three draw with 44. Ruling 30, FORK and README state this limit plainly; the plan frames it fairly. It is the user's call whether that satisfies D1.
- R10 (F5 as built). `material.respace` has a native scene (`withAnimation { wide = ... }` on `GlassEffectContainer(spacing: wide ? 40 : 8)`, two 80 pt circles at gap 12 so the join happens when spacing passes 24), a Flutter scene (`withGlassAnimation(defaultSpring, ...)`), tap ids `widen` and `narrow`, manifest entry with `topology.*` and `gap_rms`, a noise floor in Task 25, and the stop rule in Task 26 Step 4; ruling 12 and Review Focus 12 say no native evidence exists. Fair.

## D3 counts recomputed from the same recordings

Old manifest: analysed with the harness exported from `4db370855` over a copy of the case folder; new: `table.py` on the run folders as they are.

| Recording | Case | Old (plan) | Old (mine) | New (plan) | New (mine) |
|---|---|---|---|---|---|
| `20261007-054755` merge normal | dark photo | 20/41/66 | 20/41/66 | 24/61/68 | 24/61/68 |
| same, other three | dark stripes, light photo, light stripes | 24/45/66, 25/44/66, 25/46/66 | not rerun | 30/67/68, 29/62/68, 33/68/68 | same as plan |
| `20261007-055356` merge Reduce Motion | dark stripes | 22/45/66 | 22/45/66 | 26/67/68 | 26/67/68 |
| same, other three | dark photo, light photo, light stripes | 20/41/66, 27/46/66, 26/46/66 | not rerun | 24/63/68, 33/68/68, 32/68/68 | same as plan |

Morph counts were not recomputed.

## First-review findings: resolved or not

- F1 resolved (fix, two tests, mutation caught). F2 resolved (guard, render-object tests, mutation caught; ghost glass drop is stated).
- F3 **not truly resolved: R1** (scripted moves and take 5 are in the plan, but the step cannot run).
- F4 resolved (`MOTION_MEASURES` in both files, equality test, mutations caught). F5 resolved as a plan decision (D6 plus Tasks 23 and 26). F6 resolved (ruling 18 now states both rules as unevidenced hypotheses and lists a control). F7 stated (mask validated on native merge only; Task 27 Step 6 adds a Flutter hold-out). F8 resolved (Task 12's named exception). F9 resolved (three looser limits named in Task 3 Step 3, yardstick change stated). F10 resolved except R1, R2, R6. F11 resolved (compare by measure name, 2B.1 ratchet said, `spacing: 20` stop rule; but see R3). F12 resolved (gaps measured, README reworded, angle model against quadratic stated). F13 resolved (in-sample stated, exponents fixed). F14 resolved (ruling 32, ruling 10's blend 20 versus 8). F15 resolved (ruling 16 and 32).
- Notes F16-F19: unchanged and stated; D4's 1.5 is disclosed as hand-placed.

## Rule compliance in the new diff

No added code line carries a comment (checked the `packages/` diff); no whole-file `dart format` visible (changes are line-local); all 15 commits since `4db370855` end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Limits that move: none in the code. New thresholds: `gap_pt` 1.0 (the neck's), edge travel 4.0 (the cx's); the three limits Task 3 will raise (15 fall, 3 rise) are disclosed and follow max(fixed, 1.5 x noise). Fitted values: written by tools except `ios27MorphContentBlur` 1.5 (D4, disclosed).

## Needs the user

1. R4: accept that `material.morph` is tracked at the stack's outer edges only (not per glass), or ask for the tracker.
2. R9: accept the median-member row for mixed-size containers as D1, or ask for per-member rows in one layer.
3. R5: free disk (or name an external volume) before Task 25; the plan will otherwise stop to ask in its first group.
4. R3: decide whether a mixed-size container check is wanted (no still scene has one).

## What I did not check

- No recording, simulator or lab run (Tasks 3, 25, 26, 27 are execution-only). Morph counts under both manifests were not recomputed; only two merge cases were.
- Whether `fitvis` or Task 27 read the dangling links of other `noise-2b1` cases (R1 shows the recorded case needs the fix; I did not trace every reader).
- The geometry shader itself (cannot compile in `flutter test`); the `sdf.glsl` and `scene_sdf_mirror.dart` correspondence was not re-read in this round.
- Whether a dropped ghost's glass leaves anything painted by the render object when its shape is absent from the geometry (read as the same path as non-lead union members, not run).
- The removed-partner branch of the ghost step beyond the two swap tests (no third swap, no partner removed by an unrelated sink).
