package terminalblock

import (
	"context"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type Store interface {
	UpsertTerminalBlock(context.Context, domain.Block) error
	ListTerminalBlocks(context.Context, string, int) ([]domain.Block, error)
	TrimTerminalBlocks(context.Context, string, int) error
	DeleteTerminalBlocks(context.Context, string) error
	ListRecentTerminalCommands(context.Context, int) ([]domain.CommandRun, error)
	ClearOldOrphanedRawOutput(context.Context, time.Time, time.Time) (int64, error)
	DeleteFullyClearedOrphanedBlocks(context.Context, time.Time, int) (int64, error)
}
