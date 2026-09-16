Implement the de-fork plan for Operator using superpowers:subagent-driven-development.

Repository: /Users/omaraly/development/AI/Operator (branch `master`, clean). Create and work on branch `defork`.

Read, in this order, before dispatching anything:
1. /Users/omaraly/development/AI/Operator/CLAUDE.md and /Users/omaraly/development/AI/Operator/AGENTS.md
2. /Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-16-defork-design.md (the spec: what is inherited, with file:line evidence, and the shape decisions)
3. /Users/omaraly/development/AI/Operator/docs/superpowers/plans/2026-09-16-defork.md (the plan: 11 tasks, each with its own tests, gates and commit)

Rules that override anything a subagent might prefer:
- This is a removal. Nothing is replaced with a shim, feature flag, "compat" branch or TODO. When deleting something leaves a caller, delete the caller. When a test only existed to cover deleted behaviour, delete the test.
- No new code comments. Do not replace a deleted comment with a new one.
- Generated files are regenerated with `npm run sqlc` and `npm run api` from the repo root, never edited by hand, and committed with the Go change.
- Scope every `grep -r` with `--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=target --exclude-dir=.worktrees --exclude-dir=.claude --exclude-dir=build --exclude-dir=.dart_tool`; nested worktrees inside this checkout hold stale copies of tracked files.
- Do not touch LICENSE, NOTICE, README "Acknowledgements", DESIGN.md, packages/terminal, or any docs/superpowers file the plan does not name. The `~/Projects/agent-orchestrator` reference in DESIGN.md/CLAUDE.md is the user's other app, not upstream.
- One commit per task with the message the plan gives, ending in `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. Do not merge, tag or push.
- Gates per task are listed in the plan; a task is not done until its gate output is pasted into the task report. Task 11's repo-wide sweep grep must print nothing.

Environment notes:
- Go, Rust 1.96.0 with the wasm32 target, Node 24, Flutter 3.44.5 are installed. `cd frontend && npm test` runs `terminal:build` first (wasm + ts); that is expected and takes a minute.
- If any shell you open was launched from a Claude session, unset every `CLAUDE*` environment variable before running the app (not needed for the gates).

When all 11 tasks are committed, write the final report to /Users/omaraly/development/AI/Operator/docs/superpowers/reports/2026-09-16-defork-report.md exactly as Task 11 Step 4 describes (commit list, sweep command + empty output, every gate command with its summary line, migrations added, anything left out and why), then stop. The reviewing session verifies every claim independently before merging.
