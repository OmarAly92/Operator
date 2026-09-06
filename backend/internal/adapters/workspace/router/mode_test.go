package router

import (
	"context"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type recordingWorkspace struct {
	ports.Workspace
	destroyed *int
}

func (r recordingWorkspace) Destroy(context.Context, ports.WorkspaceInfo) error {
	if r.destroyed != nil {
		*r.destroyed++
	}
	return nil
}

func TestRouterSendsInPlaceInfoToTheInPlaceAdapter(t *testing.T) {
	git, inPlace := 0, 0
	w := New(Deps{
		Git:     recordingWorkspace{destroyed: &git},
		InPlace: recordingWorkspace{destroyed: &inPlace},
	})
	err := w.Destroy(context.Background(), ports.WorkspaceInfo{
		ProjectID: "p-1", Mode: domain.WorkspaceModeInPlace,
	})
	if err != nil {
		t.Fatal(err)
	}
	if inPlace != 1 || git != 0 {
		t.Fatalf("want the in-place adapter to own teardown, got inPlace=%d git=%d", inPlace, git)
	}
}

func TestRouterSendsWorktreeInfoToTheGitAdapter(t *testing.T) {
	git, inPlace := 0, 0
	w := New(Deps{
		Git:     recordingWorkspace{destroyed: &git},
		InPlace: recordingWorkspace{destroyed: &inPlace},
	})
	err := w.Destroy(context.Background(), ports.WorkspaceInfo{
		ProjectID: "p-1", Mode: domain.WorkspaceModeWorktree,
	})
	if err != nil {
		t.Fatal(err)
	}
	if git != 1 || inPlace != 0 {
		t.Fatalf("want the git adapter, got git=%d inPlace=%d", git, inPlace)
	}
}

func TestRouterErrorsWhenInPlaceIsUnconfigured(t *testing.T) {
	w := New(Deps{Git: plainWorkspace{}})
	if err := w.Destroy(context.Background(), ports.WorkspaceInfo{
		ProjectID: "p-1", Mode: domain.WorkspaceModeInPlace,
	}); err == nil {
		t.Fatal("want an error rather than a silent fall-through to the git adapter")
	}
}
