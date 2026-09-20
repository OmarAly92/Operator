package session

import (
	"context"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

// TestDelegateTaskSpawnsWorkerDirectly covers the surviving behavior of
// DelegateTask: it spawns the worker directly with a provisional display name
// derived from the brief. There is no orchestrator to title-refine through
// any more, so DelegateTaskOutcome.OrchestratorID always stays empty and no
// background work is scheduled.
func TestDelegateTaskSpawnsWorkerDirectly(t *testing.T) {
	tests := []struct {
		name      string
		agent     domain.AgentHarness
		model     string
		wantAgent domain.AgentHarness
	}{
		{name: "project default"},
		{name: "requested agent model and mode", agent: domain.HarnessCursor, model: "  sonnet-custom  ", wantAgent: domain.HarnessCursor},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			st := newFakeStore()
			st.projects["opr"] = domain.ProjectRecord{ID: "opr"}
			cmd := &fakeCommander{}
			svc := &Service{store: st, manager: cmd}

			brief := "  Fix the renderer\nwithout changing the API.  "
			out, err := svc.DelegateTask(context.Background(), DelegateTaskInput{
				ProjectID: "opr", Brief: brief, RequestedAgent: tt.agent, Model: tt.model,
			})
			if err != nil {
				t.Fatalf("DelegateTask: %v", err)
			}
			if out.WorkerID != "mer-9" || out.OrchestratorID != "" {
				t.Fatalf("out = %#v, want worker mer-9 with no orchestrator", out)
			}
			if !cmd.spawned || cmd.spawnedCfg.ProjectID != "opr" || cmd.spawnedCfg.Harness != tt.wantAgent || cmd.spawnedCfg.Prompt != brief || cmd.spawnedCfg.DisplayName != "Fix the renderer wit" {
				t.Fatalf("spawn cfg = %#v", cmd.spawnedCfg)
			}
			if cmd.spawnedCfg.AgentConfig.Model != strings.TrimSpace(tt.model) {
				t.Fatalf("spawn model = %q, want %q", cmd.spawnedCfg.AgentConfig.Model, strings.TrimSpace(tt.model))
			}
			if cmd.spawnCalls != 1 {
				t.Fatalf("spawn calls = %d, want 1 (no background orchestrator spawn)", cmd.spawnCalls)
			}
			if len(cmd.sent) != 0 || len(cmd.ready) != 0 || len(cmd.resumed) != 0 {
				t.Fatalf("DelegateTask contacted an orchestrator: sent=%#v ready=%#v resumed=%#v", cmd.sent, cmd.ready, cmd.resumed)
			}
		})
	}
}

func TestDelegateTaskStartsPromptlessWorker(t *testing.T) {
	st := newFakeStore()
	st.projects["opr"] = domain.ProjectRecord{ID: "opr"}
	cmd := &fakeCommander{}

	out, err := (&Service{store: st, manager: cmd}).DelegateTask(
		context.Background(),
		DelegateTaskInput{ProjectID: "opr", Brief: " \n\t "},
	)
	if err != nil {
		t.Fatalf("DelegateTask: %v", err)
	}
	if out.WorkerID != "mer-9" || out.OrchestratorID != "" {
		t.Fatalf("out = %#v, want promptless worker mer-9", out)
	}
	if !cmd.spawned || cmd.spawnedCfg.Prompt != "" || cmd.spawnedCfg.DisplayName != "Untitled task" {
		t.Fatalf("spawn cfg = %#v", cmd.spawnedCfg)
	}
}

func TestDelegatedTaskDisplayName(t *testing.T) {
	for _, tt := range []struct {
		name  string
		brief string
		want  string
	}{
		{name: "empty", brief: " \n\t ", want: "Untitled task"},
		{name: "short", brief: "  tell me a joke  ", want: "tell me a joke"},
		{name: "whitespace", brief: "Fix the renderer\nwithout changing the API", want: "Fix the renderer wit"},
		{name: "unicode rune limit", brief: "一二三四五六七八九十一二三四五六七八九十一", want: "一二三四五六七八九十一二三四五六七八九十"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			if got := delegatedTaskDisplayName(tt.brief); got != tt.want {
				t.Fatalf("delegatedTaskDisplayName(%q) = %q, want %q", tt.brief, got, tt.want)
			}
		})
	}
}
