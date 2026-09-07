//go:build !windows

package ptyhost

import (
	"strings"
	"testing"
	"time"
)

func readAll(t *testing.T, conn ptyConn) string {
	t.Helper()
	done := make(chan string, 1)
	go func() {
		var builder strings.Builder
		buf := make([]byte, 512)
		for {
			n, err := conn.Read(buf)
			builder.Write(buf[:n])
			if err != nil {
				break
			}
		}
		done <- builder.String()
	}()
	select {
	case out := <-done:
		return out
	case <-time.After(10 * time.Second):
		t.Fatal("timed out reading from the pty")
		return ""
	}
}

func TestRealPTYChildSeesTerminalIdentity(t *testing.T) {
	conn, err := newPTY(t.TempDir(), "/bin/sh",
		[]string{"-c", `printf "[%s|%s|%s]" "$TERM" "$COLORTERM" "$TERM_PROGRAM"`}, nil)
	if err != nil {
		t.Fatalf("newPTY: %v", err)
	}
	defer func() { _ = conn.Close() }()

	got := readAll(t, conn)
	if want := "[xterm-256color|truecolor|Operator]"; !strings.Contains(got, want) {
		t.Fatalf("child environment %q, want it to contain %q", got, want)
	}
}

func TestRealPTYChildOverrideBeatsTheDefault(t *testing.T) {
	conn, err := newPTY(t.TempDir(), "/bin/sh",
		[]string{"-c", `printf "[%s]" "$COLORTERM"`}, map[string]string{"COLORTERM": "24bit"})
	if err != nil {
		t.Fatalf("newPTY: %v", err)
	}
	defer func() { _ = conn.Close() }()

	got := readAll(t, conn)
	if !strings.Contains(got, "[24bit]") {
		t.Fatalf("child COLORTERM %q, want it to contain \"[24bit]\"", got)
	}
}
