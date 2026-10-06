//go:build !windows

package ptyhost_test

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/testsupport/realpty"
)

func startLineRecorder(t *testing.T, id domain.SessionID) *recorder {
	t.Helper()
	realpty.IsolateRegistry(t)
	dir := t.TempDir()
	out := filepath.Join(dir, "lines")
	ready := filepath.Join(dir, "ready")
	script := fmt.Sprintf("stty -echo; : > %q; while IFS= read -r line; do printf '%%s\\n' \"$line\" >> %q; done", ready, out)

	rt := realpty.Runtime(t)
	handle, err := rt.Create(context.Background(), ports.RuntimeConfig{
		SessionID:     id,
		WorkspacePath: dir,
		Argv:          []string{"sh", "-c", script},
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = rt.Destroy(context.Background(), handle) })

	deadline := time.Now().Add(10 * time.Second)
	for {
		if _, err := os.Stat(ready); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("line recorder never started")
		}
		time.Sleep(20 * time.Millisecond)
	}
	return &recorder{t: t, rt: rt, handle: handle, path: out}
}

type recorder struct {
	t      *testing.T
	rt     *ptyhost.Runtime
	handle ports.RuntimeHandle
	path   string
}

func (r *recorder) waitLines(n int) []string {
	r.t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	for {
		data, _ := os.ReadFile(r.path)
		lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
		if len(data) > 0 && len(lines) >= n {
			return lines
		}
		if time.Now().After(deadline) {
			r.t.Fatalf("shell recorded %d of %d lines: %q", len(lines), n, string(data))
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func TestSendMessageConcurrentCallsReachShellAsSeparateCommands(t *testing.T) {
	rec := startLineRecorder(t, "input-order-concurrent")

	const n = 12
	want := make([]string, 0, n)
	var wg sync.WaitGroup
	errs := make(chan error, n)
	for i := 0; i < n; i++ {
		msg := fmt.Sprintf("printf 'message-%02d\\n'", i)
		want = append(want, msg)
		wg.Add(1)
		go func(i int, msg string) {
			defer wg.Done()
			if i%3 == 2 {
				errs <- rec.rt.SendInput(context.Background(), rec.handle, msg+"\r")
				return
			}
			errs <- rec.rt.SendMessage(context.Background(), rec.handle, msg)
		}(i, msg)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}

	got := rec.waitLines(n)
	sort.Strings(got)
	sort.Strings(want)
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("shell received\n%s\nwant\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

func TestSendMessageBackToBackCallsReachShellInOrder(t *testing.T) {
	rec := startLineRecorder(t, "input-order-sequential")

	msgs := []string{"printf 'while-reader-gone-one\\n'", "printf 'while-reader-gone-two\\n'"}
	for _, msg := range msgs {
		if err := rec.rt.SendMessage(context.Background(), rec.handle, msg); err != nil {
			t.Fatal(err)
		}
	}
	const word = "ordered-keystrokes-0123456789"
	for _, r := range word {
		if err := rec.rt.SendInput(context.Background(), rec.handle, string(r)); err != nil {
			t.Fatal(err)
		}
	}
	if err := rec.rt.SendInput(context.Background(), rec.handle, "\r"); err != nil {
		t.Fatal(err)
	}

	want := append(append([]string(nil), msgs...), word)
	got := rec.waitLines(len(want))
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("shell received\n%s\nwant\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}
