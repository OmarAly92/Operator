//go:build windows

package process

import (
	"context"
	"errors"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var errUnsupported = errors.New("process: not supported on windows")

func (t *Table) ListProcesses(context.Context) ([]ports.ProcessInfo, error) {
	return nil, errUnsupported
}

func (t *Table) OpenFileWriters(context.Context, string) ([]int, error) {
	return nil, errUnsupported
}

func (t *Table) Terminate(int, bool) error { return errUnsupported }

func (t *Table) Kill(int, bool) error { return errUnsupported }

func (t *Table) Alive(int, bool) bool { return false }
