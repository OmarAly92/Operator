// capture.go implements pane capture without tmux's pipe-pane: the host spawns
// the capture argv and tees raw PTY output into its stdin. The tee subscribes to
// the same broadcast the clients read, so capture can never alter what a client
// sees.
package ptyhost

import (
	"context"
	"fmt"
	"io"
	"os/exec"
	"sync"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var _ ports.PaneCapturer = (*Runtime)(nil)

type captureSink struct {
	mu    sync.Mutex
	cmd   *exec.Cmd
	stdin io.WriteCloser
}

func (c *captureSink) start(argv []string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cmd != nil {
		return nil
	}
	cmd := exec.Command(argv[0], argv[1:]...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		_ = stdin.Close()
		return err
	}
	c.cmd, c.stdin = cmd, stdin
	return nil
}

func (c *captureSink) write(batch []byte) {
	c.mu.Lock()
	stdin := c.stdin
	c.mu.Unlock()
	if stdin == nil {
		return
	}
	_, _ = stdin.Write(batch)
}

func (c *captureSink) stop() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cmd == nil {
		return nil
	}
	_ = c.stdin.Close()
	err := c.cmd.Wait()
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
