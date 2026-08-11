package daemon

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type claimingRuntime struct {
	ports.Runtime
	claimed map[domain.SessionID]bool
	err     error
}

func (r claimingRuntime) IsSessionIDClaimed(_ context.Context, id domain.SessionID) (bool, error) {
	if r.err != nil {
		return false, r.err
	}
	return r.claimed[id], nil
}

type plainRuntime struct{ ports.Runtime }

func testLogger() (*slog.Logger, *bytes.Buffer) {
	var buf bytes.Buffer
	return slog.New(slog.NewTextHandler(&buf, &slog.HandlerOptions{Level: slog.LevelDebug})), &buf
}

func TestSessionIDClaimProbeDelegatesToRuntime(t *testing.T) {
	log, _ := testLogger()
	probe := sessionIDClaimProbe(claimingRuntime{claimed: map[domain.SessionID]bool{"scratch-1": true}}, log)
	if probe == nil {
		t.Fatal("probe = nil, want a probe for a runtime that reports claimed ids")
	}

	if !probe(context.Background(), "scratch-1") {
		t.Fatal("probe(scratch-1) = false, want true")
	}
	if probe(context.Background(), "scratch-2") {
		t.Fatal("probe(scratch-2) = true, want false")
	}
}

// An inconclusive probe must not block allocation: reporting "claimed" would
// skip ids for no reason, and could exhaust the search. It reports free and
// leaves a trace, so allocation degrades to the database-only behavior.
func TestSessionIDClaimProbeReportsFreeAndLogsWhenRuntimeErrors(t *testing.T) {
	log, buf := testLogger()
	probe := sessionIDClaimProbe(claimingRuntime{err: errors.New("tmux exploded")}, log)

	if probe(context.Background(), "scratch-1") {
		t.Fatal("probe = true, want false when the runtime cannot answer")
	}
	if !strings.Contains(buf.String(), "tmux exploded") {
		t.Fatalf("log = %q, want the runtime error recorded", buf.String())
	}
}

func TestSessionIDClaimProbeIsNilForRuntimeWithoutCapability(t *testing.T) {
	log, _ := testLogger()
	if probe := sessionIDClaimProbe(plainRuntime{}, log); probe != nil {
		t.Fatal("probe != nil, want nil so allocation keeps its database-only behavior")
	}
}

func testLoggerDiscard() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}
