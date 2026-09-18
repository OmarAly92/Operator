package ticket

import (
	"regexp"
	"strings"
	"unicode"
)

const maxSlugLen = 48

var slugPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,47}$`)

func validSlug(s string) bool {
	return slugPattern.MatchString(s)
}

func slugify(title string) string {
	var b strings.Builder
	lastDash := true
	for _, r := range strings.ToLower(title) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
			lastDash = false
		case unicode.IsLetter(r) || unicode.IsDigit(r) || unicode.IsSpace(r) || unicode.IsPunct(r) || unicode.IsSymbol(r):
			if !lastDash {
				b.WriteByte('-')
				lastDash = true
			}
		}
	}
	out := strings.Trim(b.String(), "-")
	if len(out) > maxSlugLen {
		out = strings.Trim(out[:maxSlugLen], "-")
	}
	if out == "" {
		return "ticket"
	}
	return out
}
