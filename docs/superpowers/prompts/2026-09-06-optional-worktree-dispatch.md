Execute the optional-session-worktree implementation plan: make the per-session git worktree a user choice on the two manual spawn surfaces, defaulting to off.

## Start here

Read these two documents in full before doing anything else:

- Plan: `docs/superpowers/plans/2026-09-06-optional-session-worktree.md` — 12 tasks, 68 checkboxes
- Spec it implements: `docs/superpowers/specs/2026-09-06-optional-session-worktree-design.md`

Then read `AGENTS.md` and `CLAUDE.md` at the repo root. `AGENTS.md` covers `backend/` and `frontend/`; `CLAUDE.md` covers `packages/mobile`.

## What this builds

A session can now run **in the project's own checkout** instead of an isolated worktree. The choice is a checkbox in the desktop task composer and a switch on the mobile spawn screen, **default off** — so the common manual case no longer creates a worktree. `opr session spawn`, orchestrator-spawned workers and reviewers are unchanged and still get worktrees.

The mechanism: a `domain.WorkspaceMode` (`worktree` | `in_place`) recorded on the session row and threaded through `ports.WorkspaceConfig` / `ports.WorkspaceInfo`, a new `inplace` workspace adapter whose teardown primitives are no-ops, and a workspace router that picks the adapter by mode first and project kind second.

## Execution method

Use **superpowers:subagent-driven-development**. One fresh subagent per task, two-stage review between tasks. Do not batch tasks into one agent — Task 7 is a safety gate and every task must be independently rejectable.

Work in a git worktree via **superpowers:using-git-worktrees**. Branch from `master` at `3463b4a76`.

Tick each `- [ ]` checkbox in the plan file as its step completes, and commit the plan file's checkbox updates along with the task's own commit.

Tasks 1–8 are strictly sequential; each consumes the one before. Tasks 9, 10 and 11 depend only on Task 8 and on nothing from each other, so they may be dispatched in parallel. Task 12 runs last.

## Repository state as of dispatch

- Repo: `/Users/omaraly/development/AI/Operator`, branch `master`, HEAD `3463b4a76`, working tree clean, 2 commits ahead of `origin/master`.
- Go 1.25.12, golangci-lint 2.12.2, Flutter 3.44.5.
- `cd backend && go build ./...` succeeds at HEAD.
- No implementation code for this feature exists yet — only its spec, plan and this prompt.

**`master` has moved since this feature was planned.** The phase-4 ACP removal merged at
`8d6b6a899`, and the plan has been re-synced against it. A later spawn fix (`3463b4a76`)
touched the Claude Code adapter and daemon wiring but left every anchor in this plan
intact; it is verified current at `3463b4a76`. What that merge changed under
this feature's feet, already accounted for in the plan:

- **Migration `0101` is taken** by `0101_drop_conversations.sql`. This feature's
  migration is **`0102_session_workspace_mode.go`**, registered as
  `102:` in the burned-versions map.
- `domain.SessionMode` and the whole chat/conversation vocabulary are gone. `Spawn`
  (now `manager.go:518`) no longer branches on mode, and `seedRecord`
  (`manager.go:2560`) no longer sets a `Metadata` field at all — Task 6 adds one.
- The `conversation*` and `session_interface_transition*` tables were dropped, so
  Task 2's clear-list omits them.
- `queries/sessions.sql` select lists moved to lines 8, 25, 44, 56 and 68.
- Mobile lost its `chat` feature and gained `dictation` and `usage`. The spawn screen,
  its params class and the stale isolation copy at `spawn_body.dart:156` are all
  unchanged and still match the plan.
- The workspace router is constructed at `backend/internal/daemon/lifecycle_wiring.go:177`
  and the same `ws` value is passed to `sessionIDClaimProbe` on the following line —
  Task 7 Step 3 covers both.

## The migration destroys data on purpose

Task 2 adds `sessions.workspace_mode` as `TEXT NOT NULL CHECK (workspace_mode IN ('worktree','in_place'))` **with no `DEFAULT`**, and clears session-scoped tables rather than backfilling. This is an explicit user decision: Operator is pre-release, and a defaulted column is a fallback that outlives its reason.

Measured impact on this machine, so you know what you are destroying:

- `~/.operator/data/opr.db` — goose 100, **0 sessions**, 1 project. Nothing to lose.
- `~/.operator/dev/data/opr.db` — goose 100, **12 sessions (10 live)**. This is the database the desktop app runs against.
- All 12 are **scratch-project sessions with no branch**, so no git branch and no commit is lost. Their plain directories under `~/.operator/dev/data/worktrees/scratch/` (72K total) are orphaned on disk and can be deleted by hand afterward.
- Older databases at `dev-appskin` (goose 87), `dev-task13` and `sdd-task13` (goose 92) are stale and irrelevant.

**Do not soften this.** If SQLite refuses `ALTER TABLE ... ADD COLUMN ... NOT NULL` without a default, the plan's prescribed fix is a table rebuild — never adding a `DEFAULT`. Adding one silently reintroduces the fallback the user rejected.

## Hard rules

1. **No comments.** The user's global instruction: never add explanatory comments to code. This applies to Go, TypeScript and Dart alike.

2. **`in_place` teardown must never touch the filesystem.** `Destroy`, `ForceDestroy`, `StashUncommitted` and `ApplyPreserved` on the in-place adapter are no-ops. No `os.RemoveAll`, no `git worktree remove`, no `git worktree prune`, no preserve ref. This is the whole safety property of the feature: the path in question is the user's actual repository.

3. **The dangerous caller is `SaveAndTeardownAll`, not `Kill`.** It runs at daemon shutdown over every live session and calls `StashUncommitted` then `ForceDestroy` (`backend/internal/session_manager/manager.go:1709`). `ForceDestroy` bypasses git's dirty check and falls back to `os.RemoveAll`. It currently cannot reach a project directory only because `gitworktree.validateManagedPath` refuses first — that refusal is a backstop in the wrong layer and must not be what you rely on. Task 7 pins both paths with sentinel-file assertions; if either test is hard to write, stop and report rather than weakening the assertion.

4. **No `WithDefault()` on `WorkspaceMode`.** `domain.ProjectKind` has one; this type deliberately does not. An empty mode reaching the workspace layer is a programming error and must error. The single legitimate default is at the HTTP boundary, where an omitted `workspaceMode` on `POST /api/v1/sessions` resolves to `worktree` — that keeps CLI and orchestrator spawns unchanged.

5. **`golangci-lint` produces phantom failures from a stale cache.** Nested worktrees under `.worktrees/` and `.claude/worktrees/` leave deleted paths in its cache and it will report issues in files that do not exist. Run `golangci-lint cache clean` and re-run; **only the post-clean result counts.** This has bitten several previous agents in this repo.

6. **Repo-wide `grep`/`find` from the root is unreliable.** `.worktrees/`, `.claude/worktrees/` and sibling `../Operator-*` checkouts hold stale duplicate copies of tracked files, including old `AGENTS.md` versions. Scope every search to `backend/`, `frontend/src/`, `packages/mobile/lib/`, `packages/mobile/test/` — or exclude those paths explicitly. A grep that "finds a remaining reference" in a worktree path is a false positive.

7. **Use the repo's script wrappers.** `npm run lint` (root) = backend `go test ./...` + golangci-lint. `npm run sqlc` after touching `queries/` or a migration. `npm run api` after touching the API shape — and commit the regenerated `frontend/src/api/schema.ts`. From `frontend/`: `npm run typecheck`, `npm run frontend:lint`. **`frontend` has no `build` script** — do not invent one.

8. **`flutter analyze` must print exactly `No issues found!`.** Warnings are failures. Run it and `flutter test` from `packages/mobile`.

9. **Mobile conventions are not negotiable.** Cubit only, never `Bloc` with events. No `freezed`, no `json_serializable` in first-party code — models are hand-written with nullable fields. One params class per method under `data/model/params/`. Feature code never imports `flutter_screenutil`. User-facing copy is inline English, no `LocaleKeys`.

10. **Never restart the Operator daemon from your shell.** An agent shell leaks `CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_MESSAGING_SOCKET`, `ANTHROPIC_BASE_URL` and roughly thirty other variables into any agent the daemon spawns, and the spawned agent dies within 300ms. Live verification is the user's step — see "Where to stop".

## Things the plan assumes that you must verify, not invent

The plan names several test fixtures by their role rather than their exact identifier, because they differ across files. Read the surrounding test file and use what is already there; **do not create a second helper that duplicates an existing one**:

- `newTestManager` / `fakeWorkspace` in `backend/internal/session_manager/manager_test.go` — extend the existing fake with the counters the plan asks for (`lastCreateConfig`, `destroyCalls`, `forceDestroyCalls`, `stashCalls`) and make its `Create` echo `cfg.Mode` back on the returned `WorkspaceInfo`.
- `openMigratedTestDB` in `backend/internal/storage/sqlite/` — reuse whatever `migrate_clear_data_test.go` already uses.
- `doRequest` / the spawn-recording fake in `backend/internal/httpd/controllers/sessions_test.go`.
- `renderComposer`, `renderBoard` and the session factory in the two frontend test files.

Two places where the plan tells you to read before writing rather than handing you code: the `addExclude` implementation in the in-place adapter (mirror `gitworktree`'s, resolving `git rev-parse --git-dir` so it works in a normal checkout as well as a worktree), and `ObserveWorkspace` (reuse `gitworktree`'s plumbing — an in-place session's diff and status are real and must be reported honestly).

`queries/sessions.sql` has several near-identical `SELECT` column lists (around lines 8, 25, 74, 86, 98). **All of them** must gain `workspace_mode`, or sqlc generates a struct that silently drops it.

## Where to stop

Stop after Task 12 Step 1 — the full gate run:

```
npm run lint
npm run frontend:typecheck
cd backend && go test -race ./...
cd packages/mobile && flutter analyze && flutter test
```

Task 12 Steps 2 and 3 are **manual smoke tests the user runs**, because they require launching the daemon and the desktop app, which you must not do (rule 10). Leave those two checkboxes unticked and say so explicitly in your final report.

Do Task 12 Steps 4 and 5 (the docs update) yourself.

## Final report

Report back with:

1. Which tasks landed, with their commit SHAs.
2. The exact output of each of the four gate commands.
3. Anything you had to deviate from the plan on, and why. Deviations are expected — the plan was written from reading the code, not from running it. Say so plainly rather than papering over a mismatch.
4. Any place where a test was weaker than the plan intended, especially in Task 7.
5. Confirmation that no `DEFAULT` was added to `workspace_mode` and no `WithDefault()` exists on `WorkspaceMode`.

Do not open a PR. Do not push. The user reviews the branch first.
