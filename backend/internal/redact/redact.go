// Package redact removes secret-shaped runs from text before it is persisted
// or transmitted. Operator's blocks leave the machine that produced them —
// they cross a WebSocket to a phone and land in sqlite — so redaction must
// happen here, daemon-side, and never in a client.
//
// Matches are replaced with a fixed mask rather than deleted, so the UI can
// show that something was removed. An invisible redaction is its own bug when
// someone is reading output to debug.
package redact

import (
	"regexp"
	"sort"
)

const mask = "[redacted]"

// Span marks a redacted run. Offsets index the returned Result.Text.
type Span struct {
	Start int `json:"start"`
	End   int `json:"end"`
}

// Result is redacted text plus where the removals landed.
type Result struct {
	Text  string `json:"text"`
	Spans []Span `json:"spans,omitempty"`
}

// patterns errs toward redacting too much. A false positive costs a reader one
// masked token; a false negative ships a live credential to a phone.
var patterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)\bAKIA[0-9A-Z]{16}\b`),
	regexp.MustCompile(`\bgh[pousr]_[A-Za-z0-9]{20,}\b`),
	regexp.MustCompile(`\bsk-[A-Za-z0-9_\-]{20,}\b`),
	regexp.MustCompile(`(?i)(bearer\s+)[A-Za-z0-9._\-]{16,}`),
	regexp.MustCompile(`(?i)((?:api[_\-]?key|secret|token|password)\s*[:=]\s*)[^\s"']{8,}`),
	regexp.MustCompile(`([a-z][a-z0-9+.\-]*://[^\s:/@]+:)[^\s@]+(@)`),
}

// Text redacts s. Patterns with a leading capture group keep that group and
// mask only the tail, so "Bearer <token>" stays readable as "Bearer [redacted]".
func Text(s string) Result {
	if s == "" {
		return Result{}
	}
	type hit struct{ start, end int }
	var hits []hit
	for _, re := range patterns {
		for _, m := range re.FindAllStringSubmatchIndex(s, -1) {
			start, end := m[0], m[1]
			if len(m) >= 4 && m[2] == m[0] && m[3] > m[2] {
				start = m[3]
			}
			if len(m) >= 6 && m[4] >= 0 && m[5] == m[1] {
				end = m[4]
			}
			if end > start {
				hits = append(hits, hit{start, end})
			}
		}
	}
	if len(hits) == 0 {
		return Result{Text: s}
	}
	sort.Slice(hits, func(i, j int) bool { return hits[i].start < hits[j].start })

	var out []byte
	var spans []Span
	cursor, lastEnd := 0, -1
	for _, h := range hits {
		if h.start < lastEnd {
			continue
		}
		out = append(out, s[cursor:h.start]...)
		spans = append(spans, Span{Start: len(out), End: len(out) + len(mask)})
		out = append(out, mask...)
		cursor, lastEnd = h.end, h.end
	}
	out = append(out, s[cursor:]...)
	return Result{Text: string(out), Spans: spans}
}
