package settings

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func writeLegacyFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		t.Fatalf("mkdir for %s: %v", path, err)
	}
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func legacyFiles(dir string) LegacyFiles {
	return LegacyFiles{
		UiSettings:     filepath.Join(dir, "ui-settings.json"),
		UpdateSettings: filepath.Join(dir, "update-settings.json"),
		Keybindings:    filepath.Join(dir, "keybindings.json"),
		AppState:       filepath.Join(dir, "app-state.json"),
	}
}

func TestLegacyFilesUnderNamesDesktopFiles(t *testing.T) {
	files := LegacyFilesUnder("/state")
	want := []string{"ui-settings.json", "update-settings.json", "keybindings.json", "app-state.json"}
	got := []string{files.UiSettings, files.UpdateSettings, files.Keybindings, files.AppState}
	for i, name := range want {
		if got[i] != filepath.Join("/state", name) {
			t.Errorf("file %d = %q, want %q", i, got[i], filepath.Join("/state", name))
		}
	}
}

func TestImportLegacyDesktopImportsAllFacets(t *testing.T) {
	dir := t.TempDir()
	writeLegacyFile(t, filepath.Join(dir, "ui-settings.json"), `{"locale":"ja"}`)
	writeLegacyFile(t, filepath.Join(dir, "update-settings.json"),
		`{"enabled":true,"channel":"nightly","nightlyAck":true,"feature":{"pr":42}}`)
	writeLegacyFile(t, filepath.Join(dir, "keybindings.json"),
		`{"toggle-sidebar":[{"key":"b","code":"","ctrl":true,"meta":false,"shift":false,"alt":false}]}`)
	writeLegacyFile(t, filepath.Join(dir, "app-state.json"),
		`{"schemaVersion":2,"appPath":"/app","version":"1.2.3","installedAt":"2026-01-01T00:00:00Z",`+
			`"lastReconciledAt":"2026-08-01T00:00:00Z","installSource":"dmg",`+
			`"migration":{"status":"completed","completedAt":"2026-08-01T00:00:00Z",`+
			`"report":{"projectsImported":3,"projectsSkipped":1}}}`)

	store := &fakeStore{}
	svc := newTestService(store)
	if err := svc.ImportLegacyDesktop(context.Background(), legacyFiles(dir)); err != nil {
		t.Fatalf("import: %v", err)
	}

	if store.rec.UILocale != "ja" {
		t.Errorf("locale = %q, want ja", store.rec.UILocale)
	}
	if !store.rec.UpdateOptIn || store.rec.UpdateChannel != "nightly" || !store.rec.UpdateNightlyAck {
		t.Errorf("updates = %+v, want enabled nightly with ack", store.rec)
	}
	if store.rec.UpdateFeaturePR == nil || *store.rec.UpdateFeaturePR != 42 {
		t.Errorf("feature pr = %v, want 42", store.rec.UpdateFeaturePR)
	}
	if !strings.Contains(store.rec.KeybindingsJSON, "toggle-sidebar") {
		t.Errorf("keybindings = %q, want the toggle-sidebar override", store.rec.KeybindingsJSON)
	}
	if !strings.Contains(store.rec.MigrationJSON, `"completed"`) || !strings.Contains(store.rec.MigrationJSON, "projectsImported") {
		t.Errorf("migration = %q, want the completed report", store.rec.MigrationJSON)
	}
	if store.rec.LegacyDesktopImportedAt == nil {
		t.Error("marker not stamped after a successful import")
	}
}

func TestImportLegacyDesktopToleratesMissingAndCorruptFiles(t *testing.T) {
	cases := map[string]func(t *testing.T, dir string){
		"missing directory": func(t *testing.T, dir string) {},
		"empty files": func(t *testing.T, dir string) {
			for _, name := range []string{"ui-settings.json", "update-settings.json", "keybindings.json", "app-state.json"} {
				writeLegacyFile(t, filepath.Join(dir, name), "")
			}
		},
		"corrupt json": func(t *testing.T, dir string) {
			writeLegacyFile(t, filepath.Join(dir, "ui-settings.json"), `{`)
			writeLegacyFile(t, filepath.Join(dir, "update-settings.json"), "not json")
			writeLegacyFile(t, filepath.Join(dir, "keybindings.json"), `{"toggle-sidebar":`)
			writeLegacyFile(t, filepath.Join(dir, "app-state.json"), `[]`)
		},
	}
	for name, seed := range cases {
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			seed(t, dir)
			store := &fakeStore{}
			svc := newTestService(store)

			if err := svc.ImportLegacyDesktop(context.Background(), legacyFiles(dir)); err != nil {
				t.Fatalf("import: %v", err)
			}
			if store.rec.UILocale != "" || store.rec.UpdateOptIn || store.rec.UpdateChannel != "" ||
				store.rec.UpdateNightlyAck || store.rec.UpdateFeaturePR != nil ||
				store.rec.KeybindingsJSON != "" || store.rec.MigrationJSON != "" {
				t.Errorf("facets written for unusable files: %+v", store.rec)
			}
			if store.rec.LegacyDesktopImportedAt == nil {
				t.Error("marker not stamped: the import pass must complete even with nothing to read")
			}
		})
	}
}

func TestImportLegacyDesktopCoercesValuesLikeTheDesktop(t *testing.T) {
	dir := t.TempDir()
	writeLegacyFile(t, filepath.Join(dir, "ui-settings.json"), `{"locale":"xx-YY"}`)
	writeLegacyFile(t, filepath.Join(dir, "update-settings.json"),
		`{"enabled":"yes","channel":"beta","nightlyAck":1,"feature":{"pr":-2}}`)
	writeLegacyFile(t, filepath.Join(dir, "keybindings.json"),
		`{"close-shell-terminal":[{"key":"c","ctrl":true}],"toggle-sidebar":[{"key":"b","ctrl":true}],"focus-terminal":"nope","open-project":[{"key":"5","meta":true}]}`)

	store := &fakeStore{}
	svc := newTestService(store)
	if err := svc.ImportLegacyDesktop(context.Background(), legacyFiles(dir)); err != nil {
		t.Fatalf("import: %v", err)
	}

	if store.rec.UILocale != DefaultUILocale {
		t.Errorf("locale = %q, want fallback %q", store.rec.UILocale, DefaultUILocale)
	}
	if store.rec.UpdateOptIn || store.rec.UpdateChannel != string(UpdateChannelLatest) || store.rec.UpdateNightlyAck {
		t.Errorf("updates = %+v, want strict-coercion defaults", store.rec)
	}
	if store.rec.UpdateFeaturePR != nil {
		t.Errorf("feature pr = %v, want the negative pin dropped", store.rec.UpdateFeaturePR)
	}
	if strings.Contains(store.rec.KeybindingsJSON, "close-shell-terminal") {
		t.Errorf("keybindings = %q, want the terminal-reserved ctrl+C dropped", store.rec.KeybindingsJSON)
	}
	if !strings.Contains(store.rec.KeybindingsJSON, "toggle-sidebar") {
		t.Errorf("keybindings = %q, want the valid ctrl+B override kept", store.rec.KeybindingsJSON)
	}
	if strings.Contains(store.rec.KeybindingsJSON, "open-project") {
		t.Errorf("keybindings = %q, want the non-customizable id ignored", store.rec.KeybindingsJSON)
	}
}

func TestImportLegacyDesktopSkipsStaleFilesAfterImport(t *testing.T) {
	dir := t.TempDir()
	writeLegacyFile(t, filepath.Join(dir, "ui-settings.json"), `{"locale":"ja"}`)
	writeLegacyFile(t, filepath.Join(dir, "update-settings.json"), `{"enabled":true}`)

	store := &fakeStore{}
	svc := newTestService(store)
	stamp := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	if err := svc.MarkLegacyDesktopImported(context.Background(), stamp); err != nil {
		t.Fatalf("pre-stamp: %v", err)
	}
	before := store.rec

	if err := svc.ImportLegacyDesktop(context.Background(), legacyFiles(dir)); err != nil {
		t.Fatalf("import: %v", err)
	}
	if store.rec.UILocale != before.UILocale || store.rec.UpdateOptIn != before.UpdateOptIn ||
		store.rec.UpdatedAt != before.UpdatedAt {
		t.Errorf("stale files overwrote imported state: %+v -> %+v", before, store.rec)
	}
	if !store.rec.LegacyDesktopImportedAt.Equal(stamp) {
		t.Errorf("marker moved to %v, want %v", store.rec.LegacyDesktopImportedAt, stamp)
	}
}

type markFailingStore struct{ *fakeStore }

func (f *markFailingStore) MarkLegacyDesktopImported(context.Context, time.Time) error {
	return errors.New("marker write failed")
}

func TestImportLegacyDesktopMarkerFailureLeavesRetryWindowOpen(t *testing.T) {
	dir := t.TempDir()
	writeLegacyFile(t, filepath.Join(dir, "ui-settings.json"), `{"locale":"ja"}`)

	store := &markFailingStore{&fakeStore{}}
	svc := New(store, nil, func() time.Time {
		return time.Date(2026, 8, 21, 12, 0, 0, 0, time.UTC)
	})
	if err := svc.ImportLegacyDesktop(context.Background(), legacyFiles(dir)); err == nil {
		t.Fatal("marker failure swallowed: a later crash would never re-attempt the import")
	}
	if store.rec.LegacyDesktopImportedAt != nil {
		t.Error("marker recorded despite the failed write")
	}
}

type facetFailingStore struct{ *fakeStore }

func (f *facetFailingStore) SetUILocale(context.Context, string, time.Time) error {
	return errors.New("locale write failed")
}

func TestImportLegacyDesktopFailedFacetDoesNotStampMarker(t *testing.T) {
	dir := t.TempDir()
	writeLegacyFile(t, filepath.Join(dir, "ui-settings.json"), `{"locale":"ja"}`)

	store := &facetFailingStore{&fakeStore{}}
	svc := New(store, nil, func() time.Time {
		return time.Date(2026, 8, 21, 12, 0, 0, 0, time.UTC)
	})
	if err := svc.ImportLegacyDesktop(context.Background(), legacyFiles(dir)); err == nil {
		t.Fatal("facet failure swallowed: the import must not be marked complete")
	}
	if store.rec.LegacyDesktopImportedAt != nil {
		t.Error("marker stamped despite a failed facet write")
	}
}

func TestImportLegacyDesktopImportsUpdateFacetAtomically(t *testing.T) {
	dir := t.TempDir()
	writeLegacyFile(t, filepath.Join(dir, "update-settings.json"),
		`{"enabled":true,"channel":"latest","nightlyAck":true,"feature":{"pr":7}}`)

	store := &fakeStore{}
	svc := newTestService(store)
	if err := svc.ImportLegacyDesktop(context.Background(), legacyFiles(dir)); err != nil {
		t.Fatalf("import: %v", err)
	}
	if !store.rec.UpdateOptIn || !store.rec.UpdateNightlyAck || store.rec.UpdateFeaturePR == nil || *store.rec.UpdateFeaturePR != 7 {
		t.Errorf("updates = %+v, want every field of the file landing together", store.rec)
	}
}
