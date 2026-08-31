package conpty

import (
	"context"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var _ ports.PaneCapturer = (*Runtime)(nil)

func (r *Runtime) CaptureState(context.Context, ports.RuntimeHandle) (ports.PaneCaptureState, error) {
	return ports.PaneCaptureState{}, ports.ErrCaptureUnsupported
}

func (r *Runtime) StartCapture(context.Context, ports.RuntimeHandle, []string) error {
	return ports.ErrCaptureUnsupported
}

func (r *Runtime) StopCapture(context.Context, ports.RuntimeHandle) error {
	return ports.ErrCaptureUnsupported
}
