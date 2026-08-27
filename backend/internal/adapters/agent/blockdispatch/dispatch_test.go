package blockdispatch

import (
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestMapReportsAToolFailure(t *testing.T) {
	got := Map("claude-code", "post-tool-use-failure")
	if got.Kind != domain.BlockEventToolComplete {
		t.Fatalf("kind = %q, want tool_complete", got.Kind)
	}
	if got.ErrorType == "" {
		t.Fatal("errorType is empty — a failed tool is indistinguishable from a successful one")
	}
	if got.Drop {
		t.Fatal("a tool failure must not be dropped")
	}
}

func TestMapLeavesASuccessfulToolWithoutAnError(t *testing.T) {
	if got := Map("claude-code", "post-tool-use"); got.ErrorType != "" {
		t.Fatalf("errorType = %q, want empty", got.ErrorType)
	}
}

func TestMapCanDropAnEventAtTheHarnessBoundary(t *testing.T) {
	Mappers["drop-test"] = func(event string) Decision {
		if event == "noise" {
			return Decision{Drop: true}
		}
		return Decision{Kind: domain.BlockEventStop, Known: true}
	}
	t.Cleanup(func() { delete(Mappers, "drop-test") })

	if got := Map("drop-test", "noise"); !got.Drop {
		t.Fatal("a harness must be able to drop its own useless event")
	}
	if got := Map("drop-test", "done"); got.Drop || got.Kind != domain.BlockEventStop {
		t.Fatalf("decision = %+v, want a kept stop", got)
	}
}

func TestMapOnAnUnregisteredHarnessIsUnknownAndKept(t *testing.T) {
	got := Map("aider", "stop")
	if got.Known || got.Drop || got.Kind != domain.BlockEventUnknown {
		t.Fatalf("decision = %+v, want an unknown, kept event", got)
	}
}

func TestMapOnAnUnregisteredEventIsUnknownAndKept(t *testing.T) {
	got := Map("claude-code", "some-future-hook")
	if got.Known || got.Drop || got.Kind != domain.BlockEventUnknown {
		t.Fatalf("decision = %+v, want an unknown, kept event", got)
	}
}
