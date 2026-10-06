package controllers_test

import (
	"errors"
	"net/http"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestTerminalHistoryAPI_ReturnsCommandsOldestFirst(t *testing.T) {
	finished := time.Date(2026, 9, 27, 10, 0, 0, 0, time.UTC)
	hist := &fakeShellTerminalBlockHistory{recent: []domain.CommandRun{
		{Command: "make build", FinishedAt: finished},
		{Command: "for f in a b; do\n  echo $f\ndone", FinishedAt: finished.Add(time.Minute)},
	}}
	srv := newShellTerminalBlocksTestServer(t, &fakeShellTerminalService{}, hist)

	body, status, hdr := doRequest(t, srv, "GET", "/api/v1/terminal-history", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	assertJSON(t, hdr)
	var got struct {
		Commands []struct {
			Command    string    `json:"command"`
			FinishedAt time.Time `json:"finishedAt"`
		} `json:"commands"`
	}
	mustJSON(t, body, &got)
	if len(got.Commands) != 2 || got.Commands[0].Command != "make build" || got.Commands[1].Command != "for f in a b; do\n  echo $f\ndone" {
		t.Fatalf("commands = %+v", got.Commands)
	}
	if !got.Commands[0].FinishedAt.Equal(finished) {
		t.Fatalf("finishedAt = %v, want %v", got.Commands[0].FinishedAt, finished)
	}
	if hist.gotRecent != 500 {
		t.Fatalf("default limit = %d, want 500", hist.gotRecent)
	}
}

func TestTerminalHistoryAPI_EmptyIsAnEmptyList(t *testing.T) {
	srv := newShellTerminalBlocksTestServer(t, &fakeShellTerminalService{}, &fakeShellTerminalBlockHistory{})
	body, status, _ := doRequest(t, srv, "GET", "/api/v1/terminal-history?limit=10", "")
	if status != http.StatusOK || string(body) != "{\"commands\":[]}\n" {
		t.Fatalf("status = %d body = %q", status, body)
	}
}

func TestTerminalHistoryAPI_RejectsInvalidLimit(t *testing.T) {
	for _, raw := range []string{"abc", "0", "-3", "1001"} {
		srv := newShellTerminalBlocksTestServer(t, &fakeShellTerminalService{}, &fakeShellTerminalBlockHistory{})
		body, status, _ := doRequest(t, srv, "GET", "/api/v1/terminal-history?limit="+raw, "")
		if status != http.StatusBadRequest {
			t.Fatalf("limit=%s status = %d, want 400; body=%s", raw, status, body)
		}
		var env struct {
			Code      string `json:"code"`
			RequestID string `json:"requestId"`
		}
		mustJSON(t, body, &env)
		if env.Code != "INVALID_QUERY" || env.RequestID == "" {
			t.Fatalf("limit=%s envelope = %+v", raw, env)
		}
	}
}

func TestTerminalHistoryAPI_StoreErrorKeepsTheEnvelope(t *testing.T) {
	srv := newShellTerminalBlocksTestServer(t, &fakeShellTerminalService{}, &fakeShellTerminalBlockHistory{err: errors.New("disk gone")})
	body, status, _ := doRequest(t, srv, "GET", "/api/v1/terminal-history", "")
	if status != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body=%s", status, body)
	}
	var env struct {
		RequestID string `json:"requestId"`
	}
	mustJSON(t, body, &env)
	if env.RequestID == "" {
		t.Fatalf("envelope lost its requestId: %s", body)
	}
}

func TestTerminalHistoryAPI_NotImplementedWithoutHistoryService(t *testing.T) {
	srv := newShellTerminalTestServer(t, &fakeShellTerminalService{})
	_, status, _ := doRequest(t, srv, "GET", "/api/v1/terminal-history", "")
	if status != http.StatusNotImplemented {
		t.Fatalf("status = %d, want 501", status)
	}
}
