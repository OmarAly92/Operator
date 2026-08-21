package settings

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
)

type fakeStore struct {
	mu  sync.Mutex
	rec Record
	err error
}

func (f *fakeStore) GetAppSettings(context.Context) (Record, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.rec, f.err
}

func (f *fakeStore) SetDefaultSessionMode(_ context.Context, mode domain.SessionMode, now time.Time) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	f.rec.DefaultSessionMode = mode
	f.rec.UpdatedAt = now
	return nil
}

func (f *fakeStore) SetUILocale(_ context.Context, locale string, now time.Time) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	f.rec.UILocale = locale
	f.rec.UpdatedAt = now
	return nil
}

func (f *fakeStore) SetUpdateSettings(_ context.Context, prefs UpdateSettings, now time.Time) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	f.rec.UpdateOptIn = prefs.Enabled
	f.rec.UpdateChannel = string(prefs.Channel)
	f.rec.UpdateNightlyAck = prefs.NightlyAck
	if prefs.Feature != nil {
		pr := prefs.Feature.PR
		f.rec.UpdateFeaturePR = &pr
	} else {
		f.rec.UpdateFeaturePR = nil
	}
	f.rec.UpdatedAt = now
	return nil
}

func (f *fakeStore) SetKeybindings(_ context.Context, overrides KeybindingOverrides, now time.Time) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	raw, err := json.Marshal(overrides)
	if err != nil {
		return err
	}
	f.rec.KeybindingsJSON = string(raw)
	f.rec.UpdatedAt = now
	return nil
}

func (f *fakeStore) SetMigrationState(_ context.Context, state MigrationState, now time.Time) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	raw, err := json.Marshal(state)
	if err != nil {
		return err
	}
	f.rec.MigrationJSON = string(raw)
	f.rec.UpdatedAt = now
	return nil
}

func (f *fakeStore) MarkLegacyDesktopImported(_ context.Context, importedAt time.Time) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	stamp := importedAt
	f.rec.LegacyDesktopImportedAt = &stamp
	f.rec.UpdatedAt = importedAt
	return nil
}

func newTestService(store *fakeStore) *Service {
	return New(store, nil, func() time.Time {
		return time.Date(2026, 8, 21, 12, 0, 0, 0, time.UTC)
	})
}

func TestGetNormalizesPersistedDesktopPreferences(t *testing.T) {
	store := &fakeStore{rec: Record{
		DefaultSessionMode: domain.SessionModeTUI,
		UpdatedAt:          time.Date(2026, 8, 1, 9, 0, 0, 0, time.UTC),
		UILocale:           "xx-YY",
		UpdateOptIn:        true,
		UpdateChannel:      "weekly",
		UpdateNightlyAck:   true,
		UpdateFeaturePR:    nil,
		KeybindingsJSON:    `{"new-session":not-json`,
		MigrationJSON:      `{`,
	}}
	svc := newTestService(store)

	snapshot, err := svc.Get(context.Background())
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if snapshot.UILocale != DefaultUILocale {
		t.Errorf("locale = %q, want fallback %q", snapshot.UILocale, DefaultUILocale)
	}
	if !snapshot.Updates.Enabled || !snapshot.Updates.NightlyAck {
		t.Errorf("updates = %+v, want strict booleans preserved", snapshot.Updates)
	}
	if snapshot.Updates.Channel != UpdateChannelLatest {
		t.Errorf("channel = %q, want fallback %q", snapshot.Updates.Channel, UpdateChannelLatest)
	}
	if snapshot.Updates.Feature != nil {
		t.Errorf("feature = %+v, want nil", snapshot.Updates.Feature)
	}
	if len(snapshot.Keybindings) != 0 {
		t.Errorf("keybindings = %v, want empty overrides for corrupt JSON", snapshot.Keybindings)
	}
	if snapshot.Migration.Status != MigrationPending {
		t.Errorf("migration status = %q, want %q for corrupt JSON", snapshot.Migration.Status, MigrationPending)
	}
}

func TestSetDefaultSessionModePersistsAndReturnsSnapshot(t *testing.T) {
	store := &fakeStore{}
	svc := newTestService(store)

	snapshot, err := svc.SetDefaultSessionMode(context.Background(), domain.SessionModeChat)
	if err != nil {
		t.Fatalf("set default session mode: %v", err)
	}
	if snapshot.DefaultSessionMode != domain.SessionModeChat {
		t.Errorf("mode = %q, want chat", snapshot.DefaultSessionMode)
	}
	if _, err := svc.SetDefaultSessionMode(context.Background(), "voice"); err == nil {
		t.Fatal("expected invalid mode to be rejected")
	}
}

func TestDefaultSessionModeFallsBackWhenStoreFails(t *testing.T) {
	store := &fakeStore{err: errors.New("disk on fire")}
	svc := newTestService(store)

	if got := svc.DefaultSessionMode(context.Background()); got != domain.DefaultSessionMode {
		t.Errorf("mode = %q, want compatibility default %q", got, domain.DefaultSessionMode)
	}
}

func TestSetUILocaleCoercesUnknownToEnglish(t *testing.T) {
	store := &fakeStore{}
	svc := newTestService(store)
	ctx := context.Background()

	snapshot, err := svc.SetUILocale(ctx, "ja")
	if err != nil {
		t.Fatalf("set ja: %v", err)
	}
	if snapshot.UILocale != "ja" {
		t.Errorf("locale = %q, want ja", snapshot.UILocale)
	}

	snapshot, err = svc.SetUILocale(ctx, "qq-XX")
	if err != nil {
		t.Fatalf("set qq-XX: %v", err)
	}
	if snapshot.UILocale != DefaultUILocale {
		t.Errorf("locale = %q, want fallback %q", snapshot.UILocale, DefaultUILocale)
	}
}

func TestSetUpdateSettingsCoercesChannelAndFeaturePin(t *testing.T) {
	store := &fakeStore{}
	svc := newTestService(store)
	ctx := context.Background()

	snapshot, err := svc.SetUpdateSettings(ctx, UpdateSettings{
		Enabled:    true,
		Channel:    UpdateChannelNightly,
		NightlyAck: true,
		Feature:    &FeaturePin{PR: 42},
	})
	if err != nil {
		t.Fatalf("set nightly: %v", err)
	}
	if snapshot.Updates.Channel != UpdateChannelNightly {
		t.Errorf("channel = %q, want nightly", snapshot.Updates.Channel)
	}
	if snapshot.Updates.Feature == nil || snapshot.Updates.Feature.PR != 42 {
		t.Errorf("feature = %+v, want pr 42", snapshot.Updates.Feature)
	}

	snapshot, err = svc.SetUpdateSettings(ctx, UpdateSettings{
		Channel: "beta",
		Feature: &FeaturePin{PR: -3},
	})
	if err != nil {
		t.Fatalf("set beta: %v", err)
	}
	if snapshot.Updates.Channel != UpdateChannelLatest {
		t.Errorf("channel = %q, want fallback latest", snapshot.Updates.Channel)
	}
	if snapshot.Updates.Feature != nil {
		t.Errorf("feature = %+v, want non-positive pr dropped", snapshot.Updates.Feature)
	}
	if snapshot.Updates.Enabled || snapshot.Updates.NightlyAck {
		t.Errorf("updates = %+v, want strict booleans replaced by the payload", snapshot.Updates)
	}
}

func binding(key string, mods string) ShortcutBinding {
	return ShortcutBinding{
		Key:   key,
		Ctrl:  strings.Contains(mods, "c"),
		Meta:  strings.Contains(mods, "m"),
		Shift: strings.Contains(mods, "s"),
		Alt:   strings.Contains(mods, "a"),
	}
}

func TestCoerceKeybindingOverridesPlatformReservedBindings(t *testing.T) {
	raw := KeybindingOverrides{
		"new-session":          {binding("w", "m")},
		"close-shell-terminal": {binding("c", "c")},
		"toggle-sidebar":       {binding("s", "c")},
		"focus-terminal":       {binding("s", "cs")},
		"keyboard-shortcuts":   {binding("f4", "a")},
	}
	mac := CoerceKeybindingOverrides(raw, true)
	if len(mac["new-session"]) != 0 {
		t.Errorf("mac meta+W kept: %v", mac["new-session"])
	}
	if len(mac["close-shell-terminal"]) != 0 {
		t.Errorf("ctrl+C kept: %v", mac["close-shell-terminal"])
	}
	if len(mac["toggle-sidebar"]) != 0 {
		t.Errorf("unshifted ctrl+S kept: %v", mac["toggle-sidebar"])
	}
	if len(mac["focus-terminal"]) != 1 {
		t.Errorf("ctrl+shift+S dropped: %v", mac["focus-terminal"])
	}
	if len(mac["keyboard-shortcuts"]) != 1 {
		t.Errorf("mac alt+F4 dropped: %v", mac["keyboard-shortcuts"])
	}

	other := CoerceKeybindingOverrides(raw, false)
	if len(other["new-session"]) != 1 {
		t.Errorf("non-mac meta+W dropped: %v", other["new-session"])
	}
	if len(other["close-shell-terminal"]) != 0 {
		t.Errorf("non-mac ctrl+C kept: %v", other["close-shell-terminal"])
	}
	if len(other["toggle-sidebar"]) != 0 {
		t.Errorf("non-mac unshifted ctrl+S kept: %v", other["toggle-sidebar"])
	}
	if len(other["keyboard-shortcuts"]) != 0 {
		t.Errorf("non-mac alt+F4 kept: %v", other["keyboard-shortcuts"])
	}
}

func TestCoerceKeybindingOverridesRejectsInvalidShapes(t *testing.T) {
	raw := KeybindingOverrides{
		"close-shell-terminal": []ShortcutBinding{
			binding("n", ""),
			{Key: "j", Code: strings.Repeat("x", 33), Ctrl: true},
			binding("c", "c"),
		},
		"toggle-inspector": []ShortcutBinding{
			binding("shift", "cms"),
			{Key: strings.Repeat("k", 33), Alt: true},
			binding("b", "cs"),
		},
	}
	got := CoerceKeybindingOverrides(raw, false)
	if len(got["close-shell-terminal"]) != 1 {
		t.Fatalf("close-shell-terminal = %+v, want only the ctrl+J kept", got["close-shell-terminal"])
	}
	if got["close-shell-terminal"][0].Key != "j" || !got["close-shell-terminal"][0].Ctrl {
		t.Errorf("chord = %+v, want ctrl+J", got["close-shell-terminal"][0])
	}
	if got["close-shell-terminal"][0].Code != "" {
		t.Errorf("code = %q, want dropped", got["close-shell-terminal"][0].Code)
	}
	if _, ok := got["toggle-inspector"]; ok {
		t.Errorf("toggle-inspector = %+v, want omitted: its first two chords are invalid and the valid third is beyond the two-chord cap", got["toggle-inspector"])
	}
}

func TestCoerceKeybindingOverridesCapsTwoBindings(t *testing.T) {
	raw := KeybindingOverrides{
		"toggle-sidebar": {
			binding("1", "m"),
			binding("2", "m"),
			binding("3", "m"),
		},
	}
	got := CoerceKeybindingOverrides(raw, false)
	if len(got["toggle-sidebar"]) != 2 {
		t.Fatalf("bindings = %+v, want the first two of three", got["toggle-sidebar"])
	}
	if got["toggle-sidebar"][0].Key != "1" || got["toggle-sidebar"][1].Key != "2" {
		t.Errorf("bindings = %+v, want keys 1 and 2 in order", got["toggle-sidebar"])
	}
}

func TestCoerceKeybindingOverridesEmptyMeansUnassignedInvalidRecoversDefaults(t *testing.T) {
	raw := KeybindingOverrides{
		"command-palette": {},
		"open-settings":   {binding("q", "x")},
	}
	got := CoerceKeybindingOverrides(raw, false)
	if got["command-palette"] == nil || len(got["command-palette"]) != 0 {
		t.Errorf("command-palette = %v, want an intentional empty override", got["command-palette"])
	}
	if _, ok := got["open-settings"]; ok {
		t.Errorf("open-settings = %v, want the all-invalid override omitted so defaults recover", got["open-settings"])
	}
}

func TestCoerceKeybindingOverridesIgnoresNonCustomizableIDs(t *testing.T) {
	raw := KeybindingOverrides{
		"open-project":   {binding("5", "m")},
		"focus-terminal": {binding("t", "ms")},
	}
	got := CoerceKeybindingOverrides(raw, false)
	if _, ok := got["open-project"]; ok {
		t.Errorf("open-project = %v, want the indexed family left alone", got["open-project"])
	}
	if len(got["focus-terminal"]) != 1 {
		t.Errorf("focus-terminal = %v, want kept", got["focus-terminal"])
	}
}

func TestSetKeybindingsPersistsCoercedOverrides(t *testing.T) {
	store := &fakeStore{}
	svc := newTestService(store)

	snapshot, err := svc.SetKeybindings(context.Background(), KeybindingOverrides{
		"new-session":     {},
		"previous-tab":    {binding("p", "ca")},
		"next-tab":        {binding("[", "c")},
		"nonexistent-key": {binding("z", "m")},
	})
	if err != nil {
		t.Fatalf("set keybindings: %v", err)
	}
	if len(snapshot.Keybindings["new-session"]) != 0 {
		t.Errorf("new-session = %v, want unassigned", snapshot.Keybindings["new-session"])
	}
	if len(snapshot.Keybindings["previous-tab"]) != 1 {
		t.Errorf("previous-tab = %v, want kept", snapshot.Keybindings["previous-tab"])
	}
	if _, ok := snapshot.Keybindings["nonexistent-key"]; ok {
		t.Errorf("nonexistent-key persisted: %v", snapshot.Keybindings["nonexistent-key"])
	}

	var stored KeybindingOverrides
	if err := json.Unmarshal([]byte(store.rec.KeybindingsJSON), &stored); err != nil {
		t.Fatalf("stored keybindings are not JSON: %v (%q)", err, store.rec.KeybindingsJSON)
	}
	if _, ok := stored["new-session"]; !ok {
		t.Errorf("stored = %q, want the unassigned entry persisted", store.rec.KeybindingsJSON)
	}
}

func migrationState(status MigrationStatus) MigrationState {
	return MigrationState{Status: status}
}

func TestSetMigrationStateAcceptsFrontendTransitions(t *testing.T) {
	ctx := context.Background()
	transitions := []struct {
		name string
		from MigrationState
		to   MigrationStatus
	}{
		{"pending to declined", migrationState(MigrationPending), MigrationDeclined},
		{"failed to completed", migrationState(MigrationFailed), MigrationCompleted},
		{"completed to failed on re-run", migrationState(MigrationCompleted), MigrationFailed},
		{"declined to completed on re-run", migrationState(MigrationDeclined), MigrationCompleted},
		{"pending to failed", migrationState(MigrationPending), MigrationFailed},
	}
	for _, tt := range transitions {
		t.Run(tt.name, func(t *testing.T) {
			store := &fakeStore{rec: Record{MigrationJSON: mustJSON(t, tt.from)}}
			svc := newTestService(store)

			snapshot, err := svc.SetMigrationState(ctx, migrationState(tt.to))
			if err != nil {
				t.Fatalf("set migration: %v", err)
			}
			if snapshot.Migration.Status != tt.to {
				t.Errorf("status = %q, want %q", snapshot.Migration.Status, tt.to)
			}
		})
	}
}

func TestSetMigrationStateKeepsReportAndTimestamps(t *testing.T) {
	store := &fakeStore{}
	svc := newTestService(store)
	attempt := time.Date(2026, 8, 20, 8, 30, 0, 0, time.UTC)
	done := attempt.Add(time.Minute)

	snapshot, err := svc.SetMigrationState(context.Background(), MigrationState{
		Status:        MigrationCompleted,
		LastAttemptAt: &attempt,
		CompletedAt:   &done,
		Report:        &MigrationReport{ProjectsImported: 3, ProjectsSkipped: 1},
	})
	if err != nil {
		t.Fatalf("set migration: %v", err)
	}
	if snapshot.Migration.LastAttemptAt == nil || !snapshot.Migration.LastAttemptAt.Equal(attempt) {
		t.Errorf("lastAttemptAt = %v, want %v", snapshot.Migration.LastAttemptAt, attempt)
	}
	if snapshot.Migration.Report == nil || snapshot.Migration.Report.ProjectsImported != 3 {
		t.Errorf("report = %+v, want 3 imported", snapshot.Migration.Report)
	}
}

func TestSetMigrationStateRejectsUnknownStatus(t *testing.T) {
	store := &fakeStore{}
	svc := newTestService(store)

	_, err := svc.SetMigrationState(context.Background(), MigrationState{Status: "skipped"})
	var apiErr *apierr.Error
	if !errors.As(err, &apiErr) {
		t.Fatalf("err = %v, want an apierr.Error", err)
	}
	if apiErr.Code != "MIGRATION_STATUS_INVALID" {
		t.Errorf("code = %q, want MIGRATION_STATUS_INVALID", apiErr.Code)
	}
	if len(store.rec.MigrationJSON) != 0 {
		t.Errorf("rejected state persisted: %q", store.rec.MigrationJSON)
	}
}

func TestFacetUpdatesPreserveUnrelatedFields(t *testing.T) {
	store := &fakeStore{}
	svc := newTestService(store)
	ctx := context.Background()

	if _, err := svc.SetUILocale(ctx, "de"); err != nil {
		t.Fatalf("set locale: %v", err)
	}
	if _, err := svc.SetUpdateSettings(ctx, UpdateSettings{Enabled: true, Channel: UpdateChannelNightly, NightlyAck: true}); err != nil {
		t.Fatalf("set updates: %v", err)
	}
	if _, err := svc.SetKeybindings(ctx, KeybindingOverrides{"toggle-sidebar": {binding("b", "c")}}); err != nil {
		t.Fatalf("set keybindings: %v", err)
	}
	if _, err := svc.SetMigrationState(ctx, migrationState(MigrationDeclined)); err != nil {
		t.Fatalf("set migration: %v", err)
	}

	snapshot, err := svc.Get(ctx)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if snapshot.UILocale != "de" {
		t.Errorf("locale = %q, want de preserved through later facet writes", snapshot.UILocale)
	}
	if !snapshot.Updates.Enabled || snapshot.Updates.Channel != UpdateChannelNightly {
		t.Errorf("updates = %+v, want preserved", snapshot.Updates)
	}
	if len(snapshot.Keybindings["toggle-sidebar"]) != 1 {
		t.Errorf("keybindings = %v, want preserved", snapshot.Keybindings)
	}
	if snapshot.Migration.Status != MigrationDeclined {
		t.Errorf("migration = %q, want declined preserved", snapshot.Migration.Status)
	}
	if snapshot.DefaultSessionMode != domain.DefaultSessionMode {
		t.Errorf("session mode = %q, want the default untouched", snapshot.DefaultSessionMode)
	}
}

func TestConcurrentFacetWritesAllLand(t *testing.T) {
	store := &fakeStore{}
	svc := newTestService(store)
	ctx := context.Background()

	var wg sync.WaitGroup
	wg.Add(4)
	go func() {
		defer wg.Done()
		if _, err := svc.SetUILocale(ctx, "fr"); err != nil {
			t.Errorf("set locale: %v", err)
		}
	}()
	go func() {
		defer wg.Done()
		if _, err := svc.SetUpdateSettings(ctx, UpdateSettings{Enabled: true, Channel: UpdateChannelLatest}); err != nil {
			t.Errorf("set updates: %v", err)
		}
	}()
	go func() {
		defer wg.Done()
		if _, err := svc.SetKeybindings(ctx, KeybindingOverrides{"focus-terminal": {binding("t", "ms")}}); err != nil {
			t.Errorf("set keybindings: %v", err)
		}
	}()
	go func() {
		defer wg.Done()
		if _, err := svc.SetMigrationState(ctx, migrationState(MigrationCompleted)); err != nil {
			t.Errorf("set migration: %v", err)
		}
	}()
	wg.Wait()

	snapshot, err := svc.Get(ctx)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if snapshot.UILocale != "fr" {
		t.Errorf("locale = %q, want fr", snapshot.UILocale)
	}
	if !snapshot.Updates.Enabled {
		t.Errorf("updates = %+v, want enabled", snapshot.Updates)
	}
	if len(snapshot.Keybindings["focus-terminal"]) != 1 {
		t.Errorf("keybindings = %v, want focus-terminal override", snapshot.Keybindings)
	}
	if snapshot.Migration.Status != MigrationCompleted {
		t.Errorf("migration = %q, want completed", snapshot.Migration.Status)
	}
}

func TestMarkLegacyDesktopImportedRecordsMarker(t *testing.T) {
	store := &fakeStore{}
	svc := newTestService(store)
	at := time.Date(2026, 8, 21, 7, 0, 0, 0, time.UTC)

	if err := svc.MarkLegacyDesktopImported(context.Background(), at); err != nil {
		t.Fatalf("mark imported: %v", err)
	}

	snapshot, err := svc.Get(context.Background())
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if snapshot.LegacyDesktopImportedAt == nil || !snapshot.LegacyDesktopImportedAt.Equal(at) {
		t.Errorf("marker = %v, want %v", snapshot.LegacyDesktopImportedAt, at)
	}
}

func mustJSON(t *testing.T, v any) string {
	t.Helper()
	raw, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal %T: %v", v, err)
	}
	return string(raw)
}

func TestParseMigrationSelfHeals(t *testing.T) {
	cases := []struct {
		raw  string
		want MigrationStatus
	}{
		{"", MigrationPending},
		{"{}", MigrationPending},
		{"not json", MigrationPending},
		{`{"status":"weird"}`, MigrationPending},
		{`{"status":"completed","completedAt":"2026-08-20T10:00:00Z"}`, MigrationCompleted},
	}
	for _, tc := range cases {
		t.Run(fmt.Sprintf("%q", tc.raw), func(t *testing.T) {
			if got := parseMigration(tc.raw).Status; got != tc.want {
				t.Errorf("status = %q, want %q", got, tc.want)
			}
		})
	}
}
