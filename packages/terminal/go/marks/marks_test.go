package marks

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

type vector struct {
	Name   string        `json:"name"`
	Input  string        `json:"input"`
	Events []vectorEvent `json:"events"`
}

type vectorEvent struct {
	Kind          string          `json:"kind"`
	Tier          json.RawMessage `json:"tier"`
	ExitCode      *int            `json:"exitCode"`
	ExitCodeSnake *int            `json:"exit_code"`
	Path          string          `json:"path"`
	Pairs         *[][2]string    `json:"pairs"`
}

func TestEveryVectorDecodesToItsExpectedEvents(t *testing.T) {
	paths, err := filepath.Glob("../../protocol/vectors/*.json")
	if err != nil {
		t.Fatalf("glob vectors: %v", err)
	}
	if len(paths) < 16 {
		t.Fatalf("expected the full vector set, found %d", len(paths))
	}
	for _, path := range paths {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		var v vector
		if err := json.Unmarshal(raw, &v); err != nil {
			t.Fatalf("parse %s: %v", path, err)
		}
		got := NewDecoder().Feed([]byte(v.Input))
		if len(got) != len(v.Events) {
			t.Fatalf("%s: got %d events, want %d", v.Name, len(got), len(v.Events))
		}
		for i, want := range v.Events {
			if got[i].Kind != want.Kind || int(got[i].Tier) != vectorTier(t, want.Kind, want.Tier) {
				t.Errorf("%s event %d: got %+v, want %+v", v.Name, i, got[i], want)
			}
			if (got[i].ExitCode == nil) != (want.exitCode() == nil) {
				t.Errorf("%s event %d: exit code presence differs", v.Name, i)
			}
			if want.Kind == "extension" && want.Pairs != nil && !equalPairs(got[i].Fields, *want.Pairs) {
				t.Errorf("%s event %d: got fields %+v, want pairs %+v", v.Name, i, got[i].Fields, want.Pairs)
			}
		}
	}
}

func equalPairs(fields map[string]string, pairs [][2]string) bool {
	if len(fields) != len(pairs) {
		return false
	}
	for _, pair := range pairs {
		if fields[pair[0]] != pair[1] {
			return false
		}
	}
	return true
}

func (e vectorEvent) exitCode() *int {
	if e.ExitCodeSnake != nil {
		return e.ExitCodeSnake
	}
	return e.ExitCode
}

func vectorTier(t *testing.T, kind string, raw json.RawMessage) int {
	t.Helper()
	if len(raw) == 0 {
		if kind == "extension" {
			return int(TierExtension)
		}
		return 0
	}
	var numeric int
	if err := json.Unmarshal(raw, &numeric); err == nil {
		return numeric
	}
	var named string
	if err := json.Unmarshal(raw, &named); err != nil {
		t.Fatalf("parse vector tier %q: %v", raw, err)
	}
	if named == "osc133" {
		return int(TierOSC133)
	}
	t.Fatalf("unknown vector tier %q", named)
	return 0
}

func TestMarkSplitAcrossFeedsStillDecodes(t *testing.T) {
	d := NewDecoder()
	if events := d.Feed([]byte("\x1b]133;")); len(events) != 0 {
		t.Fatalf("partial mark produced %d events", len(events))
	}
	events := d.Feed([]byte("A\x07"))
	if len(events) != 1 || events[0].Kind != "prompt_start" {
		t.Fatalf("got %+v", events)
	}
}

func TestUnterminatedOSCIsBounded(t *testing.T) {
	d := NewDecoder()
	d.Feed([]byte("\x1b]133;"))
	d.Feed(make([]byte, 256*1024))
	events := d.Feed([]byte("\x1b]133;A\x07"))
	if len(events) != 1 {
		t.Fatalf("decoder did not recover: %+v", events)
	}
}

func streamAll(d *StreamDecoder, chunks ...[]byte) []Token {
	var all []Token
	for _, c := range chunks {
		all = append(all, d.Feed(c)...)
	}
	all = append(all, d.Flush()...)
	return all
}

func joinRaw(tokens []Token) []byte {
	parts := make([][]byte, len(tokens))
	for i, tok := range tokens {
		parts[i] = tok.Raw
	}
	return bytes.Join(parts, nil)
}

func assertRoundTrip(t *testing.T, want []byte, chunks ...[]byte) []Token {
	t.Helper()
	tokens := streamAll(NewStreamDecoder(), chunks...)
	if got := joinRaw(tokens); !bytes.Equal(got, want) {
		t.Fatalf("round-trip mismatch:\n got %q\nwant %q", got, want)
	}
	return tokens
}

func TestStreamDecoderRoundTripsPlainUTF8(t *testing.T) {
	in := []byte("hello, world\nこんにちは 🌍\n")
	assertRoundTrip(t, in, in)
}

func TestStreamDecoderRoundTripsArbitraryBytes(t *testing.T) {
	in := make([]byte, 512)
	for i := range in {
		in[i] = byte((i * 7) % 256)
	}
	assertRoundTrip(t, in, in[:200], in[200:201], in[201:])
}

func TestStreamDecoderRoundTripsSplitOSC(t *testing.T) {
	a := []byte("before\x1b]133;")
	b := []byte("A\x07after")
	tokens := assertRoundTrip(t, append(append([]byte{}, a...), b...), a, b)
	var marks int
	for _, tok := range tokens {
		if tok.Kind == TokenMark {
			marks++
			if tok.Mark.Kind != "prompt_start" {
				t.Fatalf("got mark %+v", tok.Mark)
			}
			if !bytes.Equal(tok.Raw, []byte("\x1b]133;A\x07")) {
				t.Fatalf("mark raw = %q", tok.Raw)
			}
		}
	}
	if marks != 1 {
		t.Fatalf("want 1 mark token, got %d", marks)
	}
}

func TestStreamDecoderRoundTripsMalformedOSC(t *testing.T) {
	in := []byte("start\x1b]133after\x1b]133;A\x07done")
	tokens := assertRoundTrip(t, in, in)
	var kinds []string
	for _, tok := range tokens {
		if tok.Kind == TokenMark {
			kinds = append(kinds, tok.Mark.Kind)
		}
	}
	if len(kinds) != 1 || kinds[0] != "prompt_start" {
		t.Fatalf("malformed OSC should yield exactly the trailing prompt_start, got %v", kinds)
	}
}

func TestStreamDecoderRoundTripsSGR(t *testing.T) {
	in := []byte("plain\x1b[1;31mred\x1b[0mplain again")
	assertRoundTrip(t, in, in)
}

func TestStreamDecoderRoundTripsAltScreen(t *testing.T) {
	in := []byte("\x1b[?1049hin alt screen\x1b[?1049lback")
	tokens := assertRoundTrip(t, in, in)
	var seen []string
	for _, tok := range tokens {
		if tok.Kind == TokenMark {
			seen = append(seen, tok.Mark.Kind)
		}
	}
	if len(seen) != 2 || seen[0] != "alt_screen_enter" || seen[1] != "alt_screen_leave" {
		t.Fatalf("alt-screen marks = %v", seen)
	}
}

func TestStreamDecoderResetAtRecoversWithoutPreGapBytes(t *testing.T) {
	d := NewStreamDecoder()
	if tokens := d.Feed([]byte("\x1b]133;A")); len(tokens) != 0 {
		t.Fatalf("mid-OSC feed produced %d tokens", len(tokens))
	}
	d.ResetAt(1000)

	var tokens []Token
	tokens = append(tokens, d.Feed([]byte("noise\xff\xfe"))...)
	tokens = append(tokens, d.Feed([]byte("\x1b]133;A\x07\x1b]133;C\x07\x1b]133;D;0\x07"))...)

	for _, tok := range tokens {
		if bytes.Contains(tok.Raw, []byte("133;A")) && tok.Kind != TokenMark {
			t.Fatalf("pre-gap bytes leaked into %+v", tok)
		}
		if tok.Start < 1000 {
			t.Fatalf("token %+v has offset before the gap", tok)
		}
	}

	if tokens[0].Kind != TokenText || tokens[0].Start != 1000 || tokens[0].End != 1000+int64(len("noise\xff\xfe")) {
		t.Fatalf("noise token = %+v", tokens[0])
	}

	var marks []string
	var firstMarkStart int64 = -1
	for _, tok := range tokens {
		if tok.Kind == TokenMark {
			if firstMarkStart < 0 {
				firstMarkStart = tok.Start
			}
			marks = append(marks, tok.Mark.Kind)
		}
	}
	wantStart := int64(1000 + len("noise\xff\xfe"))
	if firstMarkStart != wantStart {
		t.Fatalf("first post-gap mark starts at %d, want %d", firstMarkStart, wantStart)
	}
	if len(marks) != 3 || marks[0] != "prompt_start" || marks[1] != "output_start" || marks[2] != "command_end" {
		t.Fatalf("post-gap marks = %v", marks)
	}
}

func TestStreamDecoderFlushAfterOrdinaryOutput(t *testing.T) {
	in := []byte("just some output\n")
	d := NewStreamDecoder()
	tokens := d.Feed(in)
	flush := d.Flush()
	if len(flush) != 0 {
		t.Fatalf("flush after ordinary output emitted %+v", flush)
	}
	if got := joinRaw(append(tokens, flush...)); !bytes.Equal(got, in) {
		t.Fatalf("round-trip mismatch: got %q want %q", got, in)
	}
}

func TestStreamDecoderFlushInsideIncompleteEscape(t *testing.T) {
	d := NewStreamDecoder()
	tokens := d.Feed([]byte("hello\x1b]133;"))
	flush := d.Flush()
	all := append(tokens, flush...)
	if got := joinRaw(all); !bytes.Equal(got, []byte("hello\x1b]133;")) {
		t.Fatalf("round-trip mismatch: got %q", got)
	}
	last := all[len(all)-1]
	if last.Kind != TokenIncomplete || !bytes.Equal(last.Raw, []byte("\x1b]133;")) {
		t.Fatalf("incomplete token = %+v", last)
	}
}
