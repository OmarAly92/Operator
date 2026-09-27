package vtwasm

import (
	"fmt"
	"math"
	"time"
)

type AgentActivity uint32

const (
	ActivityActive AgentActivity = iota
	ActivityPollingForIdle
	ActivityIdle
	ActivityPrompting
)

func (a AgentActivity) String() string {
	switch a {
	case ActivityActive:
		return "active"
	case ActivityPollingForIdle:
		return "pollingForIdle"
	case ActivityIdle:
		return "idle"
	case ActivityPrompting:
		return "prompting"
	default:
		return "unknown"
	}
}

const (
	cursorLineBufferBytes = 4096
	InputEchoWindow       = 250 * time.Millisecond
)

func (p *Parser) callLocked(name string, args ...uint64) (uint64, error) {
	fn := p.module.ExportedFunction(name)
	if fn == nil {
		return 0, fmt.Errorf("vtwasm: %s is not exported", name)
	}
	res, err := fn.Call(p.ctx, args...)
	if err != nil {
		return 0, fmt.Errorf("vtwasm: %s: %w", name, err)
	}
	return res[0], nil
}

func (p *Parser) LiveOutputBytes() (uint64, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.callLocked("vt_live_output_bytes", uint64(p.handle))
}

func (p *Parser) AgentActivity(quietMs int64) (AgentActivity, error) {
	quiet := uint64(math.MaxUint64)
	if quietMs >= 0 {
		quiet = uint64(quietMs)
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	raw, err := p.callLocked("vt_agent_activity", uint64(p.handle), quiet)
	if err != nil {
		return ActivityIdle, err
	}
	if raw == uint64(renderErr) {
		return ActivityIdle, fmt.Errorf("vtwasm: agent_activity failed for handle %d", p.handle)
	}
	return AgentActivity(uint32(raw)), nil
}

func (p *Parser) CursorLine() (string, error) {
	raw, err := p.readOut("vt_cursor_line", cursorLineBufferBytes)
	return string(raw), err
}

type ActivityClock struct {
	bytes     uint64
	lastAt    time.Time
	started   bool
	published bool
	shown     AgentActivity
	settledAt time.Time
}

func (c *ActivityClock) SettledSince(touched time.Time) bool {
	return !c.settledAt.IsZero() && !touched.After(c.settledAt)
}

func NewActivityClock(p *Parser) ActivityClock {
	bytes, _ := p.LiveOutputBytes()
	return ActivityClock{bytes: bytes}
}

func (c *ActivityClock) Step(p *Parser, now, pokedAt time.Time) (AgentActivity, bool, error) {
	bytes, err := p.LiveOutputBytes()
	if err != nil {
		return c.shown, false, err
	}
	if bytes != c.bytes {
		c.bytes = bytes
		if pokedAt.IsZero() || now.Sub(pokedAt) >= InputEchoWindow {
			c.lastAt = now
			c.started = true
		}
	}
	if !c.started {
		return c.shown, false, nil
	}
	state, err := p.AgentActivity(now.Sub(c.lastAt).Milliseconds())
	if err != nil {
		c.settledAt = time.Time{}
		return c.shown, false, err
	}
	c.settledAt = time.Time{}
	if state == ActivityIdle || state == ActivityPrompting {
		c.settledAt = now
	}
	if state == ActivityPollingForIdle || (c.published && state == c.shown) {
		return c.shown, false, nil
	}
	c.shown = state
	c.published = true
	return state, true, nil
}
