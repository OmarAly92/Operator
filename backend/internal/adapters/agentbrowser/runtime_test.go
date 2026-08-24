package agentbrowser

import (
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/service/browser"
)

func minimalPNG(width, height uint32) []byte {
	png := make([]byte, 33)
	copy(png, "\x89PNG\r\n\x1a\n")
	binary.BigEndian.PutUint32(png[8:], 13)
	copy(png[12:], "IHDR")
	binary.BigEndian.PutUint32(png[16:], width)
	binary.BigEndian.PutUint32(png[20:], height)
	png[24] = 8
	png[25] = 6
	return png
}

type stubEngine struct {
	mu         sync.Mutex
	resolution EngineResolution
	err        error
	calls      int
}

func (s *stubEngine) Resolve(context.Context) (EngineResolution, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.calls++
	return s.resolution, s.err
}

type callLog struct {
	mu    sync.Mutex
	items []CommandRequest
}

func (c *callLog) add(request CommandRequest) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.items = append(c.items, request)
}

func (c *callLog) snapshot() []CommandRequest {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make([]CommandRequest, len(c.items))
	copy(out, c.items)
	return out
}

func (c *callLog) commands() []string {
	var out []string
	for _, item := range c.snapshot() {
		if len(item.Args) > 0 {
			out = append(out, item.Args[0])
		}
	}
	return out
}

func jsonOK(payload string) (CommandResult, error) {
	return CommandResult{ExitCode: 0, Stdout: payload}, nil
}

func newTestAdapter(t *testing.T, mutate func(*Options)) (*Adapter, *callLog, *stubEngine, string) {
	t.Helper()
	stateRootDir := t.TempDir()
	dataDir := filepath.Join(t.TempDir(), "data")
	calls := &callLog{}
	engine := &stubEngine{}
	binary := filepath.Join(t.TempDir(), "agent-browser")
	if err := os.WriteFile(binary, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	options := Options{
		BinaryPath: binary,
		DataDir:    dataDir,
		StateRoot:  stateRootDir,
		Log:        discardTestLogger(),
		ParentEnv: map[string]string{
			"PATH":                  "/usr/bin:/bin",
			"LANG":                  "en_US.UTF-8",
			"AWS_SECRET_ACCESS_KEY": "should-not-cross",
			"HTTP_PROXY":            "http://user:secret@example.test:8080",
		},
		SocketAliasRoot: shortAliasRoot(),
		Runner: runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			calls.add(request)
			return jsonOK(`{"success":true,"data":{}}`)
		}),
	}
	if mutate != nil {
		mutate(&options)
	}
	if options.Engine == nil {
		engine.resolution = EngineResolution{Mode: "system"}
		options.Engine = engine
	}
	return New(options), calls, engine, stateRootDir
}

func runtimeRootFor(stateRoot string) string {
	return filepath.Join(stateRoot, "browser-runtime")
}

func mustExecute(t *testing.T, adapter *Adapter, sessionID, action string, args map[string]interface{}) browser.RuntimeResult {
	t.Helper()
	result, err := adapter.Execute(context.Background(), domain.SessionID(sessionID), action, args)
	if err != nil {
		t.Fatalf("Execute(%s) failed: %v", action, err)
	}
	return result
}

func requireCode(t *testing.T, err error, code string) {
	t.Helper()
	if err == nil {
		t.Fatalf("expected error %q, got nil", code)
	}
	var target browser.CommandError
	if !errors.As(err, &target) || target.Code != code {
		t.Fatalf("error = %v, want code %q", err, code)
	}
}

func discardTestLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

// shortAliasRoot mirrors production's /tmp alias base so the 103-byte unix
// socket path guard passes under long test temp directories.
func shortAliasRoot() string {
	if runtime.GOOS == "windows" {
		return os.TempDir()
	}
	return "/tmp"
}

func TestExecuteBuildsIsolatedPerSessionState(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("socket alias layout differs on windows")
	}
	adapter, calls, _, dataDir := newTestAdapter(t, nil)
	result := mustExecute(t, adapter, "opr-1", "snapshot", map[string]interface{}{})
	if result.RequestID == "" {
		t.Fatal("request id missing")
	}
	requests := calls.snapshot()
	if len(requests) != 1 || requests[0].Args[0] != "snapshot" {
		t.Fatalf("requests = %#v", requests)
	}
	env := requests[0].Env
	sessionDir := env["HOME"]
	runtimeRoot := runtimeRootFor(dataDir)
	if !strings.HasPrefix(sessionDir, runtimeRoot+string(filepath.Separator)) {
		t.Fatalf("HOME %q outside runtime root %q", sessionDir, runtimeRoot)
	}
	if filepath.Dir(sessionDir) == runtimeRoot {
		t.Fatalf("session state %q is not namespaced under a run root", sessionDir)
	}
	for name, want := range map[string]string{
		"USERPROFILE":                      sessionDir,
		"XDG_CONFIG_HOME":                  sessionDir,
		"XDG_CACHE_HOME":                   sessionDir,
		"TMPDIR":                           filepath.Join(sessionDir, "tmp"),
		"AGENT_BROWSER_AUTO_CONNECT":       "0",
		"AGENT_BROWSER_CONTENT_BOUNDARIES": "1",
		"AGENT_BROWSER_MAX_OUTPUT":         "50000",
		"AGENT_BROWSER_IDLE_TIMEOUT_MS":    "300000",
		"PATH":                             "/usr/bin:/bin",
	} {
		if env[name] != want {
			t.Fatalf("%s = %q, want %q", name, env[name], want)
		}
	}
	if _, exists := env["AWS_SECRET_ACCESS_KEY"]; exists {
		t.Fatal("parent secret crossed the process boundary")
	}
	if _, exists := env["HTTP_PROXY"]; exists {
		t.Fatal("parent proxy config crossed the process boundary")
	}
	namespace := env["AGENT_BROWSER_NAMESPACE"]
	if !regexp.MustCompile(`^opr-[0-9a-f]{4}-[0-9a-f]{12}$`).MatchString(namespace) {
		t.Fatalf("namespace = %q", namespace)
	}
	if env["AGENT_BROWSER_SESSION"] != namespace {
		t.Fatalf("session name = %q namespace = %q", env["AGENT_BROWSER_SESSION"], namespace)
	}
	if _, exists := env["AGENT_BROWSER_CDP"]; exists {
		t.Fatal("AGENT_BROWSER_CDP must never be set")
	}
	if _, exists := env["AGENT_BROWSER_EXECUTABLE_PATH"]; exists {
		t.Fatal("managed executable leaked into system-browser mode")
	}
	socketDir := env["AGENT_BROWSER_SOCKET_DIR"]
	info, err := os.Lstat(socketDir)
	if err != nil {
		t.Fatalf("socket dir missing: %v", err)
	}
	if info.Mode()&os.ModeSymlink != 0 {
		target, err := os.Readlink(socketDir)
		if err != nil {
			t.Fatal(err)
		}
		if !strings.HasPrefix(target, runtimeRoot) {
			t.Fatalf("socket alias target %q escapes runtime root", target)
		}
	}
	if _, err := os.Stat(filepath.Join(sessionDir, "config.json")); err != nil {
		t.Fatalf("session config missing: %v", err)
	}
	entries, err := os.ReadDir(runtimeRoot)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Fatalf("runtime root has %d entries, want 1 run root", len(entries))
	}
	ownerBytes, err := os.ReadFile(filepath.Join(runtimeRoot, entries[0].Name(), "owner.json"))
	if err != nil {
		t.Fatalf("owner marker missing: %v", err)
	}
	var owner runtimeOwner
	if err := json.Unmarshal(ownerBytes, &owner); err != nil {
		t.Fatal(err)
	}
	if owner.Marker != runtimeOwnerMarker || owner.PID <= 0 || len(owner.Token) != 32 {
		t.Fatalf("owner = %+v", owner)
	}
}

func TestExecuteGivesEachSessionItsOwnRootAndNamespace(t *testing.T) {
	calls := &callLog{}
	adapter, _, _, _ := newTestAdapter(t, func(options *Options) {
		options.Runner = runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			calls.add(request)
			return jsonOK(`{"success":true,"data":{"snapshot":"text"}}`)
		})
	})
	mustExecute(t, adapter, "opr-1", "snapshot", nil)
	mustExecute(t, adapter, "opr-2", "snapshot", nil)
	requests := calls.snapshot()
	if len(requests) != 2 {
		t.Fatalf("requests = %d", len(requests))
	}
	first, second := requests[0].Env, requests[1].Env
	if first["HOME"] == second["HOME"] {
		t.Fatal("sessions share a state directory")
	}
	if first["AGENT_BROWSER_NAMESPACE"] == second["AGENT_BROWSER_NAMESPACE"] {
		t.Fatal("sessions share a namespace")
	}
	if first["HOME"] != first["USERPROFILE"] || second["HOME"] != second["USERPROFILE"] {
		t.Fatal("profile roots diverge")
	}
}

func TestConcurrentFirstCommandsSerializeSessionCreation(t *testing.T) {
	calls := &callLog{}
	adapter, _, _, _ := newTestAdapter(t, func(options *Options) {
		options.Runner = runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			calls.add(request)
			time.Sleep(10 * time.Millisecond)
			return jsonOK(`{"success":true,"data":{}}`)
		})
	})
	var wg sync.WaitGroup
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := adapter.Execute(context.Background(), domain.SessionID("opr-1"), "snapshot", nil); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if got := len(calls.commands()); got != 6 {
		t.Fatalf("command count = %d", got)
	}
	sessionDirs := map[string]bool{}
	for _, request := range calls.snapshot() {
		sessionDirs[request.Env["HOME"]] = true
	}
	if len(sessionDirs) != 1 {
		t.Fatalf("concurrent init produced %d session dirs", len(sessionDirs))
	}
}

func TestExecuteAppendsJSONAndMarksUntrustedOutput(t *testing.T) {
	calls := &callLog{}
	adapter, _, _, _ := newTestAdapter(t, func(options *Options) {
		options.Runner = runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			calls.add(request)
			return jsonOK(`{"success":true,"data":{"snapshot":"page text"}}`)
		})
	})
	result := mustExecute(t, adapter, "opr-1", "snapshot", map[string]interface{}{"interactive": true})
	requests := calls.snapshot()
	last := requests[len(requests)-1]
	if got := last.Args; !reflect.DeepEqual(got, []string{"snapshot", "--interactive", "--compact", "--json"}) {
		t.Fatalf("args = %v", got)
	}
	value, ok := result.Value.(map[string]interface{})
	if !ok {
		t.Fatalf("value type = %T", result.Value)
	}
	if value["text"] != "page text" || value["untrustedExternalContent"] != true {
		t.Fatalf("value = %#v", value)
	}
}

func TestExecuteNormalizesConsoleAndErrorsMessages(t *testing.T) {
	adapter, _, _, _ := newTestAdapter(t, func(options *Options) {
		options.Runner = runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			if request.Args[0] == "console" {
				return jsonOK(`{"success":true,"data":{"messages":["hello",{"level":"error","message":"boom"}]}}`)
			}
			return jsonOK(`{"success":true,"data":{"messages":[{"type":"error","text":"ReferenceError"}]}}`)
		})
	})
	console := mustExecute(t, adapter, "opr-1", "console", nil).Value.(map[string]interface{})
	messages := console["messages"].([]map[string]interface{})
	if messages[0]["level"] != "log" || messages[1]["level"] != "error" {
		t.Fatalf("levels = %#v", messages)
	}
	for _, message := range messages {
		text := message["message"].(string)
		if !strings.Contains(text, "<<<BEGIN UNTRUSTED EXTERNAL CONTENT>>>") {
			t.Fatalf("unmarked message: %q", text)
		}
		if message["timestamp"] == "" {
			t.Fatal("timestamp missing")
		}
	}
	errValue := mustExecute(t, adapter, "opr-1", "errors", nil).Value.(map[string]interface{})
	errorMessages := errValue["messages"].([]map[string]interface{})
	if errorMessages[0]["level"] != "error" {
		t.Fatalf("errors level = %#v", errorMessages[0])
	}
}

func TestExecuteMapsTabsTabNewAndGetShapes(t *testing.T) {
	adapter, _, _, _ := newTestAdapter(t, func(options *Options) {
		options.Runner = runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			switch request.Args[0] {
			case "tab":
				if len(request.Args) > 1 && request.Args[1] == "new" {
					return jsonOK(`{"success":true,"data":{"tabId":"t2","url":"about:blank","title":""}}`)
				}
				return jsonOK(`{"success":true,"data":{"tabs":[{"id":"t1","url":"http://127.0.0.1:9/","title":"Fixture","active":true},{"id":"t2","url":"about:blank","title":"","active":false}]}}`)
			case "get":
				return jsonOK(`{"success":true,"data":{"text":"saved"}}`)
			case "open":
				return jsonOK(`{"success":true,"data":{"url":"http://127.0.0.1:9/","title":"Fixture"}}`)
			default:
				return jsonOK(`{"success":true,"data":{}}`)
			}
		})
	})
	tabs := mustExecute(t, adapter, "opr-1", "tabs", nil).Value.(map[string]interface{})
	tabList := tabs["tabs"].([]map[string]interface{})
	if len(tabList) != 2 || tabList[0]["id"] != "t1" || tabList[0]["active"] != true {
		t.Fatalf("tabs = %#v", tabs)
	}
	if tabs["activeTabId"] != "t1" || tabs["untrustedExternalContent"] != true {
		t.Fatalf("tabs envelope = %#v", tabs)
	}
	tabNew := mustExecute(t, adapter, "opr-1", "tab-new", nil).Value.(map[string]interface{})
	if tabNew["id"] != "t2" || tabNew["active"] != true {
		t.Fatalf("tab-new = %#v", tabNew)
	}
	get := mustExecute(t, adapter, "opr-1", "get", map[string]interface{}{"property": "text"}).Value.(map[string]interface{})
	if get["value"] != "saved" {
		t.Fatalf("get = %#v", get)
	}
	opened := mustExecute(t, adapter, "opr-1", "open", map[string]interface{}{"url": "http://127.0.0.1:9/"}).Value.(map[string]interface{})
	if opened["url"] != "http://127.0.0.1:9/" || opened["untrustedExternalContent"] != true {
		t.Fatalf("open = %#v", opened)
	}
}

func TestExecuteSurfacesCommandFailuresWithStableCodes(t *testing.T) {
	adapter, _, _, _ := newTestAdapter(t, func(options *Options) {
		options.Runner = runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			return CommandResult{ExitCode: 1, Stderr: "daemon transport failed"}, nil
		})
	})
	_, err := adapter.Execute(context.Background(), domain.SessionID("opr-1"), "snapshot", nil)
	requireCode(t, err, "AGENT_BROWSER_COMMAND_FAILED")
	if !strings.Contains(err.Error(), "daemon transport failed") {
		t.Fatalf("error lost stderr: %v", err)
	}
}

func TestExecuteFailsClosedWhenBinaryMissing(t *testing.T) {
	calls := &callLog{}
	adapter, _, _, _ := newTestAdapter(t, func(options *Options) {
		options.BinaryPath = filepath.Join(t.TempDir(), "absent")
	})
	_, err := adapter.Execute(context.Background(), domain.SessionID("opr-1"), "snapshot", nil)
	requireCode(t, err, "AGENT_BROWSER_NOT_INSTALLED")
	if len(calls.commands()) != 0 {
		t.Fatal("runner invoked without binary")
	}
}

func TestExecuteRejectsDesktopPanelOnlyActions(t *testing.T) {
	cases := []struct {
		action string
		code   string
	}{
		{"devtools-open", "BROWSER_DEVTOOLS_UNAVAILABLE"},
		{"devtools-close", "BROWSER_DEVTOOLS_UNAVAILABLE"},
		{"network-start", "BROWSER_AUTOMATION_UNAVAILABLE"},
		{"unhighlight", "BROWSER_AUTOMATION_UNAVAILABLE"},
	}
	for _, tc := range cases {
		adapter, calls, _, _ := newTestAdapter(t, nil)
		_, err := adapter.Execute(context.Background(), domain.SessionID("opr-1"), tc.action, nil)
		requireCode(t, err, tc.code)
		if len(calls.commands()) != 0 {
			t.Fatalf("%s reached the binary", tc.action)
		}
	}
}

func TestExecuteUsesManagedEngineExecutablePath(t *testing.T) {
	adapter, calls, engine, _ := newTestAdapter(t, nil)
	engine.resolution = EngineResolution{Mode: "managed", ExecutablePath: "/engine/chrome"}
	mustExecute(t, adapter, "opr-1", "snapshot", nil)
	env := calls.snapshot()[0].Env
	if env["AGENT_BROWSER_EXECUTABLE_PATH"] != "/engine/chrome" {
		t.Fatalf("executable path = %q", env["AGENT_BROWSER_EXECUTABLE_PATH"])
	}
}

func TestExecutePropagatesEngineFailure(t *testing.T) {
	adapter, calls, engine, _ := newTestAdapter(t, nil)
	engine.err = browser.CommandError{Code: "AGENT_BROWSER_INSTALL_FAILED", Message: "offline"}
	_, err := adapter.Execute(context.Background(), domain.SessionID("opr-1"), "snapshot", nil)
	requireCode(t, err, "AGENT_BROWSER_INSTALL_FAILED")
	if len(calls.commands()) != 0 {
		t.Fatal("runner invoked despite engine failure")
	}
}

func TestStatusReportsBinaryReadiness(t *testing.T) {
	present := filepath.Join(t.TempDir(), "agent-browser")
	if err := os.WriteFile(present, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	ready := New(Options{BinaryPath: present, DataDir: filepath.Join(t.TempDir(), "data"), Log: discardTestLogger()})
	if status := ready.Status(domain.SessionID("opr-1")); !status.Ready {
		t.Fatalf("status = %#v", status)
	}
	missing := New(Options{BinaryPath: filepath.Join(t.TempDir(), "absent"), DataDir: filepath.Join(t.TempDir(), "data"), Log: discardTestLogger()})
	if status := missing.Status(domain.SessionID("opr-1")); status.Ready {
		t.Fatalf("status = %#v", status)
	}
}

func TestDestroySessionClosesBrowserAndRemovesStateSafely(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("socket alias layout differs on windows")
	}
	var closeCalls int32
	calls := &callLog{}
	adapter, _, _, dataDir := newTestAdapter(t, func(options *Options) {
		options.Runner = runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			calls.add(request)
			if request.Args[0] == "close" {
				atomic.AddInt32(&closeCalls, 1)
				return CommandResult{ExitCode: 1, Stderr: "already closed"}, nil
			}
			return jsonOK(`{"success":true,"data":{}}`)
		})
	})
	mustExecute(t, adapter, "opr-1", "snapshot", nil)
	sessionHome := calls.snapshot()[0].Env["HOME"]
	if err := adapter.DestroySession(context.Background(), domain.SessionID("opr-1")); err != nil {
		t.Fatalf("destroy failed: %v", err)
	}
	if _, err := os.Stat(sessionHome); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("session state survived teardown: %v", err)
	}
	if atomic.LoadInt32(&closeCalls) != 1 {
		t.Fatalf("close calls = %d", closeCalls)
	}
	if err := adapter.DestroySession(context.Background(), domain.SessionID("opr-1")); err != nil {
		t.Fatalf("second destroy failed: %v", err)
	}
	if atomic.LoadInt32(&closeCalls) != 1 {
		t.Fatalf("close calls after idle destroy = %d", closeCalls)
	}
	entries, err := os.ReadDir(runtimeRootFor(dataDir))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Fatalf("run root survived final teardown: %v", entries)
	}
}

func TestDestroySessionSurvivesCloseTimeout(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("process semantics differ on windows")
	}
	script := writeScript(t, "#!/bin/sh\ncase \"$1\" in close) sleep 30 ;; *) echo '{\"success\":true,\"data\":{}}' ;; esac\n")
	adapter, _, _, _ := newTestAdapter(t, func(options *Options) {
		options.BinaryPath = script
		options.Runner = nil
		options.CloseTimeout = 300 * time.Millisecond
	})
	mustExecute(t, adapter, "opr-1", "snapshot", nil)
	started := time.Now()
	if err := adapter.DestroySession(context.Background(), domain.SessionID("opr-1")); err != nil {
		t.Fatalf("destroy failed: %v", err)
	}
	if elapsed := time.Since(started); elapsed > 3*time.Second {
		t.Fatalf("destroy waited %v for a hung close", elapsed)
	}
}

func TestDestroySessionDeduplicatesConcurrentTeardown(t *testing.T) {
	var closes int32
	adapter, _, _, _ := newTestAdapter(t, func(options *Options) {
		options.Runner = runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			time.Sleep(20 * time.Millisecond)
			if request.Args[0] == "close" {
				atomic.AddInt32(&closes, 1)
			}
			return jsonOK(`{"success":true,"data":{}}`)
		})
	})
	mustExecute(t, adapter, "opr-1", "snapshot", nil)
	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := adapter.DestroySession(context.Background(), domain.SessionID("opr-1")); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if atomic.LoadInt32(&closes) != 1 {
		t.Fatalf("concurrent destroys issued %d close commands", closes)
	}
}

func TestScreenshotReturnsBase64DimensionsAndCleansUp(t *testing.T) {
	png := minimalPNG(3, 2)
	adapter, _, _, _ := newTestAdapter(t, func(options *Options) {
		options.Runner = runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			if request.Args[0] != "screenshot" {
				return jsonOK(`{"success":true,"data":{}}`)
			}
			target := request.Args[1]
			if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
				return CommandResult{}, err
			}
			if err := os.WriteFile(target, png, 0o600); err != nil {
				return CommandResult{}, err
			}
			return jsonOK(`{"success":true,"data":{}}`)
		})
	})
	result := mustExecute(t, adapter, "opr-1", "screenshot", nil).Value.(map[string]interface{})
	if result["width"] != float64(3) || result["height"] != float64(2) {
		t.Fatalf("dimensions = %#v", result)
	}
	decoded, err := base64.StdEncoding.DecodeString(result["data"].(string))
	if err != nil || string(decoded) != string(png) {
		t.Fatalf("screenshot bytes mismatch: %v", err)
	}
	if result["untrustedExternalContent"] != true {
		t.Fatalf("envelope = %#v", result)
	}
}

func TestScreenshotRejectsOversizedCapture(t *testing.T) {
	big := append(minimalPNG(3, 2), make([]byte, maxScreenshotBytes+1)...)
	adapter, _, _, _ := newTestAdapter(t, func(options *Options) {
		options.Runner = runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			target := request.Args[1]
			if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
				return CommandResult{}, err
			}
			return CommandResult{ExitCode: 0}, os.WriteFile(target, big, 0o600)
		})
	})
	_, err := adapter.Execute(context.Background(), domain.SessionID("opr-1"), "screenshot", nil)
	requireCode(t, err, "AGENT_BROWSER_OUTPUT_TOO_LARGE")
}

func TestExecuteRejectsInvalidPNGScreenshots(t *testing.T) {
	adapter, _, _, _ := newTestAdapter(t, func(options *Options) {
		options.Runner = runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			target := request.Args[1]
			if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
				return CommandResult{}, err
			}
			return CommandResult{ExitCode: 0}, os.WriteFile(target, []byte("not a png"), 0o600)
		})
	})
	_, err := adapter.Execute(context.Background(), domain.SessionID("opr-1"), "screenshot", nil)
	requireCode(t, err, "AGENT_BROWSER_INVALID_OUTPUT")
}

func TestScavengeRuntimeRunsRemovesOnlyConfirmedDeadRoots(t *testing.T) {
	root := t.TempDir()
	dead := filepath.Join(root, "run-101-"+strings.Repeat("a", 12))
	alive := filepath.Join(root, "run-202-"+strings.Repeat("b", 12))
	malformed := filepath.Join(root, "run-303-"+strings.Repeat("c", 12))
	unmarked := filepath.Join(root, "run-404-"+strings.Repeat("d", 12))
	foreign := filepath.Join(root, "unrelated")
	for _, dir := range []string{dead, alive, malformed, unmarked, foreign} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	staleTime := time.Now().Add(-reclaimGrace - time.Minute)
	writeOwner(t, dead, 101)
	writeOwner(t, alive, 202)
	if err := os.WriteFile(filepath.Join(malformed, "owner.json"), []byte("not-json"), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, dir := range []string{dead, alive} {
		if err := os.Chtimes(filepath.Join(dir, "owner.json"), staleTime, staleTime); err != nil {
			t.Fatal(err)
		}
	}
	ScavengeRuntimeRuns(root, func(pid int) bool { return pid == 202 }, discardTestLogger())
	entries, err := os.ReadDir(root)
	if err != nil {
		t.Fatal(err)
	}
	names := map[string]bool{}
	for _, entry := range entries {
		names[entry.Name()] = true
	}
	want := map[string]bool{
		filepath.Base(alive):     true,
		filepath.Base(malformed): true,
		filepath.Base(unmarked):  true,
		filepath.Base(foreign):   true,
	}
	if !reflect.DeepEqual(names, want) {
		t.Fatalf("remaining = %v want %v", names, want)
	}
}

func TestScavengeRuntimeRunsKeepsFreshDeadOwnerWithinGrace(t *testing.T) {
	root := t.TempDir()
	fresh := filepath.Join(root, "run-101-"+strings.Repeat("e", 12))
	if err := os.MkdirAll(fresh, 0o755); err != nil {
		t.Fatal(err)
	}
	writeOwner(t, fresh, 101)
	ScavengeRuntimeRuns(root, func(int) bool { return false }, discardTestLogger())
	if _, err := os.Stat(fresh); err != nil {
		t.Fatalf("fresh dead root removed within grace: %v", err)
	}
}

func TestScavengeSocketAliasesRemovesOnlyOwnedAliases(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("symlink aliases are a unix affordance")
	}
	stateRoot := t.TempDir()
	aliasRoot := t.TempDir()
	deadTarget := filepath.Join(stateRoot, "browser-runtime", "run-101-"+strings.Repeat("a", 12), "s")
	liveTarget := filepath.Join(stateRoot, "browser-runtime", "run-202-"+strings.Repeat("b", 12), "s")
	foreignTarget := filepath.Join(t.TempDir(), "elsewhere", "s")
	for _, dir := range []string{deadTarget, liveTarget, foreignTarget} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	link := func(name, target string) {
		t.Helper()
		if err := os.Symlink(target, filepath.Join(aliasRoot, name)); err != nil {
			t.Fatal(err)
		}
	}
	link("opr-br-101-"+strings.Repeat("a", 12), deadTarget)
	link("opr-br-202-"+strings.Repeat("b", 12), liveTarget)
	link("opr-br-303-"+strings.Repeat("c", 12), foreignTarget)
	link("opr-br-not-owned", deadTarget)
	link("unrelated", deadTarget)
	ScavengeSocketAliases(aliasRoot, stateRoot, func(pid int) bool { return pid == 202 }, discardTestLogger())
	remaining, err := os.ReadDir(aliasRoot)
	if err != nil {
		t.Fatal(err)
	}
	names := map[string]bool{}
	for _, entry := range remaining {
		names[entry.Name()] = true
	}
	want := map[string]bool{
		"opr-br-202-" + strings.Repeat("b", 12): true,
		"opr-br-303-" + strings.Repeat("c", 12): true,
		"opr-br-not-owned":                      true,
		"unrelated":                             true,
	}
	if !reflect.DeepEqual(names, want) {
		t.Fatalf("remaining aliases = %v want %v", names, want)
	}
}

func TestExecuteTriggersStaleRunScavenging(t *testing.T) {
	adapter, calls, _, dataDir := newTestAdapter(t, nil)
	runtimeRoot := runtimeRootFor(dataDir)
	stale := filepath.Join(runtimeRoot, "run-999-"+strings.Repeat("f", 12))
	if err := os.MkdirAll(stale, 0o755); err != nil {
		t.Fatal(err)
	}
	writeOwner(t, stale, 999)
	staleTime := time.Now().Add(-reclaimGrace - time.Minute)
	if err := os.Chtimes(filepath.Join(stale, "owner.json"), staleTime, staleTime); err != nil {
		t.Fatal(err)
	}
	mustExecute(t, adapter, "opr-1", "snapshot", nil)
	if _, err := os.Stat(stale); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("stale run root survived a live command: %v", err)
	}
	if len(calls.commands()) == 0 {
		t.Fatal("command never ran")
	}
}

func TestExecuteTouchesRunOwnerHeartbeat(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("timestamp granularity differs on windows")
	}
	adapter, _, _, dataDir := newTestAdapter(t, nil)
	runtimeRoot := runtimeRootFor(dataDir)
	mustExecute(t, adapter, "opr-1", "snapshot", nil)
	entries, err := os.ReadDir(runtimeRoot)
	if err != nil {
		t.Fatal(err)
	}
	ownerPath := filepath.Join(runtimeRoot, entries[0].Name(), "owner.json")
	before, err := os.Stat(ownerPath)
	if err != nil {
		t.Fatal(err)
	}
	time.Sleep(60 * time.Millisecond)
	mustExecute(t, adapter, "opr-1", "get", map[string]interface{}{"property": "url"})
	after, err := os.Stat(ownerPath)
	if err != nil {
		t.Fatal(err)
	}
	if !after.ModTime().After(before.ModTime()) {
		t.Fatalf("heartbeat not touched: before=%v after=%v", before.ModTime(), after.ModTime())
	}
}

func TestProcessRunnerCapturesOutputAndExitCode(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell fixtures are unix-only")
	}
	script := writeScript(t, "#!/bin/sh\necho out-line\necho err-line >&2\nexit 3\n")
	runner := newProcessRunner(discardTestLogger())
	result, err := runner.Run(context.Background(), CommandRequest{
		Path: script,
		Args: []string{"ignored"},
		Env:  map[string]string{"PATH": "/usr/bin:/bin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.ExitCode != 3 || result.Stdout != "out-line\n" || result.Stderr != "err-line\n" {
		t.Fatalf("result = %#v", result)
	}
}

func TestProcessRunnerKillsOnTimeout(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell fixtures are unix-only")
	}
	script := writeScript(t, "#!/bin/sh\nsleep 30\n")
	runner := newProcessRunner(discardTestLogger())
	started := time.Now()
	_, err := runner.Run(context.Background(), CommandRequest{
		Path:    script,
		Args:    []string{"ignored"},
		Env:     map[string]string{"PATH": "/usr/bin:/bin"},
		Timeout: 200 * time.Millisecond,
	})
	requireCode(t, err, "AGENT_BROWSER_TIMEOUT")
	if elapsed := time.Since(started); elapsed > 5*time.Second {
		t.Fatalf("timeout kill took %v", elapsed)
	}
}

func TestProcessRunnerKillsOnCancellation(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell fixtures are unix-only")
	}
	script := writeScript(t, "#!/bin/sh\nsleep 30\n")
	runner := newProcessRunner(discardTestLogger())
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		time.Sleep(100 * time.Millisecond)
		cancel()
	}()
	_, err := runner.Run(ctx, CommandRequest{
		Path: script,
		Args: []string{"ignored"},
		Env:  map[string]string{"PATH": "/usr/bin:/bin"},
	})
	requireCode(t, err, "AGENT_BROWSER_CANCELLED")
}

func TestProcessRunnerCapsOutput(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell fixtures are unix-only")
	}
	script := writeScript(t, "#!/bin/sh\nhead -c 2097152 /dev/zero | tr '\\0' x\n")
	runner := newProcessRunner(discardTestLogger())
	_, err := runner.Run(context.Background(), CommandRequest{
		Path: script,
		Args: []string{"ignored"},
		Env:  map[string]string{"PATH": "/usr/bin:/bin"},
	})
	requireCode(t, err, "AGENT_BROWSER_OUTPUT_TOO_LARGE")
}

func TestProcessRunnerReportsSpawnFailure(t *testing.T) {
	runner := newProcessRunner(discardTestLogger())
	_, err := runner.Run(context.Background(), CommandRequest{
		Path: filepath.Join(t.TempDir(), "missing-binary"),
		Env:  map[string]string{},
	})
	requireCode(t, err, "AGENT_BROWSER_START_FAILED")
}

func writeScript(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "fixture-agent-browser.sh")
	if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func writeOwner(t *testing.T, dir string, pid int) {
	t.Helper()
	payload, _ := json.Marshal(runtimeOwner{
		Marker:    runtimeOwnerMarker,
		PID:       pid,
		StartedAt: time.Now().UTC().Format(time.RFC3339),
		Token:     strings.Repeat("a", 32),
	})
	if err := os.WriteFile(filepath.Join(dir, "owner.json"), payload, 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestResolveStateRootPrefersExplicitOverrideAndCanonicalFallback(t *testing.T) {
	explicit := resolveStateRoot(Options{StateRoot: "/explicit/root"})
	if explicit != "/explicit/root" {
		t.Fatalf("explicit state root = %q", explicit)
	}
	home, err := os.UserHomeDir()
	if err != nil {
		t.Skip("no home directory available")
	}
	if got := resolveStateRoot(Options{}); got != filepath.Join(home, ".operator") {
		t.Fatalf("canonical fallback = %q, want %q", got, filepath.Join(home, ".operator"))
	}
}

func TestExecutePlacesRuntimeUnderConfiguredStateRoot(t *testing.T) {
	stateRootDir := t.TempDir()
	dataDir := filepath.Join(t.TempDir(), "override", "operator-data")
	calls := &callLog{}
	adapter, _, _, _ := newTestAdapter(t, func(options *Options) {
		options.DataDir = dataDir
		options.StateRoot = stateRootDir
		options.Runner = runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			calls.add(request)
			return jsonOK(`{"success":true,"data":{}}`)
		})
	})
	mustExecute(t, adapter, "opr-1", "snapshot", nil)
	requests := calls.snapshot()
	if len(requests) != 1 {
		t.Fatalf("requests = %d", len(requests))
	}
	sessionHome := requests[0].Env["HOME"]
	wantBase := filepath.Join(stateRootDir, "browser-runtime")
	if !strings.HasPrefix(sessionHome, wantBase+string(filepath.Separator)) {
		t.Fatalf("session HOME %q outside configured state-root base %q", sessionHome, wantBase)
	}
	if strings.Contains(sessionHome, "override") {
		t.Fatalf("session HOME %q leaked into the data-dir override tree", sessionHome)
	}
}
