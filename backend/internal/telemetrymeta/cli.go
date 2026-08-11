package telemetrymeta

import "strings"

// NormalizeCommandPath canonicalizes command paths received from current CLIs
// and best-effort legacy loopback callers before cost-control classification.
func NormalizeCommandPath(commandPath string) string {
	return strings.ToLower(strings.Join(strings.Fields(commandPath), " "))
}

// IsRoutineInternalCLICommand reports whether a successful CLI invocation is
// routine desktop/agent plumbing rather than product usage.
func IsRoutineInternalCLICommand(commandPath string) bool {
	normalized := NormalizeCommandPath(commandPath)
	for _, routine := range routineInternalCLICommands {
		if normalized == routine || strings.HasPrefix(normalized, routine+" ") {
			return true
		}
	}
	return false
}

var routineInternalCLICommands = []string{
	"opr status",
	"opr session ls",
	"opr session get",
	"opr session agent-switch ls",
	"opr session handoff",
	"opr project ls",
	"opr project get",
	"opr orchestrator ls",
	"opr hooks",
	"opr pty-host",
}

// CLIActorType infers the actor for legacy loopback CLI telemetry requests that
// predate the explicit actor_type field. Unknown actor-less commands are treated
// as system activity so foreign/local automation cannot inflate DAU by default.
func CLIActorType(actorType, commandPath string) string {
	normalized := NormalizeCommandPath(commandPath)
	if _, ok := legacyActorlessSystemCLICommands[normalized]; ok {
		return "system"
	}

	switch actorType {
	case "agent", "user":
		return actorType
	case "system":
		return "system"
	}

	if _, ok := legacyActorlessUserCLICommands[normalized]; ok {
		return "user"
	}
	switch normalized {
	case "opr session agent-switch", "opr session agent-switch ls", "opr session switch-agent":
		return "user"
	}
	if normalized == "opr hooks" {
		return "agent"
	}
	return "system"
}

var legacyActorlessSystemCLICommands = map[string]struct{}{
	"opr agent-process":           {},
	"opr agent-process supervise": {},
	"opr completion":              {},
	"opr daemon":                  {},
	"opr help":                    {},
	"opr pty-host":                {},
	"opr start":                   {},
}

var legacyActorlessUserCLICommands = map[string]struct{}{
	"opr agent":                  {},
	"opr agent ls":               {},
	"opr browser":                {},
	"opr browser check":          {},
	"opr browser click":          {},
	"opr browser console":        {},
	"opr browser dblclick":       {},
	"opr browser devtools":       {},
	"opr browser devtools close": {},
	"opr browser devtools open":  {},
	"opr browser dialog":         {},
	"opr browser dialog accept":  {},
	"opr browser dialog dismiss": {},
	"opr browser dialog status":  {},
	"opr browser drag":           {},
	"opr browser errors":         {},
	"opr browser fill":           {},
	"opr browser focus":          {},
	"opr browser frame":          {},
	"opr browser get":            {},
	"opr browser highlight":      {},
	"opr browser hover":          {},
	"opr browser network":        {},
	"opr browser network clear":  {},
	"opr browser network list":   {},
	"opr browser network start":  {},
	"opr browser network status": {},
	"opr browser network stop":   {},
	"opr browser open":           {},
	"opr browser press":          {},
	"opr browser screenshot":     {},
	"opr browser scroll":         {},
	"opr browser scrollintoview": {},
	"opr browser select":         {},
	"opr browser snapshot":       {},
	"opr browser tab":            {},
	"opr browser tab close":      {},
	"opr browser tab new":        {},
	"opr browser tab select":     {},
	"opr browser status":         {},
	"opr browser tabs":           {},
	"opr browser type":           {},
	"opr browser uncheck":        {},
	"opr browser unhighlight":    {},
	"opr browser wait":           {},
	"opr dev":                    {},
	"opr dev import-projects":    {},
	"opr doctor":                 {},
	"opr import":                 {},
	"opr launch":                 {},
	"opr orchestrator":           {},
	"opr orchestrator done":      {},
	"opr pr":                     {},
	"opr pr merge":               {},
	"opr pr resolve-comments":    {},
	"opr preview":                {},
	"opr preview clear":          {},
	"opr preview start":          {},
	"opr preview status":         {},
	"opr preview stop":           {},
	"opr project":                {},
	"opr project add":            {},
	"opr project rm":             {},
	"opr project set-config":     {},
	"opr review":                 {},
	"opr review cancel":          {},
	"opr review ls":              {},
	"opr review submit":          {},
	"opr review trigger":         {},
	"opr send":                   {},
	"opr session":                {},
	"opr session claim-pr":       {},
	"opr session cleanup":        {},
	"opr session kill":           {},
	"opr session rename":         {},
	"opr session restore":        {},
	"opr spawn":                  {},
	"opr stop":                   {},
	"opr version":                {},

	// Legacy commands observed in PostHog's current billing-period data.
	"opr handoff":                   {},
	"opr project orchestration get": {},
	"opr project orchestration set": {},
	"opr smoke list":                {},
	"opr smoke set":                 {},
}
