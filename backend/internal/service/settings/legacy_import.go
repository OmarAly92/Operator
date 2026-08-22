package settings

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// The desktop JSON files one import pass reads, named as the Electron main
// process wrote them beside running.json.
const (
	uiSettingsFileName     = "ui-settings.json"
	updateSettingsFileName = "update-settings.json"
	keybindingsFileName    = "keybindings.json"
	appStateFileName       = "app-state.json"
)

// LegacyFiles names the four legacy desktop preference files to import.
type LegacyFiles struct {
	UiSettings     string
	UpdateSettings string
	Keybindings    string
	AppState       string
}

// LegacyFilesUnder resolves the four files inside a state directory (the
// daemon's Operator state root, i.e. dirname of running.json).
func LegacyFilesUnder(stateDir string) LegacyFiles {
	return LegacyFiles{
		UiSettings:     filepath.Join(stateDir, uiSettingsFileName),
		UpdateSettings: filepath.Join(stateDir, updateSettingsFileName),
		Keybindings:    filepath.Join(stateDir, keybindingsFileName),
		AppState:       filepath.Join(stateDir, appStateFileName),
	}
}

// ImportLegacyDesktop imports the legacy desktop preference files exactly once,
// before settings are first served.
//
// A previous import (the write-once marker) skips everything so stale files can
// never overwrite newer SQLite values. A missing or unparseable file means that
// facet is absent: it is skipped, never an error, and never blocks startup —
// the same self-healing semantics the desktop readers had. Each file maps to
// one facet write, so every file's fields land together or not at all; the
// marker is stamped only after all facet writes commit, leaving any crash a
// safe re-attempt on the next boot.
func (s *Service) ImportLegacyDesktop(ctx context.Context, files LegacyFiles) error {
	record, err := s.store.GetAppSettings(ctx)
	if err != nil {
		return fmt.Errorf("read app settings before legacy import: %w", err)
	}
	if record.LegacyDesktopImportedAt != nil {
		return nil
	}

	if raw, ok := readLegacyFile(files.UiSettings); ok {
		if locale, ok := parseLegacyLocale(raw); ok {
			if _, err := s.SetUILocale(ctx, locale); err != nil {
				return fmt.Errorf("import legacy ui settings: %w", err)
			}
		}
	}
	if raw, ok := readLegacyFile(files.UpdateSettings); ok {
		if prefs, ok := parseLegacyUpdateSettings(raw); ok {
			if _, err := s.SetUpdateSettings(ctx, prefs); err != nil {
				return fmt.Errorf("import legacy update settings: %w", err)
			}
		}
	}
	if raw, ok := readLegacyFile(files.Keybindings); ok {
		if overrides, ok := parseLegacyKeybindings(raw); ok {
			if _, err := s.SetKeybindings(ctx, overrides); err != nil {
				return fmt.Errorf("import legacy keybindings: %w", err)
			}
		}
	}
	if raw, ok := readLegacyFile(files.AppState); ok {
		if state, ok := parseLegacyMigration(raw); ok {
			if _, err := s.SetMigrationState(ctx, state); err != nil {
				return fmt.Errorf("import legacy migration state: %w", err)
			}
		}
	}

	return s.MarkLegacyDesktopImported(ctx, s.now())
}

func readLegacyFile(path string) (json.RawMessage, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, false
	}
	var raw json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, false
	}
	return raw, true
}

func parseLegacyLocale(raw json.RawMessage) (string, bool) {
	var parsed map[string]any
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return "", false
	}
	locale, ok := parsed["locale"].(string)
	return locale, ok
}

func parseLegacyUpdateSettings(raw json.RawMessage) (UpdateSettings, bool) {
	var parsed map[string]any
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return UpdateSettings{}, false
	}
	prefs := UpdateSettings{
		Enabled:    parsed["enabled"] == true,
		Channel:    UpdateChannelLatest,
		NightlyAck: parsed["nightlyAck"] == true,
	}
	if parsed["channel"] == "nightly" {
		prefs.Channel = UpdateChannelNightly
	}
	if feature, ok := parsed["feature"].(map[string]any); ok {
		if pr, ok := feature["pr"].(float64); ok && pr > 0 && pr == float64(int64(pr)) {
			prefs.Feature = &FeaturePin{PR: int64(pr)}
		}
	}
	return prefs, true
}

func parseLegacyKeybindings(raw json.RawMessage) (KeybindingOverrides, bool) {
	var parsed map[string]any
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return KeybindingOverrides{}, false
	}
	overrides := KeybindingOverrides{}
	for _, id := range customizableShortcutIDs {
		value, ok := parsed[id]
		if !ok {
			continue
		}
		chords, ok := value.([]any)
		if !ok {
			continue
		}
		bindings := make([]ShortcutBinding, 0, len(chords))
		for i, chord := range chords {
			if i >= 2 {
				break
			}
			fields, ok := chord.(map[string]any)
			if !ok {
				continue
			}
			key, ok := fields["key"].(string)
			if !ok || key == "" || len(key) > 32 {
				continue
			}
			binding := ShortcutBinding{
				Key:   key,
				Ctrl:  fields["ctrl"] == true,
				Meta:  fields["meta"] == true,
				Shift: fields["shift"] == true,
				Alt:   fields["alt"] == true,
			}
			if code, ok := fields["code"].(string); ok && code != "" && len(code) <= 32 {
				binding.Code = code
			}
			bindings = append(bindings, binding)
		}
		if len(chords) > 0 && len(bindings) == 0 {
			continue
		}
		overrides[id] = bindings
	}
	return overrides, true
}

func parseLegacyMigration(raw json.RawMessage) (MigrationState, bool) {
	var marker struct {
		Migration *MigrationState `json:"migration"`
	}
	if err := json.Unmarshal(raw, &marker); err != nil {
		return MigrationState{}, false
	}
	if marker.Migration == nil || !marker.Migration.Status.Valid() {
		return MigrationState{}, false
	}
	return *marker.Migration, true
}
