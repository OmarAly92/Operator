package claudecode

import (
	"reflect"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

const panelRule = "────────────────────────────────────────────────────────────────────────"

func pane(lines ...string) string {
	return strings.Join(lines, "\n") + "\n\n"
}

func TestReadTasksPanelListWithGroups(t *testing.T) {
	got, ok := (&Plugin{}).ReadTasksPanel(pane(
		"⏺ ok",
		"✻ Waiting for 1 background agent to finish",
		"❯ /tasks",
		panelRule,
		"  Background",
		"  1 active shell · 1 active agent",
		"    Shells (1)",
		"  ❯ perl -e 'sleep 700' (running)",
		"    Local agents (1)",
		"    blocker two (running) · Haiku 4.5",
		"  ↑/↓ to select · Enter to view · x to stop · Esc to close",
	))
	if !ok {
		t.Fatal("list panel not read")
	}
	want := ports.TasksPanel{
		Rows: []ports.TasksPanelRow{
			{Label: "perl -e 'sleep 700'", Status: "running"},
			{Label: "blocker two", Status: "running"},
		},
		Selected: 0,
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("panel = %+v", got)
	}
}

func TestReadTasksPanelListSelectionAndCompletedGroup(t *testing.T) {
	got, ok := (&Plugin{}).ReadTasksPanel(pane(
		"Background task update waiting while this panel is open",
		panelRule,
		"  Background",
		"  1 active shell",
		"    Shells (1)",
		"    sleep 900 (running)",
		"    Completed (1)",
		"  ❯ sleeper (done) · Haiku 4.5",
		"  ↑/↓ to select · Enter to view · f to foreground · x to stop · Esc to close",
	))
	if !ok || got.Selected != 1 || len(got.Rows) != 2 || got.Rows[1] != (ports.TasksPanelRow{Label: "sleeper", Status: "done"}) {
		t.Fatalf("panel = %+v, %v", got, ok)
	}
}

func TestReadTasksPanelFlatList(t *testing.T) {
	got, ok := (&Plugin{}).ReadTasksPanel(pane(
		panelRule,
		"  Background",
		"  2 active shells",
		"  ❯ sleep 900 (running)",
		"    sleep 900 (running)",
		"  ↑/↓ to select · Enter to view · x to stop · Esc to close",
	))
	if !ok || got.Selected != 0 || len(got.Rows) != 2 || got.Rows[0].Label != "sleep 900" || got.Rows[1].Label != "sleep 900" {
		t.Fatalf("panel = %+v, %v", got, ok)
	}
}

func TestReadTasksPanelAgentDetail(t *testing.T) {
	got, ok := (&Plugin{}).ReadTasksPanel(pane(
		"❯ /tasks",
		panelRule,
		"  general-purpose › blocker",
		"  2m 6s · 21.0k tokens · 1 tool · Haiku 4.5",
		"  Progress",
		"  › Bash(perl -e 'sleep 600')",
		"  Prompt",
		"  Call the Bash tool exactly once with command: perl -e 'sleep 600'.",
		"  ← to go back · Esc/Enter/Space to close · x to stop · f to foreground",
	))
	want := ports.TasksPanel{Detail: true, Selected: -1, DetailLabel: "blocker", DetailStatus: "running"}
	if !ok || !reflect.DeepEqual(got, want) {
		t.Fatalf("panel = %+v, %v", got, ok)
	}
}

func TestReadTasksPanelShellDetail(t *testing.T) {
	got, ok := (&Plugin{}).ReadTasksPanel(pane(
		panelRule,
		"  Shell details",
		"  Status:   running",
		"  Runtime:  15s",
		"  Command:  perl -e 'sleep 700'",
		"  Output:",
		"  No output available",
		"  ← to go back · Esc/Enter/Space to close · x to stop",
	))
	want := ports.TasksPanel{Detail: true, Selected: -1, DetailLabel: "perl -e 'sleep 700'", DetailStatus: "running"}
	if !ok || !reflect.DeepEqual(got, want) {
		t.Fatalf("panel = %+v, %v", got, ok)
	}
}

func TestReadTasksPanelFinishedAgentDetail(t *testing.T) {
	got, ok := (&Plugin{}).ReadTasksPanel(pane(
		panelRule,
		"  general-purpose › sleeper",
		"  ✓ Completed · 7s · 23.2k tokens · Haiku 4.5",
		"  ← to go back · Esc/Enter/Space to close",
	))
	if !ok || got.DetailLabel != "sleeper" || got.DetailStatus != "completed" {
		t.Fatalf("panel = %+v, %v", got, ok)
	}
}

func TestReadTasksPanelClosed(t *testing.T) {
	for name, text := range map[string]string{
		"composer": pane(
			"⏺ Agent \"blocker two\" was stopped by user",
			panelRule,
			"❯ ",
			panelRule,
			"  ⏸ manual mode on · 1 shell · ← 1 agent · ↓ to manage                 43707 tokens",
			"  ⏺ main",
			"  ◯ general-purpose  blocker two                                   28s · ↓ 21.0k tokens",
		),
		"stale detail above the prompt": pane(
			panelRule,
			"  Shell details",
			"  Status:   running",
			panelRule,
			"❯ Command:  perl -e 'sleep 700'",
			panelRule,
			"  ⏸ manual mode on · ? for shortcuts · ← 1 agent                      43707 tokens",
		),
		"permission dialog": pane(
			" Bash command",
			"   perl -e 'sleep 700'",
			" Do you want to proceed?",
			" ❯ 1. Yes",
			"   2. No",
			" Esc to cancel · Tab to amend",
		),
		"empty": "",
	} {
		if got, ok := (&Plugin{}).ReadTasksPanel(text); ok {
			t.Fatalf("%s: read as open panel %+v", name, got)
		}
	}
}

func TestTasksPanelKeys(t *testing.T) {
	keys := (&Plugin{}).TasksPanelKeys()
	want := ports.TasksPanelKeys{Command: "/tasks", Submit: "\r", Clear: "\x15", Up: "\x1b[A", Down: "\x1b[B", View: "\r", Stop: "x", Close: "\x1b"}
	if keys != want {
		t.Fatalf("keys = %+v", keys)
	}
}

func TestTasksPanelVerifiedVersions(t *testing.T) {
	p := &Plugin{}
	if !p.TasksPanelVerified("2.1.280") {
		t.Fatal("2.1.280 must be verified")
	}
	for _, version := range []string{"", "2.1.281", "2.1.28", "unknown"} {
		if p.TasksPanelVerified(version) {
			t.Fatalf("%q must not be verified", version)
		}
	}
}

func TestTasksCommandReady(t *testing.T) {
	p := &Plugin{}
	ready := pane(
		panelRule,
		"❯ /tasks",
		panelRule,
		"  /tasks                                          View and manage everything running in the background",
		"  /superpowers:subagent-driven-development        (superpowers) Use when executing implementation plans",
	)
	if !p.TasksCommandReady(ready) {
		t.Fatal("typed /tasks with its suggestion on top not recognised")
	}
	nbsp := pane(panelRule, "❯\u00a0/tasks", panelRule, "  /tasks     View and manage everything running in the background")
	if !p.TasksCommandReady(nbsp) || !p.TasksCommandTyped(nbsp) {
		t.Fatal("a no-break space after the prompt marker is not recognised")
	}
	long := []string{panelRule, "❯ /tasks", panelRule, "  /tasks     View and manage everything running in the background"}
	for range 60 {
		long = append(long, "  /some:skill        description", "                     continuation")
	}
	if !p.TasksCommandReady(pane(long...)) {
		t.Fatal("a long suggestion list hid the typed command")
	}
	if p.TasksCommandTyped(pane(panelRule, "❯ /tasks/tasks", panelRule)) || p.TasksCommandTyped(pane(panelRule, "❯ ", panelRule)) {
		t.Fatal("typed detection accepted another draft")
	}
	for name, text := range map[string]string{
		"other suggestion first": pane(panelRule, "❯ /tasks", panelRule, "  /tasks-extra   something"),
		"draft differs":          pane(panelRule, "❯ /task", panelRule, "  /tasks   View and manage"),
		"no suggestion list":     pane(panelRule, "❯ /tasks", "  ⏸ manual mode on"),
		"empty composer":         pane(panelRule, "❯ ", panelRule, "  ⏸ manual mode on"),
	} {
		if p.TasksCommandReady(text) {
			t.Fatalf("%s: reported ready", name)
		}
	}
}

func TestReadTasksPanelDetailWithoutAStopHintIsNeverRunning(t *testing.T) {
	for name, text := range map[string]string{
		"agent": pane(
			panelRule,
			"  general-purpose › sleeper",
			"  37s · 20.9k tokens · 1 tool · Haiku 4.5",
			"  ← to go back · Esc/Enter/Space to close · f to foreground",
		),
		"shell without status": pane(
			panelRule,
			"  Shell details",
			"  Command:  sleep 9",
			"  ← to go back · Esc/Enter/Space to close · x to stop",
		),
		"shell running but no stop hint": pane(
			panelRule,
			"  Shell details",
			"  Status:   running",
			"  Command:  sleep 9",
			"  ← to go back · Esc/Enter/Space to close",
		),
	} {
		got, ok := (&Plugin{}).ReadTasksPanel(text)
		if !ok || got.DetailStatus != "unknown" {
			t.Fatalf("%s: panel = %+v, %v", name, got, ok)
		}
	}
}

func TestReadTasksPanelOpenedMidTurnAboveTheComposer(t *testing.T) {
	got, ok := (&Plugin{}).ReadTasksPanel(pane(
		"⏺ Bash(perl -e 'sleep 60')",
		"  ⎿  Running… (35s · timeout 2m)",
		"✻ Befuddling… (39s · ↓ 442 tokens)",
		panelRule,
		"  general-purpose › mid turn agent",
		"  37s · 20.9k tokens · 1 tool · Haiku 4.5",
		"  Progress",
		"  › Bash(perl -e 'sleep 600')",
		"  ← to go back · Esc/Enter/Space to close · x to stop · f to foreground",
		panelRule,
		"❯ ",
		panelRule,
		"  ⏸ manual mode on · esc to interrupt · ← 1 agent · ↓ to manage          46785 tokens",
		"  ⏺ main",
		"  ◯ general-purpose  mid turn agent                                    37s · ↓ 20.9k tokens",
	))
	if !ok || !got.Detail || got.DetailLabel != "mid turn agent" {
		t.Fatalf("panel = %+v, %v", got, ok)
	}
	list, ok := (&Plugin{}).ReadTasksPanel(pane(
		"✻ Befuddling… (39s · ↓ 442 tokens)",
		panelRule,
		"  Background",
		"  1 active shell · 1 active agent",
		"    Shells (1)",
		"  ❯ perl -e 'sleep 700' (running)",
		"    Local agents (1)",
		"    mid turn agent (running) · Haiku 4.5",
		"  ↑/↓ to select · Enter to view · x to stop · Esc to close",
		panelRule,
		"❯ ",
		panelRule,
		"  ⏸ manual mode on · esc to interrupt                                    46785 tokens",
	))
	if !ok || list.Detail || len(list.Rows) != 2 || list.Selected != 0 {
		t.Fatalf("list = %+v, %v", list, ok)
	}
}

func TestReadTasksPanelIgnoresAFooterNotFollowedByARule(t *testing.T) {
	if got, ok := (&Plugin{}).ReadTasksPanel(pane(
		panelRule,
		"  general-purpose › stale",
		"  ← to go back · Esc/Enter/Space to close · x to stop",
		"❯ leftover",
		panelRule,
		"  ⏸ manual mode on",
	)); ok {
		t.Fatalf("stale footer read as open: %+v", got)
	}
}
