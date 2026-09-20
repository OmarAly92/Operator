package vtwasm

import (
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
