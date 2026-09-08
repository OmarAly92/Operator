package daemon

import (
	"context"
	"log/slog"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	projectsvc "github.com/OmarAly92/operator/backend/internal/service/project"
	shelltermsvc "github.com/OmarAly92/operator/backend/internal/service/shellterm"
	capturesvc "github.com/OmarAly92/operator/backend/internal/service/terminalcapture"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite"
)

// startShellTerminals builds the standalone shell terminal service and sweeps
// any terminals left behind by a previous app run.
//
// The sweep runs at boot, before the server serves, for the same reason session
// reconciliation does: a client that connects first would otherwise see — and
// try to attach to — shells belonging to an app that is already gone.
func startShellTerminals(
	ctx context.Context,
	cfg config.Config,
	runtime shelltermsvc.ShellRuntime,
	store *sqlite.Store,
	projects projectsvc.Manager,
	captureSup *capturesvc.Supervisor,
	log *slog.Logger,
) *shelltermsvc.Service {
	var capture shelltermsvc.BlockCaptureLifecycle
	if captureSup != nil {
		capture = captureSup
	}
	svc := shelltermsvc.NewService(
		runtime,
		store,
		&projectRootLocator{projects: projects},
		&sessionWorkspaceLocator{store: store},
		capture,
		cfg.DataDir,
		cfg.AppRunID,
		log,
	)
	// Best-effort: a failed sweep must never block boot. The rows survive and
	// the next boot retries.
	if _, err := svc.ReapShellTerminalsFromPreviousAppRuns(ctx); err != nil {
		log.Warn("reaping shell terminals from previous app runs failed", "err", err)
	}

	if captureSup != nil {
		live, err := svc.LiveShellTerminalRecordsForCurrentAppRun(ctx)
		if err != nil {
			log.Warn("listing shell terminals for capture adoption failed", "err", err)
		} else if err := captureSup.Adopt(ctx, live); err != nil {
			log.Warn("adopting shell block capture failed", "err", err)
		}
	}
	return svc
}

// sessionWorkspaceLocator adapts the session store to the narrow lookup a
// session-scoped shell needs: an id in, the session's directory out.
//
// It reads the store rather than the session service on purpose. The service's
// Get derives the whole read model — status, PR facts, activity — none of
// which a shell's working directory depends on, and the durable record already
// holds the one fact that matters.
type sessionWorkspaceLocator struct {
	store *sqlite.Store
}

// SessionWorkspace returns the session's own directory: its worktree when it
// has one, the project checkout when it runs in place. Session Manager writes
// both into the same field, so there is no mode to branch on here.
func (l *sessionWorkspaceLocator) SessionWorkspace(ctx context.Context, id domain.SessionID) (string, domain.ProjectID, bool, error) {
	if l.store == nil {
		return "", "", false, nil
	}
	rec, ok, err := l.store.GetSession(ctx, id)
	if err != nil || !ok {
		return "", "", false, err
	}
	return rec.Metadata.WorkspacePath, rec.ProjectID, true, nil
}

// projectRootLocator adapts the project service to the narrow lookup the shell
// terminal service needs: an id in, a directory out.
type projectRootLocator struct {
	projects projectsvc.Manager
}

// ProjectRoot returns the project's path, or "" when no such project exists so
// the caller can answer 404. A degraded project (its config failed to load)
// still has a usable path on disk, and a shell in it is exactly the tool a user
// would want to fix it with — so degraded is resolved, not rejected.
func (l *projectRootLocator) ProjectRoot(ctx context.Context, id domain.ProjectID) (string, error) {
	if l.projects == nil {
		return "", nil
	}
	res, err := l.projects.Get(ctx, id)
	if err != nil {
		return "", err
	}
	switch {
	case res.Project != nil:
		return res.Project.Path, nil
	case res.Degraded != nil:
		return res.Degraded.Path, nil
	default:
		return "", nil
	}
}
