package controllers_test

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode/claudesetup"
	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	claudeaccountssvc "github.com/OmarAly92/operator/backend/internal/service/claudeaccounts"
	shelltermsvc "github.com/OmarAly92/operator/backend/internal/service/shellterm"
)

type fakeClaudeAccountService struct {
	created    string
	deleteErr  error
	createErr  error
	refreshed  bool
	loginInput domain.ClaudeAccountID
}

func (f *fakeClaudeAccountService) List(_ context.Context, refresh bool) ([]claudeaccountssvc.AccountView, error) {
	f.refreshed = refresh
	yes := true
	return []claudeaccountssvc.AccountView{
		{Account: domain.ClaudeAccount{ID: "default", Label: "Default", IsDefault: true}, ConfigDir: "/Users/u/.claude", SharedSetup: claudesetup.Report{}},
		{
			Account:     domain.ClaudeAccount{ID: "personal", Label: "Personal", ConfigDir: "/Users/u/.claude-personal"},
			ConfigDir:   "/Users/u/.claude-personal",
			Status:      claudeaccountssvc.AuthStatus{LoggedIn: &yes, SubscriptionType: "pro"},
			SharedSetup: claudesetup.Report{"settings.json": claudesetup.ItemReplaced},
		},
	}, nil
}

func (f *fakeClaudeAccountService) Create(_ context.Context, label string) (domain.ClaudeAccount, error) {
	f.created = label
	if f.createErr != nil {
		return domain.ClaudeAccount{}, f.createErr
	}
	return domain.ClaudeAccount{ID: "personal", Label: label, ConfigDir: "/Users/u/.claude-personal"}, nil
}

func (f *fakeClaudeAccountService) Rename(_ context.Context, id domain.ClaudeAccountID, label string) (domain.ClaudeAccount, error) {
	return domain.ClaudeAccount{ID: id, Label: label, ConfigDir: "/Users/u/.claude-personal"}, nil
}

func (f *fakeClaudeAccountService) Delete(context.Context, domain.ClaudeAccountID) error {
	return f.deleteErr
}

func (f *fakeClaudeAccountService) Relink(context.Context, domain.ClaudeAccountID) (claudesetup.Report, error) {
	return claudesetup.Report{"settings.json": claudesetup.ItemLinked}, nil
}

func (f *fakeClaudeAccountService) Login(_ context.Context, id domain.ClaudeAccountID) (claudeaccountssvc.LoginLaunch, error) {
	f.loginInput = id
	return claudeaccountssvc.LoginLaunch{
		Account: domain.ClaudeAccount{ID: id, Label: "Personal"},
		Argv:    []string{"/usr/local/bin/claude"},
		Env:     map[string]string{domain.ClaudeConfigDirEnv: "/Users/u/.claude-personal"},
		Title:   "Claude login · Personal",
	}, nil
}

type fakeLoginTerminals struct {
	controllers.ShellTerminalService
	got shelltermsvc.OpenShellTerminalInput
}

func (f *fakeLoginTerminals) OpenShellTerminal(_ context.Context, in shelltermsvc.OpenShellTerminalInput) (shelltermsvc.ShellTerminal, error) {
	f.got = in
	return shelltermsvc.ShellTerminal{HandleID: "shellterm-abc", WorkingDir: "/tmp", Title: in.Title}, nil
}

func newClaudeAccountsTestServer(t *testing.T, svc controllers.ClaudeAccountService, terms controllers.ShellTerminalService) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{ClaudeAccounts: svc, ShellTerminals: terms}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestClaudeAccountsList(t *testing.T) {
	svc := &fakeClaudeAccountService{}
	srv := newClaudeAccountsTestServer(t, svc, nil)
	body, status, _ := doRequest(t, srv, "GET", "/api/v1/claude-accounts?refresh=1", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d body=%s", status, body)
	}
	var resp controllers.ListClaudeAccountsResponse
	mustJSON(t, body, &resp)
	if !svc.refreshed || len(resp.Accounts) != 2 {
		t.Fatalf("refreshed=%v resp=%+v", svc.refreshed, resp)
	}
	personal := resp.Accounts[1]
	if personal.Status.LoggedIn == nil || !*personal.Status.LoggedIn || personal.Status.SubscriptionType != "pro" || personal.SharedSetup["settings.json"] != "replaced" {
		t.Fatalf("personal = %+v", personal)
	}
	if resp.Accounts[0].Status.LoggedIn != nil {
		t.Fatalf("unknown status should be null: %+v", resp.Accounts[0].Status)
	}
}

func TestClaudeAccountsCreateAndErrors(t *testing.T) {
	svc := &fakeClaudeAccountService{}
	srv := newClaudeAccountsTestServer(t, svc, nil)
	body, status, _ := doRequest(t, srv, "POST", "/api/v1/claude-accounts", `{"label":"Personal"}`)
	if status != http.StatusCreated || svc.created != "Personal" {
		t.Fatalf("status = %d created=%q body=%s", status, svc.created, body)
	}

	cases := []struct {
		err    error
		status int
		code   string
	}{
		{domain.ErrClaudeAccountExists, http.StatusConflict, "CLAUDE_ACCOUNT_EXISTS"},
		{domain.ErrClaudeAccountLabelInvalid, http.StatusBadRequest, "CLAUDE_ACCOUNT_LABEL_INVALID"},
		{domain.ErrClaudeAccountFolderUnavailable, http.StatusConflict, "CLAUDE_ACCOUNT_FOLDER_UNAVAILABLE"},
	}
	for _, tc := range cases {
		svc.createErr = tc.err
		body, status, _ := doRequest(t, srv, "POST", "/api/v1/claude-accounts", `{"label":"X"}`)
		var env struct {
			Code string `json:"code"`
		}
		mustJSON(t, body, &env)
		if status != tc.status || env.Code != tc.code {
			t.Errorf("%v -> status %d code %q, want %d %q", tc.err, status, env.Code, tc.status, tc.code)
		}
	}
}

func TestClaudeAccountsDeleteErrors(t *testing.T) {
	cases := []struct {
		err    error
		status int
		code   string
	}{
		{nil, http.StatusNoContent, ""},
		{domain.ErrClaudeAccountInUse, http.StatusConflict, "CLAUDE_ACCOUNT_IN_USE"},
		{domain.ErrClaudeAccountDefaultImmutable, http.StatusConflict, "CLAUDE_ACCOUNT_DEFAULT_IMMUTABLE"},
		{domain.ErrClaudeAccountNotFound, http.StatusNotFound, "CLAUDE_ACCOUNT_NOT_FOUND"},
	}
	for _, tc := range cases {
		srv := newClaudeAccountsTestServer(t, &fakeClaudeAccountService{deleteErr: tc.err}, nil)
		body, status, _ := doRequest(t, srv, "DELETE", "/api/v1/claude-accounts/personal", "")
		if status != tc.status {
			t.Errorf("%v -> status %d body=%s", tc.err, status, body)
		}
		if tc.code != "" {
			var env struct {
				Code string `json:"code"`
			}
			mustJSON(t, body, &env)
			if env.Code != tc.code {
				t.Errorf("%v -> code %q", tc.err, env.Code)
			}
		}
	}
}

func TestClaudeAccountsLoginOpensTerminal(t *testing.T) {
	svc := &fakeClaudeAccountService{}
	terms := &fakeLoginTerminals{}
	srv := newClaudeAccountsTestServer(t, svc, terms)
	body, status, _ := doRequest(t, srv, "POST", "/api/v1/claude-accounts/personal/login", `{"cols":120,"rows":40}`)
	if status != http.StatusCreated {
		t.Fatalf("status = %d body=%s", status, body)
	}
	if svc.loginInput != "personal" || terms.got.Argv[0] != "/usr/local/bin/claude" || terms.got.Env[domain.ClaudeConfigDirEnv] != "/Users/u/.claude-personal" || terms.got.Cols != 120 {
		t.Fatalf("login input = %q terminal input = %+v", svc.loginInput, terms.got)
	}
	var env controllers.ShellTerminalEnvelope
	mustJSON(t, body, &env)
	if env.ShellTerminal.HandleID != "shellterm-abc" {
		t.Fatalf("envelope = %+v", env)
	}
}
