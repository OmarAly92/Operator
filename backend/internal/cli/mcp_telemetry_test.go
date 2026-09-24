package cli

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

func TestMCPToolCallsReportNameOutcomeAndStateOnly(t *testing.T) {
	var mu sync.Mutex
	var events []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case mcpToolCalledPath:
			mu.Lock()
			events = append(events, string(raw))
			mu.Unlock()
			w.WriteHeader(http.StatusAccepted)
		case "/api/v1/sessions/opr-1/agent-report":
			var in agentReportWire
			_ = json.Unmarshal(raw, &in)
			if in.Reason == "" {
				w.WriteHeader(http.StatusBadRequest)
				_, _ = io.WriteString(w, `{"error":"bad_request","code":"INVALID_AGENT_REPORT","message":"a needs_you report requires a reason","requestId":"req-4"}`)
				return
			}
			_, _ = io.WriteString(w, `{"session":{"id":"opr-1","projectId":"demo","status":"needs_input","activity":{"state":"idle"},"prs":[]}}`)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	cs := connectMCP(t, srv, selfIdentity)

	callMCPTool(t, cs, "session_report", map[string]any{"state": "needs_you", "reason": "private: which db password?"}, nil)
	callMCPTool(t, cs, "session_report", map[string]any{"state": "needs_you"}, nil)
	callMCPTool(t, cs, "session_rename", map[string]any{"name": ""}, nil)

	want := []string{
		`{"sessionId":"opr-1","tool":"session_report","outcome":"ok","state":"needs_you"}`,
		`{"sessionId":"opr-1","tool":"session_report","outcome":"error","state":"needs_you"}`,
		`{"sessionId":"opr-1","tool":"session_rename","outcome":"error"}`,
	}
	mu.Lock()
	defer mu.Unlock()
	if len(events) != len(want) {
		t.Fatalf("events = %q, want %q", events, want)
	}
	for i := range want {
		if strings.TrimSpace(events[i]) != want[i] {
			t.Fatalf("event %d = %s, want %s", i, events[i], want[i])
		}
	}
}

func TestMCPToolCallTelemetryFailureLeavesTheResultAlone(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == mcpToolCalledPath {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		_, _ = io.WriteString(w, `{"ok":true,"sessionId":"opr-1","displayName":"x"}`)
	}))
	t.Cleanup(srv.Close)
	cs := connectMCP(t, srv, selfIdentity)

	if res := callMCPTool(t, cs, "session_rename", map[string]any{"name": "x"}, nil); res.IsError {
		t.Fatalf("rename failed because telemetry did: %s", toolErrorText(res))
	}
}
