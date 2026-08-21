package settings

import (
	"encoding/json"
	"strings"
	"time"
)

// DefaultUILocale is what an unknown or unreadable locale resolves to.
const DefaultUILocale = "en"

var uiLocales = map[string]bool{
	"en":    true,
	"zh-CN": true,
	"ja":    true,
	"ko":    true,
	"es":    true,
	"fr":    true,
	"de":    true,
	"pt-BR": true,
}

// CoerceUILocale normalizes an unknown persisted or wire locale to a supported one.
func CoerceUILocale(raw string) string {
	if uiLocales[raw] {
		return raw
	}
	return DefaultUILocale
}

// UpdateChannel is the release feed the desktop updater watches.
type UpdateChannel string

// The update channels.
const (
	UpdateChannelLatest  UpdateChannel = "latest"
	UpdateChannelNightly UpdateChannel = "nightly"
)

// FeaturePin pins the desktop updater to one pull-request build.
type FeaturePin struct {
	PR int64 `json:"pr"`
}

// UpdateSettings is the desktop auto-update opt-in state.
type UpdateSettings struct {
	Enabled    bool          `json:"enabled"`
	Channel    UpdateChannel `json:"channel" enum:"latest,nightly"`
	NightlyAck bool          `json:"nightlyAck"`
	Feature    *FeaturePin   `json:"feature,omitempty"`
}

func coerceUpdateSettings(in UpdateSettings) UpdateSettings {
	out := UpdateSettings{
		Enabled:    in.Enabled,
		Channel:    UpdateChannelLatest,
		NightlyAck: in.NightlyAck,
	}
	if in.Channel == UpdateChannelNightly {
		out.Channel = UpdateChannelNightly
	}
	if in.Feature != nil && in.Feature.PR > 0 {
		out.Feature = &FeaturePin{PR: in.Feature.PR}
	}
	return out
}

// ShortcutBinding is one chord of a desktop shortcut, mirroring the client's
// KeyboardEvent-shaped binding.
type ShortcutBinding struct {
	Key   string `json:"key"`
	Code  string `json:"code,omitempty"`
	Ctrl  bool   `json:"ctrl"`
	Meta  bool   `json:"meta"`
	Shift bool   `json:"shift"`
	Alt   bool   `json:"alt"`
}

// KeybindingOverrides maps customizable shortcut IDs to their chords. A
// present-but-empty list intentionally means "unassigned"; an absent ID falls
// back to the client default.
type KeybindingOverrides map[string][]ShortcutBinding

var customizableShortcutIDs = []string{
	"new-session",
	"new-shell-terminal",
	"close-shell-terminal",
	"keyboard-shortcuts",
	"command-palette",
	"open-settings",
	"toggle-sidebar",
	"previous-session",
	"next-session",
	"previous-tab",
	"next-tab",
	"toggle-inspector",
	"focus-terminal",
	"toggle-browser-devtools",
}

var reservedModifierKeys = map[string]bool{
	"alt": true, "altgraph": true, "capslock": true, "control": true, "dead": true,
	"meta": true, "numlock": true, "process": true, "scrolllock": true, "shift": true,
	"unidentified": true,
}

var macMetaOnlyReservedKeys = map[string]bool{
	"a": true, "c": true, "h": true, "m": true, "q": true,
	"s": true, "v": true, "w": true, "x": true, "z": true,
}

var ctrlOnlyTerminalReservedKeys = map[string]bool{
	"d": true, "z": true, "\\": true, "s": true, "q": true,
}

// CoerceKeybindingOverrides drops every binding the desktop client would never
// match: unknown IDs, more than two chords per ID, over-long keys, modifier-only
// chords, and platform-reserved chords. An ID whose chords are all invalid is
// omitted so defaults recover; an explicitly empty list survives as "unassigned".
func CoerceKeybindingOverrides(raw KeybindingOverrides, isMac bool) KeybindingOverrides {
	out := KeybindingOverrides{}
	for _, id := range customizableShortcutIDs {
		chords := raw[id]
		if chords == nil {
			continue
		}
		if len(chords) > 2 {
			chords = chords[:2]
		}
		bindings := make([]ShortcutBinding, 0, len(chords))
		for _, chord := range chords {
			if binding, ok := coerceBinding(chord, isMac); ok {
				bindings = append(bindings, binding)
			}
		}
		if len(chords) > 0 && len(bindings) == 0 {
			continue
		}
		out[id] = bindings
	}
	return out
}

func coerceBinding(chord ShortcutBinding, isMac bool) (ShortcutBinding, bool) {
	if len(chord.Key) == 0 || len(chord.Key) > 32 {
		return ShortcutBinding{}, false
	}
	if len(chord.Code) > 32 {
		chord.Code = ""
	}
	if bindingRejected(chord, isMac) {
		return ShortcutBinding{}, false
	}
	return chord, true
}

func bindingRejected(chord ShortcutBinding, isMac bool) bool {
	key := normalizedBindingKey(chord.Key)
	if reservedModifierKeys[key] {
		return true
	}
	if !chord.Ctrl && !chord.Meta && !chord.Alt {
		return true
	}
	if chord.Ctrl && !chord.Meta && !chord.Alt {
		if key == "c" || key == "v" {
			return true
		}
		if !chord.Shift && ctrlOnlyTerminalReservedKeys[key] {
			return true
		}
	}
	if isMac && chord.Meta && !chord.Ctrl && !chord.Alt && macMetaOnlyReservedKeys[key] {
		return true
	}
	if !isMac && chord.Alt && !chord.Ctrl && !chord.Meta && key == "f4" {
		return true
	}
	return false
}

func normalizedBindingKey(key string) string {
	switch key {
	case "Up":
		return "arrowup"
	case "Down":
		return "arrowdown"
	}
	return strings.ToLower(key)
}

// MigrationStatus is the legacy-import decision state.
type MigrationStatus string

// The migration statuses.
const (
	MigrationPending   MigrationStatus = "pending"
	MigrationCompleted MigrationStatus = "completed"
	MigrationDeclined  MigrationStatus = "declined"
	MigrationFailed    MigrationStatus = "failed"
)

// Valid reports whether the status is one the API accepts.
func (s MigrationStatus) Valid() bool {
	switch s {
	case MigrationPending, MigrationCompleted, MigrationDeclined, MigrationFailed:
		return true
	}
	return false
}

// MigrationReport summarizes one legacy-import run.
type MigrationReport struct {
	ProjectsImported int `json:"projectsImported"`
	ProjectsSkipped  int `json:"projectsSkipped"`
}

// MigrationState is the durable record of the legacy desktop import.
type MigrationState struct {
	Status        MigrationStatus  `json:"status" enum:"pending,completed,declined,failed"`
	LastAttemptAt *time.Time       `json:"lastAttemptAt,omitempty"`
	CompletedAt   *time.Time       `json:"completedAt,omitempty"`
	Report        *MigrationReport `json:"report,omitempty"`
	Error         *string          `json:"error,omitempty"`
}

func parseKeybindings(raw string) KeybindingOverrides {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return KeybindingOverrides{}
	}
	var parsed KeybindingOverrides
	if err := json.Unmarshal([]byte(trimmed), &parsed); err != nil || parsed == nil {
		return KeybindingOverrides{}
	}
	return parsed
}

func parseMigration(raw string) MigrationState {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" || trimmed == "{}" {
		return MigrationState{Status: MigrationPending}
	}
	var parsed MigrationState
	if err := json.Unmarshal([]byte(trimmed), &parsed); err != nil || !parsed.Status.Valid() {
		return MigrationState{Status: MigrationPending}
	}
	return parsed
}
