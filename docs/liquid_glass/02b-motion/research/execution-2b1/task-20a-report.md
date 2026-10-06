# Task 20a report (Steps 1-3)
Status: DONE. Files sliced mechanically from the brief: tests/test_done_numbers.py, still_check.py, done_table.py, rim.py, rim_check.py, ghost_probe.py, cold_probe.py under packages/mobile/tool/glass_lab/harness.
TDD: with done_table, rim and still_check removed, the test file failed to import (errors=1); with them in place it ran 4 tests OK.
Gate: python3 -m unittest discover tool/glass_lab/harness/tests -> Ran 175 tests, OK. rim_check, ghost_probe and cold_probe import cleanly (not run; they need the simulator).
Self-review: code is verbatim from the brief, no comments, only the 7 files committed. Concern: the failing run was reproduced after writing (files were written in one script), not before.
