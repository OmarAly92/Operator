package vtwasm

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestAgentSessionReplayReport(t *testing.T) {
	fixture := os.Getenv("OPERATOR_AGENT_FIXTURE")
	if fixture == "" {
		t.Skip("set OPERATOR_AGENT_FIXTURE to a fixture directory")
	}
	recording, err := os.ReadFile(filepath.Join(fixture, "recording"))
	if err != nil {
		t.Fatalf("read recording: %v", err)
	}
	raw, err := os.ReadFile(filepath.Join(fixture, "size.json"))
	if err != nil {
		t.Fatalf("read size.json: %v", err)
	}
	var sizes []struct {
		Offset int `json:"offset"`
		Cols   uint32
		Rows   uint32
	}
	if err := json.Unmarshal(raw, &sizes); err != nil {
		t.Fatalf("size.json: %v", err)
	}
	p, err := New(context.Background(), Module, sizes[0].Cols, sizes[0].Rows, Limits{Rows: 1000, Bytes: 0xffffffff})
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	defer p.Close()
	next := 1
	for offset := 0; offset < len(recording); {
		end := min(offset+64<<10, len(recording))
		if next < len(sizes) && sizes[next].Offset < end {
			end = sizes[next].Offset
		}
		if end > offset {
			if err := p.Feed(recording[offset:end]); err != nil {
				t.Fatalf("feed: %v", err)
			}
			offset = end
		}
		if next < len(sizes) && sizes[next].Offset == offset {
			if err := p.Resize(sizes[next].Cols, sizes[next].Rows); err != nil {
				t.Fatalf("resize: %v", err)
			}
			next++
		}
	}
	start := time.Now()
	replay, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	elapsed := time.Since(start)
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	report := map[string]any{
		"replayBytes":      len(replay),
		"replayRows":       strings.Count(replay, "\r\n") + 1,
		"replayRenderMs":   float64(elapsed.Microseconds()) / 1000,
		"mirrorWasmBytes":  p.module.Memory().Size(),
		"goHeapAllocBytes": stats.HeapAlloc,
	}
	if out := os.Getenv("OPERATOR_AGENT_REPLAY_OUT"); out != "" {
		if err := os.WriteFile(out, []byte(replay), 0o600); err != nil {
			t.Fatalf("write replay: %v", err)
		}
	}
	encoded, _ := json.Marshal(report)
	t.Logf("REPORT %s", encoded)
}
