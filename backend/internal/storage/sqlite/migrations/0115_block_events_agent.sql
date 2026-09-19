-- +goose Up
ALTER TABLE block_events ADD COLUMN agent_id TEXT NOT NULL DEFAULT '';
ALTER TABLE block_events ADD COLUMN detail TEXT NOT NULL DEFAULT '';
CREATE INDEX block_events_session_agent_seq ON block_events (session_id, agent_id, seq);

-- +goose Down
DROP INDEX IF EXISTS block_events_session_agent_seq;
ALTER TABLE block_events DROP COLUMN detail;
ALTER TABLE block_events DROP COLUMN agent_id;
