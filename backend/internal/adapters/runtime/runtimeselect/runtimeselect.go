// Package runtimeselect picks the correct runtime backend by platform:
// tmux on Darwin/Linux, conpty (ConPTY) on Windows.
package runtimeselect

import (
	"context"
	"log/slog"
	"os"
	"runtime"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/tmux"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// Runtime is the union interface that both tmux and conpty satisfy.
// It extends ports.Runtime (Create/Destroy/IsAlive) with the additional methods
// the daemon wires directly, including ports.Attacher (Attach) so the terminal
// layer can open a Stream against the selected runtime.
type Runtime interface {
	ports.Runtime // Create, Destroy, IsAlive
	ports.Attacher
	ports.PaneCapturer
	Interrupt(ctx context.Context, handle ports.RuntimeHandle) error
	SendInput(ctx context.Context, handle ports.RuntimeHandle, input string) error
	SendMessage(ctx context.Context, handle ports.RuntimeHandle, message string) error
	GetOutput(ctx context.Context, handle ports.RuntimeHandle, lines int) (string, error)
}

// Compile-time assertions: both adapters must implement the union interface.
var _ Runtime = (*tmux.Runtime)(nil)
var _ Runtime = (*ptyhost.Runtime)(nil)

// New returns the per-platform runtime: tmux on Darwin/Linux, conpty on Windows.
// log is accepted for signature stability with callers but is currently unused.
func New(_ *slog.Logger) Runtime {
	if os.Getenv("OPERATOR_RUNTIME") == "ptyhost" || runtime.GOOS == "windows" {
		return ptyhost.New(ptyhost.Options{})
	}
	return tmux.New(tmux.Options{})
}
