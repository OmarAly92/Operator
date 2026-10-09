# Re-review of fix wave 1: ios_liquid_glass 2B.2 (`feat/ios-liquid-glass-2b2`, tip 15160aca4)

Ready to merge: **yes after fixes** (three one-line statement corrections in `results-2b2.md`; no code, data or measure change; no blocker or major finding).

## What I ran

Own detached worktree `Operator-2b2-rereview` at 15160aca4 (removed afterwards, `git worktree list` clean), `flutter pub get --offline`. Read-only on the branch and the recordings: the A2 case's five takes were copied (APFS clone) into the scratchpad and every recompute wrote there, never into `noise.json`, `noise-2b2` or a run folder. No lab, simulator or build command. Disk 50 GB before and after. Shared checkout untouched (its status is the pre-existing `frontend/` edits).

## Gate lines (all match the claims)

| Gate | Result |
|---|---|
| `packages/mobile` analyze / test | No issues found! / +2189 All tests passed |
| `packages/ios_liquid_glass` analyze / test | No issues found! / +261 All tests passed |
| `.../example` analyze / test | No issues found! / +25 All tests passed |
| `python3 -m unittest discover tool/glass_lab/harness/tests` | Ran 253 tests, OK |

## Findings

**R1. minor. `results-2b2.md` line 5 says "Nothing changed a measure or lowered a limit".** The same file (section "The second broken take") says 60 limits fell. Scenario: a reader takes line 5 as "no limit moved down", the opposite of what happened (the fall is the correction, not a loosening). Evidence: `moved.json` from my recompute: 94 values, 80 limits, 60 fell, 20 rose. Fix: "no measure changed and no limit moved outside one case; 60 fell and 20 rose there".

**R2. minor. Stale counts in the ruling-33 re-run section (`results-2b2.md` line 162).** "plain 55, 53, 89, 79 against 54, 58, 84, 77" still carries the pre-wave 79 (re-run `20261009-010310`) and 77 (Task 27). Under the new floors both are 73 (I rejudged both: 79 to 73, 77 to 73). The Done table and D3 table are corrected; this one sentence is not marked "fix wave 1". Fix: update to 73 and 73 or mark the sentence "as first written".

**R3. minor. The A4 reclass over-reads its evidence.** Results table row and todo row say 420 of 553 and 360 of 423 are "absent only because of the net-travel gate" and class (a). `absent.py` buckets them as "key absent (travel under minimum on a side, or NaN series)" and never separates the two; the excursions that differ are shown for six keys of one case (morph light-stripes normal). The by-key pattern (heart/bolt `width`, collapsed `cy`/`width` in all 17 cases, 5 measures each) points at systematic round-trip keys, so the reclass is probably right, but the series are not stored in `result.json`, so I could not split NaN from under-travel without re-running capture. The class counts do add up (895 - 553 = 342 other failures; 133 = 104 + 20 + 2 + 7; RM 63 = 58 + 4 + 1; 133 and 63 match the table), the gate and every measure are unchanged (`git diff` of `tool/glass_lab/harness` is empty). Fix: say "most of" and "probably" until the NaN share is counted, or count it.

**R4. note, for the user. E8: "ruling stands" while the code review's own test is not met.** The review said the ruling stands if no limit moves by more than one step. The wave's comparison (`e8-flagged-comparison.json`; I re-ran `e8_flagged.py` from a scratch copy, output byte-identical) shows 79 + 100 + 125 + 80 = 384 limits falling in four cases, 158 of them by more than half, and four cases (dark-photo, dark-photo Reduce Motion, light-photo Reduce Motion, light-stripes) with fewer than two unflagged takes, so not computable. The wave says exactly this, says the one-step test is not met, and keeps the ruling "as ordered". That is honest. Two points for the decision: (a) the control (dropping any same-size set of takes lowers 61-153 limits, and the flagged-out counts, 101/101/146/80 once the no-value limits are included to match the control's definition, sit inside those ranges) shows only that dropping takes always lowers a max of five, not that the flagged takes are ordinary; no per-take outlier test of the 27 was run; (b) `take_check` missed the A2 take, so it is a weak guard either way. Recommendation: accept the ruling (floors only move down when takes are dropped, so keeping them is the conservative side) or ask for a third recording of the four non-computable cases; not a merge blocker.

**R5. note. FORK.md says the parity test means "the two cannot drift".** It covers `angleSmoothUnion`, the fold-loop line and the first-shape line (text pins), with the shape SDFs of the mirror feeding both sides. The shader's `sdf*Grad` functions, `shapedGradient` and the zero-length fallback (`len > 1e-6`, unreachable in the test scenes) are not compared. Wording only.

**R6. note. Pre-existing and unchanged by the wave: the split of "newly passing" in `analysis-step6.md` (2) for morph + plain Reduce Motion.** I reproduce 237 (233 after), 25 lost and 406 raised (404 after) exactly, but get 121 under the baseline limit and 116 only under a raised limit, against the table's 113 and 124. The totals agree, so the Done verdicts do not depend on it.

**R7. note. The 20 limits that rose** (all in `material.morph.plain/light-stripes-reduce-motion`; each equals max(fixed, 1.5 x noise) of the recomputed noise and each noise maximum is a pair containing take 5): `bolt.step1e0.progress.sharpness` 1 -> 5.342 (pair 3-5), `bolt.step3e0.progress.sharpness` 69.12 -> 85.34 (2-5), `heart.step1e0.progress.damping` 0.05 -> 0.06 (3-5), `heart.step3e0.progress.sharpness` 1.233 -> 1.628 (4-5), `stack.step1e0.height.damping` / `ymax.damping` / `ymin.damping` 0.12 -> 0.195 (1-5), `stack.step1e0.height.response_pct` / `ymax.response_pct` / `ymin.response_pct` 7.317 -> 10.47 (4-5), `stack.step1e0.topology.neck_rms` 4.39 -> 4.855 (1-5), `star.step1e0.cy.response_pct` 9.78 -> 13.04, `star.step1e0.height.response_pct` 7.41 -> 9.26, `star.step1e0.width.peak_ms` and `settle_ms` 17 -> 25, `toggle.step1e0.cy.response_pct` 9.78 -> 13.04, `toggle.step1e0.height.response_pct` 7.5 -> 11.25, `toggle.step1e0.luma.response_pct` 7.5 -> 9.375, `toggle.step1e0.width.peak_ms` and `settle_ms` 17 -> 25 (all 1-5). The list in the results matches mine one for one. They are consequences of a new take's real spread, not loosening by hand; the biggest (`bolt.step1e0.progress.sharpness`, x5.3) rests on one pair, the A3 leverage point again. Nothing else rose: `noise.json` differs from 78ffa9b51 in exactly that one case, and no limit is below the baseline's in the eight counted Reduce Motion cases.

**R8. note. A5's "find the input source" has no todo row.** The results state the cause (input the driver did not send) and that the simulator must be exclusive while recording; no follow-up to find the source is written down. Optional.

## Resolution table

| Finding | Status | Evidence checked |
|---|---|---|
| C1 (fold gradient flips) | Stated honestly (user option A, carry-in) | FORK.md line, todo row and pin test agree with the review: `mix(near.yz, far.yz, h * 0.5)` in `sdf.glsl` and the mirror, three-or-more-shape folds change, re-measure merge/morph/union/navbar. Numbers 0.877 / 2.159 are the pin's finer scan (review said 0.87 / 2.14). With the fix applied to the mirror the step is 1.7e-5, as the review said. |
| C2 (no shader/mirror test) | Resolved | See "tests can fail" below. |
| C3 (leave() pairing, double-partner guard) | Resolved | Both tests fail when the code is mutated (below). |
| C4 (in-sample fit) | Stated honestly | Results line 20 states it next to the 296. |
| C5 (blur repaint one frame late) | Stated honestly | todo row, "not reproduced", no code change. |
| A1 (same yardstick) | Resolved | I rejudged all 24 prototype cases under today's `noise.json`: every cell of the new column matches (merge 32/38/29/34, 39/41/38/33; morph 42/36/43/49, 43/40/57/58; plain 32/23/31/19, 29/37/45/41). The column is headed "New manifest, today's floors", the text says the other two were judged under the prototype's lower limits and that only the last two are comparable. |
| A2 (broken take) | Resolved | Below. |
| A3 (leverage) | Stated honestly | Results line 26 gives the 22-measure range and the five examples; `noise-leave-one-out.txt` present. The A2 case's own range 69-73 reproduces (drop take 1: 72, 2: 69, 3: 73, 4: 72, 5: 70). |
| A4 (absent reclass) | Stated honestly, with R3 | Counts add up; gate and measures untouched. |
| A5 (tabbar worse: 6) | Stated honestly | `worse: 6`, two-run assembly and outside input are in the Done row, the still-check section and the failure table. R8. |
| A6 (gotcha 52 attribution) | Resolved | Text now attributes step 3 `cy` limits to pair (1, 5) with take 1 the driver and says none of the four is judged in materialize. |
| A7 (materialize) | Resolved | 11 lost / 18 gained, in-sample, +-10 measures, all stated. |
| A8 (toggle spring) | Stated honestly | Both readings and "unexplained" are in results and todo; still unexplained. |
| E8 (flagged takes) | Stated honestly; user decision (R4) | `e8_flagged.py` re-run reproduces the JSON exactly. |

## "New tests can fail"

- **Interpreter fidelity.** `glsl_function.dart` strips `//` comments, splits on `;`, and handles exactly what `angleSmoothUnion` uses: float/vec2/vec3 declarations, `max`, `abs`, `dot`, `length`, `mix` (scalar t), `vec3(...)` flattening, swizzles, unary minus, `*` `/` `+` `-`, comparisons, ternary. Precedence is right, ternary branches are evaluated eagerly (harmless; the unselected branch is finite or discarded). It agrees with the independently written Dart mirror to 1e-9 over 15 scene/k combinations (about 5000 samples each), which two independent implementations would not do if the interpreter had a bug in these constructs. Limits: doubles, not float32; both sides take their shape SDFs from the mirror (R5).
- **Mutations I ran (each confirmed failing, each reverted with `git checkout --`, scratch `git status` clean):**
  1. shader weight `* 0.5` -> `* 0.7`: 16 parity tests fail.
  2. near/far selection inverted (both lines): parity fails.
  3. mirror `t = h * w * 0.5` -> `h * 0.5`: parity fails and the C1 pin fails (step 1.7e-5 against 0.877).
  4. shader carried gradient `h * w * 0.5` -> `h * 0.5`: parity fails (15), pin still passes (mirror-only), as designed.
  5. shader `k * 0.25` -> `k * 0.3`: parity fails.
  6. shader `/ k` -> `/ (k * 1.0001)`: parity fails (tolerance 1e-9 is tight enough).
  7. shader `mix(near.yz, far.yz, ...)` swapped to `mix(far.yz, near.yz, ...)`: parity fails.
  8. fix applied to both ports (`h * 0.5` in shader and mirror): parity passes, the C1 pin fails alone, so a project 3 fix has to touch the pin, as FORK says.
  9. C3: `leave()` pairing replaced by `if (false)`: `glass_member_test` and `glass_morph_test` (the arrival-first swap) each lose one test.
  10. C3: double-partner guard removed: `glass_member_test` ("of two leavers with one id only the first pairs") fails.
- The C1 carry-in text (`h * 0.5` in `sdf.glsl` and `scene_sdf_mirror.dart`, equal weights at the bisector, three-or-more-shape folds change) matches the review.

## A2 exclusion and recompute (item 4)

- Moved, not deleted: `noise-2b2/excluded/takes/.../light-stripes-reduce-motion/0` and `excluded/material.morph.plain/light-stripes-reduce-motion/pair-0-{1,2,3,4}` exist with their `native`/`flutter` content; `excluded/README.txt` is one line with the reasons; `relinks-2b2.json` records the re-pointed links; no dangling symlink anywhere in `noise-2b2` or under `excluded/`.
- Take 5 (video start 1791506911.76, fresh boot, press 0.947 s per the results): `take_check.py` PASS: touches [16.412, 16.532] and [19.407, 19.480] (120 ms and 73 ms; siblings 88 / 94 ms, 80-100 ms), step 1 first-frame gap 8.3 ms then 3.3, step 3 gap 73.3 ms then 11.7 with burst 0 (no squeeze, so not a capture hole; the siblings show 80-100 ms at step 3). ffprobe: 266 frames, the only long gap 8.905 s to 16.41 s is the still screen before the tap, the same shape as take 1 (8.93 s to 16.1 s), and the touch window opens where the motion starts, so there is one timeline. Static mad 0.00.
- `noise.json`: differs from 78ffa9b51 in exactly `material.morph.plain` / `light-stripes-reduce-motion` (250 values each side, 94 moved, 80 limits moved: 60 fell, 20 rose). Recomputing from the takes on disk with `noise_recompute.py` (scratch copy of the five takes, scratch case root, `--write` to the scratchpad) reproduces the committed `noise.json` **exactly, whole file equal**. (Pair folders under `noise-2b2/.../pair-*` were not rewritten.)

## Re-judged numbers (item 5)

- Plain Reduce Motion light-stripes, `20261008-050026`: 77/101/148 under the pre-wave `noise.json`, **73/101/148** under the committed one. Re-run `20261009-010310`: 79 to 73. Both reproduce.
- Dependent totals, morph + plain Reduce Motion (8 cases, rerun D for morph dark-photo, baseline `20261007-061306`): newly passing 237 to **233**, passed-in-baseline-fails-now 25 unchanged, limits raised 406 to **404** (the table's 407 is the executor's earlier figure; the wave says "404, 406 on a recount"). No lowered limit against the baseline.
- No Done item's verdict changes (item 1 still fails in part; the other items do not use the case).

## Rules (item 9)

- No code comments in any added Dart, Python or GLSL line (grep of the diff and of the added `fixwave/*.py`); the `//.*` in `glsl_function.dart` is a regex string, not a comment.
- All four commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Changed paths: `docs/liquid_glass/` (23 files), `packages/mobile/packages/ios_liquid_glass` (FORK.md, 4 test files), `packages/mobile/tool/glass_lab/noise.json`. No lockfile, pubspec or generated file; `tool/glass_lab/harness` and `scenes.json` have an empty diff, so no measure or `compare_key` change.
- No limit or measure loosened by hand; the only rises are R7.

## Items for the user

1. E8 (R4): accept the morph floors as they are (the ruling), or ask for third recordings of the four morph cases that cannot be recomputed without flagged takes. My recommendation: accept; floors computed from the flagged takes are the conservative side.
2. Nothing else needs a decision; R1 to R3 are statement fixes for the executor.

## What I did not check

- Any lab recording, frame or video content beyond ffprobe packet times for takes 1 and 5 and `take_check` on takes 1-5; the A2 take 0's two-timeline claim itself (I took the audit's finding, and the exclusion rests on it; take 5 behaves like the sound siblings).
- The NaN-versus-under-travel split of the 420 and 360 absent keys (R3), and the other 61 cases' floors (only the A2 case was recomputed; the diff shows no other case moved).
- The per-case leave-one-out ranges of the other cases (`noise-leave-one-out.txt`), the `a2-limits-moved.txt` 101 lines beyond the 20 rises and the fall list, the 64 lost measures list, and every number in `analysis-step6.md` beyond the totals above.
- The Swift scenes, shader performance, and on-device behaviour (out of scope for this wave).
