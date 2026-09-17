package slashcommands

import "testing"

func TestIsBuiltin(t *testing.T) {
	cases := []struct {
		message string
		want    bool
	}{
		{"/compact", true},
		{"/compact focus on the tests", true},
		{"  /compact  ", true},
		{"/clear\n", true},
		{"/sc:analyze", false},
		{"hello /compact", false},
		{"/", false},
		{"", false},
		{"/Compact", false},
		{"/compactor", false},
	}
	for _, tc := range cases {
		if got := IsBuiltin(tc.message); got != tc.want {
			t.Errorf("IsBuiltin(%q) = %v, want %v", tc.message, got, tc.want)
		}
	}
}

func TestLookupReturnsTheEntry(t *testing.T) {
	cmd, ok := Lookup("/model sonnet")
	if !ok || cmd.Name != "model" || !cmd.Interactive {
		t.Fatalf("Lookup(/model sonnet) = %+v, %v; want the interactive model entry", cmd, ok)
	}
	if _, ok := Lookup("/sc:analyze"); ok {
		t.Fatal("Lookup(/sc:analyze) matched a built-in")
	}
}

func TestLookupResolvesAliases(t *testing.T) {
	for alias, want := range map[string]string{"cost": "usage", "stats": "usage", "review": "code-review", "checkup": "doctor", "quit": "exit", "undo": "rewind"} {
		cmd, ok := Lookup("/" + alias)
		if !ok || cmd.Name != want {
			t.Errorf("Lookup(/%s) = %+v, %v; want %s", alias, cmd, ok, want)
		}
	}
}

func TestBuiltinTableIsWellFormed(t *testing.T) {
	seen := map[string]bool{}
	for _, c := range Builtin {
		if c.Name == "" || c.Description == "" {
			t.Errorf("entry %+v is missing a name or description", c)
		}
		if c.Source != SourceBuiltin {
			t.Errorf("%s: source = %q, want %q", c.Name, c.Source, SourceBuiltin)
		}
		if seen[c.Name] {
			t.Errorf("%s listed twice", c.Name)
		}
		seen[c.Name] = true
	}
	for alias, name := range builtinAliases {
		if seen[alias] {
			t.Errorf("alias %s collides with a listed command", alias)
		}
		if !seen[name] {
			t.Errorf("alias %s points at %s, which is not listed", alias, name)
		}
	}
	for _, name := range []string{"compact", "clear", "model", "usage"} {
		if !seen[name] {
			t.Errorf("%s missing from Builtin", name)
		}
	}
}

func TestPanelCommandsAreInteractive(t *testing.T) {
	for _, name := range []string{"export", "cost", "status", "usage", "help", "release-notes"} {
		if cmd, ok := Lookup("/" + name); !ok || !cmd.Interactive {
			t.Errorf("/%s opens an Esc-to-cancel panel on Claude Code 2.1 and must be interactive; got %+v, %v", name, cmd, ok)
		}
	}
	for _, name := range []string{"context", "doctor", "compact", "clear", "code-review", "recap", "reload-plugins"} {
		if cmd, _ := Lookup("/" + name); cmd.Interactive {
			t.Errorf("/%s prints inline or runs an ordinary turn and must stay non-interactive", name)
		}
	}
}
