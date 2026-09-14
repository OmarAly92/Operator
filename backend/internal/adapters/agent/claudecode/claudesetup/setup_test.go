package claudesetup

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func mkdirs(t *testing.T) (string, string) {
	t.Helper()
	root := t.TempDir()
	def := filepath.Join(root, ".claude")
	acct := filepath.Join(root, ".claude-personal")
	for _, dir := range []string{def, acct, filepath.Join(def, "skills"), filepath.Join(def, "plugins")} {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			t.Fatal(err)
		}
	}
	for _, f := range []string{"CLAUDE.md", "settings.json"} {
		if err := os.WriteFile(filepath.Join(def, f), []byte("{}"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return def, acct
}

func TestEnsureStates(t *testing.T) {
	def, acct := mkdirs(t)
	if err := os.WriteFile(filepath.Join(acct, "settings.json"), []byte(`{"theme":"dark"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(t.TempDir(), "elsewhere"), filepath.Join(acct, "plugins")); err != nil {
		t.Fatal(err)
	}

	report, err := Ensure(def, acct)
	if err != nil {
		t.Fatal(err)
	}
	want := Report{
		"CLAUDE.md":     ItemLinked,
		"settings.json": ItemReplaced,
		"skills":        ItemLinked,
		"commands":      ItemSkipped,
		"agents":        ItemSkipped,
		"plugins":       ItemLinked,
	}
	for name, state := range want {
		if report[name] != state {
			t.Errorf("%s = %q, want %q", name, report[name], state)
		}
	}
	for _, name := range []string{"CLAUDE.md", "skills", "plugins"} {
		target, err := os.Readlink(filepath.Join(acct, name))
		if err != nil || target != filepath.Join(def, name) {
			t.Errorf("%s link = %q err=%v", name, target, err)
		}
	}
	data, _ := os.ReadFile(filepath.Join(acct, "settings.json"))
	if string(data) != `{"theme":"dark"}` {
		t.Errorf("real settings.json was modified: %s", data)
	}

	again, err := Ensure(def, acct)
	if err != nil || again["CLAUDE.md"] != ItemLinked {
		t.Fatalf("second ensure = %v err=%v", again, err)
	}
}

func TestInspectDoesNotCreate(t *testing.T) {
	def, acct := mkdirs(t)
	report, err := Inspect(def, acct)
	if err != nil {
		t.Fatal(err)
	}
	if report["CLAUDE.md"] != ItemMissing {
		t.Fatalf("CLAUDE.md = %q, want missing", report["CLAUDE.md"])
	}
	if _, err := os.Lstat(filepath.Join(acct, "CLAUDE.md")); !os.IsNotExist(err) {
		t.Fatalf("inspect created a link: %v", err)
	}
}

func TestRelinkBacksUpRealFiles(t *testing.T) {
	def, acct := mkdirs(t)
	real := filepath.Join(acct, "settings.json")
	if err := os.WriteFile(real, []byte(`{"theme":"dark"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1789400000, 0)
	report, err := Relink(def, acct, now)
	if err != nil {
		t.Fatal(err)
	}
	if report["settings.json"] != ItemLinked {
		t.Fatalf("settings.json = %q", report["settings.json"])
	}
	backup, err := os.ReadFile(real + ".bak-1789400000")
	if err != nil || string(backup) != `{"theme":"dark"}` {
		t.Fatalf("backup = %s err=%v", backup, err)
	}
	if replaced := report.Replaced(); len(replaced) != 0 {
		t.Fatalf("replaced after relink = %v", replaced)
	}
}
