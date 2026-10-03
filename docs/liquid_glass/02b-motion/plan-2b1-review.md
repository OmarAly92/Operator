# Independent review: 2B.1 implementation plan

Plan: `/Users/omaraly/development/AI/Operator-2b1-proto/docs/liquid_glass/02b-motion/plan-2b1.md` (commit `93c021d1c` on `proto/2b1`, prototype `d6c716728`). Spec: `docs/liquid_glass/02b-motion/spec.md` (approved; identical in both trees). Reviewed 2026-10-03. Nothing in the plan or prototype was edited; nothing was committed. All scratch work is under `/private/tmp/claude-501/-Users-omaraly-development-AI-Operator/38abd04f-e943-44b9-9f3e-e74bb8d8da2e/scratchpad/review2b1/`.

## Verdict

**Not ready to execute as written. It needs one fix wave, then a short re-review.** The plan's mechanics are sound:
- Every patch applies cleanly to a fresh export of `development`, and the tree it produces is the prototype, file for file.
- The per-task test counts are correct.
- The gates reproduce.
- Every headline native number reproduces exactly from the original recordings.

The failures are in judgement:
- **The harness can pass a measure by omitting it.** An unpaired extra Flutter event, or an absent progress or spring entry, is never scored. The prototype data already contains one such dropped artefact.
- **Glass inside a scroll view inside a `GlassEffectContainer` renders at a stale position.** The probe in finding 2 shows it. No test or lab scene covers it.
- **Two rulings rest on a fitting model rather than on native evidence:**
  - ruling 10 replaces the public `.snappy` and `.bouncy` presets;
  - ruling 11 clamps visibility against native's measured 1.4–3.8% overshoot.

  Together they guarantee Done-item-4 failures and add a visible post-clamp dip.
- **The plan drops or narrows several spec items without a ruling:**
  - the stall report;
  - Material follows size;
  - container spacing animation;
  - N7 noise;
  - the Operator scenes in "still glass no worse".

Findings: **1 blocker, 11 major, 20 minor.**

## Gate re-runs (prototype worktree, `packages/mobile`, Flutter 3.44.5)

| Gate | Plan header claims | Re-run |
|---|---|---|
| app `flutter analyze` | No issues found! (10.3s) | `No issues found! (ran in 9.4s)` |
| app `flutter test` | `01:04 +2146: All tests passed!` | `01:06 +2146: All tests passed!` |
| package `flutter analyze` | No issues found! (1.4s) | `No issues found! (ran in 0.9s)` |
| package `flutter test` | `00:02 +93` | `00:02 +93: All tests passed!` |
| example `flutter analyze` | No issues found! (0.9s) | `No issues found! (ran in 0.9s)` |
| example `flutter test` | `00:01 +11` | `00:01 +11: All tests passed!` |
| harness `python3 -m unittest discover tool/glass_lab/harness/tests` | `Ran 150 tests` / `OK` | `Ran 150 tests in 15.784s` / `OK` |

The worktree was clean (`git status --short` empty) before and after.

**Drift check.** `review2b1/rebuild.py` replayed every code block of the plan onto `git archive 06d406bae packages/mobile docs/liquid_glass testdata`:
- all 45 `git apply` patches applied with exit 0;
- `diff -rq` against `git archive d6c716728` differs only in `docs/liquid_glass/02b-motion/research/proto-2b1` (not part of the plan's code);
- the plan's embedded code is therefore identical to the prototype.

**Per-task counts.** Replays stopped after each task gave:
- harness: Task 1 → `Ran 134 … OK`, Task 2 → 136, Task 3 → 146, Task 4 → 150;
- package: Task 6 → `+73`, Task 8 → `+91`.

All of these match the plan's "Expected" lines. Names and signatures are consistent across tasks: every task compiles and passes when replayed in order.

**Global constraints.** Pass, except the `simctl spawn booted` reads (finding 16):
- no comment lines were added in Dart, Swift, Python or GLSL (grep of the `06d406bae..d6c716728` diff);
- all 14 `git commit` messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`;
- every `git add` names explicit paths, so `frontend/package-lock.json` is never staged;
- no `git stash`, no whole-file `dart format`, and no `flutter build` or `xcodebuild` (builds go only through `lab.py build`);
- no `pip install`, downloads or new pubspec dependencies (`motor` and `meta` were already dependencies);
- no push;
- execution setup is correct: worktree `/Users/omaraly/development/AI/Operator-2b1`, branch `feat/ios-liquid-glass-2b1` from `development`, local Mac only.

## Numbers recomputed (my value against the plan's claim)

All numbers come from the original recordings, symlinked into scratch so nothing was written into other worktrees, and were measured with the prototype's own harness (`reproduce.py` and `shapes.py`).

| # | Quantity | Recording | Recomputed | Plan claims | Holds? |
|---|---|---|---|---|---|
| 1 | Native disappear 10–90 (120 Hz grid) | LG `20260930-082046`, 4 cases | 133 / 117 / 125 / 117 ms | 117–133 | yes, exactly |
| 2 | Native appear 10–90 (120 Hz grid) | same | 275 / 275 / 292 / 292 ms | 275–292 | yes, exactly |
| 3 | Same frames with the context brief's own method (`research/materialize_summary.py` logic, 2A harness) | same | disappear 135 / 167 / 117 / 118; appear 287 / 285 / 300 / 320 | context 117–167 / 285–320 | yes; the gap is the estimator (ruling 6) |
| 4 | Raw first-frame crossings on the plan's series (my normalisation) | same | disappear 117–135; appear 267–300 | "117–150 / 268–320" | roughly; depends on endpoints |
| 5 | Not-an-alpha-fade peak residual, with glass-absent floor | same | photo 5.12 (floor 2.67) and 5.37 (2.13); stripes 2.85 (floor nan) and 3.60 (1.72). Context method: 5.22 / 5.45 against 2.93 / 2.37 | header ruling 5: "5.05–5.37"; Task 3: 5.12–5.37 | 5.05 does not reproduce (5.12). Stripes show no alpha-fade signal |
| 6 | Half-progress sharpness against the alpha mix | same | dark-photo −1.29 / −1.08, light-photo −1.54 / −1.54; stripes −0.03 to 0.04 | 1.08–1.54 below | yes |
| 7 | v13 press | P `20261003-012138` dark-stripes | 252.0 × 88.67 → 264.0 × 93.33 (+12.00 / +4.66) | +12.00 / +4.67 | yes |
| 8 | Short-glass width growth | P `-012427`, `-012517`, `-012604` | +17.00 (58 pt circle), +16.00 (138 × 53), +14.33 / +3.00 (250 × 44) | same | yes. L1 under-reads v18's ends (finding 18); true growth about 15.0–15.5, still not 17.67 |
| 9 | `button.press` widths | 6 runs, LG and GL | 138.33 → 154.33 and 174.33 → 190.33 in every run | same | yes |
| 10 | Menu open springs | GL `20260927-024701` takes | 0.27/0.78, 0.26/0.81, 0.30/0.74 | same | yes |
| 11 | `fitvis` re-fit (`fit_all`) | prototype native `20261003-032332` | exponent 3.20 (RMS 0.0142); default 0.56/1.00, snappy 0.57/0.74, bouncy 0.55/0.50; no fit on a grid edge | same | yes, tool-fitted |
| 12 | Same curves at SwiftUI's preset constants | same | **snappy** 0.5/0.85: appear RMS 0.0123 vs fitted 0.0121. Clamped appear-only best 0.51/0.81. Own exponent 2.70 → disappear RMS 0.0138 vs fitted 0.0136. **bouncy** 0.5/0.7: appear RMS 0.029 vs 0.0123. Exponent 2.65 → disappear 0.0164 vs fitted 0.0183 | ruling 10: native differs from SwiftUI | **no** for snappy; model-dependent for bouncy (finding 3) |
| 13 | N7 topology (still), count/neck | `20261003-050837` dark-photo | default: g0 1/25.33, g4 1/4.00, g8+ apart. spacing 40: g0–g20 joined (50.67, 38.33, 40.67, 34.00, 24.67, 2.00), g24+ apart | same | yes. Stripes (`-044920`): g4@40 46.33 vs 38.33, and g20@40 reads count 1 with neck 0.00 |
| 14 | Prototype materialize pass count | `045312` + `045722` `result.json` | 106/144. By measure: events 18/18, t10_90 18/18, rms 18/18, overshoot 17/18, sharpness 11/18, settle 11/18, response 8/18, damping 5/18 | 106/144 | count yes. Description wrong: **7** settle failures **up to 158 ms** (bouncy light-photo appear), not "five pairs (25–42 ms)"; sharpness also fails on bouncy **light**-photo (1.12) |
| 15 | Reduce Motion bouncy appear overshoot | `20261003-043050` | 2.83 / 3.56 / 3.77 / 3.68 against limit 2.0: all four fail | "failed the same way as normal" | understated |
| 16 | Touch-to-response delay, native vs Flutter | `045312` / `045722` | native 45–48 ms out, 75–112 ms in; Flutter 15–50 ms; \|diff\| up to 83 ms | not reported | unjudged (finding 12) |
| 17 | Flutter frame gaps at event start | `042321` vs `045312` dark-photo | first gap 33 and 28 ms before warm-up, 17 ms after; `align.stalls` returns [] for both | about 50 ms of spring at once | a one-frame stall; the stall detector cannot see it |
| 18 | Mid-appear box, native vs Flutter | `032332` native, `045312` Flutter, dark-photo | native 218–254 × 85–96 pt at p 0.09–0.6 (+7.3 pt tall at p 0.19); Flutter 216–223 × 78–85, jumping to 249.67 wide at p 0.54 | ruling 13: native +7 pt, Flutter "crisp" | mismatch about twice as large as stated |

## Findings

### Blocker

**1. A measure can pass by being absent. An unpaired extra Flutter event is never judged.** Task 1, `shapes.py` `pairs()` (prototype `shapes.py:244-258`), `limits()` (`:348`) and `compare_progress()` (`:198`, `:218`); Task 11 `done_table.py:20`.

What happens in the code:
- `pairs()` zips native and Flutter events per step and silently drops the rest. `events.steps` only compares the *sets* of steps.
- `limits()` judges only the measures present.
- A progress entry vanishes when either side's travel is under 0.2, `t10_90_ms` when a crossing is missing, and `response_pct`/`damping` when either spring fit has RMS ≥ 0.15.
- `done_table.py` counts `passed/len(present)`.

Evidence from the prototype's own data:
- `20261003-045312/material.materialize.bouncy/light-photo/result.json` shows `event_count [2, 3]` and pairs only `step1e0, step3e0`.
- Recomputing the capture shows the third Flutter event at 20.248 s (step 3): progress 0.981 → 0.950 → 0.981 over 20.23–20.54 s, luma −1.86. This is the post-clamp undershoot of the 0.50-damped bouncy spring (finding 4).
- It is a visible artefact, and the Done table never sees it.

Fix (Task 1):
- add `events.unpaired` (events of either app not in any pair, limit 0);
- in `limits()`, emit every measure listed in `scene.motion` for every pair and shape, failing an absent one with value `inf`;
- add `touches.count` (windows read against `len(touch_steps)`, limit 0) per app;
- make `done_table.py` print "judged / expected";
- add harness tests: an extra Flutter event fails, and a missing progress entry fails.

### Major

**2. Glass inside a scroll view inside a container is drawn at a stale place. Without repaint boundaries it lags on a 0.56 s spring.** Task 8, `glass_motion_widgets.dart:65-75` (`RenderGlassMemberBox.paint` → `member.report`); `glass_motion_coordinator.dart:219-233` (`_track`).

Cause: layout changes are discovered only when the member box paints.

Probe (`review2b1/fresh/.../test/review_probe_test.dart` on the replayed tree):
- `GlassEffectContainer > ListView > GlassEffect`, `jumpTo(50)`: the layout moves to `top 34`, the drawn rect stays at `top 84`, and `isMoving false` after 100 ms. ListView's per-item `RepaintBoundary` is re-composited, not repainted.
- With `addRepaintBoundaries: false` (`review_probe2_test.dart`), the drawn top springs 84 → 68.5 after 100 ms.

`RenderLiquidGlass.drawnRect = resolve()` then draws the glass at the stale rect. This is a regression from 2A for any container that holds a scrollable. Spec M1 says the coordinator compares "on every rebuild", not on every paint. Ruling 17 only covers a container that moves as a whole.

Fix:
- compare the layout in the coordinator's tick, or when the blend group gathers geometry, not in paint;
- animate a rect change only when the glass widget, or its container subtree, rebuilt in that frame or a `withGlassAnimation` is pending; a pure scroll or re-composite jumps;
- add a Review Focus test for a scrolled list inside a container.

**3. Ruling 10's `.snappy` and `.bouncy` overrides are not native facts; they are artefacts of the fitting model.** Header line 47; Task 6 seed; `fitvis.fit_all`.

The exponent is fitted on the default scene only, then forced on `.snappy` and `.bouncy` disappear curves. On the same native curves (row 12):
- **`.snappy`.** SwiftUI's own 0.5/0.85 fits the appear curves as well as the fit does (RMS 0.0123 vs 0.0121), and the appear-only best is 0.51/0.81. All of the "difference" comes from disappear. A per-preset exponent of 2.70 with SwiftUI's spring fits disappear equally well (0.0138 vs 0.0136).
- **`.bouncy`.** The 0.50 damping exists only under the clamp model of ruling 11, which native's overshoot contradicts (finding 4). The unclamped per-case fits in `native-materialize-normal.out` give 0.39–0.48 / 0.67–0.72, i.e. SwiftUI's 0.7.
- **Default.** It "matches SwiftUI" only because stripes is excluded: the all-case fit, 0.59/0.95, is 7% off and would trip Task 11 Step 2's 5% stop rule.

Because these constants become the public presets for every glass motion, 2B.2's moves under `.bouncy` would overshoot about 16% instead of SwiftUI's 4.6%.

Fix:
- keep `GlassAnimation.snappy`/`.bouncy` at SwiftUI's (motor's) constants;
- let `fitvis` fit the *materialize mapping* per animation (disappear exponent per preset, plus an appear overshoot gain), written into `ios27_motion.dart`;
- fit over the five native takes from Task 5, not one take per case;
- record the per-take spread.

**4. Ruling 11's visibility clamp goes against native evidence, guarantees Done-item-4 failures, and creates a dip.** Header line 48; `glass_materialize.dart` `progress()` clamps the presence.

Native `.bouncy` appear overshoots:
- 1.4–2.5% normal (`native-materialize-normal.out`);
- 2.8–3.8% under Reduce Motion (`native-materialize-reduce-motion.out`).

Spec M3 allows overshoot "if native's frames show it", and they do. With the clamp:
- every Reduce Motion bouncy appear fails overshoot (2.83–3.77 > 2.0, run `043050`), plus light-photo normal;
- the 0.50-damped spring clamped at 1 undershoots afterwards, producing the unjudged dip of finding 1 and a **158 ms** settle failure (bouncy light-photo appear, `045312`).

"Clamped fits better than unclamped" (the ruling's argument) compares two models; neither of them is what native does. Fix: replace the clamp for appear with a fitted gain above 1 (native overshoot ≈ 0.4–0.8 × the spring's), fitted by `fitvis`, and keep the clamp only at 0.

**5. The Done measure's spring fit sits on its grid ceiling unreported, and is ill-conditioned.** Task 1 `shapes.compare_progress`; `springfit.py:4` (`DAMPINGS` up to 1.2); there is no `at_grid_edge` in `springfit.fit`.

Evidence:
- Flutter appear fits are 0.38/**1.20** (dark-photo default, `045312`) and 0.43/1.19 (dark-stripes, `045722`);
- the curves still match (RMS 0.014, t10_90 within 8 ms), yet `response_pct` reads 33% and `damping` 0.27, both failing.

This repeats 2A's "fit stuck at a grid bound" lesson, which the plan's lessons section says only `fitvis` handles (line 114). Fix:
- `springfit.fit` returns `at_grid_edge`;
- `compare_progress` marks the pair "fit invalid" (reported and failed, never silently passed);
- widen the damping grid to 2.0;
- harness test.

**6. The new motion path drops the stall report (spec §10).** Task 1 `analyze.py` shapes branch (`analyze.py:268-274`) sets no `native_stalls`/`flutter_stalls`. `report.py:124` reads them; the old motion branch set them (`:278-279`).

Spec §10 requires "the report lists Flutter frame gaps over 25 ms, and a run with stalls during an event is repeated". Ruling 24 then hides the one stall that motivated it with a warm-up, so nothing can show whether a stall remains in a measured event.

Also, `align.stalls` skips each event's first gap by design, so it could not have seen the first-frame stall (row 17).

Fix:
- compute `align.stalls(diffs, frames.times)` in `shapes.capture` for both apps and store it in `result.json`;
- `done_table.py` prints it;
- Task 11 repeats any case with a mid-event gap over 25 ms;
- add a first-frame check: Flutter's first changed-frame progress against native's;
- record the non-warmed first transition in `results-2b1.md` for project 5.

**7. "Still glass no worse than 2A" is checked incompletely, and its definition is quietly refined.** Task 11 Step 5 (lines 6657-6673); `still_check.py:37`.

What is missing:
- Spec §8 covers *every* 2A scene and case. Step 5 omits 2A's Operator component scenes (`tabbar.rest`, `button.press`, `navbar.inline`, `--flutter operator`; 2A runs `20261002-205000`, `-205855`, `-210140`).
- Operator builds every toolbar on `GlassEffectContainer` (`lib/core/widgets/glass/glass_scope.dart:14`). 2B.1 turns those into coordinator members, with a `RepaintBoundary` and a snapshot per `GlassEffect`, and makes inserted bar items materialize.
- Their failing measures must not get worse by more than noise.

What is refined without a ruling: `still_check` excuses any measure whose Flutter frame is byte-identical (`changed = difference is None or difference > 0`).

Fix:
- add the three Operator runs (`lab.py build operator` first) and their `still_check` lines;
- make the byte-identical exemption a numbered ruling, or drop it;
- `still_check` should report cases present in the 2A run but missing in the new one.

**8. Spec M1 bullets dropped without rulings: "Material follows size" and "Animated per container: spacing".** Task 8 `glass_effect.dart`:
- `_SizeReporter` + post-frame `setState` resolve the material from the *layout* size one frame late, exactly what M1 forbids;
- container spacing changes jump.

Fix: resolve standalone material from `member.drawn` each tick (a render-level material update), or write a ruling deferring it with the user's approval; likewise for spacing (or move it explicitly to 2B.2's M4).

**9. Ruling 16 (standalone glass never transitions) departs from spec M1 on convenience, not evidence.** Header line 56.

Both obstacles have cheap answers:
- **Telling an insertion from a first build.** A standalone `GlassEffect` first built while `pendingGlassAnimation != null` is an insertion, which is SwiftUI's own rule: transitions animate inside a transaction.
- **Where to draw the ghost.** Ghosts are already positioned globally, so they can live in the nearest `Overlay`, captured in `didChangeDependencies`.

Estimated cost is about 150–250 lines plus 3–4 tests in Task 8. As things stand, `GlassEffect(transition: materialize)`, the default, does nothing for standalone glass. Fix: implement it in 2B.1, or obtain the user's explicit approval for the deferral and add it to the to-do list.

**10. N7 has no noise floor for what it measures, and static topology limits ignore noise.** Task 5 (line 3642); `analyze.py:266`; `lab.case_noise`.

How it happens:
- static topology uses `metrics.THRESHOLDS[key]` with no noise;
- `case_noise` records only motion measures;
- the spacing scenes' `count`/`neck_pt` therefore never get a noise entry.

Spec L8 says "Every scene gets noise floors" and "Every limit is max(fixed, 1.5 × noise)", so Done item 2 is weakened without a ruling. On the stripes stills, native's g4@40 neck differs by 8 pt between backdrops, so neck noise is not negligible.

Fix:
- `case_noise` also records `ready.topology.*` (and the static measures) per case;
- `analyze` applies max(fixed, 1.5 × noise) to them;
- Task 5 Step 4 checks the spacing entries.

**11. The plan expects Done item 4 to fail and gives no path for its tunable causes. Its expectations are also misreported.** "What this plan expects" (lines 119-130); Task 11 Step 7.

The half-progress sharpness gap (Flutter blurs more mid-transition) is pre-classed as a "model limitation". Yet the plan names its fix, "a fitted blur-ramp exponent", which is a tunable (class a) that `fitvis` could fit in 2B.1: sharpness at fixed visibility against native's sharpness at matched progress.

The expectations also understate the failures:
- settle fails in 7 pairs, up to 158 ms, not "five pairs (25–42 ms)";
- sharpness fails on bouncy light-photo, not only dark photo;
- all four Reduce Motion bouncy overshoots fail (row 15).

Fix: add a `fitvis` blur-ramp fit (or a user-approved deferral), correct the expectations, and report progress measures separately from the 18 trivial `events.*` checks (88/126, not 106/144).

**12. A 30–83 ms touch-to-response mismatch is measured and then neither judged nor reported.** Ruling 8 (line 42); `shapes.best_lag` (±150 ms alignment).

Native appear starts 75–112 ms after the tap, Flutter's 15–50 ms; disappear 45–48 vs 15–17 ms (row 16). The curve RMS aligns the lag away, and `delay_ms` is not listed for the materialize scenes, although spec L5 calls delay "a measure (17 ms)".

Fix: `results-2b1.md` must report the per-pair delay and class it, and the user decides whether materialize lists `delay_ms`. Native's extra about 50 ms on appear may be real SwiftUI latency worth copying.

### Minor

**13. The evidence the header says is committed is not.** Header line 21 lists `reproduce.out`, the fit checks and the Flutter tables as committed in `research/proto-2b1/`. All seven `.out` files are ignored (`.gitignore:15: *.out`); only the JSON and three PNGs are tracked. The runs themselves live in the throwaway worktree's `build/`. Fix: rename to `.txt` and commit, or correct the claim.

**14. Ruling 5's lower bound does not reproduce.** "5.05–5.37" should be 5.12–5.37 (row 5). The ruling should also say that stripes shows no alpha-fade signal (2.85 against an unreadable floor, 3.60 vs 1.72).

**15. An early reversal bounces up.** `GlassMaterialize.reverse` divides by `e · root^(e−1)`. Removing glass 8 ms after insertion takes visibility from 0.0035 up to 0.148 before it fades (probe `quick reversal right after insertion`). Fix: cap the converted velocity, or keep continuity in presence space; add a test that visibility never rises after a removal.

**16. `xcrun simctl spawn booted …` appears at lines 82, 3666 and 6704.** With two simulators booted, `booted` can resolve to the iOS 26.5 one. Use `708879DD-8B2A-4547-863F-F49EE1474D8B` (or `sim.device()`).

**17. Stale native builds are not refused.** `build.require_fresh` only knows `example` and `operator` (`build.py:26`). `run --app native` and `repeat` never check the GlassLab sources, so the lessons line "run already does" (line 115) overstates. Add a native stamp and require it in `run`, `repeat` and `reproduce`.

**18. L1 has a blind band at backdrop edges, and gotcha 35 understates it.** The 5 × 5 edge dilation makes L1 blind within ±2 px (±0.67 pt) of a stripe boundary. At v18's peak, the rim pixels at 67.67 pt (column 65: 24 rows of dark rim) sit under a threshold of 92, and L1 starts at 68.0. So "up to a third of a point" is wrong, and the lab's own `material.press.250x44` reading (+14.33) is not independent confirmation. Fix: flag box edges inside the band, and fit 2B.3's size law on `photo`.

**19. Task 11 Step 1 has unlabelled code blocks and no tests.** Its three code blocks carry no file names (`rebuild.py` had to infer them from the Files list), and `still_check.py`/`done_table.py`, which compute Done numbers, have no unit tests. Label the blocks, and add a test pinning the spec's "worse" definition.

**20. Review Focus 4's test hides an error.** It builds 17 glasses and swallows the cap's `UnsupportedError` with `tester.takeException()` (`glass_motion_coordinator_test.dart:185`). Build 16, remove one, insert one while the ghost fades, and assert no exception throughout.

**21. Lifecycle details in Task 8:**
- `leave()` returns early without disposing the snapshot when the member is not in `_members` (`glass_motion_coordinator.dart:181`);
- reparenting a `GlobalKey` glass across containers re-materializes it from 0 (rejoin, then `_join` drop and join);
- every `deactivate`, including same-frame reparents, pays a `toImageSync`.

**22. Performance traps for M10:**
- `_tick` notifies every member every frame while anything moves;
- every `GlassEffect` now carries its own `RepaintBoundary`;
- each ghost or appearing glass is a full extra `LiquidGlassLayer`, so removing 16 at once adds 16 layers.

None of this is a 2B.1 gate, but it belongs in `todo-2b1.md`.

**23. Task 5 will run for many hours, and pair names can collide.** `case_noise` re-extracts every frame of both takes for each of the 10 pairs: 20 captures per case, about 15 s each, across about 48 motion cases, plus a partial recompute after session 1. That is roughly 5 h of analysis on top of about 3.3 h of recording. Cache one capture per take. Pair names `pair-{i}{j}` collide once there are 10 or more takes.

**24. The plan and research are not on `development`, and Task 12's patch may not apply.** The branch is cut from `development`, which holds neither the plan nor `research/proto-2b1`. Task 12's ROADMAP patch carries development's current status row as context, so it fails if the main session updates the ROADMAP when it commits the plan. Say to commit the plan first, then use `git apply --3way` (or regenerate the hunks).

**25. Task 3 Step 6 assumes the spike worktree still exists.** It copies from `Operator-2b-proto`, a throwaway worktree. Add an existence check, with a stop if it is gone.

**26. Ruling 14 (no ramp of `refractiveIndex`, `outlineWidth`, `specularWidth`) has no native evidence.** Spec M3 says native's mid-transition frames decide it. Measure the rim width and lens displacement in the `tool.visibility` stills against native mid-progress frames.

**27. Rulings 12 and 13 understate the differences:**
- under Reduce Motion, bouncy overshoot changes (1.4–2.5% → 2.8–3.8%);
- the mid-appear box mismatch is about 15 pt in height and 15–30 pt in width (row 18);
- Flutter's width jumps 223 → 250 pt in one frame at p ≈ 0.54, a visible pop to check in crops.

**28. Ruling 20's geometry-pass uniform is only checked where it cannot matter.** `uFullThickness` at float 103 is verified only at visibility 1, where `max(uFullThickness, uThickness)` hides any mis-wiring. Add a simulator still at visibility 0.3 whose rim width equals the visibility-1 rim width.

**29. Ruling 17 has a common failure case.** Adding glass beside existing glass in a centred container (`Center > GlassEffectContainer > Row`) re-centres the container, and the existing glass jumps. A cheap 2B.1 mitigation is an origin offset sprung only while a `withGlassAnimation` is pending.

**30. N7 on stripes reports a contradiction.** At g20 with `spacing: 40` it reads `count 1` with `neck 0.00`. The neck is measured on the centroid segment while the join is elsewhere. Treat count 1 with neck 0 as invalid in `track.topology` (2B.2 depends on this).

**31. Three tasks are large.** Task 1 runs to about 1,370 lines across six lab items, Task 4 to about 870 and Task 8 to about 1,200. Split Task 1 into `track`/`touch`/`shapes+manifest` for reviewable subagent runs.

**32. `withGlassAnimation` uses one global pending value** (`glass_animation.dart`). Every glass change built in the next frame takes the transaction's animation, including unrelated `setState`s, and `_pending` survives between widget tests. This is spec-sanctioned, but should be documented in the README and reset in tests.

## Rulings, one by one

| Ruling | Evidence holds? |
|---|---|
| 1 Edge-aware box | Yes for v13 and `button.press`. The blind band is larger than stated (finding 18). |
| 2 250 × 44 artefact | Conclusion holds (not 17.67), but the true value is about 15.0–15.5, not 14.33. L1's own blind band contributes (finding 18). |
| 3 menu.bar whole-region + cut | Yes, reproduced exactly. |
| 4 Teardown cut, 6-level margin | Yes. On real captures it cut only the 49-level teardown frames (bouncy light-photo native: 3 frames at 22.68 s) and nothing inside events. |
| 5 Progress, residual, sharpness | Yes except the "5.05" bound (finding 14). |
| 6 120 Hz-grid 10–90 | The explanation holds: I reproduced the context's 285–320 / 117–167 with its own method on the same frames. Native and Flutter share one estimator, so Done is not loosened. Estimators differ by up to 28 ms per case, so Done item 1 should be judged against Task 5's 10–90 noise. |
| 7 Marker rest and bare launch | Yes (tests, prototype touches). |
| 8 Events by step | The design is right; the implementation drops unpaired events (finding 1); delay goes unjudged (finding 12). |
| 9 Spring in, (1−s)^3.2 out | The exponent is tool-fitted (`fitvis`, `exponent_at_grid_edge false`, my re-fit gives 3.20). It is fitted on the default scene only; snappy and bouncy prefer about 2.7 (finding 3). |
| 10 Preset springs | **Does not hold** (finding 3). |
| 11 Visibility clamp | **Does not hold** (finding 4). |
| 12 RM keeps materialize | Timing and blur hold; overshoot differs (finding 27). |
| 13 Edge spread not built | It is a soft spreading edge. It breaks no listed Done measure, but the mismatch is larger than stated (finding 27). |
| 14 No ramp of three fields | No evidence (finding 26). |
| 15 Snapshot works | Yes: tests, plus the ghost sheet, where the label fades in place over 10 frames. |
| 16 Standalone no transitions | Departure without evidence (finding 9). |
| 17 Container space | Acceptable for 2B.1 scope, with a common jump case (finding 29); the scroll bug is separate (finding 2). |
| 18 Own layer while transitioning | Reasoned and tested; costs noted (finding 22). |
| 19 API scope | Yes; no 2B.2/2B.3 API ships dead. |
| 20 Edge light uniforms | Final pass byte-pinned; geometry pass unverified below visibility 1 (finding 28). |
| 21 Content translated | Yes. |
| 22 Per-case noise; tabbar.drag event2 removed | Yes (test). |
| 23 Topology | N7 numbers reproduce. The "merge reach ≈ half spacing" observation holds and contradicts spec M4: record it for 2B.2. Nothing in 2B.1 depends on it except the N7 gap list, which brackets both readings. |
| 24 Warm-up | Plausible debug-JIT hygiene: one dropped frame (33 ms gap) before, none after. But it removes the only measured first-transition evidence, and the stall report is gone (finding 6). |

## The author's specific points

- **Ruling 16.** See finding 9. It is a shortcut. Following the spec costs about one sub-task: transaction-based insertion detection plus an Overlay-hosted ghost.
- **Ruling 17.** Low risk for the 2B.1 lab scenes (one glass). For apps, there is a medium risk of jumps when centred containers change content (finding 29). The scroll regression (finding 2) is the real risk and is not covered by ruling 17.
- **Ruling 9.** The exponent comes from a tool run that writes the table (`fitvis --write`; the seed equals `fitvis-20261003-040423.json`, which my re-fit reproduces). It is not hand-picked.
- **Ruling 10.** One backdrop (two cases, one take each) is thin, and excluding stripes is what lets the default pass the 5% check. No fit is stuck at a grid bound; damping 1.00 is inside a grid of 0.4–1.2 and is SwiftUI's value. The snappy and bouncy overrides are model artefacts (finding 3).
- **Ruling 12.** Native evidence is the Reduce Motion run `20261003-033143`: 10–90 within a frame, and sharpness −0.89 to −1.56 on photo. It supports timing and blur, not overshoot.
- **Ruling 13.** Native mid-materialize grows the box (+7.3 pt tall) and fades its ends, and stops doing so under Reduce Motion. Skipping it breaks no listed Done-item-4 measure (none is box size), but it is a visible mismatch (finding 27).
- **Ruling 6.** The measure is not loosened, and native and Flutter are read identically (same `shapes.capture` → `event_series` → `progress_features`). The moved targets are an estimator difference, confirmed above.
- **Rulings 4 and 24.** The cut hides no real frames. The warm-up hides the first-transition stall by design, and with the stall report removed nothing would catch a remaining stall (finding 6).
- **Ruling 2.** Rechecked with a column profile: still not 17.67, but L1 under-reads (finding 18).
- **106/144 and the path to Done item 4.**

  | Remaining failure | Path in the plan |
  |---|---|
  | Sharpness | None, though it is fittable (finding 11) |
  | Spring fit | Partly a grid-ceiling artefact (finding 5); noise may cover the rest |
  | Settle | Includes a 158 ms clamp artefact (finding 4) |
  | `.bouncy` overshoot | Fails by design of ruling 11 (finding 4) |

  As written, the plan is set up to miss Done item 4. The clamp is wrong where native overshoots 1.4–3.8%.
- **Merge reach ≈ half the spacing.** Confirmed on the N7 stills. Record it for 2B.2's M4; nothing in 2B.1 depends on it.
- **"The Done table on the iOS 26.5 simulator is not run."** That sentence is not in the plan.
  - The only mention of `94D0C207-A90B-4806-BBAB-8AF9B3F16329` is the "never touch" constraint (line 74).
  - All lab tools resolve the device by name and runtime (`sim.device()`: "iPhone 17 Pro (iOS 27)", iOS-27-0).
  - The prototype's 169 driver logs contain only `708879DD…`, never `94D0C207…`.

  The sentence most likely means that the prototype never produced the spec §8 Done table: Task 5's noise floors and the full Done runs were not run there (line 121, "Task 5 has not run there"). Only the three `simctl spawn booted` reads (finding 16) could touch another booted simulator.

---

## Re-review (fix wave: prototype `9e1ec21eb`, plan `509ce7be2`, 17 tasks)

### Verdict

**Not yet ready, but close.** All 32 findings are genuinely fixed, and each fix matches the main session's ruling in `plan-2b1-fixwave.md`. I re-ran the blocker probe and the scroll probe against the new tree: both now behave correctly. The gates and the replay reproduce.

One new major problem needs a user ruling and a small fix before execution (R1). Under ruling 26, a glass rebuilt on every frame lags behind its own layout by the default spring: a `setState` drag, or an `AnimatedBuilder` that builds the glass. The same was true of the first plan; I missed it in the first review.

A second major (R2) is the expectation text, which still says the noise floors will rescue failures that my recomputation shows they do not. The remaining findings are minor.

### Gates and replay

- Prototype gates, re-run:
  - app: `No issues found! (ran in 19.1s)`, `01:04 +2146: All tests passed!`;
  - package: `No issues found! (ran in 0.9s)`, `00:03 +114: All tests passed!`;
  - example: `No issues found! (ran in 1.0s)`, `00:01 +13: All tests passed!`;
  - harness: `Ran 172 tests in 30.030s`, `OK`.

  All match the plan's claims. The worktree stayed clean.
- Full replay (`review2b1/rebuild2.py`, honouring `git apply --3way`) onto `git archive 06d406bae packages/mobile docs/liquid_glass testdata`:
  - 54 patches applied, all cleanly, with no 3-way fallback needed; 36 files written;
  - `diff -rq` against `git archive 9e1ec21eb` differs only in `plan-2b1.md` and `research/proto-2b1`. **0 code files differ.**
- Sampled per-task counts all match the plan: harness after Task 1 → 118, Task 3 → 142, Task 5 → 164; package after Task 10 → +90, Task 13 → +112, with analyze clean.

### Every original finding, checked

| # | Status | Evidence |
|---|---|---|
| 1 | Fixed | New harness on the old `045312` bouncy light-photo capture (native `032332`): `motion.events.unpaired (1, 0) False`. `expected()` and `limits()` emit every listed measure per pair and shape, an absent one as `inf`; `touches.native`/`touches.flutter` are judged. `done_table.py` prints "7 pass / 14 judged / 14 expected". Tests exist. |
| 2 | Fixed | Probe `review_probe3/4_test.dart`: after `jumpTo(50)` the drawn top equals the layout (34.00) in the same frame and every frame after (34.00 → 56.20 while the list settles), `isMoving false`, with and without repaint boundaries. A `const` glass moved by `setState` follows exactly. **But see R1.** |
| 3 | Fixed | Presets are SwiftUI's (`spring(duration: 550ms)`, `spring()`, `bounce: 0.15`, `bounce: 0.3`). `fitvis-fixwave.json` fits an exponent and gain per preset over 4 cases × 4 takes (the per-take spread is recorded, one bouncy curve excluded with RMS 0.24). `default_spring_check.pass: false` with every case failing is reported, not hidden. |
| 4 | Fixed | Appear progress is `1 + g·(s−1)` above 1; visibility extends the table's last slope; clamp only at 0. Overshoot passes 24/24 in both fix-wave runs (`113033`, `120351`). The Reduce Motion gain for bouncy is 0.62, not at an edge. |
| 5 | Fixed | `springfit.fit` returns `at_grid_edge`; `DAMPINGS` runs to 2.0; `apply_spring_fits` sets `fit_invalid` and `inf`. |
| 6 | Fixed | `native_stalls`/`flutter_stalls` are in `result.json` (empty in all 48 pairs). The first-frame check is printed by `done_table`; Task 16 Step 5 repeats a case with a gap over 25 ms or a first-frame lead over 0.2. `cold_probe.py` is recorded. |
| 7 | Fixed | Task 16 Step 7 runs and checks nine scenes, including `tabbar.rest`, `button.press` and `navbar.inline` on `--flutter operator`. `still_check` reports `missing`. The exemption is ruling 28 (sound; see below). |
| 8 | Fixed | `GlassMaterialSource` is resized at the member box's layout and on animated frames; `_SizeReporter` is gone. Spacing animation moves to 2B.2 by ruling 29, as ruled. |
| 9 | Fixed | One insertion and removal rule for all glass; ghosts in `GlassOverlayGhosts`. Tests, plus simulator probe `ghost/20261003-122124`. |
| 10 | Fixed | `case_noise` records static and still-topology measures (non-finite skipped); `analyze.limit` applies max(fixed, 1.5 × noise); Task 7 Step 4 checks the spacing entries. |
| 11 | Partly | The blur-ramp fit is a tool (`fitvis.choose_ramp`, k = 3, errors 1.14 / 0.91 / 0.84 / 0.97, not on the edge). The progress measures are counted apart from the gates. **The expectation text is wrong (R2).** |
| 12 | Fixed | Delay is reported per pair (native 18–112 ms, Flutter 12–33 ms, from `result.json`), not judged, and no delay is added. |
| 13 | Fixed | 25 evidence files tracked in `research/proto-2b1/`, the `.out` files now `.txt`. |
| 14 | Fixed | Ruling 5 reads 5.12–5.37; stripes stated. |
| 15 | Fixed | Probe: reversing 8 ms after insertion gives 0.0051 → 0.0049 → … with no rise. `reverse()` clamps the velocity sign. |
| 16 | Fixed | No `booted` left in the plan; every `simctl` names `708879DD-…`. |
| 17 | Fixed | Native stamp, required in `run` (`lab.py:101`), `repeat` (`:206`) and `reproduce.py` (see R10). |
| 18 | Partly | Flagged and gotcha corrected, **but the flag fires on every box on stripes (R4).** |
| 19 | Fixed | Every helper has a labelled "Create `path`:" step; `test_done_numbers.py` exists. |
| 20 | Fixed | The test builds 15 + leaving + arriving and asserts no exception in every frame. |
| 21 | Fixed | Deferred `LayerHandle` snapshot; `leave` releases it when the glass is not a member; the `GlobalKey` cross-container test is green. |
| 22 | Fixed | In the `todo-2b1.md` list (Task 16 Step 10 item 5). |
| 23 | Fixed | `analyze(..., cache=)`; pairs named `pair-<i>-<j>`. |
| 24 | Fixed | Execution setup step 1, plus `--3way` and blob ids. |
| 25 | Fixed | Existence loop with `MISSING … exit 1`. |
| 26 | Fixed | `rim_check.py` measures it; the result becomes open items with deciding measures (the main session's allowed option). |
| 27 | Fixed | Rulings 12 and 13 restated with the numbers. |
| 28 | Fixed | Rim check below visibility 1. Flutter's rim stays within ⅓ pt from 0.3 up, consistent with `uFullThickness` being wired. |
| 29 | Fixed | The space is the parent of the container's marker; `Center > GlassEffectContainer > Row` test. |
| 30 | Fixed | One component with no neck reads NaN. |
| 31 | Partly | Tasks are split, but Task 11 is still 1,121 lines (Tasks 3 and 5: 1,081 and 1,120) against the ruling's "about 800" (R7). |
| 32 | Fixed | README documents the global transaction; tests use `debugResetGlassAnimation` (not exported, so app tests cannot reset it: trivial). |

Known numbers recomputed with the **new** harness, from the original recordings, all unchanged:
- materialize 133/117/125/117 and 275/275/292/292 ms; residual peaks 5.12/2.85/5.37/3.60;
- v13 252.0 × 88.67 → 264.0 × 93.33;
- v18 252.0 × 44.67 → 266.33 × 47.67;
- menu 0.27/0.78, 0.26/0.81, 0.30/0.74.

### The new and rewritten rulings

- **25, blur ramp.** k = 3 is fitted by a tool: `fitvis` scans `tool.visibility` at k = 1–4, scores sharpness against native at ¼, ½ and ¾ progress, and k = 3 is not on the grid edge. It is not hand-picked. The evidence that half progress is not blur-limited (−2.69 → −2.61 across k) holds. The grid is coarse (integers) and the objective shallow (0.84 vs 0.91). The example's `VisibilityScene` re-implements the ramp formula rather than sharing it (R8).
- **26, moves only after a rebuild; scrolling never animates.** The scroll fix is verified. Its other half, "a rebuild animates", produces R1.
- **27, overlay ghosts.** Works (simulator probe, tests). A ghost draws above modal routes for up to 0.3 s. That is documented and acceptable.
- **28, the byte-identical exemption.** Sound:
  - an unchanged Flutter frame cannot carry a Flutter regression;
  - the evidence holds: 52 Flutter frames identical to 2A's, native frames 0–2 levels apart, no measure moved.

  The exemption was never actually exercised (nothing moved), and the evidence covers 4 of the 9 scenes, all recorded before the last two package fixes (R9). The executor re-runs all nine fresh in Task 16 Step 7, so this is acceptable.
- **29, spacing to 2B.2.** As ruled.
- **30, material follows the drawn size.** Implemented as ruled.
- **31, no transform read on removal.** Correct. The cost: the ghost is placed from the last cached read (R6).
- **10, presets.** As ruled. The default-spring check is honest:
  - the pooled fit is 0.57/0.98 (passes);
  - every case fails (0.45–0.74 s / 0.77–1.24, stripes carrying the lens shift; `dark-photo` 0.58/0.95 misses by 0.5%);
  - `pass: false` is reported in `results-2b1.md` and is not a stop.

  That is well handled.
- **11, overshoot gains.** Fitted per preset and per mode. The default gains are not fitted (R5).
- **14, no ramp of the three fields.** Now open items with stated deciding measures. Allowed by the ruling, and an honest description of a large visible gap (native rim 5–5.3 pt deep mid-transition under Reduce Motion, against Flutter's 0.67–1).
- **16, one insertion and removal rule.** A reasonable heuristic:
  - the parent render object is laid out (insertion) or still attached (removal);
  - tested for page, list item and parent-removal cases;
  - documented in the README.

  The `if (shown) Padding(child: GlassEffect)` case does not animate without `withGlassAnimation`. That is SwiftUI-consistent but will surprise users, and it is stated.

### The coordinator's specific points

- **The default appear gain 0.17 (and Reduce Motion 0.31) as a mean of the other presets.** Not justified (R5).
  - The measured trend is gain 0 at ζ 0.85 (`.snappy`) and 0.34 at ζ 0.7 (`.bouncy`). A spring nearer ζ 1 should take ≤ 0, not the mean.
  - The value is practically inert: `GlassMaterializeMapping.of` gives the default mapping only to springs with ζ ≥ 0.925, whose overshoot is ≤ 0.05%.
  - It should be 0, marked not identifiable, or a ruling that says it is inert.
- **`default_spring_check` pass: false.** Honest and well handled (above).
- **response 5/24 and settle 12/24: is the plan set up to fail?** Yes for Done item 4, and the noise floors will not change that (R2).
- **Do the still runs need re-running?** Yes, and the plan does make the executor re-run all nine still scenes on the final code (Task 16 Step 7). Only the prototype's quoted evidence is stale.
- **New silent departures.** None in the strict sense: every departure is now a numbered ruling. R1 is an unstated consequence of ruling 26 (and of the spec's "changes animate by default"), not an unannounced change.

### Findings still open or new

**R1, major (fix before execution; needs a user ruling). Glass rebuilt on every frame lags behind its layout by the default spring.** Ruling 26 animates any layout change "when the glass widget was rebuilt", and most `GlassEffect`s are not `const`. Probes on the replayed tree:
- `review_probe5_test.dart`: a standalone `GlassEffect` with a `Text` child, in a `Stack` and moved 15 px per frame by `setState` (the standard drag pattern): after 12 frames the layout is at x 180 and the drawn glass at 49.5.
- `review_probe3_test.dart`: an `AnimatedBuilder` whose builder returns `Padding(left: t·200, child: GlassEffect(...))`. At the end of its own 300 ms animation the layout is at 200 and the glass at 109.6, then 134.7 and 154.8 in later frames.

The content follows the glass, so the label lags too, while taps go to the layout. 2A followed exactly. This hits sliders, drag handles and anything project 3 builds on glass. The spec's "changes animate by default" did not consider continuous changes.

Fix, for the user to choose:
- (a) A change that arrives on consecutive frames is continuous: snap the offset springs to 0 and follow. Animate only a change that follows at least two quiet frames. Simple and local to `GlassMember._sync`/`sized`.
- (b) Animate moves and resizes only inside `withGlassAnimation` or under an explicit `GlassAnimationScope`, as SwiftUI does, keeping materialize animated by default.

Either way, add a Review Focus test (a `setState` drag and an `AnimatedBuilder` move follow their layout within 0.5 pt every frame), and document it in the README.

**R2, major. The expectation that Task 7's noise floors rescue the timing failures is not supported.** "What this plan expects" (line 136) says the one-frame timing failures and part of the spring-shape failures "fall inside 1.5 × noise". I applied max(fixed, 1.5 × noise) from the prototype's own `research/proto-2b1/noise-preview-3takes.json` to the fix-wave `result.json`s:

| Run | Progress passes, fixed limits | With 1.5 × noise |
|---|---|---|
| Normal (`113033`) | 112/168 | 119/168 |
| Reduce Motion (`120351`, normal-case noise as proxy) | 108/168 | 116/168 |

Normal run by measure:
- `t10_90_ms` **20 → 20**: the 25 ms failures have noise 0 or 8.3 ms in those exact pairs;
- `settle_ms` 12 → 14;
- `response_pct` 5 → 7;
- `damping` 9 → 12.

The quoted medians (17 ms, 14%) are not the per-pair noise that `limits()` uses. Large spring-shape gaps (41–61% on light appears against noise of 15–21%) are a real curve-shape mismatch, not noise.

Fix:
- correct the text with these numbers;
- class the spring-shape failures with per-pair evidence;
- consider whether the light and stripes appear-shape mismatch is a tunable of the mapping (class a) rather than (b).

**R3, minor. Float equality at the damping limit.** Four damping "failures" are exactly the limit: `0.050000000000000044 > 0.05`. One is in `113033` (`material.materialize dark-stripes step3e0`); three are in `120351`. The cause is `abs(1.06 − 1.01)` on `np.linspace` grid values. Fix: round `springfit.fit`'s response and damping to the grid step (e.g. `round(x, 4)`), or compare with a 1e-9 tolerance in `analyze.within`.

**R4, minor. `track.in_band` flags almost every box on stripes.** Its top and bottom rows span the box's full width, so any box crossing a vertical stripe boundary is flagged:
- v13 (an exact reading per ruling 1) reports `edge_in_band {'rest': True, 'max': True}`, exactly like v18;
- the flag therefore cannot separate a blinded edge from a clean one.

Fix: for the left and right edges, test the edge column's band; for the top and bottom edges, flag only when a majority of the edge row lies in the band. Add a test where v13-like geometry is not flagged.

**R5, minor. The default appear gains (0.17, 0.31) are means of other presets, not fits.** Set them to 0 with `identifiable: false` (consistent with `.snappy`'s 0 at ζ 0.85), or state in ruling 9/11 that they are inert for ζ ≥ 0.925.

**R6, minor. A ghost is placed from the last cached drawn rect, which goes stale when nothing reads it.** Probe `review_probe6_test.dart`: scroll a list inside a container by 60 px, then remove one glass. The ghost appears at the pre-scroll top 160, not on screen at 100.
- On device, the transform-tracking layer of `RenderLiquidGlass` probably refreshes the read every composite.
- Under `FakeGlass` (tests, and backends without shader filters, such as Android, which must still compile) it does not.

Fix: refresh `_live`/`_spaceOrigin` in a post-frame callback while a member is inside a scrollable, or re-read in the ghost host's paint, where transforms are valid. Add the test.

**R7, minor. Three tasks are still large.** Task 11 runs to 1,121 lines, Task 3 to 1,081 and Task 5 to 1,120, against ruling 31's "about 800". Split Task 11: container join and materialize; ghosts and snapshot; material source.

**R8, minor. The fit tool duplicates the blur-ramp formula.** `example/.../motion_scenes.dart` `VisibilityScene` re-implements `blur × v^(k−1)` from `_resolveVisibility`, so a future change to one silently skews `fitvis`. Drive the scene through `LiquidGlass.withOwnLayer(visibility: AlwaysStoppedAnimation(v))`, or share the function.

**R9, minor. The still-glass evidence is stale.** Ruling 28 and the "Done item 5: Pass in the prototype" row come from runs made before the final two package fixes, covering 4 of 9 scenes. The executor re-runs all nine (fine). For honesty, re-run `material.regular` and the three Operator scenes on `9e1ec21eb`, or reword the row as "before the final fixes".

**R10, minor. `reproduce.py` refuses to run without a fresh native build.** It only reads recordings made elsewhere, so the requirement adds a simulator build (Task 5 Step 7) for no protective value. Drop it there, and keep it in `run`/`repeat`.

---

## Final check (prototype `bba17e92a`, plan `a35735fd3`, 21 tasks, 33 rulings)

### Verdict

**Ready to execute: yes.** R1–R10 are fixed. The user's two decisions are in as rulings 32 (R1 = A) and 33 (finding 12 = A). The gates and the replay reproduce. My probes now pass, and the round introduced no regression I could find. Two minor items stay open; neither blocks execution.

### Gates (re-run in the prototype worktree; worktree clean)

All four match the claims (2146 / 121 / 13 / 175):

| | `flutter analyze` | `flutter test` |
|---|---|---|
| app | `No issues found! (ran in 20.4s)` | `01:08 +2146: All tests passed!` |
| package | `No issues found! (ran in 1.1s)` | `00:03 +121: All tests passed!` |
| example | `No issues found! (ran in 0.9s)` | `00:01 +13: All tests passed!` |

Harness: `Ran 175 tests in 30.770s` / `OK`.

### Replay onto development `6f42bb8c4`

- **Full replay** (`rebuild2.py`, `git apply --3way`) onto `git archive 6f42bb8c4 packages/mobile docs/liquid_glass testdata`: 64 patches applied, all cleanly with no 3-way fallback, and 36 files were written.
- **Diff against `git archive bba17e92a`:** only three paths differ:
  - `brainstorm.md`, which development's own new commit changed;
  - `plan-2b1.md`;
  - `research/proto-2b1`.

  **No code file differs.**
- **Sampled per-task counts** match the plan: harness after Task 4 gives `Ran 145 … OK`; the package after Task 16 gives analyze clean and `+117`.

### R1–R10

**R1. Fixed (ruling 32).** I re-ran my probes on the replayed tree (`review_probe3/5/7_test.dart`).

| Probe | Result |
|---|---|
| `setState` drag, 15 pt a frame, standalone glass with a `Text` | layout/drawn `15/0.0`, then `30/30.0`, `45/45.0` … `180/180.0` |
| `AnimatedBuilder` move inside a container | `10.7/0.0` in the first moving frame, then exact; worst difference from the second moving frame on is 0.0 pt |
| Drag that pauses 120 ms, then resumes | holds one step again (`75/60.0`), then exact |
| 60 ms jank frame mid-drag | holds that frame (`60/45.0`), then exact |
| Single change after a quiet second | still springs (`205/105.0`, then 136.6 at +100 ms, `isMoving true`) |
| `withGlassAnimation(none)` | still jumps |

The author's claim holds: the first moving frame holds one step behind, and every later frame is within 0.5 pt (0.0 measured).

**Is the one-frame hold acceptable? Yes.** The lag is one frame (8–17 ms) at the start of a motion, and again after a pause or jank over 50 ms. It is then exact, with the content moving with the glass and taps going to the layout. That is in line with Flutter's own input-to-frame latency, and ruling 32 states it, along with its other cost: a second discrete change on the very next frame drops the first change's one-frame-old spring. The 50 ms `followGap` is a hand-set heuristic constant, not a fitted value. It covers 30–120 Hz frame rates.

**R2. Fixed.** The expectations now quote my recomputation, plus R3's slack: 120/168 normal and 119/168 Reduce Motion. They say plainly that Done item 4 stays partly failing, and they class each cause:
- spring shape and the one-to-three-frame timing: (b), with per-pair noise cited;
- `.bouncy` light settle: (a), with a to-do measure;
- half-progress sharpness: (b).

**R3. Fixed.** `analyze.within` now carries `FLOAT_SLACK = 1e-9`, with a test, so the four ties at exactly 0.05 now count.

**R4. Fixed.** `in_band` flags an edge only when more than half of it lies in the band. v13 is no longer flagged; v18 is still flagged at its peak. Tested.

**R5. Fixed.** The default appear gains are now 0.0, normal and Reduce Motion. They are written by `fitvis --write`, which marks them `INERT` and `identifiable: false`.

**R6. Fixed.** In `review_probe6_test.dart` (scroll 60 px, then remove the glass), the ghost now lands at top 100, on screen, instead of the stale 160. The fix adds the scroll since the last read.

**R7. Mostly fixed.** The plan now has 21 tasks, and the lab and coordinator work is split. But Task 11 (render hooks, 1,010 lines) and Task 12 (mapping and coordinator, 1,027 lines) are still over the ruling's ~800. This is left open as minor.

**R8. Fixed.** `LiquidGlassSettings.atVisibility(v, blurRampExponent:)` is the single formula, used by the renderer and by the example's `tool.visibility`; there is a test.

**R9. Fixed.** The still check was re-run on the final code (`20261003-210710`, `-212057`, `-213008`, `-213813`; `still-check-*.txt` committed). All 52 Flutter frames are byte-identical, with `missing: 0` and `worse: 0`.

**R10. Fixed.** `reproduce.py` no longer requires a native build; `run` and `repeat` keep the stamp.

### New silent departures and regressions

**Regressions.** None found:
- the earlier probes still pass on the final tree: scroll in a container follows exactly with and without repaint boundaries, an early reversal never rises, and a `const` glass dragged by `setState` follows exactly;
- the Review Focus re-centring test is green.

**Open items (minor):**
1. `LiquidGlassSettings.atVisibility` is **new public API** on an exported upstream class.
   - It is documented in the README, CHANGELOG and FORK, but no numbered ruling covers it.
   - Spec M9 fixes public names once and for all.
   - Fix: add a one-line ruling, or make the method `@internal` and let the example reach it another way.
2. Tasks 11 and 12 are still about 1,000 lines each (R7).

Neither blocks execution.
