package daemon

import (
	"context"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	"github.com/OmarAly92/operator/backend/internal/mobilebridge"
)

// restoreMobileOnBoot re-arms the Connect Mobile LAN listener across daemon
// restarts. If the persisted state says the bridge was enabled, it reuses the
// existing password (no rotation — the paired phone keeps working), deriving the
// auth hash in memory, and restarts the listener on its last bound port. A
// non-nil return means the listener failed to (re)bind; the caller logs it as a
// warning and continues booting regardless — Connect Mobile is best-effort, not
// load-bearing.
type tunnelStarter interface {
	Enable(ctx context.Context) error
	SetLocalPort(port int)
}

func restoreMobileOnBoot(path string, lan controllers.LANController, tun tunnelStarter) error {
	state, err := mobilebridge.Load(path)
	if err != nil {
		return fmt.Errorf("load mobile bridge state: %w", err)
	}
	if !state.Enabled {
		return nil
	}
	lan.SetPasswordHash(mobilebridge.HashPassword(state.Password))
	port, err := lan.Start(state.LastPort)
	if err != nil {
		return fmt.Errorf("restart mobile LAN listener: %w", err)
	}
	if tun == nil {
		return nil
	}
	tun.SetLocalPort(port)
	if !state.TunnelEnabled {
		return nil
	}
	if err := tun.Enable(context.Background()); err != nil {
		return fmt.Errorf("restart mobile tunnel: %w", err)
	}
	return nil
}
