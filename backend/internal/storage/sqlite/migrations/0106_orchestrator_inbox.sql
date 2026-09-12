-- +goose Up
-- +goose StatementBegin
CREATE TABLE orchestrator_inbox (
    id          TEXT PRIMARY KEY,
    project_id  TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    worker_id   TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    kind        TEXT NOT NULL CHECK (kind IN ('worker_idle','ci_failed','review_changes_requested')),
    occurred_at TIMESTAMP NOT NULL,
    state       TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','acked')),
    acked_at    TIMESTAMP,
    created_at  TIMESTAMP NOT NULL,
    updated_at  TIMESTAMP NOT NULL
);
-- +goose StatementEnd

-- +goose StatementBegin
CREATE UNIQUE INDEX idx_orchestrator_inbox_pending_worker
    ON orchestrator_inbox(worker_id, kind) WHERE state = 'pending';
-- +goose StatementEnd

-- +goose StatementBegin
CREATE INDEX idx_orchestrator_inbox_pending_project
    ON orchestrator_inbox(project_id) WHERE state = 'pending';
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE orchestrator_inbox;
-- +goose StatementEnd
