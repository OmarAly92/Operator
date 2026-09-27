package terminalui

import (
	"strings"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

func LastNumberedMenu(lines []string, marker string) (ports.Menu, int, bool) {
	for i := len(lines) - 1; i >= 0; i-- {
		row := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(lines[i]), marker))
		if !strings.HasPrefix(row, "1. ") {
			continue
		}
		menu, ok := ReadNumberedMenu(lines[i:], marker)
		return menu, i, ok
	}
	return ports.Menu{}, -1, false
}

func Question(context []string, menu ports.Menu) ports.TerminalQuestion {
	var text []string
	for _, line := range context {
		line = strings.TrimSpace(line)
		if line == "" || strings.Trim(line, "─━═╌┄│╭╮╰╯ ") == "" {
			continue
		}
		text = append(text, line)
	}
	text = text[max(0, len(text)-3):]
	parts := append(append([]string{}, context...), menu.Rows...)
	return ports.TerminalQuestion{
		Text:     strings.Join(text, " · "),
		Identity: strings.Join(strings.Fields(strings.Join(parts, " ")), " "),
	}
}
