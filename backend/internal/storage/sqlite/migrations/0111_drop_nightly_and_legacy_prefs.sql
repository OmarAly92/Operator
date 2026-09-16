-- +goose NO TRANSACTION
-- +goose Up
-- +goose StatementBegin
PRAGMA foreign_keys=OFF;

CREATE TABLE app_settings_new (
    id                INTEGER PRIMARY KEY CHECK (id = 1),
    updated_at        TIMESTAMP NOT NULL,
    ui_locale         TEXT NOT NULL DEFAULT 'en',
    update_opt_in     BOOLEAN NOT NULL DEFAULT FALSE,
    update_feature_pr INTEGER,
    keybindings_json  TEXT NOT NULL DEFAULT '{}',
    migration_json    TEXT NOT NULL DEFAULT '{}'
);

INSERT INTO app_settings_new (id, updated_at, ui_locale, update_opt_in, update_feature_pr, keybindings_json, migration_json)
SELECT id, updated_at, ui_locale, update_opt_in, update_feature_pr, keybindings_json, migration_json
FROM app_settings;

DROP TABLE app_settings;
ALTER TABLE app_settings_new RENAME TO app_settings;

PRAGMA foreign_keys=ON;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE app_settings ADD COLUMN update_channel TEXT NOT NULL DEFAULT 'latest'
    CHECK (update_channel IN ('latest'));
ALTER TABLE app_settings ADD COLUMN update_nightly_ack BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE app_settings ADD COLUMN legacy_desktop_imported_at TIMESTAMP;
-- +goose StatementEnd
