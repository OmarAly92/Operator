package cli

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// reportDaemon records agent-report writes and echoes the session back with the
// report applied, like the daemon route.
func reportDaemon(t *testing.T) (*httptest.Server, *sessionRequestLog, *[]string) {
	t.Helper()
	log := &sessionRequestLog{}
	var bodies []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.append(r)
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path != "/api/v1/sessions/opr-1/agent-report" {
			http.NotFound(w, r)
			return
		}
		raw, _ := io.ReadAll(r.Body)
		bodies = append(bodies, string(raw))
		report := `null`
		if r.Method == http.MethodPut {
			var in agentReportWire
			_ = json.Unmarshal(raw, &in)
			if in.State == "needs_you" && in.Reason == "" {
				w.WriteHeader(http.StatusBadRequest)
				_, _ = io.WriteString(w, `{"error":"bad_request","code":"INVALID_AGENT_REPORT","message":"a needs_you report requires a reason","requestId":"req-4"}`)
				return
			}
			report = string(raw)
		}
		_, _ = io.WriteString(w, `{"session":{"id":"opr-1","projectId":"demo","status":"needs_input","boardColumn":"needs_you",`+
			`"statusReason":"Agent needs you","activity":{"state":"idle"},"prs":[],"agentReport":`+report+`}}`)
	}))
	t.Cleanup(srv.Close)
	return srv, log, &bodies
}

func TestMCPSessionReportWritesOnlyTheCallersCard(t *testing.T) {
	srv, log, bodies := reportDaemon(t)
	cs := connectMCP(t, srv, selfIdentity)

	var card mcpCard
	res := callMCPTool(t, cs, "session_report", map[string]any{"state": "needs_you", "reason": "Postgres or SQLite?"}, &card)
	if res.IsError {
		t.Fatalf("session_report failed: %s", toolErrorText(res))
	}
	if card.SessionID != "opr-1" || card.Column != "needs_you" || card.AgentReport == nil || card.AgentReport.Reason != "Postgres or SQLite?" {
		t.Fatalf("card = %+v", card)
	}
	if res := callMCPTool(t, cs, "session_report", map[string]any{"state": "clear"}, nil); res.IsError {
		t.Fatalf("clear failed: %s", toolErrorText(res))
	}
	want := []string{"PUT /api/v1/sessions/opr-1/agent-report", "DELETE /api/v1/sessions/opr-1/agent-report"}
	if got := log.all(); !reflect.DeepEqual(got, want) {
		t.Fatalf("requests = %#v, want %#v", got, want)
	}
	if !strings.Contains((*bodies)[0], `"state":"needs_you"`) {
		t.Fatalf("put body = %s", (*bodies)[0])
	}
}

func TestMCPSessionReportRejectsBadStateAndSurfacesValidation(t *testing.T) {
	srv, log, _ := reportDaemon(t)
	cs := connectMCP(t, srv, selfIdentity)

	// The schema enum rejects an unknown state before the handler runs.
	res, err := cs.CallTool(context.Background(), &mcp.CallToolParams{Name: "session_report", Arguments: map[string]any{"state": "done"}})
	if err == nil && !res.IsError {
		t.Fatal("unknown state was accepted")
	}
	res = callMCPTool(t, cs, "session_report", map[string]any{"state": "needs_you"}, nil)
	if !res.IsError || !strings.Contains(toolErrorText(res), "INVALID_AGENT_REPORT") {
		t.Fatalf("daemon validation not surfaced: %+v", res)
	}
	if got := log.all(); len(got) != 1 {
		t.Fatalf("requests = %#v, want only the needs_you attempt", got)
	}
}

func TestMCPSessionReportSchemaNarrowsState(t *testing.T) {
	schema := sessionReportSchema()
	if got := schema.Properties["state"].Enum; !reflect.DeepEqual(got, []any{"needs_you", "ready_for_review", "clear"}) {
		t.Fatalf("state enum = %#v", got)
	}
	if !reflect.DeepEqual(schema.Required, []string{"state"}) {
		t.Fatalf("required = %#v, want only state", schema.Required)
	}
}

func TestMCPInstructionsTeachTheReportRule(t *testing.T) {
	for _, want := range []string{"session_report", "needs_you", "ready_for_review", "Before you end a turn waiting on the user", "ticket_mark_merge_ready"} {
		if !strings.Contains(MCPBoardInstructions, want) {
			t.Fatalf("instructions missing %q", want)
		}
	}
}

// Codex surfaces the first 512 characters of server instructions when deciding
// how to use a server, so the must-follow rule has to fit there.
func TestMCPInstructionsLeadWithTheReportRule(t *testing.T) {
	head := string([]rune(MCPBoardInstructions)[:512])
	for _, want := range []string{"session_report", "needs_you", "ready_for_review", "session_get"} {
		if !strings.Contains(head, want) {
			t.Fatalf("first 512 characters miss %q:\n%s", want, head)
		}
	}
}
