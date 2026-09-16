package controllers

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode/claudesetup"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	claudeaccountssvc "github.com/OmarAly92/operator/backend/internal/service/claudeaccounts"
	shelltermsvc "github.com/OmarAly92/operator/backend/internal/service/shellterm"
)

type ClaudeAccountService interface {
	List(ctx context.Context, refresh bool) ([]claudeaccountssvc.AccountView, error)
	Create(ctx context.Context, label string) (domain.ClaudeAccount, error)
	Rename(ctx context.Context, id domain.ClaudeAccountID, label string) (domain.ClaudeAccount, error)
	Delete(ctx context.Context, id domain.ClaudeAccountID) error
	SetPreferred(ctx context.Context, id domain.ClaudeAccountID) (domain.ClaudeAccount, error)
	Relink(ctx context.Context, id domain.ClaudeAccountID) (claudesetup.Report, error)
	Login(ctx context.Context, id domain.ClaudeAccountID) (claudeaccountssvc.LoginLaunch, error)
}

type ClaudeAccountsController struct {
	Svc       ClaudeAccountService
	Terminals ShellTerminalService
}

func (c *ClaudeAccountsController) Register(r chi.Router) {
	r.Get("/claude-accounts", c.list)
	r.Post("/claude-accounts", c.create)
	r.Patch("/claude-accounts/{accountId}", c.rename)
	r.Delete("/claude-accounts/{accountId}", c.remove)
	r.Post("/claude-accounts/{accountId}/login", c.login)
	r.Post("/claude-accounts/{accountId}/relink", c.relink)
	r.Post("/claude-accounts/{accountId}/prefer", c.prefer)
}

func claudeAccountID(r *http.Request) domain.ClaudeAccountID {
	return domain.ClaudeAccountID(strings.TrimSpace(chi.URLParam(r, "accountId")))
}

func claudeAccountAPIError(err error) error {
	switch {
	case errors.Is(err, domain.ErrClaudeAccountExists):
		return apierr.Conflict("CLAUDE_ACCOUNT_EXISTS", "A Claude account with that name or folder already exists", nil)
	case errors.Is(err, domain.ErrClaudeAccountLabelInvalid):
		return apierr.Invalid("CLAUDE_ACCOUNT_LABEL_INVALID", "Account names need 1–32 characters including a letter or digit", nil)
	case errors.Is(err, domain.ErrClaudeAccountNotFound):
		return apierr.NotFound("CLAUDE_ACCOUNT_NOT_FOUND", "Unknown Claude account")
	case errors.Is(err, domain.ErrClaudeAccountDefaultImmutable):
		return apierr.Conflict("CLAUDE_ACCOUNT_DEFAULT_IMMUTABLE", "The default Claude account cannot be removed", nil)
	case errors.Is(err, domain.ErrClaudeAccountInUse):
		return apierr.Conflict("CLAUDE_ACCOUNT_IN_USE", "Sessions still use this account; remove or switch them first", nil)
	case errors.Is(err, domain.ErrClaudeAccountFolderUnavailable):
		return apierr.Conflict("CLAUDE_ACCOUNT_FOLDER_UNAVAILABLE", "The account folder is missing or cannot be created", nil)
	default:
		return err
	}
}

func claudeAccountView(view claudeaccountssvc.AccountView) ClaudeAccountView {
	status := ClaudeAccountStatus{
		LoggedIn:         view.Status.LoggedIn,
		SubscriptionType: view.Status.SubscriptionType,
		ReportedEmail:    view.Status.ReportedEmail,
	}
	if !view.Status.CheckedAt.IsZero() {
		checked := view.Status.CheckedAt
		status.CheckedAt = &checked
	}
	setup := make(map[string]string, len(view.SharedSetup))
	for name, state := range view.SharedSetup {
		setup[name] = string(state)
	}
	configDir := view.ConfigDir
	if configDir == "" {
		configDir = view.Account.ConfigDir
	}
	return ClaudeAccountView{
		ID:          view.Account.ID,
		Label:       view.Account.Label,
		ConfigDir:   configDir,
		IsDefault:   view.Account.IsDefault,
		IsPreferred: view.Account.IsPreferred,
		Status:      status,
		SharedSetup: setup,
	}
}

func decodeOptionalJSON(r *http.Request, out any) error {
	err := json.NewDecoder(r.Body).Decode(out)
	if errors.Is(err, io.EOF) {
		return nil
	}
	return err
}

func (c *ClaudeAccountsController) list(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/claude-accounts")
		return
	}
	views, err := c.Svc.List(r.Context(), r.URL.Query().Get("refresh") == "1")
	if err != nil {
		envelope.WriteError(w, r, claudeAccountAPIError(err))
		return
	}
	out := make([]ClaudeAccountView, 0, len(views))
	for _, view := range views {
		out = append(out, claudeAccountView(view))
	}
	envelope.WriteJSON(w, http.StatusOK, ListClaudeAccountsResponse{Accounts: out})
}

func (c *ClaudeAccountsController) create(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/claude-accounts")
		return
	}
	var in CreateClaudeAccountRequest
	if err := decodeOptionalJSON(r, &in); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	account, err := c.Svc.Create(r.Context(), in.Label)
	if err != nil {
		envelope.WriteError(w, r, claudeAccountAPIError(err))
		return
	}
	envelope.WriteJSON(w, http.StatusCreated, ClaudeAccountEnvelope{Account: claudeAccountView(claudeaccountssvc.AccountView{Account: account})})
}

func (c *ClaudeAccountsController) rename(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "PATCH", "/api/v1/claude-accounts/{accountId}")
		return
	}
	var in RenameClaudeAccountRequest
	if err := decodeOptionalJSON(r, &in); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	account, err := c.Svc.Rename(r.Context(), claudeAccountID(r), in.Label)
	if err != nil {
		envelope.WriteError(w, r, claudeAccountAPIError(err))
		return
	}
	envelope.WriteJSON(w, http.StatusOK, ClaudeAccountEnvelope{Account: claudeAccountView(claudeaccountssvc.AccountView{Account: account})})
}

func (c *ClaudeAccountsController) remove(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "DELETE", "/api/v1/claude-accounts/{accountId}")
		return
	}
	if err := c.Svc.Delete(r.Context(), claudeAccountID(r)); err != nil {
		envelope.WriteError(w, r, claudeAccountAPIError(err))
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (c *ClaudeAccountsController) prefer(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/claude-accounts/{accountId}/prefer")
		return
	}
	account, err := c.Svc.SetPreferred(r.Context(), claudeAccountID(r))
	if err != nil {
		envelope.WriteError(w, r, claudeAccountAPIError(err))
		return
	}
	envelope.WriteJSON(w, http.StatusOK, ClaudeAccountEnvelope{Account: claudeAccountView(claudeaccountssvc.AccountView{Account: account})})
}

func (c *ClaudeAccountsController) relink(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/claude-accounts/{accountId}/relink")
		return
	}
	if _, err := c.Svc.Relink(r.Context(), claudeAccountID(r)); err != nil {
		envelope.WriteError(w, r, claudeAccountAPIError(err))
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (c *ClaudeAccountsController) login(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil || c.Terminals == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/claude-accounts/{accountId}/login")
		return
	}
	var in ClaudeAccountLoginRequest
	if err := decodeOptionalJSON(r, &in); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	launch, err := c.Svc.Login(r.Context(), claudeAccountID(r))
	if err != nil {
		envelope.WriteError(w, r, claudeAccountAPIError(err))
		return
	}
	terminal, err := c.Terminals.OpenShellTerminal(r.Context(), shelltermsvc.OpenShellTerminalInput{
		Cols:  in.Cols,
		Rows:  in.Rows,
		Argv:  launch.Argv,
		Env:   launch.Env,
		Title: launch.Title,
	})
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusCreated, ShellTerminalEnvelope{ShellTerminal: shellTerminalResponse(terminal)})
}
