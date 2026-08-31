package terminal

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/packages/terminal/go/marks"
)

func readVector(t *testing.T, name string) string {
	t.Helper()
	for _, p := range []string{
		filepath.Join("..", "..", "..", "packages", "terminal", "protocol", "vectors", name),
		filepath.Join("..", "..", "packages", "terminal", "protocol", "vectors", name),
	} {
		raw, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		var v struct {
			Input string `json:"input"`
		}
		if err := json.Unmarshal(raw, &v); err != nil {
			t.Fatalf("parse %s: %v", p, err)
		}
		return v.Input
	}
	t.Fatalf("vector %s not found", name)
	return ""
}

func fixedClock() func() time.Time {
	ts := time.Date(2026, 8, 31, 12, 0, 0, 0, time.UTC)
	return func() time.Time { return ts }
}

func assembleChunks(a *BlockAssembler, dec *marks.StreamDecoder, chunks ...string) []domain.Block {
	var out []domain.Block
	for _, c := range chunks {
		out = append(out, a.Consume(dec.Feed([]byte(c)))...)
	}
	return out
}

func splitEvery(s string, n int) []string {
	var out []string
	for len(s) > n {
		out = append(out, s[:n])
		s = s[n:]
	}
	if s != "" {
		out = append(out, s)
	}
	return out
}

func newAssembler(alt bool) (*BlockAssembler, *marks.StreamDecoder) {
	return NewBlockAssembler("term-1", "sess-1", "epoch-1", alt, fixedClock()), marks.NewStreamDecoder()
}

func TestAssemblerExtensionFullBlock(t *testing.T) {
	a, dec := newAssembler(false)
	blocks := assembleChunks(a, dec, readVector(t, "extension-full-block.json"))
	if len(blocks) != 1 {
		t.Fatalf("got %d blocks, want 1", len(blocks))
	}
	b := blocks[0]
	if b.TerminalID != "term-1" || b.SessionID != "sess-1" {
		t.Fatalf("ids = %q/%q", b.TerminalID, b.SessionID)
	}
	if b.Command != "ls -la" {
		t.Fatalf("command = %q", b.Command)
	}
	if b.Cwd != "/home/user" {
		t.Fatalf("cwd = %q", b.Cwd)
	}
	if b.GitBranch != "main" {
		t.Fatalf("branch = %q", b.GitBranch)
	}
	if b.SourceID != "block-001" {
		t.Fatalf("source id = %q, want verbatim block-001", b.SourceID)
	}
	if b.ExitCode == nil || *b.ExitCode != 0 {
		t.Fatalf("exit = %v", b.ExitCode)
	}
	if b.CaptureEpoch != "epoch-1" {
		t.Fatalf("epoch = %q", b.CaptureEpoch)
	}
	if b.StartOffset != 0 {
		t.Fatalf("start offset = %d, want 0", b.StartOffset)
	}
	if b.EndOffset != int64(len(readVector(t, "extension-full-block.json"))) {
		t.Fatalf("end offset = %d, want %d", b.EndOffset, len(readVector(t, "extension-full-block.json")))
	}
	if want := time.UnixMilli(1700000000123).UTC(); !b.FinishedAt.Equal(want) {
		t.Fatalf("finished = %v, want end_ms %v", b.FinishedAt, want)
	}
}

func TestAssemblerMarkSplitAcrossFeeds(t *testing.T) {
	in := readVector(t, "extension-full-block.json")
	a, dec := newAssembler(false)
	blocks := assembleChunks(a, dec, splitEvery(in, 1)...)
	if len(blocks) != 1 || blocks[0].Command != "ls -la" {
		t.Fatalf("byte-split feed: got %+v", blocks)
	}
}

func TestAssemblerTier1HappyPathDerivesID(t *testing.T) {
	in := readVector(t, "osc133-happy-path.json")
	a, dec := newAssembler(false)
	blocks := assembleChunks(a, dec, in)
	if len(blocks) != 1 {
		t.Fatalf("got %d blocks", len(blocks))
	}
	if blocks[0].SourceID != "osc133-epoch-1-0" {
		t.Fatalf("tier1 source id = %q, want osc133-epoch-1-0", blocks[0].SourceID)
	}
	if blocks[0].ExitCode == nil || *blocks[0].ExitCode != 0 {
		t.Fatalf("exit = %v", blocks[0].ExitCode)
	}
}

func TestAssemblerTier1IDUsesAStartOffset(t *testing.T) {
	pre := "leftover output before the prompt\n"
	in := pre + readVector(t, "osc133-happy-path.json")
	a, dec := newAssembler(false)
	blocks := assembleChunks(a, dec, in)
	if len(blocks) != 1 {
		t.Fatalf("got %d blocks", len(blocks))
	}
	want := "osc133-epoch-1-" + strconv.Itoa(len(pre))
	if blocks[0].SourceID != want {
		t.Fatalf("source id = %q, want %q", blocks[0].SourceID, want)
	}
	if blocks[0].StartOffset != int64(len(pre)) {
		t.Fatalf("start offset = %d, want %d", blocks[0].StartOffset, len(pre))
	}
}

func TestAssemblerRawOutputRoundTrips(t *testing.T) {
	in := readVector(t, "extension-full-block.json")
	a, dec := newAssembler(false)
	blocks := assembleChunks(a, dec, in)
	if len(blocks) != 1 {
		t.Fatalf("got %d blocks", len(blocks))
	}
	raw := blocks[0].RawOutput
	if !bytes.Equal(raw, []byte(in)) {
		t.Fatalf("raw_output is not the verbatim stream:\n got %q\nwant %q", raw, in)
	}

	fresh := marks.NewStreamDecoder()
	var kinds []string
	var rejoined []byte
	toks := append(fresh.Feed(raw), fresh.Flush()...)
	for _, tk := range toks {
		rejoined = append(rejoined, tk.Raw...)
		if tk.Kind == marks.TokenMark {
			kinds = append(kinds, tk.Mark.Kind)
		}
		if tk.Kind == marks.TokenIncomplete {
			t.Fatalf("re-decoding raw_output left an incomplete tail: %q", tk.Raw)
		}
	}
	if !bytes.Equal(rejoined, raw) {
		t.Fatalf("re-decode round-trip mismatch")
	}
	if strings.Join(kinds, ",") != "prompt_start,command_start,output_start,extension,command_end" {
		t.Fatalf("re-decoded marks = %v", kinds)
	}
}

func TestAssemblerAltScreenWrappingWholeBlockIsSuppressed(t *testing.T) {
	in := readVector(t, "extension-full-block.json")
	a, dec := newAssembler(false)
	blocks := assembleChunks(a, dec, "\x1b[?1049h"+in+"\x1b[?1049l")
	if len(blocks) != 0 {
		t.Fatalf("alt-screen wrapped block should emit nothing, got %d", len(blocks))
	}
	blocks = assembleChunks(a, dec, in)
	if len(blocks) != 1 || blocks[0].Command != "ls -la" {
		t.Fatalf("after leave: %+v", blocks)
	}
}

func TestAssemblerInitialAlternateOnDropsRepaintBeforeFirstPrompt(t *testing.T) {
	a, dec := newAssembler(true)
	repaint := "\x1b[2J\x1b[Hhtop repaint frame with cpu bars"
	blocks := assembleChunks(a, dec, repaint+"\x1b[?1049l"+readVector(t, "extension-full-block.json"))
	if len(blocks) != 1 {
		t.Fatalf("got %d blocks, want 1", len(blocks))
	}
	if bytes.Contains(blocks[0].RawOutput, []byte("htop repaint")) {
		t.Fatalf("repaint bytes leaked into raw_output: %q", blocks[0].RawOutput)
	}
	if !bytes.HasPrefix(blocks[0].RawOutput, []byte("\x1b]133;A")) {
		t.Fatalf("raw_output should start at the first mark, got %q", blocks[0].RawOutput[:8])
	}
}

func TestAssemblerAltEnterLeaveSplitAcrossChunks(t *testing.T) {
	in := readVector(t, "extension-full-block.json")
	a, dec := newAssembler(false)
	chunks := append([]string{}, splitEvery("\x1b[?1049h", 1)...)
	chunks = append(chunks, splitEvery(in, 3)...)
	chunks = append(chunks, splitEvery("\x1b[?1049l", 1)...)
	blocks := assembleChunks(a, dec, chunks...)
	if len(blocks) != 0 {
		t.Fatalf("split alt enter/leave still suppressed: got %d blocks", len(blocks))
	}
	if a.AlternateOn {
		t.Fatalf("alt-screen should be off after a split leave")
	}
}

func TestAssemblerInFlightCompletionExcludesRepaint(t *testing.T) {
	in := readVector(t, "extension-full-block.json")
	commandEnd := "\x1b]133;D;0\x07"
	prefix := strings.TrimSuffix(in, commandEnd)
	repaint := "\x1b[?1049hVIM SWAP FILE REDRAW PAYLOAD\x1b[?1049l"

	a, dec := newAssembler(false)
	blocks := assembleChunks(a, dec, prefix+repaint+commandEnd)
	if len(blocks) != 1 {
		t.Fatalf("in-flight block must finalize on D, got %d", len(blocks))
	}
	b := blocks[0]
	if b.ExitCode == nil || *b.ExitCode != 0 {
		t.Fatalf("exit = %v", b.ExitCode)
	}
	if bytes.Contains(b.RawOutput, []byte("REDRAW PAYLOAD")) {
		t.Fatalf("repaint payload leaked: %q", b.RawOutput)
	}
	if !bytes.HasSuffix(b.RawOutput, []byte(commandEnd)) {
		t.Fatalf("raw_output must end with the closing D mark: %q", b.RawOutput)
	}
	fresh := marks.NewStreamDecoder()
	toks := append(fresh.Feed(b.RawOutput), fresh.Flush()...)
	last := toks[len(toks)-1]
	if last.Kind != marks.TokenMark || last.Mark.Kind != "command_end" {
		t.Fatalf("re-decoded raw_output does not end on command_end: %+v", last)
	}
}

func TestAssemblerGapDiscardsPartialAndRecovers(t *testing.T) {
	a, dec := newAssembler(false)
	partial := "\x1b]133;A\x07\x1b]133;C\x07half-written output that will be lost"
	if blocks := assembleChunks(a, dec, partial); len(blocks) != 0 {
		t.Fatalf("partial block emitted %d", len(blocks))
	}

	a.Gap()
	retained := int64(4096)
	dec.ResetAt(retained)

	clean := "noise\xff after the gap" + readVector(t, "osc133-happy-path.json")
	blocks := assembleChunks(a, dec, clean)
	if len(blocks) != 1 {
		t.Fatalf("post-gap: got %d blocks, want 1", len(blocks))
	}
	if bytes.Contains(blocks[0].RawOutput, []byte("half-written")) {
		t.Fatalf("pre-gap bytes spliced into post-gap block: %q", blocks[0].RawOutput)
	}
	if bytes.Contains(blocks[0].RawOutput, []byte("noise")) {
		t.Fatalf("pre-prompt noise leaked into raw_output: %q", blocks[0].RawOutput)
	}
	if blocks[0].StartOffset < retained {
		t.Fatalf("post-gap block start offset %d is before the retained cursor %d", blocks[0].StartOffset, retained)
	}
	wantID := "osc133-epoch-1-" + strconv.Itoa(int(retained)+len("noise\xff after the gap"))
	if blocks[0].SourceID != wantID {
		t.Fatalf("post-gap source id = %q, want %q", blocks[0].SourceID, wantID)
	}
}

func TestAssemblerReplayFromOldCursorYieldsIdenticalSourceID(t *testing.T) {
	in := readVector(t, "osc133-happy-path.json")

	a1, d1 := newAssembler(false)
	first := assembleChunks(a1, d1, in)

	a2 := NewBlockAssembler("term-1", "sess-1", "epoch-1", false, fixedClock())
	d2 := marks.NewStreamDecoder()
	d2.ResetAt(0)
	second := assembleChunks(a2, d2, in)

	if len(first) != 1 || len(second) != 1 {
		t.Fatalf("run counts = %d / %d", len(first), len(second))
	}
	if first[0].SourceID != second[0].SourceID {
		t.Fatalf("replay produced a different SourceID: %q vs %q", first[0].SourceID, second[0].SourceID)
	}
	if first[0].StartOffset != second[0].StartOffset || first[0].EndOffset != second[0].EndOffset {
		t.Fatalf("replay offsets diverged")
	}
}

func TestAssemblerFinishPersistsInFlightOnlyWhenFinal(t *testing.T) {
	mk := func() (*BlockAssembler, *marks.StreamDecoder) { return newAssembler(false) }

	a, dec := mk()
	assembleChunks(a, dec, "\x1b]133;A\x07\x1b]133;C\x07running, no exit yet")
	if got := a.Finish(false); got != nil {
		t.Fatalf("Finish(false) must not persist an in-flight command, got %+v", got)
	}

	a, dec = mk()
	assembleChunks(a, dec, "\x1b]133;A\x07\x1b]133;C\x07running, no exit yet")
	got := a.Finish(true)
	if len(got) != 1 {
		t.Fatalf("Finish(true) should persist the in-flight command, got %d", len(got))
	}
	if got[0].ExitCode != nil {
		t.Fatalf("forced-close block must have a nil exit code, got %v", *got[0].ExitCode)
	}
	if got[0].FinishedAt.IsZero() {
		t.Fatalf("forced-close block must carry a finished timestamp")
	}
	if !bytes.Contains(got[0].RawOutput, []byte("running, no exit yet")) {
		t.Fatalf("raw_output = %q", got[0].RawOutput)
	}
}

func TestAssemblerUnmatchedAltLeaveIsHarmless(t *testing.T) {
	in := readVector(t, "extension-full-block.json")
	a, dec := newAssembler(false)
	blocks := assembleChunks(a, dec, "\x1b[?1049l"+in)
	if len(blocks) != 1 {
		t.Fatalf("unmatched leave must not suppress the block, got %d", len(blocks))
	}
}

func TestAssemblerSecondPromptDiscardsUnfinishedFirst(t *testing.T) {
	a, dec := newAssembler(false)
	stream := "\x1b]133;A\x07\x1b]133;C\x07first never ends" +
		readVector(t, "osc133-happy-path.json")
	blocks := assembleChunks(a, dec, stream)
	if len(blocks) != 1 {
		t.Fatalf("got %d blocks, want 1 (first prompt abandoned)", len(blocks))
	}
	if bytes.Contains(blocks[0].RawOutput, []byte("first never ends")) {
		t.Fatalf("abandoned block bytes leaked: %q", blocks[0].RawOutput)
	}
}
