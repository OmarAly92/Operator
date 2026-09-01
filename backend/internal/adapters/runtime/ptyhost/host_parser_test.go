package ptyhost

import (
	"context"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

func TestParserRendersCursorAddressedOutput(t *testing.T) {
	parser, err := vtwasm.New(context.Background(), vtwasm.Module, 80, 24, 100)
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	defer func() { _ = parser.Close() }()

	// Write "AAAA", then jump home and overwrite with "B". A raw byte ring
	// returns both; a real screen returns "BAAA". This is the exact difference
	// between a real screen grid and the old conpty ring.
	if err := parser.Feed([]byte("AAAA\x1b[1;1HB")); err != nil {
		t.Fatalf("feed: %v", err)
	}
	text, err := parser.RenderTail(5)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if !strings.Contains(text, "BAAA") {
		t.Fatalf("RenderTail = %q, want it to contain \"BAAA\"", text)
	}
	if strings.Contains(text, "\x1b[") {
		t.Fatalf("RenderTail = %q, want no escape sequences", text)
	}
}

func TestParserResizeMirrorsPTYGrid(t *testing.T) {
	parser, err := vtwasm.New(context.Background(), vtwasm.Module, 80, 24, 100)
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	defer func() { _ = parser.Close() }()

	if err := parser.Resize(100, 40); err != nil {
		t.Fatalf("resize: %v", err)
	}

	var frame strings.Builder
	for row := 0; row < 40; row++ {
		frame.WriteString(strings.Repeat("x", 100))
		if row < 39 {
			frame.WriteString("\r\n")
		}
	}
	if err := parser.Feed([]byte(frame.String())); err != nil {
		t.Fatalf("feed: %v", err)
	}

	text, err := parser.RenderTail(100)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	rows := strings.Split(strings.TrimRight(text, "\n"), "\n")
	if len(rows) != 40 {
		t.Fatalf("RenderTail returned %d rows, want 40 (text=%q)", len(rows), text)
	}
}
