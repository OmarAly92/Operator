package sessionmanager

import (
	"context"
	"errors"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type fakeComposerReader struct {
	draft string
	ok    bool
}

func (f fakeComposerReader) ReadComposerDraft(string) (string, bool) {
	return f.draft, f.ok
}

func TestDraftReturnsNotFoundForAnUnknownSession(t *testing.T) {
	m, _, _, _ := newManager()

	if _, err := m.Draft(context.Background(), "missing"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("Draft err = %v, want ErrNotFound", err)
	}
}

func TestDraftReturnsEmptyForATerminatedSessionWithoutReadingTheReader(t *testing.T) {
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:           "s1",
		Harness:      domain.HarnessClaudeCode,
		IsTerminated: true,
		Metadata:     domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	m.composerReader = fakeComposerReader{draft: "would leak if read", ok: true}

	draft, err := m.Draft(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Draft: %v", err)
	}
	if draft != "" {
		t.Fatalf("draft = %q, want empty for a terminated session", draft)
	}
	if rt.styledOutputCalls != 0 {
		t.Fatalf("a terminated session must not read the pane, got %d reads", rt.styledOutputCalls)
	}
}

func TestDraftReturnsEmptyNotAnErrorWhenTheHarnessHasNoComposerReader(t *testing.T) {
	m, st, _, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:       "s1",
		Harness:  domain.HarnessClaudeCode,
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	// m.composerReader is left nil and fakeAgent (returned by fakeAgents.Agent)
	// does not implement ports.TerminalComposerReader, so composerReaderFor must
	// fail closed to "no reader" rather than composerReaderFor panicking or Draft
	// surfacing an error.

	draft, err := m.Draft(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Draft: %v, want no error when the harness has no composer reader", err)
	}
	if draft != "" {
		t.Fatalf("draft = %q, want empty", draft)
	}
}

func TestDraftReadsAStyledPaneThroughTheComposerReader(t *testing.T) {
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:       "s1",
		Harness:  domain.HarnessClaudeCode,
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	rt.styledOutput = "STYLED PANE"
	m.composerReader = fakeComposerReader{draft: "run the sample task", ok: true}

	draft, err := m.Draft(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Draft: %v", err)
	}
	if draft != "run the sample task" {
		t.Fatalf("draft = %q", draft)
	}
}

func TestDraftFailsClosedWhenTheReaderReportsNoDraft(t *testing.T) {
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:       "s1",
		Harness:  domain.HarnessClaudeCode,
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	rt.styledOutput = "STYLED PANE"
	m.composerReader = fakeComposerReader{ok: false}

	draft, err := m.Draft(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Draft: %v", err)
	}
	if draft != "" {
		t.Fatalf("draft = %q, want empty", draft)
	}
}
