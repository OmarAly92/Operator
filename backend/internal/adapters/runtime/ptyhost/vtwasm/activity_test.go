package vtwasm

import (
	"testing"
	"time"
)

func TestTheMirrorClassifiesQuietAndQuestions(t *testing.T) {
	p := newTestParser(t, 80, 24)
	before, err := p.LiveOutputBytes()
	if err != nil {
		t.Fatalf("live bytes: %v", err)
	}
	feed(t, p, "Overwrite greet.py? (y/n) ")
	after, _ := p.LiveOutputBytes()
	if after <= before {
		t.Fatalf("live bytes did not move: %d -> %d", before, after)
	}
	for _, tc := range []struct {
		quiet int64
		want  AgentActivity
	}{{0, ActivityActive}, {499, ActivityActive}, {500, ActivityPrompting}, {-1, ActivityPrompting}} {
		got, err := p.AgentActivity(tc.quiet)
		if err != nil || got != tc.want {
			t.Fatalf("AgentActivity(%d) = %v, %v; want %v", tc.quiet, got, err, tc.want)
		}
	}
	line, err := p.CursorLine()
	if err != nil || line != "Overwrite greet.py? (y/n) " {
		t.Fatalf("cursor line = %q, %v", line, err)
	}
}

func TestTheActivityClockPublishesTransitionsOnly(t *testing.T) {
	p := newTestParser(t, 80, 24)
	clock := NewActivityClock(p)
	start := time.Unix(1_800_000_000, 0)
	if _, changed, _ := clock.Step(p, start, time.Time{}); changed {
		t.Fatal("a clock with no output published")
	}
	feed(t, p, "working")
	state, changed, err := clock.Step(p, start.Add(10*time.Millisecond), time.Time{})
	if err != nil || !changed || state != ActivityActive {
		t.Fatalf("first output = %v %v %v, want active", state, changed, err)
	}
	if _, changed, _ := clock.Step(p, start.Add(700*time.Millisecond), time.Time{}); changed {
		t.Fatal("pollingForIdle was published")
	}
	state, changed, _ = clock.Step(p, start.Add(1600*time.Millisecond), time.Time{})
	if !changed || state != ActivityIdle {
		t.Fatalf("after 1.5 s quiet = %v %v, want idle", state, changed)
	}
	if _, changed, _ := clock.Step(p, start.Add(5*time.Second), time.Time{}); changed {
		t.Fatal("idle was published twice")
	}
}

func TestTheActivityClockIgnoresTypingEcho(t *testing.T) {
	p := newTestParser(t, 80, 24)
	clock := NewActivityClock(p)
	start := time.Unix(1_800_000_000, 0)
	feed(t, p, "x")
	if _, changed, _ := clock.Step(p, start.Add(50*time.Millisecond), start); changed {
		t.Fatal("echo within 250 ms of a keystroke counted as activity")
	}
	feed(t, p, "agent output")
	state, changed, _ := clock.Step(p, start.Add(400*time.Millisecond), start)
	if !changed || state != ActivityActive {
		t.Fatalf("output after the echo window = %v %v, want active", state, changed)
	}
}

func TestANewClockTakesItsBaselineFromTheParser(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "bytes before the clock existed")
	clock := NewActivityClock(p)
	if _, changed, _ := clock.Step(p, time.Unix(1_800_000_000, 0), time.Time{}); changed {
		t.Fatal("bytes fed before the clock was made counted as new output")
	}
}
