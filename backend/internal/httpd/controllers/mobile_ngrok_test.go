package controllers

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/tunnel"
)

func TestNgrokStatusRoute(t *testing.T) {
	c := &MobileController{Bridge: &fakeBridge{}}
	rec := httptest.NewRecorder()
	c.NgrokStatus(rec, httptest.NewRequest(http.MethodGet, "/api/v1/mobile/tunnel/ngrok", nil))
	if rec.Code != 200 {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	var body MobileNgrokStatus
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Logs == nil {
		t.Error("logs must be [] on the wire")
	}
}

func TestSetAPIKeyRouteMapsErrors(t *testing.T) {
	cases := []struct {
		body     string
		err      error
		wantCode int
		wantErr  string
	}{
		{`{"key":""}`, nil, 400, "MOBILE_NGROK_APIKEY_BODY"},
		{`not json`, nil, 400, "MOBILE_NGROK_APIKEY_BODY"},
		{`{"key":"k"}`, tunnel.ErrNgrokAPIUnauthorized, 401, "NGROK_API_UNAUTHORIZED"},
		{`{"key":"k"}`, errors.New("boom"), 502, "NGROK_API_ERROR"},
		{`{"key":"k"}`, nil, 200, ""},
	}
	for _, tc := range cases {
		b := &fakeBridge{apiKeyErr: tc.err}
		c := &MobileController{Bridge: b}
		rec := httptest.NewRecorder()
		c.SetNgrokAPIKey(rec, httptest.NewRequest(http.MethodPut, "/api/v1/mobile/tunnel/ngrok/api-key", strings.NewReader(tc.body)))
		if rec.Code != tc.wantCode {
			t.Errorf("%s: code %d want %d (%s)", tc.body, rec.Code, tc.wantCode, rec.Body)
		}
		if tc.wantErr != "" && !strings.Contains(rec.Body.String(), tc.wantErr) {
			t.Errorf("%s: body %s lacks %s", tc.body, rec.Body, tc.wantErr)
		}
	}
}

func TestRevokeCredentialRouteReadsThePathParam(t *testing.T) {
	b := &fakeBridge{}
	r := chi.NewRouter()
	r.Delete("/api/v1/mobile/tunnel/ngrok/account/credential/{id}", (&MobileController{Bridge: b}).RevokeNgrokCredential)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, httptest.NewRequest(http.MethodDelete, "/api/v1/mobile/tunnel/ngrok/account/credential/cr_1", nil))
	if rec.Code != 200 || b.revoked != "cr_1" {
		t.Fatalf("code %d revoked %q", rec.Code, b.revoked)
	}
}
