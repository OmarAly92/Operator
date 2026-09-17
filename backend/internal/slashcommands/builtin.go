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

var Builtin = []Command{
	{Name: "clear", Description: "Clear conversation history and free up context", Source: SourceBuiltin},
	{Name: "compact", Description: "Clear conversation history but keep a summary in context", Source: SourceBuiltin},
	{Name: "context", Description: "Show current context usage as a colored grid", Source: SourceBuiltin},
	{Name: "cost", Description: "Show the total cost and duration of the current session", Source: SourceBuiltin},
	{Name: "doctor", Description: "Diagnose and verify your Claude Code installation and settings", Source: SourceBuiltin},
	{Name: "export", Description: "Export the current conversation to a file or clipboard", Source: SourceBuiltin, Interactive: true},
	{Name: "help", Description: "Show help and available commands", Source: SourceBuiltin},
	{Name: "init", Description: "Initialize a new CLAUDE.md file with codebase documentation", Source: SourceBuiltin},
	{Name: "pr-comments", Description: "Get comments from a GitHub pull request", Source: SourceBuiltin},
	{Name: "release-notes", Description: "View release notes", Source: SourceBuiltin},
	{Name: "review", Description: "Review a pull request", Source: SourceBuiltin},
	{Name: "security-review", Description: "Complete a security review of the pending changes on the current branch", Source: SourceBuiltin},
	{Name: "status", Description: "Show Claude Code status including version, model, account, API connectivity, and tool statuses", Source: SourceBuiltin},
	{Name: "usage", Description: "Show plan usage limits", Source: SourceBuiltin},
	{Name: "add-dir", Description: "Add a new working directory", Source: SourceBuiltin, Interactive: true},
	{Name: "agents", Description: "Manage agent configurations", Source: SourceBuiltin, Interactive: true},
	{Name: "bug", Description: "Submit feedback about Claude Code", Source: SourceBuiltin, Interactive: true},
	{Name: "config", Description: "Open config panel", Source: SourceBuiltin, Interactive: true},
	{Name: "exit", Description: "Exit the REPL", Source: SourceBuiltin, Interactive: true},
	{Name: "hooks", Description: "Manage hook configurations for tool events", Source: SourceBuiltin, Interactive: true},
	{Name: "ide", Description: "Manage IDE integrations and show status", Source: SourceBuiltin, Interactive: true},
	{Name: "login", Description: "Sign in with your Anthropic account", Source: SourceBuiltin, Interactive: true},
	{Name: "logout", Description: "Sign out from your Anthropic account", Source: SourceBuiltin, Interactive: true},
	{Name: "mcp", Description: "Manage MCP servers", Source: SourceBuiltin, Interactive: true},
	{Name: "memory", Description: "Edit Claude memory files", Source: SourceBuiltin, Interactive: true},
	{Name: "model", Description: "Set the AI model for Claude Code", Source: SourceBuiltin, Interactive: true},
	{Name: "permissions", Description: "Manage allow & deny tool permission rules", Source: SourceBuiltin, Interactive: true},
	{Name: "resume", Description: "Resume a conversation", Source: SourceBuiltin, Interactive: true},
	{Name: "rewind", Description: "Restore the code and/or conversation to a previous point", Source: SourceBuiltin, Interactive: true},
	{Name: "statusline", Description: "Set up Claude Code's status line UI", Source: SourceBuiltin, Interactive: true},
	{Name: "terminal-setup", Description: "Install Shift+Enter key binding for newlines", Source: SourceBuiltin, Interactive: true},
	{Name: "vim", Description: "Toggle between Vim and Normal editing modes", Source: SourceBuiltin, Interactive: true},
}

var builtinByName = func() map[string]Command {
	byName := make(map[string]Command, len(Builtin))
	for _, c := range Builtin {
		byName[c.Name] = c
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
