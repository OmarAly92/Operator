package vtwasm

import (
	"context"
	"fmt"
	"strings"
	"testing"
)

func newRingParser(t *testing.T, cols, rows, keep, ring uint32) *Parser {
	t.Helper()
	p, err := New(context.Background(), Module, cols, rows, Limits{Rows: keep, Bytes: 0xffffffff, ColdRingBytes: ring})
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	t.Cleanup(func() { _ = p.Close() })
	return p
}

func feedRows(t *testing.T, p *Parser, from, to int) {
	t.Helper()
	var b strings.Builder
	for i := from; i < to; i++ {
		fmt.Fprintf(&b, "row %06d\r\n", i)
		if b.Len() > 32<<10 {
			feed(t, p, b.String())
			b.Reset()
		}
	}
	feed(t, p, b.String())
}

func TestEvictedRowsReachTheColdRingAndComeBackAsAChunk(t *testing.T) {
	p := newRingParser(t, 40, 3, 50, 1<<20)
	feedRows(t, p, 0, 200)
	stats, err := p.ColdStats()
	if err != nil {
		t.Fatalf("cold stats: %v", err)
	}
	if stats.FirstStableRow != 0 || stats.Rows == 0 || stats.Cap != 1<<20 {
		t.Fatalf("cold stats = %+v", stats)
	}
	mark, err := p.OlderMark()
	if err != nil || mark != "\x1b]7000;v=1;older=0\x1b\\" {
		t.Fatalf("older mark = %q, %v", mark, err)
	}
	front := stats.FirstStableRow + uint64(stats.Rows)
	chunk, next, ok, err := p.OlderChunk(front, HistoryChunkRows)
	if err != nil || !ok {
		t.Fatalf("older chunk: ok=%v err=%v", ok, err)
	}
	if next != 0 {
		t.Fatalf("next = %d, want 0", next)
	}
	want := fmt.Sprintf("\x1b]7000;v=1;history=0,%d;cols=10\x1b\\", stats.Rows)
	if !strings.HasPrefix(chunk, want) {
		t.Fatalf("chunk starts %q, want %q", chunk[:min(len(chunk), 60)], want)
	}
	if !strings.Contains(chunk, "row 000000") || strings.Index(chunk, "row 000000") > strings.Index(chunk, "row 000001") {
		t.Fatalf("rows missing or out of order: %q", chunk[:min(len(chunk), 200)])
	}
	if _, _, ok, err := p.OlderChunk(0, HistoryChunkRows); ok || err != nil {
		t.Fatalf("a chunk below the floor: ok=%v err=%v", ok, err)
	}
}

func TestAParserWithoutARingOffersNothingOlder(t *testing.T) {
	p := newTestParser(t, 40, 3)
	feedRows(t, p, 0, 2000)
	mark, err := p.OlderMark()
	if err != nil || mark != "" {
		t.Fatalf("older mark = %q, %v", mark, err)
	}
	stats, err := p.ColdStats()
	if err != nil || stats.Rows != 0 || stats.Cap != 0 {
		t.Fatalf("cold stats = %+v, %v", stats, err)
	}
}

func TestTheColdRingNeverPassesItsCap(t *testing.T) {
	const ring = 64 << 10
	p := newRingParser(t, 40, 3, 100, ring)
	for batch := 0; batch < 40; batch++ {
		feedRows(t, p, batch*500, (batch+1)*500)
		stats, err := p.ColdStats()
		if err != nil {
			t.Fatalf("cold stats: %v", err)
		}
		if stats.Bytes > ring {
			t.Fatalf("ring holds %d bytes past its %d cap", stats.Bytes, ring)
		}
	}
	stats, _ := p.ColdStats()
	if stats.FirstStableRow == 0 {
		t.Fatalf("the oldest rows were never dropped: %+v", stats)
	}
}
