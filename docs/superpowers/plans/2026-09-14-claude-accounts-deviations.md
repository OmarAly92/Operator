# Claude Accounts Implementation — Deviations from the Plan

## Commit trailer attribution (process, all tasks so far)

**What the plan said:** every commit message ends with
`Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` (plan's Global
Constraints, "Branch and commits").

**What happened:** each task was implemented by a fresh subagent, and several
subagents wrote their own model identity into the trailer instead of the
literal text the plan specifies:

- `2a30910c7`, `1cf1231c7` (Task 1) — `Claude Opus 5`, `Claude Haiku 4.5`
- `eb9751b18` (Task 2) — `Claude Sonnet 5`
- `b2b72ac60` (Task 3) — `Claude Opus 5`
- `19f02fcd0` (Task 4) — `Claude Sonnet 5`
- `4216330bb` (Task 5) — `Claude Sonnet 5`
- `4e074e2e0` (Task 6) — `Claude Sonnet 5`

**Why it happened:** subagent dispatch prompts quoted the plan's exact
trailer text, but each subagent's own system context separately instructs it
to attribute commits with its own running model's name, and that instruction
won this conflict for most tasks.

**What was done:** none of these commits were amended — the controlling
process (subagent-driven-development) forbids amending an already-reviewed
task commit; a fix-up would need its own commit, and rewriting six historical
commits' trailers only for cosmetic consistency was judged not worth the
history churn. From Task 7 onward, dispatch prompts now tell implementers
explicitly to use the trailer text **verbatim, character-for-character,
regardless of which model they are** — see whether this holds by Task 13.

**Cost if wrong:** none functionally — this only affects who git blame shows
as co-author on 6 commits. No behavior, test, or review outcome is affected.
