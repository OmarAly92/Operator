-- +goose NO TRANSACTION
-- +goose Up
PRAGMA writable_schema = ON;
UPDATE sqlite_master
SET sql = replace(sql, '''session_created''', '''session_created'', ''ticket_updated''')
WHERE type = 'table' AND name = 'change_log'
    AND instr(sql, '''ticket_updated''') = 0;
PRAGMA writable_schema = RESET;

CREATE TABLE tickets (
    project_id          TEXT NOT NULL REFERENCES projects (id),
    slug                TEXT NOT NULL,
    planning_session_id TEXT REFERENCES sessions (id) ON DELETE SET NULL,
    archived_at         TIMESTAMP,
    created_at          TIMESTAMP NOT NULL,
    PRIMARY KEY (project_id, slug)
);
CREATE INDEX idx_tickets_planning_session ON tickets (planning_session_id);

CREATE TABLE plan_assignments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id  TEXT NOT NULL,
    slug        TEXT NOT NULL,
    plan_file   TEXT NOT NULL,
    session_id  TEXT REFERENCES sessions (id) ON DELETE SET NULL,
    assigned_at TIMESTAMP NOT NULL,
    done_at     TIMESTAMP,
    reviewer_session_id TEXT REFERENCES sessions (id) ON DELETE SET NULL,
    review_requested_at TIMESTAMP,
    merge_ready_at      TIMESTAMP,
    merge_summary       TEXT NOT NULL DEFAULT '',
    merge_approved_at   TIMESTAMP,
    FOREIGN KEY (project_id, slug) REFERENCES tickets (project_id, slug) ON DELETE CASCADE
);
CREATE INDEX idx_plan_assignments_ticket ON plan_assignments (project_id, slug, plan_file, id);
CREATE INDEX idx_plan_assignments_session ON plan_assignments (session_id);
CREATE INDEX idx_plan_assignments_reviewer ON plan_assignments (reviewer_session_id);

-- +goose StatementBegin
CREATE TRIGGER tickets_cdc_insert
AFTER INSERT ON tickets
BEGIN
    INSERT INTO change_log (project_id, event_type, payload)
    VALUES (NEW.project_id, 'ticket_updated', json_object('projectId', NEW.project_id, 'slug', NEW.slug));
END;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE TRIGGER tickets_cdc_update
AFTER UPDATE ON tickets
BEGIN
    INSERT INTO change_log (project_id, event_type, payload)
    VALUES (NEW.project_id, 'ticket_updated', json_object('projectId', NEW.project_id, 'slug', NEW.slug));
END;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE TRIGGER plan_assignments_cdc_insert
AFTER INSERT ON plan_assignments
BEGIN
    INSERT INTO change_log (project_id, event_type, payload)
    VALUES (NEW.project_id, 'ticket_updated', json_object('projectId', NEW.project_id, 'slug', NEW.slug));
END;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE TRIGGER plan_assignments_cdc_update
AFTER UPDATE ON plan_assignments
BEGIN
    INSERT INTO change_log (project_id, event_type, payload)
    VALUES (NEW.project_id, 'ticket_updated', json_object('projectId', NEW.project_id, 'slug', NEW.slug));
END;
-- +goose StatementEnd

-- +goose Down
DROP TRIGGER IF EXISTS plan_assignments_cdc_update;
DROP TRIGGER IF EXISTS plan_assignments_cdc_insert;
DROP TRIGGER IF EXISTS tickets_cdc_update;
DROP TRIGGER IF EXISTS tickets_cdc_insert;
DROP INDEX IF EXISTS idx_plan_assignments_reviewer;
DROP INDEX IF EXISTS idx_plan_assignments_session;
DROP INDEX IF EXISTS idx_plan_assignments_ticket;
DROP TABLE IF EXISTS plan_assignments;
DROP INDEX IF EXISTS idx_tickets_planning_session;
DROP TABLE IF EXISTS tickets;
DELETE FROM change_log WHERE event_type = 'ticket_updated';
PRAGMA writable_schema = ON;
UPDATE sqlite_master
SET sql = replace(sql, '''session_created'', ''ticket_updated''', '''session_created''')
WHERE type = 'table' AND name = 'change_log';
PRAGMA writable_schema = RESET;
