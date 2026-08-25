package httpd

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/config"
)

func TestCORSPreviewOriginRequestsSkipTheBoundaryWithoutCORSGrants(t *testing.T) {
	deps := APIDeps{}
	router := NewRouterWithControl(config.Config{}, discardLogger(), nil, deps, ControlDeps{})
	srv := httptest.NewServer(router)
	defer srv.Close()

	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatalf("parse server url: %v", err)
	}
	previewHost := "opr-preview.mfxs2mi.localhost:" + u.Port()

	tests := []struct {
		name   string
		origin string
	}{
		{name: "own preview origin", origin: "http://" + previewHost},
		{name: "other session's preview origin", origin: "http://opr-preview.nfyws3tf.localhost:" + u.Port()},
		{name: "hostile origin", origin: "http://evil.example"},
	}

	client := &http.Client{}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req, err := http.NewRequest(http.MethodGet, srv.URL+"/theme.css", nil)
			if err != nil {
				t.Fatalf("NewRequest: %v", err)
			}
			req.Host = previewHost
			req.Header.Set("Origin", tt.origin)
			resp, err := client.Do(req)
			if err != nil {
				t.Fatalf("GET preview asset: %v", err)
			}
			defer resp.Body.Close()
			body, err := io.ReadAll(resp.Body)
			if err != nil {
				t.Fatalf("read body: %v", err)
			}

			if resp.StatusCode == http.StatusForbidden {
				t.Fatalf("status = %d, preview request must not be stopped at the origin boundary; body=%s", resp.StatusCode, body)
			}
			var envelopeBody struct {
				Error     string `json:"error"`
				Code      string `json:"code"`
				RequestID string `json:"requestId"`
			}
			if err := json.Unmarshal(body, &envelopeBody); err != nil {
				t.Fatalf("body is not the locked error envelope: %q", body)
			}
			if envelopeBody.Error != "not_found" || envelopeBody.Code != "PREVIEW_NOT_FOUND" || envelopeBody.RequestID == "" {
				t.Fatalf("envelope = %#v, want not_found/PREVIEW_NOT_FOUND with requestId", envelopeBody)
			}
			if got := resp.Header.Get("Access-Control-Allow-Origin"); got != "" {
				t.Errorf("Access-Control-Allow-Origin = %q, want none so cross-origin reads stay browser-blocked", got)
			}
		})
	}
}

// TestCORS exercises the allowlist boundary on a real router: trusted origins
// get per-origin CORS headers (REST reads and preflights), everything else —
// including the opaque "null" origin and no-Origin CLI traffic — gets none.
func TestCORS(t *testing.T) {
	cfg := config.Config{AllowedOrigins: config.DefaultAllowedOrigins}
	router := newTestRouter(cfg, discardLogger(), nil)
	srv := httptest.NewServer(router)
	defer srv.Close()

	tests := []struct {
		name       string
		method     string
		headers    map[string]string
		wantStatus int
		wantACAO   string
	}{
		{
			name:       "removed Electron origin is rejected",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "app://renderer"},
			wantStatus: http.StatusForbidden,
			wantACAO:   "",
		},
		{
			name:       "packaged Tauri origin gets ACAO",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "tauri://localhost"},
			wantStatus: http.StatusOK,
			wantACAO:   "tauri://localhost",
		},
		{
			name:       "Windows packaged Tauri origin gets ACAO",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "http://tauri.localhost"},
			wantStatus: http.StatusOK,
			wantACAO:   "http://tauri.localhost",
		},
		{
			name:       "unlisted loopback origin rejected",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "http://localhost:5181"},
			wantStatus: http.StatusForbidden,
			wantACAO:   "",
		},
		{
			name:       "unlisted loopback IP origin rejected",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "http://127.0.0.1:8080"},
			wantStatus: http.StatusForbidden,
			wantACAO:   "",
		},
		{
			name:       "unlisted localhost subdomain rejected",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "http://opr-preview.mfxs2mi.localhost:5181"},
			wantStatus: http.StatusForbidden,
			wantACAO:   "",
		},
		{
			// localhost in the host position of a non-loopback origin must not
			// fool the predicate.
			name:       "lookalike origin rejected",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "http://localhost.evil.example"},
			wantStatus: http.StatusForbidden,
			wantACAO:   "",
		},
		{
			// Rejected outright, not just denied CORS headers: a missing ACAO
			// hides the response but a "simple" cross-origin POST would still
			// execute the handler on this no-auth daemon.
			name:       "unknown origin is rejected before handlers",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "http://evil.example"},
			wantStatus: http.StatusForbidden,
			wantACAO:   "",
		},
		{
			name:       "localhost suffix lookalike rejected",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "http://opr-preview.localhost.evil.example"},
			wantStatus: http.StatusForbidden,
			wantACAO:   "",
		},
		{
			name:       "Windows Tauri lookalike rejected",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "http://tauri.localhost.evil.example"},
			wantStatus: http.StatusForbidden,
			wantACAO:   "",
		},
		{
			name:       "HTTPS Windows Tauri origin rejected",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "https://tauri.localhost"},
			wantStatus: http.StatusForbidden,
			wantACAO:   "",
		},
		{
			name:       "Tauri host lookalike rejected",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "tauri://evil.example"},
			wantStatus: http.StatusForbidden,
			wantACAO:   "",
		},
		{
			name:       "null origin is rejected",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "null"},
			wantStatus: http.StatusForbidden,
			wantACAO:   "",
		},
		{
			name:       "wildcard origin is rejected",
			method:     http.MethodGet,
			headers:    map[string]string{"Origin": "*"},
			wantStatus: http.StatusForbidden,
			wantACAO:   "",
		},
		{
			name:       "no origin passes through untouched",
			method:     http.MethodGet,
			headers:    nil,
			wantStatus: http.StatusOK,
			wantACAO:   "",
		},
		{
			name:   "preflight from allowed origin",
			method: http.MethodOptions,
			headers: map[string]string{
				"Origin":                         "tauri://localhost",
				"Access-Control-Request-Method":  "POST",
				"Access-Control-Request-Headers": "content-type",
			},
			wantStatus: http.StatusNoContent,
			wantACAO:   "tauri://localhost",
		},
		{
			name:   "preflight from unknown origin is rejected",
			method: http.MethodOptions,
			headers: map[string]string{
				"Origin":                        "http://evil.example",
				"Access-Control-Request-Method": "POST",
			},
			wantStatus: http.StatusForbidden,
			wantACAO:   "",
		},
	}

	client := &http.Client{}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req, err := http.NewRequest(tt.method, srv.URL+"/healthz", nil)
			if err != nil {
				t.Fatalf("NewRequest: %v", err)
			}
			for k, v := range tt.headers {
				req.Header.Set(k, v)
			}
			resp, err := client.Do(req)
			if err != nil {
				t.Fatalf("%s /healthz: %v", tt.method, err)
			}
			defer resp.Body.Close()

			if resp.StatusCode != tt.wantStatus {
				t.Errorf("status = %d, want %d", resp.StatusCode, tt.wantStatus)
			}
			if got := resp.Header.Get("Access-Control-Allow-Origin"); got != tt.wantACAO {
				t.Errorf("Access-Control-Allow-Origin = %q, want %q", got, tt.wantACAO)
			}
			if tt.headers["Origin"] != "" && resp.Header.Get("Vary") == "" {
				t.Error("Vary header missing for request with Origin")
			}
		})
	}
}

func TestCORSAllowsOnlyExactSafeConfiguredOrigins(t *testing.T) {
	cfg := config.Config{AllowedOrigins: []string{
		"app://renderer",
		"http://localhost:5181",
		"http://evil.example",
		"https://operator.example",
	}}
	router := newTestRouter(cfg, discardLogger(), nil)
	srv := httptest.NewServer(router)
	defer srv.Close()

	for _, tt := range []struct {
		origin     string
		wantStatus int
	}{
		{origin: "http://localhost:5181", wantStatus: http.StatusOK},
		{origin: "app://renderer", wantStatus: http.StatusForbidden},
		{origin: "http://localhost:5182", wantStatus: http.StatusForbidden},
		{origin: "http://evil.example", wantStatus: http.StatusForbidden},
		{origin: "https://operator.example", wantStatus: http.StatusForbidden},
	} {
		req, err := http.NewRequest(http.MethodGet, srv.URL+"/healthz", nil)
		if err != nil {
			t.Fatalf("NewRequest: %v", err)
		}
		req.Header.Set("Origin", tt.origin)
		resp, err := (&http.Client{}).Do(req)
		if err != nil {
			t.Fatalf("GET /healthz: %v", err)
		}
		resp.Body.Close()
		if resp.StatusCode != tt.wantStatus {
			t.Errorf("origin %q status = %d, want %d", tt.origin, resp.StatusCode, tt.wantStatus)
		}
	}
}

// TestCORSPreflightHeaders pins the preflight grant shape: methods, echoed
// request headers, max-age, and the private-network opt-in.
func TestCORSPreflightHeaders(t *testing.T) {
	cfg := config.Config{AllowedOrigins: []string{"tauri://localhost"}}
	router := newTestRouter(cfg, discardLogger(), nil)
	srv := httptest.NewServer(router)
	defer srv.Close()

	req, err := http.NewRequest(http.MethodOptions, srv.URL+"/api/v1/sessions", nil)
	if err != nil {
		t.Fatalf("NewRequest: %v", err)
	}
	req.Header.Set("Origin", "tauri://localhost")
	req.Header.Set("Access-Control-Request-Method", "POST")
	req.Header.Set("Access-Control-Request-Headers", "content-type")
	req.Header.Set("Access-Control-Request-Private-Network", "true")

	resp, err := (&http.Client{}).Do(req)
	if err != nil {
		t.Fatalf("OPTIONS: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", resp.StatusCode)
	}
	for header, want := range map[string]string{
		"Access-Control-Allow-Origin":          "tauri://localhost",
		"Access-Control-Allow-Methods":         "GET, POST, PATCH, PUT, DELETE, OPTIONS",
		"Access-Control-Allow-Headers":         "content-type",
		"Access-Control-Max-Age":               "600",
		"Access-Control-Allow-Private-Network": "true",
	} {
		if got := resp.Header.Get(header); got != want {
			t.Errorf("%s = %q, want %q", header, got, want)
		}
	}
}
