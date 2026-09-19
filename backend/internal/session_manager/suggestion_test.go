package sessionmanager

import (
	"context"
	"errors"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestSuggestionReturnsNotFoundForAnUnknownSession(t *testing.T) {
	m, _, _, _ := newManager()

	if _, err := m.Suggestion(context.Background(), "missing"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("Suggestion err = %v, want ErrNotFound", err)
	}
}

func TestSuggestionReturnsEmptyForATerminatedSessionWithoutReadingThePane(t *testing.T) {
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:           "s1",
		Harness:      domain.HarnessClaudeCode,
		IsTerminated: true,
		Metadata:     domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	m.suggestionReader = &claudecode.Plugin{}

	suggestion, err := m.Suggestion(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Suggestion: %v", err)
	}
	if suggestion != "" || rt.styledOutputCalls != 0 {
		t.Fatalf("suggestion = %q, pane reads = %d; want empty and no reads", suggestion, rt.styledOutputCalls)
	}
}

func TestSuggestionReturnsEmptyNotAnErrorWhenTheHarnessHasNoSuggestionReader(t *testing.T) {
	m, st, _, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:       "s1",
		Harness:  domain.HarnessCodex,
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	}

	suggestion, err := m.Suggestion(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Suggestion: %v", err)
	}
	if suggestion != "" {
		t.Fatalf("suggestion = %q, want empty", suggestion)
	}
}

func TestSuggestionReadsClaudeCodesPredictedPrompt(t *testing.T) {
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:       "s1",
		Harness:  domain.HarnessClaudeCode,
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	rt.styledOutput = readPaneFixture(t, "claudecode_suggestion_styled.txt")
	plugin := &claudecode.Plugin{}
	m.suggestionReader = plugin
	m.dialogReader = plugin

	suggestion, err := m.Suggestion(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Suggestion: %v", err)
	}
	if suggestion != "what's new in iOS 27 specifically" {
		t.Fatalf("suggestion = %q", suggestion)
	}
}

func TestSuggestionIsEmptyWhileTheUserHasATypedDraft(t *testing.T) {
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:       "s1",
		Harness:  domain.HarnessClaudeCode,
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	rt.styledOutput = readPaneFixture(t, "claudecode_idle_styled.txt")
	plugin := &claudecode.Plugin{}
	m.suggestionReader = plugin
	m.dialogReader = plugin

	suggestion, err := m.Suggestion(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Suggestion: %v", err)
	}
	if suggestion != "" {
		t.Fatalf("suggestion = %q, want empty while a draft is typed", suggestion)
	}
}

func TestSuggestionIsEmptyWhileADialogIsOnScreen(t *testing.T) {
	m, st, rt, _ := newManager()
	st.sessions["s1"] = domain.SessionRecord{
		ID:       "s1",
		Harness:  domain.HarnessClaudeCode,
		Metadata: domain.SessionMetadata{RuntimeHandleID: "h1"},
	}
	rt.styledOutput = readPaneFixture(t, "claudecode_question_styled.txt")
	plugin := &claudecode.Plugin{}
	m.suggestionReader = plugin
	m.dialogReader = plugin

	suggestion, err := m.Suggestion(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Suggestion: %v", err)
	}
	if suggestion != "" {
		t.Fatalf("suggestion = %q, want empty while a dialog is up", suggestion)
	}
}
