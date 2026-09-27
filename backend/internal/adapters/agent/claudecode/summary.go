package claudecode

import (
	"regexp"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/terminalui"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

var claudeTurnFooter = regexp.MustCompile(`^✻ \S+ for \S+`)

func (p *Plugin) ReadTurnSummary(summary string) (string, bool) {
	lines := strings.Split(summary, "\n")
	for i := len(lines) - 1; i > 0; i-- {
		if strings.HasPrefix(strings.TrimSpace(lines[i]), "❯") && isRuleLine(strings.TrimSpace(lines[i-1])) {
			lines = lines[:i-1]
			break
		}
	}
	var kept []string
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if claudeTurnFooter.MatchString(line) {
			continue
		}
		kept = append(kept, line)
	}
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

func stripMarkers(lines []string) []string {
	out := make([]string, 0, len(lines))
	for _, line := range lines {
		out = append(out, strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(line, "⏺"), "⎿")))
	}
	return out
}

var _ ports.TerminalSummaryReader = (*Plugin)(nil)
