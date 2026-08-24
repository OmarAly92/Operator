package browser

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

// ErrUnavailable indicates that no browser runtime can accept a command.
var ErrUnavailable = errors.New("browser automation runtime is unavailable")

// RuntimeStatus reports whether the browser transport can accept commands.
type RuntimeStatus struct {
	Ready   bool
	ReadyAt time.Time
}

// RuntimeResult contains the correlated response to one browser command.
type RuntimeResult struct {
	RequestID string
	Value     interface{}
}

// CommandError is a stable browser failure returned by any runtime adapter.
type CommandError struct {
	Code    string
	Message string
}

// Error renders the message with its stable code for logs and envelopes.
func (e CommandError) Error() string {
	if e.Code == "" {
		return e.Message
	}
	return fmt.Sprintf("%s (%s)", e.Message, e.Code)
}

// Runtime is the adapter-neutral session-scoped browser automation contract.
// Implementations own their transport details behind these three calls.
type Runtime interface {
	// Status reports whether the transport can serve the session.
	Status(sessionID domain.SessionID) RuntimeStatus
	// Execute dispatches one supported action with its action-specific args.
	Execute(ctx context.Context, sessionID domain.SessionID, action string, args map[string]interface{}) (RuntimeResult, error)
	// DestroySession tears down the session's browser state best-effort.
	DestroySession(ctx context.Context, sessionID domain.SessionID) error
}
