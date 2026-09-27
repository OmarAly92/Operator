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
		{"a\u009b31mb", "ab"},
		{"a\u009d0;title\u0007b", "ab"},
		{"a\u009d0;title\u009cb", "ab"},
		{"a\x1bPpayload\x1b\\b", "ab"},
		{"a\u0090payload\u009cb", "ab"},
		{"a\x1b_apc\x1b\\b\x1b^pm\x1b\\c\x1bXsos\x1b\\d", "abcd"},
		{"a\u009fapc\u009cb\u009epm\u009cc\u0098sos\u009cd", "abcd"},
		{"a\x1bPunterminated payload", "a"},
		{"a\u0098unterminated payload", "a"},
		{"key sk-abcdefghij\u200bklmnopqrstuvwxyz end", "key [redacted] end"},
		{"key sk-\u200cabcdefghij\u2060klmnop\ufeffqrstuvwxyz\u200d end", "key [redacted] end"},
		{"", ""},
	} {
		if got := Clean(tc.in); got != tc.want {
			t.Errorf("Clean(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}
