# Remove the Orchestrator Subsystem — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Operator's orchestrator subsystem entirely so every session is an ordinary agent session on any harness, with the appended system prompt reduced to the PR branch-namespace block plus the workspace layout block.

**Architecture:** Bottom-up removal. The data model goes first (`domain.SessionKind` is referenced by nearly everything), then the prompt, project config, HTTP surface, CLI, renderer and mobile. Each phase compiles and tests green on its own. Deletions are complete — no compatibility shims, no vestigial fields — because Operator is pre-release with no users and the user authorised clearing data and breaking changes.

**Tech Stack:** Go 1.x + goose migrations + sqlc; React 19 + TypeScript + Vitest + Tauri; Flutter 3.44.5 (pinned in CI) + Cubit + drift.

**Spec:** [`docs/superpowers/specs/2026-09-20-remove-orchestrator-design.md`](../specs/2026-09-20-remove-orchestrator-design.md)

## Global Constraints

- **Branch:** work on a feature branch off `development`. Never commit to `master`. Never bump the version on `development`.
- **Never stash in this checkout** — concurrent sessions run `commit -a` here. Use a scratch worktree if you need a baseline.
- **Three systems must not regress** (spec §1.1): mobile normal-session chat; desktop session states (`working` / `needs_input` / review); both Kanban boards. If a step cannot preserve all three, stop and report rather than shipping.
- **`opr hooks` and the ten managed hooks stay.** Every session state in both UIs originates there (`backend/internal/adapters/agent/claudecode/hooks.go:37-48`).
- **CLI wrappers are deleted; their HTTP routes are not.** Specifically `POST /sessions/{id}/send` stays — mobile and desktop both use it.
- **Never touch `projects.kind`** or `SessionsBoard.tsx:116`'s `w.kind === "single_repo"`. That is *project* kind (`single_repo` / `workspace`), unrelated to session kind.
- **Do not hand-edit** `backend/internal/storage/sqlite/gen/*` — change queries or migrations and run `npm run sqlc`.
- **Do not switch session endpoints to `decodeJSONStrict`.** Their leniency is what keeps an un-updated mobile build working against a new daemon.
- **Never regenerate the Tauri signing key.**
- **Scope searches** to `backend/`, `frontend/`, `packages/` — nested worktrees (`.worktrees/`, `.claude/worktrees/`) and siblings (`../Operator-*`) poison repo-wide grep with stale duplicates.
- **Gate commands:** `npm run lint` (runs `go test ./...` + golangci-lint v2.12.2) from repo root; `npm run frontend:typecheck`; `cd frontend && npm test` (vitest); `cd packages/mobile && flutter analyze` (must print "No issues found!") and `flutter test`.
- **Regeneration:** `npm run sqlc` after any migration/query change; `npm run api` (spec then TS types) after any DTO change.
- **Commit after every task.** Conventional commit messages. End each message with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

---

# Phase 1 — Data model foundation

Everything else references `domain.SessionKind`. This phase removes it at the database, generated-code and domain layers so later phases compile.

### Task 1: Migration 0116 — drop session kind, spawned_by and the orchestrator inbox

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0116_remove_orchestrator.sql`
- Create: `backend/internal/storage/sqlite/migrate_remove_orchestrator_test.go`

**Interfaces:**
- Consumes: nothing.
- Produces: a `sessions` table with no `kind` and no `spawned_by` column; no `orchestrator_inbox` table; all three `sessions_cdc_*` triggers intact.

**Why in-place, not a table rebuild:** SQLite refuses `DROP COLUMN` on a column named in a CHECK constraint, and `sessions.kind` has `CHECK (kind IN ('worker', 'orchestrator'))` (`migrations/0001_init.sql:26-27`). Rebuilding the table would drop its triggers — including `sessions_cdc_update`, the sole source of the `session_updated` events that drive liveness in both Kanbans and mobile. Instead use the repo's existing pattern (`0053`, `0054`, `0082`, `0083`): edit the CHECK out via `writable_schema`, then `DROP COLUMN` normally. Verified safe: no trigger or index on `sessions` references `kind` or `spawned_by`. (The `OLD.kind` at `0108_board_cdc.sql:26` is in `projects_cdc_update` and refers to `projects.kind`.)

- [ ] **Step 1: Write the failing test**

Create `backend/internal/storage/sqlite/migrate_remove_orchestrator_test.go`:

```go
package sqlite

import (
	"database/sql"
	"path/filepath"
	"strings"
	"testing"
)

func openMigrationDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite", "file:"+filepath.Join(t.TempDir(), "opr.db")+"?_pragma=foreign_keys(1)")
	if err != nil {
		t.Fatal(err)
	}
	db.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = db.Close() })
	return db
}

func seedProjectAndSessions(t *testing.T, db *sql.DB) {
	t.Helper()
	if _, err := db.Exec(`INSERT INTO projects (id, path, registered_at) VALUES ('p', '/tmp/p', datetime('now'))`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO sessions (id, project_id, num, kind, activity_last_at, created_at, updated_at)
		VALUES ('w1', 'p', 1, 'worker', datetime('now'), datetime('now'), datetime('now'))`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO sessions (id, project_id, num, kind, activity_last_at, created_at, updated_at)
		VALUES ('o1', 'p', 2, 'orchestrator', datetime('now'), datetime('now'), datetime('now'))`); err != nil {
		t.Fatal(err)
	}
}

func TestMigrate0116DropsOrchestratorColumnsAndRows(t *testing.T) {
	db := openMigrationDB(t)
	upTo(t, db, 115)
	seedProjectAndSessions(t, db)
	upTo(t, db, 116)

	for _, col := range []string{"kind", "spawned_by"} {
		var n int
		if err := db.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('sessions') WHERE name = ?`, col).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != 0 {
			t.Fatalf("sessions.%s still exists", col)
		}
	}

	var ids string
	if err := db.QueryRow(`SELECT group_concat(id) FROM sessions`).Scan(&ids); err != nil {
		t.Fatal(err)
	}
	if ids != "w1" {
		t.Fatalf("sessions after migrate = %q, want \"w1\" (orchestrator row must be deleted)", ids)
	}

	var n int
	if err := db.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'orchestrator_inbox'`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatal("orchestrator_inbox table must be dropped")
	}

	var integrity string
	if err := db.QueryRow(`PRAGMA integrity_check`).Scan(&integrity); err != nil {
		t.Fatal(err)
	}
	if integrity != "ok" {
		t.Fatalf("integrity_check = %s", integrity)
	}
}

// TestMigrate0116PreservesSessionCDCTriggers is the guard for spec section 1.1:
// these triggers are the only source of the session_updated events that drive
// "Needs you" and termination in both Kanban boards and in mobile.
func TestMigrate0116PreservesSessionCDCTriggers(t *testing.T) {
	db := openMigrationDB(t)
	upTo(t, db, 115)
	seedProjectAndSessions(t, db)
	upTo(t, db, 116)

	for _, name := range []string{"sessions_cdc_insert", "sessions_cdc_update", "sessions_cdc_delete"} {
		var n int
		if err := db.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND name = ?`, name).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != 1 {
			t.Fatalf("trigger %s missing after migrate", name)
		}
	}

	if _, err := db.Exec(`DELETE FROM change_log`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE sessions SET activity_state = 'waiting_input' WHERE id = 'w1'`); err != nil {
		t.Fatal(err)
	}
	var eventType, payload string
	if err := db.QueryRow(`SELECT event_type, payload FROM change_log ORDER BY seq DESC LIMIT 1`).Scan(&eventType, &payload); err != nil {
		t.Fatal("no change_log row after activity update; mobile and Kanban liveness is broken: " + err.Error())
	}
	if eventType != "session_updated" {
		t.Fatalf("event_type = %s, want session_updated", eventType)
	}
	if !strings.Contains(payload, `"activity":"waiting_input"`) || !strings.Contains(payload, `"isTerminated"`) {
		t.Fatalf("payload missing activity/isTerminated: %s", payload)
	}

	if _, err := db.Exec(`DELETE FROM change_log`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE sessions SET is_terminated = 1 WHERE id = 'w1'`); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT event_type FROM change_log ORDER BY seq DESC LIMIT 1`).Scan(&eventType); err != nil {
		t.Fatal(err)
	}
	if eventType != "session_updated" {
		t.Fatalf("termination event_type = %s, want session_updated", eventType)
	}
}
```

If `upTo` or a `contains`-style helper already exists in the package, reuse it and delete the duplicate here rather than shadowing it.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd backend && go test ./internal/storage/sqlite/ -run TestMigrate0116 -v
```

Expected: FAIL — migration 116 does not exist, so `upTo(t, db, 116)` errors.

- [ ] **Step 3: Write the migration**

Create `backend/internal/storage/sqlite/migrations/0116_remove_orchestrator.sql`:

```sql
-- Remove the orchestrator subsystem's schema: the sessions.kind discriminator,
-- the spawned_by attribution column, and the orchestrator inbox.
--
-- sessions.kind carries CHECK (kind IN ('worker', 'orchestrator')) from
-- 0001_init, and SQLite refuses ALTER TABLE ... DROP COLUMN on a column named in
-- a CHECK constraint. Rebuilding the table would drop its triggers, including
-- sessions_cdc_update, which is the only source of the session_updated events
-- that carry activity and isTerminated to the desktop board and to mobile. So we
-- edit the CHECK out in place with the same writable_schema pattern used for the
-- harness constraint in 0053/0054/0082/0083, then DROP COLUMN normally.
--
-- Verified before writing: no trigger or index on sessions references kind or
-- spawned_by. The OLD.kind in 0108_board_cdc.sql belongs to projects_cdc_update
-- and refers to projects.kind, a different column on a different table.

-- +goose NO TRANSACTION
-- +goose Up
DELETE FROM sessions WHERE kind = 'orchestrator';

PRAGMA writable_schema = ON;
UPDATE sqlite_master
SET sql = replace(sql, 'CHECK (kind IN (''worker'', ''orchestrator''))', '')
WHERE type = 'table' AND name = 'sessions'
    AND instr(sql, 'CHECK (kind IN') > 0;
PRAGMA writable_schema = RESET;

ALTER TABLE sessions DROP COLUMN kind;
ALTER TABLE sessions DROP COLUMN spawned_by;

DROP TABLE IF EXISTS orchestrator_inbox;

-- +goose Down
-- Irreversible: the orchestrator rows and inbox contents are gone. Restoring the
-- columns without their data would misrepresent history, and Operator is
-- pre-release with no installed users to migrate down.
SELECT 1;
```

Before running, confirm the CHECK text matches the database byte for byte — `sqlite_master` stores the original DDL verbatim, including whitespace:

```bash
cd backend && go test ./internal/storage/sqlite/ -run TestMigrate0116DropsOrchestratorColumnsAndRows -v
```

If the column survives, print the stored DDL and adjust the `replace()` source string to match exactly:

```sql
SELECT sql FROM sqlite_master WHERE type='table' AND name='sessions';
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd backend && go test ./internal/storage/sqlite/ -run TestMigrate0116 -v
```

Expected: PASS, both tests.

- [ ] **Step 5: Run the whole storage package**

```bash
cd backend && go test ./internal/storage/...
```

Expected: PASS. Existing migration tests that pin historical behaviour must be untouched.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/storage/sqlite/migrations/0116_remove_orchestrator.sql backend/internal/storage/sqlite/migrate_remove_orchestrator_test.go
git commit -m "$(cat <<'EOF'
feat(storage): migration 0116 removes session kind, spawned_by and the orchestrator inbox

Edits the kind CHECK constraint out in place with the writable_schema
pattern already used for the harness constraint, so the sessions table is
never rebuilt and its CDC triggers are never dropped. Those triggers are
the only source of the session_updated events that drive liveness in both
Kanban boards and in mobile; a regression test asserts they still fire.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Regenerate sqlc and drop the store mapping

**Files:**
- Modify: `backend/internal/storage/sqlite/queries/sessions.sql`
- Modify: `backend/internal/storage/sqlite/store/session_store.go`
- Regenerate: `backend/internal/storage/sqlite/gen/**`

**Interfaces:**
- Consumes: Task 1's schema.
- Produces: `gen.Session` without `Kind` / `SpawnedBy`; `session_store.go` no longer maps either field.

- [ ] **Step 1: Remove the columns from the queries**

Open `backend/internal/storage/sqlite/queries/sessions.sql` and delete every `kind` and `spawned_by` occurrence — column lists, `INSERT` targets, `VALUES` placeholders (renumber the remaining `?`/named parameters), and any `WHERE kind = ...` predicate. Find them with:

```bash
grep -n "kind\|spawned_by" backend/internal/storage/sqlite/queries/sessions.sql
```

- [ ] **Step 2: Regenerate**

```bash
npm run sqlc
```

- [ ] **Step 3: Verify the generated model lost the fields**

```bash
grep -n "Kind\|SpawnedBy" backend/internal/storage/sqlite/gen/models.go
```

Expected: no `Kind` or `SpawnedBy` on the session model. (`usage_sources.kind` and any project `Kind` may legitimately remain — check which struct each hit belongs to.)

- [ ] **Step 4: Drop the store mapping**

In `backend/internal/storage/sqlite/store/session_store.go`, remove the row→record and record→insert mapping for both fields. Compile to find them:

```bash
cd backend && go build ./... 2>&1 | head -30
```

- [ ] **Step 5: Run the storage tests**

```bash
cd backend && go test ./internal/storage/...
```

Expected: PASS. Fix any test that constructs a session with `Kind`.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/storage/sqlite/
git commit -m "$(cat <<'EOF'
refactor(storage): drop session kind and spawned_by from queries and store

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Delete `domain.SessionKind` and the spawn-config fields

**Files:**
- Modify: `backend/internal/domain/session.go:16-22,88`
- Modify: `backend/internal/ports/session.go:21-56`
- Modify: `backend/internal/session_manager/manager.go:2748-2780,3008`
- Modify: call sites across `backend/internal/service/**`, `backend/internal/observe/**`, `backend/internal/review/**`

**Interfaces:**
- Consumes: Task 2's store.
- Produces: `defaultSessionBranch(id domain.SessionID, prefix, branchNamespace string) string` — the `kind` parameter is gone. `ports.SpawnConfig` no longer has `Kind` or `RequestedBy`. `domain.SessionRecord` no longer has `Kind` or `SpawnedBy`.

- [ ] **Step 1: Delete the type**

In `backend/internal/domain/session.go`, delete the `SessionKind` type and the `KindWorker` / `KindOrchestrator` constants (lines 16-22) and the `Kind` field on the session record (line 88) and on `domain.Session` if present. Also delete `SpawnedBy`.

- [ ] **Step 2: Delete the ports fields**

In `backend/internal/ports/session.go`, delete `SpawnConfig.Kind` and `SpawnConfig.RequestedBy`.

- [ ] **Step 3: Fix the branch helpers**

In `backend/internal/session_manager/manager.go`, change the signature and drop the orchestrator helper:

```go
func defaultSessionBranch(id domain.SessionID, prefix, branchNamespace string) string {
	// body unchanged except that the kind switch is gone: every session now uses
	// what was previously the worker branch shape.
}
```

Delete `orchestratorBranch` (around `manager.go:2775`) and `activeOrchestratorSessionID` (`manager.go:3008`) entirely.

- [ ] **Step 4: Compile and fix every call site**

```bash
cd backend && go build ./... 2>&1 | head -40
```

Work through the errors. Expected sites include `service/session/delegation.go`, `service/session/service.go`, `service/ticket/service.go`, `review/review.go`, `observe/trackerintake/observer.go`, `httpd/controllers/sessions.go`. Each spawn call simply stops passing `Kind` / `RequestedBy`.

- [ ] **Step 5: Run the backend suite**

```bash
cd backend && go test ./... 2>&1 | tail -30
```

Expected: failures only in tests that construct sessions with `Kind` or assert orchestrator behaviour. Delete orchestrator-specific test cases; update the rest to drop the field.

- [ ] **Step 6: Commit**

```bash
git add backend/
git commit -m "$(cat <<'EOF'
refactor(domain): delete SessionKind and orchestrator spawn attribution

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Phase 2 — Prompt reduction

### Task 4: Reduce the appended system prompt to two sections

**Files:**
- Modify: `backend/internal/session_manager/prompt.go`
- Modify: `backend/internal/session_manager/manager.go:2957-2960,2971,3009`
- Test: `backend/internal/session_manager/prompt_test.go`

**Interfaces:**
- Consumes: Task 3's domain.
- Produces: `buildSystemPromptText(cfg systemPromptConfig) string` where `systemPromptConfig` has exactly one field, `AdditionalSections []string`. Output is the branch-namespace block, plus any additional sections, joined by `"\n\n"`.

- [ ] **Step 1: Write the failing test**

Add to `backend/internal/session_manager/prompt_test.go`:

```go
func TestBuildSystemPromptTextIsBranchNamespaceOnly(t *testing.T) {
	got := buildSystemPromptText(systemPromptConfig{})
	if got != workerMultiPRPrompt() {
		t.Fatalf("system prompt must be the branch-namespace block alone, got:\n%s", got)
	}
	for _, banned := range []string{
		"Operator Worker Role",
		"Orchestrator",
		"Standing-instruction confidentiality",
		"Docker Containers Started By This Session",
		"Project Rules",
		"Using the opr CLI",
		"Operator desktop Browser panel",
		"Task Source and PR/MR Behavior",
		"Git and PR/MR Rules",
	} {
		if strings.Contains(got, banned) {
			t.Errorf("removed section %q still present", banned)
		}
	}
}

func TestBuildSystemPromptTextAppendsWorkspaceSection(t *testing.T) {
	got := buildSystemPromptText(systemPromptConfig{AdditionalSections: []string{"## Workspace project\n\nbody"}})
	want := workerMultiPRPrompt() + "\n\n## Workspace project\n\nbody"
	if got != want {
		t.Fatalf("got:\n%s\nwant:\n%s", got, want)
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd backend && go test ./internal/session_manager/ -run TestBuildSystemPromptText -v
```

Expected: FAIL — the prompt still contains the worker role and guard.

- [ ] **Step 3: Rewrite the builder**

Replace `buildSystemPromptText` in `backend/internal/session_manager/prompt.go` with:

```go
func buildSystemPromptText(cfg systemPromptConfig) string {
	sections := make([]string, 0, 1+len(cfg.AdditionalSections))
	sections = append(sections, workerMultiPRPrompt())
	for _, section := range cfg.AdditionalSections {
		if section := strings.TrimSpace(section); section != "" {
			sections = append(sections, section)
		}
	}
	return strings.Join(sections, "\n\n")
}
```

Reduce `systemPromptConfig` to:

```go
type systemPromptConfig struct {
	AdditionalSections []string
}
```

Delete from `prompt.go`: `orchestratorSystemPrompt`, `workerSystemPrompt`, `workerOrchestratorPrompt`, `workerContainerLabelPrompt`, `systemPromptGuard`, `buildProjectRules`, `projectRelativeFile`, `projectContextSection`, `projectName`, `projectValue`, the `sessionPromptRole` type and its constants, `projectRulesConfig`, and the `promptProject` type if nothing else uses it.

**Keep** `buildTaskPrompt`, `issueContextSection` and `issueContextTrustBoundary` — they belong to the task prompt, not the system prompt, and the trust boundary is the prompt-injection guard for tracker-intake issue text, which stays live.

**Keep** `workerMultiPRPrompt` exactly as written. It is the agent-side half of PR attribution: `matchSession` (`observe/scm/observer.go:848`) claims a PR for a session only by branch prefix.

- [ ] **Step 4: Delete the skill pointer and the orchestrator workspace prompt**

In `backend/internal/session_manager/manager.go`, delete the `operatorSkillPointer` method (`:2971`) and the line that appends it (`:2960`). Keep the line that appends `workspacePrompt` (`:2957`). In `workspaceProjectPrompt` (`:2988`), delete the `kind` parameter and the switch, returning `workspaceWorkerPrompt(repos)` directly; delete `workspaceOrchestratorPrompt`.

- [ ] **Step 5: Compile and run the package tests**

```bash
cd backend && go build ./... && go test ./internal/session_manager/ 2>&1 | tail -30
```

Expected: PASS after deleting orchestrator-prompt test cases.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/session_manager/
git commit -m "$(cat <<'EOF'
feat(prompt): reduce the appended system prompt to the PR branch namespace

Keeps workerMultiPRPrompt, which is the agent-side half of PR attribution
in the SCM observer, and the workspace layout section. Drops the worker
and orchestrator roles, task-source and git rules, container labels,
project rules, the confidentiality guard and the opr skill pointer.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Delete the orchestrator skill assets

**Files:**
- Delete: `backend/internal/skillassets/using-opr/commands/orchestrator.md`, `spawn.md`, `send.md`
- Modify: `backend/internal/skillassets/skillassets.go` (if it enumerates files)
- Test: `backend/internal/skillassets/skillassets_test.go`

**Interfaces:**
- Consumes: nothing.
- Produces: an installed skill directory with no orchestrator, spawn or send guide.

- [ ] **Step 1: Delete the files**

```bash
git rm backend/internal/skillassets/using-opr/commands/orchestrator.md \
       backend/internal/skillassets/using-opr/commands/spawn.md \
       backend/internal/skillassets/using-opr/commands/send.md
```

- [ ] **Step 2: Remove references to the deleted commands**

```bash
grep -rn "orchestrator\|opr spawn\|opr send\|opr board\|opr inbox" backend/internal/skillassets/using-opr/
```

Edit `SKILL.md` and `references.md` to drop those entries.

- [ ] **Step 3: Run the package tests**

```bash
cd backend && go test ./internal/skillassets/ -v
```

Expected: PASS. If the test asserts an embedded file list, update it.

- [ ] **Step 4: Commit**

```bash
git add backend/internal/skillassets/
git commit -m "$(cat <<'EOF'
chore(skillassets): remove orchestrator, spawn and send command guides

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Phase 3 — Project config and container reaping

### Task 6: Collapse the role overrides into one project harness

**Files:**
- Modify: `backend/internal/domain/projectconfig.go:20-60,129-133,193-215`
- Test: `backend/internal/domain/projectconfig_test.go`

**Interfaces:**
- Consumes: Task 3's domain.
- Produces: `ProjectConfig.Harness AgentHarness` with JSON tag `agent,omitempty`. `RoleOverride`, `OrchestratorPolicy`, `AgentRules`, `AgentRulesFile` and `ContainerReap` no longer exist.

Harness selection today lives **only** on `RoleOverride.Harness` (`projectconfig.go:131`) — `ProjectConfig.AgentConfig` has no harness field — so deleting the pair without a replacement would leave a project unable to name its harness.

- [ ] **Step 1: Write the failing test**

Add to `backend/internal/domain/projectconfig_test.go`:

```go
func TestProjectConfigHarnessRoundTrip(t *testing.T) {
	var c ProjectConfig
	if err := json.Unmarshal([]byte(`{"agent":"claude-code"}`), &c); err != nil {
		t.Fatal(err)
	}
	if c.Harness != AgentHarness("claude-code") {
		t.Fatalf("Harness = %q, want claude-code", c.Harness)
	}
	if err := c.Validate(); err != nil {
		t.Fatalf("Validate() = %v", err)
	}
}

func TestProjectConfigRejectsUnknownHarness(t *testing.T) {
	c := ProjectConfig{Harness: AgentHarness("nope")}
	if err := c.Validate(); err == nil {
		t.Fatal("Validate() must reject an unknown harness")
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd backend && go test ./internal/domain/ -run TestProjectConfigHarness -v
```

Expected: FAIL — `ProjectConfig` has no `Harness` field.

- [ ] **Step 3: Edit the struct**

In `backend/internal/domain/projectconfig.go`, replace the `Worker` / `Orchestrator` pair with:

```go
	Harness AgentHarness `json:"agent,omitempty"`
```

Delete the `RoleOverride` type, `OrchestratorPolicy` (field and type), `AgentRules`, `AgentRulesFile`, `ContainerReap` (field and type), and the `projectRulesConfig` plumbing. Replace the role loop at `:199` with:

```go
	if c.Harness != "" && !c.Harness.IsKnown() {
		return fmt.Errorf("agent: unknown harness %q", c.Harness)
	}
```

Delete the `AgentRulesFile` validation at `:212`.

- [ ] **Step 4: Compile and fix consumers**

```bash
cd backend && go build ./... 2>&1 | head -40
```

Every `cfg.Worker.Harness` / `cfg.Orchestrator.Harness` read becomes `cfg.Harness`. Delete reads of the removed fields outright.

- [ ] **Step 5: Run the tests**

```bash
cd backend && go test ./internal/domain/ ./internal/service/... 2>&1 | tail -20
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/domain/ backend/internal/service/
git commit -m "$(cat <<'EOF'
refactor(config): collapse worker/orchestrator role overrides into one harness

Also removes OrchestratorPolicy, agentRules, agentRulesFile and
ContainerReap, whose consumers are being deleted.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Delete container reaping

**Files:**
- Delete: `backend/internal/adapters/container/dockerreap/**`
- Modify: `backend/internal/lifecycle/manager.go:74-75,133-136`
- Modify: `backend/internal/ports/` (remove `ContainerReaper`)
- Modify: the daemon wiring that calls `WithContainerReaper`

**Interfaces:**
- Consumes: Task 6's config.
- Produces: `lifecycle.MarkTerminated` with no container leg; no `ports.ContainerReaper`.

Nothing instructs agents to apply `--label opr.session` any more (Task 4 removed that prompt section), so `dockerreap` is unreachable. This is an accepted regression (spec §10.2): agent-started containers now persist until removed by hand.

- [ ] **Step 1: Delete the adapter**

```bash
git rm -r backend/internal/adapters/container/dockerreap
```

- [ ] **Step 2: Remove the port and the lifecycle option**

Delete `ports.ContainerReaper` and, in `backend/internal/lifecycle/manager.go`, the `WithContainerReaper` option, the reaper field, the `projectConfigLoader` if it has no other consumer, and the reap call inside `MarkTerminated`.

- [ ] **Step 3: Remove the wiring**

```bash
grep -rn "WithContainerReaper\|ContainerReaper\|dockerreap" backend/ --include="*.go"
```

Delete every remaining hit, including in `backend/internal/daemon/`.

- [ ] **Step 4: Build and test**

```bash
cd backend && go build ./... && go test ./internal/lifecycle/ ./internal/daemon/ 2>&1 | tail -20
```

Expected: PASS after deleting reaper test cases.

- [ ] **Step 5: Commit**

```bash
git add -A backend/
git commit -m "$(cat <<'EOF'
feat(lifecycle)!: remove Docker container reaping

Nothing instructs agents to apply the opr.session label now that the
container-label prompt section is gone, so the reaper is unreachable.
Agent-started containers persist until removed by hand.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Phase 4 — HTTP surface

### Task 8: Move the delegate route and drop the orchestrator routes

**Files:**
- Modify: `backend/internal/httpd/controllers/sessions.go:245-248,354`
- Modify: `backend/internal/httpd/controllers/dto.go:203,721,1007`
- Modify: `backend/internal/service/session/delegation.go:26,64`
- Modify: `backend/internal/httpd/apispec/specgen/build.go`
- Regenerate: `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`

**Interfaces:**
- Consumes: Task 3's `SpawnConfig`.
- Produces: `POST /api/v1/sessions/delegate` (same handler, same request and response bodies minus `kind` / `requestedBy`). `GET|POST /orchestrators`, `GET /orchestrators/{id}` no longer exist.

`POST /orchestrators/delegate` is the New Task dialog's session-creation endpoint. It is **renamed, not deleted**.

- [ ] **Step 1: Write the failing route test**

Add to the sessions controller test file:

```go
func TestDelegateRouteMovedOffOrchestratorPrefix(t *testing.T) {
	r := newTestRouter(t) // use the package's existing router helper
	if got := routeExists(r, "POST", "/api/v1/sessions/delegate"); !got {
		t.Error("POST /api/v1/sessions/delegate must exist")
	}
	for _, route := range []struct{ method, path string }{
		{"POST", "/api/v1/orchestrators/delegate"},
		{"GET", "/api/v1/orchestrators"},
		{"POST", "/api/v1/orchestrators"},
	} {
		if routeExists(r, route.method, route.path) {
			t.Errorf("%s %s must be removed", route.method, route.path)
		}
	}
}
```

Use whatever router-inspection helper the package already has; if none exists, assert on response status instead (`404` for the removed paths, not `404` for the new one).

- [ ] **Step 2: Run it to verify it fails**

```bash
cd backend && go test ./internal/httpd/... -run TestDelegateRouteMoved -v
```

Expected: FAIL.

- [ ] **Step 3: Edit the routes**

In `backend/internal/httpd/controllers/sessions.go`, replace lines 245-248 with a single registration alongside the other session routes:

```go
	r.Post("/sessions/delegate", c.delegateTask)
```

Delete `c.listOrchestrators`, `c.spawnOrchestrator`, `c.getOrchestrator` and their helpers.

- [ ] **Step 4: Clean the DTOs**

In `backend/internal/httpd/controllers/dto.go`, delete `OrchestratorIDParam` (`:1007`) and remove `Kind` and `RequestedBy` from `SpawnSessionRequest` (`:203`) and `DelegateTaskRequest` (`:721`). Remove the same fields from `DelegateTaskInput` (`service/session/delegation.go:26`) and its use at `:64`.

Leave `decodeJSON` in place on every session endpoint — its leniency is what lets an un-updated mobile build keep sending `"kind":"worker"` without a 400.

- [ ] **Step 5: Update the spec generator and regenerate**

Update the route entry in `backend/internal/httpd/apispec/specgen/build.go:1856` and remove the orchestrator operations, then:

```bash
npm run api
```

- [ ] **Step 6: Run the HTTP tests**

```bash
cd backend && go test ./internal/httpd/... 2>&1 | tail -20
```

Expected: PASS. The spec-drift and route-parity tests must be green.

- [ ] **Step 7: Commit**

```bash
git add backend/ frontend/src/api/schema.ts
git commit -m "$(cat <<'EOF'
feat(api)!: move delegate to /sessions/delegate and drop orchestrator routes

The New Task dialog's session-creation endpoint lived under the
/orchestrators prefix; it is renamed rather than removed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Phase 5 — CLI

### Task 9: Delete the orchestration commands

**Files:**
- Delete: `backend/internal/cli/{orchestrator,board,inbox,send,spawn}.go` and their `_test.go` files
- Modify: `backend/internal/cli/root.go:189,190,202,203,204`
- Modify: `backend/internal/telemetrymeta/cli.go`

**Interfaces:**
- Consumes: Task 8's HTTP surface.
- Produces: an `opr` binary without `orchestrator`, `board`, `inbox`, `send`, `spawn`.

`opr send`'s HTTP route (`POST /sessions/{id}/send`) stays — only the CLI wrapper goes. `opr hooks`, `ptyhost`, `attach`, `pane-capture`, `launch`, `daemon`, `start`, `stop`, `dev`, `doctor`, `version`, `browser`, `preview`, `pr`, `review`, `session`, `project`, `status`, `agent` all stay.

- [ ] **Step 1: Write the failing test**

Add to `backend/internal/cli/root_test.go`:

```go
func TestRootCommandHasNoOrchestrationCommands(t *testing.T) {
	root := newRootCommand(context.Background(), deps{}) // match the package's existing constructor
	removed := map[string]bool{"orchestrator": true, "board": true, "inbox": true, "send": true, "spawn": true}
	kept := map[string]bool{"hooks": true, "ptyhost": true, "browser": true, "preview": true, "session": true, "project": true, "status": true}
	for _, cmd := range root.Commands() {
		if removed[cmd.Name()] {
			t.Errorf("command %q must be removed", cmd.Name())
		}
		delete(kept, cmd.Name())
	}
	for name := range kept {
		t.Errorf("command %q must still be registered", name)
	}
}
```

Match the existing constructor's signature — check how `root_test.go` already builds the root command.

- [ ] **Step 2: Run it to verify it fails**

```bash
cd backend && go test ./internal/cli/ -run TestRootCommandHasNoOrchestration -v
```

Expected: FAIL.

- [ ] **Step 3: Delete the command files**

```bash
git rm backend/internal/cli/orchestrator.go backend/internal/cli/orchestrator_test.go \
       backend/internal/cli/board.go backend/internal/cli/board_test.go \
       backend/internal/cli/inbox.go backend/internal/cli/inbox_test.go \
       backend/internal/cli/send.go backend/internal/cli/send_test.go \
       backend/internal/cli/spawn.go backend/internal/cli/spawn_test.go
```

- [ ] **Step 4: Remove the registrations**

In `backend/internal/cli/root.go`, delete the `root.AddCommand` lines for `newSpawnCommand`, `newSendCommand`, `newOrchestratorCommand`, `newBoardCommand`, `newInboxCommand`.

- [ ] **Step 5: Remove the telemetry entries**

```bash
grep -n "opr orchestrator\|opr board\|opr inbox\|opr send\|opr spawn" backend/internal/telemetrymeta/cli.go
```

Delete those map entries.

- [ ] **Step 6: Build and test**

```bash
cd backend && go build ./... && go test ./internal/cli/ ./internal/telemetrymeta/ 2>&1 | tail -20
```

Expected: PASS. Fix remaining references (e2e and completion tests may name the removed commands).

- [ ] **Step 7: Commit**

```bash
git add -A backend/
git commit -m "$(cat <<'EOF'
feat(cli)!: remove orchestrator, board, inbox, send and spawn commands

The send HTTP route is untouched; only its CLI wrapper is removed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 8: Run the full backend gate**

```bash
npm run lint
```

Expected: `go test ./...` green and golangci-lint clean. The backend is now complete.

---

# Phase 6 — Single locale

### Task 10: Delete every locale but English

**Files:**
- Delete: `frontend/src/renderer/i18n/{de,es,fr,ja,ko,pt-BR,zh-CN}.json`
- Delete: `frontend/src/renderer/i18n/renderer-coverage.test.ts`
- Modify: `frontend/src/shared/ui-locale.ts`, `frontend/src/renderer/i18n/{index.ts,instance.ts,locales.ts,messages.ts,i18next.d.ts,instance.test.ts}`
- Modify: `frontend/src/renderer/components/settings/GeneralSettingsSection.tsx`

**Interfaces:**
- Consumes: nothing.
- Produces: an i18next instance with exactly one resource bundle, `en`. Every `t("key")` call site is **unchanged** — 1238 of them across 93 files stay exactly as they are.

This runs before the settings and i18n task so that task only ever edits `en.json`.

- [ ] **Step 1: Write the failing test**

Add to `frontend/src/renderer/i18n/instance.test.ts`:

```ts
it("ships exactly one locale", () => {
	expect(Object.keys(i18n.options.resources ?? {})).toEqual(["en"]);
});

it("resolves a key through the English bundle", () => {
	expect(i18n.t("zone.working")).not.toEqual("zone.working");
});
```

Use whatever the file already imports as the instance; if `zone.working` is not a real key, pick any key present in `en.json` and assert it resolves to something other than itself.

- [ ] **Step 2: Run it to verify it fails**

```bash
cd frontend && npm test -- i18n/instance
```

Expected: FAIL — eight resource bundles are registered.

- [ ] **Step 3: Delete the locale files**

```bash
cd frontend/src/renderer/i18n
git rm de.json es.json fr.json ja.json ko.json pt-BR.json zh-CN.json renderer-coverage.test.ts
```

`renderer-coverage.test.ts` exists to enforce key parity across locales; with one locale there is nothing to compare.

- [ ] **Step 4: Collapse the locale plumbing**

In `frontend/src/shared/ui-locale.ts`, reduce `APP_LOCALES` to `["en"] as const`, make `DEFAULT_LOCALE` `"en"`, and make `coerceLocale` always return `"en"`. Then simplify the consumers:

- `i18n/instance.ts`: register only the `en` bundle; drop the other imports.
- `i18n/index.ts`, `messages.ts`, `i18next.d.ts`: drop references to the removed bundles.
- `i18n/locales.ts`: `documentLang` now always returns `"en"`; delete the file if nothing else imports it and set `document.documentElement.lang = "en"` at its single call site.

Prefer deleting the abstraction over keeping a one-element list where a type or function exists only to choose between locales.

- [ ] **Step 5: Remove the language selector**

In `frontend/src/renderer/components/settings/GeneralSettingsSection.tsx`, delete the language `<Select>` and its label, the `changeLanguage` handler and any persisted locale preference it writes. Remove the corresponding key from `en.json` and the setting from the settings type if it is not read elsewhere.

```bash
grep -rn "changeLanguage\|coerceLocale\|APP_LOCALES\|DEFAULT_LOCALE" frontend/src --include="*.ts" --include="*.tsx"
```

Clear every remaining hit.

- [ ] **Step 6: Typecheck, test and lint**

```bash
npm run frontend:typecheck && cd frontend && npm test && npm run lint
```

Expected: all green. `GlobalSettingsForm.test.tsx` and other settings tests that assert a language control must lose those assertions.

- [ ] **Step 7: Commit**

```bash
git add -A frontend/
git commit -m "$(cat <<'EOF'
feat(i18n)!: ship English only

Deletes the seven non-English bundles, the key-parity coverage test, the
language selector and the locale plumbing. The i18next instance and all
1238 t() call sites are unchanged.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Phase 7 — Renderer

### Task 11: Remove orchestrator helpers and unfilter the board

**Files:**
- Modify: `frontend/src/renderer/types/workspace.ts:286-288`
- Modify: `frontend/src/renderer/components/SessionsBoard.tsx:22-56,114,127-161,240-256`
- Delete: `frontend/src/renderer/components/OrchestratorActivityIndicator.tsx`, `OrchestratorReplacementDialog.tsx`, `lib/spawn-orchestrator.ts`, `lib/restart-orchestrator.ts` and their tests
- Test: `frontend/src/renderer/components/SessionsBoard.test.tsx`

**Interfaces:**
- Consumes: Task 8's `schema.ts`.
- Produces: `workspace.ts` without `isOrchestratorSession`, `workerSessions`, `newestActiveOrchestrator`, `orchestratorHealth`, `hasConfiguredOrchestratorAgent`.

**Do not touch `SessionsBoard.tsx:116`'s `w.kind === "single_repo"`** — that is project kind.

- [ ] **Step 1: Write the failing test**

Add to `frontend/src/renderer/components/SessionsBoard.test.tsx`:

```tsx
it("places a needs-input session in the action column and a review session in pending", () => {
	renderBoard({
		sessions: [
			makeSession({ id: "a", status: "needs_input" }),
			makeSession({ id: "b", status: "review_pending" }),
			makeSession({ id: "c", status: "working" }),
		],
	});
	expect(within(screen.getByTestId("board-column-action")).getByText(/a/)).toBeInTheDocument();
	expect(within(screen.getByTestId("board-column-pending")).getByText(/b/)).toBeInTheDocument();
	expect(within(screen.getByTestId("board-column-working")).getByText(/c/)).toBeInTheDocument();
});
```

Match the file's existing render helper and test-id convention — columns carry `data-column={col.zone}` at `SessionsBoard.tsx:563`, so query by that if there is no `board-column-<zone>` test id.

- [ ] **Step 2: Run it**

```bash
cd frontend && npm test -- SessionsBoard
```

Expected: PASS already (this pins current behaviour before the edit — it is the regression guard, so confirm green, then keep it green).

- [ ] **Step 3: Unfilter the board and delete the helpers**

In `SessionsBoard.tsx` line 114:

```tsx
	const sessions = workspaces.flatMap((w) => w.sessions);
```

Delete the orchestrator imports (lines 22-24, 51-56), the orchestrator state and effects (127-161), `openOrchestrator` (240-256), and the header strip JSX that uses them. In `types/workspace.ts`, delete `isOrchestratorSession`, `workerSessions`, `newestActiveOrchestrator`, `orchestratorHealth`, `hasConfiguredOrchestratorAgent`.

```bash
git rm frontend/src/renderer/components/OrchestratorActivityIndicator.tsx \
       frontend/src/renderer/components/OrchestratorReplacementDialog.tsx \
       frontend/src/renderer/lib/spawn-orchestrator.ts \
       frontend/src/renderer/lib/spawn-orchestrator.test.ts \
       frontend/src/renderer/lib/restart-orchestrator.ts \
       frontend/src/renderer/lib/restart-orchestrator.test.ts
```

- [ ] **Step 4: Re-run the board test**

```bash
cd frontend && npm test -- SessionsBoard
```

Expected: PASS — the column assignment must be unchanged.

- [ ] **Step 5: Commit**

```bash
git add -A frontend/src/renderer/
git commit -m "$(cat <<'EOF'
refactor(renderer): drop orchestrator helpers and the board header strip

Column assignment is unchanged: zones come from session status, never
from session kind.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Clean the shell chrome

**Files:**
- Modify: `frontend/src/renderer/components/Sidebar.tsx`, `ShellTopbar.tsx`, `CommandPalette.tsx`, `KeyboardShortcutsDialog.tsx`, `BoardEmptyStates.tsx`, `DashboardSubhead.tsx`, `CreateProjectAgentSheet.tsx`
- Modify: `frontend/src/renderer/routes/_shell.tsx`, `stores/ui-store.ts`

**Interfaces:**
- Consumes: Task 11's `workspace.ts`.
- Produces: no orchestrator state in `ui-store` (`orchestratorStartupErrors`, `orchestratorReplacementError` and their setters are gone).

- [ ] **Step 1: Delete the store slice**

In `frontend/src/renderer/stores/ui-store.ts`, delete `orchestratorStartupErrors`, `orchestratorReplacementError`, `setOrchestratorStartupError`, `setOrchestratorReplacementError` and their types.

- [ ] **Step 2: Typecheck to find every consumer**

```bash
npm run frontend:typecheck 2>&1 | head -40
```

- [ ] **Step 3: Work through the errors**

Delete each orchestrator branch: the sidebar's orchestrator row and section, the topbar's orchestrator control, the command-palette entries, the keyboard-shortcut rows, the orchestrator empty state in `BoardEmptyStates`, the orchestrator copy in `DashboardSubhead`, the orchestrator agent picker in `CreateProjectAgentSheet`, and the orchestrator route branch in `_shell.tsx`.

- [ ] **Step 4: Typecheck clean**

```bash
npm run frontend:typecheck
```

Expected: no errors.

- [ ] **Step 5: Run the renderer suite**

```bash
cd frontend && npm test
```

Expected: PASS after deleting orchestrator test cases from `Sidebar.test.tsx`, `ShellTopbar.test.tsx`, `CommandPalette.test.tsx`, `KeyboardShortcutsDialog.test.tsx`, `board-empty-states.test.tsx`, `workspace.test.ts`.

- [ ] **Step 6: Commit**

```bash
git add -A frontend/src/renderer/
git commit -m "$(cat <<'EOF'
refactor(renderer): remove orchestrator state from the shell chrome

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Project settings, the New Task delegate path, and i18n

**Files:**
- Modify: `frontend/src/renderer/components/ProjectSettingsForm.tsx:11,13,107-225,332`
- Modify: `frontend/src/renderer/components/TaskComposer.tsx:95`
- Modify: `frontend/src/renderer/i18n/en.json`
- Test: `frontend/src/renderer/components/ProjectSettingsForm.test.tsx`, `TaskComposer.test.tsx`

**Interfaces:**
- Consumes: Task 6's `ProjectConfig.Harness`, Task 8's `/sessions/delegate`, Task 10's single locale.
- Produces: a settings form with one agent selector writing `config.agent`.

- [ ] **Step 1: Point the composer at the new route**

In `TaskComposer.tsx:95`:

```tsx
				const { data, error } = await apiClient.POST("/api/v1/sessions/delegate", {
```

- [ ] **Step 2: Rewrite the settings form**

Replace `orchestratorAgent` / `orchestratorModel` / `orchestratorMode` form state with the single agent selector writing `config.agent` (was `config.worker.agent`). Delete the `spawnOrchestrator` import and the replacement flow at `:217-225`, `newestActiveOrchestrator` at `:107`, `initialOrchestratorAgent` at `:130`, and the agent-rules input. `missingRequiredAgent` becomes:

```tsx
	const missingRequiredAgent = form.agent === "";
```

- [ ] **Step 3: Remove the orchestrator i18n keys**

```bash
grep -n "orchestrator" frontend/src/renderer/i18n/en.json
```

Delete every orchestrator key, including `settings.project.replaceOrchestratorFailed`. Task 10 removed the other locales, so `en.json` is the only file to edit.

- [ ] **Step 4: Typecheck and test**

```bash
npm run frontend:typecheck && cd frontend && npm test
```

Expected: PASS. Update `ProjectSettingsForm.test.tsx` (62 orchestrator references) and `TaskComposer.test.tsx` to the new shape.

- [ ] **Step 5: Lint**

```bash
npm run frontend:lint
```

Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add -A frontend/
git commit -m "$(cat <<'EOF'
feat(renderer)!: one agent selector per project, delegate via /sessions/delegate

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: Renderer hooks and the Playwright fake bridge

**Files:**
- Modify: `frontend/src/renderer/hooks/useWorkspaceQuery.ts:73,94`
- Modify: `frontend/src/renderer/hooks/useWorkspaceQuery.test.tsx`
- Modify: `frontend/e2e/support/fake-bridge.ts:259-268`
- Modify: `frontend/e2e/workbench.spec.ts`, `frontend/e2e/terminal-viewport-retention.spec.ts`

**Interfaces:**
- Consumes: Task 13's renderer.
- Produces: a workspace query that maps no `kind` and no `orchestratorAgent`; an e2e fake bridge that serves only ordinary sessions.

`useWorkspaceQuery` is the renderer's read model. It still maps `session.kind` and `project.orchestratorAgent`, both of which no longer exist on the wire after Task 8, so it must be updated or every session arrives with a stale field.

- [ ] **Step 1: Strip the mapping**

In `frontend/src/renderer/hooks/useWorkspaceQuery.ts`, delete line 73's `orchestratorAgent` mapping and line 94's `kind` mapping entirely. Remove `kind` and `orchestratorAgent` from the `WorkspaceSession` / project view types in `types/workspace.ts` if Task 10 left them.

- [ ] **Step 2: Typecheck**

```bash
npm run frontend:typecheck
```

Expected: errors at any remaining reader of those fields. Delete each reader.

- [ ] **Step 3: Fix the fake bridge**

In `frontend/e2e/support/fake-bridge.ts`, delete the `orchestratorAgent: "codex"` property (line 259) and the entire synthetic orchestrator session object (lines 262-268). The fixture must serve only ordinary sessions.

- [ ] **Step 4: Update the e2e specs**

```bash
grep -n "rchestrat" frontend/e2e/workbench.spec.ts frontend/e2e/terminal-viewport-retention.spec.ts
```

Delete assertions that expect an orchestrator row, card or terminal handle. Do not weaken unrelated assertions to make a spec pass — if a spec depended on the orchestrator session merely to have two sessions present, add a second ordinary session instead.

- [ ] **Step 5: Run the renderer suite and the e2e typecheck**

```bash
npm run frontend:typecheck && npm run typecheck:e2e && cd frontend && npm test
```

Expected: all green.

- [ ] **Step 6: Run the renderer e2e gate**

```bash
cd frontend && npm run test:e2e:renderer
```

Expected: PASS. If the Playwright browser is not installed in this environment, record that the gate was skipped and why, rather than claiming it passed.

- [ ] **Step 7: Commit**

```bash
git add -A frontend/
git commit -m "$(cat <<'EOF'
refactor(renderer): drop session kind from the workspace query and e2e fixtures

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Phase 8 — Mobile

### Task 15: Delete the mobile orchestrator feature

**Files:**
- Delete: `packages/mobile/lib/feature/orchestrator/**` (9 files), `packages/mobile/test/feature/orchestrator/**` (6 files), `packages/mobile/lib/feature/sessions/data/model/orchestrator_model.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`, `core/utils/app_constants.dart`, `core/app_themes/colors/app_skin.dart`, `core/api/api_request_helpers/end_points.dart`

**Interfaces:**
- Consumes: Task 8's HTTP surface.
- Produces: no orchestrator feature, no `OrchestratorModel`, no `EndPoints.orchestrators`.

**`board_snapshot.dart` is NOT deleted** — it also carries `sessions`, `projects` and `accountLabels`. Only its `orchestrators` field goes.

- [ ] **Step 1: Delete the feature**

```bash
cd packages/mobile
git rm -r lib/feature/orchestrator test/feature/orchestrator
git rm lib/feature/sessions/data/model/orchestrator_model.dart
```

- [ ] **Step 2: Remove the registrations and the endpoint**

```bash
grep -rn "rchestrat" lib/core/
```

Delete the service-locator registrations, the `app_constants` entries, the `app_skin` orchestrator colour, and `EndPoints.orchestrators`.

- [ ] **Step 3: Trim BoardSnapshot**

In `lib/feature/sessions/data/model/board_snapshot.dart`, delete the `orchestrators` field, its constructor parameter, the `OrchestratorModel` import and the `props` entry. Keep `sessions`, `projects`, `accountLabels`.

- [ ] **Step 4: Analyze**

```bash
flutter analyze 2>&1 | tail -30
```

Expected: errors only at the remaining call sites, which Task 16 fixes.

- [ ] **Step 5: Commit**

```bash
git add -A packages/mobile/
git commit -m "$(cat <<'EOF'
feat(mobile)!: delete the orchestrator feature and model

BoardSnapshot is kept and loses only its orchestrators field.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: Four-tab nav, three-call fan-out, and session routing

**Files:**
- Modify: `packages/mobile/lib/core/app_routes/home_shell.dart:5,20,50,87-90`
- Modify: `packages/mobile/lib/feature/sessions/data/data_source/sessions_remote_data_source.dart:5,22-44`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart:15,46,105,130`
- Modify: `packages/mobile/lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart:73-84`
- Test: `packages/mobile/test/feature/sessions/data/data_source/sessions_remote_data_source_test.dart`

**Interfaces:**
- Consumes: Task 15's deletions.
- Produces: a 4-item `BottomNavigationBar`; `SessionsRemoteDataSource.fetchBoard` issuing three parallel calls after the `/sessions` await.

> **Preserve the sequential auth probe.** `sessions_remote_data_source.dart:22` awaits `/sessions` **alone** before fanning out. The daemon locks a device out for a minute after 5 failed auths, so a stale password under `Future.wait` burns 4 failures per poll tick and arms the lockout before the user can re-pair. A test pins the call order. Removing one future must **not** collapse the rest into the first await.

- [ ] **Step 1: Write the failing test**

In `sessions_remote_data_source_test.dart`, update the call-order test to expect three post-`/sessions` calls and no `/orchestrators`:

```dart
test('awaits /sessions alone before fanning out, and never calls /orchestrators', () async {
  final calls = <String>[];
  final consumer = FakeApiConsumer(onGet: (path) {
    calls.add(path);
    return okResponse(path);
  });
  await SessionsRemoteDataSource(consumer).fetchBoard();

  expect(calls.first, EndPoints.sessions);
  expect(calls, isNot(contains('/api/v1/orchestrators')));
  expect(calls.length, 4);
});
```

Match the file's existing fake and helper names.

- [ ] **Step 2: Run it to verify it fails**

```bash
cd packages/mobile && flutter test --plain-name 'awaits /sessions alone'
```

Expected: FAIL.

- [ ] **Step 3: Trim the fan-out**

In `sessions_remote_data_source.dart`, delete the `orchestratorsFuture` (line 24), its await (line 27), the `.where((s) => s.kind != 'orchestrator')` filter (line 42) and the `orchestrators:` argument (line 44). Keep line 22's standalone `await` of `EndPoints.sessions` exactly as it is, and keep the remaining three futures created **before** their awaits.

- [ ] **Step 4: Fix the cubit and the route screen**

In `sessions_cubit.dart`, delete the `OrchestratorModel` import (`:15`), the `orchestrators` field (`:46`), its reset (`:105`) and its assignment (`:130`). In `session_route_screen.dart`, delete the orchestrator fallback loop (lines 73-84); the `cubit.sessions` loop above it already resolves normal sessions.

- [ ] **Step 5: Drop the nav tab**

In `home_shell.dart`, delete the `OrchestratorScreen` import (`:5`), its entry in the screen list (`:50`) and the `BottomNavigationBarItem` (`:88`). Renumber every remaining tab index — check `_controllers`, `HomeShell.selectedTab.value` assignments (including the `onOpenBoard: () => HomeShell.selectedTab.value = 0` that came from the deleted screen) and `controllerFor(int tab)` (`:20`).

- [ ] **Step 6: Analyze and test**

```bash
cd packages/mobile && flutter analyze && flutter test
```

Expected: `flutter analyze` prints "No issues found!" and the suite passes.

- [ ] **Step 7: Commit**

```bash
git add -A packages/mobile/
git commit -m "$(cat <<'EOF'
feat(mobile)!: four-tab nav and a three-call session fan-out

Keeps the standalone /sessions await that guards against the daemon's
five-failure auth lockout.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Phase 9 — Verification

### Task 17: Pin the protected behaviours and verify in the real app

**Files:**
- Create/Modify: `backend/internal/service/session/status_test.go`
- Create/Modify: `packages/mobile/test/feature/sessions/logic/session_status_test.dart`
- Create/Modify: `packages/mobile/test/feature/sessions/data/model/session_model_test.dart`

**Interfaces:**
- Consumes: every prior task.
- Produces: regression tests for spec §1.1.

- [ ] **Step 1: Write the backend state table test**

Add to `backend/internal/service/session/status_test.go`:

```go
func TestDeriveStatusCoversProtectedStates(t *testing.T) {
	now := time.Now()
	cases := []struct {
		name  string
		state domain.ActivityState
		want  domain.SessionStatus
	}{
		{"active is working", domain.ActivityActive, domain.StatusWorking},
		{"waiting input needs you", domain.ActivityWaitingInput, domain.StatusNeedsInput},
		{"blocked needs you", domain.ActivityBlocked, domain.StatusNeedsInput},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := domain.SessionRecord{Activity: domain.Activity{State: tc.state, LastActivityAt: now}}
			if got := deriveStatus(rec, nil, now, true); got != tc.want {
				t.Fatalf("deriveStatus = %s, want %s", got, tc.want)
			}
		})
	}
}
```

Match the package's existing constructors for `SessionRecord` and `Activity`.

- [ ] **Step 2: Run it**

```bash
cd backend && go test ./internal/service/session/ -run TestDeriveStatusCovers -v
```

Expected: PASS.

- [ ] **Step 3: Write the mobile state tests**

Add to `packages/mobile/test/feature/sessions/logic/session_status_test.dart`:

```dart
void main() {
  group('attentionOf', () {
    test('needs_input maps to respond', () {
      expect(attentionOf(SessionModel(id: 'a', status: 'needs_input')), AttentionLevel.respond);
    });
    test('review_pending maps to pending', () {
      expect(attentionOf(SessionModel(id: 'a', status: 'review_pending')), AttentionLevel.pending);
    });
    test('working maps to working', () {
      expect(attentionOf(SessionModel(id: 'a', status: 'working')), AttentionLevel.working);
    });
  });
}
```

Add to `packages/mobile/test/feature/sessions/data/model/session_model_test.dart`:

```dart
test('parses a payload with no kind key', () {
  final session = SessionModel.fromJson({'id': 'a', 'status': 'working'});
  expect(session.id, 'a');
  expect(session.kind, isNull);
});
```

- [ ] **Step 4: Run the mobile gates**

```bash
cd packages/mobile && flutter analyze && flutter test
```

Expected: "No issues found!" and a green suite.

- [ ] **Step 5: Run every gate**

```bash
npm run lint
npm run frontend:typecheck
cd frontend && npm test && npm run lint
cd ../packages/mobile && flutter analyze && flutter test
```

Expected: all green.

- [ ] **Step 6: Verify in the real app**

Follow the repo's verify recipe (Vite proxy + `OPERATOR_DEV_API_TARGET` against an isolated daemon, opening `127.0.0.1` rather than `localhost` for CORS, hash routes). Scrub `CLAUDE*` env vars from the dev shell first, or spawned agents skip transcripts.

Confirm, and record the evidence in the PR:

1. A session created from New Task launches with no `--append-system-prompt*` orchestrator text; its `system.md`, if written, holds only the branch-namespace block (plus the workspace block for a workspace project).
2. Driving that session to a permission prompt moves its card to **Needs you** on desktop **and** mobile.
3. Opening a PR from it moves the card to **In review** on both.
4. Mobile session chat sends a message and streams blocks and terminal output.
5. The sidebar activity state still flips — hooks are alive.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
test: pin session states and the no-kind wire payload

Guards the three systems the removal must not regress: mobile chat,
desktop session states, and both Kanban boards.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

---

# Phase 10 — Documentation

### Task 18: Remove orchestrator references from project documentation

**Files:**
- Modify: `AGENTS.md`, `CLAUDE.md`, `README.md`, `DESIGN.md`, `TERMINAL.md`
- Modify: `docs/architecture.md`, `docs/STATUS.md`, `docs/mobile-parity-ledger.md`, `docs/posthog-cost-controls.md`, `docs/opr-start-bootstrapper-and-npm-deprecation.md`

**Interfaces:**
- Consumes: every prior task.
- Produces: documentation with no reference to a subsystem that no longer exists.

Dangling references are the failure mode this project explicitly rejects: a breaking-change budget buys *complete* removals, not stale prose.

- [ ] **Step 1: Find every reference**

```bash
grep -rn "rchestrat" *.md docs/*.md | grep -v "\.worktrees/"
```

- [ ] **Step 2: Edit each file**

Rewrite, do not merely delete lines — a sentence that read "workers are spawned by an orchestrator" must become an accurate statement about how sessions are created now (from the New Task dialog, the tickets/plans subsystem, auto-review, or tracker intake). Specifically:

- `AGENTS.md`: remove the orchestrator from the repository-layout and session-model sections; update any `opr` command list that names `orchestrator`, `board`, `inbox`, `send` or `spawn`.
- `CLAUDE.md`: remove orchestrator guidance.
- `README.md` and `docs/architecture.md`: update the session model to a single session kind.
- `docs/STATUS.md`: record the removal.
- `docs/mobile-parity-ledger.md`: mark the orchestrator feature's rows as removed rather than ported — that file is the answer to "was this ever ported?", so it must say the feature was deleted, not go silent.

Leave historical documents that describe past milestones alone where they are explicitly historical; the ledger entry above is the pattern — state the outcome rather than erasing the record.

- [ ] **Step 3: Verify nothing live still references it**

```bash
grep -rn "rchestrat" *.md docs/*.md backend/ frontend/src/ packages/mobile/lib/ packages/mobile/test/   --include="*.md" --include="*.go" --include="*.ts" --include="*.tsx" --include="*.dart"   | grep -v "docs/superpowers/" | grep -v "\.worktrees/"
```

Expected: no hits outside `docs/superpowers/` (specs and plans are historical records and keep their text).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
docs: remove orchestrator references from project documentation

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```


## Deferred cleanup

After Task 18 lands, delete the superseded spec:

```bash
git rm docs/superpowers/specs/2026-09-20-operator-instructions-toggle-design.md
```

Its commit `c184e93a6` stays in history.
