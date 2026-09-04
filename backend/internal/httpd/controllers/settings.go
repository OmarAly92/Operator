package controllers

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

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
	SetMigrationState(ctx context.Context, state settingssvc.MigrationState) (settingssvc.Snapshot, error)
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
	r.Patch("/settings/migration", c.setMigration)
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

func (c *SettingsController) setMigration(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "PATCH", "/api/v1/settings/migration")
		return
	}
	var req MigrationState
	if !decodeSettingsBody(w, r, &req) {
		return
	}
	state, ok := serviceMigrationState(w, r, req)
	if !ok {
		return
	}
	snapshot, err := c.Svc.SetMigrationState(r.Context(), state)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, c.response(snapshot))
}

func serviceMigrationState(w http.ResponseWriter, r *http.Request, in MigrationState) (settingssvc.MigrationState, bool) {
	lastAttemptAt, ok := parseMigrationTimestamp(w, r, "lastAttemptAt", in.LastAttemptAt)
	if !ok {
		return settingssvc.MigrationState{}, false
	}
	completedAt, ok := parseMigrationTimestamp(w, r, "completedAt", in.CompletedAt)
	if !ok {
		return settingssvc.MigrationState{}, false
	}
	state := settingssvc.MigrationState{
		Status:        settingssvc.MigrationStatus(in.Status),
		LastAttemptAt: lastAttemptAt,
		CompletedAt:   completedAt,
		Error:         &in.Error,
	}
	if in.Report != nil {
		state.Report = &settingssvc.MigrationReport{
			ProjectsImported: in.Report.ProjectsImported,
			ProjectsSkipped:  in.Report.ProjectsSkipped,
		}
	}
	if in.Error == "" {
		state.Error = nil
	}
	return state, true
}

func parseMigrationTimestamp(w http.ResponseWriter, r *http.Request, field, raw string) (*time.Time, bool) {
	if raw == "" {
		return nil, true
	}
	parsed, err := time.Parse(time.RFC3339, raw)
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "validation",
			"INVALID_TIMESTAMP", field+" must be an RFC3339 timestamp", map[string]any{"field": field})
		return nil, false
	}
	stamp := parsed.UTC()
	return &stamp, true
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
		UI:                      UiSettings{Locale: snapshot.UILocale},
		Updates:                 snapshot.Updates,
		Keybindings:             snapshot.Keybindings,
		Migration:               wireMigrationState(snapshot.Migration),
		LegacyDesktopImportedAt: snapshot.LegacyDesktopImportedAt,
	}
}

func wireMigrationState(state settingssvc.MigrationState) MigrationState {
	wire := MigrationState{
		Status: string(state.Status),
		Error:  "",
	}
	if state.LastAttemptAt != nil {
		wire.LastAttemptAt = state.LastAttemptAt.UTC().Format(time.RFC3339)
	}
	if state.CompletedAt != nil {
		wire.CompletedAt = state.CompletedAt.UTC().Format(time.RFC3339)
	}
	if state.Report != nil {
		wire.Report = &settingssvc.MigrationReport{
			ProjectsImported: state.Report.ProjectsImported,
			ProjectsSkipped:  state.Report.ProjectsSkipped,
		}
	}
	if state.Error != nil {
		wire.Error = *state.Error
	}
	return wire
}
