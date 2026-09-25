package ptyhost

import (
	"net"

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
	chunk, _, _, err := parser.OlderChunk(before, vtwasm.OlderChunkRows)
	if err != nil {
		h.logf("older output: %v", err)
	}
	mark, err := parser.OlderMark()
	if err != nil {
		h.logf("older output mark: %v", err)
	}
	h.queueOlder(cs, []byte(chunk+mark))
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
