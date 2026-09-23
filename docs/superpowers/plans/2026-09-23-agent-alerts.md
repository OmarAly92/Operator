# Agent Alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Alert the user when an agent finishes a turn, needs input, or exits on its own — as a clickable macOS toast and on the iPhone (ntfy when locked, a local notification when the Operator app is open).

**Architecture:** The daemon's lifecycle reducer emits three session-scoped notification types into the existing notification store; a store dedupe bug that swallows repeat alerts is fixed on the way. A rewritten `internal/push` package replaces the dead Expo dispatcher with an ntfy sender gated on Connect Mobile, a claimed topic and the phone's foreground state. The mux socket gains a `notifications` channel that feeds the phone's local notifications and tells the daemon when the phone app is open. The Tauri shell posts macOS toasts through UNUserNotificationCenter with a click delegate; the renderer decides whether to toast from the split-view visibility it already tracks.

**Tech Stack:** Go 1.x daemon (chi, sqlc, goose, SQLite), Tauri 2 + Rust (`objc2` 0.6.4, `objc2-user-notifications` 0.3.2, `block2` 0.6.2), React 19 + Vitest, Flutter 3.44.5 (`flutter_local_notifications` 22.3.0, `url_launcher`), ntfy.sh.

**Spec:** `docs/superpowers/specs/2026-09-23-agent-alerts-design.md` — read it end to end before Task 1; this plan argues from it.

## Global Constraints

- Work in a git worktree off `development`, never in the shared checkout: `git worktree add ../Operator-agent-alerts -b agent-alerts development`. Never `git stash` in `/Users/omaraly/development/AI/Operator` (other sessions commit there).
- Do not add code comments in new or changed code (user rule). Existing comments stay unless the code they describe is deleted.
- New notification types are exactly `turn_finished` and `agent_exited`. Session-scoped types are `needs_input`, `turn_finished`, `agent_exited`.
- Quiet window: input to the session's terminal within the last **3 s** before the event.
- ntfy: server `https://ntfy.sh`, topic 32 characters from `[A-Za-z0-9]`, per-session coalescing **10 s**, request timeout **5 s**, one retry after **2 s**.
- ntfy payload carries only the session display name and the event word. Never assistant text, terminal output, PR titles or file paths.
- Mobile deep-link scheme becomes `operator`. Tap target for a session alert: `operator://session/<sessionId>`.
- Phone alert routes live under `/api/v1/phone-alerts` (the LAN listener 404s `/api/v1/mobile`).
- Gates per area: `cd backend && go build ./... && go test -race ./...`; `cd frontend && npm run typecheck && npx vitest run <touched tests>`; `cd frontend/src-tauri && cargo test`; `cd packages/mobile && flutter analyze && flutter test`.
- Regenerate after touching SQL: `npm run sqlc` (repo root). After touching API DTOs or routes: `npm run api` (repo root). Commit generated files.
- Before running Operator dev from a Claude session, scrub `CLAUDE*` env vars (see `RUN_APP_COMMANDS.md`); verify the renderer against an isolated daemon, not the user's.

## Review Focus

1. **A second alert for the same session.** Two turns finish in a row without the bell panel ever being opened. Expected: two toasts and two ntfy messages (unless coalesced within 10 s). Test pinned in Task 1 (store) and Task 2 (lifecycle emits on the second transition).
2. **Kill racing the process watcher.** User clicks Kill; the reaper sees the agent process dead before `MarkTerminated`. Expected: no "exited" alert. Test pinned in Task 2.
3. **Daemon restart with the phone paired.** Restarting the daemon must not rotate the topic or unclaim it; the phone keeps receiving alerts without re-subscribing. Test pinned in Task 5.
4. **Phone app open while a session finishes.** Expected: exactly one notification on the phone (local), no ntfy duplicate; after backgrounding, the next alert goes through ntfy. Tests pinned in Task 4 (daemon side) and Task 10 (client side).
5. **Window focused on a different session in another split pane.** Expected: toast for the session that is not visible, none for the one that is. Test pinned in Task 8.

---

### Task 0: Step 0 — device checks (no product code)

Results are written into §3 of the spec before Task 1. Any failed check changes the plan as stated there.

**Files:**
- Modify: `docs/superpowers/specs/2026-09-23-agent-alerts-design.md` (§3, results)
- Scratch only: `$SCRATCH/unprobe/` (the session scratchpad; never commit)

- [ ] **Step 1: Build an ad-hoc signed UNUserNotificationCenter probe app**

```bash
SCRATCH="${TMPDIR%/}/unprobe"; mkdir -p "$SCRATCH/UNProbe.app/Contents/MacOS"
cat > "$SCRATCH/main.swift" <<'EOF'
import Cocoa
import UserNotifications

final class Delegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/UNProbe.log")
  func record(_ line: String) {
    let data = (line + "\n").data(using: .utf8)!
    if let handle = try? FileHandle(forWritingTo: logURL) { handle.seekToEndOfFile(); handle.write(data); try? handle.close() }
    else { try? data.write(to: logURL) }
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      self.record("auth granted=\(granted) error=\(String(describing: error))")
      let content = UNMutableNotificationContent()
      content.title = "UN probe"
      content.body = "Click me"
      content.sound = .default
      center.add(UNNotificationRequest(identifier: "probe-1", content: content, trigger: nil)) { error in
        self.record("add error=\(String(describing: error))")
      }
    }
  }
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .sound, .list])
  }
  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    record("clicked id=\(response.notification.request.identifier)")
    completionHandler()
  }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.run()
EOF
cat > "$SCRATCH/UNProbe.app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.operator.unprobe</string>
<key>CFBundleExecutable</key><string>UNProbe</string>
<key>CFBundleName</key><string>UNProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
</dict></plist>
EOF
swiftc -o "$SCRATCH/UNProbe.app/Contents/MacOS/UNProbe" "$SCRATCH/main.swift"
codesign -s - --force --deep "$SCRATCH/UNProbe.app"
codesign -dv "$SCRATCH/UNProbe.app" 2>&1 | grep -E "Signature|TeamIdentifier"
rm -rf /Applications/UNProbe.app && cp -R "$SCRATCH/UNProbe.app" /Applications/
open /Applications/UNProbe.app
```

Expected: `Signature=adhoc`, `TeamIdentifier=not set` (same signing as the installed Operator.app).

- [ ] **Step 2: Ask the user to allow the prompt and click the banner, then read the log**

Tell the user: "A test app called UNProbe will ask to send notifications. Please click Allow, then click the 'UN probe' banner." Then:

```bash
cat ~/Library/Logs/UNProbe.log
```

Expected for success: `auth granted=true error=nil`, `add error=nil`, `clicked id=probe-1`. If `granted=false` or an error appears, record it verbatim: Task 7 uses approach B (spec D7) instead.

Clean up: `osascript -e 'quit app "UNProbe"'; rm -rf /Applications/UNProbe.app ~/Library/Logs/UNProbe.log`.

- [ ] **Step 3: Check whether Esc fires Claude's Stop hook**

With the installed Operator running (daemon on port 3001), ask the user to open a session, send "count slowly from 1 to 200, one number per line", and press Esc after a few lines. Meanwhile:

```bash
curl -sN http://127.0.0.1:3001/api/v1/events | grep --line-buffered session_updated
```

Record whether a `session_updated` event with `"activity":"idle"` arrives within 2 s of the Esc. Either outcome keeps the 3-second rule; record which one holds.

- [ ] **Step 4: ntfy on the user's iPhone**

Generate a throwaway topic and ask the user to install ntfy (https://apps.apple.com/us/app/ntfy/id1625396347) and note whether it is free.

```bash
TOPIC="opr-probe-$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"; echo "$TOPIC"
```

Ask the user to (a) open `ntfy://ntfy.sh/$TOPIC` from Safari on the phone and report whether ntfy opens a subscribe screen; if not, subscribe manually with "+" and the topic name. Then:

```bash
curl -s -H "Title: operator-4 finished" -H "Tags: white_check_mark" -H "Click: aomobile://session/operator-4" -d "finished" "https://ntfy.sh/$TOPIC"
```

Ask the user to lock the phone first. Record: arrived on the lock screen (yes/no, seconds), tapping it opened Operator on the session (yes/no). The scheme is still `aomobile` until Task 9; the check is whether ntfy honors a custom-scheme `Click`.

- [ ] **Step 5: ntfy.sh rate behavior**

```bash
for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code}\n" -d "burst $i" "https://ntfy.sh/$TOPIC"; done | sort | uniq -c
```

Record the status counts. Any `429` goes into the spec.

- [ ] **Step 6: Record results and commit**

Replace the numbered list in spec §3 with the same list plus a `**Result (date):** …` line under each item, quoting log lines and status counts.

```bash
git add docs/superpowers/specs/2026-09-23-agent-alerts-design.md
git commit -m "docs: agent alerts step 0 results"
```

---

### Task 1: Notification types, quiet flag, and the dedupe fix

**Files:**
- Modify: `backend/internal/domain/notification.go`
- Modify: `backend/internal/ports/notifications.go:12-27`
- Modify: `backend/internal/notify/enrich.go`
- Create: `backend/internal/storage/sqlite/migrations/0117_notification_alerts.sql`
- Modify: `backend/internal/storage/sqlite/queries/notifications.sql`
- Modify: `backend/internal/storage/sqlite/store/notification_store.go`
- Regenerate: `backend/internal/storage/sqlite/gen/*` (`npm run sqlc`)
- Modify: `backend/internal/httpd/controllers/dto.go:1136-1151`, `backend/internal/httpd/controllers/notifications.go:211-245`
- Regenerate: `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts` (`npm run api`)
- Test: `backend/internal/domain/notification_test.go` (create if absent), `backend/internal/notify/enrich_test.go`, `backend/internal/storage/sqlite/store/notification_store_test.go`

**Interfaces:**
- Produces: `domain.NotificationTurnFinished`, `domain.NotificationAgentExited`, `func (t NotificationType) SessionScoped() bool`, `NotificationRecord.Quiet bool`, `ports.NotificationIntent.Quiet bool`, `ports.NotificationIntent.AssistantUpdate string`, wire field `quiet` on `NotificationResponse`.

- [ ] **Step 1: Write failing domain and enrich tests**

`backend/internal/domain/notification_test.go`:

```go
package domain

import "testing"

func TestNotificationTypeClassification(t *testing.T) {
	for _, tc := range []struct {
		typ             NotificationType
		valid, resolves bool
		sessionScoped   bool
	}{
		{NotificationNeedsInput, true, true, true},
		{NotificationTurnFinished, true, true, true},
		{NotificationAgentExited, true, true, true},
		{NotificationReadyToMerge, true, true, false},
		{NotificationPRMerged, true, false, false},
		{NotificationPRClosedUnmerged, true, false, false},
		{"bogus", false, false, false},
	} {
		if got := tc.typ.Valid(); got != tc.valid {
			t.Errorf("%s Valid = %v, want %v", tc.typ, got, tc.valid)
		}
		if got := tc.typ.NeedsResolution(); got != tc.resolves {
			t.Errorf("%s NeedsResolution = %v, want %v", tc.typ, got, tc.resolves)
		}
		if got := tc.typ.SessionScoped(); got != tc.sessionScoped {
			t.Errorf("%s SessionScoped = %v, want %v", tc.typ, got, tc.sessionScoped)
		}
	}
}
```

Append to `backend/internal/notify/enrich_test.go` (package `notify`):

```go
func TestEnrichTurnFinished(t *testing.T) {
	at := time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC)
	long := strings.Repeat("a", 200)
	rec, err := enrich(Intent{Type: domain.NotificationTurnFinished, SessionID: "operator-4", ProjectID: "operator", CreatedAt: at, SessionDisplayName: "split close fix", AssistantUpdate: "  " + long + "  ", Quiet: true})
	if err != nil {
		t.Fatal(err)
	}
	if rec.Title != "split close fix finished" {
		t.Fatalf("title = %q", rec.Title)
	}
	if len([]rune(rec.Body)) != 121 || !strings.HasSuffix(rec.Body, "…") {
		t.Fatalf("body = %q (%d runes)", rec.Body, len([]rune(rec.Body)))
	}
	if !rec.Quiet {
		t.Fatal("quiet was not carried")
	}
}

func TestEnrichTurnFinishedWithoutAssistantText(t *testing.T) {
	rec, err := enrich(Intent{Type: domain.NotificationTurnFinished, SessionID: "s", ProjectID: "p", CreatedAt: time.Now()})
	if err != nil {
		t.Fatal(err)
	}
	if rec.Body != "Your agent finished its turn." {
		t.Fatalf("body = %q", rec.Body)
	}
}

func TestEnrichAgentExited(t *testing.T) {
	rec, err := enrich(Intent{Type: domain.NotificationAgentExited, SessionID: "s", ProjectID: "p", CreatedAt: time.Now(), SessionDisplayName: "checkout"})
	if err != nil {
		t.Fatal(err)
	}
	if rec.Title != "checkout exited" || rec.Body != "The agent process ended. Relaunch it from the session." {
		t.Fatalf("rec = %+v", rec)
	}
}
```

Add `"strings"` to that file's imports if missing.

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && go test ./internal/domain/ ./internal/notify/ -run 'TestNotificationTypeClassification|TestEnrich(TurnFinished|AgentExited)' -v`
Expected: compile errors (`NotificationTurnFinished`, `SessionScoped`, `AssistantUpdate`, `Quiet` undefined).

- [ ] **Step 3: Implement domain, ports and enrich**

In `backend/internal/domain/notification.go`, extend the const block, `Valid`, `NeedsResolution`, add `SessionScoped`, and add `Quiet` to the record:

```go
	NotificationPRClosedUnmerged NotificationType = "pr_closed_unmerged"
	NotificationTurnFinished     NotificationType = "turn_finished"
	NotificationAgentExited      NotificationType = "agent_exited"
)

func (t NotificationType) Valid() bool {
	switch t {
	case NotificationNeedsInput, NotificationReadyToMerge, NotificationPRMerged, NotificationPRClosedUnmerged,
		NotificationTurnFinished, NotificationAgentExited:
		return true
	default:
		return false
	}
}

func (t NotificationType) NeedsResolution() bool {
	switch t {
	case NotificationNeedsInput, NotificationReadyToMerge, NotificationTurnFinished, NotificationAgentExited:
		return true
	default:
		return false
	}
}

func (t NotificationType) SessionScoped() bool {
	return t == NotificationNeedsInput || t == NotificationTurnFinished || t == NotificationAgentExited
}
```

Add to `NotificationRecord` after `ResolvedAt`:

```go
	Quiet bool
```

In `backend/internal/ports/notifications.go`, add to `NotificationIntent` after `CreatedAt`:

```go
	Quiet           bool
	AssistantUpdate string
```

In `backend/internal/notify/enrich.go`:

```go
const turnSummaryRunes = 120

func enrich(intent Intent) (domain.NotificationRecord, error) {
	rec := domain.NotificationRecord{
		SessionID: intent.SessionID,
		ProjectID: intent.ProjectID,
		PRURL:     strings.TrimSpace(intent.PRURL),
		Type:      intent.Type,
		Status:    domain.NotificationUnread,
		CreatedAt: intent.CreatedAt,
		Quiet:     intent.Quiet,
	}
	if !intent.Type.Valid() {
		return domain.NotificationRecord{}, domain.ErrInvalidNotificationType
	}
	if !intent.Type.SessionScoped() && rec.PRURL == "" {
		return domain.NotificationRecord{}, domain.ErrInvalidNotificationRecord
	}
	rec.Title = titleForIntent(intent)
	rec.Body = bodyForIntent(intent)
	if err := rec.Validate(); err != nil {
		return domain.NotificationRecord{}, err
	}
	return rec, nil
}
```

Add cases to `titleForIntent`:

```go
	case domain.NotificationTurnFinished:
		return fmt.Sprintf("%s finished", sessionLabel(intent))
	case domain.NotificationAgentExited:
		return fmt.Sprintf("%s exited", sessionLabel(intent))
```

Add cases to `bodyForIntent`:

```go
	case domain.NotificationTurnFinished:
		if summary := summarize(intent.AssistantUpdate, turnSummaryRunes); summary != "" {
			return summary
		}
		return "Your agent finished its turn."
	case domain.NotificationAgentExited:
		return "The agent process ended. Relaunch it from the session."
```

And the helper:

```go
func summarize(text string, limit int) string {
	text = strings.Join(strings.Fields(text), " ")
	runes := []rune(text)
	if len(runes) <= limit {
		return text
	}
	return string(runes[:limit]) + "…"
}
```

- [ ] **Step 4: Run to verify the domain/enrich tests pass**

Run: `cd backend && go test ./internal/domain/ ./internal/notify/ -v -run 'TestNotificationTypeClassification|TestEnrich'`
Expected: PASS.

- [ ] **Step 5: Write failing store tests**

Append to `backend/internal/storage/sqlite/store/notification_store_test.go`:

```go
func TestNotificationStore_ResolvedButUnreadDoesNotBlockTheNextAlert(t *testing.T) {
	for _, typ := range []domain.NotificationType{domain.NotificationNeedsInput, domain.NotificationTurnFinished, domain.NotificationAgentExited} {
		t.Run(string(typ), func(t *testing.T) {
			s := newTestStore(t)
			ctx := context.Background()
			seedProject(t, s, "mer")
			sess, err := s.CreateSession(ctx, sampleRecord("mer"))
			if err != nil {
				t.Fatal(err)
			}
			now := time.Now().UTC().Truncate(time.Second)
			first := domain.NotificationRecord{ID: "ntf_1", SessionID: sess.ID, ProjectID: sess.ProjectID, Type: typ, Title: "x", Status: domain.NotificationUnread, CreatedAt: now}
			if _, inserted, err := s.CreateNotification(ctx, first); err != nil || !inserted {
				t.Fatalf("first inserted=%v err=%v", inserted, err)
			}
			second := first
			second.ID = "ntf_2"
			second.CreatedAt = now.Add(time.Minute)
			if _, inserted, err := s.CreateNotification(ctx, second); err != nil || inserted {
				t.Fatalf("while unresolved inserted=%v err=%v, want false", inserted, err)
			}
			if _, err := s.ResolveSessionNotifications(ctx, sess.ID, typ, now.Add(2*time.Minute)); err != nil {
				t.Fatal(err)
			}
			if _, inserted, err := s.CreateNotification(ctx, second); err != nil || !inserted {
				t.Fatalf("after resolve, still unread: inserted=%v err=%v, want true", inserted, err)
			}
		})
	}
}

func TestNotificationStore_UnreadMergeStillBlocksADuplicate(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "mer")
	sess, _ := s.CreateSession(ctx, sampleRecord("mer"))
	rec := domain.NotificationRecord{ID: "ntf_1", SessionID: sess.ID, ProjectID: sess.ProjectID, PRURL: "https://github.com/o/r/pull/1", Type: domain.NotificationPRMerged, Title: "PR #1 merged", Status: domain.NotificationUnread, CreatedAt: time.Now()}
	if _, inserted, err := s.CreateNotification(ctx, rec); err != nil || !inserted {
		t.Fatalf("inserted=%v err=%v", inserted, err)
	}
	dup := rec
	dup.ID = "ntf_2"
	if _, inserted, err := s.CreateNotification(ctx, dup); err != nil || inserted {
		t.Fatalf("duplicate merge inserted=%v err=%v, want false", inserted, err)
	}
}

func TestNotificationStore_QuietRoundTrips(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "mer")
	sess, _ := s.CreateSession(ctx, sampleRecord("mer"))
	created, inserted, err := s.CreateNotification(ctx, domain.NotificationRecord{ID: "ntf_q", SessionID: sess.ID, ProjectID: sess.ProjectID, Type: domain.NotificationTurnFinished, Title: "x finished", Status: domain.NotificationUnread, CreatedAt: time.Now(), Quiet: true})
	if err != nil || !inserted || !created.Quiet {
		t.Fatalf("created=%+v inserted=%v err=%v", created, inserted, err)
	}
}

func TestNotificationStore_UnresolvedListIncludesNewSessionTypes(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "mer")
	sess, _ := s.CreateSession(ctx, sampleRecord("mer"))
	for i, typ := range []domain.NotificationType{domain.NotificationTurnFinished, domain.NotificationAgentExited} {
		if _, _, err := s.CreateNotification(ctx, domain.NotificationRecord{ID: fmt.Sprintf("ntf_%d", i), SessionID: sess.ID, ProjectID: sess.ProjectID, Type: typ, Title: "x", Status: domain.NotificationUnread, CreatedAt: time.Now()}); err != nil {
			t.Fatal(err)
		}
	}
	count, err := s.CountUnresolvedNotifications(ctx)
	if err != nil || count != 2 {
		t.Fatalf("unresolved count = %d err=%v, want 2", count, err)
	}
}
```

Add `"fmt"` to the file's imports.

- [ ] **Step 6: Run to verify failure**

Run: `cd backend && go test ./internal/storage/sqlite/store/ -run 'TestNotificationStore_(ResolvedButUnread|UnreadMergeStill|QuietRoundTrips|UnresolvedListIncludes)' -v`
Expected: FAIL — CHECK constraint rejects `turn_finished`, and the resolved-but-unread case returns `inserted=false`.

- [ ] **Step 7: Migration 0117**

Create `backend/internal/storage/sqlite/migrations/0117_notification_alerts.sql`:

```sql
-- +goose Up
-- +goose StatementBegin
CREATE TABLE notifications_next (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    pr_url TEXT NOT NULL DEFAULT '',
    type TEXT NOT NULL CHECK (
        type IN (
            'needs_input',
            'ready_to_merge',
            'pr_merged',
            'pr_closed_unmerged',
            'turn_finished',
            'agent_exited'
        )
    ),
    title TEXT NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'unread' CHECK (status IN ('read', 'unread')),
    created_at TIMESTAMP NOT NULL,
    resolved_at TIMESTAMP,
    quiet BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO notifications_next (id, session_id, project_id, pr_url, type, title, body, status, created_at, resolved_at)
SELECT id, session_id, project_id, pr_url, type, title, body, status, created_at, resolved_at
FROM notifications;

DROP TABLE notifications;
ALTER TABLE notifications_next RENAME TO notifications;

CREATE INDEX idx_notifications_status_history
    ON notifications(status, created_at DESC, id DESC);

CREATE INDEX idx_notifications_history
    ON notifications(created_at DESC, id DESC);

CREATE INDEX idx_notifications_unresolved
    ON notifications(resolved_at, created_at DESC, id DESC);

CREATE UNIQUE INDEX idx_notifications_open_dedupe
    ON notifications(session_id, type, pr_url)
    WHERE resolved_at IS NULL;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
CREATE TABLE notifications_prev (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    pr_url TEXT NOT NULL DEFAULT '',
    type TEXT NOT NULL CHECK (
        type IN (
            'needs_input',
            'ready_to_merge',
            'pr_merged',
            'pr_closed_unmerged'
        )
    ),
    title TEXT NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'unread' CHECK (status IN ('read', 'unread')),
    created_at TIMESTAMP NOT NULL,
    resolved_at TIMESTAMP
);

INSERT INTO notifications_prev (id, session_id, project_id, pr_url, type, title, body, status, created_at, resolved_at)
SELECT id, session_id, project_id, pr_url, type, title, body, status, created_at, resolved_at
FROM notifications
WHERE type IN ('needs_input', 'ready_to_merge', 'pr_merged', 'pr_closed_unmerged');

DROP TABLE notifications;
ALTER TABLE notifications_prev RENAME TO notifications;

CREATE INDEX idx_notifications_status_history
    ON notifications(status, created_at DESC, id DESC);

CREATE INDEX idx_notifications_history
    ON notifications(created_at DESC, id DESC);

CREATE INDEX idx_notifications_unresolved
    ON notifications(resolved_at, created_at DESC, id DESC);

CREATE UNIQUE INDEX idx_notifications_open_dedupe
    ON notifications(session_id, type, pr_url)
    WHERE status = 'unread' OR resolved_at IS NULL;
-- +goose StatementEnd
```

Why `resolved_at IS NULL` alone is enough: `pr_merged` and `pr_closed_unmerged` are never resolved (no code path resolves them; `ResolvePRNotificationsByType` is only called for `ready_to_merge`), so their rows stay `resolved_at IS NULL` and keep blocking duplicates exactly as before. Verify with `grep -rn "NotificationPRMerged\|NotificationPRClosedUnmerged" backend/internal --include='*.go' | grep -i resolv` — expect no hits outside tests.

- [ ] **Step 8: Queries**

In `backend/internal/storage/sqlite/queries/notifications.sql`:

```sql
-- name: CreateNotification :one
INSERT INTO notifications (
    id, session_id, project_id, pr_url, type, title, body, status, created_at, quiet
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
RETURNING *;
```

In `ListUnresolvedNotificationsPage` and `CountUnresolvedNotifications`, replace `AND type IN ('needs_input', 'ready_to_merge')` with:

```sql
  AND type IN ('needs_input', 'ready_to_merge', 'turn_finished', 'agent_exited')
```

Replace `GetOpenNotificationByDedupe`'s last condition:

```sql
-- name: GetOpenNotificationByDedupe :one
SELECT *
FROM notifications
WHERE session_id = ?
  AND type = ?
  AND pr_url = ?
  AND resolved_at IS NULL
LIMIT 1;
```

Append:

```sql
-- name: ResolveStaleTurnFinishedNotifications :many
UPDATE notifications
SET resolved_at = sqlc.arg(resolved_at)
WHERE type = 'turn_finished'
  AND resolved_at IS NULL
  AND session_id IN (
    SELECT id FROM sessions
    WHERE is_terminated = TRUE
       OR activity_state <> 'idle'
  )
RETURNING *;

-- name: ResolveStaleAgentExitedNotifications :many
UPDATE notifications
SET resolved_at = sqlc.arg(resolved_at)
WHERE type = 'agent_exited'
  AND resolved_at IS NULL
  AND session_id IN (
    SELECT id FROM sessions
    WHERE is_terminated = TRUE
       OR activity_state <> 'exited'
  )
RETURNING *;
```

Run: `npm run sqlc` (repo root). Expected: `gen/notifications.sql.go` and `gen/models.go` gain `Quiet bool` and the two new methods.

- [ ] **Step 9: Store mapping and reconcile**

In `notification_store.go`, pass `Quiet: rec.Quiet` in `CreateNotification`'s `gen.CreateNotificationParams`, map `Quiet: row.Quiet` in `notificationFromGen`, and extend `ReconcileResolvedNotifications` after the needs-input query:

```go
	turnFinished, err := s.qw.ResolveStaleTurnFinishedNotifications(ctx, nullTime(at))
	if err != nil {
		return nil, fmt.Errorf("reconcile turn-finished notifications: %w", err)
	}
	resolved = append(resolved, notificationsFromGen(turnFinished)...)
	agentExited, err := s.qw.ResolveStaleAgentExitedNotifications(ctx, nullTime(at))
	if err != nil {
		return nil, fmt.Errorf("reconcile agent-exited notifications: %w", err)
	}
	resolved = append(resolved, notificationsFromGen(agentExited)...)
```

Update the doc comment of `CreateNotification` (lines 17-20) so it no longer says "unseen or still unresolved": it now reads "open meaning still unresolved".

- [ ] **Step 10: Wire DTO**

In `controllers/dto.go` `NotificationResponse`, change the `Type` tag enum and add `Quiet`:

```go
	Type      string    `json:"type" enum:"needs_input,ready_to_merge,pr_merged,pr_closed_unmerged,turn_finished,agent_exited"`
```

```go
	Quiet      bool               `json:"quiet"`
```

In `controllers/notifications.go`, set `Quiet: n.Quiet,` in `notificationResponse` and `Quiet: rec.Quiet,` in `notificationResponseFromRecord`.

Run: `npm run api` (repo root).

- [ ] **Step 11: Run everything**

Run: `cd backend && go build ./... && go test -race ./internal/domain/ ./internal/notify/ ./internal/storage/... ./internal/httpd/...`
Expected: PASS. If `TestNotificationStore_InsertListAndDedupe` or `TestNotificationStore_ResolutionNotReadReopensDedupe` fail, read them: both must still pass unchanged (both exercise an unresolved row).

- [ ] **Step 12: Commit**

```bash
git add backend/internal/domain backend/internal/ports/notifications.go backend/internal/notify backend/internal/storage backend/internal/httpd frontend/src/api/schema.ts
git commit -m "feat(notify): turn_finished and agent_exited types, quiet flag, dedupe on unresolved only"
```

---

### Task 2: Lifecycle emits turn_finished and agent_exited

**Files:**
- Modify: `backend/internal/lifecycle/manager.go` (ApplyActivitySignal ~`:640-690`, ApplyRuntimeObservation `:413-470`, `mutate` `:365-390`, `needsInputResolutions` `:392-408`)
- Test: `backend/internal/lifecycle/manager_test.go`, `backend/internal/lifecycle/alerts_test.go` (create)

**Interfaces:**
- Consumes: Task 1 types and `NotificationIntent.AssistantUpdate`.
- Produces: `func (m *Manager) sessionIntent(typ domain.NotificationType, rec domain.SessionRecord) *ports.NotificationIntent` and `func sessionResolutions(prev, next domain.SessionRecord, now time.Time) []ports.NotificationResolution`. Task 3 extends `sessionIntent`.

- [ ] **Step 1: Write failing tests**

Create `backend/internal/lifecycle/alerts_test.go`:

```go
package lifecycle

import (
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func intentsOf(sink *fakeNotificationSink, typ domain.NotificationType) []ports.NotificationIntent {
	var out []ports.NotificationIntent
	for _, in := range sink.intents {
		if in.Type == typ {
			out = append(out, in)
		}
	}
	return out
}

func resolutionsOf(sink *fakeNotificationSink, typ domain.NotificationType) []ports.NotificationResolution {
	var out []ports.NotificationResolution
	for _, r := range sink.resolutions {
		if r.Type == typ {
			out = append(out, r)
		}
	}
	return out
}

func alertManager(t *testing.T, state domain.ActivityState) (*Manager, *fakeStore, *fakeNotificationSink, time.Time) {
	t.Helper()
	st := newFakeStore()
	sink := &fakeNotificationSink{}
	m := New(st, nil, WithNotificationSink(sink))
	now := time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC)
	m.clock = func() time.Time { return now }
	st.sessions["mer-1"] = domain.SessionRecord{
		ID: "mer-1", ProjectID: "mer", DisplayName: "split fix",
		Activity:      domain.Activity{State: state, LastActivityAt: now.Add(-time.Minute)},
		FirstSignalAt: now.Add(-time.Hour),
		Metadata:      domain.SessionMetadata{RuntimeHandleID: "mer-1"},
	}
	return m, st, sink, now
}

func TestAlerts_ActiveToIdleEmitsTurnFinishedWithAssistantText(t *testing.T) {
	m, _, sink, _ := alertManager(t, domain.ActivityActive)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop", LatestAssistantUpdate: "All 42 tests pass."}); err != nil {
		t.Fatal(err)
	}
	got := intentsOf(sink, domain.NotificationTurnFinished)
	if len(got) != 1 || got[0].SessionID != "mer-1" || got[0].SessionDisplayName != "split fix" || got[0].AssistantUpdate != "All 42 tests pass." {
		t.Fatalf("turn_finished intents = %+v", got)
	}
}

func TestAlerts_SecondTurnEmitsAgain(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityActive)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}
	m.clock = func() time.Time { return now.Add(time.Minute) }
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit"}); err != nil {
		t.Fatal(err)
	}
	if got := resolutionsOf(sink, domain.NotificationTurnFinished); len(got) != 1 || got[0].SessionID != "mer-1" {
		t.Fatalf("turn_finished resolutions = %+v", got)
	}
	m.clock = func() time.Time { return now.Add(2 * time.Minute) }
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationTurnFinished); len(got) != 2 {
		t.Fatalf("turn_finished intents = %d, want 2 (session %+v)", len(got), st.sessions["mer-1"])
	}
}

func TestAlerts_NoTurnFinishedFromNonActiveStates(t *testing.T) {
	for _, from := range []domain.ActivityState{domain.ActivityIdle, domain.ActivityWaitingInput, domain.ActivityBlocked} {
		t.Run(string(from), func(t *testing.T) {
			m, _, sink, _ := alertManager(t, from)
			if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle}); err != nil {
				t.Fatal(err)
			}
			if got := intentsOf(sink, domain.NotificationTurnFinished); len(got) != 0 {
				t.Fatalf("turn_finished from %s = %+v, want none", from, got)
			}
		})
	}
}

func TestAlerts_NoTurnFinishedDuringAgentOperation(t *testing.T) {
	m, _, sink, _ := alertManager(t, domain.ActivityActive)
	m.SetSessionOperationGate(fixedSessionOperationGate(true))
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationTurnFinished); len(got) != 0 {
		t.Fatalf("intents = %+v, want none while an agent operation holds the session", got)
	}
}

func TestAlerts_SessionEndHookEmitsAgentExited(t *testing.T) {
	m, _, sink, _ := alertManager(t, domain.ActivityIdle)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityExited, Event: "session-end"}); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 1 {
		t.Fatalf("agent_exited intents = %+v, want 1", got)
	}
}

func TestAlerts_SessionEndDuringKillIsSilent(t *testing.T) {
	m, _, sink, _ := alertManager(t, domain.ActivityIdle)
	m.SetSessionOperationGate(fixedSessionOperationGate(true))
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityExited, Event: "session-end"}); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 0 {
		t.Fatalf("intents = %+v, want none", got)
	}
}

func TestAlerts_WorkloadDeathEmitsAgentExited(t *testing.T) {
	m, st, sink, _ := alertManager(t, domain.ActivityActive)
	rec := st.sessions["mer-1"]
	rec.Metadata.RuntimeLaunchID = "launch-1"
	st.sessions["mer-1"] = rec
	if err := m.ApplyRuntimeObservation(ctx, "mer-1", ports.RuntimeFacts{Runtime: ports.ProbeAlive, Workload: ports.ProbeDead, LaunchID: "launch-1"}); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 1 {
		t.Fatalf("agent_exited intents = %+v, want 1", got)
	}
}

func TestAlerts_WorkloadDeathDuringKillIsSilent(t *testing.T) {
	m, st, sink, _ := alertManager(t, domain.ActivityActive)
	m.SetSessionOperationGate(fixedSessionOperationGate(true))
	rec := st.sessions["mer-1"]
	rec.Metadata.RuntimeLaunchID = "launch-1"
	st.sessions["mer-1"] = rec
	if err := m.ApplyRuntimeObservation(ctx, "mer-1", ports.RuntimeFacts{Runtime: ports.ProbeAlive, Workload: ports.ProbeDead, LaunchID: "launch-1"}); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityExited {
		t.Fatalf("state = %s, want exited (the fact is still recorded)", got)
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 0 {
		t.Fatalf("intents = %+v, want none", got)
	}
}

func TestAlerts_RuntimeDeathTerminatesWithoutAlert(t *testing.T) {
	m, st, sink, _ := alertManager(t, domain.ActivityActive)
	rec := st.sessions["mer-1"]
	rec.Activity.LastActivityAt = time.Now().Add(-2 * time.Minute)
	st.sessions["mer-1"] = rec
	m.clock = time.Now
	if err := m.ApplyRuntimeObservation(ctx, "mer-1", ports.RuntimeFacts{Runtime: ports.ProbeDead, Workload: ports.ProbeFailed}); err != nil {
		t.Fatal(err)
	}
	if !st.sessions["mer-1"].IsTerminated {
		t.Fatalf("session not terminated: %+v", st.sessions["mer-1"])
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 0 {
		t.Fatalf("intents = %+v, want none for whole-runtime death", got)
	}
}

func TestAlerts_MarkTerminatedResolvesEverySessionAlert(t *testing.T) {
	m, _, sink, _ := alertManager(t, domain.ActivityExited)
	if err := m.MarkTerminated(ctx, "mer-1"); err != nil {
		t.Fatal(err)
	}
	for _, typ := range []domain.NotificationType{domain.NotificationTurnFinished, domain.NotificationAgentExited} {
		if got := resolutionsOf(sink, typ); len(got) != 1 {
			t.Fatalf("%s resolutions = %+v, want 1", typ, got)
		}
	}
	if got := intentsOf(sink, domain.NotificationAgentExited); len(got) != 0 {
		t.Fatalf("MarkTerminated emitted %+v", got)
	}
}

func TestAlerts_LeavingExitedResolvesAgentExited(t *testing.T) {
	m, _, sink, _ := alertManager(t, domain.ActivityExited)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit"}); err != nil {
		t.Fatal(err)
	}
	if got := resolutionsOf(sink, domain.NotificationAgentExited); len(got) != 1 {
		t.Fatalf("agent_exited resolutions = %+v, want 1", got)
	}
}
```

The `TestAlerts_RuntimeDeathTerminatesWithoutAlert` facts mirror `TestRuntimeObservation_ConfirmedDeathIsSuppressedDuringSessionMutation` (`manager_test.go:584`); if `runtimeClearlyDead` needs a different window, copy the facts from `TestRuntimeObservation_ConfirmedRuntimeDeathTerminates` (`manager_test.go:324`) instead.

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && go test ./internal/lifecycle/ -run TestAlerts -v`
Expected: FAIL — no turn_finished/agent_exited intents.

- [ ] **Step 3: Implement**

In `manager.go`, replace `needsInputResolutions`' single call sites with a combined helper and add the intent builder:

```go
func sessionResolutions(prev, next domain.SessionRecord, now time.Time) []ports.NotificationResolution {
	out := needsInputResolutions(prev, next, now)
	if next.IsTerminated || (prev.Activity.State != domain.ActivityActive && next.Activity.State == domain.ActivityActive) {
		out = append(out, ports.NotificationResolution{Type: domain.NotificationTurnFinished, SessionID: next.ID, ResolvedAt: now})
	}
	if next.IsTerminated || (prev.Activity.State == domain.ActivityExited && next.Activity.State != domain.ActivityExited) {
		out = append(out, ports.NotificationResolution{Type: domain.NotificationAgentExited, SessionID: next.ID, ResolvedAt: now})
	}
	return out
}

func (m *Manager) sessionIntent(typ domain.NotificationType, rec domain.SessionRecord) *ports.NotificationIntent {
	intent := &ports.NotificationIntent{
		Type:               typ,
		SessionID:          rec.ID,
		ProjectID:          rec.ProjectID,
		CreatedAt:          rec.Activity.LastActivityAt,
		SessionDisplayName: rec.DisplayName,
	}
	if typ == domain.NotificationTurnFinished {
		intent.AssistantUpdate = rec.Metadata.LatestAssistantUpdate
	}
	return intent
}
```

In `mutate` (`:388`): `m.resolveNotifications(ctx, sessionResolutions(rec, next, now)...)`.

In `ApplyActivitySignal`, replace the needs-input intent block and the resolutions line (`:654-668`) with:

```go
	gated := m.sessionMutationInProgress(id)
	switch {
	case !rec.Activity.State.NeedsInput() && next.Activity.State.NeedsInput() && !next.IsTerminated:
		intent = m.sessionIntent(domain.NotificationNeedsInput, next)
	case !gated && rec.Activity.State == domain.ActivityActive && next.Activity.State == domain.ActivityIdle && !next.IsTerminated:
		intent = m.sessionIntent(domain.NotificationTurnFinished, next)
	case !gated && rec.Activity.State != domain.ActivityExited && next.Activity.State == domain.ActivityExited && !next.IsTerminated:
		intent = m.sessionIntent(domain.NotificationAgentExited, next)
	}
	resolutions := sessionResolutions(rec, next, now)
```

Keep the two existing explanatory comments above that block only where they still describe the code (the needs-input one does).

In `ApplyRuntimeObservation`, capture an intent in the first branch and emit it after `mutate` returns:

```go
	var exited *ports.NotificationIntent
	if err := m.mutate(ctx, id, func(cur domain.SessionRecord, now time.Time) (domain.SessionRecord, bool) {
		if cur.IsTerminated || !matchesLaunch(cur) {
			return cur, false
		}
		currentLaunch := cur.Metadata.RuntimeLaunchID
		if currentLaunch != "" && f.Runtime == ports.ProbeAlive && f.Workload == ports.ProbeDead {
			if cur.Activity.State == domain.ActivityExited {
				return cur, false
			}
			next := cur
			next.Activity = domain.Activity{State: domain.ActivityExited, LastActivityAt: timeOr(f.ObservedAt, now)}
			delete(m.flights, id)
			if !m.sessionMutationInProgress(id) {
				exited = m.sessionIntent(domain.NotificationAgentExited, next)
			}
			return next, true
		}
```

(the remaining closure body is unchanged) and change the closing condition:

```go
	}); err != nil || !shouldTerminate {
		if err == nil {
			m.emitNotification(ctx, exited)
		}
		return err
	}
```

- [ ] **Step 4: Fix the two existing tests that count resolutions**

`TestActivity_LeavingNeedsInputResolvesNotification` (`manager_test.go:2650`) and `TestMarkTerminated_ResolvesNeedsInputNotification` (`:2708`) assert `len(sink.resolutions) == 1`; they now also see turn_finished / agent_exited resolutions. Change both to assert on `resolutionsOf(sink, domain.NotificationNeedsInput)` (defined in `alerts_test.go`, same package):

```go
			got := resolutionsOf(sink, domain.NotificationNeedsInput)
			if len(got) != 1 {
				t.Fatalf("needs_input resolutions = %+v, want 1", got)
			}
			if got[0].SessionID != "mer-1" || !got[0].ResolvedAt.Equal(now) {
				t.Fatalf("resolution = %+v", got[0])
			}
```

```go
	if got := resolutionsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("needs_input resolutions = %+v", got)
	}
```

- [ ] **Step 5: Run the lifecycle suite**

Run: `cd backend && go test -race ./internal/lifecycle/...`
Expected: PASS. Any other failure counting `sink.intents` or `sink.resolutions` gets the same `intentsOf`/`resolutionsOf` treatment; do not weaken what it checks.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/lifecycle
git commit -m "feat(lifecycle): alert on finished turns and self-exited agents, never during an agent operation"
```

---

### Task 3: The 3-second "you just typed" rule

**Files:**
- Modify: `backend/internal/terminal/manager.go` (add `LastInputAt`)
- Modify: `backend/internal/lifecycle/manager.go` (recency seam, `sessionIntent`)
- Modify: `backend/internal/daemon/daemon.go` (wire after `startLifecycle`, `:181`)
- Test: `backend/internal/terminal/manager_test.go`, `backend/internal/lifecycle/alerts_test.go`

**Interfaces:**
- Consumes: `sessionIntent` from Task 2.
- Produces: `func (m *terminal.Manager) LastInputAt(terminalID string) time.Time`; `type lifecycle.InputRecency interface{ LastInputAt(terminalID string) time.Time }`; `func (m *lifecycle.Manager) SetInputRecency(r InputRecency)`.

- [ ] **Step 1: Failing tests**

In `backend/internal/terminal/manager_test.go`:

```go
func TestLastInputAtRecordsTheLatestWrite(t *testing.T) {
	pty := newFakePTY()
	mgr := NewManager(&fakeSource{alive: true, spawner: &fakeSpawner{ptys: []*fakePTY{pty}}}, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	if !mgr.LastInputAt("t1").IsZero() {
		t.Fatal("unexpected input time before any write")
	}
	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	recv(t, conn, chTerminal, msgOpened, time.Second)
	before := time.Now()
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgData, Data: base64.StdEncoding.EncodeToString([]byte("x"))}
	eventually(t, time.Second, func() bool { return !mgr.LastInputAt("t1").Before(before) })
}
```

Append to `backend/internal/lifecycle/alerts_test.go`:

```go
type fixedRecency map[string]time.Time

func (f fixedRecency) LastInputAt(id string) time.Time { return f[id] }

func TestAlerts_RecentInputMarksTheAlertQuiet(t *testing.T) {
	for _, tc := range []struct {
		name  string
		ago   time.Duration
		quiet bool
	}{
		{"typed 1s before", time.Second, true},
		{"typed 4s before", 4 * time.Second, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m, _, sink, now := alertManager(t, domain.ActivityActive)
			m.SetInputRecency(fixedRecency{"mer-1": now.Add(-tc.ago)})
			if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
				t.Fatal(err)
			}
			got := intentsOf(sink, domain.NotificationTurnFinished)
			if len(got) != 1 || got[0].Quiet != tc.quiet {
				t.Fatalf("intents = %+v, want one with quiet=%v", got, tc.quiet)
			}
		})
	}
}

func TestAlerts_RecencyFallsBackToSessionIDWithoutHandle(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityActive)
	rec := st.sessions["mer-1"]
	rec.Metadata.RuntimeHandleID = ""
	st.sessions["mer-1"] = rec
	m.SetInputRecency(fixedRecency{"mer-1": now.Add(-time.Second)})
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationTurnFinished); len(got) != 1 || !got[0].Quiet {
		t.Fatalf("intents = %+v", got)
	}
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && go test ./internal/terminal/ ./internal/lifecycle/ -run 'TestLastInputAt|TestAlerts_Recen' -v`
Expected: compile errors.

- [ ] **Step 3: Implement**

`backend/internal/terminal/manager.go`, next to `BeginInputDrain`:

```go
func (m *Manager) LastInputAt(terminalID string) time.Time {
	m.inputMu.Lock()
	defer m.inputMu.Unlock()
	return m.lastInputAt[terminalID]
}
```

`backend/internal/lifecycle/manager.go`:

```go
const quietInputWindow = 3 * time.Second

type InputRecency interface {
	LastInputAt(terminalID string) time.Time
}

func (m *Manager) SetInputRecency(r InputRecency) {
	m.recencyMu.Lock()
	m.recency = r
	m.recencyMu.Unlock()
}

func (m *Manager) typedRecently(rec domain.SessionRecord) bool {
	m.recencyMu.RLock()
	r := m.recency
	m.recencyMu.RUnlock()
	if r == nil {
		return false
	}
	id := rec.Metadata.RuntimeHandleID
	if id == "" {
		id = string(rec.ID)
	}
	last := r.LastInputAt(id)
	return !last.IsZero() && m.clock().Sub(last) < quietInputWindow
}
```

Add to the `Manager` struct: `recencyMu sync.RWMutex` and `recency InputRecency`. In `sessionIntent`, set `Quiet: m.typedRecently(rec),` in the struct literal.

`backend/internal/daemon/daemon.go`, right after `lcStack := startLifecycle(...)`:

```go
	lcStack.LCM.SetInputRecency(termMgr)
```

- [ ] **Step 4: Run**

Run: `cd backend && go build ./... && go test -race ./internal/terminal/ ./internal/lifecycle/ ./internal/daemon/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/terminal backend/internal/lifecycle backend/internal/daemon
git commit -m "feat(lifecycle): alerts caused by the user's own keystroke are quiet"
```

---

### Task 4: `notifications` mux channel and phone presence

**Files:**
- Modify: `backend/internal/terminal/protocol.go`
- Modify: `backend/internal/terminal/manager.go` (Manager fields, `NewManager`, `Close`, `Serve`, `connState`, `handle`, `cleanup`)
- Create: `backend/internal/terminal/notifications.go`
- Modify: `backend/internal/httpd/lan_listener.go:36-45`
- Modify: `backend/internal/daemon/daemon.go` (create `notificationHub` before `termMgr`, pass the option)
- Test: `backend/internal/terminal/notifications_test.go`, `backend/internal/httpd/lan_listener_test.go`

**Interfaces:**
- Consumes: `domain.NotificationEvent`, `notify.Hub.Subscribe`.
- Produces: `terminal.WithNotificationFeed(feed NotificationFeed) Option`, `terminal.WithRemoteOrigin(ctx) context.Context`, `func (m *Manager) PhoneForeground() bool`. Wire frame: client `{"ch":"notifications","type":"subscribe"|"unsubscribe"}`; server `{"ch":"notifications","type":"notification","notification":{id,sessionId,projectId,type,title,body,quiet,createdAt}}`.

- [ ] **Step 1: Failing tests**

Create `backend/internal/terminal/notifications_test.go`:

```go
package terminal

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type fakeFeed struct{ ch chan domain.NotificationEvent }

func newFakeFeed() *fakeFeed { return &fakeFeed{ch: make(chan domain.NotificationEvent, 8)} }

func (f *fakeFeed) Subscribe(domain.ProjectID) (<-chan domain.NotificationEvent, func()) {
	return f.ch, func() {}
}

func created(id string) domain.NotificationEvent {
	return domain.NotificationEvent{Kind: domain.NotificationCreated, Record: domain.NotificationRecord{
		ID: id, SessionID: "mer-1", ProjectID: "mer", Type: domain.NotificationTurnFinished,
		Title: "split fix finished", Body: "done", CreatedAt: time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC),
	}}
}

func serveConn(t *testing.T, mgr *Manager, remote bool) *fakeConn {
	t.Helper()
	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	if remote {
		ctx = WithRemoteOrigin(ctx)
	}
	go mgr.Serve(ctx, conn)
	return conn
}

func TestNotificationsReachOnlySubscribedConnections(t *testing.T) {
	feed := newFakeFeed()
	mgr := NewManager(&fakeSource{}, nil, testLogger(), WithHeartbeat(0), WithNotificationFeed(feed))
	defer mgr.Close()
	subscribed := serveConn(t, mgr, true)
	other := serveConn(t, mgr, true)
	subscribed.in <- clientMsg{Ch: chNotifications, Type: msgSubscribe}
	eventually(t, time.Second, mgr.PhoneForeground)

	feed.ch <- created("ntf_1")
	got := recv(t, subscribed, chNotifications, msgNotification, time.Second)
	if got.Notification == nil || got.Notification.ID != "ntf_1" || got.Notification.SessionID != "mer-1" || got.Notification.Type != "turn_finished" {
		t.Fatalf("frame = %+v", got.Notification)
	}
	select {
	case m := <-other.out:
		if m.Ch == chNotifications {
			t.Fatalf("unsubscribed connection received %+v", m)
		}
	case <-time.After(100 * time.Millisecond):
	}
}

func TestResolvedEventsAreNotForwarded(t *testing.T) {
	feed := newFakeFeed()
	mgr := NewManager(&fakeSource{}, nil, testLogger(), WithHeartbeat(0), WithNotificationFeed(feed))
	defer mgr.Close()
	conn := serveConn(t, mgr, true)
	conn.in <- clientMsg{Ch: chNotifications, Type: msgSubscribe}
	eventually(t, time.Second, mgr.PhoneForeground)
	ev := created("ntf_1")
	ev.Kind = domain.NotificationResolved
	feed.ch <- ev
	select {
	case m := <-conn.out:
		if m.Ch == chNotifications {
			t.Fatalf("resolved event forwarded: %+v", m)
		}
	case <-time.After(100 * time.Millisecond):
	}
}

func TestPhoneForegroundCountsOnlyRemoteSubscriptions(t *testing.T) {
	mgr := NewManager(&fakeSource{}, nil, testLogger(), WithHeartbeat(0), WithNotificationFeed(newFakeFeed()))
	defer mgr.Close()
	local := serveConn(t, mgr, false)
	local.in <- clientMsg{Ch: chNotifications, Type: msgSubscribe}
	time.Sleep(50 * time.Millisecond)
	if mgr.PhoneForeground() {
		t.Fatal("a loopback subscription must not count as the phone")
	}
	phone := serveConn(t, mgr, true)
	phone.in <- clientMsg{Ch: chNotifications, Type: msgSubscribe}
	eventually(t, time.Second, mgr.PhoneForeground)
	phone.in <- clientMsg{Ch: chNotifications, Type: msgUnsubscribe}
	eventually(t, time.Second, func() bool { return !mgr.PhoneForeground() })
}

func TestPhoneForegroundClearsWhenTheConnectionCloses(t *testing.T) {
	mgr := NewManager(&fakeSource{}, nil, testLogger(), WithHeartbeat(0), WithNotificationFeed(newFakeFeed()))
	defer mgr.Close()
	conn := newFakeConn()
	ctx, cancel := context.WithCancel(WithRemoteOrigin(context.Background()))
	done := make(chan struct{})
	go func() { mgr.Serve(ctx, conn); close(done) }()
	conn.in <- clientMsg{Ch: chNotifications, Type: msgSubscribe}
	eventually(t, time.Second, mgr.PhoneForeground)
	cancel()
	<-done
	if mgr.PhoneForeground() {
		t.Fatal("closed connection still counted as foreground")
	}
}
```

If `fakeConn`'s `ReadJSON` does not return on context cancel, end `Serve` in the last test by closing `conn.in` instead of `cancel()` (read `newFakeConn` in `manager_test.go` first and use whichever it supports).

In `backend/internal/httpd/lan_listener_test.go` (create if absent, package `httpd`):

```go
func TestLANHandlerMarksRequestsRemote(t *testing.T) {
	var sawRemote bool
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sawRemote = terminal.IsRemoteOrigin(r.Context())
		w.WriteHeader(http.StatusNoContent)
	})
	h := markRemoteOrigin(inner)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/mux", nil))
	if !sawRemote {
		t.Fatal("LAN-served request was not marked remote")
	}
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && go test ./internal/terminal/ ./internal/httpd/ -run 'TestNotifications|TestResolvedEvents|TestPhoneForeground|TestLANHandlerMarks' -v`
Expected: compile errors.

- [ ] **Step 3: Protocol**

`protocol.go`: add `chNotifications = "notifications"` to the channel consts, `msgNotification = "notification"` to server types, and to `serverMsg`:

```go
	Notification *notificationFrame `json:"notification,omitempty"`
```

```go
type notificationFrame struct {
	ID        string    `json:"id"`
	SessionID string    `json:"sessionId"`
	ProjectID string    `json:"projectId"`
	Type      string    `json:"type"`
	Title     string    `json:"title"`
	Body      string    `json:"body"`
	Quiet     bool      `json:"quiet"`
	CreatedAt time.Time `json:"createdAt"`
}
```

- [ ] **Step 4: Feed, origin and presence**

Create `backend/internal/terminal/notifications.go`:

```go
package terminal

import (
	"context"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type NotificationFeed interface {
	Subscribe(projectID domain.ProjectID) (<-chan domain.NotificationEvent, func())
}

func WithNotificationFeed(feed NotificationFeed) Option {
	return func(m *Manager) { m.notificationFeed = feed }
}

type remoteOriginKey struct{}

func WithRemoteOrigin(ctx context.Context) context.Context {
	return context.WithValue(ctx, remoteOriginKey{}, true)
}

func IsRemoteOrigin(ctx context.Context) bool {
	remote, _ := ctx.Value(remoteOriginKey{}).(bool)
	return remote
}

func (m *Manager) startNotificationFeed() {
	if m.notificationFeed == nil {
		return
	}
	events, cancel := m.notificationFeed.Subscribe("")
	m.stopNotificationFeed = cancel
	go func() {
		for ev := range events {
			if ev.Kind != domain.NotificationCreated {
				continue
			}
			m.broadcastNotification(frameFor(ev.Record))
		}
	}()
}

func frameFor(rec domain.NotificationRecord) *notificationFrame {
	return &notificationFrame{
		ID:        rec.ID,
		SessionID: string(rec.SessionID),
		ProjectID: string(rec.ProjectID),
		Type:      string(rec.Type),
		Title:     rec.Title,
		Body:      rec.Body,
		Quiet:     rec.Quiet,
		CreatedAt: rec.CreatedAt,
	}
}

func (m *Manager) broadcastNotification(frame *notificationFrame) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for c := range m.conns {
		c.mu.Lock()
		subscribed := c.notificationsSubscribed && !c.closed
		c.mu.Unlock()
		if subscribed {
			c.enqueue(serverMsg{Ch: chNotifications, Type: msgNotification, Notification: frame})
		}
	}
}

func (m *Manager) PhoneForeground() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	for c := range m.conns {
		c.mu.Lock()
		foreground := c.remote && c.notificationsSubscribed && !c.closed
		c.mu.Unlock()
		if foreground {
			return true
		}
	}
	return false
}

func (c *connState) handleNotifications(msg clientMsg) {
	c.mu.Lock()
	defer c.mu.Unlock()
	switch msg.Type {
	case msgSubscribe:
		c.notificationsSubscribed = true
	case msgUnsubscribe:
		c.notificationsSubscribed = false
	}
}
```

`manager.go` changes:
- `Manager` struct: add `notificationFeed NotificationFeed` and `stopNotificationFeed func()`.
- End of `NewManager` (after options apply, before `return m`): `m.startNotificationFeed()`.
- `Close()`: first line `if m.stopNotificationFeed != nil { m.stopNotificationFeed() }`.
- `connState`: add `remote bool` and `notificationsSubscribed bool`.
- `Serve`: in the `connState` literal add `remote: IsRemoteOrigin(ctx),`.
- `handle`: add `case chNotifications: c.handleNotifications(msg)`.
- `cleanup`: `c.closed = true` already makes the connection stop counting; no extra change.

Read `Close()` before editing: if it iterates `m.conns` under `m.mu`, call `stopNotificationFeed` before taking `m.mu` to keep the feed goroutine from blocking on the lock.

- [ ] **Step 5: LAN marks remote**

In `lan_listener.go`, add:

```go
func markRemoteOrigin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		next.ServeHTTP(w, r.WithContext(terminal.WithRemoteOrigin(r.Context())))
	})
}
```

and wrap the handler in `NewLANManager`: `handler: lanControlBlock(authMiddleware(state, lock, newMobileConnectReporter(sink, time.Now), trust)(markRemoteOrigin(handler))),`. Import `github.com/OmarAly92/operator/backend/internal/terminal`.

In `terminal_mux.go`, `mgr.Serve(r.Context(), ...)` already receives the marked context — no change.

- [ ] **Step 6: Daemon wiring**

In `daemon.go`, move `notificationHub := notify.NewHub()` (currently `:161`) above `termMgr := terminal.NewManager(...)` (`:143`) and pass the option:

```go
	notificationHub := notify.NewHub()
	termMgr := terminal.NewManager(runtimeAdapter, cdcPipe.Broadcaster, log, terminal.WithNotificationFeed(notificationHub))
```

- [ ] **Step 7: Run**

Run: `cd backend && go build ./... && go test -race ./internal/terminal/ ./internal/httpd/ ./internal/daemon/`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add backend/internal/terminal backend/internal/httpd backend/internal/daemon
git commit -m "feat(mux): notifications channel and phone foreground presence"
```

---

### Task 5: Alert topic in the Connect Mobile state

**Files:**
- Modify: `backend/internal/mobilebridge/config.go`
- Modify: `backend/internal/httpd/controllers/mobile.go` (`enableWithPassword` `:209-253`, `Disable` `:278-287`)
- Test: `backend/internal/mobilebridge/config_test.go`, `backend/internal/httpd/controllers/mobile_test.go` (or the existing BridgeService test file — find it with `grep -ln "BridgeService{" backend/internal/httpd/controllers/*_test.go`)

**Interfaces:**
- Produces: `State.AlertTopic string` (`json:"alertTopic,omitempty"`), `State.AlertTopicClaimed bool` (`json:"alertTopicClaimed,omitempty"`), `func Update(path string, fn func(*State) error) (State, error)`, `func GenerateAlertTopic() (string, error)`, `const AlertTopicLength = 32`.

- [ ] **Step 1: Failing tests**

Append to `backend/internal/mobilebridge/config_test.go`:

```go
func TestUpdateReadModifyWritesUnderOneLock(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mobile", "config.json")
	if err := Save(path, State{Enabled: true, Password: "pw", NgrokDomain: "x.ngrok.app"}); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, _ = Update(path, func(s *State) error { s.LastPort++; return nil })
		}(i)
	}
	wg.Wait()
	got, err := Load(path)
	if err != nil || got.LastPort != 20 || got.NgrokDomain != "x.ngrok.app" {
		t.Fatalf("state = %+v err=%v", got, err)
	}
}

func TestGenerateAlertTopic(t *testing.T) {
	a, err := GenerateAlertTopic()
	if err != nil {
		t.Fatal(err)
	}
	b, _ := GenerateAlertTopic()
	if len(a) != AlertTopicLength || a == b || strings.Trim(a, pwAlphabet) != "" {
		t.Fatalf("topics %q %q", a, b)
	}
}
```

Find the BridgeService tests (they use a fake `LANController`). Add:

```go
func TestEnableIssuesAnUnclaimedTopicAndRotationReplacesIt(t *testing.T) {
	bs, path := newTestBridge(t)
	if _, err := bs.Enable(); err != nil {
		t.Fatal(err)
	}
	first, _ := mobilebridge.Load(path)
	if len(first.AlertTopic) != mobilebridge.AlertTopicLength || first.AlertTopicClaimed {
		t.Fatalf("after enable: %+v", first)
	}
	if _, err := mobilebridge.Update(path, func(s *mobilebridge.State) error { s.AlertTopicClaimed = true; return nil }); err != nil {
		t.Fatal(err)
	}
	if _, err := bs.Regenerate(); err != nil {
		t.Fatal(err)
	}
	second, _ := mobilebridge.Load(path)
	if second.AlertTopic == first.AlertTopic || second.AlertTopicClaimed {
		t.Fatalf("after rotate: %+v (was %+v)", second, first)
	}
}

func TestEnableKeepsNgrokDomain(t *testing.T) {
	bs, path := newTestBridge(t)
	if err := mobilebridge.Save(path, mobilebridge.State{NgrokDomain: "keep.ngrok.app"}); err != nil {
		t.Fatal(err)
	}
	if _, err := bs.Enable(); err != nil {
		t.Fatal(err)
	}
	if st, _ := mobilebridge.Load(path); st.NgrokDomain != "keep.ngrok.app" {
		t.Fatalf("ngrok domain lost: %+v", st)
	}
}
```

`newTestBridge` must build a `*controllers.BridgeService{LAN: <fake>, ConfigPath: filepath.Join(t.TempDir(), "mobile", "config.json"), DefaultPort: 0}` using the fake LAN controller already present in the existing BridgeService tests; if the existing file has a different helper, reuse it instead of adding one.

Append to `backend/internal/daemon/mobile_restore_test.go` (create with package `daemon` if absent, mirroring any existing fake `LANController` there):

```go
func TestRestoreKeepsTheClaimedTopic(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mobile", "config.json")
	want := mobilebridge.State{Enabled: true, Password: "abcdefgh", LastPort: 0, AlertTopic: strings.Repeat("a", mobilebridge.AlertTopicLength), AlertTopicClaimed: true}
	if err := mobilebridge.Save(path, want); err != nil {
		t.Fatal(err)
	}
	if err := restoreMobileOnBoot(path, &fakeLAN{}, nil); err != nil {
		t.Fatal(err)
	}
	got, _ := mobilebridge.Load(path)
	if got.AlertTopic != want.AlertTopic || !got.AlertTopicClaimed {
		t.Fatalf("restore changed the topic: %+v", got)
	}
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && go test ./internal/mobilebridge/ ./internal/httpd/controllers/ ./internal/daemon/ -run 'TestUpdateReadModify|TestGenerateAlertTopic|TestEnableIssues|TestEnableKeepsNgrok|TestRestoreKeeps' -v`
Expected: compile errors / failures.

- [ ] **Step 3: Implement mobilebridge**

In `config.go` add to `State`:

```go
	AlertTopic        string `json:"alertTopic,omitempty"`
	AlertTopicClaimed bool   `json:"alertTopicClaimed,omitempty"`
```

and:

```go
const AlertTopicLength = 32

var stateMu sync.Mutex

func GenerateAlertTopic() (string, error) { return GeneratePasswordN(AlertTopicLength) }

func Update(path string, fn func(*State) error) (State, error) {
	stateMu.Lock()
	defer stateMu.Unlock()
	st, err := Load(path)
	if err != nil {
		return State{}, err
	}
	if err := fn(&st); err != nil {
		return State{}, err
	}
	if err := Save(path, st); err != nil {
		return State{}, err
	}
	return st, nil
}
```

Import `sync`.

- [ ] **Step 4: BridgeService**

Replace the `mobilebridge.Save(...)` call in `enableWithPassword` with:

```go
	if _, err := mobilebridge.Update(b.ConfigPath, func(st *mobilebridge.State) error {
		if st.Password != pw || st.AlertTopic == "" {
			topic, err := mobilebridge.GenerateAlertTopic()
			if err != nil {
				return err
			}
			st.AlertTopic = topic
			st.AlertTopicClaimed = false
		}
		st.Enabled = true
		st.Password = pw
		st.LastPort = port
		return nil
	}); err != nil {
```

(keep the existing rollback body under that `if`). Remove the now-unused `prevState` variable if nothing else reads it; `TunnelEnabled` is preserved because `Update` starts from the loaded state.

Replace `Disable`'s load/save with:

```go
	_, err := mobilebridge.Update(b.ConfigPath, func(st *mobilebridge.State) error {
		st.Enabled = false
		return nil
	})
	return err
```

Change `setTunnelIntent` (`:349`) the same way if it does its own `Load`/`Save`: read it and convert it to `Update`.

- [ ] **Step 5: Run**

Run: `cd backend && go build ./... && go test -race ./internal/mobilebridge/ ./internal/httpd/... ./internal/daemon/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/mobilebridge backend/internal/httpd/controllers/mobile.go backend/internal/httpd/controllers/*_test.go backend/internal/daemon
git commit -m "feat(mobile): per-pairing ntfy topic that rotates with the password"
```

---

### Task 6: ntfy sender, phone-alert gate, routes; delete Expo

**Files:**
- Delete: `backend/internal/push/dispatcher.go`, `dispatcher_test.go`, `expo.go`, `expo_test.go`, `backend/internal/mobilebridge/pushdevices.go`, `pushdevices_test.go`, `backend/internal/httpd/controllers/push.go`, `push_test.go`
- Create: `backend/internal/push/ntfy.go`, `backend/internal/push/alerts.go`, `backend/internal/push/ntfy_test.go`, `backend/internal/push/alerts_test.go`
- Create: `backend/internal/httpd/controllers/phone_alerts.go`, `phone_alerts_test.go`
- Modify: `backend/internal/httpd/controllers/dto.go` (remove push DTOs `:1480-1520`-ish, add phone-alert DTOs), `backend/internal/httpd/api.go`, `backend/internal/httpd/apispec/specgen/build.go` (tag `:74-75`, name map `:355-359`, `pushOperations` `:1216-1244`, call site `:456`)
- Modify: `backend/internal/daemon/daemon.go` (`:360-384` push block; wiring after `bs.LAN = lan` `:444`)
- Regenerate: `npm run api`

**Interfaces:**
- Consumes: `mobilebridge.Update/Load/State`, `terminal.Manager.PhoneForeground`, `notify.Hub.Subscribe`.
- Produces (package `push`):

```go
type Alert struct{ SessionID, Title, Message string }
type PhoneSender interface{ Send(ctx context.Context, topic string, alert Alert) error }
type Bridge interface{ Running() bool }
type Presence interface{ PhoneForeground() bool }
type Delivery struct{ At time.Time; OK bool; Error string }
type Status struct{ Enabled, Claimed bool; LastDelivery *Delivery }
func NewNtfySender(baseURL string, client *http.Client) *NtfySender
func NewAlerts(d AlertsDeps) *Alerts
func (a *Alerts) SetBridge(b Bridge)
func (a *Alerts) Run(ctx context.Context)
func (a *Alerts) Status() Status
func (a *Alerts) Claim() (topic string, server string, err error)
func (a *Alerts) Test(ctx context.Context) Delivery
```

- Routes: `GET /api/v1/phone-alerts` → `PhoneAlertStatusResponse`; `POST /api/v1/phone-alerts/subscribe` → `PhoneAlertSubscribeResponse{topic, server}`; `POST /api/v1/phone-alerts/test` → `PhoneAlertDeliveryResponse`.

- [ ] **Step 1: Failing ntfy sender tests**

`backend/internal/push/ntfy_test.go`:

```go
package push

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestNtfySendsTitleMessageAndClick(t *testing.T) {
	var gotPath, gotTitle, gotClick, gotBody string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotTitle = r.Header.Get("Title")
		gotClick = r.Header.Get("Click")
		b, _ := io.ReadAll(r.Body)
		gotBody = string(b)
	}))
	defer srv.Close()
	s := NewNtfySender(srv.URL, srv.Client())
	err := s.Send(context.Background(), "topic123", Alert{SessionID: "operator-4", Title: "split fix finished", Message: "finished"})
	if err != nil {
		t.Fatal(err)
	}
	if gotPath != "/topic123" || gotTitle != "split fix finished" || gotBody != "finished" || gotClick != "operator://session/operator-4" {
		t.Fatalf("path=%q title=%q click=%q body=%q", gotPath, gotTitle, gotClick, gotBody)
	}
}

func TestNtfyRetriesOnceThenReportsTheStatus(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer srv.Close()
	s := NewNtfySender(srv.URL, srv.Client())
	s.retryDelay = time.Millisecond
	err := s.Send(context.Background(), "t", Alert{Title: "x", Message: "y"})
	if err == nil || calls.Load() != 2 {
		t.Fatalf("err=%v calls=%d, want an error after 2 calls", err, calls.Load())
	}
}
```

- [ ] **Step 2: Implement `ntfy.go`**

```go
package push

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	DefaultNtfyServer = "https://ntfy.sh"
	ntfyTimeout       = 5 * time.Second
	ntfyRetryDelay    = 2 * time.Second
)

type Alert struct {
	SessionID string
	Title     string
	Message   string
}

type NtfySender struct {
	baseURL    string
	client     *http.Client
	retryDelay time.Duration
}

func NewNtfySender(baseURL string, client *http.Client) *NtfySender {
	if client == nil {
		client = &http.Client{Timeout: ntfyTimeout}
	}
	return &NtfySender{baseURL: strings.TrimRight(baseURL, "/"), client: client, retryDelay: ntfyRetryDelay}
}

func (s *NtfySender) Send(ctx context.Context, topic string, alert Alert) error {
	err := s.post(ctx, topic, alert)
	if err == nil {
		return nil
	}
	select {
	case <-ctx.Done():
		return err
	case <-time.After(s.retryDelay):
	}
	return s.post(ctx, topic, alert)
}

func (s *NtfySender) post(ctx context.Context, topic string, alert Alert) error {
	ctx, cancel := context.WithTimeout(ctx, ntfyTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.baseURL+"/"+url.PathEscape(topic), strings.NewReader(alert.Message))
	if err != nil {
		return err
	}
	req.Header.Set("Title", alert.Title)
	req.Header.Set("Tags", "robot")
	if alert.SessionID != "" {
		req.Header.Set("Click", "operator://session/"+url.PathEscape(alert.SessionID))
	}
	res, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode/100 != 2 {
		return fmt.Errorf("ntfy answered %s", res.Status)
	}
	return nil
}
```

Run: `cd backend && go test ./internal/push/ -run TestNtfy -v` → PASS.

- [ ] **Step 3: Failing gate tests**

`backend/internal/push/alerts_test.go`:

```go
package push

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/mobilebridge"
)

type fakeSender struct {
	mu     sync.Mutex
	sent   []Alert
	topics []string
	err    error
}

func (f *fakeSender) Send(_ context.Context, topic string, a Alert) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.sent = append(f.sent, a)
	f.topics = append(f.topics, topic)
	return f.err
}

type flag bool

func (f flag) Running() bool         { return bool(f) }
func (f flag) PhoneForeground() bool { return bool(f) }

func setup(t *testing.T, st mobilebridge.State, bridgeUp, foreground bool) (*Alerts, *fakeSender, *time.Time) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "mobile", "config.json")
	if err := mobilebridge.Save(path, st); err != nil {
		t.Fatal(err)
	}
	sender := &fakeSender{}
	now := time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC)
	a := NewAlerts(AlertsDeps{Sender: sender, ConfigPath: path, Presence: flag(foreground), Clock: func() time.Time { return now }})
	a.SetBridge(flag(bridgeUp))
	return a, sender, &now
}

var paired = mobilebridge.State{Enabled: true, Password: "pw", AlertTopic: strings.Repeat("t", 32), AlertTopicClaimed: true}

func record(typ domain.NotificationType, session string) domain.NotificationRecord {
	return domain.NotificationRecord{ID: "n-" + session, SessionID: domain.SessionID(session), ProjectID: "p", Type: typ, Title: session + " finished", Body: "Implemented X in /secret/path.go", CreatedAt: time.Now()}
}

func TestAlertsSendsWhenPairedAndBackgrounded(t *testing.T) {
	a, sender, _ := setup(t, paired, true, false)
	a.dispatch(context.Background(), record(domain.NotificationTurnFinished, "operator-4"))
	if len(sender.sent) != 1 || sender.topics[0] != paired.AlertTopic {
		t.Fatalf("sent=%+v topics=%v", sender.sent, sender.topics)
	}
	got := sender.sent[0]
	if got.Title != "operator-4 finished" || got.Message != "finished" || got.SessionID != "operator-4" {
		t.Fatalf("alert = %+v", got)
	}
	if strings.Contains(got.Title+got.Message, "secret") {
		t.Fatal("alert leaked the notification body")
	}
}

func TestAlertsGate(t *testing.T) {
	unclaimed := paired
	unclaimed.AlertTopicClaimed = false
	disabled := paired
	disabled.Enabled = false
	for _, tc := range []struct {
		name       string
		st         mobilebridge.State
		bridgeUp   bool
		foreground bool
		quiet      bool
	}{
		{"listener down", paired, false, false, false},
		{"connect mobile off", disabled, true, false, false},
		{"topic not claimed", unclaimed, true, false, false},
		{"phone app open", paired, true, true, false},
		{"quiet", paired, true, false, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			a, sender, _ := setup(t, tc.st, tc.bridgeUp, tc.foreground)
			rec := record(domain.NotificationTurnFinished, "s")
			rec.Quiet = tc.quiet
			a.dispatch(context.Background(), rec)
			if len(sender.sent) != 0 {
				t.Fatalf("sent %+v, want nothing", sender.sent)
			}
		})
	}
}

func TestAlertsCoalescePerSessionForTenSeconds(t *testing.T) {
	a, sender, now := setup(t, paired, true, false)
	a.dispatch(context.Background(), record(domain.NotificationTurnFinished, "s1"))
	a.dispatch(context.Background(), record(domain.NotificationNeedsInput, "s1"))
	a.dispatch(context.Background(), record(domain.NotificationTurnFinished, "s2"))
	if len(sender.sent) != 2 {
		t.Fatalf("sent %d, want 2 (one per session)", len(sender.sent))
	}
	*now = now.Add(11 * time.Second)
	a.dispatch(context.Background(), record(domain.NotificationTurnFinished, "s1"))
	if len(sender.sent) != 3 {
		t.Fatalf("sent %d after the window, want 3", len(sender.sent))
	}
}

func TestAlertsRecordsDeliveries(t *testing.T) {
	a, sender, _ := setup(t, paired, true, false)
	sender.err = errors.New("ntfy answered 429 Too Many Requests")
	a.dispatch(context.Background(), record(domain.NotificationTurnFinished, "s"))
	st := a.Status()
	if !st.Enabled || !st.Claimed || st.LastDelivery == nil || st.LastDelivery.OK || !strings.Contains(st.LastDelivery.Error, "429") {
		t.Fatalf("status = %+v", st)
	}
}

func TestAlertsPRTypesNeverCarryThePRTitle(t *testing.T) {
	a, sender, _ := setup(t, paired, true, false)
	rec := record(domain.NotificationReadyToMerge, "s")
	rec.Title = "Secret refactor · PR #12"
	rec.PRURL = "https://github.com/o/r/pull/12"
	a.dispatch(context.Background(), rec)
	if len(sender.sent) != 1 || strings.Contains(sender.sent[0].Title, "Secret") {
		t.Fatalf("sent = %+v", sender.sent)
	}
}

func TestClaimReturnsTheTopicAndMarksItClaimed(t *testing.T) {
	st := paired
	st.AlertTopicClaimed = false
	a, _, _ := setup(t, st, true, false)
	topic, server, err := a.Claim()
	if err != nil || topic != paired.AlertTopic || server != DefaultNtfyServer {
		t.Fatalf("topic=%q server=%q err=%v", topic, server, err)
	}
	if !a.Status().Claimed {
		t.Fatal("claim did not persist")
	}
}

func TestClaimWithoutConnectMobileFails(t *testing.T) {
	a, _, _ := setup(t, mobilebridge.State{}, false, false)
	if _, _, err := a.Claim(); !errors.Is(err, ErrAlertsUnavailable) {
		t.Fatalf("err = %v, want ErrAlertsUnavailable", err)
	}
}

func TestTestIgnoresForegroundButNotPairing(t *testing.T) {
	a, sender, _ := setup(t, paired, true, true)
	if d := a.Test(context.Background()); !d.OK || len(sender.sent) != 1 {
		t.Fatalf("delivery=%+v sent=%d", d, len(sender.sent))
	}
	b, sender2, _ := setup(t, mobilebridge.State{}, false, false)
	if d := b.Test(context.Background()); d.OK || len(sender2.sent) != 0 {
		t.Fatalf("unpaired test delivery=%+v sent=%d", d, len(sender2.sent))
	}
}
```

- [ ] **Step 4: Implement `alerts.go`**

```go
package push

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"sync"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/mobilebridge"
)

const (
	coalesceWindow = 10 * time.Second
	deliveryLog    = 20
)

var ErrAlertsUnavailable = errors.New("phone alerts need Connect Mobile to be on")

type PhoneSender interface {
	Send(ctx context.Context, topic string, alert Alert) error
}

type Bridge interface{ Running() bool }

type Presence interface{ PhoneForeground() bool }

type Subscriber interface {
	Subscribe(projectID domain.ProjectID) (<-chan domain.NotificationEvent, func())
}

type Delivery struct {
	At    time.Time
	OK    bool
	Error string
}

type Status struct {
	Enabled      bool
	Claimed      bool
	LastDelivery *Delivery
}

type AlertsDeps struct {
	Subscriber Subscriber
	Sender     PhoneSender
	ConfigPath string
	Presence   Presence
	Server     string
	Clock      func() time.Time
	Log        *slog.Logger
}

type Alerts struct {
	d AlertsDeps

	mu         sync.Mutex
	bridge     Bridge
	lastSent   map[domain.SessionID]time.Time
	deliveries []Delivery
}

func NewAlerts(d AlertsDeps) *Alerts {
	if d.Clock == nil {
		d.Clock = time.Now
	}
	if d.Log == nil {
		d.Log = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	if d.Server == "" {
		d.Server = DefaultNtfyServer
	}
	return &Alerts{d: d, lastSent: map[domain.SessionID]time.Time{}}
}

func (a *Alerts) SetBridge(b Bridge) {
	a.mu.Lock()
	a.bridge = b
	a.mu.Unlock()
}

func (a *Alerts) Run(ctx context.Context) {
	if a.d.Subscriber == nil {
		return
	}
	events, unsubscribe := a.d.Subscriber.Subscribe("")
	defer unsubscribe()
	for {
		select {
		case <-ctx.Done():
			return
		case ev, ok := <-events:
			if !ok {
				return
			}
			if ev.Kind == domain.NotificationCreated {
				a.dispatch(ctx, ev.Record)
			}
		}
	}
}

func (a *Alerts) Status() Status {
	st, _ := mobilebridge.Load(a.d.ConfigPath)
	a.mu.Lock()
	defer a.mu.Unlock()
	out := Status{Enabled: a.enabledLocked(st), Claimed: st.AlertTopicClaimed}
	if n := len(a.deliveries); n > 0 {
		last := a.deliveries[n-1]
		out.LastDelivery = &last
	}
	return out
}

func (a *Alerts) Claim() (string, string, error) {
	a.mu.Lock()
	bridgeUp := a.bridge != nil && a.bridge.Running()
	a.mu.Unlock()
	if !bridgeUp {
		return "", "", ErrAlertsUnavailable
	}
	st, err := mobilebridge.Update(a.d.ConfigPath, func(s *mobilebridge.State) error {
		if !s.Enabled || s.AlertTopic == "" {
			return ErrAlertsUnavailable
		}
		s.AlertTopicClaimed = true
		return nil
	})
	if err != nil {
		return "", "", err
	}
	return st.AlertTopic, a.d.Server, nil
}

func (a *Alerts) Test(ctx context.Context) Delivery {
	st, _ := mobilebridge.Load(a.d.ConfigPath)
	a.mu.Lock()
	ready := a.enabledLocked(st) && st.AlertTopicClaimed
	a.mu.Unlock()
	if !ready {
		return a.recordDelivery(ErrAlertsUnavailable)
	}
	err := a.d.Sender.Send(ctx, st.AlertTopic, Alert{Title: "Operator", Message: "Test alert from your desktop"})
	return a.recordDelivery(err)
}

func (a *Alerts) dispatch(ctx context.Context, rec domain.NotificationRecord) {
	if rec.Quiet {
		return
	}
	st, err := mobilebridge.Load(a.d.ConfigPath)
	if err != nil {
		return
	}
	now := a.d.Clock()
	a.mu.Lock()
	if !a.enabledLocked(st) || !st.AlertTopicClaimed {
		a.mu.Unlock()
		return
	}
	if a.d.Presence != nil && a.d.Presence.PhoneForeground() {
		a.mu.Unlock()
		return
	}
	if last, ok := a.lastSent[rec.SessionID]; ok && now.Sub(last) < coalesceWindow {
		a.mu.Unlock()
		return
	}
	a.lastSent[rec.SessionID] = now
	a.mu.Unlock()
	a.recordDelivery(a.d.Sender.Send(ctx, st.AlertTopic, alertFor(rec)))
}

func (a *Alerts) enabledLocked(st mobilebridge.State) bool {
	return st.Enabled && st.AlertTopic != "" && a.bridge != nil && a.bridge.Running()
}

func (a *Alerts) recordDelivery(err error) Delivery {
	d := Delivery{At: a.d.Clock(), OK: err == nil}
	if err != nil {
		d.Error = err.Error()
		a.d.Log.Warn("phone alert failed", "err", err)
	}
	a.mu.Lock()
	a.deliveries = append(a.deliveries, d)
	if over := len(a.deliveries) - deliveryLog; over > 0 {
		a.deliveries = a.deliveries[over:]
	}
	a.mu.Unlock()
	return d
}

func alertFor(rec domain.NotificationRecord) Alert {
	alert := Alert{SessionID: string(rec.SessionID), Title: rec.Title, Message: eventWord(rec.Type)}
	if !rec.Type.SessionScoped() {
		alert.Title = "Pull request " + eventWord(rec.Type)
	}
	return alert
}

func eventWord(t domain.NotificationType) string {
	switch t {
	case domain.NotificationTurnFinished:
		return "finished"
	case domain.NotificationNeedsInput:
		return "needs input"
	case domain.NotificationAgentExited:
		return "exited"
	case domain.NotificationReadyToMerge:
		return "ready to merge"
	case domain.NotificationPRMerged:
		return "merged"
	case domain.NotificationPRClosedUnmerged:
		return "closed"
	default:
		return "update"
	}
}
```

Run: `cd backend && go test -race ./internal/push/ -v` → PASS.

- [ ] **Step 5: Controller, DTOs, spec ops**

`controllers/dto.go`: delete `RegisterPushDeviceRequest`, `PushDeviceResponse`, `PushDeviceEnvelope`, `UnregisterPushDeviceResponse`, `PushDeviceTokenParam` (find them with `grep -n "PushDevice" controllers/dto.go`). Add:

```go
type PhoneAlertDeliveryResponse struct {
	At    time.Time `json:"at"`
	OK    bool      `json:"ok"`
	Error string    `json:"error,omitempty"`
}

type PhoneAlertStatusResponse struct {
	Enabled      bool                        `json:"enabled" description:"Connect Mobile is on and a topic exists."`
	Claimed      bool                        `json:"claimed" description:"A paired phone has fetched the current topic."`
	LastDelivery *PhoneAlertDeliveryResponse `json:"lastDelivery,omitempty"`
}

type PhoneAlertSubscribeResponse struct {
	Topic  string `json:"topic"`
	Server string `json:"server"`
}
```

`controllers/phone_alerts.go`:

```go
package controllers

import (
	"context"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	"github.com/OmarAly92/operator/backend/internal/push"
)

type PhoneAlertService interface {
	Status() push.Status
	Claim() (string, string, error)
	Test(ctx context.Context) push.Delivery
}

type PhoneAlertsController struct {
	Svc PhoneAlertService
}

func (c *PhoneAlertsController) Register(r chi.Router) {
	r.Get("/phone-alerts", c.status)
	r.Post("/phone-alerts/subscribe", c.subscribe)
	r.Post("/phone-alerts/test", c.test)
}

func (c *PhoneAlertsController) status(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/phone-alerts")
		return
	}
	st := c.Svc.Status()
	envelope.WriteJSON(w, http.StatusOK, PhoneAlertStatusResponse{Enabled: st.Enabled, Claimed: st.Claimed, LastDelivery: deliveryResponse(st.LastDelivery)})
}

func (c *PhoneAlertsController) subscribe(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/phone-alerts/subscribe")
		return
	}
	topic, server, err := c.Svc.Claim()
	if errors.Is(err, push.ErrAlertsUnavailable) {
		envelope.WriteAPIError(w, r, http.StatusConflict, "conflict", "PHONE_ALERTS_UNAVAILABLE", err.Error(), nil)
		return
	}
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "PHONE_ALERTS_FAILED", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, PhoneAlertSubscribeResponse{Topic: topic, Server: server})
}

func (c *PhoneAlertsController) test(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/phone-alerts/test")
		return
	}
	d := c.Svc.Test(r.Context())
	envelope.WriteJSON(w, http.StatusOK, *deliveryResponse(&d))
}

func deliveryResponse(d *push.Delivery) *PhoneAlertDeliveryResponse {
	if d == nil {
		return nil
	}
	return &PhoneAlertDeliveryResponse{At: d.At, OK: d.OK, Error: d.Error}
}
```

Before writing: confirm the JSON writer name with `grep -n "^func Write" backend/internal/httpd/envelope/*.go` and the error-kind strings used by other controllers (`grep -n "WriteAPIError(w, r, http.StatusConflict" -r backend/internal/httpd/controllers | head -3`); use what exists.

`controllers/phone_alerts_test.go` (the harness is the one the deleted `push_test.go` used):

```go
package controllers_test

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/push"
)

type fakePhoneAlerts struct {
	status   push.Status
	topic    string
	claimErr error
	delivery push.Delivery
}

func (f *fakePhoneAlerts) Status() push.Status { return f.status }
func (f *fakePhoneAlerts) Claim() (string, string, error) {
	return f.topic, push.DefaultNtfyServer, f.claimErr
}
func (f *fakePhoneAlerts) Test(context.Context) push.Delivery { return f.delivery }

func phoneAlertsServer(t *testing.T, svc *fakePhoneAlerts) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{PhoneAlerts: svc}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestPhoneAlertsStatus(t *testing.T) {
	srv := phoneAlertsServer(t, &fakePhoneAlerts{status: push.Status{Enabled: true}})
	res, err := http.Get(srv.URL + "/api/v1/phone-alerts")
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var body map[string]any
	_ = json.NewDecoder(res.Body).Decode(&body)
	if res.StatusCode != http.StatusOK || body["enabled"] != true || body["claimed"] != false {
		t.Fatalf("status=%d body=%v", res.StatusCode, body)
	}
}

func TestPhoneAlertsSubscribe(t *testing.T) {
	srv := phoneAlertsServer(t, &fakePhoneAlerts{topic: "abc"})
	res, err := http.Post(srv.URL+"/api/v1/phone-alerts/subscribe", "application/json", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var body map[string]any
	_ = json.NewDecoder(res.Body).Decode(&body)
	if res.StatusCode != http.StatusOK || body["topic"] != "abc" || body["server"] != push.DefaultNtfyServer {
		t.Fatalf("status=%d body=%v", res.StatusCode, body)
	}
}

func TestPhoneAlertsSubscribeWithoutConnectMobile(t *testing.T) {
	srv := phoneAlertsServer(t, &fakePhoneAlerts{claimErr: push.ErrAlertsUnavailable})
	res, err := http.Post(srv.URL+"/api/v1/phone-alerts/subscribe", "application/json", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var body map[string]any
	_ = json.NewDecoder(res.Body).Decode(&body)
	if res.StatusCode != http.StatusConflict || body["code"] != "PHONE_ALERTS_UNAVAILABLE" {
		t.Fatalf("status=%d body=%v", res.StatusCode, body)
	}
}

func TestPhoneAlertsTest(t *testing.T) {
	at := time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC)
	srv := phoneAlertsServer(t, &fakePhoneAlerts{delivery: push.Delivery{At: at, OK: false, Error: "ntfy answered 429"}})
	res, err := http.Post(srv.URL+"/api/v1/phone-alerts/test", "application/json", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var body map[string]any
	_ = json.NewDecoder(res.Body).Decode(&body)
	if body["ok"] != false || body["error"] != "ntfy answered 429" {
		t.Fatalf("body=%v", body)
	}
}
```

If the error envelope nests `code` (read `envelope.WriteAPIError`), assert on that shape instead.

`api.go`: replace `Push controllers.PushRegistry` with `PhoneAlerts controllers.PhoneAlertService`, the `push *controllers.PushController` field with `phoneAlerts *controllers.PhoneAlertsController`, construct `&controllers.PhoneAlertsController{Svc: deps.PhoneAlerts}`, and register `a.phoneAlerts.Register(r)` where `a.push.Register(r)` was.

`specgen/build.go`: rename the tag to `phone-alerts` ("Phone alert delivery through ntfy"), replace the four `ControllersPush*` name mappings with `"ControllersPhoneAlertDeliveryResponse": "PhoneAlertDeliveryResponse"`, `"ControllersPhoneAlertStatusResponse": "PhoneAlertStatusResponse"`, `"ControllersPhoneAlertSubscribeResponse": "PhoneAlertSubscribeResponse"`, and replace `pushOperations` with:

```go
func phoneAlertOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/phone-alerts", id: "getPhoneAlerts", tag: "phone-alerts",
			summary: "Phone alert status and the last delivery",
			resps: []respUnit{
				{http.StatusOK, controllers.PhoneAlertStatusResponse{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/phone-alerts/subscribe", id: "subscribePhoneAlerts", tag: "phone-alerts",
			summary: "Return the ntfy topic for this pairing and mark it claimed",
			resps: []respUnit{
				{http.StatusOK, controllers.PhoneAlertSubscribeResponse{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/phone-alerts/test", id: "testPhoneAlerts", tag: "phone-alerts",
			summary: "Send one test alert to the paired phone",
			resps: []respUnit{
				{http.StatusOK, controllers.PhoneAlertDeliveryResponse{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
	}
}
```

and call `phoneAlertOperations()` where `pushOperations()` was appended.

- [ ] **Step 6: Daemon wiring and deletions**

Delete the files listed under **Delete**. In `daemon.go`, remove the push registry and Expo dispatcher block (`:360-384`) and the `Push: pushRegistry,` dep. Before `httpd.NewWithDeps`, add:

```go
	phoneAlerts := push.NewAlerts(push.AlertsDeps{
		Subscriber: notificationHub,
		Sender:     push.NewNtfySender(push.DefaultNtfyServer, nil),
		ConfigPath: mobilebridge.Path(cfg.DataDir),
		Presence:   termMgr,
		Log:        log,
	})
```

pass `PhoneAlerts: phoneAlerts,` in `APIDeps`, and after `bs.LAN = lan` (`:444`):

```go
	phoneAlerts.SetBridge(lan)
	go phoneAlerts.Run(ctx)
```

Run: `npm run api` (repo root).

- [ ] **Step 7: Run everything**

Run: `cd backend && go build ./... && go test -race ./...`
Expected: PASS. `grep -rn "Expo\|PushDevice\|pushOperations\|push/devices" backend/internal` returns nothing outside comments you must also remove.

- [ ] **Step 8: Commit**

```bash
git add -A backend frontend/src/api/schema.ts
git commit -m "feat(push): ntfy phone alerts gated on pairing and foreground; remove the Expo path"
```

---

### Task 7: macOS toasts through UNUserNotificationCenter (Tauri)

If Task 0 Step 2 failed, skip this task's Steps 3-5 and instead implement approach B from spec D7; record the reason in the commit message.

**Files:**
- Modify: `frontend/src-tauri/Cargo.toml` (macOS deps)
- Create: `frontend/src-tauri/src/mac_notifications.rs`
- Modify: `frontend/src-tauri/src/lib.rs` (module decl, setup install, both `generate_handler!` lists)
- Modify: `frontend/src-tauri/src/native.rs` (`notification_show` `:437-477`, new commands, `AppClickHost`)
- Modify: `frontend/src-tauri/src/notification_policy.rs` (`show_plan`)
- Modify: `frontend/src-tauri/build.rs`, `frontend/src-tauri/capabilities/default.json`
- Test: `frontend/src-tauri/src/notification_policy.rs` (tests module)

**Interfaces:**
- Produces Tauri commands `notification_permission() -> String` (`"authorized" | "denied" | "not_determined" | "unsupported"`) and `notification_open_settings()`. Existing `notification_show` keeps its signature. Event `notifications:click` with the notification id as payload (`notification_policy::CLICK_EVENT`).

- [ ] **Step 1: Failing policy tests**

In `notification_policy.rs` tests, replace the focused-drops-everything expectation with:

```rust
    #[test]
    fn focused_window_still_toasts_but_does_not_bounce() {
        assert_eq!(
            show_plan(true, true, Some("operator-4 finished"), Some("needs_input")),
            vec![SignalAction::Toast]
        );
    }

    #[test]
    fn unfocused_window_toasts_and_bounces_for_attention_types() {
        assert_eq!(
            show_plan(false, true, Some("operator-4 needs your input"), Some("needs_input")),
            vec![SignalAction::Toast, SignalAction::Attention]
        );
    }
```

Delete any existing test asserting `show_plan(true, ...)` returns an empty plan. Add `"turn_finished"` and `"agent_exited"` to `ALL_TYPES`.

Run: `cd frontend/src-tauri && cargo test notification_policy` → FAIL.

- [ ] **Step 2: Policy change**

```rust
pub fn show_plan(
    focused: bool,
    supported: bool,
    title: Option<&str>,
    notification_type: Option<&str>,
) -> Vec<SignalAction> {
    let mut plan = Vec::with_capacity(2);
    if should_toast(title, supported) {
        plan.push(SignalAction::Toast);
    }
    if !focused && should_signal_attention(notification_type) {
        plan.push(SignalAction::Attention);
    }
    plan
}
```

Run: `cargo test notification_policy` → PASS.

- [ ] **Step 3: Dependencies**

In `[target.'cfg(target_os = "macos")'.dependencies]`:

```toml
objc2 = "=0.6.4"
block2 = "=0.6.2"
objc2-foundation = { version = "=0.3.2", default-features = false, features = ["NSGeometry", "NSString", "NSError", "NSObject"] }
objc2-user-notifications = { version = "=0.3.2", default-features = false, features = ["std", "block2", "bitflags", "UNUserNotificationCenter", "UNNotification", "UNNotificationContent", "UNNotificationRequest", "UNNotificationResponse", "UNNotificationSound", "UNNotificationSettings", "UNNotificationTrigger"] }
```

(replace the existing `objc2-foundation` line). Confirm the pinned versions match `Cargo.lock` (`grep -A1 'name = "objc2"' Cargo.lock`, same for `block2`); if the lock holds different patch versions, pin those instead.

- [ ] **Step 4: `mac_notifications.rs`**

```rust
use std::ptr::NonNull;
use std::sync::mpsc;
use std::sync::OnceLock;
use std::time::Duration;

use block2::RcBlock;
use objc2::rc::Retained;
use objc2::runtime::{Bool, ProtocolObject};
use objc2::{define_class, msg_send, AllocAnyThread};
use objc2_foundation::{NSError, NSObject, NSObjectProtocol, NSString};
use objc2_user_notifications::{
    UNAuthorizationOptions, UNAuthorizationStatus, UNMutableNotificationContent, UNNotification,
    UNNotificationPresentationOptions, UNNotificationRequest, UNNotificationResponse,
    UNNotificationSettings, UNNotificationSound, UNUserNotificationCenter,
    UNUserNotificationCenterDelegate,
};
use tauri::AppHandle;

use crate::native::AppClickHost;
use crate::notification_policy::route_click;

static APP: OnceLock<AppHandle> = OnceLock::new();

define_class!(
    #[unsafe(super(NSObject))]
    #[name = "OperatorNotificationDelegate"]
    struct NotificationDelegate;

    unsafe impl NSObjectProtocol for NotificationDelegate {}

    unsafe impl UNUserNotificationCenterDelegate for NotificationDelegate {
        #[unsafe(method(userNotificationCenter:willPresentNotification:withCompletionHandler:))]
        fn will_present(
            &self,
            _center: &UNUserNotificationCenter,
            _notification: &UNNotification,
            completion_handler: &block2::DynBlock<dyn Fn(UNNotificationPresentationOptions)>,
        ) {
            completion_handler.call((UNNotificationPresentationOptions::Banner
                | UNNotificationPresentationOptions::List
                | UNNotificationPresentationOptions::Sound,));
        }

        #[unsafe(method(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:))]
        fn did_receive(
            &self,
            _center: &UNUserNotificationCenter,
            response: &UNNotificationResponse,
            completion_handler: &block2::DynBlock<dyn Fn()>,
        ) {
            let id = response.notification().request().identifier().to_string();
            if let Some(app) = APP.get() {
                route_click(&id, &mut AppClickHost(app));
            }
            completion_handler.call(());
        }
    }
);

impl NotificationDelegate {
    fn new() -> Retained<Self> {
        let this = Self::alloc().set_ivars(());
        unsafe { msg_send![super(this), init] }
    }
}

pub fn install(app: &AppHandle) {
    let _ = APP.set(app.clone());
    let center = UNUserNotificationCenter::currentNotificationCenter();
    let delegate = NotificationDelegate::new();
    center.setDelegate(Some(ProtocolObject::from_ref(&*delegate)));
    std::mem::forget(delegate);
    let done = RcBlock::new(|_granted: Bool, _error: *mut NSError| {});
    center.requestAuthorizationWithOptions_completionHandler(
        UNAuthorizationOptions::Alert | UNAuthorizationOptions::Sound | UNAuthorizationOptions::Badge,
        &done,
    );
}

pub fn post(id: &str, title: &str, body: Option<&str>) {
    let content = UNMutableNotificationContent::new();
    content.setTitle(&NSString::from_str(title));
    if let Some(body) = body {
        content.setBody(&NSString::from_str(body));
    }
    content.setSound(Some(&UNNotificationSound::defaultSound()));
    let request = UNNotificationRequest::requestWithIdentifier_content_trigger(
        &NSString::from_str(id),
        &content,
        None,
    );
    UNUserNotificationCenter::currentNotificationCenter()
        .addNotificationRequest_withCompletionHandler(&request, None);
}

pub fn authorization() -> &'static str {
    let (tx, rx) = mpsc::channel();
    let block = RcBlock::new(move |settings: NonNull<UNNotificationSettings>| {
        let status = unsafe { settings.as_ref() }.authorizationStatus();
        let _ = tx.send(status);
    });
    UNUserNotificationCenter::currentNotificationCenter()
        .getNotificationSettingsWithCompletionHandler(&block);
    match rx.recv_timeout(Duration::from_secs(2)) {
        Ok(UNAuthorizationStatus::NotDetermined) => "not_determined",
        Ok(UNAuthorizationStatus::Denied) => "denied",
        Ok(_) => "authorized",
        Err(_) => "not_determined",
    }
}

pub fn open_settings(bundle_id: &str) {
    let _ = std::process::Command::new("open")
        .arg(format!(
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id={bundle_id}"
        ))
        .spawn();
}
```

If `define_class!` rejects the method names or `set_ivars(())` for a class without `#[ivars]`, consult `objc2-0.6.4/src/macros/define_class.rs` examples (the doc block at `:292`) and adjust to what compiles; the behavior must stay as written. `setDelegate` may require `unsafe` in this version — wrap it if the compiler says so.

In `lib.rs` add `#[cfg(target_os = "macos")] mod mac_notifications;` next to `mod mac_window_controls;`, and in `.setup(...)` after `build_main_window(...)?;`:

```rust
            #[cfg(target_os = "macos")]
            if !tauri::is_dev() {
                mac_notifications::install(app.handle());
            }
```

- [ ] **Step 5: Commands and click host**

In `native.rs`:

```rust
pub struct AppClickHost<'a>(pub &'a AppHandle);

impl crate::notification_policy::ClickHost for AppClickHost<'_> {
    fn focus_main_window(&mut self) {
        focus_main_window(self.0);
    }

    fn send_clicked(&mut self, id: &str) {
        let _ = self.0.emit(crate::notification_policy::CLICK_EVENT, id.to_string());
    }
}

#[tauri::command]
pub async fn notification_permission() -> Result<String, String> {
    #[cfg(target_os = "macos")]
    if !tauri::is_dev() {
        return Ok(crate::mac_notifications::authorization().to_string());
    }
    Ok("unsupported".to_string())
}

#[tauri::command]
pub async fn notification_open_settings(app: AppHandle) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    crate::mac_notifications::open_settings(&app.config().identifier);
    #[cfg(not(target_os = "macos"))]
    let _ = app;
    Ok(())
}
```

In `notification_show`, replace the `SignalAction::Toast` arm body with:

```rust
            crate::notification_policy::SignalAction::Toast => {
                #[cfg(target_os = "macos")]
                if !tauri::is_dev() {
                    crate::mac_notifications::post(
                        &notification.id,
                        &notification.title,
                        notification.body.as_deref(),
                    );
                    continue;
                }
                let mut builder = window
                    .notification()
                    .builder()
                    .title(notification.title.clone());
                if let Some(body) = &notification.body {
                    builder = builder.body(body.clone());
                }
                builder.show().map_err(|error| error.to_string())?;
            }
```

Ensure `tauri::Emitter` is imported in `native.rs` for `.emit` (check existing `use` lines).

Register `native::notification_permission` and `native::notification_open_settings` in **both** `generate_handler!` lists in `lib.rs`, add `"notification_permission"` and `"notification_open_settings"` to `build.rs`, and add `"allow-notification-permission"` and `"allow-notification-open-settings"` to `capabilities/default.json` next to `"allow-notification-show"`.

- [ ] **Step 6: Build and test**

Run: `cd frontend/src-tauri && cargo build && cargo test`
Expected: PASS, no warnings about unused imports.

- [ ] **Step 7: Commit**

```bash
git add frontend/src-tauri
git commit -m "feat(tauri): macOS toasts through UNUserNotificationCenter with click-to-open"
```

---

### Task 8: Renderer — who gets a toast, bridge, Notifications settings

**Files:**
- Modify: `frontend/src/renderer/lib/notifications.ts:274-330`
- Modify: `frontend/src/renderer/components/NotificationCenter.tsx:103-146`, `:631-660`
- Modify: `frontend/src/shared/operator-bridge.ts:91-96`, `frontend/src/renderer/lib/tauri-bridge.ts:255-266`, `frontend/src/renderer/lib/bridge.ts:94-99`, `frontend/e2e/support/fake-bridge.ts` (both `notifications` objects, `:99` and `:441`)
- Create: `frontend/src/renderer/components/settings/NotificationsSection.tsx`, `NotificationsSection.test.tsx`, `frontend/src/renderer/hooks/usePhoneAlerts.ts`
- Modify: `frontend/src/renderer/components/GlobalSettingsForm.tsx`, `frontend/src/renderer/components/SettingsDialog.tsx:45-51`, `frontend/src/renderer/i18n/en.json`
- Test: `frontend/src/renderer/lib/notifications.test.ts`

**Interfaces:**
- Consumes: `NotificationDTO.quiet` (Task 1 schema), `/api/v1/phone-alerts` routes (Task 6 schema), Tauri commands from Task 7.
- Produces: `createNotificationsTransport(queryClient, isWatchingSession: (sessionId: string) => boolean)`; bridge `notifications.permission(): Promise<"authorized" | "denied" | "not_determined" | "unsupported">`, `notifications.openSettings(): Promise<void>`.

- [ ] **Step 1: Failing transport tests**

In `notifications.test.ts`, change every `createNotificationsTransport(qc, () => "mer-1")` / `() => activeSessionId` call to a predicate — `(id) => id === "mer-1"` and `(id) => id === activeSessionId` — and add:

```ts
	it.each(["turn_finished", "agent_exited"] as const)(
		"suppresses the %s toast for a session visible in a focused window",
		(type) => {
			setWindowState({ focused: true, visible: true });
			createNotificationsTransport(queryClient(), (id) => id === "mer-1").connect();
			EventSourceStub.instances[0].dispatch("notification_created", notification({ type }));
			expect(showNotificationMock).not.toHaveBeenCalled();
		},
	);

	it("toasts a session that is not in any visible pane while another one is", () => {
		setWindowState({ focused: true, visible: true });
		createNotificationsTransport(queryClient(), (id) => id === "other").connect();
		EventSourceStub.instances[0].dispatch("notification_created", notification({ type: "turn_finished" }));
		expect(showNotificationMock).toHaveBeenCalledTimes(1);
	});

	it("never toasts a quiet notification", () => {
		setWindowState({ focused: false, visible: true });
		createNotificationsTransport(queryClient(), () => false).connect();
		EventSourceStub.instances[0].dispatch("notification_created", notification({ type: "turn_finished", quiet: true }));
		expect(showNotificationMock).not.toHaveBeenCalled();
	});
```

If the `notification()` factory's type does not accept `quiet`, add `quiet: false` to its defaults.

Run: `cd frontend && npx vitest run src/renderer/lib/notifications.test.ts` → FAIL.

- [ ] **Step 2: Implement the rule**

In `notifications.ts`, replace `suppressToastForWatchedSession` with:

```ts
const SESSION_SCOPED_TYPES = new Set(["needs_input", "turn_finished", "agent_exited"]);

export function shouldToast(notification: NotificationDTO, isWatchingSession: (sessionId: string) => boolean): boolean {
	if (notification.quiet) return false;
	if (!SESSION_SCOPED_TYPES.has(notification.type) || !notification.sessionId) return true;
	if (!isWatchingSession(notification.sessionId)) return true;
	return !(document.visibilityState === "visible" && document.hasFocus());
}
```

Change the transport signature to `isWatchingSession: (sessionId: string) => boolean = () => false` and the toast condition to `if (inserted && shouldToast(notification, isWatchingSession))`.

In `NotificationCenter.tsx` `NotificationRuntime`, replace `routeSessionIdRef` and `getVisibleAgentSessionId` with:

```tsx
	const isWatchingSession = useCallback(
		(sessionId: string) => useUiStore.getState().visibleTerminalKindBySession[sessionId] === "worker",
		[],
	);

	useEffect(
		() => createNotificationsTransport(queryClient, isWatchingSession).connect(),
		[isWatchingSession, queryClient],
	);
```

Remove the now-unused `useParams` import/call and the old comment block describing the route-based check. `visibleTerminalKindBySession` is written by `SplitWorkspace` for every pane's active tab (`components/split/SplitWorkspace.tsx:88-100`) and cleared when the session view unmounts, so it already covers split view.

Add icon cases:

```tsx
		case "turn_finished":
			return CircleCheck;
		case "agent_exited":
			return OctagonX;
```

```tsx
		case "turn_finished":
			return "text-success";
		case "agent_exited":
			return "text-error";
```

(import `CircleCheck` and `OctagonX` from `lucide-react`; both exist in the installed version.)

Run: `npx vitest run src/renderer/lib/notifications.test.ts` → PASS.

- [ ] **Step 3: Bridge**

`shared/operator-bridge.ts` `notifications`:

```ts
		permission: () => Promise<"authorized" | "denied" | "not_determined" | "unsupported">;
		openSettings: () => Promise<void>;
```

`tauri-bridge.ts`:

```ts
			permission: async () =>
				(await invoke<string>("notification_permission")) as "authorized" | "denied" | "not_determined" | "unsupported",
			openSettings: async () => {
				await invoke("notification_open_settings");
			},
```

`bridge.ts` web stub: `permission: async () => "unsupported" as const, openSettings: async () => undefined,`. Add the same two members to both `notifications` objects in `e2e/support/fake-bridge.ts`, plus the three members that file is already missing (`resolvePath`, `resolveFirstPath`, `openPath` — see the Frontend CI failure) under `app` with no-op implementations matching `operator-bridge.ts`'s signatures.

- [ ] **Step 4: Phone alerts hook**

`hooks/usePhoneAlerts.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { apiClient, apiErrorMessage } from "../lib/api-client";

export const phoneAlertsQueryKey = ["phone-alerts"] as const;

export function usePhoneAlerts() {
	return useQuery({
		queryKey: phoneAlertsQueryKey,
		queryFn: async () => {
			const { data, error } = await apiClient.GET("/api/v1/phone-alerts");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		refetchInterval: 15_000,
	});
}

export function useTestPhoneAlert() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/phone-alerts/test");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSettled: () => queryClient.invalidateQueries({ queryKey: phoneAlertsQueryKey }),
	});
}
```

Check `apiErrorMessage`'s real signature in `lib/api-client.ts` and adapt the call if it takes a different argument.

- [ ] **Step 5: Settings section (test first)**

`frontend/src/renderer/components/settings/NotificationsSection.test.tsx` (same mocking style as `ClaudeAccountsSection.test.tsx`; the test setup initializes i18n with `en.json`, so `t()` returns the English strings):

```tsx
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, test, vi } from "vitest";

const h = vi.hoisted(() => ({
	permission: vi.fn(),
	openSettings: vi.fn(),
	show: vi.fn(),
	status: undefined as unknown,
	sendTest: vi.fn(),
}));

vi.mock("../../lib/bridge", () => ({
	operatorBridge: { notifications: { permission: h.permission, openSettings: h.openSettings, show: h.show } },
}));

vi.mock("../../hooks/usePhoneAlerts", () => ({
	usePhoneAlerts: () => ({ data: h.status }),
	useTestPhoneAlert: () => ({ mutate: h.sendTest, isPending: false }),
}));

import { NotificationsSection } from "./NotificationsSection";

beforeEach(() => {
	for (const fn of [h.permission, h.openSettings, h.show, h.sendTest]) fn.mockReset();
	h.permission.mockResolvedValue("authorized");
	h.status = { enabled: true, claimed: true };
});

test("denied permission offers System Settings", async () => {
	h.permission.mockResolvedValue("denied");
	render(<NotificationsSection />);
	expect(await screen.findByText("Off in System Settings")).toBeTruthy();
	await userEvent.click(screen.getByRole("button", { name: "Open System Settings" }));
	expect(h.openSettings).toHaveBeenCalledTimes(1);
});

test("the Mac test posts a test notification", async () => {
	render(<NotificationsSection />);
	await userEvent.click(screen.getAllByRole("button", { name: "Send test" })[0]);
	expect(h.show).toHaveBeenCalledWith(expect.objectContaining({ type: "test", title: "Operator" }));
});

test.each([
	[{ enabled: false, claimed: false }, "Off — Connect Mobile is off", true],
	[{ enabled: true, claimed: false }, "Waiting for the phone to subscribe", true],
	[{ enabled: true, claimed: true, lastDelivery: { at: "2026-09-23T10:00:00Z", ok: false, error: "ntfy answered 429" } }, "Last attempt failed: ntfy answered 429", false],
	[{ enabled: true, claimed: true }, "On for your paired phone", false],
])("phone status %o reads %s", async (status, line, disabled) => {
	h.status = status;
	render(<NotificationsSection />);
	expect(await screen.findByText(line)).toBeTruthy();
	const phoneButton = screen.getAllByRole("button", { name: "Send test" })[1] as HTMLButtonElement;
	await waitFor(() => expect(phoneButton.disabled).toBe(disabled));
});
```

`NotificationsSection.tsx` (use `SettingsSection`, `SettingsRow`, the `Button` primitive from `components/ui/button`, and `t()` keys below; model layout on `UpdatesSection.tsx`):

```tsx
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { operatorBridge } from "../../lib/bridge";
import { usePhoneAlerts, useTestPhoneAlert } from "../../hooks/usePhoneAlerts";
import { Button } from "../ui/button";
import { SettingsRow } from "./SettingsRow";
import { SettingsSection } from "./SettingsSection";

type Permission = "authorized" | "denied" | "not_determined" | "unsupported";

export function NotificationsSection({ titleHidden }: { titleHidden?: boolean }) {
	const { t } = useTranslation();
	const [permission, setPermission] = useState<Permission>("unsupported");
	const phone = usePhoneAlerts();
	const testPhone = useTestPhoneAlert();

	useEffect(() => {
		void operatorBridge.notifications.permission().then(setPermission);
	}, []);

	const status = phone.data;
	const phoneLine = !status?.enabled
		? t("settings.notifications.phoneOff")
		: !status.claimed
			? t("settings.notifications.phoneWaiting")
			: status.lastDelivery && !status.lastDelivery.ok
				? t("settings.notifications.phoneFailed", { error: status.lastDelivery.error })
				: t("settings.notifications.phoneOn");

	return (
		<SettingsSection title={t("settings.notifications.title")} titleHidden={titleHidden} grouped>
			<SettingsRow label={t("settings.notifications.mac")}>
				<span>{t(`settings.notifications.permission.${permission}`)}</span>
				{permission === "denied" ? (
					<Button variant="outline" size="sm" onClick={() => void operatorBridge.notifications.openSettings()}>
						{t("settings.notifications.openSystemSettings")}
					</Button>
				) : null}
			</SettingsRow>
			<SettingsRow label={t("settings.notifications.testMac")}>
				<Button
					variant="outline"
					size="sm"
					onClick={() =>
						void operatorBridge.notifications.show({
							id: `test:${Date.now()}`,
							title: t("settings.notifications.testTitle"),
							body: t("settings.notifications.testBody"),
							type: "test",
						})
					}
				>
					{t("settings.notifications.send")}
				</Button>
			</SettingsRow>
			<SettingsRow label={t("settings.notifications.phone")}>
				<span>{phoneLine}</span>
			</SettingsRow>
			<SettingsRow label={t("settings.notifications.testPhone")}>
				<Button
					variant="outline"
					size="sm"
					disabled={!status?.enabled || !status.claimed || testPhone.isPending}
					onClick={() => testPhone.mutate()}
				>
					{t("settings.notifications.send")}
				</Button>
			</SettingsRow>
		</SettingsSection>
	);
}
```

Check `SettingsRow`'s children slot and `Button`'s variant names against the files before writing, and match them.

`en.json` keys (flat, like the rest of the file):

```json
"settings.notifications.title": "Notifications",
"settings.notifications.mac": "Mac notifications",
"settings.notifications.permission.authorized": "Allowed",
"settings.notifications.permission.denied": "Off in System Settings",
"settings.notifications.permission.not_determined": "Not asked yet",
"settings.notifications.permission.unsupported": "Not available in this build",
"settings.notifications.openSystemSettings": "Open System Settings",
"settings.notifications.testMac": "Test on this Mac",
"settings.notifications.testTitle": "Operator",
"settings.notifications.testBody": "Notifications are working.",
"settings.notifications.send": "Send test",
"settings.notifications.phone": "Phone alerts",
"settings.notifications.phoneOff": "Off — Connect Mobile is off",
"settings.notifications.phoneWaiting": "Waiting for the phone to subscribe",
"settings.notifications.phoneOn": "On for your paired phone",
"settings.notifications.phoneFailed": "Last attempt failed: {{error}}",
"settings.notifications.testPhone": "Test on the phone"
```

`GlobalSettingsForm.tsx`: add `"notifications"` to `GlobalSettingsSection` and render `{(section === "all" || section === "notifications") && <NotificationsSection titleHidden={leadingTitleHidden} />}` after the mobile section. `SettingsDialog.tsx`: add `{ id: "notifications", label: t("settings.notifications.title"), icon: Bell }` after `mobile` (import `Bell` from `lucide-react`).

- [ ] **Step 6: Run**

Run: `cd frontend && npm run typecheck && npx vitest run src/renderer/lib/notifications.test.ts src/renderer/components/settings/NotificationsSection.test.tsx src/renderer/components/NotificationCenter`
Expected: PASS. Also `npx tsc -p tsconfig.e2e.json --noEmit` passes (the fake bridge now satisfies `OperatorBridge`).

- [ ] **Step 7: Commit**

```bash
git add frontend/src frontend/e2e
git commit -m "feat(renderer): toast unless the session is on screen; Notifications settings with Mac and phone tests"
```

---

### Task 9: Mobile — remove the push scaffolding, rename the deep-link scheme

**Files:**
- Delete: `packages/mobile/lib/feature/notification/logic/push_registrar.dart`, `push_registration.dart`, `push_status.dart`, `push_token_source.dart`, `packages/mobile/lib/feature/notification/data/model/params/register_push_device_params.dart`, and their tests under `packages/mobile/test/feature/notification/` (find with `grep -rln "push_" packages/mobile/test`)
- Modify: `packages/mobile/lib/core/api/server_config.dart` (add `hasServer`), `packages/mobile/lib/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart:10`, `packages/mobile/lib/feature/notification/data/data_source/notification_remote_data_source.dart`, `.../repository/notification_repository.dart`, `packages/mobile/lib/core/api/api_request_helpers/end_points.dart:12,18`, `packages/mobile/lib/core/utils/service_locator.dart:25-27,278-292`, `packages/mobile/lib/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart` (push toggle and its state), `packages/mobile/test/core/app_routes/home_shell_test.dart`
- Modify: `packages/mobile/lib/core/deep_link/deep_link_target.dart:5` and its doc comments, `packages/mobile/ios/Runner/Info.plist:97`, `packages/mobile/android/app/src/main/AndroidManifest.xml:43`, `packages/mobile/test/core/deep_link/deep_link_service_test.dart`, `deep_link_target_test.dart`

- [ ] **Step 1: Move `hasServer`**

Add to `lib/core/api/server_config.dart`:

```dart
bool hasServer(ServerConfig? server) => (server?.host.trim() ?? '').isNotEmpty;
```

Point `notifications_cubit.dart` at `package:operator_mobile/core/api/server_config.dart` instead of `push_status.dart`.

- [ ] **Step 2: Delete the push files and every reference**

Delete the files listed. Remove `registerPushDevice`/`unregisterPushDevice` from the data source interface, implementation and repository; remove `pushDevices`/`pushDevice` from `EndPoints`; remove the three imports and the three registrations from `service_locator.dart`; in `settings_body.dart` remove `_pushStatus`, `_pushBusy`, `_refreshPushStatus`, `_togglePush`, the `SettingsToggle` for "Agent notifications", and the two push imports, keeping the "History" row inside the "Notifications" group. In `home_shell_test.dart` remove `_FakeTokenSource`, the push imports, the `RegisterPushDeviceParams` fallback and the `PushRegistrar` registration.

Run: `cd packages/mobile && grep -rn "Push\(Registrar\|Status\|TokenSource\|Registration\)\|pushDevice\|RegisterPushDevice\|describePushToggle" lib test` → no output.

- [ ] **Step 3: Rename the scheme (tests first)**

In both deep-link tests replace `aomobile` with `operator`, and add to `deep_link_target_test.dart`:

```dart
  test('the old aomobile scheme no longer resolves', () {
    expect(resolveDeepLink(Uri.parse('aomobile://session/abc')), isNull);
  });
```

Run: `flutter test test/core/deep_link/` → FAIL.

Set `const String kDeepLinkScheme = 'operator';`, update the two doc comments in `deep_link_target.dart` that spell `aomobile://`, change `<string>aomobile</string>` in `Info.plist` and `android:scheme="aomobile"` in `AndroidManifest.xml` to `operator`.

- [ ] **Step 4: Gate**

Run: `cd packages/mobile && flutter pub get && flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A packages/mobile
git commit -m "refactor(mobile): drop the unwired push scaffolding; deep links use operator://"
```

---

### Task 10: Mobile — live local notifications while the app is open

**Files:**
- Modify: `packages/mobile/pubspec.yaml` (add `flutter_local_notifications: ^22.3.0`)
- Create: `packages/mobile/lib/core/mux/mux_notification.dart`
- Modify: `packages/mobile/lib/core/mux/mux_client.dart`
- Create: `packages/mobile/lib/core/notifications/viewed_session.dart`, `local_alert_sink.dart`, `phone_alerts_runtime.dart`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart` (terminal route `:109-130`), `packages/mobile/lib/main.dart:80-96`, `packages/mobile/lib/core/utils/service_locator.dart`, `packages/mobile/ios/Runner/AppDelegate.swift`
- Modify: `packages/mobile/lib/feature/notification/logic/notification_view.dart`
- Test: `packages/mobile/test/core/mux/mux_client_notifications_test.dart`, `packages/mobile/test/core/notifications/phone_alerts_runtime_test.dart`, `packages/mobile/test/feature/notification/logic/notification_view_test.dart`

**Interfaces:**
- Consumes: the Task 4 wire frames.
- Produces: `MuxNotification {id, sessionId, type, title, body, quiet}`; `MuxClient.notifications` (`Stream<MuxNotification>`), `subscribeNotifications()`, `unsubscribeNotifications()`; `abstract class LocalAlertSink { Future<void> init(void Function(String payload) onTap); Future<void> show({required int id, required String title, required String body, required String payload}); }`; `PhoneAlertsRuntime(MuxClient, LocalAlertSink, bool Function(Uri) openLink)` with `start()`, `foreground()`, `background()`; `ViewedSession.current` (`ValueNotifier<String?>`).

- [ ] **Step 1: Failing MuxClient tests**

Append inside `group('MuxClient', ...)` in `packages/mobile/test/core/mux/mux_client_test.dart` (it already defines `_FakeMuxSocket`, `_StubSource` and `_source`), and add `import 'package:operator_mobile/core/mux/mux_notification.dart';`:

```dart
    test('subscribes and unsubscribes to live notifications', () {
      fakeAsync((async) {
        late _FakeMuxSocket socket;
        final client = MuxClient(_source, connect: (_, _) => socket = _FakeMuxSocket());
        client.connect();
        async.flushMicrotasks();

        client.subscribeNotifications();
        client.unsubscribeNotifications();

        final frames = socket.sent.map((s) => jsonDecode(s) as Map<String, dynamic>).where((m) => m['ch'] == 'notifications').toList();
        expect(frames, [
          {'ch': 'notifications', 'type': 'subscribe'},
          {'ch': 'notifications', 'type': 'unsubscribe'},
        ]);
        client.disconnect();
      });
    });

    test('re-sends the notification subscription after a reconnect only while subscribed', () {
      fakeAsync((async) {
        final sockets = <_FakeMuxSocket>[];
        final client = MuxClient(_source, connect: (_, _) {
          final socket = _FakeMuxSocket();
          sockets.add(socket);
          return socket;
        });
        client.connect();
        async.flushMicrotasks();
        client.subscribeNotifications();

        sockets.last.closeFromServer();
        async.elapse(const Duration(milliseconds: MuxBackoff.initialMs));
        async.flushMicrotasks();
        expect(sockets.last.sent.map(jsonDecode), contains({'ch': 'notifications', 'type': 'subscribe'}));

        client.unsubscribeNotifications();
        sockets.last.closeFromServer();
        async.elapse(const Duration(milliseconds: MuxBackoff.initialMs * 4));
        async.flushMicrotasks();
        expect(sockets.last.sent.map(jsonDecode), isNot(contains({'ch': 'notifications', 'type': 'subscribe'})));
        client.disconnect();
      });
    });

    test('emits one MuxNotification per notification frame and ignores malformed ones', () {
      fakeAsync((async) {
        late _FakeMuxSocket socket;
        final client = MuxClient(_source, connect: (_, _) => socket = _FakeMuxSocket());
        final received = <MuxNotification>[];
        client.notifications.listen(received.add);
        client.connect();
        async.flushMicrotasks();

        socket.pushMessage({
          'ch': 'notifications',
          'type': 'notification',
          'notification': {'id': 'n1', 'sessionId': 's1', 'type': 'turn_finished', 'title': 's1 finished', 'body': 'done', 'quiet': false},
        });
        socket.pushMessage({'ch': 'notifications', 'type': 'notification'});
        async.flushMicrotasks();

        expect(received, [
          const MuxNotification(id: 'n1', sessionId: 's1', type: 'turn_finished', title: 's1 finished', body: 'done', quiet: false),
        ]);
        client.disconnect();
      });
    });
```

If the reconnect backoff in the second test needs a longer elapse, use `MuxBackoff.next` to compute it, as the existing reconnect tests in this file do.

- [ ] **Step 2: Implement**

`mux_notification.dart`:

```dart
import 'package:equatable/equatable.dart';

class MuxNotification extends Equatable {
  const MuxNotification({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.title,
    required this.body,
    required this.quiet,
  });

  final String id;
  final String sessionId;
  final String type;
  final String title;
  final String body;
  final bool quiet;

  static MuxNotification? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    return MuxNotification(
      id: id,
      sessionId: raw['sessionId'] as String? ?? '',
      type: raw['type'] as String? ?? '',
      title: raw['title'] as String? ?? '',
      body: raw['body'] as String? ?? '',
      quiet: raw['quiet'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [id, sessionId, type, title, body, quiet];
}
```

`mux_client.dart`: add `final _notificationsController = StreamController<MuxNotification>.broadcast();`, `Stream<MuxNotification> get notifications => _notificationsController.stream;`, `bool _notificationsSubscribed = false;`, in `_open()` after the block re-subscribe loop:

```dart
    if (_notificationsSubscribed) _send({'ch': 'notifications', 'type': 'subscribe'});
```

in `_onMessage` before the terminal branch:

```dart
    if (ch == 'notifications' && type == 'notification') {
      final notification = MuxNotification.fromJson(msg['notification']);
      if (notification != null) _notificationsController.add(notification);
      return;
    }
```

and:

```dart
  void subscribeNotifications() {
    _notificationsSubscribed = true;
    _send({'ch': 'notifications', 'type': 'subscribe'});
  }

  void unsubscribeNotifications() {
    _notificationsSubscribed = false;
    _send({'ch': 'notifications', 'type': 'unsubscribe'});
  }
```

Run the MuxClient tests → PASS.

- [ ] **Step 3: Failing runtime tests**

`packages/mobile/test/core/notifications/phone_alerts_runtime_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/mux_notification.dart';
import 'package:operator_mobile/core/notifications/local_alert_sink.dart';
import 'package:operator_mobile/core/notifications/phone_alerts_runtime.dart';
import 'package:operator_mobile/core/notifications/viewed_session.dart';

class _MockMux extends Mock implements MuxClient {}

class _Shown {
  _Shown(this.id, this.title, this.body, this.payload);
  final int id;
  final String title;
  final String body;
  final String payload;
}

class _FakeSink implements LocalAlertSink {
  final shown = <_Shown>[];
  void Function(String payload)? onTap;

  @override
  Future<void> init(void Function(String payload) onTap) async => this.onTap = onTap;

  @override
  Future<void> show({required int id, required String title, required String body, required String payload}) async =>
      shown.add(_Shown(id, title, body, payload));
}

MuxNotification _n(String id, String session, {bool quiet = false}) =>
    MuxNotification(id: id, sessionId: session, type: 'turn_finished', title: '$session finished', body: 'done', quiet: quiet);

void main() {
  late _MockMux mux;
  late StreamController<MuxNotification> feed;
  late _FakeSink sink;
  late List<Uri> opened;
  late PhoneAlertsRuntime runtime;

  setUp(() async {
    ViewedSession.current.value = null;
    mux = _MockMux();
    feed = StreamController<MuxNotification>.broadcast(sync: true);
    when(() => mux.notifications).thenAnswer((_) => feed.stream);
    sink = _FakeSink();
    opened = [];
    runtime = PhoneAlertsRuntime(mux, sink, (uri) {
      opened.add(uri);
      return true;
    });
    await runtime.start();
  });

  tearDown(() async {
    await runtime.dispose();
    await feed.close();
  });

  test('shows a local notification that opens the session', () {
    feed.add(_n('n1', 's1'));
    expect(sink.shown.single.title, 's1 finished');
    expect(sink.shown.single.payload, 'operator://session/s1');
    sink.onTap!(sink.shown.single.payload);
    expect(opened, [Uri.parse('operator://session/s1')]);
  });

  test('skips the session on screen and quiet notifications', () {
    ViewedSession.current.value = 's1';
    feed.add(_n('n1', 's1'));
    feed.add(_n('n2', 's2', quiet: true));
    expect(sink.shown, isEmpty);
  });

  test('gives every notification its own id', () {
    feed.add(_n('n1', 's1'));
    feed.add(_n('n2', 's2'));
    expect(sink.shown.map((s) => s.id).toSet(), hasLength(2));
  });

  test('start subscribes; foreground and background follow the app', () {
    verify(() => mux.subscribeNotifications()).called(1);
    runtime.background();
    verify(() => mux.unsubscribeNotifications()).called(1);
    runtime.foreground();
    verify(() => mux.subscribeNotifications()).called(1);
  });
}
```

Confirm `mocktail` is already a dev dependency (`grep mocktail packages/mobile/pubspec.yaml`).

- [ ] **Step 4: Implement runtime, sink and viewed session**

`viewed_session.dart`:

```dart
import 'package:flutter/widgets.dart';

sealed class ViewedSession {
  static final ValueNotifier<String?> current = ValueNotifier<String?>(null);
}

class ViewedSessionMarker extends StatefulWidget {
  const ViewedSessionMarker({required this.sessionId, required this.child, super.key});

  final String sessionId;
  final Widget child;

  @override
  State<ViewedSessionMarker> createState() => _ViewedSessionMarkerState();
}

class _ViewedSessionMarkerState extends State<ViewedSessionMarker> {
  @override
  void initState() {
    super.initState();
    if (widget.sessionId.isNotEmpty) ViewedSession.current.value = widget.sessionId;
  }

  @override
  void dispose() {
    if (ViewedSession.current.value == widget.sessionId) ViewedSession.current.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

`local_alert_sink.dart`:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract class LocalAlertSink {
  Future<void> init(void Function(String payload) onTap);
  Future<void> show({required int id, required String title, required String body, required String payload});
}

class FlutterLocalAlertSink implements LocalAlertSink {
  FlutterLocalAlertSink([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> init(void Function(String payload) onTap) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onTap(payload);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) && payload != null && payload.isNotEmpty) onTap(payload);
  }

  @override
  Future<void> show({required int id, required String title, required String body, required String payload}) =>
      _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('agent_alerts', 'Agent alerts', importance: Importance.high, priority: Priority.high),
          iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true, presentList: true),
        ),
      );
}
```

Confirm `initialize`'s and `getNotificationAppLaunchDetails`' exact 22.3.0 signatures in `~/.pub-cache/hosted/pub.dev/flutter_local_notifications-22.3.0/lib/src/flutter_local_notifications_plugin.dart` (`initialize` at `:111` takes named `settings:`; `show` at `:252` takes named `id/title/body/notificationDetails/payload`) and adapt.

`phone_alerts_runtime.dart`:

```dart
import 'dart:async';

import 'package:operator_mobile/core/deep_link/deep_link_target.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/mux_notification.dart';
import 'package:operator_mobile/core/notifications/local_alert_sink.dart';
import 'package:operator_mobile/core/notifications/viewed_session.dart';

class PhoneAlertsRuntime {
  PhoneAlertsRuntime(this._mux, this._sink, this._openLink);

  final MuxClient _mux;
  final LocalAlertSink _sink;
  final bool Function(Uri uri) _openLink;
  StreamSubscription<MuxNotification>? _subscription;
  int _nextId = 1;

  Future<void> start() async {
    await _sink.init((payload) => _openLink(Uri.parse(payload)));
    _subscription ??= _mux.notifications.listen(_onNotification);
    foreground();
  }

  void foreground() => _mux.subscribeNotifications();

  void background() => _mux.unsubscribeNotifications();

  void _onNotification(MuxNotification n) {
    if (n.quiet || n.sessionId.isEmpty) return;
    if (ViewedSession.current.value == n.sessionId) return;
    unawaited(
      _sink.show(
        id: _nextId++,
        title: n.title,
        body: n.body,
        payload: '$kDeepLinkScheme://session/${Uri.encodeComponent(n.sessionId)}',
      ),
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
```

Wrap the terminal route's child in `app_router.dart` (`case RoutesStrings.terminal`) with `ViewedSessionMarker(sessionId: terminalArgs.sessionId, child: ...)`.

Register in `service_locator.dart` (notification setup):

```dart
    sl.registerLazySingleton<LocalAlertSink>(FlutterLocalAlertSink.new);
    sl.registerLazySingleton<PhoneAlertsRuntime>(
      () => PhoneAlertsRuntime(sl<MuxClient>(), sl<LocalAlertSink>(), (uri) => sl<DeepLinkService>().handle(uri)),
    );
```

In `main.dart` `_OperatorAppState`:

```dart
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () {
      unawaited(TelemetryRuntime.active());
      sl<PhoneAlertsRuntime>().foreground();
    },
    onShow: () => sl<PhoneAlertsRuntime>().foreground(),
    onHide: () => sl<PhoneAlertsRuntime>().background(),
    onPause: () => sl<PhoneAlertsRuntime>().background(),
  );
```

and in the `addPostFrameCallback` after the deep-link start: `unawaited(sl<PhoneAlertsRuntime>().start());`.

`AppDelegate.swift`, first line inside `application(_:didFinishLaunchingWithOptions:)`:

```swift
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
```

with `import UserNotifications` at the top (the plugin README's iOS setup; `FlutterAppDelegate` already conforms).

- [ ] **Step 5: Notification list visuals and targets (test first)**

`notification_view_test.dart`: `notificationTarget(type: 'turn_finished', sessionId: 's1')` and `'agent_exited'` return `'/session/s1'`; `'ready_to_merge'` still returns `'/prs'`; `notificationVisual(skin, 'turn_finished').label == 'Finished'`, `'agent_exited'` → `'Exited'`.

Implement in `notification_view.dart`:

```dart
  'turn_finished' => NotificationVisual(
    icon: Icons.check_circle_outline,
    color: skin.green,
    label: 'Finished',
  ),
  'agent_exited' => NotificationVisual(
    icon: Icons.stop_circle_outlined,
    color: skin.red,
    label: 'Exited',
  ),
```

```dart
const _sessionTypes = {'needs_input', 'turn_finished', 'agent_exited'};

String notificationTarget({required String type, String? sessionId}) =>
    _sessionTypes.contains(type) && (sessionId ?? '').isNotEmpty
    ? '/session/${Uri.encodeComponent(sessionId!)}'
    : '/prs';
```

- [ ] **Step 6: Gate**

Run: `cd packages/mobile && flutter pub get && flutter analyze && flutter test && flutter build ios --release --no-codesign`
Expected: all green; the iOS build compiles the AppDelegate change.

- [ ] **Step 7: Commit**

```bash
git add -A packages/mobile
git commit -m "feat(mobile): local notifications from the live mux feed while the app is open"
```

---

### Task 11: Mobile — Phone alerts settings (ntfy setup)

**Files:**
- Create: `packages/mobile/lib/feature/notification/data/model/phone_alert_status_model.dart`, `phone_alert_subscription_model.dart`, `phone_alert_delivery_model.dart`
- Modify: `packages/mobile/lib/feature/notification/data/data_source/notification_remote_data_source.dart`, `.../repository/notification_repository.dart`, `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Create: `packages/mobile/lib/feature/settings/presentation/settings_screen/logic/phone_alerts_cubit.dart` (+ `phone_alerts_state.dart`), `.../ui/widgets/phone_alerts_group.dart`
- Modify: `packages/mobile/lib/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart`, `service_locator.dart`, `packages/mobile/ios/Runner/Info.plist` (`LSApplicationQueriesSchemes` += `ntfy`)
- Test: `packages/mobile/test/feature/notification/data/...` (data source), `packages/mobile/test/feature/settings/.../phone_alerts_cubit_test.dart`

**Interfaces:**
- Consumes: Task 6 routes. Response bodies are bare JSON objects (parse with `withDataKey: false`, per CLAUDE.md).
- Produces: `EndPoints.phoneAlerts = '/api/v1/phone-alerts'`, `phoneAlertsSubscribe = '/api/v1/phone-alerts/subscribe'`, `phoneAlertsTest = '/api/v1/phone-alerts/test'`; `PhoneAlertsCubit` with `load()`, `subscribe()`, `sendTest()`.

- [ ] **Step 1: Models and data source (tests first)**

Models are hand-written with nullable fields and `fromJson` (no codegen). Data source tests (mocktail `ApiConsumer`, same pattern as the existing notification data source test) assert the three paths and methods and that `subscribe` returns the topic and server.

```dart
class PhoneAlertStatusModel extends Equatable {
  const PhoneAlertStatusModel({this.enabled, this.claimed, this.lastDelivery});

  final bool? enabled;
  final bool? claimed;
  final PhoneAlertDeliveryModel? lastDelivery;

  factory PhoneAlertStatusModel.fromJson(Map<String, dynamic> json) => PhoneAlertStatusModel(
    enabled: json['enabled'] as bool?,
    claimed: json['claimed'] as bool?,
    lastDelivery: json['lastDelivery'] is Map<String, dynamic>
        ? PhoneAlertDeliveryModel.fromJson(json['lastDelivery'] as Map<String, dynamic>)
        : null,
  );

  @override
  List<Object?> get props => [enabled, claimed, lastDelivery];
}
```

```dart
class PhoneAlertDeliveryModel extends Equatable {
  const PhoneAlertDeliveryModel({this.at, this.ok, this.error});

  final DateTime? at;
  final bool? ok;
  final String? error;

  factory PhoneAlertDeliveryModel.fromJson(Map<String, dynamic> json) => PhoneAlertDeliveryModel(
    at: DateTime.tryParse(json['at'] as String? ?? ''),
    ok: json['ok'] as bool?,
    error: json['error'] as String?,
  );

  @override
  List<Object?> get props => [at, ok, error];
}
```

```dart
class PhoneAlertSubscriptionModel extends Equatable {
  const PhoneAlertSubscriptionModel({this.topic, this.server});

  final String? topic;
  final String? server;

  factory PhoneAlertSubscriptionModel.fromJson(Map<String, dynamic> json) =>
      PhoneAlertSubscriptionModel(topic: json['topic'] as String?, server: json['server'] as String?);

  @override
  List<Object?> get props => [topic, server];
}
```

Add `getPhoneAlerts()`, `subscribePhoneAlerts()`, `testPhoneAlert()` to the notification data source and repository (repository returns `FutureResult<...>` like its siblings).

- [ ] **Step 2: Cubit (test first)**

The repository methods return `FutureResult<T>` like their siblings in `notification_repository.dart`. Cubit (`phone_alerts_cubit.dart` with `part 'phone_alerts_state.dart';`):

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_delivery_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_status_model.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';

part 'phone_alerts_state.dart';

const String kNtfyAppStoreUrl = 'https://apps.apple.com/us/app/ntfy/id1625396347';

class PhoneAlertsCubit extends Cubit<PhoneAlertsState> {
  PhoneAlertsCubit(this._repository, {required this.launch, required this.copy, this.ntfyDeepLink = true})
    : super(const PhoneAlertsState());

  final NotificationRepository _repository;
  final Future<bool> Function(Uri uri) launch;
  final Future<void> Function(String text) copy;
  final bool ntfyDeepLink;

  Future<void> load() async {
    final result = await _repository.getPhoneAlerts();
    result.when(
      onSuccess: (status) => emit(state.copyWith(status: status, error: '')),
      onFailure: (failure) => emit(state.copyWith(error: failure.message)),
    );
  }

  Future<void> subscribe() async {
    emit(state.copyWith(busy: true));
    final result = await _repository.subscribePhoneAlerts();
    String? topic;
    String server = 'https://ntfy.sh';
    result.when(
      onSuccess: (sub) {
        topic = sub.topic;
        server = sub.server ?? server;
      },
      onFailure: (failure) => emit(state.copyWith(busy: false, error: failure.message)),
    );
    if (topic == null || topic!.isEmpty) {
      emit(state.copyWith(busy: false));
      return;
    }
    final host = Uri.parse(server).host;
    final opened = ntfyDeepLink && await launch(Uri.parse('ntfy://$host/$topic'));
    if (!opened) {
      await copy('$server/$topic');
      await launch(Uri.parse(kNtfyAppStoreUrl));
    }
    emit(state.copyWith(busy: false, copiedTopic: !opened));
    await load();
  }

  Future<void> sendTest() async {
    emit(state.copyWith(busy: true));
    final result = await _repository.testPhoneAlert();
    result.when(
      onSuccess: (delivery) => emit(state.copyWith(busy: false, lastTest: delivery)),
      onFailure: (failure) => emit(state.copyWith(busy: false, error: failure.message)),
    );
    await load();
  }
}
```

`phone_alerts_state.dart`:

```dart
part of 'phone_alerts_cubit.dart';

class PhoneAlertsState extends Equatable {
  const PhoneAlertsState({this.status, this.lastTest, this.busy = false, this.copiedTopic = false, this.error = ''});

  final PhoneAlertStatusModel? status;
  final PhoneAlertDeliveryModel? lastTest;
  final bool busy;
  final bool copiedTopic;
  final String error;

  PhoneAlertsState copyWith({
    PhoneAlertStatusModel? status,
    PhoneAlertDeliveryModel? lastTest,
    bool? busy,
    bool? copiedTopic,
    String? error,
  }) => PhoneAlertsState(
    status: status ?? this.status,
    lastTest: lastTest ?? this.lastTest,
    busy: busy ?? this.busy,
    copiedTopic: copiedTopic ?? this.copiedTopic,
    error: error ?? this.error,
  );

  @override
  List<Object?> get props => [status, lastTest, busy, copiedTopic, error];
}
```

Check `Failure`'s message field name in `lib/core/error_handling/failures/failure.dart` and use it. Register with `sl.registerFactory<PhoneAlertsCubit>(() => PhoneAlertsCubit(sl<NotificationRepository>(), launch: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication), copy: (text) => Clipboard.setData(ClipboardData(text: text)), ntfyDeepLink: <Task 0 Step 4 result>))`.

`phone_alerts_cubit_test.dart` (mocktail repository; `Result.success` / `Result.failure` from `result.dart`):

```dart
class _MockRepo extends Mock implements NotificationRepository {}

void main() {
  late _MockRepo repo;
  late List<Uri> launched;
  late List<String> copied;

  PhoneAlertsCubit build({bool deepLinkWorks = true, bool ntfyDeepLink = true}) => PhoneAlertsCubit(
    repo,
    launch: (uri) async {
      launched.add(uri);
      return uri.scheme != 'ntfy' || deepLinkWorks;
    },
    copy: (text) async => copied.add(text),
    ntfyDeepLink: ntfyDeepLink,
  );

  setUp(() {
    repo = _MockRepo();
    launched = [];
    copied = [];
    when(() => repo.getPhoneAlerts()).thenAnswer((_) async => Result.success(const PhoneAlertStatusModel(enabled: true, claimed: true)));
    when(() => repo.subscribePhoneAlerts()).thenAnswer((_) async => Result.success(const PhoneAlertSubscriptionModel(topic: 'abc', server: 'https://ntfy.sh')));
  });

  test('subscribe opens ntfy on the topic when the deep link works', () async {
    final cubit = build();
    await cubit.subscribe();
    expect(launched, [Uri.parse('ntfy://ntfy.sh/abc')]);
    expect(copied, isEmpty);
    expect(cubit.state.status?.claimed, isTrue);
  });

  test('subscribe falls back to copying the topic and opening the App Store', () async {
    final cubit = build(deepLinkWorks: false);
    await cubit.subscribe();
    expect(copied, ['https://ntfy.sh/abc']);
    expect(launched.last, Uri.parse(kNtfyAppStoreUrl));
    expect(cubit.state.copiedTopic, isTrue);
  });

  test('without deep-link support it never tries ntfy://', () async {
    final cubit = build(ntfyDeepLink: false);
    await cubit.subscribe();
    expect(launched.where((u) => u.scheme == 'ntfy'), isEmpty);
    expect(copied, ['https://ntfy.sh/abc']);
  });

  test('sendTest keeps the delivery result', () async {
    when(() => repo.testPhoneAlert()).thenAnswer((_) async => Result.success(const PhoneAlertDeliveryModel(ok: false, error: 'ntfy answered 429')));
    final cubit = build();
    await cubit.sendTest();
    expect(cubit.state.lastTest?.error, 'ntfy answered 429');
  });
}
```

If Task 0 Step 4 showed `ntfy://` does not open a subscribe screen, register the cubit with `ntfyDeepLink: false`.

- [ ] **Step 3: UI group**

`PhoneAlertsGroup` renders a `SettingsGroup(title: 'Phone alerts', footer: <status line>)` with rows:
- "Get ntfy" → launches `https://apps.apple.com/us/app/ntfy/id1625396347`;
- "Subscribe on this phone" → `cubit.subscribe()`; disabled with footer "Turn on Connect Mobile on the desktop first" when `enabled != true`;
- "Send test alert" → `cubit.sendTest()`; disabled unless `enabled && claimed`.

Status line copy: `enabled != true` → "Off — Connect Mobile is off on the desktop"; not claimed → "Not subscribed yet"; last delivery failed → "Last alert failed: <error>"; otherwise "On — alerts arrive through ntfy when Operator is closed".

Insert `PhoneAlertsGroup` in `settings_body.dart` directly above the "Notifications" group; provide the cubit with `BlocProvider(create: (_) => sl<PhoneAlertsCubit>()..load())`. Register the cubit as a factory in `service_locator.dart`. Add `<string>ntfy</string>` to `LSApplicationQueriesSchemes` in `Info.plist` (create the array if absent).

- [ ] **Step 4: Gate and commit**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: green.

```bash
git add -A packages/mobile
git commit -m "feat(mobile): phone alerts settings — install ntfy, subscribe, send a test"
```

---

### Task 12: Docs and real-app verification

**Files:**
- Modify: `CLAUDE.md` (mobile "Deliberately unwired" → remove the Push bullet; add a short "Phone alerts" paragraph under Architecture naming ntfy, `/api/v1/phone-alerts`, and the `notifications` mux channel)
- Modify: `docs/STATUS.md` (notification kinds, OS toast-click activation now delivered on macOS, Expo removed)
- Modify: `docs/superpowers/specs/2026-09-23-agent-alerts-design.md` (Status line → "implemented", link this plan)

- [ ] **Step 1: Docs**

Make the edits above. No other doc churn.

- [ ] **Step 2: Whole-branch gates**

```bash
cd backend && go build ./... && go test -race ./...
cd ../frontend && npm run typecheck && npx vitest run
cd src-tauri && cargo test
cd ../../packages/mobile && flutter analyze && flutter test
```

Expected: all green. Record the counts.

- [ ] **Step 3: Real-app verification (spec §8), with evidence**

Build and install the release desktop app per `RUN_APP_COMMANDS.md` (scrub `CLAUDE*` env first). Install the mobile app on the user's iPhone (`flutter run --release -d <device>` with the phone connected; ask the user to connect it). Then, in order, and record evidence for each (screenshot by window id per the memory note on verifying the desktop, daemon API output, or the user's confirmation for phone-only steps):

1. A session in a background tab finishes a turn → one toast with sound; clicking it opens that session.
2. The same session visible in a focused pane → no toast; the bell lists it.
3. iPhone locked, Connect Mobile on, phone subscribed in ntfy → the ntfy alert arrives; tapping it opens Operator on that session.
4. Operator open on the phone → one local notification, no ntfy duplicate (check `GET /api/v1/phone-alerts` `lastDelivery` did not change).
5. Connect Mobile off → no ntfy message (`lastDelivery` unchanged, ntfy topic web view at `https://ntfy.sh/<topic>` shows nothing new).
6. Kill a session → no "exited" alert anywhere; `kill -9` the agent process of another session → one "exited" alert.
7. Two turns in a row on one session without opening the bell → two alerts (Review Focus 1).
8. Restart the daemon (quit and reopen the app) → the next alert still reaches the phone without re-subscribing (Review Focus 3).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md docs/STATUS.md docs/superpowers/specs/2026-09-23-agent-alerts-design.md
git commit -m "docs: agent alerts shipped — ntfy phone alerts, macOS click-to-open"
```

Then hand back for the whole-branch review and merge (the user's workflow: review, fix, real-app verify, merge `agent-alerts` into `development`, push).
