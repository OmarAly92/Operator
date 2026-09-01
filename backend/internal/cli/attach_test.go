package cli

import (
	"strings"
	"testing"
)

func TestAttachCommandRejectsUnknownSession(t *testing.T) {
	cmd := newAttachCommand()
	cmd.SetArgs([]string{"no-such-session"})
	err := cmd.Execute()
	if err == nil || !strings.Contains(err.Error(), "no-such-session") {
		t.Fatalf("Execute() error = %v, want it to name the missing session", err)
	}
}
