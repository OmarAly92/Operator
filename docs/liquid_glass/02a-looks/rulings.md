# 2A execution rulings

Every line starting `Ruling:` from `.superpowers/sdd/plan/progress.md`, verbatim, in order, grouped by where in the plan it was made. The plan's 15 header rulings live in `docs/liquid_glass/02a-looks/plan.md`'s header; these are the controller rulings made while executing it.

## Pre-flight

- Ruling: C1 (T10 Step 6 expects toneWhite 0.85→0.6, 17.85→9.08, but the T4 seed already holds the tuned 0.57) — run Step 6 exactly as written; the pass condition becomes best_score <= start_score, actual numbers recorded — the seed is the prototype's tune result, so the loop cannot improve much — cost if wrong: Step 6 proves less about the search improving a score; Task 10's unit tests on a fake evaluator still pin descent.

- Ruling: C2 (T6 default style automatic changes Operator's bottom edges, home_shell.dart:147, blocks_body.dart:424) — accept; spec B5 makes automatic the default and spec A6 says Operator's look changes by design to iOS 27; Task 13 adds a ROADMAP note that Operator bottom edges use the top-tuned automatic row until project 3/4 tunes a bottom edge — cost if wrong: Operator's bottom fades look different (hard band, light-mode divider line) until then; the revert is passing an explicit style at two call sites.

- Ruling: C3 (spec B6 fits Reduce Transparency on material.tinted too; rowFor picks a11y rows with tintAmount 0 so tinted glass loses its tint under RT/IC) — Task 4 adds: when resolve picks reduceTransparency or increaseContrast and glass has a tint, tintAmount, tintBlack and tintWhite come from the same appearance's tinted row at the same anchors (table untouched), with one test; Task 12 additionally measures material.tinted --a11y reduce-transparency (both appearances) and reports it in results.md as an extra row (not a Done criterion); no separate tint tune under RT because the RT row is shared with regular — cost if wrong: a small deviation from prototype-proven resolve code; revert is one branch in resolve.

- Ruling: C4 (Review Focus 4 claims GlassMaterialOverride's non-debug path is pinned; no test exists) — no test added: kDebugMode is a compile-time const, so the release path cannot be exercised by flutter test without a production seam; the one-line guard is checked by review, and Task 7's launch-file deletion test pins the stale-launch half — cost if wrong: a regression of the guard would go unnoticed in tests (it would only matter in release builds with a debug-only launch file).

- Ruling: C5 (Task 12 Step 4 relaxes Done 6 to "halved or already within threshold") — follow the plan; the user's handoff names the plan's Done-item-6 ruling as a criterion — cost if wrong: an Operator scene already inside threshold passes without halving.

- Ruling: C6-C8 (pubspec description suffix and `library;`, API shape details beyond ruling 10, harness names flutter_example→example / both→all / --variant→--row) — follow the plan; the user approved the plan with these and the prototype proved them — cost if wrong: renames later, before the API is used outside Operator.

- Ruling: C9 (spec B8 wants a native-vs-Flutter filmstrip of material.flip) — Task 9 includes the native filmstrip the flip analysis produces; there is no Flutter flip scene because ruling 5 builds no flip, so the doc says so — cost if wrong: the doc lacks a side-by-side the user may want.

- Ruling: C10 (Task 11 group commits list no git add) — each group commit stages docs/liquid_glass/02a-looks/tuning-log.md and the package's lib/src/material/ios27*.dart explicitly — cost if wrong: none.

- Ruling: C11 (summary-material.md not in Task 12 Files list) — commit it, as Step 6's git add does — cost if wrong: none.

- Ruling: C12 (Task 13 Step 8 grep drops build/.dart_tool exclusions) — use Task 1 Step 7's exclusions — cost if wrong: none.

- Ruling: plan-mandated defect 1 (GlassEffect and GlassEffectContainer repeat the resolve block verbatim) — Task 4 extracts it into one shared helper used by both — cost if wrong: small deviation from prototype code; behaviour identical, tests pin it.

- Ruling: plan-mandated defect 2 (tune.WEIGHTS restates metrics.THRESHOLDS; Task 12 LIMITS restates two) — Task 10 derives WEIGHTS from metrics.THRESHOLDS where keys match; Task 12 imports metrics.THRESHOLDS instead of LIMITS — cost if wrong: none if tests stay green.

- Ruling: plan-mandated defect 3 (Toggle/Merge/Split lab buttons have no onTap) — keep; spec A5 says motion scenes render statically in 2A and 2B wires the motion — cost if wrong: settled.png of those motion scenes compares against a native that animated; they are not Done criteria.

- Ruling: plan-mandated defect 4 (GlassLabLaunch.current never read; fillRatio unread) — Task 7 removes GlassLabLaunch.current if nothing reads it; fillRatio stays (upstream public API of LiquidGlassSettings, kept per spec's keep-the-renderer decision) — cost if wrong: none.

- Ruling: plan-mandated defect 6 (new tests use retired lift/gain names) — Tasks 7 and 10 use toneBlack/toneWhite as sample keys instead — cost if wrong: none.

- Ruling: plan-mandated defect 7 (weak manifest assertTrue) — Task 7 asserts the specific "measures" error text — cost if wrong: none.

- Ruling: plan-mandated defects 8-10 (repeated test tree in scroll_edge_effect_test, fallback ignores knee/cap/line, _scheduleMeasure in build carried from Operator) — keep as the plan wrote them; they are carried-over or test-only style, not behaviour a Done item depends on — cost if wrong: minor cleanup later.


## Task 4

- Ruling: Task 4 implementer on the standard tier (sonnet), not the cheapest — the C3 resolve change and the shared-resolve-helper extraction are small design edits, not transcription — cost if wrong: some extra spend.

- Ruling: shared resolve helper lives in a new non-exported file lib/src/api/glass_material_context.dart as `GlassMaterial resolveGlassMaterial(BuildContext context, {required Glass glass, required double shorterSide})`, used by GlassEffect and GlassEffectContainer — keeps lib/src/material free of widget-layer imports — cost if wrong: one file to move.


## Task 9

- Ruling: Task 9 frame-cost A/B gets a third take — after restoring the new renderer and rebuilding (the brief's last step), run perf again to build/glass_lab/perf-new-2.json and report new/old/new — ROADMAP gotcha 16 and the user's memory say A/B order must alternate; the plan measured new then old only — cost if wrong: ~5 extra simulator minutes.

- Ruling: amended Task 9's local, unpushed HEAD commit instead of adding a fix commit — it fixed that commit's own trailer, which a follow-up commit cannot do — cost if wrong: none (no one else had the SHA).


## Task 11

- Ruling: Task 11 "misses its threshold" rule is applied per step, judged only on the measures that step's parameters govern (tone steps: mad+luminance; lens/rim-light: rim; shadow: centre+box; size steps and Increase Contrast: all; edge: mad+luminance); A1/B1 get no narrowed rerun because A5/B5 re-run them; "± 2" means ± 2 old grid steps, clamped — the plan does not say which measures a partial-parameter step answers for, and judging A1 on rim would force pointless reruns — cost if wrong: a step whose params could have helped another measure gets no retry; Task 12 still reports every failure. Details: task-11-controller-notes.md.

- Ruling: Task 11 groups run on the standard tier (sonnet), one group per dispatch, per the user's handoff.

- Ruling: fix the harness so each tune candidate sends the whole current table row (edge rows with the edge. prefix) merged with the candidate as overrides; one focused test; then Group A redoes A2-A7 on the fixed tool. A1 stands (its base was the compiled seed, which equalled the table). Task 12 must rebuild example and operator before its runs so the compiled tables are the tuned ones — the plan says tuning never needs a rebuild because it assumed runtime reads — cost if wrong: ~4 h of redone simulator time; the alternative (rebuild after each step) costs ~2 h of builds and still needs discipline per step.

- Ruling: Group B's unclamped narrowed reruns for toneWhite/toneMid in B6/B7 (the copy_row seed lay outside those steps' grids) stand — clamping to a range that excludes the start would have made the rerun meaningless — cost if wrong: two reruns searched slightly outside the brief's ranges; values still came from --write runs.

- Ruling: narrowed-rerun grids stay inside each parameter's physical range (no negative amounts/widths/blurs, tone 0..1.5) — my earlier unclamped-rerun ruling let dark.tinted.44 get specular -0.1; that row is left as measured (a 0.1 difference on the 44 'Run' anchor) rather than spending another run — cost if wrong: dark tinted 44 rim slightly darkened; Task 12 measures it.

- Ruling: fix tune.py to clamp every candidate it sends/writes (start, grid, refinement) to a per-field physical range table, with a test; then rerun Group E Increase Contrast step 2 for light (brief params, but toneBlack=0.4:0.9:6 and adding toneMid=0.4:1:7) and for dark (brief params plus toneMid=0.3:0.8:6), with narrowed reruns and copy_rows, and correct the log — measurement shows the brief's grid cannot reach native's IC fill; spec Done item 5 makes IC a pass criterion; the score cap stays (spec §6) — cost if wrong: ~4 h simulator time and a grid that deviates from the brief, recorded in the log.

- Ruling: out-of-range values inherited from earlier groups (e.g. dark.regular.88 hairlineLight 1.0508, dark.increaseContrast hairline 1.2 if the rerun keeps it) are left as measured unless a rerun rewrites them; the clamp prevents new ones — cost if wrong: tiny hairline saturation differences.


## Task 12

- Ruling: fix the Operator lab screen to also provide GlassTheme with the lab's brightness (accent and scrollEdgeTint from the lab skin), add a widget test, rebuild operator, rerun Task 12 Step 4 (tabbar.rest, button.press, navbar.inline, both appearances), and update results.md's Done-6 section and row — this is a lab-only defect (the real app's glass follows the user's chosen skin, which is its intended behaviour); cost if wrong: ~1 h.


## Final review

- Ruling: final fix wave fixes Important 1, 2, 4 (docs), 5, 6 (code+tests) and the minors: results.md IC misstatements and stale README note, `tune --flutter operator` errors out, accessibility switched inside try in cmd_tune and run_cases, FORK fillRatio text, document Glass.clear.tint (untinted) and GlassEffectContainer.side; podspec homepage and accent dartdoc left (no known package repo URL; no-comments rule) — cheap, and 2B builds on 5 and 6 — cost if wrong: none material.

- Ruling: Important 3 (tinted scene 2 pt offset, retune D2/D3) is recorded as a ROADMAP open item for the first 2B lab session instead of re-measuring now — it needs a scene re-geometry, rebuild and ~3 h of tuning plus re-verification, beyond one fix wave; results.md already names the offset — cost if wrong: tinted rows (and dark.tinted.44 specular −0.1) stay fitted to a misaligned scene until then.

- Ruling: the rulings are copied into tracked docs/liquid_glass/02a-looks/rulings.md so they survive the gitignored workspace's deletion.


