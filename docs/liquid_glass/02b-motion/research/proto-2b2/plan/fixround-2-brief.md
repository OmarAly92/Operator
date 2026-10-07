# Fix round 2 for plan-2b2.md

Worktree `/Users/omaraly/development/AI/Operator-2b2-proto`, branch `proto/2b2` (tip after the re-review: `6d815172b` plus uncommitted `research/proto-2b2/plan/rereview-1.md` and `rereview-1-brief.md`, which you commit as evidence).

Read `docs/liquid_glass/02b-motion/research/proto-2b2/plan/rereview-1.md` (verdict: ready after fixes; 1 blocker R1, 6 minor R2–R7, 3 notes R8–R10). Fix every finding in the plan and builder (`research/proto-2b2/plan/`). Keep the replay matching the prototype file for file (noise.json excepted, as before).

## Rulings

- **R1 (blocker):** Task 3 cannot run: every pair link in the archive's `noise-2b1` points at the deleted `Operator-2b1` worktree, and `case_noise` raises FileExistsError on the broken link. Move the noise pair-folder link fix (today's Task 9) before Task 3, or add the scripted relink (as the prototype's `excluded/relinks-2b2.json`) as an explicit Task 3 step; pick whichever keeps the patch order valid, and say in Task 3 that the archive links are dangling. Prove it on the replay: Task 3's `repeat` must record take 5 once and write `noise.json` without a crash; a rerun must not record take 6.
- **R2:** give the archive copy an explicit `cp -R` command and a `test ! -L` guard; say the archive is only ever read and copied, never moved or written; add the missing native build and backdrop prepare steps to Task 3.
- **R3 and D1 (user decision 2026-10-07, option A):** the median member's row is accepted for 2B.2. State in the D1 ruling and in Task 27 Step 9 that the still check covers only pinned groups (no 2A still scene has an unpinned mixed-size container), so it cannot catch a mixed-size regression; record per-glass materials in one layer (per-shape shader parameters) as a carry-in to project 3, where mixed-size components are built.
- **R4 and D3 (user decision 2026-10-07, option A):** edge-only morph tracking (the stack's top and bottom edges, `ymin` and `ymax`) is accepted for 2B.2. The Decisions list and the D3 ruling must say plainly that heart and bolt are not tracked individually, that the 20 old width measures were never judged so nothing judged was removed, and that per-glass tracking of the heart and bolt is a carry-in (2B.3 or a fix wave, once the noise floors show which morph failures matter).
- **R5:** disk. Free space is now about 83 GB (a duplicate 19 GB noise copy in the scratch worktree `Operator-2b2-h4` was deleted by the main session with the user's approval). Update Task 3's disk text with real numbers: the archive copy about 8.6 GB, Task 25 group A about 17 GB, the stop line at 40 GB free and the ask line at 45 GB; require `df -h` before the copy and before every group, and tell the executor to ask the user for space instead of deleting anything.
- **R6:** give Task 27's failed press check a stated action (reboot, re-check, record nothing until it passes), and say whether Task 27 may proceed while Task 26's stop rule is active (it may not run any scene Task 26 depends on).
- **R7:** after Task 3, require a recompute check with the final harness (a Task 25 or 27 step that recomputes the Task 3 cases with the final `lab.py` and compares to the Task 3 `noise.json`, listing any moved limit).
- **R8–R10 (notes):** state or fix each honestly in the plan.

## Process and rules

- Commit on `proto/2b2` only; every commit message ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Never push. Never touch `development` or the shared checkout except `git worktree add --detach` for the replay. No code comments. Never loosen a limit or measure. Never `git stash`. Delete only your own scratch worktrees.
- Keep context lean; use `sonnet` helpers for gate runs and the replay with exact commands.
- Check `df -h /Users/omaraly` before the replay; stop under 40 GB.
- At the end re-run the full replay onto a fresh `development` export (tip `5ddb25328`) and every gate: `flutter analyze` "No issues found!" and `flutter test` in packages/mobile, the package and its example; `python3 -m unittest discover tool/glass_lab/harness/tests` OK. Confirm `packages/` matches `proto/2b2` except `noise.json`.
- Do not start any native recording. Task 3's relink/`repeat` behaviour is proven on synthetic or copied small cases only (a throwaway directory), not by a full recording.

## Final report (short)

Proto tip; plan length; R1–R10 each fixed / stated with one line; gate lines; replay result (patches, runs, problems); anything you could not do; anything new that is truly the user's.
