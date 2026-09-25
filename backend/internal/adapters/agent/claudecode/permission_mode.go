package claudecode

import (
	"regexp"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

var _ ports.TerminalPermissionModeReader = (*Plugin)(nil)

var permissionModeFooters = []struct {
	marker string
	mode   domain.PermissionMode
}{
	{"accept edits on", domain.PermissionModeAcceptEdits},
	{"plan mode on", domain.PermissionModePlan},
	{"bypass permissions on", domain.PermissionModeBypassPermissions},
	{"auto mode on", domain.PermissionModeAuto},
	{"manual mode on", domain.PermissionModeDefault},
}

var permissionModeVerifiedVersions = map[string]struct{}{
	"2.1.280": {},
}

var dialogOptionPrompt = regexp.MustCompile(`^❯\s*\d+\.`)

func (p *Plugin) ReadPermissionMode(pane string) (domain.PermissionMode, bool) {
	lines := tasksPaneLines(pane)
	top := lastPromptLine(lines)
	if top < 0 || dialogOptionPrompt.MatchString(lines[top]) {
		return "", false
	}
	bottom := -1
	for i := top + 1; i < len(lines); i++ {
		if isRule(lines[i]) {
			bottom = i
			break
		}
	}
	if bottom < 0 {
		return "", false
	}
	for _, line := range lines[bottom+1:] {
		lower := strings.ToLower(line)
		for _, footer := range permissionModeFooters {
			if strings.Contains(lower, footer.marker) {
				return footer.mode, true
			}
		}
	}
	return "", false
}

func (p *Plugin) PermissionModeKeys() ports.PermissionModeKeys {
	return ports.PermissionModeKeys{Cycle: "\x1b[Z"}
}

func (p *Plugin) PermissionModeCycle(launch domain.PermissionMode) []domain.PermissionMode {
	cycle := []domain.PermissionMode{domain.PermissionModeDefault, domain.PermissionModeAcceptEdits, domain.PermissionModePlan}
	if launch == domain.PermissionModeBypassPermissions || launch == domain.PermissionModeAuto {
		cycle = append(cycle, launch)
	}
	return cycle
}

func (p *Plugin) PermissionModeVerified(version string) bool {
	_, ok := permissionModeVerifiedVersions[strings.TrimSpace(version)]
	return ok
}
