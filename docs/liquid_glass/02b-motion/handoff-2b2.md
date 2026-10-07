Execute the ios_liquid_glass 2B.2 plan, subagent-driven, on this Mac.

Read first, in order:
1. docs/liquid_glass/ROADMAP.md: the whole file, especially §5 (working rules) and the gotchas (35 and 43–52 matter most).
2. docs/liquid_glass/02b-motion/spec.md: the approved spec. It is binding. 2B.2 is §4, its parts are §5–§7, and its Done list is §8 "2B.2 is done when".
3. docs/liquid_glass/02b-motion/plan-2b2.md: the plan. 28 tasks (0 to 27, with 24b); its header's 32 rulings refine the spec, and where they differ the rulings win. Read the header, Global Constraints, Execution setup, Review Focus, "What this plan expects to reach" and the File map in full. Then work task by task.
4. docs/liquid_glass/02b-motion/plan-2b2-review.md and docs/liquid_glass/02b-motion/research/proto-2b2/plan/rereview-1.md: what the two independent reviews found, and how the plan answered.
5. docs/liquid_glass/02b-motion/brainstorm.md, and todo-2b1.md for what 2B.1 left.

How to run it:
- Use the superpowers:subagent-driven-development skill. Keep its ledger, so a compaction cannot repeat finished tasks.
- Create the worktree from development (it holds the plan and its evidence):
  git -C /Users/omaraly/development/AI/Operator worktree add /Users/omaraly/development/AI/Operator-2b2 -b feat/ios-liquid-glass-2b2 development
  Do all work there, then cd packages/mobile && flutter pub get --offline (Task 0).
- Apply each task exactly as the plan writes it, including its `git apply --3way` steps and every fail-first step. The plan was replayed task by task onto development: 41 patches, 113 runs, 0 problems, and the result matched the prototype file for file. If a patch or an expected output does not match, stop that task, find out why, and record a ruling in the ledger. Never improvise around it.
- Keep the throwaway worktrees /Users/omaraly/development/AI/Operator-2b2-proto, Operator-2b2-h4 and Operator-2b2-morph. The plan reads prototype recordings from them. Do not delete them or their build folders.
- Tasks 3, 25, 26 and 27 record on the simulator for hours (noise floors over two sessions with a reboot between, the native `material.respace` reference, the verification runs). Keep the Mac awake, do not cut them short, and run one lab command at a time.
- Disk: about 83 GB were free on 2026-10-07. Check `df -h /Users/omaraly` before the archive copy, before every group of Task 25 and before every Task 27 run. Stop under 40 GB and report; ask the main session under 45 GB. Never delete anything to make room.
- Fitted values come only from the plan's tools (`lab.py fitvis --write`, `tune --write`). Never type a fitted number by hand. `ios27MorphContentBlur` is the one hand-placed line, disclosed in the plan.
- Task 26 has a stop rule: if native does not animate `spacing`, stop and report to the main session; do not keep unverified behaviour silently.
- Fill docs/liquid_glass/02b-motion/results-2b2.md from the plan's template (spec §8's 2B.2 Done table):
  - every number with its run folder, as passing / judged / expected, progress measures separate from the event checks;
  - the merge and morph counts under the old and the new manifest side by side (D3);
  - every failure classed by cause with evidence and carried to todo-2b2.md; the plan forecasts that Done items 1 to 3 will still fail in part;
  - "still glass no worse than 2A" checked on every 2A still scene, with the plan's stated limit (it covers pinned groups only);
  - the limits that moved because of gotcha 52, and the Task 3 recompute check.

Hard rules:
- Only the iOS 27 simulator "iPhone 17 Pro (iOS 27)", UDID 708879DD-8B2A-4547-863F-F49EE1474D8B. Name the UDID in every simctl command, never `booted`. Never touch the iOS 26.5 simulator (94D0C207-A90B-4806-BBAB-8AF9B3F16329).
- Build the lab apps only through tool/glass_lab/harness/lab.py build. Plain `flutter build ios` fails under Xcode 27.
- Stop a lab run only with SIGINT (gotcha 50). Reboot the simulator before native recordings and check that a 1.0 s press reads 0.8–1.2 s (gotcha 49).
- Simulator or system prompts: answer only "Don't Allow" or "Not Now". Never pair Operator. Never enter a password.
- No code comments in any code you write.
- Every commit message ends with: Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
- Never stage frontend/package-lock.json. Never git stash. Never run dart format on whole files.
- No downloads, no pip install, no new dependencies.
- Never loosen a limit or a measure.
- Never write to, move or delete anything in /Users/omaraly/development/AI/glass-lab-runs/2b1/: only read and copy.
- Do not merge and do not push. Never commit to development, and do not touch /Users/omaraly/development/AI/Operator except for the one worktree add.

Gates after every task that touches their code, from packages/mobile in the worktree:
- flutter analyze --no-pub in the app, packages/ios_liquid_glass and packages/ios_liquid_glass/example, each "No issues found!";
- flutter test --no-pub in all three (the app's gate does not run at Tasks 18 and 20; it runs whole at Task 24b, as the plan says);
- python3 -m unittest discover tool/glass_lab/harness/tests prints OK.

When every task is done, finish with the skill's final whole-branch review. Then stop and report:
- the branch tip;
- the gate output lines;
- the Done table summary per item, passing / judged / expected;
- every failure, with its class;
- any ruling you made, with its reason;
- anything you could not do.

The main session then reviews the branch with an independent code review and a measurement audit before anything merges.
