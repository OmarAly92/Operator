Execute the ios_liquid_glass 2B.3 plan, subagent-driven, on this Mac.

Read first, in order:
1. docs/liquid_glass/ROADMAP.md: the whole file, especially §5 (working rules) and the gotchas (35 and 43–52 matter most).
2. docs/liquid_glass/02b-motion/spec.md: the approved spec. It is binding. 2B.3 is §4, its parts are §5–§7, and its Done list is §8 "2B.3 is done when".
3. docs/liquid_glass/02b-motion/plan-2b3.md: the plan. Tasks 0 to 16 (14b is NOT TO RUN); its header rulings refine the spec, and where they differ the rulings win. Read the header, Global Constraints, Execution setup, Review Focus, "What this plan expects to reach" and the File map in full. Then work task by task.
4. The plan's three independent reviews and the answers: docs/liquid_glass/02b-motion/plan-2b3-review.md, rereview-2b3.md, rereview2-2b3.md, rereview3-2b3.md (the last says "ready to execute: yes" after one text fix, which is in the plan).
5. docs/liquid_glass/02b-motion/brainstorm.md, todo-2b1.md and todo-2b2.md for what 2B.1 and 2B.2 left.

Decisions the user has made (do not reopen):
- D9 A: Operator's `_PressLift` moves onto the package press (Task 10, separable). It is shown to the user before merge and can be dropped then.
- D6 A: native's small lean toward a finger outside the glass is not built in 2B.3 (Task 14b is NOT TO RUN); a fix wave decides it from Task 13's floors.
- D12 A / D13 A: the size law is Task 14's refit with its stop rule. If no form keeps every measured size within the 1 pt threshold, Task 14 stops, writes nothing and reports to the main session. The shipped law's known misses (120 x 250 portrait, 300 x 250) are declared in the forecast and README.
- D1 A (seam fix stays in project 3, after the mirror test of Task 9), D2, D4, D7, D8, D10 deferred to fix waves or project 3.

How to run it:
- Use the superpowers:subagent-driven-development skill. Keep its ledger, so a compaction cannot repeat finished tasks.
- Create the worktree from development (it holds the plan and its evidence), as the plan's Execution setup says:
  git -C /Users/omaraly/development/AI/Operator worktree add /Users/omaraly/development/AI/Operator-2b3 -b feat/ios-liquid-glass-2b3 development
  Do all work there, then cd packages/mobile && flutter pub get --offline (Task 0).
- Apply each task exactly as the plan writes it, including its `git apply --3way` steps and every fail-first step. The plan was replayed task by task onto a fresh export of development: 18 patches, 36 runs, 0 problems, and the result matched the prototype file for file. If a patch or an expected output does not match, stop that task, find out why, and record a ruling in the ledger. Never improvise around it.
- Keep the throwaway worktrees /Users/omaraly/development/AI/Operator-2b3-proto and Operator-2b3-dev. The plan reads prototype recordings and the development reference run from them. Do not delete them or their build folders.
- Tasks 12, 13 and 15 record on the simulator for hours (about 17 h of execution in all, about 7.5 h on the simulator). Keep the Mac awake and the simulator exclusive, run one lab command at a time, and run no analysis, test or build while a native take records or `perf` runs (the prototype's own analysis squeezed a press).
- Every press take passes the plan's take check (ruling 16). Reboot the simulator before native references, every two hours of recording, and whenever three attempts in a row fail the take check. Stop a lab run only with SIGINT (gotcha 50).
- Disk: about 79 GB were free on 2026-10-14 after the user freed 23 GB. Check `df -h /Users/omaraly` before every recording group and before the archive copy. Stop under 40 GB and report; ask the main session under 50 GB. The only thing you may delete is the analysis frame caches the plan names; never recordings, never anything else.
- Fitted values come only from the plan's tools (`pressfit.py fit --write`, `lab.py fitvis --write`, `tune --write`). Never type a fitted number by hand.
- Stop rules: Task 3's leverage stop (one take sets a time limit above 3x its siblings' median) and Task 14's law stop both end the task and report to the main session. Do not work around them.
- Fill docs/liquid_glass/02b-motion/results-2b3.md and todo-2b3.md as Task 16 says: every number with its run folder, passing / judged / expected; in-sample and independent counts side by side; every failure classed by cause with evidence.

Hard rules:
- Only the iOS 27 simulator "iPhone 17 Pro (iOS 27)", UDID 708879DD-8B2A-4547-863F-F49EE1474D8B. Name the UDID in every simctl command, never `booted`. Never touch the iOS 26.5 simulator (94D0C207-A90B-4806-BBAB-8AF9B3F16329).
- Build the lab apps only through tool/glass_lab/harness/lab.py build. Plain `flutter build ios` fails under Xcode 27.
- Simulator or system prompts: answer only "Don't Allow" or "Not Now". Never pair Operator. Never enter a password.
- No code comments in any code you write.
- Every commit message ends with: Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
- Never stage frontend/package-lock.json. Never git stash. Never run dart format on whole files.
- No downloads, no pip install, no new dependencies.
- Never loosen a limit or a measure.
- Never write to, move or delete anything in /Users/omaraly/development/AI/glass-lab-runs/: only read and copy.
- Do not merge and do not push. Never commit to development, and do not touch /Users/omaraly/development/AI/Operator except for the one worktree add.
- Use sonnet subagents for mechanical work (recordings, gates, replays) and keep usage low: the user watches the weekly limit.

Gates after every task that touches their code, from packages/mobile in the worktree:
- flutter analyze --no-pub in the app, packages/ios_liquid_glass and packages/ios_liquid_glass/example, each "No issues found!";
- flutter test --no-pub in all three (counts after the plan's patches: app 2188, package 280, example 25);
- python3 -m unittest discover tool/glass_lab/harness/tests prints OK (315).

When every task is done, finish with the skill's final whole-branch review. Then stop and report:
- the branch tip;
- the gate output lines;
- the Done table summary per item, passing / judged / expected, in-sample and independent;
- every failure, with its class;
- any ruling you made, with its reason;
- anything you could not do.

The main session then reviews the branch with an independent code review and a measurement audit before anything merges.
