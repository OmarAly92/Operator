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

<<OUT t00-setup>>

### Task 1: Topology that agrees at zero, necks only on one component, a manifest that rejects topology without regions

**Files:**
- Modify: `tool/glass_lab/harness/shapes.py`, `track.py`, `manifest.py`
- Test: `tool/glass_lab/harness/tests/test_shapes.py`, `test_track.py`, `test_manifest.py`

**Why.** Ruling 1. 2B.2's join, split and neck measures read these functions; fixed first so nothing later is judged on a defect.

- [ ] **Step 1: Add the failing tests.**

<<PATCH t01-tests from=4db49edc3 to=fb0207573 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t01-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_manifest.py` => FAIL

<<OUT t01-harness-red>>

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t01-impl from=4db49edc3 to=fb0207573 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t01-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_manifest.py` => PASS

<<OUT t01-harness-green>>

- [ ] **Step 5: Gate: harness.**

RUN[t01-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t01-gate-harness>>

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

<<PATCH t02-impl from=fb0207573 to=54cfd52d5 files=@impl>>

- [ ] **Step 2: Check the manifest still loads and validates every scene.**

RUN[t02-manifest]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_manifest.py` => PASS

<<OUT t02-manifest>>

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

<<PATCH t04-tests from=4e32718e4 to=3269b9580 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t04-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/geometry/angle_union_test.dart test/motion/glass_spacing_test.dart` => FAIL

<<OUT t04-pkg-red>>

RUN[t04-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/spacing_scenes_test.dart` => FAIL

<<OUT t04-example-red>>

RUN[t04-app-red]: `cd packages/mobile && flutter test --no-pub test/core/widgets/glass/glass_scope_test.dart` => PASS

<<OUT t04-app-red>>

Expected: the package and example tests fail (missing symbols and values); the app's `glass_scope_test` **passes** before the implementation, by design: it pins that `GlassScope` keeps 20 pt, which was the package default until this task changes it, and it must still pass after.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t04-impl from=4e32718e4 to=3269b9580 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t04-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/geometry/angle_union_test.dart test/motion/glass_spacing_test.dart` => PASS

<<OUT t04-pkg-green>>

RUN[t04-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/spacing_scenes_test.dart` => PASS

<<OUT t04-example-green>>

RUN[t04-app-green]: `cd packages/mobile && flutter test --no-pub test/core/widgets/glass/glass_scope_test.dart` => PASS

<<OUT t04-app-green>>

- [ ] **Step 5: Gate: package.**

RUN[t04-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t04-gate-pkg-analyze>>

RUN[t04-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t04-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t04-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t04-gate-example-analyze>>

RUN[t04-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t04-gate-example-test>>

- [ ] **Step 7: Gate: app.**

RUN[t04-gate-app-analyze]: `cd packages/mobile && flutter analyze --no-pub` => PASS

<<OUT t04-gate-app-analyze>>

RUN[t04-gate-app-test]: `cd packages/mobile && flutter test --no-pub` => PASS

<<OUT t04-gate-app-test>>

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

<<PATCH t05-tests from=3269b9580 to=6006902f6 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t05-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_shapes.py` => FAIL

<<OUT t05-harness-red>>

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t05-impl from=3269b9580 to=6006902f6 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t05-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_shapes.py` => PASS

<<OUT t05-harness-green>>

- [ ] **Step 5: Gate: harness.**

RUN[t05-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t05-gate-harness>>

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

<<PATCH t06-impl from=6006902f6 to=96d7d5d03 files=@impl>>

- [ ] **Step 2: Check the manifest still loads and validates every scene.**

RUN[t06-manifest]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_manifest.py` => PASS

<<OUT t06-manifest>>

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

<<PATCH t07-impl from=d0cfaf7ae to=599853e52 files=@impl>>

- [ ] **Step 2: Check the manifest still loads and validates every scene.**

RUN[t07-manifest]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_manifest.py` => PASS

<<OUT t07-manifest>>

- [ ] **Step 3: Build the native lab app (Xcode 27, a few minutes); this is the only check the Swift of Tasks 2 and 7 gets.**

RUN[t07-native-build]: `cd packages/mobile && python3 tool/glass_lab/harness/lab.py build native` => PASS

<<OUT t07-native-build>>

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

<<PATCH t08-tests from=599853e52 to=3a1e5a7f1 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t08-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_union_test.dart test/motion/render_hooks_test.dart` => FAIL

<<OUT t08-pkg-red>>

RUN[t08-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/union_scene_test.dart` => FAIL

<<OUT t08-example-red>>

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t08-impl from=599853e52 to=3a1e5a7f1 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t08-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_union_test.dart test/motion/render_hooks_test.dart` => PASS

<<OUT t08-pkg-green>>

RUN[t08-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/union_scene_test.dart` => PASS

<<OUT t08-example-green>>

- [ ] **Step 5: Gate: package.**

RUN[t08-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t08-gate-pkg-analyze>>

RUN[t08-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t08-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t08-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t08-gate-example-analyze>>

RUN[t08-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t08-gate-example-test>>

- [ ] **Step 7: Gate: app.**

RUN[t08-gate-app-analyze]: `cd packages/mobile && flutter analyze --no-pub` => PASS

<<OUT t08-gate-app-analyze>>

RUN[t08-gate-app-test]: `cd packages/mobile && flutter test --no-pub` => PASS

<<OUT t08-gate-app-test>>

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

<<PATCH t09-tests from=3a1e5a7f1 to=359eb8e31 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t09-lab-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_lab.py` => FAIL

<<OUT t09-lab-red>>

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t09-impl from=3a1e5a7f1 to=359eb8e31 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t09-lab-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_lab.py` => PASS

<<OUT t09-lab-green>>

- [ ] **Step 5: Gate: harness.**

RUN[t09-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t09-gate-harness>>

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

<<PATCH t10-tests from=6873314df to=22df6e970 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t10-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_materialize_test.dart` => FAIL

<<OUT t10-pkg-red>>

RUN[t10-fitvis-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py` => FAIL

<<OUT t10-fitvis-red>>

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t10-impl from=6873314df to=22df6e970 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t10-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_materialize_test.dart` => PASS

<<OUT t10-pkg-green>>

RUN[t10-fitvis-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py` => PASS

<<OUT t10-fitvis-green>>

- [ ] **Step 5: Check the committed exponents are `fitvis`'s fitted values (`h4/fit-h4.json`).**

RUN[t10-table]: `python3 -c "import json,re; m=json.load(open('docs/liquid_glass/02b-motion/research/proto-2b2/h4/fit-h4.json'))['mapping']; t=open('packages/mobile/packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart').read(); w={'material.materialize':'Default','material.materialize.snappy':'Snappy','material.materialize.bouncy':'Bouncy'}; print([(n, m[k]['appear_exponent']['value'], float(re.search('ios27'+n+'AppearExponent = ([0-9.]+)',t).group(1))) for k,n in w.items()])"` => PASS

<<OUT t10-table>>

- [ ] **Step 6: Gate: package.**

RUN[t10-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t10-gate-pkg-analyze>>

RUN[t10-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t10-gate-pkg-test>>

- [ ] **Step 7: Gate: harness.**

RUN[t10-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t10-gate-harness>>

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

<<PATCH t11-tests from=c8121c7aa to=f4039bea6 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t11-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_morph_test.dart` => FAIL

<<OUT t11-pkg-red>>

RUN[t11-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/morph_scene_test.dart` => FAIL

<<OUT t11-example-red>>

Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t11-impl from=c8121c7aa to=f4039bea6 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t11-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_morph_test.dart` => PASS

<<OUT t11-pkg-green>>

RUN[t11-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/morph_scene_test.dart` => PASS

<<OUT t11-example-green>>

- [ ] **Step 5: Gate: package.**

RUN[t11-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t11-gate-pkg-analyze>>

RUN[t11-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t11-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t11-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t11-gate-example-analyze>>

RUN[t11-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t11-gate-example-test>>

- [ ] **Step 7: Gate: app.**

RUN[t11-gate-app-analyze]: `cd packages/mobile && flutter analyze --no-pub` => PASS

<<OUT t11-gate-app-analyze>>

RUN[t11-gate-app-test]: `cd packages/mobile && flutter test --no-pub` => PASS

<<OUT t11-gate-app-test>>

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

<<PATCH t12-tests from=f4039bea6 to=1d2ddc57a files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t12-fitvis-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py` => FAIL

<<OUT t12-fitvis-red>>

Expected: `FAILED (failures=1)`. Task 12 adds two tests; only `test_a_write_keeps_the_morph_content_blur_line_the_target_already_holds` fails before the implementation (the old `table_source` deletes the line). `test_a_write_to_a_target_without_the_morph_content_blur_line_adds_none` **passes** before it, by design: it pins the other half of the rule (a target that has no such line must not gain one), which the old code also satisfied and a careless fix could break, so it is a guard and not a red test.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t12-impl from=f4039bea6 to=1d2ddc57a files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t12-fitvis-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_fitvis.py` => PASS

<<OUT t12-fitvis-green>>

- [ ] **Step 5: Gate: harness.**

RUN[t12-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t12-gate-harness>>

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

<<PATCH t13-tests from=4db370855 to=3f5f59cbf files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t13-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_morph_test.dart` => FAIL

<<OUT t13-pkg-red>>

Expected: the two new tests fail on `Expected: empty / Actual: [Instance of 'GlassGhost']` (the ghost is still there 5 s after the second swap, at a 60 ms and at a 300 ms gap); the other morph tests pass.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t13-impl from=4db370855 to=3f5f59cbf files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t13-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_morph_test.dart` => PASS

<<OUT t13-pkg-green>>

- [ ] **Step 5: Gate: package.**

RUN[t13-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t13-gate-pkg-analyze>>

RUN[t13-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t13-gate-pkg-test>>

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

<<PATCH t14-impl from=3f5f59cbf to=42f09d87f files=@all>>

- [ ] **Step 2: Gate: package.**

RUN[t14-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t14-gate-pkg-analyze>>

RUN[t14-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t14-gate-pkg-test>>

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

<<PATCH t15-tests from=42f09d87f to=19e53ff72 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t15-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_group_test.dart` => FAIL

<<OUT t15-pkg-red>>

Expected: three of the four tests fail on `Expected: an object with length of <16>` or on the ghost that should have been left out (18, 17 and 16 shapes drawn); `ghosts under the cap all stay in the geometry` passes before and after, by design.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t15-impl from=42f09d87f to=19e53ff72 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t15-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_group_test.dart` => PASS

<<OUT t15-pkg-green>>

- [ ] **Step 5: Gate: package.**

RUN[t15-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t15-gate-pkg-analyze>>

RUN[t15-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t15-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t15-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t15-gate-example-analyze>>

RUN[t15-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t15-gate-example-test>>

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

<<PATCH t16-impl from=19e53ff72 to=7bf674822 files=@all>>

- [ ] **Step 2: Gate: package.**

RUN[t16-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t16-gate-pkg-analyze>>

RUN[t16-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t16-gate-pkg-test>>

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

<<PATCH t17-tests from=7bf674822 to=ab9ee28c6 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t17-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart test/motion/glass_group_test.dart` => FAIL

<<OUT t17-pkg-red>>

Expected: `both circles report that they moved...`, `a move without an animation is reported...` and `a settled geometry is marked for an update...` fail (the member and the group answer `false` before the implementation); the others pass.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t17-impl from=7bf674822 to=ab9ee28c6 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t17-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart test/motion/glass_group_test.dart` => PASS

<<OUT t17-pkg-green>>

- [ ] **Step 5: Gate: package.**

RUN[t17-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t17-gate-pkg-analyze>>

RUN[t17-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t17-gate-pkg-test>>

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

<<PATCH t18-tests from=ab9ee28c6 to=6569e47e2 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t18-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart` => FAIL

<<OUT t18-pkg-red>>

Expected: the two `glass in a space that re-centres...` tests fail on `Actual: <222.0>` against 272.0 (grow) and `Actual: <372.0>` against 322.0 (shrink): the glass is drawn 50 pt from where it was.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t18-impl from=ab9ee28c6 to=6569e47e2 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t18-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart` => PASS

<<OUT t18-pkg-green>>

- [ ] **Step 5: Gate: package.**

RUN[t18-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t18-gate-pkg-analyze>>

RUN[t18-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t18-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t18-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t18-gate-example-analyze>>

RUN[t18-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t18-gate-example-test>>

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

<<PATCH t19-tests from=6569e47e2 to=5ed43ab6e files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t19-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_manifest.py` => FAIL

<<OUT t19-harness-red>>

Expected: the new tests fail on a missing key (`xmin`, `gap`, `topology.gap_rms`, `edges`) or on the manifest entries; nothing else changes.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t19-impl from=6569e47e2 to=5ed43ab6e files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t19-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_track.py tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_manifest.py` => PASS

<<OUT t19-harness-green>>

- [ ] **Step 5: Gate: harness.**

RUN[t19-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t19-gate-harness>>

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

<<PATCH t20-tests from=5ed43ab6e to=4d42f3642 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t20-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/glass_container_material_test.dart` => FAIL

<<OUT t20-pkg-red>>

Expected: five of the six tests fail on `Expected: LiquidGlassSettings` (the row of 88 is drawn); `a container with an explicit side keeps that row` passes before and after, by design.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t20-impl from=5ed43ab6e to=4d42f3642 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t20-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/glass_container_material_test.dart` => PASS

<<OUT t20-pkg-green>>

- [ ] **Step 5: Gate: package.**

RUN[t20-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t20-gate-pkg-analyze>>

RUN[t20-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t20-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t20-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t20-gate-example-analyze>>

RUN[t20-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t20-gate-example-test>>

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

<<PATCH t21-impl from=4d42f3642 to=8d61ee26c files=@all>>

- [ ] **Step 2: Gate: example.**

RUN[t21-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t21-gate-example-analyze>>

RUN[t21-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t21-gate-example-test>>

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

<<PATCH t22-tests from=8d61ee26c to=d4243f87f files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t22-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/union_scene_test.dart` => FAIL

<<OUT t22-example-red>>

Expected: `each glyph is sized so its ink is as tall as native's...` fails (`Expected: [33.0, 28.0, 34.5, 32.5] Actual: [24.0, 24.0, 24.0, 24.0]`); the other two pass.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t22-impl from=8d61ee26c to=d4243f87f files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t22-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/union_scene_test.dart` => PASS

<<OUT t22-example-green>>

- [ ] **Step 5: Gate: example.**

RUN[t22-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t22-gate-example-analyze>>

RUN[t22-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t22-gate-example-test>>

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

<<PATCH t23-tests from=d4243f87f to=7f868ffe1 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t23-harness-red]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_manifest.py` => FAIL

<<OUT t23-harness-red>>

RUN[t23-example-red]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/spacing_scenes_test.dart` => FAIL

<<OUT t23-example-red>>

Expected: the harness tests fail (`a topology change alone makes an event significant`, and the manifest has no `material.respace`) and `material.respace is two 80 pt circles...` fails on the registry.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t23-impl from=d4243f87f to=7f868ffe1 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t23-harness-green]: `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_shapes.py tool/glass_lab/harness/tests/test_manifest.py` => PASS

<<OUT t23-harness-green>>

RUN[t23-example-green]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub test/spacing_scenes_test.dart` => PASS

<<OUT t23-example-green>>

- [ ] **Step 5: Build the native lab app (Xcode 27); this is the only check the Swift of `RespaceScene` gets. `lab_ids_match_the_native_registry` (harness test) pins that the Swift registry and the manifest agree.**

RUN[t23-native-build]: `cd packages/mobile && python3 tool/glass_lab/harness/lab.py build native` => PASS

<<OUT t23-native-build>>

- [ ] **Step 6: Gate: harness.**

RUN[t23-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t23-gate-harness>>

- [ ] **Step 7: Gate: example.**

RUN[t23-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t23-gate-example-analyze>>

RUN[t23-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t23-gate-example-test>>

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

<<PATCH t24-impl from=7f868ffe1 to=e320d0cbd files=@all>>

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

<<PATCH t24b-tests from=e320d0cbd to=4fe05e630 files=@tests>>

- [ ] **Step 2: Run them and watch them fail.**

RUN[t24b-pkg-red]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart` => FAIL

<<OUT t24b-pkg-red>>

Expected: `glass whose container only moves with its parent follows at once and springs nothing` fails (`Expected: a numeric value within <0.000001> of <322.0> Actual: <272.0>`); the five others pass.

- [ ] **Step 3: Apply the implementation.**

<<PATCH t24b-impl from=e320d0cbd to=4fe05e630 files=@impl>>

- [ ] **Step 4: Run the tests again and watch them pass.**

RUN[t24b-pkg-green]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_space_shift_test.dart` => PASS

<<OUT t24b-pkg-green>>

- [ ] **Step 5: Gate: package.**

RUN[t24b-gate-pkg-analyze]: `cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub` => PASS

<<OUT t24b-gate-pkg-analyze>>

RUN[t24b-gate-pkg-test]: `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub` => PASS

<<OUT t24b-gate-pkg-test>>

- [ ] **Step 6: Gate: example.**

RUN[t24b-gate-example-analyze]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub` => PASS

<<OUT t24b-gate-example-analyze>>

RUN[t24b-gate-example-test]: `cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub` => PASS

<<OUT t24b-gate-example-test>>

- [ ] **Step 7: Gate: app.**

RUN[t24b-gate-app-analyze]: `cd packages/mobile && flutter analyze --no-pub` => PASS

<<OUT t24b-gate-app-analyze>>

RUN[t24b-gate-app-test]: `cd packages/mobile && flutter test --no-pub` => PASS

<<OUT t24b-gate-app-test>>

- [ ] **Step 8: Gate: harness.**

RUN[t24b-gate-harness]: `cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests` => PASS

<<OUT t24b-gate-harness>>

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
