package ptyhost

import (
	"encoding/json"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

var activityTick = 250 * time.Millisecond

const activityTailRows = 40

func (h *host) runActivityClock() {
	ticker := time.NewTicker(activityTick)
	defer ticker.Stop()
	for {
		select {
		case <-h.shutdownC:
			return
		case now := <-ticker.C:
			h.mu.Lock()
			h.publishActivityLocked(now)
			h.mu.Unlock()
		}
	}
}

func (h *host) publishActivityLocked(now time.Time) {
	if h.parser == nil {
		return
	}
	state, changed, err := h.activity.Step(h.parser, now, h.pokedAt)
	if err != nil || !changed {
		return
	}
	h.activitySeq++
	event := ProgramEventPayload{Kind: ProgramEventActivity, Activity: state.String(), Seq: h.activitySeq, AtMs: now.UnixMilli()}
	if state != vtwasm.ActivityActive {
		event.Tail, _ = h.parser.RenderTail(activityTailRows)
		event.CursorLine, _ = h.parser.CursorLine()
	}
	h.activityFrame = programFrame(event)
	for _, cs := range h.watchers {
		if cs.wantsActivity && cs.queuedBytes() <= maxQueuedClientBytes {
			cs.enqueue(h.activityFrame)
		}
	}
}

func (h *host) resetActivityLocked() {
	h.activityFrame = nil
	h.activity = vtwasm.ActivityClock{}
	if h.parser != nil {
		h.activity = vtwasm.NewActivityClock(h.parser)
	}
}

func wantsActivity(payload []byte) bool {
	var watch WatchPayload
	return len(payload) > 0 && json.Unmarshal(payload, &watch) == nil && watch.Activity
}
