package process

import "github.com/OmarAly92/operator/backend/internal/ports"

type Table struct{}

func New() *Table { return &Table{} }

var (
	_ ports.ProcessInspector = (*Table)(nil)
	_ ports.ProcessSignaller = (*Table)(nil)
)
