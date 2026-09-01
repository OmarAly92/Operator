// claim.go - session-id claim probe. A pty-host outlives the daemon that
// spawned it, so a database allocating ids from 1 (a fresh install, a reset
// data dir, a second instance) can hand out an id a live host still holds.
package ptyhost

import (
	"context"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/ptyregistry"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

var _ ports.SessionIDClaimChecker = (*Runtime)(nil)

// IsSessionIDClaimed reports whether a live pty-host already holds this session
// id. Two sources answer it: this process's own session map, and the on-disk
// registry, which spans daemon restarts and prunes entries whose PID is gone.
//
// A registry read failure is inconclusive and returns an error, leaving
// allocation to the database alone. An empty registry is decisive: unlike
// IsAlive, which must stay inconclusive because an agent can outlive its host
// as an orphan, an id cannot be held by a host that no longer exists.
func (r *Runtime) IsSessionIDClaimed(_ context.Context, sessionID domain.SessionID) (bool, error) {
	id := string(sessionID)
	if !validSessionID.MatchString(id) {
		return false, fmt.Errorf("ptyhost: invalid session id %q", id)
	}
	if r.resolve(id) != nil {
		return true, nil
	}
	entries, err := ptyregistry.List()
	if err != nil {
		return false, fmt.Errorf("ptyhost: read pty-host registry: %w", err)
	}
	for _, entry := range entries {
		if entry.SessionID == id {
			return true, nil
		}
	}
	return false, nil
}
