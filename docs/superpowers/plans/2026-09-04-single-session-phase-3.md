# Single Session Kind, Phase 3 — Control: the phone can act

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the mobile blocks view real control over a TUI session — approve or deny a permission dialog, answer a question, stop the agent, compact, and change the model — by writing screen-verified keystrokes into the pty and confirming each action by observation.

**Architecture:** Every phone action becomes a keystroke sequence written to the session's pty through `runtime.SendInput`, guarded by the same activity-state rules that guard `send`. Actions that touch an on-screen dialog first read the pane through `runtime.GetOutput` and check a per-harness pure predicate before writing, then read again to confirm the screen moved. Confirmation of *effect* is left to the client, which already streams block events and activity patches and can correlate them itself — the daemon reports only "the write happened and the screen moved".

**Tech Stack:** Go 1.x (backend, chi router, sqlc/SQLite, code-first OpenAPI via `specgen`), Flutter 3.44.5 (mobile, cubit-only, no codegen in first-party code).

**Spec:** [`docs/superpowers/specs/2026-09-04-single-session-interface-design.md`](../specs/2026-09-04-single-session-interface-design.md) — Phase 3. Read the whole spec; this plan implements only Phase 3 and assumes Phases 1 and 2 have shipped (they have, on `master`).

---

## Findings that correct the spec

Verified against the code on 2026-09-04, before this plan was written. **Implement what this section says, not the spec sentence it corrects.** Each is recorded here rather than silently applied so an executor reading both documents knows which wins.

1. **Pane reading is `runtime.GetOutput`, not `ports.PaneCapturer`.** The spec says "Pane capture is behind `ports.PaneCapturer`, driven by `service/terminalcapture`, and the idle detector already uses it". It does not. `ports.PaneCapturer` is a *streaming* capture (`StartCapture`/`StopCapture`) that pipes a pane to a file for the shell-terminal block recorder. The synchronous read the idle detector actually uses is `m.runtime.GetOutput(ctx, handle, lines)` ([`message_delivery.go:76`](../../../backend/internal/session_manager/message_delivery.go)), which returns the last N lines of the pty-host ring buffer. **This plan uses `GetOutput` everywhere and never touches `PaneCapturer`.**

2. **The raw-write primitive already exists.** `ptyhost.Runtime.SendInput(ctx, handle, input)` writes raw bytes with no Enter appended and is already on the `runtimeselect.Runtime` interface ([`runtimeselect.go:23`](../../../backend/internal/adapters/runtime/runtimeselect/runtimeselect.go)). Nothing new is needed at the runtime layer. It is *not* on `session_manager`'s narrower `runtimeController` interface ([`manager.go:200`](../../../backend/internal/session_manager/manager.go)), so Task 1 widens that interface by one method.

3. **The permission hook does not reliably carry `tool_use_id`.** The spec's Phase 3 says the hook "registers a pending approval carrying `tool_use_id`, `tool_name` and `tool_input`". Claude Code's `PermissionRequest` payload carries the tool *name* but not its id — this is why `applyToolPrecedenceLocked` correlates by name and **fails closed when two same-name tools are in flight** ([`lifecycle/manager.go:795-830`](../../../backend/internal/lifecycle/manager.go)). Therefore **the pending interaction gets a daemon-minted id**, not the tool's. This is strictly better: the phone answers *the dialog on screen*, of which there is only ever one, so no correlation is needed to act. Correlation is only needed to *confirm*, and confirmation is the client's job (finding 4).

4. **There is no server-side confirmation registry.** The spec's three states are a client concern. The daemon returns `sent` when the write landed and the screen moved; the phone already receives block events and activity patches over the mux and correlates the confirming signal itself, with its own timeout for *unconfirmed*. Building a server-side pending-confirmation table would duplicate state the client already has, so it is not built. The spec's "pending-interaction resource … streamed like other session state" is satisfied by putting the interaction id on the block event that already streams, plus one `GET` for reconnect reconciliation (Task 8).

5. **`send` cannot carry a control byte.** `domain.SanitizeControlChars` strips them, which is why the mobile raw key row goes through the mux instead ([`keys.dart:3`](../../../packages/mobile/lib/feature/terminal/logic/keys.dart)). Every keystroke in this plan therefore goes through `SendInput`, never through the send path.

## Global Constraints

- **Go tests and lint gate every backend task.** `npm run lint` from the repo root runs `go test ./...` plus golangci-lint and must exit 0 issues.
- **Any new or changed HTTP route requires a `specgen` entry and regeneration.** Add the route to [`internal/httpd/apispec/specgen/build.go`](../../../backend/internal/httpd/apispec/specgen/build.go), then run `npm run api` from the repo root (regenerates `openapi.yaml` and `frontend/src/api/schema.ts`). `git status --porcelain` must be empty after regenerating.
- **Error envelope is locked:** `{error, code, message, requestId}` via `envelope.WriteAPIError(w, r, status, kind, code, message, details)`. `code` is machine-readable; the mobile UI branches on it. Never drop `requestId`.
- **Mobile gates:** from `packages/mobile`, `flutter analyze` must print `No issues found!` and `flutter test` must be fully green. CI pins Flutter **3.44.5**.
- **Mobile conventions:** Cubit only, never `Bloc` with events. No `freezed`, no `json_serializable` in first-party code — hand-written models, all fields nullable, `fromJson` does wire→domain mapping. One params class per method under `data/model/params/`. Parameterized paths get static methods on `EndPoints`; interpolating at a call site is forbidden. Feature code never imports `flutter_screenutil`. User-facing copy is inline English.
- **No comments in new code** unless the surrounding file's density calls for them; where this plan's code blocks carry comments, they explain a non-obvious invariant and should be kept.
- **Every parse is** `GlobalResponse.fromJson(response.data, withDataKey: false)` — the daemon does not use the `data` key.
- **Scope searches.** `.worktrees/` and `.claude/worktrees/` hold nested checkouts; a repo-root `grep` matches stale duplicates. Scope to `backend/internal`, `packages/mobile/lib`, `packages/mobile/test`.

## File Structure

**Backend — new**

| file | responsibility |
|---|---|
| `internal/domain/sessioncommand.go` | The command vocabulary (`stop`, `compact`, `model`) and its parse/validate. Pure. |
| `internal/session_manager/command.go` | `Manager.Command` — precondition, write, and (for `model`) driver invocation. |
| `internal/session_manager/command_test.go` | Table tests over a fake runtime and store. |
| `internal/service/dialogdriver/driver.go` | Generic capture → predicate → write → re-capture → moved-check loop. Harness-agnostic. |
| `internal/service/dialogdriver/driver_test.go` | Tests against a scripted fake screen. |
| `internal/adapters/agent/claudecode/dialog.go` | Claude Code's pure screen readers and key map. |
| `internal/adapters/agent/claudecode/dialog_test.go` | Fixture-driven tests. |
| `internal/adapters/agent/codex/dialog.go` | Codex's pure screen readers and key map. |
| `internal/adapters/agent/codex/dialog_test.go` | Fixture-driven tests. |
| `internal/session_manager/interaction.go` | The pending-interaction registry: register on hook, resolve on decision, expire on turn boundary. |
| `internal/session_manager/interaction_test.go` | |
| `testdata/panes/*.txt` | Captured pane fixtures, content replaced. |

**Backend — modified**

| file | change |
|---|---|
| `internal/session_manager/manager.go` | Widen `runtimeController` with `SendInput`; add `ErrWrongActivityState`, `ErrDialogAbsent`, `ErrModelNotOffered`, `ErrUnconfirmed`; hold the interaction registry and the driver. |
| `internal/ports/agent.go` | New optional adapter capabilities `TerminalDialogReader` and `TerminalKeyMap`. |
| `internal/httpd/controllers/sessions.go` | Three routes: `POST .../command`, `POST .../decision`, `POST .../answer`; one `GET .../interactions`. |
| `internal/httpd/controllers/dto.go` | Their request/response DTOs. |
| `internal/httpd/apispec/specgen/build.go` | Their spec entries. |
| `internal/domain/blockevent.go` | `InteractionID` on the block event record. |
| `internal/lifecycle/manager.go` | Register an interaction when a `permission-request` signal arrives; clear it at a turn boundary. |

**Mobile — new**

| file | responsibility |
|---|---|
| `lib/feature/blocks/data/model/params/session_command_params.dart` | |
| `lib/feature/blocks/data/model/params/session_decision_params.dart` | |
| `lib/feature/blocks/data/model/params/session_answer_params.dart` | |
| `lib/feature/blocks/data/model/session_command_result_model.dart` | |
| `lib/feature/blocks/data/data_source/session_control_remote_data_source.dart` | |
| `lib/feature/blocks/data/repository/session_control_repository.dart` | |
| `lib/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart` | Per-action three-state machine and client-side confirmation correlation. |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/session_command_row.dart` | The three buttons. |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/model_picker_sheet.dart` | |
| `lib/feature/blocks/logic/command_confirmation.dart` | Pure: does this event confirm this pending command? |

**Mobile — modified**

| file | change |
|---|---|
| `lib/core/api/api_request_helpers/end_points.dart` | Four new path methods. |
| `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart` | Render `SessionCommandRow` in blocks mode. |
| `lib/feature/blocks/logic/session_block.dart` | `interactionId` on the block. |
| `lib/feature/blocks/logic/block_assembly.dart` | Carry `interactionId` through the merge. |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart` | Actionable permission block. |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_question_options.dart` | Real, tappable options. |

---

## Task 1: The command vocabulary and `stop`

The cheapest end-to-end proof that the write path works: one control byte, one precondition, no screen reading.

**Files:**
- Create: `backend/internal/domain/sessioncommand.go`
- Create: `backend/internal/session_manager/command.go`
- Create: `backend/internal/session_manager/command_test.go`
- Modify: `backend/internal/session_manager/manager.go:200-207` (widen `runtimeController`), `:32-103` (new error vars)

**Interfaces:**
- Produces: `domain.SessionCommand` (string type) with `domain.CommandStop`, `domain.CommandCompact`, `domain.CommandModel`; `domain.ParseSessionCommand(string) (SessionCommand, bool)`; `(*Manager).Command(ctx context.Context, id domain.SessionID, cmd domain.SessionCommand, model string) (CommandResult, error)`; `CommandResult{Wrote bool; Models []string}`; errors `ErrWrongActivityState`, `ErrDialogAbsent`, `ErrModelNotOffered`.
- Consumes: nothing from earlier tasks.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/session_manager/command_test.go`:

```go
package sessionmanager

import (
	"context"
	"errors"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeCommandRuntime struct {
	inputs  []string
	output  string
	sendErr error
}

func (f *fakeCommandRuntime) Create(context.Context, ports.RuntimeConfig) (ports.RuntimeHandle, error) {
	return ports.RuntimeHandle{}, nil
}
func (f *fakeCommandRuntime) Destroy(context.Context, ports.RuntimeHandle) error { return nil }
func (f *fakeCommandRuntime) IsAlive(context.Context, ports.RuntimeHandle) (bool, error) {
	return true, nil
}
func (f *fakeCommandRuntime) GetOutput(context.Context, ports.RuntimeHandle, int) (string, error) {
	return f.output, nil
}
func (f *fakeCommandRuntime) SendInput(_ context.Context, _ ports.RuntimeHandle, input string) error {
	if f.sendErr != nil {
		return f.sendErr
	}
	f.inputs = append(f.inputs, input)
	return nil
}

func TestCommandStopWritesEscapeWhileActive(t *testing.T) {
	rt := &fakeCommandRuntime{}
	m := newCommandTestManager(t, rt, domain.ActivityActive)

	res, err := m.Command(context.Background(), "s1", domain.CommandStop, "")
	if err != nil {
		t.Fatalf("Command: %v", err)
	}
	if !res.Wrote {
		t.Fatal("expected Wrote=true")
	}
	if len(rt.inputs) != 1 || rt.inputs[0] != "\x1b" {
		t.Fatalf("expected exactly one Esc write, got %q", rt.inputs)
	}
}

func TestCommandStopRefusedWhileIdleAndWritesNothing(t *testing.T) {
	rt := &fakeCommandRuntime{}
	m := newCommandTestManager(t, rt, domain.ActivityIdle)

	_, err := m.Command(context.Background(), "s1", domain.CommandStop, "")
	if !errors.Is(err, ErrWrongActivityState) {
		t.Fatalf("expected ErrWrongActivityState, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("a refused command must write nothing, got %q", rt.inputs)
	}
}

func TestCommandRejectsUnknownVerb(t *testing.T) {
	if _, ok := domain.ParseSessionCommand("rm -rf"); ok {
		t.Fatal("expected an unknown verb to be rejected")
	}
	for _, verb := range []string{"stop", "compact", "model"} {
		if _, ok := domain.ParseSessionCommand(verb); !ok {
			t.Fatalf("expected %q to parse", verb)
		}
	}
}
```

Add the helper at the bottom of the same file. Build the `Manager` the way the existing tests in this package do — copy the construction from the nearest existing `newTestManager`-style helper in `manager_test.go` rather than inventing one, and set the session's activity state and `Metadata.RuntimeHandleID` on the stored record:

```go
func newCommandTestManager(t *testing.T, rt *fakeCommandRuntime, state domain.ActivityState) *Manager {
	t.Helper()
	m := newTestManagerWithRuntime(t, rt)
	seedSession(t, m, domain.SessionRecord{
		ID:       "s1",
		Harness:  "claude-code",
		Activity: domain.SessionActivity{State: state},
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	})
	return m
}
```

If `newTestManagerWithRuntime` and `seedSession` do not exist under those names, write thin equivalents in this file only — do not refactor the package's existing helpers.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd backend && go test ./internal/session_manager/ -run TestCommand -v
```

Expected: FAIL to compile — `undefined: domain.CommandStop`, `undefined: ErrWrongActivityState`, `m.Command undefined`.

- [ ] **Step 3: Write the domain vocabulary**

Create `backend/internal/domain/sessioncommand.go`:

```go
package domain

// SessionCommand is a control action a client may drive into a TUI session's
// pty. The set is closed: these are the only verbs the daemon will type on a
// client's behalf, so an unrecognised string is rejected rather than typed.
type SessionCommand string

const (
	CommandStop    SessionCommand = "stop"
	CommandCompact SessionCommand = "compact"
	CommandModel   SessionCommand = "model"
)

func ParseSessionCommand(raw string) (SessionCommand, bool) {
	switch SessionCommand(raw) {
	case CommandStop:
		return CommandStop, true
	case CommandCompact:
		return CommandCompact, true
	case CommandModel:
		return CommandModel, true
	default:
		return "", false
	}
}
```

- [ ] **Step 4: Widen `runtimeController` and add the errors**

In `backend/internal/session_manager/manager.go`, add one method to the interface at line 200:

```go
type runtimeController interface {
	Create(ctx context.Context, cfg ports.RuntimeConfig) (ports.RuntimeHandle, error)
	Destroy(ctx context.Context, handle ports.RuntimeHandle) error
	GetOutput(ctx context.Context, handle ports.RuntimeHandle, lines int) (string, error)
	// SendInput writes raw bytes with no Enter appended — the only path for the
	// control keys a command or dialog answer consists of, since the send path
	// runs SanitizeControlChars and would strip them.
	SendInput(ctx context.Context, handle ports.RuntimeHandle, input string) error
	// IsAlive reports whether the handle's runtime session still exists. Used by
	// Reconcile on boot to adopt crash-surviving sessions and reap leaked ones.
	IsAlive(ctx context.Context, handle ports.RuntimeHandle) (bool, error)
}
```

`runtimeselect.Runtime` already has `SendInput`, so production wiring needs no change. Any *other* fake implementing `runtimeController` in existing tests will now fail to compile; add the one-line method to each — that is a mechanical fix, not scope creep.

Add to the error block near line 100:

```go
	// ErrWrongActivityState means a command's precondition did not hold — stop
	// while idle, or compact/model while the agent is working. Nothing is written.
	ErrWrongActivityState = errors.New("session: command not available in this activity state")
	// ErrDialogAbsent means the screen did not show the dialog the action was
	// about to answer. Nothing is written.
	ErrDialogAbsent = errors.New("session: dialog is no longer on screen")
	// ErrModelNotOffered means the harness's model picker did not list the
	// requested label. The picker is backed out of with Esc.
	ErrModelNotOffered = errors.New("session: model not offered by this harness")
```

- [ ] **Step 5: Write `Manager.Command` with only `stop` implemented**

Create `backend/internal/session_manager/command.go`:

```go
package sessionmanager

import (
	"context"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

// keyEscape interrupts the current turn in every TUI harness Operator drives.
// At an idle prompt it is a no-op, which is why a stop that slips through the
// activity check is harmless rather than destructive.
const keyEscape = "\x1b"

// CommandResult reports what the daemon actually did. Wrote is true only when a
// key sequence reached the pty. Models is populated by the model command with
// the rows the picker actually showed, so a client can refresh its seed list.
type CommandResult struct {
	Wrote  bool
	Models []string
}

// Command drives one of the closed set of control verbs into the session's pty.
// Every command checks its precondition BEFORE writing and returns without
// writing when it fails: a refused command must never half-act.
//
// Confirmation of effect is deliberately not this function's job. The client
// already streams block events and activity patches and correlates the
// confirming signal itself; a server-side registry would duplicate that state.
func (m *Manager) Command(ctx context.Context, id domain.SessionID, cmd domain.SessionCommand, model string) (CommandResult, error) {
	rec, ok, err := m.store.GetSession(ctx, id)
	if err != nil {
		return CommandResult{}, fmt.Errorf("command %s: %w", id, err)
	}
	if !ok {
		return CommandResult{}, ErrNotFound
	}
	if rec.IsTerminated {
		return CommandResult{}, ErrTerminated
	}
	if rec.Activity.State == domain.ActivityExited {
		return CommandResult{}, ErrAgentExited
	}
	if rec.Metadata.RuntimeHandleID == "" {
		return CommandResult{}, ErrIncompleteHandle
	}

	switch cmd {
	case domain.CommandStop:
		return m.commandStop(ctx, rec)
	default:
		return CommandResult{}, fmt.Errorf("command %s: %w", id, ErrWrongActivityState)
	}
}

// commandStop is the one action that must NOT wait for idle: interrupting is
// its whole purpose. Esc at an idle prompt does nothing, so refusing while idle
// costs the user nothing and keeps the button's meaning honest.
func (m *Manager) commandStop(ctx context.Context, rec domain.SessionRecord) (CommandResult, error) {
	if rec.Activity.State != domain.ActivityActive {
		return CommandResult{}, ErrWrongActivityState
	}
	if err := m.runtime.SendInput(ctx, runtimeHandle(rec.Metadata), keyEscape); err != nil {
		return CommandResult{}, fmt.Errorf("command stop %s: %w", rec.ID, err)
	}
	return CommandResult{Wrote: true}, nil
}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd backend && go test ./internal/session_manager/ -run TestCommand -v
```

Expected: PASS, three tests.

- [ ] **Step 7: Run the package and build gates**

```bash
cd backend && go build ./... && go test ./internal/session_manager/ && go vet ./internal/session_manager/
```

Expected: all pass. Fix any other fake implementing `runtimeController` that now fails to compile.

- [ ] **Step 8: Commit**

```bash
git add backend/internal/domain/sessioncommand.go backend/internal/session_manager/command.go backend/internal/session_manager/command_test.go backend/internal/session_manager/manager.go
git commit -m "feat(session): add the session command vocabulary and stop"
```

---

## Task 2: `compact`

**Files:**
- Modify: `backend/internal/session_manager/command.go`
- Modify: `backend/internal/session_manager/command_test.go`

**Interfaces:**
- Consumes: `Manager.Command`, `CommandResult`, `ErrWrongActivityState` from Task 1.
- Produces: no new exported names.

- [ ] **Step 1: Write the failing test**

Append to `command_test.go`:

```go
func TestCommandCompactTypesTheSlashCommandWhileIdle(t *testing.T) {
	rt := &fakeCommandRuntime{}
	m := newCommandTestManager(t, rt, domain.ActivityIdle)

	if _, err := m.Command(context.Background(), "s1", domain.CommandCompact, ""); err != nil {
		t.Fatalf("Command: %v", err)
	}
	if len(rt.inputs) != 1 || rt.inputs[0] != "/compact\r" {
		t.Fatalf("expected one /compact write, got %q", rt.inputs)
	}
}

func TestCommandCompactRefusedWhileActive(t *testing.T) {
	rt := &fakeCommandRuntime{}
	m := newCommandTestManager(t, rt, domain.ActivityActive)

	_, err := m.Command(context.Background(), "s1", domain.CommandCompact, "")
	if !errors.Is(err, ErrWrongActivityState) {
		t.Fatalf("expected ErrWrongActivityState, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("a refused command must write nothing, got %q", rt.inputs)
	}
}

func TestCommandCompactRefusedWhileBlocked(t *testing.T) {
	rt := &fakeCommandRuntime{}
	m := newCommandTestManager(t, rt, domain.ActivityBlocked)

	_, err := m.Command(context.Background(), "s1", domain.CommandCompact, "")
	if !errors.Is(err, ErrAwaitingDecision) {
		t.Fatalf("expected ErrAwaitingDecision, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("a refused command must write nothing, got %q", rt.inputs)
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd backend && go test ./internal/session_manager/ -run TestCommandCompact -v
```

Expected: FAIL — the `default` branch returns `ErrWrongActivityState` for every compact, so the write assertions fail.

- [ ] **Step 3: Implement compact**

In `command.go`, add the case to the switch in `Command`:

```go
	case domain.CommandCompact:
		return m.commandTyped(ctx, rec, "/compact")
```

And the function:

```go
// commandTyped writes a slash command and its Enter as one raw sequence. It is
// gated on idle for the same reason send is: a paste mid-render can be
// swallowed, and a blocked session must not have a dialog answered by a
// stray line of text.
func (m *Manager) commandTyped(ctx context.Context, rec domain.SessionRecord, text string) (CommandResult, error) {
	if rec.Activity.State == domain.ActivityBlocked {
		return CommandResult{}, ErrAwaitingDecision
	}
	if rec.Activity.State != domain.ActivityIdle {
		return CommandResult{}, ErrWrongActivityState
	}
	if err := m.runtime.SendInput(ctx, runtimeHandle(rec.Metadata), text+"\r"); err != nil {
		return CommandResult{}, fmt.Errorf("command %s %s: %w", text, rec.ID, err)
	}
	return CommandResult{Wrote: true}, nil
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd backend && go test ./internal/session_manager/ -run TestCommand -v
```

Expected: PASS, six tests.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/session_manager/command.go backend/internal/session_manager/command_test.go
git commit -m "feat(session): add the compact command"
```

---

## Task 3: `POST /sessions/{id}/command`

Exposes Tasks 1 and 2 over HTTP. `model` returns `409` until Task 7 lands, so the route ships honest rather than half-wired.

**Files:**
- Modify: `backend/internal/httpd/controllers/sessions.go` (route table near `:197`, new handler)
- Modify: `backend/internal/httpd/controllers/dto.go`
- Modify: `backend/internal/httpd/apispec/specgen/build.go` (beside the `/send` entry at `:1700`)
- Create: `backend/internal/httpd/controllers/sessions_command_test.go`

**Interfaces:**
- Consumes: `Manager.Command`, `CommandResult`, `ErrWrongActivityState`, `ErrAwaitingDecision`, `ErrModelNotOffered`, `ErrDialogAbsent`.
- Produces: `controllers.SessionCommandRequest{Command string; Model string}`, `controllers.SessionCommandResponse{State string; Models []string}`. `State` is `"sent"` on success — never `"confirmed"`, which only the client can determine.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/httpd/controllers/sessions_command_test.go`. Follow the construction used by the existing `sessions_activity_test.go` in this package for building the controller and issuing a request; assert on status, `code`, and the service call:

```go
func TestSessionCommandSentOnSuccess(t *testing.T) {
	svc := &fakeSessionService{commandResult: sessionmanager.CommandResult{Wrote: true}}
	rr := postJSON(t, svc, "/api/v1/sessions/s1/command", `{"command":"stop"}`)

	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rr.Code, rr.Body.String())
	}
	var got SessionCommandResponse
	decodeJSON(t, rr, &got)
	if got.State != "sent" {
		t.Fatalf("state = %q, want sent", got.State)
	}
	if svc.commandCalls != 1 {
		t.Fatalf("service called %d times, want 1", svc.commandCalls)
	}
}

func TestSessionCommandRejectsUnknownVerb(t *testing.T) {
	svc := &fakeSessionService{}
	rr := postJSON(t, svc, "/api/v1/sessions/s1/command", `{"command":"reboot"}`)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rr.Code)
	}
	assertErrorCode(t, rr, "SESSION_COMMAND_UNKNOWN")
	if svc.commandCalls != 0 {
		t.Fatal("an unknown verb must not reach the service")
	}
}

func TestSessionCommandWrongStateIsConflict(t *testing.T) {
	svc := &fakeSessionService{commandErr: sessionmanager.ErrWrongActivityState}
	rr := postJSON(t, svc, "/api/v1/sessions/s1/command", `{"command":"stop"}`)

	if rr.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409", rr.Code)
	}
	assertErrorCode(t, rr, "SESSION_COMMAND_UNAVAILABLE")
}

func TestSessionCommandBlockedIsAwaitingDecision(t *testing.T) {
	svc := &fakeSessionService{commandErr: sessionmanager.ErrAwaitingDecision}
	rr := postJSON(t, svc, "/api/v1/sessions/s1/command", `{"command":"compact"}`)

	if rr.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409", rr.Code)
	}
	assertErrorCode(t, rr, "SESSION_AWAITING_DECISION")
}

func TestSessionCommandModelRequiresALabel(t *testing.T) {
	svc := &fakeSessionService{}
	rr := postJSON(t, svc, "/api/v1/sessions/s1/command", `{"command":"model"}`)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rr.Code)
	}
	assertErrorCode(t, rr, "SESSION_COMMAND_MODEL_REQUIRED")
	if svc.commandCalls != 0 {
		t.Fatal("a model command with no label must not reach the service")
	}
}
```

Write `postJSON`, `decodeJSON`, `assertErrorCode` and the `fakeSessionService` fields in this file if the package has no equivalents; reuse the package's existing helpers where they exist.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd backend && go test ./internal/httpd/controllers/ -run TestSessionCommand -v
```

Expected: FAIL to compile — `SessionCommandResponse` undefined.

- [ ] **Step 3: Add the DTOs**

In `dto.go`:

```go
// SessionCommandRequest drives one control verb into a session's pty. Model is
// required for, and only meaningful to, the "model" command.
type SessionCommandRequest struct {
	Command string `json:"command"`
	Model   string `json:"model,omitempty"`
}

// SessionCommandResponse reports that the write landed. State is always "sent":
// whether the command took effect is confirmed by the caller from the block and
// activity streams it already receives, never asserted here. Models carries the
// rows the harness's picker actually showed, so a client can refresh its seed.
type SessionCommandResponse struct {
	State  string   `json:"state"`
	Models []string `json:"models,omitempty"`
}
```

- [ ] **Step 4: Add the route and handler**

In `sessions.go`, beside the `/send` route at line 197:

```go
	r.Post("/sessions/{sessionId}/command", c.command)
```

And the handler:

```go
func (c *SessionsController) command(w http.ResponseWriter, r *http.Request) {
	id := domain.SessionID(chi.URLParam(r, "sessionId"))
	var req SessionCommandRequest
	if !decodeBounded(w, r, &req, maxSendBodyBytes) {
		return
	}
	cmd, ok := domain.ParseSessionCommand(req.Command)
	if !ok {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "validation", "SESSION_COMMAND_UNKNOWN",
			"unknown command; expected one of stop, compact, model", nil)
		return
	}
	if cmd == domain.CommandModel && strings.TrimSpace(req.Model) == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "validation", "SESSION_COMMAND_MODEL_REQUIRED",
			"the model command requires a model label", nil)
		return
	}

	res, err := c.sessions.Command(r.Context(), id, cmd, req.Model)
	switch {
	case err == nil:
		envelope.WriteJSON(w, http.StatusOK, SessionCommandResponse{State: "sent", Models: res.Models})
	case errors.Is(err, sessionmanager.ErrNotFound):
		envelope.WriteAPIError(w, r, http.StatusNotFound, "not_found", "SESSION_NOT_FOUND", "session not found", nil)
	case errors.Is(err, sessionmanager.ErrAwaitingDecision):
		envelope.WriteAPIError(w, r, http.StatusConflict, "conflict", "SESSION_AWAITING_DECISION",
			"the session is paused on a permission decision", nil)
	case errors.Is(err, sessionmanager.ErrWrongActivityState):
		envelope.WriteAPIError(w, r, http.StatusConflict, "conflict", "SESSION_COMMAND_UNAVAILABLE",
			"the command is not available in the session's current state", nil)
	case errors.Is(err, sessionmanager.ErrModelNotOffered):
		envelope.WriteAPIError(w, r, http.StatusConflict, "conflict", "SESSION_MODEL_NOT_OFFERED",
			"the harness did not offer that model", nil)
	case errors.Is(err, sessionmanager.ErrDialogAbsent):
		envelope.WriteAPIError(w, r, http.StatusConflict, "conflict", "SESSION_DIALOG_ABSENT",
			"the expected dialog is no longer on screen", nil)
	case errors.Is(err, sessionmanager.ErrTerminated), errors.Is(err, sessionmanager.ErrAgentExited):
		envelope.WriteAPIError(w, r, http.StatusConflict, "conflict", "SESSION_NOT_RUNNING", "the session is not running", nil)
	default:
		c.internal(w, r, "command", err)
	}
}
```

Match the package's existing helpers — if `decodeBounded` and `c.internal` do not exist under those names, use whatever the `send` handler uses, verbatim.

Add `Command` to the session-service interface this controller depends on (the same interface that declares `Send`).

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd backend && go test ./internal/httpd/controllers/ -run TestSessionCommand -v
```

Expected: PASS, five tests.

- [ ] **Step 6: Add the spec entry and regenerate**

In `specgen/build.go`, beside the `/send` entry:

```go
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/command", id: "sendSessionCommand", tag: "sessions",
			summary:    "Drive a control command into a session's terminal",
			pathParams: []any{controllers.SessionIDParam{}},
			reqBody:    controllers.SessionCommandRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionCommandResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				// Conflict: wrong activity state, a pending permission decision,
				// an absent dialog, or a model the harness does not offer.
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
```

```bash
npm run api && git status --porcelain
```

Expected: `openapi.yaml` and `frontend/src/api/schema.ts` change; nothing else is dirty after staging them.

- [ ] **Step 7: Run the full gate**

```bash
npm run lint
```

Expected: 0 issues.

- [ ] **Step 8: Commit**

```bash
git add backend/internal/httpd/ frontend/src/api/schema.ts
git commit -m "feat(api): add POST /sessions/{id}/command for stop and compact"
```

---

## Task 4: Per-harness screen readers — the permission dialog

The daemon must never type into a screen it has not just looked at. This task adds the "looking" half: pure functions over pane text, in each harness's own adapter package beside its existing `DetectTerminalActivity`, which is the established pattern for exactly this ([`codex/terminal_activity.go`](../../../backend/internal/adapters/agent/codex/terminal_activity.go)).

**Before writing code, capture the fixtures.** These functions are worth nothing if they are written against imagined screens.

**Files:**
- Create: `backend/testdata/panes/claudecode_permission.txt`, `claudecode_idle.txt`, `codex_permission.txt`, `codex_idle.txt`
- Create: `backend/internal/adapters/agent/claudecode/dialog.go`, `dialog_test.go`
- Create: `backend/internal/adapters/agent/codex/dialog.go`, `dialog_test.go`
- Modify: `backend/internal/ports/agent.go` (new optional capability interface)

**Interfaces:**
- Produces: `ports.TerminalDialogReader` with `ReadPermissionDialog(pane string) (ports.PermissionDialog, bool)` and `PermissionKey(behavior string) (string, bool)`; `ports.PermissionDialog{ToolName string; Lines []string}`. Both `claudecode.Plugin` and `codex.Plugin` implement it.
- Consumes: nothing.

- [ ] **Step 1: Capture real fixtures**

Spawn a real session of each harness and trigger a permission dialog (a `Bash` call for Claude Code; a shell command for Codex). With the daemon running, dump the pane:

```bash
opr pane-capture <session-id> --lines 40
```

If `opr pane-capture` does not accept those flags, read `backend/internal/cli/pane_capture.go` and use what it does expose. Save each dump under `backend/testdata/panes/`, then **replace the content** — file paths, command text, repo names — with neutral placeholders, keeping the box drawing, prompts, key hints, and line structure byte-for-byte. The structure is what the readers match on; the content is not.

Capture an idle pane for each harness the same way. These are the negative cases and they matter as much.

- [ ] **Step 2: Write the failing test**

Create `backend/internal/adapters/agent/claudecode/dialog_test.go`:

```go
package claudecode

import (
	"os"
	"path/filepath"
	"testing"
)

func readPane(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "testdata", "panes", name))
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	return string(b)
}

func TestReadPermissionDialogRecognisesTheRealDialog(t *testing.T) {
	p := &Plugin{}
	dlg, ok := p.ReadPermissionDialog(readPane(t, "claudecode_permission.txt"))
	if !ok {
		t.Fatal("expected the permission dialog to be recognised")
	}
	if dlg.ToolName == "" {
		t.Fatal("expected the dialog to name the blocking tool")
	}
	if len(dlg.Lines) == 0 {
		t.Fatal("expected the dialog's option lines")
	}
}

func TestReadPermissionDialogRejectsAnIdlePane(t *testing.T) {
	p := &Plugin{}
	if _, ok := p.ReadPermissionDialog(readPane(t, "claudecode_idle.txt")); ok {
		t.Fatal("an idle pane must not be read as a permission dialog")
	}
}

func TestReadPermissionDialogRejectsEmptyAndGarbage(t *testing.T) {
	p := &Plugin{}
	for _, pane := range []string{"", "\n\n\n", "some unrelated output\nmore output"} {
		if _, ok := p.ReadPermissionDialog(pane); ok {
			t.Fatalf("expected no dialog for %q", pane)
		}
	}
}

func TestPermissionKeyCoversAllowAndDenyOnly(t *testing.T) {
	p := &Plugin{}
	for _, behavior := range []string{"allow", "deny"} {
		key, ok := p.PermissionKey(behavior)
		if !ok || key == "" {
			t.Fatalf("expected a key for %q", behavior)
		}
	}
	if _, ok := p.PermissionKey("maybe"); ok {
		t.Fatal("expected an unknown behavior to be rejected")
	}
}
```

Write the mirror file for `codex` with the codex fixtures and `package codex`.

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd backend && go test ./internal/adapters/agent/claudecode/ ./internal/adapters/agent/codex/ -run TestReadPermissionDialog -v
```

Expected: FAIL to compile — `p.ReadPermissionDialog undefined`.

- [ ] **Step 4: Add the port**

In `backend/internal/ports/agent.go`, beside `TerminalActivityDetector`:

```go
// PermissionDialog is what a harness's permission prompt says: the tool it is
// blocking on, and the option lines as rendered. Lines is for the client to
// display and for tests to pin; the driver matches on it, never on an index.
type PermissionDialog struct {
	ToolName string
	Lines    []string
}

// TerminalDialogReader is an optional adapter capability for reading a harness's
// own dialogs off the pane. Implementations MUST be pure functions of the pane
// text and MUST fail closed: an unrecognised screen returns false, never a
// guess, because the caller is about to write a keystroke on the strength of it.
type TerminalDialogReader interface {
	ReadPermissionDialog(pane string) (PermissionDialog, bool)
	// PermissionKey maps "allow" or "deny" onto the key that answers this
	// harness's dialog. The keys are chosen so that one landing on an idle
	// prompt instead is harmless.
	PermissionKey(behavior string) (string, bool)
}
```

- [ ] **Step 5: Implement the Claude Code reader**

Create `backend/internal/adapters/agent/claudecode/dialog.go`. Write the matcher against the fixture you captured in Step 1 — the markers below are the *shape* to look for, and the exact strings must come from the real pane, not from this plan:

```go
package claudecode

import "strings"

// ReadPermissionDialog recognises Claude Code's permission prompt and lifts the
// tool it is blocking on. It fails closed: the caller writes a keystroke on the
// strength of this answer, so an ambiguous screen must read as "no dialog".
func (p *Plugin) ReadPermissionDialog(pane string) (ports.PermissionDialog, bool) {
	lines := paneLines(pane)
	start := dialogStart(lines)
	if start < 0 {
		return ports.PermissionDialog{}, false
	}
	options := optionLines(lines[start:])
	if len(options) < 2 {
		return ports.PermissionDialog{}, false
	}
	return ports.PermissionDialog{ToolName: dialogToolName(lines[start:]), Lines: options}, true
}

func (p *Plugin) PermissionKey(behavior string) (string, bool) {
	switch behavior {
	case "allow":
		return claudeAllowKey, true
	case "deny":
		return claudeDenyKey, true
	default:
		return "", false
	}
}
```

`dialogStart`, `optionLines`, `dialogToolName`, `paneLines`, `claudeAllowKey` and `claudeDenyKey` are yours to write from the fixture. Two rules bind them:

- **Strip ANSI before matching.** Copy the escape regexp and line-splitting approach from `codex/terminal_activity.go:9` (`codexTerminalEscape` and `terminalLines`) rather than inventing another; a pane read through `GetOutput` carries SGR sequences.
- **Match only the last screenful.** A dialog scrolled off the top is not on screen. `DetectTerminalActivity` bounds itself to the last 12 lines for the same reason; bound yours the same way.

- [ ] **Step 6: Implement the Codex reader**

Same shape in `backend/internal/adapters/agent/codex/dialog.go`, against the Codex fixture and Codex's own keys. Reuse the package's existing `terminalLines`; do not duplicate it.

- [ ] **Step 7: Assert both plugins satisfy the port**

At the bottom of each `dialog.go`:

```go
var _ ports.TerminalDialogReader = (*Plugin)(nil)
```

- [ ] **Step 8: Run the tests to verify they pass**

```bash
cd backend && go test ./internal/adapters/agent/claudecode/ ./internal/adapters/agent/codex/ -v
```

Expected: PASS, eight new tests, nothing else broken.

- [ ] **Step 9: Commit**

```bash
git add backend/testdata/panes/ backend/internal/adapters/agent/claudecode/dialog.go backend/internal/adapters/agent/claudecode/dialog_test.go backend/internal/adapters/agent/codex/dialog.go backend/internal/adapters/agent/codex/dialog_test.go backend/internal/ports/agent.go
git commit -m "feat(agent): read the permission dialog off the pane per harness"
```

---

## Task 5: Per-harness screen readers — menus

The model picker and the question menu are the same shape: a list of rows, one of them highlighted. One reader serves both.

**Files:**
- Modify: `backend/internal/adapters/agent/claudecode/dialog.go`, `dialog_test.go`
- Modify: `backend/internal/adapters/agent/codex/dialog.go`, `dialog_test.go`
- Modify: `backend/internal/ports/agent.go`
- Create: `backend/testdata/panes/claudecode_model_picker.txt`, `claudecode_question.txt`, `codex_model_picker.txt`

**Interfaces:**
- Consumes: `ports.TerminalDialogReader` from Task 4.
- Produces: `ports.TerminalMenuReader` with `ReadMenu(pane string) (ports.Menu, bool)` and `MenuKeys() ports.MenuKeys`; `ports.Menu{Rows []string; Selected int}`; `ports.MenuKeys{Up, Down, Select, Cancel, Multi string}`.

- [ ] **Step 1: Capture the fixtures**

Open `/model` in a real session of each harness and dump the pane the same way as Task 4. Trigger an `AskUserQuestion` in Claude Code and dump that too. Replace content, keep structure. **Capture two model-picker panes per harness with a different row highlighted** — the reader's whole job is telling them apart, so one fixture cannot test it.

- [ ] **Step 2: Write the failing test**

Append to `claudecode/dialog_test.go`:

```go
func TestReadMenuFindsRowsAndTheHighlight(t *testing.T) {
	p := &Plugin{}
	menu, ok := p.ReadMenu(readPane(t, "claudecode_model_picker.txt"))
	if !ok {
		t.Fatal("expected the model picker to be recognised")
	}
	if len(menu.Rows) < 2 {
		t.Fatalf("expected several rows, got %v", menu.Rows)
	}
	if menu.Selected < 0 || menu.Selected >= len(menu.Rows) {
		t.Fatalf("Selected = %d, out of range for %d rows", menu.Selected, len(menu.Rows))
	}
}

func TestReadMenuTracksADifferentHighlight(t *testing.T) {
	p := &Plugin{}
	first, _ := p.ReadMenu(readPane(t, "claudecode_model_picker.txt"))
	second, ok := p.ReadMenu(readPane(t, "claudecode_model_picker_row2.txt"))
	if !ok {
		t.Fatal("expected the second picker pane to be recognised")
	}
	if first.Selected == second.Selected {
		t.Fatal("the two fixtures must differ in which row is highlighted, or the reader is not reading the highlight")
	}
}

func TestReadMenuRejectsAnIdlePane(t *testing.T) {
	p := &Plugin{}
	if _, ok := p.ReadMenu(readPane(t, "claudecode_idle.txt")); ok {
		t.Fatal("an idle pane must not be read as a menu")
	}
}

func TestMenuKeysAreNonEmpty(t *testing.T) {
	keys := (&Plugin{}).MenuKeys()
	if keys.Up == "" || keys.Down == "" || keys.Select == "" || keys.Cancel == "" {
		t.Fatalf("every navigation key must be set: %+v", keys)
	}
}
```

Mirror for `codex` (Codex has no question menu; its model picker is enough).

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd backend && go test ./internal/adapters/agent/claudecode/ -run TestReadMenu -v
```

Expected: FAIL to compile — `p.ReadMenu undefined`.

- [ ] **Step 4: Add the port**

In `ports/agent.go`:

```go
// Menu is a harness's list dialog — a model picker or a question's options —
// as rendered. Selected is the index into Rows the harness is highlighting.
type Menu struct {
	Rows     []string
	Selected int
}

// MenuKeys are the keystrokes that navigate a harness's list dialog. Multi is
// the key that toggles a row in a multi-select list and is empty for harnesses
// with no such list.
type MenuKeys struct {
	Up     string
	Down   string
	Select string
	Cancel string
	Multi  string
}

// TerminalMenuReader is an optional adapter capability for reading a harness's
// list dialogs. Like TerminalDialogReader it MUST be pure and MUST fail closed:
// the driver navigates by comparing successive reads, so a wrong Selected moves
// the highlight to the wrong row and then presses Enter on it.
type TerminalMenuReader interface {
	ReadMenu(pane string) (Menu, bool)
	MenuKeys() MenuKeys
}
```

- [ ] **Step 5: Implement both readers**

Write `ReadMenu` and `MenuKeys` in each `dialog.go` against the fixtures. The highlight marker (a `❯`, a reverse-video SGR run, a coloured row) is harness-specific — read it off your fixture. If the highlight is carried *only* by SGR and not by a glyph, use the runtime's `GetStyledOutput` instead of `GetOutput` for menus and say so in a comment; `ports.StyledTerminalOutputReader` exists for exactly this ([`outbound.go:93`](../../../backend/internal/ports/outbound.go)) and the driver in Task 6 takes the pane as a string either way.

Add the assertions:

```go
var _ ports.TerminalMenuReader = (*Plugin)(nil)
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd backend && go test ./internal/adapters/agent/claudecode/ ./internal/adapters/agent/codex/ -v
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/testdata/panes/ backend/internal/adapters/agent/ backend/internal/ports/agent.go
git commit -m "feat(agent): read list dialogs and their highlighted row per harness"
```

---

## Task 6: The dialog driver

One place that owns the rule: **capture, verify, write, capture, verify it moved.** Harness-agnostic; it takes readers and keys as arguments.

**Files:**
- Create: `backend/internal/service/dialogdriver/driver.go`, `driver_test.go`

**Interfaces:**
- Consumes: `ports.Menu`, `ports.MenuKeys`.
- Produces: `dialogdriver.Screen` interface `{Read(ctx) (string, error); Write(ctx, keys string) error}`; `dialogdriver.Driver` with `New(screen Screen, settle time.Duration) *Driver`; `(*Driver).AnswerDialog(ctx, present func(string) bool, key string) error`; `(*Driver).NavigateTo(ctx, read func(string) (ports.Menu, bool), keys ports.MenuKeys, target int) error`; errors `ErrNotOnScreen`, `ErrUnconfirmed`, `ErrStuck`.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/service/dialogdriver/driver_test.go`:

```go
package dialogdriver

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

// scriptedScreen returns the next scripted pane on each Read and records every
// Write. A pane that repeats models a screen that did not move.
type scriptedScreen struct {
	panes  []string
	at     int
	writes []string
}

func (s *scriptedScreen) Read(context.Context) (string, error) {
	if s.at >= len(s.panes) {
		return s.panes[len(s.panes)-1], nil
	}
	pane := s.panes[s.at]
	s.at++
	return pane, nil
}

func (s *scriptedScreen) Write(_ context.Context, keys string) error {
	s.writes = append(s.writes, keys)
	return nil
}

func TestAnswerDialogWritesOnceWhenThePromptIsPresentAndTheScreenMoves(t *testing.T) {
	screen := &scriptedScreen{panes: []string{"DIALOG", "done"}}
	d := New(screen, 0)

	err := d.AnswerDialog(context.Background(), func(p string) bool { return p == "DIALOG" }, "y")
	if err != nil {
		t.Fatalf("AnswerDialog: %v", err)
	}
	if len(screen.writes) != 1 || screen.writes[0] != "y" {
		t.Fatalf("expected exactly one write of y, got %q", screen.writes)
	}
}

func TestAnswerDialogRefusesAndWritesNothingWhenAbsent(t *testing.T) {
	screen := &scriptedScreen{panes: []string{"idle prompt"}}
	d := New(screen, 0)

	err := d.AnswerDialog(context.Background(), func(p string) bool { return p == "DIALOG" }, "y")
	if !errors.Is(err, ErrNotOnScreen) {
		t.Fatalf("expected ErrNotOnScreen, got %v", err)
	}
	if len(screen.writes) != 0 {
		t.Fatalf("a refused answer must write nothing, got %q", screen.writes)
	}
}

func TestAnswerDialogReportsUnconfirmedWhenTheScreenDoesNotMove(t *testing.T) {
	screen := &scriptedScreen{panes: []string{"DIALOG", "DIALOG"}}
	d := New(screen, 0)

	err := d.AnswerDialog(context.Background(), func(p string) bool { return p == "DIALOG" }, "y")
	if !errors.Is(err, ErrUnconfirmed) {
		t.Fatalf("expected ErrUnconfirmed, got %v", err)
	}
	if len(screen.writes) != 1 {
		t.Fatalf("an unconfirmed answer must not retry, got %d writes", len(screen.writes))
	}
}

func TestNavigateToWalksToTheVerifiedRow(t *testing.T) {
	// Selected moves 0 -> 1 -> 2 as the driver presses Down.
	screen := &scriptedScreen{panes: []string{"row0", "row1", "row2"}}
	read := func(p string) (ports.Menu, bool) {
		switch p {
		case "row0":
			return ports.Menu{Rows: []string{"a", "b", "c"}, Selected: 0}, true
		case "row1":
			return ports.Menu{Rows: []string{"a", "b", "c"}, Selected: 1}, true
		case "row2":
			return ports.Menu{Rows: []string{"a", "b", "c"}, Selected: 2}, true
		}
		return ports.Menu{}, false
	}
	keys := ports.MenuKeys{Up: "\x1b[A", Down: "\x1b[B", Select: "\r", Cancel: "\x1b"}
	d := New(screen, 0)

	if err := d.NavigateTo(context.Background(), read, keys, 2); err != nil {
		t.Fatalf("NavigateTo: %v", err)
	}
	for _, w := range screen.writes {
		if w != keys.Down {
			t.Fatalf("expected only Down presses, got %q", screen.writes)
		}
	}
	if len(screen.writes) != 2 {
		t.Fatalf("expected 2 Down presses, got %d", len(screen.writes))
	}
}

func TestNavigateToGivesUpWhenTheHighlightStopsMoving(t *testing.T) {
	screen := &scriptedScreen{panes: []string{"stuck"}}
	read := func(string) (ports.Menu, bool) {
		return ports.Menu{Rows: []string{"a", "b", "c"}, Selected: 0}, true
	}
	keys := ports.MenuKeys{Up: "\x1b[A", Down: "\x1b[B", Select: "\r", Cancel: "\x1b"}
	d := New(screen, 0)

	err := d.NavigateTo(context.Background(), read, keys, 2)
	if !errors.Is(err, ErrStuck) {
		t.Fatalf("expected ErrStuck, got %v", err)
	}
	if len(screen.writes) > maxMenuSteps {
		t.Fatalf("the driver must bound its presses, got %d", len(screen.writes))
	}
}

func TestNavigateToIsANoOpWhenAlreadyOnTheTargetRow(t *testing.T) {
	screen := &scriptedScreen{panes: []string{"row1"}}
	read := func(string) (ports.Menu, bool) {
		return ports.Menu{Rows: []string{"a", "b", "c"}, Selected: 1}, true
	}
	d := New(screen, 0)

	if err := d.NavigateTo(context.Background(), read, ports.MenuKeys{Down: "\x1b[B", Up: "\x1b[A"}, 1); err != nil {
		t.Fatalf("NavigateTo: %v", err)
	}
	if len(screen.writes) != 0 {
		t.Fatalf("expected no presses, got %q", screen.writes)
	}
}

func TestNavigateToRefusesWhenTheMenuIsGone(t *testing.T) {
	screen := &scriptedScreen{panes: []string{"idle"}}
	read := func(string) (ports.Menu, bool) { return ports.Menu{}, false }
	d := New(screen, 0)

	err := d.NavigateTo(context.Background(), read, ports.MenuKeys{Down: "\x1b[B"}, 1)
	if !errors.Is(err, ErrNotOnScreen) {
		t.Fatalf("expected ErrNotOnScreen, got %v", err)
	}
	if len(screen.writes) != 0 {
		t.Fatalf("expected no presses, got %q", screen.writes)
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd backend && go test ./internal/service/dialogdriver/ -v
```

Expected: FAIL — the package does not exist.

- [ ] **Step 3: Implement the driver**

Create `backend/internal/service/dialogdriver/driver.go`:

```go
package dialogdriver

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var (
	// ErrNotOnScreen means the expected dialog was not there when we looked.
	// Nothing was written; the caller reports the dialog as gone.
	ErrNotOnScreen = errors.New("dialogdriver: expected dialog is not on screen")
	// ErrUnconfirmed means the key was written but the screen did not change.
	// The caller must NOT retry: the write may have landed and simply not
	// redrawn, and a second key would answer a second dialog.
	ErrUnconfirmed = errors.New("dialogdriver: screen did not change after the write")
	// ErrStuck means the highlight stopped responding to navigation before it
	// reached the target row.
	ErrStuck = errors.New("dialogdriver: menu highlight stopped moving")
)

// maxMenuSteps bounds navigation so a misread highlight cannot hold the pty
// down on an arrow key. A menu deeper than this is not one we can drive.
const maxMenuSteps = 64

// Screen is the pane the driver reads and writes. The session manager supplies
// one backed by runtime.GetOutput and runtime.SendInput.
type Screen interface {
	Read(ctx context.Context) (string, error)
	Write(ctx context.Context, keys string) error
}

// Driver turns best-effort keystroke injection into something checkable: it
// never writes into a screen it has not just read, and it never reports success
// it has not just observed.
type Driver struct {
	screen Screen
	settle time.Duration
}

// New builds a driver. settle is how long to wait after a write before reading
// back, so a redraw is not mistaken for a screen that did not move; tests pass 0.
func New(screen Screen, settle time.Duration) *Driver {
	return &Driver{screen: screen, settle: settle}
}

// AnswerDialog writes one key into a dialog, but only after confirming the
// dialog is on screen, and reports whether the screen moved afterwards.
func (d *Driver) AnswerDialog(ctx context.Context, present func(pane string) bool, key string) error {
	before, err := d.screen.Read(ctx)
	if err != nil {
		return fmt.Errorf("dialogdriver: read before write: %w", err)
	}
	if !present(before) {
		return ErrNotOnScreen
	}
	if err := d.screen.Write(ctx, key); err != nil {
		return fmt.Errorf("dialogdriver: write: %w", err)
	}
	d.wait(ctx)
	after, err := d.screen.Read(ctx)
	if err != nil {
		return fmt.Errorf("dialogdriver: read after write: %w", err)
	}
	if after == before {
		return ErrUnconfirmed
	}
	return nil
}

// NavigateTo moves a menu's highlight onto target and stops. It does not press
// Select — the caller does that, so a caller can inspect the verified row first.
//
// Each step is verified against a fresh read rather than counted: counting
// presses assumes the menu did not wrap, scroll, or swallow a key, and all
// three happen.
func (d *Driver) NavigateTo(ctx context.Context, read func(pane string) (ports.Menu, bool), keys ports.MenuKeys, target int) error {
	for step := 0; step <= maxMenuSteps; step++ {
		pane, err := d.screen.Read(ctx)
		if err != nil {
			return fmt.Errorf("dialogdriver: read menu: %w", err)
		}
		menu, ok := read(pane)
		if !ok {
			return ErrNotOnScreen
		}
		if target < 0 || target >= len(menu.Rows) {
			return fmt.Errorf("dialogdriver: target row %d out of range for %d rows", target, len(menu.Rows))
		}
		if menu.Selected == target {
			return nil
		}
		key := keys.Down
		if menu.Selected > target {
			key = keys.Up
		}
		if err := d.screen.Write(ctx, key); err != nil {
			return fmt.Errorf("dialogdriver: navigate: %w", err)
		}
		d.wait(ctx)
	}
	return ErrStuck
}

// Press writes a key with no verification. It is only for keys whose effect the
// caller verifies itself on the next read — Select after a verified NavigateTo,
// or Cancel when backing out of a menu we are abandoning anyway.
func (d *Driver) Press(ctx context.Context, key string) error {
	if err := d.screen.Write(ctx, key); err != nil {
		return fmt.Errorf("dialogdriver: press: %w", err)
	}
	d.wait(ctx)
	return nil
}

func (d *Driver) wait(ctx context.Context) {
	if d.settle <= 0 {
		return
	}
	t := time.NewTimer(d.settle)
	defer t.Stop()
	select {
	case <-ctx.Done():
	case <-t.C:
	}
}
```

The `ErrStuck` test asserts the write count is bounded; with `maxMenuSteps` at 64 and a highlight that never moves, the loop writes 65 times before returning. Adjust the test's bound to `maxMenuSteps+1` if that is what you observe — the assertion that matters is *bounded*, not the exact number.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd backend && go test ./internal/service/dialogdriver/ -v
```

Expected: PASS, seven tests.

- [ ] **Step 5: Run with the race detector**

```bash
cd backend && go test -race ./internal/service/dialogdriver/
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/service/dialogdriver/
git commit -m "feat(dialogdriver): verify the screen before and after every keystroke"
```

---

## Task 7: The `model` command

**Files:**
- Modify: `backend/internal/session_manager/command.go`, `command_test.go`
- Modify: `backend/internal/session_manager/manager.go` (hold a driver factory)

**Interfaces:**
- Consumes: `Manager.Command`/`commandTyped` (Tasks 1-2), `ports.TerminalMenuReader` (Task 5), `dialogdriver.Driver` (Task 6).
- Produces: `CommandResult.Models` populated.

- [ ] **Step 1: Write the failing test**

Append to `command_test.go`. Extend `fakeCommandRuntime` so `GetOutput` returns successive panes, mirroring `scriptedScreen`:

```go
func TestCommandModelDrivesThePickerToTheMatchingRow(t *testing.T) {
	rt := &fakeCommandRuntime{panes: []string{
		"MENU:0", // after /model is typed
		"MENU:0", // NavigateTo's first read
		"MENU:1", // after one Down
	}}
	m := newCommandTestManager(t, rt, domain.ActivityIdle)
	m.menuReader = fakeMenuReader{rows: []string{"sonnet", "opus"}}

	res, err := m.Command(context.Background(), "s1", domain.CommandModel, "opus")
	if err != nil {
		t.Fatalf("Command: %v", err)
	}
	if got, want := res.Models, []string{"sonnet", "opus"}; !slices.Equal(got, want) {
		t.Fatalf("Models = %v, want %v", got, want)
	}
	if rt.inputs[0] != "/model\r" {
		t.Fatalf("expected /model to be typed first, got %q", rt.inputs)
	}
	if rt.inputs[len(rt.inputs)-1] != "\r" {
		t.Fatalf("expected Enter last, got %q", rt.inputs)
	}
}

func TestCommandModelBacksOutWhenTheLabelIsNotOffered(t *testing.T) {
	rt := &fakeCommandRuntime{panes: []string{"MENU:0"}}
	m := newCommandTestManager(t, rt, domain.ActivityIdle)
	m.menuReader = fakeMenuReader{rows: []string{"sonnet", "opus"}}

	_, err := m.Command(context.Background(), "s1", domain.CommandModel, "gpt-5")
	if !errors.Is(err, ErrModelNotOffered) {
		t.Fatalf("expected ErrModelNotOffered, got %v", err)
	}
	if last := rt.inputs[len(rt.inputs)-1]; last != "\x1b" {
		t.Fatalf("expected Esc to back out of the picker, got %q", rt.inputs)
	}
	for _, in := range rt.inputs {
		if in == "\r" {
			t.Fatal("a failed model command must never press Enter")
		}
	}
}

func TestCommandModelBacksOutWhenNoMenuAppears(t *testing.T) {
	rt := &fakeCommandRuntime{panes: []string{"idle prompt"}}
	m := newCommandTestManager(t, rt, domain.ActivityIdle)
	m.menuReader = fakeMenuReader{noMenu: true}

	_, err := m.Command(context.Background(), "s1", domain.CommandModel, "opus")
	if !errors.Is(err, ErrDialogAbsent) {
		t.Fatalf("expected ErrDialogAbsent, got %v", err)
	}
	if last := rt.inputs[len(rt.inputs)-1]; last != "\x1b" {
		t.Fatalf("expected Esc to back out, got %q", rt.inputs)
	}
}

func TestCommandModelRefusedWhileActive(t *testing.T) {
	rt := &fakeCommandRuntime{}
	m := newCommandTestManager(t, rt, domain.ActivityActive)

	_, err := m.Command(context.Background(), "s1", domain.CommandModel, "opus")
	if !errors.Is(err, ErrWrongActivityState) {
		t.Fatalf("expected ErrWrongActivityState, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("a refused command must write nothing, got %q", rt.inputs)
	}
}
```

Write `fakeMenuReader` in the test file: it returns `ports.Menu{Rows: rows, Selected: n}` where `n` is parsed from a `"MENU:<n>"` pane, and `false` when `noMenu` is set.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd backend && go test ./internal/session_manager/ -run TestCommandModel -v
```

Expected: FAIL — `m.menuReader undefined`, and the `default` branch refuses every model command.

- [ ] **Step 3: Implement the model command**

Add to `Command`'s switch:

```go
	case domain.CommandModel:
		return m.commandModel(ctx, rec, model)
```

And in `command.go`:

```go
// commandModel changes the model through the harness's own picker, in ONE call.
// Opening the picker and waiting for a client to choose would park the desktop
// terminal in a menu for as long as the phone takes, so the label is chosen
// before anything is typed and the picker is either driven to it or backed out
// of with Esc. The terminal is never left open.
func (m *Manager) commandModel(ctx context.Context, rec domain.SessionRecord, label string) (CommandResult, error) {
	if rec.Activity.State == domain.ActivityBlocked {
		return CommandResult{}, ErrAwaitingDecision
	}
	if rec.Activity.State != domain.ActivityIdle {
		return CommandResult{}, ErrWrongActivityState
	}
	reader, ok := m.menuReaderFor(rec.Harness)
	if !ok {
		return CommandResult{}, ErrWrongActivityState
	}

	handle := runtimeHandle(rec.Metadata)
	driver := m.driverFor(handle)
	if err := driver.Press(ctx, "/model\r"); err != nil {
		return CommandResult{}, fmt.Errorf("command model %s: %w", rec.ID, err)
	}

	pane, err := m.runtime.GetOutput(ctx, handle, commandPaneLines)
	if err != nil {
		return CommandResult{}, fmt.Errorf("command model %s: read picker: %w", rec.ID, err)
	}
	menu, open := reader.ReadMenu(pane)
	if !open {
		m.escape(ctx, driver, rec.ID)
		return CommandResult{}, ErrDialogAbsent
	}
	target := indexOfRow(menu.Rows, label)
	if target < 0 {
		m.escape(ctx, driver, rec.ID)
		return CommandResult{Models: menu.Rows}, ErrModelNotOffered
	}
	if err := driver.NavigateTo(ctx, reader.ReadMenu, reader.MenuKeys(), target); err != nil {
		m.escape(ctx, driver, rec.ID)
		return CommandResult{Models: menu.Rows}, fmt.Errorf("command model %s: %w", rec.ID, err)
	}
	if err := driver.Press(ctx, reader.MenuKeys().Select); err != nil {
		return CommandResult{Models: menu.Rows}, fmt.Errorf("command model %s: select: %w", rec.ID, err)
	}
	return CommandResult{Wrote: true, Models: menu.Rows}, nil
}

// escape backs out of a picker we are abandoning. Its failure is logged and
// swallowed: the caller is already returning an error, and reporting the Esc's
// failure instead would hide why the command actually failed.
func (m *Manager) escape(ctx context.Context, driver *dialogdriver.Driver, id domain.SessionID) {
	if err := driver.Press(ctx, keyEscape); err != nil {
		m.logger.Warn("command model: failed to back out of the picker", "sessionID", id, "error", err)
	}
}

// indexOfRow matches a picker row by case-insensitive substring: a harness
// renders "opus" inside a longer descriptive row, and the client's seed label
// is the short name the user picked.
func indexOfRow(rows []string, label string) int {
	want := strings.ToLower(strings.TrimSpace(label))
	if want == "" {
		return -1
	}
	for i, row := range rows {
		if strings.Contains(strings.ToLower(row), want) {
			return i
		}
	}
	return -1
}

// commandPaneLines bounds every pane read a command makes. A picker taller than
// this is not one we can drive; the readers bound themselves the same way.
const commandPaneLines = 40
```

Add to `Manager`: a `menuReaderFor(harness string) (ports.TerminalMenuReader, bool)` that type-asserts the agent from `m.agents.Agent(harness)` — mirror how `message_delivery.go:46` type-asserts `ports.TerminalActivityDetector` — and a `driverFor(handle)` that builds a `dialogdriver.Driver` over a `Screen` backed by `m.runtime.GetOutput`/`SendInput`. Give the production driver a real settle (start at 150ms) and let tests inject 0.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd backend && go test ./internal/session_manager/ -run TestCommand -v
```

Expected: PASS, ten tests.

- [ ] **Step 5: Run the full gate**

```bash
npm run lint
```

Expected: 0 issues.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/session_manager/
git commit -m "feat(session): drive the harness model picker in one call"
```

---

## Task 8: The pending-interaction registry

What the phone needs in order to *act* on a dialog is an id it can post back. Per finding 3, that id is **daemon-minted**: the hook does not reliably carry the blocking tool's `tool_use_id`, and the phone answers the dialog on screen, of which there is only ever one.

**Files:**
- Create: `backend/internal/session_manager/interaction.go`, `interaction_test.go`
- Modify: `backend/internal/domain/blockevent.go` (add `InteractionID`)
- Modify: `backend/internal/lifecycle/manager.go` (register on a blocked signal, clear at a turn boundary)
- Modify: `backend/internal/httpd/controllers/sessions.go`, `dto.go`, `specgen/build.go` (`GET .../interactions`)

**Interfaces:**
- Consumes: nothing from Tasks 1-7.
- Produces: `domain.PendingInteraction{ID, Kind, ToolName, ToolInput string; Lines []string; CreatedAt time.Time}` with `Kind` one of `"permission"`, `"question"`; `(*Manager).Interactions(ctx, id) ([]domain.PendingInteraction, error)`; `(*Manager).RegisterInteraction(id domain.SessionID, in domain.PendingInteraction)`; `(*Manager).ClearInteractions(id domain.SessionID)`; `(*Manager).Interaction(id domain.SessionID, interactionID string) (domain.PendingInteraction, bool)`.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/session_manager/interaction_test.go`:

```go
func TestInteractionsAreListedAfterRegistration(t *testing.T) {
	m := newCommandTestManager(t, &fakeCommandRuntime{}, domain.ActivityBlocked)
	m.RegisterInteraction("s1", domain.PendingInteraction{
		ID: "i1", Kind: "permission", ToolName: "Bash", ToolInput: `{"command":"ls"}`,
	})

	got, err := m.Interactions(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Interactions: %v", err)
	}
	if len(got) != 1 || got[0].ID != "i1" {
		t.Fatalf("Interactions = %+v", got)
	}
}

func TestATurnBoundaryClearsPendingInteractions(t *testing.T) {
	m := newCommandTestManager(t, &fakeCommandRuntime{}, domain.ActivityBlocked)
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: "permission"})
	m.ClearInteractions("s1")

	got, _ := m.Interactions(context.Background(), "s1")
	if len(got) != 0 {
		t.Fatalf("expected no interactions after a turn boundary, got %+v", got)
	}
}

func TestRegisteringASecondInteractionReplacesTheFirst(t *testing.T) {
	// Only one dialog is ever on screen. Keeping a stale one would let a client
	// answer a dialog that is no longer there.
	m := newCommandTestManager(t, &fakeCommandRuntime{}, domain.ActivityBlocked)
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: "permission"})
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i2", Kind: "permission"})

	got, _ := m.Interactions(context.Background(), "s1")
	if len(got) != 1 || got[0].ID != "i2" {
		t.Fatalf("expected only the newest interaction, got %+v", got)
	}
}

func TestInteractionLookupMissesAnUnknownID(t *testing.T) {
	m := newCommandTestManager(t, &fakeCommandRuntime{}, domain.ActivityBlocked)
	if _, ok := m.Interaction("s1", "nope"); ok {
		t.Fatal("expected an unknown interaction id to miss")
	}
}

func TestInteractionsOfAnUnknownSessionIsEmptyNotAnError(t *testing.T) {
	m := newCommandTestManager(t, &fakeCommandRuntime{}, domain.ActivityIdle)
	got, err := m.Interactions(context.Background(), "unknown")
	if err != nil {
		t.Fatalf("Interactions: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("expected none, got %+v", got)
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd backend && go test ./internal/session_manager/ -run TestInteraction -v
```

Expected: FAIL to compile — `domain.PendingInteraction` undefined.

- [ ] **Step 3: Add the domain type and the registry**

In `backend/internal/domain/` (a new `interaction.go`, or beside the block-event types):

```go
// PendingInteraction is a dialog the agent is waiting on a human for. Its ID is
// minted by the daemon, not lifted from the harness: Claude Code's permission
// hook carries the blocking tool's NAME but not its tool_use_id, and there is
// only ever one dialog on screen, so no correlation is needed to answer it.
type PendingInteraction struct {
	ID        string
	Kind      string
	ToolName  string
	ToolInput string
	Lines     []string
	CreatedAt time.Time
}

const (
	InteractionPermission = "permission"
	InteractionQuestion   = "question"
)
```

Create `backend/internal/session_manager/interaction.go` holding a `map[domain.SessionID]domain.PendingInteraction` behind a mutex on `Manager`. It is deliberately in-memory: a pending dialog does not survive a daemon restart because the *agent's* dialog does not either — the pty is gone with it. Registering replaces; `ClearInteractions` deletes.

- [ ] **Step 4: Wire the lifecycle**

In `internal/lifecycle/manager.go`, where a signal maps to `domain.ActivityBlocked` (`applyToolPrecedenceLocked`'s `case s.State == domain.ActivityBlocked`), call `RegisterInteraction` with a fresh id, `s.ToolName` and the hook's `ToolInput`. Where the code already does `delete(m.flights, id)` at a turn boundary, also call `ClearInteractions`.

Do this through a narrow interface declared in `lifecycle`, not by importing `session_manager` — check which direction the existing dependency runs before wiring, and follow it.

- [ ] **Step 5: Pin the hook's non-blocking contract**

The spec explicitly **rejects** a hook that blocks until a client resolves the approval: blocking hides the dialog on the desktop terminal for as long as it waits, turning every permission prompt into a hang. The hook Operator installs must therefore keep exiting 0 immediately with nothing on stdout, having only *registered* the interaction.

Nothing in this task changes that — but nothing currently stops a later change from reintroducing it, so pin it. Add to `backend/internal/cli/hooks_test.go`:

```go
func TestPermissionRequestHookExitsImmediatelyWithEmptyStdout(t *testing.T) {
	// The rejected design blocks here until a client answers, which hides the
	// dialog from the desktop terminal for the whole wait. If this test starts
	// failing because the hook now blocks or writes a decision, that design was
	// reintroduced — read the spec's "Rejected: a blocking hook" section.
	var stdout bytes.Buffer
	start := time.Now()

	code := runHook(t, &stdout, "claude-code", "permission-request", `{"tool_name":"Bash","tool_input":{}}`)

	if code != 0 {
		t.Fatalf("exit code = %d, want 0", code)
	}
	if stdout.Len() != 0 {
		t.Fatalf("stdout = %q, want empty — a decision on stdout is the rejected blocking design", stdout.String())
	}
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("hook took %s; it must not wait on a client", elapsed)
	}
}
```

Use whatever the package's existing hook tests use to invoke a sub-command in place of `runHook`.

```bash
cd backend && go test ./internal/cli/ -run TestPermissionRequestHook -v
```

Expected: PASS against the hook as it stands today.

- [ ] **Step 6: Put the id on the block event**

Add `InteractionID string` to `domain.BlockEventRecord` in `internal/domain/blockevent.go`, populate it on the permission block event, and carry it through `blockevent.Service`. Regenerate sqlc if the field is persisted:

```bash
npm run sqlc && git status --porcelain
```

- [ ] **Step 7: Add `GET /sessions/{id}/interactions`**

Route, handler, DTO (`SessionInteractionsResponse{Interactions []SessionInteraction}`), and a `specgen` entry beside the command entry. This exists for **reconnect reconciliation**: a phone that was backgrounded when the dialog appeared has no block event for it.

```bash
npm run api && git status --porcelain
```

- [ ] **Step 8: Run the tests to verify they pass**

```bash
cd backend && go test ./internal/session_manager/ ./internal/lifecycle/ ./internal/httpd/controllers/ -v
```

Expected: PASS.

- [ ] **Step 9: Run the full gate**

```bash
npm run lint
```

Expected: 0 issues.

- [ ] **Step 10: Commit**

```bash
git add backend/ frontend/src/api/schema.ts
git commit -m "feat(session): register the pending dialog a client can answer"
```

---

## Task 9: `POST /sessions/{id}/decision` — approve and deny

**This is the one write the blocked guard admits.** `send` stays refused.

**Files:**
- Create: `backend/internal/session_manager/decision.go`, `decision_test.go`
- Modify: `backend/internal/httpd/controllers/sessions.go`, `dto.go`, `specgen/build.go`
- Create: `backend/internal/httpd/controllers/sessions_decision_test.go`

**Interfaces:**
- Consumes: `dialogdriver.Driver` (Task 6), `ports.TerminalDialogReader` (Task 4), the interaction registry (Task 8).
- Produces: `(*Manager).Decide(ctx, id domain.SessionID, interactionID, behavior string) error`; `controllers.SessionDecisionRequest{RequestID, Behavior string}`; `controllers.SessionDecisionResponse{State string}`.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/session_manager/decision_test.go`:

```go
func TestDecideDrivesExactlyOneKeyWhenTheDialogIsOnScreen(t *testing.T) {
	rt := &fakeCommandRuntime{panes: []string{"DIALOG", "moved on"}}
	m := newCommandTestManager(t, rt, domain.ActivityBlocked)
	m.dialogReader = fakeDialogReader{present: true, allow: "y", deny: "n"}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: domain.InteractionPermission})

	if err := m.Decide(context.Background(), "s1", "i1", "allow"); err != nil {
		t.Fatalf("Decide: %v", err)
	}
	if len(rt.inputs) != 1 || rt.inputs[0] != "y" {
		t.Fatalf("expected exactly one allow key, got %q", rt.inputs)
	}
}

func TestDecideWritesNothingWhenTheDialogIsGone(t *testing.T) {
	rt := &fakeCommandRuntime{panes: []string{"idle prompt"}}
	m := newCommandTestManager(t, rt, domain.ActivityBlocked)
	m.dialogReader = fakeDialogReader{present: false}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: domain.InteractionPermission})

	err := m.Decide(context.Background(), "s1", "i1", "allow")
	if !errors.Is(err, ErrDialogAbsent) {
		t.Fatalf("expected ErrDialogAbsent, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestDecideReportsUnconfirmedWhenTheScreenDoesNotMove(t *testing.T) {
	rt := &fakeCommandRuntime{panes: []string{"DIALOG", "DIALOG"}}
	m := newCommandTestManager(t, rt, domain.ActivityBlocked)
	m.dialogReader = fakeDialogReader{present: true, allow: "y"}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: domain.InteractionPermission})

	err := m.Decide(context.Background(), "s1", "i1", "allow")
	if !errors.Is(err, ErrUnconfirmed) {
		t.Fatalf("expected ErrUnconfirmed, got %v", err)
	}
	if len(rt.inputs) != 1 {
		t.Fatalf("an unconfirmed decision must not retry, got %d writes", len(rt.inputs))
	}
}

func TestDecideRefusesAStaleInteractionID(t *testing.T) {
	// Two clients racing one dialog: the loser is told the dialog is gone
	// rather than answering the next one by accident.
	rt := &fakeCommandRuntime{panes: []string{"DIALOG"}}
	m := newCommandTestManager(t, rt, domain.ActivityBlocked)
	m.dialogReader = fakeDialogReader{present: true, allow: "y"}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i2", Kind: domain.InteractionPermission})

	err := m.Decide(context.Background(), "s1", "i1", "allow")
	if !errors.Is(err, ErrDialogAbsent) {
		t.Fatalf("expected ErrDialogAbsent for a stale id, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestDecideRejectsAnUnknownBehavior(t *testing.T) {
	rt := &fakeCommandRuntime{panes: []string{"DIALOG"}}
	m := newCommandTestManager(t, rt, domain.ActivityBlocked)
	m.dialogReader = fakeDialogReader{present: true, allow: "y", deny: "n"}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: domain.InteractionPermission})

	if err := m.Decide(context.Background(), "s1", "i1", "maybe"); err == nil {
		t.Fatal("expected an unknown behavior to be rejected")
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestDecideDenyDrivesTheDenyKey(t *testing.T) {
	rt := &fakeCommandRuntime{panes: []string{"DIALOG", "moved on"}}
	m := newCommandTestManager(t, rt, domain.ActivityBlocked)
	m.dialogReader = fakeDialogReader{present: true, allow: "y", deny: "n"}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: domain.InteractionPermission})

	if err := m.Decide(context.Background(), "s1", "i1", "deny"); err != nil {
		t.Fatalf("Decide: %v", err)
	}
	if len(rt.inputs) != 1 || rt.inputs[0] != "n" {
		t.Fatalf("expected the deny key, got %q", rt.inputs)
	}
}
```

Write `fakeDialogReader` in the test file, satisfying `ports.TerminalDialogReader`.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd backend && go test ./internal/session_manager/ -run TestDecide -v
```

Expected: FAIL to compile — `m.Decide undefined`.

- [ ] **Step 3: Implement `Decide`**

Create `backend/internal/session_manager/decision.go`:

```go
package sessionmanager

import (
	"context"
	"errors"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/service/dialogdriver"
)

// ErrUnconfirmed means the key was written but the screen did not move. The
// caller must present this to the user as "unconfirmed", never as failure:
// the write may well have landed. Nothing is retried.
var ErrUnconfirmed = errors.New("session: action was written but not confirmed on screen")

// Decide answers a pending permission dialog by driving one key into it.
//
// Because the phone answers the DIALOG rather than the hook, there is no
// deadline: Claude Code's dialog waits indefinitely, so a request is still
// answerable an hour later. The interaction id is checked first so that two
// clients racing one dialog cannot have the loser answer the NEXT dialog.
func (m *Manager) Decide(ctx context.Context, id domain.SessionID, interactionID, behavior string) error {
	rec, ok, err := m.store.GetSession(ctx, id)
	if err != nil {
		return fmt.Errorf("decide %s: %w", id, err)
	}
	if !ok {
		return ErrNotFound
	}
	if rec.IsTerminated {
		return ErrTerminated
	}
	pending, ok := m.Interaction(id, interactionID)
	if !ok || pending.Kind != domain.InteractionPermission {
		return ErrDialogAbsent
	}
	reader, ok := m.dialogReaderFor(rec.Harness)
	if !ok {
		return ErrDialogAbsent
	}
	key, ok := reader.PermissionKey(behavior)
	if !ok {
		return fmt.Errorf("decide %s: unknown behavior %q", id, behavior)
	}

	handle := runtimeHandle(rec.Metadata)
	driver := m.driverFor(handle)
	present := func(pane string) bool {
		_, on := reader.ReadPermissionDialog(pane)
		return on
	}
	switch err := driver.AnswerDialog(ctx, present, key); {
	case err == nil:
		m.ClearInteractions(id)
		return nil
	case errors.Is(err, dialogdriver.ErrNotOnScreen):
		m.ClearInteractions(id)
		return ErrDialogAbsent
	case errors.Is(err, dialogdriver.ErrUnconfirmed):
		return ErrUnconfirmed
	default:
		return fmt.Errorf("decide %s: %w", id, err)
	}
}
```

`dialogReaderFor` mirrors `menuReaderFor` from Task 7.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd backend && go test ./internal/session_manager/ -run TestDecide -v
```

Expected: PASS, six tests.

- [ ] **Step 5: Add the route**

Handler mapping, in `sessions.go`:

| error | status | code |
|---|---|---|
| `nil` | 200 | — (`{"state":"sent"}`) |
| `ErrDialogAbsent` | 409 | `SESSION_DIALOG_ABSENT` |
| `ErrUnconfirmed` | 200 | — (`{"state":"unconfirmed"}`) |
| unknown behavior | 400 | `SESSION_DECISION_INVALID` |
| `ErrNotFound` | 404 | `SESSION_NOT_FOUND` |

`ErrUnconfirmed` is a **200, not an error**: the write happened, and the client must show it as unconfirmed rather than as a failure it might retry.

Write `sessions_decision_test.go` covering each row of that table, add the `specgen` entry, then:

```bash
npm run api && git status --porcelain
```

- [ ] **Step 6: Assert `send` is still refused while blocked**

Add to `sessions_decision_test.go`:

```go
func TestSendRemainsRefusedWhileAnApprovalIsPending(t *testing.T) {
	svc := &fakeSessionService{sendErr: sessionmanager.ErrAwaitingDecision}
	rr := postJSON(t, svc, "/api/v1/sessions/s1/send", `{"message":"hi"}`)

	if rr.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409 — decision is the ONLY write admitted while blocked", rr.Code)
	}
}
```

- [ ] **Step 7: Run the full gate**

```bash
npm run lint
```

Expected: 0 issues.

- [ ] **Step 8: Commit**

```bash
git add backend/ frontend/src/api/schema.ts
git commit -m "feat(api): answer a permission dialog from a client with POST /sessions/{id}/decision"
```

---

## Task 10: `POST /sessions/{id}/answer` — answering a question

Claude Code only. Codex has no `AskUserQuestion` equivalent in the sampled rollouts, so Codex questions stay hook-driven and unanswerable, exactly as the spec says.

**Files:**
- Modify: `backend/internal/session_manager/decision.go`, `decision_test.go`
- Modify: `backend/internal/httpd/controllers/sessions.go`, `dto.go`, `specgen/build.go`

**Interfaces:**
- Consumes: `dialogdriver.NavigateTo`/`Press` (Task 6), `ports.TerminalMenuReader` (Task 5), the interaction registry (Task 8).
- Produces: `(*Manager).Answer(ctx, id domain.SessionID, interactionID string, selections [][]int) error`; `controllers.SessionAnswerRequest{RequestID string; Selections [][]int}`.

- [ ] **Step 1: Write the failing test**

Append to `decision_test.go`:

```go
func TestAnswerNavigatesToTheVerifiedRowBeforeEnter(t *testing.T) {
	rt := &fakeCommandRuntime{panes: []string{"MENU:0", "MENU:1", "moved on"}}
	m := newCommandTestManager(t, rt, domain.ActivityBlocked)
	m.menuReader = fakeMenuReader{rows: []string{"first", "second"}}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", [][]int{{1}}); err != nil {
		t.Fatalf("Answer: %v", err)
	}
	last := rt.inputs[len(rt.inputs)-1]
	if last != "\r" {
		t.Fatalf("expected Enter last, got %q", rt.inputs)
	}
	if len(rt.inputs) < 2 {
		t.Fatalf("expected navigation before Enter, got %q", rt.inputs)
	}
}

func TestAnswerWritesNothingWhenTheMenuIsGone(t *testing.T) {
	rt := &fakeCommandRuntime{panes: []string{"idle"}}
	m := newCommandTestManager(t, rt, domain.ActivityBlocked)
	m.menuReader = fakeMenuReader{noMenu: true}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	err := m.Answer(context.Background(), "s1", "q1", [][]int{{0}})
	if !errors.Is(err, ErrDialogAbsent) {
		t.Fatalf("expected ErrDialogAbsent, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestAnswerRejectsAnOutOfRangeSelection(t *testing.T) {
	rt := &fakeCommandRuntime{panes: []string{"MENU:0"}}
	m := newCommandTestManager(t, rt, domain.ActivityBlocked)
	m.menuReader = fakeMenuReader{rows: []string{"first", "second"}}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", [][]int{{7}}); err == nil {
		t.Fatal("expected an out-of-range selection to be rejected")
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestAnswerRejectsAnEmptySelection(t *testing.T) {
	rt := &fakeCommandRuntime{panes: []string{"MENU:0"}}
	m := newCommandTestManager(t, rt, domain.ActivityBlocked)
	m.menuReader = fakeMenuReader{rows: []string{"first", "second"}}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", nil); err == nil {
		t.Fatal("expected an empty selection to be rejected")
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestAnswerTogglesEveryRowOfAMultiSelectBeforeEnter(t *testing.T) {
	rt := &fakeCommandRuntime{panes: []string{"MENU:0", "MENU:0", "MENU:1", "MENU:1", "moved on"}}
	m := newCommandTestManager(t, rt, domain.ActivityBlocked)
	m.menuReader = fakeMenuReader{rows: []string{"a", "b", "c"}, multi: " "}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", [][]int{{0, 1}}); err != nil {
		t.Fatalf("Answer: %v", err)
	}
	spaces := 0
	for _, in := range rt.inputs {
		if in == " " {
			spaces++
		}
	}
	if spaces != 2 {
		t.Fatalf("expected one toggle per selected row, got %d in %q", spaces, rt.inputs)
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd backend && go test ./internal/session_manager/ -run TestAnswer -v
```

Expected: FAIL to compile — `m.Answer undefined`.

- [ ] **Step 3: Implement `Answer`**

In `decision.go`:

```go
// Answer drives a question's menu. Selections is one []int per question in the
// dialog; a single-element inner slice is a single-select, several are a
// multi-select whose rows are toggled before Enter.
//
// Every hop is verified against a fresh read by the driver rather than counted:
// counting presses assumes the menu did not wrap, scroll or swallow a key.
func (m *Manager) Answer(ctx context.Context, id domain.SessionID, interactionID string, selections [][]int) error {
	if len(selections) == 0 {
		return fmt.Errorf("answer %s: no selections", id)
	}
	rec, ok, err := m.store.GetSession(ctx, id)
	if err != nil {
		return fmt.Errorf("answer %s: %w", id, err)
	}
	if !ok {
		return ErrNotFound
	}
	pending, ok := m.Interaction(id, interactionID)
	if !ok || pending.Kind != domain.InteractionQuestion {
		return ErrDialogAbsent
	}
	reader, ok := m.menuReaderFor(rec.Harness)
	if !ok {
		return ErrDialogAbsent
	}

	handle := runtimeHandle(rec.Metadata)
	driver := m.driverFor(handle)
	keys := reader.MenuKeys()

	// Validate every index against the menu actually on screen BEFORE writing
	// anything: a half-answered question is worse than a refused one.
	pane, err := m.runtime.GetOutput(ctx, handle, commandPaneLines)
	if err != nil {
		return fmt.Errorf("answer %s: read menu: %w", id, err)
	}
	menu, open := reader.ReadMenu(pane)
	if !open {
		return ErrDialogAbsent
	}
	for _, group := range selections {
		if len(group) == 0 {
			return fmt.Errorf("answer %s: empty selection group", id)
		}
		for _, row := range group {
			if row < 0 || row >= len(menu.Rows) {
				return fmt.Errorf("answer %s: selection %d out of range for %d rows", id, row, len(menu.Rows))
			}
		}
	}

	for _, group := range selections {
		for i, row := range group {
			if err := driver.NavigateTo(ctx, reader.ReadMenu, keys, row); err != nil {
				return m.answerFailure(ctx, id, driver, err)
			}
			// Multi-select toggles each row and submits once at the end; a
			// single-select submits on the row itself.
			if len(group) > 1 && keys.Multi != "" && i < len(group) {
				if err := driver.Press(ctx, keys.Multi); err != nil {
					return m.answerFailure(ctx, id, driver, err)
				}
			}
		}
		if err := driver.Press(ctx, keys.Select); err != nil {
			return m.answerFailure(ctx, id, driver, err)
		}
	}
	m.ClearInteractions(id)
	return nil
}

func (m *Manager) answerFailure(ctx context.Context, id domain.SessionID, driver *dialogdriver.Driver, err error) error {
	if errors.Is(err, dialogdriver.ErrNotOnScreen) {
		m.ClearInteractions(id)
		return ErrDialogAbsent
	}
	if errors.Is(err, dialogdriver.ErrUnconfirmed) {
		return ErrUnconfirmed
	}
	return fmt.Errorf("answer %s: %w", id, err)
}
```

Extend `fakeMenuReader` from Task 7 with a `multi` field so the multi-select test can drive it.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd backend && go test ./internal/session_manager/ -run "TestAnswer|TestDecide" -v
```

Expected: PASS, eleven tests.

- [ ] **Step 5: Add the route, spec entry, and controller tests**

Same error mapping as Task 9, plus `400 SESSION_ANSWER_INVALID` for an out-of-range or empty selection.

```bash
npm run api && npm run lint
```

Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add backend/ frontend/src/api/schema.ts
git commit -m "feat(api): answer a question's menu from a client"
```

---

## Task 11: The queued-send spike

**This task's deliverable is an answer written down, not code you keep.** The spec calls for it explicitly: find out whether a message typed during an active turn lands in the harness's own queue intact.

**Files:**
- Create: `docs/superpowers/plans/2026-09-04-queued-send-spike.md`
- Modify: `backend/internal/session_manager/manager.go` (only if the spike says yes)

- [ ] **Step 1: Run the probe on Claude Code**

Spawn a real Claude Code session, give it a long task, and while the turn is active write a message straight into the pty, bypassing the idle gate:

```bash
opr send <session-id> "queued message one"
```

If `opr send` refuses while active, drive the pty directly through the mobile raw key row or a one-off Go test against `runtime.SendInput`. Record: does the text appear in the composer? Does it submit when the turn ends? Does a `prompt_submit` hook fire for it? Does the transcript show a `queue-operation` record?

- [ ] **Step 2: Run the same probe on Codex**

Same procedure, same four questions.

- [ ] **Step 3: Run the adversarial case on both**

Send **while the agent is mid-render** (during a long tool output scroll), not merely while active. This is the case the idle gate was written for; if text is swallowed anywhere, it is here. Try five sends in a row.

- [ ] **Step 4: Write the findings**

Create `docs/superpowers/plans/2026-09-04-queued-send-spike.md` with, per harness: what was typed, what the screen showed, whether a `prompt_submit` arrived, and a **recommendation — relax the gate for this harness, or keep it**. Include the raw evidence. A spike with no evidence in it is an opinion.

- [ ] **Step 5: Act on the finding**

- **If the queue holds:** relax the idle gate for that harness only, behind a per-harness predicate beside `harnessNudgeSafe` ([`manager.go:2475`](../../../backend/internal/session_manager/manager.go)). Add a test that a send during an active turn is delivered rather than refused for that harness, and still gated for the others.
- **If it does not:** change nothing in the daemon. Record why. The client shows *queued* either way (Task 13); only the delivery path differs.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/plans/2026-09-04-queued-send-spike.md backend/
git commit -m "docs: record the queued-send spike findings"
```

---

## Task 12: Mobile data layer

**Files:**
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Create: `packages/mobile/lib/feature/blocks/data/model/params/session_command_params.dart`
- Create: `packages/mobile/lib/feature/blocks/data/model/params/session_decision_params.dart`
- Create: `packages/mobile/lib/feature/blocks/data/model/params/session_answer_params.dart`
- Create: `packages/mobile/lib/feature/blocks/data/model/session_command_result_model.dart`
- Create: `packages/mobile/lib/feature/blocks/data/model/pending_interaction_model.dart`
- Create: `packages/mobile/lib/feature/blocks/data/data_source/session_control_remote_data_source.dart`
- Create: `packages/mobile/lib/feature/blocks/data/repository/session_control_repository.dart`
- Create: `packages/mobile/test/feature/blocks/data/session_control_remote_data_source_test.dart`

**Interfaces:**
- Consumes: the four routes from Tasks 3, 8, 9, 10.
- Produces: `SessionControlRemoteDataSource` with `sendCommand`, `decide`, `answer`, `getInteractions`; `SessionCommandResultModel{String? state; List<String>? models}`; `PendingInteractionModel{String? id, kind, toolName, toolInput; List<String>? lines}`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/blocks/data/session_control_remote_data_source_test.dart`. Follow the mocktail patterns already used by the terminal data-source tests in this package:

```dart
void main() {
  late MockApiConsumer api;
  late SessionControlRemoteDataSourceImpl dataSource;

  setUp(() {
    api = MockApiConsumer();
    dataSource = SessionControlRemoteDataSourceImpl(api);
  });

  test('sendCommand posts to the session command endpoint', () async {
    when(() => api.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: {'state': 'sent'},
            ));

    final result = await dataSource.sendCommand('s1', const SessionCommandParams(command: 'stop'));

    verify(() => api.post('/api/v1/sessions/s1/command', body: {'command': 'stop'})).called(1);
    expect(result.data?.state, 'sent');
  });

  test('sendCommand carries the model label and parses the offered rows', () async {
    when(() => api.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: {'state': 'sent', 'models': ['sonnet', 'opus']},
            ));

    final result = await dataSource.sendCommand(
      's1',
      const SessionCommandParams(command: 'model', model: 'opus'),
    );

    verify(() => api.post('/api/v1/sessions/s1/command', body: {'command': 'model', 'model': 'opus'})).called(1);
    expect(result.data?.models, ['sonnet', 'opus']);
  });

  test('decide posts the request id and behavior', () async {
    when(() => api.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: {'state': 'sent'},
            ));

    await dataSource.decide('s1', const SessionDecisionParams(requestId: 'i1', behavior: 'allow'));

    verify(() => api.post('/api/v1/sessions/s1/decision',
        body: {'requestId': 'i1', 'behavior': 'allow'})).called(1);
  });

  test('answer posts the nested selections', () async {
    when(() => api.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: {'state': 'sent'},
            ));

    await dataSource.answer('s1', const SessionAnswerParams(requestId: 'q1', selections: [[0], [2, 3]]));

    verify(() => api.post('/api/v1/sessions/s1/answer',
        body: {'requestId': 'q1', 'selections': [[0], [2, 3]]})).called(1);
  });

  test('getInteractions parses the reconnect list', () async {
    when(() => api.get(any())).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: ''),
          data: {
            'interactions': [
              {'id': 'i1', 'kind': 'permission', 'toolName': 'Bash', 'toolInput': '{}'}
            ]
          },
        ));

    final result = await dataSource.getInteractions('s1');

    verify(() => api.get('/api/v1/sessions/s1/interactions')).called(1);
    expect(result.data?.single.id, 'i1');
    expect(result.data?.single.kind, 'permission');
  });

  test('a missing field parses to null rather than throwing', () async {
    when(() => api.get(any())).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: ''),
          data: {'interactions': [<String, dynamic>{}]},
        ));

    final result = await dataSource.getInteractions('s1');

    expect(result.data?.single.id, isNull);
    expect(result.data?.single.toolName, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd packages/mobile && flutter test test/feature/blocks/data/session_control_remote_data_source_test.dart
```

Expected: FAIL — the imports do not resolve.

- [ ] **Step 3: Add the endpoints**

In `end_points.dart`, beside `sessionSend`:

```dart
  static String sessionCommand(String sessionId) => '${_session(sessionId)}/command';
  static String sessionDecision(String sessionId) => '${_session(sessionId)}/decision';
  static String sessionAnswer(String sessionId) => '${_session(sessionId)}/answer';
  static String sessionInteractions(String sessionId) => '${_session(sessionId)}/interactions';
```

- [ ] **Step 4: Write the params and models**

One params class per method, all model fields nullable, hand-written `fromJson`:

```dart
class SessionCommandParams {
  const SessionCommandParams({required this.command, this.model});

  final String command;
  final String? model;

  Map<String, dynamic> toJson() => {
        'command': command,
        if (model != null) 'model': model,
      };
}
```

```dart
class SessionCommandResultModel {
  const SessionCommandResultModel({this.state, this.models});

  final String? state;
  final List<String>? models;

  factory SessionCommandResultModel.fromJson(Map<String, dynamic> json) => SessionCommandResultModel(
        state: json['state'] as String?,
        models: (json['models'] as List?)?.map((e) => e as String).toList(),
      );
}
```

`SessionDecisionParams{requestId, behavior}`, `SessionAnswerParams{requestId, selections}` and `PendingInteractionModel{id, kind, toolName, toolInput, lines}` follow the same shape.

- [ ] **Step 5: Write the data source and repository**

Every parse is `GlobalResponse.fromJson(response.data, withDataKey: false)`. The repository maps Dio failures onto the daemon's `code` so the cubit can branch on `SESSION_DIALOG_ABSENT`, `SESSION_COMMAND_UNAVAILABLE` and `SESSION_AWAITING_DECISION` without parsing prose. Keep `requestId`.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd packages/mobile && flutter test test/feature/blocks/data/session_control_remote_data_source_test.dart
```

Expected: PASS, six tests.

- [ ] **Step 7: Run the gates**

```bash
cd packages/mobile && flutter analyze && flutter test
```

Expected: `No issues found!` and a green suite.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib/core/api/ packages/mobile/lib/feature/blocks/data/ packages/mobile/test/feature/blocks/data/
git commit -m "feat(mobile): add the session control data layer"
```

---

## Task 13: Client-side confirmation — the pure part

Per finding 4 the daemon does not track confirmation, so the client does. Keep the rule in a pure function with its own tests before any widget depends on it.

**Files:**
- Create: `packages/mobile/lib/feature/blocks/logic/command_confirmation.dart`
- Create: `packages/mobile/test/feature/blocks/logic/command_confirmation_test.dart`

**Interfaces:**
- Consumes: `BlockEventModel` (Phase 2).
- Produces: `enum CommandPhase { idle, sending, sent, confirmed, unconfirmed }`; `bool confirmsCommand(String command, BlockEventModel event)`; `bool confirmsStop(String? activity)`; `const kCommandConfirmationBudget = Duration(seconds: 20)`.

- [ ] **Step 1: Write the failing test**

```dart
void main() {
  test('a compaction event confirms compact', () {
    expect(confirmsCommand('compact', _event(kind: 'compaction')), isTrue);
  });

  test('a turn_model event confirms model', () {
    expect(confirmsCommand('model', _event(kind: 'turn_model')), isTrue);
  });

  test('a compaction event does not confirm model', () {
    expect(confirmsCommand('model', _event(kind: 'compaction')), isFalse);
  });

  test('an assistant_text event confirms nothing', () {
    for (final command in ['stop', 'compact', 'model']) {
      expect(confirmsCommand(command, _event(kind: 'assistant_text')), isFalse);
    }
  });

  test('stop is confirmed by the session going idle, not by a block event', () {
    expect(confirmsCommand('stop', _event(kind: 'stop')), isFalse);
    expect(confirmsStop('idle'), isTrue);
    expect(confirmsStop('active'), isFalse);
    expect(confirmsStop(null), isFalse);
  });
}
```

Write `_event` as a small `BlockEventModel` builder in the test file.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd packages/mobile && flutter test test/feature/blocks/logic/command_confirmation_test.dart
```

Expected: FAIL — `confirmsCommand` undefined.

- [ ] **Step 3: Implement**

```dart
/// The daemon reports only that a write landed and the screen moved; whether a
/// command took effect is read from the streams this client already receives.
/// A command whose signal never arrives is shown as unconfirmed, never as done.
enum CommandPhase { idle, sending, sent, confirmed, unconfirmed }

const kCommandConfirmationBudget = Duration(seconds: 20);

bool confirmsCommand(String command, BlockEventModel event) {
  switch (command) {
    case 'compact':
      return event.kind == 'compaction';
    case 'model':
      return event.kind == 'turn_model';
    default:
      return false;
  }
}

/// Stop is confirmed by the session leaving the active state. The stop hook
/// arrives as an activity patch rather than a block, so it is checked apart
/// from confirmsCommand.
bool confirmsStop(String? activity) => activity == 'idle';
```

`model`'s budget is deliberately not `kCommandConfirmationBudget`: `turn_model` only arrives on the next turn, which may be much later. Give the model button no confirmation timer at all — it sits at **sent** until a `turn_model` arrives, whenever that is. Encode that in Task 14, not here.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd packages/mobile && flutter test test/feature/blocks/logic/command_confirmation_test.dart
```

Expected: PASS, five tests.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib/feature/blocks/logic/command_confirmation.dart packages/mobile/test/feature/blocks/logic/command_confirmation_test.dart
git commit -m "feat(mobile): define which signal confirms which command"
```

---

## Task 14: `SessionCommandCubit`

**Files:**
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart`
- Create: `packages/mobile/test/feature/blocks/presentation/session_command_cubit_test.dart`

**Interfaces:**
- Consumes: `SessionControlRepository` (Task 12), `confirmsCommand`/`confirmsStop`/`CommandPhase` (Task 13), `BlocksCubit.active` (Phase 2).
- Produces: `SessionCommandCubit` with `Map<String, CommandPhase> phases`, `List<String> models`, `Future<void> run(String command, {String? model})`, `Future<void> decide(String requestId, String behavior)`, `Future<void> answer(String requestId, List<List<int>> selections)`, `void onEvent(BlockEventModel)`, `void onActivity(String? activity)`, `bool enabled(String command)`, `String? disabledReason(String command)`.

- [ ] **Step 1: Write the failing test**

```dart
void main() {
  late MockSessionControlRepository repo;
  late SessionCommandCubit cubit;

  setUp(() {
    repo = MockSessionControlRepository();
    cubit = SessionCommandCubit(repo, sessionId: 's1');
  });

  test('stop is enabled only while active', () {
    cubit.onActivity('active');
    expect(cubit.enabled('stop'), isTrue);
    expect(cubit.enabled('compact'), isFalse);

    cubit.onActivity('idle');
    expect(cubit.enabled('stop'), isFalse);
    expect(cubit.enabled('compact'), isTrue);
  });

  test('every command is disabled while blocked, with a reason', () {
    cubit.onActivity('blocked');
    for (final command in ['stop', 'compact', 'model']) {
      expect(cubit.enabled(command), isFalse, reason: command);
      expect(cubit.disabledReason(command), isNotNull, reason: command);
    }
  });

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a successful command walks sending -> sent',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => const SessionCommandResultModel(state: 'sent'),
      );
      return cubit..onActivity('idle');
    },
    act: (c) => c.run('compact'),
    verify: (c) => expect(c.phases['compact'], CommandPhase.sent),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a compaction event moves compact from sent to confirmed',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => const SessionCommandResultModel(state: 'sent'),
      );
      return cubit..onActivity('idle');
    },
    act: (c) async {
      await c.run('compact');
      c.onEvent(_event(kind: 'compaction'));
    },
    verify: (c) => expect(c.phases['compact'], CommandPhase.confirmed),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a refused command returns to idle and never claims sent',
    build: () {
      when(() => repo.sendCommand(any(), any()))
          .thenThrow(ApiFailure(code: 'SESSION_COMMAND_UNAVAILABLE'));
      return cubit..onActivity('active');
    },
    act: (c) => c.run('compact'),
    verify: (c) => expect(c.phases['compact'], CommandPhase.idle),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a model command stores the rows the picker offered',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => const SessionCommandResultModel(state: 'sent', models: ['sonnet', 'opus']),
      );
      return cubit..onActivity('idle');
    },
    act: (c) => c.run('model', model: 'opus'),
    verify: (c) => expect(c.models, ['sonnet', 'opus']),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a model rejection still refreshes the seed list from what was offered',
    build: () {
      when(() => repo.sendCommand(any(), any()))
          .thenThrow(ApiFailure(code: 'SESSION_MODEL_NOT_OFFERED', models: ['sonnet', 'haiku']));
      return cubit..onActivity('idle');
    },
    act: (c) => c.run('model', model: 'opus'),
    verify: (c) {
      expect(c.phases['model'], CommandPhase.idle);
      expect(c.models, ['sonnet', 'haiku']);
    },
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'stop confirms when the session goes idle',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => const SessionCommandResultModel(state: 'sent'),
      );
      return cubit..onActivity('active');
    },
    act: (c) async {
      await c.run('stop');
      c.onActivity('idle');
    },
    verify: (c) => expect(c.phases['stop'], CommandPhase.confirmed),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a command whose signal never arrives becomes unconfirmed',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => const SessionCommandResultModel(state: 'sent'),
      );
      return SessionCommandCubit(repo, sessionId: 's1', budget: Duration.zero)..onActivity('idle');
    },
    act: (c) async {
      await c.run('compact');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    },
    verify: (c) => expect(c.phases['compact'], CommandPhase.unconfirmed),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'model sits at sent with no timer, because turn_model may be a whole turn away',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => const SessionCommandResultModel(state: 'sent'),
      );
      return SessionCommandCubit(repo, sessionId: 's1', budget: Duration.zero)..onActivity('idle');
    },
    act: (c) async {
      await c.run('model', model: 'opus');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    },
    verify: (c) => expect(c.phases['model'], CommandPhase.sent),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a decision reporting unconfirmed is not shown as done',
    build: () {
      when(() => repo.decide(any(), any())).thenAnswer(
        (_) async => const SessionCommandResultModel(state: 'unconfirmed'),
      );
      return cubit..onActivity('blocked');
    },
    act: (c) => c.decide('i1', 'allow'),
    verify: (c) => expect(c.phases['decision'], CommandPhase.unconfirmed),
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/session_command_cubit_test.dart
```

Expected: FAIL — `SessionCommandCubit` undefined.

- [ ] **Step 3: Implement the cubit**

Cubit only, never `Bloc` with events. Rules it must encode:

- `enabled('stop')` is `activity == 'active'`; `enabled('compact')` and `enabled('model')` are `activity == 'idle'`. Everything is disabled while `blocked`.
- `disabledReason` returns the sentence the button shows on a disabled tap: `'The agent is working'`, `'The agent is idle'`, `'Answer the permission request first'`.
- `run` sets `sending`, awaits the repository, sets `sent` on success and back to `idle` on refusal — never `sent` on a refusal.
- A `SESSION_MODEL_NOT_OFFERED` failure still refreshes `models` from what the daemon returned. The seed list self-heals from a rejection as much as from a success.
- `onEvent` promotes `sent` to `confirmed` via `confirmsCommand`; `onActivity` does the same for stop via `confirmsStop`.
- A `sent` command that sees no signal within `budget` becomes `unconfirmed` — **except `model`, which has no timer at all.**
- `decide` and `answer` share the phase map under the keys `'decision'` and `'answer'`, and a `state` of `'unconfirmed'` from the daemon maps straight to `CommandPhase.unconfirmed`.

Cancel every timer in `close()`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/session_command_cubit_test.dart
```

Expected: PASS, eleven tests.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart packages/mobile/test/feature/blocks/presentation/session_command_cubit_test.dart
git commit -m "feat(mobile): three-state command tracking with client-side confirmation"
```

---

## Task 15: The command row and the model sheet

**Files:**
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/session_command_row.dart`
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/model_picker_sheet.dart`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart:100-110`
- Create: `packages/mobile/test/feature/blocks/presentation/blocks_screen/session_command_row_test.dart`

**Interfaces:**
- Consumes: `SessionCommandCubit` (Task 14).
- Produces: `SessionCommandRow` (no constructor arguments — it reads the cubit from context, as `TerminalKeyRow` does).

- [ ] **Step 1: Write the failing test**

```dart
void main() {
  testWidgets('the row renders three buttons in every session state', (tester) async {
    for (final activity in ['idle', 'active', 'blocked']) {
      await tester.pumpWidget(_host(activity: activity));
      expect(find.byType(SessionCommandButton), findsNWidgets(3));
    }
  });

  testWidgets('the row height does not change with session state', (tester) async {
    await tester.pumpWidget(_host(activity: 'idle'));
    final idle = tester.getSize(find.byType(SessionCommandRow));

    await tester.pumpWidget(_host(activity: 'blocked'));
    await tester.pumpAndSettle();
    final blocked = tester.getSize(find.byType(SessionCommandRow));

    expect(blocked, idle, reason: 'a reflowing row is the thing the fixed key row exists to avoid');
  });

  testWidgets('tapping a disabled button shows why instead of calling the cubit', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.enabled('compact')).thenReturn(false);
    when(() => cubit.disabledReason('compact')).thenReturn('The agent is working');

    await tester.pumpWidget(_host(activity: 'active', cubit: cubit));
    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();

    expect(find.text('The agent is working'), findsOneWidget);
    verifyNever(() => cubit.run(any()));
  });

  testWidgets('tapping stop while active runs the command', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.enabled('stop')).thenReturn(true);
    when(() => cubit.run(any())).thenAnswer((_) async {});

    await tester.pumpWidget(_host(activity: 'active', cubit: cubit));
    await tester.tap(find.text('Stop'));
    await tester.pump();

    verify(() => cubit.run('stop')).called(1);
  });

  testWidgets('tapping model opens the picker rather than running immediately', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.enabled('model')).thenReturn(true);
    when(() => cubit.models).thenReturn(['sonnet', 'opus']);

    await tester.pumpWidget(_host(activity: 'idle', cubit: cubit));
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();

    expect(find.byType(ModelPickerSheet), findsOneWidget);
    verifyNever(() => cubit.run(any(), model: any(named: 'model')));
  });

  testWidgets('picking a model runs the command with that label', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.enabled('model')).thenReturn(true);
    when(() => cubit.models).thenReturn(['sonnet', 'opus']);
    when(() => cubit.run(any(), model: any(named: 'model'))).thenAnswer((_) async {});

    await tester.pumpWidget(_host(activity: 'idle', cubit: cubit));
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('opus'));
    await tester.pumpAndSettle();

    verify(() => cubit.run('model', model: 'opus')).called(1);
  });

  testWidgets('an unconfirmed command is visibly distinct from a confirmed one', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.phases).thenReturn({'compact': CommandPhase.unconfirmed});
    await tester.pumpWidget(_host(activity: 'idle', cubit: cubit));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('the row is absent in raw mode and present in blocks mode', (tester) async {
    await tester.pumpWidget(_terminalBody(mode: SessionViewMode.raw));
    expect(find.byType(SessionCommandRow), findsNothing);
    expect(find.byType(TerminalKeyRow), findsOneWidget);

    await tester.pumpWidget(_terminalBody(mode: SessionViewMode.blocks));
    await tester.pumpAndSettle();
    expect(find.byType(SessionCommandRow), findsOneWidget);
    expect(find.byType(TerminalKeyRow), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_screen/session_command_row_test.dart
```

Expected: FAIL — `SessionCommandRow` undefined.

- [ ] **Step 3: Write the row**

Mirror `TerminalKeyRow`'s structure exactly — same padding, same `Expanded` per button, same `borderRadius`, same `skin.bgElevated` / `skin.borderDefault`, `Haptics.tap()` on tap. Three buttons: `Stop`, `Compact`, `Model`. The contract from `terminal_key_row.dart:11` applies verbatim: **fixed count, fixed height, one flex each — pixel-identical in every state the screen can reach.** State shows through colour and a trailing indicator, never through layout.

Per phase: `sending` a small spinner in place of the indicator; `sent` a subdued check; `confirmed` a full-colour check; `unconfirmed` `Icons.error_outline` in `skin.attention`. Disabled uses a muted foreground and taps to a snackbar carrying `disabledReason`.

- [ ] **Step 4: Write the sheet**

`ModelPickerSheet` lists `cubit.models`, one row each, and pops with the chosen label. When `models` is empty, seed it from a per-harness constant so the first-ever tap has something to show; the daemon's response replaces it from then on.

- [ ] **Step 5: Mount it in `terminal_body.dart`**

Replace the existing conditional so blocks mode gets the command row where raw mode gets the key row:

```dart
                      if (context.read<SessionViewCubit>().mode == SessionViewMode.raw)
                        const TerminalKeyRow()
                      else
                        const SessionCommandRow(),
                      const TerminalComposer(),
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_screen/session_command_row_test.dart
```

Expected: PASS, eight tests.

- [ ] **Step 7: Run the full mobile gate**

```bash
cd packages/mobile && flutter analyze && flutter test
```

Expected: `No issues found!`, whole suite green. Existing `terminal_body` tests may need updating for the new row; update them rather than skipping.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib/feature/ packages/mobile/test/feature/
git commit -m "feat(mobile): add the blocks-view command row"
```

---

## Task 16: Actionable permission and question blocks, then the final gates

The last piece of the spec's Phase 3 surface: the blocks themselves become answerable.

**Files:**
- Modify: `packages/mobile/lib/feature/blocks/logic/session_block.dart` (add `interactionId`)
- Modify: `packages/mobile/lib/feature/blocks/logic/block_assembly.dart` (carry it through the merge)
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_question_options.dart`
- Modify: `packages/mobile/test/feature/blocks/logic/block_assembly_test.dart`
- Modify: `packages/mobile/test/feature/blocks/presentation/blocks_screen/transcript_rendering_test.dart`

**Interfaces:**
- Consumes: `SessionCommandCubit.decide`/`answer` (Task 14), `PendingInteractionModel` (Task 12).

- [ ] **Step 1: Write the failing assembly test**

```dart
test('a permission event carries its interaction id onto the block', () {
  final blocks = assembleBlocks([
    _event(kind: 'permission_request', sourceId: 't1', interactionId: 'i1'),
  ]);

  expect(blocks.single.interactionId, 'i1');
});

test('a block with no interaction id is not actionable', () {
  final blocks = assembleBlocks([_event(kind: 'tool_start', sourceId: 't1')]);

  expect(blocks.single.interactionId, isNull);
});

test('the transcript merge preserves the hook-supplied interaction id', () {
  final blocks = assembleBlocks([
    _event(kind: 'permission_request', sourceId: 't1', interactionId: 'i1'),
    _event(kind: 'tool_start', sourceId: 't1', source: 'transcript', toolInput: '{"command":"ls"}'),
  ]);

  expect(blocks.single.interactionId, 'i1',
      reason: 'transcript wins on body, but it must not erase the id the hook supplied');
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd packages/mobile && flutter test test/feature/blocks/logic/block_assembly_test.dart
```

Expected: FAIL — no `interactionId` on `SessionBlock`.

- [ ] **Step 3: Thread the id through**

Add `interactionId` to `SessionBlock`, its `copyWith`, and `props`. In `block_assembly.dart`, set it from the event and — critically — **preserve it across a transcript merge**. The Phase 2 precedence rule is *transcript wins on body, hook wins on status*; the interaction id is neither, and a transcript `tool_start` merging onto a hook permission block must not null it.

- [ ] **Step 4: Write the failing widget test**

```dart
testWidgets('a permission block offers allow and deny', (tester) async {
  await tester.pumpWidget(_card(_permissionBlock(interactionId: 'i1')));

  expect(find.text('Allow'), findsOneWidget);
  expect(find.text('Deny'), findsOneWidget);
});

testWidgets('allow calls decide with the block interaction id', (tester) async {
  final cubit = MockSessionCommandCubit();
  when(() => cubit.decide(any(), any())).thenAnswer((_) async {});

  await tester.pumpWidget(_card(_permissionBlock(interactionId: 'i1'), cubit: cubit));
  await tester.tap(find.text('Allow'));
  await tester.pump();

  verify(() => cubit.decide('i1', 'allow')).called(1);
});

testWidgets('a permission block with no interaction id is not actionable', (tester) async {
  await tester.pumpWidget(_card(_permissionBlock(interactionId: null)));

  expect(find.text('Allow'), findsNothing);
  expect(find.text('Answer in the terminal'), findsOneWidget);
});

testWidgets('question options are tappable and post the selection', (tester) async {
  final cubit = MockSessionCommandCubit();
  when(() => cubit.answer(any(), any())).thenAnswer((_) async {});

  await tester.pumpWidget(_card(_questionBlock(interactionId: 'q1', options: ['first', 'second'])));
  await tester.tap(find.text('second'));
  await tester.pump();

  verify(() => cubit.answer('q1', [[1]])).called(1);
});

testWidgets('a multi-select question submits every chosen row', (tester) async {
  final cubit = MockSessionCommandCubit();
  when(() => cubit.answer(any(), any())).thenAnswer((_) async {});

  await tester.pumpWidget(_card(
    _questionBlock(interactionId: 'q1', options: ['a', 'b', 'c'], multiSelect: true),
    cubit: cubit,
  ));
  await tester.tap(find.text('a'));
  await tester.tap(find.text('c'));
  await tester.tap(find.text('Submit'));
  await tester.pump();

  verify(() => cubit.answer('q1', [[0, 2]])).called(1);
});
```

- [ ] **Step 5: Make the blocks actionable**

A permission block with an `interactionId` renders Allow and Deny; without one it keeps today's "Answer in the terminal" copy — a session whose dialog the daemon never registered must not offer a button that cannot work. `block_question_options.dart` replaces its Phase 2 read-only rendering with real controls, single-select submitting on tap and multi-select accumulating behind a Submit.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd packages/mobile && flutter test test/feature/blocks/
```

Expected: PASS.

- [ ] **Step 7: Run every gate**

```bash
npm run lint
cd backend && go build ./... && go vet ./... && go test -race ./internal/session_manager/ ./internal/service/dialogdriver/
cd .. && npm run api && npm run sqlc && git status --porcelain
cd frontend && npm run typecheck && npm run lint && npx vitest run
cd ../packages/mobile && flutter analyze && flutter test
```

Expected: every one green; `git status --porcelain` empty after regeneration.

- [ ] **Step 8: Live smoke test on both harnesses**

**This cannot be delegated to a background agent** — it needs a running daemon, the desktop app, and a paired phone. Phase 2's report flagged the same gap, and the two real bugs its final review caught were exactly this class. Run it before merge, not after:

1. Spawn a real Claude Code session. On the phone, confirm the command row is present in blocks mode and absent in raw.
2. Give the agent a long task. **Stop** from the phone; confirm the desktop terminal interrupts and the button reaches *confirmed*.
3. While idle, **Compact**; confirm the compaction block arrives and the button confirms.
4. **Model**: confirm the sheet lists real rows, that picking one changes the model in the desktop terminal, and that the terminal is **not** left sitting in an open picker. Then pick a model that is not offered and confirm the picker is backed out of.
5. Trigger a permission dialog. Confirm the desktop dialog renders immediately (the hook must not block it), answer **Allow** from the phone, and confirm the desktop dialog closes and the tool runs. Repeat with **Deny**.
6. Trigger an `AskUserQuestion`. Confirm real options render on the phone, answer from the phone, and confirm the agent received the answer you chose.
7. With a dialog pending, confirm **send is still refused** from the phone.
8. Answer a dialog **in the desktop terminal** while the phone shows it pending; confirm the phone's next attempt reports the dialog as gone rather than answering the next one.
9. Repeat 1-7 on a real Codex session, skipping the question step.

Write the results into `docs/superpowers/plans/2026-09-04-single-session-phase-3-report.md`, including anything that did not work.

- [ ] **Step 9: Commit and open the PR**

```bash
git add -A
git commit -m "feat(mobile): make permission and question blocks answerable"
```

---

## Notes for the executor

- **Tasks 1-3 need no screen reading** and are the cheap proof that the write path works. If something is wrong with pty writes or activity gating, it surfaces there, before the driver is built on top.
- **Tasks 4 and 5 are fixture work first.** Do not write a matcher against a screen you have not captured. A reader that passes tests written from an imagined pane is worse than no reader, because the driver will trust it and press a key.
- **Task 11 is a spike**, and its deliverable is a written finding. Do not keep probe code.
- **Never retry an unconfirmed write.** The key may well have landed and simply not redrawn; a second key answers the *next* dialog. `ErrUnconfirmed` is reported, never retried, at every layer.
- **A refused action writes nothing.** Every backend test in this plan asserts that explicitly, because a half-acted refusal is the failure mode that would cost a user real work.
