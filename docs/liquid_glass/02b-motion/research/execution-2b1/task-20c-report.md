# Task 20c report (Steps 5 and 6), HEAD 58ab57e0c

Load (uptime) at starts: normal run 11.4 (23:31), RM run ~19.7 (23:47), repeats 18.4 (00:16), cold probe about 18. Accessibility default ReduceMotionEnabled read 0 after every run.

## Commands and folders (from packages/mobile in /Users/omaraly/development/AI/Operator-2b1)
- `lab.py run material.materialize` -> build/glass_lab/runs/20261005-233131 (normal, 48 driver.logs, no crashes)
- `lab.py run material.materialize --a11y reduce-motion` -> build/glass_lab/runs/20261005-234750 (RM, 48 driver.logs, no crashes)
- `lab.py report` on both: 12 cases each, reports pass 0 / fail 12 (the case-level report fails every case on the measure failures below).
- `done_table.py <normal> <RM>` -> task-20c-done-table.txt (146 lines). No rebuild was needed; no driver crashes.

## done_table totals (progress measures passing/judged/expected)
- Normal 20261005-233131: 130 / 168 / 168. Reduce Motion 20261005-234750: 133 / 168 / 168. (Prototype: 112 and 108.)
- Event and touch gates: 120/120 across both (5/5 in every one of the 24 scene-appearance lines), unpaired 0 everywhere.
- Per-line counts are in the done-table file (e.g. normal dark-photo 7/14, dark-stripes 12, light-photo 12, light-stripes 12; bouncy dark-photo 9, bouncy light-stripes 9).
- 73 FAIL lines in total across both runs.

## Stalls and first frames
- Flutter gaps over 25 ms (flagged by done_table): normal default light-stripes [27]; normal snappy dark-photo [32, 25]; RM bouncy light-stripes [30]. All others none.
- Flutter first changed frame ahead of native's by more than 0.2: none (checked by script over every pair; largest differences about 0.03).
- Native stalls listed (not repeated): normal dark-photo [28], light-photo [25, 25, 27]; RM dark-photo [25], light-photo [25], light-stripes [25], snappy dark-stripes [28], snappy light-stripes [28].
- Capture holes: I did not examine native frame gaps for the first-gap >30 ms followed by two sub-5 ms signature. Native first-frame delays of 33-50 ms are common in the table (e.g. normal dark-photo step1 33, light-photo step1 48), so the controller may want to inspect.
- Odd line: RM snappy light-stripes step3 Flutter delay 0 ms, first frame 0.02@90ms (not flagged as a stall).

## Repeats (alone, both apps, pair per case)
- Normal default light-stripes (Flutter stall 27): `lab.py run material.materialize --appearance light --backdrop stripes` -> 20261006-001644 (this ran default, snappy and bouncy light-stripes). Default repeat: no stalls, 12/14 (same as original). Extra snappy 12/14 and bouncy 9/14 are not substituted.
- Normal snappy dark-photo (Flutter stalls 32, 25): `lab.py run material.materialize.snappy --appearance dark --backdrop photo` -> 20261006-002044: no stalls, 10/14 (original 11/14 with stalls).
- RM bouncy light-stripes (Flutter stall 30): `lab.py run material.materialize.bouncy --appearance light --backdrop stripes --a11y reduce-motion` -> 20261006-002206: no stalls, 12/14 (original 10/14).
- Kept the stall-free repeat for all three. Totals with the repeats substituted: normal 129 / 168, RM 135 / 168. Reports for the repeats ran (done_table on the three: 55/70, gates 25/25).

## Cold probe (task-20c-cold.txt, folder build/glass_lab/cold/20261006-002600, source normal dark-photo)
- Disappear (step 1): Flutter first frame after 35 ms at progress 0.38 (native 33 ms at 0.03), 10-90% 83 ms against native 133. Appear (step 3): Flutter first frame 15 ms at 0.03 (native 13 ms at 0.03), 10-90% 300 against 275. Native had one 28 ms stall inside; Flutter none.
- Prototype: disappear 38 ms at 0.38 (native 0.03 after 45), 83 vs 133; appear 17 ms at 0.03, 300 vs 292. Matches closely.

## Comparison with the prototype
Progress counts are above the prototype's (130/133 against 112/108). Gates 120/120 as in the prototype. The prototype had no stalls in either app; here Flutter had three stalled cases (all clean on repeat) and native several 25-28 ms gaps. The notable failures: normal dark-photo 7/14 (step1 fails damping, response_pct 32, settle, sharpness, t10_90 25 ms); bouncy settle on light-photo (158 ms over) and light-stripes (125 over) as in the prototype's .bouncy settle class; sharpness on dark photo.
