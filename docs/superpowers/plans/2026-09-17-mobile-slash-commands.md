# Mobile Slash Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Slash commands typed on the phone are delivered without a false failure, echo as a bubble, and a `/` menu offers Claude Code's built-ins plus the user's own commands, skills and plugin skills.

**Architecture:** A leaf Go package `slashcommands` holds the built-in catalogue and `IsBuiltin`; the send path skips activity confirmation for built-ins and the send handler records a synthetic `prompt_submit` block. A discovery service scans the session's Claude config dir, workspace `.claude`, and installed plugins, served at `GET /sessions/{id}/slash-commands`. On the phone a `SlashMenuCubit` watches the composer controller and a `SlashCommandMenu` panel renders matches above the input.

**Tech Stack:** Go 1.2x (chi, `gopkg.in/yaml.v3`), Flutter 3.44.5 (`flutter_bloc` Cubit, mocktail, bloc_test).

**Spec:** `docs/superpowers/specs/2026-09-17-mobile-slash-commands-design.md`

## Global Constraints

- Daemon gate: `go test ./...`, `go vet ./...`, `gofmt -l` clean, and `go generate ./internal/httpd/apispec/` after any route change (parity test `internal/httpd/apispec/parity_test.go:22` fails otherwise).
- Mobile gate: `flutter analyze` → `No issues found!`, `flutter test` green, both from `packages/mobile`.
- Mobile conventions (`CLAUDE.md`): Cubit only; hand-written models with all-nullable fields, `fromJson` after the constructor; one params class per method; parameterized paths via static methods on `EndPoints`; no `flutter_screenutil` in feature code; inline English copy; `context.skin` for colours; `AppTextStyle.*` for type.
- No comments in code (user global rule), except where the surrounding file already carries a load-bearing comment that the change must update.
- Every task ends with a commit on `development`. Never touch `master`.
- Commit trailer: the `Co-Authored-By` line your session's attribution reminder gives; do not copy one from another session.

## File map

Daemon (`backend/`):

- Create `internal/slashcommands/builtin.go` — `Command`, `Builtin`, `IsBuiltin`.
- Create `internal/slashcommands/builtin_test.go`.
- Modify `internal/session_manager/manager.go:2326-2381` (`send`) — early return for built-ins.
- Modify `internal/session_manager/manager_test.go` — one new test next to `TestSend_SkipsConfirmForHooklessHarness` (line 6277).
- Modify `internal/httpd/controllers/sessions.go:1332-1366` (`send`) — synthetic block; add `SlashCommands` dep, `listSlashCommands` handler, route.
- Modify `internal/httpd/controllers/dto.go` — `SessionSlashCommandsResponse`, `SlashCommandView`.
- Create `internal/httpd/controllers/sessions_slash_commands_test.go`.
- Create `internal/service/slashcommands/service.go`, `service_test.go`.
- Modify `internal/httpd/api.go` — `APIDeps.SlashCommands`, wire into `SessionsController`.
- Modify `internal/httpd/apispec/specgen/build.go` — route entry; regenerate `openapi.yaml` and `frontend/src/api/schema.ts` (CI diffs it, `.github/workflows/go.yml:96`).
- Modify `internal/service/session/service.go:875` — map `ErrInteractiveSlashCommand` to `409 SLASH_COMMAND_INTERACTIVE`.
- Modify `internal/daemon/daemon.go:400-420` — construct the service.

Mobile (`packages/mobile/`):

- Create `lib/feature/terminal/data/model/slash_command_model.dart`.
- Modify `lib/core/api/api_request_helpers/end_points.dart` — `sessionSlashCommands`.
- Modify `lib/feature/terminal/data/data_source/terminal_remote_data_source.dart`, `lib/feature/terminal/data/repository/terminal_repository.dart`.
- Create `lib/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit.dart`, `slash_menu_state.dart`.
- Modify `lib/core/utils/service_locator.dart:207` (`_terminalFeatureSetup`), `lib/core/app_routes/app_router.dart:105-134`.
- Create `lib/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_menu.dart`, `slash_command_row.dart`.
- Modify `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart:120-126`.
- Modify `test/feature/terminal/terminal_harness.dart` and every test that mounts `TerminalComposer` directly (`terminal_composer_test.dart`, `terminal_dock_test.dart`) — provide a `SlashMenuCubit`.
- Create tests: `test/feature/terminal/data/model/slash_command_model_test.dart`, `test/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit_test.dart`, `test/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_menu_test.dart`.

---

### Task 1: Built-in catalogue and `IsBuiltin`

**Files:**
- Create: `backend/internal/slashcommands/builtin.go`
- Test: `backend/internal/slashcommands/builtin_test.go`

**Interfaces:**
- Produces: `slashcommands.Command{Name, Description, Source string; Interactive bool}`, `slashcommands.Builtin []Command`, `slashcommands.Lookup(message string) (Command, bool)`, `slashcommands.IsBuiltin(message string) bool`.

- [ ] **Step 1: Write the failing test**

```go
package slashcommands

import "testing"

func TestIsBuiltin(t *testing.T) {
	cases := []struct {
		message string
		want    bool
	}{
		{"/compact", true},
		{"/compact focus on the tests", true},
		{"  /compact  ", true},
		{"/clear\n", true},
		{"/sc:analyze", false},
		{"hello /compact", false},
		{"/", false},
		{"", false},
		{"/Compact", false},
		{"/compactor", false},
	}
	for _, tc := range cases {
		if got := IsBuiltin(tc.message); got != tc.want {
			t.Errorf("IsBuiltin(%q) = %v, want %v", tc.message, got, tc.want)
		}
	}
}

func TestLookupReturnsTheEntry(t *testing.T) {
	cmd, ok := Lookup("/model sonnet")
	if !ok || cmd.Name != "model" || !cmd.Interactive {
		t.Fatalf("Lookup(/model sonnet) = %+v, %v; want the interactive model entry", cmd, ok)
	}
	if _, ok := Lookup("/sc:analyze"); ok {
		t.Fatal("Lookup(/sc:analyze) matched a built-in")
	}
}

func TestBuiltinTableIsWellFormed(t *testing.T) {
	seen := map[string]bool{}
	for _, c := range Builtin {
		if c.Name == "" || c.Description == "" {
			t.Errorf("entry %+v is missing a name or description", c)
		}
		if c.Source != SourceBuiltin {
			t.Errorf("%s: source = %q, want %q", c.Name, c.Source, SourceBuiltin)
		}
		if seen[c.Name] {
			t.Errorf("%s listed twice", c.Name)
		}
		seen[c.Name] = true
	}
	for _, name := range []string{"compact", "clear", "model", "cost"} {
		if !seen[name] {
			t.Errorf("%s missing from Builtin", name)
		}
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/slashcommands/`
Expected: build failure, `undefined: IsBuiltin`.

- [ ] **Step 3: Write the package**

```go
package slashcommands

import "strings"

const (
	SourceBuiltin = "builtin"
	SourceUser    = "user"
	SourceProject = "project"
	SourcePlugin  = "plugin"
)

type Command struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Source      string `json:"source"`
	Interactive bool   `json:"interactive"`
}

var Builtin = []Command{
	{Name: "clear", Description: "Clear conversation history and free up context", Source: SourceBuiltin},
	{Name: "compact", Description: "Clear conversation history but keep a summary in context", Source: SourceBuiltin},
	{Name: "context", Description: "Show current context usage as a colored grid", Source: SourceBuiltin},
	{Name: "cost", Description: "Show the total cost and duration of the current session", Source: SourceBuiltin},
	{Name: "doctor", Description: "Diagnose and verify your Claude Code installation and settings", Source: SourceBuiltin},
	{Name: "export", Description: "Export the current conversation to a file or clipboard", Source: SourceBuiltin},
	{Name: "help", Description: "Show help and available commands", Source: SourceBuiltin},
	{Name: "init", Description: "Initialize a new CLAUDE.md file with codebase documentation", Source: SourceBuiltin},
	{Name: "pr-comments", Description: "Get comments from a GitHub pull request", Source: SourceBuiltin},
	{Name: "release-notes", Description: "View release notes", Source: SourceBuiltin},
	{Name: "review", Description: "Review a pull request", Source: SourceBuiltin},
	{Name: "security-review", Description: "Complete a security review of the pending changes on the current branch", Source: SourceBuiltin},
	{Name: "status", Description: "Show Claude Code status including version, model, account, API connectivity, and tool statuses", Source: SourceBuiltin},
	{Name: "usage", Description: "Show plan usage limits", Source: SourceBuiltin},
	{Name: "add-dir", Description: "Add a new working directory", Source: SourceBuiltin, Interactive: true},
	{Name: "agents", Description: "Manage agent configurations", Source: SourceBuiltin, Interactive: true},
	{Name: "bug", Description: "Submit feedback about Claude Code", Source: SourceBuiltin, Interactive: true},
	{Name: "config", Description: "Open config panel", Source: SourceBuiltin, Interactive: true},
	{Name: "exit", Description: "Exit the REPL", Source: SourceBuiltin, Interactive: true},
	{Name: "hooks", Description: "Manage hook configurations for tool events", Source: SourceBuiltin, Interactive: true},
	{Name: "ide", Description: "Manage IDE integrations and show status", Source: SourceBuiltin, Interactive: true},
	{Name: "login", Description: "Sign in with your Anthropic account", Source: SourceBuiltin, Interactive: true},
	{Name: "logout", Description: "Sign out from your Anthropic account", Source: SourceBuiltin, Interactive: true},
	{Name: "mcp", Description: "Manage MCP servers", Source: SourceBuiltin, Interactive: true},
	{Name: "memory", Description: "Edit Claude memory files", Source: SourceBuiltin, Interactive: true},
	{Name: "model", Description: "Set the AI model for Claude Code", Source: SourceBuiltin, Interactive: true},
	{Name: "permissions", Description: "Manage allow & deny tool permission rules", Source: SourceBuiltin, Interactive: true},
	{Name: "resume", Description: "Resume a conversation", Source: SourceBuiltin, Interactive: true},
	{Name: "rewind", Description: "Restore the code and/or conversation to a previous point", Source: SourceBuiltin, Interactive: true},
	{Name: "statusline", Description: "Set up Claude Code's status line UI", Source: SourceBuiltin, Interactive: true},
	{Name: "terminal-setup", Description: "Install Shift+Enter key binding for newlines", Source: SourceBuiltin, Interactive: true},
	{Name: "vim", Description: "Toggle between Vim and Normal editing modes", Source: SourceBuiltin, Interactive: true},
}

var builtinByName = func() map[string]Command {
	byName := make(map[string]Command, len(Builtin))
	for _, c := range Builtin {
		byName[c.Name] = c
	}
	return byName
}()

func Lookup(message string) (Command, bool) {
	fields := strings.Fields(message)
	if len(fields) == 0 || !strings.HasPrefix(fields[0], "/") {
		return Command{}, false
	}
	cmd, ok := builtinByName[fields[0][1:]]
	return cmd, ok
}

func IsBuiltin(message string) bool {
	_, ok := Lookup(message)
	return ok
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/slashcommands/ && go vet ./internal/slashcommands/ && gofmt -l internal/slashcommands`
Expected: `ok`, no vet output, no files listed.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/slashcommands
git commit -m "feat(daemon): built-in Claude Code slash command catalogue"
```

---

### Task 2: Send refuses interactive built-ins and skips confirmation for the rest

**Files:**
- Modify: `backend/internal/session_manager/manager.go:117-123` (errors), `manager.go:2326-2381` (`send`)
- Modify: `backend/internal/service/session/service.go:875` (error mapping)
- Test: `backend/internal/session_manager/manager_test.go` (add after `TestSend_SkipsConfirmForHooklessHarness`, line ~6297)

**Interfaces:**
- Consumes: `slashcommands.Lookup` / `IsBuiltin` from Task 1.
- Produces: `sessionmanager.ErrInteractiveSlashCommand`; `Manager.Send` returns it with no write for an interactive built-in, and returns `nil` after one write (no latest-prompt record, no nudges) for any other built-in.

- [ ] **Step 1: Write the failing test**

```go
func TestSend_BuiltinSlashCommandSkipsConfirm(t *testing.T) {
	st := newFakeStore()
	st.sessions["s1"] = domain.SessionRecord{ID: "s1", Harness: "claude-code",
		Activity: domain.Activity{State: domain.ActivityIdle}}
	msg := &fakeMessenger{}
	m := newSendTestManager(t, signalingAgent{}, msg, st)

	if err := m.Send(context.Background(), "s1", "/compact", nil); err != nil {
		t.Fatalf("Send: %v", err)
	}
	if len(msg.msgs) != 1 {
		t.Fatalf("Send calls = %d, want 1 (a built-in never fires the submit hook, so no nudges)", len(msg.msgs))
	}
	if msg.msgs[0] != "/compact" {
		t.Fatalf("delivered %q, want /compact", msg.msgs[0])
	}
	if got := st.sessions["s1"].Metadata.LatestUserPrompt; got != "" {
		t.Fatalf("LatestUserPrompt = %q, want untouched (a built-in is not task direction)", got)
	}
}

func TestSend_InteractiveBuiltinIsRefused(t *testing.T) {
	st := newFakeStore()
	st.sessions["s1"] = domain.SessionRecord{ID: "s1", Harness: "claude-code",
		Activity: domain.Activity{State: domain.ActivityIdle}}
	msg := &fakeMessenger{}
	m := newSendTestManager(t, signalingAgent{}, msg, st)

	err := m.Send(context.Background(), "s1", "/model sonnet", nil)
	if !errors.Is(err, ErrInteractiveSlashCommand) {
		t.Fatalf("Send err = %v, want ErrInteractiveSlashCommand", err)
	}
	if len(msg.msgs) != 0 {
		t.Fatalf("Send calls = %d, want 0 (nothing may reach the pane)", len(msg.msgs))
	}
}

func TestSend_CustomSlashCommandStillConfirms(t *testing.T) {
	st := newFakeStore()
	st.sessions["s1"] = domain.SessionRecord{ID: "s1", Harness: "claude-code",
		Activity: domain.Activity{State: domain.ActivityIdle}}
	msg := &fakeMessenger{}
	m := newSendTestManager(t, signalingAgent{}, msg, st)

	err := m.Send(context.Background(), "s1", "/sc:analyze", nil)
	if !errors.Is(err, ErrAgentNotResponding) {
		t.Fatalf("Send err = %v, want ErrAgentNotResponding (custom commands keep the confirmed path)", err)
	}
}
```

`fakeMessenger.msgs` is a `[]string` of delivered messages (`manager_test.go:832-840`) and `fakeStore.RecordSessionLatestUserPrompt` writes `Metadata.LatestUserPrompt` (`manager_test.go:73-81`).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/session_manager/ -run 'TestSend_BuiltinSlashCommandSkipsConfirm|TestSend_InteractiveBuiltinIsRefused|TestSend_CustomSlashCommandStillConfirms'`
Expected: the first fails with `Send err = session: agent did not accept the message` (or `Send calls = 3, want 1`), the second fails to compile (`undefined: ErrInteractiveSlashCommand`); the third passes.

- [ ] **Step 3: Refuse, skip the prompt record, skip confirmation**

In `manager.go`, next to `ErrAgentNotResponding` (line 123):

```go
	ErrInteractiveSlashCommand = errors.New("session: slash command opens a dialog on the desktop")
```

In `send`, right after `prepareOutboundMessage` returns:

```go
	builtin, isBuiltin := slashcommands.Lookup(message)
	if isBuiltin && builtin.Interactive {
		return fmt.Errorf("send %s: %w", id, ErrInteractiveSlashCommand)
	}
```

Change the `afterWrite` condition from `if strings.TrimSpace(message) != ""` to `if !isBuiltin && strings.TrimSpace(message) != ""`.

Immediately after the `switch outcome {...}` block and before the comment beginning `// confirmActive only helps`:

```go
	if isBuiltin {
		return nil
	}
```

Add the import `"github.com/OmarAly92/operator/backend/internal/slashcommands"`. Extend the existing comment above the `harnessNudgeSafe` gate with one sentence: `A built-in slash command (/compact, /clear, …) is handled by the TUI and never fires the prompt-submit hook, so confirmation could only ever time out; it returns as soon as the paste is written.`

In `service/session/service.go`, in the `switch` that maps manager errors (line ~875, next to `ErrAgentNotResponding`):

```go
	case errors.Is(err, sessionmanager.ErrInteractiveSlashCommand):
		return apierr.Conflict("SLASH_COMMAND_INTERACTIVE",
			"This command opens a dialog on the desktop; run it there", nil)
```

- [ ] **Step 4: Run the package tests**

Run: `cd backend && go test ./internal/session_manager/ ./internal/service/session/ && go vet ./internal/session_manager/ ./internal/service/session/`
Expected: `ok`.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/session_manager/manager.go backend/internal/session_manager/manager_test.go backend/internal/service/session/service.go
git commit -m "fix(daemon): deliver built-in slash commands without a submit hook; refuse interactive ones"
```

---

### Task 3: The send handler records a synthetic prompt block for built-ins

**Files:**
- Modify: `backend/internal/httpd/controllers/sessions.go:1332-1366`
- Test: `backend/internal/httpd/controllers/sessions_slash_commands_test.go` (create)

**Interfaces:**
- Consumes: `c.BlockEvents.Record(ctx, id, harness, ports.ActivitySignal)` (`sessions.go:131-133`), `c.Svc.Get`, `slashcommands.IsBuiltin`.
- Produces: one `user-prompt-submit` signal per successful built-in send on a `claude-code` session.

- [ ] **Step 1: Write the failing test**

```go
package controllers_test

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
)

func newSendWithBlocksServer(t *testing.T, svc *fakeSessionService, rec *fakeBlockEventRecorder) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{Sessions: svc, BlockEvents: rec}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestSendBuiltinSlashCommandRecordsPromptBlock(t *testing.T) {
	svc := newFakeSessionService()
	s := svc.sessions["opr-1"]
	s.Harness = "claude-code"
	svc.sessions["opr-1"] = s
	rec := &fakeBlockEventRecorder{}
	srv := newSendWithBlocksServer(t, svc, rec)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/send", `{"message":"/compact"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if rec.calls != 1 {
		t.Fatalf("Record calls = %d, want 1", rec.calls)
	}
	if rec.gotID != domain.SessionID("opr-1") || rec.gotHarness != "claude-code" {
		t.Fatalf("recorded for %s/%s, want opr-1/claude-code", rec.gotID, rec.gotHarness)
	}
	if rec.gotSignal.Event != "user-prompt-submit" || rec.gotSignal.LatestUserPrompt != "/compact" {
		t.Fatalf("signal = %+v, want user-prompt-submit carrying /compact", rec.gotSignal)
	}
}

func TestSendPlainMessageRecordsNoBlock(t *testing.T) {
	svc := newFakeSessionService()
	rec := &fakeBlockEventRecorder{}
	srv := newSendWithBlocksServer(t, svc, rec)

	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/send", `{"message":"hello"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if rec.calls != 0 {
		t.Fatalf("Record calls = %d, want 0 (the hook records ordinary prompts)", rec.calls)
	}
}

func TestSendBuiltinOnOtherHarnessRecordsNoBlock(t *testing.T) {
	svc := newFakeSessionService()
	s := svc.sessions["opr-1"]
	s.Harness = "codex"
	svc.sessions["opr-1"] = s
	rec := &fakeBlockEventRecorder{}
	srv := newSendWithBlocksServer(t, svc, rec)

	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/send", `{"message":"/compact"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if rec.calls != 0 {
		t.Fatalf("Record calls = %d, want 0 for a non-claude harness", rec.calls)
	}
}
```

`fakeBlockEventRecorder` already exists in `sessions_block_events_test.go:23`; `doRequest` in `projects_test.go:522`. Confirm `fakeSessionService.Send` stores the message and returns `f.sendErr` (`grep -n "func (f \*fakeSessionService) Send" -A 6 internal/httpd/controllers/sessions_test.go`).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/httpd/controllers/ -run 'TestSend.*Block'`
Expected: `TestSendBuiltinSlashCommandRecordsPromptBlock` fails with `Record calls = 0, want 1`; the other two pass.

- [ ] **Step 3: Record the block after a successful built-in send**

In `sessions.go` `send`, replace the tail from `if err := c.Svc.Send(...)` to the end of the function with:

```go
	if err := c.Svc.Send(r.Context(), sessionID(r), message, attachment); err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	c.recordBuiltinSlashPrompt(r, message)
	envelope.WriteJSON(w, http.StatusOK, SendSessionMessageResponse{OK: true, SessionID: sessionID(r), Message: message})
}

// recordBuiltinSlashPrompt writes the prompt block the UserPromptSubmit hook
// would have written for an ordinary message. Claude Code handles built-in
// slash commands itself and never fires that hook, so without this the phone
// and desktop timelines never show the command the user sent.
func (c *SessionsController) recordBuiltinSlashPrompt(r *http.Request, message string) {
	if c.BlockEvents == nil || !slashcommands.IsBuiltin(message) {
		return
	}
	sess, err := c.Svc.Get(r.Context(), sessionID(r))
	if err != nil || sess.Harness != domain.HarnessClaudeCode {
		return
	}
	harness := string(sess.Harness)
	sig := ports.ActivitySignal{
		Event:            "user-prompt-submit",
		Harness:          harness,
		LatestUserPrompt: message,
	}
	if err := c.BlockEvents.Record(r.Context(), sessionID(r), harness, sig); err != nil {
		slog.Default().Warn("slash prompt block recording failed", "session", sessionID(r), "err", err)
	}
}
```

Verify the constant name with `grep -n "HarnessClaudeCode" internal/domain/*.go`; if the domain constant is named differently, use that name. Add the `slashcommands` import.

- [ ] **Step 4: Run the controller tests**

Run: `cd backend && go test ./internal/httpd/controllers/ && go vet ./internal/httpd/controllers/`
Expected: `ok`.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/httpd/controllers/sessions.go backend/internal/httpd/controllers/sessions_slash_commands_test.go
git commit -m "feat(daemon): echo a built-in slash command as a prompt block"
```

---

### Task 4: Discovery service

**Files:**
- Create: `backend/internal/service/slashcommands/service.go`
- Test: `backend/internal/service/slashcommands/service_test.go`

**Interfaces:**
- Consumes: `slashcommands.Builtin`, `ports.AgentResolver` (`internal/ports/agent.go:268`), `ports.AgentNativeSessionConfigProvider` (`internal/ports/agent_continuation.go:52`), `domain.SessionRecord.Metadata.WorkspacePath`, `rec.ClaudeAccountID`.
- Produces: `slashcommandssvc.New(sessions SessionGetter, agents ports.AgentResolver, accounts ClaudeAccountEnv) *Service`; `(*Service).List(ctx, id domain.SessionID) ([]slashcommands.Command, error)`; `ErrSessionNotFound`.

- [ ] **Step 1: Write the failing test**

```go
package slashcommands_test

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	catalogue "github.com/OmarAly92/operator/backend/internal/slashcommands"
	svc "github.com/OmarAly92/operator/backend/internal/service/slashcommands"
)

type fakeSessions struct{ recs map[domain.SessionID]domain.SessionRecord }

func (f fakeSessions) GetSession(_ context.Context, id domain.SessionID) (domain.SessionRecord, bool, error) {
	rec, ok := f.recs[id]
	return rec, ok, nil
}

type fakeAccounts struct{ configDir string }

func (f fakeAccounts) EnvFor(context.Context, domain.ClaudeAccountID) (map[string]string, error) {
	return map[string]string{"CLAUDE_CONFIG_DIR": f.configDir}, nil
}

type configDirAgent struct{ ports.Agent }

func (configDirAgent) NativeSessionConfigDir(_ context.Context, env map[string]string) (string, error) {
	return env["CLAUDE_CONFIG_DIR"], nil
}

type fakeAgents struct{ agent ports.Agent }

func (f fakeAgents) Agent(h domain.AgentHarness) (ports.Agent, bool) {
	if h != "claude-code" {
		return nil, false
	}
	return f.agent, true
}

func write(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func fixture(t *testing.T) (configDir, workspace string) {
	t.Helper()
	root := t.TempDir()
	configDir = filepath.Join(root, "claude")
	workspace = filepath.Join(root, "ws")
	pluginDir := filepath.Join(root, "plugin-cache", "superpowers", "6.3.0")

	write(t, filepath.Join(configDir, "commands", "sc", "analyze.md"), "---\nname: analyze\ndescription: \"Comprehensive code analysis\"\n---\nbody\n")
	write(t, filepath.Join(configDir, "commands", "sc", "README.md"), "# not a command\n")
	write(t, filepath.Join(configDir, "commands", "zeta.md"), "no front matter\n")
	write(t, filepath.Join(configDir, "skills", "paseo", "SKILL.md"), "---\nname: paseo\ndescription: Paseo reference\n---\n")
	write(t, filepath.Join(workspace, ".claude", "skills", "bug-triage", "SKILL.md"), "---\ndescription: Triage bugs\n---\n")
	write(t, filepath.Join(workspace, ".claude", "commands", "deploy.md"), "---\ndescription: Deploy it\n---\n")
	write(t, filepath.Join(pluginDir, "skills", "brainstorming", "SKILL.md"), "---\ndescription: Brainstorm first\n---\n")
	write(t, filepath.Join(pluginDir, "commands", "review.md"), "---\ndescription: Plugin review\n---\n")
	disabledDir := filepath.Join(root, "plugin-cache", "disabled", "1.0.0")
	write(t, filepath.Join(disabledDir, "skills", "hidden", "SKILL.md"), "---\ndescription: installed but not enabled\n---\n")
	localDir := filepath.Join(root, "plugin-cache", "frontend-design", "unknown")
	write(t, filepath.Join(localDir, "skills", "frontend-design", "SKILL.md"), "---\ndescription: enabled for another project\n---\n")
	installed, _ := json.Marshal(map[string]any{
		"version": 2,
		"plugins": map[string]any{
			"superpowers@claude-plugins-official":     []map[string]any{{"installPath": pluginDir, "scope": "user"}},
			"disabled@claude-plugins-official":        []map[string]any{{"installPath": disabledDir, "scope": "user"}},
			"frontend-design@claude-plugins-official": []map[string]any{{"installPath": localDir, "scope": "local", "projectPath": filepath.Join(root, "elsewhere")}},
		},
	})
	write(t, filepath.Join(configDir, "plugins", "installed_plugins.json"), string(installed))
	settings, _ := json.Marshal(map[string]any{
		"enabledPlugins": map[string]any{
			"superpowers@claude-plugins-official":     true,
			"frontend-design@claude-plugins-official": true,
		},
	})
	write(t, filepath.Join(configDir, "settings.json"), string(settings))
	return configDir, workspace
}

func TestListDiscoversEverySource(t *testing.T) {
	configDir, workspace := fixture(t)
	sessions := fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{
		"s1": {ID: "s1", Harness: "claude-code", Metadata: domain.SessionMetadata{WorkspacePath: workspace}},
	}}
	s := svc.New(sessions, fakeAgents{agent: configDirAgent{}}, fakeAccounts{configDir: configDir})

	got, err := s.List(context.Background(), "s1")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) < len(catalogue.Builtin) {
		t.Fatalf("got %d commands, want at least the %d built-ins", len(got), len(catalogue.Builtin))
	}
	for i, b := range catalogue.Builtin {
		if got[i] != b {
			t.Fatalf("got[%d] = %+v, want built-in %+v in table order", i, got[i], b)
		}
	}
	rest := got[len(catalogue.Builtin):]
	want := []catalogue.Command{
		{Name: "bug-triage", Description: "Triage bugs", Source: "project"},
		{Name: "deploy", Description: "Deploy it", Source: "project"},
		{Name: "paseo", Description: "Paseo reference", Source: "user"},
		{Name: "sc:analyze", Description: "Comprehensive code analysis", Source: "user"},
		{Name: "superpowers:brainstorming", Description: "Brainstorm first", Source: "plugin"},
		{Name: "superpowers:review", Description: "Plugin review", Source: "plugin"},
		{Name: "zeta", Description: "", Source: "user"},
	}
	if len(rest) != len(want) {
		t.Fatalf("custom commands = %+v\nwant %+v", rest, want)
	}
	for i := range want {
		if rest[i] != want[i] {
			t.Errorf("rest[%d] = %+v, want %+v", i, rest[i], want[i])
		}
	}
}

func TestListDropsDuplicatesKeepingEarlierSource(t *testing.T) {
	configDir, workspace := fixture(t)
	write(t, filepath.Join(configDir, "commands", "compact.md"), "---\ndescription: shadows a built-in\n---\n")
	write(t, filepath.Join(workspace, ".claude", "commands", "paseo.md"), "---\ndescription: shadows a user skill\n---\n")
	sessions := fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{
		"s1": {ID: "s1", Harness: "claude-code", Metadata: domain.SessionMetadata{WorkspacePath: workspace}},
	}}
	s := svc.New(sessions, fakeAgents{agent: configDirAgent{}}, fakeAccounts{configDir: configDir})

	got, err := s.List(context.Background(), "s1")
	if err != nil {
		t.Fatal(err)
	}
	counts := map[string]int{}
	for _, c := range got {
		counts[c.Name]++
		if c.Name == "compact" && c.Source != "builtin" {
			t.Errorf("compact source = %q, want builtin", c.Source)
		}
		if c.Name == "paseo" && c.Source != "user" {
			t.Errorf("paseo source = %q, want user", c.Source)
		}
	}
	for name, n := range counts {
		if n != 1 {
			t.Errorf("%s listed %d times", name, n)
		}
	}
}

func TestListTakesALocalScopePluginOnlyInItsProject(t *testing.T) {
	configDir, workspace := fixture(t)
	elsewhere := filepath.Join(filepath.Dir(configDir), "elsewhere")
	sessions := fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{
		"s1": {ID: "s1", Harness: "claude-code", Metadata: domain.SessionMetadata{WorkspacePath: elsewhere}},
		"s2": {ID: "s2", Harness: "claude-code", Metadata: domain.SessionMetadata{WorkspacePath: workspace}},
	}}
	s := svc.New(sessions, fakeAgents{agent: configDirAgent{}}, fakeAccounts{configDir: configDir})

	has := func(id domain.SessionID, name string) bool {
		got, err := s.List(context.Background(), id)
		if err != nil {
			t.Fatal(err)
		}
		for _, c := range got {
			if c.Name == name {
				return true
			}
		}
		return false
	}
	if !has("s1", "frontend-design:frontend-design") {
		t.Error("the local-scope plugin is missing from the project it was installed for")
	}
	if has("s2", "frontend-design:frontend-design") {
		t.Error("the local-scope plugin leaked into another project")
	}
	if has("s1", "disabled:hidden") || has("s2", "disabled:hidden") {
		t.Error("a plugin without an enabledPlugins entry was listed")
	}
}

func TestListIsEmptyForOtherHarnesses(t *testing.T) {
	configDir, _ := fixture(t)
	sessions := fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{"s1": {ID: "s1", Harness: "codex"}}}
	s := svc.New(sessions, fakeAgents{agent: configDirAgent{}}, fakeAccounts{configDir: configDir})

	got, err := s.List(context.Background(), "s1")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Fatalf("got %d commands for codex, want 0", len(got))
	}
}

func TestListToleratesMissingFolders(t *testing.T) {
	sessions := fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{"s1": {ID: "s1", Harness: "claude-code"}}}
	s := svc.New(sessions, fakeAgents{agent: configDirAgent{}}, fakeAccounts{configDir: filepath.Join(t.TempDir(), "nope")})

	got, err := s.List(context.Background(), "s1")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != len(catalogue.Builtin) {
		t.Fatalf("got %d, want just the %d built-ins", len(got), len(catalogue.Builtin))
	}
}

func TestListUnknownSession(t *testing.T) {
	s := svc.New(fakeSessions{recs: map[domain.SessionID]domain.SessionRecord{}}, fakeAgents{}, fakeAccounts{})
	if _, err := s.List(context.Background(), "ghost"); err != svc.ErrSessionNotFound {
		t.Fatalf("err = %v, want ErrSessionNotFound", err)
	}
}
```

Check the metadata type name with `grep -n "Metadata " internal/domain/session.go` (the field is `Metadata` of type `SessionMetadata` or similar; use the real name).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/service/slashcommands/`
Expected: build failure, package does not exist.

- [ ] **Step 3: Write the service**

```go
package slashcommands

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/slashcommands"
)

var ErrSessionNotFound = errors.New("slash commands: session not found")

type SessionGetter interface {
	GetSession(ctx context.Context, id domain.SessionID) (domain.SessionRecord, bool, error)
}

type ClaudeAccountEnv interface {
	EnvFor(ctx context.Context, id domain.ClaudeAccountID) (map[string]string, error)
}

type Service struct {
	sessions SessionGetter
	agents   ports.AgentResolver
	accounts ClaudeAccountEnv
}

func New(sessions SessionGetter, agents ports.AgentResolver, accounts ClaudeAccountEnv) *Service {
	return &Service{sessions: sessions, agents: agents, accounts: accounts}
}

func (s *Service) List(ctx context.Context, id domain.SessionID) ([]slashcommands.Command, error) {
	rec, ok, err := s.sessions.GetSession(ctx, id)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrSessionNotFound
	}
	if rec.Harness != domain.HarnessClaudeCode {
		return []slashcommands.Command{}, nil
	}
	out := append([]slashcommands.Command{}, slashcommands.Builtin...)
	seen := map[string]struct{}{}
	for _, c := range out {
		seen[c.Name] = struct{}{}
	}

	var custom []slashcommands.Command
	add := func(cmds []slashcommands.Command) {
		for _, c := range cmds {
			if _, dup := seen[c.Name]; dup {
				continue
			}
			seen[c.Name] = struct{}{}
			custom = append(custom, c)
		}
	}

	if configDir := s.configDir(ctx, rec); configDir != "" {
		add(commandsIn(filepath.Join(configDir, "commands"), "", slashcommands.SourceUser))
		add(skillsIn(filepath.Join(configDir, "skills"), "", slashcommands.SourceUser))
		if ws := strings.TrimSpace(rec.Metadata.WorkspacePath); ws != "" {
			add(commandsIn(filepath.Join(ws, ".claude", "commands"), "", slashcommands.SourceProject))
			add(skillsIn(filepath.Join(ws, ".claude", "skills"), "", slashcommands.SourceProject))
		}
		for _, p := range installedPlugins(configDir, rec.Metadata.WorkspacePath) {
			add(skillsIn(filepath.Join(p.installPath, "skills"), p.name+":", slashcommands.SourcePlugin))
			add(commandsIn(filepath.Join(p.installPath, "commands"), p.name+":", slashcommands.SourcePlugin))
		}
	}
	sort.Slice(custom, func(i, j int) bool { return custom[i].Name < custom[j].Name })
	return append(out, custom...), nil
}

func (s *Service) configDir(ctx context.Context, rec domain.SessionRecord) string {
	if s.agents == nil {
		return ""
	}
	agent, found := s.agents.Agent(rec.Harness)
	if !found || agent == nil {
		return ""
	}
	provider, ok := agent.(ports.AgentNativeSessionConfigProvider)
	if !ok {
		return ""
	}
	env := map[string]string{}
	if s.accounts != nil {
		accountEnv, err := s.accounts.EnvFor(ctx, rec.ClaudeAccountID)
		if err != nil {
			return ""
		}
		env = accountEnv
	}
	dir, err := provider.NativeSessionConfigDir(ctx, env)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(dir)
}

func commandsIn(root, prefix, source string) []slashcommands.Command {
	var out []slashcommands.Command
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() || !strings.HasSuffix(path, ".md") || d.Name() == "README.md" {
			return nil
		}
		rel, relErr := filepath.Rel(root, path)
		if relErr != nil {
			return nil
		}
		name := strings.TrimSuffix(filepath.ToSlash(rel), ".md")
		name = strings.ReplaceAll(name, "/", ":")
		out = append(out, slashcommands.Command{
			Name:        prefix + name,
			Description: frontMatterDescription(path),
			Source:      source,
		})
		return nil
	})
	return out
}

func skillsIn(root, prefix, source string) []slashcommands.Command {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var out []slashcommands.Command
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		skill := filepath.Join(root, e.Name(), "SKILL.md")
		if _, statErr := os.Stat(skill); statErr != nil {
			continue
		}
		out = append(out, slashcommands.Command{
			Name:        prefix + e.Name(),
			Description: frontMatterDescription(skill),
			Source:      source,
		})
	}
	return out
}

type installedPlugin struct {
	name        string
	installPath string
}

func installedPlugins(configDir, workspace string) []installedPlugin {
	raw, err := os.ReadFile(filepath.Join(configDir, "plugins", "installed_plugins.json"))
	if err != nil {
		return nil
	}
	var file struct {
		Plugins map[string][]struct {
			Scope       string `json:"scope"`
			ProjectPath string `json:"projectPath"`
			InstallPath string `json:"installPath"`
		} `json:"plugins"`
	}
	if err := json.Unmarshal(raw, &file); err != nil {
		return nil
	}
	enabled := enabledPlugins(configDir)
	workspace = filepath.Clean(strings.TrimSpace(workspace))
	var out []installedPlugin
	for key, installs := range file.Plugins {
		if !enabled[key] {
			continue
		}
		name, _, _ := strings.Cut(key, "@")
		for _, in := range installs {
			if strings.TrimSpace(in.InstallPath) == "" {
				continue
			}
			if in.Scope != "user" && (workspace == "." || filepath.Clean(in.ProjectPath) != workspace) {
				continue
			}
			out = append(out, installedPlugin{name: name, installPath: in.InstallPath})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].name < out[j].name })
	return out
}

func enabledPlugins(configDir string) map[string]bool {
	raw, err := os.ReadFile(filepath.Join(configDir, "settings.json"))
	if err != nil {
		return nil
	}
	var file struct {
		EnabledPlugins map[string]bool `json:"enabledPlugins"`
	}
	if err := json.Unmarshal(raw, &file); err != nil {
		return nil
	}
	return file.EnabledPlugins
}

func frontMatterDescription(path string) string {
	raw, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	body := bytes.TrimLeft(raw, "\xef\xbb\xbf")
	if !bytes.HasPrefix(body, []byte("---")) {
		return ""
	}
	rest := body[3:]
	end := bytes.Index(rest, []byte("\n---"))
	if end < 0 {
		return ""
	}
	var fm struct {
		Description string `yaml:"description"`
	}
	if err := yaml.Unmarshal(rest[:end], &fm); err != nil {
		return ""
	}
	return strings.TrimSpace(fm.Description)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/service/slashcommands/ && go vet ./internal/service/slashcommands/ && gofmt -l internal/service/slashcommands`
Expected: `ok`.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/service/slashcommands
git commit -m "feat(daemon): discover a session's slash commands, skills and plugin skills"
```

---

### Task 5: Route, DTO, OpenAPI entry, wiring

**Files:**
- Modify: `backend/internal/httpd/controllers/sessions.go` (struct at 172-181, `Register` at 184-218, new handler near `listInteractions` ~1486)
- Modify: `backend/internal/httpd/controllers/dto.go` (append)
- Modify: `backend/internal/httpd/api.go:29-52` (`APIDeps`), `api.go:106-115`
- Modify: `backend/internal/httpd/apispec/specgen/build.go` (after the `listSessionInteractions` entry, line ~1667)
- Modify: `backend/internal/daemon/daemon.go:400-420`
- Test: `backend/internal/httpd/controllers/sessions_slash_commands_test.go` (append)

**Interfaces:**
- Consumes: `slashcommandssvc.Service.List` from Task 4.
- Produces: `GET /api/v1/sessions/{sessionId}/slash-commands` → `SessionSlashCommandsResponse{Commands []SlashCommandView}`; `controllers.SlashCommandLister` interface; `APIDeps.SlashCommands`.

- [ ] **Step 1: Write the failing test** (append to `sessions_slash_commands_test.go`)

```go
type fakeSlashCommandLister struct {
	commands []slashcommands.Command
	err      error
	gotID    domain.SessionID
}

func (f *fakeSlashCommandLister) List(_ context.Context, id domain.SessionID) ([]slashcommands.Command, error) {
	f.gotID = id
	return f.commands, f.err
}

func TestListSlashCommands(t *testing.T) {
	lister := &fakeSlashCommandLister{commands: []slashcommands.Command{
		{Name: "compact", Description: "Clear conversation history but keep a summary in context", Source: "builtin"},
		{Name: "model", Description: "Set the AI model for Claude Code", Source: "builtin", Interactive: true},
		{Name: "sc:analyze", Description: "Comprehensive code analysis", Source: "user"},
	}}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{Sessions: newFakeSessionService(), SlashCommands: lister}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/opr-1/slash-commands", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if lister.gotID != "opr-1" {
		t.Fatalf("listed %q, want opr-1", lister.gotID)
	}
	want := `{"commands":[` +
		`{"name":"compact","description":"Clear conversation history but keep a summary in context","source":"builtin","interactive":false},` +
		`{"name":"model","description":"Set the AI model for Claude Code","source":"builtin","interactive":true},` +
		`{"name":"sc:analyze","description":"Comprehensive code analysis","source":"user","interactive":false}]}`
	if strings.TrimSpace(string(body)) != want {
		t.Fatalf("body:\n got %s\nwant %s", body, want)
	}
}

func TestListSlashCommandsUnknownSession(t *testing.T) {
	lister := &fakeSlashCommandLister{err: slashcommandssvc.ErrSessionNotFound}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{Sessions: newFakeSessionService(), SlashCommands: lister}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/ghost/slash-commands", "")
	assertErrorCode(t, body, status, http.StatusNotFound, "SESSION_NOT_FOUND")
}

func TestListSlashCommandsNotWired(t *testing.T) {
	srv := newSessionTestServer(t, newFakeSessionService())
	_, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/opr-1/slash-commands", "")
	if status != http.StatusNotImplemented {
		t.Fatalf("status = %d, want 501 when the lister is nil", status)
	}
}
```

Add imports `context`, `strings`, `github.com/OmarAly92/operator/backend/internal/slashcommands`, and `slashcommandssvc "github.com/OmarAly92/operator/backend/internal/service/slashcommands"` to the test file.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/httpd/controllers/ -run TestListSlashCommands`
Expected: build failure, `deps.SlashCommands undefined`.

- [ ] **Step 3: DTO**

Append to `dto.go`:

```go
type SlashCommandView struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Source      string `json:"source"`
	Interactive bool   `json:"interactive"`
}

type SessionSlashCommandsResponse struct {
	Commands []SlashCommandView `json:"commands"`
}
```

- [ ] **Step 4: Controller**

In `sessions.go`, next to `InteractionReader` (line 146):

```go
type SlashCommandLister interface {
	List(ctx context.Context, sessionID domain.SessionID) ([]slashcommands.Command, error)
}
```

Add `SlashCommands SlashCommandLister` to `SessionsController`. In `Register`, after the `/interactions` line: `r.Get("/sessions/{sessionId}/slash-commands", c.listSlashCommands)`. Handler, placed after `listInteractions`:

```go
func (c *SessionsController) listSlashCommands(w http.ResponseWriter, r *http.Request) {
	if c.SlashCommands == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/sessions/{sessionId}/slash-commands")
		return
	}
	commands, err := c.SlashCommands.List(r.Context(), sessionID(r))
	if err != nil {
		if errors.Is(err, slashcommandssvc.ErrSessionNotFound) {
			envelope.WriteAPIError(w, r, http.StatusNotFound, "not_found", "SESSION_NOT_FOUND", "Unknown session", nil)
			return
		}
		envelope.WriteError(w, r, err)
		return
	}
	views := make([]SlashCommandView, 0, len(commands))
	for _, cmd := range commands {
		views = append(views, SlashCommandView{Name: cmd.Name, Description: cmd.Description, Source: cmd.Source, Interactive: cmd.Interactive})
	}
	envelope.WriteJSON(w, http.StatusOK, SessionSlashCommandsResponse{Commands: views})
}
```

Add the import `slashcommandssvc "github.com/OmarAly92/operator/backend/internal/service/slashcommands"`.

- [ ] **Step 5: API deps and daemon wiring**

`api.go`: add to `APIDeps` after `Interactions`:

```go
	// SlashCommands lists the slash commands a session's harness offers, for
	// the phone's composer menu. Nil answers 501.
	SlashCommands controllers.SlashCommandLister
```

and `SlashCommands: deps.SlashCommands,` in the `SessionsController` literal at `api.go:106-115`.

`daemon.go`: import `slashcommandssvc "github.com/OmarAly92/operator/backend/internal/service/slashcommands"` and, in the `APIDeps` literal near `Interactions: sessMgr,`, add `SlashCommands: slashcommandssvc.New(store, agents, claudeAccounts),`. `store`, `agents` and `claudeAccounts` are the same values passed to `transcriptsvc.NewResolver(agents, claudeAccounts)` at `daemon.go:483`; confirm `store` satisfies `GetSession(ctx, id) (domain.SessionRecord, bool, error)` (it is the manager's store, `manager.go:217`).

- [ ] **Step 6: OpenAPI entry and regeneration**

In `specgen/build.go`, after the `listSessionInteractions` route unit:

```go
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/slash-commands", id: "listSessionSlashCommands", tag: "sessions",
			summary:    "List the slash commands, skills and plugin skills available to a session",
			pathParams: []any{controllers.SessionIDParam{}},
			resps: []respUnit{
				{http.StatusOK, controllers.SessionSlashCommandsResponse{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
```

Run: `cd backend && go generate ./internal/httpd/apispec/ && cd ../frontend && npm run api:ts`
Expected: `openapi.yaml` gains the route and `frontend/src/api/schema.ts` gains `listSessionSlashCommands`; `git diff --stat` shows only those two files changed besides your edits. CI diffs `schema.ts` (`.github/workflows/go.yml:96`), so it must be committed with the route.

- [ ] **Step 7: Full daemon gate**

Run: `cd backend && gofmt -l internal && go vet ./... && go test ./...`
Expected: no gofmt output, vet clean, all packages `ok` (parity test included).

- [ ] **Step 8: Commit**

```bash
git add backend/internal/httpd backend/internal/daemon/daemon.go frontend/src/api/schema.ts
git commit -m "feat(daemon): GET /sessions/{id}/slash-commands"
```

---

### Task 6: Mobile data layer

**Files:**
- Create: `packages/mobile/lib/feature/terminal/data/model/slash_command_model.dart`
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart` (after `sessionDraft`, line ~40)
- Modify: `packages/mobile/lib/feature/terminal/data/data_source/terminal_remote_data_source.dart`
- Modify: `packages/mobile/lib/feature/terminal/data/repository/terminal_repository.dart`
- Test: `packages/mobile/test/feature/terminal/data/model/slash_command_model_test.dart`

**Interfaces:**
- Produces: `SlashCommandModel{String? name, String? description, String? source, bool? interactive}` with `fromJson` and `static List<SlashCommandModel> listFromJson(Map<String, dynamic>)`; `EndPoints.sessionSlashCommands(String)`; `TerminalRemoteDataSource.getSlashCommands(String sessionId) → Future<GlobalResponse<List<SlashCommandModel>>>`; `TerminalRepository.getSlashCommands(String sessionId) → FutureResult<GlobalResponse<List<SlashCommandModel>>>`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/data/model/slash_command_model.dart';

void main() {
  test('listFromJson reads the commands envelope', () {
    final list = SlashCommandModel.listFromJson({
      'commands': [
        {'name': 'compact', 'description': 'Keep a summary', 'source': 'builtin', 'interactive': false},
        {'name': 'model', 'description': 'Pick a model', 'source': 'builtin', 'interactive': true},
        {'name': 'sc:analyze', 'description': 'Analyze', 'source': 'user'},
      ],
    });

    expect(list, hasLength(3));
    expect(list[0], const SlashCommandModel(name: 'compact', description: 'Keep a summary', source: 'builtin', interactive: false));
    expect(list[1].interactive, isTrue);
    expect(list[2].interactive, isNull);
  });

  test('a missing commands key is an empty list', () {
    expect(SlashCommandModel.listFromJson({}), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/terminal/data/model/slash_command_model_test.dart`
Expected: compile error, `slash_command_model.dart` not found.

- [ ] **Step 3: Model**

```dart
import 'package:equatable/equatable.dart';

class SlashCommandModel extends Equatable {
  final String? name;
  final String? description;
  final String? source;
  final bool? interactive;

  const SlashCommandModel({this.name, this.description, this.source, this.interactive});

  factory SlashCommandModel.fromJson(Map<String, dynamic> json) => SlashCommandModel(
    name: json['name'] as String?,
    description: json['description'] as String?,
    source: json['source'] as String?,
    interactive: json['interactive'] as bool?,
  );

  static List<SlashCommandModel> listFromJson(Map<String, dynamic> json) =>
      (json['commands'] as List<dynamic>? ?? [])
          .map((item) => SlashCommandModel.fromJson(item as Map<String, dynamic>))
          .toList();

  @override
  List<Object?> get props => [name, description, source, interactive];
}
```

- [ ] **Step 4: Endpoint, data source, repository**

`end_points.dart`, after `sessionDraft`:

```dart
  static String sessionSlashCommands(String sessionId) => '${_session(sessionId)}/slash-commands';
```

`terminal_remote_data_source.dart`: add to the abstract class

```dart
  Future<GlobalResponse<List<SlashCommandModel>>> getSlashCommands(String sessionId);
```

and to the `Imp`:

```dart
  @override
  Future<GlobalResponse<List<SlashCommandModel>>> getSlashCommands(String sessionId) async {
    final response = await _apiConsumer.get(EndPoints.sessionSlashCommands(sessionId));
    return GlobalResponse<List<SlashCommandModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: SlashCommandModel.listFromJson,
    );
  }
```

`terminal_repository.dart`: add to the abstract class

```dart
  FutureResult<GlobalResponse<List<SlashCommandModel>>> getSlashCommands(String sessionId);
```

and to the `Imp`, next to `getDraft` (which uses the file's `_guard` helper at line 58):

```dart
  @override
  FutureResult<GlobalResponse<List<SlashCommandModel>>> getSlashCommands(String sessionId) =>
      _guard(() => _remoteDataSource.getSlashCommands(sessionId));
```

Import the model in both files. Any test fake implementing `TerminalRemoteDataSource` or `TerminalRepository` by hand (not via `Mock`) now needs the method — `grep -rn "implements TerminalRepository\|implements TerminalRemoteDataSource" test` and add a `throw UnimplementedError()` body where a class is not a mocktail `Mock`.

- [ ] **Step 5: Gate**

Run: `cd packages/mobile && flutter analyze && flutter test test/feature/terminal`
Expected: `No issues found!`, tests pass.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): slash command model, endpoint, data source and repository"
```

---

### Task 7: `SlashMenuCubit`

**Files:**
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/slash_menu_state.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart:207` (`_terminalFeatureSetup`)
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart:110-131`
- Test: `packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit_test.dart`

**Interfaces:**
- Consumes: `TerminalRepository.getSlashCommands` (Task 6).
- Produces: `SlashMenuCubit(TerminalRepository, TextEditingController composer, {required String sessionId})` with fields `commands`, `matches`, `query`, `bool get open`, methods `getSlashCommands()`, `pick(SlashCommandModel)`; states `SlashMenuInitialState`, `GetSlashCommandsLoadingState`, `GetSlashCommandsSuccessState`, `GetSlashCommandsFailureState(failure)`, `SlashMenuChangedState(open, matches)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/terminal/data/model/slash_command_model.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit.dart';

class _MockTerminalRepository extends Mock implements TerminalRepository {}

const _commands = [
  SlashCommandModel(name: 'compact', description: 'Keep a summary', source: 'builtin', interactive: false),
  SlashCommandModel(name: 'context', description: 'Context grid', source: 'builtin', interactive: false),
  SlashCommandModel(name: 'model', description: 'Pick a model', source: 'builtin', interactive: true),
  SlashCommandModel(name: 'sc:analyze', description: 'Analyze', source: 'user', interactive: false),
];

void main() {
  late _MockTerminalRepository repository;
  late TextEditingController composer;

  setUp(() {
    repository = _MockTerminalRepository();
    composer = TextEditingController();
    when(() => repository.getSlashCommands(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse<List<SlashCommandModel>>(data: _commands)),
    );
  });

  tearDown(() => composer.dispose());

  SlashMenuCubit build() => SlashMenuCubit(repository, composer, sessionId: 's-1');

  blocTest<SlashMenuCubit, SlashMenuState>(
    'loads the session commands and drops interactive ones',
    build: build,
    expect: () => [isA<GetSlashCommandsSuccessState>()],
    verify: (cubit) {
      expect(cubit.commands.map((c) => c.name), ['compact', 'context', 'sc:analyze']);
      expect(cubit.open, isFalse);
    },
  );

  blocTest<SlashMenuCubit, SlashMenuState>(
    'opens on a leading slash and filters by prefix',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      composer.text = '/';
      composer.text = '/co';
    },
    skip: 1,
    expect: () => [
      const SlashMenuChangedState(open: true, matches: [_commands[0], _commands[1], _commands[3]]),
      const SlashMenuChangedState(open: true, matches: [_commands[0], _commands[1]]),
    ],
  );

  blocTest<SlashMenuCubit, SlashMenuState>(
    'falls back to a contains match when nothing starts with the query',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      composer.text = '/analy';
    },
    skip: 1,
    expect: () => [
      const SlashMenuChangedState(open: true, matches: [_commands[3]]),
    ],
  );

  blocTest<SlashMenuCubit, SlashMenuState>(
    'closes once the command is followed by whitespace or the slash is gone',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      composer.text = '/compact';
      composer.text = '/compact ';
      composer.text = 'plain text';
    },
    skip: 1,
    expect: () => [
      const SlashMenuChangedState(open: true, matches: [_commands[0]]),
      const SlashMenuChangedState(open: false, matches: []),
    ],
  );

  blocTest<SlashMenuCubit, SlashMenuState>(
    'pick fills the composer with the command and a trailing space',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      composer.text = '/co';
      cubit.pick(_commands[1]);
    },
    verify: (cubit) {
      expect(composer.text, '/context ');
      expect(composer.selection.baseOffset, '/context '.length);
      expect(cubit.open, isFalse);
    },
  );

  blocTest<SlashMenuCubit, SlashMenuState>(
    'a failed fetch leaves the menu closed for good',
    build: () {
      when(() => repository.getSlashCommands(any())).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'old daemon', statusCode: 501)),
      );
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      composer.text = '/';
    },
    expect: () => [isA<GetSlashCommandsFailureState>()],
    verify: (cubit) => expect(cubit.open, isFalse),
  );
}
```

The constructor starts the fetch, as every other cubit in this package does (`BlocksCubit`, `SessionCommandCubit`, `SessionsCubit`). `blocTest` subscribes after `build()` returns, so the synchronous `GetSlashCommandsLoadingState` emitted inside the constructor is never observed; the `GetSlashCommandsSuccessState` (or failure) that follows the `await` is. Hence the first test expects only the success state and the others `skip: 1` and `await Future<void>.delayed(Duration.zero)` in `act` so the fetch has landed before the composer is edited. `GlobalResponse` has a `const` constructor with named parameters (`global_response.dart:10`); check that `data:` is among them.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit_test.dart`
Expected: compile error, `slash_menu_cubit.dart` not found.

- [ ] **Step 3: State**

`slash_menu_state.dart`:

```dart
part of 'slash_menu_cubit.dart';

sealed class SlashMenuState extends Equatable {
  const SlashMenuState();

  @override
  List<Object?> get props => [];
}

final class SlashMenuInitialState extends SlashMenuState {
  const SlashMenuInitialState();
}

final class GetSlashCommandsLoadingState extends SlashMenuState {
  const GetSlashCommandsLoadingState();
}

final class GetSlashCommandsSuccessState extends SlashMenuState {
  const GetSlashCommandsSuccessState();
}

final class GetSlashCommandsFailureState extends SlashMenuState {
  const GetSlashCommandsFailureState({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

final class SlashMenuChangedState extends SlashMenuState {
  const SlashMenuChangedState({required this.open, required this.matches});

  final bool open;
  final List<SlashCommandModel> matches;

  @override
  List<Object?> get props => [open, matches];
}
```

- [ ] **Step 4: Cubit**

`slash_menu_cubit.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/terminal/data/model/slash_command_model.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';

part 'slash_menu_state.dart';

class SlashMenuCubit extends Cubit<SlashMenuState> {
  SlashMenuCubit(this._repository, this.composer, {required this.sessionId}) : super(const SlashMenuInitialState()) {
    composer.addListener(_onComposerChanged);
    getSlashCommands();
  }

  final TerminalRepository _repository;
  final TextEditingController composer;
  final String sessionId;

  List<SlashCommandModel> commands = const [];
  List<SlashCommandModel> matches = const [];
  String query = '';
  bool open = false;

  Future<void> getSlashCommands() async {
    emit(const GetSlashCommandsLoadingState());
    final result = await _repository.getSlashCommands(sessionId);
    if (isClosed) return;
    result.when(
      onSuccess: (response) {
        commands = (response.data ?? const [])
            .where((command) => command.interactive != true && (command.name ?? '').isNotEmpty)
            .toList();
        emit(const GetSlashCommandsSuccessState());
        _onComposerChanged();
      },
      onFailure: (failure) => emit(GetSlashCommandsFailureState(failure: failure)),
    );
  }

  void pick(SlashCommandModel command) {
    final text = '/${command.name} ';
    composer.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  void _onComposerChanged() {
    final text = composer.text;
    final isCommandPrefix = text.startsWith('/') && !text.contains(RegExp(r'\s'));
    final nextQuery = isCommandPrefix ? text.substring(1).toLowerCase() : '';
    final nextMatches = isCommandPrefix ? _match(nextQuery) : const <SlashCommandModel>[];
    final nextOpen = isCommandPrefix && nextMatches.isNotEmpty;
    if (nextOpen == open && nextQuery == query && _sameList(nextMatches, matches)) return;
    query = nextQuery;
    matches = nextMatches;
    open = nextOpen;
    if (!isClosed) emit(SlashMenuChangedState(open: open, matches: matches));
  }

  List<SlashCommandModel> _match(String q) {
    if (q.isEmpty) return commands;
    final byPrefix = commands.where((c) => c.name!.toLowerCase().startsWith(q)).toList();
    if (byPrefix.isNotEmpty) return byPrefix;
    return commands.where((c) => c.name!.toLowerCase().contains(q)).toList();
  }

  bool _sameList(List<SlashCommandModel> a, List<SlashCommandModel> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Future<void> close() {
    composer.removeListener(_onComposerChanged);
    return super.close();
  }
}
```

The cubit does not dispose `composer`: `TerminalCubit` owns it (`terminal_cubit.dart:97,329`).

- [ ] **Step 5: Run the cubit test**

Run: `cd packages/mobile && flutter test test/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit_test.dart`
Expected: all pass. If the "closes" test sees an extra `SlashMenuChangedState(open: false, matches: [])` for `'plain text'`, that is the dedupe guard failing — the `_sameList`/`open`/`query` comparison above suppresses it; fix the guard rather than the test.

- [ ] **Step 6: DI and route**

`service_locator.dart` inside `_terminalFeatureSetup`:

```dart
    sl.registerFactoryParam<SlashMenuCubit, TextEditingController, String>(
      (composer, sessionId) => SlashMenuCubit(sl<TerminalRepository>(), composer, sessionId: sessionId),
    );
```

(import `package:flutter/widgets.dart` if the file does not already import a Flutter library, plus the cubit.)

`app_router.dart` terminal route, add to the `providers` list after the `BlocksCubit` entry:

```dart
              if (!terminalArgs.shellOnly)
                BlocProvider<SlashMenuCubit>(
                  create: (context) => sl<SlashMenuCubit>(
                    param1: context.read<TerminalCubit>().composer,
                    param2: terminalArgs.sessionId,
                  ),
                ),
```

`MultiBlocProvider` nests providers in order, so `context.read<TerminalCubit>()` inside a later `create` resolves the one above it.

- [ ] **Step 7: Gate**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: clean and green.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): SlashMenuCubit watches the composer for slash commands"
```

---

### Task 8: Menu UI in the composer

**Files:**
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_menu.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_row.dart`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart:122-126`
- Test: `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_menu_test.dart`

**Interfaces:**
- Consumes: `SlashMenuCubit` (`open`, `matches`, `pick`, `SlashMenuChangedState`) from Task 7; `context.skin`, `AppTextStyle`, `AppText`, `AppInkWell` (`core/widgets/main_widgets/app_ink_well.dart`), `Haptics.select()` (`core/utils/haptics.dart:12`).
- Produces: `SlashCommandMenu()` and `SlashCommandRow({name, description, source, onTap})`.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/terminal/data/model/slash_command_model.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_menu.dart';

class _MockSlashMenuCubit extends MockCubit<SlashMenuState> implements SlashMenuCubit {}

const _compact = SlashCommandModel(name: 'compact', description: 'Keep a summary', source: 'builtin');
const _analyze = SlashCommandModel(name: 'sc:analyze', description: 'Analyze', source: 'user');

Widget _host(SlashMenuCubit cubit) => SkinScope(
  skin: const DarkSkin(),
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(
      home: Scaffold(body: BlocProvider<SlashMenuCubit>.value(value: cubit, child: const SlashCommandMenu())),
    ),
  ),
);

void main() {
  testWidgets('renders nothing while closed', (tester) async {
    final cubit = _MockSlashMenuCubit();
    when(() => cubit.state).thenReturn(const SlashMenuChangedState(open: false, matches: []));
    when(() => cubit.open).thenReturn(false);
    when(() => cubit.matches).thenReturn(const []);

    await tester.pumpWidget(_host(cubit));

    expect(find.text('/compact'), findsNothing);
  });

  testWidgets('lists matches and picks on tap', (tester) async {
    final cubit = _MockSlashMenuCubit();
    when(() => cubit.state).thenReturn(const SlashMenuChangedState(open: true, matches: [_compact, _analyze]));
    when(() => cubit.open).thenReturn(true);
    when(() => cubit.matches).thenReturn(const [_compact, _analyze]);

    await tester.pumpWidget(_host(cubit));

    expect(find.text('/compact'), findsOneWidget);
    expect(find.text('Keep a summary'), findsOneWidget);
    expect(find.text('/sc:analyze'), findsOneWidget);
    expect(find.text('user'), findsOneWidget);
    expect(find.text('builtin'), findsNothing);

    await tester.tap(find.text('/sc:analyze'));
    verify(() => cubit.pick(_analyze)).called(1);
  });
}
```

`MockCubit` comes from `bloc_test`; import it if `mocktail` alone does not provide it (`import 'package:bloc_test/bloc_test.dart';`).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_menu_test.dart`
Expected: compile error, `slash_command_menu.dart` not found.

- [ ] **Step 3: Row widget**

`slash_command_row.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class SlashCommandRow extends StatelessWidget {
  const SlashCommandRow({
    super.key,
    required this.name,
    required this.description,
    required this.source,
    required this.onTap,
  });

  final String name;
  final String description;
  final String source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return AppInkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText('/$name', style: AppTextStyle.mono12Regular.copyWith(color: skin.textPrimary)),
                  if (description.isNotEmpty)
                    AppText(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
                    ),
                ],
              ),
            ),
            if (source != 'builtin') ...[
              const HorizontalSpace(8),
              AppText(source, style: AppTextStyle.style10Regular.copyWith(color: skin.textFaint)),
            ],
          ],
        ),
      ),
    );
  }
}
```

Check `AppInkWell`'s constructor (`cat lib/core/widgets/main_widgets/app_ink_well.dart`) and `AppText`'s `maxLines`/`overflow` parameters (`grep -n "maxLines\|overflow" lib/core/widgets/main_widgets/app_text.dart`); if `AppText` lacks them, pass them the way `block_card.dart` does for its single-line summaries. If `AppInkWell` has a different `onTap` parameter name, match it. Verify `skin.textFaint` exists (`grep -n textFaint lib/core/app_themes/colors/app_skin.dart`); otherwise use `skin.textTertiary`.

- [ ] **Step 4: Menu widget**

`slash_command_menu.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_row.dart';

const int _kMaxVisibleRows = 6;

class SlashCommandMenu extends StatelessWidget {
  const SlashCommandMenu({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<SlashMenuCubit, SlashMenuState>(
    buildWhen: (previous, current) => current is SlashMenuChangedState,
    builder: (context, state) {
      final cubit = context.read<SlashMenuCubit>();
      if (!cubit.open) return const SizedBox.shrink();
      final skin = context.skin;
      final rows = cubit.matches.take(_kMaxVisibleRows).toList();
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Container(
          decoration: BoxDecoration(
            color: skin.bgElevated,
            border: Border.all(color: skin.borderDefault),
            borderRadius: BorderRadius.circular(11),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final command in rows)
                SlashCommandRow(
                  name: command.name ?? '',
                  description: command.description ?? '',
                  source: command.source ?? '',
                  onTap: () {
                    Haptics.select();
                    cubit.pick(command);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}
```

- [ ] **Step 5: Mount it in the composer**

In `terminal_composer.dart`, inside the `Column` children, insert between `const VoiceStrip(),` and the `BlocBuilder<TerminalCubit, TerminalState>(`:

```dart
          if (!cubit.args.shellOnly) const SlashCommandMenu(),
```

(`cubit` is the `TerminalCubit` already read at the top of `build`; confirm the variable name at `terminal_composer.dart:~110`.) Import the menu.

- [ ] **Step 6: Provide the cubit to the existing composer tests**

`TerminalComposer` now reads `SlashMenuCubit`, so every test that mounts it without the route fails with `Could not find the correct Provider<SlashMenuCubit>`. Known mounts: `test/feature/terminal/terminal_harness.dart:189-195` (`MultiBlocProvider`), `test/feature/terminal/presentation/terminal_screen/ui/terminal_composer_test.dart`, `test/feature/terminal/presentation/terminal_screen/ui/terminal_dock_test.dart`; confirm with `grep -rln "TerminalComposer(" test`. In each, add a `BlocProvider<SlashMenuCubit>.value` over a real `SlashMenuCubit(mockRepository, cubit.composer, sessionId: ...)` whose `getSlashCommands` is never called (the menu stays closed and no stub is needed), and close it in the test's teardown / the harness's `dispose()`.

- [ ] **Step 7: Run the widget test, then the whole suite**

Run: `cd packages/mobile && flutter test test/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_menu_test.dart && flutter analyze && flutter test`
Expected: all green, `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): slash command menu above the composer"
```

---

### Task 9: Real-device verification

**Files:** none (verification only; any fix is its own commit).

- [ ] **Step 1: Run the dev daemon and pair the phone**

From the repo root in a shell without `CLAUDE*` variables (`env | grep ^CLAUDE` must print nothing): `npm run tauri:dev`. Re-pair the phone via Connect Mobile.

- [ ] **Step 2: Menu contents**

Open a `claude-code` session, focus the composer, type `/`. Expected: a panel above the field listing `/clear`, `/compact`, … then the user's own entries (`/sc:analyze`, `/paseo`, `/bug-triage` (project), `/superpowers:brainstorming` (plugin)). Type `co`: only `/compact`, `/context`, `/cost`. Type `analy`: only `/sc:analyze`.

- [ ] **Step 3: Built-in send**

Tap `/compact`, then Send. Expected: no red banner; the field clears; a `/compact` bubble appears in the conversation; the `CONVERSATION COMPACTED (MANUAL)` divider follows. On the desktop the block timeline shows the same `/compact` prompt block.

- [ ] **Step 4: Interactive refusal**

Type `/model` by hand (the menu hides it) and Send. Expected: the red banner reads `Send failed: This command opens a dialog on the desktop; run it there`, the text stays in the field, and the desktop TUI never opens the picker.

- [ ] **Step 5: Custom command send**

Send `/sc:analyze`. Expected: either a normal turn starts (bubble via the hook, no banner) — done — or the phone shows `Send failed: The agent did not accept the message…`. In the second case, widen the gate: in `slashcommands`, add `func IsSlashCommand(message string) bool` (first token starts with `/`, length > 1) with a test, use it for the `afterWrite` skip and the early return in `manager.go` `send` (the interactive refusal keeps using `Lookup`) and in `recordBuiltinSlashPrompt` (rename to `recordSlashPrompt`), update §4.2/§4.3 of the spec with the finding, and commit as `fix(daemon): treat every slash command as hookless`.

- [ ] **Step 6: `/doctor` and `/export`**

Send each from the phone and watch the desktop TUI. Expected: output prints and the prompt returns. If either parks the TUI in a dialog, flip its `Interactive` flag in `builtin.go`, run `go test ./internal/slashcommands/`, commit as `fix(daemon): mark /<name> interactive`.

- [ ] **Step 7: Record the verdict**

Append a dated line to `docs/mobile-chat-bugs.md` (create the section `## Slash commands` if absent) stating which of steps 3–6 passed and any widening applied, and commit as `docs: slash command verification 2026-09-17`.

## Self-review

- **Spec coverage:** §4.1 → Task 1; §4.2 → Task 2; §4.3 → Task 3; §4.4 → Tasks 4–5; §5.1 → Task 6; §5.2 → Task 7; §5.3 → Task 8; §5.4 needs no task; §6 tests are embedded per task; §7 → Task 9.
- **Placeholder scan:** none; every code step carries the code. Two "check the real name" instructions (`HarnessClaudeCode`, `SessionMetadata`, `AppInkWell` params) are lookups the executor performs, with the fallback stated.
- **Type consistency:** `slashcommands.Command` fields (`Name`, `Description`, `Source`, `Interactive`) match the DTO, the JSON golden, `SlashCommandModel`, and the test fixtures; `SlashMenuCubit` members (`commands`, `matches`, `query`, `open`, `pick`, `getSlashCommands`) match Task 8's reads and the tests; `SlashMenuChangedState(open:, matches:)` matches in Tasks 7 and 8; `SlashCommandLister.List(ctx, id)` matches the fake in Task 5 and the service in Task 4; `installedPlugins(configDir, workspace)` matches its call in `List`.
