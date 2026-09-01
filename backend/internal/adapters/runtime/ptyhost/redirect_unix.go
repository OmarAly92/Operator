//go:build !windows

// redirect_unix.go dup2's fds 1 and 2 onto a log file after RunHost reports
// READY. Once the daemon that spawned this detached pty-host exits, the next
// write to the old stdout/stderr pipe gets EPIPE, and the Go runtime kills a
// process on EPIPE to fd 1/2 with SIGPIPE — a real fd-level dup is required so
// the runtime's own writes (not just this package's) land on the log file
// instead of the dead pipe.
package ptyhost

import (
	"os"

	"golang.org/x/sys/unix"
)

func redirectStdio(f *os.File) {
	if f == nil {
		return
	}
	_ = unix.Dup2(int(f.Fd()), 1)
	_ = unix.Dup2(int(f.Fd()), 2)
}
