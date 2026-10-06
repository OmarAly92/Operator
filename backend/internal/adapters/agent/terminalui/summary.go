package terminalui

import "strings"

func TurnSummary(lines []string, maxLines int) string {
	kept := contentLines(lines)
	return strings.Join(kept[max(0, len(kept)-maxLines):], "\n")
}

func MessageSummary(lines []string, maxLines int) string {
	kept := contentLines(lines)
	return strings.Join(kept[:min(len(kept), maxLines)], "\n")
}

func contentLines(lines []string) []string {
	var kept []string
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if isRule(line) {
			continue
		}
		kept = append(kept, line)
	}
	return kept
}

func isRule(line string) bool {
	return line == "" || strings.Trim(line, "─━═╌┄│╭╮╰╯ ") == ""
}
