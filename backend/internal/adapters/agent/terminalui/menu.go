package terminalui

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var numberedMenuRow = regexp.MustCompile(`^([1-9][0-9]*)\.\s+(.+)$`)

func ReadNumberedMenu(lines []string, marker string) (ports.Menu, bool) {
	menu := ports.Menu{Selected: -1}
	for _, line := range lines {
		selected := strings.HasPrefix(line, marker)
		row := strings.TrimSpace(strings.TrimPrefix(line, marker))
		match := numberedMenuRow.FindStringSubmatch(row)
		if match == nil {
			if selected {
				return ports.Menu{}, false
			}
			if len(menu.Rows) > 0 && strings.Trim(line, "─") != "" {
				menu.Rows[len(menu.Rows)-1] += " " + line
			}
			continue
		}
		number, err := strconv.Atoi(match[1])
		if err != nil || number != len(menu.Rows)+1 {
			return ports.Menu{}, false
		}
		if selected {
			if menu.Selected >= 0 {
				return ports.Menu{}, false
			}
			menu.Selected = len(menu.Rows)
		}
		menu.Rows = append(menu.Rows, row)
	}
	if len(menu.Rows) < 2 || menu.Selected < 0 {
		return ports.Menu{}, false
	}
	return menu, true
}
