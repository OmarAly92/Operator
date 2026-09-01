package cli

import (
	"bytes"
	"io"
	"net"
	"strings"
	"testing"
	"time"
)

func TestAttachCommandRejectsUnknownSession(t *testing.T) {
	cmd := newAttachCommand()
	cmd.SetArgs([]string{"no-such-session"})
	err := cmd.Execute()
	if err == nil || !strings.Contains(err.Error(), "no-such-session") {
		t.Fatalf("Execute() error = %v, want it to name the missing session", err)
	}
}

func TestAttachPipeDetachesOnCtrlC(t *testing.T) {
	local, remote := net.Pipe()
	t.Cleanup(func() { _ = remote.Close() })
	go func() {
		buf := make([]byte, 4096)
		for {
			if _, err := remote.Read(buf); err != nil {
				return
			}
		}
	}()

	in := strings.NewReader("hello\x03world")
	var out bytes.Buffer

	errCh := make(chan error, 1)
	go func() { errCh <- attachPipe(local, in, &out) }()

	select {
	case err := <-errCh:
		if err != nil {
			t.Fatalf("attachPipe() error = %v, want nil on Ctrl-C detach", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("attachPipe() did not return after Ctrl-C; deadlocked")
	}
}

func TestAttachPipeReturnsWhenRemoteCloses(t *testing.T) {
	local, remote := net.Pipe()

	blockedIn, neverWritten := io.Pipe()
	t.Cleanup(func() { _ = neverWritten.Close() })

	var out bytes.Buffer
	errCh := make(chan error, 1)
	go func() { errCh <- attachPipe(local, blockedIn, &out) }()

	_ = remote.Close()

	select {
	case <-errCh:
	case <-time.After(2 * time.Second):
		t.Fatal("attachPipe() did not return after the remote closed; deadlocked")
	}
}
