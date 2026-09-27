package domain

import (
	"testing"
	"time"
)

func TestMergeScreenReading(t *testing.T) {
	now := time.Date(2026, 9, 27, 12, 0, 0, 0, time.UTC)
	fresh := now.Add(-10 * time.Second)
	stale := now.Add(-HookFreshWindow)
	afterFresh := now.Add(-5 * time.Second)
	var never time.Time
	for _, tc := range []struct {
		name     string
		current  ActivityState
		reading  ScreenReading
		hook     time.Time
		screen   time.Time
		reassert bool
		want     ActivityState
		apply    bool
	}{
		{"no hooks: working", ActivityIdle, ScreenWorking, never, never, false, ActivityActive, true},
		{"no hooks: question", ActivityActive, ScreenQuestion, never, never, false, ActivityBlocked, true},
		{"no hooks: settled", ActivityActive, ScreenSettled, never, never, false, ActivityIdle, true},
		{"no hooks: waiting", ActivityActive, ScreenWaiting, never, never, false, ActivityWaitingInput, true},
		{"no hooks: the screen clears its own waiting", ActivityWaitingInput, ScreenSettled, never, fresh, false, ActivityIdle, true},
		{"same state is a no-op", ActivityBlocked, ScreenQuestion, never, never, false, ActivityBlocked, false},
		{"exited never changes", ActivityExited, ScreenWorking, never, never, false, ActivityExited, false},
		{"exited never changes, even screen-set", ActivityExited, ScreenWorking, fresh, afterFresh, false, ActivityExited, false},
		{"unknown reading", ActivityIdle, ScreenReading("maybe"), never, never, false, ActivityIdle, false},
		{"fresh hook: no demotion to idle", ActivityActive, ScreenSettled, fresh, never, false, ActivityActive, false},
		{"fresh hook: no promotion to working", ActivityIdle, ScreenWorking, fresh, never, false, ActivityIdle, false},
		{"fresh hook: blocked is not cleared", ActivityBlocked, ScreenWorking, fresh, never, false, ActivityBlocked, false},
		{"fresh hook: a question after active fills the gap", ActivityActive, ScreenQuestion, fresh, never, false, ActivityBlocked, true},
		{"fresh hook: a re-asserted question never escalates", ActivityActive, ScreenQuestion, fresh, never, true, ActivityActive, false},
		{"fresh hook: waiting is not escalated", ActivityWaitingInput, ScreenQuestion, fresh, never, false, ActivityWaitingInput, false},
		{"fresh hook: the screen may undo its own escalation", ActivityBlocked, ScreenWorking, fresh, afterFresh, false, ActivityActive, true},
		{"fresh hook: a hook after the screen owns the state again", ActivityBlocked, ScreenWorking, afterFresh, fresh, false, ActivityBlocked, false},
		{"stale hook: settled corrects active", ActivityActive, ScreenSettled, stale, never, false, ActivityIdle, true},
		{"stale hook: working clears blocked", ActivityBlocked, ScreenWorking, stale, never, false, ActivityActive, true},
		{"stale hook: a re-asserted question applies", ActivityActive, ScreenQuestion, stale, never, true, ActivityBlocked, true},
		{"hook waiting_input: settled never clears it", ActivityWaitingInput, ScreenSettled, stale, never, false, ActivityWaitingInput, false},
		{"hook waiting_input: working never clears it", ActivityWaitingInput, ScreenWorking, stale, never, true, ActivityWaitingInput, false},
		{"hook waiting_input: a stale hook's question escalates", ActivityWaitingInput, ScreenQuestion, stale, never, false, ActivityBlocked, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, apply := MergeScreenReading(ScreenMerge{Current: tc.current, Reading: tc.reading, LastHookAt: tc.hook, ScreenChangedAt: tc.screen, Reassert: tc.reassert}, now)
			if got != tc.want || apply != tc.apply {
				t.Fatalf("MergeScreenReading(%s, %s) = (%s, %v), want (%s, %v)", tc.current, tc.reading, got, apply, tc.want, tc.apply)
			}
		})
	}
}
