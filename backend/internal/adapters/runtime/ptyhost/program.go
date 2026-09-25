package ptyhost

import (
	"encoding/json"
	"net"
	"strconv"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

const maxAppearancePixels = 4096

func programFrame(event ProgramEventPayload) []byte {
	payload, _ := json.Marshal(event)
	frame, _ := EncodeMessage(MsgProgramEvent, payload)
	return frame
}

func (h *host) serveWatcher(conn net.Conn, cs *clientState, buf []byte) {
	h.mu.Lock()
	h.watchers[conn] = cs
	cs.enqueue(programFrame(ProgramEventPayload{Kind: ProgramEventTitle, Title: h.shownTitle}))
	h.mu.Unlock()
	go h.runWriter(conn, cs)
	defer func() {
		cs.closeOut()
		h.mu.Lock()
		delete(h.watchers, conn)
		h.mu.Unlock()
		_ = conn.Close()
	}()
	for {
		if _, err := conn.Read(buf); err != nil {
			return
		}
	}
}

func (h *host) publishProgramLocked() {
	if h.parser == nil {
		return
	}
	generation, err := h.parser.ProgramGeneration()
	if err != nil || generation == h.programGen {
		return
	}
	h.programGen = generation
	var events []ProgramEventPayload
	if raw, err := h.parser.Title(); err == nil {
		if shown := domain.TerminalDisplayTitle(raw); shown != h.shownTitle {
			h.shownTitle = shown
			events = append(events, ProgramEventPayload{Kind: ProgramEventTitle, Title: shown})
		}
	}
	if notes, err := h.parser.TakeNotifications(); err == nil {
		for _, note := range notes {
			events = append(events, ProgramEventPayload{Kind: ProgramEventNotification, Title: note.Title, Body: note.Body})
		}
	}
	for _, event := range events {
		h.sendWatchersLocked(programFrame(event))
	}
}

func (h *host) sendWatchersLocked(frame []byte) {
	for _, cs := range h.watchers {
		if cs.queuedBytes() > maxQueuedClientBytes {
			continue
		}
		cs.enqueue(frame)
	}
}

func (h *host) resetProgramLocked() {
	h.programGen = 0
	if h.parser != nil && h.appearance != nil {
		applyAppearance(h.parser, *h.appearance)
	}
	if h.shownTitle == "" {
		return
	}
	h.shownTitle = ""
	h.sendWatchersLocked(programFrame(ProgramEventPayload{Kind: ProgramEventTitle}))
}

func (h *host) handleAppearance(payload []byte) {
	var appearance AppearancePayload
	if err := json.Unmarshal(payload, &appearance); err != nil {
		return
	}
	h.mu.Lock()
	h.appearance = &appearance
	var replies []byte
	if h.parser != nil {
		applyAppearance(h.parser, appearance)
		replies = h.takeQueryRepliesLocked()
	}
	pty := h.pty
	h.mu.Unlock()
	if len(replies) > 0 {
		_, _ = pty.Write(replies)
	}
}

func applyAppearance(parser interface {
	SetDefaultColors(foreground, background int32) error
	SetCellPixels(width, height uint32) error
}, appearance AppearancePayload) {
	_ = parser.SetDefaultColors(parseHexColor(appearance.Foreground), parseHexColor(appearance.Background))
	_ = parser.SetCellPixels(clampPixels(appearance.CellWidth), clampPixels(appearance.CellHeight))
}

func clampPixels(value int) uint32 {
	if value <= 0 {
		return 0
	}
	return uint32(min(value, maxAppearancePixels))
}

func parseHexColor(value string) int32 {
	hex, ok := strings.CutPrefix(strings.TrimSpace(value), "#")
	if !ok || len(hex) != 6 {
		return -1
	}
	rgb, err := strconv.ParseUint(hex, 16, 32)
	if err != nil {
		return -1
	}
	return int32(rgb)
}

func (cs *clientState) queuedBytes() int {
	cs.outMu.Lock()
	defer cs.outMu.Unlock()
	return cs.outBytes
}
