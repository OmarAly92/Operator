package shellterm

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/packages/terminal/go/bootstrap"
)

// ShellRuntime is the slice of the runtime adapter a shell terminal needs:
// spawn a PTY around an argv, tear it down, and answer whether it is still
// alive. It is deliberately narrower than ports.Runtime — a shell terminal
// never reads captured output the way the activity observer does.
type ShellRuntime interface {
	Create(ctx context.Context, cfg ports.RuntimeConfig) (ports.RuntimeHandle, error)
	Destroy(ctx context.Context, handle ports.RuntimeHandle) error
	IsAlive(ctx context.Context, handle ports.RuntimeHandle) (bool, error)
}

// ProjectRootLocator resolves a project id to the directory a shell should
// start in. The daemon wiring adapts the project service to it.
type ProjectRootLocator interface {
	ProjectRoot(ctx context.Context, id domain.ProjectID) (string, error)
}

type BlockCaptureLifecycle interface {
	Start(context.Context, ShellTerminalRecord) error
	StopAndDrain(context.Context, string) error
	Capturing(handleID string) bool
}

// Service opens, lists, and closes standalone shell terminals.
//
// appRunID is minted once per desktop-app launch and is the mechanism behind
// the feature's lifetime rule: shells must survive a DAEMON restart but die
// with the APP. Rows tagged with the current run are re-attachable; rows tagged
// with any other run are orphans from an app that exited without closing them
// (a crash or force-kill, where the clean shutdown path never ran) and are
// destroyed at boot by ReapShellTerminalsFromPreviousAppRuns.
type Service struct {
	runtime  ShellRuntime
	store    Store
	projects ProjectRootLocator
	capture  BlockCaptureLifecycle
	dataDir  string
	appRunID string
	log      *slog.Logger

	// now and newHandleID are injectable so tests can assert on exact ids and
	// timestamps without a clock or entropy dependency.
	now         func() time.Time
	newHandleID func() (string, error)
}

// NewService builds the shell terminal service. dataDir is the fallback working
// directory for a shell opened with no project context. A nil logger falls back
// to slog.Default.
func NewService(runtime ShellRuntime, store Store, projects ProjectRootLocator, capture BlockCaptureLifecycle, dataDir, appRunID string, log *slog.Logger) *Service {
	if log == nil {
		log = slog.Default()
	}
	return &Service{
		runtime:     runtime,
		store:       store,
		projects:    projects,
		capture:     capture,
		dataDir:     dataDir,
		appRunID:    appRunID,
		log:         log,
		now:         time.Now,
		newHandleID: newShellTerminalHandleID,
	}
}

// OpenShellTerminal spawns a shell PTY and records it against the current app
// run. The runtime is created BEFORE the row is written, and rolled back if the
// write fails, so a persisted row always names a PTY that actually exists —
// otherwise a restart would try to re-attach to a handle that was never spawned.
func (s *Service) OpenShellTerminal(ctx context.Context, in OpenShellTerminalInput) (ShellTerminal, error) {
	workingDir, projectID, err := s.resolveShellTerminalWorkingDir(ctx, in.ProjectID)
	if err != nil {
		return ShellTerminal{}, err
	}
	resolved := resolveUserLoginShell()
	if len(resolved) == 0 {
		return ShellTerminal{}, apierr.Internal("SHELL_TERMINAL_NO_SHELL",
			"Could not determine a shell to launch. Set SHELL (macOS/Linux) or ComSpec (Windows).")
	}
	argv, env, err := s.shellBootstrapArgvEnv(resolved[0])
	if err != nil {
		return ShellTerminal{}, fmt.Errorf("open shell terminal: shell recipe: %w", err)
	}
	handleID, err := s.newHandleID()
	if err != nil {
		return ShellTerminal{}, fmt.Errorf("open shell terminal: handle id: %w", err)
	}
	env["OPERATOR_TERMINAL_ID"] = handleID

	// SessionID is the runtime adapters' name for "what to call this PTY"; it
	// is not a session row and no sessions record is ever created. The
	// shellterm- prefix keeps the two namespaces disjoint.
	handle, err := s.runtime.Create(ctx, ports.RuntimeConfig{
		SessionID:     domain.SessionID(handleID),
		WorkspacePath: workingDir,
		Argv:          argv,
		Env:           env,
	})
	if err != nil {
		return ShellTerminal{}, fmt.Errorf("open shell terminal %s: runtime: %w", handleID, err)
	}

	rec := ShellTerminalRecord{
		HandleID:   handle.ID,
		ProjectID:  projectID,
		WorkingDir: workingDir,
		Title:      shellTerminalTitle(workingDir),
		AppRunID:   s.appRunID,
		CreatedAt:  s.now().UTC(),
	}
	if err := s.store.InsertShellTerminal(ctx, rec); err != nil {
		// Roll back the PTY: an unrecorded runtime would never be reaped,
		// leaking a pty-host for the life of the machine.
		if destroyErr := s.runtime.Destroy(context.WithoutCancel(ctx), handle); destroyErr != nil {
			s.log.Warn("shell terminal rollback failed; runtime may be orphaned",
				"handleId", handle.ID, "error", destroyErr)
		}
		return ShellTerminal{}, fmt.Errorf("open shell terminal %s: persist: %w", handle.ID, err)
	}

	out := shellTerminalFromRecord(rec)
	if s.capture != nil {
		if startErr := s.capture.Start(ctx, rec); startErr != nil && !errors.Is(startErr, ports.ErrCaptureUnsupported) {
			if stillAlive, _ := s.destroyConfirmed(context.WithoutCancel(ctx), handle.ID); stillAlive {
				s.log.Warn("shell terminal: capture start failed and runtime would not die",
					"handleId", handle.ID)
			}
			return ShellTerminal{}, fmt.Errorf("open shell terminal %s: start capture: %w", handle.ID, startErr)
		}
	}
	out.DurableBlocks = s.capturing(handle.ID)

	s.log.Info("shell terminal opened", "handleId", handle.ID, "workingDir", workingDir, "durableBlocks", out.DurableBlocks)
	return out, nil
}

// maxShellTerminalTitleLen bounds a user-supplied tab name. Tabs are truncated
// in the UI anyway; this only stops an unbounded string reaching the DB.
const maxShellTerminalTitleLen = 80

// RenameShellTerminal sets a shell terminal's tab title. The title is trimmed
// and must be non-empty and within the length bound; an unknown handle is a 404.
func (s *Service) RenameShellTerminal(ctx context.Context, handleID, title string) (ShellTerminal, error) {
	if handleID == "" {
		return ShellTerminal{}, apierr.Invalid("SHELL_TERMINAL_ID_REQUIRED", "A shell terminal id is required", nil)
	}
	title = strings.TrimSpace(title)
	if title == "" {
		return ShellTerminal{}, apierr.Invalid("SHELL_TERMINAL_TITLE_REQUIRED", "A shell terminal title is required", nil)
	}
	if utf8.RuneCountInString(title) > maxShellTerminalTitleLen {
		return ShellTerminal{}, apierr.Invalid("SHELL_TERMINAL_TITLE_TOO_LONG",
			fmt.Sprintf("A shell terminal title must be at most %d characters", maxShellTerminalTitleLen), nil)
	}
	rec, found, err := s.store.UpdateShellTerminalTitle(ctx, handleID, title)
	if err != nil {
		return ShellTerminal{}, fmt.Errorf("rename shell terminal %s: %w", handleID, err)
	}
	if !found {
		return ShellTerminal{}, apierr.NotFound("SHELL_TERMINAL_NOT_FOUND", "No such shell terminal: "+handleID)
	}
	s.log.Info("shell terminal renamed", "handleId", handleID)
	out := shellTerminalFromRecord(rec)
	out.DurableBlocks = s.capturing(handleID)
	return out, nil
}

// CloseShellTerminal destroys a shell's PTY and forgets it — but only once
// death is confirmed (see destroyConfirmed): a shell that survives Destroy
// keeps its row, so it stays visible/re-attachable instead of vanishing from
// tracking while still running.
func (s *Service) CloseShellTerminal(ctx context.Context, handleID string) error {
	if handleID == "" {
		return apierr.Invalid("SHELL_TERMINAL_ID_REQUIRED", "A shell terminal id is required", nil)
	}
	_, found, err := s.store.SelectShellTerminalByHandleID(ctx, handleID)
	if err != nil {
		return fmt.Errorf("close shell terminal %s: %w", handleID, err)
	}
	if !found {
		return apierr.NotFound("SHELL_TERMINAL_NOT_FOUND", "No such shell terminal: "+handleID)
	}

	if s.capture != nil {
		if err := s.capture.StopAndDrain(ctx, handleID); err != nil {
			return fmt.Errorf("close shell terminal %s: stop capture: %w", handleID, err)
		}
	}

	stillAlive, destroyErr := s.destroyConfirmed(ctx, handleID)
	if stillAlive {
		s.log.Warn("close shell terminal: runtime still alive after destroy", "handleId", handleID, "error", destroyErr)
		return apierr.Conflict("SHELL_TERMINAL_STILL_RUNNING",
			"The shell process is still running; try closing it again in a moment", nil)
	}
	return nil
}

// ListShellTerminalsForCurrentAppRun returns the shells the running app owns,
// dropping any whose PTY has died (the user typed `exit`, or the machine
// rebooted out from under a persisted row). Dead rows are deleted as they are
// found, so the list the UI renders only ever contains attachable panes.
//
// A liveness probe that ERRORS is not treated as proof of death — the same rule
// internal/terminal applies on attach — so a transient runtime hiccup cannot
// silently delete a working terminal.
func (s *Service) ListShellTerminalsForCurrentAppRun(ctx context.Context) ([]ShellTerminal, error) {
	recs, err := s.liveShellTerminalRecordsForCurrentAppRun(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]ShellTerminal, 0, len(recs))
	for _, rec := range recs {
		dto := shellTerminalFromRecord(rec)
		dto.DurableBlocks = s.capturing(rec.HandleID)
		out = append(out, dto)
	}
	return out, nil
}

func (s *Service) capturing(handleID string) bool {
	return s.capture != nil && s.capture.Capturing(handleID)
}

func (s *Service) LiveShellTerminalRecordsForCurrentAppRun(ctx context.Context) ([]ShellTerminalRecord, error) {
	return s.liveShellTerminalRecordsForCurrentAppRun(ctx)
}

func (s *Service) liveShellTerminalRecordsForCurrentAppRun(ctx context.Context) ([]ShellTerminalRecord, error) {
	recs, err := s.store.SelectShellTerminalsByAppRunID(ctx, s.appRunID)
	if err != nil {
		return nil, fmt.Errorf("list shell terminals: %w", err)
	}
	out := make([]ShellTerminalRecord, 0, len(recs))
	for _, rec := range recs {
		alive, err := s.runtime.IsAlive(ctx, ports.RuntimeHandle{ID: rec.HandleID})
		if err != nil {
			s.log.Warn("shell terminal liveness probe failed; keeping row",
				"handleId", rec.HandleID, "error", err)
			out = append(out, rec)
			continue
		}
		if !alive {
			if s.capture != nil {
				if err := s.capture.StopAndDrain(ctx, rec.HandleID); err != nil {
					s.log.Warn("pruning dead shell terminal: final drain failed", "handleId", rec.HandleID, "error", err)
				}
			}
			if _, delErr := s.store.DeleteShellTerminalByHandleID(ctx, rec.HandleID); delErr != nil {
				s.log.Warn("pruning dead shell terminal failed", "handleId", rec.HandleID, "error", delErr)
			}
			continue
		}
		out = append(out, rec)
	}
	return out, nil
}

// ReapShellTerminalsFromPreviousAppRuns destroys shells left behind by an
// earlier app run and returns how many rows it cleared. This is the half of the
// lifetime rule the clean shutdown path cannot cover: when the app crashes or
// is force-killed, nothing gets to close its terminals, so they are swept here
// on the next boot instead of leaking forever.
//
// Runtime teardown is per-handle and confirmed-dead (see destroyConfirmed): one
// un-destroyable, still-alive PTY does not stop the rest from being reaped, but
// its own row is deliberately kept rather than blindly wiped — a boot-time
// reconciliation pass reading this session's shells later must still be able
// to see it before removing the worktree it points at.
func (s *Service) ReapShellTerminalsFromPreviousAppRuns(ctx context.Context) (int64, error) {
	orphans, err := s.store.SelectShellTerminalsFromPreviousAppRuns(ctx, s.appRunID)
	if err != nil {
		return 0, fmt.Errorf("reap shell terminals: %w", err)
	}
	var cleared int64
	for _, rec := range orphans {
		if s.capture != nil {
			if err := s.capture.StopAndDrain(ctx, rec.HandleID); err != nil {
				s.log.Warn("reaping orphaned shell terminal: final drain failed", "handleId", rec.HandleID, "error", err)
			}
		}
		stillAlive, destroyErr := s.destroyConfirmed(ctx, rec.HandleID)
		if stillAlive {
			s.log.Warn("reaping orphaned shell terminal: runtime still alive after destroy",
				"handleId", rec.HandleID, "appRunId", rec.AppRunID, "error", destroyErr)
			continue
		}
		cleared++
	}
	if cleared > 0 {
		s.log.Info("reaped shell terminals from previous app runs", "count", cleared)
	}
	return cleared, nil
}

// destroyConfirmed is the one place a shell terminal's row is allowed to
// disappear: it destroys the runtime behind handleID and deletes the row only
// once death is confirmed, so CloseShellTerminal, ReapShellTerminalsFromPreviousAppRuns,
// and BeginSessionTeardown can't each independently forget a shell that
// actually survived.
//
//   - A clean Destroy is confirmed dead.
//   - A Destroy error is followed by an IsAlive check; an IsAlive error is
//     treated the same as "alive" (unknown state must never let a live shell's
//     row vanish) — only an explicit "not alive" counts as confirmed dead.
//
// Returns stillAlive=true when the row was deliberately kept because death
// could not be confirmed. Callers that need 404-for-unknown-handle semantics
// (CloseShellTerminal) look the row up themselves beforehand — by the time
// destroyConfirmed runs, the handle is already known to exist.
func (s *Service) destroyConfirmed(ctx context.Context, handleID string) (stillAlive bool, destroyErr error) {
	destroyErr = s.runtime.Destroy(ctx, ports.RuntimeHandle{ID: handleID})
	if destroyErr != nil {
		alive, aliveErr := s.runtime.IsAlive(ctx, ports.RuntimeHandle{ID: handleID})
		if aliveErr != nil || alive {
			return true, destroyErr
		}
	}
	if _, err := s.store.DeleteShellTerminalByHandleID(ctx, handleID); err != nil {
		s.log.Warn("shell terminal: delete row after destroy failed", "handleId", handleID, "error", err)
	}
	return false, nil
}

// resolveShellTerminalWorkingDir picks where the shell starts: the project
// root when a project is named, else the daemon's data dir. It also returns
// the project the shell ended up attributed to.
func (s *Service) resolveShellTerminalWorkingDir(ctx context.Context, projectID domain.ProjectID) (workingDir string, resolvedProjectID domain.ProjectID, err error) {
	dir, err := s.resolveProjectRootOrDataDir(ctx, projectID)
	if err != nil {
		return "", "", err
	}
	return dir, projectID, nil
}

// resolveProjectRootOrDataDir picks the project root when a project is named,
// else the daemon's data dir.
func (s *Service) resolveProjectRootOrDataDir(ctx context.Context, projectID domain.ProjectID) (string, error) {
	if projectID == "" {
		if s.dataDir == "" {
			return "", apierr.Internal("SHELL_TERMINAL_NO_WORKING_DIR",
				"No project selected and the daemon has no data dir to fall back to")
		}
		return s.dataDir, nil
	}
	if s.projects == nil {
		return "", apierr.Internal("SHELL_TERMINAL_NO_PROJECT_LOOKUP",
			"Project lookup is unavailable")
	}
	root, err := s.projects.ProjectRoot(ctx, projectID)
	if err != nil {
		return "", fmt.Errorf("open shell terminal: resolve project %s: %w", projectID, err)
	}
	if root == "" {
		return "", apierr.NotFound("SHELL_TERMINAL_PROJECT_NOT_FOUND",
			"No such project: "+string(projectID))
	}
	return root, nil
}

func (s *Service) shellBootstrapArgvEnv(shellPath string) ([]string, map[string]string, error) {
	scriptDir := filepath.Join(s.dataDir, "shell")
	if kind, ok := shellKindFor(shellPath); ok {
		argv, env, err := bootstrap.Recipe(kind, scriptDir, bootstrap.Options{Integration: bootstrap.IntegrationAuto})
		if err != nil {
			return nil, nil, err
		}
		argv[0] = shellPath
		return argv, env, nil
	}
	argv, env, err := bootstrap.Recipe(shellPath, scriptDir, bootstrap.Options{Integration: bootstrap.IntegrationOSC133Only})
	if err != nil {
		return nil, nil, err
	}
	return argv, env, nil
}

// newShellTerminalHandleID mints a runtime handle id for a shell pane.
//
// The shellterm- prefix keeps shell handles trivially distinguishable from
// session handles in logs, the DB, and the mux. The character set is
// constrained by the runtime adapters, which are stricter than they look:
// the pty-host rejects anything outside ^[a-zA-Z0-9_-]+$ and uses the id as a
// session name — so hex, not base64.
func newShellTerminalHandleID() (string, error) {
	buf := make([]byte, 8)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return "shellterm-" + hex.EncodeToString(buf), nil
}

func shellTerminalFromRecord(rec ShellTerminalRecord) ShellTerminal {
	return ShellTerminal{
		HandleID:   rec.HandleID,
		ProjectID:  rec.ProjectID,
		WorkingDir: rec.WorkingDir,
		Title:      rec.Title,
		CreatedAt:  rec.CreatedAt,
	}
}
