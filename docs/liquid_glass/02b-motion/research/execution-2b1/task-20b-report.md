# Task 20b report: BLOCKED (stop conditions hold; table not committed)

Commands (from packages/mobile): lab.py build example; lab.py fitvis runs/20261004-000223 runs/20261004-001040 runs/noise-2b1 --write (exit 0).
fitvis folder: /Users/omaraly/development/AI/Operator-2b1/packages/mobile/build/glass_lab/fitvis/20261005-211745 (fit.json copied to task-20b-fit.json).
recordings() reads only <root>/<scene>/* and <root>/takes/<scene>/*/*; noise-2b1/excluded not read; no video.mp4 at noise-2b1 top level.
ios27_motion.dart restored with git checkout; no commit.

## Stop conditions
1. Take exponent outside seed +-0.5: default per_take noise-2b1/take5 = 3.65 (pooled 3.1; +0.55). HOLDS. (take3 2.9, take4 3.2.)
2. Take gain outside +-0.3: bouncy reduce_motion_gain per_take noise-2b1/take3 = 0.0 and noise-2b1/take5 = 1.24 (pooled 0.62). HOLDS.
3. Grid edge: none (all at_grid_edge false). OK.
4. excluded: bouncy exponent one curve (noise-2b1/take0 dark-stripes, rms 0.4672); others none. OK (<=1 per scene).

## Guard
default: exponent 3.1; gain INERT (identifiable false), RM gain INERT. snappy: exp 2.65, gain 0 at_floor, RM gain 0 at_floor. bouncy: exp 2.8, gain 0.36, RM gain 0.62. No nulls, all presets present. Guard passes, but stop conditions 1 and 2 block.

## Other expectations
- mapping default 3.1 (pass); snappy 2.65 (within 2.7+-0.15), gain 0 at_floor (pass); bouncy 2.8 (2.75+-0.15 pass), gain 0.36 (pass).
- Per-take spreads (normal): default 2.9-3.65 (deviation, take5 and take3/take4 beyond +-0.1); snappy 2.65-2.75 (pass); bouncy exp 2.7-2.95 (take0 2.95 is +0.15 vs 2.8, deviation vs +-0.1), gain 0.32-0.42 (pass, within 0.06 of 0.36 except take0 0.42 = +0.06 edge).
- reduce_motion_gain: bouncy 0.62 pass; snappy 0 at_floor pass; default 0 identifiable false pass. Bouncy per-take: 0.64,0.64,0.64,0.64(take1..),0.58,1.24 (take5), 0.0 (take3): deviation.
- default_spring_check: pooled 0.58 / 0.99, pass FALSE (brief expected pass true). Per case: dark-photo 0.59/0.98, dark-stripes 0.71/0.80, light-photo 0.50/1.14, light-stripes 0.44/1.30 (all pass false; light-stripes response 0.44 just under 0.45). Not a stop per ruling 10, but pooled pass differs from the prototype.
- blur_ramp 3.0, errors 1.14, 0.92, 0.84, 0.97 (pass, not on edge).
- visibility_for_progress starts 0, 0.0651, 0.1297, ... 1.0 (21 entries); Flutter mean progress at visibility 0.5 = 0.4223 (pass, about 0.42).

Gate not run (no table to commit).
Likely cause for review: the take numbering suggests default has a take5 and bouncy RM has take3/take5 outliers; these look like capture outliers in noise-2b1/takes (default dark/light cases), worth the controller inspecting those takes.

## Round 2 (controller ruling)
Confirmed: fitvis.py by_take (lines 166-169) groups by curve["take"], set at line 68 as "<root>/take<N>", ignoring the case; so replacement takes numbered 5 formed single-case groups.
Renamed take 5 -> 3 in noise-2b1/takes for material.materialize/light-stripes and material.materialize.bouncy/{dark-photo,dark-stripes}-reduce-motion; README line appended. Reran fitvis with --out on the same folder (about 38 min).
Result (fit.json copied to task-20b-fit.json): all stop conditions clear.
- default exp 3.1, per take 3.1-3.2; gain INERT (not identifiable) both modes.
- snappy exp 2.65 (takes 2.65-2.75), gain 0 at_floor, RM gain 0 at_floor.
- bouncy exp 2.8 (takes 2.7-2.95, one excluded curve take0 dark-stripes), gain 0.36 (takes 0.32-0.42), RM gain 0.62 (takes 0.58-0.64).
- no at_grid_edge anywhere; blur_ramp 3.0, errors 1.14/0.92/0.84/0.97; mean progress at 0.5 = 0.4223; visibility_for_progress unchanged.
- default_spring_check: pooled 0.58/0.99 pass false (ruling 10, report in results-2b1.md); cases 0.59/0.98, 0.71/0.80, 0.50/1.14, 0.44/1.30 all false.
- Guard passes.
Table diff: snappy exponent 2.7 -> 2.65; bouncy exponent 2.75 -> 2.8; bouncy gain 0.34 -> 0.36 (nothing else).
Gate: flutter analyze "No issues found!"; flutter test "+122: All tests passed!". lab.py build example rebuilt.
