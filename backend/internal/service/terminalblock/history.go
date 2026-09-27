package terminalblock

import (
	"context"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/redact"
)

const (
	DefaultRecentCommands  = 500
	MaxRecentCommands      = 1000
	recentCommandScan      = domain.SharedHistoryScan
	maxHistoryCommandBytes = 4096
)

func (s *Service) RecentCommands(ctx context.Context, limit int) ([]domain.CommandRun, error) {
	if limit <= 0 {
		limit = DefaultRecentCommands
	}
	limit = min(limit, MaxRecentCommands)
	runs, err := s.store.ListRecentTerminalCommands(ctx, recentCommandScan)
	if err != nil {
		return nil, err
	}
	seen := make(map[string]struct{}, limit)
	out := make([]domain.CommandRun, 0, limit)
	for _, run := range runs {
		if len(out) == limit {
			break
		}
		if _, dup := seen[run.Command]; dup || !historyWorthy(run.Command) {
			continue
		}
		seen[run.Command] = struct{}{}
		out = append(out, run)
	}
	slices.Reverse(out)
	return out, nil
}

func historyWorthy(command string) bool {
	if len(command) > maxHistoryCommandBytes || !utf8.ValidString(command) {
		return false
	}
	if strings.TrimSpace(command) == "" || strings.HasPrefix(command, " ") {
		return false
	}
	for _, r := range command {
		if r == '\n' || r == '\t' {
			continue
		}
		if r < 0x20 || r == 0x7f || (r >= 0x80 && r < 0xa0) {
			return false
		}
	}
	return len(redact.Text(command).Spans) == 0
}
