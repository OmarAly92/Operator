package controllers_test

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	settingssvc "github.com/OmarAly92/operator/backend/internal/service/settings"
)

type fakeSettingsService struct {
	gotLocale    string
	gotUpdates   settingssvc.UpdateSettings
	gotBindings  settingssvc.KeybindingOverrides
	gotMigration settingssvc.MigrationState
	snapshot     settingssvc.Snapshot
	getErr       error
	migrationErr error
}

func (f *fakeSettingsService) Get(context.Context) (settingssvc.Snapshot, error) {
	return f.snapshot, f.getErr
}

func (f *fakeSettingsService) SetUILocale(_ context.Context, locale string) (settingssvc.Snapshot, error) {
	f.gotLocale = locale
	return f.snapshot, nil
}

func (f *fakeSettingsService) SetUpdateSettings(_ context.Context, prefs settingssvc.UpdateSettings) (settingssvc.Snapshot, error) {
	f.gotUpdates = prefs
	return f.snapshot, nil
}

func (f *fakeSettingsService) SetKeybindings(_ context.Context, overrides settingssvc.KeybindingOverrides) (settingssvc.Snapshot, error) {
	f.gotBindings = overrides
	return f.snapshot, nil
}

func (f *fakeSettingsService) SetMigrationState(_ context.Context, state settingssvc.MigrationState) (settingssvc.Snapshot, error) {
	f.gotMigration = state
	if f.migrationErr != nil {
		return settingssvc.Snapshot{}, f.migrationErr
	}
	return f.snapshot, nil
}

func newSettingsTestServer(t *testing.T, svc controllers.SettingsService) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{Settings: svc}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func sampleSnapshot() settingssvc.Snapshot {
	imported := time.Date(2026, 8, 20, 9, 0, 0, 0, time.UTC)
	return settingssvc.Snapshot{
		UpdatedAt: time.Date(2026, 8, 21, 12, 0, 0, 0, time.UTC),
		UILocale:  "ja",
		Updates: settingssvc.UpdateSettings{
			Enabled:    true,
			Channel:    settingssvc.UpdateChannelNightly,
			NightlyAck: true,
			Feature:    &settingssvc.FeaturePin{PR: 7},
		},
		Keybindings: settingssvc.KeybindingOverrides{
			"new-session": {},
			"next-tab": []settingssvc.ShortcutBinding{
				{Key: "[", Ctrl: true},
			},
		},
		Migration: settingssvc.MigrationState{
			Status:        settingssvc.MigrationCompleted,
			LastAttemptAt: &imported,
		},
		LegacyDesktopImportedAt: &imported,
	}
}

func TestSettingsAPIGetReturnsFullPreferenceSet(t *testing.T) {
	svc := &fakeSettingsService{snapshot: sampleSnapshot()}
	srv := newSettingsTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "GET", "/api/v1/settings", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	var resp struct {
		UI struct {
			Locale string `json:"locale"`
		} `json:"ui"`
		Updates struct {
			Enabled    bool   `json:"enabled"`
			Channel    string `json:"channel"`
			NightlyAck bool   `json:"nightlyAck"`
			Feature    *struct {
				PR int64 `json:"pr"`
			} `json:"feature"`
		} `json:"updates"`
		Keybindings map[string][]struct {
			Key   string `json:"key"`
			Ctrl  bool   `json:"ctrl"`
			Shift bool   `json:"shift"`
		} `json:"keybindings"`
		Migration struct {
			Status        string `json:"status"`
			LastAttemptAt string `json:"lastAttemptAt"`
		} `json:"migration"`
		LegacyDesktopImportedAt string `json:"legacyDesktopImportedAt"`
	}
	mustJSON(t, body, &resp)
	if resp.UI.Locale != "ja" {
		t.Errorf("locale = %q, want ja", resp.UI.Locale)
	}
	if !resp.Updates.Enabled || resp.Updates.Channel != "nightly" || !resp.Updates.NightlyAck {
		t.Errorf("updates = %+v, want nightly opt-in", resp.Updates)
	}
	if resp.Updates.Feature == nil || resp.Updates.Feature.PR != 7 {
		t.Errorf("feature = %+v, want pr 7", resp.Updates.Feature)
	}
	if len(resp.Keybindings["new-session"]) != 0 {
		t.Errorf("new-session = %v, want unassigned preserved", resp.Keybindings["new-session"])
	}
	if len(resp.Keybindings["next-tab"]) != 1 || resp.Keybindings["next-tab"][0].Key != "[" {
		t.Errorf("next-tab = %v, want ctrl+[", resp.Keybindings["next-tab"])
	}
	if resp.Migration.Status != "completed" || resp.Migration.LastAttemptAt == "" {
		t.Errorf("migration = %+v, want completed with timestamp", resp.Migration)
	}
	if resp.LegacyDesktopImportedAt == "" {
		t.Error("legacyDesktopImportedAt missing")
	}
}

func TestSettingsAPIPatchUILocale(t *testing.T) {
	svc := &fakeSettingsService{snapshot: sampleSnapshot()}
	srv := newSettingsTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "PATCH", "/api/v1/settings/ui", `{"locale":"de"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if svc.gotLocale != "de" {
		t.Errorf("locale = %q, want de", svc.gotLocale)
	}
}

func TestSettingsAPIPatchUpdateSettings(t *testing.T) {
	svc := &fakeSettingsService{snapshot: sampleSnapshot()}
	srv := newSettingsTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "PATCH", "/api/v1/settings/updates",
		`{"enabled":true,"channel":"nightly","nightlyAck":true,"feature":{"pr":31}}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if !svc.gotUpdates.Enabled || svc.gotUpdates.Channel != settingssvc.UpdateChannelNightly {
		t.Errorf("updates = %+v, want nightly opt-in", svc.gotUpdates)
	}
	if svc.gotUpdates.Feature == nil || svc.gotUpdates.Feature.PR != 31 {
		t.Errorf("feature = %+v, want pr 31", svc.gotUpdates.Feature)
	}
}

func TestSettingsAPIPatchKeybindingsPreservesEmptyOverride(t *testing.T) {
	svc := &fakeSettingsService{snapshot: sampleSnapshot()}
	srv := newSettingsTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "PATCH", "/api/v1/settings/keybindings",
		`{"new-session":[],"previous-session":[{"key":"PageUp","ctrl":true,"meta":false,"shift":false,"alt":false}]}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if svc.gotBindings["new-session"] == nil || len(svc.gotBindings["new-session"]) != 0 {
		t.Errorf("new-session = %v, want intentional unassigned", svc.gotBindings["new-session"])
	}
	if len(svc.gotBindings["previous-session"]) != 1 || svc.gotBindings["previous-session"][0].Key != "PageUp" {
		t.Errorf("previous-session = %+v, want PageUp kept", svc.gotBindings["previous-session"])
	}
}

func TestSettingsAPIPatchMigration(t *testing.T) {
	svc := &fakeSettingsService{snapshot: sampleSnapshot()}
	srv := newSettingsTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "PATCH", "/api/v1/settings/migration",
		`{"status":"declined","lastAttemptAt":"2026-08-21T10:00:00Z"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if svc.gotMigration.Status != settingssvc.MigrationDeclined {
		t.Errorf("status = %q, want declined", svc.gotMigration.Status)
	}
	if svc.gotMigration.LastAttemptAt == nil {
		t.Error("lastAttemptAt lost in decode")
	}
}

func TestSettingsAPIPatchMigrationRejectsUnknownStatus(t *testing.T) {
	svc := &fakeSettingsService{
		snapshot:     sampleSnapshot(),
		migrationErr: apierr.Invalid("MIGRATION_STATUS_INVALID", `status must be "pending", "completed", "declined", or "failed"`, nil),
	}
	srv := newSettingsTestServer(t, svc)

	body, status, header := doRequest(t, srv, "PATCH", "/api/v1/settings/migration", `{"status":"skipped"}`)
	if status != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", status, body)
	}
	var resp struct {
		Error     string `json:"error"`
		Code      string `json:"code"`
		RequestID string `json:"requestId"`
	}
	mustJSON(t, body, &resp)
	if resp.Error != "bad_request" || resp.Code != "MIGRATION_STATUS_INVALID" {
		t.Errorf("envelope = %+v, want bad_request/MIGRATION_STATUS_INVALID", resp)
	}
	if resp.RequestID == "" {
		t.Error("requestId missing from error envelope")
	}
	_ = header
}

func TestSettingsAPIPatchRejectsInvalidBody(t *testing.T) {
	svc := &fakeSettingsService{snapshot: sampleSnapshot()}
	srv := newSettingsTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "PATCH", "/api/v1/settings/ui", `{"locale":`)
	if status != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", status, body)
	}
	var resp struct {
		Code string `json:"code"`
	}
	mustJSON(t, body, &resp)
	if resp.Code == "" {
		t.Errorf("expected an error code, got %s", body)
	}
}

func TestSettingsAPINotImplementedWithoutService(t *testing.T) {
	srv := newSettingsTestServer(t, nil)

	for _, route := range []string{"/api/v1/settings/ui", "/api/v1/settings/updates", "/api/v1/settings/keybindings", "/api/v1/settings/migration"} {
		body, status, _ := doRequest(t, srv, "PATCH", route, "{}")
		if status != http.StatusNotImplemented {
			t.Fatalf("%s status = %d, want 501; body=%s", route, status, body)
		}
		var resp struct {
			Code string `json:"code"`
		}
		mustJSON(t, body, &resp)
		if resp.Code != "NOT_IMPLEMENTED" {
			t.Errorf("%s code = %q, want NOT_IMPLEMENTED", route, resp.Code)
		}
	}
}

func TestSettingsAPIGetStillServesAnEmptySnapshot(t *testing.T) {
	svc := &fakeSettingsService{snapshot: settingssvc.Snapshot{}}
	srv := newSettingsTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "GET", "/api/v1/settings", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	var raw map[string]any
	if err := json.Unmarshal(body, &raw); err != nil {
		t.Fatalf("decode: %v", err)
	}
	for _, key := range []string{"ui", "updates", "keybindings", "migration"} {
		if _, ok := raw[key]; !ok {
			t.Errorf("response missing %q: %s", key, body)
		}
	}
}
