package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPaneCaptureRejectsBadArgs(t *testing.T) {
	cfg := setConfigEnv(t)
	captureRoot := filepath.Join(cfg.dataDir, "terminal-capture")
	if err := os.MkdirAll(captureRoot, 0o700); err != nil {
		t.Fatal(err)
	}
	inside := filepath.Join(captureRoot, "term-1")
	outside := t.TempDir()
	const validEpoch = "11111111-2222-3333-4444-555555555555"

	cases := []struct {
		name string
		args []string
	}{
		{"missing dir", []string{"pane-capture", "--epoch", validEpoch}},
		{"dir outside capture root", []string{"pane-capture", "--dir", outside, "--epoch", validEpoch}},
		{"malformed epoch", []string{"pane-capture", "--dir", inside, "--epoch", "not-a-uuid"}},
		{"missing epoch", []string{"pane-capture", "--dir", inside}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, _, err := executeCLI(t, Deps{In: strings.NewReader("")}, tc.args...)
			if err == nil {
				t.Fatalf("expected non-nil error for %v", tc.args)
			}
			if ExitCode(err) == 0 {
				t.Fatalf("expected non-zero exit code, got 0 for %v", tc.args)
			}
		})
	}
}

func TestPaneCaptureHappyPathSealsAndManifests(t *testing.T) {
	cfg := setConfigEnv(t)
	captureRoot := filepath.Join(cfg.dataDir, "terminal-capture")
	journalDir := filepath.Join(captureRoot, "term-happy")
	if err := os.MkdirAll(journalDir, 0o700); err != nil {
		t.Fatal(err)
	}
	const epoch = "abcdef01-2345-6789-abcd-ef0123456789"

	payload := strings.Repeat("shell block output line\n", 64)
	_, stderr, err := executeCLI(t, Deps{In: strings.NewReader(payload)}, "pane-capture", "--dir", journalDir, "--epoch", epoch)
	if err != nil {
		t.Fatalf("pane-capture failed: %v (stderr %q)", err, stderr)
	}

	epochDir := filepath.Join(journalDir, epoch)
	if _, err := os.Stat(filepath.Join(epochDir, "manifest.json")); err != nil {
		t.Fatalf("manifest.json not written: %v", err)
	}
	entries, err := os.ReadDir(epochDir)
	if err != nil {
		t.Fatal(err)
	}
	var ready int
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".open") {
			t.Fatalf("unsealed .open segment left behind: %s", e.Name())
		}
		if strings.HasSuffix(e.Name(), ".ready") {
			ready++
			got, _ := os.ReadFile(filepath.Join(epochDir, e.Name()))
			if string(got) != payload {
				t.Fatalf("sealed segment content mismatch")
			}
		}
	}
	if ready != 1 {
		t.Fatalf("want 1 sealed segment, got %d", ready)
	}
}
