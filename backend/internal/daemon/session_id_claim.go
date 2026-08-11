package daemon

import (
	"context"
	"log/slog"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// sessionIDClaimProbe adapts a runtime that can report claimed session ids into
// the probe the store consults while allocating one. It returns nil for a
// runtime without that capability, leaving allocation purely database-driven.
//
// Interpreting a failed probe belongs here rather than in the store: the store
// asks a yes/no question about an id, and only this layer knows that the answer
// comes from a runtime that can be unreachable. An unanswerable probe reports
// "free", so allocation degrades to its database-only behavior instead of
// skipping ids on no evidence.
func sessionIDClaimProbe(rt any, log *slog.Logger) func(context.Context, domain.SessionID) bool {
	checker, ok := rt.(ports.SessionIDClaimChecker)
	if !ok {
		return nil
	}
	return func(ctx context.Context, id domain.SessionID) bool {
		claimed, err := checker.IsSessionIDClaimed(ctx, id)
		if err != nil {
			log.Warn("session id claim probe failed; allocating from the database alone",
				"sessionID", id, "error", err)
			return false
		}
		return claimed
	}
}
