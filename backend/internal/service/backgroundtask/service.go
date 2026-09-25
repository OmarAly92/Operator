package backgroundtask

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
)

var ErrSessionNotFound = domain.ErrTaskSessionNotFound

type EventSource interface {
	TaskUpdates(ctx context.Context, sessionID domain.SessionID) ([]blockeventsvc.Record, error)
}

type SessionLookup interface {
	GetSession(ctx context.Context, id domain.SessionID) (domain.SessionRecord, bool, error)
}

type AgentStopper interface {
	StopAgentTask(ctx context.Context, id domain.SessionID, label string) error
	AgentTaskStopSupported(harness domain.AgentHarness, version string) bool
}

type Deps struct {
	Events      EventSource
	Sessions    SessionLookup
	Runtime     ports.RuntimeProcessReader
	Processes   ports.ProcessInspector
	Signals     ports.ProcessSignaller
	Agents      AgentStopper
	Grace       time.Duration
	ConfirmWait time.Duration
	ConfirmPoll time.Duration
	After       func(d time.Duration, fn func())
}

type Service struct {
	deps Deps
}

type Task struct {
	domain.BackgroundTask
	AgentID    string
	CanStop    bool
	UpdatedSeq int64
}

type StopOutcome struct {
	Task      Task
	Confirmed bool
}

func New(deps Deps) *Service {
	if deps.Grace <= 0 {
		deps.Grace = 3 * time.Second
	}
	if deps.ConfirmWait <= 0 {
		deps.ConfirmWait = 5 * time.Second
	}
	if deps.ConfirmPoll <= 0 {
		deps.ConfirmPoll = 250 * time.Millisecond
	}
	if deps.After == nil {
		deps.After = func(d time.Duration, fn func()) { time.AfterFunc(d, fn) }
	}
	return &Service{deps: deps}
}

func (s *Service) List(ctx context.Context, id domain.SessionID) ([]Task, error) {
	rec, err := s.session(ctx, id)
	if err != nil {
		return nil, err
	}
	return s.fold(ctx, rec)
}

func (s *Service) Stop(ctx context.Context, id domain.SessionID, taskID string) (StopOutcome, error) {
	rec, err := s.session(ctx, id)
	if err != nil {
		return StopOutcome{}, err
	}
	tasks, err := s.fold(ctx, rec)
	if err != nil {
		return StopOutcome{}, err
	}
	task, found := findTask(tasks, taskID)
	if !found {
		return StopOutcome{}, domain.ErrTaskNotFound
	}
	if task.Status.Finished() {
		return StopOutcome{}, domain.ErrTaskFinished
	}
	if !task.CanStop {
		return StopOutcome{}, domain.ErrTaskStopUnsupported
	}
	if task.Kind == domain.BackgroundTaskAgent {
		return s.stopAgent(ctx, rec, task)
	}
	if err := s.stopProcess(ctx, rec, task); err != nil {
		return StopOutcome{}, err
	}
	return StopOutcome{Task: task}, nil
}

func (s *Service) session(ctx context.Context, id domain.SessionID) (domain.SessionRecord, error) {
	rec, found, err := s.deps.Sessions.GetSession(ctx, id)
	if err != nil {
		return domain.SessionRecord{}, fmt.Errorf("background tasks %s: %w", id, err)
	}
	if !found {
		return domain.SessionRecord{}, ErrSessionNotFound
	}
	return rec, nil
}

func (s *Service) fold(ctx context.Context, rec domain.SessionRecord) ([]Task, error) {
	records, err := s.deps.Events.TaskUpdates(ctx, rec.ID)
	if err != nil {
		return nil, fmt.Errorf("background tasks %s: %w", rec.ID, err)
	}
	byID := map[string]*Task{}
	firstSeen := map[string]int64{}
	for _, record := range records {
		var update domain.BackgroundTask
		if err := json.Unmarshal([]byte(record.Detail), &update); err != nil || update.TaskID == "" {
			continue
		}
		existing, known := byID[update.TaskID]
		if !known {
			byID[update.TaskID] = &Task{BackgroundTask: update, AgentID: record.AgentID, UpdatedSeq: record.Seq}
			firstSeen[update.TaskID] = record.Seq
			continue
		}
		existing.BackgroundTask = merge(existing.BackgroundTask, update)
		existing.UpdatedSeq = record.Seq
		if existing.AgentID == "" {
			existing.AgentID = record.AgentID
		}
	}
	runningAgents := map[string]int{}
	for _, task := range byID {
		if task.Kind == domain.BackgroundTaskAgent && task.Status == domain.BackgroundTaskRunning {
			runningAgents[normalizeLabel(task.Description)]++
		}
	}
	out := make([]Task, 0, len(byID))
	for _, task := range byID {
		task.CanStop = s.canStop(rec, task.BackgroundTask, runningAgents)
		out = append(out, *task)
	}
	sort.Slice(out, func(i, j int) bool { return firstSeen[out[i].TaskID] > firstSeen[out[j].TaskID] })
	return out, nil
}

func merge(existing, update domain.BackgroundTask) domain.BackgroundTask {
	merged := update
	keep := func(target *string, previous string) {
		if *target == "" {
			*target = previous
		}
	}
	keep(&merged.ToolUseID, existing.ToolUseID)
	keep(&merged.Description, existing.Description)
	keep(&merged.Command, existing.Command)
	keep(&merged.OutputFile, existing.OutputFile)
	keep(&merged.StartedAt, existing.StartedAt)
	keep(&merged.HarnessVersion, existing.HarnessVersion)
	if merged.Kind == "" {
		merged.Kind = existing.Kind
	}
	return merged
}

func (s *Service) canStop(rec domain.SessionRecord, task domain.BackgroundTask, runningAgents map[string]int) bool {
	if task.Status != domain.BackgroundTaskRunning || rec.IsTerminated || rec.Metadata.RuntimeHandleID == "" {
		return false
	}
	if task.Kind == domain.BackgroundTaskAgent {
		label := normalizeLabel(task.Description)
		return s.deps.Agents != nil &&
			rec.Harness == domain.HarnessClaudeCode &&
			label != "" &&
			runningAgents[label] == 1 &&
			s.deps.Agents.AgentTaskStopSupported(rec.Harness, task.HarnessVersion)
	}
	return s.deps.Runtime != nil && s.deps.Processes != nil && s.deps.Signals != nil
}

func findTask(tasks []Task, id string) (Task, bool) {
	for _, task := range tasks {
		if task.TaskID == id {
			return task, true
		}
	}
	return Task{}, false
}

func (s *Service) stopAgent(ctx context.Context, rec domain.SessionRecord, task Task) (StopOutcome, error) {
	if err := s.deps.Agents.StopAgentTask(ctx, rec.ID, task.Description); err != nil {
		return StopOutcome{}, err
	}
	deadline := time.Now().Add(s.deps.ConfirmWait)
	for {
		tasks, err := s.fold(ctx, rec)
		if err != nil {
			return StopOutcome{}, err
		}
		if latest, found := findTask(tasks, task.TaskID); found && latest.Status.Finished() {
			return StopOutcome{Task: latest, Confirmed: true}, nil
		}
		if !time.Now().Before(deadline) {
			return StopOutcome{Task: task}, domain.ErrTaskStopUnconfirmed
		}
		timer := time.NewTimer(s.deps.ConfirmPoll)
		select {
		case <-ctx.Done():
			timer.Stop()
			return StopOutcome{}, ctx.Err()
		case <-timer.C:
		}
	}
}

func (s *Service) stopProcess(ctx context.Context, rec domain.SessionRecord, task Task) error {
	safe, unsafe, found, err := s.locate(ctx, rec, task)
	if err != nil {
		return err
	}
	switch {
	case !found:
		return s.notFound(ctx, rec, task)
	case unsafe:
		return domain.ErrTaskUnsafe
	case len(safe) > 1:
		return domain.ErrTaskAmbiguous
	case len(safe) == 0:
		return s.notFound(ctx, rec, task)
	}
	pgid := safe[0]
	if err := s.deps.Signals.Terminate(pgid, true); err != nil {
		return fmt.Errorf("background tasks %s: terminate group %d: %w", rec.ID, pgid, err)
	}
	s.deps.After(s.deps.Grace, func() {
		s.escalate(context.WithoutCancel(ctx), rec, task, pgid)
	})
	return nil
}

func (s *Service) escalate(ctx context.Context, rec domain.SessionRecord, task Task, pgid int) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if !s.deps.Signals.Alive(pgid, true) {
		return
	}
	safe, unsafe, found, err := s.locate(ctx, rec, task)
	if err != nil || !found || unsafe || len(safe) != 1 || safe[0] != pgid {
		return
	}
	_ = s.deps.Signals.Kill(pgid, true)
}

func (s *Service) sessionRoot(ctx context.Context, rec domain.SessionRecord) int {
	root, err := s.deps.Runtime.ChildPID(ctx, ports.RuntimeHandle{ID: rec.Metadata.RuntimeHandleID})
	if err != nil {
		return 0
	}
	return root
}

func (s *Service) locate(ctx context.Context, rec domain.SessionRecord, task Task) ([]int, bool, bool, error) {
	root := s.sessionRoot(ctx, rec)
	if root <= 0 {
		return nil, false, false, nil
	}
	procs, err := s.deps.Processes.ListProcesses(ctx)
	if err != nil {
		return nil, false, false, fmt.Errorf("background tasks %s: list processes: %w", rec.ID, err)
	}
	tree := descendants(procs, root)
	var candidates []int
	if file := taskOutputFile(task.BackgroundTask); file != "" {
		writers, err := s.deps.Processes.OpenFileWriters(ctx, file)
		if err != nil {
			return nil, false, false, fmt.Errorf("background tasks %s: find output writers: %w", rec.ID, err)
		}
		candidates = writers
	} else if task.Command != "" {
		candidates = commandMatches(tree, task.Command)
	}
	safe, unsafe := targetGroups(procs, tree, root, candidates)
	return safe, unsafe, true, nil
}

func (s *Service) notFound(ctx context.Context, rec domain.SessionRecord, task Task) error {
	tasks, err := s.fold(ctx, rec)
	if err == nil {
		if latest, found := findTask(tasks, task.TaskID); found && latest.Status.Finished() {
			return domain.ErrTaskFinished
		}
	}
	return domain.ErrTaskProcessNotFound
}

func taskOutputFile(task domain.BackgroundTask) string {
	if task.OutputFile == "" || filepath.Base(task.OutputFile) != task.TaskID+".output" {
		return ""
	}
	return task.OutputFile
}

func descendants(procs []ports.ProcessInfo, root int) map[int]ports.ProcessInfo {
	children := map[int][]ports.ProcessInfo{}
	for _, proc := range procs {
		if proc.PID != proc.PPID {
			children[proc.PPID] = append(children[proc.PPID], proc)
		}
	}
	tree := map[int]ports.ProcessInfo{}
	for _, proc := range procs {
		if proc.PID == root {
			tree[root] = proc
		}
	}
	queue := []int{root}
	for len(queue) > 0 {
		next := queue[0]
		queue = queue[1:]
		for _, child := range children[next] {
			if _, seen := tree[child.PID]; seen {
				continue
			}
			tree[child.PID] = child
			queue = append(queue, child.PID)
		}
	}
	return tree
}

func targetGroups(procs []ports.ProcessInfo, tree map[int]ports.ProcessInfo, root int, pids []int) ([]int, bool) {
	members := map[int][]ports.ProcessInfo{}
	children := map[int][]ports.ProcessInfo{}
	for _, proc := range procs {
		members[proc.PGID] = append(members[proc.PGID], proc)
		children[proc.PPID] = append(children[proc.PPID], proc)
	}
	matched := map[int][]ports.ProcessInfo{}
	for _, pid := range pids {
		if proc, inTree := tree[pid]; inTree && pid != root {
			matched[proc.PGID] = append(matched[proc.PGID], proc)
		}
	}
	unsafe := false
	var groups []int
	for pgid, hits := range matched {
		if groupIsSafe(pgid, members[pgid], children, tree, root, hits) {
			groups = append(groups, pgid)
		} else {
			unsafe = true
		}
	}
	sort.Ints(groups)
	return groups, unsafe
}

func groupIsSafe(pgid int, members []ports.ProcessInfo, children map[int][]ports.ProcessInfo, tree map[int]ports.ProcessInfo, root int, hits []ports.ProcessInfo) bool {
	if pgid <= 1 || len(members) == 0 {
		return false
	}
	inGroup := map[int]bool{}
	for _, member := range members {
		if _, inTree := tree[member.PID]; !inTree || member.PID == root {
			return false
		}
		inGroup[member.PID] = true
	}
	for _, member := range members {
		for _, child := range children[member.PID] {
			if !inGroup[child.PID] {
				return false
			}
		}
	}
	hit := map[int]bool{}
	for _, proc := range hits {
		hit[proc.PID] = true
	}
	for _, match := range hits {
		if hit[match.PPID] {
			continue
		}
		for parent, ok := tree[match.PPID]; ok; parent, ok = tree[parent.PPID] {
			if inGroup[parent.PID] {
				return false
			}
			if parent.PID == root {
				break
			}
		}
	}
	return true
}

func commandMatches(tree map[int]ports.ProcessInfo, command string) []int {
	wrapped := "eval " + shellQuote(command) + " "
	var pids []int
	for pid, proc := range tree {
		if proc.Command == command || strings.Contains(proc.Command, wrapped) {
			pids = append(pids, pid)
		}
	}
	return pids
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func normalizeLabel(label string) string {
	return strings.Join(strings.Fields(label), " ")
}
