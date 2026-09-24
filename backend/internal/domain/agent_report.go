package domain

import (
	"time"
	"unicode/utf8"
)

// AgentReportState is what an agent reported about its own card through the
// Operator MCP server. It is a durable fact the status derivation reads, not a
// stored display status.
type AgentReportState string

const (
	// AgentReportNeedsYou: the agent ended (or is ending) its turn waiting on
	// the user for a question, decision or access. Hooks cannot tell that apart
	// from a finished turn, so the agent says so.
	AgentReportNeedsYou AgentReportState = "needs_you"
	// AgentReportReadyForReview: the work is complete and there is no PR to
	// carry it to In review.
	AgentReportReadyForReview AgentReportState = "ready_for_review"
)

// AgentReportReasonMaxRunes bounds the one-line reason shown on the card and in
// the Needs you alert.
const AgentReportReasonMaxRunes = 280

// Valid reports whether s is a settable report state.
func (s AgentReportState) Valid() bool {
	return s == AgentReportNeedsYou || s == AgentReportReadyForReview
}

// AgentReport is a session's current agent-reported state. A nil report means
// the agent has reported nothing since it was last cleared.
type AgentReport struct {
	State  AgentReportState `json:"state" enum:"needs_you,ready_for_review"`
	Reason string           `json:"reason"`
	At     time.Time        `json:"at"`
}

// NeedsYou reports whether r is a needs_you report.
func (r *AgentReport) NeedsYou() bool {
	return r != nil && r.State == AgentReportNeedsYou
}

// ValidAgentReportReason reports whether reason fits the card: non-empty is the
// caller's rule, the length cap is shared.
func ValidAgentReportReason(reason string) bool {
	return utf8.RuneCountInString(reason) <= AgentReportReasonMaxRunes
}
