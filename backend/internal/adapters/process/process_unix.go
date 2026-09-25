//go:build !windows

package process

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

func (t *Table) ListProcesses(ctx context.Context) ([]ports.ProcessInfo, error) {
	out, err := exec.CommandContext(ctx, "ps", "-A", "-ww", "-o", "pid=,ppid=,pgid=,command=").Output()
	if err != nil {
		return nil, fmt.Errorf("process: ps: %w", err)
	}
	var procs []ports.ProcessInfo
	scanner := bufio.NewScanner(bytes.NewReader(out))
	scanner.Buffer(make([]byte, 0, 64<<10), 1<<20)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 3 {
			continue
		}
		pid, errPID := strconv.Atoi(fields[0])
		ppid, errPPID := strconv.Atoi(fields[1])
		pgid, errPGID := strconv.Atoi(fields[2])
		if errPID != nil || errPPID != nil || errPGID != nil {
			continue
		}
		procs = append(procs, ports.ProcessInfo{PID: pid, PPID: ppid, PGID: pgid, Command: strings.Join(fields[3:], " ")})
	}
	return procs, scanner.Err()
}

func (t *Table) OpenFileHolders(ctx context.Context, path string) ([]int, error) {
	if _, err := os.Stat(path); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}
	if lsof, err := exec.LookPath("lsof"); err == nil {
		return lsofHolders(ctx, lsof, path)
	}
	return procHolders(path)
}

func lsofHolders(ctx context.Context, lsof, path string) ([]int, error) {
	out, err := exec.CommandContext(ctx, lsof, "-t", "--", path).Output()
	var exit *exec.ExitError
	if err != nil && !errors.As(err, &exit) {
		return nil, fmt.Errorf("process: lsof: %w", err)
	}
	var pids []int
	for _, field := range strings.Fields(string(out)) {
		if pid, err := strconv.Atoi(field); err == nil {
			pids = append(pids, pid)
		}
	}
	return pids, nil
}

func procHolders(path string) ([]int, error) {
	target, err := filepath.EvalSymlinks(path)
	if err != nil {
		return nil, err
	}
	fds, err := filepath.Glob("/proc/[0-9]*/fd/*")
	if err != nil {
		return nil, err
	}
	seen := map[int]bool{}
	var pids []int
	for _, fd := range fds {
		link, err := os.Readlink(fd)
		if err != nil || link != target {
			continue
		}
		pid, err := strconv.Atoi(strings.Split(strings.TrimPrefix(fd, "/proc/"), "/")[0])
		if err != nil || seen[pid] {
			continue
		}
		seen[pid] = true
		pids = append(pids, pid)
	}
	return pids, nil
}

func (t *Table) Terminate(pid int, group bool) error {
	return send(pid, group, syscall.SIGTERM)
}

func (t *Table) Kill(pid int, group bool) error {
	return send(pid, group, syscall.SIGKILL)
}

func (t *Table) Alive(pid int) bool {
	if pid <= 0 {
		return false
	}
	err := syscall.Kill(pid, 0)
	return err == nil || errors.Is(err, syscall.EPERM)
}

func send(pid int, group bool, sig syscall.Signal) error {
	if pid <= 1 {
		return fmt.Errorf("process: refusing to signal pid %d", pid)
	}
	target := pid
	if group {
		target = -pid
	}
	if err := syscall.Kill(target, sig); err != nil && !errors.Is(err, syscall.ESRCH) {
		return err
	}
	return nil
}
