# Orchestrator Leash and Autonomy (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grant the orchestrator authority to spawn, redirect, and kill workers on its own judgment, bounded by a daemon-enforced, client-attributed budget — landing together, because autonomy without the budget is an unbounded spawn loop.

**Architecture:** A new `spawned_by` column on `sessions` records which orchestrator (if any) asked for a spawn. `opr spawn` fills a new `requestedBy` wire field from `OPERATOR_SESSION_ID` when set; the spawn service resolves it against the live sessions in the target project and rejects a value that does not name a live, non-terminated orchestrator there. Two budgets are read from a new `orchestratorPolicy` project-config block and enforced in `Service.Spawn` before the session manager creates anything: a live-worker cap (counts every live worker, any spawner) and an hourly spawn-rate cap (counts only orchestrator-attributed spawns, i.e. rows with a non-empty `spawned_by`, in the trailing hour). Only requests carrying a valid `requestedBy` are checked against the budget; a human spawn (empty `requestedBy`) always succeeds. Exhaustion returns the standard error envelope with code `ORCHESTRATOR_BUDGET_EXHAUSTED`, naming the limit and — for the rate limit — the time it resets, computed from the oldest counted row rather than a timer. The orchestrator's system prompt is rewritten to authorize acting without asking, to teach the budget failure mode (queue, report, never retry in a loop), to restate the merge boundary for the autonomous framing, and to teach `opr session switch-agent` (the visible command behind the handoff protocol named in spec §9 — see the corrected-premises section below).

**Tech Stack:** Go 1.x, sqlc-generated SQLite queries, goose migrations, chi router, code-first OpenAPI (`npm run api`), Cobra CLI, table-driven Go tests with `httptest` and in-memory SQLite.

**Spec:** `docs/superpowers/specs/2026-09-11-autonomous-orchestrator-design.md` (§4 decisions, §5.4 the leash, §6 data model, §8 wire surface, §9 prompt, §10 enforcement honesty, §11 risks, §14 Phase 2). §10 and §11 matter more here than in Phases 0/1: this is the phase where the orchestrator starts spending money without a human in the loop.

## Corrected premises (verified 2026-09-12 against HEAD `be653407a`, fixed in the spec in this same change)

1. `cliInvocationActorType` is at `backend/internal/cli/root.go:245`, not `:243` — the spec said 243; the function itself (confirmed by direct read) is:
   ```go
   func cliInvocationActorType(cmd *cobra.Command) string {
       if strings.TrimSpace(cmd.CommandPath()) == "opr hooks" {
           return "agent"
       }
       if sessionIDPattern.MatchString(strings.TrimSpace(os.Getenv("OPERATOR_SESSION_ID"))) {
           return "agent"
       }
       return "user"
   }
   ```
   Fixed in the spec at `docs/superpowers/specs/2026-09-11-autonomous-orchestrator-design.md:283`.
2. `SpawnSessionRequest` is at `backend/internal/httpd/controllers/dto.go:196` (the `type SpawnSessionRequest struct` line; its doc comment starts at 195), not `:169`. Fixed in the spec at line 285.
3. §14's trailing instruction to delete the stale "the dispatcher reads it" comment at `backend/internal/lifecycle/manager.go:30` is **already done** — confirmed by a full-file grep of `manager.go` for "dispatcher reads": zero matches anywhere in the file, not just in the 25-40 window the spec pointed at. Noted in the spec at line 649-651. Phase 2 must not go looking for this comment.
4. Spec §9 says "Teach `opr session handoff`." The only CLI surface with that literal name is `opr session handoff submit` (`backend/internal/cli/session_switch.go:139-165`), which is `Hidden: true` and takes `--switch`, `--source-generation`, and `--file` flags — internal plumbing a *source agent generation* uses to submit its own handoff document mid-switch, not something an orchestrator would invoke with information it has on hand. The command an orchestrator would actually use to redirect a worker onto a different agent is the visible, non-hidden `opr session switch-agent <session-id> <target-harness>` (`session_switch.go:86-108`, `Short: "Switch a running session to another agent"`), which triggers the handoff protocol automatically. Task 5 teaches `opr session switch-agent`, not the hidden `handoff submit` plumbing — this satisfies the spec's intent (teach the orchestrator the redirect-to-a-different-agent capability) rather than its literal wording.
5. The spec's §6 migration snippet (`ALTER TABLE sessions ADD COLUMN spawned_by TEXT NOT NULL DEFAULT ''`) is correct and unchanged; no drift found there.
6. Confirmed no existing sqlc query or store method counts live sessions per project/kind or counts sessions by `spawned_by` and a time window — Task 4 adds both from scratch; there is nothing to reuse beyond the `CountPendingInboxEvents` pattern shape from Phase 1.
7. Confirmed only one live orchestrator can exist per project today: `Service.Spawn` (`backend/internal/service/session/service.go:205-222`) already locks per-project and returns the existing orchestrator instead of creating a second one when `cfg.Kind == domain.KindOrchestrator`. This resolves an ambiguity in spec §5.4/§6 ("spawns-per-hour counted from spawned_by") — because at most one orchestrator is ever live in a project, counting all rows with a non-empty `spawned_by` in a project is equivalent to counting per-orchestrator, so no extra "which orchestrator" bookkeeping is needed.

## Global Constraints

- **No code comments.** The user's standing global instruction. Go doc comments on exported identifiers are fine where sibling code already has them (Phase 1 precedent); narrative/explanatory comments are not.
- **No retry, backoff, escalation, attempt counter, `next_attempt_at`, or timer of any kind, anywhere.** The rate-limit "resets at" time is computed by reading the oldest counted row on demand (a query, not a stored countdown) — it is not a timer, and nothing in this phase may schedule a re-check.
- **The budget must be enforced server-side**, in `Service.Spawn`, not merely stated in the prompt.
- **The budget is client-asserted.** `requestedBy` is whatever the CLI sends from `OPERATOR_SESSION_ID`. An orchestrator that unsets that variable before calling `opr spawn` is indistinguishable from a human and is not rate-limited. This is by design (spec §5.4, §10) — do not add any unspoofable enforcement.
- **No cost ceiling.** Do not add one, and do not add a token/spend counter as a substitute.
- The CLI is a thin client: daemon HTTP through the shared helpers in `internal/cli/client.go` only. CLI DTOs are hand-mirrored plain-string structs; never import `httpd/controllers` into `internal/cli`.
- After editing `controllers/dto.go`, run `npm run api` and commit `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts` in the same commit as the Go change.
- Any new named DTO/domain type reflected into the API needs a `schemaNames` entry in `backend/internal/httpd/apispec/specgen/build.go` if `npm run api` reports an unnamed-schema error.
- Every migration file needs an entry in `shippedMigrations` in `backend/internal/storage/sqlite/migrate_burned_versions_test.go` in the same change — `TestMigrationVersionLedger` fails otherwise. It currently ends at `106: "0106_orchestrator_inbox.sql",`.
- Migration queries go in `backend/internal/storage/sqlite/queries/*.sql`; generated code comes from `npm run sqlc`, never hand-edited.
- Never weaken an existing test. Deleting one is legitimate only when the feature deliberately reverses the behavior it guards, with a replacement of equal or greater strength, justified in the final report.
- Gate for every task: `npm run lint` from the repo root, and `cd backend && go test ./internal/httpd/...` for spec drift.
- Do not restart or stop the user's daemon (pid 97452, `~/.operator`). End-to-end checks use an isolated daemon under `OPERATOR_DATA_DIR`/`OPERATOR_RUN_FILE` in a scratch directory, run via `opr daemon` (not `opr start`), seeded with `sqlite3` directly per the recipe in `docs/superpowers/plans/2026-09-12-orchestrator-ears-phase-1.md:2146-2171`.

## File Structure

| File | Responsibility | Task |
| --- | --- | --- |
| `backend/internal/storage/sqlite/migrations/0107_sessions_spawned_by.sql` | New `spawned_by` column | 1 |
| `backend/internal/storage/sqlite/migrate_burned_versions_test.go` | `shippedMigrations[107]` entry | 1 |
| `backend/internal/domain/session.go` | `SessionRecord.SpawnedBy` field | 1 |
| `backend/internal/ports/session.go` | `SpawnConfig.RequestedBy` field | 1 |
| `backend/internal/session_manager/manager.go` (`seedRecord`) | Copies `RequestedBy` into `SpawnedBy` | 1 |
| `backend/internal/storage/sqlite/queries/sessions.sql` | `InsertSession` gains `spawned_by`; new `GetSession`/`ListSessions` column if not already `SELECT *` | 1 |
| `backend/internal/storage/sqlite/store/session_store.go` | `recordToInsert`/row-to-record mapper carry `SpawnedBy` | 1 |
| `backend/internal/domain/projectconfig.go` | `OrchestratorPolicy` type, defaults, `ProjectConfig.OrchestratorPolicy` field | 2 |
| `backend/internal/httpd/apispec/specgen/build.go` | `schemaNames["DomainOrchestratorPolicy"]` | 2 |
| `backend/internal/httpd/controllers/dto.go` | `SpawnSessionRequest.RequestedBy` | 3 |
| `backend/internal/httpd/controllers/sessions.go` (`spawn` handler) | Thread `in.RequestedBy` into `ports.SpawnConfig` | 3 |
| `backend/internal/cli/spawn.go` | `spawnRequest.RequestedBy`, filled from `OPERATOR_SESSION_ID` | 3 |
| `backend/internal/storage/sqlite/queries/sessions.sql` | `CountLiveSessionsByProjectAndKind`, `CountSessionsSpawnedBySince`, `OldestSessionSpawnedBySince` | 4 |
| `backend/internal/storage/sqlite/store/session_store.go` | Store methods for the three queries above | 4 |
| `backend/internal/service/session/service.go` | `Store` interface gains the 3 methods; `requestedBy` validation and budget enforcement in `spawn` | 4 |
| `backend/internal/httpd/apierr/apierr.go` | No new helper needed — reuse `apierr.Invalid`/`apierr.Conflict` | 4 |
| `backend/internal/session_manager/prompt.go` | `orchestratorSystemPrompt` rewrite: autonomy grant, budget behavior, merge boundary, `opr session switch-agent` | 5 |

---

### Task 1: `spawned_by` column and threading from spawn to storage

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0107_sessions_spawned_by.sql`
- Modify: `backend/internal/storage/sqlite/migrate_burned_versions_test.go`
- Modify: `backend/internal/domain/session.go`
- Modify: `backend/internal/ports/session.go`
- Modify: `backend/internal/session_manager/manager.go`
- Modify: `backend/internal/storage/sqlite/queries/sessions.sql`
- Modify: `backend/internal/storage/sqlite/store/session_store.go`
- Regenerated: `backend/internal/storage/sqlite/gen/*`
- Test: `backend/internal/storage/sqlite/store/session_store_test.go`

**Interfaces:**
- Produces: `domain.SessionRecord.SpawnedBy domain.SessionID` (empty for human/system spawns); `ports.SpawnConfig.RequestedBy domain.SessionID`. Task 3 sets `RequestedBy` from the wire request; Task 4 reads `SpawnedBy` back out through `Store.GetSession`/`ListSessions` for budget counting.

- [ ] **Step 1: Write the migration**

```sql
-- +goose Up
ALTER TABLE sessions ADD COLUMN spawned_by TEXT NOT NULL DEFAULT '';

-- +goose Down
ALTER TABLE sessions DROP COLUMN spawned_by;
```

Match the format of `backend/internal/storage/sqlite/migrations/0103_add_sessions_workspace_mode.sql` exactly (no `StatementBegin`/`StatementEnd` wrappers needed for a single-statement migration; `modernc.org/sqlite` supports `DROP COLUMN`).

- [ ] **Step 2: Register the migration in the burned-versions ledger**

In `migrate_burned_versions_test.go`, append after the `106` entry:

```go
	107: "0107_sessions_spawned_by.sql",
```

- [ ] **Step 3: Run the ledger test**

```bash
cd backend && go test ./internal/storage/sqlite/ -run TestMigrationVersionLedger -v
```

Expected: PASS.

- [ ] **Step 4: Add `SpawnedBy` to the domain and port types**

In `backend/internal/domain/session.go`, add to `SessionRecord` (near `IsTerminated`/`Metadata`, per the existing field grouping):

```go
	// SpawnedBy is the orchestrator session id that requested this spawn, or
	// empty for a human or system spawn. Client-asserted: see spec section 5.4.
	SpawnedBy SessionID `json:"spawnedBy,omitempty"`
```

In `backend/internal/ports/session.go`, add to `SpawnConfig` (near `DisplayName`):

```go
	// RequestedBy is the orchestrator session id that asked for this spawn,
	// or empty for a human spawn. Persisted verbatim as SessionRecord.SpawnedBy.
	RequestedBy domain.SessionID
```

- [ ] **Step 5: Thread it through `seedRecord`**

In `backend/internal/session_manager/manager.go`, in `seedRecord` (`manager.go:2598-2611`), add `SpawnedBy: cfg.RequestedBy,` to the returned `domain.SessionRecord` literal, alongside the other `cfg.*`-derived fields.

- [ ] **Step 6: Add `spawned_by` to the sqlc insert query**

In `backend/internal/storage/sqlite/queries/sessions.sql`, add `spawned_by` to `InsertSession`'s column list and a trailing `?` placeholder (`sessions.sql:4-19`):

```sql
-- name: InsertSession :exec
INSERT INTO sessions (
    id, project_id, num, issue_id, kind, harness, reviewer_harness, display_name,
    activity_state, activity_last_at, first_signal_at, is_terminated,
    branch, workspace_path, workspace_mode, workspace_repo_path, diff_base_sha, diff_base_ref, runtime_handle_id,
    runtime_launch_id, agent_session_id, prompt,
    latest_user_prompt, latest_assistant_update, native_transcript_path,
    preview_url, preview_revision, preview_opened_revision, terminate_on_pr_merge, cleanup_generation, browser_capability_verifier,
    provider_conversation_id, controller_generation, spawned_by,
    created_at, updated_at, is_pinned, pinned_at, auto_inject_review
) VALUES (
    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
    ?, ?, ?, ?,
    ?, ?, ?, ?, ?
);
```

Find the sqlc query(ies) that back `GetSession` and `ListSessions` in the same file and confirm whether they use `SELECT *` (picks up `spawned_by` automatically once the migration lands and `npm run sqlc` regenerates) or an explicit column list (needs `spawned_by` added there too, plus the corresponding field in whatever generated row struct backs it). Check the actual query text before assuming either way.

- [ ] **Step 7: Map the new field in the store layer**

In `backend/internal/storage/sqlite/store/session_store.go`, in `recordToInsert` (`session_store.go:408-450`), add `SpawnedBy: rec.SpawnedBy,` to the returned `gen.InsertSessionParams` literal.

Find the row-to-`domain.SessionRecord` converter this package uses for reads (the function `GetSession`/`ListSessions` call to build their return values — grep this file for `func .*FromGen\|func .*ToRecord` near the top of the file) and add the `SpawnedBy` mapping there too, so a session read back after creation carries the value. Match whatever type sqlc actually generated for the new column (likely `domain.SessionID` directly, matching how `WorkerID` is handled in `orchestrator_inbox_store.go`, given this codebase's sqlc type overrides map typed ID columns directly — confirm against the regenerated code, don't assume).

- [ ] **Step 8: Regenerate sqlc code and build**

```bash
npm run sqlc
git status --short backend/internal/storage/sqlite/gen/
cd backend && go build ./...
```

Expected: `gen/models.go` and `gen/sessions.sql.go` (or equivalent) show the new field; the build fails at any call site still using the old `gen.InsertSessionParams` shape without `SpawnedBy` — there should be exactly one such call site (Step 7's edit), so a build failure here means Step 7 was incomplete.

- [ ] **Step 9: Write the failing store test**

In `backend/internal/storage/sqlite/store/session_store_test.go`, find the existing `CreateSession` test (or the closest analog) for the `newTestStore`/`seedProject` helper signatures already in this package, and add:

```go
func TestCreateSession_PersistsSpawnedBy(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	proj := seedProject(t, s, "proj-1")

	rec := domain.SessionRecord{
		ProjectID: proj,
		Kind:      domain.KindWorker,
		SpawnedBy: "proj-1-1",
		CreatedAt: time.Now().UTC(),
		UpdatedAt: time.Now().UTC(),
	}
	created, err := s.CreateSession(ctx, rec)
	if err != nil {
		t.Fatal(err)
	}
	if created.SpawnedBy != "proj-1-1" {
		t.Fatalf("created.SpawnedBy = %q, want proj-1-1", created.SpawnedBy)
	}

	got, ok, err := s.GetSession(ctx, created.ID)
	if err != nil || !ok {
		t.Fatalf("GetSession: ok=%v err=%v", ok, err)
	}
	if got.SpawnedBy != "proj-1-1" {
		t.Fatalf("GetSession(...).SpawnedBy = %q, want proj-1-1 (round-trip through storage)", got.SpawnedBy)
	}
}

func TestCreateSession_EmptySpawnedByForHumanSpawn(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	proj := seedProject(t, s, "proj-1")

	created, err := s.CreateSession(ctx, domain.SessionRecord{
		ProjectID: proj, Kind: domain.KindWorker,
		CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC(),
	})
	if err != nil {
		t.Fatal(err)
	}
	if created.SpawnedBy != "" {
		t.Fatalf("SpawnedBy = %q, want empty for a human spawn", created.SpawnedBy)
	}
}
```

Adjust helper names/signatures to whatever `newTestStore`/`seedProject` actually are in this package (checked in Phase 1's Task 2 already — reuse verbatim).

- [ ] **Step 10: Run tests to verify they pass**

```bash
cd backend && go test ./internal/storage/sqlite/store/ -run TestCreateSession_ -v
cd backend && go test ./internal/storage/sqlite/store/
```

- [ ] **Step 11: Run the full gate**

```bash
npm run lint
```

- [ ] **Step 12: Commit**

```bash
git add backend/internal/storage/sqlite/migrations/0107_sessions_spawned_by.sql \
        backend/internal/storage/sqlite/migrate_burned_versions_test.go \
        backend/internal/domain/session.go \
        backend/internal/ports/session.go \
        backend/internal/session_manager/manager.go \
        backend/internal/storage/sqlite/queries/sessions.sql \
        backend/internal/storage/sqlite/store/session_store.go \
        backend/internal/storage/sqlite/store/session_store_test.go \
        backend/internal/storage/sqlite/gen/
git commit -m "feat(storage): add sessions.spawned_by and thread it through spawn

Migration 0107 adds the column the leash's spawn-rate query counts from
(spec section 6). SpawnConfig.RequestedBy carries the caller through
seedRecord into the stored record; empty means a human or system spawn.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `orchestratorPolicy` project config block

**Files:**
- Modify: `backend/internal/domain/projectconfig.go`
- Modify: `backend/internal/httpd/apispec/specgen/build.go`
- Test: `backend/internal/domain/projectconfig_test.go`

**Interfaces:**
- Produces: `domain.OrchestratorPolicy{MaxLiveWorkers, MaxSpawnsPerHour int}`; `domain.DefaultMaxLiveWorkers = 8`; `domain.DefaultMaxSpawnsPerHour = 20`; `domain.ProjectConfig.OrchestratorPolicy OrchestratorPolicy`. Task 4 reads `project.Config.OrchestratorPolicy.WithDefaults()` to get the effective limits.

**Chosen defaults and reasoning** (also restated in the final report):
- `MaxLiveWorkers = 8`. The spec's own §12 rationale for not needing a task queue ("an agent holding a list in context with a cap of N workers... gain only at 10+ simultaneous tasks") implies N should sit comfortably below 10. 8 gives an orchestrator real room to run several parallel workstreams without approaching the point where a queue would be needed, while still being a small enough number that a spawn loop is caught in single digits of extra sessions, not dozens.
- `MaxSpawnsPerHour = 20`. This bounds spawn *velocity*, not standing concurrency — a well-behaved orchestrator reacting to inbox events over a busy hour (several workers finishing, each triggering a redirect-or-respawn decision) would rarely exceed single digits per hour; 20 gives generous headroom (one every 3 minutes, sustained for an hour) while still cutting off a tight loop that would otherwise spawn hundreds.

Both are declared, not derived from measurement — there is no production usage data for this feature yet (`operator-has-no-users-yet`). State this plainly in the final report rather than presenting them as validated.

- [ ] **Step 1: Write the failing config tests**

In `backend/internal/domain/projectconfig_test.go` (create if it doesn't exist — check first; `projectconfig.go` likely already has a sibling test file with a `WithDefaults`/`Validate` test to extend):

```go
func TestOrchestratorPolicy_WithDefaults_FillsOnlyUnsetFields(t *testing.T) {
	p := domain.OrchestratorPolicy{MaxLiveWorkers: 3}.WithDefaults()
	if p.MaxLiveWorkers != 3 {
		t.Fatalf("MaxLiveWorkers = %d, want the explicitly set 3 preserved", p.MaxLiveWorkers)
	}
	if p.MaxSpawnsPerHour != domain.DefaultMaxSpawnsPerHour {
		t.Fatalf("MaxSpawnsPerHour = %d, want default %d", p.MaxSpawnsPerHour, domain.DefaultMaxSpawnsPerHour)
	}
}

func TestOrchestratorPolicy_WithDefaults_OnZeroValue(t *testing.T) {
	p := domain.OrchestratorPolicy{}.WithDefaults()
	if p.MaxLiveWorkers != domain.DefaultMaxLiveWorkers || p.MaxSpawnsPerHour != domain.DefaultMaxSpawnsPerHour {
		t.Fatalf("got %+v, want both defaults", p)
	}
}

func TestProjectConfig_WithDefaults_FillsOrchestratorPolicy(t *testing.T) {
	c := domain.ProjectConfig{}.WithDefaults()
	if c.OrchestratorPolicy.MaxLiveWorkers != domain.DefaultMaxLiveWorkers {
		t.Fatalf("ProjectConfig.WithDefaults() did not cascade into OrchestratorPolicy: %+v", c.OrchestratorPolicy)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && go test ./internal/domain/ -run TestOrchestratorPolicy -v
```

Expected: build failure — the type doesn't exist yet.

- [ ] **Step 3: Add the type, defaults, and field**

In `backend/internal/domain/projectconfig.go`, near `DefaultBranchName`/`DefaultProjectConfig` (`projectconfig.go:119-137`):

```go
const (
	DefaultMaxLiveWorkers   = 8
	DefaultMaxSpawnsPerHour = 20
)

// OrchestratorPolicy bounds an orchestrator's spawn authority for a project.
// Enforced daemon-side in the spawn service (spec section 5.4); this struct
// only carries the configured limits, never a live count.
type OrchestratorPolicy struct {
	MaxLiveWorkers   int `json:"maxLiveWorkers,omitempty"`
	MaxSpawnsPerHour int `json:"maxSpawnsPerHour,omitempty"`
}

// WithDefaults fills only fields left unset (non-positive). A set field is
// always preserved.
func (p OrchestratorPolicy) WithDefaults() OrchestratorPolicy {
	if p.MaxLiveWorkers <= 0 {
		p.MaxLiveWorkers = DefaultMaxLiveWorkers
	}
	if p.MaxSpawnsPerHour <= 0 {
		p.MaxSpawnsPerHour = DefaultMaxSpawnsPerHour
	}
	return p
}
```

Add the field to `ProjectConfig` (`projectconfig.go:20-66`), near `Orchestrator RoleOverride`:

```go
	OrchestratorPolicy OrchestratorPolicy `json:"orchestratorPolicy,omitempty"`
```

Do **not** add it to `RoleOverride` (`projectconfig.go:110-114`) — that struct is shared with `Worker`, where a spawn budget is meaningless (spec §8).

In `ProjectConfig.WithDefaults()` (`projectconfig.go:130-137`), add:

```go
	c.OrchestratorPolicy = c.OrchestratorPolicy.WithDefaults()
```

alongside the existing `c.TrackerIntake = c.TrackerIntake.WithDefaults()` line.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && go test ./internal/domain/ -run "TestOrchestratorPolicy|TestProjectConfig_WithDefaults" -v
cd backend && go test ./internal/domain/
```

- [ ] **Step 5: Add the `schemaNames` entry and regenerate the API spec**

In `backend/internal/httpd/apispec/specgen/build.go`'s `schemaNames` map, add near `"DomainRoleOverride": "RoleOverride",`:

```go
	"DomainOrchestratorPolicy": "OrchestratorPolicy",
```

```bash
npm run api
git diff --stat backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
```

Expected: a new `OrchestratorPolicy` schema and a new `orchestratorPolicy` property on `ProjectConfig`'s schema, nothing else unexpected. If `npm run api` reports an unnamed-schema error instead, the `schemaNames` key format is wrong — check an existing entry's exact casing convention (`DomainRoleOverride`, not `Domainroleoverride` or `domain.RoleOverride`) and match it.

- [ ] **Step 6: Run the full gate**

```bash
npm run lint
cd backend && go test ./internal/httpd/...
```

- [ ] **Step 7: Commit**

```bash
git add backend/internal/domain/projectconfig.go \
        backend/internal/domain/projectconfig_test.go \
        backend/internal/httpd/apispec/specgen/build.go \
        backend/internal/httpd/apispec/openapi.yaml \
        frontend/src/api/schema.ts
git commit -m "feat(config): add orchestratorPolicy project config block

MaxLiveWorkers (default 8) and MaxSpawnsPerHour (default 20) are the
leash's configured limits (spec section 8); Task 4 enforces them. Lives
on ProjectConfig directly, not RoleOverride, which Worker shares and
where a spawn budget would be meaningless.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: `requestedBy` wire field, CLI, and identity validation

**Files:**
- Modify: `backend/internal/httpd/controllers/dto.go`
- Modify: `backend/internal/httpd/controllers/sessions.go`
- Modify: `backend/internal/cli/spawn.go`
- Modify: `backend/internal/service/session/service.go` (`Store` interface; `spawn`)
- Test: `backend/internal/service/session/service_test.go`, `backend/internal/cli/spawn_test.go`

**Interfaces:**
- Consumes: `ports.SpawnConfig.RequestedBy` (Task 1); `Store.GetSession` (already exists, `service.go:23`).
- Produces: `SpawnSessionRequest.RequestedBy domain.SessionID` (wire field); apierr code `INVALID_REQUESTED_BY` for a `requestedBy` that does not resolve to a live orchestrator in the same project. Task 4 builds the budget check right after this validation, in the same function.

- [ ] **Step 1: Write the failing service test for identity validation**

In `backend/internal/service/session/service_test.go`, find the existing `Spawn` test setup (a fake `commander`/`Store` pair) and add:

```go
func TestSpawn_RequestedByNotALiveOrchestratorIsRejected(t *testing.T) {
	svc, store, _ := newTestService(t)
	store.projects["proj-1"] = domain.ProjectRecord{ID: "proj-1"}
	store.sessions["proj-1-1"] = domain.SessionRecord{ID: "proj-1-1", ProjectID: "proj-1", Kind: domain.KindWorker}

	_, _, _, err := svc.Spawn(context.Background(), ports.SpawnConfig{
		ProjectID: "proj-1", Kind: domain.KindWorker, RequestedBy: "proj-1-1",
	})
	var apiErr *apierr.Error
	if !errors.As(err, &apiErr) || apiErr.Code != "INVALID_REQUESTED_BY" {
		t.Fatalf("err = %v, want apierr INVALID_REQUESTED_BY (requestedBy names a worker, not an orchestrator)", err)
	}
}

func TestSpawn_RequestedByUnknownSessionIsRejected(t *testing.T) {
	svc, store, _ := newTestService(t)
	store.projects["proj-1"] = domain.ProjectRecord{ID: "proj-1"}

	_, _, _, err := svc.Spawn(context.Background(), ports.SpawnConfig{
		ProjectID: "proj-1", Kind: domain.KindWorker, RequestedBy: "does-not-exist",
	})
	var apiErr *apierr.Error
	if !errors.As(err, &apiErr) || apiErr.Code != "INVALID_REQUESTED_BY" {
		t.Fatalf("err = %v, want apierr INVALID_REQUESTED_BY", err)
	}
}

func TestSpawn_RequestedByOrchestratorInDifferentProjectIsRejected(t *testing.T) {
	svc, store, _ := newTestService(t)
	store.projects["proj-1"] = domain.ProjectRecord{ID: "proj-1"}
	store.sessions["proj-2-1"] = domain.SessionRecord{ID: "proj-2-1", ProjectID: "proj-2", Kind: domain.KindOrchestrator}

	_, _, _, err := svc.Spawn(context.Background(), ports.SpawnConfig{
		ProjectID: "proj-1", Kind: domain.KindWorker, RequestedBy: "proj-2-1",
	})
	var apiErr *apierr.Error
	if !errors.As(err, &apiErr) || apiErr.Code != "INVALID_REQUESTED_BY" {
		t.Fatalf("err = %v, want apierr INVALID_REQUESTED_BY", err)
	}
}

func TestSpawn_EmptyRequestedByIsAlwaysAHumanSpawnAndSucceeds(t *testing.T) {
	svc, store, cmd := newTestService(t)
	store.projects["proj-1"] = domain.ProjectRecord{ID: "proj-1"}
	cmd.spawnResult = domain.SessionRecord{ID: "proj-1-1", ProjectID: "proj-1", Kind: domain.KindWorker}

	_, _, _, err := svc.Spawn(context.Background(), ports.SpawnConfig{ProjectID: "proj-1", Kind: domain.KindWorker})
	if err != nil {
		t.Fatalf("empty requestedBy must never be rejected: %v", err)
	}
}
```

Check `service_test.go` for the actual fake `Store`/`commander` type names and field names already in this package (likely something like a hand-rolled `fakeStore`/`fakeCommander` with `sessions`/`projects` maps and a settable next spawn result) — reuse them verbatim rather than inventing `newTestService`, `store.projects`, `store.sessions`, `cmd.spawnResult` if the real names differ. Read the file first.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && go test ./internal/service/session/ -run TestSpawn_RequestedBy -v
```

Expected: FAIL — every case currently succeeds because nothing validates `RequestedBy` yet.

- [ ] **Step 3: Add validation to `Store` and `spawn`**

In `backend/internal/service/session/service.go`, the `Store` interface (`service.go:23-41`) already has `GetSession` — no interface change needed for this step.

In `spawn` (`service.go:222-246`), after `project, err := s.requireProject(...)` and before `cfg = s.withIssueContext(...)`, add:

```go
	if cfg.RequestedBy != "" {
		requester, ok, err := s.store.GetSession(ctx, cfg.RequestedBy)
		if err != nil {
			return domain.Session{}, 0, 0, fmt.Errorf("resolve requestedBy %s: %w", cfg.RequestedBy, err)
		}
		if !ok || requester.Kind != domain.KindOrchestrator || requester.IsTerminated || requester.ProjectID != cfg.ProjectID {
			return domain.Session{}, 0, 0, apierr.Invalid("INVALID_REQUESTED_BY", "requestedBy must be a live orchestrator in the same project", nil)
		}
	}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && go test ./internal/service/session/ -run TestSpawn_RequestedBy -v
cd backend && go test ./internal/service/session/
```

- [ ] **Step 5: Add the wire field and thread it through the HTTP handler**

In `backend/internal/httpd/controllers/dto.go`, add to `SpawnSessionRequest` (`dto.go:196-213`), near the other optional fields:

```go
	// RequestedBy is the orchestrator session id that asked for this spawn.
	// The CLI fills it from OPERATOR_SESSION_ID when set; empty means a human
	// spawn. The daemon rejects a value that does not resolve to a live
	// orchestrator in the same project.
	RequestedBy domain.SessionID `json:"requestedBy,omitempty"`
```

In `backend/internal/httpd/controllers/sessions.go`, in `spawn` (`sessions.go:269-333`), add `RequestedBy: in.RequestedBy` to the `ports.SpawnConfig{...}` literal passed to `c.Svc.Spawn`.

- [ ] **Step 6: Regenerate the API spec**

```bash
npm run api
git diff --stat backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
```

Expected: `SpawnSessionRequest` gains `requestedBy`, nothing else. If `npm run api` errors about an unnamed schema, `domain.SessionID` should already have a `schemaNames` entry from an earlier phase (it's used elsewhere) — if not, add `"DomainSessionID": "SessionID"` following the existing convention.

- [ ] **Step 7: Write the failing HTTP-level test**

Find the existing table-driven spawn test in `backend/internal/httpd/controllers/sessions_test.go` and add a case (or a new test function, matching this file's style) asserting:
- a `requestedBy` naming a live orchestrator in the request project succeeds and the created session's `spawnedBy` (check the `SessionView` JSON field name — likely `spawnedBy` if you choose to expose it, or omit exposing it publicly and only assert via a direct store read; re-decide based on whether any other DTO field mirrors an internal-only fact — `FirstSignalAt` on `SessionRecord` is `json:"-"`, suggesting the convention here is "expose only what a consumer needs"; `spawnedBy` has no read consumer yet, so lean towards NOT adding it to `SessionView` unless a later task needs it — verify this call against what `opr session get`/`opr board` actually need, and don't add unused wire surface)
- a `requestedBy` naming a worker, or an unknown id, or an orchestrator in a different project, returns `400` with `code: "INVALID_REQUESTED_BY"`

- [ ] **Step 8: Run the httpd gate**

```bash
cd backend && go test ./internal/httpd/... -run TestSpawn -v
```

- [ ] **Step 9: Wire the CLI**

In `backend/internal/cli/spawn.go`, add to `spawnRequest` (`spawn.go:36-46`):

```go
	RequestedBy string `json:"requestedBy,omitempty"`
```

In the request-construction block (`spawn.go:63-158`, wherever `req := spawnRequest{...}` is built), add:

```go
		RequestedBy: strings.TrimSpace(os.Getenv("OPERATOR_SESSION_ID")),
```

`os` and `strings` are already imported in this file (used by `resolveSpawnProject`, `spawn.go:196-218`) — confirm before adding duplicate imports.

- [ ] **Step 10: Write the failing CLI test**

In `backend/internal/cli/spawn_test.go`, find the existing table-driven spawn test and add a case that sets `OPERATOR_SESSION_ID` via `t.Setenv` before invoking the command, then asserts the JSON body the test's fake daemon server received includes `"requestedBy"` set to that value; and a second case with the env var unset asserting the field is omitted (or empty) in the request body. Match this file's existing pattern for asserting on the outgoing request body (likely a captured `httptest.Server` handler) rather than inventing a new one.

- [ ] **Step 11: Run tests to verify they pass**

```bash
cd backend && go test ./internal/cli/ -run TestSpawn -v
cd backend && go test ./internal/cli/
```

- [ ] **Step 12: Run the full gate**

```bash
npm run lint
cd backend && go test ./internal/httpd/...
```

- [ ] **Step 13: Commit**

```bash
git add backend/internal/httpd/controllers/dto.go \
        backend/internal/httpd/controllers/sessions.go \
        backend/internal/httpd/controllers/sessions_test.go \
        backend/internal/httpd/apispec/openapi.yaml \
        frontend/src/api/schema.ts \
        backend/internal/cli/spawn.go \
        backend/internal/cli/spawn_test.go \
        backend/internal/service/session/service.go \
        backend/internal/service/session/service_test.go
git commit -m "feat(spawn): add requestedBy and validate it names a live orchestrator

opr spawn fills requestedBy from OPERATOR_SESSION_ID when set. The
daemon rejects a value that does not resolve to a live, non-terminated
orchestrator in the target project rather than silently treating it as
a human spawn (spec section 5.4) -- an invalid value is a client bug,
not an identity to fall back from.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Budget queries and enforcement in `Service.Spawn`

**Files:**
- Modify: `backend/internal/storage/sqlite/queries/sessions.sql`
- Modify: `backend/internal/storage/sqlite/store/session_store.go`
- Modify: `backend/internal/service/session/service.go`
- Test: `backend/internal/storage/sqlite/store/session_store_test.go`, `backend/internal/service/session/service_test.go`

**Interfaces:**
- Produces:
  - `func (s *Store) CountLiveSessionsByProjectAndKind(ctx, project domain.ProjectID, kind domain.SessionKind) (int, error)`
  - `func (s *Store) CountSessionsSpawnedBySince(ctx, project domain.ProjectID, spawnedBy domain.SessionID, since time.Time) (int, error)`
  - `func (s *Store) OldestSessionSpawnedBySince(ctx, project domain.ProjectID, spawnedBy domain.SessionID, since time.Time) (time.Time, bool, error)`
  - Error code `ORCHESTRATOR_BUDGET_EXHAUSTED` with `Details{"limit": "maxLiveWorkers"|"maxSpawnsPerHour", "resetsAt": RFC3339 string or omitted}`.

- [ ] **Step 1: Write the failing store tests**

Add to `backend/internal/storage/sqlite/store/session_store_test.go`:

```go
func TestCountLiveSessionsByProjectAndKind_CountsOnlyLiveMatchingKind(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	proj := seedProject(t, s, "proj-1")

	live, _ := s.CreateSession(ctx, domain.SessionRecord{ProjectID: proj, Kind: domain.KindWorker, CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC()})
	_, _ = s.CreateSession(ctx, domain.SessionRecord{ProjectID: proj, Kind: domain.KindOrchestrator, CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC()})
	terminated, _ := s.CreateSession(ctx, domain.SessionRecord{ProjectID: proj, Kind: domain.KindWorker, CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC()})
	terminated.IsTerminated = true
	if err := s.UpdateSession(ctx, terminated); err != nil {
		t.Fatal(err)
	}

	n, err := s.CountLiveSessionsByProjectAndKind(ctx, proj, domain.KindWorker)
	if err != nil || n != 1 {
		t.Fatalf("n=%d err=%v, want 1 (only %s is live and a worker)", n, err, live.ID)
	}
}

func TestCountSessionsSpawnedBySince_CountsOnlyMatchingSpawnerWithinWindow(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	proj := seedProject(t, s, "proj-1")
	now := time.Now().UTC()

	inWindow, _ := s.CreateSession(ctx, domain.SessionRecord{ProjectID: proj, Kind: domain.KindWorker, SpawnedBy: "orch-1", CreatedAt: now, UpdatedAt: now})
	_, _ = s.CreateSession(ctx, domain.SessionRecord{ProjectID: proj, Kind: domain.KindWorker, SpawnedBy: "orch-1", CreatedAt: now.Add(-2 * time.Hour), UpdatedAt: now})
	_, _ = s.CreateSession(ctx, domain.SessionRecord{ProjectID: proj, Kind: domain.KindWorker, CreatedAt: now, UpdatedAt: now})

	n, err := s.CountSessionsSpawnedBySince(ctx, proj, "orch-1", now.Add(-time.Hour))
	if err != nil || n != 1 {
		t.Fatalf("n=%d err=%v, want 1 (%s only)", n, err, inWindow.ID)
	}
}

func TestOldestSessionSpawnedBySince_ReturnsOldestInWindow(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	proj := seedProject(t, s, "proj-1")
	now := time.Now().UTC()
	older := now.Add(-30 * time.Minute)

	_, _ = s.CreateSession(ctx, domain.SessionRecord{ProjectID: proj, Kind: domain.KindWorker, SpawnedBy: "orch-1", CreatedAt: older, UpdatedAt: older})
	_, _ = s.CreateSession(ctx, domain.SessionRecord{ProjectID: proj, Kind: domain.KindWorker, SpawnedBy: "orch-1", CreatedAt: now, UpdatedAt: now})

	got, ok, err := s.OldestSessionSpawnedBySince(ctx, proj, "orch-1", now.Add(-time.Hour))
	if err != nil || !ok {
		t.Fatalf("ok=%v err=%v", ok, err)
	}
	if !got.Equal(older) {
		t.Fatalf("got=%v, want the older row's created_at=%v", got, older)
	}
}

func TestOldestSessionSpawnedBySince_NoneInWindow(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	proj := seedProject(t, s, "proj-1")

	_, ok, err := s.OldestSessionSpawnedBySince(ctx, proj, "orch-1", time.Now().UTC().Add(-time.Hour))
	if err != nil || ok {
		t.Fatalf("ok=%v err=%v, want false/nil with nothing spawned", ok, err)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && go test ./internal/storage/sqlite/store/ -run "TestCountLiveSessions|TestCountSessionsSpawnedBySince|TestOldestSessionSpawnedBySince" -v
```

Expected: build failure — the three methods don't exist.

- [ ] **Step 3: Write the sqlc queries**

In `backend/internal/storage/sqlite/queries/sessions.sql`, add:

```sql
-- name: CountLiveSessionsByProjectAndKind :one
SELECT COUNT(*) FROM sessions WHERE project_id = ? AND kind = ? AND is_terminated = 0;

-- name: CountSessionsSpawnedBySince :one
SELECT COUNT(*) FROM sessions WHERE project_id = ? AND spawned_by = ? AND created_at >= ?;

-- name: OldestSessionSpawnedBySince :one
SELECT created_at FROM sessions
WHERE project_id = ? AND spawned_by = ? AND created_at >= ?
ORDER BY created_at ASC LIMIT 1;
```

```bash
npm run sqlc
git status --short backend/internal/storage/sqlite/gen/
```

- [ ] **Step 4: Implement the store methods**

In `backend/internal/storage/sqlite/store/session_store.go`, following the `CountPendingInboxEvents` shape (`orchestrator_inbox_store.go:70-76`):

```go
func (s *Store) CountLiveSessionsByProjectAndKind(ctx context.Context, project domain.ProjectID, kind domain.SessionKind) (int, error) {
	n, err := s.qr.CountLiveSessionsByProjectAndKind(ctx, gen.CountLiveSessionsByProjectAndKindParams{ProjectID: project, Kind: kind})
	if err != nil {
		return 0, fmt.Errorf("count live %s sessions for %s: %w", kind, project, err)
	}
	return int(n), nil
}

func (s *Store) CountSessionsSpawnedBySince(ctx context.Context, project domain.ProjectID, spawnedBy domain.SessionID, since time.Time) (int, error) {
	n, err := s.qr.CountSessionsSpawnedBySince(ctx, gen.CountSessionsSpawnedBySinceParams{ProjectID: project, SpawnedBy: spawnedBy, CreatedAt: since})
	if err != nil {
		return 0, fmt.Errorf("count sessions spawned by %s for %s: %w", spawnedBy, project, err)
	}
	return int(n), nil
}

func (s *Store) OldestSessionSpawnedBySince(ctx context.Context, project domain.ProjectID, spawnedBy domain.SessionID, since time.Time) (time.Time, bool, error) {
	t, err := s.qr.OldestSessionSpawnedBySince(ctx, gen.OldestSessionSpawnedBySinceParams{ProjectID: project, SpawnedBy: spawnedBy, CreatedAt: since})
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return time.Time{}, false, nil
		}
		return time.Time{}, false, fmt.Errorf("oldest session spawned by %s for %s: %w", spawnedBy, project, err)
	}
	return t, true, nil
}
```

Check the exact generated param struct names and field names (`gen.CountLiveSessionsByProjectAndKindParams` etc.) against what `npm run sqlc` actually produced in Step 3 — sqlc names params after the query's placeholders in order, which may not exactly match this sketch. Check whether this file already imports `database/sql` and `errors` for the `sql.ErrNoRows` check; if not, add them.

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd backend && go test ./internal/storage/sqlite/store/ -run "TestCountLiveSessions|TestCountSessionsSpawnedBySince|TestOldestSessionSpawnedBySince" -v
cd backend && go test ./internal/storage/sqlite/store/
```

- [ ] **Step 6: Add the methods to `service/session.Store` and write the failing budget tests**

In `backend/internal/service/session/service.go`, add to the `Store` interface (`service.go:23-41`):

```go
	CountLiveSessionsByProjectAndKind(ctx context.Context, project domain.ProjectID, kind domain.SessionKind) (int, error)
	CountSessionsSpawnedBySince(ctx context.Context, project domain.ProjectID, spawnedBy domain.SessionID, since time.Time) (int, error)
	OldestSessionSpawnedBySince(ctx context.Context, project domain.ProjectID, spawnedBy domain.SessionID, since time.Time) (time.Time, bool, error)
```

Add the same no-op-friendly implementations to whatever fake `Store` `service_test.go` already uses (check the file — likely a map-backed fake with `sessions`/`projects` fields, per Task 3 Step 1's note).

Add to `service_test.go`:

```go
func TestSpawn_RefusesAtLiveWorkerCapForOrchestratorAttributedSpawn(t *testing.T) {
	svc, store, _ := newTestService(t)
	store.projects["proj-1"] = domain.ProjectRecord{ID: "proj-1", Config: domain.ProjectConfig{OrchestratorPolicy: domain.OrchestratorPolicy{MaxLiveWorkers: 1, MaxSpawnsPerHour: 100}}}
	store.sessions["proj-1-orch"] = domain.SessionRecord{ID: "proj-1-orch", ProjectID: "proj-1", Kind: domain.KindOrchestrator}
	store.sessions["proj-1-1"] = domain.SessionRecord{ID: "proj-1-1", ProjectID: "proj-1", Kind: domain.KindWorker}

	_, _, _, err := svc.Spawn(context.Background(), ports.SpawnConfig{ProjectID: "proj-1", Kind: domain.KindWorker, RequestedBy: "proj-1-orch"})
	var apiErr *apierr.Error
	if !errors.As(err, &apiErr) || apiErr.Code != "ORCHESTRATOR_BUDGET_EXHAUSTED" || apiErr.Details["limit"] != "maxLiveWorkers" {
		t.Fatalf("err = %v, want ORCHESTRATOR_BUDGET_EXHAUSTED naming maxLiveWorkers", err)
	}
}

func TestSpawn_HumanSpawnSucceedsAtTheSameCapThatBlocksTheOrchestrator(t *testing.T) {
	svc, store, cmd := newTestService(t)
	store.projects["proj-1"] = domain.ProjectRecord{ID: "proj-1", Config: domain.ProjectConfig{OrchestratorPolicy: domain.OrchestratorPolicy{MaxLiveWorkers: 1, MaxSpawnsPerHour: 100}}}
	store.sessions["proj-1-1"] = domain.SessionRecord{ID: "proj-1-1", ProjectID: "proj-1", Kind: domain.KindWorker}
	cmd.spawnResult = domain.SessionRecord{ID: "proj-1-2", ProjectID: "proj-1", Kind: domain.KindWorker}

	_, _, _, err := svc.Spawn(context.Background(), ports.SpawnConfig{ProjectID: "proj-1", Kind: domain.KindWorker})
	if err != nil {
		t.Fatalf("a human spawn (empty RequestedBy) must be unaffected by the orchestrator's budget: %v", err)
	}
}

func TestSpawn_RefusesAtHourlySpawnRateWithResetTime(t *testing.T) {
	svc, store, _ := newTestService(t)
	now := time.Now().UTC()
	oldest := now.Add(-10 * time.Minute)
	store.projects["proj-1"] = domain.ProjectRecord{ID: "proj-1", Config: domain.ProjectConfig{OrchestratorPolicy: domain.OrchestratorPolicy{MaxLiveWorkers: 100, MaxSpawnsPerHour: 1}}}
	store.sessions["proj-1-orch"] = domain.SessionRecord{ID: "proj-1-orch", ProjectID: "proj-1", Kind: domain.KindOrchestrator}
	store.sessions["proj-1-1"] = domain.SessionRecord{ID: "proj-1-1", ProjectID: "proj-1", Kind: domain.KindWorker, SpawnedBy: "proj-1-orch", CreatedAt: oldest}

	_, _, _, err := svc.Spawn(context.Background(), ports.SpawnConfig{ProjectID: "proj-1", Kind: domain.KindWorker, RequestedBy: "proj-1-orch"})
	var apiErr *apierr.Error
	if !errors.As(err, &apiErr) || apiErr.Code != "ORCHESTRATOR_BUDGET_EXHAUSTED" || apiErr.Details["limit"] != "maxSpawnsPerHour" {
		t.Fatalf("err = %v, want ORCHESTRATOR_BUDGET_EXHAUSTED naming maxSpawnsPerHour", err)
	}
	resetsAt, ok := apiErr.Details["resetsAt"].(string)
	if !ok || resetsAt == "" {
		t.Fatalf("Details[\"resetsAt\"] = %v, want a non-empty timestamp naming when the oldest counted spawn ages out", apiErr.Details["resetsAt"])
	}
}
```

The fake `Store` needs `CountLiveSessionsByProjectAndKind`/`CountSessionsSpawnedBySince`/`OldestSessionSpawnedBySince` implementations that actually derive their answer from the fake's `sessions` map (filtering by project/kind/`is_terminated`/`spawned_by`/`created_at`) rather than being hardcoded — otherwise these tests can't distinguish cap-hit from cap-clear. Write those against the fake's real field names, matching whatever map-and-filter style its existing fake methods already use.

- [ ] **Step 7: Run tests to verify they fail**

```bash
cd backend && go test ./internal/service/session/ -run "TestSpawn_Refuses|TestSpawn_Human" -v
```

Expected: build failure (interface not satisfied) until the fake is updated, then FAIL (no budget check exists yet) once it compiles.

- [ ] **Step 8: Implement budget enforcement**

In `service.go`'s `spawn` (`service.go:222-246`), immediately after the `requestedBy` validation block from Task 3 Step 3, add:

```go
	if cfg.RequestedBy != "" {
		policy := project.Config.OrchestratorPolicy.WithDefaults()

		liveWorkers, err := s.store.CountLiveSessionsByProjectAndKind(ctx, cfg.ProjectID, domain.KindWorker)
		if err != nil {
			return domain.Session{}, 0, 0, fmt.Errorf("count live workers for %s: %w", cfg.ProjectID, err)
		}
		if liveWorkers >= policy.MaxLiveWorkers {
			return domain.Session{}, 0, 0, apierr.Invalid("ORCHESTRATOR_BUDGET_EXHAUSTED",
				fmt.Sprintf("project %s is at its live-worker cap (%d); free a worker before spawning another", cfg.ProjectID, policy.MaxLiveWorkers),
				map[string]any{"limit": "maxLiveWorkers", "current": liveWorkers, "cap": policy.MaxLiveWorkers})
		}

		windowStart := s.now().Add(-time.Hour)
		spawnedThisHour, err := s.store.CountSessionsSpawnedBySince(ctx, cfg.ProjectID, cfg.RequestedBy, windowStart)
		if err != nil {
			return domain.Session{}, 0, 0, fmt.Errorf("count hourly spawns for %s: %w", cfg.RequestedBy, err)
		}
		if spawnedThisHour >= policy.MaxSpawnsPerHour {
			details := map[string]any{"limit": "maxSpawnsPerHour", "current": spawnedThisHour, "cap": policy.MaxSpawnsPerHour}
			if oldest, ok, err := s.store.OldestSessionSpawnedBySince(ctx, cfg.ProjectID, cfg.RequestedBy, windowStart); err == nil && ok {
				details["resetsAt"] = oldest.Add(time.Hour).UTC().Format(time.RFC3339)
			}
			return domain.Session{}, 0, 0, apierr.Invalid("ORCHESTRATOR_BUDGET_EXHAUSTED",
				fmt.Sprintf("orchestrator %s has hit its spawn-rate cap (%d/hour)", cfg.RequestedBy, policy.MaxSpawnsPerHour),
				details)
		}
	}
```

Check `s.now()` — this method's existing use elsewhere in the file (`service.go:225`, `start := s.now()`) confirms it exists as the service's clock seam; use it here too rather than `time.Now()` directly, so tests can control it if the fake clock is already wired for other tests in this file (check whether `newTestService` already sets a fixed clock — if so, the `CreatedAt: oldest` fixtures in Step 6's tests need to be relative to that fixed clock, not real wall time; adjust the test fixtures accordingly if this is the case).

- [ ] **Step 9: Run tests to verify they pass**

```bash
cd backend && go test ./internal/service/session/ -run "TestSpawn_" -v
cd backend && go test ./internal/service/session/
```

- [ ] **Step 10: Run the full gate**

```bash
npm run lint
cd backend && go test ./internal/httpd/...
```

- [ ] **Step 11: Commit**

```bash
git add backend/internal/storage/sqlite/queries/sessions.sql \
        backend/internal/storage/sqlite/gen/ \
        backend/internal/storage/sqlite/store/session_store.go \
        backend/internal/storage/sqlite/store/session_store_test.go \
        backend/internal/service/session/service.go \
        backend/internal/service/session/service_test.go
git commit -m "feat(spawn): enforce the live-worker cap and hourly spawn-rate budget

Both checks run only when RequestedBy is set (a human spawn is always
unaffected). The live-worker count includes every live worker
regardless of spawner, so the cap reflects real concurrency; the hourly
count is scoped to spawned_by, since a human spawn was never rate
limited. ORCHESTRATOR_BUDGET_EXHAUSTED names which limit was hit and,
for the rate limit, the reset time computed from the oldest counted
row -- a query, not a timer (spec section 5.4, section 10).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Prompt rewrite for autonomy, budget, merge boundary, and `opr session switch-agent`

**Files:**
- Modify: `backend/internal/session_manager/prompt.go`
- Test: `backend/internal/session_manager/prompt_test.go`

**Interfaces:**
- Consumes: nothing new — this is a pure text change to `orchestratorSystemPrompt` (`prompt.go:161-220`). The function's `fmt.Sprintf` signature (5 `%s` placeholders: `projectName(project)`, `project.ID` ×3, `projectContextSection(project)`) is unchanged — every addition below is static text with no new placeholders, so the argument list is untouched.

- [ ] **Step 1: Write the failing prompt tests**

In `backend/internal/session_manager/prompt_test.go`, find the existing orchestrator-prompt test(s) (Phase 0/1 added assertions here — check what helper builds a `promptProject` and calls `orchestratorSystemPrompt`) and add:

```go
func TestOrchestratorPrompt_AuthorizesActingWithoutAsking(t *testing.T) {
	got := orchestratorSystemPrompt(testPromptProject(t))
	for _, want := range []string{
		"spawn, redirect, and kill worker sessions on your own judgment",
		"Do not ask the human for permission before spawning, redirecting, or killing a worker",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("prompt missing autonomy grant %q", want)
		}
	}
}

func TestOrchestratorPrompt_TeachesTheBudgetFailureMode(t *testing.T) {
	got := orchestratorSystemPrompt(testPromptProject(t))
	if !strings.Contains(got, "ORCHESTRATOR_BUDGET_EXHAUSTED") {
		t.Fatal("prompt does not mention ORCHESTRATOR_BUDGET_EXHAUSTED")
	}
	if !strings.Contains(got, "do not retry the spawn in a loop") {
		t.Fatal("prompt does not tell the orchestrator to avoid retrying budget exhaustion")
	}
}

func TestOrchestratorPrompt_RestatesTheMergeBoundary(t *testing.T) {
	got := orchestratorSystemPrompt(testPromptProject(t))
	if !strings.Contains(got, "Never merge a PR on your own initiative") {
		t.Fatal("prompt does not restate the merge boundary for autonomous framing")
	}
}

func TestOrchestratorPrompt_TeachesSwitchAgent(t *testing.T) {
	got := orchestratorSystemPrompt(testPromptProject(t))
	if !strings.Contains(got, "opr session switch-agent") {
		t.Fatal("prompt does not teach opr session switch-agent")
	}
}
```

Use whatever helper this file already has to build a `promptProject` for a test (`testPromptProject` is a placeholder name — find the real one, likely used by Phase 0/1's own prompt tests already in this file).

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && go test ./internal/session_manager/ -run TestOrchestratorPrompt -v
```

Expected: FAIL.

- [ ] **Step 3: Rewrite the prompt**

In `prompt.go`, replace the body of `orchestratorSystemPrompt` (`prompt.go:161-220`). Keep the `fmt.Sprintf` wrapper and its five arguments exactly as they are; only the format string's content changes. Full replacement text:

```go
func orchestratorSystemPrompt(project promptProject) string {
	return fmt.Sprintf(`## Operator Orchestrator Role

You are the human-facing orchestrator for project %s.

Your job is to coordinate work, not to perform implementation. Keep the project moving by inspecting state, spawning worker sessions, messaging workers, routing CI/review feedback, and summarizing progress for the human.

## Autonomy

You have full authority to spawn, redirect, and kill worker sessions on your own judgment, bounded only by the project's spawn budget. Do not ask the human for permission before spawning, redirecting, or killing a worker — act, then report what you did and why. The human is notified of your actions; they are not consulted before them.

This authority does not extend to the prohibitions below: they are not judgment calls you weigh against your autonomy, they are hard boundaries.

## Operating Rules

- Treat the orchestrator session as coordination-only by default.
- For every implementation, fix, test, PR update, or code-review task, always spawn or redirect a worker session; do not perform the task in the orchestrator session.
- Never ever make code changes directly in the orchestrator session.
- Never edit source files, resolve merge conflicts, run implementation-focused changes, create feature commits, push, or open PRs from the orchestrator session.
- If the human asks for implementation, fixes, tests, PR updates, or merge-conflict resolution, inspect current state and spawn or redirect a worker session instead of doing the work yourself.
- If the human explicitly insists that the orchestrator itself make code changes, ask for explicit confirmation before making any code changes, and prefer spawning or redirecting a worker unless the human explicitly confirms direct orchestrator edits are required.
- Delegate implementation, fixes, tests, and PR ownership to worker sessions.
- Before spawning new work, inspect current state so you do not duplicate active sessions.
- For complex planning, research, or large coordination tasks, write a short plan first.
- Do not use the agent runtime's built-in subagent or task-delegation tools for implementation work.
- You may coordinate multiple workers, but Operator workers only. If parallel help is needed, spawn or redirect additional Operator worker sessions.
- If a worker is stuck, clarify the task with `+"`opr send`"+`, redirect it to a different agent with `+"`opr session switch-agent`"+`, or spawn/redirect another worker when appropriate.
- Never claim a PR into the orchestrator session. If a PR needs continuation, assign or spawn a worker.
- Use `+"`opr send`"+` for session communication. Do not bypass Operator by writing directly to the PTY, pipes, or runtime internals.
- **Never merge a PR on your own initiative.** Merging is permitted only when the human has explicitly instructed it for that PR. When work is green and approved, report that state to the human and wait for the instruction — do not treat "green and approved" as license to merge.

## Core Commands

- `+"`opr board`"+` - every live worker in this project with its task brief, status, last update, and PR/CI/review state. Start here.
- `+"`opr inbox`"+` - pending worker-idle digests for this project. You are nudged with a bare count; always call this to see what changed, never act on the nudge text alone.
- `+"`opr inbox ack &lt;id&gt; [&lt;id&gt;...]`"+` - acknowledge inbox items. Ack means "seen", not "done": ack every id the pull showed you, whether or not you took action on it. An empty inbox is a normal outcome: end your turn without action rather than inventing work.
- `+"`opr status`"+` - daemon health only (pid, port, uptime). It reports nothing about the work.
- `+"`opr session ls --project %s`"+` - list sessions for this project.
- `+"`opr session get &lt;worker-session-id&gt;`"+` - one worker in full, including its brief, its last user-facing update, and every PR it owns.
- `+"`opr spawn --project %s --name \"&lt;label&gt;\" --prompt \"&lt;clear worker task&gt;\"`"+` - spawn a freeform worker.
- `+"`opr spawn --project %s --name \"&lt;label&gt;\" --issue &lt;issue-id&gt;`"+` - spawn a worker for an issue.
- `+"`--name`"+` is required: a deliberate sidebar label so the user can see what each worker is working on at a glance; labels must be 20 characters or fewer.
- Before running `+"`opr spawn`"+`, count the `+"`--name`"+` label yourself. It must be 20 characters or fewer. If your first label is longer, shorten it before executing the command.
- Add `+"`--agent &lt;name&gt;`"+` when a worker must use a specific agent.
- `+"`opr send --session &lt;session-id&gt; --message \"&lt;message&gt;\"`"+` - message a worker.
- `+"`opr session switch-agent &lt;session-id&gt; &lt;target-harness&gt;`"+` - redirect a worker to a different agent when its current one is stuck, looping, or unsuitable for the remaining work. This hands off the worker's context to the new agent automatically; you do not need to summarize the work yourself first.
- `+"`opr session claim-pr &lt;session-id&gt; &lt;pr-ref&gt;`"+` - attach an existing PR to a worker session.
- `+"`opr session kill &lt;session-id&gt;`"+` - terminate a session when appropriate.

## Spawn Budget

Spawning is bounded by a per-project budget (a live-worker cap and an hourly spawn-rate cap), enforced by the daemon — this is a real limit, not a suggestion.

- If `+"`opr spawn`"+` fails with error code `+"`ORCHESTRATOR_BUDGET_EXHAUSTED`"+`, do not retry the spawn in a loop. The error names which limit you hit and, for the hourly rate limit, when it resets.
- Keep the work you intended to spawn in mind and report it to the human, along with the limit you hit and when (if known) it will clear. Revisit it on your next natural turn — a future inbox nudge or a message from the human — rather than looping on the spawn call now.

## Coordination Workflow

1. Inspect current state with `+"`opr board`"+`.
2. On a `+"`[Operator] N inbox item(s)`"+` nudge, run `+"`opr inbox`"+`, act on what changed, then run `+"`opr inbox ack`"+` for every id that pull showed you — whether or not you took action on it, so the daemon does not keep re-announcing an item you have already reviewed. If the inbox is empty, end the turn.
3. Identify which worker owns each task or PR.
4. Spawn a worker only when no suitable active worker exists.
5. Send workers clear task instructions with the expected outcome.
6. Monitor worker output, PR state, CI, and reviews.
7. Route CI failures and review comments back to the responsible worker.
8. Summarize status and blockers for the human.

## Review and CI Workflow

- If CI fails, send the failing output to the responsible worker and ask them to fix and push.
- If review changes are requested, send the review findings to the responsible worker.
- If work is green and approved, report that state to the human. Never merge on your own initiative — only when the human explicitly instructs it.

%s`, projectName(project), project.ID, project.ID, project.ID, projectContextSection(project))
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && go test ./internal/session_manager/ -run TestOrchestratorPrompt -v
cd backend && go test ./internal/session_manager/
```

Expected: PASS. If an existing Phase 0/1 test asserts the old prompt text verbatim (e.g. the exact old merge-boundary sentence, or the exact old "if a worker is stuck" bullet), update its expected text to match — do not weaken what it checks, only the literal string it compares against.

- [ ] **Step 5: Run the full gate**

```bash
npm run lint
```

- [ ] **Step 6: Update the spec to record what shipped**

In `docs/superpowers/specs/2026-09-11-autonomous-orchestrator-design.md`, under §14 Phase 2, mark it done with a one-line pointer to this plan, noting the `opr session switch-agent` substitution for the literally-named `opr session handoff` (per this plan's corrected-premises section).

- [ ] **Step 7: Commit**

```bash
git add backend/internal/session_manager/prompt.go \
        backend/internal/session_manager/prompt_test.go \
        docs/superpowers/specs/2026-09-11-autonomous-orchestrator-design.md
git commit -m "feat(prompt): authorize the orchestrator to act without asking

Spawn, redirect, and kill are now framed as standing authority bounded
by the spawn budget, not actions requiring permission. Teaches the
ORCHESTRATOR_BUDGET_EXHAUSTED failure mode (queue and report, never
retry in a loop), restates the merge boundary for the autonomous
framing, and teaches opr session switch-agent as the redirect command
(spec section 9's 'opr session handoff' -- see this plan's
corrected-premises section for why switch-agent, not the hidden
handoff-submit plumbing, is what the prompt teaches).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Verification before calling Phase 2 done

- [ ] `npm run lint` passes from the repo root, `0 issues.`
- [ ] `cd backend && go test ./internal/httpd/...` passes (spec drift).
- [ ] `git diff --stat` on `openapi.yaml` and `frontend/src/api/schema.ts` shows only this phase's additions (`requestedBy`, `OrchestratorPolicy`/`orchestratorPolicy`).
- [ ] End-to-end against an isolated daemon (never the user's `~/.operator`, pid 97452), reusing the exact recipe from `docs/superpowers/plans/2026-09-12-orchestrator-ears-phase-1.md:2146-2171`:

  ```bash
  cd backend && go build -o /tmp/opr-phase2 ./cmd/opr
  mkdir -p /tmp/opr-phase2-data
  OPERATOR_DATA_DIR=/tmp/opr-phase2-data OPERATOR_RUN_FILE=/tmp/opr-phase2-data/run.json /tmp/opr-phase2 daemon &
  ```

  1. Confirm migration 0107 applied: `sqlite3 /tmp/opr-phase2-data/opr.db "select max(version_id) from goose_db_version;"` should show `107`.
  2. Seed a project and an orchestrator session directly with `sqlite3` (mirror the Phase 1 seeding pattern). Spawn a worker through the real HTTP path with `requestedBy` set to the orchestrator's id: `curl -X POST localhost:<port>/api/v1/sessions -d '{"projectId":"<id>","kind":"worker","displayName":"t1","requestedBy":"<orchestrator-id>"}'`. Confirm the created session's `spawned_by` column is set: `sqlite3 /tmp/opr-phase2-data/opr.db "select id, spawned_by from sessions;"`.
  3. Repeat with `requestedBy` set to a worker session's id (not an orchestrator) or to a nonexistent id. Confirm the response is `400` with `"code":"INVALID_REQUESTED_BY"`, not a silently-accepted human spawn.
  4. Set the project's `orchestratorPolicy.maxLiveWorkers` to `1` via `PUT /api/v1/projects/{id}/config`, with one live worker already present. Spawn again with a valid `requestedBy`: confirm `403`/`400` (check the actual status `httpStatus` maps `KindInvalid` to) with `"code":"ORCHESTRATOR_BUDGET_EXHAUSTED"` and `"details":{"limit":"maxLiveWorkers",...}`. Then spawn again with `requestedBy` omitted (empty): confirm it succeeds despite the same cap.
  5. Set `maxSpawnsPerHour` to `1`, seed one session already `spawned_by` the orchestrator with `created_at` inside the last hour. Spawn again with `requestedBy` set to that orchestrator: confirm `ORCHESTRATOR_BUDGET_EXHAUSTED` with `"limit":"maxSpawnsPerHour"` and a non-empty `resetsAt` in `details`, and confirm the `resetsAt` value is the seeded session's `created_at` plus one hour.
  6. `opr stop` (or a clean shutdown signal) against **this** isolated daemon only.

  Paste the actual output for every step. If any step cannot be exercised without a real PTY-backed session, say so explicitly and verify what real code path *is* reachable (the DB write, the service-layer check, the HTTP round-trip) rather than skipping the check silently.

- [ ] Confirm no code path in this phase introduces a timer, attempt counter, or `next_attempt_at`: `grep -rn "time.After\|time.Tick\|next_attempt" backend/internal/service/session/ backend/internal/domain/projectconfig.go` should show nothing from this phase's changes.
