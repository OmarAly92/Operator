# Task 8 report

Status: DONE (commit bea4bdb2b). Step 7 has deviations (below).

## Implementation
Test file extracted mechanically from the brief; both patches applied cleanly with `git apply --3way` (MaterialScenes.swift, scenes.json, 79 scenes).

## TDD
Before implementation: 4 tests, failures=2 errors=1 (KeyError for spacing, materialize track `() != ('block',)`). test_press_scenes_hold_one_press_on_one_tracked_glass did NOT pass before implementation: it failed at `scene.track` `() != ('glass',)` for material.interactive (it asserts track as well as the six heights, so the controller's pre-flight F4 premise did not hold here). Transcribed as written; passes after.

## Gates
- harness: Ran 171 tests ... OK
- example: flutter test --no-pub +10: All tests passed!; analyze: No issues found!
- Nothing Dart changed; app and package gates not run.

## Runs (native, packages/mobile/build/glass_lab/runs/)
- build native: ok (backdrops reinstalled into native after build)
- materialize: /Users/omaraly/development/AI/Operator-2b1/packages/mobile/build/glass_lab/runs/20261004-000223
- materialize Reduce Motion: .../runs/20261004-001040
- interactive: .../runs/20261004-001855
- press: .../runs/20261004-002204
- spacing: .../runs/20261004-003527
No driver crashes (every driver.log longer than one line). Accessibility defaults read 0 and 0 afterwards. Note: run layout is run/scene/case/native/, so measure paths need the trailing /native.

## Step 7 (dark-photo materialize; touches from marker; ms)
| case | out 10-90 (exp) | in 10-90 (exp) | touches s |
| default | 141.7 (125-133) | 291.7 (275-292) | 0.102, 0.153 |
| snappy | 116.7 (117-125) | 216.7 (200) | 0.074, 0.097 |
| bouncy | 108.3 (100-108) | 141.7 (133), overshoot in 1.42 | 0.080, 0.142 |
| RM default | 141.7 | 283.3 | 0.087, 0.090 |
| RM snappy | 125.0 | 208.3 | 0.054, 0.079 |
| RM bouncy | 108.3 | 158.3 (exp ~133), overshoot in 2.75 (exp 2.8-3.8) | 0.089, 0.100 |
Each has two touches and two events (steps 1, 3). Beyond a frame (8.3 ms): default out +8.7 over 133 (about 1 frame); snappy in 216.7 vs 200 (2 frames); bouncy in 141.7 vs 133 (1 frame); RM bouncy in 158.3 vs 133 (3 frames). Reduce Motion bouncy overshoots more than normal (2.75 vs 1.42), as expected.

material.interactive dark-stripes: rest 252.0 x 88.67, max 264.0 x 93.0 (+12.00 / +4.33; expected +4.67, 0.33 pt off). Two touches and six events (steps 1, 3), but touch durations 2.129 s and 2.873 s versus expected 0.95 and 1.31 s: differs by about 1.2 and 1.6 s. Press shows (max > rest), content is v13's.

material.press.250x44 dark-stripes: one touch, 1.540 s (expected ~0.99 s); rest 252.0 x 44.67, max 266.33 x 47.67 (+14.33 matches).

Spacing: measured only by viewing dark-photo ready.png of spacing.40.a: four pairs, all joined (as expected for spacing 40). Topology numbers were not measured (not required by Step 7).

## Self-review
Diff is the brief's patches and test only, no comments added. Other press sizes' measures were not checked.

## Concerns
- Marker durations of holds are about 0.55-1.6 s longer than the prototype's, and native tap durations (Task 5 also noted) vary; the marker's hold-end detection or driver latency may be the cause. Not investigated; no code changed.
- Press test premise (F4) false as noted.

## Fix round 1: spacing topology

Run 20261004-003527, dark-photo, native. Computed with track.still_mask + track.topology over each manifest region (the path of shapes.static_topology), throwaway script.

| container | region | count | neck pt |
|---|---|---|---|
| default | g0 | 1.0 | 25.333333333333332 |
| default | g4 | 1.0 | 4.0 |
| default | g8 | 2.0 | 0.0 |
| default | g12 | 2.0 | 0.0 |
| default | g16 | 2.0 | 0.0 |
| default | g20 | 2.0 | 0.0 |
| default | g24 | 2.0 | 0.0 |
| default | g32 | 2.0 | 0.0 |
| default | g40 | 2.0 | 0.0 |
| default | g48 | 2.0 | 0.0 |
| default | g60 | 2.0 | 0.0 |
| 40 | g0 | 1.0 | 50.666666666666664 |
| 40 | g4 | 1.0 | 38.333333333333336 |
| 40 | g8 | 1.0 | 40.666666666666664 |
| 40 | g12 | 1.0 | 34.0 |
| 40 | g16 | 1.0 | 24.666666666666668 |
| 40 | g20 | 1.0 | 2.0 |
| 40 | g24 | 2.0 | 0.0 |
| 40 | g32 | 2.0 | 0.0 |
| 40 | g40 | 2.0 | 0.0 |
| 40 | g48 | 2.0 | 0.0 |
| 40 | g60 | 2.0 | 0.0 |

Matches the brief exactly: default joins at g0 (25.33) and g4 (4.00), apart from g8 up; spacing 40 joins g0-g20 (necks 50.67, 38.33, 40.67, 34.00, 24.67, 2.00), apart from g24 up.

## Fix round 2

Change: in test_press_scenes_hold_one_press_on_one_tracked_glass, `assertEqual(len(heights), 6)` became `assertEqual(heights, [44, 54, 58, 88, 120, 200])`. The list is [44, 53, ...] adjusted to 54: the 138x53 press region is 114 tall (53 rest 54 incl. rounding, region height minus 60 = 54), so the manifest encodes 54, not 53.
Commands: python3 -m unittest tool/glass_lab/harness/tests/test_scenes_2b.py -> Ran 4 tests OK; python3 -m unittest discover tool/glass_lab/harness/tests -> Ran 171 tests OK.
Commit: 4140c831a test(glass-lab): press scene test pins the six glass heights
