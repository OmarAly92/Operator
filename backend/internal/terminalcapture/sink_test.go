package terminalcapture

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestSinkSealsShortSegmentBeforeRunReturns(t *testing.T) {
	dir := epochDir(t)
	j, err := Open(dir)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	payload := "a brief burst of shell output\n"
	err = NewSink(j).Run(context.Background(), strings.NewReader(payload))
	if err != nil {
		t.Fatalf("run: %v", err)
	}

	if _, err := os.Stat(filepath.Join(dir, ManifestFileName)); err != nil {
		t.Fatalf("manifest not written before Run returned: %v", err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	sealed := false
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), OpenSuffix) {
			t.Fatalf("open segment %s left unsealed after Run", e.Name())
		}
		if strings.HasSuffix(e.Name(), ReadySuffix) {
			sealed = true
			got, _ := os.ReadFile(filepath.Join(dir, e.Name()))
			if string(got) != payload {
				t.Fatalf("sealed content %q != %q", got, payload)
			}
		}
	}
	if !sealed {
		t.Fatal("short final segment was not sealed to .ready")
	}
}

func TestSinkHonorsContextCancellation(t *testing.T) {
	dir := epochDir(t)
	j, err := Open(dir)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	pr, pw := io.Pipe()
	ctx, cancel := context.WithCancel(context.Background())

	runErr := make(chan error, 1)
	go func() {
		runErr <- NewSink(j).Run(ctx, pr)
	}()

	if _, err := pw.Write([]byte("some output before cancel\n")); err != nil {
		t.Fatalf("pipe write: %v", err)
	}
	time.Sleep(20 * time.Millisecond)
	cancel()
	_ = pw.Close()

	select {
	case err := <-runErr:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("Run error = %v, want context.Canceled", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("Run did not return after context cancellation")
	}

	if _, err := os.Stat(filepath.Join(dir, ManifestFileName)); err != nil {
		t.Fatalf("sink did not seal journal on cancellation: %v", err)
	}
}
