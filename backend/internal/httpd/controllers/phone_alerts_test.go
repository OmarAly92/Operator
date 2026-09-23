package controllers_test

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/httpd"
	"github.com/OmarAly92/operator/backend/internal/push"
)

type fakePhoneAlerts struct {
	status   push.Status
	topic    string
	claimErr error
	delivery push.Delivery
}

func (f *fakePhoneAlerts) Status() push.Status { return f.status }
func (f *fakePhoneAlerts) Claim() (string, string, error) {
	return f.topic, push.DefaultNtfyServer, f.claimErr
}
func (f *fakePhoneAlerts) Test(context.Context) push.Delivery { return f.delivery }

func phoneAlertsServer(t *testing.T, svc *fakePhoneAlerts) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{PhoneAlerts: svc}, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestPhoneAlertsStatus(t *testing.T) {
	srv := phoneAlertsServer(t, &fakePhoneAlerts{status: push.Status{Enabled: true}})
	res, err := http.Get(srv.URL + "/api/v1/phone-alerts")
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var body map[string]any
	_ = json.NewDecoder(res.Body).Decode(&body)
	if res.StatusCode != http.StatusOK || body["enabled"] != true || body["claimed"] != false {
		t.Fatalf("status=%d body=%v", res.StatusCode, body)
	}
}

func TestPhoneAlertsSubscribe(t *testing.T) {
	srv := phoneAlertsServer(t, &fakePhoneAlerts{topic: "abc"})
	res, err := http.Post(srv.URL+"/api/v1/phone-alerts/subscribe", "application/json", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var body map[string]any
	_ = json.NewDecoder(res.Body).Decode(&body)
	if res.StatusCode != http.StatusOK || body["topic"] != "abc" || body["server"] != push.DefaultNtfyServer {
		t.Fatalf("status=%d body=%v", res.StatusCode, body)
	}
}

func TestPhoneAlertsSubscribeWithoutConnectMobile(t *testing.T) {
	srv := phoneAlertsServer(t, &fakePhoneAlerts{claimErr: push.ErrAlertsUnavailable})
	res, err := http.Post(srv.URL+"/api/v1/phone-alerts/subscribe", "application/json", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var body map[string]any
	_ = json.NewDecoder(res.Body).Decode(&body)
	if res.StatusCode != http.StatusConflict || body["code"] != "PHONE_ALERTS_UNAVAILABLE" {
		t.Fatalf("status=%d body=%v", res.StatusCode, body)
	}
}

func TestPhoneAlertsTest(t *testing.T) {
	at := time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC)
	srv := phoneAlertsServer(t, &fakePhoneAlerts{delivery: push.Delivery{At: at, OK: false, Error: "ntfy answered 429"}})
	res, err := http.Post(srv.URL+"/api/v1/phone-alerts/test", "application/json", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var body map[string]any
	_ = json.NewDecoder(res.Body).Decode(&body)
	if body["ok"] != false || body["error"] != "ntfy answered 429" {
		t.Fatalf("body=%v", body)
	}
}
