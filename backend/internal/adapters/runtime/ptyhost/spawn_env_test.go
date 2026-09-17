package ptyhost

import (
	"slices"
	"testing"
)

func envValue(env []string, key string) (string, bool) {
	value := ""
	found := false
	for _, entry := range env {
		if len(entry) > len(key) && entry[:len(key)+1] == key+"=" {
			value = entry[len(key)+1:]
			found = true
		}
	}
	return value, found
}

func TestProcessEnvironmentStampsTerminalIdentity(t *testing.T) {
	t.Setenv("TERM", "")
	t.Setenv("COLORTERM", "")

	env := processEnvironment(nil)

	for _, want := range [][2]string{
		{"TERM", "xterm-256color"},
		{"COLORTERM", "truecolor"},
		{"TERM_PROGRAM", "Operator"},
	} {
		got, ok := envValue(env, want[0])
		if !ok {
			t.Fatalf("%s missing from the child environment", want[0])
		}
		if got != want[1] {
			t.Fatalf("%s = %q, want %q", want[0], got, want[1])
		}
	}
}

func TestProcessEnvironmentLetsOverridesWin(t *testing.T) {
	env := processEnvironment(map[string]string{"TERM": "dumb"})

	got, ok := envValue(env, "TERM")
	if !ok || got != "dumb" {
		t.Fatalf("TERM = %q (present %v), want \"dumb\"", got, ok)
	}
	if count := slices.IndexFunc(env, func(entry string) bool { return entry == "TERM=xterm-256color" }); count >= 0 {
		t.Fatalf("the default TERM was still appended alongside the override")
	}
}

func TestProcessEnvironmentKeepsTheInheritedEnvironment(t *testing.T) {
	t.Setenv("OPERATOR_SPAWN_ENV_PROBE", "kept")

	env := processEnvironment(nil)

	if got, ok := envValue(env, "OPERATOR_SPAWN_ENV_PROBE"); !ok || got != "kept" {
		t.Fatalf("inherited variable lost: %q (present %v)", got, ok)
	}
}

func TestProcessEnvironmentDoesNotInheritLauncherNoColor(t *testing.T) {
	t.Setenv("NO_COLOR", "1")
	if value, ok := envValue(processEnvironment(nil), "NO_COLOR"); ok {
		t.Fatalf("launcher NO_COLOR leaked into interactive terminal: %q", value)
	}
	if value, ok := envValue(processEnvironment(map[string]string{"NO_COLOR": "1"}), "NO_COLOR"); !ok || value != "1" {
		t.Fatalf("explicit NO_COLOR override lost: %q", value)
	}
}

func TestHostProcessEnvironmentRecordsTheSessionKeys(t *testing.T) {
	env := hostProcessEnvironment(map[string]string{"ZETA": "1", "ALPHA": "2"})

	if got, ok := envValue(env, sessionEnvKeysVar); !ok || got != "ALPHA,ZETA" {
		t.Fatalf("%s = %q (present %v), want the sorted session keys", sessionEnvKeysVar, got, ok)
	}
	if got, _ := envValue(env, "ALPHA"); got != "2" {
		t.Fatalf("ALPHA = %q, want 2", got)
	}
}

func TestRespawnEnvironmentDropsSessionKeysTheNewOverlayOmits(t *testing.T) {
	t.Setenv(sessionEnvKeysVar, "OPERATOR_RESPAWN_PROBE_GONE,OPERATOR_RESPAWN_PROBE_KEPT")
	t.Setenv("OPERATOR_RESPAWN_PROBE_GONE", "stale")
	t.Setenv("OPERATOR_RESPAWN_PROBE_KEPT", "stale")
	t.Setenv("OPERATOR_RESPAWN_PROBE_BASE", "base")

	env := respawnEnvironment(map[string]string{"OPERATOR_RESPAWN_PROBE_KEPT": "fresh"})

	if value, ok := envValue(env, "OPERATOR_RESPAWN_PROBE_GONE"); ok {
		t.Fatalf("a session key the respawn omitted survived from the host's own environment: %q", value)
	}
	if got, _ := envValue(env, "OPERATOR_RESPAWN_PROBE_KEPT"); got != "fresh" {
		t.Fatalf("kept key = %q, want fresh", got)
	}
	if got, _ := envValue(env, "OPERATOR_RESPAWN_PROBE_BASE"); got != "base" {
		t.Fatalf("base environment lost: %q", got)
	}
	if value, ok := envValue(env, sessionEnvKeysVar); ok {
		t.Fatalf("%s leaked into the child: %q", sessionEnvKeysVar, value)
	}
}
