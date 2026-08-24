package agentbrowser

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"
)

// PinnedAgentBrowserVersion is the agent-browser release Operator packages.
const PinnedAgentBrowserVersion = "0.33.1"

const (
	// DoctorTimeout bounds system-browser discovery per attempt.
	DoctorTimeout = 60 * time.Second
	// InstallTimeout bounds the managed Chromium download per attempt.
	InstallTimeout     = 600 * time.Second
	engineManifestName = "manifest.json"
)

// CommandRequest describes one child-process invocation of the packaged
// agent-browser binary.
type CommandRequest struct {
	Path    string
	Args    []string
	Env     map[string]string
	Timeout time.Duration
}

// CommandResult carries one completed child invocation's observable outcome.
type CommandResult struct {
	ExitCode int
	Stdout   string
	Stderr   string
}

// CommandRunner executes packaged-binary invocations. Production spawns real
// processes; tests inject fakes.
type CommandRunner interface {
	Run(ctx context.Context, request CommandRequest) (CommandResult, error)
}

// EngineResolution reports how sessions reach a usable browser: either the
// user's discovered system Chrome/Edge/Chromium or Operator's managed install.
type EngineResolution struct {
	Mode           string
	ExecutablePath string
}

// EngineResolver lazily resolves the browser engine for the whole daemon run.
type EngineResolver interface {
	Resolve(ctx context.Context) (EngineResolution, error)
}

// EngineOptions configures the shared managed-engine resolver.
type EngineOptions struct {
	EngineRoot string
	BinaryPath string
	Runner     CommandRunner
	Log        *slog.Logger
}

type manifestFile struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256,omitempty"`
	Target string `json:"target,omitempty"`
	Size   int64  `json:"size"`
}

type engineManifest struct {
	Version    string         `json:"version"`
	Executable string         `json:"executable"`
	Files      []manifestFile `json:"files"`
}

// Engine owns the read-only shared managed engine install under the state
// root's browser-engine directory. Discovery and installs are serialized and
// memoized so concurrent session commands never race a download.
type Engine struct {
	options EngineOptions
	log     *slog.Logger

	mu      sync.Mutex
	cached  *EngineResolution
	busy    bool
	waiters []chan *engineOutcome
}

type engineOutcome struct {
	resolution EngineResolution
	err        error
}

// NewEngine creates the serialized engine resolver.
func NewEngine(options EngineOptions) *Engine {
	if options.Log == nil {
		options.Log = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	return &Engine{options: options, log: options.Log}
}

// Resolve returns the engine for this daemon run, discovering a system browser
// first and otherwise ensuring the pinned managed install (checksum- and
// version-verified, with partial downloads removed before any reinstall).
func (e *Engine) Resolve(ctx context.Context) (EngineResolution, error) {
	e.mu.Lock()
	if e.cached != nil {
		cached := *e.cached
		e.mu.Unlock()
		return cached, nil
	}
	if e.busy {
		waiter := make(chan *engineOutcome, 1)
		e.waiters = append(e.waiters, waiter)
		e.mu.Unlock()
		outcome := <-waiter
		return outcome.resolution, outcome.err
	}
	e.busy = true
	e.mu.Unlock()

	resolution, err := e.resolveUncached(ctx)
	e.mu.Lock()
	e.busy = false
	if err == nil {
		cachedCopy := resolution
		e.cached = &cachedCopy
	}
	waiters := e.waiters
	e.waiters = nil
	e.mu.Unlock()
	outcome := &engineOutcome{resolution: resolution, err: err}
	for _, waiter := range waiters {
		waiter <- outcome
		close(waiter)
	}
	return resolution, err
}

func (e *Engine) resolveUncached(ctx context.Context) (EngineResolution, error) {
	if e.discoveredSystemBrowser(ctx) {
		return EngineResolution{Mode: "system"}, nil
	}
	executable, err := e.ensureManagedInstall(ctx)
	if err != nil {
		return EngineResolution{}, err
	}
	return EngineResolution{Mode: "managed", ExecutablePath: executable}, nil
}

func (e *Engine) discoveredSystemBrowser(ctx context.Context) bool {
	result, err := e.run(ctx, []string{"doctor", "--json"}, DoctorTimeout)
	if err != nil || result.ExitCode != 0 {
		return false
	}
	var report struct {
		Success bool `json:"success"`
		Checks  []struct {
			ID       string `json:"id"`
			Category string `json:"category"`
			Status   string `json:"status"`
		} `json:"checks"`
	}
	if json.Unmarshal([]byte(result.Stdout), &report) != nil {
		return false
	}
	if !report.Success {
		return false
	}
	for _, check := range report.Checks {
		category := strings.ToLower(check.Category)
		id := strings.ToLower(check.ID)
		isBrowser := strings.Contains(category, "browser") || strings.Contains(category, "chrome") ||
			strings.Contains(category, "chromium") || strings.Contains(category, "edge") ||
			strings.Contains(id, "chrome") || strings.Contains(id, "browser") ||
			strings.Contains(id, "chromium") || strings.Contains(id, "edge")
		if isBrowser && check.Status == "pass" {
			return true
		}
	}
	return false
}

func (e *Engine) ensureManagedInstall(ctx context.Context) (string, error) {
	if executable, valid := e.validatedExistingInstall(); valid {
		return executable, nil
	}
	if err := os.RemoveAll(e.options.EngineRoot); err != nil && !errors.Is(err, os.ErrNotExist) {
		return "", fmt.Errorf("reset managed browser engine: %w", err)
	}
	if err := os.MkdirAll(e.options.EngineRoot, 0o755); err != nil {
		return "", fmt.Errorf("create managed browser engine root: %w", err)
	}
	result, err := e.run(ctx, []string{"install", "--json"}, InstallTimeout)
	if err != nil {
		return "", err
	}
	if result.ExitCode != 0 {
		detail := firstNonEmpty(strings.TrimSpace(result.Stderr), strings.TrimSpace(result.Stdout), fmt.Sprintf("agent-browser install exited with code %d", result.ExitCode))
		return "", commandError("AGENT_BROWSER_INSTALL_FAILED", detail)
	}
	_ = os.RemoveAll(filepath.Join(e.options.EngineRoot, ".install-tmp"))
	files, err := walkEngineFiles(e.options.EngineRoot)
	if err != nil {
		return "", fmt.Errorf("inspect managed browser engine: %w", err)
	}
	paths := make([]string, 0, len(files))
	for _, file := range files {
		paths = append(paths, file.Path)
	}
	executable, err := locateManagedExecutable(paths, e.options.EngineRoot, runtime.GOOS)
	if err != nil {
		return "", commandError("AGENT_BROWSER_NOT_INSTALLED", "The managed browser engine did not produce a usable browser executable")
	}
	relative, err := filepath.Rel(e.options.EngineRoot, executable)
	if err != nil {
		return "", fmt.Errorf("resolve managed executable: %w", err)
	}
	manifest := engineManifest{
		Version:    PinnedAgentBrowserVersion,
		Executable: relative,
		Files:      files,
	}
	payload, err := json.Marshal(manifest)
	if err != nil {
		return "", fmt.Errorf("encode engine manifest: %w", err)
	}
	temporary := filepath.Join(e.options.EngineRoot, "."+engineManifestName+".tmp")
	if err := os.WriteFile(temporary, payload, 0o644); err != nil {
		return "", fmt.Errorf("write engine manifest: %w", err)
	}
	if err := os.Rename(temporary, filepath.Join(e.options.EngineRoot, engineManifestName)); err != nil {
		return "", fmt.Errorf("publish engine manifest: %w", err)
	}
	return executable, nil
}

func (e *Engine) validatedExistingInstall() (string, bool) {
	payload, err := os.ReadFile(filepath.Join(e.options.EngineRoot, engineManifestName))
	if err != nil {
		return "", false
	}
	var manifest engineManifest
	if json.Unmarshal(payload, &manifest) != nil {
		return "", false
	}
	if manifest.Version != PinnedAgentBrowserVersion || manifest.Executable == "" || len(manifest.Files) == 0 {
		return "", false
	}
	executable := filepath.Join(e.options.EngineRoot, filepath.FromSlash(manifest.Executable))
	if !pathWithin(e.options.EngineRoot, executable) {
		return "", false
	}
	current, err := walkEngineFiles(e.options.EngineRoot)
	if err != nil {
		return "", false
	}
	if len(current) != len(manifest.Files) {
		return "", false
	}
	recorded := make(map[manifestFile]struct{}, len(manifest.Files))
	for _, file := range manifest.Files {
		recorded[file] = struct{}{}
	}
	for _, file := range current {
		if _, exists := recorded[file]; !exists {
			return "", false
		}
	}
	if info, err := os.Stat(executable); err != nil || info.IsDir() {
		return "", false
	}
	return executable, true
}

func (e *Engine) run(ctx context.Context, args []string, timeout time.Duration) (CommandResult, error) {
	if e.options.Runner == nil {
		e.options.Runner = newProcessRunner(e.log)
	}
	return e.options.Runner.Run(ctx, CommandRequest{
		Path:    e.options.BinaryPath,
		Args:    args,
		Env:     e.isolatedEnv(),
		Timeout: timeout,
	})
}

func (e *Engine) isolatedEnv() map[string]string {
	env := inheritAllowedEnv(currentParentEnv())
	env["HOME"] = e.options.EngineRoot
	env["USERPROFILE"] = e.options.EngineRoot
	installTemp := filepath.Join(e.options.EngineRoot, ".install-tmp")
	_ = os.MkdirAll(installTemp, 0o755)
	env["TMPDIR"] = installTemp
	env["TEMP"] = installTemp
	env["TMP"] = installTemp
	return env
}

func walkEngineFiles(root string) ([]manifestFile, error) {
	files := []manifestFile{}
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		slashRelative := filepath.ToSlash(relative)
		if slashRelative == engineManifestName || slashRelative == "."+engineManifestName+".tmp" {
			return nil
		}
		file := manifestFile{Path: slashRelative}
		if entry.Type()&os.ModeSymlink != 0 {
			target, err := os.Readlink(path)
			if err != nil {
				return err
			}
			file.Target = target
		} else {
			hash, size, err := hashFile(path)
			if err != nil {
				return err
			}
			file.SHA256 = hex.EncodeToString(hash)
			file.Size = size
		}
		files = append(files, file)
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(files, func(i, j int) bool { return files[i].Path < files[j].Path })
	return files, nil
}

var managedDarwinSuffixes = []string{"Google Chrome for Testing"}
var managedWindowsSuffixes = []string{"chrome.exe"}
var managedLinuxSuffixes = []string{"chrome-linux64/chrome", "chrome-linux/chrome"}

// locateManagedExecutable finds the managed Chromium's launcher inside a walked
// engine tree, refusing entries that escape the engine root.
func locateManagedExecutable(files []string, root, platform string) (string, error) {
	suffixes := managedLinuxSuffixes
	switch platform {
	case "darwin":
		suffixes = managedDarwinSuffixes
	case "windows":
		suffixes = managedWindowsSuffixes
	}
	for _, file := range files {
		if !strings.Contains(file, ".agent-browser") {
			continue
		}
		for _, suffix := range suffixes {
			if !strings.HasSuffix(filepath.FromSlash(file), filepath.FromSlash(suffix)) {
				continue
			}
			candidate := filepath.FromSlash(file)
			if !filepath.IsAbs(candidate) {
				candidate = filepath.Join(root, candidate)
			}
			if !pathWithin(root, candidate) {
				continue
			}
			return candidate, nil
		}
	}
	return "", errors.New("managed browser executable not found")
}

func pathWithin(root, target string) bool {
	relative, err := filepath.Rel(root, target)
	if err != nil {
		return false
	}
	return relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) && !filepath.IsAbs(relative)
}

func hashFile(path string) ([]byte, int64, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, 0, err
	}
	defer func() { _ = file.Close() }()
	hasher := sha256.New()
	size, err := io.Copy(hasher, file)
	if err != nil {
		return nil, 0, err
	}
	return hasher.Sum(nil), size, nil
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}
