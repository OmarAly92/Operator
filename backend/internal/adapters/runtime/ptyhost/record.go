package ptyhost

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

const recordEnv = "OPERATOR_PTY_RECORD"

type recordSize struct {
	Offset int64 `json:"offset"`
	Cols   int   `json:"cols"`
	Rows   int   `json:"rows"`
}

type recorder struct {
	mu        sync.Mutex
	recording *os.File
	timing    *os.File
	started   time.Time
	sizesPath string
	sizes     []recordSize
	written   int64
	err       error
}

func openRecorder(dir, sessionID string, cols, rows int) (*recorder, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	recording, err := os.OpenFile(filepath.Join(dir, sessionID+".recording"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return nil, err
	}
	timing, err := os.OpenFile(filepath.Join(dir, sessionID+".timing.jsonl"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		_ = recording.Close()
		return nil, err
	}
	r := &recorder{
		recording: recording,
		timing:    timing,
		started:   time.Now(),
		sizesPath: filepath.Join(dir, sessionID+".size.json"),
		sizes:     []recordSize{{Offset: 0, Cols: cols, Rows: rows}},
	}
	r.writeSizesLocked()
	return r, nil
}

func (r *recorder) write(batch []byte) {
	if r == nil || len(batch) == 0 {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.err != nil {
		return
	}
	if _, err := fmt.Fprintf(r.timing, "[%d,%d]\n", r.written, time.Since(r.started).Milliseconds()); err != nil {
		r.err = err
		return
	}
	n, err := r.recording.Write(batch)
	r.written += int64(n)
	if err != nil {
		r.err = err
	}
}

func (r *recorder) resize(cols, rows int) {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	last := r.sizes[len(r.sizes)-1]
	if last.Cols == cols && last.Rows == rows {
		return
	}
	r.sizes = append(r.sizes, recordSize{Offset: r.written, Cols: cols, Rows: rows})
	r.writeSizesLocked()
}

func (r *recorder) writeSizesLocked() {
	data, err := json.Marshal(r.sizes)
	if err != nil {
		r.err = err
		return
	}
	if err := os.WriteFile(r.sizesPath, data, 0o600); err != nil {
		r.err = err
	}
}

func (r *recorder) close() error {
	if r == nil {
		return nil
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if err := r.timing.Close(); err != nil && r.err == nil {
		r.err = err
	}
	if err := r.recording.Close(); err != nil && r.err == nil {
		r.err = err
	}
	return r.err
}
