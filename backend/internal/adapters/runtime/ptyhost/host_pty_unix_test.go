//go:build !windows

package ptyhost

import (
	"io"
	"strings"
	"testing"
	"time"
)

func TestNewPTYRunsCommandAndReportsExit(t *testing.T) {
	conn, err := newPTY(t.TempDir(), "/bin/sh", []string{"-c", "printf hello; exit 3"})
	if err != nil {
		t.Fatalf("newPTY: %v", err)
	}
	defer func() { _ = conn.Close() }()

	if conn.PID() <= 0 {
		t.Fatalf("PID = %d, want > 0", conn.PID())
	}

	buf := make([]byte, 64)
	n, _ := io.ReadFull(io.LimitReader(conn, 5), buf[:5])
	if got := string(buf[:n]); !strings.Contains(got, "hello") {
		t.Fatalf("read %q, want it to contain \"hello\"", got)
	}

	select {
	case <-conn.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("Done() never closed")
	}
	code, exited := conn.ExitCode()
	if !exited || code != 3 {
		t.Fatalf("ExitCode() = (%d, %v), want (3, true)", code, exited)
	}
}

func TestNewPTYResize(t *testing.T) {
	conn, err := newPTY(t.TempDir(), "/bin/sh", []string{"-c", "sleep 5"})
	if err != nil {
		t.Fatalf("newPTY: %v", err)
	}
	defer func() { _ = conn.Close() }()

	if err := conn.Resize(100, 40); err != nil {
		t.Fatalf("Resize: %v", err)
	}
}
