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
	for _, name := range []string{"compact", "clear", "model", "cost"} {
		if !seen[name] {
			t.Errorf("%s missing from Builtin", name)
		}
	}
}
