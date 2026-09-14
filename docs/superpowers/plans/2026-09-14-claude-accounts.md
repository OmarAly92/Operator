# Claude Accounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Claude Code sessions on more than one Claude account.
- **Settings:** lists the accounts.
- **Spawn:** picks an account.
- **Running sessions:** can switch account.
- **Setup:** every account shares the user's Claude setup.

**Architecture:**
- **Storage:** a daemon-owned `claude_accounts` table, plus a `claude_account_id` on every session.
- **Launch:** the session manager's single env builder applies the account (`CLAUDE_CONFIG_DIR` set, or the key removed for the default) at every launch. The Claude adapter, transcript resolver and usage collector read the folder from that env instead of assuming `~/.claude`.
- **Switching:** account switching rides the existing agent-switch saga with an account-aware target.

**Tech Stack:**
- **Backend:** Go (chi, sqlc over SQLite, goose migrations)
- **Desktop:** React + TanStack Query + shadcn in Tauri
- **Mobile:** Flutter (Cubit, mocktail, bloc_test)

**Spec:** [`docs/superpowers/specs/2026-09-14-claude-accounts-design.md`](../specs/2026-09-14-claude-accounts-design.md). **§13 amendments supersede earlier sections.** Evidence: [`docs/superpowers/evidence/claude-accounts-probes.md`](../evidence/claude-accounts-probes.md) (P1–P7).

## Global Constraints

**Code style**
- **No code comments** in new or changed code (user rule). Add a doc comment only if `npm run lint` fails for a missing one on an exported identifier.

**Account env and folders**
- **Default account:** removes `CLAUDE_CONFIG_DIR` from the env map; never sets it to `""` (P7, spec §13.1).
- **Non-default account:** sets `CLAUDE_CONFIG_DIR` to `config_dir` byte-identical. `config_dir` is written once, never updated, never `~`, no trailing slash, never symlink-resolved (P3).
- **New folder:** `$HOME/.claude-<slug>`, mode `0700`.
- **Slug:** lowercase, runs of non-`[a-z0-9]` become `-`, trimmed of `-`.
- **Label:** trimmed, 1–32 runes.
- **Shared setup items, in this order:** `CLAUDE.md`, `settings.json`, `skills`, `commands`, `agents`, `plugins`.
- **Account status probe:** `claude auth status`, 3 s timeout, 30 s cache per account.

**Error codes (exact strings)**
- `CLAUDE_ACCOUNT_EXISTS`
- `CLAUDE_ACCOUNT_LABEL_INVALID`
- `CLAUDE_ACCOUNT_NOT_FOUND`
- `CLAUDE_ACCOUNT_DEFAULT_IMMUTABLE`
- `CLAUDE_ACCOUNT_IN_USE`
- `CLAUDE_ACCOUNT_FOLDER_UNAVAILABLE`
- `INVALID_CLAUDE_ACCOUNT`

**Generated files and databases**
- **SQL:** never hand-edit `backend/internal/storage/sqlite/gen/*`; edit queries/migrations and run `npm run sqlc` from the repo root.
- **API:** after any DTO/route change, run `npm run api` and commit `backend/internal/httpd/apispec/openapi.yaml` plus `frontend/src/api/schema.ts`.
- **Safety:** tests must never touch the real `~/.claude`, `~/.claude.json` or Keychain. Use `t.TempDir()` and `t.Setenv("HOME", ...)`.

**Desktop**
- **Text:** all visible text through `t()`, with keys added to **all 8** files in `frontend/src/renderer/i18n/*.json` (English text in each).
- **Components:** build from `components/ui/*` primitives.

**Mobile**
- Cubit only; hand-written models with nullable fields; `EndPoints` constants; raw int spacing; inline English copy.

**Gates per area**
- **Backend:** `cd backend && go test ./...`, then `npm run lint`.
- **Desktop:** `npm run frontend:typecheck`, `npm run frontend:lint`, `cd frontend && npx vitest run <files>`.
- **Mobile:** `cd packages/mobile && flutter analyze && flutter test`.

**Branch and commits**
- Branch `feat/claude-accounts` (already checked out).
- One commit per task. Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  ```

---

## File Structure

| File | Responsibility |
|---|---|
| `backend/internal/domain/claude_account.go` | `ClaudeAccountID`, `ClaudeAccount`, `ApplyEnv`, errors |
| `backend/internal/storage/sqlite/migrations/0109_claude_accounts.sql` | table, default row, session + switch columns |
| `backend/internal/storage/sqlite/queries/claude_accounts.sql` | account queries |
| `backend/internal/storage/sqlite/store/claude_accounts_store.go` | account persistence |
| `backend/internal/adapters/agent/claudecode/claudesetup/setup.go` | shared-setup links, inspect, relink |
| `backend/internal/adapters/agent/claudecode/claudesetup/mcp.go` | per-path lock, MCP sync |
| `backend/internal/adapters/agent/claudecode/claudecode.go` | `claudeGlobalConfigPath`, `PreLaunch` from env |
| `backend/internal/adapters/agent/claudecode/claim.go` | multi-folder claim check |
| `backend/internal/service/claudeaccounts/service.go` | registry, create/adopt, rename, delete, launch prep, env lookup |
| `backend/internal/service/claudeaccounts/status.go` | `claude auth status` probe + cache |
| `backend/internal/session_manager/claude_account.go` | manager-side account env + spawn/switch account resolution |
| `backend/internal/httpd/controllers/claude_accounts.go` | `/claude-accounts` routes, error mapping |
| `frontend/src/renderer/hooks/useClaudeAccounts.ts` | queries and mutations |
| `frontend/src/renderer/components/settings/ClaudeAccountsSection.tsx` | Settings section + add dialog |
| `frontend/src/renderer/components/ClaudeAccountSelect.tsx` | account select shared by composer and switch dialog |
| `packages/mobile/lib/feature/spawn/data/model/claude_account_model.dart` | wire model |
| `packages/mobile/lib/core/widgets/pickers/claude_account_picker_sheet.dart` | picker sheet |

---

### Task 1: Domain types

**Files:**
- Create: `backend/internal/domain/claude_account.go`
- Create: `backend/internal/domain/claude_account_test.go`
- Modify: `backend/internal/domain/session.go:84-120` (`SessionRecord`)
- Modify: `backend/internal/domain/agent_switching.go:293-318` (`AgentSwitch`), `:334-345` (`AgentSwitchTargetActivation`), and `ComputeAgentSwitchRequestFingerprint`

**Interfaces:**
- Produces:
  - `type ClaudeAccountID string`
  - `const DefaultClaudeAccountID ClaudeAccountID = "default"`
  - `const ClaudeConfigDirEnv = "CLAUDE_CONFIG_DIR"`
  - `type ClaudeAccount struct{ID ClaudeAccountID; Label string; ConfigDir string; IsDefault bool; CreatedAt time.Time}`
  - `func (a ClaudeAccount) ApplyEnv(env map[string]string)`
  - `func NormalizeClaudeAccountID(id ClaudeAccountID) ClaudeAccountID`
  - errors `ErrClaudeAccountNotFound`, `ErrClaudeAccountExists`, `ErrClaudeAccountLabelInvalid`, `ErrClaudeAccountDefaultImmutable`, `ErrClaudeAccountInUse`, `ErrClaudeAccountFolderUnavailable`, `ErrInvalidClaudeAccount`
  - fields `SessionRecord.ClaudeAccountID`, `AgentSwitch.FromClaudeAccountID`, `AgentSwitch.TargetClaudeAccountID`, `AgentSwitchTargetActivation.SourceClaudeAccountID`, `AgentSwitchTargetActivation.TargetClaudeAccountID`
  - `ComputeAgentSwitchRequestFingerprint(id SessionID, target AgentHarness, targetAccount ClaudeAccountID, note string)`

- [ ] **Step 1: Write the failing test**

`backend/internal/domain/claude_account_test.go`:

```go
package domain

import "testing"

func TestClaudeAccountApplyEnvDefaultRemovesKey(t *testing.T) {
	env := map[string]string{ClaudeConfigDirEnv: "/project/override", "PATH": "/bin"}
	ClaudeAccount{ID: DefaultClaudeAccountID, IsDefault: true}.ApplyEnv(env)
	if _, ok := env[ClaudeConfigDirEnv]; ok {
		t.Fatalf("default account left %s in env: %q", ClaudeConfigDirEnv, env[ClaudeConfigDirEnv])
	}
	if env["PATH"] != "/bin" {
		t.Fatalf("PATH changed: %q", env["PATH"])
	}
}

func TestClaudeAccountApplyEnvSetsExactFolder(t *testing.T) {
	env := map[string]string{ClaudeConfigDirEnv: "/project/override"}
	ClaudeAccount{ID: "personal", ConfigDir: "/Users/u/.claude-personal"}.ApplyEnv(env)
	if got := env[ClaudeConfigDirEnv]; got != "/Users/u/.claude-personal" {
		t.Fatalf("%s = %q", ClaudeConfigDirEnv, got)
	}
}

func TestNormalizeClaudeAccountID(t *testing.T) {
	if got := NormalizeClaudeAccountID(""); got != DefaultClaudeAccountID {
		t.Fatalf("empty -> %q", got)
	}
	if got := NormalizeClaudeAccountID("personal"); got != "personal" {
		t.Fatalf("personal -> %q", got)
	}
}

func TestAgentSwitchFingerprintIncludesTargetAccount(t *testing.T) {
	a := ComputeAgentSwitchRequestFingerprint("s-1", HarnessClaudeCode, "personal", "")
	b := ComputeAgentSwitchRequestFingerprint("s-1", HarnessClaudeCode, "default", "")
	if a == b {
		t.Fatal("fingerprints for different target accounts are equal")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/domain/ -run 'ClaudeAccount|FingerprintIncludesTargetAccount'`
Expected: FAIL — `undefined: ClaudeConfigDirEnv` (compile error).

- [ ] **Step 3: Implement**

`backend/internal/domain/claude_account.go`:

```go
package domain

import (
	"errors"
	"time"
)

type ClaudeAccountID string

const (
	DefaultClaudeAccountID ClaudeAccountID = "default"
	ClaudeConfigDirEnv                     = "CLAUDE_CONFIG_DIR"
)

var (
	ErrClaudeAccountNotFound          = errors.New("claude account not found")
	ErrClaudeAccountExists            = errors.New("claude account already exists")
	ErrClaudeAccountLabelInvalid      = errors.New("claude account label is invalid")
	ErrClaudeAccountDefaultImmutable  = errors.New("the default claude account cannot be removed")
	ErrClaudeAccountInUse             = errors.New("claude account is used by a session")
	ErrClaudeAccountFolderUnavailable = errors.New("claude account folder is unavailable")
	ErrInvalidClaudeAccount           = errors.New("claude account is not valid for this request")
)

type ClaudeAccount struct {
	ID        ClaudeAccountID `json:"id"`
	Label     string          `json:"label"`
	ConfigDir string          `json:"configDir,omitempty"`
	IsDefault bool            `json:"isDefault"`
	CreatedAt time.Time       `json:"createdAt"`
}

func (a ClaudeAccount) ApplyEnv(env map[string]string) {
	if a.IsDefault {
		delete(env, ClaudeConfigDirEnv)
		return
	}
	env[ClaudeConfigDirEnv] = a.ConfigDir
}

func NormalizeClaudeAccountID(id ClaudeAccountID) ClaudeAccountID {
	if id == "" {
		return DefaultClaudeAccountID
	}
	return id
}
```

In `session.go`, add to `SessionRecord` directly after `SpawnedBy`:

```go
	ClaudeAccountID ClaudeAccountID `json:"claudeAccountId"`
```

In `agent_switching.go`, add to `AgentSwitch` directly after `TargetHarness`:

```go
	FromClaudeAccountID   ClaudeAccountID `json:"fromClaudeAccountId,omitempty"`
	TargetClaudeAccountID ClaudeAccountID `json:"targetClaudeAccountId,omitempty"`
```

Add to `AgentSwitchTargetActivation` directly after `TargetHarness`:

```go
	SourceClaudeAccountID ClaudeAccountID
	TargetClaudeAccountID ClaudeAccountID
```

**Update `ComputeAgentSwitchRequestFingerprint`:**
1. Read the function (`grep -n 'func ComputeAgentSwitchRequestFingerprint' backend/internal/domain/*.go`).
2. Insert a `targetAccount ClaudeAccountID` parameter between the harness and the note.
3. Feed `string(targetAccount)` into the hash exactly the way the harness is fed (same separator), immediately after the harness.
4. Update every caller: `grep -rn 'ComputeAgentSwitchRequestFingerprint(' backend/internal`.
   - In `session_manager/agent_switching.go:84` pass `cfg.TargetClaudeAccountID`. That field is added in Task 7; until then pass `""`, and Task 7 replaces it.
   - Existing test callers pass `""`.

- [ ] **Step 4: Run tests**

Run: `cd backend && go test ./internal/domain/ && go build ./...`
Expected: PASS, build clean.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/domain backend/internal/session_manager
git commit -m "feat(domain): Claude account types and session ownership field" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Storage — migration, queries, store

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0109_claude_accounts.sql`
- Create: `backend/internal/storage/sqlite/queries/claude_accounts.sql`
- Create: `backend/internal/storage/sqlite/store/claude_accounts_store.go`
- Create: `backend/internal/storage/sqlite/store/claude_accounts_store_test.go`
- Create: `backend/internal/storage/sqlite/store/agent_switching_validate_internal_test.go`
- Modify: `backend/sqlc.yaml` (overrides)
- Modify: `backend/internal/storage/sqlite/queries/sessions.sql` (`InsertSession`, `GetSession`, `ListSessionsByProject`, `ListAllSessions`)
- Modify: `backend/internal/storage/sqlite/queries/agent_switching.sql` (`InsertAgentSwitch`, every `agent_switches` SELECT, `ActivateSessionAgentSwitchTarget`)
- Modify: `backend/internal/storage/sqlite/store/session_store.go:395-500` (`rowToRecord`, `recordToInsert`)
- Modify: `backend/internal/storage/sqlite/store/agent_switching_store.go` (`CreateAgentSwitch`, `agentSwitchFromGen`, `ActivateAgentSwitchTarget:467-552`, `validateAgentSwitchTargetActivation:648`)

**Interfaces:**
- Consumes: Task 1 domain types.
- Produces, on `*sqlite.Store`:
  - `ListClaudeAccounts(ctx) ([]domain.ClaudeAccount, error)` — default first
  - `GetClaudeAccount(ctx, id domain.ClaudeAccountID) (domain.ClaudeAccount, error)` — `domain.ErrClaudeAccountNotFound` when missing
  - `InsertClaudeAccount(ctx, domain.ClaudeAccount) error`
  - `RenameClaudeAccount(ctx, id, label string) error`
  - `DeleteClaudeAccount(ctx, id) error` — `ErrClaudeAccountNotFound` / `ErrClaudeAccountDefaultImmutable` / `ErrClaudeAccountInUse`
- Session rows persist `ClaudeAccountID` on insert (empty → `default`) and read it back. `UpdateSession` deliberately does **not** write it, so a stale record can't undo a switch.
- `ActivateAgentSwitchTarget` sets `sessions.claude_account_id` to `activation.TargetClaudeAccountID`.

- [ ] **Step 1: Write the migration**

`0109_claude_accounts.sql`:

```sql
-- +goose Up
CREATE TABLE claude_accounts (
    id         TEXT PRIMARY KEY,
    label      TEXT NOT NULL UNIQUE,
    config_dir TEXT UNIQUE,
    is_default INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL,
    CHECK ((is_default = 1 AND config_dir IS NULL) OR (is_default = 0 AND config_dir IS NOT NULL))
);
CREATE UNIQUE INDEX idx_claude_accounts_single_default ON claude_accounts (is_default) WHERE is_default = 1;
INSERT INTO claude_accounts (id, label, config_dir, is_default, created_at)
VALUES ('default', 'Default', NULL, 1, CURRENT_TIMESTAMP);
ALTER TABLE sessions ADD COLUMN claude_account_id TEXT NOT NULL DEFAULT 'default';
CREATE INDEX idx_sessions_claude_account ON sessions (claude_account_id);
ALTER TABLE agent_switches ADD COLUMN from_claude_account_id TEXT NOT NULL DEFAULT '';
ALTER TABLE agent_switches ADD COLUMN target_claude_account_id TEXT NOT NULL DEFAULT '';

-- +goose Down
ALTER TABLE agent_switches DROP COLUMN target_claude_account_id;
ALTER TABLE agent_switches DROP COLUMN from_claude_account_id;
DROP INDEX idx_sessions_claude_account;
ALTER TABLE sessions DROP COLUMN claude_account_id;
DROP INDEX idx_claude_accounts_single_default;
DROP TABLE claude_accounts;
```

- [ ] **Step 2: Write queries**

`queries/claude_accounts.sql`:

```sql
-- name: ListClaudeAccounts :many
SELECT id, label, config_dir, is_default, created_at
FROM claude_accounts
ORDER BY is_default DESC, created_at, id;

-- name: GetClaudeAccount :one
SELECT id, label, config_dir, is_default, created_at
FROM claude_accounts WHERE id = ?;

-- name: InsertClaudeAccount :exec
INSERT INTO claude_accounts (id, label, config_dir, is_default, created_at)
VALUES (?, ?, ?, 0, ?);

-- name: RenameClaudeAccount :execrows
UPDATE claude_accounts SET label = ? WHERE id = ?;

-- name: CountSessionsByClaudeAccount :one
SELECT COUNT(*) FROM sessions WHERE claude_account_id = ?;

-- name: DeleteClaudeAccount :execrows
DELETE FROM claude_accounts WHERE id = ? AND is_default = 0;
```

**`sessions.sql`** — append the new column at the **end** of each list, so sqlc keeps reusing the existing row types:
- `InsertSession`: column list ends `..., auto_inject_review, claude_account_id`, and the final `VALUES` row becomes `?, ?, ?, ?, ?, ?`.
- `GetSession`, `ListSessionsByProject`, `ListAllSessions`: select list ends `..., auto_inject_review, spawned_by, claude_account_id`.
- Also run `grep -n 'auto_inject_review, spawned_by$' backend/internal/storage/sqlite/queries/*.sql` and append to any other hit.

**`agent_switching.sql`:**
- `InsertAgentSwitch`: append `, from_claude_account_id, target_claude_account_id` after `final_handoff_path, final_handoff_hash`, and add `, ?, ?` to `VALUES`.
- Every `SELECT` whose list contains `final_handoff_path, final_handoff_hash` (`grep -n 'final_handoff_hash' backend/internal/storage/sqlite/queries/agent_switching.sql`): append `, from_claude_account_id, target_claude_account_id` right after `final_handoff_hash`.
- `ActivateSessionAgentSwitchTarget`: add `claude_account_id = sqlc.arg(target_claude_account_id),` directly after `harness = sqlc.arg(target_harness),`.

- [ ] **Step 3: Add sqlc overrides and generate**

Append to `backend/sqlc.yaml` overrides, directly after the `sessions.spawned_by` entry:

```yaml
          - column: "sessions.claude_account_id"
            go_type:
              import: "github.com/OmarAly92/operator/backend/internal/domain"
              type: "ClaudeAccountID"
          - column: "claude_accounts.id"
            go_type:
              import: "github.com/OmarAly92/operator/backend/internal/domain"
              type: "ClaudeAccountID"
          - column: "claude_accounts.is_default"
            go_type: "bool"
          - column: "agent_switches.from_claude_account_id"
            go_type:
              import: "github.com/OmarAly92/operator/backend/internal/domain"
              type: "ClaudeAccountID"
          - column: "agent_switches.target_claude_account_id"
            go_type:
              import: "github.com/OmarAly92/operator/backend/internal/domain"
              type: "ClaudeAccountID"
```

Run: `npm run sqlc`
Expected: `gen/claude_accounts.sql.go` created. `go build ./...` in `backend` now fails only where the new params/fields are unused or missing — the next steps fix those.

- [ ] **Step 4: Write the failing store tests**

`claude_accounts_store_test.go` — same package as `store_test.go`, which declares `newTestStore`, `seedProject`, `budgetTestRecord`:

```go
package sqlite_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestClaudeAccountsMigrationSeedsDefault(t *testing.T) {
	s := newTestStore(t)
	accounts, err := s.ListClaudeAccounts(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(accounts) != 1 {
		t.Fatalf("accounts = %+v, want only default", accounts)
	}
	got := accounts[0]
	if got.ID != domain.DefaultClaudeAccountID || !got.IsDefault || got.ConfigDir != "" || got.Label != "Default" {
		t.Fatalf("default = %+v", got)
	}
}

func TestClaudeAccountsInsertRenameGet(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	created := domain.ClaudeAccount{ID: "personal", Label: "Personal", ConfigDir: "/Users/u/.claude-personal", CreatedAt: time.Now().UTC()}
	if err := s.InsertClaudeAccount(ctx, created); err != nil {
		t.Fatal(err)
	}
	if err := s.RenameClaudeAccount(ctx, "personal", "Home"); err != nil {
		t.Fatal(err)
	}
	got, err := s.GetClaudeAccount(ctx, "personal")
	if err != nil {
		t.Fatal(err)
	}
	if got.Label != "Home" || got.ConfigDir != "/Users/u/.claude-personal" || got.IsDefault {
		t.Fatalf("got %+v", got)
	}
	accounts, err := s.ListClaudeAccounts(ctx)
	if err != nil || len(accounts) != 2 || accounts[0].ID != domain.DefaultClaudeAccountID {
		t.Fatalf("list = %+v err=%v, want default first", accounts, err)
	}
	if _, err := s.GetClaudeAccount(ctx, "missing"); !errors.Is(err, domain.ErrClaudeAccountNotFound) {
		t.Fatalf("missing err = %v", err)
	}
}

func TestClaudeAccountsInsertRejectsEmptyFolder(t *testing.T) {
	s := newTestStore(t)
	err := s.InsertClaudeAccount(context.Background(), domain.ClaudeAccount{ID: "x", Label: "X", CreatedAt: time.Now().UTC()})
	if !errors.Is(err, domain.ErrClaudeAccountFolderUnavailable) {
		t.Fatalf("err = %v", err)
	}
}

func TestDeleteClaudeAccountRules(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "proj-1")
	now := time.Now().UTC()
	for _, a := range []domain.ClaudeAccount{
		{ID: "personal", Label: "Personal", ConfigDir: "/Users/u/.claude-personal", CreatedAt: now},
		{ID: "spare", Label: "Spare", ConfigDir: "/Users/u/.claude-spare", CreatedAt: now},
	} {
		if err := s.InsertClaudeAccount(ctx, a); err != nil {
			t.Fatal(err)
		}
	}
	rec := budgetTestRecord("proj-1", domain.KindWorker, "", now)
	rec.ClaudeAccountID = "personal"
	created, err := s.CreateSession(ctx, rec)
	if err != nil {
		t.Fatal(err)
	}
	stored, ok, err := s.GetSession(ctx, created.ID)
	if err != nil || !ok || stored.ClaudeAccountID != "personal" {
		t.Fatalf("stored account = %q ok=%v err=%v", stored.ClaudeAccountID, ok, err)
	}
	if err := s.DeleteClaudeAccount(ctx, domain.DefaultClaudeAccountID); !errors.Is(err, domain.ErrClaudeAccountDefaultImmutable) {
		t.Fatalf("delete default err = %v", err)
	}
	if err := s.DeleteClaudeAccount(ctx, "personal"); !errors.Is(err, domain.ErrClaudeAccountInUse) {
		t.Fatalf("delete in-use err = %v", err)
	}
	if err := s.DeleteClaudeAccount(ctx, "missing"); !errors.Is(err, domain.ErrClaudeAccountNotFound) {
		t.Fatalf("delete missing err = %v", err)
	}
	if err := s.DeleteClaudeAccount(ctx, "spare"); err != nil {
		t.Fatalf("delete spare err = %v", err)
	}
}

func TestSessionWithoutAccountDefaults(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "proj-1")
	created, err := s.CreateSession(ctx, budgetTestRecord("proj-1", domain.KindWorker, "", time.Now().UTC()))
	if err != nil {
		t.Fatal(err)
	}
	stored, _, err := s.GetSession(ctx, created.ID)
	if err != nil || stored.ClaudeAccountID != domain.DefaultClaudeAccountID {
		t.Fatalf("account = %q err=%v", stored.ClaudeAccountID, err)
	}
}
```

**Before running:** check the package clause at the top of `store_test.go` and use the same one. Check `GetSession`'s return shape in `session_store.go`; if it differs from `(rec, ok, err)`, match it.

`agent_switching_validate_internal_test.go`: use the non-`_test` package name declared in `agent_switching_store.go`.

```go
package sqlite

import (
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func activationFixture() domain.AgentSwitchTargetActivation {
	return domain.AgentSwitchTargetActivation{
		SwitchID: "switch-1", SessionID: "s-1",
		SourceHarness: domain.HarnessClaudeCode, SourceClaudeAccountID: "default",
		SourceGenerationID: "g-1", TargetGenerationID: "g-2",
		TargetHarness: domain.HarnessClaudeCode, TargetClaudeAccountID: "personal",
		TargetNativeSessionRef: "n-1", RuntimeHandleID: "h-1", ActivatedAt: time.Now(),
	}
}

func TestValidateActivationAllowsSameHarnessAcrossAccounts(t *testing.T) {
	if err := validateAgentSwitchTargetActivation(activationFixture()); err != nil {
		t.Fatalf("err = %v", err)
	}
}

func TestValidateActivationRejectsSameHarnessSameAccount(t *testing.T) {
	a := activationFixture()
	a.TargetClaudeAccountID = a.SourceClaudeAccountID
	if err := validateAgentSwitchTargetActivation(a); err == nil {
		t.Fatal("expected error for identical harness and account")
	}
}
```

Run: `cd backend && go test ./internal/storage/sqlite/store/ -run 'ClaudeAccount|SessionWithoutAccount|ValidateActivation'`
Expected: FAIL (compile: `s.ListClaudeAccounts undefined`).

- [ ] **Step 5: Implement the store**

`claude_accounts_store.go` — use the store directory's package name. Before writing, read how `SetAppUILocale` in `app_settings_store.go` performs a single write (which querier, whether it takes `s.writeMu`) and mirror it in `InsertClaudeAccount` and `RenameClaudeAccount`.

```go
package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/gen"
)

func claudeAccountFromGen(row gen.ClaudeAccount) domain.ClaudeAccount {
	return domain.ClaudeAccount{
		ID:        row.ID,
		Label:     row.Label,
		ConfigDir: row.ConfigDir.String,
		IsDefault: row.IsDefault,
		CreatedAt: row.CreatedAt,
	}
}

func (s *Store) ListClaudeAccounts(ctx context.Context) ([]domain.ClaudeAccount, error) {
	rows, err := s.qr.ListClaudeAccounts(ctx)
	if err != nil {
		return nil, fmt.Errorf("list claude accounts: %w", err)
	}
	out := make([]domain.ClaudeAccount, 0, len(rows))
	for _, row := range rows {
		out = append(out, claudeAccountFromGen(row))
	}
	return out, nil
}

func (s *Store) GetClaudeAccount(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error) {
	row, err := s.qr.GetClaudeAccount(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.ClaudeAccount{}, domain.ErrClaudeAccountNotFound
	}
	if err != nil {
		return domain.ClaudeAccount{}, fmt.Errorf("get claude account %s: %w", id, err)
	}
	return claudeAccountFromGen(row), nil
}

func (s *Store) InsertClaudeAccount(ctx context.Context, account domain.ClaudeAccount) error {
	if strings.TrimSpace(account.ConfigDir) == "" {
		return fmt.Errorf("insert claude account %s: %w", account.ID, domain.ErrClaudeAccountFolderUnavailable)
	}
	err := s.qw.InsertClaudeAccount(ctx, gen.InsertClaudeAccountParams{
		ID:        account.ID,
		Label:     account.Label,
		ConfigDir: sql.NullString{String: account.ConfigDir, Valid: true},
		CreatedAt: account.CreatedAt,
	})
	if err != nil {
		return fmt.Errorf("insert claude account %s: %w", account.ID, err)
	}
	return nil
}

func (s *Store) RenameClaudeAccount(ctx context.Context, id domain.ClaudeAccountID, label string) error {
	n, err := s.qw.RenameClaudeAccount(ctx, gen.RenameClaudeAccountParams{Label: label, ID: id})
	if err != nil {
		return fmt.Errorf("rename claude account %s: %w", id, err)
	}
	if n == 0 {
		return domain.ErrClaudeAccountNotFound
	}
	return nil
}

func (s *Store) DeleteClaudeAccount(ctx context.Context, id domain.ClaudeAccountID) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	tx, err := s.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin delete claude account %s: %w", id, err)
	}
	defer func() { _ = tx.Rollback() }()
	q := s.qw.WithTx(tx)
	row, err := q.GetClaudeAccount(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.ErrClaudeAccountNotFound
	}
	if err != nil {
		return fmt.Errorf("delete claude account %s: read: %w", id, err)
	}
	if row.IsDefault {
		return domain.ErrClaudeAccountDefaultImmutable
	}
	count, err := q.CountSessionsByClaudeAccount(ctx, id)
	if err != nil {
		return fmt.Errorf("delete claude account %s: count sessions: %w", id, err)
	}
	if count > 0 {
		return domain.ErrClaudeAccountInUse
	}
	if _, err := q.DeleteClaudeAccount(ctx, id); err != nil {
		return fmt.Errorf("delete claude account %s: %w", id, err)
	}
	return tx.Commit()
}
```

**If sqlc names differ from these, use the generated names.** Check `gen/claude_accounts.sql.go` for `InsertClaudeAccountParams`, `RenameClaudeAccountParams` and the `CountSessionsByClaudeAccount` parameter type.

**`session_store.go`:**
- In `rowToRecord`, add `ClaudeAccountID: domain.NormalizeClaudeAccountID(row.ClaudeAccountID),` next to `SpawnedBy`.
- In `recordToInsert`, add `ClaudeAccountID: domain.NormalizeClaudeAccountID(rec.ClaudeAccountID),` next to `SpawnedBy`.
- Do not add it to `recordToUpdate`.

**`agent_switching_store.go`:**
- **`CreateAgentSwitch`** insert params: add `FromClaudeAccountID: rec.FromClaudeAccountID, TargetClaudeAccountID: rec.TargetClaudeAccountID`.
- **`agentSwitchFromGen`:** map `FromClaudeAccountID: row.FromClaudeAccountID, TargetClaudeAccountID: row.TargetClaudeAccountID`.
- **`ActivateAgentSwitchTarget`**, in the mismatch check at `:489-495`, add
  `|| sw.FromClaudeAccountID != activation.SourceClaudeAccountID || sw.TargetClaudeAccountID != activation.TargetClaudeAccountID`.
  In the `ActivateSessionAgentSwitchTargetParams` literal, add `TargetClaudeAccountID: domain.NormalizeClaudeAccountID(activation.TargetClaudeAccountID),`.
- **`validateAgentSwitchTargetActivation`:** replace the harness line (`:654`) with:

```go
	if !activation.SourceHarness.IsKnown() || !activation.TargetHarness.IsKnown() {
		return fmt.Errorf("activate agent switch target %s: known source and target harnesses are required", activation.SwitchID)
	}
	if activation.SourceHarness == activation.TargetHarness &&
		domain.NormalizeClaudeAccountID(activation.SourceClaudeAccountID) == domain.NormalizeClaudeAccountID(activation.TargetClaudeAccountID) {
		return fmt.Errorf("activate agent switch target %s: target must differ from source by harness or Claude account", activation.SwitchID)
	}
```

- [ ] **Step 6: Run tests**

Run: `cd backend && go build ./... && go test ./internal/storage/... ./internal/domain/...`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/sqlc.yaml backend/internal/storage backend/internal/domain
git commit -m "feat(storage): claude_accounts table and session account ownership" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 3: `claudesetup` — shared setup links and MCP sync

**Files:**
- Create: `backend/internal/adapters/agent/claudecode/claudesetup/setup.go`
- Create: `backend/internal/adapters/agent/claudecode/claudesetup/mcp.go`
- Create: `backend/internal/adapters/agent/claudecode/claudesetup/setup_test.go`
- Create: `backend/internal/adapters/agent/claudecode/claudesetup/mcp_test.go`

**Interfaces:**
- Produces (package `claudesetup`):
  - `type ItemState string` with `ItemLinked = "linked"`, `ItemReplaced = "replaced"`, `ItemMissing = "missing"`, `ItemSkipped = "skipped"`
  - `var SharedItems = []string{"CLAUDE.md", "settings.json", "skills", "commands", "agents", "plugins"}`
  - `type Report map[string]ItemState`
  - `func (r Report) Replaced() []string`
  - `func Ensure(defaultDir, accountDir string) (Report, error)` — creates or repairs links; never touches real files
  - `func Inspect(defaultDir, accountDir string) (Report, error)` — read-only; reports `missing` where `Ensure` would create
  - `func Relink(defaultDir, accountDir string, now time.Time) (Report, error)` — moves real files to `<name>.bak-<unix>`, then `Ensure`
  - `func LockPath(path string) func()` — per-path mutex; the returned func unlocks
  - `func SyncMCP(defaultConfigPath, accountConfigPath string) error` — copies only `mcpServers`

- [ ] **Step 1: Write the failing tests**

`setup_test.go`:

```go
package claudesetup

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func mkdirs(t *testing.T) (string, string) {
	t.Helper()
	root := t.TempDir()
	def := filepath.Join(root, ".claude")
	acct := filepath.Join(root, ".claude-personal")
	for _, dir := range []string{def, acct, filepath.Join(def, "skills"), filepath.Join(def, "plugins")} {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			t.Fatal(err)
		}
	}
	for _, f := range []string{"CLAUDE.md", "settings.json"} {
		if err := os.WriteFile(filepath.Join(def, f), []byte("{}"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return def, acct
}

func TestEnsureStates(t *testing.T) {
	def, acct := mkdirs(t)
	if err := os.WriteFile(filepath.Join(acct, "settings.json"), []byte(`{"theme":"dark"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(t.TempDir(), "elsewhere"), filepath.Join(acct, "plugins")); err != nil {
		t.Fatal(err)
	}

	report, err := Ensure(def, acct)
	if err != nil {
		t.Fatal(err)
	}
	want := Report{
		"CLAUDE.md":     ItemLinked,
		"settings.json": ItemReplaced,
		"skills":        ItemLinked,
		"commands":      ItemSkipped,
		"agents":        ItemSkipped,
		"plugins":       ItemLinked,
	}
	for name, state := range want {
		if report[name] != state {
			t.Errorf("%s = %q, want %q", name, report[name], state)
		}
	}
	for _, name := range []string{"CLAUDE.md", "skills", "plugins"} {
		target, err := os.Readlink(filepath.Join(acct, name))
		if err != nil || target != filepath.Join(def, name) {
			t.Errorf("%s link = %q err=%v", name, target, err)
		}
	}
	data, _ := os.ReadFile(filepath.Join(acct, "settings.json"))
	if string(data) != `{"theme":"dark"}` {
		t.Errorf("real settings.json was modified: %s", data)
	}

	again, err := Ensure(def, acct)
	if err != nil || again["CLAUDE.md"] != ItemLinked {
		t.Fatalf("second ensure = %v err=%v", again, err)
	}
}

func TestInspectDoesNotCreate(t *testing.T) {
	def, acct := mkdirs(t)
	report, err := Inspect(def, acct)
	if err != nil {
		t.Fatal(err)
	}
	if report["CLAUDE.md"] != ItemMissing {
		t.Fatalf("CLAUDE.md = %q, want missing", report["CLAUDE.md"])
	}
	if _, err := os.Lstat(filepath.Join(acct, "CLAUDE.md")); !os.IsNotExist(err) {
		t.Fatalf("inspect created a link: %v", err)
	}
}

func TestRelinkBacksUpRealFiles(t *testing.T) {
	def, acct := mkdirs(t)
	real := filepath.Join(acct, "settings.json")
	if err := os.WriteFile(real, []byte(`{"theme":"dark"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1789400000, 0)
	report, err := Relink(def, acct, now)
	if err != nil {
		t.Fatal(err)
	}
	if report["settings.json"] != ItemLinked {
		t.Fatalf("settings.json = %q", report["settings.json"])
	}
	backup, err := os.ReadFile(real + ".bak-1789400000")
	if err != nil || string(backup) != `{"theme":"dark"}` {
		t.Fatalf("backup = %s err=%v", backup, err)
	}
	if replaced := report.Replaced(); len(replaced) != 0 {
		t.Fatalf("replaced after relink = %v", replaced)
	}
}
```

`mcp_test.go`:

```go
package claudesetup

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func readObject(t *testing.T, path string) map[string]any {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]any{}
	if err := json.Unmarshal(data, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestSyncMCPReplacesOnlyServers(t *testing.T) {
	dir := t.TempDir()
	def := filepath.Join(dir, "default.json")
	acct := filepath.Join(dir, "account.json")
	if err := os.WriteFile(def, []byte(`{"mcpServers":{"pencil":{"command":"pencil"}},"oauthAccount":{"accountUuid":"work"}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(acct, []byte(`{"mcpServers":{"old":{}},"oauthAccount":{"accountUuid":"personal"},"userID":"u-2"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := SyncMCP(def, acct); err != nil {
		t.Fatal(err)
	}
	got := readObject(t, acct)
	servers := got["mcpServers"].(map[string]any)
	if _, ok := servers["pencil"]; !ok || len(servers) != 1 {
		t.Fatalf("mcpServers = %v", servers)
	}
	if got["oauthAccount"].(map[string]any)["accountUuid"] != "personal" || got["userID"] != "u-2" {
		t.Fatalf("login fields changed: %v", got)
	}
}

func TestSyncMCPCreatesMissingAccountConfig(t *testing.T) {
	dir := t.TempDir()
	def := filepath.Join(dir, "default.json")
	acct := filepath.Join(dir, "account.json")
	if err := os.WriteFile(def, []byte(`{"mcpServers":{"pencil":{}}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := SyncMCP(def, acct); err != nil {
		t.Fatal(err)
	}
	if _, ok := readObject(t, acct)["mcpServers"].(map[string]any)["pencil"]; !ok {
		t.Fatal("pencil not copied")
	}
}

func TestSyncMCPNoServersNoWrite(t *testing.T) {
	dir := t.TempDir()
	def := filepath.Join(dir, "default.json")
	acct := filepath.Join(dir, "account.json")
	if err := os.WriteFile(def, []byte(`{}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := SyncMCP(def, acct); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(acct); !os.IsNotExist(err) {
		t.Fatalf("account config written without servers: %v", err)
	}
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && go test ./internal/adapters/agent/claudecode/claudesetup/`
Expected: FAIL (`undefined: Ensure`).

- [ ] **Step 3: Implement**

`setup.go`:

```go
package claudesetup

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"
)

type ItemState string

const (
	ItemLinked   ItemState = "linked"
	ItemReplaced ItemState = "replaced"
	ItemMissing  ItemState = "missing"
	ItemSkipped  ItemState = "skipped"
)

var SharedItems = []string{"CLAUDE.md", "settings.json", "skills", "commands", "agents", "plugins"}

type Report map[string]ItemState

func (r Report) Replaced() []string {
	out := make([]string, 0)
	for name, state := range r {
		if state == ItemReplaced {
			out = append(out, name)
		}
	}
	sort.Strings(out)
	return out
}

func Ensure(defaultDir, accountDir string) (Report, error) {
	return walk(defaultDir, accountDir, true)
}

func Inspect(defaultDir, accountDir string) (Report, error) {
	return walk(defaultDir, accountDir, false)
}

func Relink(defaultDir, accountDir string, now time.Time) (Report, error) {
	for _, name := range SharedItems {
		source := filepath.Join(defaultDir, name)
		target := filepath.Join(accountDir, name)
		if _, err := os.Stat(source); errors.Is(err, os.ErrNotExist) {
			continue
		} else if err != nil {
			return nil, fmt.Errorf("claudesetup: %s: %w", name, err)
		}
		info, err := os.Lstat(target)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, fmt.Errorf("claudesetup: %s: %w", name, err)
		}
		if info.Mode()&os.ModeSymlink != 0 {
			continue
		}
		backup := fmt.Sprintf("%s.bak-%d", target, now.Unix())
		if err := os.Rename(target, backup); err != nil {
			return nil, fmt.Errorf("claudesetup: back up %s: %w", name, err)
		}
	}
	return Ensure(defaultDir, accountDir)
}

func walk(defaultDir, accountDir string, repair bool) (Report, error) {
	report := make(Report, len(SharedItems))
	for _, name := range SharedItems {
		state, err := item(filepath.Join(defaultDir, name), filepath.Join(accountDir, name), repair)
		if err != nil {
			return report, fmt.Errorf("claudesetup: %s: %w", name, err)
		}
		report[name] = state
	}
	return report, nil
}

func item(source, target string, repair bool) (ItemState, error) {
	if _, err := os.Stat(source); errors.Is(err, os.ErrNotExist) {
		return ItemSkipped, nil
	} else if err != nil {
		return "", err
	}
	info, err := os.Lstat(target)
	switch {
	case errors.Is(err, os.ErrNotExist):
		if !repair {
			return ItemMissing, nil
		}
		return ItemLinked, os.Symlink(source, target)
	case err != nil:
		return "", err
	case info.Mode()&os.ModeSymlink == 0:
		return ItemReplaced, nil
	}
	current, err := os.Readlink(target)
	if err != nil {
		return "", err
	}
	if current == source {
		return ItemLinked, nil
	}
	if !repair {
		return ItemMissing, nil
	}
	if err := os.Remove(target); err != nil {
		return "", err
	}
	return ItemLinked, os.Symlink(source, target)
}
```

`mcp.go`:

```go
package claudesetup

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sync"
)

var pathLocks sync.Map

func LockPath(path string) func() {
	value, _ := pathLocks.LoadOrStore(filepath.Clean(path), &sync.Mutex{})
	mu := value.(*sync.Mutex)
	mu.Lock()
	return mu.Unlock
}

func SyncMCP(defaultConfigPath, accountConfigPath string) error {
	source, err := readObject(defaultConfigPath)
	if err != nil {
		return err
	}
	servers, hasServers := source["mcpServers"]
	unlock := LockPath(accountConfigPath)
	defer unlock()
	target, err := readObject(accountConfigPath)
	if err != nil {
		return err
	}
	current, hadServers := target["mcpServers"]
	switch {
	case !hasServers && !hadServers:
		return nil
	case !hasServers:
		delete(target, "mcpServers")
	case hadServers && reflect.DeepEqual(current, servers):
		return nil
	default:
		target["mcpServers"] = servers
	}
	return writeObjectAtomic(accountConfigPath, target)
}

func readObject(path string) (map[string]any, error) {
	out := map[string]any{}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return out, nil
	}
	if err != nil {
		return nil, fmt.Errorf("claudesetup: read %s: %w", path, err)
	}
	if len(data) == 0 {
		return out, nil
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("claudesetup: parse %s: %w", path, err)
	}
	return out, nil
}

func writeObjectAtomic(path string, value map[string]any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return fmt.Errorf("claudesetup: encode %s: %w", path, err)
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".claude.json.tmp-*")
	if err != nil {
		return fmt.Errorf("claudesetup: temp for %s: %w", path, err)
	}
	name := tmp.Name()
	defer func() { _ = os.Remove(name) }()
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("claudesetup: write %s: %w", path, err)
	}
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("claudesetup: chmod %s: %w", path, err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("claudesetup: close %s: %w", path, err)
	}
	return os.Rename(name, path)
}
```

- [ ] **Step 4: Run tests**

Run: `cd backend && go test ./internal/adapters/agent/claudecode/claudesetup/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/adapters/agent/claudecode/claudesetup
git commit -m "feat(claudecode): shared setup links and one-way MCP sync for accounts" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Claude adapter reads the account folder from the launch env

**Files:**
- Modify: `backend/internal/ports/agent.go:373-398` (`LaunchConfig`)
- Modify: `backend/internal/ports/outbound.go:104` (new `MultiConfigSessionIDClaimChecker` beside `SessionIDClaimChecker`)
- Modify: `backend/internal/adapters/agent/claudecode/claudecode.go` (`PreLaunch:229-241`, `claudeLocalAuthStatus:354-366`, `claudeConfigPath:519-527`, `claudeTrustMu`/`ensureWorkspaceTrusted:537-606`)
- Modify: `backend/internal/adapters/agent/claudecode/claim.go`
- Modify: `backend/internal/session_manager/manager.go:3289` (`prepareWorkspace` passes env)
- Test: `backend/internal/adapters/agent/claudecode/claudecode_test.go`, `claim_test.go`

**Interfaces:**
- Consumes: `claudesetup.LockPath` (Task 3), `domain.ClaudeConfigDirEnv` (Task 1).
- Produces:
  - `ports.LaunchConfig.Env map[string]string`
  - `claudecode.claudeGlobalConfigPath(env map[string]string) (string, error)`
  - `ports.MultiConfigSessionIDClaimChecker{ IsSessionIDClaimedIn(ctx, sessionID domain.SessionID, configDirs []string) (bool, error) }`
  - `(*claudecode.Plugin).IsSessionIDClaimedIn`

- [ ] **Step 1: Write failing tests**

Append to `claudecode_test.go`:

```go
func TestClaudeGlobalConfigPathFollowsEnv(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	got, err := claudeGlobalConfigPath(map[string]string{})
	if err != nil || got != filepath.Join(home, ".claude.json") {
		t.Fatalf("default = %q err=%v", got, err)
	}
	got, err = claudeGlobalConfigPath(map[string]string{claudeConfigDirEnv: "/Users/u/.claude-personal"})
	if err != nil || got != "/Users/u/.claude-personal/.claude.json" {
		t.Fatalf("account = %q err=%v", got, err)
	}
}

func TestPreLaunchTrustsWorkspaceInAccountConfig(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	account := filepath.Join(t.TempDir(), ".claude-personal")
	if err := os.MkdirAll(account, 0o700); err != nil {
		t.Fatal(err)
	}
	workspace := t.TempDir()
	err := New().PreLaunch(context.Background(), ports.LaunchConfig{
		WorkspacePath: workspace,
		Env:           map[string]string{claudeConfigDirEnv: account},
	})
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(account, ".claude.json"))
	if err != nil {
		t.Fatalf("account config not written: %v", err)
	}
	if !strings.Contains(string(data), workspace) {
		t.Fatalf("workspace trust missing from account config: %s", data)
	}
	if _, err := os.Stat(filepath.Join(home, ".claude.json")); !os.IsNotExist(err) {
		t.Fatalf("default ~/.claude.json was touched: %v", err)
	}
}
```

Add the `strings`/`context` imports if the file lacks them.

Append to `claim_test.go`, or create it with `package claudecode` if absent:

```go
func TestIsSessionIDClaimedInSearchesEveryFolder(t *testing.T) {
	first := t.TempDir()
	second := t.TempDir()
	project := filepath.Join(second, "projects", "-Users-u-repo")
	if err := os.MkdirAll(project, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(project, SessionUUID("proj-7")+".jsonl"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	claimed, err := New().IsSessionIDClaimedIn(context.Background(), "proj-7", []string{first, second})
	if err != nil || !claimed {
		t.Fatalf("claimed = %v err=%v", claimed, err)
	}
	claimed, err = New().IsSessionIDClaimedIn(context.Background(), "proj-8", []string{first, second})
	if err != nil || claimed {
		t.Fatalf("unclaimed id reported claimed=%v err=%v", claimed, err)
	}
}
```

Run: `cd backend && go test ./internal/adapters/agent/claudecode/ -run 'GlobalConfigPath|PreLaunchTrusts|ClaimedIn'`
Expected: FAIL (compile: `undefined: claudeGlobalConfigPath`, `LaunchConfig has no field Env`).

- [ ] **Step 2: Implement**

**`ports/agent.go`:** add to `LaunchConfig` after `DataDir`:

```go
	Env         map[string]string
```

**`ports/outbound.go`:** add after `SessionIDClaimChecker`:

```go
type MultiConfigSessionIDClaimChecker interface {
	IsSessionIDClaimedIn(ctx context.Context, sessionID domain.SessionID, configDirs []string) (bool, error)
}
```

**`claudecode.go`:**
- Delete `claudeConfigPath` (`:519-527`) and `var claudeTrustMu sync.Mutex`.
- Add:

```go
func claudeGlobalConfigPath(env map[string]string) (string, error) {
	if dir := strings.TrimSpace(env[claudeConfigDirEnv]); dir != "" {
		return filepath.Join(dir, ".claude.json"), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("claude-code: resolve home directory: %w", err)
	}
	return filepath.Join(home, ".claude.json"), nil
}
```

- In `PreLaunch`, replace `claudeConfigPath()` with `claudeGlobalConfigPath(cfg.Env)`.
- In `claudeLocalAuthStatus`, replace `claudeConfigPath()` with `claudeGlobalConfigPath(nil)`.
- In `ensureWorkspaceTrusted`, replace the two `claudeTrustMu` lines with:

```go
	unlock := claudesetup.LockPath(configPath)
	defer unlock()
```

- Import `github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode/claudesetup`, and drop `sync` if now unused.

**`claim.go`:** replace the body with:

```go
var (
	_ ports.SessionIDClaimChecker            = (*Plugin)(nil)
	_ ports.MultiConfigSessionIDClaimChecker = (*Plugin)(nil)
)

func (p *Plugin) IsSessionIDClaimed(ctx context.Context, sessionID domain.SessionID) (bool, error) {
	configDir, err := p.NativeSessionConfigDir(ctx, map[string]string{})
	if err != nil {
		return false, err
	}
	return p.IsSessionIDClaimedIn(ctx, sessionID, []string{configDir})
}

func (p *Plugin) IsSessionIDClaimedIn(ctx context.Context, sessionID domain.SessionID, configDirs []string) (bool, error) {
	id := strings.TrimSpace(string(sessionID))
	if id == "" {
		return false, nil
	}
	nativeID := claudeSessionUUID(id)
	for _, dir := range configDirs {
		_, found, err := p.LocateTranscript(ctx, ports.NativeSessionRef{NativeSessionID: nativeID, ConfigDir: dir})
		if err != nil {
			return false, err
		}
		if found {
			return true, nil
		}
	}
	return false, nil
}
```

**`manager.go:3289`:** change the `PreLaunch` call's `LaunchConfig` literal to include `Env: env`.

- [ ] **Step 3: Run tests**

Run: `cd backend && go build ./... && go test ./internal/adapters/agent/claudecode/... ./internal/session_manager/...`
Expected: PASS. Fix any existing test that referenced `claudeConfigPath` so it calls `claudeGlobalConfigPath(nil)` with `t.Setenv("HOME", ...)`.

- [ ] **Step 4: Commit**

```bash
git add backend/internal/ports backend/internal/adapters/agent/claudecode backend/internal/session_manager/manager.go
git commit -m "feat(claudecode): resolve Claude config from the launch env, claim across account folders" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 5: `claudeaccounts` service

**Files:**
- Create: `backend/internal/service/claudeaccounts/service.go`
- Create: `backend/internal/service/claudeaccounts/status.go`
- Create: `backend/internal/service/claudeaccounts/service_test.go`
- Create: `backend/internal/service/claudeaccounts/status_test.go`

**Interfaces:**
- Consumes:
  - store methods from Task 2 (through the `Store` interface below)
  - `claudesetup.Ensure/Inspect/Relink/SyncMCP` (Task 3)
  - `claudecode.ResolveClaudeBinary(ctx)` (existing, `claudecode.go:499`)
- Produces (package `claudeaccounts`):
  - `type Store interface{ ListClaudeAccounts; GetClaudeAccount; InsertClaudeAccount; RenameClaudeAccount; DeleteClaudeAccount }` (Task 2 signatures)
  - `type AuthStatus struct{ LoggedIn *bool; SubscriptionType, ReportedEmail string; CheckedAt time.Time }`
  - `type AuthProber interface{ Probe(ctx context.Context, env map[string]string) (AuthStatus, error) }`
  - `type AccountView struct{ Account domain.ClaudeAccount; ConfigDir string; Status AuthStatus; SharedSetup claudesetup.Report }`
  - `type LoginLaunch struct{ Account domain.ClaudeAccount; Argv []string; Env map[string]string; Title string }`
  - `type Deps struct{ Store Store; Prober AuthProber; Home string; Now func() time.Time; ResolveBinary func(context.Context) (string, error) }`
  - `func New(d Deps) *Service`
  - `func Slug(label string) string`
  - methods on `*Service`:
    - `List(ctx, refresh bool) ([]AccountView, error)`
    - `Create(ctx, label string) (domain.ClaudeAccount, error)`
    - `Rename(ctx, id domain.ClaudeAccountID, label string) (domain.ClaudeAccount, error)`
    - `Delete(ctx, id) error`
    - `Relink(ctx, id) (claudesetup.Report, error)`
    - `PrepareLaunch(ctx, id) (domain.ClaudeAccount, error)`
    - `Login(ctx, id) (LoginLaunch, error)`
    - `EnvFor(ctx, id) (map[string]string, error)`
    - `ConfigDirFor(ctx, id) (string, error)`
    - `ConfigDirs(ctx) ([]string, error)`
    - `OnAccountAdded(fn func(configDir string))`
  - `func NewCommandProber(timeout time.Duration) AuthProber`

- [ ] **Step 1: Write the failing service tests**

`service_test.go`:

```go
package claudeaccounts

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type memStore struct {
	mu       sync.Mutex
	accounts map[domain.ClaudeAccountID]domain.ClaudeAccount
	inUse    map[domain.ClaudeAccountID]bool
}

func newMemStore() *memStore {
	return &memStore{
		accounts: map[domain.ClaudeAccountID]domain.ClaudeAccount{
			domain.DefaultClaudeAccountID: {ID: domain.DefaultClaudeAccountID, Label: "Default", IsDefault: true},
		},
		inUse: map[domain.ClaudeAccountID]bool{},
	}
}

func (m *memStore) ListClaudeAccounts(context.Context) ([]domain.ClaudeAccount, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]domain.ClaudeAccount, 0, len(m.accounts))
	for _, a := range m.accounts {
		out = append(out, a)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].IsDefault != out[j].IsDefault {
			return out[i].IsDefault
		}
		return out[i].ID < out[j].ID
	})
	return out, nil
}

func (m *memStore) GetClaudeAccount(_ context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	a, ok := m.accounts[id]
	if !ok {
		return domain.ClaudeAccount{}, domain.ErrClaudeAccountNotFound
	}
	return a, nil
}

func (m *memStore) InsertClaudeAccount(_ context.Context, a domain.ClaudeAccount) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.accounts[a.ID] = a
	return nil
}

func (m *memStore) RenameClaudeAccount(_ context.Context, id domain.ClaudeAccountID, label string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	a, ok := m.accounts[id]
	if !ok {
		return domain.ErrClaudeAccountNotFound
	}
	a.Label = label
	m.accounts[id] = a
	return nil
}

func (m *memStore) DeleteClaudeAccount(_ context.Context, id domain.ClaudeAccountID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	a, ok := m.accounts[id]
	switch {
	case !ok:
		return domain.ErrClaudeAccountNotFound
	case a.IsDefault:
		return domain.ErrClaudeAccountDefaultImmutable
	case m.inUse[id]:
		return domain.ErrClaudeAccountInUse
	}
	delete(m.accounts, id)
	return nil
}

type fakeProber struct {
	mu    sync.Mutex
	calls int
	envs  []map[string]string
}

func (f *fakeProber) Probe(_ context.Context, env map[string]string) (AuthStatus, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.envs = append(f.envs, env)
	yes := true
	return AuthStatus{LoggedIn: &yes, SubscriptionType: "pro"}, nil
}

func newTestService(t *testing.T) (*Service, *memStore, *fakeProber, string) {
	t.Helper()
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, ".claude", "skills"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, ".claude", "CLAUDE.md"), []byte("rules"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, ".claude.json"), []byte(`{"mcpServers":{"pencil":{}}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	store := newMemStore()
	prober := &fakeProber{}
	svc := New(Deps{
		Store:  store,
		Prober: prober,
		Home:   home,
		Now:    func() time.Time { return time.Unix(1789400000, 0).UTC() },
		ResolveBinary: func(context.Context) (string, error) {
			return "/usr/local/bin/claude", nil
		},
	})
	return svc, store, prober, home
}

func TestSlug(t *testing.T) {
	cases := map[string]string{
		"Personal":        "personal",
		"  Work Account ": "work-account",
		"Omar's #2":       "omar-s-2",
		"---":             "",
	}
	for in, want := range cases {
		if got := Slug(in); got != want {
			t.Errorf("Slug(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestCreateMakesFolderLinksAndNotifies(t *testing.T) {
	svc, _, _, home := newTestService(t)
	var added []string
	svc.OnAccountAdded(func(dir string) { added = append(added, dir) })

	account, err := svc.Create(context.Background(), " Personal ")
	if err != nil {
		t.Fatal(err)
	}
	wantDir := filepath.Join(home, ".claude-personal")
	if account.ID != "personal" || account.Label != "Personal" || account.ConfigDir != wantDir {
		t.Fatalf("account = %+v", account)
	}
	info, err := os.Stat(wantDir)
	if err != nil || !info.IsDir() || info.Mode().Perm() != 0o700 {
		t.Fatalf("folder info = %v err=%v", info, err)
	}
	if target, err := os.Readlink(filepath.Join(wantDir, "CLAUDE.md")); err != nil || target != filepath.Join(home, ".claude", "CLAUDE.md") {
		t.Fatalf("CLAUDE.md link = %q err=%v", target, err)
	}
	if len(added) != 1 || added[0] != wantDir {
		t.Fatalf("added = %v", added)
	}
}

func TestCreateAdoptsExistingFolder(t *testing.T) {
	svc, _, _, home := newTestService(t)
	dir := filepath.Join(home, ".claude-personal")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".claude.json"), []byte(`{"userID":"keep"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Create(context.Background(), "Personal"); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(filepath.Join(dir, ".claude.json"))
	if string(data) != `{"userID":"keep"}` {
		t.Fatalf("existing config changed: %s", data)
	}
}

func TestCreateRejectsInvalidAndDuplicate(t *testing.T) {
	svc, _, _, home := newTestService(t)
	ctx := context.Background()
	for _, label := range []string{"", "   ", "---", "this label is far longer than thirty-two runes"} {
		if _, err := svc.Create(ctx, label); !errors.Is(err, domain.ErrClaudeAccountLabelInvalid) {
			t.Errorf("Create(%q) err = %v", label, err)
		}
	}
	if _, err := svc.Create(ctx, "Default"); !errors.Is(err, domain.ErrClaudeAccountExists) {
		t.Errorf("Default err = %v", err)
	}
	if _, err := svc.Create(ctx, "Personal"); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Create(ctx, "personal"); !errors.Is(err, domain.ErrClaudeAccountExists) {
		t.Errorf("duplicate err = %v", err)
	}
	if err := os.WriteFile(filepath.Join(home, ".claude-file"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Create(ctx, "File"); !errors.Is(err, domain.ErrClaudeAccountFolderUnavailable) {
		t.Errorf("file path err = %v", err)
	}
}

func TestRenameKeepsFolder(t *testing.T) {
	svc, _, _, _ := newTestService(t)
	ctx := context.Background()
	created, err := svc.Create(ctx, "Personal")
	if err != nil {
		t.Fatal(err)
	}
	renamed, err := svc.Rename(ctx, "personal", "Home")
	if err != nil {
		t.Fatal(err)
	}
	if renamed.Label != "Home" || renamed.ConfigDir != created.ConfigDir || renamed.ID != "personal" {
		t.Fatalf("renamed = %+v", renamed)
	}
}

func TestPrepareLaunch(t *testing.T) {
	svc, _, _, home := newTestService(t)
	ctx := context.Background()
	def, err := svc.PrepareLaunch(ctx, "")
	if err != nil || !def.IsDefault {
		t.Fatalf("default = %+v err=%v", def, err)
	}
	created, err := svc.Create(ctx, "Personal")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(created.ConfigDir, "CLAUDE.md")); err != nil {
		t.Fatal(err)
	}
	got, err := svc.PrepareLaunch(ctx, "personal")
	if err != nil || got.ConfigDir != created.ConfigDir {
		t.Fatalf("prepare = %+v err=%v", got, err)
	}
	if _, err := os.Readlink(filepath.Join(created.ConfigDir, "CLAUDE.md")); err != nil {
		t.Fatalf("link not repaired: %v", err)
	}
	data, err := os.ReadFile(filepath.Join(created.ConfigDir, ".claude.json"))
	if err != nil || string(data) == "" {
		t.Fatalf("mcp not synced: %s err=%v", data, err)
	}
	if err := os.RemoveAll(created.ConfigDir); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.PrepareLaunch(ctx, "personal"); !errors.Is(err, domain.ErrClaudeAccountFolderUnavailable) {
		t.Fatalf("missing folder err = %v", err)
	}
	if _, err := svc.PrepareLaunch(ctx, "missing"); !errors.Is(err, domain.ErrClaudeAccountNotFound) {
		t.Fatalf("unknown err = %v", err)
	}
	_ = home
}

func TestEnvForAndConfigDirs(t *testing.T) {
	svc, _, _, home := newTestService(t)
	ctx := context.Background()
	if _, err := svc.Create(ctx, "Personal"); err != nil {
		t.Fatal(err)
	}
	env, err := svc.EnvFor(ctx, domain.DefaultClaudeAccountID)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := env[domain.ClaudeConfigDirEnv]; ok {
		t.Fatalf("default env = %v", env)
	}
	env, err = svc.EnvFor(ctx, "personal")
	if err != nil || env[domain.ClaudeConfigDirEnv] != filepath.Join(home, ".claude-personal") {
		t.Fatalf("personal env = %v err=%v", env, err)
	}
	dirs, err := svc.ConfigDirs(ctx)
	want := []string{filepath.Join(home, ".claude"), filepath.Join(home, ".claude-personal")}
	if err != nil || len(dirs) != 2 || dirs[0] != want[0] || dirs[1] != want[1] {
		t.Fatalf("dirs = %v err=%v", dirs, err)
	}
}

func TestListCachesStatusAndRefreshBypasses(t *testing.T) {
	svc, _, prober, _ := newTestService(t)
	ctx := context.Background()
	if _, err := svc.Create(ctx, "Personal"); err != nil {
		t.Fatal(err)
	}
	views, err := svc.List(ctx, false)
	if err != nil || len(views) != 2 || prober.calls != 2 {
		t.Fatalf("views=%d calls=%d err=%v", len(views), prober.calls, err)
	}
	if views[0].ConfigDir == "" || views[1].SharedSetup["CLAUDE.md"] != "linked" {
		t.Fatalf("views = %+v", views)
	}
	if _, err := svc.List(ctx, false); err != nil || prober.calls != 2 {
		t.Fatalf("cached list probed again: calls=%d", prober.calls)
	}
	if _, err := svc.List(ctx, true); err != nil || prober.calls != 4 {
		t.Fatalf("refresh did not probe: calls=%d", prober.calls)
	}
}

func TestLoginBuildsLaunch(t *testing.T) {
	svc, _, _, home := newTestService(t)
	ctx := context.Background()
	if _, err := svc.Create(ctx, "Personal"); err != nil {
		t.Fatal(err)
	}
	launch, err := svc.Login(ctx, "personal")
	if err != nil {
		t.Fatal(err)
	}
	if len(launch.Argv) != 1 || launch.Argv[0] != "/usr/local/bin/claude" {
		t.Fatalf("argv = %v", launch.Argv)
	}
	if launch.Env[domain.ClaudeConfigDirEnv] != filepath.Join(home, ".claude-personal") || launch.Title != "Claude login · Personal" {
		t.Fatalf("launch = %+v", launch)
	}
}

func TestDeletePassesStoreErrors(t *testing.T) {
	svc, store, _, _ := newTestService(t)
	ctx := context.Background()
	if _, err := svc.Create(ctx, "Personal"); err != nil {
		t.Fatal(err)
	}
	store.inUse["personal"] = true
	if err := svc.Delete(ctx, "personal"); !errors.Is(err, domain.ErrClaudeAccountInUse) {
		t.Fatalf("err = %v", err)
	}
}
```

`status_test.go`:

```go
package claudeaccounts

import "testing"

func TestParseAuthStatus(t *testing.T) {
	out := []byte("warning: x\n{\"loggedIn\":true,\"subscriptionType\":\"max\",\"email\":\"a@b.c\"}\n")
	status, ok := parseAuthStatus(out)
	if !ok || status.LoggedIn == nil || !*status.LoggedIn || status.SubscriptionType != "max" || status.ReportedEmail != "a@b.c" {
		t.Fatalf("status = %+v ok=%v", status, ok)
	}
	status, ok = parseAuthStatus([]byte(`{"loggedIn":false,"authMethod":"none"}`))
	if !ok || status.LoggedIn == nil || *status.LoggedIn {
		t.Fatalf("logged out = %+v ok=%v", status, ok)
	}
	if _, ok := parseAuthStatus([]byte("garbage")); ok {
		t.Fatal("garbage parsed")
	}
}

func TestProcessEnvDropsInheritedConfigDir(t *testing.T) {
	base := []string{"PATH=/bin", "CLAUDE_CONFIG_DIR=/inherited", "HOME=/h"}
	got := processEnv(base, map[string]string{})
	for _, kv := range got {
		if kv == "CLAUDE_CONFIG_DIR=/inherited" {
			t.Fatalf("inherited value kept: %v", got)
		}
	}
	got = processEnv(base, map[string]string{"CLAUDE_CONFIG_DIR": "/acct"})
	found := false
	for _, kv := range got {
		if kv == "CLAUDE_CONFIG_DIR=/acct" {
			found = true
		}
	}
	if !found {
		t.Fatalf("account value missing: %v", got)
	}
}
```

Run: `cd backend && go test ./internal/service/claudeaccounts/`
Expected: FAIL (`undefined: New`).

- [ ] **Step 2: Implement `status.go`**

```go
package claudeaccounts

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"strings"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/domain"
	aoprocess "github.com/OmarAly92/operator/backend/internal/process"
)

type AuthStatus struct {
	LoggedIn         *bool
	SubscriptionType string
	ReportedEmail    string
	CheckedAt        time.Time
}

type AuthProber interface {
	Probe(ctx context.Context, env map[string]string) (AuthStatus, error)
}

type commandProber struct {
	timeout time.Duration
}

func NewCommandProber(timeout time.Duration) AuthProber {
	return commandProber{timeout: timeout}
}

func (p commandProber) Probe(ctx context.Context, env map[string]string) (AuthStatus, error) {
	binary, err := claudecode.ResolveClaudeBinary(ctx)
	if err != nil {
		return AuthStatus{}, err
	}
	probeCtx, cancel := context.WithTimeout(ctx, p.timeout)
	defer cancel()
	cmd := aoprocess.CommandContext(probeCtx, binary, "auth", "status")
	cmd.Env = processEnv(os.Environ(), env)
	out, _ := cmd.CombinedOutput()
	if probeCtx.Err() != nil {
		return AuthStatus{}, probeCtx.Err()
	}
	status, _ := parseAuthStatus(out)
	return status, nil
}

func processEnv(base []string, env map[string]string) []string {
	out := make([]string, 0, len(base)+len(env))
	for _, kv := range base {
		if strings.HasPrefix(kv, domain.ClaudeConfigDirEnv+"=") {
			continue
		}
		out = append(out, kv)
	}
	for key, value := range env {
		out = append(out, key+"="+value)
	}
	return out
}

func parseAuthStatus(out []byte) (AuthStatus, bool) {
	start := bytes.IndexByte(out, '{')
	end := bytes.LastIndexByte(out, '}')
	if start < 0 || end < start {
		return AuthStatus{}, false
	}
	var raw struct {
		LoggedIn         *bool  `json:"loggedIn"`
		SubscriptionType string `json:"subscriptionType"`
		Email            string `json:"email"`
	}
	if json.Unmarshal(out[start:end+1], &raw) != nil || raw.LoggedIn == nil {
		return AuthStatus{}, false
	}
	return AuthStatus{LoggedIn: raw.LoggedIn, SubscriptionType: raw.SubscriptionType, ReportedEmail: raw.Email}, true
}
```

**Before writing:** check that `aoprocess.CommandContext` returns `*exec.Cmd` (see `claudecode.go:322`). If it returns a wrapper, set the env the way that wrapper exposes it.

- [ ] **Step 3: Implement `service.go`**

```go
package claudeaccounts

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode/claudesetup"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

const (
	maxLabelRunes = 32
	statusTTL     = 30 * time.Second
)

var slugInvalid = regexp.MustCompile(`[^a-z0-9]+`)

type Store interface {
	ListClaudeAccounts(ctx context.Context) ([]domain.ClaudeAccount, error)
	GetClaudeAccount(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error)
	InsertClaudeAccount(ctx context.Context, account domain.ClaudeAccount) error
	RenameClaudeAccount(ctx context.Context, id domain.ClaudeAccountID, label string) error
	DeleteClaudeAccount(ctx context.Context, id domain.ClaudeAccountID) error
}

type AccountView struct {
	Account     domain.ClaudeAccount
	ConfigDir   string
	Status      AuthStatus
	SharedSetup claudesetup.Report
}

type LoginLaunch struct {
	Account domain.ClaudeAccount
	Argv    []string
	Env     map[string]string
	Title   string
}

type Deps struct {
	Store         Store
	Prober        AuthProber
	Home          string
	Now           func() time.Time
	ResolveBinary func(context.Context) (string, error)
}

type Service struct {
	store         Store
	prober        AuthProber
	home          string
	now           func() time.Time
	resolveBinary func(context.Context) (string, error)

	createMu sync.Mutex
	mu       sync.Mutex
	cache    map[domain.ClaudeAccountID]AuthStatus
	added    []func(string)
}

func New(d Deps) *Service {
	now := d.Now
	if now == nil {
		now = func() time.Time { return time.Now().UTC() }
	}
	resolve := d.ResolveBinary
	if resolve == nil {
		resolve = claudecode.ResolveClaudeBinary
	}
	return &Service{
		store:         d.Store,
		prober:        d.Prober,
		home:          filepath.Clean(d.Home),
		now:           now,
		resolveBinary: resolve,
		cache:         map[domain.ClaudeAccountID]AuthStatus{},
	}
}

func Slug(label string) string {
	return strings.Trim(slugInvalid.ReplaceAllString(strings.ToLower(strings.TrimSpace(label)), "-"), "-")
}

func (s *Service) OnAccountAdded(fn func(configDir string)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.added = append(s.added, fn)
}

func (s *Service) defaultDir() string {
	return filepath.Join(s.home, ".claude")
}

func (s *Service) configDir(account domain.ClaudeAccount) string {
	if account.IsDefault {
		return s.defaultDir()
	}
	return account.ConfigDir
}

func (s *Service) Create(ctx context.Context, label string) (domain.ClaudeAccount, error) {
	label = strings.TrimSpace(label)
	slug := Slug(label)
	if slug == "" || utf8.RuneCountInString(label) > maxLabelRunes {
		return domain.ClaudeAccount{}, domain.ErrClaudeAccountLabelInvalid
	}
	s.createMu.Lock()
	defer s.createMu.Unlock()
	dir := filepath.Join(s.home, ".claude-"+slug)
	existing, err := s.store.ListClaudeAccounts(ctx)
	if err != nil {
		return domain.ClaudeAccount{}, err
	}
	for _, account := range existing {
		if strings.EqualFold(account.Label, label) || account.ID == domain.ClaudeAccountID(slug) || account.ConfigDir == dir {
			return domain.ClaudeAccount{}, domain.ErrClaudeAccountExists
		}
	}
	info, err := os.Stat(dir)
	switch {
	case errors.Is(err, os.ErrNotExist):
		if err := os.Mkdir(dir, 0o700); err != nil {
			return domain.ClaudeAccount{}, fmt.Errorf("%w: %v", domain.ErrClaudeAccountFolderUnavailable, err)
		}
	case err != nil:
		return domain.ClaudeAccount{}, fmt.Errorf("%w: %v", domain.ErrClaudeAccountFolderUnavailable, err)
	case !info.IsDir():
		return domain.ClaudeAccount{}, fmt.Errorf("%w: %s is not a directory", domain.ErrClaudeAccountFolderUnavailable, dir)
	}
	if _, err := claudesetup.Ensure(s.defaultDir(), dir); err != nil {
		return domain.ClaudeAccount{}, fmt.Errorf("%w: %v", domain.ErrClaudeAccountFolderUnavailable, err)
	}
	account := domain.ClaudeAccount{ID: domain.ClaudeAccountID(slug), Label: label, ConfigDir: dir, CreatedAt: s.now()}
	if err := s.store.InsertClaudeAccount(ctx, account); err != nil {
		return domain.ClaudeAccount{}, err
	}
	s.mu.Lock()
	hooks := append([]func(string){}, s.added...)
	s.mu.Unlock()
	for _, hook := range hooks {
		hook(dir)
	}
	return account, nil
}

func (s *Service) Rename(ctx context.Context, id domain.ClaudeAccountID, label string) (domain.ClaudeAccount, error) {
	label = strings.TrimSpace(label)
	if Slug(label) == "" || utf8.RuneCountInString(label) > maxLabelRunes {
		return domain.ClaudeAccount{}, domain.ErrClaudeAccountLabelInvalid
	}
	existing, err := s.store.ListClaudeAccounts(ctx)
	if err != nil {
		return domain.ClaudeAccount{}, err
	}
	for _, account := range existing {
		if account.ID != id && strings.EqualFold(account.Label, label) {
			return domain.ClaudeAccount{}, domain.ErrClaudeAccountExists
		}
	}
	if err := s.store.RenameClaudeAccount(ctx, id, label); err != nil {
		return domain.ClaudeAccount{}, err
	}
	return s.store.GetClaudeAccount(ctx, id)
}

func (s *Service) Delete(ctx context.Context, id domain.ClaudeAccountID) error {
	if err := s.store.DeleteClaudeAccount(ctx, id); err != nil {
		return err
	}
	s.mu.Lock()
	delete(s.cache, id)
	s.mu.Unlock()
	return nil
}

func (s *Service) Relink(ctx context.Context, id domain.ClaudeAccountID) (claudesetup.Report, error) {
	account, err := s.store.GetClaudeAccount(ctx, id)
	if err != nil {
		return nil, err
	}
	if account.IsDefault {
		return claudesetup.Report{}, nil
	}
	report, err := claudesetup.Relink(s.defaultDir(), account.ConfigDir, s.now())
	if err != nil {
		return nil, fmt.Errorf("%w: %v", domain.ErrClaudeAccountFolderUnavailable, err)
	}
	return report, nil
}

func (s *Service) PrepareLaunch(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error) {
	account, err := s.store.GetClaudeAccount(ctx, domain.NormalizeClaudeAccountID(id))
	if err != nil {
		return domain.ClaudeAccount{}, err
	}
	if account.IsDefault {
		return account, nil
	}
	info, err := os.Stat(account.ConfigDir)
	if err != nil || !info.IsDir() {
		return domain.ClaudeAccount{}, fmt.Errorf("%w: %s", domain.ErrClaudeAccountFolderUnavailable, account.ConfigDir)
	}
	if _, err := claudesetup.Ensure(s.defaultDir(), account.ConfigDir); err != nil {
		return domain.ClaudeAccount{}, fmt.Errorf("%w: %v", domain.ErrClaudeAccountFolderUnavailable, err)
	}
	if err := claudesetup.SyncMCP(filepath.Join(s.home, ".claude.json"), filepath.Join(account.ConfigDir, ".claude.json")); err != nil {
		return domain.ClaudeAccount{}, fmt.Errorf("%w: sync mcp servers: %v", domain.ErrClaudeAccountFolderUnavailable, err)
	}
	return account, nil
}

func (s *Service) Login(ctx context.Context, id domain.ClaudeAccountID) (LoginLaunch, error) {
	account, err := s.PrepareLaunch(ctx, id)
	if err != nil {
		return LoginLaunch{}, err
	}
	binary, err := s.resolveBinary(ctx)
	if err != nil {
		return LoginLaunch{}, err
	}
	env := map[string]string{}
	account.ApplyEnv(env)
	s.mu.Lock()
	delete(s.cache, account.ID)
	s.mu.Unlock()
	return LoginLaunch{Account: account, Argv: []string{binary}, Env: env, Title: "Claude login · " + account.Label}, nil
}

func (s *Service) EnvFor(ctx context.Context, id domain.ClaudeAccountID) (map[string]string, error) {
	account, err := s.store.GetClaudeAccount(ctx, domain.NormalizeClaudeAccountID(id))
	if err != nil {
		return nil, err
	}
	env := map[string]string{}
	account.ApplyEnv(env)
	return env, nil
}

func (s *Service) ConfigDirFor(ctx context.Context, id domain.ClaudeAccountID) (string, error) {
	account, err := s.store.GetClaudeAccount(ctx, domain.NormalizeClaudeAccountID(id))
	if err != nil {
		return "", err
	}
	return s.configDir(account), nil
}

func (s *Service) ConfigDirs(ctx context.Context) ([]string, error) {
	accounts, err := s.store.ListClaudeAccounts(ctx)
	if err != nil {
		return nil, err
	}
	dirs := make([]string, 0, len(accounts))
	for _, account := range accounts {
		dirs = append(dirs, s.configDir(account))
	}
	return dirs, nil
}

func (s *Service) List(ctx context.Context, refresh bool) ([]AccountView, error) {
	accounts, err := s.store.ListClaudeAccounts(ctx)
	if err != nil {
		return nil, err
	}
	views := make([]AccountView, len(accounts))
	var wg sync.WaitGroup
	for i, account := range accounts {
		views[i] = AccountView{Account: account, ConfigDir: s.configDir(account), SharedSetup: claudesetup.Report{}}
		if !account.IsDefault {
			if report, err := claudesetup.Inspect(s.defaultDir(), account.ConfigDir); err == nil {
				views[i].SharedSetup = report
			}
		}
		wg.Add(1)
		go func(i int, account domain.ClaudeAccount) {
			defer wg.Done()
			views[i].Status = s.status(ctx, account, refresh)
		}(i, account)
	}
	wg.Wait()
	return views, nil
}

func (s *Service) status(ctx context.Context, account domain.ClaudeAccount, refresh bool) AuthStatus {
	s.mu.Lock()
	cached, ok := s.cache[account.ID]
	s.mu.Unlock()
	if ok && !refresh && s.now().Sub(cached.CheckedAt) < statusTTL {
		return cached
	}
	env := map[string]string{}
	account.ApplyEnv(env)
	status := AuthStatus{}
	if s.prober != nil {
		if probed, err := s.prober.Probe(ctx, env); err == nil {
			status = probed
		}
	}
	status.CheckedAt = s.now()
	s.mu.Lock()
	s.cache[account.ID] = status
	s.mu.Unlock()
	return status
}
```

In `TestListCachesStatusAndRefreshBypasses` the fixed clock means `now - CheckedAt == 0 < TTL`, so the second call is cached. A failed probe is cached for the TTL as `LoggedIn: nil` (reported as "Unknown").

- [ ] **Step 4: Run tests**

Run: `cd backend && go test -race ./internal/service/claudeaccounts/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/service/claudeaccounts
git commit -m "feat(claudeaccounts): account registry, launch preparation and status probe" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 6: Session manager launches on the session's account

**Files:**
- Create: `backend/internal/session_manager/claude_account.go`
- Create: `backend/internal/session_manager/claude_account_test.go`
- Modify: `backend/internal/ports/session.go:21-53` (`SpawnConfig`)
- Modify: `backend/internal/session_manager/manager.go`:
  - `Manager` struct `:243`
  - `Deps` `:421-449`
  - `New` `:453`
  - spawn validation before `:567`
  - `launchRuntimeEnv` call `:623`
  - restore `:1487`
  - `runtimeEnv`/`launchRuntimeEnv` `:3084-3113`
  - `cleanupAgentWorkspace` `:3331`
  - `seedRecord` `:2683`
- Modify: `backend/internal/session_manager/agent_switching.go:214`, `:742`, `:2533` (signature-only change here; Task 7 changes the account argument at `:742` and `:2533`)
- Modify: `backend/internal/service/session/service.go`:
  - `SpawnOrchestrator` `:411`, which builds `ports.SpawnConfig` at `:442`
  - `toAPIError` `:880-940`
- Modify: `backend/internal/httpd/controllers/dto.go`:
  - `SpawnSessionRequest` `:201-224`
  - `DelegateTaskRequest` `:701`
  - `SpawnOrchestratorRequest` `:997`
- Modify: `backend/internal/httpd/controllers/sessions.go`:
  - spawn `:329`
  - `delegateTask`
  - `spawnOrchestrator` `:1711`
- Modify: `backend/internal/service/session/delegation.go:26` (`DelegateTaskInput`), `:63` (`ports.SpawnConfig`)

**Interfaces:**
- Consumes: `domain.ClaudeAccount.ApplyEnv`, `domain.NormalizeClaudeAccountID`, `(*claudeaccounts.Service).PrepareLaunch` (Task 5) through the interface below.
- Produces:
  - `ports.SpawnConfig.ClaudeAccountID domain.ClaudeAccountID`
  - `sessionmanager.ClaudeAccountLauncher interface{ PrepareLaunch(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error) }`
  - `sessionmanager.Deps.ClaudeAccounts ClaudeAccountLauncher`
  - `func (m *Manager) runtimeEnv(ctx context.Context, rec domain.SessionRecord, account domain.ClaudeAccountID, projectEnv map[string]string) (map[string]string, error)`
  - `func (m *Manager) launchRuntimeEnv(ctx context.Context, rec domain.SessionRecord, account domain.ClaudeAccountID, projectEnv map[string]string) (map[string]string, string, error)`
  - `func (m *Manager) resolveSpawnClaudeAccount(ctx context.Context, cfg ports.SpawnConfig) (domain.ClaudeAccountID, error)`
  - `sessionsvc.(*Service).SpawnOrchestrator(ctx, projectID domain.ProjectID, clean bool, account domain.ClaudeAccountID)`
  - wire fields `claudeAccountId` on `POST /sessions` and `POST /orchestrators`

Taking the account as a required parameter of the one env builder is the guard: no launch site compiles without choosing an account.

- [ ] **Step 1: Write the failing manager tests**

`claude_account_test.go`:

```go
package sessionmanager

import (
	"context"
	"errors"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeClaudeAccounts struct {
	accounts map[domain.ClaudeAccountID]domain.ClaudeAccount
	prepared []domain.ClaudeAccountID
	err      error
}

func newFakeClaudeAccounts() *fakeClaudeAccounts {
	return &fakeClaudeAccounts{accounts: map[domain.ClaudeAccountID]domain.ClaudeAccount{
		domain.DefaultClaudeAccountID: {ID: domain.DefaultClaudeAccountID, IsDefault: true},
		"personal":                    {ID: "personal", ConfigDir: "/Users/u/.claude-personal"},
	}}
}

func (f *fakeClaudeAccounts) PrepareLaunch(_ context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error) {
	id = domain.NormalizeClaudeAccountID(id)
	f.prepared = append(f.prepared, id)
	if f.err != nil {
		return domain.ClaudeAccount{}, f.err
	}
	account, ok := f.accounts[id]
	if !ok {
		return domain.ClaudeAccount{}, domain.ErrClaudeAccountNotFound
	}
	return account, nil
}

type fakeSessionReader struct {
	Store
	sessions map[domain.SessionID]domain.SessionRecord
}

func (f fakeSessionReader) GetSession(_ context.Context, id domain.SessionID) (domain.SessionRecord, bool, error) {
	rec, ok := f.sessions[id]
	return rec, ok, nil
}

func TestRuntimeEnvAppliesAccount(t *testing.T) {
	m := New(Deps{ClaudeAccounts: newFakeClaudeAccounts(), Executable: func() (string, error) { return "/opt/opr/opr", nil }})
	rec := domain.SessionRecord{ID: "proj-1", ProjectID: "proj"}
	projectEnv := map[string]string{domain.ClaudeConfigDirEnv: "/project/override"}

	env, err := m.runtimeEnv(context.Background(), rec, "personal", projectEnv)
	if err != nil || env[domain.ClaudeConfigDirEnv] != "/Users/u/.claude-personal" {
		t.Fatalf("personal env = %q err=%v", env[domain.ClaudeConfigDirEnv], err)
	}

	env, err = m.runtimeEnv(context.Background(), rec, domain.DefaultClaudeAccountID, projectEnv)
	if err != nil {
		t.Fatal(err)
	}
	if value, ok := env[domain.ClaudeConfigDirEnv]; ok {
		t.Fatalf("default env kept %s=%q", domain.ClaudeConfigDirEnv, value)
	}

	if _, err := m.runtimeEnv(context.Background(), rec, "missing", nil); !errors.Is(err, domain.ErrClaudeAccountNotFound) {
		t.Fatalf("missing err = %v", err)
	}
}

func TestRuntimeEnvPropagatesFolderUnavailable(t *testing.T) {
	accounts := newFakeClaudeAccounts()
	accounts.err = domain.ErrClaudeAccountFolderUnavailable
	m := New(Deps{ClaudeAccounts: accounts, Executable: func() (string, error) { return "/opt/opr/opr", nil }})
	_, err := m.runtimeEnv(context.Background(), domain.SessionRecord{ID: "proj-1"}, "personal", nil)
	if !errors.Is(err, domain.ErrClaudeAccountFolderUnavailable) {
		t.Fatalf("err = %v", err)
	}
}

func TestResolveSpawnClaudeAccount(t *testing.T) {
	store := fakeSessionReader{sessions: map[domain.SessionID]domain.SessionRecord{
		"orch-1": {ID: "orch-1", ClaudeAccountID: "personal"},
	}}
	m := New(Deps{Store: store, ClaudeAccounts: newFakeClaudeAccounts()})
	ctx := context.Background()

	cases := []struct {
		name string
		cfg  ports.SpawnConfig
		want domain.ClaudeAccountID
		err  error
	}{
		{name: "claude default", cfg: ports.SpawnConfig{Harness: domain.HarnessClaudeCode}, want: domain.DefaultClaudeAccountID},
		{name: "claude explicit", cfg: ports.SpawnConfig{Harness: domain.HarnessClaudeCode, ClaudeAccountID: "personal"}, want: "personal"},
		{name: "claude unknown", cfg: ports.SpawnConfig{Harness: domain.HarnessClaudeCode, ClaudeAccountID: "missing"}, err: domain.ErrInvalidClaudeAccount},
		{name: "codex explicit", cfg: ports.SpawnConfig{Harness: domain.HarnessCodex, ClaudeAccountID: "personal"}, err: domain.ErrInvalidClaudeAccount},
		{name: "codex omitted", cfg: ports.SpawnConfig{Harness: domain.HarnessCodex}, want: domain.DefaultClaudeAccountID},
		{name: "worker inherits orchestrator", cfg: ports.SpawnConfig{Harness: domain.HarnessClaudeCode, RequestedBy: "orch-1"}, want: "personal"},
		{name: "explicit beats orchestrator", cfg: ports.SpawnConfig{Harness: domain.HarnessClaudeCode, RequestedBy: "orch-1", ClaudeAccountID: "default"}, want: domain.DefaultClaudeAccountID},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := m.resolveSpawnClaudeAccount(ctx, tc.cfg)
			if tc.err != nil {
				if !errors.Is(err, tc.err) {
					t.Fatalf("err = %v, want %v", err, tc.err)
				}
				return
			}
			if err != nil || got != tc.want {
				t.Fatalf("got %q err=%v, want %q", got, err, tc.want)
			}
		})
	}
}
```

**Before running:**
- If `domain.HarnessCodex` is named differently, use the constant from `domain`: `grep -n 'HarnessCodex\|= "codex"' backend/internal/domain/*.go`.
- If `Store` is not an interface named `Store` in this package (see `manager.go:217`), embed that interface's actual name in `fakeSessionReader`.

Run: `cd backend && go test ./internal/session_manager/ -run 'RuntimeEnvApplies|RuntimeEnvPropagates|ResolveSpawnClaudeAccount'`
Expected: FAIL (compile: `unknown field ClaudeAccounts in struct literal`).

- [ ] **Step 2: Implement manager account plumbing**

`ports/session.go`, `SpawnConfig`: add after `RequestedBy`:

```go
	ClaudeAccountID domain.ClaudeAccountID
```

`claude_account.go`:

```go
package sessionmanager

import (
	"context"
	"errors"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type ClaudeAccountLauncher interface {
	PrepareLaunch(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error)
}

func (m *Manager) applyClaudeAccount(ctx context.Context, env map[string]string, id domain.ClaudeAccountID) error {
	if m.claudeAccounts == nil {
		return nil
	}
	account, err := m.claudeAccounts.PrepareLaunch(ctx, domain.NormalizeClaudeAccountID(id))
	if err != nil {
		return fmt.Errorf("claude account %s: %w", domain.NormalizeClaudeAccountID(id), err)
	}
	account.ApplyEnv(env)
	return nil
}

func (m *Manager) resolveSpawnClaudeAccount(ctx context.Context, cfg ports.SpawnConfig) (domain.ClaudeAccountID, error) {
	if cfg.ClaudeAccountID != "" {
		if cfg.Harness != domain.HarnessClaudeCode {
			return "", fmt.Errorf("%w: only claude-code sessions take an account", domain.ErrInvalidClaudeAccount)
		}
		if err := m.checkClaudeAccount(ctx, cfg.ClaudeAccountID); err != nil {
			return "", err
		}
		return cfg.ClaudeAccountID, nil
	}
	if cfg.Harness == domain.HarnessClaudeCode && cfg.RequestedBy != "" && m.store != nil {
		parent, ok, err := m.store.GetSession(ctx, cfg.RequestedBy)
		if err == nil && ok && parent.ClaudeAccountID != "" {
			return parent.ClaudeAccountID, nil
		}
	}
	return domain.DefaultClaudeAccountID, nil
}

func (m *Manager) checkClaudeAccount(ctx context.Context, id domain.ClaudeAccountID) error {
	if m.claudeAccounts == nil {
		return nil
	}
	if _, err := m.claudeAccounts.PrepareLaunch(ctx, id); err != nil {
		if errors.Is(err, domain.ErrClaudeAccountNotFound) {
			return fmt.Errorf("%w: %s", domain.ErrInvalidClaudeAccount, id)
		}
		return err
	}
	return nil
}
```

**`manager.go`:**
- `Manager` struct: add field `claudeAccounts ClaudeAccountLauncher`.
- `Deps`: add `ClaudeAccounts ClaudeAccountLauncher`.
- `New`: add `claudeAccounts: d.ClaudeAccounts,`.
- **Replace `runtimeEnv` and `launchRuntimeEnv` (`:3084-3113`)** with:

```go
func (m *Manager) runtimeEnv(ctx context.Context, rec domain.SessionRecord, account domain.ClaudeAccountID, projectEnv map[string]string) (map[string]string, error) {
	env := m.spawnEnv(rec.ID, rec.ProjectID, rec.IssueID, projectEnv)
	env[EnvBrowserCapability] = ""
	env[EnvBrowserRuntimeToken] = ""
	env[EnvBrowserRuntimeTokenStdin] = ""
	if path, err := HookPATH(m.executable, os.Getenv, projectEnv); err != nil {
		m.logger.Warn("session PATH not pinned to the daemon binary; `opr hooks` callbacks may resolve to a different opr and activity tracking will stall",
			"session", rec.ID, "error", err)
	} else {
		env["PATH"] = path
	}
	if err := m.applyClaudeAccount(ctx, env, account); err != nil {
		return nil, err
	}
	return env, nil
}

func (m *Manager) launchRuntimeEnv(ctx context.Context, rec domain.SessionRecord, account domain.ClaudeAccountID, projectEnv map[string]string) (map[string]string, string, error) {
	env, err := m.runtimeEnv(ctx, rec, account, projectEnv)
	if err != nil {
		return nil, "", err
	}
	if m.browserCapabilities == nil {
		return env, "", nil
	}
	token, verifier, err := m.browserCapabilities.Issue(rec.ID)
	if err != nil {
		return nil, "", err
	}
	if strings.TrimSpace(token) == "" || strings.TrimSpace(verifier) == "" {
		return nil, "", errors.New("browser capability issuer returned an empty credential")
	}
	env[EnvBrowserCapability] = token
	return env, verifier, nil
}
```

- **Spawn, before `:567`** (immediately after the `validateRuntimePrerequisites` block):

```go
	claudeAccount, err := m.resolveSpawnClaudeAccount(ctx, cfg)
	if err != nil {
		return domain.SessionRecord{}, 0, 0, fmt.Errorf("spawn: %w", err)
	}
	cfg.ClaudeAccountID = claudeAccount
```

- **`seedRecord`:** add `ClaudeAccountID: domain.NormalizeClaudeAccountID(cfg.ClaudeAccountID),`.
- **Spawn `:623`:** replace with `env, browserCapabilityVerifier, err := m.launchRuntimeEnv(ctx, rec, rec.ClaudeAccountID, project.Config.Env)`. Change that block's error text from `browser capability` to `launch env`.
- **Restore `:1487`:** replace with `env, browserCapabilityVerifier, err := m.launchRuntimeEnv(ctx, rec, rec.ClaudeAccountID, project.Config.Env)`. Change its error text to `launch env`.
- **`cleanupAgentWorkspace` `:3330-3336`:** replace the project branch with:

```go
	if project, err := m.loadProject(ctx, rec.ProjectID); err == nil {
		if projectEnv, envErr := m.runtimeEnv(ctx, rec, rec.ClaudeAccountID, project.Config.Env); envErr == nil {
			env = projectEnv
		} else {
			m.logger.Warn("workspace cleanup: session env unavailable; agent cleanup using Operator env only",
				"sessionID", rec.ID, "error", envErr)
		}
	} else {
```

**`agent_switching.go`** — signature-only change (Task 7 changes the account argument at `:742` and `:2533`):
- `:214`:
  ```go
  sourceEnv, err := m.runtimeEnv(ctx, rec, rec.ClaudeAccountID, project.Config.Env)
  if err != nil { return domain.AgentSwitch{}, fmt.Errorf("switch agent %s: source env: %w", id, err) }
  ```
- `:742`:
  ```go
  env, err := m.runtimeEnv(ctx, rec, rec.ClaudeAccountID, project.Config.Env)
  if err != nil { return preparedTargetActivation{}, fmt.Errorf("target env: %w", err) }
  ```
- `:2533`:
  ```go
  env, err := m.runtimeEnv(ctx, rec, rec.ClaudeAccountID, project.Config.Env)
  if err != nil { return fmt.Errorf("agent switch recovery: target env: %w", err) }
  ```

- [ ] **Step 3: Wire the API fields and errors**

**`dto.go`:**
- `SpawnSessionRequest`: add after `RequestedBy`:

```go
	ClaudeAccountID domain.ClaudeAccountID `json:"claudeAccountId,omitempty" maxLength:"64" description:"Claude account for a claude-code session. Omit for the default account, or for a worker to inherit its orchestrator's account."`
```

- `SpawnOrchestratorRequest`: add:

```go
	ClaudeAccountID domain.ClaudeAccountID `json:"claudeAccountId,omitempty" maxLength:"64"`
```

**`sessions.go:329`:** add `ClaudeAccountID: in.ClaudeAccountID` to the `ports.SpawnConfig` literal.

**Delegate endpoint.** The desktop new-task composer spawns through `POST /api/v1/orchestrators/delegate` (`TaskComposer.tsx:92`), not `POST /sessions`, so it needs the account too:
- **`dto.go:701` `DelegateTaskRequest`:** add after `WorkspaceMode`:

```go
	ClaudeAccountID domain.ClaudeAccountID `json:"claudeAccountId,omitempty" maxLength:"64" description:"Claude account for a claude-code worker. Omit for the default account."`
```

- **`backend/internal/service/session/delegation.go:26` `DelegateTaskInput`:** add `ClaudeAccountID domain.ClaudeAccountID`. In the `ports.SpawnConfig` literal at `:63`, add `ClaudeAccountID: in.ClaudeAccountID,`.
- **`sessions.go` `delegateTask`:** in the `sessionsvc.DelegateTaskInput{...}` literal passed to `c.Svc.DelegateTask`, add `ClaudeAccountID: domain.ClaudeAccountID(strings.TrimSpace(string(in.ClaudeAccountID))),`.
- **Test:** add a controller test beside the existing delegate test (`grep -ln 'orchestrators/delegate' backend/internal/httpd/controllers/*_test.go`). It posts `{"projectId":"p","brief":"x","agent":"claude-code","claudeAccountId":"personal"}` and asserts the fake recorded `DelegateTaskInput.ClaudeAccountID == "personal"`.

**`spawnOrchestrator`:** pass `in.ClaudeAccountID` as the new last argument of `c.Svc.SpawnOrchestrator`. Update the `SessionService` interface in the controllers package to the new signature; find it with `grep -n 'SpawnOrchestrator(' backend/internal/httpd/controllers/*.go`.

**`service.go`:**
- `SpawnOrchestrator` gains `account domain.ClaudeAccountID` and sets `ClaudeAccountID: account` in the `ports.SpawnConfig` at `:442`.
- Update every caller (`grep -rn '\.SpawnOrchestrator(' backend/internal --include='*.go'`). Non-HTTP callers pass `""`.
- In `toAPIError`, add before the `ErrUnknownHarness` case:

```go
	case errors.Is(err, domain.ErrInvalidClaudeAccount), errors.Is(err, domain.ErrClaudeAccountNotFound):
		return apierr.Invalid("INVALID_CLAUDE_ACCOUNT", "Unknown Claude account, or an account was given for an agent other than Claude Code", nil)
	case errors.Is(err, domain.ErrClaudeAccountFolderUnavailable):
		return apierr.Conflict("CLAUDE_ACCOUNT_FOLDER_UNAVAILABLE", "The Claude account folder is missing or unusable; check Settings → Claude accounts", nil)
```

**Controller test:**
1. Find the existing spawn controller test whose fake service records its `ports.SpawnConfig`: `grep -ln 'SpawnConfig' backend/internal/httpd/controllers/*_test.go`.
2. Add a test that posts `{"projectId":"p","harness":"claude-code","claudeAccountId":"personal"}` to `/api/v1/sessions` and asserts the recorded `cfg.ClaudeAccountID == "personal"`.
3. Reuse that file's fake and server helper unchanged.

- [ ] **Step 4: Run tests**

Run: `cd backend && go build ./... && go test ./internal/session_manager/... ./internal/service/session/... ./internal/httpd/...`
Expected: PASS, except the httpd spec drift tests, which fail until `npm run api` (Step 5).

- [ ] **Step 5: Regenerate API and re-run**

Run: `npm run api && cd backend && go test ./internal/httpd/...`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend frontend/src/api/schema.ts
git commit -m "feat(sessions): launch every session on its Claude account" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 7: Switch a running session to another Claude account

**Files:**
- Modify: `backend/internal/session_manager/claude_account.go` (add `switchTargetClaudeAccount`)
- Modify: `backend/internal/session_manager/claude_account_test.go`
- Modify: `backend/internal/session_manager/agent_switching.go`:
  - `SwitchAgentConfig` `:46-50`
  - fingerprint `:84`
  - same-harness check `:186-188`
  - `switchRec` literal `:224-235`
  - `prepareTargetActivation` env `:742`
  - activation literals `:542-553`, `:2677`
  - `cleanupRecoveredTargetWorkspace` `:2533`
- Modify: `backend/internal/service/session/agent_switching.go:13-27`
- Modify: `backend/internal/httpd/controllers/dto.go:252-274` (`SwitchAgentRequest`, `AgentSwitchView`)
- Modify: `backend/internal/httpd/controllers/sessions.go:1160-1164` (`switchAgent`), `:2008-2023` (`agentSwitchView`)

**Interfaces:**
- Consumes:
  - `runtimeEnv(ctx, rec, account, projectEnv)` (Task 6)
  - `AgentSwitch.FromClaudeAccountID/TargetClaudeAccountID` and `AgentSwitchTargetActivation.SourceClaudeAccountID/TargetClaudeAccountID` (Task 1)
  - store validation that allows same harness across accounts (Task 2)
- Produces:
  - `sessionmanager.SwitchAgentConfig.TargetClaudeAccountID domain.ClaudeAccountID`
  - `func switchTargetClaudeAccount(rec domain.SessionRecord, cfg SwitchAgentConfig) (domain.ClaudeAccountID, error)`
  - `sessionsvc.SwitchAgentInput.TargetClaudeAccountID`
  - wire fields: `targetClaudeAccountId` on the request; `fromClaudeAccountId`/`targetClaudeAccountId` on `AgentSwitchView`

- [ ] **Step 1: Write the failing test**

Append to `claude_account_test.go`:

```go
func TestSwitchTargetClaudeAccount(t *testing.T) {
	claudeOnPersonal := domain.SessionRecord{Harness: domain.HarnessClaudeCode, ClaudeAccountID: "personal"}
	codexSession := domain.SessionRecord{Harness: domain.HarnessCodex, ClaudeAccountID: ""}

	cases := []struct {
		name string
		rec  domain.SessionRecord
		cfg  SwitchAgentConfig
		want domain.ClaudeAccountID
		err  error
	}{
		{name: "claude to other account", rec: claudeOnPersonal, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessClaudeCode, TargetClaudeAccountID: "default"}, want: domain.DefaultClaudeAccountID},
		{name: "claude same account rejected", rec: claudeOnPersonal, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessClaudeCode, TargetClaudeAccountID: "personal"}, err: ErrAlreadyUsingHarness},
		{name: "claude omitted account rejected", rec: claudeOnPersonal, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessClaudeCode}, err: ErrAlreadyUsingHarness},
		{name: "claude to codex keeps account", rec: claudeOnPersonal, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessCodex}, want: "personal"},
		{name: "codex target with account rejected", rec: claudeOnPersonal, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessCodex, TargetClaudeAccountID: "default"}, err: domain.ErrInvalidClaudeAccount},
		{name: "codex to claude on account", rec: codexSession, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessClaudeCode, TargetClaudeAccountID: "personal"}, want: "personal"},
		{name: "codex to claude default", rec: codexSession, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessClaudeCode}, want: domain.DefaultClaudeAccountID},
		{name: "codex to codex rejected", rec: codexSession, cfg: SwitchAgentConfig{TargetHarness: domain.HarnessCodex}, err: ErrAlreadyUsingHarness},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := switchTargetClaudeAccount(tc.rec, tc.cfg)
			if tc.err != nil {
				if !errors.Is(err, tc.err) {
					t.Fatalf("err = %v, want %v", err, tc.err)
				}
				return
			}
			if err != nil || got != tc.want {
				t.Fatalf("got %q err=%v, want %q", got, err, tc.want)
			}
		})
	}
}
```

Run: `cd backend && go test ./internal/session_manager/ -run TestSwitchTargetClaudeAccount`
Expected: FAIL (`undefined: switchTargetClaudeAccount`).

- [ ] **Step 2: Implement**

Append to `claude_account.go`:

```go
func switchTargetClaudeAccount(rec domain.SessionRecord, cfg SwitchAgentConfig) (domain.ClaudeAccountID, error) {
	current := domain.NormalizeClaudeAccountID(rec.ClaudeAccountID)
	if cfg.TargetHarness != domain.HarnessClaudeCode {
		if cfg.TargetClaudeAccountID != "" {
			return "", fmt.Errorf("%w: only a claude-code target takes an account", domain.ErrInvalidClaudeAccount)
		}
		if rec.Harness == cfg.TargetHarness {
			return "", fmt.Errorf("%w: %s", ErrAlreadyUsingHarness, cfg.TargetHarness)
		}
		return current, nil
	}
	target := current
	if cfg.TargetClaudeAccountID != "" {
		target = cfg.TargetClaudeAccountID
	}
	if rec.Harness == domain.HarnessClaudeCode && target == current {
		return "", fmt.Errorf("%w: %s on account %s", ErrAlreadyUsingHarness, cfg.TargetHarness, target)
	}
	return target, nil
}
```

**`agent_switching.go`:**
- `SwitchAgentConfig`: add `TargetClaudeAccountID domain.ClaudeAccountID`.
- In `SwitchAgent`, normalize it next to the other trims: `cfg.TargetClaudeAccountID = domain.ClaudeAccountID(strings.TrimSpace(string(cfg.TargetClaudeAccountID)))`.
- `:84`: `requestFingerprint := domain.ComputeAgentSwitchRequestFingerprint(id, cfg.TargetHarness, cfg.TargetClaudeAccountID, cfg.Note)`.
- **Replace `:186-188`** (the `rec.Harness == cfg.TargetHarness` block) with:

```go
	targetClaudeAccount, err := switchTargetClaudeAccount(rec, cfg)
	if err != nil {
		return domain.AgentSwitch{}, fmt.Errorf("switch agent %s: %w", id, err)
	}
	if m.claudeAccounts != nil && cfg.TargetHarness == domain.HarnessClaudeCode {
		if err := m.checkClaudeAccount(ctx, targetClaudeAccount); err != nil {
			return domain.AgentSwitch{}, fmt.Errorf("switch agent %s: %w", id, err)
		}
	}
```

  If `err` is already declared in scope there, use `=` for the first assignment.
- **`switchRec` literal:** add `FromClaudeAccountID: domain.NormalizeClaudeAccountID(rec.ClaudeAccountID), TargetClaudeAccountID: targetClaudeAccount,`.
- **Target env** — `prepareTargetActivation` `:742` and `cleanupRecoveredTargetWorkspace` `:2533`: pass `sw.TargetClaudeAccountID` instead of `rec.ClaudeAccountID`. `:214` keeps `rec.ClaudeAccountID`, because the source runs on the session's current account.
- **Both activation literals** (`:542-553` and the one at `:2677`): add `SourceClaudeAccountID: sw.FromClaudeAccountID, TargetClaudeAccountID: sw.TargetClaudeAccountID,`. At `:542` the saved switch record is named `result`; use `result.FromClaudeAccountID` / `result.TargetClaudeAccountID` there.

**`service/session/agent_switching.go`:** add `TargetClaudeAccountID domain.ClaudeAccountID` to `SwitchAgentInput` and pass it into `SwitchAgentConfig`.

**`dto.go`:**
- `SwitchAgentRequest`: add

```go
	TargetClaudeAccountID domain.ClaudeAccountID `json:"targetClaudeAccountId,omitempty" maxLength:"64" description:"Claude account for a claude-code target. Omit to keep the session's current account."`
```

- `AgentSwitchView`: add after `TargetHarness`:

```go
	FromClaudeAccountID   domain.ClaudeAccountID `json:"fromClaudeAccountId,omitempty"`
	TargetClaudeAccountID domain.ClaudeAccountID `json:"targetClaudeAccountId,omitempty"`
```

**`sessions.go`:**
- In `switchAgent`, pass `TargetClaudeAccountID: domain.ClaudeAccountID(strings.TrimSpace(string(in.TargetClaudeAccountID)))`.
- In `agentSwitchView`, map both new fields.

**Recovery paths.** Any other place in `agent_switching.go` that checks `sw.FromHarness != sw.TargetHarness`, or treats "same harness" as impossible, must also accept a differing account. Find them with `grep -n 'FromHarness == \|FromHarness != \|TargetHarness == rec.Harness\|rec.Harness == sw.TargetHarness' backend/internal/session_manager/agent_switching.go`. For each hit, read the surrounding function. If it is a "nothing to switch" guard, change the condition to also compare `sw.FromClaudeAccountID` with `sw.TargetClaudeAccountID`.

- [ ] **Step 3: Run tests**

Run: `cd backend && go build ./... && go test ./internal/session_manager/... ./internal/storage/... ./internal/service/session/... && npm run api && go test ./internal/httpd/...`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add backend frontend/src/api/schema.ts
git commit -m "feat(switching): switch a session to another Claude account" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 8: Transcripts, usage and daemon wiring follow each account

**Files:**
- Modify: `backend/internal/observe/transcript/resolve.go:21-60`
- Test: `backend/internal/observe/transcript/resolve_account_test.go` (create)
- Modify: `backend/internal/service/usage/collector.go`:
  - `SourceRoots` `:58-63`
  - `validateSourcePath` `:1577`
  - `allowedRoots` `:1648`
  - `discoverPath` `:1691` and its callers `:254`, `:499`, `:778`
- Test: `backend/internal/service/usage/collector_accounts_test.go` (create)
- Modify: `backend/internal/observe/usage/watcher.go` (add `AddRoot`)
- Modify: `backend/internal/observe/usage/pipeline.go` (`Pipeline` struct, `run`, add `AddRoot`)
- Test: `backend/internal/observe/usage/watcher_addroot_test.go` (create)
- Modify: `backend/internal/daemon/session_id_claim.go:62-95` (`agentSessionIDClaims`)
- Modify: `backend/internal/daemon/lifecycle_wiring.go:159` (`startSession` signature, `SetSessionIDInUse`, `sessionmanager.Deps`)
- Modify: `backend/internal/daemon/daemon.go`:
  - after `:71` (drop inherited env)
  - after the settings service `:194-197` (build accounts service)
  - `startSession` call `:213`
  - usage roots `:285-310`
  - transcript watcher/resolver `:438-455`

**Interfaces:**
- Consumes:
  - `claudeaccounts.Service` methods `EnvFor`, `ConfigDirFor`, `ConfigDirs`, `OnAccountAdded`, `PrepareLaunch` (Task 5)
  - `ports.MultiConfigSessionIDClaimChecker` (Task 4)
  - `sessionmanager.Deps.ClaudeAccounts` (Task 6)
- Produces:
  - `transcript.ClaudeAccountEnv interface{ EnvFor(ctx context.Context, id domain.ClaudeAccountID) (map[string]string, error) }`
  - `transcript.NewResolver(agents ports.AgentResolver, accounts ClaudeAccountEnv) *Resolver`
  - `usagesvc.SourceRoots.ClaudeProjectRoots func(context.Context) []string`
  - `usagesvc.SourceRoots.ClaudeProjectsFor func(context.Context, domain.SessionID) (string, error)`
  - `(*usage.TranscriptWatcher).AddRoot(ctx context.Context, root string) error`
  - `(*usage.Pipeline).AddRoot(ctx context.Context, root string)`

- [ ] **Step 1: Write the failing tests**

`resolve_account_test.go`:

```go
package transcript

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type oneAgent struct{ agent ports.Agent }

func (o oneAgent) Agent(domain.AgentHarness) (ports.Agent, bool) { return o.agent, true }

type accountEnv map[domain.ClaudeAccountID]map[string]string

func (a accountEnv) EnvFor(_ context.Context, id domain.ClaudeAccountID) (map[string]string, error) {
	if env, ok := a[domain.NormalizeClaudeAccountID(id)]; ok {
		return env, nil
	}
	return nil, domain.ErrClaudeAccountNotFound
}

func TestResolverReadsSessionAccountFolder(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv(domain.ClaudeConfigDirEnv, "")
	personal := filepath.Join(t.TempDir(), ".claude-personal")
	nativeID := claudecode.SessionUUID("proj-3")
	transcript := filepath.Join(personal, "projects", "-repo", nativeID+".jsonl")
	if err := os.MkdirAll(filepath.Dir(transcript), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(transcript, []byte("{}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	accounts := accountEnv{
		domain.DefaultClaudeAccountID: {},
		"personal":                    {domain.ClaudeConfigDirEnv: personal},
	}
	resolver := NewResolver(oneAgent{agent: claudecode.New()}, accounts)
	rec := domain.SessionRecord{ID: "proj-3", Harness: domain.HarnessClaudeCode, ClaudeAccountID: "personal", Metadata: domain.SessionMetadata{AgentSessionID: nativeID}}

	got := resolver.Path(context.Background(), rec)
	want, _ := filepath.EvalSymlinks(transcript)
	if got != want {
		t.Fatalf("path = %q, want %q", got, want)
	}

	rec.ClaudeAccountID = domain.DefaultClaudeAccountID
	if got := resolver.Path(context.Background(), rec); got != "" {
		t.Fatalf("default account resolved another account's transcript: %q", got)
	}
}
```

`t.Setenv(domain.ClaudeConfigDirEnv, "")` only makes sure a developer's own environment can't leak in. `nativeconfig.Resolve` treats an empty process value as unset.

`collector_accounts_test.go`, in the same package as `collector_test.go`:

```go
package usage

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestAllowedRootsUseAccountRootsWhenProvided(t *testing.T) {
	a := filepath.Join(t.TempDir(), "projects")
	b := filepath.Join(t.TempDir(), "projects")
	c := NewCollector(nil, SourceRoots{
		ClaudeProjects:     "/ignored",
		ClaudeProjectRoots: func(context.Context) []string { return []string{a, b} },
	}, nil)
	got := c.allowedRoots(context.Background(), domain.HarnessClaudeCode)
	if len(got) != 2 || got[0] != a || got[1] != b {
		t.Fatalf("roots = %v", got)
	}
	legacy := NewCollector(nil, SourceRoots{ClaudeProjects: a}, nil)
	if got := legacy.allowedRoots(context.Background(), domain.HarnessClaudeCode); len(got) != 1 || got[0] != a {
		t.Fatalf("legacy roots = %v", got)
	}
}

func TestClaudeProjectsRootForSession(t *testing.T) {
	c := NewCollector(nil, SourceRoots{
		ClaudeProjects: "/default/projects",
		ClaudeProjectsFor: func(_ context.Context, id domain.SessionID) (string, error) {
			if id == "proj-9" {
				return "/acct/projects", nil
			}
			return "", domain.ErrClaudeAccountNotFound
		},
	}, nil)
	if got := c.claudeProjectsRoot(context.Background(), "proj-9"); got != "/acct/projects" {
		t.Fatalf("root = %q", got)
	}
	if got := c.claudeProjectsRoot(context.Background(), "proj-x"); got != "" {
		t.Fatalf("unknown session root = %q, want empty", got)
	}
}
```

If `NewCollector(nil, ...)` panics on a nil store, pass `collectorTestStore(t)` (defined in `collector_test.go`).

`watcher_addroot_test.go`, in the same package as `watcher.go`:

```go
package usage

import (
	"context"
	"testing"
)

func TestTranscriptWatcherAddRootIsIdempotent(t *testing.T) {
	ctx := context.Background()
	first := t.TempDir()
	second := t.TempDir()
	w, err := NewTranscriptWatcher(ctx, []string{first})
	if err != nil {
		t.Fatal(err)
	}
	if err := w.AddRoot(ctx, second); err != nil {
		t.Fatal(err)
	}
	if err := w.AddRoot(ctx, second); err != nil {
		t.Fatal(err)
	}
	w.mu.Lock()
	count := len(w.roots)
	w.mu.Unlock()
	if count != 2 {
		t.Fatalf("roots = %d, want 2", count)
	}
}
```

Run: `cd backend && go test ./internal/observe/... ./internal/service/usage/ -run 'ResolverReadsSessionAccount|AllowedRootsUseAccount|ClaudeProjectsRootForSession|AddRootIsIdempotent'`
Expected: FAIL (compile errors).

- [ ] **Step 2: Implement the resolver**

`resolve.go`:

```go
type ClaudeAccountEnv interface {
	EnvFor(ctx context.Context, id domain.ClaudeAccountID) (map[string]string, error)
}

type Resolver struct {
	agents   ports.AgentResolver
	accounts ClaudeAccountEnv
}

func NewResolver(agents ports.AgentResolver, accounts ClaudeAccountEnv) *Resolver {
	return &Resolver{agents: agents, accounts: accounts}
}
```

In `Path`, replace `configDir, err := provider.NativeSessionConfigDir(ctx, nil)` with:

```go
	env := map[string]string{}
	if r.accounts != nil {
		accountEnv, err := r.accounts.EnvFor(ctx, rec.ClaudeAccountID)
		if err != nil {
			return ""
		}
		env = accountEnv
	}
	configDir, err := provider.NativeSessionConfigDir(ctx, env)
```

Update the existing `NewResolver(` test callers to pass `nil` as the second argument: `grep -rn 'NewResolver(' backend/internal --include='*_test.go'`.

- [ ] **Step 3: Implement collector roots**

`SourceRoots`: add

```go
	ClaudeProjectRoots func(context.Context) []string
	ClaudeProjectsFor  func(context.Context, domain.SessionID) (string, error)
```

Replace `allowedRoots` with:

```go
func (c *Collector) allowedRoots(ctx context.Context, harness domain.AgentHarness) []string {
	switch harness {
	case domain.HarnessClaudeCode:
		if c.roots.ClaudeProjectRoots != nil {
			return c.roots.ClaudeProjectRoots(ctx)
		}
		return []string{c.roots.ClaudeProjects}
	case domain.HarnessCodex:
		return []string{c.roots.CodexSessions, c.roots.CodexArchived}
	default:
		return nil
	}
}

func (c *Collector) claudeProjectsRoot(ctx context.Context, sessionID domain.SessionID) string {
	if c.roots.ClaudeProjectsFor == nil {
		return c.roots.ClaudeProjects
	}
	root, err := c.roots.ClaudeProjectsFor(ctx, sessionID)
	if err != nil {
		return ""
	}
	return root
}
```

**Callers:**
- In `validateSourcePath` `:1577`: `roots := c.allowedRoots(ctx, harness)`.
- `discoverPath` signature: `func (c *Collector) discoverPath(ctx context.Context, harness domain.AgentHarness, sessionID domain.SessionID, nativeID string) (string, error)`. Replace its Claude pattern line with:

```go
	case domain.HarnessClaudeCode:
		root := c.claudeProjectsRoot(ctx, sessionID)
		if root == "" {
			return "", nil
		}
		patterns = []string{filepath.Join(root, "*", nativeID+".jsonl")}
```

- Update callers: `:254` `c.discoverPath(ctx, session.Harness, session.ID, signal.NativeSessionID)`; `:499` `c.discoverPath(ctx, session.Harness, session.ID, nativeID)`; `:778` `c.discoverPath(ctx, binding.Harness, binding.SessionID, binding.NativeRootID)`. If the variable in scope at a site has another name, use that record's `ID`/`SessionID`.

- [ ] **Step 4: Implement `AddRoot`**

`watcher.go`:

```go
func (w *TranscriptWatcher) AddRoot(ctx context.Context, root string) error {
	normalized, err := normalizeTranscriptRoots([]string{root})
	if err != nil {
		return err
	}
	if len(normalized) == 0 {
		return nil
	}
	resolved, err := resolveTranscriptRoot(ctx, normalized[0])
	if err != nil {
		return fmt.Errorf("resolve transcript root: %w", redactFilesystemError(err))
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	for _, existing := range w.roots {
		if existing == resolved {
			return nil
		}
	}
	w.roots = append(w.roots, resolved)
	return nil
}
```

`pipeline.go`:
- Add `mu sync.Mutex` and `current transcriptWatcher` to `Pipeline`, and import `sync`.
- In `run`, replace `watcher, err := p.newWatcher(ctx, p.roots)` with:

```go
		p.mu.Lock()
		roots := append([]string(nil), p.roots...)
		p.mu.Unlock()
		watcher, err := p.newWatcher(ctx, roots)
```

- After the `err != nil` block, add:

```go
		p.mu.Lock()
		p.current = watcher
		p.mu.Unlock()
```

- Add the method:

```go
func (p *Pipeline) AddRoot(ctx context.Context, root string) {
	p.mu.Lock()
	for _, existing := range p.roots {
		if existing == root {
			p.mu.Unlock()
			return
		}
	}
	p.roots = append(p.roots, root)
	current := p.current
	p.mu.Unlock()
	if adder, ok := current.(interface {
		AddRoot(context.Context, string) error
	}); ok {
		if err := adder.AddRoot(ctx, root); err != nil {
			p.logger.Warn("usage transcript watcher could not add root", "err", err)
		}
	}
	p.NotifySourcesChanged()
}
```

- [ ] **Step 5: Wire the daemon**

**`session_id_claim.go`:** give `agentSessionIDClaims` a `claudeConfigDirs func(context.Context) ([]string, error)` field. In `IsSessionIDClaimed`, replace the `checker` lookup-and-call with:

```go
		var claimed bool
		var err error
		if multi, ok := agent.(ports.MultiConfigSessionIDClaimChecker); ok && a.claudeConfigDirs != nil {
			dirs, dirsErr := a.claudeConfigDirs(ctx)
			if dirsErr != nil {
				err = dirsErr
			} else {
				claimed, err = multi.IsSessionIDClaimedIn(ctx, sessionID, dirs)
			}
		} else if checker, ok := agent.(ports.SessionIDClaimChecker); ok {
			claimed, err = checker.IsSessionIDClaimed(ctx, sessionID)
		} else {
			continue
		}
```

Keep the existing `err`/`claimed` handling that follows.

**`daemon.go`, right after `log := newLogger()` (`:71`):**

```go
	if inherited, ok := os.LookupEnv(domain.ClaudeConfigDirEnv); ok {
		log.Warn("ignoring inherited CLAUDE_CONFIG_DIR; Claude accounts are chosen per session", "value", inherited)
		if err := os.Unsetenv(domain.ClaudeConfigDirEnv); err != nil {
			return fmt.Errorf("unset inherited %s: %w", domain.ClaudeConfigDirEnv, err)
		}
	}
```

**`daemon.go`, after the settings service block (`:194-197`):**

```go
	userHome, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("resolve home directory for claude accounts: %w", err)
	}
	claudeAccounts := claudeaccountssvc.New(claudeaccountssvc.Deps{
		Store:  store,
		Prober: claudeaccountssvc.NewCommandProber(3 * time.Second),
		Home:   userHome,
	})
```

Import `claudeaccountssvc "github.com/OmarAly92/operator/backend/internal/service/claudeaccounts"`. If `err` is already declared in scope, use `userHome, homeErr := ...`.

**`lifecycle_wiring.go` `startSession`:**
- Add a `claudeAccounts *claudeaccountssvc.Service` parameter after `agents`.
- Change the claim probe to `agentSessionIDClaims{agents: agents, claudeConfigDirs: claudeAccounts.ConfigDirs}`.
- Add `ClaudeAccounts: claudeAccounts,` to `sessionmanager.Deps`.
- Update the `:213` call to pass `claudeAccounts`.

**`daemon.go` usage (`:285`):** after `roots` resolves successfully, add:

```go
		roots.ClaudeProjectRoots = func(ctx context.Context) []string {
			dirs, err := claudeAccounts.ConfigDirs(ctx)
			if err != nil {
				return []string{roots.ClaudeProjects}
			}
			out := make([]string, 0, len(dirs))
			for _, dir := range dirs {
				out = append(out, filepath.Join(dir, "projects"))
			}
			return out
		}
		roots.ClaudeProjectsFor = func(ctx context.Context, id domain.SessionID) (string, error) {
			rec, ok, err := store.GetSession(ctx, id)
			if err != nil {
				return "", err
			}
			if !ok {
				return "", domain.ErrClaudeAccountNotFound
			}
			dir, err := claudeAccounts.ConfigDirFor(ctx, rec.ClaudeAccountID)
			if err != nil {
				return "", err
			}
			return filepath.Join(dir, "projects"), nil
		}
```

- Replace the pipeline's `roots.ClaudeProjects,` entry (`:300`) with `roots.ClaudeProjectRoots(ctx)...` and move `roots.CodexSessions, roots.CodexArchived` into an `append`:

```go
		usagePipeline = usagepipeline.NewPipeline(store, ingestor, append(roots.ClaudeProjectRoots(ctx), roots.CodexSessions, roots.CodexArchived), usagepipeline.CoordinatorConfig{
```

- After `usagePipeline` is assigned, add:

```go
		claudeAccounts.OnAccountAdded(func(dir string) {
			usagePipeline.AddRoot(ctx, filepath.Join(dir, "projects"))
		})
```

  If `store.GetSession`'s return shape differs from `(rec, ok, err)`, match it.

**`daemon.go` transcript watcher (`:438-455`):**
- Build the watcher roots from the accounts service instead of the single `roots.ClaudeProjects`:

```go
	} else {
		claudeRoots := []string{roots.ClaudeProjects}
		if dirs, dirsErr := claudeAccounts.ConfigDirs(ctx); dirsErr == nil {
			claudeRoots = claudeRoots[:0]
			for _, dir := range dirs {
				claudeRoots = append(claudeRoots, filepath.Join(dir, "projects"))
			}
		}
		if watcher, watchErr := usagepipeline.NewTranscriptWatcher(ctx, append(claudeRoots, roots.CodexSessions)); watchErr != nil {
			log.Warn("transcript block projection falls back to polling", "err", watchErr)
		} else {
			transcriptWatcher = watcher
			claudeAccounts.OnAccountAdded(func(dir string) {
				if err := watcher.AddRoot(ctx, filepath.Join(dir, "projects")); err != nil {
					log.Warn("transcript watcher could not add claude account root", "err", err)
				}
			})
		}
	}
```

- Change `Resolver: transcriptsvc.NewResolver(agents)` to `transcriptsvc.NewResolver(agents, claudeAccounts)`.
- Keep the existing variable names (`transcriptWatcher`, `roots`) and restructure the `if/else if` chain only as needed to compile.

- [ ] **Step 6: Run tests**

Run: `cd backend && go build ./... && go test -race ./internal/observe/... ./internal/service/usage/... ./internal/daemon/...`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend
git commit -m "feat(daemon): transcripts, usage and id claims follow each Claude account" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 9: HTTP routes for accounts and the login terminal

**Files:**
- Create: `backend/internal/httpd/controllers/claude_accounts.go`
- Create: `backend/internal/httpd/controllers/claude_accounts_test.go`
- Modify: `backend/internal/httpd/controllers/dto.go` (append account DTOs after `ShellTerminalHandleIDParam` `:1209`)
- Modify: `backend/internal/service/shellterm/types.go:48-53` (`OpenShellTerminalInput`)
- Modify: `backend/internal/service/shellterm/service.go:102-145` (`OpenShellTerminal`)
- Test: `backend/internal/service/shellterm/service_test.go` (add one test)
- Modify: `backend/internal/httpd/api.go`:
  - `APIDeps` `:54`
  - controller construction `:122`
  - `Register` `:160`
- Modify: `backend/internal/httpd/apispec/specgen/build.go`:
  - `schemaNames` near `:277`
  - operations after the shell-terminals block `:668`
  - query struct near `:498`
- Modify: `backend/internal/daemon/daemon.go:379` (`APIDeps.ClaudeAccounts`)

**Interfaces:**
- Consumes: `claudeaccounts.Service` (Task 5); `ShellTerminalService.OpenShellTerminal` (existing, `shell_terminals.go:28`).
- Produces:
  - **Routes:** `GET /api/v1/claude-accounts[?refresh=1]`, `POST /api/v1/claude-accounts`, `PATCH /api/v1/claude-accounts/{accountId}`, `DELETE /api/v1/claude-accounts/{accountId}`, `POST /api/v1/claude-accounts/{accountId}/login`, `POST /api/v1/claude-accounts/{accountId}/relink`
  - **Schemas:** `ClaudeAccountView{id,label,configDir,isDefault,status{loggedIn,subscriptionType,reportedEmail,checkedAt},sharedSetup}`, `ListClaudeAccountsResponse{accounts}`, `ClaudeAccountEnvelope{account}`, `CreateClaudeAccountRequest{label}`, `RenameClaudeAccountRequest{label}`
  - `shelltermsvc.OpenShellTerminalInput.Env/Argv/Title` (internal, `json:"-"`)

- [ ] **Step 1: Write the failing shell-terminal test**

Add to `backend/internal/service/shellterm/service_test.go`. It uses the file's own `newFakeShellRuntime`, `fakeShellTerminalStore`, `fakeProjectRootLocator` and `newTestService` helpers, following `TestOpenShellTerminalWithNoSessionOrProjectUsesDataDir` at `:18`:

```go
func TestOpenShellTerminalUsesExplicitArgvEnvAndTitle(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{}
	svc := newTestService(t, rt, st, &fakeProjectRootLocator{})
	term, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{
		Argv:  []string{"/usr/local/bin/claude"},
		Env:   map[string]string{"CLAUDE_CONFIG_DIR": "/Users/u/.claude-personal"},
		Title: "Claude login · Personal",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(rt.created) != 1 {
		t.Fatalf("created = %d runtimes, want 1", len(rt.created))
	}
	got := rt.created[0]
	if len(got.Argv) != 1 || got.Argv[0] != "/usr/local/bin/claude" {
		t.Fatalf("argv = %v", got.Argv)
	}
	if got.Env["CLAUDE_CONFIG_DIR"] != "/Users/u/.claude-personal" || got.Env["OPERATOR_TERMINAL_ID"] == "" {
		t.Fatalf("env = %v", got.Env)
	}
	if term.Title != "Claude login · Personal" {
		t.Fatalf("title = %q", term.Title)
	}
}
```

Run: `cd backend && go test ./internal/service/shellterm/ -run ExplicitArgv`
Expected: FAIL (`unknown field Argv`).

- [ ] **Step 2: Implement shell-terminal overrides**

`types.go` — `OpenShellTerminalInput` becomes:

```go
type OpenShellTerminalInput struct {
	ProjectID domain.ProjectID  `json:"projectId,omitempty"`
	SessionID domain.SessionID  `json:"sessionId,omitempty"`
	Cols      int               `json:"cols,omitempty"`
	Rows      int               `json:"rows,omitempty"`
	Argv      []string          `json:"-"`
	Env       map[string]string `json:"-"`
	Title     string            `json:"-"`
}
```

`service.go` `OpenShellTerminal` — replace the block from `resolved := resolveUserLoginShell()` through `argv, env, err := s.shellBootstrapArgvEnv(...)` and its error return with:

```go
	var argv []string
	env := map[string]string{}
	if len(in.Argv) > 0 {
		argv = append([]string(nil), in.Argv...)
	} else {
		resolved := resolveUserLoginShell()
		if len(resolved) == 0 {
			return ShellTerminal{}, apierr.Internal("SHELL_TERMINAL_NO_SHELL",
				"Could not determine a shell to launch. Set SHELL (macOS/Linux) or ComSpec (Windows).")
		}
		argv, env, err = s.shellBootstrapArgvEnv(resolved[0])
		if err != nil {
			return ShellTerminal{}, fmt.Errorf("open shell terminal: shell recipe: %w", err)
		}
	}
	for key, value := range in.Env {
		env[key] = value
	}
```

In the record literal, replace `Title: shellTerminalTitle(workingDir),` with:

```go
		Title:      shellTerminalTitleOr(in.Title, workingDir),
```

Add to `types.go`:

```go
func shellTerminalTitleOr(title, workingDir string) string {
	if strings.TrimSpace(title) != "" {
		return title
	}
	return shellTerminalTitle(workingDir)
}
```

Add a `strings` import where needed.

- [ ] **Step 3: Write the failing controller tests**

`claude_accounts_test.go`:

```go
package controllers_test

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode/claudesetup"
	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	claudeaccountssvc "github.com/OmarAly92/operator/backend/internal/service/claudeaccounts"
	shelltermsvc "github.com/OmarAly92/operator/backend/internal/service/shellterm"
)

type fakeClaudeAccountService struct {
	created    string
	deleteErr  error
	createErr  error
	refreshed  bool
	loginInput domain.ClaudeAccountID
}

func (f *fakeClaudeAccountService) List(_ context.Context, refresh bool) ([]claudeaccountssvc.AccountView, error) {
	f.refreshed = refresh
	yes := true
	return []claudeaccountssvc.AccountView{
		{Account: domain.ClaudeAccount{ID: "default", Label: "Default", IsDefault: true}, ConfigDir: "/Users/u/.claude", SharedSetup: claudesetup.Report{}},
		{
			Account:     domain.ClaudeAccount{ID: "personal", Label: "Personal", ConfigDir: "/Users/u/.claude-personal"},
			ConfigDir:   "/Users/u/.claude-personal",
			Status:      claudeaccountssvc.AuthStatus{LoggedIn: &yes, SubscriptionType: "pro"},
			SharedSetup: claudesetup.Report{"settings.json": claudesetup.ItemReplaced},
		},
	}, nil
}

func (f *fakeClaudeAccountService) Create(_ context.Context, label string) (domain.ClaudeAccount, error) {
	f.created = label
	if f.createErr != nil {
		return domain.ClaudeAccount{}, f.createErr
	}
	return domain.ClaudeAccount{ID: "personal", Label: label, ConfigDir: "/Users/u/.claude-personal"}, nil
}

func (f *fakeClaudeAccountService) Rename(_ context.Context, id domain.ClaudeAccountID, label string) (domain.ClaudeAccount, error) {
	return domain.ClaudeAccount{ID: id, Label: label, ConfigDir: "/Users/u/.claude-personal"}, nil
}

func (f *fakeClaudeAccountService) Delete(context.Context, domain.ClaudeAccountID) error {
	return f.deleteErr
}

func (f *fakeClaudeAccountService) Relink(context.Context, domain.ClaudeAccountID) (claudesetup.Report, error) {
	return claudesetup.Report{"settings.json": claudesetup.ItemLinked}, nil
}

func (f *fakeClaudeAccountService) Login(_ context.Context, id domain.ClaudeAccountID) (claudeaccountssvc.LoginLaunch, error) {
	f.loginInput = id
	return claudeaccountssvc.LoginLaunch{
		Account: domain.ClaudeAccount{ID: id, Label: "Personal"},
		Argv:    []string{"/usr/local/bin/claude"},
		Env:     map[string]string{domain.ClaudeConfigDirEnv: "/Users/u/.claude-personal"},
		Title:   "Claude login · Personal",
	}, nil
}

type fakeLoginTerminals struct {
	controllers.ShellTerminalService
	got shelltermsvc.OpenShellTerminalInput
}

func (f *fakeLoginTerminals) OpenShellTerminal(_ context.Context, in shelltermsvc.OpenShellTerminalInput) (shelltermsvc.ShellTerminal, error) {
	f.got = in
	return shelltermsvc.ShellTerminal{HandleID: "shellterm-abc", WorkingDir: "/tmp", Title: in.Title}, nil
}

func newClaudeAccountsTestServer(t *testing.T, svc controllers.ClaudeAccountService, terms controllers.ShellTerminalService) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{ClaudeAccounts: svc, ShellTerminals: terms}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestClaudeAccountsList(t *testing.T) {
	svc := &fakeClaudeAccountService{}
	srv := newClaudeAccountsTestServer(t, svc, nil)
	body, status, _ := doRequest(t, srv, "GET", "/api/v1/claude-accounts?refresh=1", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d body=%s", status, body)
	}
	var resp controllers.ListClaudeAccountsResponse
	mustJSON(t, body, &resp)
	if !svc.refreshed || len(resp.Accounts) != 2 {
		t.Fatalf("refreshed=%v resp=%+v", svc.refreshed, resp)
	}
	personal := resp.Accounts[1]
	if personal.Status.LoggedIn == nil || !*personal.Status.LoggedIn || personal.Status.SubscriptionType != "pro" || personal.SharedSetup["settings.json"] != "replaced" {
		t.Fatalf("personal = %+v", personal)
	}
	if resp.Accounts[0].Status.LoggedIn != nil {
		t.Fatalf("unknown status should be null: %+v", resp.Accounts[0].Status)
	}
}

func TestClaudeAccountsCreateAndErrors(t *testing.T) {
	svc := &fakeClaudeAccountService{}
	srv := newClaudeAccountsTestServer(t, svc, nil)
	body, status, _ := doRequest(t, srv, "POST", "/api/v1/claude-accounts", `{"label":"Personal"}`)
	if status != http.StatusCreated || svc.created != "Personal" {
		t.Fatalf("status = %d created=%q body=%s", status, svc.created, body)
	}

	cases := []struct {
		err    error
		status int
		code   string
	}{
		{domain.ErrClaudeAccountExists, http.StatusConflict, "CLAUDE_ACCOUNT_EXISTS"},
		{domain.ErrClaudeAccountLabelInvalid, http.StatusBadRequest, "CLAUDE_ACCOUNT_LABEL_INVALID"},
		{domain.ErrClaudeAccountFolderUnavailable, http.StatusConflict, "CLAUDE_ACCOUNT_FOLDER_UNAVAILABLE"},
	}
	for _, tc := range cases {
		svc.createErr = tc.err
		body, status, _ := doRequest(t, srv, "POST", "/api/v1/claude-accounts", `{"label":"X"}`)
		var env struct {
			Code string `json:"code"`
		}
		mustJSON(t, body, &env)
		if status != tc.status || env.Code != tc.code {
			t.Errorf("%v -> status %d code %q, want %d %q", tc.err, status, env.Code, tc.status, tc.code)
		}
	}
}

func TestClaudeAccountsDeleteErrors(t *testing.T) {
	cases := []struct {
		err    error
		status int
		code   string
	}{
		{nil, http.StatusNoContent, ""},
		{domain.ErrClaudeAccountInUse, http.StatusConflict, "CLAUDE_ACCOUNT_IN_USE"},
		{domain.ErrClaudeAccountDefaultImmutable, http.StatusConflict, "CLAUDE_ACCOUNT_DEFAULT_IMMUTABLE"},
		{domain.ErrClaudeAccountNotFound, http.StatusNotFound, "CLAUDE_ACCOUNT_NOT_FOUND"},
	}
	for _, tc := range cases {
		srv := newClaudeAccountsTestServer(t, &fakeClaudeAccountService{deleteErr: tc.err}, nil)
		body, status, _ := doRequest(t, srv, "DELETE", "/api/v1/claude-accounts/personal", "")
		if status != tc.status {
			t.Errorf("%v -> status %d body=%s", tc.err, status, body)
		}
		if tc.code != "" {
			var env struct {
				Code string `json:"code"`
			}
			mustJSON(t, body, &env)
			if env.Code != tc.code {
				t.Errorf("%v -> code %q", tc.err, env.Code)
			}
		}
	}
}

func TestClaudeAccountsLoginOpensTerminal(t *testing.T) {
	svc := &fakeClaudeAccountService{}
	terms := &fakeLoginTerminals{}
	srv := newClaudeAccountsTestServer(t, svc, terms)
	body, status, _ := doRequest(t, srv, "POST", "/api/v1/claude-accounts/personal/login", `{"cols":120,"rows":40}`)
	if status != http.StatusCreated {
		t.Fatalf("status = %d body=%s", status, body)
	}
	if svc.loginInput != "personal" || terms.got.Argv[0] != "/usr/local/bin/claude" || terms.got.Env[domain.ClaudeConfigDirEnv] != "/Users/u/.claude-personal" || terms.got.Cols != 120 {
		t.Fatalf("login input = %q terminal input = %+v", svc.loginInput, terms.got)
	}
	var env controllers.ShellTerminalEnvelope
	mustJSON(t, body, &env)
	if env.ShellTerminal.HandleID != "shellterm-abc" {
		t.Fatalf("envelope = %+v", env)
	}
}
```

If `ShellTerminalEnvelope`'s field isn't named `ShellTerminal`, use its actual field name (see `shell_terminals.go:96`).

Run: `cd backend && go test ./internal/httpd/controllers/ -run ClaudeAccounts`
Expected: FAIL (`undefined: controllers.ClaudeAccountService`).

- [ ] **Step 4: Implement DTOs and controller**

Append to `dto.go`:

```go
type ClaudeAccountIDParam struct {
	AccountID string `path:"accountId" description:"Claude account identifier."`
}

type ClaudeAccountStatus struct {
	LoggedIn         *bool      `json:"loggedIn"`
	SubscriptionType string     `json:"subscriptionType,omitempty"`
	ReportedEmail    string     `json:"reportedEmail,omitempty"`
	CheckedAt        *time.Time `json:"checkedAt,omitempty"`
}

type ClaudeAccountView struct {
	ID          domain.ClaudeAccountID `json:"id"`
	Label       string                 `json:"label"`
	ConfigDir   string                 `json:"configDir"`
	IsDefault   bool                   `json:"isDefault"`
	Status      ClaudeAccountStatus    `json:"status"`
	SharedSetup map[string]string      `json:"sharedSetup"`
}

type ListClaudeAccountsResponse struct {
	Accounts []ClaudeAccountView `json:"accounts"`
}

type ClaudeAccountEnvelope struct {
	Account ClaudeAccountView `json:"account"`
}

type CreateClaudeAccountRequest struct {
	Label string `json:"label" maxLength:"32"`
}

type RenameClaudeAccountRequest struct {
	Label string `json:"label" maxLength:"32"`
}

type ClaudeAccountLoginRequest struct {
	Cols int `json:"cols,omitempty" minimum:"1" maximum:"1000"`
	Rows int `json:"rows,omitempty" minimum:"1" maximum:"1000"`
}
```

`claude_accounts.go`:

```go
package controllers

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode/claudesetup"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	claudeaccountssvc "github.com/OmarAly92/operator/backend/internal/service/claudeaccounts"
	shelltermsvc "github.com/OmarAly92/operator/backend/internal/service/shellterm"
)

type ClaudeAccountService interface {
	List(ctx context.Context, refresh bool) ([]claudeaccountssvc.AccountView, error)
	Create(ctx context.Context, label string) (domain.ClaudeAccount, error)
	Rename(ctx context.Context, id domain.ClaudeAccountID, label string) (domain.ClaudeAccount, error)
	Delete(ctx context.Context, id domain.ClaudeAccountID) error
	Relink(ctx context.Context, id domain.ClaudeAccountID) (claudesetup.Report, error)
	Login(ctx context.Context, id domain.ClaudeAccountID) (claudeaccountssvc.LoginLaunch, error)
}

type ClaudeAccountsController struct {
	Svc       ClaudeAccountService
	Terminals ShellTerminalService
}

func (c *ClaudeAccountsController) Register(r chi.Router) {
	r.Get("/claude-accounts", c.list)
	r.Post("/claude-accounts", c.create)
	r.Patch("/claude-accounts/{accountId}", c.rename)
	r.Delete("/claude-accounts/{accountId}", c.remove)
	r.Post("/claude-accounts/{accountId}/login", c.login)
	r.Post("/claude-accounts/{accountId}/relink", c.relink)
}

func claudeAccountID(r *http.Request) domain.ClaudeAccountID {
	return domain.ClaudeAccountID(strings.TrimSpace(chi.URLParam(r, "accountId")))
}

func claudeAccountAPIError(err error) error {
	switch {
	case errors.Is(err, domain.ErrClaudeAccountExists):
		return apierr.Conflict("CLAUDE_ACCOUNT_EXISTS", "A Claude account with that name or folder already exists", nil)
	case errors.Is(err, domain.ErrClaudeAccountLabelInvalid):
		return apierr.Invalid("CLAUDE_ACCOUNT_LABEL_INVALID", "Account names need 1–32 characters including a letter or digit", nil)
	case errors.Is(err, domain.ErrClaudeAccountNotFound):
		return apierr.NotFound("CLAUDE_ACCOUNT_NOT_FOUND", "Unknown Claude account")
	case errors.Is(err, domain.ErrClaudeAccountDefaultImmutable):
		return apierr.Conflict("CLAUDE_ACCOUNT_DEFAULT_IMMUTABLE", "The default Claude account cannot be removed", nil)
	case errors.Is(err, domain.ErrClaudeAccountInUse):
		return apierr.Conflict("CLAUDE_ACCOUNT_IN_USE", "Sessions still use this account; remove or switch them first", nil)
	case errors.Is(err, domain.ErrClaudeAccountFolderUnavailable):
		return apierr.Conflict("CLAUDE_ACCOUNT_FOLDER_UNAVAILABLE", "The account folder is missing or cannot be created", nil)
	default:
		return err
	}
}

func claudeAccountView(view claudeaccountssvc.AccountView) ClaudeAccountView {
	status := ClaudeAccountStatus{
		LoggedIn:         view.Status.LoggedIn,
		SubscriptionType: view.Status.SubscriptionType,
		ReportedEmail:    view.Status.ReportedEmail,
	}
	if !view.Status.CheckedAt.IsZero() {
		checked := view.Status.CheckedAt
		status.CheckedAt = &checked
	}
	setup := make(map[string]string, len(view.SharedSetup))
	for name, state := range view.SharedSetup {
		setup[name] = string(state)
	}
	configDir := view.ConfigDir
	if configDir == "" {
		configDir = view.Account.ConfigDir
	}
	return ClaudeAccountView{
		ID:          view.Account.ID,
		Label:       view.Account.Label,
		ConfigDir:   configDir,
		IsDefault:   view.Account.IsDefault,
		Status:      status,
		SharedSetup: setup,
	}
}

func decodeOptionalJSON(r *http.Request, out any) error {
	err := json.NewDecoder(r.Body).Decode(out)
	if errors.Is(err, io.EOF) {
		return nil
	}
	return err
}

func (c *ClaudeAccountsController) list(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/claude-accounts")
		return
	}
	views, err := c.Svc.List(r.Context(), r.URL.Query().Get("refresh") == "1")
	if err != nil {
		envelope.WriteError(w, r, claudeAccountAPIError(err))
		return
	}
	out := make([]ClaudeAccountView, 0, len(views))
	for _, view := range views {
		out = append(out, claudeAccountView(view))
	}
	envelope.WriteJSON(w, http.StatusOK, ListClaudeAccountsResponse{Accounts: out})
}

func (c *ClaudeAccountsController) create(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/claude-accounts")
		return
	}
	var in CreateClaudeAccountRequest
	if err := decodeOptionalJSON(r, &in); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	account, err := c.Svc.Create(r.Context(), in.Label)
	if err != nil {
		envelope.WriteError(w, r, claudeAccountAPIError(err))
		return
	}
	envelope.WriteJSON(w, http.StatusCreated, ClaudeAccountEnvelope{Account: claudeAccountView(claudeaccountssvc.AccountView{Account: account})})
}

func (c *ClaudeAccountsController) rename(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "PATCH", "/api/v1/claude-accounts/{accountId}")
		return
	}
	var in RenameClaudeAccountRequest
	if err := decodeOptionalJSON(r, &in); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	account, err := c.Svc.Rename(r.Context(), claudeAccountID(r), in.Label)
	if err != nil {
		envelope.WriteError(w, r, claudeAccountAPIError(err))
		return
	}
	envelope.WriteJSON(w, http.StatusOK, ClaudeAccountEnvelope{Account: claudeAccountView(claudeaccountssvc.AccountView{Account: account})})
}

func (c *ClaudeAccountsController) remove(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "DELETE", "/api/v1/claude-accounts/{accountId}")
		return
	}
	if err := c.Svc.Delete(r.Context(), claudeAccountID(r)); err != nil {
		envelope.WriteError(w, r, claudeAccountAPIError(err))
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (c *ClaudeAccountsController) relink(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/claude-accounts/{accountId}/relink")
		return
	}
	if _, err := c.Svc.Relink(r.Context(), claudeAccountID(r)); err != nil {
		envelope.WriteError(w, r, claudeAccountAPIError(err))
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (c *ClaudeAccountsController) login(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil || c.Terminals == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/claude-accounts/{accountId}/login")
		return
	}
	var in ClaudeAccountLoginRequest
	if err := decodeOptionalJSON(r, &in); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	launch, err := c.Svc.Login(r.Context(), claudeAccountID(r))
	if err != nil {
		envelope.WriteError(w, r, claudeAccountAPIError(err))
		return
	}
	terminal, err := c.Terminals.OpenShellTerminal(r.Context(), shelltermsvc.OpenShellTerminalInput{
		Cols:  in.Cols,
		Rows:  in.Rows,
		Argv:  launch.Argv,
		Env:   launch.Env,
		Title: launch.Title,
	})
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusCreated, ShellTerminalEnvelope{ShellTerminal: shellTerminalResponse(terminal)})
}
```

**If a name collides:** if `decodeOptionalJSON` already exists in the package (`grep -n 'func decodeOptionalJSON' backend/internal/httpd/controllers/*.go`), delete this copy and use the existing one.

**Wiring:**
- **`api.go`:** add `ClaudeAccounts controllers.ClaudeAccountService` to `APIDeps`. Add a `claudeAccounts *controllers.ClaudeAccountsController` field to the API struct, set as `&controllers.ClaudeAccountsController{Svc: deps.ClaudeAccounts, Terminals: deps.ShellTerminals}`. In `Register`, add `a.claudeAccounts.Register(r)` after `a.settings.Register(r)`.
- **`daemon.go:379`:** add `ClaudeAccounts: claudeAccounts,`.

**`specgen/build.go`:**
- Add `schemaNames` entries using the same `"Controllers<Type>": "<Type>"` pattern for `ClaudeAccountView`, `ClaudeAccountStatus`, `ListClaudeAccountsResponse`, `ClaudeAccountEnvelope`, `CreateClaudeAccountRequest`, `RenameClaudeAccountRequest`, `ClaudeAccountLoginRequest`.
- Add near `:498`:

```go
type claudeAccountsListQuery struct {
	Refresh *int64 `query:"refresh,omitempty" minimum:"1" maximum:"1" description:"Set to 1 to bypass the 30-second login status cache."`
}
```

- Add operations after the shell-terminals block:

```go
		{
			method: http.MethodGet, path: "/api/v1/claude-accounts", id: "listClaudeAccounts", tag: "claudeAccounts",
			summary:    "List Claude accounts, default first, with login status and shared setup state",
			pathParams: []any{claudeAccountsListQuery{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ListClaudeAccountsResponse{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/claude-accounts", id: "createClaudeAccount", tag: "claudeAccounts",
			summary: "Add a Claude account folder at ~/.claude-<name> and link the shared setup",
			reqBody: controllers.CreateClaudeAccountRequest{},
			resps: []respUnit{
				{http.StatusCreated, controllers.ClaudeAccountEnvelope{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPatch, path: "/api/v1/claude-accounts/{accountId}", id: "renameClaudeAccount", tag: "claudeAccounts",
			summary:    "Rename a Claude account label; the folder never changes",
			pathParams: []any{controllers.ClaudeAccountIDParam{}},
			reqBody:    controllers.RenameClaudeAccountRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.ClaudeAccountEnvelope{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodDelete, path: "/api/v1/claude-accounts/{accountId}", id: "deleteClaudeAccount", tag: "claudeAccounts",
			summary:    "Unregister a Claude account; its folder stays on disk",
			pathParams: []any{controllers.ClaudeAccountIDParam{}},
			resps: []respUnit{
				{http.StatusNoContent, nil},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/claude-accounts/{accountId}/login", id: "loginClaudeAccount", tag: "claudeAccounts",
			summary:    "Open a terminal running Claude against the account folder for /login",
			pathParams: []any{controllers.ClaudeAccountIDParam{}},
			reqBody:    controllers.ClaudeAccountLoginRequest{},
			resps: []respUnit{
				{http.StatusCreated, controllers.ShellTerminalEnvelope{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/claude-accounts/{accountId}/relink", id: "relinkClaudeAccount", tag: "claudeAccounts",
			summary:    "Back up files that replaced shared setup links, then re-link them",
			pathParams: []any{controllers.ClaudeAccountIDParam{}},
			resps: []respUnit{
				{http.StatusNoContent, nil},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
```

**If spec generation rejects something:**
- A query struct placed in `pathParams`: check how `shellTerminalBlocksQuery` is attached (`:660`) and attach `claudeAccountsListQuery` the same way.
- A new tag: add `claudeAccounts` wherever tags are declared (`grep -n '"shellTerminals"' backend/internal/httpd/apispec/specgen/build.go`).

- [ ] **Step 5: Regenerate and run**

Run: `npm run api && cd backend && go build ./... && go test ./internal/httpd/... ./internal/service/shellterm/... ./internal/daemon/...`
Expected: PASS, including spec drift and route/spec parity.

- [ ] **Step 6: Commit**

```bash
git add backend frontend/src/api/schema.ts
git commit -m "feat(httpd): Claude accounts routes and login terminal" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 10: Desktop Settings — Claude accounts section

**Files:**
- Modify: `frontend/src/renderer/hooks/useShellTerminals.ts:31` (export `toShellTerminal`)
- Create: `frontend/src/renderer/hooks/useClaudeAccounts.ts`
- Create: `frontend/src/renderer/components/settings/ClaudeAccountsSection.tsx`
- Create: `frontend/src/renderer/components/settings/ClaudeAccountsSection.test.tsx`
- Modify: `frontend/src/renderer/components/GlobalSettingsForm.tsx:45` (mount the section after Preferences)
- Modify: all 8 `frontend/src/renderer/i18n/{en,de,es,fr,ja,ko,pt-BR,zh-CN}.json`

**Interfaces:**
- Consumes: `components["schemas"]["ClaudeAccountView"]` and `/api/v1/claude-accounts*` paths from the regenerated `frontend/src/api/schema.ts` (Task 9); `useUiStore` `closeSettings` and `setActiveShellTerminal` (`stores/ui-store.ts:94,110`); `paneGridBody` (`lib/pane-grid`).
- Produces (`hooks/useClaudeAccounts.ts`):
  - `type ClaudeAccount = components["schemas"]["ClaudeAccountView"]`
  - `claudeAccountsQueryKey`
  - `useClaudeAccounts()`
  - `useRefreshClaudeAccounts(): () => Promise<ClaudeAccount[]>`
  - `useCreateClaudeAccount()`
  - `useRenameClaudeAccount()`
  - `useDeleteClaudeAccount()`
  - `useRelinkClaudeAccount()`
  - `useClaudeAccountLogin()` — resolves to `ShellTerminal`
  - `claudeAccountPlanKey(account)`, returning `"max" | "pro" | "notLoggedIn" | "unknown" | "other"`
  - `claudeAccountSlug(label)`, matching Go `Slug`

- [ ] **Step 1: Add translations**

Add these keys to **each** of the 8 locale files, next to the other `settings.*` keys, with the English text in all 8:

```json
	"settings.claudeAccounts.title": "Claude accounts",
	"settings.claudeAccounts.default": "Default",
	"settings.claudeAccounts.add": "Add account",
	"settings.claudeAccounts.addTitle": "Add a Claude account",
	"settings.claudeAccounts.labelField": "Name",
	"settings.claudeAccounts.folderPreview": "Folder: {{path}}",
	"settings.claudeAccounts.create": "Create and log in",
	"settings.claudeAccounts.cancel": "Cancel",
	"settings.claudeAccounts.login": "Log in",
	"settings.claudeAccounts.loginAgain": "Log in again",
	"settings.claudeAccounts.rename": "Rename",
	"settings.claudeAccounts.save": "Save",
	"settings.claudeAccounts.remove": "Remove",
	"settings.claudeAccounts.removeTitle": "Remove {{label}}?",
	"settings.claudeAccounts.removeBody": "Operator forgets this account. The folder {{path}} and its login stay on disk.",
	"settings.claudeAccounts.plan.max": "Max",
	"settings.claudeAccounts.plan.pro": "Pro",
	"settings.claudeAccounts.plan.notLoggedIn": "Not logged in",
	"settings.claudeAccounts.plan.unknown": "Unknown",
	"settings.claudeAccounts.reportedEmail": "Reported by Claude: {{email}}",
	"settings.claudeAccounts.setupReplaced": "Setup no longer shared: {{items}}",
	"settings.claudeAccounts.relink": "Re-link",
	"settings.claudeAccounts.mcpNote": "MCP servers are copied from the default account before every launch; servers added from another account are replaced.",
	"settings.claudeAccounts.loadFailed": "Could not load Claude accounts.",
	"settings.claudeAccounts.agentWithAccount": "{{agent}} · {{account}}",
```

`agentWithAccount` is used in Task 11.

- [ ] **Step 2: Write the failing component test**

`ClaudeAccountsSection.test.tsx`:

```tsx
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, test, vi } from "vitest";

const h = vi.hoisted(() => ({
	accounts: [] as unknown[],
	create: vi.fn(),
	login: vi.fn(),
	remove: vi.fn(),
	relink: vi.fn(),
	rename: vi.fn(),
	refresh: vi.fn(),
	closeSettings: vi.fn(),
	setActiveShellTerminal: vi.fn(),
	navigate: vi.fn(),
}));

vi.mock("../../hooks/useClaudeAccounts", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useClaudeAccounts")>();
	return {
		...actual,
		useClaudeAccounts: () => ({ data: h.accounts, isPending: false, error: null }),
		useRefreshClaudeAccounts: () => h.refresh,
		useCreateClaudeAccount: () => ({ mutateAsync: h.create, isPending: false }),
		useClaudeAccountLogin: () => ({ mutateAsync: h.login, isPending: false }),
		useDeleteClaudeAccount: () => ({ mutateAsync: h.remove, isPending: false }),
		useRelinkClaudeAccount: () => ({ mutateAsync: h.relink, isPending: false }),
		useRenameClaudeAccount: () => ({ mutateAsync: h.rename, isPending: false }),
	};
});

vi.mock("../../stores/ui-store", () => ({
	useUiStore: (select: (state: unknown) => unknown) =>
		select({ closeSettings: h.closeSettings, setActiveShellTerminal: h.setActiveShellTerminal }),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => h.navigate }));

import { ClaudeAccountsSection } from "./ClaudeAccountsSection";

beforeEach(() => {
	for (const fn of [h.create, h.login, h.remove, h.relink, h.rename, h.refresh, h.closeSettings, h.setActiveShellTerminal, h.navigate]) {
		fn.mockReset();
	}
	h.accounts = [
		{ id: "default", label: "Default", configDir: "/Users/u/.claude", isDefault: true, status: { loggedIn: true, subscriptionType: "max" }, sharedSetup: {} },
		{
			id: "personal",
			label: "Personal",
			configDir: "/Users/u/.claude-personal",
			isDefault: false,
			status: { loggedIn: false },
			sharedSetup: { "settings.json": "replaced", "CLAUDE.md": "linked" },
		},
	];
});

test("lists default first with plan badges and no remove on default", () => {
	render(<ClaudeAccountsSection />);
	const defaultRow = screen.getByTestId("claude-account-default");
	expect(within(defaultRow).getByText("Max")).toBeInTheDocument();
	expect(within(defaultRow).queryByRole("button", { name: "Remove" })).toBeNull();
	const personal = screen.getByTestId("claude-account-personal");
	expect(within(personal).getByText("Not logged in")).toBeInTheDocument();
	expect(within(personal).getByText("/Users/u/.claude-personal")).toBeInTheDocument();
	expect(within(personal).getByText("Setup no longer shared: settings.json")).toBeInTheDocument();
});

test("re-link calls the mutation", async () => {
	h.relink.mockResolvedValue(undefined);
	render(<ClaudeAccountsSection />);
	await userEvent.click(within(screen.getByTestId("claude-account-personal")).getByRole("button", { name: "Re-link" }));
	expect(h.relink).toHaveBeenCalledWith("personal");
});

test("add dialog previews the folder, creates, then opens the login terminal", async () => {
	h.create.mockResolvedValue({ id: "work-2", label: "Work 2" });
	h.login.mockResolvedValue({ handleId: "shellterm-1" });
	render(<ClaudeAccountsSection />);
	await userEvent.click(screen.getByRole("button", { name: "Add account" }));
	await userEvent.type(screen.getByLabelText("Name"), "Work 2");
	expect(screen.getByText("Folder: ~/.claude-work-2")).toBeInTheDocument();
	await userEvent.click(screen.getByRole("button", { name: "Create and log in" }));
	expect(h.create).toHaveBeenCalledWith("Work 2");
	expect(h.login).toHaveBeenCalledWith("work-2");
	expect(h.closeSettings).toHaveBeenCalled();
	expect(h.setActiveShellTerminal).toHaveBeenCalledWith("shellterm-1");
	expect(h.navigate).toHaveBeenCalledWith({ to: "/terminals" });
});

test("remove asks for confirmation and shows the in-use error", async () => {
	h.remove.mockRejectedValue({ code: "CLAUDE_ACCOUNT_IN_USE", message: "Sessions still use this account; remove or switch them first" });
	render(<ClaudeAccountsSection />);
	await userEvent.click(within(screen.getByTestId("claude-account-personal")).getByRole("button", { name: "Remove" }));
	await userEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Remove" }));
	expect(h.remove).toHaveBeenCalledWith("personal");
	expect(await screen.findByText("Sessions still use this account; remove or switch them first")).toBeInTheDocument();
});
```

**If i18n isn't initialised under vitest:** the text assertions assume the test setup loads `en.json`, as `ConnectMobileGetApp.test.tsx` relies on. If it isn't, check `frontend/vitest.config.*` / the setup file and match what that test does.

Run: `cd frontend && npx vitest run src/renderer/components/settings/ClaudeAccountsSection.test.tsx`
Expected: FAIL (cannot resolve `./ClaudeAccountsSection`).

- [ ] **Step 3: Implement the hook**

In `useShellTerminals.ts`, change `function toShellTerminal(` to `export function toShellTerminal(`.

`useClaudeAccounts.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { components } from "../../api/schema";
import { apiClient, hasTrustedApiBaseUrl } from "../lib/api-client";
import { paneGridBody } from "../lib/pane-grid";
import { shellTerminalsQueryKey, toShellTerminal, type ShellTerminal } from "./useShellTerminals";

export type ClaudeAccount = components["schemas"]["ClaudeAccountView"];

export const claudeAccountsQueryKey = ["claude-accounts"] as const;

async function fetchClaudeAccounts(refresh: boolean): Promise<ClaudeAccount[]> {
	if (!hasTrustedApiBaseUrl()) return [];
	const { data, error } = await apiClient.GET("/api/v1/claude-accounts", {
		params: { query: refresh ? { refresh: 1 } : {} },
	});
	if (error) throw error;
	return data?.accounts ?? [];
}

export function claudeAccountSlug(label: string): string {
	return label
		.trim()
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-+|-+$/g, "");
}

export function claudeAccountPlanKey(account: ClaudeAccount): "max" | "pro" | "notLoggedIn" | "unknown" | "other" {
	const loggedIn = account.status?.loggedIn;
	if (loggedIn === false) return "notLoggedIn";
	if (loggedIn !== true) return "unknown";
	const plan = account.status?.subscriptionType ?? "";
	if (plan === "max" || plan === "pro") return plan;
	return plan ? "other" : "unknown";
}

export function useClaudeAccounts() {
	return useQuery({
		queryKey: claudeAccountsQueryKey,
		queryFn: () => fetchClaudeAccounts(false),
		retry: 1,
		refetchOnWindowFocus: true,
	});
}

export function useRefreshClaudeAccounts() {
	const queryClient = useQueryClient();
	return () =>
		queryClient.fetchQuery({ queryKey: claudeAccountsQueryKey, queryFn: () => fetchClaudeAccounts(true), staleTime: 0 });
}

function useInvalidatingMutation<TInput, TOutput>(fn: (input: TInput) => Promise<TOutput>) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: fn,
		onSettled: () => {
			void queryClient.invalidateQueries({ queryKey: claudeAccountsQueryKey });
		},
	});
}

export function useCreateClaudeAccount() {
	return useInvalidatingMutation(async (label: string) => {
		const { data, error } = await apiClient.POST("/api/v1/claude-accounts", { body: { label } });
		if (error) throw error;
		if (!data) throw new Error("Daemon returned no account");
		return data.account;
	});
}

export function useRenameClaudeAccount() {
	return useInvalidatingMutation(async ({ id, label }: { id: string; label: string }) => {
		const { data, error } = await apiClient.PATCH("/api/v1/claude-accounts/{accountId}", {
			params: { path: { accountId: id } },
			body: { label },
		});
		if (error) throw error;
		return data?.account;
	});
}

export function useDeleteClaudeAccount() {
	return useInvalidatingMutation(async (id: string) => {
		const { error } = await apiClient.DELETE("/api/v1/claude-accounts/{accountId}", {
			params: { path: { accountId: id } },
		});
		if (error) throw error;
	});
}

export function useRelinkClaudeAccount() {
	return useInvalidatingMutation(async (id: string) => {
		const { error } = await apiClient.POST("/api/v1/claude-accounts/{accountId}/relink", {
			params: { path: { accountId: id } },
		});
		if (error) throw error;
	});
}

export function useClaudeAccountLogin() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: async (id: string): Promise<ShellTerminal> => {
			const { data, error } = await apiClient.POST("/api/v1/claude-accounts/{accountId}/login", {
				params: { path: { accountId: id } },
				body: { ...paneGridBody() },
			});
			if (error) throw error;
			if (!data) throw new Error("Daemon returned no terminal");
			return toShellTerminal(data.shellTerminal);
		},
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: shellTerminalsQueryKey });
			void queryClient.invalidateQueries({ queryKey: claudeAccountsQueryKey });
		},
	});
}
```

- [ ] **Step 4: Implement the section**

`ClaudeAccountsSection.tsx`:

```tsx
import { useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	claudeAccountPlanKey,
	claudeAccountSlug,
	type ClaudeAccount,
	useClaudeAccountLogin,
	useClaudeAccounts,
	useCreateClaudeAccount,
	useDeleteClaudeAccount,
	useRelinkClaudeAccount,
	useRenameClaudeAccount,
} from "../../hooks/useClaudeAccounts";
import { apiErrorMessage } from "../../lib/api-client";
import { useUiStore } from "../../stores/ui-store";
import { Button } from "../ui/button";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogTitle,
	settingsDialogBodyClass,
	settingsDialogContentClass,
	settingsDialogFooterClass,
	settingsDialogHeaderClass,
} from "../ui/dialog";
import { Input } from "../ui/input";
import { SettingsSection } from "./SettingsSection";

const PLAN_KEYS = {
	max: "settings.claudeAccounts.plan.max",
	pro: "settings.claudeAccounts.plan.pro",
	notLoggedIn: "settings.claudeAccounts.plan.notLoggedIn",
	unknown: "settings.claudeAccounts.plan.unknown",
} as const;

function errorText(error: unknown): string {
	if (error && typeof error === "object" && "message" in error && typeof error.message === "string") {
		return error.message;
	}
	return apiErrorMessage(error);
}

export function ClaudeAccountsSection({ titleHidden }: { titleHidden?: boolean }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const closeSettings = useUiStore((state) => state.closeSettings);
	const setActiveShellTerminal = useUiStore((state) => state.setActiveShellTerminal);
	const accountsQuery = useClaudeAccounts();
	const createAccount = useCreateClaudeAccount();
	const login = useClaudeAccountLogin();
	const removeAccount = useDeleteClaudeAccount();
	const relink = useRelinkClaudeAccount();
	const rename = useRenameClaudeAccount();
	const [adding, setAdding] = useState(false);
	const [label, setLabel] = useState("");
	const [pendingRemove, setPendingRemove] = useState<ClaudeAccount | null>(null);
	const [renaming, setRenaming] = useState<{ id: string; label: string } | null>(null);
	const [error, setError] = useState<string | null>(null);

	const openLogin = async (id: string) => {
		setError(null);
		try {
			const shell = await login.mutateAsync(id);
			closeSettings();
			setActiveShellTerminal(shell.handleId);
			void navigate({ to: "/terminals" });
		} catch (err) {
			setError(errorText(err));
		}
	};

	const submitAdd = async () => {
		setError(null);
		try {
			const account = await createAccount.mutateAsync(label);
			setAdding(false);
			setLabel("");
			await openLogin(account.id);
		} catch (err) {
			setError(errorText(err));
		}
	};

	const confirmRemove = async () => {
		if (!pendingRemove) return;
		setError(null);
		try {
			await removeAccount.mutateAsync(pendingRemove.id);
			setPendingRemove(null);
		} catch (err) {
			setPendingRemove(null);
			setError(errorText(err));
		}
	};

	const submitRename = async () => {
		if (!renaming) return;
		setError(null);
		try {
			await rename.mutateAsync(renaming);
			setRenaming(null);
		} catch (err) {
			setError(errorText(err));
		}
	};

	const accounts = accountsQuery.data ?? [];
	const slug = claudeAccountSlug(label);

	return (
		<SettingsSection title={t("settings.claudeAccounts.title")} titleHidden={titleHidden} sectionId="claude-accounts">
			{accountsQuery.error ? <p className="px-3 text-caption text-destructive">{t("settings.claudeAccounts.loadFailed")}</p> : null}
			{accounts.map((account) => {
				const planKey = claudeAccountPlanKey(account);
				const planLabel = planKey === "other" ? (account.status?.subscriptionType ?? "") : t(PLAN_KEYS[planKey]);
				const replaced = Object.entries(account.sharedSetup ?? {})
					.filter(([, state]) => state === "replaced")
					.map(([name]) => name)
					.sort();
				const isRenaming = renaming?.id === account.id;
				return (
					<div key={account.id} data-testid={`claude-account-${account.id}`} className="settings-row-bar flex-col items-stretch gap-1.5">
						<div className="flex min-w-0 items-center gap-2">
							{isRenaming ? (
								<Input
									aria-label={t("settings.claudeAccounts.labelField")}
									value={renaming.label}
									onChange={(event) => setRenaming({ id: account.id, label: event.target.value })}
									className="max-w-48"
								/>
							) : (
								<span className="truncate text-sm text-settings-label">{account.label}</span>
							)}
							{account.isDefault ? (
								<span className="rounded px-1.5 text-micro text-settings-muted ring-1 ring-border">{t("settings.claudeAccounts.default")}</span>
							) : null}
							<span className="rounded px-1.5 text-micro text-settings-muted ring-1 ring-border">{planLabel}</span>
							<div className="ml-auto flex shrink-0 items-center gap-1.5">
								<Button type="button" onClick={() => void openLogin(account.id)} disabled={login.isPending}>
									{account.status?.loggedIn ? t("settings.claudeAccounts.loginAgain") : t("settings.claudeAccounts.login")}
								</Button>
								{!account.isDefault && !isRenaming ? (
									<Button type="button" onClick={() => setRenaming({ id: account.id, label: account.label })}>
										{t("settings.claudeAccounts.rename")}
									</Button>
								) : null}
								{isRenaming ? (
									<Button type="button" onClick={() => void submitRename()} disabled={rename.isPending}>
										{t("settings.claudeAccounts.save")}
									</Button>
								) : null}
								{!account.isDefault ? (
									<Button type="button" onClick={() => setPendingRemove(account)}>
										{t("settings.claudeAccounts.remove")}
									</Button>
								) : null}
							</div>
						</div>
						<span className="truncate font-mono text-md-sm text-settings-muted">{account.configDir}</span>
						{account.status?.reportedEmail ? (
							<span className="truncate text-caption text-settings-muted">
								{t("settings.claudeAccounts.reportedEmail", { email: account.status.reportedEmail })}
							</span>
						) : null}
						{replaced.length > 0 ? (
							<div className="flex items-center gap-2 text-caption text-warning">
								<span>{t("settings.claudeAccounts.setupReplaced", { items: replaced.join(", ") })}</span>
								<Button type="button" onClick={() => void relink.mutateAsync(account.id).catch((err) => setError(errorText(err)))}>
									{t("settings.claudeAccounts.relink")}
								</Button>
							</div>
						) : null}
					</div>
				);
			})}
			{error ? <p className="px-3 text-caption text-destructive">{error}</p> : null}
			<p className="px-3 text-caption text-settings-muted">{t("settings.claudeAccounts.mcpNote")}</p>
			<div className="px-3">
				<Button type="button" onClick={() => setAdding(true)}>
					{t("settings.claudeAccounts.add")}
				</Button>
			</div>

			<Dialog open={adding} onOpenChange={setAdding}>
				<DialogContent className={settingsDialogContentClass}>
					<form
						className="contents"
						onSubmit={(event) => {
							event.preventDefault();
							void submitAdd();
						}}
					>
						<div className={settingsDialogHeaderClass}>
							<DialogTitle>{t("settings.claudeAccounts.addTitle")}</DialogTitle>
							<DialogDescription>{slug ? t("settings.claudeAccounts.folderPreview", { path: `~/.claude-${slug}` }) : null}</DialogDescription>
						</div>
						<div className={settingsDialogBodyClass}>
							<label className="settings-field-label" htmlFor="claude-account-label">
								{t("settings.claudeAccounts.labelField")}
							</label>
							<Input id="claude-account-label" value={label} maxLength={32} onChange={(event) => setLabel(event.target.value)} autoFocus />
						</div>
						<div className={settingsDialogFooterClass}>
							<Button type="button" onClick={() => setAdding(false)}>
								{t("settings.claudeAccounts.cancel")}
							</Button>
							<Button type="submit" disabled={!slug || createAccount.isPending}>
								{t("settings.claudeAccounts.create")}
							</Button>
						</div>
					</form>
				</DialogContent>
			</Dialog>

			<Dialog open={pendingRemove !== null} onOpenChange={(open) => !open && setPendingRemove(null)}>
				<DialogContent className={settingsDialogContentClass}>
					<div className={settingsDialogHeaderClass}>
						<DialogTitle>{t("settings.claudeAccounts.removeTitle", { label: pendingRemove?.label ?? "" })}</DialogTitle>
						<DialogDescription>{t("settings.claudeAccounts.removeBody", { path: pendingRemove?.configDir ?? "" })}</DialogDescription>
					</div>
					<div className={settingsDialogFooterClass}>
						<Button type="button" onClick={() => setPendingRemove(null)}>
							{t("settings.claudeAccounts.cancel")}
						</Button>
						<Button type="button" onClick={() => void confirmRemove()} disabled={removeAccount.isPending}>
							{t("settings.claudeAccounts.remove")}
						</Button>
					</div>
				</DialogContent>
			</Dialog>
		</SettingsSection>
	);
}
```

**Styling:**
- Give the row action buttons and the footer "Cancel" the quieter variant from `button.tsx:13-24` (the non-primary one used by other settings rows). Keep "Create and log in" and the confirm "Remove" on the default primary variant.
- `text-warning`, `text-destructive`, `text-micro`, `text-caption` and `text-md-sm` are tokens already used in `TaskComposer.tsx` and `SwitchAgentDialog.tsx`. If lint or the design check rejects one, use the equivalent from `DESIGN.md`.

**`GlobalSettingsForm.tsx`:** inside the `section === "all" || section === "general"` fragment, add `<ClaudeAccountsSection titleHidden={leadingTitleHidden} />` after the Preferences `SettingsSection`, and import it.

- [ ] **Step 5: Run tests and checks**

Run: `cd frontend && npx vitest run src/renderer/components/settings/ClaudeAccountsSection.test.tsx src/renderer/i18n && cd .. && npm run frontend:typecheck && npm run frontend:lint`
Expected: PASS. If `renderer-coverage.test.ts` flags a literal, move that text into a translation key.

- [ ] **Step 6: Commit**

```bash
git add frontend
git commit -m "feat(renderer): Claude accounts section in Settings" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 11: Desktop composer, switch dialog and session labels

**Files:**
- Create: `frontend/src/renderer/components/ClaudeAccountSelect.tsx`
- Create: `frontend/src/renderer/components/ClaudeAccountSelect.test.tsx`
- Modify: `frontend/src/renderer/components/TaskComposer.tsx`:
  - `CreateTaskInput` `:36-43`
  - `createTask` body `:92-100`
  - agent state and `onChange` `:333-353`
  - toolbar slots
  - `submitTask` `:199-208`
- Modify: `frontend/src/renderer/components/TaskComposer.test.tsx` (add two tests)
- Modify: `frontend/src/renderer/hooks/useSwitchAgent.ts:10-15` (`SwitchAgentInput`), `:83-90` (request body)
- Modify: `frontend/src/renderer/components/SwitchAgentDialog.tsx`:
  - default target `:87-88`
  - target `Select` `onValueChange` `:204-208`
  - option `disabled`/`current` `:219-231`
  - account field after the target field `:252`
  - `submit` `:111-120`
  - description `:156`
- Create: `frontend/src/renderer/components/SwitchAgentDialog.accounts.test.tsx`
- Modify: `frontend/src/renderer/types/workspace.ts:124-135` (`WorkspaceSession.claudeAccountId`)
- Modify: `frontend/src/renderer/hooks/useWorkspaceQuery.ts:91` (map `claudeAccountId`)
- Modify: `frontend/src/renderer/components/SessionAgentTabMenu.tsx:29`
- Modify: all 8 locale files (keys below)

**Interfaces:**
- Consumes: `useClaudeAccounts`, `claudeAccountPlanKey`, `type ClaudeAccount` (Task 10); `DelegateTaskRequest.claudeAccountId` and `SwitchAgentRequest.targetClaudeAccountId` in `schema.ts` (Tasks 6, 7, 9).
- Produces:
  - `ClaudeAccountSelect({ id, value, onChange, accounts, triggerClassName, ariaLabel })`
  - `useClaudeAccountAgentLabel(session: { provider: string; claudeAccountId?: string }, agentName: string): string`
  - `SwitchAgentInput.targetClaudeAccountId?: string`
  - `WorkspaceSession.claudeAccountId?: string`

- [ ] **Step 1: Add translations**

Add to all 8 locale files, with English text in each:

```json
	"newTask.account": "Account",
	"switchAgent.accountLabel": "Claude account",
	"claudeAccounts.planSuffix": "{{label}} · {{plan}}",
```

- [ ] **Step 2: Write failing tests**

`ClaudeAccountSelect.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, test, vi } from "vitest";
import { ClaudeAccountSelect } from "./ClaudeAccountSelect";

const accounts = [
	{ id: "default", label: "Default", configDir: "/Users/u/.claude", isDefault: true, status: { loggedIn: true, subscriptionType: "max" }, sharedSetup: {} },
	{ id: "personal", label: "Personal", configDir: "/Users/u/.claude-personal", isDefault: false, status: { loggedIn: false }, sharedSetup: {} },
];

test("shows each account with its plan and reports the chosen id", async () => {
	const onChange = vi.fn();
	render(<ClaudeAccountSelect id="acct" ariaLabel="Account" value="default" onChange={onChange} accounts={accounts} />);
	await userEvent.click(screen.getByRole("combobox", { name: "Account" }));
	expect(await screen.findByRole("option", { name: "Personal · Not logged in" })).toBeInTheDocument();
	await userEvent.click(screen.getByRole("option", { name: "Personal · Not logged in" }));
	expect(onChange).toHaveBeenCalledWith("personal");
});
```

Radix Select under jsdom: if `userEvent.click` on the trigger doesn't open it, copy the pointer-event workaround already used by an existing Select test (`grep -rln 'SelectTrigger\|role("combobox"' frontend/src/renderer --include='*.test.tsx' | head -3`).

Append to `TaskComposer.test.tsx`, inside `describe("TaskComposer", ...)`:

```tsx
	it("hides the account chip for non-Claude agents", async () => {
		renderComposer();
		expect(await screen.findByRole("group", { name: "Runs with" })).toBeInTheDocument();
		expect(screen.queryByRole("combobox", { name: "Account" })).toBeNull();
	});

	it("sends the chosen Claude account with the delegate request", async () => {
		const onCreated = vi.fn();
		h.get.mockImplementation(async (path: string) => {
			if (path === "/api/v1/claude-accounts") {
				return {
					data: {
						accounts: [
							{ id: "default", label: "Default", configDir: "/Users/u/.claude", isDefault: true, status: { loggedIn: true, subscriptionType: "max" }, sharedSetup: {} },
							{ id: "personal", label: "Personal", configDir: "/Users/u/.claude-personal", isDefault: false, status: { loggedIn: true, subscriptionType: "pro" }, sharedSetup: {} },
						],
					},
				};
			}
			if (path.includes("/models")) {
				return { data: { agent: "claude-code", selectionMode: "text", models: [], allowCustom: true, refreshRecommended: false } };
			}
			return { data: { status: "ok", project: { kind: "single_repo", agent: "claude-code", config: {} } } };
		});
		h.post.mockResolvedValueOnce({ data: { workerId: "sess-acct" } });
		render(
			<Wrap>
				<TaskComposer projectId="proj-1" onCreated={onCreated} />
			</Wrap>,
		);
		const accountSelect = await screen.findByRole("combobox", { name: "Account" });
		await userEvent.click(accountSelect);
		await userEvent.click(await screen.findByRole("option", { name: "Personal · Pro" }));
		fireEvent.click(await screen.findByRole("button", { name: "Start task" }));
		await waitFor(() =>
			expect(h.post).toHaveBeenCalledWith(
				"/api/v1/orchestrators/delegate",
				expect.objectContaining({ body: expect.objectContaining({ agent: "claude-code", claudeAccountId: "personal" }) }),
			),
		);
	});
```

**Adjust to the actual agent default.** The mocked `RequiredAgentField` renders the value the composer resolved, so the project's `agent: "claude-code"` is expected to preselect Claude Code. If this composer derives its default from `projectQuery.data.config.worker.agentConfig` instead, put `agent: "claude-code"` where `TaskComposer.tsx:137-150` reads it.

`SwitchAgentDialog.accounts.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, test, vi } from "vitest";

const h = vi.hoisted(() => ({ mutate: vi.fn() }));

vi.mock("../hooks/useClaudeAccounts", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../hooks/useClaudeAccounts")>();
	return {
		...actual,
		useClaudeAccounts: () => ({
			data: [
				{ id: "default", label: "Default", configDir: "/Users/u/.claude", isDefault: true, status: { loggedIn: true, subscriptionType: "max" }, sharedSetup: {} },
				{ id: "personal", label: "Personal", configDir: "/Users/u/.claude-personal", isDefault: false, status: { loggedIn: true, subscriptionType: "pro" }, sharedSetup: {} },
			],
		}),
	};
});

vi.mock("../hooks/useSwitchAgent", () => ({
	createSwitchAgentIdempotencyKey: () => "key-1",
	clearSwitchAgentState: vi.fn(),
	useSwitchAgent: () => ({ mutate: h.mutate }),
	useSwitchAgentState: () => ({ isPending: false, input: undefined, error: null }),
}));

vi.mock("../hooks/useAgentSwitches", () => ({
	findActiveAgentSwitch: () => undefined,
	findRecoveryRequiredAgentSwitch: () => undefined,
	isTerminalAgentSwitch: () => false,
	useAgentSwitches: () => ({ data: [], isPending: false, error: null }),
}));

vi.mock("@tanstack/react-query", async (importOriginal) => {
	const actual = await importOriginal<typeof import("@tanstack/react-query")>();
	return { ...actual, useQueryClient: () => ({}) };
});

import { SwitchAgentDialog } from "./SwitchAgentDialog";

const session = {
	id: "s-1",
	workspaceId: "p",
	workspaceName: "P",
	title: "t",
	provider: "claude-code",
	claudeAccountId: "default",
	status: "working",
	updatedAt: "2026-09-14T00:00:00Z",
} as never;

beforeEach(() => h.mutate.mockReset());

test("a Claude session defaults to Claude on its other account", async () => {
	render(<SwitchAgentDialog open session={session} onOpenChange={vi.fn()} />);
	expect(screen.getByRole("combobox", { name: "Claude account" })).toBeInTheDocument();
	await userEvent.click(screen.getByRole("button", { name: /Switch/ }));
	expect(h.mutate).toHaveBeenCalledWith(
		expect.objectContaining({ targetHarness: "claude-code", targetClaudeAccountId: "personal" }),
	);
});
```

Match the confirm button's accessible name to `switchAgent.confirm` in `en.json` if it doesn't contain "Switch".

Run: `cd frontend && npx vitest run src/renderer/components/ClaudeAccountSelect.test.tsx src/renderer/components/TaskComposer.test.tsx src/renderer/components/SwitchAgentDialog.accounts.test.tsx`
Expected: FAIL.

- [ ] **Step 3: Implement the shared select**

`ClaudeAccountSelect.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { claudeAccountPlanKey, type ClaudeAccount } from "../hooks/useClaudeAccounts";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "./ui/select";

const PLAN_KEYS = {
	max: "settings.claudeAccounts.plan.max",
	pro: "settings.claudeAccounts.plan.pro",
	notLoggedIn: "settings.claudeAccounts.plan.notLoggedIn",
	unknown: "settings.claudeAccounts.plan.unknown",
} as const;

export function ClaudeAccountSelect({
	id,
	value,
	onChange,
	accounts,
	triggerClassName,
	ariaLabel,
	excludeId,
}: {
	id: string;
	value: string;
	onChange: (id: string) => void;
	accounts: ClaudeAccount[];
	triggerClassName?: string;
	ariaLabel: string;
	excludeId?: string;
}) {
	const { t } = useTranslation();
	const optionLabel = (account: ClaudeAccount) => {
		const key = claudeAccountPlanKey(account);
		const plan = key === "other" ? (account.status?.subscriptionType ?? "") : t(PLAN_KEYS[key]);
		return t("claudeAccounts.planSuffix", { label: account.label, plan });
	};
	return (
		<Select value={value} onValueChange={onChange}>
			<SelectTrigger id={id} aria-label={ariaLabel} className={triggerClassName}>
				<SelectValue />
			</SelectTrigger>
			<SelectContent align="start" position="popper">
				{accounts
					.filter((account) => account.id !== excludeId)
					.map((account) => (
						<SelectItem key={account.id} value={account.id}>
							{optionLabel(account)}
						</SelectItem>
					))}
			</SelectContent>
		</Select>
	);
}

export function useClaudeAccountAgentLabel(session: { provider: string; claudeAccountId?: string }, agentName: string): string {
	const { t } = useTranslation();
	const accounts = useClaudeAccountsSafe();
	if (session.provider !== "claude-code" || !session.claudeAccountId || session.claudeAccountId === "default") return agentName;
	const account = accounts.find((entry) => entry.id === session.claudeAccountId);
	return account ? t("settings.claudeAccounts.agentWithAccount", { agent: agentName, account: account.label }) : agentName;
}

function useClaudeAccountsSafe(): ClaudeAccount[] {
	return useClaudeAccounts().data ?? [];
}
```

Add `useClaudeAccounts` to the import from `../hooks/useClaudeAccounts`.

- [ ] **Step 4: Wire the composer**

In `TaskComposer.tsx`:
- Add `claudeAccountId?: string` to `CreateTaskInput`.
- In `createTask`'s body, add `claudeAccountId: input.claudeAccountId,` after `workspaceMode`.
- State next to `model`: `const [claudeAccount, setClaudeAccount] = useState("default");`, `const claudeAccountSelectId = useId();`, `const claudeAccountsQuery = useClaudeAccounts();`.
- In the agent `onChange` (`:345`), add `setClaudeAccount("default");`.
- In `submitTask`'s `createTask({...})`, add `claudeAccountId: selectedAgent === "claude-code" ? claudeAccount : undefined,`.
- In the toolbar, after the model slot's closing `</div>`, add:

```tsx
					{selectedAgent === "claude-code" && (claudeAccountsQuery.data?.length ?? 0) > 1 ? (
						<>
							<span className="composer-toolbar-divider" aria-hidden="true" />
							<div className="composer-toolbar-slot">
								<ClaudeAccountSelect
									id={claudeAccountSelectId}
									ariaLabel={t("newTask.account")}
									value={claudeAccount}
									onChange={setClaudeAccount}
									accounts={claudeAccountsQuery.data ?? []}
									triggerClassName="composer-toolbar-option w-full justify-between"
								/>
							</div>
						</>
					) : null}
```

The chip appears only when more than one account exists, so users with a single account see no change, and the existing "two stable toolbar tracks" test still holds.

- [ ] **Step 5: Wire switching**

`useSwitchAgent.ts`:
- Add `targetClaudeAccountId?: string;` to `SwitchAgentInput`.
- In `mutationFn`, destructure it, widen `body`'s type with `targetClaudeAccountId?: string;`, and set `if (targetClaudeAccountId) body.targetClaudeAccountId = targetClaudeAccountId;` after the note.

`SwitchAgentDialog.tsx`:
- Import `useClaudeAccounts` and `ClaudeAccountSelect`.
- Replace `:87-88` with:

```tsx
	const claudeAccounts = useClaudeAccounts().data ?? [];
	const currentAccountId = session.claudeAccountId ?? "default";
	const otherAccount = claudeAccounts.find((account) => account.id !== currentAccountId);
	const sessionOnClaude = session.provider === "claude-code";
	const defaultTargetHarness: SwitchAgentHarness = sessionOnClaude && !otherAccount ? "codex" : "claude-code";
	const [targetHarness, setTargetHarness] = useState<SwitchAgentHarness>(defaultTargetHarness);
	const [targetAccountId, setTargetAccountId] = useState<string>(sessionOnClaude ? (otherAccount?.id ?? currentAccountId) : currentAccountId);
	const accountId = useId();
	const accountMatchesCurrent = sessionOnClaude && targetHarness === "claude-code" && targetAccountId === currentAccountId;
```

  Accounts load asynchronously, so also add:

```tsx
	useEffect(() => {
		if (sessionOnClaude && targetAccountId === currentAccountId && otherAccount) {
			setTargetHarness("claude-code");
			setTargetAccountId(otherAccount.id);
		}
	}, [sessionOnClaude, targetAccountId, currentAccountId, otherAccount]);
```

  and add `useEffect` to the React import.
- Target `onValueChange` (`:205`): replace `if (!canSwitchAgentHarness(value) || value === session.provider) return;` with `if (!canSwitchAgentHarness(value)) return;`.
- In the option map, change `const current = option.value === session.provider;` to `const current = option.value === session.provider && !(option.value === "claude-code" && claudeAccounts.length > 1);`.
- After the target field's closing `</div>` (before the note field), add:

```tsx
								{targetHarness === "claude-code" && claudeAccounts.length > 1 ? (
									<div className="flex flex-col gap-1.5">
										<label className="settings-field-label" htmlFor={accountId}>
											{t("switchAgent.accountLabel")}
										</label>
										<ClaudeAccountSelect
											id={accountId}
											ariaLabel={t("switchAgent.accountLabel")}
											value={targetAccountId}
											onChange={(value) => {
												clearFailedAttempt();
												setTargetAccountId(value);
											}}
											accounts={claudeAccounts}
											excludeId={sessionOnClaude ? currentAccountId : undefined}
											triggerClassName="settings-field-control w-full"
										/>
									</div>
								) : null}
```

- In `submit`, return early when `accountMatchesCurrent`, and pass `targetClaudeAccountId: targetHarness === "claude-code" ? targetAccountId : undefined` in `switchAgent.mutate({...})`.
- Render the submit button only when `!switchBlocked && !accountMatchesCurrent`.
- Description `:156`: replace `agentLabel(session.provider)` with `currentAgentLabel`, where `const currentAgentLabel = useClaudeAccountAgentLabel(session, agentLabel(session.provider));` is declared with the other hooks.

- [ ] **Step 6: Session labels**

- `types/workspace.ts` `WorkspaceSession`: add `claudeAccountId?: string;` after `provider`.
- `useWorkspaceQuery.ts:91`: add `claudeAccountId: session.claudeAccountId,` after `provider`.
- `SessionAgentTabMenu.tsx:29`: replace `const agent = agentLabel(session.provider);` with `const agent = useClaudeAccountAgentLabel(session, agentLabel(session.provider));`, importing it from `./ClaudeAccountSelect`.

- [ ] **Step 7: Run tests and checks**

Run: `cd frontend && npx vitest run src/renderer/components/ClaudeAccountSelect.test.tsx src/renderer/components/TaskComposer.test.tsx src/renderer/components/SwitchAgentDialog.accounts.test.tsx src/renderer/components/settings src/renderer/i18n && cd .. && npm run frontend:typecheck && npm run frontend:lint`
Expected: PASS. Then run the full renderer suite once, `cd frontend && npx vitest run`, to catch anything using `WorkspaceSession` fixtures or `useSwitchAgent` mocks. Add `claudeAccountId` to fixtures only where a type error demands it.

- [ ] **Step 8: Commit**

```bash
git add frontend
git commit -m "feat(renderer): pick and switch Claude account for sessions" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 12: Mobile — account on spawn

All paths below are relative to `packages/mobile/`.

**Files:**
- Modify: `lib/core/api/api_request_helpers/end_points.dart:8` (add `claudeAccounts`)
- Create: `lib/feature/spawn/data/model/claude_account_model.dart`
- Modify: `lib/feature/spawn/data/data_source/spawn_remote_data_source.dart`
- Modify: `lib/feature/spawn/data/repository/spawn_repository.dart`
- Modify: `lib/feature/spawn/data/model/params/spawn_session_params.dart`
- Modify: `lib/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart`
- Create: `lib/core/widgets/pickers/claude_account_picker_sheet.dart`
- Modify: `lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart:91-100` (picker opener) and `:180-186` (row)
- Test:
  - `test/feature/spawn/data/data_source/spawn_remote_data_source_test.dart`
  - `test/feature/spawn/data/repository/spawn_repository_test.dart`
  - `test/feature/spawn/presentation/spawn_screen/logic/spawn_cubit_test.dart`
  - `test/feature/spawn/presentation/spawn_screen/ui/spawn_body_test.dart`

**Interfaces:**
- Consumes: `GET /api/v1/claude-accounts` → `{accounts: [{id, label, configDir, isDefault, status: {loggedIn, subscriptionType}}]}` (Task 9); `claudeAccountId` on `POST /api/v1/sessions` (Task 6).
- Produces:
  - `EndPoints.claudeAccounts`
  - `ClaudeAccountModel{id, label, isDefault, loggedIn, subscriptionType}` with `fromJson`, `listFromJson`, `planLabel`
  - `SpawnRemoteDataSource.getClaudeAccounts(): Future<GlobalResponse<List<ClaudeAccountModel>>>`
  - `SpawnRepository.getClaudeAccounts(): FutureResult<GlobalResponse<List<ClaudeAccountModel>>>`
  - `SpawnSessionParams.claudeAccountId`
  - `SpawnCubit.claudeAccounts`, `SpawnCubit.claudeAccountId`, `SpawnCubit.setClaudeAccount(String)`
  - `showClaudeAccountPickerSheet(context, {required List<ClaudeAccountModel> accounts, required String selected}) → Future<String?>`

- [ ] **Step 1: Write failing tests**

Append to `spawn_remote_data_source_test.dart` inside `main`:

```dart
  test('parses Claude accounts with status', () async {
    when(() => apiConsumer.get(EndPoints.claudeAccounts)).thenAnswer(
      (_) async => jsonResponse({
        'accounts': [
          {'id': 'default', 'label': 'Default', 'isDefault': true, 'status': {'loggedIn': true, 'subscriptionType': 'max'}},
          {'id': 'personal', 'label': 'Personal', 'isDefault': false, 'status': {'loggedIn': false}},
        ],
      }),
    );

    final accounts = (await dataSource.getClaudeAccounts()).data!;
    expect(accounts.map((a) => a.id), ['default', 'personal']);
    expect(accounts.first.planLabel, 'Max');
    expect(accounts.last.planLabel, 'Not logged in');
  });

  test('sends claudeAccountId when given', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => jsonResponse({'session': {'id': 's1', 'projectId': 'p'}}));

    await dataSource.spawn(const SpawnSessionParams(projectId: 'p', harness: 'claude-code', claudeAccountId: 'personal'));

    final body = verify(() => apiConsumer.post(EndPoints.sessions, body: captureAny(named: 'body'))).captured.single as Map<String, dynamic>;
    expect(body['claudeAccountId'], 'personal');
  });
```

Append to `spawn_repository_test.dart` inside `main`:

```dart
  group('getClaudeAccounts', () {
    test('fails fast with noNetwork when the daemon is unreachable', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      final result = await repository.getClaudeAccounts();

      expect(result.isFailure, isTrue);
      verifyNever(() => dataSource.getClaudeAccounts());
    });
  });
```

Append to `spawn_cubit_test.dart` inside `main`. **First update the existing helpers:**
- `buildCubit()` also stubs `when(() => repository.getClaudeAccounts()).thenAnswer((_) async => Result.success(GlobalResponse(data: _accounts)));`.
- Tests that construct `SpawnCubit(repository)` directly and call `loadCatalog` need the same stub. Put it in `setUp` so every test has it.

```dart
  List<ClaudeAccountModel> get _accounts => const [
    ClaudeAccountModel(id: 'default', label: 'Default', isDefault: true, loggedIn: true, subscriptionType: 'max'),
    ClaudeAccountModel(id: 'personal', label: 'Personal', isDefault: false, loggedIn: true, subscriptionType: 'pro'),
  ];
```

Declare `_accounts` as a top-level getter next to `_catalog`, not inside `main`.

```dart
  blocTest<SpawnCubit, SpawnState>(
    'loads Claude accounts with the catalog',
    build: buildCubit,
    act: (cubit) => cubit.loadCatalog(),
    verify: (cubit) {
      expect(cubit.claudeAccounts.map((a) => a.id), ['default', 'personal']);
      expect(cubit.claudeAccountId, 'default');
    },
  );

  blocTest<SpawnCubit, SpawnState>(
    'changing the agent resets the account',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setClaudeAccount('personal');
      cubit.setHarness('codex');
    },
    verify: (cubit) => expect(cubit.claudeAccountId, 'default'),
  );

  blocTest<SpawnCubit, SpawnState>(
    'submits the account only for claude-code',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit
        ..setProject('p-1')
        ..name = 'n'
        ..prompt = 'p'
        ..setHarness('claude-code')
        ..setClaudeAccount('personal');
      await cubit.submit();
    },
    verify: (_) {
      final params = verify(() => repository.spawn(captureAny())).captured.single as SpawnSessionParams;
      expect(params.claudeAccountId, 'personal');
    },
  );

  test('SpawnSessionParams omits claudeAccountId when absent', () {
    expect(const SpawnSessionParams(projectId: 'p').toJson().containsKey('claudeAccountId'), isFalse);
    expect(const SpawnSessionParams(projectId: 'p', claudeAccountId: 'personal').toJson()['claudeAccountId'], 'personal');
  });
```

Append to `spawn_body_test.dart` inside `main`. **First update the helper:** `stubCatalog()` also stubs `when(() => spawnRepository.getClaudeAccounts())` with the same two accounts (import `claude_account_model.dart`).

```dart
  testWidgets('the Account row appears only for Claude Code', (tester) async {
    stubCatalog();
    stubProjectKind('single_repo');
    buildSessionsCubit();
    final spawnCubit = SpawnCubit(spawnRepository);

    await pumpBody(tester, spawnCubit);
    spawnCubit.setHarness('amp');
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsNothing);

    spawnCubit.setHarness('claude-code');
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Default · Max'), findsOneWidget);
  });
```

Run: `cd packages/mobile && flutter test test/feature/spawn`
Expected: FAIL (compile: `getClaudeAccounts` / `ClaudeAccountModel` undefined).

- [ ] **Step 2: Implement data layer**

`end_points.dart`: add after `agentsRefresh`:

```dart
  static const String claudeAccounts = '/api/v1/claude-accounts';
```

`claude_account_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class ClaudeAccountModel extends Equatable {
  const ClaudeAccountModel({this.id, this.label, this.isDefault, this.loggedIn, this.subscriptionType});

  final String? id;
  final String? label;
  final bool? isDefault;
  final bool? loggedIn;
  final String? subscriptionType;

  factory ClaudeAccountModel.fromJson(Map<String, dynamic> json) {
    final status = json['status'] is Map<String, dynamic> ? json['status'] as Map<String, dynamic> : const <String, dynamic>{};
    return ClaudeAccountModel(
      id: json['id'] as String?,
      label: json['label'] as String?,
      isDefault: json['isDefault'] as bool?,
      loggedIn: status['loggedIn'] as bool?,
      subscriptionType: status['subscriptionType'] as String?,
    );
  }

  static List<ClaudeAccountModel> listFromJson(Map<String, dynamic> json) {
    final raw = json['accounts'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(ClaudeAccountModel.fromJson).toList();
  }

  String get planLabel {
    if (loggedIn == false) return 'Not logged in';
    if (loggedIn != true) return 'Unknown';
    return switch (subscriptionType) {
      'max' => 'Max',
      'pro' => 'Pro',
      null || '' => 'Unknown',
      final other => other,
    };
  }

  String get displayLabel => '${label ?? id ?? ''} · $planLabel';

  @override
  List<Object?> get props => [id, label, isDefault, loggedIn, subscriptionType];
}
```

`spawn_remote_data_source.dart`:
- Add to the abstract class: `Future<GlobalResponse<List<ClaudeAccountModel>>> getClaudeAccounts();`.
- Implementation:

```dart
  @override
  Future<GlobalResponse<List<ClaudeAccountModel>>> getClaudeAccounts() async {
    final response = await _apiConsumer.get(EndPoints.claudeAccounts);
    return GlobalResponse<List<ClaudeAccountModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: ClaudeAccountModel.listFromJson,
    );
  }
```

`spawn_repository.dart`:
- Add to the abstract class: `FutureResult<GlobalResponse<List<ClaudeAccountModel>>> getClaudeAccounts();`.
- Implementation, the same shape as `getAgents`:

```dart
  @override
  FutureResult<GlobalResponse<List<ClaudeAccountModel>>> getClaudeAccounts() async {
    if (await _network.isConnected) {
      try {
        return Result.success(await _remoteDataSource.getClaudeAccounts());
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }
```

`spawn_session_params.dart`:
- Add `this.claudeAccountId,` to the constructor and `final String? claudeAccountId;`.
- In `toJson`, add `if (claudeAccountId != null && claudeAccountId!.isNotEmpty) 'claudeAccountId': claudeAccountId,`.
- Append `claudeAccountId` to `props`.

- [ ] **Step 3: Implement cubit**

`spawn_cubit.dart`:
- Fields after `harness`:

```dart
  List<ClaudeAccountModel> claudeAccounts = const [];
  String claudeAccountId = 'default';
```

- `setHarness` resets the account:

```dart
  void setHarness(String next) {
    harness = next;
    claudeAccountId = 'default';
    _bump();
  }

  void setClaudeAccount(String next) {
    claudeAccountId = next;
    _bump();
  }
```

- In `loadCatalog`'s `onSuccess` (before `_bump()`), trigger the account load, and add the method:

```dart
        _catalog = response.data;
        harness = _pickHarness(harness);
        unawaited(_loadClaudeAccounts());
        _bump();
```

```dart
  Future<void> _loadClaudeAccounts() async {
    final result = await _repository.getClaudeAccounts();
    result.when(
      onSuccess: (response) {
        claudeAccounts = response.data ?? const [];
        if (!claudeAccounts.any((account) => account.id == claudeAccountId)) claudeAccountId = 'default';
        _bump();
      },
      onFailure: (_) {},
    );
  }
```

  Import `dart:async` for `unawaited`. If a blocTest's `verify` runs before the account load completes, `await _loadClaudeAccounts();` inside `loadCatalog` after `_bump()` instead of `unawaited`, since `loadCatalog` is already async.
- In `submit`'s `SpawnSessionParams`, add `claudeAccountId: harness == 'claude-code' ? claudeAccountId : null,`.

- [ ] **Step 4: Implement picker and row**

`claude_account_picker_sheet.dart`, modelled on `agent_picker_sheet.dart` without the refresh control:

```dart
import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_sheet_chrome.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/spawn/data/model/claude_account_model.dart';

Future<String?> showClaudeAccountPickerSheet(
  BuildContext context, {
  required List<ClaudeAccountModel> accounts,
  required String selected,
}) {
  final skin = context.skin;
  return showExpressiveSheet<String>(
    context: context,
    builder: (sheetContext) => AppSheetChrome(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText('Claude account', style: AppTextStyle.style17SemiBold),
          const VerticalSpace(4),
          AppText(
            'Which Claude login this session runs on.',
            style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
            maxLines: 2,
          ),
          const VerticalSpace(8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final account in accounts)
                  AppInkWell(
                    onTap: () {
                      Haptics.select();
                      Navigator.of(sheetContext).pop(account.id);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText(
                                  account.label ?? account.id ?? '',
                                  style: AppTextStyle.style15Medium.copyWith(
                                    color: account.id == selected ? skin.accent : skin.textPrimary,
                                  ),
                                ),
                                AppText(
                                  account.planLabel,
                                  style: AppTextStyle.style12Regular.copyWith(
                                    color: account.loggedIn == true ? skin.textTertiary : skin.amber,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (account.id == selected) Icon(Icons.check, size: 18, color: skin.accent),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
```

`spawn_body.dart`:
- Add the import. Add the opener next to `_openAgentPicker`:

```dart
  Future<void> _openClaudeAccountPicker(BuildContext context) async {
    final chosen = await showClaudeAccountPickerSheet(
      context,
      accounts: _cubit.claudeAccounts,
      selected: _cubit.claudeAccountId,
    );
    if (chosen != null && context.mounted) _cubit.setClaudeAccount(chosen);
  }
```

- In the `SettingsGroup` children, directly after the Agent `SettingsRow`:

```dart
                  if (_cubit.harness == 'claude-code' && _cubit.claudeAccounts.isNotEmpty)
                    SettingsRow(
                      icon: Icons.person_outline,
                      label: 'Account',
                      value: _claudeAccountValue(),
                      onTap: () => _openClaudeAccountPicker(context),
                    ),
```

- Add to the state class:

```dart
  String _claudeAccountValue() {
    for (final account in _cubit.claudeAccounts) {
      if (account.id == _cubit.claudeAccountId) return account.displayLabel;
    }
    return 'Default';
  }
```

- [ ] **Step 5: Run gates**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile
git commit -m "feat(mobile): choose the Claude account when spawning" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 13: Full gates and real-app verification

**Files:**
- Modify (only if a gate fails): whichever file the failure names.
- Create: `docs/superpowers/evidence/claude-accounts-verification.md`

**Interfaces:** consumes everything above; produces the verification record.

- [ ] **Step 1: Run every gate from the repo root**

```bash
cd backend && go test -race ./... && cd ..
npm run lint
npm run api && git diff --exit-code backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
npm run frontend:typecheck && npm run frontend:lint && (cd frontend && npx vitest run)
(cd packages/mobile && flutter analyze && flutter test)
```

Expected: all pass, and `git diff --exit-code` prints nothing. Fix any failure in the task that owns the file, then re-run the full list.

- [ ] **Step 2: Real app (manual, needs the user's Claude login)**

Start the app with `npm run tauri:dev` from the repo root (see `RUN_APP_COMMANDS.md`). Record each result in the evidence file:

1. **Settings → Claude accounts** shows **Default** first with plan **Max** and no Remove button.
2. **Add account "Personal":**
   - `~/.claude-personal` exists with mode `drwx------`.
   - `CLAUDE.md`, `settings.json`, `skills`, `commands`, `plugins` are symlinks into `~/.claude` (`ls -la ~/.claude-personal`).
   - A terminal opens running `claude`.
3. **`/login`** with the personal account, then quit. Refocus Settings → Personal shows **Pro**.
   - `security dump-keychain | grep -o '"svce"<blob>="Claude Code[^"]*"'` lists `Claude Code-credentials-30c38298`.
   - `claude auth status` (no env) still reports `max`.
4. **New task:** agent Claude Code, Account **Personal**.
   - In the session terminal, `/status` shows the personal account.
   - `ls ~/.claude-personal/projects` gains the worktree's project folder; `~/.claude/projects` does not.
5. **The session obeys the global `CLAUDE.md`:** ask it "what are your standing instructions about comments?". It quotes "don't make comments".
6. **Switch agent dialog** on that session: target Claude Code, account Default, confirm.
   - The switch completes fresh.
   - Switch back to Personal → it resumes the original conversation (`targetStartMode: resumed` in `GET /api/v1/sessions/{id}/agent-switches`).
7. **Restart persistence:** quit the app and restart it. The session restores on the account it was last switched to (`/status`).
8. **Remove Personal while the session exists** → the error "Sessions still use this account" appears inline.
9. **Mobile:** the spawn screen shows the Account row for Claude Code only. Spawning on Personal starts a session whose `/status` is personal.

- [ ] **Step 3: Commit the verification record**

```bash
git add docs/superpowers/evidence/claude-accounts-verification.md
git commit -m "docs: record Claude accounts real-app verification" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
