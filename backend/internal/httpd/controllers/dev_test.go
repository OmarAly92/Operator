package controllers_test

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
)

type fakeDevReplay struct {
	runs atomic.Int32
	got  blockeventsvc.ReplayInput
}

func (f *fakeDevReplay) Run(_ context.Context, in blockeventsvc.ReplayInput) error {
	f.runs.Add(1)
	f.got = in
	return nil
}

func newDevReplayServer(t *testing.T, replayer controllers.DevBlockReplayer) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{
		DevBlockReplay: replayer,
	}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestDevBlockReplayReturnsNotImplementedWhenEnvUnset(t *testing.T) {
	srv := newDevReplayServer(t, &fakeDevReplay{})

	_, status, _ := doRequest(t, srv, "POST", "/api/v1/dev/block-replay",
		`{"sessionId":"s-1","harness":"claude-code","events":4,"ratePerSecond":10}`)
	if status != http.StatusNotImplemented {
		t.Fatalf("status = %d, want 501 (env var unset)", status)
	}
}

func TestDevBlockReplayReturnsNotImplementedWithoutService(t *testing.T) {
	t.Setenv("OPERATOR_DEV_BLOCK_REPLAY", "1")
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{
		DevBlockReplay: nil,
	}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)

	_, status, _ := doRequest(t, srv, "POST", "/api/v1/dev/block-replay",
		`{"sessionId":"s-1","harness":"claude-code","events":4,"ratePerSecond":10}`)
	if status != http.StatusNotImplemented {
		t.Fatalf("status = %d, want 501 (service nil)", status)
	}
}

func TestDevBlockReplayReturnsAcceptedWhenEnabled(t *testing.T) {
	t.Setenv("OPERATOR_DEV_BLOCK_REPLAY", "1")
	svc := &fakeDevReplay{}
	srv := newDevReplayServer(t, svc)

	_, status, _ := doRequest(t, srv, "POST", "/api/v1/dev/block-replay",
		`{"sessionId":"s-1","harness":"claude-code","events":4,"ratePerSecond":1000}`)
	if status != http.StatusAccepted {
		t.Fatalf("status = %d, want 202", status)
	}
	// The replay runs on a goroutine; wait briefly for the call to land so
	// the test does not race past the handler before the goroutine fires.
	if err := waitForRuns(svc); err != nil {
		t.Fatal(err)
	}
	if svc.got.SessionID != domain.SessionID("s-1") {
		t.Fatalf("SessionID = %q, want s-1", svc.got.SessionID)
	}
	if svc.got.Harness != "claude-code" {
		t.Fatalf("Harness = %q, want claude-code", svc.got.Harness)
	}
	if svc.got.Events != 4 {
		t.Fatalf("Events = %d, want 4", svc.got.Events)
	}
}

func TestDevBlockReplayValidatesInput(t *testing.T) {
	t.Setenv("OPERATOR_DEV_BLOCK_REPLAY", "1")
	srv := newDevReplayServer(t, &fakeDevReplay{})

	cases := []struct {
		name string
		body string
	}{
		{"missing sessionId", `{"harness":"claude-code","events":4,"ratePerSecond":10}`},
		{"missing harness", `{"sessionId":"s-1","events":4,"ratePerSecond":10}`},
		{"zero events", `{"sessionId":"s-1","harness":"claude-code","events":0,"ratePerSecond":10}`},
		{"negative events", `{"sessionId":"s-1","harness":"claude-code","events":-3,"ratePerSecond":10}`},
		{"malformed json", `{"sessionId":`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, status, _ := doRequest(t, srv, "POST", "/api/v1/dev/block-replay", tc.body)
			if status != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400", status)
			}
		})
	}
}

// waitForRuns polls for at least one recorded Run call. The handler kicks off
// the goroutine, then returns 202; without a small wait the test could race
// past before the goroutine records its run.
func waitForRuns(svc *fakeDevReplay) error {
	for i := 0; i < 100; i++ {
		if svc.runs.Load() > 0 {
			return nil
		}
		time.Sleep(10 * time.Millisecond)
	}
	return errNoRun
}

var errNoRun = errors.New("replay goroutine did not run within 1s")
