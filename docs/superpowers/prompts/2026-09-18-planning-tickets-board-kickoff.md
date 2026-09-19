Implement the board and ticket-page half of the Planning Tickets feature (plan 2 of 3) by executing an existing implementation plan with subagent-driven development.

Read these first, in this order, end to end:
1. `AGENTS.md`, `CLAUDE.md` (the "clone agent-orchestrator verbatim" rule and the branch rule are load-bearing) and `DESIGN.md`. The design reference `~/Projects/agent-orchestrator/packages/web/src` is a different app, not this repository.
2. `docs/superpowers/specs/2026-09-18-planning-tickets-design.md` (sections 1.3, 2.6, 3, 4, 5 and "Plan 2" in section 6).
3. `docs/superpowers/plans/2026-09-18-planning-tickets-board.md` (the plan you are executing: ten tasks in file order 1 to 10, with full code, tests and commands).
4. `docs/superpowers/plans/2026-09-18-planning-tickets-daemon-report.md`, "Planner review" and "Curl verification" sections, for the daemon contract that already exists on `development`.

Baseline: `origin/development` at commit `c29f21279` or later. Run `git fetch origin` first; the daemon half (routes under `/api/v1/projects/{id}/tickets…`, `frontend/src/api/schema.ts` with `TicketView`/`PlanView`/`SessionTicketRef`, `ticket_updated` in `lib/event-transport.ts`) is already merged there. Do not change anything under `backend/`.

Process:
- Use the superpowers `subagent-driven-development` skill: one fresh subagent per task, in plan order, with the plan's spec review and code-quality review between tasks. Do not start Task N+1 until Task N's gate passed and its commit exists.
- Work on a branch `feat/planning-tickets-board` cut from `origin/development` inside a git worktree (superpowers `using-git-worktrees`). Put the worktree outside the checkout (for example `../Operator-planning-tickets-board`): worktrees inside `.worktrees/` or `.claude/worktrees/` poison repo-wide search (`CLAUDE.md`). Never commit to `development` directly and never touch `master`.
- Each task ends with its own conventional commit as written in the plan. End every commit message with the `Co-Authored-By` trailer your session's attribution reminder gives you.
- The plan's code is the reference, not gospel: if an existing signature differs from what the plan assumed (a prop name on `RequiredAgentField`, an openapi-fetch body type, a Testing Library query that returns two elements), adapt to the real code and say so in the task report. Do not change tests to make an implementation pass; fix the implementation. Do not relax a test's expected copy; the English strings come from the Task 1 catalogue.
- No comments in new code. Existing files keep the comments they have; code moved in Task 4 keeps its comments.
- Keep every change inside the plan's file map plus whatever compile errors force. No drive-by refactors, no new dependencies, no dnd-kit, no editor (those are plan 3).
- Every new component follows `DESIGN.md` and the agent-orchestrator look and is built from `components/ui/*` primitives and the tokens the plan names. If you need a class the plan does not name, take it from a sibling component the plan cites (for example `SessionCard`, `ZoneColumn`, `ConfirmDialog`), not from memory.

Gates, run from `frontend/` per task, then once more at the end:
- `npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`. Task 5 is the one exception the plan states (lint and vitest only; Task 6 restores the full gate).
- `npm run typecheck` rebuilds `packages/terminal` first. If it modifies `packages/terminal/package-lock.json`, `git checkout -- packages/terminal/package-lock.json` before committing.
- The i18n gates are part of the vitest run: `src/renderer/i18n/renderer-coverage.test.ts` (no hardcoded English in JSX) and `src/renderer/i18n/instance.test.ts` (every locale has every key with matching `{{placeholders}}`). Every user-visible string goes through `t()`.
- Task 6 regenerates `frontend/src/renderer/routeTree.gen.ts` through the router Vite plugin when vitest runs; commit it with the route.
- Green tests from a subagent are not proof by themselves. After Task 9, run Task 10 yourself, not through a subagent: start `npm run tauri:dev` from `frontend/` with every `CLAUDE*` variable removed exactly as Task 10 Step 2 shows (`env | grep -i '^claude' ` must print nothing in that shell before the start), confirm the dev daemon is on `127.0.0.1:3002` and that the installed app's daemon on `:3001` is never touched, drive the daemon with the curl commands in Task 10 Steps 3 and 5, capture the window with `screencapture -x -l<CGWindowID>` as the memory recipe describes, and kill the planning session you spawned. Editing an i18n JSON while the app is open blanks the Tauri window; Task 1 lands the catalogue before the app is ever started, so do not touch the catalogues after launching.
- Do not attempt to click or type into the Operator window; that is not available from a session. Record "ticket page: not verified in the window" if that is the truth.

Report:
- Write `docs/superpowers/plans/2026-09-18-planning-tickets-board-report.md`: commit list, gate output summary, the curl transcript, the screenshot file names and what each shows, every deviation from the plan and why, and anything left undone with the reason. Commit it with a `docs:` message.
- Do not merge. Push the branch to `origin` (`git push -u origin feat/planning-tickets-board`) and stop; a separate review session reviews, verifies on a real daemon and merges.

If a task is blocked (a plan assumption is wrong in a way you cannot resolve by reading the cited file, or a gate fails for a reason outside the task), stop and report the exact error and the file:line you were looking at rather than working around it.
