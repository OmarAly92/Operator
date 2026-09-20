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

var productMirrorLimits = Limits{Rows: 200_000, Bytes: 128 << 20}

type fixtureSize struct {
	Offset int `json:"offset"`
	Cols   uint32
	Rows   uint32
}

func readAgentFixture(t *testing.T, fixture string) ([]byte, []fixtureSize) {
	t.Helper()
	recording, err := os.ReadFile(filepath.Join(fixture, "recording"))
	if err != nil {
		t.Fatalf("read recording: %v", err)
	}
	raw, err := os.ReadFile(filepath.Join(fixture, "size.json"))
	if err != nil {
		t.Fatalf("read size.json: %v", err)
	}
	var sizes []fixtureSize
	if err := json.Unmarshal(raw, &sizes); err != nil {
		t.Fatalf("size.json: %v", err)
	}
	return recording, sizes
}

func feedAgentFixture(t *testing.T, recording []byte, sizes []fixtureSize, limits Limits) *Parser {
	t.Helper()
	p, err := New(context.Background(), Module, sizes[0].Cols, sizes[0].Rows, limits)
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	next := 1
	for offset := 0; offset < len(recording); {
		end := min(offset+64<<10, len(recording))
		if next < len(sizes) && sizes[next].Offset < end {
			end = sizes[next].Offset
		}
		if end > offset {
			if err := p.Feed(recording[offset:end]); err != nil {
				p.Close()
				t.Fatalf("feed: %v", err)
			}
			offset = end
		}
		if next < len(sizes) && sizes[next].Offset == offset {
			if err := p.Resize(sizes[next].Cols, sizes[next].Rows); err != nil {
				p.Close()
				t.Fatalf("resize: %v", err)
			}
			next++
		}
	}
	return p
}

const blockMarkOSCPrefix = "\x1b]7000;v=1;"
const blockMarkST = "\x1b\\"

func blockMarks(p *Parser) ([]string, error) {
	var out []byte
	before := HistoryBefore
	for {
		chunk, next, ok, err := p.HistoryChunk(before, 1000, HistoryChunkRows)
		if err != nil {
			return nil, err
		}
		if !ok {
			break
		}
		out = append(out, chunk...)
		before = next
	}
	text := string(out)
	var marks []string
	for {
		start := strings.Index(text, blockMarkOSCPrefix)
		if start < 0 {
			break
		}
		rest := text[start+len(blockMarkOSCPrefix):]
		end := strings.Index(rest, blockMarkST)
		if end < 0 {
			break
		}
		body := rest[:end]
		switch {
		case strings.HasPrefix(body, "history="):
		case strings.Contains(body, ";cmd="):
			marks = append(marks, "cmd:"+body[strings.Index(body, ";cmd=")+len(";cmd="):])
		case strings.HasPrefix(body, "exit="):
			marks = append(marks, "exit:"+body[len("exit="):])
		}
		text = rest[end+len(blockMarkST):]
	}
	return marks, nil
}

func TestAgentSessionReplayReport(t *testing.T) {
	fixture := os.Getenv("OPERATOR_AGENT_FIXTURE")
	if fixture == "" {
		t.Skip("set OPERATOR_AGENT_FIXTURE to a fixture directory")
	}
	recording, sizes := readAgentFixture(t, fixture)
	p := feedAgentFixture(t, recording, sizes, Limits{Rows: 1000, Bytes: 0xffffffff})
	defer p.Close()
	capped := feedAgentFixture(t, recording, sizes, productMirrorLimits)
	defer capped.Close()
	cappedStats, err := capped.MemoryStats()
	if err != nil {
		t.Fatalf("memory stats at the product cap: %v", err)
	}
	start := time.Now()
	replay, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	elapsed := time.Since(start)

	historyStart := time.Now()
	var historyBytes, historyRows, historyChunks int
	var historyOut []byte
	before := HistoryBefore
	for {
		chunk, next, ok, err := capped.HistoryChunk(before, 1000, HistoryChunkRows)
		if err != nil {
			t.Fatalf("history chunk: %v", err)
		}
		if !ok {
			break
		}
		historyChunks++
		historyBytes += len(chunk)
		historyRows += strings.Count(chunk, "\r\n")
		historyOut = append(historyOut, chunk...)
		before = next
	}
	historyMs := float64(time.Since(historyStart).Microseconds()) / 1000

	reconstructFrame, err := capped.Replay(1000)
	if err != nil {
		t.Fatalf("replay for reconstruction: %v", err)
	}
	reconstructed, err := New(context.Background(), Module, sizes[0].Cols, sizes[0].Rows, productMirrorLimits)
	if err != nil {
		t.Fatalf("new reconstruction parser: %v", err)
	}
	defer reconstructed.Close()
	if err := reconstructed.Feed([]byte(reconstructFrame)); err != nil {
		t.Fatalf("feed reconstruction frame: %v", err)
	}
	if err := reconstructed.Feed(historyOut); err != nil {
		t.Fatalf("feed reconstruction history: %v", err)
	}
	sourceBlocks, err := blockMarks(capped)
	if err != nil {
		t.Fatalf("source block marks: %v", err)
	}
	reconstructedBlocks, err := blockMarks(reconstructed)
	if err != nil {
		t.Fatalf("reconstructed block marks: %v", err)
	}
	sourceKey := strings.Join(sourceBlocks, "|")
	reconstructedKey := strings.Join(reconstructedBlocks, "|")
	if sourceKey != reconstructedKey {
		t.Errorf("reconstructed block list differs from the source mirror's:\nsource (%d):        %v\nreconstructed (%d): %v", len(sourceBlocks), sourceBlocks, len(reconstructedBlocks), reconstructedBlocks)
	} else {
		t.Logf("BLOCKCHECK matched %d blocks between the source mirror and the frame+history reconstruction", len(sourceBlocks))
	}

	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	report := map[string]any{
		"replayBytes":           len(replay),
		"replayRows":            strings.Count(replay, "\r\n") + 1,
		"replayRenderMs":        float64(elapsed.Microseconds()) / 1000,
		"mirrorWasmBytes":       p.module.Memory().Size(),
		"goHeapAllocBytes":      stats.HeapAlloc,
		"mirrorLimitRows":       productMirrorLimits.Rows,
		"mirrorLimitBytes":      productMirrorLimits.Bytes,
		"mirrorCapRows":         cappedStats.Rows,
		"mirrorCapWasmBytes":    capped.module.Memory().Size(),
		"mirrorCapContentBytes": cappedStats.ContentBytes,
		"historyChunks":         historyChunks,
		"historyBytes":          historyBytes,
		"historyRows":           historyRows,
		"historyRenderMs":       historyMs,
	}
	if capped.module.Memory().Size() > productMirrorLimits.Bytes {
		t.Errorf("mirror wasm memory %d bytes exceeds the %d-byte limit at %d rows", capped.module.Memory().Size(), productMirrorLimits.Bytes, cappedStats.Rows)
	}
	if out := os.Getenv("OPERATOR_AGENT_REPLAY_OUT"); out != "" {
		if err := os.WriteFile(out, []byte(replay), 0o600); err != nil {
			t.Fatalf("write replay: %v", err)
		}
		if err := os.WriteFile(out+".history", historyOut, 0o600); err != nil {
			t.Fatalf("write history: %v", err)
		}
	}
	encoded, _ := json.Marshal(report)
	t.Logf("REPORT %s", encoded)
}
