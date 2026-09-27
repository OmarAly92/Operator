package codex

import (
	"strings"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/terminalui"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func (p *Plugin) ReadQuestion(pane string) (ports.TerminalQuestion, bool) {
	all := terminalLines(pane)
	offset := max(0, len(all)-24)
	lines := all[offset:]
	for _, line := range lines {
		if strings.Contains(strings.ToLower(line), "esc to interrupt") || line == "Select Model and Effort" {
			return ports.TerminalQuestion{}, false
		}
	}
	menu, start, ok := terminalui.LastNumberedMenu(lines, "›")
	if !ok {
		return ports.TerminalQuestion{}, false
	}
	return terminalui.QuestionAt(all, offset+start, menu), true
}

var _ ports.TerminalQuestionReader = (*Plugin)(nil)
