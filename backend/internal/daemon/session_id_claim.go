package daemon

import (
	"context"
	"log/slog"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// sessionIDClaimProbe adapts every source that can report claimed session ids
// into the single probe the store consults while allocating one. An id is taken
// if any source claims it; sources that lack the capability are ignored, and the
// probe is nil when none of them have it, leaving allocation purely
// database-driven.
//
// There is more than one namespace to ask. The terminal runtime's session names
// are machine-wide and outlive the daemon, and the workspace root outlives the
// database — either can already hold the id that MAX(num)+1 just produced.
//
// Interpreting a failed probe belongs here rather than in the store: the store
// asks a yes/no question about an id, and only this layer knows that the answer
// comes from sources that can be unreachable. An unanswerable source reports
// "free", so allocation degrades to its database-only behavior instead of
// skipping ids on no evidence.
func sessionIDClaimProbe(log *slog.Logger, sources ...any) func(context.Context, domain.SessionID) bool {
	checkers := make([]ports.SessionIDClaimChecker, 0, len(sources))
	for _, source := range sources {
		if checker, ok := source.(ports.SessionIDClaimChecker); ok && checker != nil {
			checkers = append(checkers, checker)
		}
	}
	if len(checkers) == 0 {
		return nil
	}
	return func(ctx context.Context, id domain.SessionID) bool {
		for _, checker := range checkers {
			claimed, err := checker.IsSessionIDClaimed(ctx, id)
			if err != nil {
				log.Warn("session id claim probe failed; allocating from the remaining sources",
					"sessionID", id, "error", err)
				continue
			}
			if claimed {
				return true
			}
		}
		return false
	}
}

// agentSessionIDClaims asks every resolvable agent adapter that implements the
// capability whether it already holds an id in its own provider namespace. A
// provider's session store is a third namespace, independent of the pty-host
// registry and the workspace root: Claude Code derives a stable UUID from the
// Operator session id and keeps its transcript under the config dir, so a
// number whose workspace was cleaned can still be unusable.
//
// One adapter failing is not the whole answer, so probing continues and the
// first error surfaces only when no adapter claimed the id.
type agentSessionIDClaims struct {
	agents ports.AgentResolver
}

func (a agentSessionIDClaims) IsSessionIDClaimed(ctx context.Context, sessionID domain.SessionID) (bool, error) {
	if a.agents == nil {
		return false, nil
	}
	var firstErr error
	for _, harness := range domain.AllHarnesses {
		agent, ok := a.agents.Agent(harness)
		if !ok {
			continue
		}
		checker, ok := agent.(ports.SessionIDClaimChecker)
		if !ok {
			continue
		}
		claimed, err := checker.IsSessionIDClaimed(ctx, sessionID)
		if err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		if claimed {
			return true, nil
		}
	}
	return false, firstErr
}
