package controllers

import (
	"context"
	"encoding/json"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/devimport"
	"github.com/OmarAly92/operator/backend/internal/httpd/apispec"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
	devimportsvc "github.com/OmarAly92/operator/backend/internal/service/devimport"
)

// DevImportService is the controller-facing developer import service contract.
type DevImportService interface {
	RunProjects(ctx context.Context, in devimportsvc.RunInput) (devimport.Report, error)
}

// DevBlockReplayer is the controller-facing synthetic block-source contract.
// The replay drives ActivitySignals through the real blockevent Service.Record
// path so a long session can be reproduced and a load profile can be exercised
// against production code, not a test-only shortcut.
type DevBlockReplayer interface {
	Run(ctx context.Context, in blockeventsvc.ReplayInput) error
}

// DevController owns developer-only API routes.
type DevController struct {
	Import DevImportService
	Scan   DevScanService
	Replay DevBlockReplayer
}

// devBlockReplayEnvVar gates the synthetic block-source route. The handler
// is inert unless the daemon's environment carries this variable set to "1";
// without it the route answers 501 the same way the other dev routes answer
// 501 when their backing service is unwired. This guards a route that writes
// into a real session's block log against accidental shipping in a build
// that did not opt into it.
const devBlockReplayEnvVar = "OPERATOR_DEV_BLOCK_REPLAY"

// Register mounts developer REST routes on the supplied router.
func (c *DevController) Register(r chi.Router) {
	r.Post("/dev/import-projects", c.importProjects)
	r.Post("/dev/import-scan", c.importScan)
	r.Post("/dev/ancestor-repository", c.ancestorRepository)
	r.Post("/dev/block-replay", c.blockReplay)
}

func (c *DevController) importProjects(w http.ResponseWriter, r *http.Request) {
	if c.Import == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/dev/import-projects")
		return
	}
	var req DevImportProjectsRequest
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "request body must be valid JSON", nil)
		return
	}
	if req.SourceDataDir == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "SOURCE_DATA_DIR_REQUIRED", "sourceDataDir is required", nil)
		return
	}
	rep, err := c.Import.RunProjects(r.Context(), devimportsvc.RunInput{
		SourceDataDir: req.SourceDataDir,
		DryRun:        req.DryRun,
	})
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, DevImportProjectsResponse{Report: rep})
}

// blockReplay drives a synthetic block-event stream through the real Record
// path. Guarded by OPERATOR_DEV_BLOCK_REPLAY=1 in the daemon's environment;
// without that env var the route answers 501 the same way the other dev
// routes answer 501 when their backing service is unwired. When enabled, the
// replay runs on its own goroutine and the request returns 202 immediately.
func (c *DevController) blockReplay(w http.ResponseWriter, r *http.Request) {
	if os.Getenv(devBlockReplayEnvVar) != "1" {
		apispec.NotImplemented(w, r, "POST", "/api/v1/dev/block-replay")
		return
	}
	if c.Replay == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/dev/block-replay")
		return
	}
	var req DevBlockReplayRequest
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "request body must be valid JSON", nil)
		return
	}
	if req.SessionID == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "validation", "SESSION_ID_REQUIRED", "sessionId is required", nil)
		return
	}
	if req.Harness == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "validation", "HARNESS_REQUIRED", "harness is required", nil)
		return
	}
	if req.Events <= 0 {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "validation", "EVENTS_REQUIRED", "events must be positive", nil)
		return
	}
	runCtx := context.Background()
	go func() {
		_ = c.Replay.Run(runCtx, blockeventsvc.ReplayInput{
			SessionID:     req.SessionID,
			Harness:       req.Harness,
			Events:        req.Events,
			RatePerSecond: req.RatePerSecond,
		})
	}()
	envelope.WriteJSON(w, http.StatusAccepted, DevBlockReplayResponse{OK: true})
}
