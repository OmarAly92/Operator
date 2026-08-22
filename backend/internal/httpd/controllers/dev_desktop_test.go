package controllers_test

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/adapters/projectscan"
	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
)

type fakeDevScan struct {
	scanResult   projectscan.Result
	scanErr      error
	warning      string
	gotScanPath  string
	gotScanMode  projectscan.Mode
	gotAncesPath string
}

func (f *fakeDevScan) ScanFolder(_ context.Context, rootPath string, mode projectscan.Mode) (projectscan.Result, error) {
	f.gotScanPath = rootPath
	f.gotScanMode = mode
	return f.scanResult, f.scanErr
}

func (f *fakeDevScan) AncestorRepository(_ context.Context, rootPath string) string {
	f.gotAncesPath = rootPath
	return f.warning
}

func newDevDesktopServer(t *testing.T, svc controllers.DevScanService) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{DevScan: svc}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestDevImportScanReturnsScanResult(t *testing.T) {
	svc := &fakeDevScan{scanResult: projectscan.Result{
		Path: "/repos",
		Repos: []projectscan.Repo{{
			Name:         "app",
			Path:         "/repos/app",
			RelativePath: "app",
			Branch:       "main",
			Remote:       "https://example.com/app.git",
			HasRemote:    true,
			Status:       projectscan.StatusOK,
		}},
		SetupWarning: "Selected folder is inside an existing Git repository at /repos. Operator will initialize this folder as a separate repository.",
	}}
	srv := newDevDesktopServer(t, svc)

	body, status, headers := doRequest(t, srv, "POST", "/api/v1/dev/import-scan", `{"path":"/repos","mode":"workspace"}`)
	if status != http.StatusOK {
		t.Fatalf("POST import-scan = %d, want 200; body=%s", status, body)
	}
	assertJSON(t, headers)
	var resp projectscan.Result
	mustJSON(t, body, &resp)
	if resp.Path != "/repos" || resp.SetupWarning == "" || len(resp.Repos) != 1 {
		t.Fatalf("response = %+v", resp)
	}
	if resp.Repos[0].Name != "app" || resp.Repos[0].Status != projectscan.StatusOK || !resp.Repos[0].HasRemote {
		t.Fatalf("repo = %+v", resp.Repos[0])
	}
	if svc.gotScanPath != "/repos" || svc.gotScanMode != projectscan.ModeWorkspace {
		t.Fatalf("scanner received path=%q mode=%q", svc.gotScanPath, svc.gotScanMode)
	}
}

func TestDevImportScanValidatesInput(t *testing.T) {
	srv := newDevDesktopServer(t, &fakeDevScan{})

	cases := []struct {
		name string
		body string
	}{
		{"missing path", `{"mode":"workspace"}`},
		{"empty path", `{"path":"","mode":"workspace"}`},
		{"unknown mode", `{"path":"/repos","mode":"recursive"}`},
		{"missing mode", `{"path":"/repos"}`},
		{"malformed json", `{"path":`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, status, _ := doRequest(t, srv, "POST", "/api/v1/dev/import-scan", tc.body)
			if status != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400", status)
			}
		})
	}
}

func TestDevImportScanScannerErrorIsInternal(t *testing.T) {
	srv := newDevDesktopServer(t, &fakeDevScan{scanErr: errors.New("readdir failed")})
	_, status, _ := doRequest(t, srv, "POST", "/api/v1/dev/import-scan", `{"path":"/repos","mode":"workspace"}`)
	if status != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", status)
	}
}

func TestDevDesktopRoutesNotImplementedWithoutService(t *testing.T) {
	srv := newDevDesktopServer(t, nil)

	_, status, _ := doRequest(t, srv, "POST", "/api/v1/dev/import-scan", `{"path":"/repos","mode":"workspace"}`)
	if status != http.StatusNotImplemented {
		t.Fatalf("import-scan status = %d, want 501", status)
	}
	_, status, _ = doRequest(t, srv, "POST", "/api/v1/dev/ancestor-repository", `{"path":"/repos"}`)
	if status != http.StatusNotImplemented {
		t.Fatalf("ancestor-repository status = %d, want 501", status)
	}
}

func TestDevAncestorRepositoryReturnsWarning(t *testing.T) {
	svc := &fakeDevScan{warning: "Selected folder is inside an existing Git repository at /parent."}
	srv := newDevDesktopServer(t, svc)

	body, status, headers := doRequest(t, srv, "POST", "/api/v1/dev/ancestor-repository", `{"path":"/parent/inner"}`)
	if status != http.StatusOK {
		t.Fatalf("POST ancestor-repository = %d, want 200; body=%s", status, body)
	}
	assertJSON(t, headers)
	var resp controllers.DevAncestorRepositoryResponse
	mustJSON(t, body, &resp)
	if resp.SetupWarning != svc.warning {
		t.Fatalf("warning = %q, want %q", resp.SetupWarning, svc.warning)
	}
	if svc.gotAncesPath != "/parent/inner" {
		t.Fatalf("scanner received path=%q", svc.gotAncesPath)
	}
}

func TestDevAncestorRepositoryWithoutWarningOmitsField(t *testing.T) {
	srv := newDevDesktopServer(t, &fakeDevScan{})

	body, status, _ := doRequest(t, srv, "POST", "/api/v1/dev/ancestor-repository", `{"path":"/plain"}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	if strings.Contains(string(body), `"setupWarning"`) {
		t.Fatalf("body = %s, want setupWarning omitted", body)
	}
}

func TestDevAncestorRepositoryValidatesInput(t *testing.T) {
	srv := newDevDesktopServer(t, &fakeDevScan{})

	_, status, _ := doRequest(t, srv, "POST", "/api/v1/dev/ancestor-repository", `{}`)
	if status != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", status)
	}
}
