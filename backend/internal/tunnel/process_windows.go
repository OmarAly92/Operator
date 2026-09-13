//go:build windows

package tunnel

import "os/exec"

func newTunnelCommand(name string, args ...string) *exec.Cmd {
	return exec.Command(name, args...)
}

func processStartTime(int) string { return "" }

func terminateProcess(cmd *exec.Cmd) error {
	if cmd == nil || cmd.Process == nil {
		return nil
	}
	return cmd.Process.Kill()
}

func forceKillProcess(cmd *exec.Cmd) error { return terminateProcess(cmd) }

func forceKillPID(int, string) error { return nil }
