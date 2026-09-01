package runtimeselect

import (
	"testing"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
)

// The OPERATOR_RUNTIME override is gone with tmux; every platform gets the
// pty-host, and a stale value in the environment must not change that.
func TestNewAlwaysReturnsPtyHost(t *testing.T) {
	t.Setenv("OPERATOR_RUNTIME", "tmux")
	if _, ok := New(nil).(*ptyhost.Runtime); !ok {
		t.Fatalf("New() = %T, want *ptyhost.Runtime", New(nil))
	}
}
