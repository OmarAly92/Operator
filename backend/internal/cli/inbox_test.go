package cli

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestInboxRendersPendingDigestsWithAckLine(t *testing.T) {
	cfg := setConfigEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"entries":[
			{"id":"evt-1","kind":"worker_idle","occurredAt":"2026-09-12T10:00:00Z",
			 "worker":{"id":"opr-1","projectId":"proj-1","kind":"worker","displayName":"resize fix","status":"idle",
			 "activity":{"state":"idle"},"brief":"fix the resize bug","latestUserPrompt":"also check codex",
			 "latestAssistantUpdate":"Pushed a fix.",
			 "prs":[{"url":"u","number":7,"state":"open","ci":"failing","review":"none"}]}}
		]}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "inbox", "--project", "proj-1")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"evt-1", "worker_idle", "opr-1", "resize fix", "also check codex", "Pushed a fix.", "#7 open ci=failing", "opr inbox ack evt-1"} {
		if !strings.Contains(out, want) {
			t.Fatalf("output missing %q:\n%s", want, out)
		}
	}
}

func TestInboxReportsAnEmptyInbox(t *testing.T) {
	cfg := setConfigEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"entries":[]}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "inbox", "--project", "proj-1")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, "(no pending inbox items)") {
		t.Fatalf("output = %q", out)
	}
}

func TestInboxAckSendsTheGivenIds(t *testing.T) {
	cfg := setConfigEnv(t)
	var gotBody string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		gotBody = string(body)
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"acked":2}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "inbox", "ack", "--project", "proj-1", "evt-1", "evt-2")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(gotBody, "evt-1") || !strings.Contains(gotBody, "evt-2") {
		t.Fatalf("request body = %q", gotBody)
	}
	if !strings.Contains(out, "acked 2") {
		t.Fatalf("output = %q", out)
	}
}

func TestInboxAckIsANoopWithoutError(t *testing.T) {
	cfg := setConfigEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"acked":0}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	_, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "inbox", "ack", "--project", "proj-1", "already-acked")
	if err != nil {
		t.Fatalf("ack of an unknown/already-acked id must not error: %v", err)
	}
}
