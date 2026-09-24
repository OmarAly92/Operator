package cli

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"sync"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var reviewerIdentity = mcpIdentity{Reviewer: &mcpReviewerIdentity{WorkerSessionID: "opr-1", Harness: "codex"}}

func reviewerDaemon(t *testing.T) (*httptest.Server, *sessionRequestLog, *[]string, *[]string) {
	t.Helper()
	log := &sessionRequestLog{}
	var mu sync.Mutex
	var bodies, telemetry []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.append(r)
		raw, _ := io.ReadAll(r.Body)
		mu.Lock()
		defer mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case mcpToolCalledPath:
			telemetry = append(telemetry, strings.TrimSpace(string(raw)))
			w.WriteHeader(http.StatusAccepted)
		case "/api/v1/sessions/opr-1/reviews/submit":
			bodies = append(bodies, strings.TrimSpace(string(raw)))
			_, _ = io.WriteString(w, `{"review":{"id":"run-1"},"reviews":[{"id":"run-1","prUrl":"https://github.com/o/r/pull/12","status":"complete","verdict":"changes_requested"}],"reviewerHandleId":"review-opr-1"}`)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	return srv, log, &bodies, &telemetry
}

func TestMCPReviewerServesOnlyReviewSubmit(t *testing.T) {
	srv, _, _, _ := reviewerDaemon(t)
	cs := connectMCP(t, srv, reviewerIdentity)

	if got := cs.InitializeResult().Instructions; got != ports.OperatorReviewerMCPInstructions {
		t.Fatalf("instructions = %q, want the reviewer instructions", got)
	}
	tools, err := cs.ListTools(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, tool := range tools.Tools {
		names = append(names, tool.Name)
	}
	if !reflect.DeepEqual(names, ports.OperatorReviewerMCPToolNames) {
		t.Fatalf("tools = %v, want %v", names, ports.OperatorReviewerMCPToolNames)
	}
}

func TestMCPReviewSubmitRecordsForTheReviewedWorkerOnly(t *testing.T) {
	srv, log, bodies, telemetry := reviewerDaemon(t)
	cs := connectMCP(t, srv, reviewerIdentity)

	var out reviewSubmitOutput
	args := map[string]any{"reviews": []map[string]any{{
		"run_id": " run-1 ", "verdict": "changes_requested", "body": "Fix the nil check.", "github_review_id": "991",
	}}}
	if res := callMCPTool(t, cs, "review_submit", args, &out); res.IsError {
		t.Fatalf("review_submit failed: %s", toolErrorText(res))
	}
	if out.WorkerSessionID != "opr-1" || len(out.Recorded) != 1 || out.Recorded[0].Status != "complete" {
		t.Fatalf("output = %+v", out)
	}
	want := `{"reviews":[{"runId":"run-1","verdict":"changes_requested","body":"Fix the nil check.","githubReviewId":"991"}]}`
	if len(*bodies) != 1 || (*bodies)[0] != want {
		t.Fatalf("bodies = %q, want %s", *bodies, want)
	}
	if want := `{"tool":"review_submit","outcome":"ok","role":"reviewer","harness":"codex"}`; len(*telemetry) != 1 || (*telemetry)[0] != want {
		t.Fatalf("telemetry = %q, want %s", *telemetry, want)
	}

	for _, bad := range []map[string]any{
		{"reviews": []map[string]any{}},
		{"reviews": []map[string]any{{"run_id": "", "verdict": "approved"}}},
		{"reviews": []map[string]any{{"run_id": "run-1", "verdict": "lgtm"}}},
	} {
		if res := callMCPTool(t, cs, "review_submit", bad, nil); !res.IsError {
			t.Fatalf("%v was accepted", bad)
		}
	}
	if got := log.all(); !reflect.DeepEqual(got, []string{"POST /api/v1/sessions/opr-1/reviews/submit"}) {
		t.Fatalf("requests = %#v, want only the valid submit", got)
	}
}

func TestMCPReviewerIdentityComesFromTheReviewerPane(t *testing.T) {
	t.Setenv("OPERATOR_SESSION_ID", "")
	t.Setenv("OPERATOR_REVIEW_WORKER_SESSION_ID", "")
	if _, err := mcpReviewerIdentityFromEnv(); err == nil {
		t.Fatal("want an error outside a reviewer pane")
	}
	t.Setenv("OPERATOR_REVIEW_WORKER_SESSION_ID", "opr-4")
	t.Setenv("OPERATOR_REVIEW_HARNESS", "claude-code")
	id, err := mcpReviewerIdentityFromEnv()
	if err != nil {
		t.Fatal(err)
	}
	if id.SessionID != "" || id.Reviewer == nil || id.Reviewer.WorkerSessionID != "opr-4" || id.Reviewer.Harness != "claude-code" {
		t.Fatalf("identity = %+v", id)
	}
}
