package controllers_test

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	browsersvc "github.com/OmarAly92/operator/backend/internal/service/browser"
)

type fakeBrowserRuntime struct {
	status browsersvc.RuntimeStatus
	action string
	args   map[string]interface{}
	err    error
}

func (f *fakeBrowserRuntime) Status(_ context.Context, _ domain.SessionID, _ string) (browsersvc.RuntimeStatus, error) {
	return f.status, nil
}

func (f *fakeBrowserRuntime) Execute(
	_ context.Context,
	_ domain.SessionID,
	_ string,
	action string,
	args map[string]interface{},
) (browsersvc.RuntimeResult, string, error) {
	f.action, f.args = action, args
	if action == "eval" {
		return browsersvc.RuntimeResult{}, action, apierr.Invalid(
			"BROWSER_ACTION_UNSUPPORTED",
			"Unsupported browser action",
			nil,
		)
	}
	if f.err != nil {
		return browsersvc.RuntimeResult{}, action, f.err
	}
	return browsersvc.RuntimeResult{RequestID: "request-1", Value: map[string]interface{}{"text": "button Save [ref=e1]"}}, action, nil
}

func browserServer(t *testing.T, runtime *fakeBrowserRuntime) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{
		Sessions: newFakeSessionService(),
		Browser:  runtime,
	}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestBrowserStatusAndSnapshot(t *testing.T) {
	readyAt := time.Now().UTC().Truncate(time.Second)
	runtime := &fakeBrowserRuntime{status: browsersvc.RuntimeStatus{Ready: true, ReadyAt: readyAt}}
	srv := browserServer(t, runtime)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/browser/status?sessionId=opr-1", "")
	if status != http.StatusOK || !containsAll(body, `"connected":true`, `"transport":"agent-browser-standalone"`) {
		t.Fatalf("status = %d body=%s", status, body)
	}
	body, status, _ = doRequest(t, srv, http.MethodPost, "/api/v1/browser/commands", `{"sessionId":"opr-1","action":"snapshot","args":{"interactive":true}}`)
	if status != http.StatusOK || !containsAll(body, `"requestId":"request-1"`, `"button Save [ref=e1]"`) {
		t.Fatalf("command = %d body=%s", status, body)
	}
	if runtime.action != "snapshot" || runtime.args["interactive"] != true {
		t.Fatalf("runtime command = %q %#v", runtime.action, runtime.args)
	}
}

func TestBrowserStatusReportsDisconnectedWithoutReadyRuntime(t *testing.T) {
	runtime := &fakeBrowserRuntime{}
	srv := browserServer(t, runtime)
	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/browser/status?sessionId=opr-1", "")
	if status != http.StatusOK || !containsAll(body, `"connected":false`) {
		t.Fatalf("status = %d body=%s", status, body)
	}
}

func TestBrowserCoreInteractionActionsReachRuntime(t *testing.T) {
	runtime := &fakeBrowserRuntime{}
	srv := browserServer(t, runtime)
	actions := []string{
		"type", "press", "hover", "highlight", "unhighlight",
		"tabs", "tab-new", "tab-select", "tab-close",
		"scroll", "select", "check", "uncheck", "get",
		"network-start", "network-status", "network-list", "network-stop", "network-clear",
		"devtools-open", "devtools-close",
	}

	for _, action := range actions {
		t.Run(action, func(t *testing.T) {
			body, status, _ := doRequest(
				t,
				srv,
				http.MethodPost,
				"/api/v1/browser/commands",
				`{"sessionId":"opr-1","action":"`+action+`","args":{"probe":true}}`,
			)
			if status != http.StatusOK {
				t.Fatalf("%s = %d body=%s", action, status, body)
			}
			if runtime.action != action || runtime.args["probe"] != true {
				t.Fatalf("runtime command = %q %#v", runtime.action, runtime.args)
			}
		})
	}
}

func TestBrowserCommandValidationAndErrors(t *testing.T) {
	runtime := &fakeBrowserRuntime{}
	srv := browserServer(t, runtime)

	body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/browser/commands", `{"sessionId":"opr-1","action":"eval"}`)
	if status != http.StatusBadRequest || !containsAll(body, `"code":"BROWSER_ACTION_UNSUPPORTED"`) {
		t.Fatalf("unsupported = %d body=%s", status, body)
	}
	runtime.err = browsersvc.ErrUnavailable
	body, status, _ = doRequest(t, srv, http.MethodPost, "/api/v1/browser/commands", `{"sessionId":"opr-1","action":"snapshot"}`)
	if status != http.StatusServiceUnavailable || !containsAll(body, `"code":"BROWSER_RUNTIME_UNAVAILABLE"`) {
		t.Fatalf("unavailable = %d body=%s", status, body)
	}
	runtime.err = browsersvc.CommandError{Code: "STALE_REFERENCE", Message: "snapshot again"}
	body, status, _ = doRequest(t, srv, http.MethodPost, "/api/v1/browser/commands", `{"sessionId":"opr-1","action":"click"}`)
	if status != http.StatusConflict || !containsAll(body, `"code":"STALE_REFERENCE"`) {
		t.Fatalf("stale = %d body=%s", status, body)
	}
	runtime.err = browsersvc.CommandError{Code: "AGENT_BROWSER_NOT_INSTALLED", Message: "missing"}
	body, status, _ = doRequest(t, srv, http.MethodPost, "/api/v1/browser/commands", `{"sessionId":"opr-1","action":"click"}`)
	if status != http.StatusServiceUnavailable || !containsAll(body, `"code":"AGENT_BROWSER_NOT_INSTALLED"`) {
		t.Fatalf("not installed = %d body=%s", status, body)
	}
	runtime.err = browsersvc.CommandError{Code: "AGENT_BROWSER_INSTALL_FAILED", Message: "offline"}
	body, status, _ = doRequest(t, srv, http.MethodPost, "/api/v1/browser/commands", `{"sessionId":"opr-1","action":"click"}`)
	if status != http.StatusServiceUnavailable || !containsAll(body, `"code":"AGENT_BROWSER_INSTALL_FAILED"`) {
		t.Fatalf("install failed = %d body=%s", status, body)
	}
}

func containsAll(body []byte, parts ...string) bool {
	value := string(body)
	for _, part := range parts {
		if !strings.Contains(value, part) {
			return false
		}
	}
	return true
}
