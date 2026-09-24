package cli

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"sort"
	"strings"
	"sync"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

// actionDaemon fakes the routes behind the self-scoped action tools and keeps
// every request body for assertions.
func actionDaemon(t *testing.T, reviewerSession string) (*httptest.Server, *sessionRequestLog, map[string]string) {
	t.Helper()
	log := &sessionRequestLog{}
	bodies := map[string]string{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.append(r)
		raw, _ := io.ReadAll(r.Body)
		bodies[r.Method+" "+r.URL.Path] = string(raw)
		w.Header().Set("Content-Type", "application/json")
		switch {
		case r.Method == http.MethodPatch && r.URL.Path == "/api/v1/sessions/opr-1":
			var in sessionRenameRequest
			_ = json.Unmarshal(raw, &in)
			_, _ = io.WriteString(w, `{"ok":true,"sessionId":"opr-1","displayName":`+jsonQuote(in.DisplayName)+`}`)
		case r.URL.Path == "/api/v1/sessions/opr-1/pr/claim":
			var in claimPRRequest
			_ = json.Unmarshal(raw, &in)
			if in.PR == "99" {
				w.WriteHeader(http.StatusConflict)
				_, _ = io.WriteString(w, `{"error":"conflict","code":"PR_CLAIMED_BY_ACTIVE_SESSION","message":"PR is already claimed by active session opr-2","requestId":"req-7"}`)
				return
			}
			_, _ = io.WriteString(w, `{"ok":true,"sessionId":"opr-1","prs":[{"url":"https://github.com/o/r/pull/12","number":12,"state":"open","ci":"pending","review":"none","mergeability":"unknown","reviewComments":false,"updatedAt":"2026-09-24T10:00:00Z"}],"branchChanged":true,"takenOverFrom":[]}`)
		case r.Method == http.MethodPost && r.URL.Path == "/api/v1/prs/12/resolve-comments":
			_, _ = io.WriteString(w, `{"ok":true,"resolved":2}`)
		case r.URL.Path == "/api/v1/sessions/opr-1/reviews/trigger":
			w.WriteHeader(http.StatusCreated)
			_, _ = io.WriteString(w, `{"reviewerHandleId":"h","reviews":[],"runs":[{"id":"run-1"}],"created":true}`)
		case r.URL.Path == "/api/v1/sessions/opr-1":
			_, _ = io.WriteString(w, `{"session":{"id":"opr-1","projectId":"demo","status":"idle","activity":{"state":"idle"},"prs":[`+
				`{"url":"https://github.com/o/r/pull/12","number":12},{"url":"https://github.com/o/r/pull/34","number":34},{"url":"https://github.com/x/y/pull/34","number":34}],"ticket":{"slug":"login","role":"planning"}}}`)
		case r.URL.Path == "/api/v1/projects/demo/tickets/login":
			_, _ = io.WriteString(w, `{"ticket":{"slug":"login","title":"Login","status":"in_progress","files":[],"plans":[`+
				`{"file":"plans/01-redirect.md","order":1,"title":"Redirect","status":"reviewing","sessionId":"opr-3","reviewerSessionId":`+jsonQuote(reviewerSession)+`}]}}`)
		case r.URL.Path == "/api/v1/projects/demo/tickets/login/plans/01-redirect.md/merge-ready":
			_, _ = io.WriteString(w, `{"ticket":{"slug":"login","title":"Login","status":"awaiting_merge","files":[],"plans":[`+
				`{"file":"plans/01-redirect.md","order":1,"title":"Redirect","status":"awaiting_merge","reviewerSessionId":"opr-1"}]}}`)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	return srv, log, bodies
}

func TestMCPSessionRenameValidatesAndRenamesOnlySelf(t *testing.T) {
	srv, log, _ := actionDaemon(t, "opr-1")
	cs := connectMCP(t, srv, selfIdentity)

	var out sessionRenameOutput
	if res := callMCPTool(t, cs, "session_rename", map[string]any{"name": "  fix login  "}, &out); res.IsError {
		t.Fatalf("rename failed: %s", toolErrorText(res))
	}
	if out.Name != "fix login" || out.SessionID != "opr-1" {
		t.Fatalf("rename output = %+v", out)
	}
	for _, bad := range []string{"", strings.Repeat("x", maxDisplayNameRunes+1)} {
		if res := callMCPTool(t, cs, "session_rename", map[string]any{"name": bad}, nil); !res.IsError {
			t.Fatalf("name %q was accepted", bad)
		}
	}
	if got := log.all(); !reflect.DeepEqual(got, []string{"PATCH /api/v1/sessions/opr-1"}) {
		t.Fatalf("requests = %#v, want the single valid rename", got)
	}
}

func TestMCPPRClaimNeverTakesOverAnotherSession(t *testing.T) {
	srv, _, bodies := actionDaemon(t, "opr-1")
	cs := connectMCP(t, srv, selfIdentity)

	var out prClaimOutput
	if res := callMCPTool(t, cs, "pr_claim", map[string]any{"pr": "12"}, &out); res.IsError {
		t.Fatalf("claim failed: %s", toolErrorText(res))
	}
	if len(out.PRs) != 1 || out.PRs[0].Number != 12 || !out.BranchChanged {
		t.Fatalf("claim output = %+v", out)
	}
	if body := bodies["POST /api/v1/sessions/opr-1/pr/claim"]; !strings.Contains(body, `"allowTakeover":false`) {
		t.Fatalf("claim body = %s, want allowTakeover false", body)
	}
	res := callMCPTool(t, cs, "pr_claim", map[string]any{"pr": "99"}, nil)
	if !res.IsError || !strings.Contains(toolErrorText(res), "PR_CLAIMED_BY_ACTIVE_SESSION") {
		t.Fatalf("takeover conflict not surfaced: %+v", res)
	}
}

func TestMCPReviewRequestStartsAReviewOfOwnPRs(t *testing.T) {
	srv, log, _ := actionDaemon(t, "opr-1")
	cs := connectMCP(t, srv, selfIdentity)

	var out reviewRequestOutput
	if res := callMCPTool(t, cs, "review_request", nil, &out); res.IsError {
		t.Fatalf("review_request failed: %s", toolErrorText(res))
	}
	if !out.Started || out.Runs != 1 {
		t.Fatalf("review output = %+v", out)
	}
	if got := log.all(); !reflect.DeepEqual(got, []string{"POST /api/v1/sessions/opr-1/reviews/trigger"}) {
		t.Fatalf("requests = %#v", got)
	}
}

func TestMCPTicketMarkMergeReadyFindsThePlanThisSessionReviews(t *testing.T) {
	srv, _, bodies := actionDaemon(t, "opr-1")
	cs := connectMCP(t, srv, selfIdentity)

	var out ticketMarkMergeReadyOutput
	if res := callMCPTool(t, cs, "ticket_mark_merge_ready", map[string]any{"summary": "gates green, verified in the app"}, &out); res.IsError {
		t.Fatalf("merge-ready failed: %s", toolErrorText(res))
	}
	if out.PlanFile != "plans/01-redirect.md" || out.PlanStatus != "awaiting_merge" {
		t.Fatalf("merge-ready output = %+v", out)
	}
	if body := bodies["POST /api/v1/projects/demo/tickets/login/plans/01-redirect.md/merge-ready"]; !strings.Contains(body, "gates green") {
		t.Fatalf("merge-ready body = %q", body)
	}
}

func TestMCPTicketMarkMergeReadyRefusesANonReviewer(t *testing.T) {
	srv, log, _ := actionDaemon(t, "opr-9")
	cs := connectMCP(t, srv, selfIdentity)

	res := callMCPTool(t, cs, "ticket_mark_merge_ready", map[string]any{"summary": "x"}, nil)
	if !res.IsError || !strings.Contains(toolErrorText(res), "waiting on this session's review") {
		t.Fatalf("a non-reviewer marked a plan merge-ready: %+v", res)
	}
	for _, req := range log.all() {
		if strings.HasSuffix(req, "/merge-ready") {
			t.Fatalf("merge-ready was posted for a non-reviewer: %#v", log.all())
		}
	}
}

// Adapters pre-approve the server's tools by exact name from
// ports.OperatorMCPToolNames; it must list exactly what the server registers.
func TestOperatorMCPToolNamesMatchTheServer(t *testing.T) {
	srv, _ := mcpDaemon(t)
	cs := connectMCP(t, srv, selfIdentity)
	tools, err := cs.ListTools(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, tool := range tools.Tools {
		got = append(got, tool.Name)
	}
	want := append([]string(nil), ports.OperatorMCPToolNames...)
	sort.Strings(got)
	sort.Strings(want)
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("server tools %v, ports.OperatorMCPToolNames %v", got, want)
	}
}

func TestMCPPRResolveCommentsActsOnlyOnOwnPRs(t *testing.T) {
	srv, log, bodies := actionDaemon(t, "opr-1")
	cs := connectMCP(t, srv, selfIdentity)

	var out prResolveCommentsOutput
	args := map[string]any{"pr": "#12", "comment_ids": []string{" PRRC_1 ", ""}}
	if res := callMCPTool(t, cs, "pr_resolve_comments", args, &out); res.IsError {
		t.Fatalf("pr_resolve_comments failed: %s", toolErrorText(res))
	}
	if out.PR != 12 || out.Resolved != 2 || out.URL != "https://github.com/o/r/pull/12" {
		t.Fatalf("output = %+v", out)
	}
	if body := bodies["POST /api/v1/prs/12/resolve-comments"]; body != `{"prUrl":"https://github.com/o/r/pull/12","commentIds":["PRRC_1"]}` {
		t.Fatalf("body = %s", body)
	}
	for pr, want := range map[string]string{
		"77":                             "not attributed to your session",
		"https://github.com/o/r/pull/77": "not attributed to your session",
		"34":                             "pass its URL",
	} {
		res := callMCPTool(t, cs, "pr_resolve_comments", map[string]any{"pr": pr}, nil)
		if !res.IsError || !strings.Contains(toolErrorText(res), want) {
			t.Fatalf("pr %s: result = %+v, want error %q", pr, res, want)
		}
	}
	resolves := 0
	for _, req := range log.all() {
		if strings.HasSuffix(req, "/resolve-comments") {
			resolves++
		}
	}
	if resolves != 1 {
		t.Fatalf("requests = %#v, want one resolve", log.all())
	}
}

func TestMCPSessionHandoffSubmitPostsTheDocumentForTheCallersSwitch(t *testing.T) {
	var mu sync.Mutex
	bodies := map[string]string{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		mu.Lock()
		bodies[r.Method+" "+r.URL.Path] = string(raw)
		mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/api/v1/sessions/opr-1/agent-switches/sw-1/handoff" {
			_, _ = io.WriteString(w, `{"switch":{"id":"sw-1","sessionId":"opr-1","state":"collecting_handoff","agentHandoffStatus":"received"}}`)
			return
		}
		w.WriteHeader(http.StatusAccepted)
	}))
	t.Cleanup(srv.Close)
	cs := connectMCP(t, srv, selfIdentity)

	var out sessionHandoffSubmitOutput
	args := map[string]any{"switch_id": "sw-1", "source_generation": "gen-1", "handoff": map[string]any{"schemaVersion": 1, "goal": "ship it", "progressSummary": "half done"}}
	if res := callMCPTool(t, cs, "session_handoff_submit", args, &out); res.IsError {
		t.Fatalf("session_handoff_submit failed: %s", toolErrorText(res))
	}
	if out.SwitchID != "sw-1" || out.HandoffStatus != "received" {
		t.Fatalf("output = %+v", out)
	}
	mu.Lock()
	body := bodies["POST /api/v1/sessions/opr-1/agent-switches/sw-1/handoff"]
	mu.Unlock()
	if want := `{"sourceGenerationId":"gen-1","handoff":{"goal":"ship it","progressSummary":"half done","schemaVersion":1}}`; body != want {
		t.Fatalf("body = %s, want %s", body, want)
	}

	for _, bad := range []map[string]any{
		{"switch_id": "", "source_generation": "gen-1", "handoff": map[string]any{"goal": "x"}},
		{"switch_id": "sw-1", "source_generation": "gen-1", "handoff": map[string]any{}},
		{"switch_id": "sw-1", "source_generation": "gen-1", "handoff": map[string]any{"freeformDetails": strings.Repeat("x", maxHandoffBytes)}},
	} {
		if res := callMCPTool(t, cs, "session_handoff_submit", bad, nil); !res.IsError {
			t.Fatalf("%v was accepted", bad)
		}
	}
}
