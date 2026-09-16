package controllers

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	settingssvc "github.com/OmarAly92/operator/backend/internal/service/settings"
)

// SettingsService is the controller-facing preferences contract.
type SettingsService interface {
	Get(ctx context.Context) (settingssvc.Snapshot, error)
	SetUILocale(ctx context.Context, locale string) (settingssvc.Snapshot, error)
	SetUpdateSettings(ctx context.Context, prefs settingssvc.UpdateSettings) (settingssvc.Snapshot, error)
	SetKeybindings(ctx context.Context, overrides settingssvc.KeybindingOverrides) (settingssvc.Snapshot, error)
}

// SettingsController owns the daemon-owned preference routes.
//
// These are daemon-owned rather than renderer-owned on purpose: desktop, mobile,
// and the CLI all resolve the same value, so a preference held in one client would
// disagree with the others.
type SettingsController struct {
	Svc SettingsService
}

// Register mounts the settings routes.
func (c *SettingsController) Register(r chi.Router) {
	r.Get("/settings", c.get)
	r.Patch("/settings/ui", c.setUI)
	r.Patch("/settings/updates", c.setUpdates)
	r.Patch("/settings/keybindings", c.setKeybindings)
}

func (c *SettingsController) get(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/settings")
		return
	}
	snapshot, err := c.Svc.Get(r.Context())
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, c.response(snapshot))
}

func (c *SettingsController) setUI(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "PATCH", "/api/v1/settings/ui")
		return
	}
	var req UiSettings
	if !decodeSettingsBody(w, r, &req) {
		return
	}
	snapshot, err := c.Svc.SetUILocale(r.Context(), req.Locale)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, c.response(snapshot))
}

func (c *SettingsController) setUpdates(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "PATCH", "/api/v1/settings/updates")
		return
	}
	var req settingssvc.UpdateSettings
	if !decodeSettingsBody(w, r, &req) {
		return
	}
	snapshot, err := c.Svc.SetUpdateSettings(r.Context(), req)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, c.response(snapshot))
}

func (c *SettingsController) setKeybindings(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "PATCH", "/api/v1/settings/keybindings")
		return
	}
	var req settingssvc.KeybindingOverrides
	if !decodeSettingsBody(w, r, &req) {
		return
	}
	snapshot, err := c.Svc.SetKeybindings(r.Context(), req)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, c.response(snapshot))
}

func decodeSettingsBody(w http.ResponseWriter, r *http.Request, into any) bool {
	if err := json.NewDecoder(r.Body).Decode(into); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "validation",
			"INVALID_BODY", "request body is not valid JSON", nil)
		return false
	}
	return true
}

func (c *SettingsController) response(snapshot settingssvc.Snapshot) SettingsResponse {
	return SettingsResponse{
		UI:          UiSettings{Locale: snapshot.UILocale},
		Updates:     snapshot.Updates,
		Keybindings: snapshot.Keybindings,
	}
}
