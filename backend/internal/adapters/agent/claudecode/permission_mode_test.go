package claudecode

import (
	"slices"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

const permissionModeRule = "────────────────────────────────────────────────────────────"

func TestReadPermissionModeFromTheComposerFooter(t *testing.T) {
	box := permissionModeRule + "\n❯ \n" + permissionModeRule + "\n"
	tests := []struct {
		name string
		pane string
		want domain.PermissionMode
		ok   bool
	}{
		{"ask shows manual mode", box + "  ⏸ manual mode on · ? for shortcuts\n", domain.PermissionModeDefault, true},
		{"ask beside the agents hint", box + "  ⏸ manual mode on · esc to interrupt · ← 1 agent · ↓ to manage          46785 tokens\n", domain.PermissionModeDefault, true},
		{"no mode line is unknown", box + "  ? for shortcuts\n", "", false},
		{"an unknown mode line", box + "  ⏵⏵ foo mode on (shift+tab to cycle)\n", "", false},
		{"an unknown paused mode line", box + "  ⏸ something else mode on\n", "", false},
		{"accept edits", box + "  ⏵⏵ accept edits on (shift+tab to cycle)\n", domain.PermissionModeAcceptEdits, true},
		{"plan", box + "  ⏸ plan mode on (shift+tab to cycle)\n", domain.PermissionModePlan, true},
		{"bypass", box + "  ⏵⏵ bypass permissions on (shift+tab to cycle)\n", domain.PermissionModeBypassPermissions, true},
		{"auto beside the agents hint", box + "  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents\n                                     87856 tokens\n", domain.PermissionModeAuto, true},
		{"styled bypass under an update notice", box + "\x1b[38;5;220mUpdate available!\x1b[39m\n\x1b[38;5;211m⏵⏵ bypass permissions on\x1b[39m", domain.PermissionModeBypassPermissions, true},
		{"a draft in the composer", permissionModeRule + "\n❯ half a thought\n" + permissionModeRule + "\n  ⏸ plan mode on (shift+tab to cycle)\n", domain.PermissionModePlan, true},
		{"permission dialog", permissionModeRule + "\n Do you want to make this edit to main.go?\n❯ 1. Yes\n  2. Yes, and switch to accept edits (shift+tab)\n  3. No\n", "", false},
		{"dialog option right under a rule", permissionModeRule + "\n❯ 1. Yes\n  2. No\n" + permissionModeRule + "\n", "", false},
		{"no composer on screen", "compiling…\nstill going\n", "", false},
		{"composer without its bottom rule", permissionModeRule + "\n❯ \n", "", false},
	}
	p := &Plugin{}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := p.ReadPermissionMode(tt.pane)
			if got != tt.want || ok != tt.ok {
				t.Fatalf("ReadPermissionMode = %q, %v; want %q, %v", got, ok, tt.want, tt.ok)
			}
		})
	}
}

func TestPermissionModeCycleAddsALaunchModeThatCycles(t *testing.T) {
	p := &Plugin{}
	base := []domain.PermissionMode{domain.PermissionModeDefault, domain.PermissionModeAcceptEdits, domain.PermissionModePlan}
	if got := p.PermissionModeCycle(domain.PermissionModeDefault); !slices.Equal(got, base) {
		t.Fatalf("default launch cycle = %v", got)
	}
	if got := p.PermissionModeCycle(domain.PermissionModeBypassPermissions); !slices.Equal(got, append(slices.Clone(base), domain.PermissionModeBypassPermissions)) {
		t.Fatalf("bypass launch cycle = %v", got)
	}
	if got := p.PermissionModeCycle(domain.PermissionModeAuto); !slices.Equal(got, append(slices.Clone(base), domain.PermissionModeAuto)) {
		t.Fatalf("auto launch cycle = %v", got)
	}
}

func TestPermissionModeIsVerifiedOnlyOnTheCheckedVersion(t *testing.T) {
	p := &Plugin{}
	if !p.PermissionModeVerified("2.1.280") || p.PermissionModeVerified("2.1.279") || p.PermissionModeVerified("") {
		t.Fatal("the allow-list must be exactly 2.1.280")
	}
	if p.PermissionModeKeys().Cycle != "\x1b[Z" {
		t.Fatalf("cycle key = %q, want Shift+Tab", p.PermissionModeKeys().Cycle)
	}
}
