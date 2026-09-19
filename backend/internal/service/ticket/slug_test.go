package ticket

import (
	"strings"
	"testing"
)

func TestSlugify(t *testing.T) {
	cases := map[string]string{
		"Planning Tickets":             "planning-tickets",
		"  Add   CodeMirror editor!! ": "add-codemirror-editor",
		"Ünïcödé ✓ title":              "n-c-d-title",
		"---":                          "ticket",
		"":                             "ticket",
		strings.Repeat("a", 60):        strings.Repeat("a", 48),
		"Trailing-":                    "trailing",
	}
	for in, want := range cases {
		if got := slugify(in); got != want {
			t.Errorf("slugify(%q) = %q want %q", in, got, want)
		}
	}
}
