package terminalui

import (
	"strings"

	"github.com/OmarAly92/operator/backend/internal/ports"
	"github.com/OmarAly92/operator/backend/internal/redact"
)

const questionLines = 6

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
	return QuestionAt(context, len(context), menu)
}

func QuestionAt(lines []string, start int, menu ports.Menu) ports.TerminalQuestion {
	from := max(0, start-questionLines)
	window := make([]string, 0, start-max(0, from-questionLines))
	for _, line := range lines[max(0, from-questionLines):start] {
		window = append(window, strings.TrimSpace(line))
	}
	masked := redact.Lines(window)
	context := lines[from:start]
	var text []string
	belowRule := false
	for _, line := range masked[len(masked)-len(context):] {
		if isRule(line) {
			belowRule = belowRule || line != ""
			continue
		}
		if belowRule {
			text, belowRule = nil, false
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
