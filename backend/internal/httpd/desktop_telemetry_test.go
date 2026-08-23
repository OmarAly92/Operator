package httpd

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/config"
)

type desktopBootstrapPayload struct {
	DistinctID     string   `json:"distinctId"`
	AppVersion     string   `json:"appVersion"`
	Platform       string   `json:"platform"`
	DisabledEvents []string `json:"disabledEvents"`
}

func getDesktopTelemetryBootstrap(t *testing.T, r http.Handler) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:3001/internal/desktop/telemetry-bootstrap", nil)
	req.Host = "127.0.0.1:3001"
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

func TestDesktopTelemetryBootstrapServesDaemonInstallIdentity(t *testing.T) {
	dataDir := t.TempDir()
	r := NewRouterWithControl(config.Config{
		DataDir: dataDir,
		Telemetry: config.TelemetryConfig{
			Renderer:       true,
			AppVersion:     "0.11.3",
			DisabledEvents: []string{"opr.v2.app.active", "opr.renderer.*"},
		},
	}, discardLogger(), nil, APIDeps{}, ControlDeps{})

	rec := getDesktopTelemetryBootstrap(t, r)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Fatalf("Cache-Control = %q, want no-store", got)
	}
	var payload desktopBootstrapPayload
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode %q: %v", rec.Body.String(), err)
	}
	if !strings.HasPrefix(payload.DistinctID, "ins_") {
		t.Fatalf("distinctId = %q, want an ins_ install id", payload.DistinctID)
	}
	if payload.AppVersion != "0.11.3" {
		t.Fatalf("appVersion = %q, want 0.11.3", payload.AppVersion)
	}
	if payload.Platform != desktopPlatform() {
		t.Fatalf("platform = %q, want %q", payload.Platform, desktopPlatform())
	}
	if desktopPlatform() != desktopPlatformFor(runtime.GOOS) {
		t.Fatalf("desktopPlatform() = %q, want the runtime mapping of %q", desktopPlatform(), runtime.GOOS)
	}
	if len(payload.DisabledEvents) != 2 || payload.DisabledEvents[0] != "opr.v2.app.active" || payload.DisabledEvents[1] != "opr.renderer.*" {
		t.Fatalf("disabledEvents = %#v, want the daemon deny list verbatim", payload.DisabledEvents)
	}

	raw, err := os.ReadFile(filepath.Join(dataDir, "telemetry_install_id"))
	if err != nil {
		t.Fatalf("read telemetry_install_id: %v", err)
	}
	if got := strings.TrimSpace(string(raw)); got != payload.DistinctID {
		t.Fatalf("install id file = %q, bootstrap distinctId = %q, want one shared id", got, payload.DistinctID)
	}

	repeat := getDesktopTelemetryBootstrap(t, r)
	if repeat.Code != http.StatusOK {
		t.Fatalf("repeat status = %d, want 200", repeat.Code)
	}
	var again desktopBootstrapPayload
	if err := json.Unmarshal(repeat.Body.Bytes(), &again); err != nil {
		t.Fatalf("decode repeat %q: %v", repeat.Body.String(), err)
	}
	if again.DistinctID != payload.DistinctID {
		t.Fatalf("distinctId changed across requests: %q then %q", payload.DistinctID, again.DistinctID)
	}
}

func TestDesktopTelemetryBootstrapSerializesEmptyDenyListAsArray(t *testing.T) {
	r := NewRouterWithControl(config.Config{
		DataDir:   t.TempDir(),
		Telemetry: config.TelemetryConfig{Renderer: true},
	}, discardLogger(), nil, APIDeps{}, ControlDeps{})

	rec := getDesktopTelemetryBootstrap(t, r)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Fatalf("Cache-Control = %q, want no-store", got)
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(rec.Body.Bytes(), &raw); err != nil {
		t.Fatalf("decode %q: %v", rec.Body.String(), err)
	}
	if string(raw["disabledEvents"]) == "null" {
		t.Fatalf("disabledEvents serialized as null %s, want [] so the renderer accepts the payload", rec.Body.String())
	}
	var payload desktopBootstrapPayload
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode %q: %v", rec.Body.String(), err)
	}
	if payload.DisabledEvents == nil || len(payload.DisabledEvents) != 0 {
		t.Fatalf("disabledEvents = %#v, want an empty non-nil array", payload.DisabledEvents)
	}
}

func TestDesktopTelemetryBootstrapWithheldWhenRendererTelemetryDisabled(t *testing.T) {
	dataDir := t.TempDir()
	r := NewRouterWithControl(config.Config{
		DataDir:   dataDir,
		Telemetry: config.TelemetryConfig{Renderer: false, AppVersion: "0.11.3"},
	}, discardLogger(), nil, APIDeps{}, ControlDeps{})

	rec := getDesktopTelemetryBootstrap(t, r)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Fatalf("Cache-Control = %q, want no-store", got)
	}
	var payload *desktopBootstrapPayload
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode %q: %v", rec.Body.String(), err)
	}
	if payload != nil {
		t.Fatalf("bootstrap = %#v, want null when renderer telemetry is disabled", payload)
	}
	if _, err := os.Stat(filepath.Join(dataDir, "telemetry_install_id")); !os.IsNotExist(err) {
		t.Fatalf("telemetry_install_id stat err = %v, want no id minted while disabled", err)
	}
}
