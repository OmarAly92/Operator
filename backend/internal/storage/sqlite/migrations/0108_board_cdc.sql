-- +goose NO TRANSACTION
-- +goose Up
PRAGMA writable_schema = ON;
UPDATE sqlite_master
SET sql = replace(sql, '''session_created''', '''session_created'', ''session_deleted'', ''project_created'', ''project_updated''')
WHERE type = 'table' AND name = 'change_log'
    AND instr(sql, '''project_created''') = 0;
PRAGMA writable_schema = RESET;

-- +goose StatementBegin
CREATE TRIGGER IF NOT EXISTS projects_cdc_insert
AFTER INSERT ON projects
BEGIN
    INSERT INTO change_log (project_id, event_type, payload)
    VALUES (NEW.id, 'project_created', json_object('id', NEW.id));
END;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE TRIGGER IF NOT EXISTS projects_cdc_update
AFTER UPDATE ON projects
WHEN OLD.path IS NOT NEW.path
    OR OLD.display_name IS NOT NEW.display_name
    OR OLD.archived_at IS NOT NEW.archived_at
    OR OLD.config IS NOT NEW.config
    OR OLD.kind IS NOT NEW.kind
BEGIN
    INSERT INTO change_log (project_id, event_type, payload)
    VALUES (NEW.id, 'project_updated', json_object('id', NEW.id));
END;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE TRIGGER IF NOT EXISTS sessions_cdc_delete
AFTER DELETE ON sessions
BEGIN
    INSERT INTO change_log (project_id, event_type, payload)
    VALUES (OLD.project_id, 'session_deleted', json_object('id', OLD.id));
END;
-- +goose StatementEnd

-- +goose Down
DROP TRIGGER IF EXISTS sessions_cdc_delete;
DROP TRIGGER IF EXISTS projects_cdc_update;
DROP TRIGGER IF EXISTS projects_cdc_insert;
DELETE FROM change_log WHERE event_type IN ('session_deleted', 'project_created', 'project_updated');
PRAGMA writable_schema = ON;
UPDATE sqlite_master
SET sql = replace(sql, '''session_created'', ''session_deleted'', ''project_created'', ''project_updated''', '''session_created''')
WHERE type = 'table' AND name = 'change_log';
PRAGMA writable_schema = RESET;
