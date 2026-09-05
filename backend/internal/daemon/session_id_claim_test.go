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
	probe := sessionIDClaimProbe(log, claimingRuntime{claimed: map[domain.SessionID]bool{"scratch-1": true}})
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
	probe := sessionIDClaimProbe(log, claimingRuntime{err: errors.New("runtime exploded")})

	if probe(context.Background(), "scratch-1") {
		t.Fatal("probe = true, want false when the runtime cannot answer")
	}
	if !strings.Contains(buf.String(), "runtime exploded") {
		t.Fatalf("log = %q, want the runtime error recorded", buf.String())
	}
}

func TestSessionIDClaimProbeIsNilForRuntimeWithoutCapability(t *testing.T) {
	log, _ := testLogger()
	if probe := sessionIDClaimProbe(log, plainRuntime{}); probe != nil {
		t.Fatal("probe != nil, want nil so allocation keeps its database-only behavior")
	}
}

func testLoggerDiscard() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func TestSessionIDClaimProbeClaimsWhenAnySourceDoes(t *testing.T) {
	log, _ := testLogger()
	free := claimingRuntime{claimed: map[domain.SessionID]bool{}}
	taken := claimingRuntime{claimed: map[domain.SessionID]bool{"scratch-5": true}}
	probe := sessionIDClaimProbe(log, free, taken)
	if probe == nil {
		t.Fatal("probe = nil, want a probe over two capable sources")
	}
	if !probe(context.Background(), "scratch-5") {
		t.Fatal("want claimed when the second source claims the id")
	}
	if probe(context.Background(), "scratch-6") {
		t.Fatal("want free when no source claims the id")
	}
}

func TestSessionIDClaimProbeIgnoresIncapableSources(t *testing.T) {
	log, _ := testLogger()
	probe := sessionIDClaimProbe(log, plainRuntime{}, claimingRuntime{claimed: map[domain.SessionID]bool{"scratch-5": true}})
	if probe == nil {
		t.Fatal("probe = nil, want a probe when one of the sources is capable")
	}
	if !probe(context.Background(), "scratch-5") {
		t.Fatal("want the capable source consulted past the incapable one")
	}
}

// A source that cannot answer must not silence the ones that can, or a flaky
// runtime probe would hide a workspace that genuinely holds the id.
func TestSessionIDClaimProbeConsultsRemainingSourcesAfterAnError(t *testing.T) {
	log, buf := testLogger()
	broken := claimingRuntime{err: errors.New("runtime exploded")}
	taken := claimingRuntime{claimed: map[domain.SessionID]bool{"scratch-5": true}}
	probe := sessionIDClaimProbe(log, broken, taken)
	if !probe(context.Background(), "scratch-5") {
		t.Fatal("want claimed from the healthy source after the broken one failed")
	}
	if !strings.Contains(buf.String(), "runtime exploded") {
		t.Fatalf("want the probe failure logged, got %q", buf.String())
	}
}

func TestSessionIDClaimProbeNilWhenNoSourceIsCapable(t *testing.T) {
	log, _ := testLogger()
	if probe := sessionIDClaimProbe(log, plainRuntime{}, plainRuntime{}); probe != nil {
		t.Fatal("want a nil probe so allocation stays database-only")
	}
}
