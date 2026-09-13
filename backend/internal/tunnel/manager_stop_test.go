//go:build !windows

package tunnel

import (
	"context"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func recordedPIDs(t *testing.T, path string) []int {
	t.Helper()
	body, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var pids []int
	for _, line := range strings.Fields(string(body)) {
		pid, convErr := strconv.Atoi(line)
		if convErr != nil {
			t.Fatalf("pid file line %q: %v", line, convErr)
		}
		pids = append(pids, pid)
	}
	return pids
}

func processAlive(pid int) bool {
	return syscall.Kill(pid, syscall.Signal(0)) == nil
}

func TestARestartAttemptThatNeverPublishesAURLIsStopped(t *testing.T) {
	dir := t.TempDir()
	pidFile := filepath.Join(dir, "pids")
	marker := filepath.Join(dir, "marker")
	t.Setenv("TUNNEL_TEST_PIDS", pidFile)
	t.Setenv("TUNNEL_TEST_MARKER", marker)

	script := "#!/bin/sh\n" +
		"echo $$ >> \"$TUNNEL_TEST_PIDS\"\n" +
		"if [ -f \"$TUNNEL_TEST_MARKER\" ]; then while true; do sleep 1; done; fi\n" +
		"touch \"$TUNNEL_TEST_MARKER\"\n" +
		"exit 1\n"

	provider := newFakeProvider(t, "ngrok", script)
	provider.setURLErr(ErrNoURLYet)
	provider.setFailure(Failure{Class: FailureNetwork, Message: "edge unreachable"})

	clock := newFakeClock()
	sleeper := newRecordingSleeper()
	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{provider},
		Binaries:    fakeStore{path: provider.binary},
		Now:         clock.Now,
		Sleep:       sleeper.sleep,
		ReservePort: func() (int, error) { return 46201, nil },
	})
	m.SetLocalPort(3011)
	defer m.Close()

	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}
	waitForState(t, m, StateReconnecting)
	sleeper.release(1)

	var restarted int
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		pids := recordedPIDs(t, pidFile)
		if len(pids) >= 2 && processAlive(pids[1]) {
			restarted = pids[1]
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if restarted == 0 {
		t.Fatalf("no live restart attempt was observed; recorded pids %v", recordedPIDs(t, pidFile))
	}

	clock.advance(startTimeout + time.Second)

	gone := false
	deadline = time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if !processAlive(restarted) {
			gone = true
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if !gone {
		t.Fatalf("pid %d survived its url-await timeout: a restart attempt that never published a url must be stopped, not leaked", restarted)
	}
}
