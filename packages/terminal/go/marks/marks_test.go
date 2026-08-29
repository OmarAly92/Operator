package marks

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

type vector struct {
	Name   string `json:"name"`
	Input  string `json:"input"`
	Events []struct {
		Kind     string `json:"kind"`
		Tier     int    `json:"tier"`
		ExitCode *int   `json:"exitCode"`
		Path     string `json:"path"`
	} `json:"events"`
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
			if got[i].Kind != want.Kind || int(got[i].Tier) != want.Tier {
				t.Errorf("%s event %d: got %+v, want %+v", v.Name, i, got[i], want)
			}
			if (got[i].ExitCode == nil) != (want.ExitCode == nil) {
				t.Errorf("%s event %d: exit code presence differs", v.Name, i)
			}
		}
	}
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
