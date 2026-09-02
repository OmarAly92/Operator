package controllers

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	shelltermsvc "github.com/OmarAly92/operator/backend/internal/service/shellterm"
)

const (
	defaultShellTerminalBlockLimit = 100
	maxShellTerminalBlockLimit     = 500
)

// ShellTerminalService is the controller-facing standalone shell terminal
// contract.
type ShellTerminalService interface {
	OpenShellTerminal(ctx context.Context, in shelltermsvc.OpenShellTerminalInput) (shelltermsvc.ShellTerminal, error)
	ListShellTerminalsForCurrentAppRun(ctx context.Context) ([]shelltermsvc.ShellTerminal, error)
	RenameShellTerminal(ctx context.Context, handleID, title string) (shelltermsvc.ShellTerminal, error)
	CloseShellTerminal(ctx context.Context, handleID string) error
}

type ShellTerminalBlockHistory interface {
	History(ctx context.Context, terminalID string, limit int) ([]domain.Block, error)
}

// ShellTerminalsController owns the /shell-terminals routes: standalone shells
// the user opens by hand, independent of any agent session.
type ShellTerminalsController struct {
	Svc    ShellTerminalService
	Blocks ShellTerminalBlockHistory
}

// Register mounts the bounded shell terminal REST routes.
func (c *ShellTerminalsController) Register(r chi.Router) {
	r.Get("/shell-terminals", c.list)
	r.Post("/shell-terminals", c.open)
	r.Patch("/shell-terminals/{handleId}", c.rename)
	r.Delete("/shell-terminals/{handleId}", c.close)
	r.Get("/shell-terminals/{handleId}/blocks", c.blocks)
}

func (c *ShellTerminalsController) list(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/shell-terminals")
		return
	}
	terminals, err := c.Svc.ListShellTerminalsForCurrentAppRun(r.Context())
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, ListShellTerminalsResponse{
		ShellTerminals: shellTerminalResponses(terminals),
	})
}

func (c *ShellTerminalsController) open(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/shell-terminals")
		return
	}
	// An empty body is a valid request: it means "open a shell with no project
	// context", which the service resolves to the daemon data dir.
	var req OpenShellTerminalRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	terminal, err := c.Svc.OpenShellTerminal(r.Context(), shelltermsvc.OpenShellTerminalInput{
		ProjectID: domain.ProjectID(req.ProjectID),
	})
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusCreated, ShellTerminalEnvelope{
		ShellTerminal: shellTerminalResponse(terminal),
	})
}

func (c *ShellTerminalsController) rename(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "PATCH", "/api/v1/shell-terminals/{handleId}")
		return
	}
	var req UpdateShellTerminalRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	terminal, err := c.Svc.RenameShellTerminal(r.Context(), chi.URLParam(r, "handleId"), req.Title)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, ShellTerminalEnvelope{
		ShellTerminal: shellTerminalResponse(terminal),
	})
}

func (c *ShellTerminalsController) close(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "DELETE", "/api/v1/shell-terminals/{handleId}")
		return
	}
	if err := c.Svc.CloseShellTerminal(r.Context(), chi.URLParam(r, "handleId")); err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (c *ShellTerminalsController) blocks(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil || c.Blocks == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/shell-terminals/{handleId}/blocks")
		return
	}
	handleID := chi.URLParam(r, "handleId")

	limit, ok := parseShellTerminalBlockLimit(w, r)
	if !ok {
		return
	}

	terminals, err := c.Svc.ListShellTerminalsForCurrentAppRun(r.Context())
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	known := false
	for _, t := range terminals {
		if t.HandleID == handleID {
			known = true
			break
		}
	}
	if !known {
		envelope.WriteAPIError(w, r, http.StatusNotFound, "not_found", "SHELL_TERMINAL_NOT_FOUND", "No such shell terminal: "+handleID, nil)
		return
	}

	blocks, err := c.Blocks.History(r.Context(), handleID, limit)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, terminalBlockViews(blocks))
}

func parseShellTerminalBlockLimit(w http.ResponseWriter, r *http.Request) (int, bool) {
	raw := strings.TrimSpace(r.URL.Query().Get("limit"))
	if raw == "" {
		return defaultShellTerminalBlockLimit, true
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n < 1 || n > maxShellTerminalBlockLimit {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_QUERY", "limit must be an integer between 1 and 500", nil)
		return 0, false
	}
	return n, true
}

func terminalBlockViews(blocks []domain.Block) []TerminalBlockView {
	out := make([]TerminalBlockView, 0, len(blocks))
	for _, b := range blocks {
		out = append(out, terminalBlockView(b))
	}
	return out
}

func terminalBlockView(b domain.Block) TerminalBlockView {
	var exitCode *int
	if b.ExitCode != nil {
		v := *b.ExitCode
		exitCode = &v
	}
	return TerminalBlockView{
		TerminalID:     b.TerminalID,
		SourceID:       b.SourceID,
		SessionID:      b.SessionID,
		Command:        b.Command,
		Cwd:            b.Cwd,
		GitBranch:      b.GitBranch,
		ExitCode:       exitCode,
		RawOutput:      base64.StdEncoding.EncodeToString(b.RawOutput),
		StartedAt:      b.StartedAt,
		FinishedAt:     b.FinishedAt,
		CreatedAt:      b.CreatedAt,
		ShellKind:      b.ShellKind,
		ShellVersion:   b.ShellVersion,
		TruncatedLines: b.TruncatedLines,
		TruncatedBytes: b.TruncatedBytes,
		CaptureEpoch:   b.CaptureEpoch,
		StartOffset:    b.StartOffset,
		EndOffset:      b.EndOffset,
	}
}

func shellTerminalResponses(in []shelltermsvc.ShellTerminal) []ShellTerminalResponse {
	out := make([]ShellTerminalResponse, 0, len(in))
	for _, t := range in {
		out = append(out, shellTerminalResponse(t))
	}
	return out
}

func shellTerminalResponse(t shelltermsvc.ShellTerminal) ShellTerminalResponse {
	return ShellTerminalResponse{
		HandleID:      t.HandleID,
		ProjectID:     string(t.ProjectID),
		WorkingDir:    t.WorkingDir,
		Title:         t.Title,
		CreatedAt:     t.CreatedAt,
		DurableBlocks: t.DurableBlocks,
	}
}
