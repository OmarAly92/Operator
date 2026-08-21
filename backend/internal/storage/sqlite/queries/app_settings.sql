-- Daemon-owned user preferences. One row, seeded by migration 0042, so a read
-- never has to handle absence. Desktop preference columns arrive in migration
-- 0088; each setter below updates only its own facet plus updated_at, so
-- concurrent facet writes cannot clobber each other.

-- name: GetAppSettings :one
SELECT * FROM app_settings WHERE id = 1;

-- name: SetDefaultSessionMode :exec
UPDATE app_settings SET default_session_mode = ?, updated_at = ? WHERE id = 1;

-- name: SetAppUILocale :exec
UPDATE app_settings SET ui_locale = ?, updated_at = ? WHERE id = 1;

-- name: SetAppUpdateSettings :exec
UPDATE app_settings
SET update_opt_in = ?, update_channel = ?, update_nightly_ack = ?, update_feature_pr = ?, updated_at = ?
WHERE id = 1;

-- name: SetAppKeybindings :exec
UPDATE app_settings SET keybindings_json = ?, updated_at = ? WHERE id = 1;

-- name: SetAppMigrationState :exec
UPDATE app_settings SET migration_json = ?, updated_at = ? WHERE id = 1;

-- The legacy-import marker is write-once at the database level: once set, a
-- later import attempt must not move it or re-open the import window.
-- name: MarkAppLegacyDesktopImported :exec
UPDATE app_settings SET legacy_desktop_imported_at = ?, updated_at = ?
WHERE id = 1 AND legacy_desktop_imported_at IS NULL;
