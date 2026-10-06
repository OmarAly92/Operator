package controllers_test

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	prsvc "github.com/OmarAly92/operator/backend/internal/service/pr"
)

type fakePRService struct {
	mergeResult    prsvc.MergeResult
	mergeErr       error
	mergeRequest   prsvc.MergeRequest
	resolveResult  prsvc.ResolveResult
	resolveErr     error
	resolveRequest prsvc.ResolveRequest
}

func (f *fakePRService) Merge(_ context.Context, request prsvc.MergeRequest) (prsvc.MergeResult, error) {
	f.mergeRequest = request
	return f.mergeResult, f.mergeErr
}

func (f *fakePRService) ResolveComments(_ context.Context, request prsvc.ResolveRequest) (prsvc.ResolveResult, error) {
	f.resolveRequest = request
	return f.resolveResult, f.resolveErr
}

func newPRTestServer(t *testing.T, svc prsvc.ActionManager) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{PRs: svc}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

const validMergeBody = `{"prUrl":"https://github.com/acme/widgets/pull/42","expectedHeadSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}`

// ---- Nil service → 503 SCM_NOT_CONFIGURED ----

func TestPRsRoutes_NilService_MergeReturns501(t *testing.T) {
	srv := newPRTestServer(t, nil)
	body, status, headers := doRequest(t, srv, "POST", "/api/v1/prs/1/merge", "")
	assertJSON(t, headers)
	assertErrorCode(t, body, status, http.StatusNotImplemented, "NOT_IMPLEMENTED")
}

func TestPRsRoutes_NilService_ResolveCommentsReturns501(t *testing.T) {
	srv := newPRTestServer(t, nil)
	body, status, headers := doRequest(t, srv, "POST", "/api/v1/prs/1/resolve-comments", "")
	assertJSON(t, headers)
	assertErrorCode(t, body, status, http.StatusNotImplemented, "NOT_IMPLEMENTED")
}

// ---- Merge: 200 ----

func TestPRsRoutes_Merge_200(t *testing.T) {
	svc := &fakePRService{mergeResult: prsvc.MergeResult{PRNumber: 42, Method: "squash"}}
	srv := newPRTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "POST", "/api/v1/prs/42/merge", validMergeBody)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	var resp struct {
		OK       bool   `json:"ok"`
		PRNumber int    `json:"prNumber"`
		Method   string `json:"method"`
	}
	mustJSON(t, body, &resp)
	if !resp.OK || resp.PRNumber != 42 || resp.Method != "squash" {
		t.Errorf("resp = %+v, want {ok:true prNumber:42 method:squash}", resp)
	}
	if svc.mergeRequest.PRID != "42" || svc.mergeRequest.PRURL != "https://github.com/acme/widgets/pull/42" || svc.mergeRequest.ExpectedHeadSHA != "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" {
		t.Fatalf("merge request = %#v", svc.mergeRequest)
	}
}

// ---- Merge: 404 ----

func TestPRsRoutes_Merge_404(t *testing.T) {
	svc := &fakePRService{mergeErr: prsvc.ErrPRNotFound}
	srv := newPRTestServer(t, svc)

	body, status, headers := doRequest(t, srv, "POST", "/api/v1/prs/99/merge", validMergeBody)
	assertJSON(t, headers)
	assertErrorCode(t, body, status, http.StatusNotFound, "PR_NOT_FOUND")
}

// ---- Merge: 409 ----

func TestPRsRoutes_Merge_409(t *testing.T) {
	svc := &fakePRService{mergeErr: prsvc.ErrPRNotMergeable}
	srv := newPRTestServer(t, svc)

	body, status, headers := doRequest(t, srv, "POST", "/api/v1/prs/1/merge", validMergeBody)
	assertJSON(t, headers)
	assertErrorCode(t, body, status, http.StatusConflict, "PR_NOT_MERGEABLE")
}

// ---- Merge: 422 ----

func TestPRsRoutes_Merge_422(t *testing.T) {
	svc := &fakePRService{mergeErr: prsvc.ErrPRPreconditions}
	srv := newPRTestServer(t, svc)

	body, status, headers := doRequest(t, srv, "POST", "/api/v1/prs/1/merge", validMergeBody)
	assertJSON(t, headers)
	assertErrorCode(t, body, status, http.StatusUnprocessableEntity, "PR_PRECONDITIONS_UNMET")
}

// ---- ResolveComments: 200 ----

func TestPRsRoutes_ResolveComments_200(t *testing.T) {
	svc := &fakePRService{resolveResult: prsvc.ResolveResult{Resolved: 3}}
	srv := newPRTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "POST", "/api/v1/prs/42/resolve-comments", `{"prUrl":"https://github.com/acme/widgets/pull/42","commentIds":["T_1","T_2","T_3"]}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	var resp struct {
		OK       bool `json:"ok"`
		Resolved int  `json:"resolved"`
	}
	mustJSON(t, body, &resp)
	if !resp.OK || resp.Resolved != 3 {
		t.Errorf("resp = %+v, want {ok:true resolved:3}", resp)
	}
	got := svc.resolveRequest
	if got.PRID != "42" || got.PRURL != "https://github.com/acme/widgets/pull/42" || len(got.CommentIDs) != 3 || got.CommentIDs[0] != "T_1" {
		t.Fatalf("resolve request = %#v", got)
	}
}

// A number alone is ambiguous across repositories, so the PR URL is required,
// the same contract as merge.
func TestPRsRoutes_ResolveComments_400_WithoutPRURL(t *testing.T) {
	svc := &fakePRService{resolveResult: prsvc.ResolveResult{Resolved: 2}}
	srv := newPRTestServer(t, svc)

	body, status, headers := doRequest(t, srv, "POST", "/api/v1/prs/42/resolve-comments", "")
	assertJSON(t, headers)
	assertErrorCode(t, body, status, http.StatusBadRequest, "INVALID_PR")
}

func TestPRsRoutes_ResolveComments_404_UnknownComments(t *testing.T) {
	svc := &fakePRService{resolveErr: prsvc.ErrCommentsNotFound}
	srv := newPRTestServer(t, svc)

	body, status, headers := doRequest(t, srv, "POST", "/api/v1/prs/42/resolve-comments", `{"prUrl":"https://github.com/acme/widgets/pull/42","commentIds":["C_9"]}`)
	assertJSON(t, headers)
	assertErrorCode(t, body, status, http.StatusNotFound, "COMMENTS_NOT_FOUND")
}

// ---- ResolveComments: 404 ----

func TestPRsRoutes_ResolveComments_404(t *testing.T) {
	svc := &fakePRService{resolveErr: prsvc.ErrPRNotFound}
	srv := newPRTestServer(t, svc)

	body, status, headers := doRequest(t, srv, "POST", "/api/v1/prs/99/resolve-comments", `{"prUrl":"https://github.com/acme/widgets/pull/99"}`)
	assertJSON(t, headers)
	assertErrorCode(t, body, status, http.StatusNotFound, "PR_NOT_FOUND")
}

// ---- ResolveComments: 422 ----

func TestPRsRoutes_ResolveComments_422(t *testing.T) {
	svc := &fakePRService{resolveErr: prsvc.ErrNothingToResolve}
	srv := newPRTestServer(t, svc)

	body, status, headers := doRequest(t, srv, "POST", "/api/v1/prs/1/resolve-comments", `{"prUrl":"https://github.com/acme/widgets/pull/1"}`)
	assertJSON(t, headers)
	assertErrorCode(t, body, status, http.StatusUnprocessableEntity, "NOTHING_TO_RESOLVE")
}
