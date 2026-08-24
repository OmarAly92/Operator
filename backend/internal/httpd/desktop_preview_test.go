package httpd

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
)

type fakeDesktopPreviewService struct {
	acked    map[domain.SessionID]int64
	failCode string
}

func newFakeDesktopPreviewService() *fakeDesktopPreviewService {
	return &fakeDesktopPreviewService{acked: map[domain.SessionID]int64{}}
}

func (f *fakeDesktopPreviewService) AckPreviewOpened(_ context.Context, id domain.SessionID, revision int64) error {
	switch f.failCode {
	case "not_found":
		return apierr.NotFound("SESSION_NOT_FOUND", "Unknown session")
	case "conflict":
		return apierr.Conflict("PREVIEW_ACK_REJECTED", "stale or future preview acknowledgement", nil)
	}
	f.acked[id] = revision
	return nil
}

func postPreviewOpened(t *testing.T, r http.Handler, sessionID string, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/internal/desktop/sessions/"+sessionID+"/preview-opened", strings.NewReader(body))
	req.Header.Set("Origin", "tauri://localhost")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

func TestDesktopPreviewOpenedAdvancesToCurrentRevision(t *testing.T) {
	svc := newFakeDesktopPreviewService()
	r := newTestRouterWithDesktopPreview(svc)
	rec := postPreviewOpened(t, r, "mer-1", `{"revision":7}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", rec.Code, rec.Body.String())
	}
	if got := svc.acked["mer-1"]; got != 7 {
		t.Fatalf("acked revision = %d, want 7", got)
	}
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload["sessionId"] != "mer-1" {
		t.Fatalf("sessionId = %v, want mer-1", payload["sessionId"])
	}
}

func TestDesktopPreviewOpenedIsIdempotent(t *testing.T) {
	svc := newFakeDesktopPreviewService()
	r := newTestRouterWithDesktopPreview(svc)
	for i := 0; i < 2; i++ {
		rec := postPreviewOpened(t, r, "mer-1", `{"revision":3}`)
		if rec.Code != http.StatusOK {
			t.Fatalf("repeat %d: status = %d, want 200: %s", i, rec.Code, rec.Body.String())
		}
	}
	if got := svc.acked["mer-1"]; got != 3 {
		t.Fatalf("acked revision = %d, want 3 recorded once at the current revision", got)
	}
}

func TestDesktopPreviewOpenedRejectsStaleAndFutureRevisions(t *testing.T) {
	svc := newFakeDesktopPreviewService()
	svc.failCode = "conflict"
	r := newTestRouterWithDesktopPreview(svc)
	for name, body := range map[string]string{
		"stale":  `{"revision":2}`,
		"future": `{"revision":9}`,
	} {
		rec := postPreviewOpened(t, r, "mer-1", body)
		if rec.Code != http.StatusConflict {
			t.Fatalf("%s: status = %d, want 409: %s", name, rec.Code, rec.Body.String())
		}
		var payload struct {
			Code string `json:"code"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
			t.Fatalf("%s: decode error envelope: %v", name, err)
		}
		if payload.Code != "PREVIEW_ACK_REJECTED" {
			t.Fatalf("%s: code = %q, want PREVIEW_ACK_REJECTED", name, payload.Code)
		}
	}
}

func TestDesktopPreviewOpenedUnknownSession(t *testing.T) {
	svc := newFakeDesktopPreviewService()
	svc.failCode = "not_found"
	r := newTestRouterWithDesktopPreview(svc)
	rec := postPreviewOpened(t, r, "ghost-1", `{"revision":1}`)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404: %s", rec.Code, rec.Body.String())
	}
}

func TestDesktopPreviewOpenedRejectsMissingRevision(t *testing.T) {
	svc := newFakeDesktopPreviewService()
	r := newTestRouterWithDesktopPreview(svc)
	rec := postPreviewOpened(t, r, "mer-1", `{}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400: %s", rec.Code, rec.Body.String())
	}
	if len(svc.acked) != 0 {
		t.Fatalf("service must not be called without a revision, got %v", svc.acked)
	}
}

func TestDesktopPreviewOpenedRejectsInvalidJSON(t *testing.T) {
	svc := newFakeDesktopPreviewService()
	r := newTestRouterWithDesktopPreview(svc)
	rec := postPreviewOpened(t, r, "mer-1", `{"revision":"seven"}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400: %s", rec.Code, rec.Body.String())
	}
}

func TestDesktopPreviewRouteAbsentOnLANListener(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		t.Fatal("LAN request reached the shared router for a desktop-only route")
	})
	m := NewMobileLAN(inner, 0, loggerOrDefault(nil), nil)
	port, err := m.Start(0)
	if err != nil {
		t.Fatalf("start LAN listener: %v", err)
	}
	defer func() { _ = m.Stop(context.Background()) }()

	req, _ := http.NewRequest(http.MethodPost, fmt.Sprintf("http://127.0.0.1:%d/internal/desktop/sessions/mer-1/preview-opened", port), strings.NewReader(`{"revision":1}`))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("lan request: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("lan status = %d, want 404", resp.StatusCode)
	}
}

func newTestRouterWithDesktopPreview(svc DesktopPreviewService) chi.Router {
	return NewRouterWithControl(config.Config{
		AllowedOrigins: config.DefaultAllowedOrigins,
	}, slog.Default(), nil, APIDeps{DesktopPreview: svc}, ControlDeps{})
}
