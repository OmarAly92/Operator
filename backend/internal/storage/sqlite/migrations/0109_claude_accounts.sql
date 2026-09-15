-- +goose Up
CREATE TABLE claude_accounts (
    id         TEXT PRIMARY KEY,
    label      TEXT NOT NULL UNIQUE,
    config_dir TEXT UNIQUE,
    is_default INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL,
    CHECK ((is_default = 1 AND config_dir IS NULL) OR (is_default = 0 AND config_dir IS NOT NULL))
);
CREATE UNIQUE INDEX idx_claude_accounts_single_default ON claude_accounts (is_default) WHERE is_default = 1;
INSERT INTO claude_accounts (id, label, config_dir, is_default, created_at)
VALUES ('default', 'Default', NULL, 1, CURRENT_TIMESTAMP);
ALTER TABLE sessions ADD COLUMN claude_account_id TEXT NOT NULL DEFAULT 'default';
CREATE INDEX idx_sessions_claude_account ON sessions (claude_account_id);

-- +goose StatementBegin
DROP TABLE agent_switches;
-- +goose StatementEnd
-- +goose StatementBegin
CREATE TABLE agent_switches (
    id                         TEXT PRIMARY KEY CHECK (length(id) > 0),
    session_id                 TEXT NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    idempotency_key            TEXT NOT NULL CHECK (length(idempotency_key) > 0),
    request_fingerprint        TEXT NOT NULL
        CHECK (
            length(request_fingerprint) = 67
            AND substr(request_fingerprint, 1, 3) = 'v1:'
            AND substr(request_fingerprint, 4) NOT GLOB '*[^0-9a-f]*'
        ),
    from_harness               TEXT NOT NULL CHECK (length(from_harness) > 0),
    target_harness             TEXT NOT NULL CHECK (length(target_harness) > 0),
    target_native_session_ref  TEXT REFERENCES agent_native_sessions (id) ON DELETE SET NULL,
    target_start_mode          TEXT NOT NULL DEFAULT ''
        CHECK (target_start_mode IN ('', 'fresh', 'resumed')),
    state                      TEXT NOT NULL DEFAULT 'preparing_handoff'
        CHECK (state IN (
            'preparing_handoff', 'stopping_source', 'source_stopped', 'starting_target',
            'target_ready', 'delivering_context', 'completed', 'failed'
        )),
    agent_handoff_status       TEXT NOT NULL DEFAULT 'not_attempted'
        CHECK (agent_handoff_status IN (
            'not_attempted', 'requested', 'received', 'unavailable',
            'timed_out', 'failed', 'rejected'
        )),
    source_transcript_status   TEXT NOT NULL DEFAULT 'not_attempted'
        CHECK (source_transcript_status IN ('not_attempted', 'available', 'unavailable')),
    semantic_handoff_included INTEGER NOT NULL DEFAULT 0
        CHECK (semantic_handoff_included IN (0, 1)),
    agent_handoff_path         TEXT NOT NULL DEFAULT '',
    agent_handoff_hash         TEXT NOT NULL DEFAULT '',
    source_generation_id       TEXT NOT NULL CHECK (length(source_generation_id) > 0),
    target_generation_id       TEXT NOT NULL DEFAULT '',
    target_runtime_handle_id   TEXT NOT NULL DEFAULT '',
    target_acknowledged_at     TIMESTAMP,
    error_code                 TEXT NOT NULL DEFAULT ''
        CHECK (error_code IN (
            '', 'daemon_restart_pre_stop', 'daemon_restart_post_stop',
            'daemon_restart_unrecoverable_target', 'daemon_restart_before_delivery',
            'delivery_unconfirmed', 'source_session_terminated', 'source_stop_unconfirmed',
            'target_binary_missing', 'target_agent_unauthorized', 'target_start_unconfirmed',
            'request_cancelled', 'source_blocked', 'failed_pre_stop', 'failed_post_stop',
            'target_ready_failed', 'delivery_failed', 'switch_failed'
        )),
    requested_at               TIMESTAMP NOT NULL,
    updated_at                 TIMESTAMP NOT NULL,
    final_handoff_path         TEXT NOT NULL DEFAULT '',
    final_handoff_hash         TEXT NOT NULL DEFAULT '',
    from_claude_account_id     TEXT NOT NULL DEFAULT '',
    target_claude_account_id   TEXT NOT NULL DEFAULT '',
    UNIQUE (session_id, idempotency_key),
    CHECK (from_harness <> target_harness OR from_claude_account_id <> target_claude_account_id),
    CHECK (
        (
            agent_handoff_status = 'received'
            AND agent_handoff_path <> ''
            AND length(agent_handoff_hash) = 64
            AND agent_handoff_hash NOT GLOB '*[^0-9a-f]*'
        )
        OR
        (agent_handoff_status <> 'received' AND agent_handoff_path = '' AND agent_handoff_hash = '')
    ),
    CHECK (state NOT IN ('completed', 'failed') OR agent_handoff_status <> 'requested'),
    CHECK (
        (state = 'failed' AND error_code NOT IN ('', 'target_start_unconfirmed'))
        OR (
            state = 'starting_target'
            AND target_runtime_handle_id = ''
            AND error_code = 'target_start_unconfirmed'
        )
        OR (state <> 'failed' AND error_code = '')
    ),
    CHECK (updated_at >= requested_at),
    CHECK (target_runtime_handle_id = '' OR target_generation_id <> ''),
    CHECK (target_acknowledged_at IS NULL OR target_generation_id <> ''),
    CHECK (target_acknowledged_at IS NULL OR target_acknowledged_at >= requested_at)
);
-- +goose StatementEnd
-- +goose StatementBegin
CREATE TRIGGER agent_switches_target_native_scope_insert
BEFORE INSERT ON agent_switches
WHEN NEW.target_native_session_ref IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM agent_native_sessions
        WHERE id = NEW.target_native_session_ref
          AND ao_session_id = NEW.session_id
          AND harness = NEW.target_harness
    )
BEGIN
    SELECT RAISE(ABORT, 'agent switch target native session scope mismatch');
END;
-- +goose StatementEnd
-- +goose StatementBegin
CREATE TRIGGER agent_switches_target_native_scope_update
BEFORE UPDATE OF session_id, target_harness, target_native_session_ref ON agent_switches
WHEN NEW.target_native_session_ref IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM agent_native_sessions
        WHERE id = NEW.target_native_session_ref
          AND ao_session_id = NEW.session_id
          AND harness = NEW.target_harness
    )
BEGIN
    SELECT RAISE(ABORT, 'agent switch target native session scope mismatch');
END;
-- +goose StatementEnd
-- +goose StatementBegin
CREATE UNIQUE INDEX idx_agent_switches_one_active_per_session
    ON agent_switches (session_id)
    WHERE state NOT IN ('completed', 'failed');
-- +goose StatementEnd

-- +goose StatementBegin
CREATE INDEX idx_agent_switches_session_history
    ON agent_switches (session_id, requested_at DESC, id DESC);
-- +goose StatementEnd
-- +goose StatementBegin
CREATE TRIGGER agent_switches_cdc_insert
AFTER INSERT ON agent_switches
BEGIN
    INSERT INTO change_log (project_id, session_id, event_type, payload, created_at)
    VALUES (
        (SELECT project_id FROM sessions WHERE id = NEW.session_id),
        NEW.session_id,
        'session_updated',
        json_object('id', NEW.session_id),
        NEW.updated_at
    );
END;
-- +goose StatementEnd
-- +goose StatementBegin
CREATE TRIGGER agent_switches_cdc_update
AFTER UPDATE ON agent_switches
BEGIN
    INSERT INTO change_log (project_id, session_id, event_type, payload, created_at)
    VALUES (
        (SELECT project_id FROM sessions WHERE id = NEW.session_id),
        NEW.session_id,
        'session_updated',
        json_object('id', NEW.session_id),
        NEW.updated_at
    );
END;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE agent_switches;
-- +goose StatementEnd
-- +goose StatementBegin
CREATE TABLE agent_switches (
    id                         TEXT PRIMARY KEY CHECK (length(id) > 0),
    session_id                 TEXT NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    idempotency_key            TEXT NOT NULL CHECK (length(idempotency_key) > 0),
    request_fingerprint        TEXT NOT NULL
        CHECK (
            length(request_fingerprint) = 67
            AND substr(request_fingerprint, 1, 3) = 'v1:'
            AND substr(request_fingerprint, 4) NOT GLOB '*[^0-9a-f]*'
        ),
    from_harness               TEXT NOT NULL CHECK (length(from_harness) > 0),
    target_harness             TEXT NOT NULL CHECK (length(target_harness) > 0),
    target_native_session_ref  TEXT REFERENCES agent_native_sessions (id) ON DELETE SET NULL,
    target_start_mode          TEXT NOT NULL DEFAULT ''
        CHECK (target_start_mode IN ('', 'fresh', 'resumed')),
    state                      TEXT NOT NULL DEFAULT 'preparing_handoff'
        CHECK (state IN (
            'preparing_handoff', 'stopping_source', 'source_stopped', 'starting_target',
            'target_ready', 'delivering_context', 'completed', 'failed'
        )),
    agent_handoff_status       TEXT NOT NULL DEFAULT 'not_attempted'
        CHECK (agent_handoff_status IN (
            'not_attempted', 'requested', 'received', 'unavailable',
            'timed_out', 'failed', 'rejected'
        )),
    source_transcript_status   TEXT NOT NULL DEFAULT 'not_attempted'
        CHECK (source_transcript_status IN ('not_attempted', 'available', 'unavailable')),
    semantic_handoff_included INTEGER NOT NULL DEFAULT 0
        CHECK (semantic_handoff_included IN (0, 1)),
    agent_handoff_path         TEXT NOT NULL DEFAULT '',
    agent_handoff_hash         TEXT NOT NULL DEFAULT '',
    source_generation_id       TEXT NOT NULL CHECK (length(source_generation_id) > 0),
    target_generation_id       TEXT NOT NULL DEFAULT '',
    target_runtime_handle_id   TEXT NOT NULL DEFAULT '',
    target_acknowledged_at     TIMESTAMP,
    error_code                 TEXT NOT NULL DEFAULT ''
        CHECK (error_code IN (
            '', 'daemon_restart_pre_stop', 'daemon_restart_post_stop',
            'daemon_restart_unrecoverable_target', 'daemon_restart_before_delivery',
            'delivery_unconfirmed', 'source_session_terminated', 'source_stop_unconfirmed',
            'target_binary_missing', 'target_agent_unauthorized', 'target_start_unconfirmed',
            'request_cancelled', 'source_blocked', 'failed_pre_stop', 'failed_post_stop',
            'target_ready_failed', 'delivery_failed', 'switch_failed'
        )),
    requested_at               TIMESTAMP NOT NULL,
    updated_at                 TIMESTAMP NOT NULL,
    final_handoff_path         TEXT NOT NULL DEFAULT '',
    final_handoff_hash         TEXT NOT NULL DEFAULT '',
    UNIQUE (session_id, idempotency_key),
    CHECK (from_harness <> target_harness),
    CHECK (
        (
            agent_handoff_status = 'received'
            AND agent_handoff_path <> ''
            AND length(agent_handoff_hash) = 64
            AND agent_handoff_hash NOT GLOB '*[^0-9a-f]*'
        )
        OR
        (agent_handoff_status <> 'received' AND agent_handoff_path = '' AND agent_handoff_hash = '')
    ),
    CHECK (state NOT IN ('completed', 'failed') OR agent_handoff_status <> 'requested'),
    CHECK (
        (state = 'failed' AND error_code NOT IN ('', 'target_start_unconfirmed'))
        OR (
            state = 'starting_target'
            AND target_runtime_handle_id = ''
            AND error_code = 'target_start_unconfirmed'
        )
        OR (state <> 'failed' AND error_code = '')
    ),
    CHECK (updated_at >= requested_at),
    CHECK (target_runtime_handle_id = '' OR target_generation_id <> ''),
    CHECK (target_acknowledged_at IS NULL OR target_generation_id <> ''),
    CHECK (target_acknowledged_at IS NULL OR target_acknowledged_at >= requested_at)
);
-- +goose StatementEnd
-- +goose StatementBegin
CREATE TRIGGER agent_switches_target_native_scope_insert
BEFORE INSERT ON agent_switches
WHEN NEW.target_native_session_ref IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM agent_native_sessions
        WHERE id = NEW.target_native_session_ref
          AND ao_session_id = NEW.session_id
          AND harness = NEW.target_harness
    )
BEGIN
    SELECT RAISE(ABORT, 'agent switch target native session scope mismatch');
END;
-- +goose StatementEnd
-- +goose StatementBegin
CREATE TRIGGER agent_switches_target_native_scope_update
BEFORE UPDATE OF session_id, target_harness, target_native_session_ref ON agent_switches
WHEN NEW.target_native_session_ref IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM agent_native_sessions
        WHERE id = NEW.target_native_session_ref
          AND ao_session_id = NEW.session_id
          AND harness = NEW.target_harness
    )
BEGIN
    SELECT RAISE(ABORT, 'agent switch target native session scope mismatch');
END;
-- +goose StatementEnd
-- +goose StatementBegin
CREATE UNIQUE INDEX idx_agent_switches_one_active_per_session
    ON agent_switches (session_id)
    WHERE state NOT IN ('completed', 'failed');
-- +goose StatementEnd

-- +goose StatementBegin
CREATE INDEX idx_agent_switches_session_history
    ON agent_switches (session_id, requested_at DESC, id DESC);
-- +goose StatementEnd
-- +goose StatementBegin
CREATE TRIGGER agent_switches_cdc_insert
AFTER INSERT ON agent_switches
BEGIN
    INSERT INTO change_log (project_id, session_id, event_type, payload, created_at)
    VALUES (
        (SELECT project_id FROM sessions WHERE id = NEW.session_id),
        NEW.session_id,
        'session_updated',
        json_object('id', NEW.session_id),
        NEW.updated_at
    );
END;
-- +goose StatementEnd
-- +goose StatementBegin
CREATE TRIGGER agent_switches_cdc_update
AFTER UPDATE ON agent_switches
BEGIN
    INSERT INTO change_log (project_id, session_id, event_type, payload, created_at)
    VALUES (
        (SELECT project_id FROM sessions WHERE id = NEW.session_id),
        NEW.session_id,
        'session_updated',
        json_object('id', NEW.session_id),
        NEW.updated_at
    );
END;
-- +goose StatementEnd
DROP INDEX idx_sessions_claude_account;
ALTER TABLE sessions DROP COLUMN claude_account_id;
DROP INDEX idx_claude_accounts_single_default;
DROP TABLE claude_accounts;
