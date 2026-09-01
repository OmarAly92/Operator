// host_main.go is the RunHost entrypoint for the "opr pty-host" subcommand.
// It is cross-platform: the loopback TCP bind and signal wiring work on all
// OSes; only the ConPTY creation (newConPTY) is OS-gated via build tags.
package ptyhost

import (
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
)

// RunHost is the "opr pty-host" entrypoint. argv is everything after the
// subcommand name: <sessionId> <cwd> <shellCmd> [shellArg...]
//
// It binds 127.0.0.1:0 (OS assigns the port), creates the ConPTY, prints
// "READY:<pid> <port>\n" to stdout (the parent process reads this to learn the
// port), installs SIGTERM/SIGINT handlers, then runs Serve. Returns a process
// exit code.
//
// ponytail: loopback bind only; any local process on this host can connect to
// the assigned port. A per-session random token handshake is the upgrade path
// if multi-user isolation is needed.
func RunHost(args []string, stdout io.Writer) int {
	if len(args) < 3 {
		fmt.Fprintf(os.Stderr, "usage: opr pty-host <sessionId> <cwd> <shellCmd> [shellArg...]\n")
		return 1
	}

	sessionID := args[0]
	cwd := args[1]
	shellCmd := args[2]
	shellArgs := args[3:]
	if err := os.Chdir(cwd); err != nil {
		fmt.Fprintf(os.Stderr, "pty-host [%s]: chdir %s: %v\n", sessionID, cwd, err)
		return 1
	}

	// Bind before creating the PTY so we can report READY atomically.
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		fmt.Fprintf(os.Stderr, "pty-host [%s]: listen: %v\n", sessionID, err)
		return 1
	}
	tcpAddr, ok := ln.Addr().(*net.TCPAddr)
	if !ok {
		_ = ln.Close()
		fmt.Fprintf(os.Stderr, "pty-host [%s]: listener is not TCP\n", sessionID)
		return 1
	}
	port := tcpAddr.Port

	pty, err := newPTY(cwd, shellCmd, shellArgs)
	if err != nil {
		_ = ln.Close()
		fmt.Fprintf(os.Stderr, "pty-host [%s]: newConPTY: %v\n", sessionID, err)
		return 1
	}

	// Print READY after both the listener and the PTY are up.
	_, _ = fmt.Fprintf(stdout, "READY:%d %d\n", pty.PID(), port)

	// Re-point fds 1/2 at a log file now that the parent has what it needs.
	// The spawning daemon may exit at any point after this; on Unix, a
	// stdio write after that happens would otherwise get EPIPE and the Go
	// runtime would SIGPIPE this process (see redirect_unix.go).
	redirectStdio(openSessionLogFile(sessionID))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Install signal handlers so SIGTERM/SIGINT trigger graceful shutdown.
	sigC := make(chan os.Signal, 1)
	signal.Notify(sigC, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		select {
		case sig := <-sigC:
			fmt.Fprintf(os.Stderr, "pty-host [%s]: signal %v, shutting down\n", sessionID, sig)
			cancel()
		case <-ctx.Done():
		}
	}()

	ring := NewRing()
	cfg := ServeConfig{
		SessionID: sessionID,
		Listener:  ln,
		PTY:       pty,
		Ring:      ring,
	}

	if err := Serve(ctx, cfg); err != nil {
		fmt.Fprintf(os.Stderr, "pty-host [%s]: serve: %v\n", sessionID, err)
		return 1
	}
	return 0
}

// openSessionLogFile opens (creating if needed) the per-session log file that
// post-READY stdio is redirected to, under ~/.operator/pty-host-logs. Falls
// back to os.DevNull if the home directory or the log file cannot be
// resolved/created, since a missing log is not a reason to fail the host.
func openSessionLogFile(sessionID string) *os.File {
	home, err := os.UserHomeDir()
	if err == nil {
		dir := filepath.Join(home, ".operator", "pty-host-logs")
		if err := os.MkdirAll(dir, 0o700); err == nil {
			if f, err := os.OpenFile(filepath.Join(dir, sessionID+".log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600); err == nil {
				return f
			}
		}
	}
	if f, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0); err == nil {
		return f
	}
	return nil
}
