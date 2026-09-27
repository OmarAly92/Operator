package codex

import (
	"strings"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/terminalui"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func (p *Plugin) ReadQuestion(pane string) (ports.TerminalQuestion, bool) {
	lines := terminalLines(pane)
	lines = lines[max(0, len(lines)-24):]
	for _, line := range lines {
		if strings.Contains(strings.ToLower(line), "esc to interrupt") || line == "Select Model and Effort" {
			return ports.TerminalQuestion{}, false
		}
	}
	menu, start, ok := terminalui.LastNumberedMenu(lines, "›")
	if !ok {
		return ports.TerminalQuestion{}, false
	}
	return terminalui.QuestionAt(lines, start, menu), true
}

var _ ports.TerminalQuestionReader = (*Plugin)(nil)
