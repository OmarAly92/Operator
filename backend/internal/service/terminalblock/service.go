package terminalblock

import (
	"bytes"
	"context"
	"unicode/utf8"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

const (
	retainPerTerminal = 100
	maxOutputLines    = 5000
	maxOutputBytes    = 8 << 20
)

type Service struct {
	store Store
}

func NewService(store Store) *Service {
	return &Service{store: store}
}

func (s *Service) Record(ctx context.Context, b domain.Block) error {
	trimmed, omittedLines, omittedBytes := capOutput(b.RawOutput)
	b.RawOutput = trimmed
	b.TruncatedLines += omittedLines
	b.TruncatedBytes += omittedBytes

	if err := s.store.UpsertTerminalBlock(ctx, b); err != nil {
		return err
	}
	return s.store.TrimTerminalBlocks(ctx, b.TerminalID, retainPerTerminal)
}

func (s *Service) History(ctx context.Context, terminalID string, limit int) ([]domain.Block, error) {
	return s.store.ListTerminalBlocks(ctx, terminalID, limit)
}

func capOutput(raw []byte) (out []byte, omittedLines, omittedBytes int) {
	out = raw

	if lines := bytes.Count(out, []byte{'\n'}) + 1; lines > maxOutputLines {
		drop := lines - maxOutputLines
		idx := 0
		for i := 0; i < drop; i++ {
			p := bytes.IndexByte(out[idx:], '\n')
			idx += p + 1
		}
		omittedLines = drop
		out = out[idx:]
	}

	if len(out) > maxOutputBytes {
		cut := len(out) - maxOutputBytes
		for cut < len(out) && !utf8.RuneStart(out[cut]) {
			cut++
		}
		out = out[cut:]
	}

	omittedBytes = len(raw) - len(out)
	return out, omittedLines, omittedBytes
}
