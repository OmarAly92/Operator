-- Remove the orchestrator subsystem's schema: the sessions.kind discriminator,
-- the spawned_by attribution column, and the orchestrator inbox.
--
-- sessions.kind carries CHECK (kind IN ('worker', 'orchestrator')) from
-- 0001_init, and SQLite refuses ALTER TABLE ... DROP COLUMN on a column named in
-- a CHECK constraint. Rebuilding the table would drop its triggers, including
-- sessions_cdc_update, which is the only source of the session_updated events
-- that carry activity and isTerminated to the desktop board and to mobile. So we
-- edit the CHECK out in place with the same writable_schema pattern used for the
-- harness constraint in 0053/0054/0082/0083, then DROP COLUMN normally.
--
-- Verified before writing: no trigger or index on sessions references kind or
-- spawned_by. The OLD.kind in 0108_board_cdc.sql belongs to projects_cdc_update
-- and refers to projects.kind, a different column on a different table.

-- +goose NO TRANSACTION
-- +goose Up
-- change_log.session_id references sessions(id) with no ON DELETE CASCADE, so rows
-- for orchestrator sessions must be deleted first to avoid a foreign-key violation.
DELETE FROM change_log WHERE session_id IN (SELECT id FROM sessions WHERE kind = 'orchestrator');
DELETE FROM sessions WHERE kind = 'orchestrator';

PRAGMA writable_schema = ON;
UPDATE sqlite_master
SET sql = replace(sql, 'CHECK (kind IN (''worker'', ''orchestrator''))', '')
WHERE type = 'table' AND name = 'sessions'
    AND instr(sql, 'CHECK (kind IN') > 0;
PRAGMA writable_schema = RESET;

ALTER TABLE sessions DROP COLUMN kind;
ALTER TABLE sessions DROP COLUMN spawned_by;

DROP TABLE IF EXISTS orchestrator_inbox;

-- +goose Down
-- Irreversible: the orchestrator rows and inbox contents are gone. Restoring the
-- columns without their data would misrepresent history, and Operator is
-- pre-release with no installed users to migrate down.
SELECT 1;
