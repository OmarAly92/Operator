package cli

import (
	"bytes"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"time"

	"github.com/spf13/cobra"
	"golang.org/x/term"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/ptyregistry"
)

const attachDialTimeout = 3 * time.Second

// ctrlC is ETX (0x03), the byte a terminal in raw mode delivers for Ctrl-C
// instead of a local SIGINT. attachPipe intercepts it as a local detach
// trigger rather than forwarding it to the remote session.
const ctrlC = 0x03

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

	return attachPipe(conn, os.Stdin, cmd.OutOrStdout())
}

// attachPipe copies terminal data from conn to out, and stdin from in to
// conn, until either side finishes: the remote closes conn, in reaches EOF
// or errors, or in produces a Ctrl-C byte (0x03), which is treated as a
// local detach request and never forwarded to the remote session.
//
// Both directions run as goroutines. closeConn is guarded by a sync.Once
// that also carries the triggering error to winner: whichever goroutine
// first detects an end condition (a Ctrl-C byte, a read/write failure, or
// EOF) is the one whose call to closeConn actually runs, so winner always
// reports the true cause rather than racing two independently-produced
// errors against each other. Closing conn also unblocks whichever goroutine
// is blocked in conn.Read. attachPipe returns as soon as winner receives a
// value — it does not wait for a goroutine still blocked on a local read of
// in, since that read cannot be cancelled portably; it is left to exit (or
// leak harmlessly until process exit) on its own.
func attachPipe(conn net.Conn, in io.Reader, out io.Writer) error {
	var closeOnce sync.Once
	winner := make(chan error, 1)
	closeConn := func(cause error) {
		closeOnce.Do(func() {
			_ = conn.Close()
			winner <- cause
		})
	}

	go func() {
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
				closeConn(err)
				return
			}
		}
	}()

	go func() {
		inBuf := make([]byte, 4096)
		for {
			n, err := in.Read(inBuf)
			if n > 0 {
				chunk := inBuf[:n]
				if idx := bytes.IndexByte(chunk, ctrlC); idx >= 0 {
					if idx > 0 {
						_ = sendInput(conn, chunk[:idx])
					}
					closeConn(nil)
					return
				}
				if sendErr := sendInput(conn, chunk); sendErr != nil {
					closeConn(sendErr)
					return
				}
			}
			if err != nil {
				closeConn(err)
				return
			}
		}
	}()

	cause := <-winner
	if cause != nil && cause != io.EOF {
		return fmt.Errorf("attach: session ended: %w", cause)
	}
	return nil
}

func sendInput(conn net.Conn, chunk []byte) error {
	frame, err := ptyhost.EncodeMessage(ptyhost.MsgTerminalInput, chunk)
	if err != nil {
		return err
	}
	_, err = conn.Write(frame)
	return err
}
