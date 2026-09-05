package sessionmanager

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/codex"
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

// TestDraftFailsClosedWhileAClaudeCodeQuestionDialogIsOnScreen and its Codex
// sibling pin the fix for a live-reproduced leak: a dialog's own bordered,
// highlighted rows satisfy the composer-draft reader's structural checks, so
// without the dialog guard the pane's menu text is mirrored into the phone's
// composer as if the user had typed it. Both tests assert the raw reader still
// reports that text, so the guard cannot be quietly deleted as redundant.
func TestDraftFailsClosedWhileAClaudeCodeQuestionDialogIsOnScreen(t *testing.T) {
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:       "s1",
		Harness:  domain.HarnessClaudeCode,
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	pane := readPaneFixture(t, "claudecode_question_styled.txt")
	rt.styledOutput = pane
	plugin := &claudecode.Plugin{}
	m.composerReader = plugin
	m.dialogReader = plugin

	if leaked, ok := plugin.ReadComposerDraft(pane); !ok || leaked == "" {
		t.Fatalf("fixture no longer reproduces the leak: ReadComposerDraft = %q, %v", leaked, ok)
	}

	draft, err := m.Draft(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Draft: %v", err)
	}
	if draft != "" {
		t.Fatalf("draft = %q, want empty — a question dialog's rows are not the user's draft", draft)
	}
}

func TestDraftFailsClosedWhileACodexModelPickerIsOnScreen(t *testing.T) {
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:       "s1",
		Harness:  domain.HarnessCodex,
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	pane := readPaneFixture(t, "codex_model_picker_styled.txt")
	rt.styledOutput = pane
	plugin := &codex.Plugin{}
	m.composerReader = plugin
	m.dialogReader = plugin

	if leaked, ok := plugin.ReadComposerDraft(pane); !ok || leaked == "" {
		t.Fatalf("fixture no longer reproduces the leak: ReadComposerDraft = %q, %v", leaked, ok)
	}

	draft, err := m.Draft(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Draft: %v", err)
	}
	if draft != "" {
		t.Fatalf("draft = %q, want empty — a model picker's rows are not the user's draft", draft)
	}
}

// The guard must not swallow a real draft on an idle pane.
func TestDraftStillReadsARealDraftWhenNoDialogIsOnScreen(t *testing.T) {
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:       "s1",
		Harness:  domain.HarnessClaudeCode,
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	rt.styledOutput = readPaneFixture(t, "claudecode_idle_styled.txt")
	plugin := &claudecode.Plugin{}
	m.composerReader = plugin
	m.dialogReader = plugin

	draft, err := m.Draft(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Draft: %v", err)
	}
	if draft != "run the sample task" {
		t.Fatalf("draft = %q, want the idle pane's real draft", draft)
	}
}

func readPaneFixture(t *testing.T, name string) string {
	t.Helper()
	pane, err := os.ReadFile(filepath.Join("..", "..", "testdata", "panes", name))
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	return string(pane)
}
