package agentbrowser

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"
)

type runFunc func(ctx context.Context, request CommandRequest) (CommandResult, error)

func (f runFunc) Run(ctx context.Context, request CommandRequest) (CommandResult, error) {
	return f(ctx, request)
}

type runnerSpy struct {
	mu    sync.Mutex
	calls []CommandRequest
}

func (s *runnerSpy) record(request CommandRequest) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.calls = append(s.calls, request)
}

func (s *runnerSpy) count() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.calls)
}

func (s *runnerSpy) commands() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]string, 0, len(s.calls))
	for _, call := range s.calls {
		if len(call.Args) > 0 {
			out = append(out, call.Args[0])
		}
	}
	return out
}

func doctorResult(success bool, browserPass bool) CommandResult {
	checks := []map[string]string{{"id": "node", "category": "runtime", "status": "pass"}}
	if browserPass {
		checks = append(checks, map[string]string{"id": "chrome-discovery", "category": "browser", "status": "pass"})
	} else {
		checks = append(checks, map[string]string{"id": "chrome-discovery", "category": "browser", "status": "fail"})
	}
	payload, _ := json.Marshal(map[string]interface{}{"success": success, "checks": checks})
	return CommandResult{ExitCode: 0, Stdout: string(payload)}
}

func managedExecutableName(platform string) string {
	switch platform {
	case "darwin":
		return "Google Chrome for Testing"
	case "windows":
		return "chrome.exe"
	default:
		return "chrome-linux64/chrome"
	}
}

func seedManagedBrowserForPlatform(t *testing.T, root, platform string) string {
	t.Helper()
	executable := filepath.Join(root, ".agent-browser", "browsers", "chromium-1491", managedExecutableName(platform))
	if err := os.MkdirAll(filepath.Dir(executable), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(executable, []byte("mock-chromium"), 0o755); err != nil {
		t.Fatal(err)
	}
	return executable
}

// newTestEngine builds an Engine over a temp engine root; the responder receives
// the engine root so it can simulate agent-browser's own download layout.
func newTestEngine(t *testing.T, responder func(request CommandRequest, engineRoot string) (CommandResult, error)) (*Engine, *runnerSpy, string) {
	t.Helper()
	engineRoot := filepath.Join(t.TempDir(), "browser-engine")
	spy := &runnerSpy{}
	engine := NewEngine(EngineOptions{
		EngineRoot: engineRoot,
		BinaryPath: "/packaged/agent-browser",
		Runner: runFunc(func(ctx context.Context, request CommandRequest) (CommandResult, error) {
			spy.record(request)
			return responder(request, engineRoot)
		}),
		Log: discardTestLogger(),
	})
	return engine, spy, engineRoot
}

func TestEngineResolvePrefersDiscoveredSystemBrowser(t *testing.T) {
	engine, spy, engineRoot := newTestEngine(t, func(CommandRequest, string) (CommandResult, error) {
		return doctorResult(true, true), nil
	})
	resolution, err := engine.Resolve(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if resolution.Mode != "system" || resolution.ExecutablePath != "" {
		t.Fatalf("resolution = %#v", resolution)
	}
	got := spy.commands()
	if len(got) != 1 || got[0] != "doctor" {
		t.Fatalf("commands = %v", got)
	}
	for _, call := range spy.calls {
		assertEngineEnv(t, call.Env, engineRoot)
	}
}

func TestEngineResolveInstallsManagedEngineWhenSystemBrowserAbsent(t *testing.T) {
	engine, spy, engineRoot := newTestEngine(t, func(request CommandRequest, root string) (CommandResult, error) {
		switch request.Args[0] {
		case "doctor":
			return doctorResult(false, false), nil
		case "install":
			seedManagedBrowserForPlatform(t, root, runtime.GOOS)
			return CommandResult{ExitCode: 0, Stdout: `{"success":true}`}, nil
		default:
			return CommandResult{ExitCode: 1, Stderr: "unexpected command"}, nil
		}
	})
	resolution, err := engine.Resolve(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if resolution.Mode != "managed" {
		t.Fatalf("resolution = %#v", resolution)
	}
	wantSuffix := managedExecutableName(runtime.GOOS)
	if !strings.HasSuffix(resolution.ExecutablePath, wantSuffix) {
		t.Fatalf("executable = %q want suffix %q", resolution.ExecutablePath, wantSuffix)
	}
	if !pathWithin(engineRoot, resolution.ExecutablePath) {
		t.Fatalf("executable escaped engine root: %q", resolution.ExecutablePath)
	}
	got := spy.commands()
	if len(got) != 2 || got[0] != "doctor" || got[1] != "install" {
		t.Fatalf("commands = %v", got)
	}
	assertEngineEnv(t, spy.calls[1].Env, engineRoot)
	manifestBytes, err := os.ReadFile(filepath.Join(engineRoot, "manifest.json"))
	if err != nil {
		t.Fatalf("manifest missing: %v", err)
	}
	var manifest engineManifest
	if err := json.Unmarshal(manifestBytes, &manifest); err != nil {
		t.Fatal(err)
	}
	if manifest.Version != PinnedAgentBrowserVersion {
		t.Fatalf("manifest version = %q", manifest.Version)
	}
	found := false
	for _, file := range manifest.Files {
		if strings.HasSuffix(file.Path, wantSuffix) {
			found = true
		}
	}
	if !found || len(manifest.Files) == 0 {
		t.Fatalf("manifest missing executable entry: %#v", manifest.Files)
	}
}

func TestEngineResolveReusesVerifiedInstallWithoutReinstalling(t *testing.T) {
	engine, spy, _ := newTestEngine(t, func(request CommandRequest, root string) (CommandResult, error) {
		switch request.Args[0] {
		case "doctor":
			return doctorResult(false, false), nil
		case "install":
			seedManagedBrowserForPlatform(t, root, runtime.GOOS)
			return CommandResult{ExitCode: 0, Stdout: `{"success":true}`}, nil
		default:
			return CommandResult{ExitCode: 1}, nil
		}
	})
	if _, err := engine.Resolve(context.Background()); err != nil {
		t.Fatal(err)
	}
	first := spy.count()
	resolution, err := engine.Resolve(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if resolution.Mode != "managed" {
		t.Fatalf("second resolution = %#v", resolution)
	}
	if spy.count() != first {
		t.Fatalf("re-resolution spawned %d extra commands", spy.count()-first)
	}
}

func TestEngineResolveSerializesConcurrentDiscoveryAndInstall(t *testing.T) {
	engine, spy, _ := newTestEngine(t, func(request CommandRequest, root string) (CommandResult, error) {
		switch request.Args[0] {
		case "doctor":
			time.Sleep(20 * time.Millisecond)
			return doctorResult(false, false), nil
		case "install":
			time.Sleep(30 * time.Millisecond)
			seedManagedBrowserForPlatform(t, root, runtime.GOOS)
			return CommandResult{ExitCode: 0, Stdout: `{"success":true}`}, nil
		default:
			return CommandResult{ExitCode: 1}, nil
		}
	})
	var wg sync.WaitGroup
	errCh := make(chan error, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			resolution, err := engine.Resolve(context.Background())
			if err != nil {
				errCh <- err
				return
			}
			if resolution.Mode != "managed" {
				errCh <- fmt.Errorf("resolution mode = %q", resolution.Mode)
			}
		}()
	}
	wg.Wait()
	close(errCh)
	for err := range errCh {
		t.Fatal(err)
	}
	got := spy.commands()
	if len(got) != 2 || got[0] != "doctor" || got[1] != "install" {
		t.Fatalf("concurrent resolves produced %d commands (%v); want one doctor+install", len(got), got)
	}
}

func TestEngineResolveCleansPartialInstallBeforeDownloading(t *testing.T) {
	engine, _, engineRoot := newTestEngine(t, func(request CommandRequest, root string) (CommandResult, error) {
		if request.Args[0] == "install" {
			seedManagedBrowserForPlatform(t, root, runtime.GOOS)
			return CommandResult{ExitCode: 0, Stdout: `{"success":true}`}, nil
		}
		return doctorResult(false, false), nil
	})
	stale := filepath.Join(engineRoot, ".agent-browser", "browsers", "chromium-old.partial")
	if err := os.MkdirAll(filepath.Dir(stale), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(stale, []byte("junk"), 0o644); err != nil {
		t.Fatal(err)
	}
	partialDownload := filepath.Join(engineRoot, ".agent-browser", "browsers", "chrome.download")
	if err := os.WriteFile(partialDownload, []byte("half"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := engine.Resolve(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(stale); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("stale partial survived: %v", err)
	}
	if _, err := os.Stat(partialDownload); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("partial download survived: %v", err)
	}
	if _, err := os.Stat(filepath.Join(engineRoot, "manifest.json")); err != nil {
		t.Fatalf("fresh manifest missing: %v", err)
	}
}

func TestEngineResolveReinstallsWhenPinnedVersionMismatched(t *testing.T) {
	engine, spy, engineRoot := newTestEngine(t, func(request CommandRequest, root string) (CommandResult, error) {
		if request.Args[0] == "install" {
			seedManagedBrowserForPlatform(t, root, runtime.GOOS)
			return CommandResult{ExitCode: 0, Stdout: `{"success":true}`}, nil
		}
		return doctorResult(false, false), nil
	})
	seedManagedBrowserForPlatform(t, engineRoot, runtime.GOOS)
	writeManifest(t, engineRoot, "0.0.1-stale")
	before := spy.count()
	resolution, err := engine.Resolve(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if resolution.Mode != "managed" {
		t.Fatalf("resolution = %#v", resolution)
	}
	if spy.count() <= before {
		t.Fatal("version mismatch did not trigger a reinstall")
	}
	if got := spy.commands()[spy.count()-1]; got != "install" {
		t.Fatalf("last command = %q", got)
	}
}

func TestEngineResolveReinstallsWhenChecksumMismatched(t *testing.T) {
	engine, spy, engineRoot := newTestEngine(t, func(request CommandRequest, root string) (CommandResult, error) {
		if request.Args[0] == "install" {
			seedManagedBrowserForPlatform(t, root, runtime.GOOS)
			return CommandResult{ExitCode: 0, Stdout: `{"success":true}`}, nil
		}
		return doctorResult(false, false), nil
	})
	seededExecutable := seedManagedBrowserForPlatform(t, engineRoot, runtime.GOOS)
	writeManifest(t, engineRoot, PinnedAgentBrowserVersion)
	if err := os.WriteFile(seededExecutable, []byte("tampered"), 0o755); err != nil {
		t.Fatal(err)
	}
	before := spy.count()
	if _, err := engine.Resolve(context.Background()); err != nil {
		t.Fatal(err)
	}
	if spy.count() <= before {
		t.Fatal("checksum mismatch did not trigger a reinstall")
	}
}

func TestEngineResolveFailsClosedWhenInstallFails(t *testing.T) {
	engine, _, _ := newTestEngine(t, func(request CommandRequest, _ string) (CommandResult, error) {
		if request.Args[0] == "install" {
			return CommandResult{ExitCode: 1, Stderr: "network unreachable"}, nil
		}
		return doctorResult(false, false), nil
	})
	_, err := engine.Resolve(context.Background())
	if commandErrorCode(err) != "AGENT_BROWSER_INSTALL_FAILED" {
		t.Fatalf("install failure error = %v", err)
	}
	if !strings.Contains(err.Error(), "network unreachable") {
		t.Fatalf("error lost installer stderr: %v", err)
	}
}

func TestEngineResolveFailsClosedWhenInstalledExecutableMissing(t *testing.T) {
	engine, _, _ := newTestEngine(t, func(request CommandRequest, _ string) (CommandResult, error) {
		if request.Args[0] == "install" {
			return CommandResult{ExitCode: 0, Stdout: `{"success":true}`}, nil
		}
		return doctorResult(false, false), nil
	})
	_, err := engine.Resolve(context.Background())
	if commandErrorCode(err) != "AGENT_BROWSER_NOT_INSTALLED" {
		t.Fatalf("missing executable error = %v", err)
	}
}

func TestLocateManagedExecutableRequiresContainment(t *testing.T) {
	root := t.TempDir()
	outside := filepath.Join(t.TempDir(), "escape", managedExecutableName(runtime.GOOS))
	if err := os.MkdirAll(filepath.Dir(outside), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(outside, []byte("x"), 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := locateManagedExecutable([]string{outside}, root, runtime.GOOS); err == nil {
		t.Fatal("executable outside engine root was accepted")
	}
	inside := seedManagedBrowserForPlatform(t, root, runtime.GOOS)
	got, err := locateManagedExecutable([]string{filepath.ToSlash(inside)}, root, runtime.GOOS)
	if err != nil || got != inside {
		t.Fatalf("locate = %q, %v", got, err)
	}
}

func assertEngineEnv(t *testing.T, env map[string]string, engineRoot string) {
	t.Helper()
	if env["HOME"] != engineRoot || env["USERPROFILE"] != engineRoot {
		t.Fatalf("install environment HOME=%q USERPROFILE=%q, want engine root %q", env["HOME"], env["USERPROFILE"], engineRoot)
	}
	if _, exists := env["AGENT_BROWSER_CDP"]; exists {
		t.Fatal("AGENT_BROWSER_CDP must never be set")
	}
}

func writeManifest(t *testing.T, root, version string) {
	t.Helper()
	files := []manifestFile{}
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		relative, relErr := filepath.Rel(root, path)
		if relErr != nil {
			return relErr
		}
		content, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		sum := sha256.Sum256(content)
		files = append(files, manifestFile{Path: filepath.ToSlash(relative), SHA256: hex.EncodeToString(sum[:]), Size: info.Size()})
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	payload, _ := json.Marshal(engineManifest{Version: version, Files: files})
	if err := os.WriteFile(filepath.Join(root, "manifest.json"), payload, 0o644); err != nil {
		t.Fatal(err)
	}
}
