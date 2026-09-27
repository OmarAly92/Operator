package claudecode

import (
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/terminalui"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func (p *Plugin) ReadQuestion(pane string) (ports.TerminalQuestion, bool) {
	dialog, ok := p.ReadDialog(pane)
	if !ok || dialog.Kind == ports.DialogModel {
		return ports.TerminalQuestion{}, false
	}
	lines := paneLines(pane)
	_, start, ok := terminalui.LastNumberedMenu(lines, "❯")
	if !ok {
		return ports.TerminalQuestion{}, false
	}
	return terminalui.QuestionAt(lines, start, dialog.Menu), true
}

var _ ports.TerminalQuestionReader = (*Plugin)(nil)
