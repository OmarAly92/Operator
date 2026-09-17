package sessionmanager

import (
	"context"
	"strings"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/slashcommands"
)

type slashOutputConfig struct {
	pollInterval time.Duration
	budget       time.Duration
}

const (
	paneTrailingSpace       = " \u00a0\t"
	slashOutputPollInterval = 250 * time.Millisecond
	slashOutputBudget       = 20 * time.Second
	slashOutputPaneLines    = 400
	slashOutputMarker       = "⎿"
)

func (m *Manager) SlashOutput(ctx context.Context, id domain.SessionID, message string) (string, error) {
	cmd, ok := slashcommands.Lookup(message)
	if !ok || cmd.Interactive {
		return "", nil
	}
	rec, found, err := m.store.GetSession(ctx, id)
	if err != nil {
		return "", err
	}
	if !found {
		return "", ErrNotFound
	}
	if rec.Metadata.RuntimeHandleID == "" {
		return "", nil
	}
	handle := runtimeHandle(rec.Metadata)
	deadline := time.Now().Add(m.slashOutput.budget)
	previous := ""
	seen := false
	for {
		pane, err := m.runtime.GetOutput(ctx, handle, slashOutputPaneLines)
		if err != nil {
			return "", nil
		}
		current := extractSlashOutput(pane, message)
		if seen && current != "" && current == previous {
			return current, nil
		}
		previous, seen = current, true
		if time.Now().After(deadline) {
			return "", nil
		}
		if err := sleepContext(ctx, m.slashOutput.pollInterval); err != nil {
			return "", nil
		}
	}
}

func extractSlashOutput(pane, message string) string {
	echo := "❯ " + strings.TrimSpace(message)
	lines := strings.Split(pane, "\n")
	start := -1
	for i, line := range lines {
		if strings.TrimRight(line, paneTrailingSpace) == echo {
			start = i
		}
	}
	if start < 0 {
		return ""
	}
	var out []string
	first := true
	for _, line := range lines[start+1:] {
		trimmed := strings.TrimRight(line, paneTrailingSpace)
		if isPaneSeparator(trimmed) || strings.HasPrefix(strings.TrimLeft(trimmed, " "), "❯") {
			break
		}
		body := strings.TrimLeft(trimmed, " ")
		if first {
			if !strings.HasPrefix(body, slashOutputMarker) {
				return ""
			}
			first = false
		}
		body = strings.TrimSpace(strings.TrimPrefix(body, slashOutputMarker))
		out = append(out, body)
	}
	for len(out) > 0 && out[len(out)-1] == "" {
		out = out[:len(out)-1]
	}
	return strings.Join(out, "\n")
}

func isPaneSeparator(line string) bool {
	line = strings.TrimSpace(line)
	return len(line) >= 10 && strings.Trim(line, "─") == ""
}
