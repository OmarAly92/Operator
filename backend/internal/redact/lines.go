package redact

import (
	"sort"
	"strings"
)

const (
	wrapLines = 2
	wrapBytes = 64
	keyBytes  = 32
)

type wrapRun struct{ lo, first int }

func Lines(lines []string) []string {
	if len(lines) == 0 {
		return nil
	}
	visible := make([]string, len(lines))
	for i, line := range lines {
		visible[i] = dropInvisible(line)
	}
	lines = visible
	masked := make([][]hit, len(lines))
	continued := map[wrapRun]bool{}
	scan := func(text string, starts []int, index []int) bool {
		reached := false
		for _, h := range find(text) {
			for k, start := range starts {
				i := index[k]
				lo, hi := max(h.start, start), min(h.end, start+len(lines[i]))
				if lo >= hi {
					continue
				}
				masked[i] = append(masked[i], hit{lo - start, hi - start})
				if hi == h.end && hi == start+len(lines[i]) && i < len(lines)-1 {
					reached = true
				}
			}
		}
		return reached
	}
	joined := func(sep string) {
		var b strings.Builder
		starts := make([]int, len(lines))
		index := make([]int, len(lines))
		for i, line := range lines {
			if i > 0 {
				b.WriteString(sep)
			}
			starts[i], index[i] = b.Len(), i
			b.WriteString(line)
		}
		scan(b.String(), starts, index)
	}
	run := func(lo, first, last int) bool {
		var b strings.Builder
		var starts, index []int
		add := func(i int) {
			starts, index = append(starts, b.Len()), append(index, i)
			b.WriteString(lines[i])
		}
		for i := lo; i < first; i++ {
			add(i)
		}
		if lo < first {
			b.WriteByte(' ')
		}
		for i := first; i <= last; i++ {
			add(i)
		}
		if last+1 < len(lines) {
			b.WriteByte(' ')
			add(last + 1)
		}
		return scan(b.String(), starts, index)
	}
	for _, sep := range []string{"", " ", "\n"} {
		joined(sep)
	}
	for first := range lines {
		los := []int{max(0, first-1)}
		if first > 0 && len(lines[first-1]) < keyBytes {
			lo, glued := first-1, len(lines[first-1])
			for lo > 0 && glued < keyBytes {
				lo--
				glued += len(lines[lo])
			}
			if lo < first-1 {
				los = append(los, lo)
			}
		}
		for _, lo := range los {
			last := first + 1
			if lo < first-1 {
				last = first
			}
			glued := 0
			for ; last < len(lines) && (last <= first+wrapLines || glued < wrapBytes); last++ {
				glued += len(lines[last])
				if run(lo, first, last) {
					continued[wrapRun{lo, first}] = true
				}
			}
		}
	}
	for r := range continued {
		run(r.lo, r.first, len(lines)-1)
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
