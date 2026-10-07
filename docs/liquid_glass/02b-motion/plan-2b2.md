# ios_liquid_glass 2B.2: merge and split, union and morph — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. A line `RUN[label]: \`command\` => PASS|FAIL` is a command to run from the repository root with that outcome; the "Expected output ends with" block after it is the command's last lines (timings aside).

**Goal.** Give the package native's merge and split, union and morph, and give the lab the measures that judge them:
- lab: topology that reads agreeing apps as zero and finds no neck without one joined component; topology masks that count native glass on stripes and photo; a still mask without the outline; `gap_pt`; a manifest that rejects topology measures without regions; `material.merge` tracked per circle and judged on the pair's topology on photo too, by each circle's outer edge and the pair's gap (D3, approved), `material.morph` also by the stack's outer edges; the `material.respace` scene for the spacing animation; native controls for the morph toggle's swelling; the N7 finer gap series and spacing probes; a fitvis that scores on simulated moving glass and keeps the morph content blur line; gotcha 52's floors;
- package: container `spacing` that means what native's does (glass deforms toward its neighbour below `spacing` and joins below `spacing / 2`), an angle-weighted smooth union in the shader, native's default spacing of 8 pt, spacing that animates like a move (the package's own design: its native reference is recorded and judged in Task 26); a container material that follows its members' size; the first frame of a move drawn where the glass was; second morph swaps that settle; ghosts that never overflow the sixteen shapes; `GlassNamespace` and `GlassEffectUnion` (a union draws as one capsule on its members' drawn rects); `GlassEffectID` and `GlassEffectTransition.matchedGeometry` (partner morph, emergence from the nearest glass, sink or dematerialize, content blur); an appear progress that is the spring to a fitted exponent (H4);
- example: live scenes for the 23 N7 spacing cases, the merge scene's pair, the rebuilt union scene (with glyphs sized to native's ink), the two morph scenes and `material.respace`, with native's tap ids;
- verification in `docs/liquid_glass/02b-motion/results-2b2.md` against spec §8 "2B.2 is done when".

**Architecture.**
- `sdf.glsl` replaces upstream's quadratic `smoothUnion` with `angleSmoothUnion`: a quadratic smooth-min with k = blend whose correction is weighted by (1 − n_a · n_b) / 2, the angle between the two shapes' unit gradients (ruling 9). `blend` is the container's `spacing`, driven by a `ValueListenable` the coordinator animates, so a spacing change needs no rebuild (ruling 12).
- A union is one shape in the blend group: the member that leads it contributes the bounding rect of its members' drawn rects, as a capsule for circles and capsules, and the members it leads contribute nothing; each member's content stays at its own place (ruling 16).
- A morph is the coordinator's work: an id'd glass that is removed while another with the same id is inserted in the same frame is one glass that springs from the old drawn rect to the new; an id'd glass without a partner emerges from the nearest glass's drawn rect, or sinks into a remaining glass within `spacing` and otherwise dematerializes; content is blurred while a glass touches another of the morph (rulings 18–20). Ghosts that sink draw through the container's blend group at a rect the coordinator moves every frame.
- The harness changes are measurement: the video topology mask is the luma change closed and hole-filled, the still mask the rim plus the grain the glass removes, the gap a measure of its own (rulings 2–4).
- Fitted numbers (appear exponents 1.85 / 1.95 / 2.45 with the disappear exponents and gains) come from `lab.py fitvis`, never by hand. **`ios27MorphContentBlur` is the one exception: it is placed by hand from `content_blur.py`'s pooled median, no tool writes it, and `fitvis --write` only keeps it** (ruling 23).
- A container's glass layer follows a material source whose side is the median of its members' sizes (ruling 30); the blend group asks its glass to sync before it trusts its cached geometry, and a glass's anchor includes its space's on-screen origin (ruling 29); ghosts are transient shapes that are left out of the geometry before a member when a container would draw more than sixteen (ruling 28).

**Tech stack.** Flutter 3.44.5 / Dart, Impeller runtime-effect shaders (GLSL 460), `motor` 1.1.0 springs; Python 3 (stdlib, Pillow, numpy) for the harness; Xcode 27, SwiftUI and XCUITest; the iOS 27 simulator.

**Spec.** `docs/liquid_glass/02b-motion/spec.md` (approved 2026-10-03): §4 (2B.2's scope), §5–§7, §8 "2B.2 is done when", §9, §12. Read `docs/liquid_glass/ROADMAP.md` §3–§5 and gotchas 35 and 43–52 first, then the spec, then `02b-motion/brainstorm.md`, `results-2b1.md` and `todo-2b1.md`.

**Where the code comes from.** Every patch below ran in a throwaway prototype: worktree `/Users/omaraly/development/AI/Operator-2b2-proto`, branch `proto/2b2` from `development` `4db49edc3`, the code committed as the twelve commits `fb0207573` … `1d2ddc57a` and, after the plan's independent review, eleven fix-round commits `3f5f59cbf` … `e320d0cbd` (the patch names below carry the range of each), with this plan, its builder and its evidence in the commits between and after them. The patches are generated from those commits by `docs/liquid_glass/02b-motion/research/proto-2b2/plan/build_plan.py` and applied in order by `replay.py`; nothing in this plan is retyped. Evidence lives under `docs/liquid_glass/02b-motion/research/proto-2b2/` (`R` below); its scripts write into `build/glass_lab/` of the prototype and read the recordings listed with each ruling.

**Replay check.** On 2026-10-07 the plan was applied patch by patch, and its `RUN` lines run, in a scratch worktree (`/Users/omaraly/development/AI/Operator-2b2-replay`, detached at the then `development` tip `5ddb25328`, with `research/proto-2b2/` brought from `proto/2b2` as Execution setup does), by `plan/replay.py` (log and results: `research/proto-2b2/plan/replay/`): 41 patches applied with `git apply --3way` without a conflict, 113 runs, **0 problems** (every run had the outcome the plan states and its last lines equal the "Expected output" block). The replay ran the plan before this paragraph was written; the paragraph is the only difference. **What the reds are:** every new test or test file in Tasks 1-12 fails before its implementation, mostly as a compile error (the tests name symbols the implementation adds), with two exceptions the steps name: the app's `glass_scope_test` (Task 4) and the fitvis guard test `test_a_write_to_a_target_without_the_morph_content_blur_line_adds_none` (Task 12) pass before their tasks by design; in Tasks 13-24b the reds are failed assertions (two refactor steps, 14 and 16, change no behaviour so that the next task's reds are assertions, and Task 21 likewise), and Task 15's `ghosts under the cap all stay in the geometry`, Task 20's `a container with an explicit side keeps that row` and Task 24b's five other tests pass before as well, by design. The first replay of this plan found one defect that is now Task 24b (the app's `floating_working_control_test` failed at the gates of Tasks 18 and 20: the first version of the space-origin anchor made glass that only moves with its parent spring); the app gate therefore does not run at Tasks 18 and 20 and runs, whole, at Task 24b. Final gates in the replay (Task 24b): app `flutter analyze` "No issues found!" and `flutter test` `+2188: All tests passed!`; package analyze clean, `+222: All tests passed!`; example analyze clean, `+25: All tests passed!`; harness `Ran 253 tests` / `OK`; the native lab app builds (`built for 708879DD-8B2A-4547-863F-F49EE1474D8B`). Of the 56 files the prototype's commits change under `packages/`, 55 are identical (`cmp`) between the replay's result and `proto/2b2`; the 56th is **`packages/mobile/tool/glass_lab/noise.json`**, which Task 3 makes from the executor's own takes and the replay (which records nothing) leaves as `development` has it; `development` had moved from the prototype's `4db49edc3` to `5ddb25328` with changes to `packages/mobile` (the spawn feature) and `packages/terminal`, none in those files.
**Second fix round (2026-10-07):** the plan's text changed (Task 3's copy, relink and build steps, the disk numbers, the D1 and D3 acceptances, Task 26 and 27's stop rules, the recompute check); no patch changed, so the 41 patches and 113 runs are as above and the replay was run again over this plan on a fresh export of `development` at `5ddb25328` (log: `plan/replay/replay-fixround-2.log`) with the same result: 41 patches, 113 runs, 0 problems, the same gate lines, and 55 of the 56 files identical to `proto/2b2` (`noise.json` the 56th). Task 3 is not replayable (it records on a simulator); its relink was proven on a throwaway copy of the archive's link layout: `development`'s `case_noise` raises `FileExistsError` on a dangling pair link, the same call after `relink_noise.py` returns normally, a second `relink_noise.py` relinks 0, and the script refuses the archive itself.

Transcribe nothing; apply the patches. If a step fails, find the cause, fix it and say what changed in the task report.

**Scope of this plan (the user's reduced scope, 2026-10-07).** The prototype ran each 2B.2 scene end to end once, normal and Reduce Motion, against native references recorded after a fresh boot, with the existing `noise.json` limits and the fixed thresholds. It recorded no L8 noise for the 2B.2 scenes: Task 25 does that in execution, and every limit the prototype's numbers were judged on, for `material.merge`, `material.union`, `material.morph`, `material.morph.plain`, `material.respace` and the 23 `material.spacing.*` scenes, is **provisional** (a fixed threshold; noise can only raise it). Those end-to-end runs (`R/verify/`) were made on the package **before** the fix-round commits (ruling 29's first-frame defect, ruling 27, ruling 28, D1, D2, D3): their counts are the baseline the Done table compares with, not what the final package will measure. The package defects that remain are in ruling 21; the plan expects them to fail and lists them.

**Rulings the prototype forced, with evidence.** Each refines or departs from the spec; where they differ, these win. Run folders are under the prototype's `packages/mobile/build/glass_lab/runs/`; `R` is `docs/liquid_glass/02b-motion/research/proto-2b2`. "Native reference" runs were recorded after a simulator boot whose 1.0 s press read 0.95 s (`R/verify/summary.txt`, run `20261007-054559`).

*Lab*

1. **Topology reads agreeing apps as zero; no neck without one joined component; the manifest rejects topology measures without regions** (todo-2b1's harness defects, Task 1, tests `test_shapes`, `test_track`, `test_manifest`). `compare_topology` returned `None` when neither app reached two components and omitted `join_ms` and `split_ms` when one side transitioned, so a listed `topology.*` measure read `inf` when both apps agreed; a frame that is not one component read neck `0.0`, which `neck_rms` counted as a zero-width neck (now NaN, and `neck_difference` compares two NaNs as agreeing and a NaN against a number as the number); a scene could list `topology.*` with no `topology` region.
2. **The video topology mask is the luma change, closed and hole-filled** (Task 5). A pixel is glass when its luma differs from the bare frame by more than 8 (`TOPOLOGY_LUMA`; H.264 rings mostly in chroma, so stripe-boundary ringing barely moves luma), the change is closed 5 × 5 with its holes filled so a glass seen only by its rim is solid, minus closing additions within 2 px of the outside (cusps are not filled, rim breaks are not bridged). `material.merge` native, 5 cases, 120 hand-labelled frames: the tracker equals every label, and the 2B.1 mask disagreed with 96 of the 120 (all stripes and photo frames); the pass band of the threshold is 6 to 10, 8 its centre (`R/topology/summary.txt`, `hand-labels.json`, `threshold-band.txt`, `merge-topology.json`). L1's `glass_mask` and `shape_row` are unchanged. **How far this is validated:** the labels were made by eye on native `material.merge` only, and the threshold (6 to 10) and the closing were chosen on those same 120 labels, so the agreement is in-sample; the mask is then also used on Flutter frames, on `material.morph` and on the union, none of which has labels of its own. A mask that closes 5 x 5 and fills holes can read a thin real gap as joined in both apps. Task 27 Step 6 labels a few Flutter merge frames and morph frames as a hold-out before the topology counts are trusted.
3. **The still mask is the rim plus the grain the glass removes** (Task 5). A pixel is rim when its max-channel difference from the bare frame exceeds 30 (`STILL_RIM`), and a window has lost grain when the bare's 3 × 3 high-pass energy over 5 × 5 is above 4 and the frame has lost more than 0.8 of it (the glass blurs the backdrop; the cusp outline only darkens it); the mask is those, holes filled. 141 native N7 takes, 531 regions: counts agree between dark photo, light photo, light black and the light-photo silhouette on every fresh region and in every 2B.1 take; light-photo necks are within 1 px of the silhouette (`R/topology/still-check.txt`). **Limitation, recorded:** on a backdrop without grain (black, stripes, white) only the rim marks glass, so native's dark glass on stripes is not seen (`R/verify/summary.txt` 2a, 6c; ruling 17's class (c) failures).
4. **`gap_pt` is a measure of its own** (Task 5): the empty pixels on the segment between the two components' centroids, threshold 1.0 pt like `neck_pt`, NaN unless there are exactly two components. Native's dark and light gaps differ by 0 to 0.67 pt away from the reach and up to 3.67 pt close past it (80.c gap 44: 26.00 against 22.33), because on light the dark outline outside the silhouette exceeds 30 levels and joins the mask while on dark it is about 10 levels; each app's own dark-minus-light gap is therefore checked against the other's (`R/verify/n7-table.txt`, `R/topology/still-check.json`).
5. **Gotcha 52 is closed by replacement, not by a new onset rule, and each executor does it in its own copy** (Task 3). The take `noise-2b1/takes/material.materialize/light-photo-reduce-motion/2` reads its disappear onset 98 ms before the glass moves, so it alone set that case's disappear limits (`cy.peak_ms` 150). The prototype moved it to `excluded/` and recorded a replacement after a fresh boot in its own copy of `noise-2b1` (untracked, in the prototype worktree's `build/`, so it does not travel; the archive the executor copies from still holds the bad take 2 and no take 5). Task 3 therefore does the same by scripted moves, with a check that take 2 is excluded and take 5 present, records the replacement itself after a fresh boot, and lets `lab.py repeat` write `noise.json` from the executor's takes; **no `noise.json` patch is applied**. The prototype's result is the expectation: 27 values and 18 limits moved (`R/gotcha52-moved.json`, `R/noise-spacing-moved.json`: no spacing limit moved), 15 limits lower (for example `block.step1e0.cy.peak_ms` 150.0 to 25.0) and **3 higher**: `block.step1e0.cx.peak_ms` 17 to 25, `block.step1e0.width.response_pct` 5 to 9.23, `block.step3e0.luma.peak_ms` 25 to 62.5, each 1.5 times a recomputed noise (16.67, 6.15, 41.67; before 8.33, 3.08, 16.67), so the replacement take is what raised them; they follow the rule max(fixed, 1.5 x noise) and are not loosened measures, but they are looser limits than 2B.1's Done item 4 (266 of 336) was judged under, and later counts (the carried 289 of 334 of 336) use the new ones, so **the two counts are not the same yardstick**; the Done table says so. Task 3's check does not allow a take to set a floor alone (see ruling 25).
6. **A noise pair folder whose link is broken or names another take is pointed at the take it pairs** (Task 9, test `test_a_pair_folder_left_from_a_removed_take_is_pointed_at_the_take_of_that_number_now`): after gotcha 52's take was moved out and its slot re-recorded, the pair folder of that number still linked the removed take. **It is not what makes Task 3 runnable:** Task 3 runs first, with `development`'s `lab.py`, on a copy of `noise-2b1` whose 1206 pair links all name the deleted `Operator-2b1` worktree; Task 3's own relink step (`R/relink_noise.py`) repoints them at the copy before `repeat` runs, as the prototype did by hand.

*Merge and split (spec M4)*

7. **Native merges glass at half of `spacing`, and the shape is felt from `spacing` out** (N7 stills, light photo silhouette, `R/n7-series-light-photo-silhouette.json`, runs `20261004-003527`, `20261007-000000`, `20261007-002556`). The largest gap at which the pair is one component and the smallest at which it is two, per `spacing`: 4 → 0 / 4, 6 → 0 / 4, 8 → 4 / 5, 10 → 4 / 8, 12 → 4 / 8, 16 → 8 / 12, 20 → 10 / 11, 40 → 20 / 21, 80 → 38 / 40 pt (gaps recorded around each join; `R/n7_summary.py` prints them). Reach is `spacing / 2` within the gaps recorded: it is pinned tightly only where the recorded gaps bracket the join closely (S8 4 / 5, S20 10 / 11, S40 20 / 21, S80 38 / 40); S4, S6, S10, S12 and S16 are sampled at 4 pt steps (S10 4 / 8, S12 4 / 8, S16 8 / 12), where `spacing / 2` is consistent with the data and not shown by it. Past it the facing edges bulge toward each other (`R/verify/n7-table.txt`, the gaps past the reach) and the field darkens in an 8 × 10 pt patch at the gap centre only where the compared fields lie within 3.5 pt of the silhouette (`R/faint-gap-effect.txt`): the blend is applied to the whole field, not only to the shape.
8. **Merge reach, settled by the user: option A.** Spec M4's sentence stays ("closer than `spacing` begins to merge") and "begins to merge" means "begins to blend": glass deforms toward its neighbour below `spacing` and joins below `spacing / 2`; the blend constant k equals `spacing`. The spec is not changed.
9. **The blend is an angle-weighted quadratic smooth-min** (Task 4, test `angle_union_test`). The correction of the quadratic smooth-min is weighted by (1 − n_a · n_b) / 2, with each shape's analytic unit gradient; a blend of 0 is the plain minimum. Against native's necks and bulges at k = spacing (`R/blend-at-spacing-light-photo.json`, `-light-black.json`): RMS against the stored native series, light photo, angle model against the plain quadratic: S4 0.165 / 0.165, S6 0.47 / 0.332, S8 0.374 / 0.226, S10 0.502 / 0.373, S12 0.502 / 0.834, S16 0.334 / 1.414, S20 0.421 / 1.398, S40 0.427 / 3.926, S80 0.413 / 11.489 pt. **The angle model is worse than the plain quadratic at S6 to S10 (by 0.14 pt) and better from S12; it is chosen on S16 to S80, where the quadratic is 1.4 to 11.5 pt off, and all its RMS are at or below 0.5 pt.** A free fit of k per spacing (`R/blend-fit-light-photo-pad0.json`) gives nothing better than k = spacing.
10. **`GlassEffectContainer.spacing` defaults to 8 pt, native's default** (Task 4). A default-container pair is pixel-identical to `spacing: 8` at the four gaps compared, 0, 4, 8 and 12 pt, in dark and light photo (`R/default-probe.json`: max difference 0.0 against 101 to 194 levels for every other spacing); native's default contact neck is 25.67 pt light and 24.67 dark, joined to gap 4 and apart from 5 (`R/verify/n7-table.txt`, rows `S8 (default)`, 15 gaps, against native's explicit `S8`, not against the default probe). The app's `GlassScope` keeps the 20 pt it was drawn with (test `glass_scope_test`), so the app's toolbars do not change. **Why `LiquidGlassBlendGroup.blend` still defaults to 20 while the container's `spacing` defaults to 8:** the blend group is the upstream widget (`lib/src/liquid_glass_blend_group.dart`), used directly by 2B.1's own-layer code and by anyone who builds on it, and its 20 is the unit of upstream's quadratic smooth-min, whose reach differs from native's `spacing`; the container passes its `spacing` as `blend`, so a container never meets the 20, but code that uses a blend group directly keeps the old reach.
11. **The package draws its outline band from the blended field**, which the angle-weighted union already predicts (`R/faint-gap-effect.txt`: f at the gap centre = gap / 2 − k / 4; the patch appears where both compared fields are within 3.5 pt of the silhouette and differ).
12. **Spacing animates like a move, as the package's own design; native's behaviour is not yet known** (Task 4, test `glass_spacing_test`; **a user decision of 2026-10-07: keep it, with a native reference**). The behaviour: with `withGlassAnimation`'s animation, else the nearest `GlassAnimationScope`, else the default spring; `GlassAnimation.none` changes it at once; a retargeted spacing keeps value and velocity; a spacing the app changes on consecutive frames follows its value and a single change springs (ruling 32 of plan 2B.1); under Reduce Motion it springs as the drawn rects do; a muted ticker changes it at once. It runs on the container's ticker and needs no rebuild. **No native evidence exists for any of this.** Nothing recorded in 2B.1 or in the prototype changes a container's `spacing` while it is on screen (the N7 scenes are still images), spec M4 says merging needs no separate animation, and spec decision 9 asks for behaviour copied exactly. The reference is Task 23's scene `material.respace` (a native `GlassEffectContainer(spacing:)` that `withAnimation` changes between 8 and 40 pt over two circles 12 pt apart) with its Flutter twin, tap ids `widen` and `narrow` and the pair's topology measures; **Task 26 records it and judges it. If the native frames show no animation of `spacing` (the neck forms in one frame, or the join comes within one video frame of the first change), the executor stops and reports to the main session; it never keeps the unverified behaviour silently.** If native does animate it, the Flutter result is judged like any other scene and its failures are classed.
13. **Appearing glass is not merged with its neighbours, as in 2B.1 (ruling 18)** and no 2B.2 native frame was recorded that tests it (`material.merge` has no appearing glass); morphing glass is, while it moves (ruling 18). This is an open item, not a finding.
14. **Native merge under Reduce Motion moves as without it** (`R/morph/merge-rm.json`; normal runs `20261006-235616`, `-235739`, `-235905`, Reduce Motion `20261007-012653`, `-012817`, `-012942`): gap spring 0.49–0.69 s / 0.85–1.02 normal and 0.59–0.70 / 0.85–0.94 Reduce Motion, joins at 215–248 ms and 252 ms, splits at 85–117 and 102–117 ms. The package changes nothing under Reduce Motion for merge.

*Union (spec M5)*

15. **Native draws a union as one circle-ended capsule on the bounding rect of its members** (`R/union/findings.txt`, runs `20261007-011938` light black, `-011723` stripes, `-011829` photo): four 64 pt circles at x 49–113, 129–193, 209–273, 289–353 in two unions are two 144 × 64 pt capsules at 49–193 and 209–353 (end arcs r 31.91, RMS 0.12), straight top and bottom, no seam, 16.0 pt apart without blending (14.66 on stripes and photo), content at the members' centres.
16. **`GlassNamespace` and `GlassEffect(union: GlassEffectUnion(id, namespace))`** (Task 8, test `glass_union_test`): the same id in the same namespace with the same shape and the same `Glass` draws as one shape, at any distance, on the bounding rect of the members' drawn rects (so it follows a member that moves); circles and capsules become a capsule of that rect, rounded rectangles and superellipses keep their corner radius; a union counts as one shape against the container's 16; a materializing member draws on its own and joins when it settles (so a union's bounding rect and shape change in one frame when a member appears, and the capsule jumps; no native frame shows what native does when a union member appears, so this is an open item, recorded and not judged); a removed member leaves at once; a union needs a container. `scene_sdf_mirror.dart` (Task 4) mirrors the shader in Dart so the geometry is testable without the GPU.
17. **The union scene is rebuilt as native's `UnionScene`** (Task 8, test `union_scene_test`; prototype run `20261007-055926`, `R/verify/summary.txt` §2): light stripes 15 / 19 / 19 (passing / judged / expected; luma 4.48 and mad 5.65 are the glyphs: native's SF Symbols at size 24 ink 25.67 × 24.67 pt, Flutter's `Icon(size: 24)` smaller; `R/verify/union-tone-light-stripes.json`), dark stripes 3 / 16 / 19 (class (c): native's dark outline is under the still mask's 30-level rim along most of the capsule, `R/verify/union-mask-dark-stripes.json`; class (a): Flutter's dark glass is 9.5–14.8 luma darker than native's, and 64 pt native union glass is 9–12 luma lighter than 80 pt glass in dark). **Both causes are fixed after this run** (rulings 30 and 31, main-session rulings D1 and D2); the 15 / 19 / 19 and 3 / 16 / 19 are the baseline before them.

*Morph (spec M6)*

18. **`GlassEffect(id:)` morphs by default** (Task 11, test `glass_morph_test`): an id and no `transition` is `GlassEffectTransition.matchedGeometry`, no id is `materialize`; matched geometry works on a glass removed and another inserted with the same id in the same frame (one glass springing from the old drawn rect to the new, old content fading out over it, new in); an appearing glass without a partner emerges from the nearest present glass's drawn rect at that glass's size (Reduce Motion: that glass's centre at its own size, content fading in); a removed glass whose last rect is within `spacing` of a remaining glass's laid-out rect sinks into it at full brightness, shrinking, its content fading (Reduce Motion: slides at full size); a farther one dematerializes in place. Morphing glass blends with its container's glass by `spacing` while it moves. **What native's frames show** (`R/morph/findings.txt`, runs `20261007-012017` stripes and photo, `-012309` light black, Reduce Motion `-012352`; one take per case): every appearing glass starts at the toggle's old centre 451 and springs out (heart 0.58–0.62 s / 0.65–0.67, bolt 0.35–0.38 / 0.64–0.66, toggle 0.28–0.32 / 1.75–1.97, no toggle overshoot); emergence is not an alpha or blur ramp (ring luma 129–130 from the first visible frame); on collapse the heart and bolt (36 pt from 451, overlapping the toggle's rect) shrink into the toggle while the star (108 pt away, gap 52 pt) dematerializes in place. **What they do not show, and the two working hypotheses built on that:** (1) *emerge from the nearest present glass.* In native's expand the toggle is the only glass present when the badges appear, and it is the glass that was tapped, so the frames cannot tell "nearest present glass" from "the tapped glass" or from "the glass the id's namespace was matched on"; the spec's own wording is only a working guess (M6: "the nearest"). (2) *sink when within `spacing`, dematerialize otherwise.* The heart and bolt are 36 pt from the toggle and the star 108 pt (gap 52 pt) and `findings.txt` calls the rule "hypothesis (untested)": any threshold from 0 to 52 pt fits, `spacing` is one of them. Both hypotheses are consistent with the frames and **neither is evidenced by them**. **Open item, a native control that could separate them:** a container with two present glasses, the tapped one far from the new glass's slot and an untapped one next to it; if the new glass emerges from the untapped neighbour, "nearest" holds, if from the tapped one, it does not; a second, with removed glasses at gaps of 8, 20, 30 and 40 pt from a remaining one, would place the sink threshold. It is a native scene, its Flutter twin, tap ids and a tracker for the emerging glass (about the size of Task 23), so it is not built in this plan; it goes to 2B.3's carry-in unless the user asks for it first. Native's heart and bolt are also fitted with different springs (0.58–0.62 s against 0.35–0.38 s, `R/morph/tracks.json`), while the package springs every arrival with one animation: a class (a) difference, listed in ruling 21. The native `light-stripes` expand take's touch held 192 ms against 70–83 ms in the others (`tracks.json` `hold_ms`), which moves that case's timings by the difference.
19. **The toggle's swelling is the morph, not the press** (native controls, `R/morph/swelling-controls.json`, runs `20261007-053236`, `-053517` `material.tap`; `-053558`, `-053848` `material.morph.plain`): a tap that changes nothing grows 0.0 pt; the plain morph's toggle grows +14.0 pt (56.67 → 70.67) with its peak 176.7 ms after the touch-up; native's N2 press grows +17.0. The swelling is therefore part of the morph and absent under Reduce Motion (+0 to +0.34). The prototype does not draw it (ruling 21).
20. **Content blur is a Gaussian of 1.5 pt while a morphing glass touches another of its morph**, sharpening in one step when its glass separates by half of `spacing` (Task 11; `R/morph-flutter/native-content-blur.json`: pooled median 1.5 pt over 93 frames with NCC ≥ 0.8, per span 0.5–3.0; heart and bolt glyph sharpness 1.4–2.9 → 6–13 between 298 and 313 ms in `R/morph/findings.txt`); under Reduce Motion nothing is blurred and glyphs cross-fade sharp.
21. **Package defects the prototype's end-to-end runs found: what the fix round fixed and what remains** (`R/verify/summary.txt` §1c, §3c–§3e; class (a)). *Fixed after those runs:* (a) in the frame of the tap Flutter drew the moving circles at the mirror of their start (about 2 × old − new) and returned the next frame, in all 8 merge split onsets and 5 of 8 merge onsets, and persistently as the toggle's start in every `material.morph` take, producing Flutter's one-frame count change 1 → 2 → 1 and spring fit RMS 0.11–0.15: two causes, both fixed (ruling 29, Tasks 16–18; the real-app check is `R/onset/`); and (c) emergence (the heart first seen at the star's slot, 343.6–344.1, not at the toggle's, 440.9–443.3), which was the toggle's mirrored drawn rect read as the nearest glass, so it follows from the same fix and Task 27 measures it. *Remaining, expected to fail in Task 27:* (b) the toggle has no swelling (width peak 57.3–58.7 pt against native 71.0–71.7); (d) Flutter's merge and split timing is slower (join 225–250 ms against 208–217, split 108–117 against 58–75) and native shows hysteresis it lacks (native joins at an outer-edge gap of 21 pt and splits at 18–19 with its neck still 17.7–26.7 pt thick; Flutter thins to 13.7–14.3 pt and splits at 21.3–22.0, where it joined); one spring for every arrival where native springs heart and bolt differently (ruling 18); and the content-blur sharpening order. The plan's expected counts include these failures; **the remaining defects are 2B.3's carry-in unless Task 27's floors show that few of them survive (decision D5, answered by the main session).**

*Appear progress (todo-2b1 H4)*

22. **Appear progress is the spring to a fitted per-preset exponent** (Task 10, tests `glass_materialize_test`, `test_fitvis`): progress = max(s, 0)^e up to 1 and 1 + g (s − 1) above, with e = 1.85 (default), 1.95 (`.snappy`), 2.45 (`.bouncy`), fitted by `fitvis` on simulated moving glass: Flutter's progress as it would be recorded (the visibility table through the spring, the recorded frame sequence with and without the first frame) scored with the Done item 4 measures against every native appear, both first-frame outcomes, over every backdrop and take (`R/h4/fitvis-h4.txt`: failing per appear at the chosen exponent against exponent 1.0: default 0.48 against 2.11, `.snappy` 0.15 against 1.76, `.bouncy` 0.04 against 2.42). Reversing a shaped appear keeps the visible progress and a continuous rate (the exponent's inverse). **The fit is in-sample:** each preset's exponent is chosen to minimise the failing Done measures (`fitvis.py` `fit_appear_exponent`) on the same native takes and limits the Done table then counts, and spec M3 asked for a fit on the default animation checked on `.snappy` and `.bouncy`, which a free exponent per preset leaves no room for; the gain in the Done count below is a real recording, but its native side is the same takes, so it is **not an independent confirmation**. Task 27 Step 7 keeps the fitted values fixed and re-fits only if a measure moved by more than its noise, and then says so. **The blur filter under motion is not the cause** of moving glass running ahead of the fit: read from the build frame, moving and static glass agree within RMS 0.004–0.021 of progress in every case (`R/h4/moving-vs-static-from-build-frame.txt`, run `20261006-204707` and `-210255`). Effect on Done item 4: 289 / 334 / 336 progress measures pass at the fixed limits (normal 144 / 168, Reduce Motion 145 / 166; 2B.1's last results were 133 / 168 and 133 / 168), `R/verify/done-table.txt` runs `20261007-071931` and `-073538`; 45 measures still fail (sharpness 15, settle 11, response 10, damping 7).
23. **`ios27MorphContentBlur` is a value from a tool that no tool writes, and `fitvis --write` used to delete it** (Task 12). The prototype put the pooled median of `content_blur.py` (1.5) into `ios27_motion.dart` by hand; `table_source` rebuilt the file without it, so the next `fitvis --write` would have broken the build. `write_table` now keeps the line the target already holds (tests `test_a_write_keeps_the_morph_content_blur_line_the_target_already_holds` and `test_a_write_to_a_target_without_the_morph_content_blur_line_adds_none`). The one value stays hand-placed, from `content_blur.py`'s output, and **is not tool-written**: the project rule that fitted values are written by a tool has this one exception (main-session ruling D4). The follow-up, for 2B.3, is a `fitvis` flag (`--morph-blur <content_blur.json>`) so that only a tool writes `ios27MorphContentBlur`.

*Native references, noise and verification*

24. **Native references recorded in the prototype are reused**; the plan's runs re-record both apps together (`lab.py run` records native and Flutter in one run), so each run's native side is the reference. Run folders: merge `20261006-235616` … `-235905` and Reduce Motion `20261007-012653` … `-012942`, union `20261007-011723`, `-011829`, `-011938`, morph `20261007-012017`, `-012309`, Reduce Motion `-012352`, N7 `20261004-003527`, `20261007-000000`, `-002556`.
25. **L8 noise is recorded in execution and is every 2B.2 floor's source** (Task 25): five native takes per case over two sessions with a simulator reboot between, each take checked with the capture-hole rule and the touch gate (`R/take_check.py`) and replaced when it fails (gotcha 47), the 1.0 s press checked 0.8–1.2 s after each boot and after about three hours of recording (gotcha 49: 2.0–2.4 s presses at 7.5 h), every floor computed from scratch (`lab.py repeat` writes `noise.json`; `R/noise_recompute.py` lists every limit that moved). A static repeatability failure stops the task. The prototype recorded none: `noise.json` holds `material.spacing.40.{a,b,c}` and `.default.{a,b,c}` from 2B.1 and the gotcha 52 case only, so **every prototype count below is at fixed thresholds** (`R/verify/summary.txt`, header). Those six 2B.1 spacing scenes keep their 2B.1 floors: Task 25 does not record them again (`repeat` rewrites a scene's whole entry, so recording them would replace 2B.1's floors with different ones), and records the other seventeen.
26. **Manifest correction D3, approved by the user on 2026-10-07: merge by each circle's outer edge and the pair's gap, morph by the stack's outer edges** (Task 19; `R/verify/summary.txt` §6b; not a loosening: nothing is removed that could have been measured, nothing is given a looser limit). `material.merge` listed `width.*` that cannot exist (each circle keeps its width, start and end 80.0–82.3 pt, travel 0–2.0 pt: 20 absent failures per case, constants by construction); its `cx` uses a region box that the bridge crosses. Those `width.*` are replaced by new motion keys `xmin` (the left circle's left edge) and `xmax` (the right circle's right edge), `edge` positions of a region's mask that no bridge crosses, listed per region in a new manifest field `edges`, and by `topology.gap_rms` (the pair's gap over time, threshold `gap_pt`, 1 pt like `neck_rms`) beside the join, split, neck and count the scene already had; `cx.*` stays. `material.morph` and `.plain` keep every measure they had (their region boxes still overlap moving glass: 169 absent `response_pct` in 4 normal cases, a class (b) fact that stays) and gain `ymin` and `ymax`, the top and the bottom edge of the `stack` region (the star's top and the toggle's bottom, the two glasses nothing crosses) and `topology.gap_rms`. **Not built, and the user accepted that on 2026-10-07 (option A):** a tracker that follows the inner glasses (heart, bolt) one by one. **The heart and the bolt are not tracked individually**; their centres stay measured by region boxes, so \"per-glass tracking\" covers the stack's outermost glasses only. The 20 old merge `width.*` measures per case were never judged (constants, absent in every take), so no judged measure was removed. **Carry-in (2B.3 or a fix wave, once the noise floors show which morph failures matter):** per-glass tracking of the heart and the bolt. Native has 3–4 events per morph take against Flutter's 2 (events start at touch-down in native only). `MOTION_MEASURES` (`manifest.py` and `shapes.py`, which a test keeps equal) gains the twenty edge measures and `topology.gap_rms`, with tests (Task 19). **Effect on the counts, side by side, on the same recordings:** the Done table template gives the old manifest's judged / expected counts (the prototype's, `R/verify/logs/table-*.txt`) and the new manifest's (`R/verify/logs/table-newmanifest-*.txt`, the same four run folders re-analysed with this manifest at the pre-fix package).

27. **A second morph swap inside the first settles** (Task 13, tests `a second swap 60 ms into the first settles...` and `...300 ms...` in `glass_morph_test`). A content ghost reported `partner._morph.isMoving`, and a partner's spring is advanced only by its own member; a partner removed in a second swap leaves a content ghost of its own that never advanced it, so the first ghost, its snapshot and the container's ticker ran for ever (found by the plan review: ghosts `[content, content]`, five seconds later `[content]`, `pumpAndSettle` timing out; it settled only at a 1500 ms gap). The ghost now samples the removed partner's spring itself. A double tap on the morph toggle triggered it.

28. **Ghosts count toward a container's sixteen shapes and are left out before a member is** (Tasks 14 and 15, tests in `glass_group_test`). A sinking or pending ghost registers in the container's blend group so that it can blend with the glass it sinks into; 2B.1's ghosts did not, because a `dematerialize` ghost only fades in place and draws in a layer of its own, outside the container's 16. A container with 16 glasses where one is removed with an id while another with an id is inserted (the arrival is a member at once), or 15 glasses, an arrival and two sinking ghosts, drew 17 or 18 shapes and `updateGeometryShaderShapes` threw `UnsupportedError` in paint (the review's F2; spec §9 asks for the test, and the geometry shader cannot be compiled by `flutter test`, ROADMAP gotcha 3 and 39, so the tests build `RenderLiquidGlassBlendGroup` and `RenderLiquidGlass` objects with the upload stubbed and read `gatherShapeData`). `gatherShapeData` now drops transient shapes, last registered first, until the container fits; **a dropped ghost draws no glass, its content still fades** (rare: a container at its limit while it morphs). Seventeen members still throw, as in 2B.1.

29. **The first frame of a move is drawn where the glass was** (Tasks 16, 17, 18 and 24b; tests `glass_space_shift_test`, `glass_group_test`; D5, a main-session ruling: fix the one-frame mirror at motion onset before Task 27 runs). Two defects drew the onset at about 2 × old − new. (i) The blend group decides in `paint` whether to rebuild its geometry matte, before its members' `sync` has found that their anchors changed; it reused last frame's matte, which is in the group's own coordinates, at the group's new position, so both circles of the merge scene were drawn displaced by the container's shift for one frame, with their shadows (which read `drawn` after `sync`) at the right place, and the next frame, when the members' springs notified, drew them right. The group now asks each registered glass to sync (`GlassShapeMotion.syncMoved`) before its decision, and a glass whose anchor changed marks the geometry as possibly stale. (ii) A glass's anchor was its place in its space; when the space itself moves on screen in the same frame (the morph scene's column re-centres as the stack grows) the offset ignored the space's move, and the toggle started 108 pt on the wrong side for the whole spring. The spring's start now includes the change of the space's on-screen origin, outer scrolling excluded, **in the frames in which the glass's own place in the space changed too** (Task 24b: the first version counted every move of the space, and the app's `floating_working_control_test` caught glass that merely moves with its parent starting to spring, against README's "anything that moves the container's parent moves the glass at once"; a space that moves alone still moves the glass at once). **Checked in the real app** (`R/onset/`: `flutter-merge-light-stripes-after.txt`, run `20261007-114536`, no frame at the mirror at either onset; `flutter-morph-light-stripes-after.txt`, run `20261007-115120`, the toggle holds 451 in its first frames and the badges leave it); the other ruling-21 defects are not touched.

30. **A container draws with the material row of its members' size** (Task 20, tests `glass_container_material_test`; D1, a main-session ruling: option A). The container's layer follows a `GlassMaterialSource` whose side is the median of its members' laid-out shorter sides, so a union of 64 pt circles draws with the row of 64 pt glass (native's 64 pt union glass is 9–12 luma lighter than 80 pt glass in dark, `R/verify/summary.txt` §2b) and a row of 44 pt buttons with the row of 44; an explicit `side` pins the row as before. **A stated limit:** one layer has one material, so a container of members of different sizes draws all of them with the median member's row (the upper median for an even count); a row per member inside one layer needs per-shape material parameters in the final-render shader and is not built. Each member's shadow and a materializing member's own layer keep their own size's row as before (a materializing member in a container uses the container's source so that it does not jump when it joins). This changes the material of every container whose members are not 88 pt wide, so Task 27 Step 9's 2A still check is the risk check **for pinned groups only: no 2A still scene has an unpinned mixed-size container** (the standalone `LabCentered` blocks are single glass, and the app's `GlassScope` pins `side` and `spacing: 20`), so that check cannot catch a mixed-size regression, and the app itself cannot regress from this change because it always pins `side`. **The user accepted the median member's row for 2B.2 (2026-10-07, option A).** **Carry-in to project 3**, where mixed-size components are built: record per-glass materials in one layer (per-shape shader parameters).

31. **The union scene's glyphs are sized to native's ink** (Tasks 21 and 22, test `union_scene_test`; D2, a main-session ruling: option A, never shrink the measured regions). A change of the example's test content, not of the package. Sizes by ink height from the saved ink at size 24 in both apps (`R/union/glyph-ink.txt`): star 33, heart 28, bolt 34.5, leaf 32.5; in the app the heights are within 0.33 pt of native's and the star's and heart's widths within 1.0 pt; the bolt is 2.3 pt and the leaf 4.0 pt narrower because Material's `bolt` and `eco` are not SF's `bolt.fill` and `leaf.fill` (class (b)).

32. **What the generic loop costs, and one more open item.** `sceneSDF` lost its unrolled path for one to four shapes (Task 4): every container now has `blend > 0` (default spacing 8), so every container evaluates per-shape gradients (`pow` for squircles) per pixel and runs the generic loop; the frame cost is 2B.3's (M10) and the removed fast path is where it starts. Union membership jumps when a member appears (ruling 16) and no native frame shows what native does, so it is recorded, not judged.

**Decisions, as answered** (the plan's first review framed D1–D5 and the spacing animation as questions; the user answered two on 2026-10-07 and the main session the rest; each has a ruling or a task).
- **D1. Union dark material:** option A, each container member uses its own size's material row (a main-session ruling); **the user accepted on 2026-10-07 (option A of the second re-review) the median member's row for a mixed-size container**. Built as far as one layer allows: ruling 30, Task 20 (the median member's row for the whole container; per-member rows inside one layer are not built, and a container of members of different sizes draws every member with the median member's row). Risk: it changes every container whose members are not 88 pt. **Task 27 Step 9's 2A still check covers only pinned groups** (no 2A still scene has an unpinned mixed-size container: the app's `GlassScope` pins `side` and `spacing: 20`, the other still scenes are standalone glass), so it cannot catch a mixed-size regression, and the app itself cannot regress from D1 because it always pins `side`. **Carry-in to project 3**, where mixed-size components are built: record per-glass materials in one layer (per-shape shader parameters).
- **D2. Union glyph size:** option A, match native's glyph ink in the example's union scene, never shrink the measured regions (a main-session ruling). Ruling 31, Tasks 21–22.
- **D3. `material.merge` width measures and `material.morph` region boxes:** option A, a user-approved manifest correction (2026-10-07): ruling 26, Task 19, with the old and new counts side by side (Done table template). **Narrower than "per-glass tracking", and the user accepted that on 2026-10-07 (option A of the second re-review):** `material.morph` is tracked at the stack's outer edges only, `ymin` and `ymax` (the star's top and the toggle's bottom); **the heart and the bolt are not tracked individually**, their centres stay region boxes. The 20 old merge `width.*` measures per case were never judged (constants by construction, absent in every take), so nothing that was judged was removed. **Carry-in (2B.3 or a fix wave, once the noise floors show which morph failures matter):** per-glass tracking of the heart and the bolt.
- **D4. `ios27MorphContentBlur`:** keep the hand-placed 1.5 for now; the follow-up is a `fitvis` flag so only a tool writes it (a main-session ruling). Ruling 23; the value is **not tool-written**.
- **D5. The package defects of ruling 21:** the one-frame mirror at the motion's onset is fixed in this plan before Task 27 (ruling 29, Tasks 16–18, with tests); the other ruling-21 defects stay 2B.3's carry-in until the noise floors show which survive (a main-session ruling).
- **D6. Spacing animation (a user decision, 2026-10-07): keep it, with a native reference.** Ruling 12, Tasks 23 and 26; no native evidence exists yet.
- **Notes from the second review, stated.** (a) The space-origin anchor and the transient-ghost guard were read and mutation-tested by the reviewer without a defect; not pinned by a test and left to the real-app runs: that `maybeRebuildGeometry` calls the hook before it reads its cache, and the removed-partner branch of the ghost step beyond the two swap tests (no third swap, no partner removed by an unrelated sink). A ghost dropped by Task 15's guard draws no glass for those frames while its content still fades (a pop, only in containers at 16 shapes or more); seventeen members still throw. (b) D1 was asked as one row per member and built as one row per container, the median member's; the user accepted that (D1). (c) `material.respace` has a native scene, a Flutter scene, a manifest entry, a noise floor (Task 25) and the stop rule of Task 26 Step 4, and **no native evidence exists yet** that native animates `spacing`; that is the question Task 26 answers.

## Global Constraints

- No code comments in any new or changed code (Dart, Swift, Python, GLSL, shell); keep the upstream comments that already exist.
- Every commit message ends with the `Co-Authored-By:` line the executing session is given.
- Never stage `frontend/package-lock.json`. Never `git stash`. Never run `dart format` on whole files; match the surrounding style.
- Build the lab apps only with `python3 tool/glass_lab/harness/lab.py build <native|example|operator|all>` (plain `flutter build ios` fails under Xcode 27).
- Use only the simulator "iPhone 17 Pro (iOS 27)", UDID `708879DD-8B2A-4547-863F-F49EE1474D8B`, and name it in every `simctl` command, never `booted`; never touch the iOS 26.5 simulator (`94D0C207-A90B-4806-BBAB-8AF9B3F16329`) or its Operator data.
- Simulator or system prompts get only "Don't Allow" or "Not Now"; never pair Operator; never enter a password.
- No downloads, no `pip install`, no new dependencies; run `flutter test` and `flutter analyze` with `--no-pub` (the workspace resolves offline).
- Never push.
- Limits and measures are never loosened: the fixed thresholds in `metrics.py` stay, every limit is max(fixed, 1.5 × noise). A manifest correction is a decision (D3, taken by the user for the two scenes of Task 19), not an edit.
- When a patch does not apply, or a run's output differs from its "Expected output" block or its stated outcome, the executor does not improvise: it finds the cause, says in the task report what differs and why, and **stops and asks the main session** if the cause is not a path or a number that depends on the machine (a changed `development` file, a test that fails for a reason the plan does not name, a limit that would have to move).
- Material and fitted tables are written only by tools: `ios27.dart`, `ios27_scroll_edge.dart` by `lab.py tune --write`; `ios27_motion.dart` by `lab.py fitvis --write` (the prototype's table is the seed, Task 10, and `ios27MorphContentBlur` is the one hand-placed line, ruling 23).
- Flutter 3.44.5.
- One lab command at a time (`build`, `run`, `repeat`, `fitvis`, `tune`, `perf`, `a11y`, `reboot` share the simulator); run long ones with the Bash tool's `run_in_background`, never a trailing `&`, and never poll with short sleeps. Stop a lab run only with SIGINT (gotcha 50); an orphaned `recordVideo` is stopped with SIGINT too.
- Reboot the simulator (`lab.py reboot`) before recording native references and again every few hours, and check that a 1.0 s press reads 0.8–1.2 s **at the start of every recording session and again after about three hours of recording in one session** (gotcha 49 saw 2.0–2.4 s presses at 7.5 h and a good press at 4 h): `python3 docs/liquid_glass/02b-motion/research/proto-2b2/press_check.py --harness tool/glass_lab/harness <take>` on a native `material.interactive` take, from `packages/mobile`. Takes recorded since the last good check are not kept if the check fails; they are re-recorded after a reboot.
- After any interrupted lab command, `xcrun simctl spawn 708879DD-8B2A-4547-863F-F49EE1474D8B defaults read com.apple.Accessibility ReduceMotionEnabled` and `… EnhancedBackgroundContrastEnabled` must print `0`; if not, run `python3 -c "import sys; sys.path.insert(0, 'tool/glass_lab/harness'); import sim; sim.accessibility(sim.device(), 'none')"`.
- `df -h /Users/omaraly` before the archive copy (Task 3 Step 1), before every group of Task 25, before every run of Task 27 and before every noise recompute; analysis writes frame caches (`overview/`, `shapes/`, `marker/`) into the recordings (gotcha 51). Numbers at the time of writing (2026-10-07): about 83 GB free; the archive copy takes about 8.6 GB; Task 25 group A about 17 GB. **Stop under 40 GB free and report; ask the user for space under 45 GB. Never delete anything to make room** (the user clears space or names a volume); delete nothing outside the task's own scratch output without the user's approval.
- A case whose `driver.log` holds only the `xcodebuild` invocation line is a known driver crash (ROADMAP §6): rerun that case alone with `--appearance` and `--backdrop`, and say so in the task report.
- Judge glass only by lab measurements; when a number looks wrong, open the frames. Record every number with its run folder.
- `lab.py repeat` and `lab.py run` stop with `the native app build is older than its sources; run lab.py build native first` when a package, example or Swift file changed since the last build: run `python3 tool/glass_lab/harness/lab.py build all` and repeat the command. Any package edit (a Task 27 fix, a `fitvis --write`) makes the example stale, so rebuild before the next recording.
- Paths are relative to `packages/mobile/` unless they start with `docs/` or `packages/mobile/`. Run every patch from the worktree root as `git apply --3way`.

## Execution setup

- First, the main session commits this plan and `docs/liquid_glass/02b-motion/research/proto-2b2/` to `development` (they live only on `proto/2b2` until then), so the feature branch carries the plan its rulings cite.
- Then work in a new worktree on a new branch from `development`:
  `git -C /Users/omaraly/development/AI/Operator worktree add /Users/omaraly/development/AI/Operator-2b2 -b feat/ios-liquid-glass-2b2 development`
  and run `cd packages/mobile && flutter pub get --offline` (Task 0).
- This runs only on this Mac: a cloud session cannot reach the simulator.
- Never touch `/Users/omaraly/development/AI/Operator` (the shared checkout) after the `worktree add`.
- Run the lab from `packages/mobile`. Pass run folders to `--into` as absolute paths (gotcha 43). `lab.py prepare` is not needed: install the backdrops after the first build with
  `python3 -c "import sys; sys.path.insert(0, 'tool/glass_lab/harness'); import sim, build; u = sim.device(); sim.status_bar(u); [sim.install_backdrops(u, b, build.backdrops()) for b in (build.NATIVE_BUNDLE, build.EXAMPLE_BUNDLE)]"`.
- Recordings that earlier plans copied into `build/glass_lab/` (native references, `runs/noise-2b1`, `reference/`) are copied, never moved, from `/Users/omaraly/development/AI/glass-lab-runs/2b1/` (`runs/noise-2b1` is 8.6 GB on disk); never record into, move or write the archive: it is only read and copied. Only `runs/noise-2b1` is copied, by Task 3 Step 1 (`cp -R`, then `test ! -L` on the copy); the native app is built by `lab.py build`, and Task 27 Step 9 reads the archive's 2B.1 runs in place, read-only. **The copy of `noise-2b1` is the archive's, as 2B.1 left it, including the bad take 2 of `material.materialize/light-photo-reduce-motion`**: Task 3 takes it out and records its replacement in this copy. Nothing is copied from the prototype's worktree, whose `build/` is untracked and goes with it.
- From Task 3 on, shell snippets assume `cd /Users/omaraly/development/AI/Operator-2b2/packages/mobile`, `R=/Users/omaraly/development/AI/Operator-2b2/docs/liquid_glass/02b-motion/research/proto-2b2` and `NOISE=$PWD/build/glass_lab/runs/noise-2b1`.
- Gates for every task that touches their code:
  - app, from `packages/mobile`: `flutter analyze --no-pub` prints "No issues found!", `flutter test --no-pub` is green;
  - package, from `packages/mobile/packages/ios_liquid_glass`: `flutter analyze --no-pub`, `flutter test --no-pub`;
  - example, from `packages/mobile/packages/ios_liquid_glass/example`: `flutter analyze --no-pub`, `flutter test --no-pub`;
  - harness, from `packages/mobile`: `python3 -m unittest discover tool/glass_lab/harness/tests` prints OK;
  - `flutter test` prints a long SkSL error about `liquid_glass_geometry_blended` ("initializers are not permitted on arrays"); it is known and harmless (ROADMAP gotcha 3).

## Review Focus

1. **Join and split at `spacing / 2`, bulge to `spacing`, default 8.** Two 80 pt circles at `spacing: 40` are one shape up to gap 20 pt and two from gap 21, with the inner edges bulging past gap 24; a plain `GlassEffectContainer` blends at 8 pt. Pinned by `two 80 pt circles at k = 40 and gap 0 join with the model neck of 50 pt`, `from gap 21 the circles are apart, and at gap 24 each inner edge bulges 3 pt past its circle` and `a container blends at native default spacing, 8 pt` (Task 4).
2. **A spacing change is a move.** It springs with the transaction's animation, else the scope's, else the default; consecutive-frame changes follow; it never rebuilds. Pinned by the `glass_spacing_test` names in ruling 12 (Task 4).
3. **A union that moves, loses a member or gains one.** The union's rect is the bounding rect of the members' drawn rects on every frame, a removed member leaves at once, an inserted one joins when it settles, a union counts once against the 16-shape cap. Pinned by `a union follows a moving member: its rect is the bounding rect of the drawn rects on every frame`, `an inserted member materializes on its own and joins its union when it settles` and `a union counts as one shape against the 16-shape cap` (Task 8).
4. **Morph partner, emergence and sink.** Pinned by `a glass removed and another inserted with the same id in the same frame draw as one glass that springs from the old rect to the new`, `an appearing glass emerges from the nearest present glass` and `a removed glass within spacing of a remaining glass sinks into it in the shared layer; a farther one dematerializes in place` (Task 11). A sinking ghost draws through the container's blend group, so unlike 2B.1's ghosts it counts toward the 16-shape cap: pinned by `a sinking or pending ghost counts toward the sixteen shapes of a container, and is left out before a member is` and `sixteen members and a ghost draw the members and leave the ghost out, where the upload would otherwise throw` (Task 15, render-object level because the geometry shader cannot compile in `flutter test`). A second swap inside the first: `a second swap 60 ms into the first settles...` and `...300 ms...` (Task 13).
5. **Reduce Motion.** Merge changes nothing; morph slides at full size, starts at its own size and blurs nothing. Pinned by `normal motion starts an appearing glass at the size of its source, Reduce Motion at its own size`, `under Reduce Motion an appearing glass fades its content in sharp` and `under Reduce Motion a sinking glass slides into its target at full size` (Task 11).
6. **The appear exponent's inverse.** Reversing an appear that is mid-way keeps the visible progress and a continuous rate. Pinned by `reversing a shaped appear keeps the visible progress and a continuous rate` (Task 10).
7. **A tool run must not break the table.** `fitvis --write` keeps `ios27MorphContentBlur` (Task 12), and the table it writes equals the committed one apart from that line.
8. **Nothing passes by being absent in the new topology measures.** `gap_pt` is NaN unless exactly two components, `neck_pt` NaN unless one, NaN against a number fails; a scene listing `topology.*` without regions is rejected; `gap_rms` follows the same rules (Tasks 1, 5 and 19).
9. **The first frame of a move.** A glass whose anchor changes has its container's geometry rebuilt in that frame, and a space that moves as its container resizes does not shift the glass's spring. Pinned by `both circles report that they moved in the frame the container shrinks and re-centres, and once only`, `a move without an animation is reported as well`, `a settled geometry is marked for an update in the frame a member moves, and left alone when none did` (Task 17) the two `glass in a space that re-centres...` tests (Task 18) and `glass whose container only moves with its parent follows at once and springs nothing` (Task 24b); the real-app check is `R/onset/`. **Not pinned by a test:** that `maybeRebuildGeometry` calls the hook before it reads its cache (the stand-in shader cannot draw, so the rebuild itself cannot run in `flutter test`); the real-app run is the check.
10. **A container's material.** The median member's row, an explicit `side` pins it, it follows resizes, joins and leaves, a union of 64 pt circles draws the row of 64. Pinned by the six tests of `glass_container_material_test` (Task 20); mixed sizes use one row (ruling 30), the limit is stated and was accepted by the user (D1). The still check of Task 27 Step 9 covers pinned groups only and cannot see a mixed-size regression.
11. **A user-approved manifest correction is not a loosening.** `material.merge` keeps every measure it could judge and swaps the impossible `width.*` for `xmin`, `xmax` and `gap_rms`; `material.morph` loses nothing and gains `ymin`, `ymax` and `gap_rms`, at the stack's outer edges only: the heart and the bolt are not tracked individually (D3, accepted). Pinned by `RealMotionManifestTests` and `OuterEdgeTests` (Task 19). The reviewer compares the old and new counts in the Done table template.
12. **Not pinned, said:** the spacing animation's behaviour against native (no native evidence until Task 26); the emergence source and the sink threshold (hypotheses, ruling 18); a union member appearing (ruling 16); the two cases in which Task 15's guard drops a ghost's glass (its content still fades); **the shader itself**: `flutter test` cannot compile the geometry shader (gotchas 3 and 39), `scene_sdf_mirror.dart` is a Dart copy of `sdf.glsl` pinned by tests written against the copy and kept equal to the GLSL by reading, so the real-app N7 and merge runs are the only check of the GLSL.

## What this plan expects to reach

Measured in the prototype before the fix round (the package at `f4039bea6`, with the existing `noise.json` limits and the fixed thresholds; run folders are the prototype's, `R/verify/summary.txt`, `R/verify/logs/table-*.txt`). **The fix round changed the package and the manifest, so those counts are the baseline, not the forecast:** the final package is measured in Task 27 and compared with the baseline by measure name (`expected` is not constant between takes, so totals are not compared). The 2B.2 noise floors do not exist in the prototype; a floor can only raise a limit. "Counts" are passing / judged (finite) / expected per case, static and topology measures with motion measures; the event and touch gates (`events.*`, `touches.*`) passed in every case but the three named captures.

| Done item (spec §8, 2B.2) | Prototype baseline | Forecast after Task 27 |
|---|---|---|
| 1 `material.merge`, `material.union`, `material.morph` pass, normal and Reduce Motion | **Failing.** Merge, normal (`20261007-054755`), old manifest: dark-photo 20 / 41 / 66, dark-stripes 24 / 45 / 66, light-photo 25 / 44 / 66, light-stripes 25 / 46 / 66; **new manifest, same recordings** dark-photo 24 / 61 / 68, dark-stripes 30 / 67 / 68, light-photo 29 / 62 / 68, light-stripes 33 / 68 / 68 (expected 66 to 68: the 20 `width.*` measures per case are replaced by 20 edge measures and `gap_rms` is new; judged rises because the impossible measures are gone); Reduce Motion (`-055356`), old: 20 / 41 / 66, 22 / 45 / 66, 27 / 46 / 66, 26 / 46 / 66; new 24 / 63 / 68, 26 / 67 / 68, 33 / 68 / 68, 32 / 68 / 68. Morph normal (`-060205`) old: dark-photo 19 / 59 / 126, dark-stripes 24 / 55 / 126, light-photo 29 / 55 / 126, light-stripes 31 / 58 / 126; Reduce Motion (`-061306`): 29 / 64 / 180, 26 / 59 / 126, 34 / 60 / 126, 39 / 62 / 126; plain normal 22 / 65 / 180, 17 / 61 / 126, 25 / 59 / 126, 16 / 36 / 126 (light-stripes: Flutter capture hole, touches [2, 1]); plain Reduce Motion 21 / 62 / 126, 26 / 60 / 126, 31 / 60 / 126, 29 / 60 / 126; morph on the new manifest normal 25 / 73 / 148, 28 / 69 / 148, 33 / 69 / 148, 36 / 72 / 148, Reduce Motion 35 / 79 / 213, 31 / 73 / 148, 40 / 74 / 148, 47 / 76 / 148 (expected 126 to 148: ten edge measures and `gap_rms` per event added, nothing removed). | **Failing, each failure classed** (rulings 21 and 26, and the classes (b), (c), (d) of `R/verify/summary.txt`). The onset frame (ruling 29) no longer fails the merge `cx` and the one-frame count change; the remaining ruling-21 defects still do. The Flutter capture holes re-recorded. |
| 2 The rebuilt union scene passes its still-image measures | **Failing.** light-stripes 15 / 19 / 19 (luma 4.48 and mad 5.65: the glyphs), dark-stripes 3 / 16 / 19 (`20261007-055926`; classes (a) and (c), ruling 17) | Light-stripes: the glyph boxes (3.54 of luma 4.48 and 3.69 of mad 5.65) shrink with D2 (ruling 31) and the glass part (0.94) is the rest; dark-stripes: the 9.5–14.8 luma of material (ruling 30) goes, the still mask's misread of native's dark outline (class (c)) stays. |
| 3 The N7 spacing scenes pass their still-image and topology measures | **6 of 46 cases pass** (all light photo: `.6.a`, `.10.a`, `.20.a`, `.40.a`, `.80.a`, `.80.b`); dark photo none (the shadow); the necks and gaps agree within 1 pt except at contact for small spacings and at the reach (`20261007-062403`, `R/verify/n7-table.txt`) | Partly passing, as the prototype; the container material (ruling 30) may change dark cases. |
| 4 Still glass no worse than 2A; gates | Gates: the numbers in the Replay check. Still check: **not run in the prototype**. | `missing: 0` and `worse: 0` in all nine scenes against 2B.1's runs (Task 27 Step 9: a ratchet; the spec's reference is 2A; it covers pinned groups only, no 2A still scene has an unpinned mixed-size container); the default spacing is now 8 pt and the container material follows its members, so a scene that relied on 20 pt or on the 88 pt row gets `spacing: 20` or `side: 88`; a difference that remains with both pinned is reported, not tuned. |
| (carried) 2B.1 Done item 4, materialize with the H4 exponents | 289 / 334 / 336 (normal 144 / 168, Reduce Motion 145 / 166) against 2B.1's 266 / 336 (`20261007-071931`, `-073538`); events and touches 120 / 120; **in-sample for the exponents and judged under the new gotcha 52 floors (rulings 5 and 22)** | Re-measured in Task 27 Step 7 with the exponents fixed; 45 failures remain classed (sharpness 15, settle 11, response 10, damping 7, t10_90 3, rms 1, 2 absent). |
| (new) Spacing animation | none | `material.respace` in Task 26: whether native animates `spacing`, and Flutter's counts if it does. |

**The plan forecasts that Done items 1 to 3 still fail** (every failure classed); merging 2B.2 is then the user's decision on classed failures, which spec §8 allows, and not a pass. Item 4 depends on the still check that the prototype did not run.

**Why the Done items fail, and how each failure is classed** (`R/verify/summary.txt`; classes: (a) the package draws or moves differently from native, (b) the measure or manifest is wrong for this scene, (c) the mask or tracker misreads one app, (d) a capture problem):
1. **Merge `width.*` (20 failures per case), class (b), replaced by Task 19**: the circles keep their width (ruling 26). Merge `cx.*`, class (a) timing mixed with (b) (the region box the bridge crosses) and the onset frame (ruling 29, fixed after these runs); `topology.join_ms` 25–33 ms late, `split_ms` 108–117 against 58–75 ms, `neck_rms` 3.1–5.7 (merge) and 8.9–24.5 (split), class (a).
2. **Merge static `bbox_pt` 2–4 and `centre_pt` 2 on dark photo, dark stripes and light stripes**: only the bottom edge differs (native 80 tall, Flutter 84): the shadow, class (a). `ready.topology.pair.count` on dark stripes: native's still mask breaks (3 components), class (c). One light-photo normal Flutter merge, class (d) (a burst: touch-down and up in one frame, `20261007-054755`); repeat that take.
3. **Union**, ruling 17 (D1 and D2 fixed after these runs, rulings 30 and 31). **Morph**: events unpaired (native has 3–4, Flutter 2), per-region boxes crossed by other glass (class (b)), the toggle's mirrored start (a, fixed after these runs, ruling 29), no swelling (a), emergence (a, expected to follow the same fix), Flutter 1 → 4 components in one step at 398 ms against native's 1 → 2 at 305–363 ms (a); static dark `bbox_pt` 4–6 (the shadow). `material.morph.plain` light-stripes Flutter: a capture hole between 10.017 s and 17.540 s (class (d); repeat).
4. **N7**: counts agree on light photo at every gap except S80 gap 40 (native 2 components, gap 0.67; Flutter 1 with a 5.33 pt neck); on dark photo they disagree at S20 gaps 10 and 11 and at a few gaps past the reach; Flutter's neck at contact is wider at small spacings (S4 dark 22.67 against 18.0, S10 dark 30.0 against 27.33) and a pinch at the reach where native snaps (class (a), zoomed at the pinch Flutter draws a soft dark smudge about 12 pt wide); the shadow's bottom edge fails `bbox_pt` in 21 of 23 dark scenes.
5. **Materialize** (H4's effect): 15 sharpness failures on photo (Flutter is blurrier than native at half progress, 1.04–1.97 against a limit of 1.0), disappear timing 33–58 ms slow in four default cases, spring fits whose curves agree (class (b)), and two class (d) captures (`bouncy dark-photo-reduce-motion` Flutter appear; `snappy light-photo-reduce-motion` native appear).

## File map

| Path (under `packages/mobile/` unless it starts with `docs/`) | Responsibility | Task |
|---|---|---|
| `tool/glass_lab/harness/{shapes,track,manifest}.py`, `tests/{test_shapes,test_track,test_manifest}.py` | Topology that agrees at zero, necks only on one component, manifest rejects topology without regions | 1 |
| `tool/glass_lab/scenes.json`, `tool/glass_lab/native/GlassLab/MaterialScenes.swift` | N7 finer gap series and spacing probes | 2 |
| `tool/glass_lab/noise.json` (made by `lab.py repeat` from the executor's own takes) | Gotcha 52's floors | 3 |
| `packages/ios_liquid_glass/lib/assets/shaders/sdf.glsl`, `lib/src/{liquid_glass_blend_group}.dart`, `lib/src/api/glass_effect_container.dart`, `lib/src/motion/glass_motion_coordinator.dart`, `test/geometry/{angle_union_test,pair_topology,scene_sdf_mirror}`, `test/motion/glass_spacing_test.dart`, `example/lib/lab/scenes/spacing_scenes.dart`, `example/test/spacing_scenes_test.dart`, `lib/core/widgets/glass/glass_scope.dart` (app) | Angle-weighted union, default spacing 8, animated spacing, the N7 and merge live scenes | 4 |
| `tool/glass_lab/harness/{track,shapes,analyze,metrics}.py`, `tests/{synthetic,test_track,test_shapes}.py` | Video and still topology masks, `gap_pt` | 5 |
| `tool/glass_lab/scenes.json` | `material.merge` per circle, pair topology, photo | 6 |
| `tool/glass_lab/scenes.json`, `native/GlassLab/MaterialScenes.swift` | Native controls for the morph toggle's swelling | 7 |
| `packages/ios_liquid_glass/lib/src/api/glass_namespace.dart` (new), `lib/src/motion/glass_shape_motion.dart`, `lib/src/glass_shadow.dart`, `lib/src/liquid_glass*.dart`, `lib/src/motion/glass_motion_coordinator.dart`, `test/motion/glass_union_test.dart`, `example/test/union_scene_test.dart`, `example/lib/lab/scenes/material_scenes.dart` | `GlassNamespace`, `GlassEffectUnion`, the union scene | 8 |
| `tool/glass_lab/harness/{lab.py,tests/test_lab.py}` | Noise pair folder link | 9 |
| `packages/ios_liquid_glass/lib/src/motion/{glass_materialize,ios27_motion}.dart`, `test/motion/glass_materialize_test.dart`, `tool/glass_lab/harness/{fitvis.py,tests/test_fitvis.py}` | Appear exponent and the moving-glass fit (H4) | 10 |
| `packages/ios_liquid_glass/lib/src/api/{glass_effect,glass_effect_transition,glass_namespace}.dart`, `lib/src/motion/{glass_motion_coordinator,glass_motion_widgets,glass_morph_geometry,ios27_motion}.dart`, `test/motion/glass_morph_test.dart`, `example/lib/lab/scenes/morph_scenes.dart`, `example/test/morph_scene_test.dart`, `tool/glass_lab/scenes.json` | `GlassEffectID`, `matchedGeometry`, the morph scenes | 11 |
| `tool/glass_lab/harness/{fitvis.py,tests/test_fitvis.py}` | `fitvis --write` keeps the morph content blur | 12 |
| `packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart`, `test/motion/glass_morph_test.dart` | A second morph swap settles | 13 |
| `packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart`, `lib/src/liquid_glass_blend_group.dart`, `test/motion/glass_group_test.dart` | `isTransient`; the sixteen-shape guard | 14, 15 |
| `packages/ios_liquid_glass/lib/src/internal/render_liquid_glass_geometry.dart`, `lib/src/motion/glass_motion_coordinator.dart`, `lib/src/liquid_glass_blend_group.dart`, `test/motion/glass_space_shift_test.dart` | `syncMoved`, `shapesMoved`; the first frame of a move; the space-origin anchor | 16, 17, 18 |
| `tool/glass_lab/harness/{track,shapes,manifest}.py`, `tool/glass_lab/scenes.json`, `tests/{test_track,test_shapes,test_manifest}.py` | Outer-edge keys, `gap_rms`, `edges` (D3) | 19 |
| `packages/ios_liquid_glass/lib/src/api/{glass_effect_container,glass_effect}.dart`, `lib/src/motion/glass_motion_coordinator.dart`, `test/glass_container_material_test.dart` | A container's material follows its members (D1) | 20 |
| `packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart`, `example/test/union_scene_test.dart`, `R/union/glyph-ink.txt` | Union glyph sizes (D2) | 21, 22 |
| `tool/glass_lab/native/GlassLab/MaterialScenes.swift`, `tool/glass_lab/scenes.json`, `tool/glass_lab/harness/shapes.py`, `packages/ios_liquid_glass/example/lib/lab/scenes/spacing_scenes.dart`, `example/test/spacing_scenes_test.dart` | `material.respace` | 23 |
| `packages/ios_liquid_glass/{README,FORK}.md` | What is measured; what is new | 24 |
| `packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart`, `test/motion/glass_space_shift_test.dart` | The space's own move counts only with a local change | 24b |
| `tool/glass_lab/noise.json` (written by `lab.py repeat` only) | 2B.2 noise floors, L8 | 25 |
| `docs/liquid_glass/02b-motion/research/execution-2b2/respace-*.txt` | The spacing animation's native reference | 26 |
| `docs/liquid_glass/02b-motion/results-2b2.md` (new) | Verification | 27 |

## Tasks

Tasks 1–12 are the prototype's twelve code commits (Task 3 is not a patch: the executor makes its `noise.json` from its own takes), each split into a test patch and an implementation patch so every new test is seen to fail first; Tasks 13–24 are the fix round that followed the plan's independent review, whose findings are answered in the rulings (a refactor that changes no behaviour is one patch, a fix is a test patch then an implementation patch); Tasks 25–27 are recordings and verification that only execution can do (25 the noise floors, 26 the native reference for the spacing animation, 27 the verification runs and the results).

### Task 0: Setup

- [ ] **Step 1: Resolve the workspace offline.**

RUN[t00-setup]: `cd packages/mobile && flutter pub get --offline` => PASS

Expected output ends with:

```text
52 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
```

### Task 1: Topology that agrees at zero, necks only on one component, a manifest that rejects topology without regions

**Files:**
- Modify: `tool/glass_lab/harness/shapes.py`, `track.py`, `manifest.py`
- Test: `tool/glass_lab/harness/tests/test_shapes.py`, `test_track.py`, `test_manifest.py`

**Why.** Ruling 1. 2B.2's join, split and neck measures read these functions; fixed first so nothing later is judged on a defect.

- [ ] **Step 1: Add the failing tests.**

Patch `t01-tests` (`4db49edc3..fb0207573`, 3 files):

```diff
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py b/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py
index ec7af215eb2706b5c8b7ecf5c299e42f95a6a2f0..edec7787c9d085e03acee22e2e2698da3e36fdbe 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py
@@ -102,12 +102,17 @@ class TrackTests(unittest.TestCase):
         self.assertTrue(any("topology names an unknown region" in e for e in manifest.validate([self.base(topology=["z"])])))
         self.assertEqual(manifest.validate([self.base(topology=["a", "b"])]), [])
 
+    def test_topology_motion_measures_need_topology_regions(self):
+        errors = manifest.validate([self.base(track="a", motion=["topology.join_ms", "progress.rms"])])
+        self.assertTrue(any("topology measures need topology regions" in e for e in errors))
+        self.assertEqual(manifest.validate([self.base(track="a", topology="a", motion=["topology.join_ms"])]), [])
+
     def test_tracks_and_motion_measures_are_validated(self):
         self.assertTrue(any("unknown region" in e for e in manifest.validate([self.base(track=["a", "c"])])))
         self.assertTrue(any("non-empty list" in e for e in manifest.validate([self.base(track=[])])))
         self.assertTrue(any("unknown motion measure progress.wobble" in e for e in manifest.validate([self.base(track="a", motion=["progress.wobble"])])))
         self.assertTrue(any("need a track" in e for e in manifest.validate([self.base(motion=["progress.rms"])])))
-        self.assertEqual(manifest.validate([self.base(track="a", motion=list(manifest.MOTION_MEASURES))]), [])
+        self.assertEqual(manifest.validate([self.base(track="a", topology="a", motion=list(manifest.MOTION_MEASURES))]), [])
 
     def test_tracked_regions_are_not_rim_elements_and_the_union_is_the_region(self):
         scene = manifest.parse([self.base(track=["a"])])[0]
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py b/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py
index 33acd3966f511b72eceee82e2f515346c9978f8b..9c980bb1574b8548d3dca23b27eda506d826ec82 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py
@@ -15,20 +15,72 @@ from synthetic import capture_of, spring_series
 
 
 class ShapeTopologyTests(unittest.TestCase):
-    def test_join_and_split_times_count_mismatches_and_neck_are_compared(self):
-        def series(join, split):
-            count = [2.0] * join + [1.0] * (split - join) + [2.0] * (80 - split)
-            neck = [0.0] * join + [10.0] * (split - join) + [0.0] * (80 - split)
-            return {"count": count, "neck": neck}
-        late = shapes.compare_topology(series(20, 60), series(23, 60))
+    @staticmethod
+    def series(join, split, length=80, neck=10.0):
+        nan = float("nan")
+        count = [2.0] * join + [1.0] * (split - join) + [2.0] * (length - split)
+        necks = [nan] * join + [neck] * (split - join) + [nan] * (length - split)
+        return {"count": count, "neck": necks}
+
+    def test_join_and_split_times_and_count_mismatches_are_compared(self):
+        late = shapes.compare_topology(self.series(20, 60), self.series(23, 60))
         self.assertAlmostEqual(late["join_ms"], 25, places=6)
         self.assertEqual(late["split_ms"], 0)
         self.assertEqual(late["count"], 0.0)
-        self.assertAlmostEqual(late["neck_rms"], (3 * 100 / 80) ** 0.5, places=6)
-        stuck = shapes.compare_topology(series(20, 60), series(23, 80))
-        self.assertNotIn("split_ms", stuck)
+        self.assertEqual(late["neck_rms"], 0.0)
+        stuck = shapes.compare_topology(self.series(20, 60), self.series(23, 80))
+        self.assertEqual(stuck["split_ms"], float("inf"))
         self.assertEqual(stuck["count"], 17.0)
-        self.assertIsNone(shapes.compare_topology({"count": [1.0] * 5, "neck": [5.0] * 5}, {"count": [1.0] * 5, "neck": [5.0] * 5}))
+
+    def test_the_neck_is_compared_only_where_both_apps_have_one(self):
+        wider = shapes.compare_topology(self.series(20, 60), self.series(20, 60, neck=13.0))
+        self.assertAlmostEqual(wider["neck_rms"], 3.0, places=6)
+        late = shapes.compare_topology(self.series(20, 60), self.series(23, 60, neck=13.0))
+        self.assertAlmostEqual(late["neck_rms"], 3.0, places=6)
+
+    def test_apps_that_agree_on_no_transition_read_zero_not_absent(self):
+        one = {"count": [1.0] * 5, "neck": [5.0] * 5}
+        agreed = shapes.compare_topology(one, one)
+        self.assertEqual((agreed["join_ms"], agreed["split_ms"], agreed["count"], agreed["neck_rms"]), (0.0, 0.0, 0.0, 0.0))
+        apart = {"count": [2.0] * 5, "neck": [float("nan")] * 5}
+        both_apart = shapes.compare_topology(apart, apart)
+        self.assertEqual((both_apart["join_ms"], both_apart["split_ms"], both_apart["count"], both_apart["neck_rms"]), (0.0, 0.0, 0.0, 0.0))
+        empty = {"count": [0.0] * 5, "neck": [float("nan")] * 5}
+        self.assertEqual(shapes.compare_topology(empty, empty)["neck_rms"], 0.0)
+
+    def test_a_transition_in_one_app_only_fails(self):
+        joined = shapes.compare_topology(self.series(20, 80), {"count": [2.0] * 80, "neck": [float("nan")] * 80})
+        self.assertEqual(joined["join_ms"], float("inf"))
+        self.assertEqual(joined["split_ms"], 0.0)
+
+    def test_one_component_without_a_neck_against_one_with_a_neck_fails(self):
+        nan = float("nan")
+        found = shapes.compare_topology({"count": [1.0] * 5, "neck": [nan] * 5}, {"count": [1.0] * 5, "neck": [4.0] * 5})
+        self.assertEqual(found["neck_rms"], float("inf"))
+
+    def test_a_listed_topology_measure_is_present_when_both_apps_agree(self):
+        scene = manifest.parse([{"id": "x", "group": "material", "title": "t", "inventory": "2.14", "app": "lab", "backdrops": ["stripes"], "appearances": ["dark"], "steps": [{"tap": "merge"}], "regions": {"pair": [0, 0, 10, 10]}, "track": "pair", "topology": "pair", "motion": ["topology.join_ms", "topology.neck_rms"]}])[0]
+        one = {"count": [1.0] * 5, "neck": [5.0] * 5}
+        result = {"pairs": {"step0e0": {"shapes": {"pair": {"topology": shapes.compare_topology(one, one)}}}}, "event_count": [1, 1], "steps": [[0], [0]], "touches": [0, 0], "expected_touches": 0}
+        found = shapes.limits(result, scene)
+        self.assertEqual(found["pair.step0e0.topology.join_ms"][0], 0.0)
+        self.assertEqual(found["pair.step0e0.topology.neck_rms"][0], 0.0)
+
+    def test_still_necks_agree_when_neither_app_has_one(self):
+        nan = float("nan")
+        self.assertEqual(shapes.neck_difference({"count": 2.0, "neck": nan}, {"count": 2.0, "neck": nan}), 0.0)
+        self.assertAlmostEqual(shapes.neck_difference({"count": 1.0, "neck": 25.33}, {"count": 1.0, "neck": 24.0}), 1.33, places=6)
+        self.assertEqual(shapes.neck_difference({"count": 1.0, "neck": 2.0}, {"count": 2.0, "neck": nan}), float("inf"))
+        self.assertEqual(shapes.neck_difference({"count": 1.0, "neck": nan}, {"count": 1.0, "neck": 4.0}), float("inf"))
+
+    def test_the_neck_series_holds_each_frame_like_the_count(self):
+        nan = float("nan")
+        rows = [{"count": 2.0, "neck": nan}, {"count": 1.0, "neck": 6.0}, {"count": 1.0, "neck": 8.0}, {"count": 2.0, "neck": nan}]
+        rows = [dict(row, width=80.0, height=80.0, cx=1.0, cy=1.0, luma=1.0, progress=1.0, sharpness=0.0, residual=0.0) for row in rows]
+        series = shapes.event_series([0.0, 0.05, 0.1, 0.15], rows, 0, 3)
+        count, neck = np.array(series["count"]), np.array(series["neck"])
+        self.assertTrue(np.isnan(neck[count == 2]).all())
+        self.assertTrue(np.isfinite(neck[count == 1]).all())
 
 
 class ProgressMeasureTests(unittest.TestCase):
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_track.py b/packages/mobile/tool/glass_lab/harness/tests/test_track.py
index 2a1b5f2140091ac99def47d383c149ec310b7bf5..7f07c4ef4f16d2493f18e57889379c4df1872416 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_track.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_track.py
@@ -97,8 +97,15 @@ class TopologyTests(unittest.TestCase):
         self.bare = np.full((360, 720, 3), 40, dtype=np.float32)
         self.edges = track.edges(self.bare)
 
-    def test_separate_glass_counts_two_with_no_neck(self):
-        self.assertEqual(track.topology_row(disks(20), self.bare, self.edges), {"count": 2.0, "neck": 0.0})
+    def test_separate_glass_counts_two_and_has_no_neck(self):
+        found = track.topology_row(disks(20), self.bare, self.edges)
+        self.assertEqual(found["count"], 2.0)
+        self.assertTrue(np.isnan(found["neck"]))
+
+    def test_a_frame_with_no_glass_has_no_neck(self):
+        found = track.topology_row(self.bare.copy(), self.bare, self.edges)
+        self.assertEqual(found["count"], 0.0)
+        self.assertTrue(np.isnan(found["neck"]))
 
     def test_merged_glass_counts_one_and_measures_its_narrowest_neck(self):
         row = track.topology_row(disks(0, bridge=20), self.bare, self.edges)
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t01-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_manifest.py` => FAIL

Expected output ends with:

```text
FAILED (failures=6, errors=5)
```

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

Patch `t01-impl` (`4db49edc3..fb0207573`, 3 files):

```diff
diff --git a/packages/mobile/tool/glass_lab/harness/manifest.py b/packages/mobile/tool/glass_lab/harness/manifest.py
index 62ec2dda07689780869b28302e8b499e9d38fe05..f560c435da1d1096474deb9bdfdb8e783f0c8dfe 100644
--- a/packages/mobile/tool/glass_lab/harness/manifest.py
+++ b/packages/mobile/tool/glass_lab/harness/manifest.py
@@ -138,6 +138,8 @@ def validate(raw):
             errors += [f"{where}: unknown motion measure {m}" for m in motion if m not in MOTION_MEASURES]
             if motion and track is None:
                 errors.append(f"{where}: motion measures need a track")
+            if any(m.startswith("topology.") for m in motion) and topology is None:
+                errors.append(f"{where}: topology measures need topology regions")
         measures = entry.get("measures", list(STATIC_MEASURES))
         if not isinstance(measures, list) or not measures:
             errors.append(f"{where}: measures must be a non-empty list")
diff --git a/packages/mobile/tool/glass_lab/harness/shapes.py b/packages/mobile/tool/glass_lab/harness/shapes.py
index f58d62ac3fb838d2bf4f627edc0a219d71d786bf..f15add7e8ad7a31c99d3a9e6198bcd027668cb13 100644
--- a/packages/mobile/tool/glass_lab/harness/shapes.py
+++ b/packages/mobile/tool/glass_lab/harness/shapes.py
@@ -153,7 +153,8 @@ def event_series(times, rows, first, last):
     if "count" in picked[0]:
         counts = np.array([row["count"] for row in picked])
         series["count"] = counts[np.clip(np.searchsorted(stamps, grid, side="right") - 1, 0, len(counts) - 1)].tolist()
-        series["neck"] = np.interp(grid, stamps, [row["neck"] for row in picked]).tolist()
+        necks = np.array([row["neck"] for row in picked], dtype=np.float64)
+        series["neck"] = necks[np.clip(np.searchsorted(stamps, grid, side="right") - 1, 0, len(necks) - 1)].tolist()
     for key in (*KEYS, "sharpness", "residual"):
         values = np.array([row[key] for row in picked], dtype=np.float64)
         valid = np.isfinite(values)
@@ -321,23 +322,45 @@ def transitions(counts):
     return joins, splits
 
 
+def neck_difference(a, b):
+    a_neck, b_neck = a["neck"], b["neck"]
+    if np.isfinite(a_neck) and np.isfinite(b_neck):
+        return float(abs(a_neck - b_neck))
+    if not np.isfinite(a_neck) and not np.isfinite(b_neck):
+        return 0.0
+    return float("inf")
+
+
+def transition_gap(a, b):
+    if a and b:
+        return abs(a[0] - b[0]) * 1000 / align.GRID_HZ
+    return 0.0 if not a and not b else float("inf")
+
+
+def neck_rms(a_count, b_count, a_neck, b_neck):
+    squares = []
+    for ca, cb, na, nb in zip(a_count, b_count, a_neck, b_neck):
+        difference = neck_difference({"neck": na}, {"neck": nb})
+        if np.isinf(difference) and ca != cb:
+            continue
+        if np.isfinite(na) or np.isfinite(nb):
+            squares.append(difference ** 2)
+    return float(np.sqrt(np.mean(squares))) if squares else 0.0
+
+
 def compare_topology(a_series, b_series):
     a_count, b_count = np.array(a_series["count"]), np.array(b_series["count"])
-    if a_count.max() < 2 and b_count.max() < 2:
-        return None
     entry = {}
     a_joins, a_splits = transitions(a_count)
     b_joins, b_splits = transitions(b_count)
-    for key, a, b in (("join_ms", a_joins, b_joins), ("split_ms", a_splits, b_splits)):
-        if a and b:
-            entry[key] = abs(a[0] - b[0]) * 1000 / align.GRID_HZ
+    entry["join_ms"] = transition_gap(a_joins, b_joins)
+    entry["split_ms"] = transition_gap(a_splits, b_splits)
     count = min(len(a_count), len(b_count))
     excluded = np.zeros(count, dtype=bool)
     for index in a_joins + a_splits + b_joins + b_splits:
         excluded[max(0, index - TRANSITION_SAMPLES) : index + TRANSITION_SAMPLES + 1] = True
     entry["count"] = float(((a_count[:count] != b_count[:count]) & ~excluded).sum())
-    a_neck, b_neck = np.array(a_series["neck"][:count]), np.array(b_series["neck"][:count])
-    entry["neck_rms"] = float(np.sqrt(np.mean((a_neck - b_neck) ** 2)))
+    entry["neck_rms"] = neck_rms(a_count[:count], b_count[:count], a_series["neck"][:count], b_series["neck"][:count])
     entry["native"] = {"joins_ms": [i * 1000 / align.GRID_HZ for i in a_joins], "splits_ms": [i * 1000 / align.GRID_HZ for i in a_splits]}
     entry["flutter"] = {"joins_ms": [i * 1000 / align.GRID_HZ for i in b_joins], "splits_ms": [i * 1000 / align.GRID_HZ for i in b_splits]}
     return entry
@@ -363,9 +386,7 @@ def compare(scene, native, flutter):
             sa, sb = a["series"][name], b["series"][name]
             shape = {}
             if name in scene.topology:
-                topology = compare_topology(sa, sb)
-                if topology:
-                    shape["topology"] = topology
+                shape["topology"] = compare_topology(sa, sb)
             for key in align.KEYS:
                 entry = compare_key(key, sa[key], sb[key])
                 if entry:
@@ -467,6 +488,6 @@ def static_topology(scene, native_dir, flutter_dir):
             "native": rows["native"],
             "flutter": rows["flutter"],
             "count": abs(rows["native"]["count"] - rows["flutter"]["count"]),
-            "neck_pt": abs(rows["native"]["neck"] - rows["flutter"]["neck"]),
+            "neck_pt": neck_difference(rows["native"], rows["flutter"]),
         }
     return found
diff --git a/packages/mobile/tool/glass_lab/harness/track.py b/packages/mobile/tool/glass_lab/harness/track.py
index ea46a8c0e43bc5eae1546d0920667190a63511bd..2d8f1b5215690b2921c2dac1731bb93bbf58acc2 100644
--- a/packages/mobile/tool/glass_lab/harness/track.py
+++ b/packages/mobile/tool/glass_lab/harness/track.py
@@ -224,7 +224,7 @@ def still_mask(frame, bare):
 def topology(mask):
     parts = components(point_mask(mask))
     if len(parts) != 1:
-        return {"count": float(len(parts)), "neck": 0.0}
+        return {"count": float(len(parts)), "neck": float("nan")}
     width = neck(mask)
     return {"count": 1.0, "neck": width if width > 0 else float("nan")}
 
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t01-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_manifest.py` => PASS

Expected output ends with:

```text
Ran 56 tests in <time>
OK
```

- [ ] **Step 5: Gate: harness.**

RUN[t01-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

Expected output ends with:

```text
Ran 213 tests in <time>
OK
```

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "fix(glass_lab): topology reads agreeing apps as zero, no neck without one joined component, manifest rejects topology measures without regions

Co-Authored-By: <the session's attribution line>"
```

### Task 2: N7 finer gap series and spacing probes (scenes and native controls)

**Files:**
- Modify: `tool/glass_lab/scenes.json` (the `material.spacing.*` scenes 4, 6, 8, 10, 12, 16, 20 and the finer series `default.d`, `20.b`, `20.c`, `40.d`, `40.e`, `80.a`–`80.e`)
- Modify: `tool/glass_lab/native/GlassLab/MaterialScenes.swift` (the matching native scenes)

**Why.** Ruling 7. Native merge reach is read from these scenes; the 2B.1 N7 set (`default.a`–`c`, `40.a`–`c`) could not pin it. The Swift is compiled in Task 7's gate.

- [ ] **Step 1: Apply the implementation.**

Patch `t02-impl` (`fb0207573..54cfd52d5`, 2 files):

```diff
diff --git a/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift b/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift
index b638301a1db008b0b9d27f10bcca216043961bc5..82ac992b86b69736f120578d4a5596012638bdff 100644
--- a/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift
+++ b/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift
@@ -21,6 +21,23 @@ enum MaterialScenes {
         "material.spacing.40.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 40)) },
         "material.spacing.40.b": { AnyView(SpacingScene(gaps: [16, 20, 24, 32], spacing: 40)) },
         "material.spacing.40.c": { AnyView(SpacingScene(gaps: [40, 48, 60], spacing: 40)) },
+        "material.spacing.4.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 4)) },
+        "material.spacing.6.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 6)) },
+        "material.spacing.8.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 8)) },
+        "material.spacing.10.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 10)) },
+        "material.spacing.12.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 12)) },
+        "material.spacing.16.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 16)) },
+        "material.spacing.20.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 20)) },
+        "material.spacing.80.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 80)) },
+        "material.spacing.default.d": { AnyView(SpacingScene(gaps: [2, 5, 6, 7], spacing: nil)) },
+        "material.spacing.20.b": { AnyView(SpacingScene(gaps: [9, 10, 11, 14], spacing: 20)) },
+        "material.spacing.20.c": { AnyView(SpacingScene(gaps: [16, 18, 24, 32], spacing: 20)) },
+        "material.spacing.40.d": { AnyView(SpacingScene(gaps: [18, 19, 21, 22], spacing: 40)) },
+        "material.spacing.40.e": { AnyView(SpacingScene(gaps: [28, 36, 44, 52], spacing: 40)) },
+        "material.spacing.80.b": { AnyView(SpacingScene(gaps: [16, 24, 32, 36], spacing: 80)) },
+        "material.spacing.80.c": { AnyView(SpacingScene(gaps: [38, 40, 42, 44], spacing: 80)) },
+        "material.spacing.80.d": { AnyView(SpacingScene(gaps: [48, 56, 64, 72], spacing: 80)) },
+        "material.spacing.80.e": { AnyView(SpacingScene(gaps: [80, 88, 96], spacing: 80)) },
         "material.merge": { AnyView(MergeScene()) },
         "material.union": { AnyView(UnionScene()) },
         "material.morph": { AnyView(MorphScene()) },
diff --git a/packages/mobile/tool/glass_lab/scenes.json b/packages/mobile/tool/glass_lab/scenes.json
index 024c209b6bf819a62ca3126d891e283a5dea56d9..1752a00c28d0c54128230c2fa5a7c32d46e12db3 100644
--- a/packages/mobile/tool/glass_lab/scenes.json
+++ b/packages/mobile/tool/glass_lab/scenes.json
@@ -947,6 +947,798 @@
       "g60"
     ]
   },
+  {
+    "id": "material.spacing.4.a",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 0, 4, 8, 12 pt in GlassEffectContainer(spacing: 4)",
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
+    "id": "material.spacing.6.a",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 0, 4, 8, 12 pt in GlassEffectContainer(spacing: 6)",
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
+    "id": "material.spacing.8.a",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 0, 4, 8, 12 pt in GlassEffectContainer(spacing: 8)",
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
+    "id": "material.spacing.10.a",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 0, 4, 8, 12 pt in GlassEffectContainer(spacing: 10)",
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
+    "id": "material.spacing.12.a",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 0, 4, 8, 12 pt in GlassEffectContainer(spacing: 12)",
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
+    "id": "material.spacing.16.a",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 0, 4, 8, 12 pt in GlassEffectContainer(spacing: 16)",
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
+    "id": "material.spacing.20.a",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 0, 4, 8, 12 pt in GlassEffectContainer(spacing: 20)",
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
+    "id": "material.spacing.80.a",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 0, 4, 8, 12 pt in GlassEffectContainer(spacing: 80)",
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
+    "id": "material.spacing.default.d",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 2, 5, 6, 7 pt in the default GlassEffectContainer()",
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
+      "g2": [
+        108,
+        129,
+        186,
+        104
+      ],
+      "g5": [
+        106.5,
+        309,
+        189,
+        104
+      ],
+      "g6": [
+        106,
+        489,
+        190,
+        104
+      ],
+      "g7": [
+        105.5,
+        669,
+        191,
+        104
+      ]
+    },
+    "topology": [
+      "g2",
+      "g5",
+      "g6",
+      "g7"
+    ]
+  },
+  {
+    "id": "material.spacing.20.b",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 9, 10, 11, 14 pt in GlassEffectContainer(spacing: 20)",
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
+      "g9": [
+        104.5,
+        129,
+        193,
+        104
+      ],
+      "g10": [
+        104,
+        309,
+        194,
+        104
+      ],
+      "g11": [
+        103.5,
+        489,
+        195,
+        104
+      ],
+      "g14": [
+        102,
+        669,
+        198,
+        104
+      ]
+    },
+    "topology": [
+      "g9",
+      "g10",
+      "g11",
+      "g14"
+    ]
+  },
+  {
+    "id": "material.spacing.20.c",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 16, 18, 24, 32 pt in GlassEffectContainer(spacing: 20)",
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
+      "g18": [
+        100,
+        309,
+        202,
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
+      "g18",
+      "g24",
+      "g32"
+    ]
+  },
+  {
+    "id": "material.spacing.40.d",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 18, 19, 21, 22 pt in GlassEffectContainer(spacing: 40)",
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
+      "g18": [
+        100,
+        129,
+        202,
+        104
+      ],
+      "g19": [
+        99.5,
+        309,
+        203,
+        104
+      ],
+      "g21": [
+        98.5,
+        489,
+        205,
+        104
+      ],
+      "g22": [
+        98,
+        669,
+        206,
+        104
+      ]
+    },
+    "topology": [
+      "g18",
+      "g19",
+      "g21",
+      "g22"
+    ]
+  },
+  {
+    "id": "material.spacing.40.e",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 28, 36, 44, 52 pt in GlassEffectContainer(spacing: 40)",
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
+      "g28": [
+        95,
+        129,
+        212,
+        104
+      ],
+      "g36": [
+        91,
+        309,
+        220,
+        104
+      ],
+      "g44": [
+        87,
+        489,
+        228,
+        104
+      ],
+      "g52": [
+        83,
+        669,
+        236,
+        104
+      ]
+    },
+    "topology": [
+      "g28",
+      "g36",
+      "g44",
+      "g52"
+    ]
+  },
+  {
+    "id": "material.spacing.80.b",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 16, 24, 32, 36 pt in GlassEffectContainer(spacing: 80)",
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
+      "g24": [
+        97,
+        309,
+        208,
+        104
+      ],
+      "g32": [
+        93,
+        489,
+        216,
+        104
+      ],
+      "g36": [
+        91,
+        669,
+        220,
+        104
+      ]
+    },
+    "topology": [
+      "g16",
+      "g24",
+      "g32",
+      "g36"
+    ]
+  },
+  {
+    "id": "material.spacing.80.c",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 38, 40, 42, 44 pt in GlassEffectContainer(spacing: 80)",
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
+      "g38": [
+        90,
+        129,
+        222,
+        104
+      ],
+      "g40": [
+        89,
+        309,
+        224,
+        104
+      ],
+      "g42": [
+        88,
+        489,
+        226,
+        104
+      ],
+      "g44": [
+        87,
+        669,
+        228,
+        104
+      ]
+    },
+    "topology": [
+      "g38",
+      "g40",
+      "g42",
+      "g44"
+    ]
+  },
+  {
+    "id": "material.spacing.80.d",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 48, 56, 64, 72 pt in GlassEffectContainer(spacing: 80)",
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
+      "g48": [
+        85,
+        129,
+        232,
+        104
+      ],
+      "g56": [
+        81,
+        309,
+        240,
+        104
+      ],
+      "g64": [
+        77,
+        489,
+        248,
+        104
+      ],
+      "g72": [
+        73,
+        669,
+        256,
+        104
+      ]
+    },
+    "topology": [
+      "g48",
+      "g56",
+      "g64",
+      "g72"
+    ]
+  },
+  {
+    "id": "material.spacing.80.e",
+    "group": "material",
+    "title": "Two 80 pt circles at gaps 80, 88, 96 pt in GlassEffectContainer(spacing: 80)",
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
+      "g80": [
+        69,
+        219,
+        264,
+        104
+      ],
+      "g88": [
+        65,
+        399,
+        272,
+        104
+      ],
+      "g96": [
+        61,
+        579,
+        280,
+        104
+      ]
+    },
+    "topology": [
+      "g80",
+      "g88",
+      "g96"
+    ]
+  },
   {
     "id": "material.shapes",
     "group": "material",
```

- [ ] **Step 2: Check the manifest still loads and validates every scene.**

RUN[t02-manifest]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_manifest.py` => PASS

Expected output ends with:

```text
Ran 17 tests in <time>
OK
```

- [ ] **Step 3: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): N7 finer gap series and spacing probes for native merge reach

Co-Authored-By: <the session's attribution line>"
```

### Task 3: Gotcha 52: the 2B.1 floors without the take that set a limit, recorded again in this checkout

**Files:**
- Modify: `tool/glass_lab/noise.json` (written by `lab.py repeat`; no patch: execution makes it from its own takes)

**Why.** Ruling 5. 2B.1's `noise.json` holds `cy.peak_ms` 150 for `material.materialize` light-photo-reduce-motion because one of its five takes (take 2) reads its disappear onset 98 ms early. The prototype fixed that in its own, untracked copy of `noise-2b1`; that copy does not travel. This task does the same in the executor's copy by the same moves, records the replacement take after a fresh boot, and lets `repeat` write `noise.json` from the executor's own takes. The prototype's result (`R/gotcha52-moved.json`) is the expectation, not a patch. **The archive's pair-folder links are all dangling:** every one of its 1206 `pair-*/native|flutter` links names `/Users/omaraly/development/AI/Operator-2b1/packages/mobile/build/glass_lab/runs/noise-2b1/...`, a worktree that no longer exists, and this task runs with `development`'s `lab.py`, whose `case_noise` raises `FileExistsError` on a link that exists but points nowhere (Task 9 repairs that later). So the copy is relinked by script before `repeat` runs; the prototype did the same by hand (`excluded/relinks-2b2.json` records old and new targets). Task 9 stays where it is.

- [ ] **Step 1: Copy the archive's `noise-2b1` (never move or write the archive), after checking the disk.** The archive (`/Users/omaraly/development/AI/glass-lab-runs/2b1/runs/noise-2b1`) is only ever read and copied: nothing in this plan moves, deletes or records into it, and every later step in this task works on the copy. The copy is about 8.6 GB on disk (13 GB with caches counted differently by Finder); `repeat` adds one take's frame caches and the analysis of the case's pairs, under 1 GB.

```bash
cd /Users/omaraly/development/AI/Operator-2b2/packages/mobile
R=/Users/omaraly/development/AI/Operator-2b2/docs/liquid_glass/02b-motion/research/proto-2b2
NOISE=$PWD/build/glass_lab/runs/noise-2b1
CASE=material.materialize/light-photo-reduce-motion
df -h /Users/omaraly
test ! -e $NOISE && mkdir -p build/glass_lab/runs && cp -R /Users/omaraly/development/AI/glass-lab-runs/2b1/runs/noise-2b1 build/glass_lab/runs/
test -d $NOISE && test ! -L $NOISE && echo "copy, not a link"
find $NOISE -type l ! -exec test -e {} \; -print | wc -l
df -h /Users/omaraly
```

Expected: `copy, not a link`, then `1206` (every pair link in the copy is dangling; they name the removed `Operator-2b1` worktree), and about 8.6 GB less free space. **Stop under 40 GB free before the copy and report** (the user decides what to clear; do not delete anything to make room). If `$NOISE` exists already, check `test ! -L $NOISE` and use it only if it is a real directory.

- [ ] **Step 2: Take 2 out of the floors, by these moves.** `$NOISE` is the executor's copy of the archive's `noise-2b1` (Step 1); the moves are exactly the prototype's.

```bash
cd /Users/omaraly/development/AI/Operator-2b2/packages/mobile
R=/Users/omaraly/development/AI/Operator-2b2/docs/liquid_glass/02b-motion/research/proto-2b2
NOISE=$PWD/build/glass_lab/runs/noise-2b1
CASE=material.materialize/light-photo-reduce-motion
mkdir -p $NOISE/excluded/takes/$CASE $NOISE/excluded/$CASE
mv $NOISE/takes/$CASE/2 $NOISE/excluded/takes/$CASE/2
for pair in pair-0-2 pair-1-2 pair-3-2 pair-4-2; do mv $NOISE/$CASE/$pair $NOISE/excluded/$CASE/$pair; done
mkdir -p $NOISE/excluded/stale-pairs/material.materialize/light-stripes $NOISE/excluded/stale-pairs/material.materialize.bouncy/dark-stripes-reduce-motion $NOISE/excluded/stale-pairs/material.materialize.bouncy/dark-photo-reduce-motion
mv $NOISE/material.materialize/light-stripes/pair-4-5 $NOISE/excluded/stale-pairs/material.materialize/light-stripes/pair-4-5
mv $NOISE/material.materialize.bouncy/dark-stripes-reduce-motion/pair-4-5 $NOISE/excluded/stale-pairs/material.materialize.bouncy/dark-stripes-reduce-motion/pair-4-5
mv $NOISE/material.materialize.bouncy/dark-photo-reduce-motion/pair-4-5 $NOISE/excluded/stale-pairs/material.materialize.bouncy/dark-photo-reduce-motion/pair-4-5
printf '%s\n' "takes/$CASE/2 (session 2): its disappear onset is read 98 ms before the glass moves (its first changed frame and the next, 53 ms later, both at progress 0.981), so it alone set the case's disappear response_pct, settle_ms and damping limits (ROADMAP gotcha 52). Moved here with the four pair folders that used it; replaced by a take recorded after a fresh boot." "The three pair-4-5 folders under stale-pairs named a take 5 that 2B.1 deleted with its excluded takes; their links point nowhere." > $NOISE/excluded/README.txt
test ! -e $NOISE/takes/$CASE/2 && ls $NOISE/takes/$CASE
```

Expected: `ls` lists `0 1 3 4`. (Take 2 is absent; the next take number `repeat` appends is 5.)

- [ ] **Step 3: Point the copy's pair links at the copy.** The links that remain in the copy all name the removed `Operator-2b1` worktree (Step 1); the three stale `pair-4-5` folders and the four `pair-*-2` folders of the case, whose links named takes that no longer exist, were moved out by Step 2, so every remaining link has a take of the same number in the copy. `relink_noise.py` rewrites each of them to the same take inside `$NOISE`, refuses the archive and a link-not-copy, stops if any target is missing from the copy, and records old and new targets in `$NOISE/excluded/relinks-2b2.json`:

```bash
python3 $R/relink_noise.py $NOISE
find $NOISE -type l ! -exec test -e {} \; -print | wc -l
```

Expected: `relinked 1192 links` (1206 less the 14 in the seven folders Step 2 moved) and then `0` dangling links. A `MISSING` line stops the task: report it. Without this step `repeat` would record take 5 and then raise `FileExistsError` in `case_noise` on the first pair folder (`pair-0-1`) before it writes `noise.json`, and the rerun would record take 6.

- [ ] **Step 4: Build, reboot, check the press, record the replacement take.** The replacement is recorded in this task; nothing is copied from the prototype's `build/` folder (it is untracked and goes with the prototype worktree). One case only, so the flags name it:

```bash
python3 tool/glass_lab/harness/lab.py build native
python3 -c "import sys; sys.path.insert(0, 'tool/glass_lab/harness'); import sim, build; u = sim.device(); sim.status_bar(u); [sim.install_backdrops(u, b, build.backdrops()) for b in (build.NATIVE_BUNDLE, build.EXAMPLE_BUNDLE)]"
python3 tool/glass_lab/harness/lab.py reboot
python3 tool/glass_lab/harness/lab.py run material.interactive --app native --appearance light --backdrop photo
python3 $R/press_check.py --harness tool/glass_lab/harness build/glass_lab/runs/<that run>/material.interactive/light-photo/native
python3 tool/glass_lab/harness/lab.py repeat material.materialize --times 1 --appearance light --backdrop photo --a11y reduce-motion --into $NOISE
```

Expected: `press 0.9xx s PASS` (0.8-1.2 s; else reboot again, gotcha 49), then `repeat` prints that it recorded take 5 of `light-photo-reduce-motion` and rewrites that case's entry in `tool/glass_lab/noise.json` from takes 0, 1, 3, 4, 5. **Run `repeat` once.** If it ends in an error after printing `take 5` (the take is on disk), do not run it again: that would record take 6. Fix the cause and rerun it with `--times 0`, which records nothing and recomputes the case's floors and `noise.json` from the takes on disk. A `static repeatability FAILED` line stops the task: report it, do not commit. `repeat` refuses with `the native app build is older than its sources` when a package or Swift file changed since the last native build: run `python3 tool/glass_lab/harness/lab.py build native` and repeat the command.

- [ ] **Step 5: Check the new take and the file.**

```bash
python3 $R/take_check.py --harness tool/glass_lab/harness --scene material.materialize $NOISE/takes/$CASE/5
test -d $NOISE/excluded/takes/$CASE/2 && ! test -e $NOISE/takes/$CASE/2 && test -d $NOISE/takes/$CASE/5 && echo "take 2 excluded, take 5 present"
git show HEAD:packages/mobile/tool/glass_lab/noise.json > /tmp/noise-before.json
python3 $R/noise_recompute.py --harness tool/glass_lab/harness --run $NOISE --before /tmp/noise-before.json --out /tmp/gotcha52-moved.json $CASE
```

Expected: `take_check.py` reports no capture hole (a first-frame gap of 68-407 ms followed by frames 1.7-6.7 ms apart, gotcha 47), a touch window of the scene's length and the scene's touch count, and a disappear onset whose first changed frames are not both at progress 0.98 (that was take 2's fault); a take that fails any of these goes to `excluded/` with a README line and is replaced by another take after another fresh boot. Then `take 2 excluded, take 5 present`, and `noise_recompute.py` lists every value and limit that moved against 2B.1's file. The prototype's list (`R/gotcha52-moved.json`) has 27 values and 18 limits moved, 15 of them lower (for example `block.step1e0.cy.peak_ms` 150.0 to 25.0) and 3 higher (`block.step1e0.cx.peak_ms` 17 to 25, `block.step1e0.width.response_pct` 5 to 9.23, `block.step3e0.luma.peak_ms` 25 to 62.5), each equal to 1.5 times the recomputed noise, so they follow max(fixed, 1.5 x noise); the executor's take 5 is another recording, so its numbers differ, and **the list of what moved, with the three that rise named, goes into `results-2b2.md`**. Whatever moved, 2B.1's Done item 4 (266 of 336) was judged under the old floors and later counts under the new ones are not the same yardstick: the Done table says so.

- [ ] **Step 6: Commit.**

```bash
git add packages/mobile/tool/glass_lab/noise.json
git commit -m "fix(glass_lab): gotcha 52 take excluded and replaced after a fresh boot; noise.json recomputed for that case

Co-Authored-By: <the session's attribution line>"
```

### Task 4: Angle-weighted smooth union, native default spacing, animated spacing, the N7 and merge live scenes (M4)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/assets/shaders/sdf.glsl`, `lib/src/liquid_glass_blend_group.dart`, `lib/src/api/glass_effect_container.dart`, `lib/src/motion/glass_motion_coordinator.dart`, `FORK.md`, `README.md`
- Modify (app): `lib/core/widgets/glass/glass_scope.dart`
- Create (example): `lib/lab/scenes/spacing_scenes.dart`; modify `lib/lab/glass_lab_registry.dart`, `lib/lab/scenes/material_scenes.dart`
- Test: `test/geometry/{angle_union_test,pair_topology,scene_sdf_mirror}`, `test/motion/glass_spacing_test.dart`, example `test/spacing_scenes_test.dart`, app `test/core/widgets/glass/glass_scope_test.dart`

**Why.** Rulings 7–12. `scene_sdf_mirror.dart` and `pair_topology.dart` are the Dart mirror of the shader and its pair measures, so the geometry tests run without the GPU (`flutter test` cannot run the runtime effect). The app's `GlassScope` passes `spacing: 20` so its toolbars keep their look when the default becomes 8.

- [ ] **Step 1: Add the failing tests.**

Patch `t04-tests` (`4e32718e4..3269b9580`, 6 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/example/test/spacing_scenes_test.dart b/packages/mobile/packages/ios_liquid_glass/example/test/spacing_scenes_test.dart
new file mode 100644
index 0000000000000000000000000000000000000000..e7f6a19459799bfb5bdfaa44614915c89556f5bc
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/example/test/spacing_scenes_test.dart
@@ -0,0 +1,111 @@
+import 'dart:convert';
+import 'dart:io';
+
+import 'package:flutter/material.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+import 'package:ios_liquid_glass_example/lab/glass_lab_launch.dart';
+import 'package:ios_liquid_glass_example/lab/glass_lab_registry.dart';
+import 'package:ios_liquid_glass_example/lab/glass_lab_screen.dart';
+import 'package:ios_liquid_glass_example/lab/scenes/spacing_scenes.dart';
+
+const Size _screen = Size(402, 874);
+const double _top = 62;
+const double _bottom = 34;
+
+List<Map<String, dynamic>> _manifest() =>
+    (jsonDecode(File('../../../tool/glass_lab/scenes.json').readAsStringSync()) as List<dynamic>).cast<Map<String, dynamic>>();
+
+double _pixel(double points) => (points * 3 + 0.5).floorToDouble() / 3;
+
+void _iPhone17Pro(WidgetTester tester) {
+  tester.view.physicalSize = _screen * 3;
+  tester.view.devicePixelRatio = 3;
+  tester.view.padding = const FakeViewPadding(top: _top * 3, bottom: _bottom * 3);
+  addTearDown(tester.view.reset);
+}
+
+List<Rect> _glass(WidgetTester tester) {
+  final rects = [for (final element in find.byType(GlassEffect).evaluate()) tester.getRect(find.byWidget(element.widget))];
+  rects.sort((a, b) => a.top != b.top ? a.top.compareTo(b.top) : a.left.compareTo(b.left));
+  return rects;
+}
+
+void main() {
+  final spacingIds = [
+    for (final entry in _manifest())
+      if ((entry['id'] as String).startsWith('material.spacing.')) entry['id'] as String,
+  ];
+
+  test('every N7 spacing scene and the merge scene are registered, with the gaps their manifest regions name', () {
+    expect(spacingIds, hasLength(23));
+    expect(GlassLabRegistry.scenes.keys, containsAll([...spacingIds, 'material.merge']));
+    for (final entry in _manifest()) {
+      final id = entry['id'] as String;
+      if (!spacingIds.contains(id)) continue;
+      final regions = (entry['regions'] as Map<String, dynamic>).keys;
+      expect([for (final gap in SpacingScenes.gaps[id]!) 'g${gap.toInt()}'], regions.toList(), reason: id);
+      final spacing = id.split('.')[2];
+      expect(SpacingScenes.spacing[id], spacing == 'default' ? isNull : double.parse(spacing), reason: id);
+    }
+  });
+
+  testWidgets('each spacing scene places its pairs as native does: 80 pt circles, 100 pt apart, centred on the pixel grid', (tester) async {
+    _iPhone17Pro(tester);
+    final safe = _screen.height - _top - _bottom;
+    for (final entry in _manifest()) {
+      final id = entry['id'] as String;
+      if (!spacingIds.contains(id)) continue;
+      await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: id))));
+      await tester.pump();
+      final gaps = SpacingScenes.gaps[id]!;
+      final height = gaps.length * 80 + (gaps.length - 1) * 100;
+      final rects = _glass(tester);
+      expect(rects, hasLength(gaps.length * 2), reason: id);
+      final regions = (entry['regions'] as Map<String, dynamic>).values.map((r) => (r as List<dynamic>).cast<num>()).toList();
+      for (final (index, gap) in gaps.indexed) {
+        final top = _top + (safe - height) / 2 + index * 180;
+        final left = _pixel((_screen.width - 160 - gap) / 2);
+        expect(rects[2 * index], Rect.fromLTWH(left, top, 80, 80), reason: '$id g$gap');
+        expect(rects[2 * index + 1], Rect.fromLTWH(left + 80 + gap, top, 80, 80), reason: '$id g$gap');
+        final region = Rect.fromLTWH(regions[index][0].toDouble(), regions[index][1].toDouble(), regions[index][2].toDouble(), regions[index][3].toDouble());
+        expect(region.inflate(-11).contains(rects[2 * index].topLeft) && region.inflate(-11).contains(rects[2 * index + 1].bottomRight), isTrue, reason: '$id g$gap');
+      }
+      final containers = tester.widgetList<GlassEffectContainer>(find.byType(GlassEffectContainer)).toList();
+      expect(containers, hasLength(gaps.length), reason: id);
+      for (final container in containers) {
+        expect(container.spacing, SpacingScenes.spacing[id] ?? 8, reason: id);
+      }
+      await tester.pumpWidget(const SizedBox());
+    }
+  });
+
+  testWidgets('an odd-width pair sits half a pixel right of the half point, as native g5 does at x 118.667', (tester) async {
+    _iPhone17Pro(tester);
+    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.spacing.default.d'))));
+    await tester.pump();
+    expect(_glass(tester)[2].left, closeTo(356 / 3, 1e-9));
+  });
+
+  testWidgets('the merge scene closes its gap on Merge and opens it again on Split, centred in its container', (tester) async {
+    _iPhone17Pro(tester);
+    final semantics = tester.ensureSemantics();
+    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.merge'))));
+    await tester.pump();
+    expect(tester.widget<GlassEffectContainer>(find.byType(GlassEffectContainer)).spacing, 40);
+    const top = _top + (874 - _top - _bottom - 80) / 2;
+    expect(_glass(tester), [const Rect.fromLTWH(81, top, 80, 80), const Rect.fromLTWH(241, top, 80, 80)]);
+    final merge = tester.getRect(find.bySemanticsIdentifier('merge'));
+    final split = tester.getRect(find.bySemanticsIdentifier('split'));
+    expect(merge.bottom, _screen.height - _bottom - 120);
+    expect(split.left - merge.right, 24);
+    expect((merge.left + split.right) / 2, _screen.width / 2);
+    await tester.tap(find.bySemanticsIdentifier('merge'));
+    await tester.pumpAndSettle();
+    expect(_glass(tester), [const Rect.fromLTWH(121, top, 80, 80), const Rect.fromLTWH(201, top, 80, 80)]);
+    await tester.tap(find.bySemanticsIdentifier('split'));
+    await tester.pumpAndSettle();
+    expect(_glass(tester), [const Rect.fromLTWH(81, top, 80, 80), const Rect.fromLTWH(241, top, 80, 80)]);
+    semantics.dispose();
+  });
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/test/geometry/angle_union_test.dart b/packages/mobile/packages/ios_liquid_glass/test/geometry/angle_union_test.dart
new file mode 100644
index 0000000000000000000000000000000000000000..2087b59ddcb484ad58fbea793aa38cfa749328f1
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/test/geometry/angle_union_test.dart
@@ -0,0 +1,69 @@
+import 'dart:math' as math;
+
+import 'package:flutter_test/flutter_test.dart';
+
+import 'pair_topology.dart';
+import 'scene_sdf_mirror.dart';
+
+double _model(double gap, double k, double x, double y) {
+  final cx = pairRadius + gap / 2;
+  final r1 = math.sqrt((x + cx) * (x + cx) + y * y), r2 = math.sqrt((x - cx) * (x - cx) + y * y);
+  final a = r1 - pairRadius, b = r2 - pairRadius;
+  if (k <= 0) return math.min(a, b);
+  final h = math.max(k - (a - b).abs(), 0.0) / k;
+  final dot = ((x + cx) * (x - cx) + y * y) / math.max(r1 * r2, 1e-9);
+  return math.min(a, b) - h * h * k / 4 * (1 - dot) / 2;
+}
+
+List<MirrorShape> _pair(double gap) {
+  final cx = pairRadius + gap / 2;
+  return [MirrorShape.circle(-cx, 0, 2 * pairRadius), MirrorShape.circle(cx, 0, 2 * pairRadius)];
+}
+
+void main() {
+  test('two 80 pt circles at k = 40 and gap 0 join with the model neck of 50 pt', () {
+    final field = PairField(0, 40);
+    expect(field.count, 1);
+    expect(field.neck, closeTo(50, 1e-9));
+  });
+
+  test('the neck narrows with the gap as the model draws it: 45.33 pt at 4, 12 pt at 19', () {
+    expect(PairField(4, 40).neck, closeTo(136 / 3, 1e-9));
+    expect(PairField(19, 40).neck, closeTo(12, 1e-9));
+  });
+
+  test('at gap 20 and k = 40 the circles still touch through a pinch two pixels wide', () {
+    final field = PairField(20, 40);
+    expect(field.count, 1);
+    expect(field.neck, closeTo(2 / 3, 1e-9));
+  });
+
+  test('from gap 21 the circles are apart, and at gap 24 each inner edge bulges 3 pt past its circle', () {
+    expect(PairField(21, 40).count, 2);
+    final field = PairField(24, 40);
+    expect(field.count, 2);
+    expect(field.tip, closeTo(3, 1e-9));
+  });
+
+  test('two shapes draw the angle-weighted smooth union exactly', () {
+    for (final (gap, k) in [(0.0, 40.0), (12.0, 40.0), (24.0, 40.0), (4.0, 8.0), (30.0, 80.0)]) {
+      final shapes = _pair(gap);
+      var worst = 0.0;
+      for (var y = -52.0; y <= 52; y += 1.25) {
+        for (var x = -100.0; x <= 100; x += 1.25) {
+          worst = math.max(worst, (sceneSdf(shapes, x, y, k) - _model(gap, k, x, y)).abs());
+        }
+      }
+      expect(worst, lessThan(1e-9), reason: 'gap $gap, k $k');
+    }
+  });
+
+  test('a blend of 0 is the plain minimum of the shapes', () {
+    final shapes = _pair(0);
+    for (var x = -60.0; x <= 60; x += 3.5) {
+      for (var y = -50.0; y <= 50; y += 3.5) {
+        expect(sceneSdf(shapes, x, y, 0), math.min(shapeSdf(shapes[0], x, y), shapeSdf(shapes[1], x, y)));
+      }
+    }
+  });
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/test/geometry/pair_topology.dart b/packages/mobile/packages/ios_liquid_glass/test/geometry/pair_topology.dart
new file mode 100644
index 0000000000000000000000000000000000000000..a9d7b9a2941b3a8144a2d439ccdd6ad0d33f4c4a
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/test/geometry/pair_topology.dart
@@ -0,0 +1,136 @@
+import 'dart:collection';
+import 'dart:math' as math;
+
+import 'scene_sdf_mirror.dart';
+
+const int pairScale = 3;
+const double pairRadius = 40;
+const int topologyMinArea = 20;
+
+class PairField {
+  PairField._(this.gap, this.width, this.height, this.mask);
+
+  factory PairField(double gap, double k) {
+    final widthPt = 2 * pairRadius + gap + 24;
+    const heightPt = 2 * pairRadius + 24;
+    final width = (widthPt * pairScale).toInt();
+    final height = (heightPt * pairScale).toInt();
+    final cx = pairRadius + gap / 2;
+    final shapes = [MirrorShape.circle(-cx, 0, 2 * pairRadius), MirrorShape.circle(cx, 0, 2 * pairRadius)];
+    final mask = List.generate(height, (row) {
+      final y = (row + 0.5) / pairScale - heightPt / 2;
+      return List.generate(width, (column) => sceneSdf(shapes, (column + 0.5) / pairScale - widthPt / 2, y, k) < 0);
+    });
+    return PairField._(gap, width, height, mask);
+  }
+
+  final double gap;
+  final int width;
+  final int height;
+  final List<List<bool>> mask;
+
+  double xOf(int column) => (column + 0.5) / pairScale - (2 * pairRadius + gap + 24) / 2;
+
+  int get count {
+    final rows = height ~/ pairScale, columns = width ~/ pairScale;
+    final points = List.generate(rows, (r) => List.generate(columns, (c) {
+      var lit = 0;
+      for (var dy = 0; dy < pairScale; dy++) {
+        for (var dx = 0; dx < pairScale; dx++) {
+          if (mask[r * pairScale + dy][c * pairScale + dx]) lit++;
+        }
+      }
+      return lit / (pairScale * pairScale) >= 0.5;
+    }));
+    final seen = List.generate(rows, (_) => List.filled(columns, false));
+    var found = 0;
+    for (var r = 0; r < rows; r++) {
+      for (var c = 0; c < columns; c++) {
+        if (!points[r][c] || seen[r][c]) continue;
+        seen[r][c] = true;
+        final queue = Queue<(int, int)>()..add((r, c));
+        var area = 0;
+        while (queue.isNotEmpty) {
+          final (y, x) = queue.removeFirst();
+          area++;
+          for (final (ny, nx) in [(y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)]) {
+            if (ny >= 0 && ny < rows && nx >= 0 && nx < columns && points[ny][nx] && !seen[ny][nx]) {
+              seen[ny][nx] = true;
+              queue.add((ny, nx));
+            }
+          }
+        }
+        if (area >= topologyMinArea) found++;
+      }
+    }
+    return found;
+  }
+
+  int _crossSection(double px, double py, double nx, double ny) {
+    var length = 0;
+    for (final direction in [1, -1]) {
+      var step = direction == 1 ? 0 : 1;
+      while (true) {
+        final ix = (px + nx * direction * step).floor(), iy = (py + ny * direction * step).floor();
+        if (!(ix >= 0 && ix < width && iy >= 0 && iy < height && mask[iy][ix])) break;
+        length++;
+        step++;
+      }
+    }
+    return length;
+  }
+
+  double get neck {
+    final xs = <double>[], ys = <double>[];
+    for (var r = 0; r < height; r++) {
+      for (var c = 0; c < width; c++) {
+        if (mask[r][c]) {
+          xs.add(c + 0.5);
+          ys.add(r + 0.5);
+        }
+      }
+    }
+    final n = xs.length;
+    final mx = xs.reduce((a, b) => a + b) / n, my = ys.reduce((a, b) => a + b) / n;
+    var sxx = 0.0, syy = 0.0, sxy = 0.0;
+    for (var i = 0; i < n; i++) {
+      sxx += (xs[i] - mx) * (xs[i] - mx);
+      syy += (ys[i] - my) * (ys[i] - my);
+      sxy += (xs[i] - mx) * (ys[i] - my);
+    }
+    final lambda = (sxx + syy) / 2 + math.sqrt(math.pow((sxx - syy) / 2, 2) + sxy * sxy);
+    var (ax, ay) = sxy != 0 ? (lambda - syy, sxy) : (sxx >= syy ? (1.0, 0.0) : (0.0, 1.0));
+    final norm = math.sqrt(ax * ax + ay * ay);
+    ax /= norm;
+    ay /= norm;
+    var lx = 0.0, ly = 0.0, rx = 0.0, ry = 0.0, ln = 0, rn = 0;
+    for (var i = 0; i < n; i++) {
+      if ((xs[i] - mx) * ax + (ys[i] - my) * ay < 0) {
+        lx += xs[i];
+        ly += ys[i];
+        ln++;
+      } else {
+        rx += xs[i];
+        ry += ys[i];
+        rn++;
+      }
+    }
+    final aX = lx / ln, aY = ly / ln, bX = rx / rn, bY = ry / rn;
+    final span = math.sqrt((bX - aX) * (bX - aX) + (bY - aY) * (bY - aY));
+    final alongX = (bX - aX) / span, alongY = (bY - aY) / span;
+    var narrowest = 1 << 30;
+    for (var t = 0.0; t <= span + 1e-9; t += 1) {
+      narrowest = math.min(narrowest, _crossSection(aX + alongX * t, aY + alongY * t, -alongY, alongX));
+    }
+    return narrowest / pairScale;
+  }
+
+  double get tip {
+    final row = mask[height ~/ 2];
+    var last = -1;
+    for (var c = 0; c < width ~/ 2; c++) {
+      if (row[c]) last = c;
+    }
+    return xOf(last) + 0.5 / pairScale + gap / 2;
+  }
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/test/geometry/scene_sdf_mirror.dart b/packages/mobile/packages/ios_liquid_glass/test/geometry/scene_sdf_mirror.dart
new file mode 100644
index 0000000000000000000000000000000000000000..4c582905a54bac19e1756d9ca6a80c0eeb6b8ff2
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/test/geometry/scene_sdf_mirror.dart
@@ -0,0 +1,107 @@
+import 'dart:math' as math;
+
+class MirrorShape {
+  const MirrorShape(this.type, this.cx, this.cy, this.width, this.height, this.radius);
+
+  const MirrorShape.circle(double cx, double cy, double diameter) : this(2, cx, cy, diameter, diameter, 0);
+
+  final double type;
+  final double cx;
+  final double cy;
+  final double width;
+  final double height;
+  final double radius;
+}
+
+class Sdf {
+  const Sdf(this.d, this.nx, this.ny);
+
+  final double d;
+  final double nx;
+  final double ny;
+}
+
+const double _squircleExponent = 3.5;
+const double _squircleExtent = 1.65;
+
+double _sign(double v) => v > 0 ? 1 : (v < 0 ? -1 : 0);
+
+double _length(double x, double y) => math.sqrt(x * x + y * y);
+
+Sdf sdfRRect(double px, double py, double bx, double by, double r) {
+  r = math.min(r, math.min(bx, by));
+  final qx = px.abs() - bx + r, qy = py.abs() - by + r;
+  final mx = math.max(qx, 0.0), my = math.max(qy, 0.0);
+  final d = math.min(math.max(qx, qy), 0.0) + _length(mx, my) - r;
+  final (gx, gy) = mx > 0 || my > 0 ? (mx, my) : (qx > qy ? (1.0, 0.0) : (0.0, 1.0));
+  return _shaped(d, gx, gy, px, py);
+}
+
+Sdf sdfSquircle(double px, double py, double bx, double by, double r) {
+  r = math.min(r * _squircleExtent, math.min(bx, by));
+  final qx = px.abs() - bx + r, qy = py.abs() - by + r;
+  final mx = math.max(qx, 0.0), my = math.max(qy, 0.0);
+  final corner = math.pow(math.pow(mx, _squircleExponent) + math.pow(my, _squircleExponent), 1 / _squircleExponent).toDouble();
+  final d = math.min(math.max(qx, qy), 0.0) + corner - r;
+  final (gx, gy) = mx > 0 || my > 0
+      ? (math.pow(mx, _squircleExponent - 1).toDouble(), math.pow(my, _squircleExponent - 1).toDouble())
+      : (qx > qy ? (1.0, 0.0) : (0.0, 1.0));
+  return _shaped(d, gx, gy, px, py);
+}
+
+Sdf _shaped(double d, double gx, double gy, double px, double py) {
+  final length = _length(gx, gy);
+  return length > 0 ? Sdf(d, gx / length * _sign(px), gy / length * _sign(py)) : Sdf(d, 0, 0);
+}
+
+Sdf sdfEllipse(double px, double py, double rx, double ry) {
+  rx = math.max(rx, 1e-4);
+  ry = math.max(ry, 1e-4);
+  final k1 = _length(px / rx, py / ry);
+  final gx = px / (rx * rx), gy = py / (ry * ry);
+  final k2 = _length(gx, gy);
+  final d = (k1 * (k1 - 1)) / math.max(k2, 1e-4);
+  return k2 > 0 ? Sdf(d, gx / k2, gy / k2) : Sdf(d, 0, 0);
+}
+
+Sdf shapeSdfWithNormal(MirrorShape s, double x, double y) {
+  final px = x - s.cx, py = y - s.cy;
+  return switch (s.type) {
+    1 => sdfSquircle(px, py, s.width / 2, s.height / 2, s.radius),
+    2 => sdfEllipse(px, py, s.width / 2, s.height / 2),
+    3 => sdfRRect(px, py, s.width / 2, s.height / 2, s.radius),
+    _ => const Sdf(1e9, 0, 0),
+  };
+}
+
+double shapeSdf(MirrorShape s, double x, double y) => shapeSdfWithNormal(s, x, y).d;
+
+Sdf angleSmoothUnion(Sdf a, Sdf b, double k) {
+  final h = math.max(k - (a.d - b.d).abs(), 0.0) / k;
+  final w = (1 - (a.nx * b.nx + a.ny * b.ny)) * 0.5;
+  final near = a.d < b.d ? a : b, far = a.d < b.d ? b : a;
+  final t = h * w * 0.5;
+  final gx = near.nx + (far.nx - near.nx) * t, gy = near.ny + (far.ny - near.ny) * t;
+  final length = _length(gx, gy);
+  return length > 1e-6 ? Sdf(near.d - k * 0.25 * h * h * w, gx / length, gy / length) : Sdf(near.d - k * 0.25 * h * h * w, near.nx, near.ny);
+}
+
+Sdf sceneSdfWithNormal(List<MirrorShape> shapes, double x, double y, double blend) {
+  var result = shapeSdfWithNormal(shapes.first, x, y);
+  for (final shape in shapes.skip(1)) {
+    result = angleSmoothUnion(result, shapeSdfWithNormal(shape, x, y), blend);
+  }
+  return result;
+}
+
+double sceneSdf(List<MirrorShape> shapes, double x, double y, double blend) {
+  if (shapes.isEmpty) return 1e9;
+  if (blend <= 0) {
+    var result = shapeSdf(shapes.first, x, y);
+    for (final shape in shapes.skip(1)) {
+      result = math.min(result, shapeSdf(shape, x, y));
+    }
+    return result;
+  }
+  return sceneSdfWithNormal(shapes, x, y, blend).d;
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_spacing_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_spacing_test.dart
new file mode 100644
index 0000000000000000000000000000000000000000..c1bd1e307ec60251d9a7bfe37caf9783adc496fb
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_spacing_test.dart
@@ -0,0 +1,174 @@
+import 'package:flutter/material.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+import 'package:ios_liquid_glass/src/shaders.dart';
+
+class _Spaced extends StatefulWidget {
+  const _Spaced({required this.spacing, this.scope, this.reduceMotion = false, this.ticking = true});
+
+  final double spacing;
+  final GlassAnimation? scope;
+  final bool reduceMotion;
+  final bool ticking;
+
+  @override
+  State<_Spaced> createState() => _SpacedState();
+}
+
+class _SpacedState extends State<_Spaced> {
+  late double spacing = widget.spacing;
+
+  void set(double value) => setState(() => spacing = value);
+
+  @override
+  Widget build(BuildContext context) {
+    Widget child = GlassEffectContainer(
+      spacing: spacing,
+      child: const Row(
+        mainAxisSize: MainAxisSize.min,
+        children: [
+          GlassEffect(shape: GlassShape.circle(), child: SizedBox.square(dimension: 80)),
+          GlassEffect(shape: GlassShape.circle(), child: SizedBox.square(dimension: 80)),
+        ],
+      ),
+    );
+    final scope = widget.scope;
+    if (scope != null) child = GlassAnimationScope(animation: scope, child: child);
+    return MaterialApp(
+      home: MediaQuery(
+        data: MediaQueryData(disableAnimations: widget.reduceMotion),
+        child: TickerMode(enabled: widget.ticking, child: Center(child: child)),
+      ),
+    );
+  }
+}
+
+double _spacing(WidgetTester tester) {
+  final group = tester.widget<LiquidGlassBlendGroup>(find.byType(LiquidGlassBlendGroup));
+  return group.blendMotion?.value ?? group.blend;
+}
+
+_SpacedState _state(WidgetTester tester) => tester.state<_SpacedState>(find.byType(_Spaced));
+
+const Duration _frame = Duration(milliseconds: 16);
+
+void main() {
+  isLocalTest = true;
+  tearDown(debugResetGlassAnimation);
+
+  test('a container blends at native default spacing, 8 pt', () {
+    expect(const GlassEffectContainer(child: SizedBox()).spacing, 8);
+  });
+
+  testWidgets('a container draws its glass at the spacing it is given, from the first frame', (tester) async {
+    await tester.pumpWidget(const _Spaced(spacing: 40));
+    expect(_spacing(tester), 40);
+    await tester.pumpWidget(MaterialApp(home: Center(child: GlassEffectContainer(child: const GlassEffect(child: SizedBox.square(dimension: 80))))));
+    expect(_spacing(tester), 8);
+  });
+
+  testWidgets('a spacing change springs with the default spring, on the container ticker, with no rebuild', (tester) async {
+    await tester.pumpWidget(const _Spaced(spacing: 40));
+    _state(tester).set(0);
+    await tester.pump();
+    expect(_spacing(tester), 40);
+    final builds = tester.widget<LiquidGlassBlendGroup>(find.byType(LiquidGlassBlendGroup));
+    final expected = GlassAnimation.defaultSpring.simulate(40, 0, 0);
+    var elapsed = 0;
+    for (final step in [50, 50, 100, 200]) {
+      await tester.pump(Duration(milliseconds: step));
+      elapsed += step;
+      expect(_spacing(tester), closeTo(expected.x(elapsed / 1000), 1e-9), reason: '$elapsed ms');
+    }
+    expect(identical(tester.widget<LiquidGlassBlendGroup>(find.byType(LiquidGlassBlendGroup)), builds), isTrue);
+    await tester.pumpAndSettle();
+    expect(_spacing(tester), 0);
+  });
+
+  testWidgets('withGlassAnimation picks the spacing animation first, then GlassAnimationScope, then the default', (tester) async {
+    await tester.pumpWidget(const _Spaced(spacing: 40, scope: GlassAnimation.bouncy));
+    withGlassAnimation(GlassAnimation.snappy, () => _state(tester).set(0));
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 120));
+    expect(_spacing(tester), closeTo(GlassAnimation.snappy.simulate(40, 0, 0).x(0.12), 1e-9));
+    await tester.pumpAndSettle();
+    _state(tester).set(40);
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 120));
+    expect(_spacing(tester), closeTo(GlassAnimation.bouncy.simulate(0, 40, 0).x(0.12), 1e-9));
+    await tester.pumpAndSettle();
+  });
+
+  testWidgets('GlassAnimation.none, from withGlassAnimation or a scope, changes the spacing at once', (tester) async {
+    await tester.pumpWidget(const _Spaced(spacing: 40));
+    withGlassAnimation(GlassAnimation.none, () => _state(tester).set(0));
+    await tester.pump();
+    expect(_spacing(tester), 0);
+    await tester.pumpWidget(const _Spaced(spacing: 0, scope: GlassAnimation.none));
+    _state(tester).set(24);
+    await tester.pump();
+    expect(_spacing(tester), 24);
+  });
+
+  testWidgets('a spacing retargeted mid-flight keeps its value and velocity', (tester) async {
+    await tester.pumpWidget(const _Spaced(spacing: 40));
+    _state(tester).set(0);
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 100));
+    final first = GlassAnimation.defaultSpring.simulate(40, 0, 0);
+    _state(tester).set(20);
+    await tester.pump(const Duration(milliseconds: 50));
+    expect(_spacing(tester), closeTo(first.x(0.15), 1e-9));
+    final second = GlassAnimation.defaultSpring.simulate(first.x(0.15), 20, first.dx(0.15));
+    await tester.pump(const Duration(milliseconds: 80));
+    expect(_spacing(tester), closeTo(second.x(0.08), 1e-9));
+    await tester.pumpAndSettle();
+    expect(_spacing(tester), 20);
+  });
+
+  testWidgets('a spacing the app changes on consecutive frames follows its value, and a single change after springs again', (tester) async {
+    await tester.pumpWidget(const _Spaced(spacing: 40));
+    _state(tester).set(38);
+    await tester.pump(_frame);
+    expect(_spacing(tester), 40);
+    for (var value = 36.0; value >= 20; value -= 2) {
+      _state(tester).set(value);
+      await tester.pump(_frame);
+      expect(_spacing(tester), value);
+    }
+    await tester.pump(_frame);
+    await tester.pump(const Duration(milliseconds: 100));
+    _state(tester).set(0);
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 100));
+    expect(_spacing(tester), closeTo(GlassAnimation.defaultSpring.simulate(20, 0, 0).x(0.1), 1e-9));
+    await tester.pumpAndSettle();
+  });
+
+  testWidgets('inside withGlassAnimation, spacing changes on consecutive frames all spring', (tester) async {
+    await tester.pumpWidget(const _Spaced(spacing: 40));
+    withGlassAnimation(GlassAnimation.smooth, () => _state(tester).set(30));
+    await tester.pump(_frame);
+    withGlassAnimation(GlassAnimation.smooth, () => _state(tester).set(20));
+    await tester.pump(_frame);
+    expect(_spacing(tester), greaterThan(30));
+    await tester.pumpAndSettle();
+    expect(_spacing(tester), 20);
+  });
+
+  testWidgets('under Reduce Motion the spacing springs as the drawn rects do', (tester) async {
+    await tester.pumpWidget(const _Spaced(spacing: 40, reduceMotion: true));
+    _state(tester).set(0);
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 100));
+    expect(_spacing(tester), closeTo(GlassAnimation.defaultSpring.simulate(40, 0, 0).x(0.1), 1e-9));
+    await tester.pumpAndSettle();
+  });
+
+  testWidgets('a container whose ticker is muted changes its spacing at once', (tester) async {
+    await tester.pumpWidget(const _Spaced(spacing: 40, ticking: false));
+    _state(tester).set(0);
+    await tester.pump();
+    expect(_spacing(tester), 0);
+  });
+}
diff --git a/packages/mobile/test/core/widgets/glass/glass_scope_test.dart b/packages/mobile/test/core/widgets/glass/glass_scope_test.dart
new file mode 100644
index 0000000000000000000000000000000000000000..a2c31257d8b7aec3517b1b12c6b426a689f4d0b3
--- /dev/null
+++ b/packages/mobile/test/core/widgets/glass/glass_scope_test.dart
@@ -0,0 +1,22 @@
+import 'package:flutter/material.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+import 'package:operator_mobile/core/widgets/glass/glass_scope.dart';
+import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
+
+void main() {
+  testWidgets('a glass scope keeps the 20 pt spacing its toolbars were drawn with before the native default of 8', (tester) async {
+    await tester.pumpWidget(
+      const MaterialApp(
+        home: Center(
+          child: GlassScope(
+            variant: GlassVariant.regular,
+            size: 44,
+            child: GlassSurface(kind: GlassShapeKind.capsule, size: 44, child: SizedBox(width: 44, height: 44)),
+          ),
+        ),
+      ),
+    );
+    expect(tester.widget<GlassEffectContainer>(find.byType(GlassEffectContainer)).spacing, 20);
+  });
+}
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t04-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/geometry/angle_union_test.dart test/motion/glass_spacing_test.dart` => FAIL

Expected output ends with:

```text
test/motion/glass_spacing_test.dart:48:16: Error: The getter 'blendMotion' isn't defined for the type 'LiquidGlassBlendGroup'.
```

RUN[t04-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/spacing_scenes_test.dart` => FAIL

Expected output ends with:

```text
test/spacing_scenes_test.dart:77:35: Error: Undefined name 'SpacingScenes'.
```

RUN[t04-app-red]: `cd packages/mobile && flutter test --no-pub test/core/widgets/glass/glass_scope_test.dart` => PASS

Expected output ends with:

```text
+1: All tests passed!
```

Expected: the package and example tests fail (missing symbols and values); the app's `glass_scope_test` **passes** before the implementation, by design: it pins that `GlassScope` keeps 20 pt, which was the package default until this task changes it, and it must still pass after.

- [ ] **Step 3: Apply the implementation.**

Patch `t04-impl` (`4e32718e4..3269b9580`, 10 files):

```diff
diff --git a/packages/mobile/lib/core/widgets/glass/glass_scope.dart b/packages/mobile/lib/core/widgets/glass/glass_scope.dart
index a0c84bd7d74a57720bc6ba02322c55e1d2e6b487..71bf83b14ff1bbc869cbb462097c2584e5750558 100644
--- a/packages/mobile/lib/core/widgets/glass/glass_scope.dart
+++ b/packages/mobile/lib/core/widgets/glass/glass_scope.dart
@@ -11,5 +11,5 @@ class GlassScope extends StatelessWidget {
 
   @override
   Widget build(BuildContext context) =>
-      GlassEffectContainer(glass: glassForVariant(context, variant), side: size, child: child);
+      GlassEffectContainer(spacing: 20, glass: glassForVariant(context, variant), side: size, child: child);
 }
diff --git a/packages/mobile/packages/ios_liquid_glass/FORK.md b/packages/mobile/packages/ios_liquid_glass/FORK.md
index 9f972b1e9af3d917a4e3ee18635f35181e5e6e13..4c940d97f275de632a20a8a70e76847522d754ac 100644
--- a/packages/mobile/packages/ios_liquid_glass/FORK.md
+++ b/packages/mobile/packages/ios_liquid_glass/FORK.md
@@ -89,6 +89,12 @@ The package was renamed from `liquid_glass_renderer` to `ios_liquid_glass`, with
 - A rendered geometry cache (`RenderedGeometryCache`) keeps its picture and rasterizes its image at the sub-pixel phase it is drawn at (`matteAt`); `LiquidGlassRenderObject` draws a cached matte under a pure translation on the pixel grid at that phase (`drawMatteAt`), so glass at a fractional position draws its rim where the uncached picture does. Upstream drew the image rasterized on its own grid with nearest sampling at the fractional offset, up to half a pixel off. Other transforms draw the phase-zero image as before.
 - `requiresGeometryRebuild(null)` is true, and `RenderLiquidGlassGeometry.attach` and `LiquidGlassRenderObject.attach` re-apply the settings against the kept baseline (refreshing the uniforms) instead of clearing it.
 
+## ios_liquid_glass 0.1.0, project 2B.2 (merge and split)
+
+- `sdf.glsl` replaces upstream's quadratic `smoothUnion` with `angleSmoothUnion`, a quadratic smooth-min with k = blend whose correction is weighted by (1 − n_a · n_b) / 2, the angle between the two shapes' unit gradients. Each shape's gradient is analytic (`getShapeSDFGrad`); the fold carries the blended field's gradient, neglecting the change of the angle weight itself. A blend of 0 is still the plain minimum. `sceneSDF`'s unrolled path for one to four shapes is gone; every count runs the same loop.
+- `LiquidGlassBlendGroup` takes an optional internal `blendMotion` (a `ValueListenable<double>`); `RenderLiquidGlassBlendGroup` listens to it and takes its value as `blend`, so a container's spacing animates with no rebuild. Its own `blend` default stays 20.
+- `GlassEffectContainer.spacing` defaults to 8 pt, native's default, and animates through the container's coordinator.
+
 Record every later change to `lib/` in this file.
 
 Upstream: https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer
diff --git a/packages/mobile/packages/ios_liquid_glass/README.md b/packages/mobile/packages/ios_liquid_glass/README.md
index 31cbf09ad22d3e44c2dae335447795e7ba008b41..b918858c37acbd3e1b2438d9e83a25204b23460c 100644
--- a/packages/mobile/packages/ios_liquid_glass/README.md
+++ b/packages/mobile/packages/ios_liquid_glass/README.md
@@ -31,7 +31,7 @@ The glass is drawn behind the child, in the shape you choose, sized by the child
 | `.glassEffect(.identity)` | `GlassEffect(glass: Glass.identity, ...)` |
 | `.glassEffect(.regular.interactive())` | `Glass.regular.interactive()` (the press arrives in a later version) |
 | `.glassEffect(in: .circle)`, `.rect(cornerRadius:)`, capsule | `GlassShape.circle()`, `GlassShape.rect(r)`, `GlassShape.superellipse(r)`, `GlassShape.capsule()` |
-| `GlassEffectContainer(spacing:)` | `GlassEffectContainer(spacing: 20, child: ...)` |
+| `GlassEffectContainer(spacing:)`, `GlassEffectContainer()` | `GlassEffectContainer(spacing: 40, child: ...)`, `GlassEffectContainer(child: ...)` (native default, 8 pt) |
 | `.glassEffectTransition(.materialize)`, `.identity` | `GlassEffect(transition: GlassEffectTransition.materialize)`, `GlassEffectTransition.identity` |
 | `Animation.default`, `.snappy`, `.bouncy`, `.smooth` | `GlassAnimation.defaultSpring`, `.snappy`, `.bouncy`, `.smooth` |
 | `.spring(duration:bounce:)`, `.spring(response:dampingFraction:)` | `GlassAnimation.spring(duration:, bounce:)`, `GlassAnimation.dampedSpring(response:, dampingFraction:)` |
@@ -61,7 +61,9 @@ What animates:
 
 The timing is native's, measured on the iOS 27 simulator. Appearing glass follows the animation's spring and overshoots where the spring does, scaled by a fitted gain (0.44 for `snappy`, 0.5 for `bouncy`; the default spring does not overshoot, so it needs none); `lab.py fitvis` fits the gain on native's overshoot peak against the overshoot Flutter's own frames show, read through a visibility table that extends above full visibility, and the table has room for a gain per appearance, used only when the fit shows a consistent difference between light and dark (the shipped table uses one gain for both). Disappearing glass follows the spring's remainder to a fitted power (3.1 for the default, 2.75 for `snappy`, 2.7 for `bouncy`), which is why removal is about twice as fast as insertion. An app's own spring uses the preset nearest its damping. The backdrop blur ramps linearly with visibility (the fitted power is 1), the exponent that best matches native's half-way sharpness and its per-backdrop progress together. The numbers ship as a table, `ios27_motion.dart`, written by the lab. Under Reduce Motion native keeps materialize's timing and blur and overshoots more, so glass that begins to appear under Reduce Motion takes a second fitted gain (0.6 for `snappy`, 0.8 for `bouncy`).
 
-Each glass resolves its material (tone, frost, edge light and shadow) from its drawn size at layout and on every animated frame, so a glass growing from 44 to 200 pt changes its shadow as it grows. Container spacing does not animate yet.
+Each glass resolves its material (tone, frost, edge light and shadow) from its drawn size at layout and on every animated frame, so a glass growing from 44 to 200 pt changes its shadow as it grows.
+
+A container's glass blends with its neighbours as native's does: glass closer than `spacing` deforms toward its neighbour, and joins it into one shape when closer than about half of `spacing`. The shape is a smooth union weighted by the angle between the two shapes' edges, which matches native's necks and bulges on the iOS 27 simulator for spacings from 4 to 80 pt. Shapes blend by their drawn rects, so glass that springs toward or away from its neighbour joins and splits as it moves. A `spacing` change animates like a move: with `withGlassAnimation`'s animation, the nearest `GlassAnimationScope` or the default spring, and a spacing the app changes on consecutive frames follows its value.
 
 ### Theme
 
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_registry.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_registry.dart
index 9cb3ea814f1a46dca6ba0ceb2a883dc104fc898d..25cc8269b2b32858379caf11bf358d4d9ac9fb63 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_registry.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/glass_lab_registry.dart
@@ -6,9 +6,10 @@ import 'glass_lab_marker.dart';
 import 'scenes/material_scenes.dart';
 import 'scenes/motion_scenes.dart';
 import 'scenes/perf_scenes.dart';
+import 'scenes/spacing_scenes.dart';
 
 sealed class GlassLabRegistry {
-  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {...MaterialScenes.scenes, ...MotionScenes.scenes};
+  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {...MaterialScenes.scenes, ...MotionScenes.scenes, ...SpacingScenes.scenes};
   static final Map<String, Widget Function(GlassLabLaunch launch)> tools = {...PerfScenes.scenes, ...MotionScenes.tools};
 
   static Widget build(GlassLabLaunch launch) {
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
index a1aa9ea8fce99483fa0ddbaa64bada3466c15e18..e09739135578ef3bcebd4f62a25907a102cfd258 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
@@ -71,26 +71,6 @@ sealed class MaterialScenes {
         ),
       ],
     ),
-    'material.merge': (launch) => LabCentered(
-      backdrop: launch.backdrop,
-      bottom: const Row(
-        mainAxisSize: MainAxisSize.min,
-        children: [LabButton(title: 'Merge', id: 'merge'), SizedBox(width: 24), LabButton(title: 'Split', id: 'split')],
-      ),
-      children: const [
-        GlassEffectContainer(
-          spacing: 40,
-          child: Row(
-            mainAxisSize: MainAxisSize.min,
-            children: [
-              LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
-              SizedBox(width: 80),
-              LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
-            ],
-          ),
-        ),
-      ],
-    ),
     'material.union': (launch) => LabCentered(
       backdrop: launch.backdrop,
       children: [
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/spacing_scenes.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/spacing_scenes.dart
new file mode 100644
index 0000000000000000000000000000000000000000..21f0075b5d9ebd45374f65bd02eb5044b8fc8a38
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/spacing_scenes.dart
@@ -0,0 +1,183 @@
+import 'package:flutter/material.dart';
+import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+
+import '../glass_lab_backdrop.dart';
+import '../glass_lab_launch.dart';
+import 'lab_parts.dart';
+
+sealed class SpacingScenes {
+  static const Map<String, List<double>> gaps = {
+    'material.spacing.default.a': [0, 4, 8, 12],
+    'material.spacing.default.b': [16, 20, 24, 32],
+    'material.spacing.default.c': [40, 48, 60],
+    'material.spacing.40.a': [0, 4, 8, 12],
+    'material.spacing.40.b': [16, 20, 24, 32],
+    'material.spacing.40.c': [40, 48, 60],
+    'material.spacing.4.a': [0, 4, 8, 12],
+    'material.spacing.6.a': [0, 4, 8, 12],
+    'material.spacing.8.a': [0, 4, 8, 12],
+    'material.spacing.10.a': [0, 4, 8, 12],
+    'material.spacing.12.a': [0, 4, 8, 12],
+    'material.spacing.16.a': [0, 4, 8, 12],
+    'material.spacing.20.a': [0, 4, 8, 12],
+    'material.spacing.80.a': [0, 4, 8, 12],
+    'material.spacing.default.d': [2, 5, 6, 7],
+    'material.spacing.20.b': [9, 10, 11, 14],
+    'material.spacing.20.c': [16, 18, 24, 32],
+    'material.spacing.40.d': [18, 19, 21, 22],
+    'material.spacing.40.e': [28, 36, 44, 52],
+    'material.spacing.80.b': [16, 24, 32, 36],
+    'material.spacing.80.c': [38, 40, 42, 44],
+    'material.spacing.80.d': [48, 56, 64, 72],
+    'material.spacing.80.e': [80, 88, 96],
+  };
+
+  static final Map<String, double?> spacing = {
+    for (final id in gaps.keys) id: switch (id.split('.')[2]) {
+      'default' => null,
+      final value => double.parse(value),
+    },
+  };
+
+  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
+    for (final MapEntry(key: id, value: gaps) in gaps.entries)
+      id: (launch) => SpacingScene(backdrop: launch.backdrop, gaps: gaps, spacing: spacing[id]),
+    'material.merge': (launch) => MergeScene(backdrop: launch.backdrop),
+  };
+}
+
+class PixelCenter extends SingleChildLayoutDelegate {
+  const PixelCenter(this.devicePixelRatio);
+
+  final double devicePixelRatio;
+
+  double _snap(double points) => (points * devicePixelRatio + 0.5).floorToDouble() / devicePixelRatio;
+
+  @override
+  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();
+
+  @override
+  Offset getPositionForChild(Size size, Size childSize) =>
+      Offset(_snap((size.width - childSize.width) / 2), _snap((size.height - childSize.height) / 2));
+
+  @override
+  bool shouldRelayout(PixelCenter oldDelegate) => oldDelegate.devicePixelRatio != devicePixelRatio;
+}
+
+class SpacingPair extends StatelessWidget {
+  const SpacingPair({super.key, required this.gap, this.spacing});
+
+  final double gap;
+  final double? spacing;
+
+  @override
+  Widget build(BuildContext context) {
+    final circles = Row(
+      mainAxisSize: MainAxisSize.min,
+      children: [
+        const LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
+        SizedBox(width: gap),
+        const LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
+      ],
+    );
+    final spacing = this.spacing;
+    return spacing == null ? GlassEffectContainer(child: circles) : GlassEffectContainer(spacing: spacing, child: circles);
+  }
+}
+
+class SpacingScene extends StatelessWidget {
+  const SpacingScene({super.key, required this.backdrop, required this.gaps, this.spacing});
+
+  final String backdrop;
+  final List<double> gaps;
+  final double? spacing;
+
+  @override
+  Widget build(BuildContext context) {
+    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
+    return Stack(
+      children: [
+        Positioned.fill(child: GlassLabBackdrop(id: backdrop)),
+        SafeArea(
+          child: CustomSingleChildLayout(
+            delegate: const WholePointCenter(),
+            child: Column(
+              mainAxisSize: MainAxisSize.min,
+              children: [
+                for (final (index, gap) in gaps.indexed) ...[
+                  if (index > 0) const SizedBox(height: 100),
+                  SizedBox(
+                    width: double.infinity,
+                    height: 80,
+                    child: CustomSingleChildLayout(delegate: PixelCenter(pixelRatio), child: SpacingPair(gap: gap, spacing: spacing)),
+                  ),
+                ],
+              ],
+            ),
+          ),
+        ),
+      ],
+    );
+  }
+}
+
+class MergeScene extends StatefulWidget {
+  const MergeScene({super.key, required this.backdrop});
+
+  final String backdrop;
+
+  @override
+  State<MergeScene> createState() => _MergeSceneState();
+}
+
+class _MergeSceneState extends State<MergeScene> {
+  bool _merged = false;
+
+  void _set(bool merged) => withGlassAnimation(GlassAnimation.defaultSpring, () => setState(() => _merged = merged));
+
+  @override
+  Widget build(BuildContext context) {
+    return Stack(
+      children: [
+        Positioned.fill(child: GlassLabBackdrop(id: widget.backdrop)),
+        SafeArea(
+          child: Stack(
+            children: [
+              Positioned.fill(
+                child: CustomSingleChildLayout(
+                  delegate: const WholePointCenter(),
+                  child: GlassEffectContainer(
+                    spacing: 40,
+                    child: Row(
+                      mainAxisSize: MainAxisSize.min,
+                      children: [
+                        const LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
+                        SizedBox(width: _merged ? 0 : 80),
+                        const LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
+                      ],
+                    ),
+                  ),
+                ),
+              ),
+              Positioned(
+                left: 0,
+                right: 0,
+                bottom: 120,
+                child: Center(
+                  child: Row(
+                    mainAxisSize: MainAxisSize.min,
+                    children: [
+                      LabButton(title: 'Merge', id: 'merge', onTap: () => _set(true)),
+                      const SizedBox(width: 24),
+                      LabButton(title: 'Split', id: 'split', onTap: () => _set(false)),
+                    ],
+                  ),
+                ),
+              ),
+            ],
+          ),
+        ),
+      ],
+    );
+  }
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/assets/shaders/sdf.glsl b/packages/mobile/packages/ios_liquid_glass/lib/assets/shaders/sdf.glsl
index eefbc63a4993bf3f93fc8c2b8974ba8d95498b4b..5b7c71791b7fc0f941d260e8ac95bc0b11e3bd6c 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/assets/shaders/sdf.glsl
+++ b/packages/mobile/packages/ios_liquid_glass/lib/assets/shaders/sdf.glsl
@@ -41,12 +41,51 @@ float sdfEllipse(vec2 p, vec2 r) {
     return (k1 * (k1 - 1.0)) / max(k2, 1e-4);
 }
 
-float smoothUnion(float d1, float d2, float k) {
-    if (k <= 0.0) {
-        return min(d1, d2);
-    }
-    float e = max(k - abs(d1 - d2), 0.0);
-    return min(d1, d2) - e * e * 0.25 / k;
+vec3 shapedGradient(float d, vec2 g, vec2 p) {
+    float len = length(g);
+    return vec3(d, len > 0.0 ? g / len * sign(p) : vec2(0.0));
+}
+
+vec3 sdfRRectGrad(vec2 p, vec2 b, float r) {
+    float shortest = min(b.x, b.y);
+    r = min(r, shortest);
+    vec2 q = abs(p) - b + r;
+    vec2 m = max(q, 0.0);
+    float d = min(max(q.x, q.y), 0.0) + length(m) - r;
+    vec2 axis = q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
+    return shapedGradient(d, (m.x > 0.0 || m.y > 0.0) ? m : axis, p);
+}
+
+vec3 sdfSquircleGrad(vec2 p, vec2 b, float r) {
+    float shortest = min(b.x, b.y);
+    r = min(r * SQUIRCLE_EXTENT, shortest);
+    vec2 q = abs(p) - b + r;
+    vec2 m = max(q, 0.0);
+    float corner = pow(pow(m.x, SQUIRCLE_EXPONENT) + pow(m.y, SQUIRCLE_EXPONENT), 1.0 / SQUIRCLE_EXPONENT);
+    float d = min(max(q.x, q.y), 0.0) + corner - r;
+    vec2 axis = q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
+    vec2 slope = vec2(pow(m.x, SQUIRCLE_EXPONENT - 1.0), pow(m.y, SQUIRCLE_EXPONENT - 1.0));
+    return shapedGradient(d, (m.x > 0.0 || m.y > 0.0) ? slope : axis, p);
+}
+
+vec3 sdfEllipseGrad(vec2 p, vec2 r) {
+    r = max(r, 1e-4);
+    vec2 invR = 1.0 / r;
+    vec2 pInvR2 = p * invR * invR;
+    float k1 = length(p * invR);
+    float k2 = length(pInvR2);
+    float d = (k1 * (k1 - 1.0)) / max(k2, 1e-4);
+    return vec3(d, k2 > 0.0 ? pInvR2 / k2 : vec2(0.0));
+}
+
+vec3 angleSmoothUnion(vec3 a, vec3 b, float k) {
+    float h = max(k - abs(a.x - b.x), 0.0) / k;
+    float w = (1.0 - dot(a.yz, b.yz)) * 0.5;
+    vec3 near = a.x < b.x ? a : b;
+    vec3 far = a.x < b.x ? b : a;
+    vec2 g = mix(near.yz, far.yz, h * w * 0.5);
+    float len = length(g);
+    return vec3(near.x - k * 0.25 * h * h * w, len > 1e-6 ? g / len : near.yz);
 }
 
 float getShapeSDF(float type, vec2 p, vec2 center, vec2 size, float r) {
@@ -62,6 +101,19 @@ float getShapeSDF(float type, vec2 p, vec2 center, vec2 size, float r) {
     return 1e9; // none
 }
 
+vec3 getShapeSDFGrad(float type, vec2 p, vec2 center, vec2 size, float r) {
+    if (type == 1.0) {
+        return sdfSquircleGrad(p - center, size / 2.0, r);
+    }
+    if (type == 2.0) {
+        return sdfEllipseGrad(p - center, size / 2.0);
+    }
+    if (type == 3.0) {
+        return sdfRRectGrad(p - center, size / 2.0, r);
+    }
+    return vec3(1e9, 0.0, 0.0);
+}
+
 float getShapeSDFFromArray(int index, vec2 p, float shapeData[MAX_SHAPES * 6]) {
     int baseIndex = index * 6;
     float type = shapeData[baseIndex];
@@ -72,37 +124,31 @@ float getShapeSDFFromArray(int index, vec2 p, float shapeData[MAX_SHAPES * 6]) {
     return getShapeSDF(type, p, center, size, cornerRadius);
 }
 
+vec3 getShapeSDFGradFromArray(int index, vec2 p, float shapeData[MAX_SHAPES * 6]) {
+    int baseIndex = index * 6;
+    vec2 center = vec2(shapeData[baseIndex + 1], shapeData[baseIndex + 2]);
+    vec2 size = vec2(shapeData[baseIndex + 3], shapeData[baseIndex + 4]);
+    return getShapeSDFGrad(shapeData[baseIndex], p, center, size, shapeData[baseIndex + 5]);
+}
+
 float sceneSDF(vec2 p, int numShapes, float shapeData[MAX_SHAPES * 6], float blend) {
     if (numShapes == 0) {
         return 1e9;
     }
     
-    float result = getShapeSDFFromArray(0, p, shapeData);
-    
-    // Optimized: unroll for common cases (1-4 shapes), use loop for 5+ shapes
-    if (numShapes <= 4) {
-        // Fully unrolled for 1-4 shapes (covers 90%+ of use cases)
-        if (numShapes >= 2) {
-            float shapeSDF = getShapeSDFFromArray(1, p, shapeData);
-            result = smoothUnion(result, shapeSDF, blend);
-        }
-        if (numShapes >= 3) {
-            float shapeSDF = getShapeSDFFromArray(2, p, shapeData);
-            result = smoothUnion(result, shapeSDF, blend);
-        }
-        if (numShapes >= 4) {
-            float shapeSDF = getShapeSDFFromArray(3, p, shapeData);
-            result = smoothUnion(result, shapeSDF, blend);
-        }
-    } else {
-        // Dynamic loop for 5+ shapes (uncommon cases)
+    if (blend <= 0.0) {
+        float result = getShapeSDFFromArray(0, p, shapeData);
         for (int i = 1; i < min(numShapes, MAX_SHAPES); i++) {
-            float shapeSDF = getShapeSDFFromArray(i, p, shapeData);
-            result = smoothUnion(result, shapeSDF, blend);
+            result = min(result, getShapeSDFFromArray(i, p, shapeData));
         }
+        return result;
     }
     
-    return result;
+    vec3 blended = getShapeSDFGradFromArray(0, p, shapeData);
+    for (int i = 1; i < min(numShapes, MAX_SHAPES); i++) {
+        blended = angleSmoothUnion(blended, getShapeSDFGradFromArray(i, p, shapeData), blend);
+    }
+    return blended.x;
 }
 
 // Calculate 3D normal using derivatives (shader-specific normal calculation)
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart
index beb868fa6701c2c2495c2beed500ee8d53396006..17d6a1d87a9074133ed8fb475ee50ee79ebf2c87 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart
@@ -4,13 +4,14 @@ import 'package:ios_liquid_glass/src/api/glass.dart';
 import 'package:ios_liquid_glass/src/api/glass_material_context.dart';
 import 'package:ios_liquid_glass/src/liquid_glass_blend_group.dart';
 import 'package:ios_liquid_glass/src/liquid_glass_settings.dart';
+import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
 import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
 import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
 import 'package:ios_liquid_glass/src/rendering/liquid_glass_layer.dart';
 import 'package:meta/meta.dart';
 
 class GlassEffectContainer extends StatefulWidget {
-  const GlassEffectContainer({super.key, this.spacing = 20, this.glass = Glass.regular, this.side = 88, required this.child});
+  const GlassEffectContainer({super.key, this.spacing = 8, this.glass = Glass.regular, this.side = 88, required this.child});
 
   final double spacing;
   final Glass glass;
@@ -61,6 +62,7 @@ class _GlassEffectContainerState extends State<GlassEffectContainer> with Single
 
   @override
   Widget build(BuildContext context) {
+    _coordinator.spacingTo(widget.spacing, scope: GlassAnimationScope.maybeOf(context));
     return ListenableBuilder(
       listenable: GlassAccessibility.platform,
       builder: (context, _) {
@@ -72,6 +74,7 @@ class _GlassEffectContainerState extends State<GlassEffectContainer> with Single
             settings: settings,
             child: LiquidGlassBlendGroup(
               blend: widget.spacing,
+              blendMotion: _coordinator.spacing,
               child: GlassContainerScope(
                 glass: widget.glass,
                 settings: settings,
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
index 1859c178c9b4d30d553281651b9784633cbe0f17..19ed9049bc665d1b4776b2b857f4f26369fcc4eb 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
@@ -1,3 +1,5 @@
+import 'package:flutter/foundation.dart';
+import 'package:flutter/rendering.dart';
 import 'package:flutter/widgets.dart';
 import 'package:flutter_shaders/flutter_shaders.dart';
 import 'package:ios_liquid_glass/ios_liquid_glass.dart';
@@ -8,7 +10,6 @@ import 'package:ios_liquid_glass/src/liquid_glass_render_scope.dart';
 import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
 import 'package:ios_liquid_glass/src/rendering/liquid_glass_render_object.dart';
 import 'package:ios_liquid_glass/src/shaders.dart';
-import 'package:meta/meta.dart';
 
 /// A widget that groups multiple liquid glass shapes for blending.
 ///
@@ -21,6 +22,7 @@ class LiquidGlassBlendGroup extends StatefulWidget {
   const LiquidGlassBlendGroup({
     required this.child,
     this.blend = 20.0,
+    this.blendMotion,
     super.key,
   });
 
@@ -30,6 +32,9 @@ class LiquidGlassBlendGroup extends StatefulWidget {
   /// blend.
   final double blend;
 
+  @internal
+  final ValueListenable<double>? blendMotion;
+
   /// The child widget containing liquid glass shapes.
   final Widget child;
 
@@ -82,6 +87,7 @@ class _LiquidGlassBlendGroupState extends State<LiquidGlassBlendGroup> {
       child: ShaderBuilder(
         (context, shader, child) => _RawLiquidGlassBlendGroup(
           blend: widget.blend,
+          blendMotion: widget.blendMotion,
           shader: shader,
           link: _geometryLink,
           renderLink: InheritedGeometryRenderLink.of(context)!,
@@ -124,12 +130,14 @@ class _RawLiquidGlassBlendGroup extends SingleChildRenderObjectWidget {
     required this.renderLink,
     required this.link,
     required this.settings,
+    this.blendMotion,
     this.visibility,
     this.settingsSource,
     super.child,
   });
 
   final double blend;
+  final ValueListenable<double>? blendMotion;
   final FragmentShader shader;
   final GeometryRenderLink renderLink;
   final GlassGroupLink link;
@@ -145,8 +153,9 @@ class _RawLiquidGlassBlendGroup extends SingleChildRenderObjectWidget {
       geometryShader: shader,
       settings: settings,
       link: link,
-      blend: blend,
+      blend: blendMotion?.value ?? blend,
     )
+      ..blendMotion = blendMotion
       ..visibility = visibility
       ..settingsSource = settingsSource;
   }
@@ -157,7 +166,8 @@ class _RawLiquidGlassBlendGroup extends SingleChildRenderObjectWidget {
     RenderLiquidGlassBlendGroup renderObject,
   ) {
     renderObject
-      ..blend = blend
+      ..blend = blendMotion?.value ?? blend
+      ..blendMotion = blendMotion
       ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
       ..settings = settings
       ..visibility = visibility
@@ -205,6 +215,33 @@ class RenderLiquidGlassBlendGroup extends RenderLiquidGlassGeometry
     markNeedsPaint();
   }
 
+  ValueListenable<double>? _blendMotion;
+  set blendMotion(ValueListenable<double>? value) {
+    if (_blendMotion == value) return;
+    if (attached) _blendMotion?.removeListener(_followBlend);
+    _blendMotion = value;
+    if (attached) value?.addListener(_followBlend);
+    _followBlend();
+  }
+
+  void _followBlend() {
+    final motion = _blendMotion;
+    if (motion != null) blend = motion.value;
+  }
+
+  @override
+  void attach(PipelineOwner owner) {
+    super.attach(owner);
+    _blendMotion?.addListener(_followBlend);
+    _followBlend();
+  }
+
+  @override
+  void detach() {
+    _blendMotion?.removeListener(_followBlend);
+    super.detach();
+  }
+
   void _onLinkUpdate() {
     // One of the shapes might have changed.
     markGeometryNeedsUpdate();
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
index f1974b331f7654af41a8cf112cbe7885e90060e3..6793da200d254f80b7479b554ef6d1b4a1143061 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
@@ -401,9 +401,33 @@ class GlassMotionCoordinator {
   GlassMotionCoordinator? _successor;
   int _structureUntil = -1;
   GlassAnimation? _structureAnimation;
+  final GlassMotionValue spacing = GlassMotionValue(0);
+  GlassSpring? _spacing;
+  int _spacingFrame = -2;
+  Duration? _spacingTime;
 
   Iterable<GlassMember> get members => _members;
 
+  void spacingTo(double target, {GlassAnimation? scope}) {
+    final spring = _spacing;
+    if (spring == null) {
+      _spacing = GlassSpring(target);
+      spacing.value = target;
+      return;
+    }
+    if (spring.target == target) return;
+    final frame = GlassFrame.current, now = _now, last = _spacingTime;
+    final following = _spacingFrame == frame - 1 && now != null && last != null && now - last <= GlassMember.followGap;
+    _spacingFrame = frame;
+    _spacingTime = now;
+    final animation = _disposed || _ticker.muted || (following && pendingGlassAnimation == null)
+        ? GlassAnimation.none
+        : resolveGlassAnimation(scope);
+    spring.animateTo(target, animation, now);
+    spacing.value = spring.value;
+    if (spring.isMoving) _start();
+  }
+
   GlassMotionCoordinator? get ghostOwner => _departing ? _successor : this;
 
   void depart(GlassMotionCoordinator? successor) {
@@ -576,6 +600,11 @@ class GlassMotionCoordinator {
   void _tick(Duration _) {
     final now = SchedulerBinding.instance.currentFrameTimeStamp;
     var moving = false;
+    final spacingSpring = _spacing;
+    if (spacingSpring != null && spacingSpring.isMoving) {
+      moving = spacingSpring.sample(now);
+      spacing.value = spacingSpring.value;
+    }
     for (final member in _members.toList()) {
       if (member._due) moving = member._sample(now) || moving;
     }
@@ -599,6 +628,7 @@ class GlassMotionCoordinator {
   void dispose() {
     _disposed = true;
     _ticker.dispose();
+    spacing.dispose();
     dropGhosts();
     _dropLeaving();
     for (final member in _members) {
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t04-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/geometry/angle_union_test.dart test/motion/glass_spacing_test.dart` => PASS

Expected output ends with:

```text
+16: All tests passed!
```

RUN[t04-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/spacing_scenes_test.dart` => PASS

Expected output ends with:

```text
+4: All tests passed!
```

RUN[t04-app-green]: `cd packages/mobile && flutter test --no-pub test/core/widgets/glass/glass_scope_test.dart` => PASS

Expected output ends with:

```text
+1: All tests passed!
```

- [ ] **Step 5: Gate: package.**

RUN[t04-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t04-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

Expected output ends with:

```text
+171: All tests passed!
```

- [ ] **Step 6: Gate: example.**

RUN[t04-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t04-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

Expected output ends with:

```text
+17: All tests passed!
```

- [ ] **Step 7: Gate: app.**

RUN[t04-gate-app-analyze]: `cd packages/mobile && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t04-gate-app-test]: `cd packages/mobile && flutter test --no-pub` => PASS

Expected output ends with:

```text
+2188: All tests passed!
```

- [ ] **Step 8: Commit.**

```bash
git add -A packages
git commit -m "feat(ios_liquid_glass): angle-weighted smooth union, native default spacing 8, animated spacing, N7 and live merge scenes

Co-Authored-By: <the session's attribution line>"
```

### Task 5: Topology masks that count native glass on stripes and photo, a still mask without the outline, `gap_pt`

**Files:**
- Modify: `tool/glass_lab/harness/track.py` (`topology_mask`, `still_mask`, `gap`), `shapes.py`, `analyze.py`, `metrics.py`
- Test: `tool/glass_lab/harness/tests/{synthetic,test_track,test_shapes}.py`

**Why.** Rulings 2–4. The merge, union and N7 judgements read these masks; the prototype checked them against 120 hand-labelled frames and 141 native N7 takes (`R/topology/`).

- [ ] **Step 1: Add the failing tests.**

Patch `t05-tests` (`3269b9580..6006902f6`, 3 files):

```diff
diff --git a/packages/mobile/tool/glass_lab/harness/tests/synthetic.py b/packages/mobile/tool/glass_lab/harness/tests/synthetic.py
index 778458b9ffccca324c3dc7ba16750f95f1b29423..e6f1854aff3881613d46d7a0fde1eb6be8d56bec 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/synthetic.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/synthetic.py
@@ -55,3 +55,57 @@ def spring_series(response, damping, appearing=True, exponent=1.0, seconds=0.9):
 
 def capture_of(*series, steps=None):
     return {"events": [{"onset": 1.0 + i, "series": {"block": s}, "step": None if steps is None else steps[i]} for i, s in enumerate(series)], "touches": []}
+
+
+def pair_geometry(shape, gap, radius=40):
+    height, width = shape[:2]
+    yy, xx = np.mgrid[0:height, 0:width] + 0.5
+    left = width / 2 - gap * 3 / 2 - radius * 3
+    right = width / 2 + gap * 3 / 2 + radius * 3
+    distance = np.minimum(np.hypot(xx - left, yy - height / 2), np.hypot(xx - right, yy - height / 2)) - radius * 3
+    return distance, xx, yy, left, right
+
+
+def glass_pair(bare, gap, bridge=0, gain=0.6, lift=0.0, rim=60.0):
+    distance, xx, yy, left, right = pair_geometry(bare.shape, gap)
+    inside = distance <= 0
+    if bridge:
+        inside |= (np.abs(yy - bare.shape[0] / 2) <= bridge * 3 / 2) & (xx >= left) & (xx <= right)
+    frame = bare.copy()
+    frame[inside] = np.clip(bare[inside] * gain + lift, 0, 255)
+    edge = (distance <= 0) & (distance > -3)
+    frame[edge] = np.clip(frame[edge] - rim, 0, 255)
+    return frame
+
+
+def chroma_ringing(image, period=40, amplitude=60.0):
+    out = image.copy()
+    for x in range(period * 3, image.shape[1], period * 3):
+        out[:, x - 2 : x + 2, 0] -= amplitude
+        out[:, x - 2 : x + 2, 1] += amplitude * 0.2126 / 0.7152
+    return np.clip(out, 0, 255)
+
+
+def grain(height=120, width=240, level=120.0, sigma=6.0, seed=7):
+    rng = np.random.default_rng(seed)
+    return np.clip(level + rng.normal(0.0, sigma, (height * 3, width * 3, 3)), 0, 255).astype(np.float32)
+
+
+def blur3(image):
+    padded = np.pad(image, ((1, 1), (1, 1), (0, 0)), mode="edge")
+    height, width = image.shape[:2]
+    return sum(padded[dy : dy + height, dx : dx + width] for dy in range(3) for dx in range(3)) / 9.0
+
+
+def frosted_pair(bare, gap, lift=2.0, outline=0.0, reach=6, rim=0.0):
+    distance = pair_geometry(bare.shape, gap)[0]
+    inside = distance <= 0
+    frame = bare.copy()
+    if outline:
+        band = (distance > 0) & (distance <= reach)
+        frame[band] = np.clip(frame[band] - outline, 0, 255)
+    frame[inside] = np.clip(blur3(blur3(bare))[inside] + lift, 0, 255)
+    if rim:
+        edge = inside & (distance > -3)
+        frame[edge] = np.clip(frame[edge] - rim, 0, 255)
+    return frame
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py b/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py
index 9c980bb1574b8548d3dca23b27eda506d826ec82..12a2884f4c68525d8564bb8f04a81614f71b5fc8 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py
@@ -1,8 +1,10 @@
 import sys
+import tempfile
 import unittest
 from pathlib import Path
 
 import numpy as np
+from PIL import Image
 
 sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
 sys.path.insert(0, str(Path(__file__).resolve().parent))
@@ -11,7 +13,7 @@ import analyze
 import manifest
 import shapes
 import springfit
-from synthetic import capture_of, spring_series
+from synthetic import capture_of, glass_pair, spring_series
 
 
 class ShapeTopologyTests(unittest.TestCase):
@@ -73,6 +75,37 @@ class ShapeTopologyTests(unittest.TestCase):
         self.assertEqual(shapes.neck_difference({"count": 1.0, "neck": 2.0}, {"count": 2.0, "neck": nan}), float("inf"))
         self.assertEqual(shapes.neck_difference({"count": 1.0, "neck": nan}, {"count": 1.0, "neck": 4.0}), float("inf"))
 
+    def test_still_gaps_compare_like_necks(self):
+        nan = float("nan")
+        self.assertEqual(shapes.gap_difference({"gap": nan}, {"gap": nan}), 0.0)
+        self.assertAlmostEqual(shapes.gap_difference({"gap": 3.0}, {"gap": 2.33}), 0.67, places=6)
+        self.assertEqual(shapes.gap_difference({"gap": 3.0}, {"gap": nan}), float("inf"))
+
+    def test_static_topology_reads_the_gap_between_two_shapes(self):
+        scene = manifest.parse([{"id": "x", "group": "material", "title": "t", "inventory": "2.14", "app": "lab", "backdrops": ["black"], "appearances": ["light"], "steps": [{"wait": 0.5}], "regions": {"g20": [0, 0, 240, 120], "g4": [0, 0, 240, 120]}, "topology": ["g20"]}])[0]
+        bare = np.zeros((360, 720, 3), dtype=np.float32)
+        with tempfile.TemporaryDirectory() as folder:
+            root = Path(folder)
+            for app, gap in (("native", 20), ("flutter", 18)):
+                (root / app / "bare").mkdir(parents=True)
+                Image.fromarray(bare.astype(np.uint8)).save(root / app / "bare" / "ready.png")
+                Image.fromarray(glass_pair(bare, gap, gain=0.0, lift=130.0, rim=0.0).astype(np.uint8)).save(root / app / "ready.png")
+            found = shapes.static_topology(scene, root / "native", root / "flutter")["g20"]
+        self.assertAlmostEqual(found["native"]["gap"], 20, delta=0.67)
+        self.assertAlmostEqual(found["flutter"]["gap"], 18, delta=0.67)
+        self.assertAlmostEqual(found["gap_pt"], 2, delta=0.67)
+        self.assertEqual(found["count"], 0.0)
+        self.assertEqual(found["neck_pt"], 0.0)
+
+    def test_still_topology_measures_include_the_gap_with_its_own_threshold(self):
+        topology = {"g20": {"count": 0.0, "neck_pt": 0.0, "gap_pt": 0.67}}
+        found = analyze.topology_measures(topology, {})
+        self.assertEqual(found["ready.topology.g20.gap_pt"], (0.67, 1.0, "max"))
+        self.assertEqual(found["ready.topology.g20.neck_pt"], (0.0, 1.0, "max"))
+        self.assertEqual(found["ready.topology.g20.count"], (0.0, 0.0, "max"))
+        noisy = analyze.topology_measures(topology, {"ready.topology.g20.gap_pt": 1.0})
+        self.assertEqual(noisy["ready.topology.g20.gap_pt"][1], 1.5)
+
     def test_the_neck_series_holds_each_frame_like_the_count(self):
         nan = float("nan")
         rows = [{"count": 2.0, "neck": nan}, {"count": 1.0, "neck": 6.0}, {"count": 1.0, "neck": 8.0}, {"count": 2.0, "neck": nan}]
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_track.py b/packages/mobile/tool/glass_lab/harness/tests/test_track.py
index 7f07c4ef4f16d2493f18e57889379c4df1872416..8fbb4f8209f228af62858af29121ae83fed76817 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_track.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_track.py
@@ -8,7 +8,7 @@ sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
 sys.path.insert(0, str(Path(__file__).resolve().parent))
 
 import track
-from synthetic import disks, draw, frames, stripes, with_codec_lines
+from synthetic import chroma_ringing, disks, draw, frames, frosted_pair, glass_pair, grain, pair_geometry, stripes, with_codec_lines
 
 
 class PixelRectTests(unittest.TestCase):
@@ -98,28 +98,54 @@ class TopologyTests(unittest.TestCase):
         self.edges = track.edges(self.bare)
 
     def test_separate_glass_counts_two_and_has_no_neck(self):
-        found = track.topology_row(disks(20), self.bare, self.edges)
+        found = track.topology_row(disks(20), self.bare)
         self.assertEqual(found["count"], 2.0)
         self.assertTrue(np.isnan(found["neck"]))
 
     def test_a_frame_with_no_glass_has_no_neck(self):
-        found = track.topology_row(self.bare.copy(), self.bare, self.edges)
+        found = track.topology_row(self.bare.copy(), self.bare)
         self.assertEqual(found["count"], 0.0)
         self.assertTrue(np.isnan(found["neck"]))
 
     def test_merged_glass_counts_one_and_measures_its_narrowest_neck(self):
-        row = track.topology_row(disks(0, bridge=20), self.bare, self.edges)
+        row = track.topology_row(disks(0, bridge=20), self.bare)
         self.assertEqual(row["count"], 1.0)
         self.assertAlmostEqual(row["neck"], 20, delta=1)
-        overlapping = track.topology_row(disks(-10), self.bare, self.edges)
+        overlapping = track.topology_row(disks(-10), self.bare)
         self.assertAlmostEqual(overlapping["neck"], 2 * (40**2 - 35**2) ** 0.5, delta=2)
 
-    def test_still_screenshots_use_the_low_lossless_threshold(self):
-        faint = self.bare.copy()
-        yy, xx = np.mgrid[0:360, 0:720]
-        faint[(xx - 180) ** 2 + (yy - 180) ** 2 <= 120**2] += 10
-        self.assertEqual(track.topology(track.still_mask(faint, self.bare))["count"], 1.0)
-        self.assertEqual(track.topology_row(faint, self.bare, self.edges)["count"], 0.0)
+    def test_still_screenshots_see_frosted_glass_that_the_video_mask_cannot(self):
+        bare = grain(sigma=3.0)
+        frame = frosted_pair(bare, 20)
+        self.assertEqual(track.topology(track.still_mask(frame, bare))["count"], 2.0)
+        self.assertEqual(track.topology_row(frame, bare)["count"], 0.0)
+
+    def test_glass_across_rung_stripe_boundaries_counts_one_component_per_shape(self):
+        bare = stripes(width=240, height=120)
+        apart = track.topology_row(chroma_ringing(glass_pair(bare, 20)), bare)
+        self.assertEqual(apart["count"], 2.0)
+        self.assertTrue(np.isnan(apart["neck"]))
+        joined = track.topology_row(chroma_ringing(glass_pair(bare, 0, bridge=20)), bare)
+        self.assertEqual(joined["count"], 1.0)
+        self.assertAlmostEqual(joined["neck"], 20, delta=1)
+
+    def test_chroma_ringing_alone_is_not_glass(self):
+        bare = stripes(width=240, height=120)
+        self.assertEqual(track.topology_row(chroma_ringing(bare), bare)["count"], 0.0)
+
+    def test_glass_seen_only_by_its_rim_is_filled(self):
+        apart = track.topology_row(glass_pair(self.bare, 20, gain=1.0, lift=0.0), self.bare)
+        self.assertEqual(apart["count"], 2.0)
+        overlapping = track.topology_row(glass_pair(self.bare, -10, gain=1.0, lift=0.0), self.bare)
+        self.assertEqual(overlapping["count"], 1.0)
+        self.assertAlmostEqual(overlapping["neck"], 2 * (40**2 - 35**2) ** 0.5, delta=2)
+
+    def test_the_video_topology_mask_leaves_the_box_mask_alone(self):
+        bare = stripes(width=240, height=120)
+        frame = chroma_ringing(glass_pair(bare, 20))
+        before = track.glass_mask(frame, bare, track.edges(bare)).copy()
+        track.topology_mask(frame, bare)
+        self.assertTrue((track.glass_mask(frame, bare, track.edges(bare)) == before).all())
 
     def test_one_component_with_no_neck_is_not_a_join(self):
         mask = np.zeros((90, 300), dtype=bool)
@@ -131,6 +157,57 @@ class TopologyTests(unittest.TestCase):
         self.assertTrue(np.isnan(found["neck"]))
 
 
+class StillTopologyTests(unittest.TestCase):
+    def test_a_smooth_outline_between_close_shapes_is_not_glass(self):
+        bare = grain()
+        frame = frosted_pair(bare, 4, outline=11.0, reach=7)
+        self.assertEqual(track.topology(track.still_mask(frame, bare))["count"], 2.0)
+
+    def test_glass_that_wipes_the_grain_is_glass_at_any_level(self):
+        bare = grain()
+        self.assertEqual(track.topology(track.still_mask(frosted_pair(bare, 20), bare))["count"], 2.0)
+        joined = track.topology(track.still_mask(frosted_pair(bare, -10, rim=40.0), bare))
+        self.assertEqual(joined["count"], 1.0)
+        self.assertAlmostEqual(joined["neck"], 2 * (40**2 - 35**2) ** 0.5, delta=2)
+
+    def test_bright_glass_on_a_flat_backdrop_needs_no_grain(self):
+        bare = np.zeros((360, 720, 3), dtype=np.float32)
+        frame = glass_pair(bare, 20, gain=0.0, lift=130.0, rim=0.0)
+        self.assertEqual(track.topology(track.still_mask(frame, bare))["count"], 2.0)
+        joined = track.topology(track.still_mask(glass_pair(bare, -10, gain=0.0, lift=130.0, rim=0.0), bare))
+        self.assertEqual(joined["count"], 1.0)
+
+
+class FillTests(unittest.TestCase):
+    def test_a_closed_ring_is_filled_and_an_open_one_is_not(self):
+        ring = np.zeros((40, 40), dtype=bool)
+        ring[5:35, 5:35] = True
+        ring[8:32, 8:32] = False
+        self.assertTrue(track.fill_holes(ring)[8:32, 8:32].all())
+        ring[18:22, 5:8] = False
+        self.assertFalse(track.fill_holes(ring)[8:32, 8:32].any())
+
+    def test_holes_that_reach_the_border_stay_open(self):
+        mask = np.zeros((20, 30), dtype=bool)
+        mask[:, 10] = True
+        self.assertEqual(int(track.fill_holes(mask).sum()), 20)
+
+
+class GapTests(unittest.TestCase):
+    def test_two_shapes_read_the_empty_run_between_them(self):
+        distance = pair_geometry((360, 720), 20)[0]
+        self.assertAlmostEqual(track.gap(distance <= 0), 20, delta=0.67)
+        narrow = pair_geometry((360, 720), 4)[0]
+        self.assertAlmostEqual(track.gap(narrow <= 0), 4, delta=0.67)
+
+    def test_anything_but_two_components_has_no_gap(self):
+        self.assertTrue(np.isnan(track.gap(pair_geometry((360, 720), -10)[0] <= 0)))
+        self.assertTrue(np.isnan(track.gap(np.zeros((360, 720), dtype=bool))))
+        three = pair_geometry((360, 720), 20)[0] <= 0
+        three[0:60, 0:60] = True
+        self.assertTrue(np.isnan(track.gap(three)))
+
+
 class TeardownTests(unittest.TestCase):
     def test_frames_after_the_last_settled_match_are_dropped(self):
         import tempfile
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t05-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_shapes.py` => FAIL

Expected output ends with:

```text
FAILED (failures=3, errors=14)
```

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

Patch `t05-impl` (`3269b9580..6006902f6`, 4 files):

```diff
diff --git a/packages/mobile/tool/glass_lab/harness/analyze.py b/packages/mobile/tool/glass_lab/harness/analyze.py
index aa2d7583557453fd8e6ee5287935dbabcee51f97..3f4c8bbc6a08a736599655f82dc22deeaf003e86 100644
--- a/packages/mobile/tool/glass_lab/harness/analyze.py
+++ b/packages/mobile/tool/glass_lab/harness/analyze.py
@@ -255,6 +255,17 @@ def limit(key, name, noise, value):
     return (value, max(metrics.THRESHOLDS[key], NOISE_FACTOR * noise.get(name, 0.0)), "max")
 
 
+TOPOLOGY_MEASURES = ("count", "neck_pt", "gap_pt")
+
+
+def topology_measures(topology, noise):
+    return {
+        f"ready.topology.{name}.{key}": limit(key, f"ready.topology.{name}.{key}", noise, entry[key])
+        for name, entry in topology.items()
+        for key in TOPOLOGY_MEASURES
+    }
+
+
 def analyze(scene, case_dir, noise=None, cache=None):
     noise = noise or {}
     case_dir = Path(case_dir)
@@ -289,9 +300,7 @@ def analyze(scene, case_dir, noise=None, cache=None):
     }
     if scene.topology:
         result["topology"] = shapes.static_topology(scene, native_dir, flutter_dir)
-        for name, entry in result["topology"].items():
-            for key, threshold in (("count", "count"), ("neck_pt", "neck_pt")):
-                measures[f"ready.topology.{name}.{key}"] = limit(threshold, f"ready.topology.{name}.{key}", noise, entry[key])
+        measures.update(topology_measures(result["topology"], noise))
     checks = {name: within(*entry) for name, entry in measures.items()}
     if not scene.rest and (scene.track or scene.topology):
         native, flutter = shape_capture(scene, native_dir, cache), shape_capture(scene, flutter_dir, cache)
diff --git a/packages/mobile/tool/glass_lab/harness/metrics.py b/packages/mobile/tool/glass_lab/harness/metrics.py
index dd03d25bca4cdccc67305aaf95ca0bb714e831c0..7bf692cbb4c169304787c5aca0e7b2a6695ff421 100644
--- a/packages/mobile/tool/glass_lab/harness/metrics.py
+++ b/packages/mobile/tool/glass_lab/harness/metrics.py
@@ -19,6 +19,7 @@ THRESHOLDS = {
     "progress_rms": 0.05,
     "sharpness": 1.0,
     "neck_pt": 1.0,
+    "gap_pt": 1.0,
     "count": 0.0,
 }
 
diff --git a/packages/mobile/tool/glass_lab/harness/shapes.py b/packages/mobile/tool/glass_lab/harness/shapes.py
index f15add7e8ad7a31c99d3a9e6198bcd027668cb13..9bf82193e5f8cad204f75d26ed7d933b5bc4a4e5 100644
--- a/packages/mobile/tool/glass_lab/harness/shapes.py
+++ b/packages/mobile/tool/glass_lab/harness/shapes.py
@@ -104,7 +104,7 @@ def capture(scene, case_dir, found):
             row = track.shape_row(crop, part["bare"], part["edges"], part["origin"])
             row.update(track.progress_row(shrink(crop), part["bare_pt"], part["full_pt"], part["inner"]))
             if name in scene.topology:
-                row.update(track.topology_row(crop, part["bare"], part["edges"]))
+                row.update(track.topology_row(crop, part["bare"]))
             rows[name].append(row)
     windows = [w for w in touch.read(case_dir / "video.mp4", case_dir / "marker") if w[1] >= start - LEAD_SECONDS and w[0] <= end]
     events = []
@@ -322,15 +322,22 @@ def transitions(counts):
     return joins, splits
 
 
-def neck_difference(a, b):
-    a_neck, b_neck = a["neck"], b["neck"]
-    if np.isfinite(a_neck) and np.isfinite(b_neck):
-        return float(abs(a_neck - b_neck))
-    if not np.isfinite(a_neck) and not np.isfinite(b_neck):
+def finite_difference(a, b):
+    if np.isfinite(a) and np.isfinite(b):
+        return float(abs(a - b))
+    if not np.isfinite(a) and not np.isfinite(b):
         return 0.0
     return float("inf")
 
 
+def neck_difference(a, b):
+    return finite_difference(a["neck"], b["neck"])
+
+
+def gap_difference(a, b):
+    return finite_difference(a["gap"], b["gap"])
+
+
 def transition_gap(a, b):
     if a and b:
         return abs(a[0] - b[0]) * 1000 / align.GRID_HZ
@@ -483,11 +490,13 @@ def static_topology(scene, native_dir, flutter_dir):
         rows = {}
         for app, folder in (("native", native_dir), ("flutter", flutter_dir)):
             bare = track.crop_px(metrics.load(folder / "bare" / "ready.png"), px)
-            rows[app] = track.topology(track.still_mask(track.crop_px(metrics.load(folder / "ready.png"), px), bare))
+            mask = track.still_mask(track.crop_px(metrics.load(folder / "ready.png"), px), bare)
+            rows[app] = dict(track.topology(mask), gap=track.gap(mask))
         found[name] = {
             "native": rows["native"],
             "flutter": rows["flutter"],
             "count": abs(rows["native"]["count"] - rows["flutter"]["count"]),
             "neck_pt": neck_difference(rows["native"], rows["flutter"]),
+            "gap_pt": gap_difference(rows["native"], rows["flutter"]),
         }
     return found
diff --git a/packages/mobile/tool/glass_lab/harness/track.py b/packages/mobile/tool/glass_lab/harness/track.py
index 2d8f1b5215690b2921c2dac1731bb93bbf58acc2..a1e77665634ceacbbb7bc2e029d0348efa1aaa4e 100644
--- a/packages/mobile/tool/glass_lab/harness/track.py
+++ b/packages/mobile/tool/glass_lab/harness/track.py
@@ -1,5 +1,6 @@
 import re
 import subprocess
+from collections import deque
 from pathlib import Path
 
 import numpy as np
@@ -214,11 +215,66 @@ def neck(mask, scale=metrics.SCALE):
     return float(min(widths)) / scale if widths else 0.0
 
 
-STILL_THRESHOLD = 6.0
+def _reach(seeds, free):
+    flat = free.ravel()
+    width = free.shape[1]
+    starts = flat.copy()
+    starts[1:] &= ~flat[:-1] | (np.arange(1, flat.size) % width == 0)
+    runs = np.cumsum(starts) * flat
+    hit = np.bincount(runs, weights=(seeds.ravel() & flat).astype(np.float64), minlength=int(runs.max()) + 1) > 0
+    hit[0] = False
+    return hit[runs].reshape(free.shape)
+
+
+def fill_holes(mask):
+    free = ~mask
+    outside = np.zeros_like(free)
+    outside[[0, -1], :] = free[[0, -1], :]
+    outside[:, [0, -1]] |= free[:, [0, -1]]
+    while True:
+        grown = _reach(_reach(outside, free).T, free.T).T
+        if (grown == outside).all():
+            return ~outside
+        outside = grown
+
+
+def close(mask, reach):
+    size = 2 * reach + 1
+    return _box_filter(_box_filter(mask, size, np.maximum), size, np.minimum)
+
+
+TOPOLOGY_LUMA = 8.0
+TOPOLOGY_CLOSE = 2
+
+
+def topology_mask(frame, bare):
+    change = np.abs(metrics.luma(frame) - metrics.luma(bare)) > TOPOLOGY_LUMA
+    solid = fill_holes(close(change, TOPOLOGY_CLOSE))
+    edge = _box_filter(~solid, 2 * TOPOLOGY_CLOSE + 1, np.maximum)
+    return solid & (change | ~edge)
+
+
+STILL_RIM = 30.0
+GRAIN_REMOVED = 0.8
+GRAIN_MIN = 4.0
+GRAIN_WINDOW = 5
+
+
+def grain_removed(frame, bare):
+    change = frame - bare
+    shared = np.zeros(bare.shape[:2], dtype=np.float32)
+    energy = np.zeros(bare.shape[:2], dtype=np.float32)
+    for channel in range(3):
+        texture = bare[..., channel] - smooth(bare[..., channel])
+        lost = change[..., channel] - smooth(change[..., channel])
+        shared += _box_filter(lost * texture, GRAIN_WINDOW, np.add)
+        energy += _box_filter(texture * texture, GRAIN_WINDOW, np.add)
+    return (energy > GRAIN_MIN * GRAIN_WINDOW**2) & (shared < -GRAIN_REMOVED * energy)
 
 
 def still_mask(frame, bare):
-    return smooth(np.abs(frame - bare).max(axis=2)) > STILL_THRESHOLD
+    rim = np.abs(frame - bare).max(axis=2) > STILL_RIM
+    return fill_holes(rim | grain_removed(frame, bare))
 
 
 def topology(mask):
@@ -229,5 +285,46 @@ def topology(mask):
     return {"count": 1.0, "neck": width if width > 0 else float("nan")}
 
 
-def topology_row(frame, bare, edge_map):
-    return topology(glass_mask(frame, bare, edge_map))
+def _labels(mask):
+    labels = np.zeros(mask.shape, dtype=np.int32)
+    height, width = mask.shape
+    found = 0
+    for y, x in zip(*np.nonzero(mask)):
+        if labels[y, x]:
+            continue
+        found += 1
+        labels[y, x] = found
+        queue = deque([(y, x)])
+        while queue:
+            cy, cx = queue.popleft()
+            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
+                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not labels[ny, nx]:
+                    labels[ny, nx] = found
+                    queue.append((ny, nx))
+    return labels, found
+
+
+def gap(mask, scale=metrics.SCALE):
+    labels, found = _labels(point_mask(mask))
+    centres = []
+    for label in range(1, found + 1):
+        ys, xs = np.nonzero(labels == label)
+        if len(xs) >= TOPOLOGY_MIN_AREA:
+            centres.append((np.array([xs.mean(), ys.mean()]) + 0.5) * scale)
+    if len(centres) != 2:
+        return float("nan")
+    a, b = centres
+    span = float(np.linalg.norm(b - a))
+    along = (b - a) / span
+    height, width = mask.shape
+    empty = 0
+    for t in np.arange(0, span, 1.0):
+        x, y = a + along * t
+        ix, iy = int(np.floor(x)), int(np.floor(y))
+        if 0 <= ix < width and 0 <= iy < height and not mask[iy, ix]:
+            empty += 1
+    return empty / scale
+
+
+def topology_row(frame, bare):
+    return topology(topology_mask(frame, bare))
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t05-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_shapes.py` => PASS

Expected output ends with:

```text
Ran 53 tests in <time>
OK
```

- [ ] **Step 5: Gate: harness.**

RUN[t05-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

Expected output ends with:

```text
Ran 227 tests in <time>
OK
```

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): topology masks that count native glass on stripes and photo, still mask without the outline, gap_pt

Co-Authored-By: <the session's attribution line>"
```

### Task 6: `material.merge` tracks each circle, judges the pair's topology, and runs on photo too

**Files:**
- Modify: `tool/glass_lab/scenes.json` (`material.merge`: tracked circles, `topology` regions, photo backdrop, the motion list)

**Why.** Rulings 2 and 26. The scene is the spec's merge Done item; its manifest keeps `width.*` (ruling 26, D3).

- [ ] **Step 1: Apply the implementation.**

Patch `t06-impl` (`6006902f6..96d7d5d03`, 1 files):

```diff
diff --git a/packages/mobile/tool/glass_lab/scenes.json b/packages/mobile/tool/glass_lab/scenes.json
index 1752a00c28d0c54128230c2fa5a7c32d46e12db3..716c00f3882fa32a2db8557adf84e04bdbe8b04d 100644
--- a/packages/mobile/tool/glass_lab/scenes.json
+++ b/packages/mobile/tool/glass_lab/scenes.json
@@ -608,7 +608,8 @@
     "inventory": "2.14",
     "app": "lab",
     "backdrops": [
-      "stripes"
+      "stripes",
+      "photo"
     ],
     "appearances": [
       "light",
@@ -630,6 +631,49 @@
       {
         "wait": 1.5
       }
+    ],
+    "regions": {
+      "left": [
+        69,
+        399,
+        132,
+        104
+      ],
+      "right": [
+        201,
+        399,
+        132,
+        104
+      ],
+      "pair": [
+        61,
+        399,
+        280,
+        104
+      ]
+    },
+    "track": [
+      "left",
+      "right"
+    ],
+    "topology": [
+      "pair"
+    ],
+    "motion": [
+      "width.peak_ms",
+      "width.settle_ms",
+      "width.overshoot_pct",
+      "width.response_pct",
+      "width.damping",
+      "cx.peak_ms",
+      "cx.settle_ms",
+      "cx.overshoot_pct",
+      "cx.response_pct",
+      "cx.damping",
+      "topology.count",
+      "topology.join_ms",
+      "topology.split_ms",
+      "topology.neck_rms"
     ]
   },
   {
```

- [ ] **Step 2: Check the manifest still loads and validates every scene.**

RUN[t06-manifest]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_manifest.py` => PASS

Expected output ends with:

```text
Ran 17 tests in <time>
OK
```

- [ ] **Step 3: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): material.merge tracks each circle, judges the pair's topology, and runs on photo too

Co-Authored-By: <the session's attribution line>"
```

### Task 7: Native controls for the morph toggle's swelling

**Files:**
- Modify: `tool/glass_lab/scenes.json` (`material.tap`, `material.morph.plain`)
- Modify: `tool/glass_lab/native/GlassLab/MaterialScenes.swift`

**Why.** Ruling 19. A tap that changes nothing and a plain morph show that the toggle's swelling is the morph. This task also compiles the Swift of Tasks 2 and 7.

- [ ] **Step 1: Apply the implementation.**

Patch `t07-impl` (`d0cfaf7ae..599853e52`, 2 files):

```diff
diff --git a/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift b/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift
index 82ac992b86b69736f120578d4a5596012638bdff..050ecf55e26c4287ebff1fd2063ecb4f1cada59f 100644
--- a/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift
+++ b/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift
@@ -41,6 +41,8 @@ enum MaterialScenes {
         "material.merge": { AnyView(MergeScene()) },
         "material.union": { AnyView(UnionScene()) },
         "material.morph": { AnyView(MorphScene()) },
+        "material.morph.plain": { AnyView(MorphScene(interactive: false)) },
+        "material.tap": { AnyView(TapScene()) },
         "material.shapes": { AnyView(ShapesScene()) },
         "material.edge.soft": { AnyView(EdgeScene(style: .soft)) },
         "material.edge.hard": { AnyView(EdgeScene(style: .hard)) },
@@ -247,6 +249,7 @@ struct UnionScene: View {
 }
 
 struct MorphScene: View {
+    var interactive = true
     @Namespace private var namespace
     @State private var expanded = false
     private let badges = ["star.fill", "heart.fill", "bolt.fill"]
@@ -273,7 +276,7 @@ struct MorphScene: View {
                             .frame(width: 56, height: 56)
                     }
                     .buttonStyle(.plain)
-                    .glassEffect(.regular.interactive())
+                    .glassEffect(interactive ? .regular.interactive() : .regular)
                     .glassEffectID("toggle", in: namespace)
                     .accessibilityIdentifier("morph")
                 }
@@ -282,6 +285,24 @@ struct MorphScene: View {
     }
 }
 
+struct TapScene: View {
+    var body: some View {
+        ZStack {
+            Backdrop()
+            GlassEffectContainer(spacing: 20) {
+                Button {} label: {
+                    Image(systemName: "plus")
+                        .font(.system(size: 22, weight: .semibold))
+                        .frame(width: 56, height: 56)
+                }
+                .buttonStyle(.plain)
+                .glassEffect(.regular.interactive())
+                .accessibilityIdentifier("glass")
+            }
+        }
+    }
+}
+
 struct ShapesScene: View {
     var body: some View {
         ZStack {
diff --git a/packages/mobile/tool/glass_lab/scenes.json b/packages/mobile/tool/glass_lab/scenes.json
index 716c00f3882fa32a2db8557adf84e04bdbe8b04d..1627c97525b60547473a504e063f14dbac1d136f 100644
--- a/packages/mobile/tool/glass_lab/scenes.json
+++ b/packages/mobile/tool/glass_lab/scenes.json
@@ -723,6 +723,64 @@
       }
     ]
   },
+  {
+    "id": "material.morph.plain",
+    "group": "material",
+    "title": "Morph scene with a non-interactive toggle (control for the toggle's swelling)",
+    "inventory": "2.16",
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
+        "tap": "morph"
+      },
+      {
+        "wait": 1.5
+      },
+      {
+        "tap": "morph"
+      },
+      {
+        "wait": 1.5
+      }
+    ]
+  },
+  {
+    "id": "material.tap",
+    "group": "material",
+    "title": "A 56 pt interactive glass button tapped with no state change (control for the morph toggle's swelling)",
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
+        "tap": "glass"
+      },
+      {
+        "wait": 1.5
+      }
+    ]
+  },
   {
     "id": "material.spacing.default.a",
     "group": "material",
```

- [ ] **Step 2: Check the manifest still loads and validates every scene.**

RUN[t07-manifest]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_manifest.py` => PASS

Expected output ends with:

```text
Ran 17 tests in <time>
OK
```

- [ ] **Step 3: Build the native lab app (Xcode 27, a few minutes); this is the only check the Swift of Tasks 2 and 7 gets.**

RUN[t07-native-build]: `cd packages/mobile && python3 tool/glass_lab/harness/lab.py build native` => PASS

Expected output ends with:

```text
built for 708879DD-8B2A-4547-863F-F49EE1474D8B
```

- [ ] **Step 4: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): native controls for the morph toggle's swelling

Co-Authored-By: <the session's attribution line>"
```

### Task 8: `GlassNamespace` and `GlassEffectUnion`: a union draws as one capsule on its members' drawn rects; the union scene rebuilt (M5)

**Files:**
- Create: `packages/ios_liquid_glass/lib/src/api/glass_namespace.dart`
- Modify: `lib/ios_liquid_glass.dart`, `lib/src/api/glass_effect.dart`, `lib/src/glass_shadow.dart`, `lib/src/liquid_glass.dart`, `lib/src/liquid_glass_blend_group.dart`, `lib/src/motion/glass_motion_coordinator.dart`, `lib/src/motion/glass_shape_motion.dart`, `CHANGELOG.md`, `FORK.md`, `README.md`
- Modify (example): `lib/lab/scenes/material_scenes.dart` (the union scene), `tool/glass_lab/scenes.json`
- Test: `test/motion/glass_union_test.dart`, `test/motion/render_hooks_test.dart`, example `test/union_scene_test.dart`

**Why.** Rulings 15–17.

- [ ] **Step 1: Add the failing tests.**

Patch `t08-tests` (`599853e52..3a1e5a7f1`, 3 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/example/test/union_scene_test.dart b/packages/mobile/packages/ios_liquid_glass/example/test/union_scene_test.dart
new file mode 100644
index 0000000000000000000000000000000000000000..e5360106810da1db97a7d917e40687b3b08d40a7
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/example/test/union_scene_test.dart
@@ -0,0 +1,63 @@
+import 'dart:convert';
+import 'dart:io';
+
+import 'package:flutter/material.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+import 'package:ios_liquid_glass_example/lab/glass_lab_launch.dart';
+import 'package:ios_liquid_glass_example/lab/glass_lab_screen.dart';
+
+const Size _screen = Size(402, 874);
+
+Map<String, dynamic> _entry() => (jsonDecode(File('../../../tool/glass_lab/scenes.json').readAsStringSync()) as List<dynamic>)
+    .cast<Map<String, dynamic>>()
+    .singleWhere((entry) => entry['id'] == 'material.union');
+
+Rect _region(Map<String, dynamic> entry, String name) {
+  final values = (entry['regions'][name] as List<dynamic>).cast<num>();
+  return Rect.fromLTWH(values[0].toDouble(), values[1].toDouble(), values[2].toDouble(), values[3].toDouble());
+}
+
+void main() {
+  testWidgets('the union scene lays out four 64 pt glasses in two unions as native does, centred on y 451', (tester) async {
+    tester.view.physicalSize = _screen * 3;
+    tester.view.devicePixelRatio = 3;
+    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
+    addTearDown(tester.view.reset);
+    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.union'))));
+    await tester.pump();
+    final glasses = tester.widgetList<GlassEffect>(find.byType(GlassEffect)).toList();
+    expect(glasses, hasLength(4));
+    final rects = [for (final glass in glasses) tester.getRect(find.byWidget(glass))];
+    expect(rects, [
+      for (final left in [49.0, 129.0, 209.0, 289.0]) Rect.fromLTWH(left, 419, 64, 64),
+    ]);
+    expect(rects.first.center.dy, 451);
+    expect([for (final glass in glasses) glass.union!.id], ['first', 'first', 'second', 'second']);
+    expect(glasses.map((glass) => glass.union!.namespace).toSet(), hasLength(1));
+    expect(glasses.map((glass) => glass.shape).toSet(), {const GlassShape.capsule()});
+    expect(glasses.map((glass) => glass.glass).toSet(), {Glass.regular});
+    final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
+    expect([for (final icon in icons) icon.icon], [Icons.star, Icons.favorite, Icons.bolt, Icons.eco]);
+    expect(icons.map((icon) => icon.size).toSet(), {24});
+    for (final (index, icon) in icons.indexed) {
+      expect(tester.getCenter(find.byWidget(icon)), rects[index].center);
+      expect(find.ancestor(of: find.byWidget(icon), matching: find.byType(GlassForeground)), findsOneWidget);
+    }
+    expect(tester.widget<GlassEffectContainer>(find.byType(GlassEffectContainer)).spacing, 8);
+    final namespace = glasses.first.union!.namespace;
+    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.union'))));
+    expect(tester.widget<GlassEffect>(find.byType(GlassEffect).first).union!.namespace, same(namespace));
+  });
+
+  test('the union manifest pins each union and the pair padded by 12 pt, and judges their topology on its stills', () {
+    final entry = _entry();
+    expect(_region(entry, 'first'), const Rect.fromLTRB(49, 419, 193, 483).inflate(12));
+    expect(_region(entry, 'second'), const Rect.fromLTRB(209, 419, 353, 483).inflate(12));
+    expect(_region(entry, 'pair'), const Rect.fromLTRB(49, 419, 353, 483).inflate(12));
+    expect(entry['topology'], ['first', 'second', 'pair']);
+    expect(entry['backdrops'], ['stripes']);
+    expect(entry['appearances'], ['light', 'dark']);
+    expect(entry['steps'], isEmpty);
+  });
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_union_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_union_test.dart
new file mode 100644
index 0000000000000000000000000000000000000000..7f8c77cc73479cb6c8360d023215cfb0803ecc7a
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_union_test.dart
@@ -0,0 +1,368 @@
+import 'dart:ui' as ui;
+
+import 'package:flutter/material.dart';
+import 'package:flutter/rendering.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+import 'package:ios_liquid_glass/src/glass_shadow.dart';
+import 'package:ios_liquid_glass/src/internal/render_liquid_glass_geometry.dart';
+import 'package:ios_liquid_glass/src/liquid_glass.dart';
+import 'package:ios_liquid_glass/src/liquid_glass_blend_group.dart';
+import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
+import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
+import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
+import 'package:ios_liquid_glass/src/rendering/liquid_glass_render_object.dart';
+import 'package:ios_liquid_glass/src/shaders.dart';
+
+const LiquidShape _capsule = LiquidRoundedRectangle(borderRadius: 999);
+
+class _Scene extends StatefulWidget {
+  const _Scene({required this.children, this.container = true});
+
+  final List<Widget> Function(_SceneState state) children;
+  final bool container;
+
+  @override
+  State<_Scene> createState() => _SceneState();
+}
+
+class _SceneState extends State<_Scene> {
+  final GlassNamespace namespace = GlassNamespace();
+  final GlassNamespace other = GlassNamespace();
+  bool shown = true;
+  double gap = 16;
+
+  void update(VoidCallback change) => setState(change);
+
+  @override
+  Widget build(BuildContext context) {
+    final row = Row(mainAxisSize: MainAxisSize.min, children: widget.children(this));
+    return MaterialApp(
+      home: GlassTheme(
+        data: const GlassThemeData(brightness: Brightness.dark),
+        child: Align(alignment: Alignment.topLeft, child: widget.container ? GlassEffectContainer(child: row) : row),
+      ),
+    );
+  }
+}
+
+Widget _glass(String key, {GlassEffectUnion? union, GlassShape shape = const GlassShape.capsule(), Glass glass = Glass.regular}) =>
+    GlassEffect(key: ValueKey(key), union: union, shape: shape, glass: glass, child: const SizedBox.square(dimension: 64));
+
+GlassMember _member(WidgetTester tester, String key) => tester
+    .renderObject<RenderGlassMemberBox>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(GlassMemberBox)).first)
+    .member;
+
+_SceneState _state(WidgetTester tester) => tester.state<_SceneState>(find.byType(_Scene));
+
+Rect _bounds(Iterable<GlassMember> members) => members.map((member) => member.drawn!).reduce((a, b) => a.expandToInclude(b));
+
+class _Motion extends ChangeNotifier implements GlassShapeMotion {
+  _Motion(this.drawn, [this.outline]);
+
+  Rect drawn;
+  GlassUnionOutline? outline;
+
+  @override
+  Rect resolve(RenderBox shape) => drawn;
+
+  @override
+  GlassUnionOutline? union(RenderBox shape) => outline;
+}
+
+class _Group extends RenderLiquidGlassBlendGroup {
+  _Group({required super.geometryShader, required super.link})
+    : super(renderLink: GeometryRenderLink(), devicePixelRatio: 3, settings: const LiquidGlassSettings(thickness: 20), blend: 8);
+
+  @override
+  void updateShaderWithSettings(LiquidGlassSettings settings, double devicePixelRatio) {}
+
+  @override
+  void updateGeometryShaderShapes(List<ShapeGeometry> shapes) {}
+
+  void remember() {
+    final (bounds, shapes, _) = gatherShapeData();
+    final recorder = ui.PictureRecorder();
+    Canvas(recorder);
+    geometry = UnrenderedGeometryCache(matte: recorder.endRecording(), matteBounds: bounds, bounds: bounds, shapes: shapes, path: Path());
+  }
+}
+
+Future<(_Group, List<RenderLiquidGlass>)> _group(List<_Motion> motions) async {
+  final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
+  final link = GlassGroupLink();
+  final glasses = [
+    for (final motion in motions)
+      RenderLiquidGlass(shape: _capsule, glassContainsChild: false, blendGroupLink: link)
+        ..motion = motion
+        ..child = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(const Size(20, 20))),
+  ];
+  final group = _Group(geometryShader: program.fragmentShader(), link: link)
+    ..child = RenderFlex(textDirection: TextDirection.ltr, crossAxisAlignment: CrossAxisAlignment.start, children: glasses);
+  final root = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(const Size(800, 400)), child: group);
+  PipelineOwner().rootNode = root;
+  root.layout(const BoxConstraints());
+  return (group, glasses);
+}
+
+void main() {
+  isLocalTest = true;
+  tearDown(debugResetGlassAnimation);
+
+  test('a union is equal to another with the same id in the same namespace, and to no other', () {
+    final namespace = GlassNamespace();
+    final other = GlassNamespace();
+    expect(GlassEffectUnion('first', namespace), GlassEffectUnion('first', namespace));
+    expect(GlassEffectUnion('first', namespace).hashCode, GlassEffectUnion('first', namespace).hashCode);
+    expect(GlassEffectUnion('first', namespace), isNot(GlassEffectUnion('second', namespace)));
+    expect(GlassEffectUnion('first', namespace), isNot(GlassEffectUnion('first', other)));
+    expect(namespace, isNot(other));
+    expect(const GlassEffect(child: SizedBox()).union, isNull);
+  });
+
+  testWidgets('each union in a container draws as one capsule on the bounding rect of its members, led by its first member', (tester) async {
+    await tester.pumpWidget(_Scene(children: (state) => [
+      for (final (index, key) in ['a', 'b', 'c', 'd'].indexed) ...[
+        if (index > 0) const SizedBox(width: 16),
+        _glass(key, union: GlassEffectUnion(index < 2 ? 'first' : 'second', state.namespace)),
+      ],
+    ]));
+    await tester.pump(const Duration(seconds: 1));
+    final [a, b, c, d] = [for (final key in ['a', 'b', 'c', 'd']) _member(tester, key)];
+    expect(a.unionOutline, GlassUnionOutline(rect: Rect.fromLTRB(a.drawn!.left, a.drawn!.top, b.drawn!.right, b.drawn!.bottom), shape: _capsule, leads: true));
+    expect(a.unionOutline!.rect.size, const Size(144, 64));
+    expect(b.unionOutline, GlassUnionOutline(rect: a.unionOutline!.rect, shape: _capsule, leads: false));
+    expect(c.unionOutline!.rect, Rect.fromLTRB(c.drawn!.left, c.drawn!.top, d.drawn!.right, d.drawn!.bottom));
+    expect(c.unionOutline!.leads, isTrue);
+    expect(d.unionOutline!.leads, isFalse);
+    expect(c.unionOutline!.rect.left - a.unionOutline!.rect.right, 16);
+  });
+
+  testWidgets('union members keep their own drawn rects, so their content stays where each is laid out', (tester) async {
+    await tester.pumpWidget(_Scene(children: (state) => [
+      _glass('a', union: GlassEffectUnion('first', state.namespace)),
+      const SizedBox(width: 16),
+      _glass('b', union: GlassEffectUnion('first', state.namespace)),
+    ]));
+    await tester.pump(const Duration(seconds: 1));
+    final a = _member(tester, 'a'), b = _member(tester, 'b');
+    final boxA = tester.renderObject<RenderGlassMemberBox>(find.descendant(of: find.byKey(const ValueKey('a')), matching: find.byType(GlassMemberBox)).first);
+    final boxB = tester.renderObject<RenderGlassMemberBox>(find.descendant(of: find.byKey(const ValueKey('b')), matching: find.byType(GlassMemberBox)).first);
+    expect(a.resolve(boxA), const Rect.fromLTWH(0, 0, 64, 64));
+    expect(b.resolve(boxB), const Rect.fromLTWH(0, 0, 64, 64));
+    expect(a.union(boxA), GlassUnionOutline(rect: const Rect.fromLTWH(0, 0, 144, 64), shape: _capsule, leads: true));
+    expect(b.union(boxB), GlassUnionOutline(rect: const Rect.fromLTWH(-80, 0, 144, 64), shape: _capsule, leads: false));
+  });
+
+  testWidgets('a union of circles is a capsule of its rect; a union of rounded rects keeps their corner radius', (tester) async {
+    await tester.pumpWidget(_Scene(children: (state) => [
+      _glass('a', union: GlassEffectUnion('circles', state.namespace), shape: const GlassShape.circle()),
+      _glass('b', union: GlassEffectUnion('circles', state.namespace), shape: const GlassShape.circle()),
+      _glass('c', union: GlassEffectUnion('rects', state.namespace), shape: const GlassShape.rect(20)),
+      _glass('d', union: GlassEffectUnion('rects', state.namespace), shape: const GlassShape.rect(20)),
+    ]));
+    await tester.pump(const Duration(seconds: 1));
+    expect(_member(tester, 'a').unionOutline!.shape, _capsule);
+    expect(_member(tester, 'a').unionOutline!.rect.size, const Size(128, 64));
+    expect(_member(tester, 'c').unionOutline!.shape, const LiquidRoundedRectangle(borderRadius: 20));
+  });
+
+  testWidgets('only glass with the same shape and the same glass joins a union, as SwiftUI documents', (tester) async {
+    await tester.pumpWidget(_Scene(children: (state) => [
+      _glass('a', union: GlassEffectUnion('u', state.namespace)),
+      _glass('b', union: GlassEffectUnion('u', state.namespace)),
+      _glass('rect', union: GlassEffectUnion('u', state.namespace), shape: const GlassShape.rect(20)),
+      _glass('interactive', union: GlassEffectUnion('u', state.namespace), glass: Glass.regular.interactive()),
+    ]));
+    await tester.pump(const Duration(seconds: 1));
+    final a = _member(tester, 'a'), b = _member(tester, 'b');
+    expect(a.unionOutline!.rect, _bounds([a, b]));
+    expect(_member(tester, 'rect').unionOutline, isNull);
+    expect(_member(tester, 'interactive').unionOutline, isNull);
+  });
+
+  testWidgets('the same id in different namespaces, or no union, draws each glass on its own', (tester) async {
+    await tester.pumpWidget(_Scene(children: (state) => [
+      _glass('a', union: GlassEffectUnion('first', state.namespace)),
+      _glass('b', union: GlassEffectUnion('first', state.other)),
+      _glass('c'),
+    ]));
+    await tester.pump(const Duration(seconds: 1));
+    for (final key in ['a', 'b', 'c']) {
+      expect(_member(tester, key).unionOutline, isNull, reason: key);
+    }
+  });
+
+  testWidgets('standalone glass with a union id draws on its own: a union needs a container', (tester) async {
+    await tester.pumpWidget(_Scene(container: false, children: (state) => [
+      _glass('a', union: GlassEffectUnion('first', state.namespace)),
+      _glass('b', union: GlassEffectUnion('first', state.namespace)),
+    ]));
+    await tester.pump(const Duration(seconds: 1));
+    expect(_member(tester, 'a').unionOutline, isNull);
+    expect(_member(tester, 'b').unionOutline, isNull);
+  });
+
+  testWidgets('a union follows a moving member: its rect is the bounding rect of the drawn rects on every frame', (tester) async {
+    await tester.pumpWidget(_Scene(children: (state) => [
+      _glass('a', union: GlassEffectUnion('first', state.namespace)),
+      SizedBox(width: state.gap),
+      _glass('b', union: GlassEffectUnion('first', state.namespace)),
+    ]));
+    await tester.pump(const Duration(seconds: 1));
+    final a = _member(tester, 'a'), b = _member(tester, 'b');
+    var notified = 0;
+    a.addListener(() => notified++);
+    expect(a.unionOutline!.rect.width, 144);
+    _state(tester).update(() => _state(tester).gap = 116);
+    await tester.pump();
+    final widths = <double>[];
+    for (var i = 0; i < 8; i++) {
+      await tester.pump(const Duration(milliseconds: 30));
+      expect(a.unionOutline!.rect, _bounds([a, b]));
+      widths.add(a.unionOutline!.rect.width);
+    }
+    expect(widths.first, inExclusiveRange(144, 244));
+    expect(widths.last, greaterThan(widths.first));
+    expect(a.isMoving, isFalse);
+    expect(notified, greaterThan(4));
+    await tester.pumpAndSettle();
+    expect(a.unionOutline!.rect, Rect.fromLTWH(a.drawn!.left, a.drawn!.top, 244, 64));
+  });
+
+  testWidgets('an inserted member materializes on its own and joins its union when it settles', (tester) async {
+    await tester.pumpWidget(_Scene(children: (state) => [
+      _glass('a', union: GlassEffectUnion('first', state.namespace)),
+      _glass('b', union: GlassEffectUnion('first', state.namespace)),
+      if (!state.shown) _glass('c', union: GlassEffectUnion('first', state.namespace)),
+    ]));
+    await tester.pump(const Duration(seconds: 1));
+    final a = _member(tester, 'a'), b = _member(tester, 'b');
+    _state(tester).update(() => _state(tester).shown = false);
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 50));
+    final c = _member(tester, 'c');
+    expect(c.ownsLayer, isTrue);
+    expect(c.unionOutline, isNull);
+    expect(a.unionOutline!.rect, _bounds([a, b]));
+    await tester.pumpAndSettle();
+    expect(c.ownsLayer, isFalse);
+    expect(a.unionOutline!.rect, _bounds([a, b, c]));
+    expect(c.unionOutline!.leads, isFalse);
+  });
+
+  testWidgets('a removed member leaves its union at once and dematerializes on its own; the rest notice', (tester) async {
+    await tester.pumpWidget(_Scene(children: (state) => [
+      if (state.shown) _glass('a', union: GlassEffectUnion('first', state.namespace)),
+      _glass('b', union: GlassEffectUnion('first', state.namespace)),
+      _glass('c', union: GlassEffectUnion('first', state.namespace)),
+    ]));
+    await tester.pump(const Duration(seconds: 1));
+    final b = _member(tester, 'b'), c = _member(tester, 'c');
+    expect(b.unionOutline!.leads, isFalse);
+    var notified = 0;
+    b.addListener(() => notified++);
+    _state(tester).update(() => _state(tester).shown = false);
+    await tester.pump();
+    expect(notified, greaterThan(0));
+    expect(b.unionOutline!.leads, isTrue);
+    expect(b.unionOutline!.rect, _bounds([b, c]));
+    final ghost = b.coordinator.ghosts.single;
+    expect(ghost.rect.size, const Size(64, 64));
+    expect(ghost.shape, _capsule);
+    await tester.pumpAndSettle();
+    expect(b.coordinator.ghosts, isEmpty);
+  });
+
+  testWidgets('a union left with one member draws that member on its own', (tester) async {
+    await tester.pumpWidget(_Scene(children: (state) => [
+      if (state.shown) _glass('a', union: GlassEffectUnion('first', state.namespace)),
+      _glass('b', union: GlassEffectUnion('first', state.namespace)),
+    ]));
+    await tester.pump(const Duration(seconds: 1));
+    _state(tester).update(() => _state(tester).shown = false);
+    await tester.pump();
+    expect(_member(tester, 'b').unionOutline, isNull);
+    await tester.pumpAndSettle();
+  });
+
+  testWidgets('a union whose id changes in a rebuild leaves the old union and its members notice', (tester) async {
+    await tester.pumpWidget(_Scene(children: (state) => [
+      _glass('a', union: GlassEffectUnion(state.shown ? 'first' : 'second', state.namespace)),
+      _glass('b', union: GlassEffectUnion('first', state.namespace)),
+    ]));
+    await tester.pump(const Duration(seconds: 1));
+    final b = _member(tester, 'b');
+    expect(b.unionOutline, isNotNull);
+    var notified = 0;
+    b.addListener(() => notified++);
+    _state(tester).update(() => _state(tester).shown = false);
+    await tester.pump();
+    expect(notified, greaterThan(0));
+    expect(b.unionOutline, isNull);
+    expect(_member(tester, 'a').unionOutline, isNull);
+  });
+
+  test('a blend group gathers one shape per union, at the union rect and shape, and skips the members it does not lead', () async {
+    final (group, glasses) = await _group([
+      _Motion(const Rect.fromLTWH(0, 0, 20, 20), const GlassUnionOutline(rect: Rect.fromLTWH(0, 0, 60, 20), shape: _capsule, leads: true)),
+      _Motion(const Rect.fromLTWH(0, 0, 20, 20), const GlassUnionOutline(rect: Rect.fromLTWH(-40, 0, 60, 20), shape: _capsule, leads: false)),
+      _Motion(const Rect.fromLTWH(0, 0, 20, 20)),
+    ]);
+    final (_, shapes, changed) = group.gatherShapeData();
+    expect(changed, isTrue);
+    expect(shapes, hasLength(2));
+    expect(shapes[0].renderObject, glasses[0]);
+    expect(shapes[0].shapeBounds, const Rect.fromLTWH(0, 0, 60, 20));
+    expect(shapes[0].shape, _capsule);
+    expect(shapes[1].renderObject, glasses[2]);
+    expect(shapes[1].shapeBounds, const Rect.fromLTWH(40, 0, 20, 20));
+    expect(glasses[0].getPath().getBounds(), const Rect.fromLTWH(0, 0, 60, 20));
+    expect(glasses[1].getPath().getBounds(), Rect.zero);
+  });
+
+  test('a union counts as one shape against the 16-shape cap', () async {
+    final (group, _) = await _group([
+      _Motion(const Rect.fromLTWH(0, 0, 20, 20), const GlassUnionOutline(rect: Rect.fromLTWH(0, 0, 40, 20), shape: _capsule, leads: true)),
+      _Motion(const Rect.fromLTWH(0, 0, 20, 20), const GlassUnionOutline(rect: Rect.fromLTWH(-20, 0, 40, 20), shape: _capsule, leads: false)),
+      for (var i = 0; i < 15; i++) _Motion(const Rect.fromLTWH(0, 0, 20, 20)),
+    ]);
+    final (_, shapes, _) = group.gatherShapeData();
+    expect(shapes, hasLength(LiquidGlassBlendGroup.maxShapesPerLayer));
+  });
+
+  test('a union rect that moves while its leader stays marks the gathered geometry changed', () async {
+    final follower = _Motion(const Rect.fromLTWH(0, 0, 20, 20), const GlassUnionOutline(rect: Rect.fromLTWH(-20, 0, 40, 20), shape: _capsule, leads: false));
+    final leader = _Motion(const Rect.fromLTWH(0, 0, 20, 20), const GlassUnionOutline(rect: Rect.fromLTWH(0, 0, 40, 20), shape: _capsule, leads: true));
+    final (group, _) = await _group([leader, follower]);
+    group.remember();
+    expect(group.gatherShapeData().$3, isFalse);
+    leader.outline = const GlassUnionOutline(rect: Rect.fromLTWH(0, 0, 50, 20), shape: _capsule, leads: true);
+    expect(group.gatherShapeData().$3, isTrue);
+  });
+
+  testWidgets('a union leader paints one shadow on the union rect and shape; the members it leads paint none', (tester) async {
+    const shadow = BoxShadow(color: Color(0x40000000), blurRadius: 6);
+    final leader = _Motion(const Rect.fromLTWH(0, 0, 64, 64), const GlassUnionOutline(rect: Rect.fromLTWH(0, 0, 144, 64), shape: _capsule, leads: true));
+    final follower = _Motion(const Rect.fromLTWH(0, 0, 64, 64), const GlassUnionOutline(rect: Rect.fromLTWH(-80, 0, 144, 64), shape: _capsule, leads: false));
+    await tester.pumpWidget(Directionality(
+      textDirection: TextDirection.ltr,
+      child: Align(
+        alignment: Alignment.topLeft,
+        child: Row(
+          mainAxisSize: MainAxisSize.min,
+          children: [
+            GlassShadow(key: const ValueKey('leader'), shape: _capsule, shadows: const [shadow], settings: const LiquidGlassSettings(), motion: leader, child: const SizedBox.square(dimension: 64)),
+            const SizedBox(width: 16),
+            GlassShadow(key: const ValueKey('follower'), shape: _capsule, shadows: const [shadow], settings: const LiquidGlassSettings(), motion: follower, child: const SizedBox.square(dimension: 64)),
+          ],
+        ),
+      ),
+    ));
+    expect(
+      tester.renderObject(find.byKey(const ValueKey('leader'))),
+      paints..rrect(rrect: RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 144, 64), const Radius.circular(999))),
+    );
+    expect(tester.renderObject(find.byKey(const ValueKey('follower'))), paintsNothing);
+  });
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/render_hooks_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/render_hooks_test.dart
index 7637ef7d4ee508d0f8f36c75f19cd1aad80769ec..2138c469fbeb6d53ec3d39e8466ac2fb3c06fb5f 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/render_hooks_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/render_hooks_test.dart
@@ -19,6 +19,9 @@ class _Motion extends ChangeNotifier implements GlassShapeMotion {
   @override
   Rect resolve(RenderBox shape) => drawn;
 
+  @override
+  GlassUnionOutline? union(RenderBox shape) => null;
+
   void move(Rect rect) {
     drawn = rect;
     notifyListeners();
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t08-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_union_test.dart test/motion/render_hooks_test.dart` => FAIL

Expected output ends with:

```text
test/motion/render_hooks_test.dart:23:3: Error: Type 'GlassUnionOutline' not found.
```

RUN[t08-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/union_scene_test.dart` => FAIL

Expected output ends with:

```text
test/union_scene_test.dart:50:71: Error: The getter 'union' isn't defined for the type 'GlassEffect'.
```

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

Patch `t08-impl` (`599853e52..3a1e5a7f1`, 13 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/CHANGELOG.md b/packages/mobile/packages/ios_liquid_glass/CHANGELOG.md
index e946060b50d21375e4d72a8a14be06fbde3caf75..35af6c731595ce17a68d3b998c9f63068cff1c88 100644
--- a/packages/mobile/packages/ios_liquid_glass/CHANGELOG.md
+++ b/packages/mobile/packages/ios_liquid_glass/CHANGELOG.md
@@ -23,6 +23,7 @@
  - (2B.1) **FIX**: the edge line and sheen keep their full width while the lens ramps with `visibility`; still glass is unchanged.
  - (2B.1) **FIX**: glass at a fractional position draws its rim at its exact position once its geometry is cached, instead of up to half a pixel off.
  - (2B.1) **FEAT**: `debugResetGlassAnimation()` is exported for tests.
+ - (2B.2) **FEAT**: `GlassNamespace` and `GlassEffect(union: GlassEffectUnion(id, namespace))`: glass in one container with the same union, shape and `Glass` draws as one shape on the bounding rect of its members, as SwiftUI's `.glassEffectUnion` does.
 
 ## 0.2.0-dev.4
 
diff --git a/packages/mobile/packages/ios_liquid_glass/FORK.md b/packages/mobile/packages/ios_liquid_glass/FORK.md
index 4c940d97f275de632a20a8a70e76847522d754ac..4b2dffbd42d616e2131ba007456dc55af1284c33 100644
--- a/packages/mobile/packages/ios_liquid_glass/FORK.md
+++ b/packages/mobile/packages/ios_liquid_glass/FORK.md
@@ -94,6 +94,8 @@ The package was renamed from `liquid_glass_renderer` to `ios_liquid_glass`, with
 - `sdf.glsl` replaces upstream's quadratic `smoothUnion` with `angleSmoothUnion`, a quadratic smooth-min with k = blend whose correction is weighted by (1 − n_a · n_b) / 2, the angle between the two shapes' unit gradients. Each shape's gradient is analytic (`getShapeSDFGrad`); the fold carries the blended field's gradient, neglecting the change of the angle weight itself. A blend of 0 is still the plain minimum. `sceneSDF`'s unrolled path for one to four shapes is gone; every count runs the same loop.
 - `LiquidGlassBlendGroup` takes an optional internal `blendMotion` (a `ValueListenable<double>`); `RenderLiquidGlassBlendGroup` listens to it and takes its value as `blend`, so a container's spacing animates with no rebuild. Its own `blend` default stays 20.
 - `GlassEffectContainer.spacing` defaults to 8 pt, native's default, and animates through the container's coordinator.
+- `GlassShapeMotion` gains `union(shape)`, a `GlassUnionOutline` (rect, shape and whether this glass leads its union). `RenderLiquidGlassBlendGroup.gatherShapeData` gathers one shape per union, at the union's rect and shape, from the member that leads it and skips the members it leads, and compares the gathered shapes with the cached ones by their gathered index (upstream compared the cached list with every registered shape, by registration index). `RenderLiquidGlass.getPath` returns the union's path for a leader and an empty path for a member it leads; content is still painted per member at its own drawn rect. The glass shadow draws one shadow on the union's rect and shape from the leader and none from the members it leads.
+- New, not from upstream: `lib/src/api/glass_namespace.dart` (`GlassNamespace`, `GlassEffectUnion`); `GlassEffect(union:)`; `GlassMember.unite`, `unionOutline` and `union` in the coordinator, which notifies a union's members when one of them moves, joins or leaves.
 
 Record every later change to `lib/` in this file.
 
diff --git a/packages/mobile/packages/ios_liquid_glass/README.md b/packages/mobile/packages/ios_liquid_glass/README.md
index b918858c37acbd3e1b2438d9e83a25204b23460c..bf051e46bf965879710be9828374927882f2568d 100644
--- a/packages/mobile/packages/ios_liquid_glass/README.md
+++ b/packages/mobile/packages/ios_liquid_glass/README.md
@@ -32,6 +32,8 @@ The glass is drawn behind the child, in the shape you choose, sized by the child
 | `.glassEffect(.regular.interactive())` | `Glass.regular.interactive()` (the press arrives in a later version) |
 | `.glassEffect(in: .circle)`, `.rect(cornerRadius:)`, capsule | `GlassShape.circle()`, `GlassShape.rect(r)`, `GlassShape.superellipse(r)`, `GlassShape.capsule()` |
 | `GlassEffectContainer(spacing:)`, `GlassEffectContainer()` | `GlassEffectContainer(spacing: 40, child: ...)`, `GlassEffectContainer(child: ...)` (native default, 8 pt) |
+| `@Namespace` | `GlassNamespace()`, created once in a `State` |
+| `.glassEffectUnion(id:namespace:)` | `GlassEffect(union: GlassEffectUnion(id, namespace), ...)` |
 | `.glassEffectTransition(.materialize)`, `.identity` | `GlassEffect(transition: GlassEffectTransition.materialize)`, `GlassEffectTransition.identity` |
 | `Animation.default`, `.snappy`, `.bouncy`, `.smooth` | `GlassAnimation.defaultSpring`, `.snappy`, `.bouncy`, `.smooth` |
 | `.spring(duration:bounce:)`, `.spring(response:dampingFraction:)` | `GlassAnimation.spring(duration:, bounce:)`, `GlassAnimation.dampedSpring(response:, dampingFraction:)` |
@@ -65,6 +67,8 @@ Each glass resolves its material (tone, frost, edge light and shadow) from its d
 
 A container's glass blends with its neighbours as native's does: glass closer than `spacing` deforms toward its neighbour, and joins it into one shape when closer than about half of `spacing`. The shape is a smooth union weighted by the angle between the two shapes' edges, which matches native's necks and bulges on the iOS 27 simulator for spacings from 4 to 80 pt. Shapes blend by their drawn rects, so glass that springs toward or away from its neighbour joins and splits as it moves. A `spacing` change animates like a move: with `withGlassAnimation`'s animation, the nearest `GlassAnimationScope` or the default spring, and a spacing the app changes on consecutive frames follows its value.
 
+Glass in one container that shares a `GlassEffectUnion` (the same id in the same `GlassNamespace`), the same shape and the same `Glass` draws as one shape at any distance, as native's `.glassEffectUnion` does: a shape on the bounding rect of the members' drawn rects, so it follows a member that moves. Circles and capsules become a capsule of that rect, as native draws two 64 pt circles 16 pt apart as one 144 × 64 pt capsule; rounded rectangles and superellipses keep their corner radius. Each member's content stays where that member is laid out. A union counts as one shape against a container's 16 shapes, and blends with the container's other glass by `spacing` like any shape. Glass with the same union id but a different shape or `Glass` forms its own union. A member that is materializing draws on its own and joins its union when it settles; a removed member leaves its union at once and dematerializes on its own. A union needs a container: glass outside one draws on its own whatever its union. The fallback renderer without shader support (`FakeGlass`) draws each member on its own.
+
 ### Theme
 
 `GlassTheme` is optional. Without it, glass follows the platform brightness.
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
index e09739135578ef3bcebd4f62a25907a102cfd258..4f9d2e093a050cff24421e4ae6d6ce38a175fe23 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
@@ -71,25 +71,7 @@ sealed class MaterialScenes {
         ),
       ],
     ),
-    'material.union': (launch) => LabCentered(
-      backdrop: launch.backdrop,
-      children: [
-        GlassEffectContainer(
-          child: Row(
-            mainAxisSize: MainAxisSize.min,
-            children: [
-              for (final (index, icon) in const [Icons.star, Icons.favorite, Icons.bolt, Icons.eco].indexed) ...[
-                if (index > 0) const SizedBox(width: 16),
-                GlassEffect(
-                  shape: const GlassShape.rect(20),
-                  child: SizedBox.square(dimension: 64, child: GlassForeground(child: Icon(icon, size: 24))),
-                ),
-              ],
-            ],
-          ),
-        ),
-      ],
-    ),
+    'material.union': (launch) => UnionScene(backdrop: launch.backdrop),
     'material.morph': (launch) => LabCentered(
       backdrop: launch.backdrop,
       children: [
@@ -221,3 +203,41 @@ class _EdgeSceneState extends State<EdgeScene> {
     );
   }
 }
+
+class UnionScene extends StatefulWidget {
+  const UnionScene({super.key, required this.backdrop});
+
+  static const List<IconData> symbols = [Icons.star, Icons.favorite, Icons.bolt, Icons.eco];
+
+  final String backdrop;
+
+  @override
+  State<UnionScene> createState() => _UnionSceneState();
+}
+
+class _UnionSceneState extends State<UnionScene> {
+  final GlassNamespace _namespace = GlassNamespace();
+
+  @override
+  Widget build(BuildContext context) {
+    return LabCentered(
+      backdrop: widget.backdrop,
+      children: [
+        GlassEffectContainer(
+          child: Row(
+            mainAxisSize: MainAxisSize.min,
+            children: [
+              for (final (index, icon) in UnionScene.symbols.indexed) ...[
+                if (index > 0) const SizedBox(width: 16),
+                GlassEffect(
+                  union: GlassEffectUnion(index < 2 ? 'first' : 'second', _namespace),
+                  child: SizedBox.square(dimension: 64, child: GlassForeground(child: Icon(icon, size: 24))),
+                ),
+              ],
+            ],
+          ),
+        ),
+      ],
+    );
+  }
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/ios_liquid_glass.dart b/packages/mobile/packages/ios_liquid_glass/lib/ios_liquid_glass.dart
index 2fb7205d02fd5dd62721501e2b25eca48731000b..b20dcfff9f6029181fa64b62764e80a96046857e 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/ios_liquid_glass.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/ios_liquid_glass.dart
@@ -10,6 +10,7 @@ export 'src/api/glass_effect.dart' show GlassEffect, GlassEffectScope;
 export 'src/api/glass_effect_container.dart' show GlassEffectContainer;
 export 'src/api/glass_effect_transition.dart' show GlassEffectTransition;
 export 'src/api/glass_foreground.dart' show GlassForeground;
+export 'src/api/glass_namespace.dart' show GlassEffectUnion, GlassNamespace;
 export 'src/api/glass_shape.dart';
 export 'src/api/glass_theme.dart' show GlassTheme, GlassThemeData;
 export 'src/fake_glass.dart' show FakeGlass;
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
index d608dd67864f9ccb2013d29311e12595d43e6d5e..077300b44caf21c2701e5c33e15037b4e92f8ad7 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
@@ -6,6 +6,7 @@ import 'package:ios_liquid_glass/src/api/glass.dart';
 import 'package:ios_liquid_glass/src/api/glass_effect_container.dart';
 import 'package:ios_liquid_glass/src/api/glass_effect_transition.dart';
 import 'package:ios_liquid_glass/src/api/glass_material_context.dart';
+import 'package:ios_liquid_glass/src/api/glass_namespace.dart';
 import 'package:ios_liquid_glass/src/api/glass_shape.dart';
 import 'package:ios_liquid_glass/src/api/glass_theme.dart';
 import 'package:ios_liquid_glass/src/liquid_glass.dart';
@@ -20,6 +21,7 @@ class GlassEffect extends StatefulWidget {
     this.glass = Glass.regular,
     this.shape = const GlassShape.capsule(),
     this.transition = GlassEffectTransition.materialize,
+    this.union,
     this.sideHint,
     required this.child,
   });
@@ -29,6 +31,7 @@ class GlassEffect extends StatefulWidget {
   final Glass glass;
   final GlassShape shape;
   final GlassEffectTransition transition;
+  final GlassEffectUnion? union;
   final double? sideHint;
   final Widget child;
 
@@ -221,7 +224,8 @@ class _GlassEffectState extends State<GlassEffect> with SingleTickerProviderStat
           ..material = material
           ..sharedSettings = grouped ? container.settings : null
           ..reduceMotion = GlassAccessibility.of(context).reduceMotion
-          ..dark = GlassTheme.brightnessOf(context) == Brightness.dark;
+          ..dark = GlassTheme.brightnessOf(context) == Brightness.dark
+          ..unite(widget.union, glass: widget.glass, grouped: grouped && !member.ownsLayer);
         final Widget glass;
         if (grouped && !member.ownsLayer) {
           glass = LiquidGlass.grouped(shape: shape, shadows: material.shadows, shadowSource: material, motion: member, child: content);
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_namespace.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_namespace.dart
new file mode 100644
index 0000000000000000000000000000000000000000..a632de78d8e4ecdba3ce4fed6cb115efb53c3baf
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_namespace.dart
@@ -0,0 +1,19 @@
+import 'package:flutter/foundation.dart';
+
+class GlassNamespace {
+  GlassNamespace();
+}
+
+@immutable
+class GlassEffectUnion {
+  const GlassEffectUnion(this.id, this.namespace);
+
+  final Object id;
+  final GlassNamespace namespace;
+
+  @override
+  bool operator ==(Object other) => other is GlassEffectUnion && other.id == id && identical(other.namespace, namespace);
+
+  @override
+  int get hashCode => Object.hash(id, identityHashCode(namespace));
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/glass_shadow.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/glass_shadow.dart
index 874cf4ccd530eb5b3aadc8e738a817b32e148aaa..0205730bdf2b62302c89f2065c71e32e15e41af8 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/glass_shadow.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/glass_shadow.dart
@@ -151,8 +151,10 @@ class _RenderGlassShadow extends RenderProxyBox {
 
   @override
   void paint(PaintingContext context, Offset offset) {
-    if (shadows.isNotEmpty && visibility > 0) {
-      final rect = (_motion?.resolve(this) ?? Offset.zero & size).shift(offset);
+    final union = _motion?.union(this);
+    if (shadows.isNotEmpty && visibility > 0 && (union == null || union.leads)) {
+      final rect = (union?.rect ?? _motion?.resolve(this) ?? Offset.zero & size).shift(offset);
+      final shape = union?.shape ?? this.shape;
       final canvas = context.canvas;
 
       final needsCutout = shadows.any((s) => s.offset != Offset.zero);
@@ -172,7 +174,7 @@ class _RenderGlassShadow extends RenderProxyBox {
             Path.combine(
               PathOperation.difference,
               Path()..addRect(layerBounds),
-              _shapePath(rect.deflate(.5)),
+              _shapePath(shape, rect.deflate(.5)),
             ),
           );
       }
@@ -190,7 +192,7 @@ class _RenderGlassShadow extends RenderProxyBox {
             )
             .toPaint();
 
-        _drawShape(canvas, shadowRect, paint);
+        _drawShape(canvas, shape, shadowRect, paint);
       }
 
       if (needsCutout) {
@@ -201,7 +203,7 @@ class _RenderGlassShadow extends RenderProxyBox {
     super.paint(context, offset);
   }
 
-  Path _shapePath(Rect rect) => switch (shape) {
+  Path _shapePath(LiquidShape shape, Rect rect) => switch (shape) {
         LiquidRoundedSuperellipse(:final borderRadius) => Path()
           ..addRSuperellipse(
             RSuperellipse.fromRectAndRadius(
@@ -219,7 +221,7 @@ class _RenderGlassShadow extends RenderProxyBox {
           ),
       };
 
-  void _drawShape(Canvas canvas, Rect rect, Paint paint) {
+  void _drawShape(Canvas canvas, LiquidShape shape, Rect rect, Paint paint) {
     switch (shape) {
       case LiquidRoundedSuperellipse(:final borderRadius):
         canvas.drawRSuperellipse(
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass.dart
index cfbbf1d3794b88b751710888a18d156a115123be..fb91ea15171c89c9b70800b13e4423895cc09403 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass.dart
@@ -426,6 +426,8 @@ class RenderLiquidGlass extends RenderProxyBox
 
   Rect get drawnRect => _motion?.resolve(this) ?? Offset.zero & size;
 
+  GlassUnionOutline? get unionOutline => _motion?.union(this);
+
   @override
   void attach(PipelineOwner owner) {
     super.attach(owner);
@@ -504,6 +506,8 @@ class RenderLiquidGlass extends RenderProxyBox
 
   Path getPath() {
     if (_motion == null) return _lastPath;
+    final union = unionOutline;
+    if (union != null) return union.leads ? union.shape.getOuterPath(union.rect) : Path();
     return shape.getOuterPath(drawnRect);
   }
 }
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
index 19ed9049bc665d1b4776b2b857f4f26369fcc4eb..93cfe1968e932d792ee3a08027de2d43038d70d5 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
@@ -304,26 +304,26 @@ class RenderLiquidGlassBlendGroup extends RenderLiquidGlassGeometry
     final shapes = <ShapeGeometry>[];
     final cachedShapes = geometry?.shapes ?? [];
 
-    var anyShapeChangedInLayer =
-        cachedShapes.length != link.shapeEntries.length;
+    var anyShapeChangedInLayer = false;
 
     Rect? layerBounds;
 
-    for (final (
-          index,
-          MapEntry(
-            key: renderObject,
-            value: (shape, glassContainsChild),
-          )
-        ) in link.shapeEntries.indexed) {
+    for (final MapEntry(
+          key: renderObject,
+          value: (shape, glassContainsChild),
+        ) in link.shapeEntries) {
       if (!renderObject.attached || !renderObject.hasSize) continue;
 
       try {
+        final union = renderObject.unionOutline;
+        if (union != null && !union.leads) continue;
         final shapeData = _computeShapeInfo(
           renderObject,
-          shape,
+          union?.shape ?? shape,
           glassContainsChild,
+          union?.rect ?? renderObject.drawnRect,
         );
+        final index = shapes.length;
         shapes.add(shapeData);
 
         layerBounds = layerBounds?.expandToInclude(shapeData.shapeBounds) ??
@@ -343,6 +343,8 @@ class RenderLiquidGlassBlendGroup extends RenderLiquidGlassGeometry
       }
     }
 
+    if (cachedShapes.length != shapes.length) anyShapeChangedInLayer = true;
+
     return (
       (layerBounds ?? Rect.zero).inflate(blend * .25 + settings.outlineWidth + 1),
       shapes,
@@ -376,6 +378,7 @@ class RenderLiquidGlassBlendGroup extends RenderLiquidGlassGeometry
     RenderLiquidGlass renderObject,
     LiquidShape shape,
     bool glassContainsChild,
+    Rect drawnRect,
   ) {
     if (!hasSize) {
       throw StateError(
@@ -396,7 +399,7 @@ class RenderLiquidGlassBlendGroup extends RenderLiquidGlassGeometry
 
     final blendGroupRect = MatrixUtils.transformRect(
       transformToGeometry,
-      renderObject.drawnRect,
+      drawnRect,
     );
 
     return ShapeGeometry(
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
index 6793da200d254f80b7479b554ef6d1b4a1143061..f36a02f1cbd0e8441a7a3823739e196d411af43e 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
@@ -3,6 +3,8 @@ import 'dart:ui' as ui;
 import 'package:flutter/rendering.dart';
 import 'package:flutter/scheduler.dart';
 import 'package:flutter/widgets.dart';
+import 'package:ios_liquid_glass/src/api/glass.dart';
+import 'package:ios_liquid_glass/src/api/glass_namespace.dart';
 import 'package:ios_liquid_glass/src/liquid_glass_settings.dart';
 import 'package:ios_liquid_glass/src/liquid_shape.dart';
 import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
@@ -55,6 +57,7 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
   int _heldFrame = -2;
   GlassAnimation? _requested;
   GlassMotionCoordinator? _ghostOwner;
+  (GlassEffectUnion, LiquidShape, Glass?)? _union;
 
   LiquidGlassSettings? get settings => sharedSettings ?? material?.settings;
 
@@ -86,6 +89,53 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
     return Rect.fromLTWH(live.dx + _offset[0].value, live.dy + _offset[1].value, size.width, size.height);
   }
 
+  void unite(GlassEffectUnion? union, {Glass? glass, required bool grouped}) {
+    final shape = this.shape;
+    final next = union == null || shape == null || !grouped ? null : (union, shape, glass);
+    final previous = _union;
+    if (next == previous) return;
+    _union = next;
+    coordinator._unionChanged(previous);
+    coordinator._unionChanged(next);
+  }
+
+  bool get _drawsInUnion {
+    final box = _box;
+    return _union != null && box != null && box.attached && box.hasSize;
+  }
+
+  GlassUnionOutline? get unionOutline {
+    final key = _union;
+    if (key == null || !_drawsInUnion) return null;
+    Rect? bounds;
+    GlassMember? leader;
+    var count = 0;
+    var counted = false;
+    for (final member in coordinator._members) {
+      if (member._union != key || !member._drawsInUnion) continue;
+      final rect = member.drawn;
+      if (rect == null) continue;
+      leader ??= member;
+      count++;
+      counted = counted || identical(member, this);
+      bounds = bounds?.expandToInclude(rect) ?? rect;
+    }
+    if (bounds == null || count < 2 || !counted) return null;
+    return GlassUnionOutline(rect: bounds, shape: unionShape(key.$2), leads: identical(leader, this));
+  }
+
+  static LiquidShape unionShape(LiquidShape shape) => shape is LiquidOval ? const LiquidRoundedRectangle(borderRadius: 999) : shape;
+
+  @override
+  GlassUnionOutline? union(RenderBox shape) {
+    final outline = unionOutline;
+    final space = coordinator.space;
+    if (outline == null || space == null || !shape.attached || !space.attached) return null;
+    return outline.shift(-MatrixUtils.transformPoint(shape.getTransformTo(space), Offset.zero));
+  }
+
+  void _unionMoved() => notifyListeners();
+
   void attachBox(RenderBox box) => _box = box;
 
   void detachBox(RenderBox box) {
@@ -312,6 +362,7 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
     visibility.value = GlassMaterialize.visibility(progress);
     _resizeMaterial();
     notifyListeners();
+    if (coordinator._members.contains(this)) coordinator._unionChanged(_union, except: this);
   }
 
   void _resizeMaterial() {
@@ -408,6 +459,13 @@ class GlassMotionCoordinator {
 
   Iterable<GlassMember> get members => _members;
 
+  void _unionChanged(Object? union, {GlassMember? except}) {
+    if (union == null) return;
+    for (final member in _members) {
+      if (member._union == union && !identical(member, except)) member._unionMoved();
+    }
+  }
+
   void spacingTo(double target, {GlassAnimation? scope}) {
     final spring = _spacing;
     if (spring == null) {
@@ -483,6 +541,7 @@ class GlassMotionCoordinator {
     }
     final rect = _globalRect(member);
     _members.remove(member);
+    _unionChanged(member._union);
     final ghostOwner = owner ?? this;
     final animation = resolveGlassAnimation(member.scopeAnimation);
     final settings = member.settings, shape = member.shape;
@@ -516,7 +575,9 @@ class GlassMotionCoordinator {
   }
 
   void reattach(GlassMember member) {
-    if (member._ghostOwner == null) _members.add(member);
+    if (member._ghostOwner != null) return;
+    _members.add(member);
+    _unionChanged(member._union);
   }
 
   void _adopt(GlassMember member, _Leaving leaving) {
@@ -535,7 +596,10 @@ class GlassMotionCoordinator {
   void drop(GlassMember member) {
     final leaving = member._ghostOwner?._leaving.remove(member);
     leaving?.release();
-    if (_members.remove(member) || leaving != null) member.dispose();
+    if (_members.remove(member) || leaving != null) {
+      _unionChanged(member._union);
+      member.dispose();
+    }
   }
 
   void rejoin(GlassMember member) {
@@ -544,6 +608,7 @@ class GlassMotionCoordinator {
     leaving.release();
     member._ghostOwner = null;
     _members.add(member);
+    _unionChanged(member._union);
   }
 
   List<GlassGhost> takeGhosts() {
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart
index bb5f8be59d5a10e40b7ece3c1a74f3a3a1ac4ebf..1fd607eb4ac0a23b92a140ce6763869fde692768 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart
@@ -1,7 +1,31 @@
 import 'package:flutter/foundation.dart';
 import 'package:flutter/rendering.dart';
+import 'package:ios_liquid_glass/src/liquid_shape.dart';
 
 @internal
 abstract interface class GlassShapeMotion implements Listenable {
   Rect resolve(RenderBox shape);
+
+  GlassUnionOutline? union(RenderBox shape);
+}
+
+@internal
+@immutable
+class GlassUnionOutline {
+  const GlassUnionOutline({required this.rect, required this.shape, required this.leads});
+
+  final Rect rect;
+  final LiquidShape shape;
+  final bool leads;
+
+  GlassUnionOutline shift(Offset offset) => GlassUnionOutline(rect: rect.shift(offset), shape: shape, leads: leads);
+
+  @override
+  bool operator ==(Object other) => other is GlassUnionOutline && other.rect == rect && other.shape == shape && other.leads == leads;
+
+  @override
+  int get hashCode => Object.hash(rect, shape, leads);
+
+  @override
+  String toString() => 'GlassUnionOutline($rect, $shape, leads: $leads)';
 }
diff --git a/packages/mobile/tool/glass_lab/scenes.json b/packages/mobile/tool/glass_lab/scenes.json
index 1627c97525b60547473a504e063f14dbac1d136f..5dd6bb3876c874b96718f274b00a3334c5acc9bf 100644
--- a/packages/mobile/tool/glass_lab/scenes.json
+++ b/packages/mobile/tool/glass_lab/scenes.json
@@ -689,7 +689,32 @@
       "light",
       "dark"
     ],
-    "steps": []
+    "steps": [],
+    "regions": {
+      "first": [
+        37,
+        407,
+        168,
+        88
+      ],
+      "second": [
+        197,
+        407,
+        168,
+        88
+      ],
+      "pair": [
+        37,
+        407,
+        328,
+        88
+      ]
+    },
+    "topology": [
+      "first",
+      "second",
+      "pair"
+    ]
   },
   {
     "id": "material.morph",
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t08-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_union_test.dart test/motion/render_hooks_test.dart` => PASS

Expected output ends with:

```text
+20: All tests passed!
```

RUN[t08-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/union_scene_test.dart` => PASS

Expected output ends with:

```text
+2: All tests passed!
```

- [ ] **Step 5: Gate: package.**

RUN[t08-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t08-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

Expected output ends with:

```text
+187: All tests passed!
```

- [ ] **Step 6: Gate: example.**

RUN[t08-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t08-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

Expected output ends with:

```text
+19: All tests passed!
```

- [ ] **Step 7: Gate: app.**

RUN[t08-gate-app-analyze]: `cd packages/mobile && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t08-gate-app-test]: `cd packages/mobile && flutter test --no-pub` => PASS

Expected output ends with:

```text
+2188: All tests passed!
```

- [ ] **Step 8: Commit.**

```bash
git add -A packages
git commit -m "feat(ios_liquid_glass): GlassNamespace and GlassEffectUnion; a union draws as one capsule on its members' drawn rects; union scene rebuilt

Co-Authored-By: <the session's attribution line>"
```

### Task 9: A noise pair folder whose link is broken or names another take is pointed at the take it pairs

**Files:**
- Modify: `tool/glass_lab/harness/lab.py`
- Test: `tool/glass_lab/harness/tests/test_lab.py`

**Why.** Ruling 6.

- [ ] **Step 1: Add the failing tests.**

Patch `t09-tests` (`3a1e5a7f1..359eb8e31`, 1 files):

```diff
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_lab.py b/packages/mobile/tool/glass_lab/harness/tests/test_lab.py
index 31de2a59a92810faae6db507658df7bc2c070a22..61d5935d890e7150464d166982010b80319f7069 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_lab.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_lab.py
@@ -171,6 +171,32 @@ class NoiseTests(unittest.TestCase):
         self.assertEqual(len(calls), 12)
         self.assertEqual(worst, {"ready.mad": 1.5, "block.step1e0.progress.rms": 0.01})
 
+    def test_a_pair_folder_left_from_a_removed_take_is_pointed_at_the_take_of_that_number_now(self):
+        import manifest
+        scene = {s.id: s for s in manifest.load()}["material.materialize"]
+        seen = []
+
+        def analyze_pair(scene, case, cache=None):
+            seen.append({side: (case / side).resolve() for side in ("native", "flutter")})
+            return {"static": {}, "measures": {}, "shapes": {"pairs": {}}}
+
+        with tempfile.TemporaryDirectory() as temp:
+            root = Path(temp)
+            takes = []
+            for number in (4, 5):
+                (root / "takes" / str(number)).mkdir(parents=True)
+                takes.append(root / "takes" / str(number))
+            stale = root / "pairs" / "pair-4-5"
+            stale.mkdir(parents=True)
+            (root / "old").mkdir()
+            (stale / "native").symlink_to(root / "old")
+            (stale / "flutter").symlink_to(root / "gone" / "5")
+            with mock.patch.object(lab.analyze, "analyze", side_effect=analyze_pair):
+                lab.case_noise(scene, takes, root / "pairs")
+        self.assertEqual(len(seen), 1)
+        self.assertEqual({seen[0]["native"].name, seen[0]["flutter"].name}, {"4", "5"})
+        self.assertTrue(all(path.parent == (root / "takes").resolve() for path in seen[0].values()))
+
     def test_takes_are_numbered_after_the_ones_already_there(self):
         with tempfile.TemporaryDirectory() as temp:
             for name in ("0", "1", "2", "pair-01"):
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t09-lab-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_lab.py` => FAIL

Expected output ends with:

```text
FAILED (errors=1)
```

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

Patch `t09-impl` (`3a1e5a7f1..359eb8e31`, 1 files):

```diff
diff --git a/packages/mobile/tool/glass_lab/harness/lab.py b/packages/mobile/tool/glass_lab/harness/lab.py
index fba2a1be0f7ab00243866ea26d023cb09ab9d9cb..98fd7c4c6779f5b067e8a4b02efd38125a232bcd 100644
--- a/packages/mobile/tool/glass_lab/harness/lab.py
+++ b/packages/mobile/tool/glass_lab/harness/lab.py
@@ -198,6 +198,8 @@ def case_noise(scene, takes, case_root):
             case.mkdir(parents=True, exist_ok=True)
             for name, source in (("native", takes[i]), ("flutter", takes[j])):
                 link = case / name
+                if link.is_symlink() and (not link.exists() or link.resolve() != source.resolve()):
+                    link.unlink()
                 if not link.exists():
                     link.symlink_to(source.resolve())
             result = analyze.analyze(scene, case, cache=cache)
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t09-lab-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_lab.py` => PASS

Expected output ends with:

```text
Ran 17 tests in <time>
OK
```

- [ ] **Step 5: Gate: harness.**

RUN[t09-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

Expected output ends with:

```text
Ran 228 tests in <time>
OK
```

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "fix(glass_lab): a noise pair folder whose link is broken or names another take is pointed at the take it pairs now

Co-Authored-By: <the session's attribution line>"
```

### Task 10: Appear progress is the spring to a fitted per-preset exponent, fitted on simulated moving glass (H4)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_materialize.dart`, `lib/src/motion/ios27_motion.dart` (the three `ios27*AppearExponent` constants, as `fitvis --write` writes them)
- Modify: `tool/glass_lab/harness/fitvis.py` (`mapped`, `flutter_frames`, `recorded_series`, `moving_score`, `fit_appear_exponent(s)`)
- Test: `test/motion/glass_materialize_test.dart`, `tool/glass_lab/harness/tests/test_fitvis.py`

**Why.** Ruling 22. The exponents are `lab.py fitvis` output (`R/h4/fit-h4.json`, `fitvis-h4.txt`), and the check below compares the committed constants with that file.

- [ ] **Step 1: Add the failing tests.**

Patch `t10-tests` (`6873314df..22df6e970`, 2 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_materialize_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_materialize_test.dart
index e7c1c7e5800d461d535708298c7fdcc37f57eaa5..64ae2829d28b8e37a7bc94fb7c8e42492bdec856 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_materialize_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_materialize_test.dart
@@ -17,6 +17,37 @@ void main() {
     expect(GlassMaterialize.progress(1.2, appearing: false, mapping: mapping), 1);
   });
 
+  test('appearing glass follows its spring to the fitted appear exponent below full and its gain above', () {
+    const shaped = GlassMaterializeMapping(disappearExponent: 3, appearGain: 0.5, appearExponent: 2);
+    expect(GlassMaterialize.progress(0.4, appearing: true, mapping: shaped), closeTo(0.16, 1e-12));
+    expect(GlassMaterialize.progress(1, appearing: true, mapping: shaped), 1);
+    expect(GlassMaterialize.progress(1.08, appearing: true, mapping: shaped), closeTo(1.04, 1e-12));
+    expect(GlassMaterialize.progress(-0.05, appearing: true, mapping: shaped), 0);
+    expect(GlassMaterialize.progress(0.4, appearing: false, mapping: shaped), closeTo(math.pow(0.4, 3), 1e-12));
+    expect(mapping.appearExponent, 1);
+    expect(GlassMaterializeMapping.defaultSpring.appearExponent, ios27DefaultAppearExponent);
+    expect(GlassMaterializeMapping.snappy.appearExponent, ios27SnappyAppearExponent);
+    expect(GlassMaterializeMapping.bouncy.appearExponent, ios27BouncyAppearExponent);
+  });
+
+  test('reversing a shaped appear keeps the visible progress and a continuous rate', () {
+    const shaped = GlassMaterializeMapping(disappearExponent: 3, appearGain: 0.5, appearExponent: 1.6);
+    for (final (presence, velocity) in [(0.6, -2.0), (0.3, -1.5), (0.9, -0.4)]) {
+      final before = GlassMaterialize.progress(presence, appearing: true, mapping: shaped);
+      final (next, nextVelocity) = GlassMaterialize.reverse(presence, velocity, toAppearing: false, from: shaped, to: shaped);
+      expect(GlassMaterialize.progress(next, appearing: false, mapping: shaped), closeTo(before, 1e-9));
+      expect(3 * math.pow(next, 2) * nextVelocity, closeTo(1.6 * math.pow(presence, 0.6) * velocity, 1e-9));
+    }
+    for (final (presence, velocity) in [(0.6, 2.0), (0.3, 1.5)]) {
+      final before = GlassMaterialize.progress(presence, appearing: false, mapping: shaped);
+      final (next, nextVelocity) = GlassMaterialize.reverse(presence, velocity, toAppearing: true, from: shaped, to: shaped);
+      expect(GlassMaterialize.progress(next, appearing: true, mapping: shaped), closeTo(before, 1e-9));
+      expect(1.6 * math.pow(next, 0.6) * nextVelocity, closeTo(3 * math.pow(presence, 2) * velocity, 1e-9));
+    }
+    final (still, stillVelocity) = GlassMaterialize.reverse(0, 0, toAppearing: true, from: shaped, to: shaped);
+    expect((still, stillVelocity), (0.0, 0.0));
+  });
+
   test('under Reduce Motion an appearing glass overshoots by its own fitted gain', () {
     const both = GlassMaterializeMapping(disappearExponent: 3, appearGain: 0.3, reduceMotionAppearGain: 0.8);
     expect(GlassMaterialize.progress(1.1, appearing: true, mapping: both), closeTo(1.03, 1e-12));
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_fitvis.py b/packages/mobile/tool/glass_lab/harness/tests/test_fitvis.py
index 162d0ce1fdd30d02392c933fb05fc0f666810abd..485f4a022ad183a672aaf48227351987b5fc27ea 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_fitvis.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_fitvis.py
@@ -282,6 +282,7 @@ def complete_mapping(**changes):
     def preset(exponent, normal, reduce_motion):
         return {
             "exponent": fitted(exponent),
+            "appear_exponent": fitted(1.5),
             "exponent_cases": {case: fitted(exponent) for case in CASES},
             "gains": {"pooled": normal, "appearances": {"dark": normal, "light": normal}, "cases": {case: normal for case in CASES}},
             "reduce_motion_gains": {"pooled": reduce_motion, "appearances": {"dark": reduce_motion, "light": reduce_motion}, "cases": {f"{case}-reduce-motion": reduce_motion for case in CASES}},
@@ -322,6 +323,8 @@ class TableTests(unittest.TestCase):
         self.assertIn("const double ios27BouncyLightAppearGain = 0.44;", source)
         self.assertIn("const double ios27BouncyDarkReduceMotionAppearGain = 0.76;", source)
         self.assertIn("const double ios27SnappyLightReduceMotionAppearGain = 0.6;", source)
+        self.assertIn("const double ios27DefaultAppearExponent = 1.5;", source)
+        self.assertIn("const double ios27BouncyAppearExponent = 1.5;", source)
         self.assertIn("const List<double> ios27VisibilityForProgress = [\n  0.0, 0.5, 1.0,\n];", source)
         self.assertIn("const List<double> ios27VisibilityAboveFull = [1.1, 1.25];", source)
 
@@ -335,7 +338,7 @@ class TableTests(unittest.TestCase):
         self.assertIn("const double ios27BouncyLightAppearGain = 0.62;", split)
 
     def test_an_unfitted_value_is_never_written_as_a_default(self):
-        for broken in (complete_mapping(**{"material.materialize.bouncy:exponent": None}), complete_mapping(**{"material.materialize.snappy:reduce_motion_gains": None})):
+        for broken in (complete_mapping(**{"material.materialize.bouncy:exponent": None}), complete_mapping(**{"material.materialize.snappy:reduce_motion_gains": None}), complete_mapping(**{"material.materialize:appear_exponent": None})):
             with self.assertRaises(ValueError):
                 fitvis.table_source(broken, 2, [0.0, 0.5, 1.0], [1.1])
         partial = complete_mapping()
@@ -362,13 +365,15 @@ class WriteGuardTests(unittest.TestCase):
             "material.materialize.snappy:gains:pooled": fitted(0.0, at_floor=True),
             "material.materialize.bouncy:reduce_motion_gains:pooled": fitted(1.5, at_grid_edge=True),
             "material.materialize.snappy:exponent": fitted(6.0, at_grid_edge=True),
+            "material.materialize:appear_exponent": None,
+            "material.materialize.snappy:appear_exponent": fitted(3.0, at_grid_edge=True),
         })
         mapping["material.materialize.bouncy"]["gains"]["pooled"] = {"value": 0.44, "identifiable": False, "from": "the normal gain"}
         found = summary(mapping, blur_ramp={"value": 4.0, "at_grid_edge": True, "table": {"1.0": {}, "4.0": {}}}, visibility_above_full=[])
         problems = fitvis.write_problems(found)
         for name in ("ios27BouncyDisappearExponent: not fitted", "ios27SnappyDarkAppearGain = 0.0: on the grid floor", "ios27SnappyLightAppearGain = 0.0: on the grid floor",
                      "ios27BouncyDarkReduceMotionAppearGain = 1.5", "ios27SnappyDisappearExponent = 6.0", "ios27BouncyDarkAppearGain: not fitted",
-                     "ios27BlurRampExponent = 4.0", "ios27VisibilityAboveFull: not fitted"):
+                     "ios27BlurRampExponent = 4.0", "ios27VisibilityAboveFull: not fitted", "ios27DefaultAppearExponent: not fitted", "ios27SnappyAppearExponent = 3.0"):
             self.assertTrue(any(problem.startswith(name) for problem in problems), name)
         with tempfile.TemporaryDirectory() as folder:
             target = Path(folder) / "ios27_motion.dart"
@@ -421,3 +426,123 @@ class WriteGuardTests(unittest.TestCase):
 
 if __name__ == "__main__":
     unittest.main()
+
+
+def moving_rows():
+    return {v: v for v in (0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5)}
+
+
+LINEAR = [round(i / 20, 4) for i in range(21)]
+
+
+def native_events(case, exponent, slope=40.0, keep_first=True, takes=("a", "b"), scene="material.materialize"):
+    response, damping = fitvis.SCENES[scene]
+    times, progress = fitvis.flutter_frames(moving_rows(), LINEAR, [], response, damping, 0.0, exponent)
+    series = fitvis.recorded_series(times, progress, slope, keep_first)
+    return [{"case": case, "take": take, "series": series} for take in takes]
+
+
+class MovingTests(unittest.TestCase):
+    def test_flutter_frames_play_the_scan_at_the_spring_timing_from_the_build_frame(self):
+        times, progress = fitvis.flutter_frames(moving_rows(), LINEAR, [], 0.55, 1.0, 0.0, 2.0)
+        self.assertEqual(times[0], 0.0)
+        self.assertAlmostEqual(times[1], 1 / 60)
+        self.assertEqual(progress[0], 0.0)
+        s = float(springfit.step_response(1 / 60, 0.55, 1.0))
+        self.assertAlmostEqual(progress[1], s ** 2, places=6)
+        self.assertAlmostEqual(fitvis.mapped(np.array([0.4]), True, 3.0, 0.5, 2.0)[0], 0.16)
+        self.assertAlmostEqual(fitvis.mapped(np.array([1.1]), True, 3.0, 0.5, 2.0)[0], 1.05)
+        self.assertAlmostEqual(fitvis.mapped(np.array([0.4]), True, 3.0, 0.5)[0], 0.4)
+
+    def test_the_onset_is_the_first_recorded_frame_whose_change_passes_the_lab_threshold(self):
+        times = np.arange(40) / 60
+        progress = np.minimum(1.0, np.array([0.0, 0.01, 0.05, 0.12, 0.2] + [0.2 + 0.05 * i for i in range(1, 36)]))
+        quiet = fitvis.recorded_series(times, progress, 30.0, True)
+        self.assertAlmostEqual(quiet[0], 0.01)
+        self.assertAlmostEqual(quiet[1], 0.05)
+        dropped = fitvis.recorded_series(times, progress, 30.0, False)
+        self.assertAlmostEqual(dropped[0], 0.0)
+        self.assertAlmostEqual(dropped[1], 0.05)
+        seen = fitvis.recorded_series(times, progress, 80.0, True)
+        self.assertAlmostEqual(seen[0], 0.0)
+        self.assertAlmostEqual(seen[1], 0.01)
+        self.assertAlmostEqual(seen[2], 0.03)
+        self.assertEqual(seen[-1], 1.0)
+
+    def test_the_appear_exponent_that_reproduces_native_moving_glass_is_found(self):
+        events = [e for case in CASES for e in native_events(case, 1.6)]
+        rows = {case: moving_rows() for case in CASES}
+        slopes = {case: 40.0 for case in CASES}
+        found = fitvis.fit_appear_exponent(events, "material.materialize", rows, slopes, LINEAR, [], lambda case: 0.0, {}, outcomes=(True,))
+        self.assertAlmostEqual(found["value"], 1.6, delta=0.026)
+        self.assertFalse(found["at_grid_edge"])
+        self.assertEqual(found["events"], 8)
+        self.assertEqual(found["table"]["1.6"]["failing"], 0.0)
+        self.assertGreater(found["table"]["1.0"]["failing"], 0.0)
+
+    def test_the_score_counts_failures_against_the_noise_limits_over_both_first_frame_outcomes(self):
+        events = native_events("dark-photo", 1.0, slope=400.0)
+        rows, slopes = {"dark-photo": moving_rows()}, {"dark-photo": 400.0}
+        kept = fitvis.moving_score(events, "material.materialize", rows, slopes, LINEAR, [], lambda case: 0.0, 1.0, {}, (True,))
+        dropped = fitvis.moving_score(events, "material.materialize", rows, slopes, LINEAR, [], lambda case: 0.0, 1.0, {}, (False,))
+        both = fitvis.moving_score(events, "material.materialize", rows, slopes, LINEAR, [], lambda case: 0.0, 1.0, {}, (True, False))
+        self.assertEqual(kept["failing"], 0.0)
+        self.assertGreater(dropped["failing"], 0.0)
+        self.assertAlmostEqual(both["failing"], (kept["failing"] + dropped["failing"]) / 2)
+        loose = {"material.materialize": {"dark-photo": {f"block.step3e0.progress.{m}": 1e6 for m in fitvis.MOVING_MEASURES}}}
+        self.assertEqual(fitvis.moving_score(events, "material.materialize", rows, slopes, LINEAR, [], lambda case: 0.0, 1.0, loose, (False,))["failing"], 0.0)
+        self.assertEqual(fitvis.moving_limits({}, "material.materialize", "dark-photo")["response_pct"], 5.0)
+
+    def test_the_slope_is_the_lab_frame_difference_of_full_glass_against_bare(self):
+        from PIL import Image
+        with tempfile.TemporaryDirectory() as folder:
+            for v, value in ((0.0, 10), (1.0, 40)):
+                shot = Path(folder) / "dark-photo" / str(v)
+                shot.mkdir(parents=True)
+                Image.fromarray(np.full((30, 30, 3), value, dtype=np.uint8)).save(shot / "ready.png")
+            self.assertAlmostEqual(fitvis.scan_slopes(folder, (0, 0, 9, 9))["dark-photo"], 30.0)
+
+
+class NativeCurveTests(unittest.TestCase):
+    def test_each_native_event_keeps_the_onset_aligned_series_the_lab_compares(self):
+        from unittest import mock
+
+        class Scene:
+            id = "material.materialize"
+            track = ["block"]
+
+        rows = [{"progress": p, "sharpness": 0.0} for p in (0.0, 0.0, 0.3, 0.7, 1.0, 1.0)]
+        capture = {
+            "rows": {"block": {"times": [0.0, 0.1, 0.2, 0.3, 0.4, 0.5], "rows": rows}},
+            "events": [{"onset": 0.2, "series": {"block": {"progress": [0.0, 0.3, 0.7, 1.0]}}}],
+        }
+        with tempfile.TemporaryDirectory() as folder:
+            native = Path(folder) / "material.materialize" / "dark-photo" / "native"
+            native.mkdir(parents=True)
+            (native / "video.mp4").write_bytes(b"")
+            with mock.patch.object(fitvis.analyze, "window", return_value=(0.0, 1.0, None)), mock.patch.object(fitvis.shapes, "capture", return_value=capture):
+                found = fitvis.native_curves([folder], Scene())
+        self.assertEqual(len(found), 1)
+        self.assertEqual(found[0]["series"], [0.0, 0.3, 0.7, 1.0])
+        self.assertTrue(found[0]["appearing"])
+
+
+class AppearExponentWiringTests(unittest.TestCase):
+    def test_each_preset_gets_an_appear_exponent_from_its_normal_and_reduce_motion_appears_with_their_written_gains(self):
+        normal = {"material.materialize": native_events("dark-photo", 1.4) + [{"case": "dark-photo", "take": "a", "appearing": False, "series": None}]}
+        reduce_motion = {"material.materialize": native_events("dark-photo-reduce-motion", 1.4)}
+        for found in (*normal["material.materialize"], *reduce_motion["material.materialize"]):
+            found.setdefault("appearing", True)
+        mapping = {"material.materialize": {"gains": dict(fitvis.inert_gains()), "reduce_motion_gains": dict(fitvis.inert_gains())}}
+        seen = []
+        original = fitvis.fit_appear_exponent
+
+        def spy(events, scene_id, *args, **kwargs):
+            seen.append(sorted(e["case"] for e in events))
+            return original(events, scene_id, *args, **{**kwargs, "outcomes": (True,)})
+
+        from unittest import mock
+        with mock.patch.object(fitvis, "fit_appear_exponent", side_effect=spy):
+            fitvis.fit_appear_exponents(mapping, normal, reduce_motion, {"dark-photo": moving_rows()}, {"dark-photo": 40.0}, LINEAR, [], {}, "pooled")
+        self.assertEqual(seen, [["dark-photo", "dark-photo", "dark-photo-reduce-motion", "dark-photo-reduce-motion"]])
+        self.assertAlmostEqual(mapping["material.materialize"]["appear_exponent"]["value"], 1.4, delta=0.026)
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t10-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_materialize_test.dart` => FAIL

Expected output ends with:

```text
test/motion/glass_materialize_test.dart:30:43: Error: The getter 'appearExponent' isn't defined for the type 'GlassMaterializeMapping'.
```

RUN[t10-fitvis-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py` => FAIL

Expected output ends with:

```text
FAILED (failures=3, errors=7)
```

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

Patch `t10-impl` (`6873314df..22df6e970`, 3 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_materialize.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_materialize.dart
index 5f12fa84889f3c7a021d9a1b3a501f5476cc44f5..d10f26d5aabb52b1ded706d8a68d55ecefd8e2a8 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_materialize.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_materialize.dart
@@ -9,6 +9,7 @@ import 'package:meta/meta.dart';
 class GlassMaterializeMapping {
   const GlassMaterializeMapping({
     required this.disappearExponent,
+    this.appearExponent = 1,
     required double appearGain,
     double? lightAppearGain,
     double? reduceMotionAppearGain,
@@ -20,6 +21,7 @@ class GlassMaterializeMapping {
 
   static const GlassMaterializeMapping defaultSpring = GlassMaterializeMapping(
     disappearExponent: ios27DefaultDisappearExponent,
+    appearExponent: ios27DefaultAppearExponent,
     appearGain: ios27DefaultDarkAppearGain,
     lightAppearGain: ios27DefaultLightAppearGain,
     reduceMotionAppearGain: ios27DefaultDarkReduceMotionAppearGain,
@@ -27,6 +29,7 @@ class GlassMaterializeMapping {
   );
   static const GlassMaterializeMapping snappy = GlassMaterializeMapping(
     disappearExponent: ios27SnappyDisappearExponent,
+    appearExponent: ios27SnappyAppearExponent,
     appearGain: ios27SnappyDarkAppearGain,
     lightAppearGain: ios27SnappyLightAppearGain,
     reduceMotionAppearGain: ios27SnappyDarkReduceMotionAppearGain,
@@ -34,6 +37,7 @@ class GlassMaterializeMapping {
   );
   static const GlassMaterializeMapping bouncy = GlassMaterializeMapping(
     disappearExponent: ios27BouncyDisappearExponent,
+    appearExponent: ios27BouncyAppearExponent,
     appearGain: ios27BouncyDarkAppearGain,
     lightAppearGain: ios27BouncyLightAppearGain,
     reduceMotionAppearGain: ios27BouncyDarkReduceMotionAppearGain,
@@ -41,6 +45,7 @@ class GlassMaterializeMapping {
   );
 
   final double disappearExponent;
+  final double appearExponent;
   final double darkAppearGain;
   final double lightAppearGain;
   final double darkReduceMotionAppearGain;
@@ -78,7 +83,7 @@ sealed class GlassMaterialize {
   }) {
     if (presence <= 0) return 0;
     if (!appearing) return math.pow(math.min(presence, 1.0), mapping.disappearExponent).toDouble();
-    return presence <= 1 ? presence : 1 + mapping.gain(reduceMotion: reduceMotion, dark: dark) * (presence - 1);
+    return presence <= 1 ? math.pow(presence, mapping.appearExponent).toDouble() : 1 + mapping.gain(reduceMotion: reduceMotion, dark: dark) * (presence - 1);
   }
 
   static double visibility(double progress, {List<double> table = ios27VisibilityForProgress, List<double> above = ios27VisibilityAboveFull}) {
@@ -110,12 +115,14 @@ sealed class GlassMaterialize {
     if (toAppearing) {
       final p = presence.clamp(0.0, 1.0);
       final alpha = math.pow(p, from.disappearExponent).toDouble();
+      if (alpha <= 0) return (0, 0);
       final rate = from.disappearExponent * math.pow(p, from.disappearExponent - 1).toDouble() * velocity;
-      return (alpha, math.max(0, rate));
+      final root = math.pow(alpha, 1 / to.appearExponent).toDouble();
+      return (root, math.max(0, rate / (to.appearExponent * math.pow(root, to.appearExponent - 1).toDouble())));
     }
     final alpha = progress(presence, appearing: true, mapping: from, reduceMotion: reduceMotion, dark: dark).clamp(0.0, 1.0);
     if (alpha <= 0) return (0, 0);
-    final rate = velocity * (presence > 1 ? from.gain(reduceMotion: reduceMotion, dark: dark) : 1);
+    final rate = velocity * (presence > 1 ? from.gain(reduceMotion: reduceMotion, dark: dark) : from.appearExponent * math.pow(presence, from.appearExponent - 1).toDouble());
     final root = math.pow(alpha, 1 / to.disappearExponent).toDouble();
     return (root, math.min(0, rate / (to.disappearExponent * math.pow(root, to.disappearExponent - 1).toDouble())));
   }
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart
index 1d11fb82e1fa50296a7c623e321dc792baece0b3..dc20888ca88d834962c95338ed831502dc594ec7 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart
@@ -1,16 +1,19 @@
 const double ios27BlurRampExponent = 1.0;
 
 const double ios27DefaultDisappearExponent = 3.1;
+const double ios27DefaultAppearExponent = 1.85;
 const double ios27DefaultDarkAppearGain = 0.0;
 const double ios27DefaultLightAppearGain = 0.0;
 const double ios27DefaultDarkReduceMotionAppearGain = 0.0;
 const double ios27DefaultLightReduceMotionAppearGain = 0.0;
 const double ios27SnappyDisappearExponent = 2.75;
+const double ios27SnappyAppearExponent = 1.95;
 const double ios27SnappyDarkAppearGain = 0.44;
 const double ios27SnappyLightAppearGain = 0.44;
 const double ios27SnappyDarkReduceMotionAppearGain = 0.6;
 const double ios27SnappyLightReduceMotionAppearGain = 0.6;
 const double ios27BouncyDisappearExponent = 2.7;
+const double ios27BouncyAppearExponent = 2.45;
 const double ios27BouncyDarkAppearGain = 0.5;
 const double ios27BouncyLightAppearGain = 0.5;
 const double ios27BouncyDarkReduceMotionAppearGain = 0.8;
diff --git a/packages/mobile/tool/glass_lab/harness/fitvis.py b/packages/mobile/tool/glass_lab/harness/fitvis.py
index fb045218beeaea013d1117e80c673fd286a823af..1c675bf1760acfec5519d8407ed77775be29f36a 100644
--- a/packages/mobile/tool/glass_lab/harness/fitvis.py
+++ b/packages/mobile/tool/glass_lab/harness/fitvis.py
@@ -3,6 +3,7 @@ from pathlib import Path
 
 import numpy as np
 
+import align
 import analyze
 import build
 import manifest
@@ -40,6 +41,12 @@ SHARPNESS_AT = (0.25, 0.5, 0.75)
 SHARPNESS_BIN = 0.1
 SPRING_TOLERANCE = (0.05, 0.05)
 OUTLIER_RMS = 0.1
+FRAME_HZ = 60.0
+FRAME_SECONDS = 2.0
+APPEAR_EXPONENTS = np.arange(1.0, 3.0001, 0.05)
+MOVING_MEASURES = ("t10_90_ms", "settle_ms", "overshoot_pct", "response_pct", "damping", "rms")
+FIRST_FRAME_OUTCOMES = (True, False)
+NOISE = manifest.LAB / "noise.json"
 
 
 def levels(count=LEVELS):
@@ -88,13 +95,14 @@ def native_curves(roots, scene):
             t, a = times[chosen] - event["onset"], values[chosen]
             if len(t) < 4:
                 continue
-            curves.append({"case": case, "take": take, "appearing": bool(a[-1] > a[0]), "t": t, "alpha": a, "sharpness": sharpness[chosen]})
+            series = event.get("series", {}).get(scene.track[0], {}).get("progress")
+            curves.append({"case": case, "take": take, "appearing": bool(a[-1] > a[0]), "t": t, "alpha": a, "sharpness": sharpness[chosen], "series": series})
     return curves
 
 
-def mapped(s, appearing, exponent, gain):
+def mapped(s, appearing, exponent, gain, appear_exponent=1.0):
     if appearing:
-        return np.where(s <= 1, np.maximum(s, 0.0), 1 + gain * (s - 1))
+        return np.where(s <= 1, np.maximum(s, 0.0) ** appear_exponent, 1 + gain * (s - 1))
     return np.clip(1 - s, 0.0, 1.0) ** exponent
 
 
@@ -348,6 +356,115 @@ def spring_check(curves, mapping, scene_id=DEFAULT_SCENE):
     return result
 
 
+def flutter_frames(rows, table, above, response, damping, gain, appear_exponent, hz=FRAME_HZ, seconds=FRAME_SECONDS):
+    visibilities = sorted(rows)
+    progress = np.maximum.accumulate([rows[v] for v in visibilities])
+    times = np.arange(int(round(seconds * hz))) / hz
+    alpha = mapped(springfit.step_response(times, response, damping), True, 1.0, gain, appear_exponent)
+    return times, np.interp([visibility(a, table, above) for a in alpha], visibilities, progress)
+
+
+def recorded_series(times, progress, slope, keep_first):
+    kept = [i for i in range(len(times)) if keep_first or i != 1]
+    stamps, values = [float(times[i]) for i in kept], [float(progress[i]) for i in kept]
+    diffs = [0.0] + [abs(b - a) * slope for a, b in zip(values, values[1:])]
+    found = align.events(diffs, stamps)
+    if not found:
+        return None
+    first, last = found[0]
+    rows = [{**{key: 0.0 for key in shapes.KEYS}, "progress": value, "sharpness": 0.0, "residual": 0.0} for value in values]
+    return shapes.event_series(stamps, rows, first, last)["progress"]
+
+
+def moving_limits(noise, scene_id, case):
+    found = noise.get(scene_id, {}).get(case, {})
+    return {
+        measure: max(metrics.THRESHOLDS[shapes.LIMITS[measure]], 1.5 * found.get(f"block.step3e0.progress.{measure}", 0.0))
+        for measure in MOVING_MEASURES
+    }
+
+
+def progress_series(values):
+    return {"progress": list(values), "sharpness": [0.0] * len(values), "residual": [0.0] * len(values)}
+
+
+def moving_score(events, scene_id, rows, slopes, table, above, gain_of, appear_exponent, noise, outcomes=FIRST_FRAME_OUTCOMES):
+    response, damping = SCENES[scene_id]
+    failing, ratios, count = 0, [], 0
+    simulated = {}
+    for event in events:
+        case = event["case"]
+        base = base_case(case)
+        if base not in rows or base not in slopes or event.get("series") is None:
+            continue
+        limits = moving_limits(noise, scene_id, case)
+        for keep_first in outcomes:
+            key = (base, gain_of(case), keep_first)
+            if key not in simulated:
+                times, progress = flutter_frames(rows[base], table, above, response, damping, gain_of(case), appear_exponent)
+                simulated[key] = recorded_series(times, progress, slopes[base], keep_first)
+            series = simulated[key]
+            if series is None:
+                continue
+            found = shapes.compare_progress(progress_series(event["series"]), progress_series(series)) or {}
+            count += 1
+            for measure in MOVING_MEASURES:
+                value = found.get(measure, float("inf"))
+                failing += int(not value <= limits[measure])
+                ratios.append(min(value / limits[measure], 10.0) if np.isfinite(value) else 10.0)
+    if not count:
+        return {"failing": float("inf"), "ratio": float("inf"), "pairs": 0}
+    return {"failing": round(failing / count, 4), "ratio": round(float(np.mean(ratios)), 4), "pairs": count}
+
+
+def fit_appear_exponent(events, scene_id, rows, slopes, table, above, gain_of, noise, outcomes=FIRST_FRAME_OUTCOMES):
+    scores = {round(float(a), 2): moving_score(events, scene_id, rows, slopes, table, above, gain_of, float(a), noise, outcomes) for a in APPEAR_EXPONENTS}
+    best = min(scores, key=lambda a: (scores[a]["failing"], scores[a]["ratio"]))
+    return {
+        "value": best,
+        "at_grid_edge": at_edge(best, APPEAR_EXPONENTS),
+        "events": len([e for e in events if e.get("series") is not None]),
+        "objective": "mean failing Done measures per native appear and first-frame outcome, Flutter simulated from the scan at 60 Hz from its build frame; ties by mean value / limit",
+        "table": {str(a): score for a, score in scores.items()},
+    }
+
+
+def fit_appear_exponents(mapping, curves_by_scene, reduce_motion_by_scene, rows, slopes, table, above, noise, mode="pooled"):
+    for scene_id, entry in mapping.items():
+        gains = written_gains(entry, mode)
+
+        def gain_of(case, gains=gains):
+            fit = gains.get(("reduce_motion" if case.endswith("-reduce-motion") else "normal", appearance_of(case)))
+            return float(fit["value"]) if fit else 0.0
+
+        events = [c for c in (*curves_by_scene.get(scene_id, []), *reduce_motion_by_scene.get(scene_id, [])) if c["appearing"]]
+        entry["appear_exponent"] = fit_appear_exponent(events, scene_id, rows, slopes, table, above, gain_of, noise)
+    return mapping
+
+
+def appear_lines(mapping):
+    lines = ["appear exponent (Done measures on simulated moving glass against every native appear, both first-frame outcomes):"]
+    for scene_id, entry in mapping.items():
+        fit = entry.get("appear_exponent")
+        if not fit:
+            continue
+        table = fit["table"]
+        one = table.get("1.0", {})
+        chosen = table[str(fit["value"])]
+        lines.append(f"  {scene_id:28} {fit['value']}  failing per appear {chosen['failing']} (at 1.0: {one.get('failing')}), mean value/limit {chosen['ratio']} (at 1.0: {one.get('ratio')}), {fit['events']} appears{', ON THE GRID EDGE' if fit['at_grid_edge'] else ''}")
+    return lines
+
+
+def scan_slopes(scan_dir, region):
+    rect = track.pixel_rect(region)
+    found = {}
+    for case_dir in sorted(Path(scan_dir).glob("*")):
+        bare, full = case_dir / "0.0" / "ready.png", case_dir / "1.0" / "ready.png"
+        if bare.exists() and full.exists():
+            found[case_dir.name] = metrics.mad(shapes.shrink(track.crop_px(metrics.load(full), rect)), shapes.shrink(track.crop_px(metrics.load(bare), rect)))
+    return found
+
+
 def scan(udid, cases, out, values, ramp):
     folder = Path(out) / f"ramp{ramp}"
     for name in cases:
@@ -559,6 +676,9 @@ def table_values(mapping, mode):
         if not entry.get("exponent"):
             raise ValueError(f"{scene_id} disappear exponent: not fitted")
         values[f"ios27{name}DisappearExponent"] = float(entry["exponent"]["value"])
+        if not entry.get("appear_exponent"):
+            raise ValueError(f"{scene_id} appear exponent: not fitted")
+        values[f"ios27{name}AppearExponent"] = float(entry["appear_exponent"]["value"])
         gains = written_gains(entry, mode) if "gains" in entry else legacy_gains(entry)
         for (key, appearance), fit in gains.items():
             label = f"ios27{name}{appearance.title()}{'ReduceMotion' if key == 'reduce_motion' else ''}AppearGain"
@@ -634,6 +754,11 @@ def write_problems(summary, allowed=(), recorded=None):
             found.append(f"ios27{name}DisappearExponent: not fitted")
         elif exponent.get("at_grid_edge"):
             found.append(f"ios27{name}DisappearExponent = {exponent['value']}: on the grid edge")
+        appear = entry.get("appear_exponent")
+        if not appear:
+            found.append(f"ios27{name}AppearExponent: not fitted")
+        elif appear.get("at_grid_edge"):
+            found.append(f"ios27{name}AppearExponent = {appear['value']}: on the grid edge")
         for (key, appearance), fit in written_gains(entry, mode).items():
             label = f"ios27{name}{appearance.title()}{'ReduceMotion' if key == 'reduce_motion' else ''}AppearGain"
             if not fit:
@@ -676,6 +801,11 @@ def run(udid, roots, out, count=LEVELS, write=False, ramps=RAMPS, mode="pooled",
     table, mean = invert(progress)
     above, above_mean = invert_above(progress)
     fit_gains(mapping, curves, reduce_motion, final, table, above)
+    slopes = scan_slopes(Path(out) / "table" / f"ramp{ramp['value']}", region)
+    noise = json.loads(NOISE.read_text()) if NOISE.exists() else {}
+    fit_appear_exponents(mapping, curves, reduce_motion, progress, slopes, table, above, noise, mode)
+    for line in appear_lines(mapping):
+        print(line)
     check = spring_check(curves[DEFAULT_SCENE], mapping)
     summary = {
         "roots": [str(root) for root in roots],
@@ -691,6 +821,7 @@ def run(udid, roots, out, count=LEVELS, write=False, ramps=RAMPS, mode="pooled",
         "flutter_progress_mean_above_full": above_mean,
         "visibility_for_progress": table,
         "visibility_above_full": above,
+        "scan_slopes": {case: round(value, 4) for case, value in slopes.items()},
     }
     recorded = []
     problems = write_problems(summary, allowed, recorded)
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t10-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_materialize_test.dart` => PASS

Expected output ends with:

```text
+10: All tests passed!
```

RUN[t10-fitvis-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py` => PASS

Expected output ends with:

```text
Ran 38 tests in <time>
OK
```

- [ ] **Step 5: Check the committed exponents are `fitvis`'s fitted values (`h4/fit-h4.json`).**

RUN[t10-table]: `python3 -c "import json,re; m=json.load(open('docs/liquid_glass/02b-motion/research/proto-2b2/h4/fit-h4.json'))['mapping']; t=open('packages/mobile/packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart').read(); w={'material.materialize':'Default','material.materialize.snappy':'Snappy','material.materialize.bouncy':'Bouncy'}; print([(n, m[k]['appear_exponent']['value'], float(re.search('ios27'+n+'AppearExponent = ([0-9.]+)',t).group(1))) for k,n in w.items()])"` => PASS

Expected output ends with:

```text
[('Default', 1.85, 1.85), ('Snappy', 1.95, 1.95), ('Bouncy', 2.45, 2.45)]
```

- [ ] **Step 6: Gate: package.**

RUN[t10-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t10-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

Expected output ends with:

```text
+189: All tests passed!
```

- [ ] **Step 7: Gate: harness.**

RUN[t10-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

Expected output ends with:

```text
Ran 235 tests in <time>
OK
```

- [ ] **Step 8: Commit.**

```bash
git add -A packages
git commit -m "feat(materialize): appear progress is the spring to a fitted per-preset exponent, fitted on simulated moving glass (H4)

Co-Authored-By: <the session's attribution line>"
```

### Task 11: `GlassEffectID` and matched-geometry morph: partner morph, emergence from the nearest glass, sink or dematerialize, content blur, the morph scenes (M6)

**Files:**
- Create: `packages/ios_liquid_glass/lib/src/motion/glass_morph_geometry.dart`; `example/lib/lab/scenes/morph_scenes.dart`
- Modify: `lib/ios_liquid_glass.dart`, `lib/src/api/{glass_effect,glass_effect_transition,glass_namespace}.dart`, `lib/src/motion/{glass_motion_coordinator,glass_motion_widgets,ios27_motion}.dart`, `FORK.md`, `README.md`; example `lib/lab/scenes/material_scenes.dart`; `tool/glass_lab/scenes.json` (`material.morph`, `.plain`)
- Test: `test/motion/glass_morph_test.dart`, example `test/morph_scene_test.dart`

**Why.** Rulings 18–21.

- [ ] **Step 1: Add the failing tests.**

Patch `t11-tests` (`c8121c7aa..f4039bea6`, 2 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/example/test/morph_scene_test.dart b/packages/mobile/packages/ios_liquid_glass/example/test/morph_scene_test.dart
new file mode 100644
index 0000000000000000000000000000000000000000..72c94b8a770fdb7572238703ff94354058f8a1ce
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/example/test/morph_scene_test.dart
@@ -0,0 +1,86 @@
+import 'dart:convert';
+import 'dart:io';
+
+import 'package:flutter/material.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+import 'package:ios_liquid_glass_example/lab/glass_lab_launch.dart';
+import 'package:ios_liquid_glass_example/lab/glass_lab_screen.dart';
+
+const Size _screen = Size(402, 874);
+
+Map<String, dynamic> _entry(String id) => (jsonDecode(File('../../../tool/glass_lab/scenes.json').readAsStringSync()) as List<dynamic>)
+    .cast<Map<String, dynamic>>()
+    .singleWhere((entry) => entry['id'] == id);
+
+Rect _region(Map<String, dynamic> entry, String name) {
+  final values = (entry['regions'][name] as List<dynamic>).cast<num>();
+  return Rect.fromLTWH(values[0].toDouble(), values[1].toDouble(), values[2].toDouble(), values[3].toDouble());
+}
+
+Future<void> _show(WidgetTester tester, String scene) async {
+  tester.view.physicalSize = _screen * 3;
+  tester.view.devicePixelRatio = 3;
+  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
+  addTearDown(tester.view.reset);
+  await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: scene))));
+  await tester.pump(const Duration(seconds: 1));
+  await tester.pumpAndSettle();
+}
+
+List<Rect> _rects(WidgetTester tester) => [for (final glass in tester.widgetList<GlassEffect>(find.byType(GlassEffect))) tester.getRect(find.byWidget(glass))];
+
+void main() {
+  tearDown(debugResetGlassAnimation);
+
+  for (final (scene, interactive) in [('material.morph', true), ('material.morph.plain', false)]) {
+    testWidgets('$scene lays out native MorphScene: a 56 pt toggle at y 451 that expands into three badges above it, 16 pt apart, in a spacing 20 container', (tester) async {
+      await _show(tester, scene);
+      final toggle = tester.widget<GlassEffect>(find.byType(GlassEffect));
+      expect(_rects(tester), [const Rect.fromLTWH(173, 423, 56, 56)]);
+      expect(toggle.glass, interactive ? Glass.regular.interactive() : Glass.regular);
+      expect(toggle.id!.id, 'toggle');
+      expect(toggle.effectiveTransition, GlassEffectTransition.matchedGeometry);
+      expect(toggle.shape, const GlassShape.capsule());
+      expect(tester.widget<GlassEffectContainer>(find.byType(GlassEffectContainer)).spacing, 20);
+      expect(find.byIcon(Icons.add), findsOneWidget);
+      await tester.tap(find.bySemanticsIdentifier('morph'));
+      await tester.pumpAndSettle();
+      final glasses = tester.widgetList<GlassEffect>(find.byType(GlassEffect)).toList();
+      expect([for (final glass in glasses) glass.id!.id], ['star.fill', 'heart.fill', 'bolt.fill', 'toggle']);
+      expect(glasses.map((glass) => glass.id!.namespace).toSet(), hasLength(1));
+      expect(glasses.map((glass) => glass.transition).toSet(), {null});
+      expect(_rects(tester), [for (final top in [315.0, 387.0, 459.0, 531.0]) Rect.fromLTWH(173, top, 56, 56)]);
+      expect([for (final icon in tester.widgetList<Icon>(find.byType(Icon))) icon.icon], [Icons.star, Icons.favorite, Icons.bolt, Icons.close]);
+      expect(tester.widgetList<Icon>(find.byType(Icon)).map((icon) => icon.size).toSet(), {22});
+      await tester.tap(find.bySemanticsIdentifier('morph'));
+      await tester.pumpAndSettle();
+      expect(_rects(tester), [const Rect.fromLTWH(173, 423, 56, 56)]);
+    });
+  }
+
+  testWidgets('material.tap is one 56 pt interactive glass button at y 451 whose tap changes nothing', (tester) async {
+    await _show(tester, 'material.tap');
+    final glass = tester.widget<GlassEffect>(find.byType(GlassEffect));
+    expect(glass.glass, Glass.regular.interactive());
+    expect(_rects(tester), [const Rect.fromLTWH(173, 423, 56, 56)]);
+    expect(tester.widget<GlassEffectContainer>(find.byType(GlassEffectContainer)).spacing, 20);
+    await tester.tap(find.bySemanticsIdentifier('glass'));
+    await tester.pumpAndSettle();
+    expect(_rects(tester), [const Rect.fromLTWH(173, 423, 56, 56)]);
+  });
+
+  test('the morph manifest tracks the toggle at both of its rests and each badge, and judges the stack topology', () {
+    final entry = _entry('material.morph');
+    expect(entry['track'], ['star', 'heart', 'bolt', 'toggle', 'collapsed']);
+    expect(entry['topology'], ['stack']);
+    expect(_region(entry, 'collapsed').center, const Offset(201, 451));
+    expect(_region(entry, 'toggle').center, const Offset(201, 559));
+    expect(_region(entry, 'star').center, const Offset(201, 343));
+    expect(_region(entry, 'heart').center, const Offset(201, 415));
+    expect(_region(entry, 'bolt').center, const Offset(201, 487));
+    expect(_region(entry, 'stack').top, lessThanOrEqualTo(315 - 12));
+    expect(_region(entry, 'stack').bottom, greaterThanOrEqualTo(587 + 12));
+    expect((entry['steps'] as List<dynamic>).where((step) => (step as Map).containsKey('tap')).map((step) => (step as Map)['tap']), ['morph', 'morph']);
+  });
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_morph_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_morph_test.dart
new file mode 100644
index 0000000000000000000000000000000000000000..1b341b9d200e4e2697b1362e943e2e4cf5ecf09b
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_morph_test.dart
@@ -0,0 +1,424 @@
+import 'package:flutter/material.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
+import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
+import 'package:ios_liquid_glass/src/shaders.dart';
+
+const List<String> _badges = ['star', 'heart', 'bolt'];
+
+class _Morph extends StatefulWidget {
+  const _Morph({this.badge = 56, this.transition, this.ids = true});
+
+  final double badge;
+  final GlassEffectTransition? transition;
+  final bool ids;
+
+  @override
+  State<_Morph> createState() => _MorphState();
+}
+
+class _MorphState extends State<_Morph> {
+  final GlassNamespace namespace = GlassNamespace();
+  bool expanded = false;
+
+  void toggle() => withGlassAnimation(GlassAnimation.defaultSpring, () => setState(() => expanded = !expanded));
+
+  Widget _glass(String name, double side) => GlassEffect(
+    key: ValueKey(name),
+    id: widget.ids ? GlassEffectID(name, namespace) : null,
+    transition: name == 'toggle' ? null : widget.transition,
+    child: SizedBox.square(dimension: side, child: const ColoredBox(color: Color(0xFFFF0000))),
+  );
+
+  @override
+  Widget build(BuildContext context) {
+    return MaterialApp(
+      home: GlassTheme(
+        data: const GlassThemeData(brightness: Brightness.dark),
+        child: Center(
+          child: GlassEffectContainer(
+            spacing: 20,
+            child: Column(
+              mainAxisSize: MainAxisSize.min,
+              children: [
+                if (expanded)
+                  for (final name in _badges) ...[_glass(name, widget.badge), const SizedBox(height: 16)],
+                _glass('toggle', 56),
+              ],
+            ),
+          ),
+        ),
+      ),
+    );
+  }
+}
+
+class _Swap extends StatefulWidget {
+  const _Swap();
+
+  @override
+  State<_Swap> createState() => _SwapState();
+}
+
+class _SwapState extends State<_Swap> {
+  final GlassNamespace namespace = GlassNamespace();
+  bool first = true;
+
+  void swap() => setState(() => first = !first);
+
+  @override
+  Widget build(BuildContext context) {
+    return MaterialApp(
+      home: GlassTheme(
+        data: const GlassThemeData(brightness: Brightness.dark),
+        child: Align(
+          alignment: Alignment.topLeft,
+          child: GlassEffectContainer(
+            child: SizedBox(
+              width: 600,
+              height: 400,
+              child: Stack(
+                children: [
+                  if (first)
+                    Positioned(
+                      left: 20,
+                      top: 20,
+                      child: GlassEffect(
+                        key: const ValueKey('a'),
+                        id: GlassEffectID('x', namespace),
+                        child: const SizedBox(width: 100, height: 40, child: ColoredBox(color: Color(0xFFFF0000))),
+                      ),
+                    )
+                  else
+                    Positioned(
+                      left: 300,
+                      top: 200,
+                      child: GlassEffect(
+                        key: const ValueKey('b'),
+                        id: GlassEffectID('x', namespace),
+                        child: const SizedBox(width: 200, height: 80, child: ColoredBox(color: Color(0xFF00FF00))),
+                      ),
+                    ),
+                ],
+              ),
+            ),
+          ),
+        ),
+      ),
+    );
+  }
+}
+
+class _Row extends StatefulWidget {
+  const _Row();
+
+  @override
+  State<_Row> createState() => _RowState();
+}
+
+class _RowState extends State<_Row> {
+  final GlassNamespace namespace = GlassNamespace();
+  bool shown = false;
+
+  void toggle() => setState(() => shown = !shown);
+
+  Widget _glass(String name) => GlassEffect(key: ValueKey(name), id: GlassEffectID(name, namespace), child: const SizedBox.square(dimension: 40));
+
+  @override
+  Widget build(BuildContext context) {
+    return MaterialApp(
+      home: GlassTheme(
+        data: const GlassThemeData(brightness: Brightness.dark),
+        child: Align(
+          alignment: Alignment.topLeft,
+          child: GlassEffectContainer(
+            spacing: 20,
+            child: Row(
+              mainAxisSize: MainAxisSize.min,
+              children: [
+                _glass('a'),
+                const SizedBox(width: 200),
+                _glass('b'),
+                if (shown) ...[const SizedBox(width: 16), _glass('c')],
+              ],
+            ),
+          ),
+        ),
+      ),
+    );
+  }
+}
+
+GlassMember _member(WidgetTester tester, String key) => tester
+    .renderObject<RenderGlassMemberBox>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(GlassMemberBox)).first)
+    .member;
+
+Rect _onScreen(GlassMember member) => MatrixUtils.transformRect(member.coordinator.space!.getTransformTo(null), member.drawn!);
+
+Rect _layout(WidgetTester tester, String key) => tester.getRect(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(GlassMemberBox)).first);
+
+GlassMotionCoordinator _coordinator(WidgetTester tester, String key) => _member(tester, key).coordinator;
+
+Iterable<LiquidGlassLayer> _layers(WidgetTester tester) => tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer));
+
+void _expectRect(Rect actual, Rect expected, [double tolerance = 1e-6]) {
+  expect(actual.left, closeTo(expected.left, tolerance));
+  expect(actual.top, closeTo(expected.top, tolerance));
+  expect(actual.width, closeTo(expected.width, tolerance));
+  expect(actual.height, closeTo(expected.height, tolerance));
+}
+
+double _gap(Rect a, Rect b) => (a.center - b.center).distance - a.shortestSide / 2 - b.shortestSide / 2;
+
+void main() {
+  isLocalTest = true;
+  tearDown(debugResetGlassAnimation);
+  tearDown(GlassAccessibility.debugReset);
+
+  test('a glass id is equal to another with the same id in the same namespace, and to no other', () {
+    final namespace = GlassNamespace();
+    expect(GlassEffectID('a', namespace), GlassEffectID('a', namespace));
+    expect(GlassEffectID('a', namespace).hashCode, GlassEffectID('a', namespace).hashCode);
+    expect(GlassEffectID('a', namespace), isNot(GlassEffectID('b', namespace)));
+    expect(GlassEffectID('a', namespace), isNot(GlassEffectID('a', GlassNamespace())));
+    expect(GlassEffectID('a', namespace), isNot(GlassEffectUnion('a', namespace)));
+  });
+
+  test('a glass with an id and no transition morphs, and a glass without one materializes', () {
+    final namespace = GlassNamespace();
+    expect(const GlassEffect(child: SizedBox()).effectiveTransition, GlassEffectTransition.materialize);
+    expect(GlassEffect(id: GlassEffectID('a', namespace), child: const SizedBox()).effectiveTransition, GlassEffectTransition.matchedGeometry);
+    expect(
+      GlassEffect(id: GlassEffectID('a', namespace), transition: GlassEffectTransition.materialize, child: const SizedBox()).effectiveTransition,
+      GlassEffectTransition.materialize,
+    );
+    expect(const GlassEffect(transition: GlassEffectTransition.identity, child: SizedBox()).effectiveTransition, GlassEffectTransition.identity);
+  });
+
+  testWidgets('an appearing glass with an id starts on the glass it emerges from, at full visibility in the shared layer, and springs to its layout', (tester) async {
+    await tester.pumpWidget(const _Morph());
+    await tester.pump(const Duration(seconds: 1));
+    final before = _onScreen(_member(tester, 'toggle'));
+    tester.state<_MorphState>(find.byType(_Morph)).toggle();
+    await tester.pump();
+    for (final name in _badges) {
+      _expectRect(_onScreen(_member(tester, name)), before);
+      expect(_member(tester, name).presence, GlassPresence.present);
+    }
+    _expectRect(_onScreen(_member(tester, 'toggle')), before);
+    expect(_layers(tester), hasLength(1));
+    await tester.pump(const Duration(milliseconds: 100));
+    final heart = _onScreen(_member(tester, 'heart'));
+    expect(heart.center.dy, lessThan(before.center.dy));
+    expect(heart.center.dy, greaterThan(_layout(tester, 'heart').center.dy));
+    expect(_layers(tester), hasLength(1));
+    await tester.pumpAndSettle();
+    for (final name in [..._badges, 'toggle']) {
+      _expectRect(_onScreen(_member(tester, name)), _layout(tester, name));
+    }
+  });
+
+  testWidgets('an appearing glass emerges from the nearest present glass', (tester) async {
+    await tester.pumpWidget(const _Row());
+    await tester.pump(const Duration(seconds: 1));
+    final b = _onScreen(_member(tester, 'b'));
+    tester.state<_RowState>(find.byType(_Row)).toggle();
+    await tester.pump();
+    _expectRect(_onScreen(_member(tester, 'c')), b);
+    await tester.pumpAndSettle();
+    _expectRect(_onScreen(_member(tester, 'c')), _layout(tester, 'c'));
+  });
+
+  testWidgets('normal motion starts an appearing glass at the size of its source, Reduce Motion at its own size', (tester) async {
+    await tester.pumpWidget(const _Morph(badge: 40));
+    await tester.pump(const Duration(seconds: 1));
+    final before = _onScreen(_member(tester, 'toggle'));
+    tester.state<_MorphState>(find.byType(_Morph)).toggle();
+    await tester.pump();
+    _expectRect(_onScreen(_member(tester, 'heart')), before);
+    await tester.pumpAndSettle();
+    tester.state<_MorphState>(find.byType(_Morph)).toggle();
+    await tester.pumpAndSettle();
+    GlassAccessibility.platform.value = const GlassAccessibilityData(reduceMotion: true);
+    await tester.pump();
+    final collapsed = _onScreen(_member(tester, 'toggle'));
+    tester.state<_MorphState>(find.byType(_Morph)).toggle();
+    await tester.pump();
+    _expectRect(_onScreen(_member(tester, 'heart')), Rect.fromCenter(center: collapsed.center, width: 40, height: 40));
+  });
+
+  testWidgets('a morphing glass keeps its content blurred until it separates from the other glass of the morph, then sharpens in one frame', (tester) async {
+    await tester.pumpWidget(const _Morph());
+    await tester.pump(const Duration(seconds: 1));
+    for (final name in ['toggle']) {
+      expect(_member(tester, name).contentBlurred.value, isFalse);
+    }
+    tester.state<_MorphState>(find.byType(_Morph)).toggle();
+    await tester.pump();
+    final names = [..._badges, 'toggle'];
+    for (final name in names) {
+      expect(_member(tester, name).contentBlurred.value, isTrue, reason: name);
+      expect(_member(tester, name).contentOpacity.value, 1, reason: name);
+    }
+    final sharpened = <String, int>{};
+    for (var frame = 1; frame < 120; frame++) {
+      await tester.pump(const Duration(milliseconds: 8));
+      final rects = {for (final name in names) name: _onScreen(_member(tester, name))};
+      for (final name in names) {
+        final blurred = _member(tester, name).contentBlurred.value;
+        if (sharpened.containsKey(name)) {
+          expect(blurred, isFalse, reason: '$name blurred again');
+          continue;
+        }
+        if (blurred) continue;
+        sharpened[name] = frame;
+        for (final other in names.where((other) => other != name)) {
+          expect(_gap(rects[name]!, rects[other]!), greaterThanOrEqualTo(10 - 1e-6), reason: '$name sharpened while touching $other');
+        }
+      }
+    }
+    expect(sharpened.keys.toSet(), names.toSet());
+  });
+
+  testWidgets('under Reduce Motion an appearing glass fades its content in sharp', (tester) async {
+    GlassAccessibility.platform.value = const GlassAccessibilityData(reduceMotion: true);
+    await tester.pumpWidget(const _Morph());
+    await tester.pump(const Duration(seconds: 1));
+    tester.state<_MorphState>(find.byType(_Morph)).toggle();
+    await tester.pump();
+    expect(_member(tester, 'heart').contentOpacity.value, 0);
+    await tester.pump(const Duration(milliseconds: 150));
+    expect(_member(tester, 'heart').contentOpacity.value, inExclusiveRange(0, 1));
+    for (final name in [..._badges, 'toggle']) {
+      expect(_member(tester, name).contentBlurred.value, isFalse);
+    }
+    await tester.pumpAndSettle();
+    expect(_member(tester, 'heart').contentOpacity.value, 1);
+  });
+
+  testWidgets('a removed glass within spacing of a remaining glass sinks into it in the shared layer; a farther one dematerializes in place', (tester) async {
+    await tester.pumpWidget(const _Morph());
+    await tester.pump(const Duration(seconds: 1));
+    final state = tester.state<_MorphState>(find.byType(_Morph));
+    state.toggle();
+    await tester.pumpAndSettle();
+    final star = _onScreen(_member(tester, 'star'));
+    final heart = _onScreen(_member(tester, 'heart'));
+    final coordinator = _coordinator(tester, 'toggle');
+    state.toggle();
+    await tester.pump();
+    expect(coordinator.ghosts, hasLength(3));
+    await tester.pump(const Duration(milliseconds: 16));
+    final target = _layout(tester, 'toggle').center;
+    final kinds = {for (final ghost in coordinator.ghosts) ghost.rect.center.dy.round(): ghost.kind};
+    expect(kinds[star.center.dy.round()], GlassGhostKind.dematerialize);
+    expect(kinds[heart.center.dy.round()], GlassGhostKind.sink);
+    expect(coordinator.ghosts.where((ghost) => ghost.kind == GlassGhostKind.sink), hasLength(2));
+    expect(_layers(tester), hasLength(2));
+    final sinking = coordinator.ghosts.firstWhere((ghost) => ghost.rect.center.dy.round() == heart.center.dy.round());
+    await tester.pump(const Duration(milliseconds: 60));
+    final now = sinking.current;
+    expect((now.center - target).distance, lessThan((heart.center - target).distance));
+    expect(now.width, lessThan(heart.width));
+    expect(sinking.member.visibility.value, 1);
+    final dematerializing = coordinator.ghosts.firstWhere((ghost) => ghost.kind == GlassGhostKind.dematerialize);
+    _expectRect(dematerializing.current, star);
+    expect(dematerializing.member.visibility.value, lessThan(1));
+    await tester.pumpAndSettle();
+    expect(coordinator.ghosts, isEmpty);
+    expect(_layers(tester), hasLength(1));
+  });
+
+  testWidgets('under Reduce Motion a sinking glass slides into its target at full size', (tester) async {
+    GlassAccessibility.platform.value = const GlassAccessibilityData(reduceMotion: true);
+    await tester.pumpWidget(const _Morph());
+    await tester.pump(const Duration(seconds: 1));
+    final state = tester.state<_MorphState>(find.byType(_Morph));
+    state.toggle();
+    await tester.pumpAndSettle();
+    final heart = _onScreen(_member(tester, 'heart'));
+    final coordinator = _coordinator(tester, 'toggle');
+    state.toggle();
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 16));
+    final target = _layout(tester, 'toggle').center;
+    final sinking = coordinator.ghosts.firstWhere((ghost) => ghost.rect.center.dy.round() == heart.center.dy.round());
+    expect(sinking.kind, GlassGhostKind.sink);
+    await tester.pump(const Duration(milliseconds: 100));
+    expect((sinking.current.center - target).distance, lessThan((heart.center - target).distance));
+    expect(sinking.current.size, heart.size);
+    for (final ghost in coordinator.ghosts) {
+      expect(ghost.blurred, isFalse);
+    }
+    await tester.pumpAndSettle();
+    expect(coordinator.ghosts, isEmpty);
+  });
+
+  testWidgets('removed glass blurs its content at once and the glass it sinks into stays blurred until it has sunk', (tester) async {
+    await tester.pumpWidget(const _Morph());
+    await tester.pump(const Duration(seconds: 1));
+    final state = tester.state<_MorphState>(find.byType(_Morph));
+    state.toggle();
+    await tester.pumpAndSettle();
+    final coordinator = _coordinator(tester, 'toggle');
+    state.toggle();
+    await tester.pump();
+    await tester.pump(const Duration(milliseconds: 16));
+    for (final ghost in coordinator.ghosts) {
+      expect(ghost.blurred, isTrue);
+    }
+    expect(_member(tester, 'toggle').contentBlurred.value, isTrue);
+    while (coordinator.ghosts.any((ghost) => ghost.kind == GlassGhostKind.sink)) {
+      expect(_member(tester, 'toggle').contentBlurred.value, isTrue);
+      await tester.pump(const Duration(milliseconds: 8));
+    }
+    await tester.pump(const Duration(milliseconds: 8));
+    expect(_member(tester, 'toggle').contentBlurred.value, isFalse);
+  });
+
+  testWidgets('a glass with an id and an explicit materialize transition still materializes', (tester) async {
+    await tester.pumpWidget(const _Morph(transition: GlassEffectTransition.materialize));
+    await tester.pump(const Duration(seconds: 1));
+    tester.state<_MorphState>(find.byType(_Morph)).toggle();
+    await tester.pump();
+    expect(_member(tester, 'heart').presence, GlassPresence.appearing);
+    expect(_layers(tester).length, greaterThan(1));
+  });
+
+  testWidgets('glass without an id keeps materializing', (tester) async {
+    await tester.pumpWidget(const _Morph(ids: false));
+    await tester.pump(const Duration(seconds: 1));
+    tester.state<_MorphState>(find.byType(_Morph)).toggle();
+    await tester.pump();
+    expect(_member(tester, 'heart').presence, GlassPresence.appearing);
+  });
+
+  testWidgets('a glass removed and another inserted with the same id in the same frame draw as one glass that springs from the old rect to the new', (tester) async {
+    await tester.pumpWidget(const _Swap());
+    await tester.pump(const Duration(seconds: 1));
+    final old = _onScreen(_member(tester, 'a'));
+    final coordinator = _coordinator(tester, 'a');
+    tester.state<_SwapState>(find.byType(_Swap)).swap();
+    await tester.pump();
+    final member = _member(tester, 'b');
+    _expectRect(_onScreen(member), old);
+    expect(member.presence, GlassPresence.present);
+    expect(coordinator.ghosts, hasLength(1));
+    expect(coordinator.ghosts.single.kind, GlassGhostKind.content);
+    expect(_layers(tester), hasLength(1));
+    expect(member.contentOpacity.value, 0);
+    _expectRect(coordinator.ghosts.single.current, old);
+    await tester.pump(const Duration(milliseconds: 120));
+    final mid = _onScreen(member);
+    expect(mid.left, inExclusiveRange(old.left, 300));
+    expect(mid.width, inExclusiveRange(100, 200));
+    expect(member.contentOpacity.value, inExclusiveRange(0, 1));
+    _expectRect(coordinator.ghosts.single.current, mid);
+    expect(coordinator.ghosts.single.opacity.value, closeTo(1 - member.contentOpacity.value, 1e-9));
+    await tester.pumpAndSettle();
+    _expectRect(_onScreen(member), _layout(tester, 'b'));
+    expect(member.contentOpacity.value, 1);
+    expect(coordinator.ghosts, isEmpty);
+  });
+}
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t11-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_morph_test.dart` => FAIL

Expected output ends with:

```text
test/motion/glass_morph_test.dart:421:19: Error: The getter 'contentOpacity' isn't defined for the type 'GlassMember'.
```

RUN[t11-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/morph_scene_test.dart` => FAIL

Expected output ends with:

```text
test/morph_scene_test.dart:51:43: Error: The getter 'id' isn't defined for the type 'GlassEffect'.
```

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

Patch `t11-impl` (`c8121c7aa..f4039bea6`, 13 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/FORK.md b/packages/mobile/packages/ios_liquid_glass/FORK.md
index 4b2dffbd42d616e2131ba007456dc55af1284c33..64f058987035b72df41860fc5ded563b3b30baa0 100644
--- a/packages/mobile/packages/ios_liquid_glass/FORK.md
+++ b/packages/mobile/packages/ios_liquid_glass/FORK.md
@@ -97,6 +97,11 @@ The package was renamed from `liquid_glass_renderer` to `ios_liquid_glass`, with
 - `GlassShapeMotion` gains `union(shape)`, a `GlassUnionOutline` (rect, shape and whether this glass leads its union). `RenderLiquidGlassBlendGroup.gatherShapeData` gathers one shape per union, at the union's rect and shape, from the member that leads it and skips the members it leads, and compares the gathered shapes with the cached ones by their gathered index (upstream compared the cached list with every registered shape, by registration index). `RenderLiquidGlass.getPath` returns the union's path for a leader and an empty path for a member it leads; content is still painted per member at its own drawn rect. The glass shadow draws one shadow on the union's rect and shape from the leader and none from the members it leads.
 - New, not from upstream: `lib/src/api/glass_namespace.dart` (`GlassNamespace`, `GlassEffectUnion`); `GlassEffect(union:)`; `GlassMember.unite`, `unionOutline` and `union` in the coordinator, which notifies a union's members when one of them moves, joins or leaves.
 
+## ios_liquid_glass 0.1.0, project 2B.2 (morph)
+
+- New, not from upstream: `GlassEffectID` (`lib/src/api/glass_namespace.dart`); `GlassEffectTransition.matchedGeometry`; `GlassEffect(id:)`, whose `transition` is now nullable and resolves through `effectiveTransition` (matched geometry with an id, materialize without); the coordinator's arrivals, partners, sink and content ghosts, nearest-source choice and morph content blur (`glass_motion_coordinator.dart`), `GlassMorphGeometry` (`glass_morph_geometry.dart`, the shape gap on the line between centres), `GlassContentBlur` and `GlassMorphContent` (`glass_motion_widgets.dart`), and `ios27MorphContentBlur` in `ios27_motion.dart`.
+- `GlassGhost` is a `GlassShapeMotion`: a sinking ghost draws through `LiquidGlass.grouped` in its container's blend group at a rect it moves every frame, and the ghost stack places each ghost at `placement` and repaints on the coordinator's `ghostMotion`.
+
 Record every later change to `lib/` in this file.
 
 Upstream: https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer
diff --git a/packages/mobile/packages/ios_liquid_glass/README.md b/packages/mobile/packages/ios_liquid_glass/README.md
index bf051e46bf965879710be9828374927882f2568d..61dcbeba9d3a6227a4e6dff8a4fca83734aede71 100644
--- a/packages/mobile/packages/ios_liquid_glass/README.md
+++ b/packages/mobile/packages/ios_liquid_glass/README.md
@@ -34,7 +34,8 @@ The glass is drawn behind the child, in the shape you choose, sized by the child
 | `GlassEffectContainer(spacing:)`, `GlassEffectContainer()` | `GlassEffectContainer(spacing: 40, child: ...)`, `GlassEffectContainer(child: ...)` (native default, 8 pt) |
 | `@Namespace` | `GlassNamespace()`, created once in a `State` |
 | `.glassEffectUnion(id:namespace:)` | `GlassEffect(union: GlassEffectUnion(id, namespace), ...)` |
-| `.glassEffectTransition(.materialize)`, `.identity` | `GlassEffect(transition: GlassEffectTransition.materialize)`, `GlassEffectTransition.identity` |
+| `.glassEffectID(id, in: namespace)` | `GlassEffect(id: GlassEffectID(id, namespace), ...)` |
+| `.glassEffectTransition(.materialize)`, `.identity`, `.matchedGeometry` | `GlassEffect(transition: GlassEffectTransition.materialize)`, `GlassEffectTransition.identity`, `GlassEffectTransition.matchedGeometry` |
 | `Animation.default`, `.snappy`, `.bouncy`, `.smooth` | `GlassAnimation.defaultSpring`, `.snappy`, `.bouncy`, `.smooth` |
 | `.spring(duration:bounce:)`, `.spring(response:dampingFraction:)` | `GlassAnimation.spring(duration:, bounce:)`, `GlassAnimation.dampedSpring(response:, dampingFraction:)` |
 | `withAnimation(.bouncy) { ... }` | `withGlassAnimation(GlassAnimation.bouncy, () => setState(...))` |
@@ -67,6 +68,13 @@ Each glass resolves its material (tone, frost, edge light and shadow) from its d
 
 A container's glass blends with its neighbours as native's does: glass closer than `spacing` deforms toward its neighbour, and joins it into one shape when closer than about half of `spacing`. The shape is a smooth union weighted by the angle between the two shapes' edges, which matches native's necks and bulges on the iOS 27 simulator for spacings from 4 to 80 pt. Shapes blend by their drawn rects, so glass that springs toward or away from its neighbour joins and splits as it moves. A `spacing` change animates like a move: with `withGlassAnimation`'s animation, the nearest `GlassAnimationScope` or the default spring, and a spacing the app changes on consecutive frames follows its value.
 
+A glass with a `GlassEffectID` and no `transition` morphs (`GlassEffectTransition.matchedGeometry`), as native glass with a `.glassEffectID` does; a glass without one materializes. Morphing glass stays at full brightness and blends with its container's other glass by `spacing` while it moves:
+- **With a partner.** A glass removed and another inserted with the same id in the same container in the same frame draw as one glass: it springs from the removed glass's drawn rect to the inserted one's layout with the animation in force, while the old content fades out over it and the new content fades in.
+- **Appearing without a partner.** The glass emerges from the nearest glass already in the container (the one whose drawn rect is closest to the new glass's layout): it starts on that glass's drawn rect and springs to its own layout. Under Reduce Motion it starts at that glass's centre at its own size, and its content fades in.
+- **Removed without a partner.** A glass whose last rect is within `spacing` of a remaining glass's laid-out rect sinks into it: it moves to that glass's centre at full brightness while it shrinks and its content fades, then is dropped; under Reduce Motion it slides there at full size. A glass farther away dematerializes in place.
+- **Content.** The content of every glass in a morph is blurred from the change until its glass no longer touches another glass of the morph (gap at least half of `spacing`); the glass a removed one sinks into stays blurred until it has sunk. Under Reduce Motion nothing is blurred.
+- Glass without a container, or alone in one, has nothing to morph with: an appearing glass grows from its own centre and a removed one dematerializes.
+
 Glass in one container that shares a `GlassEffectUnion` (the same id in the same `GlassNamespace`), the same shape and the same `Glass` draws as one shape at any distance, as native's `.glassEffectUnion` does: a shape on the bounding rect of the members' drawn rects, so it follows a member that moves. Circles and capsules become a capsule of that rect, as native draws two 64 pt circles 16 pt apart as one 144 × 64 pt capsule; rounded rectangles and superellipses keep their corner radius. Each member's content stays where that member is laid out. A union counts as one shape against a container's 16 shapes, and blends with the container's other glass by `spacing` like any shape. Glass with the same union id but a different shape or `Glass` forms its own union. A member that is materializing draws on its own and joins its union when it settles; a removed member leaves its union at once and dematerializes on its own. A union needs a container: glass outside one draws on its own whatever its union. The fallback renderer without shader support (`FakeGlass`) draws each member on its own.
 
 ### Theme
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
index 4f9d2e093a050cff24421e4ae6d6ce38a175fe23..03368c630d1d7d9dffd2c934d3a6a25c0266b44f 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
@@ -5,6 +5,7 @@ import '../glass_lab_backdrop.dart';
 import '../glass_lab_launch.dart';
 import '../glass_lab_marker.dart';
 import 'lab_parts.dart';
+import 'morph_scenes.dart';
 
 const Color labAccent = Color(0xFF1ACB64);
 
@@ -72,19 +73,9 @@ sealed class MaterialScenes {
       ],
     ),
     'material.union': (launch) => UnionScene(backdrop: launch.backdrop),
-    'material.morph': (launch) => LabCentered(
-      backdrop: launch.backdrop,
-      children: [
-        GlassLabMarker(
-          'morph',
-          child: GlassEffect(
-            glass: Glass.regular.interactive(),
-            shape: const GlassShape.circle(),
-            child: const SizedBox.square(dimension: 56, child: GlassForeground(child: Icon(Icons.add, size: 22))),
-          ),
-        ),
-      ],
-    ),
+    'material.morph': (launch) => MorphScene(backdrop: launch.backdrop),
+    'material.morph.plain': (launch) => MorphScene(backdrop: launch.backdrop, interactive: false),
+    'material.tap': (launch) => TapScene(backdrop: launch.backdrop),
     'material.flip': (launch) => const Stack(
       children: [
         Positioned.fill(child: GlassLabScrollBackdrop()),
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/morph_scenes.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/morph_scenes.dart
new file mode 100644
index 0000000000000000000000000000000000000000..544974c264201eb04f39adec12b830b26bef815a
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/morph_scenes.dart
@@ -0,0 +1,116 @@
+import 'package:flutter/material.dart';
+import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+
+import '../glass_lab_marker.dart';
+import 'lab_parts.dart';
+
+class MorphScene extends StatefulWidget {
+  const MorphScene({super.key, required this.backdrop, this.interactive = true, this.warmUp = true});
+
+  static const List<(String, IconData)> badges = [('star.fill', Icons.star), ('heart.fill', Icons.favorite), ('bolt.fill', Icons.bolt)];
+  static const double side = 56;
+  static const double gap = 16;
+  static const double spacing = 20;
+  static const double iconSize = 22;
+
+  final String backdrop;
+  final bool interactive;
+  final bool warmUp;
+
+  @override
+  State<MorphScene> createState() => _MorphSceneState();
+}
+
+class _MorphSceneState extends State<MorphScene> {
+  static const GlassAnimation warmUp = GlassAnimation.dampedSpring(response: 0.08, dampingFraction: 1);
+  static const Duration warmUpStep = Duration(milliseconds: 150);
+
+  final GlassNamespace _namespace = GlassNamespace();
+  bool _expanded = false;
+
+  @override
+  void initState() {
+    super.initState();
+    if (widget.warmUp) WidgetsBinding.instance.addPostFrameCallback((_) => _warmUp());
+  }
+
+  Future<void> _warmUp() async {
+    for (final expanded in [true, false]) {
+      if (!mounted) return;
+      withGlassAnimation(warmUp, () => setState(() => _expanded = expanded));
+      await Future<void>.delayed(warmUpStep);
+    }
+  }
+
+  void _toggle() => withGlassAnimation(GlassAnimation.defaultSpring, () => setState(() => _expanded = !_expanded));
+
+  @override
+  Widget build(BuildContext context) {
+    return LabCentered(
+      backdrop: widget.backdrop,
+      children: [
+        GlassEffectContainer(
+          spacing: MorphScene.spacing,
+          child: Column(
+            mainAxisSize: MainAxisSize.min,
+            spacing: MorphScene.gap,
+            children: [
+              if (_expanded)
+                for (final (symbol, icon) in MorphScene.badges)
+                  GlassEffect(
+                    key: ValueKey(symbol),
+                    id: GlassEffectID(symbol, _namespace),
+                    child: SizedBox.square(dimension: MorphScene.side, child: GlassForeground(child: Icon(icon, size: MorphScene.iconSize))),
+                  ),
+              GlassLabMarker(
+                'morph',
+                key: const ValueKey('toggle'),
+                child: GlassEffect(
+                  glass: widget.interactive ? Glass.regular.interactive() : Glass.regular,
+                  id: GlassEffectID('toggle', _namespace),
+                  child: GestureDetector(
+                    behavior: HitTestBehavior.opaque,
+                    onTap: _toggle,
+                    child: SizedBox.square(
+                      dimension: MorphScene.side,
+                      child: GlassForeground(child: Icon(_expanded ? Icons.close : Icons.add, size: MorphScene.iconSize)),
+                    ),
+                  ),
+                ),
+              ),
+            ],
+          ),
+        ),
+      ],
+    );
+  }
+}
+
+class TapScene extends StatelessWidget {
+  const TapScene({super.key, required this.backdrop});
+
+  final String backdrop;
+
+  @override
+  Widget build(BuildContext context) {
+    return LabCentered(
+      backdrop: backdrop,
+      children: [
+        GlassEffectContainer(
+          spacing: MorphScene.spacing,
+          child: GlassLabMarker(
+            'glass',
+            child: GlassEffect(
+              glass: Glass.regular.interactive(),
+              child: GestureDetector(
+                behavior: HitTestBehavior.opaque,
+                onTap: () {},
+                child: const SizedBox.square(dimension: MorphScene.side, child: GlassForeground(child: Icon(Icons.add, size: MorphScene.iconSize))),
+              ),
+            ),
+          ),
+        ),
+      ],
+    );
+  }
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/ios_liquid_glass.dart b/packages/mobile/packages/ios_liquid_glass/lib/ios_liquid_glass.dart
index b20dcfff9f6029181fa64b62764e80a96046857e..8ac79a3a926ab04ac944057ace5750ee5b1b3f15 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/ios_liquid_glass.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/ios_liquid_glass.dart
@@ -10,7 +10,7 @@ export 'src/api/glass_effect.dart' show GlassEffect, GlassEffectScope;
 export 'src/api/glass_effect_container.dart' show GlassEffectContainer;
 export 'src/api/glass_effect_transition.dart' show GlassEffectTransition;
 export 'src/api/glass_foreground.dart' show GlassForeground;
-export 'src/api/glass_namespace.dart' show GlassEffectUnion, GlassNamespace;
+export 'src/api/glass_namespace.dart' show GlassEffectID, GlassEffectUnion, GlassNamespace;
 export 'src/api/glass_shape.dart';
 export 'src/api/glass_theme.dart' show GlassTheme, GlassThemeData;
 export 'src/fake_glass.dart' show FakeGlass;
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
index 077300b44caf21c2701e5c33e15037b4e92f8ad7..d4e1b2a7add8903bc3408e22b543de4bb337a20f 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
@@ -20,7 +20,8 @@ class GlassEffect extends StatefulWidget {
     super.key,
     this.glass = Glass.regular,
     this.shape = const GlassShape.capsule(),
-    this.transition = GlassEffectTransition.materialize,
+    this.transition,
+    this.id,
     this.union,
     this.sideHint,
     required this.child,
@@ -30,11 +31,15 @@ class GlassEffect extends StatefulWidget {
 
   final Glass glass;
   final GlassShape shape;
-  final GlassEffectTransition transition;
+  final GlassEffectTransition? transition;
+  final GlassEffectID? id;
   final GlassEffectUnion? union;
   final double? sideHint;
   final Widget child;
 
+  GlassEffectTransition get effectiveTransition =>
+      transition ?? (id == null ? GlassEffectTransition.materialize : GlassEffectTransition.matchedGeometry);
+
   @override
   State<GlassEffect> createState() => _GlassEffectState();
 }
@@ -68,7 +73,7 @@ class _GlassEffectState extends State<GlassEffect> with SingleTickerProviderStat
   @override
   void didUpdateWidget(GlassEffect oldWidget) {
     super.didUpdateWidget(oldWidget);
-    if (oldWidget.glass.kind != widget.glass.kind || oldWidget.transition != widget.transition) _join();
+    if (oldWidget.glass.kind != widget.glass.kind || oldWidget.effectiveTransition != widget.effectiveTransition || oldWidget.id != widget.id) _join();
   }
 
   static bool _laidOut(RenderObject? parent) => switch (parent) {
@@ -82,12 +87,16 @@ class _GlassEffectState extends State<GlassEffect> with SingleTickerProviderStat
     final coordinator = _identity ? null : container ?? (_private ??= GlassMotionCoordinator(vsync: this));
     _useOverlay(coordinator != null && container == null);
     final scope = GlassAnimationScope.maybeOf(context);
-    final animate = widget.transition == GlassEffectTransition.materialize;
+    final transition = widget.effectiveTransition;
+    final animate = transition != GlassEffectTransition.identity;
+    final morphs = transition == GlassEffectTransition.matchedGeometry;
     final current = _member;
     if (coordinator == _coordinator && current != null) {
       current
         ..scopeAnimation = scope
-        ..animatesTransitions = animate;
+        ..animatesTransitions = animate
+        ..id = widget.id
+        ..morphs = morphs;
       return;
     }
     final hosted = container != null || _overlay != null;
@@ -101,6 +110,8 @@ class _GlassEffectState extends State<GlassEffect> with SingleTickerProviderStat
       from: current,
       reduceMotion: GlassAccessibility.of(context).reduceMotion,
       dark: GlassTheme.brightnessOf(context) == Brightness.dark,
+      id: widget.id,
+      morphs: morphs,
     )
       ?..onSettled = _settled
       ..onScreen = _onScreen;
@@ -203,9 +214,10 @@ class _GlassEffectState extends State<GlassEffect> with SingleTickerProviderStat
   @override
   Widget build(BuildContext context) {
     _parent = context.findAncestorRenderObjectOfType<RenderObject>();
-    final content = GlassSnapshotBoundary(key: _snapshotKey, child: GlassEffectScope(glass: widget.glass, child: widget.child));
+    final snapshot = GlassSnapshotBoundary(key: _snapshotKey, child: GlassEffectScope(glass: widget.glass, child: widget.child));
     final member = _member;
-    if (_identity || member == null) return content;
+    if (_identity || member == null) return snapshot;
+    final content = GlassMorphContent(member: member, child: snapshot);
     member
       ..scrollables = _scrollables()
       ..rebuilt();
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_transition.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_transition.dart
index 838afbc07c8565d8fdf753c99aed20c2f619e432..e066c469db6b32ea228958da471cb456a07dda07 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_transition.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_transition.dart
@@ -1 +1 @@
-enum GlassEffectTransition { materialize, identity }
+enum GlassEffectTransition { materialize, identity, matchedGeometry }
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_namespace.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_namespace.dart
index a632de78d8e4ecdba3ce4fed6cb115efb53c3baf..d392d3c30d6451e55351964ac27879c427372835 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_namespace.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_namespace.dart
@@ -17,3 +17,20 @@ class GlassEffectUnion {
   @override
   int get hashCode => Object.hash(id, identityHashCode(namespace));
 }
+
+@immutable
+class GlassEffectID {
+  const GlassEffectID(this.id, this.namespace);
+
+  final Object id;
+  final GlassNamespace namespace;
+
+  @override
+  bool operator ==(Object other) => other is GlassEffectID && other.id == id && identical(other.namespace, namespace);
+
+  @override
+  int get hashCode => Object.hash(GlassEffectID, id, identityHashCode(namespace));
+
+  @override
+  String toString() => 'GlassEffectID($id)';
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_morph_geometry.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_morph_geometry.dart
new file mode 100644
index 0000000000000000000000000000000000000000..5ee9b8fac4b56ce3e58992aa78cb22ddebdb770a
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_morph_geometry.dart
@@ -0,0 +1,51 @@
+import 'dart:math' as math;
+import 'dart:ui';
+
+import 'package:ios_liquid_glass/src/liquid_shape.dart';
+import 'package:meta/meta.dart';
+
+@internal
+sealed class GlassMorphGeometry {
+  static double sdf(LiquidShape shape, Rect rect, Offset point) {
+    final p = point - rect.center;
+    final hx = rect.width / 2, hy = rect.height / 2;
+    if (shape is LiquidOval) {
+      final rx = math.max(hx, 1e-4), ry = math.max(hy, 1e-4);
+      final k1 = math.sqrt(p.dx * p.dx / (rx * rx) + p.dy * p.dy / (ry * ry));
+      final k2 = math.sqrt(p.dx * p.dx / (rx * rx * rx * rx) + p.dy * p.dy / (ry * ry * ry * ry));
+      return k1 * (k1 - 1) / math.max(k2, 1e-4);
+    }
+    final radius = math.min(
+      switch (shape) {
+        LiquidRoundedRectangle(:final borderRadius) => borderRadius,
+        LiquidRoundedSuperellipse(:final borderRadius) => borderRadius,
+        LiquidOval() => 0.0,
+      },
+      math.min(hx, hy),
+    );
+    final qx = p.dx.abs() - hx + radius, qy = p.dy.abs() - hy + radius;
+    return math.min(math.max(qx, qy), 0.0) + math.sqrt(math.pow(math.max(qx, 0.0), 2) + math.pow(math.max(qy, 0.0), 2)) - radius;
+  }
+
+  static double extent(LiquidShape shape, Rect rect, Offset direction) {
+    if (rect.isEmpty) return 0;
+    var low = 0.0, high = math.sqrt(rect.width * rect.width + rect.height * rect.height) / 2 + 1;
+    for (var i = 0; i < 40; i++) {
+      final mid = (low + high) / 2;
+      if (sdf(shape, rect, rect.center + direction * mid) < 0) {
+        low = mid;
+      } else {
+        high = mid;
+      }
+    }
+    return (low + high) / 2;
+  }
+
+  static double gap(Rect a, LiquidShape shapeA, Rect b, LiquidShape shapeB) {
+    final delta = b.center - a.center;
+    final distance = delta.distance;
+    if (distance < 1e-9) return -(a.shortestSide + b.shortestSide) / 2;
+    final direction = delta / distance;
+    return distance - extent(shapeA, a, direction) - extent(shapeB, b, -direction);
+  }
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
index f36a02f1cbd0e8441a7a3823739e196d411af43e..91a7261dd50e16bc80ca661922c70953f1530027 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
@@ -11,6 +11,7 @@ import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
 import 'package:ios_liquid_glass/src/motion/glass_frame.dart';
 import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
 import 'package:ios_liquid_glass/src/motion/glass_materialize.dart';
+import 'package:ios_liquid_glass/src/motion/glass_morph_geometry.dart';
 import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
 import 'package:ios_liquid_glass/src/motion/glass_spring.dart';
 import 'package:meta/meta.dart';
@@ -18,6 +19,18 @@ import 'package:meta/meta.dart';
 @internal
 enum GlassPresence { appearing, present, disappearing }
 
+@internal
+enum GlassGhostKind { dematerialize, pending, sink, content }
+
+class _Arrival {
+  _Arrival(this.animation, {required this.reduceMotion});
+
+  final GlassAnimation animation;
+  final bool reduceMotion;
+  bool fades = false;
+  Rect? partner;
+}
+
 @internal
 class GlassMember extends ChangeNotifier implements GlassShapeMotion {
   GlassMember(this.coordinator);
@@ -26,6 +39,14 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
   final GlassMotionValue visibility = GlassMotionValue();
   final GlassSpring _presence = GlassSpring(1);
   final List<GlassSpring> _offset = [for (var i = 0; i < 4; i++) GlassSpring(0)];
+  final GlassSpring _morph = GlassSpring(1);
+  final GlassMotionValue contentOpacity = GlassMotionValue();
+  final ValueNotifier<bool> contentBlurred = ValueNotifier(false);
+  GlassEffectID? id;
+  bool morphs = false;
+  _Arrival? _arrival;
+  bool _contentFades = false;
+  bool _sinking = false;
   GlassPresence presence = GlassPresence.present;
   GlassMaterializeMapping _mapping = GlassMaterializeMapping.defaultSpring;
   bool reduceMotion = false;
@@ -61,11 +82,11 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
 
   LiquidGlassSettings? get settings => sharedSettings ?? material?.settings;
 
-  bool get isMoving => _presence.isMoving || _offset.any((spring) => spring.isMoving);
+  bool get isMoving => _presence.isMoving || _morph.isMoving || _offset.any((spring) => spring.isMoving);
 
   bool get ownsLayer => presence != GlassPresence.present;
 
-  double get progress => GlassMaterialize.progress(
+  double get progress => _sinking ? 1 : GlassMaterialize.progress(
     _presence.value,
     appearing: presence != GlassPresence.disappearing,
     mapping: _mapping,
@@ -236,6 +257,13 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
       _originFrame = frame;
       _readSpace(space, inner);
     }
+    final arrival = _arrival, size = _size;
+    if (arrival != null && size != null) {
+      _arrival = null;
+      _anchor = anchor;
+      _arrive(arrival, live & size);
+      return;
+    }
     final previous = _anchor;
     _anchor = anchor;
     if (previous == null || previous == anchor) return;
@@ -285,6 +313,31 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
     return false;
   }
 
+  void _arrive(_Arrival arrival, Rect layout) {
+    final partner = arrival.partner;
+    Rect start;
+    if (partner != null) {
+      start = partner;
+    } else {
+      final source = coordinator._nearestSource(this, layout);
+      final drawn = source?.drawn;
+      if (source == null || drawn == null) {
+        start = Rect.fromCenter(center: layout.center, width: 0, height: 0);
+      } else {
+        start = arrival.reduceMotion ? Rect.fromCenter(center: drawn.center, width: layout.width, height: layout.height) : drawn;
+        coordinator._link(this, source);
+      }
+    }
+    final now = coordinator._now, animation = arrival.animation;
+    _offset[0].restart(start.left - layout.left, 0, 0, animation, now);
+    _offset[1].restart(start.top - layout.top, 0, 0, animation, now);
+    _offset[2].restart(start.width - layout.width, 0, 0, animation, now);
+    _offset[3].restart(start.height - layout.height, 0, 0, animation, now);
+    _morph.restart(0, 0, 1, animation, now);
+    _contentFades = arrival.fades || arrival.reduceMotion;
+    coordinator._start();
+  }
+
   @override
   Rect resolve(RenderBox shape) {
     final local = Offset.zero & shape.size;
@@ -345,8 +398,14 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
 
   bool get _due => isMoving || presence == GlassPresence.appearing;
 
+  void _begin(GlassAnimation animation, {required bool reduceMotion}) {
+    _arrival = _Arrival(animation, reduceMotion: reduceMotion);
+    contentOpacity.value = reduceMotion ? 0 : 1;
+  }
+
   bool _sample(Duration now) {
     var moving = _presence.sample(now);
+    moving = _morph.sample(now) || moving;
     for (final spring in _offset) {
       moving = spring.sample(now) || moving;
     }
@@ -360,6 +419,7 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
 
   void _publish() {
     visibility.value = GlassMaterialize.visibility(progress);
+    if (_contentFades) contentOpacity.value = _morph.value.clamp(0.0, 1.0);
     _resizeMaterial();
     notifyListeners();
     if (coordinator._members.contains(this)) coordinator._unionChanged(_union, except: this);
@@ -373,12 +433,14 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
   @override
   void dispose() {
     visibility.dispose();
+    contentOpacity.dispose();
+    contentBlurred.dispose();
     super.dispose();
   }
 }
 
 @internal
-class GlassGhost {
+class GlassGhost extends ChangeNotifier implements GlassShapeMotion {
   GlassGhost({
     required this.member,
     required this.rect,
@@ -387,7 +449,11 @@ class GlassGhost {
     required this.settings,
     required this.shape,
     required this.shadows,
-  });
+    this.kind = GlassGhostKind.dematerialize,
+    this.partner,
+    this.blurred = false,
+    this.reduceMotion = false,
+  }) : current = rect;
 
   final GlassMember member;
   final Rect rect;
@@ -396,13 +462,78 @@ class GlassGhost {
   final LiquidGlassSettings settings;
   final LiquidShape shape;
   final List<BoxShadow> shadows;
+  final GlassMember? partner;
+  final bool blurred;
+  final bool reduceMotion;
+  final GlassMotionValue opacity = GlassMotionValue();
+  GlassGhostKind kind;
+  GlassMember? target;
+  Offset? _goal;
+  Rect current;
+
+  bool get draws => kind != GlassGhostKind.content;
+
+  Rect get placement => kind == GlassGhostKind.content ? Rect.fromCenter(center: current.center, width: rect.width, height: rect.height) : rect;
+
+  void _sink(GlassMember into, Rect goal) {
+    kind = GlassGhostKind.sink;
+    target = into;
+    _goal = goal.center;
+    member._sinking = true;
+  }
+
+  void _aim() {
+    final box = target?._box;
+    if (box == null || !box.attached || !box.hasSize) return;
+    _goal = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size).center;
+  }
+
+  bool _step(Duration now) {
+    final partner = this.partner;
+    if (kind == GlassGhostKind.content) {
+      if (partner == null) return false;
+      final drawn = partner.coordinator._globalRect(partner);
+      if (drawn != null) current = drawn;
+      opacity.value = 1 - partner.contentOpacity.value;
+      notifyListeners();
+      return partner._morph.isMoving;
+    }
+    final moving = member._sample(now);
+    final goal = _goal;
+    if (kind == GlassGhostKind.sink && goal != null) {
+      final remaining = member._presence.value.clamp(0.0, 1.0);
+      final travel = reduceMotion ? 1 - remaining : 1 - GlassMaterialize.progress(member._presence.value, appearing: false, mapping: member._mapping);
+      final centre = Offset.lerp(rect.center, goal, travel.clamp(0.0, 1.0))!;
+      final scale = reduceMotion ? 1.0 : remaining;
+      current = Rect.fromCenter(center: centre, width: rect.width * scale, height: rect.height * scale);
+      opacity.value = remaining;
+      notifyListeners();
+    }
+    return moving;
+  }
+
+  @override
+  Rect resolve(RenderBox shape) {
+    if (!shape.attached) return Offset.zero & shape.size;
+    return current.shift(-MatrixUtils.transformPoint(shape.getTransformTo(null), Offset.zero));
+  }
 
+  @override
+  GlassUnionOutline? union(RenderBox shape) => null;
+
+  @override
   void dispose() {
     snapshot?.dispose();
+    opacity.dispose();
     member.dispose();
+    super.dispose();
   }
 }
 
+class _Notifier extends ChangeNotifier {
+  void notify() => notifyListeners();
+}
+
 class _Leaving {
   _Leaving({
     required this.animation,
@@ -413,9 +544,16 @@ class _Leaving {
     required this.content,
     required this.contentSize,
     required this.pixelRatio,
+    this.morphs = false,
+    this.reduceMotion = false,
+    this.local,
   });
 
   final GlassAnimation animation;
+  final bool morphs;
+  final bool reduceMotion;
+  final Rect? local;
+  GlassMember? partner;
   final Rect rect;
   final LiquidGlassSettings settings;
   final LiquidShape shape;
@@ -456,6 +594,14 @@ class GlassMotionCoordinator {
   GlassSpring? _spacing;
   int _spacingFrame = -2;
   Duration? _spacingTime;
+  final Set<GlassMember> _arrivals = {};
+  int _arrivalFrame = -1;
+  final Set<GlassMember> _blurred = {};
+  final Map<GlassMember, Set<Object>> _links = {};
+  bool _ghostsChanged = false;
+  final _Notifier _ghostMotion = _Notifier();
+
+  Listenable get ghostMotion => _ghostMotion;
 
   Iterable<GlassMember> get members => _members;
 
@@ -507,12 +653,34 @@ class GlassMotionCoordinator {
     return binding.schedulerPhase == SchedulerPhase.idle ? null : binding.currentFrameTimeStamp;
   }
 
-  GlassMember join({GlassAnimation? scope, bool animate = true, bool inserted = false, GlassMember? from, bool reduceMotion = false, bool dark = true}) {
+  Set<GlassMember> get _arrivedNow {
+    final frame = GlassFrame.current;
+    if (_arrivalFrame != frame) {
+      _arrivalFrame = frame;
+      _arrivals.clear();
+    }
+    return _arrivals;
+  }
+
+  GlassMember join({
+    GlassAnimation? scope,
+    bool animate = true,
+    bool inserted = false,
+    GlassMember? from,
+    bool reduceMotion = false,
+    bool dark = true,
+    GlassEffectID? id,
+    bool morphs = false,
+  }) {
+    final arrivals = _arrivedNow;
     final member = GlassMember(this)
       ..scopeAnimation = scope
       ..animatesTransitions = animate
       ..reduceMotion = reduceMotion
-      ..dark = dark;
+      ..dark = dark
+      ..id = id
+      ..morphs = morphs;
+    final others = _members.any((other) => !arrivals.contains(other)) || _leaving.keys.any((other) => other.morphs);
     _members.add(member);
     if (from != null) {
       member._adopt(from);
@@ -520,13 +688,125 @@ class GlassMotionCoordinator {
     }
     final animation = resolveGlassAnimation(scope);
     if (inserted && animate && !animation.isNone) {
-      member._appear(animation, _now);
+      if (morphs && others) {
+        member._begin(animation, reduceMotion: reduceMotion);
+        arrivals.add(member);
+        if (id != null) {
+          for (final MapEntry(key: leaver, value: leaving) in _leaving.entries) {
+            if (leaving.partner == null && leaving.morphs && leaver.id == id) {
+              _pair(member, leaver, leaving);
+              break;
+            }
+          }
+        }
+      } else {
+        member._appear(animation, _now);
+      }
       _structureChanged(animation);
       _start();
     }
     return member;
   }
 
+  void _pair(GlassMember arrival, GlassMember leaver, _Leaving leaving) {
+    leaving.partner = arrival;
+    arrival._arrival
+      ?..partner = leaving.local
+      ..fades = true;
+    arrival.contentOpacity.value = 0;
+  }
+
+  GlassMember? _nearestSource(GlassMember arrival, Rect layout) {
+    GlassMember? best;
+    var bestGap = double.infinity, bestDistance = double.infinity;
+    for (final member in _members) {
+      if (identical(member, arrival) || _arrivals.contains(member) || member.presence == GlassPresence.disappearing) continue;
+      final drawn = member.drawn, shape = member.shape;
+      if (drawn == null) continue;
+      final gap = shape == null || arrival.shape == null ? (drawn.center - layout.center).distance : GlassMorphGeometry.gap(layout, arrival.shape!, drawn, shape);
+      final distance = (drawn.center - layout.center).distance;
+      if (gap < bestGap - 1e-9 || (gap < bestGap + 1e-9 && distance < bestDistance)) {
+        best = member;
+        bestGap = gap;
+        bestDistance = distance;
+      }
+    }
+    return best;
+  }
+
+  void _link(GlassMember arrival, GlassMember source) {
+    if (arrival.reduceMotion) return;
+    _links.putIfAbsent(arrival, () => {}).add(source);
+    _links.putIfAbsent(source, () => {}).add(arrival);
+    _blur(arrival);
+    _blur(source);
+  }
+
+  void _blur(GlassMember member) {
+    if (member.reduceMotion) return;
+    _blurred.add(member);
+    member.contentBlurred.value = true;
+  }
+
+  Iterable<(Rect, LiquidShape)> _morphShapes(Object except) sync* {
+    for (final member in _blurred) {
+      if (identical(member, except)) continue;
+      final rect = _globalRect(member), shape = member.shape;
+      if (rect != null && shape != null) yield (rect, shape);
+    }
+    for (final ghost in ghosts) {
+      if (!identical(ghost, except) && ghost.blurred && ghost.draws) yield (ghost.current, ghost.shape);
+    }
+  }
+
+  void _sharpen() {
+    if (_blurred.isEmpty) return;
+    final reach = spacing.value / 2;
+    for (final member in _blurred.toList()) {
+      final rect = _globalRect(member), shape = member.shape;
+      if (rect == null || shape == null) continue;
+      final sinking = _links[member]?.any((link) => link is GlassGhost && ghosts.contains(link)) ?? false;
+      final joined = _morphShapes(member).any((other) => GlassMorphGeometry.gap(rect, shape, other.$1, other.$2) < reach);
+      final settled = !_blurred.any((other) => other.isMoving) && !ghosts.any((ghost) => ghost.blurred);
+      if ((sinking || joined) && !settled) continue;
+      _blurred.remove(member);
+      _links.remove(member);
+      member.contentBlurred.value = false;
+    }
+  }
+
+  void resolveGhosts() {
+    for (final ghost in ghosts) {
+      if (ghost.kind == GlassGhostKind.sink) ghost._aim();
+      if (ghost.kind != GlassGhostKind.pending) continue;
+      GlassMember? best;
+      Rect? bestRect;
+      var bestGap = double.infinity;
+      for (final member in _members) {
+        final box = member._box, shape = member.shape;
+        if (box == null || shape == null || !box.attached || !box.hasSize || member.presence == GlassPresence.disappearing) continue;
+        final rect = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
+        final gap = GlassMorphGeometry.gap(ghost.rect, ghost.shape, rect, shape);
+        if (gap < bestGap) {
+          best = member;
+          bestRect = rect;
+          bestGap = gap;
+        }
+      }
+      if (best != null && bestRect != null && bestGap < spacing.value) {
+        ghost._sink(best, bestRect);
+        if (ghost.blurred) {
+          _links.putIfAbsent(best, () => {}).add(ghost);
+          _blur(best);
+        }
+      } else {
+        ghost.kind = GlassGhostKind.dematerialize;
+        _ghostsChanged = true;
+      }
+      _start();
+    }
+  }
+
   bool leave(
     GlassMember member, {
     required bool animate,
@@ -540,7 +820,10 @@ class GlassMotionCoordinator {
       return false;
     }
     final rect = _globalRect(member);
+    final local = member._lastDrawn;
     _members.remove(member);
+    _blurred.remove(member);
+    _links.remove(member);
     _unionChanged(member._union);
     final ghostOwner = owner ?? this;
     final animation = resolveGlassAnimation(member.scopeAnimation);
@@ -567,10 +850,22 @@ class GlassMotionCoordinator {
       content: content,
       contentSize: contentSize,
       pixelRatio: pixelRatio,
+      morphs: member.morphs,
+      reduceMotion: member.reduceMotion,
+      local: local,
     );
     _structureChanged(animation);
     member._ghostOwner = ghostOwner;
     ghostOwner._adopt(member, leaving);
+    final id = member.id;
+    if (member.morphs && id != null && identical(ghostOwner, this)) {
+      for (final arrival in _arrivedNow) {
+        if (arrival.morphs && arrival.id == id && arrival._arrival?.partner == null && !_leaving.values.any((other) => identical(other.partner, arrival))) {
+          _pair(arrival, member, leaving);
+          break;
+        }
+      }
+    }
     return true;
   }
 
@@ -616,12 +911,19 @@ class GlassMotionCoordinator {
       _dropLeaving();
       dropGhosts();
     }
+    final morphing = _leaving.entries.any((entry) => entry.value.morphs && entry.value.partner == null);
+    final others = _members.any((member) => member.presence != GlassPresence.disappearing);
     for (final MapEntry(key: member, value: leaving) in _leaving.entries) {
       final snapshot = leaving.snapshot();
       leaving.release();
-      member
-        ..material = null
-        .._disappear(leaving.animation, _now);
+      member.material = null;
+      final partner = leaving.partner;
+      final kind = partner != null
+          ? GlassGhostKind.content
+          : leaving.morphs && others && marker != null
+          ? GlassGhostKind.pending
+          : GlassGhostKind.dematerialize;
+      if (partner == null) member._disappear(leaving.animation, _now);
       ghosts.add(GlassGhost(
         member: member,
         rect: leaving.rect,
@@ -630,6 +932,10 @@ class GlassMotionCoordinator {
         settings: leaving.settings,
         shape: leaving.shape,
         shadows: leaving.shadows,
+        kind: kind,
+        partner: partner,
+        blurred: morphing && leaving.morphs && partner == null && !leaving.reduceMotion,
+        reduceMotion: leaving.reduceMotion,
       ));
     }
     _leaving.clear();
@@ -673,9 +979,10 @@ class GlassMotionCoordinator {
     for (final member in _members.toList()) {
       if (member._due) moving = member._sample(now) || moving;
     }
-    var finished = false;
+    var finished = _ghostsChanged;
+    _ghostsChanged = false;
     for (final ghost in ghosts.toList()) {
-      if (ghost.member._sample(now)) {
+      if (ghost._step(now) || ghost.kind == GlassGhostKind.pending) {
         moving = true;
       } else {
         ghosts.remove(ghost);
@@ -683,6 +990,9 @@ class GlassMotionCoordinator {
         finished = true;
       }
     }
+    _sharpen();
+    if (_blurred.isNotEmpty) moving = true;
+    if (ghosts.isNotEmpty) _ghostMotion.notify();
     if (finished) _ghostHost?.markNeedsBuild();
     if (!moving && _leaving.isEmpty) {
       _ticker.stop();
@@ -694,6 +1004,9 @@ class GlassMotionCoordinator {
     _disposed = true;
     _ticker.dispose();
     spacing.dispose();
+    _ghostMotion.dispose();
+    _blurred.clear();
+    _links.clear();
     dropGhosts();
     _dropLeaving();
     for (final member in _members) {
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart
index b41c49fff11f76a2b86b18af1424e934d6b21a22..42f1fba71d7736c4ea487f679843c48069851093 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_widgets.dart
@@ -1,11 +1,12 @@
 import 'dart:ui' as ui;
 
+import 'package:flutter/foundation.dart';
 import 'package:flutter/rendering.dart';
 import 'package:flutter/scheduler.dart';
 import 'package:flutter/widgets.dart';
 import 'package:ios_liquid_glass/src/liquid_glass.dart';
 import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
-import 'package:meta/meta.dart';
+import 'package:ios_liquid_glass/src/motion/ios27_motion.dart';
 
 @internal
 class GlassCoordinatorSpace extends SingleChildRenderObjectWidget {
@@ -162,6 +163,7 @@ class GlassGhostHost extends StatelessWidget {
         return IgnorePointer(
           child: ExcludeSemantics(
             child: _GhostStack(
+              coordinator: coordinator,
               children: [for (final ghost in ghosts) _GhostSlot(key: ObjectKey(ghost), ghost: ghost, child: _Ghost(ghost: ghost))],
             ),
           ),
@@ -268,14 +270,44 @@ class _GhostSlot extends ParentDataWidget<_GhostParentData> {
 }
 
 class _GhostStack extends MultiChildRenderObjectWidget {
-  const _GhostStack({super.children});
+  const _GhostStack({required this.coordinator, super.children});
+
+  final GlassMotionCoordinator coordinator;
 
   @override
-  RenderObject createRenderObject(BuildContext context) => _RenderGhostStack();
+  RenderObject createRenderObject(BuildContext context) => _RenderGhostStack(coordinator);
+
+  @override
+  void updateRenderObject(BuildContext context, _RenderGhostStack renderObject) {
+    renderObject.coordinator = coordinator;
+  }
 }
 
 class _RenderGhostStack extends RenderBox
     with ContainerRenderObjectMixin<RenderBox, _GhostParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _GhostParentData> {
+  _RenderGhostStack(this._coordinator);
+
+  GlassMotionCoordinator _coordinator;
+  set coordinator(GlassMotionCoordinator value) {
+    if (identical(value, _coordinator)) return;
+    if (attached) _coordinator.ghostMotion.removeListener(markNeedsPaint);
+    _coordinator = value;
+    if (attached) value.ghostMotion.addListener(markNeedsPaint);
+    markNeedsPaint();
+  }
+
+  @override
+  void attach(PipelineOwner owner) {
+    super.attach(owner);
+    _coordinator.ghostMotion.addListener(markNeedsPaint);
+  }
+
+  @override
+  void detach() {
+    _coordinator.ghostMotion.removeListener(markNeedsPaint);
+    super.detach();
+  }
+
   @override
   void setupParentData(RenderBox child) {
     if (child.parentData is! _GhostParentData) child.parentData = _GhostParentData();
@@ -294,11 +326,12 @@ class _RenderGhostStack extends RenderBox
 
   Offset _placement(RenderBox child) {
     final ghost = (child.parentData! as _GhostParentData).ghost;
-    return ghost == null ? Offset.zero : globalToLocal(ghost.rect.topLeft);
+    return ghost == null ? Offset.zero : globalToLocal(ghost.placement.topLeft);
   }
 
   @override
   void paint(PaintingContext context, Offset offset) {
+    _coordinator.resolveGhosts();
     var child = firstChild;
     while (child != null) {
       context.paintChild(child, offset + _placement(child));
@@ -324,21 +357,127 @@ class _Ghost extends StatelessWidget {
   @override
   Widget build(BuildContext context) {
     final snapshot = ghost.snapshot;
-    return LiquidGlass.withOwnLayer(
-      settings: ghost.settings,
-      shape: ghost.shape,
-      shadows: ghost.shadows,
-      visibility: ghost.member.visibility,
-      child: SizedBox.fromSize(
-        size: ghost.rect.size,
-        child: snapshot == null
-            ? null
-            : OverflowBox(
-                maxWidth: double.infinity,
-                maxHeight: double.infinity,
-                child: RawImage(image: snapshot, scale: ghost.pixelRatio),
-              ),
+    final Widget? image = snapshot == null
+        ? null
+        : OverflowBox(
+            maxWidth: double.infinity,
+            maxHeight: double.infinity,
+            child: GlassContentBlur(blurred: ghost.blurred, child: RawImage(image: snapshot, scale: ghost.pixelRatio)),
+          );
+    final content = SizedBox.fromSize(size: ghost.rect.size, child: image);
+    return switch (ghost.kind) {
+      GlassGhostKind.content => FadeTransition(opacity: ghost.opacity, child: content),
+      GlassGhostKind.pending || GlassGhostKind.sink => LiquidGlass.grouped(
+        shape: ghost.shape,
+        shadows: ghost.shadows,
+        motion: ghost,
+        child: FadeTransition(opacity: ghost.opacity, child: content),
+      ),
+      GlassGhostKind.dematerialize => LiquidGlass.withOwnLayer(
+        settings: ghost.settings,
+        shape: ghost.shape,
+        shadows: ghost.shadows,
+        visibility: ghost.member.visibility,
+        child: content,
       ),
+    };
+  }
+}
+
+@internal
+class GlassContentBlur extends SingleChildRenderObjectWidget {
+  const GlassContentBlur({super.key, this.blurred = false, this.listenable, super.child});
+
+  final bool blurred;
+  final ValueListenable<bool>? listenable;
+
+  @override
+  RenderGlassContentBlur createRenderObject(BuildContext context) => RenderGlassContentBlur(blurred: blurred, listenable: listenable);
+
+  @override
+  void updateRenderObject(BuildContext context, RenderGlassContentBlur renderObject) {
+    renderObject
+      ..blurred = blurred
+      ..listenable = listenable;
+  }
+}
+
+@internal
+class RenderGlassContentBlur extends RenderProxyBox {
+  RenderGlassContentBlur({required bool blurred, ValueListenable<bool>? listenable}) : _blurred = blurred, _listenable = listenable;
+
+  static final ui.ImageFilter filter = ui.ImageFilter.blur(sigmaX: ios27MorphContentBlur, sigmaY: ios27MorphContentBlur, tileMode: TileMode.decal);
+
+  final LayerHandle<ImageFilterLayer> _filter = LayerHandle();
+
+  bool _blurred;
+  set blurred(bool value) {
+    if (value == _blurred) return;
+    _blurred = value;
+    markNeedsPaint();
+  }
+
+  ValueListenable<bool>? _listenable;
+  set listenable(ValueListenable<bool>? value) {
+    if (identical(value, _listenable)) return;
+    if (attached) _listenable?.removeListener(_changed);
+    _listenable = value;
+    if (attached) value?.addListener(_changed);
+    markNeedsPaint();
+  }
+
+  bool get isBlurred => _listenable?.value ?? _blurred;
+
+  void _changed() {
+    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) markNeedsPaint();
+  }
+
+  @override
+  bool get alwaysNeedsCompositing => true;
+
+  @override
+  void attach(PipelineOwner owner) {
+    super.attach(owner);
+    _listenable?.addListener(_changed);
+  }
+
+  @override
+  void detach() {
+    _listenable?.removeListener(_changed);
+    super.detach();
+  }
+
+  @override
+  void paint(PaintingContext context, Offset offset) {
+    if (!isBlurred) {
+      _filter.layer = null;
+      super.paint(context, offset);
+      return;
+    }
+    final layer = _filter.layer ??= ImageFilterLayer();
+    layer.imageFilter = filter;
+    context.pushLayer(layer, super.paint, offset);
+  }
+
+  @override
+  void dispose() {
+    _filter.layer = null;
+    super.dispose();
+  }
+}
+
+@internal
+class GlassMorphContent extends StatelessWidget {
+  const GlassMorphContent({super.key, required this.member, required this.child});
+
+  final GlassMember member;
+  final Widget child;
+
+  @override
+  Widget build(BuildContext context) {
+    return FadeTransition(
+      opacity: member.contentOpacity,
+      child: GlassContentBlur(listenable: member.contentBlurred, child: child),
     );
   }
 }
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart
index dc20888ca88d834962c95338ed831502dc594ec7..8ad61d9fc4568c89560ec0e986d8d98f55723758 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart
@@ -1,5 +1,7 @@
 const double ios27BlurRampExponent = 1.0;
 
+const double ios27MorphContentBlur = 1.5;
+
 const double ios27DefaultDisappearExponent = 3.1;
 const double ios27DefaultAppearExponent = 1.85;
 const double ios27DefaultDarkAppearGain = 0.0;
diff --git a/packages/mobile/tool/glass_lab/scenes.json b/packages/mobile/tool/glass_lab/scenes.json
index 5dd6bb3876c874b96718f274b00a3334c5acc9bf..30d9f382679602aa22eb555f6983ee5a38312acc 100644
--- a/packages/mobile/tool/glass_lab/scenes.json
+++ b/packages/mobile/tool/glass_lab/scenes.json
@@ -746,6 +746,70 @@
       {
         "wait": 1.5
       }
+    ],
+    "regions": {
+      "star": [
+        157,
+        311,
+        88,
+        64
+      ],
+      "heart": [
+        157,
+        383,
+        88,
+        64
+      ],
+      "bolt": [
+        157,
+        455,
+        88,
+        64
+      ],
+      "toggle": [
+        157,
+        527,
+        88,
+        64
+      ],
+      "collapsed": [
+        157,
+        419,
+        88,
+        64
+      ],
+      "stack": [
+        157,
+        299,
+        88,
+        304
+      ]
+    },
+    "track": [
+      "star",
+      "heart",
+      "bolt",
+      "toggle",
+      "collapsed"
+    ],
+    "topology": [
+      "stack"
+    ],
+    "motion": [
+      "cy.peak_ms",
+      "cy.settle_ms",
+      "cy.overshoot_pct",
+      "cy.response_pct",
+      "cy.damping",
+      "width.peak_ms",
+      "width.settle_ms",
+      "width.overshoot_pct",
+      "width.response_pct",
+      "width.damping",
+      "topology.count",
+      "topology.join_ms",
+      "topology.split_ms",
+      "topology.neck_rms"
     ]
   },
   {
@@ -778,6 +842,70 @@
       {
         "wait": 1.5
       }
+    ],
+    "regions": {
+      "star": [
+        157,
+        311,
+        88,
+        64
+      ],
+      "heart": [
+        157,
+        383,
+        88,
+        64
+      ],
+      "bolt": [
+        157,
+        455,
+        88,
+        64
+      ],
+      "toggle": [
+        157,
+        527,
+        88,
+        64
+      ],
+      "collapsed": [
+        157,
+        419,
+        88,
+        64
+      ],
+      "stack": [
+        157,
+        299,
+        88,
+        304
+      ]
+    },
+    "track": [
+      "star",
+      "heart",
+      "bolt",
+      "toggle",
+      "collapsed"
+    ],
+    "topology": [
+      "stack"
+    ],
+    "motion": [
+      "cy.peak_ms",
+      "cy.settle_ms",
+      "cy.overshoot_pct",
+      "cy.response_pct",
+      "cy.damping",
+      "width.peak_ms",
+      "width.settle_ms",
+      "width.overshoot_pct",
+      "width.response_pct",
+      "width.damping",
+      "topology.count",
+      "topology.join_ms",
+      "topology.split_ms",
+      "topology.neck_rms"
     ]
   },
   {
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t11-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_morph_test.dart` => PASS

Expected output ends with:

```text
+13: All tests passed!
```

RUN[t11-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/morph_scene_test.dart` => PASS

Expected output ends with:

```text
+4: All tests passed!
```

- [ ] **Step 5: Gate: package.**

RUN[t11-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t11-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

Expected output ends with:

```text
+202: All tests passed!
```

- [ ] **Step 6: Gate: example.**

RUN[t11-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t11-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

Expected output ends with:

```text
+23: All tests passed!
```

- [ ] **Step 7: Gate: app.**

RUN[t11-gate-app-analyze]: `cd packages/mobile && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t11-gate-app-test]: `cd packages/mobile && flutter test --no-pub` => PASS

Expected output ends with:

```text
+2188: All tests passed!
```

- [ ] **Step 8: Commit.**

```bash
git add -A packages
git commit -m "feat(ios_liquid_glass): GlassEffectID and matchedGeometry morph: partner morph, emergence from the nearest glass, sink or dematerialize, content blur, morph scenes

Co-Authored-By: <the session's attribution line>"
```

### Task 12: `fitvis --write` keeps the morph content blur line the table already holds

**Files:**
- Modify: `tool/glass_lab/harness/fitvis.py` (`table_source`, `write_table`)
- Test: `tool/glass_lab/harness/tests/test_fitvis.py`

**Why.** Ruling 23.

- [ ] **Step 1: Add the failing tests.**

Patch `t12-tests` (`f4039bea6..1d2ddc57a`, 1 files):

```diff
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_fitvis.py b/packages/mobile/tool/glass_lab/harness/tests/test_fitvis.py
index 485f4a022ad183a672aaf48227351987b5fc27ea..0e50c463493876ddf7556e24c090cf183c4563e1 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_fitvis.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_fitvis.py
@@ -359,6 +359,24 @@ class WriteGuardTests(unittest.TestCase):
             fitvis.write_table(found, [], target)
             self.assertIn("ios27VisibilityAboveFull = [1.1, 1.2];", target.read_text())
 
+    def test_a_write_keeps_the_morph_content_blur_line_the_target_already_holds(self):
+        found = summary(complete_mapping())
+        with tempfile.TemporaryDirectory() as folder:
+            target = Path(folder) / "ios27_motion.dart"
+            target.write_text("const double ios27BlurRampExponent = 1.0;\n\nconst double ios27MorphContentBlur = 1.5;\n\nconst double ios27DefaultDisappearExponent = 3.1;\n")
+            fitvis.write_table(found, [], target)
+            written = target.read_text()
+            self.assertEqual(written.count("const double ios27MorphContentBlur = 1.5;"), 1)
+            self.assertLess(written.index("ios27BlurRampExponent"), written.index("ios27MorphContentBlur"))
+            self.assertLess(written.index("ios27MorphContentBlur"), written.index("ios27DefaultDisappearExponent"))
+
+    def test_a_write_to_a_target_without_the_morph_content_blur_line_adds_none(self):
+        found = summary(complete_mapping())
+        with tempfile.TemporaryDirectory() as folder:
+            target = Path(folder) / "ios27_motion.dart"
+            fitvis.write_table(found, [], target)
+            self.assertNotIn("ios27MorphContentBlur", target.read_text())
+
     def test_every_unfitted_or_edge_value_is_named_and_the_write_refused(self):
         mapping = complete_mapping(**{
             "material.materialize.bouncy:exponent": None,
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t12-fitvis-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py` => FAIL

Expected output ends with:

```text
FAILED (failures=1)
```

Expected: `FAILED (failures=1)`. Task 12 adds two tests; only `test_a_write_keeps_the_morph_content_blur_line_the_target_already_holds` fails before the implementation (the old `table_source` deletes the line). `test_a_write_to_a_target_without_the_morph_content_blur_line_adds_none` **passes** before it, by design: it pins the other half of the rule (a target that has no such line must not gain one), which the old code also satisfied and a careless fix could break, so it is a guard and not a red test.

- [ ] **Step 3: Apply the implementation.**

Patch `t12-impl` (`f4039bea6..1d2ddc57a`, 1 files):

```diff
diff --git a/packages/mobile/tool/glass_lab/harness/fitvis.py b/packages/mobile/tool/glass_lab/harness/fitvis.py
index 1c675bf1760acfec5519d8407ed77775be29f36a..17e1fed2042cd602836ccf5f07d177ddff5358bb 100644
--- a/packages/mobile/tool/glass_lab/harness/fitvis.py
+++ b/packages/mobile/tool/glass_lab/harness/fitvis.py
@@ -1,4 +1,5 @@
 import json
+import re
 from pathlib import Path
 
 import numpy as np
@@ -696,9 +697,14 @@ def legacy_gains(entry):
     return found
 
 
-def table_source(mapping, ramp, table, above=(), mode="pooled"):
+MORPH_BLUR_LINE = re.compile(r"^const double ios27MorphContentBlur = [0-9.]+;$", re.M)
+
+
+def table_source(mapping, ramp, table, above=(), mode="pooled", morph_blur=None):
     values = table_values(mapping, mode)
     lines = [f"const double ios27BlurRampExponent = {float(ramp)};", ""]
+    if morph_blur:
+        lines += [morph_blur, ""]
     lines += [f"const double {name} = {value};" for name, value in values.items()]
     rows = ", ".join(f"{v}" for v in table)
     lines += ["", f"const List<double> ios27VisibilityForProgress = [\n  {rows},\n];"]
@@ -839,4 +845,5 @@ def write_table(summary, problems, target=None):
     target = Path(target or TABLE)
     if problems:
         raise SystemExit(f"fitvis --write refused, nothing written to {target}:\n" + "\n".join(f"  - {problem}" for problem in problems))
-    target.write_text(table_source(summary["mapping"], summary["blur_ramp"]["value"], summary["visibility_for_progress"], summary["visibility_above_full"], summary["gain_mode"]))
+    kept = MORPH_BLUR_LINE.search(target.read_text()) if target.exists() else None
+    target.write_text(table_source(summary["mapping"], summary["blur_ramp"]["value"], summary["visibility_for_progress"], summary["visibility_above_full"], summary["gain_mode"], kept.group(0) if kept else None))
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t12-fitvis-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py` => PASS

Expected output ends with:

```text
Ran 40 tests in <time>
OK
```

- [ ] **Step 5: Gate: harness.**

RUN[t12-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

Expected output ends with:

```text
Ran 237 tests in <time>
OK
```

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "fix(glass_lab): fitvis --write keeps the morph content blur line the table already holds

Co-Authored-By: <the session's attribution line>"
```

### Task 13: A second morph swap inside the first settles: the content ghost samples a partner that was removed

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart` (`GlassGhost._step`, content kind)
- Test: `test/motion/glass_morph_test.dart` (`_Chain`, two tests)

**Why.** Ruling 27. A content ghost reported `partner._morph.isMoving`, and a partner's spring is advanced only by its own member; when the partner was itself swapped away inside the morph, its ghost is a content ghost too and never advanced it, so the first ghost, its snapshot and the container's ticker ran for ever. A double tap on the toggle did it.

- [ ] **Step 1: Add the failing tests.**

Patch `t13-tests` (`4db370855..3f5f59cbf`, 1 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_morph_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_morph_test.dart
index 1b341b9d200e4e2697b1362e943e2e4cf5ecf09b..45fd239e4ef268279af3eed180c62e3a981e973e 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_morph_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_morph_test.dart
@@ -110,6 +110,54 @@ class _SwapState extends State<_Swap> {
   }
 }
 
+class _Chain extends StatefulWidget {
+  const _Chain();
+
+  @override
+  State<_Chain> createState() => _ChainState();
+}
+
+class _ChainState extends State<_Chain> {
+  static const List<Offset> spots = [Offset(20, 20), Offset(300, 200), Offset(100, 300)];
+
+  final GlassNamespace namespace = GlassNamespace();
+  int index = 0;
+
+  void go(int next) => setState(() => index = next);
+
+  @override
+  Widget build(BuildContext context) {
+    return MaterialApp(
+      home: GlassTheme(
+        data: const GlassThemeData(brightness: Brightness.dark),
+        child: Align(
+          alignment: Alignment.topLeft,
+          child: GlassEffectContainer(
+            child: SizedBox(
+              width: 600,
+              height: 500,
+              child: Stack(
+                children: [
+                  Positioned(
+                    left: spots[index].dx,
+                    top: spots[index].dy,
+                    child: GlassEffect(
+                      key: ValueKey('k$index'),
+                      id: GlassEffectID('x', namespace),
+                      child: const SizedBox(width: 100, height: 40),
+                    ),
+                  ),
+                  const Positioned(left: 500, top: 450, child: GlassEffect(child: SizedBox(width: 40, height: 40))),
+                ],
+              ),
+            ),
+          ),
+        ),
+      ),
+    );
+  }
+}
+
 class _Row extends StatefulWidget {
   const _Row();
 
@@ -421,4 +469,23 @@ void main() {
     expect(member.contentOpacity.value, 1);
     expect(coordinator.ghosts, isEmpty);
   });
+
+  for (final gap in [60, 300]) {
+    testWidgets('a second swap $gap ms into the first settles: no ghost is left and no frame stays scheduled', (tester) async {
+      await tester.pumpWidget(const _Chain());
+      await tester.pump(const Duration(seconds: 1));
+      final state = tester.state<_ChainState>(find.byType(_Chain));
+      final coordinator = tester.renderObject<RenderGlassMemberBox>(find.byType(GlassMemberBox).first).member.coordinator;
+      state.go(1);
+      await tester.pump();
+      await tester.pump(Duration(milliseconds: gap));
+      state.go(2);
+      await tester.pump();
+      expect(coordinator.ghosts.where((ghost) => ghost.kind == GlassGhostKind.content), isNotEmpty);
+      await tester.pump(const Duration(seconds: 5));
+      expect(coordinator.ghosts, isEmpty);
+      expect(tester.binding.hasScheduledFrame, isFalse);
+      _expectRect(_onScreen(_member(tester, 'k2')), _layout(tester, 'k2'));
+    });
+  }
 }
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t13-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_morph_test.dart` => FAIL

Expected output ends with:

```text
+13 -2: Some tests failed.
```

Expected: the two new tests fail on `Expected: empty / Actual: [Instance of 'GlassGhost']` (the ghost is still there 5 s after the second swap, at a 60 ms and at a 300 ms gap); the other morph tests pass.

- [ ] **Step 3: Apply the implementation.**

Patch `t13-impl` (`4db370855..3f5f59cbf`, 1 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
index 91a7261dd50e16bc80ca661922c70953f1530027..686f7eef53f866b1030dee023f70383cd94d0a72 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
@@ -494,9 +494,11 @@ class GlassGhost extends ChangeNotifier implements GlassShapeMotion {
       if (partner == null) return false;
       final drawn = partner.coordinator._globalRect(partner);
       if (drawn != null) current = drawn;
-      opacity.value = 1 - partner.contentOpacity.value;
+      final live = partner.coordinator._members.contains(partner);
+      final moving = live ? partner._morph.isMoving : partner._morph.sample(now);
+      opacity.value = 1 - (live ? partner.contentOpacity.value : partner._morph.value.clamp(0.0, 1.0));
       notifyListeners();
-      return partner._morph.isMoving;
+      return moving;
     }
     final moving = member._sample(now);
     final goal = _goal;
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t13-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_morph_test.dart` => PASS

Expected output ends with:

```text
+15: All tests passed!
```

- [ ] **Step 5: Gate: package.**

RUN[t13-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t13-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

Expected output ends with:

```text
+204: All tests passed!
```

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "fix(ios_liquid_glass): a second morph swap inside the first settles: the content ghost samples a removed partner

Co-Authored-By: <the session's attribution line>"
```

### Task 14: A shape motion says whether it is transient (a ghost is, a member is not)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart`, `lib/src/motion/glass_motion_coordinator.dart`
- Test: `test/motion/render_hooks_test.dart`, `test/motion/glass_union_test.dart` (their fake motions implement the new member)

**Why.** Ruling 28. A refactor that adds `isTransient` to the `GlassShapeMotion` interface and changes no behaviour, so that Task 15's test can fail on an assertion and not on a missing symbol.

- [ ] **Step 1: Apply the implementation.**

Patch `t14-impl` (`3f5f59cbf..42f09d87f`, 4 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
index 686f7eef53f866b1030dee023f70383cd94d0a72..5200720edddd2580ee7ac243cd2144bfdb7bf6b7 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
@@ -155,6 +155,9 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
     return outline.shift(-MatrixUtils.transformPoint(shape.getTransformTo(space), Offset.zero));
   }
 
+  @override
+  bool get isTransient => false;
+
   void _unionMoved() => notifyListeners();
 
   void attachBox(RenderBox box) => _box = box;
@@ -523,6 +526,9 @@ class GlassGhost extends ChangeNotifier implements GlassShapeMotion {
   @override
   GlassUnionOutline? union(RenderBox shape) => null;
 
+  @override
+  bool get isTransient => true;
+
   @override
   void dispose() {
     snapshot?.dispose();
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart
index 1fd607eb4ac0a23b92a140ce6763869fde692768..ba796d795f75b099d7ee1e1f915df5904a1f3bf6 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart
@@ -7,6 +7,8 @@ abstract interface class GlassShapeMotion implements Listenable {
   Rect resolve(RenderBox shape);
 
   GlassUnionOutline? union(RenderBox shape);
+
+  bool get isTransient;
 }
 
 @internal
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_union_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_union_test.dart
index 7f8c77cc73479cb6c8360d023215cfb0803ecc7a..06d5d81c9441c845d96dd7b09157eedef5a7560b 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_union_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_union_test.dart
@@ -66,6 +66,9 @@ class _Motion extends ChangeNotifier implements GlassShapeMotion {
   @override
   Rect resolve(RenderBox shape) => drawn;
 
+  @override
+  bool get isTransient => false;
+
   @override
   GlassUnionOutline? union(RenderBox shape) => outline;
 }
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/render_hooks_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/render_hooks_test.dart
index 2138c469fbeb6d53ec3d39e8466ac2fb3c06fb5f..c6a352b413bf507d8be290fbb96089c1e3663fa5 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/render_hooks_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/render_hooks_test.dart
@@ -19,6 +19,9 @@ class _Motion extends ChangeNotifier implements GlassShapeMotion {
   @override
   Rect resolve(RenderBox shape) => drawn;
 
+  @override
+  bool get isTransient => false;
+
   @override
   GlassUnionOutline? union(RenderBox shape) => null;
 
```

- [ ] **Step 2: Gate: package.**

RUN[t14-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t14-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

Expected output ends with:

```text
+204: All tests passed!
```

- [ ] **Step 3: Commit.**

```bash
git add -A packages
git commit -m "refactor(ios_liquid_glass): a shape motion says whether it is transient; a ghost is, a member is not

Co-Authored-By: <the session's attribution line>"
```

### Task 15: Ghosts count toward a container's sixteen shapes and are left out before a member is; paint never throws for them

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart` (`gatherShapeData`)
- Test: `test/motion/glass_group_test.dart` (new; builds the blend group and its glass render objects, as spec §9 and gotcha 39 require)

**Why.** Ruling 28. A sinking or pending ghost registers in the container's blend group, which 2B.1's ghosts did not: they drew in their own layers because they only fade in place (`dematerialize`) and need no blend; a sink has to blend with the glass it sinks into. 15 glasses, an arrival with an id and two sinking ghosts made 18 shapes and `updateGeometryShaderShapes` threw `UnsupportedError` in paint. The shader cannot be compiled by `flutter test` (gotcha 3), so the test constructs `RenderLiquidGlassBlendGroup` and `RenderLiquidGlass` objects with the shader upload stubbed and reads `gatherShapeData`.

- [ ] **Step 1: Add the failing tests.**

Patch `t15-tests` (`42f09d87f..19e53ff72`, 1 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_group_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_group_test.dart
new file mode 100644
index 0000000000000000000000000000000000000000..05c9b292297a82c53dd6c85145f932101455d4a0
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_group_test.dart
@@ -0,0 +1,86 @@
+import 'dart:ui' as ui;
+
+import 'package:flutter/foundation.dart';
+import 'package:flutter/rendering.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+import 'package:ios_liquid_glass/src/internal/render_liquid_glass_geometry.dart';
+import 'package:ios_liquid_glass/src/liquid_glass.dart';
+import 'package:ios_liquid_glass/src/liquid_glass_blend_group.dart';
+import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
+import 'package:ios_liquid_glass/src/rendering/liquid_glass_render_object.dart';
+
+const LiquidShape _capsule = LiquidRoundedRectangle(borderRadius: 999);
+
+class _Motion extends ChangeNotifier implements GlassShapeMotion {
+  _Motion({this.transient = false});
+
+  final bool transient;
+
+  @override
+  Rect resolve(RenderBox shape) => Offset.zero & shape.size;
+
+  @override
+  bool get isTransient => transient;
+
+  @override
+  GlassUnionOutline? union(RenderBox shape) => null;
+}
+
+class _Group extends RenderLiquidGlassBlendGroup {
+  _Group({required super.geometryShader, required super.link})
+    : super(renderLink: GeometryRenderLink(), devicePixelRatio: 3, settings: const LiquidGlassSettings(thickness: 20), blend: 8);
+
+  @override
+  void updateShaderWithSettings(LiquidGlassSettings settings, double devicePixelRatio) {}
+
+  @override
+  void updateGeometryShaderShapes(List<ShapeGeometry> shapes) {}
+}
+
+Future<(_Group, List<RenderLiquidGlass>)> _group(List<_Motion> motions) async {
+  final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
+  final link = GlassGroupLink();
+  final glasses = [
+    for (final motion in motions)
+      RenderLiquidGlass(shape: _capsule, glassContainsChild: false, blendGroupLink: link)
+        ..motion = motion
+        ..child = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(const Size(20, 20))),
+  ];
+  final group = _Group(geometryShader: program.fragmentShader(), link: link)
+    ..child = RenderFlex(textDirection: TextDirection.ltr, crossAxisAlignment: CrossAxisAlignment.start, children: glasses);
+  final root = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(const Size(800, 400)), child: group);
+  PipelineOwner().rootNode = root;
+  root.layout(const BoxConstraints());
+  return (group, glasses);
+}
+
+void main() {
+  TestWidgetsFlutterBinding.ensureInitialized();
+
+  test('a sinking or pending ghost counts toward the sixteen shapes of a container, and is left out before a member is', () async {
+    final (group, glasses) = await _group([for (var i = 0; i < 15; i++) _Motion(), for (var i = 0; i < 3; i++) _Motion(transient: true)]);
+    final (_, shapes, _) = group.gatherShapeData();
+    expect(shapes, hasLength(LiquidGlassBlendGroup.maxShapesPerLayer));
+    expect(shapes.map((shape) => shape.renderObject), glasses.take(16));
+  });
+
+  test('sixteen members and a ghost draw the members and leave the ghost out, where the upload would otherwise throw', () async {
+    final (group, glasses) = await _group([for (var i = 0; i < 16; i++) _Motion(), _Motion(transient: true)]);
+    final (_, shapes, _) = group.gatherShapeData();
+    expect(shapes.map((shape) => shape.renderObject), glasses.take(16));
+  });
+
+  test('ghosts under the cap all stay in the geometry', () async {
+    final (group, glasses) = await _group([for (var i = 0; i < 12; i++) _Motion(), for (var i = 0; i < 4; i++) _Motion(transient: true)]);
+    final (_, shapes, _) = group.gatherShapeData();
+    expect(shapes.map((shape) => shape.renderObject), glasses);
+  });
+
+  test('a ghost registered before the last member is the one left out', () async {
+    final (group, glasses) = await _group([for (var i = 0; i < 8; i++) _Motion(), _Motion(transient: true), for (var i = 0; i < 8; i++) _Motion()]);
+    final (_, shapes, _) = group.gatherShapeData();
+    expect(shapes, hasLength(16));
+    expect(shapes.map((shape) => shape.renderObject), isNot(contains(glasses[8])));
+  });
+}
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t15-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_group_test.dart` => FAIL

Expected output ends with:

```text
+1 -3: Some tests failed.
```

Expected: three of the four tests fail on `Expected: an object with length of <16>` or on the ghost that should have been left out (18, 17 and 16 shapes drawn); `ghosts under the cap all stay in the geometry` passes before and after, by design.

- [ ] **Step 3: Apply the implementation.**

Patch `t15-impl` (`42f09d87f..19e53ff72`, 1 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
index 93cfe1968e932d792ee3a08027de2d43038d70d5..27d116131700bdffa852444c0ae7e5e9709f41c0 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
@@ -301,7 +301,7 @@ class RenderLiquidGlassBlendGroup extends RenderLiquidGlassGeometry
 
   @override
   (Rect, List<ShapeGeometry>, bool) gatherShapeData() {
-    final shapes = <ShapeGeometry>[];
+    final candidates = <(ShapeGeometry, bool)>[];
     final cachedShapes = geometry?.shapes ?? [];
 
     var anyShapeChangedInLayer = false;
@@ -317,32 +317,44 @@ class RenderLiquidGlassBlendGroup extends RenderLiquidGlassGeometry
       try {
         final union = renderObject.unionOutline;
         if (union != null && !union.leads) continue;
-        final shapeData = _computeShapeInfo(
-          renderObject,
-          union?.shape ?? shape,
-          glassContainsChild,
-          union?.rect ?? renderObject.drawnRect,
-        );
-        final index = shapes.length;
-        shapes.add(shapeData);
-
-        layerBounds = layerBounds?.expandToInclude(shapeData.shapeBounds) ??
-            shapeData.shapeBounds;
-
-        final existingShape =
-            cachedShapes.length > index ? cachedShapes[index] : null;
-
-        if (existingShape == null) {
-          anyShapeChangedInLayer = true;
-        } else if (existingShape.shapeBounds != shapeData.shapeBounds ||
-            existingShape.shape != shapeData.shape) {
-          anyShapeChangedInLayer = true;
-        }
+        candidates.add((
+          _computeShapeInfo(
+            renderObject,
+            union?.shape ?? shape,
+            glassContainsChild,
+            union?.rect ?? renderObject.drawnRect,
+          ),
+          renderObject.motion?.isTransient ?? false,
+        ));
       } catch (e) {
         debugPrint('Failed to compute shape info: $e');
       }
     }
 
+    var excess = candidates.length - LiquidGlassBlendGroup.maxShapesPerLayer;
+    for (var i = candidates.length - 1; i >= 0 && excess > 0; i--) {
+      if (!candidates[i].$2) continue;
+      candidates.removeAt(i);
+      excess--;
+    }
+
+    final shapes = [for (final (shapeData, _) in candidates) shapeData];
+
+    for (final (index, shapeData) in shapes.indexed) {
+      layerBounds = layerBounds?.expandToInclude(shapeData.shapeBounds) ??
+          shapeData.shapeBounds;
+
+      final existingShape =
+          cachedShapes.length > index ? cachedShapes[index] : null;
+
+      if (existingShape == null) {
+        anyShapeChangedInLayer = true;
+      } else if (existingShape.shapeBounds != shapeData.shapeBounds ||
+          existingShape.shape != shapeData.shape) {
+        anyShapeChangedInLayer = true;
+      }
+    }
+
     if (cachedShapes.length != shapes.length) anyShapeChangedInLayer = true;
 
     return (
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t15-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_group_test.dart` => PASS

Expected output ends with:

```text
+4: All tests passed!
```

- [ ] **Step 5: Gate: package.**

RUN[t15-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t15-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

Expected output ends with:

```text
+208: All tests passed!
```

- [ ] **Step 6: Gate: example.**

RUN[t15-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t15-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

Expected output ends with:

```text
+23: All tests passed!
```

- [ ] **Step 7: Commit.**

```bash
git add -A packages
git commit -m "fix(ios_liquid_glass): ghosts count toward a container's sixteen shapes and are left out before a member, so paint never throws for them

Co-Authored-By: <the session's attribution line>"
```

### Task 16: A shape motion syncs itself and says whether it moved; a geometry asks before it trusts its cache (nothing answers yes yet)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart`, `lib/src/motion/glass_motion_coordinator.dart`, `lib/src/internal/render_liquid_glass_geometry.dart` (`shapesMoved`, `revalidateGeometry`)
- Test: `test/motion/render_hooks_test.dart`, `glass_union_test.dart`, `glass_group_test.dart` (fakes implement `syncMoved`)

**Why.** Ruling 29. Two refactors with no behaviour change (the member answers `false`, `shapesMoved` answers `false`), so that Task 17's tests fail on assertions.

- [ ] **Step 1: Apply the implementation.**

Patch `t16-impl` (`19e53ff72..7bf674822`, 6 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/internal/render_liquid_glass_geometry.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/internal/render_liquid_glass_geometry.dart
index 3426fb78d074941652fdb0ce6a262d8beb687053..ed8fb9f1ba88fbd86cd5e892669efbda87bdb6e6 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/internal/render_liquid_glass_geometry.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/internal/render_liquid_glass_geometry.dart
@@ -226,8 +226,17 @@ abstract class RenderLiquidGlassGeometry extends RenderProxyBox {
     return path;
   }
 
+  @protected
+  bool shapesMoved() => false;
+
+  @visibleForTesting
+  void revalidateGeometry() {
+    if (shapesMoved()) markGeometryNeedsUpdate();
+  }
+
   /// Should be called from within [paint] to maybe rebuild the [geometry].
   GeometryCache? maybeRebuildGeometry() {
+    revalidateGeometry();
     if (geometryState == LiquidGlassGeometryState.updated && geometry != null) {
       return geometry;
     }
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
index 5200720edddd2580ee7ac243cd2144bfdb7bf6b7..95348887fe555d7dc34a9ee4d73b95c6cbaef907 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
@@ -245,6 +245,12 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
 
   void sync() => _sync();
 
+  @override
+  bool syncMoved() {
+    _sync();
+    return false;
+  }
+
   void _sync() {
     final box = _box;
     final space = coordinator.space;
@@ -529,6 +535,9 @@ class GlassGhost extends ChangeNotifier implements GlassShapeMotion {
   @override
   bool get isTransient => true;
 
+  @override
+  bool syncMoved() => false;
+
   @override
   void dispose() {
     snapshot?.dispose();
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart
index ba796d795f75b099d7ee1e1f915df5904a1f3bf6..b2d265e765b44c694998f7b23ac059905fa083a0 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_shape_motion.dart
@@ -9,6 +9,8 @@ abstract interface class GlassShapeMotion implements Listenable {
   GlassUnionOutline? union(RenderBox shape);
 
   bool get isTransient;
+
+  bool syncMoved();
 }
 
 @internal
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_group_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_group_test.dart
index 05c9b292297a82c53dd6c85145f932101455d4a0..b790a2ed2fdc30857d5f96911c25e6e675216e96 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_group_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_group_test.dart
@@ -23,6 +23,9 @@ class _Motion extends ChangeNotifier implements GlassShapeMotion {
   @override
   bool get isTransient => transient;
 
+  @override
+  bool syncMoved() => false;
+
   @override
   GlassUnionOutline? union(RenderBox shape) => null;
 }
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_union_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_union_test.dart
index 06d5d81c9441c845d96dd7b09157eedef5a7560b..efcb5b22ec7f046b8d622888c15db6497770f01e 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_union_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_union_test.dart
@@ -69,6 +69,9 @@ class _Motion extends ChangeNotifier implements GlassShapeMotion {
   @override
   bool get isTransient => false;
 
+  @override
+  bool syncMoved() => false;
+
   @override
   GlassUnionOutline? union(RenderBox shape) => outline;
 }
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/render_hooks_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/render_hooks_test.dart
index c6a352b413bf507d8be290fbb96089c1e3663fa5..447609ae83412ca12db053c195852a4ebb9e60b7 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/render_hooks_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/render_hooks_test.dart
@@ -22,6 +22,9 @@ class _Motion extends ChangeNotifier implements GlassShapeMotion {
   @override
   bool get isTransient => false;
 
+  @override
+  bool syncMoved() => false;
+
   @override
   GlassUnionOutline? union(RenderBox shape) => null;
 
```

- [ ] **Step 2: Gate: package.**

RUN[t16-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t16-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

Expected output ends with:

```text
+208: All tests passed!
```

- [ ] **Step 3: Commit.**

```bash
git add -A packages
git commit -m "refactor(ios_liquid_glass): a shape motion syncs itself and says whether it moved; a geometry asks whether its shapes moved before it trusts its cache

Co-Authored-By: <the session's attribution line>"
```

### Task 17: Glass whose anchor changes has its container's geometry rebuilt in that frame (the first frame of a move)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart` (`GlassMember._moved`, `syncMoved`), `lib/src/liquid_glass_blend_group.dart` (`shapesMoved`)
- Test: `test/motion/glass_space_shift_test.dart` (new), `test/motion/glass_group_test.dart`

**Why.** Ruling 29 (D5). In the frame of a tap Flutter drew a glass at the container's shift: the blend group decides in `paint` whether to rebuild its geometry matte, before its members' `sync` has found that their anchors changed, so it reused last frame's matte (group-local) at the group's new position, and the next frame, when the members' springs notify, drew it right (`R/verify/summary.txt` 1c: 8 of 8 split onsets, 5 of 8 merge onsets). Shadows were right because they read `drawn` after `sync`. The group now asks each glass to sync, and a glass that moved marks the geometry as possibly stale, before the decision. Verified in the real app, `R/onset/flutter-merge-light-stripes-after.txt` (run `20261007-114536`): no frame at the mirror at either onset.

- [ ] **Step 1: Add the failing tests.**

Patch `t17-tests` (`7bf674822..ab9ee28c6`, 2 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_group_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_group_test.dart
index b790a2ed2fdc30857d5f96911c25e6e675216e96..bfa4fe97e3428ff7999b8110259b82c394829d98 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_group_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_group_test.dart
@@ -16,6 +16,7 @@ class _Motion extends ChangeNotifier implements GlassShapeMotion {
   _Motion({this.transient = false});
 
   final bool transient;
+  bool moved = false;
 
   @override
   Rect resolve(RenderBox shape) => Offset.zero & shape.size;
@@ -24,7 +25,11 @@ class _Motion extends ChangeNotifier implements GlassShapeMotion {
   bool get isTransient => transient;
 
   @override
-  bool syncMoved() => false;
+  bool syncMoved() {
+    final result = moved;
+    moved = false;
+    return result;
+  }
 
   @override
   GlassUnionOutline? union(RenderBox shape) => null;
@@ -39,6 +44,10 @@ class _Group extends RenderLiquidGlassBlendGroup {
 
   @override
   void updateGeometryShaderShapes(List<ShapeGeometry> shapes) {}
+
+  LiquidGlassGeometryState get state => geometryState;
+
+  void settle() => geometryState = LiquidGlassGeometryState.updated;
 }
 
 Future<(_Group, List<RenderLiquidGlass>)> _group(List<_Motion> motions) async {
@@ -86,4 +95,24 @@ void main() {
     expect(shapes, hasLength(16));
     expect(shapes.map((shape) => shape.renderObject), isNot(contains(glasses[8])));
   });
+
+  test('a settled geometry is marked for an update in the frame a member moves, and left alone when none did', () async {
+    final moving = _Motion(), still = _Motion();
+    final (group, _) = await _group([still, moving]);
+    group.settle();
+    expect(group.state, LiquidGlassGeometryState.updated);
+    group.revalidateGeometry();
+    expect(group.state, LiquidGlassGeometryState.updated);
+    moving.moved = true;
+    group.revalidateGeometry();
+    expect(group.state, LiquidGlassGeometryState.mightNeedUpdate);
+    expect(moving.moved, isFalse);
+  });
+
+  test('a ghost reports nothing, so it never marks the geometry', () async {
+    final (group, _) = await _group([_Motion(transient: true)]);
+    group.settle();
+    group.revalidateGeometry();
+    expect(group.state, LiquidGlassGeometryState.updated);
+  });
 }
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_space_shift_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_space_shift_test.dart
new file mode 100644
index 0000000000000000000000000000000000000000..fe40908997049e59d850331b55772bfe59182e4c
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_space_shift_test.dart
@@ -0,0 +1,120 @@
+import 'package:flutter/material.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
+import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
+import 'package:ios_liquid_glass/src/shaders.dart';
+
+class _Center extends SingleChildLayoutDelegate {
+  const _Center();
+
+  @override
+  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();
+
+  @override
+  Offset getPositionForChild(Size size, Size childSize) =>
+      Offset(((size.width - childSize.width) / 2).roundToDouble(), ((size.height - childSize.height) / 2).roundToDouble());
+
+  @override
+  bool shouldRelayout(_Center oldDelegate) => false;
+}
+
+class _Merge extends StatefulWidget {
+  const _Merge();
+
+  @override
+  State<_Merge> createState() => _MergeState();
+}
+
+class _MergeState extends State<_Merge> {
+  bool merged = false;
+
+  void set(bool value, {bool animated = true}) {
+    if (animated) {
+      withGlassAnimation(GlassAnimation.defaultSpring, () => setState(() => merged = value));
+    } else {
+      setState(() => merged = value);
+    }
+  }
+
+  @override
+  Widget build(BuildContext context) {
+    return MaterialApp(
+      home: GlassTheme(
+        data: const GlassThemeData(brightness: Brightness.dark),
+        child: Stack(
+          children: [
+            Positioned.fill(
+              child: CustomSingleChildLayout(
+                delegate: const _Center(),
+                child: GlassEffectContainer(
+                  spacing: 40,
+                  child: Row(
+                    mainAxisSize: MainAxisSize.min,
+                    children: [
+                      const GlassEffect(key: ValueKey('left'), shape: GlassShape.circle(), child: SizedBox.square(dimension: 80)),
+                      SizedBox(width: merged ? 0 : 80),
+                      const GlassEffect(key: ValueKey('right'), shape: GlassShape.circle(), child: SizedBox.square(dimension: 80)),
+                    ],
+                  ),
+                ),
+              ),
+            ),
+          ],
+        ),
+      ),
+    );
+  }
+}
+
+GlassMember _member(WidgetTester tester, String key) => tester
+    .renderObject<RenderGlassMemberBox>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(GlassMemberBox)).first)
+    .member;
+
+Rect _onScreen(GlassMember member) => MatrixUtils.transformRect(member.coordinator.space!.getTransformTo(null), member.drawn!);
+
+void main() {
+  isLocalTest = true;
+  tearDown(debugResetGlassAnimation);
+
+  testWidgets('both circles report that they moved in the frame the container shrinks and re-centres, and once only', (tester) async {
+    await tester.pumpWidget(const _Merge());
+    await tester.pump(const Duration(seconds: 1));
+    final left = _member(tester, 'left'), right = _member(tester, 'right');
+    expect(left.syncMoved(), isFalse);
+    expect(right.syncMoved(), isFalse);
+    final oldLeft = _onScreen(left), oldRight = _onScreen(right);
+    tester.state<_MergeState>(find.byType(_Merge)).set(true);
+    await tester.pump();
+    expect(left.syncMoved(), isTrue);
+    expect(right.syncMoved(), isTrue);
+    expect(left.syncMoved(), isFalse);
+    expect(right.syncMoved(), isFalse);
+    expect(_onScreen(left), oldLeft);
+    expect(_onScreen(right), oldRight);
+    await tester.pump(const Duration(milliseconds: 16));
+    expect(left.syncMoved(), isFalse);
+    expect(right.syncMoved(), isFalse);
+    await tester.pumpAndSettle();
+  });
+
+  testWidgets('a move without an animation is reported as well, so the geometry never lags the layout by a frame', (tester) async {
+    await tester.pumpWidget(const _Merge());
+    await tester.pump(const Duration(seconds: 1));
+    final left = _member(tester, 'left'), right = _member(tester, 'right');
+    tester.state<_MergeState>(find.byType(_Merge)).set(true, animated: false);
+    await tester.pump();
+    expect(left.syncMoved(), isTrue);
+    expect(right.syncMoved(), isTrue);
+    await tester.pumpAndSettle();
+  });
+
+  testWidgets('a member reads as unmoved when only the container around it changes size', (tester) async {
+    await tester.pumpWidget(const _Merge());
+    await tester.pump(const Duration(seconds: 1));
+    final left = _member(tester, 'left');
+    expect(left.syncMoved(), isFalse);
+    await tester.pump(const Duration(milliseconds: 100));
+    expect(left.syncMoved(), isFalse);
+  });
+}
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t17-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart test/motion/glass_group_test.dart` => FAIL

Expected output ends with:

```text
+6 -3: Some tests failed.
```

Expected: `both circles report that they moved...`, `a move without an animation is reported...` and `a settled geometry is marked for an update...` fail (the member and the group answer `false` before the implementation); the others pass.

- [ ] **Step 3: Apply the implementation.**

Patch `t17-impl` (`7bf674822..ab9ee28c6`, 2 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
index 27d116131700bdffa852444c0ae7e5e9709f41c0..9659799223cbb661a73ac11c5407d6a5859fcdf5 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart
@@ -299,6 +299,17 @@ class RenderLiquidGlassBlendGroup extends RenderLiquidGlassGeometry
     });
   }
 
+  @override
+  bool shapesMoved() {
+    var moved = false;
+    for (final entry in link.shapeEntries) {
+      final renderObject = entry.key;
+      if (!renderObject.attached || !renderObject.hasSize) continue;
+      moved = (renderObject.motion?.syncMoved() ?? false) || moved;
+    }
+    return moved;
+  }
+
   @override
   (Rect, List<ShapeGeometry>, bool) gatherShapeData() {
     final candidates = <(ShapeGeometry, bool)>[];
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
index 95348887fe555d7dc34a9ee4d73b95c6cbaef907..9aecd497685e8570aea3f5dd20da3fdb7aadf0fe 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
@@ -47,6 +47,7 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
   _Arrival? _arrival;
   bool _contentFades = false;
   bool _sinking = false;
+  bool _moved = false;
   GlassPresence presence = GlassPresence.present;
   GlassMaterializeMapping _mapping = GlassMaterializeMapping.defaultSpring;
   bool reduceMotion = false;
@@ -248,7 +249,9 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
   @override
   bool syncMoved() {
     _sync();
-    return false;
+    final moved = _moved;
+    _moved = false;
+    return moved;
   }
 
   void _sync() {
@@ -270,12 +273,14 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
     if (arrival != null && size != null) {
       _arrival = null;
       _anchor = anchor;
+      _moved = true;
       _arrive(arrival, live & size);
       return;
     }
     final previous = _anchor;
     _anchor = anchor;
     if (previous == null || previous == anchor) return;
+    _moved = true;
     final animation = _changed();
     if (animation == null) return;
     final now = coordinator._now;
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t17-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart test/motion/glass_group_test.dart` => PASS

Expected output ends with:

```text
+9: All tests passed!
```

- [ ] **Step 5: Gate: package.**

RUN[t17-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t17-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

Expected output ends with:

```text
+213: All tests passed!
```

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "fix(ios_liquid_glass): glass whose anchor changes has the container's geometry rebuilt in that frame, so the first frame of a move is not drawn at the container's shift

Co-Authored-By: <the session's attribution line>"
```

### Task 18: A space that moves on screen as its container resizes is part of the glass's anchor (a morph does not start from the mirror of its start)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart` (`GlassMember._sync`)
- Test: `test/motion/glass_space_shift_test.dart` (two tests)

**Why.** Ruling 29 (D5). The anchor was the glass's place in its space; when the space itself moves on screen at the same time (the morph scene's column re-centres as the stack grows, so the toggle's space moves 108 pt up while the toggle's place in it moves 216 down), the offset the glass springs from was computed without the space's move and the toggle started at 2 x old - new (343 for 451 to 559), for the whole spring. The anchor now adds the space's on-screen origin (outer scrolling excluded), and Task 24b limits that to the frames in which the glass's own place in the space changed. Verified in the real app (`R/onset/flutter-morph-light-stripes-after.txt`, run `20261007-115120`): the toggle's first frames stay at 451 and the badges leave it. This also removes the cause of ruling 21 (c) as the prototype described it (the heart first seen at the star's slot); whether emergence now equals native's is for Task 27 to measure.

- [ ] **Step 1: Add the failing tests.**

Patch `t18-tests` (`ab9ee28c6..6569e47e2`, 1 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_space_shift_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_space_shift_test.dart
index fe40908997049e59d850331b55772bfe59182e4c..36d09f355bda14a643b4206953d69a8a6c233456 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_space_shift_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_space_shift_test.dart
@@ -67,6 +67,48 @@ class _MergeState extends State<_Merge> {
   }
 }
 
+class _Grow extends StatefulWidget {
+  const _Grow();
+
+  @override
+  State<_Grow> createState() => _GrowState();
+}
+
+class _GrowState extends State<_Grow> {
+  bool grown = false;
+
+  void toggle() => withGlassAnimation(GlassAnimation.defaultSpring, () => setState(() => grown = !grown));
+
+  @override
+  Widget build(BuildContext context) {
+    return MaterialApp(
+      home: GlassTheme(
+        data: const GlassThemeData(brightness: Brightness.dark),
+        child: CustomSingleChildLayout(
+          delegate: const _Center(),
+          child: Column(
+            mainAxisSize: MainAxisSize.min,
+            children: [
+              GlassEffectContainer(
+                spacing: 20,
+                child: Column(
+                  mainAxisSize: MainAxisSize.min,
+                  children: [
+                    if (grown) const SizedBox(height: 100, width: 56),
+                    const GlassEffect(key: ValueKey('g'), child: SizedBox.square(dimension: 56)),
+                  ],
+                ),
+              ),
+            ],
+          ),
+        ),
+      ),
+    );
+  }
+}
+
+Rect _layout(WidgetTester tester, String key) => tester.getRect(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(GlassMemberBox)).first);
+
 GlassMember _member(WidgetTester tester, String key) => tester
     .renderObject<RenderGlassMemberBox>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(GlassMemberBox)).first)
     .member;
@@ -117,4 +159,36 @@ void main() {
     await tester.pump(const Duration(milliseconds: 100));
     expect(left.syncMoved(), isFalse);
   });
+
+  testWidgets('glass in a space that re-centres as its container grows is drawn at its old place in the frame of the change and springs to the new', (tester) async {
+    await tester.pumpWidget(const _Grow());
+    await tester.pump(const Duration(seconds: 1));
+    final old = _layout(tester, 'g');
+    final member = _member(tester, 'g');
+    tester.state<_GrowState>(find.byType(_Grow)).toggle();
+    await tester.pump();
+    final target = _layout(tester, 'g');
+    expect(target.top - old.top, closeTo(50, 1e-6));
+    expect(_onScreen(member).top, closeTo(old.top, 1e-6));
+    await tester.pump(const Duration(milliseconds: 100));
+    expect(_onScreen(member).top, inExclusiveRange(old.top, target.top));
+    await tester.pumpAndSettle();
+    expect(_onScreen(member).top, closeTo(target.top, 1e-6));
+  });
+
+  testWidgets('glass in a space that re-centres as its container shrinks is drawn at its old place in the frame of the change', (tester) async {
+    await tester.pumpWidget(const _Grow());
+    final state = tester.state<_GrowState>(find.byType(_Grow));
+    state.toggle();
+    await tester.pumpAndSettle();
+    final old = _layout(tester, 'g');
+    final member = _member(tester, 'g');
+    state.toggle();
+    await tester.pump();
+    final target = _layout(tester, 'g');
+    expect(target.top - old.top, closeTo(-50, 1e-6));
+    expect(_onScreen(member).top, closeTo(old.top, 1e-6));
+    await tester.pumpAndSettle();
+    expect(_onScreen(member).top, closeTo(target.top, 1e-6));
+  });
 }
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t18-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart` => FAIL

Expected output ends with:

```text
+3 -2: Some tests failed.
```

Expected: the two `glass in a space that re-centres...` tests fail on `Actual: <222.0>` against 272.0 (grow) and `Actual: <372.0>` against 322.0 (shrink): the glass is drawn 50 pt from where it was.

- [ ] **Step 3: Apply the implementation.**

Patch `t18-impl` (`ab9ee28c6..6569e47e2`, 1 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
index 9aecd497685e8570aea3f5dd20da3fdb7aadf0fe..a579a79a15efbbd0abeb854a31a139db0cac61ae 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
@@ -260,7 +260,6 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
     if (box == null || space == null || !box.attached || !space.attached || !box.hasSize) return;
     final live = MatrixUtils.transformPoint(box.getTransformTo(space), Offset.zero);
     final inner = _scrollShift(space);
-    final anchor = live - inner;
     _live = live;
     _liveSpace = space;
     _innerAtLive = inner;
@@ -269,6 +268,7 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
       _originFrame = frame;
       _readSpace(space, inner);
     }
+    final anchor = live - inner + _spaceOrigin! - _outerAtOrigin;
     final arrival = _arrival, size = _size;
     if (arrival != null && size != null) {
       _arrival = null;
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t18-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart` => PASS

Expected output ends with:

```text
+5: All tests passed!
```

- [ ] **Step 5: Gate: package.**

RUN[t18-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t18-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

Expected output ends with:

```text
+215: All tests passed!
```

- [ ] **Step 6: Gate: example.**

RUN[t18-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t18-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

Expected output ends with:

```text
+23: All tests passed!
```

**The app gate is not run in this task or in Task 20:** the app's `floating_working_control_test` (`reduce motion changes instantly and runs no shimmer ticker`) fails from here until Task 24b, which fixes the over-broad anchor this task introduced (the first replay found it). The app gate runs again, whole, at Task 24b.

- [ ] **Step 7: Commit.**

```bash
git add -A packages
git commit -m "fix(ios_liquid_glass): a space that moves on screen as its container resizes is part of the glass's anchor, so a morph does not start from the mirror of its start

Co-Authored-By: <the session's attribution line>"
```

### Task 19: Merge is judged by each circle's outer edge and the pair's gap, morph by the stack's outer edges (D3, a user-approved manifest correction)

**Files:**
- Modify: `tool/glass_lab/harness/track.py` (`shape_row` edges, `topology_row` gap), `shapes.py` (`EDGE_KEYS`, `gap_rms`, `significant`), `manifest.py` (`EDGE_KEYS`, `edges`)
- Modify: `tool/glass_lab/scenes.json` (`material.merge`, `material.morph`, `material.morph.plain`)
- Test: `tool/glass_lab/harness/tests/{test_track,test_shapes,test_manifest}.py`

**Why.** Ruling 26 (D3). Approved by the user on 2026-10-07 as a manifest correction, not a loosening. `material.merge` listed `width.*` for circles that never change width (20 absent measures per case, class (b)); its replacement is each circle's outer edge (the left circle's left edge `xmin`, the right circle's right edge `xmax`, which no bridge crosses) and the pair's `gap_rms` beside the join, split, neck and count it already had. `material.morph` keeps every measure it had and gains the stack's top and bottom edges (`ymin`, `ymax`: the star's top and the toggle's bottom). New keys are `MOTION_MEASURES` entries with tests; the old and new counts on the same recordings are in the Done table template.

- [ ] **Step 1: Add the failing tests.**

Patch `t19-tests` (`6569e47e2..5ed43ab6e`, 3 files):

```diff
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py b/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py
index edec7787c9d085e03acee22e2e2698da3e36fdbe..f93799e23a9adc0c6712139f476c4ec9bb66075e 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py
@@ -86,6 +86,26 @@ class RealManifestTests(unittest.TestCase):
         self.assertEqual(lab, registered)
 
 
+class RealMotionManifestTests(unittest.TestCase):
+    @staticmethod
+    def entry(scene_id):
+        return next(entry for entry in json.loads(manifest.MANIFEST.read_text()) if entry["id"] == scene_id)
+
+    def test_merge_judges_each_circle_by_its_outer_edge_and_the_pair_by_join_neck_and_gap(self):
+        entry = self.entry("material.merge")
+        self.assertEqual(entry["edges"], {"left": ["xmin"], "right": ["xmax"]})
+        self.assertFalse([m for m in entry["motion"] if m.startswith("width.")])
+        for name in ("xmin.settle_ms", "xmax.settle_ms", "cx.settle_ms", "topology.join_ms", "topology.split_ms", "topology.neck_rms", "topology.gap_rms", "topology.count"):
+            self.assertIn(name, entry["motion"])
+
+    def test_morph_judges_the_stack_by_the_edges_of_its_outermost_glasses(self):
+        for scene_id in ("material.morph", "material.morph.plain"):
+            entry = self.entry(scene_id)
+            self.assertEqual(entry["edges"], {"stack": ["ymin", "ymax"]})
+            for name in ("ymin.settle_ms", "ymax.settle_ms", "ymin.response_pct", "ymax.damping", "cy.settle_ms", "width.settle_ms", "topology.gap_rms"):
+                self.assertIn(name, entry["motion"])
+
+
 class TrackTests(unittest.TestCase):
     def base(self, **changes):
         entry = {"id": "x", "group": "material", "title": "t", "inventory": "2.13", "app": "lab", "backdrops": ["stripes"], "appearances": ["dark"], "steps": [], "regions": {"a": [0, 0, 1, 1], "b": [1, 1, 1, 1]}}
@@ -112,7 +132,26 @@ class TrackTests(unittest.TestCase):
         self.assertTrue(any("non-empty list" in e for e in manifest.validate([self.base(track=[])])))
         self.assertTrue(any("unknown motion measure progress.wobble" in e for e in manifest.validate([self.base(track="a", motion=["progress.wobble"])])))
         self.assertTrue(any("need a track" in e for e in manifest.validate([self.base(motion=["progress.rms"])])))
-        self.assertEqual(manifest.validate([self.base(track="a", topology="a", motion=list(manifest.MOTION_MEASURES))]), [])
+        edges = {"a": list(manifest.EDGE_KEYS)}
+        self.assertEqual(manifest.validate([self.base(track="a", topology="a", edges=edges, motion=list(manifest.MOTION_MEASURES))]), [])
+
+    def test_edges_name_regions_and_edge_keys_and_the_edge_measures_need_them(self):
+        scene = manifest.parse([self.base(track="a", edges={"a": ["xmin", "ymax"]})])[0]
+        self.assertEqual(scene.edges, {"a": ("xmin", "ymax")})
+        self.assertEqual(manifest.parse([self.base(track="a")])[0].edges, {})
+        self.assertTrue(any("edges names an unknown region" in e for e in manifest.validate([self.base(track="a", edges={"z": ["xmin"]})])))
+        self.assertTrue(any("edges names a region that is not tracked" in e for e in manifest.validate([self.base(track="a", edges={"b": ["xmin"]})])))
+        self.assertTrue(any("unknown edge left" in e for e in manifest.validate([self.base(track="a", edges={"a": ["left"]})])))
+        self.assertTrue(any("edges must map a region to a non-empty list" in e for e in manifest.validate([self.base(track="a", edges={"a": []})])))
+        errors = manifest.validate([self.base(track="a", motion=["xmin.peak_ms"])])
+        self.assertTrue(any("edge measures need edges" in e for e in errors))
+        errors = manifest.validate([self.base(track="a", edges={"a": ["xmax"]}, motion=["xmin.peak_ms"])])
+        self.assertTrue(any("xmin.peak_ms needs a region with the edge xmin" in e for e in errors))
+        self.assertEqual(manifest.validate([self.base(track="a", edges={"a": ["xmin"]}, motion=["xmin.peak_ms"])]), [])
+
+    def test_the_gap_and_edge_measures_are_known_motion_measures(self):
+        for name in ("topology.gap_rms", "xmin.peak_ms", "xmax.settle_ms", "ymin.response_pct", "ymax.damping", "xmin.overshoot_pct"):
+            self.assertIn(name, manifest.MOTION_MEASURES)
 
     def test_tracked_regions_are_not_rim_elements_and_the_union_is_the_region(self):
         scene = manifest.parse([self.base(track=["a"])])[0]
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py b/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py
index 12a2884f4c68525d8564bb8f04a81614f71b5fc8..532ba27b73b64fe8704e176c8ad174f92967c59e 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py
@@ -11,6 +11,7 @@ sys.path.insert(0, str(Path(__file__).resolve().parent))
 
 import analyze
 import manifest
+import metrics
 import shapes
 import springfit
 from synthetic import capture_of, glass_pair, spring_series
@@ -18,11 +19,12 @@ from synthetic import capture_of, glass_pair, spring_series
 
 class ShapeTopologyTests(unittest.TestCase):
     @staticmethod
-    def series(join, split, length=80, neck=10.0):
+    def series(join, split, length=80, neck=10.0, gap=6.0):
         nan = float("nan")
         count = [2.0] * join + [1.0] * (split - join) + [2.0] * (length - split)
         necks = [nan] * join + [neck] * (split - join) + [nan] * (length - split)
-        return {"count": count, "neck": necks}
+        gaps = [gap] * join + [nan] * (split - join) + [gap] * (length - split)
+        return {"count": count, "neck": necks, "gap": gaps}
 
     def test_join_and_split_times_and_count_mismatches_are_compared(self):
         late = shapes.compare_topology(self.series(20, 60), self.series(23, 60))
@@ -40,6 +42,29 @@ class ShapeTopologyTests(unittest.TestCase):
         late = shapes.compare_topology(self.series(20, 60), self.series(23, 60, neck=13.0))
         self.assertAlmostEqual(late["neck_rms"], 3.0, places=6)
 
+    def test_the_gap_is_compared_only_where_both_apps_have_one(self):
+        same = shapes.compare_topology(self.series(20, 60), self.series(20, 60))
+        self.assertEqual(same["gap_rms"], 0.0)
+        wider = shapes.compare_topology(self.series(20, 60), self.series(20, 60, gap=9.0))
+        self.assertAlmostEqual(wider["gap_rms"], 3.0, places=6)
+        late = shapes.compare_topology(self.series(20, 60), self.series(23, 60, gap=9.0))
+        self.assertAlmostEqual(late["gap_rms"], 3.0, places=6)
+
+    def test_a_gap_in_one_app_against_none_in_the_other_fails_and_agreeing_apps_read_zero(self):
+        nan = float("nan")
+        one = {"count": [1.0] * 5, "neck": [5.0] * 5, "gap": [nan] * 5}
+        self.assertEqual(shapes.compare_topology(one, one)["gap_rms"], 0.0)
+        found = shapes.compare_topology(one, {"count": [1.0] * 5, "neck": [5.0] * 5, "gap": [4.0] * 5})
+        self.assertEqual(found["gap_rms"], float("inf"))
+
+    def test_a_series_without_a_gap_has_no_gap_measure(self):
+        plain = {"count": [1.0] * 5, "neck": [5.0] * 5}
+        self.assertNotIn("gap_rms", shapes.compare_topology(plain, plain))
+
+    def test_gap_rms_has_the_gap_threshold(self):
+        self.assertEqual(shapes.LIMITS["gap_rms"], "gap_pt")
+        self.assertEqual(metrics.THRESHOLDS["gap_pt"], 1.0)
+
     def test_apps_that_agree_on_no_transition_read_zero_not_absent(self):
         one = {"count": [1.0] * 5, "neck": [5.0] * 5}
         agreed = shapes.compare_topology(one, one)
@@ -109,11 +134,13 @@ class ShapeTopologyTests(unittest.TestCase):
     def test_the_neck_series_holds_each_frame_like_the_count(self):
         nan = float("nan")
         rows = [{"count": 2.0, "neck": nan}, {"count": 1.0, "neck": 6.0}, {"count": 1.0, "neck": 8.0}, {"count": 2.0, "neck": nan}]
-        rows = [dict(row, width=80.0, height=80.0, cx=1.0, cy=1.0, luma=1.0, progress=1.0, sharpness=0.0, residual=0.0) for row in rows]
+        rows = [dict(row, gap=[3.0, nan, nan, 3.0][i], width=80.0, height=80.0, cx=1.0, cy=1.0, xmin=0.0, xmax=1.0, ymin=0.0, ymax=1.0, luma=1.0, progress=1.0, sharpness=0.0, residual=0.0) for i, row in enumerate(rows)]
         series = shapes.event_series([0.0, 0.05, 0.1, 0.15], rows, 0, 3)
-        count, neck = np.array(series["count"]), np.array(series["neck"])
+        count, neck, gap = np.array(series["count"]), np.array(series["neck"]), np.array(series["gap"])
         self.assertTrue(np.isnan(neck[count == 2]).all())
         self.assertTrue(np.isfinite(neck[count == 1]).all())
+        self.assertTrue(np.isnan(gap[count == 1]).all())
+        self.assertTrue(np.isfinite(gap[count == 2]).all())
 
 
 class ProgressMeasureTests(unittest.TestCase):
@@ -126,7 +153,7 @@ class ProgressMeasureTests(unittest.TestCase):
     def test_a_variable_rate_capture_reads_the_same_ten_to_ninety_time_within_a_frame(self):
         rng = np.random.default_rng(7)
         times = np.cumsum(np.concatenate([[0.0], rng.choice([1 / 120, 1 / 60, 0.033, 0.053], 40)]))
-        rows = [{"width": 250.0, "height": 88.0, "cx": 201.0, "cy": 451.0, "luma": 100.0, "progress": float(p), "sharpness": 0.0, "residual": 0.0}
+        rows = [{"width": 250.0, "height": 88.0, "cx": 201.0, "cy": 451.0, "xmin": 76.0, "xmax": 326.0, "ymin": 407.0, "ymax": 495.0, "luma": 100.0, "progress": float(p), "sharpness": 0.0, "residual": 0.0}
                 for p in springfit.step_response(times, 0.55, 1.0)]
         series = shapes.event_series(list(times), rows, 0, len(times) - 1)
         exact = shapes.progress_features(spring_series(0.55, 1.0))["t10_90_ms"]
@@ -267,6 +294,49 @@ class NothingPassesByBeingAbsentTests(unittest.TestCase):
         self.assertEqual(result["pairs"]["step0e0"]["shapes"]["block"]["first_frame"]["flutter"], {"gap_ms": 33.0, "progress": 0.73})
 
 
+class OuterEdgeTests(unittest.TestCase):
+    def scene(self, edges, motion):
+        return manifest.parse([{
+            "id": "x", "group": "material", "title": "t", "inventory": "2.14", "app": "lab",
+            "backdrops": ["stripes"], "appearances": ["dark"], "steps": [{"tap": "a"}],
+            "regions": {"left": [0, 0, 10, 10], "right": [10, 0, 10, 10]}, "track": ["left", "right"], "edges": edges, "motion": motion,
+        }])[0]
+
+    @staticmethod
+    def capture(travel):
+        flat = np.zeros(len(spring_series(0.4, 1.0)["cx"]))
+        base = spring_series(0.4, 1.0)
+        series = {"xmin": base["progress"] * travel + 100, "xmax": flat + 300, "ymin": flat + 10, "ymax": flat + 50}
+        return {"events": [{"onset": 1.0, "series": {"left": {**base, **series}, "right": {**base, **series}}, "step": 0}], "touches": []}
+
+    def test_an_edge_is_compared_only_for_the_regions_that_list_it(self):
+        scene = self.scene({"left": ["xmin"], "right": ["xmax"]}, ["xmin.peak_ms", "xmax.peak_ms"])
+        self.assertEqual(shapes.expected({"pairs": {"step0e0": {}}}, scene), ["left.step0e0.xmin.peak_ms", "right.step0e0.xmax.peak_ms"])
+
+    def test_a_moving_edge_is_measured_and_a_still_one_is_absent(self):
+        scene = self.scene({"left": ["xmin"], "right": ["xmax"]}, ["xmin.settle_ms", "xmax.settle_ms"])
+        result = shapes.compare(scene, self.capture(80.0), self.capture(80.0))
+        found = shapes.measures(result)
+        self.assertEqual(found["left.step0e0.xmin.settle_ms"], 0.0)
+        self.assertNotIn("right.step0e0.xmax.settle_ms", found)
+        limits = shapes.limits(result, scene)
+        self.assertEqual(limits["right.step0e0.xmax.settle_ms"][0], float("inf"))
+        self.assertEqual(limits["left.step0e0.xmin.settle_ms"][0], 0.0)
+
+    def test_a_slower_edge_fails_its_time_limit(self):
+        scene = self.scene({"left": ["xmin"]}, ["xmin.settle_ms"])
+        slow = self.capture(80.0)
+        slow["events"][0]["series"]["left"]["xmin"] = np.interp(np.arange(len(slow["events"][0]["series"]["left"]["xmin"])) * 0.5, np.arange(len(slow["events"][0]["series"]["left"]["xmin"])), slow["events"][0]["series"]["left"]["xmin"])
+        result = shapes.compare(scene, self.capture(80.0), slow)
+        value, limit, bound = shapes.limits(result, scene)["left.step0e0.xmin.settle_ms"]
+        self.assertGreater(value, limit)
+
+    def test_edges_do_not_make_a_still_event_significant(self):
+        series = {key: np.zeros(10) for key in ("width", "height", "cx", "cy", "luma", "progress")}
+        series.update({key: np.arange(10) * 10.0 for key in ("xmin", "xmax", "ymin", "ymax")})
+        self.assertFalse(shapes.significant(series))
+
+
 class MotionMeasureNameTests(unittest.TestCase):
     def test_the_harness_and_the_manifest_agree_on_motion_measures(self):
         self.assertEqual(manifest.MOTION_MEASURES, shapes.MOTION_MEASURES)
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_track.py b/packages/mobile/tool/glass_lab/harness/tests/test_track.py
index 8fbb4f8209f228af62858af29121ae83fed76817..2c231e83e869c96eeb61609077b217b67d09bc4a 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_track.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_track.py
@@ -64,6 +64,16 @@ class BoxTests(unittest.TestCase):
         self.assertEqual(empty["width"], 0.0)
         self.assertTrue(np.isnan(empty["cx"]))
 
+    def test_shape_rows_report_each_outer_edge_in_absolute_points(self):
+        bare = stripes()
+        row = track.shape_row(draw(bare, (30, 20, 50, 20)), bare, track.edges(bare), (100, 200))
+        self.assertAlmostEqual(row["xmin"], 130, delta=1.0)
+        self.assertAlmostEqual(row["xmax"], 180, delta=1.0)
+        self.assertAlmostEqual(row["ymin"], 220, delta=1.0)
+        self.assertAlmostEqual(row["ymax"], 240, delta=1.0)
+        empty = track.shape_row(bare, bare, track.edges(bare), (100, 200))
+        self.assertTrue(all(np.isnan(empty[key]) for key in ("xmin", "xmax", "ymin", "ymax")))
+
 
 class ProgressTests(unittest.TestCase):
     def setUp(self):
@@ -102,6 +112,14 @@ class TopologyTests(unittest.TestCase):
         self.assertEqual(found["count"], 2.0)
         self.assertTrue(np.isnan(found["neck"]))
 
+    def test_a_video_topology_row_carries_the_gap_between_two_shapes(self):
+        apart = track.topology_row(disks(20), self.bare)
+        self.assertEqual(apart["count"], 2.0)
+        self.assertAlmostEqual(apart["gap"], 20.0, delta=2.0)
+        joined = track.topology_row(disks(0, bridge=20), self.bare)
+        self.assertTrue(np.isnan(joined["gap"]))
+        self.assertTrue(np.isnan(track.topology_row(self.bare.copy(), self.bare)["gap"]))
+
     def test_a_frame_with_no_glass_has_no_neck(self):
         found = track.topology_row(self.bare.copy(), self.bare)
         self.assertEqual(found["count"], 0.0)
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t19-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_manifest.py` => FAIL

Expected output ends with:

```text
FAILED (failures=1, errors=13)
```

Expected: the new tests fail on a missing key (`xmin`, `gap`, `topology.gap_rms`, `edges`) or on the manifest entries; nothing else changes.

- [ ] **Step 3: Apply the implementation.**

Patch `t19-impl` (`6569e47e2..5ed43ab6e`, 4 files):

```diff
diff --git a/packages/mobile/tool/glass_lab/harness/manifest.py b/packages/mobile/tool/glass_lab/harness/manifest.py
index f560c435da1d1096474deb9bdfdb8e783f0c8dfe..fe8b27cf9d22a84f08f1bca96a70ae25f9d02459 100644
--- a/packages/mobile/tool/glass_lab/harness/manifest.py
+++ b/packages/mobile/tool/glass_lab/harness/manifest.py
@@ -11,13 +11,15 @@ STEP_KINDS = ("wait", "tap", "doubleTap", "press", "pressDrag")
 TOUCH_STEPS = ("tap", "doubleTap", "press", "pressDrag")
 FIELDS = ("id", "group", "title", "inventory", "app", "backdrops", "appearances", "steps")
 STATIC_MEASURES = ("mad", "luminance", "rim_rms", "bbox_pt", "centre_pt")
+EDGE_KEYS = ("xmin", "xmax", "ymin", "ymax")
 MOTION_MEASURES = (
     "delay_ms",
     "topology.count",
     "topology.join_ms",
     "topology.split_ms",
     "topology.neck_rms",
-    *(f"{key}.{measure}" for key in ("width", "height", "cx", "cy", "luma") for measure in ("peak_ms", "settle_ms", "overshoot_pct", "response_pct", "damping")),
+    "topology.gap_rms",
+    *(f"{key}.{measure}" for key in ("width", "height", "cx", "cy", "luma", *EDGE_KEYS) for measure in ("peak_ms", "settle_ms", "overshoot_pct", "response_pct", "damping")),
     "progress.t10_90_ms",
     "progress.settle_ms",
     "progress.overshoot_pct",
@@ -44,6 +46,7 @@ class Scene:
     measures: tuple = STATIC_MEASURES
     motion: tuple = ()
     topology: tuple = ()
+    edges: dict = field(default_factory=dict)
 
     @property
     def native_only(self):
@@ -131,6 +134,20 @@ def validate(raw):
             errors.append(f"{where}: topology must be a region name or a non-empty list of them")
         elif topology is not None and any(name not in regions for name in names):
             errors.append(f"{where}: topology names an unknown region")
+        edges = entry.get("edges", {})
+        tracked = set(([track] if isinstance(track, str) else track or [])) | set(([topology] if isinstance(topology, str) else topology or []))
+        if not isinstance(edges, dict):
+            errors.append(f"{where}: edges must map a region to a non-empty list of edge keys")
+            edges = {}
+        for name, keys in edges.items():
+            if name not in regions:
+                errors.append(f"{where}: edges names an unknown region {name}")
+            elif name not in tracked:
+                errors.append(f"{where}: edges names a region that is not tracked {name}")
+            if not (isinstance(keys, list) and keys and all(isinstance(k, str) for k in keys)):
+                errors.append(f"{where}: edges must map a region to a non-empty list of edge keys")
+                continue
+            errors += [f"{where}: unknown edge {k}" for k in keys if k not in EDGE_KEYS]
         motion = entry.get("motion", [])
         if not isinstance(motion, list):
             errors.append(f"{where}: motion must be a list")
@@ -140,6 +157,12 @@ def validate(raw):
                 errors.append(f"{where}: motion measures need a track")
             if any(m.startswith("topology.") for m in motion) and topology is None:
                 errors.append(f"{where}: topology measures need topology regions")
+            wanted = [m for m in motion if m.split(".")[0] in EDGE_KEYS]
+            if wanted and not edges:
+                errors.append(f"{where}: edge measures need edges")
+            else:
+                listed = {k for keys in edges.values() if isinstance(keys, list) for k in keys}
+                errors += [f"{where}: {m} needs a region with the edge {m.split('.')[0]}" for m in wanted if m.split(".")[0] not in listed]
         measures = entry.get("measures", list(STATIC_MEASURES))
         if not isinstance(measures, list) or not measures:
             errors.append(f"{where}: measures must be a non-empty list")
@@ -176,6 +199,7 @@ def parse(raw):
             measures=tuple(entry.get("measures", STATIC_MEASURES)),
             motion=tuple(entry.get("motion", [])),
             topology=tracks(entry.get("topology")),
+            edges={name: tuple(keys) for name, keys in entry.get("edges", {}).items()},
         )
         for entry in raw
     ]
diff --git a/packages/mobile/tool/glass_lab/harness/shapes.py b/packages/mobile/tool/glass_lab/harness/shapes.py
index 9bf82193e5f8cad204f75d26ed7d933b5bc4a4e5..9b8ba2a7db7794065c5035b06a7797adba76a32c 100644
--- a/packages/mobile/tool/glass_lab/harness/shapes.py
+++ b/packages/mobile/tool/glass_lab/harness/shapes.py
@@ -10,16 +10,19 @@ LEAD_SECONDS = 0.2
 HOLD_SECONDS = 0.3
 MAX_LAG_MS = 150
 INNER_INSET = (16, 8)
-MIN_TRAVEL = {"width": 4.0, "height": 4.0, "cx": 4.0, "cy": 4.0, "luma": 3.0, "progress": 0.2}
-MIN_EVENT_CHANGE = {"width": 4.0, "height": 4.0, "cx": 4.0, "cy": 4.0, "luma": 1.5, "progress": 0.1}
-KEYS = (*align.KEYS, "progress")
+EDGE_KEYS = ("xmin", "xmax", "ymin", "ymax")
+MIN_TRAVEL = {"width": 4.0, "height": 4.0, "cx": 4.0, "cy": 4.0, "luma": 3.0, "progress": 0.2, **{key: 4.0 for key in EDGE_KEYS}}
+MIN_EVENT_CHANGE = {"width": 4.0, "height": 4.0, "cx": 4.0, "cy": 4.0, "luma": 1.5, "progress": 0.1, **{key: 4.0 for key in EDGE_KEYS}}
+SIGNIFICANT_KEYS = (*align.KEYS, "progress")
+KEYS = (*SIGNIFICANT_KEYS, *EDGE_KEYS)
 MOTION_MEASURES = (
     "delay_ms",
     "topology.count",
     "topology.join_ms",
     "topology.split_ms",
     "topology.neck_rms",
-    *(f"{key}.{measure}" for key in align.KEYS for measure in ("peak_ms", "settle_ms", "overshoot_pct", "response_pct", "damping")),
+    "topology.gap_rms",
+    *(f"{key}.{measure}" for key in (*align.KEYS, *EDGE_KEYS) for measure in ("peak_ms", "settle_ms", "overshoot_pct", "response_pct", "damping")),
     "progress.t10_90_ms",
     "progress.settle_ms",
     "progress.overshoot_pct",
@@ -41,6 +44,7 @@ LIMITS = {
     "join_ms": "time_ms",
     "split_ms": "time_ms",
     "neck_rms": "neck_pt",
+    "gap_rms": "gap_pt",
     "count": "count",
 }
 TRANSITION_SAMPLES = 2
@@ -155,6 +159,8 @@ def event_series(times, rows, first, last):
         series["count"] = counts[np.clip(np.searchsorted(stamps, grid, side="right") - 1, 0, len(counts) - 1)].tolist()
         necks = np.array([row["neck"] for row in picked], dtype=np.float64)
         series["neck"] = necks[np.clip(np.searchsorted(stamps, grid, side="right") - 1, 0, len(necks) - 1)].tolist()
+        gaps = np.array([row["gap"] for row in picked], dtype=np.float64)
+        series["gap"] = gaps[np.clip(np.searchsorted(stamps, grid, side="right") - 1, 0, len(gaps) - 1)].tolist()
     for key in (*KEYS, "sharpness", "residual"):
         values = np.array([row[key] for row in picked], dtype=np.float64)
         valid = np.isfinite(values)
@@ -166,7 +172,7 @@ def event_series(times, rows, first, last):
 
 
 def significant(series):
-    return any(np.isfinite(series[key]).all() and np.ptp(series[key]) >= MIN_EVENT_CHANGE[key] for key in KEYS)
+    return any(np.isfinite(series[key]).all() and np.ptp(series[key]) >= MIN_EVENT_CHANGE[key] for key in SIGNIFICANT_KEYS)
 
 
 def crossing(times, values, level):
@@ -344,17 +350,21 @@ def transition_gap(a, b):
     return 0.0 if not a and not b else float("inf")
 
 
-def neck_rms(a_count, b_count, a_neck, b_neck):
+def series_rms(a_count, b_count, a_values, b_values):
     squares = []
-    for ca, cb, na, nb in zip(a_count, b_count, a_neck, b_neck):
-        difference = neck_difference({"neck": na}, {"neck": nb})
+    for ca, cb, va, vb in zip(a_count, b_count, a_values, b_values):
+        difference = finite_difference(va, vb)
         if np.isinf(difference) and ca != cb:
             continue
-        if np.isfinite(na) or np.isfinite(nb):
+        if np.isfinite(va) or np.isfinite(vb):
             squares.append(difference ** 2)
     return float(np.sqrt(np.mean(squares))) if squares else 0.0
 
 
+def neck_rms(a_count, b_count, a_neck, b_neck):
+    return series_rms(a_count, b_count, a_neck, b_neck)
+
+
 def compare_topology(a_series, b_series):
     a_count, b_count = np.array(a_series["count"]), np.array(b_series["count"])
     entry = {}
@@ -368,6 +378,8 @@ def compare_topology(a_series, b_series):
         excluded[max(0, index - TRANSITION_SAMPLES) : index + TRANSITION_SAMPLES + 1] = True
     entry["count"] = float(((a_count[:count] != b_count[:count]) & ~excluded).sum())
     entry["neck_rms"] = neck_rms(a_count[:count], b_count[:count], a_series["neck"][:count], b_series["neck"][:count])
+    if "gap" in a_series and "gap" in b_series:
+        entry["gap_rms"] = series_rms(a_count[:count], b_count[:count], a_series["gap"][:count], b_series["gap"][:count])
     entry["native"] = {"joins_ms": [i * 1000 / align.GRID_HZ for i in a_joins], "splits_ms": [i * 1000 / align.GRID_HZ for i in a_splits]}
     entry["flutter"] = {"joins_ms": [i * 1000 / align.GRID_HZ for i in b_joins], "splits_ms": [i * 1000 / align.GRID_HZ for i in b_splits]}
     return entry
@@ -394,7 +406,7 @@ def compare(scene, native, flutter):
             shape = {}
             if name in scene.topology:
                 shape["topology"] = compare_topology(sa, sb)
-            for key in align.KEYS:
+            for key in (*align.KEYS, *scene.edges.get(name, ())):
                 entry = compare_key(key, sa[key], sb[key])
                 if entry:
                     shape[key] = entry
@@ -430,7 +442,12 @@ def expected(result, scene):
             if measure == "delay_ms":
                 names.append(f"{label}.delay_ms")
                 continue
-            owners = scene.topology if measure.startswith("topology.") else scene.track
+            if measure.startswith("topology."):
+                owners = scene.topology
+            elif measure.split(".")[0] in EDGE_KEYS:
+                owners = [name for name, keys in scene.edges.items() if measure.split(".")[0] in keys]
+            else:
+                owners = scene.track
             names += [f"{name}.{label}.{measure}" for name in owners]
     return names
 
diff --git a/packages/mobile/tool/glass_lab/harness/track.py b/packages/mobile/tool/glass_lab/harness/track.py
index a1e77665634ceacbbb7bc2e029d0348efa1aaa4e..d1a8bbd246ef4b561a000c97a83fedc9046c8685 100644
--- a/packages/mobile/tool/glass_lab/harness/track.py
+++ b/packages/mobile/tool/glass_lab/harness/track.py
@@ -88,10 +88,22 @@ def shape_row(frame, bare, edge_map, origin, scale=metrics.SCALE):
     found = box_pixels(frame, bare, edge_map)
     luma = float(metrics.luma(frame).mean())
     if found is None:
-        return {"width": 0.0, "height": 0.0, "cx": float("nan"), "cy": float("nan"), "luma": luma, "band": 0.0}
+        nan = float("nan")
+        return {"width": 0.0, "height": 0.0, "cx": nan, "cy": nan, "xmin": nan, "xmax": nan, "ymin": nan, "ymax": nan, "luma": luma, "band": 0.0}
     left, top, right, bottom = found
     x, y, w, h = left / scale, top / scale, (right - left + 1) / scale, (bottom - top + 1) / scale
-    return {"width": float(w), "height": float(h), "cx": float(origin[0] + x + w / 2), "cy": float(origin[1] + y + h / 2), "luma": luma, "band": float(in_band(edge_map, found))}
+    return {
+        "width": float(w),
+        "height": float(h),
+        "cx": float(origin[0] + x + w / 2),
+        "cy": float(origin[1] + y + h / 2),
+        "xmin": float(origin[0] + x),
+        "xmax": float(origin[0] + x + w),
+        "ymin": float(origin[1] + y),
+        "ymax": float(origin[1] + y + h),
+        "luma": luma,
+        "band": float(in_band(edge_map, found)),
+    }
 
 
 def laplacian(image):
@@ -327,4 +339,5 @@ def gap(mask, scale=metrics.SCALE):
 
 
 def topology_row(frame, bare):
-    return topology(topology_mask(frame, bare))
+    mask = topology_mask(frame, bare)
+    return dict(topology(mask), gap=gap(mask))
diff --git a/packages/mobile/tool/glass_lab/scenes.json b/packages/mobile/tool/glass_lab/scenes.json
index 30d9f382679602aa22eb555f6983ee5a38312acc..7dc2f6665be9c900bab319200f905a0164ab0d92 100644
--- a/packages/mobile/tool/glass_lab/scenes.json
+++ b/packages/mobile/tool/glass_lab/scenes.json
@@ -660,21 +660,35 @@
       "pair"
     ],
     "motion": [
-      "width.peak_ms",
-      "width.settle_ms",
-      "width.overshoot_pct",
-      "width.response_pct",
-      "width.damping",
       "cx.peak_ms",
       "cx.settle_ms",
       "cx.overshoot_pct",
       "cx.response_pct",
       "cx.damping",
+      "xmin.peak_ms",
+      "xmin.settle_ms",
+      "xmin.overshoot_pct",
+      "xmin.response_pct",
+      "xmin.damping",
+      "xmax.peak_ms",
+      "xmax.settle_ms",
+      "xmax.overshoot_pct",
+      "xmax.response_pct",
+      "xmax.damping",
       "topology.count",
       "topology.join_ms",
       "topology.split_ms",
-      "topology.neck_rms"
-    ]
+      "topology.neck_rms",
+      "topology.gap_rms"
+    ],
+    "edges": {
+      "left": [
+        "xmin"
+      ],
+      "right": [
+        "xmax"
+      ]
+    }
   },
   {
     "id": "material.union",
@@ -806,11 +820,28 @@
       "width.overshoot_pct",
       "width.response_pct",
       "width.damping",
+      "ymin.peak_ms",
+      "ymin.settle_ms",
+      "ymin.overshoot_pct",
+      "ymin.response_pct",
+      "ymin.damping",
+      "ymax.peak_ms",
+      "ymax.settle_ms",
+      "ymax.overshoot_pct",
+      "ymax.response_pct",
+      "ymax.damping",
       "topology.count",
       "topology.join_ms",
       "topology.split_ms",
-      "topology.neck_rms"
-    ]
+      "topology.neck_rms",
+      "topology.gap_rms"
+    ],
+    "edges": {
+      "stack": [
+        "ymin",
+        "ymax"
+      ]
+    }
   },
   {
     "id": "material.morph.plain",
@@ -902,11 +933,28 @@
       "width.overshoot_pct",
       "width.response_pct",
       "width.damping",
+      "ymin.peak_ms",
+      "ymin.settle_ms",
+      "ymin.overshoot_pct",
+      "ymin.response_pct",
+      "ymin.damping",
+      "ymax.peak_ms",
+      "ymax.settle_ms",
+      "ymax.overshoot_pct",
+      "ymax.response_pct",
+      "ymax.damping",
       "topology.count",
       "topology.join_ms",
       "topology.split_ms",
-      "topology.neck_rms"
-    ]
+      "topology.neck_rms",
+      "topology.gap_rms"
+    ],
+    "edges": {
+      "stack": [
+        "ymin",
+        "ymax"
+      ]
+    }
   },
   {
     "id": "material.tap",
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t19-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_manifest.py` => PASS

Expected output ends with:

```text
Ran 84 tests in <time>
OK
```

- [ ] **Step 5: Gate: harness.**

RUN[t19-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

Expected output ends with:

```text
Ran 251 tests in <time>
OK
```

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): merge is judged by each circle's outer edge and the pair's gap, morph by the stack's outer edges (D3, user-approved manifest correction)

Co-Authored-By: <the session's attribution line>"
```

### Task 20: A container draws with the material row of its members' size (the median member), unless it is given a side (D1)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart` (`side` is nullable; a `GlassMaterialSource`), `lib/src/api/glass_effect.dart`, `lib/src/motion/glass_motion_coordinator.dart` (`followMaterial`, `_followSides`, `sharedMaterial`)
- Test: `test/glass_container_material_test.dart` (new), `test/motion/glass_member_test.dart`

**Why.** Ruling 30 (D1, a main-session ruling). Native draws each glass with its own size's material (64 pt union glass is 9-12 luma lighter than 80 pt glass in dark); the container resolved one row for a fixed `side` of 88. The container's layer now follows a material source whose side is the median of its members' laid-out shorter sides (the upper median for an even count), so a container of equal members, as in the union scene, draws with the row of that size; an explicit `side` pins it as before. **A limit, stated:** one layer has one material, so a container of members of different sizes draws all of them with the median member's row; a row per member inside one layer needs per-shape material parameters in the final-render shader and is not built. This changes the material of every container whose members are not 88 pt: Task 27 Step 9's still check against 2A is the risk check.

- [ ] **Step 1: Add the failing tests.**

Patch `t20-tests` (`5ed43ab6e..4d42f3642`, 2 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/test/glass_container_material_test.dart b/packages/mobile/packages/ios_liquid_glass/test/glass_container_material_test.dart
new file mode 100644
index 0000000000000000000000000000000000000000..62e093fd090240c127d81fd63239118109f0ba8b
--- /dev/null
+++ b/packages/mobile/packages/ios_liquid_glass/test/glass_container_material_test.dart
@@ -0,0 +1,82 @@
+import 'package:flutter/material.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+import 'package:ios_liquid_glass/src/shaders.dart';
+
+LiquidGlassSettings _drawn(LiquidGlassLayer layer) => layer.settingsSource?.settings ?? layer.settings;
+
+LiquidGlassSettings _row(double side, {Brightness brightness = Brightness.dark, Glass glass = Glass.regular}) =>
+    GlassMaterial.resolve(glass: glass, shorterSide: side, brightness: brightness).toSettings(tint: glass.tintColor);
+
+Widget _host(Widget child, {Brightness brightness = Brightness.dark}) => MaterialApp(
+  home: GlassTheme(data: GlassThemeData(brightness: brightness), child: Align(alignment: Alignment.topLeft, child: child)),
+);
+
+Widget _glasses(List<double> sides) => Row(
+  mainAxisSize: MainAxisSize.min,
+  children: [for (final side in sides) GlassEffect(child: SizedBox.square(dimension: side))],
+);
+
+LiquidGlassLayer _containerLayer(WidgetTester tester) => tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).first;
+
+void main() {
+  isLocalTest = true;
+
+  testWidgets('a container takes the material row of its members size, in its first frame', (tester) async {
+    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([64, 64]))));
+    expect(_drawn(_containerLayer(tester)), _row(64));
+    expect(_drawn(_containerLayer(tester)), isNot(_row(88)));
+  });
+
+  testWidgets('a container with an explicit side keeps that row whatever its members measure', (tester) async {
+    await tester.pumpWidget(_host(GlassEffectContainer(side: 88, child: _glasses([64, 64]))));
+    await tester.pump();
+    expect(_drawn(_containerLayer(tester)), _row(88));
+  });
+
+  testWidgets('a container of mixed sizes uses the row of its median member', (tester) async {
+    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([44, 88, 200]))));
+    await tester.pump();
+    expect(_drawn(_containerLayer(tester)), _row(88));
+    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([44, 44, 200]))));
+    await tester.pump();
+    expect(_drawn(_containerLayer(tester)), _row(44));
+  });
+
+  testWidgets('the row follows members that resize, join and leave', (tester) async {
+    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([44, 44]))));
+    await tester.pump();
+    expect(_drawn(_containerLayer(tester)), _row(44));
+    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([80, 80]))));
+    await tester.pump();
+    expect(_drawn(_containerLayer(tester)), _row(80));
+    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([80, 80, 200, 200, 200]))));
+    await tester.pumpAndSettle();
+    expect(_drawn(_containerLayer(tester)), _row(200));
+    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([80]))));
+    await tester.pumpAndSettle();
+    expect(_drawn(_containerLayer(tester)), _row(80));
+  });
+
+  testWidgets('the row re-resolves when the appearance flips, at the same size', (tester) async {
+    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([64, 64]))));
+    await tester.pump();
+    await tester.pumpWidget(_host(GlassEffectContainer(child: _glasses([64, 64])), brightness: Brightness.light));
+    await tester.pump();
+    expect(_drawn(_containerLayer(tester)), _row(64, brightness: Brightness.light));
+  });
+
+  testWidgets('a union of 64 pt members draws with the row of 64 pt glass, not of 88', (tester) async {
+    final namespace = GlassNamespace();
+    await tester.pumpWidget(_host(GlassEffectContainer(
+      child: Row(
+        mainAxisSize: MainAxisSize.min,
+        children: [
+          for (final key in ['a', 'b']) GlassEffect(key: ValueKey(key), union: GlassEffectUnion('u', namespace), child: const SizedBox.square(dimension: 64)),
+        ],
+      ),
+    )));
+    await tester.pump();
+    expect(_drawn(_containerLayer(tester)), _row(64));
+  });
+}
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_member_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_member_test.dart
index 5d43d13c1b5c6862d449baff19120cd7f042db88..ca40b6fafcfd2f6254460e96fce83d6378e18d07 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_member_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_member_test.dart
@@ -3,6 +3,7 @@ import 'dart:math' as math;
 import 'package:flutter/rendering.dart';
 import 'package:flutter_test/flutter_test.dart';
 import 'package:ios_liquid_glass/ios_liquid_glass.dart';
+import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
 import 'package:ios_liquid_glass/src/motion/glass_materialize.dart';
 import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
 import 'package:ios_liquid_glass/src/motion/ios27_motion.dart';
@@ -100,7 +101,7 @@ void main() {
     final member = coordinator.join()
       ..attachBox(space.box)
       ..shape = const LiquidRoundedRectangle(borderRadius: 20)
-      ..sharedSettings = const LiquidGlassSettings();
+      ..sharedMaterial = GlassMaterialSource(resolve: (_) => const GlassMaterial({}), side: 88);
     member.sized(space.box.size);
     expect(member.drawn, const Rect.fromLTWH(0, 0, 100, 40));
     expect(coordinator.leave(member, animate: true), isTrue);
@@ -128,7 +129,7 @@ void main() {
     final member = coordinator.join()
       ..attachBox(space.box)
       ..shape = const LiquidRoundedRectangle(borderRadius: 20)
-      ..sharedSettings = const LiquidGlassSettings();
+      ..sharedMaterial = GlassMaterialSource(resolve: (_) => const GlassMaterial({}), side: 88);
     member.sized(space.box.size);
     expect(member.drawn, const Rect.fromLTWH(150, 180, 100, 40));
     space.tripwire.armed = true;
@@ -148,7 +149,7 @@ void main() {
     final member = coordinator.join()
       ..attachBox(space.box)
       ..shape = const LiquidRoundedRectangle(borderRadius: 20)
-      ..sharedSettings = const LiquidGlassSettings();
+      ..sharedMaterial = GlassMaterialSource(resolve: (_) => const GlassMaterial({}), side: 88);
     member.sized(space.box.size);
     member.drawn;
     expect(coordinator.leave(member, animate: true), isTrue);
@@ -168,7 +169,7 @@ void main() {
     final member = coordinator.join()
       ..attachBox(space.box)
       ..shape = const LiquidRoundedRectangle(borderRadius: 20)
-      ..sharedSettings = const LiquidGlassSettings();
+      ..sharedMaterial = GlassMaterialSource(resolve: (_) => const GlassMaterial({}), side: 88);
     member.sized(space.box.size);
     expect(coordinator.leave(member, animate: false), isFalse);
     expect(coordinator.takeGhosts(), isEmpty);
@@ -209,7 +210,7 @@ void main() {
     final member = coordinator.join(inserted: true)
       ..attachBox(space.box)
       ..shape = const LiquidRoundedRectangle(borderRadius: 20)
-      ..sharedSettings = const LiquidGlassSettings();
+      ..sharedMaterial = GlassMaterialSource(resolve: (_) => const GlassMaterial({}), side: 88);
     member.sized(space.box.size);
     expect(member.drawn, const Rect.fromLTWH(0, 0, 100, 40));
     await tester.pump();
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t20-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/glass_container_material_test.dart` => FAIL

Expected output ends with:

```text
+1 -5: Some tests failed.
```

Expected: five of the six tests fail on `Expected: LiquidGlassSettings` (the row of 88 is drawn); `a container with an explicit side keeps that row` passes before and after, by design.

- [ ] **Step 3: Apply the implementation.**

Patch `t20-impl` (`5ed43ab6e..4d42f3642`, 3 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
index d4e1b2a7add8903bc3408e22b543de4bb337a20f..30a114b4b89465bde8924f6224b6a6540233e58a 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect.dart
@@ -234,7 +234,7 @@ class _GlassEffectState extends State<GlassEffect> with SingleTickerProviderStat
         member
           ..shape = shape
           ..material = material
-          ..sharedSettings = grouped ? container.settings : null
+          ..sharedMaterial = grouped ? container.material : null
           ..reduceMotion = GlassAccessibility.of(context).reduceMotion
           ..dark = GlassTheme.brightnessOf(context) == Brightness.dark
           ..unite(widget.union, glass: widget.glass, grouped: grouped && !member.ownsLayer);
@@ -243,8 +243,8 @@ class _GlassEffectState extends State<GlassEffect> with SingleTickerProviderStat
           glass = LiquidGlass.grouped(shape: shape, shadows: material.shadows, shadowSource: material, motion: member, child: content);
         } else {
           glass = LiquidGlass.withOwnLayer(
-            settings: grouped ? container.settings : material.settings,
-            settingsSource: grouped ? null : material,
+            settings: grouped ? container.material.settings : material.settings,
+            settingsSource: grouped ? container.material : material,
             shape: shape,
             shadows: material.shadows,
             shadowSource: material,
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart
index 17d6a1d87a9074133ed8fb475ee50ee79ebf2c87..85eebd5a0bc84e9ef4075de28a588ea6438ae9a1 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/api/glass_effect_container.dart
@@ -1,21 +1,22 @@
 import 'package:flutter/widgets.dart';
 import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
 import 'package:ios_liquid_glass/src/api/glass.dart';
+import 'package:ios_liquid_glass/src/api/glass_effect.dart';
 import 'package:ios_liquid_glass/src/api/glass_material_context.dart';
 import 'package:ios_liquid_glass/src/liquid_glass_blend_group.dart';
-import 'package:ios_liquid_glass/src/liquid_glass_settings.dart';
 import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
+import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
 import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
 import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
 import 'package:ios_liquid_glass/src/rendering/liquid_glass_layer.dart';
 import 'package:meta/meta.dart';
 
 class GlassEffectContainer extends StatefulWidget {
-  const GlassEffectContainer({super.key, this.spacing = 8, this.glass = Glass.regular, this.side = 88, required this.child});
+  const GlassEffectContainer({super.key, this.spacing = 8, this.glass = Glass.regular, this.side, required this.child});
 
   final double spacing;
   final Glass glass;
-  final double side;
+  final double? side;
   final Widget child;
 
   static Glass? glassOf(BuildContext context) => scopeOf(context)?.glass;
@@ -29,6 +30,7 @@ class GlassEffectContainer extends StatefulWidget {
 
 class _GlassEffectContainerState extends State<GlassEffectContainer> with SingleTickerProviderStateMixin {
   late final GlassMotionCoordinator _coordinator = GlassMotionCoordinator(vsync: this);
+  GlassMaterialSource? _material;
   GlassOverlayGhosts? _overlay;
 
   @override
@@ -55,6 +57,7 @@ class _GlassEffectContainerState extends State<GlassEffectContainer> with Single
   @override
   void dispose() {
     _coordinator.dispose();
+    _material?.dispose();
     _overlay?.release();
     _overlay = null;
     super.dispose();
@@ -66,18 +69,24 @@ class _GlassEffectContainerState extends State<GlassEffectContainer> with Single
     return ListenableBuilder(
       listenable: GlassAccessibility.platform,
       builder: (context, _) {
-        final material = resolveGlassMaterial(context, glass: widget.glass, shorterSide: widget.side);
-        final settings = material.toSettings(tint: widget.glass.tintColor);
+        final resolve = glassMaterialResolver(context, glass: widget.glass);
+        final tint = widget.glass.tintColor;
+        final fixed = widget.side;
+        final material = _material ??= GlassMaterialSource(resolve: resolve, tint: tint, side: fixed ?? GlassEffect.fallbackSide);
+        material.configure(resolve: resolve, tint: tint);
+        if (fixed != null) material.resize(fixed, exact: true);
+        _coordinator.followMaterial = fixed == null ? material : null;
         return GlassCoordinatorSpace(
           coordinator: _coordinator,
           child: LiquidGlassLayer(
-            settings: settings,
+            settings: material.settings,
+            settingsSource: material,
             child: LiquidGlassBlendGroup(
               blend: widget.spacing,
               blendMotion: _coordinator.spacing,
               child: GlassContainerScope(
                 glass: widget.glass,
-                settings: settings,
+                material: material,
                 coordinator: _coordinator,
                 child: Stack(
                   alignment: Alignment.topLeft,
@@ -96,13 +105,13 @@ class _GlassEffectContainerState extends State<GlassEffectContainer> with Single
 
 @internal
 class GlassContainerScope extends InheritedWidget {
-  const GlassContainerScope({super.key, required this.glass, required this.settings, required this.coordinator, required super.child});
+  const GlassContainerScope({super.key, required this.glass, required this.material, required this.coordinator, required super.child});
 
   final Glass glass;
-  final LiquidGlassSettings settings;
+  final GlassMaterialSource material;
   final GlassMotionCoordinator coordinator;
 
   @override
   bool updateShouldNotify(GlassContainerScope oldWidget) =>
-      oldWidget.glass != glass || oldWidget.settings != settings || oldWidget.coordinator != coordinator;
+      oldWidget.glass != glass || oldWidget.material != material || oldWidget.coordinator != coordinator;
 }
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
index a579a79a15efbbd0abeb854a31a139db0cac61ae..e650ed01356e16c06825a58e419a3e40daa717e2 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
@@ -58,7 +58,7 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
   GlassAnimation? scopeAnimation;
   bool animatesTransitions = true;
   LiquidShape? shape;
-  LiquidGlassSettings? sharedSettings;
+  GlassMaterialSource? sharedMaterial;
   GlassMaterialSource? material;
   List<ScrollableState> scrollables = const [];
   VoidCallback? onSettled;
@@ -81,7 +81,7 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
   GlassMotionCoordinator? _ghostOwner;
   (GlassEffectUnion, LiquidShape, Glass?)? _union;
 
-  LiquidGlassSettings? get settings => sharedSettings ?? material?.settings;
+  LiquidGlassSettings? get settings => sharedMaterial?.settings ?? material?.settings;
 
   bool get isMoving => _presence.isMoving || _morph.isMoving || _offset.any((spring) => spring.isMoving);
 
@@ -232,6 +232,7 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
   void sized(Size size) {
     final previous = _size;
     _size = size;
+    coordinator._followSides();
     if (previous != null && previous != size) {
       final animation = _changed();
       if (animation != null) {
@@ -623,6 +624,24 @@ class GlassMotionCoordinator {
   bool _ghostsChanged = false;
   final _Notifier _ghostMotion = _Notifier();
 
+  GlassMaterialSource? _followMaterial;
+
+  set followMaterial(GlassMaterialSource? value) {
+    if (identical(_followMaterial, value)) return;
+    _followMaterial = value;
+    _followSides();
+  }
+
+  void _followSides() {
+    final source = _followMaterial;
+    if (source == null) return;
+    final sides = [
+      for (final member in _members)
+        if (member._size != null && member.presence != GlassPresence.disappearing) member._size!.shortestSide,
+    ]..sort();
+    if (sides.isNotEmpty) source.resize(sides[sides.length ~/ 2]);
+  }
+
   Listenable get ghostMotion => _ghostMotion;
 
   Iterable<GlassMember> get members => _members;
@@ -847,6 +866,7 @@ class GlassMotionCoordinator {
     _blurred.remove(member);
     _links.remove(member);
     _unionChanged(member._union);
+    _followSides();
     final ghostOwner = owner ?? this;
     final animation = resolveGlassAnimation(member.scopeAnimation);
     final settings = member.settings, shape = member.shape;
@@ -895,6 +915,7 @@ class GlassMotionCoordinator {
     if (member._ghostOwner != null) return;
     _members.add(member);
     _unionChanged(member._union);
+    _followSides();
   }
 
   void _adopt(GlassMember member, _Leaving leaving) {
@@ -915,6 +936,7 @@ class GlassMotionCoordinator {
     leaving?.release();
     if (_members.remove(member) || leaving != null) {
       _unionChanged(member._union);
+      _followSides();
       member.dispose();
     }
   }
@@ -926,6 +948,7 @@ class GlassMotionCoordinator {
     member._ghostOwner = null;
     _members.add(member);
     _unionChanged(member._union);
+    _followSides();
   }
 
   List<GlassGhost> takeGhosts() {
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t20-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/glass_container_material_test.dart` => PASS

Expected output ends with:

```text
+6: All tests passed!
```

- [ ] **Step 5: Gate: package.**

RUN[t20-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t20-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

Expected output ends with:

```text
+221: All tests passed!
```

- [ ] **Step 6: Gate: example.**

RUN[t20-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t20-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

Expected output ends with:

```text
+23: All tests passed!
```

The app gate is not run here (see Task 18); it runs at Task 24b.

- [ ] **Step 7: Commit.**

```bash
git add -A packages
git commit -m "feat(ios_liquid_glass): a container draws with the material row of its members' size (the median member), unless it is given a side (D1)

Co-Authored-By: <the session's attribution line>"
```

### Task 21: The union scene's glyph sizes are a constant of the scene

**Files:**
- Modify: `packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart`
- Test: `example/test/union_scene_test.dart`

**Why.** Ruling 31 (D2). A refactor (all four sizes 24, as before) so that Task 22's test fails on an assertion.

- [ ] **Step 1: Apply the implementation.**

Patch `t21-impl` (`4d42f3642..8d61ee26c`, 2 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
index 03368c630d1d7d9dffd2c934d3a6a25c0266b44f..39d9facef979cd9976f729423d49798741f50407 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
@@ -199,6 +199,7 @@ class UnionScene extends StatefulWidget {
   const UnionScene({super.key, required this.backdrop});
 
   static const List<IconData> symbols = [Icons.star, Icons.favorite, Icons.bolt, Icons.eco];
+  static const List<double> glyphSizes = [24, 24, 24, 24];
 
   final String backdrop;
 
@@ -222,7 +223,7 @@ class _UnionSceneState extends State<UnionScene> {
                 if (index > 0) const SizedBox(width: 16),
                 GlassEffect(
                   union: GlassEffectUnion(index < 2 ? 'first' : 'second', _namespace),
-                  child: SizedBox.square(dimension: 64, child: GlassForeground(child: Icon(icon, size: 24))),
+                  child: SizedBox.square(dimension: 64, child: GlassForeground(child: Icon(icon, size: UnionScene.glyphSizes[index]))),
                 ),
               ],
             ],
diff --git a/packages/mobile/packages/ios_liquid_glass/example/test/union_scene_test.dart b/packages/mobile/packages/ios_liquid_glass/example/test/union_scene_test.dart
index e5360106810da1db97a7d917e40687b3b08d40a7..76c9aa18969f1b592263a2fc8e52dbe1016b1775 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/test/union_scene_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/test/union_scene_test.dart
@@ -6,6 +6,7 @@ import 'package:flutter_test/flutter_test.dart';
 import 'package:ios_liquid_glass/ios_liquid_glass.dart';
 import 'package:ios_liquid_glass_example/lab/glass_lab_launch.dart';
 import 'package:ios_liquid_glass_example/lab/glass_lab_screen.dart';
+import 'package:ios_liquid_glass_example/lab/scenes/material_scenes.dart';
 
 const Size _screen = Size(402, 874);
 
@@ -39,7 +40,7 @@ void main() {
     expect(glasses.map((glass) => glass.glass).toSet(), {Glass.regular});
     final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
     expect([for (final icon in icons) icon.icon], [Icons.star, Icons.favorite, Icons.bolt, Icons.eco]);
-    expect(icons.map((icon) => icon.size).toSet(), {24});
+    expect([for (final icon in icons) icon.size], UnionScene.glyphSizes);
     for (final (index, icon) in icons.indexed) {
       expect(tester.getCenter(find.byWidget(icon)), rects[index].center);
       expect(find.ancestor(of: find.byWidget(icon), matching: find.byType(GlassForeground)), findsOneWidget);
```

- [ ] **Step 2: Gate: example.**

RUN[t21-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t21-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

Expected output ends with:

```text
+23: All tests passed!
```

- [ ] **Step 3: Commit.**

```bash
git add -A packages
git commit -m "refactor(example): the union scene's glyph sizes are a constant of the scene

Co-Authored-By: <the session's attribution line>"
```

### Task 22: The union scene's glyphs are sized to native's ink height (D2)

**Files:**
- Modify: `packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart` (`UnionScene.glyphSizes`)
- Test: `example/test/union_scene_test.dart`
- Evidence: `R/union/glyph-ink.txt`, `R/union/ink_flutter.py`

**Why.** Ruling 31 (D2, a main-session ruling: match native's glyph ink in the example's union scene; never shrink the measured regions). Native's SF Symbols at size 24 are taller than Material Icons at 24; each size is 24 x native ink height / Flutter ink height at 24, rounded to 0.5 (star 33, heart 28, bolt 34.5, leaf 32.5), and the test derives them from the saved ink measurements. This is a change of the test content (the example), not of the package. Measured in the app (`R/union/glyph-ink.txt`, run `20261007-120641`): heights within 0.33 pt of native, star and heart widths within 1.0 pt; bolt and leaf stay 2.3 and 4.0 pt narrower because `Icons.bolt` and `Icons.eco` are other shapes than `bolt.fill` and `leaf.fill` (class (b), content).

- [ ] **Step 1: Add the failing tests.**

Patch `t22-tests` (`8d61ee26c..d4243f87f`, 1 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/example/test/union_scene_test.dart b/packages/mobile/packages/ios_liquid_glass/example/test/union_scene_test.dart
index 76c9aa18969f1b592263a2fc8e52dbe1016b1775..08b999454f3606af65e0756f6725b6dfd078ca68 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/test/union_scene_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/test/union_scene_test.dart
@@ -51,6 +51,15 @@ void main() {
     expect(tester.widget<GlassEffect>(find.byType(GlassEffect).first).union!.namespace, same(namespace));
   });
 
+  test('each glyph is sized so its ink is as tall as native\'s SF Symbol at size 24, from the ink measured at size 24 in both apps', () {
+    final ink = (jsonDecode(File('../../../../../docs/liquid_glass/02b-motion/research/proto-2b2/verify/union-tone-light-stripes.json').readAsStringSync()) as Map<String, dynamic>)['glyph_ink'] as Map<String, dynamic>;
+    final sizes = [
+      for (final name in ['star', 'heart', 'bolt', 'leaf'])
+        (24 * (ink[name]['native']['h_pt'] as num) / (ink[name]['flutter']['h_pt'] as num) * 2).round() / 2,
+    ];
+    expect(UnionScene.glyphSizes, sizes);
+  });
+
   test('the union manifest pins each union and the pair padded by 12 pt, and judges their topology on its stills', () {
     final entry = _entry();
     expect(_region(entry, 'first'), const Rect.fromLTRB(49, 419, 193, 483).inflate(12));
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t22-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/union_scene_test.dart` => FAIL

Expected output ends with:

```text
+2 -1: Some tests failed.
```

Expected: `each glyph is sized so its ink is as tall as native's...` fails (`Expected: [33.0, 28.0, 34.5, 32.5] Actual: [24.0, 24.0, 24.0, 24.0]`); the other two pass.

- [ ] **Step 3: Apply the implementation.**

Patch `t22-impl` (`8d61ee26c..d4243f87f`, 1 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
index 39d9facef979cd9976f729423d49798741f50407..14694aec8e73100179b72a66118034232d835acd 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart
@@ -199,7 +199,7 @@ class UnionScene extends StatefulWidget {
   const UnionScene({super.key, required this.backdrop});
 
   static const List<IconData> symbols = [Icons.star, Icons.favorite, Icons.bolt, Icons.eco];
-  static const List<double> glyphSizes = [24, 24, 24, 24];
+  static const List<double> glyphSizes = [33, 28, 34.5, 32.5];
 
   final String backdrop;
 
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t22-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/union_scene_test.dart` => PASS

Expected output ends with:

```text
+3: All tests passed!
```

- [ ] **Step 5: Gate: example.**

RUN[t22-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t22-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

Expected output ends with:

```text
+24: All tests passed!
```

- [ ] **Step 6: Commit.**

```bash
git add -A packages
git commit -m "feat(example): the union scene's glyphs are sized to native's ink height (D2)

Co-Authored-By: <the session's attribution line>"
```

### Task 23: `material.respace`: a native and a Flutter scene whose container spacing animates, judged on the pair's topology

**Files:**
- Modify: `tool/glass_lab/native/GlassLab/MaterialScenes.swift` (`RespaceScene`), `tool/glass_lab/scenes.json` (`material.respace`), `tool/glass_lab/harness/shapes.py` (`significant`)
- Modify (example): `lib/lab/scenes/spacing_scenes.dart` (`RespaceScene`)
- Test: `tool/glass_lab/harness/tests/{test_shapes,test_manifest}.py`, example `test/spacing_scenes_test.dart`

**Why.** Ruling 12 (a user decision of 2026-10-07: keep the spacing animation, with a native reference). **No native evidence for the animation exists yet:** nothing recorded in 2B.1 or the prototype changes a container's `spacing` while it is on screen, so ruling 12 is the package's own design until Task 26 records and judges this scene. The scene is two 80 pt circles 12 pt apart (a gap that is apart at spacing 8, whose reach is 4 pt, and joined at spacing 40, whose reach is 20 pt) in a native `GlassEffectContainer(spacing:)` that `withAnimation` changes between 8 and 40 on the buttons `widen` and `narrow`; the Flutter scene does the same under `withGlassAnimation`. The circles never move, so the whole judgement is the pair's topology (count, join and split times, neck and gap over time). A topology change alone now makes an event significant (a scene whose only change is a neck forming has no shape that moves). The id is `material.respace`, not `material.spacing.*`, so the N7 selector and the 23-scene counts do not change.

- [ ] **Step 1: Add the failing tests.**

Patch `t23-tests` (`d4243f87f..7f868ffe1`, 3 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/example/test/spacing_scenes_test.dart b/packages/mobile/packages/ios_liquid_glass/example/test/spacing_scenes_test.dart
index e7f6a19459799bfb5bdfaa44614915c89556f5bc..176e2e7555f75bd7ce0f3ebf67597baeebf56b41 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/test/spacing_scenes_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/test/spacing_scenes_test.dart
@@ -108,4 +108,28 @@ void main() {
     expect(_glass(tester), [const Rect.fromLTWH(81, top, 80, 80), const Rect.fromLTWH(241, top, 80, 80)]);
     semantics.dispose();
   });
+
+  testWidgets('material.respace is two 80 pt circles 12 pt apart in a container whose spacing is 8, 40 after Widen and 8 after Narrow, the circles never moving', (tester) async {
+    _iPhone17Pro(tester);
+    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.respace'))));
+    await tester.pump(const Duration(seconds: 1));
+    final rects = _glass(tester);
+    expect(rects, hasLength(2));
+    expect(rects.map((rect) => rect.size).toSet(), {const Size(80, 80)});
+    expect(rects[1].left - rects[0].right, 12);
+    expect(rects[0].center.dy, 451);
+    double spacing() => tester.widget<GlassEffectContainer>(find.byType(GlassEffectContainer)).spacing;
+    expect(spacing(), 8);
+    await tester.tap(find.bySemanticsIdentifier('widen'));
+    await tester.pump();
+    expect(spacing(), 40);
+    await tester.pump(const Duration(milliseconds: 100));
+    expect(_glass(tester), rects);
+    await tester.pumpAndSettle();
+    expect(_glass(tester), rects);
+    await tester.tap(find.bySemanticsIdentifier('narrow'));
+    await tester.pumpAndSettle();
+    expect(spacing(), 8);
+    expect(_glass(tester), rects);
+  });
 }
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py b/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py
index f93799e23a9adc0c6712139f476c4ec9bb66075e..acc15032f05472f493d104c087b737adb3878c25 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_manifest.py
@@ -106,6 +106,18 @@ class RealMotionManifestTests(unittest.TestCase):
                 self.assertIn(name, entry["motion"])
 
 
+class RespaceManifestTests(unittest.TestCase):
+    def test_the_respace_scene_judges_the_pair_of_a_container_whose_spacing_animates(self):
+        entry = next(entry for entry in json.loads(manifest.MANIFEST.read_text()) if entry["id"] == "material.respace")
+        self.assertEqual(entry["steps"], [{"wait": 0.5}, {"tap": "widen"}, {"wait": 1.5}, {"tap": "narrow"}, {"wait": 1.5}])
+        self.assertEqual(entry["topology"], ["pair"])
+        self.assertEqual(entry["backdrops"], ["photo"])
+        self.assertEqual(entry["appearances"], ["light", "dark"])
+        self.assertEqual(entry["motion"], ["topology.count", "topology.join_ms", "topology.split_ms", "topology.neck_rms", "topology.gap_rms"])
+        self.assertFalse(entry["id"].startswith("material.spacing."))
+        self.assertEqual([scene.id for scene in manifest.select(manifest.load(), "material.spacing")], [scene.id for scene in manifest.load() if scene.id.startswith("material.spacing.")])
+
+
 class TrackTests(unittest.TestCase):
     def base(self, **changes):
         entry = {"id": "x", "group": "material", "title": "t", "inventory": "2.13", "app": "lab", "backdrops": ["stripes"], "appearances": ["dark"], "steps": [], "regions": {"a": [0, 0, 1, 1], "b": [1, 1, 1, 1]}}
diff --git a/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py b/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py
index 532ba27b73b64fe8704e176c8ad174f92967c59e..65e304f0e16f41ea767c4d06f7b2d220e07660b5 100644
--- a/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py
+++ b/packages/mobile/tool/glass_lab/harness/tests/test_shapes.py
@@ -331,6 +331,12 @@ class OuterEdgeTests(unittest.TestCase):
         value, limit, bound = shapes.limits(result, scene)["left.step0e0.xmin.settle_ms"]
         self.assertGreater(value, limit)
 
+    def test_a_topology_change_alone_makes_an_event_significant(self):
+        flat = {key: np.zeros(10) for key in ("width", "height", "cx", "cy", "luma", "progress")}
+        self.assertFalse(shapes.significant(flat))
+        self.assertTrue(shapes.significant({**flat, "count": np.array([2.0] * 5 + [1.0] * 5)}))
+        self.assertFalse(shapes.significant({**flat, "count": np.array([2.0] * 10)}))
+
     def test_edges_do_not_make_a_still_event_significant(self):
         series = {key: np.zeros(10) for key in ("width", "height", "cx", "cy", "luma", "progress")}
         series.update({key: np.arange(10) * 10.0 for key in ("xmin", "xmax", "ymin", "ymax")})
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t23-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_manifest.py` => FAIL

Expected output ends with:

```text
FAILED (failures=1, errors=1)
```

RUN[t23-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/spacing_scenes_test.dart` => FAIL

Expected output ends with:

```text
+4 -1: Some tests failed.
```

Expected: the harness tests fail (`a topology change alone makes an event significant`, and the manifest has no `material.respace`) and `material.respace is two 80 pt circles...` fails on the registry.

- [ ] **Step 3: Apply the implementation.**

Patch `t23-impl` (`d4243f87f..7f868ffe1`, 4 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/spacing_scenes.dart b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/spacing_scenes.dart
index 21f0075b5d9ebd45374f65bd02eb5044b8fc8a38..9947db793dd855392a595d1bcaeda2c9570921e2 100644
--- a/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/spacing_scenes.dart
+++ b/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/spacing_scenes.dart
@@ -43,6 +43,7 @@ sealed class SpacingScenes {
     for (final MapEntry(key: id, value: gaps) in gaps.entries)
       id: (launch) => SpacingScene(backdrop: launch.backdrop, gaps: gaps, spacing: spacing[id]),
     'material.merge': (launch) => MergeScene(backdrop: launch.backdrop),
+    'material.respace': (launch) => RespaceScene(backdrop: launch.backdrop),
   };
 }
 
@@ -181,3 +182,64 @@ class _MergeSceneState extends State<MergeScene> {
     );
   }
 }
+
+class RespaceScene extends StatefulWidget {
+  const RespaceScene({super.key, required this.backdrop});
+
+  final String backdrop;
+
+  @override
+  State<RespaceScene> createState() => _RespaceSceneState();
+}
+
+class _RespaceSceneState extends State<RespaceScene> {
+  bool _wide = false;
+
+  void _set(bool wide) => withGlassAnimation(GlassAnimation.defaultSpring, () => setState(() => _wide = wide));
+
+  @override
+  Widget build(BuildContext context) {
+    return Stack(
+      children: [
+        Positioned.fill(child: GlassLabBackdrop(id: widget.backdrop)),
+        SafeArea(
+          child: Stack(
+            children: [
+              Positioned.fill(
+                child: CustomSingleChildLayout(
+                  delegate: const WholePointCenter(),
+                  child: GlassEffectContainer(
+                    spacing: _wide ? 40 : 8,
+                    child: const Row(
+                      mainAxisSize: MainAxisSize.min,
+                      children: [
+                        LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
+                        SizedBox(width: 12),
+                        LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
+                      ],
+                    ),
+                  ),
+                ),
+              ),
+              Positioned(
+                left: 0,
+                right: 0,
+                bottom: 120,
+                child: Center(
+                  child: Row(
+                    mainAxisSize: MainAxisSize.min,
+                    children: [
+                      LabButton(title: 'Widen', id: 'widen', onTap: () => _set(true)),
+                      const SizedBox(width: 24),
+                      LabButton(title: 'Narrow', id: 'narrow', onTap: () => _set(false)),
+                    ],
+                  ),
+                ),
+              ),
+            ],
+          ),
+        ),
+      ],
+    );
+  }
+}
diff --git a/packages/mobile/tool/glass_lab/harness/shapes.py b/packages/mobile/tool/glass_lab/harness/shapes.py
index 9b8ba2a7db7794065c5035b06a7797adba76a32c..baf22a1fdce81baf4c2c43fab2732781d2de4022 100644
--- a/packages/mobile/tool/glass_lab/harness/shapes.py
+++ b/packages/mobile/tool/glass_lab/harness/shapes.py
@@ -172,6 +172,8 @@ def event_series(times, rows, first, last):
 
 
 def significant(series):
+    if "count" in series and np.ptp(np.array(series["count"], dtype=np.float64)) >= 1:
+        return True
     return any(np.isfinite(series[key]).all() and np.ptp(series[key]) >= MIN_EVENT_CHANGE[key] for key in SIGNIFICANT_KEYS)
 
 
diff --git a/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift b/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift
index 050ecf55e26c4287ebff1fd2063ecb4f1cada59f..df3ec88c65b772824294de9b741548dfd8356bde 100644
--- a/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift
+++ b/packages/mobile/tool/glass_lab/native/GlassLab/MaterialScenes.swift
@@ -39,6 +39,7 @@ enum MaterialScenes {
         "material.spacing.80.d": { AnyView(SpacingScene(gaps: [48, 56, 64, 72], spacing: 80)) },
         "material.spacing.80.e": { AnyView(SpacingScene(gaps: [80, 88, 96], spacing: 80)) },
         "material.merge": { AnyView(MergeScene()) },
+        "material.respace": { AnyView(RespaceScene()) },
         "material.union": { AnyView(UnionScene()) },
         "material.morph": { AnyView(MorphScene()) },
         "material.morph.plain": { AnyView(MorphScene(interactive: false)) },
@@ -226,6 +227,30 @@ struct MergeScene: View {
     }
 }
 
+struct RespaceScene: View {
+    @State private var wide = false
+
+    var body: some View {
+        ZStack {
+            Backdrop()
+            GlassEffectContainer(spacing: wide ? 40 : 8) {
+                HStack(spacing: 12) {
+                    Color.clear.frame(width: 80, height: 80).glassEffect(.regular, in: .circle)
+                    Color.clear.frame(width: 80, height: 80).glassEffect(.regular, in: .circle)
+                }
+            }
+            VStack {
+                Spacer()
+                HStack(spacing: 24) {
+                    LabButton(title: "Widen", id: "widen") { withAnimation { wide = true } }
+                    LabButton(title: "Narrow", id: "narrow") { withAnimation { wide = false } }
+                }
+                .padding(.bottom, 120)
+            }
+        }
+    }
+}
+
 struct UnionScene: View {
     @Namespace private var namespace
     private let symbols = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill"]
diff --git a/packages/mobile/tool/glass_lab/scenes.json b/packages/mobile/tool/glass_lab/scenes.json
index 7dc2f6665be9c900bab319200f905a0164ab0d92..b6499fe77380c59f4904e0e0fb0bb40650eea67c 100644
--- a/packages/mobile/tool/glass_lab/scenes.json
+++ b/packages/mobile/tool/glass_lab/scenes.json
@@ -690,6 +690,58 @@
       ]
     }
   },
+  {
+    "id": "material.respace",
+    "group": "material",
+    "title": "Two 80 pt circles 12 pt apart in a container whose spacing animates between 8 and 40 pt",
+    "inventory": "2.14",
+    "app": "lab",
+    "backdrops": [
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
+        "tap": "widen"
+      },
+      {
+        "wait": 1.5
+      },
+      {
+        "tap": "narrow"
+      },
+      {
+        "wait": 1.5
+      }
+    ],
+    "regions": {
+      "pair": [
+        103,
+        399,
+        196,
+        104
+      ]
+    },
+    "track": [
+      "pair"
+    ],
+    "topology": [
+      "pair"
+    ],
+    "motion": [
+      "topology.count",
+      "topology.join_ms",
+      "topology.split_ms",
+      "topology.neck_rms",
+      "topology.gap_rms"
+    ]
+  },
   {
     "id": "material.union",
     "group": "material",
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t23-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_manifest.py` => PASS

Expected output ends with:

```text
Ran 57 tests in <time>
OK
```

RUN[t23-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/spacing_scenes_test.dart` => PASS

Expected output ends with:

```text
+5: All tests passed!
```

- [ ] **Step 5: Build the native lab app (Xcode 27); this is the only check the Swift of `RespaceScene` gets. `lab_ids_match_the_native_registry` (harness test) pins that the Swift registry and the manifest agree.**

RUN[t23-native-build]: `cd packages/mobile && python3 tool/glass_lab/harness/lab.py build native` => PASS

Expected output ends with:

```text
built for 708879DD-8B2A-4547-863F-F49EE1474D8B
```

- [ ] **Step 6: Gate: harness.**

RUN[t23-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

Expected output ends with:

```text
Ran 253 tests in <time>
OK
```

- [ ] **Step 7: Gate: example.**

RUN[t23-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t23-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

Expected output ends with:

```text
+25: All tests passed!
```

- [ ] **Step 8: Commit.**

```bash
git add -A packages
git commit -m "feat(glass_lab): material.respace, a native and a Flutter scene whose container spacing animates, judged on the pair's topology; a topology change alone makes an event significant

Co-Authored-By: <the session's attribution line>"
```

### Task 24: README and FORK say what the stills measure, that the spacing animation has no native reference yet, and what the new behaviours are

**Files:**
- Modify: `packages/ios_liquid_glass/README.md`, `FORK.md`

**Why.** Rulings 9, 12, 28-30. README claimed that the blend "matches native's necks and bulges ... from 4 to 80 pt" while 6 of the 46 recorded N7 cases pass end to end and none on dark; it now says what was measured (at most 0.5 pt RMS on the light photo silhouette, 9 spacings) and what was not. The container's material, the 16-shape guard, the anchor and the ghost fix are recorded in FORK as `FORK.md` requires.

- [ ] **Step 1: Apply the implementation.**

Patch `t24-impl` (`7f868ffe1..e320d0cbd`, 2 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/FORK.md b/packages/mobile/packages/ios_liquid_glass/FORK.md
index 64f058987035b72df41860fc5ded563b3b30baa0..5a1e80ba4651bbcfc9440c790cc09547a7f4abed 100644
--- a/packages/mobile/packages/ios_liquid_glass/FORK.md
+++ b/packages/mobile/packages/ios_liquid_glass/FORK.md
@@ -100,6 +100,10 @@ The package was renamed from `liquid_glass_renderer` to `ios_liquid_glass`, with
 ## ios_liquid_glass 0.1.0, project 2B.2 (morph)
 
 - New, not from upstream: `GlassEffectID` (`lib/src/api/glass_namespace.dart`); `GlassEffectTransition.matchedGeometry`; `GlassEffect(id:)`, whose `transition` is now nullable and resolves through `effectiveTransition` (matched geometry with an id, materialize without); the coordinator's arrivals, partners, sink and content ghosts, nearest-source choice and morph content blur (`glass_motion_coordinator.dart`), `GlassMorphGeometry` (`glass_morph_geometry.dart`, the shape gap on the line between centres), `GlassContentBlur` and `GlassMorphContent` (`glass_motion_widgets.dart`), and `ios27MorphContentBlur` in `ios27_motion.dart`.
+- `GlassShapeMotion` gains `isTransient` (a ghost is, a member is not) and `syncMoved()` (sync with the layout now and say whether the glass's anchor changed since last asked). `RenderLiquidGlassBlendGroup.gatherShapeData` leaves transient shapes out, last registered first, when a container would draw more than sixteen shapes, so a pending or sinking ghost never makes paint throw; seventeen members still do. `RenderLiquidGlassGeometry.maybeRebuildGeometry` asks `shapesMoved()` (the blend group asks each registered glass) before it trusts a cached geometry, so the geometry is rebuilt in the frame a glass's anchor changes and not the next.
+- `GlassMember`'s anchor is the glass's place in its space plus the space's on-screen origin (outer scrolling excluded), so a space that moves as its container resizes does not shift the glass a spring starts from.
+- `GlassEffectContainer.side` is nullable: unset, the container's layer follows a `GlassMaterialSource` whose side is the median of its members' laid-out shorter sides (`GlassMotionCoordinator.followMaterial`); `GlassContainerScope` carries that source and members use it (`sharedMaterial`) where they used static settings.
+- A content ghost whose partner has itself been removed samples the partner's morph spring, so a second swap inside the first settles.
 - `GlassGhost` is a `GlassShapeMotion`: a sinking ghost draws through `LiquidGlass.grouped` in its container's blend group at a rect it moves every frame, and the ghost stack places each ghost at `placement` and repaints on the coordinator's `ghostMotion`.
 
 Record every later change to `lib/` in this file.
diff --git a/packages/mobile/packages/ios_liquid_glass/README.md b/packages/mobile/packages/ios_liquid_glass/README.md
index 61dcbeba9d3a6227a4e6dff8a4fca83734aede71..3dc05b224a0c812b3350e672d6759b8dbdbb201e 100644
--- a/packages/mobile/packages/ios_liquid_glass/README.md
+++ b/packages/mobile/packages/ios_liquid_glass/README.md
@@ -66,7 +66,7 @@ The timing is native's, measured on the iOS 27 simulator. Appearing glass follow
 
 Each glass resolves its material (tone, frost, edge light and shadow) from its drawn size at layout and on every animated frame, so a glass growing from 44 to 200 pt changes its shadow as it grows.
 
-A container's glass blends with its neighbours as native's does: glass closer than `spacing` deforms toward its neighbour, and joins it into one shape when closer than about half of `spacing`. The shape is a smooth union weighted by the angle between the two shapes' edges, which matches native's necks and bulges on the iOS 27 simulator for spacings from 4 to 80 pt. Shapes blend by their drawn rects, so glass that springs toward or away from its neighbour joins and splits as it moves. A `spacing` change animates like a move: with `withGlassAnimation`'s animation, the nearest `GlassAnimationScope` or the default spring, and a spacing the app changes on consecutive frames follows its value.
+A container's glass blends with its neighbours as native's does: glass closer than `spacing` deforms toward its neighbour, and joins it into one shape when closer than about half of `spacing`. The shape is a smooth union weighted by the angle between the two shapes' edges; against native's stills its necks and bulges differ by at most 0.5 pt RMS (light photo, 9 spacings from 4 to 80 pt), but the whole still comparison passes in 6 of the 46 recorded cases (all light photo, none dark): the shadow and the pinch at the reach still differ. Shapes blend by their drawn rects, so glass that springs toward or away from its neighbour joins and splits as it moves. A `spacing` change animates like a move: with `withGlassAnimation`'s animation, the nearest `GlassAnimationScope` or the default spring, and a spacing the app changes on consecutive frames follows its value. That animation is this package's own design: no native recording of a container changing its `spacing` has been judged yet.
 
 A glass with a `GlassEffectID` and no `transition` morphs (`GlassEffectTransition.matchedGeometry`), as native glass with a `.glassEffectID` does; a glass without one materializes. Morphing glass stays at full brightness and blends with its container's other glass by `spacing` while it moves:
 - **With a partner.** A glass removed and another inserted with the same id in the same container in the same frame draw as one glass: it springs from the removed glass's drawn rect to the inserted one's layout with the animation in force, while the old content fades out over it and the new content fades in.
@@ -104,7 +104,7 @@ Reduce Transparency, Increase Contrast and Reduce Motion are read live. On iOS a
 
 Native glass changes with its size: a 200 pt glass casts a long soft shadow (sigma about 17 pt) where a 44 pt one casts almost none, and its tone and frost differ too. `GlassEffect` resolves the tuned material from its drawn size, interpolated between the 44, 88 and 200 pt anchors on its shorter side, at its first layout and whenever it changes size; no frame is painted with a guess. `sideHint` is the size its first build uses before that layout.
 
-Inside a `GlassEffectContainer`, every grouped child shares the container's single glass layer, so the layer's settings (tone, frost, edge light) are resolved once from the container's own `side` (default 88). Each child's shadow still comes from its own measured size.
+Inside a `GlassEffectContainer`, every grouped child shares the container's single glass layer, so the layer's settings (tone, frost, edge light) are resolved once for the whole container: from its `side` when one is given, and otherwise from the median of its members' measured shorter sides, following them as they resize, join and leave. A container of equal members (a union of 64 pt circles, a row of 44 pt buttons) therefore draws with the row of that size; a container of members of different sizes draws all of them with the median member's row, because one layer has one material. Each child's shadow still comes from its own measured size.
 
 ### Clear glass has no tint
 
```

- [ ] **Step 2: Commit.**

```bash
git add -A packages
git commit -m "docs(ios_liquid_glass): README states what the stills measure and that the spacing animation has no native reference yet; the container material, the cap, the anchor and the ghost fix are recorded in FORK

Co-Authored-By: <the session's attribution line>"
```

### Task 24b: A space's own move counts in a glass's anchor only when the glass's place in it changed too

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart` (`GlassMember._sync`, `_anchorOrigin`), `FORK.md`
- Test: `test/motion/glass_space_shift_test.dart` (one test, and `_Grow` gains `inside`)

**Why.** Ruling 29. Task 18 counted every move of the space; the app's own `floating_working_control_test` (`reduce motion changes instantly and runs no shimmer ticker`) failed in the first replay at Task 18's app gate, because glass that only moves with its parent (README: "anything that moves the container's parent moves the glass at once") started to spring. The origin shift is now added only when the glass's place in the space changed in the same frame, which is the morph's case (the toggle's place changes by 216 and its space moves by 108) and not the floating control's. The real-app morph check was repeated at this commit (`R/onset/flutter-morph-light-stripes-after.txt`, run `20261007-124647`).

- [ ] **Step 1: Add the failing tests.**

Patch `t24b-tests` (`e320d0cbd..4fe05e630`, 1 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_space_shift_test.dart b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_space_shift_test.dart
index 36d09f355bda14a643b4206953d69a8a6c233456..ab0744373ad24e7a918e3738c429977f051af141 100644
--- a/packages/mobile/packages/ios_liquid_glass/test/motion/glass_space_shift_test.dart
+++ b/packages/mobile/packages/ios_liquid_glass/test/motion/glass_space_shift_test.dart
@@ -68,7 +68,9 @@ class _MergeState extends State<_Merge> {
 }
 
 class _Grow extends StatefulWidget {
-  const _Grow();
+  const _Grow({this.inside = true});
+
+  final bool inside;
 
   @override
   State<_Grow> createState() => _GrowState();
@@ -89,15 +91,21 @@ class _GrowState extends State<_Grow> {
           child: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
-              GlassEffectContainer(
-                spacing: 20,
-                child: Column(
-                  mainAxisSize: MainAxisSize.min,
-                  children: [
-                    if (grown) const SizedBox(height: 100, width: 56),
-                    const GlassEffect(key: ValueKey('g'), child: SizedBox.square(dimension: 56)),
-                  ],
-                ),
+              if (grown && !widget.inside) const SizedBox(height: 100, width: 56),
+              Column(
+                mainAxisSize: MainAxisSize.min,
+                children: [
+                  GlassEffectContainer(
+                    spacing: 20,
+                    child: Column(
+                      mainAxisSize: MainAxisSize.min,
+                      children: [
+                        if (grown && widget.inside) const SizedBox(height: 100, width: 56),
+                        const GlassEffect(key: ValueKey('g'), child: SizedBox.square(dimension: 56)),
+                      ],
+                    ),
+                  ),
+                ],
               ),
             ],
           ),
@@ -191,4 +199,16 @@ void main() {
     await tester.pumpAndSettle();
     expect(_onScreen(member).top, closeTo(target.top, 1e-6));
   });
+
+  testWidgets('glass whose container only moves with its parent follows at once and springs nothing', (tester) async {
+    await tester.pumpWidget(const _Grow(inside: false));
+    await tester.pump(const Duration(seconds: 1));
+    final member = _member(tester, 'g');
+    tester.state<_GrowState>(find.byType(_Grow)).toggle();
+    await tester.pump();
+    final target = _layout(tester, 'g');
+    expect(_onScreen(member).top, closeTo(target.top, 1e-6));
+    await tester.pump(const Duration(milliseconds: 50));
+    expect(_onScreen(member).top, closeTo(target.top, 1e-6));
+  });
 }
```

- [ ] **Step 2: Run them and watch them fail.**

RUN[t24b-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart` => FAIL

Expected output ends with:

```text
+5 -1: Some tests failed.
```

Expected: `glass whose container only moves with its parent follows at once and springs nothing` fails (`Expected: a numeric value within <0.000001> of <322.0> Actual: <272.0>`); the five others pass.

- [ ] **Step 3: Apply the implementation.**

Patch `t24b-impl` (`e320d0cbd..4fe05e630`, 2 files):

```diff
diff --git a/packages/mobile/packages/ios_liquid_glass/FORK.md b/packages/mobile/packages/ios_liquid_glass/FORK.md
index 5a1e80ba4651bbcfc9440c790cc09547a7f4abed..fee86ddfced14fe7d6c9e312adeb7381497ee357 100644
--- a/packages/mobile/packages/ios_liquid_glass/FORK.md
+++ b/packages/mobile/packages/ios_liquid_glass/FORK.md
@@ -101,7 +101,7 @@ The package was renamed from `liquid_glass_renderer` to `ios_liquid_glass`, with
 
 - New, not from upstream: `GlassEffectID` (`lib/src/api/glass_namespace.dart`); `GlassEffectTransition.matchedGeometry`; `GlassEffect(id:)`, whose `transition` is now nullable and resolves through `effectiveTransition` (matched geometry with an id, materialize without); the coordinator's arrivals, partners, sink and content ghosts, nearest-source choice and morph content blur (`glass_motion_coordinator.dart`), `GlassMorphGeometry` (`glass_morph_geometry.dart`, the shape gap on the line between centres), `GlassContentBlur` and `GlassMorphContent` (`glass_motion_widgets.dart`), and `ios27MorphContentBlur` in `ios27_motion.dart`.
 - `GlassShapeMotion` gains `isTransient` (a ghost is, a member is not) and `syncMoved()` (sync with the layout now and say whether the glass's anchor changed since last asked). `RenderLiquidGlassBlendGroup.gatherShapeData` leaves transient shapes out, last registered first, when a container would draw more than sixteen shapes, so a pending or sinking ghost never makes paint throw; seventeen members still do. `RenderLiquidGlassGeometry.maybeRebuildGeometry` asks `shapesMoved()` (the blend group asks each registered glass) before it trusts a cached geometry, so the geometry is rebuilt in the frame a glass's anchor changes and not the next.
-- `GlassMember`'s anchor is the glass's place in its space plus the space's on-screen origin (outer scrolling excluded), so a space that moves as its container resizes does not shift the glass a spring starts from.
+- `GlassMember` springs from the glass's place in its space plus, when that place changed, the change of the space's own on-screen origin (outer scrolling excluded), so a space that moves as its container resizes does not shift the glass a spring starts from; a space that moves alone moves the glass at once.
 - `GlassEffectContainer.side` is nullable: unset, the container's layer follows a `GlassMaterialSource` whose side is the median of its members' laid-out shorter sides (`GlassMotionCoordinator.followMaterial`); `GlassContainerScope` carries that source and members use it (`sharedMaterial`) where they used static settings.
 - A content ghost whose partner has itself been removed samples the partner's morph spring, so a second swap inside the first settles.
 - `GlassGhost` is a `GlassShapeMotion`: a sinking ghost draws through `LiquidGlass.grouped` in its container's blend group at a rect it moves every frame, and the ghost stack places each ghost at `placement` and repaints on the coordinator's `ghostMotion`.
diff --git a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
index e650ed01356e16c06825a58e419a3e40daa717e2..c2c99f47c3baf54f7ad42cfe439b4ae480a712ca 100644
--- a/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
+++ b/packages/mobile/packages/ios_liquid_glass/lib/src/motion/glass_motion_coordinator.dart
@@ -65,6 +65,7 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
   RenderBox? _box;
   Size? _size;
   Offset? _anchor;
+  Offset? _anchorOrigin;
   Offset? _live;
   RenderObject? _liveSpace;
   Offset? _spaceOrigin;
@@ -269,24 +270,28 @@ class GlassMember extends ChangeNotifier implements GlassShapeMotion {
       _originFrame = frame;
       _readSpace(space, inner);
     }
-    final anchor = live - inner + _spaceOrigin! - _outerAtOrigin;
+    final anchor = live - inner;
+    final origin = _spaceOrigin! - _outerAtOrigin;
     final arrival = _arrival, size = _size;
     if (arrival != null && size != null) {
       _arrival = null;
       _anchor = anchor;
+      _anchorOrigin = origin;
       _moved = true;
       _arrive(arrival, live & size);
       return;
     }
-    final previous = _anchor;
+    final previous = _anchor, previousOrigin = _anchorOrigin;
     _anchor = anchor;
+    _anchorOrigin = origin;
     if (previous == null || previous == anchor) return;
     _moved = true;
     final animation = _changed();
     if (animation == null) return;
     final now = coordinator._now;
-    _offset[0].offsetBy(previous.dx - anchor.dx, animation, now);
-    _offset[1].offsetBy(previous.dy - anchor.dy, animation, now);
+    final shift = (previous - anchor) + ((previousOrigin ?? origin) - origin);
+    _offset[0].offsetBy(shift.dx, animation, now);
+    _offset[1].offsetBy(shift.dy, animation, now);
     coordinator._start();
   }
 
```

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t24b-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart` => PASS

Expected output ends with:

```text
+6: All tests passed!
```

- [ ] **Step 5: Gate: package.**

RUN[t24b-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t24b-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

Expected output ends with:

```text
+222: All tests passed!
```

- [ ] **Step 6: Gate: example.**

RUN[t24b-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t24b-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

Expected output ends with:

```text
+25: All tests passed!
```

- [ ] **Step 7: Gate: app.**

RUN[t24b-gate-app-analyze]: `cd packages/mobile && flutter analyze --no-pub` => PASS

Expected output ends with:

```text
No issues found! in <time>
```

RUN[t24b-gate-app-test]: `cd packages/mobile && flutter test --no-pub` => PASS

Expected output ends with:

```text
+2188: All tests passed!
```

- [ ] **Step 8: Gate: harness.**

RUN[t24b-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

Expected output ends with:

```text
Ran 253 tests in <time>
OK
```

- [ ] **Step 9: Commit.**

```bash
git add -A packages
git commit -m "fix(ios_liquid_glass): a space's own move counts in a glass's anchor only when the glass's place in it changed too, so glass that moves with its parent still follows at once

Co-Authored-By: <the session's attribution line>"
```
### Task 25: Noise floors for every 2B.2 scene and case (L8), over two sessions

**Files:**
- Modify: `tool/glass_lab/noise.json` (written by `lab.py repeat` only)

**Interfaces:**
- Consumes: `lab.py repeat --into`, `lab.py reboot`, the scenes of Tasks 2, 6, 7, 8, 11, 19 and 23, `take_check.py` and `press_check.py` (`R/`).
- Produces: `noise.json` entries `{scene: {case: {measure: noise}}}` for `material.merge`, `material.union`, `material.morph`, `material.morph.plain` (normal and `-reduce-motion` cases where they have them), `material.respace` and the 17 `material.spacing.*` scenes that have no floor yet: motion measures where a scene moves, and the static and still-topology measures (`ready.mad`, `ready.topology.<region>.count`, `.neck_pt`, `.gap_pt`) everywhere. Every limit those scenes are judged on becomes max(fixed threshold, 1.5 × noise) (spec L8). **Every floor is computed from scratch from this task's takes**; none is carried from the prototype. The six spacing scenes that 2B.1 recorded (`material.spacing.40.{a,b,c}`, `material.spacing.default.{a,b,c}`) keep their 2B.1 floors, because `repeat` rewrites a scene's whole entry and recording them again would replace those floors with different ones; Gotcha 52's case keeps what Task 3 wrote.

Five native takes per scene and case: three in session 1, then a simulator reboot, then two in session 2 appended to the same run, so the noise of each case is the worst of its ten pairs, six of them across the reboot. Cases: `material.merge` 4 + 4 (Reduce Motion), `material.union` 2, `material.morph` 4 + 4, `material.morph.plain` 4 + 4, `material.respace` 2 and 17 spacing scenes 2 each (light and dark photo): 62 cases, 310 takes, about 50 s a take, so about 4.3 h of recording and about 3 h of analysis; session 1 is about 2.6 h and session 2 about 1.7 h. **Disk:** analysis writes `overview/`, `shapes/` and `marker/` frame caches into every take (gotcha 51; 2B.1's 60 cases made 42 GB), so this task needs about 50 GB beyond the 40 GB floor: begin with at least 90 GB free, or record and recompute in groups (A: merge, morph and morph.plain, normal and Reduce Motion; B: union, respace and the spacing scenes) and **stop to ask the user to approve clearing the finished group's caches** (`overview/`, `shapes/` and `marker/` under its takes) whenever free space falls under 45 GB; **Numbers (2026-10-07, about 83 GB free before Task 3's 8.6 GB copy, so about 74 GB after it):** group A (merge, morph, morph.plain: 24 of the 62 cases) writes about 17 GB at 2B.1's rate (42 GB for 60 cases), group B about 25 GB; so the first group fits above the 45 GB line and the second probably does not unless the finished group's caches are cleared. **Run `df -h /Users/omaraly` before every group and before every case batch inside one; stop under 40 GB free and report; ask the user for space under 45 GB. Never delete anything yourself to make room** (including caches, old runs and worktrees: the user clears them or names a volume).

```bash
cd /Users/omaraly/development/AI/Operator-2b2/packages/mobile
R=/Users/omaraly/development/AI/Operator-2b2/docs/liquid_glass/02b-motion/research/proto-2b2
RUN=$PWD/build/glass_lab/runs/noise-2b2
```

- [ ] **Step 1: Reboot, then check the press.** Boot fresh, record one native `material.interactive` take, and read its 1.0 s press:

```bash
python3 tool/glass_lab/harness/lab.py build all
python3 tool/glass_lab/harness/lab.py reboot
python3 tool/glass_lab/harness/lab.py run material.interactive --app native --appearance light --backdrop photo
python3 $R/press_check.py --harness tool/glass_lab/harness build/glass_lab/runs/<run>/material.interactive/light-photo/native
```

Expected: `press 0.9xx s PASS` (the prototype read 0.950 s, run `20261007-054559`). A press outside 0.8–1.2 s means a stale boot: reboot again (gotcha 49). Install the backdrops after the build (Execution setup).

- [ ] **Step 2: Session 1, group A.** One command at a time, `run_in_background`; every `repeat` stops the script when it exits non-zero (`repeat` writes `noise.json` first and exits non-zero on `static repeatability FAILED`; that stops the task, and the executor reports the scene and case instead of going on):

```bash
for a in "" "--a11y reduce-motion"; do
  for s in material.merge material.morph material.morph.plain; do python3 tool/glass_lab/harness/lab.py repeat $s --times 3 $a --into $RUN || { echo "STOP $s $a"; exit 1; }; done
done
```

`repeat` takes one scene at a time (`manifest.select` with a bare `material.morph` also matches `material.morph.plain`, but `repeat` uses only the first match). Then check the press again as in Step 1: a press outside 0.8–1.2 s throws away every take recorded since the last good check, which are re-recorded after a reboot (they are excluded as in Step 5).

- [ ] **Step 3: Session 1, group B.**

```bash
python3 tool/glass_lab/harness/lab.py repeat material.union --times 3 --into $RUN || exit 1
python3 tool/glass_lab/harness/lab.py repeat material.respace --times 3 --into $RUN || exit 1
for s in default.d 4.a 6.a 8.a 10.a 12.a 16.a 20.a 20.b 20.c 40.d 40.e 80.a 80.b 80.c 80.d 80.e; do python3 tool/glass_lab/harness/lab.py repeat material.spacing.$s --times 3 --into $RUN || { echo "STOP $s"; exit 1; }; done
```

(The six scenes `default.a`, `default.b`, `default.c`, `40.a`, `40.b` and `40.c` are not in the list: they keep 2B.1's floors.) Check the press again after about three hours of session 1.

- [ ] **Step 4: Reboot, check the press, session 2.**

```bash
python3 tool/glass_lab/harness/lab.py reboot
xcrun simctl spawn 708879DD-8B2A-4547-863F-F49EE1474D8B defaults read com.apple.Accessibility ReduceMotionEnabled
```

Expected: `rebooted 708879DD-8B2A-4547-863F-F49EE1474D8B`, then `0`. Check the press as in Step 1, then run Steps 2 and 3 again with `--times 2` and the same `--into $RUN`. Each case now has takes 0–4 and each `repeat` rewrites its scene's entry from all five takes.

- [ ] **Step 5: The capture-hole rule and the touch gate.** For every case:

```bash
python3 $R/take_check.py --harness tool/glass_lab/harness --scene <scene id> $RUN/takes/<scene>/<case>/*
```

A take with a first-frame gap of 68–407 ms followed by frames 1.7–6.7 ms apart (gotcha 47), a touch window of zero length, or a touch count other than the scene's, is moved to `$RUN/excluded/` with a README line saying why, replaced by one more take recorded after a fresh boot, and the case's entry recomputed. The replacement is `repeat` with `--times 1` **and the case's flags**, so that it records that case only:

```bash
python3 tool/glass_lab/harness/lab.py repeat <scene id> --times 1 --appearance <light|dark> --backdrop photo [--a11y reduce-motion] --into $RUN
```

(without the flags it records every case of the scene and adds a take to each). Never let one take set a floor alone: for each case list the measures whose noise is above 3 × the median of the others and say why they stay (gotcha 52).

- [ ] **Step 6: Check the file and list what moved.**

```bash
python3 - <<'EOF'
import json, subprocess
noise = json.load(open("tool/glass_lab/noise.json"))
before = json.loads(subprocess.run(["git", "show", "HEAD:packages/mobile/tool/glass_lab/noise.json"], capture_output=True, text=True).stdout)
for scene in ("material.merge", "material.union", "material.morph", "material.morph.plain", "material.respace"):
    print(scene, {case: len(values) for case, values in sorted(noise[scene].items())})
kept = [f"material.spacing.{s}" for s in "default.a default.b default.c 40.a 40.b 40.c".split()]
print("2B.1 spacing floors unchanged:", all(noise[k] == before[k] for k in kept))
print(sum(len(noise[f"material.spacing.{s}"]) for s in "default.a default.b default.c default.d 4.a 6.a 8.a 10.a 12.a 16.a 20.a 20.b 20.c 40.a 40.b 40.c 40.d 40.e 80.a 80.b 80.c 80.d 80.e".split()), "spacing cases")
print([(scene, case, name) for scene, entry in noise.items() if isinstance(entry, dict) for case, values in entry.items() if isinstance(values, dict) for name, value in values.items() if value != value or value == float("inf")])
EOF
```

Expected: merge and morph list 8 cases each (4 normal, 4 `-reduce-motion`), `material.union` 2, `material.morph.plain` 8, `material.respace` 2; `2B.1 spacing floors unchanged: True`; `46 spacing cases`; `[]` for non-finite noise. Every `static mad` ≤ 1.0 (2B.1 measured 0.00). No `FAILED` line.

- [ ] **Step 7: Commit.**

```bash
git add packages/mobile/tool/glass_lab/noise.json
git commit -m "test(glass-lab): native noise floors for every 2B.2 scene and case, five takes over two sessions

Co-Authored-By: <the session's attribution line>"
```

### Task 26: `material.respace`, the native reference for the spacing animation (ruling 12)

**Files:**
- Create: `docs/liquid_glass/02b-motion/research/execution-2b2/respace-*.txt` (evidence)

**Interfaces:**
- Consumes: the scenes of Task 23, the floors of Task 25, the package's animated `spacing` (Task 4), `R/onset/topology_series.py`.
- Produces: whether native animates a container's `spacing`, what it does, and the scene's count in the Done table. **No native evidence for this behaviour exists before this task** (ruling 12); the prototype never recorded the scene.

- [ ] **Step 1: Fresh boot, press check, build.** As Task 25 Step 1, with `lab.py build all`.
- [ ] **Step 2: Record both apps.** `python3 tool/glass_lab/harness/lab.py run material.respace` (native and Flutter, light and dark photo; the steps are `widen` at 0.5 s and `narrow` at 2.0 s). Then `python3 tool/glass_lab/harness/lab.py report build/glass_lab/runs/<run>` and `python3 $R/verify/table.py --harness tool/glass_lab/harness build/glass_lab/runs/<run>`.
- [ ] **Step 3: Read native's frames, not the table.**

```bash
python3 $R/onset/topology_series.py --harness tool/glass_lab/harness --scene material.respace build/glass_lab/runs/<run>/material.respace/light-photo/native > respace-native-light-photo.txt
python3 $R/onset/topology_series.py --harness tool/glass_lab/harness --scene material.respace build/glass_lab/runs/<run>/material.respace/light-photo/flutter > respace-flutter-light-photo.txt
```

Each prints, per video frame of the capture, the time, the pair's component count, its neck thickness and its gap, after each tap. Native **animates** the spacing if, after `widen`, its neck thickens over at least three video frames (about 50 ms) between the first frame in which the pair differs from rest and the frame in which the neck is within 1 pt of its final value; if the neck appears at its final value in one frame, or the join comes within one video frame of the first change, native does not animate it.
- [ ] **Step 4: The decision.** **If native does not animate `spacing`: stop Task 26 here and report to the main session** with the two txt files and the frames (`R/verify/frames_at.py`); do not keep ruling 12's behaviour, do not change the package: ruling 12, the README sentence and Task 4's `spacingTo` and `blendMotion` stay in the tree until the main session decides. **Task 27 may proceed while this stop is active,** with every scene except those Task 26 depends on (`material.respace`, which Task 27 does not run; the `material.spacing.*` scenes of Step 5 keep a constant spacing per scene and do not need the animation); its results record the open decision, and the Done table's spacing-animation row reads `stopped, undecided`. **If native animates it:** the Flutter capture is judged like any scene: record per case `pass / judged / expected`, class each failure (a)–(d) with its number, and say in the report how far Flutter's join and split times and neck series are from native's (`topology.join_ms`, `split_ms`, `neck_rms`, `gap_rms`). A failure is not tuned away: the spring is the package's, and a different native spring is a finding for the main session.
- [ ] **Step 5: Commit the evidence.**

```bash
git add docs/liquid_glass/02b-motion/research/execution-2b2
git commit -m "docs(mobile): native reference for the container spacing animation

Co-Authored-By: <the session's attribution line>"
```

### Task 27: Verification runs and `results-2b2.md` (spec §8, 2B.2)

**Files:**
- Create: `docs/liquid_glass/02b-motion/results-2b2.md`
- Modify: `packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart` (only through `lab.py fitvis --write`, and only if Step 7 re-fits)

**Interfaces:**
- Consumes: everything above; `R/verify/table.py` (per case pass / judged / expected from `result.json`), `done_table.py`, `still_check.py`.
- Produces: the Done table and the run folders, every number recomputable from `result.json` by those scripts.

All of this runs on the package **after** the fix-round tasks (13–24), so its numbers differ from the prototype's (`R/verify/`, the package before them); the prototype's tables are the baseline each measure is compared with by name.

- [ ] **Step 1: Fresh boot, press check, disk.** As Task 25 Step 1 (press check at the start and after about three hours), and `df -h /Users/omaraly` before every `run` of Steps 2 to 9 (stop under 40 GB free and report, ask under 45 GB, delete nothing). `lab.py build all`, then install the backdrops (Execution setup). **A press outside 0.8-1.2 s:** reboot (`lab.py reboot`), run the check again, and record nothing until it reads inside the range; a stale press spoils the native recordings only, but `run` records both apps, so the runs recorded since the last good check are set aside (`excluded/`, with a line saying why) and recorded again after the reboot; never count or class a case from a run recorded under a failed check.
- [ ] **Step 2: Merge, normal and Reduce Motion.**

```bash
python3 tool/glass_lab/harness/lab.py run material.merge
python3 tool/glass_lab/harness/lab.py run material.merge --a11y reduce-motion
```

- [ ] **Step 3: Union.** `python3 tool/glass_lab/harness/lab.py run material.union`
- [ ] **Step 4: Morph and its plain control, normal and Reduce Motion.**

```bash
python3 tool/glass_lab/harness/lab.py run material.morph
python3 tool/glass_lab/harness/lab.py run material.morph --a11y reduce-motion
```

(`material.morph` selects `material.morph.plain` too.)
- [ ] **Step 5: The N7 spacing scenes.** `python3 tool/glass_lab/harness/lab.py run material.spacing --backdrop photo` (all 23 scenes, light and dark; `material.respace` is not selected by this prefix).
- [ ] **Step 6: Report, count, and check the topology masks on Flutter frames.** For each run:

```bash
python3 tool/glass_lab/harness/lab.py report build/glass_lab/runs/<run>
python3 $R/verify/table.py --harness tool/glass_lab/harness build/glass_lab/runs/<run>
```

Per case this prints `pass / judged / expected`. The counts are compared **by measure name** with the baseline tables (`R/verify/logs/table-newmanifest-*.txt` for merge and morph: the same measures on the prototype's recordings, at the package before Tasks 13–24; `R/verify/logs/table-*.txt` for the rest), not by total: `expected` is not constant between takes (`material.morph dark-photo-reduce-motion` 29 / 64 / 180 and `material.morph.plain dark-photo` 22 / 65 / 180 against 126 for the other cases of the same scene). Expected: every measure that passed in the baseline still passes unless its case now has a floor that can only have raised its limit; `events` `[2, 2]` and `touches` `[2, 2]` except for captures that fall in a class (d) hole (repeat those cases alone with `--appearance` and `--backdrop`). Every failing measure is classed (a)–(d) with a number and a crop (`R/verify/crop.py`, `frames_at.py`). **Hold-out for the topology masks** (ruling 2): for one Flutter merge case and one Flutter morph case, write down from the frames (`frames_at.py` sheets) whether the pair, and the stack, is one piece or more at 24 frames each, and compare with the mask's `count` per frame; report every disagreement as class (c) and do not tune the threshold.
- [ ] **Step 7: Materialize with the H4 exponents.** The fitted exponents stay fixed. Before anything reads `noise-2b1`, check that Task 3's exclusion holds: `test ! -e $NOISE/takes/material.materialize/light-photo-reduce-motion/2 && test -d $NOISE/takes/material.materialize/light-photo-reduce-motion/5` (a re-fit that read the bad take 2 would reproduce 2B.1's `cy.peak_ms` 150). **Recompute check with the final harness:** Task 3 wrote its `noise.json` entry with the harness as it was before Tasks 5, 6, 9 and 12 changed `analyze`, `shapes` and `track`. Without recording anything, recompute the Task 3 case with the final `lab.py` and compare with Task 3's file: `git show <Task 3 commit>:packages/mobile/tool/glass_lab/noise.json > /tmp/noise-task3.json; python3 $R/noise_recompute.py --harness tool/glass_lab/harness --run $NOISE --before /tmp/noise-task3.json --out /tmp/noise-final-moved.json material.materialize/light-photo-reduce-motion`. Expected: no value and no limit moved; **if any did, list each moved limit in `results-2b2.md` (name, Task 3's value, the final harness's value) and do not edit `noise.json` by hand: the main session decides**. `lab.py run material.materialize` (default, `.snappy`, `.bouncy`), normal and `--a11y reduce-motion`, then `python3 tool/glass_lab/harness/done_table.py <both runs>`. Expected: about 289 / 334 / 336 (the prototype's 144 + 145; **this count is in-sample for the exponents, ruling 22, and was judged under the new gotcha 52 floors where 2B.1's 266 of 336 was judged under the old: say so**); a re-fit (`lab.py fitvis <runs> noise-2b1 --write`) is made only if a measure moved by more than its noise, is reported as a change of the fitted table with the measures that moved, and `ios27MorphContentBlur` survives it (Task 12).
- [ ] **Step 8: Reduce Motion, native merge.** Compare the native merge's Reduce Motion cases with ruling 14's spring ranges; they must agree.
- [ ] **Step 9: Still glass no worse than 2A.** Run every 2B.1 still scene and compare against 2B.1's runs in the archive (`/Users/omaraly/development/AI/glass-lab-runs/2b1/runs/`): `material.regular` (`20261006-165449`), `material.clear` (`-170542`), `material.tinted` (`-171006`), `material.edge` (`-171635`), `material.regular --a11y reduce-transparency` (`-172307`), `--a11y increase-contrast` (`-173358`), `tabbar.rest --flutter operator` (`-174454`), `button.press --flutter operator` (`-175336`), `navbar.inline --flutter operator` (`-175623`):

```bash
python3 tool/glass_lab/harness/still_check.py /Users/omaraly/development/AI/glass-lab-runs/2b1/runs/<2B.1 run> build/glass_lab/runs/<new run>
```

Expected: `missing: 0` and `worse: 0` in each. **This compares with 2B.1's runs, a ratchet (each plan may drift by the allowed noise); the spec's reference is 2A (`7e318a49f`), whose runs are not in the archive. It covers pinned groups only (D1, accepted by the user): no 2A still scene has an unpinned container of members of different sizes (the nine scenes are standalone glass or the app's `GlassScope`, which pins `side` and `spacing: 20`), so a pass here says the shader rewrite and the pinned path are no worse and says nothing about the median member's row for mixed sizes; per-glass materials in one layer are the carry-in to project 3.** The default spacing changed to 8 pt and the container material now follows its members (ruling 30), so a failure here is a scene that relied on 20 pt or on the 88 pt row: give it `spacing: 20` or `side: 88` (as the app's `GlassScope` does for spacing), not a loosened measure. **If a pixel difference remains with `spacing: 20` and `side: 88` pinned, stop and report to the main session: the shader rewrite (`angleSmoothUnion` and the generic loop in `sdf.glsl`) touches every container scene and is the cause to suspect; do not tune it.**
- [ ] **Step 10: Gates.** The four gate commands of Execution setup, at the final tree. Record the counts.
- [ ] **Step 11: Write `results-2b2.md`** from the template below, with the run folders, the counts and the classed failures, and commit it with the runs' `table-*.txt` outputs under `docs/liquid_glass/02b-motion/research/execution-2b2/`.

```bash
git add docs/liquid_glass/02b-motion/results-2b2.md docs/liquid_glass/02b-motion/research/execution-2b2
git commit -m "docs(mobile): 2B.2 results

Co-Authored-By: <the session's attribution line>"
```

**`results-2b2.md` template.**

```markdown
# 2B.2 results

Date: <date>. Branch `feat/ios-liquid-glass-2b2`. Measured at `<sha>`. Noise floors: Task 25's, five takes per case over two boots; the six 2B.1 spacing scenes keep 2B.1's. Decisions taken: D1 A (ruling 30; the median member's row accepted by the user; the still check covers pinned groups only; per-glass materials in one layer carried to project 3), D2 A (ruling 31), D3 A (user-approved manifest correction of 2026-10-07, ruling 26; morph tracked at the stack's outer edges only, the heart and the bolt not tracked individually, carried to 2B.3 or a fix wave), D4 hand-placed 1.5, not tool-written (ruling 23), D5 (onset frame fixed, the rest carried), D6 spacing animation kept (ruling 12): <native animates `spacing`: yes | no, stopped>.

## The Done table

| Done item (spec §8, 2B.2) | Result | Evidence |
|---|---|---|
| 1 `material.merge`, `material.union` and `material.morph` pass, normal and Reduce Motion: per-shape motion, join and split timing, neck width over time, component count | <Pass | Partly failing | Failing>. Merge normal <dark-photo p/j/e, dark-stripes, light-photo, light-stripes>; Reduce Motion <…>. Morph normal <…>; Reduce Motion <…>; plain <…>. Union <…>. | run folders; `table-<run>.txt` |
| 2 The rebuilt union scene passes its still-image measures | <…> light-stripes <p/j/e>, dark-stripes <p/j/e> | <run>, ruling 17 |
| 3 The N7 spacing scenes pass their still-image and topology measures | <n> of 46 cases pass; counts agree at <…>; necks within <…> | <run> |
| 4 Still glass is no worse than 2A; gates | still: `missing: 0`, `worse: 0` in <9> scenes, <n> of <m> Flutter frames byte-identical; gates: app `+<n>`, package `+<n>`, example `+<n>`, harness <n> OK, all three `flutter analyze` clean | <runs> |
| (carried) 2B.1 Done item 4 | materialize <pass> / <judged> / 336, **judged under the gotcha 52 floors of Task 3 and with exponents fitted on the same takes (in-sample, ruling 22); 2B.1's 266 of 336 was judged under the old floors: not the same yardstick** | <runs> |
| (new) Spacing animation, ruling 12 | native animates `spacing`: <yes | no>; `material.respace` <p/j/e> light photo, dark photo; join and split times native <…> Flutter <…> | Task 26 |

## Judged / expected counts (passing / judged / expected)

| Scene | Appearance | Normal | Reduce Motion |
|---|---|---|---|
| `material.merge` | dark photo | <…> | <…> |
| `material.merge` | dark stripes | <…> | <…> |
| `material.merge` | light photo | <…> | <…> |
| `material.merge` | light stripes | <…> | <…> |
| `material.morph` | (4 cases) | <…> | <…> |
| `material.morph.plain` | (4 cases) | <…> | <…> |
| `material.union` | dark stripes, light stripes | <…> | not applicable |
| `material.spacing.*` | 23 scenes, light and dark photo | <n> of 46 cases | not applicable |

## Merge and morph, the old and the new manifest on the same recordings (D3)

Prototype recordings at the package before Tasks 13–24; counts are passing / judged (finite) / expected. The manifest correction is the user's (2026-10-07), not a loosening: ruling 26.

| Run (prototype) | Case | Old manifest | New manifest | Final package, Task 27 |
|---|---|---|---|---|
| `20261007-054755` merge | dark photo, dark stripes, light photo, light stripes | 20/41/66, 24/45/66, 25/44/66, 25/46/66 | 24/61/68, 30/67/68, 29/62/68, 33/68/68 | <…> |
| `20261007-055356` merge, Reduce Motion | same four | 20/41/66, 22/45/66, 27/46/66, 26/46/66 | 24/63/68, 26/67/68, 33/68/68, 32/68/68 | <…> |
| `20261007-060205` morph and plain | same four each | normal 19/59/126, 24/55/126, 29/55/126, 31/58/126; plain 22/65/180, 17/61/126, 25/59/126, 16/36/126 | normal 25/73/148, 28/69/148, 33/69/148, 36/72/148; plain 27/80/213, 21/75/148, 29/73/148, 17/43/148 | <…> |
| `20261007-061306` morph and plain, Reduce Motion | same four each | 29/64/180, 26/59/126, 34/60/126, 39/62/126; plain 21/62/126, 26/60/126, 31/60/126, 29/60/126 | 35/79/213, 31/73/148, 40/74/148, 47/76/148; plain 28/76/148, 35/74/148, 37/74/148, 36/74/148 | <…> |

## Gotcha 52, the limits that moved

<the list from Task 3 Step 3, with the limits that rose named (the prototype's three: `block.step1e0.cx.peak_ms`, `block.step1e0.width.response_pct`, `block.step3e0.luma.peak_ms`) and the take that set each>

## Failures, classed

| Measure | Case | Class (a)–(d) | Value against limit | Evidence (run, crop) |
|---|---|---|---|---|

## Provisional limits

<none after Task 25, or the list of measures still judged on a fixed threshold because their case has no floor, and why>

## Open

Merging 2B.2 with failing Done items is the user's decision on the classed failures (spec §8), not a pass; <state which of items 1–3 fail>.

<the package defects of ruling 21 that remain (the toggle's swelling, merge and split timing and hysteresis, one spring for every arrival, content sharpening order); the open items: the native control that would separate the emergence and sink hypotheses (ruling 18), a tracker for the inner glasses of the morph (ruling 26), a native frame of a union member appearing (ruling 16), per-member material rows inside one layer (ruling 30), `fitvis` writing `ios27MorphContentBlur` (D4); what Task 26 decided about the spacing animation>
```

## Self-review

- **Spec coverage (2B.2, spec §4 and §8):** M4 merge and split (Tasks 4, 6; rulings 7–14), container spacing animation (Task 4, ruling 12; its native reference Tasks 23 and 26), M5 union (Task 8; D1, D2: Tasks 20–22), M6 morph (Task 11; Tasks 13 and 15 for the swap and the cap), the lab's topology, gap and manifest corrections (Tasks 1, 5, 6, 19), H4 (Task 10), gotcha 52 (Task 3), the first frame of a move (D5: Tasks 16–18), L8 for every 2B.2 scene (Task 25), N6 for merge and morph (native Reduce Motion references recorded in the prototype, rulings 14 and 18; re-recorded in Task 27), §9's 16-shape test (Task 15), Done items 1–4 (Task 27).
- **Placeholders:** none in the code steps; every code step is a patch that ran in the prototype or in the fix round, and the replay applied them all. Tasks 3, 25, 26 and 27 are recordings and verification with no prototype counterpart (the user's reduced scope, 2026-10-07; Task 3's `noise.json` is made by the executor); their expected numbers are the prototype's end-to-end numbers on the package before the fix round, said so, or, for `material.respace`, none.
- **Review Focus:** every line names the test or check that pins it; what is not pinned is said (Review Focus 12).
