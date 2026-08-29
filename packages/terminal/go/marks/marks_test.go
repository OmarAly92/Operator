package marks

import (
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
