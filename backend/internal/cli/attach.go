package cli

import (
	"fmt"
	"net"
	"os"
	"time"

	"github.com/spf13/cobra"
	"golang.org/x/term"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/ptyregistry"
)

const attachDialTimeout = 3 * time.Second

func newAttachCommand() *cobra.Command {
	return &cobra.Command{
		Use:    "attach <session>",
		Short:  "Attach to a live pty-host session for debugging (internal)",
		Hidden: true,
		Args:   cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return runAttach(cmd, args[0])
		},
	}
}

func runAttach(cmd *cobra.Command, sessionID string) error {
	entries, err := ptyregistry.List()
	if err != nil {
		return fmt.Errorf("attach: list pty-host sessions: %w", err)
	}

	var addr string
	found := false
	for _, e := range entries {
		if e.SessionID == sessionID {
			addr = e.PipePath
			found = true
			break
		}
	}
	if !found {
		return fmt.Errorf("attach: no live pty-host session %q", sessionID)
	}

	conn, err := net.DialTimeout("tcp", addr, attachDialTimeout)
	if err != nil {
		return fmt.Errorf("attach: dial session %q: %w", sessionID, err)
	}
	defer func() { _ = conn.Close() }()

	stdinFD := int(os.Stdin.Fd())
	oldState, err := term.MakeRaw(stdinFD)
	if err != nil {
		return fmt.Errorf("attach: enter raw mode: %w", err)
	}
	defer func() { _ = term.Restore(stdinFD, oldState) }()

	out := cmd.OutOrStdout()

	done := make(chan struct{})
	go func() {
		defer close(done)
		parser := ptyhost.NewMessageParser(func(msgType byte, payload []byte) {
			if msgType == ptyhost.MsgTerminalData {
				_, _ = out.Write(payload)
			}
		})
		buf := make([]byte, 4096)
		for {
			n, err := conn.Read(buf)
			if n > 0 {
				parser.Feed(buf[:n])
			}
			if err != nil {
				return
			}
		}
	}()

	inBuf := make([]byte, 4096)
	for {
		n, err := os.Stdin.Read(inBuf)
		if n > 0 {
			frame, encErr := ptyhost.EncodeMessage(ptyhost.MsgTerminalInput, inBuf[:n])
			if encErr != nil {
				return fmt.Errorf("attach: encode input: %w", encErr)
			}
			if _, writeErr := conn.Write(frame); writeErr != nil {
				break
			}
		}
		if err != nil {
			break
		}
	}

	<-done
	return nil
}
