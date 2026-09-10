package ptyhost

import (
	"io"
	"path/filepath"
	"testing"
)

func TestRunHostRejectsMissingWorkingDirectory(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "missing")
	code := RunHost([]string{"sess-1", missing, "agent.exe"}, io.Discard)
	if code != 1 {
		t.Fatalf("RunHost code = %d, want 1", code)
	}
}

func TestHostArgsRoundTripTheGrid(t *testing.T) {
	args := hostArgs("sess-1", "/tmp/ws", []string{"claude", "--resume"}, 120, 40)
	parsed, err := parseHostArgs(args[1:])
	if err != nil {
		t.Fatalf("parseHostArgs: %v", err)
	}
	want := hostArgv{cols: 120, rows: 40, sessionID: "sess-1", cwd: "/tmp/ws", shellCmd: "claude", shellArgs: []string{"--resume"}}
	if parsed.cols != want.cols || parsed.rows != want.rows || parsed.sessionID != want.sessionID ||
		parsed.cwd != want.cwd || parsed.shellCmd != want.shellCmd || len(parsed.shellArgs) != 1 || parsed.shellArgs[0] != "--resume" {
		t.Fatalf("parsed = %+v, want %+v", parsed, want)
	}
}

func TestHostArgsWithoutAGridKeepTheDefault(t *testing.T) {
	args := hostArgs("sess-1", "/tmp/ws", []string{"claude"}, 0, 0)
	if len(args) != 4 {
		t.Fatalf("args = %q, want no grid flag", args)
	}
	parsed, err := parseHostArgs(args[1:])
	if err != nil {
		t.Fatalf("parseHostArgs: %v", err)
	}
	if parsed.cols != initialCols || parsed.rows != initialRows {
		t.Fatalf("grid = %dx%d, want %dx%d", parsed.cols, parsed.rows, initialCols, initialRows)
	}
}

func TestParseHostArgsRejectsAMalformedGrid(t *testing.T) {
	for _, spec := range []string{"120", "0x24", "80x0", "80x1001", "axb"} {
		if _, err := parseHostArgs([]string{"--grid", spec, "sess-1", "/tmp", "sh"}); err == nil {
			t.Fatalf("--grid %q was accepted", spec)
		}
	}
}
