package telemetry

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func TestLoadOrCreateInstallIDHelperProcess(t *testing.T) {
	if os.Getenv("OPERATOR_INSTALL_ID_HELPER") != "1" {
		return
	}
	readyPath := os.Getenv("OPERATOR_INSTALL_ID_READY")
	startPath := os.Getenv("OPERATOR_INSTALL_ID_START")
	if err := os.WriteFile(readyPath, []byte("ready"), 0o600); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(10 * time.Second)
	for {
		if _, err := os.Stat(startPath); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("timed out waiting for install-ID start barrier")
		}
		time.Sleep(5 * time.Millisecond)
	}
	id, err := LoadOrCreateInstallID(os.Getenv("OPERATOR_INSTALL_ID_DATA_DIR"))
	if err != nil {
		t.Fatal(err)
	}
	fmt.Printf("INSTALL_ID=%s\n", id)
}

func TestLoadOrCreateInstallIDIsConsistentAcrossProcesses(t *testing.T) {
	dataDir := t.TempDir()
	syncDir := t.TempDir()
	startPath := filepath.Join(syncDir, "start")
	const processCount = 8
	type process struct {
		cmd    *exec.Cmd
		output bytes.Buffer
		ready  string
	}
	processes := make([]process, processCount)
	for i := range processes {
		processes[i].ready = filepath.Join(syncDir, fmt.Sprintf("ready-%d", i))
		processes[i].cmd = exec.Command(os.Args[0], "-test.run=^TestLoadOrCreateInstallIDHelperProcess$")
		processes[i].cmd.Env = append(os.Environ(),
			"OPERATOR_INSTALL_ID_HELPER=1",
			"OPERATOR_INSTALL_ID_DATA_DIR="+dataDir,
			"OPERATOR_INSTALL_ID_READY="+processes[i].ready,
			"OPERATOR_INSTALL_ID_START="+startPath,
		)
		processes[i].cmd.Stdout = &processes[i].output
		processes[i].cmd.Stderr = &processes[i].output
		if err := processes[i].cmd.Start(); err != nil {
			t.Fatalf("start helper %d: %v", i, err)
		}
	}

	deadline := time.Now().Add(10 * time.Second)
	for {
		ready := 0
		for i := range processes {
			if _, err := os.Stat(processes[i].ready); err == nil {
				ready++
			}
		}
		if ready == processCount {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("only %d/%d install-ID helpers reached the barrier", ready, processCount)
		}
		time.Sleep(5 * time.Millisecond)
	}
	if err := os.WriteFile(startPath, []byte("start"), 0o600); err != nil {
		t.Fatal(err)
	}

	var want string
	for i := range processes {
		if err := processes[i].cmd.Wait(); err != nil {
			t.Fatalf("helper %d: %v\n%s", i, err, processes[i].output.String())
		}
		const marker = "INSTALL_ID="
		output := processes[i].output.String()
		start := strings.Index(output, marker)
		if start < 0 {
			t.Fatalf("helper %d output missing install ID: %q", i, output)
		}
		id := strings.TrimSpace(strings.SplitN(output[start+len(marker):], "\n", 2)[0])
		if want == "" {
			want = id
		}
		if id != want {
			t.Fatalf("cross-process install IDs diverged: %q and %q", want, id)
		}
	}
	assertInstallIDFile(t, dataDir, want)
}

func TestLoadOrCreateInstallIDIsConsistentAcrossConcurrentCallers(t *testing.T) {
	dataDir := t.TempDir()
	start := make(chan struct{})
	results := make(chan string, 128)
	errs := make(chan error, 128)
	var wg sync.WaitGroup
	for i := 0; i < cap(results); i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			id, err := LoadOrCreateInstallID(dataDir)
			if err != nil {
				errs <- err
				return
			}
			results <- id
		}()
	}
	close(start)
	wg.Wait()
	close(results)
	close(errs)
	for err := range errs {
		t.Fatalf("load or create install id: %v", err)
	}
	var want string
	for id := range results {
		if want == "" {
			want = id
		}
		if id != want {
			t.Fatalf("concurrent install IDs diverged: %q and %q", want, id)
		}
	}
	assertInstallIDFile(t, dataDir, want)
}

func assertInstallIDFile(t *testing.T, dataDir, want string) {
	t.Helper()
	path := filepath.Join(dataDir, "telemetry_install_id")
	encodedID, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read final install ID: %v", err)
	}
	if got := strings.TrimSpace(string(encodedID)); got != want {
		t.Fatalf("final install ID = %q, want winning ID %q", got, want)
	}
	if runtime.GOOS == "windows" {
		return
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat final install ID: %v", err)
	}
	if permissions := info.Mode().Perm(); permissions&^os.FileMode(0o600) != 0 {
		t.Fatalf("final install ID permissions = %04o, want no broader than 0600", permissions)
	}
}

func TestLoadOrCreateInstallIDRejectsEmptyIdentityFile(t *testing.T) {
	dataDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dataDir, "telemetry_install_id"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadOrCreateInstallID(dataDir); err == nil {
		t.Fatal("empty install identity error = nil")
	}
}

func TestPostHogSinkCapturesEvent(t *testing.T) {
	requests := make(chan map[string]any, 1)
	sink, err := NewPostHogSink(t.TempDir(), "phc_test", "https://us.i.posthog.com", "", "", roundTripClient(func(req *http.Request) (*http.Response, error) {
		defer req.Body.Close()
		var body map[string]any
		if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
			return nil, err
		}
		requests <- body
		return &http.Response{
			StatusCode: http.StatusOK,
			Header:     make(http.Header),
			Body:       http.NoBody,
		}, nil
	}), nil)
	if err != nil {
		t.Fatalf("NewPostHogSink: %v", err)
	}

	projectID := domain.ProjectID("proj-1")
	sessionID := domain.SessionID("sess-1")
	sink.Emit(context.Background(), ports.TelemetryEvent{
		Name:       "opr.session.spawned",
		Source:     "session_service",
		OccurredAt: time.Unix(1700000000, 0).UTC(),
		Level:      ports.TelemetryLevelInfo,
		ProjectID:  &projectID,
		SessionID:  &sessionID,
		RequestID:  "req-1",
		Payload: map[string]any{
			"kind": "worker",
		},
	})
	if err := sink.Close(context.Background()); err != nil {
		t.Fatalf("Close: %v", err)
	}

	select {
	case req := <-requests:
		if got := req["event"]; got != "opr.session.spawned" {
			t.Fatalf("event = %#v, want opr.session.spawned", got)
		}
		props, ok := req["properties"].(map[string]any)
		if !ok {
			t.Fatalf("properties type = %T, want map[string]any", req["properties"])
		}
		if props["kind"] != "worker" {
			t.Fatalf("properties.kind = %#v, want worker", props["kind"])
		}
		if props["project_id_hash"] == "" || props["session_id_hash"] == "" {
			t.Fatalf("hashed ids missing from properties: %#v", props)
		}
		if props["$process_person_profile"] != false {
			t.Fatalf("properties.$process_person_profile = %#v, want false", props["$process_person_profile"])
		}
	case <-time.After(2 * time.Second):
		t.Fatal("PostHog sink did not send request")
	}
}

func TestPostHogSinkSanitizesPayloads(t *testing.T) {
	requests := make(chan map[string]any, 1)
	sink, err := NewPostHogSink(t.TempDir(), "phc_test", "https://us.i.posthog.com", "", "", roundTripClient(func(req *http.Request) (*http.Response, error) {
		defer req.Body.Close()
		var body map[string]any
		if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
			return nil, err
		}
		requests <- body
		return &http.Response{
			StatusCode: http.StatusOK,
			Header:     make(http.Header),
			Body:       http.NoBody,
		}, nil
	}), nil)
	if err != nil {
		t.Fatalf("NewPostHogSink: %v", err)
	}

	sink.Emit(context.Background(), ports.TelemetryEvent{
		Name:       "opr.daemon.panic",
		Source:     "http",
		OccurredAt: time.Unix(1700000000, 0).UTC(),
		Level:      ports.TelemetryLevelError,
		Payload: map[string]any{
			"component":         "httpd",
			"operation":         "http_request_panic",
			"method":            http.MethodGet,
			"path":              "/api/v1/sessions/demo",
			"panic_kind":        "error",
			"fingerprint":       "abc123",
			"stack_fingerprint": "def456",
			"panic":             "open /Users/name/private: no such file",
			"stack":             "stack trace with local path",
		},
	})
	if err := sink.Close(context.Background()); err != nil {
		t.Fatalf("Close: %v", err)
	}

	select {
	case req := <-requests:
		props, ok := req["properties"].(map[string]any)
		if !ok {
			t.Fatalf("properties type = %T, want map[string]any", req["properties"])
		}
		if props["component"] != "httpd" || props["operation"] != "http_request_panic" {
			t.Fatalf("sanitized properties = %#v, want allowlisted metadata", props)
		}
		if props["method"] != http.MethodGet || props["path"] != "/api/v1/sessions/demo" || props["panic_kind"] != "error" {
			t.Fatalf("sanitized properties = %#v, want allowlisted fields", props)
		}
		if props["fingerprint"] != "abc123" || props["stack_fingerprint"] != "def456" {
			t.Fatalf("sanitized properties = %#v, want exported fingerprints", props)
		}
		if _, ok := props["panic"]; ok {
			t.Fatalf("panic property should be dropped: %#v", props)
		}
		if _, ok := props["stack"]; ok {
			t.Fatalf("stack property should be dropped: %#v", props)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("PostHog sink did not send request")
	}
}

func TestPostHogSinkSanitizesAppActivePayload(t *testing.T) {
	requests := make(chan map[string]any, 1)
	sink, err := NewPostHogSink(t.TempDir(), "phc_test", "https://us.i.posthog.com", "", "", roundTripClient(func(req *http.Request) (*http.Response, error) {
		defer req.Body.Close()
		var body map[string]any
		if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
			return nil, err
		}
		requests <- body
		return &http.Response{
			StatusCode: http.StatusOK,
			Header:     make(http.Header),
			Body:       http.NoBody,
		}, nil
	}), nil)
	if err != nil {
		t.Fatalf("NewPostHogSink: %v", err)
	}

	sink.Emit(context.Background(), ports.TelemetryEvent{
		Name:       "opr.app.active",
		Source:     "cli",
		OccurredAt: time.Unix(1700000000, 0).UTC(),
		Level:      ports.TelemetryLevelInfo,
		Payload: map[string]any{
			"channel":      "cli",
			"command":      "spawn",
			"command_path": "opr spawn",
			"ip":           "203.0.113.10",
			"country":      "US",
			"city":         "San Francisco",
			"latitude":     37.7749,
			"longitude":    -122.4194,
		},
	})
	if err := sink.Close(context.Background()); err != nil {
		t.Fatalf("Close: %v", err)
	}

	select {
	case req := <-requests:
		if got := req["event"]; got != "opr.v2.app.active" {
			t.Fatalf("event = %#v, want opr.v2.app.active", got)
		}
		props, ok := req["properties"].(map[string]any)
		if !ok {
			t.Fatalf("properties type = %T, want map[string]any", req["properties"])
		}
		if props["legacy_event_name"] != "opr.app.active" {
			t.Fatalf("legacy_event_name = %#v, want opr.app.active", props["legacy_event_name"])
		}
		if props["telemetry_schema_version"] != float64(2) {
			t.Fatalf("telemetry_schema_version = %#v, want 2", props["telemetry_schema_version"])
		}
		if props["channel"] != "cli" || props["command"] != "spawn" || props["command_path"] != "opr spawn" {
			t.Fatalf("sanitized properties = %#v, want active CLI metadata", props)
		}
		for _, key := range []string{"ip", "country", "city", "latitude", "longitude"} {
			if _, ok := props[key]; ok {
				t.Fatalf("%s property should be dropped: %#v", key, props)
			}
		}
	case <-time.After(2 * time.Second):
		t.Fatal("PostHog sink did not send request")
	}
}

type roundTripClient func(*http.Request) (*http.Response, error)

func (f roundTripClient) Do(req *http.Request) (*http.Response, error) { return f(req) }

var _ postHogClient = roundTripClient(nil)

// Daemon events shipped with no version at all, so a session-spawn failure rate
// could not be attributed to a release. The supervisor supplies the version
// because the daemon binary has none that release tooling sets.
func TestPostHogSinkStampsAppVersionWhenSupplied(t *testing.T) {
	requests := make(chan map[string]any, 1)
	newSink := func(appVersion string) *PostHogSink {
		sink, err := NewPostHogSink(t.TempDir(), "phc_test", "https://us.i.posthog.com", appVersion, "", roundTripClient(func(req *http.Request) (*http.Response, error) {
			defer req.Body.Close()
			var body map[string]any
			if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
				return nil, err
			}
			requests <- body
			return &http.Response{StatusCode: http.StatusOK, Header: make(http.Header), Body: http.NoBody}, nil
		}), nil)
		if err != nil {
			t.Fatalf("NewPostHogSink: %v", err)
		}
		return sink
	}

	emit := func(sink *PostHogSink) map[string]any {
		sink.Emit(context.Background(), ports.TelemetryEvent{
			Name:       "opr.session.spawn_failed",
			Source:     "session_service",
			OccurredAt: time.Unix(1700000000, 0).UTC(),
			Level:      ports.TelemetryLevelError,
		})
		select {
		case body := <-requests:
			props, ok := body["properties"].(map[string]any)
			if !ok {
				t.Fatalf("properties type = %T, want map[string]any", body["properties"])
			}
			return props
		case <-time.After(2 * time.Second):
			t.Fatal("timed out waiting for capture")
			return nil
		}
	}

	props := emit(newSink(" 0.11.2 "))
	if props["app_version"] != "0.11.2" || props["ao_version"] != "0.11.2" {
		t.Fatalf("version properties = %#v / %#v, want trimmed 0.11.2", props["app_version"], props["ao_version"])
	}

	// An unset supervisor env var must leave the properties off rather than
	// reporting a misleading placeholder that would pollute version breakdowns.
	props = emit(newSink(""))
	if _, ok := props["app_version"]; ok {
		t.Fatalf("app_version present without the option: %#v", props["app_version"])
	}
	if _, ok := props["ao_version"]; ok {
		t.Fatalf("ao_version present without the option: %#v", props["ao_version"])
	}
}
