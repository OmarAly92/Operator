-- +goose Up
-- +goose StatementBegin
DROP TRIGGER IF EXISTS sessions_cdc_update;
ALTER TABLE sessions DROP COLUMN session_mode;
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
            'autoInjectReview', json(CASE WHEN NEW.auto_inject_review THEN 'true' ELSE 'false' END)
        ),
        NEW.updated_at);
END;
ALTER TABLE app_settings DROP COLUMN default_session_mode;
DROP TRIGGER IF EXISTS conversation_branch_root_provider_update;
DROP TABLE IF EXISTS session_interface_transition_messages;
DROP TABLE IF EXISTS session_interface_transitions;
DROP TABLE IF EXISTS conversation_provider_events;
DROP TABLE IF EXISTS conversation_activities;
DROP TABLE IF EXISTS conversation_messages;
DROP TABLE IF EXISTS conversation_turns;
DROP TABLE IF EXISTS conversation_branches;
DROP TABLE IF EXISTS conversations;
-- +goose StatementEnd

-- +goose Down
SELECT 1;
