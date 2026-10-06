package claudecode

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

const fixtureTaskDir = "/tmp/claude-501/-work-proj/0f0e0d0c-0000-4000-8000-000000000001/tasks/"

func intPtr(v int) *int       { return &v }
func int64Ptr(v int64) *int64 { return &v }

func mapFixture(t *testing.T, mapper *TranscriptMapper) [][]domain.BlockTranscriptEvent {
	t.Helper()
	file, err := os.Open(filepath.Join("..", "..", "..", "..", "..", "testdata", "transcripts", "claude_code_background_tasks.jsonl"))
	if err != nil {
		t.Fatalf("open fixture: %v", err)
	}
	defer func() { _ = file.Close() }()
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 1<<20), 1<<20)
	var out [][]domain.BlockTranscriptEvent
	for scanner.Scan() {
		events, known := mapper.Map(scanner.Bytes())
		if !known {
			t.Fatalf("line %d not recognised", len(out)+1)
		}
		var tasks []domain.BlockTranscriptEvent
		for _, event := range events {
			if event.Kind == domain.BlockEventTaskUpdate {
				tasks = append(tasks, event)
			}
		}
		out = append(out, tasks)
	}
	if err := scanner.Err(); err != nil {
		t.Fatalf("scan: %v", err)
	}
	return out
}

func taskDetail(t *testing.T, event domain.BlockTranscriptEvent) domain.BackgroundTask {
	t.Helper()
	var task domain.BackgroundTask
	if err := json.Unmarshal([]byte(event.Detail), &task); err != nil {
		t.Fatalf("decode detail %q: %v", event.Detail, err)
	}
	return task
}

func TestTranscriptMapperBackgroundTaskFeed(t *testing.T) {
	perLine := mapFixture(t, NewTranscriptMapper(""))
	want := map[int]domain.BackgroundTask{
		2: {
			TaskID: "buulbcjq7", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskRunning,
			ToolUseID: "toolu_bash1", Description: "Background sleep for 900 seconds", Command: "sleep 900",
			OutputFile: fixtureTaskDir + "buulbcjq7.output", StartedAt: "2026-09-25T00:54:00.000Z", HarnessVersion: "2.1.280",
		},
		4: {
			TaskID: "a152cb13a6e30331f", Kind: domain.BackgroundTaskAgent, Status: domain.BackgroundTaskRunning,
			ToolUseID: "toolu_agent1", Description: "sleeper",
			OutputFile: fixtureTaskDir + "a152cb13a6e30331f.output", StartedAt: "2026-09-25T00:54:02.000Z", HarnessVersion: "2.1.280",
		},
		6: {
			TaskID: "bxjzu4uqc", Kind: domain.BackgroundTaskMonitor, Status: domain.BackgroundTaskRunning,
			ToolUseID: "toolu_mon1", Description: "disk free space", Command: "df -g / | tail -1",
			StartedAt: "2026-09-25T00:54:03.000Z", HarnessVersion: "2.1.280",
		},
		8: {
			TaskID: "bq7x2mdh1", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskRunning,
			ToolUseID: "toolu_bash2", Description: "npm run build", Command: "npm run build",
			OutputFile: fixtureTaskDir + "bq7x2mdh1.output", StartedAt: "2026-09-25T00:54:04.000Z", HarnessVersion: "2.1.280",
		},
		9: {
			TaskID: "a152cb13a6e30331f", Kind: domain.BackgroundTaskAgent, Status: domain.BackgroundTaskCompleted,
			ToolUseID: "toolu_agent1", Description: "sleeper", Summary: `Agent "sleeper" finished`,
			DurationMs: int64Ptr(7412), OutputFile: fixtureTaskDir + "a152cb13a6e30331f.output",
			StartedAt: "2026-09-25T00:54:02.000Z", HarnessVersion: "2.1.280", EndedAt: "2026-09-25T00:56:38.546Z",
		},
		11: {
			TaskID: "buulbcjq7", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskKilled,
			ToolUseID: "toolu_bash1", Description: "Background sleep for 900 seconds", Command: "sleep 900",
			Summary:    `Task "Background sleep for 900 seconds" was stopped by the user`,
			OutputFile: fixtureTaskDir + "buulbcjq7.output", StartedAt: "2026-09-25T00:54:00.000Z", HarnessVersion: "2.1.280",
			EndedAt: "2026-09-25T00:58:45.929Z",
		},
		12: {
			TaskID: "bq7x2mdh1", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskFailed,
			ToolUseID: "toolu_bash2", Description: "npm run build", Command: "npm run build",
			Summary:  `Background command "npm run build && echo "done"" failed with exit code 144`,
			ExitCode: intPtr(144), OutputFile: fixtureTaskDir + "bq7x2mdh1.output",
			StartedAt: "2026-09-25T00:54:04.000Z", HarnessVersion: "2.1.280", EndedAt: "2026-09-25T00:59:00.000Z",
		},
		18: {
			TaskID: "bxjzu4uqc", Kind: domain.BackgroundTaskMonitor, Status: domain.BackgroundTaskCompleted,
			ToolUseID: "toolu_mon1", Description: "disk free space", Command: "df -g / | tail -1",
			Summary:   `Monitor "disk free space" stream ended`,
			StartedAt: "2026-09-25T00:54:03.000Z", HarnessVersion: "2.1.280", EndedAt: "2026-09-25T01:00:00.000Z",
		},
		19: {
			TaskID: "b0325un0b", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskCompleted,
			ToolUseID: "toolu_bash3", Summary: `Background command "Start a harmless background sleep" completed (exit code 0)`,
			ExitCode: intPtr(0), OutputFile: fixtureTaskDir + "b0325un0b.output", EndedAt: "2026-09-25T01:00:01.000Z",
		},
	}
	for index, events := range perLine {
		line := index + 1
		expected, emits := want[line]
		if !emits {
			if len(events) != 0 {
				t.Fatalf("line %d emitted %d task updates, want none: %+v", line, len(events), events)
			}
			continue
		}
		if len(events) != 1 {
			t.Fatalf("line %d emitted %d task updates, want 1", line, len(events))
		}
		event := events[0]
		if event.SourceID != expected.TaskID || event.ToolUseID != expected.ToolUseID || event.Text != expected.Summary {
			t.Fatalf("line %d event = %+v", line, event)
		}
		if got := taskDetail(t, event); !reflect.DeepEqual(got, expected) {
			t.Fatalf("line %d detail\n got %+v\nwant %+v", line, got, expected)
		}
	}
}

func TestTranscriptMapperToolNames(t *testing.T) {
	perLine := mapFixture(t, NewTranscriptMapper(""))
	for line, name := range map[int]string{2: "Bash", 4: "Agent", 6: "Monitor", 19: ""} {
		if got := perLine[line-1][0].ToolName; got != name {
			t.Fatalf("line %d tool name = %q want %q", line, got, name)
		}
	}
}

func TestMapTranscriptRecordEmitsLaunchWithoutState(t *testing.T) {
	line := []byte(`{"type":"user","uuid":"u2","timestamp":"2026-09-25T00:54:01.500Z","message":{"role":"user","content":[{"tool_use_id":"toolu_x","type":"tool_result","content":"Command running in background with ID: bk1. Output is being written to: /tmp/tasks/bk1.output. You will be notified when it completes."}]},"toolUseResult":{"stdout":""}}`)
	events, known := MapTranscriptRecord(line)
	if !known {
		t.Fatal("record not recognised")
	}
	var found *domain.BlockTranscriptEvent
	for i := range events {
		if events[i].Kind == domain.BlockEventTaskUpdate {
			found = &events[i]
		}
	}
	if found == nil {
		t.Fatalf("no task update in %+v", events)
	}
	got := taskDetail(t, *found)
	want := domain.BackgroundTask{
		TaskID: "bk1", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskRunning,
		ToolUseID: "toolu_x", OutputFile: "/tmp/tasks/bk1.output", StartedAt: "2026-09-25T00:54:01.500Z",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("detail = %+v want %+v", got, want)
	}
}

func TestTranscriptMapperKeepsExistingEvents(t *testing.T) {
	mapper := NewTranscriptMapper("")
	line := []byte(`{"type":"user","uuid":"u2","message":{"role":"user","content":[{"tool_use_id":"toolu_x","type":"tool_result","content":"Command running in background with ID: bk1. Output is being written to: /tmp/tasks/bk1.output."}]},"toolUseResult":{"backgroundTaskId":"bk1"}}`)
	events, _ := mapper.Map(line)
	if len(events) != 2 || events[0].Kind != domain.BlockEventToolResult || events[1].Kind != domain.BlockEventTaskUpdate {
		t.Fatalf("events = %+v", events)
	}
}

func TestTranscriptMapperSidechainTasksCarryAgentID(t *testing.T) {
	mapper := NewTranscriptMapper("a1")
	line := []byte(`{"type":"user","isSidechain":true,"uuid":"u2","message":{"role":"user","content":[{"tool_use_id":"toolu_x","type":"tool_result","content":"Command running in background with ID: bk1. Output is being written to: /tmp/tasks/bk1.output."}]},"toolUseResult":{"backgroundTaskId":"bk1"}}`)
	events, _ := mapper.Map(line)
	if len(events) != 2 || events[1].Kind != domain.BlockEventTaskUpdate || events[1].AgentID != "a1" {
		t.Fatalf("events = %+v", events)
	}
}

func TestParseTaskNotificationRejectsMalformed(t *testing.T) {
	for _, content := range []string{
		"",
		"plain prompt",
		"<task-notification><status>completed</status></task-notification>",
		"<task-notification><task-id>b1</task-id><status>paused</status></task-notification>",
		"<task-notification><task-id>b1</task-id><summary>Monitor event</summary><event>x</event></task-notification>",
		"<task-notification><task-id>b1<status>completed</status></task-notification>",
	} {
		if _, ok := parseTaskNotification(content); ok {
			t.Fatalf("parseTaskNotification(%q) accepted", content)
		}
	}
}

func TestExitCodeFromSummary(t *testing.T) {
	for summary, want := range map[string]*int{
		`Background command "x" completed (exit code 0)`:      intPtr(0),
		`Background command "x" failed with exit code 1`:      intPtr(1),
		`Agent "x" finished`:                                  nil,
		`Background command "exit code 9" completed`:          nil,
		`Background command "x" failed with exit code banana`: nil,
	} {
		got := exitCodeFromSummary(summary)
		if (got == nil) != (want == nil) || (got != nil && *got != *want) {
			t.Fatalf("exitCodeFromSummary(%q) = %v want %v", summary, got, want)
		}
	}
}

func TestTranscriptMapperForgetsOldFinishedTasks(t *testing.T) {
	mapper := NewTranscriptMapper("")
	for i := range 3 * maxRememberedFinished {
		id := "b" + strconv.Itoa(i)
		line := `{"type":"queue-operation","operation":"enqueue","timestamp":"2026-09-25T00:00:00.000Z","content":"<task-notification><task-id>` + id + `</task-id><status>completed</status><summary>Background command \"x\" completed (exit code 0)</summary></task-notification>"}`
		if events, _ := mapper.Map([]byte(line)); len(events) != 1 {
			t.Fatalf("notification %d emitted %d events", i, len(events))
		}
	}
	if len(mapper.tasks) > maxRememberedFinished || len(mapper.seen) > maxRememberedFinished || len(mapper.finished) > maxRememberedFinished {
		t.Fatalf("tasks %d seen %d finished %d", len(mapper.tasks), len(mapper.seen), len(mapper.finished))
	}
	running := `{"type":"user","uuid":"u","message":{"content":[{"type":"tool_result","tool_use_id":"t","content":"Command running in background with ID: keep. Output is being written to: /tmp/tasks/keep.output."}]},"toolUseResult":{"backgroundTaskId":"keep"}}`
	mapper.Map([]byte(running))
	for i := range 2 * maxRememberedFinished {
		line := `{"type":"queue-operation","operation":"enqueue","content":"<task-notification><task-id>c` + strconv.Itoa(i) + `</task-id><status>failed</status></task-notification>"}`
		mapper.Map([]byte(line))
	}
	if _, ok := mapper.tasks["keep"]; !ok {
		t.Fatal("a running task was evicted")
	}
}
