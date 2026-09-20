package vtwasm

import (
	"context"
	"fmt"
	"strings"
	"testing"
)

const (
	bsu = "\x1b[?2026h"
	esu = "\x1b[?2026l"
)

func TestFeedAtBuffersASyncBlockUntilItsTerminator(t *testing.T) {
	p := newTestParser(t, 80, 24)
	if err := p.FeedAt([]byte(bsu+"hidden"), 1000); err != nil {
		t.Fatalf("feed: %v", err)
	}
	in, err := p.InSync()
	if err != nil || !in {
		t.Fatalf("InSync = %v, %v; want true", in, err)
	}
	text, _ := p.RenderTail(5)
	if strings.Contains(text, "hidden") {
		t.Fatalf("render shows buffered bytes: %q", text)
	}
	if err := p.FeedAt([]byte(esu), 1001); err != nil {
		t.Fatalf("feed: %v", err)
	}
	text, _ = p.RenderTail(5)
	if !strings.Contains(text, "hidden") {
		t.Fatalf("render after ESU = %q", text)
	}
}

func TestTickPastTheDeadlineFlushesTheSyncBlock(t *testing.T) {
	p := newTestParser(t, 80, 24)
	if err := p.FeedAt([]byte(bsu+"late"), 0); err != nil {
		t.Fatalf("feed: %v", err)
	}
	if flushed, err := p.Tick(149); err != nil || flushed {
		t.Fatalf("Tick(149) = %v, %v", flushed, err)
	}
	if flushed, err := p.Tick(150); err != nil || !flushed {
		t.Fatalf("Tick(150) = %v, %v", flushed, err)
	}
	text, _ := p.RenderTail(5)
	if !strings.Contains(text, "late") {
		t.Fatalf("render after tick = %q", text)
	}
}

func TestNewAcceptsByteLimit(t *testing.T) {
	p, err := New(context.Background(), Module, 40, 3, Limits{Rows: 100000, Bytes: 8192})
	if err != nil {
		t.Fatalf("new: %v", err)
	}
	t.Cleanup(func() { _ = p.Close() })
	for i := 0; i < 600; i++ {
		if err := p.Feed([]byte(fmt.Sprintf("row %05d xxxxxxxxxx\r\n", i))); err != nil {
			t.Fatalf("feed: %v", err)
		}
	}
	stats, err := p.MemoryStats()
	if err != nil {
		t.Fatalf("memory stats: %v", err)
	}
	if stats.ContentBytes+stats.StyleEntries*16 > 8192 {
		t.Fatalf("byte cap not enforced: %+v", stats)
	}
	if stats.Rows < 100 || stats.Rows >= 600 {
		t.Fatalf("rows outside the trimmed range: %+v", stats)
	}
	text, err := p.RenderTail(1)
	if err != nil || !strings.Contains(text, "row 00599") {
		t.Fatalf("newest row missing after trim: %q, %v", text, err)
	}
}
