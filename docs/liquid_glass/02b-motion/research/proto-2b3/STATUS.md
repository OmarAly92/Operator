# 2B.3 prototype status

Worktree `/Users/omaraly/development/AI/Operator-2b3-proto`, branch `proto/2b3` from `development` `c0e69d9a4`.

## Steps
- [x] 0. Worktree created, `flutter pub get --offline` OK. Free disk 192 GB.
- [x] Reading list: ROADMAP, spec, brainstorm, spike, todo-2b1/2b2, results heads, plan-2b2 header, review titles.
- [x] 1. L4 measures: `harness/press.py` + tests (commit d65ef3a94). `reproduce.py glow` on N1/N2/spike: drop 400-423 ms after a 1.0 s press, luma +17.7 dark-stripes, +19.0 light-photo, +12/+4.33 growth (output in /tmp task b7nbzv4hs; rerun: `python3 tool/glass_lab/harness/reproduce.py glow`).
- [x] 2. Native questions recorded 2026-10-09 05:55-06:02 (fresh boot; first takes under CPU load from my analysis: press 0.607 s; re-recorded interactive 060244 press 0.928 PASS). Results `native-questions.txt/json`: fast drag no stretch, no move; drag 40 pt out: no release when finger leaves (glass stays grown to touch-up), centre +1.33 pt toward finger, ratio +0.012 (one take); neighbours 0/10/40: no glow, no scale on the neighbour (its far edge fixed); content (label) scales with the glass (content_scale.py on v17/v18).
- [x] 3. RM press: glow same (peak 19.6), no growth, cut 558-570 ms after release (normal 415).
- [x] 4. Press in Flutter (commits 79a98c82b, a406f87bf): pressfit (561fa5788, d25abfb74) writes ios27_press.dart from native-press.json + glow-profile.json; inverse law kept by held-out sizes (0.81 vs 1.29). Flutter vs native dark photo: flutter-press-2.txt (runs 20261009-063647/-063817/-063941).
- [x] 5. Pointer target in the shape, innermost only, scroll releases by offset change, press survives appear settle (GlobalKey); container glow layer NOT built (native shows no spread). glass_press_test 11 tests.
- [x] 6. perf-1.json: material 13.41, motion 14.50 (+8.1%), slide 15.16 (+13.0%) ms raster median, 4 alternating takes; frames per take 360 / 245 / 202.
- [x] 7. Plan templates in plan/ (tasks.py, template-a/b/0/d, assemble.sh); plan-2b3.md assembled (16 patches, 30 runs).
- [x] 8. Replay on fresh export (3 runs; replay-3: 16 patches, 30 runs, 0 problems; 31/31 files cmp-identical): clone `--depth 1 -b development` at /Users/omaraly/development/AI/Operator-2b3-replay (not a worktree), research/proto-2b3 committed there; replay-1 running (log plan/replay/replay-1.log).

## Notes
- Plan tooling to reuse: `research/proto-2b2/plan/{build_plan,replay,gen_tasks,tasks}.py`.
- Gates at development: app 2189, package 261, example 25, harness 253.

- Do not analyse while recording: CPU load squeezed a press to 0.607 s.
- Glow model: H (uniform ~11.5 luma, cut in one frame) + D (radial, decays tau~110 ms after ~65 ms hold). Cut time 380-665 ms, cause not known.
- Operator swap done (2e0e1d756), app tests 2187. LiquidStretch RM (6ca995a88). README (6388dc790). Manifest motion (77866e090).
- Gates now: package 273, example 25, app 2187, harness 272 (+test_scenes changes).
- noise recompute probe (250x44 from archive takes): old values unchanged, +11 press noises per case (noise-recompute-probe.txt); noise.json restored.

## Fix round (review plan-2b3-review.md, F1-F21; coordinator rulings; D9 decided A by the user)
- [x] Hole rule: takecheck.py; literal "any gap <5 ms" flags all 24 N1/N2 (release cadence 3.3/13.3) -> calibrated: two consecutive gaps <4.5 ms, or squeezed first frame after touch-down (hole-rule-check.txt: N1/N2 21/24 clean, question takes 0/9, 2B.1 noise 17/30).
- [x] run/repeat scripted check, leverage stop, noise-sources.json (lab.py, analyze.py, test_takecheck.py).
- [x] press: glow_level, glow_half_ms, NaN times on holes, pinned rects (neighbours).
- [x] scenes: drag.far (+300 down), drag.up (-150), press.circle44, press.capsule36; neighbour bands.
- [x] native answers 2: no release at 40/106/256 pt; lean toward finger (stretch to -0.035, centre to 1.67); RM cut 564 from 6 clean presses; native-questions-2.txt.
- [x] pressfit: plateau law (power 1.22 chosen held-out 0.636 vs 0.685), masked sigma 77, cut per size, all backdrops, grid widened, problems guards; table written.
- [x] light colour test: light-blend.txt (stripes channel-dependent; screen form fails) -> D10.
- [x] package: cut per size, debugGlassPress, F19 tests (+5), F20 mirror test (clean, D1 A).
- [x] Operator tests restored with debugGlassPress (12 tests).
- [x] Flutter vs archived N1/N2 all cases: flutter-compare.txt (304/440 fixed thresholds).
- [x] development still reference (Operator-2b3-dev run 20261009-101012 vs proto 20261009-101613: missing 0, worse 0, byte-identical); clean circle44 native 20261009-103129 (held out: size passes, light 10.4 dimmer, cut 750 vs 632.5); README; scenes photo-only; code c11d57268; plan rebuilt (18 patches, 36 runs); replay-4/-5 0 problems, 38/38 files cmp-identical.
- Keep: Operator-2b3-proto (runs), Operator-2b3-dev (F14 reference run), Operator-2b3-replay (scratch).
- Hole rate ~2 h after the 08:38 boot: run 20261009-101613 (material.interactive both apps) 14 holed attempts for 8 kept takes, one press squeezed to 0.132 s.

## Fix round 2 (re-review rereview-2b3.md, R1-R10)
- [x] R1 span rule (takecheck.span_holes): squeezed first frame; burst (two gaps <4.5 ms) from touch-down to next touch or up+1.2 s; lost frames = gap >30 ms with motion before and after, for native only within 100 ms after down / 200 ms after up (native's 60 Hz windows; gap_phases.py / gap-phases.txt: 56 native takes, first gap >30 ms >=103.3 ms after down, >=238.3 ms after up; 87 of 88 moving gaps 33.3-56.7 ms at 103-265 ms after down), for Flutter span-wide at take level. A literal 30 ms rule fails 43 of 56 native takes. press.features applies the windows to rows for both apps (Flutter post-cut glow flicker 0.3 luma). hole-rule-check.txt: N1/N2 20/24, excluded dark-photo PASS / dark-stripes FAIL, noise 18/30 (all squeezed), first-round Flutter 19/24, questions 5/8, RM 6/6.
- [x] R8 glow-profile.json = median of the six clean RM takes (profile CLI reads holds from native-questions-2.json); sigma 77, RMS 1.59.
- [x] R5 light-blend.txt: leave-one-take-out RMS vivid 6.14, additive 9.51, screen 12.45.
- [x] R4 law on all 13 plateaus: inverse min(15.84, 9.7 x 100/h), held-out 0.781 vs free 1.149 (power 1.28): gain -0.368 < 1/3. Table rewritten (springs 21 clean takes). README numbers.
- [x] R9 quiet tests; R10 README documents debugGlassPress as tests-only.
- [x] Recording 12:13-12:47 (34 min) after reboot: native interactive check (3 holed attempts), native 250x150 121639 clean, Flutter 250x150 121734, Flutter all six sizes x4 (121858, 122339, 122743, 123308, 123752, 124153) and circle44 124556 with the refitted table: 46 attempts, 19 holed (all kept Flutter takes clean).
- [x] Code 9adddc6b5 (then press rows: windows only for both apps).
- [x] R2 forecasts: in-sample 305/441 (414 finite, 24 cases; six shared cases 93/125); independent 276/380 over 18 clean noise takes (73 %). Held out: 44x44 11/15 (growth within 0.33 pt, light 10.3 dimmer, cut 83 ms early); 250x150 11/15 with growth failing (Flutter 7.0 x 5.33 vs native 5.33 x 3.33: the inverse law over-grows tall glass; D11).
- [x] Plan: D6 explicit departure + Task 14b (option B), D10 reworded, D11 added, R3 Task 13 Step 2b, R7 drag.out Reduce Motion in Tasks 12/13/15, 250x150 in Tasks 12-15. Code 65dbeba40 (README API row). Replay 6 recorded outputs (8 count problems), replay 7: 18 patches, 36 runs, 0 problems; 38/38 package files cmp-identical.
- Simulator this round: 12:13-12:47 (0.6 h) plus the replays' native build.

## Fix round 3 (rereview2-2b3.md, S1-S6)
- [x] S1 native lost-frame test from touch-down to +90 ms and from touch-up to the span end; in the hold only gaps over 60 ms (20 Hz cap). Rows: motion over 0.5 luma or 0.5 pt (jitter). Gap of exactly 30.0 ms on the 1/600 s clock not over the limit. Tests added. hole-rule-check: N1/N2 20/24, excluded dark-photo PASS / dark-stripes FAIL, noise 17/30 (12 squeezed + dark-photo/3 118.3 ms in the drag hold), questions 6/8, RM 6/6.
- [x] S5 onset window 90 ms (drag.far 084517 had a 20 Hz gap at 96 ms); Task 12 reports the onset-flag rate.
- [x] S2 law: form must keep every measured height within 1 pt, then leave-one-size-out. 250x150 fitted (14 plateaus): min(15.84, 9.69 (100/h)^1.31), residuals 44..200: -0.33 +0.51 -0.16 +0.12 -0.54 +0.36 +0.24. Held out 300x250 (native 20261013-084022, Flutter -084127): native 4.0 pt vs law 2.92 (-1.08); 8/15. Growth not a function of height alone (300x250 grows more than 360x200): D12. 44x44 10/15.
- [x] Recording 2026-10-13 08:40-09:20 (0.67 h, two boots): 52 attempts, 27 holed.
- [x] Forecast: in-sample 314/456 (25 cases), independent 239/350 over 17 pairs (68 %), six shared cases in-sample 88/125.
- [x] S3 shrink_ms class (a): native release time by size (323-335 ms circles to 132 ms at 300x250), one spring in the package; not the 2/3 pt band (shrink_check.py).
- [x] S4 Task 14b marked NOT TO RUN (D6 A). S6 limit stated.
- Gates: harness 314, package 280, example 25, app 2188. Code a16e1e926, 29a4de8c4.
- [x] Plan regenerated; replay-8 recorded outputs (5 count problems), replay-9: 18 patches, 36 runs, 0 problems; 38/38 package files cmp-identical.

## Fix round 4 (D12 = A: growth in width and height)
- [x] pressfit forms height / area / height_width (q -1..1, includes 1 + c/(wh)^p), coarse-to-fine grid; select within 1 pt at every size, then leave-one-size-out; separated flag. 15 plateaus, 8 sizes (250x150, 300x250 in). Chosen height: min(15.84, 9.73 (100/h)^1.24); residuals 58x58 -0.16, 138x53 +0.51, 250x44 -0.33, 250x88 +0.07, 300x120 -0.41, 250x150 +0.55, 360x200 +0.45, 300x250 -0.88. height_width q=-0.10 also within, not separated (LOSO 0.789 vs 0.698); area fails 250x150 (+1.66).
- [x] Held out 120x250 portrait (native 20261014-164610, Flutter -164826): native settles 4.67 x 8.0, law 3.12 width (-1.55), 6/16 -> D13. 44x44 10/15.
- [x] Recording 2026-10-14 16:46-17:22 (0.6 h): 47 attempts, 22 holed; 4 stripes Flutter cases kept holed.
- [x] Forecast: in-sample 318/469 (26 cases), independent 246/347 (71 %), six shared cases in-sample 92/124.
- [x] Ruling 16 gives the reasons for the 0.5 luma/pt row thresholds and the 30.0 ms rounding.
- Gates: harness 314, package 280, example 25, app 2188. Code aa8c06456.
- [x] Plan regenerated; replay-10 recorded outputs (1 line-number problem), replay-11: 18 patches, 36 runs, 0 problems; 38/38 package files cmp-identical.

## D13 = A (user, 2026-10-14)
- [x] Ship the current law; Task 14 refits on fresh data and STOPS (writes nothing) if no form keeps every size within 1 pt; test test_a_refit_where_no_form_keeps_every_size_within_the_threshold_writes_nothing. Known misses (120x250 -1.55, 300x250 -0.88) declared in forecast and README. Code 87b88ab02. Replay-12 recorded (2 count problems), replay-13: 18 patches, 36 runs, 0 problems; 38/38 files identical. Gates: harness 315, package 280, example 25, app 2188.

## Re-review 3 text fixes (T1-T5)
- [x] Task 14 Step 2 and Review Focus 5 describe the 1 pt rule, leave-one-size-out, the stop rule and the current grid; stale test name removed. Disk: about 55 GB measured 2026-10-14, 40 GB stop, Task 13 Step 1b may remove only analysis caches of this execution's analysed takes. 13 of 30. D9 run id. Rows do not see some take-check holes: Done counts a case failing capture.<app> as failing (Task 15 Step 2 script).
- [x] Replay-14: 18 patches, 36 runs, 0 problems; 38/38 identical; gates harness 315, package 280, example 25, app 2188.
