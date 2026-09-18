package ticket

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeFile(t testing.TB, path, content string) {
	if t != nil {
		t.Helper()
	}
	fail := func(err error) {
		if t == nil {
			panic(err)
		}
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		fail(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		fail(err)
	}
}

func TestScanTicketsMissingRoot(t *testing.T) {
	got, err := scanTickets(filepath.Join(t.TempDir(), "nope"))
	if err != nil || len(got) != 0 {
		t.Fatalf("got %+v err %v", got, err)
	}
}

func TestScanTicketsLayoutAndOrder(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "editor", "ticket.md"), "---\ntitle: Editor\nbrief: Add it\n---\nnotes\n")
	writeFile(t, filepath.Join(root, "editor", "spec.md"), "# Editor spec\n")
	writeFile(t, filepath.Join(root, "editor", "plans", "10-ui.md"), "---\ntitle: UI\n---\n")
	writeFile(t, filepath.Join(root, "editor", "plans", "02-daemon.md"), "# Daemon phase\n")
	writeFile(t, filepath.Join(root, "editor", "plans", "02-daemon.kickoff.md"), "Execute plan 02.\n")
	writeFile(t, filepath.Join(root, "editor", "plans", "notes.md"), "# Loose\n")
	writeFile(t, filepath.Join(root, "editor", "plans", "README.txt"), "ignored\n")
	writeFile(t, filepath.Join(root, "auth", "ticket.md"), "# Auth from heading\n")
	writeFile(t, filepath.Join(root, "stray.md"), "not a ticket\n")
	if err := os.MkdirAll(filepath.Join(root, "empty"), 0o755); err != nil {
		t.Fatal(err)
	}

	got, err := scanTickets(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].Slug != "auth" || got[1].Slug != "editor" {
		t.Fatalf("slugs = %+v", got)
	}
	auth := got[0]
	if auth.Title != "Auth from heading" || auth.Brief != "" || len(auth.Plans) != 0 {
		t.Fatalf("auth = %+v", auth)
	}
	ed := got[1]
	if ed.Title != "Editor" || ed.Brief != "Add it" {
		t.Fatalf("editor = %+v", ed)
	}
	wantFiles := []string{"ticket.md", "spec.md", "plans/02-daemon.md", "plans/02-daemon.kickoff.md", "plans/10-ui.md", "plans/notes.md"}
	if len(ed.Files) != len(wantFiles) {
		t.Fatalf("files = %v", ed.Files)
	}
	for i := range wantFiles {
		if ed.Files[i] != wantFiles[i] {
			t.Fatalf("files = %v want %v", ed.Files, wantFiles)
		}
	}
	if len(ed.Plans) != 3 {
		t.Fatalf("plans = %+v", ed.Plans)
	}
	if ed.Plans[0].File != "plans/02-daemon.md" || ed.Plans[0].Order != 2 || ed.Plans[0].Title != "Daemon phase" || ed.Plans[0].Kickoff != "plans/02-daemon.kickoff.md" {
		t.Fatalf("plan0 = %+v", ed.Plans[0])
	}
	if ed.Plans[1].File != "plans/10-ui.md" || ed.Plans[1].Order != 10 || ed.Plans[1].Title != "UI" || ed.Plans[1].Kickoff != "" {
		t.Fatalf("plan1 = %+v", ed.Plans[1])
	}
	if ed.Plans[2].File != "plans/notes.md" || !ed.Plans[2].Unordered || ed.Plans[2].Warning == "" || ed.Plans[2].Title != "Loose" {
		t.Fatalf("plan2 = %+v", ed.Plans[2])
	}
}

func TestScanTicketMalformedFrontmatterWarns(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "bad", "ticket.md"), "---\ntitle: [oops\n---\n")
	got, ok, err := scanTicket(root, "bad")
	if err != nil || !ok {
		t.Fatalf("ok=%v err=%v", ok, err)
	}
	if got.Warning == "" || got.Title != "bad" {
		t.Fatalf("got %+v", got)
	}
	if _, ok, err := scanTicket(root, "missing"); ok || err != nil {
		t.Fatalf("missing ok=%v err=%v", ok, err)
	}
}

func TestScanTicketCombinesUnorderedAndFrontmatterWarnings(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "editor", "ticket.md"), "---\ntitle: Editor\n---\n")
	writeFile(t, filepath.Join(root, "editor", "plans", "notes.md"), "---\ntitle: [oops\n---\n")
	got, ok, err := scanTicket(root, "editor")
	if err != nil || !ok {
		t.Fatalf("ok=%v err=%v", ok, err)
	}
	if len(got.Plans) != 1 {
		t.Fatalf("plans = %+v", got.Plans)
	}
	p := got.Plans[0]
	if !p.Unordered || !strings.Contains(p.Warning, "no numeric prefix") || !strings.Contains(p.Warning, "; ") {
		t.Fatalf("plan warning = %q", p.Warning)
	}
}
