package controllers_test

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	"github.com/OmarAly92/operator/backend/internal/service/backgroundtask"
)

type fakeBackgroundTasks struct {
	tasks      []backgroundtask.Task
	listErr    error
	outcome    backgroundtask.StopOutcome
	stopErr    error
	gotSession domain.SessionID
	gotTask    string
}

func (f *fakeBackgroundTasks) List(_ context.Context, id domain.SessionID) ([]backgroundtask.Task, error) {
	f.gotSession = id
	return f.tasks, f.listErr
}

func (f *fakeBackgroundTasks) Stop(_ context.Context, id domain.SessionID, taskID string) (backgroundtask.StopOutcome, error) {
	f.gotSession, f.gotTask = id, taskID
	return f.outcome, f.stopErr
}

func newTasksTestServer(t *testing.T, tasks *fakeBackgroundTasks) *httptest.Server {
	t.Helper()
	deps := httpd.APIDeps{Activity: noopActivityRecorder{}, UsageHooks: noopUsageHookRecorder{}}
	if tasks != nil {
		deps.BackgroundTasks = tasks
	}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, slog.New(slog.NewTextHandler(io.Discard, nil)), nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestListSessionTasks(t *testing.T) {
	code := 0
	duration := int64(7412)
	tasks := &fakeBackgroundTasks{tasks: []backgroundtask.Task{
		{BackgroundTask: domain.BackgroundTask{
			TaskID: "a1", Kind: domain.BackgroundTaskAgent, Status: domain.BackgroundTaskRunning,
			ToolUseID: "toolu_2", Description: "sleeper", StartedAt: "2026-09-25T00:54:02.000Z",
		}, CanStop: true, UpdatedSeq: 12},
		{BackgroundTask: domain.BackgroundTask{
			TaskID: "b1", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskCompleted,
			ToolUseID: "toolu_1", Description: "Nap", Command: "sleep 1", Summary: "done", ExitCode: &code,
			DurationMs: &duration, OutputFile: "/tmp/tasks/b1.output",
			StartedAt: "2026-09-25T00:54:00.000Z", EndedAt: "2026-09-25T00:54:01.000Z",
		}, AgentID: "a7", UpdatedSeq: 9},
	}}
	srv := newTasksTestServer(t, tasks)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/tasks", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d: %s", status, body)
	}
	var raw map[string][]map[string]any
	if err := json.Unmarshal(body, &raw); err != nil {
		t.Fatal(err)
	}
	agent, shell := raw["tasks"][0], raw["tasks"][1]
	if agent["taskId"] != "a1" || agent["kind"] != "agent" || agent["canStop"] != true || agent["status"] != "running" {
		t.Fatalf("agent = %+v", agent)
	}
	if _, has := agent["exitCode"]; has {
		t.Fatalf("running agent carries an exit code: %+v", agent)
	}
	if shell["exitCode"] != float64(0) || shell["durationMs"] != float64(7412) || shell["canStop"] != false ||
		shell["command"] != "sleep 1" || shell["endedAt"] != "2026-09-25T00:54:01.000Z" || shell["updatedSeq"] != float64(9) || shell["agentId"] != "a7" {
		t.Fatalf("shell = %+v", shell)
	}
	if tasks.gotSession != "s-1" {
		t.Fatalf("session = %q", tasks.gotSession)
	}
}

func TestListSessionTasksErrors(t *testing.T) {
	srv := newTasksTestServer(t, &fakeBackgroundTasks{listErr: backgroundtask.ErrSessionNotFound})
	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/tasks", "")
	assertEnvelope(t, body, status, http.StatusNotFound, "SESSION_NOT_FOUND")

	unwired := newTasksTestServer(t, nil)
	_, status, _ = doRequest(t, unwired, http.MethodGet, "/api/v1/sessions/s-1/tasks", "")
	if status != http.StatusNotImplemented {
		t.Fatalf("unwired status = %d", status)
	}
}

func TestStopSessionTaskShellIsAccepted(t *testing.T) {
	tasks := &fakeBackgroundTasks{outcome: backgroundtask.StopOutcome{Task: backgroundtask.Task{BackgroundTask: domain.BackgroundTask{
		TaskID: "b1", Kind: domain.BackgroundTaskShell, Status: domain.BackgroundTaskRunning,
	}, CanStop: true}}}
	srv := newTasksTestServer(t, tasks)
	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s-1/tasks/b1/stop", "")
	if status != http.StatusAccepted {
		t.Fatalf("status = %d: %s", status, body)
	}
	var got controllers.StopSessionTaskResponse
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatal(err)
	}
	if got.Confirmed || got.Task.TaskID != "b1" || tasks.gotTask != "b1" || tasks.gotSession != "s-1" {
		t.Fatalf("response = %+v, got %q/%q", got, tasks.gotSession, tasks.gotTask)
	}
}

func TestStopSessionTaskAgentConfirmed(t *testing.T) {
	tasks := &fakeBackgroundTasks{outcome: backgroundtask.StopOutcome{Confirmed: true, Task: backgroundtask.Task{BackgroundTask: domain.BackgroundTask{
		TaskID: "a1", Kind: domain.BackgroundTaskAgent, Status: domain.BackgroundTaskKilled,
	}}}}
	srv := newTasksTestServer(t, tasks)
	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s-1/tasks/a1/stop", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d: %s", status, body)
	}
	var got controllers.StopSessionTaskResponse
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatal(err)
	}
	if !got.Confirmed || got.Task.Status != "killed" {
		t.Fatalf("response = %+v", got)
	}
}

func TestStopSessionTaskErrorEnvelopes(t *testing.T) {
	for _, tc := range []struct {
		err    error
		status int
		code   string
	}{
		{domain.ErrTaskSessionNotFound, http.StatusNotFound, "SESSION_NOT_FOUND"},
		{domain.ErrTaskNotFound, http.StatusNotFound, "TASK_NOT_FOUND"},
		{domain.ErrTaskProcessNotFound, http.StatusNotFound, "TASK_NOT_FOUND"},
		{domain.ErrTaskFinished, http.StatusConflict, "TASK_FINISHED"},
		{domain.ErrTaskAmbiguous, http.StatusConflict, "TASK_AMBIGUOUS"},
		{domain.ErrTaskUnsafe, http.StatusConflict, "TASK_UNSAFE"},
		{domain.ErrTaskStopUnsupported, http.StatusUnprocessableEntity, "TASK_STOP_UNSUPPORTED"},
		{domain.ErrTaskStopUnconfirmed, http.StatusGatewayTimeout, "TASK_STOP_UNCONFIRMED"},
		{fmt.Errorf("wrapped: %w", domain.ErrTaskPanelUnavailable), http.StatusConflict, "TASK_PANEL_UNAVAILABLE"},
		{domain.ErrTaskAwaitingDecision, http.StatusConflict, "SESSION_AWAITING_DECISION"},
		{domain.ErrTaskComposerNotEmpty, http.StatusConflict, "SESSION_COMPOSER_NOT_EMPTY"},
		{domain.ErrTaskSessionBusy, http.StatusConflict, "SESSION_BUSY"},
		{domain.ErrTaskSessionNotRunning, http.StatusConflict, "SESSION_NOT_RUNNING"},
	} {
		srv := newTasksTestServer(t, &fakeBackgroundTasks{stopErr: tc.err})
		body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s-1/tasks/b1/stop", "")
		assertEnvelope(t, body, status, tc.status, tc.code)
	}
}

func assertEnvelope(t *testing.T, body []byte, status, wantStatus int, wantCode string) {
	t.Helper()
	if status != wantStatus {
		t.Fatalf("status = %d want %d: %s", status, wantStatus, body)
	}
	var apiErr envelope.APIError
	if err := json.Unmarshal(body, &apiErr); err != nil {
		t.Fatalf("decode envelope: %v", err)
	}
	if apiErr.Code != wantCode || apiErr.Error == "" || apiErr.Message == "" || apiErr.RequestID == "" {
		t.Fatalf("envelope = %+v want code %s", apiErr, wantCode)
	}
}
