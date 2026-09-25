package domain

import (
	"strings"
	"unicode"
)

func TerminalDisplayTitle(raw string) string {
	runes := []rune(strings.TrimLeftFunc(raw, unicode.IsSpace))
	lead := 0
	for lead < len(runes) && !unicode.IsLetter(runes[lead]) && !unicode.IsDigit(runes[lead]) && !unicode.IsSpace(runes[lead]) {
		lead++
	}
	if lead > 0 && lead < len(runes) && runes[lead] == ' ' {
		runes = runes[lead+1:]
	}
	return strings.TrimSpace(string(runes))
}
