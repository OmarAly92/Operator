# Workspace Sessions Reliability Plan

> **For agentic workers:** work phase by phase and task by task. Steps use checkbox
> (`- [ ]`) syntax for tracking. Each phase ships on its own and leaves the suite
> green.

**Goal:** Make workspace sessions (one parent repo plus child repos) safe, practical
and reliable, and make the agent inside one do what the workspace needs: work in the
right repo, open PRs per repo, and hear about CI and reviews in terms of the folder
it has to fix.

**Scope:** `backend/` first (phases 1–3), then `frontend/` and `packages/mobile`
(phase 4). Single-repo and scratch projects must behave exactly as today.

**Source:** a three-part audit on 2026-09-24 (lifecycle; PR tracking, review and
diffs; registration and UI) against `development` plus branch
`claude/dazzling-newton-8k4n30`. Every finding below is marked:

- **Reproduced** — shown with real git.
- **Confirmed** — read in the code.
- **Suspected** — depends on git or provider behaviour not yet tested.

Line numbers are a snapshot; re-find the function by name before editing.

## How a workspace session works today

| Stage | Where | What happens |
|---|---|---|
| Register | `service/project/service.go` `Add` → `workspace_registration.go` | `detectWorkspaceChildren` scans direct child folders for git repos. `validateWorkspaceChild` requires a real `.git`, a commit, a branch, and an `origin`. The parent is `git init`ed (`initWorkspaceParent`) or adopted (`adoptWorkspaceParent`); child folders go into its `.gitignore`, committed locally. Stored per child: name, relative path, origin URL, default branch. Nothing can change these later. |
| Spawn | `session_manager/manager.go` `createSessionWorkspace` → `gitworktree/workspace.go` `CreateWorkspaceProject` | One worktree per repo, all on `opr/<id>/root` (since `035227e`). Children are nested inside the root worktree at their relative path. Symlinks and post-create commands run in the root only (`provisionWorkspace`). `in_place` is rejected. |
| Prompt | `manager.go` `workspaceWorkerPrompt`, `prompt.go` `workerMultiPRPrompt` | Repo list (name: path) plus "keep changes scoped". PR rules are written for a single repo. |
| PR tracking | `observe/scm/observer.go` `workspaceSCMSessionRepos` | Scans every child with an origin for PRs from the session branch namespace. Keys include host/owner/repo, so equal PR numbers do not collide. |
| Nudges | `lifecycle/reactions.go` | CI, review, conflict messages identify the PR by number, title and URL only. |
| Review | `review/review.go`, `review/launcher.go` | Reviewer runs in the worker's root worktree. |
| Diffs | `service/session/workspace_files.go` | Changed files across all repos, prefixed by path. |
| Kill / shutdown / restore | `manager.go` `destroyWorkspaceProjectRows`, `saveAndTeardownWorkspaceProject`, `restoreWorkspaceProjectRows`, `restoreSessionWorkspace` | Children removed before root; on shutdown each repo's changes are stashed into `refs/opr/preserved/<id>` and re-applied on restore. |

## Findings

### Tier 1 — loses work or breaks every spawn

| # | Finding | Evidence | Status |
|---|---|---|---|
| F1 | **Kill can delete a child's uncommitted work.** `destroyWorkspaceProjectRows` stops only on `ErrWorkspaceDirty`. Any other child failure (locked worktree, failed dirty probe) is logged and the loop goes on to remove the root. `git worktree remove` on the root deletes nested child folders because they are ignored, not tracked. | `manager.go:2074-2099`; real-git repro: root `worktree remove` (non-force) succeeded and `wt/api/new.txt` was gone | Reproduced |
| F2 | **Root not on `main` → every spawn fails.** The workspace branch of `Add` never records the root's branch; single-repo `Add` does (`service.go:245-254`). `WithDefaults()` then gives `main`, and `baseRefCandidates` has no fallback. | `service.go:221-234`, `domain/projectconfig.go:116`, `gitworktree/commands.go:131` | Confirmed |
| F3 | **Saved work can be lost across restarts.** (a) `upsertWorkspaceProjectRowState` omits `PreservedRef`, and the upsert overwrites that column, so a conflicted apply drops the pointer and the next shutdown overwrites the ref. (b) `restoreSessionWorkspace` (manual restore) never applies preserved refs, then clears them. (c) `saveAndTeardownWorkspaceProject` returns on the first stash error with some rows already `removed`; `RestoreAll` then restores and relaunches the partial set, contradicting the intent at `reconcileLive`. | `manager.go:2102`, `:1902`, `:2029`, `:1622` | Confirmed |
| F4 | **Root worktree can miss the child ignores.** Registration commits the `.gitignore` locally and never pushes it; the root worktree is built from `origin/<default>` first. Children then appear untracked in the root, and `git add -A` there (agent or `StashUncommitted`) records them as gitlinks. | `workspace_registration.go:240,280`, `gitworktree/commands.go:131` | Confirmed (effect Suspected) |

### Tier 2 — the agent cannot do the job well

| # | Finding | Evidence | Status |
|---|---|---|---|
| F5 | **Prompt is too thin.** Never says each folder is its own repo on its own branch, that PRs are opened per repo from that repo's origin, each repo's base branch and remote, which repos have no origin (untracked PRs), or that root commits are local-only when the root has no origin. The PR section assumes one repo. | `manager.go` `workspaceWorkerPrompt`; `prompt.go` `workerMultiPRPrompt` | Confirmed |
| F6 | **Nudges do not name the folder.** CI, review, changes-requested and conflict messages carry `prIdentity` + URL only. "Rebase onto the base branch" does not say which repo's base. | `reactions.go:192-270`, `:620` | Confirmed |
| F7 | **Reviewer uses the wrong checkout.** It runs in the worker's root worktree and is told to diff "the checkout" against the PR base; for a child PR that shows nothing. It also sees the worker's uncommitted changes. GitHub-only commands. | `review/review.go:513,608`, `launcher.go:401-407`, `review/prompt.go:47` | Confirmed |
| F8 | **Session can end early.** `sessionComplete` is true once one PR merged and none is open; with terminate-on-merge, merging `api` before `web`'s PR exists kills the session. | `reactions.go:302-317` | Confirmed |
| F9 | **Stack logic ignores the repo.** `buildStacks` and `prBlockedByOpenParent` match branch names across all the session's PRs; `PRFacts` has no repo. Stacked PRs in different repos can be marked Blocked and lose conflict nudges. | `service/session/stack.go:21`, `reactions.go:324`, `domain/pr.go:9` | Confirmed |
| F10 | **Child repos are not provisioned.** Symlinks and post-create commands run once, in the root. | `manager.go` `provisionWorkspace` | Confirmed |
| F11 | **Children diffed against the project's default branch**, not their own. | `workspace_files.go:461,517` | Confirmed |

### Tier 3 — impractical to live with

| # | Finding | Evidence | Status |
|---|---|---|---|
| F12 | **No maintenance.** No rescan or add/remove of child repos. A newly cloned repo is never registered (and shows untracked in the root); a deleted one breaks every spawn; a changed origin URL or default branch is never refreshed; a child that gains an origin later is never tracked. | `service.go` (only `Add` writes repos), `observer.go:597` | Confirmed |
| F13 | **Registration is brittle.** Depth-1 only; one child with no origin or a detached HEAD rejects the whole workspace; submodule-style children rejected; plain-parent `git add -A` commits a root `.env`; the denylist is appended to the user's `.gitignore`; adopt has no rollback. | `workspace_registration.go:141-357` | Confirmed |
| F14 | **Branches and stale bases.** No branch is deleted on rollback, kill or cleanup in any repo. No `git fetch` before spawn. A `--branch` that already exists is not reused (gets `-2` from base). Child base branches are frozen at registration. | `gitworktree/workspace.go:991-1033`, `manager.go:788` | Confirmed |
| F15 | **Legacy / single-row fallback.** Kill, cleanup and save use the multi-repo path only when there is more than one row; otherwise the root is force-removed, taking children with it. | `manager.go:1976` | Confirmed |

### Tier 4 — UI

| # | Finding | Evidence | Status |
|---|---|---|---|
| F16 | Child repos never shown (desktop or mobile). | `frontend/src/renderer/routes/_shell.tsx:276` (stored, never rendered) | Confirmed |
| F17 | PR cards show `PR #n` with no repo. Desktop Reviews groups by number, merging `api#12` and `web#12`. | `SessionInspector.tsx:571,753,1084-1091` | Confirmed |
| F18 | Mobile drops one of two same-number PRs and can show the other repo's summary. | `packages/mobile/lib/feature/pull_request/logic/pr_view.dart:41`, `pull_request_cubit.dart:29-31` | Confirmed |
| F19 | Claiming a child repo's PR fails (checked against the root origin only). | `service/session/claim_pr.go:85-97,349` | Confirmed |

---

## Phase 1 — Safety (F1–F4, F15)

Nothing in this phase changes what a user sees when things go right. It changes
what happens when they go wrong.

### Task 1.1: Kill never removes the root while a child is still present

**Files:** `backend/internal/session_manager/manager.go` (`destroyWorkspaceProjectRows`, Kill path), tests in `manager_test.go`, real-git test in `adapters/workspace/gitworktree/`.

- [ ] Before removing anything, probe every repo for uncommitted work. If any repo is dirty, stop with `ErrWorkspaceDirty` and remove nothing, so Kill is all-or-nothing.
- [ ] If any child's `Destroy` fails for any reason, do **not** remove the root. Mark the rows `retry_remove` and return the error.
- [ ] Root removal also checks that every child path under it is gone (or was never registered) before calling `Destroy`.
- [ ] Unit test: child `Destroy` fails with a non-dirty error → root `Destroy` never called.
- [ ] Real-git test: dirty child plus locked child worktree → Kill fails and the child's file still exists.

### Task 1.2: Record the root's branch at registration

**Files:** `service/project/service.go` (`Add`), a store migration or a one-time startup backfill, `service_test.go`.

- [ ] In the workspace branch of `Add`, set `row.Config.DefaultBranch` from `resolveDefaultBranch(path)` exactly like the single-repo branch does.
- [ ] Backfill existing workspace projects whose `DefaultBranch` is empty and whose root has no `main`.
- [ ] Test: adopt a parent on `master` → spawn succeeds.

### Task 1.3: Keep and use preserved work

**Files:** `manager.go` (`upsertWorkspaceProjectRowState`, `restoreSessionWorkspace`, `saveAndTeardownWorkspaceProject`, `reconcileLive`, `RestoreAll`).

- [ ] `upsertWorkspaceProjectRowState` carries the existing `PreservedRef` through instead of clearing it.
- [ ] `restoreSessionWorkspace` applies preserved refs the same way `RestoreAll` does before clearing them.
- [ ] Save is two-phase: stash every repo first; mark rows `removed` and tear down only when all stashes succeeded. On any failure leave every worktree in place and do not relaunch.
- [ ] Never write a new preserve ref over one that has not been applied; use a per-save suffix or refuse.
- [ ] Tests: conflicted apply keeps the ref; manual restore brings the work back; a stash failure in the second repo leaves both worktrees intact and no relaunch.

### Task 1.4: Root worktree always carries the child ignores

**Files:** `gitworktree/workspace.go` (`CreateWorkspaceProject` root repo), maybe `workspace_registration.go`.

- [ ] Choose one:
  - **(a) Recommended:** write the child entries to the root worktree's `.git/info/exclude` (via `git rev-parse --git-path info/exclude`) at spawn. It is per-repo, needs no commit, and works whatever branch the root is based on.
  - (b) Base the root worktree on the local default branch when it is ahead of `origin`.
- [ ] Real-git test: root with an origin that lacks the ignore commit → `git status` in the root worktree is clean after spawn.

### Task 1.5: Single-row and legacy rows never force-remove a root with children

**Files:** `manager.go` (`workspaceProjectRows` callers).

- [ ] For a workspace project, use the multi-repo path whenever the project has registered children, not only when there are more than one rows; rebuild missing rows from the registry first.
- [ ] Test: workspace session with only its root row → Kill does not delete child folders.

**Phase 1 done when:** the tests above pass, the whole backend suite passes, and a manual kill/restart/restore cycle on a real workspace loses nothing.

---

## Phase 2 — Agent effectiveness (F5–F11)

### Task 2.1: A workspace prompt the agent can act on

**Files:** `session_manager/manager.go` (`workspaceWorkerPrompt`, `workspaceRepoList`), `prompt.go`, tests.

- [ ] Render a table of repos: path, base branch, remote (host/owner/repo) or "no remote — PRs not tracked".
- [ ] State the rules in the prompt, with reasons:
  - each path is a separate git repo; run git commands inside it;
  - every repo is on the session branch; commit, push and open the PR in each repo you changed, from that repo's origin, targeting that repo's base branch;
  - the root has no remote (when true), so root changes stay local; say so if you make any;
  - never `git add` a child folder from the root.
- [ ] Make the PR section workspace-aware (the "first PR from the current branch" rule applies per repo).
- [ ] Tests assert the table and each rule appear; single-repo prompt unchanged.

### Task 2.2: Nudges name the folder

**Files:** `lifecycle/reactions.go`, `domain/pr.go` or the PR store (add the repo identity or a workspace repo name to tracked PRs), `observe/scm/observer.go` (fill it).

- [ ] Map each tracked PR to its workspace repo (by origin host/owner/repo) when the project is a workspace.
- [ ] Prefix every CI, review, changes-requested and conflict message with `In ./<path> (<repo>):` and use that repo's base branch in the conflict text.
- [ ] Tests for each message kind with two child repos.

### Task 2.3: Reviewer reviews the right repo

**Files:** `review/review.go`, `review/launcher.go`, `review/prompt.go`.

- [ ] For a workspace worker, launch the reviewer in the PR's repo worktree (`<root>/<path>`), found through the mapping from Task 2.2.
- [ ] Name the repo, path and base branch in the task file.
- [ ] Test with a child-repo PR.

### Task 2.4: Repo-aware completion and stacks

**Files:** `lifecycle/reactions.go` (`sessionComplete`, `prBlockedByOpenParent`), `service/session/stack.go`, `domain/pr.go`.

- [ ] Add the repo to `PRFacts`; stack parents must be in the same repo.
- [ ] For workspace sessions, do not treat the session as complete while any repo has commits on the session branch that are not in a merged PR, or simply disable terminate-on-merge for workspace sessions until that exists. **Decision needed.**
- [ ] Cross-repo tests for both.

### Task 2.5: Provision child repos and diff them against their own base

**Files:** `manager.go` (`provisionWorkspace`), `service/session/workspace_files.go`, `domain` config if per-repo commands are added.

- [ ] Run post-create commands in every repo, or add a per-repo `cwd`. **Decision needed.** Symlinks already resolve against the project path.
- [ ] Use `WorkspaceRepoRecord.DefaultBranch` for child diffs.

**Phase 2 done when:** in a real workspace with two child repos, an agent asked to change both opens one PR per repo, both are tracked, a CI failure in one produces a message naming its folder, and the reviewer reviews the right diff.

---

## Phase 3 — Practicality (F12–F14)

### Task 3.1: Rescan and edit repos

**Files:** `service/project/service.go`, `workspace_registration.go`, store, HTTP route + OpenAPI spec, `cli/project.go`.

- [ ] `Rescan` finds new nested repos, marks missing ones, and refreshes origin URL and default branch for existing ones; updates the root's ignores.
- [ ] Add/remove a single child by path.
- [ ] Spawn refreshes origin and default branch for each child and skips (with a visible warning) a child whose folder is gone, instead of failing.
- [ ] `opr project rescan <id>`; route and spec parity tests (`go test ./internal/httpd/...`).

### Task 3.2: Kinder registration

**Files:** `workspace_registration.go`.

- [ ] Report invalid children with a reason and let the user skip them, instead of rejecting the whole workspace.
- [ ] Add `.env`, `.env.*` to the denylist; write the denylist to `.git/info/exclude` rather than the user's `.gitignore`.
- [ ] Roll back the adopt path on failure.
- [ ] Optionally scan to depth 2–3 (`services/api`). **Decision needed.**

### Task 3.3: Fresh bases and branch cleanup

**Files:** `gitworktree/workspace.go`, `manager.go`.

- [ ] `git fetch origin <base>` per repo before creating worktrees (with a short timeout; continue offline).
- [ ] Delete the session branch in every repo on rollback, and on cleanup once its PRs are merged or closed and the branch has no unpushed commits.
- [ ] Reuse an existing `--branch` in every repo where it exists, as single-repo does.

**Phase 3 done when:** cloning a new repo into a workspace and running rescan makes the next session include it, and deleting one makes the next session start without it and say so.

---

## Phase 4 — UI (F16–F19)

**Files:** `frontend/src/renderer/components/SessionInspector.tsx`, the project settings page, `packages/mobile/lib/feature/pull_request/`, `service/session/claim_pr.go`.

- [ ] Project page lists child repos with path, remote, base branch and a Rescan button (Phase 3 API). Follow DESIGN.md.
- [ ] PR cards show the repo (`SessionPRSummary.repo`).
- [ ] Desktop Reviews and mobile PR list key PRs by URL, not number.
- [ ] Claiming a PR accepts any repo in the workspace.
- [ ] Frontend: `npx vitest run`, typecheck, lint. Mobile: `flutter analyze`, `flutter test`.

---

## Decisions needed

1. **Terminate-on-merge for workspace sessions (Task 2.4):** disable it for workspace sessions, or finish only when every repo with session commits has a merged PR?
2. **Child provisioning (Task 2.5):** run post-create commands in every repo, or add a per-command `cwd`?
3. **Nested discovery depth (Task 3.2):** stay at depth 1, or scan deeper?
4. **Root ignores (Task 1.4):** `info/exclude` at spawn (recommended) or change the root base?

## Verification for every task

- `cd backend && go test ./...` and `golangci-lint run` on changed packages (v2.12.2 per `AGENTS.md`).
- Anything that touches git behaviour gets a real-git test under `adapters/workspace/gitworktree/`, not only fakes.
- Route changes: `go test ./internal/httpd/...` for spec parity.
- Single-repo behaviour unchanged: the existing single-repo tests pass untouched.
