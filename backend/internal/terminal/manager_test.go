package terminal

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/cdc"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
)

// fakeConn is an in-memory wsConn driven by channels.
type fakeConn struct {
	in     chan clientMsg
	out    chan serverMsg
	pings  int32
	once   sync.Once
	closed chan struct{}
}

func newFakeConn() *fakeConn {
	return &fakeConn{in: make(chan clientMsg, 16), out: make(chan serverMsg, 64), closed: make(chan struct{})}
}

func (c *fakeConn) ReadJSON(ctx context.Context, v any) error {
	select {
	case m := <-c.in:
		*(v.(*clientMsg)) = m
		return nil
	case <-ctx.Done():
		return ctx.Err()
	case <-c.closed:
		return context.Canceled
	}
}

func (c *fakeConn) WriteJSON(_ context.Context, v any) error {
	c.out <- v.(serverMsg)
	return nil
}

func (c *fakeConn) Ping(context.Context) error {
	atomic.AddInt32(&c.pings, 1)
	return nil
}

func (c *fakeConn) Close(string) error {
	c.once.Do(func() { close(c.closed) })
	return nil
}

// recv waits for a frame of the given channel+type, draining others.
func recv(t *testing.T, c *fakeConn, ch, typ string, d time.Duration) serverMsg {
	t.Helper()
	deadline := time.After(d)
	for {
		select {
		case m := <-c.out:
			if m.Ch == ch && m.Type == typ {
				return m
			}
		case <-deadline:
			t.Fatalf("did not receive %s/%s within %s", ch, typ, d)
		}
	}
}

func TestServeOpenStreamsAndWritesTerminal(t *testing.T) {
	pty := newFakePTY()
	sp := &fakeSpawner{ptys: []*fakePTY{pty}}
	src := &fakeSource{alive: true, spawner: sp}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()

	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	recv(t, conn, chTerminal, msgOpened, time.Second)

	pty.push([]byte("prompt$ "))
	data := recv(t, conn, chTerminal, msgData, time.Second)
	got, _ := base64.StdEncoding.DecodeString(data.Data)
	if string(got) != "prompt$ " {
		t.Fatalf("streamed data = %q", got)
	}

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgData, Data: base64.StdEncoding.EncodeToString([]byte("whoami\n"))}
	eventually(t, time.Second, func() bool { return string(pty.writtenBytes()) == "whoami\n" })

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgResize, Rows: 30, Cols: 100}
	eventually(t, time.Second, func() bool {
		rs := pty.resizeCalls()
		return len(rs) == 1 && rs[0] == [2]uint16{30, 100}
	})
}

type fixedSessionInputLease bool

func (l fixedSessionInputLease) AcquireSessionInput(domain.SessionID) (func(), bool) {
	if !l {
		return nil, false
	}
	return func() {}, true
}

type observedTerminalInputLease struct {
	acquired chan struct{}
	released chan struct{}
}

func (l *observedTerminalInputLease) AcquireSessionInput(domain.SessionID) (func(), bool) {
	close(l.acquired)
	return func() { close(l.released) }, true
}

func TestServeRejectsTerminalInputWhileSessionGateIsClosed(t *testing.T) {
	pty := newFakePTY()
	src := &fakeSource{alive: true, spawner: &fakeSpawner{ptys: []*fakePTY{pty}}}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	mgr.SetSessionInputLease(fixedSessionInputLease(false))
	defer mgr.Close()

	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chTerminal, ID: "worker-1", Type: msgOpen}
	recv(t, conn, chTerminal, msgOpened, time.Second)
	conn.in <- clientMsg{Ch: chTerminal, ID: "worker-1", Type: msgData, Data: base64.StdEncoding.EncodeToString([]byte("unsafe\n"))}
	errFrame := recv(t, conn, chTerminal, msgError, time.Second)
	if errFrame.ID != "worker-1" || errFrame.Error == "" {
		t.Fatalf("error frame = %#v", errFrame)
	}
	time.Sleep(20 * time.Millisecond)
	if got := string(pty.writtenBytes()); got != "" {
		t.Fatalf("blocked input reached PTY: %q", got)
	}
}

func TestServeHoldsSessionInputLeaseThroughPTYWrite(t *testing.T) {
	pty := newFakePTY()
	pty.writeStarted = make(chan struct{}, 1)
	pty.writeUnblock = make(chan struct{})
	src := &fakeSource{alive: true, spawner: &fakeSpawner{ptys: []*fakePTY{pty}}}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	lease := &observedTerminalInputLease{acquired: make(chan struct{}), released: make(chan struct{})}
	mgr.SetSessionInputLease(lease)
	defer mgr.Close()

	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chTerminal, ID: "worker-1", Type: msgOpen}
	recv(t, conn, chTerminal, msgOpened, time.Second)
	conn.in <- clientMsg{Ch: chTerminal, ID: "worker-1", Type: msgData, Data: base64.StdEncoding.EncodeToString([]byte("status\n"))}

	select {
	case <-lease.acquired:
	case <-time.After(time.Second):
		t.Fatal("input lease was not acquired")
	}
	select {
	case <-pty.writeStarted:
	case <-time.After(time.Second):
		t.Fatal("PTY write did not start")
	}
	select {
	case <-lease.released:
		t.Fatal("input lease released before PTY write returned")
	default:
	}
	close(pty.writeUnblock)
	select {
	case <-lease.released:
	case <-time.After(time.Second):
		t.Fatal("input lease was not released after PTY write")
	}
	eventually(t, time.Second, func() bool { return string(pty.writtenBytes()) == "status\n" })
}

func TestServeBuffersInputUntilAttachReady(t *testing.T) {
	pty := newFakePTY()
	spawnStarted := make(chan struct{})
	releaseSpawn := make(chan struct{})
	src := &fakeSource{alive: true, attachFn: func(context.Context, uint16, uint16) (ports.Stream, error) {
		close(spawnStarted)
		<-releaseSpawn
		return pty, nil
	}}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	lease := &observedTerminalInputLease{acquired: make(chan struct{}), released: make(chan struct{})}
	mgr.SetSessionInputLease(lease)
	defer mgr.Close()

	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	select {
	case <-spawnStarted:
	case <-time.After(time.Second):
		t.Fatal("spawn was not reached")
	}
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgData, Data: base64.StdEncoding.EncodeToString([]byte("status\n"))}
	select {
	case <-lease.acquired:
	case <-time.After(time.Second):
		t.Fatal("buffered input did not acquire a lease")
	}
	select {
	case <-lease.released:
		t.Fatal("buffered input released its lease before the pending PTY write")
	default:
	}
	close(releaseSpawn)

	recv(t, conn, chTerminal, msgOpened, time.Second)
	eventually(t, time.Second, func() bool { return string(pty.writtenBytes()) == "status\n" })
	select {
	case <-lease.released:
	case <-time.After(time.Second):
		t.Fatal("buffered input lease was not released after PTY write")
	}
}

func TestBeginInputDrainBlocksMuxWritesUntilReleased(t *testing.T) {
	pty := newFakePTY()
	mgr := NewManager(&fakeSource{alive: true, spawner: &fakeSpawner{ptys: []*fakePTY{pty}}}, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()

	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	recv(t, conn, chTerminal, msgOpened, time.Second)
	_, release := mgr.BeginInputDrain("t1")
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgData, Data: base64.StdEncoding.EncodeToString([]byte("lost work\n"))}
	// The pong proves the sequential read loop has already handled the data frame.
	conn.in <- clientMsg{Ch: chSystem, Type: msgPing}
	recv(t, conn, chSystem, msgPong, time.Second)
	if got := string(pty.writtenBytes()); got != "" {
		t.Fatalf("blocked terminal wrote %q", got)
	}

	release()
	release() // release is safe under duplicate cleanup paths.
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgData, Data: base64.StdEncoding.EncodeToString([]byte("allowed\n"))}
	eventually(t, time.Second, func() bool { return string(pty.writtenBytes()) == "allowed\n" })
}

func TestBeginInputDrainReturnsTheLastAcceptedWriteBarrier(t *testing.T) {
	pty := newFakePTY()
	mgr := NewManager(&fakeSource{alive: true, spawner: &fakeSpawner{ptys: []*fakePTY{pty}}}, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()

	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	recv(t, conn, chTerminal, msgOpened, time.Second)
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgData, Data: base64.StdEncoding.EncodeToString([]byte("before\n"))}
	eventually(t, time.Second, func() bool { return string(pty.writtenBytes()) == "before\n" })

	first, release := mgr.BeginInputDrain("t1")
	if first.IsZero() {
		t.Fatal("accepted input did not produce a drain barrier")
	}
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgData, Data: base64.StdEncoding.EncodeToString([]byte("blocked\n"))}
	conn.in <- clientMsg{Ch: chSystem, Type: msgPing}
	recv(t, conn, chSystem, msgPong, time.Second)
	release()

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgData, Data: base64.StdEncoding.EncodeToString([]byte("after\n"))}
	eventually(t, time.Second, func() bool { return string(pty.writtenBytes()) == "before\nafter\n" })
	second, releaseSecond := mgr.BeginInputDrain("t1")
	defer releaseSecond()
	if !second.After(first) {
		t.Fatalf("second barrier = %s, want after first %s", second, first)
	}
}

// nextTerminal returns the next frame on conn.out (no skipping), so callers can
// assert frame ordering rather than just presence.
func nextTerminal(t *testing.T, c *fakeConn) serverMsg {
	t.Helper()
	select {
	case m := <-c.out:
		return m
	case <-time.After(time.Second):
		t.Fatal("no frame within 1s")
		return serverMsg{}
	}
}

// Opening a pane whose runtime is already dead must report exited without
// spawning an attach. The conn entry still has to clear so a later open for the
// same id on this connection is served instead of being silently dropped by the
// already-open guard.
func TestServeOpenDeadRuntimeReportsExitedAndAllowsReopen(t *testing.T) {
	sp := &fakeSpawner{ptys: []*fakePTY{newFakePTY()}}
	src := &fakeSource{alive: false, spawner: sp}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()

	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	if m := nextTerminal(t, conn); m.Type != msgExited {
		t.Fatalf("first frame = %q, want exited", m.Type)
	}
	if got := sp.calls(); got != 0 {
		t.Fatalf("attach must never run against a dead runtime, got %d attaches", got)
	}

	src.setAlive(true)
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	if m := nextTerminal(t, conn); m.Type != msgOpened {
		t.Fatalf("re-open frame = %q, want opened (open was dropped, entry stuck)", m.Type)
	}
}

// A session that exits after being opened must clear its connection entry on
// exit, so a later open for the same id is served rather than dropped by the
// already-open guard.
func TestServeExitAfterOpenClearsEntryAllowingReopen(t *testing.T) {
	p := newFakePTY()
	sp := &fakeSpawner{ptys: []*fakePTY{p}}
	src := &fakeSource{alive: true, spawner: sp} // alive for the first attach
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()

	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	recv(t, conn, chTerminal, msgOpened, time.Second)

	src.setAlive(false) // a dropped pty must not re-attach -> session exits
	p.Close()           // drop the pty; IsAlive false => session exits, no re-attach
	recv(t, conn, chTerminal, msgExited, time.Second)

	src.setAlive(true)
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	recv(t, conn, chTerminal, msgOpened, 2*time.Second)
}

// An attachment that exits the moment it is opened (dead runtime) fires onExit
// from its run goroutine, racing the reopen that follows the exited frame. The
// identity-guarded delete in onExit must never evict a successor attachment
// registered under the same id: every reopen must be served (exited again for a
// still-dead runtime), never silently dropped by the already-open guard.
// Stressed across many iterations
// to shake the exit/reopen interleavings out.
func TestServeReopenAfterImmediateExitNeverStuck(t *testing.T) {
	for i := 0; i < 400; i++ {
		sp := &fakeSpawner{}
		src := &fakeSource{spawner: sp}
		src.setAlive(false) // dead runtime -> the open exits without attaching
		mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))

		conn := newFakeConn()
		ctx, cancel := context.WithCancel(context.Background())
		go mgr.Serve(ctx, conn)

		conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}

		recv(t, conn, chTerminal, msgExited, time.Second)

		// The reopen must be served even while the first open's exit teardown is
		// still in flight.
		conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
		recv(t, conn, chTerminal, msgExited, time.Second)

		cancel()
		mgr.Close()
	}
}

func TestServeRejectsOpenWithoutID(t *testing.T) {
	mgr := NewManager(&fakeSource{}, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chTerminal, Type: msgOpen}
	msg := recv(t, conn, chTerminal, msgError, time.Second)
	if msg.Error == "" {
		t.Fatal("expected an error message for open without id")
	}
}

func TestServeForwardsSessionChannelFromCDC(t *testing.T) {
	bc := cdc.NewBroadcaster()
	mgr := NewManager(&fakeSource{}, bc, testLogger(), WithHeartbeat(0))
	defer mgr.Close()

	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chSubscribe, Type: msgSubscribe}
	// Give the subscription time to register before publishing.
	eventually(t, time.Second, func() bool {
		bc.Publish(cdc.Event{Seq: 9, ProjectID: "p1", SessionID: "s1", Type: cdc.EventSessionUpdated})
		select {
		case m := <-conn.out:
			return m.Ch == chSessions && m.Session != nil && m.Session.Seq == 9
		default:
			return false
		}
	})
}

func TestServeSystemPingGetsPong(t *testing.T) {
	mgr := NewManager(&fakeSource{}, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chSystem, Type: msgPing}
	recv(t, conn, chSystem, msgPong, time.Second)
}

func TestServeHeartbeatPings(t *testing.T) {
	mgr := NewManager(&fakeSource{}, nil, testLogger(), WithHeartbeat(10*time.Millisecond))
	defer mgr.Close()
	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	eventually(t, time.Second, func() bool { return atomic.LoadInt32(&conn.pings) >= 2 })
}

func TestServeClosesConnOnReadEnd(t *testing.T) {
	mgr := NewManager(&fakeSource{}, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	go mgr.Serve(ctx, conn)

	cancel() // client/server context ends
	select {
	case <-conn.closed:
	case <-time.After(time.Second):
		t.Fatal("Serve must close the conn when the context is cancelled")
	}
}

// Each connection opening the same pane gets its OWN attach PTY — that is the
// per-client model: the runtime replays its init handshake + full repaint to every
// fresh attach, so no client depends on bytes another client consumed. Output
// pushed to one client's PTY must reach only that client, and closing one
// client's terminal must not touch the other's PTY.
func TestServePerClientAttachIsolation(t *testing.T) {
	p1, p2 := newFakePTY(), newFakePTY()
	sp := &fakeSpawner{ptys: []*fakePTY{p1, p2}}
	src := &fakeSource{alive: true, spawner: sp}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()

	connA, connB := newFakeConn(), newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, connA)
	go mgr.Serve(ctx, connB)

	connA.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	recv(t, connA, chTerminal, msgOpened, time.Second)
	eventually(t, time.Second, func() bool { return sp.calls() == 1 })

	connB.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	recv(t, connB, chTerminal, msgOpened, time.Second)
	eventually(t, time.Second, func() bool { return sp.calls() == 2 })

	// The runtime fans output out per attach; here each fake PTY stands in for one
	// attach process, so its bytes must reach exactly its own connection.
	p1.push([]byte("for-A"))
	data := recv(t, connA, chTerminal, msgData, time.Second)
	got, _ := base64.StdEncoding.DecodeString(data.Data)
	if string(got) != "for-A" {
		t.Fatalf("conn A data = %q", got)
	}
	select {
	case m := <-connB.out:
		t.Fatalf("conn B received %s/%s for conn A's PTY output", m.Ch, m.Type)
	default:
	}

	// Closing A's terminal detaches A only: B's PTY stays live.
	connA.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgClose}
	eventually(t, time.Second, func() bool {
		select {
		case <-p1.closed:
			return true
		default:
			return false
		}
	})
	select {
	case <-p2.closed:
		t.Fatal("closing conn A's terminal must not close conn B's PTY")
	default:
	}
}

// The open frame carries the client's grid; the PTY must start at that size
// rather than the kernel default, even though the attach is asynchronous.
func TestServeOpenAppliesInitialSize(t *testing.T) {
	pty := newFakePTY()
	sp := &fakeSpawner{ptys: []*fakePTY{pty}}
	src := &fakeSource{alive: true, spawner: sp}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()

	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen, Rows: 40, Cols: 120}
	recv(t, conn, chTerminal, msgOpened, time.Second)
	eventually(t, time.Second, func() bool {
		rs := pty.resizeCalls()
		return len(rs) == 1 && rs[0] == [2]uint16{40, 120}
	})
}

func TestServeDeduplicatesResizeUnlessExplicitlyForced(t *testing.T) {
	pty := newFakePTY()
	sp := &fakeSpawner{ptys: []*fakePTY{pty}}
	src := &fakeSource{alive: true, spawner: sp}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()

	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen, Rows: 40, Cols: 120}
	recv(t, conn, chTerminal, msgOpened, time.Second)
	eventually(t, time.Second, func() bool { return len(pty.resizeCalls()) == 1 })

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgResize, Rows: 40, Cols: 120}
	conn.in <- clientMsg{Ch: chSystem, Type: msgPing}
	recv(t, conn, chSystem, msgPong, time.Second)
	if got := len(pty.resizeCalls()); got != 1 {
		t.Fatalf("duplicate normal resize calls = %d, want 1", got)
	}

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgResize, Rows: 40, Cols: 120, Force: true}
	eventually(t, time.Second, func() bool { return len(pty.resizeCalls()) == 2 })
}

// A primary and a secondary client share one PTY: the primary drives the grid,
// the secondary is told the primary's grid (not its own) and its attach Stream is
// sized to it, and when the primary leaves the grid falls back to the secondary.
// This is the multi-client sizing that keeps a phone from stripping down the
// desktop while keeping both clients' grids matched to the single PTY.
func TestServePrimaryDrivesSharedGridSecondaryFollows(t *testing.T) {
	p1, p2 := newFakePTY(), newFakePTY()
	sp := &fakeSpawner{ptys: []*fakePTY{p1, p2}}
	src := &fakeSource{alive: true, spawner: sp}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()

	primary, secondary := newFakeConn(), newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, primary)
	go mgr.Serve(ctx, secondary)

	// Primary opens at 120x40 and drives the shared grid.
	primary.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen, Cols: 120, Rows: 40}
	if r := recv(t, primary, chTerminal, msgResize, time.Second); r.Cols != 120 || r.Rows != 40 {
		t.Fatalf("primary grid = %dx%d, want 120x40", r.Cols, r.Rows)
	}

	// Secondary opens smaller; it must be told the primary's grid, not its own,
	// and its own attach Stream must start at the primary's grid (not 55x48).
	secondary.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen, Cols: 55, Rows: 48, Role: roleSecondary}
	if r := recv(t, secondary, chTerminal, msgResize, time.Second); r.Cols != 120 || r.Rows != 40 {
		t.Fatalf("secondary follows grid = %dx%d, want the primary's 120x40", r.Cols, r.Rows)
	}
	eventually(t, time.Second, func() bool {
		s := sp.spawnSizes()
		return len(s) == 2 && s[1] == [2]uint16{40, 120}
	})
	eventually(t, time.Second, func() bool {
		return len(p1.resizeCalls()) > 0 && len(p2.resizeCalls()) > 0
	})
	primaryResizeCount, secondaryResizeCount := len(p1.resizeCalls()), len(p2.resizeCalls())

	// A secondary may change its local viewport, but while the primary still
	// drives the same 120x40 authoritative grid that must not re-signal either PTY.
	secondary.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgResize, Cols: 60, Rows: 50}
	secondary.in <- clientMsg{Ch: chSystem, Type: msgPing}
	recv(t, secondary, chSystem, msgPong, time.Second)
	if got := len(p1.resizeCalls()); got != primaryResizeCount {
		t.Fatalf("primary resize calls after secondary-only change = %d, want %d", got, primaryResizeCount)
	}
	if got := len(p2.resizeCalls()); got != secondaryResizeCount {
		t.Fatalf("secondary resize calls under unchanged shared grid = %d, want %d", got, secondaryResizeCount)
	}

	// Primary leaves: the grid falls back to the secondary's own size.
	primary.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgClose}
	if r := recv(t, secondary, chTerminal, msgResize, 2*time.Second); r.Cols != 60 || r.Rows != 50 {
		t.Fatalf("after primary left, grid = %dx%d, want the secondary's 60x50", r.Cols, r.Rows)
	}
}

// Manager.Close must kill every live attach PTY: a PTY left open keeps its
// attach process running and deadlocks daemon shutdown.
func TestManagerCloseKillsLiveAttachments(t *testing.T) {
	pty := newFakePTY()
	sp := &fakeSpawner{ptys: []*fakePTY{pty}}
	src := &fakeSource{alive: true, spawner: sp}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))

	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	recv(t, conn, chTerminal, msgOpened, time.Second)
	eventually(t, time.Second, func() bool { return sp.calls() == 1 })

	mgr.Close()
	select {
	case <-pty.closed:
	case <-time.After(time.Second):
		t.Fatal("Manager.Close must close live attach PTYs")
	}
}

func TestEnqueueOverflowCancelsConn(t *testing.T) {
	cancelled := make(chan struct{})
	c := &connState{
		out:    make(chan serverMsg, 1),
		cancel: func() { close(cancelled) },
		terms:  map[string]*attachment{},
	}
	c.enqueue(serverMsg{Ch: chTerminal, Type: msgData}) // fills buffer
	c.enqueue(serverMsg{Ch: chTerminal, Type: msgData}) // overflow -> cancel
	select {
	case <-cancelled:
	case <-time.After(time.Second):
		t.Fatal("overflow must cancel the connection")
	}
}

// A desktop in Blocks holds no terminal attachment, so it is in no members map.
// The phone in Raw then becomes the only viewer rendering a grid, and the PTY
// must follow it. This inverts the usual rule that a primary outranks a larger
// secondary, and it is the behaviour the block screen depends on.
func TestGridFollowsTheSoleSecondaryWhenNoPrimaryIsAttached(t *testing.T) {
	desktop := &connState{}
	phone := &connState{}

	both := map[*connState]*termMember{
		desktop: {cols: 80, rows: 24, primary: true},
		phone:   {cols: 100, rows: 40},
	}
	if cols, rows := largestGrid(both); cols != 80 || rows != 24 {
		t.Fatalf("grid = %dx%d, want 80x24 — an attached primary outranks a larger secondary", cols, rows)
	}

	onlyPhone := map[*connState]*termMember{phone: {cols: 100, rows: 40}}
	if cols, rows := largestGrid(onlyPhone); cols != 100 || rows != 40 {
		t.Fatalf("grid = %dx%d, want 100x40 — the only client rendering a grid must choose it", cols, rows)
	}
}

func waitForTermBlockSubscriber(t *testing.T, m *Manager, handleID string) {
	t.Helper()
	deadline := time.After(2 * time.Second)
	for {
		if m.termBlockSubscriberCount(handleID) > 0 {
			return
		}
		select {
		case <-deadline:
			t.Fatalf("no terminal-block subscriber for %q appeared", handleID)
		case <-time.After(5 * time.Millisecond):
		}
	}
}

func TestPublishTerminalBlockReachesHandleSubscriberNotAgentSubscriber(t *testing.T) {
	src := &fakeSource{alive: true, spawner: &fakeSpawner{}}
	m := NewManager(src, nil, nil)
	t.Cleanup(m.Close)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	termConn := newFakeConn()
	agentConn := newFakeConn()
	go m.Serve(ctx, termConn)
	go m.Serve(ctx, agentConn)

	termConn.in <- clientMsg{Ch: chBlocks, Type: msgSubscribe, ID: "shellterm-1", BlockType: blockTypeTerminalBlock}
	agentConn.in <- clientMsg{Ch: chBlocks, Type: msgSubscribe, ID: "s-1"}
	waitForTermBlockSubscriber(t, m, "shellterm-1")
	waitForBlockSubscriber(t, m, "s-1")

	exit := 2
	m.PublishTerminalBlock("shellterm-1", domain.Block{
		TerminalID: "shellterm-1",
		SourceID:   "src-9",
		Command:    "make",
		ExitCode:   &exit,
		RawOutput:  []byte{0x00, 0xff},
	})

	msg := recv(t, termConn, chBlocks, msgBlock, 2*time.Second)
	if msg.ID != "shellterm-1" {
		t.Fatalf("frame id = %q, want the runtime handle", msg.ID)
	}
	if msg.BlockType != blockTypeTerminalBlock {
		t.Fatalf("blockType = %q, want %q", msg.BlockType, blockTypeTerminalBlock)
	}
	if msg.TerminalBlock == nil || msg.TerminalBlock.SourceID != "src-9" {
		t.Fatalf("terminal block payload = %+v", msg.TerminalBlock)
	}
	if msg.TerminalBlock.RawOutput != base64.StdEncoding.EncodeToString([]byte{0x00, 0xff}) {
		t.Fatalf("rawOutput = %q, want base64 of arbitrary bytes", msg.TerminalBlock.RawOutput)
	}
	if msg.Block != nil {
		t.Fatalf("terminal-block frame must not carry the agent-event payload: %+v", msg.Block)
	}

	select {
	case got := <-agentConn.out:
		if got.Ch == chBlocks {
			t.Fatalf("agent-event subscriber received a terminal-block frame: %+v", got)
		}
	case <-time.After(200 * time.Millisecond):
	}
}

func TestPublishTerminalBlockDeliversToStandaloneShellWithNoSession(t *testing.T) {
	src := &fakeSource{alive: true, spawner: &fakeSpawner{}}
	m := NewManager(src, nil, nil)
	t.Cleanup(m.Close)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	conn := newFakeConn()
	go m.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chBlocks, Type: msgSubscribe, ID: "shellterm-standalone", BlockType: blockTypeTerminalBlock}
	waitForTermBlockSubscriber(t, m, "shellterm-standalone")

	m.PublishTerminalBlock("shellterm-standalone", domain.Block{
		TerminalID: "shellterm-standalone",
		SourceID:   "src-1",
		SessionID:  "",
		Command:    "ls",
	})

	msg := recv(t, conn, chBlocks, msgBlock, 2*time.Second)
	if msg.TerminalBlock == nil || msg.TerminalBlock.SessionID != "" {
		t.Fatalf("standalone shell block not delivered as expected: %+v", msg.TerminalBlock)
	}
}

func TestPublishBlockEventAgentFrameStaysWireCompatible(t *testing.T) {
	src := &fakeSource{alive: true, spawner: &fakeSpawner{}}
	m := NewManager(src, nil, nil)
	t.Cleanup(m.Close)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	conn := newFakeConn()
	go m.Serve(ctx, conn)
	conn.in <- clientMsg{Ch: chBlocks, Type: msgSubscribe, ID: "s-1"}
	waitForBlockSubscriber(t, m, "s-1")

	rec := blockeventsvc.Record{Seq: 7, SessionID: "s-1", Kind: domain.BlockEventToolComplete, ToolName: "Bash", CreatedAt: time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC)}
	m.PublishBlockEvent("s-1", rec)
	got := recv(t, conn, chBlocks, msgBlock, 2*time.Second)

	gotJSON, err := json.Marshal(got)
	if err != nil {
		t.Fatalf("marshal received frame: %v", err)
	}
	wantJSON, err := json.Marshal(serverMsg{Ch: chBlocks, ID: "s-1", Type: msgBlock, Block: &rec})
	if err != nil {
		t.Fatalf("marshal golden frame: %v", err)
	}
	if string(gotJSON) != string(wantJSON) {
		t.Fatalf("agent block frame changed shape:\n got %s\nwant %s", gotJSON, wantJSON)
	}
	if strings.Contains(string(gotJSON), `"blockType"`) {
		t.Fatalf("agent block frame must not carry blockType: %s", gotJSON)
	}
	if strings.Contains(string(gotJSON), `"terminalBlock"`) {
		t.Fatalf("agent block frame must not carry terminalBlock: %s", gotJSON)
	}
}

// A desktop that is attached but has not reported a size yet must not win the
// arbitration by virtue of being primary; largestGrid requires a usable size.
func TestGridIgnoresAPrimaryThatHasReportedNoSize(t *testing.T) {
	desktop := &connState{}
	phone := &connState{}

	members := map[*connState]*termMember{
		desktop: {primary: true},
		phone:   {cols: 100, rows: 40},
	}
	if cols, rows := largestGrid(members); cols != 100 || rows != 40 {
		t.Fatalf("grid = %dx%d, want 100x40 — a sizeless primary cannot claim the grid", cols, rows)
	}
}
