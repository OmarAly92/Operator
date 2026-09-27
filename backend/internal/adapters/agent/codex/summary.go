package codex

import (
	"regexp"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/terminalui"
	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/redact"
)

var codexTurnTime = regexp.MustCompile(`^\d{1,2}:\d{2}(?::\d{2})?(?:\s?[AP]M)?$`)

func (p *Plugin) ReadTurnSummary(summary string) (string, bool) {
	lines := strings.Split(summary, "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if strings.HasPrefix(strings.TrimSpace(lines[i]), "›") {
			lines = lines[:i]
			break
		}
	}
	var kept []string
	inHook := false
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "• Hook failed" || (inHook && strings.HasPrefix(line, "└ ")) {
			inHook = true
			continue
		}
		inHook = false
		if strings.HasPrefix(line, "│") || strings.HasPrefix(line, "Tip: ") || line == "+ Show details" || codexTurnTime.MatchString(line) {
			continue
		}
		kept = append(kept, line)
	}
	kept = redact.Lines(kept)
	text := terminalui.TurnSummary(kept, 6)
	for i := len(kept) - 1; i >= 0; i-- {
		if strings.HasPrefix(kept[i], "• ") {
			text = terminalui.MessageSummary(kept[i:], 6)
			break
		}
		if strings.HasPrefix(kept[i], "›") {
			text = terminalui.MessageSummary(kept[i+1:], 6)
			break
		}
	}
	return text, text != ""
}

var _ ports.TerminalSummaryReader = (*Plugin)(nil)
