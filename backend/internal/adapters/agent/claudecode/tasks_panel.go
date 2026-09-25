package claudecode

import (
	"regexp"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var (
	tasksPanelRow    = regexp.MustCompile(`^(❯\s+)?(.+?) \(([a-z][a-z ]*)\)(?: · .*)?$`)
	tasksPanelHeader = regexp.MustCompile(`^[A-Z][A-Za-z ]* \(\d+\)$`)
	tasksPanelStatus = regexp.MustCompile(`(?:^|\s)(Completed|Failed|Stopped) · `)
)

func (p *Plugin) ReadTasksPanel(pane string) (ports.TasksPanel, bool) {
	lines := tasksPaneLines(pane)
	if len(lines) == 0 {
		return ports.TasksPanel{}, false
	}
	at, detail := panelFooter(lines)
	if at < 0 {
		return ports.TasksPanel{}, false
	}
	body := panelBody(lines[:at])
	if len(body) == 0 {
		return ports.TasksPanel{}, false
	}
	if detail {
		return readTasksDetail(body, footerOffersStop(lines[at]))
	}
	return readTasksList(body)
}

func (p *Plugin) TasksPanelKeys() ports.TasksPanelKeys {
	return ports.TasksPanelKeys{
		Command: "/tasks",
		Submit:  "\r",
		Clear:   "\x15",
		Up:      "\x1b[A",
		Down:    "\x1b[B",
		View:    "\r",
		Stop:    "x",
		Close:   "\x1b",
	}
}

var tasksPanelVerifiedVersions = map[string]struct{}{
	"2.1.280": {},
}

func (p *Plugin) TasksPanelVerified(version string) bool {
	_, ok := tasksPanelVerifiedVersions[strings.TrimSpace(version)]
	return ok
}

func (p *Plugin) TasksCommandReady(pane string) bool {
	lines := tasksPaneLines(pane)
	at := lastPromptLine(lines)
	if at < 0 || lines[at] != "❯ /tasks" || at+2 >= len(lines) || !isRule(lines[at+1]) {
		return false
	}
	rest, ok := strings.CutPrefix(lines[at+2], "/tasks")
	return ok && (rest == "" || strings.HasPrefix(rest, " "))
}

func (p *Plugin) TasksCommandTyped(pane string) bool {
	lines := tasksPaneLines(pane)
	at := lastPromptLine(lines)
	return at >= 0 && lines[at] == "❯ /tasks"
}

func lastPromptLine(lines []string) int {
	for i := len(lines) - 1; i >= 0; i-- {
		if strings.HasPrefix(lines[i], "❯") && i > 0 && isRule(lines[i-1]) {
			return i
		}
	}
	return -1
}

func tasksPaneLines(pane string) []string {
	plain := claudeTerminalEscape.ReplaceAllString(strings.ReplaceAll(pane, "\r", "\n"), "")
	plain = strings.ReplaceAll(plain, "\u00a0", " ")
	var lines []string
	for _, line := range strings.Split(plain, "\n") {
		if line = strings.TrimSpace(line); line != "" {
			lines = append(lines, line)
		}
	}
	return lines
}

func panelFooter(lines []string) (int, bool) {
	for i := len(lines) - 1; i >= 0; i-- {
		line := lines[i]
		list := strings.HasPrefix(line, "↑/↓ to select") && strings.HasSuffix(line, "Esc to close")
		detail := strings.Contains(line, "Esc/Enter/Space to close")
		if !list && !detail {
			continue
		}
		if i == len(lines)-1 || isRule(lines[i+1]) {
			return i, detail
		}
		return -1, false
	}
	return -1, false
}

func footerOffersStop(footer string) bool {
	for _, hint := range strings.Split(footer, " · ") {
		if strings.TrimSpace(hint) == "x to stop" {
			return true
		}
	}
	return false
}

func panelBody(lines []string) []string {
	for i := len(lines) - 1; i >= 0; i-- {
		if isRule(lines[i]) {
			return lines[i+1:]
		}
	}
	return nil
}

func isRule(line string) bool {
	return line != "" && strings.Trim(line, "─") == ""
}

func readTasksList(body []string) (ports.TasksPanel, bool) {
	if body[0] != "Background" {
		return ports.TasksPanel{}, false
	}
	panel := ports.TasksPanel{Selected: -1}
	for _, line := range body[1:] {
		if tasksPanelHeader.MatchString(line) {
			continue
		}
		match := tasksPanelRow.FindStringSubmatch(line)
		if match == nil {
			continue
		}
		if match[1] != "" {
			panel.Selected = len(panel.Rows)
		}
		panel.Rows = append(panel.Rows, ports.TasksPanelRow{Label: strings.TrimSpace(match[2]), Status: match[3]})
	}
	if len(panel.Rows) == 0 {
		return ports.TasksPanel{}, false
	}
	return panel, true
}

func readTasksDetail(body []string, stoppable bool) (ports.TasksPanel, bool) {
	panel := ports.TasksPanel{Detail: true, Selected: -1, DetailStatus: "unknown"}
	if body[0] == "Shell details" || body[0] == "Monitor details" {
		status := ""
		for _, line := range body[1:] {
			if value, ok := strings.CutPrefix(line, "Status:"); ok && status == "" {
				status = strings.TrimSpace(value)
			}
			if value, ok := strings.CutPrefix(line, "Command:"); ok && panel.DetailLabel == "" {
				panel.DetailLabel = strings.TrimSpace(value)
			}
		}
		switch {
		case status == "running" && stoppable:
			panel.DetailStatus = "running"
		case status != "" && status != "running":
			panel.DetailStatus = status
		}
		return panel, panel.DetailLabel != ""
	}
	_, label, ok := strings.Cut(body[0], " › ")
	if !ok || strings.TrimSpace(label) == "" {
		return ports.TasksPanel{}, false
	}
	panel.DetailLabel = strings.TrimSpace(label)
	finished := ""
	if len(body) > 1 {
		if match := tasksPanelStatus.FindStringSubmatch(body[1]); match != nil {
			finished = strings.ToLower(match[1])
		}
	}
	switch {
	case finished != "":
		panel.DetailStatus = finished
	case stoppable:
		panel.DetailStatus = "running"
	}
	return panel, true
}

var _ ports.TerminalTasksPanelReader = (*Plugin)(nil)
