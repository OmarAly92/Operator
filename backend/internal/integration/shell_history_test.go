//go:build !windows

package integration

import (
	"context"
	"fmt"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/service/terminalblock"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite"
)

func TestShellBlocksReachTheSharedCommandHistoryWithoutSecrets(t *testing.T) {
	for _, shell := range []string{"zsh", "bash", "fish"} {
		t.Run(shell, func(t *testing.T) {
			h := newShellBlocksHarnessIn(t, "run-history-"+shell, shell)
			h.send(t, "echo one")
			h.send(t, "export API_TOKEN=abcdefghijklmnop")
			h.send(t, "echo two")
			h.waitHistory(t, 3)

			ctx := context.Background()
			if err := h.shells.CloseShellTerminal(ctx, h.terminal.HandleID); err != nil {
				t.Fatalf("close shell terminal: %v", err)
			}
			h.terminal.HandleID = ""
			if err := h.store.Close(); err != nil {
				t.Fatalf("close store: %v", err)
			}
			reopened, err := sqlite.Open(h.dataDir)
			if err != nil {
				t.Fatalf("reopen store: %v", err)
			}
			h.store = reopened

			runs, err := terminalblock.NewService(reopened).RecentCommands(ctx, 10)
			if err != nil {
				t.Fatalf("recent commands: %v", err)
			}
			got := make([]string, 0, len(runs))
			for _, run := range runs {
				got = append(got, run.Command)
			}
			if want := []string{"echo one", "echo two"}; fmt.Sprint(got) != fmt.Sprint(want) {
				t.Fatalf("shared history = %q, want %q", got, want)
			}
		})
	}
}
