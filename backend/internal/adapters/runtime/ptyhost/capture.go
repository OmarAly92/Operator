// capture.go implements pane capture inside the host: it spawns
// the capture argv and tees raw PTY output into its stdin. The tee subscribes to
// the same broadcast the clients read, so capture can never alter what a client
// sees.
package ptyhost

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"sync"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var _ ports.PaneCapturer = (*Runtime)(nil)

var captureExecutablePath = os.Executable

type captureSink struct {
	mu    sync.Mutex
	cmd   *exec.Cmd
	stdin io.WriteCloser

	// queue/queueCond/stopping/drained decouple write (called from deliver,
	// the terminal's hot path) from the actual write to stdin, which blocks
	// whenever the pane-capture subprocess isn't draining fast enough (slow
	// disk I/O, segment rotation). Without this, a stalled capture consumer
	// stalls pumpPTY itself, freezing ring append and client broadcast for
	// the whole session — not just capture — for every byte after it.
	queueMu   sync.Mutex
	queueCond *sync.Cond
	queue     [][]byte
	stopping  bool
	drained   chan struct{}
}

func (c *captureSink) start(argv []string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cmd != nil {
		return nil
	}
	self, err := captureExecutablePath()
	if err != nil {
		return fmt.Errorf("ptyhost: resolve executable for pane capture: %w", err)
	}
	full := append([]string{self}, argv...)
	cmd := exec.Command(full[0], full[1:]...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		_ = stdin.Close()
		return err
	}
	c.cmd, c.stdin = cmd, stdin
	c.queueCond = sync.NewCond(&c.queueMu)
	c.queue = nil
	c.stopping = false
	c.drained = make(chan struct{})
	go c.forward(stdin, c.drained)
	return nil
}

// write queues batch for forward rather than writing to stdin directly. See
// the comment on captureSink's queue fields for why.
func (c *captureSink) write(batch []byte) {
	c.mu.Lock()
	active := c.stdin != nil
	c.mu.Unlock()
	if !active {
		return
	}
	cp := append([]byte(nil), batch...)
	c.queueMu.Lock()
	c.queue = append(c.queue, cp)
	c.queueCond.Signal()
	c.queueMu.Unlock()
}

// forward drains the queue into stdin, one batch at a time, blocking on each
// Write exactly as write() used to — but on its own goroutine, so a stalled
// capture consumer never blocks deliver(). It exits once stopping is set and
// the queue is empty, closing drained so stop() knows every already-queued
// batch reached stdin before it closes the pipe.
func (c *captureSink) forward(stdin io.Writer, drained chan struct{}) {
	for {
		c.queueMu.Lock()
		for len(c.queue) == 0 && !c.stopping {
			c.queueCond.Wait()
		}
		if len(c.queue) == 0 {
			c.queueMu.Unlock()
			close(drained)
			return
		}
		batch := c.queue[0]
		c.queue = c.queue[1:]
		c.queueMu.Unlock()
		if _, err := stdin.Write(batch); err != nil {
			// The subprocess is gone; drop whatever's left rather than
			// spinning write errors, and let stop()'s Wait() reap it.
			c.queueMu.Lock()
			c.queue = nil
			c.queueMu.Unlock()
		}
	}
}

func (c *captureSink) stop() error {
	c.mu.Lock()
	if c.cmd == nil {
		c.mu.Unlock()
		return nil
	}
	cmd, stdin, drained := c.cmd, c.stdin, c.drained
	c.mu.Unlock()

	c.queueMu.Lock()
	c.stopping = true
	c.queueCond.Signal()
	c.queueMu.Unlock()
	<-drained // every batch queued before stop() reached stdin

	c.mu.Lock()
	defer c.mu.Unlock()
	_ = stdin.Close()
	err := cmd.Wait()
	c.cmd, c.stdin = nil, nil
	return err
}

func (c *captureSink) open() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.cmd != nil
}

func (r *Runtime) CaptureState(ctx context.Context, handle ports.RuntimeHandle) (ports.PaneCaptureState, error) {
	sess := r.resolve(handle.ID)
	if sess == nil {
		return ports.PaneCaptureState{}, fmt.Errorf("ptyhost: session %q not found", handle.ID)
	}
	res, err := clientCaptureState(sess.addr)
	if err != nil {
		return ports.PaneCaptureState{}, err
	}
	return ports.PaneCaptureState{PipeOpen: res.PipeOpen, AlternateOn: res.AlternateOn}, nil
}

func (r *Runtime) StartCapture(ctx context.Context, handle ports.RuntimeHandle, argv []string) error {
	sess := r.resolve(handle.ID)
	if sess == nil {
		return fmt.Errorf("ptyhost: session %q not found", handle.ID)
	}
	return clientStartCapture(sess.addr, argv)
}

func (r *Runtime) StopCapture(ctx context.Context, handle ports.RuntimeHandle) error {
	sess := r.resolve(handle.ID)
	if sess == nil {
		return fmt.Errorf("ptyhost: session %q not found", handle.ID)
	}
	return clientStopCapture(sess.addr)
}
