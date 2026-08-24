package agentbrowser

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/service/browser"
)

const (
	runtimeOwnerMarker = "OPERATOR_BROWSER_RUNTIME_V1"
	ownerFileName      = "owner.json"
	runRootPattern     = `^(?:run-\d+-[0-9a-f]{12}|r-[0-9a-f]{10})$`
	socketAliasPattern = `^opr-br-(\d+)-[0-9a-f]{12}$`

	reclaimGrace          = 15 * time.Minute
	maxOutputBytes        = 1 << 20
	maxScreenshotBytes    = 5 << 20
	maxExternalTextBytes  = 1 << 20
	defaultCommandTimeout = 60 * time.Second
	defaultCloseTimeout   = 10 * time.Second

	untrustedBegin = "<<<BEGIN UNTRUSTED EXTERNAL CONTENT>>>"
	untrustedEnd   = "<<<END UNTRUSTED EXTERNAL CONTENT>>>"

	sessionConfigBody = "{}\n"

	idleTimeoutMillis = "300000"
	nativeMaxOutput   = "50000"
)

var (
	runRootNamePattern     = regexp.MustCompile(runRootPattern)
	socketAliasNamePattern = regexp.MustCompile(socketAliasPattern)
	ownerTokenPattern      = regexp.MustCompile(`^[0-9a-f]{32}$`)
)

type runtimeOwner struct {
	Marker    string `json:"marker"`
	PID       int    `json:"pid"`
	StartedAt string `json:"startedAt"`
	Token     string `json:"token"`
}

func validRuntimeOwner(value runtimeOwner, expectedPID string) bool {
	if value.Marker != runtimeOwnerMarker || value.PID <= 0 || value.StartedAt == "" {
		return false
	}
	if !ownerTokenPattern.MatchString(value.Token) {
		return false
	}
	if expectedPID != "" && fmt.Sprintf("%d", value.PID) != expectedPID {
		return false
	}
	return true
}

// Options configures the standalone agent-browser runtime adapter.
type Options struct {
	BinaryPath string
	DataDir    string
	Log        *slog.Logger
	Runner     CommandRunner
	Engine     EngineResolver
	NewID      func() string
	// ProcessAlive reports whether an owner PID still runs; tests inject fakes.
	ProcessAlive func(pid int) bool
	Platform     string
	// SocketAliasRoot hosts the short unix socket aliases; defaults to os.TempDir().
	SocketAliasRoot string
	// ParentEnv is the daemon environment the child allowlist draws from.
	ParentEnv map[string]string
	// StateRoot is the Operator-owned root holding browser-engine and
	// browser-runtime. Empty resolves to the canonical ~/.operator; it is never
	// derived from DataDir, which an override can point anywhere.
	StateRoot string
	// CommandTimeout bounds each action; CloseTimeout bounds session teardown.
	CommandTimeout time.Duration
	CloseTimeout   time.Duration
}

type sessionState struct {
	namespace string
	dir       string
}

// sessionCall coordinates concurrent first commands for one session: every
// waiter joins the same WaitGroup and reads the shared outcome after Done.
type sessionCall struct {
	wg      sync.WaitGroup
	session *sessionState
	err     error
}

// Adapter implements browser.Runtime by driving the packaged agent-browser
// binary against an isolated per-session Chromium under the daemon's state
// root. It never sets AGENT_BROWSER_CDP, auto-connects, or exposes the user's
// profile or home directory to the browser process.
type Adapter struct {
	options Options
	log     *slog.Logger
	runner  CommandRunner
	started time.Time

	binaryOnce sync.Once
	binaryErr  error

	stateRoot string

	rootMu    sync.Mutex
	runRoot   string
	socketDir string

	mu           sync.Mutex
	sessions     map[domain.SessionID]*sessionState
	pendingInit  map[domain.SessionID]*sessionCall
	pendingClose map[domain.SessionID]chan struct{}
	prepared     bool
}

// New creates the standalone adapter. Production wiring leaves Runner, Engine,
// and every seam nil so the packaged binary drives a real managed engine.
func New(options Options) *Adapter {
	if options.Log == nil {
		options.Log = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	if options.NewID == nil {
		options.NewID = uuid.NewString
	}
	if options.ProcessAlive == nil {
		options.ProcessAlive = defaultProcessAlive
	}
	if options.Platform == "" {
		options.Platform = runtime.GOOS
	}
	if options.SocketAliasRoot == "" {
		if options.Platform == "windows" {
			options.SocketAliasRoot = os.TempDir()
		} else {
			options.SocketAliasRoot = "/tmp"
		}
	}
	if options.CommandTimeout <= 0 {
		options.CommandTimeout = defaultCommandTimeout
	}
	if options.CloseTimeout <= 0 {
		options.CloseTimeout = defaultCloseTimeout
	}
	if options.ParentEnv == nil {
		options.ParentEnv = currentParentEnv()
	}
	stateRoot := resolveStateRoot(options)
	adapter := &Adapter{
		options:      options,
		log:          options.Log,
		started:      time.Now(),
		stateRoot:    stateRoot,
		sessions:     make(map[domain.SessionID]*sessionState),
		pendingInit:  make(map[domain.SessionID]*sessionCall),
		pendingClose: make(map[domain.SessionID]chan struct{}),
	}
	adapter.runner = options.Runner
	if adapter.runner == nil {
		adapter.runner = newProcessRunner(options.Log)
	}
	if options.Engine == nil {
		if stateRoot == "" {
			options.Engine = failedEngineResolver{err: errors.New("resolve operator state root")}
		} else {
			options.Engine = NewEngine(EngineOptions{
				EngineRoot: filepath.Join(stateRoot, "browser-engine"),
				BinaryPath: options.BinaryPath,
				Runner:     adapter.runner,
				Log:        options.Log,
			})
		}
	}
	adapter.options.Engine = options.Engine
	return adapter
}

type failedEngineResolver struct{ err error }

func (f failedEngineResolver) Resolve(context.Context) (EngineResolution, error) {
	return EngineResolution{}, f.err
}

// Status implements browser.Runtime. Readiness reflects the packaged binary's
// availability; the managed engine itself resolves lazily on first command.
func (a *Adapter) Status(domain.SessionID) browser.RuntimeStatus {
	a.binaryOnce.Do(func() {
		if _, err := os.Stat(a.options.BinaryPath); err != nil {
			a.binaryErr = err
		}
	})
	if a.binaryErr != nil {
		return browser.RuntimeStatus{}
	}
	return browser.RuntimeStatus{Ready: true, ReadyAt: a.started}
}

// Execute implements browser.Runtime for one public action.
func (a *Adapter) Execute(
	ctx context.Context,
	sessionID domain.SessionID,
	action string,
	args map[string]interface{},
) (browser.RuntimeResult, error) {
	if code, ok := desktopOnlyActionCodes[action]; ok {
		return browser.RuntimeResult{}, commandError(code, desktopOnlyMessage(action))
	}
	if err := a.assertBinary(); err != nil {
		return browser.RuntimeResult{}, err
	}
	if args == nil {
		args = map[string]interface{}{}
	}
	if action == "screenshot" {
		return a.executeScreenshot(ctx, sessionID)
	}
	nativeArgs, err := NativeArgumentsForAction(action, args)
	if err != nil {
		return browser.RuntimeResult{}, err
	}
	nativeArgs = append(nativeArgs, "--json")
	if err := ValidateArguments(nativeArgs); err != nil {
		return browser.RuntimeResult{}, err
	}
	result, err := a.runForSession(ctx, sessionID, nativeArgs)
	if err != nil {
		return browser.RuntimeResult{}, err
	}
	parsed, err := ParseJSON(result.Stdout)
	if err != nil {
		return browser.RuntimeResult{}, err
	}
	value := shapeActionValue(action, args, parsed)
	return browser.RuntimeResult{RequestID: a.options.NewID(), Value: value}, nil
}

func (a *Adapter) executeScreenshot(ctx context.Context, sessionID domain.SessionID) (browser.RuntimeResult, error) {
	session, resolution, err := a.prepareSessionCommand(ctx, sessionID)
	if err != nil {
		return browser.RuntimeResult{}, err
	}
	directory := filepath.Join(session.dir, "screenshots", randomHex(6))
	target := filepath.Join(directory, "screenshot.png")
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return browser.RuntimeResult{}, fmt.Errorf("create screenshot directory: %w", err)
	}
	defer func() { _ = os.RemoveAll(directory) }()
	result, err := a.runner.Run(ctx, CommandRequest{
		Path:    a.options.BinaryPath,
		Args:    []string{"screenshot", target, "--json"},
		Env:     a.sessionEnvironment(session, managedExecutable(resolution)),
		Timeout: a.options.CommandTimeout,
	})
	if err != nil {
		return browser.RuntimeResult{}, err
	}
	if result.ExitCode != 0 {
		return browser.RuntimeResult{}, commandFailure(result)
	}
	image, err := os.ReadFile(target)
	if errors.Is(err, os.ErrNotExist) {
		return browser.RuntimeResult{}, commandError("AGENT_BROWSER_INVALID_OUTPUT", "Browser automation did not produce a screenshot file")
	} else if err != nil {
		return browser.RuntimeResult{}, fmt.Errorf("read screenshot: %w", err)
	}
	if len(image) > maxScreenshotBytes {
		return browser.RuntimeResult{}, commandError("AGENT_BROWSER_OUTPUT_TOO_LARGE", "Browser screenshot exceeded Operator's size limit")
	}
	width, height, err := pngDimensions(image)
	if err != nil {
		return browser.RuntimeResult{}, err
	}
	return browser.RuntimeResult{
		RequestID: a.options.NewID(),
		Value: map[string]interface{}{
			"data":                     base64.StdEncoding.EncodeToString(image),
			"width":                    float64(width),
			"height":                   float64(height),
			"untrustedExternalContent": true,
		},
	}, nil
}

func (a *Adapter) runForSession(ctx context.Context, sessionID domain.SessionID, nativeArgs []string) (CommandResult, error) {
	session, err := a.ensureSession(ctx, sessionID)
	if err != nil {
		return CommandResult{}, err
	}
	resolution, err := a.options.Engine.Resolve(ctx)
	if err != nil {
		return CommandResult{}, err
	}
	a.touchOwner()
	result, err := a.runner.Run(ctx, CommandRequest{
		Path:    a.options.BinaryPath,
		Args:    nativeArgs,
		Env:     a.sessionEnvironment(session, managedExecutable(resolution)),
		Timeout: a.options.CommandTimeout,
	})
	if err != nil {
		return CommandResult{}, err
	}
	if result.ExitCode != 0 {
		return CommandResult{}, commandFailure(result)
	}
	return result, nil
}

// prepareSessionCommand performs the shared pre-command work (binary check,
// session state, engine resolution, heartbeat) for action paths that bypass the
// generic translation.
func (a *Adapter) prepareSessionCommand(ctx context.Context, sessionID domain.SessionID) (*sessionState, EngineResolution, error) {
	if err := a.assertBinary(); err != nil {
		return nil, EngineResolution{}, err
	}
	session, err := a.ensureSession(ctx, sessionID)
	if err != nil {
		return nil, EngineResolution{}, err
	}
	resolution, err := a.options.Engine.Resolve(ctx)
	if err != nil {
		return nil, EngineResolution{}, err
	}
	a.touchOwner()
	return session, resolution, nil
}

func managedExecutable(resolution EngineResolution) string {
	if resolution.Mode == "managed" {
		return resolution.ExecutablePath
	}
	return ""
}

func (a *Adapter) assertBinary() error {
	a.binaryOnce.Do(func() {
		if _, err := os.Stat(a.options.BinaryPath); err != nil {
			a.binaryErr = err
		}
	})
	if a.binaryErr != nil {
		return commandError(
			"AGENT_BROWSER_NOT_INSTALLED",
			fmt.Sprintf("Operator's browser automation component was not found at %s. Reinstall or rebuild the desktop app.", a.options.BinaryPath),
		)
	}
	return nil
}

// DestroySession implements browser.Runtime teardown: it closes the session's
// browser best-effort and always removes the session's isolated state, dropping
// the shared run root once the last session goes away.
func (a *Adapter) DestroySession(ctx context.Context, sessionID domain.SessionID) error {
	for {
		a.mu.Lock()
		if done, pending := a.pendingClose[sessionID]; pending {
			a.mu.Unlock()
			<-done
			return nil
		}
		if call, exists := a.pendingInit[sessionID]; exists {
			a.mu.Unlock()
			call.wg.Wait()
			if call.err != nil {
				return nil
			}
			continue
		}
		session, exists := a.sessions[sessionID]
		if !exists {
			a.mu.Unlock()
			return nil
		}
		delete(a.sessions, sessionID)
		done := make(chan struct{}, 1)
		a.pendingClose[sessionID] = done
		a.mu.Unlock()

		a.closeSessionBrowser(ctx, sessionID, session)

		a.mu.Lock()
		delete(a.pendingClose, sessionID)
		busy := len(a.sessions) > 0 || len(a.pendingInit) > 0 || len(a.pendingClose) > 0
		runRoot := a.runRoot
		socketDir := a.socketDir
		if !busy && runRoot != "" {
			a.runRoot = ""
			a.socketDir = ""
		}
		a.mu.Unlock()

		if !busy && runRoot != "" {
			if a.options.Platform != "windows" && socketDir != "" {
				if info, err := os.Lstat(socketDir); err == nil && info.Mode()&os.ModeSymlink != 0 {
					_ = os.Remove(socketDir)
				}
			}
			if err := os.RemoveAll(runRoot); err != nil {
				a.log.Warn("agent-browser run root cleanup failed", "err", err)
			}
		}
		done <- struct{}{}
		close(done)
		return nil
	}
}

func (a *Adapter) closeSessionBrowser(ctx context.Context, sessionID domain.SessionID, session *sessionState) {
	closeCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), a.options.CloseTimeout)
	defer cancel()
	if _, err := a.runner.Run(closeCtx, CommandRequest{
		Path:    a.options.BinaryPath,
		Args:    []string{"close", "--json"},
		Env:     a.sessionEnvironment(session, ""),
		Timeout: a.options.CloseTimeout,
	}); err != nil {
		var coded browser.CommandError
		if !errors.As(err, &coded) || coded.Code != "AGENT_BROWSER_CANCELLED" {
			a.log.Warn("agent-browser close failed", "sessionID", sessionID, "err", err)
		}
	}
	if err := os.RemoveAll(session.dir); err != nil {
		a.log.Warn("agent-browser session directory cleanup failed", "sessionID", sessionID, "err", err)
	}
}

func (a *Adapter) ensureSession(_ context.Context, sessionID domain.SessionID) (*sessionState, error) {
	a.mu.Lock()
	if session, exists := a.sessions[sessionID]; exists {
		a.mu.Unlock()
		return session, nil
	}
	if call, exists := a.pendingInit[sessionID]; exists {
		a.mu.Unlock()
		call.wg.Wait()
		return call.session, call.err
	}
	call := &sessionCall{}
	call.wg.Add(1)
	a.pendingInit[sessionID] = call
	a.mu.Unlock()

	session, err := a.createSession(sessionID)
	call.session, call.err = session, err

	a.mu.Lock()
	delete(a.pendingInit, sessionID)
	if err == nil {
		a.sessions[sessionID] = session
	}
	a.mu.Unlock()
	call.wg.Done()
	return session, err
}

func (a *Adapter) createSession(sessionID domain.SessionID) (*sessionState, error) {
	a.prepareOnce()
	runRoot, socketDir, err := a.ensureRunRoot()
	if err != nil {
		return nil, commandError("AGENT_BROWSER_START_FAILED", err.Error())
	}
	namespace := "opr-" + sessionHash(string(sessionID)) + "-" + randomHex(6)
	if err := assertSocketPath(socketDir, namespace, a.options.Platform); err != nil {
		return nil, err
	}
	dir := filepath.Join(runRoot, namespace)
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0o700); err != nil {
		return nil, commandError("AGENT_BROWSER_START_FAILED", fmt.Sprintf("create session state: %v", err))
	}
	_ = os.Chmod(dir, 0o700)
	if err := os.WriteFile(filepath.Join(dir, "config.json"), []byte(sessionConfigBody), 0o600); err != nil {
		return nil, commandError("AGENT_BROWSER_START_FAILED", fmt.Sprintf("write session config: %v", err))
	}
	return &sessionState{namespace: namespace, dir: dir}, nil
}

func (a *Adapter) ensureRunRoot() (string, string, error) {
	a.rootMu.Lock()
	defer a.rootMu.Unlock()
	if a.runRoot != "" {
		return a.runRoot, a.socketDir, nil
	}
	if a.stateRoot == "" {
		return "", "", errors.New("operator state root could not be resolved; browser automation stays disabled")
	}
	base := filepath.Join(a.stateRoot, "browser-runtime")
	if err := os.MkdirAll(base, 0o700); err != nil {
		return "", "", fmt.Errorf("create browser runtime root: %w", err)
	}
	root := filepath.Join(base, fmt.Sprintf("run-%d-%s", os.Getpid(), randomHex(6)))
	if err := os.Mkdir(root, 0o700); err != nil {
		return "", "", fmt.Errorf("create browser run root: %w", err)
	}
	failed := false
	owner := runtimeOwner{
		Marker:    runtimeOwnerMarker,
		PID:       os.Getpid(),
		StartedAt: time.Now().UTC().Format(time.RFC3339),
		Token:     randomHex(16),
	}
	payload, _ := json.Marshal(owner)
	if err := os.WriteFile(filepath.Join(root, ownerFileName), append(payload, '\n'), 0o600); err != nil {
		failed = true
	}
	socketBase := filepath.Join(root, "s")
	if !failed {
		if err := os.Mkdir(socketBase, 0o700); err != nil {
			failed = true
		}
	}
	socketDir := socketBase
	alias := ""
	if !failed && a.options.Platform != "windows" {
		alias = filepath.Join(a.options.SocketAliasRoot, fmt.Sprintf("opr-br-%d-%s", os.Getpid(), randomHex(6)))
		if err := os.Symlink(socketBase, alias); err != nil {
			failed = true
		} else {
			socketDir = alias
		}
	}
	if failed {
		if alias != "" {
			_ = os.Remove(alias)
		}
		_ = os.RemoveAll(root)
		return "", "", errors.New("could not establish the isolated browser run root")
	}
	a.runRoot = root
	a.socketDir = socketDir
	return root, socketDir, nil
}

func (a *Adapter) prepareOnce() {
	a.mu.Lock()
	alreadyPrepared := a.prepared
	a.prepared = true
	a.mu.Unlock()
	if alreadyPrepared {
		return
	}
	if a.stateRoot == "" {
		return
	}
	runtimeBase := filepath.Join(a.stateRoot, "browser-runtime")
	ScavengeRuntimeRuns(runtimeBase, a.options.ProcessAlive, a.log)
	if a.options.Platform != "windows" {
		ScavengeSocketAliases(a.options.SocketAliasRoot, a.stateRoot, a.options.ProcessAlive, a.log)
	}
}

func (a *Adapter) touchOwner() {
	a.rootMu.Lock()
	runRoot := a.runRoot
	a.rootMu.Unlock()
	if runRoot == "" {
		return
	}
	now := time.Now()
	if err := os.Chtimes(filepath.Join(runRoot, ownerFileName), now, now); err != nil {
		a.log.Warn("agent-browser runtime heartbeat failed", "err", err)
	}
}

func (a *Adapter) sessionEnvironment(session *sessionState, managedExecutablePath string) map[string]string {
	env := inheritAllowedEnv(a.options.ParentEnv)
	dir := session.dir
	env["HOME"] = dir
	env["USERPROFILE"] = dir
	env["XDG_CONFIG_HOME"] = dir
	env["XDG_CACHE_HOME"] = dir
	env["XDG_DATA_HOME"] = dir
	env["XDG_STATE_HOME"] = dir
	env["XDG_RUNTIME_DIR"] = filepath.Join(dir, "runtime")
	env["TMPDIR"] = filepath.Join(dir, "tmp")
	env["TEMP"] = filepath.Join(dir, "tmp")
	env["TMP"] = filepath.Join(dir, "tmp")
	env["AGENT_BROWSER_CONFIG"] = filepath.Join(dir, "config.json")
	env["AGENT_BROWSER_SOCKET_DIR"] = a.currentSocketDir()
	env["AGENT_BROWSER_SESSION"] = session.namespace
	env["AGENT_BROWSER_NAMESPACE"] = session.namespace
	env["AGENT_BROWSER_CONTENT_BOUNDARIES"] = "1"
	env["AGENT_BROWSER_MAX_OUTPUT"] = nativeMaxOutput
	env["AGENT_BROWSER_IDLE_TIMEOUT_MS"] = idleTimeoutMillis
	env["AGENT_BROWSER_AUTO_CONNECT"] = "0"
	if managedExecutablePath != "" {
		env["AGENT_BROWSER_EXECUTABLE_PATH"] = managedExecutablePath
	}
	return env
}

func (a *Adapter) currentSocketDir() string {
	a.rootMu.Lock()
	defer a.rootMu.Unlock()
	return a.socketDir
}

var desktopOnlyActionCodes = map[string]string{
	"devtools-open":  "BROWSER_DEVTOOLS_UNAVAILABLE",
	"devtools-close": "BROWSER_DEVTOOLS_UNAVAILABLE",
	"network-start":  "BROWSER_AUTOMATION_UNAVAILABLE",
	"network-status": "BROWSER_AUTOMATION_UNAVAILABLE",
	"network-list":   "BROWSER_AUTOMATION_UNAVAILABLE",
	"network-stop":   "BROWSER_AUTOMATION_UNAVAILABLE",
	"network-clear":  "BROWSER_AUTOMATION_UNAVAILABLE",
	"unhighlight":    "BROWSER_AUTOMATION_UNAVAILABLE",
}

func desktopOnlyMessage(action string) string {
	switch desktopOnlyActionCodes[action] {
	case "BROWSER_DEVTOOLS_UNAVAILABLE":
		return "DevTools control requires the desktop browser panel runtime"
	default:
		return "This action requires the desktop browser panel runtime and is not available in the standalone browser"
	}
}

func shapeActionValue(action string, args map[string]interface{}, parsed map[string]interface{}) map[string]interface{} {
	switch action {
	case "snapshot":
		if snapshot, ok := parsed["snapshot"].(string); ok {
			parsed["text"] = snapshot
		}
		return parsed
	case "console", "errors":
		return normalizeNativeMessages(parsed, action)
	case "tabs":
		return shapeTabs(parsed)
	case "tab-new", "tab-select":
		return shapeSingleTab(parsed)
	case "tab-close":
		return shapeTabClose(args, parsed)
	case "get":
		if _, hasValue := parsed["value"]; !hasValue {
			if fallback, exists := parsed[tostring(args["property"])]; exists {
				parsed["value"] = fallback
			}
		}
		return parsed
	default:
		return parsed
	}
}

func tostring(value interface{}) string {
	text, _ := value.(string)
	return text
}

func normalizeNativeMessages(parsed map[string]interface{}, action string) map[string]interface{} {
	defaultLevel := "log"
	if action == "errors" {
		defaultLevel = "error"
	}
	raw := messagesField(parsed["messages"])
	if raw == nil {
		raw = messagesField(parsed["value"])
	}
	messages := make([]map[string]interface{}, 0, len(raw))
	for _, item := range raw {
		entry := map[string]interface{}{
			"level":     defaultLevel,
			"timestamp": time.Now().UTC().Format(time.RFC3339Nano),
		}
		if record, ok := item.(map[string]interface{}); ok {
			if level, ok := record["level"].(string); ok && level != "" {
				entry["level"] = level
			} else if level, ok := record["type"].(string); ok && level != "" {
				entry["level"] = level
			}
			switch {
			case isString(record["message"]):
				entry["message"] = markUntrusted(externalText(record["message"].(string)))
			case isString(record["text"]):
				entry["message"] = markUntrusted(externalText(record["text"].(string)))
			default:
				entry["message"] = markUntrusted(externalText(jsonRecordText(record)))
			}
			if timestamp, ok := record["timestamp"].(string); ok && timestamp != "" {
				entry["timestamp"] = timestamp
			}
		} else if text, ok := item.(string); ok {
			entry["message"] = markUntrusted(externalText(text))
		} else {
			entry["message"] = markUntrusted(externalText(fmt.Sprintf("%v", item)))
		}
		messages = append(messages, entry)
	}
	return map[string]interface{}{"messages": messages, "untrustedExternalContent": true}
}

func isString(value interface{}) bool {
	text, ok := value.(string)
	return ok && text != ""
}

func jsonRecordText(record map[string]interface{}) string {
	payload, err := json.Marshal(record)
	if err != nil {
		return fmt.Sprintf("%v", record)
	}
	return string(payload)
}

func messagesField(value interface{}) []interface{} {
	list, _ := value.([]interface{})
	return list
}

func shapeTabs(parsed map[string]interface{}) map[string]interface{} {
	raw, _ := parsed["tabs"].([]interface{})
	tabs := make([]map[string]interface{}, 0, len(raw))
	activeTabID := ""
	for index, item := range raw {
		record, _ := item.(map[string]interface{})
		tab := map[string]interface{}{
			"id":     tabRecordID(record),
			"url":    tostring(record["url"]),
			"title":  tostring(record["title"]),
			"active": boolValue(record["active"], index == 0),
		}
		if tab["active"] == true && activeTabID == "" {
			activeTabID = tab["id"].(string)
		}
		tabs = append(tabs, tab)
	}
	if activeTabID == "" && len(tabs) > 0 {
		activeTabID = tabs[0]["id"].(string)
	}
	return map[string]interface{}{
		"tabs":                     tabs,
		"activeTabId":              activeTabID,
		"untrustedExternalContent": true,
	}
}

func boolValue(value interface{}, fallback bool) bool {
	if flag, ok := value.(bool); ok {
		return flag
	}
	return fallback
}

func tabRecordID(record map[string]interface{}) string {
	if id := tostring(record["tabId"]); id != "" {
		return id
	}
	return tostring(record["id"])
}

func shapeSingleTab(parsed map[string]interface{}) map[string]interface{} {
	id := tabRecordID(parsed)
	return map[string]interface{}{
		"id":                       id,
		"url":                      tostring(parsed["url"]),
		"title":                    tostring(parsed["title"]),
		"active":                   true,
		"untrustedExternalContent": true,
	}
}

func shapeTabClose(args map[string]interface{}, parsed map[string]interface{}) map[string]interface{} {
	closedTabID := tostring(args["tabId"])
	if closedTabID == "" {
		closedTabID = tabRecordID(parsed)
	}
	shaped := map[string]interface{}{
		"closedTabId":              closedTabID,
		"untrustedExternalContent": true,
	}
	if rawTabs, exists := parsed["tabs"]; exists {
		shaped["tabs"] = shapeTabs(map[string]interface{}{"tabs": rawTabs})["tabs"]
	}
	if activeTabID, exists := parsed["activeTabId"]; exists {
		shaped["activeTabId"] = activeTabID
	}
	return shaped
}

func externalText(value string) string {
	if len(value) <= maxExternalTextBytes {
		return value
	}
	truncated := strings.ToValidUTF8(value[:maxExternalTextBytes], "�")
	return fmt.Sprintf("%s\n[Content truncated at %d bytes]", truncated, maxExternalTextBytes)
}

func markUntrusted(value string) string {
	value = strings.ReplaceAll(value, untrustedBegin, "\\u003c"+untrustedBegin[1:])
	value = strings.ReplaceAll(value, untrustedEnd, "\\u003c"+untrustedEnd[1:])
	return untrustedBegin + "\n" + value + "\n" + untrustedEnd
}

func pngDimensions(image []byte) (uint32, uint32, error) {
	if len(image) < 24 || string(image[1:4]) != "PNG" {
		return 0, 0, commandError("AGENT_BROWSER_INVALID_OUTPUT", "Browser automation returned an invalid PNG screenshot")
	}
	width := uint32(image[16])<<24 | uint32(image[17])<<16 | uint32(image[18])<<8 | uint32(image[19])
	height := uint32(image[20])<<24 | uint32(image[21])<<16 | uint32(image[22])<<8 | uint32(image[23])
	return width, height, nil
}

func commandFailure(result CommandResult) error {
	message := firstNonEmpty(strings.TrimSpace(result.Stderr), strings.TrimSpace(result.Stdout), fmt.Sprintf("agent-browser exited with code %d", result.ExitCode))
	return commandError("AGENT_BROWSER_COMMAND_FAILED", message)
}

func sessionHash(sessionID string) string {
	sum := sha256.Sum256([]byte(sessionID))
	return hex.EncodeToString(sum[:])[:4]
}

func randomHex(bytes int) string {
	raw := make([]byte, bytes)
	if _, err := rand.Read(raw); err != nil {
		panic(fmt.Sprintf("generate randomness: %v", err))
	}
	return hex.EncodeToString(raw)
}

func resolveStateRoot(options Options) string {
	if options.StateRoot != "" {
		return options.StateRoot
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".operator")
}

func currentParentEnv() map[string]string {
	env := make(map[string]string, len(os.Environ()))
	for _, pair := range os.Environ() {
		key, value, found := strings.Cut(pair, "=")
		if found {
			env[key] = value
		}
	}
	return env
}

func assertSocketPath(socketDir, namespace, platform string) error {
	if platform == "windows" {
		return nil
	}
	socketPath := filepath.Join(socketDir, "namespaces", namespace, "run", namespace+".sock")
	byteLength := len([]byte(socketPath))
	if byteLength > unixSocketPathMaxBytes {
		return commandError(
			"AGENT_BROWSER_START_FAILED",
			fmt.Sprintf("Agent Browser socket path is %d bytes; Unix supports at most %d. Operator needs a shorter socket directory.", byteLength, unixSocketPathMaxBytes),
		)
	}
	return nil
}

const unixSocketPathMaxBytes = 103

// ScavengeRuntimeRuns removes confirmed-dead run roots owned by previous daemon
// processes. Unmarked or malformed directories are preserved rather than
// guessed at; live owners and owners within the reclaim grace are untouched.
func ScavengeRuntimeRuns(runtimeBase string, alive func(int) bool, log *slog.Logger) {
	entries, err := os.ReadDir(runtimeBase)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			log.Warn("agent-browser runtime scan failed", "err", err)
		}
		return
	}
	for _, entry := range entries {
		if !entry.IsDir() || !runRootNamePattern.MatchString(entry.Name()) {
			continue
		}
		ownerPath := filepath.Join(runtimeBase, entry.Name(), ownerFileName)
		payload, err := os.ReadFile(ownerPath)
		if err != nil {
			continue
		}
		var owner runtimeOwner
		if json.Unmarshal(payload, &owner) != nil || !validRuntimeOwner(owner, "") {
			continue
		}
		if alive(owner.PID) {
			continue
		}
		info, err := os.Stat(ownerPath)
		if err != nil {
			log.Warn("agent-browser runtime scan skipped "+entry.Name(), "err", err)
			continue
		}
		if time.Since(info.ModTime()) < reclaimGrace {
			continue
		}
		if err := os.RemoveAll(filepath.Join(runtimeBase, entry.Name())); err != nil {
			log.Warn("stale browser run root cleanup failed", "root", entry.Name(), "err", err)
		}
	}
}

// ScavengeSocketAliases removes only confirmed-dead unix aliases that point
// back into this deployment's browser-runtime tree; foreign symlinks survive.
func ScavengeSocketAliases(aliasRoot, stateRoot string, alive func(int) bool, log *slog.Logger) {
	entries, err := os.ReadDir(aliasRoot)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			log.Warn("agent-browser socket alias scan failed", "err", err)
		}
		return
	}
	for _, entry := range entries {
		match := socketAliasNamePattern.FindStringSubmatch(entry.Name())
		if match == nil || entry.Type()&os.ModeSymlink == 0 {
			continue
		}
		pid, err := parsePositiveInt(match[1])
		if err != nil || alive(pid) {
			continue
		}
		aliasPath := filepath.Join(aliasRoot, entry.Name())
		target, err := os.Readlink(aliasPath)
		if err != nil {
			continue
		}
		resolvedTarget := target
		if !filepath.IsAbs(resolvedTarget) {
			resolvedTarget = filepath.Join(aliasRoot, resolvedTarget)
		}
		resolvedTarget = filepath.Clean(resolvedTarget)
		relative, err := filepath.Rel(stateRoot, resolvedTarget)
		if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) || filepath.IsAbs(relative) {
			continue
		}
		parts := strings.Split(relative, string(filepath.Separator))
		if len(parts) != 3 || parts[0] != "browser-runtime" || parts[2] != "s" || !runRootNamePattern.MatchString(parts[1]) {
			continue
		}
		if err := os.Remove(aliasPath); err != nil && !errors.Is(err, os.ErrNotExist) {
			log.Warn("agent-browser socket alias cleanup failed for "+entry.Name(), "err", err)
		}
	}
}

func parsePositiveInt(raw string) (int, error) {
	value := 0
	for _, digit := range raw {
		if digit < '0' || digit > '9' {
			return 0, fmt.Errorf("invalid number %q", raw)
		}
		value = value*10 + int(digit-'0')
	}
	if value <= 0 {
		return 0, fmt.Errorf("non-positive number %q", raw)
	}
	return value, nil
}

type processRunner struct{}

func newProcessRunner(log *slog.Logger) CommandRunner {
	_ = log
	return processRunner{}
}

// Run spawns one packaged-binary invocation with a bounded output capture,
// hard timeout, cancellation kill, and no inherited standard input.
func (r processRunner) Run(ctx context.Context, request CommandRequest) (CommandResult, error) {
	timeout := request.Timeout
	if timeout <= 0 {
		timeout = defaultCommandTimeout
	}
	cmd := exec.Command(request.Path, request.Args...)
	cmd.SysProcAttr = childProcessAttr()
	cmd.Env = flattenEnv(request.Env)
	stdout := &boundedBuffer{limit: maxOutputBytes}
	stderr := &boundedBuffer{limit: maxOutputBytes}
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	if err := cmd.Start(); err != nil {
		return CommandResult{}, commandError("AGENT_BROWSER_START_FAILED", err.Error())
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		killChildProcess(cmd)
		awaitExit(done)
		return CommandResult{}, commandError("AGENT_BROWSER_CANCELLED", "agent-browser command was cancelled")
	case <-timer.C:
		killChildProcess(cmd)
		awaitExit(done)
		return CommandResult{}, commandError("AGENT_BROWSER_TIMEOUT", "agent-browser command timed out")
	case waitErr := <-done:
		if stdout.overflow || stderr.overflow {
			return CommandResult{}, commandError("AGENT_BROWSER_OUTPUT_TOO_LARGE", "agent-browser output exceeded Operator's limit")
		}
		result := CommandResult{Stdout: stdout.String(), Stderr: stderr.String()}
		if waitErr == nil {
			return result, nil
		}
		var exitErr *exec.ExitError
		if errors.As(waitErr, &exitErr) {
			result.ExitCode = exitErr.ExitCode()
			return result, nil
		}
		return result, commandError("AGENT_BROWSER_START_FAILED", waitErr.Error())
	}
}

func awaitExit(done <-chan error) {
	select {
	case <-done:
	case <-time.After(5 * time.Second):
	}
}

type boundedBuffer struct {
	limit    int
	buf      bytes.Buffer
	overflow bool
}

func (b *boundedBuffer) Write(p []byte) (int, error) {
	if b.buf.Len()+len(p) > b.limit {
		b.overflow = true
		return len(p), nil
	}
	return b.buf.Write(p)
}

func (b *boundedBuffer) String() string {
	return b.buf.String()
}
