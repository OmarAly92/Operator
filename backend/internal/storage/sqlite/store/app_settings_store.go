package store

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
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
	// DefaultSessionMode is the interface a new session gets when the spawn does
	// not name one. Never applied to an existing session: only an explicit
	// interface transition changes a live session's committed mode, so
	// changing this only affects sessions created afterwards.
	DefaultSessionMode      domain.SessionMode
	UpdatedAt               time.Time
	UILocale                string
	UpdateOptIn             bool
	UpdateChannel           string
	UpdateNightlyAck        bool
	UpdateFeaturePR         *int64
	KeybindingsJSON         string
	MigrationJSON           string
	LegacyDesktopImportedAt *time.Time
}

// GetAppSettings reads the preference row.
func (s *Store) GetAppSettings(ctx context.Context) (AppSettings, error) {
	row, err := s.qr.GetAppSettings(ctx)
	if err != nil {
		return AppSettings{}, fmt.Errorf("read app settings: %w", err)
	}
	out := AppSettings{
		// Normalized on read: a value written by a build that knows a mode this
		// one does not must still resolve to something dispatchable.
		DefaultSessionMode: domain.NormalizeSessionMode(row.DefaultSessionMode),
		UpdatedAt:          row.UpdatedAt,
		UILocale:           row.UiLocale,
		UpdateOptIn:        row.UpdateOptIn,
		UpdateChannel:      row.UpdateChannel,
		UpdateNightlyAck:   row.UpdateNightlyAck,
		KeybindingsJSON:    row.KeybindingsJson,
		MigrationJSON:      row.MigrationJson,
	}
	if row.UpdateFeaturePR.Valid {
		pr := row.UpdateFeaturePR.Int64
		out.UpdateFeaturePR = &pr
	}
	if row.LegacyDesktopImportedAt.Valid {
		stamp := row.LegacyDesktopImportedAt.Time
		out.LegacyDesktopImportedAt = &stamp
	}
	return out, nil
}

// SetDefaultSessionMode persists the default interface for new sessions.
func (s *Store) SetDefaultSessionMode(ctx context.Context, mode domain.SessionMode, now time.Time) error {
	if !mode.Valid() {
		return fmt.Errorf("invalid session mode %q", mode)
	}
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	if err := s.qw.SetDefaultSessionMode(ctx, gen.SetDefaultSessionModeParams{
		DefaultSessionMode: mode,
		UpdatedAt:          now,
	}); err != nil {
		return fmt.Errorf("set default session mode: %w", err)
	}
	return nil
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
func (s *Store) SetAppUpdateSettings(
	ctx context.Context,
	optIn bool,
	channel string,
	nightlyAck bool,
	featurePR *int64,
	now time.Time,
) error {
	params := gen.SetAppUpdateSettingsParams{
		UpdateOptIn:      optIn,
		UpdateChannel:    channel,
		UpdateNightlyAck: nightlyAck,
		UpdatedAt:        now,
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

// MarkAppLegacyDesktopImported stamps the one-time legacy-settings import. The
// UPDATE's IS NULL guard makes the stamp write-once at the database level; a
// later call is a no-op that leaves both columns untouched.
func (s *Store) MarkAppLegacyDesktopImported(ctx context.Context, importedAt time.Time) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	if err := s.qw.MarkAppLegacyDesktopImported(ctx, gen.MarkAppLegacyDesktopImportedParams{
		LegacyDesktopImportedAt: sql.NullTime{Time: importedAt, Valid: true},
		UpdatedAt:               importedAt,
	}); err != nil {
		return fmt.Errorf("mark legacy desktop imported: %w", err)
	}
	return nil
}
