//go:build !windows

package httpd

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"sync"
	"syscall"
	"time"

	"github.com/creack/pty"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

// spawnTestPTY runs argv on a real PTY and exposes it as a ports.Stream, so the
// /mux tests exercise the genuine upgrade + wsjson + Serve + creack/pty flow
// without a runtime. It replaces the production ptyexec package, which the
// pty-host cutover left with no caller outside these tests.
func spawnTestPTY(ctx context.Context, argv []string, rows, cols uint16) (ports.Stream, error) {
	if len(argv) == 0 {
		return nil, errors.New("spawnTestPTY: empty command")
	}
	cmd := exec.Command(argv[0], argv[1:]...)
	// Sized from birth: a post-spawn TIOCSWINSZ depends on SIGWINCH delivery
	// that can race the child installing its handler.
	var f *os.File
	var err error
	if rows > 0 && cols > 0 {
		f, err = pty.StartWithSize(cmd, &pty.Winsize{Rows: rows, Cols: cols})
	} else {
		f, err = pty.Start(cmd)
	}
	if err != nil {
		return nil, err
	}
	p := &testPTY{f: f, cmd: cmd}
	go func() {
		<-ctx.Done()
		_ = p.Close()
	}()
	return p, nil
}

type testPTY struct {
	f         *os.File
	cmd       *exec.Cmd
	closeOnce sync.Once
	closeErr  error
}

func (p *testPTY) Read(b []byte) (int, error)  { return p.f.Read(b) }
func (p *testPTY) Write(b []byte) (int, error) { return p.f.Write(b) }

func (p *testPTY) Resize(rows, cols uint16) error {
	return pty.Setsize(p.f, &pty.Winsize{Rows: rows, Cols: cols})
}

// Close stops the child and releases the PTY. SIGTERM first, SIGKILL after a
// grace, so a still-running shell (TestMuxSystemPingPong spawns a bare /bin/sh)
// cannot outlive the test.
//
// It must stay idempotent: both the attachment run loop and attachment.close
// call Close on the same stream, and a second concurrent cmd.Wait on the same
// process blocks forever.
func (p *testPTY) Close() error {
	p.closeOnce.Do(func() {
		done := make(chan struct{})
		go func() {
			_ = p.cmd.Wait()
			close(done)
		}()
		if p.cmd.Process != nil {
			_ = p.cmd.Process.Signal(syscall.SIGTERM)
		}
		select {
		case <-done:
		case <-time.After(250 * time.Millisecond):
			if p.cmd.Process != nil {
				_ = p.cmd.Process.Kill()
			}
			// Bounded: a process wedged in uninterruptible state survives
			// SIGKILL, and blocking here would hang the test binary.
			select {
			case <-done:
			case <-time.After(2 * time.Second):
			}
		}
		p.closeErr = p.f.Close()
	})
	return p.closeErr
}
