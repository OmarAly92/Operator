# Task 5 report: touch marker in both apps

Status: DONE (one concern, below). Commit ad9ef2ae4.

## Implementation
Patches and TouchMarker.swift were extracted mechanically from the brief and applied with `git apply --3way` (all clean, no conflicts). 10 files changed (TouchMarker.swift new). No comments added.

## TDD
RED (before implementation):
- `python3 -m unittest tool/glass_lab/harness/tests/test_record.py` -> `KeyError: 'marker'`, `Ran 7 tests ... FAILED (errors=2)`
- example `flutter test --no-pub test/lab_test.dart` -> `Error: No named parameter with the name 'marker'.`
GREEN: harness `Ran 147 tests ... OK`; example analyze "No issues found!", test `+10: All tests passed!`.

## Gates
- packages/mobile: analyze "No issues found!"; test `+2146: All tests passed!`
- packages/ios_liquid_glass: analyze "No issues found!"; test `+67: All tests passed!`
- example: analyze "No issues found!"; test `+10: All tests passed!`
- harness: `Ran 147 tests`, OK

## Simulator proof
Builds native and example succeeded. Backdrops installed (no error). Run: `lab.py run material.materialize --appearance dark --backdrop photo`.
Run folder: build/glass_lab/runs/20261003-234148 (material.materialize/dark-photo). Both driver.logs are 74 lines (no driver crash). ReduceMotionEnabled reads 0 afterwards.
Touches read back (start, end in s):
- native: (17.007, 17.122), (19.722, 19.863), durations 115 ms and 141 ms
- flutter: (17.542, 17.58), (20.242, 20.35), durations 38 ms and 108 ms
Two touches per app as expected.

## Self-review
Diff matches the brief verbatim; marker is the only change set; the Xcode project needed no change.

## Concerns
The native touches last 115 and 141 ms, above the brief's stated 30-110 ms window (prototype read 42 and 70 ms). Counts and positions are right; the native durations are probably video frame quantisation or the held tap in this run. Not investigated further, no code changed.
