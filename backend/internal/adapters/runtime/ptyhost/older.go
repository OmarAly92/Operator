package ptyhost

import (
	"net"
	"strconv"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

func (h *host) serveOlder(conn net.Conn, before uint64) {
	h.mu.Lock()
	cs := h.clients[conn]
	h.mu.Unlock()
	parser := h.currentParser()
	if cs == nil || parser == nil {
		return
	}
	chunk, _, ok, err := parser.OlderChunk(before, vtwasm.OlderChunkRows)
	if err != nil {
		h.logf("older output: %v", err)
	}
	mark, err := parser.OlderMark()
	if err != nil {
		h.logf("older output mark: %v", err)
	}
	if !ok && mark != "" {
		mark = nothingOlderMark(mark, before)
	}
	h.queueOlder(cs, []byte(chunk+mark))
}

const olderMarkPrefix = "\x1b]7000;v=1;older="

func nothingOlderMark(mark string, before uint64) string {
	floor, err := strconv.ParseUint(strings.TrimSuffix(strings.TrimPrefix(mark, olderMarkPrefix), "\x1b\\"), 10, 64)
	if err == nil && floor >= before {
		return mark
	}
	return olderMarkPrefix + strconv.FormatUint(before, 10) + "\x1b\\"
}

func (h *host) sendOlderMark(cs *clientState) {
	parser := h.currentParser()
	if parser == nil {
		return
	}
	mark, err := parser.OlderMark()
	if err != nil {
		h.logf("older output mark: %v", err)
		return
	}
	h.queueOlder(cs, []byte(mark))
}

func (h *host) queueOlder(cs *clientState, payload []byte) {
	if len(payload) == 0 {
		return
	}
	frame, err := EncodeMessage(MsgTerminalData, payload)
	if err != nil {
		h.logf("encode older output: %v", err)
		return
	}
	h.mu.Lock()
	cs.enqueue(frame)
	cs.delivered += len(payload)
	h.mu.Unlock()
}
