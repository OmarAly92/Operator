package ticket

import "testing"

func TestParseFrontmatter(t *testing.T) {
	fm, body, err := parseFrontmatter([]byte("---\ntitle: Editor\nbrief: Add an editor\ncreated: 2026-09-18\n---\n# Editor\n\nBody\n"))
	if err != nil {
		t.Fatal(err)
	}
	if fm.Title != "Editor" || fm.Brief != "Add an editor" || fm.Created != "2026-09-18" {
		t.Fatalf("fm = %+v", fm)
	}
	if body != "# Editor\n\nBody\n" {
		t.Fatalf("body = %q", body)
	}
}

func TestParseFrontmatterAbsent(t *testing.T) {
	fm, body, err := parseFrontmatter([]byte("# Just a heading\n"))
	if err != nil || fm.Title != "" || body != "# Just a heading\n" {
		t.Fatalf("fm=%+v body=%q err=%v", fm, body, err)
	}
}

func TestParseFrontmatterMalformed(t *testing.T) {
	if _, _, err := parseFrontmatter([]byte("---\ntitle: [oops\n---\n")); err == nil {
		t.Fatal("want yaml error")
	}
	if _, _, err := parseFrontmatter([]byte("---\ntitle: x\n")); err == nil {
		t.Fatal("want unterminated error")
	}
}

func TestTitleOf(t *testing.T) {
	if got := titleOf(frontmatter{Title: "From FM"}, "# Heading\n", "file"); got != "From FM" {
		t.Fatal(got)
	}
	if got := titleOf(frontmatter{}, "intro\n\n#   Heading here  \n", "file"); got != "Heading here" {
		t.Fatal(got)
	}
	if got := titleOf(frontmatter{}, "no heading", "01-core"); got != "01-core" {
		t.Fatal(got)
	}
}
