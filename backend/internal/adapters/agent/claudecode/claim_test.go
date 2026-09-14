package claudecode

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestIsSessionIDClaimedFindsAStaleTranscriptFromADeletedSession(t *testing.T) {
	configDir := t.TempDir()
	t.Setenv(claudeConfigDirEnv, configDir)

	const sessionID = "scratch-16"
	projectDir := filepath.Join(configDir, "projects", "-some-worktree-scratch-16")
	if err := os.MkdirAll(projectDir, 0o750); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	transcript := filepath.Join(projectDir, claudeSessionUUID(sessionID)+".jsonl")
	if err := os.WriteFile(transcript, []byte(`{"type":"user"}`+"\n"), 0o600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	claimed, err := New().IsSessionIDClaimed(context.Background(), domain.SessionID(sessionID))
	if err != nil {
		t.Fatalf("IsSessionIDClaimed: %v", err)
	}
	if !claimed {
		t.Fatalf("session id %q reported free, but Claude holds a transcript at %s; "+
			"a spawn on this number dies with \"Session ID ... is already in use\"", sessionID, transcript)
	}
}

func TestIsSessionIDClaimedReportsFreeWhenNoTranscriptExists(t *testing.T) {
	configDir := t.TempDir()
	t.Setenv(claudeConfigDirEnv, configDir)
	if err := os.MkdirAll(filepath.Join(configDir, "projects"), 0o750); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}

	claimed, err := New().IsSessionIDClaimed(context.Background(), domain.SessionID("scratch-17"))
	if err != nil {
		t.Fatalf("IsSessionIDClaimed: %v", err)
	}
	if claimed {
		t.Fatal("an unused session id must stay allocatable")
	}
}

func TestIsSessionIDClaimedIgnoresAnotherSessionsTranscript(t *testing.T) {
	configDir := t.TempDir()
	t.Setenv(claudeConfigDirEnv, configDir)
	projectDir := filepath.Join(configDir, "projects", "-some-worktree-scratch-16")
	if err := os.MkdirAll(projectDir, 0o750); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	other := filepath.Join(projectDir, claudeSessionUUID("scratch-16")+".jsonl")
	if err := os.WriteFile(other, []byte("{}\n"), 0o600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	claimed, err := New().IsSessionIDClaimed(context.Background(), domain.SessionID("scratch-17"))
	if err != nil {
		t.Fatalf("IsSessionIDClaimed: %v", err)
	}
	if claimed {
		t.Fatal("scratch-17 must not be blocked by scratch-16's transcript")
	}
}

func TestIsSessionIDClaimedInSearchesEveryFolder(t *testing.T) {
	first := t.TempDir()
	second := t.TempDir()
	project := filepath.Join(second, "projects", "-Users-u-repo")
	if err := os.MkdirAll(project, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(project, SessionUUID("proj-7")+".jsonl"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	claimed, err := New().IsSessionIDClaimedIn(context.Background(), "proj-7", []string{first, second})
	if err != nil || !claimed {
		t.Fatalf("claimed = %v err=%v", claimed, err)
	}
	claimed, err = New().IsSessionIDClaimedIn(context.Background(), "proj-8", []string{first, second})
	if err != nil || claimed {
		t.Fatalf("unclaimed id reported claimed=%v err=%v", claimed, err)
	}
}
