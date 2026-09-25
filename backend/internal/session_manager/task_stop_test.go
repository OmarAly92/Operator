package sessionmanager

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strings"
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
	tasks          []panelTask
	draft          string
	draftUnknown   bool
	open           bool
	detail         bool
	detailLabel    string
	selected       int
	noSuggestion   bool
	ignoreSubmit   bool
	keepOpenOnStop bool
	openOnArrival  bool
	closeAtRead    int
	shiftOnView    bool
	reads          int
	writes         []string
}

type fakeTUIPane struct {
	Composer string
	Ready    bool
	Panel    *ports.TasksPanel
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
	f.reads++
	if f.openOnArrival {
		f.openOnArrival = false
		f.open = true
	}
	if f.closeAtRead > 0 && f.reads == f.closeAtRead {
		f.open = false
	}
	pane := fakeTUIPane{Composer: f.draft, Ready: f.draft == "/tasks" && !f.noSuggestion}
	if f.open {
		panel := ports.TasksPanel{Detail: f.detail, Selected: -1}
		if f.detail {
			panel.DetailLabel = f.detailLabel
			panel.DetailStatus = "unknown"
			for _, task := range f.tasks {
				if task.label == f.detailLabel && task.running {
					panel.DetailStatus = "running"
				}
			}
		} else {
			for _, task := range f.visible() {
				panel.Rows = append(panel.Rows, ports.TasksPanelRow{Label: task.label, Status: "running"})
			}
			panel.Selected = f.selected
		}
		pane.Panel = &panel
	}
	encoded, _ := json.Marshal(pane)
	return string(encoded), nil
}

func (f *fakeTasksTUI) Draft(context.Context) (string, bool, error) {
	if f.draftUnknown {
		return "", false, nil
	}
	return f.draft, true, nil
}

func (f *fakeTasksTUI) Write(_ context.Context, keys string) error {
	f.writes = append(f.writes, keys)
	switch keys {
	case "/tasks":
		if !f.open {
			f.draft += keys
		}
	case "\x15":
		if !f.open {
			f.draft = ""
		}
	case "\r":
		switch {
		case !f.open:
			if f.ignoreSubmit {
				return nil
			}
			if f.draft != "/tasks" {
				return nil
			}
			f.draft = ""
			f.open = true
			f.selected = 0
			if visible := f.visible(); len(visible) == 1 {
				f.detail = true
				f.detailLabel = visible[0].label
			}
		case f.open && !f.detail:
			visible := f.visible()
			index := f.selected
			if f.shiftOnView && index+1 < len(visible) {
				index++
			}
			f.detail = true
			f.detailLabel = visible[index].label
		default:
			f.open = false
		}
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
			f.draft += "x"
			return nil
		}
		if !f.detail {
			return nil
		}
		for i := range f.tasks {
			if f.tasks[i].label == f.detailLabel && f.tasks[i].running {
				f.tasks[i].running = false
				break
			}
		}
		if !f.keepOpenOnStop {
			f.open = false
			f.detail = false
		}
	case "\x1b":
		if !f.open {
			return nil
		}
		f.open = false
		f.detail = false
	}
	return nil
}

type fakePanelReader struct{ verified string }

func (fakePanelReader) ReadTasksPanel(pane string) (ports.TasksPanel, bool) {
	var decoded fakeTUIPane
	if err := json.Unmarshal([]byte(pane), &decoded); err != nil || decoded.Panel == nil {
		return ports.TasksPanel{}, false
	}
	return *decoded.Panel, true
}

func (fakePanelReader) TasksCommandReady(pane string) bool {
	var decoded fakeTUIPane
	return json.Unmarshal([]byte(pane), &decoded) == nil && decoded.Ready
}

func (fakePanelReader) TasksPanelKeys() ports.TasksPanelKeys {
	return ports.TasksPanelKeys{Command: "/tasks", Submit: "\r", Clear: "\x15", Up: "\x1b[A", Down: "\x1b[B", View: "\r", Stop: "x", Close: "\x1b"}
}

func (f fakePanelReader) TasksPanelVerified(version string) bool {
	return version != "" && version == f.verified
}

func stopOn(t *testing.T, tui *fakeTasksTUI, label string) error {
	t.Helper()
	return stopTaskOnPanel(context.Background(), tui, fakePanelReader{}, label, panelTiming{appear: 5 * time.Millisecond, poll: time.Millisecond})
}

func assertWrites(t *testing.T, tui *fakeTasksTUI, want ...string) {
	t.Helper()
	if !slices.Equal(tui.writes, want) {
		t.Fatalf("writes = %q want %q", tui.writes, want)
	}
}

func TestStopTaskOnPanelViewsTheRowThenStopsInTheDetail(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"sleep 900", true}, {"sleeper", true}, {"reviewer", true}}}
	if err := stopOn(t, tui, "reviewer"); err != nil {
		t.Fatalf("stop: %v", err)
	}
	assertWrites(t, tui, "/tasks", "\r", "\x1b[B", "\x1b[B", "\r", "x")
	if tui.tasks[2].running || !tui.tasks[1].running || !tui.tasks[0].running || tui.open {
		t.Fatalf("tui = %+v", tui)
	}
}

func TestStopTaskOnPanelClosesADetailThatStayedOpen(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"sleeper", true}}, keepOpenOnStop: true}
	if err := stopOn(t, tui, "sleeper"); err != nil {
		t.Fatalf("stop: %v", err)
	}
	assertWrites(t, tui, "/tasks", "\r", "x", "\x1b")
}

func TestStopTaskOnPanelSingleTaskOpensStraightIntoDetail(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"sleeper", true}}}
	if err := stopOn(t, tui, "sleeper"); err != nil {
		t.Fatalf("stop: %v", err)
	}
	assertWrites(t, tui, "/tasks", "\r", "x")
}

func TestStopTaskOnPanelDetailForAnotherTaskBacksOut(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"sleep 900", true}}}
	if err := stopOn(t, tui, "sleeper"); !errors.Is(err, domain.ErrTaskNotFound) {
		t.Fatalf("err = %v", err)
	}
	assertWrites(t, tui, "/tasks", "\r", "\x1b")
	if !tui.tasks[0].running {
		t.Fatal("wrong task stopped")
	}
}

func TestStopTaskOnPanelNeverStopsWhenViewLandsOnAnotherTask(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"a", true}, {"b", true}, {"c", true}}, shiftOnView: true}
	if err := stopOn(t, tui, "b"); !errors.Is(err, domain.ErrTaskNotFound) {
		t.Fatalf("err = %v", err)
	}
	if slices.Contains(tui.writes, "x") {
		t.Fatalf("pressed stop on the wrong detail: %q", tui.writes)
	}
	if !tui.tasks[1].running || !tui.tasks[2].running || tui.open {
		t.Fatalf("tui = %+v", tui)
	}
}

func TestStopTaskOnPanelNeverStopsWhenThePanelClosesBeforeTheStop(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"sleeper", true}}, closeAtRead: 5}
	if err := stopOn(t, tui, "sleeper"); !errors.Is(err, domain.ErrTaskPanelUnavailable) {
		t.Fatalf("err = %v", err)
	}
	assertWrites(t, tui, "/tasks", "\r")
	if tui.draft != "" || !tui.tasks[0].running {
		t.Fatalf("tui = %+v", tui)
	}
}

func TestStopTaskOnPanelNeverEscapesAPanelThatClosedItself(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"a", true}, {"b", true}}, closeAtRead: 6}
	if err := stopOn(t, tui, "c"); !errors.Is(err, domain.ErrTaskNotFound) {
		t.Fatalf("err = %v", err)
	}
	if slices.Contains(tui.writes, "\x1b") || slices.Contains(tui.writes, "x") {
		t.Fatalf("writes = %q", tui.writes)
	}
}

func TestStopTaskOnPanelRefusesAmbiguousRows(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"sleeper", true}, {"sleeper", true}}}
	if err := stopOn(t, tui, "sleeper"); !errors.Is(err, domain.ErrTaskAmbiguous) {
		t.Fatalf("err = %v", err)
	}
	assertWrites(t, tui, "/tasks", "\r", "\x1b")
}

func TestStopTaskOnPanelMissingRow(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"a", true}, {"b", true}}}
	if err := stopOn(t, tui, "c"); !errors.Is(err, domain.ErrTaskNotFound) {
		t.Fatalf("err = %v", err)
	}
	assertWrites(t, tui, "/tasks", "\r", "\x1b")
}

func TestStopTaskOnPanelClearsTheCommandWhenThePanelNeverOpens(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"a", true}}, ignoreSubmit: true}
	if err := stopOn(t, tui, "a"); !errors.Is(err, domain.ErrTaskPanelUnavailable) {
		t.Fatalf("err = %v", err)
	}
	assertWrites(t, tui, "/tasks", "\r", "\x15")
	if tui.draft != "" {
		t.Fatalf("left %q in the composer", tui.draft)
	}
}

func TestStopTaskOnPanelNeverSubmitsAnUnrecognisedCommand(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"a", true}}, noSuggestion: true}
	if err := stopOn(t, tui, "a"); !errors.Is(err, domain.ErrTaskPanelUnavailable) {
		t.Fatalf("err = %v", err)
	}
	assertWrites(t, tui, "/tasks", "\x15")
	if tui.draft != "" {
		t.Fatalf("left %q in the composer", tui.draft)
	}
}

func TestStopTaskOnPanelRefusesADraftOrAnUnreadableComposer(t *testing.T) {
	drafted := &fakeTasksTUI{tasks: []panelTask{{"a", true}}, draft: "half a thought"}
	if err := stopOn(t, drafted, "a"); !errors.Is(err, ErrComposerNotEmpty) {
		t.Fatalf("draft err = %v", err)
	}
	assertWrites(t, drafted)
	unknown := &fakeTasksTUI{tasks: []panelTask{{"a", true}}, draftUnknown: true}
	if err := stopOn(t, unknown, "a"); !errors.Is(err, domain.ErrTaskPanelUnavailable) {
		t.Fatalf("unknown err = %v", err)
	}
	assertWrites(t, unknown)
}

func TestStopTaskOnPanelAlreadyOpenIsRefused(t *testing.T) {
	tui := &fakeTasksTUI{tasks: []panelTask{{"a", true}, {"b", true}}, openOnArrival: true}
	if err := stopOn(t, tui, "a"); !errors.Is(err, domain.ErrTaskPanelUnavailable) {
		t.Fatalf("err = %v", err)
	}
	assertWrites(t, tui)
}

func TestLabelMatchesTruncatedRows(t *testing.T) {
	if !taskLabelMatches("run the whole  suite…", "run the whole suite and report") {
		t.Fatal("truncated row did not match")
	}
	if taskLabelMatches("run the whole", "run the whole suite") || taskLabelMatches("", "x") {
		t.Fatal("prefix without an ellipsis matched")
	}
}

func TestStopAgentTaskMapsGuardsToDomainErrors(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityBlocked)
	m.tasksPanelReader = fakePanelReader{}
	if err := m.StopAgentTask(context.Background(), "s1", "sleeper"); !errors.Is(err, domain.ErrTaskAwaitingDecision) {
		t.Fatalf("blocked err = %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("writes = %q", rt.inputs)
	}
	if err := m.StopAgentTask(context.Background(), "missing", "sleeper"); !errors.Is(err, domain.ErrTaskSessionNotFound) {
		t.Fatalf("missing err = %v", err)
	}
	m, _ = newCommandTestManager(t, domain.ActivityActive)
	if err := m.StopAgentTask(context.Background(), "s1", "sleeper"); !errors.Is(err, domain.ErrTaskStopUnsupported) {
		t.Fatalf("no reader err = %v", err)
	}
	m, _ = newCommandTestManager(t, domain.ActivityExited)
	m.tasksPanelReader = fakePanelReader{}
	if err := m.StopAgentTask(context.Background(), "s1", "sleeper"); !errors.Is(err, domain.ErrTaskSessionNotRunning) {
		t.Fatalf("exited err = %v", err)
	}
}

func TestAgentTaskStopSupportedNeedsAVerifiedVersion(t *testing.T) {
	m, _ := newCommandTestManager(t, domain.ActivityIdle)
	if m.AgentTaskStopSupported(domain.HarnessClaudeCode, "2.1.280") {
		t.Fatal("supported without a panel reader")
	}
	m.tasksPanelReader = fakePanelReader{verified: "2.1.280"}
	m.composerReader = fakeComposerReader{ok: true}
	if !m.AgentTaskStopSupported(domain.HarnessClaudeCode, "2.1.280") {
		t.Fatal("verified version refused")
	}
	if m.AgentTaskStopSupported(domain.HarnessClaudeCode, "") || m.AgentTaskStopSupported(domain.HarnessClaudeCode, "9.9.9") {
		t.Fatal("unverified version accepted")
	}
}

func TestPaneDriveSerialisesAModelSwitch(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)
	rt.panes = []string{"MENU:0", "MENU:0", "MENU:1"}
	m.menuReader = fakeMenuReader{rows: []string{"sonnet", "opus"}}
	end, err := m.beginPaneDrive(context.Background(), "s1")
	if err != nil {
		t.Fatalf("beginPaneDrive: %v", err)
	}
	done := make(chan error, 1)
	go func() {
		_, err := m.Command(context.Background(), "s1", domain.CommandModel, "opus")
		done <- err
	}()
	select {
	case err := <-done:
		t.Fatalf("model switch ran during a pane drive: %v", err)
	case <-time.After(100 * time.Millisecond):
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("model switch wrote during a pane drive: %q", rt.inputs)
	}
	end()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("model switch after the drive: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("model switch never ran after the drive ended")
	}
	if len(rt.inputs) == 0 || rt.inputs[0] != "/model\r" {
		t.Fatalf("inputs = %q", rt.inputs)
	}
}

func TestPaneDriveHoldsOffOtherInput(t *testing.T) {
	m, _ := newCommandTestManager(t, domain.ActivityIdle)
	end, err := m.beginPaneDrive(context.Background(), "s1")
	if err != nil {
		t.Fatalf("beginPaneDrive: %v", err)
	}
	admitted := make(chan time.Time, 1)
	go func() {
		release, ok := m.AcquireSessionInput("s1")
		if ok {
			release()
		}
		admitted <- time.Now()
	}()
	time.Sleep(100 * time.Millisecond)
	if len(admitted) != 0 {
		t.Fatal("desktop input admitted during a pane drive")
	}
	ended := time.Now()
	end()
	select {
	case got := <-admitted:
		if got.Before(ended) {
			t.Fatal("input admitted before the drive ended")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("input never admitted after the drive")
	}
}

func TestPaneDriveHoldsOffAnExclusiveOperation(t *testing.T) {
	m, _ := newCommandTestManager(t, domain.ActivityIdle)
	end, err := m.beginPaneDrive(context.Background(), "s1")
	if err != nil {
		t.Fatalf("beginPaneDrive: %v", err)
	}
	operation := make(chan error, 1)
	go func() {
		operation <- m.beginAgentOperation(context.Background(), "s1", agentOperationKill)
	}()
	select {
	case err := <-operation:
		t.Fatalf("exclusive operation began during a pane drive: %v", err)
	case <-time.After(100 * time.Millisecond):
	}
	end()
	select {
	case err := <-operation:
		if err != nil {
			t.Fatalf("operation after the drive: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("operation never began after the drive")
	}
	m.endAgentOperation("s1", agentOperationKill)
}

func TestPaneDriveRefusesWhileAnExclusiveOperationRuns(t *testing.T) {
	m, _ := newCommandTestManager(t, domain.ActivityIdle)
	if err := m.beginAgentOperation(context.Background(), "s1", agentOperationSwitch); err != nil {
		t.Fatal(err)
	}
	if _, err := m.beginPaneDrive(context.Background(), "s1"); !errors.Is(err, errAgentOperationInProgress) {
		t.Fatalf("err = %v", err)
	}
	if err := m.StopAgentTask(context.Background(), "s1", "x"); !errors.Is(err, domain.ErrTaskSessionBusy) {
		t.Fatalf("stop err = %v", err)
	}
	if !strings.Contains(domain.ErrTaskSessionBusy.Error(), "operation") {
		t.Fatal("busy error lost its meaning")
	}
}

func TestPaneDrivesArePruned(t *testing.T) {
	m, _ := newCommandTestManager(t, domain.ActivityIdle)
	for range 3 {
		end, err := m.beginPaneDrive(context.Background(), "s1")
		if err != nil {
			t.Fatal(err)
		}
		end()
	}
	m.agentOpMu.Lock()
	defer m.agentOpMu.Unlock()
	if len(m.paneDrives) != 0 || m.inputLeases["s1"] != 0 {
		t.Fatalf("drives %v leases %v", m.paneDrives, m.inputLeases)
	}
}
