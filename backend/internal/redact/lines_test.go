package redact

import (
	"reflect"
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
