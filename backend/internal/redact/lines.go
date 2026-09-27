package redact

import (
	"sort"
	"strings"
)

const wrapLines = 8

func Lines(lines []string) []string {
	masked := make([][]hit, len(lines))
	collect := func(from int, seps []string) {
		var b strings.Builder
		starts := make([]int, len(seps)+1)
		for k := range starts {
			if k > 0 {
				b.WriteString(seps[k-1])
			}
			starts[k] = b.Len()
			b.WriteString(lines[from+k])
		}
		for _, h := range find(b.String()) {
			for k, start := range starts {
				lo, hi := max(h.start, start), min(h.end, start+len(lines[from+k]))
				if lo < hi {
					masked[from+k] = append(masked[from+k], hit{lo - start, hi - start})
				}
			}
		}
	}
	if len(lines) > 0 {
		for _, sep := range []string{"", " ", "\n"} {
			seps := make([]string, len(lines)-1)
			for k := range seps {
				seps[k] = sep
			}
			collect(0, seps)
		}
	}
	for first := range lines {
		for last := first + 1; last < min(len(lines), first+wrapLines+1); last++ {
			from, to := max(0, first-1), min(len(lines)-1, last+1)
			seps := make([]string, to-from)
			for k := range seps {
				seps[k] = " "
				if from+k >= first && from+k < last {
					seps[k] = ""
				}
			}
			collect(from, seps)
		}
	}
	out := make([]string, len(lines))
	for i, line := range lines {
		out[i] = maskHits(line, masked[i])
	}
	return out
}

func maskHits(line string, hits []hit) string {
	if len(hits) == 0 {
		return line
	}
	sort.Slice(hits, func(i, j int) bool { return hits[i].start < hits[j].start })
	merged := []hit{hits[0]}
	for _, h := range hits[1:] {
		last := &merged[len(merged)-1]
		if h.start <= last.end {
			last.end = max(last.end, h.end)
			continue
		}
		merged = append(merged, h)
	}
	var b strings.Builder
	cursor := 0
	for _, h := range merged {
		b.WriteString(line[cursor:h.start])
		b.WriteString(mask)
		cursor = h.end
	}
	b.WriteString(line[cursor:])
	return b.String()
}
