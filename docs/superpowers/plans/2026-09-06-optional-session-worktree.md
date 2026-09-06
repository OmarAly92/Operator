# Optional Session Worktree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the per-session git worktree a user choice on the desktop composer and the mobile spawn screen, defaulting to off, so a manually created session can run directly in the project's own checkout.

**Architecture:** A new `domain.WorkspaceMode` (`worktree` | `in_place`) is recorded on the session row and threaded through `ports.WorkspaceConfig` and `ports.WorkspaceInfo`. A new `inplace` workspace adapter returns the project path and makes every teardown primitive a no-op. The workspace router picks the adapter by mode first and project kind second, which is what lets one project hold sessions of both modes.

**Tech Stack:** Go 1.x (backend, sqlc + goose migrations), React + TypeScript (frontend/renderer), Flutter 3.44.5 (packages/mobile).

**Spec:** [`docs/superpowers/specs/2026-09-06-optional-session-worktree-design.md`](../specs/2026-09-06-optional-session-worktree-design.md)

## Global Constraints

- **No fallback values for the stored mode.** `domain.WorkspaceMode` has no `WithDefault()`. An empty mode reaching the workspace layer is a programming error and must return an error, never be coerced to `worktree`.
- **The column is `workspace_mode TEXT NOT NULL CHECK (workspace_mode IN ('worktree', 'in_place'))` with no `DEFAULT`.** Migration `0102` clears session-scoped rows rather than backfilling.
- **`in_place` teardown must never touch the filesystem.** `Destroy`, `ForceDestroy`, `StashUncommitted`, `ApplyPreserved` are no-ops. No `os.RemoveAll`, no `git worktree remove`, no `git worktree prune`, no preserve ref.
- **`in_place` is `single_repo` only.** Rejected for `workspace` projects; control hidden for `scratch`.
- **Default off on the two manual surfaces only.** `opr session spawn` and orchestrator/reviewer spawns keep creating worktrees.
- No comments in new code (repo convention, `~/.claude/CLAUDE.md`).
- Backend gate: `go build ./...`, `go test ./...`, `go vet ./...` from `backend/`.
- Mobile gate: `flutter analyze` must print "No issues found!" and `flutter test` must pass, both from `packages/mobile`.
- Mobile conventions: Cubit only (never Bloc with events), no `freezed`/`json_serializable`, hand-written models, params classes under `data/model/params/`, inline English copy, feature code never imports `flutter_screenutil`.
- After changing any API shape, run `npm run api` from the repo root to regenerate the OpenAPI spec and frontend TS types. After changing `queries/` or a migration, run `npm run sqlc`.

---

## File Structure

**Backend — new:**
- `backend/internal/domain/workspacemode.go` — the mode type and its parser.
- `backend/internal/storage/sqlite/0102_session_workspace_mode.go` — clearing migration + column.
- `backend/internal/adapters/workspace/inplace/workspace.go` — the adapter.
- `backend/internal/adapters/workspace/inplace/workspace_test.go` — adapter tests, including the two safety tests.

**Backend — modified:**
- `backend/internal/ports/outbound.go` — `Mode` on `WorkspaceConfig` and `WorkspaceInfo`.
- `backend/internal/ports/session.go` — `WorkspaceMode` on `SpawnConfig`.
- `backend/internal/domain/session.go` — `WorkspaceMode` on `SessionMetadata`.
- `backend/internal/storage/sqlite/queries/sessions.sql` + regenerated `gen/`.
- `backend/internal/storage/sqlite/store/session_store.go` — read/write mapping.
- `backend/internal/storage/sqlite/migrate_burned_versions_test.go` — register 101.
- `backend/internal/adapters/workspace/router/router.go` — route by mode.
- `backend/internal/session_manager/manager.go` — spawn resolution, `workspaceInfo`, teardown wiring.
- `backend/internal/httpd/controllers/dto.go`, `sessions.go` — request field + read model.
- `backend/internal/httpd/apispec/specgen/build.go` — spec entries.
- `backend/cmd/opr` wiring where the router is constructed.

**Frontend — modified:**
- `frontend/src/renderer/components/TaskComposer.tsx` — the checkbox.
- `frontend/src/renderer/components/SessionsBoard.tsx` — the location row.

**Mobile — modified:**
- `packages/mobile/lib/feature/spawn/data/model/params/spawn_session_params.dart`
- `packages/mobile/lib/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart`
- `packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart`

---

## Task 1: The WorkspaceMode domain type

**Files:**
- Create: `backend/internal/domain/workspacemode.go`
- Create: `backend/internal/domain/workspacemode_test.go`

**Interfaces:**
- Consumes: nothing.
- Produces: `domain.WorkspaceMode` (string type), constants `domain.WorkspaceModeWorktree = "worktree"` and `domain.WorkspaceModeInPlace = "in_place"`, `func ParseWorkspaceMode(string) (WorkspaceMode, error)`, `func (m WorkspaceMode) Valid() bool`, and `var ErrInvalidWorkspaceMode = errors.New("invalid workspace mode")`.

- [x] **Step 1: Write the failing test**

```go
package domain

import (
	"errors"
	"testing"
)

func TestParseWorkspaceModeAcceptsBothModes(t *testing.T) {
	for _, tc := range []struct {
		in   string
		want WorkspaceMode
	}{
		{"worktree", WorkspaceModeWorktree},
		{"in_place", WorkspaceModeInPlace},
	} {
		got, err := ParseWorkspaceMode(tc.in)
		if err != nil || got != tc.want {
			t.Fatalf("ParseWorkspaceMode(%q) = %q, %v; want %q, nil", tc.in, got, err, tc.want)
		}
	}
}

func TestParseWorkspaceModeRejectsEmpty(t *testing.T) {
	if _, err := ParseWorkspaceMode(""); !errors.Is(err, ErrInvalidWorkspaceMode) {
		t.Fatalf("want ErrInvalidWorkspaceMode for the empty string, got %v", err)
	}
}

func TestParseWorkspaceModeRejectsUnknown(t *testing.T) {
	if _, err := ParseWorkspaceMode("worktre"); !errors.Is(err, ErrInvalidWorkspaceMode) {
		t.Fatalf("want ErrInvalidWorkspaceMode for a typo, got %v", err)
	}
}

func TestWorkspaceModeValid(t *testing.T) {
	if WorkspaceMode("").Valid() {
		t.Fatal("the empty mode must not be valid: there is no default")
	}
	if !WorkspaceModeInPlace.Valid() {
		t.Fatal("in_place must be valid")
	}
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/domain/ -run TestParseWorkspaceMode -v`
Expected: FAIL — build error, `undefined: ParseWorkspaceMode`.

- [x] **Step 3: Write minimal implementation**

```go
package domain

import (
	"errors"
	"fmt"
)

const (
	WorkspaceModeWorktree WorkspaceMode = "worktree"
	WorkspaceModeInPlace  WorkspaceMode = "in_place"
)

var ErrInvalidWorkspaceMode = errors.New("invalid workspace mode")

type WorkspaceMode string

func (m WorkspaceMode) Valid() bool {
	return m == WorkspaceModeWorktree || m == WorkspaceModeInPlace
}

func ParseWorkspaceMode(raw string) (WorkspaceMode, error) {
	mode := WorkspaceMode(raw)
	if !mode.Valid() {
		return "", fmt.Errorf("%w: %q", ErrInvalidWorkspaceMode, raw)
	}
	return mode, nil
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `cd backend && go test ./internal/domain/ -v -run WorkspaceMode`
Expected: PASS, all four tests.

- [x] **Step 5: Commit**

```bash
git add backend/internal/domain/workspacemode.go backend/internal/domain/workspacemode_test.go
git commit -m "feat(domain): add WorkspaceMode with no default"
```

---

## Task 2: The clearing migration and the column

**Files:**
- Create: `backend/internal/storage/sqlite/0102_session_workspace_mode.go`
- Create: `backend/internal/storage/sqlite/migrate_workspace_mode_test.go`
- Modify: `backend/internal/storage/sqlite/migrate_burned_versions_test.go` (append `101` to the registry map)

**Interfaces:**
- Consumes: `migrationTableExists(ctx, tx, name)` from `0094_clear_pre_release_data.go` — reuse it, do not redefine it.
- Produces: a `sessions.workspace_mode` column, `TEXT NOT NULL CHECK (workspace_mode IN ('worktree','in_place'))`, no `DEFAULT`.

Read [`0094_clear_pre_release_data.go`](../../../backend/internal/storage/sqlite/0094_clear_pre_release_data.go) before starting: this task copies its shape (goose Go migration, `PRAGMA defer_foreign_keys`, skip tables that do not exist).

The list below deliberately omits the `conversation*` and `session_interface_transition*`
tables that `0094` clears: migration `0101_drop_conversations.sql` dropped them, so
naming them here would be dead weight. `migrationTableExists` still guards every entry,
so a table missing on some profile is skipped rather than fatal — verify the list
against `sqlite3 <db> .tables` before trusting it.

- [x] **Step 1: Write the failing test**

```go
package sqlite

import (
	"context"
	"strings"
	"testing"
)

func TestMigration0102AddsWorkspaceModeWithoutDefault(t *testing.T) {
	db := openMigratedTestDB(t)
	var ddl string
	if err := db.QueryRowContext(context.Background(),
		`SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'sessions'`).Scan(&ddl); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(ddl, "workspace_mode") {
		t.Fatalf("sessions is missing workspace_mode:\n%s", ddl)
	}
	if !strings.Contains(ddl, "CHECK") || !strings.Contains(ddl, "in_place") {
		t.Fatalf("workspace_mode must be CHECK-constrained to the two modes:\n%s", ddl)
	}
	if strings.Contains(ddl, "workspace_mode TEXT NOT NULL DEFAULT") {
		t.Fatalf("workspace_mode must have no DEFAULT: %s", ddl)
	}
}

func TestMigration0102RejectsAnUnknownMode(t *testing.T) {
	db := openMigratedTestDB(t)
	_, err := db.ExecContext(context.Background(),
		`INSERT INTO sessions (id, project_id, workspace_mode) VALUES ('s-1', 'p-1', 'nonsense')`)
	if err == nil {
		t.Fatal("want the CHECK constraint to reject an unknown workspace_mode")
	}
}

func TestMigration0102ClearsSessions(t *testing.T) {
	db := openMigratedTestDB(t)
	var count int
	if err := db.QueryRowContext(context.Background(), `SELECT COUNT(*) FROM sessions`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 0 {
		t.Fatalf("want a cleared sessions table, got %d rows", count)
	}
}
```

If `openMigratedTestDB` does not already exist in this package, read
[`migrate_clear_data_test.go`](../../../backend/internal/storage/sqlite/migrate_clear_data_test.go)
and reuse whatever helper it uses to open a fully migrated database; do not add a
second helper that does the same thing.

- [x] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/storage/sqlite/ -run TestMigration0102 -v`
Expected: FAIL — `sessions is missing workspace_mode`.

- [x] **Step 3: Write the migration**

```go
package sqlite

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/pressly/goose/v3"
)

var workspaceModeClearedTables = []string{
	"change_log",
	"block_events",
	"terminal_blocks",
	"shell_terminals",
	"agent_switches",
	"agent_native_sessions",
	"pr_review_threads",
	"pr_reviews",
	"pr_comment",
	"pr_checks",
	"pr",
	"review_run",
	"review",
	"session_cleanup_facts",
	"session_worktrees",
	"notifications",
	"sessions",
}

func init() {
	goose.AddMigrationContext(addSessionWorkspaceMode, nil)
}

func addSessionWorkspaceMode(ctx context.Context, tx *sql.Tx) error {
	if _, err := tx.ExecContext(ctx, `PRAGMA defer_foreign_keys = ON`); err != nil {
		return fmt.Errorf("defer foreign keys: %w", err)
	}
	for _, table := range workspaceModeClearedTables {
		exists, err := migrationTableExists(ctx, tx, table)
		if err != nil {
			return fmt.Errorf("find table %s: %w", table, err)
		}
		if !exists {
			continue
		}
		if _, err := tx.ExecContext(ctx, fmt.Sprintf(`DELETE FROM %s`, table)); err != nil {
			return fmt.Errorf("clear table %s: %w", table, err)
		}
	}
	if _, err := tx.ExecContext(ctx,
		`ALTER TABLE sessions ADD COLUMN workspace_mode TEXT NOT NULL CHECK (workspace_mode IN ('worktree', 'in_place'))`,
	); err != nil {
		return fmt.Errorf("add sessions.workspace_mode: %w", err)
	}
	return nil
}
```

If SQLite refuses `ADD COLUMN ... NOT NULL` without a default on this schema, fall back
to the table-rebuild form: create `sessions_new` with the full column list plus
`workspace_mode` CHECK-constrained and not defaulted, `INSERT INTO sessions_new SELECT
... FROM sessions` (which selects zero rows, since the table was just cleared), `DROP
TABLE sessions`, `ALTER TABLE sessions_new RENAME TO sessions`, then recreate the
indexes the original table had. Do **not** resolve it by adding a `DEFAULT`.

- [x] **Step 4: Register the version in the burned-versions map**

In `migrate_burned_versions_test.go`, add to the map after the `101:` entry:

```go
	102: "0102_session_workspace_mode.go",
```

- [x] **Step 5: Run tests to verify they pass**

Run: `cd backend && go test ./internal/storage/sqlite/ -v`
Expected: PASS, including `TestMigration0102*` and the existing burned-version tests.

- [x] **Step 6: Commit**

```bash
git add backend/internal/storage/sqlite/
git commit -m "feat(storage): add a fallback-free sessions.workspace_mode"
```

---

## Task 3: Persist the mode through the store

**Files:**
- Modify: `backend/internal/domain/session.go` (add to `SessionMetadata`)
- Modify: `backend/internal/storage/sqlite/queries/sessions.sql`
- Modify: `backend/internal/storage/sqlite/store/session_store.go`
- Test: `backend/internal/storage/sqlite/store/store_test.go`

**Interfaces:**
- Consumes: `domain.WorkspaceMode` (Task 1), the `workspace_mode` column (Task 2).
- Produces: `domain.SessionMetadata.WorkspaceMode` of type `domain.WorkspaceMode`, JSON tag `workspaceMode`, round-tripped by `CreateSession`/`GetSession`/`UpdateSession`.

- [x] **Step 1: Write the failing test**

Add to `store_test.go`, following the surrounding table-test style:

```go
func TestSessionStoreRoundTripsWorkspaceMode(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	rec, err := s.CreateSession(ctx, domain.SessionRecord{
		ProjectID: "p-1",
		Kind:      domain.SessionKindWorker,
		Metadata:  domain.SessionMetadata{WorkspaceMode: domain.WorkspaceModeInPlace},
	})
	if err != nil {
		t.Fatal(err)
	}
	got, ok, err := s.GetSession(ctx, rec.ID)
	if err != nil || !ok {
		t.Fatalf("GetSession: %v %v", ok, err)
	}
	if got.Metadata.WorkspaceMode != domain.WorkspaceModeInPlace {
		t.Fatalf("want in_place round-tripped, got %q", got.Metadata.WorkspaceMode)
	}
}
```

Use whatever store constructor the neighboring tests in this file already use in place
of `newTestStore` if the name differs, and the same `SessionKind` constant they use.

- [x] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/storage/sqlite/store/ -run TestSessionStoreRoundTripsWorkspaceMode -v`
Expected: FAIL — `unknown field WorkspaceMode in struct literal`.

- [x] **Step 3: Add the field, the query columns, and the mapping**

In `domain/session.go`, inside `SessionMetadata`, next to `WorkspacePath`:

```go
	WorkspaceMode WorkspaceMode `json:"workspaceMode,omitempty"`
```

In `queries/sessions.sql`, add `workspace_mode` to the insert column list and its
value placeholder, to the `UPDATE ... SET` list as `workspace_mode = ?`, and to every
`SELECT` column list that already names `workspace_path` (lines around 8, 25, 44, 56
and 68 — check each one; the file has several near-identical select lists and all of
them must stay in sync).

In `store/session_store.go`, add to the write mapping beside `WorkspacePath`:

```go
		WorkspaceMode: string(rec.Metadata.WorkspaceMode),
```

and to the read mapping beside `WorkspacePath`:

```go
			WorkspaceMode: domain.WorkspaceMode(row.WorkspaceMode),
```

- [x] **Step 4: Regenerate sqlc**

Run: `npm run sqlc` from the repo root.
Expected: `backend/internal/storage/sqlite/gen/` picks up `WorkspaceMode` on the
session row and param structs. Commit the generated files.

- [x] **Step 5: Run tests to verify they pass**

Run: `cd backend && go build ./... && go test ./internal/storage/...`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add backend/internal/domain/session.go backend/internal/storage/sqlite/
git commit -m "feat(storage): persist the session workspace mode"
```

---

## Task 4: The in-place workspace adapter

**Files:**
- Create: `backend/internal/adapters/workspace/inplace/workspace.go`
- Create: `backend/internal/adapters/workspace/inplace/workspace_test.go`

**Interfaces:**
- Consumes: `ports.Workspace`, `ports.WorkspaceConfig`, `ports.WorkspaceInfo`, `domain.WorkspaceMode`.
- Produces: `inplace.New(deps inplace.Deps) (*inplace.Workspace, error)` where `type Deps struct { Projects ProjectStore }` and `type ProjectStore interface { GetProject(ctx context.Context, id string) (domain.ProjectRecord, bool, error) }` — the same interface shape the router already declares. Implements `ports.Workspace` and `ports.WorkspaceObserver`.

Read [`scratch/workspace.go`](../../../backend/internal/adapters/workspace/scratch/workspace.go) first for the house style of a non-git workspace adapter.

- [x] **Step 1: Write the failing safety tests**

```go
package inplace

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type stubProjects struct{ rec domain.ProjectRecord }

func (s stubProjects) GetProject(context.Context, string) (domain.ProjectRecord, bool, error) {
	return s.rec, true, nil
}

func newRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	for _, args := range [][]string{
		{"init"},
		{"-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "--allow-empty", "-m", "root"},
	} {
		cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	if err := os.WriteFile(filepath.Join(dir, "sentinel.txt"), []byte("keep me"), 0o600); err != nil {
		t.Fatal(err)
	}
	return dir
}

func newWorkspace(t *testing.T, repo string) *Workspace {
	t.Helper()
	w, err := New(Deps{Projects: stubProjects{rec: domain.ProjectRecord{ID: "p-1", Path: repo}}})
	if err != nil {
		t.Fatal(err)
	}
	return w
}

func TestCreateReturnsTheProjectPathAndCurrentBranch(t *testing.T) {
	repo := newRepo(t)
	w := newWorkspace(t, repo)
	info, err := w.Create(context.Background(), ports.WorkspaceConfig{ProjectID: "p-1", SessionID: "s-1"})
	if err != nil {
		t.Fatal(err)
	}
	if info.Path != repo || info.RepoPath != repo {
		t.Fatalf("want the project path, got path=%q repo=%q", info.Path, info.RepoPath)
	}
	if info.Branch == "" {
		t.Fatal("want the currently checked out branch recorded")
	}
	if info.Mode != domain.WorkspaceModeInPlace {
		t.Fatalf("want the mode stamped, got %q", info.Mode)
	}
}

func TestCreateRejectsABranchRequest(t *testing.T) {
	repo := newRepo(t)
	w := newWorkspace(t, repo)
	if _, err := w.Create(context.Background(), ports.WorkspaceConfig{
		ProjectID: "p-1", SessionID: "s-1", Branch: "feature/x",
	}); err == nil {
		t.Fatal("want an error: in-place cannot honour a requested branch")
	}
}

func TestCreateRejectsANonRepository(t *testing.T) {
	dir := t.TempDir()
	w, err := New(Deps{Projects: stubProjects{rec: domain.ProjectRecord{ID: "p-1", Path: dir}}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Create(context.Background(), ports.WorkspaceConfig{ProjectID: "p-1", SessionID: "s-1"}); err == nil {
		t.Fatal("want an error for a path that is not a git work tree")
	}
}

func TestDestroyNeverRemovesTheProjectDirectory(t *testing.T) {
	repo := newRepo(t)
	w := newWorkspace(t, repo)
	info := ports.WorkspaceInfo{Path: repo, RepoPath: repo, ProjectID: "p-1", SessionID: "s-1", Mode: domain.WorkspaceModeInPlace}
	if err := w.Destroy(context.Background(), info); err != nil {
		t.Fatalf("Destroy must succeed as a no-op, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(repo, "sentinel.txt")); err != nil {
		t.Fatalf("Destroy deleted the project directory: %v", err)
	}
}

func TestForceDestroyNeverRemovesTheProjectDirectory(t *testing.T) {
	repo := newRepo(t)
	w := newWorkspace(t, repo)
	info := ports.WorkspaceInfo{Path: repo, RepoPath: repo, ProjectID: "p-1", SessionID: "s-1", Mode: domain.WorkspaceModeInPlace}
	if err := w.ForceDestroy(context.Background(), info); err != nil {
		t.Fatalf("ForceDestroy must succeed as a no-op, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(repo, "sentinel.txt")); err != nil {
		t.Fatalf("ForceDestroy deleted the project directory: %v", err)
	}
	if _, err := os.Stat(filepath.Join(repo, ".git")); err != nil {
		t.Fatalf("ForceDestroy deleted the git directory: %v", err)
	}
}

func TestStashUncommittedNeverPreserves(t *testing.T) {
	repo := newRepo(t)
	w := newWorkspace(t, repo)
	ref, err := w.StashUncommitted(context.Background(), ports.WorkspaceInfo{
		Path: repo, RepoPath: repo, ProjectID: "p-1", SessionID: "s-1", Mode: domain.WorkspaceModeInPlace,
	})
	if err != nil || ref != "" {
		t.Fatalf("want (\"\", nil): the user owns this directory, got %q %v", ref, err)
	}
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `cd backend && go test ./internal/adapters/workspace/inplace/ -v`
Expected: FAIL — the package does not exist yet.

- [x] **Step 3: Write the adapter**

```go
package inplace

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type ProjectStore interface {
	GetProject(ctx context.Context, id string) (domain.ProjectRecord, bool, error)
}

type Deps struct {
	Projects ProjectStore
}

type Workspace struct {
	projects ProjectStore
}

var _ ports.Workspace = (*Workspace)(nil)
var _ ports.WorkspaceObserver = (*Workspace)(nil)

func New(deps Deps) (*Workspace, error) {
	if deps.Projects == nil {
		return nil, errors.New("inplace workspace: Projects is required")
	}
	return &Workspace{projects: deps.Projects}, nil
}

func (w *Workspace) Create(ctx context.Context, cfg ports.WorkspaceConfig) (ports.WorkspaceInfo, error) {
	if strings.TrimSpace(cfg.Branch) != "" {
		return ports.WorkspaceInfo{}, fmt.Errorf("inplace workspace: a branch cannot be requested: %q", cfg.Branch)
	}
	return w.resolve(ctx, cfg)
}

func (w *Workspace) Restore(ctx context.Context, cfg ports.WorkspaceConfig) (ports.WorkspaceInfo, error) {
	return w.resolve(ctx, ports.WorkspaceConfig{ProjectID: cfg.ProjectID, SessionID: cfg.SessionID, Kind: cfg.Kind})
}

func (w *Workspace) resolve(ctx context.Context, cfg ports.WorkspaceConfig) (ports.WorkspaceInfo, error) {
	project, ok, err := w.projects.GetProject(ctx, string(cfg.ProjectID))
	if err != nil {
		return ports.WorkspaceInfo{}, fmt.Errorf("inplace workspace: project %q: %w", cfg.ProjectID, err)
	}
	if !ok {
		return ports.WorkspaceInfo{}, fmt.Errorf("inplace workspace: project %q not found", cfg.ProjectID)
	}
	path := project.Path
	if info, err := os.Stat(path); err != nil || !info.IsDir() {
		return ports.WorkspaceInfo{}, fmt.Errorf("inplace workspace: project path %q is not a directory", path)
	}
	branch, err := w.currentBranch(ctx, path)
	if err != nil {
		return ports.WorkspaceInfo{}, err
	}
	return ports.WorkspaceInfo{
		Path:      path,
		RepoPath:  path,
		Branch:    branch,
		SessionID: cfg.SessionID,
		ProjectID: cfg.ProjectID,
		Mode:      domain.WorkspaceModeInPlace,
	}, nil
}

func (w *Workspace) currentBranch(ctx context.Context, path string) (string, error) {
	out, err := exec.CommandContext(ctx, "git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD").Output()
	if err != nil {
		return "", fmt.Errorf("inplace workspace: %q is not a git work tree: %w", path, err)
	}
	branch := strings.TrimSpace(string(out))
	if branch == "" {
		return "", fmt.Errorf("inplace workspace: could not resolve the branch at %q", path)
	}
	return branch, nil
}

func (w *Workspace) Destroy(context.Context, ports.WorkspaceInfo) error { return nil }

func (w *Workspace) ForceDestroy(context.Context, ports.WorkspaceInfo) error { return nil }

func (w *Workspace) StashUncommitted(context.Context, ports.WorkspaceInfo) (string, error) {
	return "", nil
}

func (w *Workspace) ApplyPreserved(context.Context, ports.WorkspaceInfo, string) error { return nil }

func (w *Workspace) AddExclude(ctx context.Context, info ports.WorkspaceInfo, patterns ...string) error {
	return addExclude(info.Path, patterns...)
}
```

`ObserveWorkspace` is required by the spec: an in-place session's diff and status are
real and must be reported, so it is the one place this adapter does run git. Read
[`gitworktree/observe_test.go`](../../../backend/internal/adapters/workspace/gitworktree/) and the
`ObserveWorkspace` implementation beside it, and reuse the same plumbing against
`info.Path`, returning a `ports.WorkspaceObservation` populated the same way. Add a
test asserting a dirty in-place checkout reports as dirty:

```go
func TestObserveWorkspaceReportsRealGitState(t *testing.T) {
	repo := newRepo(t)
	w := newWorkspace(t, repo)
	obs, err := w.ObserveWorkspace(context.Background(), ports.WorkspaceInfo{
		Path: repo, RepoPath: repo, ProjectID: "p-1", SessionID: "s-1", Mode: domain.WorkspaceModeInPlace,
	})
	if err != nil {
		t.Fatal(err)
	}
	if obs.Branch == "" {
		t.Fatal("want the real branch reported, not a fabricated blank")
	}
}
```

Implement `addExclude` by reading how
[`gitworktree`'s exclude code](../../../backend/internal/adapters/workspace/gitworktree/) writes
`.git/info/exclude` idempotently, and mirror it. In a non-worktree checkout the file
is at `<path>/.git/info/exclude` directly rather than behind a gitdir pointer; handle
both by resolving `git -C <path> rev-parse --git-dir` and joining `info/exclude` onto
the result.

- [x] **Step 4: Run tests to verify they pass**

Run: `cd backend && go test ./internal/adapters/workspace/inplace/ -v`
Expected: PASS, all six tests, especially the two `NeverRemoves` ones.

- [x] **Step 5: Commit**

```bash
git add backend/internal/adapters/workspace/inplace/
git commit -m "feat(workspace): add the in-place adapter with no-op teardown"
```

---

## Task 5: Carry the mode on the ports and route by it

**Files:**
- Modify: `backend/internal/ports/outbound.go` (`WorkspaceConfig`, `WorkspaceInfo`)
- Modify: `backend/internal/ports/session.go` (`SpawnConfig`)
- Modify: `backend/internal/adapters/workspace/router/router.go`
- Test: `backend/internal/adapters/workspace/router/router_test.go`

**Interfaces:**
- Consumes: `domain.WorkspaceMode` (Task 1), `inplace.Workspace` (Task 4).
- Produces: `ports.WorkspaceConfig.Mode`, `ports.WorkspaceInfo.Mode`, `ports.SpawnConfig.WorkspaceMode`, all of type `domain.WorkspaceMode`; `router.Deps.InPlace ports.Workspace`.

- [x] **Step 1: Write the failing test**

Add to `router_test.go`:

```go
type recordingWorkspace struct {
	ports.Workspace
	destroyed *int
}

func (r recordingWorkspace) Destroy(context.Context, ports.WorkspaceInfo) error {
	if r.destroyed != nil {
		*r.destroyed++
	}
	return nil
}

func TestRouterSendsInPlaceInfoToTheInPlaceAdapter(t *testing.T) {
	git, inPlace := 0, 0
	w := New(Deps{
		Git:     recordingWorkspace{destroyed: &git},
		InPlace: recordingWorkspace{destroyed: &inPlace},
	})
	err := w.Destroy(context.Background(), ports.WorkspaceInfo{
		ProjectID: "p-1", Mode: domain.WorkspaceModeInPlace,
	})
	if err != nil {
		t.Fatal(err)
	}
	if inPlace != 1 || git != 0 {
		t.Fatalf("want the in-place adapter to own teardown, got inPlace=%d git=%d", inPlace, git)
	}
}

func TestRouterSendsWorktreeInfoToTheGitAdapter(t *testing.T) {
	git, inPlace := 0, 0
	w := New(Deps{
		Git:     recordingWorkspace{destroyed: &git},
		InPlace: recordingWorkspace{destroyed: &inPlace},
	})
	err := w.Destroy(context.Background(), ports.WorkspaceInfo{
		ProjectID: "p-1", Mode: domain.WorkspaceModeWorktree,
	})
	if err != nil {
		t.Fatal(err)
	}
	if git != 1 || inPlace != 0 {
		t.Fatalf("want the git adapter, got git=%d inPlace=%d", git, inPlace)
	}
}

func TestRouterErrorsWhenInPlaceIsUnconfigured(t *testing.T) {
	w := New(Deps{Git: plainWorkspace{}})
	if err := w.Destroy(context.Background(), ports.WorkspaceInfo{
		ProjectID: "p-1", Mode: domain.WorkspaceModeInPlace,
	}); err == nil {
		t.Fatal("want an error rather than a silent fall-through to the git adapter")
	}
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/adapters/workspace/router/ -v`
Expected: FAIL — `unknown field Mode` and `unknown field InPlace`.

- [x] **Step 3: Add the fields and the routing**

In `ports/outbound.go`, add to both `WorkspaceConfig` and `WorkspaceInfo`:

```go
	Mode domain.WorkspaceMode
```

In `ports/session.go`, add to `SpawnConfig`:

```go
	WorkspaceMode domain.WorkspaceMode
```

In `router.go`, add `InPlace ports.Workspace` to `Deps` and the `Workspace` struct,
then introduce a mode-aware selector and use it in every method that currently calls
`adapterForProject`:

```go
func (w *Workspace) adapterForMode(ctx context.Context, mode domain.WorkspaceMode, projectID domain.ProjectID) (ports.Workspace, error) {
	if w == nil {
		return nil, errors.New("workspace router: nil router")
	}
	if mode == domain.WorkspaceModeInPlace {
		if w.inPlace == nil {
			return nil, errors.New("workspace router: in-place workspace is not configured")
		}
		return w.inPlace, nil
	}
	return w.adapterForProject(ctx, projectID)
}
```

Every `ports.Workspace` method on the router takes either a `cfg` or an `info`, both
of which now carry `Mode`; change each call site from
`w.adapterForProject(ctx, X.ProjectID)` to `w.adapterForMode(ctx, X.Mode, X.ProjectID)`.
Leave `adapterForProject` in place — `adapterForMode` delegates to it, and the
`WorkspaceProject` methods still use it directly.

- [x] **Step 4: Run tests to verify they pass**

Run: `cd backend && go build ./... && go test ./internal/adapters/workspace/... -v`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add backend/internal/ports/ backend/internal/adapters/workspace/router/
git commit -m "feat(workspace): route teardown by session workspace mode"
```

---

## Task 6: Resolve the mode at spawn and keep it through teardown

**Files:**
- Modify: `backend/internal/session_manager/manager.go` (`Spawn`, `createSessionWorkspace`, `seedRecord`, `workspaceInfo`)
- Test: `backend/internal/session_manager/manager_test.go`

**Interfaces:**
- Consumes: `domain.WorkspaceMode`, `ports.SpawnConfig.WorkspaceMode`, `ports.WorkspaceInfo.Mode`, `domain.SessionMetadata.WorkspaceMode`.
- Produces: `session_manager.ErrInPlaceUnsupported`; `workspaceInfo(rec)` stamped with `rec.Metadata.WorkspaceMode`.

- [x] **Step 1: Write the failing tests**

Add to `manager_test.go`, using the file's existing fixture helpers rather than new ones:

```go
func TestSpawnRejectsInPlaceOnAWorkspaceProject(t *testing.T) {
	m, deps := newTestManager(t)
	deps.project.Kind = domain.ProjectKindWorkspace
	_, _, _, err := m.Spawn(context.Background(), ports.SpawnConfig{
		ProjectID:     deps.project.ID,
		Kind:          domain.SessionKindWorker,
		Harness:       "claude",
		WorkspaceMode: domain.WorkspaceModeInPlace,
	})
	if !errors.Is(err, ErrInPlaceUnsupported) {
		t.Fatalf("want ErrInPlaceUnsupported, got %v", err)
	}
}

func TestSpawnDefaultsToWorktreeWhenTheModeIsAbsent(t *testing.T) {
	m, deps := newTestManager(t)
	rec, _, _, err := m.Spawn(context.Background(), ports.SpawnConfig{
		ProjectID: deps.project.ID,
		Kind:      domain.SessionKindWorker,
		Harness:   "claude",
	})
	if err != nil {
		t.Fatal(err)
	}
	if rec.Metadata.WorkspaceMode != domain.WorkspaceModeWorktree {
		t.Fatalf("an unset spawn mode must resolve to worktree, got %q", rec.Metadata.WorkspaceMode)
	}
}

func TestSpawnInPlaceRecordsTheModeAndCreatesNoBranch(t *testing.T) {
	m, deps := newTestManager(t)
	rec, _, _, err := m.Spawn(context.Background(), ports.SpawnConfig{
		ProjectID:     deps.project.ID,
		Kind:          domain.SessionKindWorker,
		Harness:       "claude",
		WorkspaceMode: domain.WorkspaceModeInPlace,
	})
	if err != nil {
		t.Fatal(err)
	}
	if rec.Metadata.WorkspaceMode != domain.WorkspaceModeInPlace {
		t.Fatalf("want in_place recorded, got %q", rec.Metadata.WorkspaceMode)
	}
	if deps.workspace.lastCreateConfig.Branch != "" {
		t.Fatalf("in-place must request no branch, got %q", deps.workspace.lastCreateConfig.Branch)
	}
	if deps.workspace.lastCreateConfig.Mode != domain.WorkspaceModeInPlace {
		t.Fatalf("the mode must reach the adapter, got %q", deps.workspace.lastCreateConfig.Mode)
	}
}

func TestWorkspaceInfoCarriesTheStoredMode(t *testing.T) {
	info := workspaceInfo(domain.SessionRecord{
		ID: "s-1",
		Metadata: domain.SessionMetadata{
			WorkspacePath: "/tmp/x",
			WorkspaceMode: domain.WorkspaceModeInPlace,
		},
	})
	if info.Mode != domain.WorkspaceModeInPlace {
		t.Fatalf("teardown would route to the wrong adapter: got %q", info.Mode)
	}
}
```

`newTestManager` stands in for whatever fixture `manager_test.go` already uses; read
the top of that file and match it, and extend the existing `fakeWorkspace` with a
`lastCreateConfig ports.WorkspaceConfig` field recorded in its `Create`.

- [x] **Step 2: Run tests to verify they fail**

Run: `cd backend && go test ./internal/session_manager/ -run 'InPlace|WorkspaceMode|workspaceInfo|TestSpawnDefaults' -v`
Expected: FAIL — `undefined: ErrInPlaceUnsupported`.

- [x] **Step 3: Implement**

Declare the error beside the existing `ErrScratchBranchUnsupported`:

```go
var ErrInPlaceUnsupported = errors.New("in-place sessions are only supported for single-repo projects")
```

In `Spawn`, immediately after `projectKind := project.Kind.WithDefault()` and the
existing scratch/branch guard, resolve the mode once and rewrite `cfg`:

```go
	if cfg.WorkspaceMode == "" {
		cfg.WorkspaceMode = domain.WorkspaceModeWorktree
	}
	if !cfg.WorkspaceMode.Valid() {
		return domain.SessionRecord{}, 0, 0, fmt.Errorf("spawn: %w: %q", domain.ErrInvalidWorkspaceMode, cfg.WorkspaceMode)
	}
	if cfg.WorkspaceMode == domain.WorkspaceModeInPlace {
		if projectKind != domain.ProjectKindSingleRepo {
			return domain.SessionRecord{}, 0, 0, fmt.Errorf("spawn: %w", ErrInPlaceUnsupported)
		}
		if strings.TrimSpace(cfg.Branch) != "" {
			return domain.SessionRecord{}, 0, 0, fmt.Errorf("spawn: %w: an in-place session cannot take a branch", ErrInPlaceUnsupported)
		}
	}
```

This sits **before** `m.store.CreateSession`, so a rejected spawn leaves no row.

In `seedRecord` (`manager.go:2560`), carry the mode onto the seed row. After the ACP
removal this function sets **no** `Metadata` field at all, so add one:

```go
		Metadata:         domain.SessionMetadata{WorkspaceMode: cfg.WorkspaceMode},
```

placed after `AutoInjectReview: true,` and aligned with the existing keys. Do not
remove or reorder any field already there.

In `Spawn`, guard the branch derivation:

```go
	branch := cfg.Branch
	if branch == "" && cfg.WorkspaceMode != domain.WorkspaceModeInPlace {
		branch = DefaultSpawnBranch(id, cfg.Kind, sessionPrefix(project), projectKind, m.dataDir)
	}
```

In `createSessionWorkspace`, pass the mode into the adapter call:

```go
		ws, err := m.workspace.Create(ctx, ports.WorkspaceConfig{
			ProjectID:     cfg.ProjectID,
			SessionID:     id,
			Kind:          cfg.Kind,
			SessionPrefix: sessionPrefix(project),
			Branch:        branch,
			BaseBranch:    baseBranch,
			Mode:          cfg.WorkspaceMode,
		})
```

In `workspaceInfo`, stamp the mode so teardown routes correctly:

```go
		Mode: rec.Metadata.WorkspaceMode,
```

Then find every other construction of `ports.WorkspaceConfig` in this file — every
`m.workspace.Restore` call site (grep `m.workspace.Restore(` in this file) — and add
`Mode: rec.Metadata.WorkspaceMode` to each. Restore must route the same way teardown
does.

- [x] **Step 4: Keep the restore marker honest for in-place sessions**

`RestoreAll` skips any session without a `session_worktrees` row, so an in-place
session needs one too or it silently fails to come back after a daemon restart. The
row is a restore marker, not a claim that a worktree exists. Add a test and make it
pass:

```go
func TestSaveAndTeardownAllWritesARestoreMarkerForInPlaceSessions(t *testing.T) {
	m, deps := newTestManager(t)
	rec, _, _, err := m.Spawn(context.Background(), ports.SpawnConfig{
		ProjectID:     deps.project.ID,
		Kind:          domain.SessionKindWorker,
		Harness:       "claude",
		WorkspaceMode: domain.WorkspaceModeInPlace,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := m.SaveAndTeardownAll(context.Background()); err != nil {
		t.Fatal(err)
	}
	rows, err := m.store.ListSessionWorktrees(context.Background(), rec.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 {
		t.Fatalf("want one restore marker so RestoreAll does not skip the session, got %d", len(rows))
	}
	if rows[0].PreservedRef != "" {
		t.Fatalf("an in-place session preserves nothing, got ref %q", rows[0].PreservedRef)
	}
}
```

In `saveAndTeardownOne`, the existing sequence already writes the marker from
`rec.Metadata.WorkspacePath` and `rec.Metadata.Branch`, both of which an in-place
session has. The `StashUncommitted` call returns `""` via the in-place adapter and the
`ForceDestroy` call is a no-op, so the sequence needs no branching — verify that with
the test rather than adding a special case. Only add code here if the test fails.

- [x] **Step 5: Run tests to verify they pass**

Run: `cd backend && go build ./... && go test ./internal/session_manager/ -v`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add backend/internal/session_manager/
git commit -m "feat(session): resolve and persist the workspace mode at spawn"
```

---

## Task 7: Prove the two teardown paths leave the project alone

**Files:**
- Test: `backend/internal/session_manager/manager_test.go`
- Modify: `backend/cmd/opr` (or wherever `router.New` is constructed) to supply `InPlace`

**Interfaces:**
- Consumes: everything from Tasks 4–6.
- Produces: no new API. This task is the safety gate for the whole design.

- [x] **Step 1: Write the failing tests**

```go
func TestKillLeavesAnInPlaceWorkspaceUntouched(t *testing.T) {
	m, deps := newTestManager(t)
	rec, _, _, err := m.Spawn(context.Background(), ports.SpawnConfig{
		ProjectID:     deps.project.ID,
		Kind:          domain.SessionKindWorker,
		Harness:       "claude",
		WorkspaceMode: domain.WorkspaceModeInPlace,
	})
	if err != nil {
		t.Fatal(err)
	}
	freed, err := m.Kill(context.Background(), rec.ID)
	if err != nil {
		t.Fatal(err)
	}
	if freed {
		t.Fatal("an in-place kill frees no workspace")
	}
	if deps.workspace.destroyCalls != 0 {
		t.Fatalf("the git adapter must not be asked to destroy an in-place session, got %d calls", deps.workspace.destroyCalls)
	}
	got, ok, err := m.store.GetSession(context.Background(), rec.ID)
	if err != nil || !ok {
		t.Fatalf("GetSession: %v %v", ok, err)
	}
	if !got.IsTerminated {
		t.Fatal("the session must still be terminated")
	}
}

func TestSaveAndTeardownAllNeverForceDestroysAnInPlaceSession(t *testing.T) {
	m, deps := newTestManager(t)
	if _, _, _, err := m.Spawn(context.Background(), ports.SpawnConfig{
		ProjectID:     deps.project.ID,
		Kind:          domain.SessionKindWorker,
		Harness:       "claude",
		WorkspaceMode: domain.WorkspaceModeInPlace,
	}); err != nil {
		t.Fatal(err)
	}
	if err := m.SaveAndTeardownAll(context.Background()); err != nil {
		t.Fatal(err)
	}
	if deps.workspace.forceDestroyCalls != 0 {
		t.Fatalf("shutdown must never force-destroy an in-place workspace, got %d calls", deps.workspace.forceDestroyCalls)
	}
	if deps.workspace.stashCalls != 0 {
		t.Fatalf("shutdown must not stash an in-place workspace, got %d calls", deps.workspace.stashCalls)
	}
}
```

Extend the existing `fakeWorkspace` in `manager_test.go` with `destroyCalls`,
`forceDestroyCalls` and `stashCalls` counters, and make its `Create` honour
`cfg.Mode` by returning `WorkspaceInfo{Mode: cfg.Mode, ...}` so the fake routes the
way the real router does.

- [x] **Step 2: Run tests to verify they fail**

Run: `cd backend && go test ./internal/session_manager/ -run 'InPlaceWorkspaceUntouched|NeverForceDestroys' -v`
Expected: FAIL — the fake workspace is still called for in-place sessions.

- [x] **Step 3: Wire the in-place adapter into the router at construction**

The router is constructed once, at
`backend/internal/daemon/lifecycle_wiring.go:177`. Immediately before it, beside the
existing `gitWS` and `scratchWS` construction, add:

```go
	inPlaceWS, err := inplaceworkspace.New(inplaceworkspace.Deps{Projects: store})
	if err != nil {
		return nil, nil, nil, fmt.Errorf("in-place session workspace: %w", err)
	}
```

matching that function's four-value error returns, then add `InPlace: inPlaceWS,` to
the `workspacerouter.Deps` literal alongside `Git`, `Scratch` and `Projects`. Import
the package with the `inplaceworkspace` alias, matching how `scratchworkspace` and
`workspacerouter` are already aliased in that file.

Note that `ws` is also handed to `sessionIDClaimProbe` on the line after — that probe
calls `IsSessionIDClaimed`, which the router fans out over its adapters. The in-place
adapter does not implement `ports.SessionIDClaimChecker`, so the router must skip it
there rather than erroring; confirm `IsSessionIDClaimed` still passes its existing
tests after the new adapter is wired in.

- [x] **Step 4: Run the full backend suite**

Run: `cd backend && go build ./... && go vet ./... && go test ./...`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add backend/
git commit -m "test(session): pin that in-place teardown never touches the project"
```

---

## Task 8: Expose the mode over the API

**Files:**
- Modify: `backend/internal/httpd/controllers/dto.go` (spawn request + session read model)
- Modify: `backend/internal/httpd/controllers/sessions.go:318` (pass it into `SpawnConfig`)
- Modify: `backend/internal/httpd/apispec/specgen/build.go`
- Test: `backend/internal/httpd/controllers/sessions_test.go`

**Interfaces:**
- Consumes: `ports.SpawnConfig.WorkspaceMode`, `domain.ParseWorkspaceMode`.
- Produces: request field `workspaceMode` on `POST /api/v1/sessions`; response fields `workspaceMode` and `workspacePath` on the session DTO.

- [x] **Step 1: Write the failing test**

```go
func TestCreateSessionAcceptsInPlaceWorkspaceMode(t *testing.T) {
	srv, svc := newTestServer(t)
	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions",
		`{"projectId":"p-1","kind":"worker","harness":"claude","workspaceMode":"in_place"}`)
	if status != http.StatusOK && status != http.StatusCreated {
		t.Fatalf("status %d: %s", status, body)
	}
	if svc.lastSpawnConfig.WorkspaceMode != domain.WorkspaceModeInPlace {
		t.Fatalf("want in_place forwarded, got %q", svc.lastSpawnConfig.WorkspaceMode)
	}
}

func TestCreateSessionDefaultsToWorktreeWhenOmitted(t *testing.T) {
	srv, svc := newTestServer(t)
	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions",
		`{"projectId":"p-1","kind":"worker","harness":"claude"}`)
	if status != http.StatusOK && status != http.StatusCreated {
		t.Fatalf("status %d: %s", status, body)
	}
	if svc.lastSpawnConfig.WorkspaceMode != domain.WorkspaceModeWorktree {
		t.Fatalf("an omitted mode must resolve to worktree, got %q", svc.lastSpawnConfig.WorkspaceMode)
	}
}

func TestCreateSessionRejectsAnUnknownWorkspaceMode(t *testing.T) {
	srv, _ := newTestServer(t)
	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions",
		`{"projectId":"p-1","kind":"worker","harness":"claude","workspaceMode":"nonsense"}`)
	if status != http.StatusBadRequest {
		t.Fatalf("want 400 for an unknown mode, got %d", status)
	}
}
```

Match the file's existing server fixture and request helper names; `sessions_test.go`
already has a `doRequest` helper, so reuse it and whatever spawn-recording fake the
neighboring create-session tests use.

- [x] **Step 2: Run tests to verify they fail**

Run: `cd backend && go test ./internal/httpd/controllers/ -run TestCreateSession -v`
Expected: FAIL — the mode is not forwarded.

- [x] **Step 3: Implement**

Add to the spawn request struct in `dto.go`:

```go
	WorkspaceMode string `json:"workspaceMode,omitempty"`
```

Add to the session read-model struct in `dto.go`, beside `Branch`:

```go
	WorkspaceMode string `json:"workspaceMode,omitempty"`
	WorkspacePath string `json:"workspacePath,omitempty"`
```

and populate both from `rec.Metadata` wherever that struct is built.

In `sessions.go`, before constructing `ports.SpawnConfig`:

```go
	workspaceMode := domain.WorkspaceModeWorktree
	if raw := strings.TrimSpace(in.WorkspaceMode); raw != "" {
		parsed, err := domain.ParseWorkspaceMode(raw)
		if err != nil {
			apierr.BadRequest(w, r, err.Error())
			return
		}
		workspaceMode = parsed
	}
```

then add `WorkspaceMode: workspaceMode` to the `ports.SpawnConfig` literal at line 318.
Use whatever bad-request helper the surrounding handlers in this file already use in
place of `apierr.BadRequest`.

In `specgen/build.go`, add `workspaceMode` to the create-session request schema (an
enum of `worktree` and `in_place`) and `workspaceMode`/`workspacePath` to the session
response schema, matching how neighboring optional string fields are declared.

- [x] **Step 4: Regenerate the API contract**

Run: `npm run api` from the repo root.
Expected: `frontend/src/api/schema.ts` gains the fields. Commit the regenerated files.

- [x] **Step 5: Run tests to verify they pass**

Run: `cd backend && go test ./internal/httpd/... && npm run frontend:typecheck`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add backend/internal/httpd/ frontend/src/api/
git commit -m "feat(api): accept and report the session workspace mode"
```

---

## Task 9: The desktop checkbox

**Files:**
- Modify: `frontend/src/renderer/components/TaskComposer.tsx`
- Test: `frontend/src/renderer/components/TaskComposer.test.tsx`

**Interfaces:**
- Consumes: the `workspaceMode` request field (Task 8), `projectQuery.data.kind`.
- Produces: `CreateTaskInput.workspaceMode?: "worktree" | "in_place"`.

- [x] **Step 1: Write the failing test**

```tsx
it("does not create a worktree unless the box is checked", async () => {
	renderComposer({ projectKind: "single_repo" });
	await userEvent.type(screen.getByRole("textbox"), "do the thing");
	await userEvent.click(screen.getByRole("button", { name: /start task/i }));
	expect(createTaskSpy).toHaveBeenCalledWith(expect.objectContaining({ workspaceMode: "in_place" }));
});

it("creates a worktree when the box is checked", async () => {
	renderComposer({ projectKind: "single_repo" });
	await userEvent.click(screen.getByRole("checkbox", { name: /worktree/i }));
	await userEvent.type(screen.getByRole("textbox"), "do the thing");
	await userEvent.click(screen.getByRole("button", { name: /start task/i }));
	expect(createTaskSpy).toHaveBeenCalledWith(expect.objectContaining({ workspaceMode: "worktree" }));
});

it("hides the checkbox for a scratch project", async () => {
	renderComposer({ projectKind: "scratch" });
	expect(screen.queryByRole("checkbox", { name: /worktree/i })).not.toBeInTheDocument();
});
```

Follow the existing `TaskComposer.test.tsx` setup for `renderComposer` and the query
mocks; extend its project fixture with `kind` rather than inventing a new harness.

- [x] **Step 2: Run tests to verify they fail**

Run: `cd frontend && npx vitest run src/renderer/components/TaskComposer.test.tsx`
Expected: FAIL — no checkbox in the document.

- [x] **Step 3: Implement**

Add state beside the existing `agent`/`model` state:

```tsx
const [useWorktree, setUseWorktree] = useState(false);
const projectKind = projectQuery.data?.kind ?? "single_repo";
const canChooseWorktree = projectKind === "single_repo";
```

Render a `Checkbox` from `components/ui` in the control row that already holds the
agent picker, model picker and Start task button, gated on `canChooseWorktree`, with
a label reading "Create a git worktree" and an accessible name containing "worktree".

In `submitTask`, add to the `createTask` argument:

```tsx
	workspaceMode: canChooseWorktree ? (useWorktree ? "worktree" : "in_place") : undefined,
```

and extend `CreateTaskInput` with the optional field, forwarding it in the mutation's
request body.

- [x] **Step 4: Run tests and the typecheck**

Run: `cd frontend && npx vitest run src/renderer/components/TaskComposer.test.tsx && npm run typecheck && npm run frontend:lint`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add frontend/src/renderer/components/TaskComposer.tsx frontend/src/renderer/components/TaskComposer.test.tsx
git commit -m "feat(desktop): choose the worktree per task, defaulting to off"
```

---

## Task 10: Show where a session lives on the board

**Files:**
- Modify: `frontend/src/renderer/components/SessionsBoard.tsx:844-932` (the `showBranch` block at 928-934)
- Test: `frontend/src/renderer/components/SessionsBoard.test.tsx`

**Interfaces:**
- Consumes: `session.workspaceMode`, `session.workspacePath`, `session.branch` (Task 8).
- Produces: no new API.

- [x] **Step 1: Write the failing test**

```tsx
it("shows the branch and worktree directory for a worktree session", () => {
	renderBoard({
		sessions: [makeSession({
			id: "opr-1",
			branch: "opr/opr-1",
			workspaceMode: "worktree",
			workspacePath: "/Users/me/.operator/worktrees/opr-1",
		})],
	});
	expect(screen.getByText("opr/opr-1")).toBeInTheDocument();
	expect(screen.getByText(/opr-1$/)).toBeInTheDocument();
});

it("marks an in-place session as running in the project checkout", () => {
	renderBoard({
		sessions: [makeSession({
			id: "opr-2",
			branch: "master",
			workspaceMode: "in_place",
			workspacePath: "/Users/me/dev/Operator",
		})],
	});
	expect(screen.getByTestId("session-location-in-place")).toBeInTheDocument();
	expect(screen.getByText("master")).toBeInTheDocument();
});
```

Reuse the file's existing `renderBoard` and session factory helpers.

- [x] **Step 2: Run tests to verify they fail**

Run: `cd frontend && npx vitest run src/renderer/components/SessionsBoard.test.tsx`
Expected: FAIL — `session-location-in-place` not found.

- [x] **Step 3: Implement**

Replace the `showBranch` block at lines 928-934 with a location row that keeps the
existing `GitBranch` icon and truncation behavior and adds the location:

```tsx
const inPlace = session.workspaceMode === "in_place";
const workspacePath = session.workspacePath || "";
const location = inPlace ? workspacePath : workspacePath.split("/").filter(Boolean).pop() || "";
const showLocation = branch !== "" || location !== "";
```

Render the branch as it renders today, then the location as a second muted segment,
with `data-testid="session-location-in-place"` on the in-place variant and a distinct
icon (`FolderOpen`) so the real checkout is visually separable from a worktree at a
glance. Keep the row a single truncating flex line so long paths cannot widen the
card.

- [x] **Step 4: Run tests, typecheck and lint**

Run: `cd frontend && npx vitest run src/renderer/components/SessionsBoard.test.tsx && npm run typecheck && npm run frontend:lint`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add frontend/src/renderer/components/SessionsBoard.tsx frontend/src/renderer/components/SessionsBoard.test.tsx
git commit -m "feat(desktop): show where each session's workspace lives"
```

---

## Task 11: The mobile toggle

**Files:**
- Modify: `packages/mobile/lib/feature/spawn/data/model/params/spawn_session_params.dart`
- Modify: `packages/mobile/lib/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart`
- Modify: `packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart`
- Test: `packages/mobile/test/feature/spawn/spawn_cubit_test.dart` (create if absent, following the layout of the existing cubit tests)

**Interfaces:**
- Consumes: the `workspaceMode` request field (Task 8), `ProjectModel.kind`.
- Produces: `SpawnSessionParams.workspaceMode` (a `String`), `SpawnCubit.useWorktree` (a `bool`, default `false`).

- [x] **Step 1: Write the failing test**

```dart
void main() {
  group('SpawnSessionParams', () {
    test('defaults to in_place so no worktree is created', () {
      final params = SpawnSessionParams(projectId: 'p-1');
      expect(params.toJson()['workspaceMode'], 'in_place');
    });

    test('sends worktree when the toggle is on', () {
      final params = SpawnSessionParams(projectId: 'p-1', workspaceMode: 'worktree');
      expect(params.toJson()['workspaceMode'], 'worktree');
    });
  });
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/spawn/spawn_cubit_test.dart`
Expected: FAIL — `No named parameter with the name 'workspaceMode'`.

- [x] **Step 3: Implement the params**

```dart
class SpawnSessionParams extends Equatable {
  const SpawnSessionParams({
    required this.projectId,
    this.prompt,
    this.issueId,
    this.harness,
    this.workspaceMode = 'in_place',
  });

  final String projectId;
  final String? prompt;
  final String? issueId;
  final String? harness;
  final String workspaceMode;

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    if (prompt != null && prompt!.isNotEmpty) 'prompt': prompt,
    if (issueId != null && issueId!.isNotEmpty) 'issueId': issueId,
    if (harness != null && harness!.isNotEmpty) 'harness': harness,
    'workspaceMode': workspaceMode,
    'kind': 'worker',
  };

  @override
  List<Object?> get props => [projectId, prompt, issueId, harness, workspaceMode];
}
```

- [x] **Step 4: Add the cubit flag**

In `spawn_cubit.dart`, add a mutable `bool useWorktree = false;` beside the existing
`harness` and `name` fields, and pass
`workspaceMode: useWorktree ? 'worktree' : 'in_place'` when building
`SpawnSessionParams` in `submit`. Emit the existing catalog-ready state after
toggling so the UI rebuilds, matching how `setProject` already signals a rebuild.

- [x] **Step 5: Add the row and fix the copy**

In `spawn_body.dart`, add a third `SettingsRow` inside the existing `SettingsGroup`,
after the Agent row, shown only when the selected project's `kind == 'single_repo'`:

```dart
if (project?.kind == 'single_repo')
  SettingsRow(
    icon: Icons.call_split,
    label: 'Create a git worktree',
    trailing: Switch(
      value: _cubit.useWorktree,
      onChanged: (value) => _cubit.setUseWorktree(value),
    ),
  ),
```

Replace the standing description, which currently promises isolation unconditionally:

```dart
AppText(
  _cubit.useWorktree
      ? 'Spawn a worker agent. It gets its own isolated worktree, then starts on the task you give it.'
      : 'Spawn a worker agent. It works directly in the project checkout, on the branch already there.',
  style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary),
  maxLines: 3,
),
```

Add `void setUseWorktree(bool value)` to the cubit rather than assigning the field
from the widget, matching how `setProject` is exposed.

- [x] **Step 6: Run the mobile gate**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!` and a green suite.

- [x] **Step 7: Show the location on the mobile session card**

The spec requires the mobile session card to carry the same distinction as the desktop
board. Find the card widget under `packages/mobile/lib/feature/sessions/presentation/`
that renders a session's branch, add `workspaceMode` and `workspacePath` to
`SessionModel` (hand-written `fromJson`, all fields nullable, per package convention),
and render the project path with a distinct icon when the mode is `in_place` and the
branch plus worktree directory name otherwise. Add a widget test asserting both forms
render, following the layout of the existing session-card tests.

- [x] **Step 8: Re-run the mobile gate**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!` and a green suite.

- [x] **Step 9: Commit**

```bash
git add packages/mobile/
git commit -m "feat(mobile): choose the worktree at spawn, defaulting to off"
```

---

## Task 12: Full-stack verification

**Files:** none modified unless a gate fails.

- [x] **Step 1: Run every gate**

```bash
npm run lint
npm run frontend:typecheck
cd backend && go test -race ./...
cd packages/mobile && flutter analyze && flutter test
```

Expected: all green. `go test -race` matters here because the router now selects an
adapter per call rather than per project.

- [ ] **Step 2: Manual smoke — the safety property**

Register a `single_repo` project, create a session from the desktop composer with the
box **unchecked**, confirm the agent's cwd is the project directory and no new branch
exists (`git -C <project> branch --list`). Kill the session. Confirm the project
directory, its `.git`, and its working-tree contents are all intact, and that
`git -C <project> status` is unchanged apart from anything the agent itself wrote.

- [ ] **Step 3: Manual smoke — the shutdown path**

Spawn an in-place session, then stop the daemon (`opr stop` or equivalent) while it is
live. Confirm the project directory survives shutdown untouched, and that
`refs/opr/preserved/` gained no ref for that session:
`git -C <project> for-each-ref refs/opr/preserved/`.

- [x] **Step 4: Update the docs**

Add the two workspace modes to `docs/architecture.md` wherever session workspaces are
described, and note in `AGENTS.md` that in-place sessions exist and that their
teardown is a deliberate no-op.

- [x] **Step 5: Commit**

```bash
git add docs/ AGENTS.md
git commit -m "docs: describe the two session workspace modes"
```
