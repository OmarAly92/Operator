package sessionmanager

import (
	"context"
	"errors"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestCommandStopWritesEscapeWhileActive(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityActive)

	res, err := m.Command(context.Background(), "s1", domain.CommandStop, "")
	if err != nil {
		t.Fatalf("Command: %v", err)
	}
	if !res.Wrote {
		t.Fatal("expected Wrote=true")
	}
	if len(rt.inputs) != 1 || rt.inputs[0] != "\x1b" {
		t.Fatalf("expected exactly one Esc write, got %q", rt.inputs)
	}
}

func TestCommandStopRefusedWhileIdleAndWritesNothing(t *testing.T) {
	m, rt := newCommandTestManager(t, domain.ActivityIdle)

	_, err := m.Command(context.Background(), "s1", domain.CommandStop, "")
	if !errors.Is(err, ErrWrongActivityState) {
		t.Fatalf("expected ErrWrongActivityState, got %v", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("a refused command must write nothing, got %q", rt.inputs)
	}
}

func TestCommandRejectsUnknownVerb(t *testing.T) {
	if _, ok := domain.ParseSessionCommand("rm -rf"); ok {
		t.Fatal("expected an unknown verb to be rejected")
	}
	for _, verb := range []string{"stop", "compact", "model"} {
		if _, ok := domain.ParseSessionCommand(verb); !ok {
			t.Fatalf("expected %q to parse", verb)
		}
	}
}

func newCommandTestManager(t *testing.T, state domain.ActivityState) (*Manager, *fakeRuntime) {
	t.Helper()
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:       "s1",
		Harness:  domain.HarnessClaudeCode,
		Activity: domain.Activity{State: state},
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	return m, rt
}
