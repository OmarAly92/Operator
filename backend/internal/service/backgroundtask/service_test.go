package backgroundtask

import (
	"context"
	"encoding/json"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
)

type fakeEvents struct {
	mu      sync.Mutex
	records []blockeventsvc.Record
	onRead  func()
}

func (f *fakeEvents) TaskUpdates(context.Context, domain.SessionID) ([]blockeventsvc.Record, error) {
	f.mu.Lock()
	hook := f.onRead
	f.mu.Unlock()
	if hook != nil {
		hook()
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]blockeventsvc.Record(nil), f.records...), nil
}

func (f *fakeEvents) add(t *testing.T, task domain.BackgroundTask) {
	t.Helper()
	encoded, err := json.Marshal(task)
	if err != nil {
		t.Fatal(err)
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	f.records = append(f.records, blockeventsvc.Record{
		Seq:      int64(len(f.records) + 1),
		Kind:     domain.BlockEventTaskUpdate,
		SourceID: task.TaskID,
		Detail:   string(encoded),
	})
}

type fakeSessions struct {
	rec   domain.SessionRecord
	found bool
}

func (f *fakeSessions) GetSession(context.Context, domain.SessionID) (domain.SessionRecord, bool, error) {
	return f.rec, f.found, nil
}

type fakeRuntime struct{ pid int }

func (f *fakeRuntime) ChildPID(context.Context, ports.RuntimeHandle) (int, error) {
	return f.pid, nil
}

type fakeProcs struct {
	procs   []ports.ProcessInfo
	holders map[string][]int
}

func (f *fakeProcs) ListProcesses(context.Context) ([]ports.ProcessInfo, error) {
	return f.procs, nil
}

func (f *fakeProcs) OpenFileWriters(_ context.Context, path string) ([]int, error) {
	return f.holders[path], nil
}

type signal struct {
	pid   int
	group bool
	kill  bool
}

type fakeSignaller struct {
	sent       []signal
	alive      map[int]bool
	aliveQuery []signal
}

func (f *fakeSignaller) Terminate(pid int, group bool) error {
	f.sent = append(f.sent, signal{pid: pid, group: group})
	return nil
}

func (f *fakeSignaller) Kill(pid int, group bool) error {
	f.sent = append(f.sent, signal{pid: pid, group: group, kill: true})
	return nil
}

func (f *fakeSignaller) Alive(pid int, group bool) bool {
	f.aliveQuery = append(f.aliveQuery, signal{pid: pid, group: group})
	return group && f.alive[pid]
}

type fakeAgents struct {
	labels   []string
	err      error
	after    func()
	verified string
}

func (f *fakeAgents) AgentTaskStopSupported(harness domain.AgentHarness, version string) bool {
	return harness == domain.HarnessClaudeCode && version != "" && version == f.verified
}

func (f *fakeAgents) StopAgentTask(_ context.Context, _ domain.SessionID, label string) error {
	f.labels = append(f.labels, label)
	if f.after != nil {
		f.after()
	}
	return f.err
}

const outputFile = "/tmp/claude-501/-proj/sess/tasks/b1.output"

func claudeTree() []ports.ProcessInfo {
	return []ports.ProcessInfo{
		{PID: 1, PPID: 0, PGID: 1, Command: "launchd"},
		{PID: 100, PPID: 1, PGID: 100, Command: "opr pty-host"},
		{PID: 200, PPID: 100, PGID: 200, Command: "claude"},
		{PID: 300, PPID: 200, PGID: 300, Command: "/bin/zsh -c source snap.sh && eval 'sleep 900' < /dev/null && pwd -P >| /tmp/claude-4e2a-cwd"},
		{PID: 301, PPID: 300, PGID: 300, Command: "sleep 900"},
		{PID: 400, PPID: 200, PGID: 400, Command: "/bin/zsh -c source snap.sh && eval 'npm run dev' < /dev/null && pwd -P >| /tmp/claude-1111-cwd"},
		{PID: 900, PPID: 1, PGID: 900, Command: "/bin/zsh -c source snap.sh && eval 'sleep 900' < /dev/null"},
	}
}

type harness struct {
	svc      *Service
	events   *fakeEvents
	sessions *fakeSessions
	procs    *fakeProcs
	signals  *fakeSignaller
	agents   *fakeAgents
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	h := &harness{
		events: &fakeEvents{},
		sessions: &fakeSessions{found: true, rec: domain.SessionRecord{
			ID:       "s-1",
			Harness:  domain.HarnessClaudeCode,
			Metadata: domain.SessionMetadata{RuntimeHandleID: "h-1"},
		}},
		procs:   &fakeProcs{procs: claudeTree(), holders: map[string][]int{outputFile: {300, 301}}},
		signals: &fakeSignaller{alive: map[int]bool{}},
		agents:  &fakeAgents{verified: "2.1.280"},
	}
	h.svc = New(Deps{
		Events:      h.events,
		Sessions:    h.sessions,
		Runtime:     &fakeRuntime{pid: 100},
		Processes:   h.procs,
		Signals:     h.signals,
		Agents:      h.agents,
		Grace:       time.Millisecond,
		ConfirmWait: 50 * time.Millisecond,
		ConfirmPoll: time.Millisecond,
		After:       func(_ time.Duration, fn func()) { fn() },
	})
	return h
}

func runningShell() domain.BackgroundTask {
	return domain.BackgroundTask{
		TaskID: "b1", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskRunning,
		ToolUseID: "toolu_1", Description: "Nap", Command: "sleep 900", OutputFile: outputFile,
		StartedAt: "2026-09-25T00:00:00.000Z",
	}
}

func TestListFoldsLatestStatusAndKeepsLaunchFields(t *testing.T) {
	h := newHarness(t)
	h.events.add(t, runningShell())
	h.events.add(t, domain.BackgroundTask{TaskID: "a1", Kind: domain.BackgroundTaskAgent, Status: domain.BackgroundTaskRunning, Description: "sleeper", HarnessVersion: "2.1.280", StartedAt: "2026-09-25T00:00:01.000Z"})
	code := 143
	h.events.add(t, domain.BackgroundTask{TaskID: "b1", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskFailed, Summary: "failed with exit code 143", ExitCode: &code, EndedAt: "2026-09-25T00:01:00.000Z"})
	h.events.records = append(h.events.records, blockeventsvc.Record{Seq: 99, Kind: domain.BlockEventTaskUpdate, Detail: "{broken"})

	tasks, err := h.svc.List(context.Background(), "s-1")
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(tasks) != 2 {
		t.Fatalf("tasks = %+v", tasks)
	}
	agent, shell := tasks[0], tasks[1]
	if agent.TaskID != "a1" || !agent.CanStop {
		t.Fatalf("agent = %+v", agent)
	}
	if shell.TaskID != "b1" || shell.Status != domain.BackgroundTaskFailed || shell.CanStop {
		t.Fatalf("shell = %+v", shell)
	}
	if shell.Command != "sleep 900" || shell.Description != "Nap" || shell.OutputFile != outputFile || shell.StartedAt == "" {
		t.Fatalf("launch fields lost: %+v", shell)
	}
	if shell.ExitCode == nil || *shell.ExitCode != 143 || shell.EndedAt == "" || shell.Summary == "" {
		t.Fatalf("completion fields lost: %+v", shell)
	}
	if shell.UpdatedSeq != 3 {
		t.Fatalf("updated seq = %d", shell.UpdatedSeq)
	}
}

func TestListMarksNothingStoppableOnATerminatedSession(t *testing.T) {
	h := newHarness(t)
	h.sessions.rec.IsTerminated = true
	h.events.add(t, runningShell())
	tasks, err := h.svc.List(context.Background(), "s-1")
	if err != nil || len(tasks) != 1 || tasks[0].CanStop {
		t.Fatalf("tasks = %+v, %v", tasks, err)
	}
}

func TestListUnknownSession(t *testing.T) {
	h := newHarness(t)
	h.sessions.found = false
	if _, err := h.svc.List(context.Background(), "s-1"); !errors.Is(err, ErrSessionNotFound) {
		t.Fatalf("err = %v", err)
	}
}

func TestStopShellSignalsTheTaskProcessGroup(t *testing.T) {
	h := newHarness(t)
	h.events.add(t, runningShell())
	h.signals.alive[300] = true

	outcome, err := h.svc.Stop(context.Background(), "s-1", "b1")
	if err != nil {
		t.Fatalf("Stop: %v", err)
	}
	if outcome.Confirmed || outcome.Task.TaskID != "b1" {
		t.Fatalf("outcome = %+v", outcome)
	}
	want := []signal{{pid: 300, group: true}, {pid: 300, group: true, kill: true}}
	if len(h.signals.sent) != 2 || h.signals.sent[0] != want[0] || h.signals.sent[1] != want[1] {
		t.Fatalf("signals = %+v", h.signals.sent)
	}
}

func TestStopShellSkipsTheKillWhenTheGroupExited(t *testing.T) {
	h := newHarness(t)
	h.events.add(t, runningShell())
	if _, err := h.svc.Stop(context.Background(), "s-1", "b1"); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	if len(h.signals.sent) != 1 || h.signals.sent[0].kill {
		t.Fatalf("signals = %+v", h.signals.sent)
	}
}

func TestStopShellRefusesWhenTheAgentAlsoWritesTheOutput(t *testing.T) {
	h := newHarness(t)
	h.events.add(t, runningShell())
	h.procs.holders[outputFile] = []int{200, 300, 301}
	if _, err := h.svc.Stop(context.Background(), "s-1", "b1"); !errors.Is(err, domain.ErrTaskUnsafe) {
		t.Fatalf("err = %v", err)
	}
	if len(h.signals.sent) != 0 {
		t.Fatalf("signalled %+v", h.signals.sent)
	}
}

func TestStopShellFallsBackToTheExactCommand(t *testing.T) {
	h := newHarness(t)
	task := runningShell()
	task.OutputFile = ""
	h.events.add(t, task)
	if _, err := h.svc.Stop(context.Background(), "s-1", "b1"); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	if len(h.signals.sent) == 0 || h.signals.sent[0].pid != 300 {
		t.Fatalf("signals = %+v", h.signals.sent)
	}
}

func TestStopShellIgnoresAnOutputFileNotNamedForTheTask(t *testing.T) {
	h := newHarness(t)
	task := runningShell()
	task.OutputFile = "/etc/passwd"
	task.Command = "npm run dev"
	h.procs.holders["/etc/passwd"] = []int{300}
	h.events.add(t, task)
	if _, err := h.svc.Stop(context.Background(), "s-1", "b1"); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	if len(h.signals.sent) == 0 || h.signals.sent[0].pid != 400 {
		t.Fatalf("signals = %+v", h.signals.sent)
	}
}

func TestStopShellRefusesAnAmbiguousCommand(t *testing.T) {
	h := newHarness(t)
	task := runningShell()
	task.OutputFile = ""
	h.events.add(t, task)
	h.procs.procs = append(h.procs.procs, ports.ProcessInfo{PID: 500, PPID: 200, PGID: 500, Command: "/bin/zsh -c eval 'sleep 900' < /dev/null"})
	if _, err := h.svc.Stop(context.Background(), "s-1", "b1"); !errors.Is(err, domain.ErrTaskAmbiguous) {
		t.Fatalf("err = %v", err)
	}
	if len(h.signals.sent) != 0 {
		t.Fatalf("signalled %+v", h.signals.sent)
	}
}

func TestStopShellProcessNotFound(t *testing.T) {
	h := newHarness(t)
	task := runningShell()
	task.Command = "sleep 1234"
	h.procs.holders = map[string][]int{}
	h.events.add(t, task)
	if _, err := h.svc.Stop(context.Background(), "s-1", "b1"); !errors.Is(err, domain.ErrTaskProcessNotFound) {
		t.Fatalf("err = %v", err)
	}
}

func TestStopShellOutsideTheSessionTreeIsNotFound(t *testing.T) {
	h := newHarness(t)
	task := runningShell()
	h.procs.holders[outputFile] = []int{900}
	task.Command = "sleep 1234"
	h.events.add(t, task)
	if _, err := h.svc.Stop(context.Background(), "s-1", "b1"); !errors.Is(err, domain.ErrTaskProcessNotFound) {
		t.Fatalf("err = %v", err)
	}
}

func TestStopUnknownAndFinishedTasks(t *testing.T) {
	h := newHarness(t)
	if _, err := h.svc.Stop(context.Background(), "s-1", "nope"); !errors.Is(err, domain.ErrTaskNotFound) {
		t.Fatalf("unknown err = %v", err)
	}
	h.events.add(t, runningShell())
	h.events.add(t, domain.BackgroundTask{TaskID: "b1", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskCompleted})
	if _, err := h.svc.Stop(context.Background(), "s-1", "b1"); !errors.Is(err, domain.ErrTaskFinished) {
		t.Fatalf("finished err = %v", err)
	}
}

func TestStopOnATerminatedSessionIsUnsupported(t *testing.T) {
	h := newHarness(t)
	h.sessions.rec.IsTerminated = true
	h.events.add(t, runningShell())
	if _, err := h.svc.Stop(context.Background(), "s-1", "b1"); !errors.Is(err, domain.ErrTaskStopUnsupported) {
		t.Fatalf("err = %v", err)
	}
}

func TestStopAgentDrivesTheTUIAndWaitsForTheNotification(t *testing.T) {
	h := newHarness(t)
	h.events.add(t, domain.BackgroundTask{TaskID: "a1", Kind: domain.BackgroundTaskAgent, Status: domain.BackgroundTaskRunning, Description: "sleeper", HarnessVersion: "2.1.280"})
	h.agents.after = func() {
		h.events.add(t, domain.BackgroundTask{TaskID: "a1", Kind: domain.BackgroundTaskAgent, Status: domain.BackgroundTaskKilled, Summary: `Agent "sleeper" was stopped by user`})
	}
	outcome, err := h.svc.Stop(context.Background(), "s-1", "a1")
	if err != nil {
		t.Fatalf("Stop: %v", err)
	}
	if !outcome.Confirmed || outcome.Task.Status != domain.BackgroundTaskKilled || outcome.Task.Description != "sleeper" {
		t.Fatalf("outcome = %+v", outcome)
	}
	if len(h.agents.labels) != 1 || h.agents.labels[0] != "sleeper" {
		t.Fatalf("labels = %+v", h.agents.labels)
	}
}

func TestStopAgentUnconfirmed(t *testing.T) {
	h := newHarness(t)
	h.events.add(t, domain.BackgroundTask{TaskID: "a1", Kind: domain.BackgroundTaskAgent, Status: domain.BackgroundTaskRunning, Description: "sleeper", HarnessVersion: "2.1.280"})
	if _, err := h.svc.Stop(context.Background(), "s-1", "a1"); !errors.Is(err, domain.ErrTaskStopUnconfirmed) {
		t.Fatalf("err = %v", err)
	}
}

func TestStopAgentPassesTheDriverErrorThrough(t *testing.T) {
	h := newHarness(t)
	h.events.add(t, domain.BackgroundTask{TaskID: "a1", Kind: domain.BackgroundTaskAgent, Status: domain.BackgroundTaskRunning, Description: "sleeper", HarnessVersion: "2.1.280"})
	h.agents.err = domain.ErrTaskAmbiguous
	if _, err := h.svc.Stop(context.Background(), "s-1", "a1"); !errors.Is(err, domain.ErrTaskAmbiguous) {
		t.Fatalf("err = %v", err)
	}
}

func TestStopAgentWithoutADescriptionOrStopperIsUnsupported(t *testing.T) {
	h := newHarness(t)
	h.events.add(t, domain.BackgroundTask{TaskID: "a1", Kind: domain.BackgroundTaskAgent, Status: domain.BackgroundTaskRunning})
	if _, err := h.svc.Stop(context.Background(), "s-1", "a1"); !errors.Is(err, domain.ErrTaskStopUnsupported) {
		t.Fatalf("err = %v", err)
	}
	h.svc.deps.Agents = nil
	h.events.add(t, domain.BackgroundTask{TaskID: "a2", Kind: domain.BackgroundTaskAgent, Status: domain.BackgroundTaskRunning, Description: "x", HarnessVersion: "2.1.280"})
	tasks, _ := h.svc.List(context.Background(), "s-1")
	for _, task := range tasks {
		if task.CanStop {
			t.Fatalf("agent stoppable without a stopper: %+v", task)
		}
	}
	if _, err := h.svc.Stop(context.Background(), "s-1", "a2"); !errors.Is(err, domain.ErrTaskStopUnsupported) {
		t.Fatalf("err = %v", err)
	}
}

func TestListMergesASubagentShellWithItsMainScopeNotification(t *testing.T) {
	h := newHarness(t)
	h.events.add(t, domain.BackgroundTask{TaskID: "bsub", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskRunning, Description: "Sleep for 15 minutes", Command: "sleep 900"})
	h.events.records[0].AgentID = "a9"
	h.events.add(t, domain.BackgroundTask{TaskID: "bsub", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskStopped, Summary: `Task "Sleep for 15 minutes" was stopped by main session`})
	tasks, err := h.svc.List(context.Background(), "s-1")
	if err != nil || len(tasks) != 1 {
		t.Fatalf("tasks = %+v, %v", tasks, err)
	}
	got := tasks[0]
	if got.AgentID != "a9" || got.Status != domain.BackgroundTaskStopped || got.Command != "sleep 900" || got.Description != "Sleep for 15 minutes" {
		t.Fatalf("task = %+v", got)
	}
}

func TestStopShellEscalationAsksAboutTheGroupNotTheLeader(t *testing.T) {
	h := newHarness(t)
	h.events.add(t, runningShell())
	if _, err := h.svc.Stop(context.Background(), "s-1", "b1"); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	if len(h.signals.aliveQuery) != 1 || h.signals.aliveQuery[0] != (signal{pid: 300, group: true}) {
		t.Fatalf("liveness queries = %+v", h.signals.aliveQuery)
	}
}

func TestStopShellWithAKnownOutputFileNeverFallsBackToTheCommand(t *testing.T) {
	h := newHarness(t)
	h.procs.holders = map[string][]int{}
	h.events.add(t, runningShell())
	if _, err := h.svc.Stop(context.Background(), "s-1", "b1"); !errors.Is(err, domain.ErrTaskProcessNotFound) {
		t.Fatalf("err = %v", err)
	}
	if len(h.signals.sent) != 0 {
		t.Fatalf("signalled %+v", h.signals.sent)
	}
}

func TestStopShellThatFinishedMeanwhileReportsFinished(t *testing.T) {
	h := newHarness(t)
	h.procs.holders = map[string][]int{}
	h.events.add(t, runningShell())
	reads := 0
	h.events.onRead = func() {
		reads++
		if reads == 2 {
			h.events.add(t, domain.BackgroundTask{TaskID: "b1", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskCompleted})
		}
	}
	if _, err := h.svc.Stop(context.Background(), "s-1", "b1"); !errors.Is(err, domain.ErrTaskFinished) {
		t.Fatalf("err = %v", err)
	}
}

func TestStopShellRefusesUnsafeGroups(t *testing.T) {
	for name, procs := range map[string][]ports.ProcessInfo{
		"shares the session root's group": {
			{PID: 100, PPID: 1, PGID: 100, Command: "claude"},
			{PID: 300, PPID: 100, PGID: 100, Command: "/bin/zsh -c eval 'sleep 900'"},
			{PID: 301, PPID: 300, PGID: 100, Command: "sleep 900"},
		},
		"shares the agent's group": {
			{PID: 100, PPID: 1, PGID: 100, Command: "opr agent-process supervise"},
			{PID: 200, PPID: 100, PGID: 200, Command: "claude"},
			{PID: 300, PPID: 200, PGID: 200, Command: "/bin/zsh -c eval 'sleep 900'"},
			{PID: 301, PPID: 300, PGID: 200, Command: "sleep 900"},
		},
		"has a member outside the session": {
			{PID: 100, PPID: 1, PGID: 100, Command: "claude"},
			{PID: 300, PPID: 100, PGID: 300, Command: "/bin/zsh -c eval 'sleep 900'"},
			{PID: 301, PPID: 300, PGID: 300, Command: "sleep 900"},
			{PID: 950, PPID: 1, PGID: 300, Command: "stranger"},
		},
		"has a child in another group": {
			{PID: 100, PPID: 1, PGID: 100, Command: "claude"},
			{PID: 300, PPID: 100, PGID: 300, Command: "/bin/zsh -c eval 'sleep 900'"},
			{PID: 301, PPID: 300, PGID: 301, Command: "setsid worker"},
		},
	} {
		t.Run(name, func(t *testing.T) {
			h := newHarness(t)
			h.procs.procs = procs
			h.procs.holders = map[string][]int{outputFile: {300, 301}}
			h.events.add(t, runningShell())
			if _, err := h.svc.Stop(context.Background(), "s-1", "b1"); !errors.Is(err, domain.ErrTaskUnsafe) {
				t.Fatalf("err = %v", err)
			}
			if len(h.signals.sent) != 0 {
				t.Fatalf("signalled %+v", h.signals.sent)
			}
		})
	}
}

func TestAgentCanStopGates(t *testing.T) {
	agent := func(id, description, version string) domain.BackgroundTask {
		return domain.BackgroundTask{TaskID: id, Kind: domain.BackgroundTaskAgent, Status: domain.BackgroundTaskRunning, Description: description, HarnessVersion: version}
	}
	stoppable := func(t *testing.T, h *harness, id string) bool {
		t.Helper()
		tasks, err := h.svc.List(context.Background(), "s-1")
		if err != nil {
			t.Fatal(err)
		}
		for _, task := range tasks {
			if task.TaskID == id {
				return task.CanStop
			}
		}
		t.Fatalf("task %s missing", id)
		return false
	}

	h := newHarness(t)
	h.events.add(t, agent("a1", "sleeper", "2.1.280"))
	if !stoppable(t, h, "a1") {
		t.Fatal("verified claude-code agent with a unique description must be stoppable")
	}

	h = newHarness(t)
	h.events.add(t, agent("a1", "sleeper", ""))
	if stoppable(t, h, "a1") {
		t.Fatal("unknown version must not be stoppable")
	}

	h = newHarness(t)
	h.events.add(t, agent("a1", "sleeper", "2.1.999"))
	if stoppable(t, h, "a1") {
		t.Fatal("unverified version must not be stoppable")
	}

	h = newHarness(t)
	h.sessions.rec.Harness = "codex"
	h.events.add(t, agent("a1", "sleeper", "2.1.280"))
	if stoppable(t, h, "a1") {
		t.Fatal("non claude-code harness must not be stoppable")
	}

	h = newHarness(t)
	h.events.add(t, agent("a1", "sleeper", "2.1.280"))
	h.events.add(t, agent("a2", "sleeper ", "2.1.280"))
	if stoppable(t, h, "a1") || stoppable(t, h, "a2") {
		t.Fatal("duplicate running descriptions must not be stoppable")
	}
	if _, err := h.svc.Stop(context.Background(), "s-1", "a1"); !errors.Is(err, domain.ErrTaskStopUnsupported) {
		t.Fatalf("stop err = %v", err)
	}
	if len(h.agents.labels) != 0 {
		t.Fatalf("drove the panel for an ambiguous agent: %v", h.agents.labels)
	}

	h = newHarness(t)
	h.events.add(t, agent("a1", "sleeper", "2.1.280"))
	h.events.add(t, agent("a2", "sleeper", "2.1.280"))
	h.events.add(t, domain.BackgroundTask{TaskID: "a2", Kind: domain.BackgroundTaskAgent, Status: domain.BackgroundTaskCompleted})
	if !stoppable(t, h, "a1") {
		t.Fatal("a finished namesake must not block the running agent")
	}
}
