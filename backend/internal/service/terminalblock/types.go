package terminalblock

import (
	"context"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type Store interface {
	UpsertTerminalBlock(context.Context, domain.Block) error
	ListTerminalBlocks(context.Context, string, int) ([]domain.Block, error)
	TrimTerminalBlocks(context.Context, string, int) error
	DeleteTerminalBlocks(context.Context, string) error
}
