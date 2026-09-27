package redact

import (
	"regexp"
	"strings"
	"unicode"
)

var terminalEscape = regexp.MustCompile(`(?:\x1b\]|\x{9d})(?s:.*?)(?:\x07|\x1b\\|\x{9c}|$)` +
	`|(?:\x1b[PX^_]|[\x{90}\x{98}\x{9e}\x{9f}])(?s:.*?)(?:\x1b\\|\x{9c}|$)` +
	`|(?:\x1b\[|\x{9b})[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]` +
	`|\x1b[\x20-\x2f]*[\x30-\x7e]`)

func Clean(s string) string {
	s = strings.ToValidUTF8(s, "")
	s = terminalEscape.ReplaceAllString(s, "")
	s = strings.Map(func(r rune) rune {
		if r == '\n' || r == '\t' {
			return r
		}
		if unicode.IsControl(r) || unicode.Is(unicode.Bidi_Control, r) || isZeroWidth(r) {
			return -1
		}
		return r
	}, s)
	return Text(s).Text
}

func isZeroWidth(r rune) bool {
	switch r {
	case '\u200b', '\u200c', '\u200d', '\u2060', '\ufeff':
		return true
	}
	return false
}
