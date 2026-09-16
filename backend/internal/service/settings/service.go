// Package settings owns Operator's daemon-side user preferences.
//
// It exists so every spawn surface — desktop, mobile, `opr spawn`, headless —
// resolves one value. A renderer-held preference would look correct in Settings
// while disagreeing with the CLI, which is worse than having no control.
package settings

import (
	"context"
	"runtime"
	"time"
)

// Record is the persisted preference row before preference-level
// normalization: JSON facets stay encoded and unknown values are passed
// through for the service to coerce.
type Record struct {
	UpdatedAt       time.Time
	UILocale        string
	UpdateOptIn     bool
	UpdateFeaturePR *int64
	KeybindingsJSON string
}

// Store is the durable preference surface.
type Store interface {
	GetAppSettings(ctx context.Context) (Record, error)
	SetUILocale(ctx context.Context, locale string, now time.Time) error
	SetUpdateSettings(ctx context.Context, prefs UpdateSettings, now time.Time) error
	SetKeybindings(ctx context.Context, overrides KeybindingOverrides, now time.Time) error
}

// Snapshot is the current preference set.
type Snapshot struct {
	UpdatedAt   time.Time
	UILocale    string
	Updates     UpdateSettings
	Keybindings KeybindingOverrides
}

// Service reads and writes preferences.
type Service struct {
	store Store
	now   func() time.Time
}

// New builds the service.
func New(store Store, now func() time.Time) *Service {
	if now == nil {
		now = func() time.Time { return time.Now().UTC() }
	}
	return &Service{store: store, now: now}
}

// Get returns the current preferences.
func (s *Service) Get(ctx context.Context) (Snapshot, error) {
	record, err := s.store.GetAppSettings(ctx)
	if err != nil {
		return Snapshot{}, err
	}
	return snapshotFromRecord(record), nil
}

// SetUILocale persists the desktop presentation language. An unrecognized value
// falls back to English instead of failing, matching what a corrupt legacy
// ui-settings.json always meant.
func (s *Service) SetUILocale(ctx context.Context, locale string) (Snapshot, error) {
	if err := s.store.SetUILocale(ctx, CoerceUILocale(locale), s.now()); err != nil {
		return Snapshot{}, err
	}
	return s.readAfterWrite(ctx)
}

// SetUpdateSettings persists the auto-update opt-in after normalizing the
// feature pin to its supported values.
func (s *Service) SetUpdateSettings(ctx context.Context, prefs UpdateSettings) (Snapshot, error) {
	if err := s.store.SetUpdateSettings(ctx, coerceUpdateSettings(prefs), s.now()); err != nil {
		return Snapshot{}, err
	}
	return s.readAfterWrite(ctx)
}

// SetKeybindings persists shortcut overrides after dropping bindings the
// desktop client would never match.
func (s *Service) SetKeybindings(ctx context.Context, overrides KeybindingOverrides) (Snapshot, error) {
	coerced := CoerceKeybindingOverrides(overrides, macHost())
	if err := s.store.SetKeybindings(ctx, coerced, s.now()); err != nil {
		return Snapshot{}, err
	}
	return s.readAfterWrite(ctx)
}

func (s *Service) readAfterWrite(ctx context.Context) (Snapshot, error) {
	record, err := s.store.GetAppSettings(ctx)
	if err != nil {
		return Snapshot{}, err
	}
	return snapshotFromRecord(record), nil
}

func snapshotFromRecord(record Record) Snapshot {
	featurePR := record.UpdateFeaturePR
	var feature *FeaturePin
	if featurePR != nil && *featurePR > 0 {
		feature = &FeaturePin{PR: *featurePR}
	}
	return Snapshot{
		UpdatedAt:   record.UpdatedAt,
		UILocale:    CoerceUILocale(record.UILocale),
		Updates:     coerceUpdateSettings(UpdateSettings{Enabled: record.UpdateOptIn, Feature: feature}),
		Keybindings: CoerceKeybindingOverrides(parseKeybindings(record.KeybindingsJSON), macHost()),
	}
}

func macHost() bool {
	return runtime.GOOS == "darwin"
}
