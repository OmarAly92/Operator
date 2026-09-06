package domain

import (
	"errors"
	"testing"
)

func TestParseWorkspaceModeAcceptsBothModes(t *testing.T) {
	for _, tc := range []struct {
		in   string
		want WorkspaceMode
	}{
		{"worktree", WorkspaceModeWorktree},
		{"in_place", WorkspaceModeInPlace},
	} {
		got, err := ParseWorkspaceMode(tc.in)
		if err != nil || got != tc.want {
			t.Fatalf("ParseWorkspaceMode(%q) = %q, %v; want %q, nil", tc.in, got, err, tc.want)
		}
	}
}

func TestParseWorkspaceModeRejectsEmpty(t *testing.T) {
	if _, err := ParseWorkspaceMode(""); !errors.Is(err, ErrInvalidWorkspaceMode) {
		t.Fatalf("want ErrInvalidWorkspaceMode for the empty string, got %v", err)
	}
}

func TestParseWorkspaceModeRejectsUnknown(t *testing.T) {
	if _, err := ParseWorkspaceMode("worktre"); !errors.Is(err, ErrInvalidWorkspaceMode) {
		t.Fatalf("want ErrInvalidWorkspaceMode for a typo, got %v", err)
	}
}

func TestWorkspaceModeValid(t *testing.T) {
	if WorkspaceMode("").Valid() {
		t.Fatal("the empty mode must not be valid: there is no default")
	}
	if !WorkspaceModeInPlace.Valid() {
		t.Fatal("in_place must be valid")
	}
}
