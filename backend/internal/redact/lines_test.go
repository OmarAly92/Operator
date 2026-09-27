package redact

import (
	"reflect"
	"strconv"
	"strings"
	"testing"
)

func TestLinesMasksEveryPartOfASecretThatWrapsAcrossLines(t *testing.T) {
	tests := []struct {
		name string
		in   []string
		want []string
	}{
		{"keyword above the token", []string{"curl -H 'Authorization: Bearer", "abcdefghijklmnop1234' https://x.test", "done"}, []string{"curl -H 'Authorization: Bearer", "[redacted]' https://x.test", "done"}},
		{"token cut in the middle", []string{"key sk-abcdefghij", "klmnopqrstuvwxyz end"}, []string{"key [redacted]", "[redacted] end"}},
		{"secret at a line end", []string{"password=hunter2hunter2", "next line"}, []string{"password=[redacted]", "[redacted] line"}},
		{"nothing to mask", []string{"ls -la", "", "total 0"}, []string{"ls -la", "", "total 0"}},
	}
	for _, tt := range tests {
		if got := Lines(tt.in); !reflect.DeepEqual(got, tt.want) {
			t.Errorf("%s: Lines(%q) = %q, want %q", tt.name, tt.in, got, tt.want)
		}
	}
}

func TestLinesMasksATokenCutAfterAWordOnTheLineAbove(t *testing.T) {
	got := Lines([]string{"and wired the key", "sk-proj-AbCd", "EfGhIjKlMnOpQrStUvWxYz0123 into .env."})
	want := []string{"and wired the key", "[redacted]", "[redacted] into .env."}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Lines = %q, want %q", got, want)
	}
}

func TestLinesMasksATokenWrappedOverManyLines(t *testing.T) {
	got := Lines([]string{"Authorization: Bearer", "eyJhbGciOi", "JIUzI1NiIs", "InR5cCI6Ik", "pXVCJ9 sent"})
	want := []string{"Authorization: Bearer", "[redacted]", "[redacted]", "[redacted]", "[redacted] sent"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Lines = %q, want %q", got, want)
	}
}

func longToken() string {
	var b strings.Builder
	for i := 0; b.Len() < 900; i++ {
		b.WriteString("eyJ" + strconv.Itoa(i*7919) + "aZ" + strconv.Itoa(i) + "q_")
	}
	return b.String()[:900]
}

func wrapAt(text string, cols int) []string {
	var out []string
	for len(text) > cols {
		out = append(out, text[:cols])
		text = text[cols:]
	}
	return append(out, text)
}

func TestLinesMasksALongBearerTokenWrappedOverFifteenLines(t *testing.T) {
	token := longToken()
	lines := append([]string{"curl -H 'Authorization: Bearer"}, wrapAt(token+"' https://x.test", 60)...)
	got := strings.Join(Lines(lines), "\n")
	for i := 0; i+8 <= len(token); i++ {
		if strings.Contains(got, token[i:i+8]) {
			t.Fatalf("Lines leaks %q of the token:\n%s", token[i:i+8], got)
		}
	}
	if !strings.HasPrefix(got, "curl -H 'Authorization: Bearer\n") || !strings.HasSuffix(got, "' https://x.test") {
		t.Fatalf("Lines = %q", got)
	}
}

func TestLinesMasksAWrappedSecretSplitByAnInvisibleFormatRune(t *testing.T) {
	for _, r := range []rune{0x00ad, 0x200b, 0x200d, 0x2062, 0xe0041} {
		got := strings.Join(Lines([]string{"key sk-abcdefghij" + string(r), "klmnopqrstuvwxyz end"}), "\n")
		if strings.Contains(got, "abcdefghij") || strings.Contains(got, "klmnopqrstuvwxyz") || strings.ContainsRune(got, r) {
			t.Errorf("Lines with U+%04X = %q, want the secret masked and the rune dropped", r, got)
		}
	}
}
