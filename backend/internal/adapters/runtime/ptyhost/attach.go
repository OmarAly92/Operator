// attach.go - Attach: a loopback Stream over the B3 pty-host. No attach CLI is
// spawned; this dials the session's loopback host and speaks the B1 framing
// protocol directly. The host replays the scrollback Snapshot as the first
// MsgTerminalData on connect, so a fresh Read naturally yields the repaint
// first.
package ptyhost

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"sync"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var _ ports.Attacher = (*Runtime)(nil)

// Attach opens a fresh attach Stream for the session by dialing its loopback
// pty-host. rows/cols size the host's PTY from birth when known (a MsgResize is
// sent right after connect). ctx cancellation closes the Stream.
func (r *Runtime) Attach(ctx context.Context, handle ports.RuntimeHandle, rows, cols uint16) (ports.Stream, error) {
	sess := r.resolve(handle.ID)
	if sess == nil {
		return nil, fmt.Errorf("ptyhost: session %q not found", handle.ID)
	}
	conn, err := dialHost(sess.addr, dialTimeout)
	if err != nil {
		return nil, fmt.Errorf("ptyhost: dial host for %q: %w", handle.ID, err)
	}

	// The birth resize is handshaken synchronously, on the bare conn, before
	// any pipe exists. Returning without it lets the child's first output be
	// parsed at the pre-attach grid, which renders GetOutput at the wrong
	// width and height until the race resolves; doing it *after* starting the
	// pump deadlocks instead, because the host always sends the scrollback
	// snapshot before it answers, and a pump writing that snapshot into the
	// unbuffered pipe blocks before it can ever parse the reply — nothing
	// reads the pipe until Attach returns.
	//
	// Frames that arrive during the handshake are handed to the pump to replay
	// first, so ordering is unchanged. They are bounded: the snapshot is capped
	// at MaxOutputLines, and live output can only accumulate for the one
	// loopback round-trip the status reply takes.
	var replay [][]byte
	if rows > 0 && cols > 0 {
		if replay, err = attachHandshake(conn, rows, cols); err != nil {
			_ = conn.Close()
			return nil, err
		}
	}

	pr, pw := io.Pipe()
	s := &loopbackStream{conn: conn, pr: pr, pw: pw}

	// Pump host frames: MsgTerminalData payloads go into the pipe that Read
	// drains, writing directly so a Write blocks until Read drains it. That
	// block is load-bearing back-pressure: it stops the pump reading the
	// socket, which fills the host's send buffer, which stops the host reading
	// the PTY, which finally blocks the child. Queueing here instead would let
	// a stalled client accumulate the whole session in memory.
	go s.pump(replay)

	// ctx cancellation must terminate the stream (mirrors the unix/windows
	// spawn paths closing the PTY on ctx.Done).
	go func() {
		<-ctx.Done()
		_ = s.Close()
	}()

	return s, nil
}

const attachResizeAckTimeout = 5 * time.Second

// attachHandshake sends the birth resize and a status request, then reads the
// conn directly until the host answers. The host dispatches one connection's
// messages in order, so the reply proves the resize landed. Terminal data seen
// while waiting (the scrollback snapshot, and anything the child emitted in the
// same window) is returned for the pump to replay ahead of live output.
func attachHandshake(conn net.Conn, rows, cols uint16) ([][]byte, error) {
	if err := writeResize(conn, rows, cols); err != nil {
		return nil, err
	}
	statusReq, err := EncodeMessage(MsgStatusReq, nil)
	if err != nil {
		return nil, err
	}
	if _, err := conn.Write(statusReq); err != nil {
		return nil, err
	}

	if err := conn.SetReadDeadline(time.Now().Add(attachResizeAckTimeout)); err != nil {
		return nil, err
	}
	// Clear the deadline before handing the conn to the pump, which must block
	// indefinitely on an idle session.
	defer func() { _ = conn.SetReadDeadline(time.Time{}) }()

	var (
		replay  [][]byte
		applied bool
	)
	parser := NewMessageParser(func(msgType byte, payload []byte) {
		switch msgType {
		case MsgTerminalData:
			// payload aliases buf, which the next Read overwrites.
			replay = append(replay, append([]byte(nil), payload...))
		case MsgStatusRes:
			applied = true
		}
	})
	buf := make([]byte, 4096)
	for !applied {
		n, err := conn.Read(buf)
		if n > 0 {
			parser.Feed(buf[:n])
		}
		if err != nil {
			return nil, fmt.Errorf("ptyhost: host did not acknowledge the attach resize within %s: %w", attachResizeAckTimeout, err)
		}
	}
	return replay, nil
}

// loopbackStream is a ports.Stream backed by a single loopback connection to the
// pty-host. The pump goroutine reframes host output into an io.Pipe so Read
// presents a plain byte stream; Write/Resize encode client frames onto the conn.
type loopbackStream struct {
	conn io.ReadWriteCloser
	pr   *io.PipeReader
	pw   *io.PipeWriter

	closeOnce sync.Once
}

// pump replays any frames the attach handshake consumed, then reads framed host
// messages and writes MsgTerminalData payloads into the pipe. It closes the pipe
// when the connection ends so Read returns EOF.
func (s *loopbackStream) pump(replay [][]byte) {
	for _, batch := range replay {
		if _, err := s.pw.Write(batch); err != nil {
			return
		}
	}
	parser := NewMessageParser(func(msgType byte, payload []byte) {
		if msgType == MsgTerminalData {
			// Write blocks until Read drains, preserving back-pressure and order.
			_, _ = s.pw.Write(payload)
		}
	})
	buf := make([]byte, 4096)
	for {
		n, err := s.conn.Read(buf)
		if n > 0 {
			parser.Feed(buf[:n])
		}
		if err != nil {
			_ = s.pw.CloseWithError(err)
			return
		}
	}
}

func (s *loopbackStream) Read(p []byte) (int, error) { return s.pr.Read(p) }

func (s *loopbackStream) Write(p []byte) (int, error) {
	frame, err := EncodeMessage(MsgTerminalInput, p)
	if err != nil {
		return 0, err
	}
	if _, err := s.conn.Write(frame); err != nil {
		return 0, err
	}
	return len(p), nil
}

func (s *loopbackStream) Resize(rows, cols uint16) error {
	return writeResize(s.conn, rows, cols)
}

// writeResize encodes and sends one MsgResize frame.
func writeResize(w io.Writer, rows, cols uint16) error {
	payload, _ := json.Marshal(ResizePayload{Cols: int(cols), Rows: int(rows)})
	frame, err := EncodeMessage(MsgResize, payload) // small JSON payload, never overflows uint32
	if err != nil {
		return err
	}
	_, err = w.Write(frame)
	return err
}

// Close closes the conn and the pipe. Idempotent. Closing the conn unblocks
// pump's Read, which then closes the pipe-writer too; closing both here makes
// Close safe to call directly (e.g. on ctx cancel) without waiting for pump.
// Closing the pipe also unblocks a pump parked on a Write nothing is draining.
func (s *loopbackStream) Close() error {
	var err error
	s.closeOnce.Do(func() {
		err = s.conn.Close()
		_ = s.pw.Close()
		_ = s.pr.Close()
	})
	return err
}
