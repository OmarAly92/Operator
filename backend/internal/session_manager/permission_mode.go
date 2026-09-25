package sessionmanager

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/service/dialogdriver"
)

var (
	ErrPermissionModeUnsupported = errors.New("session: permission mode cannot be changed for this session")
	ErrPermissionModeUnconfirmed = errors.New("session: the terminal did not confirm the permission mode")
)

const (
	maxPermissionModePresses     = 6
	permissionRestartSettleDelay = 750 * time.Millisecond
)

type permissionModeTiming struct {
	appear time.Duration
	poll   time.Duration
}

var livePermissionModeTiming = permissionModeTiming{appear: 1500 * time.Millisecond, poll: 100 * time.Millisecond}

type PermissionModeResult struct {
	Mode      domain.PermissionMode
	Restarted bool
}

type PermissionModeObserver interface {
	LatestPermissionMode(ctx context.Context, id domain.SessionID) (domain.PermissionModeObservation, bool, error)
}

func (m *Manager) SetPermissionModeObserver(observer PermissionModeObserver) {
	m.permissionModesMu.Lock()
	defer m.permissionModesMu.Unlock()
	m.permissionModes = observer
}

func (m *Manager) permissionModeObserver() PermissionModeObserver {
	m.permissionModesMu.Lock()
	defer m.permissionModesMu.Unlock()
	return m.permissionModes
}

func (m *Manager) permissionModeReaderFor(harness domain.AgentHarness) (ports.TerminalPermissionModeReader, bool) {
	if m.permissionModeReader != nil {
		return m.permissionModeReader, true
	}
	agent, found := m.agents.Agent(harness)
	if !found {
		return nil, false
	}
	reader, ok := agent.(ports.TerminalPermissionModeReader)
	return reader, ok
}

func (m *Manager) PermissionModeReadable(harness domain.AgentHarness) bool {
	_, ok := m.permissionModeReaderFor(harness)
	return ok
}

func (m *Manager) PermissionModeSupport(harness domain.AgentHarness, launch domain.PermissionMode, version string) (bool, []domain.PermissionMode) {
	reader, ok := m.permissionModeReaderFor(harness)
	if !ok || !reader.PermissionModeVerified(version) {
		return false, nil
	}
	return true, reader.PermissionModeCycle(ports.NormalizePermissionMode(launch))
}

func (m *Manager) SetPermissionMode(ctx context.Context, id domain.SessionID, target domain.PermissionMode) (PermissionModeResult, error) {
	if target == "" || !target.Valid() {
		return PermissionModeResult{}, ErrPermissionModeUnsupported
	}
	rec, err := m.commandRecord(ctx, id)
	if err != nil {
		return PermissionModeResult{}, err
	}
	reader, ok := m.permissionModeReaderFor(rec.Harness)
	if !ok {
		return PermissionModeResult{}, ErrPermissionModeUnsupported
	}
	observation, err := m.observedPermissionMode(ctx, id)
	if err != nil {
		return PermissionModeResult{}, err
	}
	if !reader.PermissionModeVerified(observation.Version) {
		return PermissionModeResult{}, ErrPermissionModeUnsupported
	}
	project, err := m.loadProject(ctx, rec.ProjectID)
	if err != nil {
		return PermissionModeResult{}, fmt.Errorf("permission mode %s: %w", id, err)
	}
	launch := sessionAgentConfig(rec, project.Config).Permissions
	if slices.Contains(reader.PermissionModeCycle(ports.NormalizePermissionMode(launch)), target) {
		return m.cyclePermissionMode(ctx, id, reader, target)
	}
	return m.restartWithPermissionMode(ctx, id, target)
}

func (m *Manager) observedPermissionMode(ctx context.Context, id domain.SessionID) (domain.PermissionModeObservation, error) {
	observer := m.permissionModeObserver()
	if observer == nil {
		return domain.PermissionModeObservation{}, nil
	}
	observation, _, err := observer.LatestPermissionMode(ctx, id)
	if err != nil {
		return domain.PermissionModeObservation{}, fmt.Errorf("permission mode %s: %w", id, err)
	}
	return observation, nil
}

func (m *Manager) cyclePermissionMode(ctx context.Context, id domain.SessionID, reader ports.TerminalPermissionModeReader, target domain.PermissionMode) (PermissionModeResult, error) {
	end, err := m.beginPaneDrive(ctx, id)
	if err != nil {
		return PermissionModeResult{}, commandDriveError(err)
	}
	defer end()
	allowed := func(ctx context.Context) (domain.SessionRecord, error) {
		rec, err := m.commandRecord(ctx, id)
		if err != nil {
			return domain.SessionRecord{}, err
		}
		return rec, permissionChangeAllowed(rec, ErrWrongActivityState)
	}
	rec, err := allowed(ctx)
	if err != nil {
		return PermissionModeResult{}, err
	}
	screen := runtimeScreen{runtime: m.runtime, handle: runtimeHandle(rec.Metadata)}
	pressAllowed := func(ctx context.Context) error {
		_, err := allowed(ctx)
		return err
	}
	mode, err := drivePermissionMode(ctx, screen, reader, target, m.permissionModeTiming, pressAllowed)
	return PermissionModeResult{Mode: mode}, err
}

func drivePermissionMode(ctx context.Context, screen dialogdriver.Screen, reader ports.TerminalPermissionModeReader, target domain.PermissionMode, timing permissionModeTiming, pressAllowed func(context.Context) error) (domain.PermissionMode, error) {
	current, err := awaitPermissionMode(ctx, screen, reader, "", timing)
	if err != nil {
		return "", err
	}
	start := current
	for presses := 0; current != target; presses++ {
		if presses == maxPermissionModePresses {
			return current, ErrPermissionModeUnconfirmed
		}
		if err := pressAllowed(ctx); err != nil {
			return current, err
		}
		if err := screen.Write(ctx, reader.PermissionModeKeys().Cycle); err != nil {
			return current, fmt.Errorf("permission mode: press: %w", err)
		}
		next, err := awaitPermissionMode(ctx, screen, reader, current, timing)
		if err != nil {
			return current, err
		}
		current = next
		if current == start {
			return current, ErrPermissionModeUnconfirmed
		}
	}
	return current, nil
}

func awaitPermissionMode(ctx context.Context, screen dialogdriver.Screen, reader ports.TerminalPermissionModeReader, previous domain.PermissionMode, timing permissionModeTiming) (domain.PermissionMode, error) {
	deadline := time.Now().Add(timing.appear)
	for {
		pane, err := screen.Read(ctx)
		if err != nil {
			return "", fmt.Errorf("permission mode: read: %w", err)
		}
		if mode, ok := reader.ReadPermissionMode(pane); ok && mode != previous {
			return mode, nil
		}
		if time.Now().After(deadline) {
			return "", ErrPermissionModeUnconfirmed
		}
		if err := sleepContext(ctx, timing.poll); err != nil {
			return "", err
		}
	}
}

func (m *Manager) restartWithPermissionMode(ctx context.Context, id domain.SessionID, target domain.PermissionMode) (PermissionModeResult, error) {
	rec, err := m.commandRecord(ctx, id)
	if err != nil {
		return PermissionModeResult{}, err
	}
	if err := permissionChangeAllowed(rec, ErrSessionBusy); err != nil {
		return PermissionModeResult{}, err
	}
	if m.paneDriveActive(id) {
		return PermissionModeResult{}, ErrSessionBusy
	}
	if err := m.beginAgentOperation(ctx, id, agentOperationRelaunch); err != nil {
		if errors.Is(err, errAgentOperationInProgress) {
			return PermissionModeResult{}, ErrSessionBusy
		}
		return PermissionModeResult{}, err
	}
	defer m.endAgentOperation(id, agentOperationRelaunch)
	if m.paneDriveActive(id) {
		return PermissionModeResult{}, ErrSessionBusy
	}
	if err := m.permissionRestartSettle(ctx); err != nil {
		return PermissionModeResult{}, err
	}
	rec, err = m.commandRecord(ctx, id)
	if err != nil {
		return PermissionModeResult{}, err
	}
	if err := permissionChangeAllowed(rec, ErrSessionBusy); err != nil {
		return PermissionModeResult{}, err
	}
	project, err := m.loadProject(ctx, rec.ProjectID)
	if err != nil {
		return PermissionModeResult{}, fmt.Errorf("permission mode %s: %w", id, err)
	}
	meta := rec.Metadata
	if meta.WorkspacePath == "" || (meta.Branch == "" && project.Kind.WithDefault() != domain.ProjectKindScratch) {
		return PermissionModeResult{}, fmt.Errorf("permission mode %s: %w", id, ErrIncompleteHandle)
	}
	ws := ports.WorkspaceInfo{
		Path:      meta.WorkspacePath,
		Branch:    meta.Branch,
		SessionID: rec.ID,
		ProjectID: rec.ProjectID,
		Mode:      meta.WorkspaceMode,
	}
	handle := ports.RuntimeHandle{ID: meta.RuntimeHandleID}
	if _, err := m.relaunchSessionWithPolicy(ctx, "permission mode", rec, project, ws, &handle, ports.PaneGrid{}, relaunchPolicy{permissions: target}); err != nil {
		return PermissionModeResult{}, err
	}
	return PermissionModeResult{Mode: target, Restarted: true}, nil
}

func permissionChangeAllowed(rec domain.SessionRecord, busy error) error {
	switch rec.Activity.State {
	case domain.ActivityIdle, domain.ActivityWaitingInput:
		return nil
	case domain.ActivityBlocked:
		return ErrAwaitingDecision
	default:
		return busy
	}
}
