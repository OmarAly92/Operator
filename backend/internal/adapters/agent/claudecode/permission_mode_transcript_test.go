package claudecode

import (
	"slices"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func permissionModeObservations(t *testing.T, m *TranscriptMapper, lines ...string) []domain.PermissionModeObservation {
	t.Helper()
	var got []domain.PermissionModeObservation
	for _, line := range lines {
		events, known := m.Map([]byte(line))
		if !known {
			t.Fatalf("line %s was not recognised", line)
		}
		for _, event := range events {
			if event.Kind != domain.BlockEventPermissionMode {
				continue
			}
			observation, ok := domain.ParsePermissionModeObservation(event.Detail)
			if !ok || string(observation.Mode) != event.Text || event.SourceID != "permission-mode" {
				t.Fatalf("malformed permission_mode event %+v", event)
			}
			got = append(got, observation)
		}
	}
	return got
}

func TestPermissionModeEventsAreEmittedOnChangeOnly(t *testing.T) {
	got := permissionModeObservations(t, NewTranscriptMapper(""),
		`{"type":"permission-mode","permissionMode":"bypassPermissions","sessionId":"s-1"}`,
		`{"type":"user","uuid":"u-1","permissionMode":"bypassPermissions","version":"2.1.280","message":{"role":"user","content":"hi"}}`,
		`{"type":"permission-mode","permissionMode":"bypassPermissions","sessionId":"s-1"}`,
		`{"type":"permission-mode","permissionMode":"plan","sessionId":"s-1"}`,
		`{"type":"permission-mode","permissionMode":"acceptEdits","sessionId":"s-1"}`,
		`{"type":"permission-mode","permissionMode":"dontAsk","sessionId":"s-1"}`,
		`{"type":"user","uuid":"u-2","permissionMode":"acceptEdits","version":"2.1.280","message":{"role":"user","content":"next"}}`,
	)
	want := []domain.PermissionModeObservation{
		{Mode: domain.PermissionModeBypassPermissions},
		{Mode: domain.PermissionModeBypassPermissions, Version: "2.1.280"},
		{Mode: domain.PermissionModePlan, Version: "2.1.280"},
		{Mode: domain.PermissionModeAcceptEdits, Version: "2.1.280"},
	}
	if !slices.Equal(got, want) {
		t.Fatalf("observations = %+v, want %+v", got, want)
	}
}

func TestPermissionModeMapsEveryClaudeValue(t *testing.T) {
	for raw, want := range map[string]domain.PermissionMode{
		"default":           domain.PermissionModeDefault,
		"acceptEdits":       domain.PermissionModeAcceptEdits,
		"plan":              domain.PermissionModePlan,
		"auto":              domain.PermissionModeAuto,
		"bypassPermissions": domain.PermissionModeBypassPermissions,
	} {
		got := permissionModeObservations(t, NewTranscriptMapper(""), `{"type":"permission-mode","permissionMode":"`+raw+`","sessionId":"s-1"}`)
		if len(got) != 1 || got[0].Mode != want {
			t.Fatalf("%s mapped to %+v, want %s", raw, got, want)
		}
	}
}

func TestPermissionModeIsNotReadFromASubagent(t *testing.T) {
	got := permissionModeObservations(t, NewTranscriptMapper("agent-1"),
		`{"type":"user","isSidechain":true,"agentId":"agent-1","uuid":"u-3","permissionMode":"plan","version":"2.1.280","message":{"role":"user","content":"sub"}}`,
	)
	if len(got) != 0 {
		t.Fatalf("a subagent record reported a session mode: %+v", got)
	}
}
