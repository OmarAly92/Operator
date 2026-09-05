package claudecode

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/terminalui"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

var claudeTerminalEscape = regexp.MustCompile(`\x1b(?:\[[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]|\][^\x07]*(?:\x07|\x1b\\))`)

func (p *Plugin) ReadDialog(pane string) (ports.Dialog, bool) {
	lines := paneLines(pane)
	if len(lines) == 0 {
		return ports.Dialog{}, false
	}
	kind, ok := dialogKind(lines[len(lines)-1])
	if !ok {
		return ports.Dialog{}, false
	}
	lines = lines[:len(lines)-1]
	if kind == ports.DialogModel {
		for i, line := range lines {
			if strings.HasPrefix(line, "◐ ") || strings.HasPrefix(line, "○ ") || strings.HasPrefix(line, "Use /fast ") {
				lines = lines[:i]
				break
			}
		}
	}
	menu, ok := readNumberedMenu(lines)
	if !ok {
		return ports.Dialog{}, false
	}
	return ports.Dialog{Kind: kind, Title: dialogTitle(lines, kind), Menu: menu}, true
}

func (p *Plugin) AllowRow(menu ports.Menu) (int, bool) {
	return plainAnswerRow(menu, "Yes")
}

func (p *Plugin) DenyRow(menu ports.Menu) (int, bool) {
	return plainAnswerRow(menu, "No")
}

func (p *Plugin) ReadMenu(pane string) (ports.Menu, bool) {
	dialog, ok := p.ReadDialog(pane)
	if !ok {
		return ports.Menu{}, false
	}
	return dialog.Menu, true
}

func (p *Plugin) MenuKeys() ports.MenuKeys {
	return ports.MenuKeys{Up: "\x1b[A", Down: "\x1b[B", Select: "\r", Cancel: "\x1b", Multi: " ", SessionSelect: "s"}
}

func plainAnswerRow(menu ports.Menu, answer string) (int, bool) {
	found := -1
	for i, row := range menu.Rows {
		number, label, ok := strings.Cut(row, ". ")
		if !ok || label != answer {
			continue
		}
		index, err := strconv.Atoi(number)
		if err != nil || index < 1 {
			continue
		}
		if found >= 0 {
			return 0, false
		}
		found = i
	}
	if found < 0 {
		return 0, false
	}
	return found, true
}

func dialogKind(footer string) (ports.DialogKind, bool) {
	switch footer {
	case "Esc to cancel · Tab to amend":
		return ports.DialogPermission, true
	case "Enter to select · ↑/↓ to navigate · Esc to cancel":
		return ports.DialogQuestion, true
	case "Enter to set as default · s to use this session only · Esc to cancel":
		return ports.DialogModel, true
	default:
		return "", false
	}
}

func dialogTitle(lines []string, kind ports.DialogKind) string {
	for i, line := range lines {
		if kind == ports.DialogModel && line == "Select model" {
			return line
		}
		if kind != ports.DialogModel && i > 0 && strings.HasPrefix(strings.TrimSpace(strings.TrimPrefix(line, "❯")), "1. ") {
			return lines[i-1]
		}
	}
	return ""
}

func readNumberedMenu(lines []string) (ports.Menu, bool) {
	return terminalui.ReadNumberedMenu(lines, "❯")
}

func paneLines(pane string) []string {
	plain := claudeTerminalEscape.ReplaceAllString(strings.ReplaceAll(pane, "\r", "\n"), "")
	raw := strings.Split(plain, "\n")
	lines := raw[:0]
	for _, line := range raw {
		line = strings.TrimSpace(line)
		if line != "" {
			lines = append(lines, line)
		}
	}
	return lines[max(0, len(lines)-12):]
}

var _ ports.TerminalDialogReader = (*Plugin)(nil)
var _ ports.TerminalMenuReader = (*Plugin)(nil)
