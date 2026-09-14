package claudecode

import (
	"context"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

var (
	_ ports.SessionIDClaimChecker            = (*Plugin)(nil)
	_ ports.MultiConfigSessionIDClaimChecker = (*Plugin)(nil)
)

func (p *Plugin) IsSessionIDClaimed(ctx context.Context, sessionID domain.SessionID) (bool, error) {
	configDir, err := p.NativeSessionConfigDir(ctx, map[string]string{})
	if err != nil {
		return false, err
	}
	return p.IsSessionIDClaimedIn(ctx, sessionID, []string{configDir})
}

func (p *Plugin) IsSessionIDClaimedIn(ctx context.Context, sessionID domain.SessionID, configDirs []string) (bool, error) {
	id := strings.TrimSpace(string(sessionID))
	if id == "" {
		return false, nil
	}
	nativeID := claudeSessionUUID(id)
	for _, dir := range configDirs {
		_, found, err := p.LocateTranscript(ctx, ports.NativeSessionRef{NativeSessionID: nativeID, ConfigDir: dir})
		if err != nil {
			return false, err
		}
		if found {
			return true, nil
		}
	}
	return false, nil
}
