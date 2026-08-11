package telemetrymeta

import "testing"

func TestNormalizeCommandPath(t *testing.T) {
	if got := NormalizeCommandPath("  OPR   Hooks  claude-code  post-tool-use "); got != "opr hooks claude-code post-tool-use" {
		t.Fatalf("NormalizeCommandPath = %q, want normalized lowercase fields", got)
	}
}

func TestIsRoutineInternalCLICommandNormalizesLegacyShapes(t *testing.T) {
	for _, commandPath := range []string{
		"opr hooks",
		"opr  hooks",
		"OPR HOOKS",
		"opr hooks claude-code post-tool-use",
		"opr session get sess-123",
		"opr session agent-switch ls sess-123",
		"opr session handoff submit --switch switch-1",
		"opr project ls",
		"opr pty-host session-1",
	} {
		if !IsRoutineInternalCLICommand(commandPath) {
			t.Errorf("IsRoutineInternalCLICommand(%q) = false, want true", commandPath)
		}
	}
}

func TestCLIActorTypeKeepsKnownLegacyUserCommands(t *testing.T) {
	for _, commandPath := range []string{
		"opr agent ls",
		"opr session claim-pr",
		"opr session switch-agent",
		"opr session agent-switch",
		"opr session agent-switch ls",
		"opr dev import-projects",
		"opr project orchestration get",
		"opr project orchestration set",
		"opr handoff",
		"opr smoke list",
		"opr smoke set",
	} {
		if got := CLIActorType("", commandPath); got != "user" {
			t.Errorf("CLIActorType(%q) = %q, want user", commandPath, got)
		}
	}
}

func TestCLIActorTypeTreatsInternalAgentHandoffAsSystemByDefault(t *testing.T) {
	for _, commandPath := range []string{
		"opr session handoff",
		"opr session handoff submit",
	} {
		if got := CLIActorType("", commandPath); got != "system" {
			t.Errorf("CLIActorType(%q) = %q, want system", commandPath, got)
		}
	}
}

func TestCLIActorTypeSystemCommandsOverrideExplicitActor(t *testing.T) {
	for _, tc := range []struct {
		actorType   string
		commandPath string
	}{
		{actorType: "user", commandPath: "opr daemon"},
		{actorType: "agent", commandPath: "opr start"},
		{actorType: "user", commandPath: "OPR  AGENT-PROCESS  SUPERVISE"},
	} {
		if got := CLIActorType(tc.actorType, tc.commandPath); got != "system" {
			t.Errorf("CLIActorType(%q, %q) = %q, want system", tc.actorType, tc.commandPath, got)
		}
	}
}

func TestCLIActorTypeKeepsConservativeFallback(t *testing.T) {
	for _, tc := range []struct {
		actorType   string
		commandPath string
		want        string
	}{
		{actorType: "agent", commandPath: "opr surprise", want: "agent"},
		{actorType: "user", commandPath: "opr surprise", want: "user"},
		{actorType: "system", commandPath: "opr spawn", want: "system"},
		{commandPath: "opr daemon", want: "system"},
		{commandPath: "opr spawn", want: "user"},
		{commandPath: "opr surprise", want: "system"},
	} {
		if got := CLIActorType(tc.actorType, tc.commandPath); got != tc.want {
			t.Errorf("CLIActorType(%q, %q) = %q, want %q", tc.actorType, tc.commandPath, got, tc.want)
		}
	}
}
