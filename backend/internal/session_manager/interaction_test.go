package sessionmanager

import (
	"context"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestInteractionsAreListedAfterRegistration(t *testing.T) {
	m, _ := newCommandTestManager(t, domain.ActivityBlocked)
	m.RegisterInteraction("s1", domain.PendingInteraction{
		ID: "i1", Kind: "permission", ToolName: "Bash", ToolInput: `{"command":"ls"}`,
	})

	got, err := m.Interactions(context.Background(), "s1")
	if err != nil {
		t.Fatalf("Interactions: %v", err)
	}
	if len(got) != 1 || got[0].ID != "i1" {
		t.Fatalf("Interactions = %+v", got)
	}
}

func TestATurnBoundaryClearsPendingInteractions(t *testing.T) {
	m, _ := newCommandTestManager(t, domain.ActivityBlocked)
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: "permission"})
	m.ClearInteractions("s1")

	got, _ := m.Interactions(context.Background(), "s1")
	if len(got) != 0 {
		t.Fatalf("expected no interactions after a turn boundary, got %+v", got)
	}
}

func TestRegisteringASecondInteractionReplacesTheFirst(t *testing.T) {
	// Only one dialog is ever on screen. Keeping a stale one would let a client
	// answer a dialog that is no longer there.
	m, _ := newCommandTestManager(t, domain.ActivityBlocked)
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i1", Kind: "permission"})
	m.RegisterInteraction("s1", domain.PendingInteraction{ID: "i2", Kind: "permission"})

	got, _ := m.Interactions(context.Background(), "s1")
	if len(got) != 1 || got[0].ID != "i2" {
		t.Fatalf("expected only the newest interaction, got %+v", got)
	}
}

func TestInteractionLookupMissesAnUnknownID(t *testing.T) {
	m, _ := newCommandTestManager(t, domain.ActivityBlocked)
	if _, ok := m.Interaction("s1", "nope"); ok {
		t.Fatal("expected an unknown interaction id to miss")
	}
}

func TestInteractionsOfAnUnknownSessionIsEmptyNotAnError(t *testing.T) {
	m, _ := newCommandTestManager(t, domain.ActivityIdle)
	got, err := m.Interactions(context.Background(), "unknown")
	if err != nil {
		t.Fatalf("Interactions: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("expected none, got %+v", got)
	}
}
