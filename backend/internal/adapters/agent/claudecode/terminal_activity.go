package claudecode

import (
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func (p *Plugin) DetectTerminalActivity(output string) (domain.ActivityState, bool) {
	lines := paneLines(output)
	tail := lines[max(0, len(lines)-12):]
	composer := false
	for i, line := range tail {
		if strings.Contains(strings.ToLower(line), "esc to interrupt") {
			return "", false
		}
		if i > 0 && strings.HasPrefix(line, "❯") && isRuleLine(tail[i-1]) {
			composer = true
		}
	}
	if !composer {
		return "", false
	}
	if _, open := p.ReadDialog(output); open {
		return "", false
	}
	return domain.ActivityIdle, true
}

func isRuleLine(line string) bool {
	return line != "" && strings.Trim(line, "─") == ""
}

var _ ports.TerminalActivityDetector = (*Plugin)(nil)
