# Fix round 1 for plan-2b2.md

You continue the 2B.2 plan work in worktree `/Users/omaraly/development/AI/Operator-2b2-proto`, branch `proto/2b2` (tip `4db370855`). The previous plan writers are gone; read the history from `git log --oneline 4db49edc3..HEAD`.

Read, in order:
1. `docs/liquid_glass/02b-motion/research/proto-2b2/plan/` (`build_plan.py`, `gen_tasks.py`, `tasks.py`, `replay.py`, templates): how the plan is generated and replayed.
2. `docs/liquid_glass/02b-motion/plan-2b2-review.md`: the independent review (verdict: ready after fixes; 0 blockers, 6 major F1–F6, 9 minor F7–F15, 4 notes). Fix everything it finds in the plan, builder and prototype.
3. The plan itself, in parts, only where a finding points.
Original brief (still binding): `/private/tmp/claude-501/-Users-omaraly-development-AI-Operator/bef75372-7901-417c-9118-4f19c37b5461/scratchpad/brief-2b2-plan-writer.md`; continuation brief: `.../brief-2b2-continue.md` in the same folder.

Keep the replay matching the prototype file for file.

## Rulings (user decisions of 2026-10-07 and main-session rulings)

USER DECISIONS
- **F5 spacing animation: keep it (option A)**, and add a native reference to the plan: one native scene that animates `spacing` (SwiftUI changes a container's spacing under withAnimation), recorded and judged in execution as its own task with its own native scene, Flutter scene, tap id and measures. Ruling 12 must say plainly that no native evidence exists yet and the execution session records it. If the native reference shows no animation of spacing, the plan must say what the executor does: stop and report to the main session, never keep unverified behaviour silently.
- **D3 manifest (option A):** replace `material.merge`'s `width.*` measures (the circles never change width) with per-glass position and the pair's join/neck/gap measures, and give `material.morph` per-glass tracking. Not a loosening: add the new motion key to `MOTION_MEASURES` with tests (fixes F4's missing key), report old and new judged/expected counts side by side in the Done table template, and say it is a user-approved manifest correction (2026-10-07).

MAIN-SESSION RULINGS
- **D1 union dark material:** option A, each container member uses its own size's material row.
- **D2 union glyph size:** option A, match native's glyph ink in the example's union scene; never shrink the measured regions.
- **D4:** keep the hand-placed 1.5 for now; record the follow-up (a `fitvis` flag so only a tool writes `ios27MorphContentBlur`) as a carry-in, and say in the plan the value is not tool-written.
- **D5:** fix the one-frame mirror at motion onset in this plan, as a task BEFORE Task 14's verification runs, with a test; the other ruling-21 defects stay 2B.3 carry-in until the noise floors show which survive.
- **F1 chained morph swaps never settle:** fix with a test (a second swap at 60 ms and 300 ms settles: no ghost, no running ticker).
- **F2 16-shape cap:** a sinking or pending ghost counts toward the cap; handle the 17th shape without an uncaught `UnsupportedError` in paint (read how 2B.1's ghosts differ and why), and add the test spec §9 requires (construct render objects; the geometry shader cannot compile in `flutter test`).
- **F3 gotcha 52:** the execution setup must make the replacement take and the exclusion exist in its own copy of `noise-2b1`, as a scripted step with the exact moves and a check that take 2 is excluded and take 5 present; it must not rely on the prototype's untracked `build/` folder. State where the replacement take's frames come from, or that execution re-records it after a fresh boot. Task 14's refit must not read the old take.
- **F6 ruling 18:** rewrite so "nearest glass" and "within spacing sinks" are stated as working hypotheses that native's frames do not separate, not as evidence. Add the native control that could separate them to execution if it is cheap; otherwise list it as an open item.
- **F7–F15 and the notes:** fix or state each honestly:
  - disclose the 3 looser limits in the ruling;
  - give the replacement-take command its `--appearance`/`--backdrop`/`--a11y` flags;
  - add a stop rule on static repeatability failure, a press-length check at every session and after 3 hours, what to do on a stale-build refusal, and stop Task 13 from overwriting existing 2B.1 spacing floors;
  - fix the Done-table expected-count wording;
  - put the D5 fix before Task 14;
  - correct overclaims: "pixel-identical at every gap" becomes the gaps measured; the README's "4 to 80 pt" claim against 6 of 46 N7 cases passing; state that the angle model is worse than plain quadratic at S4–S10;
  - disclose that the H4 exponents were fitted on the measures that judge them;
  - say what the removed ≤4-shape fast path costs;
  - say why the block default stays 20 while the container default is 8;
  - handle or record union membership jumping when a member appears;
  - make Task 12's "red" a real test failure (fix the new test that passes before its implementation, or justify it explicitly).

## Process and hard rules

- Keep context lean; use `sonnet` helper subagents for gate runs, native recordings and the replay, with exact commands.
- Commit on `proto/2b2` only; every commit message ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Never push. Never touch `development` or the shared checkout except `git worktree add --detach` for the replay.
- No code comments. Never `dart format` whole files. Never loosen a limit or a measure. Fitted values only from tools. Never `git stash`.
- Simulator: only "iPhone 17 Pro (iOS 27)", UDID `708879DD-8B2A-4547-863F-F49EE1474D8B`, named in every simctl command, never `booted`; reboot and check the press length (0.8–1.2 s) before any native recording; stop lab runs only with SIGINT.
- Disk: `df -h /Users/omaraly` before heavy work; stop under 40 GB and report. Delete only your own scratch worktrees (you may remove `Operator-2b2-replay`; leave the other worktrees).
- Re-run the full replay onto a fresh `development` export, and every gate, at the end.

## Final report (short)

Proto tip; plan length; each finding F1–F15 as fixed / stated / needs-user with one line; the new task list; gate lines; replay result; anything you could not do, or anything new that is truly the user's.
