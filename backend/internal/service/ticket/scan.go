package ticket

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type scannedPlan struct {
	File      string
	Order     int
	Title     string
	Kickoff   string
	Unordered bool
	Warning   string
}

const kickoffSuffix = ".kickoff.md"

type scannedTicket struct {
	Slug    string
	Title   string
	Brief   string
	Plans   []scannedPlan
	Files   []string
	Warning string
}

var planPrefix = regexp.MustCompile(`^(\d{1,3})-.+\.md$`)

func planOrder(name string) (int, bool) {
	m := planPrefix.FindStringSubmatch(name)
	if m == nil {
		return 0, false
	}
	n, err := strconv.Atoi(m[1])
	if err != nil {
		return 0, false
	}
	return n, true
}

func scanTickets(root string) ([]scannedTicket, error) {
	entries, err := os.ReadDir(root)
	if errors.Is(err, os.ErrNotExist) {
		return []scannedTicket{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read tickets dir: %w", err)
	}
	out := make([]scannedTicket, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		if t, ok := scanTicket(root, e.Name()); ok {
			out = append(out, t)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Slug < out[j].Slug })
	return out, nil
}

func scanTicket(root, slug string) (scannedTicket, bool) {
	dir := filepath.Join(root, slug)
	ticketPath := filepath.Join(dir, "ticket.md")
	raw, readErr := os.ReadFile(ticketPath)
	if errors.Is(readErr, os.ErrNotExist) {
		return scannedTicket{}, false
	}
	t := scannedTicket{Slug: slug, Files: []string{"ticket.md"}}
	if readErr != nil {
		t.Title = slug
		t.Warning = "ticket.md: " + readErr.Error()
		return t, true
	}
	fm, body, err := parseFrontmatter(raw)
	if err != nil {
		t.Warning = "ticket.md: " + err.Error()
	}
	t.Title = titleOf(fm, body, slug)
	t.Brief = strings.TrimSpace(fm.Brief)
	if _, err := os.Stat(filepath.Join(dir, "spec.md")); err == nil {
		t.Files = append(t.Files, "spec.md")
	}
	plans, err := os.ReadDir(filepath.Join(dir, "plans"))
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		t.Warning = strings.TrimPrefix(t.Warning+"; plans: "+err.Error(), "; ")
		return t, true
	}
	kickoffs := map[string]bool{}
	for _, e := range plans {
		if !e.IsDir() && strings.HasSuffix(e.Name(), kickoffSuffix) {
			kickoffs[e.Name()] = true
		}
	}
	for _, e := range plans {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".md") || strings.HasSuffix(e.Name(), kickoffSuffix) {
			continue
		}
		p := scannedPlan{File: "plans/" + e.Name()}
		if kick := strings.TrimSuffix(e.Name(), ".md") + kickoffSuffix; kickoffs[kick] {
			p.Kickoff = "plans/" + kick
		}
		if n, ok := planOrder(e.Name()); ok {
			p.Order = n
		} else {
			p.Unordered = true
			p.Warning = "plan file has no numeric prefix; listed last"
		}
		raw, err := os.ReadFile(filepath.Join(dir, "plans", e.Name()))
		if err != nil {
			p.Title = strings.TrimSuffix(e.Name(), ".md")
			p.Warning = strings.TrimPrefix(p.Warning+"; "+err.Error(), "; ")
			t.Plans = append(t.Plans, p)
			continue
		}
		fm, body, err := parseFrontmatter(raw)
		if err != nil {
			if p.Warning != "" {
				p.Warning += "; " + err.Error()
			} else {
				p.Warning = err.Error()
			}
		}
		p.Title = titleOf(fm, body, strings.TrimSuffix(e.Name(), ".md"))
		t.Plans = append(t.Plans, p)
	}
	sort.SliceStable(t.Plans, func(i, j int) bool {
		a, b := t.Plans[i], t.Plans[j]
		if a.Unordered != b.Unordered {
			return !a.Unordered
		}
		if a.Order != b.Order {
			return a.Order < b.Order
		}
		return a.File < b.File
	})
	for _, p := range t.Plans {
		t.Files = append(t.Files, p.File)
		if p.Kickoff != "" {
			t.Files = append(t.Files, p.Kickoff)
		}
	}
	return t, true
}
