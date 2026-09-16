package store

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/gen"
)

// Daemon-owned user preferences.
//
// The row is seeded by migration, so a read is a plain SELECT and no caller has
// to handle "settings do not exist yet".

// AppSettings is the durable preference set. The daemon wiring adapts it to the
// settings service's Record; JSON facets stay encoded because interpreting them
// is preference policy, not storage policy.
type AppSettings struct {
	UpdatedAt       time.Time
	UILocale        string
	UpdateOptIn     bool
	UpdateFeaturePR *int64
	KeybindingsJSON string
	MigrationJSON   string
}

// GetAppSettings reads the preference row.
func (s *Store) GetAppSettings(ctx context.Context) (AppSettings, error) {
	row, err := s.qr.GetAppSettings(ctx)
	if err != nil {
		return AppSettings{}, fmt.Errorf("read app settings: %w", err)
	}
	out := AppSettings{
		UpdatedAt:       row.UpdatedAt,
		UILocale:        row.UiLocale,
		UpdateOptIn:     row.UpdateOptIn,
		KeybindingsJSON: row.KeybindingsJson,
		MigrationJSON:   row.MigrationJson,
	}
	if row.UpdateFeaturePR.Valid {
		pr := row.UpdateFeaturePR.Int64
		out.UpdateFeaturePR = &pr
	}
	return out, nil
}

// SetAppUILocale persists the desktop presentation language.
func (s *Store) SetAppUILocale(ctx context.Context, locale string, now time.Time) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	if err := s.qw.SetAppUILocale(ctx, gen.SetAppUILocaleParams{UiLocale: locale, UpdatedAt: now}); err != nil {
		return fmt.Errorf("set ui locale: %w", err)
	}
	return nil
}

// SetAppUpdateSettings persists the auto-update opt-in facet.
func (s *Store) SetAppUpdateSettings(ctx context.Context, optIn bool, featurePR *int64, now time.Time) error {
	params := gen.SetAppUpdateSettingsParams{
		UpdateOptIn: optIn,
		UpdatedAt:   now,
	}
	if featurePR != nil {
		params.UpdateFeaturePR = sql.NullInt64{Int64: *featurePR, Valid: true}
	}
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	if err := s.qw.SetAppUpdateSettings(ctx, params); err != nil {
		return fmt.Errorf("set update settings: %w", err)
	}
	return nil
}

// SetAppKeybindings persists the encoded shortcut-override facet.
func (s *Store) SetAppKeybindings(ctx context.Context, raw string, now time.Time) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	if err := s.qw.SetAppKeybindings(ctx, gen.SetAppKeybindingsParams{KeybindingsJson: raw, UpdatedAt: now}); err != nil {
		return fmt.Errorf("set keybindings: %w", err)
	}
	return nil
}

// SetAppMigrationState persists the encoded legacy-import decision facet.
func (s *Store) SetAppMigrationState(ctx context.Context, raw string, now time.Time) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	if err := s.qw.SetAppMigrationState(ctx, gen.SetAppMigrationStateParams{MigrationJson: raw, UpdatedAt: now}); err != nil {
		return fmt.Errorf("set migration state: %w", err)
	}
	return nil
}
