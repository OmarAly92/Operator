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

func MergeScreenReading(current ActivityState, reading ScreenReading, lastHookAt, now time.Time) (ActivityState, bool) {
	target, ok := reading.State()
	if !ok || current == ActivityExited || target == current {
		return current, false
	}
	if !lastHookAt.IsZero() && now.Sub(lastHookAt) < HookFreshWindow {
		if reading == ScreenQuestion && current == ActivityActive {
			return target, true
		}
		return current, false
	}
	return target, true
}
