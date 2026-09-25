package ports

import "context"

type ProcessInfo struct {
	PID     int
	PPID    int
	PGID    int
	Command string
}

type ProcessInspector interface {
	ListProcesses(ctx context.Context) ([]ProcessInfo, error)
	OpenFileHolders(ctx context.Context, path string) ([]int, error)
}

type ProcessSignaller interface {
	Terminate(pid int, group bool) error
	Kill(pid int, group bool) error
	Alive(pid int) bool
}

type RuntimeProcessReader interface {
	ChildPID(ctx context.Context, handle RuntimeHandle) (int, error)
}
