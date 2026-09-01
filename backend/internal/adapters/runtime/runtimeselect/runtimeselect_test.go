package runtimeselect

import (
	"testing"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
)

func TestNewHonoursPtyHostOverride(t *testing.T) {
	t.Setenv("OPERATOR_RUNTIME", "ptyhost")
	if _, ok := New(nil).(*ptyhost.Runtime); !ok {
		t.Fatalf("New() = %T, want *ptyhost.Runtime when OPERATOR_RUNTIME=ptyhost", New(nil))
	}
}
