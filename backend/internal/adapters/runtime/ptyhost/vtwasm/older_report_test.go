package vtwasm

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"
)

const reportColdRingBytes = 32 << 20

func syntheticRows(from, to int) []byte {
	var b strings.Builder
	for i := from; i < to; i++ {
		if i%5 == 0 {
			fmt.Fprintf(&b, "\x1b[32mrow %06d\x1b[0m lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore\r\n", i)
		} else {
			fmt.Fprintf(&b, "row %06d lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore\r\n", i)
		}
	}
	return []byte(b.String())
}

func feedTimed(t *testing.T, p *Parser, payload []byte) time.Duration {
	t.Helper()
	start := time.Now()
	for offset := 0; offset < len(payload); offset += 64 << 10 {
		end := min(offset+64<<10, len(payload))
		if err := p.Feed(payload[offset:end]); err != nil {
			t.Fatalf("feed: %v", err)
		}
	}
	return time.Since(start)
}

func timeOneClick(t *testing.T, p *Parser, before uint64) (elapsed time.Duration, rows, bytes int) {
	t.Helper()
	start := time.Now()
	chunk, next, ok, err := p.OlderChunk(before, OlderChunkRows)
	if err != nil {
		t.Fatalf("older chunk: %v", err)
	}
	mark, err := p.OlderMark()
	if err != nil {
		t.Fatalf("older mark: %v", err)
	}
	elapsed = time.Since(start)
	if !ok {
		return elapsed, 0, 0
	}
	if out := os.Getenv("OPERATOR_OLDER_ANSWER_OUT"); out != "" {
		if _, statErr := os.Stat(out); statErr != nil {
			if err := os.WriteFile(out, []byte(chunk+mark), 0o600); err != nil {
				t.Fatalf("write answer: %v", err)
			}
		}
	}
	return elapsed, int(before - next), len(chunk)
}

func TestOlderOutputReport(t *testing.T) {
	if os.Getenv("OPERATOR_OLDER_REPORT") == "" {
		t.Skip("set OPERATOR_OLDER_REPORT=1 to measure the cold ring")
	}
	limits := productMirrorLimits
	limits.ColdRingBytes = reportColdRingBytes
	payload := syntheticRows(0, 520_000)

	withRing, err := New(context.Background(), Module, 120, 40, limits)
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	defer withRing.Close()
	ringFeed := feedTimed(t, withRing, payload)

	withoutRing, err := New(context.Background(), Module, 120, 40, productMirrorLimits)
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	defer withoutRing.Close()
	plainFeed := feedTimed(t, withoutRing, payload)

	cold, err := withRing.ColdStats()
	if err != nil {
		t.Fatalf("cold stats: %v", err)
	}
	stats, err := withRing.MemoryStats()
	if err != nil {
		t.Fatalf("memory stats: %v", err)
	}
	if cold.Bytes > reportColdRingBytes {
		t.Errorf("ring holds %d bytes past its %d cap", cold.Bytes, reportColdRingBytes)
	}
	if cold.FirstStableRow == 0 {
		t.Errorf("the ring never filled: %+v", cold)
	}
	front := cold.FirstStableRow + uint64(cold.Rows)
	clickRing, clickRows, clickBytes := timeOneClick(t, withRing, front)
	clickDeep, _, _ := timeOneClick(t, withRing, cold.FirstStableRow+OlderChunkRows)

	report := map[string]any{
		"feedMB":               float64(len(payload)) / (1 << 20),
		"feedMsWithRing":       ringFeed.Milliseconds(),
		"feedMsWithoutRing":    plainFeed.Milliseconds(),
		"wasmBytesWithRing":    withRing.module.Memory().Size(),
		"wasmBytesWithoutRing": withoutRing.module.Memory().Size(),
		"coreRows":             stats.Rows,
		"coreContentBytes":     stats.ContentBytes,
		"ringRows":             cold.Rows,
		"ringBytes":            cold.Bytes,
		"ringFirstStableRow":   cold.FirstStableRow,
		"clickRows":            clickRows,
		"clickBytes":           clickBytes,
		"clickMsNewestRing":    float64(clickRing.Microseconds()) / 1000,
		"clickMsOldestRing":    float64(clickDeep.Microseconds()) / 1000,
	}

	if fixture := os.Getenv("OPERATOR_AGENT_FIXTURE"); fixture != "" {
		recording, sizes := readAgentFixture(t, fixture)
		spill := Limits{Rows: 10_000, Bytes: 128 << 20, ColdRingBytes: reportColdRingBytes}
		p := feedAgentFixture(t, recording, sizes, spill)
		defer p.Close()
		fixtureCold, err := p.ColdStats()
		if err != nil {
			t.Fatalf("fixture cold stats: %v", err)
		}
		click, rows, bytes := timeOneClick(t, p, fixtureCold.FirstStableRow+uint64(fixtureCold.Rows))
		capped := feedAgentFixture(t, recording, sizes, limits)
		defer capped.Close()
		cappedStats, err := capped.MemoryStats()
		if err != nil {
			t.Fatalf("fixture memory stats: %v", err)
		}
		cappedCold, _ := capped.ColdStats()
		ahead, aheadRows, _ := timeOneClick(t, capped, cappedCold.FirstStableRow+uint64(cappedStats.Rows))
		report["fixtureRingRows"] = fixtureCold.Rows
		report["fixtureRingBytes"] = fixtureCold.Bytes
		report["fixtureClickRows"] = rows
		report["fixtureClickBytes"] = bytes
		report["fixtureClickMsRing"] = float64(click.Microseconds()) / 1000
		report["fixtureHistoryRows"] = cappedStats.Rows
		report["fixtureClickRowsFromHistory"] = aheadRows
		report["fixtureClickMsFromHistory"] = float64(ahead.Microseconds()) / 1000
	}
	encoded, _ := json.Marshal(report)
	t.Logf("OLDER-REPORT %s", encoded)
}
