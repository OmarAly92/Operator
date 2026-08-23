package store_test

import (
	"context"
	"database/sql"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/sqlitetest"
	sqlitestore "github.com/OmarAly92/operator/backend/internal/storage/sqlite/store"
)

func TestAppSettingsMigrationSeedsDesktopDefaults(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()

	row, err := s.GetAppSettings(ctx)
	if err != nil {
		t.Fatalf("read app settings: %v", err)
	}
	if row.DefaultSessionMode != domain.SessionModeTUI {
		t.Errorf("mode = %q, want tui", row.DefaultSessionMode)
	}
	if row.UILocale != "en" {
		t.Errorf("locale = %q, want en", row.UILocale)
	}
	if row.UpdateOptIn || row.UpdateNightlyAck {
		t.Errorf("opt-in = %v ack = %v, want both false", row.UpdateOptIn, row.UpdateNightlyAck)
	}
	if row.UpdateChannel != "latest" {
		t.Errorf("channel = %q, want latest", row.UpdateChannel)
	}
	if row.UpdateFeaturePR != nil {
		t.Errorf("feature pr = %v, want nil", row.UpdateFeaturePR)
	}
	if row.KeybindingsJSON != "{}" {
		t.Errorf("keybindings json = %q, want {}", row.KeybindingsJSON)
	}
	if row.MigrationJSON != "{}" {
		t.Errorf("migration json = %q, want {}", row.MigrationJSON)
	}
	if row.LegacyDesktopImportedAt != nil {
		t.Errorf("legacy imported at = %v, want nil", row.LegacyDesktopImportedAt)
	}
	if row.UpdatedAt.IsZero() {
		t.Error("updated_at zero after migration seed")
	}
}

func TestAppSettingsFacetWritesPreserveUnrelatedColumns(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	now := time.Date(2026, 8, 21, 12, 0, 0, 0, time.UTC)

	if err := s.SetDefaultSessionMode(ctx, domain.SessionModeChat, now); err != nil {
		t.Fatalf("set session mode: %v", err)
	}
	if err := s.SetAppUILocale(ctx, "ko", now); err != nil {
		t.Fatalf("set ui locale: %v", err)
	}
	featurePR := int64(12)
	if err := s.SetAppUpdateSettings(ctx, true, "nightly", true, &featurePR, now); err != nil {
		t.Fatalf("set update settings: %v", err)
	}
	if err := s.SetAppKeybindings(ctx, `{"next-tab":[{"key":"Tab","ctrl":true}]}`, now); err != nil {
		t.Fatalf("set keybindings: %v", err)
	}
	if err := s.SetAppMigrationState(ctx, `{"status":"declined","lastAttemptAt":"2026-08-21T10:00:00Z"}`, now); err != nil {
		t.Fatalf("set migration state: %v", err)
	}

	row, err := s.GetAppSettings(ctx)
	if err != nil {
		t.Fatalf("read app settings: %v", err)
	}
	if row.DefaultSessionMode != domain.SessionModeChat {
		t.Errorf("mode = %q, want chat preserved", row.DefaultSessionMode)
	}
	if row.UILocale != "ko" {
		t.Errorf("locale = %q, want ko preserved", row.UILocale)
	}
	if !row.UpdateOptIn || !row.UpdateNightlyAck || row.UpdateChannel != "nightly" {
		t.Errorf("updates = opt-in %v channel %q ack %v, want preserved", row.UpdateOptIn, row.UpdateChannel, row.UpdateNightlyAck)
	}
	if row.UpdateFeaturePR == nil || *row.UpdateFeaturePR != 12 {
		t.Errorf("feature pr = %v, want 12", row.UpdateFeaturePR)
	}
	if row.KeybindingsJSON != `{"next-tab":[{"key":"Tab","ctrl":true}]}` {
		t.Errorf("keybindings = %q, want preserved", row.KeybindingsJSON)
	}
	if row.MigrationJSON == "" {
		t.Error("migration state lost")
	}
}

func TestAppSettingsLaterFacetWriteKeepsEarlierFacets(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	now := time.Date(2026, 8, 21, 12, 0, 0, 0, time.UTC)

	if err := s.SetAppUILocale(ctx, "pt-BR", now); err != nil {
		t.Fatalf("set ui locale: %v", err)
	}
	pr := int64(3)
	if err := s.SetAppUpdateSettings(ctx, false, "latest", false, &pr, now); err != nil {
		t.Fatalf("set update settings: %v", err)
	}
	if err := s.SetAppMigrationState(ctx, `{"status":"completed"}`, now); err != nil {
		t.Fatalf("set migration state: %v", err)
	}

	row, err := s.GetAppSettings(ctx)
	if err != nil {
		t.Fatalf("read app settings: %v", err)
	}
	if row.UILocale != "pt-BR" {
		t.Errorf("locale = %q, want pt-BR untouched by update/migration writes", row.UILocale)
	}
	if row.UpdateFeaturePR == nil || *row.UpdateFeaturePR != 3 {
		t.Errorf("feature pr = %v, want 3 untouched by migration write", row.UpdateFeaturePR)
	}
}

func TestAppSettingsConcurrentFacetWritesAllLand(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	now := time.Date(2026, 8, 21, 12, 0, 0, 0, time.UTC)

	var wg sync.WaitGroup
	wg.Add(4)
	go func() {
		defer wg.Done()
		if err := s.SetAppUILocale(ctx, "es", now); err != nil {
			t.Errorf("set ui locale: %v", err)
		}
	}()
	go func() {
		defer wg.Done()
		if err := s.SetAppUpdateSettings(ctx, true, "latest", false, nil, now); err != nil {
			t.Errorf("set update settings: %v", err)
		}
	}()
	go func() {
		defer wg.Done()
		if err := s.SetAppKeybindings(ctx, `{"focus-terminal":[{"key":"t","ctrl":true,"meta":true,"shift":true,"alt":false}]}`, now); err != nil {
			t.Errorf("set keybindings: %v", err)
		}
	}()
	go func() {
		defer wg.Done()
		if err := s.SetAppMigrationState(ctx, `{"status":"pending"}`, now); err != nil {
			t.Errorf("set migration state: %v", err)
		}
	}()
	wg.Wait()

	row, err := s.GetAppSettings(ctx)
	if err != nil {
		t.Fatalf("read app settings: %v", err)
	}
	if row.UILocale != "es" {
		t.Errorf("locale = %q, want es", row.UILocale)
	}
	if !row.UpdateOptIn {
		t.Errorf("opt-in = %v, want true", row.UpdateOptIn)
	}
	if row.KeybindingsJSON == "{}" {
		t.Error("keybindings write lost")
	}
	if row.MigrationJSON == "{}" {
		t.Error("migration write lost")
	}
}

func TestAppSettingsMutationsEmitNoChangeLogRows(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	now := time.Date(2026, 8, 21, 12, 0, 0, 0, time.UTC)
	pr := int64(9)

	mutate := []func() error{
		func() error { return s.SetDefaultSessionMode(ctx, domain.SessionModeChat, now) },
		func() error { return s.SetAppUILocale(ctx, "zh-CN", now) },
		func() error { return s.SetAppUpdateSettings(ctx, true, "nightly", true, &pr, now) },
		func() error { return s.SetAppKeybindings(ctx, `{"new-session":[]}`, now) },
		func() error { return s.SetAppMigrationState(ctx, `{"status":"failed","error":"boom"}`, now) },
		func() error { return s.MarkAppLegacyDesktopImported(ctx, now) },
	}
	for i, m := range mutate {
		if err := m(); err != nil {
			t.Fatalf("mutation %d: %v", i, err)
		}
		seq, err := s.LatestSeq(ctx)
		if err != nil {
			t.Fatalf("read change log head: %v", err)
		}
		if seq != 0 {
			t.Fatalf("mutation %d produced change_log rows (head = %d)", i, seq)
		}
	}
}

func TestMarkAppLegacyDesktopImportedIsWriteOnce(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	first := time.Date(2026, 8, 20, 8, 0, 0, 0, time.UTC)
	second := first.Add(time.Hour)

	if err := s.MarkAppLegacyDesktopImported(ctx, first); err != nil {
		t.Fatalf("mark imported: %v", err)
	}
	if err := s.MarkAppLegacyDesktopImported(ctx, second); err != nil {
		t.Fatalf("re-mark imported: %v", err)
	}

	row, err := s.GetAppSettings(ctx)
	if err != nil {
		t.Fatalf("read app settings: %v", err)
	}
	if row.LegacyDesktopImportedAt == nil || !row.LegacyDesktopImportedAt.Equal(first) {
		t.Errorf("marker = %v, want the first stamp %v kept forever", row.LegacyDesktopImportedAt, first)
	}
}

func TestImportLegacyDesktopSettingsRollsBackEveryWriteBoundary(t *testing.T) {
	tests := []struct {
		name   string
		column string
	}{
		{name: "marker", column: "legacy_desktop_imported_at"},
		{name: "locale", column: "ui_locale"},
		{name: "updates", column: "update_opt_in"},
		{name: "keybindings", column: "keybindings_json"},
		{name: "migration", column: "migration_json"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dataDir := t.TempDir()
			s := sqlitetest.MustOpenAt(t, dataDir)
			before, err := s.GetAppSettings(context.Background())
			if err != nil {
				t.Fatalf("read initial app settings: %v", err)
			}
			db, err := sql.Open("sqlite", "file:"+filepath.Join(dataDir, "opr.db"))
			if err != nil {
				t.Fatalf("open trigger connection: %v", err)
			}
			t.Cleanup(func() { _ = db.Close() })
			if _, err := db.Exec(`CREATE TRIGGER fail_import_write
BEFORE UPDATE OF ` + tt.column + ` ON app_settings
BEGIN
  SELECT RAISE(ABORT, 'injected import failure');
END`); err != nil {
				t.Fatalf("create failure trigger: %v", err)
			}

			locale := "ja"
			featurePR := int64(42)
			keybindings := `{"new-session":[{"key":"n","ctrl":true}]}`
			migration := `{"status":"completed"}`
			now := time.Date(2026, 8, 22, 12, 0, 0, 0, time.UTC)
			err = s.ImportLegacyDesktopSettings(context.Background(), sqlitestore.LegacyDesktopSettingsImport{
				UILocale: &locale,
				Updates: &sqlitestore.LegacyDesktopUpdateSettings{
					OptIn:      true,
					Channel:    "nightly",
					NightlyAck: true,
					FeaturePR:  &featurePR,
				},
				KeybindingsJSON: &keybindings,
				MigrationJSON:   &migration,
			}, now)
			if err == nil {
				t.Fatal("import error = nil, want injected failure")
			}

			row, err := s.GetAppSettings(context.Background())
			if err != nil {
				t.Fatalf("read app settings: %v", err)
			}
			if !reflect.DeepEqual(row, before) {
				t.Fatalf("partially committed import after %s failure: before=%+v after=%+v", tt.name, before, row)
			}
		})
	}
}

func TestImportLegacyDesktopSettingsConcurrentStoresCommitOneCompleteImport(t *testing.T) {
	dataDir := t.TempDir()
	firstStore := sqlitetest.MustOpenAt(t, dataDir)
	secondStore, err := sqlite.Open(dataDir)
	if err != nil {
		t.Fatalf("open second store: %v", err)
	}
	t.Cleanup(func() { _ = secondStore.Close() })

	firstLocale, secondLocale := "ja", "fr"
	firstKeys, secondKeys := `{"new-session":[]}`, `{"toggle-sidebar":[]}`
	firstMigration, secondMigration := `{"status":"completed"}`, `{"status":"declined"}`
	firstAt := time.Date(2026, 8, 22, 12, 0, 0, 0, time.UTC)
	secondAt := firstAt.Add(time.Second)
	imports := []struct {
		store     *sqlite.Store
		locale    *string
		keys      *string
		migration *string
		at        time.Time
	}{
		{store: firstStore, locale: &firstLocale, keys: &firstKeys, migration: &firstMigration, at: firstAt},
		{store: secondStore, locale: &secondLocale, keys: &secondKeys, migration: &secondMigration, at: secondAt},
	}

	start := make(chan struct{})
	errs := make(chan error, len(imports))
	var wg sync.WaitGroup
	for _, candidate := range imports {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			errs <- candidate.store.ImportLegacyDesktopSettings(context.Background(), sqlitestore.LegacyDesktopSettingsImport{
				UILocale:        candidate.locale,
				KeybindingsJSON: candidate.keys,
				MigrationJSON:   candidate.migration,
			}, candidate.at)
		}()
	}
	close(start)
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatalf("concurrent import: %v", err)
		}
	}

	row, err := firstStore.GetAppSettings(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if row.LegacyDesktopImportedAt == nil {
		t.Fatal("legacy import marker is nil")
	}
	if row.LegacyDesktopImportedAt.Equal(firstAt) {
		if row.UILocale != firstLocale || row.KeybindingsJSON != firstKeys || row.MigrationJSON != firstMigration {
			t.Fatalf("first import was mixed with second: %+v", row)
		}
		return
	}
	if row.LegacyDesktopImportedAt.Equal(secondAt) {
		if row.UILocale != secondLocale || row.KeybindingsJSON != secondKeys || row.MigrationJSON != secondMigration {
			t.Fatalf("second import was mixed with first: %+v", row)
		}
		return
	}
	t.Fatalf("unexpected import marker: %v", row.LegacyDesktopImportedAt)
}
