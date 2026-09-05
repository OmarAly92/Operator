package codex

import (
	"slices"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/terminalui"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func (p *Plugin) ReadDialog(pane string) (ports.Dialog, bool) {
	lines := terminalLines(pane)
	lines = lines[max(0, len(lines)-40):]
	if len(lines) == 0 || lines[len(lines)-1] != "Press enter to confirm or esc to go back" {
		return ports.Dialog{}, false
	}
	body := lines[:len(lines)-1]
	menu, ok := readNumberedMenu(body)
	if !ok {
		return ports.Dialog{}, false
	}
	title := ""
	if i := slices.Index(body, "Select Model and Effort"); i >= 0 {
		title = body[i]
	}
	return ports.Dialog{Kind: ports.DialogModel, Title: title, Menu: menu}, true
}

func (p *Plugin) AllowRow(ports.Menu) (int, bool) {
	return 0, false
}

func (p *Plugin) DenyRow(ports.Menu) (int, bool) {
	return 0, false
}

func (p *Plugin) ReadMenu(pane string) (ports.Menu, bool) {
	dialog, ok := p.ReadDialog(pane)
	if !ok {
		return ports.Menu{}, false
	}
	return dialog.Menu, true
}

func (p *Plugin) MenuKeys() ports.MenuKeys {
	return ports.MenuKeys{Up: "\x1b[A", Down: "\x1b[B", Select: "\r", Cancel: "\x1b", SessionSelect: "\r"}
}

func readNumberedMenu(lines []string) (ports.Menu, bool) {
	return terminalui.ReadNumberedMenu(lines, "›")
}

var _ ports.TerminalDialogReader = (*Plugin)(nil)
var _ ports.TerminalMenuReader = (*Plugin)(nil)
