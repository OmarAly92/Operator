// attach.go - Attach: a loopback Stream over the B3 pty-host. No attach CLI is
// spawned; this dials the session's loopback host and speaks the B1 framing
// protocol directly. The host replays
// the scrollback Snapshot as the first MsgTerminalData on connect, so a fresh
// Read naturally yields the repaint first.
package ptyhost

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
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

	pr, pw := io.Pipe()
	s := &loopbackStream{conn: conn, pr: pr, pw: pw, applied: make(chan struct{}, 1)}
	s.dataCond = sync.NewCond(&s.dataMu)

	// Pump host frames: MsgTerminalData payloads are hard onto forwardData's
	// queue, then to the pipe that Read drains. The first such frame is the
	// scrollback snapshot, so the replay arrives before any live output.
	//
	// Forwarding is decoupled from the pump loop (rather than pump writing to
	// pw directly) because the pipe has no buffer: a Write blocks until Read
	// drains it, and nothing reads the pipe until Attach returns the Stream.
	// A pump that wrote directly would block on the scrollback snapshot —
	// which the host always sends first, before it ever answers the resize
	// status request below — and could never get to parsing that reply,
	// deadlocking Attach for any session with existing scrollback.
	go s.pump()
	go s.forwardData()

	// ctx cancellation must terminate the stream (mirrors the unix/windows
	// spawn paths closing the PTY on ctx.Done).
	go func() {
		<-ctx.Done()
		_ = s.Close()
	}()

	if rows > 0 && cols > 0 {
		if err := s.Resize(rows, cols); err != nil {
			_ = s.Close()
			return nil, err
		}
		// Wait for the host to have applied it before handing back the stream.
		// The host dispatches one connection's messages in order, so a status
		// reply proves the resize landed. Returning early instead lets the
		// child's first output be parsed at the pre-attach grid, which renders
		// GetOutput at the wrong width and height until the race resolves.
		if err := s.awaitApplied(); err != nil {
			_ = s.Close()
			return nil, err
		}
	}
	return s, nil
}

// loopbackStream is a ports.Stream backed by a single loopback connection to the
// pty-host. The pump goroutine reframes host output into an io.Pipe so Read
// presents a plain byte stream; Write/Resize encode client frames onto the conn.
type loopbackStream struct {
	conn io.ReadWriteCloser
	pr   *io.PipeReader
	pw   *io.PipeWriter

	// applied carries host status replies, which Attach uses to confirm its
	// initial resize took effect. Buffered and best-effort: nothing after
	// Attach reads it, so the pump never blocks on it.
	applied chan struct{}

	// dataQ/dataCond/dataDone queue MsgTerminalData payloads for forwardData,
	// so pump's Read/parse loop never blocks on the pipe (see the comment on
	// Attach above).
	dataMu   sync.Mutex
	dataCond *sync.Cond
	dataQ    [][]byte
	dataDone bool

	closeOnce sync.Once
}

// enqueueData hands a MsgTerminalData payload to forwardData. payload aliases
// pump's read buffer, so it must be copied before pump's next Read overwrites
// it.
func (s *loopbackStream) enqueueData(payload []byte) {
	cp := append([]byte(nil), payload...)
	s.dataMu.Lock()
	s.dataQ = append(s.dataQ, cp)
	s.dataCond.Signal()
	s.dataMu.Unlock()
}

// forwardData drains the queue into the pipe, one batch at a time, blocking
// on each Write exactly as a direct pump write would have — but without
// blocking pump itself, which must stay free to parse the frames that follow
// a not-yet-drained batch (chiefly the attach status reply).
func (s *loopbackStream) forwardData() {
	for {
		s.dataMu.Lock()
		for len(s.dataQ) == 0 && !s.dataDone {
			s.dataCond.Wait()
		}
		if len(s.dataQ) == 0 {
			s.dataMu.Unlock()
			return
		}
		batch := s.dataQ[0]
		s.dataQ = s.dataQ[1:]
		s.dataMu.Unlock()
		if _, err := s.pw.Write(batch); err != nil {
			return
		}
	}
}

// pump reads framed host messages and writes MsgTerminalData payloads into the
// pipe. It closes the pipe when the connection ends so Read returns EOF.
func (s *loopbackStream) pump() {
	parser := NewMessageParser(func(msgType byte, payload []byte) {
		switch msgType {
		case MsgTerminalData:
			// Queued for forwardData rather than written here; see the comment
			// on Attach for why. forwardData's Write still blocks until Read
			// drains it, preserving back-pressure and order for the data
			// itself — only pump's parsing is decoupled from that block.
			s.enqueueData(payload)
		case MsgStatusRes:
			select {
			case s.applied <- struct{}{}:
			default:
			}
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

const attachResizeAckTimeout = 5 * time.Second

// awaitApplied round-trips a status request so the caller knows every frame
// written before it has been handled.
func (s *loopbackStream) awaitApplied() error {
	frame, err := EncodeMessage(MsgStatusReq, nil)
	if err != nil {
		return err
	}
	if _, err := s.conn.Write(frame); err != nil {
		return err
	}
	select {
	case <-s.applied:
		return nil
	case <-time.After(attachResizeAckTimeout):
		return fmt.Errorf("ptyhost: host did not acknowledge the attach resize in %s", attachResizeAckTimeout)
	}
}

func (s *loopbackStream) Resize(rows, cols uint16) error {
	payload, _ := json.Marshal(ResizePayload{Cols: int(cols), Rows: int(rows)})
	frame, err := EncodeMessage(MsgResize, payload) // small JSON payload, never overflows uint32
	if err != nil {
		return err
	}
	_, err = s.conn.Write(frame)
	return err
}

// Close closes the conn and the pipe, and wakes forwardData so it exits
// instead of leaking on an empty, never-signaled queue. Idempotent. Closing
// the conn unblocks pump's Read, which then closes the pipe-writer too;
// closing both here makes Close safe to call directly (e.g. on ctx cancel)
// without waiting for pump.
func (s *loopbackStream) Close() error {
	var err error
	s.closeOnce.Do(func() {
		err = s.conn.Close()
		_ = s.pw.Close()
		_ = s.pr.Close()
		s.dataMu.Lock()
		s.dataDone = true
		s.dataCond.Broadcast()
		s.dataMu.Unlock()
	})
	return err
}
