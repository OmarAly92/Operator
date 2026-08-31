package terminalblock

import (
	"bytes"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestCapOutput(t *testing.T) {
	repeatLines := func(n, width int) []byte {
		var buf bytes.Buffer
		for i := 0; i < n; i++ {
			buf.WriteString(strings.Repeat("a", width))
			buf.WriteByte('\n')
		}
		return buf.Bytes()
	}

	cases := []struct {
		name       string
		in         []byte
		wantOut    func(orig []byte, out []byte) bool
		wantLines  func(orig, out []byte) int
		wantBytesF func(orig, out []byte) int
	}{
		{
			name:       "empty",
			in:         nil,
			wantOut:    func(_, out []byte) bool { return len(out) == 0 },
			wantLines:  func(_, _ []byte) int { return 0 },
			wantBytesF: func(_, _ []byte) int { return 0 },
		},
		{
			name:       "exactly at line cap untouched",
			in:         repeatLines(maxOutputLines, 4),
			wantOut:    func(orig, out []byte) bool { return bytes.Equal(orig, out) },
			wantLines:  func(_, _ []byte) int { return 0 },
			wantBytesF: func(_, _ []byte) int { return 0 },
		},
		{
			name:       "one over line cap drops the oldest",
			in:         repeatLines(maxOutputLines+1, 4),
			wantOut:    func(orig, out []byte) bool { return bytes.HasSuffix(orig, out) && !bytes.Equal(orig, out) },
			wantLines:  func(orig, out []byte) int { return bytes.Count(orig[:len(orig)-len(out)], []byte{'\n'}) },
			wantBytesF: func(orig, out []byte) int { return len(orig) - len(out) },
		},
		{
			name:       "exactly at byte cap untouched",
			in:         bytes.Repeat([]byte("a"), maxOutputBytes),
			wantOut:    func(orig, out []byte) bool { return bytes.Equal(orig, out) },
			wantLines:  func(_, _ []byte) int { return 0 },
			wantBytesF: func(_, _ []byte) int { return 0 },
		},
		{
			name:       "one over byte cap trims the front",
			in:         bytes.Repeat([]byte("a"), maxOutputBytes+1),
			wantOut:    func(orig, out []byte) bool { return len(out) == maxOutputBytes && bytes.HasSuffix(orig, out) },
			wantLines:  func(orig, out []byte) int { return bytes.Count(orig[:len(orig)-len(out)], []byte{'\n'}) },
			wantBytesF: func(orig, out []byte) int { return len(orig) - len(out) },
		},
		{
			name:       "both caps fire",
			in:         repeatLines(6000, 2000),
			wantOut:    func(orig, out []byte) bool { return len(out) <= maxOutputBytes && bytes.HasSuffix(orig, out) },
			wantLines:  func(orig, out []byte) int { return bytes.Count(orig[:len(orig)-len(out)], []byte{'\n'}) },
			wantBytesF: func(orig, out []byte) int { return len(orig) - len(out) },
		},
		{
			name: "non-utf8 bytes over the byte cap keep a rune boundary",
			in: func() []byte {
				b := bytes.Repeat([]byte{0xff, 0xfe}, (maxOutputBytes+200)/2)
				return b
			}(),
			wantOut: func(orig, out []byte) bool {
				return len(out) <= maxOutputBytes && bytes.HasSuffix(orig, out) && utf8.RuneStart(out[0])
			},
			wantLines:  func(orig, out []byte) int { return bytes.Count(orig[:len(orig)-len(out)], []byte{'\n'}) },
			wantBytesF: func(orig, out []byte) int { return len(orig) - len(out) },
		},
		{
			name:       "dropped prefix has fewer newlines than the line-cap drop",
			in:         append(bytes.Repeat([]byte("a"), maxOutputBytes), repeatLines(maxOutputLines+10, 4)...),
			wantOut:    func(orig, out []byte) bool { return len(out) <= maxOutputBytes && bytes.HasSuffix(orig, out) },
			wantLines:  func(orig, out []byte) int { return bytes.Count(orig[:len(orig)-len(out)], []byte{'\n'}) },
			wantBytesF: func(orig, out []byte) int { return len(orig) - len(out) },
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			orig := append([]byte(nil), tc.in...)
			out, gotLines, gotBytes := capOutput(tc.in)
			if !tc.wantOut(orig, out) {
				t.Fatalf("out mismatch: len(orig)=%d len(out)=%d", len(orig), len(out))
			}
			if want := tc.wantLines(orig, out); gotLines != want {
				t.Fatalf("omittedLines = %d, want %d", gotLines, want)
			}
			if want := tc.wantBytesF(orig, out); gotBytes != want {
				t.Fatalf("omittedBytes = %d, want %d", gotBytes, want)
			}
			if len(out) > 0 && len(orig) > 0 && !bytes.HasSuffix(orig, out) {
				t.Fatalf("output must always be a suffix of the input")
			}
		})
	}
}
