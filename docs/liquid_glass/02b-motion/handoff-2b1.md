Execute the ios_liquid_glass 2B.1 plan, subagent-driven, on this Mac.

Read first, in order:
1. docs/liquid_glass/ROADMAP.md: the whole file, especially §5 (working rules) and the gotchas.
2. docs/liquid_glass/02b-motion/spec.md: the approved spec. It is binding. 2B.1 is §4, and its Done list is §8 "2B.1 is done when".
3. docs/liquid_glass/02b-motion/plan-2b1.md: the plan. 21 tasks; its header's 34 rulings refine the spec, and where they differ the rulings win. Read the header, Global Constraints, Review Focus and File map in full. Then work task by task.
4. docs/liquid_glass/02b-motion/brainstorm.md, the last three sections: the user's decisions and the review decisions.

How to run it:
- Use the superpowers:subagent-driven-development skill. Keep its ledger, so a compaction cannot repeat finished tasks.
- Create the worktree from development (it holds the plan at 697f6d709 or later):
  git -C /Users/omaraly/development/AI/Operator worktree add /Users/omaraly/development/AI/Operator-2b1 -b feat/ios-liquid-glass-2b1 development
  Do all work there.
- Apply each task exactly as the plan writes it, including its `git apply --3way` steps and every fail-first step. The plan was replayed task by task onto development and matched the prototype file for file. If a patch or an expected output does not match, stop that task, find out why, and record a ruling in the ledger. Never improvise around it.
- Keep the throwaway worktrees /Users/omaraly/development/AI/Operator-2b-proto and /Users/omaraly/development/AI/Operator-2b1-proto. The plan reads recordings from them.
- The recording tasks (native references, and noise floors over two sessions with a simulator reboot between them) run for hours. Keep the Mac awake, and do not cut them short.
- Fitted values come only from the plan's tools (`lab.py fitvis --write` and the rest). Never type a fitted number by hand.
- Fill docs/liquid_glass/02b-motion/results-2b1.md with spec §8's 2B.1 Done table, every number with its run folder:
  - judged/expected counts, with progress measures reported separately from the events checks;
  - every failure classed by cause with evidence, and carried to todo-2b1.md;
  - "still glass no worse than 2A" checked on all nine still scenes, including the three Operator scenes.

Hard rules:
- Only the iOS 27 simulator "iPhone 17 Pro (iOS 27)", UDID 708879DD-8B2A-4547-863F-F49EE1474D8B. Name the UDID in every simctl command, never `booted`. Never touch the iOS 26.5 simulator (94D0C207-A90B-4806-BBAB-8AF9B3F16329).
- Build the lab apps only through tool/glass_lab/harness/lab.py build. Plain `flutter build ios` fails under Xcode 27.
- Simulator or system prompts: answer only "Don't Allow" or "Not Now". Never pair Operator. Never enter a password.
- No code comments in any code you write.
- Every commit message ends with: Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
- Never stage frontend/package-lock.json. Never git stash. Never run dart format on whole files.
- No downloads, no pip install, no new dependencies.
- Never loosen a limit or a measure.
- Do not merge and do not push. Never commit to development, and do not touch /Users/omaraly/development/AI/Operator except for the one worktree add.

Gates after every task, from packages/mobile in the worktree:
- flutter analyze in the app, packages/ios_liquid_glass and packages/ios_liquid_glass/example, each "No issues found!";
- flutter test in all three;
- python3 -m unittest discover tool/glass_lab/harness/tests prints OK.

When every task is done, finish with the skill's final whole-branch review. Then stop and report:
- the branch tip;
- the gate output lines;
- the Done table summary per item, passing / judged / expected;
- every failure, with its class;
- any ruling you made, with its reason;
- anything you could not do.

The main session then reviews the branch with an independent code review and a measurement audit before anything merges.
