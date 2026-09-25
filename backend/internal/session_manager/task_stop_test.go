package sessionmanager

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type panelTask struct {
	label   string
	running bool
}

type fakeTasksTUI struct {
	tasks         []panelTask
	open          bool
	detail        bool
	selected      int
	swallowNextX  bool
	ignoreOpen    bool
	openOnArrival bool
	writes        []string
}

func (f *fakeTasksTUI) visible() []panelTask {
	var out []panelTask
	for _, task := range f.tasks {
		if task.running {
			out = append(out, task)
		}
	}
	return out
}

func (f *fakeTasksTUI) Read(context.Context) (string, error) {
	if f.openOnArrival {
		f.openOnArrival = false
		f.open = true
	}
	if !f.open {
		return "composer", nil
	}
	visible := f.visible()
	panel := ports.TasksPanel{Detail: f.detail, Selected: -1}
	if f.detail {
		panel.DetailLabel = visible[0].label
		panel.DetailStatus = "running"
	} else {
		for _, task := range visible {
			panel.Rows = append(panel.Rows, ports.TasksPanelRow{Label: task.label, Status: "running"})
		}
		panel.Selected = f.selected
	}
	encoded, _ := json.Marshal(panel)
	return string(encoded), nil
}

func (f *fakeTasksTUI) Write(_ context.Context, keys string) error {
	f.writes = append(f.writes, keys)
	switch keys {
	case "/tasks\r":
		if f.ignoreOpen {
			return nil
		}
		f.open = true
		f.selected = 0
		f.detail = len(f.visible()) == 1
	case "\x1b[B":
		if f.open && !f.detail && f.selected < len(f.visible())-1 {
			f.selected++
		}
	case "\x1b[A":
		if f.open && !f.detail && f.selected > 0 {
			f.selected--
		}
	case "x":
		if !f.open {
			return nil
		}
		if f.swallowNextX {
			f.swallowNextX = false
			return nil
		}
		target := f.visible()[max(f.selected, 0)].label
		for i := range f.tasks {
			if f.tasks[i].label == target && f.tasks[i].running {
				f.tasks[i].running = false
				break
			}
		}
		if f.detail {
			f.open = false
			return nil
		}
		f.selected = min(f.selected, len(f.visible())-1)
		if len(f.visible()) == 0 {
			f.open = false
		}
	case "\x1b":
		f.open = false
	}
	return nil
}

type jsonPanelReader struct{}

func (jsonPanelReader) ReadTasksPanel(pane string) (ports.TasksPanel, bool) {
	var panel ports.TasksPanel
	if err := json.Unmarshal([]byte(pane), &panel); err != nil {
		return ports.TasksPanel{}, false
	}
	return panel, true
}

func (jsonPanelReader) TasksPanelKeys() ports.TasksPanelKeys {
	return ports.TasksPanelKeys{Open: "/tasks\r", Up: "\x1b[A", Down: "\x1b[B", Stop: "x", Close: "\x1b"}
}

func stopOn(t *testing.T, tui *fakeTasksTUI, label string) error {
	t.Helper()
	return stopTaskOnPanel(context.Background(), tui, jsonPanelReader{}, label, panelTiming{appear: 5 * time.Millisecond, poll: time.Millisecond})
}

func TestStopTaskOnPanelNavigatesToTheRowStopsAndCloses(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"sleep 900", true}, {"sleeper", true}, {"reviewer", true}}}
	if err := stopOn(t, tui, "reviewer"); err != nil {
		t.Fatalf("stop: %v", err)
	}
	want := []string{"/tasks\r", "\x1b[B", "\x1b[B", "x", "\x1b"}
	if !slices.Equal(tui.writes, want) {
		t.Fatalf("writes = %q want %q", tui.writes, want)
	}
	if tui.tasks[2].running || !tui.tasks[1].running || tui.open {
		t.Fatalf("tui = %+v", tui)
	}
}

func TestStopTaskOnPanelInDetailViewDoesNotEscapeAClosedPanel(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"sleeper", true}}}
	if err := stopOn(t, tui, "sleeper"); err != nil {
		t.Fatalf("stop: %v", err)
	}
	want := []string{"/tasks\r", "x"}
	if !slices.Equal(tui.writes, want) {
		t.Fatalf("writes = %q want %q", tui.writes, want)
	}
}

func TestStopTaskOnPanelDetailForAnotherTaskBacksOut(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"sleep 900", true}}}
	if err := stopOn(t, tui, "sleeper"); !errors.Is(err, domain.ErrTaskNotFound) {
		t.Fatalf("err = %v", err)
	}
	want := []string{"/tasks\r", "\x1b"}
	if !slices.Equal(tui.writes, want) || !tui.tasks[0].running {
		t.Fatalf("writes = %q tasks %+v", tui.writes, tui.tasks)
	}
}

func TestStopTaskOnPanelRetriesASwallowedStop(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"a", true}, {"b", true}}, swallowNextX: true}
	if err := stopOn(t, tui, "b"); err != nil {
		t.Fatalf("stop: %v", err)
	}
	want := []string{"/tasks\r", "\x1b[B", "x", "x", "\x1b"}
	if !slices.Equal(tui.writes, want) || tui.tasks[1].running || !tui.tasks[0].running {
		t.Fatalf("writes = %q tasks %+v", tui.writes, tui.tasks)
	}
}

func TestStopTaskOnPanelRefusesAmbiguousRows(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"sleeper", true}, {"sleeper", true}}}
	if err := stopOn(t, tui, "sleeper"); !errors.Is(err, domain.ErrTaskAmbiguous) {
		t.Fatalf("err = %v", err)
	}
	if slices.Contains(tui.writes, "x") || tui.open {
		t.Fatalf("writes = %q open %v", tui.writes, tui.open)
	}
}

func TestStopTaskOnPanelMissingRow(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"a", true}, {"b", true}}}
	if err := stopOn(t, tui, "c"); !errors.Is(err, domain.ErrTaskNotFound) {
		t.Fatalf("err = %v", err)
	}
	if slices.Contains(tui.writes, "x") || tui.open {
		t.Fatalf("writes = %q", tui.writes)
	}
}

func TestStopTaskOnPanelThatNeverOpensWritesNothingElse(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"a", true}}, ignoreOpen: true}
	if err := stopOn(t, tui, "a"); !errors.Is(err, ErrTaskPanelUnavailable) {
		t.Fatalf("err = %v", err)
	}
	if !slices.Equal(tui.writes, []string{"/tasks\r"}) {
		t.Fatalf("writes = %q", tui.writes)
	}
}

func TestStopTaskOnPanelAlreadyOpenIsRefused(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"a", true}, {"b", true}}, openOnArrival: true}
	if err := stopOn(t, tui, "a"); !errors.Is(err, ErrTaskPanelUnavailable) {
		t.Fatalf("err = %v", err)
	}
	if len(tui.writes) != 0 {
		t.Fatalf("writes = %q", tui.writes)
	}
}

func TestLabelMatchesTruncatedRows(t *testing.T) {
	if !taskLabelMatches("run the whole  suite…", "run the whole suite and report") {
		t.Fatal("truncated row did not match")
	}
	if taskLabelMatches("run the whole", "run the whole suite") || taskLabelMatches("", "x") {
		t.Fatal("prefix without an ellipsis matched")
	}
}

func TestStopAgentTaskGuards(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	m.tasksPanelReader = jsonPanelReader{}
	if err := m.StopAgentTask(context.Background(), "s1", "sleeper"); !errors.Is(err, ErrAwaitingDecision) {
		t.Fatalf("blocked err = %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("writes = %q", rt.inputs)
	}
	m, rt = newCommandTestManager(t, domain.ActivityActive)
	m.tasksPanelReader = jsonPanelReader{}
	rt.styledOutput = "❯ draft"
	m.emptyComposerDetector = fakeEmptyComposerDetector{empty: false}
	if err := m.StopAgentTask(context.Background(), "s1", "sleeper"); !errors.Is(err, ErrComposerNotEmpty) {
		t.Fatalf("draft err = %v", err)
	}
	if err := m.StopAgentTask(context.Background(), "missing", "sleeper"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("missing err = %v", err)
	}
	m, _ = newCommandTestManager(t, domain.ActivityActive)
	if err := m.StopAgentTask(context.Background(), "s1", "sleeper"); !errors.Is(err, domain.ErrTaskStopUnsupported) {
		t.Fatalf("no reader err = %v", err)
	}
}
