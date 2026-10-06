# Task branch picker (desktop and mobile) — design

Date: 2026-10-07. Daemon `backend/`, renderer `frontend/`, mobile `packages/mobile`.
Approved in chat on 2026-10-07. Work lands on `development`.

The user's request, in substance:

- When creating a task in the desktop app, offer a dropdown of the project's git branches,
  so a branch the user created (e.g. `logic/home` in `rafeeq`) can be picked.
- Add the same choice to the Flutter app's spawn screen.
- Picking a branch means **the agent works on that branch**: its commits land on it. It
  does not mean "cut a new branch from it".

## Facts established by reading the code (2026-10-07)

- **Desktop composer.** `frontend/src/renderer/components/TaskComposer.tsx` is shared by
  `NewTaskDialog` and `GlobalNewTaskDialog`. It posts `POST /api/v1/sessions/delegate`
  with `projectId, brief, agent, model, workspaceMode, claudeAccountId, attachments`. It
  shows "Create a git worktree" only when `project.kind === "single_repo"`
  (`canChooseWorktree`), and sends `workspaceMode` only then. There is no branch control.
  The i18n key `newTask.branch` ("Branch") exists in `i18n/en.json` but no component uses it.
- **Searchable picker precedent.** `components/settings/AgentModelCombobox.tsx` is the
  existing popover + command-list combobox used by `TaskModelPicker`.
- **Delegate has no branch.** `DelegateTaskRequest` (`httpd/controllers/dto.go:749`) has
  no `branch`; `DelegateTaskInput` (`service/session/delegation.go:21`) has none;
  `DelegateTask` builds `ports.SpawnConfig` without `Branch` (`delegation.go:53-64`).
- **Plain spawn already takes a branch.** `POST /api/v1/sessions` passes `in.Branch` into
  `SpawnConfig.Branch` (`controllers/sessions.go:375`). The mobile app spawns through this
  route (`spawn_remote_data_source.dart`, `EndPoints.sessions`) and does not send `branch`.
- **Worktree checkout of an existing branch already works.** `gitworktree.addWorktree`
  (`adapters/workspace/gitworktree/workspace.go:904-953`):
  - refuses a branch checked out in another worktree with
    `ports.ErrWorkspaceBranchCheckedOutElsewhere` (`:912-914`), which `toAPIError` maps to
    409 `BRANCH_CHECKED_OUT_ELSEWHERE` (`service/session/service.go:785`);
  - checks out an existing local branch into the new worktree (`:924-932`);
  - otherwise creates the branch from `origin/<branch>` or the base (`:936-952`).
  The main checkout counts as a worktree, so its current branch is refused.
- **In-place refuses any branch today.** `Manager.Spawn` returns
  `ErrInPlaceUnsupported: an in-place session cannot take a branch`
  (`session_manager/manager.go:553-555`), and `inplace.Workspace.Create` refuses a branch
  too (`adapters/workspace/inplace/workspace.go:40`). `inplace.currentBranch` (`:75-89`)
  resolves the checkout's branch and fails on a detached HEAD.
- **Both routes share one error mapper.** `DelegateTask` and `Spawn` return
  `toAPIError(err)` (`delegation.go:66`, `service.go`).
- **No route lists branches.** `ProjectsController.Register`
  (`controllers/projects.go:26-34`) has list/add/initialize/get/update/config/remove only.
  `gitworktree` already parses `git worktree list --porcelain` into `worktreeRecord`
  (`parse.go:8-16`, `workspace.go:1232`). The daemon wires workspaces through
  `adapters/workspace/router` (`daemon/lifecycle_wiring.go:215`).
- **Mobile spawn screen.** `spawn_body.dart:134-143` shows the "Create a git worktree"
  `SettingsRow` + `Switch` for `single_repo` projects; `SpawnCubit` sends
  `workspaceMode` (`spawn_cubit.dart:135`); option rows open pages of
  `showSpawnOptionsSheet` (`spawn_options_sheet.dart:23`). `SpawnSessionParams` has no
  `branch`.
- **API types are generated.** New DTOs need a `schemaNames` entry in
  `httpd/apispec/specgen/build.go`; `openapi.yaml` and `frontend/src/api/schema.ts` are
  regenerated and committed with the Go change (`AGENTS.md:116-137`).

## Design

### 1. Daemon: list a project's branches

`GET /api/v1/projects/{id}/branches`, operation id `listProjectBranches`, tag `projects`.

Response `ProjectBranchesResponse`:

```json
{
  "current": "logic/home",
  "branches": [
    { "name": "logic/home", "checkedOutAt": "/Users/…/rafeeq", "isMainCheckout": true },
    { "name": "feat/x", "checkedOutAt": "/Users/…/.worktrees/rafeeq-3", "isMainCheckout": false },
    { "name": "development", "isMainCheckout": false }
  ]
}
```

- `branches` holds local branches only (`refs/heads/*`), most recent commit first:
  `git for-each-ref --sort=-committerdate --format=%(refname) refs/heads`, with the
  `refs/heads/` prefix stripped (not `refname:short`, which can be ambiguous).
- `checkedOutAt` is the worktree path where the branch is checked out, from the existing
  `listRecords` parse; omitted when the branch is free.
- `isMainCheckout` is true for the branch checked out in the project's own folder (the
  first, non-linked record of `git worktree list`).
- `current` is the main checkout's branch; `""` on a detached HEAD.
- Single-repo projects only. A workspace or scratch project gets 400
  `BRANCHES_UNSUPPORTED_PROJECT_KIND`. An unknown project gets the existing not-found error.

**Where it lives.**

- **gitworktree adapter:** `(*Workspace).ListBranches(ctx, projectID)` returns
  `[]ports.BranchInfo{Name, CheckedOutAt, IsMainCheckout}`. It reuses `repoPath` and
  `listRecords`.
- **Port:** a new interface `ports.WorkspaceBranchLister`. The workspace router forwards
  it to the gitworktree adapter.
- **Project service:** `projectsvc.Manager` gets `Branches(ctx, id)`. It checks the
  project kind, calls the lister, and fills `current`.
- **Controller:** `ProjectsController` registers the route, returning 501 when `Mgr` is
  nil, like its siblings.

### 2. Daemon: spawn on a chosen branch

- **Delegate:** `DelegateTaskRequest` gains
  `Branch string json:"branch,omitempty" maxLength:"255"`. It is trimmed in the handler and
  carried through `DelegateTaskInput.Branch` into `SpawnConfig.Branch`. `POST /sessions`
  already forwards its `branch`.
- **Worktree mode:** no daemon change. The worktree checks out the branch, and a branch
  checked out elsewhere returns 409 `BRANCH_CHECKED_OUT_ELSEWHERE`.
- **In-place mode** accepts a branch only if it equals the main checkout's current branch.
  - `Manager.Spawn` drops its "in-place cannot take a branch" refusal (`manager.go:553-555`).
    It keeps the single-repo check.
  - `inplace.Workspace.Create` resolves `currentBranch`. If `cfg.Branch` is non-empty and
    differs, it returns a new sentinel `ports.ErrWorkspaceBranchNotCheckedOut`. The message
    names both branches: "logic/home is not checked out in the project folder (it is on
    development)".
  - `toAPIError` maps that sentinel to 409 `BRANCH_NOT_CHECKED_OUT`.
  - The existing seed-row rollback on workspace failure (`manager.go:607-613`) covers cleanup.
  - The daemon never runs `git checkout` or `git switch` in the user's folder.
- **Empty branch:** behaviour is unchanged in both modes. The daemon auto-creates the
  session branch in a worktree, or uses whatever is checked out in place.

### 3. Desktop renderer: the branch combobox

In `TaskComposer`, for single-repo projects (`canChooseWorktree`), a **Branch** combobox
sits on the same row as "Create a git worktree", built on the `AgentModelCombobox`
popover + command pattern and styled per DESIGN.md (agent-orchestrator clone).

- **Data:** a `useProjectBranches(projectId)` query on the new route. It is enabled only
  for single-repo projects, refetches on mount (each dialog open), and is invalidated after
  a successful create.
- **State:** `branch` is a string, where `""` means "New branch".
- **Worktree on:**
  - The first option is **New branch** (the default; today's behaviour). Then come the
    branches in the order the daemon returns them, with search filtering by substring.
  - Branches with `checkedOutAt` are disabled and show a one-line reason:
    - main checkout: "Checked out in your project folder — turn off worktree to work on it";
    - any other: "In use by `<last path segment of checkedOutAt>`".
  - The trigger shows the picked branch or "New branch".
- **Worktree off:**
  - The combobox is disabled and shows `current` (or "Detached HEAD").
  - The request sends `branch: current` when `current` is non-empty, so the daemon checks it.
- **Resets:** toggling the worktree checkbox, or changing project in the global dialog,
  resets `branch` to `""`.
- **Request body:**
  - worktree on with a branch picked: `workspaceMode: "worktree", branch`;
  - worktree on with New branch: no `branch`;
  - worktree off: `workspaceMode: "in_place"`, plus `branch: current` when known.
- **Errors:** `BRANCH_CHECKED_OUT_ELSEWHERE` and `BRANCH_NOT_CHECKED_OUT` show in the
  existing error strip through `apiErrorMessage`, and the prompt and attachments are kept.
  A failed branches query shows "Couldn't load branches", with New branch still usable.
- **Copy:** in `i18n/en.json`, reusing the unused `newTask.branch` for the label.

### 4. Mobile: branch row on the spawn screen

Under the package conventions in `CLAUDE.md` (Cubit only, hand-written models, one params
class per method, `EndPoints` static methods, inline English copy):

- **Data:**
  - `EndPoints.projectBranches(String projectId)` returns
    `/api/v1/projects/$projectId/branches`.
  - Hand-written models `ProjectBranchesModel {current, branches}` and
    `ProjectBranchModel {name, checkedOutAt, isMainCheckout}`, all nullable, each with a
    `fromJson`.
  - `GetProjectBranchesParams` in `data/model/params/`.
  - `SpawnRemoteDataSource.getBranches` and the repository method parse with
    `withDataKey: false`.
- **Params:** `SpawnSessionParams` gains `branch`, sent only when non-empty, and included
  in `props`.
- **Cubit:** `SpawnCubit` loads branches whenever the selected project is single-repo,
  including the initial project and every project change.
  - It holds `branches`, `branchesLoading`, `branchesError` and `selectedBranch`
    (`null` means "New branch").
  - `setUseWorktree` and a project change clear `selectedBranch`.
  - `submit` follows the desktop request-body rules exactly.
- **UI:**
  - A **Branch** `SettingsRow` (`Icons.account_tree_outlined`) sits under the worktree
    switch, single-repo only. With the worktree on, its value is the picked branch or
    "New branch", and tapping it opens a new page of `showSpawnOptionsSheet`. With the
    worktree off, it shows `current` and is not tappable.
  - The sheet page lists "New branch" first, then the branches. A busy branch is dimmed,
    can't be picked, and has the same reason text as desktop as its subtitle.
  - An `AppTextField` search sits at the top of the page when there are more than 10
    branches.
- **Errors:** the screen's existing `errorText` shows the daemon's `message` for both
  codes. A failed branch load shows a footer on the row; "New branch" still works.

## Out of scope

- Remote-only branches (no local `refs/heads` entry).
- Creating or renaming a branch from either UI.
- Workspace (multi-repo) and scratch projects.
- Switching the main checkout's branch for an in-place session.
- Mapping `checkedOutAt` to an Operator session name.

## Testing

Gates: `cd backend && go test ./...`, `go vet ./...`; `cd frontend && npm run typecheck`,
`npm test`, `npm run lint`; `cd packages/mobile && flutter analyze` (No issues found!) and
`flutter test`. Regenerated `openapi.yaml` + `schema.ts` committed with the Go change.

- **gitworktree, against a real temp git repo:**
  - ordering by commit date;
  - `checkedOutAt` set for the main checkout and for a linked worktree;
  - `isMainCheckout`;
  - a detached main checkout reports `current == ""`.
- **inplace adapter, against a real temp repo:**
  - the matching branch succeeds;
  - a mismatch returns `ErrWorkspaceBranchNotCheckedOut`;
  - an empty branch is unchanged.
- **Manager:** an in-place spawn with a mismatched branch returns the sentinel and leaves no
  session row. This uses the real SQLite store, not the in-memory fake: see the 2026-09-15
  lesson, where fakes hid a broken core path.
- **Controllers:**
  - the branches route covers 200, 400 for a non-single-repo project, 404 and 501;
  - delegate passes `branch` through;
  - both new error codes surface with `requestId`.
- **Renderer (Vitest):**
  - New branch is the default;
  - busy branches are disabled with the right reason;
  - the worktree-off lock shows `current`;
  - a worktree toggle resets the pick;
  - the request body is right in each of the three cases;
  - a branches-query failure leaves New branch usable.
- **Mobile:**
  - model `fromJson` and params `toJson`;
  - cubit load, reset on worktree toggle and on project change, and `submit` in each case;
  - a widget test for the row and sheet page, covering the disabled busy branch and search
    appearing above 10 branches.
- **Real-app check:**
  - **Desktop:** run the renderer in the built-in browser against an isolated daemon (the
    `verify-renderer-in-browser-against-isolated-daemon` recipe) with a throwaway repo:
    - create a branch and see it at the top of the list;
    - spawn on it with a worktree and confirm `git -C <worktree> branch --show-current`;
    - see the main checkout's branch disabled;
    - turn the worktree off and see `current`;
    - switch the folder's branch underneath the open dialog, then Start, and get
      `BRANCH_NOT_CHECKED_OUT`.
  - **Mobile:** the same branch spawn from the iOS simulator against the same isolated daemon.
