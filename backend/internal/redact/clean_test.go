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

func TestCleanDropsEveryInvisibleFormatRuneSoNoneCanSplitASecret(t *testing.T) {
	for _, r := range []rune{0x00ad, 0x061c, 0x180e, 0x200b, 0x200d, 0x2062, 0x2064, 0x206a, 0xfeff, 0xfff9, 0x110bd, 0x1d173, 0xe0001, 0xe0041, 0xe007f} {
		in := "key sk-abcdefghij" + string(r) + "klmnopqrstuvwxyz end"
		if got := Clean(in); got != "key [redacted] end" {
			t.Errorf("Clean with U+%04X = %q, want the secret masked and the rune dropped", r, got)
		}
	}
}

func TestCleanKeepsVisibleTextAndBreaksAnEmojiZWJSequenceIntoItsParts(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"café ✅ naïve 日本語 ❤️", "café ✅ naïve 日本語 ❤️"},
		{"family \U0001f468\u200d\U0001f469\u200d\U0001f467 done", "family \U0001f468\U0001f469\U0001f467 done"},
	} {
		if got := Clean(tc.in); got != tc.want {
			t.Errorf("Clean(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}
