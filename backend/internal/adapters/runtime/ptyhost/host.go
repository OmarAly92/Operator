// Package conpty - host.go implements the serve engine for the pty-host
// detached process. It owns the agent's PTY (via the ptyConn seam), exposes
// it over a loopback TCP socket using the B1 binary protocol, replays
// scrollback to new clients, fans output to all connected clients, and shuts
// down gracefully (ConPTY dispose first, then clients, then listener).
//
// This file is cross-platform; only the real conptyConn impl is Windows-tagged.
package ptyhost

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
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
	Recorder    *recorder

	HistoryPath     string
	PersistInterval time.Duration
	HistoryMaxBytes int
}

// Serve runs the host event loop until the listener closes or Shutdown is
// invoked via the returned ShutdownFunc. It pumps PTY output into the ring
// and broadcasts to all clients, accepts new clients (replaying ring snapshot),
// and dispatches client messages. On PTY exit it broadcasts a status update
// but stays alive (keep-alive), so a client can still read the final screen.
// Returns when shut down.
func Serve(ctx context.Context, cfg ServeConfig) error {
	h := newHost(ctx, cfg)
	return h.run(ctx)
}

func newHost(ctx context.Context, cfg ServeConfig) *host {
	h := &host{
		cfg:       cfg,
		ctx:       ctx,
		clients:   make(map[net.Conn]*clientState),
		watchers:  make(map[net.Conn]*clientState),
		shutdownC: make(chan struct{}),
		capture:   &captureSink{},
		pty:       cfg.PTY,
		parser:    cfg.Parser,
		pumpDone:  make(chan struct{}),
		recorder:  cfg.Recorder,
	}
	h.readCond = sync.NewCond(&h.mu)
	return h
}

// clientState is the host's per-connection bookkeeping. cols/rows record the
// grid this client last asked for (sized reports whether it ever asked), so the
// host can size the shared PTY to the largest attached client (see
// applyLargestLocked). A connection that never sends a resize stays sized=false
// and never influences the shared grid.
type clientState struct {
	cols, rows   int
	sized        bool
	wantsHistory bool

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

	// Flow control. delivered counts every MsgTerminalData payload byte
	// enqueued for this client since it registered -- the replay frame and
	// the history chunks as well as the live batches, because the client acks
	// every byte it consumes. acked is what it has confirmed. A client that
	// has never acked is unlimited (everAcked false) so a client build that
	// predates acks keeps working.
	acked     int
	delivered int
	everAcked bool
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

// gone reports that this client's queue is finished, which is how every wait
// that outlives the connection -- awaitCapacity on outCond, awaitAckedHistory
// on readCond -- learns that its client left.
func (cs *clientState) gone() bool {
	cs.outMu.Lock()
	defer cs.outMu.Unlock()
	return cs.outDone
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

	recorder *recorder

	readCond   *sync.Cond
	readParked bool

	fedBytes       uint64
	persistMu      sync.Mutex
	persistedBytes uint64

	watchers   map[net.Conn]*clientState
	programGen uint32
	shownTitle string

	notifyWindowStart time.Time
	notifyCount       int
	appearance        *AppearancePayload
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
	h.applyLargestLocked(nil)
	h.mu.Unlock()
	if cs != nil {
		cs.closeOut()
	}
	// The broadcast comes AFTER closeOut: awaitAckedHistory parks on readCond
	// and leaves on cs.gone(), so a wake that precedes the flag never reaches
	// it and the history stream parks for the life of the process.
	h.mu.Lock()
	h.readCond.Broadcast()
	h.mu.Unlock()
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
//
// pending, when non-nil, is a connection that is not in h.clients yet and is
// counted as if it were. An attach has to settle the grid BEFORE it rewraps
// history and renders the replay, and it cannot register the connection that
// early without letting live output reach it ahead of its own replay frame.
func (h *host) applyLargestLocked(pending *clientState) {
	bestCols, bestRows, bestArea := 0, 0, 0
	for _, cs := range h.clients {
		if !cs.sized {
			continue
		}
		if area := cs.cols * cs.rows; area > bestArea {
			bestArea, bestCols, bestRows = area, cs.cols, cs.rows
		}
	}
	if pending != nil && pending.sized {
		if area := pending.cols * pending.rows; area > bestArea {
			bestCols, bestRows = pending.cols, pending.rows
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
		if replies := h.takeQueryRepliesLocked(); len(replies) > 0 {
			go func(pty ptyConn) { _, _ = pty.Write(replies) }(h.pty)
		}
	}
	h.recorder.resize(bestCols, bestRows)
}

// run is the main event loop.
func (h *host) run(ctx context.Context) error {
	// Pump PTY output to ring + broadcast.
	go h.pumpPTY()
	go h.runHistoryPersist()

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
		h.mu.Lock()
		h.readCond.Broadcast()
		h.mu.Unlock()
		h.persistHistory()

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
		for c, cs := range h.watchers {
			_ = c.Close()
			states = append(states, cs)
		}
		h.watchers = make(map[net.Conn]*clientState)
		h.mu.Unlock()
		// Closing a conn does not wake a writer parked on an empty queue, and
		// a deliver parked in awaitCapacity would never be signalled either.
		for _, cs := range states {
			cs.closeOut()
		}

		// 4. Close the listener to unblock Accept.
		_ = h.recorder.close()
		_ = h.cfg.Listener.Close()
	})
}

const (
	readBufferSize  = 0x4_0000
	flushInterval   = time.Second / 60
	syncHoldTimeout = 150 * time.Millisecond

	// Flow-control watermarks, from VS Code's
	// vscode/src/vs/platform/terminal/common/terminal.ts.
	readHighWatermark = 100_000
	readLowWatermark  = 5_000
)

var esuCSI = []byte("\x1b[?2026l")

// pumpPTY turns the PTY stream into coalesced client frames. A reader
// goroutine blocks on PTY.Read; this loop drains everything already available
// before deciding to flush. Idle traffic flushes immediately — the timer only
// arms when a flush already happened inside the current interval — so
// sustained load batches at 60Hz while a lone keystroke echo never waits. When
// the mirror reports that a batch ended inside a DEC 2026 synchronized block,
// the next flush waits for the terminator or syncHoldTimeout, so a frame is not
// split across two client messages more than once.
func (h *host) pumpPTY() {
	h.mu.Lock()
	pty := h.pty
	done := h.pumpDone
	h.mu.Unlock()

	chunks := make(chan []byte, 64)
	go h.readPTY(pty, chunks)

	var pending []byte
	var lastFlush time.Time
	var holdUntil time.Time
	timer := time.NewTimer(time.Hour)
	if !timer.Stop() {
		<-timer.C
	}
	timerArmed := false

	flush := func() {
		if len(pending) == 0 {
			return
		}
		if h.deliver(pending) {
			holdUntil = time.Now().Add(syncHoldTimeout)
		} else {
			holdUntil = time.Time{}
		}
		pending = nil
		lastFlush = time.Now()
	}
	holding := func() bool {
		return !holdUntil.IsZero() && time.Now().Before(holdUntil) &&
			len(pending) < readBufferSize && !bytes.Contains(pending, esuCSI)
	}
	arm := func(d time.Duration) {
		if timerArmed && !timer.Stop() {
			<-timer.C
		}
		timer.Reset(d)
		timerArmed = true
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
			if holding() {
				arm(time.Until(holdUntil))
			} else if len(pending) >= readBufferSize || time.Since(lastFlush) >= flushInterval {
				if timerArmed && !timer.Stop() {
					<-timer.C
				}
				timerArmed = false
				flush()
				if !holdUntil.IsZero() {
					arm(time.Until(holdUntil))
				}
			} else if !timerArmed {
				arm(flushInterval - time.Since(lastFlush))
			}
		case <-timer.C:
			timerArmed = false
			if holding() {
				arm(time.Until(holdUntil))
				continue
			}
			holdUntil = time.Time{}
			h.tickParser()
			flush()
			if !holdUntil.IsZero() {
				arm(time.Until(holdUntil))
			}
		}
	}
}

// awaitReadCapacity parks the PTY reader while the slowest acking CONNECTION
// is more than readHighWatermark bytes behind, and resumes it once that falls
// under readLowWatermark. A client that has never acked is not counted, so a
// client build without acks never throttles the child.
//
// A connection, not a client: the daemon may fan one pty-host attachment out
// to several mux clients, whose acks all land on the same counter
// (TERMINAL.md §5).
func (h *host) awaitReadCapacity() {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.unackedLocked() <= readHighWatermark {
		return
	}
	h.readParked = true
	for h.unackedLocked() > readLowWatermark && !h.stopping() {
		h.readCond.Wait()
	}
	h.readParked = false
}

func (h *host) unackedLocked() int {
	worst := 0
	for _, cs := range h.clients {
		if !cs.everAcked {
			continue
		}
		if behind := cs.delivered - cs.acked; behind > worst {
			worst = behind
		}
	}
	return worst
}

func (h *host) readPaused() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.readParked
}

func (h *host) readPTY(pty ptyConn, chunks chan<- []byte) {
	defer close(chunks)
	buf := make([]byte, readBufferSize)
	for {
		h.awaitReadCapacity()
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
func (h *host) deliver(batch []byte) bool {
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
	for _, cs := range states {
		cs.delivered += len(batch)
	}
	// The parser feed joins that critical section, strictly AFTER the
	// broadcast. It has to: the parser's grid is what handleConn replays to a
	// connecting client, so a batch that has left the ring but not yet reached
	// the parser is a batch a client registering in that window would see in
	// neither its replay nor its live stream. Feeding after the broadcast, and
	// before releasing the lock, keeps every byte in exactly one of the two.
	//
	// This costs the screen nothing: the batch is already queued to every
	// client, and runWriter drains those queues without h.mu.
	h.feedParserLocked(batch)
	h.fedBytes += uint64(len(batch))
	inSync := h.parserInSyncLocked()
	replies := h.takeQueryRepliesLocked()
	h.publishProgramLocked()
	pty := h.pty
	h.mu.Unlock()

	if len(replies) > 0 {
		_, _ = pty.Write(replies)
	}

	// Back-pressure, off the lock. Queueing above cannot block, so a batch can
	// overshoot the cap by at most itself; parking here before the next batch
	// stalls pumpPTY, stops the PTY being read, and lets the child throttle
	// itself -- the chain the inline write provided, minus the frozen lock.
	for _, cs := range states {
		cs.awaitCapacity()
	}

	h.capture.write(batch)
	h.recorder.write(batch)
	return inSync
}

func (h *host) takeQueryRepliesLocked() []byte {
	if h.parser == nil {
		return nil
	}
	replies, err := h.parser.TakeQueryReplies()
	if err != nil {
		return nil
	}
	return replies
}

func (h *host) parserInSyncLocked() bool {
	if h.parser == nil {
		return false
	}
	in, err := h.parser.InSync()
	return err == nil && in
}

func (h *host) tickParser() {
	if parser := h.currentParser(); parser != nil {
		_, _ = parser.Tick(time.Now().UnixMilli())
		h.mu.Lock()
		replies := h.takeQueryRepliesLocked()
		h.publishProgramLocked()
		pty := h.pty
		h.mu.Unlock()
		if len(replies) > 0 {
			_, _ = pty.Write(replies)
		}
	}
}

const maxParserSliceBytes = 0x1_0000 // Warp's MAX_LOCKED_READ

// feedParserLocked hands the batch to the passive parser in bounded slices.
// It runs after the client broadcast, never before: a slow or failing parser
// must not delay a single byte reaching the screen. Errors are dropped for the
// same reason -- a broken parser degrades GetOutput and attach replay, it does
// not break the terminal. Callers must hold h.mu.
func (h *host) feedParserLocked(batch []byte) {
	parser := h.parser
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

// openingGridWait bounds how long a new connection is given to state its grid
// before it is replayed at the host's current one. Attach sends that resize as
// its first frame on a loopback socket, so the wait is normally microseconds;
// the deadline only covers a client that connects and says nothing.
const openingGridWait = 250 * time.Millisecond

// framedMsg is a decoded client frame held back until the connection is
// registered, so nothing read while waiting for the opening grid is lost.
type framedMsg struct {
	typ     byte
	payload []byte
}

// handleConn manages the lifecycle of a single client connection.
func (h *host) handleConn(conn net.Conn) {
	cs := newClientState()

	// Phase 1: the opening grid. A replay only reproduces the pane at the
	// geometry it was rendered for, so the client's grid has to reach the PTY
	// and the parser BEFORE the snapshot is taken. Applying it afterwards is
	// what produced the duplicated screen on reopening a session: the client
	// got a paint at the old geometry, then the child's SIGWINCH repaint of
	// the same screen at the new one, and the second could not overwrite the
	// first.
	//
	// Frames read here are held back rather than handled: the connection is
	// not in h.clients yet, so a reply would be queued nowhere.
	var (
		opening    *ResizePayload
		deferred   []framedMsg
		registered bool
	)
	parser := NewMessageParser(func(msgType byte, payload []byte) {
		if registered {
			h.handleClientMsg(conn, msgType, payload)
			return
		}
		if msgType == MsgResize && opening == nil {
			var rp ResizePayload
			if err := json.Unmarshal(payload, &rp); err == nil && rp.Cols > 0 && rp.Rows > 0 {
				opening = &rp
				return
			}
		}
		deferred = append(deferred, framedMsg{typ: msgType, payload: append([]byte(nil), payload...)})
	})

	buf := make([]byte, 65536)
	var readErr error
	_ = conn.SetReadDeadline(time.Now().Add(openingGridWait))
	for opening == nil && len(deferred) == 0 {
		n, err := conn.Read(buf)
		if n > 0 {
			parser.Feed(buf[:n])
		}
		if err != nil {
			readErr = err
			break
		}
	}
	_ = conn.SetReadDeadline(time.Time{})
	if readErr != nil && !errors.Is(readErr, os.ErrDeadlineExceeded) {
		// The connection died before it was ever registered; there is nothing
		// to unwind.
		_ = conn.Close()
		return
	}
	if opening == nil && len(deferred) > 0 && deferred[0].typ == MsgWatchReq {
		h.serveWatcher(conn, cs, buf)
		return
	}

	// Phase 2: apply the grid, render the replay, and join the broadcast set
	// under a SINGLE h.mu hold. deliver() takes h.mu and feeds the parser
	// under it, so any PTY chunk is either already in this replay or is queued
	// strictly after the conn joins the set. Doing this in two separate locks
	// would let a chunk slip into the gap -- in neither the replay nor this
	// client's broadcast -- and be silently dropped.
	//
	// The replay is queued, never written inline. It runs to MaxOutputLines of
	// output, which overruns the socket buffer; writing it here blocked h.mu
	// for the whole session and starved this connection's own read loop,
	// silently dropping the input of any client that writes without reading.
	// See clientState's out fields.
	if opening != nil {
		cs.cols, cs.rows, cs.sized = opening.Cols, opening.Rows, true
		cs.wantsHistory = opening.History
	}

	// The rewrap runs off the lock (it can walk 200k rows) and before the frame
	// is rendered: the mirror rewraps only its hot window on resize, and a chunk
	// built off a row still cut at the old width loses its tail to clip_row. It
	// has to happen BEFORE the origin is rendered, because rewrapping changes
	// how many rows history holds (TERMINAL.md §4.20).
	//
	// The grid is settled first, with this connection counted before it is
	// registered: applying it afterwards resizes the parser, and every resize
	// re-marks the rows below the hot window stale at the old width, undoing
	// the rewrap. The loop re-runs both if another client moved the grid while
	// the rewrap was off the lock, so that by the time the replay is rendered
	// the rewrap it is numbered against is still valid.
	var origin uint64
	for {
		h.mu.Lock()
		h.applyLargestLocked(cs)
		gridCols, gridRows := h.curCols, h.curRows
		h.mu.Unlock()

		if cs.wantsHistory {
			if parser := h.currentParser(); parser != nil {
				if err := parser.TouchHistory(); err != nil {
					h.logf("rewrap attach history: %v", err)
				}
			}
		}

		h.mu.Lock()
		h.clients[conn] = cs
		h.applyLargestLocked(nil)
		if h.curCols != gridCols || h.curRows != gridRows {
			delete(h.clients, conn)
			h.mu.Unlock()
			continue
		}
		var frame []byte
		frame, origin = h.replayFrameLocked()
		if frame != nil {
			cs.enqueue(frame)
			cs.delivered += len(frame) - frameHeaderBytes
		}
		h.mu.Unlock()
		break
	}
	registered = true

	go h.runWriter(conn, cs)

	if cs.wantsHistory {
		go h.streamHistory(cs, origin)
	} else if opening != nil {
		h.sendOlderMark(cs)
	}

	defer func() {
		cs.closeOut()
		h.mu.Lock()
		delete(h.clients, conn)
		// This client is gone; if it was the largest, let the grid shrink back to
		// the remaining largest client.
		h.applyLargestLocked(nil)
		h.readCond.Broadcast()
		h.mu.Unlock()
		_ = conn.Close()
	}()

	for _, msg := range deferred {
		h.handleClientMsg(conn, msg.typ, msg.payload)
	}

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

// replayFrameLocked builds the frame a newly registered client is sent to
// bring it to the pane's current state. It renders the PARSER'S GRID, not the
// output ring.
//
// The ring is a byte log, and a byte log only reproduces a screen when it is
// replayed into the exact geometry that produced it. Anywhere else, a TUI's
// in-place redraws (cursor-up N, erase, rewrite) land on the wrong rows, so
// every frame the child ever drew survives instead of overwriting its
// predecessor -- which is what stacked several mangled copies of an agent's UI
// on top of each other when an old session was reopened at a new window size.
// A grid repaint carries no such assumption: it is rendered for the geometry
// the client just asked for.
//
// A parser render error yields NO replay rather than a ring fallback: falling
// back would reintroduce, through the side door, the exact divergence the
// parser exists to remove. The ring stays the replay source only for a host
// whose parser never started at all. Callers must hold h.mu.
func (h *host) replayFrameLocked() ([]byte, uint64) {
	var payload []byte
	if h.parser != nil {
		_, _ = h.parser.Tick(time.Now().UnixMilli())
		rendered, err := h.parser.Replay(MaxOutputLines)
		if err != nil {
			h.logf("render attach replay: %v", err)
			return nil, vtwasm.HistoryBefore
		}
		payload = []byte(rendered)
	} else {
		payload = h.cfg.Ring.Snapshot()
	}
	if len(payload) == 0 {
		return nil, vtwasm.HistoryBefore
	}
	frame, err := EncodeMessage(MsgTerminalData, payload)
	if err != nil {
		h.logf("encode attach replay: %v", err)
		return nil, vtwasm.HistoryBefore
	}
	return frame, replayOrigin(payload)
}

const originMarkPrefix = "\x1b]7000;v=1;origin="

// replayOrigin reads back the stable row the frame just declared. It is the
// only number a history stream for this client may start from; see
// streamHistory. A ring fallback carries no origin mark, and its client is not
// running a core that could adopt one.
func replayOrigin(payload []byte) uint64 {
	if !bytes.HasPrefix(payload, []byte(originMarkPrefix)) {
		return vtwasm.HistoryBefore
	}
	end := bytes.Index(payload, []byte("\x1b\\"))
	if end < len(originMarkPrefix) {
		return vtwasm.HistoryBefore
	}
	origin, err := strconv.ParseUint(string(payload[len(originMarkPrefix):end]), 10, 64)
	if err != nil {
		return vtwasm.HistoryBefore
	}
	return origin
}

func (h *host) stopping() bool {
	select {
	case <-h.shutdownC:
		return true
	default:
		return false
	}
}

// streamHistory queues the session's scrollback newest→oldest, behind the
// replay frame the client was already queued. It runs off h.mu: these rows
// are older than every byte in that frame, so nothing can race into the gap
// the way a live chunk could between the replay and registration.
//
// It paces on the SAME ack watermark deliver uses, so a 200k-row history sent
// to one client can never push that client past readHighWatermark and pause
// the child for every other attached pane (Task 10).
//
// `before` is the origin the replay frame already told THIS client, captured
// from the same render under the same h.mu hold. Letting the mirror re-derive
// it from a later snapshot would miss any row the child completed in between,
// and the receiver rejects a chunk whose bound is off by even one row -- every
// chunk after it too, silently (TERMINAL.md §4.21).
func (h *host) streamHistory(cs *clientState, before uint64) {
	parser := h.currentParser()
	if parser == nil {
		return
	}
	for {
		if h.stopping() || cs.gone() {
			return
		}
		chunk, next, ok, err := parser.HistoryChunk(before, MaxOutputLines, vtwasm.HistoryChunkRows)
		if err != nil {
			h.logf("stream attach history: %v", err)
			return
		}
		if !ok {
			h.sendOlderMark(cs)
			return
		}
		frame, err := EncodeMessage(MsgTerminalData, []byte(chunk))
		if err != nil {
			h.logf("encode attach history: %v", err)
			return
		}
		h.mu.Lock()
		cs.enqueue(frame)
		cs.delivered += len(chunk)
		h.mu.Unlock()
		cs.awaitCapacity()
		h.awaitAckedHistory(cs)
		before = next
	}
}

// awaitAckedHistory parks the history stream while this client is more than
// readLowWatermark bytes behind its own acks. A client that never acks is
// paced by awaitCapacity alone, exactly as it is today.
func (h *host) awaitAckedHistory(cs *clientState) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for cs.everAcked && cs.delivered-cs.acked > readLowWatermark && !h.stopping() && !cs.gone() {
		h.readCond.Wait()
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
				h.applyLargestLocked(nil)
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

	case MsgAppearance:
		h.handleAppearance(payload)

	case MsgOlderReq:
		var req OlderReq
		if err := json.Unmarshal(payload, &req); err == nil {
			h.serveOlder(conn, req.Before)
		}

	case MsgAck:
		var ack AckPayload
		if err := json.Unmarshal(payload, &ack); err != nil || ack.Bytes < 0 {
			return
		}
		h.mu.Lock()
		if cs := h.clients[conn]; cs != nil {
			cs.everAcked = true
			if ack.Bytes > cs.acked {
				cs.acked = ack.Bytes
			}
			if cs.acked > cs.delivered {
				cs.acked = cs.delivered
			}
		}
		h.readCond.Broadcast()
		h.mu.Unlock()
	}
}

// statusFrame builds a MsgStatusRes frame.
func statusFrame(alive bool, pid int, exitCode *int) []byte {
	sp := StatusPayload{Alive: alive, PID: pid, ExitCode: exitCode}
	b, _ := json.Marshal(sp)
	frame, _ := EncodeMessage(MsgStatusRes, b) // b is small JSON, never overflows uint32
	return frame
}
