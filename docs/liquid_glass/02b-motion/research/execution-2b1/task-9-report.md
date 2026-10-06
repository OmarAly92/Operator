# Task 9 report
Run folder: /Users/omaraly/development/AI/Operator-2b1/packages/mobile/build/glass_lab/runs/noise-2b1
Commit: 4140c831a test(glass-lab): press scene test pins the six glass heights
Logs (every '<scene> <case>: 5 takes, static mad ..., motion noise {...}' line is in them): /Users/omaraly/development/AI/Operator-2b1/.superpowers/sdd/plan-2b1/task-9-logs/s1-*.log (session 1, 3 takes) and /Users/omaraly/development/AI/Operator-2b1/.superpowers/sdd/plan-2b1/task-9-logs/s2-*.log (session 2, 2 takes); schedule in /Users/omaraly/development/AI/Operator-2b1/.superpowers/sdd/plan-2b1/task-9-logs/times.log, script /Users/omaraly/development/AI/Operator-2b1/.superpowers/sdd/plan-2b1/task-9-logs/run.sh

## Sessions (start/end, load at start)
session1 start Sun Oct  4 00:59:11 EEST 2026  0:59  up 9 days, 11:56, 2 users, load averages: 13.66 18.58 36.75
s1b Sun Oct  4 02:29:43 EEST 2026  2:29  up 9 days, 13:26, 2 users, load averages: 20.06 26.11 42.77
reboot Sun Oct  4 04:02:01 EEST 2026  4:02  up 9 days, 14:59, 2 users, load averages: 73.04 108.01 107.99
s2a Sun Oct  4 04:02:19 EEST 2026  4:02  up 9 days, 14:59, 2 users, load averages: 67.49 104.33 106.65
s2b Sun Oct  4 05:41:43 EEST 2026  5:41  up 9 days, 16:38, 2 users, load averages: 120.14 161.06 136.27
end Sun Oct  4 07:25:33 EEST 2026

Session 1: 00:59-04:01 (load 13.7 at start of part A, 20.1 at part B). Reboot 04:02 (rebooted line, then ReduceMotionEnabled 0 and EnhancedBackgroundContrastEnabled 0). Session 2: 04:02-07:25 (load 67 at start, 120 at part B). Load averages were very high (other processes on the machine) throughout; takes still gave static mad 0.00.

Every repeat command rc=0. No FAILED line, no driver crash, no rerun. Every static mad 0.00 (60 case lines per session; session 2 lines all '5 takes').

## Step 4 output
material.materialize ['dark-photo', 'dark-photo-reduce-motion', 'dark-stripes', 'dark-stripes-reduce-motion', 'light-photo', 'light-photo-reduce-motion', 'light-stripes', 'light-stripes-reduce-motion']
material.materialize.snappy ['dark-photo', 'dark-photo-reduce-motion', 'dark-stripes', 'dark-stripes-reduce-motion', 'light-photo', 'light-photo-reduce-motion', 'light-stripes', 'light-stripes-reduce-motion']
material.materialize.bouncy ['dark-photo', 'dark-photo-reduce-motion', 'dark-stripes', 'dark-stripes-reduce-motion', 'light-photo', 'light-photo-reduce-motion', 'light-stripes', 'light-stripes-reduce-motion']
material.interactive ['dark-photo', 'dark-stripes', 'light-photo', 'light-stripes']
material.press.circle58 ['dark-photo', 'dark-stripes', 'light-photo', 'light-stripes']
material.press.138x53 ['dark-photo', 'dark-stripes', 'light-photo', 'light-stripes']
material.press.250x44 ['dark-photo', 'dark-stripes', 'light-photo', 'light-stripes']
material.press.300x120 ['dark-photo', 'dark-stripes', 'light-photo', 'light-stripes']
material.press.360x200 ['dark-photo', 'dark-stripes', 'light-photo', 'light-stripes']
material.spacing.default.a {'dark-photo': ['ready.topology.g0.count', 'ready.topology.g0.neck_pt', 'ready.topology.g12.count', 'ready.topology.g12.neck_pt', 'ready.topology.g4.count', 'ready.topology.g4.neck_pt', 'ready.topology.g8.count', 'ready.topology.g8.neck_pt'], 'light-photo': ['ready.topology.g0.count', 'ready.topology.g0.neck_pt', 'ready.topology.g12.count', 'ready.topology.g12.neck_pt', 'ready.topology.g4.count', 'ready.topology.g4.neck_pt', 'ready.topology.g8.count', 'ready.topology.g8.neck_pt']}
material.spacing.default.b {'dark-photo': ['ready.topology.g16.count', 'ready.topology.g16.neck_pt', 'ready.topology.g20.count', 'ready.topology.g20.neck_pt', 'ready.topology.g24.count', 'ready.topology.g24.neck_pt', 'ready.topology.g32.count', 'ready.topology.g32.neck_pt'], 'light-photo': ['ready.topology.g16.count', 'ready.topology.g16.neck_pt', 'ready.topology.g20.count', 'ready.topology.g20.neck_pt', 'ready.topology.g24.count', 'ready.topology.g24.neck_pt', 'ready.topology.g32.count', 'ready.topology.g32.neck_pt']}
material.spacing.default.c {'dark-photo': ['ready.topology.g40.count', 'ready.topology.g40.neck_pt', 'ready.topology.g48.count', 'ready.topology.g48.neck_pt', 'ready.topology.g60.count', 'ready.topology.g60.neck_pt'], 'light-photo': ['ready.topology.g40.count', 'ready.topology.g40.neck_pt', 'ready.topology.g48.count', 'ready.topology.g48.neck_pt', 'ready.topology.g60.count', 'ready.topology.g60.neck_pt']}
material.spacing.40.a {'dark-photo': ['ready.topology.g0.count', 'ready.topology.g0.neck_pt', 'ready.topology.g12.count', 'ready.topology.g12.neck_pt', 'ready.topology.g4.count', 'ready.topology.g4.neck_pt', 'ready.topology.g8.count', 'ready.topology.g8.neck_pt'], 'light-photo': ['ready.topology.g0.count', 'ready.topology.g0.neck_pt', 'ready.topology.g12.count', 'ready.topology.g12.neck_pt', 'ready.topology.g4.count', 'ready.topology.g4.neck_pt', 'ready.topology.g8.count', 'ready.topology.g8.neck_pt']}
material.spacing.40.b {'dark-photo': ['ready.topology.g16.count', 'ready.topology.g16.neck_pt', 'ready.topology.g20.count', 'ready.topology.g20.neck_pt', 'ready.topology.g24.count', 'ready.topology.g24.neck_pt', 'ready.topology.g32.count', 'ready.topology.g32.neck_pt'], 'light-photo': ['ready.topology.g16.count', 'ready.topology.g16.neck_pt', 'ready.topology.g20.count', 'ready.topology.g20.neck_pt', 'ready.topology.g24.count', 'ready.topology.g24.neck_pt', 'ready.topology.g32.count', 'ready.topology.g32.neck_pt']}
material.spacing.40.c {'dark-photo': ['ready.topology.g40.count', 'ready.topology.g40.neck_pt', 'ready.topology.g48.count', 'ready.topology.g48.neck_pt', 'ready.topology.g60.count', 'ready.topology.g60.neck_pt'], 'light-photo': ['ready.topology.g40.count', 'ready.topology.g40.neck_pt', 'ready.topology.g48.count', 'ready.topology.g48.neck_pt', 'ready.topology.g60.count', 'ready.topology.g60.neck_pt']}
[]
[]

git diff of noise.json: 2954 insertions, 0 deletions; menu.bar and tabbar.drag entries still present and unchanged.
Harness unittest: Ran 171 tests, OK.

## Noise vs prototype (non-reduce-motion materialize cases, across all cases/measures)
t10_90_ms 0-75 (proto 8-25; snappy/bouncy 0-25); settle_ms 0-67 (proto 17-25); rms 0.008-0.090 (proto 0.007-0.019; materialize normal max 0.090 above, snappy/bouncy 0.010-0.019); sharpness 0.016-0.38 (proto 0.02-0.17); response_pct 2.1-34.9 (proto 2-21); damping 0.01-0.15 (proto 0.02-0.10).
Somewhat outside the prototype ranges at the top end (more takes, reboot pairs): flagged, not wrong. Concern: machine load was extreme during recording.
