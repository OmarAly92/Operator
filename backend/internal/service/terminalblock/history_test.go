package terminalblock_test

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/service/terminalblock"
)

func recordCommand(ctx context.Context, t *testing.T, svc *terminalblock.Service, terminalID, sourceID, command, cwd string, finishedAt time.Time) {
	t.Helper()
	b := sampleBlock(terminalID, sourceID, finishedAt)
	b.Command = command
	b.Cwd = cwd
	if err := svc.Record(ctx, b); err != nil {
		t.Fatalf("record %s/%s: %v", terminalID, sourceID, err)
	}
}

func commandsOf(runs []domain.CommandRun) []string {
	out := make([]string, 0, len(runs))
	for _, run := range runs {
		out = append(out, run.Command)
	}
	return out
}

func TestRecentCommandsSpansTerminalsOldestFirstWithoutRepeats(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)
	base := time.Unix(1000, 0).UTC()
	recordCommand(ctx, t, svc, "term-a", "1", "make build", "/repo/a", base)
	recordCommand(ctx, t, svc, "term-b", "1", "npm test", "/repo/b", base.Add(time.Second))
	recordCommand(ctx, t, svc, "term-a", "2", "make build", "/repo/a", base.Add(2*time.Second))
	recordCommand(ctx, t, svc, "term-c", "1", "git status", "/elsewhere", base.Add(3*time.Second))

	got, err := svc.RecentCommands(ctx, 10)
	if err != nil {
		t.Fatalf("recent: %v", err)
	}
	want := []string{"npm test", "make build", "git status"}
	if fmt.Sprint(commandsOf(got)) != fmt.Sprint(want) {
		t.Fatalf("commands = %q, want %q", commandsOf(got), want)
	}
	if !got[1].FinishedAt.Equal(base.Add(2 * time.Second)) {
		t.Fatalf("make build finished at %v, want its newest run", got[1].FinishedAt)
	}
}

func TestRecentCommandsLeavesOutSecretsHiddenAndBrokenCommands(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)
	base := time.Unix(2000, 0).UTC()
	commands := []string{
		"export GITHUB_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz0123",
		"curl -H 'Authorization: Bearer abcdefghijklmnop1234' https://x",
		"mysql --password=hunter2hunter2",
		" echo hidden by a leading space",
		"   ",
		"printf '\x1b]52;c;aGk=\x07'",
		strings.Repeat("x", 4097),
		"ls -la",
		"for f in a b; do\n  echo $f\ndone",
	}
	for i, command := range commands {
		recordCommand(ctx, t, svc, "term-a", fmt.Sprint(i), command, "/repo", base.Add(time.Duration(i)*time.Second))
	}

	got, err := svc.RecentCommands(ctx, 50)
	if err != nil {
		t.Fatalf("recent: %v", err)
	}
	want := []string{"ls -la", "for f in a b; do\n  echo $f\ndone"}
	if fmt.Sprint(commandsOf(got)) != fmt.Sprint(want) {
		t.Fatalf("commands = %q, want %q", commandsOf(got), want)
	}
}

func TestRecentCommandsKeepsTheNewestWithinTheLimit(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)
	base := time.Unix(3000, 0).UTC()
	for i := 0; i < 5; i++ {
		recordCommand(ctx, t, svc, "term-a", fmt.Sprint(i), fmt.Sprintf("cmd-%d", i), "/repo", base.Add(time.Duration(i)*time.Second))
	}

	got, err := svc.RecentCommands(ctx, 2)
	if err != nil {
		t.Fatalf("recent: %v", err)
	}
	if want := []string{"cmd-3", "cmd-4"}; fmt.Sprint(commandsOf(got)) != fmt.Sprint(want) {
		t.Fatalf("commands = %q, want %q", commandsOf(got), want)
	}
}

func TestRecentCommandsSurvivesAClosedTerminal(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)
	recordCommand(ctx, t, svc, "closed-term", "1", "cargo test", "/repo", time.Unix(4000, 0).UTC())

	got, err := svc.RecentCommands(ctx, 0)
	if err != nil {
		t.Fatalf("recent: %v", err)
	}
	if want := []string{"cargo test"}; fmt.Sprint(commandsOf(got)) != fmt.Sprint(want) {
		t.Fatalf("commands = %q, want %q", commandsOf(got), want)
	}
}
