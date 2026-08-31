package domain

import "time"

type Block struct {
	TerminalID     string
	SourceID       string
	SessionID      string
	Command        string
	Cwd            string
	GitBranch      string
	ExitCode       *int
	RawOutput      []byte
	StartedAt      time.Time
	FinishedAt     time.Time
	ShellKind      string
	ShellVersion   string
	TruncatedLines int
	TruncatedBytes int
	CaptureEpoch   string
	StartOffset    int64
	EndOffset      int64
	CreatedAt      time.Time
}
