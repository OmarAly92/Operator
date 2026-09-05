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

6. **Every blocking dialog is the same numbered menu.** Captured from a real session on 2026-09-05 (`backend/testdata/panes/`). The permission prompt is **not** a y/n prompt — it renders as a numbered list with a `❯ ` highlight, exactly like the model picker and the question menu:

```
 Do you want to create fixture-probe.txt?
 ❯ 1. Yes
   2. Yes, and switch to accept edits (auto-approve file edits and
      common file commands) for this session (shift+tab)
   3. No
 Esc to cancel · Tab to amend
```

   The option list **varies by tool** — a Write dialog offers "switch to accept edits", a Bash dialog offers different wording — so a fixed `PermissionKey(behavior) → "y"/"n"` cannot work and **is removed from this plan**. All three dialogs share one reader and one navigation model; they are told apart by their footer, which is the stable discriminator:

   | dialog | footer |
   |---|---|
   | permission | `Esc to cancel · Tab to amend` |
   | model picker | `Enter to set as default · s to use this session only · Esc to cancel` |
   | question | `Enter to select · ↑/↓ to navigate · Esc to cancel` |

7. **The model picker's Enter is the wrong key.** Its footer says `Enter to set as default · s to use this session only`. Pressing Enter changes the user's **global default model for every new session** — far beyond what "change this session's model" asks for. The driver must press **`s`**. This was wrong in the spec and in the first draft of this plan; a fixture caught it.

8. **On-screen rows do not align with the transcript's option indices.** A real `AskUserQuestion` menu appends synthetic rows the transcript never lists:

```
❯ 1. Red
  2. Green
  3. Blue
  4. Type something.
  5. Chat about this
```

   "Type something." and "Chat about this" are the harness's own additions. A client sending index 2 from the transcript's options would land on the wrong row if any synthetic row preceded it, and free-text answers go through row 4. **Selections are resolved by matching option text against the on-screen rows, never by passing an index straight through.**

9. **The two harnesses differ in glyph, in select key, and in what they gate.** Codex fixtures captured 2026-09-05 from a real session:

   | | Claude Code | Codex |
   |---|---|---|
   | composer prompt | `❯` + **non-breaking space** | `›` + space |
   | menu highlight | `❯ N.` | `› N.` |
   | model picker footer | `Enter to set as default · s to use this session only · Esc to cancel` | `Press enter to confirm or esc to go back` |
   | session-scoped model key | `s` | **Enter** — it has no separate default |

   So `MenuKeys.SessionSelect` is `"s"` for Claude Code and `"\r"` for Codex. **Never hardcode either.** A harness with no session/default split sets `SessionSelect` equal to `Select`, and the model command reads `SessionSelect` unconditionally.

   Codex also uses `›` for **both** the composer prompt and the menu highlight, so a matcher keyed on the glyph alone will read an idle composer as a one-row menu. Require the numbered-row form (`› N.`) and the menu's own footer, never the glyph by itself. `codex_idle.txt` is the negative case that catches this.

10. **No Codex permission fixture exists, and the mapper must ship without one.** The Codex session on this machine auto-approves: `touch` inside the workspace, in `/tmp`, and in `$HOME` all ran with no dialog, and this Codex build has no `/approvals` command to tighten the policy from inside the session. Capturing one needs a session launched with a stricter approval flag, which is a spawn-time decision.

    Until such a fixture exists, **`codex.Plugin.ReadDialog` must return `false` for the permission kind rather than guess at a layout nobody has seen.** That is the fail-closed behaviour the port already demands: a Codex permission dialog is then simply not answerable from the phone, which is exactly today's behaviour and no regression. Do not write a speculative Codex permission matcher — a wrong one presses a key on an unknown screen. Tracked in `todo_without_tmux.md` §15.

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

func TestCommandStopWritesEscapeWhileActive(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityActive)

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
	m, rt := newCommandTestManager(t, domain.ActivityIdle)

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

**Do not write a new fake runtime.** `manager_test.go:1008` already has `newManager() (*Manager, *fakeStore, *fakeRuntime, *fakeWorkspace)` — no `*testing.T` argument — and a `fakeRuntime` that already implements `Create`, `Destroy`, `IsAlive`, `GetOutput`, `GetStyledOutput` and `Interrupt`. Widening `runtimeController` in Step 4 breaks that fake, so it must gain `SendInput` anyway; give it the recording behaviour there rather than standing up a parallel fake:

```go
// in manager_test.go, beside the other fakeRuntime methods
func (r *fakeRuntime) SendInput(_ context.Context, _ ports.RuntimeHandle, input string) error {
	if r.sendInputErr != nil {
		return r.sendInputErr
	}
	r.inputs = append(r.inputs, input)
	return nil
}
```

Add `inputs []string`, `sendInputErr error` and `panes []string` to the `fakeRuntime` struct, and make its existing `GetOutput` return successive entries from `panes` (holding on the last) so Tasks 6, 7, 9 and 10 can script a screen. Then the helper in `command_test.go` is thin:

```go
func newCommandTestManager(t *testing.T, state domain.ActivityState) (*Manager, *fakeRuntime) {
	t.Helper()
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:       "s1",
		Harness:  domain.HarnessClaudeCode,
		Activity: domain.SessionActivity{State: state},
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	return m, rt
}
```

Check `fakeStore`'s actual field name for its session map before writing that line; use whatever it is. Every later task in this plan builds its manager through this same two-value helper.

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
	m, rt := newCommandTestManager(t, domain.ActivityIdle)

	if _, err := m.Command(context.Background(), "s1", domain.CommandCompact, ""); err != nil {
		t.Fatalf("Command: %v", err)
	}
	if len(rt.inputs) != 1 || rt.inputs[0] != "/compact\r" {
		t.Fatalf("expected one /compact write, got %q", rt.inputs)
	}
}

func TestCommandCompactRefusedWhileActive(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityActive)

	_, err := m.Command(context.Background(), "s1", domain.CommandCompact, "")
	if !errors.Is(err, ErrWrongActivityState) {
		t.Fatalf("expected ErrWrongActivityState, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("a refused command must write nothing, got %q", rt.inputs)
	}
}

func TestCommandCompactRefusedWhileBlocked(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)

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

**Use the package's real helpers, not the invented ones above.** `projects_test.go:522` has `doRequest(t, srv, method, path, body) ([]byte, int, http.Header)` against an `httptest.Server`, and `:630` has `assertErrorCode(t, body, status, wantStatus, wantCode)`. Rewrite each test above in that idiom — the assertions are what matter, not the helper names. Add the `commandResult`/`commandErr`/`commandCalls` fields to whatever fake the package already uses for the session service.

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
- Produces: `ports.TerminalDialogReader` with `ReadDialog(pane string) (ports.Dialog, bool)`, `AllowRow(ports.Menu) (int, bool)` and `DenyRow(ports.Menu) (int, bool)`; `ports.Dialog{Kind DialogKind; Title string; Menu Menu}`; `ports.DialogKind` with `DialogPermission`/`DialogQuestion`/`DialogModel`. Both `claudecode.Plugin` and `codex.Plugin` implement it. `ports.Menu` and the shared `readNumberedMenu` helper are defined here and reused by Task 5.
- Consumes: nothing.

- [ ] **Step 1: Capture real fixtures**

**`opr pane-capture` is not the tool** — it is a hidden command that journals a byte stream from stdin, and takes `--dir`/`--epoch`, not a session id. There is no HTTP route that returns a pane either. The pane lives in the pty-host's ring buffer, reachable through `ptyhost.Runtime.GetOutput`, which resolves a session id via the B2 registry at `~/.operator/windows-pty-hosts.json` (that path is HOME-based and the same on macOS despite the name).

Write a throwaway reader inside the backend module — it must be in-module to import `internal/`:

```go
// backend/tmp_panecap/main.go — delete after capturing
package main

import (
	"context"
	"fmt"
	"os"
	"strconv"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func main() {
	id := os.Args[1]
	lines := 40
	if len(os.Args) > 2 {
		lines, _ = strconv.Atoi(os.Args[2])
	}
	styled := len(os.Args) > 3 && os.Args[3] == "styled"

	rt := ptyhost.New(ptyhost.Options{})
	var out string
	var err error
	if styled {
		out, err = rt.GetStyledOutput(context.Background(), ports.RuntimeHandle{ID: id}, lines)
	} else {
		out, err = rt.GetOutput(context.Background(), ports.RuntimeHandle{ID: id}, lines)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
	fmt.Print(out)
}
```

```bash
cd backend && go run ./tmp_panecap <session-id> 40           # plain, what GetOutput returns
cd backend && go run ./tmp_panecap <session-id> 40 styled    # SGR preserved, for highlight detection
```

Spawn a real session of each harness and trigger a permission dialog (a `Bash` call for Claude Code; a shell command for Codex). Save each dump under `backend/testdata/panes/`, then **replace the content** — file paths, command text, repo names — with neutral placeholders, keeping the box drawing, prompts, key hints, and line structure byte-for-byte. The structure is what the readers match on; the content is not.

**`claudecode_idle.txt` is already captured and scrubbed**, from a real session on 2026-09-05. Read it before writing any matcher — and note what it proves: the separator after Claude Code's `❯` prompt glyph is a **non-breaking space (`c2a0`), not an ASCII space**. A matcher written from an imagined screen would have used `"❯ "` and silently never matched. Check the bytes of anything you intend to match:

```bash
sed -n '<line>p' <fixture> | head -c 60 | xxd
```

Capture an idle pane for each remaining harness the same way. These are the negative cases and they matter as much.

A session whose pty-host was restarted has an empty ring buffer and returns almost nothing; if a capture comes back near-empty, that is the cause — use a session with visible scrollback rather than debugging the reader.

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

func TestReadDialogRecognisesTheRealPermissionDialog(t *testing.T) {
	p := &Plugin{}
	dlg, ok := p.ReadDialog(readPane(t, "claudecode_permission.txt"))
	if !ok {
		t.Fatal("expected the permission dialog to be recognised")
	}
	if dlg.Kind != ports.DialogPermission {
		t.Fatalf("Kind = %q, want permission", dlg.Kind)
	}
	if len(dlg.Menu.Rows) != 3 {
		t.Fatalf("the captured fixture has 3 options, got %v", dlg.Menu.Rows)
	}
	allow, ok := p.AllowRow(dlg.Menu)
	if !ok || allow != 0 {
		t.Fatalf("AllowRow = %d, %v; want row 0 (\"1. Yes\")", allow, ok)
	}
	deny, ok := p.DenyRow(dlg.Menu)
	if !ok || deny != 2 {
		t.Fatalf("DenyRow = %d, %v; want row 2 (\"3. No\")", deny, ok)
	}
}

func TestAllowRowRejectsTheCompoundYes(t *testing.T) {
	// "2. Yes, and switch to accept edits ... for this session" widens
	// permissions for the rest of the session. A naive prefix match picks it.
	p := &Plugin{}
	menu := ports.Menu{Rows: []string{
		"2. Yes, and switch to accept edits (auto-approve file edits and common file commands) for this session (shift+tab)",
		"3. No",
	}}
	if _, ok := p.AllowRow(menu); ok {
		t.Fatal("the compound Yes must not be treated as a plain allow")
	}
}

func TestReadDialogRejectsAnIdlePane(t *testing.T) {
	p := &Plugin{}
	if _, ok := p.ReadDialog(readPane(t, "claudecode_idle.txt")); ok {
		t.Fatal("an idle pane must not be read as a dialog")
	}
}

func TestReadDialogRejectsEmptyAndGarbage(t *testing.T) {
	p := &Plugin{}
	for _, pane := range []string{"", "\n\n\n", "some unrelated output\nmore output"} {
		if _, ok := p.ReadDialog(pane); ok {
			t.Fatalf("expected no dialog for %q", pane)
		}
	}
}

func TestReadDialogTellsTheThreeKindsApartByTheirFooter(t *testing.T) {
	p := &Plugin{}
	for fixture, want := range map[string]ports.DialogKind{
		"claudecode_permission.txt":   ports.DialogPermission,
		"claudecode_model_picker.txt": ports.DialogModel,
		"claudecode_question.txt":     ports.DialogQuestion,
	} {
		dlg, ok := p.ReadDialog(readPane(t, fixture))
		if !ok {
			t.Fatalf("%s: not recognised", fixture)
		}
		if dlg.Kind != want {
			t.Fatalf("%s: Kind = %q, want %q", fixture, dlg.Kind, want)
		}
	}
}
```

Write the mirror file for `codex` with the codex fixtures and `package codex`.

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd backend && go test ./internal/adapters/agent/claudecode/ ./internal/adapters/agent/codex/ -run TestReadDialog -v
```

Expected: FAIL to compile — `p.ReadDialog undefined`.

- [ ] **Step 4: Add the port**

In `backend/internal/ports/agent.go`, beside `TerminalActivityDetector`:

```go
// DialogKind names the blocking dialogs a harness can put on screen. They all
// render as the same numbered menu (finding 6); the kind comes from the footer,
// which is what actually distinguishes them.
type DialogKind string

const (
	DialogPermission DialogKind = "permission"
	DialogQuestion   DialogKind = "question"
	DialogModel      DialogKind = "model"
)

// Dialog is a blocking prompt as rendered: its kind, its title line, and the
// menu the user is choosing from. Rows are the option text as shown, which is
// what callers match against — never a bare index, because the harness inserts
// synthetic rows the caller never knew about (finding 8).
type Dialog struct {
	Kind  DialogKind
	Title string
	Menu  Menu
}

// TerminalDialogReader is an optional adapter capability for reading a harness's
// own dialogs off the pane. Implementations MUST be pure functions of the pane
// text and MUST fail closed: an unrecognised screen returns false, never a
// guess, because the caller is about to write a keystroke on the strength of it.
type TerminalDialogReader interface {
	ReadDialog(pane string) (Dialog, bool)
	// AllowRow and DenyRow pick the row that approves or refuses a permission
	// dialog, by matching the rows' text. They return false when no row clearly
	// carries that meaning — the option list varies by tool, so guessing an
	// index would approve something the user never saw.
	AllowRow(menu Menu) (int, bool)
	DenyRow(menu Menu) (int, bool)
}
```

- [ ] **Step 5: Implement the Claude Code reader**

Create `backend/internal/adapters/agent/claudecode/dialog.go`. Write the matcher against the fixture you captured in Step 1 — the markers below are the *shape* to look for, and the exact strings must come from the real pane, not from this plan:

```go
package claudecode

import "strings"

// ReadDialog recognises any of Claude Code's blocking dialogs. It fails closed:
// the caller writes a keystroke on the strength of this answer, so an ambiguous
// screen must read as "no dialog".
//
// The three dialogs share one numbered-menu layout and differ only in their
// footer, so the footer decides the kind — see the fixtures under
// backend/testdata/panes/, which are the authority for these strings.
func (p *Plugin) ReadDialog(pane string) (ports.Dialog, bool) {
	lines := paneLines(pane)
	kind, ok := dialogKind(lines)
	if !ok {
		return ports.Dialog{}, false
	}
	menu, ok := readNumberedMenu(lines)
	if !ok || len(menu.Rows) < 2 {
		return ports.Dialog{}, false
	}
	return ports.Dialog{Kind: kind, Title: dialogTitle(lines), Menu: menu}, true
}

// AllowRow and DenyRow match by meaning, not position. A Write dialog's rows are
// "Yes" / "Yes, and switch to accept edits ..." / "No"; a Bash dialog's differ.
// The plain affirmative is the one to pick — never the "and also change a
// setting" variant, which would silently widen permissions for the session.
func (p *Plugin) AllowRow(menu ports.Menu) (int, bool) {
	for i, row := range menu.Rows {
		if isPlainYes(row) {
			return i, true
		}
	}
	return 0, false
}

func (p *Plugin) DenyRow(menu ports.Menu) (int, bool) {
	for i, row := range menu.Rows {
		if isPlainNo(row) {
			return i, true
		}
	}
	return 0, false
}
```

`dialogKind`, `dialogTitle`, `readNumberedMenu`, `paneLines`, `isPlainYes` and `isPlainNo` are yours to write from the fixtures. `readNumberedMenu` is shared with Task 5 — write it once here and reuse it. Three rules bind them:

- **`isPlainYes` must reject the compound option.** `2. Yes, and switch to accept edits ... for this session` begins with "Yes" and would match a naive prefix test, but choosing it *widens permissions for the rest of the session*. Match the bare affirmative only.


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
- Produces: `ports.TerminalMenuReader` with `ReadMenu(pane string) (ports.Menu, bool)` and `MenuKeys() ports.MenuKeys`; `ports.Menu{Rows []string; Selected int}`; `ports.MenuKeys{Up, Down, Select, Cancel, Multi, SessionSelect string}`.

`ReadMenu` is the menu-only accessor `dialogdriver.NavigateTo` consumes; implement it as a thin wrapper over Task 4's `readNumberedMenu` so there is exactly one parser for the `❯ N.` layout that all three dialogs share. Do not write a second one.

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
	if keys.SessionSelect != "s" {
		t.Fatalf("SessionSelect = %q, want \"s\" — Enter would rewrite the user's global default model", keys.SessionSelect)
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
	// SessionSelect applies a model-picker choice to THIS SESSION ONLY. Claude
	// Code's picker footer reads "Enter to set as default · s to use this
	// session only": Select there would rewrite the user's global default for
	// every future session, so the model command MUST use this key instead
	// (finding 7).
	SessionSelect string
}

// TerminalMenuReader is the menu-only view of a harness's dialogs, consumed by
// the driver's navigation loop. It MUST be pure and MUST fail closed: the driver
// navigates by comparing successive reads, so a wrong Selected moves the
// highlight to the wrong row and then presses Select on it.
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

Append to `command_test.go`. This relies on `fakeRuntime.panes` from Task 1 — `GetOutput` returns successive entries and holds on the last, mirroring `scriptedScreen` in Task 6:

```go
func TestCommandModelDrivesThePickerToTheMatchingRow(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)
	rt.panes = []string{
		"MENU:0", // after /model is typed
		"MENU:0", // NavigateTo's first read
		"MENU:1", // after one Down
	}
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
	if last := rt.inputs[len(rt.inputs)-1]; last != "s" {
		t.Fatalf("expected the session-scoped select key %q last, got %q", "s", rt.inputs)
	}
	for _, in := range rt.inputs {
		if in == "\r" && in != rt.inputs[0] {
			t.Fatal("Enter in the model picker sets the user's global default; only /model's own submit may use it")
		}
	}
}

func TestCommandModelBacksOutWhenTheLabelIsNotOffered(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)
	rt.panes = []string{"MENU:0"}
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
	m, rt := newCommandTestManager(t, domain.ActivityIdle)
	rt.panes = []string{"idle prompt"}
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
	m, rt := newCommandTestManager(t, domain.ActivityActive)

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
	// SessionSelect, never Select: the picker's Enter sets the user's DEFAULT
	// model for every new session, which is not what "change this session's
	// model" asked for (finding 7).
	if err := driver.Press(ctx, reader.MenuKeys().SessionSelect); err != nil {
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
	m, _ := newCommandTestManager(t, domain.ActivityBlocked)
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
	m, _ := newCommandTestManager(t, domain.ActivityBlocked)
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
	m, _ := newCommandTestManager(t, domain.ActivityBlocked)
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: "permission"})
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i2", Kind: "permission"})

	got, _ := m.Interactions(context.Background(), "s1")
	if len(got) != 1 || got[0].ID != "i2" {
		t.Fatalf("expected only the newest interaction, got %+v", got)
	}
}

func TestInteractionLookupMissesAnUnknownID(t *testing.T) {
	m, _ := newCommandTestManager(t, domain.ActivityBlocked)
	if _, ok := m.Interaction("s1", "nope"); ok {
		t.Fatal("expected an unknown interaction id to miss")
	}
}

func TestInteractionsOfAnUnknownSessionIsEmptyNotAnError(t *testing.T) {
	m, _ := newCommandTestManager(t, domain.ActivityIdle)
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

**Neither package imports the other** — verified; the only mentions are in comments. So declare the seam in `lifecycle` and late-bind it at daemon wiring, which is the pattern this codebase already uses for exactly this shape (`SetReviewerTerminator`, `SetTerminalInputGate`, `SetBlockPublisher`):

```go
// in internal/lifecycle
type InteractionRegistry interface {
	RegisterInteraction(id domain.SessionID, in domain.PendingInteraction)
	ClearInteractions(id domain.SessionID)
}

func (m *Manager) SetInteractionRegistry(r InteractionRegistry) { m.interactions = r }
```

Wire it in `internal/daemon/lifecycle_wiring.go` alongside the other late-bound setters, after the session manager is built. Guard every call with a nil check: lifecycle starts before the session manager, and a hook arriving in that window must not panic.

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

**The hook is a CLI that POSTs, not an in-process call.** `internal/cli/hooks.go:317` sends the signal to `POST /api/v1/sessions/{id}/activity` and deliberately exits 0 even when that POST fails. The existing tests drive it through `activityServer(t, status, respBody)` at `hooks_test.go:24`, which returns an `httptest.Server` plus a capture, with `capturedState(t, capture)` reading what was sent — `TestHooks_NotificationReportsBlocked` at `:199` is the closest model. Rewrite the test above in that idiom: point the CLI at the test server, invoke the `permission-request` sub-command, and assert exit 0, empty stdout, and that it returned promptly.

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
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"DIALOG", "moved on"}
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
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"idle prompt"}
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
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"DIALOG", "DIALOG"}
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
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"DIALOG"}
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
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"DIALOG"}
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
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"DIALOG", "moved on"}
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

Write `fakeDialogReader` in the test file, satisfying `ports.TerminalDialogReader`: it returns a `ports.Dialog` of the configured kind whose `Menu.Rows` are `["1. Yes", "3. No"]`, with `AllowRow`/`DenyRow` returning 0 and 1. The tests above assert *how many* keys were written and that the last is the menu's Select — with the fixture's highlight already on row 0, an allow navigates zero times and presses Select once, while a deny presses Down then Select.

Adjust the two "exactly one key" assertions accordingly: an allow writes one key, a deny writes two. What must not change is that a **refused** decision writes zero.

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
	if behavior != "allow" && behavior != "deny" {
		return fmt.Errorf("decide %s: unknown behavior %q", id, behavior)
	}

	handle := runtimeHandle(rec.Metadata)
	driver := m.driverFor(handle)

	// The permission prompt is a numbered menu whose options vary by tool
	// (finding 6), so the row is found by meaning and then navigated to —
	// there is no fixed answer key.
	pane, err := m.runtime.GetOutput(ctx, handle, commandPaneLines)
	if err != nil {
		return fmt.Errorf("decide %s: read dialog: %w", id, err)
	}
	dlg, on := reader.ReadDialog(pane)
	if !on || dlg.Kind != ports.DialogPermission {
		return ErrDialogAbsent
	}
	row, found := reader.AllowRow(dlg.Menu)
	if behavior == "deny" {
		row, found = reader.DenyRow(dlg.Menu)
	}
	if !found {
		return ErrDialogAbsent
	}
	keys := reader.MenuKeys()
	readMenu := func(pane string) (ports.Menu, bool) {
		d, on := reader.ReadDialog(pane)
		return d.Menu, on
	}
	if err := driver.NavigateTo(ctx, readMenu, keys, row); err != nil {
		return m.answerFailure(ctx, id, driver, err)
	}
	present := func(pane string) bool {
		d, on := reader.ReadDialog(pane)
		return on && d.Kind == ports.DialogPermission
	}
	switch err := driver.AnswerDialog(ctx, present, keys.Select); {
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
- Consumes: `dialogdriver.NavigateTo`/`Press` (Task 6), `ports.TerminalDialogReader` (Tasks 4-5), the interaction registry (Task 8).
- Produces: `(*Manager).Answer(ctx, id domain.SessionID, interactionID string, selections [][]string) error`; `controllers.SessionAnswerRequest{RequestID string; Selections [][]string}`.

**Selections are option TEXT, not indices** (finding 8). A real question menu appends synthetic rows the transcript never lists — `4. Type something.`, `5. Chat about this` — so an index taken from the transcript's option list can address the wrong row. The client sends the option label it showed the user; the daemon matches it against the rows on screen and refuses when no row matches, rather than pressing Enter on a guess.

- [ ] **Step 1: Write the failing test**

Append to `decision_test.go`:

```go
func TestAnswerNavigatesToTheVerifiedRowBeforeEnter(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"MENU:0", "MENU:1", "moved on"}
	m.menuReader = fakeMenuReader{rows: []string{"first", "second"}}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", [][]string{{"second"}}); err != nil {
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
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"idle"}
	m.menuReader = fakeMenuReader{noMenu: true}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	err := m.Answer(context.Background(), "s1", "q1", [][]string{{"first"}})
	if !errors.Is(err, ErrDialogAbsent) {
		t.Fatalf("expected ErrDialogAbsent, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestAnswerRejectsALabelThatIsNotOnScreen(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"MENU:0"}
	m.menuReader = fakeMenuReader{rows: []string{"first", "second"}}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", [][]string{{"nonexistent option"}}); err == nil {
		t.Fatal("expected a label with no matching row to be rejected")
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("expected no writes, got %q", rt.inputs)
	}
}

func TestAnswerRejectsAnEmptySelection(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"MENU:0"}
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
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	rt.panes = []string{"MENU:0", "MENU:0", "MENU:1", "MENU:1", "moved on"}
	m.menuReader = fakeMenuReader{rows: []string{"a", "b", "c"}, multi: " "}
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "q1", Kind: domain.InteractionQuestion})

	if err := m.Answer(context.Background(), "s1", "q1", [][]string{{"a", "c"}}); err != nil {
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
func (m *Manager) Answer(ctx context.Context, id domain.SessionID, interactionID string, selections [][]string) error {
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
	// Resolve every label to a row on screen BEFORE writing anything: a
	// half-answered question is worse than a refused one, and a label with no
	// matching row means the menu is not the one the client was looking at.
	resolved := make([][]int, 0, len(selections))
	for _, group := range selections {
		if len(group) == 0 {
			return fmt.Errorf("answer %s: empty selection group", id)
		}
		rows := make([]int, 0, len(group))
		for _, label := range group {
			row := indexOfRow(menu.Rows, label)
			if row < 0 {
				return fmt.Errorf("answer %s: option %q is not on screen", id, label)
			}
			rows = append(rows, row)
		}
		resolved = append(resolved, rows)
	}

	for _, group := range resolved {
		for i, row := range group {
			if err := driver.NavigateTo(ctx, readMenu, keys, row); err != nil {
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

Same error mapping as Task 9, plus `400 SESSION_ANSWER_INVALID` for an empty selection or a label that matches no row on screen.

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

## Task 16: Mirror the terminal's composer draft into the mobile composer

Reported on 2026-09-05 while this plan was being written. Half of that report was a
bug and is already fixed on `master` in `584d2ee07`: unmapped hooks
(`pre-tool-use`, `subagent-stop`, `session-end`) were persisted as `unknown` blocks
and the mobile assembler rendered any unrecognised kind as a chat notice, so a
`subagent-stop` payload carrying the composer draft appeared on the phone **as a
message from the agent**. Read that commit before starting — it is the reason
`kind: "unknown"` now renders nothing.

The other half is this task. The desktop TUI shows an unsent draft in its composer;
the phone shows nothing, because no channel carries the live composer contents to a
client. The draft belongs **in the mobile composer field**, not in the transcript.

**Files:**
- Modify: `backend/internal/adapters/agent/claudecode/dialog.go`, `dialog_test.go`
- Modify: `backend/internal/adapters/agent/codex/dialog.go`, `dialog_test.go`
- Modify: `backend/internal/ports/agent.go`
- Modify: `backend/internal/session_manager/command.go` (or a sibling `draft.go`)
- Modify: `backend/internal/httpd/controllers/sessions.go`, `dto.go`, `specgen/build.go`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart`

**Interfaces:**
- Consumes: `runtime.GetStyledOutput` (`ports.StyledTerminalOutputReader`), the readers from Tasks 4-5.
- Produces: `ports.TerminalComposerReader` with `ReadComposerDraft(styledPane string) (string, bool)`; `GET /api/v1/sessions/{sessionId}/draft` returning `{"draft": "..."}`.

### The one detail that decides whether this works

**A composer is never empty — it holds dim placeholder text when it has no draft.**
The captured fixtures show both states:

| fixture | composer line | is it a draft? |
|---|---|---|
| `claudecode_idle.txt` | `❯` + NBSP + `run the sample task` | **yes** — human-authored |
| `codex_idle.txt` | `› Improve documentation in @filename` | **no** — dim placeholder |

Plain `GetOutput` cannot tell these apart: both are just text on the prompt line.
The distinction lives in the SGR styling, which is exactly why
`ports.StyledTerminalOutputReader` exists — its doc comment already says it is
"for safety checks that must distinguish dim placeholder text from a
human-authored draft", and it instructs callers to **fail closed when
unavailable**. Do the same here: no styled reader, no draft.

Mirroring a placeholder into the phone's composer would put words in the user's
mouth — they tap send and dispatch text they never wrote. **Fail closed: when the
styling is ambiguous, report no draft.**

- [ ] **Step 1: Write the failing reader test**

Add to `claudecode/dialog_test.go`:

```go
func TestReadComposerDraftReturnsAHumanAuthoredDraft(t *testing.T) {
	p := &Plugin{}
	draft, ok := p.ReadComposerDraft(readStyledPane(t, "claudecode_idle_styled.txt"))
	if !ok {
		t.Fatal("expected the composer draft to be read")
	}
	if draft != "run the sample task" {
		t.Fatalf("draft = %q", draft)
	}
}

func TestReadComposerDraftRejectsDimPlaceholderText(t *testing.T) {
	// A placeholder mirrored into the phone's composer would have the user
	// send text they never wrote.
	p := &Plugin{}
	if draft, ok := p.ReadComposerDraft(readStyledPane(t, "claudecode_placeholder_styled.txt")); ok {
		t.Fatalf("placeholder text must not read as a draft, got %q", draft)
	}
}

func TestReadComposerDraftFailsClosedOnUnstyledInput(t *testing.T) {
	// Plain output carries no dim/normal distinction. Answering from it would
	// be a guess.
	p := &Plugin{}
	if _, ok := p.ReadComposerDraft(readPane(t, "claudecode_idle.txt")); ok {
		t.Fatal("an unstyled pane must fail closed, not guess")
	}
}
```

Mirror for `codex`, where `codex_idle_styled.txt` is the **placeholder** case —
`Improve documentation in @filename` must read as no draft.

- [ ] **Step 2: Capture the two styled fixtures this task needs**

The committed fixtures are plain. Capture styled ones with the reader from Task 4,
passing the `styled` argument, from a real session of each harness: one with a typed
draft, one with an empty composer showing its placeholder. Save as
`claudecode_idle_styled.txt`, `claudecode_placeholder_styled.txt`,
`codex_idle_styled.txt`. Scrub content, keep every escape sequence byte-for-byte —
**the escapes are the entire signal here**, so do not normalise or trim them.

Add `readStyledPane` beside `readPane`; it must not strip anything.

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd backend && go test ./internal/adapters/agent/claudecode/ ./internal/adapters/agent/codex/ -run TestReadComposerDraft -v
```

Expected: FAIL to compile — `p.ReadComposerDraft undefined`.

- [ ] **Step 4: Add the port and both readers**

```go
// TerminalComposerReader is an optional adapter capability for reading a
// harness's unsent composer draft. It takes STYLED pane text: a composer always
// holds something, and only the styling separates dim placeholder text from what
// the human actually typed. Implementations MUST fail closed — returning false
// when the styling does not clearly mark a draft — because the caller mirrors
// the result into another client's composer, where a wrong answer becomes a
// message the user never wrote.
type TerminalComposerReader interface {
	ReadComposerDraft(styledPane string) (string, bool)
}
```

Implement for both harnesses against the styled fixtures. Reuse the prompt-line
location logic from Task 4's `paneLines`; the difference here is that the escapes
must survive to be inspected.

- [ ] **Step 5: Add `GET /sessions/{sessionId}/draft`**

A read-only endpoint: resolve the harness's reader, take a styled pane read, return
`{"draft": "..."}` with an empty string when there is no draft. It never writes.
A harness with no reader returns an empty draft, not an error. Add the `specgen`
entry, then:

```bash
npm run api && git status --porcelain
```

**Polling, not streaming.** A draft changes on every keystroke and matters only
while someone is looking at the composer. Do not add it to the mux patch stream:
that would put per-keystroke traffic on the socket the Kanban board depends on.
The client fetches it when the blocks screen gains focus and after each send.

- [ ] **Step 6: Show it in the mobile composer**

`TerminalCubit` gains `draft` and fetches it on attach and after each send.
`TerminalComposer` shows a non-empty remote draft **only while its own field is
empty**, as dim prefill the user can tap to adopt — never overwriting text the
person on the phone is currently typing. Adopting it fills the field for editing;
it does not send.

Widget tests: a remote draft appears when the field is empty; it does **not**
appear when the user has typed something; tapping it fills the field without
sending; an empty remote draft shows nothing.

- [ ] **Step 7: Run the gates**

```bash
npm run lint
cd packages/mobile && flutter analyze && flutter test
```

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(mobile): mirror the terminal composer draft into the phone's composer"
```

---

## Task 17: Actionable permission and question blocks, then the final gates

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
- **Task 16 needs styled fixtures that do not exist yet.** The committed panes are plain; that task captures its own, and the ANSI escapes in them are the entire signal, so they must not be normalised.
- **Task 17 is last** and its live smoke test needs a human at the keyboard.
