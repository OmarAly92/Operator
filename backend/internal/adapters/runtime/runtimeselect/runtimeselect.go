// Package runtimeselect names the runtime backend the daemon wires. Every
// platform runs the pty-host; the selection this package once made between tmux
// and ConPTY is gone with tmux itself.
package runtimeselect

import (
	"context"
	"log/slog"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// Runtime is the interface the daemon wires. It extends ports.Runtime
// (Create/Destroy/IsAlive) with the additional methods the daemon uses
// directly, including ports.Attacher (Attach) so the terminal layer can open a
// Stream against the runtime.
type Runtime interface {
	ports.Runtime // Create, Destroy, IsAlive
	ports.Attacher
	ports.PaneCapturer
	Interrupt(ctx context.Context, handle ports.RuntimeHandle) error
	SendInput(ctx context.Context, handle ports.RuntimeHandle, input string) error
	SendMessage(ctx context.Context, handle ports.RuntimeHandle, message string) error
	GetOutput(ctx context.Context, handle ports.RuntimeHandle, lines int) (string, error)
}

var _ Runtime = (*ptyhost.Runtime)(nil)

// New returns the pty-host runtime. log is accepted for signature stability
// with callers but is currently unused.
func New(_ *slog.Logger) Runtime {
	return ptyhost.New(ptyhost.Options{})
}
