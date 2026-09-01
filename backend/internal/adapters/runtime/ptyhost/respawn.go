// respawn.go implements restart-in-place: kill the child, exec a
// replacement, keep the socket/ring/registry/handle. This is the tmux-free
// equivalent of `respawn-pane -k`.
package ptyhost

import (
	"encoding/json"
	"net"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

const respawnCloseTimeout = 5 * time.Second

// handleRespawn runs the nine-step respawn sequence for a MsgRespawnReq and
// replies with a MsgRespawnRes. respawnMu serializes this against any other
// concurrent respawn on the same host.
func (h *host) handleRespawn(conn net.Conn, payload []byte) {
	h.respawnMu.Lock()
	defer h.respawnMu.Unlock()

	var req RespawnPayload
	if err := json.Unmarshal(payload, &req); err != nil || req.Cwd == "" || req.Shell == "" {
		h.sendTo(conn, respawnResFrame(false, 0, "malformed respawn request"))
		return
	}

	old := h.currentPTY()
	_ = old.Close()
	select {
	case <-old.Done():
	case <-time.After(respawnCloseTimeout):
		h.sendTo(conn, respawnResFrame(false, 0, "timed out waiting for the previous process to exit"))
		return
	}

	h.mu.Lock()
	pumpDone := h.pumpDone
	h.mu.Unlock()
	<-pumpDone

	h.cfg.Ring.Reset()

	if oldParser := h.currentParser(); oldParser != nil {
		_ = oldParser.Close()
	}
	h.mu.Lock()
	cols, rows := h.curCols, h.curRows
	h.mu.Unlock()
	if cols == 0 || rows == 0 {
		cols, rows = h.cfg.InitialCols, h.cfg.InitialRows
	}
	newParser, err := vtwasm.New(h.ctx, vtwasm.Module, uint32(cols), uint32(rows), MaxOutputLines)
	if err != nil {
		newParser = nil
	}

	pty, err := newPTY(req.Cwd, req.Shell, req.LaunchCmd)
	if err != nil {
		if newParser != nil {
			_ = newParser.Close()
		}
		h.mu.Lock()
		h.parser = nil
		h.mu.Unlock()
		h.sendTo(conn, respawnResFrame(false, 0, err.Error()))
		return
	}

	h.mu.Lock()
	h.pty = pty
	h.parser = newParser
	h.curCols, h.curRows = 0, 0
	h.applyLargestLocked()
	h.pumpDone = make(chan struct{})
	h.mu.Unlock()

	go h.pumpPTY()

	h.sendTo(conn, respawnResFrame(true, pty.PID(), ""))
	h.broadcast(statusFrame(true, pty.PID(), nil))
}

func respawnResFrame(ok bool, pid int, errMsg string) []byte {
	rp := RespawnResPayload{OK: ok, PID: pid, Error: errMsg}
	b, _ := json.Marshal(rp)
	frame, _ := EncodeMessage(MsgRespawnRes, b) // b is small JSON, never overflows uint32
	return frame
}
