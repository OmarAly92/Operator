# Mobile Composer Attachments and Permission Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the phone's agent composer a two-row glass field with a **+** that opens an "Add context" sheet (Camera, Photos, Files, recent photos, Permission), send staged attachments with the message, and let the phone read and change a Claude Code session's permission mode live, with new phone spawns defaulting to Bypass.

**Architecture:** The daemon learns the live permission mode from Claude Code's transcript (`permission-mode` records and the `permissionMode` field on user records), stores it as a `permission_mode` block event, and reports it on the session DTO with a `capabilities` object. A new `permission-mode` session command either drives Shift+Tab under the existing exclusive per-session pane drive, confirming each press from the composer footer, or, for a mode outside the Shift+Tab cycle, restarts the agent through the existing `--resume` relaunch path with the new `--permission-mode`. The launch mode becomes a durable session column so resumes keep it. The phone stages files with the existing `POST /sessions/{id}/attachments`, appends the returned paths in the daemon's own reference format, and keeps the draft on any failure.

**Tech Stack:** Go 1.x daemon (chi, sqlc over SQLite, goose migrations, swaggest OpenAPI), Flutter 3.44.5 mobile client (flutter_bloc Cubits, get_it, mocktail, bloc_test), `image_picker`, `file_selector`, new `photo_manager`.

**Spec:** `docs/superpowers/specs/2026-09-26-mobile-composer-attachments-design.md`

**Worktree:** `/Users/omaraly/development/AI/Operator-ios-polish`, branch `feat/mobile-composer-attachments`. Every path below is relative to that worktree. Never touch `/Users/omaraly/development/AI/Operator`.

## Global Constraints

- Authored code carries no comments (Go, Dart, SQL, YAML). Generated files are left as generated.
- Every commit message ends with the trailer line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never stage `frontend/package-lock.json`. Always `git add` explicit paths, never `git add -A` or `git commit -a`.
- The composer glass stays exactly as now: the same `GlassSurface` with `GlassVariant.regular`, `size: TerminalComposer.restHeight`, radius `TerminalComposer.cardRadius` for the card, and the shell composer's capsule behaviour unchanged.
- Colours come only from `context.skin`; durations only from `AppMotion`; honour `MediaQuery.disableAnimationsOf`.
- Mobile: Cubit only, never Bloc with events; static-only classes are `sealed class`; wire models are hand-written with all fields nullable; one params class per data-source method under `data/model/params/`; parameterised paths are static methods on `EndPoints`; feature code never imports `flutter_screenutil`; user-facing copy is inline English; navigation is `Navigator.of(context)`.
- Daemon errors use upper-case codes in the locked envelope `{error, code, message, requestId}` via `envelope.WriteAPIError`. New codes: `PERMISSION_MODE_UNSUPPORTED`, `PERMISSION_MODE_UNCONFIRMED`, `SESSION_COMMAND_MODE_REQUIRED`, `INVALID_PERMISSION_MODE`; `SESSION_BUSY` is reused.
- Limits mirror the daemon exactly: 8 files, 10 MiB each, 25 MiB total, SVG refused (`backend/internal/httpd/controllers/sessions.go:56-69`).
- Permission modes on the wire are Operator's vocabulary: `default`, `accept-edits`, `plan`, `auto`, `bypass-permissions`. Phone labels: Ask, Accept edits, Plan, Auto, Bypass permissions.
- The Shift+Tab drive presses at most 6 times; the version allow-list is exactly `{"2.1.280"}` (the installed and transcript-observed Claude Code version on 2026-09-26).
- Never restart the user's daemon or `tauri:dev` from a task. Never send messages, spawn, kill, or tap Stop on the user's real sessions. The live permission-mode check at the end runs on a scratch session the controller creates.
- Gates after every task that touches them:
  - Backend: `cd backend && go build ./... && go vet ./... && go test ./...` and `cd backend && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs ./...` report nothing.
  - Mobile: `cd packages/mobile && flutter analyze` prints `No issues found!` and `flutter test` passes.
  - API: after any DTO or `build.go` change, regenerate with `cd backend && go generate ./internal/httpd/apispec/... && cd .. && frontend/node_modules/.bin/openapi-typescript backend/internal/httpd/apispec/openapi.yaml -o frontend/src/api/schema.ts`, then byte-check by running the same command a second time and confirming `git diff --stat -- backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts` did not change between the two runs, then `cd backend && go test ./internal/httpd/...`.
  - SQL: after any query or migration change, `npm run sqlc` from the worktree root; never hand-edit `backend/internal/storage/sqlite/gen/*`.
- UI tasks list simulator captures (dark and light) to save under `packages/mobile/build/composer/<task>/`. The controller batches all captures at the end; a task does not boot a simulator.

## Review Focus

1. **The Shift+Tab drive meets a dialog or overshoots.** A press that lands while a permission dialog is open would answer it ("Yes, and switch to accept edits (shift+tab)"). Expected: the drive runs only on an idle session, presses only after a fresh read shows the composer footer, stops the moment the footer reads the target, and stops without pressing again when the footer disappears or the cycle comes back to where it started. Pinned in Task 4 by `TestPermissionModeDriveStopsWhenTheFooterDisappears`, `TestPermissionModeDriveStopsAtTheTargetWithoutOvershoot` and `TestPermissionModeDriveGivesUpWhenTheCycleReturnsToTheStart`.
2. **Restart-with-resume races a turn that is just starting.** A phone send accepted a moment before the restart closed input would be killed mid-turn. Expected: input admission closes first, the daemon waits a settle interval, re-reads the session, and refuses with `SESSION_BUSY` without destroying anything if the agent is no longer idle. Pinned in Task 4 by `TestPermissionModeRestartRefusesATurnThatStartedWhileInputClosed`.
3. **Attachment upload partly fails.** Staging succeeds but the send fails (network drop, `SESSION_BUSY`). Expected: the text and attachments stay in the composer, an inline notice explains why, and a retry reuses the already staged paths instead of writing a second copy of every file. Pinned in Task 7 by `a failed send keeps the draft and a retry reuses the staged paths`.
4. **HEIC and oversized photos.** iPhone photos are HEIC and camera originals can exceed 10 MiB. Expected: camera, library and recent-photo picks are re-encoded to JPEG at 2048 px and quality 85 before admission, anything still over 10 MiB, over 25 MiB in total, over 8 files, or SVG (by MIME or `.svg` name) is refused inline and the rest are kept. Pinned in Task 6 by `admission refuses oversize, overflow, over-count and svg but keeps the rest`, and in Task 8 by `photos are requested as 2048 px quality 85 jpeg`.
5. **The phone shows a stale mode after a desktop-side Shift+Tab.** Expected: the transcript record becomes a `permission_mode` block event that the open composer applies immediately, and a failed phone change reverts to the last mode the daemon observed, not to the value the sheet opened with. Pinned in Task 2 by `TestPermissionModeEventsAreEmittedOnChangeOnly` and in Task 11 by `a desktop-side change arriving as a block event updates the mode` and `a failed change reverts to the last observed mode and says why`.

## Deviations from spec

Each of these was checked against the code on 2026-09-26; the plan follows the code and keeps the spec's intent.

1. **Reference format.** The desktop has no send-with-attachments path: `frontend/src` never calls `/attachments` (only `TaskComposer` uses spawn attachments). The one format the daemon itself uses for spawn and for `/send`'s inline attachment is `appendAttachmentReferences` (`backend/internal/session_manager/manager.go:2936-2951`): the message, a blank line, `Attached files (read these files in the workspace for context):`, then one `- <path>` line per file. The phone uses exactly that format, not bare paths on their own lines.
2. **Spawn cannot set a permission mode today.** `SpawnSessionRequest` has no permission field (`backend/internal/httpd/controllers/dto.go`, spawn controller `sessions.go:300-361`). Task 1 adds `permissionMode` to the spawn body; Task 12 sends `bypass-permissions` from the phone.
3. **The launch mode was not durable.** A spawn override was never stored, and every resume/restore re-applied the project's config (`manager.go:1424`). Task 1 adds a `launch_permission_mode` column (migration 0119), written at spawn and by a mode restart, read by every relaunch. The spec's "falls back to the launch mode" needs this.
4. **No `capabilities` on the session DTO.** It is added as `capabilities: {permissionMode, permissionModeCycle}`. `permissionMode` is true only when the harness has a permission-mode reader and the session's transcript has reported a verified Claude Code version, which happens with the first user turn. Before that the phone hides the Permission row.
5. **Transcript shape.** Checked against real 2.1.270-2.1.280 transcripts under `~/.claude/projects` (redacted shape): `{"type":"permission-mode","permissionMode":"bypassPermissions","sessionId":"…"}` is written at start and immediately on a live change, and has no `version`; `{"type":"user","permissionMode":"auto","version":"2.1.280",…}` carries both. Observed values: `default`, `auto`, `bypassPermissions` (with `acceptEdits` and `plan` from Claude Code's own vocabulary). The mapper reads both record kinds, emits `permission_mode` only on a change of mode or version, and puts `{"mode","version"}` in the event detail (the spec said `{mode}`) because the version gate needs the version and the `permission-mode` record has none. `text` carries the mode.
6. **Trim.** Block events are trimmed to the newest 2000 per session (`daemon.go:152`, `TrimBlockEventsForSession`), which would eventually drop the latest `permission_mode` event. It is exempted from the trim the same way `task_update` is.
7. **Confirmation source.** Each Shift+Tab press is confirmed from the composer footer on the parsed screen ("⏵⏵ accept edits on", "⏸ plan mode on", "⏵⏵ bypass permissions on", "⏵⏵ auto mode on", none for Ask), the same screen reads the task-stop drive uses. The transcript event follows and updates the DTO and the phone.
8. **Cycle membership.** Default → Accept edits → Plan, plus the launch mode when that is Bypass **or Auto** (the repo's own pane fixture shows `⏵⏵ auto mode on (shift+tab to cycle)`, `session_manager/slash_output_test.go:27`). The drive also stops if the cycle comes back to its starting mode, so a wrong cycle guess costs a no-op, never a stray mode.
9. **Cycle drive while working.** The spec only refuses the restart while the agent works. The cycle drive is also refused unless the agent is idle or waiting for input (`SESSION_COMMAND_UNAVAILABLE`, or `SESSION_AWAITING_DECISION` when blocked), because a permission prompt can open between the screen read and the key.
10. **HTTP status for the new codes.** `PERMISSION_MODE_UNSUPPORTED` and `PERMISSION_MODE_UNCONFIRMED` are 409, matching the responses already declared for `sendSessionCommand`.
11. **Trailing buttons.** The agent composer's row 2 ends with the mic (always shown, as a quiet round glyph) followed by one slot that shows Send when there is text or an attachment, Stop when the agent works and the field is empty, and nothing otherwise. Today's agent composer swaps mic and Send in one slot; the shell composer keeps that behaviour unchanged.
12. **Recent photos and HEIC.** The strip loads each photo as a 2048 px, quality 85 JPEG through `photo_manager`, and Camera/Photos pass the same caps to `image_picker`, which re-encodes HEIC to JPEG. Files are sent as picked, with the MIME type inferred from the extension when the platform reports none.
13. **Block timeline.** The phone's block assembly renders any unknown kind as an "Event" notice (`block_assembly.dart:294-300`), so `permission_mode` is explicitly skipped there (Task 11).
14. **The + is not a nested glass layer.** The spec asks for a "round glass +". Nothing in the app nests a liquid-glass layer inside another glass surface, so the **+** is a round button with the same translucent fill as the model chip, drawn inside the composer's own glass; the composer's `GlassSurface` itself is unchanged.
15. **Card at rest.** Two rows cannot fit the 48 pt capsule, so the agent composer always uses the card shape the current composer already grows into (`GlassShapeKind.roundedRect`, radius 26, same glass variant and metrics). The shell composer keeps the 48 pt capsule.

---
## File Structure

### Daemon (`backend/`)

| File | Responsibility | Task |
|---|---|---|
| `internal/domain/agentconfig.go` | `PermissionModePlan`, validation vocabulary | 1 |
| `internal/domain/session.go` | `SessionRecord.LaunchPermissionMode` (durable, `json:"-"`) | 1 |
| `internal/ports/agent.go` | `PermissionModePlan` alias, `NormalizePermissionMode` keeps plan | 1 |
| `internal/adapters/agent/claudecode/claudecode.go` | `--permission-mode plan` | 1 |
| `internal/storage/sqlite/migrations/0119_session_launch_permission_mode.sql` | new column | 1 |
| `internal/storage/sqlite/queries/sessions.sql`, `sqlc.yaml`, `store/session_store.go` | column in insert/selects, `SetSessionLaunchPermissionMode` | 1 |
| `internal/session_manager/manager.go` | seed the launch mode at spawn; relaunches prefer it; a requested mode on relaunch | 1, 4 |
| `internal/httpd/controllers/dto.go`, `sessions.go` | spawn `permissionMode` | 1 |
| `internal/domain/blockevent.go` | `BlockEventPermissionMode` | 2 |
| `internal/domain/permissionmode.go` (new) | `PermissionModeObservation` + detail codec | 2 |
| `internal/adapters/agent/claudecode/transcript.go`, `background_tasks.go` | map `permission-mode` and user `permissionMode` into `permission_mode` events, deduplicated | 2 |
| `internal/storage/sqlite/queries/block_events.sql`, `store/block_event_store.go` | latest-mode queries, trim exemption | 2 |
| `internal/service/blockevent/service.go`, `types.go` | `LatestPermissionMode(s)` | 2 |
| `internal/adapters/agent/claudecode/permission_mode.go` (new) | footer reader, Shift+Tab key, cycle, version allow-list | 3 |
| `internal/ports/agent.go` | `TerminalPermissionModeReader`, `PermissionModeKeys` | 3 |
| `internal/session_manager/permission_mode.go` (new) | `PermissionModeSupport`, `SetPermissionMode`, cycle drive, restart | 3, 4 |
| `internal/httpd/controllers/dto.go`, `sessions.go` | `SessionView.permissionMode`, `capabilities`; `permission-mode` command, error codes | 3, 5 |
| `internal/httpd/api.go`, `internal/daemon/daemon.go`, `lifecycle_wiring.go` | wire the readers and the observer | 3, 5 |
| `internal/domain/sessioncommand.go` | `CommandPermissionMode` | 5 |
| `internal/service/session/service.go` | `SetPermissionMode` passthrough | 5 |
| `internal/httpd/apispec/specgen/build.go`, `openapi.yaml`, `frontend/src/api/schema.ts` | contract | 1, 3, 5 |

### Mobile (`packages/mobile/`)

| File | Responsibility | Task |
|---|---|---|
| `lib/feature/terminal/logic/composer_attachment.dart` (new) | in-memory attachment value | 6 |
| `lib/feature/terminal/logic/attachment_limits.dart` (new) | admission against the daemon's caps, SVG refusal, MIME inference | 6 |
| `lib/feature/terminal/logic/attachment_references.dart` (new) | the daemon's reference format | 6 |
| `lib/feature/terminal/data/model/params/stage_session_attachments_params.dart` (new) | stage body | 6 |
| `lib/feature/terminal/data/model/staged_attachments_model.dart` (new) | stage response | 6 |
| `lib/feature/terminal/data/data_source/terminal_remote_data_source.dart`, `data/repository/terminal_repository.dart` | `stageAttachments` | 6 |
| `lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart` | attachments, staging, send with paths, draft kept on failure | 7 |
| `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart` | two-row agent card; shell capsule unchanged | 9 |
| `lib/feature/terminal/presentation/terminal_screen/ui/widgets/composer_action_button.dart` | `ComposerTrailing`, `ComposerSendSlot` | 9 |
| `lib/feature/terminal/presentation/terminal_screen/ui/widgets/composer_add_button.dart` (new) | round **+** | 9 |
| `lib/feature/terminal/presentation/terminal_screen/ui/widgets/composer_attachment_tray.dart` (new) | thumbnails, file cards, remove, notice | 9 |
| `lib/feature/dictation/ui/mic_key.dart` | `quiet` round style | 9 |
| `lib/feature/terminal/data/data_source/attachment_picker.dart` (new) | Camera, Photos, Files behind one seam | 8 |
| `lib/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart` (new) | the sheet and its tiles | 8, 10, 11 |
| `lib/feature/terminal/data/data_source/recent_photos_data_source.dart` (new), `data/model/recent_photo_model.dart` (new) | `photo_manager` seam | 10 |
| `lib/feature/terminal/presentation/terminal_screen/logic/recent_photos_cubit.dart` (new) | access state and the strip | 10 |
| `lib/feature/terminal/presentation/terminal_screen/ui/widgets/recent_photos_row.dart` (new) | disclosure row and thumbnails | 10 |
| `lib/feature/terminal/logic/permission_modes.dart` (new) | vocabulary, labels, refusals | 11 |
| `lib/feature/terminal/presentation/terminal_screen/logic/permission_mode_cubit.dart` (new) | live mode, choose, revert | 11 |
| `lib/feature/terminal/presentation/terminal_screen/ui/widgets/permission_mode_page.dart` (new) | the pushed page and the row | 11 |
| `lib/feature/sessions/data/model/session_model.dart` | `permissionMode`, capabilities | 11 |
| `lib/feature/blocks/data/model/params/session_command_params.dart`, `session_command_result_model.dart` | `mode`, `permissionMode`, `restarted` | 11 |
| `lib/feature/blocks/logic/block_assembly.dart` | skip `permission_mode` | 11 |
| `lib/feature/spawn/...` | Permission option, Bypass default | 12 |
| `lib/core/utils/service_locator.dart`, `lib/core/app_routes/app_router.dart`, `lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart` | registrations and providers | 8, 10, 11 |
| `pubspec.yaml`, `pubspec.lock`, `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml` | `photo_manager`, usage strings | 8, 10 |

### Docs

`CLAUDE.md` (Mobile client section), `docs/architecture.md` (Transcript block projection), `docs/STATUS.md` (Mobile) — Task 13.

---
### Task 1: `plan` mode, a durable launch mode, and `permissionMode` on spawn

**Files:**
- Modify: `backend/internal/domain/agentconfig.go:13-67`
- Modify: `backend/internal/domain/session.go:75-111` (add one field to `SessionRecord`)
- Modify: `backend/internal/ports/agent.go:558-580`
- Modify: `backend/internal/adapters/agent/claudecode/claudecode.go:454-476`
- Create: `backend/internal/storage/sqlite/migrations/0119_session_launch_permission_mode.sql`
- Modify: `backend/sqlc.yaml` (overrides list)
- Modify: `backend/internal/storage/sqlite/queries/sessions.sql:4-80` and append one query
- Regenerate: `backend/internal/storage/sqlite/gen/*`
- Modify: `backend/internal/storage/sqlite/store/session_store.go` (`rowToRecord`, `recordToInsert`, new setter)
- Modify: `backend/internal/storage/sqlite/migrate_burned_versions_test.go:125`
- Modify: `backend/internal/session_manager/manager.go:579` (spawn seed) and `:1424` (relaunch)
- Modify: `backend/internal/session_manager/manager_test.go:69-76` (`fakeStore.UpdateSession`)
- Modify: `backend/internal/httpd/controllers/dto.go` (`SpawnSessionRequest`), `backend/internal/httpd/controllers/sessions.go:346-355`
- Modify: `backend/internal/cli/project.go:297`
- Regenerate: `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`
- Test: `backend/internal/domain/projectconfig_test.go`, `backend/internal/adapters/agent/claudecode/claudecode_test.go`, `backend/internal/storage/sqlite/store/session_launch_permission_mode_test.go` (new), `backend/internal/session_manager/manager_test.go`, `backend/internal/httpd/controllers/sessions_spawn_permission_test.go` (new)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `domain.PermissionModePlan PermissionMode = "plan"`; `ports.PermissionModePlan`.
  - `domain.SessionRecord.LaunchPermissionMode domain.PermissionMode` (`json:"-"`), always a normalized mode for sessions spawned after this task, `""` for older rows.
  - `func (s *store.Store) SetSessionLaunchPermissionMode(ctx context.Context, id domain.SessionID, mode domain.PermissionMode, updatedAt time.Time) (bool, error)`; `UpdateSession` never writes the column.
  - Relaunches (`restore`, `resume agent`, `relaunch agent`, `restart terminal`) use `rec.LaunchPermissionMode` when it is non-empty, else the project config.
  - `SpawnSessionRequest.PermissionMode string` (`json:"permissionMode,omitempty"`), validated by `domain.PermissionMode.Valid`, error code `INVALID_PERMISSION_MODE`.

- [ ] **Step 1: Write the failing tests**

In `backend/internal/domain/projectconfig_test.go`, add this row to the `TestProjectConfigValidate` table right after `"good agent config"`:

```go
		{"plan permission", ProjectConfig{AgentConfig: AgentConfig{Permissions: PermissionModePlan}}, false},
```

In `backend/internal/adapters/agent/claudecode/claudecode_test.go`, add this row to `TestGetLaunchCommandMapsPermissionModes` after the `"auto"` row:

```go
		{"plan", ports.PermissionModePlan, []string{"--permission-mode", "plan"}, ""},
```

and append:

```go
func TestGetRestoreCommandCarriesPlanMode(t *testing.T) {
	p := &Plugin{resolvedBinary: "claude"}
	cmd, ok, err := p.GetRestoreCommand(context.Background(), ports.RestoreConfig{
		Permissions: ports.PermissionModePlan,
		Session: ports.SessionRef{
			ID:       "s1",
			Metadata: map[string]string{ports.MetadataKeyAgentSessionID: "11111111-2222-3333-4444-555555555555"},
		},
	})
	if err != nil || !ok {
		t.Fatalf("restore command: ok=%v err=%v", ok, err)
	}
	if !containsSubsequence(cmd, []string{"--permission-mode", "plan"}) {
		t.Fatalf("command %#v does not carry plan mode", cmd)
	}
}
```

Create `backend/internal/storage/sqlite/store/session_launch_permission_mode_test.go`:

```go
package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestSessionLaunchPermissionModeRoundTripsAndSurvivesUpdate(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "board")
	now := time.Now().UTC().Truncate(time.Second)
	rec, err := s.CreateSession(ctx, domain.SessionRecord{
		ProjectID:            "board",
		Harness:              domain.HarnessClaudeCode,
		Activity:             domain.Activity{State: domain.ActivityIdle, LastActivityAt: now},
		Metadata:             domain.SessionMetadata{WorkspaceMode: domain.WorkspaceModeWorktree},
		LaunchPermissionMode: domain.PermissionModeBypassPermissions,
		CreatedAt:            now,
		UpdatedAt:            now,
	})
	if err != nil {
		t.Fatal(err)
	}
	got, _, err := s.GetSession(ctx, rec.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.LaunchPermissionMode != domain.PermissionModeBypassPermissions {
		t.Fatalf("launch mode = %q, want bypass-permissions", got.LaunchPermissionMode)
	}

	got.DisplayName = "renamed"
	got.LaunchPermissionMode = domain.PermissionModeDefault
	if err := s.UpdateSession(ctx, got); err != nil {
		t.Fatal(err)
	}
	if again, _, _ := s.GetSession(ctx, rec.ID); again.LaunchPermissionMode != domain.PermissionModeBypassPermissions {
		t.Fatalf("UpdateSession rewrote the launch mode to %q", again.LaunchPermissionMode)
	}

	ok, err := s.SetSessionLaunchPermissionMode(ctx, rec.ID, domain.PermissionModeAuto, now)
	if err != nil || !ok {
		t.Fatalf("set: %v, %v", ok, err)
	}
	listed, err := s.ListSessions(ctx, "board")
	if err != nil || len(listed) != 1 || listed[0].LaunchPermissionMode != domain.PermissionModeAuto {
		t.Fatalf("list = %+v, %v; want the auto launch mode", listed, err)
	}
	all, err := s.ListAllSessions(ctx)
	if err != nil || len(all) != 1 || all[0].LaunchPermissionMode != domain.PermissionModeAuto {
		t.Fatalf("list all = %+v, %v; want the auto launch mode", all, err)
	}
}
```

Append to `backend/internal/session_manager/manager_test.go`:

```go
func TestSpawn_RecordsTheLaunchPermissionMode(t *testing.T) {
	st := newFakeStore()
	st.projects["mer"] = domain.ProjectRecord{ID: "mer", Config: domain.ProjectConfig{Harness: domain.HarnessClaudeCode}}
	agent := &recordingAgent{}
	m := New(Deps{Runtime: &fakeRuntime{}, Agents: singleAgent{agent: agent}, Workspace: &fakeWorkspace{}, Store: st, Messenger: &fakeMessenger{}, Lifecycle: &fakeLCM{store: st}, LookPath: func(string) (string, error) { return "/bin/true", nil }})

	rec, _, _, err := m.Spawn(ctx, ports.SpawnConfig{ProjectID: "mer", AgentConfig: ports.AgentConfig{Permissions: domain.PermissionModeBypassPermissions}})
	if err != nil {
		t.Fatal(err)
	}
	if got := st.sessions[rec.ID].LaunchPermissionMode; got != domain.PermissionModeBypassPermissions {
		t.Fatalf("launch mode = %q, want bypass-permissions", got)
	}
	if agent.lastLaunch.Permissions != domain.PermissionModeBypassPermissions {
		t.Fatalf("launch permissions = %q, want bypass-permissions", agent.lastLaunch.Permissions)
	}
}

func TestSpawn_RecordsDefaultWhenNothingIsConfigured(t *testing.T) {
	m, st, _, _ := newManager()

	rec, _, _, err := m.Spawn(ctx, ports.SpawnConfig{ProjectID: "mer"})
	if err != nil {
		t.Fatal(err)
	}
	if got := st.sessions[rec.ID].LaunchPermissionMode; got != domain.PermissionModeDefault {
		t.Fatalf("launch mode = %q, want default", got)
	}
}

func TestRestore_PrefersTheSessionLaunchPermissionMode(t *testing.T) {
	st := newFakeStore()
	st.projects["mer"] = domain.ProjectRecord{ID: "mer", Config: domain.ProjectConfig{
		AgentConfig: domain.AgentConfig{Permissions: domain.PermissionModeBypassPermissions},
	}}
	st.sessions["mer-1"] = domain.SessionRecord{
		ID:                   "mer-1",
		ProjectID:            "mer",
		IsTerminated:         true,
		LaunchPermissionMode: domain.PermissionModePlan,
		Metadata:             domain.SessionMetadata{Branch: "opr/mer-1", WorkspacePath: "/tmp/ws", AgentSessionID: "native-1"},
	}
	agent := &recordingAgent{}
	m := New(Deps{Runtime: &fakeRuntime{}, Agents: singleAgent{agent: agent}, Workspace: &fakeWorkspace{}, Store: st, Messenger: &fakeMessenger{}, Lifecycle: &fakeLCM{store: st}, LookPath: func(string) (string, error) { return "/bin/true", nil }})

	if _, err := m.RestoreWithMode(ctx, "mer-1", ports.PaneGrid{}); err != nil {
		t.Fatal(err)
	}
	if agent.lastRestore.Permissions != domain.PermissionModePlan {
		t.Fatalf("restore permissions = %q, want the session's plan launch mode", agent.lastRestore.Permissions)
	}
}
```

Create `backend/internal/httpd/controllers/sessions_spawn_permission_test.go`:

```go
package controllers_test

import (
	"net/http"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestSpawnForwardsThePermissionMode(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions", `{"projectId":"opr","permissionMode":"bypass-permissions"}`)
	if status != http.StatusCreated {
		t.Fatalf("status = %d, want 201; body=%s", status, body)
	}
	if got := svc.lastSpawnConfig.AgentConfig.Permissions; got != domain.PermissionModeBypassPermissions {
		t.Fatalf("spawn permissions = %q, want bypass-permissions", got)
	}
}

func TestSpawnWithoutAPermissionModeLeavesTheProjectDefault(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions", `{"projectId":"opr"}`)
	if status != http.StatusCreated {
		t.Fatalf("status = %d, want 201; body=%s", status, body)
	}
	if got := svc.lastSpawnConfig.AgentConfig.Permissions; got != "" {
		t.Fatalf("spawn permissions = %q, want empty", got)
	}
}

func TestSpawnRejectsAnUnknownPermissionMode(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions", `{"projectId":"opr","permissionMode":"yolo"}`)
	assertErrorCode(t, body, status, http.StatusBadRequest, "INVALID_PERMISSION_MODE")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && go test ./internal/domain/... ./internal/adapters/agent/claudecode/... ./internal/storage/sqlite/store/... ./internal/session_manager/... ./internal/httpd/controllers/... 2>&1 | head -40`
Expected: build failures naming `PermissionModePlan`, `LaunchPermissionMode` and `SetSessionLaunchPermissionMode` as undefined.

- [ ] **Step 3: Add `plan` to the domain and ports vocabulary**

In `backend/internal/domain/agentconfig.go`, add the constant to the block:

```go
	PermissionModeDefault           PermissionMode = "default"
	PermissionModeAcceptEdits       PermissionMode = "accept-edits"
	PermissionModePlan              PermissionMode = "plan"
	PermissionModeAuto              PermissionMode = "auto"
	PermissionModeBypassPermissions PermissionMode = "bypass-permissions"
```

and replace `Valid` and the `Validate` error:

```go
func (m PermissionMode) Valid() bool {
	switch m {
	case "", PermissionModeDefault, PermissionModeAcceptEdits, PermissionModePlan,
		PermissionModeAuto, PermissionModeBypassPermissions:
		return true
	default:
		return false
	}
}
```

```go
	return fmt.Errorf("invalid permissions %q: want one of default, accept-edits, plan, auto, bypass-permissions", c.Permissions)
```

In `backend/internal/ports/agent.go`, add the alias and keep plan through normalization:

```go
	PermissionModeDefault           = domain.PermissionModeDefault
	PermissionModeAcceptEdits       = domain.PermissionModeAcceptEdits
	PermissionModePlan              = domain.PermissionModePlan
	PermissionModeAuto              = domain.PermissionModeAuto
	PermissionModeBypassPermissions = domain.PermissionModeBypassPermissions
```

```go
func NormalizePermissionMode(mode PermissionMode) PermissionMode {
	switch mode {
	case PermissionModeDefault,
		PermissionModeAcceptEdits,
		PermissionModePlan,
		PermissionModeAuto,
		PermissionModeBypassPermissions:
		return mode
	default:
		return PermissionModeDefault
	}
}
```

Other adapters switch on the normalized mode without a `plan` case, so plan falls through to their default behaviour (verified for droid, kilocode, goose, opencode and every `case ports.PermissionModeDefault:` adapter).

In `backend/internal/adapters/agent/claudecode/claudecode.go`, add the case to `appendPermissionFlags`:

```go
	case ports.PermissionModeAcceptEdits:
		*cmd = append(*cmd, "--permission-mode", "acceptEdits")
	case ports.PermissionModePlan:
		*cmd = append(*cmd, "--permission-mode", "plan")
	case ports.PermissionModeAuto:
```

In `backend/internal/cli/project.go:297` change the help text to `"Permission mode: default, accept-edits, plan, auto, bypass-permissions"`.

- [ ] **Step 4: Add the durable launch mode column**

Add the field to `domain.SessionRecord` in `backend/internal/domain/session.go`, right after `ClaudeAccountID`:

```go
	ClaudeAccountID      ClaudeAccountID `json:"claudeAccountId"`
	LaunchPermissionMode PermissionMode  `json:"-"`
```

Create `backend/internal/storage/sqlite/migrations/0119_session_launch_permission_mode.sql`:

```sql
-- +goose Up
ALTER TABLE sessions ADD COLUMN launch_permission_mode TEXT NOT NULL DEFAULT ''
    CHECK (launch_permission_mode IN ('', 'default', 'accept-edits', 'plan', 'auto', 'bypass-permissions'));

-- +goose Down
SELECT 1;
```

Add `119: "0119_session_launch_permission_mode.sql",` after the `118:` line of the ledger map in `backend/internal/storage/sqlite/migrate_burned_versions_test.go`.

In `backend/sqlc.yaml`, add after the `sessions.claude_account_id` override:

```yaml
          - column: "sessions.launch_permission_mode"
            go_type:
              import: "github.com/OmarAly92/operator/backend/internal/domain"
              type: "PermissionMode"
```

In `backend/internal/storage/sqlite/queries/sessions.sql`, replace `InsertSession` with:

```sql
-- name: InsertSession :exec
INSERT INTO sessions (
    id, project_id, num, issue_id, harness, reviewer_harness, display_name,
    activity_state, activity_last_at, first_signal_at, is_terminated,
    branch, workspace_path, workspace_mode, workspace_repo_path, diff_base_sha, diff_base_ref, runtime_handle_id,
    runtime_launch_id, agent_session_id, prompt,
    latest_user_prompt, latest_assistant_update, native_transcript_path,
    preview_url, preview_revision, preview_opened_revision, terminate_on_pr_merge, cleanup_generation, browser_capability_verifier,
    provider_conversation_id, controller_generation,
    created_at, updated_at, is_pinned, pinned_at, auto_inject_review, claude_account_id, launch_permission_mode
) VALUES (
    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
    ?, ?,
    ?, ?, ?, ?, ?, ?, ?
);
```

In `GetSession`, `ListSessionsByProject` and `ListAllSessions`, change the last select line in all three to:

```sql
    agent_report_state, agent_report_reason, agent_report_at, launch_permission_mode
```

and append at the end of the file:

```sql
-- name: SetSessionLaunchPermissionMode :execrows
UPDATE sessions SET launch_permission_mode = ?, updated_at = ? WHERE id = ?;
```

Run: `npm run sqlc` (from the worktree root).
Expected: `backend/internal/storage/sqlite/gen/sessions.sql.go` gains `LaunchPermissionMode domain.PermissionMode` on the three row types and `InsertSessionParams`, plus `SetSessionLaunchPermissionMode`.

In `backend/internal/storage/sqlite/store/session_store.go`:
- in `rowToRecord`, after `AgentReport: agentReportFromRow(...)`, add `LaunchPermissionMode: row.LaunchPermissionMode,`;
- in `recordToInsert` (the function that returns `gen.InsertSessionParams{`), after `ClaudeAccountID: domain.NormalizeClaudeAccountID(rec.ClaudeAccountID),` add `LaunchPermissionMode: rec.LaunchPermissionMode,`;
- leave `recordToUpdate` untouched;
- add after `SetSessionClaudeAccount`:

```go
func (s *Store) SetSessionLaunchPermissionMode(ctx context.Context, id domain.SessionID, mode domain.PermissionMode, updatedAt time.Time) (bool, error) {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	rows, err := s.qw.SetSessionLaunchPermissionMode(ctx, gen.SetSessionLaunchPermissionModeParams{
		LaunchPermissionMode: mode,
		UpdatedAt:            updatedAt,
		ID:                   id,
	})
	if err != nil {
		return false, fmt.Errorf("set launch permission mode for %s: %w", id, err)
	}
	return rows > 0, nil
}
```

- [ ] **Step 5: Seed the launch mode at spawn and prefer it on relaunch**

In `backend/internal/session_manager/manager.go` `Spawn`, replace

```go
	rec, err := m.store.CreateSession(ctx, seedRecord(cfg, m.clock()))
```

with

```go
	seed := seedRecord(cfg, m.clock())
	seed.LaunchPermissionMode = ports.NormalizePermissionMode(applySpawnAgentConfig(effectiveAgentConfig(project.Config), cfg.AgentConfig).Permissions)
	rec, err := m.store.CreateSession(ctx, seed)
```

In `relaunchSessionWithPolicy`, right after `agentConfig := effectiveAgentConfig(project.Config)`:

```go
	if rec.LaunchPermissionMode != "" {
		agentConfig.Permissions = rec.LaunchPermissionMode
	}
```

In `backend/internal/session_manager/manager_test.go`, make the fake mirror the real store's rule:

```go
func (f *fakeStore) UpdateSession(_ context.Context, rec domain.SessionRecord) error {
	prev, ok := f.sessions[rec.ID]
	if ok {
		rec.ClaudeAccountID = prev.ClaudeAccountID
		rec.LaunchPermissionMode = prev.LaunchPermissionMode
	}
	f.sessions[rec.ID] = rec
	return nil
}
```

- [ ] **Step 6: Accept `permissionMode` on spawn**

In `backend/internal/httpd/controllers/dto.go`, add to `SpawnSessionRequest` after `ClaudeAccountID`:

```go
	PermissionMode string `json:"permissionMode,omitempty" enum:"default,accept-edits,plan,auto,bypass-permissions" description:"Starting permission mode for the agent. Omit to use the project's configured mode."`
```

In `backend/internal/httpd/controllers/sessions.go` `spawn`, after the `workspaceMode` block:

```go
	permissionMode := domain.PermissionMode(strings.TrimSpace(in.PermissionMode))
	if !permissionMode.Valid() {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_PERMISSION_MODE",
			"permissionMode must be one of default, accept-edits, plan, auto, bypass-permissions", nil)
		return
	}
```

and add `AgentConfig: ports.AgentConfig{Permissions: permissionMode},` to the `ports.SpawnConfig{...}` literal passed to `c.Svc.Spawn`.

- [ ] **Step 7: Regenerate the API contract**

Run: `cd backend && go generate ./internal/httpd/apispec/... && cd .. && frontend/node_modules/.bin/openapi-typescript backend/internal/httpd/apispec/openapi.yaml -o frontend/src/api/schema.ts && git diff --stat -- backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts`
Expected: both files change (a `permissionMode` enum on `SpawnSessionRequest`). Run the same command again; the `--stat` output must be identical.

- [ ] **Step 8: Run the tests and gates**

Run: `cd backend && go build ./... && go vet ./... && go test ./... && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs ./...`
Expected: all pass, lint prints `0 issues.`

- [ ] **Step 9: Commit**

```bash
git add backend/internal/domain/agentconfig.go backend/internal/domain/session.go backend/internal/domain/projectconfig_test.go \
  backend/internal/ports/agent.go backend/internal/adapters/agent/claudecode/claudecode.go backend/internal/adapters/agent/claudecode/claudecode_test.go \
  backend/internal/storage/sqlite/migrations/0119_session_launch_permission_mode.sql backend/sqlc.yaml \
  backend/internal/storage/sqlite/queries/sessions.sql backend/internal/storage/sqlite/gen \
  backend/internal/storage/sqlite/store/session_store.go backend/internal/storage/sqlite/store/session_launch_permission_mode_test.go \
  backend/internal/storage/sqlite/migrate_burned_versions_test.go \
  backend/internal/session_manager/manager.go backend/internal/session_manager/manager_test.go \
  backend/internal/httpd/controllers/dto.go backend/internal/httpd/controllers/sessions.go backend/internal/httpd/controllers/sessions_spawn_permission_test.go \
  backend/internal/cli/project.go backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
git commit -m "feat(daemon): plan permission mode, a durable launch mode, and permissionMode on spawn

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 2: Track the live permission mode from the Claude Code transcript

**Files:**
- Modify: `backend/internal/domain/blockevent.go:12-48`
- Create: `backend/internal/domain/permissionmode.go`
- Modify: `backend/internal/adapters/agent/claudecode/transcript.go:12-61` (record field, value map)
- Modify: `backend/internal/adapters/agent/claudecode/background_tasks.go:31-82` (`TranscriptMapper`)
- Modify: `testdata/transcripts/claude_code_edge.expected.json` (line 7 expectation)
- Modify: `backend/internal/storage/sqlite/queries/block_events.sql:27-39` and append two queries
- Regenerate: `backend/internal/storage/sqlite/gen/*`
- Modify: `backend/internal/storage/sqlite/store/block_event_store.go`
- Modify: `backend/internal/service/blockevent/types.go:42-49`, `backend/internal/service/blockevent/service.go:152-165`
- Test: `backend/internal/domain/permissionmode_test.go` (new), `backend/internal/adapters/agent/claudecode/permission_mode_transcript_test.go` (new), `backend/internal/storage/sqlite/store/block_event_permission_mode_test.go` (new), `backend/internal/service/blockevent/service_test.go`

**Interfaces:**
- Consumes: `domain.PermissionModePlan` and the five-mode vocabulary from Task 1.
- Produces:
  - `domain.BlockEventPermissionMode BlockEventKind = "permission_mode"`; the event's `Text` is the Operator mode and its `Detail` is `{"mode":"…","version":"…"}`; `SourceID` is `"permission-mode"`.
  - `type domain.PermissionModeObservation struct { Mode PermissionMode; Version string }` with `func (o PermissionModeObservation) Detail() string` and `func ParsePermissionModeObservation(detail string) (PermissionModeObservation, bool)`.
  - `func (s *blockevent.Service) LatestPermissionModes(ctx context.Context) (map[domain.SessionID]domain.PermissionModeObservation, error)`
  - `func (s *blockevent.Service) LatestPermissionMode(ctx context.Context, id domain.SessionID) (domain.PermissionModeObservation, bool, error)`
  - `blockevent.Store` gains `SelectLatestPermissionModes(ctx) (map[string]string, error)` and `SelectLatestPermissionMode(ctx, sessionID string) (string, bool, error)`; the sqlite store implements both. `permission_mode` rows are exempt from the per-session trim.

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/domain/permissionmode_test.go`:

```go
package domain

import "testing"

func TestPermissionModeObservationRoundTrips(t *testing.T) {
	in := PermissionModeObservation{Mode: PermissionModePlan, Version: "2.1.280"}
	out, ok := ParsePermissionModeObservation(in.Detail())
	if !ok || out != in {
		t.Fatalf("round trip = %+v, %v; want %+v", out, ok, in)
	}
}

func TestPermissionModeObservationRefusesJunk(t *testing.T) {
	for _, detail := range []string{"", "not json", `{"mode":""}`, `{"mode":"yolo"}`} {
		if _, ok := ParsePermissionModeObservation(detail); ok {
			t.Fatalf("detail %q parsed as an observation", detail)
		}
	}
}

func TestParseBlockEventKindKnowsPermissionMode(t *testing.T) {
	if kind, ok := ParseBlockEventKind("permission_mode"); !ok || kind != BlockEventPermissionMode {
		t.Fatalf("ParseBlockEventKind(permission_mode) = %q, %v", kind, ok)
	}
}
```

Create `backend/internal/adapters/agent/claudecode/permission_mode_transcript_test.go`:

```go
package claudecode

import (
	"slices"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func permissionModeObservations(t *testing.T, m *TranscriptMapper, lines ...string) []domain.PermissionModeObservation {
	t.Helper()
	var got []domain.PermissionModeObservation
	for _, line := range lines {
		events, known := m.Map([]byte(line))
		if !known {
			t.Fatalf("line %s was not recognised", line)
		}
		for _, event := range events {
			if event.Kind != domain.BlockEventPermissionMode {
				continue
			}
			observation, ok := domain.ParsePermissionModeObservation(event.Detail)
			if !ok || string(observation.Mode) != event.Text || event.SourceID != "permission-mode" {
				t.Fatalf("malformed permission_mode event %+v", event)
			}
			got = append(got, observation)
		}
	}
	return got
}

func TestPermissionModeEventsAreEmittedOnChangeOnly(t *testing.T) {
	got := permissionModeObservations(t, NewTranscriptMapper(""),
		`{"type":"permission-mode","permissionMode":"bypassPermissions","sessionId":"s-1"}`,
		`{"type":"user","uuid":"u-1","permissionMode":"bypassPermissions","version":"2.1.280","message":{"role":"user","content":"hi"}}`,
		`{"type":"permission-mode","permissionMode":"bypassPermissions","sessionId":"s-1"}`,
		`{"type":"permission-mode","permissionMode":"plan","sessionId":"s-1"}`,
		`{"type":"permission-mode","permissionMode":"acceptEdits","sessionId":"s-1"}`,
		`{"type":"permission-mode","permissionMode":"dontAsk","sessionId":"s-1"}`,
		`{"type":"user","uuid":"u-2","permissionMode":"acceptEdits","version":"2.1.280","message":{"role":"user","content":"next"}}`,
	)
	want := []domain.PermissionModeObservation{
		{Mode: domain.PermissionModeBypassPermissions},
		{Mode: domain.PermissionModeBypassPermissions, Version: "2.1.280"},
		{Mode: domain.PermissionModePlan, Version: "2.1.280"},
		{Mode: domain.PermissionModeAcceptEdits, Version: "2.1.280"},
	}
	if !slices.Equal(got, want) {
		t.Fatalf("observations = %+v, want %+v", got, want)
	}
}

func TestPermissionModeMapsEveryClaudeValue(t *testing.T) {
	for raw, want := range map[string]domain.PermissionMode{
		"default":           domain.PermissionModeDefault,
		"acceptEdits":       domain.PermissionModeAcceptEdits,
		"plan":              domain.PermissionModePlan,
		"auto":              domain.PermissionModeAuto,
		"bypassPermissions": domain.PermissionModeBypassPermissions,
	} {
		got := permissionModeObservations(t, NewTranscriptMapper(""), `{"type":"permission-mode","permissionMode":"`+raw+`","sessionId":"s-1"}`)
		if len(got) != 1 || got[0].Mode != want {
			t.Fatalf("%s mapped to %+v, want %s", raw, got, want)
		}
	}
}

func TestPermissionModeIsNotReadFromASubagent(t *testing.T) {
	got := permissionModeObservations(t, NewTranscriptMapper("agent-1"),
		`{"type":"user","isSidechain":true,"agentId":"agent-1","uuid":"u-3","permissionMode":"plan","version":"2.1.280","message":{"role":"user","content":"sub"}}`,
	)
	if len(got) != 0 {
		t.Fatalf("a subagent record reported a session mode: %+v", got)
	}
}
```

Create `backend/internal/storage/sqlite/store/block_event_permission_mode_test.go`:

```go
package store_test

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
)

func TestLatestPermissionModeSurvivesTheTrim(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)
	insert := func(sessionID string, kind domain.BlockEventKind, text, detail string) {
		t.Helper()
		if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
			SessionID: sessionID, SourceID: string(kind), Kind: kind, Text: text, Detail: detail, CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("insert: %v", err)
		}
	}
	insert("s-1", domain.BlockEventPermissionMode, "auto", `{"mode":"auto","version":"2.1.280"}`)
	insert("s-1", domain.BlockEventPermissionMode, "plan", `{"mode":"plan","version":"2.1.280"}`)
	insert("s-2", domain.BlockEventPermissionMode, "default", `{"mode":"default"}`)
	for range 10 {
		insert("s-1", domain.BlockEventToolComplete, "ok", "")
	}
	if _, err := s.TrimBlockEvents(ctx, "s-1", "", 3); err != nil {
		t.Fatalf("trim: %v", err)
	}

	detail, ok, err := s.SelectLatestPermissionMode(ctx, "s-1")
	if err != nil || !ok || !strings.Contains(detail, `"plan"`) {
		t.Fatalf("latest = %q, %v, %v; want the plan detail", detail, ok, err)
	}
	if _, ok, err := s.SelectLatestPermissionMode(ctx, "s-3"); err != nil || ok {
		t.Fatalf("unknown session = %v, %v; want not found", ok, err)
	}
	all, err := s.SelectLatestPermissionModes(ctx)
	if err != nil || !strings.Contains(all["s-1"], `"plan"`) || !strings.Contains(all["s-2"], `"default"`) {
		t.Fatalf("all = %+v, %v", all, err)
	}
	events, err := s.SelectBlockEventsBySession(ctx, "s-1", "", 0, 100)
	if err != nil {
		t.Fatal(err)
	}
	tools := 0
	for _, event := range events {
		if event.Kind == domain.BlockEventToolComplete {
			tools++
		}
	}
	if tools != 3 {
		t.Fatalf("tool events after trim = %d, want 3", tools)
	}
}
```

In `backend/internal/service/blockevent/service_test.go`, add a field `permissionModes map[string]string` to `fakeStore`, these methods to `fakeStore`:

```go
func (f *fakeStore) SelectLatestPermissionModes(context.Context) (map[string]string, error) {
	return f.permissionModes, nil
}

func (f *fakeStore) SelectLatestPermissionMode(_ context.Context, sessionID string) (string, bool, error) {
	detail, ok := f.permissionModes[sessionID]
	return detail, ok, nil
}
```

these to `concurrentStore`:

```go
func (s *concurrentStore) SelectLatestPermissionModes(context.Context) (map[string]string, error) {
	return nil, nil
}

func (s *concurrentStore) SelectLatestPermissionMode(context.Context, string) (string, bool, error) {
	return "", false, nil
}
```

and append:

```go
func TestLatestPermissionModesDecodeTheDetail(t *testing.T) {
	store := &fakeStore{permissionModes: map[string]string{
		"s-1": `{"mode":"plan","version":"2.1.280"}`,
		"s-2": `not json`,
	}}
	svc := NewService(store, nil, 500)

	modes, err := svc.LatestPermissionModes(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if got := modes["s-1"]; got != (domain.PermissionModeObservation{Mode: domain.PermissionModePlan, Version: "2.1.280"}) {
		t.Fatalf("s-1 = %+v", got)
	}
	if _, ok := modes["s-2"]; ok {
		t.Fatal("an unreadable detail became an observation")
	}
	one, ok, err := svc.LatestPermissionMode(context.Background(), "s-1")
	if err != nil || !ok || one.Mode != domain.PermissionModePlan {
		t.Fatalf("one = %+v, %v, %v", one, ok, err)
	}
	if _, ok, err := svc.LatestPermissionMode(context.Background(), "s-9"); err != nil || ok {
		t.Fatalf("missing = %v, %v", ok, err)
	}
}

func TestRecordTranscriptKeepsThePermissionModeDetail(t *testing.T) {
	store, pub := &fakeStore{}, &fakePublisher{}
	svc := NewService(store, pub, 500)
	detail := `{"mode":"plan","version":"2.1.280"}`

	err := svc.RecordTranscript(context.Background(), "s-1", "claude-code", domain.BlockTranscriptEvent{
		Kind: domain.BlockEventPermissionMode, SourceID: "permission-mode", Text: "plan", Detail: detail,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(store.inserted) != 1 || store.inserted[0].Detail != detail || store.inserted[0].Text != "plan" {
		t.Fatalf("inserted = %+v", store.inserted)
	}
	if len(pub.published) != 1 {
		t.Fatalf("published %d events, want 1", len(pub.published))
	}
}
```

In `testdata/transcripts/claude_code_edge.expected.json`, replace the seventh entry of `lines` (index 6, the `permission-mode` record, currently `{"known": true, "events": []}`) with:

```json
{"known": true, "events": [{"kind": "permission_mode", "sourceId": "permission-mode", "text": "bypass-permissions"}]}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && go test ./internal/domain/... ./internal/adapters/agent/claudecode/... ./internal/storage/sqlite/store/... ./internal/service/blockevent/... 2>&1 | head -40`
Expected: build failures naming `BlockEventPermissionMode`, `ParsePermissionModeObservation`, `SelectLatestPermissionMode` and `LatestPermissionModes` as undefined.

- [ ] **Step 3: Add the domain kind and observation**

In `backend/internal/domain/blockevent.go`, add `BlockEventPermissionMode BlockEventKind = "permission_mode"` after `BlockEventTaskUpdate`, and add `BlockEventPermissionMode` to the `case` list in `ParseBlockEventKind` after `BlockEventTaskUpdate`.

Create `backend/internal/domain/permissionmode.go`:

```go
package domain

import "encoding/json"

type PermissionModeObservation struct {
	Mode    PermissionMode `json:"mode"`
	Version string         `json:"version,omitempty"`
}

func (o PermissionModeObservation) Detail() string {
	encoded, err := json.Marshal(o)
	if err != nil {
		return ""
	}
	return string(encoded)
}

func ParsePermissionModeObservation(detail string) (PermissionModeObservation, bool) {
	var observation PermissionModeObservation
	if err := json.Unmarshal([]byte(detail), &observation); err != nil {
		return PermissionModeObservation{}, false
	}
	if observation.Mode == "" || !observation.Mode.Valid() {
		return PermissionModeObservation{}, false
	}
	return observation, true
}
```

- [ ] **Step 4: Map the transcript records**

In `backend/internal/adapters/agent/claudecode/transcript.go`, add `PermissionMode string `json:"permissionMode"`` to `claudeTranscriptRecord` after `Version`, and add below `claudeIgnoredRecordTypes`:

```go
var claudePermissionModes = map[string]domain.PermissionMode{
	"default":           domain.PermissionModeDefault,
	"acceptEdits":       domain.PermissionModeAcceptEdits,
	"plan":              domain.PermissionModePlan,
	"auto":              domain.PermissionModeAuto,
	"bypassPermissions": domain.PermissionModeBypassPermissions,
}
```

Keep `"permission-mode"` in `claudeIgnoredRecordTypes`: it maps to no body block, and the mapper below adds the mode event itself.

In `backend/internal/adapters/agent/claudecode/background_tasks.go`, add three fields to `TranscriptMapper`:

```go
type TranscriptMapper struct {
	agentID     string
	launches    map[string]taskLaunch
	order       []string
	tasks       map[string]knownTask
	seen        map[string]struct{}
	finished    []string
	version     string
	mode        domain.PermissionMode
	modeVersion string
}
```

In `Map`, insert this block right before `if sidechain {`:

```go
	if !sidechain {
		if event, ok := m.permissionModeEvent(rec); ok {
			events = append(events, event)
		}
	}
```

and add the method at the end of the file:

```go
func (m *TranscriptMapper) permissionModeEvent(rec claudeTranscriptRecord) (domain.BlockTranscriptEvent, bool) {
	if version := strings.TrimSpace(rec.Version); version != "" {
		m.version = version
	}
	if rec.Type != "permission-mode" && rec.Type != "user" {
		return domain.BlockTranscriptEvent{}, false
	}
	mode, ok := claudePermissionModes[strings.TrimSpace(rec.PermissionMode)]
	if !ok {
		return domain.BlockTranscriptEvent{}, false
	}
	if mode == m.mode && m.version == m.modeVersion {
		return domain.BlockTranscriptEvent{}, false
	}
	m.mode = mode
	m.modeVersion = m.version
	observation := domain.PermissionModeObservation{Mode: mode, Version: m.version}
	return domain.BlockTranscriptEvent{
		Kind:     domain.BlockEventPermissionMode,
		SourceID: "permission-mode",
		Text:     string(mode),
		Detail:   observation.Detail(),
	}, true
}
```

Add `strings` to the file's imports if it is not already there. The tail primes a fresh mapper from the last 4 MiB before its cursor (`observe/transcript/tail.go:52-76`), so a daemon restart does not re-emit an unchanged mode.

- [ ] **Step 5: Store queries and the trim exemption**

In `backend/internal/storage/sqlite/queries/block_events.sql`, change both `kind <> 'task_update'` conditions of `TrimBlockEventsForSession` to `kind NOT IN ('task_update', 'permission_mode')` (one on `outer_be`, one on `be`), and append:

```sql
-- name: SelectLatestPermissionModes :many
SELECT session_id, detail
FROM block_events
WHERE kind = 'permission_mode'
  AND agent_id = ''
  AND seq IN (
    SELECT MAX(seq) FROM block_events WHERE kind = 'permission_mode' AND agent_id = '' GROUP BY session_id
  );

-- name: SelectLatestPermissionMode :one
SELECT detail
FROM block_events
WHERE session_id = ? AND kind = 'permission_mode' AND agent_id = ''
ORDER BY seq DESC
LIMIT 1;
```

Run: `npm run sqlc`
Expected: `gen/block_events.sql.go` gains `SelectLatestPermissionModes`, `SelectLatestPermissionModesRow` and `SelectLatestPermissionMode`.

In `backend/internal/storage/sqlite/store/block_event_store.go`, add (and import `database/sql` and `errors` if missing):

```go
func (s *Store) SelectLatestPermissionModes(ctx context.Context) (map[string]string, error) {
	rows, err := s.qr.SelectLatestPermissionModes(ctx)
	if err != nil {
		return nil, fmt.Errorf("select latest permission modes: %w", err)
	}
	out := make(map[string]string, len(rows))
	for _, row := range rows {
		out[row.SessionID] = row.Detail
	}
	return out, nil
}

func (s *Store) SelectLatestPermissionMode(ctx context.Context, sessionID string) (string, bool, error) {
	detail, err := s.qr.SelectLatestPermissionMode(ctx, sessionID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("select latest permission mode for %s: %w", sessionID, err)
	}
	return detail, true, nil
}
```

- [ ] **Step 6: Service readers**

Add to the `Store` interface in `backend/internal/service/blockevent/types.go`:

```go
	SelectLatestPermissionModes(ctx context.Context) (map[string]string, error)
	SelectLatestPermissionMode(ctx context.Context, sessionID string) (string, bool, error)
```

Add to `backend/internal/service/blockevent/service.go` after `LatestModels`:

```go
func (s *Service) LatestPermissionModes(ctx context.Context) (map[domain.SessionID]domain.PermissionModeObservation, error) {
	rows, err := s.store.SelectLatestPermissionModes(ctx)
	if err != nil {
		return nil, err
	}
	out := make(map[domain.SessionID]domain.PermissionModeObservation, len(rows))
	for id, detail := range rows {
		if observation, ok := domain.ParsePermissionModeObservation(detail); ok {
			out[domain.SessionID(id)] = observation
		}
	}
	return out, nil
}

func (s *Service) LatestPermissionMode(ctx context.Context, id domain.SessionID) (domain.PermissionModeObservation, bool, error) {
	detail, ok, err := s.store.SelectLatestPermissionMode(ctx, string(id))
	if err != nil || !ok {
		return domain.PermissionModeObservation{}, false, err
	}
	observation, ok := domain.ParsePermissionModeObservation(detail)
	return observation, ok, nil
}
```

- [ ] **Step 7: Run the tests and gates**

Run: `cd backend && go test ./internal/domain/... ./internal/adapters/agent/... ./internal/storage/... ./internal/service/blockevent/... ./internal/observe/...`
Expected: PASS, including `TestMapTranscriptRecordFixtures/claude_code_edge`.

Run: `cd backend && go build ./... && go vet ./... && go test ./... && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs ./...`
Expected: all pass, `0 issues.`

- [ ] **Step 8: Commit**

```bash
git add backend/internal/domain/blockevent.go backend/internal/domain/permissionmode.go backend/internal/domain/permissionmode_test.go \
  backend/internal/adapters/agent/claudecode/transcript.go backend/internal/adapters/agent/claudecode/background_tasks.go \
  backend/internal/adapters/agent/claudecode/permission_mode_transcript_test.go testdata/transcripts/claude_code_edge.expected.json \
  backend/internal/storage/sqlite/queries/block_events.sql backend/internal/storage/sqlite/gen \
  backend/internal/storage/sqlite/store/block_event_store.go backend/internal/storage/sqlite/store/block_event_permission_mode_test.go \
  backend/internal/service/blockevent/types.go backend/internal/service/blockevent/service.go backend/internal/service/blockevent/service_test.go
git commit -m "feat(daemon): record Claude Code's live permission mode as a permission_mode block event

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 3: Claude Code footer reader, capability gate, and `permissionMode`/`capabilities` on the session DTO

**Files:**
- Modify: `backend/internal/ports/agent.go` (after `TerminalTasksPanelReader`, ~line 616)
- Create: `backend/internal/adapters/agent/claudecode/permission_mode.go`
- Create: `backend/internal/session_manager/permission_mode.go`
- Modify: `backend/internal/session_manager/manager.go:266` (one field)
- Modify: `backend/internal/httpd/controllers/dto.go:130-166` (`SessionView`, new `SessionCapabilitiesView`)
- Modify: `backend/internal/httpd/controllers/sessions.go` (interfaces near `SessionModelReader` ~line 150, controller fields ~line 191, `list` ~line 284, `get` ~line 478)
- Modify: `backend/internal/httpd/api.go:41-42,118`
- Modify: `backend/internal/httpd/apispec/specgen/build.go:146` (`schemaNames`)
- Modify: `backend/internal/daemon/lifecycle_wiring.go:123-143` (`sessionLifecycle`), `backend/internal/daemon/daemon.go:409`
- Regenerate: `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`
- Test: `backend/internal/adapters/agent/claudecode/permission_mode_test.go` (new), `backend/internal/session_manager/permission_mode_test.go` (new), `backend/internal/httpd/controllers/sessions_permission_mode_test.go` (new)

**Interfaces:**
- Consumes: `domain.PermissionModeObservation` and `(*blockevent.Service).LatestPermissionModes` from Task 2; `domain.SessionRecord.LaunchPermissionMode` from Task 1.
- Produces:
  - `type ports.PermissionModeKeys struct { Cycle string }`
  - `type ports.TerminalPermissionModeReader interface { ReadPermissionMode(pane string) (PermissionMode, bool); PermissionModeKeys() PermissionModeKeys; PermissionModeCycle(launch PermissionMode) []PermissionMode; PermissionModeVerified(version string) bool }`, implemented by `*claudecode.Plugin` with `Cycle: "\x1b[Z"` and allow-list `{"2.1.280"}`.
  - `func (m *Manager) PermissionModeSupport(harness domain.AgentHarness, launch domain.PermissionMode, version string) (bool, []domain.PermissionMode)`
  - `Manager.permissionModeReader ports.TerminalPermissionModeReader` (test override, nil in production) and `func (m *Manager) permissionModeReaderFor(harness domain.AgentHarness) (ports.TerminalPermissionModeReader, bool)`.
  - Test doubles in package `sessionmanager`: `fakePermissionModeReader{verified string; cycle []domain.PermissionMode}` that reads panes of the form `MODE:<mode>`.
  - Wire: `SessionView.PermissionMode string` (`permissionMode`), `SessionView.Capabilities SessionCapabilitiesView` (`capabilities: {permissionMode: bool, permissionModeCycle?: string[]}`).
  - `controllers.SessionPermissionModeReader`, `controllers.PermissionModeGate`; `httpd.APIDeps.SessionPermissionModes`, `httpd.APIDeps.PermissionModeGate`.

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/adapters/agent/claudecode/permission_mode_test.go`:

```go
package claudecode

import (
	"slices"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

const permissionModeRule = "────────────────────────────────────────────────────────────"

func TestReadPermissionModeFromTheComposerFooter(t *testing.T) {
	box := permissionModeRule + "\n❯ \n" + permissionModeRule + "\n"
	tests := []struct {
		name string
		pane string
		want domain.PermissionMode
		ok   bool
	}{
		{"ask shows no mode line", box + "  ? for shortcuts\n", domain.PermissionModeDefault, true},
		{"accept edits", box + "  ⏵⏵ accept edits on (shift+tab to cycle)\n", domain.PermissionModeAcceptEdits, true},
		{"plan", box + "  ⏸ plan mode on (shift+tab to cycle)\n", domain.PermissionModePlan, true},
		{"bypass", box + "  ⏵⏵ bypass permissions on (shift+tab to cycle)\n", domain.PermissionModeBypassPermissions, true},
		{"auto beside the agents hint", box + "  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents\n                                     87856 tokens\n", domain.PermissionModeAuto, true},
		{"styled bypass under an update notice", box + "\x1b[38;5;220mUpdate available!\x1b[39m\n\x1b[38;5;211m⏵⏵ bypass permissions on\x1b[39m", domain.PermissionModeBypassPermissions, true},
		{"a draft in the composer", permissionModeRule + "\n❯ half a thought\n" + permissionModeRule + "\n  ⏸ plan mode on (shift+tab to cycle)\n", domain.PermissionModePlan, true},
		{"permission dialog", permissionModeRule + "\n Do you want to make this edit to main.go?\n❯ 1. Yes\n  2. Yes, and switch to accept edits (shift+tab)\n  3. No\n", "", false},
		{"dialog option right under a rule", permissionModeRule + "\n❯ 1. Yes\n  2. No\n" + permissionModeRule + "\n", "", false},
		{"no composer on screen", "compiling…\nstill going\n", "", false},
		{"composer without its bottom rule", permissionModeRule + "\n❯ \n", "", false},
	}
	p := &Plugin{}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := p.ReadPermissionMode(tt.pane)
			if got != tt.want || ok != tt.ok {
				t.Fatalf("ReadPermissionMode = %q, %v; want %q, %v", got, ok, tt.want, tt.ok)
			}
		})
	}
}

func TestPermissionModeCycleAddsALaunchModeThatCycles(t *testing.T) {
	p := &Plugin{}
	base := []domain.PermissionMode{domain.PermissionModeDefault, domain.PermissionModeAcceptEdits, domain.PermissionModePlan}
	if got := p.PermissionModeCycle(domain.PermissionModeDefault); !slices.Equal(got, base) {
		t.Fatalf("default launch cycle = %v", got)
	}
	if got := p.PermissionModeCycle(domain.PermissionModeBypassPermissions); !slices.Equal(got, append(slices.Clone(base), domain.PermissionModeBypassPermissions)) {
		t.Fatalf("bypass launch cycle = %v", got)
	}
	if got := p.PermissionModeCycle(domain.PermissionModeAuto); !slices.Equal(got, append(slices.Clone(base), domain.PermissionModeAuto)) {
		t.Fatalf("auto launch cycle = %v", got)
	}
}

func TestPermissionModeIsVerifiedOnlyOnTheCheckedVersion(t *testing.T) {
	p := &Plugin{}
	if !p.PermissionModeVerified("2.1.280") || p.PermissionModeVerified("2.1.279") || p.PermissionModeVerified("") {
		t.Fatal("the allow-list must be exactly 2.1.280")
	}
	if p.PermissionModeKeys().Cycle != "\x1b[Z" {
		t.Fatalf("cycle key = %q, want Shift+Tab", p.PermissionModeKeys().Cycle)
	}
}
```

Create `backend/internal/session_manager/permission_mode_test.go`:

```go
package sessionmanager

import (
	"slices"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakePermissionModeReader struct {
	verified string
	cycle    []domain.PermissionMode
}

func (f fakePermissionModeReader) ReadPermissionMode(pane string) (domain.PermissionMode, bool) {
	mode, ok := strings.CutPrefix(pane, "MODE:")
	if !ok {
		return "", false
	}
	return domain.PermissionMode(mode), true
}

func (fakePermissionModeReader) PermissionModeKeys() ports.PermissionModeKeys {
	return ports.PermissionModeKeys{Cycle: "\x1b[Z"}
}

func (f fakePermissionModeReader) PermissionModeCycle(domain.PermissionMode) []domain.PermissionMode {
	return f.cycle
}

func (f fakePermissionModeReader) PermissionModeVerified(version string) bool {
	return version == f.verified
}

var threeModeCycle = []domain.PermissionMode{domain.PermissionModeDefault, domain.PermissionModeAcceptEdits, domain.PermissionModePlan}

func TestPermissionModeSupportNeedsAVerifiedVersion(t *testing.T) {
	m, _, _, _ := newManager()
	m.permissionModeReader = fakePermissionModeReader{verified: "2.1.280", cycle: threeModeCycle}

	ok, cycle := m.PermissionModeSupport(domain.HarnessClaudeCode, domain.PermissionModeDefault, "2.1.280")
	if !ok || !slices.Equal(cycle, threeModeCycle) {
		t.Fatalf("support = %v, %v", ok, cycle)
	}
	if ok, cycle := m.PermissionModeSupport(domain.HarnessClaudeCode, domain.PermissionModeDefault, "2.1.279"); ok || cycle != nil {
		t.Fatalf("unverified version = %v, %v; want unsupported", ok, cycle)
	}
}

func TestPermissionModeSupportIsOffForAHarnessWithoutAReader(t *testing.T) {
	m, _, _, _ := newManager()
	if ok, _ := m.PermissionModeSupport(domain.HarnessCodex, domain.PermissionModeDefault, "2.1.280"); ok {
		t.Fatal("a harness whose adapter has no reader reported support")
	}
}
```

Create `backend/internal/httpd/controllers/sessions_permission_mode_test.go`:

```go
package controllers_test

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
)

type fakePermissionModes struct {
	modes map[domain.SessionID]domain.PermissionModeObservation
	err   error
}

func (f fakePermissionModes) LatestPermissionModes(context.Context) (map[domain.SessionID]domain.PermissionModeObservation, error) {
	return f.modes, f.err
}

type fakePermissionModeGate struct{ version string }

func (f fakePermissionModeGate) PermissionModeSupport(harness domain.AgentHarness, launch domain.PermissionMode, version string) (bool, []domain.PermissionMode) {
	if harness != domain.HarnessClaudeCode || version != f.version {
		return false, nil
	}
	cycle := []domain.PermissionMode{domain.PermissionModeDefault, domain.PermissionModeAcceptEdits, domain.PermissionModePlan}
	if launch == domain.PermissionModeBypassPermissions {
		cycle = append(cycle, launch)
	}
	return true, cycle
}

func permissionModeServer(t *testing.T, modes fakePermissionModes) *httptest.Server {
	t.Helper()
	svc := newFakeSessionService()
	s := svc.sessions["opr-1"]
	s.Harness = domain.HarnessClaudeCode
	s.LaunchPermissionMode = domain.PermissionModeBypassPermissions
	svc.sessions["opr-1"] = s
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{Sessions: svc, SessionPermissionModes: modes, PermissionModeGate: fakePermissionModeGate{version: "2.1.280"}}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestSessionViewsReportTheObservedPermissionMode(t *testing.T) {
	srv := permissionModeServer(t, fakePermissionModes{modes: map[domain.SessionID]domain.PermissionModeObservation{
		"opr-1": {Mode: domain.PermissionModePlan, Version: "2.1.280"},
	}})

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/opr-1", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d body = %s", status, body)
	}
	var got controllers.SessionResponse
	mustJSON(t, body, &got)
	if got.Session.PermissionMode != "plan" || !got.Session.Capabilities.PermissionMode {
		t.Fatalf("session = %+v", got.Session)
	}
	want := []string{"default", "accept-edits", "plan", "bypass-permissions"}
	if !slices.Equal(got.Session.Capabilities.PermissionModeCycle, want) {
		t.Fatalf("cycle = %v, want %v", got.Session.Capabilities.PermissionModeCycle, want)
	}
}

func TestSessionViewsFallBackToTheLaunchModeBeforeTheTranscriptReports(t *testing.T) {
	srv := permissionModeServer(t, fakePermissionModes{})

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d body = %s", status, body)
	}
	var got controllers.ListSessionsResponse
	mustJSON(t, body, &got)
	if len(got.Sessions) != 1 || got.Sessions[0].PermissionMode != "bypass-permissions" || got.Sessions[0].Capabilities.PermissionMode {
		t.Fatalf("sessions = %+v; want the launch mode and no capability before a version is known", got.Sessions)
	}
}

func TestSessionViewsKeepTheLaunchModeWhenTheReadFails(t *testing.T) {
	srv := permissionModeServer(t, fakePermissionModes{err: errors.New("db closed")})

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions", "")
	if status != http.StatusOK || !strings.Contains(string(body), `"permissionMode":"bypass-permissions"`) {
		t.Fatalf("status = %d body = %s", status, body)
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && go test ./internal/adapters/agent/claudecode/... ./internal/session_manager/... ./internal/httpd/controllers/... 2>&1 | head -40`
Expected: build failures naming `ReadPermissionMode`, `PermissionModeKeys`, `permissionModeReader`, `PermissionModeSupport`, `SessionPermissionModes` and `Capabilities` as undefined.

- [ ] **Step 3: Add the port and the Claude Code reader**

Append to `backend/internal/ports/agent.go` after `TerminalTasksPanelReader`:

```go
type PermissionModeKeys struct {
	Cycle string
}

type TerminalPermissionModeReader interface {
	ReadPermissionMode(pane string) (PermissionMode, bool)
	PermissionModeKeys() PermissionModeKeys
	PermissionModeCycle(launch PermissionMode) []PermissionMode
	PermissionModeVerified(version string) bool
}
```

Create `backend/internal/adapters/agent/claudecode/permission_mode.go`:

```go
package claudecode

import (
	"regexp"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

var _ ports.TerminalPermissionModeReader = (*Plugin)(nil)

var permissionModeFooters = []struct {
	marker string
	mode   domain.PermissionMode
}{
	{"accept edits on", domain.PermissionModeAcceptEdits},
	{"plan mode on", domain.PermissionModePlan},
	{"bypass permissions on", domain.PermissionModeBypassPermissions},
	{"auto mode on", domain.PermissionModeAuto},
}

var permissionModeVerifiedVersions = map[string]struct{}{
	"2.1.280": {},
}

var dialogOptionPrompt = regexp.MustCompile(`^❯\s*\d+\.`)

func (p *Plugin) ReadPermissionMode(pane string) (domain.PermissionMode, bool) {
	lines := tasksPaneLines(pane)
	top := lastPromptLine(lines)
	if top < 0 || dialogOptionPrompt.MatchString(lines[top]) {
		return "", false
	}
	bottom := -1
	for i := top + 1; i < len(lines); i++ {
		if isRule(lines[i]) {
			bottom = i
			break
		}
	}
	if bottom < 0 {
		return "", false
	}
	for _, line := range lines[bottom+1:] {
		lower := strings.ToLower(line)
		for _, footer := range permissionModeFooters {
			if strings.Contains(lower, footer.marker) {
				return footer.mode, true
			}
		}
	}
	return domain.PermissionModeDefault, true
}

func (p *Plugin) PermissionModeKeys() ports.PermissionModeKeys {
	return ports.PermissionModeKeys{Cycle: "\x1b[Z"}
}

func (p *Plugin) PermissionModeCycle(launch domain.PermissionMode) []domain.PermissionMode {
	cycle := []domain.PermissionMode{domain.PermissionModeDefault, domain.PermissionModeAcceptEdits, domain.PermissionModePlan}
	if launch == domain.PermissionModeBypassPermissions || launch == domain.PermissionModeAuto {
		cycle = append(cycle, launch)
	}
	return cycle
}

func (p *Plugin) PermissionModeVerified(version string) bool {
	_, ok := permissionModeVerifiedVersions[strings.TrimSpace(version)]
	return ok
}
```

`tasksPaneLines`, `lastPromptLine` and `isRule` are the existing helpers in `tasks_panel.go`; they strip escapes and blank lines, and `lastPromptLine` only accepts a `❯` line that sits directly under a rule.

- [ ] **Step 4: Manager gate**

In `backend/internal/session_manager/manager.go`, add after `tasksPanelReader ports.TerminalTasksPanelReader`:

```go
	permissionModeReader  ports.TerminalPermissionModeReader
```

Create `backend/internal/session_manager/permission_mode.go`:

```go
package sessionmanager

import (
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func (m *Manager) permissionModeReaderFor(harness domain.AgentHarness) (ports.TerminalPermissionModeReader, bool) {
	if m.permissionModeReader != nil {
		return m.permissionModeReader, true
	}
	agent, found := m.agents.Agent(harness)
	if !found {
		return nil, false
	}
	reader, ok := agent.(ports.TerminalPermissionModeReader)
	return reader, ok
}

func (m *Manager) PermissionModeSupport(harness domain.AgentHarness, launch domain.PermissionMode, version string) (bool, []domain.PermissionMode) {
	reader, ok := m.permissionModeReaderFor(harness)
	if !ok || !reader.PermissionModeVerified(version) {
		return false, nil
	}
	return true, reader.PermissionModeCycle(ports.NormalizePermissionMode(launch))
}
```

- [ ] **Step 5: Session DTO, controller and wiring**

In `backend/internal/httpd/controllers/dto.go`, add before `SessionView`:

```go
type SessionCapabilitiesView struct {
	PermissionMode      bool     `json:"permissionMode" description:"The session's permission mode can be changed through the permission-mode command."`
	PermissionModeCycle []string `json:"permissionModeCycle,omitempty" description:"Modes the command reaches with Shift+Tab. Any other mode restarts the agent with --resume."`
}
```

and add to `SessionView` after `HasSavedPrompt`:

```go
	PermissionMode string                  `json:"permissionMode,omitempty" enum:"default,accept-edits,plan,auto,bypass-permissions" description:"The mode the transcript last reported, or the launch mode before it reports."`
	Capabilities   SessionCapabilitiesView `json:"capabilities"`
```

In `backend/internal/httpd/apispec/specgen/build.go`, add to `schemaNames` after the `ControllersSessionCommandResponse` line:

```go
	"ControllersSessionCapabilitiesView":            "SessionCapabilitiesView",
```

In `backend/internal/httpd/controllers/sessions.go`, add after `SessionModelReader`:

```go
type SessionPermissionModeReader interface {
	LatestPermissionModes(ctx context.Context) (map[domain.SessionID]domain.PermissionModeObservation, error)
}

type PermissionModeGate interface {
	PermissionModeSupport(harness domain.AgentHarness, launch domain.PermissionMode, version string) (bool, []domain.PermissionMode)
}
```

add two fields to `SessionsController`:

```go
	PermissionModes    SessionPermissionModeReader
	PermissionModeGate PermissionModeGate
```

call `c.attachPermissionModes(r.Context(), views)` right after both `c.attachModels(r.Context(), views)` calls (in `list` and in `get`), and add after `attachModels`:

```go
func (c *SessionsController) attachPermissionModes(ctx context.Context, views []SessionView) {
	var observed map[domain.SessionID]domain.PermissionModeObservation
	if c.PermissionModes != nil && len(views) > 0 {
		modes, err := c.PermissionModes.LatestPermissionModes(ctx)
		if err != nil {
			slog.Default().Warn("session permission modes read failed", "err", err)
		} else {
			observed = modes
		}
	}
	for i := range views {
		observation := observed[views[i].ID]
		mode := ports.NormalizePermissionMode(views[i].LaunchPermissionMode)
		if observation.Mode != "" {
			mode = observation.Mode
		}
		views[i].PermissionMode = string(mode)
		if c.PermissionModeGate == nil {
			continue
		}
		supported, cycle := c.PermissionModeGate.PermissionModeSupport(views[i].Harness, views[i].LaunchPermissionMode, observation.Version)
		views[i].Capabilities = SessionCapabilitiesView{PermissionMode: supported, PermissionModeCycle: permissionModeStrings(cycle)}
	}
}

func permissionModeStrings(modes []domain.PermissionMode) []string {
	if len(modes) == 0 {
		return nil
	}
	out := make([]string, 0, len(modes))
	for _, mode := range modes {
		out = append(out, string(mode))
	}
	return out
}
```

In `backend/internal/httpd/api.go`, add to `APIDeps` after `SessionModels`:

```go
	SessionPermissionModes controllers.SessionPermissionModeReader
	PermissionModeGate     controllers.PermissionModeGate
```

and to the `&controllers.SessionsController{...}` literal:

```go
			PermissionModes:    deps.SessionPermissionModes,
			PermissionModeGate: deps.PermissionModeGate,
```

In `backend/internal/daemon/lifecycle_wiring.go`, add to the `sessionLifecycle` interface:

```go
	PermissionModeSupport(harness domain.AgentHarness, launch domain.PermissionMode, version string) (bool, []domain.PermissionMode)
```

In `backend/internal/daemon/daemon.go`, add to the `httpd.APIDeps{...}` literal after `SessionModels: blockEvents,`:

```go
		SessionPermissionModes: blockEvents,
		PermissionModeGate:     sessMgr,
```

- [ ] **Step 6: Regenerate the API contract**

Run: `cd backend && go generate ./internal/httpd/apispec/... && cd .. && frontend/node_modules/.bin/openapi-typescript backend/internal/httpd/apispec/openapi.yaml -o frontend/src/api/schema.ts && git diff --stat -- backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts`
Expected: a new `SessionCapabilitiesView` schema and `permissionMode`/`capabilities` on `ControllersSessionView`. Run it a second time and confirm the `--stat` output is unchanged.

- [ ] **Step 7: Run the tests and gates**

Run: `cd backend && go build ./... && go vet ./... && go test ./... && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs ./...`
Expected: all pass, `0 issues.`

- [ ] **Step 8: Commit**

```bash
git add backend/internal/ports/agent.go backend/internal/adapters/agent/claudecode/permission_mode.go backend/internal/adapters/agent/claudecode/permission_mode_test.go \
  backend/internal/session_manager/manager.go backend/internal/session_manager/permission_mode.go backend/internal/session_manager/permission_mode_test.go \
  backend/internal/httpd/controllers/dto.go backend/internal/httpd/controllers/sessions.go backend/internal/httpd/controllers/sessions_permission_mode_test.go \
  backend/internal/httpd/api.go backend/internal/httpd/apispec/specgen/build.go backend/internal/daemon/lifecycle_wiring.go backend/internal/daemon/daemon.go \
  backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
git commit -m "feat(daemon): report each session's permission mode and whether the phone can change it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 4: `SetPermissionMode` in the session manager — Shift+Tab drive and restart-with-resume

**Files:**
- Modify: `backend/internal/session_manager/permission_mode.go` (from Task 3)
- Modify: `backend/internal/session_manager/manager.go` (Store interface ~line 205, Manager fields ~line 266, `New` ~line 482, `relaunchPolicy` ~line 1383, `relaunchSessionWithPolicy` ~lines 1424 and 1506)
- Modify: `backend/internal/session_manager/manager_test.go` (`fakeStore`)
- Test: `backend/internal/session_manager/permission_mode_test.go`

**Interfaces:**
- Consumes: `ports.TerminalPermissionModeReader`, `permissionModeReaderFor`, `fakePermissionModeReader`, `threeModeCycle` (Task 3); `domain.PermissionModeObservation` (Task 2); `store.SetSessionLaunchPermissionMode` and `rec.LaunchPermissionMode` (Task 1).
- Produces:
  - `var ErrPermissionModeUnsupported, ErrPermissionModeUnconfirmed error` in package `sessionmanager`.
  - `type PermissionModeResult struct { Mode domain.PermissionMode; Restarted bool }`
  - `type PermissionModeObserver interface { LatestPermissionMode(ctx context.Context, id domain.SessionID) (domain.PermissionModeObservation, bool, error) }`
  - `func (m *Manager) SetPermissionModeObserver(observer PermissionModeObserver)`
  - `func (m *Manager) SetPermissionMode(ctx context.Context, id domain.SessionID, target domain.PermissionMode) (PermissionModeResult, error)` — errors: `ErrPermissionModeUnsupported` (no reader, unverified or unknown version, invalid target), `ErrPermissionModeUnconfirmed` (drive could not confirm), `ErrWrongActivityState` (cycle drive while working), `ErrAwaitingDecision` (blocked), `ErrSessionBusy` (restart while working, or another drive/operation owns the session), plus the `commandRecord` errors.
  - `Store.SetSessionLaunchPermissionMode(ctx, id, mode, updatedAt) (bool, error)` on the manager's store interface.
  - Test seams on `Manager`: `permissionModeTiming permissionModeTiming{appear, poll time.Duration}` and `permissionRestartSettle func(context.Context) error`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/internal/session_manager/permission_mode_test.go` (add `context`, `errors` and `time` to its imports):

```go
type fakePermissionModeObserver struct {
	observation domain.PermissionModeObservation
	ok          bool
	err         error
}

func (f fakePermissionModeObserver) LatestPermissionMode(context.Context, domain.SessionID) (domain.PermissionModeObservation, bool, error) {
	return f.observation, f.ok, f.err
}

var verifiedObservation = fakePermissionModeObserver{
	observation: domain.PermissionModeObservation{Mode: domain.PermissionModeDefault, Version: "2.1.280"},
	ok:          true,
}

func newPermissionDriveManager(t *testing.T, state domain.ActivityState, panes ...string) (*Manager, *fakeRuntime) {
	t.Helper()
	m, rt := newCommandTestManager(t, state)
	m.permissionModeReader = fakePermissionModeReader{
		verified: "2.1.280",
		cycle:    append(slices.Clone(threeModeCycle), domain.PermissionModeBypassPermissions),
	}
	m.SetPermissionModeObserver(verifiedObservation)
	m.permissionModeTiming = permissionModeTiming{appear: 20 * time.Millisecond, poll: time.Millisecond}
	rt.panes = panes
	return m, rt
}

func shiftTabs(inputs []string) int {
	count := 0
	for _, input := range inputs {
		if input == "\x1b[Z" {
			count++
		}
	}
	return count
}

func TestPermissionModeDriveStopsAtTheTargetWithoutOvershoot(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle,
		"MODE:default", "MODE:accept-edits", "MODE:plan", "MODE:bypass-permissions")

	result, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if err != nil {
		t.Fatalf("SetPermissionMode: %v", err)
	}
	if result != (PermissionModeResult{Mode: domain.PermissionModePlan}) {
		t.Fatalf("result = %+v", result)
	}
	if len(rt.inputs) != 2 || shiftTabs(rt.inputs) != 2 {
		t.Fatalf("inputs = %q, want exactly two Shift+Tab presses", rt.inputs)
	}
}

func TestPermissionModeDriveIsANoOpWhenAlreadyThere(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:plan")

	result, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if err != nil || result.Mode != domain.PermissionModePlan {
		t.Fatalf("result = %+v, %v", result, err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("inputs = %q, want none", rt.inputs)
	}
}

func TestPermissionModeDriveStopsWhenTheFooterDisappears(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default", "DIALOG")

	_, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if !errors.Is(err, ErrPermissionModeUnconfirmed) {
		t.Fatalf("err = %v, want ErrPermissionModeUnconfirmed", err)
	}
	if len(rt.inputs) != 1 {
		t.Fatalf("inputs = %q, want the single press that preceded the dialog", rt.inputs)
	}
}

func TestPermissionModeDriveNeverPressesWithoutAFooter(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "DIALOG")

	_, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if !errors.Is(err, ErrPermissionModeUnconfirmed) {
		t.Fatalf("err = %v, want ErrPermissionModeUnconfirmed", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("inputs = %q, want none", rt.inputs)
	}
}

func TestPermissionModeDriveGivesUpWhenTheCycleReturnsToTheStart(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default", "MODE:accept-edits", "MODE:default")

	result, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModeBypassPermissions)
	if !errors.Is(err, ErrPermissionModeUnconfirmed) {
		t.Fatalf("err = %v, want ErrPermissionModeUnconfirmed", err)
	}
	if result.Mode != domain.PermissionModeDefault || len(rt.inputs) != 2 {
		t.Fatalf("result = %+v inputs = %q; want back at default after two presses", result, rt.inputs)
	}
}

func TestPermissionModeDriveGivesUpWhenAPressChangesNothing(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default")

	_, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if !errors.Is(err, ErrPermissionModeUnconfirmed) || len(rt.inputs) != 1 {
		t.Fatalf("err = %v inputs = %q; want one unconfirmed press", err, rt.inputs)
	}
}

func TestPermissionModeDrivePressesAtMostSixTimes(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle,
		"MODE:default", "MODE:m1", "MODE:m2", "MODE:m3", "MODE:m4", "MODE:m5", "MODE:m6", "MODE:m7")

	_, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if !errors.Is(err, ErrPermissionModeUnconfirmed) {
		t.Fatalf("err = %v, want ErrPermissionModeUnconfirmed", err)
	}
	if len(rt.inputs) != 6 {
		t.Fatalf("pressed %d times, want 6", len(rt.inputs))
	}
}

func TestPermissionModeDriveIsRefusedWhileTheAgentWorks(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityActive, "MODE:default")

	if _, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan); !errors.Is(err, ErrWrongActivityState) {
		t.Fatalf("err = %v, want ErrWrongActivityState", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("inputs = %q, want none", rt.inputs)
	}
}

func TestPermissionModeDriveWaitsOnABlockedSession(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityBlocked, "MODE:default")

	if _, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan); !errors.Is(err, ErrAwaitingDecision) {
		t.Fatalf("err = %v, want ErrAwaitingDecision", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("inputs = %q, want none", rt.inputs)
	}
}

func TestPermissionModeIsUnsupportedOnAnUnverifiedVersion(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default")
	m.SetPermissionModeObserver(fakePermissionModeObserver{
		observation: domain.PermissionModeObservation{Mode: domain.PermissionModeDefault, Version: "2.1.279"},
		ok:          true,
	})

	if _, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan); !errors.Is(err, ErrPermissionModeUnsupported) {
		t.Fatalf("err = %v, want ErrPermissionModeUnsupported", err)
	}
	if len(rt.inputs) != 0 || rt.outputCalls != 0 {
		t.Fatalf("an unsupported change touched the pane: inputs=%q reads=%d", rt.inputs, rt.outputCalls)
	}
}

func TestPermissionModeIsUnsupportedBeforeTheTranscriptReports(t *testing.T) {
	m, _ := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default")
	m.SetPermissionModeObserver(fakePermissionModeObserver{})

	if _, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan); !errors.Is(err, ErrPermissionModeUnsupported) {
		t.Fatalf("err = %v, want ErrPermissionModeUnsupported", err)
	}
}

func TestPermissionModeRejectsAnUnknownTarget(t *testing.T) {
	m, _ := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default")

	if _, err := m.SetPermissionMode(ctx, "s1", "yolo"); !errors.Is(err, ErrPermissionModeUnsupported) {
		t.Fatalf("err = %v, want ErrPermissionModeUnsupported", err)
	}
}

func newPermissionRestartManager(t *testing.T) (*Manager, *fakeStore, *fakeRuntime, *recordingAgent) {
	t.Helper()
	agent := &recordingAgent{}
	m, st, runtime := newRelaunchManager(t, agent)
	rec := st.sessions["mer-1"]
	rec.Harness = domain.HarnessClaudeCode
	rec.LaunchPermissionMode = domain.PermissionModeDefault
	st.sessions["mer-1"] = rec
	m.permissionModeReader = fakePermissionModeReader{verified: "2.1.280", cycle: threeModeCycle}
	m.SetPermissionModeObserver(verifiedObservation)
	m.permissionRestartSettle = func(context.Context) error { return nil }
	return m, st, runtime, agent
}

func TestPermissionModeRestartResumesWithTheNewMode(t *testing.T) {
	m, st, runtime, agent := newPermissionRestartManager(t)

	result, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeAuto)
	if err != nil {
		t.Fatalf("SetPermissionMode: %v", err)
	}
	if result != (PermissionModeResult{Mode: domain.PermissionModeAuto, Restarted: true}) {
		t.Fatalf("result = %+v", result)
	}
	if agent.restoreCalls != 1 || agent.lastRestore.Permissions != domain.PermissionModeAuto {
		t.Fatalf("restore calls = %d permissions = %q; want one --resume with auto", agent.restoreCalls, agent.lastRestore.Permissions)
	}
	if !slices.Contains(runtime.lastCfg.Argv, "resume") {
		t.Fatalf("relaunch argv = %#v, want the resume command", runtime.lastCfg.Argv)
	}
	if got := st.sessions["mer-1"].LaunchPermissionMode; got != domain.PermissionModeAuto {
		t.Fatalf("launch mode = %q, want auto", got)
	}
	if len(runtime.inputs) != 0 {
		t.Fatalf("a restart typed into the pane: %q", runtime.inputs)
	}
}

func TestPermissionModeRestartsForBypassWhenNotLaunchedWithIt(t *testing.T) {
	m, _, _, agent := newPermissionRestartManager(t)

	result, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeBypassPermissions)
	if err != nil || !result.Restarted || agent.lastRestore.Permissions != domain.PermissionModeBypassPermissions {
		t.Fatalf("result = %+v err = %v permissions = %q", result, err, agent.lastRestore.Permissions)
	}
}

func TestPermissionModeRestartIsRefusedWhileTheAgentWorks(t *testing.T) {
	m, st, runtime, agent := newPermissionRestartManager(t)
	rec := st.sessions["mer-1"]
	rec.Activity.State = domain.ActivityActive
	st.sessions["mer-1"] = rec

	if _, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeAuto); !errors.Is(err, ErrSessionBusy) {
		t.Fatalf("err = %v, want ErrSessionBusy", err)
	}
	if runtime.destroyed != 0 || agent.restoreCalls != 0 {
		t.Fatalf("a refused restart touched the runtime: destroyed=%d restores=%d", runtime.destroyed, agent.restoreCalls)
	}
}

func TestPermissionModeRestartRefusesATurnThatStartedWhileInputClosed(t *testing.T) {
	m, st, runtime, agent := newPermissionRestartManager(t)
	m.permissionRestartSettle = func(context.Context) error {
		if _, ok := m.AcquireSessionInput("mer-1"); ok {
			t.Error("input was admitted while the restart held the session")
		}
		rec := st.sessions["mer-1"]
		rec.Activity.State = domain.ActivityActive
		st.sessions["mer-1"] = rec
		return nil
	}

	if _, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeAuto); !errors.Is(err, ErrSessionBusy) {
		t.Fatalf("err = %v, want ErrSessionBusy", err)
	}
	if runtime.destroyed != 0 || runtime.created != 0 || agent.restoreCalls != 0 {
		t.Fatalf("the restart went ahead: destroyed=%d created=%d restores=%d", runtime.destroyed, runtime.created, agent.restoreCalls)
	}
	if st.sessions["mer-1"].LaunchPermissionMode != domain.PermissionModeDefault {
		t.Fatal("a refused restart rewrote the launch mode")
	}
}

func TestPermissionModeRestartWaitsOnABlockedSession(t *testing.T) {
	m, st, _, _ := newPermissionRestartManager(t)
	rec := st.sessions["mer-1"]
	rec.Activity.State = domain.ActivityBlocked
	st.sessions["mer-1"] = rec

	if _, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeAuto); !errors.Is(err, ErrAwaitingDecision) {
		t.Fatalf("err = %v, want ErrAwaitingDecision", err)
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && go test ./internal/session_manager/ -run 'PermissionMode' 2>&1 | head -30`
Expected: build failures naming `SetPermissionMode`, `SetPermissionModeObserver`, `permissionModeTiming`, `permissionRestartSettle`, `PermissionModeResult`, `ErrPermissionModeUnconfirmed` as undefined.

- [ ] **Step 3: Store seam and manager fields**

In the manager's `Store` interface (`manager.go`), add after `SetSessionClaudeAccount`:

```go
	SetSessionLaunchPermissionMode(ctx context.Context, id domain.SessionID, mode domain.PermissionMode, updatedAt time.Time) (bool, error)
```

In `manager_test.go`, add to `fakeStore`:

```go
func (f *fakeStore) SetSessionLaunchPermissionMode(_ context.Context, id domain.SessionID, mode domain.PermissionMode, _ time.Time) (bool, error) {
	rec, ok := f.sessions[id]
	if !ok {
		return false, nil
	}
	rec.LaunchPermissionMode = mode
	f.sessions[id] = rec
	return true, nil
}
```

Add to the `Manager` struct after `permissionModeReader`:

```go
	permissionModesMu       sync.Mutex
	permissionModes         PermissionModeObserver
	permissionModeTiming    permissionModeTiming
	permissionRestartSettle func(context.Context) error
```

and to the `&Manager{...}` literal in `New`:

```go
		permissionModeTiming:    livePermissionModeTiming,
		permissionRestartSettle: func(ctx context.Context) error { return sleepContext(ctx, permissionRestartSettleDelay) },
```

- [ ] **Step 4: Relaunch carries a requested mode and records it**

Add a field to `relaunchPolicy`:

```go
type relaunchPolicy struct {
	forceFresh  bool
	keepPrompt  bool
	permissions domain.PermissionMode
}
```

(keep the two existing field comments as they are; do not add new ones). In `relaunchSessionWithPolicy`, extend the block added in Task 1:

```go
	if rec.LaunchPermissionMode != "" {
		agentConfig.Permissions = rec.LaunchPermissionMode
	}
	if policy.permissions != "" {
		agentConfig.Permissions = policy.permissions
	}
```

and right after the `if err := m.lcm.MarkSpawned(ctx, rec.ID, metadata); err != nil { ... }` block:

```go
	if policy.permissions != "" {
		if _, err := m.store.SetSessionLaunchPermissionMode(ctx, rec.ID, policy.permissions, m.clock()); err != nil {
			m.logger.Warn("relaunch: record launch permission mode", "sessionID", rec.ID, "error", err)
		}
	}
```

- [ ] **Step 5: Implement `SetPermissionMode`**

Replace `backend/internal/session_manager/permission_mode.go` with:

```go
package sessionmanager

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/service/dialogdriver"
)

var (
	ErrPermissionModeUnsupported = errors.New("session: permission mode cannot be changed for this session")
	ErrPermissionModeUnconfirmed = errors.New("session: the terminal did not confirm the permission mode")
)

const (
	maxPermissionModePresses     = 6
	permissionRestartSettleDelay = 750 * time.Millisecond
)

type permissionModeTiming struct {
	appear time.Duration
	poll   time.Duration
}

var livePermissionModeTiming = permissionModeTiming{appear: 1500 * time.Millisecond, poll: 100 * time.Millisecond}

type PermissionModeResult struct {
	Mode      domain.PermissionMode
	Restarted bool
}

type PermissionModeObserver interface {
	LatestPermissionMode(ctx context.Context, id domain.SessionID) (domain.PermissionModeObservation, bool, error)
}

func (m *Manager) SetPermissionModeObserver(observer PermissionModeObserver) {
	m.permissionModesMu.Lock()
	defer m.permissionModesMu.Unlock()
	m.permissionModes = observer
}

func (m *Manager) permissionModeObserver() PermissionModeObserver {
	m.permissionModesMu.Lock()
	defer m.permissionModesMu.Unlock()
	return m.permissionModes
}

func (m *Manager) permissionModeReaderFor(harness domain.AgentHarness) (ports.TerminalPermissionModeReader, bool) {
	if m.permissionModeReader != nil {
		return m.permissionModeReader, true
	}
	agent, found := m.agents.Agent(harness)
	if !found {
		return nil, false
	}
	reader, ok := agent.(ports.TerminalPermissionModeReader)
	return reader, ok
}

func (m *Manager) PermissionModeSupport(harness domain.AgentHarness, launch domain.PermissionMode, version string) (bool, []domain.PermissionMode) {
	reader, ok := m.permissionModeReaderFor(harness)
	if !ok || !reader.PermissionModeVerified(version) {
		return false, nil
	}
	return true, reader.PermissionModeCycle(ports.NormalizePermissionMode(launch))
}

func (m *Manager) SetPermissionMode(ctx context.Context, id domain.SessionID, target domain.PermissionMode) (PermissionModeResult, error) {
	if target == "" || !target.Valid() {
		return PermissionModeResult{}, ErrPermissionModeUnsupported
	}
	rec, err := m.commandRecord(ctx, id)
	if err != nil {
		return PermissionModeResult{}, err
	}
	reader, ok := m.permissionModeReaderFor(rec.Harness)
	if !ok {
		return PermissionModeResult{}, ErrPermissionModeUnsupported
	}
	observation, err := m.observedPermissionMode(ctx, id)
	if err != nil {
		return PermissionModeResult{}, err
	}
	if !reader.PermissionModeVerified(observation.Version) {
		return PermissionModeResult{}, ErrPermissionModeUnsupported
	}
	if slices.Contains(reader.PermissionModeCycle(ports.NormalizePermissionMode(rec.LaunchPermissionMode)), target) {
		return m.cyclePermissionMode(ctx, id, reader, target)
	}
	return m.restartWithPermissionMode(ctx, id, target)
}

func (m *Manager) observedPermissionMode(ctx context.Context, id domain.SessionID) (domain.PermissionModeObservation, error) {
	observer := m.permissionModeObserver()
	if observer == nil {
		return domain.PermissionModeObservation{}, nil
	}
	observation, _, err := observer.LatestPermissionMode(ctx, id)
	if err != nil {
		return domain.PermissionModeObservation{}, fmt.Errorf("permission mode %s: %w", id, err)
	}
	return observation, nil
}

func (m *Manager) cyclePermissionMode(ctx context.Context, id domain.SessionID, reader ports.TerminalPermissionModeReader, target domain.PermissionMode) (PermissionModeResult, error) {
	end, err := m.beginPaneDrive(ctx, id)
	if err != nil {
		return PermissionModeResult{}, commandDriveError(err)
	}
	defer end()
	rec, err := m.commandRecord(ctx, id)
	if err != nil {
		return PermissionModeResult{}, err
	}
	switch rec.Activity.State {
	case domain.ActivityIdle, domain.ActivityWaitingInput:
	case domain.ActivityBlocked:
		return PermissionModeResult{}, ErrAwaitingDecision
	default:
		return PermissionModeResult{}, ErrWrongActivityState
	}
	screen := runtimeScreen{runtime: m.runtime, handle: runtimeHandle(rec.Metadata)}
	mode, err := drivePermissionMode(ctx, screen, reader, target, m.permissionModeTiming)
	return PermissionModeResult{Mode: mode}, err
}

func drivePermissionMode(ctx context.Context, screen dialogdriver.Screen, reader ports.TerminalPermissionModeReader, target domain.PermissionMode, timing permissionModeTiming) (domain.PermissionMode, error) {
	current, err := awaitPermissionMode(ctx, screen, reader, "", timing)
	if err != nil {
		return "", err
	}
	start := current
	for presses := 0; current != target; presses++ {
		if presses == maxPermissionModePresses {
			return current, ErrPermissionModeUnconfirmed
		}
		if err := screen.Write(ctx, reader.PermissionModeKeys().Cycle); err != nil {
			return current, fmt.Errorf("permission mode: press: %w", err)
		}
		next, err := awaitPermissionMode(ctx, screen, reader, current, timing)
		if err != nil {
			return current, err
		}
		current = next
		if current == start {
			return current, ErrPermissionModeUnconfirmed
		}
	}
	return current, nil
}

func awaitPermissionMode(ctx context.Context, screen dialogdriver.Screen, reader ports.TerminalPermissionModeReader, previous domain.PermissionMode, timing permissionModeTiming) (domain.PermissionMode, error) {
	deadline := time.Now().Add(timing.appear)
	for {
		pane, err := screen.Read(ctx)
		if err != nil {
			return "", fmt.Errorf("permission mode: read: %w", err)
		}
		if mode, ok := reader.ReadPermissionMode(pane); ok && mode != previous {
			return mode, nil
		}
		if time.Now().After(deadline) {
			return "", ErrPermissionModeUnconfirmed
		}
		if err := sleepContext(ctx, timing.poll); err != nil {
			return "", err
		}
	}
}

func (m *Manager) restartWithPermissionMode(ctx context.Context, id domain.SessionID, target domain.PermissionMode) (PermissionModeResult, error) {
	rec, err := m.commandRecord(ctx, id)
	if err != nil {
		return PermissionModeResult{}, err
	}
	if err := permissionRestartAllowed(rec); err != nil {
		return PermissionModeResult{}, err
	}
	if err := m.beginAgentOperation(ctx, id, agentOperationRelaunch); err != nil {
		if errors.Is(err, errAgentOperationInProgress) {
			return PermissionModeResult{}, ErrSessionBusy
		}
		return PermissionModeResult{}, err
	}
	defer m.endAgentOperation(id, agentOperationRelaunch)
	if err := m.permissionRestartSettle(ctx); err != nil {
		return PermissionModeResult{}, err
	}
	rec, err = m.commandRecord(ctx, id)
	if err != nil {
		return PermissionModeResult{}, err
	}
	if err := permissionRestartAllowed(rec); err != nil {
		return PermissionModeResult{}, err
	}
	project, err := m.loadProject(ctx, rec.ProjectID)
	if err != nil {
		return PermissionModeResult{}, fmt.Errorf("permission mode %s: %w", id, err)
	}
	meta := rec.Metadata
	if meta.WorkspacePath == "" || (meta.Branch == "" && project.Kind.WithDefault() != domain.ProjectKindScratch) {
		return PermissionModeResult{}, fmt.Errorf("permission mode %s: %w", id, ErrIncompleteHandle)
	}
	ws := ports.WorkspaceInfo{
		Path:      meta.WorkspacePath,
		Branch:    meta.Branch,
		SessionID: rec.ID,
		ProjectID: rec.ProjectID,
		Mode:      meta.WorkspaceMode,
	}
	handle := ports.RuntimeHandle{ID: meta.RuntimeHandleID}
	if _, err := m.relaunchSessionWithPolicy(ctx, "permission mode", rec, project, ws, &handle, ports.PaneGrid{}, relaunchPolicy{permissions: target}); err != nil {
		return PermissionModeResult{}, err
	}
	return PermissionModeResult{Mode: target, Restarted: true}, nil
}

func permissionRestartAllowed(rec domain.SessionRecord) error {
	switch rec.Activity.State {
	case domain.ActivityIdle, domain.ActivityWaitingInput:
		return nil
	case domain.ActivityBlocked:
		return ErrAwaitingDecision
	default:
		return ErrSessionBusy
	}
}
```

The pane drive (`beginPaneDrive`) takes an input lease and blocks every other lease for the session, so mux keystrokes get an error frame and REST `/send` answers `SESSION_BUSY` while Shift+Tab is being driven (`session_input.go:31-53`, `manager.go:3487-3492`). `beginAgentOperation` closes input admission before the settle, so no send can be admitted between the second activity check and the relaunch.

- [ ] **Step 6: Run the tests and gates**

Run: `cd backend && go test ./internal/session_manager/ -run 'PermissionMode|Relaunch|Restore|Spawn' -v 2>&1 | tail -40`
Expected: every listed test PASS.

Run: `cd backend && go build ./... && go vet ./... && go test ./... && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs ./...`
Expected: all pass, `0 issues.`

- [ ] **Step 7: Commit**

```bash
git add backend/internal/session_manager/permission_mode.go backend/internal/session_manager/permission_mode_test.go \
  backend/internal/session_manager/manager.go backend/internal/session_manager/manager_test.go
git commit -m "feat(daemon): change a session's permission mode by Shift+Tab or a --resume restart

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 5: The `permission-mode` session command over HTTP

**Files:**
- Modify: `backend/internal/domain/sessioncommand.go`
- Modify: `backend/internal/session_manager/command_test.go:106-115` (`TestCommandRejectsUnknownVerb`)
- Modify: `backend/internal/httpd/controllers/dto.go:704-712`
- Modify: `backend/internal/httpd/controllers/sessions.go` (`SessionService` interface ~line 105, `command` ~line 1525, `writeCommandError` ~line 1645)
- Modify: `backend/internal/service/session/service.go` (`commander` ~line 70, passthrough after `Command` ~line 437)
- Modify: `backend/internal/daemon/lifecycle_wiring.go` (`sessionLifecycle`), `backend/internal/daemon/daemon.go:225`
- Modify: `backend/internal/httpd/controllers/sessions_test.go` (`fakeSessionService`), `backend/internal/service/session/service_test.go` (`fakeCommander`)
- Regenerate: `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`
- Test: `backend/internal/httpd/controllers/sessions_command_permission_test.go` (new), `backend/internal/service/session/service_test.go`

**Interfaces:**
- Consumes: `sessionmanager.SetPermissionMode`, `PermissionModeResult`, `ErrPermissionModeUnsupported`, `ErrPermissionModeUnconfirmed`, `SetPermissionModeObserver`, `PermissionModeObserver` (Task 4); `(*blockevent.Service).LatestPermissionMode` (Task 2).
- Produces (wire contract the phone relies on):
  - `domain.CommandPermissionMode SessionCommand = "permission-mode"`.
  - `POST /api/v1/sessions/{id}/command` body `{"command":"permission-mode","mode":"<mode>"}` → 200 `{"state":"sent","permissionMode":"<confirmed mode>","restarted":<bool>}`.
  - 400 `SESSION_COMMAND_MODE_REQUIRED` when `mode` is missing or not one of the five modes; 409 `PERMISSION_MODE_UNSUPPORTED`, `PERMISSION_MODE_UNCONFIRMED`, `SESSION_BUSY`, `SESSION_AWAITING_DECISION`, `SESSION_COMMAND_UNAVAILABLE`, `SESSION_NOT_RUNNING`; 404 `SESSION_NOT_FOUND`.
  - `func (s *sessionsvc.Service) SetPermissionMode(ctx context.Context, id domain.SessionID, mode domain.PermissionMode) (sessionmanager.PermissionModeResult, error)`; the same method on `controllers.SessionService`.

- [ ] **Step 1: Write the failing tests**

In `backend/internal/session_manager/command_test.go`, change the verb list in `TestCommandRejectsUnknownVerb` to `[]string{"stop", "compact", "model", "permission-mode"}`.

In `backend/internal/httpd/controllers/sessions_test.go`, add three fields to `fakeSessionService`:

```go
	permissionModeResult  sessionmanager.PermissionModeResult
	permissionModeErr     error
	permissionModeTargets []domain.PermissionMode
```

and the method:

```go
func (f *fakeSessionService) SetPermissionMode(_ context.Context, _ domain.SessionID, mode domain.PermissionMode) (sessionmanager.PermissionModeResult, error) {
	f.permissionModeTargets = append(f.permissionModeTargets, mode)
	return f.permissionModeResult, f.permissionModeErr
}
```

Create `backend/internal/httpd/controllers/sessions_command_permission_test.go`:

```go
package controllers_test

import (
	"net/http"
	"slices"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	sessionmanager "github.com/OmarAly92/operator/backend/internal/session_manager"
)

func TestSessionCommandPermissionModeReportsTheConfirmedMode(t *testing.T) {
	svc := newFakeSessionService()
	svc.permissionModeResult = sessionmanager.PermissionModeResult{Mode: domain.PermissionModePlan}
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/command", `{"command":"permission-mode","mode":"plan"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d body = %s", status, body)
	}
	var got controllers.SessionCommandResponse
	mustJSON(t, body, &got)
	if got.State != "sent" || got.PermissionMode != "plan" || got.Restarted {
		t.Fatalf("response = %+v", got)
	}
	if !slices.Equal(svc.permissionModeTargets, []domain.PermissionMode{domain.PermissionModePlan}) || svc.commandCalls != 0 {
		t.Fatalf("targets = %v commandCalls = %d", svc.permissionModeTargets, svc.commandCalls)
	}
}

func TestSessionCommandPermissionModeReportsARestart(t *testing.T) {
	svc := newFakeSessionService()
	svc.permissionModeResult = sessionmanager.PermissionModeResult{Mode: domain.PermissionModeAuto, Restarted: true}
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/command", `{"command":"permission-mode","mode":"auto"}`)
	var got controllers.SessionCommandResponse
	mustJSON(t, body, &got)
	if status != http.StatusOK || got.PermissionMode != "auto" || !got.Restarted {
		t.Fatalf("status = %d response = %+v", status, got)
	}
}

func TestSessionCommandPermissionModeRequiresAValidMode(t *testing.T) {
	for _, payload := range []string{
		`{"command":"permission-mode"}`,
		`{"command":"permission-mode","mode":"yolo"}`,
		`{"command":"permission-mode","mode":"  "}`,
	} {
		svc := newFakeSessionService()
		srv := newSessionTestServer(t, svc)
		body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/command", payload)
		assertErrorCode(t, body, status, http.StatusBadRequest, "SESSION_COMMAND_MODE_REQUIRED")
		if len(svc.permissionModeTargets) != 0 {
			t.Fatalf("payload %s reached the service", payload)
		}
	}
}

func TestSessionCommandPermissionModeErrorCodes(t *testing.T) {
	tests := []struct {
		err    error
		status int
		code   string
	}{
		{sessionmanager.ErrPermissionModeUnsupported, http.StatusConflict, "PERMISSION_MODE_UNSUPPORTED"},
		{sessionmanager.ErrPermissionModeUnconfirmed, http.StatusConflict, "PERMISSION_MODE_UNCONFIRMED"},
		{sessionmanager.ErrSessionBusy, http.StatusConflict, "SESSION_BUSY"},
		{sessionmanager.ErrAwaitingDecision, http.StatusConflict, "SESSION_AWAITING_DECISION"},
		{sessionmanager.ErrWrongActivityState, http.StatusConflict, "SESSION_COMMAND_UNAVAILABLE"},
		{sessionmanager.ErrAgentExited, http.StatusConflict, "SESSION_NOT_RUNNING"},
		{sessionmanager.ErrNotFound, http.StatusNotFound, "SESSION_NOT_FOUND"},
	}
	for _, tt := range tests {
		t.Run(tt.code, func(t *testing.T) {
			svc := newFakeSessionService()
			svc.permissionModeErr = tt.err
			srv := newSessionTestServer(t, svc)
			body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/command", `{"command":"permission-mode","mode":"auto"}`)
			assertErrorCode(t, body, status, tt.status, tt.code)
		})
	}
}
```

In `backend/internal/service/session/service_test.go`, add to `fakeCommander` a field `permissionModes []domain.PermissionMode` and:

```go
func (f *fakeCommander) SetPermissionMode(_ context.Context, _ domain.SessionID, mode domain.PermissionMode) (sessionmanager.PermissionModeResult, error) {
	f.permissionModes = append(f.permissionModes, mode)
	return sessionmanager.PermissionModeResult{Mode: mode}, nil
}
```

and append:

```go
func TestSetPermissionModeDelegatesToTheManager(t *testing.T) {
	fc := &fakeCommander{}
	svc := NewWithDeps(Deps{Manager: fc})

	result, err := svc.SetPermissionMode(context.Background(), "mer-1", domain.PermissionModePlan)
	if err != nil || result.Mode != domain.PermissionModePlan || len(fc.permissionModes) != 1 {
		t.Fatalf("result = %+v err = %v calls = %v", result, err, fc.permissionModes)
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && go test ./internal/session_manager/ -run TestCommandRejectsUnknownVerb ./internal/httpd/controllers/... ./internal/service/session/... 2>&1 | head -30`
Expected: `expected "permission-mode" to parse`, and build failures for `SetPermissionMode` on the controller and service interfaces and `SessionCommandResponse.PermissionMode`.

- [ ] **Step 3: Domain verb**

Replace `backend/internal/domain/sessioncommand.go` with:

```go
package domain

type SessionCommand string

const (
	CommandStop           SessionCommand = "stop"
	CommandCompact        SessionCommand = "compact"
	CommandModel          SessionCommand = "model"
	CommandPermissionMode SessionCommand = "permission-mode"
)

func ParseSessionCommand(raw string) (SessionCommand, bool) {
	switch SessionCommand(raw) {
	case CommandStop, CommandCompact, CommandModel, CommandPermissionMode:
		return SessionCommand(raw), true
	default:
		return "", false
	}
}
```

- [ ] **Step 4: DTOs**

In `backend/internal/httpd/controllers/dto.go`:

```go
type SessionCommandRequest struct {
	Command string `json:"command" enum:"stop,compact,model,permission-mode"`
	Model   string `json:"model,omitempty"`
	Mode    string `json:"mode,omitempty" enum:"default,accept-edits,plan,auto,bypass-permissions" description:"Target mode for the permission-mode command."`
}

type SessionCommandResponse struct {
	State          string   `json:"state"`
	Models         []string `json:"models,omitempty"`
	PermissionMode string   `json:"permissionMode,omitempty" description:"The mode the terminal confirmed, for the permission-mode command."`
	Restarted      bool     `json:"restarted,omitempty" description:"The permission-mode command restarted the agent with --resume to reach the mode."`
}
```

- [ ] **Step 5: Controller**

In `backend/internal/httpd/controllers/sessions.go`, add to `SessionService` after `Command`:

```go
	SetPermissionMode(ctx context.Context, id domain.SessionID, mode domain.PermissionMode) (sessionmanager.PermissionModeResult, error)
```

In `command`, change the unknown-verb message to `"unknown command; expected one of stop, compact, model, permission-mode"`, and insert right after the model-label check:

```go
	if command == domain.CommandPermissionMode {
		c.permissionModeCommand(w, r, in.Mode)
		return
	}
```

Add below `command`:

```go
func (c *SessionsController) permissionModeCommand(w http.ResponseWriter, r *http.Request, raw string) {
	mode := domain.PermissionMode(strings.TrimSpace(raw))
	if mode == "" || !mode.Valid() {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "validation", "SESSION_COMMAND_MODE_REQUIRED",
			"the permission-mode command requires a mode: one of default, accept-edits, plan, auto, bypass-permissions", nil)
		return
	}
	result, err := c.Svc.SetPermissionMode(r.Context(), sessionID(r), mode)
	if err != nil {
		c.writeCommandError(w, r, err, nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, SessionCommandResponse{
		State:          "sent",
		PermissionMode: string(result.Mode),
		Restarted:      result.Restarted,
	})
}
```

Add two cases to `writeCommandError`, before `case errors.Is(err, sessionmanager.ErrSessionBusy):`:

```go
	case errors.Is(err, sessionmanager.ErrPermissionModeUnsupported):
		envelope.WriteAPIError(w, r, http.StatusConflict, "conflict", "PERMISSION_MODE_UNSUPPORTED",
			"this session's agent cannot change permission mode from here", nil)
	case errors.Is(err, sessionmanager.ErrPermissionModeUnconfirmed):
		envelope.WriteAPIError(w, r, http.StatusConflict, "conflict", "PERMISSION_MODE_UNCONFIRMED",
			"the terminal did not confirm the new permission mode", nil)
```

- [ ] **Step 6: Service passthrough and daemon wiring**

In `backend/internal/service/session/service.go`, add to the `commander` interface after `Command`:

```go
	SetPermissionMode(ctx context.Context, id domain.SessionID, mode domain.PermissionMode) (sessionmanager.PermissionModeResult, error)
```

and after `func (s *Service) Command(...)`:

```go
func (s *Service) SetPermissionMode(ctx context.Context, id domain.SessionID, mode domain.PermissionMode) (sessionmanager.PermissionModeResult, error) {
	return s.manager.SetPermissionMode(ctx, id, mode)
}
```

In `backend/internal/daemon/lifecycle_wiring.go`, add to `sessionLifecycle`:

```go
	SetPermissionModeObserver(observer sessionmanager.PermissionModeObserver)
```

In `backend/internal/daemon/daemon.go`, right after `lifecycleMessenger.Bind(sessionLifecycleMessenger{sessMgr})`:

```go
	sessMgr.SetPermissionModeObserver(blockEvents)
```

- [ ] **Step 7: Regenerate the API contract**

Run: `cd backend && go generate ./internal/httpd/apispec/... && cd .. && frontend/node_modules/.bin/openapi-typescript backend/internal/httpd/apispec/openapi.yaml -o frontend/src/api/schema.ts && git diff --stat -- backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts`
Expected: `SessionCommandRequest` gains `mode` and the command enum, `SessionCommandResponse` gains `permissionMode` and `restarted`. Run it again; the `--stat` output must not change.

- [ ] **Step 8: Run the tests and gates**

Run: `cd backend && go build ./... && go vet ./... && go test ./... && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs ./...`
Expected: all pass, `0 issues.`

- [ ] **Step 9: Commit**

```bash
git add backend/internal/domain/sessioncommand.go backend/internal/session_manager/command_test.go \
  backend/internal/httpd/controllers/dto.go backend/internal/httpd/controllers/sessions.go \
  backend/internal/httpd/controllers/sessions_test.go backend/internal/httpd/controllers/sessions_command_permission_test.go \
  backend/internal/service/session/service.go backend/internal/service/session/service_test.go \
  backend/internal/daemon/lifecycle_wiring.go backend/internal/daemon/daemon.go \
  backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
git commit -m "feat(daemon): permission-mode session command with its error codes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 6: Mobile attachment data layer — admission, reference format, stage endpoint

**Files:**
- Create: `packages/mobile/lib/feature/terminal/logic/composer_attachment.dart`
- Create: `packages/mobile/lib/feature/terminal/logic/attachment_limits.dart`
- Create: `packages/mobile/lib/feature/terminal/logic/attachment_references.dart`
- Create: `packages/mobile/lib/feature/terminal/data/model/params/stage_session_attachments_params.dart`
- Create: `packages/mobile/lib/feature/terminal/data/model/staged_attachments_model.dart`
- Modify: `packages/mobile/lib/feature/terminal/data/data_source/terminal_remote_data_source.dart`
- Modify: `packages/mobile/lib/feature/terminal/data/repository/terminal_repository.dart`
- Test: `packages/mobile/test/feature/terminal/logic/attachment_limits_test.dart` (new), `packages/mobile/test/feature/terminal/logic/attachment_references_test.dart` (new), `packages/mobile/test/feature/terminal/data/data_source/terminal_remote_data_source_test.dart`, `packages/mobile/test/feature/terminal/data/repository/terminal_repository_test.dart`

**Interfaces:**
- Consumes: the daemon's existing `POST /api/v1/sessions/{id}/attachments` (`{attachments:[{mimeType,data}]}` → 201 `{sessionId, paths}`) and `EndPoints.sessionAttachments(sessionId)`.
- Produces:
  - `class ComposerAttachment { const ComposerAttachment({required String id, required String name, required String mimeType, required Uint8List bytes}); bool get isImage; int get size; }`
  - `sealed class AttachmentLimits { static const int maxCount = 8; static const int maxBytes = 10485760; static const int maxTotalBytes = 26214400; }`
  - `class AttachmentAdmission { final List<ComposerAttachment> accepted; final String? notice; }` and `AttachmentAdmission admitAttachments(List<ComposerAttachment> current, List<ComposerAttachment> incoming)`
  - `bool isBlockedAttachment({required String name, required String mimeType})`, `String attachmentMimeType(String name, String? reported)`
  - Notices: `kSvgRefused`, `kFileTooLarge`, `kTooManyFiles`, `kTotalTooLarge`, `kEmptyFile`.
  - `const String kAttachedFilesHeader` and `String appendAttachmentReferences(String message, List<String> paths)`
  - `StageSessionAttachmentsParams({required List<ComposerAttachment> files})` with `toJson()`; `StagedAttachmentsModel({String? sessionId, List<String>? paths})`.
  - `TerminalRemoteDataSource.stageAttachments(String sessionId, StageSessionAttachmentsParams params) → Future<GlobalResponse<StagedAttachmentsModel>>`; `TerminalRepository.stageAttachments(...) → FutureResult<GlobalResponse<StagedAttachmentsModel>>`.

- [ ] **Step 1: Write the failing tests**

Create `packages/mobile/test/feature/terminal/logic/attachment_limits_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_limits.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

ComposerAttachment file(String id, int size, {String? name, String mimeType = 'image/png'}) =>
    ComposerAttachment(id: id, name: name ?? '$id.png', mimeType: mimeType, bytes: Uint8List(size));

void main() {
  test('admission refuses oversize, overflow, over-count and svg but keeps the rest', () {
    final current = [for (var i = 0; i < 6; i++) file('c$i', 1024)];
    final admission = admitAttachments(current, [
      file('big', AttachmentLimits.maxBytes + 1),
      file('vector', 10, name: 'logo.svg', mimeType: 'application/octet-stream'),
      file('mime-svg', 10, mimeType: 'image/svg+xml'),
      file('ok-1', 1024),
      file('ok-2', 1024),
      file('ninth', 1024),
    ]);

    expect(admission.accepted.map((a) => a.id), ['ok-1', 'ok-2']);
    expect(admission.notice, contains(kFileTooLarge));
    expect(admission.notice, contains(kSvgRefused));
    expect(admission.notice, contains(kTooManyFiles));
  });

  test('the running total may not pass 25 MB', () {
    final nine = AttachmentLimits.maxBytes - 1;
    final admission = admitAttachments([file('a', nine), file('b', nine)], [file('c', nine)]);

    expect(admission.accepted, isEmpty);
    expect(admission.notice, kTotalTooLarge);
  });

  test('a file exactly at the per-file cap is accepted', () {
    final admission = admitAttachments(const [], [file('edge', AttachmentLimits.maxBytes)]);
    expect(admission.accepted.single.id, 'edge');
    expect(admission.notice, isNull);
  });

  test('an empty file and a duplicate are dropped', () {
    final admission = admitAttachments([file('same', 10)], [file('same', 10), file('empty', 0)]);
    expect(admission.accepted, isEmpty);
    expect(admission.notice, kEmptyFile);
  });

  test('the mime type falls back to the extension', () {
    expect(attachmentMimeType('scan.PDF', null), 'application/pdf');
    expect(attachmentMimeType('IMG_0001.HEIC', ''), 'image/heic');
    expect(attachmentMimeType('notes.md', 'application/octet-stream'), 'text/markdown');
    expect(attachmentMimeType('photo.jpg', 'image/jpeg'), 'image/jpeg');
    expect(attachmentMimeType('README', null), 'application/octet-stream');
  });

  test('an svg is blocked by name or by type', () {
    expect(isBlockedAttachment(name: 'a.SVG', mimeType: 'application/octet-stream'), isTrue);
    expect(isBlockedAttachment(name: 'a', mimeType: 'image/svg+xml'), isTrue);
    expect(isBlockedAttachment(name: 'a.png', mimeType: 'image/png'), isFalse);
  });
}
```

Create `packages/mobile/test/feature/terminal/logic/attachment_references_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_references.dart';

void main() {
  test('the references follow the text after a blank line, one path per line', () {
    expect(
      appendAttachmentReferences('look at this', ['.operator/attachments/attachment-aa.png', '.operator/attachments/attachment-bb.pdf']),
      'look at this\n\n'
      'Attached files (read these files in the workspace for context):\n'
      '- .operator/attachments/attachment-aa.png\n'
      '- .operator/attachments/attachment-bb.pdf',
    );
  });

  test('an attachment-only message is just the reference block', () {
    expect(
      appendAttachmentReferences('   ', ['.operator/attachments/attachment-aa.png']),
      'Attached files (read these files in the workspace for context):\n- .operator/attachments/attachment-aa.png',
    );
  });

  test('no paths leaves the message alone', () {
    expect(appendAttachmentReferences('hello', const []), 'hello');
  });
}
```

Append to `packages/mobile/test/feature/terminal/data/data_source/terminal_remote_data_source_test.dart` inside `main()` (add imports for `dart:typed_data`, `stage_session_attachments_params.dart` and `composer_attachment.dart`):

```dart
  test('stages attachments as base64 with their mime type and reads back the paths', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => _response({
        'sessionId': 's-1',
        'paths': ['.operator/attachments/attachment-aa.png'],
      }),
    );

    final staged = (await dataSource.stageAttachments(
      's-1',
      StageSessionAttachmentsParams(files: [
        ComposerAttachment(id: 'a', name: 'a.png', mimeType: 'image/png', bytes: Uint8List.fromList([1, 2, 3])),
      ]),
    )).data!;

    expect(staged.paths, ['.operator/attachments/attachment-aa.png']);
    final body = verify(
      () => apiConsumer.post(EndPoints.sessionAttachments('s-1'), body: captureAny(named: 'body')),
    ).captured.single as Map<String, dynamic>;
    expect(body, {
      'attachments': [
        {'mimeType': 'image/png', 'data': 'AQID'},
      ],
    });
  });
```

Append to `packages/mobile/test/feature/terminal/data/repository/terminal_repository_test.dart` inside `main()` (register `StageSessionAttachmentsParams(files: const [])` as a fallback in `setUpAll`, and import the params and model files):

```dart
  test('stageAttachments passes the daemon paths through', () async {
    when(() => dataSource.stageAttachments(any(), any())).thenAnswer(
      (_) async => const GlobalResponse(data: StagedAttachmentsModel(sessionId: 's-1', paths: ['p'])),
    );

    final result = await repository.stageAttachments('s-1', const StageSessionAttachmentsParams(files: []));

    expect(result.getOrDefault(const GlobalResponse()).data?.paths, ['p']);
  });

  test('stageAttachments reports no network without calling the daemon', () async {
    when(() => network.isConnected).thenAnswer((_) async => false);

    final result = await repository.stageAttachments('s-1', const StageSessionAttachmentsParams(files: []));

    expect(result.isSuccess, isFalse);
    verifyNever(() => dataSource.stageAttachments(any(), any()));
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/terminal/logic/attachment_limits_test.dart test/feature/terminal/logic/attachment_references_test.dart test/feature/terminal/data`
Expected: compilation errors, the new files and `stageAttachments` do not exist.

- [ ] **Step 3: Write the logic files**

`packages/mobile/lib/feature/terminal/logic/composer_attachment.dart`:

```dart
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

class ComposerAttachment extends Equatable {
  const ComposerAttachment({required this.id, required this.name, required this.mimeType, required this.bytes});

  final String id;
  final String name;
  final String mimeType;
  final Uint8List bytes;

  bool get isImage => mimeType.startsWith('image/');

  int get size => bytes.length;

  @override
  List<Object?> get props => [id, name, mimeType, bytes.length];
}
```

`packages/mobile/lib/feature/terminal/logic/attachment_limits.dart`:

```dart
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

sealed class AttachmentLimits {
  static const int maxCount = 8;
  static const int maxBytes = 10 * 1024 * 1024;
  static const int maxTotalBytes = 25 * 1024 * 1024;
}

const String kSvgRefused = 'SVG files are not supported.';
const String kFileTooLarge = 'Each file must be under 10 MB.';
const String kTooManyFiles = 'You can attach up to 8 files.';
const String kTotalTooLarge = 'Attachments must add up to under 25 MB.';
const String kEmptyFile = 'Empty files are skipped.';

class AttachmentAdmission {
  const AttachmentAdmission({required this.accepted, this.notice});

  final List<ComposerAttachment> accepted;
  final String? notice;
}

bool isBlockedAttachment({required String name, required String mimeType}) =>
    mimeType.toLowerCase().trim() == 'image/svg+xml' || name.toLowerCase().trim().endsWith('.svg');

AttachmentAdmission admitAttachments(List<ComposerAttachment> current, List<ComposerAttachment> incoming) {
  final accepted = <ComposerAttachment>[];
  final notices = <String>{};
  final known = {for (final attachment in current) attachment.id};
  var count = current.length;
  var total = current.fold<int>(0, (sum, attachment) => sum + attachment.size);
  for (final attachment in incoming) {
    if (known.contains(attachment.id)) continue;
    if (isBlockedAttachment(name: attachment.name, mimeType: attachment.mimeType)) {
      notices.add(kSvgRefused);
      continue;
    }
    if (attachment.size == 0) {
      notices.add(kEmptyFile);
      continue;
    }
    if (attachment.size > AttachmentLimits.maxBytes) {
      notices.add(kFileTooLarge);
      continue;
    }
    if (count >= AttachmentLimits.maxCount) {
      notices.add(kTooManyFiles);
      continue;
    }
    if (total + attachment.size > AttachmentLimits.maxTotalBytes) {
      notices.add(kTotalTooLarge);
      continue;
    }
    accepted.add(attachment);
    known.add(attachment.id);
    count++;
    total += attachment.size;
  }
  return AttachmentAdmission(accepted: accepted, notice: notices.isEmpty ? null : notices.join(' '));
}

const Map<String, String> _mimeByExtension = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'bmp': 'image/bmp',
  'svg': 'image/svg+xml',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'log': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'json': 'application/json',
  'zip': 'application/zip',
};

String attachmentMimeType(String name, String? reported) {
  final given = (reported ?? '').toLowerCase().trim();
  if (given.isNotEmpty && given != 'application/octet-stream') return given;
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 'application/octet-stream';
  return _mimeByExtension[name.substring(dot + 1).toLowerCase()] ?? 'application/octet-stream';
}
```

`packages/mobile/lib/feature/terminal/logic/attachment_references.dart`:

```dart
const String kAttachedFilesHeader = 'Attached files (read these files in the workspace for context):';

String appendAttachmentReferences(String message, List<String> paths) {
  if (paths.isEmpty) return message;
  final buffer = StringBuffer();
  if (message.trim().isNotEmpty) {
    buffer
      ..write(message)
      ..write('\n\n');
  }
  buffer.write(kAttachedFilesHeader);
  for (final path in paths) {
    buffer
      ..write('\n- ')
      ..write(path);
  }
  return buffer.toString();
}
```

The header and layout are byte-for-byte the daemon's `appendAttachmentReferences` (`backend/internal/session_manager/manager.go:2936-2951`), except that a blank message is dropped instead of kept as whitespace.

- [ ] **Step 4: Params, model, data source, repository**

`packages/mobile/lib/feature/terminal/data/model/params/stage_session_attachments_params.dart`:

```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

class StageSessionAttachmentsParams extends Equatable {
  const StageSessionAttachmentsParams({required this.files});

  final List<ComposerAttachment> files;

  Map<String, dynamic> toJson() => {
    'attachments': [
      for (final file in files) {'mimeType': file.mimeType, 'data': base64Encode(file.bytes)},
    ],
  };

  @override
  List<Object?> get props => [files];
}
```

`packages/mobile/lib/feature/terminal/data/model/staged_attachments_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class StagedAttachmentsModel extends Equatable {
  const StagedAttachmentsModel({this.sessionId, this.paths});

  final String? sessionId;
  final List<String>? paths;

  factory StagedAttachmentsModel.fromJson(Map<String, dynamic> json) => StagedAttachmentsModel(
    sessionId: json['sessionId'] as String?,
    paths: (json['paths'] as List<dynamic>?)?.whereType<String>().toList(),
  );

  @override
  List<Object?> get props => [sessionId, paths];
}
```

In `terminal_remote_data_source.dart`, add to the abstract class:

```dart
  Future<GlobalResponse<StagedAttachmentsModel>> stageAttachments(String sessionId, StageSessionAttachmentsParams params);
```

and to `TerminalRemoteDataSourceImp`:

```dart
  @override
  Future<GlobalResponse<StagedAttachmentsModel>> stageAttachments(
    String sessionId,
    StageSessionAttachmentsParams params,
  ) async {
    final response = await _apiConsumer.post(EndPoints.sessionAttachments(sessionId), body: params.toJson());
    return GlobalResponse<StagedAttachmentsModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: StagedAttachmentsModel.fromJson,
    );
  }
```

In `terminal_repository.dart`, add to the abstract class:

```dart
  FutureResult<GlobalResponse<StagedAttachmentsModel>> stageAttachments(String sessionId, StageSessionAttachmentsParams params);
```

and to `TerminalRepositoryImp`:

```dart
  @override
  FutureResult<GlobalResponse<StagedAttachmentsModel>> stageAttachments(
    String sessionId,
    StageSessionAttachmentsParams params,
  ) => _guard(() => _remoteDataSource.stageAttachments(sessionId, params));
```

Add the imports for the new params and model in both files.

- [ ] **Step 5: Run the tests and gates**

Run: `cd packages/mobile && flutter test test/feature/terminal/logic test/feature/terminal/data`
Expected: PASS.

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib/feature/terminal/logic/composer_attachment.dart packages/mobile/lib/feature/terminal/logic/attachment_limits.dart \
  packages/mobile/lib/feature/terminal/logic/attachment_references.dart \
  packages/mobile/lib/feature/terminal/data/model/params/stage_session_attachments_params.dart \
  packages/mobile/lib/feature/terminal/data/model/staged_attachments_model.dart \
  packages/mobile/lib/feature/terminal/data/data_source/terminal_remote_data_source.dart \
  packages/mobile/lib/feature/terminal/data/repository/terminal_repository.dart \
  packages/mobile/test/feature/terminal/logic/attachment_limits_test.dart packages/mobile/test/feature/terminal/logic/attachment_references_test.dart \
  packages/mobile/test/feature/terminal/data/data_source/terminal_remote_data_source_test.dart \
  packages/mobile/test/feature/terminal/data/repository/terminal_repository_test.dart
git commit -m "feat(mobile): attachment admission, reference format and the stage endpoint

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 7: `TerminalCubit` holds attachments and sends them

**Files:**
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart:108-340`
- Test: `packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/terminal_cubit_attachments_test.dart` (new)

**Interfaces:**
- Consumes: `ComposerAttachment`, `admitAttachments`, `appendAttachmentReferences`, `StageSessionAttachmentsParams`, `TerminalRepository.stageAttachments` (Task 6).
- Produces on `TerminalCubit`:
  - `List<ComposerAttachment> attachments` (starts `const []`), `String? attachmentNotice`, `bool staging`
  - `bool get hasContent` (trimmed text non-empty or any attachment)
  - `bool hasAttachment(String id)`
  - `void addAttachments(List<ComposerAttachment> incoming)`, `void removeAttachment(String id)`, `void toggleAttachment(ComposerAttachment attachment)`, `void showAttachmentNotice(String message)`, `void dismissAttachmentNotice()`
  - `Future<void> send()` now stages first when attachments are present, sends `appendAttachmentReferences(text, paths)`, keeps text and attachments on any failure, and reuses already staged paths until the attachment list changes. `addAttachments`/`removeAttachment` are ignored while `sending`.

- [ ] **Step 1: Write the failing tests**

Create `packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/terminal_cubit_attachments_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/stage_session_attachments_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/staged_attachments_model.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_limits.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class _MockMuxClient extends Mock implements MuxClient {}

class _MockTerminalRepository extends Mock implements TerminalRepository {}

class _MockSessionsRepository extends Mock implements SessionsRepository {}

ComposerAttachment png(String id, {int size = 4}) =>
    ComposerAttachment(id: id, name: '$id.png', mimeType: 'image/png', bytes: Uint8List(size));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockMuxClient mux;
  late _MockTerminalRepository repository;
  late TerminalCubit cubit;

  setUpAll(() {
    registerFallbackValue(const SendSessionMessageParams(message: ''));
    registerFallbackValue(const StageSessionAttachmentsParams(files: []));
  });

  setUp(() {
    mux = _MockMuxClient();
    repository = _MockTerminalRepository();
    when(() => mux.status).thenAnswer((_) => const Stream<MuxStatus>.empty());
    when(() => mux.terminalEvents).thenAnswer((_) => const Stream<TerminalEvent>.empty());
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
    when(() => repository.getSuggestion(any())).thenAnswer((_) async => Result.success(null));
    when(() => repository.getDraft(any())).thenAnswer((_) async => Result.success(null));
    cubit = TerminalCubit(
      mux,
      repository,
      _MockSessionsRepository(),
      const TerminalArgs(id: 's-1', sessionId: 's-1', title: 'Session'),
    );
  });

  tearDown(() => cubit.close());

  void stubStage(List<String> paths) => when(() => repository.stageAttachments(any(), any())).thenAnswer(
    (_) async => Result.success(GlobalResponse(data: StagedAttachmentsModel(sessionId: 's-1', paths: paths))),
  );

  void stubSend() =>
      when(() => repository.sendSessionMessage(any(), any())).thenAnswer((_) async => Result.success(true));

  String sentMessage() =>
      (verify(() => repository.sendSessionMessage('s-1', captureAny())).captured.last as SendSessionMessageParams).message;

  test('an attachment alone stages, then sends only the reference block, then clears', () async {
    stubStage(['.operator/attachments/attachment-aa.png']);
    stubSend();
    cubit.addAttachments([png('a')]);

    await cubit.send();

    final staged = verify(() => repository.stageAttachments('s-1', captureAny())).captured.single as StageSessionAttachmentsParams;
    expect(staged.files.map((file) => file.id), ['a']);
    expect(sentMessage(), 'Attached files (read these files in the workspace for context):\n- .operator/attachments/attachment-aa.png');
    expect(cubit.attachments, isEmpty);
    expect(cubit.composer.text, isEmpty);
    expect(cubit.sending, isFalse);
  });

  test('text and attachments send the text then the references', () async {
    stubStage(['.operator/attachments/attachment-aa.png']);
    stubSend();
    cubit.composer.text = 'what is wrong here?';
    cubit.addAttachments([png('a')]);

    await cubit.send();

    expect(sentMessage(), startsWith('what is wrong here?\n\nAttached files'));
  });

  test('plain text never stages', () async {
    stubSend();
    cubit.composer.text = 'hello';

    await cubit.send();

    verifyNever(() => repository.stageAttachments(any(), any()));
    expect(sentMessage(), 'hello');
  });

  test('a failed stage keeps the draft, sends nothing and says why', () async {
    when(() => repository.stageAttachments(any(), any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'attachment is too large', apiStatus: 'ATTACHMENT_TOO_LARGE')),
    );
    cubit.composer.text = 'see attached';
    cubit.addAttachments([png('a')]);

    await cubit.send();

    verifyNever(() => repository.sendSessionMessage(any(), any()));
    expect(cubit.composer.text, 'see attached');
    expect(cubit.attachments.single.id, 'a');
    expect(cubit.attachmentNotice, "Couldn't attach: attachment is too large");
    expect(cubit.staging, isFalse);
    expect(cubit.sending, isFalse);
  });

  test('a failed send keeps the draft and a retry reuses the staged paths', () async {
    stubStage(['.operator/attachments/attachment-aa.png']);
    var sends = 0;
    when(() => repository.sendSessionMessage(any(), any())).thenAnswer((_) async {
      sends++;
      return sends == 1
          ? Result.failure(ServerFailure(error: 'x', message: 'another operation owns the terminal', apiStatus: 'SESSION_BUSY'))
          : Result.success(true);
    });
    cubit.composer.text = 'retry me';
    cubit.addAttachments([png('a')]);

    await cubit.send();
    expect(cubit.composer.text, 'retry me');
    expect(cubit.attachments, hasLength(1));
    expect(cubit.attachmentNotice, 'Send failed: another operation owns the terminal');

    await cubit.send();

    verify(() => repository.stageAttachments(any(), any())).called(1);
    verify(() => repository.sendSessionMessage(any(), any())).called(2);
    expect(cubit.attachments, isEmpty);
  });

  test('changing the attachments after a failure stages again', () async {
    stubStage(['.operator/attachments/attachment-aa.png']);
    when(() => repository.sendSessionMessage(any(), any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'down')),
    );
    cubit.addAttachments([png('a')]);
    await cubit.send();
    stubStage(['.operator/attachments/attachment-aa.png', '.operator/attachments/attachment-bb.png']);
    cubit.addAttachments([png('b')]);

    await cubit.send();

    verify(() => repository.stageAttachments(any(), any())).called(2);
  });

  test('a stage that returns the wrong number of paths refuses to send', () async {
    stubStage(const []);
    cubit.addAttachments([png('a')]);

    await cubit.send();

    verifyNever(() => repository.sendSessionMessage(any(), any()));
    expect(cubit.attachments, hasLength(1));
    expect(cubit.attachmentNotice, "Couldn't attach the files.");
  });

  test('staging is reported while the upload runs and editing is locked', () async {
    final upload = Completer<Result<GlobalResponse<StagedAttachmentsModel>, Failure>>();
    when(() => repository.stageAttachments(any(), any())).thenAnswer((_) => upload.future);
    stubSend();
    cubit.addAttachments([png('a')]);

    final sending = cubit.send();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.staging, isTrue);
    expect(cubit.sending, isTrue);
    cubit.removeAttachment('a');
    cubit.addAttachments([png('late')]);
    expect(cubit.attachments.map((a) => a.id), ['a']);

    upload.complete(Result.success(const GlobalResponse(data: StagedAttachmentsModel(paths: ['p']))));
    await sending;
    expect(cubit.staging, isFalse);
  });

  test('admission caps the count and reports it', () {
    cubit.addAttachments([for (var i = 0; i < 9; i++) png('f$i')]);

    expect(cubit.attachments, hasLength(8));
    expect(cubit.attachmentNotice, kTooManyFiles);
  });

  test('toggle adds then removes the same attachment', () {
    cubit.toggleAttachment(png('photo:1'));
    expect(cubit.hasAttachment('photo:1'), isTrue);
    expect(cubit.hasContent, isTrue);

    cubit.toggleAttachment(png('photo:1'));
    expect(cubit.hasAttachment('photo:1'), isFalse);
    expect(cubit.hasContent, isFalse);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/terminal/presentation/terminal_screen/logic/terminal_cubit_attachments_test.dart`
Expected: compilation errors: `addAttachments`, `attachments`, `attachmentNotice`, `staging`, `toggleAttachment`, `hasAttachment`, `hasContent` are not defined on `TerminalCubit`.

- [ ] **Step 3: Implement**

In `terminal_cubit.dart`, add imports:

```dart
import 'package:operator_mobile/feature/terminal/data/model/params/stage_session_attachments_params.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_limits.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_references.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';
```

Add fields next to `bool sending = false;`:

```dart
  bool staging = false;
  List<ComposerAttachment> attachments = const [];
  String? attachmentNotice;
  List<String>? _stagedPaths;
```

Add these members above `send()`:

```dart
  bool get hasContent => composer.text.trim().isNotEmpty || attachments.isNotEmpty;

  bool hasAttachment(String id) => attachments.any((attachment) => attachment.id == id);

  void addAttachments(List<ComposerAttachment> incoming) {
    if (sending) return;
    final admission = admitAttachments(attachments, incoming);
    attachmentNotice = admission.notice;
    if (admission.accepted.isNotEmpty) {
      attachments = [...attachments, ...admission.accepted];
      _stagedPaths = null;
    }
    _emit();
  }

  void removeAttachment(String id) {
    if (sending || !hasAttachment(id)) return;
    attachments = attachments.where((attachment) => attachment.id != id).toList();
    _stagedPaths = null;
    attachmentNotice = null;
    _emit();
  }

  void toggleAttachment(ComposerAttachment attachment) =>
      hasAttachment(attachment.id) ? removeAttachment(attachment.id) : addAttachments([attachment]);

  void showAttachmentNotice(String message) {
    attachmentNotice = message;
    _emit();
  }

  void dismissAttachmentNotice() {
    if (attachmentNotice == null) return;
    attachmentNotice = null;
    _emit();
  }
```

Replace `send()` with:

```dart
  Future<void> send() async {
    final text = composer.text.trim();
    if (sending) return;

    if (args.shellOnly) {
      if (text.isEmpty) return;
      if (!_writeToPty(text)) {
        Haptics.error();
        banner = kTerminalUnavailableNotice;
        _emit();
        return;
      }
      Haptics.success();
      banner = kTerminalModeNotice;
      composer.clear();
      dismissSuggestion();
      _emit();
      unawaited(fetchDraft());
      return;
    }

    if (text.isEmpty && attachments.isEmpty) return;
    sending = true;
    attachmentNotice = null;
    _emit();
    final paths = await _stage();
    if (paths == null) {
      sending = false;
      _emit();
      return;
    }
    final message = appendAttachmentReferences(text, paths);
    final hadAttachments = attachments.isNotEmpty;
    final result = await _repository.sendSessionMessage(
      args.sessionId,
      SendSessionMessageParams(message: message),
    );
    result.when(
      onSuccess: (_) {
        Haptics.success();
        _clearDraft();
        unawaited(fetchDraft());
      },
      onFailure: (failure) {
        if (shouldRetryOnTerminal(failure) && _writeToPty(message)) {
          Haptics.success();
          banner = kReroutedNotice;
          _clearDraft();
          unawaited(fetchDraft());
          return;
        }
        Haptics.error();
        if (hadAttachments) {
          attachmentNotice = 'Send failed: ${failure.message}';
        } else {
          banner = 'Send failed: ${failure.message}';
        }
      },
    );
    sending = false;
    _emit();
  }

  Future<List<String>?> _stage() async {
    if (attachments.isEmpty) return const [];
    final cached = _stagedPaths;
    if (cached != null) return cached;
    final snapshot = attachments;
    staging = true;
    _emit();
    final result = await _repository.stageAttachments(args.sessionId, StageSessionAttachmentsParams(files: snapshot));
    staging = false;
    List<String>? paths;
    result.when(
      onSuccess: (response) {
        final staged = response.data?.paths ?? const <String>[];
        if (staged.length == snapshot.length) {
          paths = staged;
        } else {
          attachmentNotice = "Couldn't attach the files.";
        }
      },
      onFailure: (failure) => attachmentNotice = "Couldn't attach: ${failure.message}",
    );
    if (paths == null) {
      Haptics.error();
      return null;
    }
    if (identical(snapshot, attachments)) _stagedPaths = paths;
    return paths;
  }

  void _clearDraft() {
    composer.clear();
    attachments = const [];
    _stagedPaths = null;
    attachmentNotice = null;
    dismissSuggestion();
  }
```

`Haptics` calls go through a `MethodChannel`, which needs a binding; the test file calls `TestWidgetsFlutterBinding.ensureInitialized()` so the unhandled channel call fails asynchronously and `Haptics._fire` swallows it.

- [ ] **Step 4: Run the tests and gates**

Run: `cd packages/mobile && flutter test test/feature/terminal`
Expected: PASS, including the existing `terminal_cubit_test.dart` send tests.

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart \
  packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/terminal_cubit_attachments_test.dart
git commit -m "feat(mobile): stage composer attachments and send their paths, keeping the draft on failure

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 8: Pickers and the "Add context" sheet (Camera, Photos, Files)

**Files:**
- Create: `packages/mobile/lib/feature/terminal/data/data_source/attachment_picker.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart:222-243` (`_terminalFeatureSetup`)
- Modify: `packages/mobile/ios/Runner/Info.plist:76-77` (`NSCameraUsageDescription`)
- Test: `packages/mobile/test/feature/terminal/data/data_source/attachment_picker_test.dart` (new), `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/add_context_sheet_test.dart` (new)

**Interfaces:**
- Consumes: `ComposerAttachment`, `attachmentMimeType`, `AttachmentLimits`, `kTooManyFiles` (Task 6); `TerminalCubit.attachments`, `addAttachments`, `showAttachmentNotice` (Task 7); `showAppSheet`, `AppSheetPage`, `AppSheet.of(context).close()`.
- Produces:
  - `class AttachmentPickFailure implements Exception { final String message; }`
  - `abstract class AttachmentPicker { Future<List<ComposerAttachment>> camera(); Future<List<ComposerAttachment>> photos({required int limit}); Future<List<ComposerAttachment>> files(); }`
  - `class AttachmentPickerImp implements AttachmentPicker { AttachmentPickerImp(ImagePicker images, {Future<List<XFile>> Function()? pickFiles, int Function()? now}); static const double maxDimension = 2048; static const int quality = 85; }`, registered as `sl<AttachmentPicker>()`.
  - `Future<void> showAddContextSheet(BuildContext context)` (reads `TerminalCubit` from `context`), `class AddContextBody` with keys `AddContextBody.cameraKey`, `photosKey`, `filesKey`, and `class AddContextTile`.

- [ ] **Step 1: Write the failing tests**

Create `packages/mobile/test/feature/terminal/data/data_source/attachment_picker_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/attachment_picker.dart';

class _MockImagePicker extends Mock implements ImagePicker {}

void main() {
  late _MockImagePicker images;
  late List<XFile> files;
  late AttachmentPickerImp picker;

  setUpAll(() => registerFallbackValue(ImageSource.gallery));

  setUp(() {
    images = _MockImagePicker();
    files = [];
    picker = AttachmentPickerImp(images, pickFiles: () async => files, now: () => 7);
  });

  test('photos are requested as 2048 px quality 85 jpeg', () async {
    when(
      () => images.pickMultiImage(
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
        limit: any(named: 'limit'),
        requestFullMetadata: any(named: 'requestFullMetadata'),
      ),
    ).thenAnswer((_) async => [XFile.fromData(Uint8List.fromList([1, 2]), name: 'IMG_0001.jpg')]);

    final picked = await picker.photos(limit: 5);

    verify(
      () => images.pickMultiImage(
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
        limit: 5,
        requestFullMetadata: false,
      ),
    ).called(1);
    expect(picked.single.mimeType, 'image/jpeg');
    expect(picked.single.name, 'IMG_0001.jpg');
    expect(picked.single.bytes, [1, 2]);
  });

  test('one free slot picks a single photo from the library', () async {
    when(
      () => images.pickImage(
        source: any(named: 'source'),
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
        requestFullMetadata: any(named: 'requestFullMetadata'),
      ),
    ).thenAnswer((_) async => XFile.fromData(Uint8List.fromList([3]), name: 'one.jpg'));

    final picked = await picker.photos(limit: 1);

    expect(picked, hasLength(1));
    verify(
      () => images.pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048, imageQuality: 85, requestFullMetadata: false),
    ).called(1);
  });

  test('the camera is capped the same way', () async {
    when(
      () => images.pickImage(
        source: any(named: 'source'),
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
        requestFullMetadata: any(named: 'requestFullMetadata'),
      ),
    ).thenAnswer((_) async => XFile.fromData(Uint8List.fromList([4]), name: 'shot.jpg'));

    await picker.camera();

    verify(
      () => images.pickImage(source: ImageSource.camera, maxWidth: 2048, maxHeight: 2048, imageQuality: 85, requestFullMetadata: false),
    ).called(1);
  });

  test('a denied camera becomes a readable failure', () async {
    when(
      () => images.pickImage(
        source: any(named: 'source'),
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
        requestFullMetadata: any(named: 'requestFullMetadata'),
      ),
    ).thenThrow(PlatformException(code: 'camera_access_denied'));

    expect(
      picker.camera(),
      throwsA(isA<AttachmentPickFailure>().having((failure) => failure.message, 'message', contains('Camera access is off'))),
    );
  });

  test('files keep their name, get a type from the extension, and never collide', () async {
    files = [
      XFile.fromData(Uint8List.fromList([5]), name: 'report.pdf'),
      XFile.fromData(Uint8List.fromList([6]), name: 'report.pdf'),
    ];

    final picked = await picker.files();

    expect(picked.map((file) => file.mimeType), ['application/pdf', 'application/pdf']);
    expect(picked.map((file) => file.id).toSet(), hasLength(2));
  });

  test('a cancelled camera returns nothing', () async {
    when(
      () => images.pickImage(
        source: any(named: 'source'),
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
        requestFullMetadata: any(named: 'requestFullMetadata'),
      ),
    ).thenAnswer((_) async => null);

    expect(await picker.camera(), isEmpty);
  });
}
```

Create `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/add_context_sheet_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/attachment_picker.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_limits.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart';

import '../../../terminal_harness.dart';

class FakeAttachmentPicker implements AttachmentPicker {
  List<ComposerAttachment> next = const [];
  Object? error;
  int? lastLimit;

  Future<List<ComposerAttachment>> _answer() async {
    final failure = error;
    if (failure != null) throw failure;
    return next;
  }

  @override
  Future<List<ComposerAttachment>> camera() => _answer();

  @override
  Future<List<ComposerAttachment>> photos({required int limit}) {
    lastLimit = limit;
    return _answer();
  }

  @override
  Future<List<ComposerAttachment>> files() => _answer();
}

ComposerAttachment png(String id) =>
    ComposerAttachment(id: id, name: '$id.png', mimeType: 'image/png', bytes: Uint8List(4));

void main() {
  late TerminalHarness harness;
  late FakeAttachmentPicker picker;

  setUp(() {
    harness = TerminalHarness()..start(harness: 'claude-code');
    picker = FakeAttachmentPicker();
    if (sl.isRegistered<AttachmentPicker>()) sl.unregister<AttachmentPicker>();
    sl.registerSingleton<AttachmentPicker>(picker);
  });

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester) async {
    await harness.pump(
      tester,
      Builder(
        builder: (context) => TextButton(onPressed: () => showAddContextSheet(context), child: const Text('Open')),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet is titled Add context, has a close button and three tiles', (tester) async {
    await open(tester);

    expect(find.text('Add context'), findsOneWidget);
    expect(find.byKey(AppSheet.closeKey), findsOneWidget);
    expect(find.byKey(AddContextBody.cameraKey), findsOneWidget);
    expect(find.byKey(AddContextBody.photosKey), findsOneWidget);
    expect(find.byKey(AddContextBody.filesKey), findsOneWidget);
    expect(find.text('Connectors'), findsNothing);
  });

  testWidgets('picking photos adds them to the composer and closes the sheet', (tester) async {
    picker.next = [png('a'), png('b')];
    harness.cubit.addAttachments([png('existing')]);
    await open(tester);

    await tester.tap(find.byKey(AddContextBody.photosKey));
    await tester.pumpAndSettle();

    expect(picker.lastLimit, AttachmentLimits.maxCount - 1);
    expect(harness.cubit.attachments.map((a) => a.id), ['existing', 'a', 'b']);
    expect(find.text('Add context'), findsNothing);
  });

  testWidgets('a cancelled pick leaves the sheet open', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(AddContextBody.filesKey));
    await tester.pumpAndSettle();

    expect(find.text('Add context'), findsOneWidget);
    expect(harness.cubit.attachments, isEmpty);
  });

  testWidgets('a denied camera explains itself in the composer and closes', (tester) async {
    picker.error = const AttachmentPickFailure('Camera access is off. Turn it on in Settings to take a photo.');
    await open(tester);

    await tester.tap(find.byKey(AddContextBody.cameraKey));
    await tester.pumpAndSettle();

    expect(harness.cubit.attachmentNotice, startsWith('Camera access is off'));
    expect(find.text('Add context'), findsNothing);
  });

  testWidgets('a full tray says so instead of opening a picker', (tester) async {
    harness.cubit.addAttachments([for (var i = 0; i < AttachmentLimits.maxCount; i++) png('f$i')]);
    picker.next = [png('extra')];
    await open(tester);

    await tester.tap(find.byKey(AddContextBody.photosKey));
    await tester.pumpAndSettle();

    expect(picker.lastLimit, isNull);
    expect(harness.cubit.attachmentNotice, kTooManyFiles);
    expect(harness.cubit.attachments, hasLength(AttachmentLimits.maxCount));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/terminal/data/data_source/attachment_picker_test.dart test/feature/terminal/presentation/terminal_screen/ui/add_context_sheet_test.dart`
Expected: compilation errors: `attachment_picker.dart` and `add_context_sheet.dart` do not exist.

- [ ] **Step 3: The picker seam**

Create `packages/mobile/lib/feature/terminal/data/data_source/attachment_picker.dart`:

```dart
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_limits.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

class AttachmentPickFailure implements Exception {
  const AttachmentPickFailure(this.message);

  final String message;
}

abstract class AttachmentPicker {
  Future<List<ComposerAttachment>> camera();
  Future<List<ComposerAttachment>> photos({required int limit});
  Future<List<ComposerAttachment>> files();
}

class AttachmentPickerImp implements AttachmentPicker {
  AttachmentPickerImp(this._images, {Future<List<XFile>> Function()? pickFiles, int Function()? now})
    : _pickFiles = pickFiles ?? (() => openFiles()),
      _now = now ?? (() => DateTime.now().microsecondsSinceEpoch);

  static const double maxDimension = 2048;
  static const int quality = 85;

  final ImagePicker _images;
  final Future<List<XFile>> Function() _pickFiles;
  final int Function() _now;

  @override
  Future<List<ComposerAttachment>> camera() => _guard('Camera', () async {
    final shot = await _images.pickImage(
      source: ImageSource.camera,
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: quality,
      requestFullMetadata: false,
    );
    return shot == null ? const [] : _readAll('camera', [shot]);
  });

  @override
  Future<List<ComposerAttachment>> photos({required int limit}) => _guard('Photos', () async {
    if (limit <= 0) return const [];
    if (limit == 1) {
      final one = await _images.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxDimension,
        maxHeight: maxDimension,
        imageQuality: quality,
        requestFullMetadata: false,
      );
      return one == null ? const [] : _readAll('photo', [one]);
    }
    final picked = await _images.pickMultiImage(
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: quality,
      limit: limit,
      requestFullMetadata: false,
    );
    return _readAll('photo', picked);
  });

  @override
  Future<List<ComposerAttachment>> files() => _guard('Files', () async => _readAll('file', await _pickFiles()));

  Future<List<ComposerAttachment>> _readAll(String source, List<XFile> picked) async {
    final stamp = _now();
    return [
      for (var i = 0; i < picked.length; i++)
        ComposerAttachment(
          id: '$source:$stamp:$i',
          name: picked[i].name.isEmpty ? '$source-$i' : picked[i].name,
          mimeType: attachmentMimeType(picked[i].name, picked[i].mimeType),
          bytes: await picked[i].readAsBytes(),
        ),
    ];
  }

  Future<List<ComposerAttachment>> _guard(String source, Future<List<ComposerAttachment>> Function() pick) async {
    try {
      return await pick();
    } on PlatformException catch (error) {
      throw AttachmentPickFailure(_pickMessage(source, error.code));
    }
  }
}

String _pickMessage(String source, String code) => switch (code) {
  'camera_access_denied' => 'Camera access is off. Turn it on in Settings to take a photo.',
  'photo_access_denied' => 'Photo access is off. Turn it on in Settings to attach photos.',
  _ => '$source is not available right now.',
};
```

`imageQuality` and `maxWidth`/`maxHeight` make `image_picker` re-encode the picked image, which turns an iPhone HEIC into a JPEG before it ever reaches admission.

Register it in `_terminalFeatureSetup` of `service_locator.dart` (import `package:image_picker/image_picker.dart` and the picker file):

```dart
    sl.registerLazySingleton<AttachmentPicker>(() => AttachmentPickerImp(ImagePicker()));
```

In `packages/mobile/ios/Runner/Info.plist`, change the `NSCameraUsageDescription` string to `Operator uses your camera to scan the pairing QR code and to take photos you attach for your agent.`

- [ ] **Step 4: The sheet**

Create `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/press_scale.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/attachment_picker.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_limits.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

typedef AttachmentPick = Future<List<ComposerAttachment>> Function(AttachmentPicker picker, int room);

Future<void> showAddContextSheet(BuildContext context) {
  final terminal = context.read<TerminalCubit>();
  return showAppSheet<void>(
    context: context,
    detent: AppSheetDetent.fit,
    scope: (sheetContext, sheet) => BlocProvider<TerminalCubit>.value(value: terminal, child: sheet),
    page: AppSheetPage(
      title: 'Add context',
      closeable: true,
      rows: (context, _) => const [AddContextBody()],
    ),
  );
}

class AddContextBody extends StatelessWidget {
  const AddContextBody({super.key});

  static const Key cameraKey = ValueKey('add-context-camera');
  static const Key photosKey = ValueKey('add-context-photos');
  static const Key filesKey = ValueKey('add-context-files');

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 16,
    children: [
      Row(
        spacing: 10,
        children: [
          Expanded(
            child: AddContextTile(
              key: cameraKey,
              icon: Icons.photo_camera_outlined,
              label: 'Camera',
              onTap: () => unawaited(_pick(context, (picker, _) => picker.camera())),
            ),
          ),
          Expanded(
            child: AddContextTile(
              key: photosKey,
              icon: Icons.photo_library_outlined,
              label: 'Photos',
              onTap: () => unawaited(_pick(context, (picker, room) => picker.photos(limit: room))),
            ),
          ),
          Expanded(
            child: AddContextTile(
              key: filesKey,
              icon: Icons.attach_file_rounded,
              label: 'Files',
              onTap: () => unawaited(_pick(context, (picker, _) => picker.files())),
            ),
          ),
        ],
      ),
    ],
  );
}

Future<void> _pick(BuildContext context, AttachmentPick pick) async {
  final terminal = context.read<TerminalCubit>();
  final sheet = AppSheet.of(context);
  final room = AttachmentLimits.maxCount - terminal.attachments.length;
  if (room <= 0) {
    terminal.showAttachmentNotice(kTooManyFiles);
    sheet.close();
    return;
  }
  try {
    final picked = await pick(sl<AttachmentPicker>(), room);
    if (picked.isEmpty) return;
    terminal.addAttachments(picked);
  } on AttachmentPickFailure catch (failure) {
    terminal.showAttachmentNotice(failure.message);
  }
  sheet.close();
}

class AddContextTile extends StatelessWidget {
  const AddContextTile({super.key, required this.icon, required this.label, required this.onTap});

  static const double height = 76;

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return PressScale(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.tap();
            onTap();
          },
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: skin.textPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 6,
              children: [
                Icon(icon, size: 24, color: skin.textPrimary),
                Text(label, style: AppTextStyle.style13Medium.copyWith(color: skin.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the tests and gates**

Run: `cd packages/mobile && flutter test test/feature/terminal`
Expected: PASS.

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 6: Simulator captures (batched by the controller at the end)**

Save to `packages/mobile/build/composer/task8/`: `sheet-dark.png`, `sheet-light.png` (the Add context sheet over a live chat session, tiles visible), `camera-denied-dark.png` (the composer notice after a denied camera).

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib/feature/terminal/data/data_source/attachment_picker.dart \
  packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart \
  packages/mobile/lib/core/utils/service_locator.dart packages/mobile/ios/Runner/Info.plist \
  packages/mobile/test/feature/terminal/data/data_source/attachment_picker_test.dart \
  packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/add_context_sheet_test.dart
git commit -m "feat(mobile): Add context sheet with Camera, Photos and Files

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 9: The two-row composer, the attachment tray, and **+** opening the sheet

**Files:**
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/composer_action_button.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/composer_add_button.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/composer_attachment_tray.dart`
- Modify: `packages/mobile/lib/feature/dictation/ui/mic_key.dart:10-140` (a `quiet` style)
- Test: `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_composer_test.dart` (rewritten), `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_body_layout_test.dart:230-240`

**Interfaces:**
- Consumes: `TerminalCubit.attachments`, `attachmentNotice`, `staging`, `sending`, `hasContent`, `removeAttachment`, `dismissAttachmentNotice` (Task 7); `showAddContextSheet` (Task 8); `ComposerModelChip`, `SessionCommandCubit.enabled('stop')`, `MicKey`.
- Produces:
  - `enum ComposerTrailing { none, send, stop }`, `ComposerTrailing composerTrailingFor({required bool hasContent, required bool canStop})`
  - `class ComposerSendSlot extends StatelessWidget { const ComposerSendSlot({Key? key, required ComposerTrailing trailing, required bool staging, VoidCallback? onSend, VoidCallback? onStop}); static const Key stagingKey; }`
  - `class ComposerAddButton extends StatelessWidget { const ComposerAddButton({Key? key, required VoidCallback? onTap}); }` (semantics label `Add context`)
  - `class ComposerAttachmentTray extends StatelessWidget { const ComposerAttachmentTray({Key? key, required List<ComposerAttachment> attachments, String? notice, void Function(String id)? onRemove, VoidCallback? onDismissNotice}); static const double thumbSize = 56; static const Key noticeKey; }` (each remove has semantics label `Remove <name>`)
  - `MicKey({bool quiet = false})`: a round, unfilled glyph at rest.
  - The shell composer (`args.shellOnly`) is unchanged: capsule at rest, mic↔send swap, no **+**, no chip.

- [ ] **Step 1: Rewrite the composer tests**

Replace `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_composer_test.dart` with:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_command_result_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_model_option_model.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/model_picker_sheet.dart';
import 'package:operator_mobile/feature/dictation/ui/mic_key.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/stage_session_attachments_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/staged_attachments_model.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_action_button.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_add_button.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_attachment_tray.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_model_chip.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer_draft_hint.dart';

import '../../../terminal_harness.dart';

ComposerAttachment png(String id) =>
    ComposerAttachment(id: id, name: '$id.png', mimeType: 'image/png', bytes: Uint8List(4));

ComposerAttachment pdf(String id) =>
    ComposerAttachment(id: id, name: '$id.pdf', mimeType: 'application/pdf', bytes: Uint8List(4));

void main() {
  late TerminalHarness harness;

  setUpAll(() {
    registerFallbackValue(const SessionCommandParams(command: ''));
    registerFallbackValue(const SendSessionMessageParams(message: ''));
    registerFallbackValue(const StageSessionAttachmentsParams(files: []));
  });

  setUp(() => harness = TerminalHarness()..start());

  tearDown(() => harness.dispose());

  Future<void> pumpComposer(WidgetTester tester) => harness.pump(tester, const TerminalComposer());

  Future<void> useShell() async {
    await harness.dispose();
    harness = TerminalHarness()..start(shellOnly: true);
  }

  Rect card(WidgetTester tester) => tester.getRect(find.byKey(TerminalComposer.capsuleKey));

  RenderEditable editable(WidgetTester tester) => tester.renderObject<RenderEditable>(
    find.descendant(
      of: find.byType(EditableText),
      matching: find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_Editable'),
    ),
  );

  void expectFieldFullyShown(WidgetTester tester, {required int lines}) {
    final capsule = card(tester);
    final field = tester.getRect(find.byType(TextField));
    final render = editable(tester);
    expect(capsule.contains(field.topLeft) && capsule.contains(field.bottomRight - const Offset(0.01, 0.01)), isTrue);
    expect(render.size.height, greaterThanOrEqualTo(render.preferredLineHeight * lines));
    expect(field.height, greaterThanOrEqualTo(render.size.height));
  }

  void stubStop() => when(
    () => harness.controlRepository.sendCommand(any(), any()),
  ).thenAnswer((_) async => Result.success(GlobalResponse<SessionCommandResultModel>()));

  group('agent composer', () {
    testWidgets('is a two-row glass card: the field on top, + and the model chip below', (tester) async {
      await pumpComposer(tester);

      final box = card(tester);
      final field = tester.getRect(find.byType(TextField));
      final plus = tester.getRect(find.byType(ComposerAddButton));
      final chip = tester.getRect(find.byType(ComposerModelChip));
      final mic = tester.getRect(find.byType(MicKey));
      expect(field.bottom, lessThanOrEqualTo(plus.top));
      expect(plus.left - box.left, 6);
      expect(plus.right, lessThan(chip.left));
      expect(chip.right, lessThan(mic.left));
      expect(box.right - mic.right, 6);
      expect(box.bottom - plus.bottom, 6);
      expect(box.bottom - mic.bottom, 6);

      final glass = tester.widget<GlassSurface>(find.byKey(TerminalComposer.capsuleKey));
      expect(glass.kind, GlassShapeKind.roundedRect);
      expect(glass.radius, TerminalComposer.cardRadius);
      expect(glass.variant, GlassVariant.regular);
      expect(glass.size, TerminalComposer.restHeight);
    });

    testWidgets('the hint fits the resting card', (tester) async {
      await pumpComposer(tester);

      expectFieldFullyShown(tester, lines: 1);
      expect(find.text('Message the agent...'), findsOneWidget);
    });

    testWidgets('typing shows Send after the mic and clearing hides it', (tester) async {
      await pumpComposer(tester);
      expect(find.bySemanticsLabel('Send'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();
      expect(find.byType(MicKey), findsOneWidget);
      expect(tester.getRect(find.bySemanticsLabel('Send')).left, greaterThanOrEqualTo(tester.getRect(find.byType(MicKey)).right));

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Send'), findsNothing);
      expect(find.byType(MicKey), findsOneWidget);
    });

    testWidgets('an attachment alone offers Send', (tester) async {
      await pumpComposer(tester);
      harness.cubit.addAttachments([png('a')]);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Send'), findsOneWidget);
    });

    testWidgets('while the agent works with an empty field, Stop sits after the mic', (tester) async {
      harness.commandCubit.onActivity('active');
      await pumpComposer(tester);
      await tester.pumpAndSettle();

      final stop = tester.getRect(find.bySemanticsLabel('Stop'));
      final mic = tester.getRect(find.byType(MicKey));
      expect(stop.left, greaterThanOrEqualTo(mic.right));
      expect(stop.size, const Size.square(ComposerActionButton.size));

      await tester.enterText(find.byType(TextField), 'next step');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Stop'), findsNothing);
      expect(find.bySemanticsLabel('Send'), findsOneWidget);
    });

    testWidgets('stop fades and scales in over the action swap', (tester) async {
      await pumpComposer(tester);
      harness.commandCubit.onActivity('active');
      await tester.pump();
      await tester.pump();
      await tester.pump(AppMotion.chatActionSwap ~/ 2);

      final fades = tester
          .widgetList<FadeTransition>(
            find.descendant(of: find.byType(ComposerSendSlot), matching: find.byType(FadeTransition)),
          )
          .toList();
      expect(fades.any((fade) => fade.opacity.value > 0 && fade.opacity.value < 1), isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('tapping stop interrupts the turn: it runs stop, never kill, and opens no dialog', (tester) async {
      stubStop();
      harness.commandCubit.onActivity('active');
      await pumpComposer(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Stop'));
      await tester.pumpAndSettle();

      verify(() => harness.controlRepository.sendCommand('s-1', const SessionCommandParams(command: 'stop'))).called(1);
      verifyNever(() => harness.sessionsRepository.kill(any()));
      await tester.pump(const Duration(minutes: 1));
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('dictation can start while the agent works', (tester) async {
      harness.voice.availableValue = true;
      harness.commandCubit.onActivity('active');
      await pumpComposer(tester);
      await tester.pumpAndSettle();

      final gesture = await tester.press(find.byType(MicKey));
      await tester.pump();
      await tester.pump();

      expect(harness.voice.callbacks, isNotNull);
      expect(find.text('Keep holding…'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the mic stays the same element while recording, even when Send appears', (tester) async {
      harness.voice.availableValue = true;
      await pumpComposer(tester);
      await tester.pumpAndSettle();
      final micElement = tester.element(find.byType(MicKey));

      final gesture = await tester.startGesture(tester.getCenter(find.byType(MicKey)));
      await tester.pump();
      await tester.pump();
      harness.voice.callbacks!.onReady();
      harness.cubit.composer.text = 'typed while recording';
      await tester.pump();
      await tester.pump(AppMotion.chatActionSwap * 2);

      expect(tester.element(find.byType(MicKey)), same(micElement));
      expect(find.bySemanticsLabel('Send'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.voice.stops + harness.voice.aborts, 1);
    });

    testWidgets('tapping + opens Add context', (tester) async {
      await pumpComposer(tester);

      await tester.tap(find.byType(ComposerAddButton));
      await tester.pumpAndSettle();

      expect(find.text('Add context'), findsOneWidget);
    });

    testWidgets('attachments sit in a tray above the field, each with a remove button', (tester) async {
      await pumpComposer(tester);
      harness.cubit.addAttachments([png('a'), pdf('b')]);
      await tester.pumpAndSettle();

      final tray = tester.getRect(find.byType(ComposerAttachmentTray));
      expect(tray.bottom, lessThanOrEqualTo(tester.getRect(find.byType(TextField)).top));
      expect(find.text('b.pdf'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Remove b.pdf'));
      await tester.pumpAndSettle();
      expect(harness.cubit.attachments.map((a) => a.id), ['a']);
    });

    testWidgets('a notice shows in the tray and tapping it dismisses it', (tester) async {
      await pumpComposer(tester);
      harness.cubit.showAttachmentNotice('Each file must be under 10 MB.');
      await tester.pumpAndSettle();

      expect(find.byKey(ComposerAttachmentTray.noticeKey), findsOneWidget);
      await tester.tap(find.byKey(ComposerAttachmentTray.noticeKey));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerAttachmentTray), findsNothing);
    });

    testWidgets('while staging, the send slot shows progress and + is disabled', (tester) async {
      final upload = Completer<Result<GlobalResponse<StagedAttachmentsModel>, Failure>>();
      when(() => harness.terminalRepository.stageAttachments(any(), any())).thenAnswer((_) => upload.future);
      when(() => harness.terminalRepository.sendSessionMessage(any(), any())).thenAnswer((_) async => Result.success(true));
      await pumpComposer(tester);
      harness.cubit.addAttachments([png('a')]);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();
      await tester.pump(AppMotion.chatActionSwap);

      expect(find.byKey(ComposerSendSlot.stagingKey), findsOneWidget);
      expect(tester.widget<ComposerAddButton>(find.byType(ComposerAddButton)).onTap, isNull);

      upload.complete(Result.success(const GlobalResponse(data: StagedAttachmentsModel(paths: ['p']))));
      await tester.pumpAndSettle();
      expect(find.byKey(ComposerSendSlot.stagingKey), findsNothing);
      expect(harness.cubit.attachments, isEmpty);
    });

    testWidgets('the card grows with the text and keeps its shape', (tester) async {
      await pumpComposer(tester);
      final rest = card(tester).height;

      await tester.enterText(find.byType(TextField), 'first line\nsecond line\nthird line');
      await tester.pumpAndSettle();

      expect(card(tester).height, greaterThan(rest));
      expectFieldFullyShown(tester, lines: 3);
      final glass = tester.widget<GlassSurface>(find.byKey(TerminalComposer.capsuleKey));
      expect(glass.kind, GlassShapeKind.roundedRect);
      expect(glass.radius, TerminalComposer.cardRadius);
    });

    testWidgets('opening the model picker keeps the card and returns focus when it closes', (tester) async {
      when(
        () => harness.controlRepository.getModels(any()),
      ).thenAnswer((_) async => Result.success(GlobalResponse<List<SessionModelOptionModel>>(data: const [])));
      harness.commandCubit.onActivity('idle');
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField), 'first\nsecond');
      await tester.pumpAndSettle();
      final grown = card(tester).height;

      await tester.tapAt(tester.getRect(find.byType(ComposerModelChip)).centerRight - const Offset(12, 0));
      await tester.pumpAndSettle();
      expect(find.byType(ModelPickerSheet), findsOneWidget);

      Navigator.of(tester.element(find.byType(ModelPickerSheet))).pop();
      await tester.pumpAndSettle();
      expect(card(tester).height, grown);
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(focused, isNotNull);
      expect(
        find.ancestor(of: find.byElementPredicate((e) => e == focused), matching: find.byType(TextField)),
        findsOneWidget,
      );
    });

    testWidgets('the model chip shows the harness glyph and a default label at rest', (tester) async {
      await pumpComposer(tester);

      expect(find.descendant(of: find.byType(ComposerModelChip), matching: find.byType(AgentLogo)), findsOneWidget);
      expect(find.descendant(of: find.byType(ComposerModelChip), matching: find.text('Default')), findsOneWidget);
    });

    testWidgets('has no session actions button and its field starts at the shell inset', (tester) async {
      await pumpComposer(tester);
      expect(find.byTooltip('Session actions'), findsNothing);
      final agentInset = tester.getRect(find.byType(TextField)).left - card(tester).left;

      await tester.pumpWidget(const SizedBox());
      await useShell();
      await pumpComposer(tester);
      await tester.pumpAndSettle();
      final shellInset = tester.getRect(find.byType(TextField)).left - card(tester).left;
      expect(agentInset, shellInset);
    });

    testWidgets('shows a remote draft as prefill while the field is empty', (tester) async {
      harness.cubit.draft = 'run the sample task';

      await pumpComposer(tester);

      expect(find.text('run the sample task'), findsOneWidget);
    });

    testWidgets('hides the remote draft once the user has typed something', (tester) async {
      harness.cubit.draft = 'run the sample task';
      harness.cubit.composer.text = 'already typing';

      await pumpComposer(tester);

      expect(find.text('run the sample task'), findsNothing);
    });

    testWidgets('tapping the remote draft fills the field without sending', (tester) async {
      harness.cubit.draft = 'run the sample task';

      await pumpComposer(tester);
      await tester.tap(find.text('run the sample task'));
      await tester.pump();

      expect(harness.cubit.composer.text, 'run the sample task');
      verifyNever(() => harness.mux.sendInput(any(), any(), projectId: any(named: 'projectId')));
    });

    testWidgets('a draft that arrives after the first build still shows', (tester) async {
      when(
        () => harness.terminalRepository.getDraft(any()),
      ).thenAnswer((_) async => Result.success('run the sample task'));

      await pumpComposer(tester);
      expect(find.text('run the sample task'), findsNothing);

      await harness.cubit.fetchDraft();
      await tester.pump();
      await tester.pump();

      expect(find.text('run the sample task'), findsOneWidget);
    });

    testWidgets('an empty remote draft shows nothing', (tester) async {
      harness.cubit.draft = '';

      await pumpComposer(tester);

      expect(find.byType(TerminalComposerDraftHint), findsOneWidget);
      expect(find.descendant(of: find.byType(TerminalComposerDraftHint), matching: find.byType(AppText)), findsNothing);
    });
  });

  group('shell composer', () {
    setUp(useShell);

    testWidgets('rests as a 48pt glass capsule with no + and no model chip', (tester) async {
      await pumpComposer(tester);

      expect(card(tester).height, TerminalComposer.restHeight);
      final glass = tester.widget<GlassSurface>(find.byKey(TerminalComposer.capsuleKey));
      expect(glass.kind, GlassShapeKind.capsule);
      expect(glass.variant, GlassVariant.regular);
      expect(glass.size, TerminalComposer.restHeight);
      expect(find.byType(ComposerAddButton), findsNothing);
      expect(find.byType(ComposerModelChip), findsNothing);
    });

    testWidgets('typing swaps the microphone for send and clearing restores it', (tester) async {
      await pumpComposer(tester);
      expect(find.byType(MicKey), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();
      expect(find.byType(MicKey), findsNothing);
      expect(find.bySemanticsLabel('Send'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.byType(MicKey), findsOneWidget);
    });

    testWidgets('the trailing action cross-fades between mic and send', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      await tester.pump(AppMotion.chatActionSwap ~/ 2);
      expect(find.byType(MicKey), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(MicKey), findsNothing);
    });

    testWidgets('never offers stop', (tester) async {
      harness.commandCubit.onActivity('active');
      await pumpComposer(tester);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Stop'), findsNothing);
      expect(find.byType(MicKey), findsOneWidget);
    });

    testWidgets('the hint and its descenders fit the resting capsule, centred', (tester) async {
      await pumpComposer(tester);

      expectFieldFullyShown(tester, lines: 1);
      final hint = tester.renderObject<RenderParagraph>(find.text('Send to terminal...'));
      final field = tester.getRect(find.byType(TextField));
      expect(hint.size.height, lessThanOrEqualTo(field.height));
      expect((field.center.dy - card(tester).center.dy).abs(), lessThanOrEqualTo(1));
    });

    testWidgets('a newline grows the capsule into a card, and clearing collapses it', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField), 'first\nsecond');
      await tester.pump();
      await tester.pump(AppMotion.composerMorph ~/ 2);
      final midway = card(tester).height;
      await tester.pumpAndSettle();
      final grown = card(tester).height;

      expect(midway, greaterThan(TerminalComposer.restHeight));
      expect(midway, lessThan(grown));
      final expanded = tester.widget<GlassSurface>(find.byKey(TerminalComposer.capsuleKey));
      expect(expanded.kind, GlassShapeKind.roundedRect);
      expect(expanded.radius, TerminalComposer.cardRadius);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(card(tester).height, TerminalComposer.restHeight);
      expect(tester.widget<GlassSurface>(find.byKey(TerminalComposer.capsuleKey)).kind, GlassShapeKind.capsule);
    });

    testWidgets('text that wraps to a second line expands the capsule', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField), List.filled(12, 'wrapping words').join(' '));
      await tester.pumpAndSettle();

      expect(card(tester).height, greaterThan(TerminalComposer.restHeight));
    });

    testWidgets('losing focus collapses the card back to the capsule', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField), 'first\nsecond');
      await tester.pumpAndSettle();

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(card(tester).height, TerminalComposer.restHeight);
      expect(harness.cubit.composer.text, 'first\nsecond');
    });
  });
}
```

In `terminal_body_layout_test.dart`, replace the test `'the mic sits as far in from the capsule end as the text field does from the start'` with:

```dart
  testWidgets('the + and the mic sit in the card corners, the field keeps its inset', (tester) async {
    harness = TerminalHarness()..start(harness: 'claude-code', blockRecords: _conversation(1));
    await harness.pump(tester, const TerminalBody());
    await tester.pumpAndSettle();

    final dock = capsule(tester);
    final field = tester.getRect(find.descendant(of: find.byKey(TerminalComposer.capsuleKey), matching: find.byType(TextField)));
    final plus = tester.getRect(find.byType(ComposerAddButton));
    final mic = tester.getRect(find.byType(MicKey));
    expect(field.left - dock.left, 18);
    expect(plus.left - dock.left, 6);
    expect(dock.right - mic.right, 6);
    expect(dock.bottom - mic.bottom, 6);
  });
```

adding imports for `composer_add_button.dart` and `mic_key.dart`, and dropping the `composer_action_button.dart` import if nothing else in the file uses it.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/terminal/presentation/terminal_screen/ui/terminal_composer_test.dart test/feature/terminal/presentation/terminal_screen/ui/terminal_body_layout_test.dart`
Expected: compilation errors for `ComposerAddButton`, `ComposerAttachmentTray`, `ComposerSendSlot`.

- [ ] **Step 3: The trailing slot, the + and the tray**

Append to `composer_action_button.dart` (it already imports `app_motion.dart`, `skin_scope.dart` and `press_scale.dart`):

```dart
enum ComposerTrailing { none, send, stop }

ComposerTrailing composerTrailingFor({required bool hasContent, required bool canStop}) {
  if (hasContent) return ComposerTrailing.send;
  return canStop ? ComposerTrailing.stop : ComposerTrailing.none;
}

class ComposerSendSlot extends StatelessWidget {
  const ComposerSendSlot({super.key, required this.trailing, required this.staging, this.onSend, this.onStop});

  static const Key stagingKey = ValueKey('composer-staging');

  final ComposerTrailing trailing;
  final bool staging;
  final VoidCallback? onSend;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : AppMotion.chatActionSwap,
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeOut,
      transitionBuilder: _swapTransition,
      child: switch (trailing) {
        ComposerTrailing.send when staging => const Padding(
          key: stagingKey,
          padding: EdgeInsets.only(left: ComposerStopButton.gap),
          child: _StagingIndicator(),
        ),
        ComposerTrailing.send => Padding(
          key: const ValueKey(ComposerTrailing.send),
          padding: const EdgeInsets.only(left: ComposerStopButton.gap),
          child: _RoundAction(
            label: 'Send',
            icon: Icons.arrow_upward_rounded,
            color: skin.accent,
            ink: skin.onAccent,
            onTap: onSend,
          ),
        ),
        ComposerTrailing.stop => Padding(
          key: const ValueKey(ComposerTrailing.stop),
          padding: const EdgeInsets.only(left: ComposerStopButton.gap),
          child: _RoundAction(
            label: 'Stop',
            icon: Icons.stop_rounded,
            color: skin.red,
            ink: skin.onAccent,
            onTap: onStop,
          ),
        ),
        ComposerTrailing.none => const SizedBox.shrink(key: ValueKey(ComposerTrailing.none)),
      },
    );
  }
}

class _StagingIndicator extends StatelessWidget {
  const _StagingIndicator();

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Semantics(
      label: 'Uploading attachments',
      child: Container(
        width: ComposerActionButton.size,
        height: ComposerActionButton.size,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(color: skin.accent.withValues(alpha: 0.5), shape: BoxShape.circle),
        child: CircularProgressIndicator(strokeWidth: 2, color: skin.onAccent),
      ),
    );
  }
}
```

Create `composer_add_button.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/press_scale.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_action_button.dart';

class ComposerAddButton extends StatelessWidget {
  const ComposerAddButton({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final tap = onTap;
    return PressScale(
      scale: AppMotion.pressScaleSend,
      enabled: tap != null,
      child: Semantics(
        button: true,
        enabled: tap != null,
        label: 'Add context',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap == null
              ? null
              : () {
                  Haptics.tap();
                  tap();
                },
          child: Container(
            width: ComposerActionButton.size,
            height: ComposerActionButton.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: skin.textPrimary.withValues(alpha: 0.07), shape: BoxShape.circle),
            child: Icon(Icons.add_rounded, size: 22, color: tap == null ? skin.textFaint : skin.textPrimary),
          ),
        ),
      ),
    );
  }
}
```

Create `composer_attachment_tray.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

class ComposerAttachmentTray extends StatelessWidget {
  const ComposerAttachmentTray({
    super.key,
    required this.attachments,
    this.notice,
    this.onRemove,
    this.onDismissNotice,
  });

  static const double thumbSize = 56;
  static const double fileCardWidth = 148;
  static const double badgeSize = 22;
  static const Key noticeKey = ValueKey('composer-attachment-notice');

  final List<ComposerAttachment> attachments;
  final String? notice;
  final void Function(String id)? onRemove;
  final VoidCallback? onDismissNotice;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = notice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (attachments.isNotEmpty)
            SizedBox(
              height: thumbSize + badgeSize / 2,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(top: badgeSize / 2, right: badgeSize / 2),
                clipBehavior: Clip.none,
                itemCount: attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) => _TrayItem(attachment: attachments[index], onRemove: onRemove),
              ),
            ),
          if (text != null)
            GestureDetector(
              key: noticeKey,
              behavior: HitTestBehavior.opaque,
              onTap: onDismissNotice,
              child: Text(text, style: AppTextStyle.style12Medium.copyWith(color: skin.red)),
            ),
        ],
      ),
    );
  }
}

class _TrayItem extends StatelessWidget {
  const _TrayItem({required this.attachment, required this.onRemove});

  final ComposerAttachment attachment;
  final void Function(String id)? onRemove;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final remove = onRemove;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: attachment.isImage
              ? Image.memory(
                  attachment.bytes,
                  width: ComposerAttachmentTray.thumbSize,
                  height: ComposerAttachmentTray.thumbSize,
                  fit: BoxFit.cover,
                  cacheWidth: 168,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _FileCard(name: attachment.name, width: ComposerAttachmentTray.thumbSize),
                )
              : _FileCard(name: attachment.name, width: ComposerAttachmentTray.fileCardWidth),
        ),
        Positioned(
          top: -ComposerAttachmentTray.badgeSize / 2,
          right: -ComposerAttachmentTray.badgeSize / 2,
          child: Semantics(
            button: true,
            enabled: remove != null,
            label: 'Remove ${attachment.name}',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: remove == null ? null : () => remove(attachment.id),
              child: Container(
                width: ComposerAttachmentTray.badgeSize,
                height: ComposerAttachmentTray.badgeSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: skin.bgElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: skin.borderSubtle),
                ),
                child: Icon(Icons.close_rounded, size: 14, color: skin.textSecondary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.name, required this.width});

  final String name;
  final double width;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      width: width,
      height: ComposerAttachmentTray.thumbSize,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: skin.textPrimary.withValues(alpha: 0.07),
      child: Row(
        spacing: 8,
        children: [
          Icon(Icons.insert_drive_file_outlined, size: 20, color: skin.textSecondary),
          Expanded(
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.style12Medium.copyWith(color: skin.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
```

In `mic_key.dart`, add a `quiet` flag: constructor `const MicKey({super.key, this.prominent = false, this.quiet = false, this.size});`, field `final bool quiet;`, and in `build`:

```dart
        final round = widget.prominent || widget.quiet;
        final quietRest = widget.quiet && !live && !denied && !unavailable;
        final fill = quietRest
            ? skin.textPrimary.withValues(alpha: 0)
            : widget.prominent && !live && !denied
            ? skin.accent
            : live
            ? skin.red
            : denied
            ? skin.tintRed
            : unavailable
            ? skin.bgElevated
            : skin.tintBlue;
        final ink = quietRest
            ? skin.textSecondary
            : widget.prominent && !live && !denied
            ? skin.onAccent
            : live
            ? skin.textPrimary
            : denied
            ? skin.red
            : unavailable
            ? skin.textFaint
            : skin.blue;
```

then replace every `widget.prominent ? widget.diameter / 2 : 12` radius with `round ? widget.diameter / 2 : 12`, and the icon size expression with `round ? (widget.size == null ? 22 : widget.diameter / 2) : 18`.

- [ ] **Step 4: The two-row agent card**

In `terminal_composer.dart`:

1. Add imports: `composer_add_button.dart`, `composer_attachment_tray.dart`, `add_context_sheet.dart`.
2. Add `static const double _rowGap = 6;` next to the other constants.
3. In `_send`, make an attachment disable the `/model` shortcut: `final command = cubit.args.shellOnly || cubit.attachments.isNotEmpty ? null : parseModelCommand(cubit.composer.text);`
4. Add:

```dart
  Future<void> _openAddContext(BuildContext context) async {
    setState(() => _pickerOpen = true);
    await showAddContextSheet(context);
    if (!mounted) return;
    setState(() => _pickerOpen = false);
  }
```

5. Rename `_capsule` to `_shellCapsule` without touching its body, and in `build` change the innermost builder to `builder: (context, _) => cubit.args.shellOnly ? _shellCapsule(context, cubit, constraints.maxWidth) : _agentCard(context, cubit),`.
6. Add the agent card:

```dart
  Widget _agentCard(BuildContext context, TerminalCubit cubit) {
    final skin = context.skin;
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : AppMotion.composerMorph;
    final style = AppTextStyle.style17Regular.copyWith(color: skin.textPrimary, height: _lineSpacing);
    final commands = context.read<SessionCommandCubit>();
    final trailing = composerTrailingFor(hasContent: cubit.hasContent, canStop: commands.enabled('stop'));
    final editable = !cubit.sending;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cubit.attachments.isNotEmpty || cubit.attachmentNotice != null)
          ComposerAttachmentTray(
            attachments: cubit.attachments,
            notice: cubit.attachmentNotice,
            onRemove: editable ? cubit.removeAttachment : null,
            onDismissNotice: cubit.dismissAttachmentNotice,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(_textInset, _cardTop, _textInset, 0),
          child: Stack(
            children: [
              TextField(
                controller: cubit.composer,
                focusNode: _focus,
                minLines: 1,
                maxLines: TerminalComposer.maxLines,
                keyboardType: TextInputType.multiline,
                style: style,
                cursorColor: skin.accent,
                decoration: InputDecoration.collapsed(
                  hintText: 'Message the agent...',
                  hintStyle: style.copyWith(color: skin.textTertiary),
                  hintMaxLines: 1,
                ),
              ),
              const TerminalComposerDraftHint(),
            ],
          ),
        ),
        const SizedBox(height: _rowGap),
        Padding(
          padding: const EdgeInsets.fromLTRB(_buttonInset, 0, _buttonInset, _buttonInset),
          child: Row(
            children: [
              ComposerAddButton(onTap: editable ? () => unawaited(_openAddContext(context)) : null),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ComposerModelChip(
                    harness: cubit.args.harness,
                    onTap: () => unawaited(_openModelPicker(context, cubit.args.harness)),
                  ),
                ),
              ),
              if (keyboardUp)
                IconButton(
                  style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  tooltip: 'Hide keyboard',
                  onPressed: () => SystemChannels.textInput.invokeMethod<void>('TextInput.hide'),
                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: skin.textTertiary),
                ),
              const MicKey(quiet: true, size: ComposerActionButton.size),
              ComposerSendSlot(
                trailing: trailing,
                staging: cubit.staging,
                onSend: cubit.sending ? null : () => _send(context, cubit),
                onStop: commands.phases['stop'] == CommandPhase.sending ? null : () => unawaited(_stop(commands)),
              ),
            ],
          ),
        ),
      ],
    );

    return GlassSurface(
      key: TerminalComposer.capsuleKey,
      kind: GlassShapeKind.roundedRect,
      size: TerminalComposer.restHeight,
      radius: TerminalComposer.cardRadius,
      child: Material(
        type: MaterialType.transparency,
        child: reduceMotion
            ? body
            : AnimatedSize(
                duration: duration,
                curve: AppMotion.easeOut,
                alignment: Alignment.bottomCenter,
                child: body,
              ),
      ),
    );
  }
```

`_shellCapsule` still computes its own mic↔send swap and stop with `ComposerActionButton` and `ComposerStopButton`; nothing in the shell path changes.

- [ ] **Step 5: Run the tests and gates**

Run: `cd packages/mobile && flutter test test/feature/terminal test/feature/dictation test/feature/blocks`
Expected: PASS.

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 6: Simulator captures (batched by the controller at the end)**

Save to `packages/mobile/build/composer/task9/`, dark and light for each: `empty-{dark,light}.png` (resting two-row card), `typed-{dark,light}.png` (three lines typed, Send visible), `attachments-{dark,light}.png` (two photos and a PDF card in the tray), `working-{dark,light}.png` (Stop after the mic), `staging-dark.png` (progress in the send slot).

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart \
  packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/composer_action_button.dart \
  packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/composer_add_button.dart \
  packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/composer_attachment_tray.dart \
  packages/mobile/lib/feature/dictation/ui/mic_key.dart \
  packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_composer_test.dart \
  packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_body_layout_test.dart
git commit -m "feat(mobile): two-row composer with +, attachment tray and send progress

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 10: "Show recent photos" with `photo_manager`

**Files:**
- Modify: `packages/mobile/pubspec.yaml`, `packages/mobile/pubspec.lock` (via `flutter pub add`)
- Modify: `packages/mobile/ios/Runner/Info.plist` (limited-access alert key), `packages/mobile/android/app/src/main/AndroidManifest.xml` (media read permissions)
- Create: `packages/mobile/lib/feature/terminal/data/model/recent_photo_model.dart`
- Create: `packages/mobile/lib/feature/terminal/data/data_source/recent_photos_data_source.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/recent_photos_cubit.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/recent_photos_row.dart`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart` (`AddContextBody` children)
- Modify: `packages/mobile/lib/core/utils/service_locator.dart` (`_terminalFeatureSetup`)
- Test: `packages/mobile/test/feature/terminal/fake_recent_photos.dart` (new), `packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/recent_photos_cubit_test.dart` (new), `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/recent_photos_row_test.dart` (new), `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/add_context_sheet_test.dart`, `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_composer_test.dart`

**Interfaces:**
- Consumes: `ComposerAttachment` (Task 6); `TerminalCubit.hasAttachment`, `toggleAttachment`, `showAttachmentNotice` (Task 7); `AddContextBody`, `showAddContextSheet` (Task 8); `Disclosure`, `DisclosureChevron`, `SettingsGroup`.
- Produces:
  - `enum PhotoAccess { granted, limited, denied }`
  - `class RecentPhotoModel { const RecentPhotoModel({String? id, Uint8List? thumbnail}); }`
  - `abstract class RecentPhotosDataSource { Future<PhotoAccess> requestAccess(); Future<List<RecentPhotoModel>> latest(int count); Future<ComposerAttachment?> load(String id); Future<void> openSettings(); Future<void> manageLimited(); }`, `RecentPhotosDataSourceImp` over `photo_manager`, registered as `sl<RecentPhotosDataSource>()`.
  - `String recentPhotoAttachmentId(String assetId)` → `'photo:<assetId>'`.
  - `class RecentPhotosCubit extends Cubit<RecentPhotosState>` with `toggle()`, `load(String id)`, `openSettings()`, `manageLimited()`; `RecentPhotosState { bool expanded; bool loading; PhotoAccess? access; List<RecentPhotoModel> photos; }`; `const int kRecentPhotoCount = 30`.
  - `class RecentPhotosRow` with keys `RecentPhotosRow.rowKey`, `RecentPhotosRow.stripKey`, `RecentPhotosRow.manageKey`, and thumbnails keyed `ValueKey('recent-photo-<id>')`.

- [ ] **Step 1: Add the dependency and platform keys**

Run: `cd packages/mobile && flutter pub add photo_manager`
Expected: `pubspec.yaml` gains `photo_manager: ^<latest>` under `dependencies` and `pubspec.lock` resolves.

In `packages/mobile/ios/Runner/Info.plist`, next to `NSPhotoLibraryUsageDescription`:

```xml
		<key>PHPhotoLibraryPreventAutomaticLimitedAccessAlert</key>
		<true/>
```

In `packages/mobile/android/app/src/main/AndroidManifest.xml`, after the existing permissions:

```xml
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
```

- [ ] **Step 2: Write the failing tests**

Create `packages/mobile/test/feature/terminal/fake_recent_photos.dart`:

```dart
import 'dart:typed_data';

import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/recent_photo_model.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

class FakeRecentPhotos implements RecentPhotosDataSource {
  PhotoAccess access = PhotoAccess.granted;
  List<RecentPhotoModel> photos = [RecentPhotoModel(id: '1', thumbnail: Uint8List(4))];
  int? requested;
  int settings = 0;
  int manages = 0;

  @override
  Future<PhotoAccess> requestAccess() async => access;

  @override
  Future<List<RecentPhotoModel>> latest(int count) async {
    requested = count;
    return photos;
  }

  @override
  Future<ComposerAttachment?> load(String id) async =>
      ComposerAttachment(id: recentPhotoAttachmentId(id), name: 'photo-$id.jpg', mimeType: 'image/jpeg', bytes: Uint8List(2));

  @override
  Future<void> openSettings() async => settings++;

  @override
  Future<void> manageLimited() async => manages++;
}
```

Create `packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/recent_photos_cubit_test.dart`:

```dart
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/recent_photo_model.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/recent_photos_cubit.dart';

import '../../../fake_recent_photos.dart';

void main() {
  late FakeRecentPhotos source;

  setUp(() => source = FakeRecentPhotos());

  blocTest<RecentPhotosCubit, RecentPhotosState>(
    'expanding with access loads the latest 30 photos',
    build: () => RecentPhotosCubit(source),
    act: (cubit) => cubit.toggle(),
    expect: () => [
      const RecentPhotosState(expanded: true, loading: true),
      RecentPhotosState(expanded: true, access: PhotoAccess.granted, photos: source.photos),
    ],
    verify: (_) => expect(source.requested, kRecentPhotoCount),
  );

  blocTest<RecentPhotosCubit, RecentPhotosState>(
    'denied access collapses the row and never lists photos',
    build: () => RecentPhotosCubit(source..access = PhotoAccess.denied),
    act: (cubit) => cubit.toggle(),
    expect: () => [
      const RecentPhotosState(expanded: true, loading: true),
      const RecentPhotosState(access: PhotoAccess.denied),
    ],
    verify: (_) => expect(source.requested, isNull),
  );

  blocTest<RecentPhotosCubit, RecentPhotosState>(
    'limited access still lists the photos it may see, and manage reloads them',
    build: () => RecentPhotosCubit(source..access = PhotoAccess.limited),
    act: (cubit) async {
      await cubit.toggle();
      source.photos = [RecentPhotoModel(id: '2', thumbnail: Uint8List(1))];
      await cubit.manageLimited();
    },
    skip: 2,
    expect: () => [
      RecentPhotosState(expanded: true, access: PhotoAccess.limited, photos: [RecentPhotoModel(id: '2', thumbnail: Uint8List(1))]),
    ],
    verify: (_) => expect(source.manages, 1),
  );

  blocTest<RecentPhotosCubit, RecentPhotosState>(
    'toggling an open row collapses it without asking again',
    build: () => RecentPhotosCubit(source),
    seed: () => RecentPhotosState(expanded: true, access: PhotoAccess.granted, photos: source.photos),
    act: (cubit) => cubit.toggle(),
    expect: () => [RecentPhotosState(access: PhotoAccess.granted, photos: source.photos)],
    verify: (_) => expect(source.requested, isNull),
  );
}
```

Create `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/recent_photos_row_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/recent_photo_model.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/recent_photos_row.dart';

import '../../../fake_recent_photos.dart';
import '../../../terminal_harness.dart';

void main() {
  late TerminalHarness harness;
  late FakeRecentPhotos source;

  setUp(() {
    harness = TerminalHarness()..start(harness: 'claude-code');
    source = FakeRecentPhotos()
      ..photos = [
        RecentPhotoModel(id: '1', thumbnail: Uint8List(4)),
        RecentPhotoModel(id: '2', thumbnail: Uint8List(4)),
      ];
    if (sl.isRegistered<RecentPhotosDataSource>()) sl.unregister<RecentPhotosDataSource>();
    sl.registerSingleton<RecentPhotosDataSource>(source);
  });

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester) async {
    await harness.pump(
      tester,
      Builder(builder: (context) => TextButton(onPressed: () => showAddContextSheet(context), child: const Text('Open'))),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the row expands into a strip and a thumbnail toggles a checked attachment, keeping the sheet open', (tester) async {
    await open(tester);
    expect(find.text('Show recent photos'), findsOneWidget);

    await tester.tap(find.byKey(RecentPhotosRow.rowKey));
    await tester.pumpAndSettle();
    expect(find.byKey(RecentPhotosRow.stripKey), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recent-photo-1')));
    await tester.pumpAndSettle();
    expect(harness.cubit.hasAttachment('photo:1'), isTrue);
    expect(find.descendant(of: find.byKey(const ValueKey('recent-photo-1')), matching: find.byIcon(Icons.check_circle_rounded)), findsOneWidget);
    expect(find.text('Add context'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recent-photo-1')));
    await tester.pumpAndSettle();
    expect(harness.cubit.hasAttachment('photo:1'), isFalse);
  });

  testWidgets('denied access turns the row into Allow photo access, which opens Settings', (tester) async {
    source.access = PhotoAccess.denied;
    await open(tester);

    await tester.tap(find.byKey(RecentPhotosRow.rowKey));
    await tester.pumpAndSettle();
    expect(find.text('Allow photo access'), findsOneWidget);
    expect(find.byKey(RecentPhotosRow.stripKey), findsNothing);

    await tester.tap(find.byKey(RecentPhotosRow.rowKey));
    await tester.pumpAndSettle();
    expect(source.settings, 1);
  });

  testWidgets('limited access offers Manage', (tester) async {
    source.access = PhotoAccess.limited;
    await open(tester);

    await tester.tap(find.byKey(RecentPhotosRow.rowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RecentPhotosRow.manageKey));
    await tester.pumpAndSettle();

    expect(source.manages, 1);
  });
}
```

In `add_context_sheet_test.dart`, import `../../../fake_recent_photos.dart` and `recent_photos_data_source.dart`, and in `setUp` register a fake the same way (`if (sl.isRegistered<RecentPhotosDataSource>()) sl.unregister<RecentPhotosDataSource>(); sl.registerSingleton<RecentPhotosDataSource>(FakeRecentPhotos());`) so the sheet can build its new row. Do the same in the `setUp` of `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_composer_test.dart` (its `tapping + opens Add context` test builds the sheet).

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/terminal/presentation/terminal_screen/logic/recent_photos_cubit_test.dart test/feature/terminal/presentation/terminal_screen/ui/recent_photos_row_test.dart`
Expected: compilation errors: the data source, model, cubit and row do not exist.

- [ ] **Step 4: Model and data source**

`packages/mobile/lib/feature/terminal/data/model/recent_photo_model.dart`:

```dart
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

class RecentPhotoModel extends Equatable {
  const RecentPhotoModel({this.id, this.thumbnail});

  final String? id;
  final Uint8List? thumbnail;

  @override
  List<Object?> get props => [id, thumbnail?.length];
}
```

`packages/mobile/lib/feature/terminal/data/data_source/recent_photos_data_source.dart`:

```dart
import 'package:photo_manager/photo_manager.dart';
import 'package:operator_mobile/feature/terminal/data/model/recent_photo_model.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

enum PhotoAccess { granted, limited, denied }

String recentPhotoAttachmentId(String assetId) => 'photo:$assetId';

abstract class RecentPhotosDataSource {
  Future<PhotoAccess> requestAccess();
  Future<List<RecentPhotoModel>> latest(int count);
  Future<ComposerAttachment?> load(String id);
  Future<void> openSettings();
  Future<void> manageLimited();
}

class RecentPhotosDataSourceImp implements RecentPhotosDataSource {
  static const int thumbnailSide = 200;
  static const int fullSide = 2048;
  static const int quality = 85;

  @override
  Future<PhotoAccess> requestAccess() async {
    final state = await PhotoManager.requestPermissionExtend();
    return switch (state) {
      PermissionState.authorized => PhotoAccess.granted,
      PermissionState.limited => PhotoAccess.limited,
      _ => PhotoAccess.denied,
    };
  }

  @override
  Future<List<RecentPhotoModel>> latest(int count) async {
    final albums = await PhotoManager.getAssetPathList(type: RequestType.image, onlyAll: true);
    if (albums.isEmpty) return const [];
    final assets = await albums.first.getAssetListPaged(page: 0, size: count);
    return [
      for (final asset in assets)
        RecentPhotoModel(
          id: asset.id,
          thumbnail: await asset.thumbnailDataWithSize(const ThumbnailSize.square(thumbnailSide), quality: quality),
        ),
    ];
  }

  @override
  Future<ComposerAttachment?> load(String id) async {
    final asset = await AssetEntity.fromId(id);
    if (asset == null) return null;
    final bytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(fullSide, fullSide),
      format: ThumbnailFormat.jpeg,
      quality: quality,
    );
    if (bytes == null) return null;
    return ComposerAttachment(id: recentPhotoAttachmentId(id), name: 'photo-${id.hashCode.toUnsigned(32)}.jpg', mimeType: 'image/jpeg', bytes: bytes);
  }

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Future<void> manageLimited() => PhotoManager.presentLimited();
}
```

The full-size read asks `photo_manager` for a 2048 px JPEG, which converts HEIC and keeps a photo well under the 10 MiB cap. If the installed `photo_manager` major version names any of these APIs differently, match its README; the seam above is the only file that imports the package.

Register in `_terminalFeatureSetup`:

```dart
    sl.registerLazySingleton<RecentPhotosDataSource>(RecentPhotosDataSourceImp.new);
```

- [ ] **Step 5: The cubit**

`packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/recent_photos_cubit.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/recent_photo_model.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

const int kRecentPhotoCount = 30;

class RecentPhotosState extends Equatable {
  const RecentPhotosState({this.expanded = false, this.loading = false, this.access, this.photos = const []});

  final bool expanded;
  final bool loading;
  final PhotoAccess? access;
  final List<RecentPhotoModel> photos;

  @override
  List<Object?> get props => [expanded, loading, access, photos];
}

class RecentPhotosCubit extends Cubit<RecentPhotosState> {
  RecentPhotosCubit(this._source) : super(const RecentPhotosState());

  final RecentPhotosDataSource _source;

  Future<void> toggle() async {
    if (state.expanded) {
      emit(RecentPhotosState(access: state.access, photos: state.photos));
      return;
    }
    emit(const RecentPhotosState(expanded: true, loading: true));
    final access = await _source.requestAccess();
    if (isClosed) return;
    if (access == PhotoAccess.denied) {
      emit(const RecentPhotosState(access: PhotoAccess.denied));
      return;
    }
    final photos = await _source.latest(kRecentPhotoCount);
    if (isClosed) return;
    emit(RecentPhotosState(expanded: true, access: access, photos: photos));
  }

  Future<ComposerAttachment?> load(String id) => _source.load(id);

  Future<void> openSettings() => _source.openSettings();

  Future<void> manageLimited() async {
    await _source.manageLimited();
    final photos = await _source.latest(kRecentPhotoCount);
    if (isClosed) return;
    emit(RecentPhotosState(expanded: true, access: state.access, photos: photos));
  }
}
```

- [ ] **Step 6: The row**

`packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/recent_photos_row.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/recent_photo_model.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/recent_photos_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class RecentPhotosRow extends StatelessWidget {
  const RecentPhotosRow({super.key});

  static const Key rowKey = ValueKey('recent-photos-row');
  static const Key stripKey = ValueKey('recent-photos-strip');
  static const Key manageKey = ValueKey('recent-photos-manage');
  static const double thumbSize = 72;

  @override
  Widget build(BuildContext context) => BlocProvider<RecentPhotosCubit>(
    create: (_) => RecentPhotosCubit(sl<RecentPhotosDataSource>()),
    child: const _RecentPhotosView(),
  );
}

class _RecentPhotosView extends StatelessWidget {
  const _RecentPhotosView();

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocBuilder<RecentPhotosCubit, RecentPhotosState>(
      builder: (context, state) {
        final cubit = context.read<RecentPhotosCubit>();
        final denied = state.access == PhotoAccess.denied;
        return SettingsGroup(
          children: [
            SettingsRow(
              key: RecentPhotosRow.rowKey,
              icon: denied ? Icons.lock_outline_rounded : Icons.photo_outlined,
              label: denied ? 'Allow photo access' : 'Show recent photos',
              trailing: denied
                  ? Icon(Icons.open_in_new_rounded, size: 16, color: skin.textFaint)
                  : DisclosureChevron(expanded: state.expanded, color: skin.textFaint),
              onTap: () {
                Haptics.tap();
                unawaited(denied ? cubit.openSettings() : cubit.toggle());
              },
            ),
            Disclosure(
              expanded: state.expanded,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    SizedBox(
                      key: RecentPhotosRow.stripKey,
                      height: RecentPhotosRow.thumbSize,
                      child: state.loading
                          ? Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: skin.accent)))
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: state.photos.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 8),
                              itemBuilder: (context, index) => _RecentPhotoThumb(photo: state.photos[index]),
                            ),
                    ),
                    if (state.access == PhotoAccess.limited)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: RecentPhotosRow.manageKey,
                          onPressed: () => unawaited(cubit.manageLimited()),
                          child: Text('Manage', style: AppTextStyle.style13Medium.copyWith(color: skin.accentText)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecentPhotoThumb extends StatelessWidget {
  const _RecentPhotoThumb({required this.photo});

  final RecentPhotoModel photo;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final id = photo.id ?? '';
    final thumbnail = photo.thumbnail;
    return BlocBuilder<TerminalCubit, TerminalState>(
      builder: (context, _) {
        final terminal = context.read<TerminalCubit>();
        final selected = terminal.hasAttachment(recentPhotoAttachmentId(id));
        return Semantics(
          button: true,
          selected: selected,
          label: 'Recent photo',
          child: GestureDetector(
            key: ValueKey('recent-photo-$id'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_toggle(context, terminal, id, selected)),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: thumbnail == null
                      ? Container(width: RecentPhotosRow.thumbSize, height: RecentPhotosRow.thumbSize, color: skin.bgElevated)
                      : Image.memory(
                          thumbnail,
                          width: RecentPhotosRow.thumbSize,
                          height: RecentPhotosRow.thumbSize,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => Container(
                            width: RecentPhotosRow.thumbSize,
                            height: RecentPhotosRow.thumbSize,
                            color: skin.bgElevated,
                          ),
                        ),
                ),
                if (selected)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Icon(Icons.check_circle_rounded, size: 20, color: skin.accent),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> _toggle(BuildContext context, TerminalCubit terminal, String id, bool selected) async {
  Haptics.select();
  if (selected) {
    terminal.removeAttachment(recentPhotoAttachmentId(id));
    return;
  }
  final attachment = await context.read<RecentPhotosCubit>().load(id);
  if (attachment == null) {
    terminal.showAttachmentNotice("That photo couldn't be loaded.");
    return;
  }
  terminal.toggleAttachment(attachment);
}
```

`SettingsRow` has no `key` passthrough today if its constructor lacks `super.key`; it does (`const SettingsRow({super.key, ...})`), so `RecentPhotosRow.rowKey` lands on it.

In `add_context_sheet.dart`, add `const RecentPhotosRow(),` as the second child of `AddContextBody`'s `Column`, after the tiles `Row`, and import `recent_photos_row.dart`.

- [ ] **Step 7: Run the tests and gates**

Run: `cd packages/mobile && flutter test test/feature/terminal`
Expected: PASS.

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

Native code changed (a new plugin and plist/manifest keys), so also run:
Run: `cd packages/mobile && flutter build ios --release --no-codesign`
Expected: `Built build/ios/iphoneos/Runner.app`.

- [ ] **Step 8: Simulator captures (batched by the controller at the end)**

Save to `packages/mobile/build/composer/task10/`: `strip-{dark,light}.png` (row expanded, two thumbnails checked), `denied-dark.png` (Allow photo access), `limited-dark.png` (strip with Manage).

- [ ] **Step 9: Commit**

```bash
git add packages/mobile/pubspec.yaml packages/mobile/pubspec.lock packages/mobile/ios/Runner/Info.plist \
  packages/mobile/android/app/src/main/AndroidManifest.xml \
  packages/mobile/lib/feature/terminal/data/model/recent_photo_model.dart \
  packages/mobile/lib/feature/terminal/data/data_source/recent_photos_data_source.dart \
  packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/recent_photos_cubit.dart \
  packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/recent_photos_row.dart \
  packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart \
  packages/mobile/lib/core/utils/service_locator.dart \
  packages/mobile/test/feature/terminal/fake_recent_photos.dart \
  packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/recent_photos_cubit_test.dart \
  packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/recent_photos_row_test.dart \
  packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/add_context_sheet_test.dart \
  packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_composer_test.dart
git commit -m "feat(mobile): Show recent photos strip in Add context

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

If `ios/Podfile.lock` changed during the build, add it to the same commit.

---
### Task 11: Permission row and page inside the sheet, with the live mode

**Files:**
- Create: `packages/mobile/lib/feature/terminal/logic/permission_modes.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/permission_mode_cubit.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/permission_mode_page.dart`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart` (scope and body)
- Modify: `packages/mobile/lib/feature/sessions/data/model/session_model.dart`
- Modify: `packages/mobile/lib/feature/blocks/data/model/params/session_command_params.dart`, `packages/mobile/lib/feature/blocks/data/model/session_command_result_model.dart`
- Modify: `packages/mobile/lib/feature/blocks/logic/block_assembly.dart:36-38`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart` (`_terminalFeatureSetup`), `packages/mobile/lib/core/app_routes/app_router.dart:116-150`, `packages/mobile/lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart:108-132`
- Modify: `packages/mobile/test/feature/terminal/terminal_harness.dart`
- Test: `packages/mobile/test/feature/terminal/logic/permission_modes_test.dart` (new), `packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/permission_mode_cubit_test.dart` (new), `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/permission_mode_page_test.dart` (new), `packages/mobile/test/feature/sessions/data/model/session_model_test.dart`, `packages/mobile/test/feature/blocks/logic/block_assembly_test.dart`

**Interfaces:**
- Consumes: the daemon contract from Tasks 3 and 5 (`permissionMode`, `capabilities.permissionMode`, `capabilities.permissionModeCycle` on sessions; the `permission-mode` command and its response and codes; `permission_mode` block events with the mode in `text`); `showAddContextSheet`, `AddContextBody` (Tasks 8, 10); `SessionControlRepository.sendCommand`; `MuxClient.blockEvents`.
- Produces:
  - `const List<String> kPermissionModes` (display order: bypass-permissions, auto, accept-edits, plan, default), `String permissionModeLabel(String? mode)`, `String permissionModeRefusal(String? code)`, `const String kPermissionRestartNote`, `const String kPermissionModeEventKind`.
  - `class PermissionModeState { String? mode; bool supported; List<String> cycle; String? pending; String? error; bool restarts(String target); }`
  - `class PermissionModeCubit extends Cubit<PermissionModeState> { PermissionModeCubit(MuxClient mux, SessionControlRepository control, {required String sessionId, required SessionModel? Function() session, required Stream<Object?> sessionChanges}); Future<bool> choose(String mode); }`, registered as `sl<PermissionModeCubit>(param1: sessionId)`.
  - `class PermissionModeRow` (key `PermissionModeRow.rowKey`), `AppSheetPage permissionModePage()`, `class PermissionModeList` (option keys `ValueKey('permission-mode-<mode>')`, error key `PermissionModeList.errorKey`).
  - `SessionModel.permissionMode`, `SessionModel.permissionModeSupported`, `SessionModel.permissionModeCycle`; `SessionCommandParams.mode`; `SessionCommandResultModel.permissionMode`, `.restarted`.
  - `TerminalHarness.start({..., SessionModel? session})`, `TerminalHarness.permissionCubit`, `TerminalHarness.sessionChanges`.

- [ ] **Step 1: Write the failing tests**

Create `packages/mobile/test/feature/terminal/logic/permission_modes_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/permission_modes.dart';

void main() {
  test('every mode has the phone label, with Ask for default', () {
    expect(kPermissionModes, ['bypass-permissions', 'auto', 'accept-edits', 'plan', 'default']);
    expect(kPermissionModes.map(permissionModeLabel), ['Bypass permissions', 'Auto', 'Accept edits', 'Plan', 'Ask']);
    expect(permissionModeLabel(null), 'Ask');
  });

  test('refusals name the reason', () {
    expect(permissionModeRefusal('SESSION_BUSY'), 'The agent is working — try again when it is idle');
    expect(permissionModeRefusal('SESSION_COMMAND_UNAVAILABLE'), 'The agent is working — try again when it is idle');
    expect(permissionModeRefusal('SESSION_AWAITING_DECISION'), 'Answer the permission request first');
    expect(permissionModeRefusal('PERMISSION_MODE_UNSUPPORTED'), "This agent can't change mode from the phone");
    expect(permissionModeRefusal('PERMISSION_MODE_UNCONFIRMED'), "The terminal didn't confirm the new mode");
    expect(permissionModeRefusal(null), "Couldn't change the permission mode");
  });
}
```

Create `packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/permission_mode_cubit_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_command_result_model.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/permission_mode_cubit.dart';

class _MockMuxClient extends Mock implements MuxClient {}

class _MockControl extends Mock implements SessionControlRepository {}

const _claudeSession = SessionModel(
  id: 's-1',
  harness: 'claude-code',
  permissionMode: 'bypass-permissions',
  permissionModeSupported: true,
  permissionModeCycle: ['default', 'accept-edits', 'plan', 'bypass-permissions'],
);

BlockEventEnvelope modeEvent(String mode, {String sessionId = 's-1', String? agentId}) => BlockEventEnvelope(sessionId, {
  'seq': 9,
  'sessionId': sessionId,
  'kind': 'permission_mode',
  'text': mode,
  'agentId': ?agentId,
});

void main() {
  late _MockMuxClient mux;
  late _MockControl control;
  late StreamController<BlockEventEnvelope> events;
  late StreamController<Object?> sessionChanges;
  late SessionModel? session;

  setUpAll(() => registerFallbackValue(const SessionCommandParams(command: '')));

  setUp(() {
    mux = _MockMuxClient();
    control = _MockControl();
    events = StreamController<BlockEventEnvelope>.broadcast();
    sessionChanges = StreamController<Object?>.broadcast();
    session = _claudeSession;
    when(() => mux.blockEvents).thenAnswer((_) => events.stream);
  });

  tearDown(() async {
    await events.close();
    await sessionChanges.close();
  });

  PermissionModeCubit build() => PermissionModeCubit(
    mux,
    control,
    sessionId: 's-1',
    session: () => session,
    sessionChanges: sessionChanges.stream,
  );

  test('seeds the mode, support and cycle from the session', () async {
    final cubit = build();

    expect(cubit.state.mode, 'bypass-permissions');
    expect(cubit.state.supported, isTrue);
    expect(cubit.state.restarts('auto'), isTrue);
    expect(cubit.state.restarts('plan'), isFalse);
    await cubit.close();
  });

  test('a desktop-side change arriving as a block event updates the mode', () async {
    final cubit = build();

    events.add(modeEvent('plan'));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.mode, 'plan');
    await cubit.close();
  });

  test('another session and a subagent never move the mode', () async {
    final cubit = build();

    events
      ..add(modeEvent('plan', sessionId: 's-2'))
      ..add(modeEvent('plan', agentId: 'agent-1'));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.mode, 'bypass-permissions');
    await cubit.close();
  });

  test('choosing sends the permission-mode command and keeps the confirmed mode', () async {
    when(() => control.sendCommand(any(), any())).thenAnswer(
      (_) async => Result.success(const GlobalResponse(data: SessionCommandResultModel(state: 'sent', permissionMode: 'plan'))),
    );
    final cubit = build();

    expect(await cubit.choose('plan'), isTrue);

    verify(() => control.sendCommand('s-1', const SessionCommandParams(command: 'permission-mode', mode: 'plan'))).called(1);
    expect(cubit.state.mode, 'plan');
    expect(cubit.state.pending, isNull);
    await cubit.close();
  });

  test('a failed change reverts to the last observed mode and says why', () async {
    final reply = Completer<Result<GlobalResponse<SessionCommandResultModel>, Failure>>();
    when(() => control.sendCommand(any(), any())).thenAnswer((_) => reply.future);
    final cubit = build();

    final choosing = cubit.choose('auto');
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.pending, 'auto');
    expect(cubit.state.mode, 'auto');
    events.add(modeEvent('accept-edits'));
    await Future<void>.delayed(Duration.zero);
    reply.complete(Result.failure(ServerFailure(error: 'x', message: 'busy', apiStatus: 'SESSION_BUSY')));

    expect(await choosing, isFalse);
    expect(cubit.state.mode, 'accept-edits');
    expect(cubit.state.pending, isNull);
    expect(cubit.state.error, 'The agent is working — try again when it is idle');
    await cubit.close();
  });

  test('a second choice while one is in flight is ignored', () async {
    final reply = Completer<Result<GlobalResponse<SessionCommandResultModel>, Failure>>();
    when(() => control.sendCommand(any(), any())).thenAnswer((_) => reply.future);
    final cubit = build();

    unawaited(cubit.choose('plan'));
    await Future<void>.delayed(Duration.zero);
    expect(await cubit.choose('auto'), isFalse);
    verify(() => control.sendCommand(any(), any())).called(1);

    reply.complete(Result.success(const GlobalResponse(data: SessionCommandResultModel(permissionMode: 'plan'))));
    await cubit.close();
  });

  test('a session refresh turns support on once the daemon reports it', () async {
    session = const SessionModel(id: 's-1', harness: 'claude-code', permissionMode: 'bypass-permissions');
    final cubit = build();
    expect(cubit.state.supported, isFalse);

    session = _claudeSession;
    sessionChanges.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.supported, isTrue);
    expect(cubit.state.cycle, contains('plan'));
    await cubit.close();
  });
}
```

Create `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/permission_mode_page_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_command_result_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/logic/permission_modes.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/permission_mode_page.dart';

import '../../../fake_recent_photos.dart';
import '../../../terminal_harness.dart';

const _supported = SessionModel(
  id: 's-1',
  harness: 'claude-code',
  permissionMode: 'bypass-permissions',
  permissionModeSupported: true,
  permissionModeCycle: ['default', 'accept-edits', 'plan', 'bypass-permissions'],
);

void main() {
  late TerminalHarness harness;

  setUpAll(() => registerFallbackValue(const SessionCommandParams(command: '')));

  setUp(() {
    if (sl.isRegistered<RecentPhotosDataSource>()) sl.unregister<RecentPhotosDataSource>();
    sl.registerSingleton<RecentPhotosDataSource>(FakeRecentPhotos());
  });

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester, SessionModel session) async {
    harness = TerminalHarness()..start(harness: 'claude-code', session: session);
    await harness.pump(
      tester,
      Builder(builder: (context) => TextButton(onPressed: () => showAddContextSheet(context), child: const Text('Open'))),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> openPage(WidgetTester tester) async {
    await open(tester, _supported);
    await tester.tap(find.byKey(PermissionModeRow.rowKey));
    await tester.pumpAndSettle();
  }

  Finder check(String mode) =>
      find.descendant(of: find.byKey(ValueKey('permission-mode-$mode')), matching: find.byIcon(Icons.check_rounded));

  testWidgets('a harness without support shows no Permission row', (tester) async {
    await open(tester, const SessionModel(id: 's-1', harness: 'codex', permissionMode: 'default'));

    expect(find.byKey(PermissionModeRow.rowKey), findsNothing);
  });

  testWidgets('the row reads Permission and the current mode', (tester) async {
    await open(tester, _supported);

    expect(find.text('Permission'), findsOneWidget);
    expect(find.text('Bypass permissions'), findsOneWidget);
  });

  testWidgets('the page lists every mode, checks the current one and notes restarts', (tester) async {
    await openPage(tester);

    for (final mode in kPermissionModes) {
      expect(find.byKey(ValueKey('permission-mode-$mode')), findsOneWidget);
    }
    expect(check('bypass-permissions'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('permission-mode-auto')), matching: find.text(kPermissionRestartNote)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('permission-mode-plan')), matching: find.text(kPermissionRestartNote)), findsNothing);
  });

  testWidgets('choosing a mode applies it and returns to the sheet showing it', (tester) async {
    await openPage(tester);
    when(() => harness.controlRepository.sendCommand(any(), any())).thenAnswer(
      (_) async => Result.success(const GlobalResponse(data: SessionCommandResultModel(state: 'sent', permissionMode: 'plan'))),
    );

    await tester.tap(find.byKey(const ValueKey('permission-mode-plan')));
    await tester.pumpAndSettle();

    verify(() => harness.controlRepository.sendCommand('s-1', const SessionCommandParams(command: 'permission-mode', mode: 'plan'))).called(1);
    expect(find.byKey(PermissionModeRow.rowKey), findsOneWidget);
    expect(find.descendant(of: find.byKey(PermissionModeRow.rowKey), matching: find.text('Plan')), findsOneWidget);
  });

  testWidgets('a failure stays on the page, reverts the check and shows why', (tester) async {
    await openPage(tester);
    final reply = Completer<Result<GlobalResponse<SessionCommandResultModel>, Failure>>();
    when(() => harness.controlRepository.sendCommand(any(), any())).thenAnswer((_) => reply.future);

    await tester.tap(find.byKey(const ValueKey('permission-mode-auto')));
    await tester.pump();
    expect(check('auto'), findsNothing);
    reply.complete(Result.failure(ServerFailure(error: 'x', message: 'busy', apiStatus: 'SESSION_BUSY')));
    await tester.pumpAndSettle();

    expect(find.byKey(PermissionModeList.errorKey), findsOneWidget);
    expect(find.text('The agent is working — try again when it is idle'), findsOneWidget);
    expect(check('bypass-permissions'), findsOneWidget);
    expect(find.byKey(const ValueKey('permission-mode-auto')), findsOneWidget);
  });
}
```

In `packages/mobile/test/feature/sessions/data/model/session_model_test.dart`, add inside the group:

```dart
    test('parses the permission mode and its capabilities, and tolerates their absence', () {
      final session = SessionModel.fromJson({
        'id': 'a',
        'permissionMode': 'plan',
        'capabilities': {
          'permissionMode': true,
          'permissionModeCycle': ['default', 'accept-edits', 'plan'],
        },
      });
      expect(session.permissionMode, 'plan');
      expect(session.permissionModeSupported, isTrue);
      expect(session.permissionModeCycle, ['default', 'accept-edits', 'plan']);

      final bare = SessionModel.fromJson({'id': 'b'});
      expect(bare.permissionMode, isNull);
      expect(bare.permissionModeSupported, isNull);
      expect(bare.permissionModeCycle, isNull);
    });
```

In `packages/mobile/test/feature/blocks/logic/block_assembly_test.dart`, add inside `group('assembleBlocks', ...)`:

```dart
    test('a permission_mode event is bookkeeping, not a block', () {
      expect(assembleBlocks([_event(1, 'permission_mode', text: 'plan', source: 'transcript')]), isEmpty);
    });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/terminal/logic/permission_modes_test.dart test/feature/terminal/presentation/terminal_screen/logic/permission_mode_cubit_test.dart test/feature/sessions/data/model/session_model_test.dart test/feature/blocks/logic/block_assembly_test.dart`
Expected: compilation errors for the new files and fields; the block-assembly test fails with one `notice` block.

- [ ] **Step 3: Wire models, params and block assembly**

`session_model.dart`: add constructor parameters and fields `permissionMode` (`String?`), `permissionModeSupported` (`bool?`), `permissionModeCycle` (`List<String>?`), add them to `props`, and in `fromJson`:

```dart
    permissionMode: json['permissionMode'] as String?,
    permissionModeSupported: _capabilities(json)?['permissionMode'] as bool?,
    permissionModeCycle: (_capabilities(json)?['permissionModeCycle'] as List<dynamic>?)?.whereType<String>().toList(),
```

with

```dart
  static Map<String, dynamic>? _capabilities(Map<String, dynamic> json) {
    final capabilities = json['capabilities'];
    return capabilities is Map<String, dynamic> ? capabilities : null;
  }
```

`session_command_params.dart`:

```dart
class SessionCommandParams extends Equatable {
  final String command;
  final String? model;
  final String? mode;

  const SessionCommandParams({required this.command, this.model, this.mode});

  Map<String, dynamic> toJson() => {
    'command': command,
    if (model != null) 'model': model,
    if (mode != null) 'mode': mode,
  };

  @override
  List<Object?> get props => [command, model, mode];
}
```

`session_command_result_model.dart`:

```dart
class SessionCommandResultModel extends Equatable {
  final String? state;
  final List<String>? models;
  final String? permissionMode;
  final bool? restarted;

  const SessionCommandResultModel({this.state, this.models, this.permissionMode, this.restarted});

  factory SessionCommandResultModel.fromJson(Map<String, dynamic> json) => SessionCommandResultModel(
    state: json['state'] as String?,
    models: (json['models'] as List?)?.map((e) => e as String).toList(),
    permissionMode: json['permissionMode'] as String?,
    restarted: json['restarted'] as bool?,
  );

  @override
  List<Object?> get props => [state, models, permissionMode, restarted];
}
```

`block_assembly.dart`: add `case 'permission_mode':` to the `case 'idle_prompt': case 'session_start': continue;` group.

- [ ] **Step 4: Vocabulary and cubit**

`packages/mobile/lib/feature/terminal/logic/permission_modes.dart`:

```dart
const String kPermissionModeEventKind = 'permission_mode';

const List<String> kPermissionModes = ['bypass-permissions', 'auto', 'accept-edits', 'plan', 'default'];

const String kPermissionRestartNote = 'Restarts the agent; the conversation continues';

String permissionModeLabel(String? mode) => switch (mode) {
  'bypass-permissions' => 'Bypass permissions',
  'auto' => 'Auto',
  'accept-edits' => 'Accept edits',
  'plan' => 'Plan',
  _ => 'Ask',
};

String permissionModeRefusal(String? code) => switch (code) {
  'SESSION_BUSY' || 'SESSION_COMMAND_UNAVAILABLE' => 'The agent is working — try again when it is idle',
  'SESSION_AWAITING_DECISION' => 'Answer the permission request first',
  'PERMISSION_MODE_UNSUPPORTED' => "This agent can't change mode from the phone",
  'PERMISSION_MODE_UNCONFIRMED' => "The terminal didn't confirm the new mode",
  'SESSION_NOT_RUNNING' => "The agent isn't running",
  'SESSION_NOT_FOUND' => 'Session not found',
  _ => "Couldn't change the permission mode",
};
```

`packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/permission_mode_cubit.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/terminal/logic/permission_modes.dart';

class PermissionModeState extends Equatable {
  const PermissionModeState({this.mode, this.supported = false, this.cycle = const [], this.pending, this.error});

  final String? mode;
  final bool supported;
  final List<String> cycle;
  final String? pending;
  final String? error;

  bool restarts(String target) => !cycle.contains(target);

  PermissionModeState copyWith({
    String? mode,
    bool? supported,
    List<String>? cycle,
    String? pending,
    bool clearPending = false,
    String? error,
    bool clearError = false,
  }) => PermissionModeState(
    mode: mode ?? this.mode,
    supported: supported ?? this.supported,
    cycle: cycle ?? this.cycle,
    pending: clearPending ? null : pending ?? this.pending,
    error: clearError ? null : error ?? this.error,
  );

  @override
  List<Object?> get props => [mode, supported, cycle, pending, error];
}

class PermissionModeCubit extends Cubit<PermissionModeState> {
  PermissionModeCubit(
    this._mux,
    this._control, {
    required this.sessionId,
    required SessionModel? Function() session,
    required Stream<Object?> sessionChanges,
  }) : _session = session,
       super(_fromSession(session())) {
    _observed = state.mode;
    _eventsSub = _mux.blockEvents.where((envelope) => envelope.sessionId == sessionId).listen(_onEvent);
    _sessionsSub = sessionChanges.listen((_) => _onSession());
  }

  final MuxClient _mux;
  final SessionControlRepository _control;
  final String sessionId;
  final SessionModel? Function() _session;

  String? _observed;
  bool _eventSeen = false;
  StreamSubscription<BlockEventEnvelope>? _eventsSub;
  StreamSubscription<Object?>? _sessionsSub;

  static PermissionModeState _fromSession(SessionModel? session) => PermissionModeState(
    mode: session?.permissionMode,
    supported: session?.permissionModeSupported ?? false,
    cycle: session?.permissionModeCycle ?? const [],
  );

  void _onEvent(BlockEventEnvelope envelope) {
    final event = BlockEventModel.fromJson(envelope.block);
    if (event.kind != kPermissionModeEventKind || (event.agentId ?? '').isNotEmpty) return;
    final mode = event.text;
    if (mode == null || !kPermissionModes.contains(mode)) return;
    _eventSeen = true;
    _observed = mode;
    if (state.pending != null) return;
    emit(state.copyWith(mode: mode, clearError: true));
  }

  void _onSession() {
    final fresh = _fromSession(_session());
    final mode = _eventSeen ? null : fresh.mode;
    if (mode != null) _observed = mode;
    emit(state.copyWith(
      mode: state.pending == null ? mode : null,
      supported: fresh.supported,
      cycle: fresh.cycle,
    ));
  }

  Future<bool> choose(String mode) async {
    if (state.pending != null) return false;
    if (mode == state.mode) return true;
    emit(state.copyWith(mode: mode, pending: mode, clearError: true));
    final result = await _control.sendCommand(
      sessionId,
      SessionCommandParams(command: 'permission-mode', mode: mode),
    );
    if (isClosed) return false;
    var applied = false;
    result.when(
      onSuccess: (response) {
        final confirmed = response.data?.permissionMode ?? mode;
        _observed = confirmed;
        applied = true;
        emit(state.copyWith(mode: confirmed, clearPending: true));
      },
      onFailure: (failure) => emit(PermissionModeState(
        mode: _observed,
        supported: state.supported,
        cycle: state.cycle,
        error: permissionModeRefusal(failure.apiStatus),
      )),
    );
    return applied;
  }

  @override
  Future<void> close() {
    unawaited(_eventsSub?.cancel());
    unawaited(_sessionsSub?.cancel());
    return super.close();
  }
}
```

Register in `_terminalFeatureSetup` (import `session_control_repository.dart`, `sessions_cubit.dart` is already imported, and the cubit):

```dart
    sl.registerFactoryParam<PermissionModeCubit, String, void>(
      (sessionId, _) => PermissionModeCubit(
        sl<MuxClient>(),
        sl<SessionControlRepository>(),
        sessionId: sessionId,
        session: () => sl<SessionsCubit>().sessions.where((session) => session.id == sessionId).firstOrNull,
        sessionChanges: sl<SessionsCubit>().stream,
      ),
    );
```

Provide it where the terminal screen's cubits are built:
- `session_route_screen.dart`, inside the `MultiBlocProvider` providers list after `SessionCommandCubit`: `BlocProvider<PermissionModeCubit>(create: (_) => sl<PermissionModeCubit>(param1: args.sessionId)),`
- `app_router.dart`, in the `RoutesStrings.terminal` providers after the `PreviewCubit` entry: `if (!terminalArgs.shellOnly) BlocProvider<PermissionModeCubit>(create: (_) => sl<PermissionModeCubit>(param1: terminalArgs.sessionId)),`

- [ ] **Step 5: The row and the page**

`packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/permission_mode_page.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/terminal/logic/permission_modes.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/permission_mode_cubit.dart';

class PermissionModeRow extends StatelessWidget {
  const PermissionModeRow({super.key});

  static const Key rowKey = ValueKey('permission-mode-row');

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocBuilder<PermissionModeCubit, PermissionModeState>(
      builder: (context, state) {
        if (!state.supported) return const SizedBox.shrink();
        final error = state.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            SettingsGroup(
              children: [
                SettingsRow(
                  key: rowKey,
                  icon: Icons.shield_outlined,
                  label: 'Permission',
                  value: permissionModeLabel(state.pending ?? state.mode),
                  loading: state.pending != null,
                  onTap: () => AppSheet.of(context).push(permissionModePage()),
                ),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(error, style: AppTextStyle.style12Medium.copyWith(color: skin.red)),
              ),
          ],
        );
      },
    );
  }
}

AppSheetPage permissionModePage() => AppSheetPage(
  title: 'Permission',
  subtitle: 'How much the agent asks before it acts.',
  rows: (context, _) => const [PermissionModeList()],
);

class PermissionModeList extends StatelessWidget {
  const PermissionModeList({super.key});

  static const Key errorKey = ValueKey('permission-mode-error');

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocBuilder<PermissionModeCubit, PermissionModeState>(
      builder: (context, state) {
        final cubit = context.read<PermissionModeCubit>();
        final selected = state.pending ?? state.mode ?? 'default';
        final error = state.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            SettingsGroup(
              children: [
                for (final mode in kPermissionModes)
                  _PermissionModeOption(
                    key: ValueKey('permission-mode-$mode'),
                    mode: mode,
                    selected: mode == selected && state.pending == null,
                    busy: state.pending == mode,
                    restarts: state.restarts(mode),
                    onTap: state.pending != null ? null : () => unawaited(_choose(context, cubit, mode)),
                  ),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(error, key: errorKey, style: AppTextStyle.style12Medium.copyWith(color: skin.red)),
              ),
          ],
        );
      },
    );
  }
}

Future<void> _choose(BuildContext context, PermissionModeCubit cubit, String mode) async {
  Haptics.select();
  final sheet = AppSheet.of(context);
  if (await cubit.choose(mode)) sheet.pop();
}

class _PermissionModeOption extends StatelessWidget {
  const _PermissionModeOption({
    super.key,
    required this.mode,
    required this.selected,
    required this.busy,
    required this.restarts,
    required this.onTap,
  });

  final String mode;
  final bool selected;
  final bool busy;
  final bool restarts;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Semantics(
      button: true,
      selected: selected,
      label: permissionModeLabel(mode),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 2,
                    children: [
                      Text(permissionModeLabel(mode), style: AppTextStyle.style15Regular.copyWith(color: skin.textPrimary)),
                      if (restarts)
                        Text(kPermissionRestartNote, style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary)),
                    ],
                  ),
                ),
                if (busy)
                  SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: skin.accent))
                else if (selected)
                  Icon(Icons.check_rounded, size: 18, color: skin.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

In `add_context_sheet.dart` (import `permission_mode_cubit.dart` and `permission_mode_page.dart`):
- read the cubit in `showAddContextSheet` (`final permission = context.read<PermissionModeCubit>();`) and change `scope` to

```dart
    scope: (sheetContext, sheet) => MultiBlocProvider(
      providers: [
        BlocProvider<TerminalCubit>.value(value: terminal),
        BlocProvider<PermissionModeCubit>.value(value: permission),
      ],
      child: sheet,
    ),
```

- add `const PermissionModeRow(),` as the last child of `AddContextBody`'s `Column`.

- [ ] **Step 6: Give the test harness the cubit**

In `packages/mobile/test/feature/terminal/terminal_harness.dart`:
- add fields `final StreamController<Object?> sessionChanges = StreamController<Object?>.broadcast();`, `SessionModel? session;` and `late PermissionModeCubit permissionCubit;`;
- change `start` to take `SessionModel? session` as a named parameter, set `this.session = session;` first, and at the end of `start` add:

```dart
    permissionCubit = PermissionModeCubit(
      mux,
      controlRepository,
      sessionId: cubit.args.sessionId,
      session: () => this.session,
      sessionChanges: sessionChanges.stream,
    );
```

- add `BlocProvider<PermissionModeCubit>.value(value: permissionCubit),` to the `MultiBlocProvider` in `pump`;
- in `dispose`, add `await permissionCubit.close();` before `await blockEvents.close();` and `await sessionChanges.close();` after it.

Import `session_model.dart` and `permission_mode_cubit.dart` in the harness.

- [ ] **Step 7: Run the tests and gates**

Run: `cd packages/mobile && flutter test test/feature/terminal test/feature/sessions test/feature/blocks`
Expected: PASS.

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 8: Simulator captures (batched by the controller at the end)**

Save to `packages/mobile/build/composer/task11/`: `row-{dark,light}.png` (Add context with the Permission row reading Bypass permissions), `page-{dark,light}.png` (the pushed page, check on the current mode, restart notes under Auto), `error-dark.png` (a refused change with its inline error).

- [ ] **Step 9: Commit**

```bash
git add packages/mobile/lib/feature/terminal/logic/permission_modes.dart \
  packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/permission_mode_cubit.dart \
  packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/permission_mode_page.dart \
  packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart \
  packages/mobile/lib/feature/sessions/data/model/session_model.dart \
  packages/mobile/lib/feature/blocks/data/model/params/session_command_params.dart \
  packages/mobile/lib/feature/blocks/data/model/session_command_result_model.dart \
  packages/mobile/lib/feature/blocks/logic/block_assembly.dart \
  packages/mobile/lib/core/utils/service_locator.dart packages/mobile/lib/core/app_routes/app_router.dart \
  packages/mobile/lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart \
  packages/mobile/test/feature/terminal/terminal_harness.dart \
  packages/mobile/test/feature/terminal/logic/permission_modes_test.dart \
  packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/permission_mode_cubit_test.dart \
  packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/permission_mode_page_test.dart \
  packages/mobile/test/feature/sessions/data/model/session_model_test.dart \
  packages/mobile/test/feature/blocks/logic/block_assembly_test.dart
git commit -m "feat(mobile): permission row and page in Add context, following the live mode

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 12: Spawn options — Permission, defaulting to Bypass

**Files:**
- Modify: `packages/mobile/lib/feature/spawn/data/model/params/spawn_session_params.dart`
- Modify: `packages/mobile/lib/feature/spawn/logic/spawn_option_values.dart`
- Modify: `packages/mobile/lib/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart:14-126`
- Modify: `packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_option_rows.dart`
- Modify: `packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_options_sheet.dart:29-34`
- Test: `packages/mobile/test/feature/spawn/presentation/spawn_screen/logic/spawn_cubit_test.dart`, `packages/mobile/test/feature/spawn/presentation/spawn_screen/ui/spawn_options_sheet_test.dart`

**Interfaces:**
- Consumes: `kPermissionModes`, `permissionModeLabel` (Task 11); the daemon's spawn `permissionMode` (Task 1).
- Produces:
  - `SpawnSessionParams.permissionMode` (`String?`), sent as `permissionMode`.
  - `SpawnOption.permission`; `SpawnOptionValues.permissionModesFor(String harness) → List<String>` (no `plan` unless `claude-code`), `SpawnOptionValues.permissionValue(String mode) → String`.
  - `const String kDefaultSpawnPermissionMode = 'bypass-permissions'`; `SpawnCubit.permissionMode`, `SpawnCubit.setPermissionMode(String)`.
  - Option rows keyed `ValueKey('spawn-permission-<mode>')`.

- [ ] **Step 1: Write the failing tests**

Add to `spawn_cubit_test.dart` (import `spawn_option_values.dart`):

```dart
  blocTest<SpawnCubit, SpawnState>(
    'spawns in bypass permissions unless another mode is chosen',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setProject('p');
      cubit.name = 'flaky login';
      cubit.prompt = 'fix it';
      await cubit.submit();
      cubit.setPermissionMode('accept-edits');
      await cubit.submit();
    },
    verify: (cubit) {
      final captured = verify(() => repository.spawn(captureAny())).captured.cast<SpawnSessionParams>();
      expect(captured.map((params) => params.permissionMode), ['bypass-permissions', 'accept-edits']);
      expect(captured.first.toJson()['permissionMode'], 'bypass-permissions');
    },
  );

  test('plan is offered only for Claude Code and falls back to bypass on another agent', () async {
    final cubit = buildCubit();
    await cubit.loadCatalog();
    cubit.setHarness('claude-code');
    cubit.setPermissionMode('plan');

    cubit.setHarness('codex');

    expect(cubit.permissionMode, kDefaultSpawnPermissionMode);
    expect(SpawnOptionValues.permissionModesFor('codex'), isNot(contains('plan')));
    expect(SpawnOptionValues.permissionModesFor('claude-code'), contains('plan'));
    await cubit.close();
  });

  test('a params object without a permission mode sends none', () {
    expect(const SpawnSessionParams(projectId: 'p').toJson().containsKey('permissionMode'), isFalse);
    expect(const SpawnSessionParams(projectId: 'p', permissionMode: 'auto').toJson()['permissionMode'], 'auto');
  });
```

Add to `spawn_options_sheet_test.dart`:

```dart
  testWidgets('the permission option defaults to Bypass and picking one pops back showing it', (tester) async {
    await open(tester, SpawnOption.permission);

    expect(
      find.descendant(of: find.byKey(const ValueKey('spawn-permission-bypass-permissions')), matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('spawn-permission-plan')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('spawn-permission-accept-edits')));
    await tester.pumpAndSettle();

    expect(cubit.permissionMode, 'accept-edits');
    expect(find.text('Spawn options'), findsOneWidget);
    expect(find.text('Accept edits'), findsOneWidget);
  });

  testWidgets('the root lists Permission reading Bypass permissions', (tester) async {
    await open(tester, SpawnOption.agent);
    await tester.tap(find.byKey(AppSheet.backKey));
    await tester.pumpAndSettle();

    expect(find.text('Permission'), findsOneWidget);
    expect(find.text('Bypass permissions'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/spawn`
Expected: compilation errors for `permissionMode`, `setPermissionMode`, `SpawnOption.permission`, `permissionModesFor`.

- [ ] **Step 3: Implement**

`spawn_session_params.dart`: add `this.permissionMode` to the constructor, `final String? permissionMode;`, `if (permissionMode != null && permissionMode!.isNotEmpty) 'permissionMode': permissionMode,` to `toJson`, and `permissionMode` to `props`.

`spawn_option_values.dart`:

```dart
enum SpawnOption { project, agent, account, permission }
```

and inside `SpawnOptionValues` (import `package:operator_mobile/feature/terminal/logic/permission_modes.dart`):

```dart
  static List<String> permissionModesFor(String harness) =>
      harness == 'claude-code' ? kPermissionModes : kPermissionModes.where((mode) => mode != 'plan').toList();

  static String permissionValue(String mode) => permissionModeLabel(mode);
```

`spawn_cubit.dart` (import `spawn_option_values.dart`): add above the class

```dart
const String kDefaultSpawnPermissionMode = 'bypass-permissions';
```

add the field `String permissionMode = kDefaultSpawnPermissionMode;`, the setter

```dart
  void setPermissionMode(String next) {
    permissionMode = next;
    _bump();
  }
```

in `setHarness`, before `_bump();`:

```dart
    if (!SpawnOptionValues.permissionModesFor(next).contains(permissionMode)) {
      permissionMode = kDefaultSpawnPermissionMode;
    }
```

and pass `permissionMode: permissionMode,` in the `SpawnSessionParams(...)` built by `submit`.

`spawn_option_rows.dart`: append after the account row:

```dart
    SettingsRow(
      icon: Icons.shield_outlined,
      label: 'Permission',
      value: SpawnOptionValues.permissionValue(cubit.permissionMode),
      onTap: () => onOpen(SpawnOption.permission),
    ),
```

`spawn_options_sheet.dart`: add `SpawnOption.permission => _permissionPage(cubit),` to `pageFor`, import `skin_scope.dart` and `permission_modes.dart`, and add:

```dart
AppSheetPage _permissionPage(SpawnCubit cubit) => AppSheetPage(
  title: 'Permission',
  subtitle: 'How much the agent asks before it acts.',
  rows: (context, _) => [
    BlocBuilder<SpawnCubit, SpawnState>(
      builder: (context, _) => SettingsGroup(
        children: [
          for (final mode in SpawnOptionValues.permissionModesFor(cubit.harness))
            SettingsRow(
              key: ValueKey('spawn-permission-$mode'),
              label: permissionModeLabel(mode),
              trailing: mode == cubit.permissionMode
                  ? Icon(Icons.check_rounded, size: 18, color: context.skin.accent)
                  : const SizedBox.shrink(),
              onTap: () {
                cubit.setPermissionMode(mode);
                AppSheet.of(context).pop();
              },
            ),
        ],
      ),
    ),
  ],
);
```

- [ ] **Step 4: Run the tests and gates**

Run: `cd packages/mobile && flutter test test/feature/spawn test/core/telemetry`
Expected: PASS.

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 5: Simulator captures (batched by the controller at the end)**

Save to `packages/mobile/build/composer/task12/`: `options-{dark,light}.png` (Spawn options with Permission · Bypass permissions), `permission-dark.png` (the pushed permission page).

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib/feature/spawn/data/model/params/spawn_session_params.dart \
  packages/mobile/lib/feature/spawn/logic/spawn_option_values.dart \
  packages/mobile/lib/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart \
  packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_option_rows.dart \
  packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_options_sheet.dart \
  packages/mobile/test/feature/spawn/presentation/spawn_screen/logic/spawn_cubit_test.dart \
  packages/mobile/test/feature/spawn/presentation/spawn_screen/ui/spawn_options_sheet_test.dart
git commit -m "feat(mobile): spawn options choose a permission mode, Bypass by default

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Documentation

**Files:**
- Modify: `CLAUDE.md` (Mobile client → Architecture, after the **Phone alerts.** paragraph)
- Modify: `docs/architecture.md` (new `#### Permission mode` after `#### Background tasks`, before `### Durable shell-block capture`)
- Modify: `docs/STATUS.md` (Mobile (Flutter) list)

**Interfaces:**
- Consumes: everything above; no code.
- Produces: docs only.

- [ ] **Step 1: CLAUDE.md**

Insert after the **Phone alerts.** paragraph:

```markdown
**Composer attachments and permission mode.** The agent composer is a two-row
glass card: the text on top, then **+**, the model chip, the mic, and one slot
for Send or Stop. **+** opens the Add context sheet (Camera, Photos, Files,
Show recent photos via `photo_manager`, and a Permission row). Attachments are
admitted against the daemon's caps (8 files, 10 MiB each, 25 MiB total, no
SVG), staged with `POST /sessions/{id}/attachments`, and named in the message
in the daemon's own reference format (`attachment_references.dart` mirrors
`appendAttachmentReferences`). A failed stage or send keeps the text and the
attachments, and a retry reuses already staged paths. The Permission row shows
only when the session DTO's `capabilities.permissionMode` is true; the live
mode comes from `permission_mode` block events, and a change goes through the
`permission-mode` session command, which answers `restarted: true` when it had
to relaunch the agent with `--resume`. Phone spawns default to
`bypass-permissions`.
```

- [ ] **Step 2: docs/architecture.md**

Insert before `### Durable shell-block capture`:

```markdown
#### Permission mode

Claude Code writes `{"type":"permission-mode","permissionMode":…}` at start
and on every live change, and stamps `permissionMode` and `version` on user
records. The per-tail mapper turns either into a `permission_mode` block event
(Operator's mode in `text`, `{"mode","version"}` in `detail`) only when the
mode or the version changes, and `permission_mode` rows sit outside the
per-session trim so the latest one survives. The session DTO reports that
mode as `permissionMode` (falling back to the durable
`sessions.launch_permission_mode`, written at spawn and by a mode restart and
used by every resume), plus `capabilities.permissionMode` and
`capabilities.permissionModeCycle`.

`POST /api/v1/sessions/{id}/command` with `{"command":"permission-mode","mode":…}`
has two paths, both refusing rather than guessing, and both allow-listed to the
Claude Code version the footer reader was checked against:

- **In the Shift+Tab cycle** (Ask, Accept edits, Plan, plus Bypass or Auto
  when the agent was launched in it): under the same exclusive per-session
  pane drive as the task stop, on an idle session only, the daemon reads the
  composer footer, presses Shift+Tab, and waits for the footer to change,
  at most six times. It stops at the target, stops when the footer is no
  longer readable (a dialog opened), and stops when the cycle returns to its
  start. A miss is `PERMISSION_MODE_UNCONFIRMED`.
- **Outside the cycle**: input admission closes, the daemon waits a settle
  interval and re-checks that the agent is still idle (`SESSION_BUSY`
  otherwise), then relaunches through the ordinary `--resume` path with the new
  `--permission-mode` and records it as the launch mode.
```

- [ ] **Step 3: docs/STATUS.md**

Append to the Mobile (Flutter) list:

```markdown
- The agent composer attaches camera shots, library photos, files and recent
  photos (staged into the worktree and named in the message), and reads and
  changes a Claude Code session's permission mode from the Add context sheet;
  phone spawns start in Bypass permissions.
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md docs/architecture.md docs/STATUS.md
git commit -m "docs: composer attachments and the permission-mode command

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Controller: end-of-branch verification (not an implementer task)

Run after all thirteen tasks are merged into the branch and reviewed.

1. Gates on the whole branch: backend `go build ./... && go vet ./... && go test ./...`, golangci-lint v2.12.2, API regeneration byte-check (regenerate twice, no diff against the committed files); mobile `flutter analyze` (`No issues found!`), `flutter test`, `flutter build ios --release --no-codesign`.
2. Run an isolated daemon for the phone per the memory notes (scrubbed `CLAUDE*` env, isolated data dir); never restart the user's daemon or `tauri:dev`.
3. Simulator captures, dark and light, into `packages/mobile/build/composer/<task>/` as listed in Tasks 8-12.
4. On a scratch Claude Code session the controller spawns for this check (never a user session):
   - send one photo with no text to the idle session and confirm the agent reads `.operator/attachments/attachment-*.jpg`;
   - after the first turn, confirm `GET /api/v1/sessions/{id}` reports `permissionMode` and `capabilities.permissionMode: true`;
   - change Bypass → Plan from the phone (Shift+Tab path), confirm the desktop footer reads `⏸ plan mode on` and the phone row reads Plan;
   - press Shift+Tab on the desktop and confirm the phone row follows without reopening;
   - choose Auto (restart path) on the idle session, confirm `restarted: true`, the conversation continues, and the footer reads `⏵⏵ auto mode on`;
   - start a long turn and confirm choosing Ask is refused with the inline "The agent is working" error and nothing restarts.
5. Record any footer text that differs from the reader's markers and update `permission_mode.go`'s markers and tests before merge.
