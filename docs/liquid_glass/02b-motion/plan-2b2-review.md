# Independent review of the ios_liquid_glass 2B.2 plan

Location: the session scratchpad (`.../scratchpad/plan-2b2-review.md`). Nothing under the prototype worktree was edited or committed. Probe test and logs beside this file: `review_probe_test.dart`, `review-replay.log`, `review-counts.txt`.

## What I ran

- Fresh `git worktree add --detach <scratch> development` (tip `5ddb25328`), `research/proto-2b2/` brought from `proto/2b2`, then the plan's own `plan/replay.py` over `plan-2b2.md` (20 patches, 58 RUN lines). Scratch worktrees removed afterwards.
- Replay result: **20 patches, 58 runs, 0 problems** (every RUN had the stated outcome and its last lines equalled the "Expected output" block).
- Gate lines at the end of the replay: app `flutter analyze` "No issues found!", `flutter test` `+2188: All tests passed!`; package analyze "No issues found!", `+202: All tests passed!`; example analyze "No issues found!", `+23: All tests passed!`; `python3 -m unittest discover tool/glass_lab/harness/tests` `Ran 237 tests` / `OK`; `lab.py build native` `built for 708879DD-8B2A-4547-863F-F49EE1474D8B`.
- Tree check: the 51 files the 12 prototype commits change under `packages/` are byte-identical (replay tree against `proto/2b2`, `cmp` per file): 51 files, 0 differing. So the code embedded in the plan equals the prototype.
- Recomputed numbers from the recordings and JSON on disk (table below), read the full-resolution union and morph crops, ran two probe tests of my own against the prototype package (F1, F2).
- No simulator recording was made, no simctl command was issued.

## Verdict

**Ready to execute: yes after fixes.**

The patches replay clean and every number I recomputed matches. What stops me from saying "yes": two real package bugs the plan ships without listing (F1, F2), a data gap that makes the committed `noise.json` disagree with the takes an executor will have (F3), two decisions whose framing hides a measure change (F4, F5), one behaviour with a ruling number but no evidence (F6), and several execution-section gaps (F10, F11). None needs the prototype rewritten; F1, F2 and F3 need a plan edit (fix or list), the rest are text.

Counts: blocker 0, major 6 (F1 to F6), minor 9 (F7 to F15), note 4 (F16 to F19). Decisions that need the user: F4 (D3 and D2 framing), F5 (spacing animation), plus the five D1 to D5 as framed (section "Decisions").

## Findings

### F1 (major): chained morph swaps leave a content ghost and a running ticker forever

- Where: `glass_motion_coordinator.dart`, `GlassGhost._step`, content kind (Task 11).
- Failure: a content ghost (partner morph) reports `partner._morph.isMoving`. The partner's `_morph` spring is advanced only by `GlassMember._sample`. When the partner is itself removed and paired with a third glass (same id, same frame), its own ghost is also of kind content, whose `_step` never calls `member._sample`. The first ghost's `partner._morph.isMoving` then stays true for ever: `_tick` keeps `moving = true`, the ghost is never dropped, its snapshot is never released, and the ticker never stops.
- Evidence (my probe, `review_probe_test.dart`, same pattern as `glass_morph_test`'s `_Swap`, three id'd positions a, b, c): swap a to b, then b to c 60 ms later: ghosts `[content, content]`; after 5 s `[content]`, `hasScheduledFrame` true, `pumpAndSettle` times out at 20 s. Same at a 300 ms gap. At a 1500 ms gap it settles. So any second swap inside the first morph (about 650 ms) triggers it: a double tap on the morph toggle.
- Fix: in the content-kind `_step`, advance the partner when it has no live driver (or hold a reference so the partner's own ghost samples it), and end the ghost when the partner is removed; add a test "swap, swap again inside the morph, then settle: no ghosts, no scheduled frame". Or list it in ruling 21 as a known defect with D5.

### F2 (major): the 16-shape cap with a sinking ghost is unpinned, spec §9 asks for it, and the code throws

- Where: `liquid_glass_blend_group.dart:279-284` (`updateGeometryShaderShapes` throws `UnsupportedError` above 16, outside the `try` in `gatherShapeData`); `glass_motion_widgets.dart` `_Ghost` (`pending` and `sink` ghosts use `LiquidGlass.grouped`, so they register in the container's blend group).
- Failure: a container holding 16 glasses where one is removed (pending or sinking ghost, 1 shape) while another is inserted with an id (a morphing arrival is `present`, so it is in the group at once) draws 17 shapes: the first frame the shader runs throws in paint. Also 15 glasses plus an arrival plus two sinking ghosts. 2B.1 ghosts used their own layers, so this is new in 2B.2. Spec §9 lists "the 16-shape cap, counting glass still animating out" as a required package test; the plan's Review Focus 4 admits no test exists.
- Evidence: by reading; I could not reproduce it at runtime because `flutter test` cannot compile the geometry shader (ROADMAP gotchas 3 and 39), and `RenderLiquidGlass` objects do not exist in tests. My probe built 16 glasses plus one removed-with-id plus one id'd arrival and the member and ghost counts add to 17 (members 16, ghost kind `sink`), no exception only because paint is not run.
- Fix: before a ghost or arrival joins the group, count `link.shapeEntries` and fall back to `dematerialize` (own layer) or `materialize` when the group is at 16; pin it with a render-object-level test that constructs `RenderLiquidGlassBlendGroup` and feeds 17 entries, as gotcha 39 prescribes. Or make `gatherShapeData` drop the oldest ghost rather than throw.

### F3 (major): the replacement take for gotcha 52 is not in the executor's `noise-2b1`

- Where: Execution setup ("copied, never moved, from `/Users/omaraly/development/AI/glass-lab-runs/2b1/`"), Task 3, ruling 5, Task 14 Step 7.
- Failure: Task 3 commits a `noise.json` recomputed with take 2 of `noise-2b1/takes/material.materialize/light-photo-reduce-motion/` excluded and a new take 5 added. That exclusion and that take exist only in the prototype worktree's `build/glass_lab/runs/noise-2b1/` (untracked). The archive the plan tells the executor to copy has takes 0 to 4 including the bad take 2, no `excluded/`, no take 5 (checked: archive lists `0 1 2 3 4`, prototype lists `0 1 3 4 5` plus `excluded/README.txt`, `relinks-2b2.json`, `stale-pairs/`). The executor's `noise.json` therefore matches no take set on its disk; any `lab.py repeat`, `noise_recompute.py` or `fitvis ... noise-2b1` (Task 14 Step 7 re-fit reads it) will either reproduce the old limits (`cy.peak_ms` 150 again) or read take 2 as an outlier-free take.
- Fix: add a Task 3 step that copies `noise-2b1` from the prototype worktree (path, size, checksum of take 5) or applies the exclusion and installs take 5 from a named location; state where take 5 lives so it survives the prototype worktree's removal.

### F4 (major): D3 option A and D2 option B change measures, and D3 A has no code behind it

- Where: plan "Decisions" D2 and D3; Review: spec §8 "No limit or measure is ever loosened".
- D3 A says "replace `width.*` ... by a key that exists for these circles (an outer-edge position) and give `material.morph` per-glass tracking" and "no comparison is lost". `manifest.MOTION_MEASURES` (`manifest.py:14-20`) knows only `width, height, cx, cy, luma`; no outer-edge key exists in `track.py`, `shapes.py` or `analyze.py`, and no task writes one. So A is not executable inside this plan, and it also shrinks the denominators (merge `expected` 66 would drop by the 20 absent width measures per case; morph by its width/topology absences): a measure-set change the plan frames as a "manifest correction". It also hides that the prototype's own manifest (commit `96d7d5d03`) introduced the impossible `width.*` measures, so the 20/41/66 style counts carry 20 constants-by-construction failures per case.
- D2 B ("pinned regions without glyphs") shrinks the measured region to pass; fairly labelled a choice, but it should say it is a measure change that needs explicit approval, like D3 A. D2 A edits the example scene to match native ink, which is a test-content change, not a package change: say so.
- Fix: say in D3 that A needs new harness code (name the key, add a task or a follow-up), that it changes denominators, and that B keeps 20 absent failures per merge case in every count; say in D2 that B is a region change.

### F5 (major): spacing animation has a ruling number and no native evidence

- Where: ruling 12, Task 4 (`spacingTo`, `blendMotion`, `ValueListenable` plumbing, `glass_spacing_test.dart`, 174 lines), spec M4 ("Merging needs no separate animation").
- Failure mode: no native scene in this plan or in 2B.1 animates a container's `spacing` (the N7 scenes are still images), so "springs with the transaction's animation, else the scope's, else the default" is a design choice, not copied behaviour. Spec decision 9 and M-wide practice are "copied exactly, nothing built from description". It adds a ticker path, a listener on the render object, and a new default (`GlassEffectContainer.spacing` 8, `LiquidGlassBlendGroup.blend` still 20).
- Fix: either list it as a sixth decision (D6) for the user, with "remove it, spacing changes at once" as the option, or record in the ruling that no native evidence exists and the behaviour is the package's own.

### F6 (major): ruling 18's emergence source and the sink threshold are hypotheses presented as evidence

- Where: ruling 18, `R/morph/findings.txt`, spec M6 ("working guess is the nearest").
- Evidence: in native's expand every appearing glass starts at the toggle's old centre, but at each emergence the toggle (or the nascent heart) is the only or the obviously closest candidate, so "nearest glass" is indistinguishable from "the glass that was tapped" or "the one with the matched id's neighbour". The collapse rule "within `spacing` sinks, farther dematerializes" is labelled in `findings.txt` as "hypothesis (untested)": heart and bolt are 36 pt away, the star 108 pt (gap 52 pt), so any threshold from 0 to 52 pt fits. The plan states both as rulings "evidence from native".
- Also: heart and bolt are fitted with different springs in native (0.58 to 0.62 s and 0.35 to 0.38 s, `tracks.json`, recomputed) while the package uses one spring for all arrivals; that is a class (a) difference ruling 21 does not list.
- Fix: say "untested; consistent with" in ruling 18; keep the class list honest; optionally a native scene with two candidate source glasses.

### F7 (minor): the video topology mask is validated on native merge only, in-sample, by eye

- Where: ruling 2, `R/topology/`.
- 120 hand labels (5 cases x 24 frames, 60 joined and 60 apart), threshold and closing chosen on those labels, labels made by eye. The mask is then used on Flutter frames, on `material.morph` (no labels) and on the union. A mask that closes 5 x 5 and fills holes can read a thin real gap as joined in both apps. Hold-out check missing.
- Fix: label a few Flutter merge frames and some morph frames before judging, or list "mask validated on native merge only" next to ruling 2's evidence. Also the limitation already recorded for the still mask on stripes (ruling 3) means native dark-on-stripes glass is not seen: counts there agree trivially in the cases where neither app's glass is seen.

### F8 (minor): the "red" evidence is exit status only

- All Dart reds are compile errors (`isn't defined`, `Type ... not found`), not assertion failures, so they prove the test files reference new API and nothing about the assertions. The GLSL itself is never run by `flutter test` (gotchas 3 and 39); `scene_sdf_mirror.dart` is a Dart copy of the shader pinned only by tests written against itself. I read both side by side and they agree line for line, but nothing enforces it.
- The replay claim "every new test failed before its implementation, with one exception" is wrong: Task 12 adds two tests and `FAILED (failures=1)`; `test_a_write_to_a_target_without_the_morph_content_blur_line_adds_none` passes before the implementation (Task 12 Step 2 says "each new test fails").
- Fix: correct the sentence; name the second exception.

### F9 (minor): gotcha 52: three of the eighteen moved limits are looser and the plan does not say so

- `R/gotcha52-moved.json` (27 entries, 18 limits moved, matches `t03-limits` `moved 18 bad 0`): 15 limits fall (e.g. `cy.peak_ms` 150 to 25), 3 rise: `block.step1e0.cx.peak_ms` 17 to 25, `block.step1e0.width.response_pct` 5 to 9.23, `block.step3e0.luma.peak_ms` 25 to 62.5. Each equals 1.5 x the recomputed noise (16.67, 6.15, 41.67; before 8.33, 3.08, 16.67), so they are honest under max(fixed, 1.5 x noise). But the plan says only "18 limits moved, for example 150 to 25", and the only change between the two sets is the replacement take, so it is the take that raised these three; the plan's own rule "never let one take set a floor alone" is stated for Task 13 but not checked here. 2B.1's Done item 4 (266/336) was judged under the old floors; the carried 289/334/336 uses the new ones, so the two are not the same yardstick.
- Fix: list the three, say which take sets them, state the yardstick change.

### F10 (minor): Task 13 and Task 14 execution gaps

- Replacement command: Step 5 says "`repeat --times 1` appends" but `repeat` records every case of the scene unless `--appearance`, `--backdrop` and `--a11y` are given; as written one bad take costs a take in every case of that scene (and an extra pair set).
- No stop rule: `repeat` writes `noise.json` first and exits non-zero on "static repeatability FAILED" (`lab.py:264-266`); Step 2's loop has no `set -e` and no instruction for a failing scene; Step 6 expects no FAILED line but gives no action.
- Reboot rule: gotcha 49 is stated generically in Global Constraints, but Task 13 Step 1 and Step 3 check the press only at the two session starts; each session is 2 to 3 h and gotcha 49 saw 2.0 to 2.4 s presses at 7.5 h and a good press at 4 h. Task 14 (merge, union, 16 morph cases, 46 spacing cases, materialize in both modes, 9 still scenes: several hours) says only "As Task 13 Step 1" once.
- Stale build: nothing says what to do on `the native app build is older than its sources; run lab.py build native first` (`build.require_fresh`, raised by `repeat`); any package edit from a D5 fix wave or a `fitvis --write` makes the example stale, and Task 14 Step 7 may do exactly that.
- Disk: stated (95 GB, 40 GB floor, group-wise). The machine had 64 to 65 GB free during this review, so the executor must take the group path and ask the user to clear caches; say it.
- Task 13 "none carried from 2B.1" conflicts with re-recording `material.spacing.40.{a,b,c}` and `default.{a,b,c}`, which already have 2B.1 floors: `repeat` overwrites those entries.
- A patch or output mismatch has one generic line ("find the cause, fix it and say what changed") and Global Constraints' list; no hard rule on when to stop and ask.

### F11 (minor): Done table template and counts

- "Expected after Task 14: at least the prototype's counts" is not a checkable number: `expected` is not constant between takes (`material.morph dark-photo-reduce-motion` 29/64/180 and `material.morph.plain dark-photo` 22/65/180 against 126 for the other cases of the same scene). Compare per measure name, not per total.
- Step 9 compares with 2B.1's still runs (a ratchet: each plan may drift by the noise allowance); spec's reference is 2A (`7e318a49f`). The check was never run in the prototype, and the shader rewrite touches every container scene; the only remediation named is `spacing: 20`. Add: if a pixel difference remains with `spacing: 20`, stop and report the shader, do not tune.
- D5 option A schedules the fix wave after Task 14, so the Done table describes the pre-fix package; say Task 14 is re-run after it, or put the fix wave before.
- The plan is honest that it will end with Done items 1 to 3 failing; Done item 4 depends on the still check that the prototype did not run.

### F12 (minor): numbers stated more strongly than the data

- Ruling 10 "pixel-identical to `spacing: 8` at every gap": `default-probe.json` compares only the four gaps 0, 4, 8, 12 of `material.spacing.default.a` (S8 max 0.0 in both appearances; every other spacing differs by up to 193 levels). The equality is real, the "every gap" is not shown (the series at `S8 (default)` in `n7-table.txt` covers 15 gaps but against the native explicit `S8`, which the plan does not use for this claim).
- Ruling 7 "reach is spacing / 2 within the gaps recorded": tightly pinned only at S8 (4/5), S20 (10/11), S40 (20/21) and S80 (38/40); S4, S6, S10, S12, S16 are sampled at 4 pt steps (S10 4/8, S12 4/8, S16 8/12), so spacing / 2 is consistent, not shown.
- Ruling 9 quotes the angle model's RMS (all at or under 0.5 pt) but the plain quadratic is equal or better at S4 to S10 (S6 0.33 vs 0.47, S8 0.226 vs 0.374, S10 0.372 vs 0.502; recomputed from `blend-at-spacing-light-photo.json`) and worse only from S12; the model is chosen on S16 to S80. Fine as a choice, but the ruling should show the whole row.
- README (package, `README.md`): "matches native's necks and bulges on the iOS 27 simulator for spacings from 4 to 80 pt" while 6 of 46 N7 cases pass end to end and no dark case does; reword to the measured claim.

### F13 (minor): H4 is fitted on the measures that judge it

- Ruling 22: each preset's exponent is chosen by minimising "failing Done measures per native appear" over the grid (`fitvis.py` `fit_appear_exponent`) against the same takes and limits the Done table then counts. Spec M3 says fit on the default animation, check on `.snappy` and `.bouncy`; here each preset has its own free exponent, so no independent check remains. The real-run improvement (266 to 289 of 336) is a real recording, which helps, but its native side is the same takes. Task 14 Step 7 allows a re-fit "if a measure moved by more than noise" on those same runs.
- Fix: say that the exponents are in-sample and that the Done-table gain is not an independent confirmation; keep the fitted values fixed in Task 14.

### F14 (minor): shader cost and two defaults

- `sceneSDF` lost its unrolled 1 to 4 shape path and, for every container (default spacing 8 now means `blend > 0` everywhere), evaluates per-shape gradients (`pow` for squircles) per pixel and runs the generic loop. Frame cost is 2B.3's (M10) but the plan should name the removal as the cost source so 2B.3 starts there.
- `LiquidGlassBlendGroup.blend` still defaults to 20 while `GlassEffectContainer.spacing` is 8; any direct use of the blend group keeps the old reach.

### F15 (minor): union membership jumps

- `GlassMember.unite(..., grouped: grouped && !member.ownsLayer)`: a materializing member leaves its union and rejoins when it settles, so the union's bounding rect and shape change in one frame (the capsule jumps). Ruling 16 states it as the rule; no native frame shows what native does when a union member appears. Say so.

### Notes

- F16: the plan ends with Done items 1 to 3 failing by its own forecast, so merging 2B.2 is a user decision on classed failures (spec §8 allows it), not a pass.
- F17: native morph references are one take per case; the native `light-stripes` expand take has a 192 ms touch hold against 70 to 83 ms in the others (`tracks.json` `hold_ms`), the plan mentions it for the star only.
- F18: all 19 prototype commits carry a Co-Authored-By line (16 "Claude Opus 5.5", 3 "Sonnet 5.5"); the plan correctly tells the executor to use its own line. No comments found in any added code line (`git diff 4db49edc3 proto/2b2 -- packages` filtered for `//`, `#`, `/*`): none. No whole-file `dart format` evidence. `ios27_motion.dart`: the three appear exponents and the existing gains are tool-written (`t10-table` replay line `('Default', 1.85, 1.85) ...`); `ios27MorphContentBlur = 1.5` is the one hand-placed value (D4).
- F19: gotchas 37, 41, 42, 44, 46: the new code reads no transform in `deactivate` (`leave` reads `_lastDrawn`, not a transform), `unite` and `_unionChanged` run in build and only mark paint, `resolveGhosts` runs in paint of the ghost stack and starts the ticker there (allowed). `angleSmoothUnion` at degenerate gradients: `sign(p)` zero on an axis gives a zero gradient for that pixel only, `len > 1e-6` guard, `h = max(k - |d1-d2|, 0) / k` with `blend <= 0` handled before (no divide by zero). Union with one member draws as itself (`count < 2` returns null). Morph with a removed partner is F1.

## Decisions that need the user (as the plan frames them)

- D1 (union dark material): framed fairly. Option A changes every container scene's material source and puts the 2A still check at risk; the plan says so and routes the check to Task 14 Step 9 (see F11).
- D2: A edits example content, B shrinks measured regions: see F4. Neither is a package defect.
- D3: frame is incomplete: see F4 (needs a new measure key, changes denominators).
- D4: framed fairly; note A breaks the project rule "fitted values are written by a tool" and the plan already says follow-up B. The table check in Task 12 is sound.
- D5: A leaves Task 14 measuring the pre-fix package; recommended order should be fix first, then Task 14 (F11). The recommendation to fix the one-frame mirror at onset is supported by the numbers (8 of 8 split onsets).
- New, from this review: F5 (spacing animation, remove or keep) and F6 (hypotheses recorded as rulings).

## Claimed numbers recomputed

| Claim (plan section) | Claimed | Recomputed | Source | Match |
|---|---|---|---|---|
| Hand labels vs tracker (ruling 2) | 120 labels, 0 disagreements | 120 labels, 0 disagreements (5 x 24; 60 joined, 60 apart) | reran `topology/merge_topology.py` on the five native folders | yes |
| 2B.1 mask vs labels (ruling 2) | 96 of 120 disagree | 96 (24 each on dark and light stripes, dark and light photo; 0 on light black) | same run, `labels_l1_mask_disagreeing` | yes |
| Threshold pass band 6 to 10 | 6 to 10, 8 centre | 4: dark-stripes 3 / dark-photo 5 labels wrong; 5: dark-photo 1; 6, 8, 10: 0; 12: dark-photo 3 and 9 transitions | `topology/threshold-band.txt` | yes |
| N7 one / two component gaps (ruling 7), light photo silhouette | 4: 0/4, 6: 0/4, 8: 4/5, 10: 4/8, 12: 4/8, 16: 8/12, 20: 10/11, 40: 20/21, 80: 38/40 | identical | `n7-photo-silhouette.json` + `n7-existing.json` | yes |
| S40 neck at gap 0, 20; tip at 24 (Review Focus 1) | 50 pt model neck; join to 20, apart from 21; 3 pt bulge at 24 | 50.0; 0.667 at 20; tip 5.0 at 21, 3.33 at 24 | `n7-series-light-photo-silhouette.json` | yes (3.33 for 3) |
| Default spacing equals 8 (ruling 10) | pixel-identical | S8 max 0.0 in dark and light photo at gaps 0, 4, 8, 12; all other spacings 101 to 194 | `default-probe.json` | yes (4 gaps only, F12) |
| Native default contact neck | 25.67 light, 24.67 dark, joined to 4, apart from 5 | same | `verify/n7-table.txt` rows `S8 (default)` | yes |
| Blend RMS, angle model (ruling 9) | S4 0.165, S6 0.47, S8 0.374, S10 0.5, S12 0.5, S16 0.334, S20 0.421, S40 0.426, S80 0.412 | 0.165, 0.47, 0.374, 0.502, 0.502, 0.334, 0.42, 0.427, 0.413 | rows of `blend-at-spacing-light-photo.json` | yes |
| Plain quadratic RMS | S40 3.926, S80 11.489 | 3.925, 11.488 | same | yes |
| Gotcha 52 | 27 entries, 18 limits moved | 27, 18; 15 tighter, 3 looser | `gotcha52-moved.json`, replay `t03-limits` | yes (looser not stated, F9) |
| H4 exponents | 1.85, 1.95, 2.45; failing 0.48 vs 2.11, 0.15 vs 1.76, 0.04 vs 2.42 | same (0.4792/2.1146, 0.1458/1.7604, 0.0417/2.4167) | `h4/fitvis-h4.txt`; replay `t10-table` | yes |
| Native morph springs (ruling 18) | heart 0.58 to 0.62 s / 0.65 to 0.67; bolt 0.35 to 0.38 / 0.64 to 0.66; toggle 0.28 to 0.32 / 1.75 to 1.97 | heart 0.58 to 0.62 / 0.65 to 0.67; bolt 0.35 to 0.38 / 0.64 to 0.66; toggle 0.28 to 0.32 / 1.75 to 1.97 | `morph/tracks.json` (4 cases) | yes |
| Toggle swelling | 56.67 to 70.67 (+14.0) | 56.67 to 70.67, 57.33 to 71.33, 58.0 to 71.67 | `morph/tracks.json` | yes |
| Native union (ruling 15) | two 144 x 64 capsules, 49 to 193 and 209 to 353, 16.0 pt apart (14.66 stripes/photo) | read in `union/findings.txt` and crop `union-light-photo.png` (two capsules, one per pair, no seam) | crop opened | yes (not re-measured) |
| Union D2 split | luma 4.48 = 3.54 glyphs + 0.94 glass; mad 5.65 = 3.69 + 1.96 | read in `verify/summary.txt`; per-stripe tone -5.0 to +4.9 light, -9.5 to -14.8 dark | `verify/union-tone-*.json` | yes |
| Merge counts, normal (`054755`) | 20/41/66, 24/45/66, 25/44/66, 25/46/66 (dark-photo, dark-stripes, light-photo, light-stripes) | identical | `verify/table.py` on the run folder | yes |
| Merge, Reduce Motion (`055356`) | 20/41/66, 22/45/66, 27/46/66, 26/46/66 | identical | same | yes |
| Union (`055926`) | light-stripes 15/19/19, dark-stripes 3/16/19 | identical | same | yes |
| Morph normal (`060205`) | 19/59/126, 24/55/126, 29/55/126, 31/58/126; plain 22/65/180, 17/61/126, 25/59/126, 16/36/126 | identical | same | yes |
| Morph Reduce Motion (`061306`) | 29/64/180, 26/59/126, 34/60/126, 39/62/126; plain 21/62/126, 26/60/126, 31/60/126, 29/60/126 | identical | same | yes |
| N7 end to end (`062403`) | 6 of 46 pass, all light photo: .6.a, .10.a, .20.a, .40.a, .80.a, .80.b | 46 cases, 6 pass: exactly those | same | yes |
| Gates in the replay | app +2188, package +202, example +23, harness 237 OK, analyze clean | identical in my replay | `review-replay.log` | yes |
| Files identical to `proto/2b2` | 51 | 51, 0 differing | `cmp` per file | yes |
| Task 13 case and take arithmetic | 72 cases, 360 takes, about 5 h | 8+2+8+8+46 = 72; x5 = 360; at 50 s = 5.0 h | plan text | yes |

## What I did not check, and why

- Native and Flutter recordings were not re-made or re-analysed beyond the saved summaries and `table.py` (heavy, no change to numbers expected; hard rule to prefer saved recordings). I did not re-measure the union capsule geometry (r 31.91, RMS 0.12) or the content blur 1.5 pt pool; I opened the union crop and the findings only.
- The geometry shader was not run: `flutter test` cannot compile it, and I did not run the example on the simulator. F2 is by reading.
- I did not re-run Tasks 13 and 14 (execution-only by the user's reduced scope), the 2B.1 still check, or `done_table.py` on the materialize runs.
- The full morph and merge failure classing in `verify/summary.txt` (classes a to d) was sampled, not recomputed per measure.
- I did not read all 7,900 plan lines: the patches are machine-generated from commits and verified by replay and `cmp`; I read every ruling, the Review Focus, the file map and Tasks 3, 13 and 14 in full and the new package, shader, harness and Swift diffs.
