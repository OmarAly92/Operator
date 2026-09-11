# Orchestrator Eyes (Phase 0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a worker's task brief, last user prompt, last assistant message and PR/CI state readable from `opr`, so an orchestrator (and the human) can tell what a session is doing instead of only whether it is active or idle.

**Architecture:** Pure read surface over data already persisted. `SessionView` is the HTTP wire shape that already lifts `json:"-"` fields off `domain.Session.Metadata`; three more fields join it there. The CLI's hand-mirrored `sessionDTO` gains the same fields and renders them. `opr board` is a new CLI command over the **existing** `GET /sessions?project=&active=true` route — no new endpoint, controller, or service method. Finally the orchestrator prompt stops claiming `opr status` shows work state.

**Tech Stack:** Go 1.x, Cobra CLI, chi router, code-first OpenAPI (`npm run api`), table-driven Go tests with `httptest`.

**Spec:** `docs/superpowers/specs/2026-09-11-autonomous-orchestrator-design.md` (§5.2 digest, §5.3 board, §8 wire surface, §9 prompt, §14 Phase 0)

## Global Constraints

- **Precondition:** the conversation-facts ingest fix must be present — commit `fix(hooks): only turn-boundary events may set conversation facts`, branch `fix/hook-conversation-facts-event-gate`. Without it `latestAssistantUpdate` holds a Claude Code sidechain prompt suggestion, not the worker's reply, and this whole phase surfaces corrupt data. Verify with `git log --oneline --all | grep "only turn-boundary events"` before starting.
- **No comments in new code.** The user's standing instruction. Names and tests carry the intent.
- The CLI is a thin client: it calls daemon HTTP through the shared helpers and never opens SQLite, spawns runtimes, or calls adapters (`AGENTS.md`).
- CLI DTOs are **hand-mirrored** from controller DTOs on purpose. Do not import `httpd/controllers` into `internal/cli`.
- After editing `controllers/dto.go`, run `npm run api` and commit `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts` in the same commit as the Go change. CI fails if they drift.
- Any new named DTO type needs a `schemaNames` entry in `backend/internal/httpd/apispec/specgen/build.go`.
- Usage errors return `usageError` (exit 2); runtime failures exit 1.
- Gate for every task: `npm run lint` from the repo root (runs `go test ./...` plus golangci-lint v2.12.2) and `cd backend && go test ./internal/httpd/...` for spec-drift.
- Cap on conversation text over the wire: **2048 bytes**, matching `maxHookInteractionLen` semantics at ingest. Truncate with a trailing `…`.

## File Structure

| File | Responsibility | Task |
| --- | --- | --- |
| `backend/internal/httpd/controllers/dto.go:141` | `SessionView` gains `brief`, `latestUserPrompt`, `latestAssistantUpdate` | 1 |
| `backend/internal/httpd/controllers/sessions.go:1951` | `sessionView()` maps them off `Metadata`, capped | 1 |
| `backend/internal/httpd/controllers/sessions_view_test.go` (new, `package controllers`) | Wire assertions incl. cap and omitempty | 1 |
| `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts` | Generated | 1 |
| `backend/internal/cli/session.go:43` | `sessionDTO` mirrors the three fields plus `prs` | 2 |
| `backend/internal/cli/session.go:751` | `writeSessionDetails` renders them | 2 |
| `backend/internal/cli/session_test.go` | Render + `--json` assertions | 2 |
| `backend/internal/cli/board.go` (new) | `opr board` command and rendering | 3 |
| `backend/internal/cli/board_test.go` (new) | Table-driven command tests | 3 |
| `backend/internal/cli/root.go:191` | Register the board command | 3 |
| `backend/internal/session_manager/prompt.go:187` (command list), `:201` (workflow step 1) | Correct the `opr status` claim, teach `opr board` | 4 |
| `backend/internal/session_manager/prompt_test.go` | Assert the corrected prompt text | 4 |

---

### Task 1: Expose brief and conversation facts on the session wire shape

`domain.Session.Metadata` is `json:"-"`, so `Prompt`, `LatestUserPrompt` and `LatestAssistantUpdate` never reach any client. `SessionView` already exists to lift such fields (`Branch`, `WorkspacePath`, `PreviewURL` all work this way) and already carries `PRs []SessionPRFacts` with `CI`, `Review` and `Mergeability` — so the PR half of "eyes" needs no work.

**Files:**
- Modify: `backend/internal/httpd/controllers/dto.go:141-161` (`SessionView`)
- Modify: `backend/internal/httpd/controllers/sessions.go:1951-1962` (`sessionView`)
- Test: **create** `backend/internal/httpd/controllers/sessions_view_test.go` with `package controllers` (internal). `sessions_test.go` is `package controllers_test` and cannot reach unexported `sessionView`. Internal test files are established practice here — see `mobile_test.go` and `sessions_attachments_test.go`.
- Generated: `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`

**Interfaces:**
- Consumes: `domain.Session` with populated `Metadata.Prompt`, `Metadata.LatestUserPrompt`, `Metadata.LatestAssistantUpdate` (`backend/internal/domain/session.go:36-43`).
- Produces: JSON keys `brief`, `latestUserPrompt`, `latestAssistantUpdate` on every session object returned by `GET /sessions`, `GET /sessions/{id}`, and any response embedding `SessionView`. Each is `omitempty` and capped at 2048 bytes. Task 2 and Task 3 mirror these exact names.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/httpd/controllers/sessions_view_test.go`. It must be `package controllers`, not `controllers_test`, because it exercises the unexported `sessionView` and `maxWireInteractionLen`.

```go
package controllers

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestSessionViewExposesBriefAndConversationFacts(t *testing.T) {
	s := domain.Session{}
	s.ID = "opr-1"
	s.Metadata.Prompt = "fix the flaky resize test"
	s.Metadata.LatestUserPrompt = "also check the codex path"
	s.Metadata.LatestAssistantUpdate = "I reproduced it and pushed a fix."

	view := sessionView(s)

	if view.Brief != "fix the flaky resize test" {
		t.Fatalf("brief = %q", view.Brief)
	}
	if view.LatestUserPrompt != "also check the codex path" {
		t.Fatalf("latestUserPrompt = %q", view.LatestUserPrompt)
	}
	if view.LatestAssistantUpdate != "I reproduced it and pushed a fix." {
		t.Fatalf("latestAssistantUpdate = %q", view.LatestAssistantUpdate)
	}
}

func TestSessionViewCapsConversationFacts(t *testing.T) {
	s := domain.Session{}
	s.Metadata.LatestAssistantUpdate = strings.Repeat("a", maxWireInteractionLen+500)

	view := sessionView(s)

	if len([]byte(view.LatestAssistantUpdate)) > maxWireInteractionLen {
		t.Fatalf("latestAssistantUpdate not capped: %d bytes", len(view.LatestAssistantUpdate))
	}
	if !strings.HasSuffix(view.LatestAssistantUpdate, "…") {
		t.Fatalf("capped value lost its ellipsis: %q", view.LatestAssistantUpdate[len(view.LatestAssistantUpdate)-8:])
	}
}

func TestSessionViewOmitsEmptyConversationFacts(t *testing.T) {
	body, err := json.Marshal(sessionView(domain.Session{}))
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"brief", "latestUserPrompt", "latestAssistantUpdate"} {
		if strings.Contains(string(body), key) {
			t.Fatalf("empty %s was serialized: %s", key, body)
		}
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && go test ./internal/httpd/controllers/ -run TestSessionView -v
```

Expected: build failure — `view.Brief` undefined, `maxWireInteractionLen` undefined. That is a correct RED for a missing field; fix nothing but the test's own typos.

- [ ] **Step 3: Write minimal implementation**

In `dto.go`, inside `SessionView` after the `PRs` field:

```go
	Brief                 string `json:"brief,omitempty" maxLength:"2048"`
	LatestUserPrompt      string `json:"latestUserPrompt,omitempty" maxLength:"2048"`
	LatestAssistantUpdate string `json:"latestAssistantUpdate,omitempty" maxLength:"2048"`
```

In `sessions.go`, above `sessionView`:

```go
const maxWireInteractionLen = 2048

func capWireText(s string) string {
	if len(s) <= maxWireInteractionLen {
		return s
	}
	cut := maxWireInteractionLen - len("…")
	for cut > 0 && !utf8.ValidString(s[:cut]) {
		cut--
	}
	return s[:cut] + "…"
}
```

Then extend the `sessionView` literal:

```go
		PRs:                   sessionPRFacts(s.PRs),
		Brief:                 capWireText(s.Metadata.Prompt),
		LatestUserPrompt:      capWireText(s.Metadata.LatestUserPrompt),
		LatestAssistantUpdate: capWireText(s.Metadata.LatestAssistantUpdate),
```

Add `"unicode/utf8"` to the `sessions.go` imports.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && go test ./internal/httpd/controllers/ -run TestSessionView -v
```

Expected: PASS. Then the drift gate:

```bash
cd backend && go test ./internal/httpd/...
```

- [ ] **Step 5: Regenerate the API artifacts**

```bash
npm run api
git diff --stat backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
```

Expected: both files show the three new properties. `SessionView` is an existing named type, so no `schemaNames` entry is needed. If `npm run api` reports an unnamed-schema error, add the entry it names to `specgen/build.go:235` and rerun.

- [ ] **Step 6: Run the full gate**

```bash
npm run lint
```

Expected: all packages ok, `0 issues.`

- [ ] **Step 7: Commit**

```bash
git add backend/internal/httpd/controllers/dto.go \
        backend/internal/httpd/controllers/sessions.go \
        backend/internal/httpd/controllers/sessions_view_test.go \
        backend/internal/httpd/apispec/openapi.yaml \
        frontend/src/api/schema.ts
git commit -m "feat(api): expose session brief and conversation facts

SessionView lifts Metadata.Prompt, LatestUserPrompt and
LatestAssistantUpdate onto the wire, capped at 2048 bytes, so a client can
see what a session was asked to do and what it last said. PR, CI and review
state were already on SessionView.PRs."
```

---

### Task 2: Render the new fields in `opr session get` and `--json`

**Files:**
- Modify: `backend/internal/cli/session.go:43-56` (`sessionDTO`)
- Modify: `backend/internal/cli/session.go:120-131` (`sessionListEntry`)
- Modify: `backend/internal/cli/session.go:751-783` (`writeSessionDetails`)
- Test: `backend/internal/cli/session_test.go`

**Interfaces:**
- Consumes: JSON keys `brief`, `latestUserPrompt`, `latestAssistantUpdate`, `prs` from Task 1.
- Produces: `sessionDTO.Brief`, `.LatestUserPrompt`, `.LatestAssistantUpdate`, `.PRs []sessionPRDTO` — Task 3 reuses `sessionDTO` and `sessionPRDTO` verbatim.

- [ ] **Step 1: Write the failing test**

Add to `backend/internal/cli/session_test.go`, matching the file's existing table-driven style and its daemon-stub helpers.

```go
func TestSessionGetRendersBriefAndConversationFacts(t *testing.T) {
	cfg := setConfigEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"session":{
			"id":"opr-1","projectId":"proj-1","kind":"worker","status":"working",
			"activity":{"state":"idle"},
			"brief":"fix the flaky resize test",
			"latestAssistantUpdate":"I reproduced it and pushed a fix.",
			"prs":[{"url":"https://github.com/o/r/pull/7","number":7,"state":"open","ci":"failing","review":"none"}]
		}}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "session", "get", "opr-1")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"brief: fix the flaky resize test",
		"last update: I reproduced it and pushed a fix.",
		"pr #7: open ci=failing review=none",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("output missing %q:\n%s", want, out)
		}
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend && go test ./internal/cli/ -run TestSessionGetRendersBriefAndConversationFacts -v
```

Expected: FAIL — `output missing "brief: fix the flaky resize test"`.

- [ ] **Step 3: Write minimal implementation**

In `session.go`, add to `sessionDTO`:

```go
	Brief                 string          `json:"brief,omitempty"`
	LatestUserPrompt      string          `json:"latestUserPrompt,omitempty"`
	LatestAssistantUpdate string          `json:"latestAssistantUpdate,omitempty"`
	PRs                   []sessionPRDTO  `json:"prs,omitempty"`
```

And the mirrored PR shape:

```go
type sessionPRDTO struct {
	URL    string `json:"url"`
	Number int    `json:"number"`
	State  string `json:"state"`
	CI     string `json:"ci"`
	Review string `json:"review"`
}
```

In `writeSessionDetails`, extend the `fields` slice after `{"issue", sess.IssueID}`:

```go
		{"brief", sess.Brief},
		{"last prompt", sess.LatestUserPrompt},
		{"last update", sess.LatestAssistantUpdate},
```

The existing loop already skips empty values. After the `updated:` block and before `return nil`:

```go
	for _, pr := range sess.PRs {
		if _, err := fmt.Fprintf(out, "pr #%d: %s ci=%s review=%s\n", pr.Number, pr.State, pr.CI, pr.Review); err != nil {
			return err
		}
	}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && go test ./internal/cli/ -run TestSessionGet -v && go test ./internal/cli/
```

Expected: PASS, whole package ok.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/cli/session.go backend/internal/cli/session_test.go
git commit -m "feat(cli): show session brief, last update and PR state

opr session get now renders the task brief, the last user prompt, the last
assistant update and each attributed PR's CI and review state, so a session's
work is legible without attaching to its pane."
```

---

### Task 3: Add `opr board`

One project-wide read of every live session with brief, activity, last update and PR state. This is what the orchestrator prompt currently, falsely, promises from `opr status`.

**No new endpoint.** `GET /sessions?project=<id>&active=true` already returns exactly this once Task 1 lands (`ListSessionsQuery`, `dto.go:119`). The spec's §8 entry for `GET /projects/{id}/board` is therefore dropped — record that when closing the task.

**Files:**
- Create: `backend/internal/cli/board.go`
- Create: `backend/internal/cli/board_test.go`
- Modify: `backend/internal/cli/root.go:191` (register the command)

**Interfaces:**
- Consumes: `sessionDTO`, `sessionPRDTO`, `sessionListResponse` from Task 2; `apiPath`, `getJSON`, `writeJSON`, `formatSessionAge` from the existing CLI helpers (`session.go`, `orchestrator.go:110`).
- Produces: `newBoardCommand(ctx *commandContext) *cobra.Command`.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/cli/board_test.go`:

```go
package cli

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestBoardRendersLiveWorkersForProject(t *testing.T) {
	cfg := setConfigEnv(t)
	var gotQuery string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotQuery = r.URL.RawQuery
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"sessions":[
			{"id":"opr-1","projectId":"proj-1","kind":"worker","displayName":"resize fix","status":"ci_failed",
			 "activity":{"state":"idle"},"brief":"fix the flaky resize test",
			 "latestAssistantUpdate":"Pushed a fix; CI is still red.",
			 "prs":[{"url":"u","number":7,"state":"open","ci":"failing","review":"none"}]},
			{"id":"opr-2","projectId":"proj-1","kind":"orchestrator","status":"idle","activity":{"state":"idle"}}
		]}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "board", "--project", "proj-1")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(gotQuery, "project=proj-1") || !strings.Contains(gotQuery, "active=true") {
		t.Fatalf("query = %q, want project and active filters", gotQuery)
	}
	for _, want := range []string{"opr-1", "resize fix", "ci_failed", "fix the flaky resize test", "Pushed a fix; CI is still red.", "#7 open ci=failing"} {
		if !strings.Contains(out, want) {
			t.Fatalf("board output missing %q:\n%s", want, out)
		}
	}
	if strings.Contains(out, "opr-2") {
		t.Fatalf("board listed the orchestrator itself:\n%s", out)
	}
}

func TestBoardRequiresProjectWhenNotInASession(t *testing.T) {
	t.Setenv("OPERATOR_SESSION_ID", "")
	cfg := setConfigEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	_, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "board")
	if err == nil {
		t.Fatal("expected a usage error when no project can be resolved")
	}
	if ExitCode(err) != 2 {
		t.Fatalf("exit code = %d, want 2", ExitCode(err))
	}
}

func TestBoardReportsAnEmptyProject(t *testing.T) {
	cfg := setConfigEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"sessions":[]}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "board", "--project", "proj-1")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, "(no live workers)") {
		t.Fatalf("output = %q", out)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && go test ./internal/cli/ -run TestBoard -v
```

Expected: FAIL — `unknown command "board"`.

- [ ] **Step 3: Write minimal implementation**

Create `backend/internal/cli/board.go`:

```go
package cli

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

type boardOptions struct {
	project string
	json    bool
}

type boardOutput struct {
	Data []sessionDTO `json:"data"`
}

func newBoardCommand(ctx *commandContext) *cobra.Command {
	var opts boardOptions
	cmd := &cobra.Command{
		Use:   "board",
		Short: "Show every live worker in a project with its brief, state and PRs",
		Args:  noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return ctx.showBoard(cmd.Context(), cmd, opts)
		},
	}
	cmd.Flags().StringVar(&opts.project, "project", "", "Project id (defaults to the current session's project)")
	cmd.Flags().BoolVar(&opts.json, "json", false, "Output as JSON")
	return cmd
}

func (c *commandContext) showBoard(ctx context.Context, cmd *cobra.Command, opts boardOptions) error {
	project, err := c.resolveBoardProject(ctx, opts.project)
	if err != nil {
		return err
	}
	params := url.Values{}
	params.Set("project", project)
	params.Set("active", "true")
	var res sessionListResponse
	if err := c.getJSON(ctx, apiPath("sessions", params), &res); err != nil {
		return err
	}
	workers := make([]sessionDTO, 0, len(res.Sessions))
	for _, sess := range res.Sessions {
		if sess.Kind == "orchestrator" {
			continue
		}
		workers = append(workers, sess)
	}
	sort.Slice(workers, func(i, j int) bool { return workers[i].ID < workers[j].ID })
	if opts.json {
		return writeJSON(cmd.OutOrStdout(), boardOutput{Data: workers})
	}
	return writeBoard(cmd, workers)
}

func (c *commandContext) resolveBoardProject(ctx context.Context, flag string) (string, error) {
	if trimmed := strings.TrimSpace(flag); trimmed != "" {
		return trimmed, nil
	}
	sessionID := strings.TrimSpace(os.Getenv("OPERATOR_SESSION_ID"))
	if !sessionIDPattern.MatchString(sessionID) {
		return "", usageError{fmt.Errorf("--project is required outside an Operator session")}
	}
	var res sessionResponse
	if err := c.getJSON(ctx, "sessions/"+url.PathEscape(sessionID), &res); err != nil {
		return "", err
	}
	if res.Session.ProjectID == "" {
		return "", usageError{fmt.Errorf("--project is required: session %s has no project", sessionID)}
	}
	return res.Session.ProjectID, nil
}

func writeBoard(cmd *cobra.Command, workers []sessionDTO) error {
	out := cmd.OutOrStdout()
	if len(workers) == 0 {
		_, err := fmt.Fprintln(out, "(no live workers)")
		return err
	}
	for i, w := range workers {
		if i > 0 {
			if _, err := fmt.Fprintln(out); err != nil {
				return err
			}
		}
		header := w.ID
		if w.DisplayName != "" {
			header += "  " + w.DisplayName
		}
		if w.Status != "" {
			header += "  [" + w.Status + "]"
		}
		if !w.Activity.LastActivityAt.IsZero() {
			header += "  (" + formatSessionAge(time.Since(w.Activity.LastActivityAt)) + ")"
		}
		if _, err := fmt.Fprintln(out, header); err != nil {
			return err
		}
		for _, line := range [][2]string{
			{"brief", w.Brief},
			{"last update", w.LatestAssistantUpdate},
		} {
			if line[1] == "" {
				continue
			}
			if _, err := fmt.Fprintf(out, "  %s: %s\n", line[0], line[1]); err != nil {
				return err
			}
		}
		for _, pr := range w.PRs {
			if _, err := fmt.Fprintf(out, "  #%d %s ci=%s review=%s\n", pr.Number, pr.State, pr.CI, pr.Review); err != nil {
				return err
			}
		}
	}
	return nil
}
```

In `root.go`, beside `newOrchestratorCommand`:

```go
	root.AddCommand(newBoardCommand(ctx))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && go test ./internal/cli/ -run TestBoard -v && go test ./internal/cli/
```

Expected: PASS, whole package ok. If `sessionIDPattern` is not visible from `board.go`, it lives in `internal/cli` already (used by `root.go:243`) — no new regexp.

- [ ] **Step 5: Run the full gate**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
git add backend/internal/cli/board.go backend/internal/cli/board_test.go backend/internal/cli/root.go
git commit -m "feat(cli): add opr board

One read of every live worker in a project with its brief, status, last
assistant update and PR/CI/review state. Built on the existing
GET /sessions?project=&active=true route rather than a new endpoint, and it
infers the project from OPERATOR_SESSION_ID so an orchestrator never has to
carry a project id."
```

---

### Task 4: Stop the orchestrator prompt claiming `opr status` shows work state

The prompt tells the orchestrator that `opr status` inspects "project, session, PR, and review state" and makes it step 1 of its workflow. `opr status` returns daemon health only. `opr status` keeps its contract; the prompt is corrected and points at `opr board`.

**Files:**
- Modify: `backend/internal/session_manager/prompt.go:187` and `:201`, both inside `orchestratorSystemPrompt`. The exact current lines are:
  ```go
  - `+"`opr status`"+` - inspect project, session, PR, and review state.
  ```
  ```go
  1. Inspect current state with `+"`opr status`"+`.
  ```
- Test: `backend/internal/session_manager/prompt_test.go`

**Interfaces:**
- Consumes: `opr board` from Task 3, `opr session get` fields from Task 2.
- Produces: no Go API change. Prompt text only.

- [ ] **Step 1: Write the failing test**

Add to `backend/internal/session_manager/prompt_test.go`:

```go
func TestOrchestratorPromptPointsAtBoardNotStatus(t *testing.T) {
	got := orchestratorSystemPrompt(promptProject{ID: "proj-1", Name: "Operator"})

	if !strings.Contains(got, "`opr board`") {
		t.Fatal("prompt does not teach opr board")
	}
	if strings.Contains(got, "`opr status` - inspect project, session, PR, and review state") {
		t.Fatal("prompt still claims opr status shows work state")
	}
	if !strings.Contains(got, "daemon health") {
		t.Fatal("prompt does not say what opr status actually reports")
	}
	if !strings.Contains(got, "1. Inspect current state with `opr board`") {
		t.Fatal("coordination workflow step 1 still points at the wrong command")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend && go test ./internal/session_manager/ -run TestOrchestratorPromptPointsAtBoardNotStatus -v
```

Expected: FAIL — "prompt does not teach opr board".

- [ ] **Step 3: Write minimal implementation**

In `orchestratorSystemPrompt`, in the Core Commands list, replace the `opr status` bullet with:

```go
- `+"`opr board`"+` - every live worker in this project with its task brief, status, last update, and PR/CI/review state. Start here.
- `+"`opr status`"+` - daemon health only (pid, port, uptime). It reports nothing about the work.
```

In the same function's `opr session get` bullet, append so the orchestrator knows the detail view is now useful:

```go
- `+"`opr session get <worker-session-id>`"+` - one worker in full, including its brief, its last user-facing update, and every PR it owns.
```

In the Coordination Workflow list, change step 1:

```go
1. Inspect current state with `+"`opr board`"+`.
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && go test ./internal/session_manager/ -run TestOrchestratorPrompt -v && go test ./internal/session_manager/
```

Expected: PASS. Other prompt tests may assert the old `opr status` line — if one fails, update it to the corrected text; do not weaken the new test.

- [ ] **Step 5: Run the full gate**

```bash
npm run lint
```

- [ ] **Step 6: Update the spec to match what shipped**

In `docs/superpowers/specs/2026-09-11-autonomous-orchestrator-design.md`:
- §8: remove the `GET /api/v1/projects/{id}/board` row and note that `opr board` reads `GET /sessions?project=&active=true`; keep the inbox rows for Phase 1.
- §14 Phase 0: mark it done and record that no new endpoint was needed.

- [ ] **Step 7: Commit**

```bash
git add backend/internal/session_manager/prompt.go \
        backend/internal/session_manager/prompt_test.go \
        docs/superpowers/specs/2026-09-11-autonomous-orchestrator-design.md
git commit -m "fix(prompt): point the orchestrator at opr board, not opr status

The orchestrator prompt claimed opr status inspects project, session, PR and
review state and made it step 1 of the coordination workflow; opr status
returns daemon health only. Step 1 now reads opr board, and the prompt says
what opr status actually reports."
```

---

## Deferred to Phase 1, deliberately

- **The `no hook signal` marker** for workers on aider, auggie, continue, grok or pi (§5.2). `domain.SessionStatus` already has a `no_signal` value, so the board renders whatever status derivation produces and needs no special case yet. The explicit spawn-time warning the spec asks for belongs with the inbox, where silence starts to mean something.
- **`opr inbox` / `opr inbox ack`**, migration `0106_orchestrator_inbox.sql`, the transactional store method, and the nudge. All of Phase 1.
- **The stale "the dispatcher reads it" comment** at `backend/internal/lifecycle/manager.go:30`. Phase 1 touches that interface; deleting it here would be drive-by.

## Verification before calling Phase 0 done

- [ ] `npm run lint` passes from the repo root.
- [ ] `cd backend && go test ./internal/httpd/...` passes (spec drift).
- [ ] `git diff --stat` on `openapi.yaml` and `frontend/src/api/schema.ts` shows the three new properties and nothing else unexpected.
- [ ] `opr board --project <real project>` against a running daemon shows a real worker's brief and last update — the one check no unit test makes, and the one that proves the ingest fix holds end to end. If `last update` shows a short suggested-prompt-looking string, the Global Constraints precondition commit is missing.
