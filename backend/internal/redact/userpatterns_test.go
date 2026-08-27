package redact

import (
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writePatterns(t *testing.T, body string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, userPatternsFile), []byte(body), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	return dir
}

func discardLog() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

func restoreDefaults(t *testing.T) {
	t.Helper()
	saved := patterns
	t.Cleanup(func() { patterns = saved })
}

func TestLoadUserPatternsRedactsAHouseTokenShape(t *testing.T) {
	restoreDefaults(t)
	dir := writePatterns(t, "# our internal keys\nACME-[A-Z0-9]{12}\n")

	if n := LoadUserPatterns(dir, discardLog()); n != 1 {
		t.Fatalf("installed = %d, want 1", n)
	}

	got := Text("key ACME-ABCD1234EFGH here")
	if strings.Contains(got.Text, "ACME-ABCD1234EFGH") {
		t.Fatalf("text = %q, want the house token masked", got.Text)
	}
	if len(got.Spans) != 1 {
		t.Errorf("spans = %+v, want one marked removal", got.Spans)
	}
}

func TestLoadUserPatternsKeepsTheDefaults(t *testing.T) {
	restoreDefaults(t)
	dir := writePatterns(t, "ACME-[A-Z0-9]{12}\n")
	LoadUserPatterns(dir, discardLog())

	if got := Text("AKIAIOSFODNN7EXAMPLE"); !strings.Contains(got.Text, mask) {
		t.Fatalf("text = %q, want the built-in AWS pattern still applied", got.Text)
	}
}

func TestLoadUserPatternsSkipsCommentsAndBlanks(t *testing.T) {
	restoreDefaults(t)
	dir := writePatterns(t, "\n# a comment\n\n   \nACME-[A-Z0-9]{12}\n")

	if n := LoadUserPatterns(dir, discardLog()); n != 1 {
		t.Fatalf("installed = %d, want 1", n)
	}
}

func TestLoadUserPatternsSkipsAnInvalidLineWithoutFailing(t *testing.T) {
	restoreDefaults(t)
	dir := writePatterns(t, "ACME-[A-Z0-9]{12}\n(unclosed\n")

	if n := LoadUserPatterns(dir, discardLog()); n != 1 {
		t.Fatalf("installed = %d, want 1 — a bad line is skipped, not fatal", n)
	}
	if got := Text("key ACME-ABCD1234EFGH"); strings.Contains(got.Text, "ACME-ABCD1234EFGH") {
		t.Error("the valid line was not installed alongside the invalid one")
	}
}

func TestLoadUserPatternsWithNoFileIsSilentAndHarmless(t *testing.T) {
	restoreDefaults(t)

	if n := LoadUserPatterns(t.TempDir(), discardLog()); n != 0 {
		t.Fatalf("installed = %d, want 0", n)
	}
	if got := Text("AKIAIOSFODNN7EXAMPLE"); !strings.Contains(got.Text, mask) {
		t.Fatal("the defaults stopped working when there was no user file")
	}
}

func TestLoadUserPatternsIgnoresAnAbsentDataDir(t *testing.T) {
	restoreDefaults(t)

	if n := LoadUserPatterns("", discardLog()); n != 0 {
		t.Fatalf("installed = %d, want 0", n)
	}
}

func TestLoadUserPatternsBoundsTheFile(t *testing.T) {
	restoreDefaults(t)
	line := "ACME-[A-Z0-9]{12}\n"
	dir := writePatterns(t, strings.Repeat(line, maxUserPatterns+50))

	if n := LoadUserPatterns(dir, discardLog()); n != maxUserPatterns {
		t.Fatalf("installed = %d, want the cap of %d", n, maxUserPatterns)
	}
}
