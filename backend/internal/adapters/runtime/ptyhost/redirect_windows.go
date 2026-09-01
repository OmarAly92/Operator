//go:build windows

// redirect_windows.go reassigns os.Stdout/os.Stderr after RunHost reports
// READY, for log-capture symmetry with the Unix host. Windows has no SIGPIPE,
// so there is no crash risk here; this only keeps post-READY diagnostics out
// of the daemon's pipe.
package ptyhost

import "os"

func redirectStdio(f *os.File) {
	if f == nil {
		return
	}
	os.Stdout = f
	os.Stderr = f
}
