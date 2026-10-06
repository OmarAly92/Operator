package cli

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// mcpDaemon fakes the daemon routes the Operator MCP tools read. Session opr-1
// is the caller; opr-2 is a peer in the same project.
func mcpDaemon(t *testing.T) (*httptest.Server, *sessionRequestLog) {
	t.Helper()
	log := &sessionRequestLog{}
	self := `{"id":"opr-1","projectId":"demo","harness":"claude-code","displayName":"fix-login",` +
		`"activity":{"state":"idle","lastActivityAt":"2026-09-24T10:00:00Z"},"isTerminated":false,` +
		`"status":"ci_failed","boardColumn":"needs_you","statusReason":"CI failing on PR #12",` +
		`"branch":"opr/opr-1","workspacePath":"/w/opr-1","brief":"Fix the login redirect",` +
		`"prs":[{"url":"https://github.com/o/r/pull/12","number":12,"state":"open","ci":"failing","review":"none","mergeability":"mergeable","reviewComments":false,"updatedAt":"2026-09-24T10:00:00Z"}],` +
		`"ticket":{"slug":"login","planFile":"plans/01-redirect.md","role":"implementing"}}`
	peer := `{"id":"opr-2","projectId":"demo","harness":"codex",` +
		`"activity":{"state":"active","lastActivityAt":"2026-09-24T10:05:00Z"},"isTerminated":false,` +
		`"status":"working","boardColumn":"working","statusReason":"Agent is working",` +
		`"brief":"` + strings.Repeat("x", 400) + `","prs":[]}`
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.append(r)
		w.Header().Set("Content-Type", "application/json")
		switch {
		case r.URL.Path == "/api/v1/sessions/opr-1":
			_, _ = io.WriteString(w, `{"session":`+self+`}`)
		case r.URL.Path == "/api/v1/sessions/opr-1/pr":
			_, _ = io.WriteString(w, `{"sessionId":"opr-1","prs":[{"url":"https://github.com/o/r/pull/12","number":12,"title":"Fix redirect","state":"open",`+
				`"sourceBranch":"opr/opr-1","targetBranch":"main","headSha":"abc123",`+
				`"ci":{"state":"failing","failingChecks":[{"name":"lint","status":"failed","conclusion":"failure","url":"https://ci/1"}]},`+
				`"review":{"decision":"none","hasUnresolvedHumanComments":true,"unresolvedBy":[{"reviewerId":"alice","count":2,"links":[]}]},`+
				`"mergeability":{"state":"mergeable","reasons":[],"prUrl":"https://github.com/o/r/pull/12"}}]}`)
		case r.URL.Path == "/api/v1/sessions/missing":
			w.WriteHeader(http.StatusNotFound)
			_, _ = io.WriteString(w, `{"error":"not_found","code":"SESSION_NOT_FOUND","message":"Unknown session","requestId":"req-9"}`)
		case r.URL.Path == "/api/v1/sessions" && r.URL.Query().Get("project") == "demo":
			_, _ = io.WriteString(w, `{"sessions":[`+self+`,`+peer+`]}`)
		case r.URL.Path == "/api/v1/projects/demo":
			_, _ = io.WriteString(w, `{"status":"ok","project":{"id":"demo","name":"Demo","kind":"single_repo","path":"/repo"}}`)
		case r.URL.Path == "/api/v1/projects/demo/tickets":
			_, _ = io.WriteString(w, `{"tickets":[{"slug":"login","title":"Login","status":"in_progress","plans":[],"files":[]},`+
				`{"slug":"old","title":"Old","status":"done","plans":[],"files":[]},`+
				`{"slug":"gone","title":"Gone","status":"archived","plans":[],"files":[]}]}`)
		case r.URL.Path == "/api/v1/projects/demo/tickets/login":
			_, _ = io.WriteString(w, `{"ticket":{"projectId":"demo","slug":"login","title":"Login","brief":"Fix login","status":"in_progress",`+
				`"plans":[{"file":"plans/01-redirect.md","order":1,"title":"Redirect","status":"working","sessionId":"opr-1"}],`+
				`"files":["ticket.md","spec.md","plans/01-redirect.md"]}}`)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	return srv, log
}

// connectMCP starts the Operator MCP server for session opr-1 against srv and
// returns a connected client session.
func connectMCP(t *testing.T, srv *httptest.Server, id mcpIdentity) *mcp.ClientSession {
	t.Helper()
	cfg := setConfigEnv(t)
	writeRunFileFor(t, cfg, srv)
	cc := &commandContext{deps: Deps{ProcessAlive: func(int) bool { return true }}.withDefaults()}
	server := newOperatorMCPServer(cc, id)
	serverT, clientT := mcp.NewInMemoryTransports()
	ctx := context.Background()
	ss, err := server.Connect(ctx, serverT, nil)
	if err != nil {
		t.Fatalf("server connect: %v", err)
	}
	t.Cleanup(func() { _ = ss.Close() })
	client := mcp.NewClient(&mcp.Implementation{Name: "test", Version: "0"}, nil)
	cs, err := client.Connect(ctx, clientT, nil)
	if err != nil {
		t.Fatalf("client connect: %v", err)
	}
	t.Cleanup(func() { _ = cs.Close() })
	return cs
}

func callMCPTool(t *testing.T, cs *mcp.ClientSession, name string, args map[string]any, out any) *mcp.CallToolResult {
	t.Helper()
	res, err := cs.CallTool(context.Background(), &mcp.CallToolParams{Name: name, Arguments: args})
	if err != nil {
		t.Fatalf("call %s: %v", name, err)
	}
	if out != nil && !res.IsError {
		raw, err := json.Marshal(res.StructuredContent)
		if err != nil {
			t.Fatalf("marshal structured content: %v", err)
		}
		if err := json.Unmarshal(raw, out); err != nil {
			t.Fatalf("decode %s output: %v\n%s", name, err, raw)
		}
	}
	return res
}

func toolErrorText(res *mcp.CallToolResult) string {
	var parts []string
	for _, c := range res.Content {
		if text, ok := c.(*mcp.TextContent); ok {
			parts = append(parts, text.Text)
		}
	}
	return strings.Join(parts, "\n")
}

var selfIdentity = mcpIdentity{SessionID: "opr-1", ProjectID: "demo"}

func TestMCPServerAdvertisesReadToolsAndBoardInstructions(t *testing.T) {
	srv, _ := mcpDaemon(t)
	cs := connectMCP(t, srv, selfIdentity)

	init := cs.InitializeResult()
	if init.ServerInfo.Name != MCPServerName {
		t.Fatalf("server name = %q, want %q", init.ServerInfo.Name, MCPServerName)
	}
	if init.Instructions != MCPBoardInstructions {
		t.Fatalf("instructions not advertised: %q", init.Instructions)
	}
	tools, err := cs.ListTools(context.Background(), nil)
	if err != nil {
		t.Fatalf("list tools: %v", err)
	}
	var names []string
	readOnly := map[string]bool{"board_get": true, "session_get": true, "ticket_get": true}
	for _, tool := range tools.Tools {
		names = append(names, tool.Name)
		if tool.Annotations == nil || tool.Annotations.ReadOnlyHint != readOnly[tool.Name] {
			t.Errorf("tool %s read-only annotation = %+v, want %v", tool.Name, tool.Annotations, readOnly[tool.Name])
		}
	}
	sort.Strings(names)
	if want := []string{"board_get", "pr_claim", "pr_resolve_comments", "review_request", "session_get", "session_handoff_submit", "session_rename", "session_report", "ticket_get", "ticket_mark_merge_ready"}; !reflect.DeepEqual(names, want) {
		t.Fatalf("tools = %v, want %v", names, want)
	}
}

func TestMCPBoardGetGroupsOwnProjectByColumn(t *testing.T) {
	srv, log := mcpDaemon(t)
	cs := connectMCP(t, srv, selfIdentity)

	var out boardGetOutput
	if res := callMCPTool(t, cs, "board_get", nil, &out); res.IsError {
		t.Fatalf("board_get failed: %s", toolErrorText(res))
	}
	if out.Project.ID != "demo" || out.Project.Name != "Demo" {
		t.Fatalf("project = %+v", out.Project)
	}
	var columns []string
	cards := map[string][]mcpCard{}
	for _, col := range out.Columns {
		columns = append(columns, col.Column)
		cards[col.Column] = col.Cards
	}
	if want := []string{"working", "needs_you", "in_review", "ready_to_merge"}; !reflect.DeepEqual(columns, want) {
		t.Fatalf("columns = %v, want %v", columns, want)
	}
	if len(cards["needs_you"]) != 1 || !cards["needs_you"][0].IsSelf || cards["needs_you"][0].StatusReason != "CI failing on PR #12" {
		t.Fatalf("needs_you cards = %+v", cards["needs_you"])
	}
	if got := cards["needs_you"][0].Ticket; got == nil || got.Role != "implementing" {
		t.Fatalf("self card ticket = %+v", got)
	}
	peer := cards["working"]
	if len(peer) != 1 || peer[0].IsSelf || peer[0].Name != "opr-2" {
		t.Fatalf("working cards = %+v", peer)
	}
	if n := len([]rune(peer[0].Brief)); n != mcpCardBriefLimit {
		t.Fatalf("peer brief not capped: %d runes", n)
	}
	if len(cards["in_review"]) != 0 || cards["in_review"] == nil {
		t.Fatalf("empty column must be an empty list, got %#v", cards["in_review"])
	}
	if want := []mcpPlannedTicket{{Slug: "login", Title: "Login", Status: "in_progress"}}; !reflect.DeepEqual(out.PlannedTickets, want) {
		t.Fatalf("planned tickets = %+v, want %+v", out.PlannedTickets, want)
	}
	want := []string{
		"GET /api/v1/projects/demo",
		"GET /api/v1/sessions?active=true&project=demo",
		"GET /api/v1/projects/demo/tickets",
	}
	if got := log.all(); !reflect.DeepEqual(got, want) {
		t.Fatalf("requests = %#v, want %#v", got, want)
	}
}

func TestMCPBoardGetFallsBackToSessionProjectWithoutEnv(t *testing.T) {
	srv, log := mcpDaemon(t)
	cs := connectMCP(t, srv, mcpIdentity{SessionID: "opr-1"})

	var out boardGetOutput
	if res := callMCPTool(t, cs, "board_get", nil, &out); res.IsError {
		t.Fatalf("board_get failed: %s", toolErrorText(res))
	}
	if got := log.all(); len(got) == 0 || got[0] != "GET /api/v1/sessions/opr-1" {
		t.Fatalf("expected the project to be resolved from the session first, got %#v", got)
	}
}

func TestMCPSessionGetDefaultsToSelfWithPRDetail(t *testing.T) {
	srv, _ := mcpDaemon(t)
	cs := connectMCP(t, srv, selfIdentity)

	var out sessionGetOutput
	if res := callMCPTool(t, cs, "session_get", nil, &out); res.IsError {
		t.Fatalf("session_get failed: %s", toolErrorText(res))
	}
	if out.SessionID != "opr-1" || !out.IsSelf || out.Column != "needs_you" || out.WorkspacePath != "/w/opr-1" {
		t.Fatalf("session = %+v", out.mcpCard)
	}
	if len(out.PRDetails) != 1 {
		t.Fatalf("pr details = %+v", out.PRDetails)
	}
	pr := out.PRDetails[0]
	if pr.CI != "failing" || len(pr.FailingChecks) != 1 || pr.FailingChecks[0].Name != "lint" {
		t.Fatalf("ci detail = %+v", pr)
	}
	if !pr.UnresolvedComments || len(pr.UnresolvedBy) != 1 || pr.UnresolvedBy[0] != (mcpUnresolvedBy{Reviewer: "alice", Count: 2}) {
		t.Fatalf("review detail = %+v", pr)
	}
}

func TestMCPSessionGetSurfacesDaemonErrorEnvelope(t *testing.T) {
	srv, _ := mcpDaemon(t)
	cs := connectMCP(t, srv, selfIdentity)

	res := callMCPTool(t, cs, "session_get", map[string]any{"session_id": "missing"}, nil)
	if !res.IsError {
		t.Fatal("expected a tool error for an unknown session")
	}
	text := toolErrorText(res)
	for _, want := range []string{"Unknown session", "SESSION_NOT_FOUND", "req-9"} {
		if !strings.Contains(text, want) {
			t.Fatalf("tool error %q is missing %q", text, want)
		}
	}
}

func TestMCPTicketGetDefaultsToOwnTicketWithRole(t *testing.T) {
	srv, _ := mcpDaemon(t)
	cs := connectMCP(t, srv, selfIdentity)

	var out ticketGetOutput
	if res := callMCPTool(t, cs, "ticket_get", nil, &out); res.IsError {
		t.Fatalf("ticket_get failed: %s", toolErrorText(res))
	}
	if out.Slug != "login" || out.Folder != ".operator/tickets/login" {
		t.Fatalf("ticket = %+v", out)
	}
	if out.YourRole != "implementing" || out.YourPlan != "plans/01-redirect.md" {
		t.Fatalf("role = %q plan = %q", out.YourRole, out.YourPlan)
	}
	if len(out.Plans) != 1 || out.Plans[0].SessionID != "opr-1" {
		t.Fatalf("plans = %+v", out.Plans)
	}
}

func TestMCPTicketGetWithoutTicketIsAToolError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, `{"session":{"id":"opr-1","projectId":"demo","status":"idle","activity":{"state":"idle"},"prs":[]}}`)
	}))
	t.Cleanup(srv.Close)
	cs := connectMCP(t, srv, selfIdentity)

	res := callMCPTool(t, cs, "ticket_get", nil, nil)
	if !res.IsError || !strings.Contains(toolErrorText(res), "not started from a ticket") {
		t.Fatalf("expected a no-ticket tool error, got %+v", res)
	}
}

func TestMCPCommandRequiresOperatorSession(t *testing.T) {
	t.Setenv("OPERATOR_SESSION_ID", "")
	_, _, err := executeCLI(t, Deps{}, "mcp")
	var usage usageError
	if !errors.As(err, &usage) || ExitCode(err) != 2 {
		t.Fatalf("err = %v (exit %d), want a usage error", err, ExitCode(err))
	}
}
