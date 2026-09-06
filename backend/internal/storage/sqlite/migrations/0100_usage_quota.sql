-- Migration 0100: the account's Codex quota position.
--
-- One row for the account, not one per session: every Codex rollout reports the
-- same account-wide counter, and readings from different sessions are the same
-- fact observed twice. Keyed on limit_id because Codex reports more than one
-- ("codex" carries the populated windows; a "premium" variant was seen with both
-- windows null).
--
-- Percentages are nullable because a window can be absent from an observation,
-- and absent must stay distinguishable from zero -- 0% used and "not reported"
-- are opposite messages. resets_at is stored as a timestamp; the wire format is
-- Unix epoch seconds.

-- +goose Up
-- +goose StatementBegin
CREATE TABLE usage_quota (
    limit_id                TEXT PRIMARY KEY,
    harness                 TEXT NOT NULL,
    plan_type               TEXT NOT NULL DEFAULT '',
    observed_at             TIMESTAMP NOT NULL,
    primary_used_percent    REAL    CHECK (primary_used_percent IS NULL OR primary_used_percent >= 0),
    primary_window_minutes  INTEGER CHECK (primary_window_minutes IS NULL OR primary_window_minutes > 0),
    primary_resets_at       TIMESTAMP,
    secondary_used_percent  REAL    CHECK (secondary_used_percent IS NULL OR secondary_used_percent >= 0),
    secondary_window_minutes INTEGER CHECK (secondary_window_minutes IS NULL OR secondary_window_minutes > 0),
    secondary_resets_at     TIMESTAMP
);
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS usage_quota;
-- +goose StatementEnd
