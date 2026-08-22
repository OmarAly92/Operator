package controllers

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/OmarAly92/operator/backend/internal/adapters/projectscan"
	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
)

// DevScanService is the controller-facing local folder-scan contract.
type DevScanService interface {
	ScanFolder(ctx context.Context, rootPath string, mode projectscan.Mode) (projectscan.Result, error)
	AncestorRepository(ctx context.Context, rootPath string) string
}

// DevImportScanRequest is the body of POST /api/v1/dev/import-scan.
type DevImportScanRequest struct {
	Path string `json:"path" minLength:"1"`
	Mode string `json:"mode" enum:"project,workspace"`
}

// DevAncestorRepositoryRequest is the body of POST /api/v1/dev/ancestor-repository.
type DevAncestorRepositoryRequest struct {
	Path string `json:"path" minLength:"1"`
}

// DevAncestorRepositoryResponse is the body of POST /api/v1/dev/ancestor-repository;
// setupWarning is omitted when the folder has no ancestor repository.
type DevAncestorRepositoryResponse struct {
	SetupWarning string `json:"setupWarning,omitempty"`
}

func (c *DevController) importScan(w http.ResponseWriter, r *http.Request) {
	if c.Scan == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/dev/import-scan")
		return
	}
	var req DevImportScanRequest
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "request body must be valid JSON", nil)
		return
	}
	if req.Path == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "validation", "SCAN_PATH_REQUIRED", "path is required", nil)
		return
	}
	mode := projectscan.Mode(req.Mode)
	switch mode {
	case projectscan.ModeProject, projectscan.ModeWorkspace:
	default:
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "validation", "SCAN_MODE_INVALID",
			`mode must be "project" or "workspace"`, nil)
		return
	}
	result, err := c.Scan.ScanFolder(r.Context(), req.Path, mode)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	if result.Repos == nil {
		result.Repos = []projectscan.Repo{}
	}
	envelope.WriteJSON(w, http.StatusOK, result)
}

func (c *DevController) ancestorRepository(w http.ResponseWriter, r *http.Request) {
	if c.Scan == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/dev/ancestor-repository")
		return
	}
	var req DevAncestorRepositoryRequest
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "request body must be valid JSON", nil)
		return
	}
	if req.Path == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "validation", "SCAN_PATH_REQUIRED", "path is required", nil)
		return
	}
	warning := c.Scan.AncestorRepository(r.Context(), req.Path)
	envelope.WriteJSON(w, http.StatusOK, DevAncestorRepositoryResponse{SetupWarning: warning})
}
