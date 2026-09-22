package redact

import (
	"strings"
	"testing"
)

func containsGoOnlySyntax(source string) bool {
	for _, token := range []string{"(?i)", "(?s)", "(?m)", "(?U)", "(?P<"} {
		if strings.Contains(source, token) {
			return true
		}
	}
	return false
}

func TestJSPatternsAreEcmaCompatibleAndCoverTheBuiltins(t *testing.T) {
	patterns := JSPatterns()
	if len(patterns) != len(builtinPatterns) {
		t.Fatalf("got %d patterns, want %d", len(patterns), len(builtinPatterns))
	}
	for _, pattern := range patterns {
		if pattern.Source == "" {
			t.Fatalf("empty source in %+v", pattern)
		}
		if containsGoOnlySyntax(pattern.Source) {
			t.Fatalf("pattern %q carries Go-only syntax that JavaScript cannot compile", pattern.Source)
		}
	}
	var sawCaseInsensitive bool
	for _, pattern := range patterns {
		if pattern.Flags == "i" {
			sawCaseInsensitive = true
		}
	}
	if !sawCaseInsensitive {
		t.Fatal("expected at least one case-insensitive pattern (the (?i) ones)")
	}
}

func TestEveryBuiltinPatternHasAJSForm(t *testing.T) {
	if len(builtinPatterns) != len(builtinJSPatterns) {
		t.Fatalf("%d Go patterns against %d JS forms: add the JS form beside the Go one", len(builtinPatterns), len(builtinJSPatterns))
	}
}
