package domain

import (
	"testing"
	"time"
)

func TestMergeScreenReading(t *testing.T) {
	now := time.Date(2026, 9, 27, 12, 0, 0, 0, time.UTC)
	fresh := now.Add(-10 * time.Second)
	stale := now.Add(-HookFreshWindow)
	var never time.Time
	for _, tc := range []struct {
		name    string
		current ActivityState
		reading ScreenReading
		hook    time.Time
		want    ActivityState
		apply   bool
	}{
		{"no hooks: working", ActivityIdle, ScreenWorking, never, ActivityActive, true},
		{"no hooks: question", ActivityActive, ScreenQuestion, never, ActivityBlocked, true},
		{"no hooks: settled", ActivityActive, ScreenSettled, never, ActivityIdle, true},
		{"no hooks: waiting", ActivityActive, ScreenWaiting, never, ActivityWaitingInput, true},
		{"same state is a no-op", ActivityBlocked, ScreenQuestion, never, ActivityBlocked, false},
		{"exited never changes", ActivityExited, ScreenWorking, never, ActivityExited, false},
		{"unknown reading", ActivityIdle, ScreenReading("maybe"), never, ActivityIdle, false},
		{"fresh hook: no demotion to idle", ActivityActive, ScreenSettled, fresh, ActivityActive, false},
		{"fresh hook: no promotion to working", ActivityIdle, ScreenWorking, fresh, ActivityIdle, false},
		{"fresh hook: blocked is not cleared", ActivityBlocked, ScreenWorking, fresh, ActivityBlocked, false},
		{"fresh hook: a question after active fills the gap", ActivityActive, ScreenQuestion, fresh, ActivityBlocked, true},
		{"fresh hook: waiting is not escalated", ActivityWaitingInput, ScreenQuestion, fresh, ActivityWaitingInput, false},
		{"stale hook: settled corrects active", ActivityActive, ScreenSettled, stale, ActivityIdle, true},
		{"stale hook: working clears blocked", ActivityBlocked, ScreenWorking, stale, ActivityActive, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, apply := MergeScreenReading(tc.current, tc.reading, tc.hook, now)
			if got != tc.want || apply != tc.apply {
				t.Fatalf("MergeScreenReading(%s, %s) = (%s, %v), want (%s, %v)", tc.current, tc.reading, got, apply, tc.want, tc.apply)
			}
		})
	}
}
