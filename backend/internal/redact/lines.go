package redact

import (
	"sort"
	"strings"
)

const wrapLines = 2

func Lines(lines []string) []string {
	masked := make([][]hit, len(lines))
	continued := map[int]bool{}
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
			first, reachesEnd := -1, false
			for k, start := range starts {
				lo, hi := max(h.start, start), min(h.end, start+len(lines[from+k]))
				if lo >= hi {
					continue
				}
				masked[from+k] = append(masked[from+k], hit{lo - start, hi - start})
				if first < 0 {
					first = from + k
				}
				reachesEnd = hi == start+len(lines[from+k]) && from+k < len(lines)-1
			}
			if first > 0 && reachesEnd {
				continued[first] = true
			}
		}
	}
	joined := func(from, spaced int, sep string) []string {
		seps := make([]string, len(lines)-1-from)
		for k := range seps {
			seps[k] = sep
			if from+k == spaced {
				seps[k] = " "
			}
		}
		return seps
	}
	if len(lines) == 0 {
		return nil
	}
	for _, sep := range []string{"", " ", "\n"} {
		collect(0, joined(0, -1, sep))
	}
	for first := range lines {
		from := max(0, first-1)
		for last := first + 1; last < min(len(lines), first+wrapLines+1); last++ {
			to := min(len(lines)-1, last+1)
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
	for first := range continued {
		collect(first-1, joined(first-1, first-1, ""))
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
