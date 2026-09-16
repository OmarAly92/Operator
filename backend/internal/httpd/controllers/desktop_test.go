package controllers

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestDesktopName(t *testing.T) {
	cases := map[string]string{
		"Omars-MacBook-Pro-9.local": "Omars MacBook Pro 9",
		"office-imac":               "office imac",
		"DESKTOP-ABC123":            "DESKTOP ABC123",
		"":                          "Desktop",
		".local":                    "Desktop",
	}
	for in, want := range cases {
		if got := DesktopName(in); got != want {
			t.Errorf("DesktopName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestDesktopControllerGet(t *testing.T) {
	c := &DesktopController{Hostname: func() (string, error) { return "Omars-MacBook-Pro-9.local", nil }}
	rec := httptest.NewRecorder()
	c.Get(rec, httptest.NewRequest(http.MethodGet, "/api/v1/desktop", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var body DesktopResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Name != "Omars MacBook Pro 9" || body.Hostname != "Omars-MacBook-Pro-9.local" {
		t.Fatalf("body = %+v", body)
	}
}

func TestDesktopControllerGetHostnameError(t *testing.T) {
	c := &DesktopController{Hostname: func() (string, error) { return "", errors.New("no hostname") }}
	rec := httptest.NewRecorder()
	c.Get(rec, httptest.NewRequest(http.MethodGet, "/api/v1/desktop", nil))

	var body DesktopResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if rec.Code != http.StatusOK || body.Name != "Desktop" || body.Hostname != "" {
		t.Fatalf("status %d body %+v", rec.Code, body)
	}
}
