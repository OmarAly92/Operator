// Package conpty - host.go implements the serve engine for the pty-host
// detached process. It owns the agent's PTY (via the ptyConn seam), exposes
// it over a loopback TCP socket using the B1 binary protocol, replays
// scrollback to new clients, fans output to all connected clients, and shuts
// down gracefully (ConPTY dispose first, then clients, then listener).
//
// This file is cross-platform; only the real conptyConn impl is Windows-tagged.
package ptyhost

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

// ptyConn is the host's handle to the running agent's pseudo-terminal.
// The real impl (conptyConn) lives in host_conpty_windows.go; tests use a fake.
type ptyConn interface {
	io.Reader // PTY output (raw bytes from the terminal)
	io.Writer // PTY input (keystrokes to the terminal)
	Resize(cols, rows int) error
	Close() error          // dispose the ConPTY
	Done() <-chan struct{} // closed when the child process exits
	ExitCode() (int, bool) // (code, true) once exited; (0, false) while running
	PID() int
}

// ServeConfig carries everything the host needs. PTY and Parser seed the
// host's mutable pty/parser fields (see host.pty/host.parser); InitialCols/
// InitialRows are the grid a respawned PTY falls back to when no client has
// resized yet.
type ServeConfig struct {
	SessionID   string
	Listener    net.Listener // caller provides (loopback); engine owns Accept loop
	PTY         ptyConn
	Ring        *Ring
	Parser      *vtwasm.Parser
	InitialCols int
	InitialRows int
}

// Serve runs the host event loop until the listener closes or Shutdown is
// invoked via the returned ShutdownFunc. It pumps PTY output into the ring
// and broadcasts to all clients, accepts new clients (replaying ring snapshot),
// and dispatches client messages. On PTY exit it broadcasts a status update
// but stays alive (keep-alive), so a client can still read the final screen.
// Returns when shut down.
func Serve(ctx context.Context, cfg ServeConfig) error {
	h := &host{
		cfg:       cfg,
		ctx:       ctx,
		clients:   make(map[net.Conn]*clientState),
		shutdownC: make(chan struct{}),
		capture:   &captureSink{},
		pty:       cfg.PTY,
		parser:    cfg.Parser,
		pumpDone:  make(chan struct{}),
	}
	return h.run(ctx)
}

// clientState is the host's per-connection bookkeeping. cols/rows record the
// grid this client last asked for (sized reports whether it ever asked), so the
// host can size the shared PTY to the largest attached client (see
// applyLargestLocked). A connection that never sends a resize stays sized=false
// and never influences the shared grid.
type clientState struct {
	cols, rows int
	sized      bool

	// out is this client's outbound queue, drained by a dedicated writer
	// goroutine (runWriter). Every frame the host sends a client -- the
	// scrollback snapshot, live broadcast, per-connection replies -- is queued
	// here instead of being written inline.
	//
	// Writing inline is what handleConn used to do, and it did it while holding
	// h.mu, before starting its own read loop. Once the snapshot outgrew the
	// socket buffer that write blocked, which froze h.mu for the whole session
	// AND meant the read loop that would have parsed this connection's own
	// input frame never started -- so a one-shot RPC (SendMessage, SendInput,
	// Interrupt, ...), which writes its frame and never reads a reply, had its
	// input silently dropped rather than delayed.
	//
	// Queueing under h.mu keeps the snapshot-then-register ordering exactly as
	// it was: the snapshot is queued first, and any batch broadcast afterwards
	// is queued behind it, so a client still cannot see a batch twice or miss
	// one. Only the blocking write moved off the lock.
	//
	// Lock order is h.mu -> outMu, never the reverse: enqueue is called with
	// h.mu held, while awaitCapacity and runWriter take outMu alone.
	outMu    sync.Mutex
	outCond  *sync.Cond
	out      [][]byte
	outBytes int
	outDone  bool
}

func newClientState() *clientState {
	cs := &clientState{}
	cs.outCond = sync.NewCond(&cs.outMu)
	return cs
}

// enqueue appends frame to the client's outbound queue. It never blocks:
// callers hold h.mu, and blocking under h.mu is the defect this queue exists to
// remove. Back-pressure is applied afterwards, off the lock, by awaitCapacity.
func (cs *clientState) enqueue(frame []byte) {
	cs.outMu.Lock()
	if !cs.outDone {
		cs.out = append(cs.out, frame)
		cs.outBytes += len(frame)
		cs.outCond.Broadcast()
	}
	cs.outMu.Unlock()
}

// awaitCapacity blocks until this client's backlog falls back under
// maxQueuedClientBytes, or the client goes away. Called by deliver after it has
// released h.mu, so a client that stops reading throttles the PTY pump -- and
// through it the child process -- exactly as the old inline write did, but
// without holding the lock or starving any connection's read loop.
func (cs *clientState) awaitCapacity() {
	cs.outMu.Lock()
	for cs.outBytes > maxQueuedClientBytes && !cs.outDone {
		cs.outCond.Wait()
	}
	cs.outMu.Unlock()
}

// closeOut marks the queue finished and wakes runWriter plus anyone parked in
// awaitCapacity. Idempotent: both the read loop's defer and shutdown call it.
func (cs *clientState) closeOut() {
	cs.outMu.Lock()
	cs.outDone = true
	cs.out = nil
	cs.outBytes = 0
	cs.outCond.Broadcast()
	cs.outMu.Unlock()
}

// maxQueuedClientBytes caps the output buffered for a client that is not
// keeping up. Four read buffers matches maxQueuedCaptureBytes: enough to ride
// out a renderer hiccup, small enough that a wedged client costs a bounded
// amount of memory rather than the whole session.
const maxQueuedClientBytes = 4 * readBufferSize

// host holds the mutable state for a single pty-host session.
type host struct {
	cfg     ServeConfig
	ctx     context.Context
	mu      sync.Mutex
	clients map[net.Conn]*clientState

	// pty/parser are the live child process and its passive parser. Both start
	// out as cfg.PTY/cfg.Parser and are replaced in place by respawn (see
	// respawn.go), which is the only writer besides Serve's construction.
	// Every other reader goes through currentPTY()/currentParser() (or, inside
	// a function that already holds mu, the field directly) so a respawn swap
	// is never observed as a torn read.
	pty    ptyConn
	parser *vtwasm.Parser

	// curCols/curRows are the grid the host last applied to the shared PTY (0,0
	// = none applied yet). Guarded by mu; used to skip redundant resizes.
	curCols, curRows int

	shutdownOnce sync.Once
	shutdownC    chan struct{} // closed when Shutdown is called

	// pumpDone is closed when the current pumpPTY generation's reader hits EOF.
	// Recreated before each `go h.pumpPTY()` (initial start and every respawn).
	// Guarded by mu.
	pumpDone chan struct{}

	// respawnMu serializes concurrent MsgRespawnReq handling so two respawns
	// never race the pty/parser swap.
	respawnMu sync.Mutex

	capture *captureSink
}

// runWriter drains one client's outbound queue, blocking on each conn.Write
// exactly as the inline writes used to -- but on its own goroutine, so a client
// that has stopped reading never blocks h.mu, the PTY pump, or its own read
// loop.
func (h *host) runWriter(conn net.Conn, cs *clientState) {
	for {
		cs.outMu.Lock()
		for len(cs.out) == 0 && !cs.outDone {
			cs.outCond.Wait()
		}
		if cs.outDone {
			cs.outMu.Unlock()
			return
		}
		frame := cs.out[0]
		cs.out = cs.out[1:]
		cs.outBytes -= len(frame)
		cs.outCond.Broadcast() // deliver may be parked in awaitCapacity
		cs.outMu.Unlock()

		if _, err := conn.Write(frame); err != nil {
			h.dropClient(conn)
			return
		}
	}
}

// dropClient removes a client whose write failed. It is the single place the
// write path retires a connection, replacing the inline removal that
// broadcastLocked and sendTo used to do on error.
func (h *host) dropClient(conn net.Conn) {
	h.mu.Lock()
	cs := h.clients[conn]
	delete(h.clients, conn)
	// A dropped client may have been the largest viewer; recompute the shared
	// grid so it follows the remaining clients.
	h.applyLargestLocked()
	h.mu.Unlock()
	if cs != nil {
		cs.closeOut()
	}
	_ = conn.Close()
}

// currentPTY returns the live child PTY connection. Safe to call from any
// goroutine; the returned value may become stale the instant it returns (a
// concurrent respawn may swap it), which is fine — every caller uses it for a
// single, self-contained operation rather than holding it across a respawn.
func (h *host) currentPTY() ptyConn {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.pty
}

// currentParser returns the live passive parser (nil if it failed to start).
// Same staleness contract as currentPTY.
func (h *host) currentParser() *vtwasm.Parser {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.parser
}

// applyLargestLocked sizes the shared PTY to a SINGLE client's grid — the
// largest by area — and resizes only when that choice changes. There is one PTY
// with one grid, so when several clients view it at once (e.g. the desktop app
// and the phone) the largest wins: a small viewer can never shrink the grid a
// larger one needs, which is what produced the "stripped-down" desktop view when
// a phone attached.
//
// Crucially this matches ONE client's cols AND rows as a pair, rather than taking
// an independent max of each axis. A per-axis max would synthesize a grid no
// client actually has — a wide-but-short desktop (120x30) plus a narrow-but-tall
// phone (55x48) would yield 120x48 — and that phantom grid mis-renders for every
// client (the desktop draws its footer at a row it can't show; the phone gets
// columns it can't fit). Matching one client exactly keeps that client (the
// largest — normally the desktop) pixel-correct; only smaller clients scale.
//
// Called on every client resize and on every disconnect, so the grid follows a
// newly-attached larger client and falls back to the remaining largest one when
// it leaves. Callers must hold h.mu.
func (h *host) applyLargestLocked() {
	bestCols, bestRows, bestArea := 0, 0, 0
	for _, cs := range h.clients {
		if !cs.sized {
			continue
		}
		if area := cs.cols * cs.rows; area > bestArea {
			bestArea, bestCols, bestRows = area, cs.cols, cs.rows
		}
	}
	// No client has reported a size yet: leave the PTY at its current grid (the
	// initial size set when the ConPTY was created).
	if bestCols == 0 || bestRows == 0 {
		return
	}
	if bestCols == h.curCols && bestRows == h.curRows {
		return
	}
	h.curCols, h.curRows = bestCols, bestRows
	_ = h.pty.Resize(bestCols, bestRows)
	if h.parser != nil {
		_ = h.parser.Resize(uint32(bestCols), uint32(bestRows))
	}
}

// run is the main event loop.
func (h *host) run(ctx context.Context) error {
	// Pump PTY output to ring + broadcast.
	go h.pumpPTY()

	// Watch for ctx cancellation and trigger shutdown.
	go func() {
		select {
		case <-ctx.Done():
			h.shutdown()
		case <-h.shutdownC:
		}
	}()

	// runAcceptLoop accepts connections until the listener closes. A listener
	// close is normal (shutdown or external) and is treated as success.
	h.runAcceptLoop()
	return nil
}

// runAcceptLoop runs the Accept loop until the listener closes or returns an
// error. Listener-close errors are swallowed; they signal normal shutdown.
func (h *host) runAcceptLoop() {
	for {
		conn, err := h.cfg.Listener.Accept()
		if err != nil {
			return
		}
		go h.handleConn(conn)
	}
}

// shutdown is idempotent: disposes the ConPTY, closes clients, closes the
// listener. Mirrors the pty-host.ts shutdown() function.
// ponytail: 50ms sleep after pty.Close() gives the OS ConPTY helper
// (conpty_console_list_agent.exe) time to release cleanly; avoids the
// 0x800700e8 error dialog on Windows.
func (h *host) shutdown() {
	h.shutdownOnce.Do(func() {
		close(h.shutdownC)

		// 1. Dispose the ConPTY first (critical ordering).
		_ = h.currentPTY().Close()

		// 2. Brief grace so the OS ConPTY helper can clean up.
		time.Sleep(50 * time.Millisecond)

		// 3. Close all client connections.
		h.mu.Lock()
		states := make([]*clientState, 0, len(h.clients))
		for c, cs := range h.clients {
			_ = c.Close()
			states = append(states, cs)
		}
		h.clients = make(map[net.Conn]*clientState)
		h.mu.Unlock()
		// Closing a conn does not wake a writer parked on an empty queue, and
		// a deliver parked in awaitCapacity would never be signalled either.
		for _, cs := range states {
			cs.closeOut()
		}

		// 4. Close the listener to unblock Accept.
		_ = h.cfg.Listener.Close()
	})
}

const (
	readBufferSize = 0x4_0000
	flushInterval  = time.Second / 60
)

// pumpPTY turns the PTY stream into coalesced client frames. A reader
// goroutine blocks on PTY.Read; this loop drains everything already available
// before deciding to flush. Idle traffic flushes immediately — the timer only
// arms when a flush already happened inside the current interval — so
// sustained load batches at 60Hz while a lone keystroke echo never waits.
func (h *host) pumpPTY() {
	h.mu.Lock()
	pty := h.pty
	done := h.pumpDone
	h.mu.Unlock()

	chunks := make(chan []byte, 64)
	go h.readPTY(pty, chunks)

	var pending []byte
	var lastFlush time.Time
	timer := time.NewTimer(time.Hour)
	if !timer.Stop() {
		<-timer.C
	}
	timerArmed := false

	flush := func() {
		if len(pending) == 0 {
			return
		}
		h.deliver(pending)
		pending = nil
		lastFlush = time.Now()
	}

	for {
		select {
		case chunk, ok := <-chunks:
			if !ok {
				flush()
				h.finishPump(pty, done)
				return
			}
			pending = append(pending, chunk...)
		drain:
			for len(pending) < readBufferSize {
				select {
				case more, ok := <-chunks:
					if !ok {
						flush()
						h.finishPump(pty, done)
						return
					}
					pending = append(pending, more...)
				default:
					break drain
				}
			}
			if len(pending) >= readBufferSize || time.Since(lastFlush) >= flushInterval {
				if timerArmed && !timer.Stop() {
					<-timer.C
				}
				timerArmed = false
				flush()
			} else if !timerArmed {
				timer.Reset(flushInterval - time.Since(lastFlush))
				timerArmed = true
			}
		case <-timer.C:
			timerArmed = false
			flush()
		}
	}
}

func (h *host) readPTY(pty ptyConn, chunks chan<- []byte) {
	defer close(chunks)
	buf := make([]byte, readBufferSize)
	for {
		n, err := pty.Read(buf)
		if n > 0 {
			chunk := make([]byte, n)
			copy(chunk, buf[:n])
			chunks <- chunk
		}
		if err != nil {
			return
		}
	}
}

// deliver is the single choke point later tasks extend: Task 7 appends the
// parser feed and Task 10 the capture tee — both strictly after the broadcast.
func (h *host) deliver(batch []byte) {
	// The ring append and the broadcast are one critical section, for the same
	// reason handleConn's snapshot and registration are: they are the two halves
	// of what a connecting client sees. Appending under a separate lock lets a
	// client snapshot the batch and then receive it again live, replaying the
	// whole coalesced batch — up to readBufferSize — as duplicate output the
	// moment it attaches.
	h.mu.Lock()
	h.cfg.Ring.Append(batch)
	var states []*clientState
	if frame, err := EncodeMessage(MsgTerminalData, batch); err == nil {
		states = h.broadcastLocked(frame)
	}
	h.mu.Unlock()

	// Back-pressure, off the lock. Queueing above cannot block, so a batch can
	// overshoot the cap by at most itself; parking here before the next batch
	// stalls pumpPTY, stops the PTY being read, and lets the child throttle
	// itself -- the chain the inline write provided, minus the frozen lock.
	for _, cs := range states {
		cs.awaitCapacity()
	}

	h.feedParser(batch)
	h.capture.write(batch)
}

const maxParserSliceBytes = 0x1_0000 // Warp's MAX_LOCKED_READ

// feedParser hands the batch to the passive parser in bounded slices. It runs
// after the client broadcast, never before: a slow or failing parser must not
// delay a single byte reaching the screen. Errors are dropped for the same
// reason -- a broken parser degrades GetOutput, it does not break the terminal.
func (h *host) feedParser(batch []byte) {
	parser := h.currentParser()
	if parser == nil {
		return
	}
	for offset := 0; offset < len(batch); offset += maxParserSliceBytes {
		end := min(offset+maxParserSliceBytes, len(batch))
		_ = parser.Feed(batch[offset:end])
	}
}

// finishPump runs once the pump's reader hits EOF (child exited, or its PTY
// was closed for a respawn): it drains the ring's partial line, broadcasts
// the dead status, and closes done so a waiting respawn (or nothing, on a
// real exit) knows nothing is reading pty any more.
func (h *host) finishPump(pty ptyConn, done chan struct{}) {
	<-pty.Done()
	h.cfg.Ring.FlushPartial()
	code, _ := pty.ExitCode()
	h.broadcast(statusFrame(false, pty.PID(), &code))
	close(done)
}

// broadcast queues msg to all connected clients.
func (h *host) broadcast(msg []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.broadcastLocked(msg)
}

// broadcastLocked is broadcast's body for callers already holding h.mu. It
// returns the clients it queued to so the caller can apply back-pressure after
// releasing the lock; a write failure retires the client from runWriter
// instead of here.
func (h *host) broadcastLocked(msg []byte) []*clientState {
	states := make([]*clientState, 0, len(h.clients))
	for _, cs := range h.clients {
		cs.enqueue(msg)
		states = append(states, cs)
	}
	return states
}

func (h *host) logf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "pty-host [%s]: "+format+"\n", append([]any{h.cfg.SessionID}, args...)...)
}

// sendTo queues msg to a single conn (best-effort; a conn already retired from
// the client set is a no-op, and a failing write retires it from runWriter).
func (h *host) sendTo(conn net.Conn, msg []byte) {
	h.mu.Lock()
	if cs := h.clients[conn]; cs != nil {
		cs.enqueue(msg)
	}
	h.mu.Unlock()
}

// handleConn manages the lifecycle of a single client connection.
func (h *host) handleConn(conn net.Conn) {
	// Scrollback replay: take the ring snapshot, queue it, and add the conn to
	// the broadcast set all under a SINGLE h.mu hold. deliver() also takes
	// h.mu, so it cannot interleave: any PTY chunk that arrives is either
	// already in this snapshot, or is queued strictly after the conn joins the
	// set. Doing this in two separate locks would let a chunk slip into the gap
	// (in neither the snapshot nor this client's broadcast) and be silently
	// dropped.
	//
	// The snapshot is queued, never written inline. It runs to MaxOutputLines
	// of output, which overruns the socket buffer; writing it here blocked
	// h.mu for the whole session and starved this connection's own read loop,
	// silently dropping the input of any client that writes without reading.
	// See clientState's out fields.
	cs := newClientState()
	h.mu.Lock()
	if snap := h.cfg.Ring.Snapshot(); len(snap) > 0 {
		if snapFrame, err := EncodeMessage(MsgTerminalData, snap); err == nil {
			cs.enqueue(snapFrame)
		}
	}
	h.clients[conn] = cs
	h.mu.Unlock()

	go h.runWriter(conn, cs)

	defer func() {
		h.mu.Lock()
		delete(h.clients, conn)
		// This client is gone; if it was the largest, let the grid shrink back to
		// the remaining largest client.
		h.applyLargestLocked()
		h.mu.Unlock()
		cs.closeOut()
		_ = conn.Close()
	}()

	parser := NewMessageParser(func(msgType byte, payload []byte) {
		h.handleClientMsg(conn, msgType, payload)
	})

	buf := make([]byte, 65536)
	for {
		n, err := conn.Read(buf)
		if n > 0 {
			parser.Feed(buf[:n])
		}
		if err != nil {
			return
		}
	}
}

// handleClientMsg dispatches a decoded client message. Mirrors handleClientMessage
// from pty-host.ts.
func (h *host) handleClientMsg(conn net.Conn, msgType byte, payload []byte) {
	switch msgType {
	case MsgTerminalInput:
		pty := h.currentPTY()
		if _, alive := pty.ExitCode(); !alive {
			_, _ = pty.Write(payload)
		}

	case MsgResize:
		if _, alive := h.currentPTY().ExitCode(); !alive {
			var rp ResizePayload
			if err := json.Unmarshal(payload, &rp); err == nil && rp.Cols > 0 && rp.Rows > 0 {
				// Record this client's requested grid, then size the shared PTY to
				// the largest client (see applyLargestLocked) rather than blindly
				// applying this one — otherwise a small viewer shrinks every viewer.
				h.mu.Lock()
				if cs := h.clients[conn]; cs != nil {
					cs.cols, cs.rows, cs.sized = rp.Cols, rp.Rows, true
				}
				h.applyLargestLocked()
				h.mu.Unlock()
			}
			// Malformed resize: ignore (matches TS behavior).
		}

	case MsgGetOutputReq:
		lines := 50 // default matches TS
		var req GetOutputReq
		if err := json.Unmarshal(payload, &req); err == nil && req.Lines > 0 {
			lines = req.Lines
		}
		var text string
		if parser := h.currentParser(); parser != nil {
			rendered, err := parser.RenderTail(lines)
			if err != nil {
				h.logf("render for GetOutput: %v", err)
			}
			text = rendered
		} else {
			text = h.cfg.Ring.Tail(lines)
		}
		if frame, err := EncodeMessage(MsgGetOutputRes, []byte(text)); err == nil {
			h.sendTo(conn, frame)
		}

	case MsgStyledOutputReq:
		lines := 50 // default matches TS
		var req GetOutputReq
		if err := json.Unmarshal(payload, &req); err == nil && req.Lines > 0 {
			lines = req.Lines
		}
		var text string
		if parser := h.currentParser(); parser != nil {
			rendered, err := parser.RenderStyledTail(lines)
			if err != nil {
				h.logf("render for GetStyledOutput: %v", err)
			}
			text = rendered
		}
		// No Parser means no styled-output source: the ring only ever kept
		// plain bytes, so there is no styled fallback to fall back to.
		if frame, err := EncodeMessage(MsgStyledOutputRes, []byte(text)); err == nil {
			h.sendTo(conn, frame)
		}

	case MsgCaptureStartReq:
		var req CaptureStartReq
		if err := json.Unmarshal(payload, &req); err == nil && len(req.Argv) > 0 {
			if err := h.capture.start(req.Argv); err != nil {
				h.logf("start capture: %v", err)
			}
		}

	case MsgCaptureStopReq:
		if err := h.capture.stop(); err != nil {
			h.logf("stop capture: %v", err)
		}

	case MsgCaptureStateReq:
		var alternateOn bool
		if parser := h.currentParser(); parser != nil {
			on, err := parser.AltActive()
			if err != nil {
				h.logf("alt active for CaptureState: %v", err)
			}
			alternateOn = on
		}
		state := CaptureStateRes{PipeOpen: h.capture.open(), AlternateOn: alternateOn}
		b, _ := json.Marshal(state)
		if frame, err := EncodeMessage(MsgCaptureStateRes, b); err == nil {
			h.sendTo(conn, frame)
		}

	case MsgStatusReq:
		pty := h.currentPTY()
		code, exited := pty.ExitCode()
		alive := !exited
		pid := pty.PID()
		var codePtr *int
		if exited {
			codePtr = &code
		}
		h.sendTo(conn, statusFrame(alive, pid, codePtr))

	case MsgKillReq:
		// Trigger graceful shutdown; returns immediately (idempotent).
		go h.shutdown()

	case MsgRespawnReq:
		h.handleRespawn(conn, payload)
	}
}

// statusFrame builds a MsgStatusRes frame.
func statusFrame(alive bool, pid int, exitCode *int) []byte {
	sp := StatusPayload{Alive: alive, PID: pid, ExitCode: exitCode}
	b, _ := json.Marshal(sp)
	frame, _ := EncodeMessage(MsgStatusRes, b) // b is small JSON, never overflows uint32
	return frame
}
