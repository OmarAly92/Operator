package redact

import (
	"math/rand"
	"strings"
	"testing"
)

func secretBody(r *rand.Rand, n int) string {
	const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, n)
	for i := range b {
		b[i] = alphabet[r.Intn(len(alphabet))]
	}
	return string(b)
}

func charWrap(text string, width int) []string {
	var out []string
	for len(text) > width {
		out = append(out, text[:width])
		text = text[width:]
	}
	return append(out, text)
}

func wordWrap(text string, width int) []string {
	var out []string
	line := ""
	for _, w := range strings.Split(text, " ") {
		for w != "" {
			switch {
			case line == "" && len(w) <= width:
				line, w = w, ""
			case line == "":
				out = append(out, w[:width])
				w = w[width:]
			case len(line)+1+len(w) <= width:
				line, w = line+" "+w, ""
			case len(w) > width && len(line)+2 <= width:
				room := width - len(line) - 1
				out = append(out, line+" "+w[:room])
				line, w = "", w[room:]
			default:
				out = append(out, line)
				line = ""
			}
		}
	}
	if line != "" {
		out = append(out, line)
	}
	return out
}

func indentWrap(text string, width int) []string {
	var out []string
	for _, line := range wordWrap(text, max(1, width-2)) {
		out = append(out, strings.TrimSpace("  "+line))
	}
	return out
}

func leaksSecret(lines []string) bool {
	for _, line := range lines {
		if strings.ContainsFunc(line, func(r rune) bool { return (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') }) {
			return true
		}
	}
	return false
}

func TestLinesMasksSecretsWrappedAtEveryWidth(t *testing.T) {
	r := rand.New(rand.NewSource(7))
	secrets := []struct {
		name string
		make func() string
	}{
		{"ghp", func() string { return "ghp_" + secretBody(r, 36) }},
		{"sk", func() string { return "sk-" + secretBody(r, 48) }},
		{"jwt", func() string {
			return "authorization: bearer eyJ" + secretBody(r, 36) + "." + secretBody(r, 60) + "." + secretBody(r, 43)
		}},
		{"bearer", func() string { return "bearer " + secretBody(r, 40) }},
	}
	leads := []string{"we added the key", "the token is", "export gh=", "key:", "", "k", "a key", "wired key", "and then wired the new key", "set it to"}
	tails := []string{"", " done", "' https://x.test", ". and more words follow here"}
	wraps := []struct {
		name string
		wrap func(string, int) []string
	}{{"char", charWrap}, {"word", wordWrap}, {"indent", indentWrap}}
	leaks := 0
	for width := 4; width <= 120; width++ {
		for _, secret := range secrets {
			for i := range 3 {
				lead := leads[(width*3+i)%len(leads)]
				tail := tails[(width+i)%len(tails)]
				text := strings.TrimSpace(lead + " " + secret.make() + tail)
				for _, wrap := range wraps {
					lines := wrap.wrap(text, width)
					if got := Lines(lines); leaksSecret(got) {
						leaks++
						if leaks <= 10 {
							t.Errorf("width %d %s %s wrap %q leaks: %q", width, secret.name, wrap.name, lines, got)
						}
					}
				}
			}
		}
	}
	if leaks > 0 {
		t.Fatalf("%d wrapped secrets leaked", leaks)
	}
}

func screenOf(rows, cols int) []string {
	r := rand.New(rand.NewSource(11))
	words := []string{"the", "build", "passed", "and", "wired", "config", "into", "server", "tests", "run", "-", "x"}
	lines := make([]string, rows)
	for i := range lines {
		var b strings.Builder
		for b.Len() < cols {
			b.WriteString(words[r.Intn(len(words))])
			b.WriteByte(' ')
		}
		lines[i] = b.String()[:cols]
	}
	return lines
}

func BenchmarkLines40x200(b *testing.B) {
	lines := screenOf(40, 200)
	b.ResetTimer()
	for b.Loop() {
		Lines(lines)
	}
}

func BenchmarkLines40x200WithAWrappedToken(b *testing.B) {
	lines := screenOf(40, 200)
	lines[20] = lines[20][:190] + "Bearer eyJ"
	lines[21] = strings.Repeat("AbCdEfGh12", 20)
	lines[22] = strings.Repeat("ZyXwVu9876", 5) + lines[22][50:]
	b.ResetTimer()
	for b.Loop() {
		Lines(lines)
	}
}
