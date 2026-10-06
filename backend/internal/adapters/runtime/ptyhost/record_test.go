package ptyhost

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRecorderTeesBytesAndLogsSizesAtByteOffsets(t *testing.T) {
	dir := t.TempDir()
	rec, err := openRecorder(dir, "sess-1", 120, 40)
	if err != nil {
		t.Fatalf("openRecorder: %v", err)
	}
	rec.write([]byte("hello "))
	rec.resize(100, 30)
	rec.write([]byte("world"))
	if err := rec.close(); err != nil {
		t.Fatalf("close: %v", err)
	}

	got, err := os.ReadFile(filepath.Join(dir, "sess-1.recording"))
	if err != nil {
		t.Fatalf("read recording: %v", err)
	}
	if string(got) != "hello world" {
		t.Fatalf("recording = %q, want %q", got, "hello world")
	}
	raw, err := os.ReadFile(filepath.Join(dir, "sess-1.size.json"))
	if err != nil {
		t.Fatalf("read size.json: %v", err)
	}
	var sizes []recordSize
	if err := json.Unmarshal(raw, &sizes); err != nil {
		t.Fatalf("size.json: %v\n%s", err, raw)
	}
	want := []recordSize{{Offset: 0, Cols: 120, Rows: 40}, {Offset: 6, Cols: 100, Rows: 30}}
	if len(sizes) != len(want) {
		t.Fatalf("sizes = %+v, want %+v", sizes, want)
	}
	for i := range want {
		if sizes[i] != want[i] {
			t.Fatalf("sizes[%d] = %+v, want %+v", i, sizes[i], want[i])
		}
	}
}

func TestRecorderIgnoresARedundantResize(t *testing.T) {
	dir := t.TempDir()
	rec, err := openRecorder(dir, "sess-2", 80, 24)
	if err != nil {
		t.Fatalf("openRecorder: %v", err)
	}
	rec.resize(80, 24)
	_ = rec.close()
	raw, _ := os.ReadFile(filepath.Join(dir, "sess-2.size.json"))
	var sizes []recordSize
	_ = json.Unmarshal(raw, &sizes)
	if len(sizes) != 1 {
		t.Fatalf("sizes = %+v, want the birth entry only", sizes)
	}
}

func TestNilRecorderIsANoOp(t *testing.T) {
	var rec *recorder
	rec.write([]byte("x"))
	rec.resize(1, 1)
	if err := rec.close(); err != nil {
		t.Fatalf("close: %v", err)
	}
}

func TestRecorderWritesOneTimingLinePerBatch(t *testing.T) {
	dir := t.TempDir()
	r, err := openRecorder(dir, "sess-timing", 80, 24)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	r.write([]byte("first"))
	r.write([]byte("second!"))
	if err := r.close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	raw, err := os.ReadFile(filepath.Join(dir, "sess-timing.timing.jsonl"))
	if err != nil {
		t.Fatalf("read timing: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(raw)), "\n")
	if len(lines) != 2 {
		t.Fatalf("timing lines = %q, want 2", lines)
	}
	var first, second [2]int64
	if err := json.Unmarshal([]byte(lines[0]), &first); err != nil {
		t.Fatalf("line 0: %v", err)
	}
	if err := json.Unmarshal([]byte(lines[1]), &second); err != nil {
		t.Fatalf("line 1: %v", err)
	}
	if first[0] != 0 || second[0] != 5 || second[1] < first[1] {
		t.Fatalf("timing = %v %v, want offsets 0 and 5 with time not going back", first, second)
	}
}
