package router

import (
	"context"
	"errors"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type claimingWorkspace struct {
	ports.Workspace
	claimed bool
	err     error
	asked   *int
}

func (c claimingWorkspace) IsSessionIDClaimed(context.Context, domain.SessionID) (bool, error) {
	if c.asked != nil {
		*c.asked++
	}
	return c.claimed, c.err
}

type plainWorkspace struct{ ports.Workspace }

func TestRouterClaimedWhenScratchClaims(t *testing.T) {
	w := New(Deps{Git: plainWorkspace{}, Scratch: claimingWorkspace{claimed: true}})
	claimed, err := w.IsSessionIDClaimed(context.Background(), "scratch-5")
	if err != nil || !claimed {
		t.Fatalf("want claimed, got %v %v", claimed, err)
	}
}

func TestRouterFreeWhenNoAdapterClaims(t *testing.T) {
	w := New(Deps{Git: claimingWorkspace{}, Scratch: claimingWorkspace{}})
	claimed, err := w.IsSessionIDClaimed(context.Background(), "scratch-5")
	if err != nil || claimed {
		t.Fatalf("want free, got %v %v", claimed, err)
	}
}

func TestRouterSkipsAdaptersWithoutTheCapability(t *testing.T) {
	w := New(Deps{Git: plainWorkspace{}, Scratch: plainWorkspace{}})
	claimed, err := w.IsSessionIDClaimed(context.Background(), "scratch-5")
	if err != nil || claimed {
		t.Fatalf("want free, got %v %v", claimed, err)
	}
}

func TestRouterToleratesNilAdapters(t *testing.T) {
	w := New(Deps{})
	if _, err := w.IsSessionIDClaimed(context.Background(), "scratch-5"); err != nil {
		t.Fatalf("want no error from a router with no adapters, got %v", err)
	}
}

func TestRouterPropagatesProbeError(t *testing.T) {
	boom := errors.New("probe exploded")
	w := New(Deps{Git: claimingWorkspace{err: boom}, Scratch: claimingWorkspace{claimed: true}})
	if _, err := w.IsSessionIDClaimed(context.Background(), "scratch-5"); !errors.Is(err, boom) {
		t.Fatalf("want the probe error surfaced, got %v", err)
	}
}

func TestRouterStopsAtTheFirstClaim(t *testing.T) {
	asked := 0
	w := New(Deps{Git: claimingWorkspace{claimed: true}, Scratch: claimingWorkspace{asked: &asked}})
	if _, err := w.IsSessionIDClaimed(context.Background(), "scratch-5"); err != nil {
		t.Fatal(err)
	}
	if asked != 0 {
		t.Fatalf("want the scratch adapter left unasked once git claimed, asked %d times", asked)
	}
}
