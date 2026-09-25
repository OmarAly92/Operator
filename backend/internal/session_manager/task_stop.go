package sessionmanager

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/service/dialogdriver"
)

var ErrTaskPanelUnavailable = errors.New("session: the background tasks panel is not available")

type panelTiming struct {
	settle time.Duration
	appear time.Duration
	poll   time.Duration
}

var livePanelTiming = panelTiming{settle: 150 * time.Millisecond, appear: menuAppearBudget, poll: menuAppearPoll}

const maxPanelSteps = 64

func (m *Manager) StopAgentTask(ctx context.Context, id domain.SessionID, label string) error {
	lock := m.taskStopLock(id)
	lock.Lock()
	defer lock.Unlock()

	rec, err := m.commandRecord(ctx, id)
	if err != nil {
		return err
	}
	if rec.Activity.State == domain.ActivityBlocked {
		return ErrAwaitingDecision
	}
	reader, ok := m.tasksPanelReaderFor(rec.Harness)
	if !ok {
		return domain.ErrTaskStopUnsupported
	}
	if err := m.requireEmptyComposer(ctx, rec); err != nil {
		return err
	}
	screen := runtimeScreen{runtime: m.runtime, handle: runtimeHandle(rec.Metadata)}
	if err := stopTaskOnPanel(ctx, screen, reader, label, livePanelTiming); err != nil {
		return fmt.Errorf("stop task %s: %w", rec.ID, err)
	}
	return nil
}

func (m *Manager) taskStopLock(id domain.SessionID) *sync.Mutex {
	lock, _ := m.taskStops.LoadOrStore(id, &sync.Mutex{})
	if mutex, ok := lock.(*sync.Mutex); ok {
		return mutex
	}
	return &sync.Mutex{}
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
	screen dialogdriver.Screen
	reader ports.TerminalTasksPanelReader
	keys   ports.TasksPanelKeys
	timing panelTiming
}

func stopTaskOnPanel(ctx context.Context, screen dialogdriver.Screen, reader ports.TerminalTasksPanelReader, label string, timing panelTiming) error {
	s := panelSession{screen: screen, reader: reader, keys: reader.TasksPanelKeys(), timing: timing}
	if _, open, err := s.read(ctx); err != nil {
		return err
	} else if open {
		return ErrTaskPanelUnavailable
	}
	if err := s.write(ctx, s.keys.Open); err != nil {
		return err
	}
	panel, open, err := s.await(ctx)
	if err != nil {
		return err
	}
	if !open {
		return ErrTaskPanelUnavailable
	}
	for attempt := 0; attempt < 2; attempt++ {
		if panel.Detail {
			if panel.DetailStatus != "running" || !taskLabelMatches(panel.DetailLabel, label) {
				return s.closeWith(ctx, domain.ErrTaskNotFound)
			}
			if err := s.write(ctx, s.keys.Stop); err != nil {
				return err
			}
			return s.closeWith(ctx, nil)
		}
		if _, err := s.navigate(ctx, panel, label); err != nil {
			return s.closeWith(ctx, err)
		}
		if err := s.write(ctx, s.keys.Stop); err != nil {
			return err
		}
		after, open, err := s.read(ctx)
		if err != nil {
			return err
		}
		if !open {
			return nil
		}
		if after.Detail {
			return s.closeWith(ctx, nil)
		}
		if _, err := runningRow(after.Rows, label); err != nil {
			return s.closeWith(ctx, nil)
		}
		panel = after
	}
	return s.closeWith(ctx, nil)
}

func (s panelSession) navigate(ctx context.Context, panel ports.TasksPanel, label string) (ports.TasksPanel, error) {
	for step := 0; step <= maxPanelSteps; step++ {
		target, err := runningRow(panel.Rows, label)
		if err != nil {
			return panel, err
		}
		if panel.Selected == target {
			return panel, nil
		}
		key := s.keys.Down
		if panel.Selected > target {
			key = s.keys.Up
		}
		if err := s.write(ctx, key); err != nil {
			return panel, err
		}
		next, open, err := s.read(ctx)
		if err != nil {
			return panel, err
		}
		if !open || next.Detail {
			return panel, dialogdriver.ErrNotOnScreen
		}
		panel = next
	}
	return panel, dialogdriver.ErrStuck
}

func (s panelSession) closeWith(ctx context.Context, result error) error {
	if _, open, err := s.read(ctx); err == nil && open {
		_ = s.write(ctx, s.keys.Close)
	}
	return result
}

func (s panelSession) read(ctx context.Context) (ports.TasksPanel, bool, error) {
	pane, err := s.screen.Read(ctx)
	if err != nil {
		return ports.TasksPanel{}, false, fmt.Errorf("read tasks panel: %w", err)
	}
	panel, open := s.reader.ReadTasksPanel(pane)
	return panel, open, nil
}

func (s panelSession) write(ctx context.Context, keys string) error {
	if err := s.screen.Write(ctx, keys); err != nil {
		return fmt.Errorf("write tasks panel: %w", err)
	}
	return sleepContext(ctx, s.timing.settle)
}

func (s panelSession) await(ctx context.Context) (ports.TasksPanel, bool, error) {
	deadline := time.Now().Add(s.timing.appear)
	for {
		panel, open, err := s.read(ctx)
		if err != nil || open {
			return panel, open, err
		}
		if time.Now().After(deadline) {
			return ports.TasksPanel{}, false, nil
		}
		if err := sleepContext(ctx, s.timing.poll); err != nil {
			return ports.TasksPanel{}, false, err
		}
	}
}

func runningRow(rows []ports.TasksPanelRow, label string) (int, error) {
	found := -1
	for i, row := range rows {
		if row.Status != "running" || !taskLabelMatches(row.Label, label) {
			continue
		}
		if found >= 0 {
			return -1, domain.ErrTaskAmbiguous
		}
		found = i
	}
	if found < 0 {
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
