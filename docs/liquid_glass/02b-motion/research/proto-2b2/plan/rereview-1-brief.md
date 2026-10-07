# Scoped re-review of plan-2b2.md after fix round 1

You are an independent reviewer. You did not write the plan or the fixes. Change nothing in the plan or the prototype; write findings.

Worktree `/Users/omaraly/development/AI/Operator-2b2-proto`, branch `proto/2b2`, tip `6d815172b`. The plan is `docs/liquid_glass/02b-motion/plan-2b2.md` (11,025 lines, 41 patches, 27 tasks). The first review is `docs/liquid_glass/02b-motion/plan-2b2-review.md` (F1–F15). The fix brief with the rulings is `docs/liquid_glass/02b-motion/research/proto-2b2/plan/fixround-1-brief.md`. Spec: `docs/liquid_glass/02b-motion/spec.md` (binding). Rules: `docs/liquid_glass/ROADMAP.md` §4–§5.

Scope: only what changed since the first review (tip `4db370855`), plus whether each first-review finding is truly resolved. Use `git diff 4db370855..HEAD` and read plan sections only where the diff points.

## Check

1. **Each of F1–F15 and the notes: truly resolved, or only reworded?** For F1 (chained morph swap), F2 (16-shape cap), F4 (manifest keys) run the new tests and, where possible, a mutation: break the fix and confirm the new test fails.
2. **Replay and gates.** From a fresh `git worktree add --detach <scratch> development` (tip `5ddb25328`), apply the plan with its `plan/replay.py`, run every gate (`flutter analyze` "No issues found!" and `flutter test` in packages/mobile, the package, its example; `python3 -m unittest discover tool/glass_lab/harness/tests` OK) and report counts (the fix report claims app +2188, package +222, example +25, harness 253, replay 41 patches / 113 runs / 0 problems). Confirm `packages/` matches `proto/2b2` except `noise.json` (left to Task 3). Remove your scratch worktree when done.
3. **The fix round's own changes**, read for bugs (gotchas 37, 41, 42, 44, 46 in ROADMAP):
   - D5: geometry rebuilt in the frame a glass's anchor changes; space-origin anchor; Task 24b (a space's own move counts only when the glass's place in it also changed). Could app glass still spring when only its parent moves? Could glass miss a real move?
   - F2's guard: ghosts dropped before members in `gatherShapeData`; is dropping a ghost's glass visibly wrong (a glass vanishes instead of sinking)?
   - The `isTransient`, `syncMoved`/`shapesMoved` refactors: behaviour preserved?
4. **Departures from the user's decisions that the report discloses lightly. Judge each and say whether the plan frames it fairly; do not decide it:**
   - D3 asked for per-glass tracking for `material.morph`; the report says only the stack's top and bottom edges are tracked (heart and bolt are not). Is the manifest correction still honest? Are old and new counts side by side and do the new counts come from the same recordings (recompute them for merge normal and one Reduce Motion case)?
   - D1 (each member uses its own size's material) was built as the median member's row. What does that change for containers whose members differ in size, and does the plan's 2A still-check (Task 27) really catch a regression there?
   - F5: `material.respace` native scene and the executor's stop rule if native does not animate `spacing`.
5. **Execution risk for the new tasks** (3, 25, 26, 27): disk needs, reboot and press check (gotcha 49), capture-hole and touch gate, SIGINT-only stops, absolute paths, stale-build refusal, stop rules; would a fresh executor know what to do when a patch or an output does not match? Is anything in Task 3's scripted moves destructive on the archive `/Users/omaraly/development/AI/glass-lab-runs/2b1/` (it must only copy)?
6. **Rule compliance in the new diff:** no code comments, no whole-file `dart format`, commit messages end with the Co-Authored-By line, no measure or limit loosened (list any limit that moves), every fitted value tool-written (D4's 1.5 is disclosed as hand-placed).

## Output

Write the review to `docs/liquid_glass/02b-motion/research/proto-2b2/plan/rereview-1.md` in the worktree (uncommitted; do not commit). Header: what you ran, gate lines, replay result, and the verdict **"Ready to execute: yes / yes after fixes / no"**. Then numbered findings R1…, each with severity (blocker, major, minor, note), location, failure scenario, evidence, suggested fix; a list of which of F1–F15 are resolved; items that need a user decision; and what you did not check.

## Hard rules

Simulator only "iPhone 17 Pro (iOS 27)" UDID `708879DD-8B2A-4547-863F-F49EE1474D8B` named in every simctl command, never `booted`; prefer not to record at all. No downloads, no pip install, never `git stash`, never push, never touch the shared checkout `/Users/omaraly/development/AI/Operator`. Disk: check `df -h /Users/omaraly`; stop under 40 GB. Delete only your own scratch worktree. Be specific and short; keep your context lean.
