package controllers

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	"github.com/OmarAly92/operator/backend/internal/service/backgroundtask"
)

type BackgroundTaskService interface {
	List(ctx context.Context, id domain.SessionID) ([]backgroundtask.Task, error)
	Stop(ctx context.Context, id domain.SessionID, taskID string) (backgroundtask.StopOutcome, error)
}

func (c *SessionsController) listTasks(w http.ResponseWriter, r *http.Request) {
	if c.Tasks == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/sessions/{sessionId}/tasks")
		return
	}
	tasks, err := c.Tasks.List(r.Context(), sessionID(r))
	if err != nil {
		writeTaskError(w, r, err)
		return
	}
	views := make([]SessionTaskView, 0, len(tasks))
	for _, task := range tasks {
		views = append(views, sessionTaskView(task))
	}
	envelope.WriteJSON(w, http.StatusOK, ListSessionTasksResponse{Tasks: views})
}

func (c *SessionsController) stopTask(w http.ResponseWriter, r *http.Request) {
	if c.Tasks == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/sessions/{sessionId}/tasks/{taskId}/stop")
		return
	}
	taskID := strings.TrimSpace(chi.URLParam(r, "taskId"))
	outcome, err := c.Tasks.Stop(r.Context(), sessionID(r), taskID)
	if err != nil {
		writeTaskError(w, r, err)
		return
	}
	status := http.StatusAccepted
	if outcome.Confirmed {
		status = http.StatusOK
	}
	envelope.WriteJSON(w, status, StopSessionTaskResponse{Task: sessionTaskView(outcome.Task), Confirmed: outcome.Confirmed})
}

func writeTaskError(w http.ResponseWriter, r *http.Request, err error) {
	conflict := func(code, message string) {
		envelope.WriteAPIError(w, r, http.StatusConflict, "conflict", code, message, nil)
	}
	switch {
	case errors.Is(err, domain.ErrTaskSessionNotFound):
		envelope.WriteAPIError(w, r, http.StatusNotFound, "not_found", "SESSION_NOT_FOUND", "session not found", nil)
	case errors.Is(err, domain.ErrTaskNotFound):
		envelope.WriteAPIError(w, r, http.StatusNotFound, "not_found", "TASK_NOT_FOUND", "background task not found", nil)
	case errors.Is(err, domain.ErrTaskProcessNotFound):
		envelope.WriteAPIError(w, r, http.StatusNotFound, "not_found", "TASK_NOT_FOUND", "the background task's process was not found", nil)
	case errors.Is(err, domain.ErrTaskFinished):
		conflict("TASK_FINISHED", "the background task has already finished")
	case errors.Is(err, domain.ErrTaskAmbiguous):
		conflict("TASK_AMBIGUOUS", "more than one running task matches; refusing to guess")
	case errors.Is(err, domain.ErrTaskUnsafe):
		conflict("TASK_UNSAFE", "the task's process group is shared with the agent or the session; refusing to signal it")
	case errors.Is(err, domain.ErrTaskStopUnsupported):
		envelope.WriteAPIError(w, r, http.StatusUnprocessableEntity, "unprocessable", "TASK_STOP_UNSUPPORTED", "this background task cannot be stopped from here", nil)
	case errors.Is(err, domain.ErrTaskStopUnconfirmed):
		envelope.WriteAPIError(w, r, http.StatusGatewayTimeout, "timeout", "TASK_STOP_UNCONFIRMED", "the stop was sent but the task has not reported stopping yet", nil)
	case errors.Is(err, domain.ErrTaskPanelUnavailable):
		conflict("TASK_PANEL_UNAVAILABLE", "the agent's background tasks panel could not be driven")
	case errors.Is(err, domain.ErrTaskAwaitingDecision):
		conflict("SESSION_AWAITING_DECISION", "the session is paused on a permission decision")
	case errors.Is(err, domain.ErrTaskComposerNotEmpty):
		conflict("SESSION_COMPOSER_NOT_EMPTY", "the terminal composer holds an unsent draft")
	case errors.Is(err, domain.ErrTaskSessionBusy):
		conflict("SESSION_BUSY", "another operation owns the session's terminal")
	case errors.Is(err, domain.ErrTaskSessionNotRunning):
		conflict("SESSION_NOT_RUNNING", "the session is not running")
	default:
		envelope.WriteError(w, r, err)
	}
}

func sessionTaskView(task backgroundtask.Task) SessionTaskView {
	return SessionTaskView{
		TaskID:      task.TaskID,
		Kind:        string(task.Kind),
		Status:      string(task.Status),
		ToolUseID:   task.ToolUseID,
		Description: task.Description,
		Command:     task.Command,
		Summary:     task.Summary,
		ExitCode:    task.ExitCode,
		DurationMs:  task.DurationMs,
		OutputFile:  task.OutputFile,
		StartedAt:   task.StartedAt,
		EndedAt:     task.EndedAt,
		AgentID:     task.AgentID,
		CanStop:     task.CanStop,
		UpdatedSeq:  task.UpdatedSeq,
	}
}
