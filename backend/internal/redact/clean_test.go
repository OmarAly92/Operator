package redact

import "testing"

func TestCleanMasksSecretsAndStripsEscapesAndControls(t *testing.T) {
	for _, tc := range []struct {
		in   string
		want string
	}{
		{"Run \x1b[31mcurl -H 'Authorization: Bearer abcdefghijklmnop1234'\x1b[0m\x1b]0;title\x07 now?\x07\u202e\x00\n\tnext\xff", "Run curl -H 'Authorization: Bearer [redacted]' now?\n\tnext"},
		{"key sk-abcdefghijklmnopqrstuvwxyz\u202e end\x9b", "key [redacted] end"},
		{"\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\ \x1b7saved\x1b8", "link saved"},
		{"plain text stays", "plain text stays"},
		{"", ""},
	} {
		if got := Clean(tc.in); got != tc.want {
			t.Fatalf("Clean(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}
