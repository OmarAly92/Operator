//go:build parity && !windows

package parity

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/unix"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/codex"
	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/service/shellterm"
	"github.com/OmarAly92/operator/backend/internal/service/terminalblock"
	"github.com/OmarAly92/operator/backend/internal/service/terminalcapture"
)

type runnerOutputs struct {
	plain  string
	styled string
}

func replayTmux(t *testing.T, sc Scenario) runnerOutputs {
	t.Helper()

	dir := t.TempDir()
	fifoPath := filepath.Join(dir, "fifo")
	if err := unix.Mkfifo(fifoPath, 0o600); err != nil {
		t.Fatalf("mkfifo: %v", err)
	}

	label := uniqueID("parity-dec")
	session := "s"
	tmuxCmd := func(args ...string) *exec.Cmd {
		full := append([]string{"-L", label}, args...)
		return exec.Command("tmux", full...)
	}

	newSession := tmuxCmd("-f", "/dev/null", "new-session", "-d", "-s", session,
		"-x", strconv.Itoa(sc.Cols), "-y", strconv.Itoa(sc.Rows), "cat < "+fifoPath)
	if out, err := newSession.CombinedOutput(); err != nil {
		t.Fatalf("tmux new-session: %v: %s", err, out)
	}
	t.Cleanup(func() { _ = tmuxCmd("kill-server").Run() })

	f, err := os.OpenFile(fifoPath, os.O_WRONLY, 0)
	if err != nil {
		t.Fatalf("open fifo write end: %v", err)
	}
	defer f.Close()

	capture := func() string {
		out, err := tmuxCmd("capture-pane", "-t", session, "-p").Output()
		if err != nil {
			return ""
		}
		return string(out)
	}
	if _, err := f.Write(sc.Bytes); err != nil {
		t.Fatalf("write bytes: %v", err)
	}
	waitQuiescent(t, capture)

	plainOut, err := tmuxCmd("capture-pane", "-t", session, "-p").Output()
	if err != nil {
		t.Fatalf("tmux capture-pane -p: %v", err)
	}
	styledOut, err := tmuxCmd("capture-pane", "-t", session, "-p", "-e").Output()
	if err != nil {
		t.Fatalf("tmux capture-pane -p -e: %v", err)
	}
	return runnerOutputs{plain: string(plainOut), styled: string(styledOut)}
}

func replayPtyHost(t *testing.T, sc Scenario) runnerOutputs {
	t.Helper()

	bin := oprBinary(t)
	isolateRegistry(t)

	dir := t.TempDir()
	fifoPath := filepath.Join(dir, "fifo")
	if err := unix.Mkfifo(fifoPath, 0o600); err != nil {
		t.Fatalf("mkfifo: %v", err)
	}
	workDir := t.TempDir()

	rt := ptyhost.New(ptyhost.Options{Spawner: realHostSpawner(bin)})
	ctx := context.Background()
	sessionID := uniqueID("dec")
	handle, err := rt.Create(ctx, ports.RuntimeConfig{
		SessionID:     domain.SessionID(sessionID),
		WorkspacePath: workDir,
		Argv:          []string{"/bin/sh", "-c", "cat < " + fifoPath},
	})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	t.Cleanup(func() { _ = rt.Destroy(context.Background(), handle) })

	stream, err := rt.Attach(ctx, handle, uint16(sc.Rows), uint16(sc.Cols))
	if err != nil {
		t.Fatalf("Attach: %v", err)
	}
	defer stream.Close()
	go io.Copy(io.Discard, stream) //nolint:errcheck

	f, err := os.OpenFile(fifoPath, os.O_WRONLY, 0)
	if err != nil {
		t.Fatalf("open fifo write end: %v", err)
	}
	defer f.Close()

	capture := func() string {
		out, err := rt.GetOutput(ctx, handle, sc.Rows)
		if err != nil {
			return ""
		}
		return out
	}
	if _, err := f.Write(sc.Bytes); err != nil {
		t.Fatalf("write bytes: %v", err)
	}
	waitQuiescent(t, capture)

	plainOut, err := rt.GetOutput(ctx, handle, sc.Rows)
	if err != nil {
		t.Fatalf("GetOutput: %v", err)
	}
	styledOut, err := rt.GetStyledOutput(ctx, handle, sc.Rows)
	if err != nil {
		t.Fatalf("GetStyledOutput: %v", err)
	}
	return runnerOutputs{plain: plainOut, styled: styledOut}
}

func agentIdleScenario(t *testing.T) Scenario {
	t.Helper()
	for _, sc := range Corpus() {
		if sc.Name == "agent-cli-idle" {
			return sc
		}
	}
	t.Fatal("agent-cli-idle scenario not found in corpus")
	return Scenario{}
}

func TestDecisionSitesAgreeAcrossRuntimes(t *testing.T) {
	requireTmux(t)
	sc := agentIdleScenario(t)

	tmuxOut := replayTmux(t, sc)
	hostOut := replayPtyHost(t, sc)

	detector := codex.New()

	t.Run("terminal-activity-detector", func(t *testing.T) {
		stateT, okT := detector.DetectTerminalActivity(tmuxOut.plain)
		stateH, okH := detector.DetectTerminalActivity(hostOut.plain)
		if stateT != stateH || okT != okH {
			t.Fatalf("DetectTerminalActivity disagrees: tmux=(%v,%v) ptyhost=(%v,%v)", stateT, okT, stateH, okH)
		}
	})

	t.Run("empty-composer-detector", func(t *testing.T) {
		emptyT := detector.ComposerIsEmpty(tmuxOut.styled)
		emptyH := detector.ComposerIsEmpty(hostOut.styled)
		if emptyT != emptyH {
			t.Fatalf("ComposerIsEmpty disagrees: tmux=%v ptyhost=%v", emptyT, emptyH)
		}
	})

	t.Run("pattern-readiness-scan", func(t *testing.T) {
		for _, pattern := range []string{"❯", "definitely-not-present-marker"} {
			gotT := strings.Contains(tmuxOut.plain, pattern)
			gotH := strings.Contains(hostOut.plain, pattern)
			if gotT != gotH {
				t.Fatalf("strings.Contains(output, %q) disagrees: tmux=%v ptyhost=%v", pattern, gotT, gotH)
			}
		}
	})
}

func TestCaptureSupervisorAgainstPtyHost(t *testing.T) {
	bin := oprBinary(t)
	isolateRegistry(t)
	captureRoot := t.TempDir()
	t.Setenv("OPERATOR_DATA_DIR", captureRoot)

	dir := t.TempDir()
	fifoPath := filepath.Join(dir, "fifo")
	if err := unix.Mkfifo(fifoPath, 0o600); err != nil {
		t.Fatalf("mkfifo: %v", err)
	}
	workDir := t.TempDir()

	rt := ptyhost.New(ptyhost.Options{Spawner: realHostSpawner(bin)})
	ctx := context.Background()
	sessionID := uniqueID("cap")
	handle, err := rt.Create(ctx, ports.RuntimeConfig{
		SessionID:     domain.SessionID(sessionID),
		WorkspacePath: workDir,
		Argv:          []string{"/bin/sh", "-c", "cat < " + fifoPath},
	})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	t.Cleanup(func() { _ = rt.Destroy(context.Background(), handle) })

	blocks := terminalblock.NewService(noopBlockStore{})
	sup := terminalcapture.NewSupervisor(rt, blocks, captureRoot, 5*time.Second, nil)

	rec := shellterm.ShellTerminalRecord{
		HandleID:   sessionID,
		SessionID:  domain.SessionID(sessionID),
		WorkingDir: workDir,
	}

	if err := sup.Start(ctx, rec); err != nil {
		if errors.Is(err, ports.ErrCaptureUnsupported) {
			t.Fatal("Supervisor.Start returned ErrCaptureUnsupported against ptyhost; capture must work on this platform")
		}
		t.Fatalf("Supervisor.Start: %v", err)
	}
	if !sup.Capturing(sessionID) {
		t.Fatal("Capturing() = false after Start")
	}

	f, err := os.OpenFile(fifoPath, os.O_WRONLY, 0)
	if err != nil {
		t.Fatalf("open fifo write end: %v", err)
	}
	if _, err := f.Write([]byte("hello capture\r\n")); err != nil {
		t.Fatalf("write: %v", err)
	}
	time.Sleep(300 * time.Millisecond)
	_ = f.Close()

	if err := sup.StopAndDrain(ctx, sessionID); err != nil {
		t.Fatalf("StopAndDrain: %v", err)
	}

	entries, err := os.ReadDir(filepath.Join(captureRoot, "terminal-capture", sessionID))
	if err != nil || len(entries) == 0 {
		t.Fatalf("expected capture journal entries under %s/terminal-capture/%s, got err=%v entries=%v", captureRoot, sessionID, err, entries)
	}
}

type noopBlockStore struct{}

func (noopBlockStore) UpsertTerminalBlock(ctx context.Context, b domain.Block) error { return nil }
func (noopBlockStore) ListTerminalBlocks(ctx context.Context, terminalID string, limit int) ([]domain.Block, error) {
	return nil, nil
}
func (noopBlockStore) TrimTerminalBlocks(ctx context.Context, terminalID string, keep int) error {
	return nil
}
func (noopBlockStore) DeleteTerminalBlocks(ctx context.Context, terminalID string) error {
	return nil
}
