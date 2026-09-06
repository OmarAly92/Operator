package claudecode

import (
	"context"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

var _ ports.SessionIDClaimChecker = (*Plugin)(nil)

// IsSessionIDClaimed reports whether Claude Code already holds the native
// session UUID this Operator session id derives to. The mapping is UUIDv5 over
// a fixed namespace, so scratch-16 always resolves to the same UUID, and Claude
// refuses --session-id for one it has a transcript for. That transcript lives
// under the config dir, which outlives both the workspace and the database that
// allocated the number.
//
// Existence is decisive, not size: an empty reserved transcript still blocks a
// fresh launch, and over-reporting a claim only costs the allocator one number.
func (p *Plugin) IsSessionIDClaimed(ctx context.Context, sessionID domain.SessionID) (bool, error) {
	id := strings.TrimSpace(string(sessionID))
	if id == "" {
		return false, nil
	}
	configDir, err := p.NativeSessionConfigDir(ctx, nil)
	if err != nil {
		return false, err
	}
	_, found, err := p.LocateTranscript(ctx, ports.NativeSessionRef{
		NativeSessionID: claudeSessionUUID(id),
		ConfigDir:       configDir,
	})
	if err != nil {
		return false, err
	}
	return found, nil
}
