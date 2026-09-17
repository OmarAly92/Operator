package slashcommands

import "strings"

const (
	SourceBuiltin = "builtin"
	SourceUser    = "user"
	SourceProject = "project"
	SourcePlugin  = "plugin"
)

type Command struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Source      string `json:"source"`
	Interactive bool   `json:"interactive"`
}

var builtinAliases = map[string]string{
	"allowed-tools": "permissions",
	"checkpoint":    "rewind",
	"checkup":       "doctor",
	"cost":          "usage",
	"name":          "rename",
	"quit":          "exit",
	"review":        "code-review",
	"stats":         "usage",
	"undo":          "rewind",
}

var Builtin = []Command{
	{Name: "add-dir", Description: "Add a new working directory", Source: SourceBuiltin, Interactive: true},
	{Name: "background", Description: "Send this session to the background and free the terminal", Source: SourceBuiltin, Interactive: true},
	{Name: "branch", Description: "Create a branch of the current conversation at this point", Source: SourceBuiltin, Interactive: true},
	{Name: "btw", Description: "Ask a quick side question without interrupting the main conversation", Source: SourceBuiltin, Interactive: true},
	{Name: "bug", Description: "Report a bug or share your conversation", Source: SourceBuiltin, Interactive: true},
	{Name: "cd", Description: "Move this session to a new working directory", Source: SourceBuiltin, Interactive: true},
	{Name: "clear", Description: "Start a new session with empty context; previous session stays on disk", Source: SourceBuiltin},
	{Name: "cloud-plugins", Description: "Choose whether cloud sessions use the plugins enabled on this machine", Source: SourceBuiltin, Interactive: true},
	{Name: "code-review", Description: "Review the current diff or a PR for bugs and cleanups", Source: SourceBuiltin},
	{Name: "color", Description: "Set the prompt bar color for this session", Source: SourceBuiltin, Interactive: true},
	{Name: "compact", Description: "Free up context by summarizing the conversation so far", Source: SourceBuiltin},
	{Name: "config", Description: "Open settings", Source: SourceBuiltin, Interactive: true},
	{Name: "context", Description: "Visualize current context usage as a colored grid", Source: SourceBuiltin},
	{Name: "copy", Description: "Copy Claude's last response to clipboard", Source: SourceBuiltin, Interactive: true},
	{Name: "daemon", Description: "Manage background services and routines", Source: SourceBuiltin, Interactive: true},
	{Name: "doctor", Description: "Health-check your setup and fix issues", Source: SourceBuiltin},
	{Name: "effort", Description: "Set effort level for model usage", Source: SourceBuiltin, Interactive: true},
	{Name: "exit", Description: "Exit the CLI", Source: SourceBuiltin, Interactive: true},
	{Name: "export", Description: "Export the current conversation to a file or clipboard", Source: SourceBuiltin, Interactive: true},
	{Name: "fast", Description: "Toggle fast mode", Source: SourceBuiltin, Interactive: true},
	{Name: "feedback", Description: "Send feedback to Anthropic or report a bug", Source: SourceBuiltin, Interactive: true},
	{Name: "focus", Description: "Toggle focus view: just your prompt, summary, and response", Source: SourceBuiltin, Interactive: true},
	{Name: "fork", Description: "Copy this conversation into a new background session and keep working here", Source: SourceBuiltin, Interactive: true},
	{Name: "goal", Description: "Set a goal Claude checks before stopping", Source: SourceBuiltin, Interactive: true},
	{Name: "help", Description: "Show help and available commands", Source: SourceBuiltin, Interactive: true},
	{Name: "hooks", Description: "View hook configurations for tool events", Source: SourceBuiltin, Interactive: true},
	{Name: "ide", Description: "Manage IDE integrations and show status", Source: SourceBuiltin, Interactive: true},
	{Name: "init", Description: "Initialize a new CLAUDE.md file with codebase documentation", Source: SourceBuiltin},
	{Name: "insights", Description: "Generate a report analyzing your Claude Code sessions", Source: SourceBuiltin},
	{Name: "install", Description: "Install Claude Code native build", Source: SourceBuiltin, Interactive: true},
	{Name: "install-github-app", Description: "Set up Claude GitHub Actions for a repository", Source: SourceBuiltin, Interactive: true},
	{Name: "install-slack-app", Description: "Install the Claude Slack app", Source: SourceBuiltin, Interactive: true},
	{Name: "keybindings", Description: "Open your keyboard shortcuts file", Source: SourceBuiltin, Interactive: true},
	{Name: "list-agents", Description: "List subagents, teammates, and other Claude sessions you can message", Source: SourceBuiltin},
	{Name: "login", Description: "Sign in with your Anthropic account", Source: SourceBuiltin, Interactive: true},
	{Name: "logout", Description: "Sign out from your Anthropic account", Source: SourceBuiltin, Interactive: true},
	{Name: "loops", Description: "List, create, and delete loops", Source: SourceBuiltin, Interactive: true},
	{Name: "mcp", Description: "Manage MCP servers", Source: SourceBuiltin, Interactive: true},
	{Name: "memory", Description: "Edit CLAUDE.md files and memory settings", Source: SourceBuiltin, Interactive: true},
	{Name: "mobile", Description: "Show QR code to download the Claude mobile app", Source: SourceBuiltin, Interactive: true},
	{Name: "model", Description: "Set the AI model for Claude Code", Source: SourceBuiltin, Interactive: true},
	{Name: "permissions", Description: "Manage allow and deny tool permission rules", Source: SourceBuiltin, Interactive: true},
	{Name: "plan", Description: "Enable plan mode or view the current session plan", Source: SourceBuiltin, Interactive: true},
	{Name: "plugin", Description: "Manage Claude Code plugins", Source: SourceBuiltin, Interactive: true},
	{Name: "powerup", Description: "Discover Claude Code features through quick interactive lessons", Source: SourceBuiltin, Interactive: true},
	{Name: "privacy-settings", Description: "View and update your privacy settings", Source: SourceBuiltin, Interactive: true},
	{Name: "recap", Description: "Generate a one-line session recap now", Source: SourceBuiltin},
	{Name: "release-notes", Description: "View release notes", Source: SourceBuiltin, Interactive: true},
	{Name: "reload-plugins", Description: "Activate pending plugin changes in the current session", Source: SourceBuiltin},
	{Name: "reload-skills", Description: "Pick up skills added or changed on disk during this session", Source: SourceBuiltin},
	{Name: "rename", Description: "Rename the current conversation", Source: SourceBuiltin, Interactive: true},
	{Name: "resume", Description: "Resume a previous conversation", Source: SourceBuiltin, Interactive: true},
	{Name: "rewind", Description: "Restore the code and/or conversation to a previous point", Source: SourceBuiltin, Interactive: true},
	{Name: "scroll-speed", Description: "Adjust mouse wheel scroll speed", Source: SourceBuiltin, Interactive: true},
	{Name: "security-review", Description: "Complete a security review of the pending changes on the current branch", Source: SourceBuiltin},
	{Name: "skill-doctor", Description: "Show which loaded skills are unused and costing context", Source: SourceBuiltin, Interactive: true},
	{Name: "skills", Description: "List available skills", Source: SourceBuiltin, Interactive: true},
	{Name: "status", Description: "Show Claude Code status including version, model, account, API connectivity, and tool statuses", Source: SourceBuiltin, Interactive: true},
	{Name: "statusline", Description: "Set up Claude Code's status line UI", Source: SourceBuiltin},
	{Name: "subtask", Description: "Send a subagent off with your full context; its result comes back here", Source: SourceBuiltin, Interactive: true},
	{Name: "tasks", Description: "View and manage everything running in the background", Source: SourceBuiltin, Interactive: true},
	{Name: "terminal-setup", Description: "Install Shift+Enter key binding for newlines", Source: SourceBuiltin, Interactive: true},
	{Name: "theme", Description: "Change the theme", Source: SourceBuiltin, Interactive: true},
	{Name: "tui", Description: "Set the terminal UI renderer (default | fullscreen)", Source: SourceBuiltin, Interactive: true},
	{Name: "ultraplan", Description: "Draft an editable plan in Claude Code on the web", Source: SourceBuiltin, Interactive: true},
	{Name: "ultrareview", Description: "Find and verify bugs in your branch using Claude Code on the web", Source: SourceBuiltin, Interactive: true},
	{Name: "upgrade", Description: "Upgrade to Max for higher rate limits and more Opus", Source: SourceBuiltin, Interactive: true},
	{Name: "usage", Description: "Show session cost, plan usage, and activity stats", Source: SourceBuiltin, Interactive: true},
	{Name: "usage-credits", Description: "Configure usage credits or request them from your admin when you hit a limit", Source: SourceBuiltin, Interactive: true},
	{Name: "version", Description: "Show this session's version", Source: SourceBuiltin, Interactive: true},
	{Name: "voice", Description: "Toggle voice mode", Source: SourceBuiltin, Interactive: true},
	{Name: "workflows", Description: "Browse running and completed workflows", Source: SourceBuiltin, Interactive: true},
}

var builtinByName = func() map[string]Command {
	byName := make(map[string]Command, len(Builtin))
	for _, c := range Builtin {
		byName[c.Name] = c
	}
	for alias, name := range builtinAliases {
		byName[alias] = byName[name]
	}
	return byName
}()

func Lookup(message string) (Command, bool) {
	fields := strings.Fields(message)
	if len(fields) == 0 || !strings.HasPrefix(fields[0], "/") {
		return Command{}, false
	}
	cmd, ok := builtinByName[fields[0][1:]]
	return cmd, ok
}

func IsBuiltin(message string) bool {
	_, ok := Lookup(message)
	return ok
}
