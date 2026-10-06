package claudecode

import (
	"regexp"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/terminalui"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/redact"
)

var claudeTurnFooter = regexp.MustCompile(`^✻ \S+ for \S+`)

func (p *Plugin) ReadTurnSummary(summary string) (string, bool) {
	lines, ok := beforeComposer(strings.Split(summary, "\n"))
	if !ok {
		return "", false
	}
	var kept []string
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if claudeTurnFooter.MatchString(line) {
			continue
		}
		kept = append(kept, line)
	}
	kept = redact.Lines(kept)
	text := terminalui.TurnSummary(stripMarkers(kept), 6)
	for i := len(kept) - 1; i >= 0; i-- {
		if strings.HasPrefix(kept[i], "⏺") {
			text = terminalui.MessageSummary(stripMarkers(kept[i:]), 6)
			break
		}
		if strings.HasPrefix(kept[i], "❯") {
			text = terminalui.MessageSummary(stripMarkers(kept[i+1:]), 6)
			break
		}
	}
	return text, text != ""
}

func beforeComposer(lines []string) ([]string, bool) {
	for i := len(lines) - 1; i >= 0; i-- {
		if !strings.HasPrefix(strings.TrimSpace(lines[i]), "❯") {
			continue
		}
		if i > 0 && isRuleLine(strings.TrimSpace(lines[i-1])) {
			return lines[:i-1], true
		}
		return nil, false
	}
	return nil, false
}

func stripMarkers(lines []string) []string {
	out := make([]string, 0, len(lines))
	for _, line := range lines {
		out = append(out, strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(line, "⏺"), "⎿")))
	}
	return out
}

var _ ports.TerminalSummaryReader = (*Plugin)(nil)
