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
	browsersvc "github.com/OmarAly92/operator/backend/internal/service/browser"
)

const (
	browserCapabilityHeader = "X-Operator-Browser-Capability"
	browserTransport        = "agent-browser-standalone"
)

// BrowserService authorizes and executes session-scoped browser operations
// through the adapter-neutral runtime contract.
type BrowserService interface {
	Status(ctx context.Context, sessionID domain.SessionID, capability string) (browsersvc.RuntimeStatus, error)
	Execute(ctx context.Context, sessionID domain.SessionID, capability, action string, args map[string]interface{}) (browsersvc.RuntimeResult, string, error)
}

// BrowserController exposes the loopback-only browser command API.
type BrowserController struct {
	Svc BrowserService
}

// Register adds browser status and command routes to the API router.
func (c *BrowserController) Register(r chi.Router) {
	r.Get("/browser/status", c.status)
	r.Post("/browser/commands", c.execute)
}

func (c *BrowserController) status(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, http.MethodGet, "/api/v1/browser/status")
		return
	}
	sessionID := domain.SessionID(strings.TrimSpace(r.URL.Query().Get("sessionId")))
	if sessionID == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "SESSION_ID_REQUIRED", "sessionId is required", nil)
		return
	}
	status, err := c.Svc.Status(r.Context(), sessionID, r.Header.Get(browserCapabilityHeader))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, BrowserStatusResponse{
		SessionID:   sessionID,
		Connected:   status.Ready,
		ConnectedAt: status.ReadyAt,
		Transport:   browserTransport,
	})
}

func (c *BrowserController) execute(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, http.MethodPost, "/api/v1/browser/commands")
		return
	}
	var in BrowserCommandRequest
	if err := decodeJSON(r, &in); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	if in.SessionID == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "SESSION_ID_REQUIRED", "sessionId is required", nil)
		return
	}
	result, action, err := c.Svc.Execute(
		r.Context(),
		in.SessionID,
		r.Header.Get(browserCapabilityHeader),
		in.Action,
		in.Args,
	)
	if err != nil {
		writeBrowserError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, BrowserCommandResponse{
		RequestID: result.RequestID,
		SessionID: in.SessionID,
		Action:    action,
		Result:    result.Value,
	})
}

func writeBrowserError(w http.ResponseWriter, r *http.Request, err error) {
	if errors.Is(err, browsersvc.ErrUnavailable) {
		envelope.WriteAPIError(w, r, http.StatusServiceUnavailable, "unavailable", "BROWSER_RUNTIME_UNAVAILABLE", "Browser automation runtime is not available", nil)
		return
	}
	var commandErr browsersvc.CommandError
	if errors.As(err, &commandErr) {
		status := http.StatusUnprocessableEntity
		typeName := "unprocessable"
		switch commandErr.Code {
		case "INVALID_ARGUMENT", "URL_REQUIRED", "REFERENCE_REQUIRED", "TAB_ID_REQUIRED",
			"AGENT_BROWSER_COMMAND_BLOCKED":
			status = http.StatusBadRequest
			typeName = "bad_request"
		case "STALE_REFERENCE", "TAB_NOT_FOUND":
			status = http.StatusConflict
			typeName = "conflict"
		case "BROWSER_TARGET_UNAVAILABLE", "BROWSER_AUTOMATION_UNAVAILABLE", "AGENT_BROWSER_NOT_INSTALLED",
			"AGENT_BROWSER_START_FAILED", "AGENT_BROWSER_INSTALL_FAILED", "AGENT_BROWSER_TIMEOUT",
			"BROWSER_DEVTOOLS_UNAVAILABLE":
			status = http.StatusServiceUnavailable
			typeName = "unavailable"
		case "AGENT_BROWSER_CANCELLED":
			status = http.StatusRequestTimeout
			typeName = "timeout"
		case "AGENT_BROWSER_OUTPUT_TOO_LARGE", "AGENT_BROWSER_INVALID_OUTPUT":
			status = http.StatusUnprocessableEntity
			typeName = "unprocessable"
		}
		envelope.WriteAPIError(w, r, status, typeName, commandErr.Code, commandErr.Message, nil)
		return
	}
	envelope.WriteError(w, r, err)
}
