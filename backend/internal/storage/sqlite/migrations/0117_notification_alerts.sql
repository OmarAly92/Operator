-- +goose Up
-- +goose StatementBegin
CREATE TABLE notifications_next (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    pr_url TEXT NOT NULL DEFAULT '',
    type TEXT NOT NULL CHECK (
        type IN (
            'needs_input',
            'ready_to_merge',
            'pr_merged',
            'pr_closed_unmerged',
            'turn_finished',
            'agent_exited'
        )
    ),
    title TEXT NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'unread' CHECK (status IN ('read', 'unread')),
    created_at TIMESTAMP NOT NULL,
    resolved_at TIMESTAMP,
    quiet BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO notifications_next (id, session_id, project_id, pr_url, type, title, body, status, created_at, resolved_at)
SELECT id, session_id, project_id, pr_url, type, title, body, status, created_at, resolved_at
FROM notifications;

DROP TABLE notifications;
ALTER TABLE notifications_next RENAME TO notifications;

CREATE INDEX idx_notifications_status_history
    ON notifications(status, created_at DESC, id DESC);

CREATE INDEX idx_notifications_history
    ON notifications(created_at DESC, id DESC);

CREATE INDEX idx_notifications_unresolved
    ON notifications(resolved_at, created_at DESC, id DESC);

CREATE UNIQUE INDEX idx_notifications_open_dedupe
    ON notifications(session_id, type, pr_url)
    WHERE resolved_at IS NULL;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
CREATE TABLE notifications_prev (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    pr_url TEXT NOT NULL DEFAULT '',
    type TEXT NOT NULL CHECK (
        type IN (
            'needs_input',
            'ready_to_merge',
            'pr_merged',
            'pr_closed_unmerged'
        )
    ),
    title TEXT NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'unread' CHECK (status IN ('read', 'unread')),
    created_at TIMESTAMP NOT NULL,
    resolved_at TIMESTAMP
);

INSERT INTO notifications_prev (id, session_id, project_id, pr_url, type, title, body, status, created_at, resolved_at)
SELECT id, session_id, project_id, pr_url, type, title, body, status, created_at, resolved_at
FROM notifications
WHERE type IN ('needs_input', 'ready_to_merge', 'pr_merged', 'pr_closed_unmerged');

UPDATE notifications_prev
SET status = 'read'
WHERE resolved_at IS NOT NULL;

DROP TABLE notifications;
ALTER TABLE notifications_prev RENAME TO notifications;

CREATE INDEX idx_notifications_status_history
    ON notifications(status, created_at DESC, id DESC);

CREATE INDEX idx_notifications_history
    ON notifications(created_at DESC, id DESC);

CREATE INDEX idx_notifications_unresolved
    ON notifications(resolved_at, created_at DESC, id DESC);

CREATE UNIQUE INDEX idx_notifications_open_dedupe
    ON notifications(session_id, type, pr_url)
    WHERE status = 'unread' OR resolved_at IS NULL;
-- +goose StatementEnd
