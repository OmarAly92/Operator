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

// claudeInstalledEvents mirrors the sub-command names in claudeManagedHooks
// (adapters/agent/claudecode/hooks.go). Operator installs every one of these, so
// every one of them arrives at Map. An event that is installed but unmapped is
// persisted as an unknown block and rendered by mobile as a chat notice titled
// with its raw name — which is how a composer draft carried by subagent-stop
// reached the phone as a message.
var claudeInstalledEvents = []string{
	"session-start",
	"user-prompt-submit",
	"pre-tool-use",
	"post-tool-use",
	"post-tool-use-failure",
	"permission-request",
	"stop",
	"notification",
	"subagent-stop",
	"session-end",
}

func TestEveryInstalledClaudeHookIsMappedOrDropped(t *testing.T) {
	for _, event := range claudeInstalledEvents {
		got := Map("claude-code", event)
		if got.Drop {
			continue
		}
		if !got.Known || got.Kind == domain.BlockEventUnknown {
			t.Errorf("%q is installed but unmapped: it becomes an unknown block and renders as a chat notice", event)
		}
	}
}

func TestPreToolUseOpensTheToolBlock(t *testing.T) {
	// The blocks design has the transcript's tool_start merge with the hook's
	// pre-tool-use on the same tool_use_id. The transcript half shipped in
	// phase 2; without this mapping the hook half never arrives.
	got := Map("claude-code", "pre-tool-use")
	if got.Kind != domain.BlockEventToolStart {
		t.Fatalf("kind = %q, want tool_start", got.Kind)
	}
	if got.Drop {
		t.Fatal("pre-tool-use opens the tool block; dropping it loses the tool's name and input")
	}
}

func TestSubagentTrafficIsDropped(t *testing.T) {
	// Recorded decision: subagent records are dropped, and nesting them under
	// their Task block is deferred. The transcript side already drops
	// isSidechain records and codex sub_agent_activity; this is the hook side.
	if got := Map("claude-code", "subagent-stop"); !got.Drop {
		t.Fatalf("subagent-stop must be dropped, got kind %q", got.Kind)
	}
}

func TestSessionEndContributesNoBlock(t *testing.T) {
	// session-end drives the activity state (exited); it carries nothing a
	// reader of the conversation needs, so it must not become a block.
	if got := Map("claude-code", "session-end"); !got.Drop {
		t.Fatalf("session-end must be dropped, got kind %q", got.Kind)
	}
}
