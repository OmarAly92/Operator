# Task 6 report

Status: DONE. Commit: see `git log -1` on feat/ios-liquid-glass-2b1 (message "feat(glass-lab): measure, per-case repeat ...").

Implementation: brief patches applied verbatim (extracted mechanically) with `git apply --3way`, all clean: test_lab.py, lab.py, sim.py, build.py, noise.json; reproduce.py written from the brief's code block.

TDD: RED before the code patches: 15 tests, failures=2, errors=6 (KeyError 'native', noise event2 entries, require_fresh not called, CalledProcessError from simctl ui with the MagicMock device), as the brief predicted. GREEN: `Ran 154 tests ... OK`.

Gates: only harness Python touched, no Dart; harness gate OK (154 tests). Flutter gates not run (no Dart touched).

Recordings: all 13 sources existed; copied into build/glass_lab/reference (441M, git-ignored). No simulator use.

Reproduction: reproduce.py materialize/press/menu output (33 lines) saved to task-6-reproduce.txt; `diff` against research/proto-2b1/reproduce.txt is IDENTICAL, so every number matches the brief, the prototype and rulings 1-6.

Self-review: diff equals the brief's patches; no comments added. Note: the RED run of the old cmd_repeat printed a NOISE temp path but noise.json was unchanged at that point (git status clean of it).

Concerns: none.
