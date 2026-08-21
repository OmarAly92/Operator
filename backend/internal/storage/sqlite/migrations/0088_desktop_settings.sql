-- Desktop preferences join the daemon-owned preference singleton.
--
-- The Tauri renderer resolves UI locale, update opt-in, keybinding overrides,
-- and the legacy-import decision through the daemon's settings API instead of
-- JSON files under ~/.operator, so desktop, mobile, and CLI keep one source of
-- truth. Columns are additive on the seeded singleton row; defaults match what
-- a missing legacy ui-settings.json/update-settings.json meant (English,
-- updates off, latest channel, no overrides, import still pending).

-- +goose Up
-- +goose StatementBegin
ALTER TABLE app_settings ADD COLUMN ui_locale TEXT NOT NULL DEFAULT 'en';
ALTER TABLE app_settings ADD COLUMN update_opt_in BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE app_settings ADD COLUMN update_channel TEXT NOT NULL DEFAULT 'latest'
    CHECK (update_channel IN ('latest', 'nightly'));
ALTER TABLE app_settings ADD COLUMN update_nightly_ack BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE app_settings ADD COLUMN update_feature_pr INTEGER;
ALTER TABLE app_settings ADD COLUMN keybindings_json TEXT NOT NULL DEFAULT '{}';
ALTER TABLE app_settings ADD COLUMN migration_json TEXT NOT NULL DEFAULT '{}';
-- Set by the one-time legacy-settings import; once non-NULL, stale files must
-- never overwrite newer SQLite values, so the marker is written at most once.
ALTER TABLE app_settings ADD COLUMN legacy_desktop_imported_at TIMESTAMP;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE app_settings DROP COLUMN legacy_desktop_imported_at;
ALTER TABLE app_settings DROP COLUMN migration_json;
ALTER TABLE app_settings DROP COLUMN keybindings_json;
ALTER TABLE app_settings DROP COLUMN update_feature_pr;
ALTER TABLE app_settings DROP COLUMN update_nightly_ack;
ALTER TABLE app_settings DROP COLUMN update_channel;
ALTER TABLE app_settings DROP COLUMN update_opt_in;
ALTER TABLE app_settings DROP COLUMN ui_locale;
-- +goose StatementEnd
