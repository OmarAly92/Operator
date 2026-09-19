# Planning Tickets: Daemon Implementation Plan (plan 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The daemon reads ticket folders from a project's repo, stores planning-session and plan-assignment links in SQLite, derives ticket and plan status from linked sessions, and exposes create / read / write / plan / assign / review / merge-ready / merge / done / archive routes plus a folder-change SSE stream. Reviews run in the planner session or a fresh one, auto-trigger when the implementer opens a PR, and stop for the user's merge confirmation. No UI.

**Architecture:** Markdown lives in `<project>/.operator/tickets/<slug>/` and is scanned on every request. Two new tables (`tickets`, `plan_assignments`) hold runtime links and emit a new `ticket_updated` change-log event. A leaf service `internal/service/ticket` composes scanner + store + session list into `domain.Ticket` read models and spawns sessions through the existing session service with a daemon-built task prompt. A chi controller exposes it; the OpenAPI spec is regenerated from Go.

**Tech Stack:** Go (chi, sqlc 1.31 + goose, `gopkg.in/yaml.v3`, fsnotify via `internal/workspacewatch`), real-SQLite tests via `sqlitetest`.

**Spec:** `docs/superpowers/specs/2026-09-18-planning-tickets-design.md` (read §1, §2 including §2.6, §4, §5 and "Plan 1" in §6 before starting). Tasks run in file order: 1, 2, 3, 4, 5, 6, 7, 7b, 7c, 8, 9, 10.

## Global Constraints

- Daemon gate after every task: `cd backend && go build ./... && go test ./... && go vet ./...` plus `gofmt -l internal` empty. After any route or DTO change also `npm run api` from the repo root and `cd backend && go test ./internal/httpd/...` (parity test `internal/httpd/apispec/parity_test.go:22` and drift test `specgen/build_test.go:15` fail otherwise). Commit `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts` with the Go change.
- Never hand-edit `backend/internal/storage/sqlite/gen/*`; run `npm run sqlc` from the repo root after touching `queries/*.sql`, migrations or `sqlc.yaml`.
- Never modify an already-merged migration; the new one is `0114_tickets.sql`.
- Status is derived at read time, never stored (`AGENTS.md`, "Hard rules").
- Change events come only from DB triggers into `change_log`; no manual CDC emission from store methods.
- No comments in code (user global rule). Existing files that carry load-bearing comments keep them.
- Tickets are supported only for `single_repo` projects in this plan.
- Every task ends with a commit on `development`. Never touch `master`. Commit trailer: the `Co-Authored-By` line your session's attribution reminder gives.
- Errors returned to HTTP use the locked envelope `{error, code, message, requestId}` via `apierr` + `envelope.WriteError`. Codes are `TICKET_*`.

## File map

Create:
- `backend/internal/domain/ticket.go` — records, read models, statuses, roles, `TicketsDir`.
- `backend/internal/storage/sqlite/migrations/0114_tickets.sql`
- `backend/internal/storage/sqlite/queries/tickets.sql`
- `backend/internal/storage/sqlite/store/ticket_store.go`, `ticket_store_test.go`
- `backend/internal/service/ticket/frontmatter.go`, `slug.go`, `scan.go` (+ `_test.go` each)
- `backend/internal/service/ticket/status.go`, `status_test.go`
- `backend/internal/service/ticket/prompt.go`, `prompt_test.go`
- `backend/internal/service/ticket/git.go`, `git_test.go`
- `backend/internal/service/ticket/service.go`, `service_test.go`
- `backend/internal/service/ticket/autoreview.go`, `autoreview_test.go`
- `backend/internal/httpd/controllers/tickets.go`, `tickets_test.go`
- `backend/internal/integration/tickets_sqlite_test.go`

Modify:
- `backend/sqlc.yaml` — column overrides for the two tables.
- `backend/internal/cdc/event.go:22-34` — `EventTicketUpdated`.
- `frontend/src/renderer/lib/event-transport.ts:26-35` — add `"ticket_updated"` to `CDC_EVENT_TYPES`.
- `backend/internal/domain/session.go:125-134` — `Ticket *SessionTicketRef` on `Session`.
- `backend/internal/domain/projectconfig.go:20` — `Tickets TicketDefaults` on `ProjectConfig`.
- `backend/internal/service/session/service.go:974-987` — populate `Ticket` in `toSession`; the `store` interface in that file gains `SessionTicketRef`.
- `backend/internal/httpd/controllers/dto.go` — ticket DTOs and params.
- `backend/internal/httpd/apispec/specgen/build.go` — `ticketOperations()`, tag, `schemaNames`.
- `backend/internal/httpd/api.go:70,95,131,160-167` — `APIDeps.Tickets`, controller field, construction, `Register`.
- `backend/internal/daemon/daemon.go:395-435` — construct `ticketsvc` with the loopback base URL, subscribe the auto-reviewer to `cdcPipe.Broadcaster`, pass `Tickets:`.

---

### Task 1: Domain types, migration, sqlc queries, store, CDC event

**Files:**
- Create: `backend/internal/domain/ticket.go`
- Create: `backend/internal/storage/sqlite/migrations/0114_tickets.sql`
- Create: `backend/internal/storage/sqlite/queries/tickets.sql`
- Create: `backend/internal/storage/sqlite/store/ticket_store.go`
- Test: `backend/internal/storage/sqlite/store/ticket_store_test.go`
- Modify: `backend/sqlc.yaml` (overrides list, next to the `claude_accounts.*` entries at line ~119)
- Modify: `backend/internal/cdc/event.go:22-34`
- Modify: `frontend/src/renderer/lib/event-transport.ts:26-35`

**Interfaces:**
- Produces (domain): `TicketStatus`, `PlanStatus`, `TicketRole`, `TicketRecord`, `PlanAssignmentRecord`, `SessionTicketRef`, `Plan`, `Ticket`, `const TicketsDir = ".operator/tickets"`.
- Produces (store, on `*store.Store`):
  - `ListTickets(ctx, project domain.ProjectID) ([]domain.TicketRecord, error)`
  - `GetTicket(ctx, project domain.ProjectID, slug string) (domain.TicketRecord, bool, error)`
  - `InsertTicket(ctx, rec domain.TicketRecord) error`
  - `SetTicketPlanningSession(ctx, project domain.ProjectID, slug string, session domain.SessionID) error` (empty id clears)
  - `SetTicketArchivedAt(ctx, project domain.ProjectID, slug string, at time.Time) error` (zero clears)
  - `ListPlanAssignments(ctx, project domain.ProjectID, slug string) ([]domain.PlanAssignmentRecord, error)` (newest first)
  - `InsertPlanAssignment(ctx, rec domain.PlanAssignmentRecord) error`
  - `SessionTicketRef(ctx, id domain.SessionID) (domain.SessionTicketRef, bool, error)`
  - `GetPlanAssignment(ctx, id int64) (domain.PlanAssignmentRecord, bool, error)`
  - `MarkPlanReviewRequested(ctx, id int64, reviewer domain.SessionID, at time.Time) error`
  - `MarkPlanMergeReady(ctx, id int64, at time.Time, summary string) error` — also clears `merge_approved_at`, starting a new confirmation cycle
  - `MarkPlanMergeApproved(ctx, id int64, at time.Time) error`
- Produces (cdc): `cdc.EventTicketUpdated EventType = "ticket_updated"`.

- [ ] **Step 1: Write the domain file**

`backend/internal/domain/ticket.go`:

```go
package domain

import "time"

const TicketsDir = ".operator/tickets"

type TicketStatus string

const (
	TicketStatusDraft      TicketStatus = "draft"
	TicketStatusPlanning   TicketStatus = "planning"
	TicketStatusReady      TicketStatus = "ready"
	TicketStatusInProgress TicketStatus = "in_progress"
	TicketStatusAwaitMerge TicketStatus = "awaiting_merge"
	TicketStatusDone       TicketStatus = "done"
	TicketStatusArchived   TicketStatus = "archived"
)

type PlanStatus string

const (
	PlanStatusTodo       PlanStatus = "todo"
	PlanStatusIdle       PlanStatus = "idle"
	PlanStatusWorking    PlanStatus = "working"
	PlanStatusNeedsYou   PlanStatus = "needs_you"
	PlanStatusInReview   PlanStatus = "in_review"
	PlanStatusReviewing  PlanStatus = "reviewing"
	PlanStatusAwaitMerge PlanStatus = "awaiting_merge"
	PlanStatusMerged     PlanStatus = "merged"
	PlanStatusDone       PlanStatus = "done"
	PlanStatusTerminated PlanStatus = "terminated"
)

type TicketRole string

const (
	TicketRolePlanning     TicketRole = "planning"
	TicketRoleImplementing TicketRole = "implementing"
	TicketRoleReviewing    TicketRole = "reviewing"
)

type TicketRecord struct {
	ProjectID         ProjectID
	Slug              string
	PlanningSessionID SessionID
	ArchivedAt        time.Time
	CreatedAt         time.Time
}

type PlanAssignmentRecord struct {
	ID                int64
	ProjectID         ProjectID
	Slug              string
	PlanFile          string
	SessionID         SessionID
	AssignedAt        time.Time
	DoneAt            time.Time
	ReviewerSessionID SessionID
	ReviewRequestedAt time.Time
	MergeReadyAt      time.Time
	MergeSummary      string
	MergeApprovedAt   time.Time
}

type SessionTicketRef struct {
	Slug     string     `json:"slug"`
	PlanFile string     `json:"planFile,omitempty"`
	Role     TicketRole `json:"role" enum:"planning,implementing,reviewing"`
}

type Plan struct {
	File         string
	Order        int
	Title        string
	Status       PlanStatus
	SessionID    SessionID
	AssignmentID int64
	ReviewerID   SessionID
	MergeSummary string
	KickoffFile  string
	Unordered    bool
	Warning      string
}

type Ticket struct {
	ProjectID         ProjectID
	Slug              string
	Title             string
	Brief             string
	Status            TicketStatus
	PlanningSessionID SessionID
	Plans             []Plan
	Files             []string
	Warning           string
	CreatedAt         time.Time
	ArchivedAt        time.Time
}
```

- [ ] **Step 2: Write the migration**

`backend/internal/storage/sqlite/migrations/0114_tickets.sql`:

```sql
-- +goose NO TRANSACTION
-- +goose Up
PRAGMA writable_schema = ON;
UPDATE sqlite_master
SET sql = replace(sql, '''session_created''', '''session_created'', ''ticket_updated''')
WHERE type = 'table' AND name = 'change_log'
    AND instr(sql, '''ticket_updated''') = 0;
PRAGMA writable_schema = RESET;

CREATE TABLE tickets (
    project_id          TEXT NOT NULL REFERENCES projects (id),
    slug                TEXT NOT NULL,
    planning_session_id TEXT REFERENCES sessions (id) ON DELETE SET NULL,
    archived_at         TIMESTAMP,
    created_at          TIMESTAMP NOT NULL,
    PRIMARY KEY (project_id, slug)
);
CREATE INDEX idx_tickets_planning_session ON tickets (planning_session_id);

CREATE TABLE plan_assignments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id  TEXT NOT NULL,
    slug        TEXT NOT NULL,
    plan_file   TEXT NOT NULL,
    session_id  TEXT REFERENCES sessions (id) ON DELETE SET NULL,
    assigned_at TIMESTAMP NOT NULL,
    done_at     TIMESTAMP,
    reviewer_session_id TEXT REFERENCES sessions (id) ON DELETE SET NULL,
    review_requested_at TIMESTAMP,
    merge_ready_at      TIMESTAMP,
    merge_summary       TEXT NOT NULL DEFAULT '',
    merge_approved_at   TIMESTAMP,
    FOREIGN KEY (project_id, slug) REFERENCES tickets (project_id, slug) ON DELETE CASCADE
);
CREATE INDEX idx_plan_assignments_ticket ON plan_assignments (project_id, slug, plan_file, id);
CREATE INDEX idx_plan_assignments_session ON plan_assignments (session_id);
CREATE INDEX idx_plan_assignments_reviewer ON plan_assignments (reviewer_session_id);

-- +goose StatementBegin
CREATE TRIGGER tickets_cdc_insert
AFTER INSERT ON tickets
BEGIN
    INSERT INTO change_log (project_id, event_type, payload)
    VALUES (NEW.project_id, 'ticket_updated', json_object('projectId', NEW.project_id, 'slug', NEW.slug));
END;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE TRIGGER tickets_cdc_update
AFTER UPDATE ON tickets
BEGIN
    INSERT INTO change_log (project_id, event_type, payload)
    VALUES (NEW.project_id, 'ticket_updated', json_object('projectId', NEW.project_id, 'slug', NEW.slug));
END;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE TRIGGER plan_assignments_cdc_insert
AFTER INSERT ON plan_assignments
BEGIN
    INSERT INTO change_log (project_id, event_type, payload)
    VALUES (NEW.project_id, 'ticket_updated', json_object('projectId', NEW.project_id, 'slug', NEW.slug));
END;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE TRIGGER plan_assignments_cdc_update
AFTER UPDATE ON plan_assignments
BEGIN
    INSERT INTO change_log (project_id, event_type, payload)
    VALUES (NEW.project_id, 'ticket_updated', json_object('projectId', NEW.project_id, 'slug', NEW.slug));
END;
-- +goose StatementEnd

-- +goose Down
DROP TRIGGER IF EXISTS plan_assignments_cdc_update;
DROP TRIGGER IF EXISTS plan_assignments_cdc_insert;
DROP TRIGGER IF EXISTS tickets_cdc_update;
DROP TRIGGER IF EXISTS tickets_cdc_insert;
DROP INDEX IF EXISTS idx_plan_assignments_reviewer;
DROP INDEX IF EXISTS idx_plan_assignments_session;
DROP INDEX IF EXISTS idx_plan_assignments_ticket;
DROP TABLE IF EXISTS plan_assignments;
DROP INDEX IF EXISTS idx_tickets_planning_session;
DROP TABLE IF EXISTS tickets;
DELETE FROM change_log WHERE event_type = 'ticket_updated';
PRAGMA writable_schema = ON;
UPDATE sqlite_master
SET sql = replace(sql, '''session_created'', ''ticket_updated''', '''session_created''')
WHERE type = 'table' AND name = 'change_log';
PRAGMA writable_schema = RESET;
```

The writable-schema block is the precedent from `0108_board_cdc.sql:1-8`; the `change_log.event_type` column has a `CHECK (event_type IN (...))` and inserting an unknown type fails otherwise.

- [ ] **Step 3: Write the queries and sqlc overrides**

`backend/internal/storage/sqlite/queries/tickets.sql`:

```sql
-- name: ListTickets :many
SELECT * FROM tickets WHERE project_id = ? ORDER BY created_at, slug;

-- name: GetTicket :one
SELECT * FROM tickets WHERE project_id = ? AND slug = ?;

-- name: InsertTicket :exec
INSERT INTO tickets (project_id, slug, planning_session_id, archived_at, created_at)
VALUES (?, ?, ?, ?, ?);

-- name: SetTicketPlanningSession :execrows
UPDATE tickets SET planning_session_id = ? WHERE project_id = ? AND slug = ?;

-- name: SetTicketArchivedAt :execrows
UPDATE tickets SET archived_at = ? WHERE project_id = ? AND slug = ?;

-- name: TicketByPlanningSession :one
SELECT * FROM tickets WHERE planning_session_id = ?;

-- name: ListPlanAssignments :many
SELECT * FROM plan_assignments WHERE project_id = ? AND slug = ? ORDER BY id DESC;

-- name: InsertPlanAssignment :exec
INSERT INTO plan_assignments (project_id, slug, plan_file, session_id, assigned_at, done_at)
VALUES (?, ?, ?, ?, ?, ?);

-- name: PlanAssignmentBySession :one
SELECT * FROM plan_assignments WHERE session_id = ? ORDER BY id DESC LIMIT 1;

-- name: GetPlanAssignment :one
SELECT * FROM plan_assignments WHERE id = ?;

-- name: PlanAssignmentByReviewer :one
SELECT * FROM plan_assignments WHERE reviewer_session_id = ? ORDER BY id DESC LIMIT 1;

-- name: SetPlanAssignmentReviewRequested :execrows
UPDATE plan_assignments SET reviewer_session_id = ?, review_requested_at = ? WHERE id = ?;

-- name: SetPlanAssignmentMergeReady :execrows
UPDATE plan_assignments SET merge_ready_at = ?, merge_summary = ?, merge_approved_at = NULL WHERE id = ?;

-- name: SetPlanAssignmentMergeApproved :execrows
UPDATE plan_assignments SET merge_approved_at = ? WHERE id = ?;
```

Append to the `overrides:` list in `backend/sqlc.yaml` (same indentation as the neighbouring entries):

```yaml
          - column: "tickets.project_id"
            go_type:
              import: "github.com/OmarAly92/operator/backend/internal/domain"
              type: "ProjectID"
          - column: "tickets.planning_session_id"
            go_type:
              import: "github.com/OmarAly92/operator/backend/internal/domain"
              type: "SessionID"
              pointer: true
          - column: "plan_assignments.project_id"
            go_type:
              import: "github.com/OmarAly92/operator/backend/internal/domain"
              type: "ProjectID"
          - column: "plan_assignments.session_id"
            go_type:
              import: "github.com/OmarAly92/operator/backend/internal/domain"
              type: "SessionID"
              pointer: true
          - column: "plan_assignments.reviewer_session_id"
            go_type:
              import: "github.com/OmarAly92/operator/backend/internal/domain"
              type: "SessionID"
              pointer: true
```

- [ ] **Step 4: Regenerate and confirm the generated names**

Run from the repo root: `npm run sqlc`
Expected: `backend/internal/storage/sqlite/gen/tickets.sql.go` exists with `ListTickets`, `GetTicket(ctx, arg GetTicketParams)`, `InsertTicket(ctx, arg InsertTicketParams)`, `SetTicketPlanningSession(ctx, arg …Params) (int64, error)`, `SetTicketArchivedAt(...) (int64, error)`, `TicketByPlanningSession(ctx, *domain.SessionID)`, `ListPlanAssignments(ctx, arg …Params)`, `InsertPlanAssignment(ctx, arg …Params)`, `PlanAssignmentBySession(ctx, *domain.SessionID)`; `gen/models.go` gains `Ticket{ProjectID domain.ProjectID; Slug string; PlanningSessionID *domain.SessionID; ArchivedAt sql.NullTime; CreatedAt time.Time}` and `PlanAssignment{ID int64; ProjectID domain.ProjectID; Slug, PlanFile string; SessionID *domain.SessionID; AssignedAt time.Time; DoneAt sql.NullTime; ReviewerSessionID *domain.SessionID; ReviewRequestedAt, MergeReadyAt sql.NullTime; MergeSummary string; MergeApprovedAt sql.NullTime}`; also `GetPlanAssignment(ctx, int64)`, `SetPlanAssignmentReviewRequested(ctx, arg …Params) (int64, error)`, `SetPlanAssignmentMergeReady(...)`, `SetPlanAssignmentMergeApproved(...)`. If a generated field name differs, adapt Step 6 to the generated name, never the reverse.

- [ ] **Step 5: Write the failing store test**

`backend/internal/storage/sqlite/store/ticket_store_test.go`:

```go
package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestTicketsInsertGetPlanningSessionArchive(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "tk")
	now := time.Now().UTC().Truncate(time.Second)
	if err := s.InsertTicket(ctx, domain.TicketRecord{ProjectID: "tk", Slug: "editor", CreatedAt: now}); err != nil {
		t.Fatal(err)
	}
	if err := s.InsertTicket(ctx, domain.TicketRecord{ProjectID: "tk", Slug: "auth", CreatedAt: now.Add(time.Second)}); err != nil {
		t.Fatal(err)
	}
	list, err := s.ListTickets(ctx, "tk")
	if err != nil || len(list) != 2 || list[0].Slug != "editor" || list[1].Slug != "auth" {
		t.Fatalf("list = %+v err = %v", list, err)
	}
	sess, err := s.CreateSession(ctx, domain.SessionRecord{
		ProjectID: "tk", Kind: domain.KindWorker, Harness: domain.HarnessClaudeCode,
		Activity:  domain.Activity{State: domain.ActivityIdle, LastActivityAt: now},
		Metadata:  domain.SessionMetadata{WorkspaceMode: domain.WorkspaceModeInPlace},
		CreatedAt: now, UpdatedAt: now,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := s.SetTicketPlanningSession(ctx, "tk", "editor", sess.ID); err != nil {
		t.Fatal(err)
	}
	got, ok, err := s.GetTicket(ctx, "tk", "editor")
	if err != nil || !ok || got.PlanningSessionID != sess.ID || !got.ArchivedAt.IsZero() {
		t.Fatalf("get = %+v ok=%v err=%v", got, ok, err)
	}
	ref, ok, err := s.SessionTicketRef(ctx, sess.ID)
	if err != nil || !ok || ref.Slug != "editor" || ref.Role != domain.TicketRolePlanning || ref.PlanFile != "" {
		t.Fatalf("ref = %+v ok=%v err=%v", ref, ok, err)
	}
	if err := s.SetTicketPlanningSession(ctx, "tk", "editor", ""); err != nil {
		t.Fatal(err)
	}
	if _, ok, _ := s.SessionTicketRef(ctx, sess.ID); ok {
		t.Fatal("cleared planning session still resolves a ref")
	}
	if err := s.SetTicketArchivedAt(ctx, "tk", "editor", now); err != nil {
		t.Fatal(err)
	}
	got, _, _ = s.GetTicket(ctx, "tk", "editor")
	if !got.ArchivedAt.Equal(now) {
		t.Fatalf("archived_at = %v want %v", got.ArchivedAt, now)
	}
	if err := s.SetTicketArchivedAt(ctx, "tk", "editor", time.Time{}); err != nil {
		t.Fatal(err)
	}
	got, _, _ = s.GetTicket(ctx, "tk", "editor")
	if !got.ArchivedAt.IsZero() {
		t.Fatalf("archived_at not cleared: %v", got.ArchivedAt)
	}
	if _, ok, err := s.GetTicket(ctx, "tk", "missing"); ok || err != nil {
		t.Fatalf("missing ticket ok=%v err=%v", ok, err)
	}
	if err := s.SetTicketPlanningSession(ctx, "tk", "missing", sess.ID); err == nil {
		t.Fatal("update of missing ticket should fail")
	}
}

func TestPlanAssignmentsNewestFirstAndRef(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "tk")
	now := time.Now().UTC().Truncate(time.Second)
	if err := s.InsertTicket(ctx, domain.TicketRecord{ProjectID: "tk", Slug: "editor", CreatedAt: now}); err != nil {
		t.Fatal(err)
	}
	mk := func() domain.SessionID {
		sess, err := s.CreateSession(ctx, domain.SessionRecord{
			ProjectID: "tk", Kind: domain.KindWorker, Harness: domain.HarnessClaudeCode,
			Activity:  domain.Activity{State: domain.ActivityIdle, LastActivityAt: now},
			Metadata:  domain.SessionMetadata{WorkspaceMode: domain.WorkspaceModeWorktree},
			CreatedAt: now, UpdatedAt: now,
		})
		if err != nil {
			t.Fatal(err)
		}
		return sess.ID
	}
	first, second := mk(), mk()
	if err := s.InsertPlanAssignment(ctx, domain.PlanAssignmentRecord{ProjectID: "tk", Slug: "editor", PlanFile: "plans/01-core.md", SessionID: first, AssignedAt: now}); err != nil {
		t.Fatal(err)
	}
	if err := s.InsertPlanAssignment(ctx, domain.PlanAssignmentRecord{ProjectID: "tk", Slug: "editor", PlanFile: "plans/01-core.md", SessionID: second, AssignedAt: now.Add(time.Second)}); err != nil {
		t.Fatal(err)
	}
	if err := s.InsertPlanAssignment(ctx, domain.PlanAssignmentRecord{ProjectID: "tk", Slug: "editor", PlanFile: "plans/02-ui.md", AssignedAt: now, DoneAt: now}); err != nil {
		t.Fatal(err)
	}
	rows, err := s.ListPlanAssignments(ctx, "tk", "editor")
	if err != nil || len(rows) != 3 {
		t.Fatalf("rows = %+v err = %v", rows, err)
	}
	if rows[0].PlanFile != "plans/02-ui.md" || rows[0].SessionID != "" || rows[0].DoneAt.IsZero() {
		t.Fatalf("newest row wrong: %+v", rows[0])
	}
	if rows[1].SessionID != second || rows[2].SessionID != first || rows[1].ID <= rows[2].ID {
		t.Fatalf("order wrong: %+v", rows)
	}
	ref, ok, err := s.SessionTicketRef(ctx, second)
	if err != nil || !ok || ref.Slug != "editor" || ref.PlanFile != "plans/01-core.md" || ref.Role != domain.TicketRoleImplementing {
		t.Fatalf("ref = %+v ok=%v err=%v", ref, ok, err)
	}
	if _, ok, _ := s.SessionTicketRef(ctx, "nope"); ok {
		t.Fatal("unknown session resolved a ref")
	}
	id := rows[1].ID
	reviewer := mk()
	if err := s.MarkPlanReviewRequested(ctx, id, reviewer, now); err != nil {
		t.Fatal(err)
	}
	if ref, ok, err := s.SessionTicketRef(ctx, reviewer); err != nil || !ok || ref.Role != domain.TicketRoleReviewing || ref.PlanFile != "plans/01-core.md" {
		t.Fatalf("reviewer ref = %+v ok=%v err=%v", ref, ok, err)
	}
	if err := s.MarkPlanMergeReady(ctx, id, now.Add(time.Second), "gates green, verified in app"); err != nil {
		t.Fatal(err)
	}
	if err := s.MarkPlanMergeApproved(ctx, id, now.Add(2*time.Second)); err != nil {
		t.Fatal(err)
	}
	got, ok, err := s.GetPlanAssignment(ctx, id)
	if err != nil || !ok || got.ReviewerSessionID != reviewer || !got.ReviewRequestedAt.Equal(now) || !got.MergeReadyAt.Equal(now.Add(time.Second)) || got.MergeSummary != "gates green, verified in app" || !got.MergeApprovedAt.Equal(now.Add(2*time.Second)) {
		t.Fatalf("assignment = %+v ok=%v err=%v", got, ok, err)
	}
	if err := s.MarkPlanMergeReady(ctx, 9999, now, "x"); err == nil {
		t.Fatal("unknown assignment must fail")
	}
}

func TestTicketsEmitTicketUpdatedCDC(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "tk")
	head, err := s.LatestSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC()
	if err := s.InsertTicket(ctx, domain.TicketRecord{ProjectID: "tk", Slug: "editor", CreatedAt: now}); err != nil {
		t.Fatal(err)
	}
	if err := s.SetTicketArchivedAt(ctx, "tk", "editor", now); err != nil {
		t.Fatal(err)
	}
	if err := s.InsertPlanAssignment(ctx, domain.PlanAssignmentRecord{ProjectID: "tk", Slug: "editor", PlanFile: "plans/01-core.md", AssignedAt: now, DoneAt: now}); err != nil {
		t.Fatal(err)
	}
	events, err := s.EventsAfter(ctx, head, 100)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.MarkPlanMergeReady(ctx, 1, now, "ready"); err != nil {
		t.Fatal(err)
	}
	if len(events) != 3 {
		t.Fatalf("events = %+v, want three ticket_updated", events)
	}
	events, err = s.EventsAfter(ctx, head, 100)
	if err != nil || len(events) != 4 || string(events[3].Type) != "ticket_updated" {
		t.Fatalf("after merge-ready events = %+v err=%v", events, err)
	}
	for _, e := range events {
		if string(e.Type) != "ticket_updated" || e.ProjectID != "tk" || e.SessionID != "" {
			t.Fatalf("event = %+v", e)
		}
	}
}
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `cd backend && go test ./internal/storage/sqlite/store/ -run 'TestTickets|TestPlanAssignments' -v`
Expected: compile error, `s.InsertTicket undefined`.

- [ ] **Step 7: Write the store**

`backend/internal/storage/sqlite/store/ticket_store.go`:

```go
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/gen"
)

var errTicketNotFound = errors.New("ticket not found")

func ticketFromGen(row gen.Ticket) domain.TicketRecord {
	rec := domain.TicketRecord{ProjectID: row.ProjectID, Slug: row.Slug, CreatedAt: row.CreatedAt}
	if row.PlanningSessionID != nil {
		rec.PlanningSessionID = *row.PlanningSessionID
	}
	if row.ArchivedAt.Valid {
		rec.ArchivedAt = row.ArchivedAt.Time
	}
	return rec
}

func planAssignmentFromGen(row gen.PlanAssignment) domain.PlanAssignmentRecord {
	rec := domain.PlanAssignmentRecord{ID: row.ID, ProjectID: row.ProjectID, Slug: row.Slug, PlanFile: row.PlanFile, AssignedAt: row.AssignedAt}
	if row.SessionID != nil {
		rec.SessionID = *row.SessionID
	}
	if row.DoneAt.Valid {
		rec.DoneAt = row.DoneAt.Time
	}
	if row.ReviewerSessionID != nil {
		rec.ReviewerSessionID = *row.ReviewerSessionID
	}
	if row.ReviewRequestedAt.Valid {
		rec.ReviewRequestedAt = row.ReviewRequestedAt.Time
	}
	if row.MergeReadyAt.Valid {
		rec.MergeReadyAt = row.MergeReadyAt.Time
	}
	rec.MergeSummary = row.MergeSummary
	if row.MergeApprovedAt.Valid {
		rec.MergeApprovedAt = row.MergeApprovedAt.Time
	}
	return rec
}

func optionalSessionID(id domain.SessionID) *domain.SessionID {
	if id == "" {
		return nil
	}
	return &id
}

func optionalTime(t time.Time) sql.NullTime {
	if t.IsZero() {
		return sql.NullTime{}
	}
	return sql.NullTime{Time: t, Valid: true}
}

func (s *Store) ListTickets(ctx context.Context, project domain.ProjectID) ([]domain.TicketRecord, error) {
	rows, err := s.qr.ListTickets(ctx, project)
	if err != nil {
		return nil, fmt.Errorf("list tickets %s: %w", project, err)
	}
	out := make([]domain.TicketRecord, 0, len(rows))
	for _, row := range rows {
		out = append(out, ticketFromGen(row))
	}
	return out, nil
}

func (s *Store) GetTicket(ctx context.Context, project domain.ProjectID, slug string) (domain.TicketRecord, bool, error) {
	row, err := s.qr.GetTicket(ctx, gen.GetTicketParams{ProjectID: project, Slug: slug})
	if errors.Is(err, sql.ErrNoRows) {
		return domain.TicketRecord{}, false, nil
	}
	if err != nil {
		return domain.TicketRecord{}, false, fmt.Errorf("get ticket %s/%s: %w", project, slug, err)
	}
	return ticketFromGen(row), true, nil
}

func (s *Store) InsertTicket(ctx context.Context, rec domain.TicketRecord) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	err := s.qw.InsertTicket(ctx, gen.InsertTicketParams{
		ProjectID:         rec.ProjectID,
		Slug:              rec.Slug,
		PlanningSessionID: optionalSessionID(rec.PlanningSessionID),
		ArchivedAt:        optionalTime(rec.ArchivedAt),
		CreatedAt:         rec.CreatedAt,
	})
	if err != nil {
		return fmt.Errorf("insert ticket %s/%s: %w", rec.ProjectID, rec.Slug, err)
	}
	return nil
}

func (s *Store) SetTicketPlanningSession(ctx context.Context, project domain.ProjectID, slug string, session domain.SessionID) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	n, err := s.qw.SetTicketPlanningSession(ctx, gen.SetTicketPlanningSessionParams{PlanningSessionID: optionalSessionID(session), ProjectID: project, Slug: slug})
	if err != nil {
		return fmt.Errorf("set ticket planning session %s/%s: %w", project, slug, err)
	}
	if n == 0 {
		return errTicketNotFound
	}
	return nil
}

func (s *Store) SetTicketArchivedAt(ctx context.Context, project domain.ProjectID, slug string, at time.Time) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	n, err := s.qw.SetTicketArchivedAt(ctx, gen.SetTicketArchivedAtParams{ArchivedAt: optionalTime(at), ProjectID: project, Slug: slug})
	if err != nil {
		return fmt.Errorf("set ticket archived %s/%s: %w", project, slug, err)
	}
	if n == 0 {
		return errTicketNotFound
	}
	return nil
}

func (s *Store) ListPlanAssignments(ctx context.Context, project domain.ProjectID, slug string) ([]domain.PlanAssignmentRecord, error) {
	rows, err := s.qr.ListPlanAssignments(ctx, gen.ListPlanAssignmentsParams{ProjectID: project, Slug: slug})
	if err != nil {
		return nil, fmt.Errorf("list plan assignments %s/%s: %w", project, slug, err)
	}
	out := make([]domain.PlanAssignmentRecord, 0, len(rows))
	for _, row := range rows {
		out = append(out, planAssignmentFromGen(row))
	}
	return out, nil
}

func (s *Store) InsertPlanAssignment(ctx context.Context, rec domain.PlanAssignmentRecord) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	err := s.qw.InsertPlanAssignment(ctx, gen.InsertPlanAssignmentParams{
		ProjectID:  rec.ProjectID,
		Slug:       rec.Slug,
		PlanFile:   rec.PlanFile,
		SessionID:  optionalSessionID(rec.SessionID),
		AssignedAt: rec.AssignedAt,
		DoneAt:     optionalTime(rec.DoneAt),
	})
	if err != nil {
		return fmt.Errorf("insert plan assignment %s/%s %s: %w", rec.ProjectID, rec.Slug, rec.PlanFile, err)
	}
	return nil
}

func (s *Store) SessionTicketRef(ctx context.Context, id domain.SessionID) (domain.SessionTicketRef, bool, error) {
	if id == "" {
		return domain.SessionTicketRef{}, false, nil
	}
	ticket, err := s.qr.TicketByPlanningSession(ctx, &id)
	if err == nil {
		return domain.SessionTicketRef{Slug: ticket.Slug, Role: domain.TicketRolePlanning}, true, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return domain.SessionTicketRef{}, false, fmt.Errorf("ticket by planning session %s: %w", id, err)
	}
	assignment, err := s.qr.PlanAssignmentBySession(ctx, &id)
	if err == nil {
		return domain.SessionTicketRef{Slug: assignment.Slug, PlanFile: assignment.PlanFile, Role: domain.TicketRoleImplementing}, true, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return domain.SessionTicketRef{}, false, fmt.Errorf("plan assignment by session %s: %w", id, err)
	}
	review, err := s.qr.PlanAssignmentByReviewer(ctx, &id)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.SessionTicketRef{}, false, nil
	}
	if err != nil {
		return domain.SessionTicketRef{}, false, fmt.Errorf("plan assignment by reviewer %s: %w", id, err)
	}
	return domain.SessionTicketRef{Slug: review.Slug, PlanFile: review.PlanFile, Role: domain.TicketRoleReviewing}, true, nil
}

func (s *Store) GetPlanAssignment(ctx context.Context, id int64) (domain.PlanAssignmentRecord, bool, error) {
	row, err := s.qr.GetPlanAssignment(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.PlanAssignmentRecord{}, false, nil
	}
	if err != nil {
		return domain.PlanAssignmentRecord{}, false, fmt.Errorf("get plan assignment %d: %w", id, err)
	}
	return planAssignmentFromGen(row), true, nil
}

var errPlanAssignmentNotFound = errors.New("plan assignment not found")

func (s *Store) MarkPlanReviewRequested(ctx context.Context, id int64, reviewer domain.SessionID, at time.Time) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	n, err := s.qw.SetPlanAssignmentReviewRequested(ctx, gen.SetPlanAssignmentReviewRequestedParams{ReviewerSessionID: optionalSessionID(reviewer), ReviewRequestedAt: optionalTime(at), ID: id})
	if err != nil {
		return fmt.Errorf("mark plan review requested %d: %w", id, err)
	}
	if n == 0 {
		return errPlanAssignmentNotFound
	}
	return nil
}

func (s *Store) MarkPlanMergeReady(ctx context.Context, id int64, at time.Time, summary string) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	n, err := s.qw.SetPlanAssignmentMergeReady(ctx, gen.SetPlanAssignmentMergeReadyParams{MergeReadyAt: optionalTime(at), MergeSummary: summary, ID: id})
	if err != nil {
		return fmt.Errorf("mark plan merge ready %d: %w", id, err)
	}
	if n == 0 {
		return errPlanAssignmentNotFound
	}
	return nil
}

func (s *Store) MarkPlanMergeApproved(ctx context.Context, id int64, at time.Time) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	n, err := s.qw.SetPlanAssignmentMergeApproved(ctx, gen.SetPlanAssignmentMergeApprovedParams{MergeApprovedAt: optionalTime(at), ID: id})
	if err != nil {
		return fmt.Errorf("mark plan merge approved %d: %w", id, err)
	}
	if n == 0 {
		return errPlanAssignmentNotFound
	}
	return nil
}
```

If sqlc generated the `Params` field order or names differently (Step 4), match the generated struct.

- [ ] **Step 8: Add the CDC event type and the frontend subscription**

In `backend/internal/cdc/event.go` add to the const block after `EventPRReviewThreadResolved`:

```go
	EventTicketUpdated          EventType = "ticket_updated"
```

In `frontend/src/renderer/lib/event-transport.ts` add `"ticket_updated",` as the last entry of `CDC_EVENT_TYPES`. Nothing in the frontend consumes it yet; plan 2 wires the query invalidation.

- [ ] **Step 9: Run the tests**

Run: `cd backend && go test ./internal/storage/sqlite/... && cd ../frontend && npm run typecheck`
Expected: PASS, including `migrate_unique_version_test` and the existing CDC tests.

- [ ] **Step 10: Commit**

```bash
git add backend/internal/domain/ticket.go backend/internal/storage/sqlite backend/sqlc.yaml backend/internal/cdc/event.go frontend/src/renderer/lib/event-transport.ts
git commit -m "feat(tickets): ticket and plan assignment tables with store and CDC event"
```

---

### Task 2: Frontmatter, slug and folder scanner

**Files:**
- Create: `backend/internal/service/ticket/frontmatter.go`, `frontmatter_test.go`
- Create: `backend/internal/service/ticket/slug.go`, `slug_test.go`
- Create: `backend/internal/service/ticket/scan.go`, `scan_test.go`

**Interfaces:**
- Produces:
  - `parseFrontmatter(content []byte) (frontmatter, string, error)` where `frontmatter{Title, Brief, Created string}` and the string is the body after the fences.
  - `titleOf(fm frontmatter, body, fallback string) string` — frontmatter title, else first `# ` heading, else `fallback`.
  - `slugify(title string) string` — kebab-case, max 48 runes, never empty (`"ticket"` fallback).
  - `scannedTicket{Slug, Title, Brief string; Plans []scannedPlan; Files []string; Warning string}`, `scannedPlan{File string; Order int; Title string; Kickoff string; Unordered bool; Warning string}` where `Kickoff` is `plans/NN-<phase>.kickoff.md` when that file exists, else empty.
  - `scanTickets(root string) ([]scannedTicket, error)` — `root` is `<project>/.operator/tickets`; a missing root yields an empty slice and nil error.
  - `scanTicket(root, slug string) (scannedTicket, bool, error)`.
  - `planOrder(name string) (int, bool)` — parses the numeric prefix of `NN-<phase>.md`.

- [ ] **Step 1: Write the failing frontmatter and slug tests**

`backend/internal/service/ticket/frontmatter_test.go`:

```go
package ticket

import "testing"

func TestParseFrontmatter(t *testing.T) {
	fm, body, err := parseFrontmatter([]byte("---\ntitle: Editor\nbrief: Add an editor\ncreated: 2026-09-18\n---\n# Editor\n\nBody\n"))
	if err != nil {
		t.Fatal(err)
	}
	if fm.Title != "Editor" || fm.Brief != "Add an editor" || fm.Created != "2026-09-18" {
		t.Fatalf("fm = %+v", fm)
	}
	if body != "# Editor\n\nBody\n" {
		t.Fatalf("body = %q", body)
	}
}

func TestParseFrontmatterAbsent(t *testing.T) {
	fm, body, err := parseFrontmatter([]byte("# Just a heading\n"))
	if err != nil || fm.Title != "" || body != "# Just a heading\n" {
		t.Fatalf("fm=%+v body=%q err=%v", fm, body, err)
	}
}

func TestParseFrontmatterMalformed(t *testing.T) {
	if _, _, err := parseFrontmatter([]byte("---\ntitle: [oops\n---\n")); err == nil {
		t.Fatal("want yaml error")
	}
	if _, _, err := parseFrontmatter([]byte("---\ntitle: x\n")); err == nil {
		t.Fatal("want unterminated error")
	}
}

func TestTitleOf(t *testing.T) {
	if got := titleOf(frontmatter{Title: "From FM"}, "# Heading\n", "file"); got != "From FM" {
		t.Fatal(got)
	}
	if got := titleOf(frontmatter{}, "intro\n\n#   Heading here  \n", "file"); got != "Heading here" {
		t.Fatal(got)
	}
	if got := titleOf(frontmatter{}, "no heading", "01-core"); got != "01-core" {
		t.Fatal(got)
	}
}
```

`backend/internal/service/ticket/slug_test.go`:

```go
package ticket

import (
	"strings"
	"testing"
)

func TestSlugify(t *testing.T) {
	cases := map[string]string{
		"Planning Tickets":            "planning-tickets",
		"  Add   CodeMirror editor!! ": "add-codemirror-editor",
		"Ünïcödé ✓ title":              "n-c-d-title",
		"---":                          "ticket",
		"":                             "ticket",
		strings.Repeat("a", 60):        strings.Repeat("a", 48),
		"Trailing-":                    "trailing",
	}
	for in, want := range cases {
		if got := slugify(in); got != want {
			t.Errorf("slugify(%q) = %q want %q", in, got, want)
		}
	}
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd backend && go test ./internal/service/ticket/ -run 'TestParseFrontmatter|TestTitleOf|TestSlugify'`
Expected: build failure, undefined `parseFrontmatter`.

- [ ] **Step 3: Implement frontmatter and slug**

`backend/internal/service/ticket/frontmatter.go`:

```go
package ticket

import (
	"bytes"
	"errors"
	"fmt"
	"strings"

	"gopkg.in/yaml.v3"
)

type frontmatter struct {
	Title   string `yaml:"title"`
	Brief   string `yaml:"brief"`
	Created string `yaml:"created"`
}

var fence = []byte("---\n")

func parseFrontmatter(content []byte) (frontmatter, string, error) {
	content = bytes.ReplaceAll(content, []byte("\r\n"), []byte("\n"))
	if !bytes.HasPrefix(content, fence) {
		return frontmatter{}, string(content), nil
	}
	rest := content[len(fence):]
	end := bytes.Index(rest, []byte("\n---"))
	if end < 0 {
		return frontmatter{}, "", errors.New("frontmatter: unterminated fence")
	}
	head := rest[:end+1]
	body := rest[end+len("\n---"):]
	body = bytes.TrimPrefix(body, []byte("\n"))
	var fm frontmatter
	if err := yaml.Unmarshal(head, &fm); err != nil {
		return frontmatter{}, "", fmt.Errorf("frontmatter: %w", err)
	}
	return fm, string(body), nil
}

func titleOf(fm frontmatter, body, fallback string) string {
	if t := strings.TrimSpace(fm.Title); t != "" {
		return t
	}
	for _, line := range strings.Split(body, "\n") {
		if strings.HasPrefix(line, "# ") {
			if t := strings.TrimSpace(strings.TrimPrefix(line, "# ")); t != "" {
				return t
			}
		}
	}
	return fallback
}
```

`backend/internal/service/ticket/slug.go`:

```go
package ticket

import (
	"strings"
	"unicode"
)

const maxSlugLen = 48

func slugify(title string) string {
	var b strings.Builder
	lastDash := true
	for _, r := range strings.ToLower(title) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
			lastDash = false
		case unicode.IsLetter(r) || unicode.IsDigit(r) || unicode.IsSpace(r) || unicode.IsPunct(r) || unicode.IsSymbol(r):
			if !lastDash {
				b.WriteByte('-')
				lastDash = true
			}
		}
	}
	out := strings.Trim(b.String(), "-")
	if len(out) > maxSlugLen {
		out = strings.Trim(out[:maxSlugLen], "-")
	}
	if out == "" {
		return "ticket"
	}
	return out
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && go test ./internal/service/ticket/ -run 'TestParseFrontmatter|TestTitleOf|TestSlugify' -v`
Expected: PASS. If `"Ünïcödé ✓ title"` does not produce `n-c-d-title` exactly, fix the implementation, not the expectation: every non-ASCII letter collapses into a dash boundary.

- [ ] **Step 5: Write the failing scanner test**

`backend/internal/service/ticket/scan_test.go`:

```go
package ticket

import (
	"os"
	"path/filepath"
	"testing"
)

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestScanTicketsMissingRoot(t *testing.T) {
	got, err := scanTickets(filepath.Join(t.TempDir(), "nope"))
	if err != nil || len(got) != 0 {
		t.Fatalf("got %+v err %v", got, err)
	}
}

func TestScanTicketsLayoutAndOrder(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "editor", "ticket.md"), "---\ntitle: Editor\nbrief: Add it\n---\nnotes\n")
	writeFile(t, filepath.Join(root, "editor", "spec.md"), "# Editor spec\n")
	writeFile(t, filepath.Join(root, "editor", "plans", "10-ui.md"), "---\ntitle: UI\n---\n")
	writeFile(t, filepath.Join(root, "editor", "plans", "02-daemon.md"), "# Daemon phase\n")
	writeFile(t, filepath.Join(root, "editor", "plans", "02-daemon.kickoff.md"), "Execute plan 02.\n")
	writeFile(t, filepath.Join(root, "editor", "plans", "notes.md"), "# Loose\n")
	writeFile(t, filepath.Join(root, "editor", "plans", "README.txt"), "ignored\n")
	writeFile(t, filepath.Join(root, "auth", "ticket.md"), "# Auth from heading\n")
	writeFile(t, filepath.Join(root, "stray.md"), "not a ticket\n")
	if err := os.MkdirAll(filepath.Join(root, "empty"), 0o755); err != nil {
		t.Fatal(err)
	}

	got, err := scanTickets(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].Slug != "auth" || got[1].Slug != "editor" {
		t.Fatalf("slugs = %+v", got)
	}
	auth := got[0]
	if auth.Title != "Auth from heading" || auth.Brief != "" || len(auth.Plans) != 0 {
		t.Fatalf("auth = %+v", auth)
	}
	ed := got[1]
	if ed.Title != "Editor" || ed.Brief != "Add it" {
		t.Fatalf("editor = %+v", ed)
	}
	wantFiles := []string{"ticket.md", "spec.md", "plans/02-daemon.md", "plans/02-daemon.kickoff.md", "plans/10-ui.md", "plans/notes.md"}
	if len(ed.Files) != len(wantFiles) {
		t.Fatalf("files = %v", ed.Files)
	}
	for i := range wantFiles {
		if ed.Files[i] != wantFiles[i] {
			t.Fatalf("files = %v want %v", ed.Files, wantFiles)
		}
	}
	if len(ed.Plans) != 3 {
		t.Fatalf("plans = %+v", ed.Plans)
	}
	if ed.Plans[0].File != "plans/02-daemon.md" || ed.Plans[0].Order != 2 || ed.Plans[0].Title != "Daemon phase" || ed.Plans[0].Kickoff != "plans/02-daemon.kickoff.md" {
		t.Fatalf("plan0 = %+v", ed.Plans[0])
	}
	if ed.Plans[1].File != "plans/10-ui.md" || ed.Plans[1].Order != 10 || ed.Plans[1].Title != "UI" || ed.Plans[1].Kickoff != "" {
		t.Fatalf("plan1 = %+v", ed.Plans[1])
	}
	if ed.Plans[2].File != "plans/notes.md" || !ed.Plans[2].Unordered || ed.Plans[2].Warning == "" || ed.Plans[2].Title != "Loose" {
		t.Fatalf("plan2 = %+v", ed.Plans[2])
	}
}

func TestScanTicketMalformedFrontmatterWarns(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "bad", "ticket.md"), "---\ntitle: [oops\n---\n")
	got, ok, err := scanTicket(root, "bad")
	if err != nil || !ok {
		t.Fatalf("ok=%v err=%v", ok, err)
	}
	if got.Warning == "" || got.Title != "bad" {
		t.Fatalf("got %+v", got)
	}
	if _, ok, err := scanTicket(root, "missing"); ok || err != nil {
		t.Fatalf("missing ok=%v err=%v", ok, err)
	}
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `cd backend && go test ./internal/service/ticket/ -run TestScan`
Expected: undefined `scanTickets`.

- [ ] **Step 7: Implement the scanner**

`backend/internal/service/ticket/scan.go`:

```go
package ticket

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type scannedPlan struct {
	File      string
	Order     int
	Title     string
	Kickoff   string
	Unordered bool
	Warning   string
}

const kickoffSuffix = ".kickoff.md"

type scannedTicket struct {
	Slug    string
	Title   string
	Brief   string
	Plans   []scannedPlan
	Files   []string
	Warning string
}

var planPrefix = regexp.MustCompile(`^(\d{1,3})-.+\.md$`)

func planOrder(name string) (int, bool) {
	m := planPrefix.FindStringSubmatch(name)
	if m == nil {
		return 0, false
	}
	n, err := strconv.Atoi(m[1])
	if err != nil {
		return 0, false
	}
	return n, true
}

func scanTickets(root string) ([]scannedTicket, error) {
	entries, err := os.ReadDir(root)
	if errors.Is(err, os.ErrNotExist) {
		return []scannedTicket{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read tickets dir: %w", err)
	}
	out := make([]scannedTicket, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		t, ok, err := scanTicket(root, e.Name())
		if err != nil {
			return nil, err
		}
		if ok {
			out = append(out, t)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Slug < out[j].Slug })
	return out, nil
}

func scanTicket(root, slug string) (scannedTicket, bool, error) {
	dir := filepath.Join(root, slug)
	ticketPath := filepath.Join(dir, "ticket.md")
	raw, err := os.ReadFile(ticketPath)
	if errors.Is(err, os.ErrNotExist) {
		return scannedTicket{}, false, nil
	}
	if err != nil {
		return scannedTicket{}, false, fmt.Errorf("read %s: %w", ticketPath, err)
	}
	t := scannedTicket{Slug: slug, Files: []string{"ticket.md"}}
	fm, body, err := parseFrontmatter(raw)
	if err != nil {
		t.Warning = "ticket.md: " + err.Error()
	}
	t.Title = titleOf(fm, body, slug)
	t.Brief = strings.TrimSpace(fm.Brief)
	if _, err := os.Stat(filepath.Join(dir, "spec.md")); err == nil {
		t.Files = append(t.Files, "spec.md")
	}
	plans, err := os.ReadDir(filepath.Join(dir, "plans"))
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return scannedTicket{}, false, fmt.Errorf("read plans dir %s: %w", slug, err)
	}
	kickoffs := map[string]bool{}
	for _, e := range plans {
		if !e.IsDir() && strings.HasSuffix(e.Name(), kickoffSuffix) {
			kickoffs[e.Name()] = true
		}
	}
	for _, e := range plans {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".md") || strings.HasSuffix(e.Name(), kickoffSuffix) {
			continue
		}
		p := scannedPlan{File: "plans/" + e.Name()}
		if kick := strings.TrimSuffix(e.Name(), ".md") + kickoffSuffix; kickoffs[kick] {
			p.Kickoff = "plans/" + kick
		}
		if n, ok := planOrder(e.Name()); ok {
			p.Order = n
		} else {
			p.Unordered = true
			p.Warning = "plan file has no numeric prefix; listed last"
		}
		raw, err := os.ReadFile(filepath.Join(dir, "plans", e.Name()))
		if err != nil {
			return scannedTicket{}, false, fmt.Errorf("read plan %s/%s: %w", slug, e.Name(), err)
		}
		fm, body, err := parseFrontmatter(raw)
		if err != nil {
			p.Warning = err.Error()
		}
		p.Title = titleOf(fm, body, strings.TrimSuffix(e.Name(), ".md"))
		t.Plans = append(t.Plans, p)
	}
	sort.SliceStable(t.Plans, func(i, j int) bool {
		a, b := t.Plans[i], t.Plans[j]
		if a.Unordered != b.Unordered {
			return !a.Unordered
		}
		if a.Order != b.Order {
			return a.Order < b.Order
		}
		return a.File < b.File
	})
	for _, p := range t.Plans {
		t.Files = append(t.Files, p.File)
		if p.Kickoff != "" {
			t.Files = append(t.Files, p.Kickoff)
		}
	}
	return t, true, nil
}
```

- [ ] **Step 8: Run the whole package**

Run: `cd backend && go test ./internal/service/ticket/ -v`
Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add backend/internal/service/ticket
git commit -m "feat(tickets): frontmatter, slug and ticket folder scanner"
```

---

### Task 3: Status derivation

**Files:**
- Create: `backend/internal/service/ticket/status.go`, `status_test.go`

**Interfaces:**
- Consumes: `domain.SessionStatus` values (`domain/status.go`), `domain.PlanAssignmentRecord`, `domain.TicketRecord`.
- Produces:
  - `currentAssignments(rows []domain.PlanAssignmentRecord) map[string]domain.PlanAssignmentRecord` — newest row per `PlanFile` (rows arrive newest first).
  - `planStatus(a domain.PlanAssignmentRecord, ok bool, sess *domain.Session) domain.PlanStatus`.
  - `ticketStatus(rec domain.TicketRecord, plans []domain.Plan, planning *domain.Session) domain.TicketStatus`.
  - `planLive(status domain.PlanStatus) bool` — true for `idle`, `working`, `needs_you`, `in_review`, `reviewing`, `awaiting_merge`.
  - Derivation order for a plan: no assignment → `todo`; `DoneAt` → `done`; session merged → `merged`; `MergeReadyAt` set and `MergeApprovedAt` zero → `awaiting_merge`; `ReviewRequestedAt` set → `reviewing`; otherwise the session-derived statuses. Ticket: `awaiting_merge` when any plan is awaiting merge, checked before `in_progress`.

- [ ] **Step 1: Write the failing table test**

`backend/internal/service/ticket/status_test.go`:

```go
package ticket

import (
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func sessWith(status domain.SessionStatus) *domain.Session {
	return &domain.Session{SessionRecord: domain.SessionRecord{ID: "p-1"}, Status: status}
}

func TestPlanStatusTable(t *testing.T) {
	a := domain.PlanAssignmentRecord{SessionID: "p-1"}
	cases := []struct {
		name string
		a    domain.PlanAssignmentRecord
		ok   bool
		sess *domain.Session
		want domain.PlanStatus
	}{
		{"no assignment", domain.PlanAssignmentRecord{}, false, nil, domain.PlanStatusTodo},
		{"done wins", domain.PlanAssignmentRecord{DoneAt: time.Now()}, true, sessWith(domain.StatusWorking), domain.PlanStatusDone},
		{"session missing", a, true, nil, domain.PlanStatusTerminated},
		{"working", a, true, sessWith(domain.StatusWorking), domain.PlanStatusWorking},
		{"needs input", a, true, sessWith(domain.StatusNeedsInput), domain.PlanStatusNeedsYou},
		{"pr open", a, true, sessWith(domain.StatusPROpen), domain.PlanStatusInReview},
		{"draft", a, true, sessWith(domain.StatusDraft), domain.PlanStatusInReview},
		{"ci failed", a, true, sessWith(domain.StatusCIFailed), domain.PlanStatusInReview},
		{"review pending", a, true, sessWith(domain.StatusReviewPending), domain.PlanStatusInReview},
		{"changes requested", a, true, sessWith(domain.StatusChangesRequested), domain.PlanStatusInReview},
		{"approved", a, true, sessWith(domain.StatusApproved), domain.PlanStatusInReview},
		{"mergeable", a, true, sessWith(domain.StatusMergeable), domain.PlanStatusInReview},
		{"merged", a, true, sessWith(domain.StatusMerged), domain.PlanStatusMerged},
		{"merged beats awaiting", domain.PlanAssignmentRecord{SessionID: "p-1", MergeReadyAt: time.Now()}, true, sessWith(domain.StatusMerged), domain.PlanStatusMerged},
		{"awaiting merge", domain.PlanAssignmentRecord{SessionID: "p-1", ReviewRequestedAt: time.Now(), MergeReadyAt: time.Now()}, true, sessWith(domain.StatusPROpen), domain.PlanStatusAwaitMerge},
		{"approved goes back to reviewing", domain.PlanAssignmentRecord{SessionID: "p-1", ReviewRequestedAt: time.Now(), MergeReadyAt: time.Now(), MergeApprovedAt: time.Now()}, true, sessWith(domain.StatusPROpen), domain.PlanStatusReviewing},
		{"reviewing", domain.PlanAssignmentRecord{SessionID: "p-1", ReviewRequestedAt: time.Now()}, true, sessWith(domain.StatusPROpen), domain.PlanStatusReviewing},
		{"reviewing even when implementer terminated", domain.PlanAssignmentRecord{SessionID: "p-1", ReviewRequestedAt: time.Now()}, true, sessWith(domain.StatusTerminated), domain.PlanStatusReviewing},
		{"terminated", a, true, sessWith(domain.StatusTerminated), domain.PlanStatusTerminated},
		{"exited", a, true, sessWith(domain.StatusExited), domain.PlanStatusTerminated},
		{"idle", a, true, sessWith(domain.StatusIdle), domain.PlanStatusIdle},
		{"no signal", a, true, sessWith(domain.StatusNoSignal), domain.PlanStatusIdle},
	}
	for _, tc := range cases {
		if got := planStatus(tc.a, tc.ok, tc.sess); got != tc.want {
			t.Errorf("%s: got %q want %q", tc.name, got, tc.want)
		}
	}
}

func TestCurrentAssignmentsNewestWins(t *testing.T) {
	rows := []domain.PlanAssignmentRecord{
		{ID: 3, PlanFile: "plans/01-a.md", SessionID: "p-3"},
		{ID: 2, PlanFile: "plans/02-b.md", SessionID: "p-2"},
		{ID: 1, PlanFile: "plans/01-a.md", SessionID: "p-1"},
	}
	got := currentAssignments(rows)
	if len(got) != 2 || got["plans/01-a.md"].SessionID != "p-3" || got["plans/02-b.md"].SessionID != "p-2" {
		t.Fatalf("got %+v", got)
	}
}

func TestTicketStatusTable(t *testing.T) {
	plan := func(s domain.PlanStatus) domain.Plan { return domain.Plan{Status: s} }
	cases := []struct {
		name     string
		rec      domain.TicketRecord
		plans    []domain.Plan
		planning *domain.Session
		want     domain.TicketStatus
	}{
		{"archived beats everything", domain.TicketRecord{ArchivedAt: time.Now()}, []domain.Plan{plan(domain.PlanStatusWorking)}, nil, domain.TicketStatusArchived},
		{"draft", domain.TicketRecord{}, nil, nil, domain.TicketStatusDraft},
		{"planning", domain.TicketRecord{PlanningSessionID: "p-1"}, nil, sessWith(domain.StatusWorking), domain.TicketStatusPlanning},
		{"planning session terminated is draft", domain.TicketRecord{PlanningSessionID: "p-1"}, nil, sessWith(domain.StatusTerminated), domain.TicketStatusDraft},
		{"planning session gone is draft", domain.TicketRecord{PlanningSessionID: "p-1"}, nil, nil, domain.TicketStatusDraft},
		{"ready", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusTodo)}, nil, domain.TicketStatusReady},
		{"ready while planning still open", domain.TicketRecord{PlanningSessionID: "p-1"}, []domain.Plan{plan(domain.PlanStatusTodo)}, sessWith(domain.StatusIdle), domain.TicketStatusPlanning},
		{"in progress", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusMerged), plan(domain.PlanStatusWorking)}, nil, domain.TicketStatusInProgress},
		{"in review counts as progress", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusInReview), plan(domain.PlanStatusTodo)}, nil, domain.TicketStatusInProgress},
		{"awaiting merge outranks progress", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusWorking), plan(domain.PlanStatusAwaitMerge)}, nil, domain.TicketStatusAwaitMerge},
		{"reviewing is progress", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusReviewing)}, nil, domain.TicketStatusInProgress},
		{"terminated only is ready", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusTerminated), plan(domain.PlanStatusTodo)}, nil, domain.TicketStatusReady},
		{"done", domain.TicketRecord{}, []domain.Plan{plan(domain.PlanStatusMerged), plan(domain.PlanStatusDone)}, nil, domain.TicketStatusDone},
	}
	for _, tc := range cases {
		if got := ticketStatus(tc.rec, tc.plans, tc.planning); got != tc.want {
			t.Errorf("%s: got %q want %q", tc.name, got, tc.want)
		}
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && go test ./internal/service/ticket/ -run 'Status|CurrentAssignments'`
Expected: undefined `planStatus`.

- [ ] **Step 3: Implement**

`backend/internal/service/ticket/status.go`:

```go
package ticket

import "github.com/OmarAly92/operator/backend/internal/domain"

func currentAssignments(rows []domain.PlanAssignmentRecord) map[string]domain.PlanAssignmentRecord {
	out := make(map[string]domain.PlanAssignmentRecord, len(rows))
	for _, row := range rows {
		if _, seen := out[row.PlanFile]; !seen {
			out[row.PlanFile] = row
		}
	}
	return out
}

func planStatus(a domain.PlanAssignmentRecord, ok bool, sess *domain.Session) domain.PlanStatus {
	if !ok {
		return domain.PlanStatusTodo
	}
	if !a.DoneAt.IsZero() {
		return domain.PlanStatusDone
	}
	if sess != nil && sess.Status == domain.StatusMerged {
		return domain.PlanStatusMerged
	}
	if !a.MergeReadyAt.IsZero() && a.MergeApprovedAt.IsZero() {
		return domain.PlanStatusAwaitMerge
	}
	if !a.ReviewRequestedAt.IsZero() {
		return domain.PlanStatusReviewing
	}
	if sess == nil {
		return domain.PlanStatusTerminated
	}
	switch sess.Status {
	case domain.StatusWorking:
		return domain.PlanStatusWorking
	case domain.StatusNeedsInput:
		return domain.PlanStatusNeedsYou
	case domain.StatusPROpen, domain.StatusDraft, domain.StatusCIFailed, domain.StatusReviewPending,
		domain.StatusChangesRequested, domain.StatusApproved, domain.StatusMergeable:
		return domain.PlanStatusInReview
	case domain.StatusMerged:
		return domain.PlanStatusMerged
	case domain.StatusTerminated, domain.StatusExited:
		return domain.PlanStatusTerminated
	default:
		return domain.PlanStatusIdle
	}
}

func planLive(status domain.PlanStatus) bool {
	switch status {
	case domain.PlanStatusIdle, domain.PlanStatusWorking, domain.PlanStatusNeedsYou, domain.PlanStatusInReview,
		domain.PlanStatusReviewing, domain.PlanStatusAwaitMerge:
		return true
	default:
		return false
	}
}

func ticketStatus(rec domain.TicketRecord, plans []domain.Plan, planning *domain.Session) domain.TicketStatus {
	if !rec.ArchivedAt.IsZero() {
		return domain.TicketStatusArchived
	}
	if len(plans) > 0 {
		allSettled := true
		for _, p := range plans {
			if p.Status != domain.PlanStatusMerged && p.Status != domain.PlanStatusDone {
				allSettled = false
				break
			}
		}
		if allSettled {
			return domain.TicketStatusDone
		}
		for _, p := range plans {
			if p.Status == domain.PlanStatusAwaitMerge {
				return domain.TicketStatusAwaitMerge
			}
		}
		for _, p := range plans {
			if planLive(p.Status) {
				return domain.TicketStatusInProgress
			}
		}
	}
	if planning != nil && planning.Status != domain.StatusTerminated && planning.Status != domain.StatusMerged {
		return domain.TicketStatusPlanning
	}
	if len(plans) > 0 {
		return domain.TicketStatusReady
	}
	return domain.TicketStatusDraft
}
```

- [ ] **Step 4: Run, then commit**

Run: `cd backend && go test ./internal/service/ticket/ -v`
Expected: PASS.

```bash
git add backend/internal/service/ticket/status.go backend/internal/service/ticket/status_test.go
git commit -m "feat(tickets): derive plan and ticket status from linked sessions"
```

---

### Task 4: Prompt builders

**Files:**
- Create: `backend/internal/service/ticket/prompt.go`, `prompt_test.go`

**Interfaces:**
- Consumes: `domain.Ticket`, `domain.Plan`, `domain.TicketsDir`.
- Produces:
  - `planningPrompt(t domain.Ticket, extra string) string`
  - `implementPrompt(t domain.Ticket, plan domain.Plan, kickoff, extra string) string` — `kickoff` is the kickoff file's body or empty.
  - `reviewPrompt(t domain.Ticket, plan domain.Plan, branch, worktree, mergeReadyCurl, extra string) string`
  - `mergeApprovedPrompt(t domain.Ticket, plan domain.Plan, branch, defaultBranch string) string`
  - `ticketFolder(slug string) string` → `".operator/tickets/<slug>"` (forward slashes, used in prompts and in git paths).

- [ ] **Step 1: Write the failing tests**

`backend/internal/service/ticket/prompt_test.go`:

```go
package ticket

import (
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestPlanningPromptFresh(t *testing.T) {
	tk := domain.Ticket{Slug: "editor", Title: "Editor", Brief: "Add a markdown editor."}
	got := planningPrompt(tk, "Keep it small.")
	for _, want := range []string{
		"ticket `editor`",
		".operator/tickets/editor/",
		"spec.md",
		"plans/01-<phase>.md",
		"plans/01-<phase>.kickoff.md",
		"title:",
		"Brief: Add a markdown editor.",
		"write `spec.md`",
		"Keep it small.",
		"commit",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
	if strings.Contains(got, "revise") {
		t.Errorf("fresh prompt must not say revise:\n%s", got)
	}
}

func TestPlanningPromptRevise(t *testing.T) {
	tk := domain.Ticket{Slug: "editor", Title: "Editor", Plans: []domain.Plan{{File: "plans/01-core.md", Title: "Core"}}}
	got := planningPrompt(tk, "")
	if !strings.Contains(got, "revise") || !strings.Contains(got, "plans/01-core.md") {
		t.Errorf("revise prompt wrong:\n%s", got)
	}
	if strings.HasSuffix(strings.TrimRight(got, "\n"), "instructions:") {
		t.Errorf("empty extra must not leave a dangling heading:\n%s", got)
	}
}

func TestImplementPrompt(t *testing.T) {
	tk := domain.Ticket{Slug: "editor", Title: "Editor", Brief: "Add it.", Plans: []domain.Plan{
		{File: "plans/01-daemon.md", Title: "Daemon", Status: domain.PlanStatusMerged},
		{File: "plans/02-ui.md", Title: "UI", Status: domain.PlanStatusWorking},
		{File: "plans/03-editor.md", Title: "Editor", Status: domain.PlanStatusTodo},
		{File: "plans/04-mobile.md", Title: "Mobile", Status: domain.PlanStatusTodo},
	}}
	got := implementPrompt(tk, tk.Plans[2], "", "Use TDD.")
	for _, want := range []string{
		"Editor",
		"Brief: Add it.",
		".operator/tickets/editor/spec.md",
		".operator/tickets/editor/plans/03-editor.md",
		"plans/01-daemon.md (merged)",
		"plans/02-ui.md (in progress)",
		"Implement only this phase",
		"pull request",
		"Use TDD.",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
	if strings.Contains(got, "04-mobile") {
		t.Errorf("later plans must not be listed:\n%s", got)
	}
	withKickoff := implementPrompt(tk, tk.Plans[2], "Execute plan 03 with subagents.\n", "Use TDD.")
	if !strings.Contains(withKickoff, "Execute plan 03 with subagents.") || strings.Contains(withKickoff, "Implement only this phase") {
		t.Errorf("kickoff body must replace the default body:\n%s", withKickoff)
	}
	if !strings.Contains(withKickoff, ".operator/tickets/editor/spec.md") || !strings.Contains(withKickoff, "Use TDD.") {
		t.Errorf("header and extra must survive with a kickoff:\n%s", withKickoff)
	}
}

func TestReviewAndMergePrompts(t *testing.T) {
	tk := domain.Ticket{Slug: "editor", Title: "Editor", Plans: []domain.Plan{{File: "plans/01-daemon.md", Title: "Daemon"}}}
	curl := `curl -s -X POST http://127.0.0.1:3001/api/v1/projects/tk/tickets/editor/plans/01-daemon.md/merge-ready -H 'content-type: application/json' -d '{"summary":"<one line>"}'`
	got := reviewPrompt(tk, tk.Plans[0], "opr/editor-01", "/data/worktrees/tk/tk-7", curl, "Be strict.")
	for _, want := range []string{
		".operator/tickets/editor/spec.md",
		".operator/tickets/editor/plans/01-daemon.md",
		"opr/editor-01",
		"/data/worktrees/tk/tk-7",
		"Do not merge",
		curl,
		"Be strict.",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
	m := mergeApprovedPrompt(tk, tk.Plans[0], "opr/editor-01", "development")
	if !strings.Contains(m, "Approved") || !strings.Contains(m, "opr/editor-01") || !strings.Contains(m, "development") {
		t.Errorf("merge prompt:\n%s", m)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && go test ./internal/service/ticket/ -run Prompt`
Expected: undefined `planningPrompt`.

- [ ] **Step 3: Implement**

`backend/internal/service/ticket/prompt.go`:

```go
package ticket

import (
	"fmt"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func ticketFolder(slug string) string {
	return domain.TicketsDir + "/" + slug
}

func planningPrompt(t domain.Ticket, extra string) string {
	folder := ticketFolder(t.Slug)
	var b strings.Builder
	fmt.Fprintf(&b, "You are planning ticket `%s` (%s) for this repository.\n\n", t.Slug, t.Title)
	fmt.Fprintf(&b, "The ticket folder is `%s/`, relative to your working directory. It must end up with this layout:\n\n", folder)
	b.WriteString("```\n")
	fmt.Fprintf(&b, "%s/\n", folder)
	b.WriteString("  ticket.md            frontmatter: title, brief, created\n")
	b.WriteString("  spec.md              the design spec\n")
	b.WriteString("  plans/01-<phase>.md  one implementation plan per phase, in dependency order\n")
	b.WriteString("  plans/01-<phase>.kickoff.md  the prompt a fresh session needs to execute that plan\n")
	b.WriteString("  plans/02-<phase>.md\n")
	b.WriteString("  plans/02-<phase>.kickoff.md\n")
	b.WriteString("```\n\n")
	b.WriteString("Every plan file starts with YAML frontmatter containing `title:`. The two-digit numeric prefix is the phase order; Operator reads it to know which phase depends on which. Do not put these documents anywhere else.\n\n")
	b.WriteString("Each kickoff file is the complete prompt for a separate, weaker session that will implement that plan with no other context: which files to read first and in what order, the process to follow, the gates to run, what to report, and when to stop and ask. Operator hands it to the implementing session verbatim after a short header naming the ticket and the paths.\n\n")
	if t.Brief != "" {
		fmt.Fprintf(&b, "Brief: %s\n\n", t.Brief)
	}
	if len(t.Plans) == 0 {
		b.WriteString("Brainstorm the design with the user, then write `spec.md`, then one plan per phase under `plans/`. Use whatever planning workflow you have available.\n")
	} else {
		b.WriteString("The ticket already has documents; revise them with the user rather than starting over. Existing plans:\n")
		for _, p := range t.Plans {
			fmt.Fprintf(&b, "- %s (%s)\n", p.File, p.Title)
		}
	}
	b.WriteString("\nWhen the documents are ready, commit the ticket folder.\n")
	if extra = strings.TrimSpace(extra); extra != "" {
		b.WriteString("\nAdditional instructions:\n" + extra + "\n")
	}
	return b.String()
}

func implementPrompt(t domain.Ticket, plan domain.Plan, kickoff, extra string) string {
	folder := ticketFolder(t.Slug)
	var b strings.Builder
	fmt.Fprintf(&b, "You are implementing one phase of ticket `%s` (%s).\n\n", t.Slug, t.Title)
	if t.Brief != "" {
		fmt.Fprintf(&b, "Brief: %s\n\n", t.Brief)
	}
	b.WriteString("Read these first, relative to your working directory:\n")
	fmt.Fprintf(&b, "- `%s/spec.md` (the design spec)\n", folder)
	fmt.Fprintf(&b, "- `%s/%s` (the plan for this phase: %s)\n", folder, plan.File, plan.Title)
	var earlier []string
	for _, p := range t.Plans {
		if p.File == plan.File {
			break
		}
		earlier = append(earlier, fmt.Sprintf("- `%s/%s` (%s)", folder, p.File, phaseState(p.Status)))
	}
	if len(earlier) > 0 {
		b.WriteString("\nEarlier phases of this ticket:\n" + strings.Join(earlier, "\n") + "\n")
	}
	if kickoff = strings.TrimSpace(kickoff); kickoff != "" {
		b.WriteString("\n" + kickoff + "\n")
	} else {
		b.WriteString("\nImplement only this phase. Open a pull request when the plan's final verification passes.\n")
	}
	if extra = strings.TrimSpace(extra); extra != "" {
		b.WriteString("\nAdditional instructions:\n" + extra + "\n")
	}
	return b.String()
}

func reviewPrompt(t domain.Ticket, plan domain.Plan, branch, worktree, mergeReadyCurl, extra string) string {
	folder := ticketFolder(t.Slug)
	var b strings.Builder
	fmt.Fprintf(&b, "Review the implementation of `%s` (%s) for ticket `%s` (%s).\n\n", plan.File, plan.Title, t.Slug, t.Title)
	b.WriteString("Read first, relative to the project root:\n")
	fmt.Fprintf(&b, "- `%s/spec.md`\n", folder)
	fmt.Fprintf(&b, "- `%s/%s`\n", folder, plan.File)
	fmt.Fprintf(&b, "\nThe implementing session worked on branch `%s`", branch)
	if worktree != "" {
		fmt.Fprintf(&b, " in the worktree `%s`", worktree)
	}
	b.WriteString(".\n\nReview the whole branch against the spec and the plan, not only the diff summary: read every changed file, run the gates the plan names, and verify the behaviour in the real app or daemon, not just in tests. Fix what is wrong on that branch and commit the fixes there. Do not merge.\n\n")
	b.WriteString("When the branch is ready to merge, report it to Operator with one line describing what was verified:\n\n```\n" + mergeReadyCurl + "\n```\n\nThen wait. The user confirms the merge from the board and you will receive the go-ahead here.\n")
	if extra = strings.TrimSpace(extra); extra != "" {
		b.WriteString("\nAdditional instructions:\n" + extra + "\n")
	}
	return b.String()
}

func mergeApprovedPrompt(t domain.Ticket, plan domain.Plan, branch, defaultBranch string) string {
	return fmt.Sprintf("Approved: merge `%s` (%s, ticket `%s`) into `%s` now, using the pull request if one is open, then report the merge commit and anything the next phase should know.\n", branch, plan.File, t.Slug, defaultBranch)
}

func phaseState(s domain.PlanStatus) string {
	switch s {
	case domain.PlanStatusMerged, domain.PlanStatusDone:
		return "merged"
	case domain.PlanStatusTodo, domain.PlanStatusTerminated:
		return "not started"
	default:
		return "in progress"
	}
}
```

- [ ] **Step 4: Run, then commit**

Run: `cd backend && go test ./internal/service/ticket/ -run Prompt -v`
Expected: PASS.

```bash
git add backend/internal/service/ticket/prompt.go backend/internal/service/ticket/prompt_test.go
git commit -m "feat(tickets): planning and implementing task prompts"
```

---

### Task 5: Git helpers

**Files:**
- Create: `backend/internal/service/ticket/git.go`, `git_test.go`

**Interfaces:**
- Consumes: `aoprocess.CommandContext` from `backend/internal/process` (the same helper `service/project/workspace_registration.go:368` uses).
- Produces:
  - `gitOutput(ctx, dir string, args ...string) (string, error)`
  - `gitCurrentBranch(ctx, repo string) (string, error)`
  - `gitPathDirty(ctx, repo, rel string) (bool, error)` — true when `git status --porcelain -- <rel>` prints anything (untracked included).
  - `gitCommitPath(ctx, repo, rel, message string) error` — `git add -A -- <rel>` then `git commit -m <message> -- <rel>`; a "nothing to commit" result is not an error.

- [ ] **Step 1: Write the failing test**

`backend/internal/service/ticket/git_test.go`:

```go
package ticket

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func initRepo(t *testing.T) string {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not installed")
	}
	dir := t.TempDir()
	run := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
		cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@x", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@x")
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	run("init", "-q", "-b", "main")
	run("config", "user.name", "t")
	run("config", "user.email", "t@x")
	if err := os.WriteFile(filepath.Join(dir, "README.md"), []byte("hi\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	run("add", "README.md")
	run("commit", "-q", "-m", "init")
	return dir
}

func TestGitHelpers(t *testing.T) {
	ctx := context.Background()
	repo := initRepo(t)
	branch, err := gitCurrentBranch(ctx, repo)
	if err != nil || branch != "main" {
		t.Fatalf("branch=%q err=%v", branch, err)
	}
	rel := ".operator/tickets/editor"
	dirty, err := gitPathDirty(ctx, repo, rel)
	if err != nil || dirty {
		t.Fatalf("empty path dirty=%v err=%v", dirty, err)
	}
	if err := os.MkdirAll(filepath.Join(repo, rel), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(repo, rel, "ticket.md"), []byte("---\ntitle: Editor\n---\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	dirty, err = gitPathDirty(ctx, repo, rel)
	if err != nil || !dirty {
		t.Fatalf("untracked should be dirty: dirty=%v err=%v", dirty, err)
	}
	if err := gitCommitPath(ctx, repo, rel, "ticket: add editor"); err != nil {
		t.Fatal(err)
	}
	dirty, err = gitPathDirty(ctx, repo, rel)
	if err != nil || dirty {
		t.Fatalf("after commit dirty=%v err=%v", dirty, err)
	}
	if err := gitCommitPath(ctx, repo, rel, "ticket: nothing"); err != nil {
		t.Fatalf("nothing to commit must not error: %v", err)
	}
	log, err := gitOutput(ctx, repo, "log", "--oneline")
	if err != nil || len(splitLines(log)) != 2 {
		t.Fatalf("log=%q err=%v", log, err)
	}
	if _, err := gitCurrentBranch(ctx, t.TempDir()); err == nil {
		t.Fatal("non-repo must error")
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && go test ./internal/service/ticket/ -run TestGitHelpers`
Expected: undefined `gitCurrentBranch`.

- [ ] **Step 3: Implement**

`backend/internal/service/ticket/git.go`:

```go
package ticket

import (
	"context"
	"fmt"
	"strings"

	aoprocess "github.com/OmarAly92/operator/backend/internal/process"
)

func gitOutput(ctx context.Context, dir string, args ...string) (string, error) {
	cmd := aoprocess.CommandContext(ctx, "git", append([]string{"-C", dir}, args...)...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("git -C %s %s: %w: %s", dir, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

func gitCurrentBranch(ctx context.Context, repo string) (string, error) {
	out, err := gitOutput(ctx, repo, "rev-parse", "--abbrev-ref", "HEAD")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

func gitPathDirty(ctx context.Context, repo, rel string) (bool, error) {
	out, err := gitOutput(ctx, repo, "status", "--porcelain", "--untracked-files=all", "--", rel)
	if err != nil {
		return false, err
	}
	return strings.TrimSpace(out) != "", nil
}

func gitCommitPath(ctx context.Context, repo, rel, message string) error {
	if _, err := gitOutput(ctx, repo, "add", "-A", "--", rel); err != nil {
		return err
	}
	staged, err := gitOutput(ctx, repo, "diff", "--cached", "--name-only", "--", rel)
	if err != nil {
		return err
	}
	if strings.TrimSpace(staged) == "" {
		return nil
	}
	_, err = gitOutput(ctx, repo, "commit", "-q", "-m", message, "--", rel)
	return err
}

func splitLines(s string) []string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	return strings.Split(s, "\n")
}
```

- [ ] **Step 4: Run, then commit**

Run: `cd backend && go test ./internal/service/ticket/ -run TestGitHelpers -v`
Expected: PASS.

```bash
git add backend/internal/service/ticket/git.go backend/internal/service/ticket/git_test.go
git commit -m "feat(tickets): git helpers for ticket folders"
```

---

### Task 6: Service — read models, files, create

**Files:**
- Create: `backend/internal/service/ticket/service.go`, `service_test.go`

**Interfaces:**
- Consumes: Task 1 store methods, Task 2 scanner, Task 3 status, Task 5 git; `sessionsvc.ListFilter` (`service/session/service.go:49`), `ports.SpawnConfig` (`ports/session.go:21`), `apierr` (`httpd/apierr`).
- Produces (package `ticket`):
  - `type Store interface { GetProject; ListTickets; GetTicket; InsertTicket; SetTicketPlanningSession; SetTicketArchivedAt; ListPlanAssignments; InsertPlanAssignment }` with the exact signatures from Task 1 plus `GetProject(ctx, id string) (domain.ProjectRecord, bool, error)` (already on `*store.Store`, `project_store.go:164`).
  - `type Sessions interface { List(ctx, sessionsvc.ListFilter) ([]domain.Session, error); Get(ctx, domain.SessionID) (domain.Session, error); Spawn(ctx, ports.SpawnConfig) (domain.Session, int, int, error); Send(ctx, domain.SessionID, message string, attachment *ports.SpawnAttachment) error }` — satisfied by `*sessionsvc.Service` (`Send` at `service/session/service.go:614`).
  - `Deps{Store Store; Sessions Sessions; Now func() time.Time; BaseURL string}`, `New(Deps) *Service`; `BaseURL` is the daemon's loopback origin, e.g. `http://127.0.0.1:3001`, used only to embed the merge-ready `curl` in review prompts.
  - `File{Path string; Content string; ModifiedAt time.Time}`, `CreateInput{Title, Brief string}`, `CreateResult{Ticket domain.Ticket; Warnings []string}`.
  - `(*Service) List(ctx, project domain.ProjectID) ([]domain.Ticket, error)`
  - `(*Service) Get(ctx, project domain.ProjectID, slug string) (domain.Ticket, error)`
  - `(*Service) ReadFile(ctx, project, slug, rel string) (File, error)`
  - `(*Service) WriteFile(ctx, project, slug, rel, content string, ifUnmodifiedSince time.Time) (File, error)`
  - `(*Service) Create(ctx, project, in CreateInput) (CreateResult, error)`
  - `(*Service) WatchRoot(ctx, project) (string, error)` — creates `<path>/.operator/tickets` if missing and returns it.
  - Error codes (all `apierr`): `PROJECT_NOT_FOUND` (404), `TICKET_UNSUPPORTED_PROJECT` (400), `TICKET_NOT_FOUND` (404), `TICKET_FILE_NOT_FOUND` (404), `TICKET_PATH_OUTSIDE` (400), `TICKET_FILE_STALE` (409, details `modifiedAt`), `TICKET_TITLE_REQUIRED` (400).
  - Warnings (strings): `not_on_default_branch`, `commit_failed`.

- [ ] **Step 1: Write the failing tests**

`backend/internal/service/ticket/service_test.go` (this file grows in Task 7; write the fakes once here):

```go
package ticket

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/ports"
	sessionsvc "github.com/OmarAly92/operator/backend/internal/service/session"
)

type fakeStore struct {
	projects    map[string]domain.ProjectRecord
	tickets     map[string]domain.TicketRecord
	assignments []domain.PlanAssignmentRecord
	nextID      int64
}

func newFakeStore(p domain.ProjectRecord) *fakeStore {
	return &fakeStore{projects: map[string]domain.ProjectRecord{string(p.ID): p}, tickets: map[string]domain.TicketRecord{}}
}

func key(p domain.ProjectID, slug string) string { return string(p) + "/" + slug }

func (f *fakeStore) GetProject(_ context.Context, id string) (domain.ProjectRecord, bool, error) {
	p, ok := f.projects[id]
	return p, ok, nil
}
func (f *fakeStore) ListTickets(_ context.Context, p domain.ProjectID) ([]domain.TicketRecord, error) {
	var out []domain.TicketRecord
	for _, t := range f.tickets {
		if t.ProjectID == p {
			out = append(out, t)
		}
	}
	return out, nil
}
func (f *fakeStore) GetTicket(_ context.Context, p domain.ProjectID, slug string) (domain.TicketRecord, bool, error) {
	t, ok := f.tickets[key(p, slug)]
	return t, ok, nil
}
func (f *fakeStore) InsertTicket(_ context.Context, rec domain.TicketRecord) error {
	if _, dup := f.tickets[key(rec.ProjectID, rec.Slug)]; dup {
		return errors.New("duplicate")
	}
	f.tickets[key(rec.ProjectID, rec.Slug)] = rec
	return nil
}
func (f *fakeStore) SetTicketPlanningSession(_ context.Context, p domain.ProjectID, slug string, s domain.SessionID) error {
	t, ok := f.tickets[key(p, slug)]
	if !ok {
		return errors.New("missing")
	}
	t.PlanningSessionID = s
	f.tickets[key(p, slug)] = t
	return nil
}
func (f *fakeStore) SetTicketArchivedAt(_ context.Context, p domain.ProjectID, slug string, at time.Time) error {
	t, ok := f.tickets[key(p, slug)]
	if !ok {
		return errors.New("missing")
	}
	t.ArchivedAt = at
	f.tickets[key(p, slug)] = t
	return nil
}
func (f *fakeStore) ListPlanAssignments(_ context.Context, p domain.ProjectID, slug string) ([]domain.PlanAssignmentRecord, error) {
	var out []domain.PlanAssignmentRecord
	for i := len(f.assignments) - 1; i >= 0; i-- {
		a := f.assignments[i]
		if a.ProjectID == p && a.Slug == slug {
			out = append(out, a)
		}
	}
	return out, nil
}
func (f *fakeStore) InsertPlanAssignment(_ context.Context, rec domain.PlanAssignmentRecord) error {
	f.nextID++
	rec.ID = f.nextID
	f.assignments = append(f.assignments, rec)
	return nil
}

type fakeSessions struct {
	sessions []domain.Session
	spawned  []ports.SpawnConfig
	sent     []sentMessage
	spawnErr error
	nextNum  int
}

func (f *fakeSessions) List(_ context.Context, filter sessionsvc.ListFilter) ([]domain.Session, error) {
	var out []domain.Session
	for _, s := range f.sessions {
		if filter.ProjectID == "" || s.ProjectID == filter.ProjectID {
			out = append(out, s)
		}
	}
	return out, nil
}
func (f *fakeSessions) Spawn(_ context.Context, cfg ports.SpawnConfig) (domain.Session, int, int, error) {
	if f.spawnErr != nil {
		return domain.Session{}, 0, 0, f.spawnErr
	}
	f.spawned = append(f.spawned, cfg)
	f.nextNum++
	s := domain.Session{SessionRecord: domain.SessionRecord{ID: domain.SessionID("tk-" + strings.Repeat("x", f.nextNum)), ProjectID: cfg.ProjectID}, Status: domain.StatusIdle}
	f.sessions = append(f.sessions, s)
	return s, 0, 0, nil
}
func (f *fakeSessions) Get(_ context.Context, id domain.SessionID) (domain.Session, error) {
	for _, s := range f.sessions {
		if s.ID == id {
			return s, nil
		}
	}
	return domain.Session{}, apierr.NotFound("SESSION_NOT_FOUND", "no session")
}

type sentMessage struct {
	id  domain.SessionID
	msg string
}

func (f *fakeSessions) Send(_ context.Context, id domain.SessionID, msg string, _ *ports.SpawnAttachment) error {
	f.sent = append(f.sent, sentMessage{id: id, msg: msg})
	return nil
}
func (f *fakeSessions) set(id domain.SessionID, status domain.SessionStatus) {
	for i := range f.sessions {
		if f.sessions[i].ID == id {
			f.sessions[i].Status = status
		}
	}
}

type harness struct {
	svc      *Service
	store    *fakeStore
	sessions *fakeSessions
	repo     string
	root     string
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	repo := initRepo(t)
	p := domain.ProjectRecord{ID: "tk", Path: repo, Kind: domain.ProjectKindSingleRepo, Config: domain.ProjectConfig{DefaultBranch: "main"}}
	st := newFakeStore(p)
	ss := &fakeSessions{}
	now := time.Date(2026, 9, 18, 12, 0, 0, 0, time.UTC)
	svc := New(Deps{Store: st, Sessions: ss, Now: func() time.Time { return now }})
	return &harness{svc: svc, store: st, sessions: ss, repo: repo, root: filepath.Join(repo, ".operator", "tickets")}
}

func (h *harness) ticketFile(slug, rel, content string) {
	writeFile(nil, filepath.Join(h.root, slug, filepath.FromSlash(rel)), content)
}

func codeOf(err error) string {
	var e *apierr.Error
	if errors.As(err, &e) {
		return e.Code
	}
	return ""
}

func TestListMergesFoldersAndRecords(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\nbrief: b\n---\n")
	h.ticketFile("editor", "plans/01-core.md", "---\ntitle: Core\n---\n")
	h.ticketFile("hand", "ticket.md", "# Hand written\n")
	_ = h.store.InsertTicket(ctx, domain.TicketRecord{ProjectID: "tk", Slug: "editor", CreatedAt: time.Now()})
	_ = h.store.InsertTicket(ctx, domain.TicketRecord{ProjectID: "tk", Slug: "deleted-folder", CreatedAt: time.Now()})

	got, err := h.svc.List(ctx, "tk")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].Slug != "editor" || got[1].Slug != "hand" {
		t.Fatalf("got %+v", got)
	}
	if got[0].Status != domain.TicketStatusReady || len(got[0].Plans) != 1 || got[0].Plans[0].Status != domain.PlanStatusTodo {
		t.Fatalf("editor = %+v", got[0])
	}
	if got[1].Status != domain.TicketStatusDraft || got[1].Title != "Hand written" {
		t.Fatalf("hand = %+v", got[1])
	}
}

func TestGetErrors(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	if _, err := h.svc.Get(ctx, "tk", "nope"); codeOf(err) != "TICKET_NOT_FOUND" {
		t.Fatalf("err = %v", err)
	}
	if _, err := h.svc.Get(ctx, "other", "nope"); codeOf(err) != "PROJECT_NOT_FOUND" {
		t.Fatalf("err = %v", err)
	}
	h.store.projects["ws"] = domain.ProjectRecord{ID: "ws", Path: h.repo, Kind: domain.ProjectKindWorkspace}
	if _, err := h.svc.List(ctx, "ws"); codeOf(err) != "TICKET_UNSUPPORTED_PROJECT" {
		t.Fatalf("err = %v", err)
	}
}

func TestReadWriteFileAndTraversal(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "spec.md", "# Spec\n")
	f, err := h.svc.ReadFile(ctx, "tk", "editor", "spec.md")
	if err != nil || f.Content != "# Spec\n" || f.ModifiedAt.IsZero() || f.Path != "spec.md" {
		t.Fatalf("f=%+v err=%v", f, err)
	}
	for _, bad := range []string{"", "../ticket.md", "../../README.md", "/etc/passwd", "plans/../../x.md", "spec.txt", "plans/sub/x.md"} {
		if _, err := h.svc.ReadFile(ctx, "tk", "editor", bad); codeOf(err) != "TICKET_PATH_OUTSIDE" {
			t.Errorf("%q: err = %v", bad, err)
		}
	}
	if _, err := h.svc.ReadFile(ctx, "tk", "editor", "plans/09-missing.md"); codeOf(err) != "TICKET_FILE_NOT_FOUND" {
		t.Fatalf("err = %v", err)
	}
	if err := os.Symlink(filepath.Join(h.repo, "README.md"), filepath.Join(h.root, "editor", "link.md")); err == nil {
		if _, err := h.svc.ReadFile(ctx, "tk", "editor", "link.md"); codeOf(err) != "TICKET_PATH_OUTSIDE" {
			t.Fatalf("symlink escape err = %v", err)
		}
	}
	w, err := h.svc.WriteFile(ctx, "tk", "editor", "plans/02-ui.md", "---\ntitle: UI\n---\n", time.Time{})
	if err != nil || w.ModifiedAt.IsZero() {
		t.Fatalf("w=%+v err=%v", w, err)
	}
	if got, _ := os.ReadFile(filepath.Join(h.root, "editor", "plans", "02-ui.md")); string(got) != "---\ntitle: UI\n---\n" {
		t.Fatalf("written = %q", got)
	}
	tk, _ := h.svc.Get(ctx, "tk", "editor")
	if len(tk.Plans) != 1 || tk.Plans[0].File != "plans/02-ui.md" {
		t.Fatalf("plans = %+v", tk.Plans)
	}
}

func TestWriteFileStale(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "spec.md", "v1\n")
	f, _ := h.svc.ReadFile(ctx, "tk", "editor", "spec.md")
	stale := f.ModifiedAt.Add(-2 * time.Second)
	_, err := h.svc.WriteFile(ctx, "tk", "editor", "spec.md", "v2\n", stale)
	if codeOf(err) != "TICKET_FILE_STALE" {
		t.Fatalf("err = %v", err)
	}
	if _, err := h.svc.WriteFile(ctx, "tk", "editor", "spec.md", "v2\n", f.ModifiedAt); err != nil {
		t.Fatalf("fresh write: %v", err)
	}
	if _, err := h.svc.WriteFile(ctx, "tk", "editor", "spec.md", "v3\n", time.Time{}); err != nil {
		t.Fatalf("unconditional write: %v", err)
	}
}

func TestCreateWritesFolderRecordAndCommit(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	res, err := h.svc.Create(ctx, "tk", CreateInput{Title: "Markdown Editor", Brief: "Edit docs in app"})
	if err != nil {
		t.Fatal(err)
	}
	if res.Ticket.Slug != "markdown-editor" || res.Ticket.Status != domain.TicketStatusDraft || len(res.Warnings) != 0 {
		t.Fatalf("res = %+v", res)
	}
	raw, err := os.ReadFile(filepath.Join(h.root, "markdown-editor", "ticket.md"))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"---\n", "title: Markdown Editor\n", "brief: Edit docs in app\n", "created: 2026-09-18\n"} {
		if !strings.Contains(string(raw), want) {
			t.Errorf("ticket.md missing %q:\n%s", want, raw)
		}
	}
	if spec, _ := os.ReadFile(filepath.Join(h.root, "markdown-editor", "spec.md")); string(spec) != "# Markdown Editor\n" {
		t.Fatalf("spec = %q", spec)
	}
	if _, ok := h.store.tickets[key("tk", "markdown-editor")]; !ok {
		t.Fatal("record not inserted")
	}
	if dirty, _ := gitPathDirty(ctx, h.repo, ".operator/tickets/markdown-editor"); dirty {
		t.Fatal("create must commit the folder")
	}
	res2, err := h.svc.Create(ctx, "tk", CreateInput{Title: "Markdown Editor"})
	if err != nil || res2.Ticket.Slug != "markdown-editor-2" {
		t.Fatalf("collision: %+v %v", res2, err)
	}
	if _, err := h.svc.Create(ctx, "tk", CreateInput{Title: "   "}); codeOf(err) != "TICKET_TITLE_REQUIRED" {
		t.Fatalf("err = %v", err)
	}
	if _, err := gitOutput(ctx, h.repo, "checkout", "-q", "-b", "feature"); err != nil {
		t.Fatal(err)
	}
	res3, err := h.svc.Create(ctx, "tk", CreateInput{Title: "On feature"})
	if err != nil || len(res3.Warnings) != 1 || res3.Warnings[0] != "not_on_default_branch" {
		t.Fatalf("res3 = %+v err=%v", res3, err)
	}
}
```

`writeFile(nil, …)` in `ticketFile` needs the Task 2 helper to tolerate a nil `t`. Replace the Task 2 helper with:

```go
func writeFile(t testing.TB, path, content string) {
	if t != nil {
		t.Helper()
	}
	fail := func(err error) {
		if t == nil {
			panic(err)
		}
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		fail(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		fail(err)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && go test ./internal/service/ticket/ -run 'TestList|TestGet|TestReadWrite|TestWriteFile|TestCreate'`
Expected: undefined `New`, `Deps`.

- [ ] **Step 3: Implement the service core**

`backend/internal/service/ticket/service.go`:

```go
package ticket

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/ports"
	sessionsvc "github.com/OmarAly92/operator/backend/internal/service/session"
)

type Store interface {
	GetProject(ctx context.Context, id string) (domain.ProjectRecord, bool, error)
	ListTickets(ctx context.Context, project domain.ProjectID) ([]domain.TicketRecord, error)
	GetTicket(ctx context.Context, project domain.ProjectID, slug string) (domain.TicketRecord, bool, error)
	InsertTicket(ctx context.Context, rec domain.TicketRecord) error
	SetTicketPlanningSession(ctx context.Context, project domain.ProjectID, slug string, session domain.SessionID) error
	SetTicketArchivedAt(ctx context.Context, project domain.ProjectID, slug string, at time.Time) error
	ListPlanAssignments(ctx context.Context, project domain.ProjectID, slug string) ([]domain.PlanAssignmentRecord, error)
	InsertPlanAssignment(ctx context.Context, rec domain.PlanAssignmentRecord) error
}

type Sessions interface {
	List(ctx context.Context, filter sessionsvc.ListFilter) ([]domain.Session, error)
	Get(ctx context.Context, id domain.SessionID) (domain.Session, error)
	Spawn(ctx context.Context, cfg ports.SpawnConfig) (domain.Session, int, int, error)
	Send(ctx context.Context, id domain.SessionID, message string, attachment *ports.SpawnAttachment) error
}

type Deps struct {
	Store    Store
	Sessions Sessions
	Now      func() time.Time
	BaseURL  string
}

type Service struct {
	store    Store
	sessions Sessions
	now      func() time.Time
	baseURL  string
}

func New(d Deps) *Service {
	now := d.Now
	if now == nil {
		now = func() time.Time { return time.Now().UTC() }
	}
	base := strings.TrimRight(d.BaseURL, "/")
	if base == "" {
		base = "http://127.0.0.1:3001"
	}
	return &Service{store: d.Store, sessions: d.Sessions, now: now, baseURL: base}
}

type File struct {
	Path       string
	Content    string
	ModifiedAt time.Time
}

type CreateInput struct {
	Title string
	Brief string
}

type CreateResult struct {
	Ticket   domain.Ticket
	Warnings []string
}

const maxDisplayName = 20

var errPathOutside = apierr.Invalid("TICKET_PATH_OUTSIDE", "Path must be a markdown file inside the ticket folder", nil)

func (s *Service) project(ctx context.Context, id domain.ProjectID) (domain.ProjectRecord, error) {
	row, ok, err := s.store.GetProject(ctx, string(id))
	if err != nil {
		return domain.ProjectRecord{}, apierr.Internal("PROJECT_LOAD_FAILED", "Failed to load project")
	}
	if !ok || !row.ArchivedAt.IsZero() {
		return domain.ProjectRecord{}, apierr.NotFound("PROJECT_NOT_FOUND", "Unknown project")
	}
	if row.Kind.WithDefault() != domain.ProjectKindSingleRepo {
		return domain.ProjectRecord{}, apierr.Invalid("TICKET_UNSUPPORTED_PROJECT", "Tickets need a single-repository project", nil)
	}
	return row, nil
}

func ticketsRoot(p domain.ProjectRecord) string {
	return filepath.Join(p.Path, filepath.FromSlash(domain.TicketsDir))
}

func (s *Service) sessionIndex(ctx context.Context, project domain.ProjectID) (map[domain.SessionID]*domain.Session, error) {
	list, err := s.sessions.List(ctx, sessionsvc.ListFilter{ProjectID: project})
	if err != nil {
		return nil, fmt.Errorf("list sessions: %w", err)
	}
	out := make(map[domain.SessionID]*domain.Session, len(list))
	for i := range list {
		out[list[i].ID] = &list[i]
	}
	return out, nil
}

func (s *Service) build(ctx context.Context, rec domain.TicketRecord, sc scannedTicket, sessions map[domain.SessionID]*domain.Session) (domain.Ticket, error) {
	rows, err := s.store.ListPlanAssignments(ctx, rec.ProjectID, rec.Slug)
	if err != nil {
		return domain.Ticket{}, err
	}
	current := currentAssignments(rows)
	t := domain.Ticket{
		ProjectID:         rec.ProjectID,
		Slug:              rec.Slug,
		Title:             sc.Title,
		Brief:             sc.Brief,
		PlanningSessionID: rec.PlanningSessionID,
		Files:             sc.Files,
		Warning:           sc.Warning,
		CreatedAt:         rec.CreatedAt,
		ArchivedAt:        rec.ArchivedAt,
		Plans:             make([]domain.Plan, 0, len(sc.Plans)),
	}
	for _, sp := range sc.Plans {
		a, ok := current[sp.File]
		p := domain.Plan{File: sp.File, Order: sp.Order, Title: sp.Title, KickoffFile: sp.Kickoff, Unordered: sp.Unordered, Warning: sp.Warning}
		if ok {
			p.SessionID = a.SessionID
			p.AssignmentID = a.ID
			p.ReviewerID = a.ReviewerSessionID
			p.MergeSummary = a.MergeSummary
		}
		p.Status = planStatus(a, ok, sessions[a.SessionID])
		t.Plans = append(t.Plans, p)
	}
	t.Status = ticketStatus(rec, t.Plans, sessions[rec.PlanningSessionID])
	return t, nil
}

func (s *Service) List(ctx context.Context, project domain.ProjectID) ([]domain.Ticket, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return nil, err
	}
	scanned, err := scanTickets(ticketsRoot(p))
	if err != nil {
		return nil, err
	}
	records, err := s.store.ListTickets(ctx, project)
	if err != nil {
		return nil, err
	}
	byslug := make(map[string]domain.TicketRecord, len(records))
	for _, r := range records {
		byslug[r.Slug] = r
	}
	sessions, err := s.sessionIndex(ctx, project)
	if err != nil {
		return nil, err
	}
	out := make([]domain.Ticket, 0, len(scanned))
	for _, sc := range scanned {
		rec, ok := byslug[sc.Slug]
		if !ok {
			rec = domain.TicketRecord{ProjectID: project, Slug: sc.Slug}
		}
		t, err := s.build(ctx, rec, sc, sessions)
		if err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, nil
}

func (s *Service) load(ctx context.Context, project domain.ProjectID, slug string) (domain.ProjectRecord, domain.TicketRecord, domain.Ticket, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return p, domain.TicketRecord{}, domain.Ticket{}, err
	}
	sc, ok, err := scanTicket(ticketsRoot(p), slug)
	if err != nil {
		return p, domain.TicketRecord{}, domain.Ticket{}, err
	}
	if !ok {
		return p, domain.TicketRecord{}, domain.Ticket{}, apierr.NotFound("TICKET_NOT_FOUND", "Unknown ticket")
	}
	rec, found, err := s.store.GetTicket(ctx, project, slug)
	if err != nil {
		return p, rec, domain.Ticket{}, err
	}
	if !found {
		rec = domain.TicketRecord{ProjectID: project, Slug: slug}
	}
	sessions, err := s.sessionIndex(ctx, project)
	if err != nil {
		return p, rec, domain.Ticket{}, err
	}
	t, err := s.build(ctx, rec, sc, sessions)
	return p, rec, t, err
}

func (s *Service) Get(ctx context.Context, project domain.ProjectID, slug string) (domain.Ticket, error) {
	_, _, t, err := s.load(ctx, project, slug)
	return t, err
}

func resolveTicketPath(dir, rel string) (string, error) {
	rel = strings.TrimSpace(filepath.ToSlash(rel))
	if rel == "" || strings.HasPrefix(rel, "/") || filepath.IsAbs(rel) {
		return "", errPathOutside
	}
	clean := path.Clean(rel)
	if clean == "." || clean == ".." || strings.HasPrefix(clean, "../") || !strings.HasSuffix(clean, ".md") {
		return "", errPathOutside
	}
	parent := path.Dir(clean)
	if parent != "." && parent != "plans" {
		return "", errPathOutside
	}
	abs := filepath.Join(dir, filepath.FromSlash(clean))
	realDir, err := filepath.EvalSymlinks(dir)
	if err != nil {
		return "", apierr.NotFound("TICKET_NOT_FOUND", "Unknown ticket")
	}
	if real, err := filepath.EvalSymlinks(abs); err == nil {
		if real != realDir && !strings.HasPrefix(real, realDir+string(filepath.Separator)) {
			return "", errPathOutside
		}
	}
	return abs, nil
}

func (s *Service) ReadFile(ctx context.Context, project domain.ProjectID, slug, rel string) (File, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return File{}, err
	}
	abs, err := resolveTicketPath(filepath.Join(ticketsRoot(p), slug), rel)
	if err != nil {
		return File{}, err
	}
	raw, err := os.ReadFile(abs)
	if errors.Is(err, os.ErrNotExist) {
		return File{}, apierr.NotFound("TICKET_FILE_NOT_FOUND", "No such file in the ticket")
	}
	if err != nil {
		return File{}, fmt.Errorf("read ticket file: %w", err)
	}
	info, err := os.Stat(abs)
	if err != nil {
		return File{}, fmt.Errorf("stat ticket file: %w", err)
	}
	return File{Path: path.Clean(filepath.ToSlash(rel)), Content: string(raw), ModifiedAt: info.ModTime().UTC()}, nil
}

func (s *Service) WriteFile(ctx context.Context, project domain.ProjectID, slug, rel, content string, ifUnmodifiedSince time.Time) (File, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return File{}, err
	}
	abs, err := resolveTicketPath(filepath.Join(ticketsRoot(p), slug), rel)
	if err != nil {
		return File{}, err
	}
	if info, err := os.Stat(abs); err == nil && !ifUnmodifiedSince.IsZero() {
		if info.ModTime().Truncate(time.Second).After(ifUnmodifiedSince.Truncate(time.Second)) {
			return File{}, apierr.Conflict("TICKET_FILE_STALE", "The file changed on disk since it was loaded", map[string]any{"modifiedAt": info.ModTime().UTC()})
		}
	}
	if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
		return File{}, fmt.Errorf("create plans dir: %w", err)
	}
	if err := os.WriteFile(abs, []byte(content), 0o644); err != nil {
		return File{}, fmt.Errorf("write ticket file: %w", err)
	}
	return s.ReadFile(ctx, project, slug, rel)
}

func (s *Service) uniqueSlug(ctx context.Context, project domain.ProjectID, root, base string) (string, error) {
	for i := 1; ; i++ {
		slug := base
		if i > 1 {
			slug = fmt.Sprintf("%s-%d", base, i)
		}
		if _, err := os.Stat(filepath.Join(root, slug)); err == nil {
			continue
		}
		if _, found, err := s.store.GetTicket(ctx, project, slug); err != nil {
			return "", err
		} else if found {
			continue
		}
		return slug, nil
	}
}

func (s *Service) Create(ctx context.Context, project domain.ProjectID, in CreateInput) (CreateResult, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return CreateResult{}, err
	}
	title := strings.TrimSpace(in.Title)
	if title == "" {
		return CreateResult{}, apierr.Invalid("TICKET_TITLE_REQUIRED", "A ticket needs a title", nil)
	}
	brief := strings.TrimSpace(in.Brief)
	root := ticketsRoot(p)
	slug, err := s.uniqueSlug(ctx, project, root, slugify(title))
	if err != nil {
		return CreateResult{}, err
	}
	now := s.now()
	dir := filepath.Join(root, slug)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return CreateResult{}, fmt.Errorf("create ticket dir: %w", err)
	}
	ticketMD := fmt.Sprintf("---\ntitle: %s\nbrief: %s\ncreated: %s\n---\n", yamlScalar(title), yamlScalar(brief), now.Format("2006-01-02"))
	if err := os.WriteFile(filepath.Join(dir, "ticket.md"), []byte(ticketMD), 0o644); err != nil {
		return CreateResult{}, fmt.Errorf("write ticket.md: %w", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "spec.md"), []byte("# "+title+"\n"), 0o644); err != nil {
		return CreateResult{}, fmt.Errorf("write spec.md: %w", err)
	}
	if err := s.store.InsertTicket(ctx, domain.TicketRecord{ProjectID: project, Slug: slug, CreatedAt: now}); err != nil {
		return CreateResult{}, err
	}
	var warnings []string
	if branch, err := gitCurrentBranch(ctx, p.Path); err == nil && branch != p.Config.WithDefaults().DefaultBranch {
		warnings = append(warnings, "not_on_default_branch")
	}
	if err := gitCommitPath(ctx, p.Path, ticketFolder(slug), "ticket: add "+slug); err != nil {
		warnings = append(warnings, "commit_failed")
	}
	t, err := s.Get(ctx, project, slug)
	if err != nil {
		return CreateResult{}, err
	}
	return CreateResult{Ticket: t, Warnings: warnings}, nil
}

func (s *Service) WatchRoot(ctx context.Context, project domain.ProjectID) (string, error) {
	p, err := s.project(ctx, project)
	if err != nil {
		return "", err
	}
	root := ticketsRoot(p)
	if err := os.MkdirAll(root, 0o755); err != nil {
		return "", fmt.Errorf("create tickets dir: %w", err)
	}
	return root, nil
}

func yamlScalar(s string) string {
	if s == "" {
		return `""`
	}
	if strings.ContainsAny(s, ":#\"'\n[]{}&*!|>%@`") || strings.TrimSpace(s) != s {
		return fmt.Sprintf("%q", s)
	}
	return s
}

func truncateRunes(s string, n int) string {
	s = strings.TrimSpace(s)
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	r := []rune(s)
	return strings.TrimSpace(string(r[:n]))
}
```

`truncateRunes` and `maxDisplayName` are used by Task 7; `go vet` accepts unused constants and functions, so they can land now.

- [ ] **Step 4: Run, then commit**

Run: `cd backend && go test ./internal/service/ticket/ -v`
Expected: PASS. If `TestReadWriteFileAndTraversal` fails on the symlink case on macOS because `t.TempDir()` lives under `/var` which resolves to `/private/var`, the `EvalSymlinks(dir)` in `resolveTicketPath` already normalises the root; fix the implementation rather than the test.

```bash
git add backend/internal/service/ticket
git commit -m "feat(tickets): ticket service read models, files and create"
```

---

### Task 7: Service — plan, assign, done, archive

**Files:**
- Modify: `backend/internal/service/ticket/service.go` (append)
- Modify: `backend/internal/service/ticket/service_test.go` (append)

**Interfaces:**
- Consumes: Task 6 `Service`, `load`, `truncateRunes`; Task 4 prompts; Task 5 git.
- Produces:
  - `SpawnInput{Harness domain.AgentHarness; Model string; ClaudeAccountID domain.ClaudeAccountID; Extra string}`; empty `Harness`/`Model`/`ClaudeAccountID` fall back to `ProjectConfig.Tickets.Planner` (for Plan and Review) or `.Implementer` (for Assign), see Task 11.
  - `AssignInput{SpawnInput; Force bool; DryRun bool}`
  - `AssignResult{Warnings []string; Session *domain.Session}`
  - `(*Service) Plan(ctx, project, slug string, in SpawnInput) (domain.Session, error)`
  - `(*Service) Assign(ctx, project, slug, planName string, in AssignInput) (AssignResult, error)` — `planName` is the file name inside `plans/`.
  - `(*Service) MarkDone(ctx, project, slug, planName string) (domain.Ticket, error)`
  - `(*Service) SetArchived(ctx, project, slug string, archived bool) (domain.Ticket, error)`
  - `planBranch(slug string, plan domain.Plan, attempt int) string` → `opr/<slug>-<NN>` or `opr/<slug>-<stem>` for unordered, `-<attempt>` suffix when attempt > 1.
  - Error codes: `TICKET_PLAN_NOT_FOUND` (404), `TICKET_PLANNING_ACTIVE` (409), `TICKET_ASSIGN_BLOCKED` (409, details `warnings`).
  - Warnings: `plan_order`, `ticket_repo_dirty`, `ticket_not_on_default_branch`, `planning_active`, `plan_assigned`.

- [ ] **Step 1: Append the failing tests**

Append to `service_test.go`:

```go
func TestPlanSpawnsInPlaceAndRefusesWhileActive(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Markdown Editor For Everyone\nbrief: b\n---\n")
	sess, err := h.svc.Plan(ctx, "tk", "editor", SpawnInput{Harness: domain.HarnessClaudeCode, ClaudeAccountID: "personal", Extra: "Be brief."})
	if err != nil {
		t.Fatal(err)
	}
	if len(h.sessions.spawned) != 1 {
		t.Fatalf("spawned = %+v", h.sessions.spawned)
	}
	cfg := h.sessions.spawned[0]
	if cfg.ProjectID != "tk" || cfg.Kind != domain.KindWorker || cfg.WorkspaceMode != domain.WorkspaceModeInPlace || cfg.Branch != "" ||
		cfg.Harness != domain.HarnessClaudeCode || cfg.ClaudeAccountID != "personal" || cfg.DisplayName != "Markdown Editor For" {
		t.Fatalf("cfg = %+v", cfg)
	}
	if !strings.Contains(cfg.Prompt, "Be brief.") || !strings.Contains(cfg.Prompt, "ticket `editor`") {
		t.Fatalf("prompt = %q", cfg.Prompt)
	}
	rec := h.store.tickets[key("tk", "editor")]
	if rec.PlanningSessionID != sess.ID {
		t.Fatalf("record = %+v", rec)
	}
	tk, _ := h.svc.Get(ctx, "tk", "editor")
	if tk.Status != domain.TicketStatusPlanning {
		t.Fatalf("status = %s", tk.Status)
	}
	if _, err := h.svc.Plan(ctx, "tk", "editor", SpawnInput{}); codeOf(err) != "TICKET_PLANNING_ACTIVE" {
		t.Fatalf("err = %v", err)
	}
	h.sessions.set(sess.ID, domain.StatusTerminated)
	if _, err := h.svc.Plan(ctx, "tk", "editor", SpawnInput{}); err != nil {
		t.Fatalf("replan after termination: %v", err)
	}
	if len(h.sessions.spawned) != 2 || !strings.Contains(h.sessions.spawned[1].Prompt, "Brainstorm") {
		t.Fatalf("second spawn = %+v", h.sessions.spawned)
	}
}

func TestAssignWarningsDryRunForceAndBranch(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "spec.md", "# s\n")
	h.ticketFile("editor", "plans/01-daemon.md", "---\ntitle: Daemon\n---\n")
	h.ticketFile("editor", "plans/02-ui.md", "---\ntitle: UI\n---\n")
	if err := gitCommitPath(ctx, h.repo, ".operator/tickets/editor", "ticket: add editor"); err != nil {
		t.Fatal(err)
	}

	res, err := h.svc.Assign(ctx, "tk", "editor", "02-ui.md", AssignInput{DryRun: true})
	if err != nil || res.Session != nil {
		t.Fatalf("dry run: %+v %v", res, err)
	}
	if len(res.Warnings) != 1 || res.Warnings[0] != "plan_order" {
		t.Fatalf("warnings = %v", res.Warnings)
	}
	if _, err := h.svc.Assign(ctx, "tk", "editor", "02-ui.md", AssignInput{}); codeOf(err) != "TICKET_ASSIGN_BLOCKED" {
		t.Fatalf("blocked err = %v", err)
	}
	if len(h.sessions.spawned) != 0 {
		t.Fatal("blocked assign must not spawn")
	}

	res, err = h.svc.Assign(ctx, "tk", "editor", "01-daemon.md", AssignInput{SpawnInput: SpawnInput{Harness: domain.HarnessCodex, Model: "gpt-5-mini", Extra: "Use TDD."}})
	if err != nil || res.Session == nil || len(res.Warnings) != 0 {
		t.Fatalf("assign: %+v %v", res, err)
	}
	cfg := h.sessions.spawned[0]
	if cfg.WorkspaceMode != domain.WorkspaceModeWorktree || cfg.Branch != "opr/editor-01" || cfg.Harness != domain.HarnessCodex || cfg.AgentConfig.Model != "gpt-5-mini" ||
		cfg.DisplayName != "editor · 01" || !strings.Contains(cfg.Prompt, "plans/01-daemon.md") || !strings.Contains(cfg.Prompt, "Use TDD.") {
		t.Fatalf("cfg = %+v", cfg)
	}
	tk, _ := h.svc.Get(ctx, "tk", "editor")
	if tk.Status != domain.TicketStatusInProgress || tk.Plans[0].Status != domain.PlanStatusIdle || tk.Plans[0].SessionID != res.Session.ID {
		t.Fatalf("ticket = %+v", tk)
	}

	res, err = h.svc.Assign(ctx, "tk", "editor", "01-daemon.md", AssignInput{DryRun: true})
	if err != nil || len(res.Warnings) != 1 || res.Warnings[0] != "plan_assigned" {
		t.Fatalf("reassign dry run = %+v %v", res, err)
	}
	h.sessions.set(res.Session.ID, domain.StatusTerminated)
	res, err = h.svc.Assign(ctx, "tk", "editor", "01-daemon.md", AssignInput{})
	if err != nil || h.sessions.spawned[1].Branch != "opr/editor-01-2" {
		t.Fatalf("second attempt = %+v err=%v", h.sessions.spawned, err)
	}

	h.sessions.set(res.Session.ID, domain.StatusMerged)
	h.ticketFile("editor", "spec.md", "# edited\n")
	res, err = h.svc.Assign(ctx, "tk", "editor", "02-ui.md", AssignInput{DryRun: true})
	if err != nil || len(res.Warnings) != 1 || res.Warnings[0] != "ticket_repo_dirty" {
		t.Fatalf("dirty warnings = %v err=%v", res.Warnings, err)
	}
	res, err = h.svc.Assign(ctx, "tk", "editor", "02-ui.md", AssignInput{Force: true})
	if err != nil || res.Session == nil || len(res.Warnings) != 1 {
		t.Fatalf("forced = %+v err=%v", res, err)
	}
	if !strings.Contains(h.sessions.spawned[2].Prompt, "plans/01-daemon.md` (merged)") {
		t.Fatalf("prompt = %q", h.sessions.spawned[2].Prompt)
	}
	if _, err := h.svc.Assign(ctx, "tk", "editor", "99-nope.md", AssignInput{}); codeOf(err) != "TICKET_PLAN_NOT_FOUND" {
		t.Fatalf("err = %v", err)
	}
}

func TestAssignUsesKickoffFileAndProjectDefaults(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	p := h.store.projects["tk"]
	p.Config.Tickets = domain.TicketDefaults{
		Planner:     domain.TicketRoleDefaults{Harness: domain.HarnessClaudeCode, Model: "opus", ClaudeAccountID: "personal"},
		Implementer: domain.TicketRoleDefaults{Harness: domain.HarnessClaudeCode, Model: "sonnet"},
	}
	h.store.projects["tk"] = p
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "plans/01-daemon.md", "---\ntitle: Daemon\n---\n")
	h.ticketFile("editor", "plans/01-daemon.kickoff.md", "Execute plan 01 with subagents.\n")
	_ = gitCommitPath(ctx, h.repo, ".operator/tickets/editor", "ticket: add editor")
	if _, err := h.svc.Plan(ctx, "tk", "editor", SpawnInput{}); err != nil {
		t.Fatal(err)
	}
	planner := h.sessions.spawned[0]
	if planner.AgentConfig.Model != "opus" || planner.ClaudeAccountID != "personal" || planner.Harness != domain.HarnessClaudeCode {
		t.Fatalf("planner cfg = %+v", planner)
	}
	if !strings.Contains(planner.Prompt, "kickoff.md") {
		t.Fatalf("planning prompt must ask for kickoff files:\n%s", planner.Prompt)
	}
	res, err := h.svc.Assign(ctx, "tk", "editor", "01-daemon.md", AssignInput{Force: true})
	if err != nil || res.Session == nil {
		t.Fatalf("assign = %+v err=%v", res, err)
	}
	impl := h.sessions.spawned[1]
	if impl.AgentConfig.Model != "sonnet" || impl.ClaudeAccountID != "" {
		t.Fatalf("implementer cfg = %+v", impl)
	}
	if !strings.Contains(impl.Prompt, "Execute plan 01 with subagents.") || strings.Contains(impl.Prompt, "Implement only this phase") {
		t.Fatalf("kickoff body not used:\n%s", impl.Prompt)
	}
	res, err = h.svc.Assign(ctx, "tk", "editor", "01-daemon.md", AssignInput{Force: true, SpawnInput: SpawnInput{Model: "haiku"}})
	if err != nil || h.sessions.spawned[2].AgentConfig.Model != "haiku" {
		t.Fatalf("override = %+v err=%v", h.sessions.spawned[2], err)
	}
}

func TestAssignSpawnFailureLeavesNoAssignment(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "plans/01-daemon.md", "---\ntitle: Daemon\n---\n")
	_ = gitCommitPath(ctx, h.repo, ".operator/tickets/editor", "ticket: add editor")
	h.sessions.spawnErr = errors.New("boom")
	if _, err := h.svc.Assign(ctx, "tk", "editor", "01-daemon.md", AssignInput{}); err == nil {
		t.Fatal("want spawn error")
	}
	if len(h.store.assignments) != 0 {
		t.Fatalf("assignments = %+v", h.store.assignments)
	}
}

func TestMarkDoneAndArchive(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "plans/01-daemon.md", "---\ntitle: Daemon\n---\n")
	tk, err := h.svc.MarkDone(ctx, "tk", "editor", "01-daemon.md")
	if err != nil || tk.Plans[0].Status != domain.PlanStatusDone || tk.Status != domain.TicketStatusDone {
		t.Fatalf("tk = %+v err=%v", tk, err)
	}
	if _, ok := h.store.tickets[key("tk", "editor")]; !ok {
		t.Fatal("mark done must create the record for a hand-written ticket")
	}
	tk, err = h.svc.SetArchived(ctx, "tk", "editor", true)
	if err != nil || tk.Status != domain.TicketStatusArchived || tk.ArchivedAt.IsZero() {
		t.Fatalf("tk = %+v err=%v", tk, err)
	}
	tk, err = h.svc.SetArchived(ctx, "tk", "editor", false)
	if err != nil || tk.Status != domain.TicketStatusDone {
		t.Fatalf("tk = %+v err=%v", tk, err)
	}
	if _, err := h.svc.MarkDone(ctx, "tk", "editor", "nope.md"); codeOf(err) != "TICKET_PLAN_NOT_FOUND" {
		t.Fatalf("err = %v", err)
	}
}

func TestPlanBranch(t *testing.T) {
	cases := []struct {
		plan    domain.Plan
		attempt int
		want    string
	}{
		{domain.Plan{File: "plans/01-daemon.md", Order: 1}, 1, "opr/editor-01"},
		{domain.Plan{File: "plans/10-ui.md", Order: 10}, 3, "opr/editor-10-3"},
		{domain.Plan{File: "plans/notes.md", Unordered: true}, 1, "opr/editor-notes"},
	}
	for _, tc := range cases {
		if got := planBranch("editor", tc.plan, tc.attempt); got != tc.want {
			t.Errorf("%+v attempt %d = %q want %q", tc.plan, tc.attempt, got, tc.want)
		}
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && go test ./internal/service/ticket/ -run 'TestPlan|TestAssign|TestMarkDone'`
Expected: undefined `SpawnInput`.

- [ ] **Step 3: Append the implementation**

Append to `service.go`:

```go
type SpawnInput struct {
	Harness         domain.AgentHarness
	Model           string
	ClaudeAccountID domain.ClaudeAccountID
	Extra           string
}

func (in SpawnInput) withDefaults(d domain.TicketRoleDefaults) SpawnInput {
	if in.Harness == "" {
		in.Harness = d.Harness
	}
	if strings.TrimSpace(in.Model) == "" {
		in.Model = d.Model
	}
	if in.ClaudeAccountID == "" {
		in.ClaudeAccountID = d.ClaudeAccountID
	}
	return in
}

type AssignInput struct {
	SpawnInput
	Force  bool
	DryRun bool
}

type AssignResult struct {
	Warnings []string
	Session  *domain.Session
}

func (s *Service) ensureRecord(ctx context.Context, rec domain.TicketRecord) (domain.TicketRecord, error) {
	if !rec.CreatedAt.IsZero() {
		return rec, nil
	}
	rec.CreatedAt = s.now()
	if err := s.store.InsertTicket(ctx, rec); err != nil {
		return rec, err
	}
	return rec, nil
}

func planningLive(sessions map[domain.SessionID]*domain.Session, id domain.SessionID) bool {
	sess := sessions[id]
	return sess != nil && sess.Status != domain.StatusTerminated && sess.Status != domain.StatusMerged
}

func (s *Service) Plan(ctx context.Context, project domain.ProjectID, slug string, in SpawnInput) (domain.Session, error) {
	p, rec, t, err := s.load(ctx, project, slug)
	if err != nil {
		return domain.Session{}, err
	}
	sessions, err := s.sessionIndex(ctx, project)
	if err != nil {
		return domain.Session{}, err
	}
	if planningLive(sessions, rec.PlanningSessionID) {
		return domain.Session{}, apierr.Conflict("TICKET_PLANNING_ACTIVE", "This ticket already has a running planning session", map[string]any{"sessionId": rec.PlanningSessionID})
	}
	rec, err = s.ensureRecord(ctx, rec)
	if err != nil {
		return domain.Session{}, err
	}
	return s.spawnPlanner(ctx, p, t, in, planningPrompt(t, in.Extra))
}

func (s *Service) spawnPlanner(ctx context.Context, p domain.ProjectRecord, t domain.Ticket, in SpawnInput, prompt string) (domain.Session, error) {
	in = in.withDefaults(p.Config.Tickets.Planner)
	sess, _, _, err := s.sessions.Spawn(ctx, ports.SpawnConfig{
		ProjectID:       p.ID,
		Kind:            domain.KindWorker,
		Harness:         in.Harness,
		WorkspaceMode:   domain.WorkspaceModeInPlace,
		Prompt:          prompt,
		AgentConfig:     ports.AgentConfig{Model: strings.TrimSpace(in.Model)},
		DisplayName:     truncateRunes(t.Title, maxDisplayName),
		ClaudeAccountID: in.ClaudeAccountID,
	})
	if err != nil {
		return domain.Session{}, err
	}
	if err := s.store.SetTicketPlanningSession(ctx, p.ID, t.Slug, sess.ID); err != nil {
		return domain.Session{}, err
	}
	return sess, nil
}

func findPlan(t domain.Ticket, planName string) (int, bool) {
	file := "plans/" + strings.TrimPrefix(strings.TrimSpace(planName), "plans/")
	for i, p := range t.Plans {
		if p.File == file {
			return i, true
		}
	}
	return 0, false
}

func planBranch(slug string, plan domain.Plan, attempt int) string {
	stem := strings.TrimSuffix(path.Base(plan.File), ".md")
	if !plan.Unordered {
		stem = fmt.Sprintf("%02d", plan.Order)
	}
	b := "opr/" + slug + "-" + stem
	if attempt > 1 {
		b += fmt.Sprintf("-%d", attempt)
	}
	return b
}

func (s *Service) assignWarnings(ctx context.Context, p domain.ProjectRecord, rec domain.TicketRecord, t domain.Ticket, idx int, sessions map[domain.SessionID]*domain.Session) []string {
	var w []string
	for _, earlier := range t.Plans[:idx] {
		if earlier.Status != domain.PlanStatusMerged && earlier.Status != domain.PlanStatusDone {
			w = append(w, "plan_order")
			break
		}
	}
	if dirty, err := gitPathDirty(ctx, p.Path, ticketFolder(t.Slug)); err == nil && dirty {
		w = append(w, "ticket_repo_dirty")
	}
	if branch, err := gitCurrentBranch(ctx, p.Path); err == nil && branch != p.Config.WithDefaults().DefaultBranch {
		w = append(w, "ticket_not_on_default_branch")
	}
	if planningLive(sessions, rec.PlanningSessionID) {
		w = append(w, "planning_active")
	}
	if planLive(t.Plans[idx].Status) {
		w = append(w, "plan_assigned")
	}
	return w
}

func (s *Service) Assign(ctx context.Context, project domain.ProjectID, slug, planName string, in AssignInput) (AssignResult, error) {
	p, rec, t, err := s.load(ctx, project, slug)
	if err != nil {
		return AssignResult{}, err
	}
	idx, ok := findPlan(t, planName)
	if !ok {
		return AssignResult{}, apierr.NotFound("TICKET_PLAN_NOT_FOUND", "No such plan in the ticket")
	}
	sessions, err := s.sessionIndex(ctx, project)
	if err != nil {
		return AssignResult{}, err
	}
	warnings := s.assignWarnings(ctx, p, rec, t, idx, sessions)
	if in.DryRun {
		return AssignResult{Warnings: warnings}, nil
	}
	if len(warnings) > 0 && !in.Force {
		return AssignResult{}, apierr.Conflict("TICKET_ASSIGN_BLOCKED", "Assignment needs confirmation", map[string]any{"warnings": warnings})
	}
	rec, err = s.ensureRecord(ctx, rec)
	if err != nil {
		return AssignResult{}, err
	}
	rows, err := s.store.ListPlanAssignments(ctx, project, slug)
	if err != nil {
		return AssignResult{}, err
	}
	attempt := 1
	for _, r := range rows {
		if r.PlanFile == t.Plans[idx].File && r.SessionID != "" {
			attempt++
		}
	}
	plan := t.Plans[idx]
	kickoff := ""
	if plan.KickoffFile != "" {
		raw, err := os.ReadFile(filepath.Join(ticketsRoot(p), slug, filepath.FromSlash(plan.KickoffFile)))
		if err != nil {
			return AssignResult{}, fmt.Errorf("read kickoff %s: %w", plan.KickoffFile, err)
		}
		kickoff = string(raw)
	}
	role := in.SpawnInput.withDefaults(p.Config.Tickets.Implementer)
	sess, _, _, err := s.sessions.Spawn(ctx, ports.SpawnConfig{
		ProjectID:       project,
		Kind:            domain.KindWorker,
		Harness:         role.Harness,
		WorkspaceMode:   domain.WorkspaceModeWorktree,
		Branch:          planBranch(slug, plan, attempt),
		Prompt:          implementPrompt(t, plan, kickoff, in.Extra),
		AgentConfig:     ports.AgentConfig{Model: strings.TrimSpace(role.Model)},
		DisplayName:     truncateRunes(fmt.Sprintf("%s · %s", slug, strings.TrimPrefix(planBranch(slug, plan, 1), "opr/"+slug+"-")), maxDisplayName),
		ClaudeAccountID: role.ClaudeAccountID,
	})
	if err != nil {
		return AssignResult{}, err
	}
	if err := s.store.InsertPlanAssignment(ctx, domain.PlanAssignmentRecord{ProjectID: project, Slug: slug, PlanFile: plan.File, SessionID: sess.ID, AssignedAt: s.now()}); err != nil {
		return AssignResult{}, err
	}
	return AssignResult{Warnings: warnings, Session: &sess}, nil
}

func (s *Service) MarkDone(ctx context.Context, project domain.ProjectID, slug, planName string) (domain.Ticket, error) {
	_, rec, t, err := s.load(ctx, project, slug)
	if err != nil {
		return domain.Ticket{}, err
	}
	idx, ok := findPlan(t, planName)
	if !ok {
		return domain.Ticket{}, apierr.NotFound("TICKET_PLAN_NOT_FOUND", "No such plan in the ticket")
	}
	if _, err := s.ensureRecord(ctx, rec); err != nil {
		return domain.Ticket{}, err
	}
	now := s.now()
	if err := s.store.InsertPlanAssignment(ctx, domain.PlanAssignmentRecord{ProjectID: project, Slug: slug, PlanFile: t.Plans[idx].File, AssignedAt: now, DoneAt: now}); err != nil {
		return domain.Ticket{}, err
	}
	return s.Get(ctx, project, slug)
}

func (s *Service) SetArchived(ctx context.Context, project domain.ProjectID, slug string, archived bool) (domain.Ticket, error) {
	_, rec, _, err := s.load(ctx, project, slug)
	if err != nil {
		return domain.Ticket{}, err
	}
	if _, err := s.ensureRecord(ctx, rec); err != nil {
		return domain.Ticket{}, err
	}
	at := time.Time{}
	if archived {
		at = s.now()
	}
	if err := s.store.SetTicketArchivedAt(ctx, project, slug, at); err != nil {
		return domain.Ticket{}, err
	}
	return s.Get(ctx, project, slug)
}
```

- [ ] **Step 4: Run, then commit**

Run: `cd backend && go test ./internal/service/ticket/ -v && go vet ./internal/service/ticket/`
Expected: PASS.

```bash
git add backend/internal/service/ticket
git commit -m "feat(tickets): plan, assign, mark done and archive"
```

---

### Task 7b: Review, merge-ready and merge confirmation

**Files:**
- Modify: `backend/internal/domain/projectconfig.go` — `TicketRoleDefaults`, `TicketDefaults`, `ProjectConfig.Tickets`
- Modify: `backend/internal/service/ticket/service.go` (append)
- Modify: `backend/internal/service/ticket/service_test.go` (append; fake gains `SessionTicketRef`)

**Interfaces:**
- Consumes: Task 4 `reviewPrompt`, `mergeApprovedPrompt`; Task 1 `MarkPlanReviewRequested`, `MarkPlanMergeReady`, `MarkPlanMergeApproved`, `SessionTicketRef`; Task 7 `spawnPlanner`, `findPlan`, `planningLive`.
- Produces (domain):

```go
type TicketRoleDefaults struct {
	Harness         AgentHarness    `json:"agent,omitempty"`
	Model           string          `json:"model,omitempty"`
	ClaudeAccountID ClaudeAccountID `json:"claudeAccountId,omitempty"`
}

type TicketDefaults struct {
	Planner           TicketRoleDefaults `json:"planner,omitempty"`
	Implementer       TicketRoleDefaults `json:"implementer,omitempty"`
	Reviewer          TicketRoleDefaults `json:"reviewer,omitempty"`
	ReviewerMode      string             `json:"reviewerMode,omitempty" enum:"planner,new"`
	DisableAutoReview bool               `json:"disableAutoReview,omitempty"`
}
```
  and `Tickets TicketDefaults \`json:"tickets,omitempty"\`` on `ProjectConfig` (`projectconfig.go:20`). `ProjectConfig` is stored as one JSON blob, so no migration.
- Produces (service):
  - `const ReviewerPlanner = "planner"`, `ReviewerNew = "new"`.
  - `ReviewInput{SpawnInput; Reviewer string}`, `ReviewResult{Session domain.Session; Spawned bool}`.
  - `(*Service) Review(ctx, project, slug, planName string, in ReviewInput) (ReviewResult, error)`
  - `(*Service) MergeReady(ctx, project, slug, planName, summary string) (domain.Ticket, error)`
  - `(*Service) ApproveMerge(ctx, project, slug, planName string) (domain.Ticket, error)`
  - `(*Service) AutoReview(ctx, sessionID domain.SessionID) error` — used by Task 7c; no-op unless the session is an implementer whose assignment has no review yet and the project has not disabled auto-review.
  - `Store` interface gains `SessionTicketRef(ctx, id domain.SessionID) (domain.SessionTicketRef, bool, error)`.
  - Error codes: `TICKET_PLAN_UNASSIGNED` (409), `TICKET_NOT_REVIEWING` (409), `TICKET_NOT_MERGE_READY` (409), `TICKET_REVIEWER_INVALID` (400).

- [ ] **Step 1: Add the config types**

In `backend/internal/domain/projectconfig.go` add the two structs above and the `Tickets` field to `ProjectConfig`. If `WithDefaults()` (`projectconfig.go:158`) copies fields explicitly, leave `Tickets` untouched by it; zero values mean "inherit". Run `cd backend && go test ./internal/domain/ ./internal/service/project/` and fix any config round-trip test that enumerates fields.

- [ ] **Step 2: Extend the fakes and write the failing tests**

In `service_test.go`, make `fakeSessions.Spawn` record branch and workspace so review prompts can name them:

```go
	s := domain.Session{SessionRecord: domain.SessionRecord{
		ID: domain.SessionID("tk-" + strings.Repeat("x", f.nextNum)), ProjectID: cfg.ProjectID,
		Metadata: domain.SessionMetadata{Branch: cfg.Branch, WorkspaceMode: cfg.WorkspaceMode, WorkspacePath: "/ws/" + strings.Repeat("x", f.nextNum)},
	}, Status: domain.StatusIdle}
```

Add to `fakeStore`:

```go
func (f *fakeStore) SessionTicketRef(_ context.Context, id domain.SessionID) (domain.SessionTicketRef, bool, error) {
	for _, t := range f.tickets {
		if t.PlanningSessionID == id {
			return domain.SessionTicketRef{Slug: t.Slug, Role: domain.TicketRolePlanning}, true, nil
		}
	}
	for i := len(f.assignments) - 1; i >= 0; i-- {
		a := f.assignments[i]
		if a.SessionID == id {
			return domain.SessionTicketRef{Slug: a.Slug, PlanFile: a.PlanFile, Role: domain.TicketRoleImplementing}, true, nil
		}
	}
	for i := len(f.assignments) - 1; i >= 0; i-- {
		a := f.assignments[i]
		if a.ReviewerSessionID == id {
			return domain.SessionTicketRef{Slug: a.Slug, PlanFile: a.PlanFile, Role: domain.TicketRoleReviewing}, true, nil
		}
	}
	return domain.SessionTicketRef{}, false, nil
}
func (f *fakeStore) GetPlanAssignment(_ context.Context, id int64) (domain.PlanAssignmentRecord, bool, error) {
	for _, a := range f.assignments {
		if a.ID == id {
			return a, true, nil
		}
	}
	return domain.PlanAssignmentRecord{}, false, nil
}
func (f *fakeStore) update(id int64, fn func(*domain.PlanAssignmentRecord)) error {
	for i := range f.assignments {
		if f.assignments[i].ID == id {
			fn(&f.assignments[i])
			return nil
		}
	}
	return errors.New("missing assignment")
}
func (f *fakeStore) MarkPlanReviewRequested(_ context.Context, id int64, reviewer domain.SessionID, at time.Time) error {
	return f.update(id, func(a *domain.PlanAssignmentRecord) { a.ReviewerSessionID, a.ReviewRequestedAt = reviewer, at })
}
func (f *fakeStore) MarkPlanMergeReady(_ context.Context, id int64, at time.Time, summary string) error {
	return f.update(id, func(a *domain.PlanAssignmentRecord) {
		a.MergeReadyAt, a.MergeSummary, a.MergeApprovedAt = at, summary, time.Time{}
	})
}
func (f *fakeStore) MarkPlanMergeApproved(_ context.Context, id int64, at time.Time) error {
	return f.update(id, func(a *domain.PlanAssignmentRecord) { a.MergeApprovedAt = at })
}
```

Then the tests:

```go
func assignedHarness(t *testing.T) (*harness, domain.SessionID) {
	t.Helper()
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "spec.md", "# s\n")
	h.ticketFile("editor", "plans/01-daemon.md", "---\ntitle: Daemon\n---\n")
	_ = gitCommitPath(ctx, h.repo, ".operator/tickets/editor", "ticket: add editor")
	res, err := h.svc.Assign(ctx, "tk", "editor", "01-daemon.md", AssignInput{Force: true})
	if err != nil || res.Session == nil {
		t.Fatalf("assign = %+v err=%v", res, err)
	}
	return h, res.Session.ID
}

func TestReviewWithPlannerSendsOrSpawns(t *testing.T) {
	h, impl := assignedHarness(t)
	ctx := context.Background()
	if _, err := h.svc.Review(ctx, "tk", "editor", "01-daemon.md", ReviewInput{}); err != nil {
		t.Fatal(err)
	}
	if len(h.sessions.spawned) != 2 || h.sessions.spawned[1].WorkspaceMode != domain.WorkspaceModeInPlace || len(h.sessions.sent) != 0 {
		t.Fatalf("no planner: spawned=%+v sent=%+v", h.sessions.spawned, h.sessions.sent)
	}
	prompt := h.sessions.spawned[1].Prompt
	for _, want := range []string{"opr/editor-01", "/ws/x", "merge-ready", "http://127.0.0.1:3001/api/v1/projects/tk/tickets/editor/plans/01-daemon.md/merge-ready", "Do not merge"} {
		if !strings.Contains(prompt, want) {
			t.Errorf("review prompt missing %q:\n%s", want, prompt)
		}
	}
	planner := h.sessions.sessions[1].ID
	if h.store.tickets[key("tk", "editor")].PlanningSessionID != planner {
		t.Fatal("spawned reviewer must become the planning session in planner mode")
	}
	tk, _ := h.svc.Get(ctx, "tk", "editor")
	if tk.Plans[0].Status != domain.PlanStatusReviewing || tk.Plans[0].ReviewerID != planner || tk.Status != domain.TicketStatusInProgress {
		t.Fatalf("ticket = %+v", tk)
	}
	ref, ok, _ := h.store.SessionTicketRef(ctx, planner)
	if !ok || ref.Role != domain.TicketRolePlanning {
		t.Fatalf("planner ref = %+v", ref)
	}
	_ = impl
	if _, err := h.svc.Review(ctx, "tk", "editor", "01-daemon.md", ReviewInput{SpawnInput: SpawnInput{Extra: "Again."}}); err != nil {
		t.Fatal(err)
	}
	if len(h.sessions.spawned) != 2 || len(h.sessions.sent) != 1 || h.sessions.sent[0].id != planner || !strings.Contains(h.sessions.sent[0].msg, "Again.") {
		t.Fatalf("live planner must receive a send: spawned=%d sent=%+v", len(h.sessions.spawned), h.sessions.sent)
	}
}

func TestReviewWithNewSessionUsesReviewerDefaults(t *testing.T) {
	h, _ := assignedHarness(t)
	ctx := context.Background()
	p := h.store.projects["tk"]
	p.Config.Tickets.Planner = domain.TicketRoleDefaults{Model: "opus"}
	p.Config.Tickets.Reviewer = domain.TicketRoleDefaults{Model: "sonnet", ClaudeAccountID: "personal"}
	h.store.projects["tk"] = p
	planner, _ := h.svc.Plan(ctx, "tk", "editor", SpawnInput{})
	res, err := h.svc.Review(ctx, "tk", "editor", "01-daemon.md", ReviewInput{Reviewer: ReviewerNew})
	if err != nil || !res.Spawned || res.Session.ID == planner.ID {
		t.Fatalf("res = %+v err=%v", res, err)
	}
	cfg := h.sessions.spawned[len(h.sessions.spawned)-1]
	if cfg.AgentConfig.Model != "sonnet" || cfg.ClaudeAccountID != "personal" || cfg.WorkspaceMode != domain.WorkspaceModeInPlace || cfg.DisplayName != "editor review" {
		t.Fatalf("reviewer cfg = %+v", cfg)
	}
	if h.store.tickets[key("tk", "editor")].PlanningSessionID != planner.ID {
		t.Fatal("new-session review must not replace the planner")
	}
	if ref, ok, _ := h.store.SessionTicketRef(ctx, res.Session.ID); !ok || ref.Role != domain.TicketRoleReviewing {
		t.Fatalf("reviewer ref = %+v ok=%v", ref, ok)
	}
	p.Config.Tickets.ReviewerMode = ReviewerNew
	h.store.projects["tk"] = p
	res2, _ := h.svc.Review(ctx, "tk", "editor", "01-daemon.md", ReviewInput{})
	if !res2.Spawned {
		t.Fatal("project default reviewerMode=new must spawn")
	}
	if _, err := h.svc.Review(ctx, "tk", "editor", "01-daemon.md", ReviewInput{Reviewer: "robot"}); codeOf(err) != "TICKET_REVIEWER_INVALID" {
		t.Fatalf("err = %v", err)
	}
}

func TestReviewRequiresAssignment(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.ticketFile("editor", "ticket.md", "---\ntitle: Editor\n---\n")
	h.ticketFile("editor", "plans/01-daemon.md", "---\ntitle: Daemon\n---\n")
	if _, err := h.svc.Review(ctx, "tk", "editor", "01-daemon.md", ReviewInput{}); codeOf(err) != "TICKET_PLAN_UNASSIGNED" {
		t.Fatalf("err = %v", err)
	}
	if _, err := h.svc.MergeReady(ctx, "tk", "editor", "01-daemon.md", "ready"); codeOf(err) != "TICKET_NOT_REVIEWING" {
		t.Fatalf("err = %v", err)
	}
}

func TestMergeReadyThenApproveSendsToReviewer(t *testing.T) {
	h, _ := assignedHarness(t)
	ctx := context.Background()
	res, err := h.svc.Review(ctx, "tk", "editor", "01-daemon.md", ReviewInput{})
	if err != nil {
		t.Fatal(err)
	}
	reviewer := res.Session.ID
	if _, err := h.svc.ApproveMerge(ctx, "tk", "editor", "01-daemon.md"); codeOf(err) != "TICKET_NOT_MERGE_READY" {
		t.Fatalf("err = %v", err)
	}
	tk, err := h.svc.MergeReady(ctx, "tk", "editor", "01-daemon.md", "gates green, verified in app")
	if err != nil || tk.Plans[0].Status != domain.PlanStatusAwaitMerge || tk.Plans[0].MergeSummary != "gates green, verified in app" || tk.Status != domain.TicketStatusAwaitMerge {
		t.Fatalf("tk = %+v err=%v", tk, err)
	}
	tk, err = h.svc.ApproveMerge(ctx, "tk", "editor", "01-daemon.md")
	if err != nil || tk.Plans[0].Status != domain.PlanStatusReviewing {
		t.Fatalf("tk = %+v err=%v", tk, err)
	}
	last := h.sessions.sent[len(h.sessions.sent)-1]
	if last.id != reviewer || !strings.Contains(last.msg, "Approved") || !strings.Contains(last.msg, "opr/editor-01") || !strings.Contains(last.msg, "main") {
		t.Fatalf("sent = %+v", last)
	}
	h.sessions.set(reviewer, domain.StatusTerminated)
	if _, err := h.svc.MergeReady(ctx, "tk", "editor", "01-daemon.md", "again"); err != nil {
		t.Fatal(err)
	}
	spawnedBefore := len(h.sessions.spawned)
	if _, err := h.svc.ApproveMerge(ctx, "tk", "editor", "01-daemon.md"); err != nil {
		t.Fatal(err)
	}
	if len(h.sessions.spawned) != spawnedBefore+1 || !strings.Contains(h.sessions.spawned[spawnedBefore].Prompt, "Approved") {
		t.Fatalf("dead reviewer must be replaced by a fresh in-place session: %+v", h.sessions.spawned)
	}
}

func TestAutoReviewOncePerAssignment(t *testing.T) {
	h, impl := assignedHarness(t)
	ctx := context.Background()
	if err := h.svc.AutoReview(ctx, "unknown"); err != nil {
		t.Fatal(err)
	}
	if err := h.svc.AutoReview(ctx, impl); err != nil {
		t.Fatal(err)
	}
	if len(h.sessions.spawned) != 2 {
		t.Fatalf("auto review must trigger a planner-mode review: %+v", h.sessions.spawned)
	}
	if err := h.svc.AutoReview(ctx, impl); err != nil || len(h.sessions.spawned) != 2 || len(h.sessions.sent) != 0 {
		t.Fatalf("second auto review must be a no-op: err=%v spawned=%d sent=%d", err, len(h.sessions.spawned), len(h.sessions.sent))
	}
	h2, impl2 := assignedHarness(t)
	p := h2.store.projects["tk"]
	p.Config.Tickets.DisableAutoReview = true
	h2.store.projects["tk"] = p
	if err := h2.svc.AutoReview(ctx, impl2); err != nil || len(h2.sessions.spawned) != 1 {
		t.Fatalf("disabled auto review must not act: err=%v spawned=%d", err, len(h2.sessions.spawned))
	}
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd backend && go test ./internal/service/ticket/ -run 'TestReview|TestMergeReady|TestAutoReview'`
Expected: undefined `ReviewInput`.

- [ ] **Step 4: Implement**

Add `SessionTicketRef`, `GetPlanAssignment`, `MarkPlanReviewRequested`, `MarkPlanMergeReady`, `MarkPlanMergeApproved` to the `Store` interface in `service.go` with the Task 1 signatures. Append:

```go
const (
	ReviewerPlanner = "planner"
	ReviewerNew     = "new"
)

type ReviewInput struct {
	SpawnInput
	Reviewer string
}

type ReviewResult struct {
	Session domain.Session
	Spawned bool
}

func (s *Service) currentAssignment(ctx context.Context, project domain.ProjectID, slug, planFile string) (domain.PlanAssignmentRecord, bool, error) {
	rows, err := s.store.ListPlanAssignments(ctx, project, slug)
	if err != nil {
		return domain.PlanAssignmentRecord{}, false, err
	}
	a, ok := currentAssignments(rows)[planFile]
	return a, ok, nil
}

func (s *Service) mergeReadyCurl(project domain.ProjectID, slug, planName string) string {
	return fmt.Sprintf(`curl -s -X POST %s/api/v1/projects/%s/tickets/%s/plans/%s/merge-ready -H 'content-type: application/json' -d '{"summary":"<one line: what you verified>"}'`, s.baseURL, project, slug, planName)
}

func (s *Service) sessionLive(sessions map[domain.SessionID]*domain.Session, id domain.SessionID) bool {
	return planningLive(sessions, id)
}

func (s *Service) Review(ctx context.Context, project domain.ProjectID, slug, planName string, in ReviewInput) (ReviewResult, error) {
	p, rec, t, err := s.load(ctx, project, slug)
	if err != nil {
		return ReviewResult{}, err
	}
	idx, ok := findPlan(t, planName)
	if !ok {
		return ReviewResult{}, apierr.NotFound("TICKET_PLAN_NOT_FOUND", "No such plan in the ticket")
	}
	plan := t.Plans[idx]
	a, ok, err := s.currentAssignment(ctx, project, slug, plan.File)
	if err != nil {
		return ReviewResult{}, err
	}
	if !ok || a.SessionID == "" {
		return ReviewResult{}, apierr.Conflict("TICKET_PLAN_UNASSIGNED", "Assign the plan to a session before reviewing it", nil)
	}
	mode := strings.TrimSpace(in.Reviewer)
	if mode == "" {
		mode = strings.TrimSpace(p.Config.Tickets.ReviewerMode)
	}
	if mode == "" {
		mode = ReviewerPlanner
	}
	if mode != ReviewerPlanner && mode != ReviewerNew {
		return ReviewResult{}, apierr.Invalid("TICKET_REVIEWER_INVALID", "reviewer must be planner or new", nil)
	}
	impl, err := s.sessions.Get(ctx, a.SessionID)
	if err != nil {
		return ReviewResult{}, err
	}
	prompt := reviewPrompt(t, plan, impl.Metadata.Branch, impl.Metadata.WorkspacePath, s.mergeReadyCurl(project, slug, path.Base(plan.File)), in.Extra)
	sessions, err := s.sessionIndex(ctx, project)
	if err != nil {
		return ReviewResult{}, err
	}
	var reviewer domain.Session
	spawned := false
	switch {
	case mode == ReviewerPlanner && s.sessionLive(sessions, rec.PlanningSessionID):
		if err := s.sessions.Send(ctx, rec.PlanningSessionID, prompt, nil); err != nil {
			return ReviewResult{}, err
		}
		reviewer = *sessions[rec.PlanningSessionID]
	case mode == ReviewerPlanner:
		reviewer, err = s.spawnPlanner(ctx, p, t, in.SpawnInput, prompt)
		if err != nil {
			return ReviewResult{}, err
		}
		spawned = true
	default:
		defaults := p.Config.Tickets.Reviewer
		if defaults == (domain.TicketRoleDefaults{}) {
			defaults = p.Config.Tickets.Planner
		}
		role := in.SpawnInput.withDefaults(defaults)
		reviewer, _, _, err = s.sessions.Spawn(ctx, ports.SpawnConfig{
			ProjectID:       project,
			Kind:            domain.KindWorker,
			Harness:         role.Harness,
			WorkspaceMode:   domain.WorkspaceModeInPlace,
			Prompt:          prompt,
			AgentConfig:     ports.AgentConfig{Model: strings.TrimSpace(role.Model)},
			DisplayName:     truncateRunes(slug+" review", maxDisplayName),
			ClaudeAccountID: role.ClaudeAccountID,
		})
		if err != nil {
			return ReviewResult{}, err
		}
		spawned = true
	}
	if err := s.store.MarkPlanReviewRequested(ctx, a.ID, reviewer.ID, s.now()); err != nil {
		return ReviewResult{}, err
	}
	return ReviewResult{Session: reviewer, Spawned: spawned}, nil
}

func (s *Service) MergeReady(ctx context.Context, project domain.ProjectID, slug, planName, summary string) (domain.Ticket, error) {
	_, _, t, err := s.load(ctx, project, slug)
	if err != nil {
		return domain.Ticket{}, err
	}
	idx, ok := findPlan(t, planName)
	if !ok {
		return domain.Ticket{}, apierr.NotFound("TICKET_PLAN_NOT_FOUND", "No such plan in the ticket")
	}
	a, ok, err := s.currentAssignment(ctx, project, slug, t.Plans[idx].File)
	if err != nil {
		return domain.Ticket{}, err
	}
	if !ok || a.ReviewRequestedAt.IsZero() {
		return domain.Ticket{}, apierr.Conflict("TICKET_NOT_REVIEWING", "No review is in progress for this plan", nil)
	}
	if err := s.store.MarkPlanMergeReady(ctx, a.ID, s.now(), strings.TrimSpace(summary)); err != nil {
		return domain.Ticket{}, err
	}
	return s.Get(ctx, project, slug)
}

func (s *Service) ApproveMerge(ctx context.Context, project domain.ProjectID, slug, planName string) (domain.Ticket, error) {
	p, _, t, err := s.load(ctx, project, slug)
	if err != nil {
		return domain.Ticket{}, err
	}
	idx, ok := findPlan(t, planName)
	if !ok {
		return domain.Ticket{}, apierr.NotFound("TICKET_PLAN_NOT_FOUND", "No such plan in the ticket")
	}
	plan := t.Plans[idx]
	a, ok, err := s.currentAssignment(ctx, project, slug, plan.File)
	if err != nil {
		return domain.Ticket{}, err
	}
	if !ok || a.MergeReadyAt.IsZero() || !a.MergeApprovedAt.IsZero() {
		return domain.Ticket{}, apierr.Conflict("TICKET_NOT_MERGE_READY", "The reviewer has not reported this plan as ready to merge", nil)
	}
	impl, err := s.sessions.Get(ctx, a.SessionID)
	if err != nil {
		return domain.Ticket{}, err
	}
	prompt := mergeApprovedPrompt(t, plan, impl.Metadata.Branch, p.Config.WithDefaults().DefaultBranch)
	sessions, err := s.sessionIndex(ctx, project)
	if err != nil {
		return domain.Ticket{}, err
	}
	if s.sessionLive(sessions, a.ReviewerSessionID) {
		if err := s.sessions.Send(ctx, a.ReviewerSessionID, prompt, nil); err != nil {
			return domain.Ticket{}, err
		}
	} else {
		defaults := p.Config.Tickets.Reviewer
		if defaults == (domain.TicketRoleDefaults{}) {
			defaults = p.Config.Tickets.Planner
		}
		role := SpawnInput{}.withDefaults(defaults)
		fresh, _, _, err := s.sessions.Spawn(ctx, ports.SpawnConfig{
			ProjectID:       project,
			Kind:            domain.KindWorker,
			Harness:         role.Harness,
			WorkspaceMode:   domain.WorkspaceModeInPlace,
			Prompt:          prompt,
			AgentConfig:     ports.AgentConfig{Model: strings.TrimSpace(role.Model)},
			DisplayName:     truncateRunes(slug+" merge", maxDisplayName),
			ClaudeAccountID: role.ClaudeAccountID,
		})
		if err != nil {
			return domain.Ticket{}, err
		}
		if err := s.store.MarkPlanReviewRequested(ctx, a.ID, fresh.ID, a.ReviewRequestedAt); err != nil {
			return domain.Ticket{}, err
		}
	}
	if err := s.store.MarkPlanMergeApproved(ctx, a.ID, s.now()); err != nil {
		return domain.Ticket{}, err
	}
	return s.Get(ctx, project, slug)
}

func (s *Service) AutoReview(ctx context.Context, sessionID domain.SessionID) error {
	ref, ok, err := s.store.SessionTicketRef(ctx, sessionID)
	if err != nil || !ok || ref.Role != domain.TicketRoleImplementing {
		return err
	}
	impl, err := s.sessions.Get(ctx, sessionID)
	if err != nil {
		return err
	}
	p, err := s.project(ctx, impl.ProjectID)
	if err != nil {
		return nil
	}
	if p.Config.Tickets.DisableAutoReview {
		return nil
	}
	a, ok, err := s.currentAssignment(ctx, impl.ProjectID, ref.Slug, ref.PlanFile)
	if err != nil {
		return err
	}
	if !ok || a.SessionID != sessionID || !a.ReviewRequestedAt.IsZero() {
		return nil
	}
	_, err = s.Review(ctx, impl.ProjectID, ref.Slug, path.Base(ref.PlanFile), ReviewInput{})
	return err
}
```

- [ ] **Step 5: Run, then commit**

Run: `cd backend && go test ./internal/service/ticket/ -v && go vet ./internal/service/ticket/ ./internal/domain/`
Expected: PASS.

```bash
git add backend/internal/domain/projectconfig.go backend/internal/service/ticket
git commit -m "feat(tickets): review by planner or fresh session, merge-ready and merge confirmation"
```

---

### Task 7c: Auto-review observer on PR creation

**Files:**
- Create: `backend/internal/service/ticket/autoreview.go`, `autoreview_test.go`

**Interfaces:**
- Consumes: `cdc.Broadcaster.Subscribe(fn func(cdc.Event)) func()` (`cdc/broadcast.go:28`, called synchronously from the poller so `fn` must not block), `cdc.EventPRCreated`, Task 7b `AutoReview`.
- Produces:
  - `type AutoReviewer struct` with `NewAutoReviewer(svc interface{ AutoReview(context.Context, domain.SessionID) error }, log *slog.Logger) *AutoReviewer`
  - `(*AutoReviewer) Subscribe(ctx context.Context, b *cdc.Broadcaster) (unsubscribe func())` — each `pr_created` event with a session id runs `AutoReview` on a goroutine bound to `ctx`; errors are logged at warn and never retried.

- [ ] **Step 1: Write the failing test**

```go
package ticket

import (
	"context"
	"io"
	"log/slog"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/cdc"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

type recordingReviewer struct {
	mu  sync.Mutex
	ids []domain.SessionID
}

func (r *recordingReviewer) AutoReview(_ context.Context, id domain.SessionID) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.ids = append(r.ids, id)
	return nil
}

func TestAutoReviewerReactsToPRCreatedOnly(t *testing.T) {
	rec := &recordingReviewer{}
	b := cdc.NewBroadcaster()
	ar := NewAutoReviewer(rec, slog.New(slog.NewTextHandler(io.Discard, nil)))
	unsub := ar.Subscribe(context.Background(), b)
	defer unsub()
	b.Publish(cdc.Event{Type: cdc.EventPRCreated, SessionID: "tk-1"})
	b.Publish(cdc.Event{Type: cdc.EventPRUpdated, SessionID: "tk-1"})
	b.Publish(cdc.Event{Type: cdc.EventSessionUpdated, SessionID: "tk-2"})
	b.Publish(cdc.Event{Type: cdc.EventPRCreated})
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		rec.mu.Lock()
		n := len(rec.ids)
		rec.mu.Unlock()
		if n == 1 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	rec.mu.Lock()
	defer rec.mu.Unlock()
	if len(rec.ids) != 1 || rec.ids[0] != "tk-1" {
		t.Fatalf("ids = %v", rec.ids)
	}
}
```

If the constructor is not `cdc.NewBroadcaster()`, use the one `cdc/broadcast.go:22` exports.

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && go test ./internal/service/ticket/ -run TestAutoReviewer`
Expected: undefined `NewAutoReviewer`.

- [ ] **Step 3: Implement**

`backend/internal/service/ticket/autoreview.go`:

```go
package ticket

import (
	"context"
	"log/slog"

	"github.com/OmarAly92/operator/backend/internal/cdc"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

type autoReviewSource interface {
	AutoReview(ctx context.Context, sessionID domain.SessionID) error
}

type AutoReviewer struct {
	svc autoReviewSource
	log *slog.Logger
}

func NewAutoReviewer(svc autoReviewSource, log *slog.Logger) *AutoReviewer {
	if log == nil {
		log = slog.Default()
	}
	return &AutoReviewer{svc: svc, log: log}
}

func (a *AutoReviewer) Subscribe(ctx context.Context, b *cdc.Broadcaster) func() {
	return b.Subscribe(func(e cdc.Event) {
		if e.Type != cdc.EventPRCreated || e.SessionID == "" {
			return
		}
		id := domain.SessionID(e.SessionID)
		go func() {
			if err := a.svc.AutoReview(ctx, id); err != nil {
				a.log.Warn("ticket auto-review failed", "session", id, "err", err)
			}
		}()
	})
}
```

- [ ] **Step 4: Run, then commit**

Run: `cd backend && go test -race ./internal/service/ticket/ -run TestAutoReviewer -v`
Expected: PASS.

```bash
git add backend/internal/service/ticket/autoreview.go backend/internal/service/ticket/autoreview_test.go
git commit -m "feat(tickets): auto-review when an implementing session opens a PR"
```

---

### Task 8: `ticket` on the session read model

**Files:**
- Modify: `backend/internal/domain/session.go:125-134`
- Modify: `backend/internal/service/session/service.go` — the store interface near line 59 and `toSession` at line 974
- Modify: `backend/internal/service/session/service_test.go` (or the nearest existing `toSession`/`Get` test) — one test
- Modify: any test fake implementing the session service's store interface (grep `ListPRFactsForSession(` under `backend/internal` in `_test.go` files) — add a no-op `SessionTicketRef`.

**Interfaces:**
- Consumes: `(*store.Store).SessionTicketRef` from Task 1.
- Produces: `domain.Session.Ticket *domain.SessionTicketRef` with tag `json:"ticket,omitempty"`.

- [ ] **Step 1: Add the field**

In `backend/internal/domain/session.go` add to `Session` after `TerminalHandleID`:

```go
	Ticket           *SessionTicketRef `json:"ticket,omitempty"`
```

- [ ] **Step 2: Write the failing test**

Find the existing test file that constructs a `*sessionsvc.Service` against a real `sqlitetest` store (`grep -rl "sqlitetest" backend/internal/service/session/*_test.go`; if none exists there, use `backend/internal/integration/lifecycle_sqlite_test.go`'s `newStack` in Task 10 instead and skip to Step 4). Add:

```go
func TestGetCarriesTicketRef(t *testing.T) {
	ctx := context.Background()
	st := newStack(t)
	sess, _, _, err := st.sm.Spawn(ctx, ports.SpawnConfig{ProjectID: "mer", Kind: domain.KindWorker, Branch: "b", Prompt: "do it"})
	if err != nil {
		t.Fatal(err)
	}
	got, err := st.sm.Get(ctx, sess.ID)
	if err != nil || got.Ticket != nil {
		t.Fatalf("unlinked session ticket = %+v err=%v", got.Ticket, err)
	}
	if err := st.store.InsertTicket(ctx, domain.TicketRecord{ProjectID: "mer", Slug: "editor", CreatedAt: time.Now()}); err != nil {
		t.Fatal(err)
	}
	if err := st.store.InsertPlanAssignment(ctx, domain.PlanAssignmentRecord{ProjectID: "mer", Slug: "editor", PlanFile: "plans/01-core.md", SessionID: sess.ID, AssignedAt: time.Now()}); err != nil {
		t.Fatal(err)
	}
	got, err = st.sm.Get(ctx, sess.ID)
	if err != nil || got.Ticket == nil || got.Ticket.Slug != "editor" || got.Ticket.PlanFile != "plans/01-core.md" || got.Ticket.Role != domain.TicketRoleImplementing {
		t.Fatalf("ticket = %+v err=%v", got.Ticket, err)
	}
	list, err := st.sm.List(ctx, sessionsvc.ListFilter{ProjectID: "mer"})
	if err != nil || len(list) != 1 || list[0].Ticket == nil {
		t.Fatalf("list = %+v err=%v", list, err)
	}
}
```

This test belongs in `backend/internal/integration/lifecycle_sqlite_test.go`, which already has `newStack`.

- [ ] **Step 3: Run to verify it fails**

Run: `cd backend && go test ./internal/integration/ -run TestGetCarriesTicketRef`
Expected: FAIL, `ticket = <nil>`.

- [ ] **Step 4: Implement**

In `backend/internal/service/session/service.go`, add to the store interface the service consumes (the one that declares `ListPRFactsForSession`):

```go
	SessionTicketRef(ctx context.Context, id domain.SessionID) (domain.SessionTicketRef, bool, error)
```

and change `toSession` to:

```go
func (s *Service) toSession(ctx context.Context, rec domain.SessionRecord) (domain.Session, error) {
	prs, err := s.store.ListPRFactsForSession(ctx, rec.ID)
	if err != nil {
		return domain.Session{}, fmt.Errorf("pr facts %s: %w", rec.ID, err)
	}
	prs = deduplicatePRFacts(prs)
	sess := domain.Session{
		SessionRecord:    rec,
		Status:           deriveStatus(rec, prs, s.now(), s.harnessSignals(rec.Harness)),
		SCMStatus:        deriveSCMStatus(prs),
		TerminalHandleID: rec.Metadata.RuntimeHandleID,
		PRs:              prs,
	}
	ref, ok, err := s.store.SessionTicketRef(ctx, rec.ID)
	if err != nil {
		return domain.Session{}, fmt.Errorf("ticket ref %s: %w", rec.ID, err)
	}
	if ok {
		sess.Ticket = &ref
	}
	return sess, nil
}
```

Run `cd backend && go build ./... && go vet ./...`; every fake that implements that store interface now fails to compile. Add to each:

```go
func (f *fakeStore) SessionTicketRef(context.Context, domain.SessionID) (domain.SessionTicketRef, bool, error) {
	return domain.SessionTicketRef{}, false, nil
}
```

using the fake's real receiver name.

- [ ] **Step 5: Regenerate the API and run**

The `Session` schema is reflected into OpenAPI (`schemaNames` has `"DomainSession": "Session"`), so the new field changes `openapi.yaml`. Add to `schemaNames` in `backend/internal/httpd/apispec/specgen/build.go`:

```go
	"DomainSessionTicketRef": "SessionTicketRef",
	"DomainTicketRole":       "TicketRole",
```

Run from the repo root: `npm run api`, then `cd backend && go test ./... && go vet ./...`, then `cd frontend && npm run typecheck`.
Expected: PASS; `git status` shows `openapi.yaml` and `frontend/src/api/schema.ts` changed with a `ticket` property on `Session`.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/domain/session.go backend/internal/service/session backend/internal/integration backend/internal/httpd/apispec frontend/src/api/schema.ts
git add -u backend/internal
git commit -m "feat(tickets): sessions carry their ticket link"
```

---

### Task 9: HTTP controller, DTOs, OpenAPI operations, wiring

**Files:**
- Create: `backend/internal/httpd/controllers/tickets.go`
- Test: `backend/internal/httpd/controllers/tickets_test.go`
- Modify: `backend/internal/httpd/controllers/dto.go` (append)
- Modify: `backend/internal/httpd/apispec/specgen/build.go` — tag in `Build()` (~line 84), `ops = append(ops, ticketOperations()...)` in `operations()` (~line 434), new `ticketOperations()`, `schemaNames` entries
- Modify: `backend/internal/httpd/api.go:70,95,131,160-167`
- Modify: `backend/internal/daemon/daemon.go:395-435`

**Interfaces:**
- Consumes: Task 6/7 `ticket.Service` methods; `envelope`, `apierr`, `apispec.NotImplemented`, `decodeJSON`, `decodeOptionalJSON` (`claude_accounts.go:97`), `projectID(r)` (`projects.go:160`), `workspacewatch.Watch`.
- Produces:
  - `controllers.TicketService` interface (mirrors the service's exported methods).
  - `controllers.TicketsController{Svc TicketService}` with `Register(chi.Router)`.
  - DTOs: `TicketSlugParam`, `TicketPlanParam`, `TicketFileQuery`, `TicketView`, `PlanView`, `ListTicketsResponse`, `TicketResponse`, `TicketFileResponse`, `CreateTicketRequest`, `CreateTicketResponse`, `SaveTicketFileRequest`, `PlanTicketRequest`, `AssignPlanRequest`, `AssignPlanQuery`, `AssignPlanResponse`, `ReviewPlanRequest`, `ReviewPlanResponse`, `MergeReadyRequest`.
  - `httpd.APIDeps.Tickets controllers.TicketService`.

- [ ] **Step 1: Append the DTOs**

Append to `backend/internal/httpd/controllers/dto.go`:

```go
type TicketSlugParam struct {
	Slug string `path:"slug" description:"Ticket folder name under .operator/tickets."`
}

type TicketPlanParam struct {
	Plan string `path:"plan" description:"Plan file name inside the ticket's plans/ folder, e.g. 01-daemon.md."`
}

type TicketFileQuery struct {
	Path string `query:"path" description:"Ticket-folder-relative markdown path, e.g. spec.md or plans/01-daemon.md."`
}

type AssignPlanQuery struct {
	DryRun bool `query:"dryRun" description:"Compute warnings without spawning."`
}

type PlanView struct {
	File              string            `json:"file"`
	Order             int               `json:"order"`
	Title             string            `json:"title"`
	Status            domain.PlanStatus `json:"status" enum:"todo,idle,working,needs_you,in_review,reviewing,awaiting_merge,merged,done,terminated"`
	SessionID         domain.SessionID  `json:"sessionId,omitempty"`
	ReviewerSessionID domain.SessionID  `json:"reviewerSessionId,omitempty"`
	MergeSummary      string            `json:"mergeSummary,omitempty"`
	KickoffFile       string            `json:"kickoffFile,omitempty"`
	Unordered         bool              `json:"unordered,omitempty"`
	Warning           string            `json:"warning,omitempty"`
}

type TicketView struct {
	ProjectID         domain.ProjectID    `json:"projectId"`
	Slug              string              `json:"slug"`
	Title             string              `json:"title"`
	Brief             string              `json:"brief,omitempty"`
	Status            domain.TicketStatus `json:"status" enum:"draft,planning,ready,in_progress,awaiting_merge,done,archived"`
	PlanningSessionID domain.SessionID    `json:"planningSessionId,omitempty"`
	Plans             []PlanView          `json:"plans"`
	Files             []string            `json:"files"`
	Warning           string              `json:"warning,omitempty"`
	CreatedAt         *time.Time          `json:"createdAt,omitempty"`
	ArchivedAt        *time.Time          `json:"archivedAt,omitempty"`
}

type ListTicketsResponse struct {
	Tickets []TicketView `json:"tickets"`
}

type TicketResponse struct {
	Ticket TicketView `json:"ticket"`
}

type TicketFileResponse struct {
	Path       string    `json:"path"`
	Content    string    `json:"content"`
	ModifiedAt time.Time `json:"modifiedAt"`
}

type CreateTicketRequest struct {
	Title string `json:"title" maxLength:"200"`
	Brief string `json:"brief,omitempty" maxLength:"4000"`
}

type CreateTicketResponse struct {
	Ticket   TicketView `json:"ticket"`
	Warnings []string   `json:"warnings"`
}

type SaveTicketFileRequest struct {
	Content           string     `json:"content" maxLength:"1048576"`
	IfUnmodifiedSince *time.Time `json:"ifUnmodifiedSince,omitempty"`
}

type PlanTicketRequest struct {
	Harness         domain.AgentHarness    `json:"harness,omitempty"`
	Model           string                 `json:"model,omitempty" maxLength:"128"`
	ClaudeAccountID domain.ClaudeAccountID `json:"claudeAccountId,omitempty" maxLength:"64"`
	Extra           string                 `json:"extra,omitempty" maxLength:"65536"`
}

type AssignPlanRequest struct {
	Harness         domain.AgentHarness    `json:"harness,omitempty"`
	Model           string                 `json:"model,omitempty" maxLength:"128"`
	ClaudeAccountID domain.ClaudeAccountID `json:"claudeAccountId,omitempty" maxLength:"64"`
	Extra           string                 `json:"extra,omitempty" maxLength:"65536"`
	Force           bool                   `json:"force,omitempty"`
}

type AssignPlanResponse struct {
	Warnings []string     `json:"warnings"`
	Session  *SessionView `json:"session,omitempty"`
}

type ReviewPlanRequest struct {
	Harness         domain.AgentHarness    `json:"harness,omitempty"`
	Model           string                 `json:"model,omitempty" maxLength:"128"`
	ClaudeAccountID domain.ClaudeAccountID `json:"claudeAccountId,omitempty" maxLength:"64"`
	Extra           string                 `json:"extra,omitempty" maxLength:"65536"`
	Reviewer        string                 `json:"reviewer,omitempty" enum:"planner,new"`
}

type ReviewPlanResponse struct {
	Session SessionView `json:"session"`
	Spawned bool        `json:"spawned"`
}

type MergeReadyRequest struct {
	Summary string `json:"summary,omitempty" maxLength:"1000"`
}
```

If `dto.go` does not already import `time`, add it. `SessionView` and `sessionView(...)` exist at `dto.go:140` / `sessions.go:2128`; check whether `sessionView` is a method or a function and call it accordingly in Step 3.

- [ ] **Step 2: Write the failing controller test**

`backend/internal/httpd/controllers/tickets_test.go`:

```go
package controllers_test

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	ticketsvc "github.com/OmarAly92/operator/backend/internal/service/ticket"
)

type fakeTicketService struct {
	tickets    []domain.Ticket
	file       ticketsvc.File
	created    ticketsvc.CreateInput
	assigned   ticketsvc.AssignInput
	assignName string
	planned    ticketsvc.SpawnInput
	reviewed   ticketsvc.ReviewInput
	reviewName string
	mergeReady string
	merged     string
	done       string
	archived   *bool
	err        error
}

func (f *fakeTicketService) List(context.Context, domain.ProjectID) ([]domain.Ticket, error) {
	return f.tickets, f.err
}
func (f *fakeTicketService) Get(_ context.Context, _ domain.ProjectID, slug string) (domain.Ticket, error) {
	if f.err != nil {
		return domain.Ticket{}, f.err
	}
	for _, t := range f.tickets {
		if t.Slug == slug {
			return t, nil
		}
	}
	return domain.Ticket{}, apierr.NotFound("TICKET_NOT_FOUND", "Unknown ticket")
}
func (f *fakeTicketService) ReadFile(_ context.Context, _ domain.ProjectID, _, _ string) (ticketsvc.File, error) {
	return f.file, f.err
}
func (f *fakeTicketService) WriteFile(_ context.Context, _ domain.ProjectID, _, rel, content string, since time.Time) (ticketsvc.File, error) {
	if f.err != nil {
		return ticketsvc.File{}, f.err
	}
	f.file = ticketsvc.File{Path: rel, Content: content, ModifiedAt: since.Add(time.Second)}
	return f.file, nil
}
func (f *fakeTicketService) Create(_ context.Context, _ domain.ProjectID, in ticketsvc.CreateInput) (ticketsvc.CreateResult, error) {
	f.created = in
	if f.err != nil {
		return ticketsvc.CreateResult{}, f.err
	}
	return ticketsvc.CreateResult{Ticket: domain.Ticket{Slug: "new", Title: in.Title, Status: domain.TicketStatusDraft}, Warnings: []string{"not_on_default_branch"}}, nil
}
func (f *fakeTicketService) Plan(_ context.Context, _ domain.ProjectID, _ string, in ticketsvc.SpawnInput) (domain.Session, error) {
	f.planned = in
	return domain.Session{SessionRecord: domain.SessionRecord{ID: "tk-1"}}, f.err
}
func (f *fakeTicketService) Assign(_ context.Context, _ domain.ProjectID, _, plan string, in ticketsvc.AssignInput) (ticketsvc.AssignResult, error) {
	f.assigned, f.assignName = in, plan
	if f.err != nil {
		return ticketsvc.AssignResult{}, f.err
	}
	if in.DryRun {
		return ticketsvc.AssignResult{Warnings: []string{"plan_order"}}, nil
	}
	return ticketsvc.AssignResult{Warnings: []string{}, Session: &domain.Session{SessionRecord: domain.SessionRecord{ID: "tk-2"}}}, nil
}
func (f *fakeTicketService) MarkDone(_ context.Context, _ domain.ProjectID, _, plan string) (domain.Ticket, error) {
	f.done = plan
	return domain.Ticket{Slug: "editor", Status: domain.TicketStatusDone}, f.err
}
func (f *fakeTicketService) SetArchived(_ context.Context, _ domain.ProjectID, _ string, archived bool) (domain.Ticket, error) {
	f.archived = &archived
	return domain.Ticket{Slug: "editor", Status: domain.TicketStatusArchived}, f.err
}
func (f *fakeTicketService) WatchRoot(context.Context, domain.ProjectID) (string, error) {
	return "", errors.New("not watched in tests")
}
func (f *fakeTicketService) Review(_ context.Context, _ domain.ProjectID, _, plan string, in ticketsvc.ReviewInput) (ticketsvc.ReviewResult, error) {
	f.reviewed, f.reviewName = in, plan
	if f.err != nil {
		return ticketsvc.ReviewResult{}, f.err
	}
	return ticketsvc.ReviewResult{Session: domain.Session{SessionRecord: domain.SessionRecord{ID: "tk-9"}}, Spawned: in.Reviewer == "new"}, nil
}
func (f *fakeTicketService) MergeReady(_ context.Context, _ domain.ProjectID, _, plan, summary string) (domain.Ticket, error) {
	f.mergeReady = summary
	return domain.Ticket{Slug: "editor", Status: domain.TicketStatusAwaitMerge, Plans: []domain.Plan{{File: "plans/" + plan, Status: domain.PlanStatusAwaitMerge, MergeSummary: summary}}}, f.err
}
func (f *fakeTicketService) ApproveMerge(_ context.Context, _ domain.ProjectID, _, plan string) (domain.Ticket, error) {
	f.merged = plan
	return domain.Ticket{Slug: "editor", Status: domain.TicketStatusInProgress}, f.err
}

func newTicketsTestServer(t *testing.T, svc controllers.TicketService) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{Tickets: svc}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestTicketsListGetAndErrors(t *testing.T) {
	svc := &fakeTicketService{tickets: []domain.Ticket{{ProjectID: "p", Slug: "editor", Title: "Editor", Status: domain.TicketStatusReady, Plans: []domain.Plan{{File: "plans/01-core.md", Order: 1, Title: "Core", Status: domain.PlanStatusTodo}}, Files: []string{"ticket.md"}}}}
	srv := newTicketsTestServer(t, svc)
	body, status, _ := doRequest(t, srv, "GET", "/api/v1/projects/p/tickets", "")
	if status != http.StatusOK {
		t.Fatalf("status %d body %s", status, body)
	}
	var list controllers.ListTicketsResponse
	mustJSON(t, body, &list)
	if len(list.Tickets) != 1 || list.Tickets[0].Slug != "editor" || list.Tickets[0].Plans[0].Status != domain.PlanStatusTodo || list.Tickets[0].CreatedAt != nil {
		t.Fatalf("list = %+v", list)
	}
	body, status, _ = doRequest(t, srv, "GET", "/api/v1/projects/p/tickets/nope", "")
	var env struct {
		Code string `json:"code"`
	}
	mustJSON(t, body, &env)
	if status != http.StatusNotFound || env.Code != "TICKET_NOT_FOUND" {
		t.Fatalf("status %d code %q", status, env.Code)
	}
	svc.err = apierr.Invalid("TICKET_UNSUPPORTED_PROJECT", "x", nil)
	_, status, _ = doRequest(t, srv, "GET", "/api/v1/projects/p/tickets", "")
	if status != http.StatusBadRequest {
		t.Fatalf("status %d", status)
	}
}

func TestTicketsFileRoutes(t *testing.T) {
	svc := &fakeTicketService{file: ticketsvc.File{Path: "spec.md", Content: "# S\n", ModifiedAt: time.Unix(1700000000, 0).UTC()}}
	srv := newTicketsTestServer(t, svc)
	body, status, _ := doRequest(t, srv, "GET", "/api/v1/projects/p/tickets/editor/file?path=spec.md", "")
	var f controllers.TicketFileResponse
	mustJSON(t, body, &f)
	if status != http.StatusOK || f.Content != "# S\n" || f.ModifiedAt.Unix() != 1700000000 {
		t.Fatalf("status %d f=%+v", status, f)
	}
	_, status, _ = doRequest(t, srv, "GET", "/api/v1/projects/p/tickets/editor/file", "")
	if status != http.StatusBadRequest {
		t.Fatalf("missing path status %d", status)
	}
	body, status, _ = doRequest(t, srv, "PUT", "/api/v1/projects/p/tickets/editor/file?path=spec.md", `{"content":"v2","ifUnmodifiedSince":"2023-11-14T22:13:20Z"}`)
	mustJSON(t, body, &f)
	if status != http.StatusOK || f.Content != "v2" || f.Path != "spec.md" {
		t.Fatalf("status %d f=%+v", status, f)
	}
	svc.err = apierr.Conflict("TICKET_FILE_STALE", "x", map[string]any{"modifiedAt": "later"})
	_, status, _ = doRequest(t, srv, "PUT", "/api/v1/projects/p/tickets/editor/file?path=spec.md", `{"content":"v3"}`)
	if status != http.StatusConflict {
		t.Fatalf("stale status %d", status)
	}
}

func TestTicketsCreatePlanAssignDoneArchive(t *testing.T) {
	svc := &fakeTicketService{}
	srv := newTicketsTestServer(t, svc)
	body, status, _ := doRequest(t, srv, "POST", "/api/v1/projects/p/tickets", `{"title":"Editor","brief":"b"}`)
	var created controllers.CreateTicketResponse
	mustJSON(t, body, &created)
	if status != http.StatusCreated || created.Ticket.Slug != "new" || svc.created.Brief != "b" || len(created.Warnings) != 1 {
		t.Fatalf("status %d created=%+v", status, created)
	}
	_, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets", `{"brief":"b"}`)
	if status != http.StatusBadRequest {
		t.Fatalf("missing title status %d", status)
	}
	body, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plan", `{"harness":"claude-code","claudeAccountId":"personal","extra":"hi"}`)
	var sv controllers.SessionView
	mustJSON(t, body, &sv)
	if status != http.StatusCreated || sv.ID != "tk-1" || svc.planned.ClaudeAccountID != "personal" || svc.planned.Extra != "hi" {
		t.Fatalf("plan status %d sv=%+v planned=%+v", status, sv, svc.planned)
	}
	body, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/assign?dryRun=1", `{}`)
	var ar controllers.AssignPlanResponse
	mustJSON(t, body, &ar)
	if status != http.StatusOK || ar.Session != nil || len(ar.Warnings) != 1 || !svc.assigned.DryRun || svc.assignName != "01-core.md" {
		t.Fatalf("dry run status %d ar=%+v assigned=%+v", status, ar, svc.assigned)
	}
	body, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/assign", `{"force":true,"harness":"codex"}`)
	mustJSON(t, body, &ar)
	if status != http.StatusCreated || ar.Session == nil || ar.Session.ID != "tk-2" || !svc.assigned.Force || svc.assigned.Harness != domain.HarnessCodex {
		t.Fatalf("assign status %d ar=%+v", status, ar)
	}
	svc.err = apierr.Conflict("TICKET_ASSIGN_BLOCKED", "x", map[string]any{"warnings": []string{"plan_order"}})
	body, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/assign", `{}`)
	var env struct {
		Code    string         `json:"code"`
		Details map[string]any `json:"details"`
	}
	mustJSON(t, body, &env)
	if status != http.StatusConflict || env.Code != "TICKET_ASSIGN_BLOCKED" || env.Details["warnings"] == nil {
		t.Fatalf("blocked status %d env=%+v", status, env)
	}
	svc.err = nil
	body, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/done", "")
	var tr controllers.TicketResponse
	mustJSON(t, body, &tr)
	if status != http.StatusOK || svc.done != "01-core.md" || tr.Ticket.Status != domain.TicketStatusDone {
		t.Fatalf("done status %d tr=%+v", status, tr)
	}
	_, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/archive", "")
	if status != http.StatusOK || svc.archived == nil || !*svc.archived {
		t.Fatalf("archive status %d archived=%v", status, svc.archived)
	}
	_, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/unarchive", "")
	if status != http.StatusOK || *svc.archived {
		t.Fatalf("unarchive status %d archived=%v", status, *svc.archived)
	}
}

func TestTicketsReviewMergeReadyMerge(t *testing.T) {
	svc := &fakeTicketService{}
	srv := newTicketsTestServer(t, svc)
	body, status, _ := doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/review", `{"reviewer":"new","model":"sonnet","extra":"strict"}`)
	var rr controllers.ReviewPlanResponse
	mustJSON(t, body, &rr)
	if status != http.StatusOK || rr.Session.ID != "tk-9" || !rr.Spawned || svc.reviewed.Reviewer != "new" || svc.reviewed.Model != "sonnet" || svc.reviewName != "01-core.md" {
		t.Fatalf("review status %d rr=%+v reviewed=%+v", status, rr, svc.reviewed)
	}
	body, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/merge-ready", `{"summary":"gates green"}`)
	var tr controllers.TicketResponse
	mustJSON(t, body, &tr)
	if status != http.StatusOK || svc.mergeReady != "gates green" || tr.Ticket.Status != domain.TicketStatusAwaitMerge || tr.Ticket.Plans[0].MergeSummary != "gates green" {
		t.Fatalf("merge-ready status %d tr=%+v", status, tr)
	}
	_, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/merge", "")
	if status != http.StatusOK || svc.merged != "01-core.md" {
		t.Fatalf("merge status %d merged=%q", status, svc.merged)
	}
	svc.err = apierr.Conflict("TICKET_NOT_MERGE_READY", "x", nil)
	_, status, _ = doRequest(t, srv, "POST", "/api/v1/projects/p/tickets/editor/plans/01-core.md/merge", "")
	if status != http.StatusConflict {
		t.Fatalf("not ready status %d", status)
	}
}

func TestTicketsNotImplementedWithoutService(t *testing.T) {
	srv := newTicketsTestServer(t, nil)
	_, status, _ := doRequest(t, srv, "GET", "/api/v1/projects/p/tickets", "")
	if status != http.StatusNotImplemented {
		t.Fatalf("status %d", status)
	}
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd backend && go test ./internal/httpd/controllers/ -run TestTickets`
Expected: compile error, `httpd.APIDeps` has no field `Tickets`.

- [ ] **Step 4: Write the controller**

`backend/internal/httpd/controllers/tickets.go`:

```go
package controllers

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	ticketsvc "github.com/OmarAly92/operator/backend/internal/service/ticket"
	"github.com/OmarAly92/operator/backend/internal/workspacewatch"
)

type TicketService interface {
	List(ctx context.Context, project domain.ProjectID) ([]domain.Ticket, error)
	Get(ctx context.Context, project domain.ProjectID, slug string) (domain.Ticket, error)
	ReadFile(ctx context.Context, project domain.ProjectID, slug, rel string) (ticketsvc.File, error)
	WriteFile(ctx context.Context, project domain.ProjectID, slug, rel, content string, ifUnmodifiedSince time.Time) (ticketsvc.File, error)
	Create(ctx context.Context, project domain.ProjectID, in ticketsvc.CreateInput) (ticketsvc.CreateResult, error)
	Plan(ctx context.Context, project domain.ProjectID, slug string, in ticketsvc.SpawnInput) (domain.Session, error)
	Assign(ctx context.Context, project domain.ProjectID, slug, plan string, in ticketsvc.AssignInput) (ticketsvc.AssignResult, error)
	MarkDone(ctx context.Context, project domain.ProjectID, slug, plan string) (domain.Ticket, error)
	SetArchived(ctx context.Context, project domain.ProjectID, slug string, archived bool) (domain.Ticket, error)
	WatchRoot(ctx context.Context, project domain.ProjectID) (string, error)
	Review(ctx context.Context, project domain.ProjectID, slug, plan string, in ticketsvc.ReviewInput) (ticketsvc.ReviewResult, error)
	MergeReady(ctx context.Context, project domain.ProjectID, slug, plan, summary string) (domain.Ticket, error)
	ApproveMerge(ctx context.Context, project domain.ProjectID, slug, plan string) (domain.Ticket, error)
}

type TicketsController struct {
	Svc TicketService
}

func (c *TicketsController) Register(r chi.Router) {
	r.Get("/projects/{id}/tickets", c.list)
	r.Post("/projects/{id}/tickets", c.create)
	r.Get("/projects/{id}/tickets/events", c.events)
	r.Get("/projects/{id}/tickets/{slug}", c.get)
	r.Get("/projects/{id}/tickets/{slug}/file", c.readFile)
	r.Put("/projects/{id}/tickets/{slug}/file", c.writeFile)
	r.Post("/projects/{id}/tickets/{slug}/plan", c.plan)
	r.Post("/projects/{id}/tickets/{slug}/archive", c.archive)
	r.Post("/projects/{id}/tickets/{slug}/unarchive", c.unarchive)
	r.Post("/projects/{id}/tickets/{slug}/plans/{plan}/assign", c.assign)
	r.Post("/projects/{id}/tickets/{slug}/plans/{plan}/done", c.done)
	r.Post("/projects/{id}/tickets/{slug}/plans/{plan}/review", c.review)
	r.Post("/projects/{id}/tickets/{slug}/plans/{plan}/merge-ready", c.mergeReady)
	r.Post("/projects/{id}/tickets/{slug}/plans/{plan}/merge", c.merge)
}

func ticketSlug(r *http.Request) string { return strings.TrimSpace(chi.URLParam(r, "slug")) }
func ticketPlan(r *http.Request) string { return strings.TrimSpace(chi.URLParam(r, "plan")) }

func planView(p domain.Plan) PlanView {
	return PlanView{File: p.File, Order: p.Order, Title: p.Title, Status: p.Status, SessionID: p.SessionID, ReviewerSessionID: p.ReviewerID, MergeSummary: p.MergeSummary, KickoffFile: p.KickoffFile, Unordered: p.Unordered, Warning: p.Warning}
}

func ticketView(t domain.Ticket) TicketView {
	v := TicketView{
		ProjectID: t.ProjectID, Slug: t.Slug, Title: t.Title, Brief: t.Brief, Status: t.Status,
		PlanningSessionID: t.PlanningSessionID, Warning: t.Warning,
		Plans: make([]PlanView, 0, len(t.Plans)), Files: t.Files,
	}
	if v.Files == nil {
		v.Files = []string{}
	}
	for _, p := range t.Plans {
		v.Plans = append(v.Plans, planView(p))
	}
	if !t.CreatedAt.IsZero() {
		at := t.CreatedAt
		v.CreatedAt = &at
	}
	if !t.ArchivedAt.IsZero() {
		at := t.ArchivedAt
		v.ArchivedAt = &at
	}
	return v
}

func ticketFileView(f ticketsvc.File) TicketFileResponse {
	return TicketFileResponse{Path: f.Path, Content: f.Content, ModifiedAt: f.ModifiedAt}
}

func (c *TicketsController) list(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/projects/{id}/tickets")
		return
	}
	tickets, err := c.Svc.List(r.Context(), projectID(r))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	views := make([]TicketView, 0, len(tickets))
	for _, t := range tickets {
		views = append(views, ticketView(t))
	}
	envelope.WriteJSON(w, http.StatusOK, ListTicketsResponse{Tickets: views})
}

func (c *TicketsController) get(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/projects/{id}/tickets/{slug}")
		return
	}
	t, err := c.Svc.Get(r.Context(), projectID(r), ticketSlug(r))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, TicketResponse{Ticket: ticketView(t)})
}

func (c *TicketsController) create(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets")
		return
	}
	var req CreateTicketRequest
	if err := decodeJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	if strings.TrimSpace(req.Title) == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "TICKET_TITLE_REQUIRED", "title is required", nil)
		return
	}
	res, err := c.Svc.Create(r.Context(), projectID(r), ticketsvc.CreateInput{Title: req.Title, Brief: req.Brief})
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	warnings := res.Warnings
	if warnings == nil {
		warnings = []string{}
	}
	envelope.WriteJSON(w, http.StatusCreated, CreateTicketResponse{Ticket: ticketView(res.Ticket), Warnings: warnings})
}

func (c *TicketsController) readFile(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/projects/{id}/tickets/{slug}/file")
		return
	}
	rel := strings.TrimSpace(r.URL.Query().Get("path"))
	if rel == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "TICKET_PATH_REQUIRED", "path query parameter is required", nil)
		return
	}
	f, err := c.Svc.ReadFile(r.Context(), projectID(r), ticketSlug(r), rel)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, ticketFileView(f))
}

func (c *TicketsController) writeFile(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "PUT", "/api/v1/projects/{id}/tickets/{slug}/file")
		return
	}
	rel := strings.TrimSpace(r.URL.Query().Get("path"))
	if rel == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "TICKET_PATH_REQUIRED", "path query parameter is required", nil)
		return
	}
	var req SaveTicketFileRequest
	if err := decodeJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	var since time.Time
	if req.IfUnmodifiedSince != nil {
		since = *req.IfUnmodifiedSince
	}
	f, err := c.Svc.WriteFile(r.Context(), projectID(r), ticketSlug(r), rel, req.Content, since)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, ticketFileView(f))
}

func (c *TicketsController) plan(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets/{slug}/plan")
		return
	}
	var req PlanTicketRequest
	if err := decodeOptionalJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	sess, err := c.Svc.Plan(r.Context(), projectID(r), ticketSlug(r), ticketsvc.SpawnInput{Harness: req.Harness, Model: req.Model, ClaudeAccountID: req.ClaudeAccountID, Extra: req.Extra})
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusCreated, sessionView(sess))
}

func (c *TicketsController) assign(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/assign")
		return
	}
	var req AssignPlanRequest
	if err := decodeOptionalJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	dry := r.URL.Query().Get("dryRun")
	in := ticketsvc.AssignInput{
		SpawnInput: ticketsvc.SpawnInput{Harness: req.Harness, Model: req.Model, ClaudeAccountID: req.ClaudeAccountID, Extra: req.Extra},
		Force:      req.Force,
		DryRun:     dry == "1" || dry == "true",
	}
	res, err := c.Svc.Assign(r.Context(), projectID(r), ticketSlug(r), ticketPlan(r), in)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	out := AssignPlanResponse{Warnings: res.Warnings}
	if out.Warnings == nil {
		out.Warnings = []string{}
	}
	status := http.StatusOK
	if res.Session != nil {
		v := sessionView(*res.Session)
		out.Session = &v
		status = http.StatusCreated
	}
	envelope.WriteJSON(w, status, out)
}

func (c *TicketsController) done(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/done")
		return
	}
	t, err := c.Svc.MarkDone(r.Context(), projectID(r), ticketSlug(r), ticketPlan(r))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, TicketResponse{Ticket: ticketView(t)})
}

func (c *TicketsController) review(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/review")
		return
	}
	var req ReviewPlanRequest
	if err := decodeOptionalJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	res, err := c.Svc.Review(r.Context(), projectID(r), ticketSlug(r), ticketPlan(r), ticketsvc.ReviewInput{
		SpawnInput: ticketsvc.SpawnInput{Harness: req.Harness, Model: req.Model, ClaudeAccountID: req.ClaudeAccountID, Extra: req.Extra},
		Reviewer:   req.Reviewer,
	})
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, ReviewPlanResponse{Session: sessionView(res.Session), Spawned: res.Spawned})
}

func (c *TicketsController) mergeReady(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/merge-ready")
		return
	}
	var req MergeReadyRequest
	if err := decodeOptionalJSON(r, &req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	t, err := c.Svc.MergeReady(r.Context(), projectID(r), ticketSlug(r), ticketPlan(r), req.Summary)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, TicketResponse{Ticket: ticketView(t)})
}

func (c *TicketsController) merge(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/merge")
		return
	}
	t, err := c.Svc.ApproveMerge(r.Context(), projectID(r), ticketSlug(r), ticketPlan(r))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, TicketResponse{Ticket: ticketView(t)})
}

func (c *TicketsController) archive(w http.ResponseWriter, r *http.Request) {
	c.setArchived(w, r, true, "/api/v1/projects/{id}/tickets/{slug}/archive")
}

func (c *TicketsController) unarchive(w http.ResponseWriter, r *http.Request) {
	c.setArchived(w, r, false, "/api/v1/projects/{id}/tickets/{slug}/unarchive")
}

func (c *TicketsController) setArchived(w http.ResponseWriter, r *http.Request, archived bool, specPath string) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", specPath)
		return
	}
	t, err := c.Svc.SetArchived(r.Context(), projectID(r), ticketSlug(r), archived)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, TicketResponse{Ticket: ticketView(t)})
}

func (c *TicketsController) events(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/projects/{id}/tickets/events")
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "SSE_UNSUPPORTED", "Streaming is not supported by this server", nil)
		return
	}
	root, err := c.Svc.WatchRoot(r.Context(), projectID(r))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	changes, err := workspacewatch.Watch(r.Context(), root)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	h := w.Header()
	h.Set("Content-Type", "text/event-stream; charset=utf-8")
	h.Set("Cache-Control", "no-cache")
	h.Set("Connection", "keep-alive")
	h.Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	flusher.Flush()
	keepAlive := time.NewTicker(15 * time.Second)
	defer keepAlive.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case _, ok := <-changes:
			if !ok {
				return
			}
			if _, err := fmt.Fprint(w, "event: tickets_changed\ndata: {}\n\n"); err != nil {
				return
			}
			flusher.Flush()
		case <-keepAlive.C:
			if _, err := fmt.Fprint(w, ": keepalive\n\n"); err != nil {
				return
			}
			flusher.Flush()
		}
	}
}
```

`sessionView` is whatever `sessions.go:2128` defines; if it is a method on `*SessionsController` that needs model attachment, extract the pure record-to-view part into a package function first (a two-line refactor) so both controllers share it.

- [ ] **Step 5: Wire the controller**

`backend/internal/httpd/api.go`:
- `APIDeps`: add `Tickets controllers.TicketService`.
- `API`: add `tickets *controllers.TicketsController`.
- `NewAPI`: add `tickets: &controllers.TicketsController{Svc: deps.Tickets},`.
- `Register`: add `a.tickets.Register(r)` inside the timeout group after `a.inbox.Register(r)`.

`backend/internal/daemon/daemon.go`, before the `httpd.NewWithDeps(...)` call:

```go
	ticketSvc := ticketsvc.New(ticketsvc.Deps{Store: store, Sessions: sessionSvc, BaseURL: fmt.Sprintf("http://127.0.0.1:%d", cfg.Port)})
	ticketsvc.NewAutoReviewer(ticketSvc, log).Subscribe(ctx, cdcPipe.Broadcaster)
```

with import `ticketsvc "github.com/OmarAly92/operator/backend/internal/service/ticket"`, and `Tickets: ticketSvc,` in the `APIDeps` literal. `cdcPipe` is the value from `startCDC` at `daemon.go:139`; `ctx` is the daemon's lifetime context already in scope there. The unsubscribe function is intentionally dropped: the subscription lives as long as the daemon.

- [ ] **Step 6: Declare the operations**

In `backend/internal/httpd/apispec/specgen/build.go`:

Add a tag in `Build()` after the `inbox` tag:

```go
		*(&openapi31.Tag{Name: "tickets"}).WithDescription(
			"Planning tickets: spec and plan documents in the repo, assigned to sessions"),
```

Add `ops = append(ops, ticketOperations()...)` after the inbox line in `operations()`, and:

```go
func ticketOperations() []operation {
	apiErr := func(codes ...int) []respUnit {
		out := make([]respUnit, 0, len(codes)+1)
		for _, c := range codes {
			out = append(out, respUnit{c, envelope.APIError{}})
		}
		return append(out, respUnit{http.StatusNotImplemented, envelope.APIError{}})
	}
	ticketOK := func(status int, body any, codes ...int) []respUnit {
		return append([]respUnit{{status, body}}, apiErr(codes...)...)
	}
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/projects/{id}/tickets", id: "listTickets", tag: "tickets",
			summary:    "List a project's planning tickets with derived statuses",
			pathParams: []any{controllers.ProjectIDParam{}},
			resps:      ticketOK(http.StatusOK, controllers.ListTicketsResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets", id: "createTicket", tag: "tickets",
			summary:    "Create a ticket folder with ticket.md and spec.md and commit it",
			pathParams: []any{controllers.ProjectIDParam{}},
			reqBody:    controllers.CreateTicketRequest{},
			resps:      ticketOK(http.StatusCreated, controllers.CreateTicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodGet, path: "/api/v1/projects/{id}/tickets/events", id: "streamTicketChanges", tag: "tickets",
			summary:      "Server-sent events: tickets_changed whenever the tickets folder changes",
			pathParams:   []any{controllers.ProjectIDParam{}},
			resps:        ticketOK(http.StatusOK, nil, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
			contentTypes: map[int]string{http.StatusOK: "text/event-stream"},
		},
		{
			method: http.MethodGet, path: "/api/v1/projects/{id}/tickets/{slug}", id: "getTicket", tag: "tickets",
			summary:    "Fetch one ticket with its plans and linked sessions",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}},
			resps:      ticketOK(http.StatusOK, controllers.TicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodGet, path: "/api/v1/projects/{id}/tickets/{slug}/file", id: "getTicketFile", tag: "tickets",
			summary:    "Read one markdown file inside the ticket folder",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketFileQuery{}},
			resps:      ticketOK(http.StatusOK, controllers.TicketFileResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodPut, path: "/api/v1/projects/{id}/tickets/{slug}/file", id: "saveTicketFile", tag: "tickets",
			summary:    "Write one markdown file inside the ticket folder, optionally guarded by ifUnmodifiedSince",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketFileQuery{}},
			reqBody:    controllers.SaveTicketFileRequest{},
			resps:      ticketOK(http.StatusOK, controllers.TicketFileResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusConflict, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/plan", id: "planTicket", tag: "tickets",
			summary:         "Spawn the ticket's planning session in place at the project root",
			pathParams:      []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}},
			reqBody:         controllers.PlanTicketRequest{},
			optionalReqBody: true,
			resps:           ticketOK(http.StatusCreated, controllers.SessionView{}, http.StatusBadRequest, http.StatusNotFound, http.StatusConflict, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/archive", id: "archiveTicket", tag: "tickets",
			summary:    "Hide a ticket in the archive",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}},
			resps:      ticketOK(http.StatusOK, controllers.TicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/unarchive", id: "unarchiveTicket", tag: "tickets",
			summary:    "Bring an archived ticket back",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}},
			resps:      ticketOK(http.StatusOK, controllers.TicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/assign", id: "assignPlan", tag: "tickets",
			summary:         "Spawn an implementing session for one plan in a worktree; dryRun=1 only computes warnings",
			pathParams:      []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketPlanParam{}, controllers.AssignPlanQuery{}},
			reqBody:         controllers.AssignPlanRequest{},
			optionalReqBody: true,
			resps:           append([]respUnit{{http.StatusOK, controllers.AssignPlanResponse{}}}, ticketOK(http.StatusCreated, controllers.AssignPlanResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusConflict, http.StatusInternalServerError)...),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/done", id: "markPlanDone", tag: "tickets",
			summary:    "Record a plan as done by hand",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketPlanParam{}},
			resps:      ticketOK(http.StatusOK, controllers.TicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/review", id: "reviewPlan", tag: "tickets",
			summary:         "Ask the planner session, or a fresh session, to review the plan's implementation",
			pathParams:      []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketPlanParam{}},
			reqBody:         controllers.ReviewPlanRequest{},
			optionalReqBody: true,
			resps:           ticketOK(http.StatusOK, controllers.ReviewPlanResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusConflict, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/merge-ready", id: "reportPlanMergeReady", tag: "tickets",
			summary:         "Called by the reviewer: the branch is ready and waits for the user's merge confirmation",
			pathParams:      []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketPlanParam{}},
			reqBody:         controllers.MergeReadyRequest{},
			optionalReqBody: true,
			resps:           ticketOK(http.StatusOK, controllers.TicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusConflict, http.StatusInternalServerError),
		},
		{
			method: http.MethodPost, path: "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/merge", id: "approvePlanMerge", tag: "tickets",
			summary:    "User confirmation: tell the reviewer to merge the branch now",
			pathParams: []any{controllers.ProjectIDParam{}, controllers.TicketSlugParam{}, controllers.TicketPlanParam{}},
			resps:      ticketOK(http.StatusOK, controllers.TicketResponse{}, http.StatusBadRequest, http.StatusNotFound, http.StatusConflict, http.StatusInternalServerError),
		},
	}
}
```

If `respUnit` with a `nil` body is not accepted by the builder for the SSE route, copy exactly what the `/workspace/events` operation (`build.go:~1390`) passes for its 200 response.

Add to `schemaNames`:

```go
	"ControllersTicketView":            "TicketView",
	"ControllersPlanView":              "PlanView",
	"ControllersListTicketsResponse":   "ListTicketsResponse",
	"ControllersTicketResponse":        "TicketResponse",
	"ControllersTicketFileResponse":    "TicketFileResponse",
	"ControllersCreateTicketRequest":   "CreateTicketRequest",
	"ControllersCreateTicketResponse":  "CreateTicketResponse",
	"ControllersSaveTicketFileRequest": "SaveTicketFileRequest",
	"ControllersPlanTicketRequest":     "PlanTicketRequest",
	"ControllersAssignPlanRequest":     "AssignPlanRequest",
	"ControllersAssignPlanResponse":    "AssignPlanResponse",
	"ControllersReviewPlanRequest":     "ReviewPlanRequest",
	"ControllersReviewPlanResponse":    "ReviewPlanResponse",
	"ControllersMergeReadyRequest":     "MergeReadyRequest",
	"DomainTicketStatus":               "TicketStatus",
	"DomainPlanStatus":                 "PlanStatus",
	"DomainTicketDefaults":             "TicketDefaults",
	"DomainTicketRoleDefaults":         "TicketRoleDefaults",
```

`ProjectConfig` is already reflected (`"DomainProjectConfig": "ProjectConfig"`), so the two `Domain…` config entries are needed once `Tickets` exists on it.

- [ ] **Step 7: Regenerate and run everything**

From the repo root:

```bash
npm run api
cd backend && go build ./... && go test ./... && go vet ./... && gofmt -l internal
cd ../frontend && npm run typecheck
```

Expected: all green; `TestRouteSpecParity` and `TestBuild_MatchesEmbedded` pass; `grep -c "Controllers\|Domain" backend/internal/httpd/apispec/openapi.yaml` shows no new unmapped names (if it does, add the mapping and rerun).

- [ ] **Step 8: Commit**

```bash
git add backend/internal/httpd backend/internal/daemon/daemon.go frontend/src/api/schema.ts
git commit -m "feat(tickets): ticket routes, OpenAPI operations and daemon wiring"
```

---

### Task 10: End-to-end test through the real store and manager, plus daemon verification

**Files:**
- Create: `backend/internal/integration/tickets_sqlite_test.go`

**Interfaces:**
- Consumes: `newStack(t)` from `lifecycle_sqlite_test.go:132` (same package `integration`), `ticketsvc.New`, `st.store` (`*sqlite.Store`), `st.sm` (`*sessionsvc.Service`).

- [ ] **Step 1: Write the test**

```go
package integration

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	sessionsvc "github.com/OmarAly92/operator/backend/internal/service/session"
	ticketsvc "github.com/OmarAly92/operator/backend/internal/service/ticket"
)

func gitRepo(t *testing.T) string {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not installed")
	}
	dir := t.TempDir()
	run := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
		cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@x", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@x")
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	run("init", "-q", "-b", "main")
	run("config", "user.name", "t")
	run("config", "user.email", "t@x")
	if err := os.WriteFile(filepath.Join(dir, "README.md"), []byte("hi\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	run("add", "README.md")
	run("commit", "-q", "-m", "init")
	return dir
}

func TestTicketCreatePlanAssignRoundTrip(t *testing.T) {
	ctx := context.Background()
	st := newStack(t)
	repo := gitRepo(t)
	if err := st.store.UpsertProject(ctx, domain.ProjectRecord{
		ID: "tk", Path: repo, Kind: domain.ProjectKindSingleRepo, RegisteredAt: time.Now(),
		Config: domain.ProjectConfig{DefaultBranch: "main", Worker: domain.RoleOverride{Harness: domain.HarnessClaudeCode}},
	}); err != nil {
		t.Fatal(err)
	}
	svc := ticketsvc.New(ticketsvc.Deps{Store: st.store, Sessions: st.sm})

	created, err := svc.Create(ctx, "tk", ticketsvc.CreateInput{Title: "Editor", Brief: "Add an editor"})
	if err != nil {
		t.Fatal(err)
	}
	if created.Ticket.Slug != "editor" || created.Ticket.Status != domain.TicketStatusDraft || len(created.Warnings) != 0 {
		t.Fatalf("created = %+v", created)
	}

	planning, err := svc.Plan(ctx, "tk", "editor", ticketsvc.SpawnInput{Harness: domain.HarnessClaudeCode})
	if err != nil {
		t.Fatal(err)
	}
	got, err := st.sm.Get(ctx, planning.ID)
	if err != nil || got.Ticket == nil || got.Ticket.Role != domain.TicketRolePlanning || got.Ticket.Slug != "editor" {
		t.Fatalf("planning session = %+v err=%v", got.Ticket, err)
	}
	if got.Metadata.WorkspaceMode != domain.WorkspaceModeInPlace {
		t.Fatalf("planning workspace mode = %q", got.Metadata.WorkspaceMode)
	}
	if !strings.Contains(got.Metadata.Prompt, ".operator/tickets/editor/") {
		t.Fatalf("planning prompt = %q", got.Metadata.Prompt)
	}
	tk, err := svc.Get(ctx, "tk", "editor")
	if err != nil || tk.Status != domain.TicketStatusPlanning {
		t.Fatalf("ticket = %+v err=%v", tk, err)
	}
	if _, err := st.sm.Kill(ctx, planning.ID); err != nil {
		t.Fatal(err)
	}

	planDir := filepath.Join(repo, ".operator", "tickets", "editor", "plans")
	if err := os.MkdirAll(planDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(planDir, "01-daemon.md"), []byte("---\ntitle: Daemon\n---\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("git", "-C", repo, "add", "-A")
	cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@x", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@x")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git add: %v %s", err, out)
	}
	cmd = exec.Command("git", "-C", repo, "commit", "-q", "-m", "plan")
	cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@x", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@x")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git commit: %v %s", err, out)
	}

	tk, _ = svc.Get(ctx, "tk", "editor")
	if tk.Status != domain.TicketStatusReady || len(tk.Plans) != 1 || tk.Plans[0].Status != domain.PlanStatusTodo {
		t.Fatalf("ticket after plan file = %+v", tk)
	}

	dry, err := svc.Assign(ctx, "tk", "editor", "01-daemon.md", ticketsvc.AssignInput{DryRun: true})
	if err != nil || len(dry.Warnings) != 0 || dry.Session != nil {
		t.Fatalf("dry = %+v err=%v", dry, err)
	}
	res, err := svc.Assign(ctx, "tk", "editor", "01-daemon.md", ticketsvc.AssignInput{SpawnInput: ticketsvc.SpawnInput{Harness: domain.HarnessClaudeCode, Extra: "Use TDD."}})
	if err != nil || res.Session == nil {
		t.Fatalf("assign = %+v err=%v", res, err)
	}
	impl, err := st.sm.Get(ctx, res.Session.ID)
	if err != nil {
		t.Fatal(err)
	}
	if impl.Metadata.Branch != "opr/editor-01" || impl.Metadata.WorkspaceMode != domain.WorkspaceModeWorktree {
		t.Fatalf("impl metadata = %+v", impl.Metadata)
	}
	if impl.Ticket == nil || impl.Ticket.Role != domain.TicketRoleImplementing || impl.Ticket.PlanFile != "plans/01-daemon.md" {
		t.Fatalf("impl ticket = %+v", impl.Ticket)
	}
	if !strings.Contains(impl.Metadata.Prompt, "plans/01-daemon.md") || !strings.Contains(impl.Metadata.Prompt, "Use TDD.") {
		t.Fatalf("impl prompt = %q", impl.Metadata.Prompt)
	}
	list, err := st.sm.List(ctx, sessionsvc.ListFilter{ProjectID: "tk"})
	if err != nil || len(list) != 2 {
		t.Fatalf("list = %+v err=%v", list, err)
	}
	tk, _ = svc.Get(ctx, "tk", "editor")
	if tk.Status != domain.TicketStatusInProgress || tk.Plans[0].Status != domain.PlanStatusIdle || tk.Plans[0].SessionID != res.Session.ID {
		t.Fatalf("ticket in progress = %+v", tk)
	}

	if _, err := st.sm.Kill(ctx, res.Session.ID); err != nil {
		t.Fatal(err)
	}
	tk, _ = svc.Get(ctx, "tk", "editor")
	if tk.Plans[0].Status != domain.PlanStatusTerminated || tk.Status != domain.TicketStatusReady {
		t.Fatalf("ticket after kill = %+v", tk)
	}

	res2, err := svc.Assign(ctx, "tk", "editor", "01-daemon.md", ticketsvc.AssignInput{Force: true, SpawnInput: ticketsvc.SpawnInput{Harness: domain.HarnessClaudeCode}})
	if err != nil || res2.Session == nil {
		t.Fatalf("second assign = %+v err=%v", res2, err)
	}
	review, err := svc.Review(ctx, "tk", "editor", "01-daemon.md", ticketsvc.ReviewInput{SpawnInput: ticketsvc.SpawnInput{Harness: domain.HarnessClaudeCode}})
	if err != nil || !review.Spawned {
		t.Fatalf("review = %+v err=%v", review, err)
	}
	reviewer, err := st.sm.Get(ctx, review.Session.ID)
	if err != nil || reviewer.Ticket == nil || reviewer.Ticket.Role != domain.TicketRolePlanning || reviewer.Metadata.WorkspaceMode != domain.WorkspaceModeInPlace {
		t.Fatalf("reviewer = %+v err=%v", reviewer.Ticket, err)
	}
	tk, _ = svc.Get(ctx, "tk", "editor")
	if tk.Plans[0].Status != domain.PlanStatusReviewing || tk.Plans[0].ReviewerID != review.Session.ID {
		t.Fatalf("reviewing = %+v", tk.Plans[0])
	}
	tk, err = svc.MergeReady(ctx, "tk", "editor", "01-daemon.md", "verified")
	if err != nil || tk.Plans[0].Status != domain.PlanStatusAwaitMerge || tk.Status != domain.TicketStatusAwaitMerge {
		t.Fatalf("merge ready = %+v err=%v", tk, err)
	}
	tk, err = svc.ApproveMerge(ctx, "tk", "editor", "01-daemon.md")
	if err != nil || tk.Plans[0].Status != domain.PlanStatusReviewing {
		t.Fatalf("approve = %+v err=%v", tk, err)
	}
	fresh, err := svc.Review(ctx, "tk", "editor", "01-daemon.md", ticketsvc.ReviewInput{Reviewer: ticketsvc.ReviewerNew, SpawnInput: ticketsvc.SpawnInput{Harness: domain.HarnessClaudeCode}})
	if err != nil || !fresh.Spawned || fresh.Session.ID == review.Session.ID {
		t.Fatalf("fresh review = %+v err=%v", fresh, err)
	}
	if got, _ := st.sm.Get(ctx, fresh.Session.ID); got.Ticket == nil || got.Ticket.Role != domain.TicketRoleReviewing {
		t.Fatalf("fresh reviewer ref = %+v", got.Ticket)
	}
	if _, err := st.sm.Kill(ctx, res2.Session.ID); err != nil {
		t.Fatal(err)
	}

	tk, err = svc.MarkDone(ctx, "tk", "editor", "01-daemon.md")
	if err != nil || tk.Status != domain.TicketStatusDone {
		t.Fatalf("done = %+v err=%v", tk, err)
	}
	head, _ := st.store.LatestSeq(ctx)
	events, err := st.store.EventsAfter(ctx, 0, int(head)+1)
	if err != nil {
		t.Fatal(err)
	}
	ticketEvents := 0
	for _, e := range events {
		if string(e.Type) == "ticket_updated" {
			ticketEvents++
		}
	}
	if ticketEvents < 8 {
		t.Fatalf("want ticket_updated for create, plan link, assigns, review, merge-ready, approve and done; got %d in %+v", ticketEvents, events)
	}
}
```

If `Metadata.Prompt` is not populated by `seedRecord` for the stub stack (check `manager.go:2730` and where `Metadata.Prompt` is set), assert on the prompt via the `captureMessenger` (`st.msg.msgs`) instead, which receives the auto-submitted task prompt.

- [ ] **Step 2: Run**

Run: `cd backend && go test ./internal/integration/ -run TestTicketCreatePlanAssignRoundTrip -v`
Expected: PASS. A failure inside `Plan` with `ErrInPlaceUnsupported` means the project row lost its `Kind`; a failure on branch means `cfg.Branch` did not survive `Spawn` — read `manager.go:595-598`.

- [ ] **Step 3: Full gate**

```bash
cd backend && go test ./... && go test -race ./internal/service/ticket/ ./internal/storage/sqlite/... ./internal/httpd/... && go vet ./... && gofmt -l internal
cd .. && npm run lint
```

Expected: green, `gofmt -l` prints nothing, golangci-lint reports no new issues.

- [ ] **Step 4: Verify against a running daemon**

Build and start the daemon with a scrubbed environment (see the memory rule about `CLAUDE*` variables), then, with a registered single-repo project id `<pid>` (from `curl -s localhost:3002/api/v1/projects | jq '.projects[] | {id, kind}'`):

```bash
curl -s -X POST localhost:3002/api/v1/projects/<pid>/tickets -H 'content-type: application/json' -d '{"title":"Smoke ticket","brief":"daemon smoke"}' | jq
curl -s localhost:3002/api/v1/projects/<pid>/tickets | jq '.tickets[] | {slug, status, plans}'
curl -s "localhost:3002/api/v1/projects/<pid>/tickets/smoke-ticket/file?path=spec.md" | jq
curl -s -X PUT "localhost:3002/api/v1/projects/<pid>/tickets/smoke-ticket/file?path=plans/01-first.md" -H 'content-type: application/json' -d '{"content":"---\ntitle: First\n---\n"}' | jq
curl -s -X POST "localhost:3002/api/v1/projects/<pid>/tickets/smoke-ticket/plans/01-first.md/assign?dryRun=1" | jq
curl -s -X POST localhost:3002/api/v1/projects/<pid>/tickets/smoke-ticket/plans/01-first.md/assign -H 'content-type: application/json' -d '{"harness":"fake","force":true}' | jq '.session | {id, ticket, branch}'
curl -s localhost:3002/api/v1/sessions | jq '.sessions[] | select(.ticket != null) | {id, ticket, status}'
curl -s -X POST localhost:3002/api/v1/projects/<pid>/tickets/smoke-ticket/plans/01-first.md/review -H 'content-type: application/json' -d '{"reviewer":"new","harness":"fake"}' | jq '{spawned, id: .session.id, ticket: .session.ticket}'
curl -s -X POST localhost:3002/api/v1/projects/<pid>/tickets/smoke-ticket/plans/01-first.md/merge-ready -H 'content-type: application/json' -d '{"summary":"smoke"}' | jq '.ticket | {status, plans}'
curl -s -X POST localhost:3002/api/v1/projects/<pid>/tickets/smoke-ticket/plans/01-first.md/merge | jq '.ticket.plans[0].status'
curl -s -N localhost:3002/api/v1/projects/<pid>/tickets/events &
touch <project>/.operator/tickets/smoke-ticket/spec.md
```

Expected: the create returns 201 with slug `smoke-ticket`; the dry run reports `ticket_repo_dirty` because the plan file written through the API is uncommitted; the forced assign returns a session whose `ticket` is `{slug: "smoke-ticket", planFile: "plans/01-first.md", role: "implementing"}` and whose branch is `opr/smoke-ticket-01`; the review with `reviewer: new` returns `spawned: true` and a session whose ticket role is `reviewing`; merge-ready flips the ticket to `awaiting_merge` with the plan carrying `mergeSummary: "smoke"`; merge returns the plan as `reviewing`; the SSE stream prints `event: tickets_changed` after the touch. Kill both fake sessions afterwards. Kill the fake session afterwards through `POST /api/v1/sessions/{id}/kill` (check the exact route in `controllers/sessions.go:203-245`) and delete the smoke ticket folder and its commit from the project with `git reset --hard HEAD~1` only if the project is a throwaway; otherwise leave the folder and note it in the report.

- [ ] **Step 5: Commit and write the report**

```bash
git add backend/internal/integration/tickets_sqlite_test.go
git commit -m "test(tickets): end-to-end create, plan, assign and done through real store and manager"
```

Write `docs/superpowers/plans/2026-09-18-planning-tickets-daemon-report.md` with: the commit list, the gate output summary, the curl transcript from Step 4 (trimmed), and anything left out with the reason. Commit it with `docs:`.

---

## Self-review against the spec

- §1.1 layout, ordering, unprefixed plans last with warning, ticket valid with only ticket.md, frontmatter fallback: Task 2.
- §1.2 tables, append-only assignments, latest wins, triggers into change_log: Task 1, Task 3 (`currentAssignments`).
- §1.3 plan and ticket status tables: Task 3, including `exited` folded into `terminated` and `no_signal` into `idle`, which the spec's "otherwise" row covers.
- §2.1 scan on request, single-repo only, two change signals, every route, `path` query, 409 on stale: Tasks 6, 7, 9, and the CDC event in Task 1.
- §2.2 create writes both files, commits, warns off default branch: Task 6.
- §2.3 planning session in place, prompt-only handoff, refuse while active, replace after termination: Tasks 4 and 7.
- §2.4 assign branch naming with attempt suffix, prompt contents, dry run, warnings, force: Tasks 4 and 7; `TICKET_ASSIGN_BLOCKED` carries `warnings` in `details`.
- §2.5 `ticket` on sessions via read-time lookup, including the `reviewing` role: Tasks 1 and 8.
- §2.6 roles and model defaults (`ProjectConfig.Tickets`, `withDefaults`): Tasks 7 and 7b; kickoff files scanned, listed and used as the implementer prompt body: Tasks 2, 4, 7; review by planner (send, or spawn when dead) or by a fresh session, `reviewer_session_id` recorded: Task 7b; auto-review on `pr_created`, once per assignment, project opt-out: Tasks 7b and 7c; merge-ready with summary and the `awaiting_merge` statuses, user confirmation forwarded to the reviewer, dead reviewer replaced: Tasks 3 and 7b; routes and DTOs for all three: Task 9.
- §4 malformed frontmatter warns not drops (Task 2), deleted session leaves rows (schema `ON DELETE SET NULL`, Task 1), deleted folder hides the ticket (Task 6 list iterates scanned folders), non-default branch warnings (Tasks 6 and 7), traversal and symlink rejection (Task 6).
- §5 tests: scanner, status table, prompt, file routes, real-SQLite store, end to end: Tasks 1, 2, 3, 4, 6, 9, 10.
- Deliberately not in this plan: the frontend beyond the one-line `CDC_EVENT_TYPES` addition and regenerated types (plan 2), drag and editor (plan 3), workspace-kind projects (spec §2.1 scopes them out).
