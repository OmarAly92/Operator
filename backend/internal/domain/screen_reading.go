package domain

import "time"

type ScreenReading string

const (
	ScreenWorking  ScreenReading = "working"
	ScreenQuestion ScreenReading = "question"
	ScreenWaiting  ScreenReading = "waiting"
	ScreenSettled  ScreenReading = "settled"
)

const HookFreshWindow = 30 * time.Second

func (r ScreenReading) State() (ActivityState, bool) {
	switch r {
	case ScreenWorking:
		return ActivityActive, true
	case ScreenQuestion:
		return ActivityBlocked, true
	case ScreenWaiting:
		return ActivityWaitingInput, true
	case ScreenSettled:
		return ActivityIdle, true
	default:
		return "", false
	}
}

type ScreenMerge struct {
	Current         ActivityState
	Reading         ScreenReading
	LastHookAt      time.Time
	ScreenChangedAt time.Time
	Reassert        bool
}

func MergeScreenReading(in ScreenMerge, now time.Time) (ActivityState, bool) {
	target, ok := in.Reading.State()
	if !ok || in.Current == ActivityExited || target == in.Current {
		return in.Current, false
	}
	if in.LastHookAt.IsZero() || in.ScreenChangedAt.After(in.LastHookAt) {
		return target, true
	}
	if in.Current == ActivityWaitingInput && target != ActivityBlocked {
		return in.Current, false
	}
	if now.Sub(in.LastHookAt) < HookFreshWindow {
		if in.Reading == ScreenQuestion && in.Current == ActivityActive && !in.Reassert {
			return target, true
		}
		return in.Current, false
	}
	return target, true
}
