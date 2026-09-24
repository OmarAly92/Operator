-- Agent-reported board state. An agent in an Operator session reports through
-- the Operator MCP server that it is waiting on the user (needs_you) or that its
-- work is ready for review without a PR (ready_for_review). These are durable
-- facts the status derivation reads; the display status itself stays derived.
-- The columns are written only by their own queries, never by UpdateSession, so
-- a whole-record lifecycle write cannot clobber a report. sessions_cdc_update
-- must see them, or the board and mobile never learn about a report.

-- +goose Up
-- +goose StatementBegin
ALTER TABLE sessions ADD COLUMN agent_report_state TEXT NOT NULL DEFAULT ''
    CHECK (agent_report_state IN ('', 'needs_you', 'ready_for_review'));
ALTER TABLE sessions ADD COLUMN agent_report_reason TEXT NOT NULL DEFAULT '';
ALTER TABLE sessions ADD COLUMN agent_report_at TIMESTAMP;
DROP TRIGGER IF EXISTS sessions_cdc_update;
CREATE TRIGGER sessions_cdc_update
AFTER UPDATE ON sessions
WHEN OLD.activity_state <> NEW.activity_state
    OR OLD.is_terminated <> NEW.is_terminated
    OR (OLD.first_signal_at IS NULL AND NEW.first_signal_at IS NOT NULL)
    OR OLD.preview_url <> NEW.preview_url
    OR OLD.preview_revision <> NEW.preview_revision
    OR OLD.preview_opened_revision <> NEW.preview_opened_revision
    OR OLD.display_name <> NEW.display_name
    OR OLD.terminate_on_pr_merge <> NEW.terminate_on_pr_merge
    OR OLD.is_pinned <> NEW.is_pinned
    OR OLD.pinned_at <> NEW.pinned_at
    OR (OLD.pinned_at IS NULL AND NEW.pinned_at IS NOT NULL)
    OR (OLD.pinned_at IS NOT NULL AND NEW.pinned_at IS NULL)
    OR OLD.auto_inject_review <> NEW.auto_inject_review
    OR OLD.harness <> NEW.harness
    OR OLD.runtime_launch_id <> NEW.runtime_launch_id
    OR OLD.agent_session_id <> NEW.agent_session_id
    OR OLD.native_transcript_path <> NEW.native_transcript_path
    OR OLD.agent_report_state <> NEW.agent_report_state
    OR OLD.agent_report_reason <> NEW.agent_report_reason
BEGIN
    INSERT INTO change_log (project_id, session_id, event_type, payload, created_at)
    VALUES (NEW.project_id, NEW.id, 'session_updated',
        json_object(
            'id', NEW.id,
            'activity', NEW.activity_state,
            'isTerminated', json(CASE WHEN NEW.is_terminated THEN 'true' ELSE 'false' END),
            'terminateOnPrMerge', json(CASE WHEN NEW.terminate_on_pr_merge THEN 'true' ELSE 'false' END),
            'previewUrl', NEW.preview_url,
            'previewRevision', NEW.preview_revision,
            'previewOpenedRevision', NEW.preview_opened_revision,
            'isPinned', json(CASE WHEN NEW.is_pinned THEN 'true' ELSE 'false' END),
            'autoInjectReview', json(CASE WHEN NEW.auto_inject_review THEN 'true' ELSE 'false' END),
            'agentReportState', NEW.agent_report_state,
            'agentReportReason', NEW.agent_report_reason
        ),
        NEW.updated_at);
END;
-- +goose StatementEnd

-- +goose Down
SELECT 1;
