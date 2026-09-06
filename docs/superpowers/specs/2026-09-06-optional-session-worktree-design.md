# The worktree becomes a choice

Status: Design approved, unimplemented
Date: 2026-09-06
Scope: `backend/internal`, `frontend/src/renderer`, `packages/mobile`

Today every session owns an isolated workspace. This design makes that a decision the
user makes per session, on the two surfaces where a human creates one by hand: the
desktop task composer and the mobile spawn screen. On both, the control defaults to
**off** — the session runs in the project's own checkout, on whatever branch is
already there.

Every other spawn path is unchanged. `opr session spawn` and orchestrator-driven
worker and reviewer spawns still create a worktree.

## Why

Isolation is the right default for an agent working unattended in parallel with
others. It is the wrong default for the case the user actually has in hand most
often: sitting at a project, wanting an agent to work on it the way they would run
the CLI themselves — in the repo, on the branch they are already on, seeing the
changes in the editor they already have open.

The current model has no way to express that. A manual session gets a worktree in
Operator's managed root, on a generated branch, and the user's own checkout never
sees the work.

## The user-visible contract

Two modes, named end to end:

- **`worktree`** — today's behavior, unchanged. A `git worktree` on a generated
  branch under the managed root.
- **`in_place`** — the agent runs in `project.Path`, on the branch already checked
  out there. No branch is created. Nothing is created. **Nothing is destroyed.**

`in_place` applies to `single_repo` projects only. Multi-repo `workspace` projects
always get their per-repo worktrees; `scratch` projects never had a worktree, so the
control does not appear.

Concurrency is not policed. Two in-place sessions on one project, plus the user's own
terminal, may all write the same files on the same branch. This is deliberate: the
mode's whole premise is that Operator stays out of the way.

## Why a mode on the session, not a boolean on the project

`Kill` reconstructs the workspace from the session row through `workspaceInfo(rec)`
([`manager.go:4003`](../../../backend/internal/session_manager/manager.go)) and hands
it to the router, which today selects an adapter **by project kind alone**
(`adapterForProject`,
[`router.go:152`](../../../backend/internal/adapters/workspace/router/router.go)).
Once one project can hold sessions of both modes, the project no longer answers
"which adapter?".

Two alternatives were rejected:

- **Infer at teardown** — treat `ws.Path == project.Path` as in-place. No new state,
  but it reconstructs a safety-critical decision from a path comparison, and a
  symlinked or relocated project makes it wrong. The destroy path is the last place
  that should hold a heuristic.
- **A `NoWorktree` boolean** — identical wiring, worse naming, and a third mode later
  means a second boolean and an illegal fourth state.

So the mode is recorded on the session and the router keys off it.

## Backend

### The mode

`domain.WorkspaceMode` with values `worktree` and `in_place`. Deliberately **no
`WithDefault()`**, unlike `domain.ProjectKind`: that helper exists to absorb rows
predating a column, and this design leaves no such rows behind (see the migration
below). An empty mode reaching the workspace layer is a programming error and is
rejected, not silently coerced. It is carried on:

- `ports.SpawnConfig` — the request.
- `ports.WorkspaceConfig` — what the adapter is asked to build.
- `ports.WorkspaceInfo` — what teardown is handed. This is the load-bearing one.
- `domain.SessionMetadata` as `WorkspaceMode` — the durable record.

`SessionMetadata` is **not** a JSON blob: its fields are individual columns on
`sessions` (`branch` and `workspace_path` land at
[`0001_init.sql:38`](../../../backend/internal/storage/sqlite/migrations/0001_init.sql)).
So this needs a migration, the query updates, and `npm run sqlc`.

**The migration clears session data rather than defaulting it.** Operator is
pre-release with no installs to preserve, and a defaulted column is exactly the kind
of fallback that outlives the reason for it: every later reader would have to keep
answering "what does empty mean?". Migration `0102_session_workspace_mode.go` follows
the precedent of
[`0094_clear_pre_release_data.go`](../../../backend/internal/storage/sqlite/0094_clear_pre_release_data.go)
— a Go migration that deletes session-scoped rows, then adds

```sql
workspace_mode TEXT NOT NULL CHECK (workspace_mode IN ('worktree', 'in_place'))
```

with no `DEFAULT`. Every surviving row must name its mode explicitly, and the database
refuses anything else. Existing sessions and their worktrees on disk are orphaned by
this; that is the accepted cost of the clean column. It must also be registered in the
burned-versions registry in
[`migrate_burned_versions_test.go`](../../../backend/internal/storage/sqlite/migrate_burned_versions_test.go)
as `102: "0102_session_workspace_mode.go"`.

### The in-place adapter

New package `internal/adapters/workspace/inplace`, implementing `ports.Workspace` and
`ports.WorkspaceObserver`.

- `Create` — verifies `project.Path` exists and is a git work tree, resolves the
  currently checked-out branch for display, and returns
  `WorkspaceInfo{Path: project.Path, RepoPath: project.Path, Branch: <current>}`. It
  creates nothing. Unlike `scratch.Create`, a non-empty directory is expected, not
  `ErrWorkspaceDirty`.
- `Restore` — re-resolves the same values. Nothing to re-materialize.
- **`Destroy`, `ForceDestroy` — no-ops returning nil.** They must never call
  `removeAll`, `git worktree remove`, or `git worktree prune`.
- **`StashUncommitted` — returns `("", nil)` unconditionally.** The user owns this
  directory and its uncommitted state; Operator does not move it to a preserve ref
  behind their back.
- `ApplyPreserved` — no-op, since nothing is ever preserved.
- `AddExclude` — writes to `.git/info/exclude` as the git adapter does, so spawn
  attachments stay out of `git status`.
- `ObserveWorkspace` — delegates to the same git plumbing the worktree adapter uses;
  an in-place session's diff and status are real and should be reported.

### The two destroy paths, and which one is actually dangerous

`Kill` is the obvious one, and the least dangerous: `gitworktree.Destroy` already
calls `validateManagedPath` and would refuse a project directory outright. The real
hazard is **`SaveAndTeardownAll`**
([`manager.go:1709`](../../../backend/internal/session_manager/manager.go)), which runs
at daemon shutdown over every live session and calls `StashUncommitted` followed by
`ForceDestroy`. `ForceDestroy` bypasses git's dirty check and falls back to
`os.RemoveAll` on any residue. Pointed at `project.Path`, that is the user's
repository.

It does not currently reach that state — `validateManagedPath` rejects the path first
— but the protection is a refusal in the wrong layer, and a refusal at shutdown means
a failed teardown rather than a correct one. Routing in-place sessions to an adapter
whose teardown is a no-op is what makes this correct rather than merely survivable.

Note also that `SaveAndTeardownAll` skips records with an empty `Branch`. In-place
sessions record the current branch, so they are *not* skipped and do reach this path.

Both paths get explicit tests asserting the project directory and its contents still
exist afterward.

### Router

`adapterForProject` becomes `adapterFor(ctx, info)`: if the mode resolves to
`in_place`, return the in-place adapter; otherwise fall back to the existing
project-kind branch. Every delegating method already has an `info` or `cfg` in hand,
so no signature outside the router changes.

### Spawn

In `createSessionWorkspace`
([`manager.go:847`](../../../backend/internal/session_manager/manager.go)):

- `in_place` on a `workspace`-kind project is rejected before any durable state is
  created, alongside the existing `ErrScratchBranchUnsupported` check — a new
  `ErrInPlaceUnsupported`.
- `DefaultSpawnBranch` is skipped for `in_place`; no branch is passed and none is
  created. An explicit `cfg.Branch` with `in_place` is rejected for the same reason
  scratch rejects it: the mode cannot honor it.
- The rest of the shared spawn sequence — provisioning, attachments, `AddExclude`,
  the launch — is untouched. It already operates on `ws.Path`.

### Restore across a daemon restart

`RestoreAll` skips any session without a `session_worktrees` marker row. In-place
sessions therefore write one at teardown like any other, with `WorktreePath` set to
the project path and `Branch` to the recorded branch. On restore, `workspace.Restore`
routes to the in-place adapter and re-resolves rather than re-creating. The row is a
restore marker, not a claim that a worktree exists.

### API

`POST /api/v1/sessions` accepts `workspaceMode`. Absent means `worktree` — this is the
one place a default is correct, because it is an API compatibility boundary rather
than stored state, and it keeps `opr session spawn` and orchestrator spawns unchanged.
The controller resolves it to an explicit mode before anything durable is written. The session DTO
([`dto.go:173`](../../../backend/internal/httpd/controllers/dto.go)) gains
`workspaceMode` and `workspacePath` so clients can show where a session lives.
Regenerate with `npm run api`.

## Desktop

The task composer gains a checkbox in the control row that holds the agent picker,
model picker, attach button and Start task. Unchecked by default; rendered only when
the project's kind is `single_repo`. `submitTask` passes the resulting mode through
`createTask`.

## Mobile

The spawn screen gains a row in the existing `SettingsGroup` beside Project and
Agent. `SettingsRow` already exposes a `trailing` slot
([`settings_group.dart:58`](../../../packages/mobile/lib/core/widgets/main_widgets/settings_group.dart)),
so a `Switch` needs no new widget. Off by default, shown only when
`ProjectModel.kind == 'single_repo'` — the model already parses `kind`, so no
additional API surface is required.

`SpawnSessionParams` gains the field and emits it from `toJson` following the
package's hand-written model convention; no codegen. `SpawnCubit` holds the flag
beside `harness` and `name`.

The screen's standing copy is now false and is rewritten. It currently reads
*"Spawn a worker agent. It gets its own isolated workspace, then starts on the task
you give it."*
([`spawn_body.dart:156`](../../../packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart)).
The replacement describes the selected mode, so the promise of isolation appears only
when isolation was chosen.

## Showing where a session lives

The desktop board card already renders a branch row
([`SessionsBoard.tsx:930`](../../../frontend/src/renderer/components/SessionsBoard.tsx)),
gated on `session.branch` being present and distinct from the title and id — which is
why scratch sessions show none. That row is extended to answer *where*, not just
*which branch*:

- `worktree` sessions: branch, plus the worktree directory name.
- `in_place` sessions: the project path, with a distinct marker making it visible at
  a glance that this agent is editing the real checkout.

The mobile session card carries the same distinction.

## Testing

- `inplace` adapter unit tests, including the two that matter most: after `Destroy`
  and after `ForceDestroy`, the project directory and a sentinel file inside it still
  exist.
- Router test: two sessions in one project routing to different adapters by mode.
- Manager: spawn in both modes; `Kill` on an in-place session leaves the directory
  intact and returns `freed=false`; `SaveAndTeardownAll` over a mixed set destroys
  only the worktree session; `in_place` on a `workspace` project is rejected before
  the seed row is created.
- Frontend: composer renders the checkbox only for `single_repo` and sends the mode;
  board card renders both location forms.
- Mobile: `flutter analyze` clean and `flutter test` green, covering the params
  serialization, the cubit flag, and the conditional row.

## Accepted consequences

Stated plainly, because the default is off:

- The common manual case now edits the user's real checkout on their current branch.
  No isolation, no undo, and `Kill` cleans up nothing.
- `ErrWorkspaceDirty` — the protection that refuses to discard uncommitted agent work
  — does not apply to in-place sessions. There is nothing to refuse.
- The diff base is `merge-base` against the default branch, so uncommitted work that
  predates the session reads as session output in the diff and PR views.
- A mobile spawn runs on the daemon's host, so an in-place session started from the
  phone edits the checkout on the user's machine, on whatever branch it is on.
- The shared spawn sequence still installs the agent's own hook files (e.g. Claude
  Code's entries in `.claude/settings.local.json`) and a `.git/info/exclude` line into
  the real checkout; neither is cleaned up on teardown.
