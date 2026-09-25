package domain

import "testing"

func TestTerminalDisplayTitle(t *testing.T) {
	cases := []struct {
		raw  string
		want string
	}{
		{"◐ Number list 1 to 3000", "Number list 1 to 3000"},
		{"◑ Number list 1 to 3000", "Number list 1 to 3000"},
		{"◒ Fixing tests", "Fixing tests"},
		{"◓ Fixing tests", "Fixing tests"},
		{"✳ Claude Code", "Claude Code"},
		{"✳️ Emoji spinner", "Emoji spinner"},
		{"⠋ Braille spinner", "Braille spinner"},
		{"** two symbols", "two symbols"},
		{"✳ ", ""},
		{"✳", "✳"},
		{"", ""},
		{"   ", ""},
		{"~/dev/operator", "~/dev/operator"},
		{"vim main.go", "vim main.go"},
		{"1. first", "1. first"},
		{"◐  double space", "double space"},
		{"  ◐ padded  ", "padded"},
		{"◐ ◑ nested", "◑ nested"},
	}
	for _, tc := range cases {
		if got := TerminalDisplayTitle(tc.raw); got != tc.want {
			t.Errorf("TerminalDisplayTitle(%q) = %q, want %q", tc.raw, got, tc.want)
		}
	}
}
