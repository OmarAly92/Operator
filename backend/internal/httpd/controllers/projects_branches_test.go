package controllers_test

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	projectsvc "github.com/OmarAly92/operator/backend/internal/service/project"
)

type branchesManager struct {
	projectsvc.Manager
	got domain.ProjectID
	out projectsvc.Branches
	err error
}

func (m *branchesManager) Branches(_ context.Context, id domain.ProjectID) (projectsvc.Branches, error) {
	m.got = id
	return m.out, m.err
}

func branchesServer(t *testing.T, mgr projectsvc.Manager) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{Projects: mgr}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestProjectsAPI_BranchesReturnsTheListing(t *testing.T) {
	mgr := &branchesManager{out: projectsvc.Branches{
		Current: "logic/home",
		Branches: []projectsvc.Branch{
			{Name: "logic/home", CheckedOutAt: "/repo", IsMainCheckout: true},
			{Name: "main"},
		},
	}}
	body, status, headers := doRequest(t, branchesServer(t, mgr), "GET", "/api/v1/projects/rafeeq/branches", "")
	assertJSON(t, headers)
	if status != http.StatusOK {
		t.Fatalf("status = %d\nbody=%s", status, body)
	}
	if mgr.got != "rafeeq" {
		t.Fatalf("project id = %q, want rafeeq", mgr.got)
	}
	var got struct {
		Current  string           `json:"current"`
		Branches []map[string]any `json:"branches"`
	}
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatal(err)
	}
	if got.Current != "logic/home" || len(got.Branches) != 2 {
		t.Fatalf("body = %s", body)
	}
	if got.Branches[0]["checkedOutAt"] != "/repo" || got.Branches[0]["isMainCheckout"] != true {
		t.Fatalf("first branch = %#v", got.Branches[0])
	}
	if _, present := got.Branches[1]["checkedOutAt"]; present {
		t.Fatalf("a free branch must omit checkedOutAt, got %#v", got.Branches[1])
	}
}

func TestProjectsAPI_BranchesSurfacesServiceErrors(t *testing.T) {
	cases := []struct {
		err    error
		status int
		code   string
	}{
		{apierr.Invalid("BRANCHES_UNSUPPORTED_PROJECT_KIND", "no", nil), http.StatusBadRequest, "BRANCHES_UNSUPPORTED_PROJECT_KIND"},
		{apierr.NotFound("PROJECT_NOT_FOUND", "Unknown project"), http.StatusNotFound, "PROJECT_NOT_FOUND"},
	}
	for _, tc := range cases {
		body, status, _ := doRequest(t, branchesServer(t, &branchesManager{err: tc.err}), "GET", "/api/v1/projects/p/branches", "")
		assertErrorCode(t, body, status, tc.status, tc.code)
		var envelope struct {
			RequestID string `json:"requestId"`
		}
		if err := json.Unmarshal(body, &envelope); err != nil || envelope.RequestID == "" {
			t.Fatalf("want requestId kept in the error envelope, body=%s", body)
		}
	}
}

func TestProjectsAPI_BranchesIsNotImplementedWithoutAManager(t *testing.T) {
	body, status, _ := doRequest(t, branchesServer(t, nil), "GET", "/api/v1/projects/p/branches", "")
	if status != http.StatusNotImplemented {
		t.Fatalf("status = %d, want 501\nbody=%s", status, body)
	}
}
