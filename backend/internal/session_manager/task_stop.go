package sessionmanager

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/service/dialogdriver"
)

type panelTiming struct {
	settle time.Duration
	appear time.Duration
	poll   time.Duration
}

var livePanelTiming = panelTiming{settle: 250 * time.Millisecond, appear: 1500 * time.Millisecond, poll: 100 * time.Millisecond}

const maxPanelSteps = 64

type composerScreen interface {
	dialogdriver.Screen
	Draft(ctx context.Context) (string, bool, error)
}

func (m *Manager) AgentTaskStopSupported(harness domain.AgentHarness, version string) bool {
	reader, ok := m.tasksPanelReaderFor(harness)
	if !ok {
		return false
	}
	if _, ok := m.composerReaderFor(harness); !ok {
		return false
	}
	if _, ok := m.emptyComposerDetectorFor(harness); !ok {
		return false
	}
	return reader.TasksPanelVerified(version)
}

func (m *Manager) StopAgentTask(ctx context.Context, id domain.SessionID, label string) error {
	if err := m.stopAgentTask(ctx, id, label); err != nil {
		return taskStopError(err)
	}
	return nil
}

func (m *Manager) stopAgentTask(ctx context.Context, id domain.SessionID, label string) error {
	if _, err := m.commandRecord(ctx, id); err != nil {
		return err
	}
	end, err := m.beginPaneDrive(ctx, id)
	if err != nil {
		return err
	}
	defer end()

	rec, err := m.commandRecord(ctx, id)
	if err != nil {
		return err
	}
	switch rec.Activity.State {
	case domain.ActivityIdle, domain.ActivityActive, domain.ActivityWaitingInput:
	case domain.ActivityBlocked:
		return ErrAwaitingDecision
	default:
		return ErrWrongActivityState
	}
	reader, ok := m.tasksPanelReaderFor(rec.Harness)
	if !ok {
		return domain.ErrTaskStopUnsupported
	}
	composer, ok := m.composerReaderFor(rec.Harness)
	if !ok {
		return domain.ErrTaskStopUnsupported
	}
	empty, ok := m.emptyComposerDetectorFor(rec.Harness)
	if !ok {
		return domain.ErrTaskStopUnsupported
	}
	styled, ok := m.runtime.(ports.StyledTerminalOutputReader)
	if !ok {
		return domain.ErrTaskStopUnsupported
	}
	screen := panelScreen{
		runtimeScreen: runtimeScreen{runtime: m.runtime, handle: runtimeHandle(rec.Metadata)},
		styled:        styled,
		composer:      composer,
		empty:         empty,
	}
	return stopTaskOnPanel(ctx, screen, reader, label, livePanelTiming, m.logger)
}

type panelScreen struct {
	runtimeScreen
	styled   ports.StyledTerminalOutputReader
	composer ports.TerminalComposerReader
	empty    ports.EmptyComposerDetector
}

const panelPaneLines = 160

func (s panelScreen) Read(ctx context.Context) (string, error) {
	return s.styled.GetStyledOutput(ctx, s.handle, panelPaneLines)
}

func (s panelScreen) Draft(ctx context.Context) (string, bool, error) {
	pane, err := s.styled.GetStyledOutput(ctx, s.handle, panelPaneLines)
	if err != nil {
		return "", false, err
	}
	if s.empty.ComposerIsEmpty(pane) {
		return "", true, nil
	}
	draft, ok := s.composer.ReadComposerDraft(pane)
	return draft, ok, nil
}

func taskStopError(err error) error {
	switch {
	case errors.Is(err, ErrNotFound):
		return fmt.Errorf("%w: %w", domain.ErrTaskSessionNotFound, err)
	case errors.Is(err, ErrTerminated), errors.Is(err, ErrAgentExited), errors.Is(err, ErrIncompleteHandle):
		return fmt.Errorf("%w: %w", domain.ErrTaskSessionNotRunning, err)
	case errors.Is(err, ErrAwaitingDecision):
		return fmt.Errorf("%w: %w", domain.ErrTaskAwaitingDecision, err)
	case errors.Is(err, ErrComposerNotEmpty):
		return fmt.Errorf("%w: %w", domain.ErrTaskComposerNotEmpty, err)
	case errors.Is(err, errAgentOperationInProgress):
		return fmt.Errorf("%w: %w", domain.ErrTaskSessionBusy, err)
	case errors.Is(err, ErrWrongActivityState):
		return fmt.Errorf("%w: %w", domain.ErrTaskSessionNotReady, err)
	case errors.Is(err, dialogdriver.ErrNotOnScreen), errors.Is(err, dialogdriver.ErrStuck):
		return fmt.Errorf("%w: %w", domain.ErrTaskPanelUnavailable, err)
	default:
		return err
	}
}

func (m *Manager) tasksPanelReaderFor(harness domain.AgentHarness) (ports.TerminalTasksPanelReader, bool) {
	if m.tasksPanelReader != nil {
		return m.tasksPanelReader, true
	}
	agent, found := m.agents.Agent(harness)
	if !found {
		return nil, false
	}
	reader, ok := agent.(ports.TerminalTasksPanelReader)
	return reader, ok
}

type panelSession struct {
	screen composerScreen
	reader ports.TerminalTasksPanelReader
	keys   ports.TasksPanelKeys
	timing panelTiming
	log    *slog.Logger
}

const (
	panelCleanupBudget = 3 * time.Second
	panelCleanupPoll   = time.Second
)

func stopTaskOnPanel(ctx context.Context, screen composerScreen, reader ports.TerminalTasksPanelReader, label string, timing panelTiming, log *slog.Logger) error {
	if log == nil {
		log = slog.Default()
	}
	s := panelSession{screen: screen, reader: reader, keys: reader.TasksPanelKeys(), timing: timing, log: log}
	if err := s.openPanel(ctx); err != nil {
		return err
	}
	panel, open, err := s.read(ctx)
	if err != nil {
		return s.closeWith(ctx, err)
	}
	if !open {
		return domain.ErrTaskPanelUnavailable
	}
	if !panel.Detail {
		if err := s.navigate(ctx, label); err != nil {
			return s.closeWith(ctx, err)
		}
		if err := s.viewSelected(ctx, label); err != nil {
			return s.closeWith(ctx, err)
		}
	}
	panel, open, err = s.read(ctx)
	if err != nil {
		return s.closeWith(ctx, err)
	}
	if !open || !panel.Detail {
		return s.closeWith(ctx, domain.ErrTaskPanelUnavailable)
	}
	if panel.DetailStatus != "running" || !taskLabelMatches(panel.DetailLabel, label) {
		return s.closeWith(ctx, domain.ErrTaskNotFound)
	}
	if err := s.write(ctx, s.keys.Stop); err != nil {
		return s.closeWith(ctx, err)
	}
	cleanup, cancel := s.cleanupContext(ctx)
	defer cancel()
	_, _ = s.until(cleanup, panelCleanupPoll, func(pane string) bool {
		after, open := s.reader.ReadTasksPanel(pane)
		return !open || !after.Detail
	})
	return s.closeWith(ctx, nil)
}

func (s panelSession) openPanel(ctx context.Context) error {
	if _, open, err := s.read(ctx); err != nil {
		return err
	} else if open {
		return domain.ErrTaskPanelUnavailable
	}
	draft, known, err := s.screen.Draft(ctx)
	if err != nil {
		return err
	}
	if !known {
		return domain.ErrTaskPanelUnavailable
	}
	if draft != "" {
		return ErrComposerNotEmpty
	}
	if err := s.write(ctx, s.keys.Command); err != nil {
		return s.abandonTyped(ctx, err)
	}
	ready, err := s.until(ctx, s.timing.appear, s.reader.TasksCommandReady)
	if err != nil || !ready {
		return s.abandonTyped(ctx, err)
	}
	if err := s.write(ctx, s.keys.Submit); err != nil {
		return s.abandonTyped(ctx, err)
	}
	opened, err := s.until(ctx, s.timing.appear, func(pane string) bool {
		_, open := s.reader.ReadTasksPanel(pane)
		return open
	})
	if err != nil || !opened {
		return s.abandonTyped(ctx, err)
	}
	return nil
}

func (s panelSession) cleanupContext(ctx context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.WithoutCancel(ctx), panelCleanupBudget)
}

func (s panelSession) abandonTyped(ctx context.Context, cause error) error {
	cleanup, cancel := s.cleanupContext(ctx)
	defer cancel()
	if cause == nil {
		cause = domain.ErrTaskPanelUnavailable
	}
	if _, open, err := s.read(cleanup); err == nil && open {
		return s.closeWith(cleanup, cause)
	}
	for attempt := 0; attempt < 2; attempt++ {
		pane, err := s.screen.Read(cleanup)
		if err != nil {
			break
		}
		if !s.reader.TasksCommandTyped(pane) {
			return cause
		}
		if err := s.write(cleanup, s.keys.Clear); err != nil {
			break
		}
		cleared, err := s.until(cleanup, panelCleanupPoll, func(pane string) bool {
			return !s.reader.TasksCommandTyped(pane)
		})
		if err == nil && cleared {
			return cause
		}
	}
	s.log.Error("tasks panel: typed command could not be cleared from the composer", "typed", s.keys.Command, "cause", cause)
	return fmt.Errorf("%w: %w", domain.ErrTaskCommandLeftTyped, cause)
}

func (s panelSession) navigate(ctx context.Context, label string) error {
	for step := 0; step <= maxPanelSteps; step++ {
		panel, open, err := s.read(ctx)
		if err != nil {
			return err
		}
		if !open || panel.Detail {
			return domain.ErrTaskPanelUnavailable
		}
		target, err := runningRow(panel.Rows, label)
		if err != nil {
			return err
		}
		if panel.Selected == target {
			return nil
		}
		key := s.keys.Down
		if panel.Selected > target {
			key = s.keys.Up
		}
		if err := s.write(ctx, key); err != nil {
			return err
		}
	}
	return dialogdriver.ErrStuck
}

func (s panelSession) viewSelected(ctx context.Context, label string) error {
	panel, open, err := s.read(ctx)
	if err != nil {
		return err
	}
	if !open || panel.Detail {
		return domain.ErrTaskPanelUnavailable
	}
	target, err := runningRow(panel.Rows, label)
	if err != nil {
		return err
	}
	if panel.Selected != target {
		return domain.ErrTaskPanelUnavailable
	}
	return s.write(ctx, s.keys.View)
}

func (s panelSession) closeWith(ctx context.Context, result error) error {
	cleanup, cancel := s.cleanupContext(ctx)
	defer cancel()
	if _, open, err := s.read(cleanup); err == nil && open {
		_ = s.write(cleanup, s.keys.Close)
	}
	return result
}

func (s panelSession) read(ctx context.Context) (ports.TasksPanel, bool, error) {
	if err := ctx.Err(); err != nil {
		return ports.TasksPanel{}, false, err
	}
	pane, err := s.screen.Read(ctx)
	if err != nil {
		return ports.TasksPanel{}, false, fmt.Errorf("read tasks panel: %w", err)
	}
	panel, open := s.reader.ReadTasksPanel(pane)
	return panel, open, nil
}

func (s panelSession) write(ctx context.Context, keys string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := s.screen.Write(ctx, keys); err != nil {
		return fmt.Errorf("write tasks panel: %w", err)
	}
	return sleepContext(ctx, s.timing.settle)
}

func (s panelSession) until(ctx context.Context, budget time.Duration, done func(pane string) bool) (bool, error) {
	deadline := time.Now().Add(budget)
	for {
		if err := ctx.Err(); err != nil {
			return false, err
		}
		pane, err := s.screen.Read(ctx)
		if err != nil {
			return false, fmt.Errorf("read tasks panel: %w", err)
		}
		if done(pane) {
			return true, nil
		}
		if time.Now().After(deadline) {
			return false, nil
		}
		if err := sleepContext(ctx, s.timing.poll); err != nil {
			return false, err
		}
	}
}

func runningRow(rows []ports.TasksPanelRow, label string) (int, error) {
	found := -1
	for i, row := range rows {
		if !taskLabelMatches(row.Label, label) {
			continue
		}
		if found >= 0 {
			return -1, domain.ErrTaskAmbiguous
		}
		found = i
	}
	if found < 0 || rows[found].Status != "running" {
		return -1, domain.ErrTaskNotFound
	}
	return found, nil
}

func taskLabelMatches(shown, label string) bool {
	shown = strings.Join(strings.Fields(shown), " ")
	label = strings.Join(strings.Fields(label), " ")
	if shown == "" || label == "" {
		return false
	}
	if shown == label {
		return true
	}
	prefix, truncated := strings.CutSuffix(shown, "…")
	prefix = strings.TrimSpace(prefix)
	return truncated && prefix != "" && strings.HasPrefix(label, prefix)
}
