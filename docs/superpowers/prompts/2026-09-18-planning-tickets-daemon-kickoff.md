Implement the daemon half of the Planning Tickets feature by executing an existing implementation plan with subagent-driven development.

Read these first, in this order, end to end:
1. `AGENTS.md` (repository rules; the "API contract changes" and "Hard rules" sections are load-bearing).
2. `docs/superpowers/specs/2026-09-18-planning-tickets-design.md` (the approved design; sections 1, 2 including 2.6, 4, 5 and "Plan 1" in section 6).
3. `docs/superpowers/plans/2026-09-18-planning-tickets-daemon.md` (the plan you are executing; it has 12 tasks in file order 1, 2, 3, 4, 5, 6, 7, 7b, 7c, 8, 9, 10, with full code, tests and commands).

Process:
- Use the superpowers `subagent-driven-development` skill: one fresh subagent per task, in plan order, with the plan's spec review and code-quality review between tasks. Do not start Task N+1 until Task N's gate passed and its commit exists.
- Work on a branch `feat/planning-tickets-daemon` cut from `development` inside a git worktree (superpowers `using-git-worktrees`). Never commit to `development` directly and never touch `master`.
- Each task ends with its own conventional commit as written in the plan. End every commit message with the `Co-Authored-By` trailer your session's attribution reminder gives you.
- The plan's code is the reference, not gospel: if a generated name (sqlc struct field, existing helper signature such as `sessionView`, `respUnit` handling of a nil body) differs from what the plan assumed, adapt the plan's code to the real name and say so in the task report. Do not change tests to make an implementation pass; fix the implementation.
- No comments in code. Existing files keep the comments they have.
- Keep every change inside the plan's file map plus whatever compile errors force (for example test fakes that must gain a `SessionTicketRef` method in Task 8). No drive-by refactors.

Gates, run per task, then once more at the end:
- `cd backend && go build ./... && go test ./... && go vet ./... && gofmt -l internal` (gofmt must print nothing).
- After Task 1, Task 7b, Task 8 and Task 9: `npm run sqlc` and/or `npm run api` from the repo root as the plan says, then `cd backend && go test ./internal/httpd/...` and `cd frontend && npm run typecheck`; commit `openapi.yaml`, `frontend/src/api/schema.ts` and `sqlite/gen/*` together with the Go change.
- Final: `npm run lint` from the repo root and `go test -race` on the packages the plan names in Task 10.
- Green tests from a subagent are not proof by themselves: after Task 10 run the curl verification in Task 10 Step 4 against a real daemon yourself, with a shell whose environment has every `CLAUDE*` variable removed (`env | grep -i claude` must print nothing before you start the daemon). Use the `fake` harness for the assign step. Record the trimmed transcript in the report.

Report:
- Write `docs/superpowers/plans/2026-09-18-planning-tickets-daemon-report.md`: commit list, gate output summary, the curl transcript, every place you deviated from the plan and why, and anything left undone with the reason. Commit it with a `docs:` message.
- Do not merge. Leave the branch pushed to `origin` and stop; a separate review session merges.

If a task is blocked (a plan assumption is wrong in a way you cannot resolve by reading the cited file, or a gate fails for a reason outside the task), stop and report the exact error and the file:line you were looking at rather than working around it.
