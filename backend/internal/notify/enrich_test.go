package notify

import (
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestEnrichReadyToMergePrioritizesPRContext(t *testing.T) {
	t.Parallel()

	rec, err := enrich(Intent{
		Type:               domain.NotificationReadyToMerge,
		SessionID:          "sess-1",
		ProjectID:          "proj-1",
		PRURL:              "https://github.com/acme/app/pull/67",
		SessionDisplayName: "Checkout flow",
		PRNumber:           67,
		PRTitle:            "Fix checkout totals",
		CreatedAt:          time.Date(2026, 8, 5, 4, 0, 0, 0, time.UTC),
	})
	if err != nil {
		t.Fatalf("enrich ready notification: %v", err)
	}

	if want := "Fix checkout totals · PR #67"; rec.Title != want {
		t.Fatalf("title = %q, want %q", rec.Title, want)
	}
	if want := "PR from session Checkout flow is ready to merge. CI passed with no blocking review feedback."; rec.Body != want {
		t.Fatalf("body = %q, want %q", rec.Body, want)
	}
}

func TestEnrichReadyToMergeFallsBackWithoutPRTitle(t *testing.T) {
	t.Parallel()

	rec, err := enrich(Intent{
		Type:      domain.NotificationReadyToMerge,
		SessionID: "sess-1",
		ProjectID: "proj-1",
		PRURL:     "https://github.com/acme/app/pull/67",
		PRNumber:  67,
		CreatedAt: time.Date(2026, 8, 5, 4, 0, 0, 0, time.UTC),
	})
	if err != nil {
		t.Fatalf("enrich ready notification: %v", err)
	}

	if want := "PR #67 is ready to merge"; rec.Title != want {
		t.Fatalf("title = %q, want %q", rec.Title, want)
	}
}

func TestEnrichTurnFinished(t *testing.T) {
	at := time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC)
	long := strings.Repeat("a", 200)
	rec, err := enrich(Intent{Type: domain.NotificationTurnFinished, SessionID: "operator-4", ProjectID: "operator", CreatedAt: at, SessionDisplayName: "split close fix", AssistantUpdate: "  " + long + "  ", Quiet: true})
	if err != nil {
		t.Fatal(err)
	}
	if rec.Title != "split close fix finished" {
		t.Fatalf("title = %q", rec.Title)
	}
	if len([]rune(rec.Body)) != 121 || !strings.HasSuffix(rec.Body, "…") {
		t.Fatalf("body = %q (%d runes)", rec.Body, len([]rune(rec.Body)))
	}
	if !rec.Quiet {
		t.Fatal("quiet was not carried")
	}
}

func TestEnrichTurnFinishedWithoutAssistantText(t *testing.T) {
	rec, err := enrich(Intent{Type: domain.NotificationTurnFinished, SessionID: "s", ProjectID: "p", CreatedAt: time.Now()})
	if err != nil {
		t.Fatal(err)
	}
	if rec.Body != "Your agent finished its turn." {
		t.Fatalf("body = %q", rec.Body)
	}
}

func TestEnrichAgentExited(t *testing.T) {
	rec, err := enrich(Intent{Type: domain.NotificationAgentExited, SessionID: "s", ProjectID: "p", CreatedAt: time.Now(), SessionDisplayName: "checkout"})
	if err != nil {
		t.Fatal(err)
	}
	if rec.Title != "checkout exited" || rec.Body != "The agent process ended. Relaunch it from the session." {
		t.Fatalf("rec = %+v", rec)
	}
}
