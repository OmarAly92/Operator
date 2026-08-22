package httpd

import (
	"net/http"
	"runtime"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/adapters/telemetry"
	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
)

// mountDesktopTelemetry registers GET /internal/desktop/telemetry-bootstrap,
// the loopback-only source of the renderer's telemetry identity. The desktop
// supervisor stamps OPERATOR_TELEMETRY_RENDERER with the packaged/development
// intent; when it is off — a dev build that has not opted in, or a bare
// CLI-started daemon — the endpoint answers null and the renderer never
// constructs its PostHog client. Like the Connect Mobile control routes, this
// route is deliberately not gated by localControlRequest: the renderer always
// sends an Origin header, so loopback bind + CORS allowlist + the LAN
// listener's /internal/ block are the boundaries.
func mountDesktopTelemetry(r chi.Router, cfg config.Config) {
	r.Get("/internal/desktop/telemetry-bootstrap", func(w http.ResponseWriter, req *http.Request) {
		if !cfg.Telemetry.Renderer {
			envelope.WriteJSON(w, http.StatusOK, nil)
			return
		}
		distinctID, err := telemetry.LoadOrCreateInstallID(cfg.DataDir)
		if err != nil {
			envelope.WriteAPIError(w, req, http.StatusInternalServerError, "internal", "INSTALL_ID_UNAVAILABLE",
				"telemetry install identity unavailable", nil)
			return
		}
		disabledEvents := cfg.Telemetry.DisabledEvents
		if disabledEvents == nil {
			disabledEvents = []string{}
		}
		envelope.WriteJSON(w, http.StatusOK, desktopTelemetryBootstrap{
			DistinctID:     distinctID,
			AppVersion:     cfg.Telemetry.AppVersion,
			Platform:       desktopPlatform(),
			DisabledEvents: disabledEvents,
		})
	})
}

type desktopTelemetryBootstrap struct {
	DistinctID     string   `json:"distinctId"`
	AppVersion     string   `json:"appVersion"`
	Platform       string   `json:"platform"`
	DisabledEvents []string `json:"disabledEvents"`
}

// desktopPlatform maps the daemon's GOOS to the renderer's platform
// vocabulary, matching process.platform values.
func desktopPlatform() string {
	return desktopPlatformFor(runtime.GOOS)
}

func desktopPlatformFor(goos string) string {
	switch goos {
	case "windows":
		return "win32"
	case "darwin":
		return "darwin"
	default:
		return goos
	}
}
