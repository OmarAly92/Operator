package ptyhost

import (
	"bytes"
	"context"
	"io"
	"net"
	"sort"
	"sync"
	"testing"
	"time"
)

type pipePTY struct {
	r    *io.PipeReader
	w    *io.PipeWriter
	done chan struct{}
}

func newPipePTY() *pipePTY {
	r, w := io.Pipe()
	return &pipePTY{r: r, w: w, done: make(chan struct{})}
}

func (p *pipePTY) Read(b []byte) (int, error)  { return p.r.Read(b) }
func (p *pipePTY) Write(b []byte) (int, error) { return len(b), nil }
func (p *pipePTY) Resize(cols, rows int) error { return nil }
func (p *pipePTY) Close() error                { return p.w.Close() }
func (p *pipePTY) Done() <-chan struct{}       { return p.done }
func (p *pipePTY) ExitCode() (int, bool)       { return 0, false }
func (p *pipePTY) PID() int                    { return 1 }

type frameLog struct {
	mu     sync.Mutex
	frames int
	data   []byte
	status chan struct{}
}

func (l *frameLog) frameCount() int { l.mu.Lock(); defer l.mu.Unlock(); return l.frames }
func (l *frameLog) byteCount() int  { l.mu.Lock(); defer l.mu.Unlock(); return len(l.data) }
func (l *frameLog) received() []byte {
	l.mu.Lock()
	defer l.mu.Unlock()
	return append([]byte(nil), l.data...)
}

func startPumpHost(t *testing.T) (*pipePTY, net.Conn, *frameLog) {
	t.Helper()
	pty := newPipePTY()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		_ = Serve(ctx, ServeConfig{SessionID: "pump-test", Listener: ln, PTY: pty, Ring: NewRing()})
	}()
	conn, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	t.Cleanup(func() { cancel(); _ = conn.Close(); close(pty.done) })

	log := &frameLog{status: make(chan struct{}, 1)}
	parser := NewMessageParser(func(msgType byte, payload []byte) {
		switch msgType {
		case MsgTerminalData:
			log.mu.Lock()
			log.frames++
			log.data = append(log.data, payload...)
			log.mu.Unlock()
		case MsgStatusRes:
			select {
			case log.status <- struct{}{}:
			default:
			}
		}
	})
	go func() {
		buf := make([]byte, 64*1024)
		for {
			n, err := conn.Read(buf)
			if n > 0 {
				parser.Feed(buf[:n])
			}
			if err != nil {
				return
			}
		}
	}()
	return pty, conn, log
}

func waitFor(t *testing.T, timeout time.Duration, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatal("condition not met before timeout")
		}
		time.Sleep(time.Millisecond)
	}
}

func TestPumpCoalescesUnderLoad(t *testing.T) {
	pty, _, log := startPumpHost(t)

	payload := bytes.Repeat([]byte("0123456789abcdef"), 2048)
	const writes = 128
	start := time.Now()
	for range writes {
		if _, err := pty.w.Write(payload); err != nil {
			t.Fatalf("write: %v", err)
		}
	}
	waitFor(t, 5*time.Second, func() bool { return log.byteCount() == writes*len(payload) })
	elapsed := time.Since(start)

	if !bytes.Equal(log.received(), bytes.Repeat(payload, writes)) {
		t.Fatal("client bytes differ from PTY bytes")
	}
	totalBytes := writes * len(payload)
	minFlushes := totalBytes / readBufferSize
	ceiling := max(int(elapsed/flushInterval), minFlushes) + 2
	if got := log.frameCount(); got > ceiling {
		t.Fatalf("frames = %d over %v, want <= %d: coalescing is not engaging", got, elapsed, ceiling)
	}
}

func TestPumpFlushesImmediatelyWhenIdle(t *testing.T) {
	pty, _, log := startPumpHost(t)

	var latencies []time.Duration
	for range 20 {
		time.Sleep(3 * flushInterval)
		before := log.byteCount()
		start := time.Now()
		if _, err := pty.w.Write([]byte("x")); err != nil {
			t.Fatalf("write: %v", err)
		}
		waitFor(t, time.Second, func() bool { return log.byteCount() > before })
		latencies = append(latencies, time.Since(start))
	}
	sort.Slice(latencies, func(i, j int) bool { return latencies[i] < latencies[j] })
	if median := latencies[len(latencies)/2]; median >= 8*time.Millisecond {
		t.Fatalf("idle echo median = %v, want < 8ms: a coalescer that always waits a frame fails this", median)
	}
}

func TestPumpDoesNotStarveControlMessages(t *testing.T) {
	pty, conn, log := startPumpHost(t)

	stopFlood := make(chan struct{})
	defer close(stopFlood)
	go func() {
		payload := bytes.Repeat([]byte("y\n"), 16*1024)
		for {
			select {
			case <-stopFlood:
				return
			default:
				if _, err := pty.w.Write(payload); err != nil {
					return
				}
			}
		}
	}()

	time.Sleep(100 * time.Millisecond)
	req, err := EncodeMessage(MsgStatusReq, nil)
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	if _, err := conn.Write(req); err != nil {
		t.Fatalf("send status req: %v", err)
	}
	select {
	case <-log.status:
	case <-time.After(500 * time.Millisecond):
		t.Fatal("MsgStatusRes starved by the firehose")
	}
}
