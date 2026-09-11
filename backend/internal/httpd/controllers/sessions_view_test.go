package controllers

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestSessionViewExposesBriefAndConversationFacts(t *testing.T) {
	s := domain.Session{}
	s.ID = "opr-1"
	s.Metadata.Prompt = "fix the flaky resize test"
	s.Metadata.LatestUserPrompt = "also check the codex path"
	s.Metadata.LatestAssistantUpdate = "I reproduced it and pushed a fix."

	view := sessionView(s)

	if view.Brief != "fix the flaky resize test" {
		t.Fatalf("brief = %q", view.Brief)
	}
	if view.LatestUserPrompt != "also check the codex path" {
		t.Fatalf("latestUserPrompt = %q", view.LatestUserPrompt)
	}
	if view.LatestAssistantUpdate != "I reproduced it and pushed a fix." {
		t.Fatalf("latestAssistantUpdate = %q", view.LatestAssistantUpdate)
	}
}

func TestSessionViewCapsConversationFacts(t *testing.T) {
	s := domain.Session{}
	s.Metadata.LatestAssistantUpdate = strings.Repeat("a", maxWireInteractionLen+500)

	view := sessionView(s)

	if len([]byte(view.LatestAssistantUpdate)) > maxWireInteractionLen {
		t.Fatalf("latestAssistantUpdate not capped: %d bytes", len(view.LatestAssistantUpdate))
	}
	if !strings.HasSuffix(view.LatestAssistantUpdate, "…") {
		t.Fatalf("capped value lost its ellipsis: %q", view.LatestAssistantUpdate[len(view.LatestAssistantUpdate)-8:])
	}
}

func TestSessionViewOmitsEmptyConversationFacts(t *testing.T) {
	body, err := json.Marshal(sessionView(domain.Session{}))
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"brief", "latestUserPrompt", "latestAssistantUpdate"} {
		if strings.Contains(string(body), key) {
			t.Fatalf("empty %s was serialized: %s", key, body)
		}
	}
}
