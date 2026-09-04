package daemon

import (
	"context"
	"encoding/json"
	"time"

	settingssvc "github.com/OmarAly92/operator/backend/internal/service/settings"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite"
)

// settingsStore adapts the SQLite store to the settings service's Store.
//
// The two define their own snapshot types so neither depends on the other's; this
// is the one place that knows both, keeping the translation in the wiring.
type settingsStore struct{ store *sqlite.Store }

var _ settingssvc.Store = settingsStore{}

func (s settingsStore) GetAppSettings(ctx context.Context) (settingssvc.Record, error) {
	row, err := s.store.GetAppSettings(ctx)
	if err != nil {
		return settingssvc.Record{}, err
	}
	return settingssvc.Record{
		UpdatedAt:               row.UpdatedAt,
		UILocale:                row.UILocale,
		UpdateOptIn:             row.UpdateOptIn,
		UpdateChannel:           row.UpdateChannel,
		UpdateNightlyAck:        row.UpdateNightlyAck,
		UpdateFeaturePR:         row.UpdateFeaturePR,
		KeybindingsJSON:         row.KeybindingsJSON,
		MigrationJSON:           row.MigrationJSON,
		LegacyDesktopImportedAt: row.LegacyDesktopImportedAt,
	}, nil
}

func (s settingsStore) SetUILocale(ctx context.Context, locale string, now time.Time) error {
	return s.store.SetAppUILocale(ctx, locale, now)
}

func (s settingsStore) SetUpdateSettings(
	ctx context.Context,
	prefs settingssvc.UpdateSettings,
	now time.Time,
) error {
	var featurePR *int64
	if prefs.Feature != nil {
		pr := prefs.Feature.PR
		featurePR = &pr
	}
	return s.store.SetAppUpdateSettings(ctx, prefs.Enabled, string(prefs.Channel), prefs.NightlyAck, featurePR, now)
}

func (s settingsStore) SetKeybindings(
	ctx context.Context,
	overrides settingssvc.KeybindingOverrides,
	now time.Time,
) error {
	if overrides == nil {
		overrides = settingssvc.KeybindingOverrides{}
	}
	raw, err := json.Marshal(overrides)
	if err != nil {
		return err
	}
	return s.store.SetAppKeybindings(ctx, string(raw), now)
}

func (s settingsStore) SetMigrationState(
	ctx context.Context,
	state settingssvc.MigrationState,
	now time.Time,
) error {
	raw, err := json.Marshal(state)
	if err != nil {
		return err
	}
	return s.store.SetAppMigrationState(ctx, string(raw), now)
}

func (s settingsStore) MarkLegacyDesktopImported(ctx context.Context, importedAt time.Time) error {
	return s.store.MarkAppLegacyDesktopImported(ctx, importedAt)
}

func (s settingsStore) ApplyLegacyDesktopImport(
	ctx context.Context,
	legacyImport settingssvc.LegacyDesktopImport,
	importedAt time.Time,
) error {
	stored := sqlite.LegacyDesktopSettingsImport{UILocale: legacyImport.UILocale}
	if legacyImport.Updates != nil {
		updates := &sqlite.LegacyDesktopUpdateSettings{
			OptIn:      legacyImport.Updates.Enabled,
			Channel:    string(legacyImport.Updates.Channel),
			NightlyAck: legacyImport.Updates.NightlyAck,
		}
		if legacyImport.Updates.Feature != nil {
			pr := legacyImport.Updates.Feature.PR
			updates.FeaturePR = &pr
		}
		stored.Updates = updates
	}
	if legacyImport.Keybindings != nil {
		raw, err := json.Marshal(legacyImport.Keybindings)
		if err != nil {
			return err
		}
		encoded := string(raw)
		stored.KeybindingsJSON = &encoded
	}
	if legacyImport.Migration != nil {
		raw, err := json.Marshal(legacyImport.Migration)
		if err != nil {
			return err
		}
		encoded := string(raw)
		stored.MigrationJSON = &encoded
	}
	return s.store.ImportLegacyDesktopSettings(ctx, stored, importedAt)
}
