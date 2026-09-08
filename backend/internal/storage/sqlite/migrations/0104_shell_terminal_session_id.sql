-- +goose Up
-- +goose StatementBegin
-- session_id scopes a shell terminal to the agent session it was opened from,
-- so the session's tab strip can show its own shells beside the agent pane.
-- Nullable on purpose: a shell opened from the topbar or the standalone
-- /terminals screen belongs to no session and lives only on that screen.
--
-- ON DELETE CASCADE ties a session's shells to its lifetime, mirroring
-- project_id: deleting the session forgets its shell rows too.
ALTER TABLE shell_terminals
    ADD COLUMN session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE;

-- The session tab strip reads one session's shells on every render of a
-- session route, so that lookup gets its own index rather than scanning the
-- app run's whole shell list.
CREATE INDEX idx_shell_terminals_session
    ON shell_terminals(session_id, created_at);
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP INDEX IF EXISTS idx_shell_terminals_session;
ALTER TABLE shell_terminals DROP COLUMN session_id;
-- +goose StatementEnd
