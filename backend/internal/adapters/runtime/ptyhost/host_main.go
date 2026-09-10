// host_main.go is the RunHost entrypoint for the "opr pty-host" subcommand.
// It is cross-platform: the loopback TCP bind and signal wiring work on all
// OSes; only the ConPTY creation (newConPTY) is OS-gated via build tags.
package ptyhost

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

// initialCols/initialRows are the grid the shared PTY (and its passive parser)
// start at when the spawner named none; vt-core defaults to 24 rows on its
// own, so this mirrors the same 80x24 into both. A spawner that knows the
// pane's grid passes it as `--grid COLSxROWS` so the child is born at the
// size it will be shown at and its first attach costs no SIGWINCH.
const (
	initialCols = 80
	initialRows = 24
	gridFlag    = "--grid"
	maxGridSide = 1000
)

// hostArgs builds the `opr pty-host` argv (without the executable). cols/rows
// of zero omit the grid flag and leave the host at its default.
func hostArgs(sessionID, cwd string, argv []string, cols, rows int) []string {
	args := []string{"pty-host"}
	if cols > 0 && rows > 0 {
		args = append(args, gridFlag, fmt.Sprintf("%dx%d", cols, rows))
	}
	args = append(args, sessionID, cwd)
	return append(args, argv...)
}

type hostArgv struct {
	cols, rows int
	sessionID  string
	cwd        string
	shellCmd   string
	shellArgs  []string
}

func parseHostArgs(args []string) (hostArgv, error) {
	parsed := hostArgv{cols: initialCols, rows: initialRows}
	if len(args) >= 2 && args[0] == gridFlag {
		cols, rows, err := parseGrid(args[1])
		if err != nil {
			return hostArgv{}, err
		}
		parsed.cols, parsed.rows = cols, rows
		args = args[2:]
	}
	if len(args) < 3 {
		return hostArgv{}, errors.New("usage: opr pty-host [--grid COLSxROWS] <sessionId> <cwd> <shellCmd> [shellArg...]")
	}
	parsed.sessionID, parsed.cwd, parsed.shellCmd, parsed.shellArgs = args[0], args[1], args[2], args[3:]
	return parsed, nil
}

func parseGrid(spec string) (int, int, error) {
	colsText, rowsText, ok := strings.Cut(spec, "x")
	if !ok {
		return 0, 0, fmt.Errorf("pty-host: --grid %q: want COLSxROWS", spec)
	}
	cols, colsErr := strconv.Atoi(colsText)
	rows, rowsErr := strconv.Atoi(rowsText)
	if colsErr != nil || rowsErr != nil || cols < 1 || rows < 1 || cols > maxGridSide || rows > maxGridSide {
		return 0, 0, fmt.Errorf("pty-host: --grid %q: sides must be 1..%d", spec, maxGridSide)
	}
	return cols, rows, nil
}

// RunHost is the "opr pty-host" entrypoint. argv is everything after the
// subcommand name: [--grid COLSxROWS] <sessionId> <cwd> <shellCmd> [shellArg...]
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
	parsed, err := parseHostArgs(args)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	sessionID, cwd, shellCmd, shellArgs := parsed.sessionID, parsed.cwd, parsed.shellCmd, parsed.shellArgs
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

	pty, err := newPTY(cwd, shellCmd, shellArgs, nil, parsed.cols, parsed.rows)
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
	parser, err := vtwasm.New(ctx, vtwasm.Module, uint32(parsed.cols), uint32(parsed.rows), MaxOutputLines)
	if err != nil {
		fmt.Fprintf(os.Stderr, "pty-host [%s]: vtwasm.New: %v\n", sessionID, err)
		parser = nil
	}
	cfg := ServeConfig{
		SessionID:   sessionID,
		Listener:    ln,
		PTY:         pty,
		Ring:        ring,
		Parser:      parser,
		InitialCols: parsed.cols,
		InitialRows: parsed.rows,
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
