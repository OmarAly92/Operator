package ptyhost

import (
	"os"
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
	if len(env) < len(os.Environ()) {
		t.Fatalf("child environment %d entries, shorter than the parent's %d", len(env), len(os.Environ()))
	}
}
