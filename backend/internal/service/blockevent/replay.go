package blockevent

import (
	"context"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// Replay drives synthetic block events through the real Record path so a long
// session can be reproduced by hand and driven from a test. It is the harness
// for the load profile: every event goes through redaction, truncation,
// persistence, trimming, and the mux publish — exactly the path a real hook
// would take — so a client being tuned against this stream is being tuned
// against production code, not a test-only shortcut.
type Replay struct {
	Svc *Service
}

// ReplayInput is one replay run. Events caps the total number of recorded
// events; RatePerSecond paces the timer. The cycle is fixed: session-start,
// user-prompt-submit, four post-tool-use with distinct ToolUseIDs, one
// post-tool-use-failure, stop. The last cycle may be partial when Events is
// not a multiple of the cycle length.
type ReplayInput struct {
	SessionID     domain.SessionID
	Harness       string
	Events        int
	RatePerSecond int
}

// NewReplay builds a Replay over the supplied Service.
func NewReplay(svc *Service) *Replay {
	return &Replay{Svc: svc}
}

// replayCycle is the fixed event sequence one cycle emits. Event names match
// the claudeCodeEvents table at
// backend/internal/adapters/agent/blockdispatch/dispatch.go:39-47; an
// unrecognised name would map to BlockEventUnknown and exercise the wrong
// path, so this list is exact.
var replayCycle = []ports.ActivitySignal{
	{Event: "session-start", LatestAssistantUpdate: "session-start payload"},
	{Event: "user-prompt-submit", LatestUserPrompt: "user-prompt-submit payload"},
	{Event: "post-tool-use", ToolName: "Bash", ToolUseID: "tu-1", LatestAssistantUpdate: "post-tool-use 1 result"},
	{Event: "post-tool-use", ToolName: "Bash", ToolUseID: "tu-2", LatestAssistantUpdate: "post-tool-use 2 result"},
	{Event: "post-tool-use", ToolName: "Bash", ToolUseID: "tu-3", LatestAssistantUpdate: "post-tool-use 3 result"},
	{Event: "post-tool-use", ToolName: "Bash", ToolUseID: "tu-4", LatestAssistantUpdate: "post-tool-use 4 result"},
	{Event: "post-tool-use-failure", ToolName: "Bash", ToolUseID: "tu-fail", LatestAssistantUpdate: "post-tool-use-failure result"},
	{Event: "stop", LatestAssistantUpdate: "stop payload"},
}

const replayCycleLength = 8

// Run emits Events synthetic signals through Service.Record, paced by
// time.After at RatePerSecond. It returns when Events have been recorded or
// ctx is cancelled, whichever comes first. A partial cycle at the tail is
// intentional: the brief says "until Events have been recorded", not "until
// the next cycle boundary".
func (r *Replay) Run(ctx context.Context, in ReplayInput) error {
	if r.Svc == nil {
		return nil
	}
	if in.Events <= 0 {
		return nil
	}
	rate := in.RatePerSecond
	if rate <= 0 {
		rate = 1
	}
	interval := time.Second / time.Duration(rate)

	emitted := 0
	for emitted < in.Events {
		step := emitted % replayCycleLength
		sig := replayCycle[step]
		if err := r.Svc.Record(ctx, in.SessionID, in.Harness, sig); err != nil {
			return err
		}
		emitted++
		if emitted >= in.Events {
			break
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(interval):
		}
	}
	return nil
}
