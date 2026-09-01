//go:build !windows

// host_pty_unix.go backs the ptyConn seam with a real Unix PTY. It is the
// Darwin/Linux counterpart to host_conpty_windows.go; both are only ever
// constructed inside the detached pty-host process.
package ptyhost

import (
	"os"
	"os/exec"
	"sync"

	"github.com/creack/pty"
)

type unixPTY struct {
	file *os.File
	cmd  *exec.Cmd
	done chan struct{}

	mu       sync.Mutex
	exitCode int
	exited   bool
}

func newPTY(cwd, shellCmd string, shellArgs []string, env map[string]string) (ptyConn, error) {
	cmd := exec.Command(shellCmd, shellArgs...)
	cmd.Dir = cwd
	cmd.Env = processEnvironment(env)
	file, err := pty.Start(cmd)
	if err != nil {
		return nil, err
	}
	conn := &unixPTY{file: file, cmd: cmd, done: make(chan struct{})}
	go conn.wait()
	return conn, nil
}

func (p *unixPTY) wait() {
	err := p.cmd.Wait()
	p.mu.Lock()
	p.exited = true
	if exitErr, ok := err.(*exec.ExitError); ok {
		p.exitCode = exitErr.ExitCode()
	}
	p.mu.Unlock()
	close(p.done)
}

func (p *unixPTY) Read(b []byte) (int, error)  { return p.file.Read(b) }
func (p *unixPTY) Write(b []byte) (int, error) { return p.file.Write(b) }

func (p *unixPTY) Resize(cols, rows int) error {
	return pty.Setsize(p.file, &pty.Winsize{Rows: uint16(rows), Cols: uint16(cols)})
}

func (p *unixPTY) Close() error {
	err := p.file.Close()
	// Best-effort kill: losing the controlling terminal does not reliably
	// terminate the child on every platform/shell (observed: a shell blocked
	// on a concurrent Read of the master fd can outlive the close). Mirrors
	// conptyConn.Close's best-effort kill on Windows.
	if p.cmd.Process != nil {
		_ = p.cmd.Process.Kill()
	}
	return err
}

func (p *unixPTY) Done() <-chan struct{} { return p.done }

func (p *unixPTY) ExitCode() (int, bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.exitCode, p.exited
}

func (p *unixPTY) PID() int {
	if p.cmd.Process == nil {
		return 0
	}
	return p.cmd.Process.Pid
}
