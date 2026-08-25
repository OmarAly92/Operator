//go:build windows

package agentbrowser

import (
	"os/exec"
	"syscall"

	"golang.org/x/sys/windows"
)

func defaultProcessAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	handle, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION, false, uint32(pid))
	if err != nil {
		return false
	}
	_ = windows.CloseHandle(handle)
	return true
}

func childProcessAttr() *syscall.SysProcAttr {
	return &syscall.SysProcAttr{}
}

func killChildProcess(cmd *exec.Cmd) {
	if cmd.Process == nil {
		return
	}
	_ = cmd.Process.Kill()
}
