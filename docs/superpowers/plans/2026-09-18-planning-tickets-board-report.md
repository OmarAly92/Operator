# Planning Tickets: Board and Ticket Page — Implementation Report (plan 2 of 3)

**Branch:** `feat/planning-tickets-board`, cut from `origin/development` @ `1f19bfe16` (which already contains plan 1's merge at `25b6ebe24`).
**Worktree:** `/Users/omaraly/development/AI/Operator-planning-tickets-board` (outside the main checkout, per `CLAUDE.md`'s "nested worktrees poison repo-wide search" rule).
**Process:** superpowers `subagent-driven-development` — one fresh implementer subagent per task, in plan order, with a task-scoped spec + quality review after each. Ledger: `.superpowers/sdd/2026-09-18-planning-tickets-board/progress.md` (not committed; git-ignored SDD workspace).

## Commit list

| Task | Commit | Subject |
|---|---|---|
| 1 | `bcd7df3b3` | feat(tickets): add i18n message catalogue |
| 2 | `d503e6b90` | feat(tickets): plan and ticket status presentation, ticket route templates |
| 3 | `ef5b5ea3b` | feat(tickets): ticket queries, live updates and mutations |
| 4 | `065ec12a5` | refactor(renderer): extract MarkdownBody and TaskModelPicker for reuse |
| 5 | `f45ebd05e` | feat(tickets): role fields, create/plan/review sheets and merge confirmation |
| 6 | `c20262ca2` | feat(tickets): plan rows, ticket page and route |
| 7 | `e0aa16198` | feat(tickets): ticket badge on session cards and the session topbar |
| 8 | `a490d6f82` | feat(tickets): ticket cards, PLANNED column and five-column board |
| 9 | `370802b64` | feat(tickets): done and archived tickets in the archive bar with Reopen |

Every commit carries `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. All nine task reviews returned "Task quality: Approved" with no Critical or Important findings requiring a fix loop — no task needed a fix round.

## Gate output summary

Baseline (before Task 1, on the freshly created worktree): `npm run typecheck` clean, `npm run frontend:lint` 0 errors, `npx vitest run --config vite.renderer.config.ts` 126 files / 1449 tests passed.

Per-task gates all passed (Task 5 ran only lint + vitest per its plan-mandated exception — its sheets call `useNavigate()` to the route Task 6 creates; Task 6 restored and passed the full gate over both tasks together).

Final whole-branch gate, run by the controller (not a subagent) from a clean tree at HEAD `370802b64`:

```
cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts
```

- `npm run typecheck`: clean (rebuilt `packages/terminal` first, no `package-lock.json` drift left behind).
- `npm run frontend:lint`: 0 errors, 150 pre-existing warnings (same warning set as the pre-Task-1 baseline; nothing new).
- `npx vitest run --config vite.renderer.config.ts`: **134 files / 1498 tests passed.**
- `git status --short` after the gate run: clean (no uncommitted drift).

## Real-app verification: not performed

Task 10 Steps 2–7 (start a scrubbed-env dev daemon on `127.0.0.1:3002`, create a ticket via curl, screenshot the board window, verify the planning-session badge, verify the ticket page) were **not completed**. What happened:

1. Port 3002 was already served by a long-running, **actively used** dev daemon (PID 90267, up ~13.5h at the time, supervising multiple real live agent sessions such as `scratch-10`, `scratch-27`, `scratch-29`, `tbm-online-coaching-flutter-1`). The plan's own Step 2 says "if port 3002 is already served by another dev daemon, stop" — this was flagged to the user rather than silently working around it, since touching a live daemon with real running sessions is a side effect outside this worktree.
2. The user asked to proceed and free the port; after checking twice the daemon was still the same PID, and the user then said to use it as-is for verification.
3. Curl calls against that daemon (`POST .../tickets`) returned `404 ROUTE_NOT_FOUND` — that daemon is running a backend build from **before** plan 1 merged, so it has no ticket routes at all. A throwaway project (`id: board-smoke-repo`, registered at `/private/tmp/claude-501/.../scratchpad/board-smoke-repo`) was created on it before this was discovered; it is harmless (empty throwaway repo, no work done in it) but there is no project-delete route, so **the reviewer or user should remove this stale project registration from `~/.operator/dev/data` by hand** if it matters.
4. The user then asked to just start a fresh scrubbed-env `tauri:dev` from this worktree. That build failed on its first attempt: `frontend/src-tauri/build.rs` panicked with `resource path ../agent-browser doesn't exist` — this worktree never had `npm run browser-runtime:prepare` run (it fetches a pinned vercel-labs `agent-browser` binary release, not part of `npm install`). That was run (`Prepared browser automation runtime for darwin-arm64`) and the build was restarted.
5. Before the second build/verification pass completed, the user asked to stop and get this report for a separate review session instead. All dev-server/build processes started for this worktree were killed cleanly; `curl http://127.0.0.1:3001/readyz` (installed app) and `http://127.0.0.1:3002/readyz` (the pre-existing dev daemon, PID unchanged) were both re-confirmed untouched and unchanged before writing this report.

**Ticket page: not verified in the window** (plan's own stated fallback for this exact case, Task 10 Step 6).
**Board/PLANNED column in a live window: not verified.**
**Planning-session badge: not verified.**

No screenshots were captured. The only evidence of correctness for this plan is the per-task subagent reviews (spec + quality, all Approved) and the final whole-branch gate above — Vitest coverage for the ticket page (Task 6), the board/PlannedColumn (Task 8), and the archive bar (Task 9) is real and passing, but it is not a substitute for seeing the running app.

## Deviations from the plan

None beyond what each task's own review already recorded as adaptations to real code (see the ledger for per-task detail); no task changed a test to fit a wrong assumption — every deviation found during review was either the implementer correctly adapting to real signatures/props, or a cosmetic/minor gap parked below.

## Parked / deferred findings (from task reviews, none blocking)

- **Task 3** (minor, ruled): `lib/ticket-events.ts` duplicates `lib/event-transport.ts`'s SSE/debounce/retry/base-URL-rebind pattern. This is prescribed verbatim by the plan's own Task 3 code block, not the implementer's invention, and a shared extraction is outside this plan's file map. Ruling: left as-is.
- **Task 4** (minor): the new `MarkdownBody` import in `SessionInspector.tsx` landed one line off from the brief's "beside the other `./` imports" grouping — cosmetic, no functional effect.
- **Task 5** (minor): `CreateTicketSheet.tsx`'s reset effect depends on `projects` by array reference, not a stable key — inherited from the brief's own prescribed code; a future caller passing a freshly-computed `projects` array on every render while the sheet is open could reset the user's selection. Worth watching if a later plan wires this sheet from a non-memoized source.
- **Task 6** (minor): `PlanRow.tsx` renders an enabled "Session no longer exists" button that still fires a dead `onOpenSession` navigation when `sessionId` points at a missing session — should be disabled instead.
- **Task 6** (minor): the brief listed `dotGlow`/`useNavigateToSession` as consumed interfaces; `TicketPage.tsx` hand-rolls its own navigator and skips the `dotGlow` halo convention instead. Functionally harmless; the implementer's own report incorrectly claimed "no deviations."
- **Task 8** (minor): a pre-existing (not introduced by this branch) comment in `BoardEmptyStates.tsx` references "four empty columns," now stale at five columns.
- **Task 9** (minor): `ArchiveTicketItem`'s Reopen tooltip doesn't swap to a "restoring…" label while `setArchived.isPending`, unlike the `ArchiveRestoreButton` pattern it otherwise matches exactly (the spinning icon still communicates pending state). Also no unit test for the mutation-error path or the pending-disabled state specifically — low risk since the component mirrors the already-tested `ArchiveRestoreButton`/`ArchiveRestoreError` pattern.

None of the above were judged load-bearing for later work; none blocked a task's own review approval.

## Anything left undone

- **Real-app / window verification (Task 10 Steps 2–7), as detailed above.** This is the only substantive gap. A stale throwaway project `board-smoke-repo` may need manual removal from `~/.operator/dev/data` (no delete route exists).
- No whole-branch code-review pass (the plan's own "Self-review" section, and a final broad reviewer per the `subagent-driven-development` skill) was run before this report was written — the user asked to stop and hand off to a separate reviewer session instead of completing it here.

## Not merged

This branch has not been merged and **has not yet been pushed** to `origin` either — the user interrupted before Step 8's `git push`. A separate review session should review, verify against a real (current-build) daemon, and merge, per this plan's own instructions.

## Planner review (2026-09-18, separate session)

Whole-branch read of every new file plus the diffs into `SessionsBoard.tsx`, `ShellTopbar.tsx`, `useWorkspaceQuery.ts`, `event-transport.ts` and `api-client.ts`, then a live verification of the real renderer against a real daemon.

### Live verification

The dev port `3002` belongs to the user's running daemon, so the review used an isolated daemon: `opr` built from this branch's `backend/` (unchanged from `development`), started with `env -i HOME PATH` plus `OPERATOR_DATA_DIR`/`OPERATOR_RUN_FILE`/`OPERATOR_PORT=39311`, and a throwaway `single_repo` project `repo`. The renderer was served from this worktree with `vite --host --port 5180` and `OPERATOR_DEV_API_TARGET=http://127.0.0.1:39311`, and driven in a browser at `http://127.0.0.1:5180` (the origin must be `127.0.0.1`, not `localhost`: the daemon's CORS allow-origin is `tauri://localhost`, so a `localhost` page origin fails; a same-origin page proxies through Vite and works). This is the recipe for future renderer verification without the Tauri window.

Verified end to end in that renderer, all against the real daemon:
- Five columns; PLANNED first; `No tickets yet` empty state; `+` opens the create dialog; creating `Search page` navigated to the ticket page with `spec.md` previewed.
- `ticket.md` preview shows the frontmatter table (`title`, `brief`, `created`); a plan file renders GFM (task list, table).
- `PUT …/file` for two plans and a kickoff file: the ticket page updated live over `tickets_changed` (status `Draft` → `Ready`, rows `01 Index`, `02 UI`, nested `Kickoff prompt`).
- `Mark done` on `02 UI` → `POST …/plans/02-ui.md/done` 200 → row `Done` (after the fix below).
- `Plan with agent` → agent picker, model picker (Haiku), extra → `POST …/plan` 201 → navigated to the planning session; the board card read `Planning` with the live dot and `Open planning session`; the session card carried the badge `search-page · plan`; the daemon record had `ticket: {slug, role: planning}`.
- `assign` via curl (haiku, `force: true`) → the card updated live over the CDC path to `1/2 merged`, `01 Index · Working`, session link, `Review`.
- `Review` → sheet with `Planning session | New session`, submit → `POST …/review` 200 → navigated to the planner.
- `merge-ready` via curl → card status `Waiting for your confirmation`, block `01 Index · Awaiting your merge` with the markdown summary and `Merge` → confirm dialog with the summary → `POST …/merge` 200 → row `Merging`, board stayed on the board (see fix 2).
- Ticket page cold load at `#/projects/repo/tickets/search-page?file=plans%2F01-index.kickoff.md` opened the kickoff file; `Archive` → `Archived`; board archive bar listed `Board smoke · Done` and `Search page · Archived` alongside sessions; `Reopen` → unarchived and navigated to the ticket page.
- Both smoke sessions were killed, the isolated daemon stopped; the user's daemons on `3001` and `3002` answered `/readyz` unchanged throughout.

### Fixes made during review

1. **Every plan action was broken against the real daemon.** The UI sent `plan.file` (`plans/01-index.md`) as the `{plan}` path segment; openapi-fetch encodes it as `plans%2F01-index.md`, chi hands the handler the still-escaped segment, and `findPlan` answered `TICKET_PLAN_NOT_FOUND` (reproduced with curl). `useTicketMutations` now sends `planParam(file)`, the bare file name the route documents (`dto.go` `TicketPlanParam`), for review, merge and done; unit test added.
2. **Clicks inside the card's dialogs navigated to the ticket page.** React synthetic events bubble through portals, so `PlanWithAgentSheet`, `ReviewPlanSheet` and `MergeConfirmDialog` inside the `role="button"` card fired the card's `onClick`. Reproduced by adding `expect(navigateMock).not.toHaveBeenCalled()` to the merge test (failed on the original code); the dialogs now sit in a wrapper that stops click and key propagation.
3. **Invisible accent text.** `text-accent`/`bg-accent/12` resolve to `rgba(255,255,255,0.06)` in this theme, so the `TicketBadge` and the card's `Plan with agent` action were unreadable. The badge now uses the bordered chip look of the Claude-account chip; the action uses `text-foreground`. (The pre-existing intake-issue chip at `SessionsBoard.tsx:1081` has the same problem and is left as is.)
4. `CreateTicketSheet` reset its project selection whenever the board re-rendered because the effect depended on the `projects` array identity; it now depends on the first project id.
5. `PlanRow` disables the session link when the session no longer exists instead of navigating to a dead route.
6. `supportsTickets` on the root board is `ticketProjects.length > 0`, so a workspace with only scratch projects gets the repo hint instead of an enabled `+` that opens an empty dialog.
7. Layout: card footer and status row wrap instead of clipping (`Open planning session` / `Open`, `Waiting for your confirmation` next to the project chip); ticket page footer wraps.

Gates after the fixes: `npm run typecheck` clean, `npm run frontend:lint` 0 errors (150 pre-existing warnings), vitest 134 files / 1499 tests.

### Left for later

- On macOS the shell topbar is hidden on session routes, so the topbar badge (Task 7) only shows on Windows/Linux, like the branch and status pill it sits beside. The board card badge and the sidebar cover macOS.
- The ticket page has no breadcrumb back to the board on macOS (the same platform gap); the sidebar project row gets there.
- The stale `board-smoke-repo` project the implementing session registered on the user's daemon at `3002` is still there (no delete route).
