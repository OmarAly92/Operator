# 2A handoff prompt (paste into a fresh local Claude Code session)

You are executing project 2A of the `ios_liquid_glass` effort: turn Operator's vendored Liquid Glass renderer into `ios_liquid_glass`, a Flutter package that looks like native iOS 27 Liquid Glass as measured by the glass lab. Operator is only its first consumer. You are the controller. Execute the approved plan task by task with **superpowers:subagent-driven-development**, then stop and report. A separate session, the one that wrote the plan, reviews your branch afterwards.

## Read first, in this order
1. `/Users/omaraly/development/AI/Operator/docs/liquid_glass/ROADMAP.md`, all of it. It is the source of truth: goal, environment (§3), gotchas (§4, items 1–20), working rules (§5).
2. `docs/liquid_glass/02a-looks/spec.md`: the approved spec.
3. `docs/liquid_glass/02a-looks/plan.md`: **the plan you execute**. It has 13 tasks and embeds tested code. Its header lists 15 rulings, which win over the spec where they differ. Then come the Global Constraints, the Review Focus and the file map.

Read these three files from the shared checkout only until the worktree exists; afterwards read them inside the worktree. They are identical, since the branch starts from `development` at or after `f236ebad4`.

## Where to work
- Worktree `/Users/omaraly/development/AI/Operator-ios-liquid-glass`, branch `feat/ios-liquid-glass-2a`, from `development`. Create it exactly as Task 1 Step 1 says, then run `flutter pub get` in `packages/mobile`.
- **Never touch the shared checkout `/Users/omaraly/development/AI/Operator`.** Other sessions commit there. Never stash, never commit there, never merge, never push.
- The prototype `/Users/omaraly/development/AI/Operator-2a-proto` (branch `proto/2a`) is **read-only reference**. Every code block in the plan was extracted from its working tree. If a plan block ever looks truncated or ambiguous, the same path in the prototype is the ground truth. Never modify or build it.

## How to run the plan
- Use superpowers:subagent-driven-development exactly: a ledger in the worktree's `.superpowers/sdd/`, a task brief per task, one implementer per task, a task review after each, and a final whole-branch review on the most capable model. Before Task 1, run the skill's pre-flight conflict scan and write it to the ledger.
- **Models.** Tasks 1, 3, 4, 5, 6, 8, 9 and 10 are transcription of complete code plus verification: use a cheap tier for the implementer and a mid tier for reviewers. Tasks 7, 12 and 13 involve multi-file judgment: use a mid tier. Task 11 is described below.
- **Task 11, the tuning campaign**, is many hours of simulator time. Dispatch one implementer per group (A, B, C, D, E, F), mid tier, each with its own task review. The reviewer checks that group's `tuning-log.md` lines and the table diff: only the intended rows changed, and only through `--write` or `copy_row`.
- **Long commands** (`lab.py build`, `prepare`, `run`, `tune`, `perf`, `a11y`, `baseline`): run them in the background and wait with an until-loop or Monitor on their output. Never poll with short sleeps.
- **Run only one lab command at a time.** They share the one simulator, and two at once corrupt each other's screenshots.
- **Keep the Mac awake for the whole session.** Use the app's keep-awake tool if you have it, otherwise run `caffeinate -dimsu` in the background.
- If context runs low, trust the ledger and `git log`, never your memory.

## Hard rules (also in the plan's Global Constraints)
- No code comments in any new or changed code: Dart, Swift, Python, GLSL or shell. Keep upstream comments already in the vendored files.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `frontend/package-lock.json`. Never `git stash`.
- Never run `dart format` on whole files; match the surrounding style.
- `flutter build ios` alone fails under Xcode 27. Build only with `python3 tool/glass_lab/harness/lab.py build <target>`.
- **Simulator.**
  - Use only "iPhone 17 Pro (iOS 27)", UDID `708879DD-8B2A-4547-863F-F49EE1474D8B`; the harness finds it by name.
  - Never touch the iOS 26.5 simulator `94D0C207-A90B-4806-BBAB-8AF9B3F16329`; it holds the user's real Operator.
  - System prompts get only "Don't Allow" or "Not Now".
  - Never pair Operator, never enter a password.
- No `pip install`, no downloads. Python uses the standard library, Pillow and numpy.
- **Material numbers** in `ios27.dart` and `ios27_scroll_edge.dart` change only through `lab.py tune --write`, or the `copy_row` snippet in Task 11. Never edit them by hand, even to "fix" a failing case.
- Judge glass only by lab measurements. When a number looks wrong, open the screenshots and the filmstrips.
- The long SkSL error about `liquid_glass_geometry_blended` in `flutter test` output is known and harmless.

## When to stop and ask
Only these:
- an irreversible or destructive operation;
- anything outside the worktree that normally needs asking (merge, push, touching the shared checkout);
- **Task 9 Step 4's flip table shows any `flips` verdict.** That changes 2A's scope; stop and report the table;
- a plan defect where every path forward is a guess.

For everything else, rule, record the ruling in the ledger as `Ruling: what — why — cost if wrong`, and continue. A tuning case that misses its threshold after the plan's one retry is **not** a stop: log the residual and go on.

## When all 13 tasks are done
Do not merge, push or delete the worktree. Reply with:
1. the branch head, and the list of commits per task;
2. the ledger path, and every ruling you made;
3. every place you deviated from the plan's code, and why;
4. the contents of `docs/liquid_glass/02a-looks/results.md`: every Done item with its numbers, and every failing case;
5. the gate results as final counts: package, example, app `flutter test`; harness unittest; and `flutter analyze` in all three;
6. anything the reviewer should look at first.

The reviewing session will diff the branch against the plan, rerun every gate, reopen the reports and filmstrips, and fix what is wrong before anything merges.
