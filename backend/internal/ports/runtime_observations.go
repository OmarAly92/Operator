package ports

import (
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

// ProbeResult is a single liveness reading. "failed" means the probe errored
// or timed out and is never treated as a death conclusion.
type ProbeResult string

// Probe readings. Alive/Dead are conclusions; Failed is ignored by lifecycle
// because it is not a reliable death decision.
const (
	ProbeAlive  ProbeResult = "alive"
	ProbeDead   ProbeResult = "dead"
	ProbeFailed ProbeResult = "failed"
)

// RuntimeFacts is what the reaper reports each probe of a session runtime.
type RuntimeFacts struct {
	ObservedAt time.Time
	Runtime    ProbeResult
	Workload   ProbeResult
	LaunchID   string
}

// ActivitySignal is pushed by the agent hooks. Only a Valid activity state is
// authoritative; a stale/absent one is ignored rather than read as idleness.
// AgentSessionID may be supplied independently by metadata-only hooks such as
// SessionStart, allowing lifecycle to persist the native resume handle without
// inventing an activity transition.
//
// Event/ToolName/ToolUseID are optional correlation facts: the Operator hook
// sub-command that produced the state and, for tool-use hooks, the native
// tool call it concerns. Lifecycle uses them to clear a stale blocked state
// only when the specific approved tool finishes. A signal without an Event
// (old CLIs, adapters with no tool identity) keeps plain last-writer-wins
// state semantics.
type ActivitySignal struct {
	Valid             bool
	State             domain.ActivityState
	Timestamp         time.Time
	ExpectedUpdatedAt time.Time
	Event             string
	ToolName          string
	ToolUseID         string
	AgentSessionID    string
	// LatestUserPrompt and LatestAssistantUpdate are provider hook facts used
	// to build a deterministic handoff. They are never promoted to system
	// instructions and internal <opr-...> coordination turns are filtered by
	// the hook client before submission.
	LatestUserPrompt      string
	LatestAssistantUpdate string
	// TranscriptPath is a read-only provider-native transcript reference when
	// the hook exposes one. Operator stores the path, never rewrites the transcript.
	TranscriptPath string
	// Harness is the agent token the hook reported itself under. It is what
	// blockdispatch keys on; an empty harness maps every event to unknown.
	Harness string
	// ToolInput is a bounded preview of the native tool input. It is redacted
	// before it is persisted or transmitted, like every other text field.
	ToolInput string
	// HookVersion is the reporting CLI's body-schema version.
	HookVersion string
	// LaunchID is set by Operator's process supervisor. Lifecycle rejects a signal
	// from an older process generation of the same session.
	LaunchID string
	// ControllerGeneration is the equivalent fence for a runtime-less Chat
	// controller. It is intentionally internal (provider events never call the
	// public hook endpoint): lifecycle rejects it after a mode handoff or Chat
	// controller replacement.
	ControllerGeneration string
	// InteractionID is minted by the controller, not decoded from the wire: the
	// hook payload does not reliably carry the blocking tool's own id.
	InteractionID string
}
