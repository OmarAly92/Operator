package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestSessionLaunchPermissionModeRoundTripsAndSurvivesUpdate(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "board")
	now := time.Now().UTC().Truncate(time.Second)
	rec, err := s.CreateSession(ctx, domain.SessionRecord{
		ProjectID:            "board",
		Harness:              domain.HarnessClaudeCode,
		Activity:             domain.Activity{State: domain.ActivityIdle, LastActivityAt: now},
		Metadata:             domain.SessionMetadata{WorkspaceMode: domain.WorkspaceModeWorktree},
		LaunchPermissionMode: domain.PermissionModeBypassPermissions,
		CreatedAt:            now,
		UpdatedAt:            now,
	})
	if err != nil {
		t.Fatal(err)
	}
	got, _, err := s.GetSession(ctx, rec.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.LaunchPermissionMode != domain.PermissionModeBypassPermissions {
		t.Fatalf("launch mode = %q, want bypass-permissions", got.LaunchPermissionMode)
	}

	got.DisplayName = "renamed"
	got.LaunchPermissionMode = domain.PermissionModeDefault
	if err := s.UpdateSession(ctx, got); err != nil {
		t.Fatal(err)
	}
	if again, _, _ := s.GetSession(ctx, rec.ID); again.LaunchPermissionMode != domain.PermissionModeBypassPermissions {
		t.Fatalf("UpdateSession rewrote the launch mode to %q", again.LaunchPermissionMode)
	}

	ok, err := s.SetSessionLaunchPermissionMode(ctx, rec.ID, domain.PermissionModeAuto, now)
	if err != nil || !ok {
		t.Fatalf("set: %v, %v", ok, err)
	}
	listed, err := s.ListSessions(ctx, "board")
	if err != nil || len(listed) != 1 || listed[0].LaunchPermissionMode != domain.PermissionModeAuto {
		t.Fatalf("list = %+v, %v; want the auto launch mode", listed, err)
	}
	all, err := s.ListAllSessions(ctx)
	if err != nil || len(all) != 1 || all[0].LaunchPermissionMode != domain.PermissionModeAuto {
		t.Fatalf("list all = %+v, %v; want the auto launch mode", all, err)
	}
}
